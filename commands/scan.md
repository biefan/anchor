---
description: 漏洞扫描深入挖一遍——按 efficient-coding skill 的多遍扫方法论再扫一轮。Use when initial vuln scan finds 0 or few issues, or before declaring a security audit complete.
argument-hint: "[可选：聚焦的子目录或语言，如 src/api/ 或 python]"
---

按 `efficient-coding` skill 的"漏洞扫描：多遍扫，扫到为止"方法论深扫一轮。

详细 grep / 工具命令 / coverage checklist 参考：
`~/.claude/skills/efficient-coding/references/vuln-checklist.md`

执行：

1. **确定本轮 lens**（如果不知道现在是第几遍，回头看 task list 或对话历史决定）：
   - **第 1 遍**：模式 grep（硬编码 secret / `eval(` / 广 catch / SQL 拼接 / `shell=True` / `dangerouslySetInnerHTML` / `os.system` / debug 开着）+ SAST 工具（npm/pip/cargo audit、bandit、gosec、semgrep）
   - **第 2 遍**：数据流追踪——每个用户可控输入追到敏感 sink（SQL/shell/文件/反序列化/模板/URL/日志），路径上每个变换点检查验证、逃逸、授权
   - **第 3 遍**：跨文件 / 跨抽象——调用方 vs 实现、基类 vs 子类、配置/IaC/CI 里的 secret/permission/network rule
   - **第 4 遍**：派 `/codex:adversarial-review` 或 `/security-review` 做交叉验证，告诉它你已发现什么让它找你没发现的

2. **派 Explore agent**（broad 场景）或自己干（已知文件）执行本轮 lens。范围限在 `$ARGUMENTS`（如为空则全仓库）。

3. **对照 references/vuln-checklist.md** 的 coverage list 标出还没扫到的项。

4. **报告**（按这个结构）：
   ```
   本轮（第 N 遍，lens: <数据流追踪>）扫描结果：
   - 新发现 finding：[按 ID | Severity | file:line | Exploit(1句) | Fix 格式]
   - 已扫 coverage：[...]
   - 还没扫的 coverage：[...]
   - 建议下一遍 lens：[...]
   ```

5. **何时停**：
   - 跑完前 3 遍 + 一次 codex 交叉 + 连续两遍只 surface 已知问题 + 满足 coverage checklist 适用项 → 报告"扫描完成"
   - 否则继续——只跑一遍说"扫完了"是错的

**重要**：本命令只扫和报告，**不直接修漏洞**——修要单独的 task 走 efficient-coding 主流程（包括踩坑回写 CLAUDE.md）。
