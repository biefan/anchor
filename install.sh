#!/bin/bash
# Install anchor (efficient-coding skill + 7 slash commands + 4 safety hooks)
# - Always installs to ~/.claude/ (Claude Code)
# - If `codex` CLI is detected, also installs to ~/.codex/
# - By default merges hook config into ~/.claude/settings.json (timestamped backup)
# - Idempotent: re-running won't duplicate hooks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

WITH_HOOKS=1
for arg in "$@"; do
    case "$arg" in
        --no-hooks) WITH_HOOKS=0 ;;
        -h|--help)
            cat <<'USAGE'
Usage: ./install.sh [--no-hooks]

Installs anchor into ~/.claude/ (Claude Code) and ~/.codex/ (if Codex CLI present).
By default also merges hook config into ~/.claude/settings.json (with timestamped backup, idempotent).

Options:
  --no-hooks    Skip merging hooks into settings.json
  -h, --help    Show this message
USAGE
            exit 0
            ;;
    esac
done

echo "anchor installer"

# ---- 1. Claude Code: skill + commands ----
mkdir -p "$CLAUDE_DIR/skills/efficient-coding/references"
mkdir -p "$CLAUDE_DIR/skills/efficient-coding/scripts"
mkdir -p "$CLAUDE_DIR/commands"

cp "$SCRIPT_DIR/skills/efficient-coding/SKILL.md" "$CLAUDE_DIR/skills/efficient-coding/"
cp "$SCRIPT_DIR/skills/efficient-coding/references/"*.md "$CLAUDE_DIR/skills/efficient-coding/references/"
cp "$SCRIPT_DIR/skills/efficient-coding/scripts/"*.sh "$CLAUDE_DIR/skills/efficient-coding/scripts/"
chmod +x "$CLAUDE_DIR/skills/efficient-coding/scripts/"*.sh
cp "$SCRIPT_DIR/commands/"*.md "$CLAUDE_DIR/commands/"
echo "  ✓ Claude Code: skill + 7 commands"

# ---- 2. Claude Code hooks (auto-merge into settings.json) ----
if [ "$WITH_HOOKS" = "1" ]; then
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        BACKUP="$CLAUDE_DIR/settings.json.bak.$(date +%s)"
        cp "$CLAUDE_DIR/settings.json" "$BACKUP"
        python3 - "$SCRIPT_DIR/settings.hooks.json" "$CLAUDE_DIR/settings.json" <<'PYEOF'
import json, sys
from pathlib import Path

src = json.loads(Path(sys.argv[1]).read_text())
src_hooks = src.get("hooks", {})
target_path = Path(sys.argv[2])
target = json.loads(target_path.read_text())
existing = target.get("hooks", {})

added = 0
for event, groups in src_hooks.items():
    existing.setdefault(event, [])
    existing_cmds = {h["command"] for g in existing[event] for h in g.get("hooks", [])}
    for grp in groups:
        grp_cmds = {h["command"] for h in grp.get("hooks", [])}
        if grp_cmds & existing_cmds:
            continue  # already installed
        existing[event].append(grp)
        added += 1

target["hooks"] = existing
target_path.write_text(json.dumps(target, indent=2))
print(f"    (merged {added} new hook entries)")
PYEOF
        echo "  ✓ Claude Code: hooks merged into settings.json (backup: $(basename "$BACKUP"))"
    else
        # Fresh install — write a settings.json containing only hooks
        python3 -c "
import json, sys
from pathlib import Path
src = json.loads(Path('$SCRIPT_DIR/settings.hooks.json').read_text())
src.pop('_comment', None)
src.pop('_optional_statusline', None)
Path('$CLAUDE_DIR/settings.json').write_text(json.dumps(src, indent=2))
"
        echo "  ✓ Claude Code: created ~/.claude/settings.json with hooks"
    fi
fi

# ---- 3. Codex CLI (if installed) ----
if command -v codex >/dev/null 2>&1 && [ -d "$CODEX_DIR" ]; then
    mkdir -p "$CODEX_DIR/skills/ec/references"
    mkdir -p "$CODEX_DIR/skills/ec/scripts"
    cp "$SCRIPT_DIR/skills/efficient-coding/SKILL.md" "$CODEX_DIR/skills/ec/"
    cp "$SCRIPT_DIR/skills/efficient-coding/references/"*.md "$CODEX_DIR/skills/ec/references/"
    cp "$SCRIPT_DIR/skills/efficient-coding/scripts/"*.sh "$CODEX_DIR/skills/ec/scripts/"
    chmod +x "$CODEX_DIR/skills/ec/scripts/"*.sh
    for cmd in lock pit scan "done" next recap init-claude-md; do
        mkdir -p "$CODEX_DIR/skills/$cmd"
        cp "$SCRIPT_DIR/commands/$cmd.md" "$CODEX_DIR/skills/$cmd/SKILL.md"
    done
    echo "  ✓ Codex CLI: skill + 7 commands"
fi

echo ""
echo "Done. Try:"
echo "  /ec        — load the full skill"
echo "  /lock <task>  — anchor task scope before coding"
echo "  /done      — wrap-up checklist (lint + E2E + codex hint + CLAUDE.md writeback)"
echo ""
echo "Enable autonomous mode (Stop hook blocks until task list is complete):"
echo "  touch ~/.claude/.efficient-coding-autonomous"
[ "$WITH_HOOKS" = "0" ] && echo "" && echo "(Skipped hooks — re-run without --no-hooks to enable them)"
