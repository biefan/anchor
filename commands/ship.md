---
description: 一条龙发车 —— done check + Conventional Commit + gh PR create。Use to ship a finished change as a PR in one command (assumes /done has passed or you're confident).
argument-hint: "[base branch, default main]"
---

按这个流程发车，每步成功才走下一步：

### 1. 先跑 `/done` 流程（如果还没跑）

如果用户最近**没**跑过 `/done`，**先调用 `/done`** 跑完所有 done-gates。如果 `/done` 没全过（lint 挂、未做 E2E、未回写 CLAUDE.md），停在这里报告 + 不发车。

如果用户在前 5 turn 内已经跑过 `/done` 且通过，可以跳过这步。

### 2. 决定 base branch

`$ARGUMENTS` 为空 → base = `main`。否则 base = `$ARGUMENTS`。

确认当前在一个**非 base**的 branch 上（不能从 main 直接 PR 到 main）：

```bash
current=$(git branch --show-current)
test "$current" != "<base>" || { echo "ERROR: 在 base branch 上，先切到 feature branch"; exit 1; }
```

没在 feature branch → 报告 + 停。

### 3. 拿 commit message subject（如果只有一个 commit）或者 用户原话生成

跑：
```bash
git log --oneline <base>..HEAD
```

- 如果只有 1 个 commit → PR title = 这个 commit subject
- 如果多个 → 用对话里的"任务原话"或者最新 commit subject 作为 PR title 起点
- 建议**强制 Conventional Commits 风格**：`feat:` / `fix:` / `docs:` / `refactor:` / `test:` / `ci:` / `chore:`

判断 prefix：
- 加新功能 → `feat:`
- 修 bug → `fix:`
- 只改文档 → `docs:`
- 重构无功能变化 → `refactor:`
- 加测试 → `test:`
- 改 CI / 构建 → `ci:` / `build:`

### 4. 生成 PR body

模板：

```markdown
## Summary

<1-3 bullets：这个 PR 改了什么 / 为什么>

## How tested

<本会话做过的 E2E 步骤；如果只跑了单测，明说>

## Risk / 二阶问题

<改动有没有这些隐患？(每项打勾或写 N/A)>
- [ ] Empty state 安全
- [ ] Retry 幂等
- [ ] Stale state 处理
- [ ] Rollback 路径

## Related

<linked issue/discussion 链接，或 N/A>
```

填的时候**只填本会话里你确定的信息**，没做的诚实写 N/A 或留空，不要编。

### 5. push branch + 创建 PR

```bash
# Ensure branch is pushed
git push -u origin "$current" 2>&1

# Create PR via gh CLI
gh pr create --base <base> --head "$current" \
  --title "<conventional commit title>" \
  --body-file /tmp/pr-body-$(date +%s).md
```

`--body-file` 用临时文件传 body，避免 PR body 里如果含敏感字面量被 PreToolUse hook 误拦。

PR 成功创建 → 拿到 URL，告诉用户：
```
✅ PR opened: <url>
   Title: <title>
   Base:  <base>
   Head:  <branch>
```

### 6. 不做的事

- ❌ 不自动 push 到 base（即使 base 不是 main）
- ❌ 不自动 merge（即使本 user 是 maintainer）
- ❌ 不开 auto-merge（让人类决定时机）
- ❌ 不在 PR description 里编造你没做过的测试

### 7. 用户 escape

如果用户在 `$ARGUMENTS` 里加 `--skip-done`，跳过第 1 步的 `/done` 自动调用（信任用户已经检查过）。但在 PR description 里加一行 "⚠️ `/done` was skipped at user request"。
