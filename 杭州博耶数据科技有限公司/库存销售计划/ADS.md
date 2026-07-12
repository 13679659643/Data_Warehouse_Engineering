# ADS层：应用数据层（DWS → ADS 完整解决方案）

> 编写日期：2026-07-12
> 适用范围：韦德品牌4个核心渠道 `channel_code IN ('wd', 'japan', 'spanish', 'germany')`，不考虑361品牌
> 口径依据：`杭州博耶数据科技有限公司/指标口径/基于DWD层的字段口径定义.md`
> 数据基座：DWS层6张核心表（均带 `feishu_dws.` 前缀）

## 设计目标

将 DWS 层汇总数据加工为面向 QuickBI 直接消费的宽表，支持 SKU / SKC 两个维度的 1~180 天销售计划展示。ADS 层以 SELECT + JOIN 为主，不做复杂计算（计算已在 DWS 层完成），重点在于字段业务化命名、预计算展示指标、对齐 QuickBI 展示需求。

## 设计原则

1. **面向 BI 展示优化**：字段命名业务化，便于 QuickBI 直接拖拽展示
2. **口径唯一来源**：所有字段计算逻辑以 `基于DWD层的字段口径定义.md` 为准
3. **StarRocks 规范**：COMMENT 用双引号 `"`、英文括号 `()`、`replication_num="1"`、`compression="LZ4"`、`fast_schema_evolution="true"`、`enable_persistent_index="true"`
4. **Key 列前 N 列**：PRIMARY KEY ≤3 列，Key 列与表结构顺序一致
5. **空值兜底**：数值 `COALESCE(..., 0)`，字符串 `COALESCE(NULLIF(TRIM(...), ''), 'None')`
6. **防除零**：使用 `NULLIF(..., 0)`
7. **显式列名与别名**：INSERT INTO 显式列出目标列，SELECT 每个字段加 `AS alias`
8. **渠道过滤已在 DWS 层完成**：ADS 层无需重复过滤 `channel_code IN ('wd','japan','spanish','germany')`
9. **财务/库存高亮**：涉及金额、库存的字段需人工审查

## 全局口径速记

| 项 | 取值 |
|---|---|
| 品牌过滤 | `brand = '韦德'`（已在 DWS 层过滤） |
| 渠道过滤 | `channel_code IN ('wd', 'japan', 'spanish', 'germany')`（已在 DWS 层过滤） |
| SKU 维度键 | `style_no_size = CONCAT_WS('-', style_no, size)` |
| SKC 维度键 | `style_no` |
| 上市第1天 | `shelf_date`（SKU直接取，SKC取 `MIN(shelf_date)`） |
| 上市第N天 | `lifecycle_day = DATEDIFF(sale_date, shelf_date) + 1` |
| 阶段 ratio | 新品期(1~30)=0.8，热销期(31~120)=1.1，清货期(121~180)=1.0 |
| sale_date_label | 1~180 显示"第N天"，>180 显示 '超周期' |
| sales_phase | 新品期/热销期/清货期/超周期 |
| is_over_cycle | 1（超周期）/ 0（正常周期） |
| 超周期阶段 | 只算日销量/日金额/累计/在仓/可提/可售周期，销售计划全部 NULL |

---

## 一、ADS层整体架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            DWS 汇总层                                   │
│  feishu_dws.dws_sku_product_info_d       (SKU商品维表,日刷新)            │
│  feishu_dws.dws_skc_product_info_d       (SKC商品维表,日刷新)            │
│  feishu_dws.dws_sku_sales_plan_180d_d    (SKU销售计划核心表,日刷新)      │
│  feishu_dws.dws_skc_sales_plan_180d_d    (SKC销售计划核心表,日刷新)      │
│  feishu_dws.dws_sku_abnormal_d           (SKU异常表,日刷新)              │
│  feishu_dws.dws_skc_abnormal_d           (SKC异常表,日刷新)              │
└─────────────────────────────────────────────────────────────────────────┘
                                   │ ETL: JOIN + 字段业务化 + 预计算展示指标
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            ADS 应用层                                   │
│  ┌──────────────────────────────────┐ ┌──────────────────────────────────┐│
│  │ feishu_ads.                      │ │ feishu_ads.                      ││
│  │ ads_sku_sales_plan_180d_d        │ │ ads_skc_sales_plan_180d_d        ││
│  │ SKU维度1~180天销售计划(核心表)   │ │ SKC维度1~180天销售计划(核心表)   ││
│  │ 粒度: style_no_size + sale_date  │ │ 粒度: style_no + sale_date       ││
│  └──────────────────────────────────┘ └──────────────────────────────────┘│
│  ┌──────────────────────────────────────────────────────────────────────┐│
│  │ feishu_ads.ads_sku_skc_summary_d                                     ││
│  │ SKU/SKC汇总表(辅助表)                                                ││
│  │ 粒度: dim_type + dim_value                                           ││
│  └──────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                              QuickBI 展示
```

**数据流**：
1. 6 张 DWS 表 → JOIN + 字段业务化 → 3 张 ADS 表
2. 核心表（`ads_sku_sales_plan_180d_d` / `ads_skc_sales_plan_180d_d`）：基于销售计划核心表 JOIN 商品维表，补充商品属性 + 预计算昨日/今日/7天/30天达成指标
3. 汇总表（`ads_sku_skc_summary_d`）：UNION ALL SKU 与 SKC 商品维表，提供不区分日期的汇总视图

---

## 二、ADS层表清单

| 表名 | 中文名 | 粒度 | 来源 | 模型 | 刷新 | 用途 |
|------|--------|------|------|------|------|------|
| `feishu_ads.ads_sku_sales_plan_180d_d` | SKU维度1~180天销售计划表 | style_no_size + sale_date | dws_sku_sales_plan_180d_d + dws_sku_product_info_d | PRIMARY KEY | 日刷新 | QuickBI展示SKU维度逐日销售计划 |
| `feishu_ads.ads_skc_sales_plan_180d_d` | SKC维度1~180天销售计划表 | style_no + sale_date | dws_skc_sales_plan_180d_d + dws_skc_product_info_d | PRIMARY KEY | 日刷新 | QuickBI展示SKC维度逐日销售计划 |
| `feishu_ads.ads_sku_skc_summary_d` | SKU/SKC汇总表 | dim_type + dim_value | dws_sku_product_info_d + dws_skc_product_info_d + dws_sku/skc_sales_plan_180d_d | PRIMARY KEY | 日刷新 | QuickBI展示SKU/SKC汇总信息 |

---

## 三、关键设计说明

### 3.1 ADS 层如何对齐 QuickBI 展示需求

| QuickBI 展示需求 | ADS 字段 | 数据来源 | 口径章节 |
|-----------------|---------|---------|---------|
| 1~180天销售计划(前) | `plan_pre` | DWS sales_plan.plan_pre | 4.3 / 6.3 |
| 1~180天销售计划(后) | `plan_post` | DWS sales_plan.plan_post | 4.4 / 6.4 |
| 1~180天实际销售 | `daily_qty` | DWS sales_plan.actual_qty | 4.5 / 6.5 |
| 1~180天达成情况 | `achievement_rate` | DWS sales_plan.achievement_rate | 4.6 / 6.6 |
| 累计销量 | `cum_qty` | DWS sales_plan.cum_actual + actual_qty | 3.16 / 5.16 |
| 累计金额 | `cum_amt` | DWS sales_plan.cum_actual_amt + actual_amt | 3.17 / 5.17 |
| 日销量 | `daily_qty` | DWS sales_plan.actual_qty | 3.14 / 5.14 |
| 日金额 | `daily_amt` | DWS sales_plan.actual_amt | 3.15 / 5.15 |
| 在仓库存 | `inventory_sku` | DWS sales_plan.inventory_sku | 3.9 / 5.9 |
| 可提库存 | `available_inventory` | DWS sales_plan.available_inventory | 3.10 / 5.10 |
| 可售周期 | `sellable_days` | DWS sales_plan.sellable_days | 3.11 / 5.11 |
| 30天平均日销 | `daily_avg_qty_30d` | DWS product_info.daily_avg_qty_30d | 3.12 / 5.12 |
| 昨日实际销售 | `yesterday_actual_qty` | DWS sales_plan.actual_qty (sale_date=昨日) | 3.21 / 5.21 |
| 昨日销售达成 | `yesterday_achievement` | DWS sales_plan.achievement_rate (sale_date=昨日) | 3.22 / 5.22 |
| 7天销售达成 | `7d_achievement` | 近7天 actual / 近7天 plan_post | 3.23 / 5.23 |
| 30天销售达成 | `30d_achievement` | 近30天 actual / 近30天 plan_post | 3.24 / 5.24 |
| 今日计划销售 | `today_plan_qty` | DWS sales_plan.plan_post (sale_date=今日) | 3.25 / 5.25 |
| 订货数量 | `order_qty` | DWS sales_plan.order_qty | 3.18 / 5.18 |
| 总订货数量 | `total_order_qty` | DWS product_info.total_order_qty | 3.20 / 5.20 |
| 达成比例 | `achievement_ratio` | DWS product_info.achievement_ratio | 3.19 / 5.19 |

### 3.2 sale_date_label 格式化

```sql
-- DWS 中 sale_date_label 为 "1"、"2"、...、"180"、"超周期"
-- ADS 中格式化为 "第1天"、"第2天"、...、"第180天"、"超周期"
CASE WHEN lifecycle_day BETWEEN 1 AND 180
     THEN CONCAT('第', CAST(lifecycle_day AS VARCHAR), '天')
     ELSE '超周期'
END AS sale_date_label
```

### 3.3 is_over_cycle 标记

```sql
-- 1 = 超周期（lifecycle_day > 180），0 = 正常周期
CASE WHEN lifecycle_day > 180 THEN 1 ELSE 0 END AS is_over_cycle
```

### 3.4 昨日/今日/7天/30天指标计算（当前快照）

这些指标是"当前状态"快照，对同一个 SKU/SKC 的所有行值相同，通过子查询 + LEFT JOIN 广播到每一行：

```sql
-- 昨日指标：sale_date = DATE_SUB(CURRENT_DATE(), 1)
-- 今日计划：sale_date = CURRENT_DATE()，超周期则为0
-- 7天达成：近7天（含昨日）实际销量 / 近7天计划(后)之和
-- 30天达成：近30天（含昨日）实际销量 / 近30天计划(后)之和
```

### 3.5 cum_qty / cum_amt 计算

DWS 中 `cum_actual` 为"截至第 N-1 天的累计"，ADS 中 `cum_qty` 为"截至当天 N 的累计"（含当天）：

```sql
-- cum_qty = 截至当天的累计销量 = cum_actual(N-1) + actual_qty(N)
COALESCE(sp.cum_actual, 0) + COALESCE(sp.actual_qty, 0) AS cum_qty
-- cum_amt 同理
COALESCE(sp.cum_actual_amt, 0) + COALESCE(sp.actual_amt, 0) AS cum_amt
```

---

## 四、ADS表1：SKU维度1~180天销售计划表 `ads_sku_sales_plan_180d_d`

> 用途：QuickBI 直接连接展示 SKU 维度的 1~180 天销售计划（核心表）
> 粒度：`style_no_size + sale_date`（一行一个SKU的一天）
> 来源：`feishu_dws.dws_sku_sales_plan_180d_d` + `feishu_dws.dws_sku_product_info_d`
> 超周期(>180天)：plan_pre/plan_post/achievement_rate = NULL，只展示实际销售和库存

### 4.1 DDL

```sql
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

### 4.2 ETL

```sql
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
    achievement_rate, inventory_sku, available_inventory, daily_avg_qty_30d,
    sellable_days, yesterday_actual_qty, yesterday_achievement,
    `7d_achievement`, `30d_achievement`, today_plan_qty,
    order_qty, total_order_qty, achievement_ratio,
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
    sp.sync_time                                             AS sync_time,
    CURRENT_TIMESTAMP()                                      AS insert_date,
    CURRENT_TIMESTAMP()                                      AS update_date
FROM feishu_dws.dws_sku_sales_plan_180d_d sp
LEFT JOIN product_info pi   ON sp.style_no_size = pi.style_no_size
LEFT JOIN current_metrics cm ON sp.style_no_size = cm.style_no_size;
```

### 4.3 验证SQL

```sql
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

---

## 五、ADS表2：SKC维度1~180天销售计划表 `ads_skc_sales_plan_180d_d`

> 用途：QuickBI 直接连接展示 SKC 维度的 1~180 天销售计划（核心表）
> 粒度：`style_no + sale_date`（一行一个SKC的一天）
> 来源：`feishu_dws.dws_skc_sales_plan_180d_d` + `feishu_dws.dws_skc_product_info_d`
> 逻辑同 SKU 表，维度聚合到 style_no，去掉 size 和 color_name，inventory_sku 改为 inventory_skc

### 5.1 DDL

```sql
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

### 5.2 ETL

```sql
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
    cum_qty, cum_amt, achievement_rate, inventory_skc, available_inventory,
    daily_avg_qty_30d, sellable_days, yesterday_actual_qty,
    yesterday_achievement, `7d_achievement`, `30d_achievement`, today_plan_qty,
    order_qty, total_order_qty, achievement_ratio,
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
    sp.sync_time                                             AS sync_time,
    CURRENT_TIMESTAMP()                                      AS insert_date,
    CURRENT_TIMESTAMP()                                      AS update_date
FROM feishu_dws.dws_skc_sales_plan_180d_d sp
LEFT JOIN product_info_skc pi  ON sp.style_no = pi.style_no
LEFT JOIN current_metrics_skc cm ON sp.style_no = cm.style_no;
```

### 5.3 验证SQL

```sql
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

---

## 六、QuickBI 对接说明

### 6.1 数据集配置

| ADS 表 | QuickBI 数据集 | 展示维度 | 主要图表 |
|--------|--------------|---------|---------|
| `ads_sku_sales_plan_180d_d` | SKU销售计划 | style_no_size, sale_date | 折线图（计划vs实际）、柱状图（达成率）、明细表 |
| `ads_skc_sales_plan_180d_d` | SKC销售计划 | style_no, sale_date | 同上 |

### 6.2 字段使用建议

#### 6.2.1 维度字段（用于筛选/分组）

| 字段 | 用途 | 说明 |
|------|------|------|
| `style_no_size` / `style_no` | 主维度 | SKU/SKC 编码 |
| `sale_date` | 时间维度 | 销售日期，支持日期范围筛选 |
| `lifecycle_day` | 数值维度 | 上市第N天，支持1~180范围筛选 |
| `sale_date_label` | 文本维度 | "第N天"/"超周期"，便于展示 |
| `sales_phase` | 文本维度 | 新品期/热销期/清货期/超周期 |
| `brand` | 文本维度 | 品牌（当前固定为'韦德'） |
| `ip` / `series` / `category` | 文本维度 | 商品属性分组 |
| `is_over_cycle` | 数值维度 | 0=正常周期, 1=超周期 |

#### 6.2.2 度量字段（用于聚合/计算）

| 字段 | 聚合方式 | 说明 |
|------|---------|------|
| `plan_pre` / `plan_post` | SUM | 销售计划(前/后) |
| `daily_qty` | SUM | 日销量 |
| `daily_amt` | SUM | 日金额 |
| `cum_qty` / `cum_amt` | MAX | 累计（取最大值，因同一日期对同一SKU只有一行） |
| `achievement_rate` | AVG | 达成情况 |
| `inventory_sku` / `available_inventory` | MAX | 库存（取最新值） |
| `yesterday_actual_qty` | MAX | 昨日实际（快照，取最大值） |
| `today_plan_qty` | MAX | 今日计划（快照） |

#### 6.2.3 典型图表配置

**图表1：1~180天销售计划vs实际（折线图）**
- X轴：`lifecycle_day`（1~180）
- Y轴：`plan_pre`（SUM）、`plan_post`（SUM）、`daily_qty`（SUM）
- 筛选：`is_over_cycle = 0`、`style_no_size = [选择]`

**图表2：达成率趋势（柱状图）**
- X轴：`sale_date_label`
- Y轴：`achievement_rate`（AVG）
- 筛选：`lifecycle_day BETWEEN 1 AND 180`

**图表3：SKU销售汇总（明细表）**
- 数据源：`ads_sku_skc_summary_d`
- 维度：`dim_value`、`product_name`、`sales_cycle_label`
- 度量：`cum_qty`、`cum_amt`、`achievement_ratio`、`sellable_days`
- 筛选：`dim_type = 'SKU'`

**图表4：当前达成看板（仪表盘）**
- 数据源：`ads_sku_skc_summary_d`
- 度量：`yesterday_actual_qty`（SUM）、`today_plan_qty`（SUM）
- 筛选：`dim_type = 'SKU'` 或 `'SKC'`

### 6.3 QuickBI 注意事项

1. **超周期数据处理**：展示1~180天计划时，筛选 `is_over_cycle = 0` 或 `lifecycle_day BETWEEN 1 AND 180`
2. **累计指标**：`cum_qty` / `cum_amt` 在时间序列中随日期递增，展示时取对应日期的值即可
3. **昨日/今日指标**：这些是当前快照，对同一SKU/SKC所有行值相同，展示时用 MAX 聚合
4. **7天/30天达成**：同理为当前快照，用 MAX 聚合
5. **金额字段精度**：`DECIMAL(18,6)`，QuickBI 展示时建议格式化为2位小数
6. **日期字段**：`sale_date` 为 DATE 类型，QuickBI 自动识别为日期维度

---

## 七、关键业务规则速查

### 7.1 渠道与品牌过滤

| 场景 | 条件 | 说明 |
|------|------|------|
| 品牌 | `brand = '韦德'` | 已在 DWS 层过滤 |
| 渠道 | `channel_code IN ('wd', 'japan', 'spanish', 'germany')` | 已在 DWS 层过滤 |

> **ADS 层无需重复过滤渠道条件**

### 7.2 维度键

| 维度 | 键 | ADS 表 |
|------|-----|--------|
| SKU | `style_no_size` | ads_sku_sales_plan_180d_d |
| SKC | `style_no` | ads_skc_sales_plan_180d_d |
| 混合 | `dim_type + dim_value` | ads_sku_skc_summary_d |

### 7.3 时间基准

| 字段 | SKU | SKC |
|------|-----|-----|
| 上架日期 | `shelf_date`（补全后） | `MIN(shelf_date)`（补全后） |
| 上市第N天 | `DATEDIFF(sale_date, shelf_date) + 1` | `DATEDIFF(sale_date, MIN(shelf_date)) + 1` |
| 已售天数 | `N - 1`（排除今天） | `N - 1` |

### 7.4 阶段与比例

| 阶段 | lifecycle_day | ratio | sales_phase |
|------|--------------|-------|-------------|
| 新品期 | 1~30 | 0.8 | 新品期 |
| 热销期 | 31~120 | 1.1 | 热销期 |
| 清货期 | 121~180 | 1.0 | 清货期 |
| 超周期 | >180 | NULL | 超周期 |

### 7.5 销售计划公式

| 指标 | 公式 | 适用 | ADS 字段 |
|------|------|------|---------|
| plan_pre | `Q * ratio / 180` | 1~180天 | `plan_pre` |
| plan_post | `(Q - cum_actual) * ratio / (181 - N)` | 1~180天 | `plan_post` |
| actual_qty | `第N天 SUM(qty)` | 全部 | `daily_qty` |
| achievement | `actual_qty / plan_post` | 1~180天 | `achievement_rate` |

> **cum_actual(N)** = 截至第 **N-1** 天的实际销量总和（不含当天N），来自 DWS 层
> **cum_qty** (ADS) = `cum_actual + actual_qty` = 截至第 **N** 天的累计（含当天）

### 7.6 sale_date_label 格式

| lifecycle_day | sale_date_label |
|--------------|-----------------|
| 1 | 第1天 |
| 30 | 第30天 |
| 180 | 第180天 |
| >180 | 超周期 |

### 7.7 库存口径

| 字段 | SKU | SKC | ADS 字段 |
|------|-----|-----|---------|
| 在仓库存 | `COALESCE(inventory_sku, 0)` | `SUM(inventory_sku)` | `inventory_sku` / `inventory_skc` |
| 可提库存 | 最新 `inventory_date` 按 sku 聚合 | 最新 `inventory_date` 按 style_no 聚合 | `available_inventory` |
| 可售周期 | 在仓库存 / 30天平均日销 | 同 SKU | `sellable_days` |

### 7.8 当前快照指标

| 指标 | 口径 | ADS 字段 | 聚合方式 |
|------|------|---------|---------|
| 昨日实际销售 | `SUM(qty) WHERE sale_date = 昨日` | `yesterday_actual_qty` | MAX（快照） |
| 昨日达成 | `昨日实际 / 昨日计划(后)` | `yesterday_achievement` | MAX（快照） |
| 7天达成 | `近7天实际 / 近7天计划(后)` | `7d_achievement` | MAX（快照） |
| 30天达成 | `近30天实际 / 近30天计划(后)` | `30d_achievement` | MAX（快照） |
| 今日计划 | `今天的 plan_post`，超周期为0 | `today_plan_qty` | MAX（快照） |

> **快照指标说明**：这些指标反映"当前状态"，对同一 SKU/SKC 的所有行值相同，通过子查询 + JOIN 广播到每一行。

### 7.9 ⚠️ 财务/库存人工审查提醒

以下字段涉及财务金额或库存数据，**上线前必须人工审查**：

1. **`daily_amt` / `cum_amt`**：销售金额，依赖 DWS 层 `actual_amt` / `cum_actual_amt`，需确认金额单位（元）与精度（DECIMAL(18,6)）
2. **`tag_price`**：吊牌价，需确认是否含税
3. **`inventory_sku` / `inventory_skc` / `available_inventory`**：在仓库存与可提库存来自不同数据源（商品库 vs 品牌方库存表），需确认两者口径一致
4. **`total_order_qty`**：涉及补货数量，需确认 `is_replenish` 字段的取值规范（'是'/'否'）
5. **`sellable_days`**：可售周期依赖 30天平均日销，当日销为0时返回 NULL，需确认业务上是否需要兜底值
6. **`achievement_ratio` / `7d_achievement` / `30d_achievement`**：达成率指标，分母为0时返回 NULL，需确认业务展示逻辑

### 7.10 字段映射总表（ADS ← DWS ← 口径）

| ADS 字段 | DWS 来源 | 口径章节 | 说明 |
|---------|---------|---------|------|
| style_no_size | dws_sku_sales_plan_180d_d | 3.1 | SKU = CONCAT_WS('-', style_no, size) |
| style_no | dws_sku/skc_sales_plan_180d_d | 5.1 | SKC = style_no |
| sale_date | dws_sku/skc_sales_plan_180d_d | 4.1/6.1 | 销售日期 |
| lifecycle_day | dws_sku/skc_sales_plan_180d_d | 4.1/6.1 | 上市第N天 |
| sale_date_label | 计算 | 4.1/6.1 | 第N天/超周期 |
| sales_phase | 计算 | 4.2/6.2 | 新品期/热销期/清货期/超周期 |
| is_over_cycle | 计算 | 4.2/6.2 | 1=超周期, 0=正常 |
| brand | dws_sku/skc_sales_plan_180d_d | 3.2/5.2 | 品牌 |
| ip | dws_sku/skc_product_info_d | 3.4/5.4 | IP |
| series | dws_sku/skc_product_info_d | 3.3/5.3 | 系列 |
| shelf_date | dws_sku/skc_sales_plan_180d_d | 3.5/5.5 | 上架日期 |
| first_sales_date | dws_sku/skc_product_info_d | 3.6/5.6 | 首次销售日期 |
| plan_pre | dws_sku/skc_sales_plan_180d_d | 4.3/6.3 | 销售计划(前) |
| plan_post | dws_sku/skc_sales_plan_180d_d | 4.4/6.4 | 销售计划(后) |
| daily_qty | dws_sku/skc_sales_plan_180d_d.actual_qty | 3.14/5.14 | 日销量 |
| daily_amt | dws_sku/skc_sales_plan_180d_d.actual_amt | 3.15/5.15 | 日金额 |
| cum_qty | dws cum_actual + actual_qty | 3.16/5.16 | 累计销量 |
| cum_amt | dws cum_actual_amt + actual_amt | 3.17/5.17 | 累计金额 |
| achievement_rate | dws_sku/skc_sales_plan_180d_d | 4.6/6.6 | 达成情况 |
| inventory_sku/skc | dws_sku/skc_sales_plan_180d_d | 3.9/5.9 | 在仓库存 |
| available_inventory | dws_sku/skc_sales_plan_180d_d | 3.10/5.10 | 可提库存 |
| daily_avg_qty_30d | dws_sku/skc_product_info_d | 3.12/5.12 | 30天平均日销 |
| sellable_days | dws_sku/skc_sales_plan_180d_d | 3.11/5.11 | 可售周期 |
| yesterday_actual_qty | 计算（sale_date=昨日） | 3.21/5.21 | 昨日实际销售 |
| yesterday_achievement | 计算（sale_date=昨日） | 3.22/5.22 | 昨日达成 |
| 7d_achievement | 计算（近7天） | 3.23/5.23 | 7天达成 |
| 30d_achievement | 计算（近30天） | 3.24/5.24 | 30天达成 |
| today_plan_qty | 计算（sale_date=今日） | 3.25/5.25 | 今日计划 |
| order_qty | dws_sku/skc_sales_plan_180d_d | 3.18/5.18 | 订货数量Q |
| total_order_qty | dws_sku/skc_product_info_d | 3.20/5.20 | 总订货数量 |
| achievement_ratio | dws_sku/skc_product_info_d | 3.19/5.19 | 达成比例 |

---

## 八、部署与调度建议

### 8.1 执行顺序

```
1. ads_sku_sales_plan_180d_d   （依赖 dws_sku_sales_plan_180d_d + dws_sku_product_info_d）
2. ads_skc_sales_plan_180d_d   （依赖 dws_skc_sales_plan_180d_d + dws_skc_product_info_d）
```

> **前置依赖**：DWS 层 6 张表必须全部刷新完成

### 8.2 刷新策略

| 表 | 刷新方式 | 说明 |
|----|---------|------|
| ads_sku_sales_plan_180d_d | 全量 TRUNCATE + INSERT | 每日全量重算，数据量大 |
| ads_skc_sales_plan_180d_d | 全量 TRUNCATE + INSERT | 每日全量重算 |

### 8.3 性能优化建议

1. **核心表数据量大**：SKU数 × 天数（180+超周期），建议按 `sale_date` 分区查询
2. **JOIN 优化**：ADS 表主要 JOIN 商品维表（小表），使用 BROADCAST JOIN
3. **索引**：`bloom_filter_columns` 可对 `style_no`、`style_no_size` 加 Bloom Filter 加速等值查询
4. **Colocate Join**：ADS 表与 DWS 表可配置 `colocate_with` 同组，加速关联
5. **分区裁剪**：QuickBI 查询时带 `sale_date` 条件，自动触发分区裁剪

---

## 九、附录：StarRocks 语法兼容性说明

### 9.1 反引号转义

`7d_achievement` / `30d_achievement` 以数字开头，在 SQL 中必须用反引号包裹：

```sql
-- DDL 中字段定义
`7d_achievement`    DECIMAL(18,6)   COMMENT "7天销售达成情况"
`30d_achievement`   DECIMAL(18,6)   COMMENT "30天销售达成情况"

-- INSERT 和 SELECT 中引用
INSERT INTO ... (`7d_achievement`, `30d_achievement`, ...)
SELECT ... AS `7d_achievement`, ... AS `30d_achievement`
```

### 9.2 日期函数

```sql
DATE_SUB(CURRENT_DATE(), 1)          -- 昨日
DATE_SUB(CURRENT_DATE(), 7)          -- 7天前
CURRENT_DATE()                       -- 今日
DATEDIFF(end_date, start_date)       -- 日期差（天数）
```

### 9.3 空值处理

```sql
COALESCE(col, 0)                     -- 数值空值兜底0
COALESCE(NULLIF(TRIM(col), ''), 'None')  -- 字符串空值兜底None
NULLIF(col, 0)                       -- 防除零
```

---

> **文档结束**
> 本文档严格依据 `基于DWD层的字段口径定义.md` 和 `DWS.md` 生成，所有计算逻辑以口径文档为准。
> ADS 层以 SELECT + JOIN 为主，不做复杂计算，重点在于字段业务化命名和 QuickBI 展示优化。
> 涉及财务金额、库存的字段已标注人工审查提醒，上线前请业务方确认。
