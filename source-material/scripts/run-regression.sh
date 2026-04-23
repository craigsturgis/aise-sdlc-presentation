#!/usr/bin/env bash
#
# Run E2E regression tests against a deployed environment (dev or prod).
#
# Usage:
#   ./scripts/run-regression.sh <env> [--suite <name>] [-- <playwright-args>]
#
# Arguments:
#   env              Required. "dev" or "prod"
#   --suite <name>   Optional. E2E_SUITE to run (e.g., dataspaces, smoke, onboarding, content).
#                    If omitted, runs all suites.
#   -- <args>        Optional. Extra arguments passed directly to Playwright.
#
# Examples:
#   ./scripts/run-regression.sh dev
#   ./scripts/run-regression.sh dev --suite dataspaces
#   ./scripts/run-regression.sh prod --suite smoke -- --headed
#   ./scripts/run-regression.sh dev -- --grep "widget"

set -eo pipefail

# --- Resolve URL for environment ---
resolve_url() {
  case "$1" in
    dev)  echo "https://dev.example.app" ;;
    prod) echo "https://app.example.app" ;;
    *)    echo "Unknown environment: $1" >&2; return 1 ;;
  esac
}

# --- Parse arguments ---
ENV=""
SUITE=""
PLAYWRIGHT_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    dev|prod)
      ENV="$1"
      shift
      ;;
    --suite)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --suite requires a value" >&2
        exit 1
      fi
      SUITE="$2"
      shift 2
      ;;
    --)
      shift
      PLAYWRIGHT_ARGS+=("$@")
      break
      ;;
    -h|--help)
      echo "Usage: $0 <dev|prod> [--suite <name>] [-- <playwright-args>]"
      echo ""
      echo "Run E2E regression tests against a deployed environment."
      echo ""
      echo "Arguments:"
      echo "  dev|prod           Target environment"
      echo "  --suite <name>     E2E suite to run (dataspaces, smoke, onboarding, content)"
      echo "                     If omitted, runs all suites"
      echo "  -- <args>          Extra arguments passed to Playwright"
      echo ""
      echo "Examples:"
      echo "  $0 dev"
      echo "  $0 dev --suite dataspaces"
      echo "  $0 prod --suite smoke -- --headed"
      exit 0
      ;;
    *)
      echo "Error: Unknown argument '$1'" >&2
      echo "Usage: $0 <dev|prod> [--suite <name>] [-- <playwright-args>]" >&2
      exit 1
      ;;
  esac
done

# --- Validate suite name ---
VALID_SUITES=("dataspaces" "smoke" "onboarding" "content")
if [[ -n "$SUITE" ]]; then
  valid=false
  for s in "${VALID_SUITES[@]}"; do
    if [[ "$SUITE" == "$s" ]]; then valid=true; break; fi
  done
  if [[ "$valid" == false ]]; then
    echo "Error: Unknown suite '$SUITE'. Valid suites: ${VALID_SUITES[*]}" >&2
    exit 1
  fi
fi

if [[ -z "$ENV" ]]; then
  echo "Error: Environment is required (dev or prod)" >&2
  echo "Usage: $0 <dev|prod> [--suite <name>] [-- <playwright-args>]" >&2
  exit 1
fi

BASE_URL="$(resolve_url "$ENV")"

echo "=== RootNote E2E Regression ==="
echo "Environment: $ENV"
echo "Base URL:    $BASE_URL"
if [[ -n "$SUITE" ]]; then
  echo "Suite:       $SUITE"
else
  echo "Suite:       all"
fi
if [[ ${#PLAYWRIGHT_ARGS[@]} -gt 0 ]]; then
  echo "Extra args:  ${PLAYWRIGHT_ARGS[*]}"
fi
echo ""

# --- Verify prerequisites ---
command -v pnpm >/dev/null 2>&1 || { echo "Error: pnpm not found in PATH" >&2; exit 1; }

# --- Build the command ---
cd "$(dirname "$0")/../web"

export PLAYWRIGHT_BASE_URL="$BASE_URL"

if [[ -n "$SUITE" ]]; then
  export E2E_SUITE="$SUITE"
fi

echo "Running: PLAYWRIGHT_BASE_URL=$BASE_URL${SUITE:+ E2E_SUITE=$SUITE} pnpm exec playwright test ${PLAYWRIGHT_ARGS[*]:-}"
echo ""

exec pnpm exec playwright test "${PLAYWRIGHT_ARGS[@]+"${PLAYWRIGHT_ARGS[@]}"}"
