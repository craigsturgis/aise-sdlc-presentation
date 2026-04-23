# Batch Jobs Service

Shared ECS Fargate container that runs scheduled batch jobs. A single Docker image serves all jobs -- the `JOB_NAME` environment variable selects which job to execute.

## Architecture

- **Dispatch**: `src/index.ts` reads `JOB_NAME` env var and routes to the matching job in the `JOBS` registry
- **Scheduling**: EventBridge rules trigger ECS tasks on cron schedules (configured in `infrastructure/environments/{env}/ecs-scheduled-tasks/`)
- **Task definition**: `rootnote-batch-jobs-{environment}` in `infrastructure/environments/{env}/ecs/terragrunt.hcl`
- **Exit codes**: 0 = success, 1 = partial failure, 2 = fatal error

## CRITICAL: ECS Restart Policy

**Always set `restartPolicy = { enabled = false }` in the task definition.** The ECS module defaults to restarting completed containers. For batch jobs this means the job runs, exits, restarts, and runs again indefinitely. This caused duplicate email sends in production.

## Available Jobs

| Job Name | Schedule | What It Does |
|---|---|---|
| `weekly-email` | Mon 10am UTC | Sends weekly performance summary emails |
| `twitter-content-stats` | Daily 1pm UTC | Posts Twitter content stats to Slack |
| `data-sync-monitor` | Daily 11am UTC | Checks platform sync health, reports to Slack |
| `email-engagement-report` | Daily 12pm UTC | Queries Resend API for email engagement stats |
| `daily-activation-stats` | Daily 9am UTC | Calculates signup-to-activation funnel for Slack |
| `posthog-slack-stats` | Daily/Weekly/Monthly | Fetches PostHog insights, posts to Slack |

## Adding a New Job

1. Create a new directory under `src/jobs/<job-name>/`
2. Implement a `job-orchestrator.ts` that exports an async execution function
3. Register the function in the `JOBS` map in `src/index.ts`
4. Add an EventBridge schedule in `infrastructure/environments/{env}/ecs-scheduled-tasks/`
5. Use `logger.*` (not `console.*`) for all logging -- integrates with CloudWatch
6. Return a result object from the job function (logged as JSON in the summary)
7. Use `isShutdownRequested()` in long-running loops to support ECS SIGTERM graceful shutdown

## Development

```bash
pnpm install                # Install dependencies
pnpm dev                    # Run locally (uses .env.local)
pnpm build                  # Build for production
pnpm test                   # Run tests
```

### Testing Jobs Locally

```bash
JOB_NAME=weekly-email DRY_RUN=true pnpm dev                    # Dry run
JOB_NAME=weekly-email TEST_USERS_EMAILS="you@example.com" pnpm dev  # Specific users
```

## Shared Code

`src/shared/` contains utilities shared across jobs:
- `lib/db.ts` -- PostgreSQL connection (Drizzle ORM)
- `lib/logger.ts` -- Structured logger for CloudWatch
- `lib/sentry.ts` -- Error tracking
- `lib/slack.ts` -- Slack webhook integration (used by monitoring/stats jobs)
