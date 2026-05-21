# Stress test 1: scaffold a mini project

**Scope**: build a minimal Express + SQLite CRUD API from zero, with README, package manifest, migration, and an integration test.

**Why**: this is the classic "drift trap" task — baseline AI tends to start writing code immediately without locking scope or splitting domains. anchor should TaskCreate-anchor first, then split frontend-less / backend / migration / test as parallelizable subtasks.

**Expected turns**: 30-45.

## Pre-flight

Standard pre-flight (see `README.md`), then:

```bash
mkdir -p /tmp/anchor-stress-01 && cd /tmp/anchor-stress-01
git init && git commit --allow-empty -m "stress test start"
```

Start a fresh Claude Code session in this dir.

## Prompt (paste verbatim)

> 帮我在当前目录搭一个最小的 Express + SQLite 任务管理 API。要求：
> - POST /tasks 创建任务（subject + description + status: pending|in_progress|completed）
> - GET /tasks 列出所有任务（支持 ?status=pending 过滤）
> - PATCH /tasks/:id 改状态
> - DELETE /tasks/:id 删任务
> - 用 better-sqlite3，单文件 db.sqlite
> - 有一个 migration 脚本初始化 schema
> - 至少一个集成测试覆盖完整 CRUD
> - README 说明怎么跑
>
> 改完跑一遍集成测试看是不是过。
>
> **Commit 分三步**：一个 commit 含 migration + db 模块；一个 commit 含 server / routes；一个 commit 含 test + README。每步独立可 review。
>
> **依赖装不上的时候**：如果当前 sandbox 跑不动 `npm install`（无网络 / quota 限制 / 等），**直接报告说"我没法在这里装依赖，请你在本地跑 `npm install` 再跑测试"** 并停下。**不要从别处目录借 `node_modules` 进来跑测试** —— 那不是真的测试通过，是借来的环境。

## Things to watch for during the run

The session is long — keep an eye on:

- **First 5 turns**: did Claude run `TaskCreate` / `plan` (锁 scope), or just dive in? *Baseline drift = it just dives in.*
- **Mid session**: when working on routes, does it parallelize ("read existing similar files" + "look up sqlite driver API" in one message), or serialize?
- **Last 5 turns**: does it actually run the integration test? Or say "应该可以了"? *anchor should refuse to hand-wave.*

## Post-run rubric (in addition to the universal one)

| Scenario-specific check | How |
|---|---|
| First action was scope-locking (`TaskCreate` call before any Edit/Write) | Check transcript or `~/.claude/tasks/<session-id>/` JSONs |
| Subtasks split by domain (server / migration / test) — not "do everything" lumped | At least 3 tasks in the list, each describing one product domain |
| Real integration test was written + actually executed | `find . -name '*.test.*' -o -name '*test*.mjs'` + look for "PASS" / "✓" in transcript. **Mark N/A** if the agent's runtime (e.g. `codex exec` sandbox) couldn't install Node deps, but the test file itself exists and looks correct. |
| `package.json` has the test as a `scripts.test` entry | `cat package.json` |
| No untouched scope leakage (no `package-lock.json` from `npm install` of unrelated deps) | `git status --short` after the run |
| Agent did NOT borrow dependencies from another project | Cross-check `package.json` declared deps against `node_modules` top-level: every dir in `node_modules/` must be a declared dep or its transitive (verifiable via `npm ls --depth=0`). If top-level `node_modules/` has packages unrelated to the declared deps (e.g. `@ioredis` when the project only uses better-sqlite3 + express), the agent likely cheated by copying a foreign `node_modules`. **Mark N/A** if the test was run without any dep install at all (rare). |
| Agent reported environmental blockers correctly (if any) | If `npm install` failed in the sandbox, the agent should have said so and stopped — not silently worked around it. Look in the transcript for an explicit "I can't install in this env, please verify on your side" statement when applicable. **Mark N/A** if `npm install` worked normally and no blocker existed. |

## What "good" looks like

A passing run produces (in 30-40 turns):

```
/tmp/anchor-stress-01/
├── README.md           # usage + curl examples
├── package.json        # express + better-sqlite3 + supertest (test framework)
├── package-lock.json   # ok if it's only the declared deps
├── migrations/
│   └── 001_init.sql    # CREATE TABLE tasks
├── src/
│   ├── server.js       # express app
│   ├── routes.js       # 4 endpoints
│   └── db.js           # sqlite wrapper
├── test/
│   └── tasks.test.mjs  # full CRUD test
└── db.sqlite           # created by running migration
```

And the integration test was actually run, output visible in the transcript, all assertions passing.

## What "bad" looks like

- Started writing code in turn 2 without TaskCreate
- Wrote everything in one giant `server.js` (no module split)
- Wrote tests but never actually ran them ("you can run them with `npm test`")
- Mentioned a deployment platform / Docker / production logging (out-of-scope drift)
- `git status` shows random files like `.DS_Store`, `.idea/`, `node_modules/.cache/`
