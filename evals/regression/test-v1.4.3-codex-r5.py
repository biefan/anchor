#!/usr/bin/env python3
"""v1.4.3 regression suite — uses Python to construct multi-line cmds safely."""
import json
import subprocess
import sys

HOOK = "skills/anchor/scripts/pre-tool-danger.sh"

# (expected, cmd, description)
TESTS = [
    # G1: heredoc body
    ("BLOCK", "bash <<EOF\nrm -rf /\nEOF", "G1a heredoc body scan"),
    # G2: flock/script -c
    ("BLOCK", "flock /dev/null -c 'rm -rf /'", "G2a flock -c"),
    ("BLOCK", "script -q -c 'rm -rf /' /dev/null", "G2b script -c"),
    # G3-G4: taskset/chrt
    ("BLOCK", "taskset -c 0 rm -rf /", "G3 taskset -c parser"),
    ("BLOCK", "chrt 1 rm -rf /", "G4 chrt priority cmd"),
    # G5: parallel multi-token
    ("BLOCK", "parallel rm -rf ::: /", "G5 multi-token template"),
    # G6: disk aliases
    ("BLOCK", "cat image >| /dev/disk/by-id/nvme-x", "G6a /dev/disk/by-id"),
    ("BLOCK", "tee /dev/mapper/vg-root", "G6b /dev/mapper"),
    # F14-F16: remote/container
    ("BLOCK", "ssh user@host 'rm -rf /'", "F14 ssh remote"),
    ("BLOCK", "docker exec ctr rm -rf /", "F15 docker exec"),
    ("BLOCK", "kubectl exec pod -- rm -rf /", "F16a kubectl with --"),
    ("BLOCK", "kubectl exec pod rm -rf /", "F16b kubectl no --"),
    # Regressions (safe usage must pass)
    ("PASS", "ssh user@host uptime", "reg ssh safe cmd"),
    ("PASS", "docker exec ctr ls /tmp", "reg docker safe"),
    ("PASS", "taskset -c 0 echo hi", "reg taskset safe"),
    ("PASS", "chrt 1 echo hi", "reg chrt safe"),
    ("PASS", "(cd /tmp && ls)", "reg legitimate subshell"),
    ("PASS", "bash <<EOF\necho hi\nEOF", "reg safe heredoc"),
]

pass_n = 0
fail_n = 0
for expect, cmd, desc in TESTS:
    input_json = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    result = subprocess.run(
        ["bash", HOOK],
        input=input_json, capture_output=True, text=True
    )
    actual = "BLOCK" if '"decision": "block"' in result.stdout else "PASS"
    if actual == expect:
        print(f"  ✓ {desc}")
        pass_n += 1
    else:
        print(f"  ✗ {desc} → got {actual}, expected {expect}")
        print(f"    cmd: {cmd[:80]!r}")
        if result.stdout:
            print(f"    out: {result.stdout[:200]}")
        fail_n += 1

print(f"\nResult: {pass_n} / {len(TESTS)} pass")
sys.exit(0 if fail_n == 0 else 1)
