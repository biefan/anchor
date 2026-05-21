# Competitive landscape — what's around, what's anchor doing differently

anchor sits in a crowded space. AI coding discipline / workflow packs are a 2025 trend; the [awesome-codex-plugins](https://github.com/hashgraph-online/awesome-codex-plugins) listing alone has 40+ entries under "Development & Workflow". This doc is an honest take on what's nearby and where anchor is genuinely different.

**Quick read**: anchor's center of gravity is **mechanical enforcement** (hooks + auto-grading), not method. Most peers are method-only; a few (Session Orchestrator, HOTL) add structured loops. Cross-CLI runtime is shared by a handful (Archcore, Session Orchestrator, Antigravity), but anchor is the only one combining cross-CLI + 4 hooks + a codex-as-judge auto-grader for its own stress tests.

## Closest neighbors

### [Praxis](https://github.com/ouonet/praxis)
- **Pitch**: *"What, not how. Tell your agent what done looks like, not the steps."* A discipline framework rewritten as a cheaper alternative to Superpowers.
- **Overlap with anchor**: high. Both are "engineering discipline" packs that constrain agent behavior via skills.
- **Anchor's difference**: anchor adds hooks (Stop / PreToolUse / PostToolUse) for hard enforcement and an auto-grader for measuring whether the rules landed. Praxis is method-only.

### [HOTL (Human-on-the-Loop)](https://github.com/yimwoo/hotl-plugin)
- **Pitch**: *"Keeps implementation work grounded in a design, an executable workflow, review checkpoints, and verification evidence."* Cross-CLI (Codex / Claude Code / Cline, Cursor adapter).
- **Overlap with anchor**: high on the *cross-CLI + structured workflow + verification gate* axis.
- **Anchor's difference**: HOTL's "Human-on-the-Loop" frames human as the checkpoint; anchor's autonomous mode + Stop hook frames task completion as the checkpoint and lets the agent keep going until the task list is empty. Different stance on autonomy.

### [Session Orchestrator](https://github.com/Kanevry/session-orchestrator)
- **Pitch**: *"Turn ad-hoc Claude Code sessions into a repeatable loop — research → plan → execute in waves → close. Inter-wave reviews catch regressions before they ship."* 37 skills. Cross-CLI (Claude Code + Codex + Cursor). 5632 passing tests on its own CI.
- **Overlap with anchor**: high on cross-CLI; structurally larger.
- **Anchor's difference**: Session Orchestrator is the bigger, more mature wave-based execution framework. Anchor is leaner: 1 main skill + 11 commands + 4 hooks, and ships an auto-grader instead of inter-wave human review. If you want "agents on rails with wave reviews", pick Session Orchestrator; if you want "minimal discipline pack + hook enforcement + measurable", anchor.

### [Aegis](https://github.com/GanyuanRan/Aegis)
- **Pitch**: *"An agentic skills framework & software development methodology that works: planning, TDD, debugging, and collaboration workflows."* Marketing-forward.
- **Overlap with anchor**: medium-high (same "discipline + method" framing, similar TDD/debug skills).
- **Anchor's difference**: Aegis leans more on methodology and presentation; anchor's deliverables are more tooling-shaped (run.sh, grade.py, hooks/hooks.json). If you want a polished method pack, pick Aegis; if you want infrastructure-style enforcement, pick anchor.

### [Archcore](https://github.com/archcore-ai/plugin)
- **Pitch**: *"Make your AI code like it already knows your repo."* Repo-awareness layer; ingests `CLAUDE.md`/`AGENTS.md`/`.cursorrules`.
- **Overlap with anchor**: low-medium. Different center of gravity (Archcore = repo-awareness; anchor = discipline + enforcement).
- **Compatible, not competitive**: Archcore + anchor compose well. Archcore loads your repo's existing conventions into the agent; anchor enforces the engineering discipline on top of that. Same project can use both.

### [Antigravity Workspace Template](https://github.com/study8677/antigravity-workspace-template)
- **Pitch**: *"Multi-agent codebase knowledge graph generator with context-aware planning and automatic scope management."*
- **Overlap with anchor**: low. Different problem (codebase Q&A / grounded answers vs discipline).
- **Compatible, not competitive**: Antigravity for *understanding the codebase first*, anchor for *behaving well while changing it*.

### [Brooks Lint](https://github.com/hyhmrright/brooks-lint)
- **Pitch**: *"AI code reviews grounded in twelve classic engineering books — consistent, traceable, actionable."*
- **Overlap with anchor**: low. Narrow vertical (code review only).
- **Compatible**: anchor's `/codex:review` step in `/done` could in principle pipe through brooks-lint. Different tools for different stages.

### [Spec-Driven Development](https://github.com/Habib0x0/spec-driven-plugin)
- **Pitch**: *"Three-phase Requirements → Design → Tasks workflow with EARS notation acceptance criteria, autonomous execution loop, cross-spec dependencies, post-implementation acceptance testing."*
- **Overlap with anchor**: medium on *autonomous loop + task structure*.
- **Anchor's difference**: anchor's "task list" is a thin scope-anchoring layer (1 task = user's exact phrasing); SDD's is a full requirements engineering framework. Pick SDD if you want EARS + acceptance tests as artifacts; pick anchor if you want lightweight scope-locking + hook enforcement.

## What's specifically anchor's own

The intersection of all of these isn't covered anywhere else:

1. **4 hooks that physically enforce**:
   - `SessionStart` — injects project state + autonomous toggle
   - `Stop` — blocks the session ending while autonomous mode + pending tasks
   - `PreToolUse` — blocks irreversible bash patterns (force-push, hard-reset, schema drops, mkfs, dd-to-device, recursive-777, curl-pipe-bash) with a shell-aware segment + safe-list parser
   - `PostToolUse` — runs the language-appropriate linter after Edit/Write
   - Logs every event to `~/.claude/anchor-events.jsonl` for `/status` review

2. **Codex-as-judge auto-grading** (`evals/stress/grade.py`):
   - Reads spec rubric + sandbox evidence (git log/diff/files + auto-detected dep cross-check across Node/Python/Rust/Go) and asks codex to grade
   - Catches things transcripts hide — e.g. v1.3 stress #1 caught an agent who copied a foreign `node_modules` to fake `npm install` success; 184-package mismatch surfaced automatically
   - Run via `./evals/stress/run.sh <id>` end-to-end

3. **Strong override of Codex's built-in memory** (SKILL.md "pitfall writeback" section):
   - Explicitly forbids `~/.codex/memories/` and code comments for pitfalls
   - Forces project-level `CLAUDE.md` so lessons travel with `git`
   - Tested working in stress #3 (agent wrote 2 entries in the 4-field template)

4. **Cross-CLI as a first-class goal**, not an afterthought:
   - Same `SKILL.md` for Claude Code (Agent Skills) + Codex CLI (skills/plugins)
   - Slash commands installed in both `~/.claude/commands/` and as individual `~/.codex/skills/<name>/`
   - Hooks portable via `${CLAUDE_PLUGIN_ROOT}` when installed as a plugin (both CLIs honor it)
   - Adapters documented for Cursor / Cline / Aider in `references/multi-cli-adapters.md`

5. **Bilingual docs** (中/EN) — README.md (中) + README.en.md, both kept in sync per PR

6. **CI gates on the discipline tool itself**:
   - `shellcheck` on every `.sh`
   - `jsonlint` on every `*.json`
   - `install.sh` smoke test on a fresh Ubuntu runner (verifies skill+commands land, then `uninstall.sh` cleans up)
   - 7+ green runs as of v1.3.4

7. **Self-test stress data shipped in repo** (`evals/results/stress-{1,2,3}-2026-05-21/`) — anchor publishes its own grader scoresheets, including the rubric-failure analyses that drove the v1.3.x patches.

## When NOT to pick anchor

- Pick **Praxis** if you want a leaner, "what not how" pure-method pack with no hooks.
- Pick **Session Orchestrator** if you want a larger, more mature wave-based execution + inter-wave review framework, and you don't mind a heavier surface.
- Pick **HOTL** if you specifically want human-in-the-loop checkpoints rather than autonomous mode.
- Pick **Aegis** for the polished method pack experience and TDD focus.
- Pick **Spec-Driven Development** if EARS-notation requirements + acceptance tests as artifacts matter to you.
- Pick **Archcore** or **Antigravity** if your bottleneck is "agent doesn't know my repo," not discipline (and combine with anchor on top).
- Pick **brooks-lint** as a code-review *stage tool*; not as the full discipline pack.

## How peers and anchor compose

Anchor isn't an island. Reasonable combinations:

| Scenario | Stack |
|---|---|
| Need both repo context AND discipline | Archcore (or Antigravity) + anchor |
| Want EARS specs as deliverables AND scope-locking discipline | Spec-Driven Development + anchor (use SDD for the spec phase, anchor for the implementation discipline) |
| Need codex review + book-grounded code review | anchor's `/codex:review` → brooks-lint |
| Migrating from Superpowers | Praxis (preserves "what not how" feel cheaper); anchor adds enforcement if you want it |

## Honest gaps (where anchor is behind peers)

- **No knowledge-graph / repo Q&A capability** — Antigravity / Archcore do this; anchor punts on it.
- **No EARS / acceptance-test artifacts** — Spec-Driven Development does this; anchor's TaskCreate-anchored scope is much thinner.
- **No wave-based execution + inter-wave human review** — Session Orchestrator does this with 37 skills; anchor's autonomous mode is the opposite stance (less human, more keep-going).
- **No GUI / dashboard** — others have web UIs, anchor is CLI-only.
- **Fewer skills bundled** — anchor ships 1 main skill + 11 commands; some peers ship 30-200+ skills.

The honest answer to "is there a replacement?" is **yes, several** — but each picks a different center of gravity. anchor's specific bet is *hooks + auto-grading + cross-CLI + bilingual, in a lean 91-file package*. If that bet doesn't match your needs, the table above is the map to the alternatives.
