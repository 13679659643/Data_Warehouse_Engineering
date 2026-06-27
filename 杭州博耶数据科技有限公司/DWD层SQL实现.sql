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

-- 建库（如不存在）
CREATE DATABASE IF NOT EXISTS feishu_dwd;


-- ============================================================
-- DWD-1: feishu_dwd.dwd_feishu_sales_361_d  361品牌销售日明细表(日刷新)
-- 来源：feishu.t_361sales_01 ~ feishu.t_361sales_50(50张分表)
-- 粒度：品牌 + SKU + 销售日期(宽表形态，每渠道一列)
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型，按 sales_date 动态分区
-- 主键：record_id(飞书唯一ID,全局唯一) + sales_date(分区键)
-- ============================================================

-- 方案一：物化表
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_sales_361_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_361_d (
    `record_id`       VARCHAR(64)     COMMENT "飞书记录唯一ID(主键,去重依据)",
    `sales_date`      DATE            COMMENT "销售日期(主键,分区键)",
    `id`              BIGINT          COMMENT "自增主键(来源ODS的id,溯源用)",
    `brand`           VARCHAR(20)     COMMENT "品牌:361(DWD新增字段)",
    `sku`             VARCHAR(64)     COMMENT "SKU编码",
    `qty_361sport`    BIGINT          COMMENT "361sport渠道销量",
    `qty_china`       BIGINT          COMMENT "中国公司(361客户)渠道销量",
    `qty_sample`      BIGINT          COMMENT "361寄样渠道销量",
    `qty_staff_hk`    BIGINT          COMMENT "员工内购(香港)渠道销量",
    `amt_361sport`    DECIMAL(18,6)   COMMENT "361sport渠道金额",
    `amt_china`       DECIMAL(18,6)   COMMENT "中国公司(361客户)渠道金额",
    `amt_sample`      DECIMAL(18,6)   COMMENT "361寄样渠道金额",
    `amt_staff_hk`    DECIMAL(18,6)   COMMENT "员工内购(香港)渠道金额",
    `sync_time`       DATETIME        COMMENT "ODS同步时间",
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

-- 合并50张分表(结构一致，直接UNION ALL)
-- 模板：t_361sales_01，其余分表套用同一SELECT，仅改FROM表名
INSERT INTO feishu_dwd.dwd_feishu_sales_361_d (
    id, record_id, brand, sku, sales_date,
    qty_361sport, qty_china, qty_sample, qty_staff_hk,
    amt_361sport, amt_china, amt_sample, amt_staff_hk,
    sync_time, insert_date, update_date
)
SELECT
    id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    '361' AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`361寄样-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`361寄样-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    NOW(),
    NOW()
FROM feishu.t_361sales_01
WHERE record_id IS NOT NULL
UNION ALL
SELECT id, COALESCE(NULLIF(TRIM(record_id), ''), 'None'), '361', COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`361寄样-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`361寄样-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)), NOW(), NOW()
FROM feishu.t_361sales_02 WHERE record_id IS NOT NULL
-- ... 依次 UNION ALL feishu.t_361sales_03 ~ feishu.t_361sales_49 ...
UNION ALL
SELECT id, COALESCE(NULLIF(TRIM(record_id), ''), 'None'), '361', COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`361寄样-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`361寄样-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)), NOW(), NOW()
FROM feishu.t_361sales_50 WHERE record_id IS NOT NULL;

-- 方案二：视图(不落物化表，查询时实时UNION ALL 50张分表)
DROP VIEW IF EXISTS feishu_dwd.v_feishu_sales_361_d;
CREATE VIEW feishu_dwd.v_feishu_sales_361_d AS
SELECT
    id, COALESCE(NULLIF(TRIM(record_id), ''), 'None') AS record_id,
    '361' AS brand, COALESCE(NULLIF(TRIM(SKU), ''), 'None') AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')) AS sales_date,
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0) AS qty_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-销量`), '') AS SIGNED), 0) AS qty_china,
    COALESCE(CAST(NULLIF(TRIM(`361寄样-销量`), '') AS SIGNED), 0) AS qty_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-销量`), '') AS SIGNED), 0) AS qty_staff_hk,
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0) AS amt_361sport,
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_china,
    COALESCE(CAST(NULLIF(TRIM(`361寄样-金额`), '') AS DECIMAL(18,6)), 0) AS amt_sample,
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_staff_hk,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS insert_date,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS update_date
FROM feishu.t_361sales_01 WHERE record_id IS NOT NULL
UNION ALL
SELECT id, COALESCE(NULLIF(TRIM(record_id), ''), 'None'), '361', COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`361寄样-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`361寄样-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))
FROM feishu.t_361sales_02 WHERE record_id IS NOT NULL
-- ... 依次 UNION ALL feishu.t_361sales_03 ~ feishu.t_361sales_49 ...
UNION ALL
SELECT id, COALESCE(NULLIF(TRIM(record_id), ''), 'None'), '361', COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),
    COALESCE(CAST(NULLIF(TRIM(`361sport-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`361寄样-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`361sport-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`中国公司(361客户)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`361寄样-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`员工内购(香港)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))
FROM feishu.t_361sales_50 WHERE record_id IS NOT NULL;


-- ============================================================
-- DWD-2: feishu_dwd.dwd_feishu_sales_wd_d  韦德品牌销售日明细表(日刷新)
-- 来源：feishu.wd_sales_01 ~ feishu.wd_sales_50(50张分表，结构不一致)
-- 难点：wd_sales分表结构差异(06:55字段/23:47字段/30,50:41字段)
-- 解决：以wd_sales_06为超集基准，缺失字段补默认值(数值=0，字符="None"，日期=1970-01-01)
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型，按 sales_date 动态分区
-- 主键：record_id(飞书唯一ID,全局唯一) + sales_date(分区键)
-- ============================================================

DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_sales_wd_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_wd_d (
    `record_id`           VARCHAR(64)     COMMENT "飞书记录唯一ID(主键,去重依据)",
    `sales_date`          DATE            COMMENT "销售日期(主键,分区键)",
    `id`                  BIGINT          COMMENT "自增主键(来源ODS的id,溯源用)",
    `brand`               VARCHAR(20)     COMMENT "品牌:韦德(DWD新增字段)",
    `sku`                 VARCHAR(64)     COMMENT "SKU编码",
    `style_no`            VARCHAR(64)     COMMENT "款号(仅06/23有，其余为None)",
    `size`                VARCHAR(20)     COMMENT "尺码(仅06/23有，其余为None)",
    `first_sales_date`    DATE            COMMENT "首次销售日期(仅06/23有，其余为1970-01-01)",
    `sales_week`          VARCHAR(20)     COMMENT "销售周期所属周(仅06/23有，其余为None)",
    `order_replenish_1`   BIGINT          COMMENT "订货+补货1(仅06有)",
    `order_replenish`     BIGINT          COMMENT "订货+补货(仅06有)",
    `actual_total_qty`    BIGINT          COMMENT "实际总销量(仅06有)",
    `est_cycle_days`      BIGINT          COMMENT "预计销售周期天数(仅06有)",
    `est_week_qty`        BIGINT          COMMENT "预计周销量(仅06有)",
    `est_qty`             BIGINT          COMMENT "预计销量(仅06有)",
    `actual_week_qty`     BIGINT          COMMENT "实际周销量(仅06有)",
    `actual_qty`          BIGINT          COMMENT "实际销量(06为decimal,23为varchar,30/50无)",
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
    `total_sum`           DECIMAL(18,6)   COMMENT "总和",
    `total_sum_copy`      DECIMAL(18,6)   COMMENT "总和副本(仅06有)",
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

-- 类型A：wd_sales_06(55字段，最全)- 直接映射
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
    id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    '韦德' AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),
    COALESCE(NULLIF(TRIM(款号), ''), 'None'),
    COALESCE(NULLIF(TRIM(尺码), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(首次销售日期), '')), DATE('1970-01-01')),
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None'),
    COALESCE(CAST(NULLIF(TRIM(`订货+补货1`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`订货+补货`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(实际总销量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(预计销售周期天数), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(预计周销量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(预计销量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(实际周销量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`总和 副本`), '') AS DECIMAL(18,6)), 0),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    'wd_sales_06', NOW(), NOW()
FROM feishu.wd_sales_06
WHERE record_id IS NOT NULL;

-- 类型B：wd_sales_23(47字段)- 缺7个销售指标，"实际销量"为varchar，无"总和副本"
-- 缺失字段用默认值(数值=0，字符="None")
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
    id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    '韦德', COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),
    COALESCE(NULLIF(TRIM(款号), ''), 'None'),
    COALESCE(NULLIF(TRIM(尺码), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(首次销售日期), '')), DATE('1970-01-01')),
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None'),
    0, 0, 0, 0, 0, 0, 0,                                   -- 7个缺失销售指标=0
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS SIGNED), 0),  -- 23分表"实际销量"为varchar
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0),
    0,                                                       -- "总和副本"缺失=0
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    'wd_sales_23', NOW(), NOW()
FROM feishu.wd_sales_23
WHERE record_id IS NOT NULL;

-- 类型C：wd_sales_30/50(41字段，精简版)- 缺款号/尺码/首次销售日期/销售周期/8个销售指标/总和/总和副本
-- 缺失字段用默认值(数值=0，字符="None"，日期=1970-01-01)
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
    id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    '韦德', COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),
    'None', 'None',                                          -- 款号/尺码缺失
    DATE('1970-01-01'), 'None',                              -- 首次销售日期/销售周期缺失
    0, 0, 0, 0, 0, 0, 0, 0,                                 -- 8个销售指标全缺失=0
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0),
    0, 0,                                                    -- 总和/总和副本缺失=0
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    'wd_sales_30', NOW(), NOW()
FROM feishu.wd_sales_30
WHERE record_id IS NOT NULL;

-- wd_sales_50 与 wd_sales_30 结构相同，套用上述INSERT，source_table改为'wd_sales_50'
-- INSERT INTO feishu_dwd.dwd_feishu_sales_wd_d ... FROM feishu.wd_sales_50 ... 'wd_sales_50', NOW(), NOW();

-- 注：wd_sales_01~05, 07~22, 24~29, 31~49 的具体结构需根据实际分表确认，
--     若与06/23/30/50之一相同则套用对应模板；若结构有差异，按超集对齐原则补默认值。
--     确认SQL：
--     SELECT table_name, COUNT(*) AS col_cnt
--     FROM information_schema.columns
--     WHERE table_name LIKE 'wd_sales_%' AND table_schema = 'feishu'
--     GROUP BY table_name ORDER BY table_name;

-- 方案二：视图(不落物化表，查询时实时UNION ALL 50张分表，结构对齐)
-- 视图结构与物化表方案一的SELECT一致，此处以06/23/30为例
DROP VIEW IF EXISTS feishu_dwd.v_feishu_sales_wd_d;
CREATE VIEW feishu_dwd.v_feishu_sales_wd_d AS
-- 类型A：wd_sales_06(最全)
SELECT
    id, COALESCE(NULLIF(TRIM(record_id), ''), 'None') AS record_id,
    '韦德' AS brand, COALESCE(NULLIF(TRIM(SKU), ''), 'None') AS sku,
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')) AS sales_date,
    COALESCE(NULLIF(TRIM(款号), ''), 'None') AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None') AS size,
    COALESCE(DATE(NULLIF(TRIM(首次销售日期), '')), DATE('1970-01-01')) AS first_sales_date,
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None') AS sales_week,
    COALESCE(CAST(NULLIF(TRIM(`订货+补货1`), '') AS SIGNED), 0) AS order_replenish_1,
    COALESCE(CAST(NULLIF(TRIM(`订货+补货`), '') AS SIGNED), 0) AS order_replenish,
    COALESCE(CAST(NULLIF(TRIM(实际总销量), '') AS SIGNED), 0) AS actual_total_qty,
    COALESCE(CAST(NULLIF(TRIM(预计销售周期天数), '') AS SIGNED), 0) AS est_cycle_days,
    COALESCE(CAST(NULLIF(TRIM(预计周销量), '') AS SIGNED), 0) AS est_week_qty,
    COALESCE(CAST(NULLIF(TRIM(预计销量), '') AS SIGNED), 0) AS est_qty,
    COALESCE(CAST(NULLIF(TRIM(实际周销量), '') AS SIGNED), 0) AS actual_week_qty,
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS SIGNED), 0) AS actual_qty,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0) AS qty_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0) AS qty_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0) AS qty_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0) AS qty_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0) AS qty_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0) AS qty_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0) AS qty_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0) AS qty_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0) AS qty_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0) AS qty_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0) AS qty_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0) AS qty_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0) AS qty_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0) AS qty_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0) AS qty_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0) AS qty_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0) AS qty_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0) AS qty_b2b,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0) AS amt_wd,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0) AS amt_wd_sample,
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0) AS amt_dewu,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0) AS amt_dewu_consign,
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0) AS amt_95fen,
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0) AS amt_guangdong,
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0) AS amt_quanyong,
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0) AS amt_yingkedi,
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0) AS amt_offline,
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0) AS amt_japan,
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0) AS amt_spanish,
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0) AS amt_weihong,
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0) AS amt_95fen_shop,
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0) AS amt_pdd,
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0) AS amt_ebay,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0) AS amt_entertainment,
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0) AS amt_germany,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0) AS amt_b2b,
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0) AS total_sum,
    COALESCE(CAST(NULLIF(TRIM(`总和 副本`), '') AS DECIMAL(18,6)), 0) AS total_sum_copy,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    'wd_sales_06' AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS insert_date,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS update_date
FROM feishu.wd_sales_06 WHERE record_id IS NOT NULL
UNION ALL
-- 类型B：wd_sales_23(缺失字段补默认值)
SELECT id, COALESCE(NULLIF(TRIM(record_id), ''), 'None'), '韦德', COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),
    COALESCE(NULLIF(TRIM(款号), ''), 'None'), COALESCE(NULLIF(TRIM(尺码), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(首次销售日期), '')), DATE('1970-01-01')),
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None'),
    0, 0, 0, 0, 0, 0, 0,
    COALESCE(CAST(NULLIF(TRIM(实际销量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0), 0,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    'wd_sales_23',
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))
FROM feishu.wd_sales_23 WHERE record_id IS NOT NULL
UNION ALL
-- 类型C：wd_sales_30/50(精简版，缺失字段补默认值)
SELECT id, COALESCE(NULLIF(TRIM(record_id), ''), 'None'), '韦德', COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(销售日期), '')), DATE('1970-01-01')),
    'None', 'None', DATE('1970-01-01'), 'None',
    0, 0, 0, 0, 0, 0, 0, 0,
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`eBay-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-销量`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道寄样-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP_韦德-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道-得物寄售-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`得物APP转寄_95分-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`广东炫动商贸有限公司(李宁客户)-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`全勇分销-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`应科迪_客户-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德线下店铺-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德日本站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德西语站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`dw_韦德伟宏店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德_95分店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`拼多多_博耶运动户外专营店-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`eBay-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道--招待费-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德德国站-金额`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`韦德之道B2B-金额`), '') AS DECIMAL(18,6)), 0),
    0, 0,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    'wd_sales_30',
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))
FROM feishu.wd_sales_30 WHERE record_id IS NOT NULL;
-- wd_sales_50 同 wd_sales_30，UNION ALL 时 source_table 改为 'wd_sales_50'


-- ============================================================
-- DWD-3: feishu_dwd.dwd_feishu_sales_all_d  统一销售日明细表(长表,日刷新)
-- 来源：feishu_dwd.dwd_feishu_sales_361_d + feishu_dwd.dwd_feishu_sales_wd_d
-- 粒度：品牌 + SKU + 销售日期 + 渠道(每条记录=一个渠道的一笔销售)
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型，按 sales_date 动态分区
-- 主键：record_id(飞书唯一ID) + sales_date(分区键) + channel_code(渠道,同一record_id多渠道)
-- ============================================================

DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_sales_all_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_all_d (
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
    `qty`                 BIGINT          COMMENT "销量(件/双,整数)",
    `amt`                 DECIMAL(18,6)   COMMENT "金额(元,保留6位小数)",
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
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

-- 361品牌数据(4个渠道转行，361无first_sales_date用1970-01-01，无style_no/size用None)
INSERT INTO feishu_dwd.dwd_feishu_sales_all_d (
    id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
    channel_code, channel_name, channel_type, qty, amt, sync_time, insert_date, update_date
)
SELECT id, sales_date, record_id, brand, sku, 'None', 'None', DATE('1970-01-01'),
       '361sport', '361sport', '自营',
       qty_361sport, amt_361sport, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_361_d
WHERE qty_361sport <> 0 OR amt_361sport <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, 'None', 'None', DATE('1970-01-01'),
       'china_company', '中国公司(361客户)', '自营',
       qty_china, amt_china, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_361_d
WHERE qty_china <> 0 OR amt_china <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, 'None', 'None', DATE('1970-01-01'),
       '361_sample', '361寄样', '寄售',
       qty_sample, amt_sample, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_361_d
WHERE qty_sample <> 0 OR amt_sample <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, 'None', 'None', DATE('1970-01-01'),
       'staff_hk', '员工内购(香港)', '自营',
       qty_staff_hk, amt_staff_hk, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_361_d
WHERE qty_staff_hk <> 0 OR amt_staff_hk <> 0;

-- 韦德品牌数据(18个渠道转行)
INSERT INTO feishu_dwd.dwd_feishu_sales_all_d (
    id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
    channel_code, channel_name, channel_type, qty, amt, sync_time, insert_date, update_date
)
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'wd', '韦德之道', '自营', qty_wd, amt_wd, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_wd <> 0 OR amt_wd <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'wd_sample', '韦德之道寄样', '寄售', qty_wd_sample, amt_wd_sample, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_wd_sample <> 0 OR amt_wd_sample <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'dewu', '得物APP_韦德', '平台', qty_dewu, amt_dewu, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_dewu <> 0 OR amt_dewu <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'dewu_consign', '韦德之道-得物寄售', '寄售', qty_dewu_consign, amt_dewu_consign, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_dewu_consign <> 0 OR amt_dewu_consign <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       '95fen', '得物APP转寄_95分', '平台', qty_95fen, amt_95fen, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_95fen <> 0 OR amt_95fen <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'guangdong', '广东炫动商贸(李宁客户)', '分销', qty_guangdong, amt_guangdong, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_guangdong <> 0 OR amt_guangdong <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'quanyong', '全勇分销', '分销', qty_quanyong, amt_quanyong, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_quanyong <> 0 OR amt_quanyong <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'yingkedi', '应科迪_客户', '分销', qty_yingkedi, amt_yingkedi, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_yingkedi <> 0 OR amt_yingkedi <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'offline', '韦德线下店铺', '自营', qty_offline, amt_offline, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_offline <> 0 OR amt_offline <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'japan', '韦德日本站', '海外', qty_japan, amt_japan, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_japan <> 0 OR amt_japan <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'spanish', '韦德西语站', '海外', qty_spanish, amt_spanish, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_spanish <> 0 OR amt_spanish <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'weihong', 'dw_韦德伟宏店', '自营', qty_weihong, amt_weihong, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_weihong <> 0 OR amt_weihong <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       '95fen_shop', '韦德_95分店', '平台', qty_95fen_shop, amt_95fen_shop, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_95fen_shop <> 0 OR amt_95fen_shop <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'pdd', '拼多多_博耶运动户外专营店', '平台', qty_pdd, amt_pdd, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_pdd <> 0 OR amt_pdd <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'ebay', 'eBay', '海外', qty_ebay, amt_ebay, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_ebay <> 0 OR amt_ebay <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'entertainment', '韦德之道--招待费', '其他', qty_entertainment, amt_entertainment, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_entertainment <> 0 OR amt_entertainment <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'germany', '韦德德国站', '海外', qty_germany, amt_germany, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_germany <> 0 OR amt_germany <> 0
UNION ALL
SELECT id, sales_date, record_id, brand, sku, style_no, size, first_sales_date,
       'b2b', '韦德之道B2B', '分销', qty_b2b, amt_b2b, sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_wd_d WHERE qty_b2b <> 0 OR amt_b2b <> 0;


-- ============================================================
-- DWD-4: feishu_dwd.dwd_feishu_product_wd_d  韦德商品库清洗表(日刷新)
-- 来源：feishu.wd_shop(103字段)
-- 粒度：SKU(主键)，无需聚合(id=record_id=SKU一对一)
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型
-- ============================================================

DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_product_wd_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_product_wd_d (
    `sku`                 VARCHAR(64)     COMMENT "SKU编码(主键)",
    `style_no`            VARCHAR(64)     COMMENT "款号",
    `ip`                  VARCHAR(50)     COMMENT "IP",
    `series`              VARCHAR(50)     COMMENT "系列",
    `color_name`          VARCHAR(50)     COMMENT "配色名",
    `product_name`        VARCHAR(200)    COMMENT "商品名称",
    `size`                VARCHAR(20)     COMMENT "尺码(码)",
    `product_category`    VARCHAR(50)     COMMENT "商品分类",
    `tag_price`           DECIMAL(18,6)   COMMENT "吊牌价",
    `discount`            DECIMAL(18,6)   COMMENT "折扣(比值保留6位小数)",
    `payment_price`       DECIMAL(18,6)   COMMENT "回款价(varchar转decimal)",
    `actual_sales_price`  DECIMAL(18,6)   COMMENT "实际销售价(varchar转decimal)",
    `order_qty_sku`       BIGINT          COMMENT "订货数量(SKU)",
    `order_qty_skc`       BIGINT          COMMENT "订货数量(SKC)",
    `order_date`          DATE            COMMENT "订货日期",
    `est_arrival_date`    DATE            COMMENT "预计到货日期",
    `first_pickup_date`   DATE            COMMENT "首次提货日期",
    `shelf_date`          DATE            COMMENT "上架日期",
    `first_sales_date`    DATE            COMMENT "首次销售日期",
    `first_order_quarter` VARCHAR(20)     COMMENT "首次订货季度",
    `year`                VARCHAR(10)     COMMENT "年份",
    `sales_cycle_label`   VARCHAR(50)     COMMENT "销售周期标签",
    `inventory_sku`       BIGINT          COMMENT "库存数量(SKU)",
    `inventory_skc`       BIGINT          COMMENT "库存数量(SKC)",
    `inventory_total`     BIGINT          COMMENT "库存合计",
    `inventory_hz`        BIGINT          COMMENT "杭州库存",
    `inventory_baoshui`   BIGINT          COMMENT "保税库存",
    `inventory_feibao`    BIGINT          COMMENT "非保库存",
    `sales_cycle_days`    BIGINT          COMMENT "销售周期天数",
    `daily_target`        BIGINT          COMMENT "销售目标(日)",
    `weekly_target`       BIGINT          COMMENT "销售目标(周)",
    `monthly_target`      BIGINT          COMMENT "销售目标(月)",
    `quarterly_target`    BIGINT          COMMENT "销售目标(季)",
    `cum_sales_sku`       BIGINT          COMMENT "销售累计数量(SKU)",
    `cum_sales_skc`       BIGINT          COMMENT "销售累计数量(SKC)",
    `skc_achievement`     DECIMAL(18,6)   COMMENT "SKC达成率(比值保留6位小数)",
    `actual_sales_days`   BIGINT          COMMENT "实际售卖天数",
    `actual_daily_avg`    BIGINT          COMMENT "实际日均销量",
    `replenish_qty`       BIGINT          COMMENT "补货量",
    `turnover_days`       BIGINT          COMMENT "周转天数",
    `safety_days`         BIGINT          COMMENT "安全天数",
    `is_replenish`        VARCHAR(10)     COMMENT "是否补货",
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间(ETL写入)",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`sku`)
COMMENT "DWD层-韦德商品库清洗表(SKU粒度,无需聚合,日刷新)"
DISTRIBUTED BY HASH(`sku`)
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", -- PK模型专属优化，开启
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
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
    COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(NULLIF(TRIM(款号), ''), 'None'),
    COALESCE(NULLIF(TRIM(IP), ''), 'None'),
    COALESCE(NULLIF(TRIM(系列), ''), 'None'),
    COALESCE(NULLIF(TRIM(配色名), ''), 'None'),
    COALESCE(NULLIF(TRIM(商品名称), ''), 'None'),
    COALESCE(NULLIF(TRIM(码), ''), 'None'),
    COALESCE(NULLIF(TRIM(商品分类), ''), 'None'),
    COALESCE(CAST(NULLIF(TRIM(吊牌价), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(折扣), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(回款价), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`实际销售价($)`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(`订货数量(sku)`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`订货数量(SKC)`), '') AS SIGNED), 0),
    COALESCE(DATE(NULLIF(TRIM(订货日期), '')), DATE('1970-01-01')),
    COALESCE(DATE(NULLIF(TRIM(预计到货日期), '')), DATE('1970-01-01')),
    COALESCE(DATE(NULLIF(TRIM(首次提货日期), '')), DATE('1970-01-01')),
    COALESCE(DATE(NULLIF(TRIM(上架日期), '')), DATE('1970-01-01')),
    COALESCE(DATE(NULLIF(TRIM(首次销售日期), '')), DATE('1970-01-01')),
    COALESCE(NULLIF(TRIM(首次订货季度), ''), 'None'),
    COALESCE(NULLIF(TRIM(年份), ''), 'None'),
    COALESCE(NULLIF(TRIM(销售周期标签), ''), 'None'),
    COALESCE(CAST(NULLIF(TRIM(`库存数量(SKU)`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`库存数量(SKC)`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(库存合计), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(杭州库存), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(保税库存), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(非保库存), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(销售周期天数), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`销售目标(日)`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`销售目标(周)`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`销售目标(月)`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`销售目标(季)`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`销售累计数量(SKU)`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(`销售累计数量(SKC)`), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(SKC达成率), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(实际售卖天数), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(实际日均销量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(补货量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(周转天数), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(安全天数), '') AS SIGNED), 0),
    COALESCE(NULLIF(TRIM(是否补货), ''), 'None'),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    NOW(), NOW()
FROM feishu.wd_shop
WHERE SKU IS NOT NULL AND TRIM(SKU) <> '';


-- ============================================================
-- DWD-5: feishu_dwd.dwd_feishu_product_361_d  361商品库清洗表(日刷新)
-- 来源：feishu.t_361_shop(34字段)
-- 粒度：SKU(主键)，无需聚合(id=record_id=SKU一对一，577条空SKU过滤)
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型
-- ============================================================

DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_product_361_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_product_361_d (
    `sku`                 VARCHAR(64)     COMMENT "SKU编码(主键)",
    `style_no`            VARCHAR(64)     COMMENT "商品货号(款号)",
    `ip`                  VARCHAR(50)     COMMENT "IP",
    `series`              VARCHAR(50)     COMMENT "系列",
    `product_name`        VARCHAR(200)    COMMENT "商品名称",
    `category`            VARCHAR(50)     COMMENT "品类",
    `size_us`             VARCHAR(20)     COMMENT "美码(尺码)",
    `size_code`           VARCHAR(50)     COMMENT "规格编码",
    `tag_price`           DECIMAL(18,6)   COMMENT "吊牌价(金额保留6位小数)",
    `order_date`          DATE            COMMENT "订货日期",
    `order_qty`           BIGINT          COMMENT "订货数量(varchar转BIGINT整数)",
    `is_ordered`          VARCHAR(10)     COMMENT "是否订过货",
    `order_method`        VARCHAR(50)     COMMENT "下单方式",
    `est_arrival_month`   VARCHAR(20)     COMMENT "预计到货月份",
    `est_arrival_date`    DATE            COMMENT "预计到货日期",
    `arrival_confirmed`   VARCHAR(10)     COMMENT "到货月份是否确认",
    `brand_confirm_date`  DATE            COMMENT "品牌方确认日期",
    `plan_pickup_date`    DATE            COMMENT "计划提货日期",
    `first_pickup_date`   DATE            COMMENT "首次提货日期(ODS为varchar,CAST为DATE)",
    `picked_qty`          BIGINT          COMMENT "已提数量(varchar转BIGINT整数)",
    `unpicked_qty`        BIGINT          COMMENT "未提可提数量(varchar转BIGINT整数)",
    `est_shelf_month`     VARCHAR(20)     COMMENT "预计上架月份",
    `overseas_shelf_date` DATE            COMMENT "海外预计上架时间",
    `actual_shelf_date`   DATE            COMMENT "实际上架时间",
    `is_on_shelf`         VARCHAR(10)     COMMENT "是否上架",
    `material_status`     VARCHAR(50)     COMMENT "素材情况",
    `image_status`        VARCHAR(50)     COMMENT "图片完成情况",
    `first_order_quarter` VARCHAR(20)     COMMENT "首次订货到货季度",
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间(ETL写入)",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间(ETL写入)"
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
    COALESCE(NULLIF(TRIM(SKU), ''), 'None'),
    COALESCE(NULLIF(TRIM(商品货号), ''), 'None'),
    COALESCE(NULLIF(TRIM(IP), ''), 'None'),
    COALESCE(NULLIF(TRIM(系列), ''), 'None'),
    COALESCE(NULLIF(TRIM(商品名称), ''), 'None'),
    COALESCE(NULLIF(TRIM(品类), ''), 'None'),
    COALESCE(NULLIF(TRIM(美码), ''), 'None'),
    COALESCE(NULLIF(TRIM(规格编码), ''), 'None'),
    COALESCE(CAST(NULLIF(TRIM(吊牌价), '') AS DECIMAL(18,6)), 0),
    COALESCE(DATE(NULLIF(TRIM(订货日期), '')), DATE('1970-01-01')),
    COALESCE(CAST(NULLIF(TRIM(订货数量), '') AS SIGNED), 0),
    COALESCE(NULLIF(TRIM(是否订过货), ''), 'None'),
    COALESCE(NULLIF(TRIM(下单方式), ''), 'None'),
    COALESCE(NULLIF(TRIM(预计到货月份), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(预计到货日期), '')), DATE('1970-01-01')),
    COALESCE(NULLIF(TRIM(到货月份是否确认), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(品牌方确认日期), '')), DATE('1970-01-01')),
    COALESCE(DATE(NULLIF(TRIM(计划提货日期), '')), DATE('1970-01-01')),
    COALESCE(DATE(NULLIF(TRIM(首次提货日期), '')), DATE('1970-01-01')),
    COALESCE(CAST(NULLIF(TRIM(已提数量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(未提可提数量), '') AS SIGNED), 0),
    COALESCE(NULLIF(TRIM(预计上架月份), ''), 'None'),
    COALESCE(DATE(NULLIF(TRIM(海外预计上架时间), '')), DATE('1970-01-01')),
    COALESCE(DATE(NULLIF(TRIM(实际上架时间), '')), DATE('1970-01-01')),
    COALESCE(NULLIF(TRIM(是否上架), ''), 'None'),
    COALESCE(NULLIF(TRIM(素材情况), ''), 'None'),
    COALESCE(NULLIF(TRIM(图片完成情况), ''), 'None'),
    COALESCE(NULLIF(TRIM(首次订货到货季度), ''), 'None'),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    NOW(), NOW()
FROM feishu.t_361_shop
WHERE SKU IS NOT NULL AND TRIM(SKU) <> '';


-- ============================================================
-- DWD-6: feishu_dwd.dwd_feishu_product_all_d  统一商品库表(SKU粒度,日刷新)
-- 来源：feishu_dwd.dwd_feishu_product_wd_d(DWD-4) + feishu_dwd.dwd_feishu_product_361_d(DWD-5)
-- 粒度：SKU+品牌(主键)，统一361和韦德商品库核心字段
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型(SKU+brand为主键，避免两品牌SKU冲突)
-- ============================================================

DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_product_all_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_product_all_d (
    `sku`                 VARCHAR(64)     COMMENT "SKU编码(主键组成部分)",
    `brand`               VARCHAR(20)     COMMENT "品牌:361/韦德(主键组成部分)",
    `style_no`            VARCHAR(64)     COMMENT "款号/商品货号",
    `ip`                  VARCHAR(50)     COMMENT "IP",
    `series`              VARCHAR(50)     COMMENT "系列",
    `color_name`          VARCHAR(50)     COMMENT "配色名(韦德有,361为None)",
    `product_name`        VARCHAR(200)    COMMENT "商品名称",
    `category`            VARCHAR(50)     COMMENT "品类/商品分类",
    `size`                VARCHAR(20)     COMMENT "尺码(韦德码/361美码统一)",
    `tag_price`           DECIMAL(18,6)   COMMENT "吊牌价(金额保留6位小数)",
    `order_qty`           BIGINT          COMMENT "订货数量(统一为SKU维度,整数)",
    `order_date`          DATE            COMMENT "订货日期",
    `shelf_date`          DATE            COMMENT "上架日期(韦德取shelf_date,361取actual_shelf_date)",
    `first_sales_date`    DATE            COMMENT "首次销售日期(韦德有,361为1970-01-01)",
    `first_order_quarter` VARCHAR(20)     COMMENT "首次订货季度",
    `year`                VARCHAR(10)     COMMENT "年份(韦德有,361为None)",
    `inventory_sku`       BIGINT          COMMENT "库存数量(SKU)(韦德有,361为0)",
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间(ETL写入)",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间(ETL写入)"
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

-- 韦德商品库(来源DWD-4)
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku, sync_time,
    insert_date, update_date
)
SELECT
    sku, '韦德', style_no, ip, series, color_name, product_name,
    product_category, size,
    tag_price, order_qty_sku, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku, sync_time,
    NOW(), NOW()
FROM feishu_dwd.dwd_feishu_product_wd_d
WHERE sku <> 'None';

-- 361商品库(来源DWD-5)
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku, sync_time,
    insert_date, update_date
)
SELECT
    sku, '361', style_no, ip, series,
    'None',                                                  -- 361无配色名
    product_name, category, size_us,
    tag_price, order_qty, order_date,
    actual_shelf_date,                                       -- 361取实际上架时间
    DATE('1970-01-01'),                                      -- 361商品库无首次销售日期
    first_order_quarter,
    'None',                                                  -- 361无年份字段
    0,                                                       -- 361无SKU维度库存
    sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_product_361_d
WHERE sku <> 'None';


-- ============================================================
-- DWD-7: feishu_dwd.dwd_feishu_inventory_d  品牌方库存清洗表(日刷新)
-- 来源：feishu.wd_pinpaikucun(24字段)
-- 粒度：SKU+库存更新日期
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型，按 inventory_date 动态分区
-- 主键：id(来源ODS自增主键,单表唯一) + inventory_date(分区键)
-- 注意：ODS中sku为小写，与其他表SKU(大写)不同，关联时需UPPER(sku)
-- ============================================================

DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_inventory_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_inventory_d (
    `id`                  BIGINT          COMMENT "自增主键(主键,来源ODS的id)",
    `inventory_date`      DATE            COMMENT "品牌方库存更新日期(主键,分区键)",
    `record_id`           VARCHAR(64)     COMMENT "飞书记录唯一ID",
    `sku`                 VARCHAR(64)     COMMENT "sku编码(ODS小写sku,注意与SKU区分)",
    `style_no`            VARCHAR(64)     COMMENT "款号",
    `quarter`             VARCHAR(20)     COMMENT "季度",
    `ip`                  VARCHAR(50)     COMMENT "IP",
    `product_name`        VARCHAR(200)    COMMENT "品名",
    `series`              VARCHAR(50)     COMMENT "系列",
    `color_name`          VARCHAR(50)     COMMENT "配色名",
    `category`            VARCHAR(50)     COMMENT "商品类别",
    `size`                VARCHAR(20)     COMMENT "尺码",
    `inventory_qty`       BIGINT          COMMENT "库存数量(整数)",
    `price_with_tax`      DECIMAL(18,6)   COMMENT "含税单价(金额保留6位小数)",
    `tag_price`           DECIMAL(18,6)   COMMENT "吊牌价(金额保留6位小数)",
    `order_qty`           BIGINT          COMMENT "订货数量(varchar转BIGINT整数)",
    `picked_qty`          BIGINT          COMMENT "已提数量(varchar转BIGINT整数)",
    `unpicked_qty`        BIGINT          COMMENT "未提数量(varchar转BIGINT整数)",
    `pickup_flag`         VARCHAR(50)     COMMENT "提货标识",
    `min_granularity`     VARCHAR(100)    COMMENT "最小颗粒度",
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间(ETL写入)",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间(ETL写入)"
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

INSERT INTO feishu_dwd.dwd_feishu_inventory_d (
    id, inventory_date, record_id, sku, style_no, quarter, ip, product_name, series,
    color_name, category, size,
    inventory_qty, price_with_tax, tag_price, order_qty, picked_qty, unpicked_qty,
    pickup_flag, min_granularity, sync_time, insert_date, update_date
)
SELECT
    id,
    COALESCE(DATE(NULLIF(TRIM(品牌方库存更新日期), '')), DATE('1970-01-01')),
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    COALESCE(NULLIF(TRIM(sku), ''), 'None'),
    COALESCE(NULLIF(TRIM(款号), ''), 'None'),
    COALESCE(NULLIF(TRIM(季度), ''), 'None'),
    COALESCE(NULLIF(TRIM(IP), ''), 'None'),
    COALESCE(NULLIF(TRIM(品名), ''), 'None'),
    COALESCE(NULLIF(TRIM(系列), ''), 'None'),
    COALESCE(NULLIF(TRIM(配色名), ''), 'None'),
    COALESCE(NULLIF(TRIM(商品类别), ''), 'None'),
    COALESCE(NULLIF(TRIM(尺码), ''), 'None'),
    COALESCE(CAST(NULLIF(TRIM(库存数量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(含税单价), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(吊牌价), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(订货数量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(已提数量), '') AS SIGNED), 0),
    COALESCE(CAST(NULLIF(TRIM(未提数量), '') AS SIGNED), 0),
    COALESCE(NULLIF(TRIM(提货标识), ''), 'None'),
    COALESCE(NULLIF(TRIM(最小颗粒度), ''), 'None'),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    NOW(), NOW()
FROM feishu.wd_pinpaikucun
WHERE sku IS NOT NULL AND TRIM(sku) <> '';


-- ============================================================
-- DWD-8: feishu_dwd.dwd_feishu_otb_d  OTB订货计划清洗表(日刷新)
-- 来源：feishu.wd_otb(9字段)
-- 粒度：IP+年度(主键)
-- 说明：OTB(单位:亿)(decimal)与OTB(varchar)语义不同，均保留
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型(IP+year为主键)
-- ============================================================

DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_otb_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_otb_d (
    `ip`                  VARCHAR(50)     COMMENT "IP(主键组成部分)",
    `year`                VARCHAR(10)     COMMENT "年度(主键组成部分)",
    `id`                  BIGINT          COMMENT "自增主键(来源ODS的id,溯源用)",
    `record_id`           VARCHAR(64)     COMMENT "飞书记录唯一ID(溯源用)",
    `otb_amount_yi`       DECIMAL(18,6)   COMMENT "OTB金额(单位:亿,原decimal字段,如2.000000)",
    `order_amount_ratio`  DECIMAL(18,6)   COMMENT "订货金额占比(比值保留6位小数)",
    `order_tag_price`     DECIMAL(18,6)   COMMENT "订货牌价(varchar转DECIMAL,金额)",
    `otb_raw`             DECIMAL(18,6)   COMMENT "OTB原始值(varchar转DECIMAL,如7.02,与otb_amount_yi语义不同)",
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

INSERT INTO feishu_dwd.dwd_feishu_otb_d (
    ip, year, id, record_id,
    otb_amount_yi, order_amount_ratio, order_tag_price, otb_raw,
    sync_time, insert_date, update_date
)
SELECT
    COALESCE(NULLIF(TRIM(IP), ''), 'None'),
    COALESCE(NULLIF(TRIM(年度), ''), 'None'),
    COALESCE(id, 0),
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    COALESCE(CAST(NULLIF(TRIM(`OTB(单位:亿)`), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(订货金额占比), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(订货牌价), '') AS DECIMAL(18,6)), 0),
    COALESCE(CAST(NULLIF(TRIM(OTB), '') AS DECIMAL(18,6)), 0),
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)),
    NOW(), NOW()
FROM feishu.wd_otb
WHERE record_id IS NOT NULL
  AND IP IS NOT NULL
  AND 年度 IS NOT NULL;
