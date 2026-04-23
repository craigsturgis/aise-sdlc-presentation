---
name: prloop-enhanced
description: Commit, push, create PR, then loop on CI failures and AI review feedback until green. Includes pre-PR self-review, code simplification, implementation reflection, and incorporates ALL feedback including minor suggestions.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill, Agent
model: sonnet
---

# Enhanced PR Loop with Pre-Review and Comprehensive Feedback Incorporation

Execute a complete PR workflow that includes self-review, code simplification, and implementation reflection before PR creation, and incorporates review feedback with a convergence cap (rounds 1–3: fix everything actionable; round 4+: fix only bugs/security/correctness and defer polish to follow-ups).

## User Input

```text
$ARGUMENTS
```

Consider user input for commit message guidance or specific instructions.

## Preconditions: Iterative Review Must Have Run

This skill assumes `/iterative-review` has **already run locally** against the pending changes before this skill is invoked. The `/feature`, `/bugfix`, and `/chore` skills handle this for you in the phase immediately before delegating here.

- **If you are invoked directly (not from feature/bugfix/chore)**: run `/iterative-review` first yourself, then invoke this skill. Pushing without a prior iterative-review pass burns GH Action tokens and CI minutes on issues that four parallel local specialists would have caught in under 2 minutes.
- **If the caller has already run iterative-review**: proceed. No need to re-run — the diff has not changed since.
- **Exception (infra/CI/tooling/docs-only diffs)**: if the caller explicitly notes "no app code changes, iterative-review skipped", proceed without prompting.
- **Handoff contract from the caller**: if iterative-review surfaced any skipped items (major refactor suggestions deferred to follow-up, or items it couldn't auto-fix), the caller should hand those forward so this skill can include them in the PR description as known open items. If no skipped-items note is present in the handoff (common for direct invocations), **proceed without pausing** and add a line to the PR body: `_No iterative-review handoff received; any skipped findings are not enumerated below._` This preserves the fast path for direct invokers while still documenting the contract gap for reviewers.

## Phase 1: Pre-PR Self-Review

Before creating the PR, perform a thorough self-review of your changes. This phase is critical for catching issues that would otherwise require multiple review round-trips with the GitHub Action reviewer, burning non-cached tokens.

1. **Get the diff of all changes** to be included in the PR:
   ```bash
   git diff $(git merge-base HEAD origin/dev)..HEAD
   ```

2. **Review your own code** using the checklist below. These checks are ordered by frequency from analysis of 188 review feedback items across 17 recent PRs — the top categories account for 75% of all review round-trips.

   ### 2a. Test Coverage Gaps (25% of all review feedback — #1 cause of round-trips)
   - **Every new utility/module file has a corresponding test file.** Run:
     ```bash
     # List new non-test .ts/.tsx files and check each has a test counterpart
     git diff --name-only --diff-filter=A $(git merge-base HEAD origin/dev)..HEAD | grep -E '\.(ts|tsx)$' | grep -v -E '\.(spec|test)\.' | grep -v -E '__tests__'
     ```
     For each file listed, verify a test file exists or the file is covered by an existing test.
   - **Enumerate branches before implementing.** For every new function with N branches/edge cases, write at least N tests: happy path, error path, null/undefined input, empty input, boundary conditions (pagination end, rate limits, zero values).
   - **Test every error handling path.** If you added a `catch` block or error branch, there must be a test that exercises it. This is the single most common gap.
   - **Meaningful assertions** — not just `expect(result).toBeDefined()` but checking actual values, structure, and side effects. Use `toEqual` over `toBeDefined`.

   ### 2b. Comments & Documentation (19% of all review feedback)
   - **Add explanatory comments** for non-obvious decisions: why a sentinel value is used, why an enum member is excluded, why a particular field mapping exists. The reviewer shouldn't have to guess intent.
   - **JSDoc comments must match actual behavior** — especially `@returns` descriptions, parameter types, and thrown error types. Wrong docs are worse than no docs.
   - **Variable/function names must reflect what they actually do** — a field called `total` should be a total, not a union count. Rename or add clarifying comments if ambiguous.
   - **Cross-reference related code** — when two files must stay in sync (e.g., field mappings, service pairs), add a comment pointing to the counterpart.

   ### 2c. Error Handling & Logging (12% of all review feedback)
   - **No silent error swallowing** — every `catch` block must either re-throw, return a meaningful value, or log with `logger.warn`/`logger.error` (never just `console.log` or empty catch).
   - **Use `logger.error`/`logger.warn`** not `console.error`/`console.warn` — console methods don't integrate with CloudWatch.
   - **Error messages must include context** — which operation failed, what input caused it, enough to debug from CloudWatch.
   - **Never cache error responses** — transient API failures cached permanently would suppress correct behavior.
   - **In platform adapters**: classify errors correctly per CLAUDE.md "Platform Adapter Error Classification" rules.

   ### 2d. Correctness — Actual Bugs (11% of all review feedback)
   - **`??` vs `||`**: Use nullish coalescing (`??`) for numeric/string fallbacks. `|| 0` treats empty string as falsy; `?? 0` only catches null/undefined. This is the most common single-line bug.
   - **Truthy checks on arrays/objects**: `[]` and `{}` are truthy — use `.length > 0` or `Object.keys(x).length > 0`.
   - **Operator precedence in casts**: `(value as Type | undefined) ?? fallback` — parenthesize the cast.
   - **Null checks after create/find operations**: Service `.create()` and `.find()` can return null — check before using the result.
   - **Field access on correct object**: When a response object has nested structures (e.g., `automatedConnection` vs `connection`), verify you're accessing the right one.

   ### 2e. Edge Cases (8% of all review feedback)
   - **Empty/null inputs**: What happens when the input is `null`, `undefined`, empty string, empty array, or `0`?
   - **Pagination boundaries**: Missing cursor, `has_more=true` with no next page token, empty-string tokens.
   - **Empty-string vs null**: `??` treats empty string as non-null; `||` treats it as falsy. Choose intentionally.
   - **Guard against unexpected API response shapes** — log a warning and handle gracefully rather than crashing.

   ### 2f. Type Safety (7% of all review feedback)
   - **No `as unknown as` double casts** unless matching an established pattern in the same module family. If you add one, add a code comment explaining why.
   - **No `any` types** in new code. Use `unknown` in catch blocks with type guards. If unavoidable, add `// eslint-disable-next-line` with justification.
   - **Use `unknown` instead of `any` in catch blocks**: `catch (error: unknown)` then narrow with `if (error instanceof Error)`.

   ### 2g. Dead Code (7% of all review feedback)
   - **Remove all unused imports, variables, and unreachable code paths.** Run:
     ```bash
     pnpm lint:web --quiet 2>&1 | grep -E 'no-unused|@typescript-eslint/no-unused'
     ```
   - **Remove redundant null coalescing** on values already guaranteed non-null (e.g., `?? 0` on a number field, `?? undefined` on an optional).
   - **No commented-out code** — delete it (it's in git history).

   ### 2h. Pattern Consistency (5% of all review feedback)
   - **New modules must match sibling structure** — platform adapters mirror `api-client.ts`, `auth.ts`, `metrics.ts`, `content.ts`, `index.ts`. API routes match the patterns of existing routes in the same directory.
   - **Use `logger.*` consistently** — not a mix of `console.*` and `logger.*` in the same file.

   ### 2i. Security (low frequency but high severity)
   - **Never log PII** (emails, authUserId) at `info` level or above.
   - **Tokens/API keys in POST body or headers**, never URL query params.
   - **Validate user-supplied IDs** (UUID format) at API boundaries — return 400 early.

   ### 2j. Performance & Accessibility (low frequency)
   - **Parallelize independent async calls** with `Promise.all` instead of sequential `await`.
   - **Accessibility**: `aria-label` on icon buttons, `htmlFor`/`id` on label/input pairs.

3. **If issues found**: Fix them, commit with clear message, then re-review the fixes (don't just fix and move on — verify your fix doesn't introduce new issues).

4. **Run local checks** before proceeding:
   ```bash
   pnpm lint:web --quiet
   pnpm --filter @rootnote/web tsc --noEmit
   pnpm test:ci:web
   ```
   Fix any failures before proceeding to Phase 2 (Code Simplification).

   **Note:** If builds fail with memory errors, use:
   ```bash
   NODE_OPTIONS="--max-old-space-size=4096" pnpm build:web
   ```

5. **If database schema changes were made**, generate migrations:
   ```bash
   pnpm --filter @rootnote/web db:generate
   ```
   Never manually create migration SQL files - always use `db:generate`.

## Phase 2: Code Simplification

After self-review and before committing, run the **simplify** skill to refine the changed code for clarity, consistency, and maintainability.

1. **Invoke the Skill tool** with `skill: "simplify"`. The simplifier will:
   - Identify recently modified code sections
   - Simplify overly complex logic
   - Apply project coding standards from CLAUDE.md
   - Eliminate redundant code and unnecessary abstractions
   - Improve naming and readability
   - Preserve all existing functionality

2. **Review the simplifier's changes** — ensure no behavior was altered. If the simplifier made changes, verify tests still pass:
   ```bash
   pnpm test:ci:web
   ```

3. **If the simplifier found nothing to improve**, proceed to Phase 3.

## Phase 3: Implementation Reflection

Before committing, reflect on the implementation by answering these questions. Include the answers in the PR description under a "## Reflection" section:

1. **What was the hardest decision you made here?** — Identify the most difficult trade-off, design choice, or judgment call in this implementation.

2. **What alternatives did you reject, and why?** — Describe approaches you considered but decided against, and the reasoning behind those decisions.

3. **What are you least confident about?** — Call out areas where you're uncertain, where edge cases might lurk, or where future changes could cause issues.

These reflections help reviewers focus their attention on the areas that matter most and provide valuable context for future maintainers.

## Phase 4: Commit and Push

**Important:** Always branch from `dev`, not `main`. Verify you're on the correct branch.

1. **Check git status** for uncommitted changes:
   ```bash
   git status
   ```

2. **If there are uncommitted changes**, create a well-structured commit:
   - Use conventional commits format (feat:, fix:, chore:, docs:, refactor:, test:)
   - Write clear, descriptive commit messages
   - Include the Linear issue ID if applicable (e.g., ROO-XXX)

3. **If pre-commit hooks fail**:
   - Examine the failure — is it related to your changes?
   - If related: fix the issue and try again
   - If clearly unrelated (flaky test, unrelated lint rule): retry once
   - If it fails again on the same unrelated issue: use `--no-verify` and note in the commit message:
     ```
     Note: --no-verify used due to unrelated pre-commit hook failure in <description>
     ```

4. **Push to origin**:
   ```bash
   git push -u origin HEAD
   ```

## Phase 5: Create or Update PR

1. **Check if PR already exists**:
   ```bash
   gh pr view --json number,url 2>/dev/null || echo "NO_PR"
   ```

2. **If no PR exists**, create one:
   - Generate a clear title summarizing the changes
   - Write a comprehensive description including:
     - Summary of changes (bullet points)
     - Reflection section (from Phase 3)
     - Test plan
     - If `$ARGUMENTS` contains iterative-review convergence caveats (e.g., `"clean-pass pending"`, `"not converged (cap hit)"`, or skipped findings), include them under a **Known open items** section so reviewers and CI can weigh in on whether follow-up is needed. (On a clean-convergence handoff — `"iterative-review converged cleanly, no items skipped"` — this section is omitted.)
     - Any other relevant context
   - Use `gh pr create`

3. **If PR exists**, ensure it's up to date with latest push.

## Phase 6: Monitor and Loop on Feedback (Parallel Tracks)

Enter the feedback loop using **two parallel tracks** to avoid idle time. Do NOT block on all CI checks before reading review feedback.

Continue until ALL of the following are true:
- All CI checks pass (green)
- All actionable review comments are addressed (see the Addressing Feedback section for the round-based triage — rounds 1–3 incorporate minor/nit/optional suggestions, round 4+ fix only bugs/security/correctness)
- No pending review requests

**First, get the PR number** (used by both tracks):
```bash
PR_NUMBER=${PR_NUMBER:-$(gh pr view --json number -q '.number')}
```

### Track A: Monitor for Claude Code Review (Fast — typically 2-5 minutes)

The Claude Code Review GitHub Action runs on every push and typically completes much faster than the full CI suite. Prioritize reading its feedback early.

1. **Poll for the Claude Code Review check to complete.** Check the following command every 30 seconds (up to 10 minutes total). If `claude` appears in the output and the status is not `pending`, proceed immediately:
   ```bash
   gh pr checks | grep -i "claude"
   ```
   - Do NOT wait for other checks to finish before reading Claude's review

2. **Read Claude Code Review feedback as soon as it's available**:
   ```bash
   # Filter by body content — the Claude Code Review action posts as github-actions[bot], not a "claude" login
   gh pr view --json comments -q '.comments[] | select(.body | test("Code Review|Claude finished"; "i")) | .body'
   # Also check inline review comments
   gh api "repos/$(gh repo view --json owner,name -q '"\(.owner.login)/\(.name)"')/pulls/${PR_NUMBER}/comments"
   ```

3. **Address Claude's feedback immediately** — don't wait for CI to finish. See "Addressing Feedback" below.

### Track B: Monitor Full CI Suite (Slower — typically 10-20 minutes)

While addressing review feedback (or after, if no feedback yet), monitor the full CI suite.

1. **Poll CI status every 60 seconds (up to 30 minutes total).** If all checks show pass/fail (no more pending), stop polling:
   ```bash
   gh pr checks
   ```

2. **As soon as any check fails**, investigate and fix it. Extract the run URL from the checks output:
   ```bash
   # List failed checks with their detail URLs
   gh pr checks --json name,status,detailsUrl | jq -r '.[] | select(.status | ascii_downcase | test("fail")) | "\(.name): \(.detailsUrl)"'
   # View failure logs (extract run ID from the URL, e.g., the number after /runs/)
   gh run view <run-id> --log-failed
   ```
   - Fix the issues locally
   - Commit and push fixes

3. **If all checks pass and Track A is also done**, the loop is complete.

### Addressing Feedback (applies to both tracks)

**Triage by severity — and count rounds:**

Track how many Claude Code Review rounds have run on this PR (each push that touches app code triggers a new review). Apply different rules at different round counts:

- **Rounds 1–3**: Incorporate minor/nit/optional suggestions. Early rounds tend to surface real gaps that compound, and fixing them in-band while context is fresh is cheaper than deferring.
- **Round 4+**: Only fix **bugs, security, correctness, or user-visible regressions**. Defer everything else — `consider`/`nit`/`minor`/`documentation` items — to a follow-up ticket. Push the PR to merge-ready state and stop the loop.

**Why the cap**: every push re-runs `claude-review` (~5 min of non-cached tokens plus the associated CI minutes) and the reviewer reliably finds new "consider" items on every diff, even after 5+ converged rounds. The prfeedback memory calls this the "token trap" — it applies equally here. Don't conflate "the reviewer always has something to say" with "the PR isn't ready."

**Discriminator** for whether a finding is a bug vs. a consider-item:
- Bug / correctness: user-visible regression, security gap, silent data loss, broken guarantee the PR introduced (or worsened).
- Consider: missing test parity, better abstraction, comment rewording, doc improvements, latency optimizations under nominal load, cleanup of pre-existing code adjacent to the diff.

**Hard stop signals** (exit the loop regardless of round count):
- The reviewer flagged the same finding in two consecutive rounds and you've already triaged it as skipped with a justification → stop acknowledging it.
- The reviewer's only findings are on code the current PR didn't touch → out of scope, file a follow-up.
- You've pushed a fix and the next review's findings are all about the fix itself rather than the original work → you've crossed into polishing, not shipping.

**For each piece of feedback that passes the triage:**
- Read and understand the suggestion
- Implement the change
- If you disagree, respond explaining why, but default to implementing for correctness findings
- Commit with: `fix: address review feedback - [brief description]`

**When skipping reviewer feedback**: note it in the PR's "Known open items" section so the reviewer (human or AI) sees it was triaged, not overlooked. This breaks the loop by signaling "already considered."

### After Addressing Feedback or Fixing CI

1. **Run the iterative local review before pushing** — feedback fixes often introduce new issues that trigger another GH Action review cycle. Invoke the Skill tool with `skill: "iterative-review"`. Commit any changes it produces:
   ```bash
   if [ -n "$(git status --porcelain)" ]; then
     git add -A
     git commit -m "fix: address issues found during local iterative review"
   fi
   ```

2. **Push changes**:
   ```bash
   git push
   ```

3. **Check for new review feedback** (a new push triggers a new Claude Code Review run):
   ```bash
   # Reuse the same body-content filter from Track A to find Claude review comments
   gh pr view --json comments -q '.comments[] | select(.body | test("Code Review|Claude finished"; "i")) | .body'
   gh api "repos/$(gh repo view --json owner,name -q '"\(.owner.login)/\(.name)"')/pulls/${PR_NUMBER}/comments"
   ```

4. **Also check for human reviewer comments** that may have arrived:
   ```bash
   # Include COMMENTED state — reviewers often leave inline feedback without formally requesting changes
   gh pr view --json reviews -q '.reviews[] | select(.state != "APPROVED" and .state != "DISMISSED") | .body'
   # Also check inline review comments separately (catches comments not attached to a formal review)
   gh api "repos/$(gh repo view --json owner,name -q '"\(.owner.login)/\(.name)"')/pulls/${PR_NUMBER}/comments"
   ```

5. **Monitor CI on the new push** — repeat Track B polling.

6. **Repeat** until all checks pass and all feedback (Claude + human) is addressed.

## Success Criteria

The loop completes when:
- All CI checks show green/passing status
- All review comments have been addressed or resolved
- No outstanding change requests
- PR is ready for merge approval

## Key Principles

1. **Self-review catches issues early** - Fix problems before reviewers see them
2. **Simplify before shipping** - Run the code-simplifier to catch complexity before reviewers do
3. **Reflect on your decisions** - Documenting trade-offs helps reviewers focus on what matters
4. **Minor feedback matters** - Small improvements compound into better code quality
5. **In-band fixes are cheaper** - Address feedback while context is fresh
6. **Default to implementing** - Only push back on feedback with strong technical justification
7. **Keep the loop tight** - Small, focused commits make iteration faster
8. **Check fast feedback first** - Don't let slow CI block reading review feedback that's already available
