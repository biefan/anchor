# 多 Agent 并行 Recipes（实战 prompt 模板）

SKILL.md 讲了"能派就派 + 一条消息发多个"的原则；这里是几个常用场景的具体 prompt 模板，复制即可用。

## Recipe 1：调研型（迁移 / 接入新依赖 / 学新技术）

**场景**：要把 OldAuth 迁移到新 SDK；要接入第三方支付；要了解某个开源项目能不能用。

**派 3 个 Explore agent 并行**（同一条消息）：

```
Agent: Explore (breadth: "medium")
任务：找仓库里所有用到 OldAuth 的地方。我需要：
1. 调用点的文件:行号清单
2. OldAuth 暴露的 public API（函数 / 类 / 类型）有哪些被用了
3. 每个调用点的形态（同步/异步？返回值怎么用？错误怎么处理？）
不要建议方案。只给现状清单。

Agent: Explore (breadth: "medium")
任务：从 NewAuth SDK 的官方文档 / repo 找出：
1. 与 OldAuth 概念对应的 NewAuth API
2. 迁移指南（如果存在）
3. 已知的 breaking change
URL 我不确定，先搜 `<sdk-name> migration guide` / `<sdk-name> v2 changes`。
不要写迁移代码，只给映射表和 gotcha 列表。

Agent: Plan
任务：基于以下假设，给出从 OldAuth 迁移到 NewAuth 的分阶段方案：
- 假设 1：要保持 API 兼容（外部调用方不改）
- 假设 2：先做新版灰度，老版逐步淘汰
分阶段，每阶段可独立部署可回滚。不写代码，只给步骤 + 风险点。
```

**为什么并行**：三个任务互相独立（一个查现状、一个查目标、一个给方案）。结果同时回来，模型一次性看全图。

---

## Recipe 2：Debug 型（生产/测试出现奇怪现象）

**场景**：某个 endpoint 偶发 500；某个测试在 CI 上偶发失败；某个数据偶尔被覆盖。

**派 2-3 个 Explore 同时挖**：

```
Agent: Explore (breadth: "quick")
任务：从最近 100 条相关日志（路径 `logs/...`）grep 出 endpoint X 的错误。我要：
1. 错误的具体形态（异常类型、堆栈、请求参数）
2. 错误的时间分布（集中爆发还是均匀稀疏）
3. 错误请求的共同特征（特定 user_id？特定 payload size？）
只给数据，不给猜测。

Agent: Explore (breadth: "medium")
任务：从代码层面分析 endpoint X 的可能错误路径：
1. 这个 endpoint 调了哪些下游服务/DB？
2. 哪些点有 try/catch 但没有完整重 raise？
3. 有没有共享可变状态（全局变量、单例、cache）会被并发请求踩到？
读代码不写代码。

Agent: general-purpose
任务：基于这些观察提 3 个能解释现象的假设，每个假设给出"如何用最小实验证伪它"。
（注：这个在另外两个 agent 回来后再派，因为它依赖前面的结果）
```

**反例**：自己一个 grep 一个 grep 跑，跑完看一眼想下一步——三轮串行，浪费一倍时间。

---

## Recipe 3：大改重构型（提一个大功能、大重命名、大架构调整）

**场景**：把 monolith 拆成两个服务；把回调改成 promise；把全局 logger 换实现。

**多 agent 分领域**（前端 / 后端 / infra / 测试 并行）：

```
Agent: Explore (breadth: "very thorough")
[前端范围]
任务：找前端代码里所有用到 logger 的地方（src/web/ 下）。给：
1. 文件:行号清单
2. 调用形态（logger.X 的 X 都用了哪些）
3. 是否有 wrapper / context-aware 用法
不要改代码。

Agent: Explore (breadth: "very thorough")
[后端范围]
任务：找后端 logger 用法（src/api/ + src/worker/ 下）。同上格式。

Agent: Explore (breadth: "medium")
[基础设施]
任务：找 logger 配置入口（config/ logger.*）、初始化代码、与第三方 log aggregator 的集成。

Agent: Explore (breadth: "medium")
[测试范围]
任务：找测试里 mock logger 的方式（spyOn / sinon / pytest-mock）。新 logger 上线后这些 mock 是否需要改？
```

四个 agent 一次发出，等四个都回来一起读，得到完整迁移地图，再决定怎么动手。

---

## Recipe 4：审查 / 扫描并行型

**场景**：刚改完一个 PR，要扫漏洞 + codex review + 跑测试。

**主线干别的 + 副线 agent 后台跑**：

```
[同一条消息]
- Bash run_in_background: npm run test:integration
- Bash run_in_background: semgrep --config=auto . > /tmp/semgrep.out
- Bash run_in_background: node /path/to/codex-companion.mjs review --background

主线：开始写 PR description / 写踩坑记录 / 改另一个文件
```

后台任务完成时自动通知。**不要 sleep poll**。

---

## Recipe 5：分头实现独立子功能

**场景**：用户提了一个功能，能拆成 3 个完全独立的小块（前端表单 / 后端 endpoint / migration 脚本）。

**派 3 个 general-purpose 并行**：

```
Agent: general-purpose
任务：在 src/web/UploadAvatar.tsx 加一个表单组件：
- props: { userId, onSuccess(url) }
- 上传 → 调 POST /api/users/:id/avatar → 回调
- UI 用现有的 <Form> + <FileInput>，参考 src/web/EditProfile.tsx 的样式
不要碰后端代码。

Agent: general-purpose
任务：在 src/api/users.ts 加 POST /api/users/:id/avatar：
- 接受 multipart/form-data
- 存到 S3 bucket "user-avatars"
- 把 URL 写回 users 表 avatar_url 字段
- 校验：图片 ≤ 5MB、jpeg/png/webp 之一
不要碰前端代码、不要碰 migration。

Agent: general-purpose
任务：在 migrations/ 加 migration 给 users 表加 avatar_url 字段（nullable text）。参考最近一次 migration 的格式（migrations/20260301_xxx.sql）。
```

**重要**：每个 agent 的"不要碰 X"明确边界——避免 3 个 agent 同时改同一个文件冲突。

---

## 通用 prompt 写法

每个 agent 的 prompt 应该包含：

1. **目标**：一句话说要什么产出
2. **范围**：明确文件/目录边界
3. **格式**：要 JSON / 清单 / 代码？
4. **边界**：明确**不要做**什么（防止它跑偏）
5. **背景**：必要的项目上下文（一两句）

**反模式**：派 agent 时只给"看看 X" / "处理一下 Y"——agent 不知道你要什么，浪费一次调用。

## 何时**不**用 agent

- 已知具体路径 / 文件 / 函数 → 自己 Read 更快
- 1-2 步的简单操作 → 直接干
- 需要紧密交互式协作（一边看用户反馈一边调） → 自己来

派 agent 的成本：上下文转移 + 启动延迟 + token。当查询足够具体时，自己干更便宜。
