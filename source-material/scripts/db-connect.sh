#!/usr/bin/env bash
# db-connect.sh — Connect to RootNote RDS PostgreSQL databases
#
# Dynamically discovers RDS endpoints and credentials from AWS.
# No hardcoded hosts, secret IDs, or passwords.
#
# Supports both single RDS instances (dev) and Multi-AZ DB clusters (prod).
# For VPC-only clusters, automatically uses SSM Session Manager port forwarding
# through a bastion EC2 instance — no VPN or SSH keys needed.
#
# SECURITY: Credentials never touch shell variables. They flow directly
# from AWS Secrets Manager → Python stdin → pgpass file or output file.
# The --connection-string and --env-vars modes write to files (not stdout)
# to prevent credentials from appearing in terminal scrollback or logs.
#
# Usage:
#   ./scripts/db-connect.sh <env>                     # Open interactive psql session
#   ./scripts/db-connect.sh <env> --connection-string  # Write postgresql:// URI to file
#   ./scripts/db-connect.sh <env> --env-vars           # Write DB_* env vars to file
#   ./scripts/db-connect.sh <env> --pgpass             # Create pgpass file, print path
#   ./scripts/db-connect.sh <env> --test               # Test connection only
#   ./scripts/db-connect.sh <env> --tunnel             # Open SSM tunnel (for Drizzle Studio, GUI clients)
#
# Environment: dev | prod
# Requires: AWS CLI v2, psql, python3
# For clusters: AWS Session Manager plugin (https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
# AWS auth: Uses AWS_PROFILE (default: rootnote)

set -euo pipefail

# --- Help ---
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  cat <<'HELPEOF'
db-connect.sh — Connect to RootNote RDS PostgreSQL databases

Dynamically discovers RDS endpoints and credentials from AWS.
Credentials never touch shell variables — they flow directly from
AWS Secrets Manager through Python to pgpass/output files.

For VPC-only RDS clusters (prod), automatically tunnels through an SSM
bastion — no VPN or SSH keys needed.

USAGE:
  ./scripts/db-connect.sh <env> [mode]

ENVIRONMENTS:
  dev   Development database (direct connection)
  prod  Production database (SSM tunnel through bastion)

MODES:
  --psql              Interactive psql session (default)
  --test              Test connection and exit
  --pgpass            Create pgpass file, print its path
  --connection-string Write postgresql:// URI to a temp file
  --env-vars          Write DB_* env vars to a temp file
  --tunnel            Open SSM tunnel only — for Drizzle Studio, GUI clients, etc.
                      Runs in foreground; Ctrl+C to stop. Then connect to localhost.

ENVIRONMENT VARIABLES:
  AWS_PROFILE   AWS profile to use (default: rootnote)
  AWS_REGION    AWS region (default: us-east-1)
  LOCAL_PORT    Local port for SSM tunnel (default: 5432)

EXAMPLES:
  ./scripts/db-connect.sh dev              # Direct psql to dev
  ./scripts/db-connect.sh prod             # psql to prod via SSM tunnel
  ./scripts/db-connect.sh prod --test      # Test prod connection
  ./scripts/db-connect.sh prod --tunnel    # Open tunnel, then use Drizzle Studio
  LOCAL_PORT=54320 ./scripts/db-connect.sh prod --tunnel  # Custom local port
HELPEOF
  exit 0
fi

ENV="${1:-}"
MODE="${2:---psql}"
export AWS_PROFILE="${AWS_PROFILE:-rootnote}"
AWS_REGION="${AWS_REGION:-us-east-1}"
LOCAL_PORT="${LOCAL_PORT:-54320}"

if [[ -z "$ENV" ]] || [[ ! "$ENV" =~ ^(dev|prod)$ ]]; then
  echo "Usage: $0 <dev|prod> [--psql|--connection-string|--env-vars|--pgpass|--test|--tunnel]"
  echo "       $0 --help"
  exit 1
fi

# --- Prerequisites ---
if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 is required but not found in PATH" >&2
  exit 1
fi
if [[ "$MODE" != "--tunnel" ]] && ! command -v psql &>/dev/null; then
  echo "ERROR: psql is required but not found in PATH" >&2
  exit 1
fi

DB_INSTANCE_IDENTIFIER="rootnote-${ENV}-postgres"
DB_CLUSTER_IDENTIFIER="rootnote-${ENV}-postgres-cluster"
PGPASS_FILE="/tmp/.pgpass_rootnote_${ENV}"
CONNSTR_FILE="/tmp/.connstr_rootnote_${ENV}"
ENVVARS_FILE="/tmp/.envvars_rootnote_${ENV}"
SSM_PID=""
IS_CLUSTER=false

cleanup() {
  # Kill SSM tunnel if we started one
  if [[ -n "$SSM_PID" ]] && kill -0 "$SSM_PID" 2>/dev/null; then
    echo "Stopping SSM tunnel (PID ${SSM_PID})..." >&2
    kill "$SSM_PID" 2>/dev/null || true
    wait "$SSM_PID" 2>/dev/null || true
  fi
  if [[ "$MODE" == "--psql" ]] || [[ "$MODE" == "--test" ]]; then
    rm -f "$PGPASS_FILE"
  fi
}
trap cleanup EXIT

# --- AWS Auth Check ---
echo "Checking AWS authentication..." >&2
if ! aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null; then
  echo "AWS credentials expired or missing. Attempting SSO login..." >&2
  aws sso login --profile "$AWS_PROFILE"
  if ! aws sts get-caller-identity --region "$AWS_REGION" &>/dev/null; then
    echo "ERROR: AWS authentication failed after SSO login attempt." >&2
    exit 1
  fi
fi
echo "AWS authentication OK." >&2

# --- Discover RDS Endpoint ---
# Try cluster first (Multi-AZ DB cluster), then fall back to single instance.

echo "Discovering RDS database: ${ENV}..." >&2

CLUSTER_JSON=$(aws rds describe-db-clusters \
  --db-cluster-identifier "$DB_CLUSTER_IDENTIFIER" \
  --query 'DBClusters[0]' \
  --output json \
  --region "$AWS_REGION" 2>/dev/null) && IS_CLUSTER=true || IS_CLUSTER=false

if [[ "$IS_CLUSTER" == true ]]; then
  echo "Found Multi-AZ DB cluster: ${DB_CLUSTER_IDENTIFIER}" >&2

  DB_STATE=$(echo "$CLUSTER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('Status', 'unknown'))")
  if [[ "$DB_STATE" != "available" ]]; then
    echo "ERROR: RDS cluster '${DB_CLUSTER_IDENTIFIER}' is in state '${DB_STATE}', not 'available'" >&2
    exit 1
  fi

  DB_HOST=$(echo "$CLUSTER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['Endpoint'])")
  DB_PORT=$(echo "$CLUSTER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['Port'])")
  DB_NAME=$(echo "$CLUSTER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['DatabaseName'])")
  SECRET_ARN=$(echo "$CLUSTER_JSON" | python3 -c "
import json, sys
info = json.load(sys.stdin)
secrets = info.get('MasterUserSecret', {})
arn = secrets.get('SecretArn', '')
if not arn:
    print('ERROR: No MasterUserSecret found on cluster. Is manage_master_user_password enabled?', file=sys.stderr)
    sys.exit(1)
print(arn)
") || { echo "ERROR: Could not retrieve MasterUserSecret ARN from RDS cluster" >&2; exit 1; }
else
  echo "No cluster found, trying single instance: ${DB_INSTANCE_IDENTIFIER}..." >&2

  INSTANCE_JSON=$(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
    --query 'DBInstances[0]' \
    --output json \
    --region "$AWS_REGION") || {
    echo "ERROR: Failed to find RDS instance '${DB_INSTANCE_IDENTIFIER}' or cluster '${DB_CLUSTER_IDENTIFIER}'" >&2
    exit 1
  }

  DB_STATE=$(echo "$INSTANCE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('DBInstanceStatus', 'unknown'))")
  if [[ "$DB_STATE" != "available" ]]; then
    echo "ERROR: RDS instance '${DB_INSTANCE_IDENTIFIER}' is in state '${DB_STATE}', not 'available'" >&2
    exit 1
  fi

  DB_HOST=$(echo "$INSTANCE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['Endpoint']['Address'])")
  DB_PORT=$(echo "$INSTANCE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['Endpoint']['Port'])")
  DB_NAME=$(echo "$INSTANCE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['DBName'])")
  SECRET_ARN=$(echo "$INSTANCE_JSON" | python3 -c "
import json, sys
info = json.load(sys.stdin)
arn = info.get('MasterUserSecret', {}).get('SecretArn', '')
if not arn:
    print('ERROR: No MasterUserSecret found in RDS instance metadata. Is manage_master_user_password enabled?', file=sys.stderr)
    sys.exit(1)
print(arn)
") || { echo "ERROR: Could not retrieve MasterUserSecret ARN from RDS instance" >&2; exit 1; }
fi

echo "Host: ${DB_HOST}  Port: ${DB_PORT}  Database: ${DB_NAME}" >&2
if [[ "$IS_CLUSTER" == true ]]; then
  echo "Type: Multi-AZ DB cluster (VPC-only, requires SSM tunnel)" >&2
fi

# --- SSM Tunnel for VPC-only clusters ---

start_ssm_tunnel() {
  # Discover bastion instance by tags
  echo "Discovering SSM bastion instance..." >&2
  BASTION_ID=$(aws ec2 describe-instances \
    --filters \
      "Name=tag:Purpose,Values=ssm-bastion-rds-access" \
      "Name=tag:Environment,Values=${ENV}" \
      "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text \
    --region "$AWS_REGION")

  if [[ -z "$BASTION_ID" ]]; then
    echo "ERROR: No running SSM bastion instance found for '${ENV}' environment." >&2
    echo "  Expected an EC2 instance with tags:" >&2
    echo "    Purpose=ssm-bastion-rds-access" >&2
    echo "    Environment=${ENV}" >&2
    echo "  See: infrastructure/environments/${ENV}/bastion/" >&2
    exit 1
  fi

  # Check that Session Manager plugin is installed
  if ! command -v session-manager-plugin &>/dev/null; then
    echo "ERROR: AWS Session Manager plugin is required for SSM tunneling." >&2
    echo "  Install: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html" >&2
    echo "  macOS:   brew install --cask session-manager-plugin" >&2
    exit 1
  fi

  echo "Starting SSM tunnel: localhost:${LOCAL_PORT} → ${DB_HOST}:${DB_PORT}" >&2
  echo "  Bastion: ${BASTION_ID}" >&2

  aws ssm start-session \
    --target "$BASTION_ID" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"${DB_HOST}\"],\"portNumber\":[\"${DB_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" \
    --region "$AWS_REGION" &
  SSM_PID=$!

  # Wait for tunnel to be ready (poll local port)
  echo "Waiting for tunnel to be ready..." >&2
  for i in $(seq 1 60); do
    if command -v pg_isready &>/dev/null; then
      if pg_isready -h 127.0.0.1 -p "${LOCAL_PORT}" -t 2 &>/dev/null; then
        echo "SSM tunnel ready after ${i}s." >&2
        return 0
      fi
    elif python3 -c "
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect(('127.0.0.1', ${LOCAL_PORT}))
    s.close()
    sys.exit(0)
except:
    sys.exit(1)
" 2>/dev/null; then
      echo "SSM tunnel ready after ${i}s." >&2
      return 0
    fi
    # Check if SSM process died
    if ! kill -0 "$SSM_PID" 2>/dev/null; then
      echo "ERROR: SSM session failed to start. Check IAM permissions and bastion status." >&2
      SSM_PID=""
      exit 1
    fi
    sleep 1
  done

  echo "ERROR: SSM tunnel did not become ready after 60s." >&2
  exit 1
}

# Determine the host to connect to (localhost if tunneling, remote otherwise)
if [[ "$IS_CLUSTER" == true ]]; then
  CONNECT_HOST="127.0.0.1"
  CONNECT_PORT="$LOCAL_PORT"
else
  CONNECT_HOST="$DB_HOST"
  CONNECT_PORT="$DB_PORT"
fi

# --- Credential handling ---
# SECURITY: Credentials are piped directly from AWS CLI → Python stdin.
# Python writes them to files (pgpass, connstr, envvars) with 600 permissions.
# Credentials NEVER appear in shell variables, stdout, or stderr.

fetch_and_create_pgpass() {
  # Fetches creds and creates pgpass file + prints username to stdout
  aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --query SecretString \
    --output text \
    --region "$AWS_REGION" \
  | python3 -c "
import json, sys, os

creds = json.load(sys.stdin)

def pgpass_escape(s):
    return s.replace('\\\\', '\\\\\\\\').replace(':', '\\\\:')

host = '$CONNECT_HOST'
port = '$CONNECT_PORT'
dbname = '$DB_NAME'
pgpass_file = '$PGPASS_FILE'

u = pgpass_escape(creds['username'])
p = pgpass_escape(creds['password'])

with open(pgpass_file, 'w') as f:
    f.write(f'{host}:{port}:{dbname}:{u}:{p}\n')
os.chmod(pgpass_file, 0o600)

# Only the username goes to stdout — never the password
print(creds['username'])
"
}

fetch_and_create_connstr_file() {
  # Fetches creds and writes connection string to a file (NOT stdout)
  aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --query SecretString \
    --output text \
    --region "$AWS_REGION" \
  | python3 -c "
import json, sys, os, urllib.parse

creds = json.load(sys.stdin)
u = urllib.parse.quote(creds['username'], safe='')
p = urllib.parse.quote(creds['password'], safe='')
connstr = f'postgresql://{u}:{p}@$CONNECT_HOST:$CONNECT_PORT/$DB_NAME?sslmode=require'

outfile = '$CONNSTR_FILE'
with open(outfile, 'w') as f:
    f.write(connstr + '\n')
os.chmod(outfile, 0o600)
"
}

fetch_and_create_envvars_file() {
  # Fetches creds and writes env vars to a file (NOT stdout)
  aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --query SecretString \
    --output text \
    --region "$AWS_REGION" \
  | python3 -c "
import json, sys, os

creds = json.load(sys.stdin)
outfile = '$ENVVARS_FILE'

with open(outfile, 'w') as f:
    f.write(f'DB_HOST=$CONNECT_HOST\n')
    f.write(f'DB_PORT=$CONNECT_PORT\n')
    f.write(f'DB_NAME=$DB_NAME\n')
    f.write(f'DB_USER={creds[\"username\"]}\n')
    f.write(f'DB_PASSWORD={creds[\"password\"]}\n')
os.chmod(outfile, 0o600)
"
}

# --- Output based on mode ---
case "$MODE" in
  --psql)
    if [[ "$IS_CLUSTER" == true ]]; then
      start_ssm_tunnel
    fi
    echo "Fetching credentials..." >&2
    DB_USER=$(fetch_and_create_pgpass)
    echo "Connecting to ${ENV} (${CONNECT_HOST}:${CONNECT_PORT}/${DB_NAME})..." >&2
    PGPASSFILE="$PGPASS_FILE" PGSSLMODE=require PGGSSENCMODE=disable \
      psql -h "$CONNECT_HOST" -p "$CONNECT_PORT" -U "$DB_USER" -d "$DB_NAME"
    ;;

  --connection-string)
    if [[ "$IS_CLUSTER" == true ]]; then
      start_ssm_tunnel
    fi
    echo "Fetching credentials..." >&2
    fetch_and_create_connstr_file
    echo "Connection string written to: ${CONNSTR_FILE}" >&2
    echo "  (file permissions: 600, contains credentials)" >&2
    echo "  Usage: psql \$(cat ${CONNSTR_FILE})" >&2
    if [[ "$IS_CLUSTER" == true ]]; then
      echo "" >&2
      echo "  SSM tunnel is running (PID ${SSM_PID}). Connection string points to localhost:${LOCAL_PORT}." >&2
      echo "  Press Enter to stop the tunnel when done, or Ctrl+C." >&2
      read -r
    else
      echo "$CONNSTR_FILE"
    fi
    ;;

  --env-vars)
    if [[ "$IS_CLUSTER" == true ]]; then
      start_ssm_tunnel
    fi
    echo "Fetching credentials..." >&2
    fetch_and_create_envvars_file
    echo "Environment variables written to: ${ENVVARS_FILE}" >&2
    echo "  (file permissions: 600, contains credentials)" >&2
    echo "  Usage: source ${ENVVARS_FILE}" >&2
    if [[ "$IS_CLUSTER" == true ]]; then
      echo "" >&2
      echo "  SSM tunnel is running (PID ${SSM_PID}). Env vars point to localhost:${LOCAL_PORT}." >&2
      echo "  Press Enter to stop the tunnel when done, or Ctrl+C." >&2
      read -r
    else
      echo "$ENVVARS_FILE"
    fi
    ;;

  --pgpass)
    if [[ "$IS_CLUSTER" == true ]]; then
      start_ssm_tunnel
    fi
    echo "Fetching credentials..." >&2
    fetch_and_create_pgpass > /dev/null
    echo "pgpass file created: ${PGPASS_FILE}" >&2
    echo "  (file permissions: 600)" >&2
    if [[ "$IS_CLUSTER" == true ]]; then
      echo "" >&2
      echo "  SSM tunnel is running (PID ${SSM_PID}). pgpass points to localhost:${LOCAL_PORT}." >&2
      echo "  Press Enter to stop the tunnel when done, or Ctrl+C." >&2
      read -r
    else
      echo "$PGPASS_FILE"
    fi
    ;;

  --test)
    if [[ "$IS_CLUSTER" == true ]]; then
      start_ssm_tunnel
    fi
    echo "Fetching credentials..." >&2
    DB_USER=$(fetch_and_create_pgpass)
    echo "Testing connection to ${ENV}..." >&2
    PGPASSFILE="$PGPASS_FILE" PGSSLMODE=require PGGSSENCMODE=disable \
      psql -h "$CONNECT_HOST" -p "$CONNECT_PORT" -U "$DB_USER" -d "$DB_NAME" \
      -c "SELECT 1 AS connected, current_database() AS database, current_user AS \"user\", version();"
    echo "Connection OK." >&2
    ;;

  --tunnel)
    if [[ "$IS_CLUSTER" != true ]]; then
      echo "Tunnel not needed — '${ENV}' uses a publicly accessible RDS instance." >&2
      echo "Connect directly with: $0 ${ENV}" >&2
      exit 0
    fi
    start_ssm_tunnel
    echo "" >&2
    echo "=== SSM tunnel is open ===" >&2
    echo "  Local:  localhost:${LOCAL_PORT}" >&2
    echo "  Remote: ${DB_HOST}:${DB_PORT}" >&2
    echo "  Database: ${DB_NAME}" >&2
    echo "" >&2
    echo "Connect with your favorite tool:" >&2
    echo "  psql:          psql -h localhost -p ${LOCAL_PORT} -d ${DB_NAME}" >&2
    echo "  Drizzle Studio: DATABASE_URL=postgresql://user:pass@localhost:${LOCAL_PORT}/${DB_NAME} pnpm db:studio" >&2
    echo "  Any client:    localhost:${LOCAL_PORT}" >&2
    echo "" >&2
    echo "To get credentials: $0 ${ENV} --pgpass  (in another terminal while tunnel is running)" >&2
    echo "" >&2
    echo "Press Ctrl+C to stop the tunnel." >&2
    # Wait for the SSM process to exit (or Ctrl+C)
    wait "$SSM_PID" 2>/dev/null || true
    SSM_PID=""
    ;;

  *)
    echo "Unknown mode: $MODE" >&2
    echo "Usage: $0 <dev|prod> [--psql|--connection-string|--env-vars|--pgpass|--test|--tunnel]" >&2
    exit 1
    ;;
esac
