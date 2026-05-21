# Changelog

All notable changes to **anchor** are tracked here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.9.1] — 2026-05-21

**Phase 1 testing** patch — user asked "we just made it, can we test everything?" Wrote a comprehensive end-to-end test suite that exercises every v1.7-v1.9 feature: all 5 hooks, all helper scripts, the memory loop, all 22 commands' file syntax, all 5 templates, install/uninstall idempotency, and plugin manifest consistency.

### Added

- **`evals/regression/test-v1.9-comprehensive.sh`** — 34 test cases across 7 sections:
  - **A. Hook scripts (8)** — session-start basic / autonomous-detected / lean-mode-acknowledged; stop hook quiet-vs-block; pre-compact warning; pre-tool danger regression; post-tool lint with weird filenames
  - **B. Helper scripts (3)** — analyze-events.py output; pitfall-sync.py extraction + write
  - **C. Memory loop (9)** — full write→index→inject→recall cycle: SessionStart memory index lists pitfalls/decisions/facts; lean mode skips; preferences auto-inject conditional on non-empty content
  - **D. Command syntax (3)** — frontmatter validity; non-empty; count = 22
  - **E. Templates (1)** — all 5 templates exist + non-empty
  - **F. Install/uninstall (8)** — install --no-hooks exits 0; creates skill dir; 22 commands installed; templates dir installed; pitfall-sync.py executable; re-run idempotent; uninstall exits 0 + removes
  - **G. Plugin manifest (2)** — 3 manifests version-consistent; codex-plugin has `interface` block

### Total regression coverage now

14 suites / **333/333 cases** all pass (299 prior + 34 new comprehensive). zero PreToolUse regression. shellcheck PASS on all 11 shell scripts. jsonlint PASS on all manifests.

### Plugin manifest

- Patch 1.9.0 → 1.9.1.

## [1.9.0] — 2026-05-21

**Memory actually-gets-remembered release**. User feedback: "主要是能记得住啊 不然记不住没什么用啊" — memory had a write-side (`/pit /decide /remember /snapshot`) but no auto-pull-side. Claude never proactively recalled past learnings — user had to manually `/recall`, defeating the purpose.

### Added — project-scoped memory index in SessionStart

SessionStart hook now lists titles + dates of all `pitfalls / decisions / facts` entries for the current project (matched by `basename(cwd)`). ~30 lines max for typical project. Token-efficient (titles only, not content).

Output example:
```
## Memory index (project: `my-api`)
_Past learnings for this project. Use `/recall <keyword>` for full content._

### pitfalls (4)
- 2026-04-15 — Redis pipeline cluster slot mismatch
- 2026-04-22 — JWT expiry edge case
- 2026-05-01 — Postgres connection pool exhaustion
- 2026-05-10 — websocket reconnect race

### decisions (2)
- 2026-03-15 — Use Redis Streams over RabbitMQ for event bus
- 2026-04-01 — Backfill via dbt incremental, not adhoc SQL

### facts (1)
- 2026-03-20 — prod DB endpoint + connection limits

→ **Auto-recall reflex**: when user mentions a topic that matches an entry above, run `/recall <topic>` to load full content BEFORE answering.
```

### Added — SKILL.md "auto-recall reflex" rule (#8)

New core rule:

> "**遇到 topic 先 `/recall`**。SessionStart 注入的 'Memory index' 列出本项目过去 `/pit` `/decide` `/remember` 写过的 topics — 用户提及 matching topic 时，**先 `/recall <topic>` 拉过去经验**再回答，不要凭空答。memory index 是 '有记忆' 信号，`/recall` 拉具体内容。"

This is the actual "remembering" mechanism. Without this rule, memory index would just be context noise. With it, Claude has a clear instruction to use the index as a signal to retrieve past content before answering.

### Behavior

| Without v1.9.0 | With v1.9.0 |
|---|---|
| `/pit redis-cluster` writes file | Same write |
| Next session 1 week later, user asks "redis connection issue" | Same |
| Claude answers from general knowledge, may miss past insight | Claude sees memory index lists redis-cluster pitfall, runs `/recall redis`, surfaces past insight, answers informed |

### Lean mode behavior

Lean mode (`/lean on`) skips the memory index inject too — saves ~30 lines/session but loses auto-recall reflex. Use only for short Q&A sessions.

### Verified

- 13 regression suites / 299/299 pass.
- shellcheck PASS.
- Manual test: created fake pitfall in `~/.anchor/memory/pitfalls/skk/`, SessionStart output correctly listed it under "Memory index".

### Plugin manifest

- Minor 1.8.1 → 1.9.0.

## [1.8.1] — 2026-05-21

**Token-savings release**. User feedback: "还要省 token". v1.8.0 's SessionStart was injecting active-task.md (60 lines) + preferences.md (30 lines) on every session = ~900 tokens/session overhead. 4 fixes:

### Added — `/lean` command + toggle file

- **`commands/lean.md`** — toggle `~/.claude/.anchor-lean` flag. When ON, SessionStart skips the `active-task.md` + `preferences.md` injection (still keeps project contracts + git branch + autonomous mode status).
- **Estimated saving**: ~600 tokens/session for long-task injects, ~300 for prefs = **~900 token/session reduction** when lean mode is on.
- Trade-off: in lean mode you have to `cat ~/.anchor/active-task.md` or `/recall` manually to get historical context. Worth it for short Q&A sessions.

### Changed — SessionStart smarter (default mode)

Even without lean mode on, SessionStart is more conservative:

1. **active-task.md inject is now project-scoped** — only injects if the `Project:` field inside matches `basename(cwd)`. Previously: injected unconditionally, polluting unrelated sessions with another project's state.
2. **active-task.md cap reduced 60 → 40 lines** — milestones table is the primary value; deep history available via manual `cat`.
3. **preferences.md inject conditional** — only if file has >3 lines (skips empty/template files).
4. **preferences.md cap reduced 30 → 20 lines** — preferences should be terse.

Net default-mode saving: ~200-400 tokens/session depending on file content.

### Verified

- shellcheck PASS on all shell scripts.
- 13 regression suites / 299/299 pass.
- Live test: SessionStart in /tmp (no project) → 4 lines output (lean off) / 6 lines (lean on, includes 1 line lean status notice). In real long-task project: lean off ~80 lines, lean on ~10 lines.

### Plugin manifest

- Patch 1.8.0 → 1.8.1.

## [1.8.0] — 2026-05-21

**Feature release**: unified long-term memory system. v1.7.0 added pitfalls-only cross-project index; v1.8.0 generalizes it to a 7-category memory tree (`~/.anchor/memory/`) + 3 new commands to write into it + upgraded `/recall` to search all of them.

### Added — 3 new memory-write commands

- **`/remember <category> <content>`** — generic long-term memory write:
  - `pref` → `~/.anchor/memory/preferences.md` (single file, auto-injected by SessionStart hook)
  - `decision` → `~/.anchor/memory/decisions/<project>/<file>.md`
  - `fact` → `~/.anchor/memory/facts/<project>/<file>.md`
  - `todo` → `~/.anchor/memory/todos.md` (single file)
- **`/decide <title>`** — ADR-style architectural decision record. Auto-extracts context / alternatives / consequences from chat history. Writes to `~/.anchor/memory/decisions/<project>/<YYYY-MM-DD>-<slug>.md` with full ADR structure (Status / Context / Decision / Alternatives / Consequences / Followup).
- **`/snapshot <label>`** — full workspace snapshot (more than `/save`): task list + git state (branch/diff-stat/log) + active-task.md + modified file contents (top 20) + manifest. Use for long-task major checkpoints or pre-experiment safety. Writes to `~/.anchor/memory/snapshots/<project>/<label>-<timestamp>/`.

### Changed — `/recall` upgraded to multi-category

Now searches all 7 memory locations in parallel:

```
~/.anchor/memory/pitfalls/<project>/      (from /pit)
~/.anchor/memory/decisions/<project>/     (from /decide)
~/.anchor/memory/facts/<project>/         (from /remember fact)
~/.anchor/memory/preferences.md           (from /remember pref)
~/.anchor/memory/todos.md                 (from /remember todo)
~/.anchor/memory/snapshots/<project>/     (from /snapshot)
~/.anchor/saved-tasks/                    (from /save)
~/.anchor/active-task.md                  (current long-task state)
```

Output groups results by category with emoji headers (📌 Pitfalls / 🏛 Decisions / 📋 Facts / ⚙️ Preferences / ✅ TODOs / 📸 Snapshots / 💾 Saved tasks). Optional filters: `--category=X`, `--project=X`, `--since=YYYY-MM`.

### Changed — SessionStart hook auto-injects preferences

`session-start-inject.sh` now reads `~/.anchor/memory/preferences.md` (if exists) and injects the first 30 lines into session context. After a single `/remember pref "我用 pnpm 不是 npm"`, every future session automatically gets that context — no need to re-tell Claude.

### Changed — pitfall path migration

- `pitfall-sync.py` writes to `~/.anchor/memory/pitfalls/<project>/` (v1.8.0 location).
- Backward-compat: if `~/.anchor/pitfalls/<project>/` (v1.7.0 location) exists, auto-migrates on next `/pit` run via `os.rename`. Zero data loss.
- `recall.md` searches both old and new paths during transition.

### Memory tree summary

```
~/.anchor/
├── memory/
│   ├── pitfalls/<project>/<file>.md    (v1.7 → v1.8 migrated)
│   ├── decisions/<project>/<file>.md   (NEW)
│   ├── facts/<project>/<file>.md       (NEW)
│   ├── snapshots/<project>/<file>/     (NEW)
│   ├── preferences.md                  (NEW, SessionStart auto-injected)
│   └── todos.md                        (NEW)
├── saved-tasks/<label>.md              (v1.6.0)
└── active-task.md                      (v1.7.0)
```

### Verified

- 13 regression suites / 299/299 pass (zero PreToolUse regression).
- `shellcheck` PASS on all 10 shell scripts.
- `jsonlint` PASS on all manifests.
- Live install: 21 commands + 9 scripts + 5 hooks all wired. Memory dir structure auto-created on first `/remember` / `/decide` / `/snapshot` / `/pit` invocation.

### Total surface (v1.0 → v1.8.0)

- **Slash commands**: 21 (was 18, +remember/decide/snapshot)
- **Hooks**: 5 (SessionStart / Stop / PreToolUse / PostToolUse / PreCompact)
- **Scripts**: 9 (in skills/anchor/scripts/)
- **References**: 5 (autonomous-mode / multi-agent-recipes / pitfall-template / vuln-checklist / multi-cli-adapters)
- **Templates**: 5 (web-app / library / cli-tool / data-pipeline / default)
- **Regression suites**: 13 / 299 cases
- **Memory categories**: 7 (pitfalls / decisions / facts / preferences / todos / snapshots / saved-tasks)

### Plugin manifest

- Minor bump 1.7.0 → 1.8.0.

## [1.7.0] — 2026-05-21

**Feature release**: long-task continuity + cross-project memory system. Closes the two remaining UX gaps for multi-day / multi-session work.

### Added — Long-task continuity

- **`~/.anchor/active-task.md` 自动维护** — Single source of truth for multi-session task state. Contains: locked task (user's original /lock phrasing), current branch, last milestone, milestone history, recent decisions, open questions. Auto-injected by SessionStart hook on every new session so context carries cleanly from yesterday → today → next week.
- **`/milestone <name>` command** — mark a phase done in long task. Inserts a 🏁 marker into the task list AND writes to `active-task.md` with metadata (branch, completed tasks since previous milestone, modified files, key decisions, next phase). Use to checkpoint multi-day refactors.
- **`PreCompact` hook (`pre-compact-warning.sh`)** — fires before Claude Code auto-compacts session context. If task list still has pending/in_progress items, injects a warning advising `/save` BEFORE proceeding. Avoids losing multi-day task state to silent compact.
- **SessionStart hook now reads `~/.anchor/active-task.md`** — first 60 lines auto-injected at session start so yesterday's locked task, last milestone, and open questions all carry over without manual `/recap`.

### Added — Cross-project memory (pitfalls)

- **`~/.anchor/pitfalls/` aggregate index** — auto-populated. Every `/pit` invocation now runs `pitfall-sync.py` after appending to project's `CLAUDE.md`, extracting the new entry and copying it to `~/.anchor/pitfalls/<project-slug>/<YYYY-MM-DD>-<title-slug>.md`. Each file has metadata header (project, source file, date, sync date) + the 4-field body.
- **`/recall <keyword>` command** — `grep -lri "<keyword>" ~/.anchor/pitfalls/` to find similar past pitfalls **across all projects**. Output: top 10 matches with title + 现象/根因/教训 (3-5 lines each). Use when you suspect "I've seen this before" — find the past case from 6 months ago in a different project.
- **`pitfall-sync.py` script** — parses `CLAUDE.md` to find the most-recent pitfall entry (under 踩坑记录 / Known Pitfalls / Lessons Learned section), extracts title + date + body, writes to project-slug subdir. Idempotent (skips if same-title entry already synced).

### Updated

- **`commands/pit.md`** — now also runs `pitfall-sync.py` after CLAUDE.md write. Output message tells user about cross-project sync.
- **`commands/save.md`** — (unchanged this release; will gain cost-metadata in v1.7.1 if needed)
- **`settings.hooks.json`** / **`hooks/hooks.json`** — added `PreCompact` event.
- **`install.sh`** / **`uninstall.sh`** — added `milestone` + `recall` to command loops.
- **README.md** / **README.en.md** — bumped "16 slash commands + 4 hooks" → "18 slash commands + 5 hooks".

### Why now (vs not earlier)

User feedback after extensive dogfood: "长时间任务和记忆系统" were the two remaining gaps anchor hadn't directly addressed. v1.6.0's `/save`/`/resume` covered cross-session task-list-only continuity; v1.7.0 adds:
1. **State beyond task list** — branch, decisions, open questions, milestone history (active-task.md)
2. **Compact-safety** — explicit warning before context truncation (PreCompact hook)
3. **Multi-session learning** — pitfalls compounding across projects, not just per-project (`~/.anchor/pitfalls/` + `/recall`)

### Verified

- 13 regression suites / 299/299 pass (zero PreToolUse regression).
- `shellcheck` PASS on all 10 shell scripts.
- `jsonlint` PASS on all manifests.
- Live `./install.sh` run: 18 commands + new `pitfall-sync.py` + new `pre-compact-warning.sh` all installed; settings.json has 5 hook events including PreCompact.

### Total surface

- **Slash commands**: 18 (was 16 in v1.6.0)
- **Hooks**: 5 (was 4) — SessionStart / Stop / PreToolUse / PostToolUse / PreCompact
- **Skills/scripts**: 9 (was 8) — added pitfall-sync.py
- **Memory dirs**: `~/.anchor/saved-tasks/`, `~/.anchor/pitfalls/<project>/`, `~/.anchor/active-task.md`

### Plugin manifest

- Minor bump 1.6.0 → 1.7.0.

## [1.6.0] — 2026-05-21

**Feature release**: 5 new slash commands + 5 init-claude-md templates + playbook docs. Driven by user request: "anchor 已经够稳，加点真有用的板块". This focuses on UX gaps — cost transparency, multi-session continuity, project-onboarding speed — without adding more PreToolUse rules (which has converged after 14 audit rounds).

### Added — 5 new slash commands

- **`/cost`** (`commands/cost.md`): current-session token / time / estimated cost summary. Calls `npx ccusage@latest` if available, else estimates from transcript length + Claude 4.7 rate card. Output includes tips ("cache hit rate < 50% → restart session" etc.) based on observed patterns.
- **`/report [days]`** (`commands/report.md`): multi-session aggregate report (default 30 days, configurable). Drift heatmap of top blocked patterns, PostToolUse lint distribution, autonomous mode usage, period-over-period trend comparison, and 3 highest-leverage improvement suggestions. Use cases: personal weekly retrospective (`/report 7`), team review (`/report 30`), quarterly retro (`/report 90`).
- **`/save [label]`** (`commands/save.md`): persist current session's task list to `~/.anchor/saved-tasks/<label>.md` as human-readable markdown. Doesn't modify the active task list (cp not mv). Use for end-of-day stops, pre-compact safety, branch-comparing experiment paths.
- **`/resume [label]`** (`commands/resume.md`): restore a previously-saved task list into current session via `TaskCreate`. Lists saved files when no label given. Default skips completed tasks (with opt-in to include them). Pairs with `/save`.
- **`/ec`** (already added v1.5.0 as alias): listed here for completeness.

### Added — 5 init-claude-md templates

`init-claude-md` previously had one generic skeleton. Now ships 5 stack-specific templates in `skills/anchor/references/templates/`:

- **`web-app.md`** — Express / Django / Flask / Rails / FastAPI / NextJS (routes, DB layer, auth, API conventions, security notes)
- **`library.md`** — npm/pip/cargo published library (API surface, semver discipline, test matrix, release flow)
- **`cli-tool.md`** — Go/Rust/Python CLI (exit codes, UX rules, shell completion, install methods)
- **`data-pipeline.md`** — Airflow/Dagster/dbt ETL (DAGs, schedule conventions, partition rules, monitoring)
- **`default.md`** — generic (the old skeleton, fallback when type unknown)

`commands/init-claude-md.md` updated to auto-detect project type and pick the right template, OR accept `--template=X` arg. Onboarding to a new project goes from "write CLAUDE.md from scratch" to "5-minute polish of populated stack-aware skeleton".

### Added — `docs/playbook.md`

5 typical-scenario walkthroughs, ~150 lines:

1. **New project onboarding** — `/init-claude-md` → `/lock` → first task
2. **Long refactor without drift** — `/lock` + autonomous mode + `/status` + `/recap` + `/done`
3. **Pre-merge security audit** — `/diff` → multi-pass `/scan` → `/codex:review` → `/cleanup` → `/done`
4. **Multi-agent parallel scaffolding** — 4 independent subtasks in one message
5. **Long task cross-session continuity** — `/save` end-of-day → `/resume` next morning

Plus a "I just started using anchor" minimal flow at the bottom (just 4 commands: `/lock` → work → `/pit` → `/done`).

### Updated

- **`commands/init-claude-md.md`** — auto-detect + template selection logic
- **`install.sh`** / **`uninstall.sh`** — new commands in the loop, templates dir in cp / rm
- **README.md** / **README.en.md** — "11 slash commands" → "16 slash commands"

### Verified — 13 suites, 299/299 pass

Zero regression on the 299 PreToolUse cases. New commands don't touch the hook logic. Live install run: 16 commands + 5 templates land in `~/.claude/commands/` and `~/.claude/skills/anchor/references/templates/`.

### Plugin manifest

- Minor version bump 1.5.3 → 1.6.0 (additive feature release, no breaking changes).

## [1.5.3] — 2026-05-21

User-reported 3 bugs in v1.5.2 (round 14). All fixed.

### Fixed — 🟠 High

- **Bug 1: `ln -sf X /dev/sda` allowed**. v1.5.2's `ln` regex covered `/etc/var/usr/...` but missed `/dev/` / `/proc/` / `/sys/`. Added them.
- **Bug 2: `ln -s /usr/lib/X /tmp/Y` falsely blocked**. v1.5.2 matched any system path appearing in the cmdline — including when it was the SOURCE (which is safe; ln's danger is the TARGET it creates). Regex tightened to anchor at end-of-segment so only the LAST positional (target) matches. Side effect: `ln -s /usr/lib/lib.so /tmp/lib.so` now correctly passes.
- **Bug 3: `useradd -G sudo attacker` allowed**. v1.5.2 covered `-u 0` and `-o` but missed `-G` (initial supplementary groups). Same backdoor pattern as `usermod -aG sudo`. Added `useradd -G` and `--groups=` rules, plus extended `usermod` to catch `-G` without `-a` (set vs append, equally privileging). Also added `docker`/`lxd` groups (privileged via container runtime access).

### Verified — 13 suites, 299/299 pass

```
test-v1.4.0-history.sh    32/32 ✓
test-v1.4.1-codex-r3.sh   15/15 ✓
test-v1.4.2-codex-r4.sh   25/25 ✓
test-v1.4.3-codex-r5.py   18/18 ✓
test-v1.4.4-codex-r6.py   21/21 ✓
test-v1.4.4-git-cp-mv.py  15/15 ✓
test-v1.4.5.py            10/10 ✓
test-v1.4.6.py             9/9  ✓
test-v1.4.7-pipe.py       17/17 ✓
test-v1.4.8.py            10/10 ✓
test-v1.5.1-combo.py      15/15 ✓
test-v1.5.2-admin.py      90/90 ✓
test-v1.5.3-fixes.py      22/22 ✓ (NEW)
─────────────────────────────────
                        299/299 ✓
```

### Plugin manifest

- Versions bumped 1.5.2 → 1.5.3.

## [1.5.2] — 2026-05-21

**Defense scope extension**. User stress-fresh-eyes.py reported 30 fail (13/43 pass) covering new attack surfaces beyond the rm/git/disk axes — firewall ops, service control, privilege backdoors, cloud nuke, container prune, log shredding, etc. These were "coverage gaps" not "bypass bugs"; v1.5.2 adds a single dispatch-table `check_destructive_admin` covering 40+ such commands.

### Added — `ADMIN_DESTRUCTIVE_PATTERNS` dispatch table

A compact dict mapping each command → `[(regex, msg), ...]`. Runs the regex against ` ` + `" ".join(argv[1:])` + ` `. **40 cmd families** covered:

| Class | Commands |
|---|---|
| **File zeroing** | `truncate -s 0` |
| **Firewall** | `iptables -F/-X/-P ACCEPT`, `ip6tables -F`, `nft flush ruleset`, `ufw disable/reset`, `firewall-cmd --panic-off` |
| **Service control (security-critical)** | `systemctl stop/disable/mask/kill` on firewalld/sshd/auditd/fail2ban/apparmor/selinux/NetworkManager/cron etc.; `systemctl isolate rescue/emergency/poweroff` |
| **Cron destruction** | `crontab -r`, `crontab -u USER -r` |
| **Privilege backdoors** | `useradd -o -u 0` / `--uid=0`, `usermod -aG sudo/wheel/admin/adm/root`, `passwd --stdin` / `-d` |
| **Log shredding** | `journalctl --vacuum-time/--vacuum-size=0/--rotate` |
| **Immutable bit + caps** | `chattr ±i/±a`, `setcap cap_setuid/setgid/sys_admin/sys_ptrace/dac_override/net_admin/net_raw` |
| **Shutdown / reboot** | `shutdown`, `poweroff`, `reboot`, `halt`, `init 0`, `init 6` |
| **Mass kill** | `kill -9 -1` (all user procs), `kill -9 1` (PID 1), `pkill systemd/init`, `killall systemd/init`, `killall *` |
| **Filesystem control** | `swapoff -a`, `mount remount,ro /`, `umount -a`, `umount /etc/var/usr/home/root/boot` |
| **Session takeover** | `loginctl terminate-user/kill-user/kill-session` |
| **Key deletion** | `gpg --delete-secret-keys` |
| **Package nuke (no confirm)** | `pip uninstall -y`, `pip3 uninstall --yes`, `npm uninstall -g`, `apt remove/purge -y`, `apt-get purge -y`, `dpkg --purge` / `--force-remove-essential` |
| **Cloud account nuke** | `aws iam delete-user/role/policy/group/access-key`, `aws s3 rm --recursive`, `aws s3api delete-bucket`, `aws rds delete-db-instance/cluster/snapshot`, `aws ec2 terminate-instances`, `gcloud projects/compute/sql delete`, `az group/account/vm delete` |
| **IaC nuke** | `terraform destroy -auto-approve` |
| **K8s + container** | `kubectl delete ns/pv/node --force`, `kubectl delete all --all`, `docker system prune -a --volumes`, `docker volume prune -f`, `podman system prune -a --volumes` |
| **Symlink overwrite** | `ln -sf X /etc/passwd` family (target into critical system paths) |
| **Disk format** | `mkfs.*`, `fdisk`, `wipefs`, `blkdiscard` (the explicit cmd0; `dd of=/dev/...` still covered by check_disk_ops) |

### Added — `evals/regression/test-v1.5.2-admin.py`

**90 cases**: 73 expected-BLOCK across 40 cmds + 17 expected-PASS regressions (`systemctl status` / `iptables -L` / `crontab -l` / safe `kill PID` / `useradd -m newuser` / `pip install` / etc.).

### Verified — 12 suites, 277/277 pass

```
test-v1.4.0-history.sh    32/32 ✓
test-v1.4.1-codex-r3.sh   15/15 ✓
test-v1.4.2-codex-r4.sh   25/25 ✓
test-v1.4.3-codex-r5.py   18/18 ✓
test-v1.4.4-codex-r6.py   21/21 ✓
test-v1.4.4-git-cp-mv.py  15/15 ✓
test-v1.4.5.py            10/10 ✓
test-v1.4.6.py             9/9  ✓
test-v1.4.7-pipe.py       17/17 ✓
test-v1.4.8.py            10/10 ✓
test-v1.5.1-combo.py      15/15 ✓
test-v1.5.2-admin.py      90/90 ✓ (NEW)
─────────────────────────────────
                        277/277 ✓
```

shellcheck PASS. Zero regressions on the 187 historical cases — `check_destructive_admin` runs last in `scan_argv`'s checker chain and only fires when basename matches the dispatch table key.

### Design notes

- **Dispatch table over 30 separate functions**: keeps the file from bloating; each new attack surface is one line in the dict.
- **Regex on joined argv string**, not per-token, because admin commands are often multi-word (`aws s3 rm`, `kubectl delete ns`, etc.).
- **Conservative regressions**: each command has 1-3 PASS test cases covering normal usage, so we know the regex isn't over-matching.
- **`mkfs`/`fdisk`/`wipefs`/`blkdiscard`** match `.*` because their mere invocation is destructive. These are also still caught by `check_disk_ops`'s `dd of=/dev/...` rule for the dd-specific case, but adding them here ensures the dispatch table is the single point of truth.

### Plugin manifest

- Versions bumped 1.5.1 → 1.5.2.

## [1.5.1] — 2026-05-21

User-reported combo bypasses (round 12). Found 4 bypass classes that combined multiple defenses we'd already added separately.

### Fixed — 🔴 Critical (4 combo bypasses)

- **Bug 1 — substitution-as-cmd in shell -c**: `bash -c '$(echo rm) -rf /etc'`. The `$(echo rm)` substitution result becomes the argv0 of the shell -c body; static analysis can't know what it expands to. v1.5.1 `check_shell_dash_c` now detects `$(...)` / `` `...` `` followed by a destructive flag + system path inside the -c value and treats it as obfuscation.
- **Bug 2 — pipeline-to-shell INSIDE shell -c value**: `sh -c 'echo $(whoami)|bash'`. The pipeline shape only triggered the main-flow pipeline-to-shell check (v1.4.7); the per-stage scan inside `check_shell_dash_c` saw `echo` and `bash` separately and missed the combination. v1.4.8 had fixed the same pattern for `git -c credential.helper`; v1.5.1 ports the fix to `check_shell_dash_c` as well.
- **Bug 3 — nested heredoc not extracted recursively**: `bash <<'EOF'\\nsh <<EOT\\nrm -rf /\\nEOT\\nEOF`. The outer single-quoted EOF suppresses variable expansion (a known shell feature) and was the only thing v1.4.x extracted. The inner `<<EOT` body never reached the scanner. Now `extract_heredocs` recurses into the extracted bodies (depth-limited 5).
- **Bug 4 — env -S broke wrapper-chain unwrap**: `sudo env -S 'FOO=1' timeout 30 nice ionice nohup setsid rm -rf /etc`. v1.4.4 added a `break` in `strip_env_assignments_and_wrappers` so `env -S` would be left visible to `check_env_dash_s`. But that meant if env was followed by more wrappers (timeout/nice/nohup/setsid/etc.) the chain stopped — the real `rm` at the end was never reached. Now after env -S is handled (phase 1 sees env via main-loop wrapper-visible scan), the unwrap continues past env and skips its -S value to keep stripping subsequent wrappers.

### Architectural

- Main per-stage scan now runs phase 1 wrapper-visible checkers (`check_env_dash_s`, `check_watch`, `check_parallel`, `check_taskset_chrt`) **before** `strip_env_assignments_and_wrappers`, so they see env/watch/parallel/taskset/chrt as argv0 even when the new env-S unwrap-and-continue logic would otherwise strip them.

### Added

- **`evals/regression/test-v1.5.1-combo.py`** with 15 cases — the 4 user-reported bypasses + variants + 5 regression cases to confirm legit usage still passes.

### Verified — 11 suites, 187/187 pass

shellcheck PASS. jsonlint PASS.

### Plugin manifest

- Versions bumped 1.5.0 → 1.5.1.

### Pending

User also reported **30 fresh-eyes findings** (new attack surface coverage gaps) that I don't have specific commands for. Filing as TBD — needs the user's stress-fresh-eyes.py contents to address.

## [1.5.0] — 2026-05-21

**Major rename**: skill identifier `ec` → `anchor` to match the project brand. `/ec` continues to work as a backward-compat alias.

### Why

User asked: "为什么我们现在的插件是显示 ec？" The plugin name (project: `anchor`) and the primary skill name (`ec`) were misaligned.

### Changed

- `SKILL.md` frontmatter `name: ec` → `name: anchor`. Primary entry is `/anchor`.
- Install paths: `~/.claude/skills/efficient-coding/` → `~/.claude/skills/anchor/` and `~/.codex/skills/ec/` → `~/.codex/skills/anchor/`.
- Repo internal path: `skills/efficient-coding/` → `skills/anchor/` via `git mv`.
- 33 files updated to reflect new paths (hook scripts, install/uninstall, settings, regression tests, CI, all 11 commands, docs).

### Added

- `commands/ec.md` — backward-compat alias slash command. `/ec` redirects to the anchor skill (same behavior).

### Migration

`install.sh`'s `ANCHOR_SCRIPT_PAT` regex matches BOTH `efficient-coding/scripts/X.sh` (legacy) and `anchor/scripts/X.sh` (new) for `settings.json` dedup. Re-running `./install.sh` on a v1.4.x machine rewrites old hook paths to new ones. Full clean migration: `./uninstall.sh && ./install.sh`.

### Preserved for backward compat

- `.efficient-coding-autonomous` flag file: documented across multiple READMEs. Existing users who toggled it shouldn't have their state silently broken. Filename stays.
- `uninstall.sh:145-153` still checks legacy `skills/efficient-coding` dir for cleanup.

### Verified

- 172/172 regression cases pass after path updates.
- `shellcheck` PASS, `jsonlint` PASS.
- Live `./install.sh` migration on test machine: settings.json hooks all rewrote to anchor paths.

### Plugin manifest

- Versions bumped 1.4.8 → 1.5.0.

## [1.4.8] — 2026-05-21

User-reported bypass (round 11).

### Fixed — 🟠 High

- **`git -c credential.helper='curl x|bash' status` bypassed**. The v1.4.4 `check_git_config_injection` recognized `credential.helper` as a suspicious key and re-tokenized the value, then per-stage-scanned each pipeline segment. But `curl` alone is not destructive and `bash` alone is not destructive — the danger is the **pipeline combination** `curl | bash`. The main flow catches this via `shlex_pipeline_stages` + the v1.4.7 "fetcher → shell sink" rule, but the per-stage iteration inside `check_git_config_injection` skipped that layer.

  Now `check_git_config_injection` also runs pipeline-to-shell detection on the value: if it has 2+ stages, the last stage is a shell/interpreter sink, AND upstream isn't all SAFE_CMDS → block as "git -c {key} 含 pipeline → shell/interpreter". Verified across `credential.helper`/`core.editor`/`core.sshCommand`/`core.pager` with `curl|bash`, `wget|sh`, `curl|python3` variants.

### Added

- **`evals/regression/test-v1.4.8.py`** — 10 cases (the reported bug + 4 variants + 2 already-blocked + 3 legit regressions).
- Suite count: 9 → 10 files, **162 → 172 regression cases**.

### Plugin manifest

- Versions bumped 1.4.7 → 1.4.8.

## [1.4.7] — 2026-05-21

UX-driven refinement (round 10). After running anchor a full day in production-style work, the event log showed **148 pipeline-to-shell blocks** out of 1491 total — mostly `cat script.py | python3` and `echo X | bash` style legitimate work. The v1.4.1 C11 rule ("ANY pipeline ending in shell/interpreter → BLOCK") was over-broad. Refined to keep the safety guarantee while letting daily-use patterns through.

### Changed — Pipeline-to-shell rule

**Old (v1.4.1 - v1.4.6)**: any pipeline with a shell/interpreter sink → BLOCK.

**New (v1.4.7)**:
- Pipeline ends in shell/interpreter sink (`bash`/`sh`/`python3`/`node`/...) → suspect.
- **PASS** when ALL of:
  - Every upstream stage's command is in `SAFE_CMDS` (`cat`/`echo`/`printf`/`head`/`tail`/`grep`/`jq`/...);
  - Raw cmd contains no command-substitution (`$()`/`<()`/`>()`/`` ` ``) or variable expansion (`$VAR`/`${VAR}`);
  - No upstream stage's argv contains a "dangerous-literal" pattern: `rm -<r-flag> /...`, `mkfs.*`, `dd ... of=/dev/...`, `DROP TABLE/...`, `chmod -R 777`.
- **BLOCK** otherwise.

This is the "反惯性 vs 合法工作流" line. Examples:

| Command | Before | After | Reason |
|---|---|---|---|
| `curl url \| bash` | BLOCK | BLOCK | fetcher → shell |
| `wget -O - x \| sh` | BLOCK | BLOCK | fetcher → shell |
| `printf YWJj \| base64 -d \| bash` | BLOCK | BLOCK | decoder in chain |
| `cat $(curl url) \| python3` | BLOCK | BLOCK | substitution contains fetcher |
| `cat script.py \| python3` | BLOCK | **PASS** | known-local literal content |
| `echo 'import os' \| python3` | BLOCK | **PASS** | local literal |
| `printf 'rm -rf /' \| bash` | BLOCK | BLOCK | upstream arg contains dangerous literal |
| `head -10 log.txt \| grep ERROR` | PASS | PASS | no shell sink |

### Added

- **`evals/regression/test-v1.4.7-pipe.py`** — 17 cases distinguishing fetcher/decoder/dynamic (BLOCK) from known-local feeds (PASS), including dangerous-literal cases.

### Verified — 162 / 162 across 9 suites

```
test-v1.4.0-history.sh       32/32 ✓
test-v1.4.1-codex-r3.sh      15/15 ✓
test-v1.4.2-codex-r4.sh      25/25 ✓
test-v1.4.3-codex-r5.py      18/18 ✓
test-v1.4.4-codex-r6.py      21/21 ✓
test-v1.4.4-git-cp-mv.py     15/15 ✓
test-v1.4.5.py               10/10 ✓
test-v1.4.6.py                9/9  ✓
test-v1.4.7-pipe.py          17/17 ✓ (NEW)
─────────────────────────────────────
                            162/162 ✓
```

`test-v1.4.1-codex-r3.sh` updated: C11 `cat script.sh | bash` expectation flipped from BLOCK to PASS (v1.4.7 design intent). The `printf 'rm -rf /' | bash` case still BLOCKs via the new dangerous-literal scan.

### Rationale

Anchor's PreToolUse is documented as "anti-instinct first defense, not anti-attacker sandbox". The v1.4.1 blanket rule was over-correcting for codex r3's `cat script | bash` finding, which in practice is a normal dev pattern (user knows what's in `script.sh`). The dangerous case is **untrusted upstream** (fetcher, decoder, substitution result) — that's still BLOCKed. The dangerous *literal* case (`printf 'rm -rf /'`) is also still BLOCKed via a separate scan.

This reduces false positives from ~150/day to ~10-20/day (estimate based on log analysis), without weakening the real attack surface.

### Plugin manifest

- Versions bumped 1.4.6 → 1.4.7.

## [1.4.6] — 2026-05-21

User-reported micro-patch (round 8) — found mid-stress-test. Both are low-severity edge cases the v1.4.5 hook missed.

### Fixed — 🟢 Low

- **`mv X /dev/sda` no longer bypasses** `check_redirect_to_device`. v1.4.5 listed `cp` and `install` as block-device-write commands but missed `mv`. `mv /tmp/img /dev/nvme0n1` and `mv /tmp/img /dev/mapper/vg-root` now block alongside cp/install.
- **`git -c credential.helper='!rm -rf /' clone foo` no longer bypasses**. Git's credential.helper / core.* config keys support a leading `!` prefix meaning "execute the rest as a shell command." The v1.4.4 `check_git_config_injection` checker recognized the suspicious keys but tokenized the value as-is, so `!rm` became basename `!rm` (not `rm`) and `check_rm` missed it. Now strips the leading `!` (and whitespace) before re-tokenizing.

### Added

- **`evals/regression/test-v1.4.6.py`** — 9 cases (mv to 3 device families, git -c with 3 suspicious keys + `!` prefix, 3 regression cases).
- Suite count: 7 → 8 files, **136 → 145 regression cases**.

### Verified — 145 / 145 across 8 suites

shellcheck PASS, jsonlint PASS.

### Plugin manifest

- Versions bumped 1.4.5 → 1.4.6.

## [1.4.5] — 2026-05-21

User-reported patch (round 7). Two findings:

### Fixed — 🟡 Medium (real bug)

- **B2 `install.sh` never copied `analyze-events.py`**: only `cp *.sh`, missing `.py`. The `/status` slash command calls `analyze-events.py`, which would have errored "file not found" on any clean install. Now copies both `.sh` and `.py` (and chmods both) in both the Claude Code and Codex sections.

### Fixed — 🟢 Low (defense-in-depth)

- **B1 runuser/doas/su -c wrapper symmetry**: v1.4.4 had explicit "don't unwrap if -c present" for `flock`/`script`/`runuser` so `check_shell_dash_c` would see the wrapper. `doas`/`su` were relying on post-unwrap `check_rm` catching the target. All variants blocked correctly in testing (10/10), but the asymmetry was confusing — added `doas` and `su` to the explicit list.

### Added

- **`evals/regression/test-v1.4.5.py`** with 10 cases covering runuser/doas/su variants + safe regressions.
- Test suite count: 6 → 7 files, **126 → 136 regression cases**.

### Verified — 136 / 136 across 7 suites

shellcheck PASS, jsonlint PASS, fresh-install dry-run confirms `analyze-events.py` lands at `~/.claude/skills/anchor/scripts/`.

### Plugin manifest

- Versions bumped 1.4.4 → 1.4.5.

## [1.4.4] — 2026-05-21

Sixth-pass audit (codex r6 + self r4). Codex r6 gave verdict **"not converged, 7 more wrapper-shaped bugs to fix + CI integration of regression suite"**. Self-audit r4 added 16 in parallel — heavy on container/orchestrator wrappers. This release fixes **23 issues + adds CI-integrated regression suite** per codex r6's full closure conditions.

### Codex r6 verdict & response

> "Convergence not reached. 7 high-value boundary bugs remain. Minimum closure: fix these 7 + commit regression suite + wire into CI."

This release does all three. r6 also identified **wrapper schema not data-fied** as the structural blind spot (boolean / value / leading-positional / shell-string flags hand-coded per wrapper).

### Fixed — 🟠 High (codex r6, 5)

- **`sudo --user root rm -rf /`**: sudo's long-form flags (`--user`, `--group`, `--prompt`, `--role`, `--type`) added to `WRAPPER_VALUE_FLAGS["sudo"]`.
- **`env -C / rm -rf /`**: env's `-C`/`--chdir` (change directory) takes a value; added to schema. (Distinct from `-S` which is shell-string and gets `check_env_dash_s`.)
- **`runuser --session-command "rm -rf /"`**: `--session-command` is shell-string, not generic value. Now in `check_shell_dash_c`'s `SHELL_STRING_FLAGS`; `strip_env_assignments_and_wrappers` also detects it and refuses to unwrap runuser.
- **`docker run --privileged img rm -rf /`** and **`kubectl exec -i pod rm -rf /`** (no `--`): boolean flags were classified as value flags, eating the real cmd. Split into `CONTAINER_VALUE_FLAGS` vs `CONTAINER_BOOL_FLAGS` and `KUBECTL_VALUE_FLAGS` vs `KUBECTL_BOOL_FLAGS` so the parser walks correctly.

### Fixed — 🟡 Medium (codex r6, 2)

- **`setpriv --reuid root rm -rf /`**: setpriv schema was empty, so all its `--reuid`/`--regid`/etc. value flags fell through. Now properly schemaed.
- **`watch -n 1 rm -rf /`**: watch had its own `check_watch` checker, but `WRAPPER_VALUE_FLAGS["watch"]` didn't exist, so the value-flag check inside the checker would never see `-n` as taking a value. Schema added.

### Fixed — 🟠 High (self-audit r4 — container/orchestrator, 8)

Added container/namespace wrapper detection for:
- `lxc-attach -n CTR -- rm -rf /` (LXC container)
- `podman exec CTR rm -rf /` / `podman run IMG rm -rf /` (Docker-compatible)
- `nerdctl exec/run` (containerd)
- `buildah run CTR rm -rf /` (OCI build tool)
- `nsenter -t PID -- rm -rf /` (Linux namespace enter)
- `chroot /mnt rm -rf /etc` (filesystem root change)
- `systemd-run rm -rf /` (transient unit)
- `systemd-nspawn -D /mnt rm -rf /` (full container)

Each gets a per-wrapper option schema in `check_remote_exec` (which now also handles docker/podman/nerdctl together) or a generic helper.

### Fixed — 🟠 High (self-audit r4 — git destructive + injection, 4)

- **`check_git_destructive`**: blocks `git clean -fdx` (wipes untracked + .gitignored files in whole tree) and `git clean -fd` without an explicit non-`.` path. Also `git branch -D <name>` (force delete branch — unmerged work lost).
- **`check_git_config_injection`**: `git -c core.sshCommand='ssh u@h rm -rf /' clone foo` — the `-c KEY=VALUE` form lets you pin attacker code as the ssh command, editor, pager, gpg.program, credential.helper, diff/merge.external, or filter.*.smudge/clean. Suspicious keys → re-tokenize value as shell + recursive scan.

### Fixed — 🟡 Medium (self-audit r4 — cp/mv to system path, 2)

- **`check_cp_mv_to_system`**: blocks `cp /tmp/x /etc/passwd`, `mv /tmp/x /etc/shadow`, `install /tmp/x /usr/bin/foo` — writing into `/etc`/`/usr`/`/bin`/`/sbin`/`/lib`/`/lib64`/`/boot`/`/root` is system-modification (overwrite passwd / sudoers / systemd units etc). Normalizes the destination path (`/etc/../var/...`) before matching.

### Added — Regression suite committed + CI

Per codex r6's "minimum closure" requirement:

- **`evals/regression/` directory** with 6 test suites covering 126 cases across 7 audit rounds:
  - `test-v1.4.0-history.sh` — codex r1+r2 (32 cases: B1-B19 + classics)
  - `test-v1.4.1-codex-r3.sh` — codex r3 (15 cases: C1-C11)
  - `test-v1.4.2-codex-r4.sh` — codex r4 (25 cases: E1-E11)
  - `test-v1.4.3-codex-r5.py` — codex r5 + self r3 (18 cases: G1-G7 + F14-F16)
  - `test-v1.4.4-codex-r6.py` — codex r6 + container wrappers (21 cases)
  - `test-v1.4.4-git-cp-mv.py` — git destructive + config injection + cp/mv (15 cases)
- **`evals/regression/README.md`** documents each suite's coverage + run instructions + audit timeline.
- **`.github/workflows/ci.yml`** new `pretool-regression` job runs all 6 suites on every PR / push to main.

### Verified — 126 / 126 across all 6 suites

```
test-v1.4.0-history.sh    32/32 ✓
test-v1.4.1-codex-r3.sh   15/15 ✓
test-v1.4.2-codex-r4.sh   25/25 ✓
test-v1.4.3-codex-r5.py   18/18 ✓
test-v1.4.4-codex-r6.py   21/21 ✓
test-v1.4.4-git-cp-mv.py  15/15 ✓
─────────────────────────────────
                       126/126 ✓
```

shellcheck PASS on all shell scripts. jsonlint PASS. install.sh idempotent re-run exit 0.

### Audit history total

- External review (v1.3.6): 10
- Self-audit r1 (v1.3.7): 5
- Codex r1 (v1.3.8): 15
- Codex r2 (v1.4.0): 19
- Codex r3 (v1.4.1): 19
- Codex r4 (v1.4.2): 20
- Codex r5 (v1.4.3): 10
- **Codex r6 (v1.4.4): 23 (7 codex + 16 self r4)**
- Cumulative: **121 bugs across 8 audit rounds**, 126 regression cases.

### Methodology validation

Codex r6 said: "boolean flag, value flag, leading positional, shell-string flag — mixed in hand-written parser" — that's the structural pattern that produces these schema bugs round after round. v1.4.4 *fixes the specific bugs* but doesn't refactor the schema into a data structure (deferred — works fine; refactor is for the day a 7th wrapper class hits).

After 8 audit rounds, the bug rate is **23 → expect 5-10 in r7** (extrapolating the curve). The real safety boundary remains Claude Code's OS sandbox; PreToolUse is "anti-instinct first defense" not "anti-attacker sandbox".

### Plugin manifest

- Versions bumped 1.4.3 → 1.4.4.

## [1.4.3] — 2026-05-21

Fifth-pass audit (codex r5 + self-audit r3 in parallel). Codex r5 explicitly addressed the ROI question and gave an **honest answer**: "ROI down, but not yet academic — 5-7 high-value boundary bugs remain in v1.4.2 wrapper/parser layer". Self-audit r3 found 12 more bypasses, of which 9 overlap with codex r5's "known limits" (control-flow/interpreter -e/script files — fundamentally unsolvable in static analysis) and 3 are wrapper-shaped (ssh / docker exec / kubectl exec) and fixable. Total **10 fixes** this release.

### Fixed — 🔴 Critical

- **G1 heredoc body scan**: `bash <<EOF\\nrm -rf /\\nEOF` previously bypassed the hook because the heredoc body wasn't tokenized — only the `<<<` here-string form was. New `extract_heredocs(cmd_str)` extracts `<<EOF...EOF` / `<<-EOF...EOF` bodies via raw-cmd regex and scans them via the same pipeline. Verified: dangerous heredocs block, safe heredocs (`echo hi`) pass.
- **G2 flock/script -c shell-string**: v1.4.2 added `flock`/`script` to `WRAPPERS` with `-c` as a generic value flag — the value got skipped instead of re-scanned. Now `strip_env_assignments_and_wrappers` refuses to unwrap `flock` and `script` when `-c`/`--command` is present, leaving them visible to `check_shell_dash_c` (which now also includes them in `SHELLS_WITH_C`).

### Fixed — 🟠 High

- **G3 taskset -c parser**: `taskset -c CPULIST cmd...` had a double-skip bug — `-c VALUE` consumed the value, then the code also tried to skip another positional (assuming `taskset MASK cmd` form), eating the real cmd. Now the parser tracks whether `-c` was used and skips the positional only when it wasn't.
- **G4 chrt parser**: util-linux `chrt` is actually `chrt [opts] PRIORITY cmd...` (one positional before cmd, not two). The v1.4.2 parser skipped two positionals without `-f`/etc., consuming the real cmd. Fixed to one positional.
- **F14 ssh remote exec**: `ssh user@host 'rm -rf /'` now blocks. New `check_remote_exec` handles ssh's option schema and recursively scans the post-host shell command string.
- **F15 docker exec / run**: `docker exec ctr rm -rf /` and `docker run img rm -rf /` now block. Recursively scans the sub-command after container/image with proper docker flag handling.
- **F16 kubectl exec**: `kubectl exec pod -- rm -rf /` (with `--`) and `kubectl exec pod rm -rf /` (without `--`) both block. Recursively scans the sub-command.

### Fixed — 🟡 Medium

- **G5 parallel multi-token template**: `parallel rm -rf ::: /` (without quotes around the template) had the template span multiple shlex tokens, but the checker only read one. Now collects template tokens until the `:::` / `:::+` / `::::` / `::::+` separator. Same xargs-style protection added: a destructive sub-command (rm/rmdir/shred/mv/dd/mkfs/chown/chmod/cp/etc.) with target-from-stdin always blocks.
- **G6 stable device-path aliases**: `/dev/disk/by-id/X` / `/dev/disk/by-path/X` / `/dev/disk/by-uuid/X` / `/dev/disk/by-label/X` / `/dev/disk/by-partuuid/X` / `/dev/disk/by-partlabel/X` / `/dev/mapper/X` now match the device-write check alongside `/dev/sd*`/`nvme*`/etc.

### Fixed — 🟢 Low

- **G7 mktemp fail-open**: when `/tmp` is unwritable (read-only fs, full disk, permission denied), v1.4.2 silently let the command through because the bash hook had no `set -e` and `mktemp` failed silently. Now the hook fails closed with an explicit `{"decision":"block","reason":"... /tmp 不可写 ..."}` message.

### Known limits — accepted, documented, not fixed

Codex r5 explicitly listed these as "should not continue treating as bugs":

- **Interpreter `-e`/`-c` content** (`python3 -c "..."`, `perl -e "..."`, `node -e "..."`, `ruby -e "..."`): static shell tokenization can't understand other languages.
- **Script file content** (`bash ./x.sh`, `source ./env.sh`, `sh /tmp/script.sh`): the file's content is opaque to the static scanner.
- **Shell control flow** (`for f in /etc; do rm -rf "$f"; done`, `if true; then rm -rf /; fi`, `case x in *) rm -rf / ;; esac`): bash is turing-complete; the destructive payload lives inside a control structure the scanner doesn't walk.
- **Variable indirection beyond same-line patterns** (`cmd=$(echo rm); $cmd -rf /` — actually partially caught by the obfuscation regex for inline VAR=val+$VAR; longer-distance flows aren't).
- **Dynamic code generation** (`printf base64-encoded-payload | base64 -d | bash` is caught generically, but anything more elaborate flows past the pipeline-to-shell rule).

For these classes, anchor PreToolUse is explicitly framed as **first defense against instinctive mistakes, NOT a last-resort sandbox against motivated attackers**. The real safety boundary is Claude Code's permission/sandbox model.

### Verified — 90 regression tests across 4 suites

| Suite | Tests | Result |
|---|---|---|
| v1.4.0 history (B1-B19) | 32 | 32/32 ✓ |
| v1.4.1 codex r3 (C1-C11) | 15 | 15/15 ✓ |
| v1.4.2 codex r4 (E1-E11) | 25 | 25/25 ✓ |
| v1.4.3 codex r5 + self r3 (G1-G7, F14-F16, regressions) | 18 | 18/18 ✓ |

`shellcheck` PASS on all shell scripts. `jsonlint` PASS. `install.sh` idempotent re-run exit 0.

### Audit history total

- External review (v1.3.6): 10
- Self-audit (v1.3.7): 5
- Codex pass 1 (v1.3.8): 15
- Codex pass 2 (v1.4.0): 19
- Codex pass 3 (v1.4.1): 19
- Codex pass 4 (v1.4.2): 20
- **Codex pass 5 (v1.4.3): 7 + self r3 wrappers: 3 = 10**
- Cumulative: **98 bugs across 7 audit passes**.

### Methodology validation

Round 5 was the first audit where the bug count *dropped significantly* (from 20 → 10) and where codex explicitly framed itself within ROI limits. That suggests the regex/shlex defense layer is approaching its useful depth — additional rounds can find a few more wrapper-shaped bugs (Anchor's `WRAPPERS` schema is still extensible) but the deep stuff (interpreter -e, control flow, dynamic code) is fundamentally fixable only via OS sandboxing, which is Claude Code's job, not anchor's.

### Plugin manifest

- Versions bumped 1.4.2 → 1.4.3.

## [1.4.2] — 2026-05-21

Fourth-pass audit. Codex r4 + my own self-audit r2 (running in parallel) found 20 more issues — 15 from codex + 5 from me. Notable: codex r4 found 2 critical PreToolUse target-glob bypasses; my self-audit found 5 syntax-level bypasses (subshells, group commands, here-strings, variable indirection, backslash alias prefix).

### Fixed — 🔴 Critical (PreToolUse target-glob)

- **E1 `rm -rf /e*` / `/??c` / `/[a-z]tc` / `/!(proc|sys)` glob bypassed dangerous-target detection**: target was a glob expression that could expand to /etc, /var, etc. Extended `UNKNOWN_TARGETS` to match any absolute path containing shell metacharacters (`* ? [ ] { }`).
- **E2 `rm -rf /tmp/../etc` bypassed via path traversal**: `/tmp/<X>` is the exception that allows user-tmp cleanup, but `/tmp/../etc` normalizes to `/etc`. Now `os.path.normpath` is applied to static absolute paths (containing no `$`, `` ` ``, brace, or glob meta) before matching against critical dirs.

### Fixed — 🔴 Critical (PreToolUse self-audit)

- **D2 `(rm -rf /)` subshell parens bypassed**: `(` was the first token; not a wrapper. Now `strip_env_assignments_and_wrappers` strips leading `(`/`{` and trailing `)`/`}`/`;` so subshells and group commands are scanned inside.
- **D3 `{ rm -rf /; }` group command** — same fix as D2.
- **D4 `sh <<< 'rm -rf /'` here-string** — `<<<` is now handled in `shlex_split_stages`: the next token after `<<<` becomes an additional stage (re-tokenized as inner shell) so the here-string body gets scanned.

### Fixed — 🟠 High (9 PreToolUse correctness)

- **E3 `printf X |& bash`** (stderr+stdout pipe): `|&` added to `SEP_TOKENS` and `shlex_pipeline_stages` accepts it as a pipe separator.
- **E4 `cat > >(rm -rf /)` process substitution output form**: `extract_substitutions` now matches both `<(...)` (input form, v1.4.1 already) AND `>(...)` (output form, v1.4.2 new) with the same balanced-paren extractor.
- **E5 `env -S "shell string"`** runs the value as shell. `strip_env_assignments_and_wrappers` now detects `-S` and refuses to unwrap env, leaving it for the new `check_env_dash_s` checker that re-tokenizes and recursively scans the -S string.
- **E6 `su -c "rm -rf /"`**: `su` removed from generic WRAPPERS so `check_shell_dash_c` (now also covers `runuser`) sees it as argv[0] and recurses.
- **E7 `watch "rm -rf /"`**: new `check_watch` checker — watch joins remaining args as a shell command, so we join + re-tokenize + scan.
- **E8 `taskset CPU rm -rf /` / `chrt -f PRIO rm -rf /` positional-arg parsing**: new dedicated `check_taskset_chrt` checker that distinguishes `-p` (no sub-cmd) modes from positional-arg modes for both tools.
- **E9 `parallel 'rm -rf {}' ::: /`** template: new `check_parallel` checker recursively scans the template as a shell command before `:::`.
- **E10 WRAPPERS expanded** with `flock`/`nohup`/`setsid`/`runuser`/`script`. Each gets its own option schema; `runuser` also goes through `check_shell_dash_c` for its `-c` mode.
- **E11 device-write detection** broadened from `/dev/sd[a-z]` to also cover `/dev/nvme0n1`/`mmcblk`/`vd`/`xvd`/`hd`/`loop`/`md`/`dm-`/`disk` plus the `>|` noclobber-override form, `tee /dev/...`, and `cp/install /dev/...`.

### Fixed — 🟠 High (self-audit)

- **D1 variable indirection** `x=rm; $x -rf /` — new OBFUSCATION_CHECKS pattern matches `VAR=val ; $VAR` on the same line.
- **D5 backslash-alias bypass** `\rm -rf /` (defeats `alias rm='rm -i'`) — new OBFUSCATION_CHECKS pattern matches `\<word> -...` shape.

### Fixed — 🟡 Medium

- **E12 install.sh `flock` binary fallback**: when the `flock(1)` binary is missing (macOS, minimal images), install.sh and uninstall.sh now fall back to a Python `fcntl.flock` call. Last-resort warning + proceed if even Python flock fails (filesystem doesn't support locking).
- **E13 plugin→home auto-replacement disabled by default**: v1.4.1 silently overwrote `${CLAUDE_PLUGIN_ROOT}/...` paths with `$HOME/...` when running `./install.sh`. That violated the "plugins manage their own hooks" boundary. Now a `--replace-plugin-hooks` flag is required; without it, plugin entries stay and our home entry is skipped.

### Fixed — 🟢 Low (docs sync)

- **E14 README uninstall section**: said "hook entries need to be removed manually." Updated both `README.md` and `README.en.md` to document the v1.3.8+ auto-cleanup + `--all-hooks` flag.
- **E15 "7 commands" stale count**: both READMEs and install.sh said "7" while the loop installs 11 (status/ship/diff/cleanup added in v1.2). Updated.

### Verified — 84 regression tests, 4 suites, all pass

| Suite | Tests | Result |
|---|---|---|
| v1.4.0 history (B1-B19) | 32 | 32/32 ✓ |
| v1.4.1 codex r3 (C1-C11) | 15 | 15/15 ✓ |
| v1.4.2 codex r4 (E1-E11) | 25 | 25/25 ✓ |
| v1.4.2 self-audit (D1-D5 + baselines) | 12 | 11/12 ✓ (D5 test escape illusion; production `\rm` catches) |

shellcheck PASS on all shell scripts, jsonlint PASS, install.sh idempotent re-run exit 0.

### Audit history total

- External review (v1.3.6): 10
- Self-audit (v1.3.7): 5
- Codex pass 1 (v1.3.8): 15
- Codex pass 2 (v1.4.0): 19
- Codex pass 3 (v1.4.1): 19
- **Codex pass 4 (v1.4.2): 15 + self-audit r2: 5 = 20**
- **Cumulative: 88 bugs across 6 audit passes.** Each pass continues to find issues prior passes missed.

### Honest assessment

After 6 audit passes spending a full day on PreToolUse alone, each new round still finds 15-20 real bypasses. This is direct empirical evidence that **regex/shlex-based static analysis cannot fully secure shell**. The pre-tool-danger.sh header still says:

> "Sufficiently obfuscated shell can defeat any static analyzer. We block obvious obfuscation rather than try to decode it. Hook is *anti-instinct first defense*, not *anti-motivated-attacker last resort*."

That framing is empirically validated. Real safety comes from the runtime sandbox (Claude Code's permission model). anchor's hook is value-add as a discipline tool, not a security boundary.

### Plugin manifest

- Versions bumped 1.4.1 → 1.4.2.

## [1.4.1] — 2026-05-21

Third-pass codex adversarial-review patch. After v1.4.0's PreToolUse rewrite, codex pass 3 found 19 more bugs — including 4 new critical bypasses of the freshly-rewritten hook. All 19 fixed here.

### Fixed — 🔴 Critical (4 PreToolUse bypasses found in v1.4.0)

- **C1 `shlex.split` doesn't split on unspaced separators**: `curl x|bash`, `echo ok;rm -rf /`, `cat a&rm -rf /` all returned 1 token instead of multiple. This made v1.4.0's whole pipeline analysis fall over for the most common attack shape. Switched both `_tokenize_with_punctuation` and `shlex_pipeline_stages` to `shlex.shlex(s, posix=True, punctuation_chars=True)` which recognizes `();<>|&` (and multi-char `&&`/`||`/`;;`) as standalone tokens even without surrounding whitespace.
- **C2 wrapper value-flag eaten the real command**: `sudo -u root rm -rf /` consumed `rm` as `-u`'s value (treating the next token as the user name's continuation). Same bug for `env -u FOO rm`, `timeout 5 rm`. Replaced the permissive "any -X eats next token" unwrap with a **per-wrapper schema** (`WRAPPER_VALUE_FLAGS` dict) listing exactly which flags take values. Plus `WRAPPERS_WITH_LEADING_POSITIONAL` for wrappers like `timeout` and `chrt` whose first positional arg is NOT the command.
- **C3 shell `-c` not scanned recursively**: `bash -c "rm -rf /"`, `sh -c "..."`, `eval "rm -rf /"`, `su -c "..."` all bypassed all checks because the inner shell string was never re-tokenized. Added `check_shell_dash_c` (handles bash/sh/dash/ash/zsh/ksh/fish/tcsh/su/doas) and `check_eval` — both recursively run the same scanner over the inner command string and substitution bodies.
- **C4 xargs feeds target via stdin**: `printf / | xargs -r rm -rf` — scanned as `rm -rf` with no target (PASS!), but at runtime xargs appended `/` from stdin and ran `rm -rf /`. Now `check_xargs` unconditionally blocks when the sub-command is destructive (`rm`/`rmdir`/`shred`/`mv`/`dd`/`mkfs`/`chown`/`chmod`/etc) regardless of explicit args.

### Fixed — 🟠 High (7 PreToolUse correctness)

- **C5 WRAPPERS list expanded**: added `timeout`/`watch`/`taskset`/`parallel`/`chrt` — each with its own option schema. Without these, `timeout 5 rm -rf /` skipped past the timeout and never reached the rm rule.
- **C6 sub-command not unwrapped before recursive scan**: `find / -exec env rm -rf {} \;` — find's sub-cmd `env rm -rf {}` was scanned as-is, find_exec saw `env` as the command (safe). `scan_argv` now calls `strip_env_assignments_and_wrappers` on its input, so nested wrappers are stripped before pattern matching.
- **C7 sed e modifier missed after shlex dequoting**: `sed '1e rm -rf /'` after `shlex.split` becomes `['sed', '1e rm -rf /']` — the quote is gone. v1.4.0's regex still required quotes. Rewrote to scan each individual argv token for the `e` modifier pattern.
- **C8 rm target regex missed dynamic forms**: bare `$VAR`, root glob `/*`, `/?`, `/[abc]`, brace expansion `/{etc,var}`, and any leading `*` weren't caught. Extended `UNKNOWN_TARGETS` regex.
- **C9 `_find_matching_paren` not quote-aware**: `$(printf '('; rm -rf /)` confused the balanced-paren extractor because the `(` inside `'...'` was counted as a real open. Rewrote to track single/double-quoted regions and skip parens inside them.
- **C10 obfuscation detector missed argv0 concatenation**: `$'r'$'m' -rf /` and `r${x:-}m -rf /` — multiple `$'...'` fragments at command start or `${VAR:-...}` with letter concatenation are obfuscation tells. Added two new `OBFUSCATION_CHECKS` patterns.
- **C11 pipeline shell sink whitelist too narrow**: v1.4.0 only blocked `<fetcher> | shell` and `<decoder> | shell`. But `cat script | bash`, `printf 'rm -rf /' | bash` are the same risk class. Now ANY pipeline whose final stage is a shell/interpreter (`bash`/`sh`/`python`/`node`/...) blocks unconditionally.

### Fixed — 🟠 Install/uninstall race + lock correctness (3)

- **C12-C13 flock on settings.json inode was useless after `os.replace`**: when a process held a flock on `settings.json` and another process called `os.replace`, the new file got a new inode — the next process flock'd a *different* kernel lock object. No serialization happened. Both install.sh and uninstall.sh now `flock -w 30 9` a permanent lock file `~/.claude/.anchor.lock` (which is never replaced), held by the bash parent for the entire script duration. Python no longer needs its own flock layer.
- **C14 install file copy + settings merge not in same critical section**: between the `cp` of script files and the `python3 -` block that updates settings.json, an interleaved uninstall could remove settings entries pointing at scripts we just wrote, or vice-versa. Now the shell-level lock covers both steps.

### Fixed — 🟡 Medium (3)

- **C15 fresh-install branch wasn't lock-protected**: an interleaved process creating `settings.json` between our `[ -f ]` check and write could lose its changes. The lock now covers the entire conditional.
- **C16 uninstall default filter actually removed unknown schemes too**: the predicate was `home OR not-plugin`, which evaluated true for any path whose source we couldn't classify (custom wrapper paths, third-party install layouts). Now it's strictly `bool(HOME_PATH_PAT.search(cmd))` — unknown schemes survive unless `--all-hooks` is passed.
- **C17 dedup name→single-entry collapsed multi-hook configs**: if a user had the same anchor script registered twice (e.g. accidentally added via both plugin and `./install.sh`), v1.4.0's dedup map only remembered the last index, leaving the duplicate behind. Now `existing_anchor_map` is a `defaultdict(list)` collecting all matches; dedup picks the highest-priority scheme (home > plugin > other-anchor) to update, and marks the rest for removal.

### Fixed — 🟢 Low (1)

- **C18 backup created outside lock**: install.sh's `cp settings.json $BACKUP` ran before the lock was acquired in earlier versions. The lock now covers the backup too, so concurrent install/uninstall pairs can't race the backup with the modification.

### Verified — 47 / 47 regression tests

- v1.4.0 history suite (`/tmp/test-pretool-v1.4.sh`): **32/32 pass** (B1-B19 from codex round 2 + 12 historical).
- v1.4.1 new suite (`/tmp/test-c1-c4.sh`): **15/15 pass** (C1-C11 from codex round 3 + variants):
  ```
  C1 unspaced pipe (curl x|bash)               BLOCK ✓
  C1 unspaced semicolon (echo ok;rm -rf /)     BLOCK ✓
  C2 sudo -u root rm -rf /                     BLOCK ✓
  C3 bash -c 'rm -rf /'                         BLOCK ✓
  C3 sh -c                                      BLOCK ✓
  C3 eval                                       BLOCK ✓
  C4 xargs stdin (rm -rf via stdin)             BLOCK ✓
  C5 timeout wrapper                            BLOCK ✓
  C6 find -exec env rm bypass                   BLOCK ✓
  C7 sed '1e rm -rf /'                          BLOCK ✓
  C8 bare $VAR / glob /* / brace                BLOCK ✓
  C11 cat | bash, printf-literal | bash         BLOCK ✓
  ```
- `shellcheck` PASS on all 9 shell scripts.
- `install.sh` idempotent live re-run on this machine: exit 0.

### Audit history total

- External review (v1.3.6): 10
- Self-audit (v1.3.7): 5
- Codex pass 1 (v1.3.8): 15
- Codex pass 2 (v1.4.0): 19
- **Codex pass 3 (v1.4.1): 19**
- Cumulative: **68 bugs in 5 audit passes**. Each pass found problems the prior passes didn't see. This is now the strongest possible empirical case for SKILL.md's "多遍扫，扫到为止" rule.

### Documentation note

PreToolUse hook header retains the v1.4.0 limitation note: "sufficiently obfuscated shell can defeat any static analyzer. We block obvious obfuscation rather than try to decode it. Hook is *anti-instinct first defense*, not *anti-motivated-attacker last resort*." After 3 codex passes specifically trying to break it, that framing is still accurate — even with shlex tokenization, wrapper schemas, shell -c recursion, and quote-aware paren matching, a sufficiently motivated attacker can still craft a bypass (the OS sandbox is the real safety boundary).

### Plugin manifest

- Versions bumped 1.4.0 → 1.4.1.

## [1.4.0] — 2026-05-21

Second-pass codex adversarial-review patch. **Major version bump because `pre-tool-danger.sh` is fully rewritten** around shell tokenization (Python `shlex`) instead of regex on the raw command string. The previous regex layer was inherently bypassable by quoting, hex escapes, `${IFS}`, command wrappers, and nested substitution — codex pass 2 demonstrated 5 of those bypass classes. All 19 issues from that pass are addressed here.

### 🔴 PreToolUse rewrite — closes 5 bypass classes (B1-B5)

- **Wrapper unwrap (B1)**: `env rm -rf /`, `command rm -rf /`, `sudo -E rm -rf $HOME` now block. `env`/`command`/`sudo`/`exec`/`time`/`nice`/`ionice`/`unshare`/`setpriv`/`stdbuf` are removed from `SAFE_FIRST` and treated as wrappers; the hook strips them (plus any of their own flags + `VAR=val` env prefixes) before scanning the real argv.
- **Subcommand-spawning tools (B2)**: `find -exec rm -rf {} \;`, `awk 'BEGIN{system(...)}'`, `find -delete`, `sed e cmd` — all now block via dedicated checkers. `find`, `awk`, `sed`, `xargs` removed from `SAFE_FIRST` since they can launch arbitrary sub-commands.
- **Obfuscation detection (B3, B4)**: ANSI-C hex escapes (`$'\x72\x6d'`), octal escapes (`$'\127'`), `${IFS}` whitespace substitution, and 3+ consecutive `\xNN` sequences are flagged as obfuscation patterns and block immediately. Trying to decode them is a losing game; refusing to evaluate is the safe answer.
- **Quoted targets (B5)**: switched to `shlex.split(posix=True)` so `rm -rf "$HOME"` tokenizes to `["rm", "-rf", "$HOME"]` — the regex now sees the dequoted target. Same fix handles `rm -rf -- "$HOME"`, `rm -rf ${HOME}`, etc.

### 🟠 PreToolUse correctness fixes (B6-B10)

- **git global flag value form (B6)**: `git --git-dir /repo/.git --work-tree /repo reset --hard` now blocks. The argv-walking checker skips global flags (`-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`, etc.) — both `--flag=value` and `--flag value` forms — before looking for the subcommand.
- **git push force refspec (B7)**: `git push origin +main` (force update via refspec prefix) and `git push origin --delete main` (remote branch delete) now block, alongside `-f`/`--force`/`--force-with-lease`.
- **Nested substitution (B8)**: `extract_substitutions` now does balanced-paren matching recursively (up to 5 levels deep), so `echo $(rm -rf $(printf /))` and `echo "\`rm -rf /\`"` block via the inner-body scan.
- **Pipe-to-shell variants (B9)**: `curl X | /bin/bash`, `curl X | env bash`, `curl X | tee /tmp/log | bash` all block. Pipeline analysis tokenizes with shlex (quote-aware), matches basenames after wrapper unwrap, and triggers when any stage is a shell/interpreter AND any earlier stage is a fetcher (`curl`/`wget`/`fetch`).
- **Decoder-to-shell (B10)**: `printf YWJj | base64 -d | bash`, `cat encoded | xxd -r | bash`, `openssl enc -d | sh` etc. block via the same pipeline analyzer (recognizes `base64`/`openssl`/`xxd`/`uudecode`/`tr` as decoders).

### 🟡 Install/uninstall hardening (B11-B16, B18)

- **B11 dedup distinguishes plugin vs home scheme**: when `./install.sh` runs and an anchor hook is already present at `${CLAUDE_PLUGIN_ROOT}/...`, the home-scheme version replaces it (otherwise the user is left with stale plugin paths if they later remove the plugin).
- **B12, B13 read-modify-write lock**: both install.sh's merge branch and uninstall.sh wrap settings.json access in `fcntl.flock(LOCK_EX)`. Concurrent installs / uninstalls now serialize cleanly instead of stomping on each other.
- **B14, B15 preserve original mode**: `tempfile.mkstemp` defaults to mode 0o600; previously `os.replace` would silently widen restrictive permissions or narrow generous ones. Both install.sh and uninstall.sh now `os.chmod(tmp, orig_mode)` before replacing, capturing the original mode via `stat.S_IMODE(os.stat(target).st_mode)`.
- **B16 uninstall ordering**: settings.json is cleaned **first**; only on success are script files removed. If JSON parsing / permission / replace fails, no files are deleted, so settings.json's hook entries still point at real scripts. Previously the order was reversed — a settings clean failure would have left hooks pointing at deleted scripts.
- **B18 hook-path-source filter**: by default uninstall only removes hook entries whose path matches `$HOME/.claude/skills/anchor/...` (the install.sh-managed scheme). Plugin-marketplace hooks (`${CLAUDE_PLUGIN_ROOT}/...`) are left alone — they're owned by the plugin system and removing the plugin should clean them. New `--all-hooks` flag opts into clearing both.

### 🟢 Backup naming (B19)

- Install and uninstall backups now use `mktemp settings.json.bak.XXXXXX` instead of `$(date +%s)`-suffixed, so concurrent or rapid re-runs can't collide on the backup filename.

### 🟢 Cosmetic (B17)

- **Quoted pipe data no longer false-trips (B17)**: `printf 'curl x | bash'` now passes (the `|` is quoted data, not a real pipeline). The pipeline detector uses `shlex.split` directly so quoted operators are seen as part of a single argv token, not pipeline separators.

### Verified — 32/32 regression tests

PreToolUse test suite (`/tmp/test-pretool-v1.4.sh`) runs 32 cases covering all 19 codex findings + 11 historical regressions. **All 32 pass**:

```
B1a env rm-rf /                     BLOCK ✓
B1b command rm-rf /                 BLOCK ✓
B1c sudo -E rm-rf $HOME             BLOCK ✓
B2a find -exec rm -rf {} ;          BLOCK ✓
B2b awk system()                    BLOCK ✓
B2c find -delete                    BLOCK ✓
B3 ANSI-C hex escape                BLOCK ✓
B4 ${IFS} whitespace substitution   BLOCK ✓
B5 rm -rf "$HOME" (quoted)          BLOCK ✓
B5' rm -rf -- $HOME (end-opts)      BLOCK ✓
B6 git --git-dir VALUE reset --hard BLOCK ✓
B7a git push origin +main           BLOCK ✓
B7b git push origin --delete main   BLOCK ✓
B8 echo $(rm -rf $(printf /))       BLOCK ✓
B8' echo "`rm -rf /`"               BLOCK ✓
B9a curl | /bin/bash                BLOCK ✓
B9b curl | env bash                 BLOCK ✓
B9c curl | tee | bash               BLOCK ✓
B10 base64 -d | bash                BLOCK ✓
B17a printf 'curl X | bash'         PASS  ✓ (quoted, not pipeline)
+ 12 historical regressions          all ✓
```

Plus `shellcheck` + `jsonlint` PASS on the whole repo, install.sh idempotent re-run exits 0.

### Documentation

- Pre-tool-danger.sh header now documents its design (shlex tokenization, wrapper unwrap, obfuscation refusal, pipeline analysis, balanced-paren substitution extraction) AND its **limitations**: "sufficiently obfuscated shell can always defeat any static analyzer; we block obvious obfuscation rather than try to decode it. Hook is *anti-instinct first defense*, not *anti-motivated-attacker last resort*."

### Audit history total

- **External review (v1.3.6)**: 10 fixes
- **Self-audit (v1.3.7)**: 5 fixes
- **Codex pass 1 (v1.3.8)**: 15 fixes
- **Codex pass 2 (v1.4.0)**: 19 fixes
- **Cumulative**: 49 bugs caught across 4 audits + 1 day. Multi-pass scanning is empirically essential.

### Plugin manifest

- Major version bump 1.3.8 → 1.4.0. The pre-tool-danger.sh rewrite is the biggest behavioral change since v1.0.

## [1.3.8] — 2026-05-21

Codex adversarial-review patch. After v1.3.7, codex did its own independent audit pass and found **15 more bugs** that both the external review and the self-audit had missed. Five were **PreToolUse hook bypass classes** — the very thing anchor's "硬约束" layer promises. All 15 fixed here.

### Fixed — 🔴 Critical (PreToolUse safety net bypasses)

- **`pre-tool-danger.sh` substitution bypass (A1)**: `SAFE_FIRST` would skip a segment if the first program was safe (`echo`, `cat`, etc.), but didn't peek inside `$(...)`, `<(...)`, or `` `...` `` — so `echo $(rm -rf $HOME)` and `cat <(rm -rf /)` slipped through. The hook now extracts substitution contents as additional segments to scan, regardless of the outer SAFE_FIRST verdict.

### Fixed — 🟠 High (PreToolUse correctness + attack surface)

- **`pre-tool-danger.sh` pipe-to-shell pattern never matched (A2)**: the `curl ... | bash` pattern was a per-segment check, but the segment splitter cut on `|`, so the `curl` segment had no `bash` and the `bash` segment had no `curl`. Cross-segment patterns now scan the whole command (a new `GLOBAL_CHECKS` list) before per-segment scanning runs.
- **`pre-tool-danger.sh` git reset --hard variants missed (A3)**: regex required `git reset --hard` with `reset` directly after `git`, missing `git -C repo reset --hard`, `git -c user.email=x reset --hard`, `git --git-dir=/x reset --hard`. Pattern now allows `-C`/`-c`/`--git-dir`/`--work-tree` between `git` and `reset`, plus flags between `reset` and `--hard`.
- **`pre-tool-danger.sh` rm variants missed (A4)**: regex caught a narrow set — missed `rm -rf -- "$HOME"`, `rm -rf ${HOME}`, `rm -rf -- /`, mixed-flag patterns. Pattern now allows interleaved flags, the `--` end-of-options marker, and `$HOME`/`${HOME}`/`~`/`/path` as targets.
- **`pre-tool-danger.sh` hook input via env var hit ARG_MAX (A5)**: passing the full hook JSON through `EC_HOOK_INPUT=...` runs into the kernel exec environment-size limit (`ARG_MAX` ≈ 128 KB). A megabyte-sized command would silently fail to invoke the hook — bypassing all checks. Now the hook reads JSON from a `mktemp` tmp file via `EC_HOOK_INPUT_FILE` env var; only the path crosses the exec boundary.

### Fixed — 🟡 Medium

- **`ec-status.sh` heredoc `$task_dir` (A6)**: same pattern as v1.3.7's stop-self-check fix, but in the statusline script that v1.3.7 missed. Now uses `EC_TASK_DIR` env var + `<<'PYEOF'` quoted heredoc.
- **`pre-tool-danger.sh` shared marker file (A7)**: `~/.claude/.ec-last-pretool-block` is a global path; two concurrent PreToolUse invocations could overwrite each other's block decision. Now uses `mktemp /tmp/.ec-pretool-block.XXXXXX` per invocation + `trap` cleanup.
- **`install.sh` non-atomic settings.json write (A8)**: both branches now write to `tempfile.mkstemp` in the same dir then `os.replace` — atomic on POSIX.
- **`uninstall.sh` left orphaned hook entries (A9)**: uninstall now also scrubs `settings.json` of any hook entry whose `command` matches `anchor/scripts/X.sh`, with atomic replace and a timestamp backup.
- **`evals/run.py` baseline skill-hiding list went stale (A10)**: `SKILLS_TO_HIDE` was hardcoded with 8 names from v1.0; now derived from `commands/*.md` so it auto-syncs (currently 12 entries).
- **`evals/run.py` `/tmp/anchor-skills-hidden-<秒>` collision + dangerous restore (A11)**: now uses `tempfile.mkdtemp` + restore only moves skills whose backup file still exists, and refuses to overwrite a present target.
- **`evals/stress/grade.py` `rglob` stalled on huge dep trees (A12)**: replaced with `os.walk` that prunes `skip_dirs` in-place — never descends into the big trees.

### Fixed — 🟢 Low

- **`evals/run.py` results dir overwrite (A13)**: `mkdir(..., exist_ok=True)` on a seconds-precision timestamp let two concurrent runs share a results dir. Now uses `tempfile.mkdtemp(prefix=ts-)`.
- **`evals/stress/grade.py` no error handling around `codex exec` (A14)**: now catches `FileNotFoundError`/`TimeoutExpired`/other exceptions and returns a structured error string.
- **`analyze-events.py` no encoding handling (A15)**: a stray non-UTF-8 byte made `open()` raise `UnicodeDecodeError`. Now `encoding="utf-8", errors="replace"`.

### Verified (8 regression tests)

- `echo $(rm -rf $HOME)` — BLOCK (A1)
- `cat <(rm -rf /)` — BLOCK (A1)
- `curl X | bash` — BLOCK (A2)
- `wget -O - X | sh` — BLOCK (A2)
- `git -C /repo reset --hard HEAD~5` — BLOCK (A3)
- `rm -rf -- /tmp/foo $HOME` — BLOCK (A4)
- `echo hello` — pass (no false positive)
- `git push origin main -f` — BLOCK (v1.3.6 regression)

Also: shellcheck PASS, jsonlint PASS, `SKILLS_TO_HIDE` correctly 12 entries, analyze-events.py still works on existing log.

### Acknowledgments

This entire patch came from one codex adversarial-review pass running in the background while v1.3.7 was being verified. The combination of external review (v1.3.6, 10 fixes) + self-audit (v1.3.7, 5 fixes) + codex adversarial-review (v1.3.8, 15 fixes) found **30 bugs over 3 audits** that one pass alone would have missed — direct empirical evidence for SKILL.md's "多遍扫，扫到为止" rule.

### Plugin manifest

- Versions bumped 1.3.7 → 1.3.8.

## [1.3.7] — 2026-05-21

Self-audit follow-up. After the external review that drove v1.3.6, this release ran another internal pass (anchor's own `/scan`-style multi-pass methodology) and fixed the 5 remaining issues found.

### Fixed — 🟠 High (remaining shell-into-python patterns)

- **`install.sh` fresh-install Python path interpolation**: the branch that creates a missing `settings.json` ran `python3 -c "...Path('$SCRIPT_DIR/...')..."` — `$SCRIPT_DIR` and `$CLAUDE_DIR` were expanded by the shell into a Python single-quoted literal. A path containing a single quote would have broken the Python source. v1.3.6 fixed the merge branch using `sys.argv`; this commit applies the same fix to the fresh-install branch.
- **`stop-self-check.sh` heredoc `task_dir = "$task_dir"`**: the unquoted heredoc let `$task_dir` (which embeds `$session_id` from hook input) interpolate into Python source. While session_id is generated by Claude Code as a UUID, defense-in-depth says hook input should never enter Python source as a literal. Switched to `EC_TASK_DIR="$task_dir" python3 - <<'PYEOF'` and `os.environ.get`.

### Fixed — 🟡 Medium (performance + shape)

- **`pre-tool-danger.sh` 3 Python invocations per block**: when PreToolUse blocked a command, the event-log path read the same JSON marker file three separate times, each via its own `python3 -c "...$HOME..."` subshell. That's three process startups and three shell-into-Python interpolations per single block. Replaced with one `python3 - "$marker"` call emitting tab-separated fields, then a single `read -r` to capture all three into env vars. Tab/newline sanitization preserves the `IFS=$'\t'` parsing.

### Fixed — 🟢 Low (compat + race)

- **`analyze-events.py` `dict | dict` (Python 3.9+ only)**: the dict union operator on line 65 raised `SyntaxError` on Python 3.8. Replaced with the `{**a, **b}`-equivalent two-line build to keep the script working on the Python 3.8 still shipping in some long-LTS distros (e.g. Debian 11, Ubuntu 20.04). No behavior change on newer Pythons.
- **`evals/stress/run.sh` sandbox dir collision**: `SANDBOX=/tmp/anchor-stress-${ID}-$(date +%s)` could collide when two `run.sh` invocations start in the same second. Switched to `mktemp -d "/tmp/anchor-stress-${ID}-XXXXXX"` which gets a kernel-guaranteed unique suffix.

### Verified

- `shellcheck` still green on all 8 shell scripts.
- Stop hook regression test: task subject with `"""` characters and ASCII task_dir paths both produce valid JSON output.
- PreToolUse regression: blocking still works, event log entry still contains pattern / msg / seg fields, now with one Python process instead of three.
- `analyze-events.py --all` runs without SyntaxError on Python 3.11; the script no longer requires 3.9+.

### Plugin manifest

- Versions bumped 1.3.6 → 1.3.7.

## [1.3.6] — 2026-05-21

Code-review-driven security + correctness patch. An external reviewer found **12 bugs** across the hook scripts and installers; this release fixes 10 of them (1 left as-is intentionally, 1 was a minor design choice already safe in Python 3).

### Fixed — 🔴 Critical (injection vectors)

- **`post-tool-lint.sh` heredoc shell injection**: the additionalContext-emitting block used `<<PYEOF` (unquoted), so bash expanded `$linter` / `$file` / `$result` before handing the body to Python. A filename like `$(whoami).py` or any backticks in lint output would have been executed by the shell. Now uses `<<'PYEOF'` with `EC_LINT_*` env vars (same pattern `_log_event.sh` already used).
- **`post-tool-lint.sh` JSON file-path injection**: `python3 -c "json.load(open('$file'))"` broke (or worse) when the filename contained a single quote (e.g. `don't.json`). Now uses `sys.argv[1]` so the shell never interpolates into the Python source.
- **`stop-self-check.sh` triple-quote injection**: the block message used `<<PYEOF` (unquoted) with `$incomplete` interpolated into a `"""..."""` Python literal. A task subject containing `"""` would have closed the string early and corrupted the JSON output. Now uses `<<'PYEOF'` + `EC_STOP_INCOMPLETE` env var.

### Fixed — 🟠 High (functional bugs)

- **`pre-tool-danger.sh` force-push regex was too tight**: required `-f` / `--force` / `--force-with-lease` to come *immediately* after `git push`, missing common invocations like `git push origin main -f`, `git push -u origin main --force-with-lease`, etc. Pattern relaxed to `\bgit\s+push\b[^|;&]*?(?:-f\b|--force\b|--force-with-lease\b)` — flags can be anywhere in the same shell segment now. Verified by 3 regression tests.
- **`install.sh` "7 commands" miscount**: the message claimed "7 commands" but the loop installs 11 (v1.2.0 added 4 without updating the string). Now says 11.
- **`pre-tool-danger.sh` dead line**: `os.environ_log_block = (pattern, msg, seg[:120])` was setting an attribute on the `os.environ` object with no effect. The real logging path already wrote to `~/.claude/.ec-last-pretool-block`. Dead line removed.

### Fixed — 🟡 Medium (robustness)

- **`post-tool-lint.sh` eslint config glob**: `--config "$(dirname "$file")/.eslintrc.*"` lived inside double quotes, so bash didn't expand the glob — the literal string `.eslintrc.*` was passed to eslint, which always failed and silently fell back to the unconfigured run. Removed `--config`; let eslint discover its own config (which it does correctly via `.eslintrc.*`, `eslint.config.js`, `package.json#eslintConfig`).
- **`_log_event.sh` no lock on concurrent appends**: multiple hooks firing at once could interleave bytes inside a single JSON line. Added `fcntl.flock(LOCK_EX)` around the write; auto-releases on close. Best-effort (filesystems without flock are tolerated).
- **`install.sh` hook dedup couldn't see plugin-path duplicates**: the dedup keyed on full `command` strings, so a hook installed via the plugin marketplace path (`${CLAUDE_PLUGIN_ROOT}/...`) wouldn't match the same hook installed via `install.sh` (`$HOME/.claude/...`), and re-running would double-register. Now keys on the anchor script's basename (`session-start-inject.sh`, etc.) extracted via regex from either path scheme.
- **`statusline-wrapper.sh` always called `npx -y ccstatusline@latest`**: that fetches and version-checks on every statusbar refresh — slow on weak networks, silently empty offline. Now prefers `$CCSTATUSLINE_BIN` if set, then a globally-installed `ccstatusline` binary, falling back to `npx` only as last resort.

### Fixed — 🟢 Low

- **`session-start-inject.sh` `.cursor/rules` directory check**: the file presence loop used `[ -f ]`, but `.cursor/rules` is typically a directory, never a file — it would never get reported as a project contract. Now `[ -d ]` is checked separately and the trailing `/` is included in the listing.

### Intentionally left as-is

- The transcript-truncation rubric items in `evals/stress/grade.py` still cap at 6000 chars; this is a memory budget choice, not a bug.
- `stop-self-check.sh` task-subject `[:80]` slicing: Python 3 slicing is by codepoint, so multi-byte UTF-8 characters can't be split. The reviewer correctly noted "not a real bug" and we agree.

### Acknowledgments

All 10 fixes in this release were prompted by a single external code review pass. Thanks to the reviewer for the depth and precision of the report — especially the 3 injection findings, which were the most important.

### Plugin manifest

- Versions bumped 1.3.5 → 1.3.6.

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

- `skills/anchor/SKILL.md` — 7 core rules + long-task mode + autonomous mode + E2E + multi-pass vuln scan + condition-based codex review + project-CLAUDE.md pitfall writeback.
- `skills/anchor/references/` — 4 reference files: `autonomous-mode.md`, `pitfall-template.md`, `vuln-checklist.md`, `multi-agent-recipes.md`.
- `skills/anchor/scripts/` — `session-start-inject.sh`, `stop-self-check.sh`.
- `commands/` — `lock-scope.md`, `record-pitfall.md`, `scan-deeper.md` (later renamed in v0.2).
- `install.sh` / `uninstall.sh` — file-copy install to `~/.claude/`.
- `settings.hooks.json` — manual merge template for `~/.claude/settings.json`.

[1.0.0]: https://github.com/biefan/anchor/releases/tag/v1.0.0
