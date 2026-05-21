# <CLI 名>

<一句话描述：解决什么操作流。例如：fast project-aware grep with .gitignore respect / git workflow accelerator for team conventional commits>

## 架构概览

- **语言**：`<Go / Rust / Python / Node / Bash>`
- **runtime 依赖**：`<理想 0 个；列出必需的 system tools>`
- **目标平台**：`<Linux / macOS / Windows / WSL>`
- **distribution**：`<homebrew / npm global / pip / cargo install / 二进制 release>`

## 关键路径

- 入口：`<cmd/main.go or src/main.rs or bin/<name> or cli.py>:<lineno>`
- subcommand router：`<src/commands/ or cobra/clap 配置>`
- 用户 config：`<~/.<name>/config.toml 或 $XDG_CONFIG_HOME/<name>/>`
- 输出格式：`<plaintext / table / json --output flag>`
- shell completion：`<bash_completion / zsh / fish — 装在哪里>`

## Conventions

- 命名：`<my-cli command sub-command>` 模式（kebab-case subcommands）
- exit codes：
  - 0 — success
  - 1 — runtime error  
  - 2 — usage error (bad flags)
  - <其它项目专用 code 列出来>
- 输出：
  - 主输出走 stdout（pipeable）
  - 状态 / 进度走 stderr（不混入 pipe）
  - 颜色：默认 detect tty，`--color=never` / `--color=always` flag
- flag style：`<long --names / -short / --no-X 否定形式>`
- 错误信息：`<actionable, suggesting next step>`，**不要**只 dump stack

## Testing

```bash
# 单元
<go test ./... / cargo test / pytest>

# 集成（实际跑 CLI）
<scripts/integration-test.sh / tests/cli_test.py 用 subprocess>

# 跨平台
<.github/workflows/ci.yml 矩阵>
```

## Setup

```bash
# build
<go build -o bin/<name> ./cmd or cargo build --release or pip install -e .>

# 本地试用
./bin/<name> --help
```

## UX 准则

- **5 秒规则**：`<name> --help` 在 5 秒内让用户明白怎么开始
- **idempotent**：可重跑（除非命令名包含明确动作如 init / clean）
- **fail fast + suggest**：错的 flag → 不只说"unknown flag"，suggest typo correction
- **respect TTY** vs **respect piping**：进 pipe 就不要 color/spinner

## 安装方式

```bash
# Homebrew (macOS)
brew install <name>

# Linux
curl -L https://... | sh

# 源码
git clone ... && cd <name> && make install
```

## 踩坑记录

<用 `/pit` 在每次修完非平凡 bug 后追加。>

(空)
