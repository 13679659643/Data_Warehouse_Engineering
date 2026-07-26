# 全流程SQL语句

# 1、建表语句

## DWD层：明细数据层

### feishu\_dwd\.dwd\_feishu\_sales\_361\_d

```SQL
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
```

### feishu\_dwd\.dwd\_feishu\_sales\_wd\_d

#### v1版本：

```JavaScript
-- ============================================================
-- 方案一：物化表（feishu_dwd.dwd_feishu_sales_wd_d）
-- 落地存储，查询性能好，适合下游高频分析与DWS层加工
-- ============================================================
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_sales_wd_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_wd_d (
    -- 1. Key 列（前 N 列，顺序与 DUPLICATE KEY 一致）
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
```

#### v2版本：

```JavaScript
-- ============================================================
        -- 方案一：物化表（feishu_dwd.dwd_feishu_sales_wd_d）
        -- 落地存储，查询性能好，适合下游高频分析与DWS层加工
        -- 遗漏的字段如下：
        -- 自然周 （需补充在维度列中）natural_week
        -- 订货数量 （需补充在销售指标度量列中）order_qty
        -- 达成率 （需补充在销售指标度量列中）achievement_rate
        -- 预警 （需补充在销售指标度量列中）alert
        -- ============================================================
        DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_sales_wd_d;
        CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_wd_d (
            -- 1. Key 列（前 N 列，顺序与 DUPLICATE KEY 一致）
            `record_id`           VARCHAR(64)     COMMENT "飞书记录唯一ID(主键,去重依据)",
            `sales_date`          DATE            COMMENT "销售日期(主键,分区键)",
            `id`                  BIGINT          COMMENT "自增主键(来源ODS的id,溯源用)",
            `brand`               VARCHAR(20)     COMMENT "品牌:韦德(DWD新增字段)",
            `sku`                 VARCHAR(64)     COMMENT "SKU编码",
            -- 2. 维度列
            `style_no`            VARCHAR(64)     COMMENT "款号(存在None)",
            `size`                VARCHAR(20)     COMMENT "尺码(存在None)",
            `first_sales_date`    DATE            COMMENT "首次销售日期(空值为1970-01-01)",
            `natural_week`        VARCHAR(20)     COMMENT "自然周",
            `sales_week`          VARCHAR(20)     COMMENT "销售周期所属周(存在None)",
            -- 3. 度量列：销售指标（仅wd_sales_06完整有，其他分表补NULL）
            `order_replenish_1`   BIGINT          COMMENT "订货+补货1",
            `order_replenish`     BIGINT          COMMENT "订货+补货数量",
            `order_qty`           BIGINT          COMMENT "订货数量",
            `actual_total_qty`    BIGINT          COMMENT "实际总销量",
            `est_cycle_days`      BIGINT          COMMENT "预计销售周期天数",
            `est_week_qty`        BIGINT          COMMENT "预计周销量",
            `est_qty`             BIGINT          COMMENT "预计销量",
            `actual_week_qty`     BIGINT          COMMENT "实际周销量",
            `actual_qty`          BIGINT          COMMENT "实际销量",
            `achievement_rate`    VARCHAR(50)     COMMENT "达成率",
            `alert`               VARCHAR(50)     COMMENT "预警",
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
            `total_sum_copy`      DECIMAL(18,6)   COMMENT "总和副本",
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
```

### feishu\_dwd\.dwd\_feishu\_sales\_all\_d

```SQL
-- ============================================================
-- DWD-3: feishu_dwd.dwd_feishu_sales_all_d  统一销售日明细表（长表结构，日刷新）
-- 来源：feishu_dwd.dwd_feishu_sales_361_d + feishu_dwd.dwd_feishu_sales_wd_d
-- 粒度：品牌 + SKU + 销售日期 + 渠道（每条记录=一个渠道的一笔销售）
-- 设计：将"宽表"（每渠道一列）UNPIVOT为"长表"（渠道转行）
--   设计动因：1) 新增渠道无需改表结构 2) QuickBI聚合简单 3) 便于跨品牌统一分析
-- 引擎：StarRocks OLAP，PRIMARY KEY 模型，按 sales_date 动态分区
-- 主键：record_id(飞书唯一ID) + sales_date(分区键) + channel_code(渠道,同一record_id多渠道)
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
```

### feishu\_dwd\.dwd\_feishu\_product\_wd\_d

```JavaScript
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

```

### feishu\_dwd\.dwd\_feishu\_product\_361\_d

```SQL
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
```

### feishu\_dwd\.dwd\_feishu\_product\_all\_d

```SQL
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_product_all_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_product_all_d (
    -- 1. Key 列（PRIMARY KEY 模型，SKU+brand 为业务主键，须为前 N 列）
    `sku`                 VARCHAR(128)     COMMENT "SKU编码(主键组成部分)",
    `brand`               VARCHAR(20)     COMMENT "品牌:361/韦德(主键组成部分)",
    -- 2. 维度列
    `style_no`            VARCHAR(128)     COMMENT "款号/商品货号",
    `ip`                  VARCHAR(100)     COMMENT "IP(",
    `series`              VARCHAR(100)     COMMENT "系列",
    `color_name`          VARCHAR(100)     COMMENT "配色名（韦德有，361为空）",
    `product_name`        VARCHAR(500)    COMMENT "商品名称",
    `category`            VARCHAR(100)     COMMENT "品类/商品分类",
    `size`                VARCHAR(50)     COMMENT "尺码（韦德码/361美码统一）",
    -- 3. 度量列
    `tag_price`           DECIMAL(18,6)   COMMENT "吊牌价（金额保留6位小数）",
    `order_qty`           BIGINT          COMMENT "订货数量（统一为SKU维度，整数）",
    -- 4. 维度列：订货/上架/销售时间（统一口径）
    `order_date`          DATE            COMMENT "订货日期",
    `shelf_date`          DATE            COMMENT "上架日期（统一口径：韦德取shelf_date，361取actual_shelf_date，空值为null）",
    `first_sales_date`    DATE            COMMENT "首次销售日期（韦德有，361预计算：从销售明细表取最早有销量的日期，空值为null）",
    `first_order_quarter` VARCHAR(50)     COMMENT "首次订货季度",
    `year`                VARCHAR(50)     COMMENT "年份（韦德有，361为空）",    
    -- 5. 度量列：库存信息（韦德有详细库存，361为空）
    `inventory_sku`       BIGINT          COMMENT "库存数量(SKU)（韦德有，361为空，整数）",
    -- ============== 新增：韦德特有字段（361置NULL/默认值） ==============
    `order_qty_skc`       BIGINT          COMMENT "订货数量(SKC维度)(韦德特有,361为NULL)",
    `inventory_skc`       BIGINT          COMMENT "库存数量(SKC)(韦德特有,361为NULL)",
    `sales_cycle_label`   VARCHAR(100)    COMMENT "销售周期标签(韦德特有,361为NULL)",
    `is_replenish`        VARCHAR(50)     COMMENT "是否补货(韦德特有:是/否,361固定为'否')",
    `replenish_qty`       BIGINT          COMMENT "补货量(韦德特有,361为0)",
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
```

### feishu\_dwd\.dwd\_feishu\_inventory\_wdpinpai\_d

```SQL
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
```

### feishu\_dwd\.dwd\_feishu\_otb\_wd\_d

```SQL
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
```

### feishu\_dwd\.dwd\_feishu\_brand\_order\_arrival\_d

```SQL
*-- =============================================*
*-- 1. DWD 层建表语句 (以 style_no_size 为主键，需聚合)*
*-- =============================================*
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_brand_order_arrival_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_brand_order_arrival_d (
    *-- 1. Key 列（PRIMARY KEY 模型，style_no_size 为唯一业务主键）*
    `style_no_size`         VARCHAR(255)    COMMENT "款号与尺码拼接(主键, 形如:ABAV015-7-11.5)",
    
    *-- 2. 维度列*
    `sku`                    VARCHAR(128)    COMMENT "商品SKU(按主键聚合取MAX值)",
    `style_no`               VARCHAR(255)    COMMENT "款号",
    `size_code`              VARCHAR(50)     COMMENT "尺码",
    `ip`                     VARCHAR(100)    COMMENT "IP",
    `series`                 VARCHAR(100)    COMMENT "系列",
    `color_name`             VARCHAR(255)    COMMENT "配色名",
    `product_name`           VARCHAR(500)    COMMENT "品名",
    `category`               VARCHAR(100)    COMMENT "商品分类",
    `pickup_status`          VARCHAR(50)     COMMENT "提货状态",
    `est_arrival_month`      VARCHAR(50)     COMMENT "预计到货年月(取最早到货时间对应记录)",
    
    *-- 3. 度量列 (按 style_no_size 聚合叠加)*
    `order_qty`              BIGINT          COMMENT "订货数量(叠加)",
    `picked_qty`             BIGINT          COMMENT "已提货数量(叠加)",
    `unpicked_qty`           BIGINT          COMMENT "未提货数量(叠加)",
    `brand_stock_qty`        BIGINT          COMMENT "品牌库存数量(叠加)",
    `unpicked_avail_qty`     BIGINT          COMMENT "未提可提数量(叠加)",
    `unpicked_unavail_qty`   BIGINT          COMMENT "未提不可提数量(叠加)",
    `cumulative_order_qty`   BIGINT          COMMENT "累计订货(叠加)",
    
    *-- 4. 日期列*
    `est_arrival_date`       DATE            COMMENT "预计到货时间(取最早的，空值默认CAST NULL AS DATE)",
    `30_est_arrival_date`    DATE            COMMENT "预计到货时间+30天",
    
    *-- 5. 技术字段*
    `sync_time`              DATETIME        COMMENT "ODS同步时间(取最新时间)",
    `insert_date`            DATETIME        COMMENT "DWD记录插入时间（ETL写入，增量更新用）",
    `update_date`            DATETIME        COMMENT "DWD记录更新时间（ETL写入，增量更新用）"
) ENGINE=OLAP
PRIMARY KEY(`style_no_size`)
COMMENT "DWD层-品牌订货到货情况清洗表(款号尺码粒度,需聚合,日刷新)"
DISTRIBUTED BY HASH(`style_no_size`)
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

## DWS层：明细数据层

### feishu\_dws\.dws\_sku\_product\_info\_d

```SQL
DROP TABLE IF EXISTS feishu_dws.dws_sku_product_info_d;

CREATE TABLE IF NOT EXISTS feishu_dws.dws_sku_product_info_d (
    -- 1. Key 列（前 N 列，顺序与 PRIMARY KEY 一致）
    `style_no_size`        VARCHAR(255)    COMMENT "SKU编码(style_no-size拼接)",
    -- 2. 维度属性
    `brand`                VARCHAR(20)     COMMENT "品牌",
    `style_no`             VARCHAR(128)    COMMENT "款号/SKC编码",
    `size`                 VARCHAR(50)     COMMENT "尺码",
    `ip`                   VARCHAR(100)    COMMENT "IP(空值兜底None)",
    `series`               VARCHAR(100)    COMMENT "系列(空值兜底None)",
    `color_name`           VARCHAR(100)    COMMENT "配色名",
    `product_name`         VARCHAR(500)    COMMENT "商品名称",
    `category`             VARCHAR(100)    COMMENT "品类",
    `tag_price`            DECIMAL(18,6)   COMMENT "吊牌价(元)",
    -- 3. 时间字段
    `shelf_date`           DATE            COMMENT "上架日期(空值取30_est_arrival_date补全)",
    `first_sales_date`     DATE            COMMENT "首次销售日期",
    -- 4. 库存字段
    `inventory_sku`        BIGINT          COMMENT "在仓库存(空值兜底0)",
    `available_inventory`  BIGINT          COMMENT "可提库存(取最新inventory_date按sku聚合)",
    -- 5. 订货字段
    `order_qty`            BIGINT          COMMENT "订货数量Q(按style_no_size关联,空值兜底0)",
    `replenish_qty`        BIGINT          COMMENT "补货数量",
    `is_replenish`         VARCHAR(50)     COMMENT "是否补货(是/否)",
    `total_order_qty`      BIGINT          COMMENT "总订货数量(订货+补货)",
    -- 6. 销售汇总字段
    `daily_avg_qty_30d`    DECIMAL(18,6)   COMMENT "30天平均日销(核心4渠道)",
    `sellable_days`        DECIMAL(18,6)   COMMENT "可售周期天数(在仓库存/30天平均日销)",
    `achievement_ratio`    DECIMAL(18,6)   COMMENT "达成比例(累计销量/订货数量)",
    `should_achieve_ratio` DECIMAL(18,6)   COMMENT "应达成比例(累计计划销量/订货数量,取销售计划表最新cum_plan_qty)",
    `lifecycle_day`        BIGINT          COMMENT "当日已上架天数(基于shelf_date)",
    `sales_cycle_label`    VARCHAR(50)     COMMENT "销售周期标签(新品期/热销期/清货期/超周期)",
    -- 7. 技术字段
    `sync_time`            DATETIME        COMMENT "ODS同步时间",
    `insert_date`          DATETIME        COMMENT "DWS记录插入时间(ETL写入)",
    `update_date`          DATETIME        COMMENT "DWS记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`style_no_size`)
COMMENT "DWS层-SKU商品维表"
DISTRIBUTED BY HASH(`style_no_size`) BUCKETS 16
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

### feishu\_dws\.dws\_skc\_product\_info\_d

```SQL
DROP TABLE IF EXISTS feishu_dws.dws_skc_product_info_d;

CREATE TABLE IF NOT EXISTS feishu_dws.dws_skc_product_info_d (
    -- 1. Key 列
    `style_no`             VARCHAR(128)    COMMENT "SKC编码/款号",
    -- 2. 维度属性
    `brand`                VARCHAR(20)     COMMENT "品牌",
    `ip`                   VARCHAR(100)    COMMENT "IP(空值兜底None)",
    `series`               VARCHAR(100)    COMMENT "系列(空值兜底None)",
    `color_name`           VARCHAR(100)    COMMENT "配色名(取代表值)",
    `product_name`         VARCHAR(500)    COMMENT "商品名称(取代表值)",
    `category`             VARCHAR(100)    COMMENT "品类(取代表值)",
    -- 3. 时间字段
    `shelf_date`           DATE            COMMENT "SKC上架日期(MIN(shelf_date))",
    `first_sales_date`     DATE            COMMENT "SKC首次销售日期(MIN(first_sales_date))",
    -- 4. 库存字段
    `inventory_sku`        BIGINT          COMMENT "SKC在仓库存(SUM(inventory_sku))",
    `available_inventory`  BIGINT          COMMENT "SKC可提库存(SUM(inventory_qty)按style_no聚合)",
    -- 5. 订货字段
    `order_qty`            BIGINT          COMMENT "SKC订货数量Q(SUM(order_qty))",
    `replenish_qty`        BIGINT          COMMENT "SKC补货数量(SUM(replenish_qty))",
    `total_order_qty`      BIGINT          COMMENT "SKC总订货数量",
    -- 6. 销售汇总字段
    `daily_avg_qty_30d`    DECIMAL(18,6)   COMMENT "SKC 30天平均日销(核心4渠道)",
    `sellable_days`        DECIMAL(18,6)   COMMENT "SKC可售周期天数",
    `achievement_ratio`    DECIMAL(18,6)   COMMENT "SKC达成比例",
    `should_achieve_ratio` DECIMAL(18,6)   COMMENT "SKC应达成比例(累计计划销量/订货数量,取销售计划表最新cum_plan_qty)",
    `lifecycle_day`        BIGINT          COMMENT "当日SKC已上架天数",
    `sales_cycle_label`    VARCHAR(50)     COMMENT "SKC销售周期标签",
    -- 7. 技术字段
    `sync_time`            DATETIME        COMMENT "ODS同步时间(取MAX)",
    `insert_date`          DATETIME        COMMENT "DWS记录插入时间(ETL写入)",
    `update_date`          DATETIME        COMMENT "DWS记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`style_no`)
COMMENT "DWS层-SKC商品维表"
DISTRIBUTED BY HASH(`style_no`) BUCKETS 16
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

### feishu\_dws\.dws\_sku\_sales\_plan\_180d\_d

```SQL
DROP TABLE IF EXISTS feishu_dws.dws_sku_sales_plan_180d_d;

CREATE TABLE IF NOT EXISTS feishu_dws.dws_sku_sales_plan_180d_d (
    -- 1. Key 列（前 N 列，顺序与 PRIMARY KEY 一致，≤3列）
    `style_no_size`        VARCHAR(255)    COMMENT "SKU编码",
    `sale_date`            DATE            COMMENT "销售日期(从shelf_date补齐到全局最晚shelf_date+180)",
    -- 2. 生命周期定位
    `lifecycle_day`        BIGINT          COMMENT "上市第N天(DATEDIFF(sale_date,shelf_date)+1)",
    `sale_date_label`      VARCHAR(20)     COMMENT "销售日期标签(1~180显示数字,>180显示超周期)",
    `sales_cycle_label`    VARCHAR(50)     COMMENT "销售周期标签(新品期/热销期/清货期/超周期)",
    `ratio`                DECIMAL(18,6)   COMMENT "阶段比例(新品0.8/热销1.1/清货1.0/超周期NULL)",
    -- 3. 维度属性（冗余便于查询）
    `brand`                VARCHAR(20)     COMMENT "品牌",
    `style_no`             VARCHAR(128)    COMMENT "款号/SKC编码",
    `size`                 VARCHAR(50)     COMMENT "尺码",
    `shelf_date`           DATE            COMMENT "上架日期",
    -- 4. 订货数量 Q
    `order_qty`            BIGINT          COMMENT "订货数量Q(空值兜底0)",
    -- 5. 销售计划（1~180天计算，超周期为NULL）
    `plan_pre`             DECIMAL(18,6)   COMMENT "销售计划(销售前)(Q*ratio/180)",
    `plan_post`            DECIMAL(18,6)   COMMENT "销售计划(销售后)((Q-cum_actual)*ratio/(180-N))",
    -- 6. 实际销售
    `actual_qty`           BIGINT          COMMENT "实际销售(第N天核心4渠道SUM(qty))",
    `actual_amt`           DECIMAL(18,6)   COMMENT "实际销售金额(第N天核心4渠道SUM(amt))",
    `cum_actual`           BIGINT          COMMENT "累计实际销量(截至N-1天的SUM(qty))",
    `cum_actual_amt`       DECIMAL(18,6)   COMMENT "累计实际金额(截至N-1天的SUM(amt))",
    `cum_plan_qty`         DECIMAL(18,6)   COMMENT "累计计划销量(截至N-1天,SUM(plan_post)窗口累计)",
    `cum_plan_amt`         DECIMAL(18,6)   COMMENT "累计计划金额(截至N-1天,占位0)",
    `should_achieve_ratio` DECIMAL(18,6)   COMMENT "应达成比例(累计计划销量/订货数量Q,基于截至N-1天的cum_plan_qty)",
    -- 7. 达成情况
    `achievement_rate`     DECIMAL(18,6)   COMMENT "达成情况(actual_qty/plan_post,plan_post=0时NULL)",
    -- 8. 库存（每日快照）
    `inventory_sku`        BIGINT          COMMENT "在仓库存",
    `available_inventory`  BIGINT          COMMENT "可提库存",
    `sellable_days`        DECIMAL(18,6)   COMMENT "可售周期天数(超周期才计算)",
    -- 9. 技术字段
    `sync_time`            DATETIME        COMMENT "ODS同步时间",
    `insert_date`          DATETIME        COMMENT "DWS记录插入时间(ETL写入)",
    `update_date`          DATETIME        COMMENT "DWS记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`style_no_size`, `sale_date`)
COMMENT "DWS层-SKU销售计划180天表"
DISTRIBUTED BY HASH(`style_no_size`) BUCKETS 32
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

### feishu\_dws\.dws\_skc\_sales\_plan\_180d\_d

```SQL
DROP TABLE IF EXISTS feishu_dws.dws_skc_sales_plan_180d_d;

CREATE TABLE IF NOT EXISTS feishu_dws.dws_skc_sales_plan_180d_d (
    -- 1. Key 列（前 N 列，≤3列）
    `style_no`             VARCHAR(128)    COMMENT "SKC编码/款号",
    `sale_date`            DATE            COMMENT "销售日期(从MIN(shelf_date)补齐到全局最晚shelf_date+180)",
    -- 2. 生命周期定位
    `lifecycle_day`        BIGINT          COMMENT "上市第N天(DATEDIFF(sale_date,MIN(shelf_date))+1)",
    `sale_date_label`      VARCHAR(20)     COMMENT "销售日期标签(1~180显示数字,>180显示超周期)",
    `sales_cycle_label`    VARCHAR(50)     COMMENT "销售周期标签",
    `ratio`                DECIMAL(18,6)   COMMENT "阶段比例",
    -- 3. 维度属性（冗余）
    `brand`                VARCHAR(20)     COMMENT "品牌",
    `shelf_date`           DATE            COMMENT "SKC上架日期(MIN(shelf_date))",
    -- 4. 订货数量 Q
    `order_qty`            BIGINT          COMMENT "SKC订货数量Q(SUM(order_qty)按style_no聚合)",
    -- 5. 销售计划
    `plan_pre`             DECIMAL(18,6)   COMMENT "销售计划(销售前)",
    `plan_post`            DECIMAL(18,6)   COMMENT "销售计划(销售后)",
    -- 6. 实际销售
    `actual_qty`           BIGINT          COMMENT "实际销售(第N天核心4渠道SUM(qty)按style_no聚合)",
    `actual_amt`           DECIMAL(18,6)   COMMENT "实际销售金额(第N天核心4渠道SUM(amt))",
    `cum_actual`           BIGINT          COMMENT "累计实际销量(截至N-1天)",
    `cum_actual_amt`       DECIMAL(18,6)   COMMENT "累计实际金额(截至N-1天)",
    `cum_plan_qty`         DECIMAL(18,6)   COMMENT "SKC累计计划销量(截至N-1天,SUM(plan_post)窗口累计)",
    `cum_plan_amt`         DECIMAL(18,6)   COMMENT "SKC累计计划金额(截至N-1天,占位0)",
    `should_achieve_ratio` DECIMAL(18,6)   COMMENT "SKC应达成比例(累计计划销量/订货数量Q,基于截至N-1天的cum_plan_qty)",
    -- 7. 达成情况
    `achievement_rate`     DECIMAL(18,6)   COMMENT "达成情况(actual_qty/plan_post)",
    -- 8. 库存
    `inventory_sku`        BIGINT          COMMENT "SKC在仓库存(SUM(inventory_sku))",
    `available_inventory`  BIGINT          COMMENT "SKC可提库存",
    `sellable_days`        DECIMAL(18,6)   COMMENT "SKC可售周期天数",
    -- 9. 技术字段
    `sync_time`            DATETIME        COMMENT "ODS同步时间",
    `insert_date`          DATETIME        COMMENT "DWS记录插入时间(ETL写入)",
    `update_date`          DATETIME        COMMENT "DWS记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`style_no`, `sale_date`)
COMMENT "DWS层-SKC销售计划180天表"
DISTRIBUTED BY HASH(`style_no`) BUCKETS 32
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

### feishu\_dws\.dws\_sku\_abnormal\_d

```SQL
DROP TABLE IF EXISTS feishu_dws.dws_sku_abnormal_d;

CREATE TABLE IF NOT EXISTS feishu_dws.dws_sku_abnormal_d (
    -- 1. Key 列
    `sku`                  VARCHAR(128)    COMMENT "SKU编码(来源product_all_d.sku)",
    -- 2. 维度属性
    `style_no`             VARCHAR(128)    COMMENT "款号(可能为空或None)",
    `size`                 VARCHAR(50)     COMMENT "尺码(可能为空或None)",
    `style_no_size`        VARCHAR(255)    COMMENT "SKU编码(style_no-size拼接,可能为空或None)",
    `brand`                VARCHAR(20)     COMMENT "品牌",
    -- 3. 异常诊断字段
    `shelf_date_raw`       DATE            COMMENT "原始上架日期(未补全)",
    `first_sales_date`     DATE            COMMENT "首次销售日期",
    `abnormal_reason`      VARCHAR(200)    COMMENT "异常原因(见下方说明)",
    -- 4. 技术字段
    `sync_time`            DATETIME        COMMENT "ODS同步时间",
    `insert_date`          DATETIME        COMMENT "DWS记录插入时间(ETL写入)",
    `update_date`          DATETIME        COMMENT "DWS记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`sku`)
COMMENT "DWS层-SKU异常表"
DISTRIBUTED BY HASH(`sku`) BUCKETS 8
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

### feishu\_dws\.dws\_skc\_abnormal\_d

```SQL
DROP TABLE IF EXISTS feishu_dws.dws_skc_abnormal_d;

CREATE TABLE IF NOT EXISTS feishu_dws.dws_skc_abnormal_d (
    -- 1. Key 列
    `style_no`             VARCHAR(128)    COMMENT "SKC编码/款号(可能为空或None)",
    -- 2. 维度属性
    `brand`                VARCHAR(20)     COMMENT "品牌",
    -- 3. 异常诊断字段
    `shelf_date_raw`       DATE            COMMENT "原始最早上架日期(MIN(shelf_date),未补全)",
    `first_sales_date`     DATE            COMMENT "SKC首次销售日期(MIN(first_sales_date))",
    `abnormal_reason`      VARCHAR(200)    COMMENT "异常原因",
    -- 4. 技术字段
    `sync_time`            DATETIME        COMMENT "ODS同步时间(取MAX)",
    `insert_date`          DATETIME        COMMENT "DWS记录插入时间(ETL写入)",
    `update_date`          DATETIME        COMMENT "DWS记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`style_no`)
COMMENT "DWS层-SKC异常表"
DISTRIBUTED BY HASH(`style_no`) BUCKETS 8
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

## ADS层：明细数据层

### feishu\_ads\.ads\_sku\_sales\_plan\_180d\_d

```JavaScript
DROP TABLE IF EXISTS feishu_ads.ads_sku_sales_plan_180d_d;

CREATE TABLE IF NOT EXISTS feishu_ads.ads_sku_sales_plan_180d_d (
    -- 1. Key 列（前 N 列，顺序与 PRIMARY KEY 一致，≤3列）
    `style_no_size`            VARCHAR(255)    COMMENT "SKU编码(style_no-size拼接)",
    `sale_date`                DATE            COMMENT "销售日期(分区键)",
    -- 2. 日期与生命周期定位
    `lifecycle_day`            BIGINT          COMMENT "上市第N天(DATEDIFF(sale_date,shelf_date)+1)",
    `sale_date_label`          VARCHAR(20)     COMMENT "销售日期标签(第N天/超周期)",
    `sales_phase`              VARCHAR(50)     COMMENT "销售阶段(新品期/热销期/清货期/超周期)",
    `is_over_cycle`            TINYINT         COMMENT "是否超周期(1=超周期,0=正常周期)",
    -- 3. 维度属性
    `brand`                    VARCHAR(20)     COMMENT "品牌",
    `style_no`                 VARCHAR(128)    COMMENT "款号/SKC编码",
    `size`                     VARCHAR(50)     COMMENT "尺码",
    `ip`                       VARCHAR(100)    COMMENT "IP(空值兜底None)",
    `series`                   VARCHAR(100)    COMMENT "系列(空值兜底None)",
    `color_name`               VARCHAR(100)    COMMENT "配色名",
    `product_name`             VARCHAR(500)    COMMENT "商品名称",
    `category`                 VARCHAR(100)    COMMENT "品类",
    `tag_price`                DECIMAL(18,6)   COMMENT "吊牌价(元)",
    `shelf_date`               DATE            COMMENT "上架日期",
    `first_sales_date`         DATE            COMMENT "首次销售日期",
    -- 4. 销售计划(1~180天计算,超周期为NULL)
    `plan_pre`                 DECIMAL(18,6)   COMMENT "销售计划(销售前)(Q*ratio/180)",
    `plan_post`                DECIMAL(18,6)   COMMENT "销售计划(销售后)((Q-cum_actual)*ratio/(181-N))",
    -- 5. 实际销售与累计
    `daily_qty`                BIGINT          COMMENT "日销量(第N天核心4渠道SUM(qty))",
    `daily_amt`                DECIMAL(18,6)   COMMENT "日金额(第N天核心4渠道SUM(amt))",
    `cum_qty`                  BIGINT          COMMENT "累计销量(截至当天N的累计)",
    `cum_amt`                  DECIMAL(18,6)   COMMENT "累计金额(截至当天N的累计)",
    -- 5.1 累计计划(截至N-1天,来自DWS销售计划表)
    `cum_plan_qty`             DECIMAL(18,6)   COMMENT "累计计划销量(截至N-1天,SUM(plan_post)窗口累计)",
    `cum_plan_amt`             DECIMAL(18,6)   COMMENT "累计计划金额(截至N-1天,占位0)",
    -- 6. 达成情况
    `achievement_rate`         DECIMAL(18,6)   COMMENT "达成情况(daily_qty/plan_post,plan_post=0时NULL)",
    -- 7. 库存指标
    `inventory_sku`            BIGINT          COMMENT "在仓库存(空值兜底0)",
    `available_inventory`      BIGINT          COMMENT "可提库存(取最新inventory_date按sku聚合)",
    `daily_avg_qty_30d`        DECIMAL(18,6)   COMMENT "30天平均日销(核心4渠道)",
    `sellable_days`            DECIMAL(18,6)   COMMENT "可售周期天数(在仓库存/30天平均日销)",
    -- 8. 当前快照指标(昨日/今日/7天/30天达成,同一SKU所有行值相同)
    `yesterday_actual_qty`     BIGINT          COMMENT "昨日实际销售(昨日核心4渠道SUM(qty))",
    `yesterday_achievement`    DECIMAL(18,6)   COMMENT "昨日销售达成情况(昨日实际/昨日计划(后))",
    `7d_achievement`           DECIMAL(18,6)   COMMENT "7天销售达成情况(近7天实际/近7天计划(后))",
    `30d_achievement`          DECIMAL(18,6)   COMMENT "30天销售达成情况(近30天实际/近30天计划(后))",
    `today_plan_qty`           DECIMAL(18,6)   COMMENT "今日计划销售数量(今天的销售计划(后),超周期为0)",
    -- 9. 订货指标
    `order_qty`                BIGINT          COMMENT "订货数量Q(空值兜底0)",
    `total_order_qty`          BIGINT          COMMENT "总订货数量(订货+补货)",
    `achievement_ratio`        DECIMAL(18,6)   COMMENT "达成比例(累计销量/订货数量)",
    `should_achieve_ratio`     DECIMAL(18,6)   COMMENT "应达成比例(累计计划销量/订货数量Q,取DWS销售计划表对应行cum_plan_qty/order_qty)",
    -- 10. 技术字段
    `sync_time`                DATETIME        COMMENT "ODS同步时间",
    `insert_date`              DATETIME        COMMENT "ADS记录插入时间(ETL写入)",
    `update_date`              DATETIME        COMMENT "ADS记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`style_no_size`, `sale_date`)
COMMENT "ADS层-SKU维度1~180天销售计划表(日刷新,韦德4核心渠道,核心表,QuickBI直接消费)"
DISTRIBUTED BY HASH(`style_no_size`) BUCKETS 32
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

### feishu\_ads\.ads\_skc\_sales\_plan\_180d\_d

```SQL
DROP TABLE IF EXISTS feishu_ads.ads_skc_sales_plan_180d_d;

CREATE TABLE IF NOT EXISTS feishu_ads.ads_skc_sales_plan_180d_d (
    -- 1. Key 列（前 N 列，≤3列）
    `style_no`                 VARCHAR(128)    COMMENT "SKC编码/款号",
    `sale_date`                DATE            COMMENT "销售日期(分区键)",
    -- 2. 日期与生命周期定位
    `lifecycle_day`            BIGINT          COMMENT "上市第N天(DATEDIFF(sale_date,MIN(shelf_date))+1)",
    `sale_date_label`          VARCHAR(20)     COMMENT "销售日期标签(第N天/超周期)",
    `sales_phase`              VARCHAR(50)     COMMENT "销售阶段(新品期/热销期/清货期/超周期)",
    `is_over_cycle`            TINYINT         COMMENT "是否超周期(1=超周期,0=正常周期)",
    -- 3. 维度属性
    `brand`                    VARCHAR(20)     COMMENT "品牌",
    `ip`                       VARCHAR(100)    COMMENT "IP(空值兜底None)",
    `series`                   VARCHAR(100)    COMMENT "系列(空值兜底None)",
    `product_name`             VARCHAR(500)    COMMENT "商品名称(取代表值)",
    `category`                 VARCHAR(100)    COMMENT "品类(取代表值)",
    `tag_price`                DECIMAL(18,6)   COMMENT "吊牌价(元)",
    `shelf_date`               DATE            COMMENT "SKC上架日期(MIN(shelf_date))",
    `first_sales_date`         DATE            COMMENT "SKC首次销售日期(MIN(first_sales_date))",
    -- 4. 销售计划(1~180天计算,超周期为NULL)
    `plan_pre`                 DECIMAL(18,6)   COMMENT "销售计划(销售前)(Q*ratio/180)",
    `plan_post`                DECIMAL(18,6)   COMMENT "销售计划(销售后)((Q-cum_actual)*ratio/(181-N))",
    -- 5. 实际销售与累计
    `daily_qty`                BIGINT          COMMENT "日销量(第N天核心4渠道SUM(qty)按style_no聚合)",
    `daily_amt`                DECIMAL(18,6)   COMMENT "日金额(第N天核心4渠道SUM(amt))",
    `cum_qty`                  BIGINT          COMMENT "累计销量(截至当天N的累计)",
    `cum_amt`                  DECIMAL(18,6)   COMMENT "累计金额(截至当天N的累计)",
    -- 5.1 累计计划(截至N-1天,来自DWS销售计划表)
    `cum_plan_qty`             DECIMAL(18,6)   COMMENT "SKC累计计划销量(截至N-1天,SUM(plan_post)窗口累计)",
    `cum_plan_amt`             DECIMAL(18,6)   COMMENT "SKC累计计划金额(截至N-1天,占位0)",
    -- 6. 达成情况
    `achievement_rate`         DECIMAL(18,6)   COMMENT "达成情况(daily_qty/plan_post)",
    -- 7. 库存指标
    `inventory_skc`            BIGINT          COMMENT "SKC在仓库存(SUM(inventory_sku)按style_no聚合)",
    `available_inventory`      BIGINT          COMMENT "SKC可提库存(SUM(inventory_qty)按style_no聚合)",
    `daily_avg_qty_30d`        DECIMAL(18,6)   COMMENT "SKC 30天平均日销(核心4渠道)",
    `sellable_days`            DECIMAL(18,6)   COMMENT "SKC可售周期天数",
    -- 8. 当前快照指标(昨日/今日/7天/30天达成,同一SKC所有行值相同)
    `yesterday_actual_qty`     BIGINT          COMMENT "昨日实际销售",
    `yesterday_achievement`    DECIMAL(18,6)   COMMENT "昨日销售达成情况",
    `7d_achievement`           DECIMAL(18,6)   COMMENT "7天销售达成情况",
    `30d_achievement`          DECIMAL(18,6)   COMMENT "30天销售达成情况",
    `today_plan_qty`           DECIMAL(18,6)   COMMENT "今日计划销售数量(超周期为0)",
    -- 9. 订货指标
    `order_qty`                BIGINT          COMMENT "SKC订货数量Q(SUM(order_qty))",
    `total_order_qty`          BIGINT          COMMENT "SKC总订货数量",
    `achievement_ratio`        DECIMAL(18,6)   COMMENT "SKC达成比例",
    `should_achieve_ratio`     DECIMAL(18,6)   COMMENT "SKC应达成比例(累计计划销量/订货数量Q,取DWS销售计划表对应行cum_plan_qty/order_qty)",
    -- 10. 技术字段
    `sync_time`                DATETIME        COMMENT "ODS同步时间",
    `insert_date`              DATETIME        COMMENT "ADS记录插入时间(ETL写入)",
    `update_date`              DATETIME        COMMENT "ADS记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`style_no`, `sale_date`)
COMMENT "ADS层-SKC维度1~180天销售计划表(日刷新,韦德4核心渠道,核心表,QuickBI直接消费)"
DISTRIBUTED BY HASH(`style_no`) BUCKETS 32
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

# 2、查询语句

## DWD:

### feishu\_dwd\.dwd\_feishu\_sales\_361\_d

```SQL
-- 验证1：361销售分表合并行数
SELECT 'ODS_361_total' AS source, SUM(cnt) AS rows_cnt FROM (
    SELECT COUNT(*) AS cnt FROM feishu.t_361sales_01
    UNION ALL SELECT COUNT(*) FROM feishu.t_361sales_02
    -- ... 省略 t_361sales_03 ~ t_361sales_49
    UNION ALL SELECT COUNT(*) FROM feishu.t_361sales_50
) t
UNION ALL
SELECT 'DWD_361' AS source, COUNT(*) AS rows_cnt FROM feishu_dwd.dwd_feishu_sales_361_d;

-- 验证2：韦德销售分表合并行数
SELECT 'ODS_WD_total' AS source, SUM(cnt) AS rows_cnt FROM (
    SELECT COUNT(*) AS cnt FROM wd_sales_01
    UNION ALL SELECT COUNT(*) FROM wd_sales_02
    UNION ALL SELECT COUNT(*) FROM wd_sales_03
    UNION ALL SELECT COUNT(*) FROM wd_sales_04
    UNION ALL SELECT COUNT(*) FROM wd_sales_05
    UNION ALL SELECT COUNT(*) FROM wd_sales_06
    -- ... 省略 wd_sales_02 ~ wd_sales_49
    UNION ALL SELECT COUNT(*) FROM wd_sales_50
) t
UNION ALL
SELECT 'DWD_WD' AS source, COUNT(*) AS rows_cnt FROM feishu_dwd.dwd_feishu_sales_wd_d;

-- 验证3：长表行数 = 361(4渠道) + 韦德(18渠道) 的有效记录数
SELECT 'DWD_all' AS source, COUNT(*) AS rows_cnt FROM feishu_dwd.dwd_feishu_sales_all_d;

-- feishu.t_361sales_02
SELECT COUNT(1) FROM  feishu.t_361sales_02
SELECT COUNT(DISTINCT record_id ) FROM  feishu.t_361sales_02
WHERE  record_id IS NULL
;
SELECT * FROM  feishu.t_361sales_01;
-- feishu_dwd.v_feishu_sales_361_d
SELECT COUNT(1) FROM  feishu_dwd.v_feishu_sales_361_d;
SELECT * FROM  feishu_dwd.v_feishu_sales_361_d;
-- feishu_dwd.dwd_feishu_sales_361_d
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_sales_361_d;
SELECT * FROM  feishu_dwd.dwd_feishu_sales_361_d;
SELECT COUNT(DISTINCT record_id ) FROM  feishu_dwd.dwd_feishu_sales_361_d
```

### feishu\_dwd\.dwd\_feishu\_sales\_wd\_d

```SQL
-- 抽样：随机取10条361记录，对比ODS和DWD dwd_feishu_sales_361_d
SELECT a.record_id, a.sku, a.sales_date, a.qty_361sport, b.`361sport-销量`
FROM feishu_dwd.dwd_feishu_sales_361_d a
JOIN feishu.t_361sales_01 b ON a.record_id = b.record_id
ORDER BY RAND() LIMIT 10;

-- 抽样：韦德06分表（结构最全）对比
SELECT a.record_id, a.sku, a.style_no, a.qty_wd, b.`韦德之道-销量`
FROM feishu_dwd.dwd_feishu_sales_wd_d a
JOIN feishu.wd_sales_06 b ON a.record_id = b.record_id
ORDER BY RAND() LIMIT 10;

-- feishu.wd_sales_06
SELECT COUNT(1) FROM  feishu.wd_sales_06;
SELECT * FROM  feishu.wd_sales_06
WHERE record_id = "recvmfrxdsuu2Z"
;
-- feishu.wd_sales_01
SELECT COUNT(1) FROM  feishu.wd_sales_01;
SELECT * FROM  feishu.wd_sales_02 ;
-- feishu_dwd.v_feishu_sales_wd_d
SELECT COUNT(1) FROM  feishu_dwd.v_feishu_sales_wd_d;
SELECT * FROM  feishu_dwd.v_feishu_sales_wd_d
WHERE record_id = "recvmfrxdsuu2Z";
-- feishu_dwd.feishu_dwd.dwd_feishu_sales_wd_d
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_sales_wd_d;
SELECT * FROM  feishu_dwd.dwd_feishu_sales_wd_d
WHERE source_table = "wd_sales_03";
SELECT * FROM  feishu_dwd.dwd_feishu_sales_wd_d
WHERE qty_wd is NULL ;
SELECT * FROM  feishu_dwd.dwd_feishu_sales_wd_d
WHERE record_id = "recvmfrxdsuu2Z"
;
```

### feishu\_dwd\.dwd\_feishu\_sales\_all\_d

```SQL
-- feishu_dwd.dwd_feishu_sales_all_d
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_sales_all_d;
SELECT * FROM  feishu_dwd.dwd_feishu_sales_all_d;
-- total:feishu_dwd.dwd_feishu_sales_361_d 101472320.3
SELECT SUM(
qty_361sport+
qty_china+
qty_sample+
qty_staff_hk+
amt_361sport+
amt_china+
amt_sample+
amt_staff_hk) AS Total FROM  feishu_dwd.dwd_feishu_sales_361_d;
-- feishu_dwd.dwd_feishu_sales_all_d : 101472320.3 验证通过 影响行数：324724
SELECT SUM (qty +amt) FROM  feishu_dwd.dwd_feishu_sales_all_d
WHERE channel_code in ( "361sport","china_company","361_sample","staff_hk" )
;
```

### feishu\_dwd\.dwd\_feishu\_product\_wd\_d

```SQL
-- feishu.wd_shop
SELECT COUNT(1) FROM  feishu.wd_shop;
SELECT * FROM  feishu.wd_shop
limit 3
;
-- 补货量:31615.0
SELECT SUM(补货量) FROM  feishu.wd_shop;

-- feishu_dwd.dwd_feishu_product_wd_d
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_product_wd_d;
SELECT * FROM  feishu_dwd.dwd_feishu_product_wd_d
limit 3
;
-- 补货量:31615
SELECT SUM(replenish_qty) FROM  feishu_dwd.dwd_feishu_product_wd_d;
-- 11028
SELECT COUNT(CONCAT_WS ('-',style_no,size)) FROM  feishu_dwd.dwd_feishu_product_wd_d 
-- 11028
SELECT COUNT(sku ) FROM  feishu_dwd.dwd_feishu_product_wd_d 

-- 11028
SELECT COUNT(CONCAT_WS ('-',style_no,size)) FROM  feishu_dwd.dwd_feishu_product_all_d 
-- 11028
SELECT COUNT(sku ) FROM  feishu_dwd.dwd_feishu_product_all_d 
```

### feishu\_dwd\.dwd\_feishu\_product\_361\_d

```SQL
-- feishu.t_361_shop  16679
SELECT COUNT(1) FROM  feishu.t_361_shop;
SELECT * FROM  feishu.t_361_shop
limit 3
;
-- feishu.t_361_shop 577
SELECT COUNT(1) FROM  feishu.t_361_shop
WHERE SKU IS NULL OR TRIM(SKU) = '';   
SELECT * FROM  feishu.t_361_shop
WHERE SKU IS NULL OR TRIM(SKU) = '';   
-- feishu_dwd.dwd_feishu_product_361_d 16102
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_product_361_d;
-- feishu_dwd.dwd_feishu_product_361_d
SELECT * FROM  feishu_dwd.dwd_feishu_product_361_d
limit 3
;
```

### feishu\_dwd\.dwd\_feishu\_product\_all\_d

```SQL
-- feishu_dwd.dwd_feishu_product_wd_d wd  11028
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_product_wd_d wd;
SELECT * FROM  feishu_dwd.dwd_feishu_product_wd_d wd
limit 3
;
-- feishu_dwd.dwd_feishu_product_361_d  16102
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_product_361_d;
SELECT * FROM  feishu_dwd.dwd_feishu_product_361_d
limit 3
;
-- 361  16102
-- 韦德  11028
SELECT brand, COUNT(*) FROM feishu_dwd.dwd_feishu_product_all_d GROUP BY brand;  -- 各品牌SKU数
-- 27130
SELECT COUNT(DISTINCT CONCAT(sku,'_',brand)) FROM feishu_dwd.dwd_feishu_product_all_d;  -- SKU+品牌去重数（应等于总行数）

-- feishu_dwd.dwd_feishu_product_361_d  16102
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_product_all_d;
SELECT * FROM  feishu_dwd.dwd_feishu_product_all_d
```

### feishu\_dwd\.dwd\_feishu\_inventory\_wdpinpai\_d


![image\.png](图片和附件/image.png)



```SQL
-- feishu.wd_pinpaikucun  339
SELECT COUNT(1) FROM  feishu.wd_pinpaikucun;
SELECT * FROM  feishu.wd_pinpaikucun
WHERE sku IS  NULL OR TRIM(sku) = '';
;
-- feishu_dwd.feishu_dwd.dwd_feishu_inventory_wdpinpai_d  338
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_inventory_wdpinpai_d;
SELECT * FROM  feishu_dwd.dwd_feishu_inventory_wdpinpai_d
limit 3
;
SELECT * FROM  feishu_dwd.dwd_feishu_inventory_wdpinpai_d
-- 329
SELECT COUNT(DISTINCT sku,inventory_date) FROM  feishu_dwd.dwd_feishu_inventory_wdpinpai_d

-- 338
SELECT COUNT(DISTINCT record_id ,inventory_date) FROM  feishu_dwd.dwd_feishu_inventory_wdpinpai_d
-- 查询具体的 sku 及其对应的record_id数量（便于排查具体数据）：
SELECT 
      sku, 
      COUNT(DISTINCT record_id) AS record_id_count
  FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d
  GROUP BY sku
  HAVING COUNT(DISTINCT record_id) > 1
  ORDER BY record_id_count DESC;
-- 继续查询 sku BYSku1000000614300829
SELECT * FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d
WHERE 1=1 
AND sku IN (  
'BYSku1000001907677711',
'BYSku1000001736892477',
'BYSku1000001096136709',
'BYSku1000000614300829',
'BYSku1000001286477163',
'BYSku1000001325304058',
'BYSku1000001170740095',
'BYSku1000001531572180',
'BYSku1000000965507119'
)
```

### feishu\_dwd\.dwd\_feishu\_otb\_wd\_d

```SQL
-- feishu.wd_otb  27
SELECT COUNT(1) FROM  feishu.wd_otb;
SELECT * FROM  feishu.wd_otb
WHERE sku IS  NULL OR TRIM(sku) = '';
;
-- feishu_dwd.dwd_feishu_otb_wd_d  27
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_otb_wd_d;
SELECT * FROM  feishu_dwd.dwd_feishu_otb_wd_d
limit 3
;
```

### feishu\_dwd\.dwd\_feishu\_brand\_order\_arrival\_d

```SQL
-- 20260707 7809
SELECT COUNT(*) FROM feishu_dwd.dwd_feishu_brand_order_arrival_d

SELECT * FROM feishu_dwd.dwd_feishu_brand_order_arrival_d

SELECT CONCAT_WS ('-',style_no,size_code),* FROM feishu_dwd.dwd_feishu_brand_order_arrival_d
```

### 垃圾桶：

```SQL
TRUNCATE TABLE feishu_dwd.dwd_feishu_product_all_d;

-- feishu_dwd.dwd_feishu_product_361_d  16102
SELECT COUNT(1) FROM  feishu_dwd.dwd_feishu_product_all_d;
SELECT * FROM  feishu_dwd.dwd_feishu_sales_all_d
WHERE brand = '361' AND qty > 0 
and sales_date = DATE('2026-06-15')

-- feishu_dwd.dwd_feishu_product_361_d  16102
SELECT COUNT(1) FROM  feishu.wd_shop;
SELECT * FROM  feishu_dwd.dwd_feishu_sales_361_d 

SELECT * FROM  feishu_dwd.dwd_feishu_product_361_d 

SELECT * FROM  feishu_dwd.dwd_feishu_product_all_d ;

SELECT * FROM  feishu_dwd.dwd_feishu_product_all_d
WHERE brand = '韦德' 
and first_sales_date = DATE('1970-01-01')

SELECT * FROM  feishu_dwd.dwd_feishu_sales_wd_d 
WHERE first_sales_date = DATE('1970-01-01')

SELECT * FROM  feishu_dwd.dwd_feishu_sales_all_d  
WHERE brand = '韦德' AND qty > 0
AND sku = 'BYSku1000000219132288'
and sales_date = DATE('1970-01-01')

SELECT * FROM  feishu_dwd.dwd_feishu_product_wd_d 
where is_replenish is null

SELECT * FROM   feishu_dwd.dwd_feishu_inventory_wdpinpai_d  
```

## DWS：

### feishu\_dws\.dws\_sku\_product\_info\_d

```SQL
-- 1. 行数核验
SELECT COUNT(*) AS sku_cnt FROM feishu_dws.dws_sku_product_info_d;

-- 2. 抽样：查看某SKU的库存与销售汇总
SELECT style_no_size, brand, shelf_date, inventory_sku, available_inventory,
       order_qty, total_order_qty, daily_avg_qty_30d, sellable_days,
       achievement_ratio, lifecycle_day, sales_cycle_label
FROM feishu_dws.dws_sku_product_info_d
WHERE style_no_size LIKE 'ABAW001-5%'
ORDER BY style_no_size
LIMIT 20;

-- 3. 异常检查：shelf_date 不应为空
SELECT COUNT(*) AS null_shelf_cnt
FROM feishu_dws.dws_sku_product_info_d
WHERE shelf_date IS NULL;

-- 4. 达成比例异常值检查（应为 0~1 之间，>1 表示超额完成）
SELECT style_no_size, achievement_ratio
FROM feishu_dws.dws_sku_product_info_d
WHERE achievement_ratio > 2 OR achievement_ratio < 0
ORDER BY achievement_ratio DESC
LIMIT 50;
```

### feishu\_dws\.dws\_skc\_product\_info\_d

```SQL
-- 1. 行数核验
SELECT COUNT(1) AS skc_cnt FROM feishu_dws.dws_skc_product_info_d
WHERE 1=1 
AND color_name = 'None'
;

-- 2. 抽样查看
SELECT style_no, brand, shelf_date, inventory_sku, available_inventory,
       order_qty, total_order_qty, daily_avg_qty_30d, sellable_days,
       achievement_ratio, lifecycle_day, sales_cycle_label
FROM feishu_dws.dws_skc_product_info_d
ORDER BY style_no
LIMIT 20;

-- 3. SKU 与 SKC 数量对比（SKC 数应 ≤ SKU 数）
SELECT
    (SELECT COUNT(*) FROM feishu_dws.dws_sku_product_info_d)   AS sku_cnt,
    (SELECT COUNT(*) FROM feishu_dws.dws_skc_product_info_d)   AS skc_cnt;

-- 4. 校验：SKC 在仓库存 = 该 SKC 下所有 SKU 在仓库存之和
SELECT sb.style_no, sb.inventory_sku AS skc_inv,
       (SELECT SUM(COALESCE(p.inventory_sku, 0))
        FROM feishu_dwd.dwd_feishu_product_all_d p
        WHERE p.brand = '韦德' AND p.style_no = sb.style_no) AS sku_sum_inv
FROM feishu_dws.dws_skc_product_info_d sb
WHERE sb.inventory_sku <>
      (SELECT SUM(COALESCE(p.inventory_sku, 0))
       FROM feishu_dwd.dwd_feishu_product_all_d p
       WHERE p.brand = '韦德' AND p.style_no = sb.style_no)
LIMIT 50;
```

### feishu\_dws\.dws\_sku\_sales\_plan\_180d\_d

```SQL
-- 1. 行数核验
SELECT COUNT(*) AS total_rows FROM feishu_dws.dws_sku_sales_plan_180d_d;

-- 2. 每个 SKU 的行数（应 = 该SKU从shelf_date到全局最晚shelf_date+180天的天数）
SELECT style_no_size, shelf_date, MIN(sale_date) AS min_sale_date,
       MAX(sale_date) AS max_sale_date, COUNT(*) AS day_cnt
FROM feishu_dws.dws_sku_sales_plan_180d_d
GROUP BY style_no_size, shelf_date
ORDER BY day_cnt DESC
LIMIT 20;

-- 3. 抽样：查看某SKU前30天的计划与实际
SELECT style_no_size, sale_date, lifecycle_day, sale_date_label,
       sales_cycle_label, ratio, order_qty,
       plan_pre, plan_post, actual_qty, cum_actual, achievement_rate
FROM feishu_dws.dws_sku_sales_plan_180d_d
WHERE style_no_size = 'ABAS083-11-12.5'
  AND lifecycle_day BETWEEN 1 AND 30
ORDER BY sale_date
LIMIT 30;

-- 4. 校验：第1天的 plan_post 应 = Q * ratio / 180（cum_actual=0, 分母=180）
SELECT style_no_size, lifecycle_day, order_qty, ratio, plan_pre, plan_post,
       CASE WHEN lifecycle_day = 1 AND plan_post IS NOT NULL
            THEN ABS(plan_post - order_qty * ratio / 180)
            ELSE 0 END AS diff_day1
FROM feishu_dws.dws_sku_sales_plan_180d_d
WHERE lifecycle_day = 1
LIMIT 50;

-- 5. 校验：超周期(>180天)的 plan_pre/plan_post/achievement_rate 应为 NULL
SELECT COUNT(*) AS abnormal_cnt
FROM feishu_dws.dws_sku_sales_plan_180d_d
WHERE lifecycle_day > 180
  AND (plan_pre IS NOT NULL OR plan_post IS NOT NULL OR achievement_rate IS NOT NULL);

-- 6. 累计销量校验：cum_actual(N) 应 = SUM(actual_qty) WHERE lifecycle_day < N
WITH cum_check AS (
    SELECT
        style_no_size,
        sale_date,
        lifecycle_day,
        actual_qty,
        cum_actual AS stored_cum,  -- 表里已存储的累计值
        -- 重算期望值：按 SKU 分组，按天数排序，累加当前行之前所有的 actual_qty
        SUM(COALESCE(actual_qty, 0)) OVER (
            PARTITION BY style_no_size 
            ORDER BY lifecycle_day 
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS calc_cum
    FROM feishu_dws.dws_sku_sales_plan_180d_d
    -- 如果数据量太大，可以先限定日期范围进行抽检：
    -- WHERE sale_date >= '2023-10-01'
)
SELECT 
    style_no_size,
    sale_date,
    lifecycle_day,
    actual_qty,
    stored_cum,  -- 存的值
    calc_cum     -- 算的值
FROM cum_check
WHERE lifecycle_day > 1  -- 第1天的 cum_actual 应为0，通常跳过或者单独看，这里看第2天起的不一致数据
  -- 处理 NULL 值的比较，如果直接用 <> 比较 NULL 结果会被过滤掉
  AND COALESCE(stored_cum, -1) <> COALESCE(calc_cum, -1)
LIMIT 100;

```

### feishu\_dws\.dws\_skc\_sales\_plan\_180d\_d

```SQL
-- 1. 行数核验
SELECT COUNT(*) AS total_rows FROM feishu_dws.dws_skc_sales_plan_180d_d;

-- 2. 每个 SKC 的行数
SELECT style_no, shelf_date, MIN(sale_date) AS min_sale_date,
       MAX(sale_date) AS max_sale_date, COUNT(*) AS day_cnt
FROM feishu_dws.dws_skc_sales_plan_180d_d
GROUP BY style_no, shelf_date
ORDER BY day_cnt DESC
LIMIT 20;

-- 3. 抽样：查看某SKC前30天的计划与实际
SELECT style_no, sale_date, lifecycle_day, sale_date_label,
       sales_cycle_label, ratio, order_qty,
       plan_pre, plan_post, actual_qty, cum_actual, achievement_rate
FROM feishu_dws.dws_skc_sales_plan_180d_d
WHERE style_no = 'ABAS083-11'
  AND lifecycle_day BETWEEN 1 AND 30
ORDER BY sale_date
LIMIT 30;

-- 4. 校验：超周期行销售计划应为 NULL
SELECT COUNT(*) AS abnormal_cnt
FROM feishu_dws.dws_skc_sales_plan_180d_d
WHERE lifecycle_day > 180
  AND (plan_pre IS NOT NULL OR plan_post IS NOT NULL);

-- 5. SKU 与 SKC 数量对比（SKC 表行数应 ≤ SKU 表行数，因 SKC 聚合了尺码）
SELECT
    (SELECT COUNT(DISTINCT style_no_size) FROM feishu_dws.dws_sku_sales_plan_180d_d) AS sku_dim_cnt,
    (SELECT COUNT(DISTINCT style_no) FROM feishu_dws.dws_skc_sales_plan_180d_d)      AS skc_dim_cnt;
```

### feishu\_dws\.dws\_sku\_abnormal\_d

```SQL
SELECT * FROM feishu_dws.dws_sku_abnormal_d
-- 1. 异常 SKU 数量
SELECT COUNT(*) AS abnormal_sku_cnt FROM feishu_dws.dws_sku_abnormal_d;

-- 2. 异常原因分布
SELECT abnormal_reason, COUNT(*) AS cnt
FROM feishu_dws.dws_sku_abnormal_d
GROUP BY abnormal_reason
ORDER BY cnt DESC;

-- 3. 抽样查看异常 SKU
SELECT sku, style_no, size, style_no_size, brand,
       shelf_date_raw, first_sales_date, abnormal_reason
FROM feishu_dws.dws_sku_abnormal_d
ORDER BY sku
LIMIT 50;

-- 4. 校验：异常表 + 正常 SKU 商品维表 = 全部韦德 SKU
SELECT
    (SELECT COUNT(*) FROM feishu_dws.dws_sku_abnormal_d)      AS abnormal_cnt,
    (SELECT COUNT(*) FROM feishu_dws.dws_sku_product_info_d)  AS normal_cnt,
    (SELECT COUNT(*) FROM feishu_dwd.dwd_feishu_product_all_d WHERE brand = '韦德') AS total_cnt;
```

### feishu\_dws\.dws\_skc\_abnormal\_d

```SQL
SELECT * FROM feishu_dws.dws_skc_abnormal_d
-- 1. 异常 SKC 数量
SELECT COUNT(*) AS abnormal_skc_cnt FROM feishu_dws.dws_skc_abnormal_d;

-- 2. 异常原因分布
SELECT abnormal_reason, COUNT(*) AS cnt
FROM feishu_dws.dws_skc_abnormal_d
GROUP BY abnormal_reason
ORDER BY cnt DESC;

-- 3. 抽样查看异常 SKC
SELECT style_no, brand, shelf_date_raw, first_sales_date, abnormal_reason
FROM feishu_dws.dws_skc_abnormal_d
ORDER BY style_no
LIMIT 50;

-- 4. 校验：异常表 + 正常 SKC 商品维表 = 全部韦德 SKC（DISTINCT style_no）
SELECT
    (SELECT COUNT(*) FROM feishu_dws.dws_skc_abnormal_d)      AS abnormal_cnt,
    (SELECT COUNT(*) FROM feishu_dws.dws_skc_product_info_d)  AS normal_cnt,
    (SELECT COUNT(DISTINCT style_no) FROM feishu_dwd.dwd_feishu_product_all_d
     WHERE brand = '韦德')   
```

## ADS

### feishu\_ads\.ads\_sku\_sales\_plan\_180d\_d

```SQL
SELECT * FROM feishu_ads.ads_sku_sales_plan_180d_d
WHERE 1=1
and style_no_size = 'AAPV017-1-S'
SELECT * FROM feishu_dws.dws_sku_product_info_d
WHERE 1=1
and style_no_size = 'AAPV017-1-S'
SELECT
        CONCAT_WS('-', s.style_no, s.size)                 AS style_no_size,
        COALESCE(SUM(CASE WHEN s.sales_date < CURRENT_DATE() THEN s.qty ELSE 0 END), 0)
                                                          AS cum_actual,
        COALESCE(SUM(CASE WHEN s.sales_date >= DATE_SUB(CURRENT_DATE(), 30)
                          AND s.sales_date < CURRENT_DATE() THEN s.qty ELSE 0 END), 0)
                                                          AS last_30d_qty
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
      and CONCAT_WS('-', s.style_no, s.size) = 'AAPV017-1-S'
    GROUP BY CONCAT_WS('-', s.style_no, s.size)
  
SELECT * FROM feishu_dws.dws_sku_sales_plan_180d_d
WHERE 1=1
and style_no_size = 'AAPV017-1-S'
SELECT
        CONCAT_WS('-', s.style_no, s.size)                 AS style_no_size,
        s.sales_date                                       AS sales_date,
        COALESCE(SUM(s.qty), 0)                            AS daily_qty,
        COALESCE(SUM(s.amt), 0)                            AS daily_amt
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
      and CONCAT_WS('-', s.style_no, s.size) = 'AAPV017-1-S'
    GROUP BY CONCAT_WS('-', s.style_no, s.size), s.sales_date
-- 1. 行数核验：ADS 行数应与 DWS 销售计划表一致
SELECT
    (SELECT COUNT(*) FROM feishu_ads.ads_sku_sales_plan_180d_d) AS ads_cnt,
    (SELECT COUNT(*) FROM feishu_dws.dws_sku_sales_plan_180d_d) AS dws_cnt;

-- 2. 抽样：查看某SKU前30天的计划与实际
SELECT style_no_size, sale_date, lifecycle_day, sale_date_label, sales_phase,
       is_over_cycle, plan_pre, plan_post, daily_qty, cum_qty,
       achievement_rate, inventory_sku, available_inventory, sellable_days,
       yesterday_actual_qty, yesterday_achievement, today_plan_qty
FROM feishu_ads.ads_sku_sales_plan_180d_d
WHERE style_no_size LIKE 'ABAS083-11%'
  AND lifecycle_day BETWEEN 1 AND 30
ORDER BY style_no_size, sale_date
LIMIT 30;

-- 3. 校验：超周期行的 plan_pre/plan_post/achievement_rate 应为 NULL
SELECT COUNT(*) AS abnormal_cnt
FROM feishu_ads.ads_sku_sales_plan_180d_d
WHERE is_over_cycle = 1
  AND (plan_pre IS NOT NULL OR plan_post IS NOT NULL OR achievement_rate IS NOT NULL);

-- 4. 校验：sale_date_label 格式
SELECT DISTINCT lifecycle_day, sale_date_label
FROM feishu_ads.ads_sku_sales_plan_180d_d
WHERE lifecycle_day IN (1, 30, 31, 120, 121, 180, 181)
ORDER BY lifecycle_day;

-- 5. 校验：昨日/今日指标（同一SKU所有行值应相同）
SELECT style_no_size, sale_date, yesterday_actual_qty, yesterday_achievement,
       today_plan_qty, `7d_achievement`, `30d_achievement`
FROM feishu_ads.ads_sku_sales_plan_180d_d
WHERE style_no_size = (
    SELECT style_no_size
    FROM feishu_ads.ads_sku_sales_plan_180d_d
    WHERE yesterday_actual_qty > 0
    LIMIT 1
)
ORDER BY sale_date
LIMIT 10;

-- 6. 校验：cum_qty = cum_actual + actual_qty
SELECT sp.style_no_size, sp.sale_date, sp.lifecycle_day,
       sp.cum_actual AS dws_cum_actual,
       sp.actual_qty AS dws_actual_qty,
       sp.cum_actual + sp.actual_qty AS calc_cum_qty,
       ads.cum_qty AS ads_cum_qty
FROM feishu_dws.dws_sku_sales_plan_180d_d sp
INNER JOIN feishu_ads.ads_sku_sales_plan_180d_d ads
    ON sp.style_no_size = ads.style_no_size AND sp.sale_date = ads.sale_date
WHERE (sp.cum_actual + sp.actual_qty) <> ads.cum_qty
LIMIT 50;

-- 7. ⚠️ 财务字段人工审查：日金额与累计金额
SELECT style_no_size, sale_date, daily_qty, daily_amt, cum_qty, cum_amt
FROM feishu_ads.ads_sku_sales_plan_180d_d
WHERE daily_amt > 0 OR cum_amt > 0
ORDER BY sale_date DESC
LIMIT 20;
```

### feishu\_ads\.ads\_skc\_sales\_plan\_180d\_d

```SQL
SELECT * FROM feishu_ads.ads_skc_sales_plan_180d_d
-- 1. 行数核验：ADS 行数应与 DWS 销售计划表一致
SELECT
    (SELECT COUNT(*) FROM feishu_ads.ads_skc_sales_plan_180d_d) AS ads_cnt,
    (SELECT COUNT(*) FROM feishu_dws.dws_skc_sales_plan_180d_d) AS dws_cnt;

-- 2. 抽样：查看某SKC前30天的计划与实际
SELECT style_no, sale_date, lifecycle_day, sale_date_label, sales_phase,
       is_over_cycle, plan_pre, plan_post, daily_qty, cum_qty,
       achievement_rate, inventory_skc, available_inventory, sellable_days,
       yesterday_actual_qty, yesterday_achievement, today_plan_qty
FROM feishu_ads.ads_skc_sales_plan_180d_d
WHERE style_no = 'ABAS083-11'
  AND lifecycle_day BETWEEN 1 AND 30
ORDER BY sale_date
LIMIT 30;

-- 3. 校验：超周期行的销售计划应为 NULL
SELECT COUNT(*) AS abnormal_cnt
FROM feishu_ads.ads_skc_sales_plan_180d_d
WHERE is_over_cycle = 1
  AND (plan_pre IS NOT NULL OR plan_post IS NOT NULL OR achievement_rate IS NOT NULL);

-- 4. 校验：sale_date_label 格式
SELECT DISTINCT lifecycle_day, sale_date_label
FROM feishu_ads.ads_skc_sales_plan_180d_d
WHERE lifecycle_day IN (1, 30, 31, 120, 121, 180, 181)
ORDER BY lifecycle_day;

-- 5. SKU 与 SKC 数量对比（SKC 数应 ≤ SKU 数）
SELECT
    (SELECT COUNT(DISTINCT style_no_size) FROM feishu_ads.ads_sku_sales_plan_180d_d) AS sku_dim_cnt,
    (SELECT COUNT(DISTINCT style_no) FROM feishu_ads.ads_skc_sales_plan_180d_d)      AS skc_dim_cnt;

-- 6. 校验：cum_qty = cum_actual + actual_qty
SELECT sp.style_no, sp.sale_date, sp.lifecycle_day,
       sp.cum_actual AS dws_cum_actual,
       sp.actual_qty AS dws_actual_qty,
       sp.cum_actual + sp.actual_qty AS calc_cum_qty,
       ads.cum_qty AS ads_cum_qty
FROM feishu_dws.dws_skc_sales_plan_180d_d sp
INNER JOIN feishu_ads.ads_skc_sales_plan_180d_d ads
    ON sp.style_no = ads.style_no AND sp.sale_date = ads.sale_date
WHERE (sp.cum_actual + sp.actual_qty) <> ads.cum_qty
LIMIT 50;

-- 7. ⚠️ 财务字段人工审查：SKC 日金额与累计金额
SELECT style_no, sale_date, daily_qty, daily_amt, cum_qty, cum_amt
FROM feishu_ads.ads_skc_sales_plan_180d_d
WHERE daily_amt > 0 OR cum_amt > 0
ORDER BY sale_date DESC
LIMIT 20;
```

# 3、删除语句

```SQL
TRUNCATE TABLE  feishu_dwd.dwd_feishu_product_wd_d
TRUNCATE TABLE  feishu_dwd.dwd_feishu_product_361_d
TRUNCATE TABLE  feishu_dwd.dwd_feishu_product_all_d
TRUNCATE TABLE  feishu_dwd.dwd_feishu_inventory_wdpinpai_d
TRUNCATE TABLE  feishu_dwd.dwd_feishu_otb_wd_d
TRUNCATE TABLE  feishu_dwd.dwd_feishu_brand_order_arrival_d
TRUNCATE TABLE  feishu_dws.dws_sku_product_info_d
TRUNCATE TABLE  feishu_dws.dws_skc_product_info_d
TRUNCATE TABLE  feishu_dws.dws_sku_sales_plan_180d_d
TRUNCATE TABLE  feishu_dws.dws_skc_sales_plan_180d_d
TRUNCATE TABLE  feishu_dws.dws_sku_abnormal_d
TRUNCATE TABLE  feishu_dws.dws_skc_abnormal_d
TRUNCATE TABLE  feishu_ads.ads_sku_sales_plan_180d_d
TRUNCATE TABLE  feishu_ads.ads_skc_sales_plan_180d_d
```

# 4、插入语句

## DWD:

### feishu\_dwd\.dwd\_feishu\_sales\_361\_d

```SQL
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
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),     -- varchar类型，保留去空格和空串处理
    '361' AS brand,                                    -- 品牌标识（DWD新增）
    COALESCE(NULLIF(TRIM(SKU), ''), 'None'),           -- SKU编码（varchar类型，保留去空格和空串处理）
    COALESCE(DATE(销售日期), DATE('1970-01-01')),      -- 【修改】datetime类型，去掉TRIM/NULLIF，直接转DATE
    -- 4个渠道销量（【修改】decimal类型，去掉TRIM/NULLIF，增加ROUND防止小数直接转BIGINT报错）
    COALESCE(CAST(ROUND(`361sport-销量`, 0) AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(ROUND(`中国公司(361°客户)-销量`, 0) AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(ROUND(`361°寄样-销量`, 0) AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(ROUND(`员工内购（香港）-销量`, 0) AS BIGINT), 0) AS qty_staff_hk,
    -- 4个渠道金额（【修改】decimal类型，去掉TRIM/NULLIF，直接转换精度）
    COALESCE(CAST(`361sport-金额` AS DECIMAL(18,6)), 0.000000) AS amt_361sport,
    COALESCE(CAST(`中国公司(361°客户)-金额` AS DECIMAL(18,6)), 0.000000) AS amt_china,
    COALESCE(CAST(`361°寄样-金额` AS DECIMAL(18,6)), 0.000000) AS amt_sample,
    COALESCE(CAST(`员工内购（香港）-金额` AS DECIMAL(18,6)), 0.000000) AS amt_staff_hk,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_01'                                    AS source_table,
    NOW() AS insert_date,                              -- ETL写入插入时间
    NOW() AS update_date                               -- ETL写入更新时间
FROM feishu.t_361sales_01
WHERE record_id IS NOT NULL                            -- 过滤空记录

UNION ALL

SELECT
    id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    '361' AS brand,                                    
    COALESCE(NULLIF(TRIM(SKU), ''), 'None'),           
    COALESCE(DATE(销售日期), DATE('1970-01-01')),      
    -- 4个渠道销量
    COALESCE(CAST(ROUND(`361sport-销量`, 0) AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(ROUND(`中国公司(361°客户)-销量`, 0) AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(ROUND(`361°寄样-销量`, 0) AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(ROUND(`员工内购（香港）-销量`, 0) AS BIGINT), 0) AS qty_staff_hk,
    -- 4个渠道金额
    COALESCE(CAST(`361sport-金额` AS DECIMAL(18,6)), 0.000000) AS amt_361sport,
    COALESCE(CAST(`中国公司(361°客户)-金额` AS DECIMAL(18,6)), 0.000000) AS amt_china,
    COALESCE(CAST(`361°寄样-金额` AS DECIMAL(18,6)), 0.000000) AS amt_sample,
    COALESCE(CAST(`员工内购（香港）-金额` AS DECIMAL(18,6)), 0.000000) AS amt_staff_hk,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_02'                                    AS source_table,
    NOW() AS insert_date,                              
    NOW() AS update_date                               
FROM feishu.t_361sales_02 
WHERE record_id IS NOT NULL

-- ... 依次 UNION ALL feishu.t_361sales_03 ~ feishu.t_361sales_49 ...

UNION ALL

SELECT
    id,
    COALESCE(NULLIF(TRIM(record_id), ''), 'None'),
    '361' AS brand,                                    
    COALESCE(NULLIF(TRIM(SKU), ''), 'None'),           
    COALESCE(DATE(销售日期), DATE('1970-01-01')),      
    -- 4个渠道销量
    COALESCE(CAST(ROUND(`361sport-销量`, 0) AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(ROUND(`中国公司(361°客户)-销量`, 0) AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(ROUND(`361°寄样-销量`, 0) AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(ROUND(`员工内购（香港）-销量`, 0) AS BIGINT), 0) AS qty_staff_hk,
    -- 4个渠道金额
    COALESCE(CAST(`361sport-金额` AS DECIMAL(18,6)), 0.000000) AS amt_361sport,
    COALESCE(CAST(`中国公司(361°客户)-金额` AS DECIMAL(18,6)), 0.000000) AS amt_china,
    COALESCE(CAST(`361°寄样-金额` AS DECIMAL(18,6)), 0.000000) AS amt_sample,
    COALESCE(CAST(`员工内购（香港）-金额` AS DECIMAL(18,6)), 0.000000) AS amt_staff_hk,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_50'                                    AS source_table,
    NOW() AS insert_date,                              
    NOW() AS update_date                               
FROM feishu.t_361sales_50 
WHERE record_id IS NOT NULL;

```

### feishu\_dwd\.dwd\_feishu\_sales\_wd\_d

#### v1版本：

##### feishu\.wd\_sales\_01

```SQL
-- ============================================================
-- 合并50张分表：按结构差异分3类处理
-- 01：订货+补货数量  订货数量  --> 06:订货+补货1   订货+补货
-- 02：订货+补货数量  又没有订货数量字段
-- 03: 又只有 订货+补货字段，额外还有一个销售周期的所属周，离谱！
-- 04: 又只有 订货+补货字段，去掉销售周期的所属周，离谱！
-- 05: 和06一致
-- ============================================================

-- 类型A：wd_sales_01~06（55字段，最全）- 直接映射
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
    -- 字符串类型 (varchar)：保留 TRIM 和 NULLIF
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
    
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- ================= 销售指标 =================
    -- VARCHAR 转 BIGINT：场景二，先转 DECIMAL 再 ROUND 转 BIGINT，防止源数据带小数报错
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货数量`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS order_replenish_1,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货数量`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS order_replenish,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_total_qty,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS est_cycle_days,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS est_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`预计销量`, 0) AS BIGINT), 0)                               AS est_qty,
    
    -- VARCHAR 转 BIGINT：场景二
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一
    COALESCE(CAST(ROUND(`实际销量`, 0) AS BIGINT), 0)                               AS actual_qty,
    
    -- ================= 18个渠道销量 =================
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- ================= 18个渠道金额 =================
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST 控制精度，去除 TRIM 和 NULLIF
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- ================= 汇总字段 =================
    -- VARCHAR 转 DECIMAL(18,6)：场景二，保留 TRIM 和 NULLIF，直接转 DECIMAL
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST，去除 TRIM 和 NULLIF
    COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                 AS total_sum_copy,
    
    -- ================= 系统字段 =================
    -- 日期时间类型 (datetime)：场景一
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_01'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date    
FROM feishu.wd_sales_01
WHERE record_id IS NOT NULL;

```

##### feishu\.wd\_sales\_02

```SQL
-- ============================================================
-- 合并50张分表：按结构差异分3类处理
-- 02：订货+补货数量  又没有订货数量字段
-- ============================================================

-- 类型A：wd_sales_01~06（55字段，最全）- 直接映射
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
    -- 字符串类型 (varchar)：保留 TRIM 和 NULLIF
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
    
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- ================= 销售指标 =================
    -- VARCHAR 转 BIGINT：场景二，先转 DECIMAL 再 ROUND 转 BIGINT，防止源数据带小数报错
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货数量`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS order_replenish_1,
    
    -- 02表特有逻辑：没有订货数量字段，直接补0
    0                                                                               AS order_replenish,
    
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_total_qty,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS est_cycle_days,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS est_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`预计销量`, 0) AS BIGINT), 0)                               AS est_qty,
    
    -- VARCHAR 转 BIGINT：场景二
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一
    COALESCE(CAST(ROUND(`实际销量`, 0) AS BIGINT), 0)                               AS actual_qty,
    
    -- ================= 18个渠道销量 =================
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- ================= 18个渠道金额 =================
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST 控制精度，去除 TRIM 和 NULLIF
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- ================= 汇总字段 =================
    -- VARCHAR 转 DECIMAL(18,6)：场景二，保留 TRIM 和 NULLIF，直接转 DECIMAL
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST，去除 TRIM 和 NULLIF
    COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                 AS total_sum_copy,
    
    -- ================= 系统字段 =================
    -- 日期时间类型 (datetime)：场景一
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_02'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date    
FROM feishu.wd_sales_02
WHERE record_id IS NOT NULL;

```

##### feishu\.wd\_sales\_03

```SQL
-- ============================================================
-- 合并50张分表：按结构差异分3类处理
-- 03: 又只有 订货+补货字段，额外还有一个销售周期的所属周，离谱！
-- ============================================================

-- 类型A：wd_sales_01~06（55字段，最全）- 直接映射
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
    -- 字符串类型 (varchar)：保留 TRIM 和 NULLIF
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
    
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- ================= 销售指标 =================
    -- 03表特有逻辑：只有"订货+补货"字段，映射到 order_replenish_1
    -- VARCHAR 转 BIGINT：场景二，先转 DECIMAL 再 ROUND 转 BIGINT，防止源数据带小数报错
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS order_replenish_1,
    
    -- 03表特有逻辑：没有订货数量字段，直接补0
    0                                                                               AS order_replenish,
    
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_total_qty,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS est_cycle_days,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS est_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`预计销量`, 0) AS BIGINT), 0)                               AS est_qty,
    
    -- VARCHAR 转 BIGINT：场景二
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一
    COALESCE(CAST(ROUND(`实际销量`, 0) AS BIGINT), 0)                               AS actual_qty,
    
    -- ================= 18个渠道销量 =================
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- ================= 18个渠道金额 =================
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST 控制精度，去除 TRIM 和 NULLIF
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- ================= 汇总字段 =================
    -- VARCHAR 转 DECIMAL(18,6)：场景二，保留 TRIM 和 NULLIF，直接转 DECIMAL
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST，去除 TRIM 和 NULLIF
    COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                 AS total_sum_copy,
    
    -- ================= 系统字段 =================
    -- 日期时间类型 (datetime)：场景一
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_03'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date    
FROM feishu.wd_sales_03
WHERE record_id IS NOT NULL;

```

##### feishu\.wd\_sales\_04

```SQL
-- ============================================================
-- 合并50张分表：按结构差异分3类处理
-- 04: 又只有 订货+补货字段，去掉销售周期的所属周，离谱！
-- ============================================================

-- 类型A：wd_sales_01~06（55字段，最全）- 直接映射
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
    -- 字符串类型 (varchar)：保留 TRIM 和 NULLIF
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
    
    -- 04表特有逻辑：源表去掉了"销售周期所属周"字段，直接补 'None' 防止 Column not found 报错
    'None'                                                                          AS sales_week,
    
    -- ================= 销售指标 =================
    -- 04表特有逻辑：只有"订货+补货"字段，映射到 order_replenish_1
    -- VARCHAR 转 BIGINT：场景二，先转 DECIMAL 再 ROUND 转 BIGINT，防止源数据带小数报错
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS order_replenish_1,
    
    -- 04表特有逻辑：没有订货数量字段，直接补0
    0                                                                               AS order_replenish,
    
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_total_qty,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS est_cycle_days,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS est_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`预计销量`, 0) AS BIGINT), 0)                               AS est_qty,
    
    -- VARCHAR 转 BIGINT：场景二
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一
    COALESCE(CAST(ROUND(`实际销量`, 0) AS BIGINT), 0)                               AS actual_qty,
    
    -- ================= 18个渠道销量 =================
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- ================= 18个渠道金额 =================
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST 控制精度，去除 TRIM 和 NULLIF
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- ================= 汇总字段 =================
    -- VARCHAR 转 DECIMAL(18,6)：场景二，保留 TRIM 和 NULLIF，直接转 DECIMAL
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST，去除 TRIM 和 NULLIF
    COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                 AS total_sum_copy,
    
    -- ================= 系统字段 =================
    -- 日期时间类型 (datetime)：场景一
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_04'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date    
FROM feishu.wd_sales_04
WHERE record_id IS NOT NULL;

```

##### feishu\.wd\_sales\_05

```SQL
-- ============================================================
-- 合并50张分表：按结构差异分3类处理
-- 05: 和06一致
-- ============================================================

-- 类型A：wd_sales_01~06（55字段，最全）- 直接映射
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
    -- 字符串类型 (varchar)：保留 TRIM 和 NULLIF
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
    
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- ================= 销售指标 =================
    -- 05表特有逻辑：包含"订货+补货1"和"订货+补货"两个字段
    -- VARCHAR 转 BIGINT：场景二，先转 DECIMAL 再 ROUND 转 BIGINT，防止源数据带小数报错
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货1`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS order_replenish_1,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)  AS order_replenish,
    
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_total_qty,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS est_cycle_days,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS est_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`预计销量`, 0) AS BIGINT), 0)                               AS est_qty,
    
    -- VARCHAR 转 BIGINT：场景二
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一
    COALESCE(CAST(ROUND(`实际销量`, 0) AS BIGINT), 0)                               AS actual_qty,
    
    -- ================= 18个渠道销量 =================
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- ================= 18个渠道金额 =================
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST 控制精度，去除 TRIM 和 NULLIF
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- ================= 汇总字段 =================
    -- VARCHAR 转 DECIMAL(18,6)：场景二，保留 TRIM 和 NULLIF，直接转 DECIMAL
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST，去除 TRIM 和 NULLIF
    COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                 AS total_sum_copy,
    
    -- ================= 系统字段 =================
    -- 日期时间类型 (datetime)：场景一
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_05'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date    
FROM feishu.wd_sales_05
WHERE record_id IS NOT NULL;

```

##### feishu\.wd\_sales\_06

```SQL
-- ============================================================
-- 合并50张分表：按结构差异分3类处理
-- 05: 和06一致
-- ============================================================

-- 类型A：wd_sales_01~06（55字段，最全）- 直接映射
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
    -- 字符串类型 (varchar)：保留 TRIM 和 NULLIF
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
    
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- ================= 销售指标 =================
    -- 05表特有逻辑：包含"订货+补货1"和"订货+补货"两个字段
    -- VARCHAR 转 BIGINT：场景二，先转 DECIMAL 再 ROUND 转 BIGINT，防止源数据带小数报错
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货1`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS order_replenish_1,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)  AS order_replenish,
    
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_total_qty,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS est_cycle_days,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS est_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`预计销量`, 0) AS BIGINT), 0)                               AS est_qty,
    
    -- VARCHAR 转 BIGINT：场景二
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)      AS actual_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一
    COALESCE(CAST(ROUND(`实际销量`, 0) AS BIGINT), 0)                               AS actual_qty,
    
    -- ================= 18个渠道销量 =================
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- ================= 18个渠道金额 =================
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST 控制精度，去除 TRIM 和 NULLIF
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- ================= 汇总字段 =================
    -- VARCHAR 转 DECIMAL(18,6)：场景二，保留 TRIM 和 NULLIF，直接转 DECIMAL
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST，去除 TRIM 和 NULLIF
    COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                 AS total_sum_copy,
    
    -- ================= 系统字段 =================
    -- 日期时间类型 (datetime)：场景一
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_06'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date    
FROM feishu.wd_sales_06
WHERE record_id IS NOT NULL;

```

##### feishu\.wd\_sales\_23

```SQL
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
    -- 字符串类型 (varchar)：保留 TRIM 和 NULLIF
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
    
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- ================= 销售指标 =================
    -- 23分表缺少的销售指标字段补0（7个缺失指标）
    0                                                                               AS order_replenish_1,
    0                                                                               AS order_replenish,
    0                                                                               AS actual_total_qty,
    0                                                                               AS est_cycle_days,
    0                                                                               AS est_week_qty,
    0                                                                               AS est_qty,
    0                                                                               AS actual_week_qty,
    
    -- 23分表"实际销量"为 varchar，需 CAST：场景二，先转 DECIMAL 再 ROUND 转 BIGINT，防止源数据带小数报错
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS actual_qty,
    
    -- ================= 18个渠道销量 =================
    -- 18个渠道销量（23分表有，与06一致），物理类型为 decimal：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- ================= 18个渠道金额 =================
    -- 18个渠道金额，物理类型为 decimal：场景一，直接 CAST 控制精度，去除 TRIM 和 NULLIF
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- ================= 汇总字段 =================
    -- 汇总字段（23有"总和"无"总和副本"）
    -- "总和" 为 varchar：场景二，保留 TRIM 和 NULLIF，直接转 DECIMAL
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    
    -- 缺失"总和副本"，直接补0
    0                                                                               AS total_sum_copy,
    
    -- ================= 系统字段 =================
    -- 日期时间类型 (datetime)：场景一
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_23'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date
    
FROM feishu.wd_sales_23
WHERE record_id IS NOT NULL;

```

##### feishu\.wd\_sales\_50

```SQL
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
    -- 字符串类型 (varchar)：保留 TRIM 和 NULLIF
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
    -- 款号/尺码缺失补 'None'
    'None'                                                                          AS style_no,
    'None'                                                                          AS size,
    
    -- 首次销售日期/销售周期缺失补默认值
    DATE('1970-01-01')                                                              AS first_sales_date,
    'None'                                                                          AS sales_week,
    
    -- ================= 销售指标 =================
    -- 8个销售指标全缺失补 0
    0                                                                               AS order_replenish_1,
    0                                                                               AS order_replenish,
    0                                                                               AS actual_total_qty,
    0                                                                               AS est_cycle_days,
    0                                                                               AS est_week_qty,
    0                                                                               AS est_qty,
    0                                                                               AS actual_week_qty,
    0                                                                               AS actual_qty,
    
    -- ================= 18个渠道销量 =================
    -- 18个渠道销量（30/50有，与06一致），物理类型为 decimal：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- ================= 18个渠道金额 =================
    -- 18个渠道金额，物理类型为 decimal：场景一，直接 CAST 控制精度，去除 TRIM 和 NULLIF
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- ================= 汇总字段 =================
    -- 汇总字段补 0（30/50无）
    0                                                                               AS total_sum,
    0                                                                               AS total_sum_copy,
    
    -- ================= 系统字段 =================
    -- 日期时间类型 (datetime)：场景一
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_30'                                                                   AS source_table,
    NOW()                                                                           AS insert_date,
    NOW()                                                                           AS update_date
FROM feishu.wd_sales_30
WHERE record_id IS NOT NULL;

```

#### v2版本：

```SQL
-- ============================================================
  -- 合并50张分表：以feishu.wd_sales_01结构为准。
  -- 字段命名用``符号包裹：`销售日期`、`款号`
  -- 遗漏了4个字段：你在头部注释提到了需补充 natural_week（自然周）、order_qty（订货数量）、achievement_rate（达成率）、alert（预警），但在 INSERT 字段列 表和 SELECT 中均未实际添加。
  -- 源表字段映射错位修正：原SQL中，你将源表的 订货+补货数量 映射给了 order_replenish_1，将 订货数量 映射给了 order_replenish。根据建表语句的注释，正确的对应关系应为：订货+补货1 -> order_replenish_1，订货+补货数量 -> order_replenish，订货数量 -> order_qty。已一并修正。
  -- 插入了 63 个字段，与建表字段完全对齐
  -- ============================================================
  TRUNCATE TABLE feishu_dwd.dwd_feishu_sales_wd_d;
  INSERT INTO feishu_dwd.dwd_feishu_sales_wd_d (
      id, record_id, brand, sku, sales_date, style_no, size, first_sales_date, natural_week, sales_week,
      order_replenish_1, order_replenish, order_qty, actual_total_qty, est_cycle_days, est_week_qty,
      est_qty, actual_week_qty, actual_qty, achievement_rate, alert,
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
      -- 字符串类型 (varchar)：保留 TRIM 和 NULLIF
      COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
      '韦德'                                                                           AS brand,
      COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
      -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
      COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
      COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
      COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
      -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
      COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
      -- 补充遗漏字段：自然周 (需补充在维度列中)
      COALESCE(NULLIF(TRIM(自然周), ''), 'None')                                      AS natural_week,
      COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
      -- ================= 销售指标 =================
      -- VARCHAR 转 BIGINT：场景二，先转 DECIMAL 再 ROUND 转 BIGINT，防止源数据带小数报错
      -- 修正映射：订货+补货1 -> order_replenish_1
      COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货1`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish_1,
      -- 修正映射：订货+补货数量 -> order_replenish
      COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish,
      -- 补充遗漏字段：订货数量 (需补充在销售指标度量列中)
      COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_qty,
      COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0)      AS actual_total_qty,
      COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_cycle_days,
      COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0)      AS est_week_qty,
      -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
      COALESCE(CAST(ROUND(`预计销量`, 0) AS BIGINT), 0)                               AS est_qty,
      -- VARCHAR 转 BIGINT：场景二
      COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0)      AS actual_week_qty,
      -- DECIMAL 转 BIGINT：场景一
      COALESCE(CAST(ROUND(`实际销量`, 0) AS BIGINT), 0)                               AS actual_qty,
      -- 补充遗漏字段：达成率、预警 (需补充在销售指标度量列中)
      COALESCE(NULLIF(TRIM(`达成率`), ''), 'None')                                   AS achievement_rate,
      COALESCE(NULLIF(TRIM(`预警`), ''), 'None')                                     AS alert,
      -- ================= 18个渠道销量 =================
      -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
      COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
      COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
      COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
      COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
      COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
      COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
      COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
      COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
      COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
      COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
      COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
      COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
      COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
      COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
      COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
      COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
      COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
      COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
      -- ================= 18个渠道金额 =================
      -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST 控制精度，去除 TRIM 和 NULLIF
      COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
      COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
      COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
      COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
      COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
      COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
      COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
      COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
      COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
      COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
      COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
      COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
      COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
      COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
      COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
      COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
      COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
      COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
      -- ================= 汇总字段 =================
      -- VARCHAR 转 DECIMAL(18,6)：场景二，保留 TRIM 和 NULLIF，直接转 DECIMAL
      COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
      -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST，去除 TRIM 和 NULLIF
      COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                 AS total_sum_copy,
      -- ================= 系统字段 =================
      -- 日期时间类型 (datetime)：场景一
      COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
      'wd_sales_01'                                                                   AS source_table,
      NOW()                                                                           AS insert_date,
      NOW()                                                                           AS update_date    
  FROM feishu.wd_sales_01
  WHERE record_id IS NOT NULL;
```

### feishu\_dwd\.dwd\_feishu\_sales\_all\_d

#### 361渠道

```SQL
USE feishu_dwd;
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
```

#### 韦德渠道

```SQL
USE feishu_dwd;
TRUNCATE TABLE feishu_dwd.dwd_feishu_sales_all_d;
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

### feishu\_dwd\.dwd\_feishu\_product\_wd\_d

```SQL
-- ============================================================
-- DWD-4 ETL: 韦德商品库清洗表（日刷新）数据写入
-- 来源：feishu.wd_shop (ODS) -> feishu_dwd.dwd_feishu_product_wd_d (DWD)
-- 说明：
-- 1. 针对飞书多维表格导出的 varchar 类型进行清洗与类型转换。
-- 2. 金额、比率及含小数的指标统一使用 DECIMAL(38,6) 防止精度丢失。
-- 3. 整数指标增加正则校验，过滤非数字脏数据，防止转换失败导致行被过滤。
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
    
    -- 2. 维度列：商品主数据与归类 (均为 varchar，保留清洗逻辑)
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
    COALESCE(CAST(吊牌价 AS DECIMAL(38,6)), 0)                               AS tag_price,       -- 【修改】ODS为decimal，去掉TRIM/NULLIF
    COALESCE(CAST(折扣 AS DECIMAL(38,6)), 0)                                 AS discount,        -- 【修改】ODS为decimal，去掉TRIM/NULLIF
    COALESCE(CAST(NULLIF(TRIM(回款价), '') AS DECIMAL(38,6)), 0)             AS payment_price,   -- ODS为varchar，保留
    COALESCE(CAST(NULLIF(TRIM(`实际销售价（$）`), '') AS DECIMAL(38,6)), 0)  AS actual_sales_price, -- ODS为varchar，保留
    
    -- 4. 度量列：订货信息（ODS为varchar，保留正则校验过滤非数字字符）
    COALESCE(CASE WHEN TRIM(`订货数量(sku)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`订货数量(sku)`) AS BIGINT) ELSE 0 END, 0) AS order_qty_sku,
    COALESCE(CASE WHEN TRIM(`订货数量(SKC)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`订货数量(SKC)`) AS BIGINT) ELSE 0 END, 0) AS order_qty_skc,
    
    -- 5. 维度列：时间信息与状态
    COALESCE(DATE(订货日期), DATE('1970-01-01'))                             AS order_date,      -- 【修改】ODS为datetime，去掉TRIM/NULLIF
    COALESCE(DATE(预计到货日期), DATE('1970-01-01'))                         AS est_arrival_date,-- 【修改】ODS为datetime，去掉TRIM/NULLIF
    COALESCE(NULLIF(TRIM(预计到货月份), ''), 'None')                         AS est_arrival_month,
    COALESCE(DATE(首次可提日期), DATE('1970-01-01'))                         AS first_available_pickup_date, -- 【修改】ODS为datetime
    COALESCE(DATE(首次提货日期), DATE('1970-01-01'))                         AS first_pickup_date,         -- 【修改】ODS为datetime
    COALESCE(NULLIF(TRIM(计划销售时间), ''), 'None')                         AS planned_sales_time,
    COALESCE(NULLIF(TRIM(预计上架时间), ''), 'None')                         AS est_shelf_time,
    -- 20260713 上架日期 --> 实际上架日期
    COALESCE(DATE(实际上架日期), DATE('1970-01-01'))                         AS shelf_date,      -- 【修改】ODS为datetime，去掉      -- 【修改】ODS为datetime，去掉TRIM/NULLIF
    COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                         AS first_sales_date,-- 【修改】ODS为datetime，去掉TRIM/NULLIF
    COALESCE(DATE(NULLIF(TRIM(实际售卖最小日期), '')), DATE('1970-01-01'))   AS actual_sales_min_date, -- ODS为varchar，保留
    COALESCE(NULLIF(TRIM(首次订货季度), ''), 'None')                         AS first_order_quarter,
    COALESCE(NULLIF(TRIM(年份), ''), 'None')                                 AS year,
    COALESCE(NULLIF(TRIM(销售周期标签), ''), 'None')                         AS sales_cycle_label,
    COALESCE(NULLIF(TRIM(是否确认过), ''), 'None')                           AS is_confirmed,
    
    -- 6. 度量列：库存信息（ODS均为varchar，保留正则校验过滤非数字字符）
    COALESCE(CASE WHEN TRIM(`库存数量(SKU)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`库存数量(SKU)`) AS BIGINT) ELSE 0 END, 0) AS inventory_sku,
    COALESCE(CASE WHEN TRIM(`库存数量(SKC)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`库存数量(SKC)`) AS BIGINT) ELSE 0 END, 0) AS inventory_skc,
    COALESCE(CASE WHEN TRIM(库存合计) REGEXP '^[0-9]+$' THEN CAST(TRIM(库存合计) AS BIGINT) ELSE 0 END, 0) AS inventory_total,
    COALESCE(CASE WHEN TRIM(杭州库存) REGEXP '^[0-9]+$' THEN CAST(TRIM(杭州库存) AS BIGINT) ELSE 0 END, 0) AS inventory_hz,
    COALESCE(CASE WHEN TRIM(保税库存) REGEXP '^[0-9]+$' THEN CAST(TRIM(保税库存) AS BIGINT) ELSE 0 END, 0) AS inventory_baoshui,
    COALESCE(CASE WHEN TRIM(非保库存) REGEXP '^[0-9]+$' THEN CAST(TRIM(非保库存) AS BIGINT) ELSE 0 END, 0) AS inventory_feibao,
    
    -- 7. 度量列：销售指标
    COALESCE(NULLIF(TRIM(评级), ''), 'None')                                 AS rating,
    -- 【修改】销售周期天数 ODS为decimal，原正则转BIGINT改为 ROUND后转BIGINT，防止小数截断报错
    COALESCE(CAST(ROUND(销售周期天数, 0) AS BIGINT), 0)                      AS sales_cycle_days,
    
    -- 销售目标 ODS为varchar，保留
    COALESCE(CAST(NULLIF(TRIM(`销售目标（日）`), '') AS DECIMAL(38,6)), 0)   AS daily_target,
    COALESCE(CAST(NULLIF(TRIM(`销售目标（周）`), '') AS DECIMAL(38,6)), 0)   AS weekly_target,
    COALESCE(CAST(NULLIF(TRIM(`销售目标（月）`), '') AS DECIMAL(38,6)), 0)   AS monthly_target,
    COALESCE(CAST(NULLIF(TRIM(`销售目标（季）`), '') AS DECIMAL(38,6)), 0)   AS quarterly_target,
    
    -- 销量与累积 ODS为varchar，保留正则校验
    COALESCE(CASE WHEN TRIM(官网当日销售) REGEXP '^[0-9]+$' THEN CAST(TRIM(官网当日销售) AS BIGINT) ELSE 0 END, 0) AS official_daily_sales,
    COALESCE(CASE WHEN TRIM(`销售累积数量(不含本周）`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`销售累积数量(不含本周）`) AS BIGINT) ELSE 0 END, 0) AS cum_sales_excl_current_week,
    COALESCE(CASE WHEN TRIM(`销售累计数量(SKU)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`销售累计数量(SKU)`) AS BIGINT) ELSE 0 END, 0) AS cum_sales_sku,
    COALESCE(CASE WHEN TRIM(`销售累计数量(SKC)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`销售累计数量(SKC)`) AS BIGINT) ELSE 0 END, 0) AS cum_sales_skc,
    COALESCE(CAST(NULLIF(TRIM(SKC达成率), '') AS DECIMAL(38,6)), 0)          AS skc_achievement,
    COALESCE(CASE WHEN TRIM(实际售卖天数) REGEXP '^[0-9]+$' THEN CAST(TRIM(实际售卖天数) AS BIGINT) ELSE 0 END, 0) AS actual_sales_days,
    COALESCE(CAST(NULLIF(TRIM(实际日均销量), '') AS DECIMAL(38,6)), 0)       AS actual_daily_avg,
    
    -- 8. 度量列：补货预警
    -- 补货量/数量 ODS为varchar，保留正则校验
    COALESCE(CASE WHEN TRIM(补货量) REGEXP '^[0-9]+$' THEN CAST(TRIM(补货量) AS BIGINT) ELSE 0 END, 0) AS replenish_qty,
    COALESCE(CASE WHEN TRIM(补货数量) REGEXP '^[0-9]+$' THEN CAST(TRIM(补货数量) AS BIGINT) ELSE 0 END, 0) AS replenish_num,
    
    COALESCE(NULLIF(TRIM(补货修正), ''), 'None')                             AS replenish_correction,
    -- 差异/周转天数 ODS为varchar，保留
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

### feishu\_dwd\.dwd\_feishu\_product\_361\_d

```SQL
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
    -- ODS为DATETIME，去掉TRIM 20260713 预计到货日期 -->预计到货时间
    COALESCE(
            CAST(
                CASE 
                    WHEN `预计到货时间` REGEXP '^[0-9]{4}[-/][0-9]{2}[-/][0-9]{2}$' 
                    THEN REPLACE(`预计到货时间`, '/', '-')
                    ELSE NULL 
                END AS DATE
            ), 
            CAST('1970-01-01' AS DATE)
        )                                                                 AS est_arrival_date,
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
    -- 【微调】为兜底值增加显式 CAST，确保在 Presto/Trino 等严格引擎中不会因隐式转换导致类型变为 STRING
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))            AS sync_time,
    NOW()                                                                   AS insert_date,                                -- ETL写入插入时间
    NOW()                                                                   AS update_date                                 -- ETL写入更新时间
FROM feishu.t_361_shop
WHERE SKU IS NOT NULL AND TRIM(SKU) <> '';                    -- 过滤空SKU（577条空SKU被过滤）

```

### feishu\_dwd\.dwd\_feishu\_product\_all\_d

#### 韦德商品库

```SQL
-- 韦德商品库（来源DWD-4）
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku, 
    order_qty_skc, inventory_skc, sales_cycle_label, is_replenish, replenish_qty,
    sync_time,insert_date, update_date
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
    -- 使用 NULLIF 将默认的 '1970-01-01' 转为 NULL，避免影响上架天数计算，韦德直接取上架日期
    NULLIF(CAST(wd.shelf_date AS DATE), CAST('1970-01-01' AS DATE))   AS shelf_date, 
    COALESCE(fs.first_sales_date, fs.first_sales_date) AS first_sales_date,
    wd.first_order_quarter,
    wd.year,
    wd.inventory_sku,
        -- 新增字段
    wd.order_qty_skc, wd.inventory_skc, wd.sales_cycle_label,
    COALESCE(NULLIF(wd.is_replenish, ''), '否'),
    COALESCE(wd.replenish_qty, 0),
    wd.sync_time,
    NOW() AS insert_date,                                            -- ETL写入插入时间
    NOW() AS update_date                                             -- ETL写入更新时间
FROM feishu_dwd.dwd_feishu_product_wd_d wd
LEFT JOIN (
    SELECT sku, MIN(sales_date) AS first_sales_date
    FROM feishu_dwd.dwd_feishu_sales_all_d
    WHERE brand = '韦德' AND qty > 0
    GROUP BY sku
) fs ON wd.sku = fs.sku
WHERE wd.sku IS NOT NULL;
```

#### 361商品库

```SQL
-- 361商品库（来源DWD-5）
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku, 
    order_qty_skc, inventory_skc, sales_cycle_label, is_replenish, replenish_qty,
    sync_time,insert_date, update_date
)
SELECT
    p.sku                                                                   AS sku,
    '361'                                                                   AS brand,
    p.style_no                                                              AS style_no,
    p.ip                                                                    AS ip,
    p.series                                                                AS series,
    NULL                                                                    AS color_name,                                  -- 361无配色名
    p.product_name                                                          AS product_name,
    p.category                                                              AS category,
    p.size_us                                                               AS size,                                        -- 361用美码作为统一尺码
    p.tag_price                                                             AS tag_price,
    p.order_qty                                                             AS order_qty,
    p.order_date                                                            AS order_date,

    -- 使用 NULLIF 将默认的 '1970-01-01' 转为 NULL，避免影响上架天数计算，361取实际上架时间作为统一上架日期
    NULLIF(CAST(p.actual_shelf_date AS DATE), CAST('1970-01-01' AS DATE))   AS shelf_date,                                  -- 361取实际上架时间作为统一上架日期
     -- 预计算：从销售明细表取最早有销量的日期
    COALESCE(fs.first_sales_date, CAST(NULL AS DATE))                       AS first_sales_date,
    first_order_quarter                                                     AS first_order_quarter,
    NULL                                                                    AS year,                                        -- 361商品库无年份字段
    NULL                                                                    AS inventory_sku,                               -- 361商品库无SKU维度库存
    -- 361 无补货概念
    CAST(NULL AS BIGINT) AS order_qty_skc,
    CAST(NULL AS BIGINT) AS inventory_skc,
    CAST(NULL AS VARCHAR) AS sales_cycle_label,
    '否' AS is_replenish,
    0 AS replenish_qty,
    p.sync_time                                                             AS sync_time,
    NOW()                                                                   AS insert_date,
    NOW()                                                                   AS update_date
FROM feishu_dwd.dwd_feishu_product_361_d p
LEFT JOIN (
    SELECT sku, MIN(sales_date) AS first_sales_date
    FROM feishu_dwd.dwd_feishu_sales_all_d
    WHERE brand = '361' AND qty > 0
    GROUP BY sku
) fs ON p.sku = fs.sku
WHERE p.sku IS NOT NULL;

-- 验证：
-- SELECT brand, COUNT(*) FROM feishu_dwd.dwd_feishu_product_all_d GROUP BY brand;  -- 各品牌SKU数
-- SELECT COUNT(DISTINCT CONCAT(sku,'_',brand)) FROM feishu_dwd.dwd_feishu_product_all_d;  -- SKU+品牌去重数（应等于总行数）
```

### feishu\_dwd\.dwd\_feishu\_inventory\_wdpinpai\_d

```SQL
INSERT INTO feishu_dwd.dwd_feishu_inventory_wdpinpai_d (
    id, inventory_date, record_id, sku, style_no, quarter, ip, product_name, series,
    color_name, category, size,
    inventory_qty, price_with_tax, tag_price, order_qty, picked_qty, unpicked_qty,
    pickup_flag, min_granularity, sync_time, insert_date, update_date
)
SELECT
    inv.id                                                                    AS id,
    -- 【修改】ODS为datetime，去掉TRIM/NULLIF，直接提取DATE
    COALESCE(DATE(inv.品牌方库存更新日期), DATE('1970-01-01'))                  AS inventory_date,
    
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
    -- 【修改】ODS为decimal，去掉TRIM/NULLIF，直接CAST；同时将SIGNED修正为标准的BIGINT
    COALESCE(CAST(inv.库存数量 AS BIGINT), 0)                                 AS inventory_qty,
    -- 【修改】ODS为decimal，去掉TRIM/NULLIF，直接CAST
    COALESCE(CAST(inv.含税单价 AS DECIMAL(18,6)), 0)                          AS price_with_tax,
    -- 【修改】ODS为decimal，去掉TRIM/NULLIF，直接CAST
    COALESCE(CAST(inv.吊牌价 AS DECIMAL(18,6)), 0)                            AS tag_price,
    
    -- 【修正】将MySQL方言 SIGNED 统一修正为大数据标准类型 BIGINT，ODS为varchar，保留TRIM/NULLIF
    COALESCE(CAST(NULLIF(TRIM(inv.订货数量), '') AS BIGINT), 0)               AS order_qty,                            
    COALESCE(CAST(NULLIF(TRIM(inv.已提数量), '') AS BIGINT), 0)               AS picked_qty,                           
    COALESCE(CAST(NULLIF(TRIM(inv.未提数量), '') AS BIGINT), 0)               AS unpicked_qty,                         
    
    COALESCE(NULLIF(TRIM(inv.提货标识), ''), 'None')                          AS pickup_flag,
    COALESCE(NULLIF(TRIM(inv.最小颗粒度), ''), 'None')                        AS min_granularity,
    
    -- ODS为datetime，原SQL已正确处理，保留
    COALESCE(inv.sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))          AS sync_time,
    NOW()                                                                     AS insert_date,
    NOW()                                                                     AS update_date
FROM feishu.wd_pinpaikucun inv
WHERE inv.sku IS NOT NULL AND TRIM(inv.sku) <> '';

```

### feishu\_dwd\.dwd\_feishu\_otb\_wd\_d

```SQL
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
    
    -- 【修改】ODS为decimal，去掉TRIM/NULLIF，直接CAST
    COALESCE(CAST(otb.`OTB（单位：亿）` AS DECIMAL(18,6)), 0)               AS otb_amount_yi,   -- decimal转DECIMAL(18,6)，单位：亿（如2.000000）
    -- 【修改】ODS为decimal，去掉TRIM/NULLIF，直接CAST
    COALESCE(CAST(otb.订货金额占比 AS DECIMAL(18,6)), 0)                    AS order_amount_ratio,-- decimal转DECIMAL(18,6)，比值（如0.019400）
    
    -- ODS为varchar，保留TRIM/NULLIF，防止空字符串转DECIMAL报错
    COALESCE(CAST(NULLIF(TRIM(otb.订货牌价), '') AS DECIMAL(18,6)), 0)      AS order_tag_price,   -- varchar转DECIMAL(18,6)，金额（如7129800）
    COALESCE(CAST(NULLIF(TRIM(otb.OTB), '') AS DECIMAL(18,6)), 0)           AS otb_raw,           -- varchar转DECIMAL(18,6)，原始值（如7.02，与otb_amount_yi语义不同）
    
    -- ODS为datetime，原SQL处理正确，保留
    COALESCE(otb.sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))        AS sync_time,
    NOW()                                                                   AS insert_date,       -- ETL写入插入时间
    NOW()                                                                   AS update_date        -- ETL写入更新时间
FROM feishu.wd_otb otb
WHERE otb.record_id IS NOT NULL
  AND otb.IP IS NOT NULL
  AND otb.年度 IS NOT NULL;

```

### feishu\_dwd\.dwd\_feishu\_brand\_order\_arrival\_d

```SQL
*-- =============================================*
*-- 2. DWD 层清洗插入语句 (含拼接与聚合逻辑)*
*-- =============================================*
INSERT INTO feishu_dwd.dwd_feishu_brand_order_arrival_d (
    style_no_size, sku, style_no, size_code, ip, series, color_name, product_name, category, pickup_status, est_arrival_month,
    order_qty, picked_qty, unpicked_qty, brand_stock_qty, unpicked_avail_qty, unpicked_unavail_qty, cumulative_order_qty,
    est_arrival_date, 30_est_arrival_date, sync_time, insert_date, update_date
)
WITH base_data AS (
    *-- 步骤1: 基础数据清洗与类型转换，并生成主键 style_no_size*
    SELECT
        *-- 拼接主键：CONCAT_WS('-', style_no, size_code)*
        CONCAT_WS('-', 
            COALESCE(NULLIF(TRIM(款号), ''), 'None'), 
            COALESCE(NULLIF(TRIM(尺码), ''), 'None')
        )                                                         AS style_no_size,
        
        COALESCE(NULLIF(TRIM(商品SKU), ''), 'None')               AS sku,
        COALESCE(NULLIF(TRIM(款号), ''), 'None')                   AS style_no,
        COALESCE(NULLIF(TRIM(尺码), ''), 'None')                   AS size_code,
        COALESCE(NULLIF(TRIM(IP), ''), 'None')                     AS ip,
        COALESCE(NULLIF(TRIM(系列), ''), 'None')                   AS series,
        COALESCE(NULLIF(TRIM(配色名), ''), 'None')                 AS color_name,
        COALESCE(NULLIF(TRIM(品名), ''), 'None')                   AS product_name,
        COALESCE(NULLIF(TRIM(商品分类), ''), 'None')              AS category,
        COALESCE(NULLIF(TRIM(提货状态), ''), 'None')               AS pickup_status,
        COALESCE(NULLIF(TRIM(预计到货年月), ''), 'None')           AS est_arrival_month,
        
        *-- 数值字段安全转换，为后续聚合叠加做准备*
        COALESCE(CAST(订货数量 AS BIGINT), 0)                      AS order_qty,
        COALESCE(CAST(NULLIF(TRIM(已提货数量), '') AS BIGINT), 0)  AS picked_qty,
        COALESCE(CAST(NULLIF(TRIM(未提货数量), '') AS BIGINT), 0)  AS unpicked_qty,
        COALESCE(CAST(NULLIF(TRIM(品牌库存数量), '') AS BIGINT), 0) AS brand_stock_qty,
        COALESCE(CAST(NULLIF(TRIM(未提可提数量), '') AS BIGINT), 0) AS unpicked_avail_qty,
        COALESCE(CAST(NULLIF(TRIM(未提不可提数量), '') AS BIGINT), 0) AS unpicked_unavail_qty,
        COALESCE(CAST(NULLIF(TRIM(累计订货), '') AS BIGINT), 0)    AS cumulative_order_qty,
        
        *-- 日期处理：为空则 CAST(NULL AS DATE)*
        COALESCE(CAST(预计到货时间 AS DATE), CAST(NULL AS DATE))  AS est_arrival_date,
        sync_time
    FROM feishu.wd_品牌订货到货情况表_bak
    WHERE 款号 IS NOT NULL AND TRIM(款号) <> ''  *-- 过滤无款号的脏数据，保证主键有效*
)
*-- 步骤2: 按 style_no_size 聚合*
SELECT 
    style_no_size,
    
    *-- 维度字段：同 style_no_size 下可能存在多SKU，取MAX作为代表值*
    MAX(sku)                   AS sku,
    MAX(style_no)              AS style_no,
    MAX(size_code)             AS size_code,
    MAX(ip)                    AS ip,
    MAX(series)                AS series,
    MAX(color_name)            AS color_name,
    MAX(product_name)          AS product_name,
    MAX(category)              AS category,
    MAX(pickup_status)         AS pickup_status,
    *-- 预计到货年月：取最早的到货时间对应记录的月份*
    MIN(est_arrival_month)     AS est_arrival_month,
    
    *-- 度量字段：按 style_no_size 叠加*
    SUM(order_qty)             AS order_qty,
    SUM(picked_qty)            AS picked_qty,
    SUM(unpicked_qty)          AS unpicked_qty,
    SUM(brand_stock_qty)       AS brand_stock_qty,
    SUM(unpicked_avail_qty)    AS unpicked_avail_qty,
    SUM(unpicked_unavail_qty)  AS unpicked_unavail_qty,
    SUM(cumulative_order_qty)  AS cumulative_order_qty,
    
    *-- 日期字段：取最早的预计到货时间*
    MIN(est_arrival_date)      AS est_arrival_date,
    *-- 新增字段：预计到货时间 + 30天 (基于最早的到货时间计算)*
    DATE_ADD(MIN(est_arrival_date), INTERVAL 30 DAY) AS 30_est_arrival_date,
    
    *-- 技术字段：同步时间取最新*
    MAX(sync_time)             AS sync_time,
    NOW()                      AS insert_date,
    NOW()                      AS update_date
FROM base_data
GROUP BY style_no_size;
```

## DWS：

### feishu\_dws\.dws\_sku\_product\_info\_d

```SQL
-- ============================================================
-- ETL: feishu_dws.dws_sku_product_info_d
-- 粒度：style_no_size（SKU）
-- 渠道：韦德4核心渠道 channel_code IN ('wd','japan','spanish','germany')
-- 口径：3.1~3.20节
-- ============================================================
TRUNCATE TABLE feishu_dws.dws_sku_product_info_d;

INSERT INTO feishu_dws.dws_sku_product_info_d (
    style_no_size, brand, style_no, size, ip, series, color_name,
    product_name, category, tag_price, shelf_date, first_sales_date,
    inventory_sku, available_inventory, order_qty, replenish_qty,
    is_replenish, total_order_qty, daily_avg_qty_30d, sellable_days,
    achievement_ratio, should_achieve_ratio, lifecycle_day, sales_cycle_label,
    sync_time, insert_date, update_date
)
WITH
-- 1. brand_order_arrival_d 按 style_no_size 聚合，30_est_arrival_date 取最早时间（口径3.5节）
--    原因：同一 style_no_size 可能有多条记录，补全 shelf_date 时取最早的 30_est_arrival_date
boa_agg AS (
    SELECT
        boa.style_no_size                                  AS style_no_size,
        COALESCE(SUM(boa.order_qty), 0)                    AS order_qty,
        MIN(boa.`30_est_arrival_date`)                     AS est_arrival_date
    FROM feishu_dwd.dwd_feishu_brand_order_arrival_d boa
    GROUP BY boa.style_no_size
),
-- 2. 商品库基础信息 + shelf_date 补全（口径3.5节）
--    shelf_date 优先取 product_all_d.shelf_date，为空取 boa_agg.est_arrival_date（最早时间）
product_base AS (
    SELECT
        CONCAT_WS('-', p.style_no, p.size)                 AS style_no_size,
        p.brand                                            AS brand,
        p.style_no                                         AS style_no,
        p.size                                             AS size,
        COALESCE(NULLIF(TRIM(p.ip), ''), 'None')           AS ip,
        COALESCE(NULLIF(TRIM(p.series), ''), 'None')       AS series,
        COALESCE(NULLIF(TRIM(p.color_name), ''), 'None')   AS color_name,
        p.product_name                                     AS product_name,
        p.category                                         AS category,
        COALESCE(p.tag_price, 0)                           AS tag_price,
        -- 口径3.5节：shelf_date 优先取 product_all_d.shelf_date，为空取最早的 30_est_arrival_date
        COALESCE(
            NULLIF(p.shelf_date, DATE('1970-01-01')),
            boa.est_arrival_date
        )                                                  AS shelf_date,
        NULLIF(p.first_sales_date, DATE('1970-01-01'))     AS first_sales_date,
        COALESCE(p.inventory_sku, 0)                       AS inventory_sku,
        COALESCE(p.replenish_qty, 0)                       AS replenish_qty,
        COALESCE(p.is_replenish, '否')                     AS is_replenish,
        p.sync_time                                        AS sync_time,
        -- 订货数量 Q（口径3.18节）：按 style_no_size 关联
        COALESCE(boa.order_qty, 0)                         AS order_qty
    FROM feishu_dwd.dwd_feishu_product_all_d p
    LEFT JOIN boa_agg boa
        ON CONCAT_WS('-', p.style_no, p.size) = boa.style_no_size
    WHERE p.brand = '韦德'
),
-- 3. 可提库存（口径3.10节）：取最新 inventory_date，按 style_no_size 聚合
available_inv AS (
    SELECT
        CONCAT_WS('-', inv.style_no, inv.size)             AS style_no_size,
        COALESCE(SUM(inv.inventory_qty), 0)                AS available_inventory,
        MAX(inv.inventory_date) AS max_date
    FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d inv
    GROUP BY CONCAT_WS('-', inv.style_no, inv.size)
),
-- 4. 销售汇总（口径3.12节 / 3.16节）：核心4渠道，按 style_no_size 聚合
--    【修改点1】：关联 product_base 获取补全后的 shelf_date，过滤上架前的异常销售记录
--    累计销量 = shelf_date ~ 昨日 的 SUM(qty)
--    最近30天销量 = 最近30天（含昨日）的 SUM(qty)
sales_agg AS (
    SELECT
        CONCAT_WS('-', s.style_no, s.size)                 AS style_no_size,
        COALESCE(SUM(CASE WHEN s.sales_date < CURRENT_DATE() 
                          AND s.sales_date >= pb.shelf_date THEN s.qty ELSE 0 END), 0) AS cum_actual,
        COALESCE(SUM(CASE WHEN s.sales_date >= DATE_SUB(CURRENT_DATE(), 30)
                          AND s.sales_date < CURRENT_DATE()
                          AND s.sales_date >= pb.shelf_date THEN s.qty ELSE 0 END), 0) AS last_30d_qty
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    -- 【修改点2】：INNER JOIN 引入 shelf_date 用于过滤
    INNER JOIN product_base pb
        ON CONCAT_WS('-', s.style_no, s.size) = pb.style_no_size
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
    GROUP BY CONCAT_WS('-', s.style_no, s.size)
),
-- 【优化点1】：新增 CTE 提前算出 30天平均日销，避免主查询中重复计算 4 次
sales_metrics AS (
    SELECT
        pb.style_no_size,
        pb.inventory_sku,
        pb.shelf_date,
        sa.cum_actual,
        sa.last_30d_qty,
        CASE
            WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) <= 0 THEN NULL
            WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) < 30
                THEN CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6)) / DATEDIFF(CURRENT_DATE(), pb.shelf_date)
            ELSE CAST(COALESCE(sa.last_30d_qty, 0) AS DECIMAL(18,6)) / 30
        END AS daily_avg_qty_30d
    FROM product_base pb
    LEFT JOIN sales_agg sa ON pb.style_no_size = sa.style_no_size
),
-- 5. 应达成比例辅助：取销售计划表中每个SKU的最新累计计划销量
--    口径：cum_plan_qty 为截至N-1天的累计计划销量，取昨日(DATE_SUB(CURRENT_DATE(),1))对应行
--    昨日无记录时（如上架第1天）取 NULL，应达成比例返回 NULL
latest_cum_plan AS (
    SELECT
        sp.style_no_size                                       AS style_no_size,
        sp.cum_plan_qty                                        AS cum_plan_qty
    FROM feishu_dws.dws_sku_sales_plan_180d_d sp
    WHERE sp.sale_date = DATE_SUB(CURRENT_DATE(), 1)
)
SELECT
    pb.style_no_size                                       AS style_no_size,
    pb.brand                                               AS brand,
    pb.style_no                                            AS style_no,
    pb.size                                                AS size,
    pb.ip                                                  AS ip,
    pb.series                                              AS series,
    pb.color_name                                          AS color_name,
    pb.product_name                                        AS product_name,
    pb.category                                            AS category,
    pb.tag_price                                           AS tag_price,
    pb.shelf_date                                          AS shelf_date,
    pb.first_sales_date                                    AS first_sales_date,
    pb.inventory_sku                                       AS inventory_sku,
    COALESCE(ai.available_inventory, 0)                    AS available_inventory,
    pb.order_qty                                           AS order_qty,
    pb.replenish_qty                                       AS replenish_qty,
    pb.is_replenish                                        AS is_replenish,
    -- 口径3.20节：总订货数量
    CASE WHEN pb.is_replenish = '是'
         THEN pb.order_qty + pb.replenish_qty
         ELSE pb.order_qty
    END                                                    AS total_order_qty,
    -- 【优化点2】：直接取预先算好的日销
    -- 口径3.12节：30天平均日销
    -- sold_days = DATEDIFF(CURRENT_DATE(), shelf_date) （排除今天）
    sm.daily_avg_qty_30d                                   AS daily_avg_qty_30d,
    -- 口径3.11节：可售周期 = 在仓库存 / 30天平均日销
    -- 【优化点3】：基于预计算的日销，简化防除零逻辑
    CASE
        WHEN sm.daily_avg_qty_30d IS NULL OR sm.daily_avg_qty_30d = 0 THEN NULL
        ELSE CAST(pb.inventory_sku AS DECIMAL(18,6)) / sm.daily_avg_qty_30d
    END                                                    AS sellable_days,
    -- 口径3.19节：达成比例 = 累计销量 / 订货数量
    CAST(COALESCE(sm.cum_actual, 0) AS DECIMAL(18,6))
        / NULLIF(CAST(pb.order_qty AS DECIMAL(18,6)), 0)   AS achievement_ratio,
    -- 应达成比例 = 累计计划销量 / 订货数量
    -- 口径：取销售计划表昨日(D-1)对应行的 cum_plan_qty(截至N-1天的累计计划销量)
    --      昨日无记录(如上架第1天)时返回 NULL
    CAST(lcp.cum_plan_qty AS DECIMAL(18,6))
        / NULLIF(CAST(pb.order_qty AS DECIMAL(18,6)), 0)   AS should_achieve_ratio,
    -- 口径3.7节：已上架天数
    DATEDIFF(CURRENT_DATE(), pb.shelf_date) + 1            AS lifecycle_day,
    -- 口径3.8节：销售周期标签
    CASE
        WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) + 1 BETWEEN 1 AND 30   THEN '新品期'
        WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) + 1 BETWEEN 31 AND 120 THEN '热销期'
        WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) + 1 BETWEEN 121 AND 180 THEN '清货期'
        WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) + 1 > 180              THEN '超周期'
        ELSE NULL
    END                                                    AS sales_cycle_label,
    pb.sync_time                                           AS sync_time,
    CURRENT_TIMESTAMP()                                    AS insert_date,
    CURRENT_TIMESTAMP()                                    AS update_date
FROM product_base pb
LEFT JOIN available_inv ai   ON pb.style_no_size = ai.style_no_size
-- 【优化点4】：关联预算好的指标 CTE
LEFT JOIN sales_metrics sm    ON pb.style_no_size = sm.style_no_size
-- 关联销售计划表昨日累计计划销量，用于计算应达成比例
LEFT JOIN latest_cum_plan lcp ON pb.style_no_size = lcp.style_no_size
WHERE pb.style_no_size IS NOT NULL
  AND pb.style_no_size <> 'None'
  AND pb.shelf_date IS NOT NULL;
```

### feishu\_dws\.dws\_skc\_product\_info\_d

```SQL
-- ============================================================
-- ETL: feishu_dws.dws_skc_product_info_d
-- 粒度：style_no（SKC）
-- 渠道：韦德4核心渠道
-- 口径：5.1~5.20节
-- ============================================================
TRUNCATE TABLE feishu_dws.dws_skc_product_info_d;

INSERT INTO feishu_dws.dws_skc_product_info_d (
    style_no, brand, ip, series, color_name, product_name, category,
    shelf_date, first_sales_date, inventory_sku, available_inventory,
    order_qty, replenish_qty, total_order_qty, daily_avg_qty_30d,
    sellable_days, achievement_ratio, should_achieve_ratio, lifecycle_day, sales_cycle_label,
    sync_time, insert_date, update_date
)
WITH
-- 1. brand_order_arrival_d 按 style_no 聚合（SKC维度）
--    order_qty: SUM(order_qty)，30_est_arrival_date: MIN 取最早时间
boa_agg_skc AS (
    SELECT
        boa.style_no                                       AS style_no,
        COALESCE(SUM(boa.order_qty), 0)                    AS order_qty,
        MIN(boa.`30_est_arrival_date`)                     AS est_arrival_date
    FROM feishu_dwd.dwd_feishu_brand_order_arrival_d boa
    GROUP BY boa.style_no
),
-- 2. SKU 级补全后的基础信息（复用 SKU 维度的补全逻辑，再聚合到 SKC）
--    口径5.5节：SKC上架时间 = MIN(shelf_date)，shelf_date 需先按3.5节补全
--    注意：先在 SKU 级用 MIN(30_est_arrival_date) 补全 shelf_date，再聚合到 SKC 取 MIN
sku_base AS (
    SELECT
        p.style_no                                         AS style_no,
        MAX(p.brand)                                       AS brand,
        -- 强制取非 None 的有效值，如果全为 None/空则结果为 NULL
        MAX(CASE WHEN COALESCE(NULLIF(TRIM(p.ip), ''), 'None') <> 'None' 
                 THEN p.ip ELSE NULL END)                   AS ip,
        MAX(CASE WHEN COALESCE(NULLIF(TRIM(p.series), ''), 'None') <> 'None' 
                 THEN p.series ELSE NULL END)               AS series,
        MAX(CASE WHEN COALESCE(NULLIF(TRIM(p.color_name), ''), 'None') <> 'None' 
                 THEN p.color_name ELSE NULL END)           AS color_name,
        MAX(CASE WHEN COALESCE(NULLIF(TRIM(p.product_name), ''), 'None') <> 'None' 
                 THEN p.product_name ELSE NULL END)         AS product_name,         
        MAX(CASE WHEN COALESCE(NULLIF(TRIM(p.category), ''), 'None') <> 'None' 
                 THEN p.category ELSE NULL END)             AS category,
        -- 口径5.5节：SKC上架时间 = MIN(每个SKU补全后的shelf_date)
        MIN(COALESCE(
            NULLIF(p.shelf_date, DATE('1970-01-01')),
            boa.est_arrival_date
        ))                                                 AS shelf_date,
        MIN(NULLIF(p.first_sales_date, DATE('1970-01-01'))) AS first_sales_date,
        SUM(COALESCE(p.inventory_sku, 0))                  AS inventory_sku,
        SUM(COALESCE(p.replenish_qty, 0))                  AS replenish_qty,
        MAX(CASE WHEN COALESCE(p.is_replenish, '否') = '是' THEN 1 ELSE 0 END) AS has_replenish,
        MAX(p.sync_time)                                   AS sync_time,
        -- 订货数量 Q（口径5.18节）：SKC维度 SUM(order_qty)，从 boa_agg_skc 取
        -- 注意：同一 style_no 下所有 SKU 的 boa.order_qty 相同（来源于同一 SKC 订货单），取 MAX 避免重复累加
        -- 若需精确按 SKU 累加，应在 SKU 级聚合后再 SUM 到 SKC
        MAX(COALESCE(boa.order_qty, 0))                    AS order_qty
    FROM feishu_dwd.dwd_feishu_product_all_d p
    LEFT JOIN boa_agg_skc boa
        ON p.style_no = boa.style_no
    WHERE p.brand = '韦德'
    GROUP BY p.style_no
),
-- 3. SKC 可提库存（口径5.10节）：取最新 inventory_date，按 style_no 聚合（一步完成）
available_inv_skc AS (
    SELECT
        inv.style_no                                       AS style_no,
        COALESCE(SUM(inv.inventory_qty), 0)                AS available_inventory,
        MAX(inv.inventory_date) AS max_date
    FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d inv
    GROUP BY inv.style_no
),
-- 4. SKC 销售汇总（口径5.12节 / 5.16节）：按 style_no 聚合，核心4渠道
--    【修改点1】：关联 sku_base 获取补全后的 shelf_date，过滤上架前的异常销售记录
sales_agg_skc AS (
    SELECT
        s.style_no                                         AS style_no,
        COALESCE(SUM(CASE WHEN s.sales_date < CURRENT_DATE() 
                          AND s.sales_date >= sb.shelf_date THEN s.qty ELSE 0 END), 0) AS cum_actual,
        COALESCE(SUM(CASE WHEN s.sales_date >= DATE_SUB(CURRENT_DATE(), 30)
                          AND s.sales_date < CURRENT_DATE()
                          AND s.sales_date >= sb.shelf_date THEN s.qty ELSE 0 END), 0) AS last_30d_qty
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    -- 【修改点2】：INNER JOIN 引入 shelf_date 用于过滤
    INNER JOIN sku_base sb
        ON s.style_no = sb.style_no
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
    GROUP BY s.style_no
),
-- 【优化点1】：新增 CTE 提前算出 SKC 30天平均日销，避免主查询中重复计算 4 次
sales_metrics_skc AS (
    SELECT 
        sb.style_no,
        sb.inventory_sku,
        sb.shelf_date,
        sa.cum_actual,
        sa.last_30d_qty,
        CASE
            WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) <= 0 THEN NULL
            WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) < 30
                THEN CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6)) / DATEDIFF(CURRENT_DATE(), sb.shelf_date)
            ELSE CAST(COALESCE(sa.last_30d_qty, 0) AS DECIMAL(18,6)) / 30
        END AS daily_avg_qty_30d
    FROM sku_base sb
    LEFT JOIN sales_agg_skc sa ON sb.style_no = sa.style_no
),
-- 5. 应达成比例辅助：取 SKC 销售计划表中每个 SKC 的最新累计计划销量
--    口径：cum_plan_qty 为截至N-1天的累计计划销量，取昨日(DATE_SUB(CURRENT_DATE(),1))对应行
--    昨日无记录时（如上架第1天）取 NULL，应达成比例返回 NULL
latest_cum_plan_skc AS (
    SELECT
        sp.style_no                                          AS style_no,
        sp.cum_plan_qty                                      AS cum_plan_qty
    FROM feishu_dws.dws_skc_sales_plan_180d_d sp
    WHERE sp.sale_date = DATE_SUB(CURRENT_DATE(), 1)
)
SELECT
    sb.style_no                                            AS style_no,
    sb.brand                                               AS brand,
    COALESCE(sb.ip, 'None')                                AS ip,
    COALESCE(sb.series, 'None')                            AS series,
    -- 兜底处理，如果 sku_base 里算出来是 NULL，则转为 'None'
    COALESCE(sb.color_name, 'None')                        AS color_name,
    COALESCE(sb.product_name, 'None')                      AS product_name,
    COALESCE(sb.category, 'None')                          AS category,
    sb.shelf_date                                          AS shelf_date,
    sb.first_sales_date                                    AS first_sales_date,
    sb.inventory_sku                                       AS inventory_sku,
    COALESCE(ai.available_inventory, 0)                    AS available_inventory,
    sb.order_qty                                           AS order_qty,
    sb.replenish_qty                                       AS replenish_qty,
    -- 口径5.20节：SKC总订货数量
    CASE WHEN sb.has_replenish = 1
         THEN sb.order_qty + sb.replenish_qty
         ELSE sb.order_qty
    END                                                    AS total_order_qty,
    -- 口径5.12节：SKC 30天平均日销
    -- 【优化点2】：直接取预先算好的日销
    sm.daily_avg_qty_30d                                   AS daily_avg_qty_30d,
    -- 口径5.11节：SKC可售周期
    -- 【优化点3】：基于预计算的日销，简化防除零逻辑
    CASE
        WHEN sm.daily_avg_qty_30d IS NULL OR sm.daily_avg_qty_30d = 0 THEN NULL
        ELSE CAST(sb.inventory_sku AS DECIMAL(18,6)) / sm.daily_avg_qty_30d
    END                                                    AS sellable_days,
    -- 口径5.19节：SKC达成比例
    CAST(COALESCE(sm.cum_actual, 0) AS DECIMAL(18,6))
        / NULLIF(CAST(sb.order_qty AS DECIMAL(18,6)), 0) AS achievement_ratio,
    -- 应达成比例 = 累计计划销量 / 订货数量
    -- 口径：取销售计划表昨日(D-1)对应行的 cum_plan_qty(截至N-1天的累计计划销量)
    --      昨日无记录(如上架第1天)时返回 NULL
    CAST(lcp.cum_plan_qty AS DECIMAL(18,6))
        / NULLIF(CAST(sb.order_qty AS DECIMAL(18,6)), 0) AS should_achieve_ratio,
    -- 口径5.7节：SKC已上架天数
    DATEDIFF(CURRENT_DATE(), sb.shelf_date) + 1           AS lifecycle_day,
    -- 口径5.8节：SKC销售周期标签
    CASE
        WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) + 1 BETWEEN 1 AND 30   THEN '新品期'
        WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) + 1 BETWEEN 31 AND 120 THEN '热销期'
        WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) + 1 BETWEEN 121 AND 180 THEN '清货期'
        WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) + 1 > 180              THEN '超周期'
        ELSE NULL
    END                                                    AS sales_cycle_label,
    sb.sync_time                                           AS sync_time,
    CURRENT_TIMESTAMP()                                    AS insert_date,
    CURRENT_TIMESTAMP()                                    AS update_date
FROM sku_base sb
LEFT JOIN available_inv_skc ai ON sb.style_no = ai.style_no
-- 【优化点4】：关联预算好的指标 CTE
LEFT JOIN sales_metrics_skc sm ON sb.style_no = sm.style_no
-- 关联销售计划表昨日累计计划销量，用于计算应达成比例
LEFT JOIN latest_cum_plan_skc lcp ON sb.style_no = lcp.style_no
WHERE sb.style_no IS NOT NULL
  AND sb.style_no <> 'None'
  AND sb.shelf_date IS NOT NULL;
```

### feishu\_dws\.dws\_sku\_sales\_plan\_180d\_d

```SQL
-- ============================================================
-- ETL: feishu_dws.dws_sku_sales_plan_180d_d
-- 粒度：style_no_size + sale_date
-- 日期补齐：每个SKU从 shelf_date 到 全局最晚shelf_date+180天
-- 渠道：韦德4核心渠道
-- 口径：4.1~4.6节
-- 设计要点：
--   1. 复用 dws_sku_product_info_d 已聚合好的商品维度字段（shelf_date、order_qty、inventory_sku等）
--   2. 修复 cum_actual 稀疏断档Bug：先展开日历 LEFT JOIN 销量，再在连续数据上用窗口函数
--   3. 可售周期：1~180天用滚动近30天日销（不含当天），超周期用当前时间近30天日销
--   4. 日期序列：GENERATE_SERIES(0, DATEDIFF) + DATE_ADD，简洁高效
-- ============================================================
TRUNCATE TABLE feishu_dws.dws_sku_sales_plan_180d_d;

INSERT INTO feishu_dws.dws_sku_sales_plan_180d_d (
    style_no_size, sale_date, lifecycle_day, sale_date_label,
    sales_cycle_label, ratio, brand, style_no, size, shelf_date,
    order_qty, plan_pre, plan_post, actual_qty, actual_amt,
    cum_actual, cum_actual_amt, cum_plan_qty, cum_plan_amt, should_achieve_ratio, achievement_rate,
    inventory_sku, available_inventory, sellable_days,
    sync_time, insert_date, update_date
)
WITH
-- ============================================================
-- 1. 销售明细按 style_no_size + sales_date 聚合（核心4渠道）
--    稀疏表：只有有销量的日期才有记录
-- ============================================================
sales_daily AS (
    SELECT
        CONCAT_WS('-', s.style_no, s.size)                 AS style_no_size,
        s.sales_date                                       AS sales_date,
        COALESCE(SUM(s.qty), 0)                            AS daily_qty,
        COALESCE(SUM(s.amt), 0)                            AS daily_amt
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
    GROUP BY CONCAT_WS('-', s.style_no, s.size), s.sales_date
),
-- ============================================================
-- 2. 当前时间的30天平均日销辅助（口径3.12节），用于超周期可售周期
--    按商品维表逻辑：上架<30天用累计/已售天数，上架>=30天用近30天日均
--    直接从 dws_sku_product_info_d 取 daily_avg_qty_30d 更简洁
-- ============================================================
current_30d_avg AS (
    SELECT
        style_no_size,
        sellable_days AS current_sellable_days,
        daily_avg_qty_30d AS current_daily_avg_30d
    FROM feishu_dws.dws_sku_product_info_d
),
-- ============================================================
-- 3. 全局最晚 shelf_date（用于确定补齐结束日 = 最晚shelf_date + 180天）
--    直接从商品维表取，商品维表的 shelf_date 已是补全后的最全数据
-- ============================================================
global_max_shelf AS (
    SELECT MAX(shelf_date) AS max_shelf_date
    FROM feishu_dws.dws_sku_product_info_d
),
-- ============================================================
-- 4. 日期补齐：每个 SKU 从 shelf_date 到 全局最晚shelf_date+180天
--    主表直接用 dws_sku_product_info_d（已聚合好 shelf_date、order_qty、inventory_sku等）
--    日期序列：GENERATE_SERIES(0, DATEDIFF(end, shelf_date)) 生成偏移量，DATE_ADD 转日期
-- ============================================================
sku_calendar AS (
    SELECT
        p.style_no_size                                       AS style_no_size,
        p.brand                                               AS brand,
        p.style_no                                            AS style_no,
        p.size                                                AS size,
        p.shelf_date                                          AS shelf_date,
        p.inventory_sku                                       AS inventory_sku,
        p.available_inventory                                 AS available_inventory,
        p.order_qty                                           AS order_qty,
        p.sync_time                                           AS sync_time,
        -- 上市第N天 = 偏移量 + 1
        gs.day_offset + 1                                     AS lifecycle_day,
        -- 具体的日期 = shelf_date + 偏移量
        DATE_ADD(p.shelf_date, INTERVAL gs.day_offset DAY)    AS sale_date
    FROM feishu_dws.dws_sku_product_info_d p
    CROSS JOIN global_max_shelf gms
    -- 生成 0 到 天数差 的序列，避免与 1970 互相转换
    -- gs 是这个临时表的名字。
    -- day_offset 就是这个临时表里那一列的名字。
    CROSS JOIN GENERATE_SERIES(
        0,
        DATEDIFF(DATE_ADD(gms.max_shelf_date, INTERVAL 180 DAY), p.shelf_date)
    ) AS gs(day_offset)
),
-- ============================================================
-- 5. 关联日销：保证每个 SKU 每天都有一条记录，没销量的日期补0
--    这一步是修复 cum_actual 稀疏断档Bug的关键
-- ============================================================
sku_with_sales AS (
    SELECT
        sc.*,
        COALESCE(sd.daily_qty, 0) AS actual_qty,
        COALESCE(sd.daily_amt, 0) AS actual_amt
    FROM sku_calendar sc
    LEFT JOIN sales_daily sd
        ON sc.style_no_size = sd.style_no_size
       AND sc.sale_date = sd.sales_date
),
-- ============================================================
-- 6. 在连续日历数据上计算累计销量和滚动近30天日销（关键修复）
--    - cum_actual: 截至N-1天的累计销量（窗口函数 ROWS UNBOUNDED ~ 1 PRECEDING）
--    - rolling_30d_qty: 滚动近30天销量（不含当天，ROWS 30 PRECEDING ~ 1 PRECEDING）
--    - rolling_30d_days: 滚动窗口实际天数（lifecycle_day-1 与 30 取较小值）
-- ============================================================
sales_cum AS (
    SELECT
        style_no_size,
        sale_date,
        lifecycle_day,
        actual_qty,
        actual_amt,
        brand,
        style_no,
        size,
        shelf_date,
        order_qty,
        inventory_sku,
        available_inventory,
        sync_time,
        -- 1 PRECEDING：往前数1个人（也就是昨天）。
        -- UNBOUNDED PRECEDING：一直往前到队伍的最开头（也就是上市第一天）。
        -- 30 PRECEDING：从当前位置往前数30个人（也就是往前推30天）。
        -- 累计实际销量 = 截至N-1天（不含当天N）
        SUM(actual_qty) OVER (PARTITION BY style_no_size ORDER BY sale_date
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cum_actual,
        SUM(actual_amt) OVER (PARTITION BY style_no_size ORDER BY sale_date
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cum_actual_amt,
        -- 滚动近30天销量（不含当天）：用于1~180天的可售周期计算
        SUM(actual_qty) OVER (PARTITION BY style_no_size ORDER BY sale_date
                              ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS rolling_30d_qty
    FROM sku_with_sales
),
-- ============================================================
-- 6.1 计算 plan_post_value（基于 cum_actual），供后续累计
--     plan_post 依赖 cum_actual(N-1)，须先在 sales_cum 中算出 cum_actual 再计算
-- ============================================================
plan_post_calc AS (
    SELECT
        sc.*,
        -- plan_post(N) = (Q - cum_actual(N)) * ratio / (181 - N)，超周期为NULL
        CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
             THEN (CAST(sc.order_qty AS DECIMAL(18,6))
                   - CAST(COALESCE(sc.cum_actual, 0) AS DECIMAL(18,6)))
                  * CASE
                      WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                    END
                  / NULLIF(181 - sc.lifecycle_day, 0)
             ELSE NULL
        END AS plan_post_value
    FROM sales_cum sc
),
-- ============================================================
-- 6.2 累计计划销量 = 截至N-1天的 SUM(plan_post_value)，在连续日历上累计
--     超周期段 plan_post_value 为 NULL，累计结果为 NULL
-- ============================================================
cum_plan AS (
    SELECT
        pc.*,
        -- 累计计划销量 = 截至N-1天的 SUM(plan_post_value)，不含当天N
        SUM(CASE WHEN pc.lifecycle_day BETWEEN 1 AND 180
                 THEN pc.plan_post_value ELSE NULL END
           ) OVER (PARTITION BY pc.style_no_size ORDER BY pc.sale_date
                   ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cum_plan_qty
    FROM plan_post_calc pc
)
SELECT
    sc.style_no_size                                       AS style_no_size,
    sc.sale_date                                           AS sale_date,
    sc.lifecycle_day                                       AS lifecycle_day,
    -- 口径4.1节：sale_date_label
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN CAST(sc.lifecycle_day AS VARCHAR)
         ELSE '超周期'
    END                                                    AS sale_date_label,
    -- 口径4.2节：销售周期标签
    CASE
        WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN '新品期'
        WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN '热销期'
        WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN '清货期'
        ELSE '超周期'
    END                                                    AS sales_cycle_label,
    -- 口径4.2节：ratio
    CASE
        WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
        WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
        WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
        ELSE NULL
    END                                                    AS ratio,
    sc.brand                                               AS brand,
    sc.style_no                                            AS style_no,
    sc.size                                                AS size,
    sc.shelf_date                                          AS shelf_date,
    sc.order_qty                                           AS order_qty,
    -- 口径4.3节：plan_pre = (Q - cum_actual(N)) * ratio （超周期为NULL）
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN (CAST(sc.order_qty AS DECIMAL(18,6))
               - CAST(COALESCE(sc.cum_actual, 0) AS DECIMAL(18,6)))
              * CASE
                  WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                END
         ELSE NULL
    END                                                    AS plan_pre,
    -- 口径4.4节：plan_post = (Q - cum_actual(N)) * ratio / (181 - N)
    --    cum_actual(N) = 截至N-1天的累计销量（在连续日历上计算，修复稀疏断档Bug）
    --    分母 = 180 - sold_days = 180 - (N-1) = 181 - N
    --    超周期为NULL
    sc.plan_post_value                                     AS plan_post,
    -- 口径4.5节：实际销售 = 第N天的 SUM(qty)，没销量的日期为0
    sc.actual_qty                                          AS actual_qty,
    sc.actual_amt                                          AS actual_amt,
    -- 累计实际销量 = 截至N-1天的 SUM(qty)
    COALESCE(sc.cum_actual, 0)                             AS cum_actual,
    COALESCE(sc.cum_actual_amt, 0)                          AS cum_actual_amt,
    -- 累计计划销量 = 截至N-1天的 SUM(plan_post)，超周期段累计为 NULL
    sc.cum_plan_qty                                        AS cum_plan_qty,
    -- 累计计划金额 = 截至N-1天，占位0（后续补全）
    CAST(0 AS DECIMAL(18,6))                               AS cum_plan_amt,
    -- 应达成比例 = 累计计划销量 / 订货数量Q（基于截至N-1天的cum_plan_qty）
    --   超周期段 cum_plan_qty 为 NULL，结果为 NULL
    CAST(sc.cum_plan_qty AS DECIMAL(18,6))
        / NULLIF(CAST(sc.order_qty AS DECIMAL(18,6)), 0)   AS should_achieve_ratio,
    -- 口径4.6节：达成情况 = actual_qty / plan_post
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN CAST(sc.actual_qty AS DECIMAL(18,6))
              / NULLIF(
                  (CAST(sc.order_qty AS DECIMAL(18,6))
                   - CAST(COALESCE(sc.cum_actual, 0) AS DECIMAL(18,6)))
                  * CASE
                      WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                    END
                  / NULLIF(181 - sc.lifecycle_day, 0), 0)
         ELSE NULL
    END                                                    AS achievement_rate,
    sc.inventory_sku                                       AS inventory_sku,
    sc.available_inventory                                 AS available_inventory,
    -- 口径3.11节：可售周期 = 在仓库存 / 30天平均日销
    --   - 1~180天：用滚动近30天日销（不含当天，反映历史时间节点的真实可售周期）
    --     滚动窗口天数 = MIN(lifecycle_day-1, 30)，上架<30天用实际已售天数
    --   - 超周期(>180天)：用当前时间的近30天日销（直接取商品维表 daily_avg_qty_30d）
    CASE
        -- 无库存或无日销数据时返回NULL
        WHEN sc.inventory_sku = 0 THEN NULL
        WHEN sc.lifecycle_day BETWEEN 1 AND 180 THEN
            -- 1~180天：用滚动近30天日销（不含当天）
            CASE
                WHEN COALESCE(sc.rolling_30d_qty, 0) = 0 THEN NULL
                -- 当 SKU 刚上架第 1 天（lifecycle_day = 1）时，LEAST(sc.lifecycle_day - 1, 30) 的结果为 0
                -- 上架第一天的销量，需要第二天才会采集到，所以没有近30天的销量
                WHEN LEAST(sc.lifecycle_day - 1, 30) = 0 THEN NULL
                ELSE CAST(sc.inventory_sku AS DECIMAL(18,6))
                     / (CAST(sc.rolling_30d_qty AS DECIMAL(18,6))
                        / LEAST(sc.lifecycle_day - 1, 30))
            END
        ELSE
            -- 超周期：用当前时间的近30天日销（与商品维表一致）
            COALESCE(c30.current_sellable_days, 0)
    END                                                    AS sellable_days,
    sc.sync_time                                           AS sync_time,
    CURRENT_TIMESTAMP()                                    AS insert_date,
    CURRENT_TIMESTAMP()                                    AS update_date
FROM cum_plan sc
LEFT JOIN current_30d_avg c30    ON sc.style_no_size = c30.style_no_size
ORDER BY sc.style_no_size, sc.sale_date;
```

### feishu\_dws\.dws\_skc\_sales\_plan\_180d\_d

```SQL
-- ============================================================
-- ETL: feishu_dws.dws_skc_sales_plan_180d_d
-- 粒度：style_no + sale_date
-- 日期补齐：每个SKC从 shelf_date 到 全局最晚shelf_date+180天
-- 渠道：韦德4核心渠道
-- 口径：6.1~6.6节
-- 设计要点：
--   1. 复用 dws_skc_product_info_d 已聚合好的商品维度字段（shelf_date、order_qty、inventory_sku等）
--   2. 修复 cum_actual 稀疏断档Bug：先展开日历 LEFT JOIN 销量，再在连续数据上用窗口函数
--   3. 可售周期：1~180天用滚动近30天日销（不含当天），超周期用当前时间近30天日销
--   4. 日期序列：GENERATE_SERIES(0, DATEDIFF) + DATE_ADD，简洁高效
-- ============================================================
TRUNCATE TABLE feishu_dws.dws_skc_sales_plan_180d_d;

INSERT INTO feishu_dws.dws_skc_sales_plan_180d_d (
    style_no, sale_date, lifecycle_day, sale_date_label,
    sales_cycle_label, ratio, brand, shelf_date,
    order_qty, plan_pre, plan_post, actual_qty, actual_amt,
    cum_actual, cum_actual_amt, cum_plan_qty, cum_plan_amt, should_achieve_ratio, achievement_rate,
    inventory_sku, available_inventory, sellable_days,
    sync_time, insert_date, update_date
)
WITH
-- ============================================================
-- 1. SKC 销售明细按 style_no + sales_date 聚合（核心4渠道）
--    稀疏表：只有有销量的日期才有记录
-- ============================================================
sales_daily_skc AS (
    SELECT
        s.style_no                                         AS style_no,
        s.sales_date                                       AS sales_date,
        COALESCE(SUM(s.qty), 0)                            AS daily_qty,
        COALESCE(SUM(s.amt), 0)                            AS daily_amt
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
    GROUP BY s.style_no, s.sales_date
),
-- ============================================================
-- 2. 当前时间的30天平均日销辅助（口径5.12节），用于超周期可售周期
--    直接从 dws_skc_product_info_d 取 daily_avg_qty_30d 更简洁
-- ============================================================
current_30d_avg_skc AS (
    SELECT
        style_no,
        sellable_days AS current_sellable_days,
        daily_avg_qty_30d AS current_daily_avg_30d
    FROM feishu_dws.dws_skc_product_info_d
),
-- ============================================================
-- 3. 全局最晚 shelf_date（直接从商品维表取）
-- ============================================================
global_max_shelf_skc AS (
    SELECT MAX(shelf_date) AS max_shelf_date
    FROM feishu_dws.dws_skc_product_info_d
),
-- ============================================================
-- 4. 日期补齐：每个 SKC 从 shelf_date 到 全局最晚shelf_date+180天
--    主表直接用 dws_skc_product_info_d（已聚合好 shelf_date、order_qty、inventory_sku等）
-- ============================================================
skc_calendar AS (
    SELECT
        p.style_no                                            AS style_no,
        p.brand                                               AS brand,
        p.shelf_date                                          AS shelf_date,
        p.inventory_sku                                       AS inventory_sku,
        p.available_inventory                                 AS available_inventory,
        p.order_qty                                           AS order_qty,
        p.sync_time                                           AS sync_time,
        -- 上市第N天 = 偏移量 + 1
        gs.day_offset + 1                                     AS lifecycle_day,
        -- 具体的日期 = shelf_date + 偏移量
        DATE_ADD(p.shelf_date, INTERVAL gs.day_offset DAY)    AS sale_date
    FROM feishu_dws.dws_skc_product_info_d p
    CROSS JOIN global_max_shelf_skc gms
    -- gs 是这个临时表的名字。
    -- day_offset 就是这个临时表里那一列的名字。
    CROSS JOIN GENERATE_SERIES(
        0,
        DATEDIFF(DATE_ADD(gms.max_shelf_date, INTERVAL 180 DAY), p.shelf_date)
    ) AS gs(day_offset)
),
-- ============================================================
-- 5. 关联日销：保证每个 SKC 每天都有一条记录，没销量的日期补0
--    这一步是修复 cum_actual 稀疏断档Bug的关键
-- ============================================================
skc_with_sales AS (
    SELECT
        sc.*,
        COALESCE(sd.daily_qty, 0) AS actual_qty,
        COALESCE(sd.daily_amt, 0) AS actual_amt
    FROM skc_calendar sc
    LEFT JOIN sales_daily_skc sd
        ON sc.style_no = sd.style_no
       AND sc.sale_date = sd.sales_date
),
-- ============================================================
-- 6. 在连续日历数据上计算累计销量和滚动近30天日销（关键修复）
--    - cum_actual: 截至N-1天的累计销量
--    - rolling_30d_qty: 滚动近30天销量（不含当天）
-- ============================================================
sales_cum_skc AS (
    SELECT
        style_no,
        sale_date,
        lifecycle_day,
        actual_qty,
        actual_amt,
        brand,
        shelf_date,
        order_qty,
        inventory_sku,
        available_inventory,
        sync_time,
        -- 1 PRECEDING：往前数1个人（也就是昨天）。
        -- UNBOUNDED PRECEDING：一直往前到队伍的最开头（也就是上市第一天）。
        -- 30 PRECEDING：从当前位置往前数30个人（也就是往前推30天）。
        -- 累计实际销量 = 截至N-1天（不含当天N）
        SUM(actual_qty) OVER (PARTITION BY style_no ORDER BY sale_date
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cum_actual,
        SUM(actual_amt) OVER (PARTITION BY style_no ORDER BY sale_date
                              ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cum_actual_amt,
        -- 滚动近30天销量（不含当天）：用于1~180天的可售周期计算
        SUM(actual_qty) OVER (PARTITION BY style_no ORDER BY sale_date
                              ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING) AS rolling_30d_qty
    FROM skc_with_sales
),
-- ============================================================
-- 6.1 计算 plan_post_value（基于 cum_actual），供后续累计
--     plan_post 依赖 cum_actual(N-1)，须先在 sales_cum_skc 中算出 cum_actual 再计算
-- ============================================================
plan_post_calc_skc AS (
    SELECT
        sc.*,
        -- plan_post(N) = (Q - cum_actual(N)) * ratio / (181 - N)，超周期为NULL
        CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
             THEN (CAST(sc.order_qty AS DECIMAL(18,6))
                   - CAST(COALESCE(sc.cum_actual, 0) AS DECIMAL(18,6)))
                  * CASE
                      WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                    END
                  / NULLIF(181 - sc.lifecycle_day, 0)
             ELSE NULL
        END AS plan_post_value
    FROM sales_cum_skc sc
),
-- ============================================================
-- 6.2 累计计划销量 = 截至N-1天的 SUM(plan_post_value)，在连续日历上累计
--     超周期段 plan_post_value 为 NULL，累计结果为 NULL
-- ============================================================
cum_plan_skc AS (
    SELECT
        pc.*,
        -- 累计计划销量 = 截至N-1天的 SUM(plan_post_value)，不含当天N
        SUM(CASE WHEN pc.lifecycle_day BETWEEN 1 AND 180
                 THEN pc.plan_post_value ELSE NULL END
           ) OVER (PARTITION BY pc.style_no ORDER BY pc.sale_date
                   ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cum_plan_qty
    FROM plan_post_calc_skc pc
)
SELECT
    sc.style_no                                            AS style_no,
    sc.sale_date                                           AS sale_date,
    sc.lifecycle_day                                       AS lifecycle_day,
    -- 口径6.1节：sale_date_label
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN CAST(sc.lifecycle_day AS VARCHAR)
         ELSE '超周期'
    END                                                    AS sale_date_label,
    -- 口径6.2节：销售周期标签
    CASE
        WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN '新品期'
        WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN '热销期'
        WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN '清货期'
        ELSE '超周期'
    END                                                    AS sales_cycle_label,
    -- 口径6.2节：ratio
    CASE
        WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
        WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
        WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
        ELSE NULL
    END                                                    AS ratio,
    sc.brand                                               AS brand,
    sc.shelf_date                                          AS shelf_date,
    sc.order_qty                                           AS order_qty,
    -- 口径6.3节：(Q - cum_actual(N)) * ratio （超周期为NULL）
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN (CAST(sc.order_qty AS DECIMAL(18,6))
               - CAST(COALESCE(sc.cum_actual, 0) AS DECIMAL(18,6)))
              * CASE
                  WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                END
         ELSE NULL
    END                                                    AS plan_pre,
    -- 口径6.4节：plan_post = (Q - cum_actual(N)) * ratio / (181 - N)
    --    cum_actual(N) = 截至N-1天的累计销量（在连续日历上计算，修复稀疏断档Bug）
    --    超周期为NULL
    sc.plan_post_value                                     AS plan_post,
    -- 口径6.5节：实际销售 = 第N天的 SUM(qty)，没销量的日期为0
    sc.actual_qty                                          AS actual_qty,
    sc.actual_amt                                          AS actual_amt,
    -- 累计实际销量 = 截至N-1天的 SUM(qty)
    COALESCE(sc.cum_actual, 0)                             AS cum_actual,
    COALESCE(sc.cum_actual_amt, 0)                         AS cum_actual_amt,
    -- SKC累计计划销量 = 截至N-1天的 SUM(plan_post)，超周期段累计为 NULL
    sc.cum_plan_qty                                        AS cum_plan_qty,
    -- SKC累计计划金额 = 截至N-1天，占位0（后续补全）
    CAST(0 AS DECIMAL(18,6))                               AS cum_plan_amt,
    -- SKC应达成比例 = 累计计划销量 / 订货数量Q（基于截至N-1天的cum_plan_qty）
    --   超周期段 cum_plan_qty 为 NULL，结果为 NULL
    CAST(sc.cum_plan_qty AS DECIMAL(18,6))
        / NULLIF(CAST(sc.order_qty AS DECIMAL(18,6)), 0) AS should_achieve_ratio,
    -- 口径6.6节：达成情况 = actual_qty / plan_post
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN CAST(sc.actual_qty AS DECIMAL(18,6))
              / NULLIF(
                  (CAST(sc.order_qty AS DECIMAL(18,6))
                   - CAST(COALESCE(sc.cum_actual, 0) AS DECIMAL(18,6)))
                  * CASE
                      WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                    END
                  / NULLIF(181 - sc.lifecycle_day, 0), 0)
         ELSE NULL
    END                                                    AS achievement_rate,
    sc.inventory_sku                                       AS inventory_sku,
    sc.available_inventory                                 AS available_inventory,
    -- 口径5.11节：可售周期 = SKC在仓库存 / 30天平均日销
    --   - 1~180天：用滚动近30天日销（不含当天，反映历史时间节点的真实可售周期）
    --     滚动窗口天数 = MIN(lifecycle_day-1, 30)，上架<30天用实际已售天数
    --   - 超周期(>180天)：用当前时间的近30天日销（直接取商品维表 daily_avg_qty_30d）
    CASE
        -- 无库存或无日销数据时返回NULL
        WHEN sc.inventory_sku = 0 THEN NULL
        WHEN sc.lifecycle_day BETWEEN 1 AND 180 THEN
            -- 1~180天：用滚动近30天日销（不含当天）
            -- LEAST(A, B) 的作用就是比较括号里的几个值，返回其中最小的那一个。与之对应的是 GREATEST(A, B)（取最大值）。
            CASE
                WHEN COALESCE(sc.rolling_30d_qty, 0) = 0 THEN NULL
                -- 当 SKU 刚上架第 1 天（lifecycle_day = 1）时，LEAST(sc.lifecycle_day - 1, 30) 的结果为 0
                -- 上架第一天的销量，需要第二天才会采集到，所以没有近30天的销量
                WHEN LEAST(sc.lifecycle_day - 1, 30) = 0 THEN NULL
                ELSE CAST(sc.inventory_sku AS DECIMAL(18,6))
                     / (CAST(sc.rolling_30d_qty AS DECIMAL(18,6))
                        / LEAST(sc.lifecycle_day - 1, 30))
            END
        ELSE
            -- 超周期：用当前时间的近30天日销（与商品维表一致）
            COALESCE(c30.current_sellable_days, 0)
    END                                                    AS sellable_days,
    sc.sync_time                                           AS sync_time,
    CURRENT_TIMESTAMP()                                    AS insert_date,
    CURRENT_TIMESTAMP()                                    AS update_date
FROM cum_plan_skc sc
LEFT JOIN current_30d_avg_skc c30 ON sc.style_no = c30.style_no
ORDER BY sc.style_no, sc.sale_date;
```

### feishu\_dws\.dws\_sku\_abnormal\_d

```SQL
-- ============================================================
-- ETL: feishu_dws.dws_sku_abnormal_d
-- 异常条件：
--   1. style_no 或 size 为空(NULL)或 'None'，导致拼接的 style_no_size 失去意义
--   2. shelf_date（含 30_est_arrival_date 补全后）IS NULL
-- ============================================================
TRUNCATE TABLE feishu_dws.dws_sku_abnormal_d;

INSERT INTO feishu_dws.dws_sku_abnormal_d (
    sku, style_no, size, style_no_size, brand,
    shelf_date_raw, first_sales_date, abnormal_reason,
    sync_time, insert_date, update_date
)
SELECT
    p.sku                                                  AS sku,
    p.style_no                                             AS style_no,
    p.size                                                 AS size,
    CONCAT_WS('-', p.style_no, p.size)                     AS style_no_size,
    p.brand                                                AS brand,
    NULLIF(p.shelf_date, DATE('1970-01-01'))               AS shelf_date_raw,
    NULLIF(p.first_sales_date, DATE('1970-01-01'))         AS first_sales_date,
    CASE
        -- 优化点：严格校验 style_no 和 size 本身是否为空或 None
        WHEN p.style_no IS NULL OR p.style_no = 'None'
          OR p.size IS NULL OR p.size = 'None'
            THEN 'style_no或size为空或None'
        WHEN COALESCE(
                NULLIF(p.shelf_date, DATE('1970-01-01')),
                boa.est_arrival_date
             ) IS NULL
            THEN 'shelf_date为空且无30_est_arrival_date可补全'
        ELSE '未知异常'
    END                                                    AS abnormal_reason,
    p.sync_time                                            AS sync_time,
    CURRENT_TIMESTAMP()                                    AS insert_date,
    CURRENT_TIMESTAMP()                                    AS update_date
FROM feishu_dwd.dwd_feishu_product_all_d p
-- 先按 style_no_size 聚合，30_est_arrival_date 取最早时间，避免一对多导致数据膨胀
LEFT JOIN (
    SELECT
        boa.style_no_size                                  AS style_no_size,
        MIN(boa.`30_est_arrival_date`)                     AS est_arrival_date
    FROM feishu_dwd.dwd_feishu_brand_order_arrival_d boa
    GROUP BY boa.style_no_size
) boa
    ON CONCAT_WS('-', p.style_no, p.size) = boa.style_no_size
WHERE p.brand = '韦德'
  AND (
      -- 条件1：style_no 或 size 为 NULL 或 'None'
      p.style_no IS NULL OR p.style_no = 'None'
      OR p.size IS NULL OR p.size = 'None'
      -- 条件2：补全后的 shelf_date 为空
      OR COALESCE(
            NULLIF(p.shelf_date, DATE('1970-01-01')),
            boa.est_arrival_date
         ) IS NULL
  );
```

### feishu\_dws\.dws\_skc\_abnormal\_d

```SQL
-- ============================================================
-- ETL: feishu_dws.dws_skc_abnormal_d
-- 异常条件：
--   1. style_no IS NULL OR style_no = 'None'
--   2. 同一 style_no 下，存在任意一行（SKU）的补全后 shelf_date 为空(NULL)
-- ============================================================
TRUNCATE TABLE feishu_dws.dws_skc_abnormal_d;

INSERT INTO feishu_dws.dws_skc_abnormal_d (
    style_no, brand, shelf_date_raw, first_sales_date,
    abnormal_reason, sync_time, insert_date, update_date
)
SELECT
    skc.style_no                                           AS style_no,
    skc.brand                                              AS brand,
    skc.min_shelf_raw                                      AS shelf_date_raw,
    skc.min_first_sales                                    AS first_sales_date,
    CASE
        WHEN skc.style_no IS NULL OR skc.style_no = 'None'
            THEN 'style_no为空或None'
        -- 【新增】根据空值数量，精准提示是部分缺失还是全部缺失
        WHEN skc.null_shelf_count = skc.total_sku_count
            THEN '全部SKU的shelf_date为空且无30_est_arrival_date可补全'
        WHEN skc.null_shelf_count > 0
            THEN '部分SKU的shelf_date为空且无30_est_arrival_date可补全'
        ELSE '未知异常'
    END                                                    AS abnormal_reason,
    skc.max_sync_time                                      AS sync_time,
    CURRENT_TIMESTAMP()                                    AS insert_date,
    CURRENT_TIMESTAMP()                                    AS update_date
FROM (
    SELECT
        p.style_no                                         AS style_no,
        MAX(p.brand)                                       AS brand,
        MIN(NULLIF(p.shelf_date, DATE('1970-01-01')))      AS min_shelf_raw,
        MIN(NULLIF(p.first_sales_date, DATE('1970-01-01'))) AS min_first_sales,
        MAX(p.sync_time)                                   AS max_sync_time,
        -- 【新增】统计该 SKC 下补全后仍为 NULL 的行数
        SUM(CASE WHEN COALESCE(
                    NULLIF(p.shelf_date, DATE('1970-01-01')),
                    boa.est_arrival_date
                 ) IS NULL THEN 1 ELSE 0 END)              AS null_shelf_count,
        -- 【新增】统计该 SKC 下的总 SKU 行数，用于对比
        COUNT(1)                                           AS total_sku_count
    FROM feishu_dwd.dwd_feishu_product_all_d p
    -- 先按 style_no 聚合，30_est_arrival_date 取最早时间，避免一对多导致数据膨胀
    LEFT JOIN (
        SELECT
            boa.style_no                                   AS style_no,
            MIN(boa.`30_est_arrival_date`)                 AS est_arrival_date
        FROM feishu_dwd.dwd_feishu_brand_order_arrival_d boa
        GROUP BY boa.style_no
    ) boa
        ON p.style_no = boa.style_no
    WHERE p.brand = '韦德'
    GROUP BY p.style_no
) skc
WHERE skc.style_no IS NULL
   OR skc.style_no = 'None'
   -- 【优化】只要存在 1 行补全后为空，就判定为异常（覆盖了原 MIN IS NULL 的全部为空场景）
   OR skc.null_shelf_count > 0;

```

## ADS

### feishu\_ads\.ads\_sku\_sales\_plan\_180d\_d

```SQL
-- ============================================================
-- ETL: feishu_ads.ads_sku_sales_plan_180d_d
-- 粒度：style_no_size + sale_date
-- 来源：feishu_dws.dws_sku_sales_plan_180d_d + feishu_dws.dws_sku_product_info_d
-- 口径：3.1~3.25节、4.1~4.6节
-- 说明：渠道过滤已在 DWS 层完成，ADS 层无需重复过滤
-- ============================================================
TRUNCATE TABLE feishu_ads.ads_sku_sales_plan_180d_d;

INSERT INTO feishu_ads.ads_sku_sales_plan_180d_d (
    style_no_size, sale_date, lifecycle_day, sale_date_label, sales_phase,
    is_over_cycle, brand, style_no, size, ip, series, color_name,
    product_name, category, tag_price, shelf_date, first_sales_date,
    plan_pre, plan_post, daily_qty, daily_amt, cum_qty, cum_amt,
    cum_plan_qty, cum_plan_amt,
    achievement_rate, inventory_sku, available_inventory, daily_avg_qty_30d,
    sellable_days, yesterday_actual_qty, yesterday_achievement,
    `7d_achievement`, `30d_achievement`, today_plan_qty,
    order_qty, total_order_qty, achievement_ratio, should_achieve_ratio,
    sync_time, insert_date, update_date
)
WITH
-- 1. 商品维表补充属性（口径3.3/3.4/3.6节）
product_info AS (
    SELECT
        pi.style_no_size                                   AS style_no_size,
        COALESCE(NULLIF(TRIM(pi.ip), ''), 'None')          AS ip,
        COALESCE(NULLIF(TRIM(pi.series), ''), 'None')      AS series,
        COALESCE(NULLIF(TRIM(pi.color_name), ''), 'None')  AS color_name,
        pi.product_name                                    AS product_name,
        pi.category                                        AS category,
        COALESCE(pi.tag_price, 0)                          AS tag_price,
        pi.first_sales_date                                AS first_sales_date,
        pi.daily_avg_qty_30d                               AS daily_avg_qty_30d,
        pi.achievement_ratio                               AS achievement_ratio,
        COALESCE(pi.total_order_qty, 0)                    AS total_order_qty
    FROM feishu_dws.dws_sku_product_info_d pi
),
-- 2. 当前快照指标：昨日/今日/7天/30天达成（每个SKU一行，口径3.21~3.25节）
--    这些指标对同一SKU的所有行值相同，通过 JOIN 广播
current_metrics AS (
    SELECT
        sp.style_no_size                                   AS style_no_size,
        -- 口径3.21节：昨日实际销售
        MAX(CASE WHEN sp.sale_date = DATE_SUB(CURRENT_DATE(), 1)
                 THEN COALESCE(sp.actual_qty, 0) ELSE NULL END) AS yesterday_actual_qty,
        -- 口径3.22节：昨日销售达成情况 = 昨日实际 / 昨日计划(后)
        MAX(CASE WHEN sp.sale_date = DATE_SUB(CURRENT_DATE(), 1)
                 THEN sp.achievement_rate ELSE NULL END)        AS yesterday_achievement,
        -- 口径3.25节：今日计划销售数量 = 今天的销售计划(后)，超周期为0
        COALESCE(
            MAX(CASE WHEN sp.sale_date = CURRENT_DATE()
                     THEN sp.plan_post ELSE NULL END),
            0
        )                                                         AS today_plan_qty,
        -- 口径3.23节：7天销售达成情况 = 近7天实际 / 近7天计划(后)
        -- 近7天 = 昨日往前推7天（含昨日）
        CAST(
            SUM(CASE WHEN sp.sale_date BETWEEN DATE_SUB(CURRENT_DATE(), 7)
                                          AND DATE_SUB(CURRENT_DATE(), 1)
                     THEN COALESCE(sp.actual_qty, 0) ELSE 0 END)
            AS DECIMAL(18,6)
        ) / NULLIF(
            CAST(
                SUM(CASE WHEN sp.sale_date BETWEEN DATE_SUB(CURRENT_DATE(), 7)
                                              AND DATE_SUB(CURRENT_DATE(), 1)
                         THEN COALESCE(sp.plan_post, 0) ELSE 0 END)
                AS DECIMAL(18,6)
            ), 0
        )                                                         AS `7d_achievement`,
        -- 口径3.24节：30天销售达成情况 = 近30天实际 / 近30天计划(后)
        CAST(
            SUM(CASE WHEN sp.sale_date BETWEEN DATE_SUB(CURRENT_DATE(), 30)
                                          AND DATE_SUB(CURRENT_DATE(), 1)
                     THEN COALESCE(sp.actual_qty, 0) ELSE 0 END)
            AS DECIMAL(18,6)
        ) / NULLIF(
            CAST(
                SUM(CASE WHEN sp.sale_date BETWEEN DATE_SUB(CURRENT_DATE(), 30)
                                              AND DATE_SUB(CURRENT_DATE(), 1)
                         THEN COALESCE(sp.plan_post, 0) ELSE 0 END)
                AS DECIMAL(18,6)
            ), 0
        )                                                         AS `30d_achievement`
    FROM feishu_dws.dws_sku_sales_plan_180d_d sp
    GROUP BY sp.style_no_size
)
SELECT
    sp.style_no_size                                          AS style_no_size,
    sp.sale_date                                              AS sale_date,
    sp.lifecycle_day                                          AS lifecycle_day,
    -- 口径4.1节：sale_date_label 格式化为"第N天"
    CASE WHEN sp.lifecycle_day BETWEEN 1 AND 180
         THEN CONCAT('第', CAST(sp.lifecycle_day AS VARCHAR), '天')
         ELSE '超周期'
    END                                                       AS sale_date_label,
    -- 口径4.2节：销售阶段
    CASE
        WHEN sp.lifecycle_day BETWEEN 1 AND 30    THEN '新品期'
        WHEN sp.lifecycle_day BETWEEN 31 AND 120  THEN '热销期'
        WHEN sp.lifecycle_day BETWEEN 121 AND 180 THEN '清货期'
        ELSE '超周期'
    END                                                       AS sales_phase,
    -- 是否超周期标记
    CASE WHEN sp.lifecycle_day > 180 THEN 1 ELSE 0 END        AS is_over_cycle,
    sp.brand                                                 AS brand,
    sp.style_no                                              AS style_no,
    sp.size                                                  AS size,
    pi.ip                                                    AS ip,
    pi.series                                                AS series,
    pi.color_name                                            AS color_name,
    pi.product_name                                          AS product_name,
    pi.category                                              AS category,
    pi.tag_price                                             AS tag_price,
    sp.shelf_date                                            AS shelf_date,
    pi.first_sales_date                                      AS first_sales_date,
    -- 口径4.3节：销售计划(销售前)
    sp.plan_pre                                              AS plan_pre,
    -- 口径4.4节：销售计划(销售后)
    sp.plan_post                                             AS plan_post,
    -- 口径3.14/4.5节：日销量
    COALESCE(sp.actual_qty, 0)                               AS daily_qty,
    -- 口径3.15节：日金额
    COALESCE(sp.actual_amt, 0)                               AS daily_amt,
    -- 口径3.16节：累计销量 = cum_actual(N-1) + actual_qty(N)
    COALESCE(sp.cum_actual, 0) + COALESCE(sp.actual_qty, 0) AS cum_qty,
    -- 口径3.17节：累计金额
    COALESCE(sp.cum_actual_amt, 0) + COALESCE(sp.actual_amt, 0) AS cum_amt,
    -- 累计计划销量(截至N-1天)：直接取DWS销售计划表的 cum_plan_qty
    sp.cum_plan_qty                                         AS cum_plan_qty,
    -- 累计计划金额(截至N-1天)：占位0
    CAST(0 AS DECIMAL(18,6))                                AS cum_plan_amt,
    -- 口径4.6节：达成情况
    sp.achievement_rate                                      AS achievement_rate,
    -- 口径3.9节：在仓库存
    COALESCE(sp.inventory_sku, 0)                            AS inventory_sku,
    -- 口径3.10节：可提库存
    COALESCE(sp.available_inventory, 0)                      AS available_inventory,
    -- 口径3.12节：30天平均日销
    pi.daily_avg_qty_30d                                     AS daily_avg_qty_30d,
    -- 口径3.11节：可售周期
    sp.sellable_days                                         AS sellable_days,
    -- 口径3.21节：昨日实际销售
    COALESCE(cm.yesterday_actual_qty, 0)                     AS yesterday_actual_qty,
    -- 口径3.22节：昨日销售达成情况
    cm.yesterday_achievement                                 AS yesterday_achievement,
    -- 口径3.23节：7天销售达成情况
    cm.`7d_achievement`                                      AS `7d_achievement`,
    -- 口径3.24节：30天销售达成情况
    cm.`30d_achievement`                                     AS `30d_achievement`,
    -- 口径3.25节：今日计划销售数量
    cm.today_plan_qty                                        AS today_plan_qty,
    -- 口径3.18节：订货数量Q
    COALESCE(sp.order_qty, 0)                                AS order_qty,
    -- 口径3.20节：总订货数量
    pi.total_order_qty                                       AS total_order_qty,
    -- 口径3.19节：达成比例
    pi.achievement_ratio                                     AS achievement_ratio,
    -- 应达成比例：直接取DWS销售计划表的 should_achieve_ratio(基于截至N-1天的cum_plan_qty/order_qty)
    sp.should_achieve_ratio                                  AS should_achieve_ratio,
    sp.sync_time                                             AS sync_time,
    CURRENT_TIMESTAMP()                                      AS insert_date,
    CURRENT_TIMESTAMP()                                      AS update_date
FROM feishu_dws.dws_sku_sales_plan_180d_d sp
LEFT JOIN product_info pi   ON sp.style_no_size = pi.style_no_size
LEFT JOIN current_metrics cm ON sp.style_no_size = cm.style_no_size;
```

### feishu\_ads\.ads\_skc\_sales\_plan\_180d\_d

```SQL
-- ============================================================
-- ETL: feishu_ads.ads_skc_sales_plan_180d_d
-- 粒度：style_no + sale_date
-- 来源：feishu_dws.dws_skc_sales_plan_180d_d + feishu_dws.dws_skc_product_info_d
-- 口径：5.1~5.25节、6.1~6.6节
-- 说明：逻辑同 SKU 表，维度聚合到 style_no
-- ============================================================
TRUNCATE TABLE feishu_ads.ads_skc_sales_plan_180d_d;

INSERT INTO feishu_ads.ads_skc_sales_plan_180d_d (
    style_no, sale_date, lifecycle_day, sale_date_label, sales_phase,
    is_over_cycle, brand, ip, series, product_name, category, tag_price,
    shelf_date, first_sales_date, plan_pre, plan_post, daily_qty, daily_amt,
    cum_qty, cum_amt, cum_plan_qty, cum_plan_amt,
    achievement_rate, inventory_skc, available_inventory,
    daily_avg_qty_30d, sellable_days, yesterday_actual_qty,
    yesterday_achievement, `7d_achievement`, `30d_achievement`, today_plan_qty,
    order_qty, total_order_qty, achievement_ratio, should_achieve_ratio,
    sync_time, insert_date, update_date
)
WITH
-- 1. SKC商品维表补充属性（口径5.3/5.4/5.6节）
product_info_skc AS (
    SELECT
        pi.style_no                                         AS style_no,
        COALESCE(NULLIF(TRIM(pi.ip), ''), 'None')           AS ip,
        COALESCE(NULLIF(TRIM(pi.series), ''), 'None')       AS series,
        pi.product_name                                     AS product_name,
        pi.category                                         AS category,
        -- skc暂时没有吊牌价的逻辑
        0                                                   AS tag_price,
        pi.first_sales_date                                 AS first_sales_date,
        pi.daily_avg_qty_30d                                AS daily_avg_qty_30d,
        pi.achievement_ratio                                AS achievement_ratio,
        COALESCE(pi.total_order_qty, 0)                     AS total_order_qty
    FROM feishu_dws.dws_skc_product_info_d pi
),
-- 2. 当前快照指标：昨日/今日/7天/30天达成（每个SKC一行，口径5.21~5.25节）
current_metrics_skc AS (
    SELECT
        sp.style_no                                         AS style_no,
        -- 口径5.21节：昨日实际销售
        MAX(CASE WHEN sp.sale_date = DATE_SUB(CURRENT_DATE(), 1)
                 THEN COALESCE(sp.actual_qty, 0) ELSE NULL END) AS yesterday_actual_qty,
        -- 口径5.22节：昨日销售达成情况
        MAX(CASE WHEN sp.sale_date = DATE_SUB(CURRENT_DATE(), 1)
                 THEN sp.achievement_rate ELSE NULL END)        AS yesterday_achievement,
        -- 口径5.25节：今日计划销售数量，超周期为0
        COALESCE(
            MAX(CASE WHEN sp.sale_date = CURRENT_DATE()
                     THEN sp.plan_post ELSE NULL END),
            0
        )                                                         AS today_plan_qty,
        -- 口径5.23节：7天销售达成情况
        CAST(
            SUM(CASE WHEN sp.sale_date BETWEEN DATE_SUB(CURRENT_DATE(), 7)
                                          AND DATE_SUB(CURRENT_DATE(), 1)
                     THEN COALESCE(sp.actual_qty, 0) ELSE 0 END)
            AS DECIMAL(18,6)
        ) / NULLIF(
            CAST(
                SUM(CASE WHEN sp.sale_date BETWEEN DATE_SUB(CURRENT_DATE(), 7)
                                              AND DATE_SUB(CURRENT_DATE(), 1)
                         THEN COALESCE(sp.plan_post, 0) ELSE 0 END)
                AS DECIMAL(18,6)
            ), 0
        )                                                         AS `7d_achievement`,
        -- 口径5.24节：30天销售达成情况
        CAST(
            SUM(CASE WHEN sp.sale_date BETWEEN DATE_SUB(CURRENT_DATE(), 30)
                                          AND DATE_SUB(CURRENT_DATE(), 1)
                     THEN COALESCE(sp.actual_qty, 0) ELSE 0 END)
            AS DECIMAL(18,6)
        ) / NULLIF(
            CAST(
                SUM(CASE WHEN sp.sale_date BETWEEN DATE_SUB(CURRENT_DATE(), 30)
                                              AND DATE_SUB(CURRENT_DATE(), 1)
                         THEN COALESCE(sp.plan_post, 0) ELSE 0 END)
                AS DECIMAL(18,6)
            ), 0
        )                                                         AS `30d_achievement`
    FROM feishu_dws.dws_skc_sales_plan_180d_d sp
    GROUP BY sp.style_no
)
SELECT
    sp.style_no                                              AS style_no,
    sp.sale_date                                              AS sale_date,
    sp.lifecycle_day                                          AS lifecycle_day,
    -- 口径6.1节：sale_date_label 格式化为"第N天"
    CASE WHEN sp.lifecycle_day BETWEEN 1 AND 180
         THEN CONCAT('第', CAST(sp.lifecycle_day AS VARCHAR), '天')
         ELSE '超周期'
    END                                                       AS sale_date_label,
    -- 口径6.2节：销售阶段
    CASE
        WHEN sp.lifecycle_day BETWEEN 1 AND 30    THEN '新品期'
        WHEN sp.lifecycle_day BETWEEN 31 AND 120  THEN '热销期'
        WHEN sp.lifecycle_day BETWEEN 121 AND 180 THEN '清货期'
        ELSE '超周期'
    END                                                       AS sales_phase,
    -- 是否超周期标记
    CASE WHEN sp.lifecycle_day > 180 THEN 1 ELSE 0 END        AS is_over_cycle,
    sp.brand                                                 AS brand,
    pi.ip                                                    AS ip,
    pi.series                                                AS series,
    pi.product_name                                          AS product_name,
    pi.category                                              AS category,
    pi.tag_price                                             AS tag_price,
    sp.shelf_date                                            AS shelf_date,
    pi.first_sales_date                                      AS first_sales_date,
    -- 口径6.3节：销售计划(销售前)
    sp.plan_pre                                              AS plan_pre,
    -- 口径6.4节：销售计划(销售后)
    sp.plan_post                                             AS plan_post,
    -- 口径5.14/6.5节：日销量
    COALESCE(sp.actual_qty, 0)                               AS daily_qty,
    -- 口径5.15节：日金额
    COALESCE(sp.actual_amt, 0)                               AS daily_amt,
    -- 口径5.16节：累计销量
    COALESCE(sp.cum_actual, 0) + COALESCE(sp.actual_qty, 0) AS cum_qty,
    -- 口径5.17节：累计金额
    COALESCE(sp.cum_actual_amt, 0) + COALESCE(sp.actual_amt, 0) AS cum_amt,
    -- SKC累计计划销量(截至N-1天)：直接取DWS销售计划表的 cum_plan_qty
    sp.cum_plan_qty                                         AS cum_plan_qty,
    -- SKC累计计划金额(截至N-1天)：占位0
    CAST(0 AS DECIMAL(18,6))                                AS cum_plan_amt,
    -- 口径6.6节：达成情况
    sp.achievement_rate                                      AS achievement_rate,
    -- 口径5.9节：SKC在仓库存
    COALESCE(sp.inventory_sku, 0)                            AS inventory_skc,
    -- 口径5.10节：SKC可提库存
    COALESCE(sp.available_inventory, 0)                      AS available_inventory,
    -- 口径5.12节：30天平均日销
    pi.daily_avg_qty_30d                                     AS daily_avg_qty_30d,
    -- 口径5.11节：可售周期
    sp.sellable_days                                         AS sellable_days,
    -- 口径5.21节：昨日实际销售
    COALESCE(cm.yesterday_actual_qty, 0)                     AS yesterday_actual_qty,
    -- 口径5.22节：昨日销售达成情况
    cm.yesterday_achievement                                 AS yesterday_achievement,
    -- 口径5.23节：7天销售达成情况
    cm.`7d_achievement`                                      AS `7d_achievement`,
    -- 口径5.24节：30天销售达成情况
    cm.`30d_achievement`                                     AS `30d_achievement`,
    -- 口径5.25节：今日计划销售数量
    cm.today_plan_qty                                        AS today_plan_qty,
    -- 口径5.18节：SKC订货数量Q
    COALESCE(sp.order_qty, 0)                                AS order_qty,
    -- 口径5.20节：SKC总订货数量
    pi.total_order_qty                                       AS total_order_qty,
    -- 口径5.19节：SKC达成比例
    pi.achievement_ratio                                     AS achievement_ratio,
    -- SKC应达成比例：直接取DWS销售计划表的 should_achieve_ratio(基于截至N-1天的cum_plan_qty/order_qty)
    sp.should_achieve_ratio                                  AS should_achieve_ratio,
    sp.sync_time                                             AS sync_time,
    CURRENT_TIMESTAMP()                                      AS insert_date,
    CURRENT_TIMESTAMP()                                      AS update_date
FROM feishu_dws.dws_skc_sales_plan_180d_d sp
LEFT JOIN product_info_skc pi  ON sp.style_no = pi.style_no
LEFT JOIN current_metrics_skc cm ON sp.style_no = cm.style_no;
```

# 5、SQL逻辑

## QUICKBI:

### feishu\_ads\.ads\_sku\_sales\_plan\_180d\_d

```JavaScript
-- ============================================================
-- 数据集名称：SKU销售计划数据集
-- 数据来源：feishu_ads.ads_sku_sales_plan_180d_d
-- 粒度：style_no_size + sale_date
-- 说明：直接查询ADS表，AS别名使用ADS字段备注名称
-- ============================================================
SELECT
    -- 1. 主维度
    `style_no_size`            AS `SKU编码`,
    -- 2. 商品属性维度
    `style_no`                 AS `款号`,
    `brand`                    AS `品牌`,
    `series`                   AS `系列`,
    `ip`                       AS `IP`,
    `size`                     AS `尺码`,
    `color_name`               AS `配色名`,
    `product_name`             AS `商品名称`,
    `category`                 AS `品类`,
    `tag_price`                AS `吊牌价`,
    `shelf_date`               AS `上架日期`,
    `first_sales_date`         AS `首次销售日期`,
    -- 3. 时间维度
    `sale_date`                AS `销售日期`,
    `lifecycle_day`            AS `上市第N天`,
    `sale_date_label`          AS `销售日期标签`,
    REPLACE(`sale_date_label`, '第', '') AS `销售日期标签_简洁版`,
        -- 新增排序字段：将"第N天"的N提取并左补零至3位，超周期赋值为999，确保按字符串升序排列时顺序正确
    CASE 
        WHEN `sale_date_label` = '超周期' THEN '999'
        ELSE LPAD(REPLACE(REPLACE(`sale_date_label`, '第', ''), '天', ''), 3, '0')
    END                        AS `销售日期标签_排序`,
    `sales_phase`              AS `销售阶段`,
    `is_over_cycle`            AS `是否超周期`,
    -- 4. 销售计划
    `plan_pre`                 AS `销售计划(销售前)`,
    `plan_post`                AS `销售计划(销售后)`,
    -- 5. 实际销售与累计
    `daily_qty`                AS `日销量`,
    `daily_amt`                AS `日金额`,
    `cum_qty`                  AS `累计销量`,
    `cum_amt`                  AS `累计金额`,
    `cum_plan_qty`             AS `累计计划销量`,
    `cum_plan_amt`             AS `累计计划金额`,
    -- 6. 达成情况
    `achievement_rate`         AS `达成情况`,
    `achievement_ratio`        AS `达成比例`,
    -- 7. 库存指标
    `inventory_sku`            AS `在仓库存`,
    `available_inventory`      AS `可提库存`,
    `daily_avg_qty_30d`        AS `30天平均日销`,
    `sellable_days`            AS `可售周期天数`,
    -- 8. 当前快照指标
    `yesterday_actual_qty`     AS `昨日实际销售`,
    `yesterday_achievement`    AS `昨日销售达成情况`,
    `7d_achievement`           AS `7天销售达成情况`,
    `30d_achievement`          AS `30天销售达成情况`,
    `today_plan_qty`           AS `今日计划销售数量`,
    -- 9. 订货指标
    `order_qty`                AS `订货数量`,
    `total_order_qty`          AS `总订货数量`,
    `should_achieve_ratio`     AS `应达成比例`
FROM feishu_ads.ads_sku_sales_plan_180d_d;
```

### feishu\_ads\.ads\_skc\_sales\_plan\_180d\_d

```JavaScript
-- ============================================================
-- 数据集名称：SKC销售计划数据集
-- 数据来源：feishu_ads.ads_skc_sales_plan_180d_d
-- 粒度：style_no + sale_date
-- 说明：直接查询ADS表，AS别名使用ADS字段备注名称
-- ============================================================
SELECT
    -- 1. 主维度
    `style_no`                 AS `SKC编码`,
    -- 2. 商品属性维度
    `brand`                    AS `品牌`,
    `series`                   AS `系列`,
    `ip`                       AS `IP`,
    `product_name`             AS `商品名称`,
    `category`                 AS `品类`,
    `tag_price`                AS `吊牌价`,
    `shelf_date`               AS `SKC上架日期`,
    `first_sales_date`         AS `SKC首次销售日期`,
    -- 3. 时间维度
    `sale_date`                AS `销售日期`,
    `lifecycle_day`            AS `上市第N天`,
    `sale_date_label`          AS `销售日期标签`,
    REPLACE(`sale_date_label`, '第', '') AS `销售日期标签_简洁版`,
        -- 新增排序字段：将"第N天"的N提取并左补零至3位，超周期赋值为999，确保按字符串升序排列时顺序正确
    CASE 
        WHEN `sale_date_label` = '超周期' THEN '999'
        ELSE LPAD(REPLACE(REPLACE(`sale_date_label`, '第', ''), '天', ''), 3, '0')
    END                        AS `销售日期标签_排序`,
    `sales_phase`              AS `销售阶段`,
    `is_over_cycle`            AS `是否超周期`,
    -- 4. 销售计划
    `plan_pre`                 AS `销售计划(销售前)`,
    `plan_post`                AS `销售计划(销售后)`,
    -- 5. 实际销售与累计
    `daily_qty`                AS `日销量`,
    `daily_amt`                AS `日金额`,
    `cum_qty`                  AS `累计销量`,
    `cum_amt`                  AS `累计金额`,
    `cum_plan_qty`             AS `SKC累计计划销量`,
    `cum_plan_amt`             AS `SKC累计计划金额`,
    -- 6. 达成情况
    `achievement_rate`         AS `达成情况`,
    `achievement_ratio`        AS `SKC达成比例`,
    -- 7. 库存指标
    `inventory_skc`            AS `SKC在仓库存`,
    `available_inventory`      AS `SKC可提库存`,
    `daily_avg_qty_30d`        AS `SKC30天平均日销`,
    `sellable_days`            AS `SKC可售周期天数`,
    -- 8. 当前快照指标
    `yesterday_actual_qty`     AS `昨日实际销售`,
    `yesterday_achievement`    AS `昨日销售达成情况`,
    `7d_achievement`           AS `7天销售达成情况`,
    `30d_achievement`          AS `30天销售达成情况`,
    `today_plan_qty`           AS `今日计划销售数量`,
    -- 9. 订货指标
    `order_qty`                AS `SKC订货数量`,
    `total_order_qty`          AS `SKC总订货数量`,
    `should_achieve_ratio`     AS `SKC应达成比例`
FROM feishu_ads.ads_skc_sales_plan_180d_d;
```











# 6、视图语句

## DWD:

### feishu\_dwd\.v\_feishu\_sales\_361\_d

```SQL
DROP VIEW IF EXISTS feishu_dwd.v_feishu_sales_361_d;
CREATE VIEW feishu_dwd.v_feishu_sales_361_d AS
SELECT
    id, 
    COALESCE(NULLIF(TRIM(record_id), ''), 'None') AS record_id,
    '361' AS brand, 
    COALESCE(NULLIF(TRIM(SKU), ''), 'None') AS sku,
    -- 【修改】ODS为datetime，去掉TRIM/NULLIF，直接提取DATE
    COALESCE(DATE(销售日期), DATE('1970-01-01')) AS sales_date,
    
    -- 【修改】ODS为decimal，去掉TRIM/NULLIF，增加ROUND防止小数直接转BIGINT报错
    COALESCE(CAST(ROUND(`361sport-销量`, 0) AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(ROUND(`中国公司(361°客户)-销量`, 0) AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(ROUND(`361°寄样-销量`, 0) AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(ROUND(`员工内购（香港）-销量`, 0) AS BIGINT), 0) AS qty_staff_hk,
    
    -- 【修改】ODS为decimal，去掉TRIM/NULLIF，直接CAST转换精度
    COALESCE(CAST(`361sport-金额` AS DECIMAL(18,6)), 0) AS amt_361sport,
    COALESCE(CAST(`中国公司(361°客户)-金额` AS DECIMAL(18,6)), 0) AS amt_china,
    COALESCE(CAST(`361°寄样-金额` AS DECIMAL(18,6)), 0) AS amt_sample,
    COALESCE(CAST(`员工内购（香港）-金额` AS DECIMAL(18,6)), 0) AS amt_staff_hk,
    
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_01' AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS insert_date,  -- 视图无ETL写入，用sync_time占位
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS update_date
FROM feishu.t_361sales_01 WHERE record_id IS NOT NULL

UNION ALL

SELECT
    id, 
    COALESCE(NULLIF(TRIM(record_id), ''), 'None') AS record_id,
    '361' AS brand, 
    COALESCE(NULLIF(TRIM(SKU), ''), 'None') AS sku,
    COALESCE(DATE(销售日期), DATE('1970-01-01')) AS sales_date,
    
    COALESCE(CAST(ROUND(`361sport-销量`, 0) AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(ROUND(`中国公司(361°客户)-销量`, 0) AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(ROUND(`361°寄样-销量`, 0) AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(ROUND(`员工内购（香港）-销量`, 0) AS BIGINT), 0) AS qty_staff_hk,
    
    COALESCE(CAST(`361sport-金额` AS DECIMAL(18,6)), 0) AS amt_361sport,
    COALESCE(CAST(`中国公司(361°客户)-金额` AS DECIMAL(18,6)), 0) AS amt_china,
    COALESCE(CAST(`361°寄样-金额` AS DECIMAL(18,6)), 0) AS amt_sample,
    COALESCE(CAST(`员工内购（香港）-金额` AS DECIMAL(18,6)), 0) AS amt_staff_hk,
    
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_02' AS source_table,
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
    COALESCE(DATE(销售日期), DATE('1970-01-01')) AS sales_date,
    
    COALESCE(CAST(ROUND(`361sport-销量`, 0) AS BIGINT), 0) AS qty_361sport,
    COALESCE(CAST(ROUND(`中国公司(361°客户)-销量`, 0) AS BIGINT), 0) AS qty_china,
    COALESCE(CAST(ROUND(`361°寄样-销量`, 0) AS BIGINT), 0) AS qty_sample,
    COALESCE(CAST(ROUND(`员工内购（香港）-销量`, 0) AS BIGINT), 0) AS qty_staff_hk,
    
    COALESCE(CAST(`361sport-金额` AS DECIMAL(18,6)), 0) AS amt_361sport,
    COALESCE(CAST(`中国公司(361°客户)-金额` AS DECIMAL(18,6)), 0) AS amt_china,
    COALESCE(CAST(`361°寄样-金额` AS DECIMAL(18,6)), 0) AS amt_sample,
    COALESCE(CAST(`员工内购（香港）-金额` AS DECIMAL(18,6)), 0) AS amt_staff_hk,
    
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS sync_time,
    't_361sales_050' AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS insert_date,  -- 视图无ETL写入，用sync_time占位
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME)) AS update_date
FROM feishu.t_361sales_50 WHERE record_id IS NOT NULL;

```

### feishu\_dwd\.v\_feishu\_sales\_wd\_d

#### v1版本：

```JavaScript
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
    -- 字符串类型 (varchar)：保留 TRIM 和 NULLIF
    COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
    '韦德'                                                                           AS brand,
    COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    
    -- 日期时间类型 (datetime)：场景一，去除 TRIM 和 NULLIF
    COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
    
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- ================= 8个销售指标 =================
    -- VARCHAR 转 BIGINT：场景二，先转 DECIMAL 再 ROUND 转 BIGINT
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货1`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS order_replenish_1,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货`), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)  AS order_replenish,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)   AS actual_total_qty,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS est_cycle_days,
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)    AS est_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT
    COALESCE(CAST(ROUND(预计销量, 0) AS BIGINT), 0)                                 AS est_qty,
    
    -- VARCHAR 转 BIGINT：场景二
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0)    AS actual_week_qty,
    
    -- DECIMAL 转 BIGINT：场景一
    COALESCE(CAST(ROUND(实际销量, 0) AS BIGINT), 0)                                 AS actual_qty,
    
    -- ================= 18个渠道销量 =================
    -- DECIMAL 转 BIGINT：场景一，直接 ROUND 转 BIGINT，去除 TRIM 和 NULLIF
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- ================= 18个渠道金额 =================
    -- DECIMAL 转 DECIMAL(18,6)：场景一，直接 CAST 控制精度，去除 TRIM 和 NULLIF
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- ================= 汇总与系统字段 =================
    -- VARCHAR 转 DECIMAL：场景二，保留 TRIM 和 NULLIF
    COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
    -- DECIMAL 转 DECIMAL：场景一，去除 TRIM 和 NULLIF
    COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                 AS total_sum_copy,
    
    -- 日期时间类型 (datetime)：场景一
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
    
    -- 日期时间类型 (datetime)：场景一
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
    COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
    COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
    COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
    COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
    
    -- 23分表缺失7个指标补0，保留actual_qty
    0                                                                               AS order_replenish_1,
    0                                                                               AS order_replenish,
    0                                                                               AS actual_total_qty,
    0                                                                               AS est_cycle_days,
    0                                                                               AS est_week_qty,
    0                                                                               AS est_qty,
    0                                                                               AS actual_week_qty,
    
    -- 23分表"实际销量"为varchar，需CAST：场景二
    COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际销量), '') AS DECIMAL(18,4)), 0) AS BIGINT), 0) AS actual_qty,
    
    -- 18个渠道销量 (DECIMAL -> BIGINT，场景一)
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- 18个渠道金额 (DECIMAL -> DECIMAL，场景一)
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- 汇总与系统字段 (23缺总和副本)
    -- VARCHAR 转 DECIMAL：场景二
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
    
    -- 日期时间类型 (datetime)：场景一
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
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
    
    -- 18个渠道销量 (DECIMAL -> BIGINT，场景一)
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- 18个渠道金额 (DECIMAL -> DECIMAL，场景一)
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
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
    
    -- 日期时间类型 (datetime)：场景一
    COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
    
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
    
    -- 18个渠道销量 (DECIMAL -> BIGINT，场景一)
    COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
    COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
    COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
    COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
    COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
    COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
    COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
    COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
    COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
    COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
    COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
    COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
    COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
    COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
    COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
    COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
    COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
    COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
    
    -- 18个渠道金额 (DECIMAL -> DECIMAL，场景一)
    COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
    COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
    COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
    COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
    COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
    COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
    COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
    COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
    COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
    COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
    COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
    COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
    COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
    COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
    COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
    COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
    COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
    COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
    
    -- 汇总与系统字段 (50全缺失补0)
    0                                                                               AS total_sum,
    0                                                                               AS total_sum_copy,
    
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
    'wd_sales_50'                                                                   AS source_table,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
    COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
FROM feishu.wd_sales_50 
WHERE record_id IS NOT NULL;

```

#### v2版本：

```JavaScript
-- ============================================================
        -- 方案二：视图（feishu_dwd.v_feishu_sales_wd_d）
        -- 不落物化表，查询时实时UNION ALL 6张分表（结构完全对齐）
        -- 适用：数据探查、低频查询、节省存储；不适合高频分析场景
        -- ============================================================
        DROP VIEW IF EXISTS feishu_dwd.v_feishu_sales_wd_d;
        CREATE VIEW feishu_dwd.v_feishu_sales_wd_d AS
        -- ==========================================
        -- wd_sales_01
        -- ==========================================
        SELECT
            id                                                                              AS id,
            -- 字符串类型：保留 TRIM 和 NULLIF
            COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
            '韦德'                                                                           AS brand,
            COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
            -- 日期时间类型：去除 TRIM 和 NULLIF
            COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
            COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
            COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
            COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
            COALESCE(NULLIF(TRIM(自然周), ''), 'None')                                      AS natural_week,
            COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
            -- ================= 11个销售指标 =================
            -- VARCHAR 转 BIGINT：先转 DECIMAL 再 ROUND 转 BIGINT
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货1`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish_1,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_total_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_cycle_days,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_qty,
            COALESCE(NULLIF(TRIM(达成率), ''), 'None')                                      AS achievement_rate,
            COALESCE(NULLIF(TRIM(预警), ''), 'None')                                        AS alert,
            -- ================= 18个渠道销量 =================
            -- DECIMAL 转 BIGINT：直接 ROUND 转 BIGINT
            COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
            COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
            COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
            COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
            COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
            COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
            COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
            COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
            COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
            COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
            COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
            COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
            COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
            COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
            COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
            COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
            COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
            COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
            -- ================= 18个渠道金额 =================
            -- DECIMAL 转 DECIMAL(18,6)：直接 CAST 控制精度
            COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
            COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
            COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
            COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
            COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
            COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
            COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
            COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
            COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
            COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
            COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
            COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
            COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
            COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
            COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
            COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
            COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
            COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
            -- ================= 汇总与系统字段 =================
            -- VARCHAR 转 DECIMAL：保留 TRIM 和 NULLIF
            COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
            -- DECIMAL 转 DECIMAL：去除 TRIM 和 NULLIF
            COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                  AS total_sum_copy,
            -- 日期时间类型：去除 TRIM 和 NULLIF
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
            'wd_sales_01'                                                                   AS source_table,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
        FROM feishu.wd_sales_01 
        WHERE record_id IS NOT NULL
        UNION ALL
        -- ==========================================
        -- wd_sales_02
        -- ==========================================
        SELECT
            id                                                                              AS id,
            COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
            '韦德'                                                                           AS brand,
            COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
            COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
            COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
            COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
            COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
            COALESCE(NULLIF(TRIM(自然周), ''), 'None')                                      AS natural_week,
            COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货1`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish_1,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_total_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_cycle_days,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_qty,
            COALESCE(NULLIF(TRIM(达成率), ''), 'None')                                      AS achievement_rate,
            COALESCE(NULLIF(TRIM(预警), ''), 'None')                                        AS alert,
            COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
            COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
            COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
            COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
            COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
            COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
            COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
            COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
            COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
            COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
            COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
            COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
            COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
            COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
            COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
            COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
            COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
            COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
            COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
            COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
            COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
            COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
            COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
            COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
            COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
            COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
            COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
            COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
            COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
            COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
            COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
            COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
            COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
            COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
            COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
            COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
            COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
            COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                  AS total_sum_copy,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
            'wd_sales_02'                                                                   AS source_table,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
        FROM feishu.wd_sales_02 
        WHERE record_id IS NOT NULL
        UNION ALL
        -- ==========================================
        -- wd_sales_03
        -- ==========================================
        SELECT
            id                                                                              AS id,
            COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
            '韦德'                                                                           AS brand,
            COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
            COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
            COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
            COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
            COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
            COALESCE(NULLIF(TRIM(自然周), ''), 'None')                                      AS natural_week,
            COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货1`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish_1,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_total_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_cycle_days,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_qty,
            COALESCE(NULLIF(TRIM(达成率), ''), 'None')                                      AS achievement_rate,
            COALESCE(NULLIF(TRIM(预警), ''), 'None')                                        AS alert,
            COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
            COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
            COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
            COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
            COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
            COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
            COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
            COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
            COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
            COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
            COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
            COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
            COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
            COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
            COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
            COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
            COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
            COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
            COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
            COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
            COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
            COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
            COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
            COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
            COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
            COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
            COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
            COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
            COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
            COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
            COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
            COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
            COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
            COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
            COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
            COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
            COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
            COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                  AS total_sum_copy,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
            'wd_sales_03'                                                                   AS source_table,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
        FROM feishu.wd_sales_03 
        WHERE record_id IS NOT NULL
        UNION ALL
        -- ==========================================
        -- wd_sales_04
        -- ==========================================
        SELECT
            id                                                                              AS id,
            COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
            '韦德'                                                                           AS brand,
            COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
            COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
            COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
            COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
            COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
            COALESCE(NULLIF(TRIM(自然周), ''), 'None')                                      AS natural_week,
            COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货1`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish_1,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_total_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_cycle_days,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_qty,
            COALESCE(NULLIF(TRIM(达成率), ''), 'None')                                      AS achievement_rate,
            COALESCE(NULLIF(TRIM(预警), ''), 'None')                                        AS alert,
            COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
            COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
            COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
            COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
            COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
            COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
            COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
            COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
            COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
            COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
            COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
            COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
            COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
            COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
            COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
            COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
            COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
            COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
            COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
            COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
            COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
            COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
            COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
            COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
            COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
            COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
            COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
            COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
            COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
            COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
            COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
            COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
            COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
            COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
            COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
            COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
            COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
            COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                  AS total_sum_copy,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
            'wd_sales_04'                                                                   AS source_table,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
        FROM feishu.wd_sales_04 
        WHERE record_id IS NOT NULL
        UNION ALL
        -- ==========================================
        -- wd_sales_05
        -- ==========================================
        SELECT
            id                                                                              AS id,
            COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
            '韦德'                                                                           AS brand,
            COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
            COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
            COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
            COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
            COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
            COALESCE(NULLIF(TRIM(自然周), ''), 'None')                                      AS natural_week,
            COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货1`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish_1,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_total_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_cycle_days,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_qty,
            COALESCE(NULLIF(TRIM(达成率), ''), 'None')                                      AS achievement_rate,
            COALESCE(NULLIF(TRIM(预警), ''), 'None')                                        AS alert,
            COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
            COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
            COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
            COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
            COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
            COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
            COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
            COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
            COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
            COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
            COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
            COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
            COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
            COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
            COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
            COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
            COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
            COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
            COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
            COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
            COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
            COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
            COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
            COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
            COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
            COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
            COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
            COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
            COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
            COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
            COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
            COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
            COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
            COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
            COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
            COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
            COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
            COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                  AS total_sum_copy,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
            'wd_sales_05'                                                                   AS source_table,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
        FROM feishu.wd_sales_05 
        WHERE record_id IS NOT NULL
        UNION ALL
        -- ==========================================
        -- wd_sales_06
        -- ==========================================
        SELECT
            id                                                                              AS id,
            COALESCE(NULLIF(TRIM(record_id), ''), 'None')                                   AS record_id,
            '韦德'                                                                           AS brand,
            COALESCE(NULLIF(TRIM(SKU), ''), 'None')                                         AS sku,
            COALESCE(DATE(销售日期), DATE('1970-01-01'))                                    AS sales_date,
            COALESCE(NULLIF(TRIM(款号), ''), 'None')                                        AS style_no,
            COALESCE(NULLIF(TRIM(尺码), ''), 'None')                                        AS size,
            COALESCE(DATE(首次销售日期), DATE('1970-01-01'))                                AS first_sales_date,
            COALESCE(NULLIF(TRIM(自然周), ''), 'None')                                      AS natural_week,
            COALESCE(NULLIF(TRIM(销售周期所属周), ''), 'None')                              AS sales_week,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货1`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish_1,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货+补货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_replenish,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货数量`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际总销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_total_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销售周期天数), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_cycle_days,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(预计销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS est_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际周销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_week_qty,
            COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(实际销量), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS actual_qty,
            COALESCE(NULLIF(TRIM(达成率), ''), 'None')                                      AS achievement_rate,
            COALESCE(NULLIF(TRIM(预警), ''), 'None')                                        AS alert,
            COALESCE(CAST(ROUND(`韦德之道-销量`, 0) AS BIGINT), 0)                          AS qty_wd,
            COALESCE(CAST(ROUND(`韦德之道寄样-销量`, 0) AS BIGINT), 0)                      AS qty_wd_sample,
            COALESCE(CAST(ROUND(`得物APP_韦德-销量`, 0) AS BIGINT), 0)                      AS qty_dewu,
            COALESCE(CAST(ROUND(`韦德之道-得物寄售-销量`, 0) AS BIGINT), 0)                 AS qty_dewu_consign,
            COALESCE(CAST(ROUND(`得物APP转寄_95分-销量`, 0) AS BIGINT), 0)                  AS qty_95fen,
            COALESCE(CAST(ROUND(`广东炫动商贸有限公司(李宁客户)-销量`, 0) AS BIGINT), 0)    AS qty_guangdong,
            COALESCE(CAST(ROUND(`全勇分销-销量`, 0) AS BIGINT), 0)                          AS qty_quanyong,
            COALESCE(CAST(ROUND(`应科迪_客户-销量`, 0) AS BIGINT), 0)                       AS qty_yingkedi,
            COALESCE(CAST(ROUND(`韦德线下店铺-销量`, 0) AS BIGINT), 0)                      AS qty_offline,
            COALESCE(CAST(ROUND(`韦德日本站-销量`, 0) AS BIGINT), 0)                        AS qty_japan,
            COALESCE(CAST(ROUND(`韦德西语站-销量`, 0) AS BIGINT), 0)                        AS qty_spanish,
            COALESCE(CAST(ROUND(`dw_韦德伟宏店-销量`, 0) AS BIGINT), 0)                     AS qty_weihong,
            COALESCE(CAST(ROUND(`韦德_95分店-销量`, 0) AS BIGINT), 0)                       AS qty_95fen_shop,
            COALESCE(CAST(ROUND(`拼多多_博耶运动户外专营店-销量`, 0) AS BIGINT), 0)         AS qty_pdd,
            COALESCE(CAST(ROUND(`eBay-销量`, 0) AS BIGINT), 0)                              AS qty_ebay,
            COALESCE(CAST(ROUND(`韦德之道--招待费-销量`, 0) AS BIGINT), 0)                  AS qty_entertainment,
            COALESCE(CAST(ROUND(`韦德德国站-销量`, 0) AS BIGINT), 0)                        AS qty_germany,
            COALESCE(CAST(ROUND(`韦德之道B2B-销量`, 0) AS BIGINT), 0)                       AS qty_b2b,
            COALESCE(CAST(`韦德之道-金额` AS DECIMAL(18,6)), 0)                             AS amt_wd,
            COALESCE(CAST(`韦德之道寄样-金额` AS DECIMAL(18,6)), 0)                         AS amt_wd_sample,
            COALESCE(CAST(`得物APP_韦德-金额` AS DECIMAL(18,6)), 0)                         AS amt_dewu,
            COALESCE(CAST(`韦德之道-得物寄售-金额` AS DECIMAL(18,6)), 0)                    AS amt_dewu_consign,
            COALESCE(CAST(`得物APP转寄_95分-金额` AS DECIMAL(18,6)), 0)                     AS amt_95fen,
            COALESCE(CAST(`广东炫动商贸有限公司(李宁客户)-金额` AS DECIMAL(18,6)), 0)       AS amt_guangdong,
            COALESCE(CAST(`全勇分销-金额` AS DECIMAL(18,6)), 0)                             AS amt_quanyong,
            COALESCE(CAST(`应科迪_客户-金额` AS DECIMAL(18,6)), 0)                          AS amt_yingkedi,
            COALESCE(CAST(`韦德线下店铺-金额` AS DECIMAL(18,6)), 0)                         AS amt_offline,
            COALESCE(CAST(`韦德日本站-金额` AS DECIMAL(18,6)), 0)                           AS amt_japan,
            COALESCE(CAST(`韦德西语站-金额` AS DECIMAL(18,6)), 0)                           AS amt_spanish,
            COALESCE(CAST(`dw_韦德伟宏店-金额` AS DECIMAL(18,6)), 0)                        AS amt_weihong,
            COALESCE(CAST(`韦德_95分店-金额` AS DECIMAL(18,6)), 0)                          AS amt_95fen_shop,
            COALESCE(CAST(`拼多多_博耶运动户外专营店-金额` AS DECIMAL(18,6)), 0)            AS amt_pdd,
            COALESCE(CAST(`eBay-金额` AS DECIMAL(18,6)), 0)                                 AS amt_ebay,
            COALESCE(CAST(`韦德之道--招待费-金额` AS DECIMAL(18,6)), 0)                     AS amt_entertainment,
            COALESCE(CAST(`韦德德国站-金额` AS DECIMAL(18,6)), 0)                           AS amt_germany,
            COALESCE(CAST(`韦德之道B2B-金额` AS DECIMAL(18,6)), 0)                          AS amt_b2b,
            COALESCE(CAST(NULLIF(TRIM(`总和`), '') AS DECIMAL(18,6)), 0)                    AS total_sum,
            COALESCE(CAST(`总和 副本` AS DECIMAL(18,6)), 0)                                  AS total_sum_copy,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS sync_time,
            'wd_sales_06'                                                                   AS source_table,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS insert_date,
            COALESCE(sync_time, CAST('1970-01-01 00:00:00' AS DATETIME))                    AS update_date
        FROM feishu.wd_sales_06 
        WHERE record_id IS NOT NULL;
```

# 测试：

```SQL
SELECT COUNT(*) FROM feishu_dwd.dwd_feishu_brand_order_arrival_d

SELECT * FROM feishu.wd_shop
WHERE 1=1
and CONCAT_WS ('-',款号,尺码) = 'ABCV035-3-10'

SELECT * FROM feishu_dwd.dwd_feishu_product_wd_d
WHERE 1=1
and CONCAT_WS ('-',style_no,size) = 'ABCV035-3-10'

SELECT * FROM feishu_dwd.dwd_feishu_product_all_d
WHERE 1=1
and CONCAT_WS ('-',style_no,size) = 'ABCV035-3-10'

SELECT * FROM feishu_dws.dws_sku_product_info_d
WHERE 1=1
and CONCAT_WS ('-',style_no,size) = 'ABCV035-3-10'

SELECT * FROM feishu_dws.dws_sku_sales_plan_180d_d
WHERE 1=1
and style_no_size = 'ABCV035-3-10'
```

