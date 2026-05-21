# Autonomous Mode：任务完成才停 + 遇阻自主推进

## 是什么

启用 autonomous mode 后，efficient-coding skill 进入"长跑模式"：
- **任务清单未清空前不停**——Stop hook 会拦截，让你继续推进
- **遇到障碍自主排查**——不动不动就停下问用户
- **真卡死才报告**——按"观察 → 假设 → 验证"穷尽 3 轮假设仍无进展才停

## 怎么启用 / 关闭

```bash
# 启用
touch ~/.claude/.efficient-coding-autonomous

# 关闭
rm ~/.claude/.efficient-coding-autonomous
```

**默认关闭**。autonomous 是工程化模式，不适合所有场景：
- 适合：用户给一个完整任务后想要"完成才停"，比如"做一个用户头像上传功能"
- 不适合：探索性对话、需要边做边商量的决策、用户在场实时盯着

## 工作流（启用后）

### 1. 开工前 — 锁 scope

每个新任务**必须** `TaskCreate` 把用户原话当锚点，拆 3-7 个子 task。这是 Stop hook 的判断依据——没有 task list = 自治模式无法工作。

### 2. 推进中 — 持续干

- 完成一个 task → `TaskUpdate` 标 `completed` → 自动看下一个
- 中途遇到问题 → **不要立刻停**，按工作法处理：
  1. **观察**：精确描述发生了什么（错误信息、复现步骤）
  2. **假设**：提一个能解释现象的假设
  3. **验证**：设计最小实验证伪/证实它
  4. 证伪 → 换假设回 1；证实 → 修，继续下一个 task
- 遇到 task list 外的新需求 → 加成新 task，**不顺手做**
- 跨阶段了（调研完 → 改动 → E2E）→ 主动汇报进度（不停，只汇报）

### 3. 遇到真卡死 — 才停下报告

什么算"真卡死"：
- 穷尽 3 轮假设-验证仍无进展
- 需要外部信息/凭证/权限，环境内拿不到
- 走到岔路口，两种实现的影响范围用户必须决策
- 涉及"高代价动作"（删数据、push 生产、改 schema）

报告格式（停下时必须这么写）：
```
我卡在 task #N：
- 我做了：A、B、C
- 我看到：D、E
- 我的假设是 X，验证发现 Y 不符
- 我需要：决策 Z 或 信息 W
```

### 4. 任务完成 — Stop hook 放行

所有 task 都 `completed` 后，Stop hook 检查通过，可以正常 stop。

## Stop hook 拦截规则

hook 脚本 (`scripts/stop-self-check.sh`) 检查：

| 条件 | 动作 |
|---|---|
| `~/.claude/.efficient-coding-autonomous` 不存在 | 跳过检查，正常 stop |
| 文件存在 + task list 有 pending/in_progress | **block** stop，让 Claude 继续 |
| 文件存在 + task list 全 completed | 允许 stop |
| 没有任何 task list（用户没问代码任务）| 允许 stop |

## 防卡死兜底

如果 Stop hook 反复 block 但 Claude 真的推不动了：
- 用户随时可以 `rm ~/.claude/.efficient-coding-autonomous` 关掉
- 或者强制结束 session
- hook 脚本本身有 timeout 5 秒，hook 异常会自动放行（不会卡死永远）

## 与 /loop 的对比

| | autonomous mode | /loop |
|---|---|---|
| 触发 | Stop 时 hook 拦截 | 主动启用循环 |
| 范围 | 当前 task list | 一个固定 prompt 反复跑 |
| 停止 | 任务清空 | 用户中止 |
| 适用 | 一次性大任务"做完为止" | 周期性后台任务 |

需要"做完一个完整任务"用 autonomous；需要"每 5 分钟检查一次 X"用 `/loop`。

## 反模式

- **没有 task list 就开 autonomous** → hook 无判断依据，会过早放行 / 阻塞混乱
- **task 描述太模糊**（"看看 X"）→ 无法判断是否完成
- **autonomous 下随便加新 task** → 一直堆下去停不下来，要严守 scope，新发现先报告让用户决定
- **autonomous 下还频繁问用户** → 违背设计意图，应该自主推进
