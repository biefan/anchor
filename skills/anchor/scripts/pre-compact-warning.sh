#!/bin/bash
# PreCompact hook — fires before Claude Code auto-compacts session context.
# Warns the user if task list still has pending/in_progress items so they can
# /save first to preserve full state.
#
# Hook contract: read JSON from stdin, write JSON to stdout (or nothing).
# Set decision=block if user should /save first. Otherwise exit 0.

# shellcheck source=./_log_event.sh
. "$(dirname "${BASH_SOURCE[0]}")/_log_event.sh"

input=$(cat)

# Extract session_id
session_id=$(echo "$input" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    print('')
" 2>/dev/null)

if [ -z "$session_id" ]; then
    exit 0
fi

task_dir="$HOME/.claude/tasks/$session_id"
if [ ! -d "$task_dir" ]; then
    exit 0  # no task list, nothing to lose
fi

# Count pending / in_progress
incomplete_count=$(EC_TASK_DIR="$task_dir" python3 - <<'PYEOF' 2>/dev/null
import json, os, glob
task_dir = os.environ.get("EC_TASK_DIR", "")
n = 0
for p in glob.glob(os.path.join(task_dir, "*.json")):
    try:
        with open(p) as f:
            s = json.load(f).get("status", "")
        if s in ("pending", "in_progress"):
            n += 1
    except Exception:
        pass
print(n)
PYEOF
)

if [ "${incomplete_count:-0}" -gt 0 ]; then
    EC_LOG_event="precompact_warn" \
    EC_LOG_session_id="$session_id" \
    EC_LOG_pending="$incomplete_count" \
    ec_log_event

    # Non-blocking advisory: print warning text. PreCompact doesn't actually
    # block but text becomes part of system context for the model to see.
    EC_PENDING="$incomplete_count" python3 - <<'PYEOF'
import json, os
n = os.environ.get("EC_PENDING", "0")
msg = (
    f"⚠️  Anchor PreCompact warning: task list still has {n} pending/in_progress item(s).\n\n"
    "Auto-compact is about to truncate older context. To preserve full multi-day task state, "
    "consider running `/save <label>` BEFORE proceeding. After compact, use `/resume <label>` "
    "to restore the task list cleanly.\n\n"
    "If this is a short task and you don't need cross-session continuity, ignore this and continue."
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreCompact", "additionalContext": msg}}))
PYEOF
fi

exit 0
