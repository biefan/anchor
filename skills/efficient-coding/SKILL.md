---
name: ec
description: Apply when writing or modifying code — implementing a feature, fixing a bug, refactoring, or any non-trivial multi-step code edit. Enforces intent clarity, task-scope locking via TaskCreate, project-CLAUDE.md compliance, smallest-correct-diff edits, aggressive parallel sub-agents, end-to-end self-verification, multi-pass vulnerability scanning, condition-based Codex review, writing lessons learned back to project CLAUDE.md, anti-drift discipline on long tasks, and optional autonomous mode (don't stop until the task list is fully completed). TRIGGER when the user asks to implement / add / build / fix / debug / refactor / change / optimize anything in code, or hands over a coding task that touches one or more files. Also TRIGGER for security audits, vulnerability scans, and pre-merge verification. SKIP for pure explanation, documentation writing, one-line typo fixes, and brainstorming without code changes.
allowed-tools: Read Grep Glob TaskCreate TaskUpdate TaskList TaskGet AskUserQuestion Bash(grep:*) Bash(rg:*) Bash(git status:*) Bash(git diff:*) Bash(git log:*) Bash(git branch:*) Bash(git show:*) Bash(ls:*) Bash(cat:*) Bash(head:*) Bash(tail:*) Bash(wc:*) Bash(find:*) Bash(pwd) Bash(npm audit:*) Bash(pip-audit:*) Bash(cargo audit:*) Bash(bandit:*) Bash(semgrep:*) Bash(gosec:*)
---

# Efficient Coding

写代码的最大成本不是打字，而是**返工 + 重复踩坑 + 串行思考 + 中途偏题 + 长任务记忆衰减**。这个 skill 把对策压成一组动作。

## 当前项目状态（skill 加载时自动注入）

- 工作目录：!`pwd`
- 项目契约：!`for f in CLAUDE.md AGENTS.md .cursor/rules .github/instructions.md; do [ -f "$f" ] && echo "  ✓ $f ($(wc -l < "$f") lines)"; done; [ -z "$(ls CLAUDE.md AGENTS.md 2>/dev/null)" ] && echo "  (none — fall back to reading neighbor files for de-facto conventions)"`
- Git 状态：!`git rev-parse --git-dir >/dev/null 2>&1 && echo "  branch: $(git branch --show-current 2>/dev/null), $(git status --short 2>/dev/null | wc -l | tr -d ' ') changed files" || echo "  (not a git repo)"`
- Autonomous mode：!`[ -f ~/.claude/.efficient-coding-autonomous ] && echo "  ✅ ENABLED — Stop hook will block stop while task list has incomplete items" || echo "  ⬜ disabled (toggle: touch ~/.claude/.efficient-coding-autonomous)"`

**如果上面显示项目有 CLAUDE.md / AGENTS.md，开任何动作前先读它。** 它是项目宪法。

---

## 核心七条（任何时候被打断都先回这里）

1. **意图清晰才开工**。需求模糊就问，不要二选一兜底硬猜。
2. **任务范围用任务列表锁住**（Claude Code: `TaskCreate`；Codex: `plan` tool / `update_plan`）。开干前把用户原话当第一条 task 锚住，所有动作只服务 task list 上的项。
3. **先读项目契约**。`CLAUDE.md` / `AGENTS.md` 是项目宪法。**项目契约 > 用户全局规则 > 本 skill**。
4. **最小正确改动**。修 bug 就只改 bug。**显式 > 紧凑**——清晰胜过省行数。
5. **能派 sub-agent 就派，能并行就并行**。一条消息发多个工具调用同时跑（Claude Code 派 `Agent`；Codex 用 `plan` 列子任务 + 一轮内多个 shell/read 并发）。串行思考是最大隐性成本。
6. **审查看情况调 codex**，不是每次都跑。trivial 改动跳过，复杂 / 安全 / 大改必跑。
7. **踩坑必须回写当前工作目录的 `CLAUDE.md`**。否则下次再踩。

---

## 长任务模式：防偏题 + 防记忆衰减

长任务（>10 步、>30 分钟、跨多个子目标）的两个常见死法：**中途偏题** 和 **skill 内容被 auto-compact 截掉一半**。

### 锁 scope：开干前 TaskCreate

任何非 trivial 任务**第一件事**用任务列表工具建任务（Claude Code: `TaskCreate`；Codex: `plan` / `update_plan`；或直接用 `/lock <用户原话>`）：

- **第一条 task 抄用户原话**——这是锚点，后面所有动作回头对它。
- 拆 3-7 个子 task，覆盖完整路径（调研 → 改动 → E2E → 回写 CLAUDE.md）。
- task 描述写**可验证的产出**，不要写"看看 X" 这种模糊状态。

### 偏题刹车

每完成一个 task：
1. 标当前 task `completed`（Claude Code: `TaskUpdate`；Codex: `update_plan` 推进状态）。
2. 看 task list 剩什么——下一步是什么。
3. **当前想做的事不在 task list 上**——停。要么加成新 task 等用户确认，要么放弃。

常见偏题信号（看到就刹车）：
- "顺便看看 X 文件吧" → grep 发现新问题 → 跑去管它
- tool 输出意外结果 → 开始 debug 工具而不是回原任务
- 用户提了一个例子 → 我去通用化所有相似情况
- 中途想到"以后扩展"的设计 → 开始加抽象

正确动作：发现的新事项作为**新 task** 写下来（或报给用户），**回当前 task**。

### 长任务的记忆维护

`/ec` 内容 auto-compact 后**只保留前 ~5000 token**——本 SKILL.md 已为此优化（核心规则全部前置）。

主动维护：
- 跑了 **>30 turn** 或 **>1 小时**：主动 `/ec` re-invoke 一次。
- 感觉"我在做的事是不是偏了"——回头看 **核心七条**，对照。
- task list 是外置记忆，**不被 compact**，可靠。

### 复盘节点

每完成主要阶段（调研完 / 改动完 / 验证完），主动汇报：
- 完成了什么（对照 task list）
- 下一阶段做什么
- 是否有需要用户决策的岔路

不要堆到最后才说——用户没法及时纠偏。

---

## 自治模式：任务完成才停

**仅在 `~/.claude/.efficient-coding-autonomous` 文件存在时启用**。详细协议见 `references/autonomous-mode.md`。

启用后：
- **Stop hook 拦截**：task list 还有 pending/in_progress 项时，Claude 想 stop 就被 block，强制继续推进。
- **遇阻自主**：不轻易停下问用户。按 `观察 → 假设 → 验证` 自主排查，**穷尽 3 轮**假设仍无进展才停下报告。
- **新需求不轻易接**：autonomous 中加 task 要严守 scope，新发现报给用户决定，不顺手扩。
- **真卡死的报告格式**：
  ```
  卡在 task #N：
  - 我做了：A、B、C
  - 我看到：D、E
  - 假设是 X，验证发现 Y 不符
  - 我需要：决策 Z 或 信息 W
  ```

### 何时该停下来报告（autonomous 下的合理 stop）

- 穷尽 3 轮假设-验证仍无进展
- 需要外部凭证/权限/信息，环境内拿不到
- 走到岔路口，两种实现影响范围用户必须决策
- 涉及高代价动作（删数据、push 生产、改 schema）

否则**继续干**。

### 用户随时可关掉

`rm ~/.claude/.efficient-coding-autonomous` —— Stop hook 立即放行。

---

## 第一步：意图清晰才动手

含糊的需求 = 必然的返工。任何一项不清楚，**先问**：

- **范围**："改一下登录" → 哪个登录？密码 / OAuth / SSO？改行为还是 UI？
- **症状 vs 期望**："这里 bug" → 重现步骤？预期？观察到什么？
- **关键决策**："加搜索" → 后端搜索 vs 前端过滤？模糊 vs 精确？分页？
- **影响面**："优化性能" → 哪个指标？接受什么取舍？

问的时候：1-3 个**最关键**问题；给具体选项让用户选（Claude Code: `AskUserQuestion`；Codex: 编号 1/2/3/4 让用户回数字）；标 `(Recommended)`。

不用问：已经具体到文件/函数/行号，或明显 trivial。

---

## 第二步：60 秒定位

意图清楚 + 项目契约已读（见顶部注入）之后：

1. **找调用方与被调用方**。改函数前 grep 引用点；改接口前看上下游。
2. **找现有抽象**。要加 util？先看 `utils/` / `helpers/` / `lib/`。
3. **找现有依赖**。要加包？先 grep manifest 看有没有等价的。
4. **说出假设**。猜数据结构 / 配置项 / 返回类型——停下来 grep / 读真实代码。
5. **一句话目标**。"让 X 从 A 变到 B"说清楚。说不清楚 = 还没想清楚。

搜索任务**能并行就并行**。

---

## 多 agent 并行：默认开火力

写代码的瓶颈通常不是模型能力，是**串行思考**。详细 prompt 模板见 `references/multi-agent-recipes.md`。

### 默认派 agent

| 场景 | 派谁 | 单独/并行 |
|---|---|---|
| 广泛搜索（>3 次 grep 才覆盖） | 探索型子代理（Claude Code: `Explore` agent；Codex: `plan` 列搜索步 + 多 shell 并发） | 单独 |
| 多步实现需先做架构方案 | 规划型（Claude Code: `Plan` agent；Codex: `plan` tool 先输出方案） | 单独 |
| 独立多路调研（前端/后端/infra） | 多路并发（Claude Code: 多 `Explore`；Codex: 一个 plan 多个并发分支） | **并行** |
| 多个独立子任务（功能 A / bug B / 调研 C） | 对应 agent | **并行** |
| 主线写代码 + 副线调研/扫漏洞/build | 主线自做 + 副线 agent 后台 | **并行** |
| 长跑任务（CI / 大查询 / build / install） | `Bash` background | **并行** |
| 大型审查 | `codex:review --background` | **并行** |

### 并行做法

**一条消息里发多个工具调用**，同时跑：

```
[同一条消息内]
- Agent: Explore  "找所有调用 OldAuth 的地方"
- Agent: Explore  "看新 SDK 的认证 API 文档"
- Agent: Plan     "迁移方案分阶段"
→ 三个并行
```

派一个 → 等 → 再派一个 = 三倍 wall clock。

### 不派 agent

- 已知具体路径/符号 → 自己 Read/grep 更快
- 1-2 步简单操作（改常量、加 import）
- 紧密依赖刚才对话上下文

---

## 动手时

### 只改要改的

不顺手：重构无关函数 / 调 import 顺序 / 改格式 / 加"以备将来"的参数 / 写无触发场景的 try/except。每一处无关改动都是 PR review 负担 + git blame 噪音 + 潜伏回归。

### 显式 > 紧凑

不为了少几行写嵌套三元 / dense one-liner / 删有用的中间变量。

### 信任已有保证

只在**系统边界**验证（用户输入、外部 API、跨进程消息、文件 IO）。框架契约保证的不要重复 check。

### 并行调用工具

读三个不相关文件 → 一条消息三个 Read。独立 grep / build / lint → 同条消息并行。只有 B 依赖 A 才串行。

---

## 验证：自己做 E2E

**单元测试通过 ≠ 功能正确**。

### E2E 标准

- **后端 API**：起 server，`curl`/`httpie` 发请求看真实响应；golden path + 1 错误路径。
- **前端 UI**：起 dev server，浏览器/Playwright 亲手点一遍。
- **数据处理**：跑真实样本通过 pipeline，对照预期。
- **CLI/脚本**：真实参数跑一次，看 stdout/stderr + exit code。
- **集成/跨模块**：跑集成测试。

跑不了**明说**："我没法在这个环境跑 X，建议你执行 `<具体命令>`。"

### 二阶问题自检

E2E 跑通**不等于**完工。再问一遍：

- **Empty state**：列表空、数据 null、首次进来没缓存——会崩吗？
- **Retry / 重复触发**：连点、网络重试、消息重复消费——重复扣款/发邮件？幂等吗？
- **Stale state**：缓存过期、并发写、tab 切回来——状态对吗？
- **Rollback / 上线安全**：怎么回滚？数据迁移可逆吗？feature flag 能关吗？
- **资源边界**：大数据量、慢网络、磁盘满？N+1？

任何一项答不上"显然没问题"，未完成。

### 最后清单

- [ ] 改动只覆盖任务范围（对照 task list）
- [ ] 类型 / 编译 / lint 过
- [ ] 项目 CLAUDE.md 规则遵守
- [ ] 注释只解释 **why**
- [ ] 没引入不必要依赖/状态/抽象
- [ ] 没留 TODO/FIXME/dead code/print
- [ ] task list 所有项都 `completed`

---

## 漏洞扫描：多遍扫，扫到为止

**一遍只能找表面**。第一遍找到 0 个 = 你没扫深。详细 grep 命令 / SAST 工具 / coverage checklist 见 `references/vuln-checklist.md`。可以用 `/scan [范围]` 引导单轮扫描。

### 多遍层次（能并行就并行）

1. **模式匹配**：grep 反模式 + 跑 SAST（`npm audit` / `pip-audit` / `cargo audit` / `bandit` / `gosec` / `semgrep`）。工具输出原样保留作基线。
2. **数据流追踪**：每个用户可控输入追到敏感 sink（SQL / shell / 文件 / 反序列化 / 模板 / URL / 日志）。**读代码**，工具找不到逻辑漏洞。
3. **跨文件 / 跨抽象**：调用方没授权 / 子类覆写 hook / 配置 IaC CI 里的 secret-permission-network。
4. **codex 交叉**：`/codex:adversarial-review` 或 `/security-review`，告诉它你已发现什么，让它找你没发现的。

### 何时停

前 3 遍 + codex 交叉 + 连续两遍只 surface 已知问题 + 满足 coverage checklist。只跑一遍说"扫完"——**继续**。

### 报告

每条 finding：`ID | Severity | file:line | Exploit(1 句) | Fix`。写不出 exploit 就降级或删。

---

## 审查：看情况调 codex

**自审有盲点**，但 **trivial 改动不必兴师动众**。

**必跑**：>3 文件 / >50 行 / 业务逻辑分支 / 安全敏感（auth/payment/加密/DB/IO） / 复杂逻辑（并发/状态机/迁移） / "不太自信" / 创建 PR 前。

**跳过**：typo / 常量改名 / 注释 / 格式 / 纯样式 / 1-2 行明显修复 / 已在 codex 上下文 / 用户说不审。

**拿不准就跑**——审查成本可控，盲点代价不可控。

命令：`/codex:review`（质量） / `/codex:adversarial-review`（挑战设计） / `/security-review`（安全专项）。大改动用 `--background` 后台跑，主线继续干。

反馈处理：真问题修；看起来不对**先验证**再说；多条交叉重复=有共性问题找根因。**原样**给用户看 codex 输出，不要先过滤先反驳。

---

## 犯错和修复后：把教训写回项目 CLAUDE.md

**最易忽略、回报最大**。可以用 `/pit [标题]` 引导。详细模板和多类型示例见 `references/pitfall-template.md`。

### 必写

- 花 >5 分钟定位的 bug
- "以为是 A 实际是 B" 的认知错误
- 依赖库 / 框架非直觉行为踩坑
- 并发 / 异步 / 时序问题
- "测试通过但生产挂了" 的盲点
- 反复出现过 2+ 次的问题

### 不写

typo、格式、通用编程常识、一次性偶发问题。

### 写到哪 + 怎么写

**当前工作目录的 `CLAUDE.md`**（也接受 `AGENTS.md`，看项目用哪个；不是 `~/.claude/CLAUDE.md`）。不存在就创建。已存在追加到 `## 踩坑记录 / Known Pitfalls / Lessons Learned`。

**绝对不要写到这些地方**（即使工具方便也不要——它们解决不了同一个问题）：
- ❌ **代码注释** —— 注释会过期，PR diff 会改掉它们，没人专门去翻。
- ❌ **`~/.codex/memories/` / Codex 的 `update_memory` 工具** —— 那是**用户级**记忆（user-level memory），跨所有项目共享，**不会跟着项目走**。换台机器、新成员 clone、CI 容器都看不到。即使你是 Codex，**写到 cwd 的 `CLAUDE.md` 而不是 memory**——这是"踩坑跟着项目走"的强约束。
- ❌ **`~/.claude/CLAUDE.md`** —— 同理，user-level，跨项目，不该装项目特定踩坑。
- ❌ **commit message 单行** —— 单行容易丢上下文 + 后人不会专门 grep commit history。

**为什么必须项目级**：项目踩坑只对这个项目有意义；跟着 git 走才能让下一个 contributor（人 / AI / 自己 6 个月后）在进入项目时看到。这就是 SKILL.md "先读项目契约"那条规则的依赖项。

每条 3-5 行：

```markdown
### [一句话标题] (YYYY-MM-DD)
- **现象**：观察到什么
- **根因**：实际是什么
- **修复**：怎么改的 / `file:line`
- **教训**：下次遇到 X 类问题先检查 Y
```

**选择标准**：6 个月后的自己看到这条会感谢现在的自己——写。否则不写。

写完一句话告诉用户："已把踩坑记录追加到 `./CLAUDE.md`。"

---

## 反模式（看到自己在做这些就刹车）

- **"顺手把 X 也改了"** → 不顺手。新事项加新 task。
- **"task list 外的事我先做了"** → 偏题信号，停。
- **"加点 try/except 防万一"** → 无触发场景的 fallback 不写。
- **"加个参数 / 抽象层留着以后用"** → 不加。YAGNI。
- **"全文件 Read 一遍保险"** → 不保险，只是慢。
- **"先返回半成品占位"** → 不要。
- **"测试挂了就 mock 掉"** → 先理解为啥挂。
- **"hook 失败就 `--no-verify`"** → 永远不要。
- **"单测过了应该没事"** → E2E + 二阶自检过才算。
- **"扫一遍漏洞没找到，干净"** → 不干净，继续扫。
- **"小改动也跑 codex 保险"** → 噪音，按性质判断。
- **"大改动我自己看看就行"** → 不行。
- **"任务挺急的，串行做快"** → 错。独立子任务并行才快。
- **"自己 grep 三遍就好，不用 agent"** → 广搜场景派 agent。
- **"修完了下次再写 CLAUDE.md"** → 现在写。
- **"用户没明说但我猜是"** → 问。
- **"这个 API 大概这样调"** → 不要猜。grep 实际用例 / WebFetch 文档 / 看 SDK 源码。不编造 import / 签名 / 返回结构。
- **"虚构执行结果 / benchmark / 日志"** → 永远不要。没跑过就说没跑过。
- **"装包失败？复制别处 node_modules / venv / vendor 进来"** → 不要。这是**作弊**。任何 `npm install` / `pip install` / `cargo build` / `go mod download` 装不上，**报告 blocker 并停下**："我没法在这环境装依赖（具体原因），需要你在本地执行 `<命令>` 再让我接着跑。" 千万不要从别的项目目录借 `node_modules` / `site-packages` / `vendor/` —— 跑出来的"测试通过"是基于借来的环境，下一个干净 clone 的人复现不出来。同样：不要把别处的 `Cargo.lock` / `package-lock.json` / `go.sum` 拷过来"凑数"。
- **"跑了 30 turn 了感觉不对劲"** → 主动 re-invoke `/ec`。
- **(autonomous mode)** **"卡了一下就停下问用户"** → 先穷尽 3 轮假设。
- **(autonomous mode)** **"为了让 task 显示 completed 草草标完"** → 不行。可验证产出做到才算 completed。

---

## 卡住时：观察 → 假设 → 验证

调试是搞清楚"模型 vs 现实"哪里对不上，不是"换姿势试试"。

1. **观察**：现在到底发生了什么？精确描述——错误信息、复现步骤、最小输入。
2. **假设**：基于观察提**一个**假设，不要同时怀疑 5 件事。
3. **验证**：设计能**证伪**该假设的最小实验，跑，对照预期。
4. 证伪 → 观察新现象回 step 1。证实 → 修，写回 CLAUDE.md。

**禁止**：跳 lint / 跳测试 / 删错误日志 / catch-and-ignore；改 assertion 让测试"过"；循环里加 sleep 等问题"自己消失"；同时改 3 处希望"总有一处奏效"。

非 autonomous mode 修不动 → 先报告现状（假设 X，证据 Y 不符，需 Z）。
autonomous mode 修不动 → 穷尽 3 轮假设，仍无果再按上方格式停下报告。

---

## 高代价动作：动手前先确认

- 不可逆：删文件/分支、`git reset --hard`、覆盖未提交、`rm -rf`、drop table
- 影响共享：push / force-push / 创建合并关闭 PR / 发消息 / 改生产
- 跨多文件且影响架构
- 引入新依赖、改 CI、改 schema、改环境变量、换包管理器
- 上传到第三方服务（diagram / pastebin / gist）

**先说要做什么、为什么、影响范围**，等用户确认。

不主动 `git commit` / `push` / `branch` / `merge` / `rebase` / `tag`。永远不 `--no-verify`。

---

## 写完代码的最后一件事

不要堆"我做了 A、B、C"总结——用户看得到 diff。一两句话说**变了什么 / 下一步**就够。

完成清单按序：
1. E2E 跑过、二阶自检过
2. 漏洞多遍扫过（如适用）
3. codex review 跑过（**按改动性质**）
4. 踩坑写回 `CLAUDE.md`（如适用）
5. task list 全部 `completed`
6. 范围内外清晰交代

持久化笔记写进 commit message / PR description / CLAUDE.md——不进代码注释。

---

## Slash commands & references 速查

| 命令 / 文件 | 用途 |
|---|---|
| `/ec` | 强制加载本 skill 完整内容 |
| `/lock <用户原话>` | 任务开始前用 TaskCreate 锁 scope |
| `/pit [标题]` | 修完 bug 后写踩坑记录到 ./CLAUDE.md |
| `/scan [范围]` | 漏洞扫描多遍法的下一轮 |
| `/done [跳过项]` | 一键收尾：lint + E2E + codex 判断 + CLAUDE.md 回写检查 |
| `/next` | 看 task list 下一步并标 in_progress |
| `/recap` | 复盘已做 / 剩余 / 岔路（不修改状态，只汇报） |
| `/init-claude-md` | 项目无 CLAUDE.md 时一键创建骨架 |
| `references/autonomous-mode.md` | 自治模式协议详解 |
| `references/pitfall-template.md` | 踩坑记录模板 + 多类型示例 |
| `references/vuln-checklist.md` | 漏洞 grep 命令 + SAST 工具 + coverage checklist |
| `references/multi-agent-recipes.md` | 多 agent 并行实战 prompt 模板 |
| `references/multi-cli-adapters.md` | 在 Cursor / Cline / Aider 上手动安装 anchor（hooks/commands 不跨过去） |
