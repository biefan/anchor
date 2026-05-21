#!/bin/bash
# PreToolUse hook: block dangerous Bash commands by ec skill's "高代价动作" rule.
# Returns {"decision":"block","reason":"..."} for explicitly destructive patterns.
# Settings-level Bash deny rules cover rm -rf /* — this catches the rest.
#
# Approach:
#   1. Split the command on shell separators (;, &&, ||, |, \n) into sub-commands.
#   2. For each sub-command, find the FIRST actual program.
#      - If it's in SAFE_FIRST (echo/grep/cat/...), skip this segment (likely
#        carrying a dangerous-looking string as data, not as command).
#      - Otherwise, scan the segment against danger patterns.
#   3. Block on first hit with a clear reason.

# shellcheck source=./_log_event.sh
. "$(dirname "${BASH_SOURCE[0]}")/_log_event.sh"

EC_HOOK_INPUT="$(cat)" python3 - <<'PYEOF'
import json
import os
import re
import sys

try:
    data = json.loads(os.environ.get("EC_HOOK_INPUT", "") or "{}")
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

CHECKS = [
    (r"git\s+reset\s+--hard\b",
     "git reset --hard 不可逆，会丢失未提交改动"),
    (r"git\s+push\s+(-f(\s|$)|--force(\s|$)|--force-with-lease(\s|$))",
     "git push --force 会覆盖远端历史，影响所有协作者"),
    (r"\brm\s+-rf?\s+/(\s|$|[^a-zA-Z0-9_])",
     "rm -rf / 或子根目录是灾难性删除"),
    (r"\brm\s+-rf?\s+~(\s|$|/)",
     "rm -rf ~/ 会清空用户主目录"),
    (r"\brm\s+-rf?\s+\$HOME",
     "rm -rf $HOME 会清空主目录"),
    (r"\bsudo\s+rm\s+-rf?",
     "sudo rm -rf 是 root 级删除，极其危险"),
    (r"\bDROP\s+(TABLE|DATABASE|SCHEMA)\b",
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
    (r"\bcurl\s+.*\|\s*(ba)?sh\b",
     "curl ... | bash 执行未验证脚本——先看内容再执行"),
]


def first_program(segment: str) -> str:
    """Return the basename of the first actual command in a shell segment."""
    s = segment.lstrip()
    s = re.sub(r"^[\(\{]\s*", "", s)
    while re.match(r"^[A-Za-z_][A-Za-z0-9_]*=\S*\s+", s):
        s = re.sub(r"^[A-Za-z_][A-Za-z0-9_]*=\S*\s+", "", s)
    tok = s.split(maxsplit=1)[0] if s else ""
    return tok.rsplit("/", 1)[-1]


segments = re.split(r"(?:;|\n|&&|\|\||\|)", cmd)

for seg in segments:
    seg = seg.strip()
    if not seg:
        continue
    fp = first_program(seg)
    if fp in SAFE_FIRST:
        continue
    for pattern, msg in CHECKS:
        if re.search(pattern, seg, re.IGNORECASE):
            reason = (
                f"ec skill 的'高代价动作'规则拦截：\n\n"
                f"命令片段：{seg}\n"
                f"完整命令：{cmd}\n\n"
                f"原因：{msg}\n\n"
                "按规则，请先：\n"
                "1. 说清楚你要做什么 / 为什么 / 影响范围\n"
                "2. 等用户明确确认\n\n"
                "用户已明确授权时让用户说\"已确认，执行\"再回来跑。"
            )
            # Log block decision to a side-channel file (env var path) for the
            # bash wrapper to pick up after this python block ends.
            os.environ_log_block = (pattern, msg, seg[:120])
            try:
                with open(os.path.expanduser("~/.claude/.ec-last-pretool-block"), "w") as lf:
                    json.dump({"pattern": pattern, "msg": msg, "seg": seg[:120], "cmd": cmd[:300]}, lf)
            except Exception:
                pass
            print(json.dumps({"decision": "block", "reason": reason}))
            sys.exit(0)

sys.exit(0)
PYEOF

# After python exits: if it wrote a block-marker file, log the event.
if [ -f "$HOME/.claude/.ec-last-pretool-block" ]; then
    EC_LOG_event="pretool_blocked" \
    EC_LOG_pattern="$(python3 -c "import json; print(json.load(open('$HOME/.claude/.ec-last-pretool-block')).get('pattern',''))" 2>/dev/null)" \
    EC_LOG_msg="$(python3 -c "import json; print(json.load(open('$HOME/.claude/.ec-last-pretool-block')).get('msg',''))" 2>/dev/null)" \
    EC_LOG_seg="$(python3 -c "import json; print(json.load(open('$HOME/.claude/.ec-last-pretool-block')).get('seg',''))" 2>/dev/null)" \
    ec_log_event
    rm -f "$HOME/.claude/.ec-last-pretool-block"
fi
