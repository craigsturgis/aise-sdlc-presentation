#!/bin/bash
set -e

echo "Setting up worktree..."

# Check for required dependencies
if ! command -v lsof >/dev/null 2>&1; then
  echo "Error: lsof command not found. Please install it first."
  exit 1
fi

# Find the main worktree (first one listed, typically the original clone)
MAIN_WORKTREE=$(git worktree list | head -1 | awk '{print $1}')
CURRENT_WORKTREE=$(pwd)

# Function to find an available port in a given range
# Note: There's a potential race condition if multiple worktree setups run simultaneously.
# Run setup sequentially to avoid port conflicts.
find_available_port() {
  local start_port=${1:-3001}
  local end_port=${2:-3099}

  for port in $(seq $start_port $end_port); do
    # Check if port is in use using lsof (macOS/Linux compatible)
    if ! lsof -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then
      echo $port
      return 0
    fi
  done

  # No available port found in range
  echo "Error: No available port found in range $start_port-$end_port" >&2
  return 1
}

# Function to update port-related variables in .env.local
update_env_port() {
  local env_file=$1
  local port=$2
  local base_url="http://localhost:$port"

  if [[ ! -f "$env_file" ]]; then
    return
  fi

  # Remove existing PORT, ROOT_URL, NEXTAUTH_URL lines (commented or not)
  sed -i '' '/^#*\s*PORT=/d' "$env_file" 2>/dev/null || true
  sed -i '' '/^#*\s*ROOT_URL=/d' "$env_file" 2>/dev/null || true
  sed -i '' '/^#*\s*NEXTAUTH_URL=/d' "$env_file" 2>/dev/null || true

  # Add new values at the top of the file
  local temp_file=$(mktemp)
  {
    echo "# Worktree-specific port configuration"
    echo "PORT=$port"
    echo "ROOT_URL=$base_url"
    echo "NEXTAUTH_URL=$base_url"
    echo ""
    cat "$env_file"
  } > "$temp_file"
  mv "$temp_file" "$env_file"

  echo "  Updated $env_file with PORT=$port"
}

if [[ "$MAIN_WORKTREE" == "$CURRENT_WORKTREE" ]]; then
  echo "This appears to be the main worktree, skipping env copy."
else
  # Set up beads redirect so all worktrees share the same .beads database
  if [[ -d "$MAIN_WORKTREE/.beads" ]]; then
    echo "Setting up beads redirect to main worktree..."
    mkdir -p .beads
    chmod 700 .beads
    # bd resolves redirect contents relative to the worktree root (parent of .beads),
    # so compute the relative path from the worktree root — not from .beads itself.
    BEADS_RELATIVE=$(python3 -c "import os.path, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$MAIN_WORKTREE/.beads" "$CURRENT_WORKTREE")
    echo "$BEADS_RELATIVE" > .beads/redirect
    echo "  Beads redirect: .beads/redirect → $BEADS_RELATIVE"
  fi
  echo "Copying .env.local files from main worktree: $MAIN_WORKTREE"

  # Copy web/.env.local
  if [[ -f "$MAIN_WORKTREE/web/.env.local" ]]; then
    cp "$MAIN_WORKTREE/web/.env.local" ./web/.env.local
    echo "  Copied web/.env.local"
  else
    echo "  Warning: $MAIN_WORKTREE/web/.env.local not found"
  fi

  # Copy services/rootnote-api/.env.local
  if [[ -f "$MAIN_WORKTREE/services/rootnote-api/.env.local" ]]; then
    mkdir -p ./services/rootnote-api
    cp "$MAIN_WORKTREE/services/rootnote-api/.env.local" ./services/rootnote-api/.env.local
    echo "  Copied services/rootnote-api/.env.local"
  else
    echo "  Warning: $MAIN_WORKTREE/services/rootnote-api/.env.local not found"
  fi

  # Copy services/batch-jobs/.env.local
  if [[ -f "$MAIN_WORKTREE/services/batch-jobs/.env.local" ]]; then
    mkdir -p ./services/batch-jobs
    cp "$MAIN_WORKTREE/services/batch-jobs/.env.local" ./services/batch-jobs/.env.local
    echo "  Copied services/batch-jobs/.env.local"
  else
    echo "  Warning: $MAIN_WORKTREE/services/batch-jobs/.env.local not found"
  fi

  # Copy web/src/amplifyconfiguration.json
  if [[ -f "$MAIN_WORKTREE/web/src/amplifyconfiguration.json" ]]; then
    mkdir -p ./web/src
    cp "$MAIN_WORKTREE/web/src/amplifyconfiguration.json" ./web/src/amplifyconfiguration.json
    echo "  Copied web/src/amplifyconfiguration.json"
  else
    echo "  Warning: $MAIN_WORKTREE/web/src/amplifyconfiguration.json not found"
  fi

  # Find an available port for this worktree's dev server
  echo "Finding available port for dev server..."
  if DEV_PORT=$(find_available_port 3001 3099); then
    echo "  Using port $DEV_PORT for this worktree"
    # Update web/.env.local with the assigned port
    update_env_port "./web/.env.local" "$DEV_PORT"
  else
    echo "  Warning: Could not find available port. You may need to configure PORT manually in web/.env.local"
  fi
fi

# Check AWS SSO login status
echo "Checking AWS SSO login status for rootnote profile..."
if ! aws configure list-profiles 2>/dev/null | grep -q "^rootnote$"; then
  echo "  Warning: 'rootnote' AWS profile not found. Please configure it first."
  echo "  See: https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html"
elif AWS_PROFILE=rootnote aws sts get-caller-identity >/dev/null 2>&1; then
  echo "  AWS rootnote profile is authenticated."
  if [[ -z "$AWS_PROFILE" || "$AWS_PROFILE" != "rootnote" ]]; then
    echo "  Note: AWS_PROFILE is not set to 'rootnote' in your current shell."
    echo "  Run: export AWS_PROFILE=rootnote"
  fi
else
  echo "  AWS rootnote profile is NOT authenticated."
  read -p "  Would you like to log in now? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    aws sso login --profile rootnote
    if AWS_PROFILE=rootnote aws sts get-caller-identity >/dev/null 2>&1; then
      echo "  AWS login successful."
    else
      echo "  Warning: AWS login may not have completed successfully."
      echo "  Common causes: browser didn't open, SSO session expired, or network issues."
      echo "  You can try again later with: aws sso login --profile rootnote"
    fi
  else
    echo "  Skipping AWS login. You can log in later with:"
    echo "    aws sso login --profile rootnote"
    echo "    export AWS_PROFILE=rootnote"
  fi
fi

# Install dependencies
echo "Installing dependencies..."
pnpm install

echo "Worktree setup complete!"
