---
description: 从 ~/.anchor/saved-tasks/ 读出之前 /save 的 task list，用 TaskCreate 在当前 session 重建。Use to pick up a previously-saved long task.
argument-hint: "[label]"
---

# /resume-task — restore saved task list

读出 `/save` 持久化的 task list，在**当前 session** 重建。

### Steps

1. **如果没有 `$ARGUMENTS` (label)**：
   - List `~/.anchor/saved-tasks/*.md` 按时间倒序
   - 显示给用户选 (number 1, 2, 3...)
   - 等待用户回应再 proceed

2. **拿到 label 后**：
   - Read `~/.anchor/saved-tasks/<label>.md`
   - 解析 task list 节
   - 显示给用户预览（"将要 resume 这些 task: ..."）
   - 等用户确认 "yes / 续上"

3. **重建 task list**：
   - 对每个 task 用 `TaskCreate` 工具创建新 task
   - 保持原 subject / description / status
   - **不**重建已 completed 的（否则当前 session 显示有"已完成"task 是 misleading）—— **可选**：用户回应 "include completed too" 才加

4. **报告**：
   - 多少 task 已 resume
   - 用 `TaskList` 列当前 session 的新 task list
   - **明确告知**：之前 session 的 task 文件还在原 path（没 mv，只 cp），如果不想保留可以删

### 如果原 saved 文件含敏感信息

- 用户可以在 resume 之前手动 `cat ~/.anchor/saved-tasks/<label>.md` 看
- Resume 不 prompt 任何系统外内容 — 只 list 元数据

### 典型场景

- 早上接昨天的活：`/resume-task end-of-day-refactor`
- Compact 之后丢上下文：`/resume-task before-compact`
- 切回主项目：`/resume-task migrate-api`
- 选不同 approach：`/resume-task approach-a`（替代 approach-b 的 session）

### 不做

- **不**在当前 session 已有 task 时**自动覆盖** — 先警告 + 让用户选 "merge / replace / cancel"
- **不**修改 saved file（resume 是只读 + 重建，不是 move）
