---
description: 当前 session 的 token / 时长 / 估算成本摘要。Use when you want to know how much this session has spent so far.
---

# /spend — session cost summary

报告当前 session 的资源使用 + 估算成本。

### Steps

1. **如果 `ccusage` (`npx -y ccusage`) 装着**，直接调用拿 session usage：
   ```bash
   npx -y ccusage@latest session --json 2>/dev/null
   ```
   提取 `total_input_tokens`、`total_output_tokens`、`total_cost_usd`、`session_duration`。

2. **否则降级估算**：
   - Transcript size：从 conversation 长度估 token (~4 char/token)
   - 跑过的 tool calls：从 ~/.claude/anchor-events.jsonl 拿 session_id 对应事件数
   - Time elapsed：from session_start event ts → now

3. **价格估算（Claude 4.7 默认费率）**：
   ```
   Opus 4.7:    input $15 / 1M, output $75 / 1M
   Sonnet 4.6:  input $3  / 1M, output $15 / 1M  
   Haiku 4.5:   input $0.80 / 1M, output $4 / 1M
   (cache reads ~10%, prompt caching writes ~25% extra)
   ```

4. **输出**（markdown）：
   ```
   ## Session cost
   
   - Tokens: 123,456 in / 45,678 out (cache 78%)
   - Time: 1h 23m since session start
   - Estimated: $X.XX (Opus 4.7 rate)
   - PreToolUse blocks: 12 (see /status for breakdown)
   - Files touched: 8
   - Tasks completed: 5 / 7
   
   Tips to cut cost:
   - <basic recommendations based on observed pattern>
   ```

5. **建议规则**：
   - cache 命中率 < 50% → 提示"避免频繁切换 working directory / 重启会话"
   - output token 占比 > 40% → "考虑要求更短输出 / 减少 long 解释"
   - 长 session（> 2h）→ "考虑 /save 当前进度 + 新开 session"
   - PreToolUse blocks > 20 → "可能 hook 过严，看 /status hook 详情"

### Not in scope

- 不持久化历史成本（用 `/report` 看跨 session 趋势）
- 不收取 Claude / Codex 真实账单数据（只是估算）
- 不修改任何状态
