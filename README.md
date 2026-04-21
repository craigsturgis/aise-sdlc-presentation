# Composable SDLC Automation with Claude Code

A 25-minute meetup talk (Slidev). Case study: the `~/src/rootnote` Claude Code setup —
skills, hooks, CLAUDE.md, GitHub Actions — composed to automate the SDLC end-to-end.

**Thesis:** you can automate lots more of your SDLC than you think, in composable ways,
and AI agents can help you.

## Run the deck

```bash
pnpm install
pnpm dev         # opens http://localhost:3030
```

Presenter mode: press `o` to open the overview; `d` for dark mode toggle; arrow keys / `space` to advance.

Export:

```bash
pnpm build       # static site in dist/
pnpm export:pdf  # slides.pdf
```

## Structure

- `slides.md` — the deck (Slidev markdown)
- `style.css` — Vibecto brand palette overrides
- `public/` — images, screenshots, QR codes
- `recordings/` — asciinema `.cast` files for embedded demos
- `components/` — Vue components for custom slide widgets

## Asciinema recordings

The deck embeds pre-recorded terminal clips instead of doing anything live.
See `recordings/README.md` for the shot list and how to record them.
