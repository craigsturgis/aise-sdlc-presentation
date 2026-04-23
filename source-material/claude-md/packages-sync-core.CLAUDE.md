# Sync-Core Platform Adapters

`@rootnote/sync-core` handles data syncing from external platforms. Each platform is a self-contained adapter implementing the `PlatformAdapter` interface (`fetchMetrics`, `fetchContent?`, `refreshToken?`).

## Adapter Structure

Adapters live in `src/platforms/<name>/` with this structure:
- `api-client.ts` - fetch wrapper with error classification
- `auth.ts` - token refresh
- `metrics.ts` - profile/channel metrics
- `content.ts` - posts/videos
- `index.ts` - wiring

New adapters must be registered in `platforms/registry.ts` and exported from `src/index.ts`.

The sync-worker (`services/sync-worker/`) consumes SQS messages and calls `syncConnection()` which resolves the platform adapter and orchestrates the sync.

## API Client Pattern

In adapter `api-client.ts` fetch helpers, classify HTTP status codes (401/403) BEFORE attempting to parse the response body as JSON. A non-JSON response on an auth-failure status (e.g., HTML error page from a CDN or proxy) will fall through the JSON parse catch-block and silently retry instead of throwing `CredentialError`. Check status first, extract the error message best-effort, then classify.

## Credential Persistence Contract

The `syncConnection` orchestrator automatically persists refreshed credentials back to the database in two cases:
1. After `adapter.refreshToken()` returns new credentials
2. After `adapter.fetchMetrics()` returns `updatedCredentials` in its `FetchMetricsResult`

Adapters that refresh tokens internally during `fetchMetrics` (e.g., Twitch) must return the updated credentials via `{ dataPoints, updatedCredentials }`. All `fetchMetrics` implementations return `FetchMetricsResult` (not a bare `NewDataPoint[]` array).

**Important**: Adapters must choose ONE refresh strategy -- either implement `adapter.refreshToken` (orchestrator-managed) OR refresh internally in `fetchMetrics` and return `updatedCredentials`. Implementing both causes two token rotations per sync, which can trigger `invalid_grant` errors on providers that limit rotation frequency.

## Error Classification

When working in platform adapters:
- **5xx and network errors** -> transient, retryable (throw regular `Error`, not `CredentialError`)
- **4xx errors** -> non-retryable, throw immediately (except 429 rate limits)
- **401/403 auth errors** -> `CredentialError` with classification: `'invalid'` (needs re-auth) vs `'expired'` (needs token rotation)
- **429 rate limits** -> retryable short-window throttle. **Quota limits** (e.g., YouTube `quotaExceeded`) -> throw immediately (retrying wastes quota)
- **Non-JSON error responses** -> handle gracefully with try/catch around `response.json()`

## Testing

```bash
# Run adapter tests (unit tests, no DB required)
pnpm test:ci

# Typecheck (requires building @rootnote/db first)
pnpm --filter @rootnote/db build && pnpm --filter @rootnote/sync-core typecheck
```
