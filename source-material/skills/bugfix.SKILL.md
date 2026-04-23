---
name: bugfix
description: Read a Linear ticket, diagnose root cause, generate and confirm acceptance criteria, write failing tests (TDD), implement the fix, visually verify with agent-browser/chrome-devtools, document via Showboat, and create a PR targeting dev
argument-hint: "<TICKET-ID e.g. ROO-123>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, Skill, mcp__linear__get_issue, mcp__linear__list_issues, mcp__linear__list_issue_statuses, mcp__linear__update_issue, mcp__linear__list_teams, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__new_page, mcp__chrome-devtools__list_pages, mcp__chrome-devtools__select_page, mcp__chrome-devtools__take_snapshot, mcp__chrome-devtools__wait_for, mcp__chrome-devtools__fill, mcp__chrome-devtools__click, mcp__chrome-devtools__evaluate_script
model: opus
---

# Bugfix Workflow

Read a Linear ticket, diagnose the root cause, generate and confirm acceptance criteria with the user, write failing tests first (TDD), implement the fix, visually verify with agent-browser (or chrome-devtools fallback), document via Showboat, create a PR targeting `dev`, and monitor CI until green.

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` must contain a Linear ticket ID (e.g., `ROO-123`). If empty or missing, use **AskUserQuestion** to ask for the ticket ID before proceeding.

## Phase 1: Read the Ticket & Understand the Problem

1. **Parse the ticket ID** from `$ARGUMENTS`:
   - Extract the ticket identifier (e.g., `ROO-123`)
   - Strip any URL prefix if the user pasted a full Linear URL

2. **Fetch the Linear ticket**:
   Use `mcp__linear__get_issue` with the ticket ID.

3. **Understand the bug** — read the ticket carefully and extract:
   - **What is broken**: The observable symptom
   - **Expected behavior**: What should happen instead
   - **Reproduction steps**: How to trigger the bug (if provided)
   - **Affected area**: Which feature/component is involved
   - **Relevant logs or screenshots**: Any attached evidence

4. **If the ticket is ambiguous**, use **AskUserQuestion** to clarify with the user rather than guessing at intent. Ask specific questions about:
   - Which behavior is considered correct
   - Whether there are edge cases to consider
   - Priority of the fix (does it need a hotfix approach?)

## Phase 2: Diagnose the Root Cause

Explore the codebase to identify the root cause. Do this thoroughly before writing any code.

1. **Locate relevant source files**:
   - Search for components, functions, or modules mentioned in the ticket
   - Check related test files to understand existing coverage
   - Review recent git history for changes that may have introduced the bug:
     ```bash
     git log --oneline -20 -- <relevant-paths>
     ```

2. **Trace the bug**:
   - Read the source files involved
   - Follow the code path from user action to the failure point
   - Identify the exact line(s) or logic causing the defect

3. **Document the root cause**:
   Write a concise root cause summary covering:
   - **What**: The specific code defect
   - **Where**: File(s) and line(s)
   - **Why**: How it got introduced or why it wasn't caught
   - **Impact**: What users experience

4. **Check for related issues**:
   - Are there other code paths with the same pattern?
   - Could this fix cause regressions elsewhere?

## Phase 3: Generate & Confirm Acceptance Criteria

Before writing any code, define what "done" looks like. Use what you learned in Phases 1-2 to propose concrete, checkable acceptance criteria.

1. **Generate acceptance criteria** (typically 2-6) based on:
   - The bug symptoms and root cause you identified
   - Edge cases revealed during diagnosis
   - Regression risks — what must NOT break
   - Any criteria already stated in the ticket

   Each criterion should be a concrete, verifiable statement — something a reviewer can check yes/no. Examples:
   - "Clicking 'Save' with an empty title no longer throws a 500 error"
   - "Existing widgets with null descriptions still render correctly"
   - "Unit test reproduces the original bug and passes after the fix"

2. **Present the criteria to the user** via **AskUserQuestion**:

   Format as a checklist:
   ```
   Based on the ticket and root cause analysis, here are the proposed acceptance criteria:

   - [ ] <criterion 1>
   - [ ] <criterion 2>
   - [ ] ...

   Do these look right? Anything to add, remove, or change?
   ```

3. **Wait for confirmation** before proceeding. Incorporate any changes the user requests.

4. **Use the confirmed criteria to drive**:
   - Which tests to write (Phase 5)
   - What to verify visually (Phase 8)
   - The PR's test plan (handled by /prloop-enhanced in Phase 11)
   - The final report's acceptance criteria check (Phase 12)

## Phase 4: Set Up Branch or Worktree

1. **Detect if already in a worktree**:
   ```bash
   # If .git is a file (not a directory), we're in a worktree
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
   - The user already ran `gww` or equivalent to set up this worktree
   - Verify the branch name relates to the ticket (contains the `ROO-XXX` pattern)
   - If it does: use the current branch as-is, no branch creation needed
   - If it doesn't: warn the user that the worktree branch doesn't match the ticket and ask how to proceed

   **If in the main repo** (`.git` is a directory):
   - Fetch latest: `git fetch origin dev`
   - Create a fix branch from `dev`:
     ```bash
     git checkout -b fix/<LINEAR_BRANCH_NAME> origin/dev
     ```
   - Use the `branchName` field from the Linear ticket if available. Otherwise construct from the ticket ID and a short description.

   **NEVER commit directly to `main` or `dev`.**

## Phase 5: Write Failing Tests First (TDD Red Phase)

**Do NOT write any implementation code yet.** Tests come first.

1. **Determine the appropriate test type** using the testing pyramid:

   | Bug Location | Test Type | Framework |
   |---|---|---|
   | Pure function / utility | Unit test | Vitest |
   | React component rendering | Unit test | Vitest + RTL |
   | API route / database service | Integration test | Vitest |
   | Full user workflow | E2E test | Playwright |

   If unsure which test type is appropriate, use **AskUserQuestion** to check with the user.

2. **Create the test file** (or add to an existing one):
   - Unit tests: `*.spec.ts` or `*.test.ts` alongside the source file
   - Integration tests: In the appropriate `__tests__` directory
   - E2E tests: In `/web/e2e/`

3. **Write the failing test**:
   - The test MUST reproduce the bug — it should fail for the same reason the bug occurs
   - Name the test descriptively: `it('should not crash when X is null', ...)`
   - Include edge cases if the bug reveals a pattern

4. **Run the test to confirm it fails** (Red):
   ```bash
   pnpm --filter @rootnote/web test:ci -- <path-to-test-file>
   ```
   Verify it fails for the **right reason** — the failure should match the bug, not be a setup error.

## Phase 6: Implement the Fix (TDD Green Phase)

1. **Write the minimum code** to make the failing test pass:
   - Fix only the identified defect
   - Do not refactor or improve surrounding code unless directly necessary
   - Keep the change focused and reviewable

2. **Run the test to confirm it passes** (Green):
   ```bash
   pnpm --filter @rootnote/web test:ci -- <path-to-test-file>
   ```

3. **Refactor if needed** (Refactor phase):
   - Only if the fix introduced duplication or unclear code
   - Keep tests green throughout

## Phase 7: Run Full Verification Suite

Run all checks to ensure nothing is broken. Execute these in parallel where possible:

```bash
# Run full test suite
pnpm test:ci:web

# Lint check
pnpm lint:web --quiet

# TypeScript compilation check
pnpm --filter @rootnote/web tsc --noEmit
```

- **If tests fail**: Diagnose whether the failure is related to your change or pre-existing. Fix related failures. For clearly unrelated flaky tests, note them and proceed.
- **If lint fails**: Fix lint errors in your changed files.
- **If TypeScript fails**: Fix type errors before proceeding.

## Phase 8: Visual Verification (agent-browser → chrome-devtools fallback)

If the bug has a browser-facing component, verify the fix visually. Skip this phase if the change is purely backend/logic with no UI impact.

### 8a: Read environment

1. **Parse PORT from `web/.env.local`**:
   ```bash
   grep '^PORT=' web/.env.local | cut -d= -f2
   ```
   Default to `3000` if not found.

2. **Parse ticket ID** (already known from Phase 1 — reuse the `ROO-XXX` value).

3. **Ensure `demos/` directory exists**:
   ```bash
   mkdir -p demos
   ```

4. **Read authentication credentials from `web/.env.local`**:
   ```bash
   TEST_EMAIL=$(grep '^TEST_USER_EMAIL=' web/.env.local 2>/dev/null | cut -d= -f2)
   TEST_PASSWORD=$(grep '^TEST_USER_PASSWORD=' web/.env.local 2>/dev/null | cut -d= -f2)
   ```
   If either is empty, warn: "TEST_USER_EMAIL or TEST_USER_PASSWORD not set in web/.env.local — proceeding without authentication. Screenshots will show the login page." Set `AUTH_AVAILABLE=false`.

5. **Check for cached Playwright auth state**:
   ```bash
   AUTH_FILE="web/e2e/.auth/user-0.json"
   if [ -f "$AUTH_FILE" ]; then
     AGE=$(( $(date +%s) - $(stat -c %Y "$AUTH_FILE" 2>/dev/null || stat -f %m "$AUTH_FILE") ))
     if [ $AGE -lt 3600 ]; then
       CACHED_AUTH=true
     else
       CACHED_AUTH=false
     fi
   else
     CACHED_AUTH=false
   fi
   ```
   Set `AUTH_AVAILABLE=true` if credentials were found.

### 8b: Ensure dev server is running

1. **Check if already responding**:
   ```bash
   curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}
   ```

2. **If not running**, start it in the background and poll up to 90s:
   ```bash
   pnpm dev:web &
   for i in $(seq 1 90); do
     STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT} 2>/dev/null)
     if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ] || [ "$STATUS" = "304" ]; then
       echo "Dev server ready after ${i}s"
       break
     fi
     sleep 1
   done
   ```
   If still not responding after 90s, warn the user and skip visual verification.

### 8c: Try agent-browser first

1. **Check availability**: `command -v agent-browser || npx agent-browser --help >/dev/null 2>&1`
   If using npx fallback, prefix all subsequent `agent-browser` commands with `npx`.
2. **If available**, run the verification flow:

   **Authenticate (if `AUTH_AVAILABLE=true`)**:

   If `CACHED_AUTH=true`, try cached auth first:
   ```bash
   agent-browser open http://localhost:${PORT}
   agent-browser wait load
   agent-browser eval "const s = $(cat web/e2e/.auth/user-0.json); (s.origins||[]).forEach(o => (o.localStorage||[]).forEach(i => localStorage.setItem(i.name, i.value)))"
   agent-browser reload
   agent-browser wait load
   agent-browser wait 2000
   ```
   Check URL — if it contains `/signin`, cached auth didn't work, fall through to form login.

   If still on `/signin` (or `CACHED_AUTH=false`), do form-based login:
   ```bash
   agent-browser open http://localhost:${PORT}/signin
   agent-browser wait 'input[type="email"], input[name="email"], [data-testid="signin-email"]'
   agent-browser fill 'input[type="email"], [data-testid="signin-email"]' "${TEST_EMAIL}"
   agent-browser fill 'input[type="password"], [data-testid="signin-password"]' "${TEST_PASSWORD}"
   agent-browser click 'button[type="submit"], [data-testid="signin-form"] button[type="submit"]'
   ```
   Wait for redirect away from `/signin` (up to 15s):
   ```bash
   for i in $(seq 1 15); do
     CURRENT_URL=$(agent-browser get url)
     if echo "$CURRENT_URL" | grep -qv '/signin'; then
       echo "Login successful"
       break
     fi
     sleep 1
   done
   ```
   If still on `/signin` after 15s, warn: "Authentication failed — proceeding with screenshot of current page."

   **Navigate and capture**:

   If the bug involves a specific page, navigate there:
   ```bash
   agent-browser open http://localhost:${PORT}/<page>
   agent-browser wait load
   ```

   ```bash
   agent-browser wait 'body'
   agent-browser screenshot demos/${TICKET}-verify.png
   agent-browser close
   ```

3. **If agent-browser fails** at any step (not installed, errors), fall back silently to 8d.

### 8d: Fallback — chrome-devtools MCP

Only if agent-browser was unavailable or failed:

1. Use `mcp__chrome-devtools__new_page` to open `http://localhost:${PORT}`

2. **Authenticate (if `AUTH_AVAILABLE=true`)**:

   If `CACHED_AUTH=true`, try cached auth first:
   - Use `mcp__chrome-devtools__evaluate_script` to inject localStorage from the cached Playwright auth state:
     ```javascript
     () => {
       const authState = <read and parse web/e2e/.auth/user-0.json>;
       (authState.origins || []).forEach(o => {
         (o.localStorage || []).forEach(item => localStorage.setItem(item.name, item.value));
       });
     }
     ```
   - Reload with `mcp__chrome-devtools__navigate_page` (type: `reload`)
   - Take a snapshot — if URL no longer contains `/signin`, auth succeeded

   If still on `/signin` (or `CACHED_AUTH=false`), do form-based login:
   - Navigate to `/signin` with `mcp__chrome-devtools__navigate_page`
   - Wait for the sign-in form with `mcp__chrome-devtools__wait_for` (text: "Sign In" or "Sign in")
   - Take a snapshot with `mcp__chrome-devtools__take_snapshot` to find form element UIDs
   - Use `mcp__chrome-devtools__fill` on the email input UID with `${TEST_EMAIL}`
   - Use `mcp__chrome-devtools__fill` on the password input UID with `${TEST_PASSWORD}`
   - Use `mcp__chrome-devtools__click` on the submit button UID
   - Wait for redirect: take a snapshot and verify the URL no longer contains `/signin`
   - If login fails after 15s, warn: "Authentication failed — proceeding with screenshot of current page."

3. If the bug involves a specific page, navigate there with `mcp__chrome-devtools__navigate_page`
4. Use `mcp__chrome-devtools__wait_for` with `body`
5. Use `mcp__chrome-devtools__take_screenshot` to capture the page
6. Save screenshot to `demos/${TICKET}-verify.png`

## Phase 9: Showboat Documentation

1. **Check if Showboat is available**: `command -v showboat`

2. **Check for existing demo file**: `demos/${TICKET}.md`

3. **If Showboat is installed AND demo file exists**:
   ```bash
   showboat image demos/${TICKET}.md demos/${TICKET}-verify.png
   showboat note demos/${TICKET}.md "Visual verification completed — bug fix confirmed via [agent-browser|chrome-devtools]"
   ```

4. **If Showboat is installed but NO demo file exists**:
   - Initialize one for this bugfix:
     ```bash
     showboat init demos/${TICKET}.md "Fix: <brief bug description>"
     showboat note demos/${TICKET}.md "Root cause: <root cause summary from Phase 2>"
     showboat image demos/${TICKET}.md demos/${TICKET}-verify.png
     showboat note demos/${TICKET}.md "Visual verification completed via [agent-browser|chrome-devtools]"
     ```

5. **If Showboat is not installed**, skip and just report the screenshot location.

## Phase 10: Local Iterative Review (MANDATORY before PR)

Run `/iterative-review` locally **before** handing off to `/prloop-enhanced`. This catches issues on cached local tokens and short wall time instead of paying the GH Action reviewer cycle cost (~5 min + non-cached tokens) for problems a local pass would find in under 2 minutes.

1. **Commit any in-flight fix changes** so iterative-review operates on a stable diff:
   ```bash
   if [ -n "$(git status --porcelain)" ]; then
     # git add -A is intentional: a bug fix may have added new test files (TDD Red phase
     # creates failing tests before the fix) that git add -u would silently drop. This runs
     # in a worktree context, not at a user-facing boundary, so the risk of staging secrets
     # is low. If CLAUDE.md says "never git add -A", this is the exception.
     git add -A
     git commit -m "fix(<ticket-id from Phase 1>): <short description of fix>"
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

4. **Record the iterative-review outcome** for the PR description. **Always pass a note in the Phase 11 handoff** — even on clean convergence — so prloop-enhanced's Preconditions block doesn't mis-classify this as a direct invocation and emit the "no handoff received" disclaimer:
   - If convergence was clean (all specialists converged, nothing skipped): `"iterative-review converged cleanly, no items skipped"`
   - If any specialist ended in `converged (clean-pass pending — iteration cap reached)` or `not converged (cap hit)`: describe the specifics (which specialist, which caveat) so /prloop-enhanced can include them in the PR body.

Only proceed to Phase 11 once iterative-review reports convergence (or the 4-iteration cap is reached with skipped items justified).

## Phase 11: Commit, PR, and CI Loop

Delegate the commit, push, PR creation, and CI monitoring to the `/prloop-enhanced` skill.

**Invoke the Skill tool** with `skill: "prloop-enhanced"` and provide context as arguments:
- The ticket ID (ROO-XXX)
- That the PR should target `dev`
- The commit message should use `fix(ROO-XXX): <description>` format and include the root cause
- A note that `/iterative-review` has already run locally (Phase 10), so prloop-enhanced can skip re-running it and go directly to simplification + reflection + PR creation
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

1. **Root Cause**: Concise explanation of the bug's cause
2. **Files Changed**: List of modified files with brief descriptions
3. **Test Coverage Added**: What tests were written and what they verify
4. **Visual Verification**: Which tool was used (agent-browser or chrome-devtools), screenshot path, what was verified
5. **Showboat Demo**: Path to the demo doc (if created/updated), or note that it was skipped
6. **PR Link**: URL to the pull request
7. **CI Status**: Confirmation that all checks pass
8. **Notes**: Any caveats, related issues discovered, or follow-up work needed

## Phase 13: Refine Linear Title & Description for Release Notes

Linear titles for bugs are often written mid-incident and read as technical shorthand ("Null activeView.config crash in creators-summary HYDRATE"). Before the PR merges, propose a version written for non-technical readers — teammates scanning standup updates and end users reading release notes. This phase runs **after the PR is green** so you have full context about what actually shipped.

0. Re-fetch the ticket: `mcp__linear__get_issue` with `<TICKET-ID>` to get the current description before constructing any update.

1. **Draft a human-readable title** describing the fixed behavior from a user's perspective:
   - Outcome-focused (e.g. "Saved dashboard views no longer crash on load", not "Guard activeView.config in HYDRATE extraReducer")
   - Plain language — avoid file names, class names, framework names, and internal project jargon
   - Brief — ideally fits on one release-note line
   - Frame it as the resolved state ("X no longer fails when…", "Y now loads correctly on…")

2. **Draft a 1-2 sentence user-facing summary** suitable for release notes:
   - Describe what users will no longer experience, or what now works as expected
   - Skip implementation details (no "added null guard", "normalized config shape")
   - If the bug was purely internal with no user-visible impact, a summary may not be warranted — note that and offer "title only" below

3. **Show the user the current vs proposed values** and use **AskUserQuestion** to ask how to proceed. Format the question body so they can compare:
   ```
   Current title: <original>
   Proposed title: <human-readable version>

   Current description (top): <first line or two>
   Proposed summary to prepend: <1-2 sentence user-facing summary>
   ```
   Options:
   - "Apply both" — update title and prepend the summary to the description
   - "Apply title only" — update just the title, leave description unchanged
   - "Edit first" — user wants to tweak the wording before applying
   - "Skip" — keep the Linear issue as-is

4. **If the user chooses "Edit first"**, collect the preferred wording (ask follow-up questions as needed) then apply their version.

5. **If applying changes**, call `mcp__linear__update_issue` with:
   - `id: <TICKET-ID>`
   - `title: <accepted title>` (when title is being updated)
   - `description: <updated description>` (when summary is being applied) — prepend a `## Summary` block at the top of the existing description so the original content (repro steps, root cause notes, acceptance criteria) is preserved. If a `## Summary` block already exists at the top, replace its body rather than stacking a second one.

6. **If the user chooses "Skip"**, continue to the next phase without any Linear changes.

## Phase 14: Review Learnings (opt-in)

After the PR is green and ready to merge, offer to review what was learned during the bugfix.

Use **AskUserQuestion** to ask:
> "Would you like to review learnings from this bugfix? This analyzes the session and diff to propose updates to CLAUDE.md, skills, or testing guidelines."

Options:
- **Yes, review learnings** — Invoke the `/review-learnings` skill
- **Skip** — No review needed

If the user chooses yes, invoke the Skill tool with `skill: "review-learnings"` and pass the ticket ID (e.g., `args: "ROO-XXX"`) so the commit message links back to the ticket. Any approved updates will be committed and pushed to the PR branch.

## Error Handling

- **Linear ticket not found**: Ask the user to verify the ticket ID
- **Branch already exists**: Ask the user whether to reuse it or create a fresh one
- **Tests fail for unrelated reasons**: Document the pre-existing failures and proceed with the fix
- **CI infrastructure failures**: Wait and retry once; if persistent, note in the PR and inform the user

## Key Principles

1. **Understand before you fix** — read the ticket fully, diagnose the root cause, never guess at intent
2. **Tests first, always** — no implementation without a failing test that reproduces the bug
3. **Minimal changes** — fix only the bug, resist the urge to refactor or improve surrounding code
4. **Never commit to main** — always branch from `dev`
5. **Use pnpm** — never `npm` or `yarn` (except in `amplify/` Lambda functions)
6. **Ask when uncertain** — use AskUserQuestion rather than making assumptions about ambiguous requirements
