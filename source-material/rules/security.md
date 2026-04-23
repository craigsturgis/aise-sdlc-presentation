---
paths:
  - "web/pages/api/**"
  - "services/**"
  - "amplify/**"
  - "packages/sync-core/**"
  - "scripts/**"
  - "util-scripts/**"
---

# Security Rules

## Credentials and Secrets

**NEVER commit any credentials or secrets to source control, including:**
- API keys (production OR test/sandbox)
- API secrets, database passwords, JWT secrets
- OAuth client secrets, webhook signing secrets
- Any tokens or credentials, even "test" or "development" ones

**Instead, use:**
- Environment variables (from `.env.local` or CI/CD)
- AWS Secrets Manager or Parameter Store
- Command-line arguments for scripts (with env var fallbacks)

**If you accidentally commit credentials:**
1. Immediately rotate/regenerate the compromised credentials
2. Remove from git history using `git filter-branch` or BFG Repo-Cleaner
3. Force push the cleaned history

## Logging and PII

- **Never log PII** (emails, authUserId, user names) at `info` level or above. Use `debug` level if needed for development.
- **Tokens and API keys must never appear in URL query parameters** -- always use POST body or request headers. Query params leak into access logs, browser history, and error monitoring.
- **Validate user-supplied IDs** (UUID format) at API route boundaries. Return 400 early rather than letting invalid IDs reach downstream services.

## Credential Table Types

When a Drizzle table stores hashed secrets (e.g., `apiSecretHash`), always export a `Safe*` type that omits the hash field: `export type SafeUserApiKey = Omit<UserApiKey, 'apiSecretHash'>`. Route handlers must use the safe type, never the full table type, to prevent accidental hash exposure.

**Important:** `Safe*` types only omit the hash — fields like `apiKey` (the raw key string) are still present. API responses must mask these at the route layer (e.g., `uk_***...a1b2`) before serializing. The type alone is not sufficient for response safety. Add a JSDoc invariant on the `Safe*` type stating which field is elided and why.

## Log Severity for Data Integrity

- `logger.warn` for recoverable/retryable conditions (transient 5xx, optional-enrichment miss).
- `logger.error` for conditions indicating data corruption, lost signal, or security-relevant failures (BP duplication, cross-system ID leakage, failed uniqueness checks, expired tokens on write paths). Reviewers repeatedly escalate `warn→error` on these — start at `error`.

## Spread-Operator Safety Invariants

When a component exposes a caller-controlled prop like `componentOptions`/`linkProps`/`buttonProps`, **never** allow the spread to override a safety default. Same rule applies to `target`, CSP attrs, and any defensive default.

- Wrong: `<a rel="noopener noreferrer" {...componentOptions}>` — spread can contain `rel=""`.
- Right: `<a {...componentOptions} rel="noopener noreferrer">`, or explicit merge: `rel={['noopener', 'noreferrer', componentOptions?.rel].filter(Boolean).join(' ')}`.

## Concurrency on Auth / Billing / Uniqueness Endpoints

Endpoints enforcing a cap ("max N active keys", "one active BP per org") or replace-in-place ("regenerate", "rotate") must assume concurrent requests. Never rely on `check succeeded → insert succeeded` as a sequence. Options:

- Wrap check+insert in a transaction with `SELECT ... FOR UPDATE`, or rely on a unique constraint.
- Catch the constraint violation on insert and translate to HTTP 409.

For replace-in-place operations (regenerate, rotate), document the non-idempotency — network timeout after commit locks the caller out — in API response docs.

## API-Route Security Checklist (apply to every new or modified route)

Run this before marking a route change complete. These items have appeared in review rounds 8+ on recent PRs (ROO-1372, ROO-1557, ROO-1534) — catching them at author time is cheaper than review round-trips.

1. **Auth hook / session check present.** No route should rely on "the frontend doesn't call it without a session."
2. **Input validation on every path param and body field.** UUID params: validate shape before using. Enum fields: check membership. Return 400 early.
3. **Authorization runs BEFORE business-state checks.** Check "can this user act on this resource?" before "is the resource already in the requested state?" Otherwise differential error responses leak state information.
4. **Cross-creator / cross-tenant resource ownership.** When a request references a `creatorId`, `channelId`, `workspaceId`, confirm the authenticated actor owns or is a member of that resource. Missing this is BOLA/IDOR.
5. **Fail closed on auth/ownership errors.** If the check throws or returns an unexpected shape, reject. Don't let an error path continue to the business logic.
6. **HTTP code mapping.** Uniqueness/constraint violations → 409, not 500. Soft-deleted resource → 404 or 410, not 500. Already-in-requested-state → 409. Unauthenticated → 401, unauthorized → 403.
7. **Scrub responses and errors.** Never surface raw PG errors, S3 keys/paths, papaparse error text, or `authUserId` values to clients. Map known cases to user-friendly messages; log the raw details server-side only.
8. **Strip server-authoritative fields from client payloads.** `createdBy`, `ownerId`, `workspaceId` in a POST body must come from the session, not the request. Ignore or reject if present.
9. **No PII in response payloads unless explicitly required.** Emails, names, `authUserId` should be elided from list responses by default.
10. **Response type must not leak secrets.** Never return a DB row containing password hashes (`*Hash`), API/OAuth/session secrets (`*Secret`), or authentication tokens (`accessToken`, `refreshToken`, `sessionToken`, `apiKeyToken`, raw key strings). Pagination cursors, CSRF tokens, Stripe `idempotencyToken`, and similar non-secret tokens are fine — name the field precisely so review agents don't flag legitimate tokens. Use a `Safe*` wrapper type that Omits the sensitive fields (see "Credential Table Types" above) and mask any remaining semi-sensitive values at the route layer.
