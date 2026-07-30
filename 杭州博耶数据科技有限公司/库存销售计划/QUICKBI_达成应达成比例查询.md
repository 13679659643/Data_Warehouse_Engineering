# QuickBI 达成比例与应达成比例查询SQL

> 编写日期：2026-07-30
> 适用范围：韦德品牌4个核心渠道 `channel_code IN ('wd', 'japan', 'spanish', 'germany')`
> 数据来源：ADS层2张核心表
> - SKU表：`feishu_ads.ads_sku_sales_plan_180d_d`
> - SKC表：`feishu_ads.ads_skc_sales_plan_180d_d`

---

## 一、需求说明

1. **受日期筛选器影响**：sale_date 为日期范围筛选，需聚合时间段内的 plan_post（计划销量）和 daily_qty（实际销量）
2. **多选筛选器**：ip、series、style_no(即SKC维度)、style_no_size(SKU维度)、sales_phase、sale_date_label、sales_plan_tag、rating，均为多选
3. **表切换逻辑**：
   - 有 `style_no_size` 筛选 → 使用 SKU 表 (`feishu_ads.ads_sku_sales_plan_180d_d`)
   - 无 `style_no_size` 筛选 → 使用 SKC 表 (`feishu_ads.ads_skc_sales_plan_180d_d`)
4. **计算口径**（按时间段聚合）：
   - 达成比例 = 时间段内实际销量 / 订货数量 = SUM(daily_qty) / SUM(order_qty)
   - 应达成比例 = 时间段内计划销量 / 订货数量 = SUM(plan_post) / SUM(order_qty)
5. **多选汇总逻辑**：
   - `daily_qty` / `plan_post`：按 SKU/SKC 分组求和（不同 sale_date 值不同，需聚合）
   - `order_qty`：SKU/SKC 维度常量（同一 SKU/SKC 不同 sale_date 值相同），需先按 SKU/SKC 分组取 MAX 去重，再对所有 SKU/SKC 求和

---

## 二、占位符说明

| 占位符名 | 占位符类型 | 变量类型 | 筛选模式 | 说明 |
|---------|-----------|---------|---------|------|
| `style_no_size` | **值占位符** | 文本 | 多选 | SKU编码筛选，**关键切换字段**（有值用SKU表，无值用SKC表，**必须用值占位符**） |
| `style_no` | 表达式占位符 | 文本 | 多选 | SKC编码/款号筛选，支持包含/排除 |
| `ip` | 表达式占位符 | 文本 | 多选 | IP筛选，支持包含/排除 |
| `series` | 表达式占位符 | 文本 | 多选 | 系列筛选，支持包含/排除 |
| `sales_phase` | 表达式占位符 | 文本 | 多选 | 销售阶段筛选（新品期/热销期/清货期/超周期），支持包含/排除 |
| `sale_date_label` | 表达式占位符 | 文本 | 多选 | 销售日期标签筛选（第N天/超周期），支持包含/排除 |
| `sales_plan_tag` | 表达式占位符 | 文本 | 多选 | 销售计划标签筛选，支持包含/排除 |
| `rating` | 表达式占位符 | 文本 | 多选 | 评级筛选，支持包含/排除 |
| `sale_date` | **值占位符** | 日期-年月日 | 范围 | 日期范围筛选（起止日期），用 `.get(0)` 取起始、`.get(1)` 取结束 |

### QuickBI 占位符配置要点

1. **style_no_size 占位符**：**值占位符**，**不设置默认值**（或设置为空），用于判断是否传值（表切换依赖 `IN ('')` 返回空的行为）
2. **sale_date 占位符**：**值占位符**，日期范围控件，类型选"日期-年月日"，使用 `.get(0)` 和 `.get(1)` 取起止日期
3. **其他7个占位符（style_no/ip/series/sales_phase/sale_date_label/sales_plan_tag/rating）**：**表达式占位符**，支持用户在查询控件中切换"包含/排除"模式
4. **表达式占位符的默认值**：表达式占位符的默认值需填写完整的表达式，比如 `ip = "None"`（设置一个能命中全部数据的默认表达式，或留空由用户主动选择）
5. **值占位符与表达式占位符的差异**：
   - 值占位符 `'$val{ph}'`：只传值，固定用 `IN` 展开，**不支持"排除"操作**
   - 表达式占位符 `$expr{field :ph}`：传完整条件（含操作符），**支持"排除"操作**（如 `NOT IN ('超周期')`）

---

## 三、完整查询SQL

```sql
-- ============================================================
-- QuickBI 达成比例与应达成比例查询SQL（受日期筛选影响）
-- 功能：按 sale_date 日期范围聚合 plan_post 和 daily_qty，计算达成比例和应达成比例
-- 表切换逻辑：
--   1. 有 style_no_size 筛选 → 使用 SKU 表 (feishu_ads.ads_sku_sales_plan_180d_d)
--   2. 无 style_no_size 筛选 → 使用 SKC 表 (feishu_ads.ads_skc_sales_plan_180d_d)
-- 计算口径：
--   1. 达成比例 = SUM(daily_qty) / SUM(order_qty)
--   2. 应达成比例 = SUM(plan_post) / SUM(order_qty)
-- 多选汇总逻辑：
--   daily_qty / plan_post：按 SKU/SKC 分组求和（不同 sale_date 值不同，需聚合）
--   order_qty：SKU/SKC 维度常量，先按 SKU/SKC 分组取 MAX 去重，再求和
-- 占位符类型说明：
--   style_no_size：值占位符（表切换依赖 IN ('') 返回空的行为，必须用值占位符）
--   sale_date：值占位符（日期范围语法 .get(0)/.get(1)，必须用值占位符）
--   其他7个字段：表达式占位符（支持用户切换"包含/排除"模式）
-- ============================================================

WITH 
-- 1. SKU维度数据（有 style_no_size 筛选时生效）
SKU_DATA AS (
    SELECT 
        style_no_size,
        -- daily_qty / plan_post：按 sale_date 聚合求和（时间段内累加）
        SUM(daily_qty)   AS sum_daily_qty,       -- SKU时间段内实际销量汇总
        SUM(plan_post)   AS sum_plan_post,       -- SKU时间段内计划销量汇总
        -- order_qty：SKU维度常量，用 MAX 去重取单值
        MAX(order_qty)   AS order_qty            -- SKU订货数量Q(当前时间常量)
    FROM feishu_ads.ads_sku_sales_plan_180d_d
    WHERE style_no_size IN ('$val{style_no_size}')              -- 关键筛选：有值时生效，无值时 IN ('') 返回空
        -- 日期范围筛选（起止日期）
        AND sale_date >= '$val{sale_date.get(0)}'               -- 起始日期
        AND sale_date <= '$val{sale_date.get(1)}'               -- 结束日期
        AND $expr{ip :ip}                                            -- IP筛选(表达式占位符,支持包含/排除)
        AND $expr{series :series}                                    -- 系列筛选(表达式占位符,支持包含/排除)
        AND $expr{style_no :style_no}                                -- 款号/SKC编码筛选(表达式占位符,支持包含/排除)
        AND $expr{sales_phase :sales_phase}                          -- 销售阶段筛选(表达式占位符,支持包含/排除)
        AND $expr{sale_date_label :sale_date_label}                  -- 销售日期标签筛选(表达式占位符,支持包含/排除)
        AND $expr{sales_plan_tag :sales_plan_tag}                    -- 销售计划标签筛选(表达式占位符,支持包含/排除)
        AND $expr{rating :rating}                                    -- 评级筛选(表达式占位符,支持包含/排除)
    GROUP BY style_no_size
),

-- 2. SKC维度数据（无 style_no_size 筛选时生效）
-- 切换原理：通过 NOT EXISTS 判断 style_no_size 占位符是否传值
--   - 未传值时：子查询 IN ('') 无匹配 → NOT EXISTS = TRUE → SKC 表返回数据
--   - 传值时：子查询有匹配 → NOT EXISTS = FALSE → SKC 表返回空
SKC_DATA AS (
    SELECT 
        style_no,
        -- daily_qty / plan_post：按 sale_date 聚合求和（时间段内累加）
        SUM(daily_qty)   AS sum_daily_qty,       -- SKC时间段内实际销量汇总
        SUM(plan_post)   AS sum_plan_post,       -- SKC时间段内计划销量汇总
        -- order_qty：SKC维度常量，用 MAX 去重取单值
        MAX(order_qty)   AS order_qty            -- SKC订货数量Q(当前时间常量)
    FROM feishu_ads.ads_skc_sales_plan_180d_d
    WHERE NOT EXISTS (
        -- 判断 style_no_size 占位符是否有传值：有匹配说明用户筛选了 SKU
        SELECT 1 
        FROM feishu_ads.ads_sku_sales_plan_180d_d 
        WHERE style_no_size IN ('$val{style_no_size}') 
        LIMIT 1
    )
    -- 日期范围筛选（起止日期）
    AND sale_date >= '$val{sale_date.get(0)}'                    -- 起始日期
    AND sale_date <= '$val{sale_date.get(1)}'                    -- 结束日期
    AND $expr{ip :ip}                                            -- IP筛选(表达式占位符,支持包含/排除)
    AND $expr{series :series}                                    -- 系列筛选(表达式占位符,支持包含/排除)
    AND $expr{style_no :style_no}                                -- 款号/SKC编码筛选(表达式占位符,支持包含/排除)
    AND $expr{sales_phase :sales_phase}                          -- 销售阶段筛选(表达式占位符,支持包含/排除)
    AND $expr{sale_date_label :sale_date_label}                  -- 销售日期标签筛选(表达式占位符,支持包含/排除)
    AND $expr{sales_plan_tag :sales_plan_tag}                    -- 销售计划标签筛选(表达式占位符,支持包含/排除)
    AND $expr{rating :rating}                                    -- 评级筛选(表达式占位符,支持包含/排除)
    GROUP BY style_no
),

-- 3. 合并SKU与SKC数据（同一时刻只有一方有数据，另一方为空）
UNION_DATA AS (
    SELECT 
        sum_daily_qty,
        sum_plan_post,
        order_qty
    FROM SKU_DATA
    UNION ALL
    SELECT 
        sum_daily_qty,
        sum_plan_post,
        order_qty
    FROM SKC_DATA
)

-- 4. 最终结果：全局汇总计算两个比例
SELECT 
    -- 中间汇总值（可用于QuickBI展示或调试）
    SUM(sum_daily_qty)  AS sum_daily_qty,          -- 时间段内实际销量汇总
    SUM(sum_plan_post)  AS sum_plan_post,          -- 时间段内计划销量汇总
    SUM(order_qty)      AS sum_order_qty,          -- 订货数量汇总
    
    -- 核心指标1：达成比例 = 实际销量 / 订货数量
    CASE 
        WHEN SUM(order_qty) > 0 
        THEN ROUND(SUM(sum_daily_qty) * 1.0 / SUM(order_qty), 6)
        ELSE NULL 
    END AS achievement_ratio,                       -- 达成比例
    
    -- 核心指标2：应达成比例 = 计划销量 / 订货数量
    CASE 
        WHEN SUM(order_qty) > 0 
        THEN ROUND(SUM(sum_plan_post) * 1.0 / SUM(order_qty), 6)
        ELSE NULL 
    END AS should_achieve_ratio                     -- 应达成比例
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

### 4.2 日期范围筛选

使用 QuickBI 日期范围控件语法：
```sql
sale_date >= '$val{sale_date.get(0)}'   -- 起始日期
AND sale_date <= '$val{sale_date.get(1)}' -- 结束日期
```

- `.get(0)`：取日期范围控件的起始日期
- `.get(1)`：取日期范围控件的结束日期

### 4.3 多选汇总原理

`daily_qty` / `plan_post` / `order_qty` 三个字段在 SKU/SKC 维度的特性不同，需分别处理：

| 字段 | 字段特性 | 聚合方式 |
|------|---------|---------|
| `daily_qty` | 不同 sale_date 值不同（日销量） | `SUM()` 按 SKU/SKC 分组求和 |
| `plan_post` | 不同 sale_date 值不同（日计划） | `SUM()` 按 SKU/SKC 分组求和 |
| `order_qty` | SKU/SKC 维度常量（同 SKU/SKC 不同 sale_date 值相同） | `MAX()` 去重取单值 |

**处理步骤**：
1. 先 `GROUP BY style_no_size` / `style_no` 分组
2. `daily_qty` / `plan_post` 用 `SUM()` 聚合时间段内累加值
3. `order_qty` 用 `MAX()` 取每个 SKU/SKC 的单值（去重）
4. 外层 `UNION ALL` 合并后，再对所有 SKU/SKC 求和

### 4.4 结果输出

最终输出单行全局汇总数据：
- `sum_daily_qty`：时间段内实际销量汇总
- `sum_plan_post`：时间段内计划销量汇总
- `sum_order_qty`：订货数量汇总
- `achievement_ratio`：达成比例（保留6位小数）
- `should_achieve_ratio`：应达成比例（保留6位小数）

---

## 五、QuickBI 配置说明

### 5.1 创建数据集

1. 在 QuickBI 数据源页面，单击"SQL 创建数据集"
2. 粘贴上述完整 SQL
3. 单击"占位符管理"，配置 9 个占位符（见第二章表格）
4. 运行验证，保存数据集

### 5.2 配置查询控件

1. 创建仪表板，添加该数据集
2. 添加查询控件，绑定 9 个占位符（见第二章表格）
3. **style_no_size**：值占位符，多选，**不设置默认值**（表切换依赖）
4. **sale_date**：值占位符，日期范围控件，类型选"日期-年月日"
5. **其他7个占位符**：表达式占位符，多选，支持用户切换"包含/排除"模式；建议设置一个能命中全部数据的默认表达式（如 `1=1`）

### 5.3 配置图表

1. 添加指标看板或交叉表
2. 拖入 `achievement_ratio` 和 `should_achieve_ratio` 字段
3. 配置数值展示格式（百分比，保留2位小数）

---

## 六、注意事项

1. **style_no_size 占位符必须用值占位符且不设置默认值**：表切换逻辑依赖 `IN ('$val{style_no_size}')` 未传值时变成 `IN ('')` 返回空的行为；若改用表达式占位符，未传值时的行为不同，会破坏 NOT EXISTS 切换逻辑
2. **sale_date 占位符必须用值占位符**：日期范围语法 `.get(0)`/`.get(1)` 仅值占位符支持
3. **其他7个占位符使用表达式占位符**：支持用户在查询控件中切换"包含/排除"模式，解决值占位符只能 IN、无法 NOT IN 的局限
4. **表达式占位符的默认值需为完整表达式**：如 `ip = "None"` 或 `1=1`，不能只写值
5. **UNION ALL 合并安全性**：SKU_DATA 和 SKC_DATA 在同一时刻只有一方有数据，另一方为空，UNION ALL 不会产生重复
6. **NULL 处理**：order_qty = 0 时，比例为 NULL（避免除零错误）
7. **order_qty 去重逻辑**：order_qty 是 SKU/SKC 维度常量，先 MAX 去重再 SUM，避免 180 倍放大
8. **daily_qty / plan_post 聚合逻辑**：这两个字段按 sale_date 累加，时间段筛选后直接 SUM 即可，无需额外去重
