---
description: 扫本会话改动的文件，找 dead code / debug print / 未用 import / 过期 TODO 等收尾杂物。Use right before /done or /ship to ship clean code.
argument-hint: "[range, default HEAD or use 'all' for all changed files]"
---

扫**改动过的文件**（不是全仓库），找收尾杂物。只**报告**，不自动改——用户决定每条要不要清。

### 1. 拿改动文件清单

```bash
git diff --name-only HEAD 2>/dev/null
# 或 staged + unstaged 都看：
git diff --name-only HEAD; git diff --cached --name-only
```

`$ARGUMENTS=all` → 跑 `git ls-files | xargs` 全仓库（慢 + 噪音多，不推荐）

按文件类型分桶，准备走扫描。

### 2. 按语言扫各类杂物

**Python (`*.py`)**：

```bash
# debug print
grep -n 'print(' <file>
# pdb
grep -n 'import pdb\|pdb.set_trace()\|breakpoint()' <file>
# unused imports (用 ruff/pyflakes)
ruff check --select F401 <file> 2>/dev/null || pyflakes <file> | grep 'unused'
# TODO/FIXME
grep -nE 'TODO|FIXME|XXX|HACK' <file>
```

**JavaScript/TypeScript (`*.js`, `*.ts`, `*.jsx`, `*.tsx`)**：

```bash
# debug
grep -nE 'console\.(log|debug|info)' <file>
# debugger
grep -n 'debugger;' <file>
# unused (用 eslint)
eslint --no-eslintrc --rule 'no-unused-vars:error' <file> 2>/dev/null
# TODO
grep -nE '//\s*(TODO|FIXME|XXX|HACK)' <file>
```

**Go (`*.go`)**：

```bash
# debug
grep -nE 'fmt\.Println|fmt\.Printf' <file>  # 注意：业务里的 Println 也会命中，让用户区分
# TODO
grep -nE '// (TODO|FIXME)' <file>
# Unused (用 go vet / staticcheck)
go vet <file> 2>&1
```

**Rust (`*.rs`)**：

```bash
grep -nE 'println!|dbg!\(|todo!\(\)|unimplemented!\(\)' <file>
grep -nE '// (TODO|FIXME)' <file>
cargo clippy --message-format=short -- -W unused 2>/dev/null
```

**Shell (`*.sh`)**：

```bash
grep -nE 'echo .*DEBUG|echo .*\[debug\]' <file>
shellcheck -S info <file> 2>/dev/null | grep -E 'unused|never'
```

### 3. 报告分类

按 severity 列：

**🔴 必清**（明确是调试遗留 / 死代码）：
- `path/to/file.py:42  print("DEBUG:", x)`
- `path/to/file.ts:88  debugger;`
- `path/to/file.go:120  fmt.Println("temp check")`

**🟡 review**（可能故意保留，可能要清）：
- TODO/FIXME 行
- unused import 警告（ruff/eslint 可能有 false positive）
- dead branches

**🟢 FYI**：
- 注释里的 `// for debugging` / `# temp` 等标记
- 大量空行

### 4. 一句话 verdict + 推荐动作

- "✅ 没找到明显杂物，可以 /done 收尾"
- "⚠️ 找到 N 处必清 + M 处 review。Clean before /ship"
- "🔴 大量调试代码（>10 处）—— 应该是忘了清，建议过一遍"

**清的时候**：用户决定逐条改 / 跑 formatter 自动清 / 标 `// keep` 注释忽略它。

### 5. 不做的事

- ❌ 不自动改文件（这是只读扫描）
- ❌ 不阻塞 /done 流程（这是辅助命令）
- ❌ 不警告"我看不懂这个函数"——本命令只看 lint 类杂物，不评价架构
- ❌ 不扫 `.git/` / `node_modules/` / `vendor/` / `target/` 等生成目录
