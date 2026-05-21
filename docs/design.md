# 设计原则

## 核心八条（任何时候被打断都回这里）

1. **意图清晰才开工**（含糊就问，不二选一兜底）
2. **任务范围用 `TaskCreate` 锁住**（用户原话当第一条 task）
3. **先读项目契约**（`CLAUDE.md` / `AGENTS.md`）
4. **最小正确改动**（显式 > 紧凑）
5. **能派 agent 就派，能并行就并行**
6. **审查看情况调 codex**（trivial 跳过，复杂 / 安全 / 大改必跑）
7. **踩坑必须回写**当前工作目录的 `CLAUDE.md`（+ 自动 sync 跨项目）
8. **遇到 topic 先 `/recall`** ⭐（SessionStart 注入 memory index → 用户提及 matching topic 时先拉过去经验再答）

每条详解见 [`skills/anchor/SKILL.md`](../skills/anchor/SKILL.md) + `skills/anchor/references/`。

## 防偏题三招

- **TaskCreate 锁 scope**：用户原话当第一条 task 锚住
- **偏题刹车**：每完成 1 task 看下一步，发现不在 list 上就停
- **新事项加新 task**：不顺手做，让用户决定

## 防记忆衰减（v1.7+ 跨 session）

- **关键规则前置** SKILL.md 顶部（auto-compact 保留前 5000 token）
- **task list 是外置记忆**（不被 compact）
- **`~/.anchor/active-task.md`** 跨 session 续接（branch / milestone history / open questions）
- **PreCompact hook** 在 auto-compact 前提示 `/save` + 自动 fallback
- **长任务主动 re-invoke** `/ec` 恢复完整内容
- **`/lean on`** 显式 token-saving mode（节省 ~900 token/session）

## 跨项目记忆系统（v1.8+ 真的记得住）

```
[写] /pit /decide /remember /snapshot
   ↓ 写入 ~/.anchor/memory/<category>/<project>/
[索引] SessionStart 自动列出本项目 memory titles
   ↓
[反射] SKILL.md 规则 #8: 用户提 matching topic 时先 /recall
   ↓
[读] /recall <keyword> 拉完整内容
```

之前缺中间 2 段（**索引 + 反射**），所以 memory 是 write-only。v1.9.0 起 closed loop。

### 7 种 memory category

| 类型 | 写入命令 | 文件位置 | 自动 inject? |
|---|---|---|---|
| Pitfall | `/pit` 自动 sync | `~/.anchor/memory/pitfalls/<project>/` | 索引在 SessionStart |
| Decision | `/decide` | `~/.anchor/memory/decisions/<project>/` | 索引在 SessionStart |
| Fact | `/remember fact ...` | `~/.anchor/memory/facts/<project>/` | 索引在 SessionStart |
| Preference | `/remember pref ...` | `~/.anchor/memory/preferences.md` | **全文 auto-inject** |
| TODO | `/remember todo ...` | `~/.anchor/memory/todos.md` | 不自动 |
| Snapshot | `/snapshot <label>` | `~/.anchor/memory/snapshots/<project>/` | 不自动 |
| Saved task | `/save <label>` | `~/.anchor/saved-tasks/<label>.md` | 不自动 |

## 自治模式（autonomous mode）

```bash
touch ~/.claude/.efficient-coding-autonomous     # ON
rm ~/.claude/.efficient-coding-autonomous        # OFF（默认）
```

- ON：Stop hook 检查 task list 未完成项就 `block`，让 Claude 继续
- 遇阻按"**观察 → 假设 → 验证**"自主推进，穷尽 3 轮才停下报告
- PreCompact + Stop hook 自动 save 到 `~/.anchor/saved-tasks/auto-*.md`（GC 保留 20 个）

详细协议见 [`skills/anchor/references/autonomous-mode.md`](../skills/anchor/references/autonomous-mode.md)。

## 两层防线

| 层 | 机制 | 例子 |
|---|---|---|
| **软** | SKILL.md 写明工作流，模型主动遵循 | 核心八条 + 反模式 list |
| **硬** | 5 个 hooks 在关键时机自动触发 | Stop block / PreToolUse 277 patterns / PostToolUse lint |

软规则可被忽略，硬约束做不到。两层结合 = 大概率走对路。

## 跨 CLI 适配

详见 [`docs/codex.md`](codex.md)。

## 进一步阅读

- [`skills/anchor/references/intent-and-recon.md`](../skills/anchor/references/intent-and-recon.md) — 规则 #1 详解
- [`skills/anchor/references/coding-discipline.md`](../skills/anchor/references/coding-discipline.md) — 规则 #4 详解
- [`skills/anchor/references/e2e-validation.md`](../skills/anchor/references/e2e-validation.md) — 完工标准
- [`skills/anchor/references/codex-review-when.md`](../skills/anchor/references/codex-review-when.md) — 规则 #6 详解
- [`skills/anchor/references/debugging-and-risks.md`](../skills/anchor/references/debugging-and-risks.md) — 卡住 + 高代价动作
- [`skills/anchor/references/pitfall-template.md`](../skills/anchor/references/pitfall-template.md) — 踩坑写法
- [`skills/anchor/references/vuln-checklist.md`](../skills/anchor/references/vuln-checklist.md) — 漏洞扫描清单
- [`skills/anchor/references/multi-agent-recipes.md`](../skills/anchor/references/multi-agent-recipes.md) — 并行 agent
- [`skills/anchor/references/autonomous-mode.md`](../skills/anchor/references/autonomous-mode.md) — 自治模式协议
- [`skills/anchor/references/multi-cli-adapters.md`](../skills/anchor/references/multi-cli-adapters.md) — 跨 CLI 适配
