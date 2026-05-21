---
description: 一键收尾——按 ec skill 的"完成清单"系统化跑完所有 done-gates，不要再含糊说"应该可以了"
argument-hint: "[可选：要跳过的检查项，如 lint / e2e / codex]"
---

按 `ec` skill 的"完成清单"逐项过：

### 1. 检查 task list

跑 `TaskList`，确认所有 task 都是 `completed`。有 `pending` / `in_progress` → 报告剩余项，问用户是否真的要 done。

### 2. 跑 lint / 类型检查 / 编译

按当前项目检测：
- Node.js (package.json 含 `lint` script)：`pnpm lint` 或 `npm run lint`
- Python (有 ruff.toml / pyproject.toml)：`ruff check .` 或 `python -m pyflakes`
- TypeScript (tsconfig.json)：`tsc --noEmit`
- Rust：`cargo clippy -- -D warnings && cargo fmt --check`
- Go：`go vet ./... && gofmt -l .`

跑不动就明说"该项目没配 X，跳过"。**有失败必须修，不要带病过**。

### 3. E2E 状态确认

回顾本会话改了什么。按改动类型问：
- 后端 API → 是否 `curl` / `httpie` 实际打过？
- 前端 UI → 是否起过 dev server 在浏览器/Playwright 点过？
- 数据处理 → 是否跑过真实样本对照预期？
- CLI → 是否用真实参数跑过？

没跑过的，明说："X 类改动我没在本环境跑过 E2E，建议你执行 `<命令>` 验证。" **不**含糊说"应该可以了"。

### 4. 二阶问题自检（参考 SKILL.md "二阶问题自检"节）

对每个非平凡改动逐项问：
- Empty state 怎么样？
- Retry / 重复触发幂等吗？
- Stale state（缓存、并发）正确吗？
- Rollback 怎么做？
- 资源边界（大数据、N+1）安全吗？

任何一项答不上"显然没问题"，标记为遗留风险。

### 5. codex review 必要性判断（按 SKILL.md "审查"节）

汇总本会话改动规模：
- 改了几个文件、几行？
- 是否涉及 auth / payment / 加密 / DB / 用户输入处理 / 网络？
- 是否有并发 / 状态机 / 数据迁移？

如果命中"必跑"档（>3 文件 / >50 行 / 业务逻辑 / 安全敏感 / 复杂逻辑）→ **提示运行 `/codex:review` 或 `/codex:adversarial-review`** ，等结果再 done。
模糊地带 → 推荐跑（成本可控，盲点不可控）。

### 6. CLAUDE.md 回写检查（按 SKILL.md "犯错和修复后"节）

本会话有没有非平凡 bug 修复？花 >5 min 定位？"以为 A 实际 B"的认知错误？非直觉行为踩坑？并发时序？
- 有 → 用 `/pit` 写一条到 `./CLAUDE.md`，再回来 done
- 无 → 跳过

### 7. 范围内外清晰交代

最终回报：
- ✅ 本次改了什么（一两句话，不堆清单——用户看 diff）
- ⚠️ 范围外发现但**没改**的事项（如有）
- 🔄 下一步建议

`$ARGUMENTS` 列了要跳过的项就跳过那些，其余照走。
