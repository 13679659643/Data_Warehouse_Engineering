# QuickBI 达成比例与应达成比例查询SQL

> 编写日期：2026-07-30
> 适用范围：韦德品牌4个核心渠道 `channel_code IN ('wd', 'japan', 'spanish', 'germany')`
> 数据来源：ADS层2张核心表
> - SKU表：`feishu_ads.ads_sku_sales_plan_180d_d`
> - SKC表：`feishu_ads.ads_skc_sales_plan_180d_d`

---

## 一、需求说明

1. **不受时间筛选器影响**：达成比例和应达成比例均基于当前时间计算（使用 current_cum_actual / current_cum_plan_qty / order_qty 三个 SKU/SKC 维度常量字段）
2. **多选筛选器**：ip、series、style_no(即SKC维度)、style_no_size(SKU维度)、sales_phase、sale_date_label、sales_plan_tag、rating，均为多选
3. **表切换逻辑**：
   - 有 `style_no_size` 筛选 → 使用 SKU 表 (`feishu_ads.ads_sku_sales_plan_180d_d`)
   - 无 `style_no_size` 筛选 → 使用 SKC 表 (`feishu_ads.ads_skc_sales_plan_180d_d`)
4. **计算口径**：
   - 达成比例 = 累计销量 / 订货数量 = SUM(current_cum_actual) / SUM(order_qty)
   - 应达成比例 = 累计计划销量 / 订货数量 = SUM(current_cum_plan_qty) / SUM(order_qty)
5. **多选汇总逻辑**：current_cum_actual / current_cum_plan_qty / order_qty 均为 SKU/SKC 维度常量（同一 SKU/SKC 不同 sale_date 值相同），多选时需先按 SKU/SKC 分组取单值（MAX 去重），再对所有 SKU/SKC 求和

---

## 二、占位符说明

| 占位符名 | 变量类型 | 筛选模式 | 说明 |
|---------|---------|---------|------|
| `style_no_size` | 文本 | 多选 | SKU编码筛选，**关键切换字段**（有值用SKU表，无值用SKC表） |
| `style_no` | 文本 | 多选 | SKC编码/款号筛选 |
| `ip` | 文本 | 多选 | IP筛选 |
| `series` | 文本 | 多选 | 系列筛选 |
| `sales_phase` | 文本 | 多选 | 销售阶段筛选（新品期/热销期/清货期/超周期） |
| `sale_date_label` | 文本 | 多选 | 销售日期标签筛选（第N天/超周期） |
| `sales_plan_tag` | 文本 | 多选 | 销售计划标签筛选 |
| `rating` | 文本 | 多选 | 评级筛选 |

### QuickBI 占位符配置要点

1. **style_no_size 占位符**：**不设置默认值**（或设置为空），用于判断是否传值
2. **其他占位符**：建议在 QuickBI 占位符管理中设置"全局生效"的默认值（如选择全部可选值），确保未传值时返回全部数据
3. **多选 IN 语法**：`field IN ('$val{占位符名}')`，QuickBI 会自动将多选值展开为 `'v1','v2','v3'`

---

## 三、完整查询SQL

```sql
-- ============================================================
-- QuickBI 达成比例与应达成比例查询SQL
-- 功能：基于当前时间计算达成比例和应达成比例，不受时间筛选器影响
-- 表切换逻辑：
--   1. 有 style_no_size 筛选 → 使用 SKU 表 (feishu_ads.ads_sku_sales_plan_180d_d)
--   2. 无 style_no_size 筛选 → 使用 SKC 表 (feishu_ads.ads_skc_sales_plan_180d_d)
-- 计算口径：
--   1. 达成比例 = SUM(current_cum_actual) / SUM(order_qty)
--   2. 应达成比例 = SUM(current_cum_plan_qty) / SUM(order_qty)
-- 多选汇总逻辑：
--   current_cum_actual / current_cum_plan_qty / order_qty 均为 SKU/SKC 维度常量
--   先按 SKU/SKC 分组取 MAX（去重，因同一 SKU/SKC 不同 sale_date 值相同）
--   再对所有 SKU/SKC 求和，避免 180 行重复累加
-- ============================================================

WITH 
-- 1. SKU维度数据（有 style_no_size 筛选时生效）
SKU_DATA AS (
    SELECT 
        style_no_size,
        -- 三个维度常量字段：同一 SKU 不同 sale_date 值相同，用 MAX 去重取单值
        MAX(current_cum_actual)   AS current_cum_actual,    -- SKU累计实际销量(当前时间常量)
        MAX(current_cum_plan_qty) AS current_cum_plan_qty,  -- SKU当前累计计划销量(当前时间常量)
        MAX(order_qty)            AS order_qty              -- SKU订货数量Q(当前时间常量)
    FROM feishu_ads.ads_sku_sales_plan_180d_d
    WHERE style_no_size IN ('$val{style_no_size}')           -- 关键筛选：有值时生效，无值时 IN ('') 返回空
        AND ip IN ('$val{ip}')                               -- IP多选筛选
        AND series IN ('$val{series}')                       -- 系列多选筛选
        AND style_no IN ('$val{style_no}')                   -- 款号/SKC编码多选筛选
        AND sales_phase IN ('$val{sales_phase}')             -- 销售阶段多选筛选
        AND sale_date_label IN ('$val{sale_date_label}')     -- 销售日期标签多选筛选
        AND sales_plan_tag IN ('$val{sales_plan_tag}')       -- 销售计划标签多选筛选
        AND rating IN ('$val{rating}')                       -- 评级多选筛选
    GROUP BY style_no_size
),

-- 2. SKC维度数据（无 style_no_size 筛选时生效）
-- 切换原理：通过 NOT EXISTS 判断 style_no_size 占位符是否传值
--   - 未传值时：子查询 IN ('') 无匹配 → NOT EXISTS = TRUE → SKC 表返回数据
--   - 传值时：子查询有匹配 → NOT EXISTS = FALSE → SKC 表返回空
SKC_DATA AS (
    SELECT 
        style_no,
        -- 三个维度常量字段：同一 SKC 不同 sale_date 值相同，用 MAX 去重取单值
        MAX(current_cum_actual)   AS current_cum_actual,    -- SKC累计实际销量(当前时间常量)
        MAX(current_cum_plan_qty) AS current_cum_plan_qty,  -- SKC当前累计计划销量(当前时间常量)
        MAX(order_qty)            AS order_qty              -- SKC订货数量Q(当前时间常量)
    FROM feishu_ads.ads_skc_sales_plan_180d_d
    WHERE NOT EXISTS (
        -- 判断 style_no_size 占位符是否有传值：有匹配说明用户筛选了 SKU
        SELECT 1 
        FROM feishu_ads.ads_sku_sales_plan_180d_d 
        WHERE style_no_size IN ('$val{style_no_size}') 
        LIMIT 1
    )
    AND ip IN ('$val{ip}')                                   -- IP多选筛选
    AND series IN ('$val{series}')                           -- 系列多选筛选
    AND style_no IN ('$val{style_no}')                       -- 款号/SKC编码多选筛选
    AND sales_phase IN ('$val{sales_phase}')                 -- 销售阶段多选筛选
    AND sale_date_label IN ('$val{sale_date_label}')         -- 销售日期标签多选筛选
    AND sales_plan_tag IN ('$val{sales_plan_tag}')           -- 销售计划标签多选筛选
    AND rating IN ('$val{rating}')                           -- 评级多选筛选
    GROUP BY style_no
),

-- 3. 合并SKU与SKC数据（同一时刻只有一方有数据，另一方为空）
UNION_DATA AS (
    SELECT 
        current_cum_actual,
        current_cum_plan_qty,
        order_qty
    FROM SKU_DATA
    UNION ALL
    SELECT 
        current_cum_actual,
        current_cum_plan_qty,
        order_qty
    FROM SKC_DATA
)

-- 4. 最终结果：全局汇总计算两个比例
SELECT 
    -- 中间汇总值（可用于QuickBI展示或调试）
    SUM(current_cum_actual)   AS sum_cum_actual,       -- 累计实际销量汇总
    SUM(current_cum_plan_qty) AS sum_cum_plan_qty,     -- 累计计划销量汇总
    SUM(order_qty)            AS sum_order_qty,        -- 订货数量汇总
    
    -- 核心指标1：达成比例 = 累计销量 / 订货数量
    CASE 
        WHEN SUM(order_qty) > 0 
        THEN ROUND(SUM(current_cum_actual) * 1.0 / SUM(order_qty), 6)
        ELSE NULL 
    END AS achievement_ratio,                           -- 达成比例
    
    -- 核心指标2：应达成比例 = 累计计划销量 / 订货数量
    CASE 
        WHEN SUM(order_qty) > 0 
        THEN ROUND(SUM(current_cum_plan_qty) * 1.0 / SUM(order_qty), 6)
        ELSE NULL 
    END AS should_achieve_ratio                         -- 应达成比例
FROM UNION_DATA;
```

---

## 四、SQL 逻辑说明

### 4.1 表切换原理

利用 QuickBI 多选值占位符的特性：
- **未传值时**：占位符替换为空字符串 `''`，SQL 展开为 `IN ('')`，无数据匹配
- **传值时**：占位符展开为 `'v1','v2','v3'`，SQL 展开为 `IN ('v1','v2','v3')`

**SKU 查询**（有筛选时生效）：
```sql
WHERE style_no_size IN ('$val{style_no_size}')
```
- 未传值 → `IN ('')` → 无匹配 → SKU_DATA 为空
- 传值 → `IN ('v1','v2')` → 有匹配 → SKU_DATA 有数据

**SKC 查询**（无筛选时生效）：
```sql
WHERE NOT EXISTS (
    SELECT 1 FROM feishu_ads.ads_sku_sales_plan_180d_d 
    WHERE style_no_size IN ('$val{style_no_size}') 
    LIMIT 1
)
```
- 未传值 → 子查询 `IN ('')` 无匹配 → NOT EXISTS = TRUE → SKC_DATA 有数据
- 传值 → 子查询有匹配 → NOT EXISTS = FALSE → SKC_DATA 为空

### 4.2 多选汇总原理

`current_cum_actual` / `current_cum_plan_qty` / `order_qty` 三个字段均为 SKU/SKC 维度常量（同一 SKU/SKC 不同 sale_date 值相同），直接 SUM 会因 180 行重复累加导致放大。

**处理步骤**：
1. 先 `GROUP BY style_no_size` / `style_no` 分组
2. 用 `MAX()` 取每个 SKU/SKC 的单值（去重）
3. 外层 `UNION ALL` 合并后，再 `SUM()` 对所有 SKU/SKC 求和

### 4.3 结果输出

最终输出单行全局汇总数据：
- `sum_cum_actual`：累计实际销量汇总
- `sum_cum_plan_qty`：累计计划销量汇总
- `sum_order_qty`：订货数量汇总
- `achievement_ratio`：达成比例（保留6位小数）
- `should_achieve_ratio`：应达成比例（保留6位小数）

---

## 五、QuickBI 配置说明

### 5.1 创建数据集

1. 在 QuickBI 数据源页面，单击"SQL 创建数据集"
2. 粘贴上述完整 SQL
3. 单击"占位符管理"，配置 8 个占位符（见第二章表格）
4. 运行验证，保存数据集

### 5.2 配置查询控件

1. 创建仪表板，添加该数据集
2. 添加查询控件，绑定 8 个占位符
3. 配置为多选模式
4. `style_no_size` 查询控件**不设置默认值**
5. 其他查询控件建议设置默认值为"全选"

### 5.3 配置图表

1. 添加指标看板或交叉表
2. 拖入 `achievement_ratio` 和 `should_achieve_ratio` 字段
3. 配置数值展示格式（百分比，保留2位小数）

---

## 六、注意事项

1. **style_no_size 占位符不要设置默认值**：否则 NOT EXISTS 判断会失效，始终走 SKU 表
2. **其他占位符建议设置默认值**：避免未传值时 `IN ('')` 返回空数据
3. **UNION ALL 合并安全性**：SKU_DATA 和 SKC_DATA 在同一时刻只有一方有数据，另一方为空，UNION ALL 不会产生重复
4. **NULL 处理**：order_qty = 0 时，比例为 NULL（避免除零错误）
5. **数据刷新**：ADS 表每天刷新，current_cum_actual / current_cum_plan_qty / order_qty 为当日最新值
