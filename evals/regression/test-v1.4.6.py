#!/usr/bin/env python3
"""v1.4.6 — mv to block device + git -c '!shell' prefix."""
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
    ("BLOCK", "mv /tmp/img /dev/sda", "mv to /dev/sda"),
    ("BLOCK", "mv /tmp/img /dev/nvme0n1", "mv to nvme"),
    ("BLOCK", "mv /tmp/img /dev/mapper/vg-root", "mv to mapper"),
    ("BLOCK", "git -c credential.helper='!rm -rf /' clone foo",
              "git -c credential.helper '!rm -rf /'"),
    ("BLOCK", "git -c core.sshCommand='!rm -rf /' clone foo",
              "git -c core.sshCommand '!rm -rf /'"),
    ("BLOCK", "git -c core.editor='!rm -rf /' commit",
              "git -c core.editor '!rm -rf /'"),
    # Regressions
    ("PASS", "mv old.txt new.txt", "reg mv safe cwd"),
    ("PASS", "git -c credential.helper=store push", "reg credential.helper safe"),
    ("PASS", "git -c color.ui=always log", "reg git -c safe"),
]
p = f = 0
for expect, cmd, desc in TESTS:
    inp = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    r = subprocess.run(["bash", HOOK], input=inp, capture_output=True, text=True)
    actual = "BLOCK" if '"decision": "block"' in r.stdout else "PASS"
    if actual == expect: print(f"  ✓ {desc}"); p += 1
    else: print(f"  ✗ {desc} → {actual}, expected {expect}"); print(f"    cmd: {cmd}"); f += 1
print(f"\nResult: {p} / {len(TESTS)} pass")
sys.exit(0)
