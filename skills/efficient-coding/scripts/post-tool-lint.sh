#!/bin/bash
# PostToolUse(Edit/Write/MultiEdit) hook: run the appropriate linter for the
# just-edited file. Outputs lint issues as additionalContext (does NOT block).
# Detects language by extension and runs only locally-available linters.

set -e

# shellcheck source=./_log_event.sh
. "$(dirname "${BASH_SOURCE[0]}")/_log_event.sh"

input=$(cat)

tool=$(echo "$input" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null)

# Only inspect file-edit tools
case "$tool" in
    Edit|Write|MultiEdit|NotebookEdit) ;;
    *) exit 0 ;;
esac

file=$(echo "$input" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null)

[ -z "$file" ] && exit 0
[ ! -f "$file" ] && exit 0

# Skip files inside .claude/ (don't lint our own skill/commands/hook config)
case "$file" in
    */.claude/*) exit 0 ;;
esac

result=""
linter=""

case "$file" in
    *.py)
        if command -v ruff >/dev/null 2>&1; then
            linter="ruff"
            result=$(ruff check --quiet "$file" 2>&1 || true)
        elif command -v pyflakes >/dev/null 2>&1; then
            linter="pyflakes"
            result=$(pyflakes "$file" 2>&1 || true)
        fi
        ;;
    *.js|*.jsx|*.cjs|*.mjs)
        if command -v eslint >/dev/null 2>&1; then
            linter="eslint"
            # Let eslint find its own config (.eslintrc.*, eslint.config.js, package.json eslintConfig, etc.)
            # Earlier versions tried to pin --config via glob; bash didn't expand it inside double quotes,
            # so the explicit path was always wrong. Default discovery is what eslint is good at.
            result=$(eslint "$file" 2>&1 || true)
        fi
        ;;
    *.ts|*.tsx)
        if command -v eslint >/dev/null 2>&1; then
            linter="eslint"
            result=$(eslint "$file" 2>&1 || true)
        fi
        ;;
    *.rs)
        if command -v rustfmt >/dev/null 2>&1; then
            linter="rustfmt"
            d=$(rustfmt --check "$file" 2>&1 | head -20 || true)
            [ -n "$d" ] && result="rustfmt 建议:\n$d"
        fi
        ;;
    *.go)
        if command -v gofmt >/dev/null 2>&1; then
            linter="gofmt"
            d=$(gofmt -d "$file" 2>&1 | head -20 || true)
            [ -n "$d" ] && result="gofmt 建议:\n$d"
        fi
        ;;
    *.sh|*.bash)
        if command -v shellcheck >/dev/null 2>&1; then
            linter="shellcheck"
            result=$(shellcheck -S warning "$file" 2>&1 || true)
        fi
        ;;
    *.json)
        if command -v python3 >/dev/null 2>&1; then
            linter="json"
            result=$(python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$file" 2>&1 || true)
        fi
        ;;
esac

# Trim noise
result=$(echo "$result" | head -30 | sed '/^$/d')

if [ -n "$result" ]; then
    issue_count=$(echo "$result" | wc -l | tr -d ' ')
    EC_LOG_event="posttool_lint_issue" \
    EC_LOG_file="$file" \
    EC_LOG_linter="$linter" \
    EC_LOG_issue_count="$issue_count" \
    ec_log_event

    EC_LINT_LINTER="$linter" \
    EC_LINT_FILE="$file" \
    EC_LINT_RESULT="$result" \
    python3 - <<'PYEOF'
import json, os
linter = os.environ.get("EC_LINT_LINTER", "")
file = os.environ.get("EC_LINT_FILE", "")
result = os.environ.get("EC_LINT_RESULT", "")
out = (
    f"{linter} found issues in {file}:\n\n"
    f"{result}\n\n"
    "Per ec skill's \"最后清单\"，lint 通过才算 done。修了再 declare 完成；"
    "若是误警告，记下来 + 用 inline disable + 在 CLAUDE.md 解释为什么。"
)
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":out}}))
PYEOF
fi

exit 0
