#!/usr/bin/env python3
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
    # Codex r6 7
    ("BLOCK", "sudo --user root rm -rf /", "codex-r6-1 sudo --user"),
    ("BLOCK", "env -C / rm -rf /", "codex-r6-2 env -C"),
    ("BLOCK", "runuser --session-command 'rm -rf /' root", "codex-r6-3 runuser --session-command"),
    ("BLOCK", "docker run --privileged alpine rm -rf /", "codex-r6-4 docker --privileged"),
    ("BLOCK", "kubectl exec -i pod rm -rf /", "codex-r6-5 kubectl -i no --"),
    ("BLOCK", "setpriv --reuid root rm -rf /", "codex-r6-6 setpriv --reuid"),
    ("BLOCK", "watch -n 1 rm -rf /", "codex-r6-7 watch -n schema"),
    # Self-audit r4 container wrappers
    ("BLOCK", "lxc-attach -n ctr -- rm -rf /", "self-r4-H1 lxc-attach"),
    ("BLOCK", "podman exec ctr rm -rf /", "self-r4-H2 podman exec"),
    ("BLOCK", "podman run img rm -rf /", "self-r4-H3 podman run"),
    ("BLOCK", "buildah run ctr rm -rf /", "self-r4-H4 buildah"),
    ("BLOCK", "nsenter -t 1 -m -u -- rm -rf /", "self-r4-H5 nsenter"),
    ("BLOCK", "chroot /mnt rm -rf /etc", "self-r4-H6 chroot"),
    ("BLOCK", "systemd-run rm -rf /", "self-r4-H7 systemd-run"),
    ("BLOCK", "systemd-nspawn -D /mnt rm -rf /", "self-r4-H8 systemd-nspawn"),
    # Regressions: safe usage still passes
    ("PASS", "sudo --user nobody whoami", "reg sudo --user safe cmd"),
    ("PASS", "env -C /tmp ls", "reg env -C safe"),
    ("PASS", "podman exec ctr ls", "reg podman safe"),
    ("PASS", "chroot /mnt bash --login", "reg chroot interactive"),
    ("PASS", "watch -n 1 date", "reg watch safe"),
    ("PASS", "kubectl exec -i pod cat /etc/hostname", "reg kubectl safe"),
]

p = f = 0
for expect, cmd, desc in TESTS:
    inp = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    r = subprocess.run(["bash", HOOK], input=inp, capture_output=True, text=True)
    actual = "BLOCK" if '"decision": "block"' in r.stdout else "PASS"
    if actual == expect:
        print(f"  ✓ {desc}"); p += 1
    else:
        print(f"  ✗ {desc} → {actual}, expected {expect}")
        print(f"    cmd: {cmd}")
        f += 1
print(f"\nResult: {p} / {len(TESTS)} pass, {f} fail")
sys.exit(0)
