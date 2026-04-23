---
name: verify
description: Start dev server, validate changes visually with agent-browser (or chrome-devtools fallback), and document via Showboat
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion, mcp__chrome-devtools__navigate_page, mcp__chrome-devtools__take_screenshot, mcp__chrome-devtools__new_page, mcp__chrome-devtools__list_pages, mcp__chrome-devtools__select_page, mcp__chrome-devtools__take_snapshot, mcp__chrome-devtools__wait_for, mcp__chrome-devtools__fill, mcp__chrome-devtools__click, mcp__chrome-devtools__evaluate_script
model: sonnet
---

# Visual Verification Workflow

Start the dev server, verify changes visually with agent-browser (Vercel's headless browser CLI) or chrome-devtools MCP as fallback, and document results via Showboat.

## User Input

```text
$ARGUMENTS
```

If `$ARGUMENTS` is provided, use it as hints for what to verify (specific URLs, selectors to wait for, pages to visit, etc.).

## Step 0: Read Environment

1. **Parse PORT from `web/.env.local`**:
   ```bash
   grep '^PORT=' web/.env.local | cut -d= -f2
   ```
   Store this as `PORT` for all subsequent steps. If not found, default to `3000`.

2. **Parse ticket ID from current git branch**:
   ```bash
   git branch --show-current | grep -oE 'ROO-[0-9]+' | head -1
   ```
   Store this as `TICKET`. If no ticket ID is found, use `unknown` as a fallback.

3. **Check for existing Showboat demo file**:
   ```bash
   ls demos/${TICKET}.md 2>/dev/null
   ```
   Note whether the file exists for Step 4.

4. **Ensure `demos/` directory exists**:
   ```bash
   mkdir -p demos
   ```

## Step 1: Ensure Dev Server is Running

1. **Check if dev server is already responding**:
   ```bash
   curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}
   ```

2. **If not running** (non-200 response or connection refused):
   - Start the dev server in the background:
     ```bash
     pnpm dev:web &
     ```
   - Poll until ready (up to 90 seconds for Next.js cold compile):
     ```bash
     for i in $(seq 1 90); do
       STATUS=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT} 2>/dev/null)
       if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ] || [ "$STATUS" = "304" ]; then
         echo "Dev server ready after ${i}s"
         break
       fi
       sleep 1
     done
     ```
   - If still not responding after 90s, warn the user and ask how to proceed.

3. **If already running**, report it and continue.

## Step 1.5: Read Authentication Credentials

The app requires authentication. Without logging in, screenshots will only capture the login page.

1. **Read test credentials from `web/.env.local`**:
   ```bash
   TEST_EMAIL=$(grep '^TEST_USER_EMAIL=' web/.env.local 2>/dev/null | cut -d= -f2)
   TEST_PASSWORD=$(grep '^TEST_USER_PASSWORD=' web/.env.local 2>/dev/null | cut -d= -f2)
   ```

2. **If either is empty**, warn:
   > "TEST_USER_EMAIL or TEST_USER_PASSWORD not set in web/.env.local — proceeding without authentication. Screenshots will show the login page."

   Set `AUTH_AVAILABLE=false` and continue to Step 2 (skip all auth substeps in Steps 2–3).

3. **Check for cached Playwright auth state**:
   ```bash
   AUTH_FILE="web/e2e/.auth/user-0.json"
   if [ -f "$AUTH_FILE" ]; then
     AGE=$(( $(date +%s) - $(stat -f %m "$AUTH_FILE") ))
     if [ $AGE -lt 3600 ]; then
       echo "Cached auth state found (${AGE}s old)"
       CACHED_AUTH=true
     else
       echo "Cached auth state expired (${AGE}s old), will use form login"
       CACHED_AUTH=false
     fi
   else
     echo "No cached auth state, will use form login"
     CACHED_AUTH=false
   fi
   ```

   Set `AUTH_AVAILABLE=true`.

## Step 2: Browser Verification — Try agent-browser First

1. **Check if agent-browser is available**:
   ```bash
   command -v agent-browser || npx agent-browser --help >/dev/null 2>&1
   ```
   If using npx fallback, prefix all subsequent `agent-browser` commands with `npx`.

2. **If agent-browser is available**, run the verification flow:

   **Authenticate (if `AUTH_AVAILABLE=true`)**:

   If `CACHED_AUTH=true`, try cached auth first:
   ```bash
   agent-browser open http://localhost:${PORT}
   agent-browser wait load
   # Inject localStorage from cached Playwright auth state
   agent-browser eval "const s = $(cat web/e2e/.auth/user-0.json); (s.origins||[]).forEach(o => (o.localStorage||[]).forEach(i => localStorage.setItem(i.name, i.value)))"
   agent-browser reload
   agent-browser wait load
   agent-browser wait 2000
   ```
   Check if authenticated:
   ```bash
   CURRENT_URL=$(agent-browser get url)
   # If URL contains /signin, cached auth didn't work — fall through to form login
   ```

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

   ```bash
   agent-browser screenshot demos/${TICKET}-verify.png
   ```

   - If `$ARGUMENTS` contains a specific path (e.g., `/dashboard`, `/settings`), navigate there before the screenshot:
     ```bash
     agent-browser open http://localhost:${PORT}/<path>
     agent-browser wait load
     ```
   - If `$ARGUMENTS` contains a CSS selector to wait for, use it:
     ```bash
     agent-browser wait '<selector>'
     ```
   - Optionally take an accessibility snapshot to inspect page state:
     ```bash
     agent-browser snapshot -i
     ```
   - Then take the screenshot:
     ```bash
     agent-browser screenshot demos/${TICKET}-verify.png
     ```

   After capturing, close agent-browser:
   ```bash
   agent-browser close
   ```

   Note which tool was used: `TOOL_USED=agent-browser`

3. **If agent-browser fails at any step** (not installed, errors, crashes), proceed to Step 3. Do NOT prompt the user — silently fall back.

## Step 3: Fallback — chrome-devtools MCP

Only execute this step if agent-browser was unavailable or failed in Step 2.

1. **Open a new browser page**:
   Use `mcp__chrome-devtools__new_page` to open `http://localhost:${PORT}`

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
   - Reload the page with `mcp__chrome-devtools__navigate_page` (type: `reload`)
   - Wait for page load, then take a snapshot with `mcp__chrome-devtools__take_snapshot`
   - Check if the page URL still contains `/signin` — if not, auth succeeded, skip form login

   If still on `/signin` (or `CACHED_AUTH=false`), do form-based login:
   - Navigate to `/signin` with `mcp__chrome-devtools__navigate_page`
   - Wait for the sign-in form with `mcp__chrome-devtools__wait_for` (text: "Sign In" or "Sign in")
   - Take a snapshot with `mcp__chrome-devtools__take_snapshot` to find form element UIDs
   - Use `mcp__chrome-devtools__fill` on the email input UID with `${TEST_EMAIL}`
   - Use `mcp__chrome-devtools__fill` on the password input UID with `${TEST_PASSWORD}`
   - Use `mcp__chrome-devtools__click` on the submit button UID
   - Wait for redirect: use `mcp__chrome-devtools__wait_for` with text that appears after login, or take a snapshot and verify the URL no longer contains `/signin`
   - If login fails after 15s, warn: "Authentication failed — proceeding with screenshot of current page."

3. **Navigate to target page** (if `$ARGUMENTS` contains a specific path):
   - Use `mcp__chrome-devtools__navigate_page` to go to `http://localhost:${PORT}/<path>`

4. **Wait for page content**:
   Use `mcp__chrome-devtools__wait_for` with `body` (or a user-specified selector from `$ARGUMENTS`).

5. **Take a screenshot**:
   Use `mcp__chrome-devtools__take_screenshot` to capture the page state.
   Save to `demos/${TICKET}-verify.png`.

   Note which tool was used: `TOOL_USED=chrome-devtools`

## Step 4: Showboat Integration

1. **Check if Showboat is available**:
   ```bash
   command -v showboat
   ```

2. **If a Showboat demo file exists** for this ticket (`demos/${TICKET}.md`) and Showboat is installed:
   ```bash
   showboat image demos/${TICKET}.md demos/${TICKET}-verify.png
   showboat note demos/${TICKET}.md "Visual verification completed via ${TOOL_USED}"
   ```

3. **If no Showboat file exists but Showboat is installed**:
   - Do NOT create one automatically — just report the screenshot location.
   - Suggest the user can create one with: `showboat init demos/${TICKET}.md "Ticket Title"`

4. **If Showboat is not installed**, skip this step and just report screenshot location.

## Step 5: Report

Summarize the verification results:

- **Tool used**: agent-browser or chrome-devtools (and whether it was a fallback)
- **Dev server**: Was it already running or started fresh?
- **URL verified**: `http://localhost:${PORT}` (or specific path if provided)
- **Screenshot**: Path to the captured screenshot (`demos/${TICKET}-verify.png`)
- **Showboat**: Whether the screenshot was embedded in an existing demo doc
- **Any issues observed**: Note anything unusual about the page (errors, blank page, etc.)

If the user provided specific instructions via `$ARGUMENTS`, confirm whether those specific items were verified.
