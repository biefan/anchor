#!/bin/bash
# PostToolUse(Edit/Write/MultiEdit) hook: run the appropriate linter for the
# just-edited file. Outputs lint issues as additionalContext (does NOT block).
# Detects language by extension and runs only locally-available linters.

set -e

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
    *.claude/*|*/.claude/*) exit 0 ;;
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
            result=$(eslint --no-eslintrc --config "$(dirname "$file")/.eslintrc.*" "$file" 2>&1 || eslint "$file" 2>&1 || true)
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
            result=$(python3 -c "import json,sys; json.load(open('$file'))" 2>&1 || true)
        fi
        ;;
esac

# Trim noise
result=$(echo "$result" | head -30 | sed '/^$/d')

if [ -n "$result" ]; then
    python3 <<PYEOF
import json
out = """$linter found issues in $file:

$result

Per ec skill's "最后清单"，lint 通过才算 done。修了再 declare 完成；若是误警告，记下来 + 用 inline disable + 在 CLAUDE.md 解释为什么。"""
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":out}}))
PYEOF
fi

exit 0
