---
name: five-whys
description: Perform a Five Whys root cause analysis to identify the true source of a bug or issue
argument-hint: "[problem statement or issue description]"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
model: opus
---

# Five Whys Root Cause Analysis

You are executing a structured root cause analysis using the **Five Whys** technique. This method helps identify the underlying cause of a problem by iteratively asking "Why?" until the root cause is uncovered.

## Purpose

The Five Whys technique:
- Prevents fixing symptoms instead of root causes
- Uncovers systemic issues that could cause similar bugs
- Provides a clear chain of reasoning for documentation
- Helps identify preventive measures

## User Input

```text
$ARGUMENTS
```

**Input Validation**: If `$ARGUMENTS` is empty, contains only whitespace, or is too vague to be actionable (e.g., just "bug" or "error"), use **AskUserQuestion** to gather more details before proceeding.

## Workflow

### Step 1: Establish the Problem Statement

If `$ARGUMENTS` is provided and contains a clear, actionable problem statement (describes what's happening, where, and has observable symptoms), use it as the starting point.

Otherwise, use **AskUserQuestion** to gather:
- What is the observable problem/bug?
- What is the expected behavior vs actual behavior?
- When/where does this occur?

Formulate a clear, specific problem statement. Good problem statements:
- Describe the observable symptom
- Are specific and measurable
- Avoid assumptions about the cause

**Example**: "Users see a blank screen after clicking the 'Save' button on the profile page"
**Not**: "The save function is broken" (too vague and assumes cause)

### Step 2: Investigate the Codebase (if applicable)

If this is a code-related issue, follow this search strategy:

1. **Start with error keywords**: Search for the error message, exception type, or function name
   ```bash
   # Example: grep for the error message
   ```
2. **Find the affected component**: Use Glob to locate relevant files by name patterns
3. **Check recent changes**: Look at git history for the affected files
   ```bash
   git log --oneline -10 -- <file>
   ```
4. **Read the implementation**: Understand the code flow and data handling
5. **Examine related tests**: Check what behavior is expected and what edge cases are covered
6. **Search for similar patterns**: The same bug might exist elsewhere in the codebase

Document what you find - this context informs the "Why" questions.

### Step 3: Conduct the Five Whys Analysis

For each "Why" iteration:

1. **Ask "Why?"** - Why did the previous statement occur?
2. **Investigate** - Look at code, logs, or documentation if needed
3. **Answer** - Provide a factual answer based on evidence
4. **Validate** - Use **AskUserQuestion** if you need user confirmation or additional context

**Format each iteration as:**

```
**Why #N**: [Question based on previous answer]
**Investigation**: [What you looked at to find the answer]
**Answer**: [Factual answer with evidence]
```

**Guidelines:**
- Stop when you reach a root cause that is actionable
- Don't force exactly 5 iterations - sometimes 3 is enough, sometimes 7 is needed
- Prefer factual answers over speculation
- If you hit a dead end, ask the user for more context
- Look for systemic issues (process, architecture, tooling) not just code bugs

**Time-boxing**: If you haven't identified a clear root cause after 7 iterations or the analysis exceeds reasonable scope:
1. Summarize what you've discovered so far
2. Identify what information is missing or unclear
3. Recommend escalation to team discussion or additional debugging
4. Document partial findings - they're still valuable even if incomplete

### Step 4: Identify the Root Cause

After completing the Why iterations, clearly state:

1. **Root Cause**: The fundamental reason the problem occurred
2. **Contributing Factors**: Other issues that made this worse or possible
3. **Why this matters**: The impact of not fixing the root cause

### Step 5: Recommend Solutions

Based on the root cause analysis, provide:

1. **Immediate Fix**: What to do right now to resolve the symptom
2. **Root Cause Fix**: What to change to prevent recurrence
3. **Preventive Measures**: Process/tooling changes to catch similar issues earlier

### Step 6: Generate Summary

Output a structured summary that can be used in issue trackers or documentation:

```markdown
## Five Whys Analysis

### Problem Statement
[Clear description of the observable problem]

### Analysis Chain

| # | Why? | Answer |
|---|------|--------|
| 1 | [Initial problem] | [First-level cause] |
| 2 | Why [first-level cause]? | [Second-level cause] |
| 3 | Why [second-level cause]? | [Third-level cause] |
| ... | ... | ... |

### Root Cause
[The fundamental cause identified]

### Recommendations

**Immediate Fix:**
[What to do now]

**Root Cause Fix:**
[What to change systemically]

**Prevention:**
[How to prevent similar issues]
```

## Example Analysis

**Problem**: "API requests fail with 500 error after deploying new feature"

| # | Why? | Answer |
|---|------|--------|
| 1 | Why are API requests failing with 500? | The database query throws an error when the `user_preferences` column is null |
| 2 | Why is `user_preferences` null? | Existing users don't have this column populated - only new users do |
| 3 | Why don't existing users have data? | The migration added the column but didn't backfill existing records |
| 4 | Why didn't the migration backfill? | There's no standard practice for backfill migrations in the team |
| 5 | Why no standard practice? | Migration guidelines don't cover data backfills |

**Root Cause**: Missing data backfill migration combined with code that assumes data exists

**Recommendations**:
- Immediate: Add null handling to the query
- Root cause: Create and run a backfill migration
- Prevention: Update migration guidelines to require backfill consideration

## When to Use Five Whys

**Use Five Whys for:**
- Recurring bugs that keep coming back after fixes
- Production incidents with unclear causes
- Issues where the symptom and cause seem disconnected
- Bugs that affect multiple users or systems
- Post-mortems and retrospectives

**Skip or simplify for:**
- Obvious typos or simple syntax errors
- Clear-cut bugs with a single cause (e.g., missing null check)
- Issues where the fix is already known and straightforward
- Time-sensitive incidents where immediate action is needed (fix first, analyze later)

When in doubt, start the analysis - you can always stop early if the root cause becomes obvious.

## Notes

- Be thorough but don't over-complicate simple issues
- The goal is understanding, not blame
- Document your findings clearly for future reference
- This analysis is valuable input for Linear issues and PR descriptions
