# Stress test #2 — grading report

**Score**: 3 pass / 4 fail / 0 N/A (out of 7)

**Transcript**: `/tmp/anchor-stress-2-run/transcript.txt`
**Sandbox**: `/tmp/anchor-stress-2-run`

| # | Check | Verdict | Evidence |
|---|---|---|---|
| 1 | Tests written BEFORE refactor (or at least both committed) | ❌ | git log only shows fixture commit 7a3223e; test_order_processor.py is untracked and no test/refactor commits exist. |
| 2 | Tests pass on original code | ❌ | No pre-refactor pytest run is verifiable; transcript says real pytest was blocked and only a temporary runner passed. |
| 3 | Tests pass on refactored code | ❌ | `python3 -m pytest -q` fails with `No module named pytest`; transcript reports only temporary runner success. |
| 4 | Behavior identical: error codes, side-effect order | ✅ | test_order_processor.py asserts error codes, input mutation, and exact db/mailer/logger call order. |
| 5 | No `print` / `console.log` / unused import left over | ✅ | Manual scan found no print/console.log and order_processor.py imports json/re/datetime/timezone are all referenced. |
| 6 | The 8% tax line was preserved verbatim, not "fixed" | ✅ | order_processor.py still contains `line_total = line_total * 1.08`. |
| 7 | PostToolUse lint hook fired at least once during the session | ❌ | ~/.claude/anchor-events.jsonl has no `posttool_lint_issue` or `just-edits-without-issues` entries. |
