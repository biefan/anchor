#!/usr/bin/env python3
"""v1.4.5 regression — user-reported B1 (runuser/doas -c) + B2 install fix."""
import json, subprocess, sys, os

import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_CANDIDATES = [
    os.path.expanduser("~/.claude/skills/anchor/scripts/pre-tool-danger.sh"),
    os.path.join(SCRIPT_DIR, "..", "..", "skills", "anchor", "scripts", "pre-tool-danger.sh"),
    "skills/anchor/scripts/pre-tool-danger.sh",
]
HOOK = next((p for p in _CANDIDATES if os.path.exists(p)), _CANDIDATES[-1])

TESTS = [
    # B1: runuser / doas / su variants with -c shell string
    ("BLOCK", "runuser -u root -c 'rm -rf /etc'", "B1a runuser -u user -c"),
    ("BLOCK", "runuser --user root -c 'rm -rf /etc'", "B1b runuser --user -c"),
    ("BLOCK", "runuser --session-command 'rm -rf /etc' root", "B1c runuser --session-command"),
    ("BLOCK", "doas -u root rm -rf /etc", "B1d doas without -c (caught by check_rm)"),
    ("BLOCK", "doas rm -rf /etc", "B1e doas without flags"),
    ("BLOCK", "su -c 'rm -rf /etc'", "B1f su -c"),
    ("BLOCK", "su - root -c 'rm -rf /etc'", "B1g su - user -c"),
    # Regressions: safe variants must pass
    ("PASS", "runuser -u nobody whoami", "reg runuser safe"),
    ("PASS", "doas -u nobody whoami", "reg doas safe"),
    ("PASS", "su nobody -c 'whoami'", "reg su safe cmd"),
]

p = f = 0
for expect, cmd, desc in TESTS:
    inp = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    r = subprocess.run(["bash", HOOK], input=inp, capture_output=True, text=True)
    actual = "BLOCK" if '"decision": "block"' in r.stdout else "PASS"
    if actual == expect:
        print(f"  ✓ {desc}")
        p += 1
    else:
        print(f"  ✗ {desc} → {actual}, expected {expect}")
        print(f"    cmd: {cmd}")
        f += 1
print(f"\nResult: {p} / {len(TESTS)} pass")
sys.exit(0)
