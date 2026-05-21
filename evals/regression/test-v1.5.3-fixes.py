#!/usr/bin/env python3
"""v1.5.3 — fix 3 bugs in v1.5.2's admin checker.

Bug 1: ln to /dev/ not covered
Bug 2: ln false-positive when system path is the SOURCE not target
Bug 3: useradd -G sudo (initial groups) not detected
"""
import json, subprocess, sys

import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_CANDIDATES = [
    os.path.expanduser("~/.claude/skills/anchor/scripts/pre-tool-danger.sh"),
    os.path.join(SCRIPT_DIR, "..", "..", "skills", "anchor", "scripts", "pre-tool-danger.sh"),
    "skills/anchor/scripts/pre-tool-danger.sh",
]
HOOK = next((p for p in _CANDIDATES if os.path.exists(p)), _CANDIDATES[-1])

TESTS = [
    # Bug 1: ln target /dev/* should BLOCK
    ("BLOCK", "ln -sf /tmp/x /dev/sda",                "Bug1 ln target /dev/sda"),
    ("BLOCK", "ln -s /tmp/y /dev/nvme0n1",             "Bug1 ln target nvme"),
    ("BLOCK", "ln -sf evil /dev/null",                 "Bug1 ln target /dev/null"),

    # Bug 2: ln with system source but /tmp target should PASS (legit use)
    ("PASS",  "ln -s /usr/lib/libfoo.so /tmp/libfoo.so", "Bug2 source /usr/lib, target /tmp (legit)"),
    ("PASS",  "ln -s /etc/hosts /tmp/hosts-backup",      "Bug2 source /etc, target /tmp (legit)"),
    ("PASS",  "ln -sf /var/log/x.log /tmp/x.log",        "Bug2 source /var/log, target /tmp"),
    # But target as system path still must block
    ("BLOCK", "ln -sf /tmp/evil /etc/passwd",            "Bug2 target /etc/passwd still blocks"),
    ("BLOCK", "ln -s /tmp/evil /usr/bin/ls",             "Bug2 target /usr/bin/ls blocks"),

    # Bug 3: useradd -G with privileged groups
    ("BLOCK", "useradd -G sudo attacker",               "Bug3 useradd -G sudo"),
    ("BLOCK", "useradd -G wheel evil",                  "Bug3 useradd -G wheel"),
    ("BLOCK", "useradd -G docker bad",                  "Bug3 useradd -G docker"),
    ("BLOCK", "useradd --groups=sudo,users evil",       "Bug3 useradd --groups=sudo"),
    ("BLOCK", "usermod -G sudo somebody",               "Bug3' usermod -G (no -a) sudo"),
    ("BLOCK", "usermod -G admin somebody",              "Bug3' usermod -G admin"),

    # Regressions: must still pass
    ("PASS",  "useradd -m newuser",                     "reg useradd normal"),
    ("PASS",  "useradd -G developers alice",            "reg useradd -G non-privileged group"),
    ("PASS",  "usermod -L locked-user",                 "reg usermod -L (lock)"),
    ("PASS",  "ln -sf /tmp/source /tmp/link",           "reg ln in /tmp"),
    ("PASS",  "ln -s ~/notes ~/work/notes",             "reg ln in home"),
    ("PASS",  "ln -sf ./script ./bin/script",           "reg ln in cwd"),

    # Make sure v1.5.2 existing blocks still work
    ("BLOCK", "usermod -aG sudo evil",                  "reg v1.5.2 usermod -aG still blocks"),
    ("BLOCK", "useradd -u 0 evil",                      "reg v1.5.2 useradd -u 0 still blocks"),
]

p = f = 0
for expect, cmd, desc in TESTS:
    inp = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    r = subprocess.run(["bash", HOOK], input=inp, capture_output=True, text=True)
    actual = "BLOCK" if '"decision": "block"' in r.stdout else "PASS"
    if actual == expect:
        p += 1
    else:
        print(f"  ✗ {desc} → {actual}, expected {expect}")
        print(f"    cmd: {cmd}")
        f += 1
print(f"\nResult: {p} / {len(TESTS)} pass ({f} fail)")
sys.exit(0)
