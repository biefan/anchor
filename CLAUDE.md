# anchor — project contract for AI coding sessions

> Self-applied: this is exactly the kind of `./CLAUDE.md` the anchor skill tells you to write on entering a new project. Anchor advocates for project-level contracts but went 5 release rounds without one of its own — fixed in v1.0.0 alongside the LICENSE + CHANGELOG + CI scaffolding.

## What this repo is

A cross-CLI (Claude Code + Codex CLI) engineering-discipline pack:

- **One skill** (`skills/anchor/SKILL.md`) — 7 core rules + long-task mode + autonomous mode + E2E + multi-pass vuln scan + condition-based codex review + pitfall writeback.
- **7 slash commands** (`commands/*.md`): `/ec /lock /pit /scan /done /next /recap /init-claude-md`.
- **4 safety hooks** (`hooks/hooks.json` + `skills/anchor/scripts/*.sh`): `SessionStart`, `Stop`, `PreToolUse`, `PostToolUse`.
- **Bilingual docs** (`README.md` zh, `README.en.md` en).
- **Evals** (`evals/`): 5 test prompts + runner + analysis.

Install via `./install.sh` (file-copy, auto-merges hooks into `~/.claude/settings.json`, also installs to `~/.codex/` if codex CLI is on PATH) or via plugin marketplace registration (see README "Plugin install").

## File layout

```
.
├── .claude-plugin/plugin.json    # Claude Code plugin manifest
├── .codex-plugin/plugin.json     # Codex CLI plugin manifest
├── .github/workflows/ci.yml      # shellcheck + jsonlint + install smoke test
├── README.md / README.en.md      # bilingual top doc
├── CHANGELOG.md                  # versioned history
├── LICENSE                       # MIT
├── install.sh / uninstall.sh     # idempotent file-copy install
├── settings.hooks.json           # hook config merged into ~/.claude/settings.json
├── hooks/hooks.json              # same hooks for plugin install path
├── skills/anchor/
│   ├── SKILL.md
│   ├── references/*.md           # detail loaded on demand
│   └── scripts/*.sh              # hook implementations
├── commands/                     # 7 slash commands
└── evals/                        # prompts + runner + result archive
```

## Working in this repo

### Where to make changes

| Change kind | Edit here |
|---|---|
| Tweak a rule in the skill itself | `skills/anchor/SKILL.md` (then `./install.sh` to re-sync to `~/.claude/` and `~/.codex/`) |
| Add a new slash command | `commands/<name>.md` (frontmatter `description:` + body) |
| Change a hook's logic | `skills/anchor/scripts/<name>.sh` (keep stdin / stdout contract — read JSON from stdin, write `{"decision":"block","reason":...}` JSON to stdout or exit 0) |
| Change install behavior | `install.sh` (idempotent, must not duplicate hooks on re-run) |
| Add a detailed reference loaded on demand | `skills/anchor/references/<topic>.md` (then reference it from `SKILL.md`) |
| Add an eval scenario | `evals/evals.json` (add to `evals` array with `discriminators` that are observable behaviors, not tool calls) |

### Editing the skill: hot reload

Claude Code watches `~/.claude/skills/` for changes after session start. Editing `~/.claude/skills/anchor/SKILL.md` reloads on next invocation **as long as the top-level `~/.claude/skills/` directory existed when the session started**. If you create that directory mid-session, restart Claude Code to begin watching it.

This means the dev workflow is:

1. Edit `/root/skk/skills/anchor/SKILL.md` (the repo source of truth).
2. `cp` to `~/.claude/skills/anchor/SKILL.md` (or re-run `./install.sh`).
3. Re-trigger `/ec` in Claude Code to see the new content.

### Hooks: stdin/stdout contract

Each hook script is a stdin → stdout filter:

- **Input** (stdin): JSON with at minimum `session_id`, `cwd`, plus event-specific fields (`tool_name` + `tool_input` for `PreToolUse`/`PostToolUse`).
- **Output options**:
  - `exit 0`, no stdout → "allow / no comment"
  - JSON `{"decision":"block","reason":"..."}` on stdout, exit 0 → block the action
  - JSON `{"hookSpecificOutput":{"hookEventName":"<event>","additionalContext":"..."}}` → inject text into the session (for `SessionStart` / `PostToolUse`)

Test a hook locally before committing:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"<test cmd>"}}' | \
  bash skills/anchor/scripts/pre-tool-danger.sh
```

## Conventions

- **Bash scripts**: shebang `#!/bin/bash`, `set -e`, prefer Python heredocs for any non-trivial logic. All scripts must pass `shellcheck` (CI enforces).
- **JSON files**: must be valid (CI runs `python3 -m json.tool` on every `.json` outside `evals/results/`).
- **Commit messages**: imperative mood (`fix X, not "fixed X"`), one-line summary ≤ 72 chars, then a blank line and longer explanation if needed. The CHANGELOG groups related commits per release.
- **Email privacy**: NEVER use a non-noreply email in commit author or any tracked file. Use `<github-id>+<username>@users.noreply.github.com` (the project did leak `biefan7@gmail.com` once during initial setup — see "Known pitfalls" below).
- **Description language**: skill / command `description:` fields are English (so they trigger well in either CLI's English-leaning model). Inline doc body can be Chinese.

## Cross-CLI design rules

When editing `SKILL.md` or commands, remember the same file is used by both Claude Code and Codex CLI:

- **Tool names**: when referring to specific tools (e.g. `TaskCreate`, `AskUserQuestion`, `Agent`), annotate both runtimes' equivalents in parentheses (e.g. "Claude Code: `TaskCreate`; Codex: `plan` / `update_plan`").
- **Behaviors over tools**: when possible, describe the **behavior** (e.g. "anchor task scope") not the **tool** (e.g. "call `TaskCreate`"). Behaviors generalize.
- **Eval discriminators**: same rule — `explicit_task_breakdown_in_response`, not `is_task_list_used`. See `evals/results/20260521-071227-no-baseline/analysis.md` for the rewrite story.

## Known pitfalls

### Initial commit leaked a non-noreply email (2026-05-21)
- **Symptom**: First 4 commits to `vibe-coding` repo had author email `biefan7@gmail.com` (publicly indexable on GitHub).
- **Root cause**: install / commit scripts pulled `userEmail` from the user's CLAUDE.md memo file instead of using `git config user.email`'s noreply default.
- **Fix**: deleted the `vibe-coding` repo, re-init'd as `anchor` (also renamed for clarity) with `git config user.email "<id>+<user>@users.noreply.github.com"` and removed the email field from `*-plugin/plugin.json` (`url` field replaces it). See commit `5418195`.
- **Lesson**: never override `git config user.email` from a script. Trust the user's global config. If a project needs author info in a tracked file, use a GitHub `noreply` address or no address at all.

### Codex memory feature competes with project-level CLAUDE.md (2026-05-21)
- **Symptom**: SKILL.md instructs "write pitfall to `./CLAUDE.md`" but on Codex the model often writes to `~/.codex/memories/extensions/ad_hoc/notes/` instead (Codex has built-in memory tools with `generate_memories=true` in `~/.codex/config.toml`).
- **Root cause**: Codex's first-party memory feature has higher precedence in the model's attention than skill text saying "write to a file".
- **Possible fixes** (not yet applied):
  1. Strengthen SKILL.md language: "DO NOT use `~/.codex/memories/`. Write pitfalls to the cwd's `CLAUDE.md` so they travel with the project's git history."
  2. Or accept codex memory as a runtime-equivalent persistent record and stop fighting it.
- **Lesson**: cross-runtime skills can't always assume the underlying agent has no competing built-in for the same capability. State both the WHAT (persistent project pitfall log) and the WHY (must travel with git), so the model has the constraint to compare against.

### PreToolUse hook blocked our own commit message containing "git reset --hard" literally (2026-05-21)
- **Symptom**: Tried to `git commit -m "...references git reset --hard..."` and PreToolUse hook blocked the entire command because it pattern-matched the regex against the full command string, including the message body.
- **Root cause**: First-pass `pre-tool-danger.sh` regex-matched the whole `cmd`, treating literal substrings the same as actual command tokens.
- **Fix**: Rewrote with shell-separator segmentation + first-program safe-list (`echo`, `grep`, `cat`, etc. as no-op carriers when they're the actual program). See commit `7908f96`.
- **Lesson**: when blocking based on patterns, the pattern must consider the **command token**, not just any substring of the cmd. Even then, `git commit -m "<message>"` makes git the first program — fine — but message bodies still hit the regex. Document `EC_BYPASS_HOOK` style escape hatches conservatively (auto-mode-classifier denied adding one anyway, which is the right safety boundary).

### Auto-mode classifier blocked adding a `--bypass` escape hatch to the hook (2026-05-21)
- **Symptom**: To work around the above, tried to add `if "EC_BYPASS_HOOK" in cmd: sys.exit(0)` to `pre-tool-danger.sh`. The classifier denied the edit citing "Security Weaken".
- **Root cause**: A safety hook should not have a user-side bypass that's easy to invoke unilaterally.
- **Resolution**: accepted the denial — the right answer was to fix commit messages to not contain bare `git reset --hard` literally (use `hard-reset` etc.). The hook's strict behavior is a feature.
- **Lesson**: don't weaken your own safety constraint to work around a UX inconvenience. Fix the upstream input instead.

### Codex eval baseline + 12 KB ~/.codex/AGENTS.md absorbed most "soft" anchor rules (2026-05-21)
- **Symptom**: First eval run scored 8/19 with-skill vs 9/19 without-skill. Looked like anchor had no effect.
- **Root cause**: User's existing `~/.codex/AGENTS.md` already taught Codex "ask before guessing", "multi-pass vuln scan", "raise second-order concerns", etc. Anchor's soft rules overlap a lot with baseline AGENTS.md. Discriminators also tested Claude-Code-specific tools (`TaskCreate`) that Codex doesn't expose.
- **Fix**: rewrote discriminators as behavioral; added `--no-baseline` flag to `run.py` that temporarily moves `~/.codex/AGENTS.md` aside; added `--sandbox workspace-write` so codex can actually write files.
- **Lesson**: when benchmarking a skill against a baseline that already implements the same soft rules, the measurable delta is small. Anchor's differentiation is structural (`TaskCreate`-anchored scope, `Stop` hook enforcement, 4-field pitfall template) and only shows in **long, multi-step tasks** — short Q&A evals will mostly show baseline parity. Eval 4 (`e2e-not-just-tests`) was the one short eval where anchor structurally won (3/4 vs 1/4) because the task directly hit "warning against handwaving completion".

## Testing

### Quick: shellcheck + jsonlint locally (mirrors CI)

```bash
# Shell scripts
find . -name '*.sh' -not -path '*/.git/*' | xargs shellcheck --exclude=SC1091,SC2034

# JSON manifests
find . -name '*.json' -not -path '*/.git/*' -not -path '*/evals/results/*' \
  -exec python3 -m json.tool {} \;
```

### Eval runner

```bash
# All 5 evals, codex with current state
python3 evals/run.py --all

# Single eval
python3 evals/run.py --eval-id 4

# Zero-baseline (temporarily moves AGENTS.md aside)
python3 evals/run.py --all --no-baseline
```

Results land in `evals/results/<timestamp>[-no-baseline]/`. See `evals/README.md` for the full workflow.

### Hook smoke tests

```bash
# PreToolUse danger blocker
echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}' | \
  bash skills/anchor/scripts/pre-tool-danger.sh
# Should print {"decision":"block",...}, exit 0

# Stop hook (must have autonomous flag + a real session task dir to trigger block)
touch ~/.claude/.efficient-coding-autonomous
echo '{"session_id":"<id-with-pending-tasks>"}' | \
  bash skills/anchor/scripts/stop-self-check.sh
rm ~/.claude/.efficient-coding-autonomous
```

## Release process

1. All changes land via PR → CI green required.
2. Bump `version` in `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` (semver).
3. Add a new `## [x.y.z] — YYYY-MM-DD` block to `CHANGELOG.md`.
4. Tag: `git tag vX.Y.Z && git push --tags`.
5. (Optional) draft a GitHub Release with the changelog block as the body.
