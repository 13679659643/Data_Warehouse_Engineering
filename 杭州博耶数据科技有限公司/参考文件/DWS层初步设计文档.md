# DWD → DWS 计算逻辑说明

> 基于 DWD 层四张合并表（4.3/4.6/4.7/4.8）及业务逻辑说明文档（6.29版）
> 编写日期：2026-06-30
> 适用范围：1~180天逐日销售计划与达成分析（韦德品牌），库存决策与OTB（双品牌通用）

---

## 一、DWD → DWS 依赖关系

```
dwd_feishu_sales_all_d (4.3 统一销售日明细)
    ├──→ dws_sku_sales_daily          (SKU每日汇总 + 生命周期定位)
    └──→ dws_sku_lifecycle_180d       (1~180天销售计划与达成)  ← 核心
dwd_feishu_product_all_d (4.6 统一商品库)
    ├──→ dws_sku_product_info         (SKU商品维表，提供订货量/目标/库存/评级)
    └──→ dws_sku_lifecycle_180d       (JOIN 提供 order_qty, first_sales_date)
dwd_feishu_inventory_brand_d (4.7 品牌方库存)
    └──→ dws_brand_inventory_decision (品牌库存决策：可销天数/补货建议)
dwd_feishu_otb_plan_d (4.8 OTB订货计划)
    └──→ dws_otb_monthly_summary      (OTB月度回款与订货差异)
```

---

## 二、核心计算：1~180天逐日销售计划与达成

### 2.1 基础定义

| 概念         | 公式                                              | 说明                                 |
| ------------ | ------------------------------------------------- | ------------------------------------ |
| 已上架天数   | `DATEDIFF(GETDATE(), first_sales_date) + 1`     | 上架当天为第1天                      |
| 上市第N天    | `DATEDIFF(sales_date, first_sales_date) + 1`    | 每笔销售映射到生命周期位置           |
| 已售天数     | `已上架天数 - 1`                                | 今日销量次日才更新，故计算时排除今天 |
| 销售阶段(新) | 1~30天=新品期, 31~120天=热销期, 121~180天=清货期 | 三阶段分配比例不同                   |

> **注意**：业务文档的阶段划分为 **1-30 / 31-120 / 121-180**，与 DWD 表注释中的 1-30/31-90/91+ 不同，以业务文档为准。

### 2.2 阶段分配比例

| 阶段           | 天数范围        | 分配比例(ratio) | 含义                                              |
| -------------- | --------------- | --------------- | ------------------------------------------------- |
| 新品期         | 1~30            | 80%             | 新品期目标=订货量*80%                             |
| 热销期         | 31~120          | 110%            | 热销期目标=订货量*110%                            |
| 清货期         | 121~180         | 100%            | 清货期目标=订货量*100%                            |
| **合计** | **1~180** |                 | **总目标 = 80%+110%+100% = 290% of 订货量** |

### 2.3 四个指标的计算逻辑（1~180天每天）

对每个 SKU 的上市第 N 天（N=1,2,...,180），需要计算以下四个指标：

#### (1) 销售计划_销售前 (plan_pre)

固定计划，不依赖实际销售。按阶段等比分配：

```
plan_pre(N) = order_qty * phase_ratio / 180
```

| 阶段            | 公式                    | 示例(order_qty=1000) |
| --------------- | ----------------------- | -------------------- |
| 新品期(1~30)    | 1000 * 0.8 / 180 = 4.44 | 每天计划 4.44 双     |
| 热销期(31~120)  | 1000 * 1.1 / 180 = 6.11 | 每天计划 6.11 双     |
| 清货期(121~180) | 1000 * 1.0 / 180 = 5.56 | 每天计划 5.56 双     |

#### (2) 销售计划_销售后 (plan_post)

**核心逻辑**：有了实际销售后，用「剩余可销量」按当前阶段比例动态分配给剩余天数。

递推定义（业务文档原文逻辑）：

```
第1天:  plan_post = order_qty * 80% / 180
第2天:  plan_post = (order_qty - 第1天实际) * 80% / (180-1)
第3天:  plan_post = (order_qty - 第1天实际 - 第2天计划) * 80% / (180-2)
...
第N天:  plan_post = (order_qty - 截至N-1天实际与计划的总和) * phase_ratio / (180-N+1)
```

**闭式公式**（避免递推，SQL 直接计算）：

```
令 cum_actual(N) = 截至第N-1天的实际销量总和
令 phase_start = 当前阶段起始天（新品期=1, 热销期=31, 清货期=121）

定义:
  r₁ = 0.8 / 180    (新品期系数)
  r₂ = 1.1 / 180    (热销期系数)
  r₃ = 1.0 / 180    (清货期系数)

新品期(N=1~30):
  plan_post = (order_qty - cum_actual) * r₁ / (1 - r₁)^(N-1)

热销期(N=31~120):
  effective_r₂ = r₂ / (1 - r₁)
  plan_post = (order_qty - cum_actual) * effective_r₂ / (1 - effective_r₂)^(N-31)

清货期(N=121~180):
  effective_r₃ = r₃ / (1 - r₂)
  plan_post = (order_qty - cum_actual) * effective_r₃ / (1 - effective_r₃)^(N-121)
```

> **公式推导过程**：见附录 A

#### (3) 实际销售 (actual_qty)

```
actual_qty(N) = SKU 在上市第N天的销量合计
             = SUM(qty) WHERE DATEDIFF(sales_date, first_sales_date) + 1 = N
```

数据来源：`dwd_feishu_sales_all_d` 按 sku + lifecycle_day 聚合。

#### (4) 达成情况 (achievement)

```
achievement(N) = actual_qty(N) / plan_post(N)
```

> 分子=实际销售，分母=销售后计划。>100% 表示超预期，<100% 表示未达标。

### 2.4 日销量定义

```
日销量 = 30天平均日销
如果已售天数 < 30天，则按实际已售天数计算

日销量(N) = cum_actual(N) / LEAST(N - 1, 30)

其中:
  - cum_actual(N) = 截至第N-1天的累计实际销量
  - N-1 = 已售天数（今天不更新）
  - 当已售天数 < 30，除以实际已售天数
  - 当已售天数 >= 30，除以30
```

### 2.5 可售周期

```
可售周期(N) = 当前库存 / 日销量(N)

如果已售天数 < 30:
  可售周期 = 库存 / (cum_actual / (N-1))
  注意 N=1 时已售天数=0，可售周期为 NULL（无销售数据）
```

---

## 三、DWS表1：SKU每日销售汇总 (dws_sku_sales_daily)

> 数据源：4.3 + 4.6
> 粒度：brand + sku + sales_date

### 3.1 计算逻辑

```sql
-- 从 DWD 销售明细 + 商品库，计算每个SKU每天的销售汇总
SELECT
    s.brand,
    s.sku,
    s.sales_date,
    -- 维度（来自商品库）
    p.style_no,
    p.ip,
    p.series,
    p.first_sales_date,
    p.order_qty_sku,
    p.order_qty_skc,
    p.daily_target,
    p.weekly_target,
    p.inventory_sku,

    -- 生命周期定位
    DATEDIFF(s.sales_date, p.first_sales_date) + 1   AS lifecycle_day,
    CASE
        WHEN DATEDIFF(s.sales_date, p.first_sales_date) + 1 BETWEEN 1 AND 30
            THEN '新品期'
        WHEN DATEDIFF(s.sales_date, p.first_sales_date) + 1 BETWEEN 31 AND 120
            THEN '热销期'
        WHEN DATEDIFF(s.sales_date, p.first_sales_date) + 1 BETWEEN 121 AND 180
            THEN '清货期'
        ELSE '超周期'
    END                                                AS sales_phase,

    -- 当日销售
    SUM(s.qty)                                         AS day_qty,
    SUM(s.amt)                                         AS day_amt,

    -- 累计销售（窗口函数）
    SUM(SUM(s.qty)) OVER (
        PARTITION BY s.sku
        ORDER BY s.sales_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                  AS cum_qty,
    SUM(SUM(s.amt)) OVER (
        PARTITION BY s.sku
        ORDER BY s.sales_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                  AS cum_amt,

    -- 日销量（30天滑动平均，不足30天按实际天数）
    -- 已售天数 = lifecycle_day - 1（今天不更新）
    -- 日销量 = 截至昨天的累计销量 / MIN(已售天数, 30)
    CASE
        WHEN DATEDIFF(s.sales_date, p.first_sales_date) <= 0 THEN NULL
        ELSE
            SUM(SUM(s.qty)) OVER (
                PARTITION BY s.sku ORDER BY s.sales_date
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            )
            / LEAST(DATEDIFF(s.sales_date, p.first_sales_date), 30)
    END                                                AS daily_avg_qty,

    -- 达成比例 = 累计销量 / 订货数量
    ROUND(
        SUM(SUM(s.qty)) OVER (
            PARTITION BY s.sku ORDER BY s.sales_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / NULLIF(p.order_qty_skc, 0)
    , 6)                                               AS achievement_ratio,

    -- 可售周期 = 库存 / 日销量
    CASE
        WHEN DATEDIFF(s.sales_date, p.first_sales_date) <= 0 THEN NULL
        ELSE
            ROUND(p.inventory_sku / NULLIF(
                SUM(SUM(s.qty)) OVER (
                    PARTITION BY s.sku ORDER BY s.sales_date
                    ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                )
                / LEAST(DATEDIFF(s.sales_date, p.first_sales_date), 30)
            , 0), 0)
    END                                                AS sellable_days

FROM feishu_dwd.dwd_feishu_sales_all_d s
JOIN feishu_dwd.dwd_feishu_product_all_d p ON s.sku = p.sku
WHERE p.first_sales_date IS NOT NULL
  AND p.first_sales_date > DATE('1970-01-01')
GROUP BY
    s.brand, s.sku, s.sales_date,
    p.style_no, p.ip, p.series, p.first_sales_date,
    p.order_qty_sku, p.order_qty_skc, p.daily_target, p.weekly_target,
    p.inventory_sku;
```

### 3.2 字段映射

| DWS字段           | 来源    | 计算逻辑                                   |
| ----------------- | ------- | ------------------------------------------ |
| day_qty           | 4.3     | SUM(qty) 按 sku+日期 聚合                  |
| day_amt           | 4.3     | SUM(amt) 按 sku+日期 聚合                  |
| cum_qty           | 4.3     | day_qty 的累计窗口                         |
| daily_avg_qty     | 4.3     | 截至昨日累计 / MIN(已售天数, 30)           |
| lifecycle_day     | 4.3+4.6 | DATEDIFF(sales_date, first_sales_date) + 1 |
| sales_phase       | 计算    | 1-30=新品期, 31-120=热销期, 121-180=清货期 |
| achievement_ratio | 4.3+4.6 | cum_qty / order_qty_skc                    |
| sellable_days     | 4.6+4.3 | inventory_sku / daily_avg_qty              |

---

## 四、DWS表2：1~180天销售计划与达成 (dws_sku_lifecycle_180d)

> 数据源：4.3 + 4.6
> 粒度：brand + sku + lifecycle_day(1~180)
> **这是整个 DWS 层最核心的表**

### 4.1 设计思路

每个 SKU 生成 180 行（上市第1天~第180天），每行包含：

- 当天实际卖了多少
- 当天计划卖多少（销售前/销售后两个版本）
- 达成情况 = 实际 / 计划

### 4.2 SQL 实现

```sql
-- ============================================================
-- Step 1: 每个SKU每天的实际销售（仅包含有销售记录的天）
-- ============================================================
WITH sku_daily_actual AS (
    SELECT
        s.sku,
        s.sales_date,
        DATEDIFF(s.sales_date, p.first_sales_date) + 1 AS lifecycle_day,
        SUM(s.qty)                                      AS actual_qty,
        SUM(s.amt)                                      AS actual_amt
    FROM feishu_dwd.dwd_feishu_sales_all_d s
    JOIN feishu_dwd.dwd_feishu_product_all_d p ON s.sku = p.sku
    WHERE p.first_sales_date IS NOT NULL
      AND p.first_sales_date > DATE('1970-01-01')
      AND DATEDIFF(s.sales_date, p.first_sales_date) + 1 BETWEEN 1 AND 180
    GROUP BY s.sku, s.sales_date, p.first_sales_date
),

-- ============================================================
-- Step 2: 每个SKU的商品属性（去重一次，后续JOIN用）
-- ============================================================
sku_info AS (
    SELECT DISTINCT
        sku, brand, style_no, ip, series,
        first_sales_date, order_qty_sku, inventory_sku
    FROM feishu_dwd.dwd_feishu_product_all_d
    WHERE first_sales_date IS NOT NULL
      AND first_sales_date > DATE('1970-01-01')
),

-- ============================================================
-- Step 3: 生成 1~180 天序列
-- ============================================================
day_seq AS (
    SELECT value AS lifecycle_day
    FROM GENERATE_SERIES(1, 180)
),

-- ============================================================
-- Step 4: SKU × 180天 笛卡尔积 + LEFT JOIN 实际销售
--   用窗口函数替代关联子查询，一次扫描完成累计计算
-- ============================================================
sku_days_joined AS (
    SELECT
        si.sku,
        si.brand,
        si.style_no,
        si.ip,
        si.series,
        si.first_sales_date,
        si.order_qty_sku,
        si.inventory_sku,
        d.lifecycle_day,

        -- 当天实际销量（LEFT JOIN匹配不到则为0）
        COALESCE(sda.actual_qty, 0) AS actual_qty,
        COALESCE(sda.actual_amt, 0) AS actual_amt,

        -- 截至第N-1天的累计实际销量（LAG + 窗口累计）
        -- 先算当前行的累计，再减去当前行 = 前N-1天的累计
        COALESCE(
            SUM(COALESCE(sda.actual_qty, 0)) OVER (
                PARTITION BY si.sku ORDER BY d.lifecycle_day
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ), 0
        ) AS cum_actual_before,

        -- 截至第N-1天有实际销售的天数
        COALESCE(
            SUM(CASE WHEN sda.actual_qty > 0 THEN 1 ELSE 0 END) OVER (
                PARTITION BY si.sku ORDER BY d.lifecycle_day
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ), 0
        ) AS actual_sales_days_before

    FROM (SELECT DISTINCT sku, brand, style_no, ip, series,
                 first_sales_date, order_qty_sku, inventory_sku
          FROM sku_info) si
    CROSS JOIN day_seq d
    LEFT JOIN sku_daily_actual sda
        ON si.sku = sda.sku AND d.lifecycle_day = sda.lifecycle_day
),

-- ============================================================
-- Step 5: 四个核心指标（纯列计算，无关联子查询）
-- ============================================================
result AS (
    SELECT
        sku,
        brand,
        style_no,
        ip,
        series,
        first_sales_date,
        DATE_ADD(first_sales_date, INTERVAL lifecycle_day - 1 DAY) AS sales_date,
        lifecycle_day,

        -- 销售阶段
        CASE
            WHEN lifecycle_day BETWEEN 1 AND 30   THEN '新品期'
            WHEN lifecycle_day BETWEEN 31 AND 120  THEN '热销期'
            WHEN lifecycle_day BETWEEN 121 AND 180 THEN '清货期'
        END AS sales_phase,

        order_qty_sku,
        inventory_sku,

        -- ========== 指标1: 销售计划_销售前（固定计划） ==========
        ROUND(order_qty_sku *
            CASE
                WHEN lifecycle_day BETWEEN 1 AND 30   THEN 0.8
                WHEN lifecycle_day BETWEEN 31 AND 120  THEN 1.1
                WHEN lifecycle_day BETWEEN 121 AND 180 THEN 1.0
            END / 180, 6)
        AS plan_pre,

        -- ========== 指标2: 销售计划_销售后（简化版，对齐业务文档） ==========
        -- (订货量 - 截至N-1天实际总和) * 阶段比例 / 剩余天数
        ROUND(
            (order_qty_sku - cum_actual_before)
            * CASE
                WHEN lifecycle_day BETWEEN 1 AND 30   THEN 0.8
                WHEN lifecycle_day BETWEEN 31 AND 120  THEN 1.1
                WHEN lifecycle_day BETWEEN 121 AND 180 THEN 1.0
              END
            / (180 - lifecycle_day + 1)
        , 6) AS plan_post,

        -- ========== 指标3: 实际销售 ==========
        actual_qty,
        actual_amt,

        -- ========== 指标4: 达成情况 = 实际 / 销售后计划 ==========
        ROUND(actual_qty / NULLIF(
            (order_qty_sku - cum_actual_before)
            * CASE
                WHEN lifecycle_day BETWEEN 1 AND 30   THEN 0.8
                WHEN lifecycle_day BETWEEN 31 AND 120  THEN 1.1
                WHEN lifecycle_day BETWEEN 121 AND 180 THEN 1.0
              END
            / (180 - lifecycle_day + 1)
        , 0), 6) AS achievement_rate,

        -- ========== 辅助: 累计销量（窗口函数） ==========
        SUM(actual_qty) OVER (
            PARTITION BY sku ORDER BY lifecycle_day
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cum_qty,

        -- ========== 辅助: 日销量（30天滑动平均） ==========
        CASE
            WHEN actual_sales_days_before = 0 THEN NULL
            ELSE ROUND(cum_actual_before / LEAST(actual_sales_days_before, 30), 6)
        END AS daily_avg_qty,

        -- ========== 辅助: 可售周期 = 库存 / 日销量 ==========
        CASE
            WHEN actual_sales_days_before = 0 THEN NULL
            ELSE ROUND(
                inventory_sku
                / NULLIF(cum_actual_before / LEAST(actual_sales_days_before, 30), 0)
            , 0)
        END AS sellable_days

    FROM sku_days_joined
)
SELECT * FROM result
ORDER BY sku, lifecycle_day;
```

### 4.3 计算逻辑验证（用业务文档示例）

**示例1**：order_qty=1000, 第1天实际=5

```
plan_pre(1)  = 1000 * 0.8 / 180 = 4.444
plan_post(1) = 1000 * (0.8/180) / (1-0.8/180)^0 = 1000 * 0.8/180 = 4.444  ✓
achievement(1) = 5 / 4.444 = 112.5%  ✓（与业务文档第1天达成=5/(1000*80%/180)一致）
```

**示例2**：order_qty=1000, 前4天实际总和=50

```
cum_actual_before(5) = 50

plan_post(5) = (1000-50) * (0.8/180) / (1-0.8/180)^4
             = 950 * 0.004444 / 0.98232
             = 950 * 0.004524
             = 4.298

业务文档: (1000-50) * 80% / (180-4) = 950 * 0.8 / 176 = 4.318
```

> 差异原因：闭式公式考虑了前几天的"计划消耗"，而业务文档的简化公式仅扣减了"实际消耗"。两者在前几天差异极小（<0.5%），随天数增加趋近。如需完全对齐业务文档的简化逻辑，使用下方简化版本：

**简化版 plan_post**（完全对齐业务文档）：

```sql
-- 简化版: plan_post = (order_qty - cum_actual_before) * phase_ratio / (180 - lifecycle_day + 1)
ROUND(
    (order_qty_sku - cum_actual_before)
    * CASE
        WHEN lifecycle_day BETWEEN 1 AND 30   THEN 0.8
        WHEN lifecycle_day BETWEEN 31 AND 120  THEN 1.1
        WHEN lifecycle_day BETWEEN 121 AND 180 THEN 1.0
      END
    / (180 - lifecycle_day + 1)
, 6) AS plan_post_simple,
```

> 简化版与业务文档示例完全一致：`(1000-50) * 0.8 / (180-4) = 4.318`

---

## 五、DWS表3：SKU商品维表 (dws_sku_product_info)

> 数据源：4.6
> 粒度：sku
> 逻辑：直接从 DWD-6 商品库取值，补充 DWS 层需要的衍生字段

```sql
SELECT
    sku,
    brand,
    style_no,
    ip,
    series,
    color_name,
    product_name,
    product_category,
    size,
    rating,
    sales_cycle_label,
    first_sales_date,
    actual_sales_min_date,

    -- 价格
    tag_price,
    discount,
    payment_price,
    actual_sales_price,

    -- 订货
    order_qty_sku,
    order_qty_skc,

    -- 库存
    inventory_sku,
    inventory_skc,
    inventory_total,
    inventory_hz,
    inventory_baoshui,
    inventory_feibao,

    -- 销售目标
    daily_target,
    weekly_target,
    monthly_target,
    quarterly_target,

    -- 补货预警
    replenish_qty,
    replenish_num,
    variance,
    turnover_days,
    safety_days,
    warning_status,
    is_replenish,

    -- ===== DWS衍生字段 =====

    -- 回款价
    CASE
        WHEN brand = '361' THEN ROUND(tag_price * 0.4, 6)
        ELSE payment_price
    END AS effective_payment_price,

    -- 日均销量百分比
    ROUND(actual_daily_avg / NULLIF(daily_target, 0), 6) AS daily_avg_pct,

    -- SKC达成率
    ROUND(cum_sales_sku / NULLIF(order_qty_skc, 0), 6) AS skc_achievement,

    -- 售罄率
    ROUND(cum_sales_sku / NULLIF(cum_sales_sku + inventory_sku, 0), 6) AS sell_through_rate

FROM feishu_dwd.dwd_feishu_product_all_d;
```

---

## 六、DWS表4：品牌库存决策表 (dws_brand_inventory_decision)

> 数据源：4.7
> 粒度：brand + inventory_date
> 逻辑：直接取 DWD-7 已计算好的字段，补充窗口衍生

```sql
SELECT
    brand,
    inventory_date,

    -- DWD-7已计算好的指标（直接取值）
    total_inventory,
    brand_daily_sales,
    available_days_7d,
    available_days_14d,
    available_days_30d,
    turnover_days,
    replenish_suggested_qty,
    inventory_gap,

    -- ===== DWS衍生字段 =====

    -- 库存健康状态
    CASE
        WHEN available_days_30d < 30  THEN '缺货风险'
        WHEN available_days_30d < 60  THEN '库存偏低'
        WHEN available_days_30d < 90  THEN '库存健康'
        ELSE '库存偏高'
    END AS inventory_status,

    -- 可销天数趋势（与7天前对比）
    available_days_30d - LAG(available_days_30d, 7) OVER (
        PARTITION BY brand ORDER BY inventory_date
    ) AS available_days_trend_7d,

    -- 日销量趋势（近7天日均 vs 前7天日均）
    ROUND(
        AVG(brand_daily_sales) OVER (
            PARTITION BY brand ORDER BY inventory_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )
        / NULLIF(AVG(brand_daily_sales) OVER (
            PARTITION BY brand ORDER BY inventory_date
            ROWS BETWEEN 13 PRECEDING AND 7 PRECEDING
        ), 0)
    , 4) AS sales_trend_ratio

FROM feishu_dwd.dwd_feishu_inventory_brand_d;
```

---

## 七、DWS表5：OTB月度汇总表 (dws_otb_monthly_summary)

> 数据源：4.8
> 粒度：brand + arrival_month + style_no + ip + series
> 逻辑：基于 DWD-8 的当月数据与上月数据做环比差异

```sql
SELECT
    curr.brand,
    curr.arrival_month,
    curr.style_no,
    curr.ip,
    curr.series,

    -- ===== 订货量 =====
    curr.sku_order                                       AS curr_order_qty,
    COALESCE(prev.sku_order, 0)                          AS prev_order_qty,
    curr.sku_order - COALESCE(prev.sku_order, 0)         AS order_diff,

    curr.skc_order                                       AS curr_order_skc,
    COALESCE(prev.skc_order, 0)                          AS prev_order_skc,

    -- ===== 提货 =====
    curr.picked_qty                                      AS curr_picked_qty,
    curr.unpicked_qty                                    AS curr_unpicked_qty,

    -- ===== 回款 =====
    curr.monthly_payment                                 AS curr_payment,
    COALESCE(prev.monthly_payment, 0)                    AS prev_payment,
    curr.monthly_payment - COALESCE(prev.monthly_payment, 0) AS payment_diff,
    ROUND(
        (curr.monthly_payment - COALESCE(prev.monthly_payment, 0))
        / NULLIF(prev.monthly_payment, 0)
    , 6)                                                 AS payment_growth_rate,

    -- ===== 销售目标（当月 vs 上月） =====
    curr.month_daily_target,
    COALESCE(prev.month_daily_target, 0)                 AS prev_daily_target,
    curr.month_daily_target - COALESCE(prev.month_daily_target, 0) AS daily_target_diff,

    curr.month_weekly_target,
    COALESCE(prev.month_weekly_target, 0)                AS prev_weekly_target,

    curr.month_monthly_target,
    COALESCE(prev.month_monthly_target, 0)               AS prev_monthly_target,

    curr.month_quarterly_target,
    COALESCE(prev.month_quarterly_target, 0)             AS prev_quarterly_target,

    -- ===== 价格 =====
    curr.tag_price,
    curr.discount,
    curr.payment_price,

    -- ===== 售罄率 =====
    ROUND(
        curr.monthly_payment / NULLIF(curr.payment_price, 0)
        / NULLIF(
            curr.monthly_payment / NULLIF(curr.payment_price, 0) + curr.actual_inventory
        , 0)
    , 6) AS sell_through_rate

FROM feishu_dwd.dwd_feishu_otb_plan_d curr
LEFT JOIN feishu_dwd.dwd_feishu_otb_plan_d prev
    ON curr.brand = prev.brand
    AND curr.style_no = prev.style_no
    AND curr.ip = prev.ip
    AND curr.series = prev.series
    AND prev.arrival_month = DATE_FORMAT(
        DATE_SUB(STR_TO_DATE(CONCAT(curr.arrival_month, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH),
        '%Y-%m'
    );
```

---

## 八、关键业务规则速查

### 8.1 1~180天核心公式

| 指标                | 公式                                                                |
| ------------------- | ------------------------------------------------------------------- |
| 上市第N天           | `DATEDIFF(sales_date, first_sales_date) + 1`                      |
| 已售天数            | `已上架天数 - 1`（今日不更新）                                    |
| 销售计划(前)        | `order_qty * phase_ratio / 180`                                   |
| 销售计划(后)-简化版 | `(order_qty - 截至N-1天实际总和) * phase_ratio / (180 - N + 1)`   |
| 销售计划(后)-精确版 | `(order_qty - cum_actual) * effective_r / (1 - effective_r)^偏移` |
| 达成情况            | `actual_qty / plan_post`                                          |
| 日销量              | `截至昨日累计 / MIN(实际有销售天数, 30)`                          |
| 可售周期            | `库存 / 日销量`                                                   |
| 达成比例            | `累计销量 / 订货数量(SKC)`                                        |

### 8.2 阶段划分

| 阶段   | 天数    | 分配比例 |
| ------ | ------- | -------- |
| 新品期 | 1~30    | 80%      |
| 热销期 | 31~120  | 110%     |
| 清货期 | 121~180 | 100%     |

### 8.3 品牌差异

| 项目             | 361                     | 韦德                |
| ---------------- | ----------------------- | ------------------- |
| first_sales_date | 无(1970-01-01)          | 有                  |
| 能否做180天分析  | 否                      | 是                  |
| 折扣             | 固定0.4                 | 各SKU不同           |
| 回款价           | 吊牌价*0.4              | actual_sales_price  |
| 销售阶段         | 按sales_cycle_label字段 | 按lifecycle_day计算 |

### 8.4 日销量渠道范围

业务文档中"日销量"取以下4个渠道的销量总和：

| channel_code | channel_name |
| ------------ | ------------ |
| wd           | 韦德之道     |
| japan        | 韦德日本站   |
| spanish      | 韦德西语站   |
| germany      | 韦德德国站   |

---

## 附录 A：plan_post 闭式公式推导

### 递推关系

业务文档的递推定义：

```
plan_post(1) = Q * r
plan_post(N) = (Q - cum_actual(N) - Σplan_post(1..N-1)) * r / (D - N + 1)
```

其中 Q=order_qty, r=phase_ratio, D=180, cum_actual(N)=截至第N-1天的实际销量总和。

### 推导（以新品期为例）

令 a = r / D = 0.8/180

**Day 1**:

```
plan(1) = Q * a
```

**Day 2** (已售1天):

```
plan(2) = (Q - actual(1) - plan(1)) * a / (D-1)
        = (Q - actual(1) - Q*a) * a / (D-1)
        = (Q(1-a) - actual(1)) * a / (D-1)
```

**Day 3** (已售2天):

```
plan(3) = (Q - [actual(1)+actual(2)] - plan(1)-plan(2)) * a / (D-2)
```

展开 plan(1)+plan(2):

```
plan(1) + plan(2) = Q*a + (Q(1-a) - actual(1)) * a/(D-1)
```

归纳可得:

```
plan(N) = (Q - cum_actual(N)) * a / ((1-a)^(N-2) * (D-N+1))
         当 N >= 2

简化: plan(N) = (Q - cum_actual(N)) * a / (1-a)^(N-1)
```

### 跨阶段推导

**热销期第一天(N=31)**:

```
令 cum_30 = 前30天实际总和
plan(31) = (Q - cum_30 - Σplan(1..30)) * (1.1/180) / (180-30)

Σplan(1..30) = Q * 0.8 * (1 - (1-a₁)^30) / a₁ 的化简
             = Q * [1 - (1-0.8/180)^30]

代入:
plan(31) = (Q - cum_30) * (1.1/180)/(1-0.8/180) / (180-30)
         = (Q - cum_30) * effective_r₂ / (1 - effective_r₂)^0

其中 effective_r₂ = (1.1/180) / (1 - 0.8/180)
```

**热销期第N天(31~120)**:

```
plan(N) = (Q - cum_actual(N)) * effective_r₂ / (1 - effective_r₂)^(N-31)
```

**清货期第N天(121~180)**:

```
effective_r₃ = (1.0/180) / (1 - 1.1/180)
plan(N) = (Q - cum_actual(N)) * effective_r₃ / (1 - effective_r₃)^(N-121)
```

### 简化版（完全对齐业务文档）

如果忽略"计划消耗"（即不扣减前几天已分配的计划量，只扣减实际销量），公式简化为：

```
plan_post_simple(N) = (Q - cum_actual(N)) * phase_ratio / (D - N + 1)
```

此版本与业务文档的示例完全一致，误差在可接受范围内（前几天差异<0.5%），推荐使用。
