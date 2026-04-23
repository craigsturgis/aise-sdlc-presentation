---
paths:
  - "web/pages/api/**"
  - "web/src/lib/db/**"
  - "web/src/utils/**"
  - "services/**"
---

# Pre-Implementation Review

When adding new write paths, upserts, or API integrations, complete these checks BEFORE writing code:

1. **Read called functions' contracts**: Before writing conditional branches on a function's return value, read that function's implementation. Confirm each branch is reachable. Don't assume a function can return `{ success: false }` if it actually throws -- read the source.

2. **Trace FK relationships**: For every value written to a FK column, trace where the value originates and confirm it's a valid reference. Pay special attention to values crossing system boundaries (DDB UUIDs used in PG columns).

3. **Scope normalization/transformation**: When adding data normalization (date coercion, ID remapping), list every caller of the endpoint. If any caller is a legacy or dual-write path, scope the normalization to only the new path -- otherwise the legacy path silently changes behavior.

4. **Upsert conflict completeness**: Every `onConflictDoUpdate` set must explicitly handle `_deleted`, status fields, and all fields the caller intends to update. Omitting `_deleted: false` means soft-deleted records stay invisible after upsert.

5. **Test mock fidelity**: Test mocks must use values that actually occur in production. Check enum definitions in the schema before using mock values -- using an enum value from the wrong type silently passes tests but masks real behavior.

6. **Typed Drizzle update patches**: Conditional update objects passed to `.set()` must be typed as `Partial<typeof <table>.$inferInsert>`, never `Record<string, unknown>`. The bare record type bypasses Drizzle's column-name checking — a typo like `apikey` instead of `apiKey` compiles clean, produces no DB error, and silently leaves the old value in place.

7. **Stream / timer interaction**: Idle timers attached to stream `data` events do not reset while the stream is paused for an awaited operation (DB write, HTTP call). If the awaited op can exceed the timeout, pause the timer around the `await` and resume after, or use a keep-alive heartbeat. Without this, slow-DB batches silently kill imports. Reference: ROO-1534 CSV import processor.

8. **Graceful-shutdown cleanup in catch blocks**: `catch` blocks that write to the DB/cache/queue can themselves throw during SIGTERM if the pool closed first, swallowing the original error. Wrap the cleanup in its own `try/catch`, log-and-swallow any cleanup failure, and re-throw the original error unconditionally.

9. **Widen the search before fixing**: Any bug-class finding during review or self-review must trigger a repo-wide grep for the same pattern (same helper call, same anti-pattern shape, same cross-system field assignment). Fix every instance in the same commit. This is the #1 source of "review round 5 catches the same bug as round 3, just in a sibling file."

10. **Drizzle error wrapping for PG codes**: postgres-js errors propagated through Drizzle (especially from within `db.transaction()`) may arrive wrapped — the SQLSTATE code lives on `error.cause?.code`, not on the top-level `error.code`. Every PG-code-based error translation (`23505 → 409`, `23503 → 404`, etc.) must probe both paths: `const pgCode = (error as { code?: string } | null)?.code ?? (error as { cause?: { code?: string } } | null)?.cause?.code;`. A single-path check misses wrapped errors and falls through to a generic 500.
