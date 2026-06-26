# 数仓架构设计方案：从飞书分表到ADS宽表

## 一、整体架构概览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              QuickBI 展示层                                  │
│  ┌────────────┐  ┌──────────┐  ┌────────────┐  ┌────────────┐            │
│  │  交叉表    │  │ 指标卡   │  │ 趋势图     │  │ 筛选面板   │            │
│  │ SKC×180天  │  │ KPI汇总  │  │ 计划vs实际 │  │ 多维度下钻 │            │
│  └────────────┘  └──────────┘  └────────────┘  └────────────┘            │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ 直连/数据集
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ADS 应用数据层                                │
│  ┌────────────────────┐  ┌────────────────────┐  ┌──────────────────┐    │
│  │ ads_skc_base_info  │  │ ads_skc_daily_plan │  │ vw_skc_analysis  │    │
│  │ SKC基础信息        │  │ 180天日计划窄表    │  │ 物化视图(宽表)   │    │
│  └────────────────────┘  └────────────────────┘  └──────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ ETL-3
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DWS 汇总数据层                                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │dws_skc_daily │ │dws_skc_cumu- │ │dws_skc_life- │ │dws_skc_plan  │       │
│  │_sales       │ │lative         │ │cycle         │ │              │       │
│  │日销售汇总    │ │累计指标       │ │生命周期标签  │ │180天计划     │       │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ ETL-2
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DWD 明细数据层                                │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐       │
│  │dwd_sales_all │ │dwd_product_  │ │dwd_inventory │ │dwd_otb_clean │       │
│  │统一销售明细  │ │all统一商品库  │ │清洗库存表    │ │清洗OTB表     │       │
│  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ ETL-1
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ODS 原始数据层                                │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐           │
│  │t_361sales_ │  │wd_sales_   │  │wd_pinpai-  │  │wd_shop /   │           │
│  │01~50       │  │01~50       │  │kucun       │  │t_361_shop  │           │
│  │50张分表    │  │50张分表    │  │品牌库存    │  │商品库      │           │
│  └────────────┘  └────────────┘  └────────────┘  └────────────┘           │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │  wd_otb (OTB表)                                                    │   │
│  └────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 二、各层详细设计

### 2.1 ODS层（已完成）

| 表名 | 说明 | 数据量 |
|------|------|--------|
| `t_361sales_01` ~ `t_361sales_50` | 361品牌日销售，50张分表 | ~50万行/表 |
| `wd_sales_01` ~ `wd_sales_50` | 韦德品牌日销售，50张分表 | ~50万行/表 |
| `wd_pinpaikucun` | 品牌方库存表 | ~10万行 |
| `wd_shop` | 韦德商品库 | ~5万行 |
| `t_361_shop` | 361商品库 | ~5万行 |
| `wd_otb` | OTB订货计划 | ~1千行 |

**痛点**：飞书5万行限制导致分表，需按品牌+SKU维度合并。

---

### 2.2 DWD层：明细数据层（清洗+合并+标准化）

#### 2.2.1 分表合并：50张销售表 → 1张统一表

```sql
-- ============================================
-- DWD-1: 合并361销售分表
-- ============================================
DROP TABLE IF EXISTS dwd_sales_361;
CREATE TABLE dwd_sales_361 AS
SELECT 
    '361' AS brand,
    SKU,
    销售日期 AS sales_date,
    `361sport-销量` AS qty_361sport,
    `中国公司(361°客户)-销量` AS qty_china_company,
    `361°寄样-销量` AS qty_sample,
    `员工内购（香港）-销量` AS qty_staff,
    `361sport-金额` AS amt_361sport,
    `中国公司(361°客户)-金额` AS amt_china_company,
    `361°寄样-金额` AS amt_sample,
    `员工内购（香港）-金额` AS amt_staff,
    sync_time
FROM t_361sales_01
UNION ALL
SELECT '361', SKU, 销售日期, `361sport-销量`, `中国公司(361°客户)-销量`, `361°寄样-销量`, `员工内购（香港）-销量`,
       `361sport-金额`, `中国公司(361°客户)-金额`, `361°寄样-金额`, `员工内购（香港）-金额`, sync_time
FROM t_361sales_02
-- ... UNION ALL t_361sales_03 ~ t_361sales_50
UNION ALL
SELECT '361', SKU, 销售日期, `361sport-销量`, `中国公司(361°客户)-销量`, `361°寄样-销量`, `员工内购（香港）-销量`,
       `361sport-金额`, `中国公司(361°客户)-金额`, `361°寄样-金额`, `员工内购（香港）-金额`, sync_time
FROM t_361sales_50;

-- 添加索引
CREATE INDEX idx_dwd_sales_361_sku_date ON dwd_sales_361(SKU, sales_date);
CREATE INDEX idx_dwd_sales_361_date ON dwd_sales_361(sales_date);

-- ============================================
-- DWD-2: 合并韦德销售分表
-- ============================================
DROP TABLE IF EXISTS dwd_sales_wd;
CREATE TABLE dwd_sales_wd AS
SELECT 
    '韦德' AS brand,
    SKU,
    销售日期 AS sales_date,
    `韦德之道-销量` AS qty_wd,
    `韦德之道寄样-销量` AS qty_wd_sample,
    `得物APP_韦德-销量` AS qty_dewu,
    `韦德之道-得物寄售-销量` AS qty_dewu_consignment,
    `得物APP转寄_95分-销量` AS qty_95fen,
    `广东炫动商贸有限公司(李宁客户)-销量` AS qty_guangdong,
    `全勇分销-销量` AS qty_quanyong,
    `应科迪_客户-销量` AS qty_yingkedi,
    `韦德线下店铺-销量` AS qty_offline,
    `韦德日本站-销量` AS qty_japan,
    `韦德西语站-销量` AS qty_spanish,
    `dw_韦德伟宏店-销量` AS qty_weihong,
    `韦德_95分店-销量` AS qty_95fen_shop,
    `拼多多_博耶运动户外专营店-销量` AS qty_pdd,
    `eBay-销量` AS qty_ebay,
    `韦德之道--招待费-销量` AS qty_entertainment,
    `韦德德国站-销量` AS qty_germany,
    `韦德之道B2B-销量` AS qty_b2b,
    `韦德之道-金额` AS amt_wd,
    `韦德之道寄样-金额` AS amt_wd_sample,
    `得物APP_韦德-金额` AS amt_dewu,
    `韦德之道-得物寄售-金额` AS amt_dewu_consignment,
    `得物APP转寄_95分-金额` AS amt_95fen,
    `广东炫动商贸有限公司(李宁客户)-金额` AS amt_guangdong,
    `全勇分销-金额` AS amt_quanyong,
    `应科迪_客户-金额` AS amt_yingkedi,
    `韦德线下店铺-金额` AS amt_offline,
    `韦德日本站-金额` AS amt_japan,
    `韦德西语站-金额` AS amt_spanish,
    `dw_韦德伟宏店-金额` AS amt_weihong,
    `韦德_95分店-金额` AS amt_95fen_shop,
    `拼多多_博耶运动户外专营店-金额` AS amt_pdd,
    `eBay-金额` AS amt_ebay,
    `韦德之道--招待费-金额` AS amt_entertainment,
    `韦德德国站-金额` AS amt_germany,
    `韦德之道B2B-金额` AS amt_b2b,
    sync_time
FROM wd_sales_01
UNION ALL SELECT ... FROM wd_sales_02
-- ... UNION ALL wd_sales_03 ~ wd_sales_50
UNION ALL SELECT ... FROM wd_sales_50;

CREATE INDEX idx_dwd_sales_wd_sku_date ON dwd_sales_wd(SKU, sales_date);
CREATE INDEX idx_dwd_sales_wd_date ON dwd_sales_wd(sales_date);

-- ============================================
-- DWD-3: 统一销售表（361 + 韦德）
-- ============================================
DROP TABLE IF EXISTS dwd_sales_all;
CREATE TABLE dwd_sales_all AS
SELECT 
    brand, SKU, sales_date,
    COALESCE(qty_361sport, 0) + COALESCE(qty_china_company, 0) + COALESCE(qty_sample, 0) + COALESCE(qty_staff, 0) AS total_qty,
    COALESCE(amt_361sport, 0) + COALESCE(amt_china_company, 0) + COALESCE(amt_sample, 0) + COALESCE(amt_staff, 0) AS total_amt,
    sync_time
FROM dwd_sales_361
UNION ALL
SELECT 
    brand, SKU, sales_date,
    COALESCE(qty_wd, 0) + COALESCE(qty_wd_sample, 0) + COALESCE(qty_dewu, 0) + COALESCE(qty_dewu_consignment, 0)
    + COALESCE(qty_95fen, 0) + COALESCE(qty_guangdong, 0) + COALESCE(qty_quanyong, 0) + COALESCE(qty_yingkedi, 0)
    + COALESCE(qty_offline, 0) + COALESCE(qty_japan, 0) + COALESCE(qty_spanish, 0) + COALESCE(qty_weihong, 0)
    + COALESCE(qty_95fen_shop, 0) + COALESCE(qty_pdd, 0) + COALESCE(qty_ebay, 0) + COALESCE(qty_entertainment, 0)
    + COALESCE(qty_germany, 0) + COALESCE(qty_b2b, 0) AS total_qty,
    COALESCE(amt_wd, 0) + COALESCE(amt_wd_sample, 0) + COALESCE(amt_dewu, 0) + COALESCE(amt_dewu_consignment, 0)
    + COALESCE(amt_95fen, 0) + COALESCE(amt_guangdong, 0) + COALESCE(amt_quanyong, 0) + COALESCE(amt_yingkedi, 0)
    + COALESCE(amt_offline, 0) + COALESCE(amt_japan, 0) + COALESCE(amt_spanish, 0) + COALESCE(amt_weihong, 0)
    + COALESCE(amt_95fen_shop, 0) + COALESCE(amt_pdd, 0) + COALESCE(amt_ebay, 0) + COALESCE(amt_entertainment, 0)
    + COALESCE(amt_germany, 0) + COALESCE(amt_b2b, 0) AS total_amt,
    sync_time
FROM dwd_sales_wd;

CREATE INDEX idx_dwd_sales_all_sku ON dwd_sales_all(SKU);
CREATE INDEX idx_dwd_sales_all_date ON dwd_sales_all(sales_date);
```

#### 2.2.2 商品库清洗与标准化

```sql
-- ============================================
-- DWD-4: 清洗韦德商品库，提取SKC维度
-- ============================================
DROP TABLE IF EXISTS dwd_product_wd;
CREATE TABLE dwd_product_wd AS
SELECT 
    '韦德' AS brand,
    IP,
    系列 AS series,
    配色名 AS color_name,
    款号 AS style_no,
    SKU,
    首次可提日期 AS first_available_date,
    首次提货日期 AS first_pickup_date,
    上架日期 AS shelf_date,
    首次销售日期 AS first_sales_date,
    销售周期标签 AS lifecycle_label,
    首次订货季度 AS first_order_quarter,
    年份 AS year,
    折扣 AS discount,
    吊牌价 AS tag_price,
    订货数量_sku AS order_qty_sku,
    订货数量_SKC AS order_qty_skc,
    销售周期天数 AS sales_cycle_days,
    销售目标_日 AS daily_target,
    销售目标_周 AS weekly_target,
    销售目标_月 AS monthly_target,
    销售目标_季 AS quarterly_target,
    库存数量_SKU AS inventory_sku,
    库存数量_SKC AS inventory_skc,
    销售累计数量_SKU AS cum_sales_sku,
    销售累计数量_SKC AS cum_sales_skc,
    SKC达成率 AS skc_achievement_rate,
    实际售卖天数 AS actual_sales_days,
    实际日均销量 AS actual_daily_avg,
    补货量 AS replenishment_qty,
    周转天数 AS turnover_days,
    sync_time
FROM wd_shop
WHERE SKU IS NOT NULL AND 款号 IS NOT NULL;

-- ============================================
-- DWD-5: 清洗361商品库，提取SKC维度
-- ============================================
DROP TABLE IF EXISTS dwd_product_361;
CREATE TABLE dwd_product_361 AS
SELECT 
    '361' AS brand,
    IP,
    系列 AS series,
    商品名称 AS product_name,
    商品货号 AS style_no,
    SKU,
    首次订货到货季度 AS first_order_quarter,
    吊牌价 AS tag_price,
    订货日期 AS order_date,
    预计到货月份 AS est_arrival_month,
    预计到货日期 AS est_arrival_date,
    计划提货日期 AS planned_pickup_date,
    首次提货日期 AS first_pickup_date,
    预计上架月份 AS est_shelf_month,
    海外预计上架时间 AS overseas_shelf_date,
    实际上架时间 AS actual_shelf_date,
    订货数量 AS order_qty,
    已提数量 AS picked_qty,
    未提可提数量 AS unpicked_qty,
    sync_time
FROM t_361_shop
WHERE SKU IS NOT NULL AND 商品货号 IS NOT NULL;

-- ============================================
-- DWD-6: 统一商品库（SKC粒度）
-- ============================================
DROP TABLE IF EXISTS dwd_product_all;
CREATE TABLE dwd_product_all AS
SELECT 
    brand,
    style_no AS skc,
    SKU,
    IP,
    series,
    COALESCE(shelf_date, actual_shelf_date, first_pickup_date) AS shelf_date,
    tag_price,
    COALESCE(order_qty_skc, order_qty, 0) AS order_qty,
    first_order_quarter,
    year,
    sync_time
FROM dwd_product_wd
UNION ALL
SELECT 
    brand,
    style_no AS skc,
    SKU,
    IP,
    series,
    COALESCE(actual_shelf_date, planned_pickup_date, order_date) AS shelf_date,
    tag_price,
    COALESCE(order_qty, 0) AS order_qty,
    first_order_quarter,
    YEAR(COALESCE(order_date, NOW())) AS year,
    sync_time
FROM dwd_product_361;

CREATE INDEX idx_dwd_product_skc ON dwd_product_all(skc);
CREATE INDEX idx_dwd_product_sku ON dwd_product_all(SKU);

-- ============================================
-- DWD-7: 清洗库存表
-- ============================================
DROP TABLE IF EXISTS dwd_inventory;
CREATE TABLE dwd_inventory AS
SELECT 
    sku,
    品牌方库存更新日期 AS inventory_date,
    季度 AS quarter,
    IP,
    品名 AS product_name,
    系列 AS series,
    配色名 AS color_name,
    商品类别 AS category,
    款号 AS style_no,
    尺码 AS size,
    库存数量 AS inventory_qty,
    含税单价 AS price_with_tax,
    订货数量 AS order_qty,
    已提数量 AS picked_qty,
    未提数量 AS unpicked_qty,
    吊牌价 AS tag_price,
    sync_time
FROM wd_pinpaikucun
WHERE sku IS NOT NULL;

CREATE INDEX idx_dwd_inventory_sku ON dwd_inventory(sku);
CREATE INDEX idx_dwd_inventory_style ON dwd_inventory(style_no);
```

---

### 2.3 DWS层：汇总数据层（SKC粒度 + 时间窗口计算）

#### 2.3.1 DWS-1: SKC日销售汇总

```sql
-- ============================================
-- DWS-1: SKC日销售汇总（关联商品库获取上架日期）
-- ============================================
DROP TABLE IF EXISTS dws_skc_daily_sales;
CREATE TABLE dws_skc_daily_sales AS
SELECT 
    p.brand,
    p.skc,
    p.shelf_date,
    s.sales_date,
    SUM(s.total_qty) AS daily_qty,
    SUM(s.total_amt) AS daily_amt,
    COUNT(DISTINCT s.SKU) AS sku_count
FROM dwd_product_all p
LEFT JOIN dwd_sales_all s ON p.SKU = s.SKU
WHERE s.sales_date IS NOT NULL
GROUP BY p.brand, p.skc, p.shelf_date, s.sales_date;

CREATE INDEX idx_dws_daily_skc ON dws_skc_daily_sales(skc);
CREATE INDEX idx_dws_daily_date ON dws_skc_daily_sales(sales_date);
```

#### 2.3.2 DWS-2: SKC累计指标汇总

```sql
-- ============================================
-- DWS-2: SKC累计指标（累计销量、达成率、昨日/7天/30天达成）
-- ============================================
DROP TABLE IF EXISTS dws_skc_cumulative;
CREATE TABLE dws_skc_cumulative AS
SELECT 
    brand,
    skc,
    shelf_date,
    order_qty,
    -- 累计销量（截至昨天）
    SUM(CASE WHEN sales_date < CURRENT_DATE THEN daily_qty ELSE 0 END) AS cum_sales_qty,
    SUM(CASE WHEN sales_date < CURRENT_DATE THEN daily_amt ELSE 0 END) AS cum_sales_amt,
    -- 达成率
    CASE 
        WHEN order_qty > 0 THEN SUM(CASE WHEN sales_date < CURRENT_DATE THEN daily_qty ELSE 0 END) / order_qty
        ELSE 0 
    END AS achievement_rate,
    -- 昨日销售
    SUM(CASE WHEN sales_date = DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY) THEN daily_qty ELSE 0 END) AS yesterday_sales,
    -- 7天销售
    SUM(CASE WHEN sales_date >= DATE_SUB(CURRENT_DATE, INTERVAL 7 DAY) AND sales_date < CURRENT_DATE THEN daily_qty ELSE 0 END) AS last_7days_sales,
    -- 30天销售
    SUM(CASE WHEN sales_date >= DATE_SUB(CURRENT_DATE, INTERVAL 30 DAY) AND sales_date < CURRENT_DATE THEN daily_qty ELSE 0 END) AS last_30days_sales,
    -- 可售周期（库存/日均销量）
    inv.inventory_qty AS current_inventory,
    CASE 
        WHEN AVG(daily_qty) > 0 THEN inv.inventory_qty / AVG(daily_qty)
        ELSE NULL 
    END AS sellable_days,
    CURRENT_DATE AS calc_date
FROM dws_skc_daily_sales ds
LEFT JOIN (
    SELECT style_no, SUM(inventory_qty) AS inventory_qty 
    FROM dwd_inventory 
    GROUP BY style_no
) inv ON ds.skc = inv.style_no
GROUP BY brand, skc, shelf_date, order_qty, inv.inventory_qty;

CREATE INDEX idx_dws_cum_skc ON dws_skc_cumulative(skc);
```

#### 2.3.3 DWS-3: SKC生命周期标签

```sql
-- ============================================
-- DWS-3: SKC生命周期标签计算
-- ============================================
DROP TABLE IF EXISTS dws_skc_lifecycle;
CREATE TABLE dws_skc_lifecycle AS
SELECT 
    brand,
    skc,
    shelf_date,
    order_qty,
    cum_sales_qty,
    achievement_rate,
    yesterday_sales,
    last_7days_sales,
    last_30days_sales,
    current_inventory,
    sellable_days,
    -- 已上架天数
    DATEDIFF(CURRENT_DATE, shelf_date) AS days_on_shelf,
    -- 生命周期标签
    CASE 
        WHEN DATEDIFF(CURRENT_DATE, shelf_date) <= 30 THEN '新品期'
        WHEN DATEDIFF(CURRENT_DATE, shelf_date) <= 120 THEN '热销期'
        WHEN DATEDIFF(CURRENT_DATE, shelf_date) <= 180 THEN '清货期'
        ELSE '滞销'
    END AS lifecycle_tag,
    -- 阶段占比（假设：新品30%、热销50%、清货20%）
    CASE 
        WHEN DATEDIFF(CURRENT_DATE, shelf_date) <= 30 THEN 0.30
        WHEN DATEDIFF(CURRENT_DATE, shelf_date) <= 120 THEN 0.50
        WHEN DATEDIFF(CURRENT_DATE, shelf_date) <= 180 THEN 0.20
        ELSE 0
    END AS stage_ratio,
    calc_date
FROM dws_skc_cumulative;

CREATE INDEX idx_dws_lifecycle_skc ON dws_skc_lifecycle(skc);
CREATE INDEX idx_dws_lifecycle_tag ON dws_skc_lifecycle(lifecycle_tag);
```

#### 2.3.4 DWS-4: 180天销售计划生成

```sql
-- ============================================
-- DWS-4: 生成180天销售计划（从Day 1到Day 180）
-- ============================================
-- 先生成数字序列表（1-180）
DROP TABLE IF EXISTS dim_day_numbers;
CREATE TABLE dim_day_numbers AS
SELECT 1 AS day_no UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
-- ... 继续到180，或用存储过程/CTE生成
UNION ALL SELECT 180;

-- 生成180天计划
DROP TABLE IF EXISTS dws_skc_sales_plan;
CREATE TABLE dws_skc_sales_plan AS
SELECT 
    l.brand,
    l.skc,
    l.shelf_date,
    l.order_qty,
    l.lifecycle_tag,
    d.day_no,
    -- 日销售计划 = 按生命周期分阶段均摊
    CASE 
        -- 新品期（Day 1-30）：订货量 × 30% ÷ 30天
        WHEN d.day_no <= 30 THEN l.order_qty * 0.30 / 30
        -- 热销期（Day 31-120）：订货量 × 50% ÷ 90天
        WHEN d.day_no <= 120 THEN l.order_qty * 0.50 / 90
        -- 清货期（Day 121-180）：订货量 × 20% ÷ 60天
        WHEN d.day_no <= 180 THEN l.order_qty * 0.20 / 60
        ELSE 0
    END AS daily_plan_qty,
    -- 计划日期 = 上架日期 + day_no - 1
    DATE_ADD(l.shelf_date, INTERVAL (d.day_no - 1) DAY) AS plan_date,
    CURRENT_DATE AS calc_date
FROM dws_skc_lifecycle l
CROSS JOIN dim_day_numbers d
WHERE l.order_qty > 0 AND l.shelf_date IS NOT NULL;

CREATE INDEX idx_dws_plan_skc ON dws_skc_sales_plan(skc);
CREATE INDEX idx_dws_plan_day ON dws_skc_sales_plan(day_no);
```

---

### 2.4 ADS层：应用数据层（面向QuickBI）

#### 方案A：窄表存储（推荐用于数据库存储）

```sql
-- ============================================
-- ADS-1: SKC基础信息表
-- ============================================
DROP TABLE IF EXISTS ads_skc_base_info;
CREATE TABLE ads_skc_base_info (
    brand VARCHAR(50) COMMENT '品牌',
    skc VARCHAR(100) COMMENT 'SKC编码',
    shelf_date DATE COMMENT '上架日期',
    days_on_shelf INT COMMENT '已上架天数',
    lifecycle_tag VARCHAR(20) COMMENT '生命周期标签：新品期/热销期/清货期/滞销',
    current_inventory DECIMAL(18,2) COMMENT '当前库存',
    sellable_days DECIMAL(10,2) COMMENT '可售周期（天）',
    order_qty DECIMAL(18,2) COMMENT '订货数量',
    cum_sales_qty DECIMAL(18,2) COMMENT '累计销量',
    achievement_rate DECIMAL(10,4) COMMENT '达成比例',
    yesterday_sales DECIMAL(18,2) COMMENT '昨日销售',
    last_7days_sales DECIMAL(18,2) COMMENT '7天销售',
    last_30days_sales DECIMAL(18,2) COMMENT '30天销售',
    today_plan_qty DECIMAL(18,2) COMMENT '今日计划销售数量',
    calc_date DATE COMMENT '计算日期',
    PRIMARY KEY (skc),
    INDEX idx_lifecycle (lifecycle_tag),
    INDEX idx_brand (brand),
    INDEX idx_shelf_date (shelf_date)
) COMMENT='SKC基础信息汇总表';

INSERT INTO ads_skc_base_info
SELECT 
    brand, skc, shelf_date, days_on_shelf, lifecycle_tag,
    current_inventory, sellable_days, order_qty, cum_sales_qty,
    achievement_rate, yesterday_sales, last_7days_sales, last_30days_sales,
    -- 今日计划 = 根据当前生命周期阶段计算
    CASE 
        WHEN days_on_shelf <= 30 THEN order_qty * 0.30 / 30
        WHEN days_on_shelf <= 120 THEN order_qty * 0.50 / 90
        WHEN days_on_shelf <= 180 THEN order_qty * 0.20 / 60
        ELSE 0
    END AS today_plan_qty,
    calc_date
FROM dws_skc_lifecycle;

-- ============================================
-- ADS-2: 180天日计划窄表（行存储）
-- ============================================
DROP TABLE IF EXISTS ads_skc_daily_plan;
CREATE TABLE ads_skc_daily_plan (
    brand VARCHAR(50) COMMENT '品牌',
    skc VARCHAR(100) COMMENT 'SKC编码',
    day_no INT COMMENT '天数序号（1-180）',
    plan_type VARCHAR(50) COMMENT '计划类型：销售计划/实际销售/销售计划有销售后',
    plan_qty DECIMAL(18,4) COMMENT '计划数量',
    actual_qty DECIMAL(18,2) COMMENT '实际销售数量',
    plan_date DATE COMMENT '计划日期',
    calc_date DATE COMMENT '计算日期',
    PRIMARY KEY (skc, day_no, plan_type),
    INDEX idx_skc_day (skc, day_no),
    INDEX idx_plan_date (plan_date)
) COMMENT='SKC 180天日销售计划窄表';

-- 插入销售计划（plan_type='销售计划'）
INSERT INTO ads_skc_daily_plan (brand, skc, day_no, plan_type, plan_qty, plan_date, calc_date)
SELECT brand, skc, day_no, '销售计划', daily_plan_qty, plan_date, calc_date
FROM dws_skc_sales_plan;

-- 插入实际销售（plan_type='实际销售'）
INSERT INTO ads_skc_daily_plan (brand, skc, day_no, plan_type, actual_qty, plan_date, calc_date)
SELECT 
    p.brand,
    p.skc,
    DATEDIFF(s.sales_date, p.shelf_date) + 1 AS day_no,
    '实际销售',
    NULL,
    s.daily_qty,
    s.sales_date,
    CURRENT_DATE
FROM dws_skc_daily_sales s
JOIN dws_skc_lifecycle p ON s.skc = p.skc
WHERE DATEDIFF(s.sales_date, p.shelf_date) + 1 BETWEEN 1 AND 180;

-- 插入调整后计划（plan_type='销售计划有销售后'）
-- 根据实际销售情况动态调整后续计划
INSERT INTO ads_skc_daily_plan (brand, skc, day_no, plan_type, plan_qty, plan_date, calc_date)
SELECT 
    brand, skc, day_no, '销售计划有销售后',
    -- 调整逻辑：根据实际销售偏差调整后续日计划
    CASE 
        WHEN day_no <= days_on_shelf THEN daily_plan_qty  -- 已过去天数保持原样
        ELSE daily_plan_qty * (1 + (cum_sales_qty - expected_cum) / NULLIF(expected_cum, 0) * 0.5)
    END AS adjusted_plan,
    plan_date, calc_date
FROM dws_skc_sales_plan sp
JOIN dws_skc_lifecycle l ON sp.skc = l.skc;
```

#### 方案B：宽表存储（兼容Excel 195列格式）

```sql
-- ============================================
-- ADS-3: 180天宽表（与Excel格式一致）
-- ============================================
-- 使用动态SQL生成宽表，或手动定义195列
-- 这里展示核心结构，实际可用存储过程生成

DROP TABLE IF EXISTS ads_skc_sales_plan_wide;
CREATE TABLE ads_skc_sales_plan_wide (
    brand VARCHAR(50),
    skc VARCHAR(100),
    shelf_date DATE,
    days_on_shelf INT,
    lifecycle_tag VARCHAR(20),
    current_inventory DECIMAL(18,2),
    sellable_days DECIMAL(10,2),
    cum_sales_qty DECIMAL(18,2),
    achievement_rate DECIMAL(10,4),
    yesterday_sales DECIMAL(18,2),
    last_7days_sales DECIMAL(18,2),
    last_30days_sales DECIMAL(18,2),
    order_qty DECIMAL(18,2),
    today_plan_qty DECIMAL(18,2),
    plan_type VARCHAR(50),  -- '销售计划' / '实际销售' / '销售计划有销售后'
    -- Day 1 ~ Day 180
    day_001 DECIMAL(18,4), day_002 DECIMAL(18,4), day_003 DECIMAL(18,4),
    -- ... 继续到 day_180
    day_180 DECIMAL(18,4),
    calc_date DATE,
    PRIMARY KEY (skc, plan_type)
);

-- 使用动态SQL将窄表Pivot为宽表
-- MySQL 8.0+ 可用 GROUP BY + MAX(CASE WHEN ...)
-- 或使用 Python Pandas pivot 后写入
```

#### 方案C：物化视图（最佳实践）

```sql
-- ============================================
-- ADS-4: 物化视图（基于窄表动态生成宽表）
-- ============================================
-- MySQL 8.0 不支持物化视图，可用事件定时刷新表
-- PostgreSQL / Oracle 支持 CREATE MATERIALIZED VIEW

-- 创建刷新事件（MySQL）
DELIMITER //
CREATE EVENT IF NOT EXISTS evt_refresh_skc_wide
ON SCHEDULE EVERY 1 DAY STARTS '2026-06-26 03:00:00'
DO
BEGIN
    -- 清空并重新生成宽表
    TRUNCATE TABLE ads_skc_sales_plan_wide;

    -- 使用存储过程或动态SQL将窄表转为宽表
    -- 这里用 Python 脚本在外部执行更高效
END //
DELIMITER ;
```

---

### 2.5 QuickBI 数据集配置

```
【数据集1】ads_skc_base_info
- 直连 MySQL 表
- 维度：brand, skc, lifecycle_tag, shelf_date
- 度量：order_qty, cum_sales_qty, achievement_rate, current_inventory
- 筛选器：品牌、生命周期、上架时间范围

【数据集2】ads_skc_daily_plan（窄表）
- 直连 MySQL 表
- 维度：skc, day_no, plan_type, plan_date
- 度量：plan_qty, actual_qty
- 在QuickBI中使用交叉表：行=skc, 列=day_no, 值=plan_qty
- 按 plan_type 分sheet或添加为筛选器

【数据集3】vw_skc_sales_analysis（视图）
- 创建视图将窄表动态Pivot
- QuickBI直接读取视图
```

---

## 三、Python ETL 脚本（用于分表合并和宽表生成）

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
数仓ETL脚本：从ODS分表到ADS宽表
用于飞书分表合并 + 180天销售计划生成
"""

import pandas as pd
import numpy as np
from sqlalchemy import create_engine
from datetime import datetime, timedelta
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 数据库连接配置
DB_CONFIG = {
    'host': 'your_mysql_host',
    'port': 3306,
    'user': 'your_user',
    'password': 'your_password',
    'database': 'your_database'
}

engine = create_engine(
    f"mysql+pymysql://{DB_CONFIG['user']}:{DB_CONFIG['password']}"
    f"@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}"
)


def merge_sales_tables(table_prefix, brand_name, total_tables=50):
    """合并50张销售分表"""
    logger.info(f"开始合并 {brand_name} 销售分表...")
    dfs = []
    for i in range(1, total_tables + 1):
        table_name = f"{table_prefix}{str(i).zfill(2)}"
        try:
            df = pd.read_sql(f"SELECT * FROM {table_name}", engine)
            df['brand'] = brand_name
            dfs.append(df)
            logger.info(f"  读取 {table_name}: {len(df)} 行")
        except Exception as e:
            logger.warning(f"  读取 {table_name} 失败: {e}")

    merged = pd.concat(dfs, ignore_index=True)
    logger.info(f"{brand_name} 合并完成: {len(merged)} 行")
    return merged


def calculate_lifecycle(shelf_date, current_date=None):
    """计算生命周期标签"""
    if current_date is None:
        current_date = datetime.now().date()

    if shelf_date is None or pd.isna(shelf_date):
        return '未知', 0

    days = (current_date - pd.to_datetime(shelf_date).date()).days

    if days <= 30:
        return '新品期', days
    elif days <= 120:
        return '热销期', days
    elif days <= 180:
        return '清货期', days
    else:
        return '滞销', days


def generate_180_day_plan(skc_row):
    """为单个SKC生成180天销售计划"""
    order_qty = skc_row['order_qty'] or 0
    if order_qty == 0:
        return pd.DataFrame()

    days = list(range(1, 181))
    plans = []

    for day in days:
        if day <= 30:
            # 新品期：30% ÷ 30天
            daily_plan = order_qty * 0.30 / 30
            stage = '新品期'
        elif day <= 120:
            # 热销期：50% ÷ 90天
            daily_plan = order_qty * 0.50 / 90
            stage = '热销期'
        elif day <= 180:
            # 清货期：20% ÷ 60天
            daily_plan = order_qty * 0.20 / 60
            stage = '清货期'
        else:
            daily_plan = 0
            stage = '滞销'

        plans.append({
            'day_no': day,
            'daily_plan': round(daily_plan, 4),
            'stage': stage
        })

    return pd.DataFrame(plans)


def pivot_to_wide(df_narrow, value_col='plan_qty'):
    """将窄表Pivot为宽表（195列格式）"""
    # 基础字段
    base_cols = ['brand', 'skc', 'shelf_date', 'days_on_shelf', 'lifecycle_tag',
                 'current_inventory', 'order_qty', 'cum_sales_qty', 'achievement_rate']

    # Pivot day_no 为列
    wide = df_narrow.pivot_table(
        index=base_cols,
        columns='day_no',
        values=value_col,
        aggfunc='first'
    ).reset_index()

    # 重命名列为 day_001, day_002, ...
    wide.columns = [f'day_{str(c).zfill(3)}' if isinstance(c, int) else c for c in wide.columns]

    return wide


def main_etl():
    """主ETL流程"""
    logger.info("=" * 60)
    logger.info("开始执行 ETL 流程")
    logger.info("=" * 60)

    # Step 1: 合并361销售分表
    df_361 = merge_sales_tables('t_361sales_', '361', 50)
    df_361.to_sql('dwd_sales_361', engine, if_exists='replace', index=False)

    # Step 2: 合并韦德销售分表
    df_wd = merge_sales_tables('wd_sales_', '韦德', 50)
    df_wd.to_sql('dwd_sales_wd', engine, if_exists='replace', index=False)

    # Step 3: 读取商品库并计算生命周期
    df_product = pd.read_sql("SELECT * FROM dwd_product_all", engine)
    df_product[['lifecycle_tag', 'days_on_shelf']] = df_product['shelf_date'].apply(
        lambda x: pd.Series(calculate_lifecycle(x))
    )

    # Step 4: 生成180天计划
    all_plans = []
    for _, row in df_product.iterrows():
        plan = generate_180_day_plan(row)
        if not plan.empty:
            plan['skc'] = row['skc']
            plan['brand'] = row['brand']
            all_plans.append(plan)

    df_plans = pd.concat(all_plans, ignore_index=True)
    df_plans.to_sql('dws_skc_sales_plan', engine, if_exists='replace', index=False)

    # Step 5: 生成宽表（用于QuickBI）
    df_wide = pivot_to_wide(df_plans, 'daily_plan')
    df_wide.to_sql('ads_skc_sales_plan_wide', engine, if_exists='replace', index=False)

    logger.info("ETL 流程执行完成！")


if __name__ == '__main__':
    main_etl()
```

---

## 四、调度配置

### 4.1 Crontab（简单场景）

```bash
# 每天凌晨 02:00 执行ETL
0 2 * * * /usr/bin/python3 /opt/etl/skc_sales_etl.py >> /var/log/etl/skc_sales_$(date +\%Y\%m\%d).log 2>&1

# 每天凌晨 04:00 刷新QuickBI缓存（如需要）
0 4 * * * /usr/bin/curl -X POST "https://quickbi.aliyuncs.com/api/refresh?dataset=skc_sales_analysis"
```

### 4.2 DolphinScheduler（推荐）

```yaml
# 工作流定义
project: skc_sales_analysis
workflow: daily_etl_skc

# 任务依赖链
# task1: merge_ods_sales → task2: clean_dwd → task3: aggregate_dws → task4: build_ads → task5: refresh_quickbi

tasks:
  - name: merge_ods_sales
    type: shell
    command: python3 /opt/etl/01_merge_ods.py

  - name: clean_dwd
    type: sql
    datasource: mysql_prod
    sql: /opt/etl/02_clean_dwd.sql

  - name: aggregate_dws
    type: sql
    datasource: mysql_prod
    sql: /opt/etl/03_aggregate_dws.sql

  - name: build_ads
    type: sql
    datasource: mysql_prod
    sql: /opt/etl/04_build_ads.sql

  - name: refresh_quickbi
    type: http
    url: https://quickbi.aliyuncs.com/api/refresh
    method: POST
    body: '{"dataset": "skc_sales_analysis"}'

dependencies:
  merge_ods_sales → clean_dwd → aggregate_dws → build_ads → refresh_quickbi
```

---

## 五、QuickBI 看板配置建议

### 5.1 页面布局

```
┌────────────────────────────────────────────────────────────┐
│  指标卡区域（顶部）                                          │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐  │
│  │ 总SKC  │ │ 总订货 │ │ 总达成 │ │ 滞销数 │ │ 今日计划│  │
│  │  156   │ │ 50,000 │ │ 28.6%  │ │   12   │ │  850   │  │
│  └────────┘ └────────┘ └────────┘ └────────┘ └────────┘  │
├────────────────────────────────────────────────────────────┤
│  筛选器区域                                                  │
│  [品牌▼] [生命周期▼] [系列▼] [上架时间范围 □□□□~□□□□]     │
├────────────────────────────────────────────────────────────┤
│  交叉表区域（核心）                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │ SKC      │ 基础信息 │ Day1 │ Day2 │ ... │ Day180 │  │
│  │ ABCW011  │ 清货期   │ 27.8 │ 27.8 │ ... │ 27.8   │  │
│  │          │ 实际销售 │  41  │  --  │ ... │  --    │  │
│  │          │ 调整后   │ 22.2 │ 22.2 │ ... │ 27.8   │  │
│  │ ABAV085  │ 热销期   │ 13.3 │ 13.3 │ ... │ 16.7   │  │
│  │ ...      │ ...      │ ...  │ ...  │ ... │ ...    │  │
│  └────────────────────────────────────────────────────┘  │
├────────────────────────────────────────────────────────────┤
│  趋势图区域（底部）                                          │
│  [选中SKC的180天计划vs实际折线图]                           │
└────────────────────────────────────────────────────────────┘
```

### 5.2 数据集配置要点

| 配置项 | 说明 |
|--------|------|
| 数据连接 | MySQL / MaxCompute 直连 |
| 刷新策略 | 每日 06:00 自动刷新（T+1） |
| 缓存设置 | 开启数据集缓存，有效期24小时 |
| 权限控制 | 按品牌/系列设置行级权限 |
| 导出格式 | 支持Excel导出（兼容现有格式） |

---

## 六、总结

| 层级 | 核心任务 | 表数量 | 数据量 | 更新频率 |
|------|---------|--------|--------|---------|
| ODS | 飞书同步原始数据 | 100+张 | ~500万行 | 实时/小时 |
| DWD | 分表合并+清洗+标准化 | 6张 | ~250万行 | 每日 |
| DWS | SKC聚合+生命周期+计划生成 | 4张 | ~50万行 | 每日 |
| ADS | 宽表组装+QuickBI适配 | 3张 | ~5万行 | 每日 |
| QuickBI | 可视化展示 | 数据集3个 | 内存缓存 | 每日刷新 |

**核心设计原则**：
1. **分表合并**：用 `UNION ALL` 或 Python 脚本将50张分表合并为统一明细表
2. **生命周期计算**：基于上架日期动态计算，非固定标签
3. **计划生成**：按三阶段比例（30%/50%/20%）均摊到180天
4. **存储优化**：窄表存储 + 视图宽表展示，兼顾存储与展示
5. **增量更新**：DWD层近7日增量，DWS/ADS层全量覆盖（SKC维度小）
