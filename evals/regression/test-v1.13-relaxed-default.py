#!/usr/bin/env python3
"""v1.13.0 — verify relaxed default + strict opt-in 2-tier behavior.

Tests:
- ALWAYS-block patterns still block (regardless of strict mode)
- STRICT-only patterns PASS in default mode
- STRICT-only patterns BLOCK when ANCHOR_STRICT=1
- Real disasters (rm -rf /, mkfs, etc) still always block
"""
import json
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_CANDIDATES = [
    os.path.expanduser("~/.claude/skills/anchor/scripts/pre-tool-danger.sh"),
    os.path.join(SCRIPT_DIR, "..", "..", "skills", "anchor", "scripts", "pre-tool-danger.sh"),
    "skills/anchor/scripts/pre-tool-danger.sh",
]
HOOK = next((p for p in _CANDIDATES if os.path.exists(p)), _CANDIDATES[-1])


def run_hook(cmd, strict=False):
    inp = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    env = dict(os.environ)
    if strict:
        env["ANCHOR_STRICT"] = "1"
    else:
        env.pop("ANCHOR_STRICT", None)
    r = subprocess.run(["bash", HOOK], input=inp, capture_output=True, text=True, env=env)
    return "BLOCK" if '"decision": "block"' in r.stdout else "PASS"


# (expected_default, expected_strict, cmd, desc)
TESTS = [
    # --- ALWAYS BLOCK (real disasters; both default and strict) ---
    ("BLOCK", "BLOCK", "rm -rf /", "rm -rf /"),
    ("BLOCK", "BLOCK", "git push --force origin main", "git push --force main"),
    ("BLOCK", "BLOCK", "git reset --hard origin/main", "git reset --hard"),
    ("BLOCK", "BLOCK", "dd if=/dev/zero of=/dev/sda", "dd of=/dev/sda"),
    ("BLOCK", "BLOCK", "mkfs.ext4 /dev/sda1", "mkfs disk wipe"),
    ("BLOCK", "BLOCK", "fdisk /dev/sda", "fdisk"),
    ("BLOCK", "BLOCK", "wipefs /dev/sda1", "wipefs"),
    ("BLOCK", "BLOCK", "blkdiscard /dev/sda", "blkdiscard"),
    ("BLOCK", "BLOCK", "mount -o remount,ro /", "remount,ro /"),
    ("BLOCK", "BLOCK", "kill -9 1", "kill -9 PID 1"),
    ("BLOCK", "BLOCK", "kill -9 -1", "kill -9 -1 (all procs)"),
    ("BLOCK", "BLOCK", "pkill -9 systemd", "pkill systemd"),
    ("BLOCK", "BLOCK", "killall -9 systemd", "killall systemd"),
    ("BLOCK", "BLOCK", "setcap cap_setuid+ep /tmp/x", "setcap cap_setuid"),
    ("BLOCK", "BLOCK", "useradd -u 0 evil", "useradd UID 0"),
    ("BLOCK", "BLOCK", "useradd -o evil", "useradd -o (non-unique)"),
    ("BLOCK", "BLOCK", "usermod -u 0 normaluser", "usermod UID 0"),
    ("BLOCK", "BLOCK", "passwd -d root", "passwd -d root"),
    ("BLOCK", "BLOCK", "ln -sf /tmp/evil /etc/passwd", "ln /etc/passwd"),
    ("BLOCK", "BLOCK", "ln -s /tmp/evil /bin/bash", "ln /bin/bash"),
    ("BLOCK", "BLOCK", "chattr +i /etc/passwd", "chattr +i /etc/passwd"),
    ("BLOCK", "BLOCK", "source /etc/profile.d/evil.sh", "source profile.d"),

    # --- STRICT-only (PASS in default, BLOCK in strict) ---
    # Note: systemctl pattern only matches security-critical services (ssh/firewalld/auditd/etc)
    # — `systemctl stop nginx` is ALWAYS PASS (nginx is not in critical list).
    ("PASS",  "BLOCK", "systemctl stop firewalld", "systemctl stop firewalld (critical)"),
    ("PASS",  "BLOCK", "systemctl disable ssh", "systemctl disable ssh (critical)"),
    ("PASS",  "BLOCK", "systemctl mask sshd", "systemctl mask sshd (critical)"),
    ("PASS",  "BLOCK", "apt remove -y curl", "apt remove -y"),
    ("PASS",  "BLOCK", "apt-get purge -y nginx", "apt-get purge -y"),
    ("PASS",  "BLOCK", "pip uninstall -y old-pkg", "pip uninstall -y"),
    ("PASS",  "BLOCK", "pip3 uninstall --yes django", "pip3 uninstall --yes"),
    ("PASS",  "BLOCK", "npm uninstall -g typescript", "npm uninstall -g"),
    ("PASS",  "BLOCK", "docker system prune -a --volumes -f", "docker prune"),
    ("PASS",  "BLOCK", "docker volume prune -f", "docker volume prune"),
    ("PASS",  "BLOCK", "kubectl delete ns dev --force", "kubectl delete ns"),
    ("PASS",  "BLOCK", "kubectl delete all --all", "kubectl delete all --all"),
    ("PASS",  "BLOCK", "terraform destroy -auto-approve", "terraform destroy"),
    ("PASS",  "BLOCK", "aws s3 rm s3://bucket --recursive", "aws s3 rm --recursive"),
    ("PASS",  "BLOCK", "aws iam delete-user --user-name X", "aws iam delete-user"),
    ("PASS",  "BLOCK", "gcloud projects delete proj", "gcloud projects delete"),
    ("PASS",  "BLOCK", "iptables -F", "iptables -F"),
    ("PASS",  "BLOCK", "ufw disable", "ufw disable"),
    ("PASS",  "BLOCK", "nft flush ruleset", "nft flush"),
    ("PASS",  "BLOCK", "crontab -r", "crontab -r"),
    ("PASS",  "BLOCK", "journalctl --vacuum-time=1s", "journalctl vacuum"),
    ("PASS",  "BLOCK", "useradd -G sudo attacker", "useradd -G sudo"),
    ("PASS",  "BLOCK", "usermod -aG sudo evil", "usermod -aG sudo"),
    ("PASS",  "BLOCK", "chown -R root /etc", "chown -R /etc"),
    ("PASS",  "BLOCK", "shutdown -h now", "shutdown"),
    ("PASS",  "BLOCK", "poweroff", "poweroff"),
    ("PASS",  "BLOCK", "reboot", "reboot"),
    ("PASS",  "BLOCK", "halt", "halt"),
    ("PASS",  "BLOCK", "init 0", "init 0"),
    ("PASS",  "BLOCK", "swapoff -a", "swapoff -a"),
    ("PASS",  "BLOCK", "umount -a", "umount -a"),
    ("PASS",  "BLOCK", "loginctl terminate-user root", "loginctl"),
    ("PASS",  "BLOCK", "gpg --delete-secret-keys foo", "gpg --delete-secret-keys"),
    ("PASS",  "BLOCK", "sysctl -w kernel.dmesg_restrict=0", "sysctl dmesg_restrict"),
    ("PASS",  "BLOCK", "mount --bind /tmp /mnt/etc", "mount --bind"),
    ("PASS",  "BLOCK", "passwd --stdin root", "passwd --stdin"),
    ("PASS",  "BLOCK", "truncate -s 0 /etc/passwd", "truncate -s 0"),
    ("PASS",  "BLOCK", "dpkg --purge openssh-server", "dpkg --purge"),

    # --- Always PASS (legit dev ops, should never block) ---
    ("PASS",  "PASS",  "systemctl status nginx", "systemctl status (read-only)"),
    ("PASS",  "PASS",  "systemctl restart myapp", "systemctl restart (non-critical)"),
    ("PASS",  "PASS",  "iptables -L", "iptables -L (list)"),
    ("PASS",  "PASS",  "crontab -l", "crontab -l (list)"),
    ("PASS",  "PASS",  "kill -9 12345", "kill specific pid"),
    ("PASS",  "PASS",  "useradd -m newuser", "useradd -m normal"),
    ("PASS",  "PASS",  "pip install requests", "pip install"),
    ("PASS",  "PASS",  "docker run alpine ls", "docker run"),
    ("PASS",  "PASS",  "aws s3 ls", "aws s3 ls"),
    ("PASS",  "PASS",  "terraform plan", "terraform plan"),
    ("PASS",  "PASS",  "mount /dev/sda1 /mnt", "mount (normal)"),
]


if not os.path.exists(HOOK):
    print(f"FATAL: pre-tool-danger.sh not found")
    sys.exit(1)

p = f = 0
for exp_default, exp_strict, cmd, desc in TESTS:
    # Test default mode
    got_default = run_hook(cmd, strict=False)
    if got_default == exp_default:
        p += 1
    else:
        print(f"  ✗ [default] {desc} → {got_default}, expected {exp_default}")
        print(f"      cmd: {cmd}")
        f += 1

    # Test strict mode
    got_strict = run_hook(cmd, strict=True)
    if got_strict == exp_strict:
        p += 1
    else:
        print(f"  ✗ [strict]  {desc} → {got_strict}, expected {exp_strict}")
        print(f"      cmd: {cmd}")
        f += 1

total = len(TESTS) * 2
print(f"\nResult: {p} / {total} pass ({f} fail)")
print(f"Used HOOK: {HOOK}")
sys.exit(0 if f == 0 else 1)
