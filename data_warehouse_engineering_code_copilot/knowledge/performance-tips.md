# 性能优化知识库

> 数仓 SQL / ETL / 调度的性能优化核心知识与实践。

## 1. 分区裁剪

### 核心
所有大型分区表（dt / ds / pt）的 WHERE 条件必须直接命中分区字段，禁止用函数包裹。

### 反例 vs 正例
```sql
-- ❌ 反例：函数包裹分区字段，导致全表扫描
WHERE to_date(dt, 'yyyyMMdd') >= '2026-06-01'
WHERE substr(dt, 1, 6) = '202606'
WHERE date_add(dt, 0) = '20260601'

-- ✅ 正例：直接比较
WHERE dt >= '20260601'
WHERE dt = '20260601'
WHERE dt BETWEEN '20260601' AND '20260630'
```

### 验证
```sql
-- Hive
EXPLAIN
SELECT * FROM dwh_dwd.dwd_xxx WHERE dt = '20260601';
-- 在执行计划中查找 "partition values" 或 "filter pushed down"

-- Spark
EXPLAIN EXTENDED
SELECT * FROM dwh_dwd.dwd_xxx WHERE dt = '20260601';
-- 关注 PartitionFilters 是否包含 dt
```

### 踩坑
- ❌ 动态分区裁剪（DPP）在 Spark 3.0+ 才默认开启，旧版本失效
- ⚠️ 子查询/JOIN 关联条件中使用分区字段时，必须确认裁剪是否生效

---

## 2. 数据倾斜

### 现象
- 任务卡在 99% 长时间不结束
- 个别 reducer 处理数据量是其他的 100x
- OOM 发生在某个特定 stage

### 常见原因
1. Group By / Join Key 上有大量 NULL / 默认值
2. 业务热点（爆款 SKU、头部用户）
3. 时间集中（大促日单分区数据 10x 平日）

### 解决方案

#### 方案 A：过滤 + 单独处理
```sql
-- 把热点 user_id 单独处理
SELECT * FROM (
    SELECT * FROM dwh_dws.dws_user_act WHERE user_id NOT IN ('-1', 'NULL', 'guest')
    UNION ALL
    SELECT user_id, SUM(amt) AS amt
    FROM dwh_dws.dws_user_act WHERE user_id IN ('-1', 'NULL', 'guest')
    GROUP BY user_id
) x;
```

#### 方案 B：加盐打散（Salt + 二次聚合）
```sql
-- 一阶段：加盐分散到 N 个桶
SELECT user_id, salt, SUM(amt) AS amt_part
FROM (
    SELECT user_id, amt, pmod(rand() * 1000, 100) AS salt
    FROM dwh_dwd.dwd_xxx
    WHERE dt = '${bizdate}'
) t
GROUP BY user_id, salt;

-- 二阶段：去盐汇总
-- (在外层再 SUM)
```

#### 方案 C：Map Join 小表
（详见 §3）

### 配置项参考
```sql
-- Hive
SET hive.optimize.skewjoin = true;
SET hive.skewjoin.key = 100000;
SET hive.groupby.skewindata = true;

-- Spark
SET spark.sql.adaptive.enabled = true;
SET spark.sql.adaptive.skewJoin.enabled = true;
SET spark.sql.adaptive.skewJoin.skewedPartitionThresholdInBytes = 256m;
```

---

## 3. Map Join / Broadcast Join

### 核心
当 Join 一侧是小表（< 阈值，通常 50-100MB）时，把小表广播到每个 Map Task，避免 Shuffle。

### 触发方式
```sql
-- Hive：自动触发（开启后）
SET hive.auto.convert.join = true;
SET hive.mapjoin.smalltable.filesize = 25000000;  -- 25MB

-- Hive：显式 Hint
SELECT /*+ MAPJOIN(b) */ a.*, b.dim_name
FROM big_fact a
LEFT JOIN small_dim b ON a.dim_id = b.dim_id;

-- Spark：自动 Broadcast
SET spark.sql.autoBroadcastJoinThreshold = 104857600;  -- 100MB

-- Spark：显式 Hint
SELECT /*+ BROADCAST(b) */ a.*, b.dim_name FROM ...;
SELECT /*+ BROADCASTJOIN(b) */ a.*, b.dim_name FROM ...;
```

### 阈值建议
| 引擎 | 默认阈值 | 推荐 |
|------|---------|------|
| Hive | 25MB | 50MB |
| Spark | 10MB | 100MB |
| Trino | 自动 | 配合 dynamic filtering |

### 踩坑
- ❌ 把"小表"实际行数 > 1 千万时也加广播 hint → driver OOM
- ⚠️ 多个 Broadcast Join 嵌套时，注意累积 driver 内存

---

## 4. 小文件问题

### 危害
- 元数据爆炸（NameNode 压力）
- Map Task 启动开销 >> 实际处理时间
- 查询性能下降

### 控制手段
```sql
-- 输出端控制
SET mapreduce.job.reduces = 64;
INSERT OVERWRITE TABLE ... SELECT ... DISTRIBUTE BY pmod(hash(some_key), 64);

-- Spark AQE 自动合并
SET spark.sql.adaptive.enabled = true;
SET spark.sql.adaptive.coalescePartitions.enabled = true;
SET spark.sql.adaptive.advisoryPartitionSizeInBytes = 256m;

-- 周期性合并（运维任务）
ALTER TABLE dwh_xxx PARTITION (dt='...') CONCATENATE;  -- Hive ORC
CALL system.rewrite_data_files('dwh_xxx');             -- Iceberg
```

### 阈值
- 单文件目标：128MB ~ 256MB
- 单分区文件数：< 50

---

## 5. CTE / WITH 物化策略

### 引擎差异
| 引擎 | CTE 行为 | 多次引用 |
|------|---------|---------|
| Hive | 默认不物化 | 每次重新计算 |
| Spark | 默认不物化（可 CACHE） | 每次重新计算 |
| Trino / Presto | 默认不物化 | 每次重新计算 |
| PostgreSQL 12+ | 默认 NOT MATERIALIZED | 可 inlining |
| Snowflake | 物化为临时结果 | 复用 |

### 推荐做法
```sql
-- ✅ 多次引用的复杂 CTE，先落临时表
CREATE TEMPORARY TABLE tmp_base AS
SELECT ... FROM big_table WHERE dt='${bizdate}' AND ...;

-- 然后多次引用 tmp_base，避免重复计算

-- ✅ Spark 可显式 CACHE
CACHE TABLE tmp_base;
```

### 踩坑
- ❌ 在 Hive/Spark 中假设 WITH 会被物化，导致重复计算 5+ 次
- ⚠️ Spark `CACHE` 会占用 executor 内存，注意释放

---

## 6. 谓词下推（PPD）与列裁剪

### 核心
- **谓词下推**：WHERE 条件下推到数据源层，减少扫描
- **列裁剪**：只读必要列，跳过其他列（列存格式如 ORC/Parquet 收益巨大）

### 验证
```sql
-- 检查执行计划是否包含 PartitionFilters / DataFilters
EXPLAIN EXTENDED SELECT col1, col2 FROM dwh_xxx WHERE dt='20260601' AND col3 = 'A';
```

### 失效场景
- ❌ ON 条件中混入对外层表的过滤
- ❌ 用了 UDF（自定义函数）使谓词无法下推
- ❌ SELECT * 导致列裁剪失效

### 优化技巧
```sql
-- ❌ 反例：WHERE 写在 ON 中，无法下推
SELECT a.*, b.*
FROM big a
LEFT JOIN big b ON a.k = b.k AND a.dt = '20260601' AND b.dt = '20260601'
WHERE a.col > 0;

-- ✅ 正例：WHERE 各自约束
SELECT a.*, b.*
FROM big a
LEFT JOIN big b ON a.k = b.k AND a.dt = b.dt
WHERE a.dt = '20260601'
  AND b.dt = '20260601'
  AND a.col > 0;
```

---

## 7. Join 顺序与类型

### 顺序原则（按引擎）
- **Hive on MR**：左大右小（SortMerge），右表会被广播为 build side
- **Spark / Trino**：CBO 自动选，但保留 hint 兜底
- **MaxCompute**：Map Join 优先小表

### 类型选择
| Join 类型 | 适用 | 代价 |
|----------|------|------|
| Broadcast Hash Join | 一侧小表 | 🟢 最快 |
| Shuffle Hash Join | 中等表 | 🟡 中等 |
| Sort Merge Join | 两侧都大 | 🔴 高（需排序） |
| Bucket Join | 两侧按相同 key 分桶 | 🟢 跳过 Shuffle |

### 分桶 Join
```sql
-- 两张大表按 user_id 分桶，Join 时跳过 Shuffle
CREATE TABLE dwh_dwd.dwd_user_event (...)
CLUSTERED BY (user_id) INTO 256 BUCKETS;

CREATE TABLE dwh_dwd.dwd_user_order (...)
CLUSTERED BY (user_id) INTO 256 BUCKETS;
```

---

## 8. 窗口函数性能

### 关键点
- **PARTITION BY** 列基数过低 → 单分区数据过大，倾斜
- **PARTITION BY** 列基数过高 → 分区过多，启动开销
- **ORDER BY** 复杂时考虑预排序

### 优化技巧
```sql
-- ❌ 不必要的全局排序
SELECT *, ROW_NUMBER() OVER (ORDER BY ts) AS rn FROM big_table;

-- ✅ 加 PARTITION BY 限定范围
SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY ts) AS rn FROM big_table;
```

### 配合 DISTRIBUTE BY
```sql
SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY ts) AS rn
FROM (
    SELECT * FROM big_table WHERE dt = '${bizdate}'
    DISTRIBUTE BY user_id SORT BY user_id, ts
) t;
```

---

## 9. 存储格式与压缩

| 格式 | 适用 | 压缩 | 查询性能 |
|------|------|------|---------|
| **ORC** | Hive 主流 | Zlib / Snappy / ZSTD | 🟢 优秀 |
| **Parquet** | Spark / Iceberg / Trino 主流 | Snappy / ZSTD / GZIP | 🟢 优秀 |
| **TextFile** | 临时 / 兼容 | GZIP / BZIP2 | 🔴 慢 |
| **Avro** | Schema 演进强 | Snappy | 🟡 中等 |
| **JSON** | 半结构化 | GZIP | 🔴 慢 |

### 推荐
- 大型分析表：ORC + ZSTD（Hive）/ Parquet + ZSTD（Spark）
- 小表 / 临时表：Parquet + Snappy
- 强 schema 演进：Iceberg + Parquet

### 列存收益
- 列裁剪：只读必要列，扫描量降 5-10x
- 谓词下推：基于列统计跳过 row group
- 压缩：列内同质数据压缩率高 3-5x

---

## 10. 调度与资源

### 资源队列
- 按主题/优先级划分队列
- 高优先级任务（核心 ADS）独占队列
- 低优先级（探索 / 回刷）放共享队列，限并发

### 调度时间窗
- 错峰调度：避开 0:00 / 1:00 数据库备份高峰
- 依赖紧凑：上游就绪后立即触发，避免空等
- SLA 基线：核心表标记基线（如 7:00 前必须产出）

### 失败重试
- 重试 3 次，间隔指数退避（1min → 5min → 15min）
- 重试前先判断幂等（INSERT OVERWRITE 才能重试）
- 连续失败 → 告警值班 + 自动跳过下游或保留前一日数据

---

## 11. 性能分析工具

### 通用流程
1. **EXPLAIN** 看执行计划：分区裁剪 / Join 类型 / Shuffle 数
2. **作业历史**（HDP / EMR / Azkaban / DolphinScheduler / MC Logview）：识别慢 stage
3. **Profile / Stage Metrics**：单 task 数据量、运行时长、shuffle 读写量
4. **数据采样**：`SELECT key, COUNT(*) FROM ... GROUP BY key ORDER BY 2 DESC LIMIT 20` 找倾斜键

### 常用命令
```sql
-- 查看分区列表
SHOW PARTITIONS dwh_dwd.dwd_xxx;

-- 查看表元数据
DESC FORMATTED dwh_dwd.dwd_xxx;

-- 查看建表语句
SHOW CREATE TABLE dwh_dwd.dwd_xxx;

-- Hive 表统计信息（让优化器生效）
ANALYZE TABLE dwh_dwd.dwd_xxx PARTITION (dt='${bizdate}') COMPUTE STATISTICS FOR COLUMNS;
```
