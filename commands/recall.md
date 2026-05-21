---
description: 跨项目 grep 历史踩坑记录 — 找类似 bug / similar pitfalls. Reads from ~/.anchor/pitfalls/ (auto-populated by /pit).
argument-hint: "<keyword or phrase>"
---

# /recall — search past pitfalls across all projects

跨项目搜索历史踩坑。每次 `/pit` 写入项目 `CLAUDE.md` 时同步到 `~/.anchor/pitfalls/`，所以 `/recall` 能 grep 所有项目的累积经验。

### Steps

1. **`$ARGUMENTS` 必填** — keyword / phrase. 如果空，列最近 10 个 pitfalls 让用户挑。

2. **搜索 `~/.anchor/pitfalls/`**：
   ```bash
   # Each .md is one pitfall, named by date+project
   grep -lri "$ARGUMENTS" ~/.anchor/pitfalls/ 2>/dev/null | head -10
   ```
   - 关键字搜 title + 现象 + 根因 + 修复 + 教训
   - 大小写不敏感
   - 按文件最近修改时间倒序

3. **显示匹配结果**：
   ```
   找到 N 条匹配 "<keyword>"：
   
   ### 1. <pitfall title> (project-X, 2026-04-15)
   - **现象**：...
   - **根因**：...
   - **教训**：...
   ---
   
   ### 2. ...
   ```
   
   每条 3-5 行（不要 dump 全文）。

4. **如果 0 个匹配**：明说"没找到，可能是新型 bug，修完用 `/pit` 写回"。

5. **如果 > 10 个**：显示前 10 + 提示 "用更具体关键字"。

### 关于 ~/.anchor/pitfalls/ 是怎么 populate 的

- `/pit` 命令在写项目 `CLAUDE.md` 同时，cp 一份到 `~/.anchor/pitfalls/<project-slug>/<YYYY-MM-DD>-<short-slug>.md`
- 项目 slug 从 cwd basename 取
- 每条 pitfall 一个独立 file 方便 grep
- 含 metadata：原 file path / git remote / commit hash

### 典型用法

```
# 遇到 Redis 行为不符预期
/recall redis cluster
# → 找到 6 个月前 "Redis pipeline 在 cluster 模式下不跨 slot" — 同问题

/recall race condition
# → 跨项目找过去并发问题

/recall "tests pass but"
# → 找过去 mocked test 通过但生产挂的案例
```

### 不做

- **不**外发 pitfalls 数据（pure local file system grep）
- **不**修改 pitfalls 文件（read-only operation）
- **不**自动 categorize / tag — keyword grep 就够
