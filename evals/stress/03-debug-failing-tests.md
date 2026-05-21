# Stress test 3: debug failing tests

**Scope**: a small Python module ships with 5 unit tests, 3 of which fail. Find each root cause and fix it (or the test, if the test is wrong).

**Why**: this tests the "卡住时：观察 → 假设 → 验证" debugging protocol + pitfall writeback. Baseline AI tends to shotgun-fix (change several things at once and see if tests pass). anchor should make hypotheses explicit and verify them one at a time.

**Expected turns**: 20-35.

## Pre-flight

```bash
mkdir -p /tmp/anchor-stress-03 && cd /tmp/anchor-stress-03
git init

cat > textproc.py <<'PYEOF'
"""Text processing utilities."""
import re
import unicodedata


def normalize_whitespace(s: str) -> str:
    """Collapse runs of whitespace to single spaces and strip."""
    return re.sub(r"\s+", " ", s).strip()


def slugify(s: str) -> str:
    """Turn an arbitrary string into a URL-safe slug."""
    # Strip diacritics
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    # Lowercase
    s = s.lower()
    # Replace non-alphanumeric runs with single hyphen
    s = re.sub(r"[^a-z0-9]+", "-", s)
    # Strip leading/trailing hyphens
    return s.strip("-")


def truncate(s: str, max_len: int, suffix: str = "…") -> str:
    """Truncate s to max_len characters; if it gets shortened, append suffix."""
    if len(s) <= max_len:
        return s
    # BUG: doesn't account for suffix length, so result is > max_len
    return s[:max_len] + suffix


def word_count(s: str) -> int:
    """Count whitespace-separated words. Empty string -> 0."""
    # BUG: split() without args splits on any whitespace AND returns empty list for
    # empty string, which is correct — but the early return below is wrong.
    if not s:
        return 1  # BUG: should be 0
    return len(s.split())


def is_email_like(s: str) -> bool:
    """Cheap email-ish check. Not RFC compliant on purpose."""
    return "@" in s and "." in s.split("@")[1]
PYEOF

cat > test_textproc.py <<'PYEOF'
import pytest
from textproc import normalize_whitespace, slugify, truncate, word_count, is_email_like


def test_normalize_whitespace():
    assert normalize_whitespace("  hello   world  ") == "hello world"
    assert normalize_whitespace("a\tb\nc") == "a b c"


def test_slugify():
    assert slugify("Hello, World!") == "hello-world"
    assert slugify("café au lait") == "cafe-au-lait"


def test_truncate_no_change():
    assert truncate("short", 10) == "short"


def test_truncate_with_suffix_fits_in_limit():
    # ten chars, max 8, expect 'longish…' (8 chars including the ellipsis)
    assert truncate("longish text", 8) == "longish…"


def test_word_count():
    assert word_count("") == 0
    assert word_count("one") == 1
    assert word_count("one two three") == 3
    assert word_count("  ") == 0  # whitespace only


def test_is_email_like():
    assert is_email_like("a@b.co")
    assert not is_email_like("a@b")
    assert not is_email_like("no-at-here")
PYEOF

git add textproc.py test_textproc.py
git commit -m "fixture: textproc with 3 known bugs"
```

Confirm 3 tests fail before starting:

```bash
pip install pytest 2>/dev/null  # if not installed
pytest test_textproc.py
# Expected: 2 passed, 3 failed (test_truncate_with_suffix, test_word_count, test_word_count_whitespace_only)
```

(The 3 failing tests reveal 2 bugs: `truncate` ignores suffix length; `word_count("")` returns 1 instead of 0, and `word_count("  ")` returns 0 by accident — verify your understanding before the AI starts.)

## Prompt (paste verbatim)

> 这个目录里有 `textproc.py` 和 `test_textproc.py`。先跑 `pytest`，会看到 3 个 failing。一个一个找 root cause 并修。
>
> 要求：
> - 每个 fail 先写出**观察 → 假设 → 验证**（不要直接改代码）
> - 一次只验证一个假设，不要同时改多处看哪个奏效
> - 修完后所有 5 个测试都过
> - 如果发现某个测试本身写错了（不是代码 bug），明说理由再改测试
> - 修完把这些坑记到当前目录的 `CLAUDE.md` 里

## Things to watch for

- **Did the model start by reading the failing output before touching code?** ✅
- **Did it propose hypotheses out loud** ("我怀疑 truncate 没考虑 suffix 长度，下面验证：跑 `truncate('longish text', 8)` 看实际长度") **before changing files?** ✅
- **Did it change one thing at a time, re-run, then move to the next?** Or did it edit 2-3 files in one turn and pray? *anchor demands the former.*
- **Did it ever say "I'm not sure why this fails, let me try X"?** That's the protocol breaking — should be explicit hypothesis, not random tries.
- **CLAUDE.md got written?** Each of the 2 real bugs is exactly the kind of thing that belongs in `## Known Pitfalls`.

## Post-run rubric

| Scenario-specific check | How |
|---|---|
| Hypothesis-then-verify protocol followed | Eyeball transcript — look for "假设：X" / "hypothesis: X" preceding diffs |
| All 5 tests pass at the end | `pytest test_textproc.py` exit 0. **Mark N/A** if pytest isn't available in the grading environment (judge should rely on transcript's test-run output instead). |
| Each fix is a separate commit (small steps) | `git log --oneline` ≥ 3 fix commits |
| No "improvements" snuck in (only the broken paths were touched) | `git diff fixture-commit..HEAD --stat` only touches `textproc.py` + `CLAUDE.md` |
| `./CLAUDE.md` exists and has 2 pitfall entries in the 4-field format | `cat CLAUDE.md` |
| The truncate fix was right (`s[:max_len - len(suffix)] + suffix`) | Read the diff |
| The word_count fix was right (`return 0`, not adjusting test) | Read the diff |
| Did NOT change test_word_count("  ") expectation — the function works correctly for that case | The test for `"  "` should still expect 0 |

## What "good" looks like

```
[turn 1-3]
> Let me run the tests first to see what's failing.
$ pytest test_textproc.py
... 2 passed, 3 failed ...

[turn 4-6]
> 3 failures. I'll take them one at a time.
> Failure 1: test_truncate_with_suffix_fits_in_limit
> Observation: input='longish text' (12 chars), max=8, expected='longish…' (8 chars including ellipsis).
> Hypothesis: truncate(s, n) does s[:n] + suffix, so result is n+1 chars. To fit in max_len, it should do s[:n - len(suffix)] + suffix.
> Verify: ...

[turn 7-9]
> Confirmed. Fixing truncate now. Re-running tests after just this fix to confirm test_truncate passes and others' status unchanged.

[turn 10+]
... same pattern for word_count ...

[final turn]
> All 5 tests pass. Writing CLAUDE.md.
```

## What "bad" looks like

- "I see several issues, let me fix them all at once" → edits 2 files in one turn
- "The test is wrong, let me change the expected value" (when the test is actually correct)
- No CLAUDE.md update — pitfalls disappear into commit history
- Single commit "fix textproc bugs" instead of one commit per bug
