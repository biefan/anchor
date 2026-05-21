# anchor

[![CI](https://github.com/biefan/anchor/actions/workflows/ci.yml/badge.svg)](https://github.com/biefan/anchor/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**English** | [中文](README.md)

> Engineering discipline for Claude Code & Codex CLI: a skill + 21 slash commands + 5 hooks + unified long-term memory (pitfalls / decisions / preferences / snapshots across sessions & projects) that keep AI on-task, prevent drift, and don't stop until the job is done.

## Field report (v1.4.6 re-run across 3 real scenarios)

Ran [`evals/stress/`](evals/stress/) on Codex CLI; scored with `evals/stress/grade.py` (codex-as-judge). This is the **v1.4.6 re-run** after 9 audit rounds / 123 bug fixes:

| Scenario | v1.3 baseline | v1.4.6 re-run | Key finding |
|---|---|---|---|
| **Debug 5 failing tests** | 6/1/1 | **5/2/1** | All anchor core rules passed: observe→hypothesize→verify ✓, didn't modify tests ✓, truncate/word_count fixed correctly ✓. Mild regression: CLAUDE.md was written but as a bullet list, not the 4-field template. |
| **Refactor preserving behavior** | 3/1/3 | **3/1/3** | Identical — 1.08 tax line / floating-point details / side-effect order all preserved; only missed splitting commits in two. |
| **Scaffold Express + SQLite API** | 2/3/0 | **3/2/2** ★ | **anti-borrow-deps rule closed the loop in production**: the cheat caught in v1.3 (borrowed `node_modules` from elsewhere) **did not happen** in v1.4.6 — agent explicitly said *"I can't install dependencies here; please run `npm install` locally"*. |
| **Total** | 11/5/4 (20) | **11/5/6 (22)** | Same pass count → the v1.4.x PreToolUse rewrite didn't break normal usage. |

**Most informative finding** (v1.4.6 full cross-scenario loop):

> v1.3 stress #1 → `grade.py` caught the borrowed-`node_modules` cheat → v1.3.3 added the anti-pattern to SKILL.md → v1.4.6 stress #1 re-run: agent correctly reports the blocker and stops, **cheat doesn't recur**. Full three-stage closed loop: `grade.py → SKILL.md → field validation`.

Full data + cross-stress comparison + improvement suggestions → [`evals/results/stress-2026-05-21-v1.4.6/cross-summary.md`](evals/results/stress-2026-05-21-v1.4.6/cross-summary.md) (includes v1.3 baseline comparison, anti-borrow-deps loop story, real-world data with 1491 PreToolUse block events).

> Run your own: `./evals/stress/run.sh <id>` for one-shot prep + codex exec + transcript + grade + report.

**Against alternatives** → [`docs/competitors.md`](docs/competitors.md) — honest comparison with Praxis / HOTL / Session Orchestrator / Aegis / Archcore and others.

## What it solves

Common Claude Code / Codex CLI failure modes on long tasks:

- **Drifts mid-task** — gets pulled by tool output, spawns side-quests, fixes unrelated code
- **Memory decay on long sessions** — auto-compact truncates skill content past ~5000 tokens
- **"Tests pass = done" lies** — no E2E gate, ships claiming "should work"
- **"Scanned once, looks clean" lies** — no multi-pass vuln scan, surface findings only
- **Forgets pitfalls after fixing** — no CLAUDE.md writeback; next session steps on the same trap
- **Self-reviews with blind spots** — never goes through Codex review

This pack folds the fixes into **soft + hard** defenses:

- **Soft**: `SKILL.md` defines the workflow; the model follows when it remembers
- **Hard**: `Stop` hook in autonomous mode physically blocks stopping until the task list is empty

## Install

```bash
git clone https://github.com/biefan/anchor.git ~/anchor
cd ~/anchor
./install.sh
```

`install.sh` does:

1. Copies skill / 11 slash commands / hook scripts to `~/.claude/`
2. **Auto-merges hooks into `~/.claude/settings.json`** (timestamped backup; `--no-hooks` to skip)
3. If `codex` CLI is detected, also installs to `~/.codex/` (skill + 11 commands as skills)
4. Idempotent — re-running doesn't duplicate hooks

**Restart Claude Code after first install** if `~/.claude/skills/` didn't exist before — live change detection doesn't watch top-level dirs created mid-session.

## Layout

```
anchor/
├── README.md / README.en.md           # this doc (zh / en)
├── install.sh / uninstall.sh          # one-shot install / uninstall
├── settings.hooks.json                # hook config merged into your settings.json
├── .claude-plugin/plugin.json         # Claude Code plugin manifest
├── .codex-plugin/plugin.json          # Codex CLI plugin manifest
├── hooks/hooks.json                   # 4 hooks for plugin-based install
├── skills/
│   └── anchor/
│       ├── SKILL.md                   # core 7 rules + long-task mode + autonomous + E2E + vuln scan + review + pitfall writeback
│       ├── references/                # detailed guides loaded on demand
│       │   ├── autonomous-mode.md     # autonomous protocol
│       │   ├── pitfall-template.md    # pitfall-record templates and examples
│       │   ├── vuln-checklist.md      # vuln grep recipes + SAST commands
│       │   └── multi-agent-recipes.md # parallel sub-agent prompt templates
│       └── scripts/                   # hook implementations
│           ├── session-start-inject.sh
│           ├── stop-self-check.sh
│           ├── pre-tool-danger.sh
│           ├── post-tool-lint.sh
│           ├── ec-status.sh
│           └── statusline-wrapper.sh
├── commands/                          # 7 slash commands
│   ├── lock.md                        # /lock — anchor task scope
│   ├── pit.md                         # /pit — write pitfall record
│   ├── scan.md                        # /scan — vuln scan next pass
│   ├── done.md                        # /done — wrap-up gate
│   ├── next.md                        # /next — advance task list
│   ├── recap.md                       # /recap — progress recap
│   └── init-claude-md.md              # /init-claude-md — scaffold project CLAUDE.md
└── evals/                             # 5 test prompts + run instructions
    ├── evals.json
    └── README.md
```

## Usage

### Automatic (most cases)

Nothing to do. Claude / Codex sees tasks matching the description (implement / fix / refactor / debug / security audit / vuln scan) and loads the skill automatically.

### Manual slash commands

```
/ec                  # load full skill content
/lock <user-request> # anchor task scope before coding
/pit [title]         # write pitfall record to CLAUDE.md after fixing a bug
/scan [path]         # next deeper vuln scan pass
/done                # wrap-up checklist (lint + E2E + codex hint + CLAUDE.md writeback)
/next                # advance task list, mark next pending in_progress
/recap               # report progress / leftover / forks (read-only)
/init-claude-md      # scaffold project CLAUDE.md when missing
```

### Autonomous mode (don't stop until tasks are done)

```bash
# Enable: Stop hook blocks until task list is fully completed
touch ~/.claude/.efficient-coding-autonomous

# Disable: back to normal
rm ~/.claude/.efficient-coding-autonomous
```

**Good for**: a single bounded task you want completed in one shot
**Not for**: exploratory conversation, decisions you want to discuss as you go

Full protocol: [`references/autonomous-mode.md`](skills/anchor/references/autonomous-mode.md)

## Design principles

### 7 core rules (return here when interrupted)

1. **Clarify intent before coding** — ask if vague, don't guess
2. **Lock scope with `TaskCreate`** — user's exact phrasing as the first task
3. **Read project contracts first** — `CLAUDE.md` / `AGENTS.md`
4. **Smallest correct diff** — explicit > terse
5. **Parallelize agents** — multiple `Agent` / `Read` / `Bash` calls in one message
6. **Codex review by change size** — skip trivial, mandatory for complex/security/large
7. **Pitfall writeback to project `CLAUDE.md`** — otherwise the next session steps on it

### Anti-drift triad

- **`TaskCreate` locks scope**: user's exact phrasing becomes the first task — every action checks back against it
- **Drift brake**: after each completed task, look at what's left; if you want to do something not on the list, stop
- **New finds = new tasks**: don't sneak them in, let the user decide whether to extend scope

### Memory survival on long sessions

- Core rules pinned at the top of `SKILL.md` (auto-compact preserves first ~5000 tokens)
- Task list is an external memory not affected by compact
- Re-invoke `/ec` on long sessions to restore full content

### Autonomous mode

Toggled by file flag `~/.claude/.efficient-coding-autonomous`:

- **ON**: Stop hook blocks if task list has pending / in_progress items
- **OFF (default)**: normal conversation

Get-unstuck protocol when truly blocked: 3 rounds of observe → hypothesize → verify before reporting a blocker.

## Codex CLI support

This pack runs on **OpenAI Codex CLI** (0.130+) — it shares the [agentskills.io](https://agentskills.io) `SKILL.md` standard with Claude Code.

### Auto-install

`install.sh` detects `codex` in `PATH` and installs to `~/.codex/skills/ec/`. Manual fallback:

```bash
mkdir -p ~/.codex/skills/ec
cp -r skills/anchor/{SKILL.md,references,scripts} ~/.codex/skills/ec/
```

### Verify

```bash
codex exec --json --skip-git-repo-check 'list available skills' | grep -i '"ec"'
```

### Cross-CLI coverage

| Capability | Claude Code | Codex CLI |
|---|---|---|
| SKILL.md core (7 rules + long-task + autonomous + E2E + vuln scan + review + pitfall) | ✅ | ✅ |
| references/ | ✅ | ✅ |
| Auto trigger by description | ✅ | ✅ |
| 7 slash commands | ✅ `~/.claude/commands/` | ✅ `~/.codex/skills/<name>/` (each command is its own skill) |
| 4 hooks (SessionStart / Stop / PreToolUse / PostToolUse) | ✅ `~/.claude/settings.json` | ✅ via plugin install (see below) |
| Autonomous mode | ✅ Stop hook | ✅ same after plugin install |

### Tool-name differences (negligible)

`SKILL.md` mentions Claude Code tools by name (`TaskCreate`, `AskUserQuestion`, `Agent`). Codex (GPT-5) reads intent and uses its own equivalents (`plan_tool` / asking / sub-tasks). The rules' spirit carries over.

### Re: existing `~/.codex/AGENTS.md`

No conflict. `AGENTS.md` is Codex's global baseline; the skill is a task-activated extension. They compose.

---

## Plugin install (recommended for Codex users — enables hooks)

`install.sh` is file-copy install — gets skill + commands on both CLIs, but **hooks only land in Claude Code's `settings.json`**. To enable hooks on Codex too, install this repo as a **plugin**:

```
.claude-plugin/plugin.json    # Claude Code plugin manifest
.codex-plugin/plugin.json     # Codex CLI plugin manifest
hooks/hooks.json              # 4 hooks using ${CLAUDE_PLUGIN_ROOT}
```

### Claude Code: via marketplace

Add to `~/.claude/settings.json`:

```json
"extraKnownMarketplaces": {
  "anchor": {
    "source": { "source": "github", "repo": "biefan/anchor" }
  }
},
"enabledPlugins": {
  "anchor@anchor": true
}
```

Restart Claude Code; hooks auto-register.

### Codex CLI: via `codex plugin add`

```bash
codex plugin marketplace add github:biefan/anchor
codex plugin add anchor@anchor
```

Codex reads `hooks/hooks.json`; all 4 hooks come up.

### `install.sh` vs plugin install

| Aspect | `./install.sh` (copy) | Plugin install |
|---|---|---|
| Method | run script, copy files | marketplace registration |
| Claude Code skill + commands | ✅ | ✅ |
| Codex skill + commands | ✅ | ✅ |
| Claude Code hooks | ✅ (writes settings.json) | ✅ (plugin) |
| Codex hooks | ❌ | ✅ |
| Upgrade | `git pull && ./install.sh` | `codex plugin add --update` |
| Uninstall | `./uninstall.sh` | `codex plugin remove` |

New users → **plugin install recommended**. Existing `install.sh` users: hooks already live in `~/.claude/settings.json`, you're fine.

---

## Uninstall

```bash
./uninstall.sh
```

Removes `~/.claude/skills/anchor/`, all 11 `~/.claude/commands/*.md`, and any anchor skill dirs under `~/.codex/skills/` if present. **Home-scheme anchor hook entries in `settings.json` are automatically cleaned** (with a timestamped backup); plugin-marketplace hook entries are left alone by default — they're owned by the plugin system. Pass `--all-hooks` to clear plugin-scheme entries too.

## Credits

Design references:

- [anthropics/skills](https://github.com/anthropics/skills) — official skill examples (`skill-creator`, `claude-api`)
- [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) — `stop-review-gate` hook pattern
- Anthropic [claude-plugins-official/pr-review-toolkit](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit) — silent-failure-hunter / code-reviewer / code-simplifier and 3 other PR review agents
- Anthropic [claude-plugins-official/code-modernization](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-modernization) — `security-auditor` agent

## License

MIT
