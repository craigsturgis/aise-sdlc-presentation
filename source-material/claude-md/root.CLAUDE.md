# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Detailed guidelines are split into scoped files that load only when relevant:
- `.claude/rules/testing.md` — TDD, testing pyramid, test type selection (loads near test files)
- `.claude/rules/pg-migration.md` — PG migration patterns, PG flag gotchas (loads near API/DB code)
- `.claude/rules/security.md` — credentials, PII logging, secret handling (loads near server code)
- `.claude/rules/pre-implementation-review.md` — pre-coding checklist for write paths (loads near API/DB code)
- `.claude/rules/visual-verification.md` — Showboat, agent-browser demos (loads near demos/e2e)
- `services/rootnote-api/CLAUDE.md` — API service dev commands and config
- `services/batch-jobs/CLAUDE.md` — ECS scheduled jobs, JOB_NAME dispatch, adding new jobs
- `packages/sync-core/CLAUDE.md` — platform adapter patterns and error classification
- `amplify/CLAUDE.md` — Amplify env vars (CRITICAL), team-provider-info rules
- `infrastructure/CLAUDE.md` — Terragrunt, ECS, bastion, SSM

## Monorepo Structure

pnpm workspaces monorepo:
- `/web` — Next.js 13+ web application (main frontend)
- `/amplify` — AWS Amplify backend infrastructure
- `/packages` — Shared packages (`sync-core`, `db`, etc.)
- `/services` — Microservices (`rootnote-api`, `sync-worker`)
- `/util-scripts` — Utility scripts
- `/admin-tools` — Administrative tooling

## Technology Stack

- **Frontend**: Next.js 13, TypeScript, React 18, Redux Toolkit, TailwindCSS, shadcn/ui, Radix UI
- **Backend**: Fastify 5 (rootnote-api), AWS Amplify Gen 1 v6, GraphQL (AppSync)
- **Database**: PostgreSQL (RDS) + Drizzle ORM; legacy DynamoDB (migrating to PG)
- **Auth**: AWS Cognito + NextAuth.js
- **Infra**: Terragrunt + Terraform, ECS Fargate, S3, Lambda
- **Testing**: Vitest (unit), Playwright (E2E), Storybook
- **CI/CD**: GitHub Actions + AWS Amplify
- **Monitoring**: Sentry, CloudWatch
- **Email**: React Email

## Common Commands

### Development
```bash
pnpm dev:web                # Start web dev server (uses PORT from web/.env.local)
pnpm storybook:web          # Start Storybook
pnpm build:web              # Build web application
pnpm email:web              # Email template dev server
```

### Testing
```bash
pnpm test:ci:web                                         # All unit tests (CI mode)
pnpm --filter @rootnote/web test:ci -- path/to.spec.ts   # Specific test file
pnpm --filter @rootnote/web test:e2e                     # Playwright E2E tests
pnpm --filter @rootnote/web test:e2e:ui                  # Playwright interactive UI
```

> **IMPORTANT**: Never use `pnpm test:web` from Claude Code — `--watch` hangs. Always use `test:ci`.

### Quality Checks
```bash
pnpm lint:web --quiet                    # ESLint
pnpm --filter @rootnote/web typecheck    # TypeScript compilation
```

### Database
```bash
pnpm --filter @rootnote/db db:generate  # Generate migrations from schema changes (schema in packages/db/src/schema.ts)
pnpm --filter @rootnote/db db:migrate   # Run pending migrations
pnpm --filter @rootnote/db db:studio    # Drizzle Studio
```

### Remote Database Access
```bash
./scripts/db-connect.sh dev              # Direct connection (dev is publicly accessible)
./scripts/db-connect.sh prod             # SSM tunnel (prod is VPC-only)
./scripts/db-connect.sh prod --tunnel    # Open tunnel for GUI clients
```
Prerequisites: AWS CLI v2 + SSO login (`aws sso login --profile rootnote`), Session Manager plugin, psql.

### Regression Testing
```bash
./scripts/run-regression.sh dev                  # All suites against dev
./scripts/run-regression.sh dev --suite dataspaces  # Specific suite
./scripts/run-regression.sh prod --suite smoke   # Smoke tests against prod
pnpm regression dev --suite dataspaces           # pnpm alias
```
The `/regression` Claude Code skill wraps this with Amplify build awareness.

### Infrastructure
```bash
cd infrastructure && terragrunt plan    # Preview infra changes
cd infrastructure && terragrunt apply   # Apply infra changes
```
See `infrastructure/CLAUDE.md` for detailed guidance.

## Data Architecture

GraphQL with AWS AppSync as the primary API layer. Key models: Creator, Connection, DataChannel, ContentItem, Organization, Board/Dataspace.

External integrations: Instagram, Twitter/X, Facebook, TikTok, YouTube, Twitch, Shopify, Stripe, Mailchimp, Twilio, SendGrid, Slack, Mixpanel, Sentry.

## Package Manager

- **`pnpm`** for the monorepo. Use it for all workspace commands.
- **`yarn`** only for Lambda functions under `amplify/`.
- **Never** use `npm`.

## Git Workflow

- Always branch from `dev`, not `main`. Pattern: `feat/ROO-XXX-description` or `fix/ROO-XXX-description`.
- When pre-commit hooks fail due to flaky/unrelated tests, retry once, then `--no-verify` if clearly unrelated. Note in commit message.
- To delete tracked directories, use `git rm -r <relative-path>` rather than `rm -rf <absolute-path>`.

## File Organization

- Components: `/web/components` (by feature)
- API routes: `/web/pages/api`
- Redux slices: `/web/src/store`
- Utilities: `/web/src/utils`
- Database: `/web/src/lib/db/`
- Email Templates: `/web/src/email/`
- Playwright E2E: `/web/e2e/`
- GraphQL: co-located with components

## Environment Configuration

- Secrets: AWS Systems Manager Parameter Store
- Local: `.env.local` files
- Build-time: `amplify.yml`
- **Port**: Each worktree has its own `PORT` in `web/.env.local`. Dev servers and Playwright read from this.
- **Amplify env var changes**: Always fetch existing vars first before calling `update-branch` -- it REPLACES, not merges. See `amplify/CLAUDE.md`.

## Important Development Notes

1. **Branch Strategy**: Always branch from `dev`, not `main`
2. **Database Modifications**: Never edit DynamoDB directly — use Amplify Studio
3. **API Development**: GraphQL schema in `/amplify/backend/api/rootnote/schema.graphql`
4. **Component Development**: Use Storybook for isolated component development
5. **State Management**: Redux Toolkit with feature-based slices
6. **Styling**: Tailwind classes + established design system
7. **Testing**: TDD — write failing tests FIRST. Vitest for unit, Playwright for E2E
8. **Linting**: `pnpm lint:web --quiet` before committing
9. **TypeScript**: No compilation errors before finishing a task
10. **Database Migrations**: NEVER manually create — use `db:generate` after schema changes
11. **Infrastructure**: Terragrunt only, never modify AWS directly (see `infrastructure/CLAUDE.md`)
12. **ECS Batch Jobs**: Always set `restartPolicy = { enabled = false }` — the module default restarts completed jobs indefinitely. This caused duplicate email sends in production. See `services/batch-jobs/CLAUDE.md`.
13. **Memory**: `NODE_OPTIONS="--max-old-space-size=4096"` for build memory issues
14. **Component Refactoring**: Check all references including Storybook
15. **Environment Sync**: Ensure `.env.local` matches Parameter Store for dev
16. **Test File Placement**: NEVER in `web/pages/` (non-API). Use `web/src/__tests__/pages/` instead.

## Code Quality Rules

### Operator and Logger Conventions
- **Use `??` instead of `||`** for numeric and string fallbacks. Use `||` only when empty string or zero should also trigger the fallback.
- **Use `logger.error`/`logger.warn`** instead of `console.error`/`console.warn` in server-side code.
- **Use `unknown` instead of `any`** in catch blocks. Narrow with type guards.
- **Partial DB updates**: `field: value ?? null` erases existing values when `value` is `undefined`. Use conditional spread: `...(value !== undefined && { field: value })`.

### Error Handling
- **No silent error swallowing**: Every `catch` must re-throw, return a meaningful value, or log.
- **Error messages must include context**: which operation failed, what input caused it.
- **Never cache error responses**: transient failures would permanently suppress correct behavior.

### Dead Code
- Remove all dead code before review: unused imports, variables, unreachable paths. Run `pnpm lint:web --quiet`.
- After removing a dependency or swapping a library (e.g. Grommet→shadcn), grep the repo for lingering imports of the old library and remove them in the same PR.

### Mobile UI Gotchas
- **iOS Safari drops sessionStorage across third-party OAuth redirects** (especially private browsing / ITP). For OAuth return routing, make the OAuth callback URL the authoritative source of state — put `connectionId`, `platform`, and `fromOnboarding` in query params. Treat sessionStorage only as a fallback, never as required.
- **shadcn/vaul `Drawer` with `h-auto` clips its footer on short mobile viewports.** Any Drawer hosting multi-section content (presets + calendar + footer, forms, etc.) must cap height with `max-h-[calc(100svh-Xrem)]` on `DrawerContent` and wrap the long body in `overflow-y-auto` with the footer pinned via `shrink-0`.

## Development Workflow

- Follow TDD (Red -> Green -> Refactor): write a failing test FIRST, implement the minimum to pass, then refactor.
- When reading a Linear ticket for a bug, focus on root cause before proposing a fix. Analyze CloudWatch logs if needed.

### Quick Test Type Guide

Pick the right test type before writing your first test (full guide in `.claude/rules/testing.md`):
- **Utility function, hook, Redux slice** -> Unit test (Vitest)
- **React component** -> Unit test + Storybook
- **API route, DB service** -> Integration test (Vitest)
- **Full user workflow** -> E2E test (Playwright)
- **Bug fix** -> Test at the level that reproduces it

## MCP Tools

- Use exact tool names. Chrome DevTools MCP is `chrome-devtools`, NOT `claude-in-chrome`.

## Demo Documentation

After every feature or bug fix, create a Showboat demo doc -- see `.claude/rules/visual-verification.md` for commands.

## Common Issues & Solutions

- **DB Connection**: Check `DATABASE_URL` in `.env.local`. Prod: use `./scripts/db-connect.sh prod` (SSM tunnel).
- **Build Memory**: `NODE_OPTIONS="--max-old-space-size=4096" pnpm build:web`
- **PageNotFoundError**: Test file in `web/pages/` — move to `web/src/__tests__/pages/`.
- **Playwright skipped**: Check AWS credentials (`aws sso login`). First load: 60s+ for Next.js compilation.
- **networkidle hangs**: Use `domcontentloaded` instead.
- **SSM tunnel errors**: Check AWS SSO login, verify bastion is running.
- **Port conflict on 5432**: Use `LOCAL_PORT=54320 ./scripts/db-connect.sh prod --tunnel`.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->

## Beads ↔ Linear Linkage (no shadow backlog)

This section lives outside the auto-generated beads integration block so `bd prime` regenerations don't wipe it.

- **Every bead must reference a Linear issue** (`ROO-xxxx`) in its title or description. Beads are a local execution view of Linear work, not a parallel backlog.
- Multiple beads **may** link to the same Linear issue when a ticket is decomposed into digestible chunks — that's the right pattern for large tickets.
- Before creating a new bead, check whether a Linear issue already covers the work. If not, create the Linear issue **first**, then create the bead referencing it. Use the `/followup` skill for follow-up work surfaced during a PR or review.
- Orphan beads (no `ROO-xxxx`) are not allowed. If you find one, either link it to an existing Linear issue, create a Linear issue for it, or close it.
