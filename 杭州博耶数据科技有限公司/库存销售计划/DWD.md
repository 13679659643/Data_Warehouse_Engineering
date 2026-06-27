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
    -- 4个渠道销量（CAST为SIGNED整数）
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS SIGNED), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS SIGNED), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS SIGNED), 0) AS qty_staff_hk,
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
    -- 4个渠道销量（CAST为SIGNED整数）
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS SIGNED), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS SIGNED), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS SIGNED), 0) AS qty_staff_hk,
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
    -- 4个渠道销量（CAST为SIGNED整数）
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS SIGNED), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS SIGNED), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS SIGNED), 0) AS qty_staff_hk,
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
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS SIGNED), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS SIGNED), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS SIGNED), 0) AS qty_staff_hk,
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
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS SIGNED), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS SIGNED), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS SIGNED), 0) AS qty_staff_hk,
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
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361°客户)-销量`), '') AS SIGNED), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361°寄样-销量`), '') AS SIGNED), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购（香港）-销量`), '') AS SIGNED), 0) AS qty_staff_hk,
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
    COALESCE(CAST(NULLIF(TRIM(`订货+补货1`), '') AS SIGNED), 0)                     AS order_replenish_1,
    COALESCE(CAST(NULLIF(TRIM(`订货+补货`), '') AS SIGNED), 0)                      AS order_replenish,
    COALESCE(CAST(NULLIF(TRIM(实际总销量), '') AS SIGNED), 0)                       AS actual_total_qty,
    COALESCE(CAST(NULLIF(TRIM(预计销售周期天数), '') AS SIGNED), 0)                 AS est_cycle_days,
    COALESCE(CAST(NULLIF(TRIM(预计周销量), '') AS SIGNED), 0)                       AS est_week_qty,
    COALESCE(CAST(NULLIF(TRIM(预计销量), '') AS SIGNED), 0)                         AS est_qty,
    COALESCE(CAST(NULLIF(TRIM(实际周销量), '') AS SIGNED), 0)                       AS actual_week_qty,
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS SIGNED), 0)                         AS actual_qty,
    -- 18个渠道销量
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0)               AS qty_b2b,
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
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS SIGNED), 0)                         AS actual_qty,
    
    -- 18个渠道销量（23分表有，与06一致）
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0)               AS qty_b2b,
    
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
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0)               AS qty_b2b,
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
    COALESCE(CAST(NULLIF(TRIM(`订货+补货1`), '') AS SIGNED), 0)                     AS order_replenish_1,
    COALESCE(CAST(NULLIF(TRIM(`订货+补货`), '') AS SIGNED), 0)                      AS order_replenish,
    COALESCE(CAST(NULLIF(TRIM(实际总销量), '') AS SIGNED), 0)                       AS actual_total_qty,
    COALESCE(CAST(NULLIF(TRIM(预计销售周期天数), '') AS SIGNED), 0)                 AS est_cycle_days,
    COALESCE(CAST(NULLIF(TRIM(预计周销量), '') AS SIGNED), 0)                       AS est_week_qty,
    COALESCE(CAST(NULLIF(TRIM(预计销量), '') AS SIGNED), 0)                         AS est_qty,
    COALESCE(CAST(NULLIF(TRIM(实际周销量), '') AS SIGNED), 0)                       AS actual_week_qty,
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS SIGNED), 0)                         AS actual_qty,
    
    -- 18个渠道销量
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0)               AS qty_b2b,
    
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
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS SIGNED), 0)                         AS actual_qty,
    
    -- 18个渠道销量
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0)               AS qty_b2b,
    
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
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0)               AS qty_b2b,
    
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
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0)                  AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0)              AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0)              AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0)         AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0)          AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0)                  AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0)               AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0)              AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0)                AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0)                AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0)             AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0)               AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0)                      AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0)          AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0)                AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0)               AS qty_b2b,
    
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
-- 粒度：SKU（主键）
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
-- ============================================================
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_product_wd_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_product_wd_d (
    -- 1. Key 列（PRIMARY KEY 模型，SKU 为业务主键，须为前 N 列）
    `sku`                 VARCHAR(64)     COMMENT 'SKU编码（主键）',
    -- 2. 维度列
    `style_no`            VARCHAR(64)     COMMENT '款号',
    `ip`                  VARCHAR(50)     COMMENT 'IP',
    `series`              VARCHAR(50)     COMMENT '系列',
    `color_name`          VARCHAR(50)     COMMENT '配色名',
    `product_name`        VARCHAR(200)    COMMENT '商品名称',
    `size`                VARCHAR(20)     COMMENT '尺码（码）',
    `product_category`    VARCHAR(50)     COMMENT '商品分类',
    -- 3. 度量列：价格信息（金额保留6位小数）
    `tag_price`           DECIMAL(18,6)   COMMENT '吊牌价',
    `discount`            DECIMAL(18,6)   COMMENT '折扣（比值保留6位小数）',
    `payment_price`       DECIMAL(18,6)   COMMENT '回款价（varchar转decimal，金额）',
    `actual_sales_price`  DECIMAL(18,6)   COMMENT '实际销售价（$，varchar转decimal，金额）',
    -- 4. 度量列：订货信息（数量为整数）
    `order_qty_sku`       BIGINT          COMMENT '订货数量(SKU)',
    `order_qty_skc`       BIGINT          COMMENT '订货数量(SKC)',
    -- 5. 维度列：时间信息
    `order_date`          DATE            COMMENT '订货日期',
    `est_arrival_date`    DATE            COMMENT '预计到货日期',
    `first_pickup_date`   DATE            COMMENT '首次提货日期',
    `shelf_date`          DATE            COMMENT '上架日期',
    `first_sales_date`    DATE            COMMENT '首次销售日期',
    `first_order_quarter` VARCHAR(20)     COMMENT '首次订货季度',
    `year`                VARCHAR(10)     COMMENT '年份',
    `sales_cycle_label`   VARCHAR(50)     COMMENT '销售周期标签',
    -- 6. 度量列：库存信息（数量为整数）
    `inventory_sku`       BIGINT          COMMENT '库存数量(SKU)',
    `inventory_skc`       BIGINT          COMMENT '库存数量(SKC)',
    `inventory_total`     BIGINT          COMMENT '库存合计',
    `inventory_hz`        BIGINT          COMMENT '杭州库存',
    `inventory_baoshui`   BIGINT          COMMENT '保税库存',
    `inventory_feibao`    BIGINT          COMMENT '非保库存',
    -- 7. 度量列：销售指标（数量/天数为整数，比值为6位小数）
    `sales_cycle_days`    BIGINT          COMMENT '销售周期天数',
    `daily_target`        BIGINT          COMMENT '销售目标(日)',
    `weekly_target`       BIGINT          COMMENT '销售目标(周)',
    `monthly_target`      BIGINT          COMMENT '销售目标(月)',
    `quarterly_target`    BIGINT          COMMENT '销售目标(季)',
    `cum_sales_sku`       BIGINT          COMMENT '销售累计数量(SKU)',
    `cum_sales_skc`       BIGINT          COMMENT '销售累计数量(SKC)',
    `skc_achievement`     DECIMAL(18,6)   COMMENT 'SKC达成率（比值保留6位小数）',
    `actual_sales_days`   BIGINT          COMMENT '实际售卖天数',
    `actual_daily_avg`    BIGINT          COMMENT '实际日均销量',
    -- 8. 度量列：补货预警（数量/天数为整数）
    `replenish_qty`       BIGINT          COMMENT '补货量',
    `turnover_days`       BIGINT          COMMENT '周转天数',
    `safety_days`         BIGINT          COMMENT '安全天数',
    `is_replenish`        VARCHAR(10)     COMMENT '是否补货',
    -- 9. 技术字段
    `sync_time`           DATETIME        COMMENT 'ODS同步时间',
    `insert_date`         DATETIME        COMMENT 'DWD记录插入时间（ETL写入，增量更新用）',
    `update_date`         DATETIME        COMMENT 'DWD记录更新时间（ETL写入，增量更新用）'
) ENGINE=OLAP
PRIMARY KEY(`sku`)
COMMENT 'DWD层-韦德商品库清洗表（SKU粒度，无需聚合，日刷新）'
DISTRIBUTED BY HASH(`sku`) BUCKETS 8
PROPERTIES (
    "replication_num" = "1",
    "compression" = "LZ4",
    "enable_persistent_index" = "true",
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "in_memory" = "false",
    "storage_format" = "DEFAULT"
);

INSERT INTO feishu_dwd.dwd_feishu_product_wd_d (
    sku, style_no, ip, series, color_name, product_name, size, product_category,
    tag_price, discount, payment_price, actual_sales_price,
    order_qty_sku, order_qty_skc,
    order_date, est_arrival_date, first_pickup_date, shelf_date, first_sales_date,
    first_order_quarter, year, sales_cycle_label,
    inventory_sku, inventory_skc, inventory_total, inventory_hz, inventory_baoshui, inventory_feibao,
    sales_cycle_days, daily_target, weekly_target, monthly_target, quarterly_target,
    cum_sales_sku, cum_sales_skc, skc_achievement, actual_sales_days, actual_daily_avg,
    replenish_qty, turnover_days, safety_days, is_replenish, sync_time,
    insert_date, update_date
)
SELECT
    SKU,
    款号,
    IP,
    系列,
    配色名,
    商品名称,
    码 AS size,
    商品分类,
    -- 价格（金额类转DECIMAL(18,6)，varchar字段需CAST）
    CAST(吊牌价 AS DECIMAL(18,6)),
    CAST(折扣 AS DECIMAL(18,6)),
    CAST(回款价 AS DECIMAL(18,6)),                       -- 回款价为varchar，转decimal
    CAST(`实际销售价（$）` AS DECIMAL(18,6)),             -- 实际销售价为varchar，转decimal
    -- 订货数量（varchar转BIGINT整数）
    CAST(`订货数量(sku)` AS SIGNED),
    CAST(`订货数量(SKC)` AS SIGNED),
    -- 时间字段
    DATE(订货日期),
    DATE(预计到货日期),
    DATE(首次提货日期),
    DATE(上架日期),
    DATE(首次销售日期),
    首次订货季度,
    年份,
    销售周期标签,
    -- 库存字段（varchar转BIGINT整数）
    CAST(`库存数量(SKU)` AS SIGNED),
    CAST(`库存数量(SKC)` AS SIGNED),
    CAST(库存合计 AS SIGNED),
    CAST(杭州库存 AS SIGNED),
    CAST(保税库存 AS SIGNED),
    CAST(非保库存 AS SIGNED),
    -- 销售指标（天数/数量转BIGINT整数，比值转DECIMAL(18,6)）
    CAST(销售周期天数 AS SIGNED),
    CAST(`销售目标（日）` AS SIGNED),
    CAST(`销售目标（周）` AS SIGNED),
    CAST(`销售目标（月）` AS SIGNED),
    CAST(`销售目标（季）` AS SIGNED),
    CAST(`销售累计数量(SKU)` AS SIGNED),
    CAST(`销售累计数量(SKC)` AS SIGNED),
    CAST(SKC达成率 AS DECIMAL(18,6)),
    CAST(实际售卖天数 AS SIGNED),
    CAST(实际日均销量 AS SIGNED),
    -- 补货预警（数量/天数转BIGINT整数）
    CAST(补货量 AS SIGNED),
    CAST(周转天数 AS SIGNED),
    CAST(安全天数 AS SIGNED),
    是否补货,
    sync_time,
    NOW() AS insert_date,                                -- ETL写入插入时间
    NOW() AS update_date                                 -- ETL写入更新时间
FROM wd_shop
WHERE SKU IS NOT NULL AND SKU <> '';                     -- 过滤空SKU
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
    `sku`                 VARCHAR(64)     COMMENT 'SKU编码（主键）',
    -- 2. 维度列
    `style_no`            VARCHAR(64)     COMMENT '商品货号（款号）',
    `ip`                  VARCHAR(50)     COMMENT 'IP',
    `series`              VARCHAR(50)     COMMENT '系列',
    `product_name`        VARCHAR(200)    COMMENT '商品名称',
    `category`            VARCHAR(50)     COMMENT '品类',
    `size_us`             VARCHAR(20)     COMMENT '美码（尺码）',
    `size_code`           VARCHAR(50)     COMMENT '规格编码',
    -- 3. 度量列
    `tag_price`           DECIMAL(18,6)   COMMENT '吊牌价（金额保留6位小数）',
    -- 4. 维度列：订货信息
    `order_date`          DATE            COMMENT '订货日期',
    `order_qty`           BIGINT          COMMENT '订货数量（varchar转BIGINT整数）',
    `is_ordered`          VARCHAR(10)     COMMENT '是否订过货',
    `order_method`        VARCHAR(50)     COMMENT '下单方式',
    -- 5. 维度列：到货信息
    `est_arrival_month`   VARCHAR(20)     COMMENT '预计到货月份',
    `est_arrival_date`    DATE            COMMENT '预计到货日期',
    `arrival_confirmed`   VARCHAR(10)     COMMENT '到货月份是否确认',
    `brand_confirm_date`  DATE            COMMENT '品牌方确认日期',
    -- 6. 维度列：提货信息
    `plan_pickup_date`    DATE            COMMENT '计划提货日期',
    `first_pickup_date`   DATE            COMMENT '首次提货日期（ODS为varchar，CAST为DATE，异常值置NULL）',
    `picked_qty`          BIGINT          COMMENT '已提数量（varchar转BIGINT整数）',
    `unpicked_qty`        BIGINT          COMMENT '未提可提数量（varchar转BIGINT整数）',
    -- 7. 维度列：上架信息
    `est_shelf_month`     VARCHAR(20)     COMMENT '预计上架月份',
    `overseas_shelf_date` DATE            COMMENT '海外预计上架时间',
    `actual_shelf_date`   DATE            COMMENT '实际上架时间',
    `is_on_shelf`         VARCHAR(10)     COMMENT '是否上架',
    -- 8. 维度列：运营
    `material_status`     VARCHAR(50)     COMMENT '素材情况',
    `image_status`        VARCHAR(50)     COMMENT '图片完成情况',
    `first_order_quarter` VARCHAR(20)     COMMENT '首次订货到货季度',
    -- 9. 技术字段
    `sync_time`           DATETIME        COMMENT 'ODS同步时间',
    `insert_date`         DATETIME        COMMENT 'DWD记录插入时间（ETL写入，增量更新用）',
    `update_date`         DATETIME        COMMENT 'DWD记录更新时间（ETL写入，增量更新用）'
) ENGINE=OLAP
PRIMARY KEY(`sku`)
COMMENT 'DWD层-361商品库清洗表（SKU粒度，无需聚合，日刷新）'
DISTRIBUTED BY HASH(`sku`) BUCKETS 8
PROPERTIES (
    "replication_num" = "1",
    "compression" = "LZ4",
    "enable_persistent_index" = "true",
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "in_memory" = "false",
    "storage_format" = "DEFAULT"
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
    SKU,
    商品货号 AS style_no,
    IP,
    系列,
    商品名称,
    品类,
    美码 AS size_us,
    规格编码 AS size_code,
    CAST(吊牌价 AS DECIMAL(18,6)),                       -- 金额保留6位小数
    -- 订货信息
    DATE(订货日期),
    CAST(订货数量 AS SIGNED),                            -- varchar转BIGINT整数
    是否订过货,
    下单方式,
    -- 到货信息
    预计到货月份,
    DATE(预计到货日期),
    到货月份是否确认,
    DATE(品牌方确认日期),
    -- 提货信息
    DATE(计划提货日期),
    DATE(首次提货日期),                                  -- ODS为varchar，转DATE，异常值自动置NULL
    CAST(已提数量 AS SIGNED),                            -- varchar转BIGINT整数
    CAST(未提可提数量 AS SIGNED),                        -- varchar转BIGINT整数
    -- 上架信息
    预计上架月份,
    DATE(海外预计上架时间),
    DATE(实际上架时间),
    是否上架,
    -- 运营
    素材情况,
    图片完成情况,
    首次订货到货季度,
    sync_time,
    NOW() AS insert_date,                                -- ETL写入插入时间
    NOW() AS update_date                                 -- ETL写入更新时间
FROM t_361_shop
WHERE SKU IS NOT NULL AND SKU <> '';                     -- 过滤空SKU（577条空SKU被过滤）
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
    `sku`                 VARCHAR(64)     COMMENT 'SKU编码（主键组成部分）',
    `brand`               VARCHAR(20)     COMMENT '品牌：361 / 韦德（主键组成部分，区分来源）',
    -- 2. 维度列
    `style_no`            VARCHAR(64)     COMMENT '款号/商品货号',
    `ip`                  VARCHAR(50)     COMMENT 'IP',
    `series`              VARCHAR(50)     COMMENT '系列',
    `color_name`          VARCHAR(50)     COMMENT '配色名（韦德有，361为空）',
    `product_name`        VARCHAR(200)    COMMENT '商品名称',
    `category`            VARCHAR(50)     COMMENT '品类/商品分类',
    `size`                VARCHAR(20)     COMMENT '尺码（韦德码/361美码统一）',
    -- 3. 度量列
    `tag_price`           DECIMAL(18,6)   COMMENT '吊牌价（金额保留6位小数）',
    `order_qty`           BIGINT          COMMENT '订货数量（统一为SKU维度，整数）',
    -- 4. 维度列：订货/上架/销售时间（统一口径）
    `order_date`          DATE            COMMENT '订货日期',
    `shelf_date`          DATE            COMMENT '上架日期（统一口径：韦德取shelf_date，361取actual_shelf_date）',
    `first_sales_date`    DATE            COMMENT '首次销售日期（韦德有，361为空）',
    `first_order_quarter` VARCHAR(20)     COMMENT '首次订货季度',
    `year`                VARCHAR(10)     COMMENT '年份（韦德有，361为空）',
    -- 5. 度量列：库存信息（韦德有详细库存，361为空）
    `inventory_sku`       BIGINT          COMMENT '库存数量(SKU)（韦德有，361为空，整数）',
    -- 6. 技术字段
    `sync_time`           DATETIME        COMMENT 'ODS同步时间',
    `insert_date`         DATETIME        COMMENT 'DWD记录插入时间（ETL写入，增量更新用）',
    `update_date`         DATETIME        COMMENT 'DWD记录更新时间（ETL写入，增量更新用）'
) ENGINE=OLAP
PRIMARY KEY(`sku`, `brand`)
COMMENT 'DWD层-统一商品库表（361+韦德，SKU+品牌粒度，核心字段统一，日刷新）'
DISTRIBUTED BY HASH(`sku`) BUCKETS 8
PROPERTIES (
    "replication_num" = "1",
    "compression" = "LZ4",
    "enable_persistent_index" = "true",
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "in_memory" = "false",
    "storage_format" = "DEFAULT"
);

-- 韦德商品库（来源DWD-4）
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku, sync_time,
    insert_date, update_date
)
SELECT
    sku, '韦德' AS brand, style_no, ip, series, color_name, product_name,
    product_category AS category, size,                                 -- 韦德 product_category → 统一 category
    tag_price,
    order_qty_sku AS order_qty,                          -- 统一为SKU维度订货量
    order_date,
    shelf_date,                                          -- 韦德直接取上架日期
    first_sales_date,
    first_order_quarter,
    year,
    inventory_sku,
    sync_time,
    NOW() AS insert_date,                                -- ETL写入插入时间
    NOW() AS update_date                                 -- ETL写入更新时间
FROM feishu_dwd.dwd_feishu_product_wd_d
WHERE sku IS NOT NULL;

-- 361商品库（来源DWD-5）
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku, sync_time,
    insert_date, update_date
)
SELECT
    sku, '361' AS brand, style_no, ip, series,
    NULL AS color_name,                                  -- 361无配色名
    product_name,
    category,
    size_us AS size,                                     -- 361用美码作为统一尺码
    tag_price,
    order_qty,
    order_date,
    actual_shelf_date AS shelf_date,                     -- 361取实际上架时间作为统一上架日期
    NULL AS first_sales_date,                            -- 361商品库无首次销售日期（在销售表中）
    first_order_quarter,
    NULL AS year,                                        -- 361商品库无年份字段
    NULL AS inventory_sku,                               -- 361商品库无SKU维度库存
    sync_time,
    NOW() AS insert_date,
    NOW() AS update_date
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
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_inventory_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_inventory_d (
    -- 1. Key 列（前 N 列，顺序与 PRIMARY KEY 一致；inventory_date 须为 Key 列以支持分区）
    `id`                  BIGINT          COMMENT '自增主键（来源ODS的id）',
    `inventory_date`      DATE            COMMENT '品牌方库存更新日期（分区键）',
    -- 2. 维度列
    `record_id`           VARCHAR(64)     COMMENT '飞书记录唯一ID',
    `sku`                 VARCHAR(64)     COMMENT 'sku编码（ODS小写sku，注意与SKU区分）',
    `style_no`            VARCHAR(64)     COMMENT '款号',
    `quarter`             VARCHAR(20)     COMMENT '季度',
    `ip`                  VARCHAR(50)     COMMENT 'IP',
    `product_name`        VARCHAR(200)    COMMENT '品名',
    `series`              VARCHAR(50)     COMMENT '系列',
    `color_name`          VARCHAR(50)     COMMENT '配色名',
    `category`            VARCHAR(50)     COMMENT '商品类别',
    `size`                VARCHAR(20)     COMMENT '尺码',
    -- 3. 度量列：库存指标（数量为整数，金额保留6位小数）
    `inventory_qty`       BIGINT          COMMENT '库存数量（整数）',
    `price_with_tax`      DECIMAL(18,6)   COMMENT '含税单价（金额保留6位小数）',
    `tag_price`           DECIMAL(18,6)   COMMENT '吊牌价（金额保留6位小数）',
    `order_qty`           BIGINT          COMMENT '订货数量（varchar转BIGINT整数）',
    `picked_qty`          BIGINT          COMMENT '已提数量（varchar转BIGINT整数）',
    `unpicked_qty`        BIGINT          COMMENT '未提数量（varchar转BIGINT整数）',
    -- 4. 维度列：业务标识
    `pickup_flag`         VARCHAR(50)     COMMENT '提货标识',
    `min_granularity`     VARCHAR(100)    COMMENT '最小颗粒度',
    -- 5. 技术字段
    `sync_time`           DATETIME        COMMENT 'ODS同步时间',
    `insert_date`         DATETIME        COMMENT 'DWD记录插入时间（ETL写入，增量更新用）',
    `update_date`         DATETIME        COMMENT 'DWD记录更新时间（ETL写入，增量更新用）'
) ENGINE=OLAP
PRIMARY KEY(`id`, `inventory_date`)
COMMENT 'DWD层-品牌方库存清洗表（SKU+日期粒度，日刷新）'
PARTITION BY RANGE(`inventory_date`) ()
DISTRIBUTED BY HASH(`id`) BUCKETS 8
PROPERTIES (
    "replication_num" = "1",
    "compression" = "LZ4",
    "in_memory" = "false",
    "storage_format" = "DEFAULT",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.create_history_partition" = "true"
);

INSERT INTO feishu_dwd.dwd_feishu_inventory_d (
    id, inventory_date, record_id, sku, style_no, quarter, ip, product_name, series,
    color_name, category, size,
    inventory_qty, price_with_tax, tag_price, order_qty, picked_qty, unpicked_qty,
    pickup_flag, min_granularity, sync_time, insert_date, update_date
)
SELECT
    id,
    DATE(品牌方库存更新日期) AS inventory_date,
    record_id,
    sku,                                                 -- 注意：小写sku
    款号 AS style_no,
    季度 AS quarter,
    IP,
    品名 AS product_name,
    系列 AS series,
    配色名 AS color_name,
    商品类别 AS category,
    尺码 AS size,
    -- 库存指标（数量转BIGINT整数，金额转DECIMAL(18,6)）
    CAST(库存数量 AS SIGNED),
    CAST(含税单价 AS DECIMAL(18,6)),
    CAST(吊牌价 AS DECIMAL(18,6)),
    CAST(订货数量 AS SIGNED),                            -- varchar转BIGINT整数
    CAST(已提数量 AS SIGNED),                            -- varchar转BIGINT整数
    CAST(未提数量 AS SIGNED),                            -- varchar转BIGINT整数
    提货标识 AS pickup_flag,
    最小颗粒度 AS min_granularity,
    sync_time,
    NOW() AS insert_date,                                -- ETL写入插入时间
    NOW() AS update_date                                 -- ETL写入更新时间
FROM wd_pinpaikucun
WHERE sku IS NOT NULL AND sku <> '';                     -- 过滤空sku
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
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_otb_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_otb_d (
    -- 1. Key 列（PRIMARY KEY 模型，ip+year 为业务主键，须为前 N 列）
    `ip`                  VARCHAR(50)     COMMENT 'IP（主键组成部分）',
    `year`                VARCHAR(10)     COMMENT '年度（主键组成部分）',
    -- 2. 维度列
    `id`                  BIGINT          COMMENT '自增主键（来源ODS的id，溯源用）',
    `record_id`           VARCHAR(64)     COMMENT '飞书记录唯一ID（溯源用）',
    -- 3. 度量列（金额/比值保留6位小数）
    `otb_amount_yi`       DECIMAL(18,6)   COMMENT 'OTB金额（单位：亿，原decimal字段，如2.000000）',
    `order_amount_ratio`  DECIMAL(18,6)   COMMENT '订货金额占比（比值保留6位小数）',
    `order_tag_price`     DECIMAL(18,6)   COMMENT '订货牌价（varchar转DECIMAL(18,6)，金额）',
    `otb_raw`             DECIMAL(18,6)   COMMENT 'OTB原始值（varchar转DECIMAL(18,6)，如7.02，与otb_amount_yi语义不同）',
    -- 4. 技术字段
    `sync_time`           DATETIME        COMMENT 'ODS同步时间',
    `insert_date`         DATETIME        COMMENT 'DWD记录插入时间（ETL写入，增量更新用）',
    `update_date`         DATETIME        COMMENT 'DWD记录更新时间（ETL写入，增量更新用）'
) ENGINE=OLAP
PRIMARY KEY(`ip`, `year`)
COMMENT 'DWD层-OTB订货计划清洗表（IP+年度粒度，全字段保留，日刷新）'
DISTRIBUTED BY HASH(`ip`) BUCKETS 4
PROPERTIES (
    "replication_num" = "1",
    "compression" = "LZ4",
    "enable_persistent_index" = "true",
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "in_memory" = "false",
    "storage_format" = "DEFAULT"
);

INSERT INTO feishu_dwd.dwd_feishu_otb_d (
    ip, year, id, record_id,
    otb_amount_yi, order_amount_ratio, order_tag_price, otb_raw,
    sync_time, insert_date, update_date
)
SELECT
    IP,
    年度 AS year,
    id,
    record_id,
    CAST(`OTB（单位：亿）` AS DECIMAL(18,6)),            -- decimal转DECIMAL(18,6)，单位：亿（如2.000000）
    CAST(订货金额占比 AS DECIMAL(18,6)),                 -- decimal转DECIMAL(18,6)，比值（如0.019400）
    CAST(订货牌价 AS DECIMAL(18,6)),                     -- varchar转DECIMAL(18,6)，金额（如7129800）
    CAST(OTB AS DECIMAL(18,6)),                          -- varchar转DECIMAL(18,6)，原始值（如7.02，与otb_amount_yi语义不同）
    sync_time,
    NOW() AS insert_date,                                -- ETL写入插入时间
    NOW() AS update_date                                 -- ETL写入更新时间
FROM wd_otb
WHERE record_id IS NOT NULL
  AND IP IS NOT NULL
  AND 年度 IS NOT NULL;
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
