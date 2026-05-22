---
description: 切换 anchor 严格模式 — 是否拦截 admin/cloud/package 命令（默认放松，只拦"真灾难"）。Use on prod servers / shared envs where you want maximum protection.
argument-hint: "on | off | status"
---

# /strict — toggle strict admin command blocking

切换 anchor 严格模式 — 控制 PreToolUse hook 是否拦截**日常 admin/dev 操作**。

## 默认（OFF）放行 vs 严格模式（ON）拦截

**始终拦截**（不受 strict mode 影响 — 真灾难）：
- `rm -rf /` 类、`git push --force` 到 main、`git reset --hard origin/main`
- `dd of=/dev/sd...`、`mkfs.*`、`fdisk`、`wipefs`、`blkdiscard`（disk 操作）
- `mount remount,ro /`（锁死根分区）
- `kill -9 -1`、`kill -9 1`、`pkill systemd`（杀 PID 1）
- `setcap cap_setuid+ep`（提权后门）
- `useradd -u 0`、`passwd -d root`、`ln -sf ... /etc/passwd`（认证后门）
- `chattr +i /etc/passwd`（系统认证文件锁死）
- `source /etc/profile.d/*`（特权 shell 注入）

**默认放行**（strict mode ON 才拦截 — 日常 dev 常用）：
- `systemctl stop/disable/mask <service>`
- `apt remove -y` / `apt-get purge -y` / `dpkg --purge`
- `pip uninstall -y` / `npm uninstall -g`
- `docker system prune -a --volumes` / `kubectl delete ns`
- `terraform destroy -auto-approve`
- `aws/gcloud/az ... delete`（云资源删除）
- `iptables -F` / `nft flush ruleset` / `ufw disable`（防火墙）
- `crontab -r` / `journalctl --vacuum-*`
- `useradd -G sudo` / `usermod -aG sudo`（提权组）
- `chown -R /etc`、`mount --bind`、`sysctl -w kernel.X`
- `shutdown` / `poweroff` / `reboot` / `halt`

## Steps

1. `$ARGUMENTS` = `on` | `off` | `status`（默认 `status`）

2. 操作：
   - `on` → `touch ~/.claude/.anchor-strict`
   - `off` → `rm -f ~/.claude/.anchor-strict`
   - `status` → 检查文件是否存在 + `ANCHOR_STRICT` env

3. 报告：
   ```
   Strict mode: ON / OFF
   
   File flag: ~/.claude/.anchor-strict (exists / missing)
   Env var:   ANCHOR_STRICT=1 (set / unset)
   
   ALWAYS-block patterns: ~30 (real disasters — unchanged)
   STRICT-only patterns:  ~250 (admin/cloud/pkg — opt-in)
   
   Total active: <X> patterns
   ```

4. 切换后**当前 session 立即生效**（hook 每次 invoke 读 file flag）。

## 什么时候 ON

- 在**生产服务器 / 共享环境**上跑 Claude Code
- 处理**真实用户数据 / 关键 infra** 的项目
- **新人入职** training 阶段（多防一道）
- 对 anchor 的拦截行为做**安全审计**或**演示**

## 什么时候 OFF（默认）

- **日常开发**（你的 laptop / dev container / dev cluster）
- **临时 dev env**（可丢弃的 docker / VM / namespace）
- 已经有**其它沙箱 / 权限隔离**（Claude Code OS sandbox / k8s pod 等）
- 嫌 hook 误报多

## Toggle by file flag (无需 command)

```bash
touch ~/.claude/.anchor-strict       # strict ON
rm ~/.claude/.anchor-strict          # strict OFF (默认)
ls ~/.claude/.anchor-strict 2>/dev/null && echo "strict ON" || echo "strict OFF"
```

或临时 enable 单条命令：

```bash
ANCHOR_STRICT=1 <your-command>       # 仅本次 hook 检查用 strict
```

## 和 `/lean` 的区别

- `/lean on|off` — 控制 **SessionStart hook 注入 token 量**（省 token，不影响安全）
- `/strict on|off` — 控制 **PreToolUse hook 拦截范围**（防误操作，不影响 token）

两个独立。
