# 第一次 evals 跑分析

## 总分

| | with-skill | without-skill |
|---|---|---|
| 总分 | **8/19** | **9/19** |
| 触发率 | 42% | 47% |

数字上 without 略胜，但**这不是 anchor 没用，是测试方法本身有几个 bug**。

## 三大失真因素

### 1. 跑在 Codex 上 → discriminator 偏向 Claude Code 工具集失效

evals.json 的 discriminator 设计假设 Claude Code 运行时（有 `TaskCreate` / `Agent` / `AskUserQuestion` 工具）。但本次跑在 **Codex CLI** 上，这些工具 Codex 根本没有：

| Discriminator | 两边都 ❌ 的原因 |
|---|---|
| `is_task_list_used` (eval 1) | Codex 不暴露 TaskCreate tool 给短回答 |
| `subagent_count >= 2` (eval 1) | Codex 不像 Claude Code 那样命名 Agent tool |
| `uses_AskUserQuestion` (eval 5) | Codex 没 AskUserQuestion，问问题靠 prose |
| `real_curl_or_http_test_suggested` (eval 4) | Codex 在只读 sandbox 不主动建议 curl |

这些 ❌ **跟 anchor 装不装无关** —— 是 Codex 默认就触发不到。

### 2. 只读 sandbox 让 eval 3 (pitfall-writeback) 失效

两次跑 codex 都明说 "只读沙箱拦截了 `~/.codex/memories/extensions/.../` 写入"。两边都没真的写 CLAUDE.md，**`claude_md_created_or_appended` 注定 ❌**。

讽刺的是 **without-skill 在被拦截后反而把内容组织成更接近 4-field 模板的结构**（"项目: ... 文件: ... 修复方式: ... 经验: ..."），got ✅ on `four_field_structure_used`。with-skill 用了散文式表达，judge 没认。

### 3. Codex baseline + 你的 ~/.codex/AGENTS.md (12 KB) 已经很强

两个回答里都看到了 anchor 想要的行为：
- eval 2 (vuln-scan)：**两边**都"第 1 遍 / 第 2 遍 / 第 3 遍"多次扫
- eval 4 (e2e)：**两边**都没说"应该可以"，都提了二阶风险
- eval 5 (intent)：**两边**都问了 3 个澄清问题

说明 anchor 的"软规则"层面（问澄清 / 警惕含糊 / 多遍扫）**baseline 已经做了**。

## 关键洞察

### anchor 的边际价值在哪里

**不在**：
- 对话式 Q&A（baseline + AGENTS.md 已经够）
- 短任务（< 3 步的）

**在**：
- **结构化工作流**：TaskCreate 锁 scope、4-field 踩坑模板、多 agent 并行调研
- **长任务防偏题**：tool 输出意外不带跑、autonomous 自治
- **硬约束**：Stop hook 拦截 + PreToolUse 危险命令拦截

这些价值 **eval 这种"短回答"场景测不出**。要测它们得跑**实际长任务**：让 anchor 跑 30+ turn 的真功能开发，看是否真的不偏题、真的写回 CLAUDE.md、真的派多 agent。

### Codex baseline 强意味着什么

不是 anchor 没价值——是你的 **~/.codex/AGENTS.md 12KB 已经把基础工程纪律做到了**。anchor 在 Codex 上的真正价值可能是：
- 把 12KB 散文式规则压缩成**可执行的 7 条核心 + 触发明确的 commands**
- 提供**跨工具一致性**（Claude Code + Codex 共用同一份）
- 提供**硬约束**（Stop / PreToolUse hooks），不靠模型自觉

## 改进 evals 的建议

如果想拿到有信号的对比数据：

1. **Claude Code 跑**而不是 Codex —— discriminator 设计就是为 Claude Code 工具集准备的
2. **打开 `codex exec --full-auto`** 或 `--sandbox workspace-write` 让它能真写文件（eval 3）
3. **重写 discriminator**：把工具调用类（`uses_AskUserQuestion`）换成**行为类**（`explicitly_asks_at_least_one_question`）
4. **加一个真实长任务 stress test**：让 anchor 跑 30+ turn 的实际功能开发，事后看 CLAUDE.md 有没有踩坑记录、git diff 是否只改 task scope 内的文件、是否调用过多 agent
5. **降低 baseline**：临时 mv 走 `~/.codex/AGENTS.md` 同时跑 without-skill，看 anchor 在"空白 baseline"上是否有差

## 下一步建议

按价值-成本权衡：

- **A**（最划算）：先把 anchor 改进成 Codex 友好——把 SKILL.md 里的 `TaskCreate` 换成 "用 codex 的 plan tool 锁 scope"，让 Codex 真的能 reach 这些行为
- **B**：把 evals 重写一下，符合上面 4 点改进
- **C**：跑一个真实小项目实测，看长任务下 anchor 是否真的 anti-drift

这次"失败"的测试反倒最有信息量——证明在 Codex 上 anchor 的"对话纪律"部分被 baseline 覆盖了。anchor 的差异化得靠**长任务结构化**和**硬 hook**体现。
