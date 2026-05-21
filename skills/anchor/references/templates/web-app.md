# <项目名>

<一句话描述项目，例如：基于 Express + PostgreSQL 的任务管理 API / 基于 Django 的内部 OA 系统>

## 架构概览

- **框架**：<Express 5 / Django 5 / Flask / Rails / FastAPI / NextJS>
- **数据层**：<PostgreSQL via Prisma / Django ORM / SQLAlchemy 等>
- **认证**：<Session / JWT / OAuth / Passport / Devise / DRF auth>
- **前端**（如有）：<分离 SPA / SSR / HTMX>
- **部署**：<容器 / VM / serverless / K8s>

## 关键路径

- 入口：`<src/server.ts / manage.py / app.rb>:<lineno>`
- 路由 / URL conf：`<src/routes/ or urls.py>`
- 数据模型：`<src/models/ or apps/<X>/models.py>`
- 中间件 / interceptor：`<src/middleware/ or settings.py:MIDDLEWARE>`
- Migration：`<prisma/migrations or migrations/ or db/migrate/>`
- Config / env：`<.env.example or config/settings.py or config/database.yml>`

## Conventions

- 命名：`<驼峰 / snake_case / kebab-case>`
- import 顺序：`<标准库 → 第三方 → 本地, 用 isort/eslint 校验>`
- 错误处理：`<抛 HTTP Exception / 全局 error middleware / Result type>`
- logger：`<winston / loguru / Logger.<level> / structlog>`
- 测试位置：`<__tests__/ same-dir or tests/ top-level>`
- 包管理：`<pnpm / poetry / bundler / pip-tools>` — 不要擅自换

## Testing

```bash
# 单元
<pnpm test:unit / pytest tests/unit / rspec spec/models>

# 集成（含 DB）
<pnpm test:integration / pytest tests/integration / rspec spec/requests>

# E2E（起 server + 真请求）
<pnpm test:e2e / playwright test / pytest tests/e2e>
```

测试数据库：`<test DB schema / docker-compose.test.yml / sqlite memory>`

## Setup

```bash
# 依赖
<pnpm install / poetry install / bundle install>

# DB
<docker compose up -d postgres>
<pnpm db:migrate / python manage.py migrate / rake db:migrate>
<pnpm db:seed / python manage.py loaddata fixtures / rake db:seed>

# 本地起
<pnpm dev / python manage.py runserver / rails s>
```

环境变量：复制 `<.env.example>` 到 `<.env>`，按文档填 `<DATABASE_URL / SECRET_KEY / JWT_SECRET>` 等。

## API 约定

- RESTful: `<GET /resource, POST /resource, PATCH /resource/:id, DELETE /resource/:id>`
- 错误响应：`<{"error": "code", "message": "..."} 格式>`
- 分页：`<?page=N&per_page=M / cursor based>`
- 认证：`<Authorization: Bearer <token> / cookie session>`

## 安全注意

- **不要**：log token / 用户密码 / cookie 内容
- **不要**：信任 client-side 输入 — 始终在 server 端再校验
- **CSRF**：`<是否启用，怎么校验>`
- **CORS**：`<允许的 origin 列表来自哪里>`
- **rate limit**：`<是否有，如何配置>`

## 踩坑记录

<本节用 `/pit` 在每次修完非平凡 bug 后追加。3-5 行/条：现象 + 根因 + 修复 + 教训。>

(空 — 按"6 个月后看到值得感谢现在的自己"标准追加)
