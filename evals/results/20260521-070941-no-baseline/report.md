# Eval results — 20260521-070941-no-baseline

1 eval(s) run. Each prompt was run twice with `codex exec --json`:
with the anchor skill installed, and again after temporarily moving the skills aside.
Discriminators were graded by codex acting as judge.

## Summary

| ID | Name | with-skill | without-skill | delta |
|---|---|---|---|---|
| 3 | pitfall-writeback | 1/4 | 1/4 | 0 |

## Per-eval details

### 3. pitfall-writeback

**With-skill**:
- ❌ `proposes_writing_to_project_claude_md_or_agents_md` — no evidence
- ❌ `uses_structured_four_field_template` — no evidence
- ❌ `explicitly_avoids_code_comments` — no evidence
- ✅ `includes_date_or_file_location_anchor` — `20260521T070956Z-redis-cluster-pipeline-cross-slot.md`

**Without-skill**:
- ❌ `proposes_writing_to_project_claude_md_or_agents_md` — no evidence
- ❌ `uses_structured_four_field_template` — no evidence
- ❌ `explicitly_avoids_code_comments` — no evidence
- ✅ `includes_date_or_file_location_anchor` — `cache/batch.ts:42`