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
echo "  ✓ Claude Code: skill + 11 commands"

# ---- 2. Claude Code hooks (auto-merge into settings.json) ----
if [ "$WITH_HOOKS" = "1" ]; then
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        BACKUP="$(mktemp "$CLAUDE_DIR/settings.json.bak.XXXXXX")"
        cp "$CLAUDE_DIR/settings.json" "$BACKUP"
        python3 - "$SCRIPT_DIR/settings.hooks.json" "$CLAUDE_DIR/settings.json" <<'PYEOF'
import fcntl, json, os, re, stat, sys, tempfile
from pathlib import Path

# Dedup keys: scheme-aware so we can distinguish a hook installed via the
# plugin marketplace path from one installed by ./install.sh.
ANCHOR_SCRIPT_PAT = re.compile(r"efficient-coding/scripts/([\w.-]+\.sh)")
PLUGIN_PATH_PAT = re.compile(r"\$\{?CLAUDE_PLUGIN_ROOT\}?")
HOME_PATH_PAT = re.compile(r"(?:\$\{?HOME\}?|~)/\.claude/skills/efficient-coding/")

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

# Lock the settings.json itself for read-modify-write. flock auto-releases
# at process exit. Concurrent installs / uninstalls will serialize here
# instead of stomping on each other.
lock_fp = open(str(target_path), "r+")
try:
    fcntl.flock(lock_fp.fileno(), fcntl.LOCK_EX)
except OSError:
    pass  # filesystem may not support flock — proceed best-effort

target = json.loads(target_path.read_text())
existing = target.get("hooks", {})

# Preserve original file mode so atomic replace doesn't widen it.
try:
    orig_mode = stat.S_IMODE(os.stat(str(target_path)).st_mode)
except OSError:
    orig_mode = 0o600

added = 0
replaced = 0
for event, groups in src_hooks.items():
    existing.setdefault(event, [])
    # Build map from anchor-script-name → (group_index, hook_index, scheme).
    existing_anchor_map = {}
    for gi, g in enumerate(existing[event]):
        for hi, h in enumerate(g.get("hooks", [])):
            k = anchor_key(h.get("command", ""))
            if k[0] == "anchor":
                existing_anchor_map[k[1]] = (gi, hi, k[2])

    for grp in groups:
        grp_keys = {anchor_key(h["command"]) for h in grp.get("hooks", [])}
        anchor_names_in_grp = {k[1] for k in grp_keys if k[0] == "anchor"}
        if not anchor_names_in_grp:
            existing[event].append(grp)
            added += 1
            continue
        # If every anchor script in this group is already present under any
        # scheme, decide based on scheme: if existing is plugin-scheme and
        # we're installing home-scheme via ./install.sh, replace the entries
        # so we don't leave the user with stale plugin paths.
        if anchor_names_in_grp.issubset(existing_anchor_map):
            our_scheme = next(iter(k[2] for k in grp_keys if k[0] == "anchor"), "")
            for name in anchor_names_in_grp:
                gi, hi, ex_scheme = existing_anchor_map[name]
                if our_scheme == "home" and ex_scheme == "plugin":
                    # Replace the existing hook entry with our home-path one.
                    new_cmd = next(h["command"] for h in grp["hooks"]
                                   if anchor_key(h["command"])[1] == name)
                    existing[event][gi]["hooks"][hi]["command"] = new_cmd
                    replaced += 1
            continue
        existing[event].append(grp)
        added += 1

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
if replaced:
    print(f"    (merged {added} new + replaced {replaced} stale-path hook entries)")
else:
    print(f"    (merged {added} new hook entries)")
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
    mkdir -p "$CODEX_DIR/skills/ec/references"
    mkdir -p "$CODEX_DIR/skills/ec/scripts"
    cp "$SCRIPT_DIR/skills/efficient-coding/SKILL.md" "$CODEX_DIR/skills/ec/"
    cp "$SCRIPT_DIR/skills/efficient-coding/references/"*.md "$CODEX_DIR/skills/ec/references/"
    cp "$SCRIPT_DIR/skills/efficient-coding/scripts/"*.sh "$CODEX_DIR/skills/ec/scripts/"
    chmod +x "$CODEX_DIR/skills/ec/scripts/"*.sh
    for cmd in lock pit scan "done" next recap init-claude-md status ship diff cleanup; do
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
