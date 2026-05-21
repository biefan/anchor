---
description: Workspace 完整 snapshot — task list + branch + modified files + active-task + open questions。比 /save 更全面，适合长任务中段或大节点保护。
argument-hint: "<label>"
---

# /snapshot — full workspace state snapshot

比 `/save` 更全面 — 不只是 task list，还含 **branch / modified files / active-task.md / 开放问题 / 决策栈 / cost so far**。

### Steps

1. **`$ARGUMENTS` 必填** = label.

2. **创建 snapshot dir**：
   ```bash
   mkdir -p ~/.anchor/memory/snapshots/<project-slug>
   SNAP_DIR=~/.anchor/memory/snapshots/<project-slug>/<label>-<YYYY-MM-DDTHHMM>
   mkdir -p "$SNAP_DIR"
   ```

3. **抓 workspace state**（并行跑 4 件事）：
   - **Task list**: 用 `TaskList` tool dump 当前 session tasks → `$SNAP_DIR/tasks.md`
   - **Git state**: 
     ```bash
     git -C "$PWD" status --short > $SNAP_DIR/git-status.txt
     git -C "$PWD" diff --stat > $SNAP_DIR/git-diff-stat.txt
     git -C "$PWD" branch --show-current > $SNAP_DIR/git-branch.txt
     git -C "$PWD" log --oneline -20 > $SNAP_DIR/git-log.txt
     ```
   - **Active-task**: `cp ~/.anchor/active-task.md $SNAP_DIR/active-task.md` (if exists)
   - **Modified files content** (top 20 changed):
     ```bash
     git -C "$PWD" diff --name-only HEAD | head -20 | while read f; do
       cp --parents "$f" $SNAP_DIR/files/ 2>/dev/null
     done
     ```

4. **写 `$SNAP_DIR/manifest.md`** 主 metadata：
   ```markdown
   # Snapshot — <label>
   
   - Created: 2026-05-22T14:32
   - Project: <slug>
   - Working dir: <cwd>
   - Session: <session_id>
   
   ## Locked task (from active-task.md)
   "<user's original /lock phrasing>"
   
   ## Task state
   - X completed / Y pending / Z in_progress
   - Last milestone: <name>
   
   ## Git
   - Branch: <branch>
   - Modified: X files (see git-status.txt)
   - Recent commits: see git-log.txt
   
   ## Open questions
   - <from active-task>
   
   ## Restore instructions
   - `/resume-snapshot <label>` 把 task list 重新加载到新 session
   - 文件 diff 在 `files/` 子目录，git apply 可以重 stage
   - branch 切换：`git checkout <recorded-branch>`
   ```

5. **报告**：snapshot 路径 + 大小 + 含哪些组件。

### 和 `/save` 的区别

| 维度 | `/save` (v1.6.0) | `/snapshot` (v1.8.0+) |
|---|---|---|
| Task list | ✓ | ✓ |
| Git state | ✗ | ✓ branch/log/diff-stat |
| Modified file contents | ✗ | ✓ (top 20) |
| Active-task.md | ✗ | ✓ |
| 存储位置 | `~/.anchor/saved-tasks/` | `~/.anchor/memory/snapshots/<project>/` |
| 适用场景 | 短-中任务 cross-session | 长任务大节点 / 实验前安全点 |

### 典型用法

```
# 大改动前
/snapshot before-redis-migration

# 实验性 approach
/snapshot try-approach-a
# (跑了一阵发现不行)
# 回到 approach-a 的起点：
# /resume-snapshot before-redis-migration  (TODO: 这个 cmd 在 v1.8.0 也加)
git checkout <branch from manifest>

# 月底 sprint 收尾
/snapshot sprint-2026-q2-w3-end
```

### 不做

- **不**自动 git stash / commit — user 责任管 git
- **不**包含 ~/.env / 任何 dotfile（隐私）
- **不**自动清理旧 snapshots — disk usage 是 user 责任
