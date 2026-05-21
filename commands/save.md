---
description: 把当前 session 的 task list 持久化到 ~/.anchor/saved-tasks/，供后续 /resume 续接。Use when ending a long task mid-way (computer shutdown, end of day, switching context).
argument-hint: "[label]"
---

# /save — persist task list

把当前 session 的 task list（含状态、subject、关联 sub-tasks）dump 到磁盘，**今后任意 session 用 `/resume` 续接**。

### Steps

1. **拿当前 task list**（用 `TaskList` tool 或 read fs）：
   - Claude Code session 的 task list 在 `~/.claude/tasks/<session_id>/*.json`
   - 用 TaskList tool 直接列也行（更可靠）

2. **生成保存目录**：
   ```bash
   mkdir -p ~/.anchor/saved-tasks
   ```

3. **写文件**：
   - **文件名**：`$ARGUMENTS` 提供则用 `<label>.md`，否则 `<YYYY-MM-DDTHHMM>.md`
   - **格式**：human-readable markdown（不是 raw JSON），第 6 个月看回也能 grok
   
   ```markdown
   # Saved task list — <label>
   
   - Saved: 2026-05-21T14:32 (cwd: /path/to/project)
   - Session: <session_id>
   - User original request: <推断 / 用户原话>
   - Total: X tasks (Y pending / Z in_progress / W completed)
   
   ## Tasks
   
   ### #1 [completed] — <subject>
   <description if any>
   
   ### #2 [in_progress] — <subject>
   <description>
   
   ### #3 [pending] — <subject>
   ...
   ```

4. **报告**：
   - 保存路径
   - 多少 task 已存
   - 提示：`后续用 /resume <label> 续接`

### 不做

- **不**修改当前 task list 状态（保存 = 拷贝，不是移动）
- **不**覆盖已有同名文件，自动加 `.1` / `.2` suffix
- **不**保存 transcript 全文（只 task list 元数据，方便 grep / browse）

### 典型场景

- 下班前长 refactor 没做完 → `/save end-of-day-refactor`
- 切到别项目 → `/save migrate-api` 
- 即将 long compact 担心 task 丢 → `/save before-compact`
- 测试不同方向 → `/save approach-a`，开新 session 试 approach-b
