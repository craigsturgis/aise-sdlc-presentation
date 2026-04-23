---
name: chore
description: Read a Linear ticket, understand the chore scope, generate and confirm acceptance criteria, plan the work, implement with tests where behavior changes, verify, document via Showboat, and create a PR targeting dev
argument-hint: "<TICKET-ID e.g. ROO-123>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, Skill, mcp__linear__get_issue, mcp__linear__list_issues, mcp__linear__list_issue_statuses, mcp__linear__update_issue, mcp__linear__list_teams, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__new_page, mcp__chrome-devtools__list_pages, mcp__chrome-devtools__select_page, mcp__chrome-devtools__take_snapshot, mcp__chrome-devtools__wait_for, mcp__chrome-devtools__fill, mcp__chrome-devtools__click, mcp__chrome-devtools__evaluate_script
model: opus
---

# Chore Workflow

Read a Linear ticket, understand the chore scope (refactoring, dependency updates, CI/CD, tooling, config, infra, etc.), generate and confirm acceptance criteria with the user, plan the work, implement with tests where behavior changes, run verification, document via Showboat, create a PR targeting `dev`, and monitor CI until green.

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` must contain a Linear ticket ID (e.g., `ROO-123`). If empty or missing, use **AskUserQuestion** to ask for the ticket ID before proceeding.

## Phase 1: Read the Ticket & Understand the Chore

1. **Parse the ticket ID** from `$ARGUMENTS`:
   - Extract the ticket identifier (e.g., `ROO-123`)
   - Strip any URL prefix if the user pasted a full Linear URL

2. **Fetch the Linear ticket**:
   Use `mcp__linear__get_issue` with the ticket ID.

3. **Understand the chore** — read the ticket carefully and extract:
   - **Goal**: What is the outcome of this chore? (cleaner code, updated deps, better CI, etc.)
   - **Scope**: What exactly needs to change? What's out of scope?
   - **Motivation**: Why is this chore needed now? (tech debt, security, compliance, performance, DX)
   - **Risks**: Could this break anything? What needs extra caution?
   - **Dependencies**: Does this depend on or block other tickets?

4. **Classify the chore type** to guide later phases:

   | Chore Type | Examples | Tests Needed? | Visual Verification? |
   |---|---|---|---|
   | Refactoring | Extract component, rename, restructure | Yes — existing tests must stay green, add if coverage gaps | Only if UI touched |
   | Dependency update | Bump packages, migrate APIs | Yes — run full suite, add tests for breaking changes | Only if UI libs updated |
   | CI/CD | Pipeline changes, build config | No new tests usually — verify pipeline runs | No |
   | Tooling/DX | Linting rules, dev scripts, configs | No new tests usually — verify tools work | No |
   | Infrastructure | Terraform, AWS config, env vars | No app tests — verify infra plan/apply | No |
   | Performance | Optimization, caching, query tuning | Yes — benchmark or test the optimization | Sometimes |
   | Cleanup | Remove dead code, delete unused files | Yes — existing tests must stay green | No |

5. **Explore the codebase** to understand the current state:
   - Search for files, modules, or configurations related to the chore
   - Understand what exists that will be changed
   - Check for existing test coverage of affected areas
   - Review recent git history if relevant:
     ```bash
     git log --oneline -20 -- <relevant-paths>
     ```

## Phase 2: Ask Clarifying Questions

If the ticket is ambiguous or underspecified, use **AskUserQuestion** to resolve uncertainty before proceeding.

Ask about things like:
- **Unclear scope**: "The ticket says 'clean up the auth module' — should I only restructure files, or also refactor the logic?"
- **Risk assessment**: "Updating this dependency has breaking changes in X — should I address those now or split into a follow-up?"
- **Approach trade-offs**: "I can do this incrementally (safer, multiple PRs) or all at once (one PR, more risk) — which do you prefer?"

Skip this phase if the ticket is clear and unambiguous.

## Phase 3: Generate & Confirm Acceptance Criteria

Before planning implementation, define what "done" looks like.

1. **Generate acceptance criteria** (typically 2-6) based on:
   - The chore's goal and scope from the ticket
   - Risks identified during analysis
   - What must NOT break (regression criteria)
   - Any criteria already stated in the ticket

   Each criterion should be a concrete, verifiable statement — something a reviewer can check yes/no. Examples:
   - "All references to the old `AuthProvider` are replaced with `AuthContextProvider`"
   - "No new lint warnings introduced"
   - "Existing test suite passes without modification"
   - "`react-query` upgraded from v4 to v5 with no runtime errors"

2. **Present the criteria to the user** via **AskUserQuestion**:

   Format as a checklist:
   ```
   Based on the ticket and analysis, here are the proposed acceptance criteria:

   - [ ] <criterion 1>
   - [ ] <criterion 2>
   - [ ] ...

   Do these look right? Anything to add, remove, or change?
   ```

3. **Wait for confirmation** before proceeding. Incorporate any changes the user requests.

4. **Use the confirmed criteria to drive**:
   - The implementation plan (Phase 4)
   - Which tests to write or verify (Phase 6)
   - What to verify visually, if applicable (Phase 8)
   - The PR's test plan (handled by /prloop-enhanced in Phase 11)
   - The final report's acceptance criteria check (Phase 12)

## Phase 4: Plan the Implementation

Design a plan before making changes.

1. **Identify all files that need changes**:
   - Files to modify
   - Files to create or delete
   - Config files affected

2. **Break into ordered steps**:
   - Each step should be independently verifiable
   - For risky changes, plan a rollback-safe order (e.g., add new code before removing old)
   - For dependency updates, plan: update → fix breaking changes → verify

3. **Determine testing strategy**:
   - **If behavior changes**: Write or update tests (TDD if adding new behavior)
   - **If pure refactor**: Existing tests must pass — identify gaps and fill them first
   - **If config/tooling only**: Verify the tool/pipeline works correctly
   - **If cleanup/deletion**: Ensure nothing references removed code

4. **Present the plan to the user** via **AskUserQuestion**:
   - Summarize the approach in 3-5 bullet points
   - Call out any risks or decisions
   - Ask: "Does this approach look right, or would you like me to adjust anything?"

Only proceed to implementation after the user confirms the plan.

## Phase 5: Set Up Branch or Worktree

1. **Detect if already in a worktree**:
   ```bash
   if [ -f .git ]; then
     echo "WORKTREE"
   else
     echo "MAIN_REPO"
   fi
   ```

2. **Check the current branch**:
   ```bash
   git branch --show-current
   ```

3. **Decide how to proceed**:

   **If in a worktree** (`.git` is a file):
   - Verify the branch name relates to the ticket (contains the `ROO-XXX` pattern)
   - If it does: use the current branch as-is
   - If it doesn't: warn the user and ask how to proceed

   **If in the main repo** (`.git` is a directory):
   - Fetch latest: `git fetch origin dev`
   - Create a chore branch from `dev`:
     ```bash
     git checkout -b chore/<LINEAR_BRANCH_NAME> origin/dev
     ```
   - Use the `branchName` field from the Linear ticket if available.

   **NEVER commit directly to `main` or `dev`.**

## Phase 6: Implement the Chore

Execute the plan from Phase 4, adapting the testing approach to the chore type.

### For behavior-changing chores (refactoring, performance, dependency updates):

1. **If adding new behavior or changing existing behavior**, follow TDD:
   - Write failing tests first
   - Implement the change
   - Verify tests pass

2. **If pure refactoring** (same behavior, different structure):
   - Run existing tests first to establish a green baseline
   - Make changes incrementally
   - Run tests after each change to catch regressions immediately

3. **If updating dependencies**:
   - Update the dependency
   - Fix any breaking API changes
   - Run the full test suite
   - Add tests for any new behavior or changed APIs

### For non-behavior chores (CI/CD, tooling, config, infra):

1. **Make the changes** according to the plan
2. **Verify they work**:
   - CI/CD: Dry-run or test the pipeline locally if possible
   - Tooling: Run the tool and verify output
   - Config: Verify the config is valid and has the intended effect
   - Infrastructure: Run `terragrunt plan` to preview changes

### For cleanup/deletion chores:

1. **Search for all references** to the code being removed:
   ```bash
   grep -r "SymbolName" --include="*.ts" --include="*.tsx" --include="*.js" .
   ```
   Also use the Glob and Grep tools for thorough cross-referencing.
2. **Check for indirect callers** where the deleted name is constructed dynamically — routers, dispatchers, and registries often build endpoint paths or handler keys from another field (e.g., `fetch(`/${creatorBlock.identifier}`)` where `identifier` happens to be the deleted name). A plain grep for the symbol will miss these. Look for string-interpolation patterns that match the deleted name's shape.
3. **Remove the code** only after confirming no references exist
4. **Run the full test suite** to catch any missed references

## Phase 7: Run Full Verification Suite

**For chores that touch app code** (refactoring, dependency updates, cleanup, performance), run all checks:

```bash
# Run full test suite
pnpm test:ci:web

# Lint check
pnpm lint:web --quiet

# TypeScript compilation check
pnpm --filter @rootnote/web tsc --noEmit
```

- **If tests fail**: Diagnose whether the failure is related to your change or pre-existing. Fix related failures.
- **If lint fails**: Fix lint errors in your changed files.
- **If TypeScript fails**: Fix type errors before proceeding.

**For infra/CI/tooling-only chores** (no app code changes), skip the above and instead verify the specific tool or pipeline works:
- Infrastructure: `terragrunt plan` to preview changes
- CI/CD: Verify pipeline config is valid (e.g., `gh workflow view` or dry-run)
- Tooling: Run the tool and verify output
- Config: Validate the config has the intended effect

## Phase 8: Visual Verification (optional)

**Skip this phase** unless the chore touches UI components, updates UI libraries, or changes rendering behavior. Refer to the classification table in Phase 1 — only "Refactoring" and "Dependency update" rows mark visual verification as potentially needed.

If visual verification is warranted, use the same approach as the `/bugfix` and `/feature` skills:

1. **Parse PORT from `web/.env.local`** (default to `3000`).
2. **Ensure the dev server is running**.
3. **Try agent-browser first**, falling back to chrome-devtools MCP:
   - Authenticate using cached Playwright auth state or form-based login (see the Visual Verification phase in `/bugfix` skill for full details)
   - Navigate to the affected page
   - Capture a screenshot: `demos/${TICKET}-verify.png`
4. **If the chore has no UI impact**, skip this entirely — do not start a dev server unnecessarily.

## Phase 9: Showboat Documentation

1. **Check if Showboat is available**: `command -v showboat`

2. **Check for existing demo file**: `demos/${TICKET}.md`

3. **If Showboat is installed AND demo file exists**:
   ```bash
   showboat note demos/${TICKET}.md "Chore completed — <brief summary of what was done>"
   ```

4. **If Showboat is installed but NO demo file exists**:
   ```bash
   showboat init demos/${TICKET}.md "Chore: <brief chore description>"
   showboat note demos/${TICKET}.md "Summary: <what was changed and why>"
   showboat exec demos/${TICKET}.md bash "pnpm test:ci:web"
   ```

5. **If Showboat is not installed**, skip this phase.

## Phase 10: Local Iterative Review (MANDATORY before PR)

Run `/iterative-review` locally **before** handing off to `/prloop-enhanced`. This catches issues on cached local tokens and short wall time instead of paying the GH Action reviewer cycle cost (~5 min + non-cached tokens) for problems a local pass would find in under 2 minutes.

**For infra/CI/tooling/docs-only chores** where no app code changed (e.g., Terragrunt, pipeline YAML, dev scripts, `SKILL.md` / `CLAUDE.md` / other markdown-only edits), iterative-review has little to work with — the specialists target code patterns (`??` vs `||`, N+1, auth gaps, silent failures) that markdown and config files don't exercise. Skip iterative-review and note "no app code changes, iterative-review skipped" in the handoff to /prloop-enhanced. For all other chore types (refactoring, dependency updates, cleanup, performance), run iterative-review normally.

1. **Commit any in-flight chore changes** so iterative-review operates on a stable diff:
   ```bash
   if [ -n "$(git status --porcelain)" ]; then
     # git add -A is intentional: a chore may add new files (extracted modules, dep migration
     # snapshots, tests for newly-covered behavior) that git add -u would silently drop. This
     # runs in a worktree context, not at a user-facing boundary, so the risk of staging
     # secrets is low. If CLAUDE.md says "never git add -A", this is the exception.
     git add -A
     git commit -m "chore(<ticket-id from Phase 1>): <short description of the chore>"
   fi
   ```

2. **Invoke the Skill tool** with `skill: "iterative-review"`. The skill will:
   - Spawn four parallel specialist agents (generalist, scale, silent-failure, security) against the branch diff vs `origin/dev`
   - Commit fixes between iterations
   - Loop up to 4 iterations until convergence

3. **Verify local checks still pass** after iterative-review completes — it runs checks internally after each fix iteration, but confirm once more before handoff:
   ```bash
   pnpm lint:web --quiet && pnpm --filter @rootnote/web tsc --noEmit && pnpm test:ci:web
   ```
   **Skip this step for the infra/CI/tooling/docs-only skip path** — there's no app code to lint, typecheck, or test against. Consistent with the Phase 7 "skip the above" guidance for the same chore types.

4. **Record the iterative-review outcome** for the PR description. **Always pass a note in the Phase 11 handoff** — even on clean convergence — so prloop-enhanced's Preconditions block doesn't mis-classify this as a direct invocation and emit the "no handoff received" disclaimer:
   - If convergence was clean (all specialists converged, nothing skipped): `"iterative-review converged cleanly, no items skipped"`
   - If any specialist ended in `converged (clean-pass pending — iteration cap reached)` or `not converged (cap hit)`: describe the specifics (which specialist, which caveat) so /prloop-enhanced can include them in the PR body.
   - For the infra/CI/tooling/docs-only skip path, the exact phrase requirement from the handoff bullet below takes precedence over this confirmation note.

Only proceed to Phase 11 once iterative-review reports convergence (or the 4-iteration cap is reached with skipped items justified), or you explicitly skipped it as an infra/CI/tooling-only chore.

## Phase 11: Commit, PR, and CI Loop

Delegate the commit, push, PR creation, and CI monitoring to the `/prloop-enhanced` skill.

**Invoke the Skill tool** with `skill: "prloop-enhanced"` and provide context as arguments:
- The ticket ID (ROO-XXX)
- That the PR should target `dev`
- The commit message should use `chore(ROO-XXX): <description>` format
- A note that `/iterative-review` has already run locally (Phase 10), so prloop-enhanced can skip re-running it and go directly to simplification + reflection + PR creation. If iterative-review was skipped (infra/CI/tooling/docs-only chore), include the **exact phrase** `"no app code changes, iterative-review skipped"` in the args — prloop-enhanced's Preconditions block looks for that specific marker to trigger its exception path (any paraphrase will fall through to the fail-open disclaimer).
- The iterative-review outcome note from Phase 10 step 4 — either `"iterative-review converged cleanly, no items skipped"` on the happy path, or the specific convergence caveats / skipped findings. Without any note, prloop-enhanced's Preconditions block treats the run as a direct invocation and adds a "no handoff received" disclaimer to the PR body.

The prloop-enhanced skill will handle:
1. Code simplification (via the /simplify skill)
2. Implementation reflection (hardest decision, rejected alternatives, least confident areas)
3. Committing and pushing
4. Creating the PR with a comprehensive description including the reflection
5. Monitoring CI and addressing review feedback until green

**Wait for the skill to complete** before proceeding to the Report phase.

## Phase 12: Report

After all CI checks are green, provide a summary:

1. **Chore Summary**: What was done and why, in 2-3 sentences
2. **Files Changed**: List of modified/created/deleted files with brief descriptions
3. **Testing**: What was tested and how (existing tests, new tests, manual verification)
4. **Acceptance Criteria**: Checklist of confirmed criteria with pass/fail status
5. **Showboat Demo**: Path to the demo doc (if created), or note that it was skipped
6. **PR Link**: URL to the pull request
7. **CI Status**: Confirmation that all checks pass
8. **Notes**: Any caveats, follow-up work, or related issues discovered

## Phase 13: Refine Linear Title & Description for Release Notes

Chore tickets often read as pure tech-debt shorthand ("Bump react-query to v5", "Extract AuthProvider"). Even when the user-visible impact is small, a sentence describing what changed in plain language makes standup updates and release notes far more consumable. This phase runs **after the PR is green** so you have full context about what actually shipped.

0. Re-fetch the ticket: `mcp__linear__get_issue` with `<TICKET-ID>` to get the current description before constructing any update.

1. **Draft a human-readable title** describing the outcome:
   - If the chore has any user-visible impact (performance, reliability, new capability), frame the title around that outcome
   - If it's purely internal (refactor, tooling, dead code removal), use plain language that still makes sense to a non-engineer — e.g. "Clean up unused authentication helpers" rather than "Delete unused AuthProvider exports"
   - Avoid file names, class names, framework names, and internal project jargon in the title itself
   - Brief — ideally fits on one release-note line

2. **Draft a 1-2 sentence user-facing summary** suitable for release notes:
   - If there is user-visible impact: describe what users will experience (faster loads, fewer errors, etc.)
   - If purely internal: a one-liner like "Internal cleanup — no user-visible change" is fine, and you should offer "title only" in step 3
   - Skip implementation details (no "switched from X to Y")

3. **Show the user the current vs proposed values** and use **AskUserQuestion** to ask how to proceed. Format the question body so they can compare:
   ```
   Current title: <original>
   Proposed title: <human-readable version>

   Current description (top): <first line or two>
   Proposed summary to prepend: <1-2 sentence user-facing summary>
   ```
   Options:
   - "Apply both" — update title and prepend the summary to the description
   - "Apply title only" — update just the title, leave description unchanged (recommended for purely internal chores)
   - "Edit first" — user wants to tweak the wording before applying
   - "Skip" — keep the Linear issue as-is

4. **If the user chooses "Edit first"**, collect the preferred wording (ask follow-up questions as needed) then apply their version.

5. **If applying changes**, call `mcp__linear__update_issue` with:
   - `id: <TICKET-ID>`
   - `title: <accepted title>` (when title is being updated)
   - `description: <updated description>` (when summary is being applied) — prepend a `## Summary` block at the top of the existing description so the original content is preserved. If a `## Summary` block already exists at the top, replace its body rather than stacking a second one.

6. **If the user chooses "Skip"**, continue to the next phase without any Linear changes.

## Phase 14: Review Learnings (opt-in)

After the PR is green and ready to merge, offer to review what was learned during the chore.

Use **AskUserQuestion** to ask:
> "Would you like to review learnings from this chore? This analyzes the session and diff to propose updates to CLAUDE.md, skills, or testing guidelines."

Options:
- **Yes, review learnings** — Invoke the `/review-learnings` skill
- **Skip** — No review needed

If the user chooses yes, invoke the Skill tool with `skill: "review-learnings"` and pass the ticket ID (e.g., `args: "ROO-XXX"`) so the commit message links back to the ticket. Any approved updates will be committed and pushed to the PR branch.

## Error Handling

- **Linear ticket not found**: Ask the user to verify the ticket ID
- **Branch already exists**: Ask the user whether to reuse it or create a fresh one
- **Worktree branch mismatch**: Warn the user and ask whether to proceed or switch
- **Tests fail for unrelated reasons**: Document the pre-existing failures and proceed
- **CI infrastructure failures**: Wait and retry once; if persistent, note in the PR and inform the user
- **Dependency conflicts**: Present the conflict to the user and ask for resolution preference

## Key Principles

1. **Understand before you change** — read the ticket fully, understand the scope, never guess at intent
2. **Tests where behavior changes** — not every chore needs new tests, but behavior changes always do
3. **Don't mix concerns** — a refactoring chore should not sneak in bug fixes or features
4. **Verify, don't assume** — run the full suite, check that tools work, confirm configs are valid
5. **Never commit to main** — always branch from `dev` or work in an existing worktree
6. **Use pnpm** — never `npm` or `yarn` (except in `amplify/` Lambda functions)
7. **Ask when uncertain** — use AskUserQuestion rather than making assumptions
