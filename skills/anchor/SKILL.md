---
name: ec
description: Apply when writing or modifying code — implementing a feature, fixing a bug, refactoring, or any non-trivial multi-step code edit. Enforces intent clarity, task-scope locking via TaskCreate, project-CLAUDE.md compliance, smallest-correct-diff edits, aggressive parallel sub-agents, end-to-end self-verification, multi-pass vulnerability scanning, condition-based Codex review, writing lessons learned back to project CLAUDE.md, anti-drift discipline on long tasks, and optional autonomous mode (don't stop until the task list is fully completed). TRIGGER when the user asks to implement / add / build / fix / debug / refactor / change / optimize anything in code, or hands over a coding task that touches one or more files. Also TRIGGER for security audits, vulnerability scans, and pre-merge verification. SKIP for pure explanation, documentation writing, one-line typo fixes, and brainstorming without code changes.
allowed-tools: Read Grep Glob TaskCreate TaskUpdate TaskList TaskGet AskUserQuestion Bash(grep:*) Bash(rg:*) Bash(git status:*) Bash(git diff:*) Bash(git log:*) Bash(git branch:*) Bash(git show:*) Bash(ls:*) Bash(cat:*) Bash(head:*) Bash(tail:*) Bash(wc:*) Bash(find:*) Bash(pwd) Bash(npm audit:*) Bash(pip-audit:*) Bash(cargo audit:*) Bash(bandit:*) Bash(semgrep:*) Bash(gosec:*)
---

# Efficient Coding

写代码的最大成本不是打字，而是**返工 + 重复踩坑 + 串行思考 + 中途偏题 + 长任务记忆衰减**。这个 skill 把对策压成 **8 条核心规则** + 一系列 references 详细参考。

## 当前项目状态（skill 加载时自动注入）

- 工作目录：!`pwd`
- 项目契约：!`for f in CLAUDE.md AGENTS.md .cursor/rules .github/instructions.md; do [ -f "$f" ] && echo "  ✓ $f ($(wc -l < "$f") lines)"; done; [ -z "$(ls CLAUDE.md AGENTS.md 2>/dev/null)" ] && echo "  (none — fall back to reading neighbor files for de-facto conventions)"`
- Git 状态：!`git rev-parse --git-dir >/dev/null 2>&1 && echo "  branch: $(git branch --show-current 2>/dev/null), $(git status --short 2>/dev/null | wc -l | tr -d ' ') changed files" || echo "  (not a git repo)"`
- Autonomous mode：!`[ -f ~/.claude/.efficient-coding-autonomous ] && echo "  ✅ ENABLED — Stop hook will block stop while task list has incomplete items" || echo "  ⬜ disabled (toggle: touch ~/.claude/.efficient-coding-autonomous)"`

**如果上面显示项目有 CLAUDE.md / AGENTS.md，开任何动作前先读它。** 它是项目宪法。

---

## 核心八条（任何时候被打断都先回这里）

1. **意图清晰才开工**。需求模糊就问，不要二选一兜底硬猜。详见 `references/intent-and-recon.md`。
2. **任务范围用任务列表锁住**（Claude Code: `TaskCreate`；Codex: `plan` tool）。开干前把用户原话当第一条 task 锚住，所有动作只服务 task list 上的项。
3. **先读项目契约**。`CLAUDE.md` / `AGENTS.md` 是项目宪法。**项目契约 > 用户全局规则 > 本 skill**。
4. **最小正确改动**。修 bug 就只改 bug。**显式 > 紧凑**。详见 `references/coding-discipline.md`。
5. **能派 sub-agent 就派，能并行就并行**。一条消息发多个工具调用同时跑。详见 `references/multi-agent-recipes.md`。
6. **审查看情况调 codex**，不是每次都跑。trivial 跳过，复杂 / 安全 / 大改必跑。详见 `references/codex-review-when.md`。
7. **踩坑必须回写当前工作目录的 `CLAUDE.md`**（自动 sync 到 `~/.anchor/memory/pitfalls/`，跨项目可 `/recall`）。否则下次再踩。模板见 `references/pitfall-template.md`。
8. **遇到 topic 先 `/recall`**。SessionStart 注入的"Memory index"列出本项目过去 `/pit` `/decide` `/remember` 写过的 topics — 用户提及 matching topic 时，**先 `/recall <topic>` 拉过去经验**再答，不要凭空。

**额外操作清单**：
- 完工标准（E2E + 二阶自检 + 完成清单）→ `references/e2e-validation.md`
- 卡住时的 观察→假设→验证 协议 + 高代价动作清单 → `references/debugging-and-risks.md`
- 漏洞扫描多遍方法论 + 工具命令 → `references/vuln-checklist.md`

---

## 长任务模式：防偏题 + 防记忆衰减

长任务（>10 步、>30 分钟、跨多个子目标）的两个常见死法：**中途偏题** 和 **skill 被 auto-compact 截掉**。

**锁 scope**：第一件事用任务列表工具建 task，第一条抄用户原话作锚点。拆 3-7 个子 task，每个写**可验证的产出**。

**偏题刹车**：每完成一个 task → 标 completed → 看下一步 → 如果当前想做的事不在 list 上 → **停**。要么加成新 task，要么放弃。

常见偏题信号：
- "顺便看看 X 文件吧" → 跑去 debug 不相关问题
- tool 输出意外结果 → 开始 debug 工具而不是回原任务
- 用户提了一个例子 → 去通用化所有相似情况
- 中途想到"以后扩展"的设计 → 开始加抽象

**长任务记忆维护**：跑了 >30 turn / >1h → 主动 `/ec` re-invoke；感觉"我在做的事是不是偏了"→ 回头对照核心八条；用 `/save <label>` 或 `/snapshot <label>` 做存档；隔天 `/resume-task <label>` 续接。

**复盘节点**：每完成主要阶段（调研完 / 改动完 / 验证完）主动汇报，不要堆到最后。`/recap` 命令一键复盘。

---

## 自治模式：任务完成才停

**仅在 `~/.claude/.efficient-coding-autonomous` 文件存在时启用**。详细协议见 `references/autonomous-mode.md`。

启用后：
- **Stop hook 拦截**：task list 有 pending/in_progress 时，Claude 想 stop 就被 block
- **遇阻自主**：按 `观察 → 假设 → 验证` 排查，**穷尽 3 轮**假设仍无进展才停下报告
- **新需求严守 scope**：发现新事项作为新 task 报给用户决定，不顺手扩
- **`/save` 自动 fallback**：PreCompact + Stop hook 自动 save 到 `~/.anchor/saved-tasks/auto-*.md`

合理停下报告的场景：3 轮假设全证伪 / 需要外部凭证/信息 / 岔路口需要用户决策 / 涉及高代价动作。

用户随时关掉：`rm ~/.claude/.efficient-coding-autonomous`。

---

## 反模式（看到自己在做这些就刹车）

- **"顺手把 X 也改了"** → 不顺手。新事项加新 task
- **"task list 外的事我先做了"** → 偏题信号，停
- **"加点 try/except 防万一"** → 无触发场景的 fallback 不写
- **"加个参数 / 抽象层留着以后用"** → 不加。YAGNI
- **"全文件 Read 一遍保险"** → 不保险，只是慢
- **"先返回半成品占位"** → 不要
- **"测试挂了就 mock 掉"** → 先理解为啥挂
- **"hook 失败就 `--no-verify`"** → 永远不要
- **"单测过了应该没事"** → E2E + 二阶自检过才算
- **"扫一遍漏洞没找到，干净"** → 不干净，继续扫
- **"小改动也跑 codex 保险"** → 噪音，按性质判断
- **"大改动我自己看看就行"** → 不行
- **"任务挺急的，串行做快"** → 错。独立子任务并行才快
- **"自己 grep 三遍就好，不用 agent"** → 广搜场景派 agent
- **"修完了下次再写 CLAUDE.md"** → 现在写
- **"用户没明说但我猜是"** → 问
- **"这个 API 大概这样调"** → 不要猜。grep 实际用例 / WebFetch 文档
- **"虚构执行结果 / benchmark / 日志"** → 永远不要
- **"装包失败？复制别处 node_modules / venv / vendor 进来"** → 这是**作弊**。`npm install` / `pip install` 装不上，**报告 blocker 并停下**："我没法在这环境装依赖（具体原因），需要你在本地执行 `<命令>` 再让我接着跑。" 借别处依赖跑出来的"测试通过"基于借来的环境，下一个干净 clone 的人复现不出来
- **"跑了 30 turn 了感觉不对劲"** → 主动 re-invoke `/ec`
- **(autonomous mode)** **"卡了一下就停下问用户"** → 先穷尽 3 轮假设
- **(autonomous mode)** **"为了让 task 显示 completed 草草标完"** → 不行。可验证产出做到才算 completed

---

## 写完代码的最后一件事

不要堆"我做了 A、B、C"总结——用户看得到 diff。一两句话说**变了什么 / 下一步**就够。

完成清单按序：
1. E2E 跑过、二阶自检过（见 `references/e2e-validation.md`）
2. 漏洞多遍扫过（如适用，见 `references/vuln-checklist.md`）
3. codex review 跑过（**按改动性质**，见 `references/codex-review-when.md`）
4. 踩坑写回 `CLAUDE.md`（如适用，见 `references/pitfall-template.md`）
5. task list 全部 `completed`
6. 范围内外清晰交代

持久化笔记写进 commit message / PR description / CLAUDE.md——不进代码注释。

---

## 命令 + references 速查

### 22 个 slash commands（按阶段分类）

| 阶段 | 命令 |
|---|---|
| **开始任务** | `/lock` / `/init-claude-md` / `/ec` |
| **干活中** | `/next` / `/recap` / `/status` / `/diff` |
| **长任务跨 session** | `/save` / `/resume-task` / `/milestone` / `/snapshot` |
| **跨项目记忆** | `/pit` / `/decide` / `/remember` / `/recall` |
| **收尾 / 安全** | `/scan` / `/cleanup` / `/done` / `/ship` |
| **复盘 / 成本** | `/spend` / `/report` / `/lean` |

### References（按需加载，不每次都读）

| 文件 | 用途 |
|---|---|
| `references/intent-and-recon.md` | 意图清晰 + 60 秒定位（规则 #1 详解） |
| `references/coding-discipline.md` | 动手时的纪律（规则 #4 详解） |
| `references/e2e-validation.md` | E2E + 二阶自检 + 完成清单 |
| `references/codex-review-when.md` | 何时调 codex review（规则 #6 详解） |
| `references/debugging-and-risks.md` | 卡住的协议 + 高代价动作清单 |
| `references/pitfall-template.md` | 踩坑记录模板 + 多类型示例 |
| `references/vuln-checklist.md` | 漏洞 grep 命令 + SAST 工具 + coverage checklist |
| `references/multi-agent-recipes.md` | 多 agent 并行实战 prompt 模板 |
| `references/autonomous-mode.md` | 自治模式完整协议 |
| `references/multi-cli-adapters.md` | Codex / Cursor / Cline / Aider 跨 CLI 适配 |
