#!/usr/bin/env bash
# Sends a Slack notification to #dev-notifications when Claude Code needs input.
# Triggered by the Notification hook event.

set -uo pipefail
# Safety: never let notification hook crash Claude Code
trap 'exit 0' ERR

# Load SLACK_BOT_TOKEN from web/.env.local
ENV_FILE="${CLAUDE_PROJECT_DIR}/web/.env.local"
if [[ -f "$ENV_FILE" ]]; then
  SLACK_BOT_TOKEN=$(grep '^SLACK_BOT_TOKEN=' "$ENV_FILE" | cut -d'"' -f2)
fi

if [[ -z "${SLACK_BOT_TOKEN:-}" ]]; then
  echo "SLACK_BOT_TOKEN not found in $ENV_FILE" >&2
  exit 0  # exit 0 so we don't block Claude
fi

if [[ ! "$SLACK_BOT_TOKEN" =~ ^xoxb- ]]; then
  echo "Invalid SLACK_BOT_TOKEN format (expected xoxb-...)" >&2
  exit 0
fi

# Read the hook payload from stdin and extract all fields in a single jq call
PAYLOAD=$(cat)
FIELDS=$(echo "$PAYLOAD" | jq -r '[
  (.message // "Claude Code needs your attention"),
  (.title // ""),
  (.notification_type // "unknown"),
  (.session_id // "unknown"),
  (.cwd // "")
] | join("\t")' 2>/dev/null) || FIELDS=""

if [[ -n "$FIELDS" ]]; then
  IFS=$'\t' read -r MESSAGE TITLE NOTIFICATION_TYPE SESSION_ID CWD <<< "$FIELDS"
else
  MESSAGE="Claude Code needs your attention"
  TITLE=""
  NOTIFICATION_TYPE="unknown"
  SESSION_ID="unknown"
  CWD=""
fi
SHORT_SESSION="${SESSION_ID:0:8}"

# Derive project name from cwd (last directory component)
PROJECT_NAME=$(basename "${CWD:-$CLAUDE_PROJECT_DIR}" 2>/dev/null || echo "unknown")

# Get the current branch for context
BRANCH=$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Map notification type to emoji
case "$NOTIFICATION_TYPE" in
  permission_prompt)  EMOJI=":lock:" ;;
  idle_prompt)        EMOJI=":hourglass_flowing_sand:" ;;
  elicitation_dialog) EMOJI=":question:" ;;
  auth_success)       EMOJI=":white_check_mark:" ;;
  *)                  EMOJI=":bell:" ;;
esac

# Build the header line
HEADER="${EMOJI} *Claude Code*"
if [[ -n "$TITLE" ]]; then
  HEADER="${HEADER} — ${TITLE}"
fi

# Build context line (similar to status line)
CONTEXT=":git-merge: \`${BRANCH}\`  :file_folder: \`${PROJECT_NAME}\`  :id: \`${SHORT_SESSION}\`"

# Build the Slack Block Kit message for rich formatting
BLOCKS=$(jq -n \
  --arg header "$HEADER" \
  --arg message "$MESSAGE" \
  --arg context "$CONTEXT" \
  '[
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": $header }
    },
    {
      "type": "section",
      "text": { "type": "mrkdwn", "text": $message }
    },
    {
      "type": "context",
      "elements": [
        { "type": "mrkdwn", "text": $context }
      ]
    }
  ]'
)

# Plain text fallback for notifications
FALLBACK="${HEADER} — ${MESSAGE} (${BRANCH} | ${PROJECT_NAME} | ${SHORT_SESSION})"

curl -s -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg channel "#dev-notifications" \
    --arg text "$FALLBACK" \
    --argjson blocks "$BLOCKS" \
    '{channel: $channel, text: $text, blocks: $blocks}'
  )" > /dev/null

exit 0
