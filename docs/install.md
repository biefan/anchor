# 安装

anchor 支持 **2 种安装方式**，按你的 CLI 选：

## 方式 A：脚本安装（推荐 Claude Code 用户）

```bash
git clone https://github.com/biefan/anchor.git ~/anchor
cd ~/anchor
./install.sh
```

`install.sh` 做的事：

1. 复制 skill / **22 个** slash commands / **9 个** hook 脚本 / **5 个** init templates 到 `~/.claude/`
2. **自动 merge 5 个 hooks 到 `~/.claude/settings.json`**（带 timestamp backup，可用 `--no-hooks` 跳过）
3. 检测到 codex CLI 就同时安装到 `~/.codex/`（skill + 22 commands as skills）
4. **3 层锁机制**：`flock(1)` → Python `fcntl.flock` → mkdir-atomicity，永不 silent loss-of-serialization
5. **v1.11.0 migration**：自动删除旧 `/cost.md` 和 `/resume.md`（避免和 Claude Code 内建冲突）
6. 重复跑无副作用（idempotent，不会重复 merge hooks）

**首次安装后需要重启 Claude Code**（如果 `~/.claude/skills/` 是首次创建的话）——live change detection 不监视会话启动时不存在的顶层目录。

### Options

```bash
./install.sh --no-hooks                # 跳过 settings.json 修改
./install.sh --replace-plugin-hooks    # 把 plugin-scheme hooks 替换为 home-scheme（迁移用）
./install.sh -h                        # 帮助
```

## 方式 B：作为 plugin 安装（推荐 Codex CLI 用户）

`./install.sh` 的 hooks 只装到 Claude Code 的 `settings.json`。要让 **Codex CLI 也启用 hooks**，把 repo 当 plugin 加载：

### Claude Code 用户：通过 marketplace

在 `~/.claude/settings.json` 里加：

```json
"extraKnownMarketplaces": {
  "anchor": {
    "source": {
      "source": "github",
      "repo": "biefan/anchor"
    }
  }
},
"enabledPlugins": {
  "anchor@anchor": true
}
```

下次启动 Claude Code 自动安装 + hooks 自动注册（不需要手动改 settings.json hooks 段）。

### Codex CLI 用户：通过 `codex plugin add`

```bash
codex plugin marketplace add github:biefan/anchor
codex plugin add anchor@anchor
```

启用后 Codex 也自动读 hooks/hooks.json，5 个 hook 都生效。

## 两种安装方式对比

| 项 | `./install.sh`（文件复制）| plugin 安装 |
|---|---|---|
| 安装方式 | 跑脚本，复制文件 | marketplace 注册 |
| Claude Code skill + commands | ✅ | ✅ |
| Codex skill + commands | ✅（自动检测）| ✅ |
| Claude Code hooks | ✅ 写 settings.json | ✅ plugin 自动 |
| Codex hooks | ❌ | ✅ plugin 自动 |
| 升级 | `git pull && ./install.sh` | `codex plugin add --update` |
| 卸载 | `./uninstall.sh` | `codex plugin remove` |

**新用户**：
- 只用 Claude Code → 方式 A 简单
- 用 Codex CLI → 方式 B 让 hooks 也启用

## 卸载

```bash
./uninstall.sh             # 默认：移除 home-scheme，保留 plugin 安装的
./uninstall.sh --all-hooks # 也清掉 plugin-scheme hook 条目
```

会移除：
- `~/.claude/skills/anchor/`
- 22 个 `~/.claude/commands/*.md`
- `~/.codex/skills/` 下的所有 anchor skill 目录

`settings.json` 里 home-scheme 的 anchor hook 条目自动清掉（带 timestamp backup）。

**`~/.anchor/memory/` 不会被删** — 跨项目记忆是你的资产，由你自己决定要不要清。手动删：

```bash
rm -rf ~/.anchor/memory ~/.anchor/saved-tasks ~/.anchor/active-task.md
```

## 文件结构

```
~/anchor/                              # repo clone
├── install.sh / uninstall.sh
├── .claude-plugin/plugin.json         # Claude Code plugin manifest
├── .codex-plugin/plugin.json          # Codex CLI plugin manifest
├── hooks/hooks.json                   # 5 hooks 共享配置
├── settings.hooks.json                # settings.json merge 示例
├── skills/anchor/
│   ├── SKILL.md
│   ├── references/                    # 按需载入的 10 个详细参考
│   └── scripts/                       # 9 个 hook + helper 脚本
├── commands/                          # 22 个 slash commands
└── evals/                             # 测试 + stress test

~/.anchor/                             # user data（不在 repo）
├── active-task.md                     # 跨 session 长任务状态
├── saved-tasks/<label>.md             # /save → /resume-task
└── memory/                            # /pit, /decide, /remember
    ├── pitfalls/<project>/
    ├── decisions/<project>/
    ├── facts/<project>/
    ├── snapshots/<project>/
    ├── preferences.md                 # 自动 inject 下次 session
    └── todos.md
```
