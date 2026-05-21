---
description: 跨项目 + 跨类型 grep 长期记忆 — pitfalls / decisions / facts / preferences / snapshots / saved-tasks 全搜。Use to find anything Claude remembered before.
argument-hint: "<keyword or phrase>"
---

# /recall — search long-term memory across projects and categories

跨项目 + 跨类型搜索 anchor 长期记忆。v1.8.0 起搜索范围扩展到全部：

- `~/.anchor/memory/pitfalls/` (来自 `/pit`)
- `~/.anchor/memory/decisions/` (来自 `/decide` 或 `/remember decision`)
- `~/.anchor/memory/facts/` (来自 `/remember fact`)
- `~/.anchor/memory/preferences.md` (来自 `/remember pref`)
- `~/.anchor/memory/todos.md` (来自 `/remember todo`)
- `~/.anchor/memory/snapshots/` (来自 `/snapshot`)
- `~/.anchor/saved-tasks/` (来自 `/save`)
- `~/.anchor/active-task.md` (当前长任务状态)

### Steps

1. **`$ARGUMENTS` 必填** — keyword / phrase. 如果空，列每个 category 的最近 3 条让用户挑。

2. **搜索全部 memory dirs**：
   ```bash
   ROOTS=(
       ~/.anchor/memory/pitfalls
       ~/.anchor/memory/decisions
       ~/.anchor/memory/facts
       ~/.anchor/memory/snapshots
       ~/.anchor/saved-tasks
   )
   grep -lri "$ARGUMENTS" "${ROOTS[@]}" 2>/dev/null
   grep -li "$ARGUMENTS" ~/.anchor/memory/preferences.md ~/.anchor/memory/todos.md ~/.anchor/active-task.md 2>/dev/null
   ```
   - 大小写不敏感
   - 按文件最近修改时间倒序

3. **按类型分组显示**：
   ```
   找到 N 条匹配 "<keyword>"：
   
   ## 📌 Pitfalls (2)
   ### 1. <title> (project-X, 2026-04-15)
   - 现象/根因/教训摘要 (3 行)
   
   ## 🏛  Decisions (1)
   ### 1. <title> (project-Y, 2026-03-01, status: accepted)
   - context/decision 摘要
   
   ## 📋 Facts (1)
   ### 1. <title>
   - content (1-2 行)
   
   ## ⚙️ Preferences (matched)
   - <匹配的 preference line>
   
   ## ✅ TODOs (matched)
   - <匹配的 todo line>
   
   ## 📸 Snapshots (1)
   ### 1. <label> (2026-05-20)
   - manifest 摘要
   
   ## 💾 Saved tasks (0)
   (none)
   ```
   
   每条 3-5 行（不 dump 全文）。

4. **如果 0 个匹配**：明说 "没找到 — 可能是新东西，修完用 `/pit` / `/decide` / `/remember` 写回 (long-term memory)"。

5. **如果 > 20 个**：显示按类型分组的 top + 提示 "用更具体关键字 或 `--category=X` 限定（pitfalls/decisions/...）"。

### 各 memory category 怎么 populate

| Category | 写入命令 | 文件位置 |
|---|---|---|
| Pitfall | `/pit` 自动 sync | `~/.anchor/memory/pitfalls/<project>/` |
| Decision | `/decide` | `~/.anchor/memory/decisions/<project>/` |
| Fact | `/remember fact ...` | `~/.anchor/memory/facts/<project>/` |
| Preference | `/remember pref ...` | `~/.anchor/memory/preferences.md` (single file) |
| TODO | `/remember todo ...` | `~/.anchor/memory/todos.md` (single file) |
| Snapshot | `/snapshot <label>` | `~/.anchor/memory/snapshots/<project>/` |
| Saved task | `/save <label>` | `~/.anchor/saved-tasks/<label>.md` |

### 典型用法

```
# 遇到 Redis 行为不符预期
/recall redis cluster
# → 找到 6 个月前 pitfall "Redis pipeline 在 cluster 模式下不跨 slot"
#   AND 找到 3 个月前 decision "用 Redis Streams 替代 RabbitMQ" 含 cluster 选型 context

/recall pnpm
# → 找到 preference "我用 pnpm，永远不要建议 npm"
# → 找到 fact "monorepo workspaces 在 pnpm 8+"

/recall "tests pass but"
# → 跨项目找过去 mocked test 通过但生产挂的案例
```

### Filter (optional)

- `/recall --category=pitfalls redis` — 只搜 pitfalls
- `/recall --project=acme redis` — 只搜 acme 项目的记忆
- `/recall --since=2026-04 redis` — 限近期

### 不做

- **不**外发 memory 数据（pure local file system grep）
- **不**修改 memory 文件（read-only operation）
- **不**自动 categorize / tag — keyword grep + category 标识就够
