# DWD层：明细数据层（ODS → DWD 最优架构方案）

> **设计目标**：将ODS层100+张分表（飞书5万行限制产生）合并、清洗、标准化为DWD层明细表，为下游DWS/ADS层提供高质量、统一口径的明细数据。
>
> **设计原则**：
>
> 1. **分表合并**：50张销售分表通过 `UNION ALL` 合并为单表，消除飞书分表限制；同时提供视图方案作为轻量替代
> 2. **结构对齐**：wd_sales 分表结构不一致（06=55字段/23=47字段/30/50=41字段），以最全结构为基准超集对齐，缺失字段补 NULL
> 3. **长表设计**：销售渠道从「列」转「行」（channel_name + qty + amt），提升扩展性，新增渠道无需改表结构
> 4. **字段标准化**：中文字段名 → 英文标准命名（snake_case）；**数量/天数类用整数**（BIGINT），**金额/比值类用 DECIMAL(18,6)** 保留6位小数，日期用 DATE/DATETIME
> 5. **数据清洗**：varchar 数值字段 CAST 转换、record_id 去重、空值过滤、精度统一
> 6. **粒度统一**：销售明细粒度 = `品牌 + SKU + 销售日期 + 渠道`，商品粒度 = `SKU`，库存粒度 = `SKU`
> 7. **增量字段**：每张DWD表统一新增 `insert_date`（插入时间）和 `update_date`（更新时间），均由 ETL 写入，用于增量更新或增量方案
> 8. **StarRocks 语法**：所有 DDL 采用 StarRocks OLAP PRIMARY KEY 模型，Key 列为前 N 列且顺序一致，按销售日期动态分区，Hash 分桶，replication_num=1（单机环境）

---

## 一、DWD层整体架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            ODS 原始数据层（已完成）                      │
│  t_361sales_01~50   wd_sales_01~50   wd_pinpaikucun   wd_shop          │
│  (13字段,4渠道)     (41~55字段,18渠道) (24字段)        (103字段)         │
│                                       t_361_shop(34字段)  wd_otb(9字段) │
└─────────────────────────────────────────────────────────────────────────┘
                                    │ ETL-1: 合并+清洗+标准化
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            DWD 明细数据层                               │
│  ┌────────────────────────────┐ ┌────────────────────────────┐ ┌────────────────────────────┐ │
│  │ feishu_dwd.                │ │ feishu_dwd.                │ │ feishu_dwd.                │ │
│  │ dwd_feishu_sales_361_d     │ │ dwd_feishu_sales_wd_d      │ │ dwd_feishu_sales_all_d     │ │
│  │ 361销售明细(日刷新)        │ │ 韦德销售明细(日刷新)       │ │ 统一销售明细(长表,日刷新)  │ │
│  │ (50表合并)                 │ │ (50表合并,对齐)            │ │ (361+韦德,渠道转行)        │ │
│  └────────────────────────────┘ └────────────────────────────┘ └────────────────────────────┘ │
│  ┌────────────────────────────┐ ┌────────────────────────────┐ ┌────────────────────────────┐ │
│  │ feishu_dwd.                │ │ feishu_dwd.                │ │ feishu_dwd.                │ │
│  │ dwd_feishu_product_wd_d    │ │ dwd_feishu_product_361_d   │ │ dwd_feishu_product_all_d   │ │
│  │ 韦德商品库(日刷新)         │ │ 361商品库(日刷新)          │ │ 统一商品库(日刷新)         │ │
│  └────────────────────────────┘ └────────────────────────────┘ └────────────────────────────┘ │
│  ┌────────────────────────────┐ ┌────────────────────────────┐                                │
│  │ feishu_dwd.                │ │ feishu_dwd.                │                                │
│  │ dwd_feishu_inventory_d     │ │ dwd_feishu_otb_d           │                                │
│  │ 品牌方库存(日刷新)         │ │ OTB订货计划(日刷新)        │                                │
│  └────────────────────────────┘ └────────────────────────────┘                                │
└─────────────────────────────────────────────────────────────────────────┘

【视图层（可选轻量方案，与DWD表方案并存）】
┌─────────────────────────────────────────────────────────────────────────┐
│  feishu_dwd.v_feishu_sales_361_d   feishu_dwd.v_feishu_sales_wd_d       │
│  (UNION ALL 50张分表，不落物化表，查询时实时合并)                       │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 二、DWD层表清单与粒度定义

| 表名 | 中文名 | 粒度 | 来源 | 记录数(估) |
|------|--------|------|------|-----------|
| `feishu_dwd.dwd_feishu_sales_361_d` | 361销售日明细表 | 品牌+SKU+销售日期+渠道 | t_361sales_01~50 | ~200万行 |
| `feishu_dwd.dwd_feishu_sales_wd_d` | 韦德销售日明细表 | 品牌+SKU+销售日期+渠道 | wd_sales_01~50 | ~250万行 |
| `feishu_dwd.dwd_feishu_sales_all_d` | 统一销售日明细表(长表) | 品牌+SKU+销售日期+渠道 | feishu_dwd.dwd_feishu_sales_361_d + feishu_dwd.dwd_feishu_sales_wd_d | ~450万行 |
| `feishu_dwd.dwd_feishu_product_wd_d` | 韦德商品库清洗表 | SKU | wd_shop | ~5万行 |
| `feishu_dwd.dwd_feishu_product_361_d` | 361商品库清洗表 | SKU | t_361_shop | ~5万行 |
| `feishu_dwd.dwd_feishu_product_all_d` | 统一商品库表 | SKU | feishu_dwd.dwd_feishu_product_wd_d + feishu_dwd.dwd_feishu_product_361_d | ~10万行 |
| `feishu_dwd.dwd_feishu_inventory_d` | 品牌方库存清洗表 | SKU+更新日期 | wd_pinpaikucun | ~10万行 |
| `feishu_dwd.dwd_feishu_otb_d` | OTB订货计划清洗表 | IP+年度 | wd_otb | ~1千行 |

> **命名规范**：`feishu_dwd.dwd_<数据源>_<业务域>_<品牌/范围>_<刷新周期>`
> - Schema：feishu_dwd（DWD层统一Schema）
> - 数据源：feishu（飞书）
> - 刷新周期：d = 日刷新，w = 周刷新
> - 视图命名：`feishu_dwd.v_<数据源>_<业务域>_<品牌/范围>_<刷新周期>`

---

## 三、关键设计决策

### 3.1 wd_sales 分表结构差异处理（核心难点）

**问题**：wd_sales_01~50 分表结构不一致，差异如下：

| 分表           | 字段数 | 差异说明                                                                      |
| -------------- | ------ | ----------------------------------------------------------------------------- |
| wd_sales_06    | 55     | 最全：含款号/尺码/首次销售日期/销售周期所属周 + 8个销售指标 + 总和 + 总和副本 |
| wd_sales_23    | 47     | 少8个销售指标（仅保留实际销量，且为varchar），少"总和副本"                    |
| wd_sales_30/50 | 41     | 精简版：仅 SKU + 销售日期 + 36渠道字段 + sync_time                            |

**解决方案**：以 wd_sales_06（55字段）为**超集基准**，所有分表 UNION ALL 时对齐到超集结构，缺失字段补 NULL。

```sql
-- 超集字段对齐示意（以 wd_sales_06 为基准）：
-- wd_sales_30/50 缺失字段：款号、尺码、首次销售日期、销售周期所属周、
--   订货+补货1、订货+补货、实际总销量、预计销售周期天数、预计周销量、
--   预计销量、实际周销量、实际销量、总和、总和副本 → 统一补 NULL
```

### 3.2 长表 vs 宽表设计选择

| 方案                         | 优点                            | 缺点                                | 适用场景     |
| ---------------------------- | ------------------------------- | ----------------------------------- | ------------ |
| **宽表**（每渠道一列） | 与ODS一致，无需转换             | 新增渠道需改表结构；SQL冗长；难聚合 | 渠道固定不变 |
| **长表**（渠道转行）✅ | 扩展性强；聚合简单；QuickBI友好 | 需UNPIVOT转换；行数膨胀             | 渠道可能变化 |

**决策**：DWD层采用**长表**（渠道转行），即 `feishu_dwd.dwd_feishu_sales_all_d` 表中每条记录 = 一个渠道的一笔销售。

### 3.3 类型统一规范

| 字段类型                       | ODS现状            | DWD目标                                  | 处理方式                           |
| ------------------------------ | ------------------ | ---------------------------------------- | ---------------------------------- |
| 金额                           | decimal / varchar  | `DECIMAL(18,6)`                        | CAST 转换，保留6位小数，异常值置 0 |
| 比值/占比/达成率               | decimal            | `DECIMAL(18,6)`                        | CAST 转换，保留6位小数             |
| 数量（销量/订货/库存）         | decimal / varchar  | `BIGINT`                               | CAST 转换为整数，异常值置 0        |
| 天数（销售周期/周转/安全天数） | decimal / varchar  | `BIGINT`                               | CAST 转换为整数，异常值置 0        |
| 日期                           | datetime / varchar | `DATE`（日期）/ `DATETIME`（时间戳） | CAST 转换                          |
| 字符串                         | varchar            | `VARCHAR(n)`                           | TRIM 去空格                        |

---

## 四、DWD层 SQL 实现（完整代码）

### 4.1 DWD-1：361销售日明细表（合并50张分表）
```sql
-- ============================================================
-- DWD层 SQL 实现（完整代码）
-- 数据库：StarRocks
-- ODS Schema：feishu    DWD Schema：feishu_dwd
-- 规范：
--   1. COMMENT 使用双引号 ""，避免中文括号（）和特殊符号°
--   2. ODS 表引用加 feishu. 前缀
--   3. NULLIF+TRIM 防止 CAST 空字符串报错，DWD 层无 NULL（数值=0，字符="None"，日期=1970-01-01）
--   4. PROPERTIES 精简为 5 项 + 动态分区参数
--   5. dynamic_partition.history_partition_num 替代 create_history_partition
-- ============================================================
```

> 提供两种方案，**方案一为物化表**（落地存储，查询性能好，适合下游高频分析），**方案二为视图**（不落物化表，查询时实时合并，省存储但每次查询需扫描50张分表）。两种方案并存，按场景选用。

```sql
-- ============================================================
-- DWD-1: feishu_dwd.dwd_feishu_sales_361_d  361品牌销售日明细表（日刷新）
-- 来源：t_361sales_01 ~ t_361sales_50（50张分表）
-- 粒度：品牌 + SKU + 销售日期（宽表形态，每渠道一列）
-- 说明：361分表结构一致（13字段，4渠道），直接UNION ALL合并
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型，按 sales_date 动态分区
-- 主键：record_id(飞书唯一ID,全局唯一) + sales_date(分区键)
--
-- 【与ODS层字段差异说明】
-- 1. 新增字段：
--    - brand（品牌）：ODS无，DWD统一标记 '361'
--    - insert_date（插入时间）：ETL写入，用于增量更新
--    - update_date（更新时间）：ETL写入，用于增量更新
-- 2. 去除字段：无（ODS 13字段全部保留）
-- 3. 字段重命名：中文 → 英文snake_case（如 `361sport-销量` → qty_361sport）
-- 4. 类型转换：
--    - 销量字段：varchar/decimal → BIGINT（数量为整数）
--    - 金额字段：varchar/decimal → DECIMAL(18,6)（金额保留6位小数）
--    - 销售日期：datetime → DATE
-- 5. 字段数变化：ODS 13字段 → DWD 17字段（新增 brand/insert_date/update_date）
-- ============================================================

-- ======================================================= =====
-- 方案一：物化表（feishu_dwd.dwd_feishu_sales_361_d）
-- 落地存储，查询性能好，适合下游高频分析与DWS层加工
-- ============================================================
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_sales_361_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_361_d (
    -- 1. record_id 列（前 N 列，顺序与 PRIMARY KEY 一致）
    `record_id`       VARCHAR(64)     COMMENT "飞书记录唯一ID(主键,去重依据)",
    `sales_date`      DATE            COMMENT "销售日期(主键,分区键)",
    `id`              BIGINT          COMMENT "自增主键(来源ODS的id,溯源用)",
    `brand`           VARCHAR(20)     COMMENT "品牌:361(DWD新增字段)",
    `sku`             VARCHAR(64)     COMMENT "SKU编码",
    -- 2. 度量列：4个渠道的销量（件/双，整数类型）
    `qty_361sport`    BIGINT          COMMENT "361sport渠道销量",
    `qty_china`       BIGINT          COMMENT "中国公司(361客户)渠道销量",
    `qty_sample`      BIGINT          COMMENT "361寄样渠道销量",
    `qty_staff_hk`    BIGINT          COMMENT "员工内购(香港)渠道销量",
    -- 3. 度量列：4个渠道的金额（元，保留6位小数）
    `amt_361sport`    DECIMAL(18,6)   COMMENT "361sport渠道金额",
    `amt_china`       DECIMAL(18,6)   COMMENT "中国公司(361客户)渠道金额",
    `amt_sample`      DECIMAL(18,6)   COMMENT "361寄样渠道金额",
    `amt_staff_hk`    DECIMAL(18,6)   COMMENT "员工内购(香港)渠道金额",
    -- 4. 技术字段
    `sync_time`       DATETIME        COMMENT "ODS同步时间",
    `source_table`        VARCHAR(20)     COMMENT "来源分表名(数据溯源,DWD新增)",
    `insert_date`     DATETIME        COMMENT "DWD记录插入时间(ETL写入)",
    `update_date`     DATETIME        COMMENT "DWD记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`record_id`, `sales_date`)
COMMENT "DWD层-361品牌销售日明细表(50张分表合并,日刷新)"
DISTRIBUTED BY HASH(`record_id`)
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", -- PK模型专属优化，开启
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);

-- 合并50张分表（结构一致，直接UNION ALL）
-- 模板：t_361sales_01，其余分表套用同一SELECT，仅改FROM表名
INSERT INTO feishu_dwd.dwd_feishu_sales_361_d (
    id, record_id, brand, sku, sales_date,
    qty_361sport, qty_china, qty_sample, qty_staff_hk,
    amt_361sport, amt_china, amt_sample, amt_staff_hk,
    sync_time, source_table, insert_date, update_date
)
SELECT
    id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    '361' AS brand,                                    -- 品牌标识（DWD新增）
    COALESCE(NULLIF(TRIM(SKU), ''), 'None'),           -- SKU编码
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),        -- 销售日期转DATE类型
    -- 4个渠道销量（CAST为BIGINT整数）
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS BIGINT), 0) AS qty_staff_hk,
    -- 4个渠道金额（CAST为DECIMAL(18,6)保留6位小数）
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_staff_hk,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_01'                                                                   AS source_table,
    NOW() AS insert_date,                              -- ETL写入插入时间
    NOW() AS update_date                               -- ETL写入更新时间
FROM feishu.t_361sales_01
WHERE record_id IS NOT NULL                            -- 过滤空记录
UNION ALL
SELECT
    id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    '361' AS brand,                                    -- 品牌标识（DWD新增）
    COALESCE(NULLIF(TRIM(SKU), ''), 'None'),           -- SKU编码
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),        -- 销售日期转DATE类型
    -- 4个渠道销量（CAST为BIGINT整数）
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS BIGINT), 0) AS qty_staff_hk,
    -- 4个渠道金额（CAST为DECIMAL(18,6)保留6位小数）
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_staff_hk,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_02'                                                                   AS source_table,
    NOW() AS insert_date,                              -- ETL写入插入时间
    NOW() AS update_date                               -- ETL写入更新时间
FROM feishu.t_361sales_02 WHERE record_id IS NOT NULL
-- ... 依次 UNION ALL feishu.t_361sales_03 ~ feishu.t_361sales_49 ...
UNION ALL
SELECT
    id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    '361' AS brand,                                    -- 品牌标识（DWD新增）
    COALESCE(NULLIF(TRIM(SKU), ''), 'None'),           -- SKU编码
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),        -- 销售日期转DATE类型
    -- 4个渠道销量（CAST为BIGINT整数）
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS BIGINT), 0) AS qty_staff_hk,
    -- 4个渠道金额（CAST为DECIMAL(18,6)保留6位小数）
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-金额`), '') AS DECIMAL(18,6)), 0.000000) AS amt_staff_hk,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_50'                                                                   AS source_table,
    NOW() AS insert_date,                              -- ETL写入插入时间
    NOW() AS update_date                               -- ETL写入更新时间
FROM feishu.t_361sales_50 WHERE record_id IS NOT NULL;

-- 验证：行数核验（50张表总行数 = DWD表行数）
-- SELECT COUNT(*) FROM t_361sales_01 + ... + t_361sales_50 应等于
-- SELECT COUNT(*) FROM feishu_dwd.dwd_feishu_sales_361_d;

-- ============================================================
-- 方案二：视图（feishu_dwd.v_feishu_sales_361_d）
-- 不落物化表，查询时实时UNION ALL 50张分表
-- 适用：数据探查、低频查询、节省存储；不适合高频分析场景
-- ============================================================
DROP VIEW IF EXISTS feishu_dwd.v_feishu_sales_361_d;
CREATE VIEW feishu_dwd.v_feishu_sales_361_d AS
SELECT
    id, 
    COALESCE(NULLIF(TRIM(record_id), ''), 'None') AS record_id,
    '361' AS brand, 
    COALESCE(NULLIF(TRIM(SKU), ''), 'None') AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')) AS sales_date,
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS BIGINT), 0) AS qty_staff_hk,
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0) AS amt_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-金额`), '') AS DECIMAL(18,6)), 0) AS amt_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-金额`), '') AS DECIMAL(18,6)), 0) AS amt_staff_hk,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_01'                                                                   AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS insert_date,  -- 视图无ETL写入，用sync_time占位
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS update_date
FROM feishu.t_361sales_01 WHERE record_id IS NOT NULL
UNION ALL
SELECT
    id, 
    COALESCE(NULLIF(TRIM(record_id), ''), 'None') AS record_id,
    '361' AS brand, 
    COALESCE(NULLIF(TRIM(SKU), ''), 'None') AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')) AS sales_date,
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS BIGINT), 0) AS qty_staff_hk,
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0) AS amt_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-金额`), '') AS DECIMAL(18,6)), 0) AS amt_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-金额`), '') AS DECIMAL(18,6)), 0) AS amt_staff_hk,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_02'                                                                   AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS insert_date,  -- 视图无ETL写入，用sync_time占位
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS update_date
FROM feishu.t_361sales_02 WHERE record_id IS NOT NULL
-- ... 依次 UNION ALL feishu.t_361sales_03 ~ feishu.t_361sales_49 ...
UNION ALL
SELECT
    id, 
    COALESCE(NULLIF(TRIM(record_id), ''), 'None') AS record_id,
    '361' AS brand, 
    COALESCE(NULLIF(TRIM(SKU), ''), 'None') AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')) AS sales_date,
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS BIGINT), 0) AS qty_staff_hk,
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0) AS amt_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-金额`), '') AS DECIMAL(18,6)), 0) AS amt_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-金额`), '') AS DECIMAL(18,6)), 0) AS amt_staff_hk,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_050'                                                                   AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS insert_date,  -- 视图无ETL写入，用sync_time占位
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS update_date
FROM feishu.t_361sales_50 WHERE record_id IS NOT NULL;
```

### 4.2 DWD-2：韦德销售日明细表（合并50张分表，处理结构差异）

> 同 DWD-1，提供物化表与视图两种方案。视图方案将50张分表结构对齐后 UNION ALL，查询时实时合并；物化表方案落地存储，适合下游高频分析。两种方案并存。

```sql
-- ============================================================
-- DWD-2: feishu_dwd.dwd_feishu_sales_wd_d  韦德品牌销售日明细表（日刷新）
-- 来源：wd_sales_01 ~ wd_sales_50（50张分表，结构不一致）
-- 粒度：品牌 + SKU + 销售日期（宽表形态，每渠道一列）
-- 难点：wd_sales分表结构差异：
--   - wd_sales_06: 55字段（最全，含款号/尺码/销售指标等）
--   - wd_sales_23: 47字段（少8个销售指标，实际销量为varchar）
--   - wd_sales_30/50: 41字段（精简版，仅SKU+日期+36渠道字段）
-- 解决：以wd_sales_06为超集基准，缺失字段补NULL，统一类型
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型，按 sales_date 动态分区
-- 主键：record_id(飞书唯一ID,全局唯一) + sales_date(分区键)
--
-- 【与ODS层字段差异说明】
-- 1. 新增字段：
--    - brand（品牌）：ODS无，DWD统一标记 '韦德'
--    - source_table（来源分表名）：数据溯源用
--    - insert_date（插入时间）：ETL写入，用于增量更新
--    - update_date（更新时间）：ETL写入，用于增量更新
-- 2. 去除字段：无（以wd_sales_06为超集基准，其他分表缺失字段补NULL保留）
-- 3. 字段重命名：中文 → 英文snake_case（如 `韦德之道-销量` → qty_wd）
-- 4. 类型转换：
--    - 销量字段：varchar/decimal → BIGINT（数量为整数）
--    - 金额/总和字段：varchar/decimal → DECIMAL(18,6)（金额保留6位小数）
--    - 销售日期/首次销售日期：datetime → DATE
-- 5. 字段数变化：以wd_sales_06(55字段)为基准 → DWD 62字段（新增brand/source_table/insert_date/update_date，去除id重复）
-- ============================================================

-- ============================================================
-- 方案一：物化表（feishu_dwd.dwd_feishu_sales_wd_d）
-- 落地存储，查询性能好，适合下游高频分析与DWS层加工
-- ============================================================
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_sales_wd_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_wd_d (
    -- 1. Key 列（前 N 列，顺序与 PRIMARY KEY 一致）
    `record_id`           VARCHAR(64)     COMMENT "飞书记录唯一ID(主键,去重依据)",
    `sales_date`          DATE            COMMENT "销售日期(主键,分区键)",
    `id`                  BIGINT          COMMENT "自增主键(来源ODS的id,溯源用)",
    `brand`               VARCHAR(20)     COMMENT "品牌:韦德(DWD新增字段)",
    `sku`                 VARCHAR(64)     COMMENT "SKU编码",
    -- 2. 维度列
    `style_no`            VARCHAR(64)     COMMENT "款号(仅06/23有，其余为None)",
    `size`                VARCHAR(20)     COMMENT "尺码(仅06/23有，其余为None)",
    `first_sales_date`    DATE            COMMENT "首次销售日期(仅06/23有，其余为1970-01-01)",
    `sales_week`          VARCHAR(20)     COMMENT "销售周期所属周(仅06/23有，其余为None)",
    -- 3. 度量列：销售指标（仅wd_sales_06完整有，其他分表补NULL）
    `order_replenish_1`   BIGINT          COMMENT "订货+补货1(仅06有)",
    `order_replenish`     BIGINT          COMMENT "订货+补货(仅06有)",
    `actual_total_qty`    BIGINT          COMMENT "实际总销量(仅06有)",
    `est_cycle_days`      BIGINT          COMMENT "预计销售周期天数(仅06有)",
    `est_week_qty`        BIGINT          COMMENT "预计周销量(仅06有)",
    `est_qty`             BIGINT          COMMENT "预计销量(仅06有)",
    `actual_week_qty`     BIGINT          COMMENT "实际周销量(仅06有)",
    `actual_qty`          BIGINT          COMMENT "实际销量(06为decimal,23为varchar,30/50无)",
    -- 4. 度量列：18个渠道的销量（整数类型）
    `qty_wd`              BIGINT          COMMENT "韦德之道-销量",
    `qty_wd_sample`       BIGINT          COMMENT "韦德之道寄样-销量",
    `qty_dewu`            BIGINT          COMMENT "得物APP_韦德-销量",
    `qty_dewu_consign`    BIGINT          COMMENT "韦德之道-得物寄售-销量",
    `qty_95fen`           BIGINT          COMMENT "得物APP转寄_95分-销量",
    `qty_guangdong`       BIGINT          COMMENT "广东炫动商贸(李宁客户)-销量",
    `qty_quanyong`        BIGINT          COMMENT "全勇分销-销量",
    `qty_yingkedi`        BIGINT          COMMENT "应科迪_客户-销量",
    `qty_offline`         BIGINT          COMMENT "韦德线下店铺-销量",
    `qty_japan`           BIGINT          COMMENT "韦德日本站-销量",
    `qty_spanish`         BIGINT          COMMENT "韦德西语站-销量",
    `qty_weihong`         BIGINT          COMMENT "dw_韦德伟宏店-销量",
    `qty_95fen_shop`      BIGINT          COMMENT "韦德_95分店-销量",
    `qty_pdd`             BIGINT          COMMENT "拼多多_博耶运动户外专营店-销量",
    `qty_ebay`            BIGINT          COMMENT "eBay-销量",
    `qty_entertainment`   BIGINT          COMMENT "韦德之道--招待费-销量",
    `qty_germany`         BIGINT          COMMENT "韦德德国站-销量",
    `qty_b2b`             BIGINT          COMMENT "韦德之道B2B-销量",
    -- 5. 度量列：18个渠道的金额（保留6位小数）
    `amt_wd`              DECIMAL(18,6)   COMMENT "韦德之道-金额",
    `amt_wd_sample`       DECIMAL(18,6)   COMMENT "韦德之道寄样-金额",
    `amt_dewu`            DECIMAL(18,6)   COMMENT "得物APP_韦德-金额",
    `amt_dewu_consign`    DECIMAL(18,6)   COMMENT "韦德之道-得物寄售-金额",
    `amt_95fen`           DECIMAL(18,6)   COMMENT "得物APP转寄_95分-金额",
    `amt_guangdong`       DECIMAL(18,6)   COMMENT "广东炫动商贸(李宁客户)-金额",
    `amt_quanyong`        DECIMAL(18,6)   COMMENT "全勇分销-金额",
    `amt_yingkedi`        DECIMAL(18,6)   COMMENT "应科迪_客户-金额",
    `amt_offline`         DECIMAL(18,6)   COMMENT "韦德线下店铺-金额",
    `amt_japan`           DECIMAL(18,6)   COMMENT "韦德日本站-金额",
    `amt_spanish`         DECIMAL(18,6)   COMMENT "韦德西语站-金额",
    `amt_weihong`         DECIMAL(18,6)   COMMENT "dw_韦德伟宏店-金额",
    `amt_95fen_shop`      DECIMAL(18,6)   COMMENT "韦德_95分店-金额",
    `amt_pdd`             DECIMAL(18,6)   COMMENT "拼多多_博耶运动户外专营店-金额",
    `amt_ebay`            DECIMAL(18,6)   COMMENT "eBay-金额",
    `amt_entertainment`   DECIMAL(18,6)   COMMENT "韦德之道--招待费-金额",
    `amt_germany`         DECIMAL(18,6)   COMMENT "韦德德国站-金额",
    `amt_b2b`             DECIMAL(18,6)   COMMENT "韦德之道B2B-金额",
    -- 6. 度量列：汇总字段（金额保留6位小数）
    `total_sum`           DECIMAL(18,6)   COMMENT "总和",
    `total_sum_copy`      DECIMAL(18,6)   COMMENT "总和副本(仅06有)",
    -- 7. 技术字段
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `source_table`        VARCHAR(20)     COMMENT "来源分表名(数据溯源,DWD新增)",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间(ETL写入)",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`record_id`, `sales_date`)
COMMENT "DWD层-韦德品牌销售日明细表(50张分表合并,结构对齐,日刷新)"
DISTRIBUTED BY HASH(`record_id`)
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", -- PK模型专属优化，开启
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);

-- ============================================================
-- 合并50张分表：按结构差异分3类处理
-- ============================================================

-- 类型A：wd_sales_06（55字段，最全）- 直接映射
INSERT INTO feishu_dwd.dwd_feishu_sales_wd_d (
    id, record_id, brand, sku, sales_date, style_no, size, first_sales_date, sales_week,
    order_replenish_1, order_replenish, actual_total_qty, est_cycle_days, est_week_qty,
    est_qty, actual_week_qty, actual_qty,
    qty_wd, qty_wd_sample, qty_dewu, qty_dewu_consign, qty_95fen, qty_guangdong,
    qty_quanyong, qty_yingkedi, qty_offline, qty_japan, qty_spanish, qty_weihong,
    qty_95fen_shop, qty_pdd, qty_ebay, qty_entertainment, qty_germany, qty_b2b,
    amt_wd, amt_wd_sample, amt_dewu, amt_dewu_consign, amt_95fen, amt_guangdong,
    amt_quanyong, amt_yingkedi, amt_offline, amt_japan, amt_spanish, amt_weihong,
    amt_95fen_shop, amt_pdd, amt_ebay, amt_entertainment, amt_germany, amt_b2b,
    total_sum, total_sum_copy, sync_time, source_table, insert_date, update_date
)
SELECT
    id                                                                              AS id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01'))                    AS sales_date,
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    COALESCE(DATE(NULLIF(TRIM(首次销售日期), '')), DATE('1970-01-01'))                AS first_sales_date,
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    -- 销售指标
    COALESCE(CAST(NULLIF(TRIM(`订货+补货1`), '') AS BIGINT), 0)                     AS order_replenish_1,
    COALESCE(CAST(NULLIF(TRIM(`订货+补货`), '') AS BIGINT), 0)                      AS order_replenish,
    COALESCE(CAST(NULLIF(TRIM(实际总销量), '') AS BIGINT), 0)                       AS actual_total_qty,
    COALESCE(CAST(NULLIF(TRIM(预计销售周期天数), '') AS BIGINT), 0)                 AS est_cycle_days,
    COALESCE(CAST(NULLIF(TRIM(预计周销量), '') AS BIGINT), 0)                       AS est_week_qty,
    COALESCE(CAST(NULLIF(TRIM(预计销量), '') AS BIGINT), 0)                         AS est_qty,
    COALESCE(CAST(NULLIF(TRIM(实际周销量), '') AS BIGINT), 0)                       AS actual_week_qty,
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS BIGINT), 0)                         AS actual_qty,
    -- 18个渠道销量
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS BIGINT), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS BIGINT), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS BIGINT), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS BIGINT), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS BIGINT), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS BIGINT), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS BIGINT), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS BIGINT), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS BIGINT), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS BIGINT), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS BIGINT), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS BIGINT), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS BIGINT), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS BIGINT), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS BIGINT), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS BIGINT), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS BIGINT), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS BIGINT), 0)               AS qty_b2b,
    -- 18个渠道金额
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0)  AS amt_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0)      AS amt_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0) AS amt_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0)               AS amt_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_b2b,
    -- 汇总字段
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    COALESCE(CAST(NULLIF(TRIM(`总和 副本`), '') AS DECIMAL(18,6)), 0)               AS total_sum_copy,
    -- 系统字段
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_06'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date    
FROM feishu.wd_sales_06
WHERE record_id IS NOT NULL;


-- 类型B：wd_sales_23（47字段）- 缺少8个销售指标中的7个，"实际销量"为varchar，无"总和副本"
-- 对齐方式：缺失的销售指标字段补NULL，其他字段正常映射
INSERT INTO feishu_dwd.dwd_feishu_sales_wd_d (
    id, record_id, brand, sku, sales_date, style_no, size, first_sales_date, sales_week,
    order_replenish_1, order_replenish, actual_total_qty, est_cycle_days, est_week_qty,
    est_qty, actual_week_qty, actual_qty,
    qty_wd, qty_wd_sample, qty_dewu, qty_dewu_consign, qty_95fen, qty_guangdong,
    qty_quanyong, qty_yingkedi, qty_offline, qty_japan, qty_spanish, qty_weihong,
    qty_95fen_shop, qty_pdd, qty_ebay, qty_entertainment, qty_germany, qty_b2b,
    amt_wd, amt_wd_sample, amt_dewu, amt_dewu_consign, amt_95fen, amt_guangdong,
    amt_quanyong, amt_yingkedi, amt_offline, amt_japan, amt_spanish, amt_weihong,
    amt_95fen_shop, amt_pdd, amt_ebay, amt_entertainment, amt_germany, amt_b2b,
    total_sum, total_sum_copy, sync_time, source_table, insert_date, update_date
)
SELECT
    id                                                                              AS id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01'))                    AS sales_date,
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    COALESCE(DATE(NULLIF(TRIM(首次销售日期), '')), DATE('1970-01-01'))                AS first_sales_date,
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- 23分表缺少的销售指标字段补0（7个缺失指标）
    0                                                                               AS order_replenish_1,
    0                                                                               AS order_replenish,
    0                                                                               AS actual_total_qty,
    0                                                                               AS est_cycle_days,
    0                                                                               AS est_week_qty,
    0                                                                               AS est_qty,
    0                                                                               AS actual_week_qty,
    -- 23分表"实际销量"为varchar，需CAST
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS BIGINT), 0)                         AS actual_qty,
    
    -- 18个渠道销量（23分表有，与06一致）
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS BIGINT), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS BIGINT), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS BIGINT), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS BIGINT), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS BIGINT), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS BIGINT), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS BIGINT), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS BIGINT), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS BIGINT), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS BIGINT), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS BIGINT), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS BIGINT), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS BIGINT), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS BIGINT), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS BIGINT), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS BIGINT), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS BIGINT), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS BIGINT), 0)               AS qty_b2b,
    
    -- 18个渠道金额
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0)  AS amt_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0)      AS amt_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0) AS amt_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0)               AS amt_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_b2b,
    
    -- 汇总字段（23有"总和"无"总和副本"）
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    0                                                                               AS total_sum_copy,
    
    -- 系统字段
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_23'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date
    
FROM feishu.wd_sales_23
WHERE record_id IS NOT NULL;


-- 类型C：wd_sales_30/50（41字段，精简版）- 缺少款号/尺码/首次销售日期/销售周期所属周/8个销售指标/总和/总和副本
-- 对齐方式：所有缺失字段补NULL，仅保留SKU+销售日期+36渠道字段
INSERT INTO feishu_dwd.dwd_feishu_sales_wd_d (
    id, record_id, brand, sku, sales_date, style_no, size, first_sales_date, sales_week,
    order_replenish_1, order_replenish, actual_total_qty, est_cycle_days, est_week_qty,
    est_qty, actual_week_qty, actual_qty,
    qty_wd, qty_wd_sample, qty_dewu, qty_dewu_consign, qty_95fen, qty_guangdong,
    qty_quanyong, qty_yingkedi, qty_offline, qty_japan, qty_spanish, qty_weihong,
    qty_95fen_shop, qty_pdd, qty_ebay, qty_entertainment, qty_germany, qty_b2b,
    amt_wd, amt_wd_sample, amt_dewu, amt_dewu_consign, amt_95fen, amt_guangdong,
    amt_quanyong, amt_yingkedi, amt_offline, amt_japan, amt_spanish, amt_weihong,
    amt_95fen_shop, amt_pdd, amt_ebay, amt_entertainment, amt_germany, amt_b2b,
    total_sum, total_sum_copy, sync_time, source_table, insert_date, update_date
)
SELECT
    id                                                                              AS id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01'))                    AS sales_date,
    -- 款号/尺码缺失补 'None'
    'None'                                                                          AS style_no,
    'None'                                                                          AS size,
    -- 首次销售日期/销售周期缺失补默认值
    DATE('1970-01-01')                                                              AS first_sales_date,
    'None'                                                                          AS sales_week,
    -- 8个销售指标全缺失补 0
    0                                                                               AS order_replenish_1,
    0                                                                               AS order_replenish,
    0                                                                               AS actual_total_qty,
    0                                                                               AS est_cycle_days,
    0                                                                               AS est_week_qty,
    0                                                                               AS est_qty,
    0                                                                               AS actual_week_qty,
    0                                                                               AS actual_qty,
    -- 18个渠道销量（30/50有，与06一致）
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS BIGINT), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS BIGINT), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS BIGINT), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS BIGINT), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS BIGINT), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS BIGINT), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS BIGINT), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS BIGINT), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS BIGINT), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS BIGINT), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS BIGINT), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS BIGINT), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS BIGINT), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS BIGINT), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS BIGINT), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS BIGINT), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS BIGINT), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS BIGINT), 0)               AS qty_b2b,
    -- 18个渠道金额
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0)  AS amt_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0)      AS amt_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0) AS amt_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0)               AS amt_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_b2b,
    -- 汇总字段补 0（30/50无）
    0                                                                               AS total_sum,
    0                                                                               AS total_sum_copy,
    -- 系统字段
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_30'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date
FROM feishu.wd_sales_30
WHERE record_id IS NOT NULL;


-- wd_sales_50 与 wd_sales_30 结构完全相同，重复上述INSERT，source_table改为'wd_sales_50'
-- INSERT INTO feishu_dwd.dwd_feishu_sales_wd_d ... SELECT ... FROM wd_sales_50 ... 'wd_sales_50' AS source_table, NOW(), NOW();

-- 注：wd_sales_01~05, 07~22, 24~29, 31~49 的具体结构需根据实际分表确认，
--     若与06/23/30/50之一相同，则套用对应模板；若结构有差异，按超集对齐原则补NULL。
--     先用 information_schema 确认每张分表的实际字段数：
--     SELECT table_name, COUNT(*) AS col_cnt 
--     FROM information_schema.columns 
--     WHERE table_name LIKE 'wd_sales_%' AND table_schema = DATABASE()
--     GROUP BY table_name ORDER BY table_name;

-- 验证：行数核验 + 去重检查
-- SELECT COUNT(*) FROM feishu_dwd.dwd_feishu_sales_wd_d;  -- 应等于50张分表记录总和
-- SELECT record_id, COUNT(*) FROM feishu_dwd.dwd_feishu_sales_wd_d GROUP BY record_id HAVING COUNT(*) > 1;  -- 检查重复

-- ============================================================
-- 方案二：视图（feishu_dwd.v_feishu_sales_wd_d）
-- 不落物化表，查询时实时UNION ALL 50张分表（结构对齐）
-- 适用：数据探查、低频查询、节省存储；不适合高频分析场景
-- ============================================================
DROP VIEW IF EXISTS feishu_dwd.v_feishu_sales_wd_d;
CREATE VIEW feishu_dwd.v_feishu_sales_wd_d AS

-- ==========================================
-- 类型A：wd_sales_06 (最全，包含所有字段)
-- ==========================================
SELECT
    id                                                                              AS id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01'))                    AS sales_date,
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    COALESCE(DATE(NULLIF(TRIM(首次销售日期), '')), DATE('1970-01-01'))                AS first_sales_date,
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- 8个销售指标
    COALESCE(CAST(NULLIF(TRIM(`订货+补货1`), '') AS BIGINT), 0)                     AS order_replenish_1,
    COALESCE(CAST(NULLIF(TRIM(`订货+补货`), '') AS BIGINT), 0)                      AS order_replenish,
    COALESCE(CAST(NULLIF(TRIM(实际总销量), '') AS BIGINT), 0)                       AS actual_total_qty,
    COALESCE(CAST(NULLIF(TRIM(预计销售周期天数), '') AS BIGINT), 0)                 AS est_cycle_days,
    COALESCE(CAST(NULLIF(TRIM(预计周销量), '') AS BIGINT), 0)                       AS est_week_qty,
    COALESCE(CAST(NULLIF(TRIM(预计销量), '') AS BIGINT), 0)                         AS est_qty,
    COALESCE(CAST(NULLIF(TRIM(实际周销量), '') AS BIGINT), 0)                       AS actual_week_qty,
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS BIGINT), 0)                         AS actual_qty,
    
    -- 18个渠道销量
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS BIGINT), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS BIGINT), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS BIGINT), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS BIGINT), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS BIGINT), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS BIGINT), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS BIGINT), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS BIGINT), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS BIGINT), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS BIGINT), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS BIGINT), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS BIGINT), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS BIGINT), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS BIGINT), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS BIGINT), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS BIGINT), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS BIGINT), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS BIGINT), 0)               AS qty_b2b,
    
    -- 18个渠道金额
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0)  AS amt_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0)      AS amt_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0) AS amt_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0)               AS amt_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_b2b,
    
    -- 汇总与系统字段
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    COALESCE(CAST(NULLIF(TRIM(`总和 副本`), '') AS DECIMAL(18,6)), 0)               AS total_sum_copy,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_06'                                                                   AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
FROM feishu.wd_sales_06 
WHERE record_id IS NOT NULL

UNION ALL

-- ==========================================
-- 类型B：wd_sales_23 (缺失7个销售指标，补0)
-- ==========================================
SELECT
    id                                                                              AS id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01'))                    AS sales_date,
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    COALESCE(DATE(NULLIF(TRIM(首次销售日期), '')), DATE('1970-01-01'))                AS first_sales_date,
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- 23分表缺失7个指标补0，保留actual_qty
    0                                                                               AS order_replenish_1,
    0                                                                               AS order_replenish,
    0                                                                               AS actual_total_qty,
    0                                                                               AS est_cycle_days,
    0                                                                               AS est_week_qty,
    0                                                                               AS est_qty,
    0                                                                               AS actual_week_qty,
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS BIGINT), 0)                         AS actual_qty,
    
    -- 18个渠道销量
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS BIGINT), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS BIGINT), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS BIGINT), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS BIGINT), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS BIGINT), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS BIGINT), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS BIGINT), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS BIGINT), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS BIGINT), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS BIGINT), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS BIGINT), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS BIGINT), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS BIGINT), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS BIGINT), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS BIGINT), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS BIGINT), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS BIGINT), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS BIGINT), 0)               AS qty_b2b,
    
    -- 18个渠道金额
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0)  AS amt_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0)      AS amt_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0) AS amt_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0)               AS amt_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_b2b,
    
    -- 汇总与系统字段 (23缺总和副本)
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    0                                                                               AS total_sum_copy,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_23'                                                                   AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
FROM feishu.wd_sales_23 
WHERE record_id IS NOT NULL

UNION ALL

-- ==========================================
-- 类型C：wd_sales_30 (精简版，缺失字段全补默认值)
-- ==========================================
SELECT
    id                                                                              AS id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01'))                    AS sales_date,
    'None'                                                                          AS style_no,
    'None'                                                                          AS size,
    DATE('1970-01-01')                                                              AS first_sales_date,
    'None'                                                                          AS sales_week,
    
    -- 8个销售指标全缺失补0
    0                                                                               AS order_replenish_1,
    0                                                                               AS order_replenish,
    0                                                                               AS actual_total_qty,
    0                                                                               AS est_cycle_days,
    0                                                                               AS est_week_qty,
    0                                                                               AS est_qty,
    0                                                                               AS actual_week_qty,
    0                                                                               AS actual_qty,
    
    -- 18个渠道销量
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS BIGINT), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS BIGINT), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS BIGINT), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS BIGINT), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS BIGINT), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS BIGINT), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS BIGINT), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS BIGINT), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS BIGINT), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS BIGINT), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS BIGINT), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS BIGINT), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS BIGINT), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS BIGINT), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS BIGINT), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS BIGINT), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS BIGINT), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS BIGINT), 0)               AS qty_b2b,
    
    -- 18个渠道金额
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0)  AS amt_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0)      AS amt_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0) AS amt_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0)               AS amt_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_b2b,
    
    -- 汇总与系统字段 (30全缺失补0)
    0                                                                               AS total_sum,
    0                                                                               AS total_sum_copy,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_30'                                                                   AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
FROM feishu.wd_sales_30 
WHERE record_id IS NOT NULL

UNION ALL

-- ==========================================
-- 类型D：wd_sales_50 (同30精简版，source_table为50)
-- ==========================================
SELECT
    id                                                                              AS id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01'))                    AS sales_date,
    'None'                                                                          AS style_no,
    'None'                                                                          AS size,
    DATE('1970-01-01')                                                              AS first_sales_date,
    'None'                                                                          AS sales_week,
    
    -- 8个销售指标全缺失补0
    0                                                                               AS order_replenish_1,
    0                                                                               AS order_replenish,
    0                                                                               AS actual_total_qty,
    0                                                                               AS est_cycle_days,
    0                                                                               AS est_week_qty,
    0                                                                               AS est_qty,
    0                                                                               AS actual_week_qty,
    0                                                                               AS actual_qty,
    
    -- 18个渠道销量
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS BIGINT), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS BIGINT), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS BIGINT), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS BIGINT), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS BIGINT), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS BIGINT), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS BIGINT), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS BIGINT), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS BIGINT), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS BIGINT), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS BIGINT), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS BIGINT), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS BIGINT), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS BIGINT), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS BIGINT), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS BIGINT), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS BIGINT), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS BIGINT), 0)               AS qty_b2b,
    
    -- 18个渠道金额
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0)  AS amt_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0)           AS amt_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0)       AS amt_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0)      AS amt_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0) AS amt_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0)               AS amt_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0)   AS amt_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0)         AS amt_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0)        AS amt_b2b,
    
    -- 汇总与系统字段 (50全缺失补0)
    0                                                                               AS total_sum,
    0                                                                               AS total_sum_copy,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_50'                                                                   AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
FROM feishu.wd_sales_50 
WHERE record_id IS NOT NULL;
-- wd_sales_50 同 wd_sales_30，UNION ALL 时 source_table 改为 'wd_sales_50'
```

### 4.3 DWD-3：统一销售日明细表（长表，渠道转行）

```sql
-- ============================================================
-- DWD-3: feishu_dwd.dwd_feishu_sales_all_d  统一销售日明细表（长表结构，日刷新）
-- 来源：feishu_dwd.dwd_feishu_sales_361_d + feishu_dwd.dwd_feishu_sales_wd_d
-- 粒度：品牌 + SKU + 销售日期 + 渠道（每条记录=一个渠道的一笔销售）
-- 设计：将"宽表"（每渠道一列）UNPIVOT为"长表"（渠道转行）
--   设计动因：1) 新增渠道无需改表结构 2) QuickBI聚合简单 3) 便于跨品牌统一分析
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型，按 sales_date 动态分区
-- 主键：record_id(飞书唯一ID) + sales_date(分区键) + channel_code(渠道,同一record_id多渠道)
--
-- 【与上游DWD表字段差异说明】
-- 1. 新增字段：
--    - channel_code（渠道编码）：英文标准名，统一标识渠道
--    - channel_name（渠道中文名称）：便于展示
--    - channel_type（渠道类型）：自营/寄售/分销/海外/平台/其他
--    - first_sales_date（首次销售日期）：来自wd_sales系列，361系列该字段为空
--    - insert_date / update_date：ETL写入，增量更新用
-- 2. 去除字段：
--    - 去除原宽表中按渠道展开的列（361的4渠道×2指标=8列，韦德的18渠道×2指标=36列）
--    - 转为长表结构：channel_code + qty + amt 三列表示
-- 3. 类型转换：
--    - qty（销量）：BIGINT（整数）
--    - amt（金额）：DECIMAL(18,6)（保留6位小数）
-- 4. 字段数变化：上游宽表（361:17字段，韦德:62字段）→ DWD长表 17字段（统一结构）
-- ============================================================
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_sales_all_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_all_d (
    -- 1. Key 列（前 N 列，顺序与 PRIMARY KEY 一致；sales_date 须为 Key 列以支持分区）
    `record_id`           VARCHAR(64)     COMMENT "飞书记录唯一ID(主键,溯源用)",
    `sales_date`          DATE            COMMENT "销售日期(主键,分区键)",
    `channel_code`        VARCHAR(50)     COMMENT "渠道编码(主键,英文标准名)",
    `id`                  BIGINT          COMMENT "自增ID(溯源用)",
    `brand`               VARCHAR(20)     COMMENT "品牌:361/韦德",
    `sku`                 VARCHAR(64)     COMMENT "SKU编码",
    `style_no`            VARCHAR(64)     COMMENT "款号(361为None)",
    `size`                VARCHAR(20)     COMMENT "尺码(361为None)",
    `first_sales_date`    DATE            COMMENT "首次销售日期(361为1970-01-01)",
    `channel_name`        VARCHAR(100)    COMMENT "渠道中文名称",
    `channel_type`        VARCHAR(30)     COMMENT "渠道类型:自营/寄售/分销/海外/平台/其他",
    -- 3. 度量列
    `qty`                 BIGINT          COMMENT "销量(件/双,整数)",
    `amt`                 DECIMAL(18,6)   COMMENT "金额(元,保留6位小数)",
    -- 4. 技术字段
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `source_table`        VARCHAR(50)     COMMENT "数据来源表名(如wd_sales_06, 361_sales_01,用于溯源和重跑)",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间(ETL写入)",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`record_id`, `sales_date`, `channel_code`)
COMMENT "DWD层-统一销售日明细表(长表,361+韦德,渠道转行,日刷新)"
DISTRIBUTED BY HASH(`record_id`)
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", -- PK模型专属优化，开启
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);

-- ============================================================
-- 插入361品牌数据（4个渠道转行）
-- 使用 UNION ALL 将4个渠道列拆为4行
-- 注：361系列无 first_sales_date，该字段置 NULL
-- ============================================================
INSERT INTO feishu_dwd.dwd_feishu_sales_all_d (
    id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
    channel_code, channel_name, channel_type, qty, amt, sync_time ,source_table, insert_date, update_date
)
-- 361渠道1：361sport
SELECT id, sales_date, record_id, brand, sku, 'None', 'None', DATE('1970-01-01'),
       '361sport', '361sport', '自营',
       qty_361sport, amt_361sport, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_361_d
WHERE qty_361sport <> 0 OR amt_361sport <> 0
UNION ALL
-- 361渠道2：中国公司(361°客户)
SELECT id, sales_date, record_id, brand, sku, 'None', 'None', DATE('1970-01-01'),
       'china_company', '中国公司(361客户)', '自营',
       qty_china, amt_china, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_361_d
WHERE qty_china <> 0 OR amt_china <> 0
UNION ALL
-- 361渠道3：361°寄样
SELECT id, sales_date, record_id, brand, sku, 'None', 'None', DATE('1970-01-01'),
       '361_sample', '361寄样', '寄售',
       qty_sample, amt_sample, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_361_d
WHERE qty_sample <> 0 OR amt_sample <> 0
UNION ALL
-- 361渠道4：员工内购（香港）
SELECT id, sales_date, record_id, brand, sku, 'None', 'None', DATE('1970-01-01'),
       'staff_hk', '员工内购(香港)', '自营',
       qty_staff_hk, amt_staff_hk, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_361_d
WHERE qty_staff_hk <> 0 OR amt_staff_hk <> 0;

-- ============================================================
-- 插入韦德品牌数据（18个渠道转行）
-- 注：韦德系列有 first_sales_date，直接取上游字段
-- ============================================================
INSERT INTO feishu_dwd.dwd_feishu_sales_all_d (
    id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
    channel_code, channel_name, channel_type, qty, amt, sync_time ,source_table, insert_date, update_date
)
-- 韦德渠道1：韦德之道
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'wd', '韦德之道', '自营', qty_wd, amt_wd, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_wd <> 0 OR amt_wd <> 0
UNION ALL
-- 韦德渠道2：韦德之道寄样
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'wd_sample', '韦德之道寄样', '寄售', qty_wd_sample, amt_wd_sample, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_wd_sample <> 0 OR amt_wd_sample <> 0
UNION ALL
-- 韦德渠道3：得物APP_韦德
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'dewu', '得物APP_韦德', '平台', qty_dewu, amt_dewu, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_dewu <> 0 OR amt_dewu <> 0
UNION ALL
-- 韦德渠道4：韦德之道-得物寄售
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'dewu_consign', '韦德之道-得物寄售', '寄售', qty_dewu_consign, amt_dewu_consign, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_dewu_consign <> 0 OR amt_dewu_consign <> 0
UNION ALL
-- 韦德渠道5：得物APP转寄_95分
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       '95fen', '得物APP转寄_95分', '平台', qty_95fen, amt_95fen, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_95fen <> 0 OR amt_95fen <> 0
UNION ALL
-- 韦德渠道6：广东炫动商贸(李宁客户)
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'guangdong', '广东炫动商贸(李宁客户)', '分销', qty_guangdong, amt_guangdong, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_guangdong <> 0 OR amt_guangdong <> 0
UNION ALL
-- 韦德渠道7：全勇分销
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'quanyong', '全勇分销', '分销', qty_quanyong, amt_quanyong, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_quanyong <> 0 OR amt_quanyong <> 0
UNION ALL
-- 韦德渠道8：应科迪_客户
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'yingkedi', '应科迪_客户', '分销', qty_yingkedi, amt_yingkedi, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_yingkedi <> 0 OR amt_yingkedi <> 0
UNION ALL
-- 韦德渠道9：韦德线下店铺
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'offline', '韦德线下店铺', '自营', qty_offline, amt_offline, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_offline <> 0 OR amt_offline <> 0
UNION ALL
-- 韦德渠道10：韦德日本站
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'japan', '韦德日本站', '海外', qty_japan, amt_japan, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_japan <> 0 OR amt_japan <> 0
UNION ALL
-- 韦德渠道11：韦德西语站
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'spanish', '韦德西语站', '海外', qty_spanish, amt_spanish, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_spanish <> 0 OR amt_spanish <> 0
UNION ALL
-- 韦德渠道12：dw_韦德伟宏店
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'weihong', 'dw_韦德伟宏店', '自营', qty_weihong, amt_weihong, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_weihong <> 0 OR amt_weihong <> 0
UNION ALL
-- 韦德渠道13：韦德_95分店
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       '95fen_shop', '韦德_95分店', '平台', qty_95fen_shop, amt_95fen_shop, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_95fen_shop <> 0 OR amt_95fen_shop <> 0
UNION ALL
-- 韦德渠道14：拼多多_博耶运动户外专营店
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'pdd', '拼多多_博耶运动户外专营店', '平台', qty_pdd, amt_pdd, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_pdd <> 0 OR amt_pdd <> 0
UNION ALL
-- 韦德渠道15：eBay
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'ebay', 'eBay', '海外', qty_ebay, amt_ebay, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_ebay <> 0 OR amt_ebay <> 0
UNION ALL
-- 韦德渠道16：韦德之道--招待费
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'entertainment', '韦德之道--招待费', '其他', qty_entertainment, amt_entertainment, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_entertainment <> 0 OR amt_entertainment <> 0
UNION ALL
-- 韦德渠道17：韦德德国站
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'germany', '韦德德国站', '海外', qty_germany, amt_germany, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_germany <> 0 OR amt_germany <> 0
UNION ALL
-- 韦德渠道18：韦德之道B2B
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'b2b', '韦德之道B2B', '分销', qty_b2b, amt_b2b, sync_time ,source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_b2b <> 0 OR amt_b2b <> 0;

-- 验证：
-- SELECT brand, COUNT(*) FROM feishu_dwd.dwd_feishu_sales_all_d GROUP BY brand;  -- 各品牌记录数
-- SELECT channel_code, channel_name, COUNT(*) FROM feishu_dwd.dwd_feishu_sales_all_d GROUP BY channel_code, channel_name;  -- 各渠道记录数
```

### 4.4 DWD-4：韦德商品库清洗表

```sql
-- ============================================================
-- DWD-4: feishu_dwd.dwd_feishu_product_wd_d  韦德商品库清洗表（日刷新）
-- 来源：wd_shop（103字段）
-- 粒度：SKU(主键)，无需聚合(id=record_id=SKU一对一)
-- 说明：从103字段中提取核心商品属性，剔除重复/预留字段（如实际售卖天数1~22、备用款号等）
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型（SKU为业务主键，支持按主键更新）
--
-- 【与ODS层字段差异说明】
-- 1. 新增字段：
--    - insert_date / update_date：ETL写入，增量更新用
-- 2. 去除字段：
--    - id、record_id（ODS的飞书主键）：DWD以 SKU 为业务主键，不需要飞书主键
--    - 实际售卖天数1~22（22个预留字段）：无业务意义
--    - 备用款号、备用款号1~5（6个预留字段）：无业务意义
--    - 其他重复/预留字段（共从103字段精简为44字段）
-- 3. 字段重命名：中文 → 英文snake_case（如 `订货数量(sku)` → order_qty_sku）
-- 4. 类型转换：
--    - 数量/天数类（订货数量/库存/销售目标/售卖天数/补货量/周转天数/安全天数）→ BIGINT（整数）
--    - 金额类（吊牌价/回款价/实际销售价）→ DECIMAL(18,6)（保留6位小数）
--    - 比值类（折扣/SKC达成率）→ DECIMAL(18,6)（保留6位小数）
--    - 日期类：datetime → DATE
-- 5. 聚合说明：不需要聚合。ODS表 wd_shop 中 SKU 唯一（每个SKU对应一条商品记录），
--    id维度 = record_id维度 = SKU维度（一对一），直接按SKU插入即可。
--    验证：SELECT COUNT(DISTINCT SKU) FROM wd_shop = SELECT COUNT(*) FROM wd_shop

-- 额外补充字段:
-- 1. 销售与评级指标（核心补充）
-- rating (评级)：您特别指出的字段。用于商品 ABC 分类或 S/A/B/C 评级，对后续商品生命周期管理和资源倾斜至关重要。
-- official_daily_sales (官网当日销售)：细分渠道的日销指标，用于监控官网渠道的实时爆发力。
-- cum_sales_excl_current_week (销售累积数量-不含本周)：用于计算历史稳定销量，剔除本周波动干扰，是计算“安全库存”和“补货量”的核心基数。
-- 2. 补货与预警体系（完善供应链闭环）
-- warning_status (预警)：原 ODS 中的“预警”，通常为“高/中/低”或红黄蓝标签，用于看板直接展示。
-- variance (差异)：补货模型中的核心计算字段（如：实际库存 - 目标库存），用于分析库存缺口。
-- replenish_num (补货数量)：与原有的 replenish_qty (补货量) 区分。通常业务中一个是“系统建议补货量”，另一个是“人工修正后的最终补货数量”。
-- replenish_correction (补货修正)：记录人工或系统二次干预的修正差值。
-- has_replenish_mark (是否有补货标记)：过程状态字段，标识该 SKU 是否被业务人员打上了“需要补货”的标签（区别于最终结论 is_replenish）。
-- 3. 时间维度与节点追踪（精细化运营）
-- first_available_pickup_date (首次可提日期)：与“首次提货日期”区分，代表供应链端“允许提货”的时间，用于计算供应链响应时效。
-- actual_sales_min_date (实际售卖最小日期)：动销起点，用于精准计算商品的实际生命周期和库龄。
-- est_arrival_month (预计到货月份)：便于直接进行月度维度的到货计划和资金盘点，无需在 BI 层再做日期截断。
-- planned_sales_time (计划销售时间) & est_shelf_time (预计上架时间)：VARCHAR 类型，保留业务填写的计划文本或模糊时间（如“2023年Q3”、“10月下旬”）。
-- 4. 商品主数据与状态标识
-- image_url (图片)：商品主图 URL。在 BI 看板（如 Tableau/FineBI）或数据产品中展示商品明细时，有图片能大幅提升业务人员的核对效率。
-- system_item_no (系统货号)：提取了“系统货号1”作为主系统货号（剔除2/3/4），用于和 ERP/WMS 系统进行底层数据对账。
-- min_granularity (最小颗粒度)：商品归类字段，用于标识该 SKU 是否是拆包售卖的最小单位。
-- order_unique_value (订货唯一值)：订货单或批次的唯一标识，方便追溯该 SKU 属于哪一批次的订货计划。
-- is_confirmed (是否确认过)：状态字段，标识该商品计划是否已经过业务主管审批确认，用于过滤“草稿”数据。
-- ============================================================
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_product_wd_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_product_wd_d (
    -- 1. Key 列（PRIMARY KEY 模型，SKU 为业务主键，须为前 N 列）
    `sku`                         VARCHAR(128)    COMMENT "SKU编码(主键)",
    -- 2. 维度列：商品主数据与归类
    `style_no`                    VARCHAR(128)    COMMENT "款号",
    `ip`                          VARCHAR(100)    COMMENT "IP",
    `series`                      VARCHAR(100)    COMMENT "系列",
    `color_name`                  VARCHAR(100)    COMMENT "配色名",
    `product_name`                VARCHAR(500)    COMMENT "商品名称",
    `size`                        VARCHAR(50)     COMMENT "尺码(码)",
    `product_category`            VARCHAR(100)    COMMENT "商品分类",
    `image_url`                   VARCHAR(1000)   COMMENT "商品图片URL",
    `system_item_no`              VARCHAR(500)    COMMENT "系统货号(主)",
    `min_granularity`             VARCHAR(100)    COMMENT "最小颗粒度",
    `order_unique_value`          VARCHAR(500)    COMMENT "订货唯一值",
    -- 3. 度量列：价格信息
    `tag_price`                   DECIMAL(18,6)   COMMENT "吊牌价",
    `discount`                    DECIMAL(18,6)   COMMENT "折扣",
    `payment_price`               DECIMAL(18,6)   COMMENT "回款价",
    `actual_sales_price`          DECIMAL(18,6)   COMMENT "实际销售价($)",
    -- 4. 度量列：订货信息
    `order_qty_sku`               BIGINT          COMMENT "订货数量(SKU)",
    `order_qty_skc`               BIGINT          COMMENT "订货数量(SKC)",
    -- 5. 维度列：时间信息与状态
    `order_date`                  DATE            COMMENT "订货日期",
    `est_arrival_date`            DATE            COMMENT "预计到货日期",
    `est_arrival_month`           VARCHAR(50)     COMMENT "预计到货月份",
    `first_available_pickup_date` DATE            COMMENT "首次可提日期",
    `first_pickup_date`           DATE            COMMENT "首次提货日期",
    `planned_sales_time`          VARCHAR(100)    COMMENT "计划销售时间",
    `est_shelf_time`              VARCHAR(100)    COMMENT "预计上架时间",
    `shelf_date`                  DATE            COMMENT "上架日期",
    `first_sales_date`            DATE            COMMENT "首次销售日期",
    `actual_sales_min_date`       DATE            COMMENT "实际售卖最小日期",
    `first_order_quarter`         VARCHAR(50)     COMMENT "首次订货季度",
    `year`                        VARCHAR(20)     COMMENT "年份",
    `sales_cycle_label`           VARCHAR(100)    COMMENT "销售周期标签",
    `is_confirmed`                VARCHAR(50)     COMMENT "是否确认过",
    -- 6. 度量列：库存信息
    `inventory_sku`               BIGINT          COMMENT "库存数量(SKU)",
    `inventory_skc`               BIGINT          COMMENT "库存数量(SKC)",
    `inventory_total`             BIGINT          COMMENT "库存合计",
    `inventory_hz`                BIGINT          COMMENT "杭州库存",
    `inventory_baoshui`           BIGINT          COMMENT "保税库存",
    `inventory_feibao`            BIGINT          COMMENT "非保库存",
    -- 7. 度量列：销售指标
    `rating`                      VARCHAR(50)     COMMENT "评级",
    `sales_cycle_days`            BIGINT          COMMENT "销售周期天数",
    `daily_target`                DECIMAL(18,6)   COMMENT "销售目标(日)",
    `weekly_target`               DECIMAL(18,6)   COMMENT "销售目标(周)",
    `monthly_target`              DECIMAL(18,6)   COMMENT "销售目标(月)",
    `quarterly_target`            DECIMAL(18,6)   COMMENT "销售目标(季)",
    `official_daily_sales`        BIGINT          COMMENT "官网当日销售数量",
    `cum_sales_excl_current_week` BIGINT          COMMENT "销售累积数量(不含本周)",
    `cum_sales_sku`               BIGINT          COMMENT "销售累计数量(SKU)",
    `cum_sales_skc`               BIGINT          COMMENT "销售累计数量(SKC)",
    `skc_achievement`             DECIMAL(18,6)   COMMENT "SKC达成率",
    `actual_sales_days`           BIGINT          COMMENT "实际售卖天数",
    `actual_daily_avg`            DECIMAL(18,6)   COMMENT "实际日均销量",
    -- 8. 度量列：补货预警
    `replenish_qty`               BIGINT          COMMENT "补货量",
    `replenish_num`               BIGINT          COMMENT "补货数量",
    `replenish_correction`        VARCHAR(100)    COMMENT "补货修正",
    `variance`                    DECIMAL(18,6)   COMMENT "差异",
    `turnover_days`               DECIMAL(18,6)   COMMENT "周转天数",
    `safety_days`                 BIGINT          COMMENT "安全天数",
    `warning_status`              VARCHAR(100)    COMMENT "预警状态",
    `has_replenish_mark`          VARCHAR(100)    COMMENT "是否有补货标记",
    `is_replenish`                VARCHAR(50)     COMMENT "是否补货",
    -- 9. 技术字段
    `sync_time`                   DATETIME        COMMENT "ODS同步时间",
    `insert_date`                 DATETIME        COMMENT "DWD记录插入时间",
    `update_date`                 DATETIME        COMMENT "DWD记录更新时间"
) ENGINE=OLAP
PRIMARY KEY(`sku`)
COMMENT "DWD层-韦德商品库清洗表(SKU粒度,无需聚合,日刷新)"
DISTRIBUTED BY HASH(`sku`)
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);




-- ============================================================
-- DWD-4 ETL: 韦德商品库清洗表（日刷新）数据写入
-- 来源：feishu.wd_shop (ODS) -> feishu_dwd.dwd_feishu_product_wd_d (DWD)
-- 优化点：
-- 1. 修正了销售目标、日均销量、差异、周转天数的 CAST 类型，适配 ODS 中的小数（DECIMAL）。
-- 2. 修正了补货修正字段的处理，适配 ODS 中的文本“待判定”（VARCHAR）。
-- 3. 统一了空值处理逻辑，确保与 DWD 表结构严格对应。
-- 4. 针对飞书多维表格导出的 varchar 类型进行清洗与类型转换。
-- 5. 金额、比率及含小数的指标统一使用 DECIMAL(38,6) 防止精度丢失。
-- 6. 整数指标增加正则校验，过滤非数字脏数据，防止转换失败导致行被过滤。
-- ============================================================

INSERT INTO feishu_dwd.dwd_feishu_product_wd_d (
    -- 1. Key 列
    sku,
    -- 2. 维度列：商品主数据与归类
    style_no, ip, series, color_name, product_name, size, product_category, 
    image_url, system_item_no, min_granularity, order_unique_value,
    -- 3. 度量列：价格信息
    tag_price, discount, payment_price, actual_sales_price,
    -- 4. 度量列：订货信息
    order_qty_sku, order_qty_skc,
    -- 5. 维度列：时间信息与状态
    order_date, est_arrival_date, est_arrival_month, first_available_pickup_date, 
    first_pickup_date, planned_sales_time, est_shelf_time, shelf_date, 
    first_sales_date, actual_sales_min_date, first_order_quarter, year, 
    sales_cycle_label, is_confirmed,
    -- 6. 度量列：库存信息
    inventory_sku, inventory_skc, inventory_total, inventory_hz, inventory_baoshui, inventory_feibao,
    -- 7. 度量列：销售指标
    rating, sales_cycle_days, daily_target, weekly_target, monthly_target, quarterly_target,
    official_daily_sales, cum_sales_excl_current_week, cum_sales_sku, cum_sales_skc, 
    skc_achievement, actual_sales_days, actual_daily_avg,
    -- 8. 度量列：补货预警
    replenish_qty, replenish_num, replenish_correction, variance, 
    turnover_days, safety_days, warning_status, has_replenish_mark, is_replenish,
    -- 9. 技术字段
    sync_time, insert_date, update_date
)
SELECT
    -- 1. Key 列 (优先取 SKU，为空则取 SKU1)
    COALESCE(NULLIF(TRIM(SKU), ''), NULLIF(TRIM(SKU1), ''))                 AS sku,
    
    -- 2. 维度列：商品主数据与归类
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                 AS style_no,
    COALESCE(NULLIF(TRIM(IP), ''), 'None')                                   AS ip,
    COALESCE(NULLIF(TRIM(系列), ''), 'None')                                 AS series,
    COALESCE(NULLIF(TRIM(配色名), ''), 'None')                               AS color_name,
    COALESCE(NULLIF(TRIM(商品名称), ''), 'None')                             AS product_name,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                 AS size,
    COALESCE(NULLIF(TRIM(商品分类), ''), 'None')                             AS product_category,
    COALESCE(NULLIF(TRIM(图片), ''), 'None')                                 AS image_url,
    COALESCE(NULLIF(TRIM(系统货号1), ''), 'None')                            AS system_item_no,
    COALESCE(NULLIF(TRIM(最小颗粒度), ''), 'None')                           AS min_granularity,
    COALESCE(NULLIF(TRIM(订货唯一值), ''), 'None')                           AS order_unique_value,
    
    -- 3. 度量列：价格信息
    COALESCE(CAST(NULLIF(TRIM(吊牌价), '') AS DECIMAL(38,6)), 0)             AS tag_price,
    COALESCE(CAST(NULLIF(TRIM(折扣), '') AS DECIMAL(38,6)), 0)               AS discount,
    COALESCE(CAST(NULLIF(TRIM(回款价), '') AS DECIMAL(38,6)), 0)             AS payment_price,
    COALESCE(CAST(NULLIF(TRIM(`实际销售价（$）`), '') AS DECIMAL(38,6)), 0)  AS actual_sales_price,
    
    -- 4. 度量列：订货信息（增加正则校验，过滤非数字字符）
    COALESCE(CASE WHEN TRIM(`订货数量(sku)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`订货数量(sku)`) AS BIGINT) ELSE 0 END, 0) AS order_qty_sku,
    COALESCE(CASE WHEN TRIM(`订货数量(SKC)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`订货数量(SKC)`) AS BIGINT) ELSE 0 END, 0) AS order_qty_skc,
    
    -- 5. 维度列：时间信息与状态
    COALESCE(DATE(NULLIF(TRIM(订货日期), '')), DATE('1970-01-01'))           AS order_date,
    COALESCE(DATE(NULLIF(TRIM(预计到货日期), '')), DATE('1970-01-01'))       AS est_arrival_date,
    COALESCE(NULLIF(TRIM(预计到货月份), ''), 'None')                         AS est_arrival_month,
    COALESCE(DATE(NULLIF(TRIM(首次可提日期), '')), DATE('1970-01-01'))       AS first_available_pickup_date,
    COALESCE(DATE(NULLIF(TRIM(首次提货日期), '')), DATE('1970-01-01'))       AS first_pickup_date,
    COALESCE(NULLIF(TRIM(计划销售时间), ''), 'None')                         AS planned_sales_time,
    COALESCE(NULLIF(TRIM(预计上架时间), ''), 'None')                         AS est_shelf_time,
    COALESCE(DATE(NULLIF(TRIM(上架日期), '')), DATE('1970-01-01'))           AS shelf_date,
    COALESCE(DATE(NULLIF(TRIM(首次销售日期), '')), DATE('1970-01-01'))       AS first_sales_date,
    COALESCE(DATE(NULLIF(TRIM(实际售卖最小日期), '')), DATE('1970-01-01'))   AS actual_sales_min_date,
    COALESCE(NULLIF(TRIM(首次订货季度), ''), 'None')                         AS first_order_quarter,
    COALESCE(NULLIF(TRIM(年份), ''), 'None')                                 AS year,
    COALESCE(NULLIF(TRIM(销售周期标签), ''), 'None')                         AS sales_cycle_label,
    COALESCE(NULLIF(TRIM(是否确认过), ''), 'None')                           AS is_confirmed,
    
    -- 6. 度量列：库存信息（增加正则校验，过滤非数字字符）
    COALESCE(CASE WHEN TRIM(`库存数量(SKU)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`库存数量(SKU)`) AS BIGINT) ELSE 0 END, 0) AS inventory_sku,
    COALESCE(CASE WHEN TRIM(`库存数量(SKC)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`库存数量(SKC)`) AS BIGINT) ELSE 0 END, 0) AS inventory_skc,
    COALESCE(CASE WHEN TRIM(库存合计) REGEXP '^[0-9]+$' THEN CAST(TRIM(库存合计) AS BIGINT) ELSE 0 END, 0) AS inventory_total,
    COALESCE(CASE WHEN TRIM(杭州库存) REGEXP '^[0-9]+$' THEN CAST(TRIM(杭州库存) AS BIGINT) ELSE 0 END, 0) AS inventory_hz,
    COALESCE(CASE WHEN TRIM(保税库存) REGEXP '^[0-9]+$' THEN CAST(TRIM(保税库存) AS BIGINT) ELSE 0 END, 0) AS inventory_baoshui,
    COALESCE(CASE WHEN TRIM(非保库存) REGEXP '^[0-9]+$' THEN CAST(TRIM(非保库存) AS BIGINT) ELSE 0 END, 0) AS inventory_feibao,
    
    -- 7. 度量列：销售指标（目标值与日均销量适配飞书小数精度）
    COALESCE(NULLIF(TRIM(评级), ''), 'None')                                 AS rating,
    COALESCE(CASE WHEN TRIM(销售周期天数) REGEXP '^[0-9]+$' THEN CAST(TRIM(销售周期天数) AS BIGINT) ELSE 0 END, 0) AS sales_cycle_days,
    
    COALESCE(CAST(NULLIF(TRIM(`销售目标（日）`), '') AS DECIMAL(38,6)), 0)   AS daily_target,
    COALESCE(CAST(NULLIF(TRIM(`销售目标（周）`), '') AS DECIMAL(38,6)), 0)   AS weekly_target,
    COALESCE(CAST(NULLIF(TRIM(`销售目标（月）`), '') AS DECIMAL(38,6)), 0)   AS monthly_target,
    COALESCE(CAST(NULLIF(TRIM(`销售目标（季）`), '') AS DECIMAL(38,6)), 0)   AS quarterly_target,
    
    COALESCE(CASE WHEN TRIM(官网当日销售) REGEXP '^[0-9]+$' THEN CAST(TRIM(官网当日销售) AS BIGINT) ELSE 0 END, 0) AS official_daily_sales,
    COALESCE(CASE WHEN TRIM(`销售累积数量(不含本周）`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`销售累积数量(不含本周）`) AS BIGINT) ELSE 0 END, 0) AS cum_sales_excl_current_week,
    COALESCE(CASE WHEN TRIM(`销售累计数量(SKU)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`销售累计数量(SKU)`) AS BIGINT) ELSE 0 END, 0) AS cum_sales_sku,
    COALESCE(CASE WHEN TRIM(`销售累计数量(SKC)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`销售累计数量(SKC)`) AS BIGINT) ELSE 0 END, 0) AS cum_sales_skc,
    COALESCE(CAST(NULLIF(TRIM(SKC达成率), '') AS DECIMAL(38,6)), 0)          AS skc_achievement,
    COALESCE(CASE WHEN TRIM(实际售卖天数) REGEXP '^[0-9]+$' THEN CAST(TRIM(实际售卖天数) AS BIGINT) ELSE 0 END, 0) AS actual_sales_days,
    COALESCE(CAST(NULLIF(TRIM(实际日均销量), '') AS DECIMAL(38,6)), 0)       AS actual_daily_avg,
    
    -- 8. 度量列：补货预警（补货修正字段为文本状态，直接保留字符串）
    COALESCE(CASE WHEN TRIM(补货量) REGEXP '^[0-9]+$' THEN CAST(TRIM(补货量) AS BIGINT) ELSE 0 END, 0) AS replenish_qty,
    COALESCE(CASE WHEN TRIM(补货数量) REGEXP '^[0-9]+$' THEN CAST(TRIM(补货数量) AS BIGINT) ELSE 0 END, 0) AS replenish_num,
    
    COALESCE(NULLIF(TRIM(补货修正), ''), 'None')                             AS replenish_correction,
    COALESCE(CAST(NULLIF(TRIM(差异), '') AS DECIMAL(38,6)), 0)               AS variance,
    COALESCE(CAST(NULLIF(TRIM(周转天数), '') AS DECIMAL(38,6)), 0)           AS turnover_days,
    
    COALESCE(CASE WHEN TRIM(安全天数) REGEXP '^[0-9]+$' THEN CAST(TRIM(安全天数) AS BIGINT) ELSE 0 END, 0) AS safety_days,
    COALESCE(NULLIF(TRIM(预警), ''), 'None')                                 AS warning_status,
    COALESCE(NULLIF(TRIM(是否有补货标记), ''), 'None')                       AS has_replenish_mark,
    COALESCE(NULLIF(TRIM(是否补货), ''), 'None')                             AS is_replenish,
    
    -- 9. 技术字段
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))             AS sync_time,
    NOW()                                                                    AS insert_date,
    NOW()                                                                    AS update_date
FROM feishu.wd_shop
-- 过滤条件：只要 SKU 或 SKU1 其中一个有值即可，避免误杀
WHERE COALESCE(NULLIF(TRIM(SKU), ''), NULLIF(TRIM(SKU1), '')) IS NOT NULL;



```

### 4.5 DWD-5：361商品库清洗表

```sql
-- ============================================================
-- DWD-5: feishu_dwd.dwd_feishu_product_361_d  361商品库清洗表（日刷新）
-- 来源：t_361_shop（34字段）
-- 粒度：SKU（主键）
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型（SKU为业务主键，支持按主键更新）
--
-- 【与ODS层字段差异说明】
-- 1. 新增字段：
--    - insert_date / update_date：ETL写入，增量更新用
-- 2. 去除字段：
--    - id、record_id（ODS的飞书主键）：DWD以 SKU 为业务主键，不需要飞书主键
-- 3. 字段重命名：中文 → 英文snake_case（如 `商品货号` → style_no，`订货数量` → order_qty）
-- 4. 类型转换：
--    - 数量类（订货数量/已提数量/未提可提数量）→ BIGINT（整数）
--    - 金额类（吊牌价）→ DECIMAL(18,6)（保留6位小数）
--    - 日期类：datetime/varchar → DATE
--    - 首次提货日期：ODS为varchar，DWD尝试 CAST 为 DATE（异常值置 NULL）
-- 5. 聚合说明：不需要聚合。经数据验证，ODS表 t_361_shop 中：
--    - COUNT(*) = 16672，COUNT(DISTINCT id) = 16672，COUNT(DISTINCT record_id) = 16672
--    - COUNT(DISTINCT SKU) = 16095（577条SKU为空）
--    - 即 id维度 = record_id维度（一对一），过滤空SKU后 SKU维度与id维度一致
--    验证SQL：SELECT COUNT(DISTINCT CONCAT(id,'_',record_id,'_',SKU)) FROM t_361_shop = 16095
-- ============================================================
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_product_361_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_product_361_d (
    -- 1. Key 列（PRIMARY KEY 模型，SKU 为业务主键，须为前 N 列）
    `sku`                 VARCHAR(128)     COMMENT "SKU编码(主键)",
    -- 2. 维度列
    `style_no`            VARCHAR(128)     COMMENT "商品货号（款号）",
    `ip`                  VARCHAR(100)     COMMENT "IP",
    `series`              VARCHAR(100)     COMMENT "系列",
    `product_name`        VARCHAR(500)    COMMENT "商品名称",
    `category`            VARCHAR(100)     COMMENT "品类",
    `size_us`             VARCHAR(50)     COMMENT "美码（尺码）",
    `size_code`           VARCHAR(100)     COMMENT "规格编码",
    -- 3. 度量列
    `tag_price`           DECIMAL(18,6)   COMMENT "吊牌价（金额保留6位小数）",
    -- 4. 维度列：订货信息
    `order_date`          DATE            COMMENT "订货日期",   
    `order_qty`           BIGINT          COMMENT "订货数量（varchar转BIGINT整数）",
    `is_ordered`          VARCHAR(50)     COMMENT "是否订过货",
    `order_method`        VARCHAR(50)     COMMENT "下单方式",
    -- 5. 维度列：到货信息
    `est_arrival_month`   VARCHAR(50)     COMMENT "预计到货月份",
    `est_arrival_date`    DATE            COMMENT "预计到货日期",
    `arrival_confirmed`   VARCHAR(50)     COMMENT "到货月份是否确认",
    `brand_confirm_date`  DATE            COMMENT "品牌方确认日期",
    -- 6. 维度列：提货信息
    `plan_pickup_date`    DATE            COMMENT "计划提货日期",
    `first_pickup_date`   DATE            COMMENT "首次提货日期（ODS为varchar，CAST为DATE，异常值置NULL）",
    `picked_qty`          BIGINT          COMMENT "已提数量（varchar转BIGINT整数）",
    `unpicked_qty`        BIGINT          COMMENT "未提可提数量（varchar转BIGINT整数）",
    -- 7. 维度列：上架信息
    `est_shelf_month`     VARCHAR(20)     COMMENT "预计上架月份",
    `overseas_shelf_date` DATE            COMMENT "海外预计上架时间",
    `actual_shelf_date`   DATE            COMMENT "实际上架时间",
    `is_on_shelf`         VARCHAR(50)     COMMENT "是否上架",
    -- 8. 维度列：运营
    `material_status`     VARCHAR(50)     COMMENT "素材情况",
    `image_status`        VARCHAR(50)     COMMENT "图片完成情况",
    `first_order_quarter` VARCHAR(20)     COMMENT "首次订货到货季度",
    -- 9. 技术字段
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间（ETL写入，增量更新用）",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间（ETL写入，增量更新用）"
) ENGINE=OLAP
PRIMARY KEY(`sku`)
COMMENT "DWD层-361商品库清洗表(SKU粒度,无需聚合,日刷新)"
DISTRIBUTED BY HASH(`sku`)
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", -- PK模型专属优化，开启
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);


INSERT INTO feishu_dwd.dwd_feishu_product_361_d (
    sku, style_no, ip, series, product_name, category, size_us, size_code, tag_price,
    order_date, order_qty, is_ordered, order_method,
    est_arrival_month, est_arrival_date, arrival_confirmed, brand_confirm_date,
    plan_pickup_date, first_pickup_date, picked_qty, unpicked_qty,
    est_shelf_month, overseas_shelf_date, actual_shelf_date, is_on_shelf,
    material_status, image_status, first_order_quarter, sync_time,
    insert_date, update_date
)
SELECT
    -- 1. 基础维度 (ODS均为VARCHAR，保留TRIM)
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                 AS sku,
    COALESCE(NULLIF(TRIM(商品货号), ''), 'None')                            AS style_no,
    COALESCE(NULLIF(TRIM(IP), ''), 'None')                                  AS ip,
    COALESCE(NULLIF(TRIM(系列), ''), 'None')                                AS series,
    COALESCE(NULLIF(TRIM(商品名称), ''), 'None')                            AS product_name,
    COALESCE(NULLIF(TRIM(品类), ''), 'None')                                AS category,
    COALESCE(NULLIF(TRIM(美码), ''), 'None')                                AS size_us,
    COALESCE(NULLIF(TRIM(规格编码), ''), 'None')                            AS size_code,
    
    -- 2. 度量 (ODS为DECIMAL，去掉TRIM，直接CAST)
    COALESCE(CAST(吊牌价 AS DECIMAL(18,6)), 0)                              AS tag_price,                       -- 金额保留6位小数
    
    -- 3. 订货信息
    -- ODS为DATETIME，去掉TRIM，直接CAST为DATE
    COALESCE(CAST(订货日期 AS DATE), '1970-01-01')                          AS order_date,
    -- ODS为VARCHAR，保留TRIM，转BIGINT
    COALESCE(CAST(NULLIF(TRIM(订货数量), '') AS BIGINT), 0)                 AS order_qty,
    COALESCE(NULLIF(TRIM(是否订过货), ''), 'None')                          AS is_ordered,
    COALESCE(NULLIF(TRIM(下单方式), ''), 'None')                            AS order_method,
    
    -- 4. 到货信息
    COALESCE(NULLIF(TRIM(预计到货月份), ''), 'None')                        AS est_arrival_month,
    -- ODS为DATETIME，去掉TRIM
    COALESCE(CAST(预计到货日期 AS DATE), '1970-01-01')                      AS est_arrival_date,
    COALESCE(NULLIF(TRIM(到货月份是否确认), ''), 'None')                    AS arrival_confirmed,
    -- ODS为DATETIME，去掉TRIM
    COALESCE(CAST(品牌方确认日期 AS DATE), '1970-01-01')                    AS brand_confirm_date,
    
    -- 5. 提货信息
    -- ODS为DATETIME，去掉TRIM
    COALESCE(CAST(计划提货日期 AS DATE), '1970-01-01')                      AS plan_pickup_date,
    -- ODS为VARCHAR，保留TRIM，转DATE
    COALESCE(CAST(NULLIF(TRIM(首次提货日期), '') AS DATE), '1970-01-01')    AS first_pickup_date,
    -- ODS为VARCHAR，保留TRIM，转BIGINT
    COALESCE(CAST(NULLIF(TRIM(已提数量), '') AS BIGINT), 0)                 AS picked_qty,
    COALESCE(CAST(NULLIF(TRIM(未提可提数量), '') AS BIGINT), 0)             AS unpicked_qty,
    
    -- 6. 上架信息
    COALESCE(NULLIF(TRIM(预计上架月份), ''), 'None')                        AS est_shelf_month,
    -- ODS为DATETIME，去掉TRIM
    COALESCE(CAST(海外预计上架时间 AS DATE), '1970-01-01')                  AS overseas_shelf_date,
    -- ODS为DATETIME，去掉TRIM
    COALESCE(CAST(实际上架时间 AS DATE), '1970-01-01')                      AS actual_shelf_date,
    COALESCE(NULLIF(TRIM(是否上架), ''), 'None')                            AS is_on_shelf,
    
    -- 7. 运营 (ODS均为VARCHAR，保留TRIM)
    COALESCE(NULLIF(TRIM(素材情况), ''), 'None')                            AS material_status,
    COALESCE(NULLIF(TRIM(图片完成情况), ''), 'None')                        AS image_status,
    COALESCE(NULLIF(TRIM(首次订货到货季度), ''), 'None')                    AS first_order_quarter,
    
    -- 8. 系统字段 (ODS为DATETIME，去掉TRIM)
    COALESCE(sync_time, '1970-01-01 00:00:00')                              AS sync_time,
    NOW()                                                                   AS insert_date,                                -- ETL写入插入时间
    NOW()                                                                   AS update_date                                 -- ETL写入更新时间
FROM feishu.t_361_shop
WHERE SKU IS NOT NULL AND TRIM(SKU) <> '';                    -- 过滤空SKU（577条空SKU被过滤）



```

### 4.6 DWD-6：统一商品库表

```sql
-- ============================================================
-- DWD-6: feishu_dwd.dwd_feishu_product_all_d  统一商品库表（SKU粒度，日刷新）
-- 来源：feishu_dwd.dwd_feishu_product_wd_d（DWD-4）+ feishu_dwd.dwd_feishu_product_361_d（DWD-5）
-- 粒度：SKU + 品牌（主键），统一361和韦德商品库核心字段，为下游DWS/ADS提供统一商品维度
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型（SKU+brand 为业务主键，避免两品牌SKU冲突）
--
-- 【与上游DWD-4/DWD-5字段差异说明】
-- 1. 新增字段：
--    - brand（品牌）：标识来源品牌（361/韦德），区分两源数据，并作为主键组成部分
--    - insert_date / update_date：ETL写入，增量更新用
-- 2. 去除字段（相比DWD-4/DWD-5的详细字段，统一商品库只保留核心字段）：
--    - 来自DWD-4（韦德）去除：discount/payment_price/actual_sales_price/order_qty_skc/
--      est_arrival_date/first_pickup_date/sales_cycle_label/inventory_skc/inventory_total/
--      inventory_hz/inventory_baoshui/inventory_feibao/sales_cycle_days/daily_target/
--      weekly_target/monthly_target/quarterly_target/cum_sales_sku/cum_sales_skc/
--      skc_achievement/actual_sales_days/actual_daily_avg/replenish_qty/turnover_days/
--      safety_days/is_replenish（韦德特有字段，统一库不保留）
--    - 来自DWD-5（361）去除：size_code/is_ordered/order_method/est_arrival_month/
--      arrival_confirmed/brand_confirm_date/plan_pickup_date/first_pickup_date/
--      picked_qty/unpicked_qty/est_shelf_month/overseas_shelf_date/is_on_shelf/
--      material_status/image_status（361特有字段，统一库不保留）
-- 3. 字段统一映射：
--    - 韦德 product_category → 统一 category
--    - 韦德 size（码） → 统一 size；361 size_us（美码） → 统一 size
--    - 韦德 order_qty_sku → 统一 order_qty；361 order_qty → 统一 order_qty
--    - 韦德 shelf_date → 统一 shelf_date；361 actual_shelf_date → 统一 shelf_date
-- 4. 类型转换：
--    - order_qty（订货数量）：BIGINT（整数，继承上游）
--    - inventory_sku（库存数量）：BIGINT（整数，继承上游）
--    - tag_price（吊牌价）：DECIMAL(18,6)（金额保留6位小数，继承上游）
-- 5. 字段数变化：DWD-4(44字段) + DWD-5(31字段) → DWD-6(19字段，统一核心字段)
-- ============================================================
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_product_all_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_product_all_d (
    -- 1. Key 列（PRIMARY KEY 模型，SKU+brand 为业务主键，须为前 N 列）
    `sku`                 VARCHAR(128)     COMMENT "SKU编码(主键组成部分)",
    `brand`               VARCHAR(20)     COMMENT "品牌:361/韦德(主键组成部分)",
    -- 2. 维度列
    `style_no`            VARCHAR(128)     COMMENT "款号/商品货号(主键组成部分)",
    `ip`                  VARCHAR(100)     COMMENT "IP(主键组成部分)",
    `series`              VARCHAR(100)     COMMENT "系列(主键组成部分)",
    `color_name`          VARCHAR(100)     COMMENT "配色名（韦德有，361为空）",
    `product_name`        VARCHAR(500)    COMMENT "商品名称",
    `category`            VARCHAR(100)     COMMENT "品类/商品分类(主键组成部分)",
    `size`                VARCHAR(50)     COMMENT "尺码（韦德码/361美码统一）",
    -- 3. 度量列
    `tag_price`           DECIMAL(18,6)   COMMENT "吊牌价（金额保留6位小数）",
    `order_qty`           BIGINT          COMMENT "订货数量（统一为SKU维度，整数）",
    -- 4. 维度列：订货/上架/销售时间（统一口径）
    `order_date`          DATE            COMMENT "订货日期(主键组成部分)",
    `shelf_date`          DATE            COMMENT "上架日期（统一口径：韦德取shelf_date，361取actual_shelf_date）",
    `first_sales_date`    DATE            COMMENT "首次销售日期（韦德有，361为空）",
    `first_order_quarter` VARCHAR(50)     COMMENT "首次订货季度(主键组成部分)",
    `year`                VARCHAR(50)     COMMENT "年份（韦德有，361为空）",    
    -- 5. 度量列：库存信息（韦德有详细库存，361为空）
    `inventory_sku`       BIGINT          COMMENT "库存数量(SKU)（韦德有，361为空，整数）",
    -- 6. 技术字段
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间（ETL写入，增量更新用）",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间（ETL写入，增量更新用）"
) ENGINE=OLAP
PRIMARY KEY(`sku`, `brand`)
COMMENT "DWD层-统一商品库表(361+韦德,SKU+品牌粒度,核心字段统一,日刷新)"
DISTRIBUTED BY HASH(`sku`)
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", -- PK模型专属优化，开启
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);

-- 韦德商品库（来源DWD-4）
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku, sync_time,
    insert_date, update_date
)
SELECT
    wd.sku, 
    '韦德' AS brand, 
    wd.style_no, 
    wd.ip, 
    wd.series, 
    wd.color_name, 
    wd.product_name,
    wd.product_category AS category,                                 -- 韦德 product_category → 统一 category
    wd.size,
    wd.tag_price,
    wd.order_qty_sku AS order_qty,                                   -- 统一为SKU维度订货量
    wd.order_date,
    wd.shelf_date,                                                   -- 韦德直接取上架日期
    wd.first_sales_date,
    wd.first_order_quarter,
    wd.year,
    wd.inventory_sku,
    wd.sync_time,
    NOW() AS insert_date,                                            -- ETL写入插入时间
    NOW() AS update_date                                             -- ETL写入更新时间
FROM feishu_dwd.dwd_feishu_product_wd_d wd
WHERE wd.sku IS NOT NULL;


-- 361商品库（来源DWD-5）
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku, sync_time,
    insert_date, update_date
)
SELECT
    sku                                                                   AS sku,
    '361'                                                                 AS brand,
    style_no                                                              AS style_no,
    ip                                                                    AS ip,
    series                                                                AS series,
    NULL                                                                  AS color_name,                                  -- 361无配色名
    product_name                                                          AS product_name,
    category                                                              AS category,
    size_us                                                               AS size,                                        -- 361用美码作为统一尺码
    tag_price                                                             AS tag_price,
    order_qty                                                             AS order_qty,
    order_date                                                            AS order_date,
    actual_shelf_date                                                     AS shelf_date,                                  -- 361取实际上架时间作为统一上架日期
    NULL                                                                  AS first_sales_date,                            -- 361商品库无首次销售日期（在销售表中）
    first_order_quarter                                                   AS first_order_quarter,
    NULL                                                                  AS year,                                        -- 361商品库无年份字段
    NULL                                                                  AS inventory_sku,                               -- 361商品库无SKU维度库存
    sync_time                                                             AS sync_time,
    NOW()                                                                 AS insert_date,
    NOW()                                                                 AS update_date
FROM feishu_dwd.dwd_feishu_product_361_d
WHERE sku IS NOT NULL;


-- 验证：
-- SELECT brand, COUNT(*) FROM feishu_dwd.dwd_feishu_product_all_d GROUP BY brand;  -- 各品牌SKU数
-- SELECT COUNT(DISTINCT CONCAT(sku,'_',brand)) FROM feishu_dwd.dwd_feishu_product_all_d;  -- SKU+品牌去重数（应等于总行数）
```

### 4.7 DWD-7：品牌方库存清洗表

```sql
-- ============================================================
-- DWD-7: feishu_dwd.dwd_feishu_inventory_d  品牌方库存清洗表（日刷新）
-- 来源：wd_pinpaikucun（24字段）
-- 粒度：SKU + 库存更新日期
-- 说明：清洗韦德品牌方库存，订货/已提/未提数量从varchar转整数
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型，按 inventory_date 动态分区
--
-- 【与ODS层字段差异说明】
-- 1. 新增字段：
--    - insert_date / update_date：ETL写入，增量更新用
-- 2. 去除字段：无（ODS 24字段全部保留）
-- 3. 字段重命名：中文 → 英文snake_case（如 `品牌方库存更新日期` → inventory_date）
-- 4. 类型转换：
--    - 数量类（库存数量/订货数量/已提数量/未提数量）→ BIGINT（整数）
--    - 金额类（含税单价/吊牌价）→ DECIMAL(18,6)（保留6位小数）
--    - 日期类：datetime → DATE
-- 5. 字段数变化：ODS 24字段 → DWD 26字段（新增 insert_date/update_date）
-- 6. 注意：ODS中 sku 为小写字段名，与其他表 SKU（大写）不同，关联时需统一大小写
-- ============================================================
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_inventory_wdpinpai_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_inventory_wdpinpai_d (
    -- 1. Key 列（前 N 列，顺序与 PRIMARY KEY 一致；inventory_date 须为 Key 列以支持分区）
    `id`                  BIGINT          COMMENT "自增主键(主键,来源ODS的id)",
    `inventory_date`      DATE            COMMENT "品牌方库存更新日期（分区键）",
    -- 2. 维度列
    `record_id`           VARCHAR(64)     COMMENT "飞书记录唯一ID",
    `sku`                 VARCHAR(128)     COMMENT "sku编码（ODS小写sku，注意与SKU区分）",
    `style_no`            VARCHAR(128)     COMMENT "款号",
    `quarter`             VARCHAR(50)     COMMENT "季度",
    `ip`                  VARCHAR(100)     COMMENT "IP",
    `product_name`        VARCHAR(500)    COMMENT "品名",
    `series`              VARCHAR(50)     COMMENT "系列",
    `color_name`          VARCHAR(100)     COMMENT "配色名",
    `category`            VARCHAR(100)     COMMENT "商品类别",
    `size`                VARCHAR(50)     COMMENT "尺码",
    -- 3. 度量列：库存指标（数量为整数，金额保留6位小数）
    `inventory_qty`       BIGINT          COMMENT "库存数量(整数)",
    `price_with_tax`      DECIMAL(18,6)   COMMENT "含税单价(金额保留6位小数)",
    `tag_price`           DECIMAL(18,6)   COMMENT "吊牌价(金额保留6位小数)",
    `order_qty`           BIGINT          COMMENT "订货数量(varchar转BIGINT整数)",
    `picked_qty`          BIGINT          COMMENT "已提数量(varchar转BIGINT整数)",
    `unpicked_qty`        BIGINT          COMMENT "未提数量(varchar转BIGINT整数)",
    -- 4. 维度列：业务标识
    `pickup_flag`         VARCHAR(50)     COMMENT "提货标识",
    `min_granularity`     VARCHAR(100)    COMMENT "最小颗粒度",
    -- 5. 技术字段
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间（ETL写入，增量更新用）",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间（ETL写入，增量更新用）"
) ENGINE=OLAP
PRIMARY KEY(`id`, `inventory_date`)
COMMENT "DWD层-品牌方库存清洗表(SKU+日期粒度,日刷新)"
DISTRIBUTED BY HASH(`id`)
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", -- PK模型专属优化，开启
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);

INSERT INTO feishu_dwd.dwd_feishu_inventory_wdpinpai_d (
    id, inventory_date, record_id, sku, style_no, quarter, ip, product_name, series,
    color_name, category, size,
    inventory_qty, price_with_tax, tag_price, order_qty, picked_qty, unpicked_qty,
    pickup_flag, min_granularity, sync_time, insert_date, update_date
)
SELECT
    inv.id                                                                    AS id,
    COALESCE(DATE(NULLIF(TRIM(inv.品牌方库存更新日期), '')), DATE('1970-01-01')) AS inventory_date,
    COALESCE(NULLIF(TRIM(inv.record_id), ''), 'None')                         AS record_id,
    COALESCE(NULLIF(TRIM(inv.sku), ''), 'None')                               AS sku,
    COALESCE(NULLIF(TRIM(inv.款号), ''), 'None')                              AS style_no,
    COALESCE(NULLIF(TRIM(inv.季度), ''), 'None')                              AS quarter,
    COALESCE(NULLIF(TRIM(inv.IP), ''), 'None')                                AS ip,
    COALESCE(NULLIF(TRIM(inv.品名), ''), 'None')                              AS product_name,
    COALESCE(NULLIF(TRIM(inv.系列), ''), 'None')                              AS series,
    COALESCE(NULLIF(TRIM(inv.配色名), ''), 'None')                            AS color_name,
    COALESCE(NULLIF(TRIM(inv.商品类别), ''), 'None')                          AS category,
    COALESCE(NULLIF(TRIM(inv.尺码), ''), 'None')                              AS size,
    -- 库存指标（数量转BIGINT整数，金额转DECIMAL(18,6)）
    COALESCE(CAST(NULLIF(TRIM(inv.库存数量), '') AS SIGNED), 0)               AS inventory_qty,
    COALESCE(CAST(NULLIF(TRIM(inv.含税单价), '') AS DECIMAL(18,6)), 0)        AS price_with_tax,
    COALESCE(CAST(NULLIF(TRIM(inv.吊牌价), '') AS DECIMAL(18,6)), 0)          AS tag_price,
    COALESCE(CAST(NULLIF(TRIM(inv.订货数量), '') AS SIGNED), 0)               AS order_qty,                            -- varchar转BIGINT整数
    COALESCE(CAST(NULLIF(TRIM(inv.已提数量), '') AS SIGNED), 0)               AS picked_qty,                           -- varchar转BIGINT整数
    COALESCE(CAST(NULLIF(TRIM(inv.未提数量), '') AS SIGNED), 0)               AS unpicked_qty,                         -- varchar转BIGINT整数
    COALESCE(NULLIF(TRIM(inv.提货标识), ''), 'None')                          AS pickup_flag,
    COALESCE(NULLIF(TRIM(inv.最小颗粒度), ''), 'None')                        AS min_granularity,
    COALESCE(inv.sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))          AS sync_time,
    NOW()                                                                     AS insert_date,
    NOW()                                                                     AS update_date
FROM feishu.wd_pinpaikucun inv
WHERE inv.sku IS NOT NULL AND TRIM(inv.sku) <> '';

```

### 4.8 DWD-8：OTB订货计划清洗表

```sql
-- ============================================================
-- DWD-8: feishu_dwd.dwd_feishu_otb_d  OTB订货计划清洗表（日刷新）
-- 来源：wd_otb（9字段）
-- 粒度：IP + 年度（主键）
-- 说明：清洗OTB订货计划，仅做数据类型清洗，不删除字段
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型（IP+year 为业务主键，支持按主键更新）
--
-- 【与ODS层字段差异说明】
-- 1. 新增字段：
--    - insert_date / update_date：ETL写入，增量更新用
-- 2. 去除字段：无（ODS 9字段全部保留，包括 id/record_id/IP/年度/OTB（单位：亿）/订货金额占比/订货牌价/OTB/sync_time）
-- 3. 字段重命名：中文 → 英文snake_case（如 `年度` → year）
-- 4. 类型转换：
--    - OTB（单位：亿）：原decimal → DECIMAL(18,6)（保留6位小数，单位：亿）
--    - OTB：原varchar → DECIMAL(18,6)（保留6位小数，原始数值，如 7.02）
--    - 订货金额占比：原decimal → DECIMAL(18,6)（比值保留6位小数）
--    - 订货牌价：原varchar → DECIMAL(18,6)（金额保留6位小数）
-- 5. 字段数变化：ODS 9字段 → DWD 11字段（新增 insert_date/update_date）
-- 6. 特别说明：ODS中 "OTB（单位：亿）"(decimal) 与 "OTB"(varchar) 不是重复字段：
--    - "OTB（单位：亿）" = 2.000000（decimal，单位：亿元，是规范化金额）
--    - "OTB" = 7.02（varchar，原始数值，可能为其他单位或原始录入值）
--    两者语义不同，均保留
-- 7. 主键设计：以 (ip, year) 为业务主键（PRIMARY KEY），record_id 作为普通字段保留溯源
-- ============================================================
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_otb_wd_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_otb_wd_d (
    -- 1. Key 列（PRIMARY KEY 模型，ip+year 为业务主键，须为前 N 列）
    `ip`                  VARCHAR(100)     COMMENT "IP(主键组成部分)",
    `year`                VARCHAR(20)     COMMENT "年度（主键组成部分）",
    -- 2. 维度列
    `id`                  BIGINT          COMMENT "自增主键（来源ODS的id，溯源用）",
    `record_id`           VARCHAR(64)     COMMENT "飞书记录唯一ID（溯源用）",
    -- 3. 度量列（金额/比值保留6位小数）
    `otb_amount_yi`       DECIMAL(18,6)   COMMENT "OTB金额（单位：亿，原decimal字段，如2.000000）",
    `order_amount_ratio`  DECIMAL(18,6)   COMMENT "订货金额占比（比值保留6位小数）",
    `order_tag_price`     DECIMAL(18,6)   COMMENT "订货牌价（varchar转DECIMAL(18,6)，金额）",
    `otb_raw`             DECIMAL(18,6)   COMMENT "OTB原始值（varchar转DECIMAL(18,6)，如7.02，与otb_amount_yi语义不同）",
    -- 4. 技术字段
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间(ETL写入)",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`ip`, `year`)
COMMENT "DWD层-OTB订货计划清洗表(IP+年度粒度,全字段保留,日刷新)"
DISTRIBUTED BY HASH(`ip`)
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", -- PK模型专属优化，开启
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);


INSERT INTO feishu_dwd.dwd_feishu_otb_wd_d (
    ip, year, id, record_id,
    otb_amount_yi, order_amount_ratio, order_tag_price, otb_raw,
    sync_time, insert_date, update_date
)
SELECT
    COALESCE(NULLIF(TRIM(otb.IP), ''), 'None')                              AS ip,
    COALESCE(NULLIF(TRIM(otb.年度), ''), 'None')                            AS year,
    COALESCE(otb.id, 0)                                                     AS id,
    COALESCE(NULLIF(TRIM(otb.record_id), ''), 'None')                       AS record_id,
    COALESCE(CAST(NULLIF(TRIM(otb.`OTB（单位：亿）`), '') AS DECIMAL(18,6)), 0) AS otb_amount_yi,   -- decimal转DECIMAL(18,6)，单位：亿（如2.000000）
    COALESCE(CAST(NULLIF(TRIM(otb.订货金额占比), '') AS DECIMAL(18,6)), 0)  AS order_amount_ratio,-- decimal转DECIMAL(18,6)，比值（如0.019400）
    COALESCE(CAST(NULLIF(TRIM(otb.订货牌价), '') AS DECIMAL(18,6)), 0)      AS order_tag_price,   -- varchar转DECIMAL(18,6)，金额（如7129800）
    COALESCE(CAST(NULLIF(TRIM(otb.OTB), '') AS DECIMAL(18,6)), 0)           AS otb_raw,           -- varchar转DECIMAL(18,6)，原始值（如7.02，与otb_amount_yi语义不同）
    COALESCE(otb.sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))        AS sync_time,
    NOW()                                                                   AS insert_date,       -- ETL写入插入时间
    NOW()                                                                   AS update_date        -- ETL写入更新时间
FROM feishu.wd_otb otb
WHERE otb.record_id IS NOT NULL
  AND otb.IP IS NOT NULL
  AND otb.年度 IS NOT NULL;

-- 注：OTB（单位：亿）与OTB是两个不同字段，前者为规范化金额（亿），后者为原始值，均保留
```

---

## 五、DWD层验证方案

### 5.1 行数核验（完整性）

```sql
-- 验证1：361销售分表合并行数
SELECT 'ODS_361_total' AS source, SUM(cnt) AS rows_cnt FROM (
    SELECT COUNT(*) AS cnt FROM t_361sales_01
    UNION ALL SELECT COUNT(*) FROM t_361sales_02
    -- ... 省略 t_361sales_03 ~ t_361sales_49
    UNION ALL SELECT COUNT(*) FROM t_361sales_50
) t
UNION ALL
SELECT 'DWD_361' AS source, COUNT(*) AS rows_cnt FROM feishu_dwd.dwd_feishu_sales_361_d;

-- 验证2：韦德销售分表合并行数
SELECT 'ODS_WD_total' AS source, SUM(cnt) AS rows_cnt FROM (
    SELECT COUNT(*) AS cnt FROM wd_sales_01
    -- ... 省略 wd_sales_02 ~ wd_sales_49
    UNION ALL SELECT COUNT(*) FROM wd_sales_50
) t
UNION ALL
SELECT 'DWD_WD' AS source, COUNT(*) AS rows_cnt FROM feishu_dwd.dwd_feishu_sales_wd_d;

-- 验证3：长表行数 = 361(4渠道) + 韦德(18渠道) 的有效记录数
SELECT 'DWD_all' AS source, COUNT(*) AS rows_cnt FROM feishu_dwd.dwd_feishu_sales_all_d;
```

### 5.2 去重检查（唯一性）

```sql
-- 检查record_id是否重复（飞书记录唯一ID应全局唯一）
SELECT 'feishu_dwd.dwd_feishu_sales_361_d' AS tbl, record_id, COUNT(*) AS dup_cnt
FROM feishu_dwd.dwd_feishu_sales_361_d GROUP BY record_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'feishu_dwd.dwd_feishu_sales_wd_d', record_id, COUNT(*)
FROM feishu_dwd.dwd_feishu_sales_wd_d GROUP BY record_id HAVING COUNT(*) > 1;
```

### 5.3 抽样校验（准确性）

```sql
-- 抽样：随机取10条361记录，对比ODS和DWD
SELECT a.record_id, a.sku, a.sales_date, a.qty_361sport, b.`361sport-销量`
FROM feishu_dwd.dwd_feishu_sales_361_d a
JOIN t_361sales_01 b ON a.record_id = b.record_id
ORDER BY RAND() LIMIT 10;

-- 抽样：韦德06分表（结构最全）对比
SELECT a.record_id, a.sku, a.style_no, a.qty_wd, b.`韦德之道-销量`
FROM feishu_dwd.dwd_feishu_sales_wd_d a
JOIN wd_sales_06 b ON a.record_id = b.record_id
ORDER BY RAND() LIMIT 10;
```

### 5.4 空值检查（质量）

```sql
-- 检查关键字段空值率
SELECT
    'feishu_dwd.dwd_feishu_sales_wd_d' AS tbl,
    COUNT(*) AS total_cnt,
    SUM(CASE WHEN sku IS NULL THEN 1 ELSE 0 END) AS sku_null_cnt,
    SUM(CASE WHEN sales_date IS NULL THEN 1 ELSE 0 END) AS date_null_cnt,
    ROUND(SUM(CASE WHEN sku IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS sku_null_pct
FROM feishu_dwd.dwd_feishu_sales_wd_d;
```

---

## 六、性能与成本考量

| 维度                 | 说明                                        | 拓展方向                           |
| -------------------- | ------------------------------------------- | ---------------------------------- |
| **数据扫描量** | 50张分表UNION ALL，单次全表扫描约500万行    | 在业务低峰期执行（凌晨）           |
| **索引设计**   | 主键 record_id + 复合索引 (sku, sales_date) | 满足下游按SKU+日期查询需求         |
| **写入方式**   | CTAS + INSERT，全量覆盖                     | 每日T+1全量重建，简单可靠          |
| **存储成本**   | DWD层约250万行（宽表）+ 450万行（长表）     | 长表行数膨胀但单行更小，总存储相当 |
| **倾斜风险**   | 渠道转行后，热销渠道记录数多                | 查询时按需过滤渠道，不影响写入     |
| **扩展性**     | 长表设计新增渠道无需改表结构                | 扩展性强，下游适配灵活             |

---

## 七、注意事项与后续依赖

### 7.1 注意事项

1. **wd_sales分表结构确认**：上述SQL以 wd_sales_06/23/30/50 四种结构为模板，实际 wd_sales_01~50 中其余分表（01~05, 07~22, 24~29, 31~49）的结构需用 `information_schema.columns` 确认后套用对应模板。可先执行：
   ```sql
   SELECT table_name, COUNT(*) AS col_cnt 
   FROM information_schema.columns 
   WHERE table_name LIKE 'wd_sales_%' AND table_schema = DATABASE()
   GROUP BY table_name ORDER BY table_name;
   ```
2. **SKU大小写问题**：`wd_pinpaikucun` 中 `sku`（小写）与销售表/商品库中 `SKU`（大写）在大小写敏感数据库中视为不同字段，关联时需统一转大写或小写：`UPPER(sku)` 或 `LOWER(SKU)`。
3. **varchar数值字段**：ODS层多处出现 varchar 类型的数值字段（如订货数量、已提数量、回款价等），CAST 时若遇到非数字字符会报错或返回NULL，可用 `TRY_CAST`（如数据库支持）或预先清洗。
4. **首次提货日期类型不一致**：t_361_shop 中 `首次提货日期` 为 varchar，后续清洗为 DATE 类型。
5. **OTB两个字段语义不同需同时保留**：wd_otb 中 `OTB（单位：亿）`(decimal) 为规范化金额（单位：亿），`OTB`(varchar) 为原始值（如7.02），两者语义不同，DWD层统一保留并重命名为 `otb_amount_yi` 与 `otb_raw`。

### 7.2 下游依赖（DWS层需基于DWD层）

- `feishu_dwd.dwd_feishu_sales_all_d`（长表）→ DWS层按 SKC/日期/渠道 聚合
- `feishu_dwd.dwd_feishu_product_all_d` → DWS层关联销售数据计算上架天数、生命周期
- `feishu_dwd.dwd_feishu_inventory_d` → DWS层计算可售周期、库存周转
- `feishu_dwd.dwd_feishu_otb_d` → DWS/ADS层关联OTB计划与实际订货

> **下一步**：待DWD层方案确认并实施后，再设计DWS层（SKC日销售汇总、累计指标、生命周期标签、180天销售计划）。

---

> DWD层方案到此结束。本架构方案的要点：
>
> 1. **明确处理wd_sales分表结构差异**（06/23/30/50三类结构超集对齐）
> 2. **采用长表设计**（渠道转行），新增渠道无需改表结构，QuickBI聚合更灵活
> 3. **增加数据溯源字段**（source_table）和增量字段（insert_date/update_date）
> 4. **完整的数据清洗**（varchar→BIGINT/DECIMAL类型转换、空值过滤、去重）
> 5. **字段命名标准化**（英文snake_case，数量类整数、金额/比值类保留6位小数）
> 6. **完整的验证方案**（行数核验、去重检查、抽样校验、空值检查）
