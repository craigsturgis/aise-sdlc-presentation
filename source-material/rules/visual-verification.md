---
paths:
  - "web/**"
  - "demos/**"
---

# Demo Documentation & Browser Verification (Showboat + agent-browser)

After completing a feature or bug fix, use **Showboat** and **agent-browser** to document and verify the work.

## Showboat - Demo Documents

Create a Markdown demo document that serves as reproducible proof of what was built/fixed.

**Demo docs go in `demos/` and are named by ticket ID** (e.g., `demos/ROO-878.md`).

```bash
# Start a demo doc
showboat init demos/ROO-878.md "Feature/Fix Title"

# Add context
showboat note demos/ROO-878.md "Description of what was built or fixed."

# Run commands that prove it works - output is captured
showboat exec demos/ROO-878.md bash "pnpm test:ci:web"

# Embed screenshots
showboat image demos/ROO-878.md screenshot.png

# Verify the demo is still reproducible
showboat verify demos/ROO-878.md

# Undo the last entry
showboat pop demos/ROO-878.md
```

## agent-browser - CLI Browser Automation

Use alongside chrome-devtools MCP for browser-facing verification:

- **agent-browser** (preferred): headless screenshots, programmatic element checks, accessibility tree snapshots with ref-based selection, automated verification flows, capturing evidence for Showboat docs
- **chrome-devtools MCP** (fallback): interactive debugging, visual inspection, real-time page manipulation — use when agent-browser is unavailable or for interactive debugging

### agent-browser flow

```bash
agent-browser open http://localhost:<PORT>
agent-browser wait '<selector>'
agent-browser screenshot demos/ROO-878-feature.png
agent-browser snapshot -i  # inspect interactive accessibility tree with @refs
agent-browser close

# Then embed in Showboat doc
showboat image demos/ROO-878.md demos/ROO-878-feature.png
```

Install via `npm install -g agent-browser && agent-browser install` (installs Chromium). Can also use `npx agent-browser` without global install.

### chrome-devtools MCP fallback flow

If agent-browser is not installed or fails, use the `chrome-devtools` MCP tools instead:

1. Open a page: `mcp__chrome-devtools__navigate_page` with the target URL
2. Wait for elements: `mcp__chrome-devtools__wait_for` with a CSS selector
3. Take a screenshot: `mcp__chrome-devtools__take_screenshot`
4. Interact with the page: `mcp__chrome-devtools__click`, `mcp__chrome-devtools__fill`, `mcp__chrome-devtools__evaluate_script`

The MCP tool name is `chrome-devtools`, NOT `claude-in-chrome`.

## Authentication for Visual Verification

The app requires authentication, so visual verification must log in before capturing screenshots. The `/verify`, `/bugfix`, and `/feature` skills handle this automatically using the following strategy:

1. **Read credentials** from `web/.env.local`: `TEST_USER_EMAIL` and `TEST_USER_PASSWORD`
2. **Try cached Playwright auth state** first (`web/e2e/.auth/user-0.json`) -- if the file exists and is less than 1 hour old, inject localStorage entries
3. **Fall back to form-based login** -- navigate to `/signin`, fill the email/password form, submit, wait for redirect
4. **If no credentials are set**, warn and proceed without authentication

For **agent-browser**, auth uses `agent-browser fill`, `agent-browser click`, and `agent-browser eval` (for cached state injection).
For **chrome-devtools MCP**, auth uses `fill`, `click`, and `evaluate_script` tools.

## When to Use

- **Always** create a Showboat demo doc after completing a feature or bug fix
- **Use agent-browser** when the change has a browser-facing component to verify visually
- Combine both: use agent-browser to capture screenshots, then embed them in Showboat docs
