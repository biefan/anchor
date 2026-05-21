---
description: 通用长期记忆写入 — 把任何重要事项存到 ~/.anchor/memory/。Use to make Claude remember something across sessions and projects.
argument-hint: "<category: pref|decision|fact|todo> <content>"
---

# /remember — write to long-term memory

把任何**跨 session 应该记住**的事项写入 `~/.anchor/memory/`。

### Categories

| Category | 写入位置 | 例子 |
|---|---|---|
| **`pref`** (preference) | `~/.anchor/memory/preferences.md` | "我用 pnpm 不是 npm"、"代码注释默认中文"、"测试用 pytest 不是 unittest" |
| **`decision`** | `~/.anchor/memory/decisions/<project>/<date>-<topic>.md` | "用 Redis 缓存，理由：X / Y / Z" |
| **`fact`** | `~/.anchor/memory/facts/<project>/<date>-<topic>.md` | "production DB 在 us-east-1 / staging 在 us-west-2" |
| **`todo`** | `~/.anchor/memory/todos.md` | 跨 session 想做但还没排上的事 |

### Steps

1. **`$ARGUMENTS` 解析**：第一个词是 category，其余是 content。
   - 如果 category 不在 4 类里 → 提示并列出有效 categories
   - 如果 content 空 → 提示让用户补充

2. **写入位置**：
   - `pref` / `todo`：单 file append（顶部插入，按时间倒序）
   - `decision` / `fact`：每条独立 file，slug 化 title
   - Project-scoped 的（decision / fact）：用 `basename(pwd)` 作为 project-slug

3. **格式（per entry）**：
   ```markdown
   ### [一句话标题] (YYYY-MM-DD HH:MM)
   <content>
   
   - **Context**: <from chat history 或 cwd>
   - **Source**: <session ID 或 cwd>
   ```

4. **如果 category=`pref`**，**额外**通知 SessionStart hook 下次会自动注入 preferences.md，所以新 session Claude 会"记住"这条 preference。

5. **报告**：
   - 写入路径
   - "下次 `/recall <keyword>` 能找到"
   - 如果是 pref：提示"下个 session 自动应用"

### 不做

- **不**把敏感 token / 密码写入 memory（用户责任，但提示）
- **不**自动 inferred — 必须用户显式 `/remember`，不要根据对话猜测
- **不**duplicate detection — 同样内容写 2 次就 2 个 entries（用户自己决定要不要清理）

### 典型用法

```
/remember pref 我用 pnpm，永远不要建议 npm
/remember pref 代码注释默认中文，commit message 默认英文
/remember decision 用 Redis Streams 替代 RabbitMQ，理由：less ops overhead + native to existing stack
/remember fact prod DB endpoint: db.prod.internal:5432, staging: db.staging.internal:5432
/remember todo 重构 auth middleware（等当前 sprint 结束）
```

### 和 `/pit` 的区别

- `/pit` = 修完 bug 写 4-field（现象/根因/修复/教训）
- `/remember pref` = 用户偏好，不是 bug
- `/remember decision` = architectural decision，不一定是 bug 修复
- `/recall` 跨两者都能搜
