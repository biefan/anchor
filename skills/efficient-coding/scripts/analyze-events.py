#!/usr/bin/env python3
"""Analyze ~/.claude/anchor-events.jsonl and print a summary.

By default, summarize last 7 days. Override with --days N or --all.
Print as markdown table by default, or pass --json for machine-readable output.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import sys
from pathlib import Path

EVENTS_FILE = Path.home() / ".claude" / "anchor-events.jsonl"


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--days", type=int, default=7, help="Look back this many days (default 7)")
    p.add_argument("--all", action="store_true", help="Look at the whole log (overrides --days)")
    p.add_argument("--json", action="store_true", help="Output machine-readable JSON instead of markdown")
    p.add_argument("--file", default=str(EVENTS_FILE), help="Path to events.jsonl (default ~/.claude/anchor-events.jsonl)")
    return p.parse_args()


def load_events(path, since):
    if not os.path.exists(path):
        return []
    events = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            ts = d.get("ts", "")
            if since and ts and ts < since:
                continue
            events.append(d)
    return events


def summarize(events):
    out = {
        "total": len(events),
        "by_event": collections.Counter(e.get("event", "?") for e in events),
        "first_ts": min((e.get("ts", "") for e in events), default=""),
        "last_ts": max((e.get("ts", "") for e in events), default=""),
        "sessions": len({e.get("session_id") for e in events if e.get("session_id")}),
    }
    # Per-event detail
    out["details"] = {}
    for ev_name in out["by_event"]:
        sub = [e for e in events if e.get("event") == ev_name]
        sample = sub[-3:]  # last 3 of this kind
        # Build sample dicts. Use {**a, **b} instead of `a | b` so this stays
        # compatible with Python 3.8 (dict union operator is 3.9+).
        samples = []
        for s in sample:
            base = {k: v for k, v in s.items() if k not in ("event", "ts")}
            base["ts"] = s.get("ts", "")[:19]
            samples.append(base)
        out["details"][ev_name] = {"count": len(sub), "samples": samples}
    # PreToolUse pattern breakdown
    pt = [e for e in events if e.get("event") == "pretool_blocked"]
    if pt:
        out["pretool_blocked_by_pattern"] = collections.Counter(e.get("msg", "?")[:60] for e in pt).most_common()
    # PostToolUse linter breakdown
    pl = [e for e in events if e.get("event") == "posttool_lint_issue"]
    if pl:
        out["lint_by_linter"] = collections.Counter(e.get("linter", "?") for e in pl).most_common()
    return out


def render_markdown(summary, since_label):
    lines = []
    lines.append(f"# anchor events summary ({since_label})")
    lines.append("")
    if summary["total"] == 0:
        lines.append("_No events recorded yet._")
        lines.append("")
        lines.append("Hooks log to `~/.claude/anchor-events.jsonl`. Trigger something (start a session, hit a Stop in autonomous mode, run a blocked Bash) and re-run.")
        return "\n".join(lines)
    lines.append(f"**Total events**: {summary['total']} across {summary['sessions']} session(s)")
    lines.append(f"**First**: {summary['first_ts'][:19]}  **Last**: {summary['last_ts'][:19]}")
    lines.append("")
    lines.append("## By event type")
    lines.append("")
    lines.append("| Event | Count |")
    lines.append("|---|---|")
    for ev, n in summary["by_event"].most_common():
        lines.append(f"| `{ev}` | {n} |")
    lines.append("")
    if summary.get("pretool_blocked_by_pattern"):
        lines.append("## PreToolUse blocks — top reasons")
        lines.append("")
        lines.append("| Reason | Count |")
        lines.append("|---|---|")
        for msg, n in summary["pretool_blocked_by_pattern"][:10]:
            lines.append(f"| {msg} | {n} |")
        lines.append("")
    if summary.get("lint_by_linter"):
        lines.append("## PostToolUse lint hits — by linter")
        lines.append("")
        lines.append("| Linter | Count |")
        lines.append("|---|---|")
        for linter, n in summary["lint_by_linter"]:
            lines.append(f"| `{linter}` | {n} |")
        lines.append("")
    lines.append("## Recent samples (last 3 per event)")
    lines.append("")
    for ev_name, det in summary["details"].items():
        lines.append(f"### `{ev_name}` — total {det['count']}")
        for s in det["samples"]:
            ts = s.pop("ts", "")
            extras = " · ".join(f"{k}={v}" for k, v in s.items() if v)
            lines.append(f"- `{ts}` {extras}")
        lines.append("")
    return "\n".join(lines)


def main():
    args = parse_args()
    if args.all:
        since = ""
        since_label = "all time"
    else:
        cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=args.days)
        since = cutoff.strftime("%Y-%m-%dT%H:%M:%SZ")
        since_label = f"last {args.days} day(s)"

    events = load_events(args.file, since)
    summary = summarize(events)

    if args.json:
        # Compact-friendly JSON: drop sample bodies that contain newlines
        json.dump(summary, sys.stdout, indent=2, ensure_ascii=False, default=str)
        sys.stdout.write("\n")
    else:
        print(render_markdown(summary, since_label))


if __name__ == "__main__":
    main()
