---
name: ticket
description: Create a Linear issue from a bug or feature description, asking clarifying questions to produce a well-structured ticket ready for /bugfix or /feature
argument-hint: "<description of the bug or feature>"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion, mcp__linear__create_issue, mcp__linear__list_teams, mcp__linear__list_issue_labels, mcp__linear__list_issue_statuses
model: sonnet
---

# Ticket Creation Workflow

Take a rough description of a bug or feature, ask clarifying questions, explore the codebase for context, and create a well-structured Linear issue ready to be picked up by `/bugfix` or `/feature`.

## User Input

```text
$ARGUMENTS
```

`$ARGUMENTS` should contain a natural-language description of the bug or feature. If empty or missing, use **AskUserQuestion** to ask the user to describe what they need.

## Phase 1: Understand the Request

1. **Read the description** from `$ARGUMENTS` carefully.

2. **Determine the type** — is this a bug or a feature?

   Signals it's a **bug**:
   - Describes something that's broken, wrong, or unexpected
   - References an error, crash, or incorrect behavior
   - Uses words like "broken", "fails", "wrong", "regression", "doesn't work"

   Signals it's a **feature**:
   - Describes something new to build
   - References a desired behavior that doesn't exist yet
   - Uses words like "add", "implement", "create", "support", "enable"

   If unclear, use **AskUserQuestion** to ask:
   > "Is this a bug (something broken that needs fixing) or a feature (something new to build)?"

3. **Extract what you can** from the description:
   - What is the problem or desired outcome?
   - What area of the app is affected?
   - Are there any specifics about reproduction steps, expected behavior, or scope?

## Phase 2: Explore the Codebase for Context

Before asking questions, do quick codebase exploration to inform smarter questions:

1. **Search for related code** based on keywords in the description:
   - Components, pages, or API routes mentioned
   - Feature areas referenced (e.g., "dashboard", "onboarding", "connections")
   - Error messages or behaviors described

2. **Understand the current state**:
   - What exists today related to this request?
   - What patterns does the codebase use in this area?
   - Are there related tests that reveal expected behavior?

3. **Check for related existing issues**:
   ```bash
   git log --oneline -20 --grep="<relevant keyword>"
   ```
   Look for recent commits that touch the same area.

This exploration helps you ask targeted questions rather than generic ones.

## Phase 3: Ask Clarifying Questions

Use **AskUserQuestion** to fill in gaps. Tailor questions to the type:

### For Bugs, clarify:
- **Reproduction steps**: "Can you walk me through how to trigger this? What page/action causes it?"
- **Expected vs actual**: "What should happen? What happens instead?"
- **Frequency**: "Does this happen every time, or intermittently?"
- **Environment**: "Is this on production, staging, or local dev?"
- **Severity**: "Is this blocking users, or is it a cosmetic/minor issue?"

### For Features, clarify:
- **User story**: "Who is this for and what's their goal?"
- **Acceptance criteria**: "How will we know this is done? What's the minimum viable version?"
- **Scope boundaries**: "What's explicitly NOT included in this ticket?"
- **Design**: "Are there mockups, or should this follow existing patterns?"
- **Edge cases**: "What should happen with empty states, errors, or unusual input?"
- **Priority**: "Is this blocking other work, or is it part of a larger initiative?"

### General guidelines:
- Batch related questions into a single **AskUserQuestion** call (up to 4 questions)
- Only ask questions whose answers you genuinely need — skip anything you can infer from the codebase
- If the description is already thorough, you may skip this phase or ask just 1-2 targeted questions
- Don't ask about implementation details (that's for `/bugfix` or `/feature` to figure out)

## Phase 4: Draft the Ticket

Compose the Linear issue content based on everything gathered.

### For Bugs:

- **Title**: Human-readable and outcome-focused. The title eventually ends up in standup updates and release notes, so it must read cleanly to non-engineers and end users.
  - Pattern: `<Area>: <plain-language description of the broken behavior>`
  - Plain language — avoid file names, class names, framework names, and internal project jargon
  - Frame it around the user experience, not the code path (e.g. "Dashboard: widget count shows stale data after refresh" — not "Dashboard: useWidgetStats hook returns cached value")
  - Brief — ideally fits on one release-note line
  - Examples: "Dashboard: widget count shows stale data after refresh", "Onboarding: Stripe checkout fails for annual plans"

- **Description**:
  ```markdown
  ## Bug Report

  **What's happening:**
  <Clear description of the broken behavior>

  **Expected behavior:**
  <What should happen instead>

  **Steps to reproduce:**
  1. <Step 1>
  2. <Step 2>
  3. <Step 3>

  **Environment:** <production/staging/local>

  **Severity:** <blocking/high/medium/low>

  ## Context
  <Any relevant codebase context discovered during exploration — affected files, recent related commits, existing test coverage>

  ## Acceptance Criteria
  - [ ] <Specific condition that must be true when fixed>
  - [ ] <Another condition>
  - [ ] Regression test added
  ```

### For Features:

- **Title**: Human-readable and outcome-focused. The title eventually ends up in standup updates and release notes, so it must read cleanly to non-engineers and end users.
  - Pattern: `<Area>: <plain-language description of the user-visible outcome>`
  - Plain language — avoid file names, class names, framework names, and internal project jargon
  - Frame it around what the user can now do, not the implementation (e.g. "Dashboard: allow widget reordering via drag-and-drop" — not "Dashboard: add useWidgetOrder hook and DnD provider")
  - Brief — ideally fits on one release-note line
  - Examples: "Connections: add TikTok analytics sync", "Dashboard: allow widget reordering via drag-and-drop"

- **Description**:
  ```markdown
  ## Feature Request

  **Goal:**
  <What user/business outcome this achieves>

  **User Story:**
  As a <role>, I want to <action> so that <benefit>.

  **Scope:**
  <What's included in this ticket>

  **Out of Scope:**
  <What's explicitly NOT included — save for follow-up tickets>

  ## Context
  <Relevant codebase context — existing patterns, related components, current state>

  ## Acceptance Criteria
  - [ ] <Specific condition that must be true when done>
  - [ ] <Another condition>
  - [ ] Tests added for new behavior
  - [ ] Visual verification completed (if UI change)

  ## Design Notes
  <Mockups, references to existing patterns, or "follow existing <component> pattern">

  ## Edge Cases
  - <Empty state>
  - <Error handling>
  - <Other edge cases>
  ```

## Phase 5: Confirm with User

Before creating the issue, present the draft to the user via **AskUserQuestion**:

- Show the proposed **title** and **type** (Bug/Feature)
- Summarize the **key points** of the description (don't dump the whole thing)
- Ask: "Does this look right? Anything to add or change before I create the ticket?"

Options:
- "Looks good, create it"
- "Needs changes" (user provides edits)
- "Let me rewrite the description" (user provides new text)

## Phase 6: Create the Linear Issue

Use `mcp__linear__create_issue` with:

- **Team**: `RootNote`
- **Title**: As drafted in Phase 4
- **Description**: As drafted in Phase 4
- **Labels**: `["Bug"]` for bugs, `["Feature"]` for features

## Phase 7: Report

After the issue is created, report:

1. **Ticket ID**: The `ROO-XXX` identifier
2. **Title**: The issue title
3. **Type**: Bug or Feature
4. **URL**: Link to the Linear issue
5. **Branch name**: The `branchName` from the Linear response (for use with `gww` or the `/bugfix`/`/feature` skills)
6. **Next step**: Suggest the appropriate follow-up:
   - For bugs: "Run `/bugfix ROO-XXX` to start fixing this"
   - For features: "Run `/feature ROO-XXX` to start building this"
