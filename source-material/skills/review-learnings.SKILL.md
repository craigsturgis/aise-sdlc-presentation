---
name: review-learnings
description: Review learnings from completed work and propose updates to CLAUDE.md, skills, and testing approach. Filters for compounding value only.
argument-hint: "[TICKET-ID or description — optional]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion
model: opus
---

# Review Learnings

Analyze the implementation from a completed ticket, identify reusable learnings, and propose targeted updates to CLAUDE.md, skill definitions, or testing guidelines. Only propose changes that compound over time — skip one-off fixes and ticket-specific details.

## User Input

```text
$ARGUMENTS
```

Optional: a ticket ID or description of the work to review. If empty, the skill reviews the current branch diff against `origin/dev`.

## Phase 1: Gather Context

1. **Fetch latest remote refs** and **get the full diff** of work done on this branch:
   ```bash
   git fetch origin dev
   git diff $(git merge-base HEAD origin/dev)..HEAD
   ```

2. **Get the commit history** for this branch:
   ```bash
   git log --oneline $(git merge-base HEAD origin/dev)..HEAD
   ```

3. **Read the full session log** to understand the journey — decisions made, problems hit, approaches tried and abandoned:
   ```bash
   # Find the current project's session log (most recent JSONL file)
   # Note: Claude Code session dirs use leading dash (e.g., -Users-foo-src-project)
   PROJECT_DIR=$(echo "$PWD" | sed 's|/|-|g')
   SESSION_DIR="$HOME/.claude/projects/${PROJECT_DIR}"
   SESSION_FILE=$(ls -t "${SESSION_DIR}"/*.jsonl 2>/dev/null | head -1)
   ```
   If a session file exists (`[ -n "${SESSION_FILE}" ] && [ -f "${SESSION_FILE}" ]`), **read the entire file** using the Read tool with a high `limit` (e.g., `limit: 50000`) to avoid the default 2000-line truncation. Session logs are JSONL (one JSON object per line) and typically 1-3 MB — well within context limits.

   If no session file exists, skip this step — the diff and commit history alone are still valuable.

   **What to look for** in the session log:
   - **User messages and assistant responses** (type: "user" and "assistant") — these reveal intent, clarifications, and decisions
   - **Tool call failures and retries** — these reveal gotchas worth documenting
   - **Approach changes** — places where the initial approach was abandoned for a better one

   **What to mentally filter out** (most of the file by volume):
   - Tool results containing full file contents (type: "tool_result") — ~75% of the file, mostly noise
   - Repeated system-reminder blocks listing available skills
   - Pre-commit hook output and lint warnings

   Focus on extracting the *why* behind decisions, not the mechanical steps. The session log captures context that the diff alone cannot — such as why a particular approach was chosen over alternatives, what error led to a workaround, or what the user explicitly asked for that isn't obvious from the code.

4. **Read the current CLAUDE.md files and rules**:
   The project's guidance is split across multiple files. Read the ones relevant to the work done:
   - Root `CLAUDE.md` — always read (project overview, common commands, code quality rules)
   - `.claude/rules/` directory — list files and read any relevant to the work:
     - `testing.md` — TDD, testing pyramid, test type selection
     - `pg-migration.md` — PG migration patterns, PG flag gotchas
     - `security.md` — credentials, PII logging, secret handling
     - `pre-implementation-review.md` — pre-coding checklist for write paths
     - `visual-verification.md` — Showboat, agent-browser demos
   - Subdirectory CLAUDE.md files — read if the work touched those areas:
     - `services/rootnote-api/CLAUDE.md` — API service config
     - `services/batch-jobs/CLAUDE.md` — ECS scheduled jobs, JOB_NAME dispatch
     - `packages/sync-core/CLAUDE.md` — platform adapter patterns
     - `amplify/CLAUDE.md` — Amplify env vars, team-provider-info
     - `infrastructure/CLAUDE.md` — Terragrunt, ECS, bastion

5. **Read relevant skill files**:
   - Read `.claude/skills/feature/SKILL.md`
   - Read `.claude/skills/bugfix/SKILL.md`
   - Read `.claude/skills/chore/SKILL.md`
   - Read any other skill files that were touched or are relevant to the work done

## Phase 2: Identify Learnings

Analyze the diff, commits, session log, and implementation decisions to identify learnings in three categories. The session log is especially valuable for surfacing learnings that the diff alone cannot reveal — failed approaches, surprising behaviors, and the reasoning behind non-obvious decisions.

### Category A: CLAUDE.md Updates
Look for learnings that would belong in the project-wide development guide:
- **New gotchas**: Did you hit an issue that would trip up anyone working in this area? (e.g., "DynamoDB GSI queries are eventually consistent — use direct ID lookups for newly created records")
- **Corrected assumptions**: Did the code behave differently than expected based on existing docs?
- **New patterns**: Did you establish a new pattern that should be followed consistently? (e.g., a new API convention, a new way to handle auth)
- **Tool/command updates**: Did you discover a command variant or tool behavior worth documenting?

### Category B: Skill Improvements
Look for ways the workflow skills could work better:
- **Missing steps**: Did you have to do something manually that should be part of the skill workflow?
- **Wrong order**: Would a different phase ordering have been more efficient?
- **Better defaults**: Should a skill make a different assumption by default?
- **Error handling gaps**: Did you hit a situation the skill doesn't handle?

### Category C: Testing Approach Changes
Look for testing insights:
- **Test type mismatches**: Was the testing pyramid guidance wrong for this case?
- **Missing test patterns**: Is there a type of test that should be recommended but isn't?
- **Framework gotchas**: Did you discover a testing framework behavior worth documenting?
- **Coverage gaps**: Did the existing test strategy miss something important?

## Phase 3: Filter for Compounding Value

For each potential learning, apply this filter — **only keep learnings where you can answer YES to at least 2 of these**:

1. **Recurrence**: Would this come up again on 3+ future tickets?
2. **Non-obvious**: Would a developer familiar with the codebase NOT already know this?
3. **Actionable**: Can this be expressed as a concrete instruction or guideline?
4. **Not already documented**: Is this genuinely missing from CLAUDE.md or the relevant skill?

**Discard** anything that is:
- Specific to this one ticket with no broader applicability
- Already documented somewhere (even if in a different section)
- A general programming best practice (e.g., "write good tests")
- A temporary workaround that will be removed soon
- Too verbose or complex to express concisely

## Phase 4: Propose Updates

If there are learnings that pass the filter, present them to the user organized by target file.

For each proposed update, show:
- **What**: The specific text to add or change
- **Where**: The exact file and section — route to the correct file based on topic:
  - Testing patterns → `.claude/rules/testing.md`
  - PG migration / API data patterns → `.claude/rules/pg-migration.md`
  - Security / credentials / PII → `.claude/rules/security.md`
  - Pre-implementation review steps → `.claude/rules/pre-implementation-review.md`
  - Visual verification / Showboat → `.claude/rules/visual-verification.md`
  - Sync-core / platform adapters → `packages/sync-core/CLAUDE.md`
  - rootnote-api service → `services/rootnote-api/CLAUDE.md`
  - Batch jobs / ECS scheduled tasks → `services/batch-jobs/CLAUDE.md`
  - Amplify / env vars → `amplify/CLAUDE.md`
  - Infrastructure / Terragrunt → `infrastructure/CLAUDE.md`
  - General / cross-cutting → root `CLAUDE.md`
- **Why**: Brief explanation of the compounding value

Use **AskUserQuestion** to present the proposals:

```
Based on the work on this branch, I identified the following learnings worth capturing:

### CLAUDE.md Updates
1. [description of update] — *Why: [compounding value]*

### Skill Updates
1. [skill name]: [description of update] — *Why: [compounding value]*

### Testing Approach
1. [description of update] — *Why: [compounding value]*

Which of these should I apply?
```

Offer these options:
- **Apply all** — Apply every proposed update
- **Select which to apply** — Let me choose (present each individually)
- **Skip all** — No updates needed, the current docs are fine

If the user selects individual updates, present each one with a yes/no choice.

## Phase 5: Apply Approved Updates

For each approved update:

1. **Read the target file** to find the right insertion point
2. **Make the edit** using the Edit tool — insert the new guidance in the most logical section
3. **Keep it concise** — each addition should be 1-3 lines. If it needs more, it's too complex
4. **Match the existing style** of the target file (formatting, tone, structure)

After applying all updates, stage only the specific files that were edited (track which files you modified during the apply loop) and commit:
```bash
git add <list of specific files modified, e.g. CLAUDE.md .claude/skills/bugfix/SKILL.md>
git commit -m "docs(<TICKET-ID if available>): apply review-learnings updates"
git push origin HEAD
```

Then show a summary:
```
Applied N updates:
- CLAUDE.md: [brief description of each change]
- .claude/skills/[name]/SKILL.md: [brief description]
```

## Phase 6: Report

If no learnings passed the filter:
```
No compounding learnings identified from this change. The existing documentation covers the patterns used here well.
```

If learnings were found and applied:
```
Applied N learnings from this implementation:
- [list of what was updated and why]

These changes will help with future [feature/bugfix/chore] work in [affected areas].
```

## Key Principles

1. **Less is more** — one high-value update is better than five marginal ones
2. **Compounding value only** — if it won't help on 3+ future tickets, skip it
3. **Concise additions** — each update should be 1-3 lines, not paragraphs
4. **User approval required** — never auto-apply updates to CLAUDE.md or skills
5. **Match existing style** — additions should feel native to the target file
6. **No ticket-specific details** — learnings should be generalized, not "when working on ROO-123..."
