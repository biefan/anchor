# anchor

> 让 Claude Code 写代码"少走错路、不偏题、跑到完为止"的一套工程化 skill + slash commands + hooks。

## 它解决什么

Claude Code 在长任务下常见问题：
- 中途偏题（被 tool 输出带跑、自己派生新子任务、顺手做范围外的事）
- 长任务记忆衰减（auto-compact 后 skill 内容被截断）
- 单测过 ≠ 功能正确（不做 E2E 就说"完成"）
- 漏洞扫一遍说"干净"（没扫深就停）
- 修完 bug 转头就忘（不写回 CLAUDE.md，下次再踩）
- 自己审自己（有盲点，但每次都麻烦 codex 又太重）

这套配套把这些问题压成**软规则 + 硬拦截** 两层防线：
- **软**：SKILL.md 写明工作流，模型主动遵循
- **硬**：Stop hook 在 autonomous mode 下拦截未完成任务，强制推进

## 安装

```bash
# 克隆
git clone https://github.com/biefan/anchor.git ~/anchor
cd ~/anchor

# 一键安装到 ~/.claude/
./install.sh
```

`install.sh` 会做：
1. 把 `skills/efficient-coding/` 复制到 `~/.claude/skills/`
2. 把 `commands/*.md` 复制到 `~/.claude/commands/`
3. 给 `scripts/*.sh` 加可执行权限
4. 提示如何把 hook 配置 merge 进 `~/.claude/settings.json`

**首次安装后需要重启 Claude Code**（如果 `~/.claude/skills/` 是首次创建的话）——live change detection 不监视会话启动时不存在的顶层目录。

## 包含什么

```
anchor/
├── README.md                          # 本文档
├── install.sh / uninstall.sh          # 一键安装/卸载
├── settings.hooks.json                # hooks 配置示例（要 merge 到自己的 settings.json）
├── skills/
│   └── efficient-coding/
│       ├── SKILL.md                   # 核心 skill（核心七条 + 长任务模式 + 验证 + 漏洞扫描 + 审查 + 踩坑回写）
│       ├── references/                # 详细参考（按需读，不每次加载）
│       │   ├── autonomous-mode.md     # 自治模式协议
│       │   ├── pitfall-template.md    # 踩坑记录模板和示例
│       │   ├── vuln-checklist.md      # 漏洞 grep / SAST 工具命令清单
│       │   └── multi-agent-recipes.md # 多 agent 并行实战 prompt 模板
│       └── scripts/                   # hook 脚本
│           ├── session-start-inject.sh # SessionStart: 注入项目契约 + git 状态
│           ├── stop-self-check.sh      # Stop: autonomous 模式下拦截未完成任务
│           ├── pre-tool-danger.sh      # PreToolUse: 拦截 git reset --hard / push --force / DROP TABLE 等
│           ├── post-tool-lint.sh       # PostToolUse: 写完自动跑 ruff/eslint/clippy 等
│           ├── ec-status.sh            # 输出"autonomous + task 剩余"状态
│           └── statusline-wrapper.sh   # 把 ec-status 加到 ccstatusline 末尾
├── commands/                          # slash commands
│   ├── lock.md                        # /lock 锁定任务 scope
│   ├── pit.md                         # /pit 写踩坑记录
│   ├── scan.md                        # /scan 漏洞深扫
│   ├── done.md                        # /done 一键收尾
│   ├── next.md                        # /next 看下一步
│   ├── recap.md                       # /recap 复盘
│   └── init-claude-md.md              # /init-claude-md 创建项目契约骨架
└── evals/                             # 量化测试
    ├── evals.json                     # 5 个测试 prompt
    └── README.md                      # 跑法说明
```

## 使用

### 自动触发（多数场景）

不用做任何事。Claude 看到符合 description 的任务（implement / fix / refactor / debug / 安全审查 / 漏洞扫描 等关键词），自动调用 skill 走完整流程。

### 手动调用

```
/ec                  # 强制加载完整 skill 内容
/lock <用户原话>     # 任务开始前锁 scope
/pit [标题]          # 修完 bug 后写踩坑记录
/scan [子目录]       # 漏洞深扫一遍
/done                # 一键收尾（lint + E2E + codex + CLAUDE.md 检查）
/next                # 看 task list 下一步并标 in_progress
/recap               # 复盘已做 / 剩余 / 岔路
/init-claude-md      # 项目无 CLAUDE.md 时一键创建骨架
```

### 启用 / 关闭自治模式（任务完成才停）

```bash
# 启用：Claude 推进任务直到 task list 全部 completed，才允许 stop
touch ~/.claude/.efficient-coding-autonomous

# 关闭：恢复常规对话模式
rm ~/.claude/.efficient-coding-autonomous
```

**适合**：用户给一个完整任务后想要"做完才停"
**不适合**：探索性对话、需要边做边商量的决策

详细协议见 [`references/autonomous-mode.md`](skills/efficient-coding/references/autonomous-mode.md)。

## 设计原则

### 核心七条（任何时候被打断都回这里）

1. 意图清晰才开工（含糊就问，不二选一兜底）
2. 任务范围用 `TaskCreate` 锁住（用户原话当第一条 task）
3. 先读项目契约（`CLAUDE.md` / `AGENTS.md`）
4. 最小正确改动（显式 > 紧凑）
5. 能派 agent 就派，能并行就并行
6. 审查看情况调 codex（trivial 跳过，复杂 / 安全 / 大改必跑）
7. 踩坑必须回写当前工作目录的 `CLAUDE.md`

### 防偏题三招

- **TaskCreate 锁 scope**：用户原话当第一条 task 锚住，所有动作回头对它
- **偏题刹车**：每完成一个 task 看下一步，发现想做的事不在 list 上就停
- **新事项加新 task**：不顺手做，让用户决定要不要扩

### 防记忆衰减

- 核心规则全部前置到 SKILL.md 顶部（auto-compact 保留前 5000 token，关键内容能保住）
- task list 是外置记忆（不被 compact）
- 长任务主动 re-invoke `/ec` 恢复完整内容

### 自治模式（autonomous mode）

通过 `~/.claude/.efficient-coding-autonomous` 文件开关：
- ON：Stop hook 检查 task list 未完成项就 `block`，让 Claude 继续
- OFF（默认）：常规对话模式

遇阻按"观察 → 假设 → 验证"自主推进，穷尽 3 轮才停下报告。

## Codex CLI 支持

本 skill 同样跑得动 **OpenAI Codex CLI**（0.130+）——它和 Claude Code 共用同一份 [agentskills.io](https://agentskills.io) SKILL.md 标准。

### 自动安装

`install.sh` 检测到 `codex` 在 `PATH` 里时会自动同时把 skill 复制到 `~/.codex/skills/ec/`，无需额外配置。手动可以直接复制：

```bash
mkdir -p ~/.codex/skills/ec
cp -r skills/efficient-coding/{SKILL.md,references,scripts} ~/.codex/skills/ec/
```

### 用法

- **自动触发**：写代码 / 修 bug / 漏洞审查等场景，Codex 按 description 自动加载 `ec`
- **手动触发**：`/skills` 或直接调用 `ec`

验证装上了：
```bash
codex exec --json --skip-git-repo-check 'list available skills' | grep -i '"ec"'
```

### 跨平台覆盖范围

| 内容 | Claude Code | Codex CLI |
|---|---|---|
| SKILL.md（核心七条 + 长任务模式 + 自治 + 验证 + 漏洞扫描 + 审查 + 踩坑回写） | ✅ | ✅ |
| references/（详细参考文件） | ✅ | ✅ |
| 自动按 description 触发 | ✅ | ✅ |
| Slash 命令（/lock /pit /scan /done /next /recap /init-claude-md） | ✅ `~/.claude/commands/` | ✅ `~/.codex/skills/<name>/`（每条 command 是独立 skill，invoke 名相同） |
| SessionStart / Stop / PreToolUse / PostToolUse hooks | ✅ `~/.claude/settings.json` | ✅ 通过 plugin 安装（见下方"作为 plugin 安装"），跑 `${CLAUDE_PLUGIN_ROOT}/skills/.../scripts/` 里同一组脚本 |
| Autonomous mode（任务完成才停） | ✅ Stop hook 强制 | ✅ plugin 装上后等同 Claude Code |

### 工具名差异（影响很小）

SKILL.md 里写的是 Claude Code 工具名（`TaskCreate` / `AskUserQuestion` / `Agent`）。Codex（GPT-5）会理解意图，用自己等价工具（`plan_tool` / 询问 / 子任务）替代。**规则精神跨工具一致**——意图清晰、锁 scope、并行 agent、E2E、多遍扫漏洞等都生效。

### 关于已有的 ~/.codex/AGENTS.md

不冲突。AGENTS.md 是 Codex 全局基础规则，skill 是任务激活时的扩展。两者一起工作。

---

## 作为 plugin 安装（推荐 Codex 用户，启用 hooks）

`install.sh` 是文件复制安装——能让 skill + commands 在两边都生效，但 **hook 只装到 Claude Code 的 settings.json**。要让 Codex 也启用 hooks，把 repo 当 **plugin** 加载：

仓库根已经准备好了 plugin 元文件：

```
.claude-plugin/plugin.json    # Claude Code plugin manifest
.codex-plugin/plugin.json     # Codex CLI plugin manifest
hooks/hooks.json              # 4 hooks（用 ${CLAUDE_PLUGIN_ROOT} 引用脚本）
```

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

下次启动 Claude Code 自动安装 + hooks.json 自动注册（不需要手动改 settings.json hooks 段）。

### Codex CLI 用户：通过 `codex plugin add`

```bash
codex plugin marketplace add github:biefan/anchor
codex plugin add anchor@anchor
```

启用后 Codex 也自动读 hooks/hooks.json，4 个 hook 都生效。

### 两种安装方式对比

| 项 | `./install.sh`（文件复制） | plugin 安装 |
|---|---|---|
| 安装方式 | 跑脚本，复制文件 | marketplace 注册 |
| Claude Code skill + commands | ✅ | ✅ |
| Codex skill + commands | ✅ | ✅ |
| Claude Code hooks | ✅ 写 settings.json | ✅ plugin 自动 |
| Codex hooks | ❌ | ✅ plugin 自动 |
| 升级 | `git pull && ./install.sh` | `codex plugin add --update` |
| 卸载 | `./uninstall.sh` | `codex plugin remove` |

新用户**推荐 plugin 安装**。已用 `install.sh` 装的可以保持现状，hooks 已经在 ~/.claude/settings.json 里跑着。

---

## 卸载

```bash
./uninstall.sh
```

会移除 `~/.claude/skills/efficient-coding/` 和 `~/.claude/commands/{lock-scope,record-pitfall,scan-deeper}.md`。`settings.json` 里的 hook 配置需要手动从 `hooks` 段移除。

## 致谢与参考

设计参考：
- [Anthropic Agent Skills](https://github.com/anthropics/skills) 的官方 skill 模板（`skill-creator`、`claude-api`）
- [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) 的 stop-review-gate hook 实现
- [pr-review-toolkit](https://github.com/anthropics/claude-code-marketplace) 的 silent-failure-hunter / security-auditor / code-reviewer agents

## License

MIT
