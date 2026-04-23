---
name: db-connect
description: Connect to RDS PostgreSQL databases by dynamically discovering endpoints and credentials from AWS, introspect the schema, and prepare for database operations
argument-hint: "[env: prod|dev]"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
model: sonnet
---

# Database Connection Primer

You are executing a workflow to dynamically connect to the RootNote RDS PostgreSQL database and prepare for operations. This skill discovers ALL connection details from AWS at runtime — no hardcoded endpoints, secret IDs, or passwords.

## CREDENTIAL SAFETY — MANDATORY RULES

**These rules are non-negotiable. Violating them leaks production credentials into conversation logs.**

1. **NEVER store credentials in a shell variable.** No `CREDS_JSON=$(...)`, no `PASSWORD=$(...)`. Credentials must flow directly from AWS CLI stdout → Python stdin → pgpass file. The only value that may be captured in a shell variable is the **username**.
2. **NEVER echo, print, or cat credential-containing content.** No `echo "$CREDS_JSON"`, no `cat /tmp/.pgpass_*`, no `cat /tmp/.connstr_*`, no `cat /tmp/.envvars_*`.
3. **NEVER run the companion script with `--connection-string` or `--env-vars` flags** from this skill — those modes write credentials to files for manual human use only.
4. **ALL credential handling uses a single pipeline:** `aws secretsmanager ... | python3 -c "..."` where Python reads from stdin and writes to the pgpass file. Only the username is printed to stdout.
5. **If a command fails**, do NOT retry by echoing the credentials or debugging the credential content. Re-run the full pipeline from `aws secretsmanager`.

## Configuration

- **AWS Profile**: `rootnote`
- **AWS Region**: `us-east-1`
- **RDS Instance Naming**: `rootnote-<env>-postgres` (where env is `dev` or `prod`)
- **Credentials**: Managed by RDS via AWS Secrets Manager (auto-rotated)

## User Input

```text
$ARGUMENTS
```

**Parsing `$ARGUMENTS`:**
- If empty, default to `dev`
- Parse for environment keyword: `prod` or `dev`
- Any additional text after the environment is an optional operation to perform after connecting

Example inputs:
- `dev` — Connect to dev, introspect schema, ready for operations
- `prod` — Connect to prod (read-only mode by default)
- `dev show me all tables and their row counts` — Connect and immediately run a query
- (empty) — Default to dev

## Workflow

### Step 0: Validate AWS Authentication

```bash
AWS_PROFILE=rootnote aws sts get-caller-identity --region us-east-1 2>&1
```

**If authentication fails** (error contains "ExpiredToken", "InvalidIdentityToken", "Unable to locate credentials", "Token has expired"):

1. Inform the user that AWS credentials have expired
2. Run `aws sso login --profile rootnote`
3. Wait for the browser-based authentication to complete
4. Verify authentication again
5. If still failing, stop and ask the user to authenticate manually

### Step 1: Discover RDS Database

Use the AWS CLI to dynamically discover the RDS endpoint, port, database name, and secret ARN. The script tries **Multi-AZ DB clusters first** (prod), then falls back to **single instances** (dev).

**1a. Try cluster first:**

```bash
IS_CLUSTER=false
CLUSTER_JSON=$(AWS_PROFILE=rootnote aws rds describe-db-clusters \
  --db-cluster-identifier "rootnote-<ENV>-postgres-cluster" \
  --query 'DBClusters[0]' \
  --output json \
  --region us-east-1 2>/dev/null) && IS_CLUSTER=true || IS_CLUSTER=false
```

**1b. If cluster found**, parse cluster-specific fields:

```bash
DB_STATE=$(echo "$CLUSTER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('Status', 'unknown'))")
# Cluster endpoint is a direct string (not Endpoint.Address like instances)
DB_HOST=$(echo "$CLUSTER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['Endpoint'])")
DB_PORT=$(echo "$CLUSTER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['Port'])")
DB_NAME=$(echo "$CLUSTER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['DatabaseName'])")
SECRET_ARN=$(echo "$CLUSTER_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('MasterUserSecret',{}).get('SecretArn',''))")
```

**1c. If no cluster found**, fall back to single instance:

```bash
INSTANCE_JSON=$(AWS_PROFILE=rootnote aws rds describe-db-instances \
  --db-instance-identifier "rootnote-<ENV>-postgres" \
  --query 'DBInstances[0]' \
  --output json \
  --region us-east-1)

DB_STATE=$(echo "$INSTANCE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('DBInstanceStatus', 'unknown'))")
DB_HOST=$(echo "$INSTANCE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['Endpoint']['Address'])")
DB_PORT=$(echo "$INSTANCE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['Endpoint']['Port'])")
DB_NAME=$(echo "$INSTANCE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['DBName'])")
SECRET_ARN=$(echo "$INSTANCE_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('MasterUserSecret',{}).get('SecretArn',''))")
```

If `DB_STATE` is not `available`, stop and inform the user. If `SECRET_ARN` is empty, stop — the database may not have `manage_master_user_password` enabled.

### Step 1.5: Start SSM Tunnel (clusters only)

**If `IS_CLUSTER=true`**, the database is VPC-only and requires an SSM tunnel through a bastion EC2 instance.

**Discover the bastion:**
```bash
BASTION_ID=$(AWS_PROFILE=rootnote aws ec2 describe-instances \
  --filters \
    "Name=tag:Purpose,Values=ssm-bastion-rds-access" \
    "Name=tag:Environment,Values=<ENV>" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text \
  --region us-east-1)
```

If `BASTION_ID` is empty, stop and inform the user: "No running SSM bastion instance found. Check that the bastion EC2 is running (see `infrastructure/environments/<ENV>/bastion/`)."

**Start the tunnel in background:**
```bash
LOCAL_PORT="${LOCAL_PORT:-5432}"
AWS_PROFILE=rootnote aws ssm start-session \
  --target "$BASTION_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${DB_HOST}\"],\"portNumber\":[\"${DB_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" \
  --region us-east-1 &
SSM_PID=$!
```

**Wait for tunnel readiness** (poll local port, up to 30s):
```bash
for i in $(seq 1 30); do
  if python3 -c "
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(1)
try:
    s.connect(('127.0.0.1', ${LOCAL_PORT}))
    s.close()
    sys.exit(0)
except:
    sys.exit(1)
" 2>/dev/null; then
    echo "SSM tunnel ready after ${i}s"
    break
  fi
  if ! kill -0 "$SSM_PID" 2>/dev/null; then
    echo "ERROR: SSM session failed to start"
    break
  fi
  sleep 1
done
```

**Set connection variables:**
- If cluster: `CONNECT_HOST=127.0.0.1`, `CONNECT_PORT=$LOCAL_PORT`
- If instance: `CONNECT_HOST=$DB_HOST`, `CONNECT_PORT=$DB_PORT`

**IMPORTANT:** You MUST kill the SSM tunnel (`kill $SSM_PID`) when the session is done. Always do this in the cleanup step.

### Step 2: Fetch Credentials and Create pgpass File (SINGLE PIPELINE)

**This is the critical security step.** Fetch credentials from Secrets Manager and pipe them directly into Python, which writes the pgpass file. The password never touches a shell variable.

```bash
DB_USER=$(AWS_PROFILE=rootnote aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text \
  --region us-east-1 \
| python3 -c "
import json, sys, os
creds = json.load(sys.stdin)
def esc(s):
    return s.replace('\\\\', '\\\\\\\\').replace(':', '\\\\:')
pgpass_file = '/tmp/.pgpass_rootnote_<ENV>'
with open(pgpass_file, 'w') as f:
    f.write(f'<CONNECT_HOST>:<CONNECT_PORT>:<DB_NAME>:{esc(creds[\"username\"])}:{esc(creds[\"password\"])}\n')
os.chmod(pgpass_file, 0o600)
# ONLY the username goes to stdout
print(creds['username'])
")
chmod 600 /tmp/.pgpass_rootnote_<ENV>
```

Replace `<ENV>`, `<CONNECT_HOST>`, `<CONNECT_PORT>`, `<DB_NAME>` with the actual values. For clusters, `CONNECT_HOST` is `127.0.0.1` and `CONNECT_PORT` is `$LOCAL_PORT`. For instances, use the RDS endpoint directly.

The Python script:
- Reads the JSON credentials from stdin
- Writes the pgpass file with proper escaping
- Prints ONLY the username to stdout (captured by `DB_USER=$(...)`)
- The password exists only inside the Python process and the pgpass file

### Step 3: Test Connection

```bash
PGPASSFILE=/tmp/.pgpass_rootnote_<ENV> PGSSLMODE=require PGGSSENCMODE=disable \
  psql -h "$CONNECT_HOST" -p "$CONNECT_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT 1 AS connected, current_database() AS database, current_user AS \"user\";"
```

**If connection fails**, report the error and stop. Common issues:
- Security group doesn't allow current IP -> inform user to check SG rules
- Password rotated since last fetch -> re-run the pipeline from Step 2
- RDS instance stopped -> check instance status
- SSM tunnel not ready -> check bastion instance and IAM permissions

### Step 4: Introspect Database Schema

Run these queries to discover the full schema. This gives you (and the user) complete knowledge of what's in the database without relying on hardcoded documentation that could be stale.

**4a. List all schemas:**
```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
ORDER BY schema_name;
```

**4b. List all tables with estimated row counts:**
```sql
SELECT schemaname AS schema, tablename AS table, n_live_tup AS estimated_rows
FROM pg_stat_user_tables
ORDER BY schemaname, tablename;
```

**4c. List all columns for user tables:**
```sql
SELECT table_schema, table_name, column_name, data_type,
       is_nullable, column_default
FROM information_schema.columns
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY table_schema, table_name, ordinal_position;
```

**4d. List indexes:**
```sql
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, tablename, indexname;
```

**4e. List foreign key relationships:**
```sql
SELECT
  tc.table_schema, tc.table_name, kcu.column_name,
  ccu.table_schema AS foreign_schema,
  ccu.table_name AS foreign_table,
  ccu.column_name AS foreign_column
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
ORDER BY tc.table_schema, tc.table_name;
```

Run all introspection queries using the established pgpass connection. Present the results in a clear, organized summary.

### Step 5: Present Connection Summary

After successful connection and introspection, present:

1. **Connection details** (host, port, database, user — **NEVER the password**)
2. **Schema overview** — schemas, tables, row counts
3. **Column details** — organized by schema.table
4. **Index summary**
5. **Environment safety level**:
   - `dev`: Full read/write operations allowed
   - `prod`: **READ-ONLY by default**. Warn before any write operations. Require explicit user confirmation for INSERT/UPDATE/DELETE. Never run DDL (DROP, ALTER, TRUNCATE) on prod.

6. **Inform the user** that the connection is ready and they can now ask for:
   - SQL queries (analysis, debugging, data exploration)
   - Schema inspection (detailed column types, constraints)
   - Data operations (dev only, or with explicit prod confirmation)

### Step 6: Execute Operations (if requested)

If the user included an operation in their arguments, execute it now using the established connection.

For all queries:
```bash
PGPASSFILE=/tmp/.pgpass_rootnote_<ENV> PGSSLMODE=require PGGSSENCMODE=disable \
  psql -h "$CONNECT_HOST" -p "$CONNECT_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -c "<QUERY>"
```

**Query safety rules:**
- Always include `LIMIT` clauses (start with 25-50)
- Use `WHERE _deleted = false` for soft-deleted tables (content_items, data_points, etc.)
- Set statement timeout for expensive queries: `SET statement_timeout = '30s';`
- For prod: SELECT only unless user explicitly requests writes
- For dev: All operations allowed, but confirm destructive operations (DROP, TRUNCATE, DELETE without WHERE)

## Companion Script

A standalone script is available at `scripts/db-connect.sh` for manual use outside of Claude Code:

```bash
# Interactive psql session
./scripts/db-connect.sh dev

# Create pgpass file only (safe — no credentials in output)
./scripts/db-connect.sh dev --pgpass

# Test connection (safe — no credentials in output)
./scripts/db-connect.sh dev --test

# Write connection string to a file (credentials go to FILE, not stdout)
./scripts/db-connect.sh dev --connection-string

# Write env vars to a file (credentials go to FILE, not stdout)
./scripts/db-connect.sh dev --env-vars
```

**From this skill, ONLY use `--pgpass` or `--test` modes.** The `--connection-string` and `--env-vars` modes are for manual human use only.

## Cleanup

When the conversation/session is ending or when explicitly asked, clean up:

```bash
# Kill SSM tunnel if one was started
if [[ -n "${SSM_PID:-}" ]] && kill -0 "$SSM_PID" 2>/dev/null; then
  kill "$SSM_PID" 2>/dev/null || true
fi
rm -f /tmp/.pgpass_rootnote_dev /tmp/.pgpass_rootnote_prod /tmp/.connstr_rootnote_dev /tmp/.connstr_rootnote_prod /tmp/.envvars_rootnote_dev /tmp/.envvars_rootnote_prod
```

**Do NOT clean up proactively between queries** — the pgpass file and SSM tunnel are reused for all subsequent operations in the session.

## Safety Summary

- **No credential logging**: NEVER output, echo, print, or log database passwords, credential JSON, pgpass file contents, connection strings, or env var files in any command output.
- **Single pipeline pattern**: Credentials flow `aws secretsmanager ... | python3 -c "..."` — Python reads stdin, writes pgpass file, prints only the username.
- **No credential shell variables**: The password must never be stored in a bash variable. Only the username may be captured via `$()`.
- **No credential file reads**: Never `cat`, `head`, `tail`, or `read` the pgpass, connstr, or envvars files in bash commands.
- **Credentials via pgpass only**: psql reads credentials from the pgpass file automatically via `PGPASSFILE` env var.
- **Production awareness**: When querying prod, be mindful of query performance. Use EXPLAIN before expensive queries. Avoid full table scans without filters.
- **Cleanup on exit**: Always mention that `/tmp/.pgpass_rootnote_<env>` should be cleaned up when done.
- **Dynamic discovery**: All connection details are fetched fresh from AWS each time. This handles credential rotation, endpoint changes, and instance replacements automatically.
