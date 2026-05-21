# Codex CLI 支持

anchor 同样跑得动 **OpenAI Codex CLI**（0.130+）—— 它和 Claude Code 共用同一份 [agentskills.io](https://agentskills.io) SKILL.md 标准。

## 自动安装

`install.sh` 检测到 `codex` 在 `PATH` 里时自动同时复制到 `~/.codex/skills/anchor/`，**无需额外配置**。

也可以手动：

```bash
mkdir -p ~/.codex/skills/anchor
cp -r skills/anchor/{SKILL.md,references,scripts} ~/.codex/skills/anchor/
```

## 用法

- **自动触发**：写代码 / 修 bug / 漏洞审查等场景，Codex 按 description 自动加载 `anchor`
- **手动触发**：`/skills` 或直接调用 `anchor`

验证装上了：
```bash
codex exec --json --skip-git-repo-check 'list available skills' | grep -i '"anchor"'
```

## 跨平台覆盖范围

| 内容 | Claude Code | Codex CLI |
|---|---|---|
| SKILL.md 核心八条 | ✅ | ✅ |
| references/ 详细参考 | ✅ | ✅ |
| 自动按 description 触发 | ✅ | ✅ |
| Slash 命令（22 个）| ✅ `~/.claude/commands/` | ✅ `~/.codex/skills/<name>/`（每条 command 是独立 skill）|
| SessionStart / Stop / PreToolUse / PostToolUse / PreCompact hooks | ✅ `~/.claude/settings.json` | ✅ 通过 plugin 安装 |
| Autonomous mode（任务完成才停）| ✅ Stop hook 强制 | ✅ plugin 装上后等同 |
| 长期记忆系统（`~/.anchor/memory/`）| ✅ | ✅ 共享同一棵记忆树 |
| Runtime detection (v1.11.0)| 自动 `claude-code` | 自动 `codex` |

## 工具名差异（影响很小）

SKILL.md 主体提到 Claude Code 工具名（`TaskCreate` / `AskUserQuestion` / `Agent`）。

**v1.11.0 起**：SessionStart hook 自动检测 runtime + 注入对应工具名 hints。Codex session 启动会看到：

```
**Runtime**: `codex`
- Task list: use `plan_tool` / `update_plan` (Codex names)
- Asking user: write a clear question in your response
- Sub-agents: list them in plan_tool as parallel steps
```

**规则精神跨工具一致** — 意图清晰、锁 scope、并行 agent、E2E、多遍扫漏洞等都生效。

## 关于已有的 `~/.codex/AGENTS.md`

**不冲突**。AGENTS.md 是 Codex 全局基础规则，anchor skill 是任务激活时的扩展。两者一起工作。

如果想测 anchor 单独的贡献（去掉 baseline AGENTS.md 干扰）：

```bash
python3 evals/run.py --all --no-baseline    # 临时 mv AGENTS.md 到一边
```

## 跨 CLI 适配的更多细节

适配 Cursor / Cline / Aider 等其它 AI coding 平台 → [`skills/anchor/references/multi-cli-adapters.md`](../skills/anchor/references/multi-cli-adapters.md)
