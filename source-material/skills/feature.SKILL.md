---
name: feature
description: Read a Linear ticket, understand the feature intent, ask clarifying questions, plan the implementation, then build with TDD, visual verification, Showboat docs, and PR
argument-hint: "<TICKET-ID e.g. ROO-123>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, Skill, mcp__linear__get_issue, mcp__linear__list_issues, mcp__linear__list_issue_statuses, mcp__linear__update_issue, mcp__linear__list_teams, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__new_page, mcp__chrome-devtools__list_pages, mcp__chrome-devtools__select_page, mcp__chrome-devtools__take_snapshot, mcp__chrome-devtools__wait_for, mcp__chrome-devtools__fill, mcp__chrome-devtools__click, mcp__chrome-devtools__evaluate_script
model: opus
---

# Feature Implementation Workflow

Read a Linear ticket, deeply understand the feature intent, ask clarifying questions, generate and confirm acceptance criteria with the user, design an implementation plan, then build with TDD (Red → Green → Refactor), visually verify, document via Showboat, create a PR targeting `dev`, and monitor CI until green.

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` must contain a Linear ticket ID (e.g., `ROO-123`). If empty or missing, use **AskUserQuestion** to ask for the ticket ID before proceeding.

## Phase 1: Read the Ticket & Understand the Feature

1. **Parse the ticket ID** from `$ARGUMENTS`:
   - Extract the ticket identifier (e.g., `ROO-123`)
   - Strip any URL prefix if the user pasted a full Linear URL

2. **Fetch the Linear ticket**:
   Use `mcp__linear__get_issue` with the ticket ID.

3. **Understand the feature** — read the ticket carefully and extract:
   - **Goal**: What is the user/business outcome this feature achieves?
   - **Scope**: What exactly needs to be built? What's explicitly out of scope?
   - **Acceptance criteria**: How do we know this is done?
   - **User stories**: Who benefits and how?
   - **Design references**: Any mockups, screenshots, or design links
   - **Dependencies**: Does this depend on other tickets or infrastructure?
   - **Edge cases**: What happens with empty states, errors, or unusual input?

4. **Explore the codebase** to understand the current state:
   - Search for existing components, services, or patterns related to the feature
   - Understand what already exists that can be reused or extended
   - Identify the files and modules that will need changes
   - Check for existing tests that cover related functionality

## Phase 2: Ask Clarifying Questions

**Do NOT proceed to planning until you fully understand the intent.** Use **AskUserQuestion** to resolve any ambiguity.

Ask about things like:
- **Unclear acceptance criteria**: "The ticket says 'improve the dashboard' — what specific metrics or layout changes are expected?"
- **Multiple valid interpretations**: "Should the filter apply client-side or server-side? Each has trade-offs."
- **Missing details**: "The ticket doesn't specify error states — what should happen when the API returns no data?"
- **Scope boundaries**: "Should this include mobile responsiveness, or is that a follow-up?"
- **Design decisions**: "There's no mockup — should I match the existing pattern in [component], or propose something new?"

Batch related questions into a single **AskUserQuestion** call when possible (up to 4 questions). Only proceed once you have enough clarity to plan confidently.

## Phase 3: Generate & Confirm Acceptance Criteria

Before planning implementation, define what "done" looks like. Use what you learned in Phases 1-2 to propose concrete, checkable acceptance criteria.

1. **Generate acceptance criteria** (typically 2-6) based on:
   - The feature's goal and scope from the ticket
   - Clarifications received from the user
   - Edge cases, error states, and empty states
   - Any criteria already stated in the ticket

   Each criterion should be a concrete, verifiable statement — something a reviewer can check yes/no. Examples:
   - "Users can filter the dashboard by date range using a date picker"
   - "Empty state shows a helpful message when no data matches the filter"
   - "Existing dashboard functionality is unaffected (no regressions)"

2. **Present the criteria to the user** via **AskUserQuestion**:

   Format as a checklist:
   ```
   Based on the ticket and our discussion, here are the proposed acceptance criteria:

   - [ ] <criterion 1>
   - [ ] <criterion 2>
   - [ ] ...

   Do these look right? Anything to add, remove, or change?
   ```

3. **Wait for confirmation** before proceeding. Incorporate any changes the user requests.

4. **Use the confirmed criteria to drive**:
   - The implementation plan (Phase 4)
   - Which tests to write (Phase 6)
   - What to verify visually (Phase 9)
   - The PR's test plan (handled by /prloop-enhanced in Phase 12)
   - The final report's acceptance criteria check (Phase 13)

## Phase 4: Plan the Implementation

Design a thorough implementation plan before writing any code.

1. **Identify all files that need changes**:
   - New files to create
   - Existing files to modify
   - Test files to create or extend

2. **Define the architecture**:
   - What components, hooks, services, or API routes are involved?
   - How does data flow through the feature?
   - What state management approach fits (Redux slice, local state, URL params)?
   - Are there database schema changes needed?

3. **Break into ordered steps**:
   - Each step should be independently testable
   - Dependencies between steps should be clear
   - Start with the foundation (schema, types, services) and build up to UI

4. **Identify risks and edge cases**:
   - What could go wrong?
   - What needs special handling (loading states, errors, empty states)?
   - Are there performance considerations?

5. **Present the plan to the user** via **AskUserQuestion**:
   - Summarize the approach in 3-5 bullet points
   - Call out any significant trade-offs or decisions
   - Ask: "Does this approach look right, or would you like me to adjust anything?"

Only proceed to implementation after the user confirms the plan.

## Phase 5: Set Up Branch or Worktree

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
   - Create a feature branch from `dev`:
     ```bash
     git checkout -b feat/<LINEAR_BRANCH_NAME> origin/dev
     ```
   - Use the `branchName` field from the Linear ticket if available. Otherwise construct from the ticket ID and a short description.

   **NEVER commit directly to `main` or `dev`.**

## Phase 6: Write Tests First (TDD Red Phase)

**Do NOT write any implementation code yet.** Tests come first.

1. **Determine the appropriate test types** using the testing pyramid:

   | Feature Layer | Test Type | Framework |
   |---|---|---|
   | Pure utility / helper | Unit test | Vitest |
   | React component (presentational) | Unit test + Storybook | Vitest + RTL |
   | React component (stateful/effects) | Unit test | Vitest + RTL |
   | Custom hook | Unit test | Vitest + renderHook |
   | API route / server action | Integration test | Vitest |
   | Database service / query | Integration test | Vitest |
   | Full user workflow | E2E test | Playwright |

   For features, you'll typically need **multiple test types** across layers. If unsure about the right mix, use **AskUserQuestion**.

2. **Create test files** following naming conventions:
   - Unit tests: `ComponentName.spec.tsx` or `utilityName.test.ts`
   - Integration tests: `feature.integration.spec.ts`
   - E2E tests: `/web/e2e/user-flow.spec.ts`

3. **Write the failing tests**:
   - Start with the most fundamental behavior (data layer, core logic)
   - Each test should describe one clear aspect of the expected feature behavior
   - Name tests descriptively: `it('should display the widget list when data loads', ...)`

4. **Run tests to confirm they fail** (Red):
   ```bash
   pnpm --filter @rootnote/web test:ci -- <path-to-test-file>
   ```
   Verify each test fails for the **right reason** — missing implementation, not setup errors.

## Phase 7: Implement the Feature (TDD Green Phase)

Build the feature incrementally, making tests pass one by one.

1. **Work bottom-up through the implementation plan**:
   - Start with data layer (schema, services, API routes)
   - Then business logic (hooks, utilities, state management)
   - Then UI (components, pages)

2. **For each piece of implementation**:
   - Write the code to make the next failing test pass
   - Run the specific test to confirm it passes (Green):
     ```bash
     pnpm --filter @rootnote/web test:ci -- <path-to-test-file>
     ```
   - Refactor if needed while keeping tests green

3. **If database schema changes are needed**:
   - Modify the schema in `/web/src/lib/db/schema.ts`
   - Generate migrations: `pnpm --filter @rootnote/web db:generate`
   - **NEVER manually create migration SQL files**
   - Run migrations locally: `pnpm --filter @rootnote/web db:migrate`

## Phase 8: Run Full Verification Suite

Run all checks to ensure nothing is broken. Execute these in parallel where possible:

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

## Phase 9: Visual Verification (agent-browser → chrome-devtools fallback)

If the feature has a browser-facing component, verify it visually. Skip this phase if the change is purely backend/logic with no UI impact.

### 9a: Read environment

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

### 9b: Ensure dev server is running

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

### 9c: Try agent-browser first

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

   If the feature involves a specific page, navigate there:
   ```bash
   agent-browser open http://localhost:${PORT}/<page>
   agent-browser wait load
   ```

   ```bash
   agent-browser wait 'body'
   agent-browser screenshot demos/${TICKET}-verify.png
   agent-browser close
   ```

3. **If agent-browser fails** at any step (not installed, errors), fall back silently to 9d.

### 9d: Fallback — chrome-devtools MCP

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

3. If the feature involves a specific page, navigate there with `mcp__chrome-devtools__navigate_page`
4. Use `mcp__chrome-devtools__wait_for` with `body`
5. Use `mcp__chrome-devtools__take_screenshot` to capture the page
6. Save screenshot to `demos/${TICKET}-verify.png`

## Phase 10: Showboat Documentation

1. **Check if Showboat is available**: `command -v showboat`

2. **Check for existing demo file**: `demos/${TICKET}.md`

3. **If Showboat is installed AND demo file exists**:
   ```bash
   showboat image demos/${TICKET}.md demos/${TICKET}-verify.png
   showboat note demos/${TICKET}.md "Visual verification completed — feature confirmed via [agent-browser|chrome-devtools]"
   ```

4. **If Showboat is installed but NO demo file exists**:
   - Initialize one for this feature:
     ```bash
     showboat init demos/${TICKET}.md "Feature: <brief feature description>"
     showboat note demos/${TICKET}.md "Implementation summary: <key changes made>"
     showboat image demos/${TICKET}.md demos/${TICKET}-verify.png
     showboat note demos/${TICKET}.md "Visual verification completed via [agent-browser|chrome-devtools]"
     ```

5. **If Showboat is not installed**, skip and just report the screenshot location.

## Phase 11: Local Iterative Review (MANDATORY before PR)

Run `/iterative-review` locally **before** handing off to `/prloop-enhanced`. This catches issues on cached local tokens and short wall time instead of paying the GH Action reviewer cycle cost (~5 min + non-cached tokens) for problems a local pass would find in under 2 minutes.

1. **Commit any in-flight implementation changes** so iterative-review operates on a stable diff:
   ```bash
   if [ -n "$(git status --porcelain)" ]; then
     # git add -A is intentional: a feature typically adds new files (tests, components,
     # migrations, stories) that git add -u would silently drop. This runs in a worktree
     # context, not at a user-facing boundary, so the risk of staging secrets is low.
     # If CLAUDE.md says "never git add -A", this is the exception.
     git add -A
     git commit -m "feat(<ticket-id from Phase 1>): <short description of implementation>"
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

4. **Record the iterative-review outcome** for the PR description. **Always pass a note in the Phase 12 handoff** — even on clean convergence — so prloop-enhanced's Preconditions block doesn't mis-classify this as a direct invocation and emit the "no handoff received" disclaimer:
   - If convergence was clean (all specialists converged, nothing skipped): `"iterative-review converged cleanly, no items skipped"`
   - If any specialist ended in `converged (clean-pass pending — iteration cap reached)` or `not converged (cap hit)`: describe the specifics (which specialist, which caveat) so /prloop-enhanced can include them in the PR body.

Only proceed to Phase 12 once iterative-review reports convergence (or the 4-iteration cap is reached with skipped items justified).

## Phase 12: Commit, PR, and CI Loop

Delegate the commit, push, PR creation, and CI monitoring to the `/prloop-enhanced` skill.

**Invoke the Skill tool** with `skill: "prloop-enhanced"` and provide context as arguments:
- The ticket ID (ROO-XXX)
- That the PR should target `dev`
- The commit message should use `feat(ROO-XXX): <description>` format
- A note that `/iterative-review` has already run locally (Phase 11), so prloop-enhanced can skip re-running it and go directly to simplification + reflection + PR creation
- The iterative-review outcome note from Phase 11 step 4 — either `"iterative-review converged cleanly, no items skipped"` on the happy path, or the specific convergence caveats / skipped findings. Without any note, prloop-enhanced's Preconditions block treats the run as a direct invocation and adds a "no handoff received" disclaimer to the PR body.

The prloop-enhanced skill will handle:
1. Code simplification (via the /simplify skill)
2. Implementation reflection (hardest decision, rejected alternatives, least confident areas)
3. Committing and pushing
4. Creating the PR with a comprehensive description including the reflection
5. Monitoring CI and addressing review feedback until green

**Wait for the skill to complete** before proceeding to the Report phase.

## Phase 13: Report

After all CI checks are green, provide a summary:

1. **Feature Summary**: What was built, in 2-3 sentences
2. **Implementation Approach**: Key architectural decisions made
3. **Files Changed**: List of modified/created files with brief descriptions
4. **Test Coverage Added**: What tests were written and what they verify
5. **Visual Verification**: Which tool was used (agent-browser or chrome-devtools), screenshot path, what was verified
6. **Showboat Demo**: Path to the demo doc (if created/updated), or note that it was skipped
7. **PR Link**: URL to the pull request
8. **CI Status**: Confirmation that all checks pass
9. **Notes**: Any caveats, follow-up work, or related issues discovered

## Phase 14: Refine Linear Title & Description for Release Notes

Linear titles are frequently auto-generated or written quickly, so they often read as technical shorthand ("Update AuthProvider to use React Context"). Before the PR merges, propose a version written for non-technical readers — teammates scanning standup updates and end users reading release notes. This phase runs **after the PR is green** so you have full context about what actually shipped.

0. Re-fetch the ticket: `mcp__linear__get_issue` with `<TICKET-ID>` to get the current description before constructing any update.

1. **Draft a human-readable title** describing the new state of the system from a user's perspective:
   - Outcome-focused (e.g. "Creators can now export their audience data", not "Add /export API route")
   - Plain language — avoid file names, class names, framework names, and internal project jargon
   - Brief — ideally fits on one release-note line
   - Prefer concrete outcome verbs over generic "update", "refactor", "fix", "add" when possible

2. **Draft a 1-2 sentence user-facing summary** suitable for release notes:
   - Describe what users can now do, or what no longer breaks, from their point of view
   - Skip implementation details (no "switched from X to Y", "extracted into Z hook")
   - If the change is purely internal with no user-visible impact, a summary may not be warranted — note that and offer "title only" below

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
   - `description: <updated description>` (when summary is being applied) — prepend a `## Summary` block at the top of the existing description so the original content (user story, scope, design notes, acceptance criteria) is preserved. If a `## Summary` block already exists at the top, replace its body rather than stacking a second one.

6. **If the user chooses "Skip"**, continue to the next phase without any Linear changes.

## Phase 15: Review Learnings (opt-in)

After the PR is green and ready to merge, offer to review what was learned during implementation.

Use **AskUserQuestion** to ask:
> "Would you like to review learnings from this implementation? This analyzes the session and diff to propose updates to CLAUDE.md, skills, or testing guidelines."

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

## Key Principles

1. **Understand before you build** — read the ticket fully, ask questions, never guess at intent
2. **Plan before you code** — present the approach for user approval before implementation
3. **Tests first, always** — no implementation without failing tests that define the expected behavior
4. **Minimal and focused** — build only what the ticket asks for, resist scope creep
5. **Never commit to main** — always branch from `dev` or work in an existing worktree
6. **Use pnpm** — never `npm` or `yarn` (except in `amplify/` Lambda functions)
7. **Ask when uncertain** — use AskUserQuestion rather than making assumptions
