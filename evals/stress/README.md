# Stress tests — long-task scenarios

Short Q&A evals (in `evals/evals.json`) measure single-response behavior.
**Stress tests measure multi-turn behavior** — 30+ turns, real code changes, actual hooks firing — which is where anchor's structural value (task list anchoring, autonomous mode, hook enforcement) actually pays off.

Each stress test below is a **prompt template you paste into a fresh Claude Code or Codex CLI session**. After the session ends (whether by completion or by you interrupting), you grade it against the **post-run rubric** at the bottom of each file.

## How stress tests differ from regular evals

| | `evals/run.py` short evals | `evals/stress/*.md` stress tests |
|---|---|---|
| Turn count | 1-3 turns | 20-60+ turns |
| Measures | single-response behavior (asks question? lists vuln types?) | workflow behavior over a session (locked scope? wrote CLAUDE.md? hooks fired?) |
| Automation | `python3 evals/run.py --all` runs everything | manual — start a session, paste prompt, then `python3 evals/stress/grade.py` after |
| Cost per run | ~5 min × 5 evals = ~25 min | ~30-60 min × 3 tests = ~3 hours |
| What it surfaces | obvious skill misses | drift / forgotten gates / hook UX issues |

## Pre-flight (do once before any stress test)

```bash
# 1. Reset event log so we can isolate this run
mv ~/.claude/anchor-events.jsonl ~/.claude/anchor-events.jsonl.before-stress-$(date +%s) 2>/dev/null || true

# 2. Make sure anchor is fully installed (skill + commands + hooks)
cd ~/anchor  # or wherever you cloned
./install.sh

# 3. Decide autonomous mode for this run. If you want to test the Stop hook:
touch ~/.claude/.efficient-coding-autonomous

# 4. Start a fresh Claude Code session in a scratch dir
mkdir -p /tmp/anchor-stress-run-$(date +%s) && cd /tmp/anchor-stress-run-*

# 5. Now paste one of the prompts below
```

## Three stress tests

| ID | File | What it tests |
|---|---|---|
| 1 | [`01-scaffold-mini-project.md`](01-scaffold-mini-project.md) | scope locking + multi-domain parallelism + E2E gate on a new feature build (~40 turn) |
| 2 | [`02-refactor-function.md`](02-refactor-function.md) | smallest-correct-diff + behavior preservation + lint discipline on a refactor (~20 turn) |
| 3 | [`03-debug-failing-tests.md`](03-debug-failing-tests.md) | observe-hypothesize-verify protocol + pitfall writeback on debugging (~30 turn) |

## Post-run grading (the universal rubric)

After any stress test, run:

```bash
python3 ~/anchor/skills/efficient-coding/scripts/analyze-events.py --all > /tmp/anchor-events-this-run.md
git -C /tmp/anchor-stress-run-* status --short
git -C /tmp/anchor-stress-run-* diff --stat
ls /tmp/anchor-stress-run-*/CLAUDE.md 2>&1
```

Score against this checklist (each test's file has scenario-specific extras):

| Anchor behavior | How to verify | Pass? |
|---|---|---|
| Used TaskCreate / equivalent task list to anchor scope | Look at the session transcript for an early `TaskCreate` call (or `plan` tool in Codex) referencing the user prompt | ✅ / ❌ |
| Read project contracts before coding | If a `CLAUDE.md` / `AGENTS.md` was present, was it Read'd in the first few turns? | ✅ / ❌ / N/A |
| Parallelized independent work | Was there at least one turn with 2+ Read/Bash/Agent calls in the same message? | ✅ / ❌ |
| Smallest correct diff | `git diff --stat`: are all changed files inside the stated scope, or did things leak (touched unrelated files / 顺手 refactored)? | ✅ / ❌ |
| Ran E2E or admitted it couldn't | Did the model curl / start dev server / run tests, or explicitly say "I can't run X here, please verify with <command>"? | ✅ / ❌ |
| Wrote pitfall to project CLAUDE.md (if applicable) | `cat CLAUDE.md` in the scratch dir — does it have a new "Known pitfalls" entry, in the 4-field format? | ✅ / ❌ / N/A |
| Hook events recorded | `~/.claude/anchor-events.jsonl` has session_start + (in autonomous mode) Stop attempts | ✅ / ❌ |
| Autonomous mode behavior (if enabled) | Stop hook events visible in the log; the session didn't terminate while tasks were `pending` | ✅ / ❌ / N/A |

A score of **6/8 or better** is anchor doing its job. Below that, look at the transcript to find which rule the model dropped and **file a real issue** against this repo with the transcript + ec-status output.

## Optional: turn this into automated tests later

These stress tests are deliberately manual right now — long-task automated grading is hard (the rubric items are partly subjective). If the project grows, an obvious next step is to take the `analyze-events.py` JSON + `git diff --stat` + transcript and feed them through a codex-as-judge pass like `evals/run.py` does for short evals. Out of scope for v1.2.
