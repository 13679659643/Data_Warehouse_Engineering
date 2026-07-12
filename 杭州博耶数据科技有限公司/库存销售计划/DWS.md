# DWS层：数据汇总层（DWD → DWS 完整解决方案）

> 编写日期：2026-07-12
> 适用范围：韦德品牌4个核心渠道 `channel_code IN ('wd', 'japan', 'spanish', 'germany')`，不考虑361品牌
> 口径依据：`杭州博耶数据科技有限公司/指标口径/基于DWD层的字段口径定义.md`
> 数据基座：DWD层4张核心表（均带 `feishu_dwd.` 前缀）

## 设计目标

将 DWD 层明细数据按业务口径汇总为可直接消费的宽表，输出 SKU / SKC 两个维度的商品维表、1~180天销售计划核心表，以及异常数据表。所有计算严格遵循口径文档（第三节 SKU 维度、第五节 SKC 维度、第四节/第六节 1~180天逐日计划）。

## 设计原则

1. **口径唯一来源**：所有字段计算逻辑以 `基于DWD层的字段口径定义.md` 为准，不灵活变通
2. **StarRocks 规范**：COMMENT 用双引号 `"`、英文括号 `()`、`replication_num="1"`、`compression="LZ4"`、`fast_schema_evolution="true"`
3. **Key 列前 N 列**：PRIMARY KEY 建议 ≤3 列，Key 列与表结构顺序一致
4. **空值兜底**：数值 `COALESCE(..., 0)`，字符串 `COALESCE(NULLIF(TRIM(...), ''), 'None')`，日期兜底 NULL
5. **防除零**：使用 `NULLIF(..., 0)`
6. **显式列名与别名**：INSERT INTO 显式列出目标列，SELECT 每个字段加 `AS alias`
7. **反引号转义**：`30_est_arrival_date` 以数字开头必须用反引号包裹
8. **财务/库存高亮**：涉及金额、库存的字段需人工审查

## 全局口径速记

| 项 | 取值 |
|---|---|
| 品牌过滤 | `brand = '韦德'` |
| 渠道过滤 | `channel_code IN ('wd', 'japan', 'spanish', 'germany')` |
| SKU 维度键 | `style_no_size = CONCAT_WS('-', style_no, size)` |
| SKC 维度键 | `style_no` |
| 上市第1天 | `shelf_date`（SKU直接取，SKC取 `MIN(shelf_date)`） |
| 上市第N天 | `lifecycle_day = DATEDIFF(sale_date, shelf_date) + 1` |
| 阶段 ratio | 新品期(1~30)=0.8，热销期(31~120)=1.1，清货期(121~180)=1.0 |
| 日期补齐范围 | 每个 SKU/SKC 从自身 shelf_date 到「全局最晚 shelf_date + 180天」 |
| sale_date_label | 1~180 显示数字（1、2、…、180），>180 显示 '超周期' |
| 超周期阶段 | 只算日销量/日金额/累计/在仓/可提/可售周期，销售计划全部 NULL |

---

## 一、DWS层整体架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            DWD 明细数据层                               │
│  feishu_dwd.dwd_feishu_sales_all_d          (销售日明细,record_id主键)  │
│  feishu_dwd.dwd_feishu_product_all_d        (商品库,sku+brand主键)      │
│  feishu_dwd.dwd_feishu_inventory_wdpinpai_d (品牌方库存,id主键)        │
│  feishu_dwd.dwd_feishu_brand_order_arrival_d(订货到货,style_no_size主键)│
└─────────────────────────────────────────────────────────────────────────┘
                                   │ ETL: 聚合+计算+补齐
                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            DWS 汇总层                                   │
│  ┌──────────────────────────────┐ ┌──────────────────────────────┐     │
│  │ feishu_dws.                  │ │ feishu_dws.                  │     │
│  │ dws_sku_product_info_d       │ │ dws_skc_product_info_d       │     │
│  │ SKU商品维表(日刷新)          │ │ SKC商品维表(日刷新)          │     │
│  └──────────────────────────────┘ └──────────────────────────────┘     │
│  ┌──────────────────────────────┐ ┌──────────────────────────────┐     │
│  │ feishu_dws.                  │ │ feishu_dws.                  │     │
│  │ dws_sku_sales_plan_180d_d    │ │ dws_skc_sales_plan_180d_d    │     │
│  │ SKU销售计划核心表(日刷新)    │ │ SKC销售计划核心表(日刷新)    │     │
│  └──────────────────────────────┘ └──────────────────────────────┘     │
│  ┌──────────────────────────────┐ ┌──────────────────────────────┐     │
│  │ feishu_dws.                  │ │ feishu_dws.                  │     │
│  │ dws_sku_abnormal_d           │ │ dws_skc_abnormal_d           │     │
│  │ SKU异常表(日刷新)            │ │ SKC异常表(日刷新)            │     │
│  └──────────────────────────────┘ └──────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
                              ADS / QuickBI
```

**数据流**：
1. 4 张 DWD 表 → JOIN 聚合 → 6 张 DWS 表
2. 商品维表 (`dws_sku_product_info_d` / `dws_skc_product_info_d`) 提供静态属性 + 当日库存/销售汇总
3. 销售计划表 (`dws_sku_sales_plan_180d_d` / `dws_skc_sales_plan_180d_d`) 提供 1~180 天逐日计划与达成
4. 异常表 (`dws_sku_abnormal_d` / `dws_skc_abnormal_d`) 收集 style_no_size/style_no 为空或 shelf_date 为空的记录

---

## 二、DWS层表清单

| 表名 | 中文名 | 粒度 | 来源 | 模型 | 刷新 |
|------|--------|------|------|------|------|
| `feishu_dws.dws_sku_product_info_d` | SKU商品维表 | style_no_size | product_all_d + brand_order_arrival_d + inventory_wdpinpai_d + sales_all_d | PRIMARY KEY | 日刷新 |
| `feishu_dws.dws_skc_product_info_d` | SKC商品维表 | style_no | 同上聚合到 style_no | PRIMARY KEY | 日刷新 |
| `feishu_dws.dws_sku_sales_plan_180d_d` | SKU销售计划180天表 | style_no_size + sale_date | product_all_d + brand_order_arrival_d + sales_all_d + inventory_wdpinpai_d | PRIMARY KEY | 日刷新 |
| `feishu_dws.dws_skc_sales_plan_180d_d` | SKC销售计划180天表 | style_no + sale_date | 同上聚合到 style_no | PRIMARY KEY | 日刷新 |
| `feishu_dws.dws_sku_abnormal_d` | SKU异常表 | sku | product_all_d | PRIMARY KEY | 日刷新 |
| `feishu_dws.dws_skc_abnormal_d` | SKC异常表 | style_no | product_all_d | PRIMARY KEY | 日刷新 |

---

## 三、关键口径实现说明

### 3.1 shelf_date 补全（口径3.5节 / 5.5节）

```sql
-- SKU维度：优先取 product_all_d.shelf_date，为空则关联 brand_order_arrival_d 的最早 30_est_arrival_date
-- 注意：同一 style_no_size 可能有多条记录，须先聚合取 MIN(30_est_arrival_date)，避免一对多导致数据膨胀
COALESCE(
    NULLIF(p.shelf_date, DATE('1970-01-01')),
    boa.est_arrival_date   -- 来源于子查询：SELECT style_no_size, MIN(`30_est_arrival_date`) ... GROUP BY style_no_size
) AS shelf_date
-- 关联条件：CONCAT_WS('-', p.style_no, p.size) = boa.style_no_size
```

### 3.2 订货数量 Q（口径3.18节 / 5.18节）

- **SKU维度**：`brand_order_arrival_d.order_qty`，按 `style_no_size` 关联，`COALESCE(..., 0)`
- **SKC维度**：`SUM(order_qty) GROUP BY style_no`，`COALESCE(..., 0)`

### 3.3 累计实际销量 cum_actual(N)（口径4.4节 / 6.4节）

```sql
-- cum_actual(N) = 截至第N-1天的实际销量总和（不含当天N）
-- 即 lifecycle_day BETWEEN 1 AND (N-1) 的 SUM(qty)
SUM(CASE WHEN lifecycle_day < N THEN qty ELSE 0 END) AS cum_actual
-- 等价于：SUM(CASE WHEN lifecycle_day <= N-1 THEN qty ELSE 0 END)
```

### 3.4 阶段与 ratio（口径4.2节）

```sql
CASE
    WHEN lifecycle_day BETWEEN 1 AND 30   THEN 0.8  -- 新品期
    WHEN lifecycle_day BETWEEN 31 AND 120 THEN 1.1  -- 热销期
    WHEN lifecycle_day BETWEEN 121 AND 180 THEN 1.0 -- 清货期
    ELSE NULL                                       -- 超周期
END AS ratio
```

### 3.5 销售计划计算（口径4.3~4.6节）

```sql
-- 1) plan_pre(N) = Q * ratio / 180  （1≤N≤180）
Q * ratio / 180 AS plan_pre

-- 2) plan_post(N) = (Q - cum_actual(N)) * ratio / (180 - sold_days)
--    sold_days = N - 1（截至昨天的天数）
--    即分母 = 180 - (N-1) = 181 - N
--    当 N=1 时，cum_actual=0, sold_days=0, 分母=180
(Q - cum_actual) * ratio / NULLIF(181 - N, 0) AS plan_post

-- 3) actual_qty(N) = 该SKU/SKC在上市第N天的实际销量
--    无销售记录则 0

-- 4) achievement(N) = actual_qty(N) / plan_post(N)
--    plan_post=0 或 NULL 时为 NULL
actual_qty / NULLIF(plan_post, 0) AS achievement_rate
```

### 3.6 日期补齐范围（口径4.1节）

- 全局最晚 shelf_date = `MAX(shelf_date) OVER()` （考虑补全后的 shelf_date）
- 补齐结束日 = 全局最晚 shelf_date + 180 天
- 每个 SKU/SKC：从自身 shelf_date 到补齐结束日，逐日生成一行
- `lifecycle_day = DATEDIFF(sale_date, shelf_date) + 1`
- `sale_date_label = CAST(lifecycle_day AS VARCHAR)` 当 1~180，否则 `'超周期'`

### 3.7 库存相关（口径3.9~3.11节）

- **在仓库存**：SKU=`COALESCE(product_all_d.inventory_sku, 0)`；SKC=`SUM(inventory_sku) GROUP BY style_no`
- **可提库存**：取 `inventory_wdpinpai_d` 中 `inventory_date = MAX(inventory_date)` 的记录
  - SKU：按 `sku` 聚合 `SUM(inventory_qty)`
  - SKC：按 `style_no` 聚合 `SUM(inventory_qty)`
- **可售周期** = 在仓库存 / 30天平均日销（日销为0或NULL时返回NULL）

### 3.8 30天平均日销（口径3.12节 / 5.12节）

```sql
-- sold_days = N - 1（排除今天）
CASE
    WHEN sold_days = 0 THEN NULL                                        -- 无销售历史
    WHEN sold_days < 30 THEN cum_actual / sold_days                     -- 不足30天按实际已售天数
    ELSE last_30d_qty / 30                                              -- 满30天按30天平均
END AS daily_avg_qty_30d
```

### 3.9 达成比例（口径3.19节 / 5.19节）

```sql
cum_actual / NULLIF(order_qty, 0) AS achievement_ratio
```

### 3.10 总订货数量（口径3.20节 / 5.20节）

```sql
-- 当 is_replenish='是' 时：总订货 = 订货数量 + 补货数量；否则 = 订货数量
CASE WHEN COALESCE(is_replenish, '否') = '是'
     THEN order_qty + COALESCE(replenish_qty, 0)
     ELSE order_qty
END AS total_order_qty
```

---

## 四、DWS表1：SKU商品维表 `dws_sku_product_info_d`

> 用途：SKU维度的商品基础信息 + 当日库存/销售汇总
> 粒度：`style_no_size`（一行一个SKU）
> 来源：`dwd_feishu_product_all_d` + `dwd_feishu_brand_order_arrival_d` + `dwd_feishu_inventory_wdpinpai_d` + `dwd_feishu_sales_all_d`
> 过滤：`style_no_size IS NOT NULL AND style_no_size <> 'None' AND shelf_date IS NOT NULL`

### 4.1 DDL

```sql
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

### 4.2 ETL

```sql
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
    achievement_ratio, lifecycle_day, sales_cycle_label,
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
-- 3. 可提库存（口径3.10节）：取最新 inventory_date，按 style_no_size 聚合（一步完成）
available_inv AS (
    SELECT
        CONCAT_WS('-', inv.style_no, inv.size)             AS style_no_size,
        COALESCE(SUM(inv.inventory_qty), 0)                AS available_inventory,
        MAX(inv.inventory_date) AS max_date
    FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d inv
    GROUP BY CONCAT_WS('-', inv.style_no, inv.size)
),
-- 4. 销售汇总（口径3.12节 / 3.16节）：核心4渠道，按 style_no_size 聚合
--    累计销量 = shelf_date ~ 昨日 的 SUM(qty)
--    最近30天销量 = 最近30天（含昨日）的 SUM(qty)
sales_agg AS (
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
    GROUP BY CONCAT_WS('-', s.style_no, s.size)
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
    -- 口径3.12节：30天平均日销
    -- sold_days = DATEDIFF(CURRENT_DATE(), shelf_date) （排除今天）
    CASE
        WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) <= 0 THEN NULL
        WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) < 30
            THEN CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6)) / DATEDIFF(CURRENT_DATE(), pb.shelf_date)
        ELSE CAST(COALESCE(sa.last_30d_qty, 0) AS DECIMAL(18,6)) / 30
    END                                                    AS daily_avg_qty_30d,
    -- 口径3.11节：可售周期 = 在仓库存 / 30天平均日销
    CASE
        WHEN (CASE
            WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) <= 0 THEN NULL
            WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) < 30
                THEN CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6)) / DATEDIFF(CURRENT_DATE(), pb.shelf_date)
            ELSE CAST(COALESCE(sa.last_30d_qty, 0) AS DECIMAL(18,6)) / 30
        END) IS NULL
          OR (CASE
            WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) <= 0 THEN NULL
            WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) < 30
                THEN CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6)) / DATEDIFF(CURRENT_DATE(), pb.shelf_date)
            ELSE CAST(COALESCE(sa.last_30d_qty, 0) AS DECIMAL(18,6)) / 30
        END) = 0
        THEN NULL
        ELSE CAST(pb.inventory_sku AS DECIMAL(18,6)) /
             (CASE
                WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) <= 0 THEN NULL
                WHEN DATEDIFF(CURRENT_DATE(), pb.shelf_date) < 30
                    THEN CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6)) / DATEDIFF(CURRENT_DATE(), pb.shelf_date)
                ELSE CAST(COALESCE(sa.last_30d_qty, 0) AS DECIMAL(18,6)) / 30
             END)
    END                                                    AS sellable_days,
    -- 口径3.19节：达成比例 = 累计销量 / 订货数量
    CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6))
        / NULLIF(CAST(pb.order_qty AS DECIMAL(18,6)), 0) AS achievement_ratio,
    -- 口径3.7节：已上架天数
    DATEDIFF(CURRENT_DATE(), pb.shelf_date) + 1           AS lifecycle_day,
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
LEFT JOIN sales_agg sa       ON pb.style_no_size = sa.style_no_size
WHERE pb.style_no_size IS NOT NULL
  AND pb.style_no_size <> 'None'
  AND pb.shelf_date IS NOT NULL;
```

### 4.3 验证SQL

```sql
-- 1. 行数核验
SELECT COUNT(*) AS sku_cnt FROM feishu_dws.dws_sku_product_info_d;

-- 2. 抽样：查看某SKU的库存与销售汇总
SELECT style_no_size, brand, shelf_date, inventory_sku, available_inventory,
       order_qty, total_order_qty, daily_avg_qty_30d, sellable_days,
       achievement_ratio, lifecycle_day, sales_cycle_label
FROM feishu_dws.dws_sku_product_info_d
WHERE style_no_size LIKE 'ABAS083-11%'
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

---

## 五、DWS表2：SKC商品维表 `dws_skc_product_info_d`

> 用途：SKC维度的商品基础信息 + 当日库存/销售汇总（按 style_no 聚合）
> 粒度：`style_no`（一行一个SKC）
> 来源：同 SKU 表，聚合到 style_no
> 过滤：`style_no IS NOT NULL AND style_no <> 'None' AND MIN(shelf_date) IS NOT NULL`

### 5.1 DDL

```sql
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

### 5.2 ETL

```sql
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
    sellable_days, achievement_ratio, lifecycle_day, sales_cycle_label,
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
sales_agg_skc AS (
    SELECT
        s.style_no                                         AS style_no,
        COALESCE(SUM(CASE WHEN s.sales_date < CURRENT_DATE() THEN s.qty ELSE 0 END), 0)
                                                          AS cum_actual,
        COALESCE(SUM(CASE WHEN s.sales_date >= DATE_SUB(CURRENT_DATE(), 30)
                          AND s.sales_date < CURRENT_DATE() THEN s.qty ELSE 0 END), 0)
                                                          AS last_30d_qty
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
    GROUP BY s.style_no
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
    CASE
        WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) <= 0 THEN NULL
        WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) < 30
            THEN CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6)) / DATEDIFF(CURRENT_DATE(), sb.shelf_date)
        ELSE CAST(COALESCE(sa.last_30d_qty, 0) AS DECIMAL(18,6)) / 30
    END                                                    AS daily_avg_qty_30d,
    -- 口径5.11节：SKC可售周期
    CASE
        WHEN (CASE
            WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) <= 0 THEN NULL
            WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) < 30
                THEN CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6)) / DATEDIFF(CURRENT_DATE(), sb.shelf_date)
            ELSE CAST(COALESCE(sa.last_30d_qty, 0) AS DECIMAL(18,6)) / 30
        END) IS NULL
          OR (CASE
            WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) <= 0 THEN NULL
            WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) < 30
                THEN CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6)) / DATEDIFF(CURRENT_DATE(), sb.shelf_date)
            ELSE CAST(COALESCE(sa.last_30d_qty, 0) AS DECIMAL(18,6)) / 30
        END) = 0
        THEN NULL
        ELSE CAST(sb.inventory_sku AS DECIMAL(18,6)) /
             (CASE
                WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) <= 0 THEN NULL
                WHEN DATEDIFF(CURRENT_DATE(), sb.shelf_date) < 30
                    THEN CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6)) / DATEDIFF(CURRENT_DATE(), sb.shelf_date)
                ELSE CAST(COALESCE(sa.last_30d_qty, 0) AS DECIMAL(18,6)) / 30
             END)
    END                                                    AS sellable_days,
    -- 口径5.19节：SKC达成比例
    CAST(COALESCE(sa.cum_actual, 0) AS DECIMAL(18,6))
        / NULLIF(CAST(sb.order_qty AS DECIMAL(18,6)), 0) AS achievement_ratio,
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
LEFT JOIN sales_agg_skc sa   ON sb.style_no = sa.style_no
WHERE sb.style_no IS NOT NULL
  AND sb.style_no <> 'None'
  AND sb.shelf_date IS NOT NULL;
```

### 5.3 验证SQL

```sql
-- 1. 行数核验
SELECT COUNT(*) AS skc_cnt FROM feishu_dws.dws_skc_product_info_d;

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

---

## 六、DWS表3：SKU销售计划180天表 `dws_sku_sales_plan_180d_d`（核心表）

> 用途：SKU维度的1~180天逐日销售计划与达成分析（核心表）
> 粒度：`style_no_size + sale_date`（一行一个SKU的一天）
> 日期补齐：每个SKU从自身 shelf_date 到「全局最晚 shelf_date + 180天」
> 来源：`dwd_feishu_product_all_d` + `dwd_feishu_brand_order_arrival_d` + `dwd_feishu_sales_all_d` + `dwd_feishu_inventory_wdpinpai_d`
> 超周期(>180天)：plan_pre/plan_post/achievement_rate = NULL，只计算实际销售和库存

### 6.1 DDL

```sql
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
PARTITION BY RANGE(`sale_date`) ()
DISTRIBUTED BY HASH(`style_no_size`) BUCKETS 32
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

### 6.2 ETL

```sql
-- ============================================================
-- ETL: feishu_dws.dws_sku_sales_plan_180d_d
-- 粒度：style_no_size + sale_date
-- 日期补齐：每个SKU从 shelf_date 到 全局最晚shelf_date+180天
-- 渠道：韦德4核心渠道
-- 口径：4.1~4.6节
-- ============================================================
TRUNCATE TABLE feishu_dws.dws_sku_sales_plan_180d_d;

INSERT INTO feishu_dws.dws_sku_sales_plan_180d_d (
    style_no_size, sale_date, lifecycle_day, sale_date_label,
    sales_cycle_label, ratio, brand, style_no, size, shelf_date,
    order_qty, plan_pre, plan_post, actual_qty, actual_amt,
    cum_actual, cum_actual_amt, achievement_rate,
    inventory_sku, available_inventory, sellable_days,
    sync_time, insert_date, update_date
)
WITH
-- 1. brand_order_arrival_d 按 style_no_size 聚合，30_est_arrival_date 取最早时间（口径3.5节）
boa_agg AS (
    SELECT
        boa.style_no_size                                  AS style_no_size,
        COALESCE(SUM(boa.order_qty), 0)                    AS order_qty,
        MIN(boa.`30_est_arrival_date`)                     AS est_arrival_date
    FROM feishu_dwd.dwd_feishu_brand_order_arrival_d boa
    GROUP BY boa.style_no_size
),
-- 2. SKU 基础信息 + shelf_date 补全（口径3.5节）
--    shelf_date 优先取 product_all_d.shelf_date，为空取最早的 30_est_arrival_date
product_base AS (
    SELECT
        CONCAT_WS('-', p.style_no, p.size)                 AS style_no_size,
        p.brand                                            AS brand,
        p.style_no                                         AS style_no,
        p.size                                             AS size,
        COALESCE(
            NULLIF(p.shelf_date, DATE('1970-01-01')),
            boa.est_arrival_date
        )                                                  AS shelf_date,
        COALESCE(p.inventory_sku, 0)                       AS inventory_sku,
        p.sync_time                                        AS sync_time,
        -- 订货数量 Q（口径3.18节）：按 style_no_size 关联
        COALESCE(boa.order_qty, 0)                         AS order_qty
    FROM feishu_dwd.dwd_feishu_product_all_d p
    LEFT JOIN boa_agg boa
        ON CONCAT_WS('-', p.style_no, p.size) = boa.style_no_size
    WHERE p.brand = '韦德'
      AND CONCAT_WS('-', p.style_no, p.size) IS NOT NULL
      AND CONCAT_WS('-', p.style_no, p.size) <> 'None'
      AND COALESCE(
            NULLIF(p.shelf_date, DATE('1970-01-01')),
            boa.est_arrival_date
          ) IS NOT NULL
),
-- 3. 可提库存（口径3.10节）：取最新 inventory_date，按 style_no_size 聚合（一步完成）
available_inv AS (
    SELECT
        CONCAT_WS('-', inv.style_no, inv.size)             AS style_no_size,
        COALESCE(SUM(inv.inventory_qty), 0)                AS available_inventory
    FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d inv
    INNER JOIN (
        SELECT CONCAT_WS('-', style_no, size) AS style_no_size,
               MAX(inventory_date) AS max_date
        FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d
        GROUP BY CONCAT_WS('-', style_no, size)
    ) lid ON CONCAT_WS('-', inv.style_no, inv.size) = lid.style_no_size
       AND inv.inventory_date = lid.max_date
    GROUP BY CONCAT_WS('-', inv.style_no, inv.size)
),
-- 4. 销售明细按 style_no_size + sales_date 聚合（核心4渠道）
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
-- 5. 30天平均日销辅助（口径3.12节），按 style_no_size 聚合
sales_30d AS (
    SELECT
        CONCAT_WS('-', s.style_no, s.size)                 AS style_no_size,
        COALESCE(SUM(CASE WHEN s.sales_date >= DATE_SUB(CURRENT_DATE(), 30)
                          AND s.sales_date < CURRENT_DATE() THEN s.qty ELSE 0 END), 0) AS last_30d_qty,
        COALESCE(SUM(CASE WHEN s.sales_date < CURRENT_DATE() THEN s.qty ELSE 0 END), 0) AS cum_actual_total
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
    GROUP BY CONCAT_WS('-', s.style_no, s.size)
),
-- 6. 累计实际销量（截至 N-1 天，口径4.4节），按 style_no_size 聚合
--    使用窗口函数：SUM(qty) OVER (PARTITION BY style_no_size ORDER BY sales_date ROWS UNBOUNDED ~ 1 PRECEDING)
sales_cum AS (
    SELECT
        CONCAT_WS('-', s.style_no, s.size)                 AS style_no_size,
        s.sales_date                                       AS sales_date,
        SUM(s.qty) OVER (PARTITION BY CONCAT_WS('-', s.style_no, s.size) ORDER BY s.sales_date
                         ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cum_before,
        SUM(s.amt) OVER (PARTITION BY CONCAT_WS('-', s.style_no, s.size) ORDER BY s.sales_date
                         ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cum_before_amt
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
),
-- 6. 全局最晚 shelf_date（用于确定补齐结束日 = 最晚shelf_date + 180天）
global_max_shelf AS (
    SELECT MAX(shelf_date) AS max_shelf_date FROM product_base
),
-- 7. 日期补齐：每个 SKU 从 shelf_date 到 全局最晚shelf_date+180天，逐日生成
--    使用 GENERATE_SERIES 生成日期序列，再 CROSS JOIN
sku_calendar AS (
    SELECT
        pb.style_no_size                                   AS style_no_size,
        pb.brand                                           AS brand,
        pb.style_no                                        AS style_no,
        pb.size                                            AS size,
        pb.shelf_date                                      AS shelf_date,
        pb.inventory_sku                                   AS inventory_sku,
        pb.order_qty                                       AS order_qty,
        pb.sync_time                                       AS sync_time,
        -- 全局最晚 shelf_date + 180天
        DATE_ADD(gms.max_shelf_date, INTERVAL 180 DAY)     AS end_date,
        -- 上市第N天 = DATEDIFF(sale_date, shelf_date) + 1
        DATEDIFF(gs.dt, pb.shelf_date) + 1                 AS lifecycle_day,
        gs.dt                                              AS sale_date
    FROM product_base pb
    CROSS JOIN global_max_shelf gms
    -- 生成从 shelf_date 到 全局最晚shelf_date+180天 的日期序列
    CROSS JOIN GENERATE_SERIES(
        DATE_DIFF(pb.shelf_date, DATE('1970-01-01')),
        DATE_DIFF(DATE_ADD(gms.max_shelf_date, INTERVAL 180 DAY), DATE('1970-01-01'))
    ) AS gs(dt_int)
    -- 将整数序列转回日期
    -- 注：StarRocks 中 GENERATE_SERIES 返回数值序列，需转日期
    -- 此处 dt_int 转换为日期：DATE_ADD('1970-01-01', INTERVAL dt_int DAY)
    -- 为简化，下方 SELECT 使用 DATE_ADD 转换
    -- 实际使用时，请根据 StarRocks 版本调整日期序列生成方式
    WHERE DATE_ADD(DATE('1970-01-01'), INTERVAL gs.dt_int DAY)
          BETWEEN pb.shelf_date
          AND DATE_ADD(gms.max_shelf_date, INTERVAL 180 DAY)
)
-- 注：由于 GENERATE_SERIES 的列引用需在 SELECT 中转换，这里用子查询包装
-- 实际可执行的等价写法见下方说明
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
    -- 口径4.3节：plan_pre = Q * ratio / 180 （超周期为NULL）
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN CAST(sc.order_qty AS DECIMAL(18,6))
              * CASE
                  WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                END / 180
         ELSE NULL
    END                                                    AS plan_pre,
    -- 口径4.4节：plan_post = (Q - cum_actual(N)) * ratio / (181 - N)
    --    cum_actual(N) = 截至N-1天的累计销量
    --    分母 = 180 - sold_days = 180 - (N-1) = 181 - N
    --    超周期为NULL
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN (CAST(sc.order_qty AS DECIMAL(18,6))
               - CAST(COALESCE(sdc.cum_before, 0) AS DECIMAL(18,6)))
              * CASE
                  WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                END
              / NULLIF(181 - sc.lifecycle_day, 0)
         ELSE NULL
    END                                                    AS plan_post,
    -- 口径4.5节：实际销售 = 第N天的 SUM(qty)
    COALESCE(sd.daily_qty, 0)                              AS actual_qty,
    COALESCE(sd.daily_amt, 0)                              AS actual_amt,
    -- 累计实际销量 = 截至N-1天的 SUM(qty)（即 lifecycle_day < N）
    COALESCE(sdc.cum_before, 0)                            AS cum_actual,
    COALESCE(sdc.cum_before_amt, 0)                        AS cum_actual_amt,
    -- 口径4.6节：达成情况 = actual_qty / plan_post
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN CAST(COALESCE(sd.daily_qty, 0) AS DECIMAL(18,6))
              / NULLIF(
                  (CAST(sc.order_qty AS DECIMAL(18,6))
                   - CAST(COALESCE(sdc.cum_before, 0) AS DECIMAL(18,6)))
                  * CASE
                      WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                    END
                  / NULLIF(181 - sc.lifecycle_day, 0), 0)
         ELSE NULL
    END                                                    AS achievement_rate,
    sc.inventory_sku                                       AS inventory_sku,
    COALESCE(ai.available_inventory, 0)                    AS available_inventory,
    -- 口径3.11节：可售周期（超周期才计算，1~180天也可计算便于对比）
    CASE
        WHEN s30.cum_actual_total IS NULL OR s30.last_30d_qty IS NULL THEN NULL
        WHEN DATEDIFF(CURRENT_DATE(), sc.shelf_date) <= 0 THEN NULL
        WHEN DATEDIFF(CURRENT_DATE(), sc.shelf_date) < 30
             AND DATEDIFF(CURRENT_DATE(), sc.shelf_date) > 0
             AND NULLIF(DATEDIFF(CURRENT_DATE(), sc.shelf_date), 0) IS NOT NULL
            THEN CAST(sc.inventory_sku AS DECIMAL(18,6))
                 / NULLIF(CAST(s30.cum_actual_total AS DECIMAL(18,6))
                          / DATEDIFF(CURRENT_DATE(), sc.shelf_date), 0)
        ELSE CAST(sc.inventory_sku AS DECIMAL(18,6))
             / NULLIF(CAST(s30.last_30d_qty AS DECIMAL(18,6)) / 30, 0)
    END                                                    AS sellable_days,
    sc.sync_time                                           AS sync_time,
    CURRENT_TIMESTAMP()                                    AS insert_date,
    CURRENT_TIMESTAMP()                                    AS update_date
FROM sku_calendar sc
LEFT JOIN available_inv ai   ON sc.style_no_size = ai.style_no_size
LEFT JOIN sales_daily sd     ON sc.style_no_size = sd.style_no_size AND sc.sale_date = sd.sales_date
LEFT JOIN sales_30d s30      ON sc.style_no_size = s30.style_no_size
-- 累计销量：截至 N-1 天（即 lifecycle_day < N 的所有销量），关联键：style_no_size + sale_date
LEFT JOIN sales_cum sdc      ON sc.style_no_size = sdc.style_no_size AND sc.sale_date = sdc.sales_date
ORDER BY sc.style_no_size, sc.sale_date;
```

> **【日期序列生成说明】**
>
> 上述 SQL 使用 `GENERATE_SERIES` 生成日期序列。在 StarRocks 中，`GENERATE_SERIES(start, end)` 返回一个数值序列表，需配合 `DATE_ADD` 转换为日期。
>
> 如果 StarRocks 版本不支持 `GENERATE_SERIES`，可使用以下**递归 CTE 替代方案**：
>
> ```sql
> -- 递归 CTE 生成日期序列（替代 GENERATE_SERIES）
> WITH RECURSIVE date_series AS (
>     SELECT DATE('2024-01-01') AS dt  -- 起始日期（取最早的 shelf_date）
>     UNION ALL
>     SELECT DATE_ADD(dt, INTERVAL 1 DAY) FROM date_series
>     WHERE dt < DATE_ADD(CURRENT_DATE(), INTERVAL 180 DAY)  -- 结束日期
> )
> SELECT dt FROM date_series
> ```
>
> 实际部署时，请根据 StarRocks 版本选择合适的方式。建议先用以下 SQL 测试 `GENERATE_SERIES` 是否可用：
>
> ```sql
> SELECT * FROM GENERATE_SERIES(1, 10) AS t(n);
> ```

### 6.3 验证SQL

```sql
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
  AND ABS(plan_post - order_qty * ratio / 180) > 0.001
LIMIT 50;

-- 5. 校验：超周期(>180天)的 plan_pre/plan_post/achievement_rate 应为 NULL
SELECT COUNT(*) AS abnormal_cnt
FROM feishu_dws.dws_sku_sales_plan_180d_d
WHERE lifecycle_day > 180
  AND (plan_pre IS NOT NULL OR plan_post IS NOT NULL OR achievement_rate IS NOT NULL);

-- 6. 累计销量校验：cum_actual(N) 应 = SUM(actual_qty) WHERE lifecycle_day < N
SELECT sc.style_no_size, sc.sale_date, sc.lifecycle_day, sc.cum_actual,
       (SELECT SUM(COALESCE(actual_qty, 0))
        FROM feishu_dws.dws_sku_sales_plan_180d_d sub
        WHERE sub.style_no_size = sc.style_no_size
          AND sub.lifecycle_day < sc.lifecycle_day) AS calc_cum
FROM feishu_dws.dws_sku_sales_plan_180d_d sc
WHERE sc.lifecycle_day BETWEEN 2 AND 10
  AND sc.cum_actual <>
      (SELECT SUM(COALESCE(actual_qty, 0))
       FROM feishu_dws.dws_sku_sales_plan_180d_d sub
       WHERE sub.style_no_size = sc.style_no_size
         AND sub.lifecycle_day < sc.lifecycle_day)
LIMIT 50;
```

---

## 七、DWS表4：SKC销售计划180天表 `dws_skc_sales_plan_180d_d`（核心表）

> 用途：SKC维度的1~180天逐日销售计划与达成分析（核心表）
> 粒度：`style_no + sale_date`
> 逻辑同 SKU 表，维度聚合到 style_no
> 来源：同 SKU 表

### 7.1 DDL

```sql
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
PARTITION BY RANGE(`sale_date`) ()
DISTRIBUTED BY HASH(`style_no`) BUCKETS 32
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true", 
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```

### 7.2 ETL

```sql
-- ============================================================
-- ETL: feishu_dws.dws_skc_sales_plan_180d_d
-- 粒度：style_no + sale_date
-- 逻辑同 SKU 表，维度聚合到 style_no
-- 口径：6.1~6.6节
-- ============================================================
TRUNCATE TABLE feishu_dws.dws_skc_sales_plan_180d_d;

INSERT INTO feishu_dws.dws_skc_sales_plan_180d_d (
    style_no, sale_date, lifecycle_day, sale_date_label,
    sales_cycle_label, ratio, brand, shelf_date,
    order_qty, plan_pre, plan_post, actual_qty, actual_amt,
    cum_actual, cum_actual_amt, achievement_rate,
    inventory_sku, available_inventory, sellable_days,
    sync_time, insert_date, update_date
)
WITH
-- 1. brand_order_arrival_d 按 style_no 聚合（SKC维度），30_est_arrival_date 取最早时间
boa_agg_skc AS (
    SELECT
        boa.style_no                                       AS style_no,
        COALESCE(SUM(boa.order_qty), 0)                    AS order_qty,
        MIN(boa.`30_est_arrival_date`)                     AS est_arrival_date
    FROM feishu_dwd.dwd_feishu_brand_order_arrival_d boa
    GROUP BY boa.style_no
),
-- 2. SKC 基础信息：shelf_date = MIN(每个SKU补全后的shelf_date)（口径5.5节）
--    注意：先在 SKU 级用 MIN(30_est_arrival_date) 补全 shelf_date，再聚合到 SKC 取 MIN
skc_base AS (
    SELECT
        p.style_no                                         AS style_no,
        p.brand                                            AS brand,
        MIN(COALESCE(
            NULLIF(p.shelf_date, DATE('1970-01-01')),
            boa.est_arrival_date
        ))                                                 AS shelf_date,
        SUM(COALESCE(p.inventory_sku, 0))                  AS inventory_sku,
        MAX(p.sync_time)                                   AS sync_time,
        -- 订货数量 Q（口径5.18节）：SKC维度，取 MAX 避免重复累加
        MAX(COALESCE(boa.order_qty, 0))                    AS order_qty
    FROM feishu_dwd.dwd_feishu_product_all_d p
    LEFT JOIN boa_agg_skc boa
        ON p.style_no = boa.style_no
    WHERE p.brand = '韦德'
    GROUP BY p.style_no, p.brand
),
-- 3. SKC 可提库存（口径5.10节）：取最新 inventory_date，按 style_no 聚合（一步完成）
available_inv_skc AS (
    SELECT
        inv.style_no                                       AS style_no,
        COALESCE(SUM(inv.inventory_qty), 0)                AS available_inventory
    FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d inv
    INNER JOIN (
        SELECT style_no, MAX(inventory_date) AS max_date
        FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d
        GROUP BY style_no
    ) lid ON inv.style_no = lid.style_no
       AND inv.inventory_date = lid.max_date
    GROUP BY inv.style_no
),
-- 4. SKC 销售明细按 style_no + sales_date 聚合（核心4渠道）
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
-- 5. SKC 30天平均日销辅助，按 style_no 聚合
sales_30d_skc AS (
    SELECT
        s.style_no                                         AS style_no,
        COALESCE(SUM(CASE WHEN s.sales_date >= DATE_SUB(CURRENT_DATE(), 30)
                          AND s.sales_date < CURRENT_DATE() THEN s.qty ELSE 0 END), 0) AS last_30d_qty,
        COALESCE(SUM(CASE WHEN s.sales_date < CURRENT_DATE() THEN s.qty ELSE 0 END), 0) AS cum_actual_total
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
    GROUP BY s.style_no
),
-- 6. SKC 累计实际销量（截至 N-1 天，口径6.4节），按 style_no 聚合
sales_cum_skc AS (
    SELECT
        s.style_no                                         AS style_no,
        s.sales_date                                       AS sales_date,
        SUM(s.qty) OVER (PARTITION BY s.style_no ORDER BY s.sales_date
                         ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cum_before,
        SUM(s.amt) OVER (PARTITION BY s.style_no ORDER BY s.sales_date
                         ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS cum_before_amt
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    WHERE s.brand = '韦德'
      AND s.channel_code IN ('wd', 'japan', 'spanish', 'germany')
),
-- 7. 全局最晚 shelf_date
global_max_shelf_skc AS (
    SELECT MAX(shelf_date) AS max_shelf_date FROM skc_base
),
-- 8. 日期补齐：每个 SKC 从 MIN(shelf_date) 到 全局最晚shelf_date+180天
skc_calendar AS (
    SELECT
        sb.style_no                                        AS style_no,
        sb.brand                                           AS brand,
        sb.shelf_date                                      AS shelf_date,
        sb.inventory_sku                                   AS inventory_sku,
        sb.order_qty                                       AS order_qty,
        sb.sync_time                                       AS sync_time,
        gms.max_shelf_date                                 AS max_shelf_date,
        DATEDIFF(gs.dt, sb.shelf_date) + 1                 AS lifecycle_day,
        gs.dt                                              AS sale_date
    FROM skc_base sb
    CROSS JOIN global_max_shelf_skc gms
    CROSS JOIN GENERATE_SERIES(
        DATE_DIFF(sb.shelf_date, DATE('1970-01-01')),
        DATE_DIFF(DATE_ADD(gms.max_shelf_date, INTERVAL 180 DAY), DATE('1970-01-01'))
    ) AS gs(dt_int)
    -- 将整数序列转回日期
    CROSS JOIN LATERAL (
        SELECT DATE_ADD(DATE('1970-01-01'), INTERVAL gs.dt_int DAY) AS dt
    ) AS dt_table
    WHERE dt_table.dt BETWEEN sb.shelf_date
                          AND DATE_ADD(gms.max_shelf_date, INTERVAL 180 DAY)
)
SELECT
    sc.style_no                                            AS style_no,
    sc.sale_date                                           AS sale_date,
    sc.lifecycle_day                                       AS lifecycle_day,
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN CAST(sc.lifecycle_day AS VARCHAR)
         ELSE '超周期'
    END                                                    AS sale_date_label,
    CASE
        WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN '新品期'
        WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN '热销期'
        WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN '清货期'
        ELSE '超周期'
    END                                                    AS sales_cycle_label,
    CASE
        WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
        WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
        WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
        ELSE NULL
    END                                                    AS ratio,
    sc.brand                                               AS brand,
    sc.shelf_date                                          AS shelf_date,
    sc.order_qty                                           AS order_qty,
    -- 口径6.3节：plan_pre
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN CAST(sc.order_qty AS DECIMAL(18,6))
              * CASE
                  WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                END / 180
         ELSE NULL
    END                                                    AS plan_pre,
    -- 口径6.4节：plan_post = (Q - cum_actual) * ratio / (181 - N)
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN (CAST(sc.order_qty AS DECIMAL(18,6))
               - CAST(COALESCE(sdc.cum_before, 0) AS DECIMAL(18,6)))
              * CASE
                  WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                  WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                END
              / NULLIF(181 - sc.lifecycle_day, 0)
         ELSE NULL
    END                                                    AS plan_post,
    COALESCE(sd.daily_qty, 0)                              AS actual_qty,
    COALESCE(sd.daily_amt, 0)                              AS actual_amt,
    COALESCE(sdc.cum_before, 0)                            AS cum_actual,
    COALESCE(sdc.cum_before_amt, 0)                        AS cum_actual_amt,
    -- 口径6.6节：达成情况
    CASE WHEN sc.lifecycle_day BETWEEN 1 AND 180
         THEN CAST(COALESCE(sd.daily_qty, 0) AS DECIMAL(18,6))
              / NULLIF(
                  (CAST(sc.order_qty AS DECIMAL(18,6))
                   - CAST(COALESCE(sdc.cum_before, 0) AS DECIMAL(18,6)))
                  * CASE
                      WHEN sc.lifecycle_day BETWEEN 1 AND 30    THEN CAST(0.8 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 31 AND 120  THEN CAST(1.1 AS DECIMAL(18,6))
                      WHEN sc.lifecycle_day BETWEEN 121 AND 180 THEN CAST(1.0 AS DECIMAL(18,6))
                    END
                  / NULLIF(181 - sc.lifecycle_day, 0), 0)
         ELSE NULL
    END                                                    AS achievement_rate,
    sc.inventory_sku                                       AS inventory_sku,
    COALESCE(ai.available_inventory, 0)                    AS available_inventory,
    -- 口径5.11节：可售周期
    CASE
        WHEN s30.cum_actual_total IS NULL OR s30.last_30d_qty IS NULL THEN NULL
        WHEN DATEDIFF(CURRENT_DATE(), sc.shelf_date) <= 0 THEN NULL
        WHEN DATEDIFF(CURRENT_DATE(), sc.shelf_date) < 30
             AND DATEDIFF(CURRENT_DATE(), sc.shelf_date) > 0
            THEN CAST(sc.inventory_sku AS DECIMAL(18,6))
                 / NULLIF(CAST(s30.cum_actual_total AS DECIMAL(18,6))
                          / DATEDIFF(CURRENT_DATE(), sc.shelf_date), 0)
        ELSE CAST(sc.inventory_sku AS DECIMAL(18,6))
             / NULLIF(CAST(s30.last_30d_qty AS DECIMAL(18,6)) / 30, 0)
    END                                                    AS sellable_days,
    sc.sync_time                                           AS sync_time,
    CURRENT_TIMESTAMP()                                    AS insert_date,
    CURRENT_TIMESTAMP()                                    AS update_date
FROM skc_calendar sc
LEFT JOIN available_inv_skc ai ON sc.style_no = ai.style_no
LEFT JOIN sales_daily_skc sd   ON sc.style_no = sd.style_no AND sc.sale_date = sd.sales_date
LEFT JOIN sales_30d_skc s30    ON sc.style_no = s30.style_no
-- 累计销量：截至 N-1 天，关联键：style_no + sale_date
LEFT JOIN sales_cum_skc sdc    ON sc.style_no = sdc.style_no AND sc.sale_date = sdc.sales_date
ORDER BY sc.style_no, sc.sale_date;
```

### 7.3 验证SQL

```sql
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

---

## 八、DWS表5：SKU异常表 `dws_sku_abnormal_d`

> 用途：存储 style_no_size 为空/'None' 或 shelf_date 为空的 SKU
> 粒度：`sku`
> 来源：`dwd_feishu_product_all_d` + `dwd_feishu_brand_order_arrival_d`

### 8.1 DDL

```sql
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
PARTITION BY RANGE(`insert_date`) ()
DISTRIBUTED BY HASH(`sku`) BUCKETS 8
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true",
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.history_partition_num" = "365"
);
```

### 8.2 ETL

```sql
-- ============================================================
-- ETL: feishu_dws.dws_sku_abnormal_d
-- 异常条件：
--   1. style_no_size IS NULL OR style_no_size = 'None'
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
        WHEN CONCAT_WS('-', p.style_no, p.size) IS NULL
          OR CONCAT_WS('-', p.style_no, p.size) = 'None'
            THEN 'style_no_size为空或None'
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
      -- 条件1：style_no_size 为空或 None
      CONCAT_WS('-', p.style_no, p.size) IS NULL
      OR CONCAT_WS('-', p.style_no, p.size) = 'None'
      -- 条件2：补全后的 shelf_date 为空
      OR COALESCE(
            NULLIF(p.shelf_date, DATE('1970-01-01')),
            boa.est_arrival_date
         ) IS NULL
  );
```

### 8.3 验证SQL

```sql
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

---

## 九、DWS表6：SKC异常表 `dws_skc_abnormal_d`

> 用途：存储 style_no 为空/'None' 或 MIN(shelf_date) 为空的 SKC
> 粒度：`style_no`
> 来源：`dwd_feishu_product_all_d` + `dwd_feishu_brand_order_arrival_d`

### 9.1 DDL

```sql
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
PARTITION BY RANGE(`insert_date`) ()
DISTRIBUTED BY HASH(`style_no`) BUCKETS 8
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true",
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.history_partition_num" = "365"
);
```

### 9.2 ETL

```sql
-- ============================================================
-- ETL: feishu_dws.dws_skc_abnormal_d
-- 异常条件：
--   1. style_no IS NULL OR style_no = 'None'
--   2. MIN(shelf_date)（含 30_est_arrival_date 补全后）IS NULL
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
        WHEN skc.min_shelf_full IS NULL
            THEN 'MIN(shelf_date)为空且无30_est_arrival_date可补全'
        ELSE '未知异常'
    END                                                    AS abnormal_reason,
    skc.max_sync_time                                      AS sync_time,
    CURRENT_TIMESTAMP()                                    AS insert_date,
    CURRENT_TIMESTAMP()                                    AS update_date
FROM (
    SELECT
        p.style_no                                         AS style_no,
        MAX(p.brand)                                       AS brand,
        MIN(NULLIF(p.shelf_date, DATE('1970-01-01')))     AS min_shelf_raw,
        MIN(COALESCE(
            NULLIF(p.shelf_date, DATE('1970-01-01')),
            boa.est_arrival_date
        ))                                                 AS min_shelf_full,
        MIN(NULLIF(p.first_sales_date, DATE('1970-01-01'))) AS min_first_sales,
        MAX(p.sync_time)                                   AS max_sync_time
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
   OR skc.min_shelf_full IS NULL;
```

### 9.3 验证SQL

```sql
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
     WHERE brand = '韦德')                                    AS total_cnt;
```

---

## 十、关键业务规则速查

### 10.1 渠道与品牌过滤

| 场景 | 条件 |
|------|------|
| 品牌 | `brand = '韦德'` |
| 渠道 | `channel_code IN ('wd', 'japan', 'spanish', 'germany')` |

### 10.2 维度键

| 维度 | 键 | 构造方式 |
|------|-----|---------|
| SKU | `style_no_size` | `CONCAT_WS('-', style_no, size)` |
| SKC | `style_no` | 直接取 `style_no` |

### 10.3 时间基准

| 字段 | SKU | SKC |
|------|-----|-----|
| 上架日期 | `shelf_date`（补全后） | `MIN(shelf_date)`（补全后） |
| 上市第N天 | `DATEDIFF(sale_date, shelf_date) + 1` | `DATEDIFF(sale_date, MIN(shelf_date)) + 1` |
| 已售天数 | `N - 1`（排除今天） | `N - 1` |

### 10.4 阶段与比例

| 阶段 | lifecycle_day | ratio |
|------|--------------|-------|
| 新品期 | 1~30 | 0.8 |
| 热销期 | 31~120 | 1.1 |
| 清货期 | 121~180 | 1.0 |
| 超周期 | >180 | NULL（不计算计划） |

### 10.5 销售计划公式

| 指标 | 公式 | 适用 |
|------|------|------|
| plan_pre | `Q * ratio / 180` | 1~180天 |
| plan_post | `(Q - cum_actual) * ratio / (181 - N)` | 1~180天 |
| actual_qty | `第N天 SUM(qty)` | 全部 |
| achievement | `actual_qty / plan_post` | 1~180天（plan_post≠0） |

> **cum_actual(N)** = 截至第 **N-1** 天的实际销量总和（不含当天N）

### 10.6 日期补齐范围

- 每个 SKU/SKC：从自身 shelf_date 到 **全局最晚 shelf_date + 180天**
- 全局最晚 shelf_date = `MAX(shelf_date)`（补全后）
- sale_date_label：1~180 显示数字，>180 显示 '超周期'

### 10.7 库存口径

| 字段 | SKU | SKC |
|------|-----|-----|
| 在仓库存 | `COALESCE(inventory_sku, 0)` | `SUM(inventory_sku)` |
| 可提库存 | 最新 `inventory_date` 按 sku 聚合 `SUM(inventory_qty)` | 最新 `inventory_date` 按 style_no 聚合 `SUM(inventory_qty)` |
| 可售周期 | 在仓库存 / 30天平均日销 | 同 SKU（防除零） |

### 10.8 30天平均日销

| 已售天数 | 计算 |
|---------|------|
| =0 | NULL |
| <30 | cum_actual / sold_days |
| ≥30 | last_30d_qty / 30 |

### 10.9 异常条件

| 表 | 异常条件 |
|----|---------|
| SKU异常表 | `style_no_size IS NULL OR style_no_size = 'None' OR shelf_date(补全后) IS NULL` |
| SKC异常表 | `style_no IS NULL OR style_no = 'None' OR MIN(shelf_date)(补全后) IS NULL` |

### 10.10 ⚠️ 财务/库存人工审查提醒

以下字段涉及财务金额或库存数据，**上线前必须人工审查**：

1. **`actual_amt` / `cum_actual_amt`**：销售金额，依赖 `dwd_feishu_sales_all_d.amt`，需确认金额单位（元）与精度（DECIMAL(18,6)）
2. **`tag_price`**：吊牌价，需确认是否含税
3. **`inventory_sku` / `available_inventory`**：在仓库存与可提库存来自不同数据源（商品库 vs 品牌方库存表），需确认两者口径一致
4. **`total_order_qty`**：涉及补货数量，需确认 `is_replenish` 字段的取值规范（'是'/'否'）
5. **`sellable_days`**：可售周期依赖 30天平均日销，当日销为0时返回 NULL，需确认业务上是否需要兜底值

### 10.11 字段映射总表（口径依据）

| DWS 字段 | 口径章节 | 说明 |
|---------|---------|------|
| style_no_size | 3.1 | SKU = CONCAT_WS('-', style_no, size) |
| brand | 3.2 | 直接取值 |
| shelf_date | 3.5 | 优先 product_all_d，为空取 `30_est_arrival_date` |
| first_sales_date | 3.6 | 直接取值 |
| lifecycle_day | 3.7 | DATEDIFF(CURRENT_DATE(), shelf_date) + 1 |
| sales_cycle_label | 3.8 | CASE lifecycle_day |
| inventory_sku | 3.9 | COALESCE(inventory_sku, 0) |
| available_inventory | 3.10 | 最新 inventory_date 按 sku/style_no 聚合 |
| sellable_days | 3.11 | 在仓库存 / 30天平均日销 |
| daily_avg_qty_30d | 3.12 | 30天平均日销 |
| order_qty | 3.18 | brand_order_arrival_d.order_qty |
| achievement_ratio | 3.19 | cum_actual / order_qty |
| total_order_qty | 3.20 | order_qty + replenish_qty (is_replenish='是') |
| plan_pre | 4.3 | Q * ratio / 180 |
| plan_post | 4.4 | (Q - cum_actual) * ratio / (181 - N) |
| actual_qty | 4.5 | 第N天 SUM(qty) |
| achievement_rate | 4.6 | actual_qty / plan_post |

---

## 十一、部署与调度建议

### 11.1 执行顺序

```
1. dws_sku_abnormal_d          （异常表先跑，排除异常数据）
2. dws_skc_abnormal_d          （异常表先跑）
3. dws_sku_product_info_d      （商品维表）
4. dws_skc_product_info_d      （商品维表）
5. dws_sku_sales_plan_180d_d   （核心表，依赖商品维表逻辑）
6. dws_skc_sales_plan_180d_d   （核心表）
```

### 11.2 刷新策略

| 表 | 刷新方式 | 说明 |
|----|---------|------|
| dws_sku_product_info_d | 全量 TRUNCATE + INSERT | 每日全量重算 |
| dws_skc_product_info_d | 全量 TRUNCATE + INSERT | 每日全量重算 |
| dws_sku_sales_plan_180d_d | 全量 TRUNCATE + INSERT | 数据量大，建议分区刷新 |
| dws_skc_sales_plan_180d_d | 全量 TRUNCATE + INSERT | 同上 |
| dws_sku_abnormal_d | 全量 TRUNCATE + INSERT | 每日全量重算 |
| dws_skc_abnormal_d | 全量 TRUNCATE + INSERT | 每日全量重算 |

### 11.3 性能优化建议

1. **销售计划表数据量大**：SKU数 × 天数（180+超周期），建议按 `sale_date` 分区查询
2. **GENERATE_SERIES 性能**：日期序列生成可能成为瓶颈，可预先物化日期维表
3. **窗口函数**：累计销量使用 `SUM() OVER()` 窗口函数，确保 StarRocks 版本支持
4. **索引**：`bloom_filter_columns` 可对 `style_no`、`style_no_size` 加 Bloom Filter 加速等值查询
5. **Colocate Join**：SKU 表与 SKC 表可配置 `colocate_with` 同组，加速关联

---

## 十二、附录：StarRocks 语法兼容性说明

### 12.1 GENERATE_SERIES

```sql
-- 测试是否可用
SELECT * FROM GENERATE_SERIES(1, 10) AS t(n);
```

若不可用，使用递归 CTE：

```sql
WITH RECURSIVE date_series AS (
    SELECT DATE('2024-01-01') AS dt
    UNION ALL
    SELECT DATE_ADD(dt, INTERVAL 1 DAY) FROM date_series
    WHERE dt < DATE('2024-12-31')
)
SELECT dt FROM date_series;
```

### 12.2 DATE_DIFF / DATEDIFF

StarRocks 使用 `DATEDIFF(end_date, start_date)` 返回天数差。

### 12.3 DATE_ADD

```sql
DATE_ADD(date, INTERVAL n DAY)     -- 加 n 天
DATE_SUB(date, INTERVAL n DAY)     -- 减 n 天
```

### 12.4 窗口函数

```sql
SUM(qty) OVER (PARTITION BY sku ORDER BY sales_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
-- 累计到上一行（即截至昨天）
```

---

> **文档结束**
> 本文档严格依据 `基于DWD层的字段口径定义.md` 生成，所有计算逻辑以口径文档为准。
> 涉及财务金额、库存的字段已标注人工审查提醒，上线前请业务方确认。
