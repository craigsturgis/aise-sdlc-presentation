---
name: sentry-fix
description: Browse Sentry issues, select one to fix, create a Linear issue, set up a worktree, and start fixing
argument-hint: "[project-slug]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, mcp__linear__create_issue, mcp__linear__get_issue, mcp__linear__list_teams
model: opus
---

# Sentry Issue Fix Workflow

You are executing an automated workflow to:
1. Select a Sentry project to check for issues
2. Browse unresolved issues and select one to fix
3. Analyze it and create a human-readable problem description
4. Create a Linear issue to track the fix
5. Create a git worktree for the fix
6. Begin implementing a solution

## Configuration

- **Sentry Organization**: `<your-org-slug>`
- **Default Sentry Project**: `javascript-nextjs` (can be overridden via `$ARGUMENTS`)
- **Linear Team**: `RootNote`
- **Worktree Script**: `~/src/util-scripts/git-worktree-warp`

## Prerequisites

Before running this skill, ensure:
- `sentry-cli` is installed and configured with access to the `<your-org-slug>` organization
- Linear MCP is properly configured with workspace access
- The `git-worktree-warp` script exists at the configured path

## User Input

```text
$ARGUMENTS
```

If `$ARGUMENTS` is provided and non-empty, use it as the Sentry project slug to skip project selection.

## Workflow Steps

### Step 0: Validate Environment

Before proceeding, verify the environment is properly configured:

1. Check sentry-cli access: `sentry-cli info`

If validation fails, inform the user what's missing and stop.

### Step 1: Select Sentry Project

If a project slug was provided via `$ARGUMENTS`, use it directly and skip to Step 2.

Otherwise, fetch the list of available projects:

```bash
sentry-cli projects list -o <org>
```

Present the projects to the user using **AskUserQuestion**:
- Show project name/slug
- Let user select which project to check for issues

Available projects (for reference):
- `javascript-nextjs` - Next.js frontend errors
- `node-awslambda` - Lambda function errors
- `batch-jobs` - Batch job errors
- `rootnote-api` - API errors

### Step 2: Fetch Unresolved Sentry Issues

Use the Sentry API to get detailed issue information including event counts:

```bash
curl -s -H "Authorization: Bearer $(grep token ~/.sentryclirc | cut -d= -f2)" \
  "https://sentry.io/api/0/projects/<org>/<PROJECT>/issues/?query=is:unresolved+environment:production&limit=10" | \
  jq '.[] | {id, shortId, title, count, firstSeen, lastSeen, level, priority, userCount}'
```

Parse the JSON output to extract for each issue:
- **ID**: The numeric issue ID
- **Short ID**: The human-readable ID (e.g., `JAVASCRIPT-NEXTJS-15`)
- **Title**: The error message/title
- **Count**: Number of times this error has occurred
- **First Seen**: When this error first appeared
- **Last Seen**: Most recent occurrence
- **Level**: error/warning
- **Priority**: high/medium/low
- **User Count**: Number of affected users

If no unresolved issues are found, inform the user and stop.

### Step 3: Present Issues for Selection

Display the issues in a formatted table showing key metrics:

```
| # | Issue ID              | Title (truncated)           | Events | Users | Last Seen    | Priority |
|---|----------------------|-----------------------------| ------:|------:|--------------|----------|
| 1 | JAVASCRIPT-NEXTJS-15 | <unknown>                   |    316 |    15 | 2 hours ago  | high     |
| 2 | JAVASCRIPT-NEXTJS-RQ | TypeError: Load failed      |     22 |     0 | 5 hours ago  | high     |
| 3 | JAVASCRIPT-NEXTJS-RT | TypeError: null is not...   |      8 |     0 | 5 hours ago  | high     |
```

Then use **AskUserQuestion** to let the user select which issue to work on:
- Present options based on the issue short IDs
- Include a brief description showing the error title and event count
- Allow the user to select one issue

### Step 4: Get Selected Issue Details

For the selected issue, construct the Sentry URL:
- URL pattern: `https://<org>.sentry.io/issues/<ISSUE_ID>/`

Use this information along with the title to understand the problem.

### Step 5: Analyze and Create Human-Readable Title

Based on the Sentry issue information:

1. **Understand the error**: Analyze the error title/message
2. **Create a descriptive title**: Write a clear, actionable title that describes:
   - What is failing (component/feature)
   - The type of error (TypeError, null reference, load failure, etc.)
   - Where it's happening if known

Examples:
- `TypeError: Load failed` -> "Fix network request load failure in client"
- `TypeError: null is not an object (evaluating 'localStorage.setItem')` -> "Fix localStorage null reference error"
- `<unknown>` -> "Investigate unknown error in [component]"

### Step 5.5: Five Whys Root Cause Analysis

Before creating the Linear issue, perform a **Five Whys** analysis to identify the root cause. This ensures we fix the actual problem, not just the symptom.

#### Procedure:

1. **Establish the problem statement** from the Sentry error information

2. **Search the codebase** for relevant code:
   - Look for the component/function mentioned in the stack trace
   - Find related error handling and edge cases
   - Check recent changes in git history that might be related

3. **Conduct the Why iterations**:

   For each "Why", investigate the codebase and document:
   ```
   **Why #N**: [Question based on previous answer]
   **Investigation**: [Files/code examined]
   **Answer**: [Factual answer with evidence]
   ```

4. **Identify the root cause**:
   - What is the fundamental reason this error occurs?
   - What contributing factors made this possible?
   - Is this a code bug, missing validation, architecture issue, or process gap?

5. **Document recommendations**:
   - **Immediate fix**: What resolves the symptom
   - **Root cause fix**: What prevents recurrence
   - **Prevention**: Process/tooling improvements

#### Example for Sentry Issue:

**Problem**: "TypeError: Cannot read property 'id' of undefined in UserProfile component"

| # | Why? | Answer |
|---|------|--------|
| 1 | Why is the property undefined? | The `user` object is null when the component renders |
| 2 | Why is `user` null? | The API call hasn't completed before the component mounts |
| 3 | Why does it render before data loads? | No loading state check before accessing user properties |
| 4 | Why no loading check? | The component was refactored and the guard was removed |

**Root Cause**: Missing null/loading guard after component refactoring

#### Handling Inconclusive Analysis

If the Five Whys analysis doesn't reach a clear root cause:

1. **Document partial findings**: What you discovered is still valuable
2. **List open questions**: What information is missing to continue?
3. **Mark as "Investigation Needed"**: Add label to Linear issue indicating further debugging is required
4. **Suggest next steps**: What logs, metrics, or reproduction steps would help?

Don't force a conclusion - an honest "needs more investigation" is better than a speculative root cause.

#### Output:

Generate a structured summary to include in the Linear issue description. This analysis will be embedded in the issue description in Step 6.

### Step 6: Create Linear Issue

Use the Linear MCP to create an issue with:

- **Team**: `RootNote`
- **Title**: Prefix with "(Sentry reported) " followed by the human-readable title you created (e.g., "(Sentry reported) Fix localStorage null reference error")
- **Description**: Include:
  ```markdown
  ## Sentry Issue
  - **Sentry ID**: [SHORT_ID]
  - **Sentry URL**: https://<org>.sentry.io/issues/[ISSUE_ID]/
  - **Error**: [Original error title]
  - **Level**: [error/warning]
  - **Events**: [count] occurrences
  - **Users Affected**: [userCount]
  - **First Seen**: [firstSeen timestamp]
  - **Last Seen**: [lastSeen timestamp]

  ## Five Whys Analysis

  ### Problem Statement
  [Clear description of the observable problem from Sentry]

  ### Analysis Chain

  | # | Why? | Answer |
  |---|------|--------|
  | 1 | [Initial problem] | [First-level cause] |
  | 2 | Why [first-level cause]? | [Second-level cause] |
  | ... | ... | ... |

  ### Root Cause
  [The fundamental cause identified in Step 5.5]

  ## Recommendations

  **Immediate Fix:**
  [What to do now to resolve the symptom]

  **Root Cause Fix:**
  [What to change to prevent recurrence]

  **Prevention:**
  [Process/tooling improvements to catch similar issues]
  ```
- **Labels**: `["Bug"]`

After creating the issue, note the returned `gitBranchName` from the Linear issue response (e.g., `roo-691-upgrade-button-redirects-to-billing-settings`).

### Step 7: Create Git Worktree

Use the `git-worktree-warp` script to create a new worktree:

```bash
~/src/util-scripts/git-worktree-warp "fix/<LINEAR_BRANCH_NAME>"
```

Where `<LINEAR_BRANCH_NAME>` is the branch name from the Linear issue (e.g., `roo-123-fix-localstorage-null-reference`).

**Important**: The script outputs the worktree path. Capture this path for the next step.

### Step 8: Report Setup Complete & Begin Analysis

After setup is complete, report:

1. **Summary of what was created**:
   - Sentry issue being addressed
   - Linear issue ID and URL
   - Worktree location and branch name

2. **Begin investigating the fix**:
   - Search the codebase for relevant code related to the error
   - Identify the root cause
   - Propose a solution approach
   - If you have high confidence, start implementing the fix following TDD practices

## Error Handling

- If `sentry-cli` fails, check if the project slug is correct
- If Linear issue creation fails, report the error and continue with manual instructions
- If worktree creation fails (e.g., branch already exists), suggest alternatives

## Notes

- Always follow TDD: write a failing test first before implementing the fix
- Check CLAUDE.md for project-specific testing and development guidelines
- The worktree will be created in `../rootnote-worktrees/fix/<branch-name>`
