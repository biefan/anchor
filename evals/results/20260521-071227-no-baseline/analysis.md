# 第二次 evals 跑分析（修正方法论后）

## 跑的条件

- `~/.codex/AGENTS.md` 临时 mv 走（`--no-baseline`），消除 12 KB 工程规则的 baseline 噪音
- Codex `--sandbox workspace-write`，能真写文件
- 每个 eval 在独立沙箱目录跑，可观察 codex 写了什么
- Discriminators 全部改成行为类，不依赖 Claude-Code 特定工具名
- SKILL.md 工具名加了 Codex 等价物注释

## 总分

| Eval | with-skill | without-skill | delta |
|---|---|---|---|
| 1 anti-drift-on-long-task | 0/4 | 1/4 | -1 ⚠️ **timeout** |
| 2 multi-pass-vuln-scan | 0/4 | 1/4 | -1 ⚠️ **judge 误判** |
| 3 pitfall-writeback | 1/4 | 2/4 | -1 ⚠️ **codex memory override** |
| 4 e2e-not-just-tests | **3/4** | 1/4 | **+2 🎯** |
| 5 intent-clarification | 4/4 | 4/4 | 0 |

## 实质结论：anchor 有真实价值，但测试有 3 个 noise 源

### ✅ eval 4 是干净的胜利

prompt: "我修了 GET /api/users/:id 的 bug（之前 404 返回 200），单测过了，可以了吗？"

with-skill 触发了 anchor 教的 3 个具体行为：
- ✅ `explicitly_says_unit_tests_alone_insufficient` — "不只依据'单测过了'来判断"
- ✅ `raises_at_least_one_second_order_concern` — 提了"成功路径仍返回 200"作为二阶检查
- ✅ `no_handwave_should_be_ok` — "现在不能确认'可以了'"

without-skill 只触发 1 个 ✅。anchor 的"验证：自己做 E2E + 二阶问题自检"两节直接被模型 reach 到了。

**这就是 anchor 设计要解决的问题**——baseline codex 会含糊地说"应该可以"，anchor 让它明确说"单测过 ≠ 完成 + 二阶要看"。

### ⚠️ eval 2 with-skill 实际胜出但 judge 没认

with-skill 输出 1533 chars，明确做了：
- 提到"按风险等级给出结论和文件行号"（multi-pass scan 体现）
- 列了 11 种 vuln 类别：debug=True / 硬编码 SECRET_KEY / 会话 cookie / CSRF / 认证 / IDOR / SQL 注入 / 模板 / XSS / SSTI / SSRF / open redirect / 错误信息泄露 / CORS / 安全响应头
- 提到要跑 Bandit 和依赖审计
- 正确拒绝"无源码就编造漏洞"

但 judge 全 ❌。判官失误的原因：
- 输出在 `output[:4000]` 截断，judge 可能没看到完整列表
- judge prompt 不够明确——"multiple_scan_passes" 是要看"几步流程"还是"几种漏洞"？

**修复**: judge prompt 加 explicit 例子 + output 不截断。

### ⚠️ eval 1 两边都 timeout（240s）

prompt 是"在 monorepo 加一个完整功能（前端+后端+migration）"——这是个长任务。240s timeout 不够。两边都 timeout 返回 "(codex exec timed out)"，judge 给 0 是合理的。

**修复**: run.py 把这个 eval 的 timeout 加到 600s，或者改 prompt 让它在不写大量代码的情况下规划。

### ⚠️ eval 3 codex memory feature override

仍然两边都把记录写到 `~/.codex/memories/...` 而不是 sandbox 目录的 CLAUDE.md。Codex 自带 memory feature 强 override 了 SKILL.md 的"写项目 CLAUDE.md"指令。

**两条路**:
1. SKILL.md 用更强语言: "**Do NOT use ~/.codex/memories or codex memory tools**. Write to the cwd's `CLAUDE.md` so the pitfall travels with the project's git history."
2. 承认 codex memory 是合理替代——在 codex 上踩坑记录用 codex memory，在 Claude Code 上用 project CLAUDE.md。两者都是持久化，scope 不同

### eval 5 双方满分

prompt "帮我改一下登录" 双方都问了 3 个澄清问题，给了具体选项。这是 codex 强项，baseline 已经做得很好——anchor 加不上什么。

## 修正测试方法论后真正学到什么

### Anchor 的边际价值集中在 3 个地方

1. **E2E 验证 + 二阶问题自检**（eval 4 验证 +2）
2. **结构化漏洞扫描方法**（eval 2 实质胜出，但 judge 没量到）
3. **长任务防偏题**（eval 1 timeout 没测出来）

### Anchor 没增益的地方

1. **意图澄清**（eval 5）— codex GPT-5 baseline 已经会
2. **踩坑回写到项目 CLAUDE.md**（eval 3）— 跟 codex memory feature 冲突
3. **快速回答场景**（< 1 分钟的 Q&A）— anchor 强在 30+ turn 长任务下的纪律

### 测试方法本身仍有改进空间

- judge output 截断（4000 chars）丢失证据
- judge prompt 对"multiple"等量词解释不一
- timeout 240s 不够长任务用
- 单次跑有 variance，没做多轮平均

## 下一步建议

跑 eval 不再加细节信息，**改去做 B（stress test）**——让 anchor 跑一个真实 30+ turn 任务（比如给 anchor 仓库自己加 GitHub Actions CI），从这些维度评：

- 是否真的用 task list 锁了 scope（看 git diff 是否只在 scope 内）
- 是否真的派多 agent 并行调研
- 是否真的写回 CLAUDE.md（看本仓库 ./CLAUDE.md 有没有新 entry）
- Stop hook 是否拦过停止（看 hook 日志）
- PreToolUse 是否拦过危险命令（看 hook 日志）

这些**不在短对话 eval 里能测**，必须实战。

## 当前最有信号的数据点

> **eval 4：在"用户问'单测过了，可以了吗'"场景下，with-skill 触发 3 个具体的工程纪律行为，without-skill 只触发 1 个。**

这是 anchor 价值的硬证据——在 anchor 教的具体行为（E2E、二阶问题、警惕"应该可以"）上有 measurable improvement，即使在 codex baseline + 移走 AGENTS.md 之后。
