# Eval results — 20260521-071227-no-baseline

5 eval(s) run. Each prompt was run twice with `codex exec --json`:
with the anchor skill installed, and again after temporarily moving the skills aside.
Discriminators were graded by codex acting as judge.

## Summary

| ID | Name | with-skill | without-skill | delta |
|---|---|---|---|---|
| 1 | anti-drift-on-long-task | 0/4 | 1/4 | -1 |
| 2 | multi-pass-vuln-scan | 0/4 | 1/4 | -1 |
| 3 | pitfall-writeback | 1/4 | 2/4 | -1 |
| 4 | e2e-not-just-tests | 3/4 | 1/4 | +2 |
| 5 | intent-clarification | 4/4 | 4/4 | 0 |

## Per-eval details

### 1. anti-drift-on-long-task

**With-skill**:
- ❌ `explicit_task_breakdown_in_response` — no evidence
- ❌ `splits_work_by_3_domains_frontend_backend_migration` — no evidence
- ❌ `mentions_integration_test_step` — no evidence
- ❌ `no_unrelated_changes_proposed` — no evidence

**Without-skill**:
- ❌ `explicit_task_breakdown_in_response` — no evidence
- ❌ `splits_work_by_3_domains_frontend_backend_migration` — no evidence
- ❌ `mentions_integration_test_step` — no evidence
- ✅ `no_unrelated_changes_proposed` — (codex exec timed out)

### 2. multi-pass-vuln-scan

**With-skill**:
- ❌ `proposes_multiple_scan_passes` — no evidence
- ❌ `mentions_user_input_to_sink_data_flow` — no evidence
- ❌ `suggests_second_review_or_codex_cross_check` — no evidence
- ❌ `findings_include_concrete_exploit_scenarios` — no evidence

**Without-skill**:
- ❌ `proposes_multiple_scan_passes` — no evidence
- ✅ `mentions_user_input_to_sink_data_flow` — 用户可控 URL 被 `requests` 或 `redirect` 使用
- ❌ `suggests_second_review_or_codex_cross_check` — no evidence
- ❌ `findings_include_concrete_exploit_scenarios` — no evidence

### 3. pitfall-writeback

**With-skill**:
- ❌ `proposes_writing_to_project_claude_md_or_agents_md` — no evidence
- ❌ `uses_structured_four_field_template` — no evidence
- ❌ `explicitly_avoids_code_comments` — no evidence
- ✅ `includes_date_or_file_location_anchor` — `cache/batch.ts:42`

**Without-skill**:
- ❌ `proposes_writing_to_project_claude_md_or_agents_md` — no evidence
- ✅ `uses_structured_four_field_template` — 包含症状、触发条件、修复点和相关文件位置
- ❌ `explicitly_avoids_code_comments` — no evidence
- ✅ `includes_date_or_file_location_anchor` — cache/batch.ts:42

### 4. e2e-not-just-tests

**With-skill**:
- ✅ `explicitly_says_unit_tests_alone_insufficient` — 不只依据“单测过了”来判断
- ❌ `suggests_real_http_or_curl_test` — no evidence
- ✅ `raises_at_least_one_second_order_concern` — 成功路径 `GET /api/users/:id` 仍返回 `200`
- ✅ `no_handwave_should_be_ok` — 现在不能确认“可以了”

**Without-skill**:
- ❌ `explicitly_says_unit_tests_alone_insufficient` — no evidence
- ❌ `suggests_real_http_or_curl_test` — no evidence
- ❌ `raises_at_least_one_second_order_concern` — no evidence
- ✅ `no_handwave_should_be_ok` — 还不能确认“可以”。

### 5. intent-clarification

**With-skill**:
- ✅ `asks_at_least_one_clarifying_question` — 先确认 3 个点，你回数字/选项就行
- ✅ `questions_cover_scope_or_symptom_or_expectation` — 改哪个登录？ / 要改什么？ / 现在的问题是什么？
- ✅ `offers_concrete_options_to_pick_from` — A. 后台管理登录 / B. 用户端登录 / C. API 登录接口 / D. 具体文件/页面你发路径
- ✅ `no_implementation_code_before_clarification` — 给我这三个答案后我再动代码

**Without-skill**:
- ✅ `asks_at_least_one_clarifying_question` — 先确认 3 点，你回选项即可
- ✅ `questions_cover_scope_or_symptom_or_expectation` — 1. 改哪个登录？ ... 2. 要改什么？ ... 3. 期望怎么验收？
- ✅ `offers_concrete_options_to_pick_from` — A. 用户端登录  B. 管理后台登录  C. API 登录接口
- ✅ `no_implementation_code_before_clarification` — 现在信息不够，而且当前 sandbox 里没有业务源码可直接定位登录实现