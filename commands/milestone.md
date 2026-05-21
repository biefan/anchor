---
description: 标记当前 task list 状态为 milestone — 写入 task list 分隔 + 更新 ~/.anchor/active-task.md。Use to mark "phase X done" in multi-day work.
argument-hint: "<milestone-name>"
---

# /milestone — mark a phase done in long task

把当前 task list 状态固化为一个 milestone，**用于多日 / 多 session 任务**的进度锚点。

### Steps

1. **`$ARGUMENTS` 必填** — milestone 名（短描述）。如果空，提示用户提供。

2. **新建一个 completed task** 作为 milestone marker：
   ```
   TaskCreate(subject=f"🏁 MILESTONE: {name}", description="<auto: 哪些 task 在此之前完成>", status="completed")
   ```
   把它插在 task list 当前位置 — 形成 visual divider。

3. **更新 `~/.anchor/active-task.md`**：
   ```bash
   mkdir -p ~/.anchor
   # 写入 / 追加 milestone section
   ```
   格式：
   ```markdown
   ## Milestone history
   
   ### 2026-05-22T14:32 — extracted parse module
   - Branch at this point: feat/order-refactor (commit a3b2c1d)
   - Tasks completed since previous milestone: #1, #2, #3
   - Modified files: src/order-service.ts, src/parse.ts, tests/parse.test.ts
   - Key decisions: 用 snapshot tests 而不是 unit tests
   - Next phase: extract validate module
   ```

4. **如果是这次 session 的第一个 milestone**，**还**应该写"当前阶段"section（顶部）：
   ```markdown
   ## 当前阶段 (last updated: 2026-05-22T14:32)
   
   ### Locked task
   "<用户最初的 /lock 原话>"
   
   ### Current branch
   <git branch --show-current>
   
   ### Last milestone
   {name} — 2026-05-22T14:32
   
   ### Open questions
   - (any)
   ```

5. **报告**：
   - milestone 名 + 写入路径
   - 已 completed tasks 数 / total
   - 提示：明天 `/recap` 或 `/resume-task-task` 时 SessionStart hook 会自动注入这些信息

### 不做

- **不**改其它已有 task 的 status
- **不**自动 git tag / commit（user 自己决定）
- **不**列敏感细节进 active-task.md（grep 时可读）

### 典型用法

```
/lock 把 order-service 拆成 6 个模块
# (干 phase 1)
/milestone extracted parse module
# (干 phase 2)
/milestone extracted validate module
# 收工 → /save end-of-day
# 第二天 /resume-task，SessionStart 注入会显示"上一个 milestone: extracted validate module"
```
