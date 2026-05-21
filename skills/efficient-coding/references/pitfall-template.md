# 踩坑记录模板（写进项目 CLAUDE.md）

## 标准模板（每条 3-5 行）

```markdown
### [一句话标题] (YYYY-MM-DD)
- **现象**：观察到什么
- **根因**：实际是什么
- **修复**：怎么改的 / `file:line`
- **教训**：下次遇到 X 类问题先检查 Y
```

## 章节组织

CLAUDE.md 里建议章节名（任选一个，保持一致）：
- `## 踩坑记录`
- `## Known Pitfalls`
- `## Lessons Learned`

按时间倒序（最新在上），便于读到最近的最重要。

## 不同类型的示例

### 依赖库非直觉行为

```markdown
### Redis pipeline 在 cluster 模式下不跨 slot (2026-05-21)
- **现象**：批量写 100 个 key，部分丢失，无报错
- **根因**：cluster 模式下 pipeline 命令必须 hash 到同 slot，跨 slot 命令被静默丢弃
- **修复**：用 `hashtag` 让 key 落同 slot，`cache/batch.ts:42`
- **教训**：Redis cluster 下批量操作前先检查 key 分布；"部分丢失无报错"先怀疑 slot
```

### 并发 / 时序问题

```markdown
### React useEffect 闭包捕获过期 state (2026-04-10)
- **现象**：按钮 onClick 拿到的 user.id 永远是首次渲染时的值
- **根因**：handler 在 useEffect 里定义但依赖数组没填 user.id，闭包捕获了过期 state
- **修复**：把 handler 改成 `useCallback` 加正确依赖，或用 `useRef` 存最新值，`Button.tsx:88`
- **教训**：useEffect 里的 callback 引用了 state 就要进依赖数组；ESLint react-hooks/exhaustive-deps 要开
```

### 平台 / 环境差异

```markdown
### macOS sed 与 GNU sed 的 -i 参数不兼容 (2026-03-15)
- **现象**：CI（Linux）通过，本地（macOS）跑同样 shell 脚本失败
- **根因**：`sed -i 's/a/b/' file` 在 GNU sed 是原地修改，BSD sed（macOS）需要 `-i ''`
- **修复**：脚本里改用 perl 或显式 backup 后缀 `sed -i.bak`，删除 .bak
- **教训**：跨平台 shell 脚本避免 sed -i；用 perl -pi 或显式中间文件
```

### "测试通过但生产挂了"

```markdown
### 单测 mock 了 Redis，但真实 Redis 拒绝大 key (2026-02-01)
- **现象**：单测 100% 通过，部署后写 5MB JSON 到 Redis 抛 PROTO_ERR
- **根因**：测试用了内存 mock，没复现 Redis 1MB 默认 value 上限
- **修复**：写入前 `JSON.stringify(...).length` 检查 + 拆分大对象，`storage/redis.ts:71`
- **教训**：critical path 的 IO 不要纯 mock，跑一遍真实 dependency 至少一次；mock 是隔离不是替代
```

### 框架 / 配置陷阱

```markdown
### Next.js dynamic import 在 SSR 时仍会执行模块顶层代码 (2026-01-22)
- **现象**：browser-only 库（用了 window）在 build 阶段炸
- **根因**：`dynamic(() => import('lib'))` 默认 ssr: true，模块的 top-level 仍在 server 跑
- **修复**：`dynamic(() => import('lib'), { ssr: false })`，`components/Map.tsx:5`
- **教训**：Next.js 的 dynamic import 默认仍 SSR；window/document 依赖必须 ssr: false
```

## 决策标准：写不写？

**写**：6 个月后的自己看到这条，能省 30 分钟排查时间。

**不写**：
- 通用编程常识（不是这个项目特有）
- typo / 格式
- 一次性偶发问题（不可复现）
- 你只是不熟悉但读了文档就明白的

## 写多深？

够"未来遇到时识别得出"就行——3-5 行。不要变成日记或博客。

如果一个坑需要 20 行才说清楚，把详细分析写到单独的设计文档，CLAUDE.md 里留一句索引："详见 `docs/redis-cluster-notes.md`"。

## 触发再写一次的信号

如果发现 CLAUDE.md 已有的某条踩坑记录**又被忽略了**（同一个坑再踩），不只是再写一条，而是：
1. 把那条置顶（移到章节最上）
2. 加一个 `(updated YYYY-MM-DD, hit N times)` 标记
3. 考虑是不是该写成 lint 规则或代码层 guard，让它无法再发生
