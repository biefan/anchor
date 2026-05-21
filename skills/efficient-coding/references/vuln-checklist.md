# 漏洞扫描 Checklist（按栈裁剪）

SKILL.md 给了"多遍扫"的方法论；这里给详细 grep / 工具命令，按需查阅。

## 通用反模式 grep

```bash
# 硬编码密钥 / token
grep -rEn '(api[_-]?key|secret|password|token)\s*=\s*["\047][A-Za-z0-9_\-]{16,}' --include='*.py' --include='*.js' --include='*.ts' --include='*.go' --include='*.rs' .

# 危险动态执行
grep -rEn '\beval\(|\bexec\(|Function\(["\047]' --include='*.py' --include='*.js' --include='*.ts' .

# 广 catch
grep -rEn 'except\s*:|except\s+Exception\s*:|catch\s*\(\s*\w*\s*\)\s*\{' --include='*.py' --include='*.js' --include='*.ts' --include='*.java' .

# SQL 字符串拼接
grep -rEn 'SELECT.*\+|INSERT.*\+|UPDATE.*\+|DELETE.*\+|f["\047].*\bSELECT|".*WHERE.*\$' --include='*.py' --include='*.js' --include='*.ts' --include='*.java' --include='*.go' .

# Shell 注入风险
grep -rEn 'shell\s*=\s*True|os\.system\(|subprocess\.[a-z]+\([^)]*\+|exec\s*\(' --include='*.py' .

# 不安全反序列化
grep -rEn 'pickle\.loads?|yaml\.load\s*\(|ObjectInputStream|unserialize\(' --include='*.py' --include='*.js' --include='*.ts' --include='*.java' --include='*.php' .

# 调试 / verbose 错误开着
grep -rEn 'DEBUG\s*=\s*True|debug:\s*true|app\.debug|NODE_ENV.*development' --include='*.py' --include='*.js' --include='*.ts' --include='*.yml' --include='*.yaml' .
```

## SAST 工具

| 语言 | 工具 | 命令 |
|---|---|---|
| Node.js | `npm audit` | `npm audit --audit-level=high` |
| Python | `pip-audit` | `pip-audit --strict` |
| Python | `bandit` | `bandit -r . -ll` |
| Go | `gosec` | `gosec -severity high ./...` |
| Rust | `cargo audit` | `cargo audit -D warnings` |
| 多语言 | `semgrep` | `semgrep --config=auto .` |
| Java | `dependency-check` | `dependency-check --scan .` |
| Ruby | `brakeman` | `brakeman -A` |

每个工具的 output **原样保留**作基线，不要先过滤。

## 按 Web 攻击面的 checklist

### Injection

- [ ] SQL：所有动态 SQL 都用参数化查询（prepared statements / 参数绑定），没有字符串拼接
- [ ] NoSQL：MongoDB `$where` / Redis Lua / Elasticsearch query 没有用户输入直接拼
- [ ] OS command：`exec`/`system`/`Runtime.exec` 没有用户输入；必须有就严格白名单 + 数组参数
- [ ] LDAP：filter 字符串里没有 raw 用户输入
- [ ] Template：用户输入不进入 Jinja/Mustache/Handlebars 等模板的非 escape 区

### Authentication / Session

- [ ] 密码用 bcrypt/argon2/scrypt 哈希（不是 MD5/SHA1）
- [ ] session token 长度 ≥ 128 bit，random secure
- [ ] cookie 设 `HttpOnly` + `Secure` + `SameSite`
- [ ] 没有"默认凭证"（admin/admin、root/root）
- [ ] 失败登录有 rate limit / lockout
- [ ] 敏感操作（改密码、删账户、转账）有 re-auth

### Authorization

- [ ] 每个敏感 endpoint 入口都有授权检查
- [ ] 资源访问检查的是**当前用户对该资源的权限**，不是"是否登录"
- [ ] IDOR：URL 里的 ID 不能让用户改成别人的就能访问
- [ ] 管理员功能 + 普通用户功能严格分离，不是同一个 endpoint 用 role 判断
- [ ] 文件/对象存储的 ACL/IAM policy 没有 `*` / `public-read`（除非真要公开）

### 敏感数据

- [ ] 源码 / 配置 / 日志 / git 历史里没有 secret（用 `git-secrets` / `trufflehog` 扫一遍）
- [ ] PII（手机号、身份证、邮箱）不进入未脱敏日志
- [ ] 加密用现代算法（AES-GCM / ChaCha20-Poly1305），不用 DES/RC4/ECB mode
- [ ] TLS 强制（HSTS），不接受 HTTP 回退

### XSS / CSRF

- [ ] 用户输入在 HTML 输出前 escape（框架默认通常 ok，但 `dangerouslySetInnerHTML` / `v-html` / `innerHTML =` 要重点查）
- [ ] CSP header 设了（至少 `default-src 'self'`）
- [ ] 状态改动接口要 CSRF token（除非纯 cookie-less API + SameSite）

### SSRF / Path traversal / Open redirect

- [ ] 用户提供 URL 的场景（webhook、importer、preview）有 host 白名单 / blocklist（拒绝 127.0.0.1, 169.254.*, metadata）
- [ ] 文件路径输入做 `path.normalize` + 检查 `startsWith(allowedDir)`
- [ ] redirect URL 校验是相对路径或在白名单 host

### 反序列化

- [ ] 不用 pickle / yaml.load(untrusted) / `ObjectInputStream`(untrusted)
- [ ] Python 用 `yaml.safe_load`，PHP 不用 `unserialize` 用户输入
- [ ] JSON 解析后做 schema 校验（zod / joi / pydantic）

### 配置 / 部署

- [ ] 生产 DEBUG 关闭，错误信息不暴露 stack trace 给用户
- [ ] CORS 不设 `*` + `Access-Control-Allow-Credentials: true`
- [ ] 数据库连接不开 root / superuser；分级账号
- [ ] 容器不 root 跑；secrets 不进镜像层
- [ ] CI/CD 的 secret 用平台 secret store，不写 yaml

## 按语言额外项

### Python

- [ ] `subprocess` 不用 `shell=True`
- [ ] `requests` 不禁 verify（除非显式知道）
- [ ] f-string 不用于 SQL/shell/path
- [ ] Django: `extra(where=...)` / `raw()` 用户输入；模板 `|safe` 用户输入

### JavaScript / TypeScript

- [ ] `eval` / `new Function` / `setTimeout(string)` 完全不用
- [ ] `dangerouslySetInnerHTML` 必须 sanitize（DOMPurify）
- [ ] React: 不把用户输入塞进 `href` 不做 `javascript:` 过滤
- [ ] Express: `body-parser` 限 size，避免 DoS
- [ ] `JSON.parse` 用户输入做 try/catch + size limit

### Go

- [ ] `database/sql` 用 `?` placeholder，不 `fmt.Sprintf`
- [ ] `exec.Command` 不用 `sh -c`，参数分开传
- [ ] `http.Server` 设置 `ReadTimeout` / `WriteTimeout`（防 slowloris）

## 报告格式

每条 finding：

| 字段 | 内容 |
|---|---|
| **ID** | SEC-NNN |
| **CWE** | CWE-XXX with name |
| **Severity** | Critical / High / Medium / Low |
| **Location** | `file:line` |
| **Exploit** | 一句话怎么利用 |
| **Fix** | 具体改动 |

写不出 exploit scenario 就降级 severity 或删——不堆"理论上可能"的噪音。
