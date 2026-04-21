# Asciinema recordings — shot list

Two recordings are referenced by the deck. Both should be brief, silent, and sped up
for stage playback. Asciinema's web player supports `speed` and `autoplay` params.

## Setup

```bash
brew install asciinema
# optional — for converting to GIF if you prefer
brew install agg
```

Record with a clean, wide prompt and a readable font (≥16pt). Keep the terminal at
about 120×30 so it fills the slide without wrapping.

```bash
PS1='$ '        # minimal prompt
export CLICOLOR=1
stty cols 120 rows 30
```

## 01 — `gwg feat/...` → merged PR (cold open, ~90 sec)

Purpose: the Act 1 receipt. Audience sees the whole end-to-end with no narration.

**Script:**

1. `gwg feat/ROO-42-demo` — shows worktree creation + Claude boot
2. Cut. Speed up 6× through the planning + TDD phase.
3. Cut to the PR-open moment — show the `gh pr view` output.
4. Cut to the merged state.

**Record:**

```bash
asciinema rec recordings/01-gwg-feature.cast \
  --title "gwg feat/ROO-42 → merged PR" \
  --idle-time-limit 2
```

Trim with any editor — asciinema cast files are JSON, and `asciinema-edit` can cut
chunks without re-recording.

## 02 — `dcg` blocks a destructive command (~20 sec) — OPTIONAL

The dcg slide now ships a static ASCII rendering of the warning, so
this clip is a bonus. Record it if you want a live-feel moment during
the hooks section; otherwise the slide stands on its own.

Purpose: "watch a hook fire" moment on slide 9.

**Script:**

1. `cd ~/src/rootnote-worktrees/stale-branch`
2. Show `git log --oneline -5` (with unpushed commits visible)
3. Ask Claude to clean up the worktree — or just type `git worktree remove --force ..`
4. `dcg` intercepts. Show the warning. Type `n`.

**Record:**

```bash
asciinema rec recordings/02-dcg-blocks.cast \
  --title "dcg blocks destructive git command" \
  --idle-time-limit 1
```

## Embedding in Slidev

Two options:

**Option A — native asciinema-player (recommended).** Drop a Vue component that
loads the player for a given cast file. See `components/AsciinemaPlayer.vue`
(stub included). Then in the slide:

```md
<AsciinemaPlayer src="/recordings/01-gwg-feature.cast" :speed="3" autoplay />
```

**Option B — pre-rendered GIF.** Convert the cast to a GIF with `agg` and drop the
GIF in `public/`. Simpler, no player deps, but larger files and no pause/play.

```bash
agg recordings/01-gwg-feature.cast public/01-gwg-feature.gif --speed 3
```

Then embed in the slide:

```md
<img src="/01-gwg-feature.gif" />
```

## Stage notes

- **Test on the projector.** Terminal recordings that look crisp on a retina laptop
  often turn to mush on a beamer. Bump the font and re-record if needed.
- **Keep them silent.** No captions in the cast — the slide around it explains what's
  happening. Noise-to-signal ratio matters on stage.
- **Leave a 1-sec still at the end.** So the audience has time to register before the
  next slide advances.
