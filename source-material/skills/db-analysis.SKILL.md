---
name: db-analysis
description: Connect to RDS databases via dynamically discovered AWS credentials and run SQL-based analysis queries
argument-hint: "[env: prod|dev] [analysis prompt or SQL query]"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
model: opus
---

# Production Database Analysis

You are executing a workflow to connect to the RootNote RDS PostgreSQL database and run SQL-based analysis queries.

## CREDENTIAL SAFETY — MANDATORY RULES

**These rules are non-negotiable. Violating them leaks production credentials into conversation logs.**

1. **NEVER store credentials in a shell variable.** No `CREDS_JSON=$(...)`, no `PASSWORD=$(...)`. Credentials must flow directly from AWS CLI stdout → Python stdin → pgpass file. The only value that may be captured in a shell variable is the **username**.
2. **NEVER echo, print, or cat credential-containing content.** No `echo "$CREDS_JSON"`, no `cat /tmp/.pgpass_*`.
3. **ALL credential handling uses a single pipeline:** `aws secretsmanager ... | python3 -c "..."` where Python reads from stdin and writes to the pgpass file. Only the username is printed to stdout.
4. **If a command fails**, do NOT retry by echoing the credentials or debugging the credential content. Re-run the full pipeline from `aws secretsmanager`.

## Configuration

- **AWS Profile**: `rootnote`
- **AWS Region**: `us-east-1`
- **RDS Instance Naming**: `rootnote-<env>-postgres` (where env is `dev` or `prod`)
- **Credentials**: Managed by RDS via AWS Secrets Manager (auto-rotated, dynamically discovered)

### Database Schemas

The PostgreSQL database has two main schemas:

**`content` schema:**
- `content.content_items` - Synced content from platforms (posts, videos, etc.)
  - Key columns: `id`, `title`, `platform_content_id`, `platform_username`, `content_unit_name`, `type`, `sub_type`, `platform_publish_date_time`, `platform_url`, `creator_block_id`, `creator_id`, `connection_id`, `extra_data`, `_deleted`, `created_at`, `updated_at`
  - Types: `SONG`, `VIDEO`, `LIVE_VIDEO_STREAM`, `PODCAST`, `POST`, `IMAGE`, `ALBUM`, `EVENT`, `OTHER`
  - Platforms identifiable via `platform_url` domain (instagram.com, tiktok.com, youtube.com, facebook.com, twitter.com)
- `content.tags` - Tag definitions
- `content.content_items_tags` - Junction table linking content items to tags

**`metrics` schema:**
- `metrics.data_points` - Time-series metrics data
  - Key columns: `id`, `data_channel_id`, `connection_id`, `creator_id`, `value`, `string_value`, `value_type`, `date`, `extra_data`, `_deleted`, `created_at`, `updated_at`

**Related DynamoDB tables** (legacy, queried via AppSync/GraphQL - not directly accessible here):
- Creators, Connections, DataChannels, Organizations are primarily in DynamoDB
- `creator_id` and `connection_id` in PostgreSQL reference DynamoDB records

### Important Notes

- Column names in PostgreSQL use **snake_case** (e.g., `platform_username`, `content_unit_name`, `created_at`)
- Soft deletes: Always filter with `WHERE _deleted = false` unless specifically analyzing deleted items
- The `created_at` field = when the record was synced into our system, NOT when the content was originally published
- The `platform_publish_date_time` field = when the content was originally published on the platform
- The `updated_at` field = last time the record was synced/updated (engagement stats refresh, etc.)

## User Input

```text
$ARGUMENTS
```

**Parsing `$ARGUMENTS`:**
- If empty, use **AskUserQuestion** to ask what analysis the user wants to run and which environment
- Parse for environment: `prod`, `dev` (default: `prod`)
- The rest of the arguments describe the analysis to perform or contain raw SQL

Example inputs:
- `prod which creators have the most Twitter content items in the last 30 days` - Natural language analysis request
- `dev SELECT COUNT(*) FROM content.content_items WHERE _deleted = false` - Raw SQL query
- `show me content item creation trends by platform for the last 3 months` - Defaults to prod
- `prod top 10 connections by update frequency this week` - Specific analysis request

## Workflow Steps

### Step 0: Validate AWS Authentication

Check if AWS CLI is authenticated with the rootnote profile:

```bash
AWS_PROFILE=rootnote aws sts get-caller-identity --region us-east-1 2>&1
```

**If authentication fails** (error contains "ExpiredToken", "InvalidIdentityToken", "Unable to locate credentials", "Token has expired", or similar):

1. Inform the user that AWS credentials have expired
2. Attempt to refresh SSO credentials:

```bash
aws sso login --profile rootnote
```

3. Wait for the browser-based authentication to complete
4. Verify authentication again with `aws sts get-caller-identity`
5. If still failing, stop and inform the user to manually authenticate

**If authentication succeeds**, proceed to Step 1.

### Step 1: Discover RDS Database

Use the AWS CLI to dynamically discover the RDS endpoint, port, database name, and secret ARN. Try **Multi-AZ DB clusters first** (prod), then fall back to **single instances** (dev).

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
pgpass_file = '/tmp/.pgpass_rootnote_analysis_<ENV>'
with open(pgpass_file, 'w') as f:
    f.write(f'<CONNECT_HOST>:<CONNECT_PORT>:<DB_NAME>:{esc(creds[\"username\"])}:{esc(creds[\"password\"])}\n')
os.chmod(pgpass_file, 0o600)
# ONLY the username goes to stdout
print(creds['username'])
")
```

Replace `<CONNECT_HOST>`, `<CONNECT_PORT>`, `<DB_NAME>` with the actual values. For clusters, `CONNECT_HOST` is `127.0.0.1` and `CONNECT_PORT` is `$LOCAL_PORT`. For instances, use the RDS endpoint directly.

The Python script:
- Reads the JSON credentials from stdin
- Writes the pgpass file with proper escaping
- Prints ONLY the username to stdout (captured by `DB_USER=$(...)`)
- The password exists only inside the Python process and the pgpass file

Test the connection:

```bash
PGPASSFILE=/tmp/.pgpass_rootnote_analysis_<ENV> PGSSLMODE=require PGGSSENCMODE=disable \
  psql -h "$CONNECT_HOST" -p "$CONNECT_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT 1 AS connected, current_database() AS database, current_user AS \"user\";"
```

**If connection fails**, report the error and stop.

### Step 3: Run Analysis

Based on the user's request, either:

**A) Raw SQL**: If the user provided a SQL query, run it directly:
```bash
PGPASSFILE=/tmp/.pgpass_rootnote_analysis_<ENV> PGSSLMODE=require PGGSSENCMODE=disable \
  psql -h "$CONNECT_HOST" -p "$CONNECT_PORT" -U "$DB_USER" -d "$DB_NAME" \
  -c "<SQL_QUERY>"
```

**B) Natural language analysis**: Translate the user's request into appropriate SQL queries. Use your knowledge of the schema to:
1. Write efficient queries (use appropriate indexes, filters, limits)
2. Start broad, then drill down based on initial results
3. Run multiple queries in parallel when independent
4. Present results in clear markdown tables with analysis

**Query safety guidelines:**
- ONLY run SELECT queries - never INSERT, UPDATE, DELETE, DROP, ALTER, or any DDL/DML
- Always include reasonable LIMIT clauses (start with LIMIT 25-50)
- Use `WHERE _deleted = false` unless analyzing deletions
- For large tables, prefer aggregations over full table scans
- Set reasonable timeouts (30 seconds max per query)

**Analysis best practices:**
- Start with overview/summary queries to understand scope
- Follow up with detailed breakdowns based on what the overview reveals
- Compare time periods (this week vs last week, this month vs last month)
- Identify outliers and anomalies
- Group by meaningful dimensions (creator, platform, connection, time period)
- Calculate rates and percentages, not just raw counts

### Step 4: Present Results

Format results as:
1. **Summary**: High-level findings in 2-3 sentences
2. **Data tables**: Well-formatted markdown tables with key metrics
3. **Analysis**: Interpretation of what the data shows
4. **Recommendations** (if applicable): Suggested actions based on findings
5. **Follow-up queries**: Suggest what to investigate next if the user wants to dig deeper

### Step 5: Cleanup

Always clean up the temporary credentials file and SSM tunnel when done:

```bash
# Kill SSM tunnel if one was started
if [[ -n "${SSM_PID:-}" ]] && kill -0 "$SSM_PID" 2>/dev/null; then
  kill "$SSM_PID" 2>/dev/null || true
fi
rm -f /tmp/.pgpass_rootnote_analysis_dev /tmp/.pgpass_rootnote_analysis_prod
```

## Error Handling

- **AWS authentication fails after SSO login**: Suggest checking AWS CLI configuration
- **Database connection fails**: Check if the password was rotated, re-run the full credential pipeline from Step 2. For clusters, verify SSM tunnel is running.
- **SSM tunnel fails to start**: Check that the bastion EC2 instance is running and the Session Manager plugin is installed (`brew install --cask session-manager-plugin`)
- **No bastion instance found**: The bastion may not be deployed for this environment. See `infrastructure/environments/<ENV>/bastion/`
- **Query timeout**: Suggest adding more filters or breaking into smaller queries
- **Permission denied on table**: Note which tables are accessible and which aren't
- **Empty results**: Suggest broadening filters or checking if data exists in the time range

## Safety

- **READ-ONLY**: This skill only runs SELECT queries. Never execute write operations against the database.
- **No credential shell variables**: The password must never be stored in a bash variable. Only the username may be captured via `$()`.
- **No credential file reads**: Never `cat`, `head`, `tail`, or `read` the pgpass file in bash commands.
- **Single pipeline pattern**: Credentials flow `aws secretsmanager ... | python3 -c "..."` — Python reads stdin, writes pgpass file, prints only the username.
- **Credentials cleanup**: Always remove the temporary pgpass file after analysis, even if errors occur.
- **No credential logging**: Never output database passwords in results or logs.
- **Production awareness**: When querying prod, be mindful of query performance. Avoid full table scans on large tables without filters.
- **Dynamic discovery**: All connection details (endpoints, secret ARNs) are fetched fresh from AWS each time. No hardcoded hosts or secret IDs that could become stale.
