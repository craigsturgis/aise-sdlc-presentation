---
name: iterative-review
description: Run a local iterative code review that mirrors the GitHub Action reviewer. Review -> fix -> re-review until convergence, so the GH Action finds little to nothing on push.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
model: opus
---

# Local Iterative Code Review

Run a local code review that uses the **same focus areas** as the GitHub Action Claude Code Review, then fix findings and re-review until convergence. This replaces the push-and-wait-for-GH-Action cycle with a fast local loop.

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` may carry either of two shapes:

1. **Scope hints or mode overrides** — free-form text like "only review the API changes" or "focus on the new DB migration". Treat as a soft filter the specialists should respect while still flagging anything dangerous they spot.

2. **PR-reviewer focus context** (used when invoked from `/prfeedback`) — a structured summary of findings the GH Action reviewer or human reviewers already flagged, plus a list of items already triaged as "skipping". When detected (common markers: "PR feedback", "prior reviewer findings", "already triaged as skipped"), thread the relevant portions into each specialist's prompt as an additional **"Reviewer-flagged focus areas"** section so specialists prioritize those file:line anchors first. **Do NOT use this context as a suppression list** — specialists must still surface unrelated findings. The "already skipped" list, however, should be added to each specialist's skip-list injection so they don't re-raise items the user already justified skipping.

When in doubt about which shape the input takes, treat it as scope hints and pass it through verbatim.

## Phase 1: Gather the Diff

1. **Determine the base branch** (default: `origin/dev`):
   ```bash
   BASE_BRANCH="${BASE:-origin/dev}"
   git fetch origin dev 2>/dev/null || true
   MERGE_BASE=$(git merge-base HEAD ${BASE_BRANCH})
   ```

2. **Get the full diff**:
   ```bash
   git diff ${MERGE_BASE}..HEAD
   ```

3. **Get the list of changed files** for targeted reading:
   ```bash
   git diff --name-only ${MERGE_BASE}..HEAD
   ```

4. **If the diff is empty**, report "nothing to review" and exit.

## Phase 2: Iterative Review Loop

Run up to **4 review iterations**. Each iteration spawns **four parallel subagents** — a generalist review plus three narrow specialists (scale, silent-failure, security & API-surface) that target the failure modes the GH Action reviewer has historically caught when local review missed them. The loop exits early if all four passes produce no new actionable findings.

**Why four agents, not one:** the generalist checklist is broad, and specialist concerns (scale/N+1, silent-failure semantics, security/authz/IDOR) routinely get lost in the breadth. Giving each specialist one narrow job in a fresh context produces sharper findings at the cost of 3 extra subagent spawns per iteration. They run in parallel so wall time is roughly unchanged.

### For each iteration (1 to 4):

#### Step A: Spawn Review Agents in Parallel

Spawn all four agents in a single message (parallel `Agent` tool calls) so they run concurrently. Each gets a fresh `code-review-architect` subagent with the prompt below.

**Thread reviewer-flagged context (if present in `$ARGUMENTS`).** When the user input contains PR-reviewer focus context (see the User Input section above), append a section to each specialist's prompt:

> **Reviewer-flagged focus areas** (from a prior PR review round — prioritize these but do not suppress unrelated findings):
> - [file:line] <what was flagged>
> - ...

Scope the additions to each specialist's lane — e.g., don't attach a security-category finding to the scale specialist. If a flagged item doesn't fit any specialist cleanly, attach it to the generalist. Do not paste raw review bodies; distill to file:line + one-line summaries.

##### Agent 1 — Generalist Review

Use the **Agent tool** with `subagent_type: "code-review-architect"` and the following prompt. This prompt mirrors the GitHub Action's `claude-code-review.yml` prompt so both reviewers look for the same things:

> Review the diff of this branch against the base branch. To get the diff, run: `git diff $(git merge-base HEAD <BASE_BRANCH>)..HEAD` where `<BASE_BRANCH>` is the base computed in Phase 1 (defaults to `origin/dev`). The codebase is a pnpm monorepo with Next.js 15, TypeScript, Fastify, Drizzle ORM, and AWS infrastructure.
>
> A local self-review has already covered: unused imports/variables, dead code, minor style/formatting, missing test files for new modules, and generic type safety. **Deprioritize** those unless egregious.
>
> **Focus your review on these categories** (ordered by impact):
>
> **1. Bugs & Correctness (always flag)**
> - Subtle business logic bugs requiring domain understanding (OAuth token rotation, API rate-limit vs quota, DynamoDB eventual consistency)
> - Date/time calculation errors (timezone handling, date range boundaries, partial-day aggregation)
> - Error classifications that don't match actual external API behavior
> - `??` vs `||` misuse on numeric/string fallbacks
> - Truthy checks on arrays/objects (`[]` and `{}` are truthy)
> - Null checks after create/find operations
> - Field access on wrong nested object
>
> **2. Security (always flag)**
> - Authentication/authorization gaps
> - Data exposure — response leaking sensitive fields
> - PII in logs at info level or above
> - Credentials in URL query params instead of POST body/headers
> - Missing input validation at API boundaries
>
> **3. Cross-Module & Integration Impact**
> - Will this break existing consumers (API routes, Redux selectors, hooks)?
> - PG migration flag considerations (pgOnly, write-through, flag evaluation)
> - DynamoDB-to-PostgreSQL migration patterns (write-through, legacyId fallback, enrichment parity)
> - Field mappings between services staying in sync
>
> **4. Architecture & Design**
> - Better abstraction or location for this code?
> - Pattern that will cause problems at scale?
> - Cross-cutting concerns (caching, retry, error propagation) affecting other modules
>
> **5. Error Handling**
> - Silent error swallowing (empty catch, catch-and-ignore)
> - Error messages missing context (which operation, what input)
> - `console.error`/`console.warn` instead of `logger.error`/`logger.warn`
> - Caching error responses (transient failures cached permanently)
>
> **6. Test Coverage Gaps**
> - New behavior paths without corresponding tests
> - Error/edge-case paths without test coverage
> - Tests with weak assertions (`toBeDefined` instead of checking actual values)
>
> **7. Edge Cases**
> - Empty/null/undefined inputs not handled
> - Pagination boundaries (missing cursor, empty-string tokens)
> - Empty-string vs null semantics with `??` vs `||`
>
> Reference CLAUDE.md for project conventions. Be concise and specific — only flag issues worth fixing. For each finding, include:
> - **File and line reference** (file:line format)
> - **Category** (from the list above)
> - **Severity** (must-fix, should-fix, consider)
> - **What's wrong and how to fix it**
>
> **Read one hop deep:** for any helper or utility the diff calls (e.g. `resolveEntityId`, `fetchAndDispatchConnections`), open the file and read the implementation before accepting claims about what it does. "Batched" helpers that internally loop with `await` are the #1 missed finding. Do not reason from the function name alone.
>
> **Trace useEffect chains explicitly:** for any new/changed `useEffect` or dispatch sequence, write out the expected firing order step-by-step (which deps change, which effects re-fire, which refs are set/cleared when). Effect-ordering bugs (stale refs, re-fires after awaited dispatches) are invisible from reading the diff linearly.
>
> If you find NO issues, explicitly state "No issues found" so the loop can terminate.
>
> IMPORTANT: This is one pass of a multi-iteration local review loop. Focus only on NEW issues not already addressed — do not re-flag things fixed in earlier passes.
>
> For iterations 2+, append: "The following findings were intentionally skipped in prior iterations — do NOT re-flag them: [list of skipped items with brief descriptions]." This prevents the loop from re-surfacing out-of-scope items and allows convergence even when some findings are skipped.

##### Agent 2 — Scale & N+1 Pass

Use the **Agent tool** with `subagent_type: "code-review-architect"` and the following prompt:

> You are a specialist reviewer with one job: find scale/performance footguns in the diff of this branch against the base branch. Get the diff with: `git diff $(git merge-base HEAD <BASE_BRANCH>)..HEAD` where `<BASE_BRANCH>` is the base computed in Phase 1 (defaults to `origin/dev`).
>
> Ignore style, tests, architecture, and general correctness — other reviewers handle those. Flag ONLY these patterns:
>
> **1. Hidden N+1 inside "batch" / "bulk" code paths**
> - `Promise.all(xs.map(...))` is parallel fan-out, not automatically N+1. The risk is **per-item query count inside the awaited helper**. For any helper called inside `Promise.all(...).map` (or `for..of` with `await`), **open the helper and count queries per invocation**. If the helper issues multiple queries (e.g. `resolveEntityId` does 2 sequential SELECTs), multiply by the outer fan-out and report the worst-case query count for N=100.
> - Do not flag correct parallel batching where each invocation is O(1) queries against a well-indexed column — that's fine.
> - Endpoints named `listByChannel`, `getBulk`, `batchX` are especially suspect — "batch" in the name does not mean the internals batch.
>
> **2. Hardcoded limits without pagination loops**
> - `limit: 100`, `limit: 1000`, `MAX_LIMIT`, etc. passed to list/fetch calls with no `while (hasMore)` or cursor loop around it.
> - Flag as silent truncation risk — state which caller will hit the ceiling first (e.g. "any creator with >100 connections").
>
> **3. Sequential awaits in hot paths**
> - `for` / `for..of` loops with `await` inside, on request-handling code paths.
> - `await` chains that could be `Promise.all`.
>
> **4. Resolver / lookup steps added before the real query**
> - FK-resolution, legacy-id fallback, or permission-check code added per-item before a list query. State whether the resolver is batchable and cite the existing batch helper if one exists (e.g. `resolveEntityIds` in `fk-resolution.ts`).
>
> For each finding:
> - **File:line** of the problematic call site
> - **Helper(s) you opened** and query count per invocation (e.g. "resolveEntityId = 2 queries; called in Promise.all over N channels → 2N queries")
> - **Worst-case at N=100** (or realistic N for the use case)
> - **Suggested fix** (usually: batch helper, or single `WHERE id = ANY($ids)` query)
>
> If no scale issues exist, state "No scale issues found". Do NOT flag generalist issues — stay in your lane.
>
> For iterations 2+, append: "The following scale findings were intentionally skipped in prior iterations — do NOT re-flag them: [list of skipped items with brief descriptions]." This prevents the loop from re-surfacing out-of-scope items so the loop can converge.

##### Agent 3 — Silent Failure & Control-Flow Pass

Use the **Agent tool** with `subagent_type: "code-review-architect"` and the following prompt:

> You are a specialist reviewer with one job: find silent failures, unreachable fallbacks, and control-flow semantics that subtly change behavior. Get the diff with: `git diff $(git merge-base HEAD <BASE_BRANCH>)..HEAD` where `<BASE_BRANCH>` is the base computed in Phase 1 (defaults to `origin/dev`).
>
> Ignore style, tests, architecture, and general correctness — other reviewers handle those. Flag ONLY these patterns:
>
> **1. Nested catches making outer handlers unreachable**
> - Any new inner `try { ... } catch { ... }` that swallows an error the outer `catch` was designed to handle. Read the surrounding function and confirm whether the outer logger/alert is now unreachable.
> - Any `catch {}` (no binding) or `catch (e) { /* empty */ }` — state what signal is lost.
>
> **2. Graceful-degradation that silently changes query semantics**
> - Fallbacks that return the input unchanged when a lookup fails (e.g. `resolveEntityIdForFilter` returning raw DDB UUID when not found). Trace the downstream use: does the query now become `ne(column, <never-matches>)` which is always true? Does a filter become a no-op? Does an "exclude" include everything?
> - Null-coalescing / `?? defaultValue` on IDs, filters, or auth claims — what does the default value mean downstream?
>
> **3. Conditional spreads or partial updates that erase state**
> - `{ ...obj, field: value ?? null }` where `value === undefined` — erases existing DB value silently. Flag.
> - Conditional spreads that differ from the pre-change behavior.
>
> **4. Early returns or guard clauses that skip cleanup**
> - New `if (!x) return` before a block that previously ran cleanup, unsubscribe, or state reset.
>
> **5. Cache writes on error paths**
> - Any code that caches a result inside an error branch or without checking for error — permanent suppression of correct behavior on transient failure.
>
> **Read one hop deep:** for any helper invoked in a fallback, catch, or graceful-degradation path, open and read the implementation before concluding the caller's semantics. Silent-failure bugs hide in the called helper as often as in the call site — e.g., `resolveEntityIdForFilter` looks innocent at the call site but silently returns the input unchanged when the lookup misses, which is exactly what makes the downstream filter a no-op.
>
> For each finding:
> - **File:line** of the changed code
> - **What was supposed to happen** (read the outer function / original intent)
> - **What now actually happens** (trace the semantics)
> - **What signal is lost** (log line, alert, filter behavior, cache correctness)
> - **Suggested fix**
>
> If no silent-failure issues exist, state "No silent-failure issues found". Do NOT flag generalist issues — stay in your lane.
>
> For iterations 2+, append: "The following silent-failure findings were intentionally skipped in prior iterations — do NOT re-flag them: [list of skipped items with brief descriptions]." This prevents the loop from re-surfacing out-of-scope items so the loop can converge.

##### Agent 4 — Security & API-Surface Pass

Use the **Agent tool** with `subagent_type: "code-review-architect"` and the following prompt:

> You are a specialist reviewer with one job: find security and API-surface discipline gaps in the diff of this branch against the base branch. Get the diff with: `git diff $(git merge-base HEAD <BASE_BRANCH>)..HEAD` where `<BASE_BRANCH>` is the base computed in Phase 1 (defaults to `origin/dev`).
>
> Ignore style, tests, architecture, and general correctness — other reviewers handle those. Flag ONLY these patterns on new or modified routes/handlers:
>
> **1. Missing auth hook on API routes**
> - Any new `web/pages/api/**` or `services/rootnote-api/src/routes/**` handler that doesn't run the session/auth check. Grep for the auth-hook pattern used elsewhere in the same directory and flag if absent.
>
> **2. Missing input validation**
> - UUID path params not validated before use (no `isUuid`/schema check).
> - Enum body fields not checked for membership.
> - Free-text fields used in DB queries without length/shape bounds.
>
> **3. Authorization vs business-state ordering**
> - Any handler that checks "is the resource in state X?" (already accepted, already revoked, already member) BEFORE checking "can the authenticated actor act on this resource?" Differential error responses leak state info.
>
> **4. Cross-creator / cross-tenant IDOR**
> - Request references a `creatorId`, `channelId`, `workspaceId`, `organizationId` from the body/params, and the handler uses it without confirming the authenticated actor owns or is a member of that resource. This is BOLA/IDOR — always flag.
>
> **5. Fail-open on auth/ownership errors**
> - `try { authCheck() } catch { /* fall through */ }` or ownership lookups that proceed to business logic on error. Auth/ownership failures must reject.
>
> **6. Wrong HTTP codes**
> - PG constraint/uniqueness violations → should be 409, not 500.
> - Soft-deleted or missing resources → should be 404/410, not 500.
> - Already-in-requested-state → should be 409, not 200 or 500.
> - Unauthenticated → 401. Unauthorized (authenticated but wrong actor) → 403. Confusing these leaks info.
>
> **7. Raw-error leakage to clients**
> - Raw PG error messages, Drizzle stack traces, S3 keys/paths, papaparse error text surfaced in response bodies. Log server-side, return a sanitized message.
>
> **8. Server-authoritative fields accepted from client**
> - `createdBy`, `ownerId`, `workspaceId`, `userId` in POST/PUT body being written to the DB. These must come from the session; reject or ignore if in the payload.
>
> **9. PII in response payloads or logs at info+**
> - Emails, full names, `authUserId`, Cognito subs in list responses or `logger.info` calls.
>
> **10. Response type leaking secrets**
> - Handler returning a DB row with password hashes (`*Hash`), credential secrets (`*Secret`), or authentication tokens (`accessToken`, `refreshToken`, `sessionToken`, `apiKeyToken`, raw key strings) without a `Safe*` type + mask.
> - Do NOT flag pagination cursors, CSRF tokens, Stripe `idempotencyToken`, or other non-secret tokens. Match on the specific field names above, not any column ending in "Token".
>
> For each finding:
> - **File:line** of the issue
> - **Which checklist item** (1–10 above)
> - **Concrete exploit or leak scenario** (one sentence)
> - **Suggested fix** (point to the pattern used elsewhere in the codebase if one exists)
>
> If no security/API-surface issues exist, state "No security issues found". Do NOT flag generalist issues — stay in your lane.
>
> For iterations 2+, append: "The following security findings were intentionally skipped in prior iterations — do NOT re-flag them: [list of skipped items with brief descriptions]." This prevents the loop from re-surfacing out-of-scope items so the loop can converge.

#### Step B: Parse and Act on Findings

1. **Merge findings from all four agents.** De-duplicate: if two agents flag the same file:line with overlapping concerns, keep the more specific finding (usually the specialist's).

2. **If all four agents report no issues**: the loop converges. Exit and proceed to Phase 3.

3. **If any agent reports findings**:
   - **Widen the search before fixing.** For each bug-class finding, grep the repo for the same pattern in sibling files before writing any fix. If `resolveEntityId` leaks a PG UUID into a DDB field in one route, the same leak likely exists in peer routes. If one `{...componentOptions}` spread lets the caller override `rel="noopener"`, other components with the same prop pattern are suspect. Record every additional instance found and fix them in the same iteration. This directly prevents the "round 5 then round 5b" pattern where the reviewer finds the twin bug a round later.
     - Concrete search checklist per finding:
       - Same function/helper name called elsewhere (`grep -rn "<helper>("`)
       - Same anti-pattern shape (e.g., `Promise.all` over an awaited helper, `{...spread}` after safety defaults, `catch {}` in sibling handlers)
       - Same field-to-field assignment across system boundaries (PG→DDB, DDB→PG)
   - Triage using the same categories as `/prfeedback`:
     - **Always fix**: bugs, correctness, security
     - **Fix if straightforward**: error handling, test gaps, edge cases
     - **Skip with justification**: comment rewording, doc improvements, major refactors
   - **Track skipped items per agent**: Maintain **four separate skip lists** — one per specialist (`generalist_skipped`, `scale_skipped`, `silent_failure_skipped`, `security_skipped`). Each skipped finding gets appended to the list of the agent that originally produced it. In the next iteration, inject each list only into the matching specialist's prompt. This avoids telling the scale specialist to ignore a security finding (and vice versa), which would either confuse the prompt or risk suppressing valid findings that share surface-level descriptions.
   - **Per-specialist convergence**: A specialist is treated as **converged for this run** when BOTH conditions hold in the same iteration:
     1. Its only findings are zero, or are items already on its own skip list (skip-list injection worked but the specialist re-flagged them anyway).
     2. No fixes were committed in that iteration (i.e., it was a clean pass, not just a low-signal one).

     If condition (1) holds but fixes were committed in the same iteration — possibly by other specialists or by the generalist — the converged specialist must run ONCE MORE in the next iteration. Those fixes might have introduced new issues in that specialist's lane (a Scale fix can introduce a Silent-failure bug; a Silent-failure fix can re-open a Security gap). Only after a clean-pass confirmation iteration may the specialist be retired.

     The loop terminates when all four specialists are converged under this stricter rule — prevents a stubborn-but-non-actionable specialist from blocking convergence, while preserving the core premise that iteration N's fixes can introduce iteration N+1 regressions.
   - Fix each actionable finding plus every sibling instance found by the widen-the-search step
   - Run local checks after fixes:
     ```bash
     pnpm lint:web --quiet
     pnpm --filter @rootnote/web tsc --noEmit
     pnpm test:ci:web
     ```
   - **Commit fixes** so the next iteration's diff reflects the changes:
     ```bash
     if [ -n "$(git status --porcelain)" ]; then
       # git add -A is intentional here: review fixes may create new files (e.g. test files
       # for coverage gaps). git add -u would silently drop those. This runs in a controlled
       # skill context, not at a user-facing boundary, so the risk of staging secrets is low.
       git add -A
       git commit -m "fix: address issues from local review iteration N"
     fi
     ```
   - If this is iteration 4 (final): fix what you can, note remaining items, and exit the loop

#### Step C: Re-review (next iteration)

After fixing and committing, the loop continues to the next iteration with a fresh review of the updated diff. Because fixes are committed between passes, the review agent sees the actual current state of the code — not the same diff from the first pass.

### Loop Termination

The loop ends when ANY of these is true:
- **Convergence**: All four agents (generalist + scale + silent-failure + security) have converged by the per-specialist rule above (either zero findings OR findings that are a subset of that agent's skip list)
- **Max iterations reached**: 4 passes completed (prevents infinite loops; cap raised from 3 to 4 so most active PRs get a clean-pass confirmation iteration after fixes settle, reducing the frequency of `converged (clean-pass pending)` warnings)
- **No code changes possible**: All remaining findings are out-of-scope or would require major refactors

## Phase 3: Report

After the loop completes, report:

1. **Iterations completed**: How many review passes ran
2. **Findings summary by specialist**: Break totals down by specialist (generalist / scale / silent-failure / security) so the report surfaces which specialist is contributing the most signal
3. **Remaining items**: Any findings that were skipped (with reasons), grouped by specialist
4. **Convergence status per specialist**: One of:
   - `converged` — zero or subset-of-skip-list findings in a clean-pass (no-commit) iteration
   - `converged (clean-pass pending — iteration cap reached)` — satisfied the finding criterion but the confirmation iteration never ran because the 4-iteration cap was hit while fixes were still being committed by other specialists. **Do NOT call the review clean in this state** — call out that a manual re-run or push-and-review is warranted for this specialist's lane.
   - `not converged (cap hit)` — still producing new findings at the 4-iteration cap

Format as a concise summary, e.g.:
```
Local review complete (all converged in 2 iterations):
- Pass 1: 8 findings — generalist: 3 (2 fixed, 1 skipped), scale: 2 (2 fixed), silent-failure: 2 (2 fixed), security: 1 (1 fixed)
- Pass 2: 1 finding — generalist: 0, scale: 0, silent-failure: 1 (subset of skip list → converged), security: 0 → all converged
- Remaining: 1 item skipped (refactor suggestion for auth module — follow-up ticket recommended)
```

Or, when cap is reached mid-confirmation:
```
Local review complete (iteration cap reached, partial convergence):
- Pass 3 committed fixes → clean-pass confirmation iteration 4 never ran
- generalist: converged
- scale: converged (clean-pass pending — iteration cap reached) ← re-run or push to verify
- silent-failure: converged
- security: converged (clean-pass pending — iteration cap reached) ← re-run or push to verify
```

## Standalone vs. Embedded Usage

- **Standalone** (`/iterative-review`): Runs the full loop, committing fixes between iterations. Does not push. The calling user or skill handles push.
- **Embedded** (called from `/feature`, `/bugfix`, `/chore`, or `/prfeedback`): Same loop with inter-iteration commits. The calling skill handles push afterward. `/prloop-enhanced` no longer invokes iterative-review as a pre-PR phase (the old Phase 1.5 was removed); that responsibility now sits in the caller (`/feature`, `/bugfix`, `/chore`). It still invokes iterative-review in its own Phase 6 before each feedback-loop re-push — that gate is intentional and prevents CI round-trips on feedback-fix regressions.

## Key Principles

1. **Mirror the GH Action** — use the same focus areas so local and remote reviews are aligned
2. **Iterate to convergence** — fixes can introduce new issues; re-reviewing catches them locally
3. **Cap iterations** — 4 passes prevents runaway loops while catching fix-introduced regressions AND giving most active PRs one clean-pass confirmation iteration after fixes settle
4. **Triage, don't blindly fix** — skip comment rewording and major refactors, same as `/prfeedback`
5. **Fresh eyes each pass** — each iteration spawns a new review agent for independent assessment
