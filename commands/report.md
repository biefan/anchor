---
description: 跨 session 多日聚合报告 (drift heatmap / top blocked patterns / completion rate / hook 触发频率)。Default 30 days. Use for personal retrospective or team review.
argument-hint: "[days=30]"
---

# /report — multi-session aggregate report

跨 session、长时段的 anchor 数据聚合 — 给个人复盘 / 团队 review。

### Steps

1. **跑 `analyze-events.py`** 拿基础统计（输入参数 `$ARGUMENTS` 默认 30）：
   ```bash
   days=${ARGUMENTS:-30}
   python3 ~/.claude/skills/anchor/scripts/analyze-events.py --days $days --json > /tmp/anchor-report.json
   ```

2. **从 JSON 中提取关键 metric**，输出 markdown 报告：

   ```markdown
   # Anchor report (last N days)
   
   ## 概览
   - Sessions: X / Events: Y / Days active: Z
   - Hook 触发率：每 session 平均触发 W 次
   - Tasks completion rate: X% (completed / total)
   
   ## Drift heatmap (top blocked patterns)
   排名前 10 的 PreToolUse 拦截原因 — 反映"想做但被规则拦"的模式：
   | # | Pattern | Count | % | 趋势 |
   |---|---------|-------|---|---|
   ...
   
   ## PostToolUse lint distribution
   按 linter 分布 — 反映项目代码质量入场情况：
   | Linter | Issues found | Trend |
   |---|---|---|
   ...
   
   ## Autonomous mode usage
   - Sessions with autonomous on: X (Y%)
   - Stop hook 拦截次数：A
   - Stop hook 放行次数：B
   - 比率：A:B = ...（越接近 1:1 说明 task list 平均跑完 1 个再 stop）
   
   ## 趋势对比 (此 N 天 vs 前 N 天)
   - Blocks/session 变化：+X% / -X%
   - Top emerging pattern: <pattern with biggest growth>
   - Receding pattern: <pattern with biggest drop>
   
   ## 建议
   <基于以上数据，最有杠杆的 3 个改进点>
   ```

3. **如果 events log 不足 N 天数据**，明确报"only X days observed" 而不是假装数据完整。

### Optional flags

- `/report 7` — 看 7 天（更短期，看本周）
- `/report 90` — 看 季度
- `/report 365` — 看 全年

### Use cases

- **个人周复盘**：`/report 7` 看本周 anchor 帮你拦了哪些惯性操作
- **团队 review**：`/report 30` 看团队 anchor 使用 + 共同 trip up 的 patterns
- **入职 onboarding**：新人看 senior 的 `/report 30` 学习"哪些命令应该 think twice"
