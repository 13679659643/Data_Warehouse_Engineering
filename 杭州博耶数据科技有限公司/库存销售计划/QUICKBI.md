# QuickBI 可视化解决方案（ADS → QuickBI 完整对接方案）

> 编写日期：2026-07-12
> 设计目标：基于 ADS 层 3 张表，在 QuickBI 上展示 SKU/SKC 维度的 1~180 天销售计划
> 适用范围：韦德品牌 4 个核心渠道 `channel_code IN ('wd', 'japan', 'spanish', 'germany')`
> 数据源：StarRocks
> 口径依据：`杭州博耶数据科技有限公司/指标口径/基于DWD层的字段口径定义.md`
> 数据基座：ADS 层 3 张表（均带 `feishu_ads.` 前缀）

---

## 一、整体方案概览

### 1.1 架构流程图

```
┌──────────────────────────────────────────────────────────────────────┐
│                         ADS 应用层 (StarRocks)                        │
│  ┌─────────────────────────────────┐ ┌─────────────────────────────┐ │
│  │ feishu_ads.                     │ │ feishu_ads.                 │ │
│  │ ads_sku_sales_plan_180d_d       │ │ ads_skc_sales_plan_180d_d   │ │
│  │ SKU 维度1~180天销售计划(核心表) │ │ SKC 维度1~180天销售计划     │ │
│  │ 粒度: style_no_size + sale_date │ │ 粒度: style_no + sale_date  │ │
│  └─────────────────────────────────┘ └─────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ feishu_ads.ads_sku_skc_summary_d                                │ │
│  │ SKU/SKC 汇总表(辅助表)                                          │ │
│  │ 粒度: dim_type + dim_value                                      │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          QuickBI 数据源连接层                          │
│  数据源类型: StarRocks                                                 │
│  连接方式: 直连 (Live Connection)                                      │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          QuickBI 数据集层                              │
│  ┌────────────────┐ ┌────────────────┐ ┌──────────────────────────┐ │
│  │ 数据集1:        │ │ 数据集2:        │ │ 数据集3:                 │ │
│  │ SKU销售计划      │ │ SKC销售计划      │ │ SKU/SKC 汇总             │ │
│  └────────────────┘ └────────────────┘ └──────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          QuickBI 仪表板层                              │
│  仪表板1: SKU-1~180天销售计划概览                                      │
│  仪表板2: SKU-销售达成分析                                             │
│  仪表板3: SKU-库存与可售周期                                           │
│  仪表板4: SKC-1~180天销售计划概览                                      │
│  仪表板5: SKC-销售达成分析                                             │
│  仪表板6: SKU/SKC 汇总对比                                             │
└──────────────────────────────────────────────────────────────────────┘
```

### 1.2 核心展示内容

| 维度 | 核心指标 | 数据集 |
|------|---------|--------|
| SKU（style_no_size） | 1~180天销售计划(前/后)、实际销售、达成情况 | 数据集1 |
| SKC（style_no） | 1~180天销售计划(前/后)、实际销售、达成情况 | 数据集2 |
| SKU/SKC 混合 | 累计销量、累计金额、达成比例、可售周期 | 数据集3 |

### 1.3 ⚠️ 财务/库存人工审查提醒

以下字段涉及财务金额或库存数据，**QuickBI 上线前必须由业务方人工审查**：

1. **`daily_amt` / `cum_amt`**：销售金额（元，DECIMAL(18,6)），需确认金额单位与精度
2. **`tag_price`**：吊牌价，需确认是否含税
3. **`inventory_sku` / `inventory_skc` / `available_inventory`**：在仓库存与可提库存来自不同数据源（商品库 vs 品牌方库存表），需确认两者口径一致
4. **`total_order_qty`**：涉及补货数量，需确认 `is_replenish` 字段的取值规范
5. **`sellable_days`**：可售周期依赖 30 天平均日销，当日销为 0 时返回 NULL，需确认业务展示逻辑
6. **`achievement_ratio` / `7d_achievement` / `30d_achievement`**：达成率指标，分母为 0 时返回 NULL，需确认业务展示逻辑

---

## 二、QuickBI 数据源连接

### 2.1 数据源配置

#### 2.1.1 数据源类型选择

| 配置项 | 取值 |
|--------|------|
| 数据源类型 | **StarRocks** |
| 数据源名称 | `starrocks_weide_bi`（建议命名） |
| 连接方式 | 直连（Live Connection，实时查询） |
| 数据库 | `feishu_ads` |

#### 2.1.2 连接参数配置

| 参数 | 说明 | 示例值 |
|------|------|--------|
| 数据库类型 | StarRocks | - |
| 主机地址 | StarRocks FE 节点 IP | `192.168.x.x` |
| 端口 | FE 查询端口（默认 9030） | `9030` |
| 数据库名 | ADS 层所在数据库 | `feishu_ads` |
| 用户名 | BI 专用只读账号（建议） | `bi_reader` |
| 密码 | 数据库密码 | `******` |
| SSL 加密 | 建议开启 | 是 |

> **安全建议**：为 QuickBI 创建专用只读账号 `bi_reader`，仅授予 `feishu_ads` 库的 SELECT 权限，不授予写入/修改权限。

#### 2.1.3 账号权限配置示例

```sql
-- 在 StarRocks 中创建 BI 只读账号
CREATE USER 'bi_reader' IDENTIFIED BY '******';

-- 授予 feishu_ads 库的查询权限
GRANT SELECT ON feishu_ads.* TO ROLE 'bi_reader_role';
GRANT bi_reader_role TO USER 'bi_reader';
```

### 2.2 连接测试

#### 2.2.1 测试步骤

1. 登录 QuickBI 控制台
2. 进入「数据源」→「新建数据源」→ 选择「StarRocks」
3. 填写 2.1.2 节中的连接参数
4. 点击「连接测试」按钮
5. 测试通过后点击「保存」

#### 2.2.2 验证 SQL（在 StarRocks 客户端执行）

```sql
-- 1. 验证账号可查询 ADS 表
SELECT COUNT(*) FROM feishu_ads.ads_sku_sales_plan_180d_d;
SELECT COUNT(*) FROM feishu_ads.ads_skc_sales_plan_180d_d;
SELECT COUNT(*) FROM feishu_ads.ads_sku_skc_summary_d;

-- 2. 验证 ADS 表字段完整性
SHOW COLUMNS FROM feishu_ads.ads_sku_sales_plan_180d_d;
SHOW COLUMNS FROM feishu_ads.ads_skc_sales_plan_180d_d;
SHOW COLUMNS FROM feishu_ads.ads_sku_skc_summary_d;

-- 3. 验证数据时间范围（确认 ETL 已刷新）
SELECT
    MIN(sale_date) AS min_date,
    MAX(sale_date) AS max_date,
    COUNT(DISTINCT style_no_size) AS sku_cnt
FROM feishu_ads.ads_sku_sales_plan_180d_d;
```

---

## 三、数据集设计

### 3.1 数据集1：SKU 维度 1~180 天销售计划

#### 3.1.1 基本信息

| 项 | 取值 |
|----|------|
| 数据集名称 | `dataset_sku_sales_plan` |
| 数据来源 | `feishu_ads.ads_sku_sales_plan_180d_d` |
| 粒度 | style_no_size + sale_date（一行 = 一个 SKU 的一天） |
| 用途 | 仪表板1、仪表板2、仪表板3 |

#### 3.1.2 字段映射与分组

**A. 维度字段（用于筛选/分组）**

| 字段名 | 字段类型 | QuickBI 字段类型 | 分组 | 说明 | 口径章节 |
|--------|---------|------------------|------|------|---------|
| `style_no_size` | VARCHAR(255) | 文本 | SKU 维度 | SKU 编码 | 3.1 |
| `sale_date` | DATE | 日期 | 时间维度 | 销售日期（分区键） | 4.1 |
| `lifecycle_day` | BIGINT | 数值 | 时间维度 | 上市第 N 天 | 4.1 |
| `sale_date_label` | VARCHAR(20) | 文本 | 时间维度 | "第 N 天"/"超周期" | 4.1 |
| `sales_phase` | VARCHAR(50) | 文本 | 阶段维度 | 新品期/热销期/清货期/超周期 | 4.2 |
| `is_over_cycle` | TINYINT | 数值 | 阶段维度 | 1=超周期, 0=正常 | 4.2 |
| `brand` | VARCHAR(20) | 文本 | 商品属性 | 品牌（固定'韦德'） | 3.2 |
| `style_no` | VARCHAR(128) | 文本 | 商品属性 | 款号/SKC 编码 | 3.1 |
| `size` | VARCHAR(50) | 文本 | 商品属性 | 尺码 | - |
| `ip` | VARCHAR(100) | 文本 | 商品属性 | IP | 3.4 |
| `series` | VARCHAR(100) | 文本 | 商品属性 | 系列 | 3.3 |
| `color_name` | VARCHAR(100) | 文本 | 商品属性 | 配色名 | - |
| `product_name` | VARCHAR(500) | 文本 | 商品属性 | 商品名称 | - |
| `category` | VARCHAR(100) | 文本 | 商品属性 | 品类 | - |
| `shelf_date` | DATE | 日期 | 商品属性 | 上架日期 | 3.5 |
| `first_sales_date` | DATE | 日期 | 商品属性 | 首次销售日期 | 3.6 |

**B. 度量字段（用于聚合/计算）**

| 字段名 | 字段类型 | QuickBI 聚合方式 | 分组 | 说明 | 口径章节 |
|--------|---------|------------------|------|------|---------|
| `plan_pre` | DECIMAL(18,6) | SUM | 销售计划 | 销售计划(销售前) | 4.3 |
| `plan_post` | DECIMAL(18,6) | SUM | 销售计划 | 销售计划(销售后) | 4.4 |
| `daily_qty` | BIGINT | SUM | 实际销售 | 日销量 | 3.14 / 4.5 |
| `daily_amt` | DECIMAL(18,6) | SUM | 实际销售 | 日金额 ⚠️ | 3.15 |
| `cum_qty` | BIGINT | MAX | 累计指标 | 累计销量 | 3.16 |
| `cum_amt` | DECIMAL(18,6) | MAX | 累计指标 | 累计金额 ⚠️ | 3.17 |
| `achievement_rate` | DECIMAL(18,6) | AVG | 达成指标 | 达成情况 | 4.6 |
| `inventory_sku` | BIGINT | MAX | 库存指标 | 在仓库存 ⚠️ | 3.9 |
| `available_inventory` | BIGINT | MAX | 库存指标 | 可提库存 ⚠️ | 3.10 |
| `daily_avg_qty_30d` | DECIMAL(18,6) | MAX | 库存指标 | 30 天平均日销 | 3.12 |
| `sellable_days` | DECIMAL(18,6) | MAX | 库存指标 | 可售周期(天) ⚠️ | 3.11 |
| `yesterday_actual_qty` | BIGINT | MAX | 当前快照 | 昨日实际销售 | 3.21 |
| `yesterday_achievement` | DECIMAL(18,6) | MAX | 当前快照 | 昨日销售达成情况 | 3.22 |
| `7d_achievement` | DECIMAL(18,6) | MAX | 当前快照 | 7 天销售达成情况 | 3.23 |
| `30d_achievement` | DECIMAL(18,6) | MAX | 当前快照 | 30 天销售达成情况 | 3.24 |
| `today_plan_qty` | DECIMAL(18,6) | MAX | 当前快照 | 今日计划销售数量 | 3.25 |
| `order_qty` | BIGINT | MAX | 订货指标 | 订货数量 Q | 3.18 |
| `total_order_qty` | BIGINT | MAX | 订货指标 | 总订货数量 ⚠️ | 3.20 |
| `achievement_ratio` | DECIMAL(18,6) | MAX | 订货指标 | 达成比例 | 3.19 |

> **聚合方式说明**：
> - **SUM 聚合**：适用于按日期汇总的指标（如 plan_pre、daily_qty）
> - **MAX 聚合**：适用于快照型指标（如 cum_qty、inventory_sku、yesterday_actual_qty），这些指标在同一日期对同一 SKU 只有一行值，取 MAX 即可

#### 3.1.3 自定义计算字段

| 计算字段名 | 计算公式 | 用途 |
|-----------|---------|------|
| `plan_pre_display` | `CASE WHEN [lifecycle_day] <= 180 THEN [plan_pre] ELSE NULL END` | 1~180 天展示用 |
| `plan_post_display` | `CASE WHEN [lifecycle_day] <= 180 THEN [plan_post] ELSE NULL END` | 1~180 天展示用 |
| `achievement_color` | `CASE WHEN [achievement_rate] >= 1.0 THEN '绿色' WHEN [achievement_rate] < 1.0 THEN '红色' ELSE '灰色' END` | 达成颜色标记 |

---

### 3.2 数据集2：SKC 维度 1~180 天销售计划

#### 3.2.1 基本信息

| 项 | 取值 |
|----|------|
| 数据集名称 | `dataset_skc_sales_plan` |
| 数据来源 | `feishu_ads.ads_skc_sales_plan_180d_d` |
| 粒度 | style_no + sale_date（一行 = 一个 SKC 的一天） |
| 用途 | 仪表板4、仪表板5 |

#### 3.2.2 字段映射与分组

**A. 维度字段**

| 字段名 | 字段类型 | QuickBI 字段类型 | 分组 | 说明 | 口径章节 |
|--------|---------|------------------|------|------|---------|
| `style_no` | VARCHAR(128) | 文本 | SKC 维度 | SKC 编码/款号 | 5.1 |
| `sale_date` | DATE | 日期 | 时间维度 | 销售日期 | 6.1 |
| `lifecycle_day` | BIGINT | 数值 | 时间维度 | 上市第 N 天 | 6.1 |
| `sale_date_label` | VARCHAR(20) | 文本 | 时间维度 | "第 N 天"/"超周期" | 6.1 |
| `sales_phase` | VARCHAR(50) | 文本 | 阶段维度 | 新品期/热销期/清货期/超周期 | 6.2 |
| `is_over_cycle` | TINYINT | 数值 | 阶段维度 | 1=超周期, 0=正常 | 6.2 |
| `brand` | VARCHAR(20) | 文本 | 商品属性 | 品牌 | 5.2 |
| `ip` | VARCHAR(100) | 文本 | 商品属性 | IP | 5.4 |
| `series` | VARCHAR(100) | 文本 | 商品属性 | 系列 | 5.3 |
| `product_name` | VARCHAR(500) | 文本 | 商品属性 | 商品名称 | - |
| `category` | VARCHAR(100) | 文本 | 商品属性 | 品类 | - |
| `shelf_date` | DATE | 日期 | 商品属性 | SKC 上架日期 (MIN) | 5.5 |
| `first_sales_date` | DATE | 日期 | 商品属性 | SKC 首次销售日期 (MIN) | 5.6 |

> **与 SKU 数据集差异**：SKC 数据集无 `size` 和 `color_name` 字段（已聚合到 style_no 维度）

**B. 度量字段**

| 字段名 | 字段类型 | QuickBI 聚合方式 | 分组 | 说明 | 口径章节 |
|--------|---------|------------------|------|------|---------|
| `plan_pre` | DECIMAL(18,6) | SUM | 销售计划 | 销售计划(销售前) | 6.3 |
| `plan_post` | DECIMAL(18,6) | SUM | 销售计划 | 销售计划(销售后) | 6.4 |
| `daily_qty` | BIGINT | SUM | 实际销售 | 日销量 | 5.14 / 6.5 |
| `daily_amt` | DECIMAL(18,6) | SUM | 实际销售 | 日金额 ⚠️ | 5.15 |
| `cum_qty` | BIGINT | MAX | 累计指标 | 累计销量 | 5.16 |
| `cum_amt` | DECIMAL(18,6) | MAX | 累计指标 | 累计金额 ⚠️ | 5.17 |
| `achievement_rate` | DECIMAL(18,6) | AVG | 达成指标 | 达成情况 | 6.6 |
| `inventory_skc` | BIGINT | MAX | 库存指标 | SKC 在仓库存 ⚠️ | 5.9 |
| `available_inventory` | BIGINT | MAX | 库存指标 | SKC 可提库存 ⚠️ | 5.10 |
| `daily_avg_qty_30d` | DECIMAL(18,6) | MAX | 库存指标 | SKC 30 天平均日销 | 5.12 |
| `sellable_days` | DECIMAL(18,6) | MAX | 库存指标 | SKC 可售周期(天) ⚠️ | 5.11 |
| `yesterday_actual_qty` | BIGINT | MAX | 当前快照 | 昨日实际销售 | 5.21 |
| `yesterday_achievement` | DECIMAL(18,6) | MAX | 当前快照 | 昨日销售达成情况 | 5.22 |
| `7d_achievement` | DECIMAL(18,6) | MAX | 当前快照 | 7 天销售达成情况 | 5.23 |
| `30d_achievement` | DECIMAL(18,6) | MAX | 当前快照 | 30 天销售达成情况 | 5.24 |
| `today_plan_qty` | DECIMAL(18,6) | MAX | 当前快照 | 今日计划销售数量 | 5.25 |
| `order_qty` | BIGINT | MAX | 订货指标 | SKC 订货数量 Q | 5.18 |
| `total_order_qty` | BIGINT | MAX | 订货指标 | SKC 总订货数量 ⚠️ | 5.20 |
| `achievement_ratio` | DECIMAL(18,6) | MAX | 订货指标 | SKC 达成比例 | 5.19 |

> **与 SKU 数据集差异**：库存字段为 `inventory_skc`（SKU 表为 `inventory_sku`）

---

### 3.3 数据集3：SKU/SKC 汇总

#### 3.3.1 基本信息

| 项 | 取值 |
|----|------|
| 数据集名称 | `dataset_sku_skc_summary` |
| 数据来源 | `feishu_ads.ads_sku_skc_summary_d` |
| 粒度 | dim_type + dim_value（一行 = 一个 SKU 或一个 SKC 的当前快照） |
| 用途 | 仪表板6 |

#### 3.3.2 字段映射与分组

**A. 维度字段**

| 字段名 | 字段类型 | QuickBI 字段类型 | 分组 | 说明 | 口径章节 |
|--------|---------|------------------|------|------|---------|
| `dim_type` | VARCHAR(10) | 文本 | 维度类型 | SKU / SKC | - |
| `dim_value` | VARCHAR(255) | 文本 | 维度值 | SKU=style_no_size, SKC=style_no | - |
| `brand` | VARCHAR(20) | 文本 | 商品属性 | 品牌 | 3.2 / 5.2 |
| `style_no` | VARCHAR(128) | 文本 | 商品属性 | 款号/SKC 编码 | - |
| `ip` | VARCHAR(100) | 文本 | 商品属性 | IP | 3.4 / 5.4 |
| `series` | VARCHAR(100) | 文本 | 商品属性 | 系列 | 3.3 / 5.3 |
| `product_name` | VARCHAR(500) | 文本 | 商品属性 | 商品名称 | - |
| `shelf_date` | DATE | 日期 | 商品属性 | 上架日期 | 3.5 / 5.5 |
| `first_sales_date` | DATE | 日期 | 商品属性 | 首次销售日期 | 3.6 / 5.6 |
| `lifecycle_day` | BIGINT | 数值 | 当前状态 | 当日已上架天数 | 3.7 / 5.7 |
| `sales_cycle_label` | VARCHAR(50) | 文本 | 当前状态 | 新品期/热销期/清货期/超周期 | 3.8 / 5.8 |

**B. 度量字段**

| 字段名 | 字段类型 | QuickBI 聚合方式 | 分组 | 说明 | 口径章节 |
|--------|---------|------------------|------|------|---------|
| `order_qty` | BIGINT | SUM | 订货指标 | 订货数量 Q | 3.18 / 5.18 |
| `total_order_qty` | BIGINT | SUM | 订货指标 | 总订货数量 ⚠️ | 3.20 / 5.20 |
| `cum_qty` | BIGINT | SUM | 销售累计 | 累计销量 | 3.16 / 5.16 |
| `cum_amt` | DECIMAL(18,6) | SUM | 销售累计 | 累计金额 ⚠️ | 3.17 / 5.17 |
| `inventory_qty` | BIGINT | SUM | 库存指标 | 在仓库存 ⚠️ | 3.9 / 5.9 |
| `available_inventory` | BIGINT | SUM | 库存指标 | 可提库存 ⚠️ | 3.10 / 5.10 |
| `daily_avg_qty_30d` | DECIMAL(18,6) | AVG | 库存指标 | 30 天平均日销 | 3.12 / 5.12 |
| `sellable_days` | DECIMAL(18,6) | AVG | 库存指标 | 可售周期(天) ⚠️ | 3.11 / 5.11 |
| `achievement_ratio` | DECIMAL(18,6) | AVG | 达成指标 | 达成比例 | 3.19 / 5.19 |
| `yesterday_actual_qty` | BIGINT | SUM | 达成指标 | 昨日实际销售 | 3.21 / 5.21 |
| `today_plan_qty` | DECIMAL(18,6) | SUM | 达成指标 | 今日计划销售数量 | 3.25 / 5.25 |

---

## 四、仪表板设计

### 4.1 仪表板1：SKU 维度 - 1~180 天销售计划概览

#### 4.1.1 仪表板基本信息

| 项 | 取值 |
|----|------|
| 仪表板名称 | `SKU-1~180天销售计划概览` |
| 数据集 | `dataset_sku_sales_plan` |
| 主要用途 | 展示 SKU 维度的销售计划 vs 实际销售趋势 |

#### 4.1.2 图表配置

**图表1.1：销售计划 vs 实际销售趋势（折线图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 折线图 |
| X 轴 | `lifecycle_day`（上市第 N 天，1~180） |
| Y 轴（左轴） | `plan_pre`（SUM，销售计划前）、`plan_post`（SUM，销售计划后）、`daily_qty`（SUM，实际销售） |
| 颜色图例 | 自动区分 3 条线 |
| 筛选条件 | `is_over_cycle = 0`、`lifecycle_day BETWEEN 1 AND 180` |
| 排序 | `lifecycle_day` 升序 |
| 标题 | "SKU 1~180 天销售计划 vs 实际销售趋势" |

> **说明**：
> - `plan_pre`（口径 4.3 节）：固定计划，Q*ratio/180，上架前即可算出
> - `plan_post`（口径 4.4 节）：动态计划，(Q-cum_actual)*ratio/(181-N)，每天更新
> - `daily_qty`（口径 3.14 / 4.5 节）：实际日销量

**图表1.2：达成情况趋势（柱状图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 柱状图 |
| X 轴 | `sale_date_label`（"第 N 天"） |
| Y 轴 | `achievement_rate`（AVG，达成情况） |
| 颜色 | 根据达成率着色：>=1.0 绿色，<1.0 红色（参考第六章自定义字段） |
| 筛选条件 | `is_over_cycle = 0`、`lifecycle_day BETWEEN 1 AND 180` |
| 标题 | "SKU 1~180 天达成情况" |

> **达成情况口径**（4.6 节）：`achievement_rate = daily_qty / plan_post`，>100% 表示超预期，<100% 表示未达标

**图表1.3：SKU 明细表（表格）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 明细表 |
| 列 | `style_no_size`、`product_name`、`brand`、`series`、`ip`、`sale_date_label`、`sales_phase`、`plan_pre`、`plan_post`、`daily_qty`、`cum_qty`、`achievement_rate`、`inventory_sku`、`sellable_days` |
| 筛选条件 | `is_over_cycle = 0` |
| 排序 | `style_no_size`、`sale_date` |
| 标题 | "SKU 销售计划明细" |

**图表1.4：销售阶段分布（饼图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 饼图 |
| 维度 | `sales_phase` |
| 度量 | `style_no_size`（COUNT DISTINCT，去重 SKU 数） |
| 筛选条件 | `is_over_cycle = 0` |
| 标题 | "SKU 销售阶段分布" |

#### 4.1.3 筛选器配置

| 筛选器 | 字段 | 类型 | 默认值 |
|--------|------|------|--------|
| 品牌 | `brand` | 单选/多选 | 韦德 |
| 系列 | `series` | 多选 | 全选 |
| IP | `ip` | 多选 | 全选 |
| 销售周期标签 | `sales_phase` | 多选 | 全选 |
| SKU 编码 | `style_no_size` | 文本搜索 | 空 |
| 上市天数范围 | `lifecycle_day` | 数值范围 | 1~180 |

---

### 4.2 仪表板2：SKU 维度 - 销售达成分析

#### 4.2.1 仪表板基本信息

| 项 | 取值 |
|----|------|
| 仪表板名称 | `SKU-销售达成分析` |
| 数据集 | `dataset_sku_sales_plan` |
| 主要用途 | 重点展示 1~180 天达成趋势，识别未达标 SKU |

#### 4.2.2 图表配置

**图表2.1：达成情况组合图（柱状图 + 折线图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 组合图（柱状图 + 折线图） |
| X 轴 | `lifecycle_day` |
| Y 轴（柱） | `daily_qty`（SUM，实际销售） |
| Y 轴（线） | `plan_post`（SUM，销售计划后） |
| 次轴（线） | `achievement_rate`（AVG，达成情况） |
| 筛选条件 | `is_over_cycle = 0`、`lifecycle_day BETWEEN 1 AND 180` |
| 标题 | "SKU 实际销售 vs 计划 + 达成率" |

**图表2.2：昨日/7天/30天达成看板（指标卡）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 指标卡 |
| 指标1 | `yesterday_achievement`（MAX，昨日销售达成情况） |
| 指标2 | `7d_achievement`（MAX，7 天销售达成情况） |
| 指标3 | `30d_achievement`（MAX，30 天销售达成情况） |
| 指标4 | `today_plan_qty`（MAX，今日计划销售数量） |
| 筛选条件 | `style_no_size = [选择 SKU]` |
| 标题 | "SKU 当前达成快照" |

> **快照指标说明**（3.21~3.25 节）：这些指标对同一 SKU 的所有行值相同，使用 MAX 聚合即可获取当前状态。

**图表2.3：未达标 SKU 排行（表格）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 明细表 |
| 列 | `style_no_size`、`product_name`、`series`、`ip`、`lifecycle_day`、`daily_qty`、`plan_post`、`achievement_rate` |
| 筛选条件 | `is_over_cycle = 0`、`lifecycle_day BETWEEN 1 AND 180`、`achievement_rate < 1.0` |
| 排序 | `achievement_rate` 升序（达成率最低的排最前） |
| 标题 | "未达标 SKU 排行（达成率 < 100%）" |

**图表2.4：各阶段达成率对比（柱状图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 柱状图 |
| X 轴 | `sales_phase`（新品期/热销期/清货期） |
| Y 轴 | `achievement_rate`（AVG） |
| 颜色 | `sales_phase` |
| 筛选条件 | `is_over_cycle = 0` |
| 标题 | "各销售阶段达成率对比" |

#### 4.2.3 筛选器配置

| 筛选器 | 字段 | 类型 | 默认值 |
|--------|------|------|--------|
| 品牌 | `brand` | 单选 | 韦德 |
| 系列 | `series` | 多选 | 全选 |
| IP | `ip` | 多选 | 全选 |
| 销售阶段 | `sales_phase` | 多选 | 全选 |
| SKU 编码 | `style_no_size` | 文本搜索 | 空 |

---

### 4.3 仪表板3：SKU 维度 - 库存与可售周期

#### 4.3.1 仪表板基本信息

| 项 | 取值 |
|----|------|
| 仪表板名称 | `SKU-库存与可售周期` |
| 数据集 | `dataset_sku_sales_plan` |
| 主要用途 | 库存预警、可售周期监控 |

#### 4.3.2 图表配置

**图表3.1：库存预警指标卡**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 指标卡 |
| 指标1 | `inventory_sku`（MAX，在仓库存总计） |
| 指标2 | `available_inventory`（MAX，可提库存总计） |
| 指标3 | `daily_avg_qty_30d`（MAX，30 天平均日销） |
| 指标4 | `sellable_days`（MAX，可售周期） |
| 筛选条件 | `style_no_size = [选择 SKU]` |
| 标题 | "SKU 库存预警看板" |

> ⚠️ **库存口径提醒**：
> - `inventory_sku`（3.9 节）：在仓库存，来自商品库实时快照
> - `available_inventory`（3.10 节）：可提库存，来自品牌方库存表最新快照
> - `sellable_days`（3.11 节）：可售周期 = 在仓库存 / 30 天平均日销，日销为 0 时返回 NULL

**图表3.2：库存预警 SKU 列表（表格）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 明细表 |
| 列 | `style_no_size`、`product_name`、`series`、`sales_phase`、`inventory_sku`、`available_inventory`、`daily_avg_qty_30d`、`sellable_days` |
| 筛选条件 | `sellable_days < 30`（可售周期不足 30 天预警） |
| 排序 | `sellable_days` 升序 |
| 标题 | "可售周期预警（<30 天）" |

**图表3.3：各阶段库存分布（柱状图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 柱状图 |
| X 轴 | `sales_phase` |
| Y 轴 | `inventory_sku`（SUM）、`available_inventory`（SUM） |
| 颜色 | 区分在仓库存与可提库存 |
| 筛选条件 | `is_over_cycle = 0` |
| 标题 | "各销售阶段库存分布" |

**图表3.4：可售周期分布（柱状图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 柱状图 |
| X 轴 | `sellable_days`（数值分箱：0-7、8-30、31-90、91-180、>180） |
| Y 轴 | `style_no_size`（COUNT DISTINCT，SKU 数） |
| 标题 | "SKU 可售周期分布" |

#### 4.3.3 筛选器配置

| 筛选器 | 字段 | 类型 | 默认值 |
|--------|------|------|--------|
| 品牌 | `brand` | 单选 | 韦德 |
| 系列 | `series` | 多选 | 全选 |
| IP | `ip` | 多选 | 全选 |
| 销售阶段 | `sales_phase` | 多选 | 全选 |
| 可售周期范围 | `sellable_days` | 数值范围 | 空 |
| SKU 编码 | `style_no_size` | 文本搜索 | 空 |

---

### 4.4 仪表板4：SKC 维度 - 1~180 天销售计划概览

#### 4.4.1 仪表板基本信息

| 项 | 取值 |
|----|------|
| 仪表板名称 | `SKC-1~180天销售计划概览` |
| 数据集 | `dataset_skc_sales_plan` |
| 主要用途 | 展示 SKC 维度的销售计划 vs 实际销售趋势 |

#### 4.4.2 图表配置

**图表4.1：销售计划 vs 实际销售趋势（折线图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 折线图 |
| X 轴 | `lifecycle_day`（1~180） |
| Y 轴 | `plan_pre`（SUM）、`plan_post`（SUM）、`daily_qty`（SUM） |
| 筛选条件 | `is_over_cycle = 0`、`lifecycle_day BETWEEN 1 AND 180` |
| 标题 | "SKC 1~180 天销售计划 vs 实际销售趋势" |

> **SKC 口径说明**：所有指标按 `style_no` 聚合（5.1~5.25 节、6.1~6.6 节），库存字段为 `inventory_skc`

**图表4.2：达成情况趋势（柱状图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 柱状图 |
| X 轴 | `sale_date_label` |
| Y 轴 | `achievement_rate`（AVG） |
| 筛选条件 | `is_over_cycle = 0`、`lifecycle_day BETWEEN 1 AND 180` |
| 标题 | "SKC 1~180 天达成情况" |

**图表4.3：SKC 明细表（表格）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 明细表 |
| 列 | `style_no`、`product_name`、`brand`、`series`、`ip`、`sale_date_label`、`sales_phase`、`plan_pre`、`plan_post`、`daily_qty`、`cum_qty`、`achievement_rate`、`inventory_skc`、`sellable_days` |
| 筛选条件 | `is_over_cycle = 0` |
| 标题 | "SKC 销售计划明细" |

**图表4.4：销售阶段分布（饼图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 饼图 |
| 维度 | `sales_phase` |
| 度量 | `style_no`（COUNT DISTINCT，去重 SKC 数） |
| 筛选条件 | `is_over_cycle = 0` |
| 标题 | "SKC 销售阶段分布" |

#### 4.4.3 筛选器配置

| 筛选器 | 字段 | 类型 | 默认值 |
|--------|------|------|--------|
| 品牌 | `brand` | 单选 | 韦德 |
| 系列 | `series` | 多选 | 全选 |
| IP | `ip` | 多选 | 全选 |
| 销售周期标签 | `sales_phase` | 多选 | 全选 |
| SKC 编码 | `style_no` | 文本搜索 | 空 |
| 上市天数范围 | `lifecycle_day` | 数值范围 | 1~180 |

---

### 4.5 仪表板5：SKC 维度 - 销售达成分析

#### 4.5.1 仪表板基本信息

| 项 | 取值 |
|----|------|
| 仪表板名称 | `SKC-销售达成分析` |
| 数据集 | `dataset_skc_sales_plan` |
| 主要用途 | 重点展示 SKC 维度 1~180 天达成趋势 |

#### 4.5.2 图表配置

**图表5.1：达成情况组合图（柱状图 + 折线图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 组合图 |
| X 轴 | `lifecycle_day` |
| Y 轴（柱） | `daily_qty`（SUM，实际销售） |
| Y 轴（线） | `plan_post`（SUM，销售计划后） |
| 次轴（线） | `achievement_rate`（AVG，达成情况） |
| 筛选条件 | `is_over_cycle = 0`、`lifecycle_day BETWEEN 1 AND 180` |
| 标题 | "SKC 实际销售 vs 计划 + 达成率" |

**图表5.2：昨日/7天/30天达成看板（指标卡）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 指标卡 |
| 指标1 | `yesterday_achievement`（MAX） |
| 指标2 | `7d_achievement`（MAX） |
| 指标3 | `30d_achievement`（MAX） |
| 指标4 | `today_plan_qty`（MAX） |
| 筛选条件 | `style_no = [选择 SKC]` |
| 标题 | "SKC 当前达成快照" |

**图表5.3：未达标 SKC 排行（表格）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 明细表 |
| 列 | `style_no`、`product_name`、`series`、`ip`、`lifecycle_day`、`daily_qty`、`plan_post`、`achievement_rate` |
| 筛选条件 | `is_over_cycle = 0`、`lifecycle_day BETWEEN 1 AND 180`、`achievement_rate < 1.0` |
| 排序 | `achievement_rate` 升序 |
| 标题 | "未达标 SKC 排行（达成率 < 100%）" |

**图表5.4：各阶段达成率对比（柱状图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 柱状图 |
| X 轴 | `sales_phase` |
| Y 轴 | `achievement_rate`（AVG） |
| 筛选条件 | `is_over_cycle = 0` |
| 标题 | "SKC 各销售阶段达成率对比" |

#### 4.5.3 筛选器配置

| 筛选器 | 字段 | 类型 | 默认值 |
|--------|------|------|--------|
| 品牌 | `brand` | 单选 | 韦德 |
| 系列 | `series` | 多选 | 全选 |
| IP | `ip` | 多选 | 全选 |
| 销售阶段 | `sales_phase` | 多选 | 全选 |
| SKC 编码 | `style_no` | 文本搜索 | 空 |

---

### 4.6 仪表板6：SKU/SKC 汇总对比

#### 4.6.1 仪表板基本信息

| 项 | 取值 |
|----|------|
| 仪表板名称 | `SKU/SKC 汇总对比` |
| 数据集 | `dataset_sku_skc_summary` |
| 主要用途 | SKU vs SKC 维度对比，全局汇总 |

#### 4.6.2 图表配置

**图表6.1：SKU vs SKC 全局汇总（表格）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 明细表 |
| 列 | `dim_type`、`dim_value`、`product_name`、`brand`、`series`、`ip`、`sales_cycle_label`、`lifecycle_day`、`order_qty`、`cum_qty`、`cum_amt`、`achievement_ratio`、`inventory_qty`、`sellable_days` |
| 排序 | `dim_type`、`cum_qty` 降序 |
| 标题 | "SKU/SKC 全局汇总" |

> ⚠️ **财务字段提醒**：`cum_amt`（累计金额，3.17 / 5.17 节）需人工审查确认金额单位与精度。

**图表6.2：SKU vs SKC 维度占比（饼图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 饼图 |
| 维度 | `dim_type` |
| 度量 | `cum_qty`（SUM，累计销量） |
| 标题 | "SKU vs SKC 累计销量占比" |

**图表6.3：各系列达成比例对比（柱状图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 柱状图 |
| X 轴 | `series` |
| Y 轴 | `achievement_ratio`（AVG，达成比例） |
| 颜色 | `dim_type`（SKU/SKC 对比） |
| 筛选条件 | `series != 'None'` |
| 标题 | "各系列达成比例对比（SKU vs SKC）" |

**图表6.4：各 IP 达成比例对比（柱状图）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 柱状图 |
| X 轴 | `ip` |
| Y 轴 | `achievement_ratio`（AVG） |
| 颜色 | `dim_type` |
| 筛选条件 | `ip != 'None'` |
| 标题 | "各 IP 达成比例对比（SKU vs SKC）" |

**图表6.5：累计销量 Top 10 排行（表格）**

| 配置项 | 取值 |
|--------|------|
| 图表类型 | 明细表 |
| 列 | `dim_type`、`dim_value`、`product_name`、`series`、`ip`、`cum_qty`、`cum_amt`、`achievement_ratio` |
| 筛选条件 | `dim_type = 'SKU'` |
| 排序 | `cum_qty` 降序 |
| 行数限制 | 前 10 |
| 标题 | "SKU 累计销量 Top 10" |

#### 4.6.3 筛选器配置

| 筛选器 | 字段 | 类型 | 默认值 |
|--------|------|------|--------|
| 维度类型 | `dim_type` | 单选/多选 | 全选（SKU+SKC） |
| 品牌 | `brand` | 单选 | 韦德 |
| 系列 | `series` | 多选 | 全选 |
| IP | `ip` | 多选 | 全选 |
| 销售周期标签 | `sales_cycle_label` | 多选 | 全选 |
| 上架时间范围 | `shelf_date` | 日期范围 | 空 |

---

## 五、筛选器设计

### 5.1 全局筛选器

全局筛选器作用于所有仪表板，建议在 QuickBI「数据集」级别配置（作为数据集的默认筛选条件）：

| 筛选器 | 字段 | 类型 | 默认值 | 作用 |
|--------|------|------|--------|------|
| 品牌 | `brand` | 单选 | 韦德 | 限定品牌范围（口径：韦德 4 个核心渠道） |
| 系列 | `series` | 多选 | 全选 | 按系列筛选 |
| IP | `ip` | 多选 | 全选 | 按 IP 筛选 |
| 销售周期标签 | `sales_phase` / `sales_cycle_label` | 多选 | 全选 | 按阶段筛选（新品期/热销期/清货期/超周期） |
| 上架时间范围 | `shelf_date` | 日期范围 | 空 | 按上架日期筛选 |

> **说明**：
> - SKU/SKC 维度仪表板使用 `sales_phase` 字段
> - 汇总仪表板使用 `sales_cycle_label` 字段

### 5.2 仪表板级筛选器

每个仪表板可配置局部筛选器：

| 仪表板 | 筛选器 | 字段 | 类型 | 默认值 | 说明 |
|--------|--------|------|------|--------|------|
| 仪表板1（SKU 概览） | 上市天数范围 | `lifecycle_day` | 数值范围 | 1~180 | 限定 1~180 天展示 |
| 仪表板1（SKU 概览） | 超周期过滤 | `is_over_cycle` | 单选 | 0 | 默认不展示超周期 |
| 仪表板2（SKU 达成） | 上市天数范围 | `lifecycle_day` | 数值范围 | 1~180 | 限定 1~180 天展示 |
| 仪表板3（SKU 库存） | 可售周期范围 | `sellable_days` | 数值范围 | 空 | 库存预警用 |
| 仪表板4（SKC 概览） | 上市天数范围 | `lifecycle_day` | 数值范围 | 1~180 | 限定 1~180 天展示 |
| 仪表板4（SKC 概览） | 超周期过滤 | `is_over_cycle` | 单选 | 0 | 默认不展示超周期 |
| 仪表板5（SKC 达成） | 上市天数范围 | `lifecycle_day` | 数值范围 | 1~180 | 限定 1~180 天展示 |
| 仪表板6（汇总对比） | 维度类型 | `dim_type` | 单选/多选 | 全选 | SKU/SKC 切换 |

---

## 六、关键指标计算字段

### 6.1 销售计划展示逻辑

在 QuickBI 数据集中创建自定义字段，控制 1~180 天销售计划的展示：

**SKU 数据集（dataset_sku_sales_plan）：**

```sql
-- 销售计划(前)展示字段：1~180天有值，超周期为NULL
plan_pre_display = CASE WHEN [lifecycle_day] <= 180 THEN [plan_pre] ELSE NULL END

-- 销售计划(后)展示字段：1~180天有值，超周期为NULL
plan_post_display = CASE WHEN [lifecycle_day] <= 180 THEN [plan_post] ELSE NULL END
```

**SKC 数据集（dataset_skc_sales_plan）：**

```sql
-- 同 SKU 逻辑
plan_pre_display = CASE WHEN [lifecycle_day] <= 180 THEN [plan_pre] ELSE NULL END
plan_post_display = CASE WHEN [lifecycle_day] <= 180 THEN [plan_post] ELSE NULL END
```

> **口径依据**（4.3 / 4.4 / 6.3 / 6.4 节）：销售计划仅在 1~180 天有效，超周期阶段销售计划为 NULL

### 6.2 达成情况颜色标记

为达成率字段创建颜色标记，便于业务直观判断：

**达成率颜色标记（achievement_rate）：**

```sql
-- 颜色标记字段
achievement_color = CASE
    WHEN [achievement_rate] IS NULL THEN '灰色'       -- 无数据
    WHEN [achievement_rate] >= 1.0 THEN '绿色'        -- 达成或超预期
    WHEN [achievement_rate] >= 0.8 THEN '黄色'        -- 接近达成
    WHEN [achievement_rate] < 0.8 THEN '红色'         -- 未达标
    ELSE '灰色'
END
```

**达成比例颜色标记（achievement_ratio）：**

```sql
-- 累计达成比例颜色标记
ratio_color = CASE
    WHEN [achievement_ratio] IS NULL THEN '灰色'
    WHEN [achievement_ratio] >= 1.0 THEN '绿色'
    WHEN [achievement_ratio] >= 0.8 THEN '黄色'
    WHEN [achievement_ratio] < 0.8 THEN '红色'
    ELSE '灰色'
END
```

> **颜色含义**：
> - 绿色（>=100%）：达成或超预期
> - 黄色（80%~100%）：接近达成，需关注
> - 红色（<80%）：未达标，需预警
> - 灰色：无数据

### 6.3 超周期过滤逻辑

超周期（lifecycle_day > 180）的行展示规则：

```sql
-- 超周期标记字段
is_over_cycle_flag = CASE WHEN [lifecycle_day] > 180 THEN '超周期' ELSE '正常' END

-- 超周期过滤条件（应用于图表筛选器）
-- 方式1：通过 is_over_cycle 字段筛选
WHERE is_over_cycle = 0

-- 方式2：通过 lifecycle_day 范围筛选
WHERE lifecycle_day BETWEEN 1 AND 180
```

> **超周期展示规则**（4.2 / 6.2 节）：
> - 超周期行的 `plan_pre`、`plan_post`、`achievement_rate` 为 NULL
> - 超周期行只展示：日销量、日金额、累计销量、累计金额、在仓库存、可提库存、可售周期
> - 展示 1~180 天销售计划时，必须筛选 `is_over_cycle = 0`

### 6.4 库存预警计算字段

```sql
-- 可售周期预警级别
sellable_days_alert = CASE
    WHEN [sellable_days] IS NULL THEN '无数据'
    WHEN [sellable_days] < 7 THEN '紧急预警'       -- 不足7天
    WHEN [sellable_days] < 30 THEN '预警'          -- 不足30天
    WHEN [sellable_days] < 90 THEN '关注'          -- 不足90天
    ELSE '正常'                                    -- 90天以上
END
```

> ⚠️ **库存预警提醒**（3.11 / 5.11 节）：可售周期 = 在仓库存 / 30 天平均日销，当日销为 0 时返回 NULL，需确认业务展示逻辑。

---

## 七、数据刷新与调度

### 7.1 数据刷新频率

| 数据集 | 刷新频率 | 刷新方式 | 说明 |
|--------|---------|---------|------|
| `dataset_sku_sales_plan` | 日刷新 | 依赖 ADS 层 ETL | ADS 层每日全量重算 |
| `dataset_skc_sales_plan` | 日刷新 | 依赖 ADS 层 ETL | ADS 层每日全量重算 |
| `dataset_sku_skc_summary` | 日刷新 | 依赖 ADS 层 ETL | ADS 层每日全量重算 |

### 7.2 调度依赖

```
DWD 层 ETL (日刷新)
    │
    ▼
DWS 层 ETL (日刷新, 6 张表)
    │  前置依赖: DWD 层全部刷新完成
    ▼
ADS 层 ETL (日刷新, 3 张表)
    │  前置依赖: DWS 层 6 张表全部刷新完成
    │  执行顺序:
    │    1. ads_sku_sales_plan_180d_d
    │    2. ads_skc_sales_plan_180d_d
    │    3. ads_sku_skc_summary_d
    ▼
QuickBI 数据集刷新
    │  前置依赖: ADS 层 3 张表全部刷新完成
    │  刷新方式: 直连模式，无需主动刷新，查询时实时获取最新数据
    ▼
QuickBI 仪表板展示
```

**调度时间建议**：

| 层级 | 建议完成时间 | 说明 |
|------|-------------|------|
| DWD 层 | 每日 06:00 前 | ODS 同步完成后 |
| DWS 层 | 每日 07:00 前 | DWD 完成后 |
| ADS 层 | 每日 08:00 前 | DWS 完成后 |
| QuickBI 可用 | 每日 08:00 后 | 业务人员上班前数据就绪 |

### 7.3 缓存配置

QuickBI 直连 StarRocks 模式下的缓存配置建议：

| 配置项 | 建议值 | 说明 |
|--------|--------|------|
| 缓存开关 | 开启 | 启用查询缓存 |
| 缓存有效期 | 1 小时 | 数据日刷新，缓存 1 小时即可 |
| 缓存粒度 | 仪表板级 | 按仪表板查询结果缓存 |
| 缓存刷新触发 | ADS 层 ETL 完成后 | 可配置 ETL 完成回调通知 QuickBI 清缓存 |

> **缓存策略说明**：
> - 由于 ADS 层为日刷新，缓存有效期设为 1 小时即可平衡性能与数据新鲜度
> - 重要决策场景可手动刷新缓存
> - 高频查询的仪表板（如仪表板1、4）建议开启缓存

---

## 八、QuickBI 实施步骤

### 8.1 创建数据源

**操作步骤**：

1. 登录 QuickBI 控制台
2. 进入「工作台」→「数据源」
3. 点击「新建数据源」
4. 选择「StarRocks」
5. 填写连接参数：
   - 数据源名称：`starrocks_weide_bi`
   - 主机地址：StarRocks FE 节点 IP
   - 端口：9030
   - 数据库：`feishu_ads`
   - 用户名：`bi_reader`
   - 密码：`******`
6. 点击「连接测试」，确认连接成功
7. 点击「保存」

**验证点**：
- 连接测试通过
- 可在数据源下看到 `feishu_ads` 库的 3 张 ADS 表

### 8.2 创建数据集

#### 8.2.1 创建数据集1：SKU 销售计划

1. 进入「数据源」→ 选择 `starrocks_weide_bi`
2. 找到 `feishu_ads.ads_sku_sales_plan_180d_d` 表
3. 点击「创建数据集」
4. 数据集名称：`dataset_sku_sales_plan`
5. 配置字段类型（参考 3.1.2 节）：
   - 维度字段：`style_no_size`、`sale_date`、`lifecycle_day`、`sale_date_label`、`sales_phase`、`is_over_cycle`、`brand`、`style_no`、`size`、`ip`、`series`、`color_name`、`product_name`、`category`、`shelf_date`、`first_sales_date`
   - 度量字段：`plan_pre`、`plan_post`、`daily_qty`、`daily_amt`、`cum_qty`、`cum_amt`、`achievement_rate`、`inventory_sku`、`available_inventory`、`daily_avg_qty_30d`、`sellable_days`、`yesterday_actual_qty`、`yesterday_achievement`、`7d_achievement`、`30d_achievement`、`today_plan_qty`、`order_qty`、`total_order_qty`、`achievement_ratio`
6. 配置字段聚合方式（参考 3.1.2 节度量字段表）
7. 创建自定义计算字段（参考第六章）：
   - `plan_pre_display`
   - `plan_post_display`
   - `achievement_color`
   - `sellable_days_alert`
8. 保存数据集

#### 8.2.2 创建数据集2：SKC 销售计划

1. 重复 8.2.1 步骤，选择 `feishu_ads.ads_skc_sales_plan_180d_d` 表
2. 数据集名称：`dataset_skc_sales_plan`
3. 字段配置参考 3.2.2 节
4. 注意：库存字段为 `inventory_skc`（非 `inventory_sku`）
5. 保存数据集

#### 8.2.3 创建数据集3：SKU/SKC 汇总

1. 重复 8.2.1 步骤，选择 `feishu_ads.ads_sku_skc_summary_d` 表
2. 数据集名称：`dataset_sku_skc_summary`
3. 字段配置参考 3.3.2 节
4. 保存数据集

### 8.3 创建仪表板

#### 8.3.1 创建仪表板1：SKU-1~180天销售计划概览

1. 进入「仪表板」→「新建仪表板」
2. 仪表板名称：`SKU-1~180天销售计划概览`
3. 选择数据集：`dataset_sku_sales_plan`
4. 添加图表（参考 4.1.2 节）：
   - 图表1.1：折线图（销售计划 vs 实际销售趋势）
   - 图表1.2：柱状图（达成情况趋势）
   - 图表1.3：明细表（SKU 销售计划明细）
   - 图表1.4：饼图（销售阶段分布）
5. 配置每个图表的字段、筛选条件、排序
6. 调整图表布局（建议：折线图占顶部 2/3，柱状图和饼图并排，明细表占底部）
7. 保存仪表板

#### 8.3.2 创建仪表板2~6

重复 8.3.1 步骤，按第四章各节配置创建仪表板2~6：

- 仪表板2：`SKU-销售达成分析`（参考 4.2 节）
- 仪表板3：`SKU-库存与可售周期`（参考 4.3 节）
- 仪表板4：`SKC-1~180天销售计划概览`（参考 4.4 节）
- 仪表板5：`SKC-销售达成分析`（参考 4.5 节）
- 仪表板6：`SKU/SKC 汇总对比`（参考 4.6 节）

### 8.4 配置筛选器和交互

#### 8.4.1 配置全局筛选器

1. 进入每个仪表板编辑页面
2. 点击「筛选器」区域
3. 添加全局筛选器（参考 5.1 节）：
   - 品牌（`brand`）
   - 系列（`series`）
   - IP（`ip`）
   - 销售周期标签（`sales_phase` 或 `sales_cycle_label`）
   - 上架时间范围（`shelf_date`）
4. 配置筛选器联动：品牌 → 系列 → IP 层级联动

#### 8.4.2 配置仪表板级筛选器

1. 在每个仪表板中添加局部筛选器（参考 5.2 节）
2. 配置上市天数范围（`lifecycle_day BETWEEN 1 AND 180`）
3. 配置超周期过滤（`is_over_cycle = 0`）

#### 8.4.3 配置图表交互

1. 配置明细表的「跳转」功能：点击某行 SKU 可跳转到该 SKU 的详细分析
2. 配置图表的「联动」功能：选择某系列时，其他图表自动过滤
3. 配置指标卡的「下钻」功能：点击指标可下钻到明细

### 8.5 发布与分享

#### 8.5.1 发布仪表板

1. 仪表板编辑完成后，点击「发布」按钮
2. 填写发布说明（如版本号、更新内容）
3. 确认发布

#### 8.5.2 分享仪表板

1. 进入「仪表板」列表
2. 选择要分享的仪表板，点击「分享」
3. 配置分享权限：
   - 指定用户/用户组
   - 设置权限级别（查看/编辑）
   - 设置有效期
4. 发送分享链接给业务人员

#### 8.5.3 嵌入外部系统（可选）

1. 在仪表板设置中开启「嵌入」
2. 获取嵌入代码
3. 将嵌入代码集成到企业内部系统（如钉钉、飞书工作台）

---

## 九、常见问题与优化

### 9.1 数据量优化

**问题**：SKU 数 × 天数（180+超周期）数据量大，查询慢

**解决方案**：

| 优化项 | 说明 |
|--------|------|
| 分区裁剪 | QuickBI 查询时带 `sale_date` 条件，自动触发 StarRocks 分区裁剪 |
| 超周期过滤 | 默认筛选 `is_over_cycle = 0`，减少数据量 |
| 上市天数范围 | 限定 `lifecycle_day BETWEEN 1 AND 180` |
| 时间范围限制 | 业务人员查询时限定近 30/90 天数据 |
| SKU 范围限制 | 通过品牌/系列/IP 筛选器缩小范围 |

### 9.2 查询性能优化

**优化建议**：

| 优化项 | 说明 |
|--------|------|
| StarRocks 索引 | 为 `style_no`、`style_no_size`、`sale_date` 添加 Bloom Filter |
| Colocate Join | ADS 表与 DWS 表配置 `colocate_with` 同组 |
| QuickBI 缓存 | 开启 1 小时缓存，减少重复查询 |
| 避免全表扫描 | 所有图表必须带时间范围筛选条件 |
| 使用明细表代替聚合 | 明细表查询性能优于复杂聚合图表 |

### 9.3 展示优化

| 优化项 | 说明 |
|--------|------|
| 金额格式化 | `daily_amt`、`cum_amt` 格式化为 2 位小数 + 千分位 |
| 百分比展示 | `achievement_rate`、`achievement_ratio` 等乘以 100 并加 % 后缀 |
| 日期格式化 | `sale_date` 格式化为 YYYY-MM-DD |
| 空值处理 | NULL 显示为 "-" 或 "无数据" |
| 颜色标记 | 达成率 >=100% 绿色，<100% 红色（参考 6.2 节） |
| 字段别名 | 中文字段别名（如 `style_no_size` → "SKU 编码"） |

### 9.4 常见问题排查

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 仪表板无数据 | ADS 层 ETL 未刷新 | 检查 ADS 层 ETL 调度状态 |
| 达成率为空 | `plan_post = 0` 导致除零 | 正常现象，`NULLIF` 防除零 |
| 可售周期为空 | 30 天平均日销为 0 | 正常现象，业务确认展示逻辑 |
| 超周期行有计划值 | 数据异常 | 校验 `is_over_cycle = 1` 时 `plan_pre`/`plan_post` 是否为 NULL |
| SKU 与 SKC 数据不一致 | 维度聚合差异 | 正常现象，SKC 为 SKU 按 `style_no` 聚合 |
| 日期筛选不生效 | 字段类型错误 | 确认 `sale_date` 为 DATE 类型 |

---

## 十、业务指标速查表

### 10.1 SKU 维度字段映射表（对应口径文档 8.1 节）

| 业务字段 | ADS 字段 | 数据集字段 | 聚合方式 | 口径章节 | 说明 |
|---------|---------|-----------|---------|---------|------|
| SKU | `style_no_size` | 维度 | - | 3.1 | 直接展示 |
| 品牌 | `brand` | 维度 | - | 3.2 | 直接展示 |
| 系列 | `series` | 维度 | - | 3.3 | 直接展示 |
| IP | `ip` | 维度 | - | 3.4 | 直接展示 |
| 上架时间 | `shelf_date` | 维度 | - | 3.5 | 仅展示 |
| 首次销售日期 | `first_sales_date` | 维度 | - | 3.6 | 仅展示 |
| 已上架天数 | `lifecycle_day` | 维度 | - | 3.7 | 当前日期对应 |
| 销售周期标签 | `sales_phase` | 维度 | - | 3.8 | 新品期/热销期/清货期/超周期 |
| 在仓库存 | `inventory_sku` | 度量 | MAX ⚠️ | 3.9 | 直接展示 |
| 可提库存 | `available_inventory` | 度量 | MAX ⚠️ | 3.10 | 直接展示 |
| 可售周期(天) | `sellable_days` | 度量 | MAX ⚠️ | 3.11 | 直接展示 |
| 30天平均日销 | `daily_avg_qty_30d` | 度量 | MAX | 3.12 | 直接展示 |
| 日销量 | `daily_qty` | 度量 | SUM | 3.14 | 按 sale_date 展示 |
| 日金额 | `daily_amt` | 度量 | SUM ⚠️ | 3.15 | 按 sale_date 展示 |
| 累计销量 | `cum_qty` | 度量 | MAX | 3.16 | 直接展示 |
| 累计金额 | `cum_amt` | 度量 | MAX ⚠️ | 3.17 | 直接展示 |
| 订货数量 | `order_qty` | 度量 | MAX | 3.18 | 直接展示 |
| 达成比例 | `achievement_ratio` | 度量 | MAX | 3.19 | 累计销量/订货数量 |
| 总订货数量 | `total_order_qty` | 度量 | MAX ⚠️ | 3.20 | 直接展示 |
| 昨日实际销售 | `yesterday_actual_qty` | 度量 | MAX | 3.21 | 直接展示 |
| 昨日销售达成情况 | `yesterday_achievement` | 度量 | MAX | 3.22 | 直接展示 |
| 7天销售达成情况 | `7d_achievement` | 度量 | MAX | 3.23 | 直接展示 |
| 30天销售达成情况 | `30d_achievement` | 度量 | MAX | 3.24 | 直接展示 |
| 今日计划销售数量 | `today_plan_qty` | 度量 | MAX | 3.25 | 直接展示 |
| 1~180天①销售计划(前) | `plan_pre` | 度量 | SUM | 4.3 | 按 lifecycle_day 展示 |
| 1~180天②销售计划(后) | `plan_post` | 度量 | SUM | 4.4 | 按 lifecycle_day 展示 |
| 1~180天③实际销售 | `daily_qty` | 度量 | SUM | 4.5 | 按 lifecycle_day 展示 |
| 1~180天④达成情况 | `achievement_rate` | 度量 | AVG | 4.6 | 按 lifecycle_day 展示 |

### 10.2 SKC 维度字段映射表（对应口径文档 8.2 节）

| 业务字段 | ADS 字段 | 数据集字段 | 聚合方式 | 口径章节 | 说明 |
|---------|---------|-----------|---------|---------|------|
| SKC | `style_no` | 维度 | - | 5.1 | 直接展示 |
| 品牌 | `brand` | 维度 | - | 5.2 | 直接展示 |
| 系列 | `series` | 维度 | - | 5.3 | 直接展示 |
| IP | `ip` | 维度 | - | 5.4 | 直接展示 |
| 上架时间 | `shelf_date` | 维度 | - | 5.5 | MIN(shelf_date)，仅展示 |
| 首次销售日期 | `first_sales_date` | 维度 | - | 5.6 | MIN(first_sales_date) |
| 已上架天数 | `lifecycle_day` | 维度 | - | 5.7 | 当前日期对应 |
| 销售周期标签 | `sales_phase` | 维度 | - | 5.8 | 新品期/热销期/清货期/超周期 |
| SKC在仓库存 | `inventory_skc` | 度量 | MAX ⚠️ | 5.9 | SUM(inventory_sku) 按 style_no 聚合 |
| SKC可提库存 | `available_inventory` | 度量 | MAX ⚠️ | 5.10 | SUM(inventory_qty) 按 style_no 聚合 |
| SKC可售周期(天) | `sellable_days` | 度量 | MAX ⚠️ | 5.11 | SKC 在仓库存 / SKC 30天平均日销 |
| SKC 30天平均日销 | `daily_avg_qty_30d` | 度量 | MAX | 5.12 | 直接展示 |
| SKC日销量 | `daily_qty` | 度量 | SUM | 5.14 | 按 sale_date 展示 |
| SKC日金额 | `daily_amt` | 度量 | SUM ⚠️ | 5.15 | 按 sale_date 展示 |
| SKC累计销量 | `cum_qty` | 度量 | MAX | 5.16 | 直接展示 |
| SKC累计金额 | `cum_amt` | 度量 | MAX ⚠️ | 5.17 | 直接展示 |
| SKC订货数量 | `order_qty` | 度量 | MAX | 5.18 | SUM(order_qty) 按 style_no 聚合 |
| SKC达成比例 | `achievement_ratio` | 度量 | MAX | 5.19 | SKC累计销量 / SKC订货数量 |
| SKC总订货数量 | `total_order_qty` | 度量 | MAX ⚠️ | 5.20 | 直接展示 |
| SKC昨日实际销售 | `yesterday_actual_qty` | 度量 | MAX | 5.21 | 直接展示 |
| SKC昨日销售达成情况 | `yesterday_achievement` | 度量 | MAX | 5.22 | 直接展示 |
| SKC 7天销售达成情况 | `7d_achievement` | 度量 | MAX | 5.23 | 直接展示 |
| SKC 30天销售达成情况 | `30d_achievement` | 度量 | MAX | 5.24 | 直接展示 |
| SKC今日计划销售数量 | `today_plan_qty` | 度量 | MAX | 5.25 | 直接展示 |
| 1~180天①销售计划(前) | `plan_pre` | 度量 | SUM | 6.3 | 按 lifecycle_day 展示 |
| 1~180天②销售计划(后) | `plan_post` | 度量 | SUM | 6.4 | 按 lifecycle_day 展示 |
| 1~180天③实际销售 | `daily_qty` | 度量 | SUM | 6.5 | 按 lifecycle_day 展示 |
| 1~180天④达成情况 | `achievement_rate` | 度量 | AVG | 6.6 | 按 lifecycle_day 展示 |

### 10.3 汇总表字段映射表

| 业务字段 | ADS 字段 | 数据集字段 | 聚合方式 | 口径章节 | 说明 |
|---------|---------|-----------|---------|---------|------|
| 维度类型 | `dim_type` | 维度 | - | - | SKU / SKC |
| 维度值 | `dim_value` | 维度 | - | - | SKU=style_no_size, SKC=style_no |
| 品牌 | `brand` | 维度 | - | 3.2/5.2 | 直接展示 |
| 系列 | `series` | 维度 | - | 3.3/5.3 | 直接展示 |
| IP | `ip` | 维度 | - | 3.4/5.4 | 直接展示 |
| 上架时间 | `shelf_date` | 维度 | - | 3.5/5.5 | 直接展示 |
| 首次销售日期 | `first_sales_date` | 维度 | - | 3.6/5.6 | 直接展示 |
| 当日已上架天数 | `lifecycle_day` | 维度 | - | 3.7/5.7 | 直接展示 |
| 销售周期标签 | `sales_cycle_label` | 维度 | - | 3.8/5.8 | 新品期/热销期/清货期/超周期 |
| 订货数量 | `order_qty` | 度量 | SUM | 3.18/5.18 | 直接展示 |
| 总订货数量 | `total_order_qty` | 度量 | SUM ⚠️ | 3.20/5.20 | 直接展示 |
| 累计销量 | `cum_qty` | 度量 | SUM | 3.16/5.16 | 截至昨日 |
| 累计金额 | `cum_amt` | 度量 | SUM ⚠️ | 3.17/5.17 | 截至昨日 |
| 在仓库存 | `inventory_qty` | 度量 | SUM ⚠️ | 3.9/5.9 | SKU=inventory_sku, SKC=inventory_skc |
| 可提库存 | `available_inventory` | 度量 | SUM ⚠️ | 3.10/5.10 | 直接展示 |
| 30天平均日销 | `daily_avg_qty_30d` | 度量 | AVG | 3.12/5.12 | 直接展示 |
| 可售周期(天) | `sellable_days` | 度量 | AVG ⚠️ | 3.11/5.11 | 直接展示 |
| 达成比例 | `achievement_ratio` | 度量 | AVG | 3.19/5.19 | 累计销量/订货数量 |
| 昨日实际销售 | `yesterday_actual_qty` | 度量 | SUM | 3.21/5.21 | 直接展示 |
| 今日计划销售数量 | `today_plan_qty` | 度量 | SUM | 3.25/5.25 | 超周期为0 |

---

## 附录：口径速查

### A.1 销售阶段定义（4.2 / 6.2 节）

| 阶段 | lifecycle_day 范围 | ratio | sales_phase |
|------|-------------------|-------|-------------|
| 新品期 | 1~30 | 0.8 | 新品期 |
| 热销期 | 31~120 | 1.1 | 热销期 |
| 清货期 | 121~180 | 1.0 | 清货期 |
| 超周期 | >180 | NULL | 超周期 |

### A.2 销售计划公式（4.3 / 4.4 / 6.3 / 6.4 节）

| 指标 | 公式 | 适用范围 |
|------|------|---------|
| plan_pre | `Q * ratio / 180` | 1~180 天 |
| plan_post | `(Q - cum_actual) * ratio / (181 - N)` | 1~180 天 |
| achievement_rate | `daily_qty / plan_post` | 1~180 天 |

> **说明**：
> - Q = 订货数量（3.18 / 5.18 节）
> - cum_actual = 截至第 N-1 天的实际销量总和
> - N = 上市第 N 天（lifecycle_day）

### A.3 上市第 N 天计算（4.1 / 6.1 节）

| 维度 | 计算公式 |
|------|---------|
| SKU | `lifecycle_day = DATEDIFF(sale_date, shelf_date) + 1` |
| SKC | `lifecycle_day = DATEDIFF(sale_date, MIN(shelf_date)) + 1` |

### A.4 sale_date_label 格式

| lifecycle_day | sale_date_label |
|---------------|-----------------|
| 1 | 第1天 |
| 30 | 第30天 |
| 180 | 第180天 |
| >180 | 超周期 |

### A.5 ⚠️ 财务/库存字段审查清单

以下字段涉及财务金额或库存数据，**上线前必须由业务方人工审查**：

| 字段 | 审查要点 | 口径章节 |
|------|---------|---------|
| `daily_amt` | 金额单位（元）、精度（DECIMAL(18,6)）、是否含税 | 3.15 / 5.15 |
| `cum_amt` | 累计金额计算逻辑、时间范围 | 3.17 / 5.17 |
| `tag_price` | 吊牌价是否含税 | - |
| `inventory_sku` / `inventory_skc` | 在仓库存来源（商品库实时快照） | 3.9 / 5.9 |
| `available_inventory` | 可提库存来源（品牌方库存表最新快照） | 3.10 / 5.10 |
| `total_order_qty` | 补货数量逻辑（is_replenish='是' 时加上 replenish_qty） | 3.20 / 5.20 |
| `sellable_days` | 日销为 0 时返回 NULL 的业务展示逻辑 | 3.11 / 5.11 |
| `achievement_ratio` | 分母为 0 时返回 NULL 的业务展示逻辑 | 3.19 / 5.19 |

---

> **文档结束**
> 本文档严格依据 `基于DWD层的字段口径定义.md` 和 `ADS.md` 生成，所有字段计算逻辑以口径文档为准。
> 涉及财务金额、库存的字段已标注 ⚠️ 人工审查提醒，上线前请业务方确认。
> QuickBI 实施过程中如遇到口径疑问，请对照口径文档相应章节核实。
