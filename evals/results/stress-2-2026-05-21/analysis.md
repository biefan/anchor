# Stress test #2 (refactor-function) — auto-graded run

> First end-to-end demo of v1.3's `grade.py` codex-as-judge auto-scoring against a real stress test run.

## Setup

- Stress test: `evals/stress/02-refactor-function.md`
- Sandbox: `/tmp/anchor-stress-2-run/`
- Fixture: deliberately tangled `order_processor.py` (~80 lines, 6 concerns mixed: parse / validate / price / discount / persist / notify), committed as `7a3223e`
- Agent: `codex exec --json --skip-git-repo-check --sandbox workspace-write` (Codex 0.132.0, GPT-5.4)

## Result

`grade.py` invoked codex-as-judge against the spec's 7 scenario-specific rubric items. Final score: **3/7 pass, 4/7 fail**.

| # | Rubric | Verdict | Why |
|---|---|---|---|
| 1 | Tests committed before refactor (or both committed) | ❌ | Only the fixture commit `7a3223e` exists. The agent edited both files but never staged/committed them. |
| 2 | Tests pass on **original** code | ❌ | The judge couldn't verify because pytest wasn't available in the local environment (PEP 668 blocked install). Agent's transcript claimed they passed via a "temporary runner" — judge correctly refused to take that on faith. |
| 3 | Tests pass on **refactored** code | ❌ | Same as #2. |
| 4 | Behavior identical (error codes, side-effect order) | ✅ | The test file asserts each error code string and the exact `db.execute` → `mailer.send` → `logger.info` order. Faithful coverage. |
| 5 | No `print` / unused imports left behind | ✅ | Manual scan: only `json`/`re`/`datetime`/`timezone` imports, all referenced. No `print(...)`. |
| 6 | 8 % tax line preserved verbatim | ✅ | `grep '1.08' order_processor.py` still hits. Not "improved" to `(1 + 0.08)` or `(1 + TAX_RATE)`. |
| 7 | `PostToolUse` lint hook fired during the session | ❌ | The sandbox runs in `codex exec`, not under Claude Code's hook system. `~/.claude/anchor-events.jsonl` has no relevant entries. (Genuinely N/A here, but the judge defaulted to ❌ since the rubric phrasing assumed in-anchor session.) |

## What the auto-grader caught that a casual reader might miss

The agent's transcript explicitly says "tests pass". A human skimming the transcript would probably check ✅. The judge however reads the spec's rubric ("commits"), cross-references `git log`, sees the fixture commit is the only one, and marks ❌. This is the auto-grader's main value: it's not fooled by the agent's narration, it grounds in observable products (`git log`, file contents, hook event log).

## What this run tells us about anchor's effectiveness here

- **Refactor behavior preservation**: ✅ The agent correctly kept the 8 % tax line, didn't sneak in "improvements", and the tests file asserts the exact side-effect order. The skill's "smallest correct diff" rule landed.
- **Discipline gaps**: ❌ The agent did not commit work in two steps (tests, then refactor). Reading the rubric, that should have been the workflow. The agent saved work but didn't sequence it.
- **Tool-runtime gap**: Two ❌ s are environment-driven (no pytest, hooks not active in `codex exec` runs), not anchor's fault. If we re-run inside a Claude Code session with hooks live, those should pass.

## Suggested follow-up

1. Re-run inside an actual Claude Code session (anchor's natural runtime) and re-grade — items 2/3/7 should flip.
2. Strengthen the spec's rubric items 2 / 3 to handle "judge can't verify locally" without forcing ❌ (allow N/A when toolchain is missing).
3. Consider relaxing rubric item 1 ("commits before refactor") — many agents won't auto-commit unless the prompt explicitly says to; either bake that into the prompt, or treat it as informational not pass/fail.

## Conclusion for v1.3

The `grade.py` pipeline is **demonstrably useful** on the very first run: it caught a real discipline gap (no commit sequencing) that the agent's own narration would have hidden. This is the case for using codex-as-judge over self-reports. Ship `grade.py` + `analysis.md` style follow-ups as the v1.3 deliverable.
