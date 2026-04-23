---
name: followup
description: Capture a follow-up item surfaced during a PR, review, or investigation. Creates a Linear issue first (NEVER a bare beads issue), cross-links to the source PR, and optionally creates a linked beads issue for local execution tracking.
argument-hint: "<description of the follow-up, optionally: for ROO-xxxx or PR #nnnn>"
allowed-tools: Bash, Read, Grep, AskUserQuestion, mcp__linear__authenticate, mcp__linear__complete_authentication, mcp__linear__create_issue, mcp__linear__list_teams, mcp__linear__list_issue_labels
model: haiku
---

# Follow-up Capture

Capture a follow-up item with the **Linear-first** discipline: Linear issue is the source of truth; beads is an optional local execution view. Never create a bare beads issue for work that is not already tracked in Linear.

## User Input

```text
$ARGUMENTS
```

If `$ARGUMENTS` is empty, use **AskUserQuestion** to collect everything upfront (so Phase 1 step 3 doesn't need to re-ask):
1. What is the follow-up? (one-line title)
2. What's the context? (why is this a follow-up? which PR/ticket surfaced it?)
3. Should this be a standalone Linear issue, or added as a sub-bead under an existing ROO ticket?
4. If standalone: priority (P0–P4, default P3) and issue type (bug / task / feature).
5. **If the follow-up came from an inline PR review comment**, the comment ID (optional) — so Phase 3 can reply directly on that thread. Scan `$ARGUMENTS` first for either GitHub review-comment URL format; if present, capture the ID and don't ask:
   - Conversation tab: `.../pull/N#discussion_r<id>`
   - Files tab: `.../pull/N/files#r<id>`

   Both produce the same underlying comment ID. Match `(?:discussion_r|/files#r)(\d+)` and take the captured number.

If this intro block ran, Phase 1 step 3 SHOULD NOT ask again — use the collected title/priority/type directly.

## Phase 0: Linear Authentication Guard

Before any `mcp__linear__*` tool call, verify the MCP session is authenticated. Call `mcp__linear__authenticate` — if it returns an auth URL or indicates an unauthenticated state, present the URL to the user and wait for `mcp__linear__complete_authentication` before continuing. Skip this phase silently if auth is already established.

## Phase 1: Decide New Linear vs. Link to Existing

1. **Scan `$ARGUMENTS` for an existing ROO reference** (pattern `ROO-\d+`, case-insensitive — branch names in this repo are lowercase like `roo-1508`). If present, normalize to uppercase and treat that as the parent Linear issue — this follow-up is a decomposition, not a new issue.

2. **Scan for a PR reference** (pattern `#\d+` or a PR URL). If present, fetch the PR to extract its Linear ticket from the branch name or title:
   ```bash
   gh pr view <number> --json title,headRefName,body --jq '. | [.title, .headRefName, .body] | .[]' | grep -oiE 'ROO-[0-9]+' | tr '[:lower:]' '[:upper:]' | head -1
   ```
   The `-i` flag is critical — branch names are lowercase (`fix/roo-1508-...`), and without it the skill silently falls through and asks the user to create a new Linear issue when the parent is already unambiguously signaled by the branch. If found, the follow-up is a child of that ticket unless the user specifies otherwise.

3. **If no ROO reference is in scope**, the follow-up needs a new Linear issue. If the intro AskUserQuestion block above already collected title/priority/type (empty-args path), use those values directly and skip this step. Only call AskUserQuestion here when `$ARGUMENTS` was non-empty but missing priority/type.

## Phase 2: Create the Linear Issue (or skip if linking to existing)

If creating a new Linear issue:

1. Use `mcp__linear__list_teams` to find the correct team if not already known (Rootnote team typically).
2. Use `mcp__linear__create_issue` with:
   - **Title**: concise, action-oriented
   - **Description**: include:
     - **Context**: where this was surfaced (PR number, review round, investigation)
     - **What needs to happen**: specific work required
     - **Why it's a follow-up**: why it wasn't bundled into the original PR (scope, priority, risk)
   - **Priority**: from user input or P3 default for follow-ups
   - **Labels**: carry forward relevant labels from the parent ticket if applicable. Before passing label values to `create_issue`, call `mcp__linear__list_issue_labels` to resolve label names to IDs — Linear's API expects label IDs, not names.

3. Capture the new `ROO-xxxx` identifier.

If linking to an existing ROO issue: skip this phase. The bead(s) below will reference that ROO id.

## Phase 3: Cross-link to the Source

If the follow-up was surfaced from a PR:

1. Post a top-level PR comment via `gh pr comment <number> --body "<message>"` with the Linear URL:
   ```
   Follow-up tracked in ROO-xxxx: <linear url>
   ```

2. **If the follow-up was an inline review comment** and you captured its `comment_id` (from the PR review-comment API), also reply directly on that thread so the reviewer sees the acknowledgment where they left it. `gh pr comment` does NOT do this — it only creates top-level comments. Use the GitHub API instead. Derive `<owner>/<repo>` from the current repo:
   ```bash
   REPO_SLUG=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
   gh api "repos/${REPO_SLUG}/pulls/comments/<comment_id>/replies" \
     -f body="Follow-up tracked in ROO-xxxx: <linear url>"
   ```
   Note: the GitHub REST path for replying to a review comment is `/repos/{owner}/{repo}/pulls/comments/{comment_id}/replies` — there is NO `{pull_number}` segment in the reply path (only in the list-comments-for-a-PR endpoint). If no `comment_id` is available (e.g. the follow-up came from a Claude Code Review sticky comment, which is an issue-level comment not a review comment), the top-level PR comment in step 1 is sufficient.

## Phase 4: Create a Linked Beads Issue (optional)

Ask the user whether they want a beads issue for local execution tracking:

```
AskUserQuestion:
  "Create a beads issue that links to ROO-xxxx?"
  Options: yes / no / already has one
```

If yes:

```bash
bd create \
  --title="ROO-xxxx: <short title>" \
  --description="Linear: https://linear.app/<workspace>/issue/ROO-xxxx

<context + what needs to happen>" \
  --type=<task|bug|feature> \
  --priority=<0-4>
```

Requirements:
- **The bead title MUST start with `ROO-xxxx:`** so it's unambiguous that it links to a Linear issue.
- The bead description MUST include the full Linear URL.
- Multiple beads linking to the same ROO issue are fine and encouraged for decomposition — just prefix each bead title with the same `ROO-xxxx:`.

## Phase 5: Report

Report the outcome:

```
Follow-up captured:
- Linear: ROO-xxxx <title> <url>
- PR crosslink: <PR #nnnn commented / n/a>
- Bead: <bead-id> / none
```

## Anti-patterns (do NOT do these)

1. **Never** create a beads issue for a follow-up without first creating or identifying the parent Linear issue. Beads without `ROO-xxxx` in the title become a shadow backlog the team can't see.
2. **Never** silently close a review comment as "out of scope" without creating a follow-up. Out-of-scope comments that matter need a Linear issue.
3. **Never** create the Linear issue after pushing the fix commit — create it *before* or *at* the moment the follow-up is identified so cross-linking from the PR thread is trivial.
