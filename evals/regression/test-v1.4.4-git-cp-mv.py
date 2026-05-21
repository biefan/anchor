import json, subprocess, sys
HOOK = "skills/efficient-coding/scripts/pre-tool-danger.sh"

TESTS = [
    # Git destructive
    ("BLOCK", "git clean -fdx", "git clean -fdx whole tree"),
    ("BLOCK", "git clean -fd", "git clean -fd whole tree"),
    ("BLOCK", "git branch -D main", "git branch -D force delete"),
    # Git config injection
    ("BLOCK", "git -c core.sshCommand='ssh u@h rm -rf /' clone foo", "git -c sshCommand injection"),
    ("BLOCK", "git -c core.editor='rm -rf /' commit", "git -c editor injection"),
    ("BLOCK", "git -c gpg.program='rm -rf /' tag", "git -c gpg.program injection"),
    # cp/mv to system
    ("BLOCK", "cp /tmp/evil /etc/passwd", "cp to /etc/passwd"),
    ("BLOCK", "mv /tmp/evil /etc/shadow", "mv to /etc/shadow"),
    ("BLOCK", "cp -f /tmp/x /bin/ls", "cp to /bin/ls"),
    ("BLOCK", "install /tmp/x /usr/bin/foo", "install to /usr/bin"),
    # Regressions
    ("PASS", "git clean -fd build/", "git clean specific dir OK"),
    ("PASS", "git branch -d feature-x", "git branch -d safe"),
    ("PASS", "cp /tmp/a /tmp/b", "cp safe paths"),
    ("PASS", "git -c color.ui=always log", "git -c safe config"),
    ("PASS", "mv old.txt new.txt", "mv in cwd"),
]

p = f = 0
for expect, cmd, desc in TESTS:
    inp = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    r = subprocess.run(["bash", HOOK], input=inp, capture_output=True, text=True)
    actual = "BLOCK" if '"decision": "block"' in r.stdout else "PASS"
    mark = "✓" if actual == expect else "✗"
    print(f"  {mark} {desc} → {actual}")
    if actual == expect:
        p += 1
    else:
        print(f"    cmd: {cmd}")
        f += 1
print(f"\nResult: {p} / {len(TESTS)} pass")
