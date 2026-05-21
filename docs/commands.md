# 22 个 slash commands

按使用阶段分类。所有命令在 Claude Code 和 Codex CLI 都生效（Codex CLI 把每个 command 当独立 skill）。

## 🚀 开始任务

| 命令 | 作用 | 何时用 |
|---|---|---|
| `/lock <用户原话>` | 把用户原话锚定为第一条 task，所有后续动作只服务它 | 任何非 trivial 任务开始时 |
| `/init-claude-md [--template=X]` | 项目无 CLAUDE.md 时自动识别类型 + 生成骨架 | 第一次进入新项目 |
| `/ec` | 强制加载完整 SKILL.md 内容 | auto-compact 后；或长任务感觉偏题时 |

**Templates** (`--template=` arg)：`web-app` / `library` / `cli-tool` / `data-pipeline` / `default`。检测不到就用 `default`。

## ⚒️ 干活中

| 命令 | 作用 |
|---|---|
| `/next` | 看 task list 下一步，标 in_progress |
| `/recap` | 复盘进度：已做 / 剩余 / 岔路 / 需决策项 |
| `/status` | autonomous mode 状态 + task 进度 + 7 天 hook 触发统计 |
| `/diff` | 分析 git diff 的风险面（改动规模 / 敏感关键词 / 回归类别）|

## 🔒 长任务跨 session

| 命令 | 作用 |
|---|---|
| `/save [label]` | 持久化当前 task list 到 `~/.anchor/saved-tasks/<label>.md` |
| `/resume-task [label]` | 在新 session 用 TaskCreate 重建之前 save 的 task list |
| `/milestone <name>` | 标记阶段完成，写入 `~/.anchor/active-task.md` 给后续 session 看 |
| `/snapshot <label>` | Workspace 完整快照（task + git diff + 文件 + 决策）|

**Auto-save (v1.11.0+)**：PreCompact + Stop hook 自动 save 到 `~/.anchor/saved-tasks/auto-*.md`。**用户完全不用做**——`/save` 失败也有 fallback。

## 🧠 跨项目长期记忆

| 命令 | 作用 |
|---|---|
| `/pit [标题]` | 修完 bug 写 4-field 踩坑到 `CLAUDE.md` + 自动 sync 全局 |
| `/decide <题目>` | ADR-style 架构决策记录到 `~/.anchor/memory/decisions/<project>/` |
| `/remember pref\|decision\|fact\|todo <内容>` | 通用长期记忆写入 |
| `/recall <keyword>` | **跨项目 grep 7 类记忆**（这是关键 — 让 anchor 真的"记得住"）|

**记忆系统 closed loop**：
1. `/pit` 等命令写入 `~/.anchor/memory/<category>/<project>/`
2. SessionStart hook 自动列出本项目 memory titles
3. SKILL.md 规则 #8 教 Claude 见到 matching topic 先 `/recall`
4. `/recall <keyword>` 拉完整内容

之前缺中间 2 步（索引 + 反射），所以 memory 是 write-only。v1.9.0 起 closed loop。

## ✅ 收尾 / 安全

| 命令 | 作用 |
|---|---|
| `/scan [子目录]` | 漏洞深扫一遍（多遍方法论 + SAST 工具）|
| `/cleanup` | 找 dead code / debug print / 未用 import / 过期 TODO |
| `/done` | 收尾 checklist：lint + E2E + codex review（按规模）+ CLAUDE.md 写回 |
| `/ship` | done check + Conventional Commit + gh PR create 一条龙 |

## 💰 成本 / 复盘

| 命令 | 作用 |
|---|---|
| `/spend` | 当前 session token / 时长 / 估算 USD（调 `ccusage` 或 fallback 估）|
| `/report [days]` | 跨 session 聚合（drift heatmap / top blocked patterns / 趋势对比）|
| `/lean on\|off` | 切换 token-saving mode（SessionStart 减少注入 ~900 token/session）|

## 自动触发 vs 手动调用

**不用 `/<cmd>` 也行** — Claude 看到符合 description 的任务（implement / fix / refactor / debug / 安全审查 等关键词），**自动调用** anchor skill 走完整流程。手动 `/<cmd>` 是显式 override。

## 命名冲突避免

v1.11.0 rename 了 2 个跟 Claude Code 内建冲突的命令：

| 旧名 (v1.6.0–v1.10.0) | 新名 (v1.11.0+) | 为什么 |
|---|---|---|
| `/cost` | `/spend` | Claude Code 内建 `/cost`（session token cost）|
| `/resume` | `/resume-task` | Claude Code 内建 `/resume`（恢复 prior session）|

如果你从老版本升级，**重新跑 `./install.sh`** 自动迁移。

## 启用 / 关闭自治模式

```bash
touch ~/.claude/.efficient-coding-autonomous     # ON
rm ~/.claude/.efficient-coding-autonomous        # OFF（默认）
```

- ON：Stop hook 检查 task list 未完成项就 `block`，让 Claude 继续
- 遇阻按"观察 → 假设 → 验证"自主推进，穷尽 3 轮才停下报告

详细协议见 [`skills/anchor/references/autonomous-mode.md`](../skills/anchor/references/autonomous-mode.md)。

## 完整 walkthrough

5 个典型场景（新项目 / 长 refactor / 安全审计 / 多 agent 并行 / 跨 session 续接）→ [`docs/playbook.md`](playbook.md)
