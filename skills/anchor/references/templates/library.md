# <库名>

<一句话描述：解决的问题 + 目标用户。例如：A small, dependency-free HTTP retry helper for Python / TypeScript 端 Zod validator with great error messages>

## 架构概览

- **语言**：`<Python / TypeScript / Rust / Go>`
- **导出形态**：`<single function / class / module / multiple subexports>`
- **运行依赖**：`<列出运行时依赖；越少越好>`
- **开发依赖**：`<test runner, type checker, linter, doc gen>`
- **打包**：`<pyproject.toml / package.json / Cargo.toml>` 是 source of truth

## 关键路径

- 入口：`<src/index.ts or <pkg>/__init__.py or src/lib.rs>`
- 公共 API surface：`<导出哪些 — 函数 / class / 类型>`
- 私有 impl：`<src/internal/ or _private/ 命名约定>`
- 类型：`<index.d.ts (auto-gen) / py.typed marker / *.d.ts>`
- 测试：`<__tests__/ or tests/ 同层>`

## Conventions

- **公共 API breaking change** 在 minor 版本不允许（库的契约）
- 命名：`<camelCase 对外 / _snake_case 对内, etc>`
- 错误处理：`<抛 Error / 返回 Result / 命名 exception 类>`
- 文档：`<JSDoc / 详细 docstring / no-public-without-docstring>`
- semver：strict — patch/minor/major 区别清楚（不要混淆）

## Testing

```bash
# 单元
<npm test / pytest / cargo test>

# 类型 / lint
<npm run typecheck / mypy / cargo clippy>

# 兼容性矩阵（多 Python/Node 版本）
<tox / nox / .github/workflows/test.yml 跑哪些 version>

# Benchmark
<是否有，运行命令>
```

## Setup

```bash
<npm install / poetry install --with dev / cargo build>
```

## 发布流程

- bump version: `<pyproject.toml / package.json / Cargo.toml>`
- changelog：`<CHANGELOG.md 用 Keep a Changelog 格式>`
- tag: `git tag v<X.Y.Z> && git push --tags`
- 发布：`<npm publish / poetry publish / cargo publish>`
- GitHub Release：发 tag 后 `gh release create` 生成 release notes from CHANGELOG

## API 稳定承诺

- **公共 API**（在 `<src/index.ts or __init__.py>` exported）— semver 守护
- **`_*` / `internal/*`** — 内部 impl，**任何**版本可改

## 踩坑记录

<本节用 `/pit` 在每次修完非平凡 bug 后追加。>

(空)
