---
description: 切换 anchor "lean mode" — hooks 减少 SessionStart 注入 / PostToolUse 输出 / 节省 token。Use when sessions are short, when you want minimal context tax, or for cost optimization.
argument-hint: "on | off | status"
---

# /lean — toggle lean mode (token-savings)

切换 anchor lean mode — hook 进入"最少必要输出"模式，**减少 SessionStart 自动注入 + PostToolUse 冗余**。

### What lean mode changes

| Layer | Default | Lean mode |
|---|---|---|
| SessionStart: project contracts list | ✓ inject | ✓ inject (essential) |
| SessionStart: git branch / changed | ✓ inject | ✓ inject (1 line) |
| SessionStart: active-task.md (~60 lines) | ✓ inject 如果存在 | ✗ skip — 用 `cat ~/.anchor/active-task.md` 手动看 |
| SessionStart: preferences.md (~30 lines) | ✓ inject 如果存在 | ✗ skip — 用 `cat ~/.anchor/memory/preferences.md` 手动看 |
| PostToolUse: success case (no issues) | quiet | quiet (no change) |
| PostToolUse: issue case | full report | full report (no change — need details) |
| Stop hook | block in autonomous + pending | block in autonomous + pending (no change) |
| PreToolUse | only emit on block | only emit on block (no change) |

**净效果**：每个 session 节省 ~900 tokens（active-task 600 + preferences 300）+ 0 functional cost.

### Steps

1. **`$ARGUMENTS` = on | off | status**：
   - `on` → `touch ~/.claude/.anchor-lean`
   - `off` → `rm ~/.claude/.anchor-lean`
   - `status` → 报告是否启用 + 估算每 session 节省 / 浪费 token
   - 空 → 等同 `status`

2. **报告效果**：
   ```
   Lean mode: ON
   Effective from next SessionStart.
   Estimated savings: ~900 tokens / session
   
   What's still active:
   - Project contracts list ✓
   - Git branch ✓
   - Autonomous mode flag ✓
   - All 5 hooks (PreToolUse / PostToolUse / SessionStart / Stop / PreCompact)
   - All 21 slash commands
   
   What's suppressed:
   - active-task.md auto-inject (use /resume or cat manually)
   - preferences.md auto-inject (prefs still saved, just not auto-pushed)
   ```

### 什么时候用 lean mode

**Use lean mode for**:
- Short Q&A sessions (< 10 turns)
- Cost-sensitive sessions (Opus pricing)
- 不涉及长任务的对话
- 不需要 prefs 提醒（你已经记得）

**Don't use lean mode for**:
- 长 refactor 多 session 续接
- 新 session 接昨天的 active-task
- 团队上手新 project (需要 prefs auto-inject)

### Toggle by file flag (无需 command)

```bash
touch ~/.claude/.anchor-lean    # lean ON
rm ~/.claude/.anchor-lean       # lean OFF
ls ~/.claude/.anchor-lean 2>/dev/null && echo "lean ON" || echo "lean OFF"
```
