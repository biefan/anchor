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
# v1.8.1: lean mode — skip non-essential injections to save ~900 tokens/session.
# Toggle via `touch ~/.claude/.anchor-lean` (cmd: /lean on|off).
lean_mode=0
[ -f "$HOME/.claude/.anchor-lean" ] && lean_mode=1

# v1.7.0+: active-task.md inject — but only if project matches (v1.8.1: project-scoped)
if [ "$lean_mode" = "0" ] && [ -f "$HOME/.anchor/active-task.md" ]; then
    # v1.8.1: only inject if the saved active-task is for THIS project
    # (matches by basename of cwd). Avoids polluting unrelated session.
    project_in_file=$(grep -oE '^\s*-?\s*\*\*Project\*\*[:：]\s*[^\s]+' "$HOME/.anchor/active-task.md" 2>/dev/null | head -1 | sed -E 's/.*\*\*[:：]\s*//')
    cwd_basename=$(basename "$cwd")
    if [ -z "$project_in_file" ] || [ "$project_in_file" = "$cwd_basename" ]; then
        echo ""
        echo "## Active long-task memory (project: ${project_in_file:-$cwd_basename})"
        echo ""
        # v1.8.1: cap at 40 lines (was 60) — token-budget-conscious
        head -40 "$HOME/.anchor/active-task.md"
        total_lines=$(wc -l < "$HOME/.anchor/active-task.md")
        if [ "$total_lines" -gt 40 ]; then
            echo "_(...${total_lines} lines; full: \`cat ~/.anchor/active-task.md\`)_"
        fi
    fi
fi

# v1.8.0: preferences inject (v1.8.1: lean-mode-aware + shorter cap)
if [ "$lean_mode" = "0" ] && [ -f "$HOME/.anchor/memory/preferences.md" ]; then
    pref_lines=$(wc -l < "$HOME/.anchor/memory/preferences.md")
    # Only inject if file is non-trivial (>3 lines, has actual preferences)
    if [ "$pref_lines" -gt 3 ]; then
        echo ""
        echo "## User preferences"
        echo ""
        # v1.8.1: cap at 20 lines (was 30) — preferences should be terse
        head -20 "$HOME/.anchor/memory/preferences.md"
        if [ "$pref_lines" -gt 20 ]; then
            echo "_(...$pref_lines lines; full: \`cat ~/.anchor/memory/preferences.md\`)_"
        fi
    fi
fi

# v1.9.0: project-scoped memory index — show Claude what's remembered ABOUT THIS PROJECT.
# Without this, /pit /decide /remember are "write-only" — saved to disk but never
# proactively surfaced. The index lists titles + dates so Claude knows what
# past learnings exist, and can /recall <keyword> for full content when relevant.
if [ "$lean_mode" = "0" ]; then
    project_slug=$(basename "$cwd")
    memory_root="$HOME/.anchor/memory"
    has_memory=0

    for category in pitfalls decisions facts; do
        dir="$memory_root/$category/$project_slug"
        [ -d "$dir" ] || continue
        count=$(find "$dir" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
        [ "$count" = "0" ] && continue
        if [ "$has_memory" = "0" ]; then
            echo ""
            echo "## Memory index (project: \`$project_slug\`)"
            echo "_Past learnings for this project. Use \`/recall <keyword>\` for full content._"
            has_memory=1
        fi
        echo ""
        echo "### ${category} (${count})"
        # Top 5 most recent: date from filename + first markdown heading
        find "$dir" -maxdepth 1 -name '*.md' -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr | head -5 | while read -r _ts f; do
            date_part=$(basename "$f" .md | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo "????-??-??")
            title=$(grep -m1 '^#' "$f" 2>/dev/null | sed 's/^#\+ *//')
            [ -z "$title" ] && title=$(basename "$f" .md)
            echo "- ${date_part} — ${title}"
        done
        if [ "$count" -gt 5 ]; then
            echo "- _(... $((count - 5)) more, ls \`$dir\` for all)_"
        fi
    done

    if [ "$has_memory" = "1" ]; then
        echo ""
        echo "→ **Auto-recall reflex**: when user mentions a topic that matches an entry above, run \`/recall <topic>\` to load full content BEFORE answering."
    fi
fi

if [ "$lean_mode" = "1" ]; then
    echo ""
    echo "_(lean mode: SessionStart skipped active-task / preferences / memory index — \`rm ~/.claude/.anchor-lean\` to restore)_"
fi

# Log event
EC_LOG_event="session_start" \
EC_LOG_cwd="$cwd" \
EC_LOG_autonomous="$autonomous" \
ec_log_event

exit 0
