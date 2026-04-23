# Amplify Backend

## Environment Variables -- CRITICAL

**`aws amplify update-branch --environment-variables` REPLACES all env vars, it does not merge.**

When adding or updating an Amplify branch env var, you MUST:
1. **Fetch all existing vars first**: `aws amplify get-branch --app-id <AMPLIFY_APP_ID> --branch-name <branch> --query 'branch.environmentVariables'`
2. **Merge the new var into the full set** (e.g. with `jq '. + {"NEW_VAR": "value"}'`)
3. **Pass the complete merged set** to `update-branch --environment-variables`

Failing to do this will **delete all other env vars on the branch**, breaking the deployment. This has happened before -- never skip the fetch-and-merge step.

The Amplify app ID is `<AMPLIFY_APP_ID>`. Env vars can be set at app level (inherited by all branches) or at branch level (overrides app level). Use branch-level overrides when dev and prod need different values (e.g. `NEXT_PUBLIC_POSTHOG_KEY`).

### Server-only env vars at SSR runtime (non-`NEXT_PUBLIC_*`)

Amplify Hosted Next.js SSR Lambdas **do not** inherit Amplify Console branch env vars for non-public variables at runtime, and the `.env` / `web/.env.production` files written in `amplify.yml` are not loaded at runtime either. Echoing a value into `.env` is necessary but not sufficient.

For a server-only secret to reach `process.env` inside an SSR route or `getServerSideProps`, it MUST be listed in the `env` block of `web/next.config.js`:

```js
env: {
  POSTHOG_PERSONAL_API_KEY: process.env.POSTHOG_PERSONAL_API_KEY,
  // ...
}
```

Next.js inlines those entries into the compiled server bundle at build time using the value present in the build shell (which `amplify.yml` populates by sourcing `web/.env.production`). Without the `env` block entry, `process.env.X` resolves to `undefined` at SSR runtime even though the value was present during the build. `next.config.spec.ts` guards `POSTHOG_PERSONAL_API_KEY` specifically; add a similar assertion when introducing new server-only vars (ROO-1621).

## team-provider-info.json

The file contains parallel deployment blocks for `dev`, `prod`, and each developer's personal environment (typically 6+ entries keyed by name). When adding, removing, or renaming a Lambda, you MUST update all blocks -- missing any one leaves stale deployment references that can fail Amplify deploys. Grep the file for the Lambda name before and after the edit to confirm every block is touched.

## PG Flag Env Vars vs PostHog

`NEXT_PUBLIC_USE_PG_*` env vars in Amplify are defaults only. PostHog evaluates per-user flags that may override them. Server-side code uses `evaluatePostgresFlagsForRequest()` (always correct); client-side code uses the Redux `pgFlags` slice (eventually correct after `pgFlagsLoaded` becomes true). Never assume the env var value matches what a specific user sees.

## GraphQL Schema

The GraphQL schema is at `backend/api/rootnote/schema.graphql`.

## Package Manager

**`yarn`** is used for Lambda functions under `amplify/` and other Amplify backend resources. This is the one exception to the monorepo's `pnpm` default.
