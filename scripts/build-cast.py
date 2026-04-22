#!/usr/bin/env python3
"""
Synthesize an asciinema .cast v2 file from a Claude Code session JSONL.

Real asciinema captures of Claude Code sessions are often lossy (TUI
redraw) and always too long for a 90-second cold open. This script
instead produces a cinematic compressed replay: real artifacts
(ticket, commit subjects, PR number, files touched) from the session,
timed on a storyboard designed for stage playback.

Usage:
  python3 scripts/build-cast.py \\
    --session /path/to/session.jsonl \\
    --out recordings/01-gwg-feature.cast
"""

from __future__ import annotations
import argparse
import json
import re
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

# ───────────────────────── ANSI helpers ─────────────────────────

R = "\x1b[0m"
BOLD = "\x1b[1m"
DIM = "\x1b[2m"
CYAN = "\x1b[36m"
GREEN = "\x1b[32m"
YELLOW = "\x1b[33m"
RED = "\x1b[31m"
MAGENTA = "\x1b[35m"
GRAY = "\x1b[90m"
TEAL = "\x1b[38;5;79m"   # close to vibecto teal #5DCAA5

PROMPT = f"{GRAY}~/src/rootnote{R} {TEAL}❯{R} "


# ───────────────────────── Session extraction ─────────────────────────

@dataclass
class SessionData:
    ticket: str = "ROO-???"
    branch_hint: str = "feat/ROO-???-desc"
    pr_number: str = "????"
    first_commit: str = "feat: initial implementation"
    files_touched: list = field(default_factory=list)
    review_rounds: int = 0
    # time breakdown in seconds
    elapsed_sec: int = 0       # total wall clock
    attended_sec: int = 0      # continuous-attention (≤90s gaps)
    active_sec: int = 0        # session-active (≤5min gaps)
    idle_sec: int = 0          # elapsed - active
    walkaway_count: int = 0    # number of >5-min gaps


def _fmt(sec: int) -> str:
    """Render seconds as '7h 12m' / '1h 50m' / '44m' / '28s'."""
    td = timedelta(seconds=int(sec))
    h, rem = divmod(int(td.total_seconds()), 3600)
    m = rem // 60
    s = rem % 60
    if h: return f"{h}h {m:02d}m"
    if m: return f"{m}m {s:02d}s"
    return f"{s}s"


def _compute_time(events: list, short_gap: int = 90, long_gap: int = 300):
    """Return (elapsed, attended, active, idle, walkaway_count)."""
    if len(events) < 2:
        return 0, 0, 0, 0, 0
    elapsed = (events[-1] - events[0]).total_seconds()
    walkaways = 0
    short_idle = 0
    long_idle = 0
    for i in range(1, len(events)):
        dt = (events[i] - events[i-1]).total_seconds()
        if dt > short_gap:
            short_idle += dt
        if dt > long_gap:
            long_idle += dt
            walkaways += 1
    attended = elapsed - short_idle
    active = elapsed - long_idle
    return int(elapsed), int(attended), int(active), int(long_idle), walkaways


def extract(session_path: Path) -> SessionData:
    d = SessionData()
    files = set()
    commit_subjects = []
    timestamps = []
    for line in session_path.read_text().splitlines():
        try:
            e = json.loads(line)
        except Exception:
            continue
        t = e.get("type")
        msg = e.get("message") or {}

        # collect timestamps for time-breakdown analysis
        ts = e.get("timestamp") or msg.get("timestamp")
        if ts:
            try:
                timestamps.append(datetime.fromisoformat(ts.replace("Z", "+00:00")))
            except ValueError:
                pass

        # first user slash invocation → ticket + branch hint
        if t == "user" and d.ticket == "ROO-???":
            content = msg.get("content")
            text = content if isinstance(content, str) else ""
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") == "text":
                        text = c.get("text", "")
                        break
            m = re.search(r"<command-args>(ROO-\d+)", text)
            if m:
                d.ticket = m.group(1)

        # tool calls
        if t == "assistant":
            for c in msg.get("content", []) or []:
                if not isinstance(c, dict):
                    continue
                if c.get("type") != "tool_use":
                    continue
                name = c.get("name")
                inp = c.get("input") or {}

                if name == "Bash":
                    cmd = inp.get("command", "")
                    # commit subjects
                    m = re.search(r"git\s+commit[^\n]*-m\s*\"[^\n]*?\$\(cat\s+<<'EOF'\s*\n([^\n]+)", cmd)
                    if m:
                        commit_subjects.append(m.group(1).strip())
                    else:
                        m2 = re.search(r"git\s+commit[^\n]*-m\s*[\"']([^\"']+)", cmd)
                        if m2:
                            commit_subjects.append(m2.group(1).strip())
                    # PR number
                    m = re.search(r"gh pr (create|view|checks)\s+(?:[^0-9]*?)(\d{3,5})", cmd)
                    if m:
                        d.pr_number = m.group(2)
                    m = re.search(r"PR_NUMBER=(\d+)", cmd)
                    if m:
                        d.pr_number = m.group(1)
                    # review round count
                    if re.search(r"round-(\d)", cmd):
                        rn = int(re.search(r"round-(\d)", cmd).group(1))
                        d.review_rounds = max(d.review_rounds, rn)

                if name in ("Edit", "Write"):
                    fp = inp.get("file_path", "")
                    if fp:
                        files.add(fp.split("/rootnote-worktrees/")[-1])

    d.files_touched = sorted(files)
    if commit_subjects:
        d.first_commit = commit_subjects[0]
    if d.ticket != "ROO-???":
        d.branch_hint = f"feat/{d.ticket.lower()}-onboarding-questions"

    timestamps.sort()
    d.elapsed_sec, d.attended_sec, d.active_sec, d.idle_sec, d.walkaway_count = \
        _compute_time(timestamps)
    return d


# ───────────────────────── Cast writer ─────────────────────────

class CastWriter:
    """Incrementally build an asciinema .cast v2 file."""
    def __init__(self, width=120, height=30, title="gwg → merged PR"):
        self.events = []
        self.t = 0.0
        self.header = {
            "version": 2,
            "width": width,
            "height": height,
            "timestamp": int(time.time()),
            "env": {"SHELL": "/bin/zsh", "TERM": "xterm-256color"},
            "title": title,
        }

    def wait(self, seconds: float):
        self.t += max(seconds, 0.0)

    def out(self, text: str):
        """Emit text instantly."""
        self.events.append([round(self.t, 3), "o", text])

    def type(self, text: str, cps: float = 28):
        """Type text one char at a time for realism."""
        delay = 1.0 / cps
        for ch in text:
            self.events.append([round(self.t, 3), "o", ch])
            self.t += delay

    def line(self, text: str = ""):
        self.out(text + "\r\n")

    def prompt(self):
        self.out(PROMPT)

    def write(self, path: Path):
        with path.open("w") as f:
            f.write(json.dumps(self.header) + "\n")
            for ev in self.events:
                f.write(json.dumps(ev, ensure_ascii=False) + "\n")


# ───────────────────────── Storyboard ─────────────────────────

def storyboard(cast: CastWriter, d: SessionData):
    # Opening prompt
    cast.prompt()
    cast.wait(0.6)
    cast.type(f"gwg {d.branch_hint}")
    cast.wait(0.8)
    cast.line()

    # Worktree bootstrap
    cast.line(f"{GRAY}[gwg]{R} branch prefix → skill '/feature'")
    cast.wait(0.3)
    cast.line(f"{GRAY}[gwg]{R} creating worktree …/rootnote-worktrees/{d.branch_hint}")
    cast.wait(0.5)
    cast.line(f"{GRAY}[.worktree-setup]{R} {GREEN}✓{R} env copied  {GREEN}✓{R} port 3042  {GREEN}✓{R} pnpm install (2.1s)")
    cast.wait(0.4)
    cast.line(f"{GRAY}[gwg]{R} launching claude with {CYAN}/feature {d.ticket}{R}")
    cast.wait(0.8)
    cast.line()

    # Claude session — header
    cast.line(f"{TEAL}─── Claude Code ───{R}")
    cast.wait(0.4)
    cast.line(f"{BOLD}/feature {d.ticket}{R}")
    cast.wait(0.6)

    # Phase: Linear
    cast.line(f"{DIM}▸ reading Linear ticket {d.ticket} …{R}")
    cast.wait(0.8)
    cast.line(f"  {GREEN}✓{R} ticket: \"Onboarding goal-selection step between plan and create-creator\"")
    cast.wait(0.7)

    # Phase: Explore
    cast.line(f"{DIM}▸ exploring codebase (subagent: Explore) …{R}")
    cast.wait(1.4)
    cast.line(f"  {GREEN}✓{R} mapped onboarding flow, schema patterns, auth helpers")
    cast.wait(0.5)

    # Phase: Clarify
    cast.line(f"{YELLOW}▸ 2 ambiguities before planning{R}")
    cast.wait(0.5)
    cast.line(f"  {GRAY}?{R} preserve answers on skip? {GRAY}→{R} {GREEN}yes{R}")
    cast.wait(0.5)
    cast.line(f"  {GRAY}?{R} analytics events? {GRAY}→{R} {GREEN}mixpanel, existing schema{R}")
    cast.wait(0.4)
    cast.line(f"{DIM}▸ proposing acceptance criteria …{R}")
    cast.wait(0.8)
    cast.line(f"  {GREEN}✓{R} plan approved")
    cast.wait(0.5)

    # Phase: TDD
    cast.line(f"{DIM}▸ TDD — writing failing tests first …{R}")
    cast.wait(1.0)
    cast.line(f"  {GREEN}✓{R} 7 tests red")
    cast.wait(0.4)
    cast.line(f"{DIM}▸ implementing …{R}")
    # show a few real files being touched
    picks = [p for p in d.files_touched if any(
        k in p for k in ["schema.ts", "questions.ts", "onboard", "services", "api/"]
    )][:4]
    for p in picks:
        cast.line(f"  {CYAN}✎{R} {GRAY}{p}{R}")
        cast.wait(0.35)
    cast.wait(0.4)
    cast.line(f"  {GREEN}✓{R} all 7 tests green  {GREEN}✓{R} lint clean  {GREEN}✓{R} typecheck clean")
    cast.wait(0.6)

    # Phase: iterative-review
    cast.line(f"{DIM}▸ {CYAN}/iterative-review{R}{DIM} — 4 parallel specialists ×{R} {BOLD}iter 1/4{R}")
    cast.wait(1.0)
    cast.line(f"  {YELLOW}→{R} 5 findings  {GRAY}(scale/N+1 · silent-failure · security · generalist){R}")
    cast.wait(0.5)
    cast.line(f"  {GREEN}✓{R} fixes applied  {DIM}→ re-review{R}")
    cast.wait(0.5)
    cast.line(f"{DIM}▸ iter 2/4  →  iter 3/4  →  iter 4/4 — converged, no findings{R}")
    cast.wait(0.7)

    # Phase: simplify + PR
    cast.line(f"{DIM}▸ {CYAN}/simplify{R}{DIM} (code-simplifier plugin) …{R}")
    cast.wait(0.7)
    cast.line(f"  {GREEN}✓{R} simplified 3 files")
    cast.wait(0.4)
    # commit
    cast.line()
    cast.line(f"{PROMPT}{DIM}git commit …{R}")
    cast.wait(0.5)
    commit_line = d.first_commit
    if len(commit_line) > 96:
        commit_line = commit_line[:93] + "…"
    cast.line(f"  {GREEN}[{d.branch_hint} a8ae373]{R} {commit_line}")
    cast.wait(0.5)
    cast.line(f"{PROMPT}{DIM}git push -u origin HEAD{R}")
    cast.wait(0.5)
    cast.line(f"  {GREEN}✓{R} pushed")
    cast.wait(0.3)
    cast.line(f"{PROMPT}{DIM}gh pr create --base dev{R}")
    cast.wait(0.7)
    cast.line(f"  {GREEN}✓{R} PR {BOLD}#{d.pr_number}{R} opened")
    cast.wait(0.7)
    cast.line()

    # Phase: outer loop — CI + Claude review
    cast.line(f"{DIM}▸ monitoring CI + claude-code-review.yml …{R}")
    cast.wait(0.7)
    rounds = max(d.review_rounds, 3)
    for i in range(1, rounds + 1):
        cast.line(f"  {YELLOW}round {i}:{R} review feedback → fixes → push")
        cast.wait(0.45)
    cast.line(f"  {GREEN}✓ all checks passing   ✓ review approves{R}")
    cast.wait(0.7)

    # Payoff
    cast.line()
    cast.line(f"{BOLD}{TEAL}🚀 merged to dev.{R}")
    cast.wait(0.5)
    elapsed = _fmt(d.elapsed_sec)
    attended = _fmt(d.attended_sec)
    walked = _fmt(d.idle_sec)
    cast.line(f"{DIM}   elapsed: {elapsed}  ·  attended: ~{attended}  ·  "
              f"walked away / stuck: {walked}{R}")
    cast.wait(2.0)


# ───────────────────────── CLI ─────────────────────────

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--session", type=Path, required=True,
                    help="path to Claude Code session JSONL")
    ap.add_argument("--out", type=Path,
                    default=Path("recordings/01-gwg-feature.cast"),
                    help="output .cast file")
    ap.add_argument("--width", type=int, default=120)
    ap.add_argument("--height", type=int, default=30)
    args = ap.parse_args(argv)

    if not args.session.exists():
        print(f"session not found: {args.session}", file=sys.stderr)
        return 1

    data = extract(args.session)
    print(f"extracted: ticket={data.ticket} pr=#{data.pr_number} "
          f"rounds={data.review_rounds} files={len(data.files_touched)}")
    print(f"first commit: {data.first_commit[:80]}")
    print(f"time:  elapsed {_fmt(data.elapsed_sec)}  · "
          f"attended {_fmt(data.attended_sec)}  · "
          f"walked away {_fmt(data.idle_sec)} ({data.walkaway_count} gaps)")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    cast = CastWriter(width=args.width, height=args.height,
                      title=f"gwg {data.branch_hint} → PR #{data.pr_number} merged")
    storyboard(cast, data)
    cast.write(args.out)

    duration = cast.t
    print(f"wrote {args.out} · {duration:.1f}s runtime · {len(cast.events)} events")
    return 0


if __name__ == "__main__":
    sys.exit(main())
