#!/bin/bash
# PreToolUse hook: block dangerous Bash commands by ec skill's "高代价动作" rule.
# Returns {"decision":"block","reason":"..."} for explicitly destructive patterns.
#
# v1.4.0 redesign (driven by codex adversarial-review pass 2):
#   - Uses shlex tokenization so quoting / r"m" / "$HOME" map to real argv tokens.
#   - Detects obfuscation patterns (ANSI-C hex/octal escapes, ${IFS} replacement,
#     unparseable shell) and refuses to evaluate — a hostile token-encoded command
#     gets blocked conservatively.
#   - Unwraps wrappers (env / command / sudo / exec / time / nice / unshare) per
#     command stage so `env rm -rf /` is recognized as rm, not env.
#   - Removes find / awk / sed / env / command from SAFE_FIRST because they can
#     execute sub-commands; adds explicit detection for find -exec, awk system(),
#     and decoder-to-shell pipelines (base64 -d | bash, etc.).
#   - Walks pipelines stage-by-stage matching basenames (so `curl x | /bin/bash`,
#     `curl x | env bash`, `curl x | tee log | bash` all block).
#   - Recursively extracts $(...) / <(...) / `...` with balanced-paren matching,
#     not the v1.3.8 one-level non-nested regex.
#   - Hook JSON via tmp file (avoids ARG_MAX); marker file per-invocation (mktemp).
#
# Limitations (documented in README — hook is "anti-instinct" not "anti-attacker"):
#   - Sufficiently obfuscated shell can always defeat any static analyzer. We
#     block obvious obfuscation rather than try to decode it.

# shellcheck source=./_log_event.sh
. "$(dirname "${BASH_SOURCE[0]}")/_log_event.sh"

BLOCK_MARKER="$(mktemp "/tmp/.ec-pretool-block.XXXXXX")"
INPUT_FILE="$(mktemp "/tmp/.ec-pretool-input.XXXXXX")"
# shellcheck disable=SC2064
trap "rm -f $BLOCK_MARKER $INPUT_FILE" EXIT

cat > "$INPUT_FILE"

EC_HOOK_INPUT_FILE="$INPUT_FILE" EC_BLOCK_MARKER="$BLOCK_MARKER" python3 - <<'PYEOF'
import json
import os
import re
import shlex
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


# --------------------------------------------------------------------------
# Layer 1: Obfuscation detection. If raw command shows signs of trying to hide
# what it does, refuse to evaluate. These patterns rarely appear in legitimate
# commands; an agent that needs them can be asked to rewrite plainly.
# --------------------------------------------------------------------------
OBFUSCATION_CHECKS = [
    (r"\$'\\x[0-9a-fA-F]{1,2}",
     "ANSI-C 十六进制转义 ($'\\x..') 常用于隐藏命令名 — 改成明文写法"),
    (r"\$'\\[0-9]{1,3}'?[^']",
     "ANSI-C 八进制转义 ($'\\NNN') 可隐藏命令名 — 改成明文"),
    (r"\$\{IFS[}%/-]",
     "${IFS} 替代空白通常是为了绕过静态分析 — 用空格"),
    (r"\$IFS\b",
     "$IFS 替代空白通常是绕过 — 用空格"),
    (r"\\x[0-9a-fA-F]{2}.*?\\x[0-9a-fA-F]{2}.*?\\x[0-9a-fA-F]{2}",
     "命令含多个十六进制转义序列 — 改成明文"),
]


# --------------------------------------------------------------------------
# Layer 2: pipeline + token analysis. Tokenize with shlex; if it fails, block.
# Walk each pipeline stage; for each stage strip env vars and wrappers, then
# check the real command against danger rules.
# --------------------------------------------------------------------------

# Programs that wrap another command — strip them to find the real argv0.
# `env -i`, `env -u VAR`, `env VAR=val`, `command -p`, `sudo -E`, etc.
WRAPPERS = {"env", "command", "sudo", "exec", "doas", "su",
            "time", "nice", "ionice", "unshare", "setpriv", "stdbuf"}

# Safe commands that can't realistically destroy state on their own.
# Removed since v1.4: env, command (wrappers — caught above);
# find, awk, sed (can spawn subcommands — handled by SUBCMD_CHECKS below).
SAFE_CMDS = {
    "echo", "printf", "cat", "less", "more", "head", "tail", "wc",
    "grep", "rg", "ag", "ls", "ll", "tree", "stat", "file",
    "diff", "comm", "sort", "uniq", "tr", "cut", "paste", "column",
    "jq", "yq",
    "test", "[", "true", "false",
    "which", "type",
    "pwd", "id", "whoami", "date", "uname", "hostname",
}

# Shell-like interpreters used as pipeline sinks.
SHELL_BASENAMES = {"sh", "bash", "dash", "ash", "zsh", "ksh", "fish", "tcsh"}
INTERPRETER_BASENAMES = {"python", "python2", "python3", "node", "nodejs",
                         "ruby", "perl", "lua", "php"}
DECODERS = {"base64", "openssl", "xxd", "uudecode", "tr"}


def basename(token):
    return token.rsplit("/", 1)[-1]


def strip_env_assignments_and_wrappers(tokens):
    """Skip VAR=val prefixes and wrapper invocations to find the real argv."""
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if not t:
            i += 1
            continue
        # VAR=VAL prefix
        if "=" in t and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
            continue
        # Wrappers
        if basename(t) in WRAPPERS:
            i += 1
            # Skip wrapper-specific flags. Be permissive: any -X / --X / VAR=val.
            while i < len(tokens):
                arg = tokens[i]
                if arg.startswith("-") or ("=" in arg and re.match(r"^[A-Za-z_]", arg)):
                    i += 1
                else:
                    break
            continue
        break
    return tokens[i:]


SEP_TOKENS = {"|", "||", "&&", ";", "&", "\n"}


def shlex_split_stages(cmd_str):
    """Tokenize cmd via shlex (quote-aware), then split tokens into stages on
    pipeline / sequence operators. Returns (list_of_stage_argvs, ok). When
    shlex fails (unbalanced quotes etc.), ok=False signals obfuscation.
    """
    try:
        tokens = shlex.split(cmd_str, posix=True)
    except ValueError:
        return None, False
    stages = [[]]
    for t in tokens:
        if t in SEP_TOKENS:
            if stages[-1]:
                stages.append([])
            continue
        stages[-1].append(t)
    return [s for s in stages if s], True


def extract_substitutions(s, depth=0):
    """Recursively pull command-substitution contents from a string.

    Handles nested $(...) and <(...) by balanced-paren matching.
    Returns a list of inner shell strings.
    """
    if depth > 5:  # paranoia: avoid pathological nesting
        return []
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "$" and i + 1 < len(s) and s[i + 1] == "(":
            end = _find_matching_paren(s, i + 1)
            if end > 0:
                inner = s[i + 2:end]
                if inner.strip():
                    out.append(inner)
                    out.extend(extract_substitutions(inner, depth + 1))
                i = end + 1
                continue
        if c == "<" and i + 1 < len(s) and s[i + 1] == "(":
            end = _find_matching_paren(s, i + 1)
            if end > 0:
                inner = s[i + 2:end]
                if inner.strip():
                    out.append(inner)
                    out.extend(extract_substitutions(inner, depth + 1))
                i = end + 1
                continue
        if c == "`":
            j = s.find("`", i + 1)
            if j > 0:
                inner = s[i + 1:j]
                if inner.strip():
                    out.append(inner)
                    out.extend(extract_substitutions(inner, depth + 1))
                i = j + 1
                continue
        i += 1
    return out


def _find_matching_paren(s, open_idx):
    """Find index of `)` matching the `(` at open_idx. -1 if unbalanced."""
    depth = 0
    i = open_idx
    while i < len(s):
        if s[i] == "(":
            depth += 1
        elif s[i] == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


# Dangerous patterns scanned against the **real argv** (post-tokenize, post-unwrap).
# Each rule gets the argv list; returns (msg) or None.
def check_rm(argv):
    if not argv or basename(argv[0]) != "rm":
        return None
    # rm + -rf + dangerous target
    has_recursive = False
    has_force = False
    targets = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--":
            i += 1
            targets.extend(argv[i:])
            break
        if a.startswith("-") and not a.startswith("--"):
            if "r" in a.lower() or "R" in a:
                has_recursive = True
            if "f" in a:
                has_force = True
            i += 1
            continue
        if a.startswith("--"):
            i += 1
            continue
        targets.append(a)
        i += 1
    if not has_recursive:
        return None
    # Bare root.
    BARE_ROOT = re.compile(r"^/$")
    # Bare critical top-level dir (e.g. `/etc`, `/tmp`, `/var`) — wiping a
    # whole system dir even if it's /tmp is destructive enough to block.
    DANGEROUS_BARE = re.compile(
        r"^/(?:etc|var|usr|bin|sbin|lib|lib64|opt|root|boot|home|dev|proc|sys|run|srv|tmp|mnt|media)/?$"
    )
    # Children inside critical dirs — `/etc/passwd`, `/var/log/...` — block.
    # /tmp/<X> is the deliberate exception (normal cleanup of user-tmp files).
    DANGEROUS_CHILDREN = re.compile(
        r"^/(?:etc|var|usr|bin|sbin|lib|lib64|opt|root|boot|home|dev|proc|sys|run|srv|mnt|media)(?:/.*)$"
    )
    # $HOME / ~ / $PWD and any child.
    HOME_VARS = re.compile(r"^(?:~|\$\{?HOME\}?|\$\{?PWD\}?)(?:/.*)?$")
    # Substitution / placeholder / variable expansion — unknown expansion is dangerous.
    UNKNOWN_TARGETS = re.compile(r"(?:\{\}|\$\(|`|\$\{|\$\*|\$@)")
    for t in targets:
        if BARE_ROOT.match(t) or DANGEROUS_BARE.match(t) or DANGEROUS_CHILDREN.match(t) or HOME_VARS.match(t):
            return f"rm -rf 针对危险目标 {t!r} — 不可逆"
        if UNKNOWN_TARGETS.search(t):
            return f"rm -rf 针对动态 target {t!r}（substitution/placeholder）— 展开后可能任意"
    return None


def check_git_reset_hard(argv):
    if not argv or basename(argv[0]) != "git":
        return None
    # Skip git global flags to find the subcommand
    i = 1
    while i < len(argv):
        a = argv[i]
        if a in ("-C", "-c", "-P", "--git-dir", "--work-tree", "--namespace",
                 "--config-env", "--exec-path"):
            # Two-arg flag form: skip flag + value
            i += 2
            continue
        if a.startswith("--git-dir=") or a.startswith("--work-tree="):
            i += 1
            continue
        if a.startswith("-c") and "=" in a:
            i += 1
            continue
        if a.startswith("-"):
            i += 1
            continue
        break
    if i >= len(argv) or argv[i] != "reset":
        return None
    # Look for --hard anywhere after `reset`
    for a in argv[i + 1:]:
        if a == "--hard":
            return "git hard-reset 不可逆 — 会丢未提交改动"
    return None


def check_git_push_force(argv):
    if not argv or basename(argv[0]) != "git":
        return None
    # Skip global flags
    i = 1
    while i < len(argv) and argv[i].startswith("-"):
        if argv[i] in ("-C", "-c", "--git-dir", "--work-tree"):
            i += 2
        else:
            i += 1
    if i >= len(argv) or argv[i] != "push":
        return None
    rest = argv[i + 1:]
    # --force / -f / --force-with-lease anywhere
    for a in rest:
        if a in ("-f", "--force") or a.startswith("--force-with-lease"):
            return "git push --force 会覆盖远端历史"
    # Refspec with + prefix (force update)
    for a in rest:
        if not a.startswith("-") and a.startswith("+"):
            return f"git push 含强制 refspec ({a}) — 等同 --force"
    # --delete <branch>
    if "--delete" in rest or "-d" in rest:
        return "git push --delete 会删远端分支"
    return None


def check_sql_destroy(argv):
    joined = " ".join(argv).upper()
    if re.search(r"\bDROP\s+(TABLE|DATABASE|SCHEMA)\b", joined):
        return "SQL DROP 不可逆"
    if re.search(r"\bTRUNCATE\s+TABLE\b", joined):
        return "SQL TRUNCATE 不可逆"
    if re.search(r"\bDELETE\s+FROM\s+\S+\s+WHERE\s+1\s*=\s*1\b", joined):
        return "DELETE FROM ... WHERE 1=1 等于清表"
    return None


def check_disk_ops(argv):
    if not argv:
        return None
    cmd0 = basename(argv[0])
    if cmd0.startswith("mkfs."):
        return "mkfs 会格式化分区"
    if cmd0 == "dd":
        for a in argv[1:]:
            if a.startswith("of=/dev/"):
                return "dd 写入块设备会覆盖整个设备"
    if cmd0 == "chmod" and len(argv) >= 3 and argv[1] in ("-R", "-Rf", "-fR"):
        if any(a == "777" or a.endswith("=777") for a in argv[2:]):
            return "chmod -R 777 是安全反模式"
    return None


def check_redirect_to_device(stage_str):
    if re.search(r">\s*/dev/sd[a-z]\b", stage_str):
        return "重定向到 /dev/sdX 会覆盖原始磁盘"
    return None


def check_find_exec(argv):
    """find ... -exec rm -rf {} \\; bypass."""
    if not argv or basename(argv[0]) != "find":
        return None
    # find sub-commands that are inherently destructive — always block.
    DESTRUCTIVE_SUBCMDS = {"rm", "rmdir", "shred", "mv", "dd", "mkfs", "chown"}
    for i, a in enumerate(argv):
        if a in ("-exec", "-execdir", "-ok", "-okdir"):
            # The next tokens until \; or + form the sub-command.
            sub = []
            for j in range(i + 1, len(argv)):
                if argv[j] in (";", "+", "\\;"):
                    break
                sub.append(argv[j])
            if sub:
                sub_cmd = basename(sub[0])
                if sub_cmd in DESTRUCTIVE_SUBCMDS:
                    return f"find -exec 调用破坏性命令 {sub_cmd!r} — 范围由 find 决定，易失控"
                # Recursively check the sub-command for nested patterns.
                msg = scan_argv(sub, sub_check=True)
                if msg:
                    return f"find -exec 嵌入危险命令: {msg}"
        if a == "-delete":
            return "find -delete 删除匹配文件 — 范围易失控"
    return None


def check_awk_system(argv):
    if not argv or basename(argv[0]) not in {"awk", "gawk", "mawk", "nawk"}:
        return None
    program = " ".join(argv[1:])
    if re.search(r"\bsystem\s*\(", program):
        return "awk system() 调用 shell — 等同 shell injection vector"
    if re.search(r'\|\s*(?:"|\')?\s*(?:ba)?sh\b', program):
        return "awk getline | sh 调用 shell — 等同 shell injection vector"
    return None


def check_sed_e(argv):
    if not argv or basename(argv[0]) != "sed":
        return None
    # -e 'X e cmd' or '... e cmd' executes shell
    program = " ".join(argv[1:])
    if re.search(r"['\"]\s*\d*\s*e\s+", program):
        return "sed e 修饰符执行 shell — 等同 shell injection vector"
    return None


def check_xargs(argv):
    if not argv or basename(argv[0]) != "xargs":
        return None
    # xargs invokes whatever follows it — check the wrapped command.
    # Find arg after flags.
    i = 1
    while i < len(argv):
        a = argv[i]
        if a.startswith("-"):
            # Some xargs flags take values
            if a in ("-I", "-J", "-L", "-n", "-P", "-s", "-E"):
                i += 2
            elif a.startswith("--") and "=" not in a and a in ("--max-args",):
                i += 2
            else:
                i += 1
            continue
        break
    if i < len(argv):
        msg = scan_argv(argv[i:], sub_check=True)
        if msg:
            return f"xargs 嵌入危险命令: {msg}"
    return None


# Main scan: given a real (unwrapped) argv, return blocking msg or None.
def scan_argv(argv, sub_check=False):
    if not argv:
        return None
    for checker in (check_rm, check_git_reset_hard, check_git_push_force,
                    check_sql_destroy, check_disk_ops,
                    check_find_exec, check_awk_system, check_sed_e, check_xargs):
        msg = checker(argv)
        if msg:
            return msg
    # sudo wrapper around rm is already covered by check_rm post-unwrap.
    return None


def write_block_marker(reason_summary, msg, evidence, cmd):
    try:
        marker = os.environ.get("EC_BLOCK_MARKER", "")
        if marker:
            with open(marker, "w") as lf:
                json.dump({"pattern": reason_summary, "msg": msg, "seg": evidence[:120], "cmd": cmd[:300]}, lf)
    except Exception:
        pass


def emit_block(reason_summary, msg, evidence, cmd_str):
    write_block_marker(reason_summary, msg, evidence, cmd_str)
    reason = (
        "ec skill 的'高代价动作'规则拦截：\n\n"
        f"证据：{evidence[:200]}\n"
        f"原因：{msg}\n"
        f"完整命令：{cmd_str[:400]}\n\n"
        "按规则，请先：\n"
        "1. 说清楚要做什么 / 为什么 / 影响范围\n"
        "2. 等用户明确确认\n\n"
        "用户已明确授权时让用户说\"已确认，执行\"再回来跑。"
    )
    print(json.dumps({"decision": "block", "reason": reason}))
    sys.exit(0)


# --------------- Layer 1: Obfuscation ---------------
for pat, msg in OBFUSCATION_CHECKS:
    if re.search(pat, cmd):
        emit_block("obfuscation", msg, cmd[:200], cmd)


# --------------- Pipeline-level checks (cross-stage) ---------------
# Use quote-aware shlex tokenization so a literal `|` inside quotes
# (e.g. `printf 'curl x | bash'`) doesn't fake a pipeline.
def shlex_pipeline_stages(cmd_str):
    """Tokenize whole cmd; split on `|` tokens (which are unquoted by shlex).

    Returns list[list[str]] of stage-argv. None if shlex couldn't parse.
    """
    try:
        tokens = shlex.split(cmd_str, posix=True)
    except ValueError:
        return None
    stages = [[]]
    for t in tokens:
        if t == "|":
            stages.append([])
        else:
            stages[-1].append(t)
    return [s for s in stages if s]


pipeline = shlex_pipeline_stages(cmd)
if pipeline and len(pipeline) >= 2:
    stage_bases = []
    for stage_argv in pipeline:
        unwrapped = strip_env_assignments_and_wrappers(stage_argv)
        b = basename(unwrapped[0]) if unwrapped else ""
        stage_bases.append(b)

    has_fetcher = any(b in {"curl", "wget", "fetch"} for b in stage_bases)
    has_decoder = any(b in DECODERS for b in stage_bases)
    has_shell_sink = any(b in SHELL_BASENAMES | INTERPRETER_BASENAMES
                         for b in stage_bases)

    if has_shell_sink and (has_fetcher or has_decoder):
        kind = "fetcher" if has_fetcher else "decoder"
        emit_block("pipe-to-shell",
                   f"{kind} | shell 模式 — 远程 / 解码后内容直接进 shell 执行",
                   " | ".join(stage_bases), cmd)


# --------------- Per-stage tokenized scan ---------------
# Redirect to disk device — regex on raw cmd (redirect target rarely quoted)
msg = check_redirect_to_device(cmd)
if msg:
    emit_block("disk-redirect", msg, cmd[:120], cmd)

stages, ok = shlex_split_stages(cmd)
if not ok:
    emit_block("shlex-parse-failed",
               "命令无法 shell-tokenize — 可能是引号 / 转义 obfuscation",
               cmd[:120], cmd)

checked = set()
for stage_argv in stages or []:
    # Strip env-prefix VAR=val and wrapper invocations.
    real = strip_env_assignments_and_wrappers(stage_argv)
    if not real:
        continue

    cmd0 = basename(real[0])
    if cmd0 in SAFE_CMDS:
        continue  # Safe top-level command (substitution bodies handled below)

    evidence = " ".join(real[:6])
    if evidence in checked:
        continue
    checked.add(evidence)
    msg = scan_argv(real)
    if msg:
        emit_block(f"argv:{cmd0}", msg, evidence, cmd)


# --------------- Recursive substitution bodies ---------------
for body in extract_substitutions(cmd):
    body_stages, body_ok = shlex_split_stages(body)
    if not body_ok:
        # Couldn't parse the substitution body — treat as obfuscation.
        emit_block("substitution-parse-failed",
                   "命令替换体无法 tokenize — 可能藏了 obfuscation",
                   body[:120], cmd)
    for stage_argv in body_stages or []:
        real = strip_env_assignments_and_wrappers(stage_argv)
        if not real:
            continue
        msg = scan_argv(real)
        if msg:
            emit_block("substitution-body",
                       f"嵌入的子命令含危险操作: {msg}",
                       " ".join(stage_argv[:6]), cmd)

sys.exit(0)
PYEOF

# After python exits: if marker file is non-empty, log the event.
if [ -s "$BLOCK_MARKER" ]; then
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
