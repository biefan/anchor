---
description: 显示 anchor 当前状态 —— autonomous mode 开关、当前 session task list 进度、最近 7 天 hook 触发统计。Use to see what anchor's been doing for you / how often hooks are firing.
argument-hint: "[--all | --days N]"
---

汇报 anchor 当前状态，按 4 段输出：

### 1. Autonomous mode 开关

跑：
```bash
test -f ~/.claude/.efficient-coding-autonomous && echo "🤖 ENABLED" || echo "⬜ disabled"
```

如果 enabled，提醒用户：Stop hook 在拦截未完成 task。要关：`rm ~/.claude/.efficient-coding-autonomous`。

### 2. 当前 session 的 task list

跑 `TaskList` 工具拿当前 session 任务。按 status 分桶统计：
- pending: N
- in_progress: N
- completed: N

如果没 task list，提示用 `/lock <用户原话>` 开始一个。

### 3. 最近 hook 触发统计（来自 `~/.claude/anchor-events.jsonl`）

跑（按用户的 `$ARGUMENTS` 决定时间窗口；默认 7 天）：
```bash
python3 ~/.claude/skills/efficient-coding/scripts/analyze-events.py $ARGUMENTS
```

把脚本输出原样转发给用户（这是 markdown，会渲染）。

### 4. 一句话状况总结

基于上面三段，告诉用户：
- 如果 autonomous + task list 有 pending → "推进中：还剩 N 项"
- 如果 autonomous + task list 全空 → "任务完成，可以 stop（Stop hook 会放行）"
- 如果没 autonomous + 有 task list → "task list 有 N 项，但 Stop hook 不会强拦——靠你自己决定何时 done"
- 如果都没 → "无活跃任务。准备好接新任务时用 `/lock <原话>` 锁 scope"

参数处理：
- 空 `$ARGUMENTS` → analyze 默认 7 天
- `$ARGUMENTS=--all` → 看全部历史
- `$ARGUMENTS=--days 30` → 30 天
- 如果用户传了 `--json`，把 analyze 的 JSON 输出原样转发（不渲染）

**重要**：本命令只读 + 报告，不修改任何状态（不动 task list、不动 autonomous flag、不删事件日志）。
