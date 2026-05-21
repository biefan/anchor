# anchor

[![CI](https://github.com/biefan/anchor/actions/workflows/ci.yml/badge.svg)](https://github.com/biefan/anchor/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/biefan/anchor?sort=semver)](https://github.com/biefan/anchor/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/regression-364%2F364-brightgreen.svg)](evals/regression/)

[English](README.en.md) | **中文**

> **Claude Code / Codex CLI 的工程化纪律包**  
> 让 AI 写代码"少走错路、不偏题、跑到完为止"，并且**真的记得住**跨 session 跨项目的经验。

| 维度 | 数量 | 内容 |
|---|---|---|
| Slash commands | **22** | 工作流 / 长任务 / 记忆 / 复盘 / 安全 / Token 经济 |
| Hooks | **5** | SessionStart / Stop / PreToolUse / PostToolUse / PreCompact |
| 防御 patterns | **277+** | 14 轮 audit / 残忍 obfuscation 测试 |
| Regression tests | **364/364** | 15 suites（hooks / 记忆 loop / install / manifest 等）|
| 长期记忆类别 | **7** | pitfalls / decisions / facts / preferences / todos / snapshots / saved-tasks |
| 跨 CLI | **2** | Claude Code + OpenAI Codex CLI |

**Quick links** → [实测战报](#实测战报v191-跑过-3-个真实场景) · [它解决什么](#它解决什么) · [1 分钟上手](#1-分钟上手) · [22 个命令](#22-个-slash-commands) · [设计原则](#设计原则) · [对比](#和市面上对比) · [Plugin 安装](#作为-plugin-安装-推荐)

---

## 实测战报（v1.9.1 跑过 3 个真实场景）

在 Codex CLI 上跑 [`evals/stress/`](evals/stress/) 里的 3 个长任务测试，用 `evals/stress/grade.py`（codex-as-judge）评分。

| 场景 | v1.3 baseline | v1.4.6 | **v1.9.1** | 改进 |
|---|---|---|---|---|
| **debug 5 个失败测试** | 6/1/1 | 5/2/1 | **6/1/1** | 回到 peak — CLAUDE.md 4-field format ✅ |
| **refactor 保留行为** | 3/1/3 | 3/1/3 | **4/0/3** ⬆ | tests-before-refactor 第一次过 |
| **scaffold Express + SQLite API** | 2/3/0 | 3/2/2 | **3/2/2** | anti-borrow-deps 持续闭环 |
| **总计 (pass/fail/N-A)** | 11/5/4 | 11/5/6 | **13/3/6** | **+2 pass / -2 fail** |

**最有信号的 finding**：

> **anti-borrow-deps 跨场景闭环**：v1.3 抓到 agent 借 node_modules cheat → v1.3.3 SKILL.md 加 anti-pattern → v1.9.1 stress #1 agent 正确说 *"我没法在这里装依赖，请你本地跑 npm install 再跑测试"* 并停下。
>
> **CLAUDE.md format regression 修复**：v1.4.6 stress #3 写了 pitfall 但 format 偏（bullet list 而非 4-field），v1.9.1 加了 SKILL.md auto-recall reflex 后 stress #3 format 完全合规。
>
> 三段闭环：`grade.py finding → SKILL.md update → 实测验证`。

跑自己的：

```bash
./evals/stress/run.sh <1|2|3>      # 一条命令 prep fixture + 跑 codex exec + extract + grade
./evals/stress/run.sh 1 --keep     # 保留 sandbox 供检查
```

**和市面上替代品的对比** → [`docs/competitors.md`](docs/competitors.md)（诚实评估，含 Praxis / HOTL / Session Orchestrator / Aegis / Archcore 等 10+ 对比）。

## 它解决什么

| 问题 | anchor 怎么解 |
|---|---|
| 中途偏题（被 tool 输出带跑、顺手做范围外的事） | `/lock` 锁用户原话当第一条 task / autonomous mode Stop hook 拦截 |
| 长任务记忆衰减（auto-compact 截掉 skill） | 关键规则前置 SKILL.md / PreCompact hook 提示 `/save` / `~/.anchor/active-task.md` 跨 session 续接 |
| 单测过 ≠ 功能正确（不做 E2E 就说"完成"） | `/done` checklist 强制走 E2E + 二阶自检 |
| 漏洞扫一遍说"干净" | `/scan` 多遍扫方法论 / `/codex:review` 交叉验证 |
| 修完 bug 转头就忘 | `/pit` 写当前项目 `CLAUDE.md` + 自动 sync 到 `~/.anchor/memory/pitfalls/<project>/` |
| 自己审自己有盲点 | `/done` 按改动规模触发 codex review；trivial 跳过、复杂/安全/大改必跑 |
| **下次 session 不知道上次踩过什么坑** ⭐ | SessionStart 自动注入本项目 memory index → SKILL.md 规则 #8 "auto-recall reflex" |
| **跨项目复用经验**（"我上个项目踩过这个 redis cluster 坑"） | `/recall <keyword>` grep `~/.anchor/memory/` 全部 7 个 category |
| **危险命令本能误操作**（`git push --force` / `rm -rf /` 等） | PreToolUse hook 拦 277+ patterns（包括组合绕过 / obfuscation / 跨平台变种）|

**两层防线**：
- **软**：SKILL.md 写明工作流，模型主动遵循；commands 引导专门动作
- **硬**：5 个 hooks 在关键时机自动触发（SessionStart 注入 / PreToolUse 拦截 / PostToolUse lint / Stop 推进 / PreCompact 警告）

---

## 1 分钟上手

```bash
# 1. 安装（一键，含 Codex CLI 检测）
git clone https://github.com/biefan/anchor.git ~/anchor && cd ~/anchor && ./install.sh

# 2. 打开 Claude Code 进项目，第一次先建 CLAUDE.md
/init-claude-md                    # 自动识别项目类型并选 template

# 3. 锁定任务 scope，开始干活
/lock 把 order-service 拆成 6 个模块

# 4. 启动 autonomous mode（做完才停）
touch ~/.claude/.efficient-coding-autonomous

# 5. 干完一阶段标记 milestone（多日任务用）
/milestone phase-1-parse-extracted

# 6. 下班保存进度
/save end-of-day-refactor

# 7. 第二天进 session，自动注入昨天状态
/resume end-of-day-refactor

# 8. 修完 bug 写踩坑（跨项目可 /recall 到）
/pit

# 9. 一键收尾
/done
```

完整 walkthrough → [`docs/playbook.md`](docs/playbook.md)（5 个典型场景：新项目 / 长 refactor / 安全审计 / 多 agent 并行 / 跨 session 续接）

## 安装

```bash
# 克隆 + 一键安装
git clone https://github.com/biefan/anchor.git ~/anchor && cd ~/anchor && ./install.sh
```

`install.sh` 一键完成：
1. 复制 skill / **22 个** slash commands / **9 个** hook 脚本 / **5 个** init templates 到 `~/.claude/`
2. **自动 merge 5 个 hooks 到 `~/.claude/settings.json`**（带 timestamp backup，可用 `--no-hooks` 跳过）
3. 检测到 codex CLI 就同时安装到 `~/.codex/`（skill + 22 commands as skills）
4. **3 层锁机制**：`flock(1)` → Python `fcntl.flock` → mkdir-atomicity，永不 silent loss-of-serialization
5. 重复跑无副作用（idempotent，不会重复 merge hooks）

**首次安装后需要重启 Claude Code**（如果 `~/.claude/skills/` 是首次创建的话）——live change detection 不监视会话启动时不存在的顶层目录。

也支持作为 **plugin** 安装（推荐 Codex CLI 用户，因为 plugin 安装 Codex hooks 也自动启用）→ [下方"作为 plugin 安装"章节](#作为-plugin-安装-推荐)。

## 包含什么

```
anchor/
├── README.md / README.en.md            # 双语文档
├── CHANGELOG.md                        # 34 个 release 的完整变更
├── docs/
│   ├── playbook.md                     # 5 个典型场景实战 walkthrough
│   └── competitors.md                  # 跟 10+ 同类工具的诚实对比
├── install.sh / uninstall.sh           # 一键安装/卸载（含 3-tier 锁）
├── .claude-plugin/plugin.json          # Claude Code plugin manifest
├── .codex-plugin/plugin.json           # Codex CLI plugin manifest
├── hooks/hooks.json                    # 5 个 hooks 共享配置
├── settings.hooks.json                 # ~/.claude/settings.json merge 示例
├── skills/anchor/
│   ├── SKILL.md                        # 8 核心规则 + 长任务 + 验证 + 漏洞扫描 + 记忆 reflex
│   ├── references/                     # 按需载入的详细参考
│   │   ├── autonomous-mode.md
│   │   ├── pitfall-template.md
│   │   ├── vuln-checklist.md
│   │   ├── multi-agent-recipes.md
│   │   ├── multi-cli-adapters.md
│   │   └── templates/                  # 5 种 init-claude-md template
│   │       ├── web-app.md / library.md / cli-tool.md
│   │       ├── data-pipeline.md / default.md
│   └── scripts/                        # 9 个 hook + helper 脚本
│       ├── session-start-inject.sh     # SessionStart: 项目契约 + git + memory index + active-task
│       ├── stop-self-check.sh          # Stop: autonomous 模式拦截未完任务
│       ├── pre-tool-danger.sh          # PreToolUse: 277+ 危险 pattern + 14 轮 audit
│       ├── post-tool-lint.sh           # PostToolUse: ruff/eslint/shellcheck/etc
│       ├── pre-compact-warning.sh      # PreCompact: 提示 /save 防丢任务状态
│       ├── analyze-events.py           # 事件 log 聚合（/status /report 用）
│       ├── pitfall-sync.py             # /pit 后跨项目 sync 到 ~/.anchor/memory/
│       ├── ec-status.sh                # statusline / /status 输出
│       └── statusline-wrapper.sh
├── commands/                           # 22 个 slash commands
└── evals/
    ├── stress/                         # 3 个长任务 stress test + codex-as-judge
    ├── regression/                     # 15 个 regression suite / 364 cases
    └── results/                        # 历史 stress test 报告

~/.anchor/                              # 长期记忆树（user-level，不在 repo）
├── active-task.md                      # 跨 session 长任务状态
├── saved-tasks/<label>.md              # /save → /resume
└── memory/
    ├── pitfalls/<project>/<file>.md    # /pit auto-sync
    ├── decisions/<project>/<file>.md   # /decide
    ├── facts/<project>/<file>.md       # /remember fact
    ├── snapshots/<project>/<label>/    # /snapshot full state
    ├── preferences.md                  # /remember pref (auto-inject 下次 session)
    └── todos.md                        # /remember todo
```

## 22 个 slash commands

按使用阶段分类，**任务流程上看一眼就懂**：

### 🚀 开始任务

| 命令 | 作用 |
|---|---|
| `/lock <用户原话>` | 把用户原话锚定为第一条 task，所有后续动作只服务它 |
| `/init-claude-md [--template=X]` | 项目无 CLAUDE.md 时自动识别类型 + 生成骨架（5 种 template）|
| `/ec` | 强制加载完整 SKILL.md 内容（auto-compact 后用） |

### ⚒️ 干活中

| 命令 | 作用 |
|---|---|
| `/next` | 看 task list 下一步，标 in_progress |
| `/recap` | 复盘进度：已做 / 剩余 / 岔路 / 需决策项 |
| `/status` | autonomous mode 状态 + task 进度 + 7 天 hook 触发统计 |
| `/diff` | 分析 git diff 的风险面（改动规模 / 敏感关键词 / 回归类别） |

### 🔒 长任务跨 session

| 命令 | 作用 |
|---|---|
| `/save [label]` | 持久化当前 task list（end-of-day / 担心 compact 前）|
| `/resume [label]` | 在新 session 用 TaskCreate 重建之前 save 的 task list |
| `/milestone <name>` | 标记阶段完成，写入 `~/.anchor/active-task.md` 给后续 session 看 |
| `/snapshot <label>` | Workspace 完整快照（task + git diff + 文件 + 决策）|

### 🧠 跨项目长期记忆

| 命令 | 作用 |
|---|---|
| `/pit [标题]` | 修完 bug 写 4-field 踩坑到 `CLAUDE.md` + 自动 sync 到全局 |
| `/decide <题目>` | ADR-style 架构决策记录 |
| `/remember pref\|decision\|fact\|todo <内容>` | 通用长期记忆写入 |
| `/recall <keyword>` | 跨项目 grep 7 类记忆（**这是关键 — 让 anchor 真的"记得住"**）|

### ✅ 收尾 / 安全

| 命令 | 作用 |
|---|---|
| `/scan [子目录]` | 漏洞深扫一遍（多遍方法论 + SAST 工具）|
| `/cleanup` | 找 dead code / debug print / 未用 import / 过期 TODO |
| `/done` | 收尾 checklist：lint + E2E + codex review（按规模）+ CLAUDE.md 写回 |
| `/ship` | done check + Conventional Commit + gh PR create 一条龙 |

### 💰 成本 / 复盘

| 命令 | 作用 |
|---|---|
| `/cost` | 当前 session token / 时长 / 估算 USD（调 ccusage 或 fallback 估）|
| `/report [days]` | 跨 session 聚合（drift heatmap / top blocked patterns / 趋势对比）|
| `/lean on\|off` | 切换 token-saving mode（SessionStart 减少注入 ~900 token/session）|

### 自动触发

不用 `/<cmd>` 也行 — Claude 看到符合 description 的任务（implement / fix / refactor / debug / 安全审查 等关键词），**自动调用** anchor skill 走完整流程。manual `/cmd` 是显式 override。

### 启用 / 关闭自治模式（任务完成才停）

```bash
# 启用：Claude 推进任务直到 task list 全部 completed，才允许 stop
touch ~/.claude/.efficient-coding-autonomous

# 关闭：恢复常规对话模式
rm ~/.claude/.efficient-coding-autonomous
```

**适合**：用户给一个完整任务后想要"做完才停"
**不适合**：探索性对话、需要边做边商量的决策

详细协议见 [`references/autonomous-mode.md`](skills/anchor/references/autonomous-mode.md)。

## 设计原则

### 核心八条（任何时候被打断都回这里）

1. **意图清晰才开工**（含糊就问，不二选一兜底）
2. **任务范围用 `TaskCreate` 锁住**（用户原话当第一条 task）
3. **先读项目契约**（`CLAUDE.md` / `AGENTS.md`）
4. **最小正确改动**（显式 > 紧凑）
5. **能派 agent 就派，能并行就并行**
6. **审查看情况调 codex**（trivial 跳过，复杂 / 安全 / 大改必跑）
7. **踩坑必须回写**当前工作目录的 `CLAUDE.md`（+ 自动 sync 跨项目）
8. **遇到 topic 先 `/recall`** ⭐（SessionStart 注入 memory index → 用户提及 matching topic 时先拉过去经验再答）

### 防偏题三招

- **TaskCreate 锁 scope**：用户原话当第一条 task 锚住
- **偏题刹车**：每完成 1 task 看下一步，发现不在 list 上就停
- **新事项加新 task**：不顺手做，让用户决定

### 防记忆衰减（v1.7+ 跨 session）

- **关键规则前置** SKILL.md 顶部（auto-compact 保留前 5000 token）
- **task list 是外置记忆**（不被 compact）
- **`~/.anchor/active-task.md`** 跨 session 续接（branch / milestone history / open questions）
- **PreCompact hook** 在 auto-compact 前提示 `/save`
- **长任务主动 re-invoke** `/ec` 恢复完整内容

### 跨项目记忆系统（v1.8+ 真的记得住）

```
[写] /pit /decide /remember /snapshot
   ↓ 写入 ~/.anchor/memory/<category>/<project>/
[索引] SessionStart 自动列出本项目 memory titles
   ↓
[反射] SKILL.md 规则 #8: 用户提 matching topic 时先 /recall
   ↓
[读] /recall <keyword> 拉完整内容
```

之前缺中间两段（**索引 + 反射**），所以变 write-only。v1.9.0 起 closed loop。

### 自治模式（autonomous mode）

```bash
touch ~/.claude/.efficient-coding-autonomous     # ON
rm ~/.claude/.efficient-coding-autonomous        # OFF（默认）
```

- ON：Stop hook 检查 task list 未完成项就 `block`，让 Claude 继续
- 遇阻按"**观察 → 假设 → 验证**"自主推进，穷尽 3 轮才停下报告

## Codex CLI 支持

本 skill 同样跑得动 **OpenAI Codex CLI**（0.130+）——它和 Claude Code 共用同一份 [agentskills.io](https://agentskills.io) SKILL.md 标准。

### 自动安装

`install.sh` 检测到 `codex` 在 `PATH` 里时会自动同时把 skill 复制到 `~/.codex/skills/ec/`，无需额外配置。手动可以直接复制：

```bash
mkdir -p ~/.codex/skills/ec
cp -r skills/anchor/{SKILL.md,references,scripts} ~/.codex/skills/ec/
```

### 用法

- **自动触发**：写代码 / 修 bug / 漏洞审查等场景，Codex 按 description 自动加载 `ec`
- **手动触发**：`/skills` 或直接调用 `ec`

验证装上了：
```bash
codex exec --json --skip-git-repo-check 'list available skills' | grep -i '"ec"'
```

### 跨平台覆盖范围

| 内容 | Claude Code | Codex CLI |
|---|---|---|
| SKILL.md（核心七条 + 长任务模式 + 自治 + 验证 + 漏洞扫描 + 审查 + 踩坑回写） | ✅ | ✅ |
| references/（详细参考文件） | ✅ | ✅ |
| 自动按 description 触发 | ✅ | ✅ |
| Slash 命令（/lock /pit /scan /done /next /recap /init-claude-md） | ✅ `~/.claude/commands/` | ✅ `~/.codex/skills/<name>/`（每条 command 是独立 skill，invoke 名相同） |
| SessionStart / Stop / PreToolUse / PostToolUse hooks | ✅ `~/.claude/settings.json` | ✅ 通过 plugin 安装（见下方"作为 plugin 安装"），跑 `${CLAUDE_PLUGIN_ROOT}/skills/.../scripts/` 里同一组脚本 |
| Autonomous mode（任务完成才停） | ✅ Stop hook 强制 | ✅ plugin 装上后等同 Claude Code |

### 工具名差异（影响很小）

SKILL.md 里写的是 Claude Code 工具名（`TaskCreate` / `AskUserQuestion` / `Agent`）。Codex（GPT-5）会理解意图，用自己等价工具（`plan_tool` / 询问 / 子任务）替代。**规则精神跨工具一致**——意图清晰、锁 scope、并行 agent、E2E、多遍扫漏洞等都生效。

### 关于已有的 ~/.codex/AGENTS.md

不冲突。AGENTS.md 是 Codex 全局基础规则，skill 是任务激活时的扩展。两者一起工作。

---

## 和市面上对比

简表（完整对比在 [`docs/competitors.md`](docs/competitors.md)）：

| 工具 | 类型 | 核心差异点 |
|---|---|---|
| **anchor** | 跨 CLI hook 包 | **唯一**：22 commands + 5 hooks + 277 防御 patterns + 跨项目记忆 closed loop + codex-as-judge auto-grader + 14 轮 audit |
| Praxis | 方法论 doc | 只有 prompt 规则，无 hook 强制 |
| HOTL (Human-on-the-Loop) | 工作流 | 强制人工 confirm，更慢但更安全 |
| Session Orchestrator | 跨 CLI runtime | 跨 Claude Code + Codex，但无 hook 防御 / 无记忆系统 |
| Aegis | 安全 audit | 偏向 audit phase，工作流弱 |
| Archcore | 跨 CLI | 跨 CLI 但无 anchor 的 hook + 记忆深度 |
| Antigravity Workspace | codebase 理解 | **互补**：Antigravity for *理解 codebase*，anchor for *改动时不犯错* |

anchor 的**重心**：**机械化强制**（hooks + auto-grading），不是方法论。多数同类只有"软规则"。

---

## 作为 plugin 安装 (推荐)

`./install.sh` 是文件复制安装——能让 skill + commands 在两边都生效，**hook 只装到 Claude Code 的 settings.json**。要让 Codex 也启用 hooks，把 repo 当 **plugin** 加载：

仓库根已经准备好了 plugin 元文件：

```
.claude-plugin/plugin.json    # Claude Code plugin manifest
.codex-plugin/plugin.json     # Codex CLI plugin manifest
hooks/hooks.json              # 4 hooks（用 ${CLAUDE_PLUGIN_ROOT} 引用脚本）
```

### Claude Code 用户：通过 marketplace

在 `~/.claude/settings.json` 里加：

```json
"extraKnownMarketplaces": {
  "anchor": {
    "source": {
      "source": "github",
      "repo": "biefan/anchor"
    }
  }
},
"enabledPlugins": {
  "anchor@anchor": true
}
```

下次启动 Claude Code 自动安装 + hooks.json 自动注册（不需要手动改 settings.json hooks 段）。

### Codex CLI 用户：通过 `codex plugin add`

```bash
codex plugin marketplace add github:biefan/anchor
codex plugin add anchor@anchor
```

启用后 Codex 也自动读 hooks/hooks.json，4 个 hook 都生效。

### 两种安装方式对比

| 项 | `./install.sh`（文件复制） | plugin 安装 |
|---|---|---|
| 安装方式 | 跑脚本，复制文件 | marketplace 注册 |
| Claude Code skill + commands | ✅ | ✅ |
| Codex skill + commands | ✅ | ✅ |
| Claude Code hooks | ✅ 写 settings.json | ✅ plugin 自动 |
| Codex hooks | ❌ | ✅ plugin 自动 |
| 升级 | `git pull && ./install.sh` | `codex plugin add --update` |
| 卸载 | `./uninstall.sh` | `codex plugin remove` |

新用户**推荐 plugin 安装**。已用 `install.sh` 装的可以保持现状，hooks 已经在 ~/.claude/settings.json 里跑着。

---

## 卸载

```bash
./uninstall.sh             # 默认：移除 home-scheme，保留 plugin 安装的
./uninstall.sh --all-hooks # 也清掉 plugin-scheme hook 条目
```

会移除 `~/.claude/skills/anchor/`、22 个 `~/.claude/commands/*.md`、`~/.codex/skills/` 下的所有 anchor skill 目录。`settings.json` 里 home-scheme 的 anchor hook 条目自动清掉（带 timestamp backup）。

**`~/.anchor/memory/` 不会被删** — 跨项目记忆是你的资产，由你自己决定要不要清。手动删：

```bash
rm -rf ~/.anchor/memory ~/.anchor/saved-tasks ~/.anchor/active-task.md
```

## 致谢与参考

设计参考：
- [anthropics/skills](https://github.com/anthropics/skills) 的官方 skill 范例（`skill-creator`、`claude-api`）
- [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) 的 `stop-review-gate` hook 实现
- Anthropic [claude-plugins-official/pr-review-toolkit](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit) 的 silent-failure-hunter / code-reviewer / code-simplifier 等 6 个 PR review agents
- Anthropic [claude-plugins-official/code-modernization](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-modernization) 的 `security-auditor` agent

## License

MIT
