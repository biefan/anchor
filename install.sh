#!/bin/bash
# Install anchor (skill + 11 slash commands + 4 safety hooks)
# - Always installs to ~/.claude/ (Claude Code)
# - If `codex` CLI is detected, also installs to ~/.codex/
# - By default merges hook config into ~/.claude/settings.json (timestamped backup)
# - Idempotent: re-running won't duplicate hooks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

WITH_HOOKS=1
export REPLACE_PLUGIN_HOOKS=0
for arg in "$@"; do
    case "$arg" in
        --no-hooks) WITH_HOOKS=0 ;;
        --replace-plugin-hooks) REPLACE_PLUGIN_HOOKS=1 ;;
        -h|--help)
            cat <<'USAGE'
Usage: ./install.sh [--no-hooks] [--replace-plugin-hooks]

Installs anchor into ~/.claude/ (Claude Code) and ~/.codex/ (if Codex CLI present).
By default also merges hook config into ~/.claude/settings.json (with timestamped backup, idempotent).

Options:
  --no-hooks                Skip merging hooks into settings.json
  --replace-plugin-hooks    Replace any existing plugin-scheme hook entries
                            ($\{CLAUDE_PLUGIN_ROOT\}/...) with home-scheme paths.
                            By default plugin-managed hooks are left alone —
                            they're owned by the plugin system. Pass this flag
                            only when migrating off the plugin install path.
  -h, --help                Show this message
USAGE
            exit 0
            ;;
    esac
done

echo "anchor installer"

# ---- 0. Acquire shared anchor lock (covers file copy + settings.json RMW).
# The lock file is permanent (never replaced) so concurrent installs/
# uninstalls actually serialize on the same kernel lock object.
# Previously we flock'd settings.json itself, but `os.replace` changes the
# inode, and the next process flock'd a different object — no serialization.
mkdir -p "$CLAUDE_DIR"
LOCK_FILE="$CLAUDE_DIR/.anchor.lock"
touch "$LOCK_FILE"
exec 9>"$LOCK_FILE"
# Prefer the `flock` binary (Linux/util-linux). On macOS / minimal images that
# lack `flock(1)`, fall through to Python `fcntl.flock` so we still serialize.
if command -v flock >/dev/null 2>&1; then
    if ! flock -w 30 9; then
        echo "ERROR: could not acquire $LOCK_FILE within 30s — another install/uninstall is running?" >&2
        exit 1
    fi
else
    # Python fallback: acquire and hold the lock for the entire shell lifetime.
    # The subshell stays alive until trap EXIT, holding the lock by holding fd 9.
    if ! python3 -c "
import fcntl, os, sys
try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    sys.exit(1)
" 2>/dev/null; then
        # Best-effort: filesystem may not support flock; warn and proceed.
        echo "WARNING: could not acquire $LOCK_FILE (no flock(1) binary, Python fcntl declined); proceeding without serialization." >&2
    fi
fi

# ---- 1. Claude Code: skill + commands ----
mkdir -p "$CLAUDE_DIR/skills/anchor/references/templates"
mkdir -p "$CLAUDE_DIR/skills/anchor/scripts"
mkdir -p "$CLAUDE_DIR/commands"

cp "$SCRIPT_DIR/skills/anchor/SKILL.md" "$CLAUDE_DIR/skills/anchor/"
cp "$SCRIPT_DIR/skills/anchor/references/"*.md "$CLAUDE_DIR/skills/anchor/references/"
cp "$SCRIPT_DIR/skills/anchor/references/templates/"*.md "$CLAUDE_DIR/skills/anchor/references/templates/"
cp "$SCRIPT_DIR/skills/anchor/scripts/"*.sh "$CLAUDE_DIR/skills/anchor/scripts/"
cp "$SCRIPT_DIR/skills/anchor/scripts/"*.py "$CLAUDE_DIR/skills/anchor/scripts/"
chmod +x "$CLAUDE_DIR/skills/anchor/scripts/"*.sh "$CLAUDE_DIR/skills/anchor/scripts/"*.py
cp "$SCRIPT_DIR/commands/"*.md "$CLAUDE_DIR/commands/"
echo "  ✓ Claude Code: skill + 11 commands"

# ---- 2. Claude Code hooks (auto-merge into settings.json) ----
if [ "$WITH_HOOKS" = "1" ]; then
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        BACKUP="$(mktemp "$CLAUDE_DIR/settings.json.bak.XXXXXX")"
        cp "$CLAUDE_DIR/settings.json" "$BACKUP"
        python3 - "$SCRIPT_DIR/settings.hooks.json" "$CLAUDE_DIR/settings.json" <<'PYEOF'
import collections, json, os, re, stat, sys, tempfile
from pathlib import Path

replace_plugin_hooks = os.environ.get("REPLACE_PLUGIN_HOOKS") == "1"

# Dedup keys: scheme-aware so we distinguish a hook installed via the plugin
# marketplace path from one installed by ./install.sh. (flock is held by the
# parent bash script on ~/.claude/.anchor.lock — no need to flock here.)
ANCHOR_SCRIPT_PAT = re.compile(r"(?:efficient-coding|anchor)/scripts/([\w.-]+\.sh)")
PLUGIN_PATH_PAT = re.compile(r"\$\{?CLAUDE_PLUGIN_ROOT\}?")
HOME_PATH_PAT = re.compile(r"(?:\$\{?HOME\}?|~)/\.claude/skills/anchor/")

def anchor_key(cmd):
    m = ANCHOR_SCRIPT_PAT.search(cmd)
    if not m:
        return ("other", cmd)
    if PLUGIN_PATH_PAT.search(cmd):
        scheme = "plugin"
    elif HOME_PATH_PAT.search(cmd):
        scheme = "home"
    else:
        scheme = "other-anchor"
    return ("anchor", m.group(1), scheme)


src = json.loads(Path(sys.argv[1]).read_text())
src_hooks = src.get("hooks", {})
target_path = Path(sys.argv[2])
target = json.loads(target_path.read_text())
existing = target.get("hooks", {})

# Preserve original file mode so atomic replace doesn't widen it.
try:
    orig_mode = stat.S_IMODE(os.stat(str(target_path)).st_mode)
except OSError:
    orig_mode = 0o600

added = 0
replaced = 0
removed_dup = 0
for event, groups in src_hooks.items():
    existing.setdefault(event, [])
    # Build map: anchor-script-name → list of (group_index, hook_index, scheme).
    # Multiple entries with the same script name (under different schemes) are
    # tracked separately so we can collapse duplicates.
    existing_anchor_map = collections.defaultdict(list)
    for gi, g in enumerate(existing[event]):
        for hi, h in enumerate(g.get("hooks", [])):
            k = anchor_key(h.get("command", ""))
            if k[0] == "anchor":
                existing_anchor_map[k[1]].append((gi, hi, k[2]))

    for grp in groups:
        grp_keys = {anchor_key(h["command"]) for h in grp.get("hooks", [])}
        anchor_names_in_grp = {k[1] for k in grp_keys if k[0] == "anchor"}
        if not anchor_names_in_grp:
            existing[event].append(grp)
            added += 1
            continue
        if anchor_names_in_grp.issubset(existing_anchor_map):
            our_scheme = next(iter(k[2] for k in grp_keys if k[0] == "anchor"), "")
            for name in anchor_names_in_grp:
                entries = existing_anchor_map[name]
                SCHEME_RANK = {"home": 0, "plugin": 1, "other-anchor": 2}
                if our_scheme == "home":
                    new_cmd = next(h["command"] for h in grp["hooks"]
                                   if anchor_key(h["command"])[1] == name)
                    entries_sorted = sorted(entries, key=lambda e: SCHEME_RANK.get(e[2], 99))
                    keeper_gi, keeper_hi, keeper_scheme = entries_sorted[0]
                    # v1.4.2: only auto-replace plugin→home when explicitly requested.
                    # Plugin hooks are owned by the plugin system; silently
                    # rewriting them is surprising. Without --replace-plugin-hooks
                    # we leave plugin entries alone and skip adding ours.
                    if keeper_scheme == "plugin" and not replace_plugin_hooks:
                        # Skip — plugin entry stays in place.
                        continue
                    if keeper_scheme != "home":
                        existing[event][keeper_gi]["hooks"][keeper_hi]["command"] = new_cmd
                        replaced += 1
                    for gi, hi, _ in entries_sorted[1:]:
                        existing[event][gi]["hooks"][hi]["_anchor_drop"] = True
                        removed_dup += 1
            continue
        existing[event].append(grp)
        added += 1

# Now actually drop the marked duplicate hook entries.
for event, groups in existing.items():
    new_groups = []
    for g in groups:
        kept = [h for h in g.get("hooks", []) if not h.pop("_anchor_drop", False)]
        if kept:
            g["hooks"] = kept
            new_groups.append(g)
    existing[event] = new_groups

target["hooks"] = existing
# Atomic write: tmp in same dir + os.replace.
fd, tmp = tempfile.mkstemp(prefix=target_path.name + ".", dir=str(target_path.parent))
try:
    with os.fdopen(fd, "w") as fh:
        fh.write(json.dumps(target, indent=2))
    os.chmod(tmp, orig_mode)  # preserve original mode (mkstemp defaults 0600)
    os.replace(tmp, str(target_path))
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise
parts = [f"merged {added} new"]
if replaced:
    parts.append(f"replaced {replaced} stale-path")
if removed_dup:
    parts.append(f"removed {removed_dup} duplicate")
print(f"    ({', '.join(parts)} hook entries)")
PYEOF
        echo "  ✓ Claude Code: hooks merged into settings.json (backup: $(basename "$BACKUP"))"
    else
        # Fresh install — write a settings.json containing only hooks.
        # Paths passed via sys.argv; atomic write (tmp + os.replace).
        python3 - "$SCRIPT_DIR/settings.hooks.json" "$CLAUDE_DIR/settings.json" <<'PYEOF'
import json, os, sys, tempfile
from pathlib import Path
src = json.loads(Path(sys.argv[1]).read_text())
src.pop('_comment', None)
src.pop('_optional_statusline', None)
target = Path(sys.argv[2])
fd, tmp = tempfile.mkstemp(prefix=target.name + ".", dir=str(target.parent))
try:
    with os.fdopen(fd, "w") as fh:
        fh.write(json.dumps(src, indent=2))
    os.chmod(tmp, 0o600)  # fresh install — restrictive default
    os.replace(tmp, str(target))
except Exception:
    try: os.unlink(tmp)
    except OSError: pass
    raise
PYEOF
        echo "  ✓ Claude Code: created ~/.claude/settings.json with hooks"
    fi
fi

# ---- 3. Codex CLI (if installed) ----
if command -v codex >/dev/null 2>&1 && [ -d "$CODEX_DIR" ]; then
    mkdir -p "$CODEX_DIR/skills/anchor/references/templates"
    mkdir -p "$CODEX_DIR/skills/anchor/scripts"
    cp "$SCRIPT_DIR/skills/anchor/SKILL.md" "$CODEX_DIR/skills/anchor/"
    cp "$SCRIPT_DIR/skills/anchor/references/"*.md "$CODEX_DIR/skills/anchor/references/"
    cp "$SCRIPT_DIR/skills/anchor/references/templates/"*.md "$CODEX_DIR/skills/anchor/references/templates/"
    cp "$SCRIPT_DIR/skills/anchor/scripts/"*.sh "$CODEX_DIR/skills/anchor/scripts/"
    cp "$SCRIPT_DIR/skills/anchor/scripts/"*.py "$CODEX_DIR/skills/anchor/scripts/"
    chmod +x "$CODEX_DIR/skills/anchor/scripts/"*.sh "$CODEX_DIR/skills/anchor/scripts/"*.py
    for cmd in lock pit scan "done" next recap init-claude-md status ship diff cleanup ec cost report save resume; do
        mkdir -p "$CODEX_DIR/skills/$cmd"
        cp "$SCRIPT_DIR/commands/$cmd.md" "$CODEX_DIR/skills/$cmd/SKILL.md"
    done
    echo "  ✓ Codex CLI: skill + 11 commands"
fi

echo ""
echo "Done. Try:"
echo "  /ec        — load the full skill"
echo "  /lock <task>  — anchor task scope before coding"
echo "  /done      — wrap-up checklist (lint + E2E + codex hint + CLAUDE.md writeback)"
echo ""
echo "Enable autonomous mode (Stop hook blocks until task list is complete):"
echo "  touch ~/.claude/.efficient-coding-autonomous"
if [ "$WITH_HOOKS" = "0" ]; then
    echo ""
    echo "(Skipped hooks — re-run without --no-hooks to enable them)"
fi

exit 0
