---
description: 锁定当前任务 scope——把用户原话当第一条 task，引导后续拆解。Use when starting any non-trivial coding task to anchor scope before drift.
argument-hint: "[用户原话或任务一句话]"
---

按 `efficient-coding` skill 的"锁 scope"规则执行：

1. **用 TaskCreate 工具**创建第一个 task：
   - subject: `$ARGUMENTS`（用户原话，如果为空就问用户"这次任务的原话是？"）
   - description: "用户原始需求锚点。任何动作只服务下方拆解的 task。"

2. **拆 3-7 个子 task** 用 TaskCreate 依次创建。每个 task：
   - subject 写**可验证的产出**（"实现 X endpoint 返回正确数据 + 通过 curl 测试"），不要写"看看 X"这种模糊状态
   - 覆盖完整路径：调研 → 改动 → E2E → 回写 CLAUDE.md（如适用）

3. **简短报告 task list**，问用户确认 scope 没漏没多再动手。

4. 如果用户启用了 autonomous mode（`~/.claude/.efficient-coding-autonomous` 存在），提醒用户：本任务在自治模式下推进，task 全部完成前不会 stop。

参考：`~/.claude/skills/efficient-coding/SKILL.md` 的"长任务模式：防偏题 + 防记忆衰减"节。
