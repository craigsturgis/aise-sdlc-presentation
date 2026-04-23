---
name: cloudwatch-errors
description: Review production CloudWatch logs for errors, prioritize them, run Five Whys analysis, and create Linear issues
argument-hint: "[time-range: 1h|6h|24h|7d] [log-group: amplify|lambda|api|batch|all] [env: prod|dev]"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion, mcp__linear__create_issue, mcp__linear__get_issue, mcp__linear__list_teams, mcp__linear__list_issues, Skill
model: opus
---

# CloudWatch Error Review Workflow

You are executing an automated workflow to:
1. Verify AWS CLI authentication (and log in if needed)
2. Query production CloudWatch logs for errors
3. Parse, deduplicate, and categorize errors
4. Help the user prioritize which errors to address
5. Run Five Whys root cause analysis on selected errors
6. Create Linear issues to track each fix

## Configuration

- **AWS Profile**: `rootnote`
- **AWS Region**: `us-east-1`
- **Linear Team**: `RootNote`
- **Default Environment**: `prod` (can specify `dev` to include dev logs)

### CloudWatch Log Groups

#### Amplify Web App
| Alias | Log Group Name | Description |
|-------|----------------|-------------|
| `amplify` | `/aws/amplify/<AMPLIFY_APP_ID>` | Next.js SSR and build logs |

#### Lambda Functions (prod)
| Alias | Log Group Name | Description |
|-------|----------------|-------------|
| `lambda-auth` | `/aws/lambda/ConnectAuthUserToCognito-prod` | Auth user connection |
| `lambda-content` | `/aws/lambda/CreateContentItem-prod` | Content item creation |
| `lambda-datapoint` | `/aws/lambda/CreateDataPoint-prod` | Data point creation |
| `lambda-cron` | `/aws/lambda/CronGetItemContentStatsScript-prod` | Scheduled content stats |
| `lambda-router` | `/aws/lambda/GetAppDataRouter-prod` | Main data routing |
| `lambda-connection` | `/aws/lambda/GetConnectionData-prod` | Connection data fetch |
| `lambda-facebook` | `/aws/lambda/GetFacebookContent-prod`, `/aws/lambda/GetFacebookData-prod` | Facebook integration |
| `lambda-instagram` | `/aws/lambda/GetInstagramContent-prod`, `/aws/lambda/GetInstagramData-prod` | Instagram integration |
| `lambda-tiktok` | `/aws/lambda/GetTikTokContent-prod`, `/aws/lambda/GetTikTokData-prod` | TikTok integration |
| `lambda-youtube` | `/aws/lambda/GetYouTubeContent-prod`, `/aws/lambda/GetYouTubeData-prod` | YouTube integration |
| `lambda-twitter` | `/aws/lambda/GetTwitterContent-prod`, `/aws/lambda/GetTwitterData-prod` | Twitter/X integration |
| `lambda-twitch` | `/aws/lambda/GetTwitchData-prod` | Twitch integration |
| `lambda-mailchimp` | `/aws/lambda/GetMailchimpData-prod` | Mailchimp integration |
| `lambda-ingestion` | `/aws/lambda/TriggerDataIngestion-prod`, `/aws/lambda/TriggerDataIngestionBlock-prod` | Data ingestion triggers |
| `lambda-upload` | `/aws/lambda/ImageUploadToS3-prod`, `/aws/lambda/ProcessFileUpload-prod`, `/aws/lambda/s3TriggerFileUpload-prod` | File uploads |
| `lambda-cognito` | `/aws/lambda/appAbc12345PreSignup-prod`, `/aws/lambda/appAbc12345CreateAuthChallenge-prod`, `/aws/lambda/appAbc12345DefineAuthChallenge-prod`, `/aws/lambda/appAbc12345VerifyAuthChallengeResponse-prod` | Cognito auth triggers |
| `lambda-email` | `/aws/lambda/SendCreatorOnboardingEmail-prod` | Email sending |
| `lambda-queue` | `/aws/lambda/QueueCreatorConnections-prod` | Connection queue processing |

#### ECS Services
| Alias | Log Group Name | Description |
|-------|----------------|-------------|
| `api` | `/aws/ecs/rootnote-api-prod` | Fastify API service |
| `batch` | `/aws/ecs/rootnote-batch-jobs-prod` | Scheduled batch jobs |

#### API Gateway
| Alias | Log Group Name | Description |
|-------|----------------|-------------|
| `apigw` | `/aws/apigateway/rootnote-prod-api/default` | API Gateway access logs |

### Log Group Shortcuts

When user specifies a group alias:
- `amplify` - Query Amplify web app logs only
- `lambda` - Query ALL Lambda function logs (prod)
- `api` - Query ECS API service logs only
- `batch` - Query ECS batch jobs logs only
- `apigw` - Query API Gateway logs only
- `all` - Query all log groups (default)

### Environment Selection

- `prod` (default) - Query production log groups only
- `dev` - Query development log groups (replace `-prod` suffix with `-dev` in Lambda/ECS names)

## User Input

```text
$ARGUMENTS
```

**Parsing `$ARGUMENTS`:**
- If empty, default to `time-range=24h`, `log-group=all`, `env=prod`
- Parse for time range: `1h`, `6h`, `24h`, `7d` (default: `24h`)
- Parse for log group: `amplify`, `lambda`, `api`, `batch`, `apigw`, `all` (default: `all`)
- Parse for environment: `prod`, `dev` (default: `prod`)

Example inputs:
- `lambda` - Last 24 hours (default), all Lambda logs (prod)
- `7d amplify` - Last 7 days, Amplify logs only
- `1h all dev` - Last 1 hour, all log groups, dev environment
- `6h api` - Last 6 hours, API service logs (prod)

## Workflow Steps

### Step 0: Validate AWS Authentication

Check if AWS CLI is authenticated and has access to the rootnote profile:

```bash
AWS_PROFILE=rootnote aws sts get-caller-identity 2>&1
```

**If authentication fails** (error contains "ExpiredToken", "InvalidIdentityToken", "Unable to locate credentials", or similar):

1. Inform the user that AWS credentials have expired or are missing
2. Attempt to refresh SSO credentials:

```bash
aws sso login --profile rootnote
```

3. Wait for the browser-based authentication to complete
4. Verify authentication again with `aws sts get-caller-identity`
5. If still failing, stop and inform the user to manually authenticate

**If authentication succeeds**, proceed to Step 1.

### Step 1: Query CloudWatch Logs for Errors

Calculate the time range based on user input:
- `1h` = 3600000 ms
- `6h` = 21600000 ms
- `24h` = 86400000 ms
- `7d` = 604800000 ms

**Query Strategy:**
1. For `all` or `lambda` aliases, query the most important Lambda functions first (auth, ingestion, router)
2. Limit each query to 50 events to avoid overwhelming output
3. Use parallel queries where possible

For each selected log group, query for error-level logs:

```bash
# Calculate start time (milliseconds since epoch)
START_TIME=$(($(date +%s) * 1000 - <TIME_RANGE_MS>))

# Query logs - filter for errors (exclude expected warnings)
AWS_PROFILE=rootnote aws logs filter-log-events \
  --log-group-name "<LOG_GROUP_NAME>" \
  --start-time $START_TIME \
  --filter-pattern '?"ERROR" ?"Error" ?"error" ?"Exception" ?"exception" ?"FATAL" ?"fatal" ?"Failed" ?"failed" -"Initial download failed, attempting fallback"' \
  --limit 50 \
  --region us-east-1 \
  --output json
```

**Note**: The filter excludes known noisy errors like TikTok image download failures.

### Step 2: Parse and Categorize Errors

For each log event returned, extract:
- **Timestamp**: When the error occurred
- **Log Stream**: Which container/instance/Lambda invocation
- **Message**: The error message
- **Error Type**: Parse from the message (TypeError, ValidationError, NetworkError, etc.)
- **Stack Trace**: If present in the message
- **Source**: Which log group/service

**Deduplication Strategy:**
1. Group errors by their error message (ignoring timestamps and variable data like IDs, request IDs)
2. For each unique error, track:
   - First occurrence
   - Last occurrence
   - Total count
   - Sample stack trace (from most recent occurrence)
   - Affected log groups/services

**Categorization:**
- **Critical**: Database errors, authentication failures, payment processing errors, Cognito errors
- **High**: API 5xx errors, unhandled exceptions, null reference errors, Lambda timeouts
- **Medium**: Validation errors, retry failures, timeout warnings, third-party API errors
- **Low**: Deprecation warnings, rate limiting, expected error conditions, already-handled errors

### Step 3: Present Error Summary

Display a summary table of unique errors:

```
## Error Summary for Last [TIME_RANGE] ([ENVIRONMENT])

| # | Category | Service | Error Type | Message (truncated) | Count | First Seen | Last Seen |
|---|----------|---------|------------|---------------------|------:|------------|-----------|
| 1 | Critical | lambda-auth | CognitoError | User pool not found... | 5 | 2h ago | 10m ago |
| 2 | High | api | TypeError | Cannot read property 'id'... | 42 | 6h ago | 5m ago |
| 3 | Medium | lambda-tiktok | APIError | Rate limit exceeded... | 8 | 1h ago | 30m ago |
```

**If no errors found:**
- Report that no errors were found in the specified time range
- Suggest expanding the time range or checking a different log group
- Stop workflow

### Step 4: Prioritize and Select Errors

Use **AskUserQuestion** to help the user select which errors to investigate:

Present options based on:
1. **By priority**: Start with Critical, then High severity
2. **By frequency**: Most frequent errors first
3. **By recency**: Most recent errors first
4. **Custom selection**: Let user pick specific error numbers

Allow multi-select for batch processing.

**Recommendation heuristic:**
- Prioritize Critical/High severity errors
- Among same severity, prefer higher frequency (indicates broader impact)
- Flag errors that started recently (potential regression)
- Highlight errors affecting multiple services (systemic issues)

### Step 5: Investigate Selected Errors

For each selected error, perform detailed investigation:

1. **Get full error details**:
   ```bash
   # Get more context around the error
   AWS_PROFILE=rootnote aws logs filter-log-events \
     --log-group-name "<LOG_GROUP_NAME>" \
     --start-time <SPECIFIC_TIME_RANGE> \
     --filter-pattern "<SPECIFIC_ERROR_MESSAGE>" \
     --limit 10 \
     --region us-east-1
   ```

2. **Search the codebase** for related code:
   - Look for the function/component mentioned in the stack trace
   - Find related error handling
   - Check for recent changes in git history

3. **Correlate with other logs**:
   - Look for related request IDs or trace IDs
   - Check if errors correlate across services (e.g., Lambda -> API)

### Step 6: Run Five Whys Analysis

For each selected error, conduct a Five Whys root cause analysis.

#### Procedure:

1. **Establish the problem statement** from the CloudWatch error:
   - What is the exact error message?
   - Which service/Lambda is affected?
   - When and where does it occur?
   - What is the observable impact?

2. **Investigate the codebase**:
   - Search for the error message or stack trace components
   - Find the originating code
   - Check recent changes that might have introduced the issue
   - For Lambda errors, check `/amplify/backend/function/` directory
   - For API errors, check `/services/rootnote-api/` directory

3. **Conduct the Why iterations**:
   ```
   **Why #N**: [Question based on previous answer]
   **Investigation**: [Files/logs examined]
   **Answer**: [Factual answer with evidence]
   ```

4. **Identify root cause and contributing factors**

5. **Document recommendations**:
   - **Immediate fix**: Resolve the symptom
   - **Root cause fix**: Prevent recurrence
   - **Prevention**: Process/tooling improvements

#### Handling Inconclusive Analysis

If the analysis doesn't reach a clear root cause:
- Document partial findings
- List open questions
- Mark as "Investigation Needed" in Linear
- Suggest next steps (additional logging, reproduction steps, etc.)

### Step 7: Check for Existing Linear Issues

Before creating a new issue, search for existing issues that might be related:

```
Use mcp__linear__list_issues with:
- team: "RootNote"
- query: "<error keywords>"
- state: "backlog,todo,in_progress"
```

If a related issue exists:
- Show it to the user
- Ask if they want to update the existing issue or create a new one
- If updating, add a comment with the new CloudWatch findings

### Step 8: Create Linear Issues

For each error that needs a new issue, use Linear MCP to create:

- **Team**: `RootNote`
- **Title**: Prefix with "(CloudWatch) " followed by a descriptive title
  - Example: "(CloudWatch) Fix Cognito auth timeout in ConnectAuthUserToCognito Lambda"
- **Description**:
  ```markdown
  ## CloudWatch Error

  - **Environment**: [prod/dev]
  - **Service**: [Lambda name / ECS service / Amplify]
  - **Log Group**: [LOG_GROUP_NAME]
  - **Error Type**: [ERROR_TYPE]
  - **Error Message**:
    ```
    [FULL_ERROR_MESSAGE]
    ```
  - **First Seen**: [TIMESTAMP]
  - **Last Seen**: [TIMESTAMP]
  - **Occurrences**: [COUNT] times in last [TIME_RANGE]

  ### Sample Stack Trace
  ```
  [STACK_TRACE if available]
  ```

  ## Five Whys Analysis

  ### Problem Statement
  [Clear description of the observable problem]

  ### Analysis Chain

  | # | Why? | Answer |
  |---|------|--------|
  | 1 | [Initial problem] | [First-level cause] |
  | 2 | Why [first-level cause]? | [Second-level cause] |
  | ... | ... | ... |

  ### Root Cause
  [The fundamental cause identified]

  ## Recommendations

  **Immediate Fix:**
  [What to do now]

  **Root Cause Fix:**
  [What to change systemically]

  **Prevention:**
  [How to prevent similar issues]

  ## Related CloudWatch Insights

  To investigate further:
  ```
  AWS_PROFILE=rootnote aws logs filter-log-events --log-group-name "[LOG_GROUP]" --filter-pattern "[ERROR_PATTERN]" --start-time [TIMESTAMP] --region us-east-1
  ```
  ```
- **Labels**: `["Bug", "Production"]` (or `["Bug", "Development"]` for dev errors)
- **Priority**: Map from error category (Critical=1, High=2, Medium=3, Low=4)

### Step 9: Summary Report

After processing all selected errors, provide a summary:

```markdown
## CloudWatch Error Review Complete

### Environment: [prod/dev]
### Time Range: [TIME_RANGE]
### Log Groups Queried: [LIST]

### Issues Created
| Linear ID | Title | Priority | Service | Root Cause |
|-----------|-------|----------|---------|------------|
| ROO-XXX | (CloudWatch) Fix auth timeout | Urgent | lambda-auth | Connection pool exhaustion |
| ROO-YYY | (CloudWatch) Handle null user | High | api | Missing null guard |

### Issues Updated
| Linear ID | Update |
|-----------|--------|
| ROO-ZZZ | Added new CloudWatch findings |

### Errors Skipped
- [Reason for any errors not processed]

### Recommendations
- [Any patterns noticed across errors]
- [Suggestions for monitoring improvements]
- [Systemic issues to address]
```

## Error Handling

- **AWS authentication fails after SSO login**: Suggest checking AWS CLI configuration and profile setup
- **No logs returned**: Check if the time range is correct and log group exists
- **Linear API fails**: Report error and provide manual issue creation instructions
- **Rate limiting**: Add delays between API calls and inform user of progress
- **Log group doesn't exist**: Skip and note in output, continue with other groups

## Advanced Options

If the user wants more control, support these additional parameters:

- `--filter "<pattern>"` - Custom CloudWatch filter pattern
- `--exclude "<pattern>"` - Exclude errors matching pattern (e.g., known issues)
- `--dry-run` - Show what would be created without creating Linear issues

## Notes

- Errors are deduplicated by message to avoid creating duplicate issues
- The workflow is interactive - user confirms before creating issues
- Five Whys analysis may require reading multiple files to trace the error
- Consider checking Sentry for correlated frontend errors (use `/sentry-fix` skill)
- Follow TDD practices when implementing fixes
- Lambda source code is in `/amplify/backend/function/<FunctionName>/src/`
- API source code is in `/services/rootnote-api/src/`
