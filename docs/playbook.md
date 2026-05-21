# anchor playbook — 实战 walkthrough

5 个典型场景，每个 15 分钟内能跟着走完。所有命令假设 anchor 已 install（`./install.sh`），Claude Code 或 Codex CLI 在用。

---

## Scenario 1 — 新人接入一个不认识的项目（5-10 min）

**情境**：你刚 clone 一个 repo，需要在里面改东西，但项目没 `CLAUDE.md`。

```bash
cd ~/some-new-project

# 1. 让 anchor 看项目类型 + 生成 CLAUDE.md 骨架
/init-claude-md

# anchor 会自动识别项目类型（web-app / library / cli-tool / data-pipeline）
# 用对应 template 创建 CLAUDE.md，把识别到的实际语言/框架/入口路径填实
# 没识别出来的留 TODO，等你补
```

输出长这样：

```
✓ Created ./CLAUDE.md (123 lines)
  - Template: web-app (detected Express + Prisma + PostgreSQL)
  - 侦察填实: 架构概览、入口路径、Conventions(命名), Testing(命令), Setup
  - 待补: API 约定、安全注意细节、踩坑记录（空）
  
Tip: 修非平凡 bug 后用 /pit 追加踩坑记录
```

接下来开始干活：

```bash
# 2. 锁住第一个任务的 scope（不偏题）
/lock 给 task API 加分页 ?page=N&per_page=M

# anchor 会 TaskCreate("给 task API 加分页 ?page=N&per_page=M") 作为第一条 task
# 然后引导拆 subtasks
```

---

## Scenario 2 — 长 refactor 不偏题（30-60 min 任务）

**情境**：要把一个 1500 行的服务拆成 6 个职责清晰的模块。Refactor 中段容易"顺手优化别的"。

```bash
# 1. 锁 scope
/lock 把 src/order-service.ts 拆成 6 个模块 (parse/validate/price/persist/notify/audit)，行为完全保留

# anchor 把"用户原话"作为第一条 task，然后引导你拆：
#   1.1 写 snapshot tests 覆盖现有行为
#   1.2 让旧实现通过这些 tests
#   1.3 拆 parse 模块 + tests 仍过
#   1.4 拆 validate 模块 + tests 仍过
#   ... 重复 6 个模块

# 2. 启动 autonomous mode（"做完才停"模式）
touch ~/.claude/.efficient-coding-autonomous

# 3. 任 Claude 自己跑
# Stop hook 会拦：每完成一个子任务就检查 task list 还有没有 pending，有就继续干

# 4. 出门吃饭 / 开会，回来看进展
/status
# 输出含 task list 进度 + autonomous on/off + 最近 7 天 hook 触发统计

# 5. 干完，复盘
/recap
# 列出已做 / 剩余 / 岔路 / 需要决策的点

# 6. 收尾
/done
# 跑 done-checklist：lint + E2E + codex review (>50 行变化时强制) + 引导写 /pit

# 7. 关闭 autonomous mode
rm ~/.claude/.efficient-coding-autonomous
```

**如果中途卡住了**：anchor SKILL.md 的 "观察 → 假设 → 验证" 协议 — Claude 写出"观察到 X，假设是 Y，验证方法 Z"，跑验证，回 step 1。3 轮自己没解开才报 blocker。

---

## Scenario 3 — 安全审计（pre-merge / pre-release）

**情境**：要在合 PR 前对 changes 做安全 review。

```bash
# 1. 先看改了什么
/diff
# 输出改动规模 + 命中敏感关键词 + 可能引入的回归类别

# 2. 多遍扫漏洞（anchor SKILL.md "多遍扫，扫到为止"）
/scan
# 跑第一遍：grep 反模式 + SAST tools

/scan src/auth
# 跑下一遍：聚焦 auth 子目录，更深扫

# 反复跑 /scan，每次换 lens（pattern → 数据流 → 跨文件 → codex 交叉）
# 直到连续两遍只 surface 已知问题，停

# 3. 让 codex 做 adversarial review
/codex:review

# 4. 修了之后 cleanup
/cleanup
# 扫本会话改动的文件，找 dead code / debug print / 未用 import

# 5. 收尾
/done
# 强制 codex review（因为改动大）+ 引导 CLAUDE.md 写回
```

---

## Scenario 4 — 多 agent 并行（独立子任务）

**情境**：4 个独立子任务（前端 / 后端 / migration / docs），串行做太慢。

```
"帮我做这 4 件事：(1) 加 React 组件 X，(2) 加 API endpoint，(3) DB migration 加 column，(4) 写 README 这个 feature。"
```

Claude 会在**一条消息**里并行 4 个 Agent：

```
[同一条消息内 4 个 Agent tool call:]
- Agent: 在 src/components/ 加 X 组件
- Agent: 在 src/api/ 加 endpoint
- Agent: 在 prisma/migrations/ 生成 migration
- Agent: 改 README.md 这个 feature 章节
```

4 个并行跑，每个独立 context，结果一起回来。Claude 主线 merge 后向用户报告。

**关键**：anchor SKILL.md 默认推**并行**子任务派 agent。串行干 = 三倍 wall-clock，是 anchor "防偏题"反模式之一。

---

## Scenario 5 — 长任务跨 session 续接

**情境**：refactor 干到一半，要去开会 / 下班，task list 还有 5 个 pending。

```bash
# 收工前
/save end-of-day-refactor

# anchor 会把当前 task list dump 到 ~/.anchor/saved-tasks/end-of-day-refactor.md
# 含每个 task 的 subject / description / status
# 不修改当前 session 的 task list（只是 cp）
```

**第二天 / 重新开 session**：

```bash
cd ~/that-same-project

# 续上
/resume end-of-day-refactor
# 或者不带 label，列出所有 saved files 让你选

# anchor 会:
# 1. Read ~/.anchor/saved-tasks/end-of-day-refactor.md
# 2. 显示要 resume 的 tasks 给你看
# 3. 等你 "yes / 续上"
# 4. 在当前 session 用 TaskCreate 重建（默认跳过已 completed 的）

# 然后继续干
/next  # 看下一步是什么，标 in_progress
```

**典型 save labels**：
- `/save before-compact` — 担心 long compact 丢上下文
- `/save end-of-day-X` — 收工时
- `/save approach-a` — 测试方向 A，开 b session 测 approach-b
- `/save before-experiment` — 改大事之前的安全点

---

## 报告 / 复盘

```bash
# 当前 session
/status            # autonomous mode + task progress + hook 7-day stats
/cost              # 当前 session token / 时长 / 估算 cost

# 跨 session 聚合
/report            # 默认最近 30 天
/report 7          # 本周
/report 90         # 本季度
```

**典型用法**：
- 每周五 `/report 7` 看本周 anchor 拦了哪些惯性操作 → 调整下周用法
- 月初 `/report 30` 看趋势：哪些 pattern 越来越频繁 → 是否需要新规则
- 季度 review `/report 90` 给团队看：anchor 在什么场景救了多少次

---

## "我刚开始用 anchor，最简流程？"

如果你只想用 anchor 的核心规则 + autonomous mode，**4 个命令足够**：

```bash
/lock <user-original-request>   # 锁 scope
# (干活)
/pit <bug 简述>                 # 修完 bug 写回 CLAUDE.md
/done                           # 收尾 checklist
```

剩下的命令（`/scan` `/cost` `/report` 等）按需要再学。
