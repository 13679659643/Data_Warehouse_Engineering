# QuickBI 数据集解决方案（ADS → QuickBI 数据集查询SQL）

> 编写日期：2026-07-13
> 适用范围：韦德品牌4个核心渠道 `channel_code IN ('wd', 'japan', 'spanish', 'germany')`
> 数据基座：ADS层2张核心表（均带 `feishu_ads.` 前缀）
> 口径依据：`杭州博耶数据科技有限公司/指标口径/基于DWD层的字段口径定义.md`、`杭州博耶数据科技有限公司/库存销售计划/ADS.md`

---

## 一、方案概述

### 1.1 设计原则

1. **维度分离存储**：`style_no_size`（SKU）和 `style_no`（SKC）分别以两张ADS表存储，不在QuickBI层做汇总
2. **直接来源ADS表**：数据集查询SQL直接来源为ADS表，不额外从其他表写逻辑
3. **AS别名对齐备注**：AS别名直接使用ADS字段的COMMENT备注名称，便于QuickBI直接拖拽展示
4. **缺失字段优先调整数仓**：若QuickBI所需字段在ADS表中缺失，优先调整ADS/DWS层补齐字段，不在QuickBI数据集SQL中拼接其他表

### 1.2 数据集清单

| 数据集 | 数据来源表 | 粒度 | 主维度 | 用途 |
|--------|-----------|------|--------|------|
| SKU数据集 | `feishu_ads.ads_sku_sales_plan_180d_d` | style_no_size + sale_date | `style_no_size` | QuickBI展示SKU维度1~180天销售计划 |
| SKC数据集 | `feishu_ads.ads_skc_sales_plan_180d_d` | style_no + sale_date | `style_no` | QuickBI展示SKC维度1~180天销售计划 |

---

## 二、SKU数据集完整查询SQL

> 数据来源：`feishu_ads.ads_sku_sales_plan_180d_d`
> 粒度：`style_no_size + sale_date`（一行 = 一个SKU的一天）
> AS别名：直接使用ADS字段COMMENT备注名称

```sql
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
    `total_order_qty`          AS `总订货数量`
FROM feishu_ads.ads_sku_sales_plan_180d_d;
```

---

## 三、SKC数据集完整查询SQL

> 数据来源：`feishu_ads.ads_skc_sales_plan_180d_d`
> 粒度：`style_no + sale_date`（一行 = 一个SKC的一天）
> AS别名：直接使用ADS字段COMMENT备注名称
> 与SKU数据集差异：无 `尺码`、`配色名` 字段，库存字段为 `inventory_skc`

```sql
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
    `total_order_qty`          AS `SKC总订货数量`
FROM feishu_ads.ads_skc_sales_plan_180d_d;
```

---

## 四、字段映射表

### 4.1 必需字段覆盖情况（SKU数据集）

| 序号 | 必需字段 | ADS字段 | AS别名 | 是否已覆盖 | 口径章节 |
|------|---------|---------|--------|-----------|---------|
| 1 | style_no_size | `style_no_size` | `SKU编码` | ✅ | 3.1 |
| 2 | 系列 | `series` | `系列` | ✅ | 3.3 |
| 3 | 上架时间 | `shelf_date` | `上架日期` | ✅ | 3.5 |
| 4 | 在仓库存 | `inventory_sku` | `在仓库存` | ✅ | 3.9 |
| 5 | 可提库存 | `available_inventory` | `可提库存` | ✅ | 3.10 |
| 6 | 日销量 | `daily_qty` | `日销量` | ✅ | 3.14 / 4.5 |
| 7 | 系列日销 | — | `系列日销` | **就是销量总计** | qbi |
| 8 | 累计销量 | `cum_qty` | `累计销量` | ✅ | 3.16 |
| 9 | 金额 | `daily_amt` | `日金额` | ✅ | 3.15 |
| 10 | 达成比例 | `achievement_ratio` | `达成比例` | ✅ | 3.19 |
| 11 | 昨日销售达成情况 | `yesterday_achievement` | `昨日销售达成情况` | ✅ | 3.22 |
| 12 | 7天销售达成情况 | `7d_achievement` | `7天销售达成情况` | ✅ | 3.23 |
| 13 | 30天销售达成情况 | `30d_achievement` | `30天销售达成情况` | ✅ | 3.24 |
| 14 | 订货数量 | `order_qty` | `订货数量` | ✅ | 3.18 |
| 15 | 昨日实际销售 | `yesterday_actual_qty` | `昨日实际销售` | ✅ | 3.21 |

### 4.2 必需字段覆盖情况（SKC数据集）

| 序号 | 必需字段 | ADS字段 | AS别名 | 是否已覆盖 | 口径章节 |
|------|---------|---------|--------|-----------|---------|
| 1 | style_no | `style_no` | `SKC编码` | ✅ | 5.1 |
| 2 | 系列 | `series` | `系列` | ✅ | 5.3 |
| 3 | 上架时间 | `shelf_date` | `SKC上架日期` | ✅ | 5.5 |
| 4 | 在仓库存 | `inventory_skc` | `SKC在仓库存` | ✅ | 5.9 |
| 5 | 可提库存 | `available_inventory` | `SKC可提库存` | ✅ | 5.10 |
| 6 | 日销量 | `daily_qty` | `日销量` | ✅ | 5.14 / 6.5 |
| 7 | 系列日销 | — | `系列日销` | **就是销量总计** | qbi |
| 8 | 累计销量 | `cum_qty` | `累计销量` | ✅ | 5.16 |
| 9 | 金额 | `daily_amt` | `日金额` | ✅ | 5.15 |
| 10 | 达成比例 | `achievement_ratio` | `SKC达成比例` | ✅ | 5.19 |
| 11 | 昨日销售达成情况 | `yesterday_achievement` | `昨日销售达成情况` | ✅ | 5.22 |
| 12 | 7天销售达成情况 | `7d_achievement` | `7天销售达成情况` | ✅ | 5.23 |
| 13 | 30天销售达成情况 | `30d_achievement` | `30天销售达成情况` | ✅ | 5.24 |
| 14 | 订货数量 | `order_qty` | `SKC订货数量` | ✅ | 5.18 |
| 15 | 昨日实际销售 | `yesterday_actual_qty` | `昨日实际销售` | ✅ | 5.21 |

### 4.3 扩展字段清单（额外包含的ADS字段）

除必需字段外，查询SQL还包含以下扩展字段，用于QuickBI多维分析：

| 分类 | SKU数据集字段 | SKC数据集字段 | AS别名 | 用途 |
|------|-------------|-------------|--------|------|
| 商品属性 | `style_no` | — | `款号` | SKU关联SKC |
| 商品属性 | `brand` | `brand` | `品牌` | 品牌筛选 |
| 商品属性 | `ip` | `ip` | `IP` | IP筛选 |
| 商品属性 | `size` | — | `尺码` | 尺码筛选 |
| 商品属性 | `color_name` | — | `配色名` | 配色筛选 |
| 商品属性 | `product_name` | `product_name` | `商品名称` | 展示商品名称 |
| 商品属性 | `category` | `category` | `品类` | 品类筛选 |
| 商品属性 | `tag_price` | `tag_price` | `吊牌价` | 展示吊牌价 |
| 商品属性 | `first_sales_date` | `first_sales_date` | `首次销售日期` | 首次销售时间 |
| 时间维度 | `sale_date` | `sale_date` | `销售日期` | 时间筛选/分区裁剪 |
| 时间维度 | `lifecycle_day` | `lifecycle_day` | `上市第N天` | 1~180天范围筛选 |
| 时间维度 | `sale_date_label` | `sale_date_label` | `销售日期标签` | "第N天"展示 |
| 时间维度 | `sales_phase` | `sales_phase` | `销售阶段` | 阶段筛选 |
| 时间维度 | `is_over_cycle` | `is_over_cycle` | `是否超周期` | 超周期过滤 |
| 销售计划 | `plan_pre` | `plan_pre` | `销售计划(销售前)` | 1~180天计划展示 |
| 销售计划 | `plan_post` | `plan_post` | `销售计划(销售后)` | 1~180天计划展示 |
| 实际销售 | `cum_amt` | `cum_amt` | `累计金额` | 累计金额展示 |
| 达成情况 | `achievement_rate` | `achievement_rate` | `达成情况` | 日达成率趋势 |
| 库存指标 | `daily_avg_qty_30d` | `daily_avg_qty_30d` | `30天平均日销` / `SKC30天平均日销` | 30天日销展示 |
| 库存指标 | `sellable_days` | `sellable_days` | `可售周期天数` / `SKC可售周期天数` | 可售周期预警 |
| 当前快照 | `today_plan_qty` | `today_plan_qty` | `今日计划销售数量` | 今日计划展示 |
| 订货指标 | `total_order_qty` | `total_order_qty` | `总订货数量` / `SKC总订货数量` | 总订货展示 |

---

## 五、QuickBI数据集字段配置

### 5.1 维度字段配置（用于筛选/分组）

#### 5.1.1 SKU数据集维度字段

| AS别名 | ADS字段 | QuickBI字段类型 | 分组 | 说明 |
|--------|---------|----------------|------|------|
| `SKU编码` | style_no_size | 文本 | 主维度 | SKU主键，文本搜索筛选 |
| `款号` | style_no | 文本 | 商品属性 | SKU关联SKC |
| `品牌` | brand | 文本 | 商品属性 | 固定"韦德" |
| `系列` | series | 文本 | 商品属性 | 多选筛选 |
| `IP` | ip | 文本 | 商品属性 | 多选筛选 |
| `尺码` | size | 文本 | 商品属性 | 尺码筛选 |
| `配色名` | color_name | 文本 | 商品属性 | 配色筛选 |
| `商品名称` | product_name | 文本 | 商品属性 | 展示用 |
| `品类` | category | 文本 | 商品属性 | 品类筛选 |
| `上架日期` | shelf_date | 日期 | 商品属性 | 日期范围筛选 |
| `首次销售日期` | first_sales_date | 日期 | 商品属性 | 日期范围筛选 |
| `销售日期` | sale_date | 日期 | 时间维度 | 分区键，时间范围筛选 |
| `上市第N天` | lifecycle_day | 数值 | 时间维度 | 1~180范围筛选 |
| `销售日期标签` | sale_date_label | 文本 | 时间维度 | "第N天"展示 |
| `销售阶段` | sales_phase | 文本 | 阶段维度 | 新品期/热销期/清货期/超周期 |
| `是否超周期` | is_over_cycle | 数值 | 阶段维度 | 0=正常, 1=超周期 |

#### 5.1.2 SKC数据集维度字段

| AS别名 | ADS字段 | QuickBI字段类型 | 分组 | 说明 |
|--------|---------|----------------|------|------|
| `SKC编码` | style_no | 文本 | 主维度 | SKC主键，文本搜索筛选 |
| `品牌` | brand | 文本 | 商品属性 | 固定"韦德" |
| `系列` | series | 文本 | 商品属性 | 多选筛选 |
| `IP` | ip | 文本 | 商品属性 | 多选筛选 |
| `商品名称` | product_name | 文本 | 商品属性 | 展示用 |
| `品类` | category | 文本 | 商品属性 | 品类筛选 |
| `SKC上架日期` | shelf_date | 日期 | 商品属性 | MIN(shelf_date) |
| `SKC首次销售日期` | first_sales_date | 日期 | 商品属性 | MIN(first_sales_date) |
| `销售日期` | sale_date | 日期 | 时间维度 | 分区键 |
| `上市第N天` | lifecycle_day | 数值 | 时间维度 | 1~180范围筛选 |
| `销售日期标签` | sale_date_label | 文本 | 时间维度 | "第N天"展示 |
| `销售阶段` | sales_phase | 文本 | 阶段维度 | 新品期/热销期/清货期/超周期 |
| `是否超周期` | is_over_cycle | 数值 | 阶段维度 | 0=正常, 1=超周期 |

> **与SKU数据集差异**：SKC数据集无 `款号`、`尺码`、`配色名` 字段（已聚合到style_no维度）

### 5.2 度量字段配置（用于聚合/计算）

#### 5.2.1 SKU数据集度量字段

| AS别名 | ADS字段 | QuickBI聚合方式 | 分组 | 说明 |
|--------|---------|----------------|------|------|
| `吊牌价` | tag_price | MAX | 商品属性 | ⚠️ 财务字段 |
| `销售计划(销售前)` | plan_pre | SUM | 销售计划 | 1~180天计划，超周期为NULL |
| `销售计划(销售后)` | plan_post | SUM | 销售计划 | 1~180天计划，超周期为NULL |
| `日销量` | daily_qty | SUM | 实际销售 | 按sale_date汇总 |
| `日金额` | daily_amt | SUM | 实际销售 | ⚠️ 财务字段 |
| `累计销量` | cum_qty | MAX | 累计指标 | 同一SKU同一日期仅一行，取MAX |
| `累计金额` | cum_amt | MAX | 累计指标 | ⚠️ 财务字段 |
| `达成情况` | achievement_rate | AVG | 达成指标 | 日达成率 |
| `达成比例` | achievement_ratio | MAX | 订货指标 | 累计销量/订货数量 |
| `在仓库存` | inventory_sku | MAX | 库存指标 | ⚠️ 快照值，取MAX |
| `可提库存` | available_inventory | MAX | 库存指标 | ⚠️ 快照值，取MAX |
| `30天平均日销` | daily_avg_qty_30d | MAX | 库存指标 | 快照值 |
| `可售周期天数` | sellable_days | MAX | 库存指标 | ⚠️ 日销为0时NULL |
| `昨日实际销售` | yesterday_actual_qty | MAX | 当前快照 | 同一SKU所有行值相同 |
| `昨日销售达成情况` | yesterday_achievement | MAX | 当前快照 | 同一SKU所有行值相同 |
| `7天销售达成情况` | 7d_achievement | MAX | 当前快照 | 同一SKU所有行值相同 |
| `30天销售达成情况` | 30d_achievement | MAX | 当前快照 | 同一SKU所有行值相同 |
| `今日计划销售数量` | today_plan_qty | MAX | 当前快照 | 超周期为0 |
| `订货数量` | order_qty | MAX | 订货指标 | Q值 |
| `总订货数量` | total_order_qty | MAX | 订货指标 | ⚠️ 含补货 |
| `系列日销` | series_daily_qty | MAX | 系列指标 | 就是销量总计 |

#### 5.2.2 SKC数据集度量字段

| AS别名 | ADS字段 | QuickBI聚合方式 | 分组 | 说明 |
|--------|---------|----------------|------|------|
| `吊牌价` | tag_price | MAX | 商品属性 | ⚠️ 财务字段 |
| `销售计划(销售前)` | plan_pre | SUM | 销售计划 | 1~180天计划 |
| `销售计划(销售后)` | plan_post | SUM | 销售计划 | 1~180天计划 |
| `日销量` | daily_qty | SUM | 实际销售 | 按sale_date汇总 |
| `日金额` | daily_amt | SUM | 实际销售 | ⚠️ 财务字段 |
| `累计销量` | cum_qty | MAX | 累计指标 | 同一SKC同一日期仅一行 |
| `累计金额` | cum_amt | MAX | 累计指标 | ⚠️ 财务字段 |
| `达成情况` | achievement_rate | AVG | 达成指标 | 日达成率 |
| `SKC达成比例` | achievement_ratio | MAX | 订货指标 | SKC累计销量/SKC订货数量 |
| `SKC在仓库存` | inventory_skc | MAX | 库存指标 | ⚠️ SUM(inventory_sku)按style_no聚合 |
| `SKC可提库存` | available_inventory | MAX | 库存指标 | ⚠️ 快照值 |
| `SKC30天平均日销` | daily_avg_qty_30d | MAX | 库存指标 | 快照值 |
| `SKC可售周期天数` | sellable_days | MAX | 库存指标 | ⚠️ 日销为0时NULL |
| `昨日实际销售` | yesterday_actual_qty | MAX | 当前快照 | 同一SKC所有行值相同 |
| `昨日销售达成情况` | yesterday_achievement | MAX | 当前快照 | 同一SKC所有行值相同 |
| `7天销售达成情况` | 7d_achievement | MAX | 当前快照 | 同一SKC所有行值相同 |
| `30天销售达成情况` | 30d_achievement | MAX | 当前快照 | 同一SKC所有行值相同 |
| `今日计划销售数量` | today_plan_qty | MAX | 当前快照 | 超周期为0 |
| `SKC订货数量` | order_qty | MAX | 订货指标 | SUM(order_qty)按style_no聚合 |
| `SKC总订货数量` | total_order_qty | MAX | 订货指标 | ⚠️ 含补货 |
| `系列日销` | series_daily_qty | MAX | 系列指标 | 就是销量总计 |

> **聚合方式说明**：
> - **SUM**：适用于按日期汇总的时间序列指标（销售计划、日销量、日金额）
> - **MAX**：适用于快照型指标（累计、库存、昨日/今日达成），同一SKU/SKC同一日期仅一行，取MAX即可
> - **AVG**：适用于比率类指标（达成情况），多SKU聚合时取平均

### 5.3 ⚠️ 财务/库存字段审查清单

以下字段涉及财务金额或库存数据，QuickBI上线前必须由业务方人工审查：

| AS别名 | ADS字段 | 审查要点 | 口径章节 |
|--------|---------|---------|---------|
| `日金额` | daily_amt | 金额单位（元）、精度DECIMAL(18,6)、是否含税 | 3.15 / 5.15 |
| `累计金额` | cum_amt | 累计金额计算逻辑、时间范围 | 3.17 / 5.17 |
| `吊牌价` | tag_price | 是否含税 | - |
| `在仓库存` / `SKC在仓库存` | inventory_sku / inventory_skc | 在仓库存来源（商品库实时快照） | 3.9 / 5.9 |
| `可提库存` / `SKC可提库存` | available_inventory | 可提库存来源（品牌方库存表最新快照） | 3.10 / 5.10 |
| `总订货数量` / `SKC总订货数量` | total_order_qty | 补货数量逻辑（is_replenish='是'时加replenish_qty） | 3.20 / 5.20 |
| `可售周期天数` / `SKC可售周期天数` | sellable_days | 日销为0时返回NULL的业务展示逻辑 | 3.11 / 5.11 |
| `达成比例` / `SKC达成比例` | achievement_ratio | 分母为0时返回NULL的业务展示逻辑 | 3.19 / 5.19 |

---

## 六、仪表板设计建议

### 6.1 SKU维度仪表板

| 仪表板 | 核心图表 | X轴/维度 | Y轴/度量 | 筛选条件 |
|--------|---------|---------|---------|---------|
| SKU-销售计划概览 | 折线图 | `上市第N天` | `销售计划(销售前)`(SUM)、`销售计划(销售后)`(SUM)、`日销量`(SUM) | `是否超周期`=0，`上市第N天` 1~180 |
| SKU-达成分析 | 组合图 | `上市第N天` | `日销量`(SUM,柱)、`销售计划(后)`(SUM,线)、`达成情况`(AVG,次轴线) | `是否超周期`=0 |
| SKU-当前达成看板 | 指标卡 | — | `昨日销售达成情况`(MAX)、`7天销售达成情况`(MAX)、`30天销售达成情况`(MAX)、`昨日实际销售`(MAX) | `SKU编码`=[选择] |
| SKU-库存预警 | 明细表 | `SKU编码`、`商品名称`、`系列` | `在仓库存`(MAX)、`可提库存`(MAX)、`可售周期天数`(MAX) | `可售周期天数`<30 |
| SKU-系列对比 | 明细表 | `SKU编码`、`系列` | `日销量`(SUM)、`系列日销`(MAX) | `系列`=[选择] |

### 6.2 SKC维度仪表板

| 仪表板 | 核心图表 | X轴/维度 | Y轴/度量 | 筛选条件 |
|--------|---------|---------|---------|---------|
| SKC-销售计划概览 | 折线图 | `上市第N天` | `销售计划(销售前)`(SUM)、`销售计划(销售后)`(SUM)、`日销量`(SUM) | `是否超周期`=0 |
| SKC-达成分析 | 组合图 | `上市第N天` | `日销量`(SUM,柱)、`销售计划(后)`(SUM,线)、`达成情况`(AVG,次轴线) | `是否超周期`=0 |
| SKC-当前达成看板 | 指标卡 | — | `昨日销售达成情况`(MAX)、`7天销售达成情况`(MAX)、`30天销售达成情况`(MAX)、`昨日实际销售`(MAX) | `SKC编码`=[选择] |
| SKC-库存预警 | 明细表 | `SKC编码`、`商品名称`、`系列` | `SKC在仓库存`(MAX)、`SKC可提库存`(MAX)、`SKC可售周期天数`(MAX) | `SKC可售周期天数`<30 |

### 6.3 筛选器配置建议

| 筛选器 | 字段 | 类型 | 默认值 | 作用 |
|--------|------|------|--------|------|
| 品牌 | `品牌` | 单选 | 韦德 | 限定品牌范围 |
| 系列 | `系列` | 多选 | 全选 | 按系列筛选 |
| IP | `IP` | 多选 | 全选 | 按IP筛选 |
| 销售阶段 | `销售阶段` | 多选 | 全选 | 新品期/热销期/清货期/超周期 |
| 上市天数范围 | `上市第N天` | 数值范围 | 1~180 | 限定1~180天展示 |
| 超周期过滤 | `是否超周期` | 单选 | 0 | 默认不展示超周期 |
| SKU/SKC编码 | `SKU编码` / `SKC编码` | 文本搜索 | 空 | 精确查找 |

---

## 七、附录：口径速查

### 7.1 销售阶段定义

| 阶段 | lifecycle_day范围 | ratio | sales_phase |
|------|------------------|-------|-------------|
| 新品期 | 1~30 | 0.8 | 新品期 |
| 热销期 | 31~120 | 1.1 | 热销期 |
| 清货期 | 121~180 | 1.0 | 清货期 |
| 超周期 | >180 | NULL | 超周期 |

### 7.2 销售计划公式

| 指标 | 公式 | 适用范围 |
|------|------|---------|
| 销售计划(销售前) | `Q * ratio / 180` | 1~180天 |
| 销售计划(销售后) | `(Q - cum_actual) * ratio / (181 - N)` | 1~180天 |
| 达成情况 | `daily_qty / plan_post` | 1~180天 |

> - Q = 订货数量
> - cum_actual = 截至第N-1天的实际销量总和
> - N = 上市第N天（lifecycle_day）

### 7.3 维度键定义

| 维度 | 键 | ADS表 |
|------|-----|--------|
| SKU | `style_no_size = CONCAT_WS('-', style_no, size)` | ads_sku_sales_plan_180d_d |
| SKC | `style_no` | ads_skc_sales_plan_180d_d |

### 7.4 超周期展示规则

- 超周期行（lifecycle_day > 180）的 `销售计划(销售前)`、`销售计划(销售后)`、`达成情况` 为 NULL
- 超周期行只展示：日销量、日金额、累计销量、累计金额、在仓库存、可提库存、可售周期天数
- 展示1~180天销售计划时，必须筛选 `是否超周期 = 0`

---

> **文档结束**
> 本文档严格依据 `ADS.md` 和 `基于DWD层的字段口径定义.md` 生成。
> SKU/SKC数据集分别直接查询ADS表，AS别名使用ADS字段备注名称。
> 涉及财务金额、库存的字段已标注⚠️人工审查提醒，上线前请业务方确认。
