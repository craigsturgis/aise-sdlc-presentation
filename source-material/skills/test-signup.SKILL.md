---
name: test-signup
description: Test sign-up end-to-end using browser automation and real email verification via SES/S3
argument-hint: "[signup-only | through-verification | full-onboarding] [--env local|preview|dev|prod] [--url <override>] [--email <override>] [--plan free|paid]"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__new_page, mcp__chrome-devtools__list_pages, mcp__chrome-devtools__select_page, mcp__chrome-devtools__take_snapshot, mcp__chrome-devtools__wait_for, mcp__chrome-devtools__click_element, mcp__chrome-devtools__fill_input, mcp__chrome-devtools__evaluate
model: sonnet
---

# Test Sign-Up End-to-End

Perform a real end-to-end sign-up test using browser automation (agent-browser or chrome-devtools MCP). Navigates through the sign-up form, reads the verification email from S3 (via SES receiving), enters the OTP code, and optionally continues through the full onboarding flow.

## User Input

```text
$ARGUMENTS
```

### Argument Parsing

Parse `$ARGUMENTS` to determine:

- **Scope** (first positional argument, default: `through-verification`):
  - `signup-only` — Fill and submit the sign-up form only (no email verification)
  - `through-verification` — Sign up + complete email verification via real email
  - `full-onboarding` — Complete entire flow: signup → verification → profile → plan selection → creator creation → dashboard

- **Options**:
  - `--env <environment>` — Target environment (default: `local`):
    - `local` — Local dev server at `http://localhost:${PORT}` (PORT from `web/.env.local`, default 3000)
    - `preview` — Amplify deploy preview. Requires `--pr <number>` to construct the URL: `https://pr-<number>.<AMPLIFY_APP_ID>.amplifyapp.com`
    - `dev` — Dev environment at `https://dev.example.app`
    - `prod` — Production at `https://app.example.app`
  - `--url <base-url>` — Explicit base URL, overrides `--env` entirely (e.g., `--url https://my-custom-preview.amplifyapp.com`)
  - `--pr <number>` — PR number for `--env preview` (e.g., `--pr 1669`)
  - `--email <address>` — Use a specific email instead of generating one. Must be `@test.example.app` domain.
  - `--plan free|paid` — Plan selection for `full-onboarding` scope (default: `free`)
  - `--keep-user` — Do NOT clean up the test user after completion (useful for manual inspection)
  - `--screenshot-dir <path>` — Directory for screenshots (default: `demos/`)

If `$ARGUMENTS` is empty, default to `through-verification` scope with `--env local`.

### URL Resolution

Resolve the target base URL (`BASE_URL`) using this priority:

1. If `--url` is provided, use it directly as `BASE_URL`
2. If `--env` is provided (or defaulting to `local`):
   - `local` → `http://localhost:${PORT}` (PORT from `web/.env.local`, default 3000)
   - `preview` → `https://pr-${PR_NUMBER}.<AMPLIFY_APP_ID>.amplifyapp.com` (requires `--pr`)
   - `dev` → `https://dev.example.app`
   - `prod` → `https://app.example.app`

If `--env preview` is used without `--pr`, ask the user for the PR number.

**For non-local environments**: verify the URL is reachable before proceeding:
```bash
STATUS=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}" 2>/dev/null)
if [ "$STATUS" = "000" ]; then
  echo "Cannot reach ${BASE_URL} — is the environment running?"
fi
```

**Use `BASE_URL` everywhere** below instead of `http://localhost:${PORT}`.

## Prerequisites

Before starting, verify these requirements:

### 1. AWS Credentials

Try to authenticate automatically before prompting the user:

```bash
# Step 1: Check if credentials already work (with or without AWS_PROFILE)
aws sts get-caller-identity 2>/dev/null
```

If this fails, attempt auto-login:

```bash
# Step 2: Try the "rootnote" profile (standard project profile)
AWS_PROFILE=rootnote aws sts get-caller-identity 2>/dev/null
```

If the `rootnote` profile works, use `AWS_PROFILE=rootnote` for all subsequent AWS commands in this session.

If the `rootnote` profile also fails (e.g., SSO session expired), attempt to refresh it:

```bash
# Step 3: Refresh SSO session for rootnote profile
aws sso login --profile rootnote
```

After login completes, verify:
```bash
AWS_PROFILE=rootnote aws sts get-caller-identity 2>/dev/null
```

If this succeeds, use `AWS_PROFILE=rootnote` for all subsequent commands.

**Only if all auto-login attempts fail**, stop and tell the user:
> "AWS credentials are required for reading verification emails from S3 and cleaning up Cognito test users. Auto-login with the `rootnote` profile failed. Run `aws sso login --profile rootnote` and `export AWS_PROFILE=rootnote` first, or configure the correct AWS profile."

**Important**: All AWS commands in subsequent steps (S3 reads, Cognito cleanup, etc.) must be prefixed with `AWS_PROFILE=rootnote` unless the user already has `AWS_PROFILE` set in their environment.

### 2. Environment Variables

```bash
grep '^SES_EMAIL_BUCKET=' web/.env.local
grep '^PORT=' web/.env.local
```

Required:
- `SES_EMAIL_BUCKET` — S3 bucket name where SES stores incoming test emails
- `PORT` — Dev server port (default: 3000)

Optional:
- `SES_EMAIL_PREFIX` — S3 key prefix (default: `incoming/`)
- `COGNITO_USER_POOL_ID` — Cognito pool ID (default: `<COGNITO_USER_POOL_ID>`)

If `SES_EMAIL_BUCKET` is not set, stop and tell the user:
> "Set `SES_EMAIL_BUCKET` in `web/.env.local` to the S3 bucket configured for SES email receiving (e.g., `<app>-ses-incoming-dev`)."

### 3. DNS / SES Readiness (if scope requires email verification)

If scope is `through-verification` or `full-onboarding`, verify that DNS is configured for email receiving:

```bash
# Check MX record for test.example.app
dig +short MX test.example.app
```

Expected output should contain `inbound-smtp.us-east-1.amazonaws.com`. If no MX record is found, warn the user:
> "No MX record found for `test.example.app`. Email verification will fail. See the post-merge setup instructions in the PR to configure DNS records."

This check is non-blocking — continue with the test but warn that email verification may fail.

### 4. Dev Server (local env only)

**Skip this step if `--env` is not `local`.** Non-local environments are already running.

```bash
PORT=$(grep '^PORT=' web/.env.local | cut -d= -f2)
PORT=${PORT:-3000}
curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}
```

If not running, start it:
```bash
pnpm dev:web &
# Poll until ready (up to 90 seconds)
for i in $(seq 1 90); do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT} 2>/dev/null)
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ] || [ "$STATUS" = "304" ] || [ "$STATUS" = "307" ]; then
    echo "Dev server ready after ${i}s"
    break
  fi
  sleep 1
done
```

## Step 1: Generate Test User Data

```bash
# Generate unique test email and password
TIMESTAMP=$(date +%s)
RANDOM_SUFFIX=$(openssl rand -hex 3)
TEST_EMAIL="e2e-test-${TIMESTAMP}-${RANDOM_SUFFIX}@test.example.app"
TEST_PASSWORD="Test${TIMESTAMP}!Pwd"
TEST_FIRST_NAME="E2E"
TEST_LAST_NAME="TestUser"
```

If `--email` was provided, use that instead (but still generate a password).

Store these values for use throughout the test.

## Step 2: Navigate to Sign-Up Page

### 2a: Try agent-browser First

```bash
command -v agent-browser || npx agent-browser --help >/dev/null 2>&1
```
If using npx fallback, prefix all subsequent `agent-browser` commands with `npx`.

**If agent-browser is available:**
```bash
agent-browser open ${BASE_URL}/signup
# Use fallback selector chain — data-testid is preferred, form element is backup
agent-browser wait '[data-testid="signup-form"], form[action*="signup"], form:has(input[type="email"])'
agent-browser screenshot demos/test-signup-01-form.png
```

**If agent-browser fails**, fall back to chrome-devtools MCP (Step 2b).

### 2b: Fallback — chrome-devtools MCP

1. Use `mcp__chrome-devtools__new_page` to open `${BASE_URL}/signup`
2. Use `mcp__chrome-devtools__wait_for` with selector `[data-testid="signup-form"], form:has(input[type="email"])`
3. Take a screenshot for documentation

Note which tool is being used: `TOOL=agent-browser` or `TOOL=chrome-devtools`

## Step 3: Fill the Sign-Up Form

### Using agent-browser:
```bash
# Fill first name
agent-browser fill 'input[placeholder*="First"]' "${TEST_FIRST_NAME}"

# Fill last name
agent-browser fill 'input[placeholder*="Last"]' "${TEST_LAST_NAME}"

# Fill email
agent-browser fill 'input[type="email"]' "${TEST_EMAIL}"

# Fill password
agent-browser fill 'input[type="password"]' "${TEST_PASSWORD}"

# Check terms and conditions checkbox (it's a button[role="checkbox"], not an input)
agent-browser click 'button[role="checkbox"]'

# Take screenshot before submit
agent-browser screenshot demos/test-signup-02-filled.png
```

### Using chrome-devtools MCP:
1. Use `mcp__chrome-devtools__fill_input` for each field
2. Use `mcp__chrome-devtools__click_element` for the checkbox
3. Take screenshot

### Handle Error Overlays and Form Errors

Next.js dev mode may show error overlays that block interactions. If any click or type action fails:

```bash
# 1. Check for and dismiss Next.js error overlay
agent-browser eval "document.querySelector('nextjs-portal')?.remove(); document.querySelector('nextjs-portal')?.shadowRoot?.querySelector('button')?.click()"
```
Or via chrome-devtools: use `mcp__chrome-devtools__evaluate` with the same script.

Then retry the failed action.

**If the action still fails after dismissing overlays**, check for form validation errors:
```bash
# 2. Check for visible validation error messages
agent-browser eval "JSON.stringify(Array.from(document.querySelectorAll('[role=\"alert\"], .text-destructive, [data-testid*=\"error\"]')).map(el => el.textContent?.trim()).filter(Boolean))"
```

If validation errors are found:
- Screenshot the current state: `agent-browser screenshot demos/test-signup-error.png`
- Report the specific error messages to the user
- Attempt to fix (e.g., re-fill the field that failed validation) and retry

**If clicking a button fails** (e.g., submit button not clickable):
```bash
# 3. Check if button is disabled
agent-browser eval "document.querySelector('button[type=\"submit\"]')?.disabled"
```
If disabled, there may be unfilled required fields — re-check all form inputs.

## Step 4: Submit the Form

**Record the current timestamp** before submitting (used to filter emails):
```bash
SUBMIT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
```

### Using agent-browser:
```bash
agent-browser click 'button[type="submit"]'

# Wait for redirect to confirm-email page
agent-browser wait 5000
agent-browser wait load
agent-browser screenshot demos/test-signup-03-confirm-email.png
```

### Using chrome-devtools MCP:
1. Use `mcp__chrome-devtools__click_element` on `button[type="submit"]`
2. Wait for navigation to `/signup/confirm-email`
3. Take screenshot

**Verify** the browser is now on `/signup/confirm-email`. If still on `/signup`, check for form validation errors and report them.

**If scope is `signup-only`**: Skip to Step 8 (Cleanup).

## Step 5: Read Verification Email from S3

Use the SES email reader utility to poll for the verification email:

```bash
cd web && npx tsx e2e/onboarding/utils/ses-email-reader.ts \
  --email "${TEST_EMAIL}" \
  --bucket "${SES_EMAIL_BUCKET}" \
  --timeout 90000 \
  --prefix "${SES_EMAIL_PREFIX:-incoming/}"
```

This will output: `VERIFICATION_CODE=XXXXXX`

**Parse the 6-digit code** from the output.

If the command fails or times out:
1. Check that SES email receiving is configured (MX records, SES receipt rules)
2. Check the S3 bucket for any emails: `aws s3 ls s3://${SES_EMAIL_BUCKET}/${SES_EMAIL_PREFIX:-incoming/}`
3. Report the issue to the user

## Step 6: Enter Verification Code

### Using agent-browser:
```bash
# The OTP input may be a single input or multiple single-char inputs
# Check which pattern is used
agent-browser eval "document.querySelectorAll('input[data-input-otp=\"true\"]').length || document.querySelectorAll('input[maxlength=\"1\"]').length"
```

**If single OTP input** (`input[data-input-otp="true"]`):
```bash
agent-browser fill 'input[data-input-otp="true"]' "${VERIFICATION_CODE}"
```

**If multiple single-char inputs** (`input[maxlength="1"]`):
```bash
# Type each digit into successive inputs
for i in $(seq 0 5); do
  DIGIT=${VERIFICATION_CODE:$i:1}
  agent-browser fill "input[maxlength='1']:nth-of-type($(($i + 1)))" "${DIGIT}"
done
```

### Using chrome-devtools MCP:
Use `mcp__chrome-devtools__fill_input` or `mcp__chrome-devtools__evaluate` to set the OTP value.

**Wait for verification to complete** — the page should redirect away from `/signup/confirm-email`:
```bash
# Wait up to 30 seconds for redirect
agent-browser wait 5000
agent-browser wait load
agent-browser screenshot demos/test-signup-04-verified.png
```

**If scope is `through-verification`**: Skip to Step 8 (Cleanup).

## Step 7: Complete Onboarding (full-onboarding scope only)

### 7a: Complete Profile

The profile page (`/onboard/complete-profile`) is fully client-side. On load it:
1. Fetches the auth session (access token)
2. Calls `POST /api/onboard/get-or-create-profile` to create the profile
3. Auto-completes the profile and redirects to the next step

While loading, the page shows rotating fun messages like "Reticulating splines..." and "Calibrating flux capacitors...". Wait for auto-redirect:

```bash
# Wait for navigation away from complete-profile (up to 45s — may include API cold start)
agent-browser wait 5000
agent-browser wait load
agent-browser screenshot demos/test-signup-05-after-profile.png
```

If the page shows an error card with "Try Again":
```bash
agent-browser click 'button:has-text("Try Again")'
agent-browser wait 10000
agent-browser wait load
```

If the page stays on complete-profile and shows a name form ("One More Step"):
```bash
agent-browser fill '#firstName' "${TEST_FIRST_NAME}"
agent-browser fill '#lastName' "${TEST_LAST_NAME}"
agent-browser click 'button[type="submit"]'
agent-browser wait 5000
agent-browser wait load
```

### 7b: Select Plan

If redirected to `/onboard/select-plan`:

**For free plan** (default):
```bash
# Look for "Continue with Free" button and click it
agent-browser click 'button:has-text("Continue with Free")'
agent-browser wait 5000
agent-browser wait load
agent-browser screenshot demos/test-signup-06-plan-selected.png
```

**For paid plan** (`--plan paid`):
> Stop and tell the user: "Paid plan testing requires Stripe checkout which involves entering payment details. This skill cannot automate Stripe's hosted checkout. Please complete the payment manually, then tell me to continue."

### 7c: Create Creator

If redirected to `/onboard/create-creator`:
```bash
CREATOR_NAME="E2E Test Creator ${RANDOM_SUFFIX}"

agent-browser wait '[data-testid="create-creator-form"], form:has([data-testid="creator-name-input"])'
agent-browser fill '[data-testid="creator-name-input"], input[name="creatorName"], input[placeholder*="creator" i]' "${CREATOR_NAME}"
agent-browser click 'button[type="submit"]'
agent-browser wait 10000
agent-browser wait load
agent-browser screenshot demos/test-signup-07-creator-created.png
```

### 7d: Add Creator Apps (Skip)

If redirected to `/onboard/add-creator-apps`:
```bash
# Click "Continue to dashboard" to skip platform connections
agent-browser click 'button:has-text("Continue")'
agent-browser wait 5000
agent-browser wait load
agent-browser screenshot demos/test-signup-08-dashboard.png
```

### 7e: Verify Dashboard

Confirm the browser is on `/content` (the dashboard):
```bash
agent-browser eval "window.location.pathname"
```

If on `/content`, the full onboarding is complete. Take a final screenshot:
```bash
agent-browser screenshot demos/test-signup-09-final.png
```

## Step 8: Cleanup

Unless `--keep-user` was specified, clean up the test user.

**Important**: Users created through the signup UI get UUID usernames in Cognito, not email-based usernames. Use `deleteTestUserByEmail` which looks up the UUID first:

```bash
cd web && npx tsx -e "
  import { deleteTestUserByEmail } from './e2e/onboarding/utils/cognito-admin';
  deleteTestUserByEmail('${TEST_EMAIL}')
    .then(deleted => console.log(deleted ? 'User deleted' : 'User not found'))
    .catch(err => console.error('Cleanup failed:', err.message));
"
```

Stop agent-browser if it was used:
```bash
agent-browser close 2>/dev/null || true
```

## Step 9: Report

Summarize the test results:

1. **Scope**: Which scope was tested (signup-only / through-verification / full-onboarding)
2. **Environment**: Which environment was targeted (local / preview / dev / prod) and the resolved `BASE_URL`
3. **Test User**: Email used, whether it was generated or provided
4. **Sign-Up Form**: Did form submission succeed? Any validation errors?
4. **Email Verification** (if applicable): How long did the email take to arrive? Was the code extracted successfully?
5. **Onboarding Steps** (if applicable): Which steps were completed, any that were skipped or failed
6. **Final URL**: Where did the browser end up?
7. **Screenshots**: List all screenshots captured with their paths
8. **Cleanup**: Was the test user deleted?
9. **Tool Used**: agent-browser or chrome-devtools (and whether it was a fallback)
10. **Issues**: Any problems encountered, with details

### Example Output:

```
## Test Sign-Up Results

- Scope: through-verification
- Environment: local (http://localhost:3000)
- Email: e2e-test-1740000000-a1b2c3@test.example.app
- Sign-up: Form submitted successfully
- Email verification: Code 482901 received after 8s, entered successfully
- Final URL: /onboard/complete-profile
- Screenshots: demos/test-signup-01-form.png through demos/test-signup-04-verified.png
- Cleanup: Test user deleted from Cognito
- Tool: agent-browser (primary)
```

## Error Handling

- **Form validation fails**: Screenshot the error state, report which fields failed, suggest fixes
- **Email never arrives**: After timeout, check S3 bucket directly, verify SES config, report findings
- **OTP entry fails**: Try alternative input patterns (single input vs. multi-input), screenshot the state
- **Page redirect fails**: Check for JavaScript errors via console, screenshot current state, report URL
- **agent-browser fails**: Silently fall back to chrome-devtools MCP without prompting the user
- **chrome-devtools also fails**: Report both failures and suggest the user check their MCP configuration
- **AWS credentials missing**: Stop immediately with clear instructions for authentication
- **Dev server not running**: Start it automatically, wait up to 90s, report if it fails to start
