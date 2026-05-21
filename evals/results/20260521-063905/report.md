# Eval results — 20260521-063905

5 eval(s) run. Each prompt was run twice with `codex exec --json`:
with the anchor skill installed, and again after temporarily moving the skills aside.
Discriminators were graded by codex acting as judge.

## Summary

| ID | Name | with-skill | without-skill | delta |
|---|---|---|---|---|
| 1 | anti-drift-on-long-task | 1/4 | 1/4 | 0 |
| 2 | multi-pass-vuln-scan | 2/4 | 2/4 | 0 |
| 3 | pitfall-writeback | 1/4 | 2/4 | -1 |
| 4 | e2e-not-just-tests | 2/3 | 2/3 | 0 |
| 5 | intent-clarification | 2/4 | 2/4 | 0 |

## Per-eval details

### 1. anti-drift-on-long-task

**With-skill**:
- ❌ `is_task_list_used` — no evidence
- ❌ `subagent_count_>= 2` — no evidence
- ✅ `no_unrelated_changes` — 当前没有做任何写入
- ❌ `explicit_e2e_step` — no evidence

**Without-skill**:
- ❌ `is_task_list_used` — no evidence
- ❌ `subagent_count_>= 2` — no evidence
- ✅ `no_unrelated_changes` — 因此我没有新增 React 组件、Express 接口或 migration
- ❌ `explicit_e2e_step` — no evidence

### 2. multi-pass-vuln-scan

**With-skill**:
- ✅ `multiple_scan_passes` — 第 1 遍...第 2 遍...第 3 遍
- ✅ `data_flow_analysis_mentioned` — 第 2 遍：数据流追踪
- ❌ `codex_review_suggested` — no evidence
- ❌ `exploit_scenario_per_finding` — no evidence

**Without-skill**:
- ✅ `multiple_scan_passes` — 第二轮确认显示
- ✅ `data_flow_analysis_mentioned` — 建路由和数据流视图
- ❌ `codex_review_suggested` — no evidence
- ❌ `exploit_scenario_per_finding` — no evidence

### 3. pitfall-writeback

**With-skill**:
- ❌ `claude_md_created_or_appended` — no evidence
- ❌ `four_field_structure_used` — no evidence
- ✅ `no_code_comment_solution` — 写成一条 memory 更新 note
- ❌ `date_included` — no evidence

**Without-skill**:
- ❌ `claude_md_created_or_appended` — no evidence
- ✅ `four_field_structure_used` — 项目：/root/skk 文件：cache/batch.ts:42 ... 修复方式：... 经验：...
- ✅ `no_code_comment_solution` — 我会按你的记录要求写一条 ad hoc memory note
- ❌ `date_included` — no evidence

### 4. e2e-not-just-tests

**With-skill**:
- ❌ `real_curl_or_http_test_suggested` — no evidence
- ✅ `second_order_issues_raised` — 成功路径仍然返回 `200`，没有被误改。
- ✅ `no_should_be_ok_handwave` — 还不能确认“可以”。

**Without-skill**:
- ❌ `real_curl_or_http_test_suggested` — no evidence
- ✅ `second_order_issues_raised` — 路由没有吞掉异常，把数据库错误误判成用户不存在
- ✅ `no_should_be_ok_handwave` — 现在我不能确认“可以了”

### 5. intent-clarification

**With-skill**:
- ❌ `asks_question_before_acting` — no evidence
- ❌ `uses_AskUserQuestion` — no evidence
- ✅ `1_to_3_focused_questions` — 请补 3 点：  1. 登录代码在哪个目录或仓库？
- ✅ `no_premature_implementation` — 不能直接猜着改

**Without-skill**:
- ❌ `asks_question_before_acting` — no evidence
- ❌ `uses_AskUserQuestion` — no evidence
- ✅ `1_to_3_focused_questions` — 要继续改，请先补 3 点
- ✅ `no_premature_implementation` — 不能直接猜着改