---
description: 看 task list 下一步是什么，把下一个 pending task 标 in_progress 并报告它的 description
argument-hint: ""
---

执行以下动作推进任务进度：

1. 跑 `TaskList` 拿到当前所有 task。

2. 找到第一个 `status: pending` 的 task（按 ID 顺序，或者 blockedBy 已清的）。

3. 用 `TaskUpdate` 把它标为 `in_progress`。

4. 报告：
   - 刚完成的（如果有刚 completed 的）
   - 当前激活：task #N — subject
   - description 的详细要求
   - 剩余 task 数

5. 如果没有 pending task：
   - 所有 task 都 completed → 提示用户可以 `/done` 走完成检查
   - 有 in_progress 但没 pending → 报告当前 in_progress 是什么，提示推进它

6. 如果没有任何 task list：提示用户用 `/lock <原话>` 先锁 scope。

**重要**：本命令只切换状态 + 报告，**不开始执行**新 task。让用户/Claude 看到下一步是什么，再决定怎么做。
