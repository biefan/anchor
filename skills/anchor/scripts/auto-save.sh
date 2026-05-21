#!/bin/bash
# auto-save.sh — silent auto-backup of current task list when triggered by hooks.
#
# Called by PreCompact + Stop hooks. The user gets a fallback they didn't have
# to ask for (anchor "dream mode"). Files land in ~/.anchor/saved-tasks/ named
# auto-<reason>-<ts>.md; old ones (>20) are GC'd automatically.
#
# Usage:  bash auto-save.sh <reason> <session_id>
#   reason: "precompact" | "stop" | "manual" — used in filename
#   session_id: from hook stdin JSON
#
# Exits 0 silently if nothing to save or save fails (we don't want auto-save
# blocking the parent hook). The parent hook continues regardless.

set -e
reason=${1:-unknown}
session_id=${2:-}

# Bail silently — nothing to save
if [ -z "$session_id" ]; then
    exit 0
fi

task_dir="$HOME/.claude/tasks/$session_id"
if [ ! -d "$task_dir" ]; then
    exit 0
fi

# Use Python for JSON + atomic write + GC
EC_TASK_DIR="$task_dir" \
EC_REASON="$reason" \
EC_SESSION="$session_id" \
python3 - <<'PYEOF' 2>/dev/null || true
import json
import os
import glob
import sys
from datetime import datetime
from pathlib import Path

task_dir = os.environ["EC_TASK_DIR"]
reason = os.environ["EC_REASON"]
session = os.environ["EC_SESSION"]

# Collect tasks
tasks = []
for p in sorted(glob.glob(os.path.join(task_dir, "*.json"))):
    try:
        with open(p) as f:
            tasks.append(json.load(f))
    except (json.JSONDecodeError, OSError):
        pass

# Skip if all complete — nothing to recover
incomplete = [t for t in tasks if t.get("status") in ("pending", "in_progress")]
if not incomplete:
    sys.exit(0)

# Save dir
save_dir = Path.home() / ".anchor" / "saved-tasks"
save_dir.mkdir(parents=True, exist_ok=True)

ts = datetime.now().strftime("%Y-%m-%dT%H%M%S")
out_path = save_dir / f"auto-{reason}-{ts}.md"

# Write markdown summary
lines = [
    f"# Auto-save ({reason}) — {ts}",
    "",
    f"- **Reason**: `{reason}` (triggered automatically by hook, not user)",
    f"- **Session**: `{session}`",
    f"- **Tasks**: {len(tasks)} total / {len(incomplete)} incomplete",
    f"- **Restore**: `/resume auto-{reason}-{ts}` to rebuild this task list in a new session",
    "",
    "## Incomplete tasks",
    "",
]
for t in incomplete:
    status = t.get("status", "?")
    subject = t.get("subject") or t.get("description") or "(no subject)"
    lines.append(f"### [{status}] {subject}")
    desc = t.get("description")
    if desc and desc != subject:
        lines.append("")
        lines.append(desc)
    lines.append("")

# Also list completed for context (so user knows what's already done if resuming)
completed = [t for t in tasks if t.get("status") == "completed"]
if completed:
    lines.append("## Completed before save (context)")
    lines.append("")
    for t in completed:
        subject = t.get("subject") or "(no subject)"
        lines.append(f"- ✓ {subject}")
    lines.append("")

# Atomic write
tmp = out_path.with_suffix(".tmp")
tmp.write_text("\n".join(lines), encoding="utf-8")
tmp.replace(out_path)

# GC: keep last 20 auto-* files, prune the rest
all_autos = sorted(
    save_dir.glob("auto-*.md"),
    key=lambda p: p.stat().st_mtime,
    reverse=True,
)
for old in all_autos[20:]:
    try:
        old.unlink()
    except OSError:
        pass

# Silent success — don't pollute hook output
PYEOF

exit 0
