# DWD 层优化建议

> 编写日期：2026-07-05
> 审查对象：`杭州博耶数据科技有限公司/库存销售计划/DWD.md`（DWD 层解决方案文档）
> 参考依据：
> - `指标口径/基于DWD层的字段口径定义.md`（2026-07-05 修订版）
> - `指标口径/新品-热销-清货期销售分析-最终效果页.md`（Excel 业务口径原文件）
> 适用范围：361品牌 + 韦德品牌，SKU / SKC 维度
> 审查人：数仓架构专家

---

## 一、审查概述

### 1.1 审查范围

本次审查覆盖 DWD.md 中定义的 8 张表：

| 表编号 | 表名 | 粒度 | 重点关注项 |
|--------|------|------|------------|
| DWD-1 | `dwd_feishu_sales_361_d` | 品牌+SKU+销售日期+渠道 | 361 宽表合并 |
| DWD-2 | `dwd_feishu_sales_wd_d` | 品牌+SKU+销售日期+渠道 | 韦德 18 渠道宽表，结构差异对齐 |
| DWD-3 | `dwd_feishu_sales_all_d` | 品牌+SKU+销售日期+渠道（长表） | first_sales_date 处理、shelf_date 缺失 |
| DWD-4 | `dwd_feishu_product_wd_d` | SKU | 韦德特有字段（is_replenish 等） |
| DWD-5 | `dwd_feishu_product_361_d` | SKU | 361 actual_shelf_date 映射 |
| DWD-6 | `dwd_feishu_product_all_d` | SKU+品牌 | 字段统一、特有字段丢失 |
| DWD-7 | `dwd_feishu_inventory_wdpinpai_d` | SKU+更新日期 | 仅韦德有，361 缺失 |
| DWD-8 | `dwd_feishu_otb_wd_d` | IP+年度 | OTB 双字段语义 |

### 1.2 总体评价

DWD.md 整体方案已较完善：

- ✅ 分表合并策略清晰（50 张分表 UNION ALL）
- ✅ 长表设计合理（DWD-3 渠道转行，扩展性强）
- ✅ 字段命名标准化（英文 snake_case）
- ✅ 类型转换规范（数量 BIGINT、金额 DECIMAL(18,6)）
- ✅ 空值兜底完整（COALESCE+NULLIF+TRIM）
- ✅ PRIMARY KEY 模型 + enable_persistent_index 配置正确
- ✅ 已新增 DWD-4 韦德商品库表保留特有字段

但对照字段口径定义和业务文档，仍存在以下关键问题需调整：

### 1.3 问题严重度分布

| 严重度 | 数量 | 说明 |
|--------|------|------|
| 🔴 高 | 4 | 影响 361 品牌 1~180 天分析、达成比例计算等核心指标 |
| 🟡 中 | 5 | 影响字段完整性、ETL 健壮性、查询性能 |
| 🟢 低 | 3 | 优化建议，非阻塞性问题 |

---

## 二、逐项问题诊断

### 审查要点 1：first_sales_date 字段处理

#### 问题 1.1【🟡 中】DWD-3 销售明细表 361 品牌 first_sales_date 兜底值不一致

**问题描述**：
- DWD-3 `dwd_feishu_sales_all_d` 表中 361 品牌的 `first_sales_date` 在不同位置处理方式不一致：
  - 字段 COMMENT（DWD.md 第 1059 行）：`"首次销售日期(361为1970-01-01)"`
  - 注释说明（DWD.md 第 1085 行）：`"注：361系列无 first_sales_date，该字段置 NULL"`
  - 实际 SQL（DWD.md 第 1092 行）：`DATE('1970-01-01')` 兜底
- 而字段口径定义文档（1.1 节）明确写：`first_sales_date DATE 首次销售日期（361为1970-01-01）`

**影响分析**：
- 兜底值 `1970-01-01` 与 NULL 在下游计算时行为不同：
  - `DATEDIFF(CURRENT_DATE(), '1970-01-01')` 会得到 20000+ 天的脏数据
  - `DATEDIFF(CURRENT_DATE(), NULL)` 返回 NULL，下游可识别
- 虽然字段口径定义已明确"first_sales_date 不再作为已上架天数等指标计算基准，仅作参考字段"，但仍可能误导下游 DWS 开发者

**调整建议**：
统一为 NULL 兜底（更符合"无值"的语义），并修正 COMMENT：

```sql
-- DWD-3 表结构定义修正
`first_sales_date` DATE COMMENT "首次销售日期(韦德取值,361为NULL,仅作参考字段,不作为已上架天数计算基准)",

-- DWD-3 ETL 361品牌插入修正（第1092行附近）
-- 原：DATE('1970-01-01')
-- 改：
SELECT id, sales_date, record_id, brand, sku, 'None', 'None', CAST(NULL AS DATE) AS first_sales_date,
       '361sport', '361sport', '自营',
       qty_361sport, amt_361sport, sync_time, source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_361_d
WHERE qty_361sport <> 0 OR amt_361sport <> 0;
```

**优先级**：🟡 中（不影响核心指标，但影响数据语义清晰度）

---

#### 问题 1.2【🔴 高】361 品牌 first_sales_date 是否在 DWD 层预计算

**问题描述**：
- 字段口径定义 3.5 节明确：361 品牌的 `first_sales_date` 需从销售明细表 `MIN(sales_date)` 计算
- DWD-6 统一商品库（DWD.md 第 1792 行）对 361 品牌直接置 NULL，未做预计算
- 字段口径定义 2026-07-05 优化说明称"361 不再强制补充计算"，但 SKC 维度首次销售日期（5.4 节）仍需计算

**影响分析**：
- 虽然已上架天数、销售周期标签、累计销量等核心指标已改为基于 `shelf_date` 计算，361 品牌不依赖 `first_sales_date`
- 但业务文档仍将 `first_sales_date` 作为"业务参考字段"展示在 QuickBI 报表中
- 若 361 品牌该字段为 NULL，QuickBI 报表会显示空白，业务方可能误认为数据缺失
- 若每个 DWS 任务都重新 `MIN(sales_date)` 计算，重复扫描销售明细表，性能开销大

**调整建议**：
推荐方案：在 DWD-6 统一商品库 ETL 中预计算 361 品牌的 `first_sales_date`，避免下游重复计算。

```sql
-- DWD-6 361品牌插入改为预计算 first_sales_date
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku, sync_time,
    insert_date, update_date
)
SELECT
    p.sku,
    '361' AS brand,
    p.style_no, p.ip, p.series,
    NULL AS color_name,
    p.product_name, p.category, p.size_us AS size,
    p.tag_price, p.order_qty, p.order_date,
    p.actual_shelf_date AS shelf_date,
    -- 预计算：从销售明细表取最早有销量的日期
    COALESCE(fs.first_sales_date, CAST(NULL AS DATE)) AS first_sales_date,
    p.first_order_quarter,
    NULL AS year,
    NULL AS inventory_sku,
    p.sync_time,
    NOW(), NOW()
FROM feishu_dwd.dwd_feishu_product_361_d p
LEFT JOIN (
    SELECT sku, MIN(sales_date) AS first_sales_date
    FROM feishu_dwd.dwd_feishu_sales_all_d
    WHERE brand = '361' AND qty > 0
    GROUP BY sku
) fs ON p.sku = fs.sku
WHERE p.sku IS NOT NULL;
```

**优先级**：🔴 高（影响 361 品牌业务参考字段完整性）

---

#### 问题 1.3【🟡 中】DWD-3 销售明细表 first_sales_date 字段冗余

**问题描述**：
- DWD-3 `dwd_feishu_sales_all_d` 长表中保留了 `first_sales_date` 字段（DWD.md 第 1059 行）
- 但 `first_sales_date` 是 SKU 维度的属性（同一 SKU 在所有销售日期都相同），不应放在销售明细表中
- 这导致同一 SKU 的所有销售记录都重复存储 `first_sales_date`，造成数据冗余

**影响分析**：
- 存储浪费：450 万行销售明细每行多存一个 DATE 字段（4 字节），约 18MB 冗余
- 维护困难：若韦德商品库的 `first_sales_date` 更新，需同步更新所有销售明细记录
- 范式违反：违反第三范式，SKU 属性应放在商品库表，不应冗余到事实表

**调整建议**：
方案 A（推荐）：DWD-3 删除 `first_sales_date` 字段，下游通过 `sku + brand` 关联 DWD-6 获取。

```sql
-- DWD-3 表结构修正（删除 first_sales_date 字段）
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_all_d (
    `record_id`           VARCHAR(64)     COMMENT "飞书记录唯一ID(主键,溯源用)",
    `sales_date`          DATE            COMMENT "销售日期(主键,分区键)",
    `channel_code`        VARCHAR(50)     COMMENT "渠道编码(主键,英文标准名)",
    `id`                  BIGINT          COMMENT "自增ID(溯源用)",
    `brand`               VARCHAR(20)     COMMENT "品牌:361/韦德",
    `sku`                 VARCHAR(64)     COMMENT "SKU编码",
    `style_no`            VARCHAR(64)     COMMENT "款号(361为None)",
    `size`                VARCHAR(20)     COMMENT "尺码(361为None)",
    -- 删除 first_sales_date 字段，下游 JOIN dwd_feishu_product_all_d 获取
    `channel_name`        VARCHAR(100)    COMMENT "渠道中文名称",
    `channel_type`        VARCHAR(30)     COMMENT "渠道类型:自营/寄售/分销/海外/平台/其他",
    `qty`                 BIGINT          COMMENT "销量(件/双,整数)",
    `amt`                 DECIMAL(18,6)   COMMENT "金额(元,保留6位小数)",
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `source_table`        VARCHAR(50)     COMMENT "数据来源表名",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间(ETL写入)",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`record_id`, `sales_date`, `channel_code`)
...
```

方案 B（保守）：若担心下游 JOIN 性能，可保留字段，但需在文档中明确标注"冗余字段，更新策略：每日全量重建"。

**优先级**：🟡 中（不影响功能，影响数据规范化）

---

### 审查要点 2：shelf_date 字段处理

#### 问题 2.1【🔴 高】DWD-3 销售明细表缺失 shelf_date 字段

**问题描述**：
- 字段口径定义 1.1 节明确指出：DWD-3 `dwd_feishu_sales_all_d` 表**不含 `shelf_date`**（上架日期）
- 但已上架天数、累计销量、1~180天实际销售等核心指标的计算公式都需要 `shelf_date`：
  - 已上架天数 = `DATEDIFF(CURRENT_DATE(), shelf_date) + 1`
  - 累计销量：`sales_date BETWEEN shelf_date AND DATE_SUB(CURRENT_DATE(), 1)`
  - 1~180天实际销售：`DATEDIFF(sales_date, shelf_date) + 1 = N`
- 这意味着 DWS 层每次计算这些指标都必须 JOIN `dwd_feishu_product_all_d` 表获取 `shelf_date`

**影响分析**：
- DWS 层频繁 JOIN 商品库表，性能开销大
- 若商品库 shelf_date 更新滞后，销售指标的"上架日期基准"会不一致
- 业务文档明确"已上架天数 = today()-上架日期+1"，shelf_date 是核心基准字段

**调整建议**：
推荐方案：在 DWD-3 销售明细表中冗余 `shelf_date` 字段，作为"退化维度"（Degenerate Dimension）保留，便于 DWS 层直接计算。

```sql
-- DWD-3 表结构增加 shelf_date 字段（退化维度）
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_all_d (
    `record_id`           VARCHAR(64)     COMMENT "飞书记录唯一ID(主键,溯源用)",
    `sales_date`          DATE            COMMENT "销售日期(主键,分区键)",
    `channel_code`        VARCHAR(50)    COMMENT "渠道编码(主键,英文标准名)",
    `id`                  BIGINT          COMMENT "自增ID(溯源用)",
    `brand`               VARCHAR(20)     COMMENT "品牌:361/韦德",
    `sku`                 VARCHAR(64)     COMMENT "SKU编码",
    `style_no`            VARCHAR(64)     COMMENT "款号(361为None)",
    `size`                VARCHAR(20)     COMMENT "尺码(361为None)",
    -- 新增 shelf_date 退化维度，便于 DWS 直接计算已上架天数
    `shelf_date`          DATE            COMMENT "上架日期(退化维度,来源商品库,361取actual_shelf_date)",
    `channel_name`        VARCHAR(100)    COMMENT "渠道中文名称",
    `channel_type`        VARCHAR(30)     COMMENT "渠道类型:自营/寄售/分销/海外/平台/其他",
    `qty`                 BIGINT          COMMENT "销量(件/双,整数)",
    `amt`                 DECIMAL(18,6)   COMMENT "金额(元,保留6位小数)",
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `source_table`        VARCHAR(50)     COMMENT "数据来源表名",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间(ETL写入)",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间(ETL写入)"
) ENGINE=OLAP
PRIMARY KEY(`record_id`, `sales_date`, `channel_code`)
...

-- ETL 插入时通过 JOIN 商品库获取 shelf_date
INSERT INTO feishu_dwd.dwd_feishu_sales_all_d (
    id, sales_date, record_id, brand, sku, style_no, size, shelf_date,
    channel_code, channel_name, channel_type, qty, amt, sync_time, source_table, insert_date, update_date
)
SELECT
    s.id, s.sales_date, s.record_id, s.brand, s.sku, s.style_no, s.size,
    p.shelf_date,  -- 从商品库关联获取
    s.channel_code, s.channel_name, s.channel_type, s.qty, s.amt,
    s.sync_time, s.source_table, NOW(), NOW()
FROM tmp_sales_long s  -- 临时表存放 UNION ALL 后的长表数据
LEFT JOIN feishu_dwd.dwd_feishu_product_all_d p
  ON s.sku = p.sku AND s.brand = p.brand;
```

**优先级**：🔴 高（影响 DWS 层所有核心指标计算性能与口径一致性）

---

#### 问题 2.2【🟢 低】shelf_date 与 actual_shelf_date 的统一映射说明

**问题描述**：
- DWD-6 统一商品库已正确处理 shelf_date 统一映射：
  - 韦德：`wd.shelf_date`（DWD.md 第 1759 行）
  - 361：`actual_shelf_date AS shelf_date`（DWD.md 第 1791 行）
- 字段口径定义 3.4 节也明确该映射关系
- 该项处理正确，无需调整

**调整建议**：
无需调整，但建议在 DWD-6 表的 COMMENT 中补充说明，便于下游理解：

```sql
`shelf_date` DATE COMMENT "上架日期(统一口径:韦德取shelf_date,361取actual_shelf_date,上架当天为销售第1天)",
```

**优先级**：🟢 低（文档完善性）

---

### 审查要点 3：DWD-4 韦德商品库特有字段保留问题

#### 问题 3.1【🔴 高】统一商品库未保留 is_replenish、replenish_qty 等关键字段

**问题描述**：
- DWD-6 统一商品库（DWD.md 第 1683 行注释）明确去除以下韦德特有字段：
  - `is_replenish`（是否补货）
  - `replenish_qty`（补货量）
  - `order_qty_skc`（SKC维度订货量）
  - `inventory_skc`（SKC维度库存）
  - `sales_cycle_label`（销售周期标签）
- 字段口径定义 3.16 节明确：达成比例计算需判断"是否补货"，若 `is_replenish='是'`，分母 = 订货数量 + 补货数量
- 字段口径定义 1.4 节已新增 DWD-4 韦德商品库表，建议 DWS 层 LEFT JOIN 获取

**影响分析**：
- 当前方案要求 DWS 层每次计算达成比例都 JOIN DWD-4 表，但 DWD-4 仅含韦德数据
- 361 品牌无补货概念，分母直接取订货数量，无需 JOIN
- 这导致 DWS 层 SQL 复杂化：需先判断品牌，韦德才 JOIN DWD-4

**调整建议**：
推荐方案 A（首选）：在 DWD-6 统一商品库中保留这 5 个字段，361 品牌置 NULL/默认值。

```sql
-- DWD-6 表结构增加 5 个韦德特有字段
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_product_all_d (
    -- 1. Key 列
    `sku`                 VARCHAR(128)    COMMENT "SKU编码(主键)",
    `brand`               VARCHAR(20)     COMMENT "品牌:361/韦德(主键)",
    -- 2. 维度列（原有）
    `style_no`            VARCHAR(128)    COMMENT "款号/商品货号",
    `ip`                  VARCHAR(100)    COMMENT "IP",
    `series`              VARCHAR(100)    COMMENT "系列",
    `color_name`          VARCHAR(100)    COMMENT "配色名(韦德有,361为空)",
    `product_name`        VARCHAR(500)    COMMENT "商品名称",
    `category`            VARCHAR(100)    COMMENT "品类/商品分类",
    `size`                VARCHAR(50)     COMMENT "尺码(韦德码/361美码统一)",
    -- 3. 度量列（原有）
    `tag_price`           DECIMAL(18,6)   COMMENT "吊牌价",
    `order_qty`           BIGINT          COMMENT "订货数量(SKU维度)",
    -- 4. 时间字段（原有）
    `order_date`          DATE            COMMENT "订货日期",
    `shelf_date`          DATE            COMMENT "上架日期",
    `first_sales_date`    DATE            COMMENT "首次销售日期(韦德有,361预计算或NULL)",
    `first_order_quarter` VARCHAR(50)     COMMENT "首次订货季度",
    `year`                VARCHAR(50)     COMMENT "年份(韦德有,361为空)",
    -- 5. 库存字段（原有）
    `inventory_sku`       BIGINT          COMMENT "库存数量(SKU)(韦德有,361为空)",
    -- ============== 新增：韦德特有字段（361置NULL/默认值） ==============
    `order_qty_skc`       BIGINT          COMMENT "订货数量(SKC维度)(韦德特有,361为NULL)",
    `inventory_skc`       BIGINT          COMMENT "库存数量(SKC)(韦德特有,361为NULL)",
    `sales_cycle_label`   VARCHAR(100)    COMMENT "销售周期标签(韦德特有,361为NULL)",
    `is_replenish`        VARCHAR(50)     COMMENT "是否补货(韦德特有:是/否,361固定为'否')",
    `replenish_qty`       BIGINT          COMMENT "补货量(韦德特有,361为0)",
    -- 6. 技术字段
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间"
) ENGINE=OLAP
PRIMARY KEY(`sku`, `brand`)
...
```

```sql
-- DWD-6 韦德插入（补充 5 个字段）
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku,
    order_qty_skc, inventory_skc, sales_cycle_label, is_replenish, replenish_qty,  -- 新增
    sync_time, insert_date, update_date
)
SELECT
    wd.sku, '韦德' AS brand,
    wd.style_no, wd.ip, wd.series, wd.color_name, wd.product_name,
    wd.product_category AS category, wd.size,
    wd.tag_price, wd.order_qty_sku AS order_qty,
    wd.order_date, wd.shelf_date, wd.first_sales_date,
    wd.first_order_quarter, wd.year, wd.inventory_sku,
    -- 新增字段
    wd.order_qty_skc, wd.inventory_skc, wd.sales_cycle_label,
    COALESCE(NULLIF(wd.is_replenish, ''), '否'),
    COALESCE(wd.replenish_qty, 0),
    wd.sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_product_wd_d wd
WHERE wd.sku IS NOT NULL;

-- DWD-6 361插入（补充 5 个字段，置 NULL/默认值）
INSERT INTO feishu_dwd.dwd_feishu_product_all_d (
    sku, brand, style_no, ip, series, color_name, product_name, category, size,
    tag_price, order_qty, order_date, shelf_date, first_sales_date,
    first_order_quarter, year, inventory_sku,
    order_qty_skc, inventory_skc, sales_cycle_label, is_replenish, replenish_qty,  -- 新增
    sync_time, insert_date, update_date
)
SELECT
    p.sku, '361' AS brand,
    p.style_no, p.ip, p.series, NULL AS color_name,
    p.product_name, p.category, p.size_us AS size,
    p.tag_price, p.order_qty, p.order_date,
    p.actual_shelf_date AS shelf_date,
    COALESCE(fs.first_sales_date, CAST(NULL AS DATE)) AS first_sales_date,
    p.first_order_quarter, NULL AS year, NULL AS inventory_sku,
    -- 361 无补货概念
    CAST(NULL AS BIGINT) AS order_qty_skc,
    CAST(NULL AS BIGINT) AS inventory_skc,
    CAST(NULL AS VARCHAR) AS sales_cycle_label,
    '否' AS is_replenish,
    0 AS replenish_qty,
    p.sync_time, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_product_361_d p
LEFT JOIN (
    SELECT sku, MIN(sales_date) AS first_sales_date
    FROM feishu_dwd.dwd_feishu_sales_all_d
    WHERE brand = '361' AND qty > 0
    GROUP BY sku
) fs ON p.sku = fs.sku
WHERE p.sku IS NOT NULL;
```

方案 B（保守）：保留现有 DWD-6 结构不变，DWS 层通过 LEFT JOIN DWD-4 获取这些字段。

**推荐方案 A**，理由：
1. 减少 DWS 层 JOIN 次数，简化 SQL
2. 统一商品库作为"维度表"应尽量保留所有下游需要的属性字段
3. 361 品牌置 NULL/默认值，不影响存储成本

**优先级**：🔴 高（影响达成比例等核心指标计算）

---

#### 问题 3.2【🟡 中】sales_cycle_label 字段语义冲突

**问题描述**：
- DWD-4 韦德商品库已有 `sales_cycle_label` 字段（DWD.md 第 1310 行），但 COMMENT 为"销售周期标签"
- 字段口径定义 3.7 节也有计算字段"销售周期标签"（基于已上架天数划分：新品期/热销期/清货期/超周期）
- 两者名称相同但语义不同：
  - DWD-4 的 `sales_cycle_label`：韦德业务原始录入的标签（可能为"新品期/热销期/清货期/滞销"等业务自定义值）
  - 字段口径定义的计算字段：基于 `shelf_date` 和 `CURRENT_DATE()` 动态计算的标签

**影响分析**：
- 下游开发者可能误用 DWD-4 的静态标签，而非动态计算结果
- 韦德原始标签可能未及时更新，与动态计算结果不一致

**调整建议**：
1. DWD-4 的字段重命名为 `raw_sales_cycle_label`（业务原始录入标签）：
```sql
`raw_sales_cycle_label` VARCHAR(100) COMMENT "业务原始销售周期标签(韦德录入,可能滞后,下游应以计算字段为准)",
```

2. 若按问题 3.1 方案 A 在 DWD-6 中保留该字段，也使用 `raw_sales_cycle_label` 命名，并明确 COMMENT 警示。

3. 字段口径定义 3.7 节的销售周期标签保持为"计算字段"，DWS 层基于 `shelf_date` 动态计算。

**优先级**：🟡 中（避免字段语义混淆）

---

### 审查要点 4：表结构与字段完整性

#### 问题 4.1【🔴 高】DWD-6 统一商品库缺失 SKU 维度主键设计问题

**问题描述**：
- DWD-6 表主键为 `(sku, brand)`（DWD.md 第 1728 行），但表结构中 `style_no`、`ip`、`series`、`category`、`order_date`、`first_order_quarter` 等 COMMENT 标注为"(主键组成部分)"（第 1705-1719 行）
- 这与 PRIMARY KEY 定义不一致，COMMENT 误导

**影响分析**：
- COMMENT 错误导致开发者对主键理解混乱
- 实际主键仅 `(sku, brand)`，其他字段是普通维度列

**调整建议**：
修正 COMMENT，移除"(主键组成部分)"标注：

```sql
`style_no`            VARCHAR(128)    COMMENT "款号/商品货号",
`ip`                  VARCHAR(100)    COMMENT "IP",
`series`              VARCHAR(100)    COMMENT "系列",
`category`            VARCHAR(100)    COMMENT "品类/商品分类",
`order_date`          DATE            COMMENT "订货日期",
`first_order_quarter` VARCHAR(50)     COMMENT "首次订货季度",
```

**优先级**：🟡 中（文档准确性）

---

#### 问题 4.2【🟡 中】DWD-6 缺失 361 品牌的 color_name 字段处理

**问题描述**：
- DWD-6 表中 361 品牌 `color_name` 直接置 NULL（DWD.md 第 1784 行）
- 字段口径定义 5.1 节明确：361 品牌 SKC 近似等于 `style_no`（361 业务上款号即近似 SKC）
- 这意味着 361 品牌无法通过 `style_no + color_name` 组合推导 SKC，需特殊处理

**影响分析**：
- SKC 维度是核心分析维度（业务文档以 SKC 为主键）
- 361 品牌若无法准确推导 SKC，SKC 维度分析将退化为款号维度
- 字段口径定义 5.1 节已说明"361 业务上款号即近似 SKC"，但仍可能误导下游

**调整建议**：
1. 在 DWD-6 表 COMMENT 中明确标注 361 品牌 SKC 推导方式：

```sql
`color_name` VARCHAR(100) COMMENT "配色名(韦德有,361为NULL,361的SKC近似等于style_no)",
```

2. 建议在 DWS 层新增计算字段 `skc_code`：
```sql
-- DWS 层 SKC 推导逻辑
CASE
    WHEN brand = '韦德' THEN CONCAT(style_no, '-', color_name)
    WHEN brand = '361' THEN style_no  -- 361款号即近似SKC
    ELSE NULL
END AS skc_code
```

**优先级**：🟡 中（影响 SKC 维度分析口径）

---

#### 问题 4.3【🟢 低】DWD-2 韦德销售表 order_qty 字段语义不清

**问题描述**：
- DWD-2 `dwd_feishu_sales_wd_d` 表有 `order_qty` 字段（DWD.md 第 404 行），COMMENT 为"订货数量"
- 字段口径定义 8.2 节问题4 已确认：该字段是 SKU 维度的订货量
- 但 DWD-4 韦德商品库表有 `order_qty_sku` 和 `order_qty_skc` 两个字段（DWD.md 第 1295-1296 行）
- DWD-2 的 `order_qty` 来源不明（是 `order_qty_sku` 还是 `order_qty_skc`？）

**影响分析**：
- 字段口径定义 3.15 节明确 DWD-6 的 `order_qty` 统一为 SKU 维度
- 但 DWD-2 销售明细表中的 `order_qty` 来源未明确说明
- 可能导致下游误用

**调整建议**：
1. 在 DWD-2 表 COMMENT 中明确字段来源：
```sql
`order_qty` BIGINT COMMENT "订货数量(SKU维度,来源wd_sales_06分表,其他分表可能为NULL)",
```

2. 若 DWD-2 的 `order_qty` 实际来自 `订货数量` 字段（DWD.md 第 513 行 ETL），需确认与 DWD-4 的 `order_qty_sku` 是否一致。

**优先级**：🟢 低（字段语义澄清）

---

### 审查要点 5：ETL 逻辑与数据质量

#### 问题 5.1【🔴 高】DWD-3 长表 ETL 中 WHERE 条件过滤导致数据丢失

**问题描述**：
- DWD-3 长表 ETL（DWD.md 第 1096、1103、1110、1117 行等）使用如下过滤：
```sql
WHERE qty_361sport <> 0 OR amt_361sport <> 0
```
- 这会过滤掉销量和金额都为 0 的记录
- 但业务上"某天某渠道无销售"是有效信息，应保留为 0 销量记录

**影响分析**：
- 业务文档（最终效果页）显示：实际销售工作表有大量"空"或"0"值记录
- 若 DWD-3 过滤掉 0 销量记录，下游计算"昨日实际销售"时，无销售的 SKU 会被遗漏
- 字段口径定义 3.17 节明确：昨日无销售记录时为 0

**调整建议**：
方案 A（推荐）：保留 0 销量记录，仅过滤 NULL 或异常值：

```sql
-- DWD-3 361品牌渠道1：361sport
SELECT id, sales_date, record_id, brand, sku, 'None', 'None', CAST(NULL AS DATE),
       '361sport', '361sport', '自营',
       COALESCE(qty_361sport, 0), COALESCE(amt_361sport, 0),
       sync_time, source_table, NOW(), NOW()
FROM feishu_dwd.dwd_feishu_sales_361_d
WHERE qty_361sport IS NOT NULL OR amt_361sport IS NOT NULL
-- 改为：保留 0 值记录，仅过滤 NULL 记录
```

方案 B（保守）：维持现状，但在文档中明确说明"DWD-3 仅包含有销售的记录，无销售的 SKU 需从商品库表 LEFT JOIN 获取"。

**推荐方案 A**，理由：
1. 符合业务报表"有 SKU 即展示，无销售显示 0"的逻辑
2. 简化 DWS 层 SQL，无需额外 LEFT JOIN 补 0

**优先级**：🔴 高（影响数据完整性）

---

#### 问题 5.2【🟡 中】DWD-2 韦德销售表 ETL 中 first_sales_date 兜底值不一致

**问题描述**：
- DWD-2 韦德销售表 ETL（DWD.md 第 502 行）：
```sql
COALESCE(DATE(首次销售日期), DATE('1970-01-01')) AS first_sales_date
```
- 韦德商品库 DWD-4 ETL（DWD.md 第 1446 行）：
```sql
COALESCE(DATE(首次销售日期), DATE('1970-01-01')) AS first_sales_date
```
- 两表都用 `1970-01-01` 兜底，但若 DWD-3 改为 NULL 兜底（见问题 1.1），会导致 DWD-2 和 DWD-3 不一致

**影响分析**：
- 同一字段在不同表中的兜底值不一致，增加下游处理复杂度
- `1970-01-01` 兜底可能被误用为有效日期参与计算

**调整建议**：
统一所有表的 `first_sales_date` 兜底策略。推荐两个方案任选其一：

方案 A（推荐）：全部统一为 NULL 兜底
```sql
-- DWD-2 韦德销售表
CAST(DATE(首次销售日期) AS DATE) AS first_sales_date  -- NULL 自动保留

-- DWD-4 韦德商品库
CAST(DATE(首次销售日期) AS DATE) AS first_sales_date
```

方案 B：全部统一为 `1970-01-01` 兜底（保持现状，但修正 DWD-3 注释不一致问题）

**优先级**：🟡 中（数据一致性）

---

#### 问题 5.3【🟡 中】DWD-2 韦德销售表 source_table 字段长度不足

**问题描述**：
- DWD-2 表 `source_table` 字段定义为 `VARCHAR(20)`（DWD.md 第 456 行）
- 但视图方案中 source_table 值为 `'wd_sales_01'` 等（11 字符），尚可
- 若未来分表数超过 99（如 `wd_sales_100`），将超过 VARCHAR(20) 长度

**影响分析**：
- 当前不影响，但未来扩展性差
- DWD-1 361 销售表的 `source_table` 也是 VARCHAR(20)，但 361 分表名格式为 `t_361sales_XX`，最长 14 字符，安全

**调整建议**：
将 `source_table` 字段长度统一调整为 VARCHAR(50)，与 DWD-3 长表保持一致：

```sql
`source_table` VARCHAR(50) COMMENT "来源分表名(数据溯源,DWD新增)",
```

**优先级**：🟢 低（未来扩展性）

---

#### 问题 5.4【🟡 中】DWD-4 韦德商品库 ETL 字段精度风险

**问题描述**：
- DWD-4 ETL（DWD.md 第 1434-1435 行）使用正则校验过滤非数字字符：
```sql
COALESCE(CASE WHEN TRIM(`订货数量(sku)`) REGEXP '^[0-9]+$' THEN CAST(TRIM(`订货数量(sku)`) AS BIGINT) ELSE 0 END, 0) AS order_qty_sku
```
- 但 `订货数量(sku)` 可能含小数（如 "100.5"），正则 `^[0-9]+$` 会过滤掉小数，导致数据置 0

**影响分析**：
- 业务上订货数量应为整数，但飞书录入可能存在小数（如 "100.0"）
- 正则过滤会导致有效数据被误判为 0

**调整建议**：
改用 DECIMAL 中转 + ROUND 取整的方式（与 DWD-2 销售表处理一致）：

```sql
-- 修正：先转 DECIMAL，再 ROUND 转 BIGINT
COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货数量(sku)`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_qty_sku,
COALESCE(CAST(ROUND(CAST(NULLIF(TRIM(`订货数量(SKC)`), '') AS DECIMAL(18,6)), 0) AS BIGINT), 0) AS order_qty_skc,
```

对所有使用 `REGEXP '^[0-9]+$'` 的字段统一修正，包括：
- `order_qty_sku`、`order_qty_skc`
- `inventory_sku`、`inventory_skc`、`inventory_total`、`inventory_hz`、`inventory_baoshui`、`inventory_feibao`
- `official_daily_sales`、`cum_sales_excl_current_week`、`cum_sales_sku`、`cum_sales_skc`、`actual_sales_days`
- `replenish_qty`、`replenish_num`、`safety_days`

**优先级**：🟡 中（数据准确性）

---

### 审查要点 6：性能与分区策略

#### 问题 6.1【🔴 高】DWD-3 长表缺失分区配置

**问题描述**：
- DWD-3 `dwd_feishu_sales_all_d` 表（DWD.md 第 1048-1080 行）的 PROPERTIES 中**未配置动态分区**：
```sql
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true",
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1"
);
```
- 而 DWD-1、DWD-2 销售表（按 sales_date 分区）应在 PROPERTIES 中配置动态分区参数
- 文档第三章明确："按销售日期动态分区"，但实际 DDL 中 `PARTITION BY RANGE` 子句缺失，PROPERTIES 中也无 `dynamic_partition.*` 参数

**影响分析**：
- 无动态分区配置，所有历史数据堆积在单一分区，查询性能差
- 无法自动清理过期数据（如 3 年前的销售记录）
- 按日期查询无法走分区裁剪，全表扫描 450 万行

**调整建议**：
DWD-3 表增加分区配置：

```sql
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_all_d (
    ...
) ENGINE=OLAP
PRIMARY KEY(`record_id`, `sales_date`, `channel_code`)
COMMENT "DWD层-统一销售日明细表(长表,361+韦德,渠道转行,日刷新)"
PARTITION BY RANGE(`sales_date`) ()  -- 新增分区子句
DISTRIBUTED BY HASH(`record_id`) BUCKETS 32  -- 长表数据量大,建议32桶
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true",
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1",
    -- 新增动态分区配置
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "32",
    "dynamic_partition.history_partition_num" = "365"
);
```

同样需要为 DWD-1、DWD-2 销售表补充分区配置。

**优先级**：🔴 高（影响查询性能与数据生命周期管理）

---

#### 问题 6.2【🟡 中】DWD-3 长表分桶数偏少

**问题描述**：
- DWD-3 表分桶数为 16（DWD.md 第 1073 行 `DISTRIBUTED BY HASH(\`record_id\`)`，未指定 BUCKETS）
- 实际未指定 BUCKETS 数，使用默认值（通常 10）
- 长表预估 450 万行，单分区数据量约 1.2 万行/天

**影响分析**：
- 分桶数过少，并行度不足，查询性能差
- 根据规范：单分区数据量 100万~1000万，建议 BUCKETS 16~32

**调整建议**：
明确指定 BUCKETS 32：

```sql
DISTRIBUTED BY HASH(`record_id`) BUCKETS 32
```

或考虑按 `sku` 分桶（高频过滤字段），便于按 SKU 聚合：

```sql
DISTRIBUTED BY HASH(`sku`) BUCKETS 32
```

**优先级**：🟡 中（查询性能）

---

#### 问题 6.3【🟢 低】缺少布隆过滤索引配置

**问题描述**：
- 所有 DWD 表均未配置 `bloom_filter_columns`，无法加速 `=` 和 `IN` 查询
- 销售明细表的高频查询场景：按 `sku`、`brand`、`channel_code` 过滤

**影响分析**：
- 按 SKU 点查时无法利用布隆过滤索引，扫描效率低
- 商品库表按品牌过滤时同样无法加速

**调整建议**：
为高频过滤字段添加布隆过滤索引：

```sql
-- DWD-3 销售明细表
PROPERTIES (
    ...
    "bloom_filter_columns" = "sku,brand,channel_code"
);

-- DWD-6 统一商品库表
PROPERTIES (
    ...
    "bloom_filter_columns" = "sku,brand,style_no"
);

-- DWD-7 品牌方库存表
PROPERTIES (
    ...
    "bloom_filter_columns" = "sku,style_no"
);
```

**优先级**：🟢 低（性能优化）

---

### 审查要点 7：361品牌数据缺失问题

#### 问题 7.1【🔴 高】361 品牌 inventory_sku 缺失，影响在仓库存指标

**问题描述**：
- DWD-6 统一商品库中 361 品牌的 `inventory_sku` 直接置 NULL（DWD.md 第 1795 行）
- 字段口径定义 3.8 节明确：在仓库存 = `dwd_feishu_product_all_d.inventory_sku`，空值兜底为 0
- 字段口径定义 8.1 节确认：361 的 `inventory_sku` 为 NULL，需从其他来源补充或确认是否使用品牌方库存表
- 但 DWD-7 品牌方库存表仅含韦德数据（来源 `wd_pinpaikucun`），361 无对应数据

**影响分析**：
- 361 品牌的"在仓库存"、"可售周期(天)"指标无法计算
- 业务报表会显示空白，业务方无法看到 361 库存情况
- 字段口径定义 5.7 节 SKC 维度在仓库存同样受影响

**调整建议**：
方案 A（短期）：361 品牌 `inventory_sku` 兜底为 0，并在 COMMENT 中明确标注：

```sql
-- DWD-6 361品牌插入
COALESCE(NULL, 0) AS inventory_sku,  -- 361无SKU维度库存,暂兜底为0
```

并在 DWD-6 表 COMMENT 中补充：
```sql
`inventory_sku` BIGINT COMMENT "库存数量(SKU)(韦德有,361暂为0,待确认数据源)",
```

方案 B（长期）：与业务方确认 361 品牌是否有库存数据源（如 361 ERP 系统、WMS 系统），新增 ODS 采集任务。

**优先级**：🔴 高（影响 361 品牌库存指标完整性，需业务确认）

---

#### 问题 7.2【🟡 中】361 品牌可提库存缺失

**问题描述**：
- 字段口径定义 3.9 节明确：可提库存 = `dwd_feishu_inventory_wdpinpai_d.inventory_qty`
- 但 DWD-7 品牌方库存表仅含韦德数据（来源 `wd_pinpaikucun`）
- 字段口径定义 3.9 节明确：361 品牌无品牌方库存数据，该字段为 0

**影响分析**：
- 361 品牌的"可提库存"指标为 0，无法反映实际可提货情况
- 业务报表 361 品牌该列空白

**调整建议**：
与问题 7.1 同步处理：
1. 短期：DWS 层 361 品牌可提库存兜底为 0，COMMENT 标注
2. 长期：与业务方确认 361 品牌库存数据源

**优先级**：🟡 中（影响 361 品牌库存指标）

---

#### 问题 7.3【🟢 低】361 品牌的 SKC 推导方式建议沉淀到 DWD 层

**问题描述**：
- 字段口径定义 5.1 节明确：361 品牌 SKC 近似等于 `style_no`
- 但 DWD-6 统一商品库未提供 `skc_code` 计算字段
- 每个 DWS 任务都需重复实现 SKC 推导逻辑

**影响分析**：
- DWS 层 SQL 重复代码多
- 不同任务可能实现不一致

**调整建议**：
建议在 DWD-6 表新增 `skc_code` 计算字段（物化到表中）：

```sql
-- DWD-6 新增 skc_code 字段
`skc_code` VARCHAR(256) COMMENT "SKC编码(韦德=style_no+color_name,361=style_no)",

-- ETL 插入时计算
-- 韦德
CONCAT(wd.style_no, '-', wd.color_name) AS skc_code,
-- 361
p.style_no AS skc_code,
```

**优先级**：🟢 低（减少 DWS 层重复代码，非阻塞）

---

## 三、优先级排序汇总

### 3.1 高优先级问题（必须修复）

| 问题编号 | 问题简述 | 影响范围 |
|----------|----------|----------|
| 1.2 | 361 品牌 first_sales_date 未预计算 | 361 品牌业务参考字段缺失 |
| 2.1 | DWD-3 销售明细表缺失 shelf_date 字段 | DWS 层核心指标计算性能 |
| 3.1 | 统一商品库未保留 is_replenish 等字段 | 达成比例计算 |
| 4.1 | DWD-6 COMMENT 主键标注错误 | 文档准确性 |
| 5.1 | DWD-3 长表 WHERE 过滤导致 0 销量数据丢失 | 数据完整性 |
| 6.1 | DWD-3 长表缺失分区配置 | 查询性能、数据生命周期 |
| 7.1 | 361 品牌 inventory_sku 缺失 | 361 库存指标 |

### 3.2 中优先级问题（建议修复）

| 问题编号 | 问题简述 | 影响范围 |
|----------|----------|----------|
| 1.1 | DWD-3 first_sales_date 兜底值不一致 | 数据语义清晰度 |
| 1.3 | DWD-3 first_sales_date 字段冗余 | 数据规范化 |
| 3.2 | sales_cycle_label 字段语义冲突 | 字段语义混淆 |
| 4.2 | 361 品牌 color_name 缺失，SKC 推导需特殊处理 | SKC 维度分析 |
| 5.2 | DWD-2 first_sales_date 兜底值不一致 | 数据一致性 |
| 5.4 | DWD-4 ETL 正则过滤小数导致数据丢失 | 数据准确性 |
| 6.2 | DWD-3 分桶数偏少 | 查询性能 |
| 7.2 | 361 品牌可提库存缺失 | 361 库存指标 |

### 3.3 低优先级问题（可选优化）

| 问题编号 | 问题简述 | 影响范围 |
|----------|----------|----------|
| 2.2 | shelf_date COMMENT 补充说明 | 文档完善性 |
| 4.3 | DWD-2 order_qty 字段语义不清 | 字段语义澄清 |
| 5.3 | source_table 字段长度不足 | 未来扩展性 |
| 6.3 | 缺少布隆过滤索引配置 | 性能优化 |
| 7.3 | 361 品牌 SKC 推导建议沉淀到 DWD 层 | 减少 DWS 重复代码 |

---

## 四、总结与建议实施顺序

### 4.1 实施阶段划分

#### 阶段一：阻塞性修复（1~2 天）

优先解决影响核心指标计算和数据完整性的高优先级问题：

1. **问题 6.1**：为 DWD-1、DWD-2、DWD-3 销售表补充动态分区配置
2. **问题 5.1**：修正 DWD-3 长表 WHERE 过滤，保留 0 销量记录
3. **问题 2.1**：DWD-3 表新增 shelf_date 退化维度字段
4. **问题 3.1**：DWD-6 表新增 is_replenish、replenish_qty 等 5 个韦德特有字段
5. **问题 1.2**：DWD-6 361 品牌 first_sales_date 预计算（LEFT JOIN 销售明细表）

#### 阶段二：数据质量修复（2~3 天）

解决数据一致性和准确性问题：

1. **问题 1.1**：统一 DWD-3 first_sales_date 兜底策略（推荐改为 NULL）
2. **问题 5.2**：统一 DWD-2 first_sales_date 兜底策略
3. **问题 5.4**：修正 DWD-4 ETL 正则过滤小数问题
4. **问题 4.1**：修正 DWD-6 COMMENT 主键标注错误
5. **问题 7.1**：361 品牌 inventory_sku 兜底为 0，COMMENT 标注待确认

#### 阶段三：字段语义优化（1~2 天）

解决字段语义混淆和文档完善：

1. **问题 3.2**：DWD-4 sales_cycle_label 重命名为 raw_sales_cycle_label
2. **问题 4.2**：DWD-6 color_name COMMENT 补充 361 SKC 推导说明
3. **问题 4.3**：DWD-2 order_qty COMMENT 明确字段来源

#### 阶段四：性能优化（可选，1 天）

1. **问题 6.2**：DWD-3 分桶数调整为 32
2. **问题 6.3**：为高频过滤字段添加布隆过滤索引
3. **问题 5.3**：source_table 字段长度调整为 VARCHAR(50)
4. **问题 1.3**：评估是否删除 DWD-3 冗余的 first_sales_date 字段
5. **问题 7.3**：DWD-6 新增 skc_code 计算字段

### 4.2 待业务确认事项

以下问题需与业务方确认后才能最终定方案：

| 问题编号 | 待确认事项 |
|----------|------------|
| 7.1 | 361 品牌是否有 SKU 维度库存数据源？（ERP/WMS 系统） |
| 7.2 | 361 品牌是否有品牌方库存数据？是否需要新增 ODS 采集？ |
| 1.3 | 是否接受 DWD-3 删除 first_sales_date 字段，下游 JOIN 获取？ |
| 2.1 | 是否接受 DWD-3 新增 shelf_date 退化维度字段？ |

### 4.3 验证方法

实施完成后，需执行以下验证：

```sql
-- 验证1：DWD-3 分区配置
SHOW PARTITIONS FROM feishu_dwd.dwd_feishu_sales_all_d;

-- 验证2：DWD-3 shelf_date 字段非空率
SELECT
    brand,
    COUNT(*) AS total_cnt,
    SUM(CASE WHEN shelf_date IS NULL THEN 1 ELSE 0 END) AS null_cnt,
    ROUND(SUM(CASE WHEN shelf_date IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS null_pct
FROM feishu_dwd.dwd_feishu_sales_all_d
GROUP BY brand;

-- 验证3：DWD-6 is_replenish 字段值分布
SELECT brand, is_replenish, COUNT(*) 
FROM feishu_dwd.dwd_feishu_product_all_d 
GROUP BY brand, is_replenish;

-- 验证4：361品牌 first_sales_date 预计算覆盖率
SELECT
    COUNT(*) AS total_361_sku,
    SUM(CASE WHEN first_sales_date IS NOT NULL THEN 1 ELSE 0 END) AS has_first_sales,
    ROUND(SUM(CASE WHEN first_sales_date IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS coverage_pct
FROM feishu_dwd.dwd_feishu_product_all_d
WHERE brand = '361';

-- 验证5：DWD-3 0销量记录保留情况
SELECT
    brand,
    SUM(CASE WHEN qty = 0 THEN 1 ELSE 0 END) AS zero_qty_cnt,
    COUNT(*) AS total_cnt
FROM feishu_dwd.dwd_feishu_sales_all_d
GROUP BY brand;
```

---

## 五、附录：完整 DWD-6 优化后表结构参考

```sql
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_product_all_d;
CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_product_all_d (
    -- 1. Key 列（PRIMARY KEY 模型，SKU+brand 为业务主键）
    `sku`                 VARCHAR(128)    COMMENT "SKU编码(主键)",
    `brand`               VARCHAR(20)     COMMENT "品牌:361/韦德(主键)",
    -- 2. 维度列
    `style_no`            VARCHAR(128)    COMMENT "款号/商品货号",
    `ip`                  VARCHAR(100)    COMMENT "IP",
    `series`              VARCHAR(100)    COMMENT "系列",
    `color_name`          VARCHAR(100)    COMMENT "配色名(韦德有,361为NULL,361的SKC近似等于style_no)",
    `product_name`        VARCHAR(500)    COMMENT "商品名称",
    `category`            VARCHAR(100)    COMMENT "品类/商品分类",
    `size`                VARCHAR(50)     COMMENT "尺码(韦德码/361美码统一)",
    `skc_code`            VARCHAR(256)    COMMENT "SKC编码(韦德=style_no+color_name,361=style_no,下游SKC维度分析主键)",
    -- 3. 度量列：价格与订货
    `tag_price`           DECIMAL(18,6)   COMMENT "吊牌价(金额保留6位小数)",
    `order_qty`           BIGINT          COMMENT "订货数量(SKU维度,整数)",
    -- 4. 维度列：时间信息（统一口径）
    `order_date`          DATE            COMMENT "订货日期",
    `shelf_date`          DATE            COMMENT "上架日期(统一口径:韦德取shelf_date,361取actual_shelf_date,上架当天为销售第1天)",
    `first_sales_date`    DATE            COMMENT "首次销售日期(韦德直接取值,361从销售明细表MIN(sales_date)预计算,仅作参考字段)",
    `first_order_quarter` VARCHAR(50)     COMMENT "首次订货季度",
    `year`                VARCHAR(50)     COMMENT "年份(韦德有,361为空)",
    -- 5. 度量列：库存信息
    `inventory_sku`       BIGINT          COMMENT "库存数量(SKU)(韦德有,361暂为0,待确认数据源)",
    -- 6. 韦德特有字段（361置NULL/默认值）
    `order_qty_skc`       BIGINT          COMMENT "订货数量(SKC维度)(韦德特有,361为NULL)",
    `inventory_skc`       BIGINT          COMMENT "库存数量(SKC)(韦德特有,361为NULL)",
    `raw_sales_cycle_label` VARCHAR(100)  COMMENT "业务原始销售周期标签(韦德录入,可能滞后,下游应以计算字段为准,361为NULL)",
    `is_replenish`        VARCHAR(50)     COMMENT "是否补货(韦德特有:是/否,361固定为'否',用于达成比例分母调整)",
    `replenish_qty`       BIGINT          COMMENT "补货量(韦德特有,用于达成比例分母调整,361为0)",
    -- 7. 技术字段
    `sync_time`           DATETIME        COMMENT "ODS同步时间",
    `insert_date`         DATETIME        COMMENT "DWD记录插入时间(ETL写入,增量更新用)",
    `update_date`         DATETIME        COMMENT "DWD记录更新时间(ETL写入,增量更新用)"
) ENGINE=OLAP
PRIMARY KEY(`sku`, `brand`)
COMMENT "DWD层-统一商品库表(361+韦德,SKU+品牌粒度,核心字段统一+韦德特有字段保留,日刷新)"
DISTRIBUTED BY HASH(`sku`) BUCKETS 16
PROPERTIES (
    "compression" = "LZ4",
    "enable_persistent_index" = "true",
    "fast_schema_evolution" = "true",
    "replicated_storage" = "true",
    "replication_num" = "1",
    "bloom_filter_columns" = "sku,brand,style_no"
);
```

---

> 本优化建议基于 2026-07-05 字段口径定义和业务文档审查生成。实施前请与业务方确认待确认事项（4.2 节），实施后请按验证方法（4.3 节）核验数据质量。
