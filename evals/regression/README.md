# PreToolUse hook regression tests

Per-audit-round regression suites for `skills/efficient-coding/scripts/pre-tool-danger.sh`.

| File | Origin | Count | Coverage |
|---|---|---|---|
| `test-v1.4.0-history.sh` | codex pass 1 + 2 + 12 historical | 32 | B1-B19 + classic regressions |
| `test-v1.4.1-codex-r3.sh` | codex pass 3 | 15 | C1-C11 (shlex unspaced / shell -c / xargs stdin) |
| `test-v1.4.2-codex-r4.sh` | codex pass 4 | 25 | E1-E11 + regressions (target glob / heredoc absent / wrappers) |
| `test-v1.4.3-codex-r5.py` | codex pass 5 + self r3 | 18 | G1-G7 + F14-F16 (heredoc body / flock-c / docker/kubectl/ssh) |
| `test-v1.4.4-codex-r6.py` | codex pass 6 + self r4 H-set | 21 | codex-r6 1-7 + container/orchestrator wrappers |
| `test-v1.4.4-git-cp-mv.py` | self r4 J/L sets | 15 | git destructive / git config injection / cp/mv to system |
| `test-v1.4.5.py` | user-reported round 7 | 10 | runuser/doas/su -c variants + B2 |
| `test-v1.4.6.py` | user-reported round 8 | 9 | mv to block device + git -c '!cmd' prefix |
| `test-v1.4.7-pipe.py` | user UX feedback | 17 | pipeline-to-shell false-positive reduction |

**Total**: 162 regression cases across 9 files, 10 audit rounds.

## Running

From repo root:

```bash
# Individual suites
bash evals/regression/test-v1.4.0-history.sh
python3 evals/regression/test-v1.4.3-codex-r5.py

# All
for f in evals/regression/test-*.sh; do bash "$f"; done
for f in evals/regression/test-*.py; do python3 "$f"; done
```

## CI

These are also wired into `.github/workflows/ci.yml` — the `pretool-regression` job runs every suite on every PR / push to main.

## Adding new tests

When future audit rounds find new bypasses:

1. Add fix to `skills/efficient-coding/scripts/pre-tool-danger.sh`
2. Add new test file `evals/regression/test-v<version>-<round>.{sh,py}` matching the pattern
3. Update this README's table
4. Reference the round in `CHANGELOG.md`

## Audit history (high-level)

| Round | Release | Found | Notes |
|---|---|---|---|
| External review | v1.3.6 | 12 (修 10) | shell-into-python injection |
| Self-audit r1 | v1.3.7 | 5 | same patterns missed in fresh-install branch |
| Codex r1 | v1.3.8 | 15 | first PreToolUse bypass class (substitution + pipe segment) |
| Codex r2 | v1.4.0 | 19 | wrapper / quoting / obfuscation; rewrite around shlex |
| Codex r3 | v1.4.1 | 19 | shlex unspaced / shell -c / xargs stdin |
| Codex r4 | v1.4.2 | 20 | target glob / subshells / wrappers; self r2 contributed 5 |
| Codex r5 | v1.4.3 | 10 | heredoc / flock-c / script-c / docker/kubectl/ssh; ROI down |
| Codex r6 | v1.4.4 | 23 | wrapper schema details + container wrappers + git destructive |

Cumulative: **123 bugs across 8 audit rounds**, 126 regression cases as the test floor.
