#!/bin/bash
# SessionStart hook for anchor skill
# Prints a short context block to stdout, which Claude Code injects into the session context.
# Hook contract: read JSON from stdin, write text/JSON to stdout. Exit 0 = ok.

set -e

# shellcheck source=./_log_event.sh
. "$(dirname "${BASH_SOURCE[0]}")/_log_event.sh"

# Read hook input
input=$(cat)

# Extract cwd from input (fallback to current shell cwd)
cwd=$(echo "$input" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('cwd', ''))
except Exception:
    print('')
" 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"

# Build context
echo "## Efficient-Coding Context"
echo ""

# Project contracts (some are files, .cursor/rules is typically a directory)
contracts=""
for f in CLAUDE.md AGENTS.md .github/instructions.md; do
    if [ -f "$cwd/$f" ]; then
        contracts="$contracts $f"
    fi
done
if [ -d "$cwd/.cursor/rules" ]; then
    contracts="$contracts .cursor/rules/"
fi

if [ -n "$contracts" ]; then
    echo "**Project contracts present**:$contracts"
    echo "→ \`anchor\` skill requires you read them before coding."
else
    echo "**No project contracts found** in \`$cwd\`. Use neighbor files' actual style as the de facto standard."
fi

# Git status (only if it's a git repo)
if [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "?")
    modified=$(git -C "$cwd" status --short 2>/dev/null | wc -l | tr -d ' ')
    echo "**Git**: branch \`$branch\`, $modified changed file(s)."
fi

# Autonomous mode status
autonomous="off"
if [ -f "$HOME/.claude/.efficient-coding-autonomous" ]; then
    autonomous="on"
    echo ""
    echo "**Autonomous mode**: ENABLED. Stop hook will block stop while task list has incomplete items."
    echo "→ Treat the current user task as long-running; self-resolve obstacles; only stop to report a true blocker."
    echo "→ Disable with: \`rm ~/.claude/.efficient-coding-autonomous\`"
fi

# v1.7.0: long-task memory — inject ~/.anchor/active-task.md if present.
# This provides multi-session continuity: yesterday's locked task, last
# milestone, current branch, recent decisions, open questions all carry over.
if [ -f "$HOME/.anchor/active-task.md" ]; then
    echo ""
    echo "## Active long-task memory (from \`~/.anchor/active-task.md\`)"
    echo ""
    # Truncate to first 60 lines to avoid swamping session context
    head -60 "$HOME/.anchor/active-task.md"
    total_lines=$(wc -l < "$HOME/.anchor/active-task.md")
    if [ "$total_lines" -gt 60 ]; then
        echo ""
        echo "_(... ${total_lines} lines total; \`cat ~/.anchor/active-task.md\` for full history)_"
    fi
    echo ""
    echo "→ If this is the SAME long task you were on yesterday, /resume <label> or just continue."
    echo "→ If unrelated, /lock new scope (anchor will clear/reset active-task on /milestone or /done)."
fi

# Log event
EC_LOG_event="session_start" \
EC_LOG_cwd="$cwd" \
EC_LOG_autonomous="$autonomous" \
ec_log_event

exit 0
