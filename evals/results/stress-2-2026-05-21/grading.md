# Stress test #2 — grading report

**Score**: 3 pass / 1 fail / 3 N/A (out of 7)

**Transcript**: `/tmp/anchor-stress-2-run/transcript.txt`
**Sandbox**: `/tmp/anchor-stress-2-run`

| # | Check | Verdict | Evidence |
|---|---|---|---|
| 1 | Tests written BEFORE refactor (or at least both committed) | ❌ | git log only shows `7a3223e fixture: tangled order processor`; `order_processor.py` is modified and `test_order_processor.py` is untracked. |
| 2 | Tests pass on original code | — | `python3 -m pytest -q` fails in the grading environment with `No module named pytest`. |
| 3 | Tests pass on refactored code | — | `python3 -m pytest -q` fails in the grading environment with `No module named pytest`. |
| 4 | Behavior identical: error codes, side-effect order | ✅ | `test_order_processor.py` asserts exact error codes plus ordered `db.fetchone`, `db.execute`, `mailer.send`, and `logger.*` call lists. |
| 5 | No `print` / `console.log` / unused import left over | ✅ | Manual inspection found no `print`/`console.log`; `json`, `re`, `datetime`, and `timezone` are all referenced in `order_processor.py`. |
| 6 | The 8% tax line was preserved verbatim, not "fixed" | ✅ | `order_processor.py:42` still contains `line_total = line_total * 1.08`. |
| 7 | PostToolUse lint hook fired at least once during the session | — | Transcript is a Codex-style run and no `/tmp/anchor-stress-2-run` hook entry exists; Claude Code PostToolUse hook is not applicable. |
