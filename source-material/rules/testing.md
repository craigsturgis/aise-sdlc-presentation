---
paths:
  - "**/*.spec.*"
  - "**/*.test.*"
  - "**/e2e/**"
  - "web/src/__tests__/**"
---

# Testing Guidelines

## Test-Driven Development (TDD) - MANDATORY

**All new development MUST follow the TDD workflow: Red -> Green -> Refactor**

1. **Red**: Write a failing test FIRST that defines the expected behavior
2. **Green**: Write the minimum code necessary to make the test pass
3. **Refactor**: Clean up the code while keeping tests green

**NEVER write implementation code without a failing test first.** This applies to:
- New features
- Bug fixes (write a test that reproduces the bug first)
- Refactoring (ensure existing tests cover the behavior before changing code)

## The Testing Pyramid

```
        /\
       /  \     E2E Tests (Playwright)
      /----\    - Full user flows, critical paths only
     /      \   - Expensive to run and maintain
    /--------\  Integration Tests (Vitest + API/DB)
   /          \ - Component interactions, API routes
  /------------\- Database operations, service layers
 /              \ Unit Tests (Vitest)
/________________\- Pure functions, utilities, hooks
                   - Individual component rendering
                   - Redux reducers/selectors
```

## Test Type Selection Guide

| Change Type | Primary Test | Secondary Test | Ask User If... |
|-------------|--------------|----------------|----------------|
| Pure utility function | Unit test | - | Never |
| React component (presentational) | Unit test + Storybook | - | Complex interactions |
| React component (with state/effects) | Unit test | Integration if complex | Multiple external dependencies |
| Custom hook | Unit test | - | Depends on external services |
| API route | Integration test | E2E for critical paths | Involves auth or payments |
| Database service | Integration test | - | Schema changes involved |
| Redux slice | Unit test | - | Never |
| Full user workflow | E2E test | - | Which flows are critical |
| Bug fix | Test at appropriate level | - | Root cause unclear |

## When to Ask the User

**ALWAYS ask the user before proceeding if:**
- Uncertain which test type is most appropriate for the change
- The feature spans multiple layers (UI -> API -> Database)
- Existing test coverage is unclear or inconsistent
- The change involves critical paths (auth, payments, data integrity)
- Multiple valid testing approaches exist
- Test setup would require significant mocking of external services

## TDD Workflow for This Codebase

1. **Before writing any code**, create the test file:
   - Unit tests: `*.spec.ts` or `*.test.ts` alongside the source file
   - Integration tests: In appropriate `__tests__` directory
   - E2E tests: In `/web/e2e/` directory (Playwright)

2. **Write the failing test**:
   ```bash
   # Run the specific test to confirm it fails (use test:ci to avoid --watch hanging)
   pnpm --filter @rootnote/web test:ci -- path/to/new.spec.ts
   ```

3. **Implement the minimum code** to make the test pass

4. **Verify the test passes**:
   ```bash
   pnpm --filter @rootnote/web test:ci -- path/to/new.spec.ts
   ```

5. **Refactor** if needed, keeping tests green

6. **Run the full test suite** before committing:
   ```bash
   pnpm test:ci:web
   ```

## Test File Naming Conventions

- Unit tests: `ComponentName.spec.tsx` or `utilityName.test.ts`
- Integration tests: `feature.integration.spec.ts`
- E2E tests: `user-flow.spec.ts` (Playwright)

## Bug Fix TDD Pattern

When fixing bugs, ALWAYS:
1. Write a test that reproduces the bug (should fail)
2. Verify the test fails for the right reason
3. Fix the bug
4. Verify the test now passes
5. This prevents regression and documents the bug

## Test Coverage Expectations

- **Branch-level coverage**: For every new function with N branches or edge cases, write at least N tests. Enumerate the branches (happy path, error path, null input, boundary condition, etc.) before implementing.
- **Every new utility/module file must have a corresponding test file.** If you add `utils/foo.ts`, there must be `utils/foo.test.ts` or `utils/foo.spec.ts`.
- **Test error handling paths**: If you add a `catch` block or error branch, there must be a test that exercises it.
- **Meaningful assertions**: Use `expect(result).toEqual(expectedValue)` over `expect(result).toBeDefined()`. Verify actual values, structure, and side effects.

## Barrel Export Mocking

When mocking `src/utils` or other barrel exports, always use `importOriginal` to preserve re-exported constants (e.g., `COLOR_PRESETS`). A bare `vi.mock('src/utils', () => ({...}))` replaces the entire module and breaks Redux slices that import from the same barrel. Use: `vi.mock('src/utils', async (importOriginal) => { const actual = await importOriginal(); return { ...actual, myFn: vi.fn() }; })`.

## Server-only Imports on GSSP Pages with Unit Tests

Next.js pages that have a `getServerSideProps` export AND a vitest unit test of the default export must NOT import server-only modules at the top level. Next.js tree-shakes these out of the client bundle at build time, but vitest does not — under jsdom the page module eagerly loads every import, and `src/utils/amplify/serverUtils` runs `createServerRunner({ config })` at module-load, which hangs the test worker indefinitely. Applies to `getUserServerSide`, `runWithAmplifyServerContext`, `generateServerClientUsingReqRes`, and any helper whose import chain pulls those in.

Safe pattern: dynamic `import()` the server-only modules inside GSSP, keep pure utilities (routing helpers, sanitize helpers, `loadFlags()`-style env readers) at the top:
```ts
export const getServerSideProps = async (context) => {
  const [{ getUserServerSide }, { withTimeoutFallback }] = await Promise.all([
    import('src/utils/amplify/serverUtils'),
    import('src/utils/serverSideTimeout'),
  ]);
  // ...
};
```

Symptom when missed: `Run - pnpm test:ci:web` CI job CANCELLED at the 15-min timeout; local `pnpm exec vitest run src/__tests__/pages/<page>.spec.tsx` hangs with no output past `RUN` banner. Pattern landed in ROO-1671.

## Pre-Commit Checklist

Before committing and pushing code changes, ALWAYS verify:
1. **Tests written first**: Confirm you followed TDD (wrote failing tests before implementation)
2. **All tests pass**: `pnpm test:ci:web` (this is NOT optional - tests must exist and pass)
3. **Linting passes**: `pnpm lint:web --quiet`
4. **TypeScript compiles**: `pnpm --filter @rootnote/web typecheck`

**If no tests were written, STOP and write them before committing.**
