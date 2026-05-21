---
description: 在当前工作目录创建 CLAUDE.md 骨架（项目无 CLAUDE.md 时用）。Use when entering a new project that has no project-level CLAUDE.md / AGENTS.md.
argument-hint: "[可选：项目一句话描述] 或 --template=<web-app|library|cli-tool|data-pipeline|default>"
---

在**当前工作目录**（不是 ~/.claude/）创建一个项目 CLAUDE.md 骨架。

### 步骤

1. **检查是否已存在**：
   - `./CLAUDE.md` 已存在 → 报告位置 + 现有章节列表，问用户是否要"补齐缺失章节"，**不要覆盖**已有内容
   - 不存在 → 继续

2. **判断项目类型 + 选 template**：
   - 如果 `$ARGUMENTS` 含 `--template=X` → 用指定 template
   - 否则**自动侦察**：
     - 有 `package.json` + Express/Django/Flask/Rails route 文件 → `web-app`
     - 有 `pyproject.toml`/`Cargo.toml`/`package.json` 但**没**入口 server → `library`
     - 有 `bin/` 或 `cmd/main.go` 或 cli framework imports → `cli-tool`
     - 有 `dags/` / `dbt/` / Airflow/Dagster imports → `data-pipeline`
     - 其它 → `default`
   - Templates 在 `~/.claude/skills/anchor/references/templates/`：
     - `web-app.md` — Express/Django/Flask/Rails/NextJS/FastAPI 类
     - `library.md` — npm/pip/cargo 发布的 library
     - `cli-tool.md` — Go/Rust/Python CLI 工具
     - `data-pipeline.md` — Airflow/Dagster/dbt ETL
     - `default.md` — 通用骨架

3. **快速侦察项目**：用 1 条命令同时跑（不要等结果再说话）：
   - `ls -la` 看顶层结构
   - 找语言（package.json / pyproject.toml / Cargo.toml / go.mod / pom.xml / Gemfile / composer.json）
   - 找入口（`grep -l "main\|app\|server\|entry"` 之类）
   - `git log --oneline -10` 看最近活动（如果是 git repo）

4. **写 `./CLAUDE.md`**，**复制 template 内容** + **基于侦察填实际值**（不要照搬 `<placeholders>`）：

```markdown
# <项目名>

<一句话描述：$ARGUMENTS 或基于侦察推断>

## 架构概览

<2-4 句话：技术栈、主要模块、对外接口形态>

## 关键路径

<3-5 行：入口在哪、core 逻辑在哪、配置在哪>

## Conventions

<按侦察到的语言列项目实际遵循的约定。读邻近文件归纳出来，不要写"应该用 X"——只写"这个项目用 X"。>

- 命名：<驼峰/下划线/横线？前缀？>
- import 顺序：<标准库/第三方/本地的顺序？分组？>
- 错误处理：<抛异常/返回 Result/log 形式？>
- logger：<用什么 logger 函数？>
- 测试位置：<__tests__ / tests/ / _test.go 同目录？>

(没读出来的项**不要瞎填**——留 TODO 或省略)

## Testing

<怎么跑 unit / integration / e2e？>

```bash
# unit
<command>

# integration
<command>
```

## Setup

<新成员/Claude 进来要做什么环境准备？依赖、env 文件、本地服务？>

## 踩坑记录

<本节用 `/pit` 在每次修完非平凡 bug 后追加。3-5 行/条：现象 + 根因 + 修复 + 教训。>

(空——按"6 个月后看到值得感谢现在的自己"标准追加)
```

5. **写完报告**：
   - 创建路径
   - 用了哪个 template（`web-app` / `library` / `cli-tool` / `data-pipeline` / `default`）
   - 哪些章节内容是基于侦察填的（"侦察填实"）
   - 哪些章节内容是骨架占位需要用户/未来追加（"待补"）
   - 提示：以后修非平凡 bug 用 `/pit` 追加到"踩坑记录"

### 不做

- 不覆盖已存在的 `./CLAUDE.md`
- 不基于猜测填具体技术细节（侦察不出来就留空，不要造）
- 不写超过 150 行的 CLAUDE.md 骨架——CLAUDE.md 是项目契约，不是文档汇编
