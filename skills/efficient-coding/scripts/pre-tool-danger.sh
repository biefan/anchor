#!/bin/bash
# PreToolUse hook: block dangerous Bash commands by ec skill's "高代价动作" rule.
# v1.4.3: set -e + fail-closed if mktemp can't create marker files
set -e
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

# G7: fail-closed if /tmp isn't writable — block with explicit reason rather
# than silently allowing the command through.
if ! BLOCK_MARKER="$(mktemp "/tmp/.ec-pretool-block.XXXXXX" 2>/dev/null)"; then
    printf '%s' '{"decision":"block","reason":"ec PreToolUse hook 无法创建 /tmp 标记文件 — fail-closed。请确认 /tmp 可写后重试，或临时禁用 hook。"}'
    exit 0
fi
if ! INPUT_FILE="$(mktemp "/tmp/.ec-pretool-input.XXXXXX" 2>/dev/null)"; then
    rm -f "$BLOCK_MARKER"
    printf '%s' '{"decision":"block","reason":"ec PreToolUse hook 无法创建 /tmp 输入文件 — fail-closed。"}'
    exit 0
fi
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
    # argv0 concatenation: $'r'$'m' / r${x:-}m and similar.
    (r"^\s*(?:\$'[^']*'){2,}",
     "命令以多个 $'...' 片段开头拼接 — 通常是 obfuscation"),
    (r"^\s*[A-Za-z]?\$\{[A-Za-z_]+(?::-[^}]*)?\}[A-Za-z]+",
     "命令开头含 ${VAR:-...} 与字母拼接 — 通常是 obfuscation"),
    # D1: variable indirection — `x=rm; $x -rf /`, `cmd=$(...); $cmd ...`.
    # If the same line assigns VAR=value then uses $VAR (or ${VAR}) as an
    # argv0-position token, it's dynamic command dispatch.
    (r"\b([A-Za-z_]\w*)=\S+\s*[;\n&]+\s*[\"']?\$\{?\1\}?\b",
     "command 间接通过变量调度（VAR=...; $VAR ...） — 不可预知，按 obfuscation 处理"),
    # D5: backslash-prefix alias bypass — `\rm -rf /`, `\cp -f /` etc.
    # The backslash defeats shell aliases (e.g. `alias rm='rm -i'`).
    (r"(?:^|[\s;&|])\\[a-zA-Z]\w*\s+-",
     "命令前置反斜杠（\\\\cmd 形式）通常用于绕过 shell alias — 用明文"),
]


# --------------------------------------------------------------------------
# Layer 2: pipeline + token analysis. Tokenize with shlex; if it fails, block.
# Walk each pipeline stage; for each stage strip env vars and wrappers, then
# check the real command against danger rules.
# --------------------------------------------------------------------------

# Programs that wrap another command — strip them to find the real argv0.
# Per-wrapper schema in WRAPPER_VALUE_FLAGS.
#
# v1.4.2: `su` removed from WRAPPERS (so `check_shell_dash_c` sees it first
# and recurses into its -c argument). Added flock/nohup/setsid/runuser/script
# as additional command-runner wrappers.
# v1.4.2: also removed taskset, chrt, parallel, env-with-S from generic WRAPPER
# unwrap because they have positional-arg semantics or shell-string values
# that need dedicated checkers (check_taskset_chrt, check_parallel, check_env_dash_s).
# `env` stays in WRAPPERS for the common `env VAR=val cmd` shape; check_env_dash_s
# runs in phase 1 before the unwrap to catch `env -S "..."` separately.
WRAPPERS = {"env", "command", "sudo", "exec", "doas",
            "time", "nice", "ionice", "unshare", "setpriv", "stdbuf",
            "timeout",
            "flock", "nohup", "setsid", "runuser", "script"}

WRAPPER_VALUE_FLAGS = {
    # sudo: codex r6 — also long forms (--user, --group, --prompt, etc.)
    "sudo": {"-u", "--user", "-g", "--group", "-p", "--prompt",
             "-r", "--role", "-t", "--type", "-C", "-T", "-D",
             "--close-from", "--chdir", "--host"},
    # env: codex r6 added -C (--chdir). -S handled separately.
    "env": {"-u", "--unset", "-C", "--chdir"},
    "command": set(),
    "exec": {"-a"},
    "doas": {"-u", "-C"},
    "timeout": {"-s", "--signal", "-k", "--kill-after"},
    "taskset": {"-c", "--cpu-list"},
    "chrt": set(),
    "nice": {"-n", "--adjustment"},
    "ionice": {"-c", "-n", "-p", "--class", "--classdata", "--pid"},
    "unshare": set(),
    # setpriv: codex r6 — --reuid/--regid/--init-groups etc. all take values.
    "setpriv": {"--reuid", "--regid", "--init-groups", "--inh-caps",
                "--bounding-set", "--securebits", "--selinux-label",
                "--apparmor-profile", "--reset-env", "--ambient-caps"},
    "stdbuf": {"-i", "--input", "-o", "--output", "-e", "--error"},
    "parallel": {"-j", "--jobs", "-N", "--max-args", "-n", "-L", "--max-replace-args"},
    "time": {"-o", "--output", "-f", "--format"},
    "flock": {"-E", "--conflict-exit-code", "-w", "--timeout"},
    "nohup": set(),
    "setsid": {"-w", "--wait"},
    # runuser: --session-command takes a shell string (handled via check_shell_dash_c).
    # Listed here so we know to PARSE it, but check_shell_dash_c sees it before unwrap.
    "runuser": {"-u", "--user", "-g", "--group", "-G", "--supp-group",
                "-s", "--shell"},
    "script": {"-a", "-f", "-q", "-t",
               "--quiet", "--append", "--timing"},
    # watch: codex r6 — schema was missing entirely.
    "watch": {"-n", "--interval", "-d", "--differences",
              "-p", "--precise"},
}

# Wrappers whose first POSITIONAL argument(s) is NOT the command.
WRAPPERS_WITH_LEADING_POSITIONAL = {
    "timeout": 1,   # duration
    "chrt": 2,      # policy, priority (only without -p)
    "flock": 1,     # lockfile (only without -c)
}

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
    """Skip VAR=val prefixes and wrapper invocations to find the real argv.

    Also strips leading `(` / `{` group-syntax tokens and trailing `)` / `}`
    so a subshell `(rm -rf /)` or group `{ rm -rf /; }` doesn't hide the rm.

    Recursively unwraps nested wrappers (`sudo env command rm` → `rm`).
    """
    # D2/D3: strip group/subshell delimiters at the boundaries.
    while tokens and tokens[0] in ("(", "{"):
        tokens = tokens[1:]
    while tokens and tokens[-1] in (")", "}", ";"):
        tokens = tokens[:-1]

    i = 0
    while i < len(tokens):
        if i >= len(tokens):
            break
        t = tokens[i]
        if not t:
            i += 1
            continue
        # VAR=VAL prefix (only at the very start or after env)
        if "=" in t and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
            continue
        # Wrappers
        wname = basename(t)
        if wname in WRAPPERS:
            # Special case: env -S "shell string" — `-S` makes env split a
            # shell-string and execute. Don't unwrap env so check_env_dash_s sees it.
            if wname == "env" and any(
                (a == "-S" or a.startswith("-S"))
                for a in tokens[i + 1:]
            ):
                break
            # G2/v1.4.4 + B1/v1.4.5: shell-string-taking wrappers — don't
            # unwrap so check_shell_dash_c sees them. doas added in v1.4.5
            # for symmetry with runuser/su (was relying on check_rm post-unwrap;
            # explicit safeguard is more defense-in-depth).
            SHELL_STRING_FLAGS_INLINE = {"-c", "--command", "--session-command"}
            if wname in ("flock", "script", "runuser", "doas", "su") and any(
                a in SHELL_STRING_FLAGS_INLINE
                or a.startswith("--command=")
                or a.startswith("--session-command=")
                for a in tokens[i + 1:]
            ):
                break
            i += 1
            value_flags = WRAPPER_VALUE_FLAGS.get(wname, set())
            # Skip option flags
            while i < len(tokens):
                arg = tokens[i]
                if arg == "--":
                    i += 1
                    break
                if arg.startswith("--") and "=" in arg:
                    i += 1
                    continue
                if arg in value_flags:
                    i += 2
                    continue
                if arg.startswith("-") and arg != "-":
                    i += 1
                    continue
                if "=" in arg and re.match(r"^[A-Za-z_]", arg) and wname == "env":
                    i += 1
                    continue
                break
            for _ in range(WRAPPERS_WITH_LEADING_POSITIONAL.get(wname, 0)):
                if i < len(tokens):
                    i += 1
            continue
        break
    return tokens[i:]


SEP_TOKENS = {"|", "||", "|&", "&&", ";", ";;", "&", "\n", ">", ">>", ">|", "<", "<<"}
# `<<<` (here-string) is special: the next token is the input to the *previous*
# pipeline command, not a continuation. We handle it explicitly in the stage
# walker below so the here-string content gets scanned as inner shell.
# `|&` is bash shorthand for `2>&1 |` — same pipeline semantics, must split.
# `>|` is bash noclobber-override write — same risk class as `>`.


def _tokenize_with_punctuation(cmd_str):
    """shlex tokenization that recognizes |, ;, &, etc. as separate tokens
    even WITHOUT surrounding whitespace.

    Default `shlex.split` does NOT split on punctuation, so `curl x|bash`
    tokenizes as `['curl', 'x|bash']` — completely missing the pipeline.
    `punctuation_chars=True` fixes that: it treats `();<>|&` as standalone
    tokens, plus multi-char `&&`/`||`/`;;` etc.
    """
    lex = shlex.shlex(cmd_str, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    return list(lex)


def shlex_split_stages(cmd_str):
    """Tokenize cmd via shlex with punctuation awareness, then split tokens
    into stages on pipeline / sequence operators. Returns (list_of_stage_argvs,
    ok). When shlex fails (unbalanced quotes etc.), ok=False signals
    obfuscation.

    v1.4.3: heredoc (`<<EOF`/`<<-EOF`) body is now also extracted via raw cmd
    pre-processing in scan_heredocs(); this function still handles `<<<` and
    plain file redirections.
    """
    try:
        tokens = _tokenize_with_punctuation(cmd_str)
    except ValueError:
        return None, False
    stages = [[]]
    skip_next = False
    here_string_next = False
    for t in tokens:
        if skip_next:
            skip_next = False
            continue
        if here_string_next:
            here_string_next = False
            try:
                inner_tokens = _tokenize_with_punctuation(t)
                stages.append(inner_tokens)
            except ValueError:
                stages.append([t])
            continue
        if t == "<<<":
            here_string_next = True
            continue
        if t in SEP_TOKENS:
            if stages[-1]:
                stages.append([])
            continue
        if t in {">", "<", ">>", "<<"}:
            skip_next = True
            continue
        stages[-1].append(t)
    return [s for s in stages if s], True


def extract_heredocs(cmd_str):
    """G1: Pull `<<EOF...EOF` / `<<-EOF...EOF` heredoc bodies out of the raw cmd
    so they can be scanned as inner shell.

    Returns list of body strings. The body of `bash <<EOF\\nrm -rf /\\nEOF`
    is `rm -rf /`.
    """
    out = []
    # Match << or <<- followed by optional quotes + delimiter, then capture
    # everything until a line equal to the delimiter (possibly indented for <<-).
    for m in re.finditer(r"<<-?\s*['\"]?(\w+)['\"]?\n(.*?)\n\s*\1\b", cmd_str, re.DOTALL):
        body = m.group(2).strip()
        if body:
            out.append(body)
    return out


def extract_substitutions(s, depth=0):
    """Recursively pull command-substitution contents from a string.

    Handles `$()`, `<()` (input process substitution), `>()` (output process
    substitution — E4 fix), and `` `...` `` by balanced-paren matching.
    """
    if depth > 5:
        return []
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        # $(...)
        if c == "$" and i + 1 < len(s) and s[i + 1] == "(":
            end = _find_matching_paren(s, i + 1)
            if end > 0:
                inner = s[i + 2:end]
                if inner.strip():
                    out.append(inner)
                    out.extend(extract_substitutions(inner, depth + 1))
                i = end + 1
                continue
        # <(...) / >(...) — both are process substitution. The body is an
        # actual command. v1.4.1 only handled `<(`; >() is the same risk class.
        if c in ("<", ">") and i + 1 < len(s) and s[i + 1] == "(":
            end = _find_matching_paren(s, i + 1)
            if end > 0:
                inner = s[i + 2:end]
                if inner.strip():
                    out.append(inner)
                    out.extend(extract_substitutions(inner, depth + 1))
                i = end + 1
                continue
        # `...`
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
    """Find index of `)` matching the `(` at open_idx, ignoring parens inside
    single/double-quoted regions. -1 if unbalanced.
    """
    depth = 0
    i = open_idx
    in_single = False
    in_double = False
    while i < len(s):
        c = s[i]
        if not in_single and not in_double:
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return i
            elif c == "'":
                in_single = True
            elif c == '"':
                in_double = True
        elif in_single:
            if c == "'":
                in_single = False
        elif in_double:
            if c == '"':
                in_double = False
            elif c == "\\" and i + 1 < len(s):
                i += 1  # skip escaped char inside double quotes
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
    BARE_ROOT = re.compile(r"^/$")
    DANGEROUS_BARE = re.compile(
        r"^/(?:etc|var|usr|bin|sbin|lib|lib64|opt|root|boot|home|dev|proc|sys|run|srv|tmp|mnt|media)/?$"
    )
    DANGEROUS_CHILDREN = re.compile(
        r"^/(?:etc|var|usr|bin|sbin|lib|lib64|opt|root|boot|home|dev|proc|sys|run|srv|mnt|media)(?:/.*)$"
    )
    HOME_VARS = re.compile(r"^(?:~|\$\{?HOME\}?|\$\{?PWD\}?)(?:/.*)?$")
    # Substitution / placeholder / variable / glob / brace expansion.
    # E1: any absolute path with shell metacharacters (* ? [ ] { }) is unknown
    # — globs can match into critical dirs (/e* → /etc).
    UNKNOWN_TARGETS = re.compile(
        r"(?:\{\}|\$\(|`|\$\{|\$\*|\$@|\$[A-Za-z_]\w*"
        r"|^/?\*|/\*(?:$|/)|/\?|/\[[^\]]+\]|/\{[^}]+\}"
        r"|^/[^/\s]*[*?\[\]{}]|/[^/]*[*?][^/]*(?:$|/))"
    )

    # E2: normalize static absolute paths so `/tmp/../etc` is evaluated as
    # `/etc` — falls under DANGEROUS_BARE.
    def normalize(t):
        # Only normalize purely-static absolute paths (no $, no glob meta).
        if t.startswith("/") and not re.search(r"[$`{}*?\[\]]", t):
            try:
                return os.path.normpath(t)
            except Exception:
                return t
        return t

    for raw_t in targets:
        t = normalize(raw_t)
        if BARE_ROOT.match(t) or DANGEROUS_BARE.match(t) or DANGEROUS_CHILDREN.match(t) or HOME_VARS.match(t):
            return f"rm -rf 针对危险目标 {t!r}（原始 {raw_t!r}） — 不可逆"
        if UNKNOWN_TARGETS.search(t):
            return f"rm -rf 针对动态 target {t!r}（substitution/glob/placeholder）— 展开后可能任意"
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


def check_git_destructive(argv):
    """git clean -fd[x] / git branch -D — force-deletes that lose work.

    git clean -fdx wipes untracked files AND files in .gitignore.
    git branch -D force-deletes branches (unmerged work lost).
    """
    if not argv or basename(argv[0]) != "git":
        return None
    # Skip git global flags
    i = 1
    while i < len(argv):
        a = argv[i]
        if a in ("-C", "-c", "-P", "--git-dir", "--work-tree", "--namespace",
                 "--config-env", "--exec-path"):
            i += 2
            continue
        if a.startswith("--git-dir=") or a.startswith("--work-tree="):
            i += 1
            continue
        if a.startswith("-"):
            i += 1
            continue
        break
    if i >= len(argv):
        return None
    sub = argv[i]
    rest = argv[i + 1:]
    if sub == "clean":
        has_force = any("f" in flag for flag in rest if flag.startswith("-") and not flag.startswith("--"))
        has_force = has_force or "--force" in rest
        has_recursive = any("d" in flag for flag in rest if flag.startswith("-") and not flag.startswith("--"))
        # `-fdx` or `-fd` with no specific path = wipe whole tree
        if has_force and has_recursive:
            # Allow when an explicit non-dot path argument is given
            paths = [a for a in rest if not a.startswith("-")]
            if not paths:
                return "git clean -fd wipes ALL untracked files in working tree — 范围不可逆"
            # Wiping CWD or .gitignore-tracked files is destructive
            if any("x" in flag for flag in rest if flag.startswith("-") and not flag.startswith("--")):
                return "git clean -fdx 同时清掉 .gitignore 内文件 — 范围不可逆"
    if sub == "branch":
        if "-D" in rest:
            return "git branch -D 强制删除分支（可能丢未合并工作）"
    return None


SUSPICIOUS_GIT_CONFIG_KEYS = {
    "core.sshcommand", "core.editor", "core.pager", "core.askpass",
    "gpg.program", "credential.helper", "diff.external", "merge.external",
}


def check_git_config_injection(argv):
    """git -c core.sshCommand='ssh ... rm -rf /' clone ... — git config inj.

    The -c value can pin sshCommand / core.editor / gpg.program etc. to a
    shell-runnable that executes attacker code on git operations.
    """
    if not argv or basename(argv[0]) != "git":
        return None
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "-c" and i + 1 < len(argv):
            kv = argv[i + 1]
            i += 2
            if "=" not in kv:
                continue
            key, _, value = kv.partition("=")
            key_lower = key.lower()
            # filter.<name>.{smudge,clean} - wildcard match
            is_filter = (key_lower.startswith("filter.") and
                         (key_lower.endswith(".smudge") or key_lower.endswith(".clean")))
            if not (key_lower in SUSPICIOUS_GIT_CONFIG_KEYS or is_filter):
                continue
            sub_stages, ok = shlex_split_stages(value)
            if not ok:
                return f"git -c {key} 值无法 tokenize — obfuscation"
            for stage_argv in sub_stages or []:
                real = strip_env_assignments_and_wrappers(stage_argv)
                if not real:
                    continue
                msg = scan_argv(real, sub_check=True)
                if msg:
                    return f"git -c {key} 嵌入危险命令: {msg}"
            continue
        i += 1
    return None


def check_cp_mv_to_system(argv):
    """cp / mv into /etc/, /usr/, /bin/, /sbin/, /lib/, /boot/.

    Overwriting critical system files (passwd / sudoers / shadow / hosts /
    systemd units) is essentially privilege escalation or persistent backdoor.
    """
    if not argv:
        return None
    cmd0 = basename(argv[0])
    if cmd0 not in ("cp", "mv", "install"):
        return None
    # Get positional args (skip flags + their values when known)
    CP_MV_VALUE_FLAGS = {"-S", "--suffix", "-t", "--target-directory",
                         "-T", "--no-target-directory", "--backup",
                         "--preserve", "--reflink"}
    paths = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--":
            i += 1
            paths.extend(argv[i:])
            break
        if a in CP_MV_VALUE_FLAGS:
            i += 2
            continue
        if a.startswith("--") and "=" in a:
            i += 1
            continue
        if a.startswith("-") and a != "-":
            i += 1
            continue
        paths.append(a)
        i += 1
    if not paths:
        return None
    # Last positional is the destination (cp/mv convention).
    dest = paths[-1]
    DANGEROUS_DEST = re.compile(
        r"^/(?:etc|usr|bin|sbin|lib|lib64|boot|root)(?:/.*)?$"
    )
    # Normalize for /etc/../var/... tricks
    if dest.startswith("/") and not re.search(r"[$`{}*?\[\]]", dest):
        try:
            normalized = os.path.normpath(dest)
        except Exception:
            normalized = dest
    else:
        normalized = dest
    if DANGEROUS_DEST.match(normalized):
        return f"{cmd0} 写入系统目录 {normalized!r} — 可能覆盖系统文件 / 提权"
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
    # E11+G6: cover write redirection (>, >>, >|), tee/cp/install destinations,
    # modern device naming, AND Linux stable device aliases
    # (/dev/disk/by-id/..., /dev/disk/by-path/..., /dev/mapper/...).
    DEV_PAT = (
        r"/dev/(?:"
        r"sd[a-z]|nvme\d+n\d+|mmcblk\d+|vd[a-z]|xvd[a-z]|hd[a-z]"
        r"|loop\d+|md\d+|dm-\d+|disk\d+"
        r"|disk/(?:by-id|by-path|by-uuid|by-label|by-partuuid|by-partlabel)/[^\s/]+"
        r"|mapper/[^\s/]+"
        r")"
    )
    if re.search(rf">\|?\s*{DEV_PAT}\b", stage_str):
        return "重定向到块设备会覆盖原始磁盘"
    if re.search(rf"\btee\s+(?:-[a-z]\s+)*(?:--?\S+\s+)*{DEV_PAT}\b", stage_str):
        return "tee 写入块设备会覆盖原始磁盘"
    if re.search(rf"\b(?:cp|install)\s+[^|;&]*?{DEV_PAT}\b", stage_str):
        return "cp/install 写入块设备会覆盖原始磁盘"
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
    # After shlex.split, quotes are stripped — programs look like '1e rm -rf /'
    # not "'1e rm -rf /'". So check each individual argv token for the e cmd.
    for tok in argv[1:]:
        # `e` modifier on a number range: `1e cmd`, `/pat/e cmd`
        # also -e form: argv contains ['-e', '1e cmd'] after shlex
        if re.search(r"(?:^|;|/)\s*\d*\s*e\b[ \t]", tok):
            return "sed e 修饰符执行 shell — 等同 shell injection vector"
        # Same pattern after /pattern/ address
        if re.search(r"/[^/]*/\s*e\b[ \t]", tok):
            return "sed /pat/e 修饰符执行 shell — 等同 shell injection vector"
    return None


XARGS_VALUE_FLAGS = {"-I", "-J", "-L", "-n", "-P", "-s", "-E", "-a", "-d",
                     "--max-args", "--max-chars", "--max-lines", "--max-procs",
                     "--arg-file", "--replace", "--delimiter", "--eof"}
DESTRUCTIVE_NAMES = {"rm", "rmdir", "shred", "mv", "dd", "mkfs", "chown", "chmod",
                     "cp", "fdisk", "wipefs", "blkdiscard", "format"}


def check_xargs(argv):
    if not argv or basename(argv[0]) != "xargs":
        return None
    # Skip xargs options to find the sub-command.
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--":
            i += 1
            break
        if a in XARGS_VALUE_FLAGS or a.startswith("--arg-file="):
            i += (2 if a in XARGS_VALUE_FLAGS else 1)
            continue
        if a.startswith("-") and a != "-":
            i += 1
            continue
        break
    if i >= len(argv):
        return None
    sub = argv[i:]
    # Unwrap wrappers in the sub-command too (find -exec env rm bypass).
    sub_unwrapped = strip_env_assignments_and_wrappers(sub)
    if not sub_unwrapped:
        return None
    sub_cmd = basename(sub_unwrapped[0])
    # xargs feeds stdin tokens as additional args — a destructive sub-command
    # whose explicit argv shows no target STILL gets one at runtime via stdin.
    # That's a dynamic target we can't see, so always block destructive xargs.
    if sub_cmd in DESTRUCTIVE_NAMES:
        return f"xargs 调用破坏性命令 {sub_cmd!r} — stdin 决定 target，扫描看不到"
    msg = scan_argv(sub_unwrapped, sub_check=True)
    if msg:
        return f"xargs 嵌入危险命令: {msg}"
    return None


def check_shell_dash_c(argv):
    """`bash -c "rm -rf /"`, `sh -c ...`, `su -c "..."`, `runuser -c ...`,
    `runuser --session-command "..."`, `flock LOCKFILE -c "..."`,
    `script -q -c "..." /dev/null`.

    Recursively scan the shell command string by re-entering the whole pipeline.
    """
    if not argv:
        return None
    cmd0 = basename(argv[0])
    SHELLS_WITH_C = {"sh", "bash", "dash", "ash", "zsh", "ksh", "fish", "tcsh",
                     "busybox", "su", "doas", "runuser",
                     "flock", "script"}
    if cmd0 not in SHELLS_WITH_C:
        return None
    # Find -c/--command/--session-command flag and its value.
    SHELL_STRING_FLAGS = {"-c", "--command", "--session-command"}
    for i, a in enumerate(argv[1:], start=1):
        inner = None
        if a in SHELL_STRING_FLAGS and i + 1 < len(argv):
            inner = argv[i + 1]
        else:
            for prefix in ("--command=", "--session-command="):
                if a.startswith(prefix):
                    inner = a[len(prefix):]
                    break
        if inner is None:
            continue
        sub_stages, ok = shlex_split_stages(inner)
        if not ok:
            return f"{cmd0} -c 内的命令字符串无法 tokenize — obfuscation"
        for stage_argv in sub_stages or []:
            real = strip_env_assignments_and_wrappers(stage_argv)
            if not real:
                continue
            msg = scan_argv(real)
            if msg:
                return f"{cmd0} -c 嵌入危险命令: {msg}"
        for body in extract_substitutions(inner):
            body_stages, _ok = shlex_split_stages(body)
            for s in body_stages or []:
                real = strip_env_assignments_and_wrappers(s)
                if not real:
                    continue
                msg = scan_argv(real)
                if msg:
                    return f"{cmd0} -c substitution 含危险命令: {msg}"
        break
    return None


def check_env_dash_s(argv):
    """E5: `env -S "rm -rf /"` — env -S splits the string and runs it as cmd.

    The value of -S is shell-string-like; recursively scan it.
    """
    if not argv or basename(argv[0]) != "env":
        return None
    for i, a in enumerate(argv[1:], start=1):
        if a == "-S" and i + 1 < len(argv):
            inner = argv[i + 1]
        elif a.startswith("-S"):
            inner = a[2:]
        else:
            continue
        sub_stages, ok = shlex_split_stages(inner)
        if not ok:
            return "env -S 内的字符串无法 tokenize — obfuscation"
        for stage_argv in sub_stages or []:
            real = strip_env_assignments_and_wrappers(stage_argv)
            if not real:
                continue
            msg = scan_argv(real)
            if msg:
                return f"env -S 嵌入危险命令: {msg}"
        break
    return None


def check_watch(argv):
    """E7: `watch "rm -rf /"` runs the (single quoted) argv as a shell command.

    watch joins its non-option args with spaces and executes as shell.
    """
    if not argv or basename(argv[0]) != "watch":
        return None
    # Skip watch's options
    WATCH_VALUE_FLAGS = WRAPPER_VALUE_FLAGS.get("watch", set())
    i = 1
    while i < len(argv):
        a = argv[i]
        if a in WATCH_VALUE_FLAGS:
            i += 2
            continue
        if a.startswith("-") and a != "-" and a != "--":
            i += 1
            continue
        if a == "--":
            i += 1
            break
        break
    if i >= len(argv):
        return None
    # The remaining args form a shell command (watch passes them to sh -c).
    inner = " ".join(argv[i:])
    sub_stages, ok = shlex_split_stages(inner)
    if not ok:
        return "watch 的命令字符串无法 tokenize — obfuscation"
    for stage_argv in sub_stages or []:
        real = strip_env_assignments_and_wrappers(stage_argv)
        if not real:
            continue
        msg = scan_argv(real)
        if msg:
            return f"watch 嵌入危险命令: {msg}"
    return None


def check_parallel(argv):
    """E9/G5: `parallel 'rm -rf {}' ::: /` or `parallel rm -rf ::: /` — template
    is a shell command. G5 fix: join ALL tokens up to `:::` (not just one).
    """
    if not argv or basename(argv[0]) != "parallel":
        return None
    PARALLEL_VALUE_FLAGS = WRAPPER_VALUE_FLAGS.get("parallel", set())
    i = 1
    while i < len(argv):
        a = argv[i]
        if a in PARALLEL_VALUE_FLAGS:
            i += 2
            continue
        if a.startswith("-") and a != "-":
            i += 1
            continue
        break
    if i >= len(argv):
        return None
    # Collect template tokens until `:::` separator.
    template_toks = []
    while i < len(argv) and argv[i] not in (":::", ":::+", "::::", "::::+"):
        template_toks.append(argv[i])
        i += 1
    if not template_toks:
        return None
    template = " ".join(template_toks)
    sub_stages, ok = shlex_split_stages(template)
    if not ok:
        return "parallel 模板无法 tokenize — obfuscation"
    for stage_argv in sub_stages or []:
        real = strip_env_assignments_and_wrappers(stage_argv)
        if not real:
            continue
        cmd0 = basename(real[0])
        # Same shape as xargs: parallel feeds tokens from `:::` (or stdin via -a)
        # as additional args. Destructive sub-commands whose explicit argv
        # shows no target STILL get one at runtime via parallel input.
        if cmd0 in DESTRUCTIVE_NAMES:
            return (
                f"parallel 模板调用破坏性命令 {cmd0!r}（:::/stdin 提供 target，扫描看不到）"
            )
        msg = scan_argv(real)
        if msg:
            return f"parallel 模板含危险命令: {msg}"
    return None


def check_remote_exec(argv):
    """F14-F16: ssh / docker exec / kubectl exec — they pass a sub-command
    that gets executed (locally or remotely). Recursively scan it.
    """
    if not argv:
        return None
    cmd0 = basename(argv[0])
    if cmd0 == "ssh":
        # ssh [opts] HOST [cmd...]
        # Skip ssh's options. ssh options with values: -p PORT, -i KEY, -o OPT,
        # -L/-R/-D PORT_SPEC, -F FILE, -E FILE, -l USER, -c CIPHER, -m MAC, -e CHAR.
        SSH_VALUE_FLAGS = {"-p", "-i", "-o", "-L", "-R", "-D", "-F", "-E", "-l",
                           "-c", "-m", "-e", "-b", "-B", "-J", "-Q", "-S", "-w"}
        i = 1
        while i < len(argv):
            a = argv[i]
            if a in SSH_VALUE_FLAGS:
                i += 2
                continue
            if a.startswith("-") and a != "-":
                i += 1
                continue
            break
        # Now argv[i] should be HOST; argv[i+1:] is the sub-command.
        if i + 1 < len(argv):
            sub = argv[i + 1:]
            if len(sub) == 1:
                # Single string argument — treat as shell command string.
                inner = sub[0]
                sub_stages, ok = shlex_split_stages(inner)
                if not ok:
                    return "ssh 远程命令字符串无法 tokenize"
                for stage_argv in sub_stages or []:
                    real = strip_env_assignments_and_wrappers(stage_argv)
                    if not real:
                        continue
                    msg = scan_argv(real, sub_check=True)
                    if msg:
                        return f"ssh 远程嵌入危险命令: {msg}"
            else:
                msg = scan_argv(sub, sub_check=True)
                if msg:
                    return f"ssh 远程嵌入危险命令: {msg}"
        return None
    if cmd0 in ("docker", "podman", "nerdctl", "buildah"):
        # docker/podman/nerdctl exec [opts] CONTAINER cmd...
        # buildah run [opts] CONTAINER cmd...
        if len(argv) >= 2 and argv[1] in ("exec", "run"):
            # codex r6: --privileged is boolean, NOT value flag.
            CONTAINER_VALUE_FLAGS = {"-e", "--env", "-u", "--user", "-w", "--workdir",
                                     "-v", "--volume", "--name", "--network",
                                     "-h", "--hostname", "--cpus", "--memory",
                                     "-m", "--mount", "--label", "-l",
                                     "--cgroup-parent", "--restart", "--add-host"}
            CONTAINER_BOOL_FLAGS = {"-d", "--detach", "-i", "--interactive",
                                    "-t", "--tty", "--rm", "--privileged",
                                    "--init", "--read-only", "--no-healthcheck"}
            i = 2
            while i < len(argv):
                a = argv[i]
                if a in CONTAINER_VALUE_FLAGS:
                    i += 2
                    continue
                if a in CONTAINER_BOOL_FLAGS:
                    i += 1
                    continue
                if a.startswith("--") and "=" in a:
                    i += 1
                    continue
                if a.startswith("-") and a != "-":
                    i += 1
                    continue
                break
            # argv[i] is container/image; argv[i+1:] is cmd
            if i + 1 < len(argv):
                sub = argv[i + 1:]
                msg = scan_argv(sub, sub_check=True)
                if msg:
                    return f"{cmd0} {argv[1]} 嵌入危险命令: {msg}"
        return None
    if cmd0 == "kubectl":
        if len(argv) >= 2 and argv[1] in ("exec", "run"):
            if "--" in argv:
                idx = argv.index("--")
                if idx + 1 < len(argv):
                    sub = argv[idx + 1:]
                    msg = scan_argv(sub, sub_check=True)
                    if msg:
                        return f"kubectl {argv[1]} 嵌入危险命令: {msg}"
            else:
                # codex r6: -i/-t/--stdin/--tty are BOOLEAN, not value flags.
                KUBECTL_VALUE_FLAGS = {"-c", "--container", "-n", "--namespace",
                                       "--context", "--cluster", "-f", "--filename"}
                KUBECTL_BOOL_FLAGS = {"-i", "--stdin", "-t", "--tty", "-q", "--quiet"}
                i = 2
                while i < len(argv):
                    a = argv[i]
                    if a in KUBECTL_VALUE_FLAGS:
                        i += 2
                        continue
                    if a in KUBECTL_BOOL_FLAGS:
                        i += 1
                        continue
                    if a.startswith("--") and "=" in a:
                        i += 1
                        continue
                    if a.startswith("-") and a != "-":
                        i += 1
                        continue
                    break
                if i + 1 < len(argv):
                    sub = argv[i + 1:]
                    msg = scan_argv(sub, sub_check=True)
                    if msg:
                        return f"kubectl {argv[1]} 嵌入危险命令: {msg}"
        return None
    # H1-H8: container/namespace wrappers that take cmd inline after POD/CTR.
    # (buildah handled above with docker/podman/nerdctl.)
    if cmd0 in ("lxc-attach", "nsenter", "chroot", "systemd-run",
                "systemd-nspawn"):
        # Skip wrapper-specific options to find the inner cmd.
        # We use a permissive skip: any -X with value-looking next arg gets skipped.
        WRAPPER_VAL_FLAGS_GENERIC = {
            "lxc-attach": {"-n", "--name", "-P", "--lxcpath", "-f", "--rcfile",
                           "-e", "--env", "-V", "--clear-env"},
            "buildah": {"--user", "--workingdir", "--env"},
            "nsenter": {"-t", "--target", "-m", "-u", "-i", "-n", "-p", "-U",
                        "-S", "--setuid", "-G", "--setgid", "-r", "--root",
                        "-w", "--wd"},
            "chroot": set(),
            "systemd-run": {"-u", "--unit", "-p", "--property", "--description",
                            "--slice", "-t", "--pty", "--uid", "--gid",
                            "--nice", "--working-directory", "-E", "--setenv"},
            "systemd-nspawn": {"-D", "--directory", "-i", "--image", "-M",
                               "--machine", "-u", "--user", "--network-zone",
                               "--bind", "--bind-ro", "--tmpfs"},
        }
        WRAPPER_LEADING_POS = {
            "chroot": 1,  # chroot NEW_ROOT [cmd...]
        }
        value_flags = WRAPPER_VAL_FLAGS_GENERIC.get(cmd0, set())
        i = 1
        while i < len(argv):
            a = argv[i]
            if a == "--":
                i += 1
                break
            if a in value_flags:
                i += 2
                continue
            if a.startswith("--") and "=" in a:
                i += 1
                continue
            if a.startswith("-") and a != "-":
                i += 1
                continue
            break
        # Skip wrapper-specific leading positionals
        i += WRAPPER_LEADING_POS.get(cmd0, 0)
        if i < len(argv):
            sub = argv[i:]
            real = strip_env_assignments_and_wrappers(sub)
            if real:
                msg = scan_argv(real, sub_check=True)
                if msg:
                    return f"{cmd0} 嵌入危险命令: {msg}"
        return None
    return None


def check_eval(argv):
    """eval "rm -rf /" — direct shell command-string execution."""
    if not argv or basename(argv[0]) != "eval":
        return None
    # eval concatenates its args with spaces and executes as shell.
    joined = " ".join(argv[1:])
    if not joined.strip():
        return None
    sub_stages, ok = shlex_split_stages(joined)
    if not ok:
        return "eval 含无法 tokenize 的命令字符串 — obfuscation"
    for stage_argv in sub_stages or []:
        real = strip_env_assignments_and_wrappers(stage_argv)
        if not real:
            continue
        msg = scan_argv(real)
        if msg:
            return f"eval 嵌入危险命令: {msg}"
    return None


# Main scan: given a real (unwrapped) argv, return blocking msg or None.
#
# v1.4.2: split into two phases so wrapper-aware checkers (env -S, parallel,
# taskset/chrt with positional args, watch) see the wrapper before unwrap
# strips it. Then unwrap + run the rest.
def scan_argv(argv, sub_check=False):
    if not argv:
        return None
    # Phase 1: wrapper-visible checkers (need to see the wrapper itself).
    for checker in (check_env_dash_s, check_watch, check_parallel,
                    check_taskset_chrt):
        msg = checker(argv)
        if msg:
            return msg
    # Phase 2: defense-in-depth unwrap (sub-check from find/xargs/shell-c
    # often has `env rm ...` shape).
    argv = strip_env_assignments_and_wrappers(argv)
    if not argv:
        return None
    for checker in (check_shell_dash_c, check_eval, check_remote_exec,
                    check_rm, check_git_reset_hard, check_git_push_force,
                    check_git_destructive, check_git_config_injection,
                    check_cp_mv_to_system,
                    check_sql_destroy, check_disk_ops,
                    check_find_exec, check_awk_system, check_sed_e, check_xargs):
        msg = checker(argv)
        if msg:
            return msg
    return None


def check_taskset_chrt(argv):
    """E8: taskset/chrt positional-arg parsers.

    taskset CPU cmd...        → cpu is positional, cmd starts after
    taskset -p [-c] PID       → no cmd
    chrt POLICY PRIO cmd...   → two positionals
    chrt -p PID               → no cmd
    chrt -f|-r|-o PRIO cmd... → policy flag + priority positional + cmd
    """
    if not argv:
        return None
    cmd0 = basename(argv[0])
    if cmd0 not in ("taskset", "chrt"):
        return None
    if cmd0 == "taskset":
        # G3: taskset modes:
        #   taskset MASK cmd...     → MASK is positional, cmd follows
        #   taskset -c CPULIST cmd  → -c takes CPULIST value; cmd follows the value (NO extra positional)
        #   taskset -p [-c] PID     → no sub-cmd
        i = 1
        has_p = False
        used_c_flag = False
        while i < len(argv):
            a = argv[i]
            if a in ("-p", "--pid"):
                has_p = True
                i += 1
                continue
            if a in ("-c", "--cpu-list"):
                used_c_flag = True
                i += 2  # -c VALUE
                continue
            if a.startswith("-") and a != "-":
                i += 1
                continue
            break
        if has_p:
            return None
        # With -c CPULIST consumed: argv[i:] is already the cmd.
        # Without -c: the first positional is the mask, then cmd.
        sub_start = i if used_c_flag else i + 1
        if sub_start < len(argv):
            sub = argv[sub_start:]
            real = strip_env_assignments_and_wrappers(sub)
            if real:
                msg = scan_argv(real, sub_check=True)
                if msg:
                    return f"taskset 嵌入危险命令: {msg}"
        return None

    # chrt
    # G4: util-linux chrt: `chrt [options] <priority> <command> [args]`.
    # 即非 -p 模式只有 ONE positional (priority) 在 cmd 前。
    has_p = False
    i = 1
    while i < len(argv):
        a = argv[i]
        if a in ("-p", "--pid"):
            has_p = True
            i += 1
            continue
        if a in ("-f", "-r", "-o", "-b", "-i",
                 "--fifo", "--rr", "--other", "--batch", "--idle",
                 "-m", "--max", "-v", "--verbose", "-a", "--all-tasks",
                 "-R", "--reset-on-fork"):
            i += 1
            continue
        if a.startswith("-") and a != "-":
            i += 1
            continue
        break
    if has_p:
        return None
    # chrt PRIORITY cmd... — skip ONE positional (priority).
    if i + 1 < len(argv):
        sub = argv[i + 1:]
        real = strip_env_assignments_and_wrappers(sub)
        if real:
            msg = scan_argv(real, sub_check=True)
            if msg:
                return f"chrt 嵌入危险命令: {msg}"
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
    """Tokenize whole cmd with punctuation awareness; split on pipe tokens.

    Both `|` and `|&` (bash stderr+stdout pipe) act as pipeline separators.
    """
    try:
        tokens = _tokenize_with_punctuation(cmd_str)
    except ValueError:
        return None
    stages = [[]]
    for t in tokens:
        if t in ("|", "|&"):
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

    # ANY pipeline whose final stage is a shell/interpreter is suspect —
    # `cat script | bash`, `printf 'rm -rf /' | bash`, etc. are all the same
    # risk class as `curl | bash`. Don't try to distinguish "trusted" upstream.
    if stage_bases and stage_bases[-1] in SHELL_BASENAMES | INTERPRETER_BASENAMES:
        # If the upstream stages are ALL safe-cmds reading static literals,
        # we might still allow (rare). But conservative default is block.
        emit_block("pipe-to-shell",
                   f"pipeline 末端是 shell/interpreter ({stage_bases[-1]}) — 上游内容直进 shell 执行",
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


# --------------- G1: Heredoc body scan ---------------
# `bash <<EOF\nrm -rf /\nEOF` etc. shlex tokenizes the `<<EOF` form weirdly;
# we operate on the raw cmd string to pull the body out.
for body in extract_heredocs(cmd):
    body_stages, body_ok = shlex_split_stages(body)
    if not body_ok:
        emit_block("heredoc-parse-failed",
                   "heredoc 内容无法 tokenize — 可能 obfuscation",
                   body[:120], cmd)
    for stage_argv in body_stages or []:
        real = strip_env_assignments_and_wrappers(stage_argv)
        if not real:
            continue
        msg = scan_argv(real)
        if msg:
            emit_block("heredoc-body",
                       f"heredoc 含危险命令: {msg}",
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
