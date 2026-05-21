#!/bin/bash
# PreToolUse hook: block dangerous Bash commands by ec skill's "高代价动作" rule.
# Returns {"decision":"block","reason":"..."} for explicitly destructive patterns.
# Settings-level Bash deny rules cover rm -rf /* — this catches the rest.
#
# Approach (v1.3.8 redesign — addresses 5 bypass classes found in audit):
#   1. Read hook JSON from a tmp file (NOT env var) — avoids ARG_MAX exec limit
#      that an attacker could trigger with a megabyte-sized command.
#   2. Two-layer scanning:
#      a. CROSS-SEGMENT (whole command): catches patterns that span pipes,
#         e.g. `curl ... | bash`, `wget ... | sh`.
#      b. PER-SEGMENT: split on ; | && || \n into sub-commands.
#         For each, also extract $(...) / <(...) / `...` substitution
#         contents as ADDITIONAL segments — closes the
#         `echo $(rm -rf /)` / `cat <(...)` SAFE_FIRST bypass.
#   3. SAFE_FIRST only skips a segment if the first program is safe AND that
#      segment has no embedded substitutions (otherwise we still scan inside).
#   4. Marker file is unique per invocation (mktemp) so concurrent hooks can't
#      overwrite each other's block-decision record.

# shellcheck source=./_log_event.sh
. "$(dirname "${BASH_SOURCE[0]}")/_log_event.sh"

# Per-invocation marker file (avoids the v1.3.7 shared-marker race).
BLOCK_MARKER="$(mktemp "/tmp/.ec-pretool-block.XXXXXX")"
INPUT_FILE="$(mktemp "/tmp/.ec-pretool-input.XXXXXX")"
# shellcheck disable=SC2064  # we want the trap to capture the path NOW, not on exit
trap "rm -f $BLOCK_MARKER $INPUT_FILE" EXIT

# Save hook stdin to tmp file. Stdin pipe doesn't compete with the heredoc below.
cat > "$INPUT_FILE"

EC_HOOK_INPUT_FILE="$INPUT_FILE" EC_BLOCK_MARKER="$BLOCK_MARKER" python3 - <<'PYEOF'
import json
import os
import re
import sys

try:
    with open(os.environ.get("EC_HOOK_INPUT_FILE", "/dev/null")) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

if data.get("tool_name") != "Bash":
    sys.exit(0)

cmd = data.get("tool_input", {}).get("command", "")
if not cmd:
    sys.exit(0)

SAFE_FIRST = {
    "echo", "printf", "cat", "less", "more", "head", "tail", "wc",
    "grep", "rg", "ag", "find", "ls", "ll", "tree", "stat", "file",
    "awk", "sed",
    "diff", "comm", "sort", "uniq", "tr", "cut", "paste", "column",
    "jq", "yq",
    "test", "[", "true", "false",
    "env", "which", "type", "command",
    "pwd", "id", "whoami", "date", "uname", "hostname",
}

# Cross-segment patterns: scan against the FULL command (not per-segment).
# These match shapes that span pipes/separators, like `curl X | bash`.
GLOBAL_CHECKS = [
    (r"\b(?:curl|wget|fetch)\b[^|;&\n]*\|\s*(?:ba|z|k|fi|t)?sh\b",
     "curl/wget ... | sh 执行未验证脚本——先看内容再执行"),
    (r"\b(?:curl|wget|fetch)\b[^|;&\n]*\|\s*(?:python|node|ruby|perl|lua)\d?\b",
     "curl/wget ... | <interpreter> 执行未验证脚本"),
]

# Per-segment patterns: applied to each sub-command after splitting.
SEGMENT_CHECKS = [
    # git reset --hard — allow git's global flags (-C / -c k=v / --git-dir=...)
    # AND allow flags between `reset` and `--hard`.
    (r"\bgit(?:\s+(?:-[CcP]\s+\S+|-c\s+[\w.]+=\S+|--git-dir=\S+|--work-tree=\S+))*\s+reset\s+(?:--?\S+\s+)*--hard\b",
     "git reset --hard 不可逆，会丢失未提交改动"),
    # git push --force — flags can be anywhere in this segment.
    (r"\bgit\b[^|;&]*?\bpush\b[^|;&]*?(?:\s-f\b|--force\b|--force-with-lease\b)",
     "git push --force 会覆盖远端历史，影响所有协作者"),
    # rm -rf <dangerous targets> — flags can interleave, support `--`,
    # `~`, `$HOME`, `${HOME}`, `/`, `/$word`, `/*`.
    (r"\brm\b(?:\s+(?:-[a-zA-Z]+|--[\w=-]+))*\s+(?:--\s+)?"
     r"(?:[~]|\$\{?HOME\}?|/(?:\s|$|\*|[a-zA-Z]+(?:\s|/|$)))",
     "rm 命令针对根目录、$HOME、~ 等关键路径——非常危险"),
    (r"\bsudo\b[^|;&]*\brm\b[^|;&]*?(?:-r|-rf)",
     "sudo rm -rf 是 root 级删除，极其危险"),
    (r"\bDROP\s+(?:TABLE|DATABASE|SCHEMA)\b",
     "SQL DROP 不可逆"),
    (r"\bTRUNCATE\s+TABLE\b",
     "TRUNCATE 会清空整表数据，不可逆"),
    (r"\bDELETE\s+FROM\s+.+\bWHERE\s+1\s*=\s*1\b",
     "DELETE FROM ... WHERE 1=1 等于清表"),
    (r"\bmkfs\.",
     "mkfs 会格式化分区"),
    (r"\bdd\s+.*of=/dev/",
     "dd 写入块设备会覆盖整个设备"),
    (r">\s*/dev/sd[a-z]",
     "重定向到 /dev/sdX 会覆盖原始磁盘"),
    (r"\bchmod\s+-R\s+777\b",
     "chmod -R 777 通常是安全反模式"),
]


def first_program(segment: str) -> str:
    """Return the basename of the first actual command in a shell segment."""
    s = segment.lstrip()
    s = re.sub(r"^[\(\{]\s*", "", s)
    while re.match(r"^[A-Za-z_][A-Za-z0-9_]*=\S*\s+", s):
        s = re.sub(r"^[A-Za-z_][A-Za-z0-9_]*=\S*\s+", "", s)
    tok = s.split(maxsplit=1)[0] if s else ""
    return tok.rsplit("/", 1)[-1]


def extract_substitutions(s):
    """Pull contents from $(...) / <(...) / `...` (one level, non-nested).

    Closes the v1.3.7 bypass where SAFE_FIRST would skip `echo $(rm -rf /)`
    because `echo` is in the safe list but `rm -rf /` lurks inside.
    """
    out = []
    # $(...) and <(...)
    for m in re.finditer(r"\$\(([^()]*)\)|<\(([^()]*)\)", s):
        inner = m.group(1) or m.group(2) or ""
        if inner.strip():
            out.append(inner)
    # `...`
    for m in re.finditer(r"`([^`]*)`", s):
        if m.group(1).strip():
            out.append(m.group(1))
    return out


def write_block_marker(pattern, msg, seg, cmd):
    try:
        marker = os.environ.get("EC_BLOCK_MARKER", "")
        if marker:
            with open(marker, "w") as lf:
                json.dump({"pattern": pattern, "msg": msg, "seg": seg[:120], "cmd": cmd[:300]}, lf)
    except Exception:
        pass


def emit_block(pattern, msg, seg, cmd):
    write_block_marker(pattern, msg, seg, cmd)
    reason = (
        "ec skill 的'高代价动作'规则拦截：\n\n"
        f"命令片段：{seg}\n"
        f"完整命令：{cmd[:500]}\n\n"
        f"原因：{msg}\n\n"
        "按规则，请先：\n"
        "1. 说清楚你要做什么 / 为什么 / 影响范围\n"
        "2. 等用户明确确认\n\n"
        "用户已明确授权时让用户说\"已确认，执行\"再回来跑。"
    )
    print(json.dumps({"decision": "block", "reason": reason}))
    sys.exit(0)


# 1. Cross-segment scan (whole cmd, catches pipe-to-shell etc.)
for pattern, msg in GLOBAL_CHECKS:
    if re.search(pattern, cmd, re.IGNORECASE):
        emit_block(pattern, msg, cmd[:120], cmd)

# 2. Per-segment scan, with substitution unpacking.
segments = re.split(r"(?:;|\n|&&|\|\||\|)", cmd)
to_scan = []
for seg in segments:
    seg = seg.strip()
    if not seg:
        continue
    fp = first_program(seg)
    subs = extract_substitutions(seg)
    # Always scan substitution bodies (regardless of SAFE_FIRST), because
    # `echo $(rm -rf /)` has fp=echo but the danger lives inside $(...).
    for inner in subs:
        to_scan.append(inner)
    if fp in SAFE_FIRST and not subs:
        # Pure safe command with no embedded substitution → skip outer segment.
        continue
    to_scan.append(seg)

for seg in to_scan:
    for pattern, msg in SEGMENT_CHECKS:
        if re.search(pattern, seg, re.IGNORECASE):
            emit_block(pattern, msg, seg[:120], cmd)

sys.exit(0)
PYEOF

# After python exits: if marker file is non-empty, log the event.
if [ -s "$BLOCK_MARKER" ]; then
    # Read all 3 fields with one Python invocation; tab-separated.
    IFS=$'\t' read -r EC_LOG_pattern EC_LOG_msg EC_LOG_seg < <(
        python3 - "$BLOCK_MARKER" <<'PYEOF' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    def clean(s): return (s or "").replace("\t", " ").replace("\n", " ")
    print(f"{clean(d.get('pattern',''))}\t{clean(d.get('msg',''))}\t{clean(d.get('seg',''))}")
except Exception:
    print("\t\t")
PYEOF
    )
    EC_LOG_event="pretool_blocked" \
    EC_LOG_pattern="$EC_LOG_pattern" \
    EC_LOG_msg="$EC_LOG_msg" \
    EC_LOG_seg="$EC_LOG_seg" \
    ec_log_event
fi
