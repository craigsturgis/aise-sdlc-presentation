---
name: regression
description: Run E2E regression tests against dev or prod, checking for active Amplify builds first and optionally waiting for them to complete
argument-hint: "[env: dev|prod] [--suite dataspaces|smoke|onboarding|content]"
allowed-tools: Bash, Read, Grep, Glob, AskUserQuestion
model: sonnet
---

# Regression Test Runner

Run E2E regression tests against a deployed environment (dev or prod), with automatic detection and optional monitoring of in-progress Amplify builds.

## User Input

```text
$ARGUMENTS
```

## Step 1: Parse Arguments

Extract from `$ARGUMENTS`:
- **Environment**: `dev` or `prod` (required)
- **Suite**: optional `--suite <name>` (dataspaces, smoke, onboarding, content)

If the environment is not specified or unclear, ask the user:

```
Use AskUserQuestion:
  "Which environment should I run the regression against?"
  Options: dev, prod
```

Map environments:
- `dev` → Amplify branch `dev`, URL `https://dev.example.app`
- `prod` → Amplify branch `prod`, URL `https://app.example.app`

## Step 2: Check AWS Authentication

Verify AWS CLI is authenticated — needed for Amplify build checks:

```bash
aws sts get-caller-identity --profile rootnote 2>&1
```

If this fails, tell the user:
> "AWS CLI is not authenticated. Please run `aws sso login --profile rootnote` to log in, then try again."

Stop and wait for the user to authenticate before proceeding.

## Step 3: Check for Active Amplify Builds

Query Amplify for recent jobs on the target branch:

```bash
aws amplify list-jobs \
  --app-id <AMPLIFY_APP_ID> \
  --branch-name <BRANCH> \
  --max-results 5 \
  --profile rootnote \
  --output json
```

Where `<BRANCH>` is `dev` or `prod` based on the selected environment.

Parse the response to find jobs with status `PENDING`, `PROVISIONING`, `RUNNING`, `DEPLOYING`, or `CANCELLING` (i.e., not yet `SUCCEED`, `FAILED`, or `CANCELLED`).

### If an active build is found:

Report the build status to the user:
> "There's an active Amplify build on **<ENV>** (branch: `<BRANCH>`):
> - Job ID: `<jobId>`
> - Status: `<status>`
> - Started: `<startTime>`
>
> Running regression tests against an environment that's mid-deploy may produce unreliable results."

Then ask the user:

```
Use AskUserQuestion:
  "What would you like to do?"
  Options:
  - "Wait for the build to finish, then run tests" (Recommended)
  - "Run tests now anyway"
  - "Cancel"
```

### If the user chooses to wait:

Poll the build status every 30 seconds (up to 20 polls / 10 minutes):

```bash
aws amplify get-job \
  --app-id <AMPLIFY_APP_ID> \
  --branch-name <BRANCH> \
  --job-id <JOB_ID> \
  --profile rootnote \
  --output json
```

Report status updates to the user as the build progresses (e.g., "Build status: RUNNING → DEPLOYING → SUCCEED"). Continue polling until the job reaches a terminal state (`SUCCEED`, `FAILED`, `CANCELLED`).

- If `SUCCEED`: proceed to Step 4.
- If `FAILED` or `CANCELLED`: report the failure and ask the user whether to run the tests anyway or abort.
- If the 10-minute polling cap is reached: ask the user whether to continue waiting, run tests now, or cancel.

### If no active build is found:

Report: "No active Amplify builds on **<ENV>**. Proceeding with regression tests."

Continue to Step 4.

## Step 4: Run the Regression Tests

Execute the regression script:

```bash
./scripts/run-regression.sh <ENV> [--suite <SUITE>]
```

Where:
- `<ENV>` is `dev` or `prod`
- `<SUITE>` is included only if the user specified a suite

Run this with a generous timeout (up to 10 minutes) since E2E tests take time.

**Important**: The script changes directory to `web/` internally, so run it from the repo root.

## Step 5: Report Results

After the tests complete, summarize the results:

1. **Environment**: Which environment was tested and the URL
2. **Amplify build**: Whether there was an active build and what happened (waited, skipped, none)
3. **Suite**: Which suite was run (or all)
4. **Test results**: Pass/fail summary from the Playwright output
5. **Failures**: If any tests failed, list the test names and brief failure descriptions
6. **Report**: Tell the user they can view the full HTML report with:
   ```
   pnpm --filter @rootnote/web test:e2e:report
   ```

If the tests all passed, report success concisely. If there were failures, provide enough detail for the user to understand what broke without having to dig through logs.
