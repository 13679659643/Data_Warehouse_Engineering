# ETL / 数据集成模式库

> 数仓常用的数据接入与同步模式，覆盖 JDBC 抽取、CDC、文件、API 等典型场景。
> 工具栈以 DataX / SeaTunnel / Flink CDC / dbt / Spark 为主。

## 1. CDC 增量同步（Flink CDC + Kafka + Iceberg/Hudi）

### 场景
对延迟敏感的业务表（订单、支付）实时同步至数仓，并保留历史每条变更。

### 拓扑
```
MySQL binlog ──> Flink CDC Source ──> Kafka(原始流) ──> Flink ETL ──> Iceberg/Hudi(MOR)
                                                       └──> 写 ODS 增量表（按 dt 分区）
```

### 关键约定
- **位点保护**：Checkpoint 周期建议 30s ~ 60s，state backend 选 RocksDB
- **op 字段**：保留 `+I / -U / +U / -D` 四种事件，下游可还原全量
- **幂等**：Hudi/Iceberg 主键 upsert；Hive 增量表落 binlog 原始事件，由 ODS 合并任务做去重
- **回放**：保留 Kafka topic 不少于 7 天，故障时按位点重放

### 踩坑
- ❌ binlog 中 ts 字段是事件时间，不是事务提交时间。强一致排序需结合 `gtid + bin_pos + op_seq`
- ❌ 大事务（DDL / 批量 update）会瞬间产生海量 binlog，需要监控 lag
- ⚠️ MySQL 主备切换时位点会跳变，订阅端需要做 GTID 校验

---

## 2. JDBC 增量抽取（DataX / SeaTunnel）

### 场景
对实时性要求一般的业务表（每日 T+1），用基于 update_time 水位的批量抽取。

### 关键 SQL
```sql
-- 抽取 SQL（在 DataX/SeaTunnel querySql 中）
SELECT id, name, status, amount, create_time, update_time
FROM source_db.orders
WHERE update_time >= '${bizdate} 00:00:00'
  AND update_time <  '${bizdate_plus_1} 00:00:00';
```

### 关键约定
- **水位字段**：必须单调递增、有索引、与业务事件时间一致；推荐 `update_time` 而非 `create_time`
- **重叠窗口**：跨天边界抽取建议有 5~30 分钟重叠 + ODS 去重，避免漏数
- **网络与并发**：DataX `channel` 数与源端连接池容量匹配；大表用 `splitPk` 分片
- **幂等**：写入侧用 `INSERT OVERWRITE PARTITION (dt='${bizdate}')`

### 踩坑
- ❌ 用 `create_time` 做水位会漏掉历史数据的字段更新
- ❌ 源端 `update_time` 不更新（如某些枚举切换走存储过程）会丢更新
- ⚠️ 时区不一致（业务库 +00:00，数仓 +08:00）会导致跨日丢数

---

## 3. MERGE / UPSERT（基于主键的幂等写入）

### 场景
对支持 ACID 的存储（Hudi / Iceberg / Delta / MaxCompute Transaction Table）做主键幂等写入。

### 代码
```sql
-- Iceberg / Spark 3.x
MERGE INTO dwh_dwd.dwd_user AS t
USING (
    SELECT user_id, name, level, update_time
    FROM dwh_ods.ods_user_inc
    WHERE dt = '${bizdate}'
) AS s
ON t.user_id = s.user_id
WHEN MATCHED AND s.update_time > t.update_time THEN
    UPDATE SET name = s.name, level = s.level, update_time = s.update_time
WHEN NOT MATCHED THEN
    INSERT (user_id, name, level, update_time)
    VALUES (s.user_id, s.name, s.level, s.update_time);
```

### 关键约定
- **乱序保护**：必须用 `s.update_time > t.update_time` 避免被后到的旧事件覆盖
- **冲突处理**：源端如有重复主键，先在 USING 子查询里 ROW_NUMBER 去重
- **小文件**：开启 compaction（Hudi `clustering`、Iceberg `rewrite_data_files`）

### 踩坑
- ❌ Hive 非事务表不支持 MERGE，会被解析为 INSERT，产生重复
- ⚠️ 频繁 UPSERT 产生大量删除标记文件，需要定期合并

---

## 4. 小文件控制

### 场景
Spark / Hive 输出端 reduce 数过多，导致下游小文件爆炸。

### 解决思路
```sql
-- Hive：手动控制 reduce 数
SET mapreduce.job.reduces = 32;

-- Hive / Spark：通过 distribute by 强制散列
INSERT OVERWRITE TABLE dwh_dwd.dwd_xxx_di PARTITION (dt='${bizdate}')
SELECT ... FROM ...
DISTRIBUTE BY pmod(hash(some_key), 32);
-- 或按目标文件大小估算的桶数

-- Spark：动态合并
SET spark.sql.adaptive.enabled = true;
SET spark.sql.adaptive.coalescePartitions.enabled = true;
SET spark.sql.adaptive.advisoryPartitionSizeInBytes = 256m;
```

### 阈值建议
- 单文件目标大小：128MB ~ 256MB（HDFS / OSS）
- 单分区文件数：建议 < 50

### 踩坑
- ❌ 一刀切设置 `mapreduce.job.reduces=1` 会导致最后阶段单点
- ⚠️ AQE 在 Spark 3.0 之前默认关闭，旧版需要手动开启

---

## 5. 历史回刷（分批 + 进度跟踪）

### 场景
口径调整需要回刷过去 N 个月的分区，单次执行体量过大。

### 推荐流程
1. **确认范围**：列出所有受影响表与分区
2. **确认依赖**：构建依赖 DAG，确认上游 ODS/DIM 数据齐备
3. **试点**：先回刷最近 7 天，对比指标，确认口径一致
4. **分批执行**：每批 N 个分区，控制并发不影响日常作业
5. **进度追踪**：用一张状态表记录每个分区状态（pending / running / success / failed）
6. **失败处理**：单分区失败重试 3 次后告警

### 进度状态表示例
```sql
CREATE TABLE IF NOT EXISTS ops_log.refresh_progress (
    refresh_id  STRING,
    table_name  STRING,
    dt          STRING,
    status      STRING COMMENT 'pending/running/success/failed',
    start_time  TIMESTAMP,
    end_time    TIMESTAMP,
    rows_count  BIGINT,
    err_msg     STRING
);
```

### 踩坑
- ❌ 一次性回刷上千分区会把队列资源吃光，影响日常基线
- ⚠️ 回刷期间下游会读到不一致数据，建议加"回刷中"标记并通知下游

---

## 6. 文件接入（CSV / Excel / JSON）

### 场景
合作方按日推送 CSV/Excel 文件，需要解析、校验、入库。

### 关键约定
- **目录约定**：按日期分文件夹 `/landing/{system}/{table}/dt=YYYYMMDD/`
- **完成标记**：等待 `_SUCCESS` 文件再触发解析，避免读到半文件
- **编码**：CSV 显式指定 UTF-8 / GBK；Excel 用 XLSX 而非 XLS
- **schema 校验**：列数、列名、类型不一致时阻断 + 告警
- **bad record 隔离**：解析失败的行单独落到 `*_error` 表，不阻塞主流程

### 踩坑
- ❌ Excel 中文本数字（如手机号）被自动转科学计数法
- ❌ CSV 中字段含逗号但未转义，会错列
- ⚠️ 文件名时间戳与数据日期不一致时，需要约定以哪个为准

---

## 7. API 拉取（REST / GraphQL）

### 场景
从三方 SaaS（如广告平台、CRM）拉取数据，多为分页 + Token 鉴权。

### 关键约定
- **限流**：尊重 API rate limit，使用 token bucket
- **重试**：5xx / 429 退避重试；4xx 直接告警
- **断点续传**：保存 cursor / next_token，避免全量重拉
- **变更追踪**：能取增量就用增量参数（since / updated_after）
- **schema 漂移**：保留原始 JSON 列 `raw_payload`，便于回溯字段新增/调整

### 踩坑
- ❌ Token 写在代码或脚本里 → 必须走密钥管理服务
- ⚠️ API 返回字段大小写不一致（snake / camel），统一在 ODS 入库时规范化

---

## 8. 全量 vs 增量 vs CDC 选型对照

| 维度 | 全量抽取 | JDBC 增量 | CDC |
|------|---------|----------|-----|
| 实时性 | T+1 | T+1（小时级） | 秒级 ~ 分钟级 |
| 源端压力 | 高（每次扫表） | 中（按水位） | 低（订阅 binlog） |
| 数据完整性 | 高（一致快照） | 中（依赖水位） | 高（事件流） |
| 实现复杂度 | 低 | 低 | 高 |
| 历史变更追踪 | 无（覆盖） | 弱（仅最新） | 强（完整事件） |
| 适用规模 | 小表（< 100 万行） | 中等 | 大型 / 需要变更追踪 |
| 工具 | DataX/SeaTunnel | DataX/SeaTunnel | Flink CDC / Debezium |

---

## 9. 数据漂移与时区处理

### 场景
跨时区业务（出海）按"业务自然日"切分时与数据落库时间不一致。

### 关键约定
- **存储**：所有时间字段存储为 UTC，并附带 `tz` 列或 `local_dt` 派生列
- **分区**：按业务日（local_dt）分区，而非数据落库时间
- **报表**：明确每个指标的时区口径（北京时间 / UTC / 本地时区）
- **跨日订单**：以下单时区的自然日为准

### 踩坑
- ❌ 业务库 datetime（无时区）+ 数仓 timestamp（UTC）混用 → 必须显式转换
- ⚠️ 夏令时国家（如美国）跨日订单会有 23/25 小时的日，注意聚合时不要硬编码 24
