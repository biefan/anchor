# Evals — 量化 ec skill 是否真的有效

> 准备好的测试 prompt + with-skill / without-skill 跑法。用来证明（或证伪）skill 的价值。

## 测试场景（见 evals.json）

| ID | 名字 | 测什么 |
|---|---|---|
| 1 | anti-drift-on-long-task | 长任务下是否锁 scope + 并行 agent + 不偏题 + 真做 E2E |
| 2 | multi-pass-vuln-scan | 漏洞扫描是否多遍 + codex 交叉 + 给 exploit |
| 3 | pitfall-writeback | 踩坑是否回写 CLAUDE.md（四要素结构） |
| 4 | e2e-not-just-tests | 单测过后是否 push 用户做 E2E 而不是含糊"应该可以" |
| 5 | intent-clarification | 含糊需求是否先问 1-3 个关键问题 |

## 快速跑法（单测）

启用 ec skill 的环境里：

```bash
# 1. 起一个新 Claude Code session（确保 skill 加载）
# 2. 把 evals.json 里某条 prompt 字面输入
# 3. 观察是否符合 expected_behavior 和 discriminators
```

用同样的 prompt 跑两次：
- **with-skill**：你当前环境（~/.claude/skills/efficient-coding 已装）
- **without-skill**：临时移走 skill 跑同样的 prompt
  ```bash
  mv ~/.claude/skills/efficient-coding /tmp/ec-backup
  # 重启 Claude Code，跑同样的 prompt
  # 跑完恢复：mv /tmp/ec-backup ~/.claude/skills/efficient-coding
  ```

记录差异。

## 自动化跑法（subagent 批量）

如果你有 Claude Code 的子代理能力，可以让一个 agent 批量跑所有 5 个 prompt：

```
for each eval in evals.json:
  spawn Agent with the prompt
  collect: transcript, files-changed, did-task-list-exist, etc.
  score each discriminator
```

完整 eval-viewer 流程参考 Anthropic skill-creator 的 `eval-viewer/generate_review.py`：
- 见 `/root/.claude/plugins/marketplaces/anthropic-agent-skills/skills/skill-creator/`

## Discriminator 的含义

每个 eval 的 `discriminators` 列表是**可程序化检测**的指标。例如：

- `is_task_list_used`：transcript 里有 `TaskCreate` 调用
- `subagent_count >= 2`：transcript 里有 ≥2 个 Agent 调用
- `no_unrelated_changes`：git diff 范围限于 prompt 提到的目录
- `claude_md_created_or_appended`：测试结束后 ./CLAUDE.md 存在 + 含新条目
- `asks_question_before_acting`：transcript 里有 AskUserQuestion 调用且在任何 Edit/Write 之前
- `real_curl_or_http_test_suggested`：transcript 里出现 `curl http://` 或 `httpie` 调用
- `exploit_scenario_per_finding`：审计输出里每个 finding 有"攻击者怎么用"的一句话

实施这些检测可以 grep transcript（Claude Code 的 transcript_path 在 hook input 里有），或写一个 Python 脚本扫输出。

## 期待

预期 with-skill 在所有 5 个场景上比 baseline 至少**多触发 60%** 的 discriminator。如果某个场景没差距，要么是 prompt 太简单（任何模型都能做对），要么是 skill 那部分没生效——按 skill-creator 的"improve the skill"循环迭代。

## 已知局限

- 这 5 个场景偏"工程纪律"，没覆盖纯架构判断 / 算法设计
- discriminator 是程序化指标，捕捉不到"质量"维度（如改的代码是否优雅）—— 那部分需要人审
- 真实长任务 > 5 分钟，单条 eval 不能模拟">30 turn 后 skill 是否被 compact 掉"的场景；那要专门的长任务 stress 测试
