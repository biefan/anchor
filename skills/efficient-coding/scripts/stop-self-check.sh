#!/bin/bash
# Stop hook for efficient-coding autonomous mode
# Blocks stop if the current session's task list still has pending/in_progress items.
# Hook contract: read JSON from stdin, write JSON or exit code to control stop.
# Only active when ~/.claude/.efficient-coding-autonomous exists.

set -e

# Escape hatch: autonomous mode not enabled → allow stop
if [ ! -f "$HOME/.claude/.efficient-coding-autonomous" ]; then
    exit 0
fi

# Read hook input
input=$(cat)

# Extract session_id
session_id=$(echo "$input" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('session_id', ''))
except Exception:
    print('')
" 2>/dev/null)

# No session_id → can't determine task state → allow stop
if [ -z "$session_id" ]; then
    exit 0
fi

task_dir="$HOME/.claude/tasks/$session_id"

# No task list for this session → not a code task, allow stop
if [ ! -d "$task_dir" ]; then
    exit 0
fi

# Check for incomplete tasks
incomplete=$(python3 <<PYEOF 2>/dev/null
import json, os, glob
task_dir = "$task_dir"
incomplete = []
for path in sorted(glob.glob(os.path.join(task_dir, "*.json"))):
    try:
        with open(path) as f:
            t = json.load(f)
        if t.get("status") in ("pending", "in_progress"):
            subject = t.get("subject", "?")[:80]
            tid = t.get("id", "?")
            incomplete.append(f"  - #{tid} [{t.get('status')}]: {subject}")
    except Exception:
        continue
if incomplete:
    print("\n".join(incomplete))
PYEOF
)

# All done → allow stop
if [ -z "$incomplete" ]; then
    exit 0
fi

# Block stop and tell Claude to continue
# Use JSON form so Claude Code parses our reason properly.
python3 <<PYEOF
import json
reason = """Autonomous mode is ON — task list still has incomplete items:

$incomplete

By the efficient-coding skill's autonomous-mode rules:
1. Do not stop. Continue working on the next pending task.
2. If blocked, use 观察 → 假设 → 验证: state the observation, propose one hypothesis, design a minimal test to refute/confirm. Iterate up to 3 hypotheses before reporting.
3. Only report a true blocker when you've exhausted self-resolution OR you genuinely need a user decision (high-cost action, ambiguous business choice, missing credential).
4. See ~/.claude/skills/efficient-coding/references/autonomous-mode.md for the full protocol.

To override and stop anyway: \`rm ~/.claude/.efficient-coding-autonomous\` then end."""
print(json.dumps({"decision": "block", "reason": reason}))
PYEOF

exit 0
