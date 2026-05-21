---
description: 引导写一条踩坑记录到当前工作目录的 CLAUDE.md。Use after fixing any non-trivial bug (>5min to locate, surprising root cause, library quirk, concurrency issue).
argument-hint: "[bug 一句话标题，可选]"
---

按 `anchor` skill 的"犯错和修复后：把教训写回项目 CLAUDE.md"规则执行。

完整模板参考：`~/.claude/skills/anchor/references/pitfall-template.md`

步骤：

1. **检查 `./CLAUDE.md`**：
   - 不存在 → 创建，开头写一句项目简介
   - 存在 → 找 `## 踩坑记录` / `## Known Pitfalls` / `## Lessons Learned` 章节，没有就在文件末尾追加 `## 踩坑记录`

2. **填模板**（每条 3-5 行，按时间倒序——新条目放章节最上）：

```markdown
### [标题，用 $ARGUMENTS 或前文对话提取] (YYYY-MM-DD)
- **现象**：观察到什么
- **根因**：实际是什么
- **修复**：怎么改的 / `file:line`
- **教训**：下次遇到 X 类问题先检查 Y
```

3. **优先从对话上下文提取**——如果用户已经在前面讲清楚了现象/根因/修复，直接填入，不要再问。只有信息真的缺才问。

4. **写完后告诉用户**："已把踩坑记录追加到 `./CLAUDE.md`。"

判断标准（不达标就跳过，告诉用户为啥不写）：6 个月后的自己看到这条会感谢现在的自己——值得写。
- 写：花 >5 min 定位 / "以为是 A 实际是 B" / 库非直觉行为 / 并发时序 / 测试通过但生产挂 / 反复踩过 2+ 次
- 不写：typo / 格式 / 通用编程常识 / 一次性偶发
