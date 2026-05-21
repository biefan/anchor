#!/bin/bash
# Uninstall anchor from ~/.claude/
#
# v1.4 ordering: settings.json hook entries are removed FIRST (and verified)
# before any script files are deleted. If the settings clean fails, no scripts
# are removed — avoids leaving Claude Code with hooks pointing at deleted files.

set -e

CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

ALL_HOOKS=0
for arg in "$@"; do
    case "$arg" in
        --all-hooks) ALL_HOOKS=1 ;;
        -h|--help)
            cat <<'USAGE'
Usage: ./uninstall.sh [--all-hooks]

Removes anchor from ~/.claude/ (Claude Code) and ~/.codex/ (if installed).

By default, only removes hook entries whose path is $HOME/.claude/skills/...
(the install.sh-managed scheme). Plugin-marketplace hooks (CLAUDE_PLUGIN_ROOT)
are left intact — they're managed by the plugin system, uninstall via plugin.

Options:
  --all-hooks   Also remove plugin-path hook entries
  -h, --help    Show this message
USAGE
            exit 0
            ;;
    esac
done

echo "anchor uninstaller"
echo "  target: $CLAUDE_DIR"
[ "$ALL_HOOKS" = "1" ] && echo "  flag: --all-hooks (also removes plugin-path hook entries)"
echo ""

# ---- 0. Acquire shared anchor lock — see install.sh for rationale. ----
mkdir -p "$CLAUDE_DIR"
LOCK_FILE="$CLAUDE_DIR/.anchor.lock"
touch "$LOCK_FILE"
exec 9>"$LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
    if ! flock -w 30 9; then
        echo "ERROR: could not acquire $LOCK_FILE within 30s — another install/uninstall is running?" >&2
        exit 1
    fi
else
    if ! python3 -c "
import fcntl, sys
try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(1)
" 2>/dev/null; then
        echo "WARNING: could not acquire $LOCK_FILE (no flock(1), Python fcntl declined); proceeding without serialization." >&2
    fi
fi

# ---- 1. Clean settings.json hook entries FIRST (before deleting scripts). ----
# If this fails, scripts stay so the hooks still point at something real.
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    BACKUP="$(mktemp "$CLAUDE_DIR/settings.json.bak.XXXXXX")"
    cp "$CLAUDE_DIR/settings.json" "$BACKUP"
    if removed=$(ALL_HOOKS="$ALL_HOOKS" python3 - "$CLAUDE_DIR/settings.json" <<'PYEOF'
import json, os, re, stat, sys, tempfile
from pathlib import Path

# flock is held by the parent bash script on ~/.claude/.anchor.lock; no need
# to flock here. v1.4.1: removing the inode-level flock that os.replace bypassed.
ANCHOR_SCRIPT_PAT = re.compile(r"(?:efficient-coding|anchor)/scripts/[\w.-]+\.sh")
HOME_PATH_PAT = re.compile(r"(?:\$\{?HOME\}?|~)/\.claude/skills/anchor/")
PLUGIN_PATH_PAT = re.compile(r"\$\{?CLAUDE_PLUGIN_ROOT\}?")
all_hooks = os.environ.get("ALL_HOOKS") == "1"

path = Path(sys.argv[1])
try:
    orig_mode = stat.S_IMODE(os.stat(str(path)).st_mode)
except OSError:
    orig_mode = 0o600

data = json.loads(path.read_text())
hooks = data.get("hooks", {})
removed = 0

def should_remove(cmd):
    if not ANCHOR_SCRIPT_PAT.search(cmd):
        return False
    if all_hooks:
        return True
    # Default: ONLY remove hooks whose path is the home-scheme install
    # ($HOME/.claude/skills/anchor/...). Plugin-managed and any
    # unknown-scheme paths (custom wrappers, third-party install layouts)
    # are left intact. --all-hooks opts into the broader sweep.
    return bool(HOME_PATH_PAT.search(cmd))

for event, groups in list(hooks.items()):
    new_groups = []
    for grp in groups:
        kept = [h for h in grp.get("hooks", []) if not should_remove(h.get("command", ""))]
        skipped = len(grp.get("hooks", [])) - len(kept)
        removed += skipped
        if kept:
            grp["hooks"] = kept
            new_groups.append(grp)
    if new_groups:
        hooks[event] = new_groups
    else:
        hooks.pop(event, None)
data["hooks"] = hooks

# Atomic replace, preserve original mode.
fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
try:
    with os.fdopen(fd, "w") as fh:
        fh.write(json.dumps(data, indent=2))
    os.chmod(tmp, orig_mode)
    os.replace(tmp, str(path))
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise
print(removed)
PYEOF
)
    then
        if [ "${removed:-0}" -gt 0 ]; then
            echo "→ Removed $removed anchor hook entry/entries from settings.json (backup: $(basename "$BACKUP"))"
        else
            rm -f "$BACKUP"
        fi
    else
        echo "ERROR: failed to update settings.json — aborting, no files removed." >&2
        echo "  Backup at: $BACKUP" >&2
        echo "  Re-run after fixing the settings.json issue, or restore from backup." >&2
        exit 1
    fi
fi

# ---- 2. Now safe to remove script files. ----
# Skill
if [ -d "$CLAUDE_DIR/skills/anchor" ] || [ -d "$CLAUDE_DIR/skills/efficient-coding" ]; then
    echo "→ Removing $CLAUDE_DIR/skills/anchor/"
    rm -f "$CLAUDE_DIR/skills/anchor/SKILL.md"
    rm -f "$CLAUDE_DIR/skills/anchor/references/templates/"*.md
    rm -f "$CLAUDE_DIR/skills/anchor/references/"*.md
    rm -f "$CLAUDE_DIR/skills/anchor/scripts/"*.sh
    rm -f "$CLAUDE_DIR/skills/anchor/scripts/"*.py
    rmdir "$CLAUDE_DIR/skills/anchor/references/templates" 2>/dev/null || true
    rmdir "$CLAUDE_DIR/skills/anchor/references" 2>/dev/null || true
    rmdir "$CLAUDE_DIR/skills/anchor/scripts" 2>/dev/null || true
    rmdir "$CLAUDE_DIR/skills/anchor" 2>/dev/null || true
    rmdir "$CLAUDE_DIR/skills/efficient-coding" 2>/dev/null || true
fi

# Commands
for cmd in lock pit scan "done" next recap init-claude-md status ship diff cleanup ec cost report save resume milestone recall; do
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
if [ -d "$CODEX_DIR/skills/anchor" ] || [ -d "$CODEX_DIR/skills/ec" ]; then
    echo "→ Removing $CODEX_DIR/skills/anchor/"
    rm -f "$CODEX_DIR/skills/anchor/SKILL.md"
    rm -f "$CODEX_DIR/skills/anchor/references/templates/"*.md
    rm -f "$CODEX_DIR/skills/anchor/references/"*.md
    rm -f "$CODEX_DIR/skills/anchor/scripts/"*.sh
    rm -f "$CODEX_DIR/skills/anchor/scripts/"*.py
    rmdir "$CODEX_DIR/skills/anchor/references/templates" 2>/dev/null || true
    rmdir "$CODEX_DIR/skills/anchor/references" 2>/dev/null || true
    rmdir "$CODEX_DIR/skills/anchor/scripts" 2>/dev/null || true
    rmdir "$CODEX_DIR/skills/anchor" 2>/dev/null || true
    rmdir "$CODEX_DIR/skills/ec" 2>/dev/null || true
fi
# Codex commands-as-skills
for cmd in lock pit scan "done" next recap init-claude-md status ship diff cleanup ec cost report save resume milestone recall; do
    if [ -d "$CODEX_DIR/skills/$cmd" ]; then
        echo "→ Removing $CODEX_DIR/skills/$cmd/"
        rm -f "$CODEX_DIR/skills/$cmd/SKILL.md"
        rmdir "$CODEX_DIR/skills/$cmd" 2>/dev/null || true
    fi
done

echo ""
echo "✓ Files removed."
echo ""
