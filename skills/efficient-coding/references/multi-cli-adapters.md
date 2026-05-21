# Multi-CLI adapters

anchor's `SKILL.md` is fully cross-CLI for **Claude Code** and **Codex CLI** (both implement the agentskills.io standard). For other AI coding tools that don't use that standard — Cursor, Cline, Aider — you can still get most of anchor's *soft* rules (skill content) but **hooks and slash commands don't port** (those are runtime-specific).

This doc shows how to plug anchor's `SKILL.md` content into each tool's project-level rules file.

## Adapter matrix

| Tool | Rules file | Scope | Hot reload | Hooks support |
|---|---|---|---|---|
| **Claude Code** | `~/.claude/skills/efficient-coding/SKILL.md` | user (cross-project) | yes | ✅ full (4 hooks via `~/.claude/settings.json`) |
| **Codex CLI** | `~/.codex/skills/ec/SKILL.md` | user (cross-project) | yes | ✅ full (via plugin install) |
| **Cursor** | `<project>/.cursor/rules/anchor.mdc` | project | yes (on edit) | ❌ no native hook system |
| **Cline** | `<project>/.clinerules` | project | yes | ❌ |
| **Aider** | `<project>/AI_RULES.md` referenced from `.aider.conf.yml` | project | yes | partial (yes-no confirm prompts) |

## Cursor

Cursor uses `.cursor/rules/*.mdc` (Markdown-with-frontmatter) files in the project root. Multiple files concatenate into the system prompt.

### Install

```bash
cd <your-project>
mkdir -p .cursor/rules
cp ~/anchor/skills/efficient-coding/SKILL.md .cursor/rules/anchor.mdc
```

Then edit the file's frontmatter to be Cursor-style:

```yaml
---
description: Engineering discipline pack — anchor.
globs: ["**/*"]
alwaysApply: true
---
```

(Cursor doesn't recognize anchor's `name:` / `description:` SKILL.md frontmatter as-is. Replace it with the block above.)

### What you get

- Soft rules (7 core rules + long-task mode + autonomous + E2E + multi-pass vuln + condition-based review + pitfall writeback) all apply
- Cursor's "ask before applying changes" naturally implements ~70% of anchor's "意图清晰才动手" rule
- `TaskCreate` / `AskUserQuestion` references in the text become guidance — Cursor will read them as "use the equivalent UI flow"

### What you don't get

- The 4 hooks (SessionStart / Stop / PreToolUse / PostToolUse) — Cursor doesn't run external scripts before/after tool calls
- The 11 slash commands — Cursor's slash commands are built-in and not user-extensible at this layer
- The autonomous mode toggle (Cursor has its own "agent mode" toggle, which is similar in spirit but not driven by `~/.claude/.efficient-coding-autonomous`)

## Cline

Cline reads `.clinerules` at the project root (plain markdown, no frontmatter).

### Install

```bash
cd <your-project>
cp ~/anchor/skills/efficient-coding/SKILL.md .clinerules
```

That's it. No frontmatter conversion needed — Cline ignores YAML it doesn't understand.

### Caveats

Cline's `.clinerules` files are concatenated into the system prompt every turn. anchor's SKILL.md is ~16 KB (~5000 tokens). If you already have other `.clinerules` content, watch your context budget.

## Aider

Aider reads `AI_RULES.md` if `~/.aider.conf.yml` (or project-level `.aider.conf.yml`) references it via `read:` field.

### Install

```bash
cd <your-project>
cp ~/anchor/skills/efficient-coding/SKILL.md AI_RULES.md
# Strip the YAML frontmatter — aider doesn't parse it as YAML, it shows raw
# (Easiest: sed -i '1,/^---$/d' AI_RULES.md after the first --- block. Or open and delete the frontmatter manually.)

cat >> .aider.conf.yml <<'YAML'
read:
  - AI_RULES.md
YAML
```

### Caveats

- Aider's chat is interactive and short-task-oriented; anchor's "autonomous mode" / long-task discipline doesn't map cleanly. The rules still apply per-message.
- `git push --force` etc. — Aider already prompts for confirmation, so anchor's PreToolUse hook is somewhat redundant.

## What all three skip (and how to mitigate)

| Anchor capability | Cursor / Cline / Aider equivalent |
|---|---|
| `/lock` command (anchor scope in TaskCreate) | Tell the model "anchor the scope first: list the user's request as task #1 and only do work on the list" at the start of a session |
| `/done` gate (lint + E2E + codex + pitfall) | Add a manual "before declaring done, run lint+tests, then write `CLAUDE.md` pitfall if applicable" reminder block at the bottom of the rules file |
| `Stop` hook autonomous-mode enforcement | These tools don't have a per-stop callback. Closest is Aider's `--auto-test` / Cursor's agent loop, which keep going until the model says done — that's "autonomous-light" |
| `PreToolUse` blocking irreversible commands | Cursor and Aider both prompt the user before destructive commands by default. Cline less so — be careful with autonomy settings |
| `PostToolUse` linter | Hook a git pre-commit (e.g. via `pre-commit` package) running the same linters anchor would |

## Recommendation

If you primarily use **Claude Code or Codex CLI**: use the full anchor (`./install.sh`).
If you also use Cursor / Cline / Aider on the same project: cp SKILL.md into the rules file for that tool (above). You'll get ~70% of anchor's value with no hooks, no commands.
If your team uses several of these: keep the `~/anchor/skills/efficient-coding/SKILL.md` as the single source of truth and re-sync the project rules file when you upgrade anchor (e.g. via a `make sync-cursor-rules` Makefile target on your end).

## What's NOT happening here

This adapters doc is **manual**. anchor's `install.sh` does not auto-detect Cursor / Cline / Aider projects and write to their rules files. Reason: each of these tools is project-level, not user-level, so the right place to install changes per-project. The cost of one `cp` per project is low; the cost of auto-detection going wrong is high.

If we ever ship auto-detection (v1.3?), it'd be opt-in via a flag like `./install.sh project --cursor --cline --aider` in the current working directory.
