#!/usr/bin/env python3
"""Sync the most-recent pitfall entry from ./CLAUDE.md to ~/.anchor/pitfalls/.

Run after /pit appends a new entry. Extracts the top-most entry under the
踩坑记录 / Known Pitfalls / Lessons Learned section and writes it to
~/.anchor/pitfalls/<project-slug>/<YYYY-MM-DD>-<short-slug>.md for later
cross-project search via /recall.

Idempotent: if the same entry is already synced (matched by title), skip.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from datetime import date
from pathlib import Path


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--project", required=True, help="Project slug (typically basename of cwd)")
    p.add_argument("--cwd", default=os.getcwd(), help="Project working dir (defaults to $PWD)")
    p.add_argument("--claude-md", default=None, help="Path to CLAUDE.md (default: <cwd>/CLAUDE.md)")
    return p.parse_args()


def slugify(s: str, maxlen: int = 50) -> str:
    """Convert title to filesystem-safe slug."""
    s = re.sub(r"[^\w\s-]", "", s, flags=re.UNICODE)
    s = re.sub(r"[\s_-]+", "-", s).strip("-")
    return s[:maxlen].lower() or "untitled"


def extract_top_pitfall(claude_md_text: str) -> dict | None:
    """Find the first pitfall entry under the 踩坑/Pitfalls/Lessons section.

    Returns dict with keys: title, date, body. Or None if no entry found.
    """
    # Find section start
    section_pat = re.compile(r"^##\s+(?:踩坑记录|Known\s*Pitfalls|Lessons\s*Learned)\s*$", re.M | re.I)
    m = section_pat.search(claude_md_text)
    if not m:
        return None
    section_start = m.end()
    # Find next ## or EOF
    next_h = re.search(r"^##\s+", claude_md_text[section_start:], re.M)
    section_end = section_start + next_h.start() if next_h else len(claude_md_text)
    section = claude_md_text[section_start:section_end]

    # First entry — usually starts with ### Title
    entry_pat = re.compile(
        r"^###\s+(.+?)(?:\s*\(([\d-]+)\))?\s*$"
        r"([\s\S]*?)"
        r"(?=^###\s|\Z)",
        re.M
    )
    em = entry_pat.search(section)
    if not em:
        return None
    title = em.group(1).strip()
    pit_date = em.group(2) or date.today().isoformat()
    body = em.group(3).strip()
    return {"title": title, "date": pit_date, "body": body}


def already_synced(target_dir: Path, title: str) -> bool:
    """Check if an entry with the same title was already synced."""
    if not target_dir.is_dir():
        return False
    title_slug = slugify(title)
    for f in target_dir.glob(f"*{title_slug}*.md"):
        return True
    return False


def write_entry(target_dir: Path, entry: dict, project: str, cwd: str):
    target_dir.mkdir(parents=True, exist_ok=True)
    title_slug = slugify(entry["title"])
    out_path = target_dir / f"{entry['date']}-{title_slug}.md"
    # If exists, append a numeric suffix
    counter = 1
    while out_path.exists():
        out_path = target_dir / f"{entry['date']}-{title_slug}.{counter}.md"
        counter += 1
    content = (
        f"# {entry['title']}\n\n"
        f"- **Project**: {project}\n"
        f"- **Source**: {cwd}/CLAUDE.md\n"
        f"- **Date**: {entry['date']}\n"
        f"- **Synced**: {date.today().isoformat()}\n\n"
        "---\n\n"
        f"{entry['body']}\n"
    )
    out_path.write_text(content, encoding="utf-8")
    return out_path


def main():
    args = parse_args()
    claude_md_path = Path(args.claude_md) if args.claude_md else Path(args.cwd) / "CLAUDE.md"
    if not claude_md_path.is_file():
        print(f"pitfall-sync: no CLAUDE.md at {claude_md_path}", file=sys.stderr)
        sys.exit(0)
    text = claude_md_path.read_text(encoding="utf-8", errors="replace")
    entry = extract_top_pitfall(text)
    if not entry:
        print("pitfall-sync: no pitfall section / entry found in CLAUDE.md", file=sys.stderr)
        sys.exit(0)
    target_dir = Path.home() / ".anchor" / "pitfalls" / slugify(args.project, 80)
    if already_synced(target_dir, entry["title"]):
        print(f"pitfall-sync: '{entry['title']}' already synced (skip)", file=sys.stderr)
        sys.exit(0)
    out = write_entry(target_dir, entry, args.project, args.cwd)
    print(f"pitfall-sync: synced → {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
