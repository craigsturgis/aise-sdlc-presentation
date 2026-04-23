---
paths:
  - "web/pages/api/**"
  - "web/src/lib/db/**"
  - "web/src/store/**"
  - "web/src/utils/**"
  - "web/components/**"
  - "web/src/hooks/**"
  - "services/**"
---

# PostgreSQL Migration Patterns

These rules apply when working with the ongoing DynamoDB-to-PostgreSQL migration, PG feature flags, and API routes that have dual data paths.

## API Pagination

The rootnote-api `by-creator` and `by-connection` endpoints default to `limit=100` ordered by `desc(created_at)`. Callers that need ALL results must either paginate through all pages or add query params (e.g., `defaultOnly=true`) to narrow results at the DB level -- a single call does NOT return everything.

## Filter Parity

When migrating API routes from GraphQL/DynamoDB to PostgreSQL, ensure all query-time filters (e.g., `defaultChannelId: { ne: null }`) are replicated as DB-level WHERE clauses. Post-fetch filtering behind a paginated API silently drops results when the dataset grows beyond one page.

## PG Flag Race Condition

When writing client-side code that uses `pgCoreEntities` (or other PG flags from Redux), always gate on `pgFlagsLoaded` before making data fetches. The env var default may differ from the PostHog-evaluated value. Follow the pattern in `InitialDataLoader.tsx:94`. Without this guard, fetches may use the wrong data source (GraphQL vs API routes) before PostHog flags load.

## Type Import Aliasing

In API routes with both GraphQL and PG code paths, use aliased imports (e.g., `import type { DataChannel as PgDataChannel }`) when the PG service type shares a name with a GraphQL type. Without the alias, it's easy to annotate PG-path variables with the GraphQL type, causing TS errors that only surface at build time.

## Write-Through Legacy ID Mismatch

When a write-through entity is found via `getByLegacyId`, `entity.id` is the PG primary key -- use `entity.legacyId` (or the original request ID) for write-through updates so the DDB primary store can find the record. All billing API routes that read then write must include the `getByLegacyId` fallback consistently (see ROO-1261 pattern in `cancel-subscription.ts`).

## Redux Enrichment Parity

When writing PG connections to Redux (via `setCreatorConnections`), every code path must enrich them with `creatorBlock` data -- PG API responses lack nested relational objects that GraphQL responses include. Follow the enrichment pattern in `InitialDataLoader.tsx:335-341`. Missing enrichment causes downstream hooks (e.g., `useActiveConnectionPlatforms`) to fail silently.

## Create-Response Shape Parity

When a client dispatches the raw response from a create endpoint directly into Redux (or other shared state), the created entity's shape MUST match the shape returned by the corresponding list/read endpoint. Any nested connection field the list endpoint enriches (`creator.Members.items`, `creator.Connections.items`, etc.) must also be populated on the create response — at minimum with the just-created record. Otherwise components reading `entity?.nested?.items?.filter(...) ?? []` render a count/list of 0 for the fresh entity until the next full refetch runs (e.g., `InitialDataLoader`). Example: ROO-1622 — `/api/creator/create` omitted `Members` while `byUserId` enriched it, so new creator cards showed "0 members" until reload.

## Date-Only Strings as API Parameters

When sending `startDate`/`endDate` to rootnote-api, date-only strings like `"2026-04-08"` are parsed as midnight UTC (start of day). Using one as `endDate` effectively excludes the entire day. Always send full ISO timestamps with explicit time boundaries (e.g., `T00:00:00.000Z` for start, `T23:59:59.999Z` for end). The API's `isValidIsoDate` accepts both formats without error, so the bug is silent.

## Server-Side PG Flag Evaluation

Utility modules that branch on PG flags must use `evaluatePostgresFlagsForRequest(context)` -- not the static `featureFlags` singleton -- when a server-side `context` (req/res) is available. When a function reads from a store then writes, evaluate the flag once and pass the result through to both operations to prevent store divergence on transient PostHog failures. Follow the `resolveUsePgCoreEntities` pattern in `userReportingMetadata.ts`.

## Postgres Numeric Over the Wire

PG `numeric`/`decimal` columns (prices, monetary amounts, high-precision metrics) serialize as strings from rootnote-api, not numbers (e.g., `plans.price` arrives as `"9.99"`). TypeScript types derived from GraphQL (`Plan.price: number`) are a silent lie against the raw API response. Coerce at the proxy boundary (`typeof value === 'string' ? parseFloat(value) : value`) so the wire shape matches the declared type — don't push coercion to each client consumer, or the next consumer to skip it gets `NaN` from arithmetic on a string.

## Timestamp Format Divergence

PG API responses (e.g., `useSyncEvents`) return timestamps as ISO 8601 strings (`"2026-03-26T04:02:47.008Z"`), while DynamoDB stores them as numeric epoch values (seconds or milliseconds). Functions consuming timestamps from both paths must handle both types with `typeof` guards -- numeric coercion on ISO strings produces `NaN`, not a parseable value. See `syncTimestampToDate` in `src/services/connections/types.ts`.

## Invalid Date Truthiness

`Invalid Date` is truthy in JS, so `if (value)` does not catch it. When formatting dates with `date-fns` (`formatDistanceToNow`, `formatDistanceToNowStrict`, etc.), always guard with `isNaN(date.getTime())` before calling the formatter -- otherwise an Invalid Date from timestamp conversion crashes the component with `RangeError: Invalid time value`.

## Client-Side GraphQL → API Route Migration

Client-side components using `generateClient().graphql()` to fetch entity data will return null for pgOnly users (who have no DynamoDB records). Replace with `fetch('/api/<entity>/[id]')` to delegate PG flag evaluation to the server-side API route. Check `web/components/` for remaining `generateClient` usages -- each is a potential blank-data bug for pgOnly users.

## pgOnly + Atomic PG Create + Write-Through

When an API route uses an atomic PG operation (e.g., `checkOrCreateInvitation`) that creates a record, pgOnly code paths must skip the subsequent write-through `create()` call. Write-through passes `legacyId: ''` which the PG upsert endpoint rejects as invalid. Non-pgOnly paths mask this because DDB generates the ID first and PG replication errors are swallowed. Guard with: `if (pgResult?.created && flagOptions?.pgOnly) { use pgResult.data; continue; }`.

## Soft-Delete Awareness in Resolve/Lookup Endpoints

When a data migration soft-deletes records (e.g., dedup), any endpoint that looks up records by ID without filtering `_deleted` will silently return deleted data to callers. After soft-delete migrations, audit all lookup endpoints (`resolve`, `getById`, `listByIds`) for the affected entity to ensure they either filter `_deleted=false` or redirect to the canonical replacement.

## Canonical Selection Consistency

When multiple code paths select a "canonical" record from duplicates (SQL migration, application endpoint, sync-core adapter), they must all use the same deterministic ordering (e.g., `ORDER BY created_at ASC, id ASC`). Divergent selection strategies cause the migration and runtime to disagree on which record is canonical, splitting data.

## SQS Attribute Types

SQS returns all message and queue attributes as strings (e.g., `ApproximateReceiveCount: '3'`, `ApproximateNumberOfMessages: '42'`). Always convert to `Number()` before returning in API responses or using in comparisons -- string coercion bugs are silent (`'3' > '10'` is `true`).

## Plain `text()` Columns vs TS Enum Sets

Several status/tier columns (`workspaces.billingTier`, `workspaces.billingStatus`, etc.) are declared as plain `text()` in the schema — not PG enums — so the DB enforces no case. Stripe webhooks, backfill scripts, and sync paths have been observed writing mixed case. When comparing a text column to a `Set<EnumType>` in code, normalize case on BOTH sides (e.g., `toUpperCase()` the DB value and use uppercase set members). Asymmetric normalization — lowercasing the tier but not the status — produces silent 403s/mismatches on otherwise-eligible rows.

## Cross-System ID Discipline (PG ↔ DDB)

Never write a PG UUID into a DDB field that expects a legacy ID, or vice versa. When resolving IDs at a system boundary, normalize to the target system's shape *before* the write, not after. When a lookup returns a record from the "other" system (e.g., `getByLegacyId` returns a PG shape), treat the response type as nullable on the cross-system field and guard downstream uses — do not annotate cross-system fields as non-nullable just because TypeScript will accept it.

When review catches this kind of leak in one write path, grep the **repo** (not just the diff) for **every** sibling write site before claiming the fix is complete. The diff only shows paths touched in the current PR — the same leak may exist in older code that survived prior reviews. PR 2967 needed rounds 5 and 5b for the same bug class in two different paths.

## ON CONFLICT + Composite Unique Constraints

`INSERT ... ON CONFLICT (col) DO UPDATE` resolves only ONE conflict target. Tables with a second unique constraint (e.g., `unique_creator_membership_creator_user` alongside `legacy_id`) need a transaction-wrapped pre-check by the composite key before the INSERT — the `ON CONFLICT (legacy_id)` alone lets the INSERT pass its `legacy_id` check and then blow up on the composite constraint with a 500. Pattern: SELECT by composite key inside the tx → UPDATE-in-place if found → else INSERT ... ON CONFLICT (legacy_id) for retry idempotency → translate residual `23505` to 409. Applies to any write-through upsert on a table with multiple unique constraints (ROO-1640).

## Nullable legacyId in pgOnly Rows

pgOnly-created rows store `legacyId = null` by design. Any comparison like `if (existing.legacyId !== incoming.legacyId)` — typically used to detect DDB ID churn or log reassignments — must be guarded by `existing.legacyId !== null &&` first. Otherwise the first DDB re-sync of any pgOnly row triggers a false-positive reassignment log, polluting data-integrity alerting. Only both-sides-non-null-and-different indicates actual churn.

## Partial Index Pairing

When a table carries a partial index on `WHERE <cond> = true` and a query also filters on `WHERE <cond> = false ORDER BY ...` (e.g., active vs revoked keys, non-deleted vs deleted rows), add the complementary partial index. Without it, the opposite-side query full-scans the table while the true-side query looks fast locally — the divergence only surfaces at scale.
