# Source material — the rootnote SDLC automation stack

Everything this talk references, pulled straight from the `~/src/rootnote`
repo and Craig's dotfiles. Organized by the six composable layers from the
deck:

1. **Shell** — `gwg` / `gww` / `.worktree-setup` and the util-scripts they wrap
2. **CLAUDE.md** — the shared brain, root + per-module
3. **Hooks** — invisible guardrails fired on Claude Code lifecycle events
4. **Project skills** — the orchestrators (`/feature`, `/bugfix`, `/chore`) and the leaves
5. **GitHub Actions** — the outer loop (`claude-code-review.yml`, `claude.yml`) + regression
6. **Scripts and docs** — helpers the skills call into, plus the full composability doc

Everything lives in the corresponding folder below. Filenames follow the
original repo paths (flattened with dots, e.g. `services-rootnote-api.CLAUDE.md`)
so you can map each file back to where it lives in the real repo.

## Layout

```
source-material/
├── shell/              # gwg/gww snippet + util-scripts + .worktree-setup
├── claude-md/          # root + per-module CLAUDE.md files
├── rules/              # .claude/rules/*.md scoped guidance
├── skills/             # .claude/skills/<name>/SKILL.md — one per project skill
├── hooks/              # .claude/hooks/* + settings.json (the wiring)
├── github-actions/     # .github/workflows/* — the outer loop + regression
├── scripts/            # scripts/ — db-connect.sh, run-regression.sh
└── docs/               # skill-composability.md — the deep-dive companion
```

## What maps to which slide

| Slide / layer            | Where to look                                                                                   |
| ------------------------ | ----------------------------------------------------------------------------------------------- |
| Layer 1 — Shell          | [shell/](shell/) — `gwg` function, `git-worktree-go`, `git-worktree-warp`, `.worktree-setup`    |
| Layer 2 — CLAUDE.md      | [claude-md/](claude-md/) — root + scoped modules; [rules/](rules/) for the path-gated rule sets |
| Layer 3 — Hooks          | [hooks/](hooks/) — individual hook scripts + `settings.json` that wires them                    |
| Layer 4 — Skills         | [skills/](skills/) — orchestrators (`feature`, `bugfix`, `chore`) + leaves                      |
| `/iterative-review` slide | [skills/iterative-review.SKILL.md](skills/iterative-review.SKILL.md)                             |
| `/prloop-enhanced`       | [skills/prloop-enhanced.SKILL.md](skills/prloop-enhanced.SKILL.md)                               |
| Self-closing loop        | [skills/review-learnings.SKILL.md](skills/review-learnings.SKILL.md)                             |
| GH Actions outer loop    | [github-actions/claude-code-review.yml](github-actions/claude-code-review.yml)                   |
| On-demand `@claude`      | [github-actions/claude.yml](github-actions/claude.yml)                                           |
| Regression workflow      | [github-actions/playwright-regression.yml](github-actions/playwright-regression.yml)             |
| Deep-dive companion      | [docs/skill-composability.md](docs/skill-composability.md)                                       |

## What's scrubbed

These files are the real thing, pulled verbatim, then run through a small
set of placeholder substitutions so production infra identifiers don't
ship with the deck. Everywhere you see one of these placeholders, the
original file had a live value:

| Placeholder                | Replaced                                                   |
| -------------------------- | ---------------------------------------------------------- |
| `<AMPLIFY_APP_ID>`         | The real Amplify app ID                                    |
| `<COGNITO_USER_POOL_ID>`   | The real Cognito user pool ID                              |
| `dev.example.app`          | The dev custom domain                                      |
| `app.example.app`          | The prod custom domain                                     |
| `test.example.app`         | The SES inbound test-email domain                          |
| `<org>.sentry.io`          | The Sentry organization slug                               |
| `<org>` (sentry-cli flag)  | The Sentry organization slug                               |
| `appAbc12345` (prefix)     | The Amplify-generated Lambda name prefix                   |
| `<app>-ses-incoming-dev`   | The real S3 bucket for SES inbound test email              |
| `linear.app/<workspace>`   | The Linear workspace slug                                  |

Nothing else has been edited — ticket prefixes (`ROO-XXX`), workspace names
(`@rootnote/web`, `rootnote-api`), the `rootnote` AWS CLI profile name,
and other references that already appear in the public talk and the
linked blog post are kept as-is. Secrets, tokens, and real credentials
were never checked into the source repo in the first place — you'll see
pattern-only references (`${SLACK_BOT_TOKEN}`, `TEST_USER_PASSWORD`, etc.).

## Notes on a few files

- **`shell/zshrc-snippet.sh`** — the `gwg` / `gww` / `gww-clean` functions
  as they live in Craig's `.zshrc`. Drop them into your own shell init and
  point them at wherever you cloned the util-scripts.
- **`shell/.worktree-setup` → `shell/worktree-setup.sh`** — renamed for
  obvious file extension; the real file lives dot-prefixed at the repo
  root of the project.
- **`hooks/settings.json`** — this is the `.claude/settings.json` wiring
  that tells Claude Code which hooks to fire on which events. Without it,
  the individual hook scripts just sit in the folder doing nothing.
- **`skills/` filenames** — the real repo has `.claude/skills/<name>/SKILL.md`.
  Flattened here to `<name>.SKILL.md` for ergonomics. The frontmatter
  inside each file (especially `allowed-tools:` and `model:`) is the
  important bit to keep if you're forking these.

## Attribution

Many of the hook patterns were lifted from or inspired by
[Anthony Panozzo's `claude-hooks` repo](https://github.com/panozzaj/claude-hooks)
and his [Agent Quality Gates talk](https://panozzaj.com/presentations/agent-quality-gates/1).
The destructive-command guard (`dcg`) referenced in the deck is
[Dicklesworthstone/destructive_command_guard](https://github.com/Dicklesworthstone/destructive_command_guard).
