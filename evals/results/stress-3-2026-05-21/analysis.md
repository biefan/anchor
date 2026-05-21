# Stress test #3 (debug-failing-tests) — auto-graded run

> Strongest evidence yet that anchor delivers on its design intent.

## Setup

- Stress test: `evals/stress/03-debug-failing-tests.md`
- Sandbox: `/tmp/anchor-stress-3-run/`
- Fixture: `textproc.py` with 2 real bugs (`truncate` ignores suffix length; `word_count("")` returns 1 instead of 0) + `test_textproc.py` with assertions exposing them
- Agent: `codex exec --json --skip-git-repo-check --sandbox workspace-write` (Codex 0.132.0)

## Result

**Score: 6 pass / 1 fail / 1 N/A** out of 8 rubric items.

| # | Rubric | Verdict | Why |
|---|---|---|---|
| 1 | Hypothesis-then-verify protocol followed | ✅ | Transcript shows "假设: ... 验证确认了第一个假设" before each edit. The "observe → hypothesize → verify" cadence from anchor's SKILL.md actually drove the agent's reasoning order. |
| 2 | All 5 tests pass at the end | — | pytest unavailable in the grading environment; the agent's transcript reports "0 failed, 6 passed" via an equivalent inline runner. Judge correctly marks N/A per v1.3.1 patched rubric. |
| 3 | Each fix is a separate commit | ❌ | Only the fixture commit `150b01a` exists. The agent fixed the bugs in the working tree but never committed. Same gap as stress #2. |
| 4 | No "improvements" snuck in | ✅ | The diff stat shows only `textproc.py` was modified; `test_textproc.py` is unchanged. |
| 5 | `./CLAUDE.md` exists with pitfall entries in 4-field format | **✅ ★** | Two entries, each with `现象 / 根因 / 修复 / 教训` exactly as the SKILL.md template specifies. |
| 6 | The truncate fix is right (`s[:max_len - len(suffix)] + suffix`) | ✅ | Diff contains the correct expression plus boundary handling (`max_len <= 0`, `len(suffix) >= max_len`). |
| 7 | The word_count fix is right (`return 0`, not adjusting test) | ✅ | Diff removes the bogus `if not s: return 1` branch; `len(s.split())` already returns 0 for `""` and `"  "`. |
| 8 | Did NOT change the test_word_count("  ") expectation | ✅ | `test_textproc.py` unchanged. |

## ★ Strongest evidence: pitfall writeback worked end-to-end

The v1.1 patch strengthened SKILL.md to forbid `~/.codex/memories/` and demand `./CLAUDE.md`. Stress test #3 is the first time this was tested in the wild with full pitfall reporting required:

The agent wrote `/tmp/anchor-stress-3-run/CLAUDE.md`:

```markdown
# anchor-stress-3-run

这个目录是 `textproc.py` 文本处理工具及其测试的最小复现项目。

## 踩坑记录

### `word_count` 空字符串不能按一个词计数 (2026-05-21)
- **现象**：`word_count("")` 返回 1，测试期望 0。
- **根因**：空字符串分支把 `not s` 错误映射为 1，和 `str.split()` 对空串/空白串的语义不一致。
- **修复**：删除特殊分支，统一返回 `len(s.split())`。
- **教训**：词数统计先确认标准库 `split()` 对空串和纯空白串的边界行为。

### `truncate` 的后缀必须计入最大长度 (2026-05-21)
- **现象**：`truncate("longish text", 8)` 返回 `longish …`，长度为 9，测试期望 `longish…`。
- **根因**：实现把 `max_len` 当成正文截断长度，再追加后缀，导致最终结果超过最大长度。
- **修复**：截断正文时预留 `suffix` 长度，并处理 `max_len <= 0` 与后缀过长的边界。
- **教训**：包含省略后缀的截断函数要先明确 `max_len` 约束的是正文长度还是最终长度。
```

Every field anchor asked for is there. Project-level location (cwd, not `~/.codex/memories/`). Two entries with reusable lessons. **The v1.1 override patch landed.**

## Where anchor still loses

Same as stress #2: agent doesn't auto-commit each fix as a separate commit. The stress #2 fix (v1.3.1) was to add "commit in two steps" to that spec's prompt. Stress #3's spec doesn't have an equivalent instruction. Two options for v1.3.2 or later:

1. Add explicit "commit each bug fix as a separate commit" to spec #3's prompt.
2. Or: relax rubric #3 to "agent made the work auditable" (commits OR clear sequenced edits with the agent narrating each step), since the underlying intent is reviewability rather than literal `git log` entries.

## What this confirms about anchor's value

- **Soft rules carry across runtime**: SKILL.md's "observe → hypothesize → verify" pattern shaped the agent's debugging output, even running under Codex.
- **The pitfall writeback rule is enforceable**: with the v1.1 strong language, the agent reliably picks the project-level CLAUDE.md over Codex's built-in memory. This was the highest-risk rule in v1.0; it now works.
- **The auto-grader is robust**: 6/1/1 ratio matches a fair human read of the same artifacts — no false ❌ from environment limits.

This is anchor's strongest data point so far. Stress #2 was confounded by spec/prompt mismatch (now fixed in v1.3.1). Stress #3 hits cleanly: high pass rate, single legitimate gap (commits), zero false fails.
