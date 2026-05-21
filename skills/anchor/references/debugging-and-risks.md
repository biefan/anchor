# debugging-and-risks

详细参考：**卡住时的协议** + **高代价动作的确认流程** — 两个 anchor 防灾难规则的展开。

## 卡住时：观察 → 假设 → 验证

调试是搞清楚"模型 vs 现实"哪里对不上，**不是"换姿势试试"**。

### 工作法

1. **观察**：现在到底发生了什么？精确描述——错误信息、复现步骤、最小输入
2. **假设**：基于观察，提出**一个**能解释现象的假设。**不要同时怀疑 5 件事**
3. **验证**：设计能**证伪**该假设的最小实验。能跑就跑，对照预期
4. **证伪了** → 观察新现象，回 step 1。**证实了** → 修复，写回 CLAUDE.md

### 禁止

- 跳 lint、跳测试、删错误日志、catch-and-ignore——把信号换成噪音
- 改 assertion 让测试"通过"而不改实现
- 循环里加 sleep 等问题"自己消失"
- 同时改 3 处希望"总有一处奏效"——错了你不知道是哪个修好的

### 修不动时

**先报告现状**：假设是 X，证据 Y 不符，需要 Z 信息——比硬塞猜测的 fix 更可信、更快得到帮助。

3 轮假设全证伪 → 报告 blocker，不要硬扛。

## 高代价动作：动手前先确认

这些动作做错代价远高于"先停下来问一句"：

### 不可逆操作

- 删文件 / 删分支
- `git reset --hard`、覆盖未提交改动
- `rm -rf`
- `drop table` / SQL DELETE 无 where
- 覆盖 production database / secret store

### 影响共享状态

- `git push` / `git push --force`
- 创建 / 合并 / 关闭 PR
- 发消息（Slack / Discord / email）
- 改生产数据
- 部署到 production / staging
- 修改 IAM / 权限 / 网络规则

### 影响别人

- 跨多文件且影响架构的改动
- 引入新依赖
- 改 CI / 改 build pipeline
- 改数据库 schema
- 改环境变量 / config
- 换包管理器（pnpm ↔ npm ↔ yarn 等）

### 第三方上传

- 把内容上传到 diagram 工具 / pastebin / gist
- 把代码 / log 贴到外部 LLM 服务
- 把 secret 不小心进入 search 索引

### 默认行为

**先说要做什么、为什么、影响范围，等用户确认**。

呼应项目契约：不主动 `git commit` / `push` / `branch` / `merge` / `rebase` / `tag`，除非用户明确要求。**永远不 `--no-verify`**。

## 反模式

- **"hook 失败就 `--no-verify`"** → 永远不要
- **"任务挺急的，我直接 push 算了"** → 该等的确认必须等
