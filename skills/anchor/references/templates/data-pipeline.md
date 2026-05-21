# <pipeline 名>

<一句话描述：数据流 + 目的。例如：Daily ETL from MySQL slaves to Snowflake for analytics / Realtime event ingest from Kafka to ClickHouse>

## 架构概览

- **调度**：`<Airflow / Dagster / Prefect / Luigi / cron / Argo>`
- **数据源**：`<MySQL replica / Kafka / S3 / 上游 API>`
- **数据目的**：`<Data warehouse: Snowflake/BigQuery/Redshift / OLAP: ClickHouse/Druid / 应用 DB>`
- **中间状态**：`<S3 bucket / GCS / temp tables>`
- **计算引擎**：`<Spark / dbt / Python / SQL only>`

## 关键路径

- 入口 / DAG：`<dags/main.py 或 jobs/etl.yaml>`
- Task 定义：`<dags/<X>.py 或 dbt/models/<X>.sql>`
- Connections / hooks：`<airflow connections / dbt profiles.yml>`
- 配置：`<.env / vault / aws ssm parameters>` — secret 来源
- Sensor / 触发：`<schedule_interval / S3 sensor / Kafka offset>`

## Conventions

- 命名：
  - DAG：`<owner_domain_freq_purpose>` 例如 `data_marketing_daily_kpi_etl`
  - Task：`<verb_object_qualifier>` 例如 `extract_orders_yesterday`、`transform_dim_customer`、`load_fact_revenue`
  - 表：`<staging_X / dim_X / fact_X / mart_X>` 分层命名
- 时区：**统一 UTC** 在 pipeline 内（输入数据带 tz 立刻 normalize）
- backfill：**idempotent** — 同样 DAG run for same date 多跑 N 次结果一致
- partition：所有大表按日期 partition（不要 SELECT 不带 partition filter）

## Testing

```bash
# 单元（业务逻辑函数）
<pytest tests/unit/>

# DBT 测试（schema, not-null, unique, custom）
<dbt test>

# Integration（小 sample 真跑 pipeline）
<airflow tasks test <dag_id> <task_id> <date> / dagster job execute>

# 数据质量（产出 row count / null rate / freshness）
<great_expectations / Soda / dbt-expectations>
```

## Setup

```bash
# 本地起 airflow / dagster
<docker-compose up -d>

# 装 dbt
<pip install dbt-snowflake>

# Connection 初始化
<airflow connections add 或 dbt profiles.yml 填实际地址>
```

## 数据合约

- **schema 变更**必须先 PR review — 下游有依赖
- **breaking schema changes** 必须公告 + 数据消费者迁移期
- **rename / drop column** 走"标记 deprecated → 公告 → N 周后删"流程
- **新表**遵循命名约定（staging/dim/fact/mart）

## 错误 / 重跑策略

- **transient**（网络 / 上游延迟）：airflow retry 3 次 + 5min backoff
- **data quality fail**：fail loud，不要 silent skip
- **upstream missing**：sensor 等到 timeout，timeout 后报警

## 监控

- **健康指标**：`<DAG 成功率 / 单 task 延迟 / 数据新鲜度>`
- **alerting**：`<PagerDuty / Slack #data-alerts on failure>`
- **dashboard**：`<Grafana / Datadog board URL>`

## 踩坑记录

<用 `/pit` 在每次修完非平凡 bug 后追加。>

(空)
