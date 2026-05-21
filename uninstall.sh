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
for cmd in lock pit scan done next recap init-claude-md; do
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
for cmd in lock pit scan done next recap init-claude-md; do
    if [ -d "$CODEX_DIR/skills/$cmd" ]; then
        echo "→ Removing $CODEX_DIR/skills/$cmd/"
        rm -f "$CODEX_DIR/skills/$cmd/SKILL.md"
        rmdir "$CODEX_DIR/skills/$cmd" 2>/dev/null || true
    fi
done

echo ""
echo "✓ Files removed."
echo ""
echo "Manual step:"
echo "  Edit $CLAUDE_DIR/settings.json and remove the SessionStart / Stop hook entries"
echo "  whose 'command' references session-start-inject.sh or stop-self-check.sh."
echo ""
