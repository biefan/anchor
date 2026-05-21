---
description: 分析 git diff 的风险面 —— 改动规模、命中敏感关键词、可能引入的回归类别。Use before /done or before committing to spot trouble early.
argument-hint: "[base ref, default HEAD or main; or specific file path]"
---

分析当前改动的风险面，按 4 段输出：

### 1. 决定 diff 范围

按 `$ARGUMENTS` 决定：
- 空 → `git diff` （unstaged + staged 都看）
- 文件名/路径 → `git diff -- <path>` 限定该路径
- ref（main / HEAD~3 / commit sha） → `git diff <ref>..HEAD`
- `--cached` → 只看 staged

跑命令前先告诉用户：scope is X，否则用户不知道你在分析啥。

### 2. 规模 + 文件清单

```bash
git diff <range> --stat
git diff <range> --name-only
```

报告：
- 总文件数 / 增加行 / 删除行
- 按目录分组（前端 / 后端 / 测试 / 配置）

### 3. 风险扫描

对改动的文件名 + diff 内容（用 `git diff <range>`）扫这几类关键词。每个命中**列具体 file:line**：

**🔴 高风险**（必须人工 review）：
- `auth`, `password`, `secret`, `token`, `jwt`, `oauth`, `session`, `cookie`
- `payment`, `charge`, `refund`, `billing`
- `crypto`, `encrypt`, `decrypt`, `signature`, `hash`
- `migration`, `schema`, `CREATE TABLE`, `ALTER TABLE`, `DROP`
- `eval(`, `exec(`, `dangerouslySetInnerHTML`, `innerHTML =`, `shell=True`
- 硬编码的 URL / IP / API key 模式

**🟡 中风险**（建议二阶问题自检）：
- 并发原语：`async`, `await`, `Promise`, `goroutine`, `Mutex`, `Lock`
- 缓存：`cache`, `redis`, `memcache`
- 错误处理：`try/except`, `catch`, `panic`
- 状态机：`state`, `status`, `enum`

**🟢 低风险**（FYI 不阻塞）：
- 纯 UI / CSS / 文案
- 测试代码
- 文档

跑命令的好套路：

```bash
git diff <range> | grep -inE '(password|secret|token|jwt|eval\(|exec\(|innerHTML|dangerouslySet|shell=True|DROP\s+TABLE)' | head -30
```

### 4. 二阶问题清单

针对**已找到的高/中风险点**，列出二阶问题（不是泛泛清单——具体到改动）：

举例：
- 改动里有 `async` 调用没 await → 是否漏了 await？
- 改动里加了新 catch 块 → catch 范围是否过宽（catching too much）？
- 改动里碰了 migration → 是否可逆？数据备份策略？
- 改动里加了新外部依赖 → 是否进了 dependency manifest？

### 5. 一句话 verdict

最后给个 verdict 让用户快速决策：

- "✅ 看上去 ship-ready，没看到红色风险" 
- "⚠️ N 个中风险点，建议跑 `/done` 全流程包括 codex review"
- "🔴 N 个红色风险（auth/payment/crypto/db migration 等），强烈建议人工 review + codex adversarial review"

### 6. 不做的事

- ❌ 不修改任何文件（这是 read-only 分析）
- ❌ 不评价代码风格 / 命名好坏（那是 codex review 做的事）
- ❌ 不替用户决策"要不要 ship"——只 surface 风险，决定权在用户
