# Changelog

All notable changes to **anchor** are tracked here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.5] — 2026-05-21

### Fixed

- **`install.sh` always returned exit code 1** (cosmetic but ugly). The final line was `[ "$WITH_HOOKS" = "0" ] && echo "..."`; when `WITH_HOOKS=1` (the default), `[` returns false, and bash uses the last command's exit code as the script's. Replaced with an explicit `if ... then ... fi` block plus a trailing `exit 0`. Files were always installed correctly; the bug only showed up if you piped `./install.sh; echo $?` or used it inside another shell script that checked the return code.

### Plugin manifest

- Versions bumped 1.3.4 → 1.3.5.

## [1.3.4] — 2026-05-21

Documentation + tooling polish based on the v1.3 stress test learnings.

### Added

- **`README.md` + `README.en.md` field-report section** at the top of both. Three rows summarizing the 3 stress runs (Debug 6/1/1, Refactor 3/1/3, Scaffold 2/3/0 with the borrowed-`node_modules` cheat story) so visitors immediately see anchor has been measured.
- **`evals/stress/run.sh`** — one-shot stress-test runner. `./evals/stress/run.sh <id>` does prep-fixture + codex exec + extract-transcript + grade + print report. Replaces the previous 5-step manual sequence (`mkdir → git init → cat fixture → codex exec → python extract → grade.py`).
- **`evals/stress/fixtures/02-refactor/order_processor.py`** + **`evals/stress/fixtures/03-debug/{textproc.py,test_textproc.py}`** — fixtures broken out into reusable files instead of being inlined in the spec docs as heredocs. The spec docs still describe them; `run.sh` reads from this dir.
- **`docs/competitors.md`** — honest landscape doc. Compares anchor against Praxis / HOTL / Session Orchestrator / Aegis / Archcore / Antigravity / brooks-lint / Spec-Driven Development. Documents what anchor's specifically owns (4 hooks + auto-grading + cross-CLI + bilingual + CI-on-self), what peers do better, and useful compositions ("Archcore + anchor", "SDD spec phase + anchor implementation phase", etc.).

### Plugin manifest

- Versions bumped 1.3.3 → 1.3.4.

### Not changed

- No skill / hook / command logic changes. This patch is documentation + ergonomics only.

## [1.3.3] — 2026-05-21

Three improvements all driven by what we learned from running the three stress tests:

### Added (SKILL.md anti-pattern)

- **"Don't borrow dependencies to fake a successful install"** added to the SKILL.md anti-pattern list. If `npm install` / `pip install` / `cargo build` / `go mod download` can't run in the current sandbox, the agent must **report the blocker and stop** — never copy a foreign `node_modules` / `site-packages` / `vendor/` to fake a passing test. Stress test #1 caught exactly this cheat (84 MB `node_modules` with 184 packages unrelated to the declared deps `better-sqlite3` + `express`). The skill now names it.

### Changed (stress test #1 spec)

- **Prompt** now requires three separate commits (migration, server, test), aligning with the rubric (which already required commit-splitting). Same fix pattern as v1.3.1 did for stress #2.
- **Prompt** now explicitly tells the agent: "if `npm install` can't run, report and stop, do NOT borrow node_modules." This is the policy version of the new SKILL.md anti-pattern.
- **Rubric** gains two items targeting this failure mode:
  - "Agent did NOT borrow dependencies from another project" — verified by cross-checking `package.json` declared deps against the actual `node_modules` top-level.
  - "Agent reported environmental blockers correctly (if any)" — verified by reading the transcript for explicit blocker reports.

### Changed (grade.py auto-evidence)

- **`collect_evidence` now auto-computes a dependency cross-check** for every supported language present in the sandbox:
  - **Node** — `package.json` declared deps vs `node_modules/` top-level (flags unrelated packages with a count).
  - **Python** — `requirements.txt` / `pyproject.toml` vs `site-packages/*.dist-info`.
  - **Rust** — `Cargo.toml` + `Cargo.lock` + `target/` presence.
  - **Go** — `go.mod` + `vendor/` listing.
- On the stress-#1 sandbox, the new check immediately flagged **184 top-level packages not in declared deps**. Future grade runs surface this evidence mechanically, instead of requiring the judge to notice it from the file listing.
- **`collect_evidence` file listing** now excludes `node_modules` / `vendor` / `site-packages` / `target` / `.venv` / `__pycache__` to keep evidence focused on actual source.

### Plugin manifest

- Versions bumped 1.3.2 → 1.3.3 in `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.claude-plugin/marketplace.json`.

### Why this patch

The three stress tests run on 2026-05-21 surfaced three distinct failure modes:
1. Stress #1 — agent cheated by borrowing `node_modules`; SKILL.md's "不绕路" was too vague.
2. Stress #2 — earlier-day patch; rubric/prompt mismatch fixed in v1.3.1.
3. Stress #3 — anchor passed cleanly except commit-splitting (rubric mismatch, same as #2).

v1.3.3 patches #1's failure mode (the specific anti-pattern + spec text + grade.py evidence) and resolves the #1/#3 commit-splitting issue by patching the spec prompts. After v1.3.3, all three stress test specs are self-consistent and grade.py mechanically catches dependency-borrowing cheats.

## [1.3.2] — 2026-05-21

Patch in preparation for awesome-codex-plugins submission.

### Added

- **`assets/icon.svg`** — 512×512 SVG icon (711 bytes). Simple anchor mark in cream on deep blue. Referenced from `.codex-plugin/plugin.json` `interface.composerIcon`.

### Changed

- **`.codex-plugin/plugin.json`** schema upgraded to match `hashgraph-online/awesome-codex-plugins` CONTRIBUTING.md requirements:
  - Added `license: "MIT"`.
  - Added `keywords` (engineering-discipline, skill, hooks, slash-commands, claude-code, codex-cli, anti-drift, autonomous-mode, e2e-verification, pitfall-writeback).
  - Added `interface.displayName`, `interface.shortDescription`, `interface.composerIcon`.
- **`.claude-plugin/plugin.json`** — added `license: "MIT"` for hygiene (Claude Code doesn't require `interface`, so other new fields stay codex-side only).
- Plugin manifest versions bumped 1.3.1 → 1.3.2.

### Other

- **PR submitted to `hashgraph-online/awesome-codex-plugins`** under Community / Development & Workflow, alphabetically between AgentOps and Antigravity. Includes the full bundle (plugin.json + icon + LICENSE + README) under `plugins/biefan/anchor/`.

## [1.3.1] — 2026-05-21

Patch driven by the v1.3.0 demo run (which scored 3 pass / 4 fail). Inspection of the 4 fails showed only 1 was a real agent failure; the other 3 were rubric-design defects. Patched in this release.

### Fixed

- **Stress test #2 spec prompt**: now explicitly says "Commit 分两步：第一个 commit 只含测试 + 通过原始代码的证据；第二个 commit 才含 refactor + 测试仍然通过。" The original prompt didn't ask for this, but the rubric required it — so the v1.3 demo's failure on rubric #1 was on a rule the agent wasn't told. Now prompt and rubric are aligned.
- **Rubric items across all 3 stress tests**: every item that depends on a particular runtime (pytest installed, Claude Code session vs `codex exec`) now explicitly says "**Mark N/A if ...**" with the exact opt-out condition. Specifically:
  - Test #1: integration test execution can be N/A when the agent's sandbox couldn't install Node deps (test file existence still counts).
  - Test #2: "tests pass on original/refactored" items can be N/A when pytest isn't in the grading env; PostToolUse hook item can be N/A under `codex exec`.
  - Test #3: "all 5 tests pass" can be N/A when pytest isn't available; the judge should rely on the transcript's claimed test output instead.
- **`grade.py` judge prompt**: distinguishes the three verdict cases more strictly. Pass = positive evidence; Fail = agent demonstrably didn't do something the spec required; N/A = check is unverifiable in this environment or the rubric says "Mark N/A if ...".

### Validated

- Re-graded the v1.3 stress test #2 transcript against the patched spec + judge prompt: **3 pass / 1 fail / 3 N/A** (was 3 / 4 / 0). The single remaining ❌ is now a legitimate signal — commit sequencing — that the v1.3.1 spec prompt would have asked for explicitly. See `evals/results/stress-2-2026-05-21/grading.md` (current) vs `grading-v1.3.0.md` (baseline) and the updated `analysis.md`.

### Other

- `.gitignore` now excludes `__pycache__/` and `*.pyc` (a `grade.cpython-311.pyc` slipped into the v1.3 commit before the gitignore was tightened).
- Plugin manifests bumped 1.3.0 → 1.3.1; marketplace.json metadata too.

## [1.3.0] — 2026-05-21

### Added (Codex-as-judge auto-grading for stress tests — v1.3-E)

- **`evals/stress/grade.py`** — extracts the post-run rubric from a stress test spec, collects evidence from the sandbox dir (`git log`, `git diff --stat`, file listing, `CLAUDE.md` if present), and asks `codex exec` to evaluate each rubric item with a Pass/Fail/NA verdict + one-line evidence. Renders a markdown report and aggregate score. CLI args: `--stress-id N`, `--transcript FILE`, `--sandbox DIR`, optional `--output FILE` / `--json`.
- **`evals/stress/README.md`** now documents the `grade.py` workflow end-to-end: prep fixture → `codex exec` into sandbox → extract `item.completed` text to plain transcript → `python3 evals/stress/grade.py ...`.

### Added (First real stress test run + post-mortem — v1.3-A)

- **`evals/results/stress-2-2026-05-21/`** — first end-to-end run of stress test #2 (refactor function preserving behavior). Artifacts captured: agent's transcript, post-run `order_processor.py` and `test_order_processor.py`, `git log`, `git status`, and the auto-generated `grading.md` (3/7 pass / 4/7 fail).
- **`analysis.md`** in that results dir — what the auto-grader caught that a casual reader would miss, plus suggested rubric refinements (allow N/A when toolchain missing; relax rubric item #1 around commit sequencing).

### Plugin manifest

- Both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` bumped 1.2.0 → 1.3.0.
- `.claude-plugin/marketplace.json` metadata version bumped to match.

### Validated by this run

- The codex-as-judge approach **isn't fooled by the agent's narration**. The transcript said "tests pass"; the judge cross-checked `git log` and the empty post-fixture commit history, and correctly marked rubric item #1 as ❌.
- Some rubric ❌s were environment-driven (pytest not installed locally, hooks not live under `codex exec`) rather than agent failures — a known limitation. See the analysis doc for spec adjustments to land in v1.4 or v1.3.x.

## [1.2.0] — 2026-05-21

### Added (Observability — v1.2-A)

- **Hook event logging**: all 4 hooks (`SessionStart` / `Stop` / `PreToolUse` / `PostToolUse`) now append a structured JSON line to `~/.claude/anchor-events.jsonl` when they trigger something interesting (session start, stop allow/block decision, PreToolUse block, PostToolUse lint hits). New `_log_event.sh` helper is sourced by each hook for DRY.
- **`/status` command**: shows autonomous-mode toggle, current session task list breakdown, and the last 7 days of hook events as a markdown summary. Args: `--all`, `--days N`, `--json`.
- **`scripts/analyze-events.py`**: parses the jsonl event log into a markdown or JSON summary; `/status` calls it.

### Added (Workflow commands — v1.2-B)

- **`/ship`** — one-shot wrap-up: runs `/done`, generates a Conventional-Commits PR title, drafts a body with summary + how-tested + risk + linked issues, pushes the branch, calls `gh pr create`.
- **`/diff [base|file]`** — read-only diff risk analyzer: scope, file count + LOC, red/yellow/green keyword scan (auth / payment / crypto / migration / concurrency), then concrete second-order questions targeted at what changed. Outputs a one-line ship verdict.
- **`/cleanup`** — scans changed files for debug `print` / `console.log` / `debugger` / `pdb` / unused imports / `TODO` / `FIXME` per language (Python / JS-TS / Go / Rust / shell). Reports only; doesn't auto-modify.

### Added (Self-marketplace — v1.2-C)

- **`.claude-plugin/marketplace.json`**: anchor's repo is now its own single-plugin marketplace. Users add `extraKnownMarketplaces.anchor` + `enabledPlugins["anchor@anchor"]` to settings.json and they're installed — no waiting for the Anthropic directory.

### Added (Long-task stress tests — v1.2-D)

- **`evals/stress/`**: three multi-turn task templates (scaffold mini-project / refactor function preserving behavior / debug failing tests via observe-hypothesize-verify) with pre-flight setup, paste-verbatim prompt, what-to-watch-for narration, and post-run rubrics. Designed to expose anchor's long-task structural value (which short Q&A evals can't measure).
- README explains why short and long evals measure different things, plus a universal 8-item post-run rubric.

### Added (Multi-CLI adapters — v1.2-E)

- **`references/multi-cli-adapters.md`**: how to install anchor's `SKILL.md` content into Cursor (`.cursor/rules/anchor.mdc`), Cline (`.clinerules`), and Aider (`AI_RULES.md` via `.aider.conf.yml read:`). Each section includes a copy-paste install snippet, what carries over, what doesn't (hooks + slash commands don't), and how to mitigate the gaps. Manual by design — auto-detection of project-level tools is too risky to default on.

### Plugin manifest

- Both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` bumped 1.1.0 → 1.2.0.

### Fixed

- **shellcheck SC2148**: `_log_event.sh` is sourced (no shebang); added `# shellcheck shell=bash` directive so shellcheck stops complaining.
- 4 places updated the command-name list from 7 to 11 (`status`, `ship`, `diff`, `cleanup` added): `install.sh`, `uninstall.sh`, `.github/workflows/ci.yml`, README structure listing.

## [1.1.0] — 2026-05-21

Closes the four follow-ups identified in the v1.0.0 self-stress-test post-mortem.

### Changed

- **`/done` now enforces codex review when warranted** (was a soft "提示" before). The command runs `git diff --stat` to count files / inserted+deleted lines and `git diff --name-only` to scan paths for sensitivity keywords (`auth`, `payment`, `crypto`, `migration`, `lock`/`mutex`/`concurrent`/`async`, user-input markers). If any threshold trips, `/done` **stops the wrap-up flow** and tells the user to run `/codex:review` / `/codex:adversarial-review` / `/security-review` before returning. Explicit opt-out is `/done codex` which records "⚠️ codex review skipped by user" in the final report. This fixes the rule-#6 leak observed in the v1.0.0 stress test (5.5/7 → expected 7/7 going forward).
- **SKILL.md "pitfall writeback" section now strongly overrides Codex's built-in memory feature**. Previously the model could honor either "write to `./CLAUDE.md`" or Codex's `~/.codex/memories/`. Now SKILL.md explicitly forbids `~/.codex/memories/` / `update_memory` / `~/.claude/CLAUDE.md` / code comments / single-line commit messages for pitfalls, and explains the reason: project-level pitfalls only matter for the project, and must travel with `git` so a fresh clone / new contributor / CI / 6-months-later-you can see them. Eval 3's "wrote to user-level memory instead of project CLAUDE.md" failure mode is the target.

### Added

- **`CONTRIBUTING.md`** — full contributor guide: dev loop (`git clone → ./install.sh → edit → re-run install.sh`), where each kind of change lands (skill / command / hook / install / reference / eval), CI gate description with local mirror commands, commit-message style (Conventional Commits + ≤72 char first line), the email privacy rule (always noreply form, with a link to the post-mortem of the v1.0 leak), the release process, issue-reporting guidance with hook-bug-specific advice.

### Plugin manifest

- Both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` bumped `version` from `0.3.0` to `1.1.0`. (The repo went from 0.3 to 1.0 conceptually inside the same session as 1.0; the v1.0 manifest still said 0.3 — fixing that now alongside the v1.1 bump.)

### Marketplace submission

- Tried to PR anchor into [`anthropics/claude-plugins-official`](https://github.com/anthropics/claude-plugins-official/pull/1955) — auto-closed by a bot with the message: *"This repo only accepts contributions from Anthropic team members. If you'd like to submit a plugin to the marketplace, please submit your plugin [here](https://clau.de/plugin-directory-submission)."* The PR did create a clean reference entry for `marketplace.json` (16 lines, inserted between `amplitude` and `apollo`, pinned to commit `063cf56`) that the official submission form can reuse.
- **Correct submission path**: https://clau.de/plugin-directory-submission (Anthropic's plugin-directory submission form). Submission has to come from the project owner via that form; can't be merged via direct PR.

## [1.0.0] — 2026-05-21

First stable release. The repo went through 5 iteration rounds within a single conversation; this changelog reconstructs the iteration history from commit messages.

### Added
- **LICENSE** file (MIT) — previously only mentioned in README, now an explicit file at the repo root.
- **CHANGELOG.md** — this file.
- **`.github/workflows/ci.yml`** — three CI jobs:
  - `shellcheck` validates every `.sh` in the repo.
  - `jsonlint` validates every `*.json` (plugin manifests, hooks.json, settings.hooks.json, evals.json).
  - `install-smoke` runs `./install.sh --no-hooks` on a clean Ubuntu runner and verifies skill + commands land in `~/.claude/`.
- **`./CLAUDE.md`** — project-level CLAUDE.md (the irony was that anchor advocated for project contracts but didn't have one of its own).
- **Evals stress test analysis** — `evals/results/<ts>-no-baseline/analysis.md` showing where anchor moves the needle (eval 4 e2e-not-just-tests: with-skill 3/4 vs without-skill 1/4, **+2**) and where it doesn't (eval 5 intent-clarification was already a codex baseline strength; eval 3 pitfall-writeback conflicts with codex's built-in memory feature).

### Iteration history (reconstructed from commits)

#### v0.5 — evals + analysis (commits `dd85c51`, `90b0d03`, `979d46b`, `2bbee61`)

- Added `evals/` directory: 5 test prompts spanning anti-drift / multi-pass-vuln-scan / pitfall-writeback / e2e-not-just-tests / intent-clarification.
- Added `evals/run.py` — batch runner that uses `codex exec --json` to run each prompt twice (with-skill vs without-skill), then uses codex itself as LLM judge to score each behavioral discriminator. Per-eval transcripts and a markdown report land in `evals/results/<ts>/`.
- Two eval batches captured:
  - First batch (default conditions): 8/19 vs 9/19 — measurement artifact, discriminators referenced Claude-Code-only tool names that Codex doesn't expose.
  - Second batch (`--no-baseline --sandbox workspace-write` + rewritten behavioral discriminators): **eval 4 with-skill 3/4 vs without-skill 1/4** — clean evidence anchor's E2E + second-order discipline lands. Other 4 evals are confounded by timeouts / judge misjudgements / codex memory feature conflicts (see `evals/results/20260521-071227-no-baseline/analysis.md`).
- `evals/run.py` modes: `--all`, `--eval-id N`, `--limit N`, `--sandbox`, `--no-baseline`.
- `.gitignore` now excludes `evals/results/*/sandbox-*/` (codex's per-eval scratch dirs).

#### v0.4 — bilingual README + install.sh auto-merges hooks (commit `25b1379`)

- README split into `README.md` (中文) + `README.en.md` (English) with a top-of-page language switcher.
- `install.sh`:
  - Auto-merges hooks into `~/.claude/settings.json` with a timestamped backup (was a manual step before).
  - Idempotent (re-running does not duplicate hooks).
  - `--no-hooks` opt-out.
  - Detects `codex` CLI in PATH and installs to `~/.codex/` too.
- Removed leftover email address from plugin.json files; renamed project from `vibe-coding` to **anchor** (cleaner repo name, no leaked email in commit author after the rename).

#### v0.3 — full cross-CLI parity + plugin-installable (commits before rename)

- Each of the 7 slash commands also gets installed as a Codex skill at `~/.codex/skills/<name>/` (since Codex doesn't read a global `commands/` dir but does read each `~/.codex/skills/<dir>/SKILL.md`).
- New plugin manifests: `.claude-plugin/plugin.json` + `.codex-plugin/plugin.json` + `hooks/hooks.json` (the latter uses `${CLAUDE_PLUGIN_ROOT}` so a marketplace install auto-registers the 4 hooks on both CLIs).
- README updated with a "作为 plugin 安装" / "Plugin install" section.

#### v0.2 — short commands + 4 hooks + statusline + evals scaffold

- Command renaming for brevity:
  - `/efficient-coding` → `/ec`
  - `/lock-scope` → `/lock`
  - `/record-pitfall` → `/pit`
  - `/scan-deeper` → `/scan`
- 4 new commands: `/done`, `/next`, `/recap`, `/init-claude-md`.
- 2 new hard-constraint hooks:
  - `PreToolUse` (`pre-tool-danger.sh`) — blocks irreversible / shared-state-affecting Bash commands (hard-reset, force-push, SQL drop, `rm -rf` of root/home, mkfs, dd to device, chmod 777, curl-pipe-bash). Shell-separator segmentation + first-program safe-list to avoid false positives from echo/grep with dangerous strings as data.
  - `PostToolUse` (`post-tool-lint.sh`) — after Edit/Write/MultiEdit, detects file language and runs the matching linter (ruff / eslint / clippy / gofmt / shellcheck). Outputs via `additionalContext`, does not block.
- Statusline integration (opt-in):
  - `ec-status.sh` prints `🤖auto · 📋3/5` style hints.
  - `statusline-wrapper.sh` wraps the user's existing ccstatusline + appends ec-status.
- `evals/` scaffold (5 test prompts + README).

#### v0.1 — initial commit

- `skills/efficient-coding/SKILL.md` — 7 core rules + long-task mode + autonomous mode + E2E + multi-pass vuln scan + condition-based codex review + project-CLAUDE.md pitfall writeback.
- `skills/efficient-coding/references/` — 4 reference files: `autonomous-mode.md`, `pitfall-template.md`, `vuln-checklist.md`, `multi-agent-recipes.md`.
- `skills/efficient-coding/scripts/` — `session-start-inject.sh`, `stop-self-check.sh`.
- `commands/` — `lock-scope.md`, `record-pitfall.md`, `scan-deeper.md` (later renamed in v0.2).
- `install.sh` / `uninstall.sh` — file-copy install to `~/.claude/`.
- `settings.hooks.json` — manual merge template for `~/.claude/settings.json`.

[1.0.0]: https://github.com/biefan/anchor/releases/tag/v1.0.0
