# coding-discipline

详细参考：**动手时的纪律** — 只改要改的 / 显式胜紧凑 / 信任契约 / 并行调用工具。

SKILL.md 核心规则 #4（最小正确改动）的展开。

## 只改要改的

不顺手做这些：
- 重构无关函数
- 调整 import 顺序、改格式、统一命名
- 添加"以备将来"的参数 / 抽象层 / 配置项
- 写没有真实触发场景的 try/except、fallback、retry

每一处无关改动都是：
- PR review 负担（reviewer 要花时间确认是不是你 intend）
- git blame 噪音（未来 debugger 找不到真正提交人）
- 潜伏的回归风险（你没测，但改了行为）

修 bug 就只改 bug。重构是单独的任务，**不顺手做**。

## 显式 > 紧凑

"最小改动"不等于"代码越少越好"。**不要**为了少几行写：
- 嵌套三元
- dense one-liner
- 删掉有用的中间变量

3 个 `if/else` 的可读性远超 1 个嵌套三元。**清晰胜过省行数**。

## 信任已有保证

只在**系统边界**做验证：
- 用户输入
- 外部 API 返回
- 跨进程 / 跨服务消息
- 文件 IO

框架契约保证的（如 Express middleware 已 `req.user` 非空、Django auth_required decorator 已验过）→ 不要重复 check。重复验证 = 噪音。

## 并行调用工具

读三个不相关的文件 → 同一条消息里发三个 Read。
跑独立的 grep / build / lint → 同一条消息里并行。

只有当 B 的参数依赖 A 的结果时才串行。

## 反模式

- **"既然在这了，顺手把 X 也改了"** → 不顺手，一次一件事
- **"加点 try/except 防万一"** → 不防，无法发生的场景不写 fallback
- **"为了未来扩展加个参数 / 抽象层"** → 不加，YAGNI
- **"自己 grep 三遍找完就好，不用 Explore agent"** → 广搜场景派 agent
