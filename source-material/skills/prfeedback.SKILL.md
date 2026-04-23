---
name: prfeedback
description: Loop on PR review feedback from Claude reviewer and human reviewers, implementing suggestions until approval or no actionable items remain. Assumes a PR already exists.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Skill, Agent
model: sonnet
---

# PR Feedback Loop

React to and implement PR review feedback until the PR receives approval or no actionable feedback remains. This skill assumes the PR already exists and has been pushed.

## User Input

```text
$ARGUMENTS
```

Consider user input for any specific feedback to prioritize or instructions on scope.

## Phase 1: Establish Context

0. **Check for uncommitted changes** — a dirty working tree will cause problems during rebase in Phase 6:
   ```bash
   if [ -n "$(git status --porcelain)" ]; then
     echo "ERROR: Working tree has uncommitted changes. Commit or stash them before running /prfeedback."
     exit 1
   fi
   ```

1. **Verify a PR exists** for the current branch:
   ```bash
   gh pr view --json number,url,title,state -q '"\(.number) \(.url) \(.title) [\(.state)]"' || { echo "ERROR: No PR found for this branch. Create one first."; exit 1; }
   ```

2. **Capture PR number, repo slug, and base branch** for use throughout:
   ```bash
   PR_NUMBER=$(gh pr view --json number -q '.number')
   REPO_SLUG=$(gh repo view --json owner,name -q '"\(.owner.login)/\(.name)"')
   BASE=$(gh pr view --json baseRefName -q '.baseRefName')
   ```

3. **Get the current diff against the base branch** to understand what's in the PR:
   ```bash
   git diff $(git merge-base HEAD origin/${BASE})..HEAD --stat
   ```

## Phase 2: Collect All Feedback

Gather feedback from all sources before starting fixes. This avoids addressing one comment only to discover a related comment that would have changed the approach.

**CRITICAL: Always read the full Claude review comment.** The Claude Code Review action edits a single comment (not multiple). This comment can be very long (100+ lines). You MUST read the entire body on every invocation — never truncate with `head` or assume you already processed it from a prior cycle. A prior cycle may have truncated the read and missed items near the end.

### 2a: PR-Level Comments

```bash
# Claude Code Review action summary (posts as github-actions[bot])
# IMPORTANT: Do NOT pipe through head or truncate — read the full body every time.
# The Claude review edits a single long comment; items near the end are easy to miss.
gh pr view --json comments -q '.comments[] | select(.body | test("Code Review|Claude finished"; "i")) | .body'

# Formal reviews from humans (CHANGES_REQUESTED, COMMENTED — skip APPROVED and DISMISSED)
gh pr view --json reviews -q '.reviews[] | select(.state != "APPROVED" and .state != "DISMISSED") | "[\(.state)] \(.author.login): \(.body)"'
```

### 2b: All Inline Review Comments (single API call)

```bash
# Fetch all inline comments once — .user.login distinguishes Claude (github-actions[bot]) from humans
# Capture .id for replying to specific threads in Phase 5
gh api --paginate "repos/${REPO_SLUG}/pulls/${PR_NUMBER}/comments" --jq '.[] | "[id:\(.id)] [\(.path):\(.line // .original_line)] \(.user.login): \(.body)"'
```

### 2c: Check Current CI Status

```bash
gh pr checks
```

Note any failing checks — CI fixes are handled alongside feedback but feedback implementation takes priority since fixes often resolve CI issues too.

## Phase 3: Triage Feedback

Categorize each piece of feedback into one of these buckets:

| Category | Action | Examples |
|----------|--------|---------|
| **Bug / Correctness** | Always fix | Logic errors, missing null checks, wrong return type |
| **Security** | Always fix | Input validation, injection risks, exposed secrets |
| **Style / Nit** | Fix if straightforward | Naming, formatting, import ordering |
| **Simplification** | Fix if localized | Extract variable, inline unnecessary abstraction, reduce nesting |
| **Suggestion / Enhancement** | Fix if small and contained | Add a missing edge case test, improve an error message |
| **Comment wording / docs** | Skip unless from human reviewer | Rewording comments, adding clarifying docs, improving log messages. AI reviewers generate these endlessly — each round triggers more. Only fix if a human reviewer specifically requests it. |
| **Major refactor request** | Skip and explain | Rearchitect a module, change data model, rewrite a subsystem |
| **Factually incorrect** | Skip and explain | Reviewer misread the code, suggestion would introduce a bug |
| **Repeat / previously addressed** | Skip silently | Same concern raised in a prior round, already fixed or explained |

**Track comment IDs during triage.** Each inline comment from Phase 2 includes an `[id:XXXXX]` prefix. Preserve these IDs alongside each triaged item — they're needed as `COMMENT_ID` when replying to specific threads in Phase 5.

**Guiding principle:** Default to implementing feedback for bugs and correctness issues. Be more selective with style, documentation, and observability items — each push triggers a new review cycle, so low-value fixes compound into many wasted rounds. The bar for skipping is:
- **Always fix**: bugs, correctness, security, test fidelity
- **Fix if straightforward and won't trigger a new cycle**: style, simplification
- **Skip (explain on PR)**: comment rewording, documentation improvements, repeated concerns, suggestions requiring out-of-scope changes
- **Never fix**: factually incorrect suggestions

For anything skipped, reply on the PR explaining why.

## Phase 4: Implement Feedback

Work through the triaged feedback, grouping related items when possible.

### For each feedback item (or group):

1. **Read the relevant file(s)** to understand the current state
2. **Make the change** — keep it minimal and focused
3. **Verify the change** doesn't break anything:
   ```bash
   pnpm --filter @rootnote/web test:ci -- <relevant-test-file>
   ```
4. **Stage and commit** with a clear message:
   ```bash
   git add <changed-files>
   git commit -m "$(cat <<'EOF'
   fix: address review feedback - <brief description>

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```

### Commit strategy:
- **Group related feedback** into a single commit when the items touch the same file or concern
- **Separate unrelated feedback** into distinct commits for clean history
- **Never bundle bug fixes with style changes** in the same commit

## Phase 5: Comment on All Non-Trivial Decisions

Leave a PR comment for **every** feedback item where the response isn't a straightforward "done." This keeps the reasoning visible to reviewers.

### For skipped items (not implementing):

```bash
gh pr comment --body "$(cat <<'EOF'
Re: [brief description of suggestion]

**Not implementing** — [specific reason]. [Optional: what would need to change for this to be feasible, or suggest it as a follow-up.]
EOF
)"
```

### For items implemented with a different approach than suggested:

```bash
gh pr comment --body "$(cat <<'EOF'
Re: [brief description of suggestion]

**Addressed differently** — [what was done instead and why]. The reviewer's concern about [X] is valid, but [alternative approach] better fits because [reason].
EOF
)"
```

### For items where you disagree but implement anyway:

```bash
gh pr comment --body "$(cat <<'EOF'
Re: [brief description of suggestion]

**Implemented as suggested**, though I'd note [counterpoint or concern]. [Optional: flag if this might need revisiting.]
EOF
)"
```

### Comment guidelines:
- Keep explanations concise and technical — no defensiveness, just reasoning
- **For inline comments**, reply directly on the comment thread instead of a top-level PR comment:
  ```bash
  # Reply to a specific inline review comment by its ID
  gh api "repos/${REPO_SLUG}/pulls/comments/${COMMENT_ID}/replies" -f body="Your reply here"
  ```
  Get the comment ID from the feedback collection step (Phase 2) — it's in the API response.
- For straightforward fixes (typo, obvious bug, clear style improvement), no comment is needed — just fix it

## Phase 6: MANDATORY Local Iterative Review (HARD GATE — DO NOT SKIP)

**This phase is not optional.** Every push in this loop must be preceded by a local `/iterative-review` pass on the uncommitted or newly-committed changes. Skipping it defeats the entire point of running `/prfeedback` locally — each push triggers another GH Action review cycle (~5 min wall time + tokens), and the Action's reviewer routinely catches issues that four local specialist agents would have caught in parallel in under 2 minutes. **The loop converges in 1–2 round-trips with this gate; it takes 5+ round-trips without it.**

### Before every push, confirm:

```
[ ] /iterative-review has run since my last commit
[ ] All findings it surfaced are either fixed or explicitly skipped with justification
[ ] Lint + typecheck + tests are green locally
```

If the answer to any of these is "no" or "I don't remember", **run /iterative-review now before pushing**. Do not rationalize skipping it because "the changes are small" or "the reviewer will catch it" — the whole reason you're running `/prfeedback` is that the reviewer has *already* caught things, and this phase exists to break the cycle.

### Steps:

1. **Assemble a focus context from the PR feedback collected in Phase 2.** Summarize what the PR reviewers flagged — keep it tight (a handful of bullets is enough). Include:
   - The Claude Code Review action summary's top findings (from Phase 2a)
   - Human review bodies with `CHANGES_REQUESTED` / `COMMENTED` state (from Phase 2a)
   - Inline comment highlights with file:line anchors (from Phase 2b)
   - Which of those you triaged as "skipping" in Phase 3 — specialists should not re-surface those
   
   Do NOT paste raw 100+ line review bodies into args; distill to what would help a reviewer prioritize.

2. **Invoke iterative-review with that context.** Use the Skill tool with `skill: "iterative-review"` and pass the summary via `args`. Format:
   ```
   args: "Context: this review round follows PR feedback. Prior reviewer findings to prioritize:
   - [file:line] <what was flagged>
   - [file:line] <what was flagged>
   - ...
   Already triaged as skipped (do not re-raise): <bulleted skip list>
   Focus specialist attention on these areas first, but do not suppress unrelated findings."
   ```
   
   Iterative-review spawns four parallel specialist agents (generalist + scale + silent-failure + security) against the uncommitted/newly-committed diff, applies triaged fixes, and loops until convergence (cap: 4 iterations). The focus context biases specialists toward reviewer-flagged concerns without limiting their scope.

3. **If iterative-review made any commits**, no extra action needed — the loop already committed them. If iterative-review made uncommitted changes (edge case), commit them before proceeding:
   ```bash
   if [ -n "$(git status --porcelain)" ]; then
     git add -A
     git commit -m "fix: address issues found during local iterative review"
   fi
   ```
   Note: local checks (lint, typecheck, tests) are skipped here because `/iterative-review` already runs them internally after each fix.

4. **Verify convergence status** from iterative-review's final report. If any specialist ended in `converged (clean-pass pending — iteration cap reached)` or `not converged (cap hit)`, treat those lanes with extra skepticism in the next review cycle — they are likely where the GH Action reviewer will find something.

## Phase 7: Push and Verify

**Prerequisite**: Phase 6 (iterative-review) has completed since the most recent commit. Do not proceed to this phase without verifying the Phase 6 checklist.

1. **Push changes** (capture UTC time before push for later comment filtering):
   ```bash
   PUSH_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
   git push || {
     echo "Push failed — likely needs rebase onto origin/${BASE}"
     git fetch origin ${BASE}
     git rebase origin/${BASE} || {
       echo "Rebase has conflicts — aborting and flagging for human intervention"
       git rebase --abort
       echo "ERROR: Rebase conflicts detected. Please resolve manually."
       exit 1
     }
     # Re-run full local checks after rebase (rebase can break tests)
     pnpm lint:web --quiet && pnpm --filter @rootnote/web typecheck && pnpm test:ci:web
     git push
   }
   ```

2. **Wait for CI and new review cycle** — the push triggers a new Claude Code Review run. Wait for the new run to register before polling:
   ```bash
   # Give GitHub time to register the new push and start new CI runs
   sleep 15

   # Poll for Claude review (typically 2-5 minutes)
   for i in $(seq 1 20); do
     sleep 30
     CLAUDE_CHECK=$(gh pr checks 2>/dev/null | grep -i "claude" || true)
     if [ -z "$CLAUDE_CHECK" ]; then
       echo "No Claude review check found yet (${i}/20)"
       continue
     fi
     if echo "$CLAUDE_CHECK" | grep -qiE "pass|success"; then
       echo "Claude review passed: $CLAUDE_CHECK"
       break
     elif echo "$CLAUDE_CHECK" | grep -qiE "fail"; then
       echo "Claude review failed: $CLAUDE_CHECK"
       break
     fi
     echo "Waiting for Claude review to complete... (${i}/20)"
   done
   ```

3. **Read the new feedback.** IMPORTANT: Always read the **full** Claude review comment body — never truncate. The Claude Code Review action edits a single comment that can be 100+ lines. Items at the end are easily missed if piped through `head`.
   ```bash
   # Claude review comment — read FULL body (new or edited since push).
   # Do NOT truncate with head. The review is one long edited comment; items near the end matter.
   gh api --paginate "repos/${REPO_SLUG}/issues/${PR_NUMBER}/comments" \
     --jq ".[] | select(.body | test(\"Code Review|Claude finished\"; \"i\")) | select(.created_at > \"${PUSH_TIME}\" or .updated_at > \"${PUSH_TIME}\") | .body"

   # Inline review comments (new or edited since push)
   gh api --paginate "repos/${REPO_SLUG}/pulls/${PR_NUMBER}/comments" \
     --jq ".[] | select(.created_at > \"${PUSH_TIME}\" or .updated_at > \"${PUSH_TIME}\") | \"[id:\(.id)] [\(.path):\(.line // .original_line)] \(.user.login): \(.body)\""

   # Human reviews (new since push)
   gh pr view --json reviews -q ".reviews[] | select(.state != \"APPROVED\" and .state != \"DISMISSED\") | select(.submittedAt > \"${PUSH_TIME}\") | \"[\(.state)] \(.author.login): \(.body)\""
   ```

4. **Check CI status**:
   ```bash
   gh pr checks
   ```

## Phase 8: Loop or Complete

### Early exit — check for approval first:
```bash
APPROVED=$(gh pr view --json reviews -q '.reviews[] | select(.state == "APPROVED") | .author.login' 2>/dev/null)
if [ -n "$APPROVED" ]; then
  echo "PR approved by: $APPROVED"
  # Approval + green CI = done. Approval + red CI = continue fixing CI only (skip feedback collection).
fi
```

### If new actionable feedback exists:
- Return to **Phase 3** (triage) with only the new/unaddressed feedback
- Repeat the implement → push → verify cycle

### If CI checks are failing but no new review feedback:
- Investigate and fix CI failures:
  ```bash
  gh pr checks --json name,status,detailsUrl | jq -r '.[] | select(.status | ascii_downcase | test("fail")) | "\(.name): \(.detailsUrl)"'
  # Extract run ID from URL and view logs
  gh run view <run-id> --log-failed
  ```
- Fix, commit, push, and re-enter this phase

### If all checks pass AND no unaddressed feedback:
- The loop is **complete**. Report the final status:
  ```bash
  echo "=== PR Feedback Loop Complete ==="
  gh pr view --json number,url,title,state,reviews -q '"PR #\(.number): \(.title)\nURL: \(.url)\nState: \(.state)\nReviews: \(.reviews | map(.state) | join(", "))"'
  gh pr checks
  ```

## Termination Conditions

The loop ends when ANY of these are true:

1. **Approval received** — a reviewer has approved the PR and CI is green
2. **No actionable feedback remains** — all checks pass and the latest review cycle produced no new suggestions (or only items that were correctly skipped with explanations)
3. **Feedback is exclusively major refactor requests** — if all remaining feedback would require changes outside the PR's scope, explain this on the PR and exit

## Key Principles

1. **Iterative-review before every push is mandatory** — see Phase 6. Without it, the GH Action review cycle does the work of local specialist agents, at 3–10× the wall time and token cost. A single extra round-trip costs more than 10 full iterative-review runs.
2. **Default to implementing** — only push back with strong technical justification
3. **Nits are worth fixing** — small improvements compound into better code quality
4. **Read all feedback before acting** — avoid rework from addressing items in isolation
5. **Group related changes** — one commit per logical concern, not per comment
6. **Stay in scope** — fix what's reasonable, defer what would be a separate PR
7. **Explain skips, don't ignore** — every skipped item gets a reply
8. **Keep commits clean** — clear messages referencing what feedback was addressed
