# RootNote API Service

Fastify-based REST API for internal and partner endpoints.

## Development

```bash
# Start the API development server (port 4001)
pnpm dev

# Start local PostgreSQL for development
docker-compose up -d

# Run E2E tests (API-only, no web app)
API_URL=http://localhost:4001 pnpm test:e2e:internal
API_URL=http://localhost:4001 pnpm test:e2e:partner

# Run full-stack E2E tests (web app + API)
pnpm test:e2e:full-stack

# Build for production
pnpm build

# Type check
pnpm tsc -p tsconfig.fastify.json --noEmit
```

## Database Operations

```bash
pnpm db:generate    # Generate migrations after schema changes
pnpm db:migrate     # Run migrations
pnpm db:studio      # Open Drizzle Studio
```

## Key Configuration

- Local development: port 4001 (via `FASTIFY_PORT` env var)
- Production: port 3000 (via `PORT` env var, set by Docker/ECS)
- Health check: `/api/healthcheck`
- Internal API auth: `X-API-Key`/`X-API-Secret` headers
- Partner API auth: same headers with bcrypt-verified secrets from database

## Service-Local Gotchas

- **Vitest only picks up `*.test.ts`**, not `*.spec.ts` (see `vitest.config.ts` `include` glob). New integration tests in this service must use `.test.ts` / `.integration.test.ts` — a `.spec.ts` file runs zero tests and silently passes in CI unless you notice the "no test files found" exit code.
- **Run `pnpm lint` from this service directory** before pushing. It applies stricter rules (e.g., `curly`) than a root-level `pnpm eslint --quiet`, so lint issues here will pass locally at the monorepo root and then fail CI. The pre-commit hook runs `lint:web`, which does not cover these rules.

## File Organization

- `src/server.ts` - Server entry point with graceful shutdown
- `src/app.ts` - Fastify app configuration and plugin registration
- `src/routes/` - Route handlers organized by resource
- `src/plugins/` - Fastify plugins (auth, partner-auth, sentry)
- `src/lib/` - Shared utilities (db, validation, s3, image processing)
- `e2e/` - Playwright E2E tests (internal and partner projects)
