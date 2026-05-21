---
description: ADR-style 架构决策记录 — 写到 ~/.anchor/memory/decisions/<project>/。Use when you make a non-trivial design / tech / process decision worth remembering.
argument-hint: "<one-line decision title>"
---

# /decide — architectural decision record (ADR)

把一个**非平凡的设计 / 技术 / 流程决策**记录下来，**跨 session 能 `/recall` 到**。比 `/remember decision` 更结构化 — 含 context / alternatives / consequences。

### Steps

1. **`$ARGUMENTS` 是 decision title**（短陈述句）。如果空，提示给一个。

2. **从对话上下文提取** context / alternatives / chosen / consequences — **不要再问**，除非真的缺：

3. **写入**：`~/.anchor/memory/decisions/<project-slug>/<YYYY-MM-DD>-<title-slug>.md`
   - project-slug = `basename(pwd)`，去特殊字符
   - title-slug = 标题小写化、空格→hyphen、限 50 chars

4. **格式（ADR-lite）**：
   ```markdown
   # <title>
   
   - **Date**: 2026-05-22
   - **Project**: <slug>
   - **Status**: accepted | superseded by <other-decision> | deprecated
   - **Source**: <cwd / git remote / commit hash>
   
   ## Context
   
   <2-4 sentences: what triggered this decision, what constraints applied>
   
   ## Decision
   
   <The choice in 1-2 sentences. Direct.>
   
   ## Alternatives considered
   
   - **<Option A>**: rejected because <why>
   - **<Option B>**: rejected because <why>
   - **<Option C - chosen>**: <why preferred>
   
   ## Consequences
   
   ### Positive
   - <what gets easier>
   
   ### Negative
   - <what gets harder / tradeoffs accepted>
   
   ### Followup
   - <action items that fall out, if any>
   ```

5. **报告**：写入路径 + "用 `/recall <keyword>` 能搜到 + 项目 CLAUDE.md 可以引用这个 file 路径作为权威决策来源"。

### 不做

- **不**自动覆盖已有同 title 的 decision（自动加 `.1` `.2` suffix；提示用户考虑改成 superseding 关系）
- **不**写入项目 `CLAUDE.md` — decision 是**跨 session memory**, CLAUDE.md 是**项目契约**，两个不同
- **不**导入 / 自动 link external ADR 系统 — 简单 local file

### 典型用法

```
/decide 用 Redis Streams 替代 RabbitMQ 做事件 bus
# Claude 从对话 context 抽 context / alternatives / consequences，写 ADR

/decide 缓存策略改成 write-through 不是 write-back
# 同样

/decide 把 monorepo 拆成 6 个独立 repo
# 高 impact decision，必须文档化
```

### 后续

- 月度 retrospective 时 `ls ~/.anchor/memory/decisions/<project>/` 看本月所有决策
- 新人入项目：`/recall <area>` 找历史决策建立 mental model
- 后悔了：在原 decision file 加 `Status: superseded by <new-decision>`，再 `/decide` 新的
