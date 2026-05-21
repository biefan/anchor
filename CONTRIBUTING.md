# Contributing to anchor

Thanks for considering a contribution. anchor is small and the workflow is intentionally lightweight.

## Quick orientation

If you haven't already, read [`CLAUDE.md`](CLAUDE.md) — it's the project contract for AI-assisted edits, but it also tells humans the file layout, where each kind of change goes, conventions, and known pitfalls.

The project is bilingual: [`README.md`](README.md) (中文) and [`README.en.md`](README.en.md) (English). PRs that change user-facing wording in one should update the other in the same PR.

## Dev loop

```bash
# Clone and install your local changes onto your own Claude Code / Codex CLI
git clone https://github.com/<your-fork>/anchor.git ~/anchor
cd ~/anchor
./install.sh
```

The `install.sh` is **idempotent** and re-running it is the standard "apply my edits" step:

1. Edit a file under `/root/anchor/` (or wherever you cloned).
2. Re-run `./install.sh`. It overwrites `~/.claude/skills/efficient-coding/`, `~/.claude/commands/`, and `~/.codex/skills/*` from the repo.
3. Re-invoke the affected skill (`/ec`) or trigger the affected hook in a fresh Claude Code session.

For the hook scripts specifically you can also smoke-test them in isolation:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"<your test cmd>"}}' \
  | bash skills/efficient-coding/scripts/pre-tool-danger.sh
```

## Where each kind of change lands

| Change | Edit here | Notes |
|---|---|---|
| Tweak a rule in the skill | `skills/efficient-coding/SKILL.md` | Cross-CLI: when you reference a Claude-Code-only tool name (`TaskCreate`, `AskUserQuestion`, `Agent`), include the Codex equivalent in parentheses. |
| Add a slash command | `commands/<name>.md` | YAML frontmatter `description:` + body. `install.sh` will install it as both a Claude Code command and a Codex skill. |
| Change a hook's logic | `skills/efficient-coding/scripts/<name>.sh` | Stdin = hook input JSON; stdout = `{"decision":"block","reason":...}` to block, or empty to allow. Keep `set -e`. Use a Python heredoc for anything non-trivial. **CI runs shellcheck on every `.sh`** — keep it clean. |
| Tweak install behavior | `install.sh` / `uninstall.sh` | Must remain idempotent. CI runs `./install.sh --no-hooks` and `./uninstall.sh` on a clean container. |
| Add a detailed reference (loaded on demand) | `skills/efficient-coding/references/<topic>.md` | Reference it from `SKILL.md`. |
| Add an eval scenario | `evals/evals.json` | Discriminators must be **behavioral** (`asks_at_least_one_clarifying_question`), not tool-specific (`uses_AskUserQuestion`). See `evals/results/20260521-071227-no-baseline/analysis.md` for why. |
| Project meta (LICENSE / CHANGELOG / README) | repo root | Bump version in both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` if you're releasing. |

## CI gate

Every PR runs three jobs ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)):

1. **shellcheck** — every `.sh` in the repo (excluding harmless SC1091 / SC2034).
2. **jsonlint** — every `*.json` outside `evals/results/`.
3. **install-smoke** — fresh Ubuntu runner: `./install.sh --no-hooks` → verifies files landed → verifies `--no-hooks` didn't mutate `settings.json` → `./uninstall.sh` → verifies cleanup.

Run them locally before pushing to catch issues early:

```bash
# shellcheck
find . -name '*.sh' -not -path '*/.git/*' \
  | xargs shellcheck --exclude=SC1091,SC2034

# jsonlint
find . -name '*.json' -not -path '*/.git/*' -not -path '*/evals/results/*' \
  -exec python3 -m json.tool {} \;
```

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) style. Imperative mood, ≤ 72 char first line, then a blank line and prose if needed.

```
feat: add /diff command for git diff risk analysis
fix(pre-tool-danger): segment shell separators before pattern check
docs: clarify autonomous mode escape hatch
ci: bump actions/checkout v4 -> v5
```

Group related work into a single commit when possible — the CHANGELOG groups by release, but it's nicer when reading `git log` if each commit is a coherent unit.

## Privacy: emails in commits

**Do not** use a non-noreply email in commit author or any tracked file. Use the GitHub privacy-mode email format `<github-id>+<username>@users.noreply.github.com`. This project leaked a real email once during initial setup — see [`CLAUDE.md`'s "Known pitfalls"](CLAUDE.md#known-pitfalls) for the post-mortem.

```bash
# Set this once per machine if you haven't already
git config --global user.email "<id>+<username>@users.noreply.github.com"
```

## Releasing

Maintainer task (you don't need to do this for a PR):

1. All CI green on `main`.
2. Bump `version` in `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` (semver).
3. Add `## [x.y.z] — YYYY-MM-DD` block at the top of `CHANGELOG.md`.
4. `git tag -a vX.Y.Z -m "release notes one-liner"` + `git push origin vX.Y.Z`.
5. `gh release create vX.Y.Z --notes-file <(python3 -c "import re; t=open('CHANGELOG.md').read(); print(re.search(r'^## \\[X\\.Y\\.Z\\][\\s\\S]*?(?=^## \\[|\\Z)', t, re.M).group(0))")`

## Reporting issues

Use [GitHub Issues](https://github.com/biefan/anchor/issues). Helpful info:

- Which CLI you're on (Claude Code or Codex CLI), version
- Which version of anchor (commit / tag)
- What you ran + expected vs got
- Whether `~/.claude/.efficient-coding-autonomous` was active when the issue happened

For hook bugs specifically, please include the **exact JSON input** the hook received (you can usually find it in the Claude Code transcript) — most hook bugs are about edge-case input shapes.

## Code of conduct

Be kind. This is a small project, the kind of feedback that helps is "here's a case where the rule misfired" and "here's what I'd expect instead." We don't have a heavy CoC document; act like the colleague you'd want to share an office with.

## License

By contributing you agree your contribution is MIT-licensed (the project's [LICENSE](LICENSE)).
