#!/bin/bash
# Common boilerplate for PostToolUse hook scripts.
# Adapted from https://github.com/panozzaj/claude-hooks
#
# Usage: at the top of each hook, set HOOK_NAME and FILE_PATTERN, then source this file:
#
#   HOOK_NAME="eslint"
#   FILE_PATTERN='\.(js|jsx|ts|tsx)$'
#   SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPTS_DIR/hook_common.bash"
#
# Note: Do NOT use set -e — hook_common.bash sets `trap 'exit 0' ERR` so
# unexpected failures exit cleanly instead of surfacing as "hook error".
#
# After sourcing, these variables are available:
#   CHANGED_FILES  - space-separated list of matching files (non-empty, or script already exited)
#   VERBOSE        - "true" if -v/--verbose was passed
#
# These functions are available:
#   hook_status    - prints "toolname: checkmark/x/N/A" and exits

# Safety: catch unexpected errors so hooks never crash Claude Code.
# This trap swallows all non-zero exits — callers should NOT use set -e.
# Intentional blocks must use explicit `exit 2` which bypasses this trap.
trap 'exit 0' ERR

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Parse flags
VERBOSE=false
FILES_ARG=()
for arg in "$@"; do
  if [ "$arg" = "-v" ] || [ "$arg" = "--verbose" ]; then
    VERBOSE=true
  else
    FILES_ARG+=("$arg")
  fi
done

# Print status line and exit.
# Usage: hook_status pass|fail|na [message]
hook_status() {
  local status=$1
  local message=${2:-}

  case "$status" in
    pass)
      echo -e "${HOOK_NAME}: ${GREEN}✓${NC}"
      exit 0
      ;;
    fail)
      echo -e "${HOOK_NAME}: ${RED}✗${NC}" >&2
      exit 2
      ;;
    na)
      if [ -n "$message" ]; then
        echo -e "${HOOK_NAME}: ${GRAY}N/A (${message})${NC}"
      else
        echo -e "${HOOK_NAME}: ${GRAY}N/A${NC}"
      fi
      exit 0
      ;;
    *)
      exit 0
      ;;
  esac
}

# --- Determine file to check ---

CHANGED_FILES=""

if [ ${#FILES_ARG[@]} -gt 0 ]; then
  CHANGED_FILES="${FILES_ARG[*]}"
else
  # Hook mode: read JSON from STDIN
  if [ ! -t 0 ]; then
    HOOK_JSON=$(cat)

    # Guard: if jq is not available, skip gracefully
    if ! command -v jq &>/dev/null; then
      hook_status na "jq not found"
    fi

    FILE_PATH=$(echo "$HOOK_JSON" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null || true)

    if [ -n "$FILE_PATH" ] && [[ "$FILE_PATH" =~ $FILE_PATTERN ]]; then
      CHANGED_FILES="$FILE_PATH"
    fi
  fi
fi

if [ -z "$CHANGED_FILES" ]; then
  hook_status na
fi
