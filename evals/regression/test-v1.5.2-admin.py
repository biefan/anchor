#!/usr/bin/env python3
"""v1.5.2 — defense scope extension: 30+ destructive admin commands.

Adds checker for: truncate / iptables / nft / ufw / systemctl / crontab /
useradd / usermod / passwd / journalctl / chattr / setcap / shutdown /
swapoff / mount remount / loginctl / pkill / kill -9 -1 / gpg / pip / npm /
apt / dpkg / aws / gcloud / az / terraform / kubectl / docker prune / ln -sf.
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
    # Truncate (zero file)
    ("BLOCK", "truncate -s 0 /etc/passwd",                "truncate -s 0 system file"),
    ("BLOCK", "truncate --size=0 /var/log/auth.log",      "truncate --size=0"),

    # Firewall ops
    ("BLOCK", "iptables -F",                              "iptables -F"),
    ("BLOCK", "iptables -X",                              "iptables -X"),
    ("BLOCK", "iptables -P INPUT ACCEPT",                 "iptables -P INPUT ACCEPT"),
    ("BLOCK", "ip6tables -F",                             "ip6tables -F"),
    ("BLOCK", "nft flush ruleset",                        "nft flush ruleset"),
    ("BLOCK", "ufw disable",                              "ufw disable"),
    ("BLOCK", "ufw reset",                                "ufw reset"),
    ("BLOCK", "firewall-cmd --panic-off",                 "firewall-cmd --panic-off"),

    # Service control (security-critical)
    ("BLOCK", "systemctl stop firewalld",                 "systemctl stop firewalld"),
    ("BLOCK", "systemctl disable ssh",                    "systemctl disable ssh"),
    ("BLOCK", "systemctl mask sshd",                      "systemctl mask sshd"),
    ("BLOCK", "systemctl stop auditd",                    "systemctl stop auditd"),
    ("BLOCK", "systemctl isolate rescue",                 "systemctl isolate rescue"),

    # Cron destruction
    ("BLOCK", "crontab -r",                               "crontab -r"),
    ("BLOCK", "crontab -u root -r",                       "crontab -u root -r"),

    # Privilege backdoors
    ("BLOCK", "useradd -o -u 0 evil",                     "useradd -o -u 0"),
    ("BLOCK", "useradd --uid=0 evil",                     "useradd --uid=0"),
    ("BLOCK", "usermod -aG sudo evil",                    "usermod -aG sudo"),
    ("BLOCK", "usermod -aG wheel attacker",               "usermod -aG wheel"),
    ("BLOCK", "passwd --stdin root",                      "passwd --stdin"),
    ("BLOCK", "passwd -d root",                           "passwd -d (no password)"),

    # Log shredding
    ("BLOCK", "journalctl --vacuum-time=1s",              "journalctl vacuum-time"),
    ("BLOCK", "journalctl --vacuum-size=0",               "journalctl vacuum-size=0"),
    ("BLOCK", "journalctl --rotate",                      "journalctl --rotate"),

    # Immutable bit + caps
    ("BLOCK", "chattr +i /etc/passwd",                    "chattr +i system file"),
    ("BLOCK", "chattr -i /etc/passwd",                    "chattr -i (unlock for tampering)"),
    ("BLOCK", "setcap cap_setuid+ep /tmp/evil",           "setcap cap_setuid"),
    ("BLOCK", "setcap cap_sys_admin=eip /tmp/x",          "setcap cap_sys_admin"),

    # Shutdown / reboot
    ("BLOCK", "shutdown -h now",                          "shutdown -h"),
    ("BLOCK", "poweroff",                                  "poweroff"),
    ("BLOCK", "reboot",                                    "reboot"),
    ("BLOCK", "halt",                                      "halt"),
    ("BLOCK", "init 0",                                    "init 0"),
    ("BLOCK", "init 6",                                    "init 6"),

    # Mass kill
    ("BLOCK", "kill -9 -1",                                "kill -9 -1 (kill all user procs)"),
    ("BLOCK", "kill -9 1",                                 "kill -9 1 (PID 1)"),
    ("BLOCK", "pkill -9 systemd",                          "pkill -9 systemd"),
    ("BLOCK", "killall -9 systemd",                        "killall -9 systemd"),

    # Mount / swap
    ("BLOCK", "swapoff -a",                                "swapoff -a"),
    ("BLOCK", "mount -o remount,ro /",                     "mount remount,ro /"),
    ("BLOCK", "umount /etc",                               "umount /etc"),
    ("BLOCK", "umount -a",                                 "umount -a"),

    # Login control
    ("BLOCK", "loginctl terminate-user root",              "loginctl terminate-user"),
    ("BLOCK", "loginctl kill-session 1",                   "loginctl kill-session"),

    # GPG
    ("BLOCK", "gpg --delete-secret-keys foo@bar",          "gpg --delete-secret-keys"),

    # Package mgmt
    ("BLOCK", "pip uninstall -y critical-pkg",             "pip uninstall -y"),
    ("BLOCK", "pip3 uninstall --yes django",               "pip3 uninstall --yes"),
    ("BLOCK", "npm uninstall -g typescript",               "npm uninstall -g"),
    ("BLOCK", "apt remove -y openssh-server",              "apt remove -y openssh-server"),
    ("BLOCK", "apt-get purge -y nginx",                    "apt-get purge -y"),
    ("BLOCK", "dpkg --purge openssh-server",               "dpkg --purge"),

    # Cloud nuke
    ("BLOCK", "aws iam delete-user --user-name admin",     "aws iam delete-user"),
    ("BLOCK", "aws s3 rm s3://bucket --recursive",         "aws s3 rm --recursive"),
    ("BLOCK", "aws s3api delete-bucket --bucket prod",     "aws s3api delete-bucket"),
    ("BLOCK", "aws rds delete-db-instance --db-instance-identifier prod", "aws rds delete-db-instance"),
    ("BLOCK", "aws ec2 terminate-instances --instance-ids i-x", "aws ec2 terminate-instances"),
    ("BLOCK", "gcloud projects delete my-proj",            "gcloud projects delete"),
    ("BLOCK", "gcloud compute instances delete prod-vm",   "gcloud compute instances delete"),
    ("BLOCK", "az group delete --name prod",               "az group delete"),
    ("BLOCK", "az vm delete --name prod-vm",               "az vm delete"),

    # IaC
    ("BLOCK", "terraform destroy -auto-approve",           "terraform destroy -auto-approve"),

    # k8s + container
    ("BLOCK", "kubectl delete ns prod --force",            "kubectl delete ns --force"),
    ("BLOCK", "kubectl delete all --all",                  "kubectl delete all --all"),
    ("BLOCK", "docker system prune -a --volumes -f",       "docker system prune -a --volumes"),
    ("BLOCK", "docker volume prune -f",                    "docker volume prune -f"),
    ("BLOCK", "podman system prune -a --volumes",          "podman system prune -a --volumes"),

    # Symlink replace
    ("BLOCK", "ln -sf /tmp/evil /etc/passwd",              "ln -sf /etc/passwd"),
    ("BLOCK", "ln -s /dev/null /var/log/auth.log",         "ln -s /var/log/auth.log"),

    # Disk format
    ("BLOCK", "mkfs.ext4 /dev/sda1",                       "mkfs.ext4"),
    ("BLOCK", "fdisk /dev/sda",                            "fdisk"),
    ("BLOCK", "wipefs /dev/sda1",                          "wipefs"),

    # Regressions: legitimate usage must pass
    ("PASS", "systemctl status nginx",                     "reg systemctl status (read-only)"),
    ("PASS", "systemctl restart myapp",                    "reg systemctl restart (non-critical)"),
    ("PASS", "iptables -L",                                "reg iptables -L (list)"),
    ("PASS", "truncate -s 100 /tmp/test.log",              "reg truncate to non-zero on tmp"),
    ("PASS", "crontab -l",                                 "reg crontab -l (list)"),
    ("PASS", "kill -9 12345",                              "reg kill specific pid"),
    ("PASS", "useradd -m newuser",                         "reg useradd normal"),
    ("PASS", "passwd",                                     "reg passwd interactive"),
    ("PASS", "ln -sf /tmp/source /tmp/link",               "reg ln in /tmp"),
    ("PASS", "mount /dev/sda1 /mnt",                       "reg mount (no remount,ro)"),
    ("PASS", "docker run alpine ls",                       "reg docker run normal"),
    ("PASS", "kubectl get pods",                           "reg kubectl get"),
    ("PASS", "aws s3 ls",                                  "reg aws s3 ls"),
    ("PASS", "terraform plan",                             "reg terraform plan"),
    ("PASS", "pip install requests",                       "reg pip install"),
    ("PASS", "npm install lodash",                         "reg npm install"),
    ("PASS", "gcloud projects list",                       "reg gcloud list"),
]

p = f = 0
# v1.13.0: admin patterns are now opt-in (strict mode). Enable for these tests.
env = {**os.environ, "ANCHOR_STRICT": "1"}
for expect, cmd, desc in TESTS:
    inp = json.dumps({"tool_name": "Bash", "tool_input": {"command": cmd}})
    r = subprocess.run(["bash", HOOK], input=inp, capture_output=True, text=True, env=env)
    actual = "BLOCK" if '"decision": "block"' in r.stdout else "PASS"
    if actual == expect:
        p += 1
    else:
        print(f"  ✗ {desc} → {actual}, expected {expect}")
        print(f"    cmd: {cmd}")
        f += 1
print(f"\nResult: {p} / {len(TESTS)} pass ({f} fail)")
sys.exit(0)
