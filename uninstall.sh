#!/bin/bash
# Uninstall anchor from ~/.claude/

set -e

CLAUDE_DIR="$HOME/.claude"

echo "anchor uninstaller"
echo "  target: $CLAUDE_DIR"
echo ""

# Skill — remove individual files then dirs, avoid rm -rf
if [ -d "$CLAUDE_DIR/skills/efficient-coding" ]; then
    echo "→ Removing $CLAUDE_DIR/skills/efficient-coding/"
    rm -f "$CLAUDE_DIR/skills/efficient-coding/SKILL.md"
    rm -f "$CLAUDE_DIR/skills/efficient-coding/references/"*.md
    rm -f "$CLAUDE_DIR/skills/efficient-coding/scripts/"*.sh
    rmdir "$CLAUDE_DIR/skills/efficient-coding/references" 2>/dev/null || true
    rmdir "$CLAUDE_DIR/skills/efficient-coding/scripts" 2>/dev/null || true
    rmdir "$CLAUDE_DIR/skills/efficient-coding" 2>/dev/null || true
fi

# Commands
for cmd in lock pit scan "done" next recap init-claude-md status ship diff cleanup; do
    if [ -f "$CLAUDE_DIR/commands/$cmd.md" ]; then
        echo "→ Removing $CLAUDE_DIR/commands/$cmd.md"
        rm -f "$CLAUDE_DIR/commands/$cmd.md"
    fi
done

# Autonomous flag
if [ -f "$CLAUDE_DIR/.efficient-coding-autonomous" ]; then
    echo "→ Removing autonomous mode flag"
    rm -f "$CLAUDE_DIR/.efficient-coding-autonomous"
fi

# Codex CLI install (if present)
CODEX_DIR="$HOME/.codex"
if [ -d "$CODEX_DIR/skills/ec" ]; then
    echo "→ Removing $CODEX_DIR/skills/ec/"
    rm -f "$CODEX_DIR/skills/ec/SKILL.md"
    rm -f "$CODEX_DIR/skills/ec/references/"*.md
    rm -f "$CODEX_DIR/skills/ec/scripts/"*.sh
    rmdir "$CODEX_DIR/skills/ec/references" 2>/dev/null || true
    rmdir "$CODEX_DIR/skills/ec/scripts" 2>/dev/null || true
    rmdir "$CODEX_DIR/skills/ec" 2>/dev/null || true
fi
# Codex commands-as-skills
for cmd in lock pit scan "done" next recap init-claude-md status ship diff cleanup; do
    if [ -d "$CODEX_DIR/skills/$cmd" ]; then
        echo "→ Removing $CODEX_DIR/skills/$cmd/"
        rm -f "$CODEX_DIR/skills/$cmd/SKILL.md"
        rmdir "$CODEX_DIR/skills/$cmd" 2>/dev/null || true
    fi
done

echo ""
echo "✓ Files removed."

# Also remove anchor's hook entries from settings.json so Claude Code doesn't
# try to call deleted scripts on next launch (v1.3.8 fix).
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    BACKUP="$CLAUDE_DIR/settings.json.bak.$(date +%s)"
    cp "$CLAUDE_DIR/settings.json" "$BACKUP"
    removed=$(python3 - "$CLAUDE_DIR/settings.json" <<'PYEOF'
import json, os, re, sys, tempfile
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text())
hooks = data.get("hooks", {})
PAT = re.compile(r"efficient-coding/scripts/[\w.-]+\.sh")
removed = 0
for event, groups in list(hooks.items()):
    new_groups = []
    for grp in groups:
        kept = [h for h in grp.get("hooks", []) if not PAT.search(h.get("command", ""))]
        skipped = len(grp.get("hooks", [])) - len(kept)
        removed += skipped
        if kept:
            grp["hooks"] = kept
            new_groups.append(grp)
        elif not skipped:
            new_groups.append(grp)
    if new_groups:
        hooks[event] = new_groups
    else:
        hooks.pop(event, None)
data["hooks"] = hooks
# Atomic replace
fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
try:
    with os.fdopen(fd, "w") as fh:
        fh.write(json.dumps(data, indent=2))
    os.replace(tmp, str(path))
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise
print(removed)
PYEOF
)
    if [ "${removed:-0}" -gt 0 ]; then
        echo "→ Removed $removed anchor hook entries from settings.json (backup: $(basename "$BACKUP"))"
    else
        rm -f "$BACKUP"
    fi
fi
echo ""
