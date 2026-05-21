#!/bin/bash
# Print short status string about ec skill state.
# Designed to be appended to your existing statusLine output.
# Reads JSON input from stdin (Claude Code statusline contract) for session_id.

set -e

input=$(cat 2>/dev/null || echo "{}")

# Parts collected
parts=()

# Autonomous mode
if [ -f "$HOME/.claude/.efficient-coding-autonomous" ]; then
    parts+=("🤖auto")
fi

# Task list state (current session)
session_id=$(echo "$input" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    print('')
" 2>/dev/null)

if [ -n "$session_id" ]; then
    task_dir="$HOME/.claude/tasks/$session_id"
    if [ -d "$task_dir" ]; then
        counts=$(python3 <<PYEOF 2>/dev/null
import json, os, glob
pending = ip = done = 0
for p in glob.glob(os.path.join("$task_dir", "*.json")):
    try:
        with open(p) as f:
            s = json.load(f).get("status", "")
        if s == "pending": pending += 1
        elif s == "in_progress": ip += 1
        elif s == "completed": done += 1
    except Exception:
        pass
total = pending + ip + done
if total:
    print(f"{done}/{total}")
else:
    print("")
PYEOF
)
        if [ -n "$counts" ] && [ "$counts" != "0/0" ]; then
            parts+=("📋$counts")
        fi
    fi
fi

# Join with spaces; print only if non-empty
if [ ${#parts[@]} -gt 0 ]; then
    IFS=' '
    echo "${parts[*]}"
fi
