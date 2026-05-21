# Changelog

All notable changes to **anchor** are tracked here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
