# 基于DWD层韦德四个渠道的字段口径定义

> 编写日期：2026-07-03
> 最近修订：2026-07-09
> 适用范围：只考虑韦德品牌的四个渠道：channel_code IN ('wd', 'japan', 'spanish', 'germany')
> 维度划分：SKU维度（style_no+size）与 SKC维度（style_no、款号/商品货号字段）
> 数据基座：DWD层四张核心表：feishu_dwd.dwd_feishu_sales_all_d、feishu_dwd.dwd_feishu_product_all_d、feishu_dwd.dwd_feishu_inventory_wdpinpai_d、feishu_dwd.dwd_feishu_brand_order_arrival_d
> 目的：明确每个业务字段的取值来源、计算逻辑、边界条件,为后续DWS/ADS层设计提供口径依据
> **全局范围**：韦德品牌的四个渠道：channel_code IN ('wd', 'japan', 'spanish', 'germany')
> **全局规则**：上架日期当天为销售第一天。
> **表使用规则**：必须加上前缀`feishu_dwd.`，如`feishu_dwd.dwd_feishu_sales_all_d`，前缀分别对应数仓分层的名称：`feishu_dwd.`、`feishu_dws.`、`feishu_ads.`。
> **SKU和SKC维度**：SKU和SKC逻辑一模一样，就单纯维度不一样，需要聚合到SKC维度。其中SKC的上架时间即为该SKC下所有SKU的最早上架时间，其余逻辑类似。
> **必须遵守的准则**：开发过程中必须以此口径定义为准，不能根据业务场景灵活变通。不懂就问，不懂就问，不懂就问，最终输出的是DWS层的完整解决方案、ADS完整解决方案、QUICKBI展示方案。

---

## 【说明汇总】

> 本次依据 `新品-热销-清货期销售分析-最终效果页.md`（Excel原文件业务口径）及 `DWD.md`（DWD层实际表结构）对本口径定义进行优化,主要变更如下：

---

## 一、DWD层核心表结构概览

> 以下为口径定义涉及的DWD表及其关键字段,便于后续引用时快速定位。

### 1.1 统一销售日明细表 `feishu_dwd.dwd_feishu_sales_all_d`

| 字段                 | 类型          | 说明                                          |
| -------------------- | ------------- | --------------------------------------------- |
| `record_id`        | VARCHAR(64)   | 飞书记录唯一ID（主键）                        |
| `sales_date`       | DATE          | 销售日期（分区键）                            |
| `channel_code`     | VARCHAR(50)   | 渠道编码（主键）,如'wd','japan','361sport'等 |
| `brand`            | VARCHAR(20)   | 品牌：361/韦德                                |
| `sku`              | VARCHAR(64)   | SKU编码                                       |
| `style_no`         | VARCHAR(64)   | 款号（361为None）                             |
| `size`             | VARCHAR(20)   | 尺码（361为None）                             |
| `first_sales_date` | DATE          | 首次销售日期（361为1970-01-01）               |
| `channel_name`     | VARCHAR(100)  | 渠道中文名称                                  |
| `channel_type`     | VARCHAR(30)   | 渠道类型：自营/寄售/分销/海外/平台/其他       |
| `qty`              | BIGINT        | 销量（件/双）                                 |
| `amt`              | DECIMAL(18,6) | 金额（元）                                    |

> 粒度：品牌 + SKU + 销售日期 + 渠道（每条记录=一个渠道的一笔销售）
> 361渠道4个：361sport / china_company / 361_sample / staff_hk
> 韦德渠道18个：wd / wd_sample / dewu / dewu_consign / 95fen / guangdong / quanyong / yingkedi / offline / japan / spanish / weihong / 95fen_shop / pdd / ebay / entertainment / germany / b2b

### 1.2 统一商品库表 `feishu_dwd.dwd_feishu_product_all_d`

| 字段                    | 类型          | 说明                               |
| ----------------------- | ------------- | ---------------------------------- |
| `sku`                 | VARCHAR(128)  | SKU编码（主键）                    |
| `brand`               | VARCHAR(20)   | 品牌：361/韦德（主键）             |
| `style_no`            | VARCHAR(128)  | 款号/商品货号                      |
| `ip`                  | VARCHAR(100)  | IP                                 |
| `series`              | VARCHAR(100)  | 系列                               |
| `color_name`          | VARCHAR(100)  | 配色名（韦德有,361为空）          |
| `product_name`        | VARCHAR(500)  | 商品名称                           |
| `category`            | VARCHAR(100)  | 品类/商品分类                      |
| `size`                | VARCHAR(50)   | 尺码                               |
| `tag_price`           | DECIMAL(18,6) | 吊牌价                             |
| `order_qty`           | BIGINT        | 订货数量（SKU维度）                |
| `order_date`          | DATE          | 订货日期                           |
| `shelf_date`          | DATE          | 上架日期（统一口径：韦德取shelf_date,361取actual_shelf_date） |
| `first_sales_date`    | DATE          | 首次销售日期（韦德有,361预计算：从销售明细表取最早有销量的日期,空值为null）  |
| `first_order_quarter` | VARCHAR(50)   | 首次订货季度                       |
| `year`                | VARCHAR(50)   | 年份（韦德有,361为空）            |
| `inventory_sku`       | BIGINT        | 库存数量SKU维度（韦德有,361为空,空值为null） |
| `order_qty_skc`       | BIGINT        | 订货数量SKC维度（韦德有,361为空,空值为null） |
| `inventory_skc`       | BIGINT        | 库存数量SKC维度（韦德有,361为空,空值为null） |
| `sales_cycle_label`   | VARCHAR(100)  | 销售周期标签（韦德有,361为空,空值为null）   |
| `is_replenish`        | VARCHAR(50)   | 是否补货（韦德特有:是/否,361固定为'否'） |
| `replenish_qty`       | BIGINT        | 补货量（韦德特有,361为0）                |

> 粒度：SKU + 品牌

### 1.3 品牌方库存清洗表 `feishu_dwd.dwd_feishu_inventory_wdpinpai_d`

| 字段                | 类型          | 说明                         |
| ------------------- | ------------- | ---------------------------- |
| `id`              | BIGINT        | 自增主键（主键）             |
| `inventory_date`  | DATE          | 品牌方库存更新日期（分区键） |
| `sku`             | VARCHAR(128)  | SKU编码                      |
| `style_no`        | VARCHAR(128)  | 款号                         |
| `ip`              | VARCHAR(100)  | IP                           |
| `series`          | VARCHAR(50)   | 系列                         |
| `color_name`      | VARCHAR(100)  | 配色名                       |
| `category`        | VARCHAR(100)  | 商品类别                     |
| `size`            | VARCHAR(50)   | 尺码                         |
| `inventory_qty`   | BIGINT        | 库存数量（品牌方可提库存）   |
| `price_with_tax`  | DECIMAL(18,6) | 含税单价                     |
| `tag_price`       | DECIMAL(18,6) | 吊牌价                       |
| `order_qty`       | BIGINT        | 订货数量                     |
| `picked_qty`      | BIGINT        | 已提数量                     |
| `unpicked_qty`    | BIGINT        | 未提数量                     |
| `pickup_flag`     | VARCHAR(50)   | 提货标识                     |
| `min_granularity` | VARCHAR(100)  | 最小颗粒度                   |

> 粒度：SKU + 库存更新日期
> 注意：该表仅包含韦德品牌数据（来源wd_pinpaikucun）,361品牌无品牌方库存数据

### 1.4 品牌订货到货情况清洗表 `feishu_dwd.dwd_feishu_brand_order_arrival_d`

| 字段                    | 类型          | 说明                                      |
| ----------------------- | ------------- | ----------------------------------------- |
| `style_no_size`       | VARCHAR(255)  | 款号与尺码拼接（主键,形如:ABAV015-7-11.5）|
| `sku`                 | VARCHAR(128)  | 商品SKU（按主键聚合取MAX值）              |
| `style_no`            | VARCHAR(255)  | 款号                                      |
| `size_code`           | VARCHAR(50)   | 尺码                                      |
| `ip`                  | VARCHAR(100)  | IP                                        |
| `series`              | VARCHAR(100)  | 系列                                      |
| `color_name`          | VARCHAR(255)  | 配色名                                    |
| `product_name`        | VARCHAR(500)  | 品名                                      |
| `category`            | VARCHAR(100)  | 商品分类                                  |
| `pickup_status`       | VARCHAR(50)   | 提货状态                                  |
| `est_arrival_month`   | VARCHAR(50)   | 预计到货年月（取最早到货时间对应记录）    |
| `order_qty`           | BIGINT        | 订货数量（叠加）                          |
| `picked_qty`          | BIGINT        | 已提货数量（叠加）                        |
| `unpicked_qty`        | BIGINT        | 未提货数量（叠加）                        |
| `brand_stock_qty`     | BIGINT        | 品牌库存数量（叠加）                      |
| `unpicked_avail_qty`  | BIGINT        | 未提可提数量（叠加）                      |
| `unpicked_unavail_qty`| BIGINT        | 未提不可提数量（叠加）                    |
| `cumulative_order_qty`| BIGINT        | 累计订货（叠加）                          |
| `est_arrival_date`    | DATE          | 预计到货时间（取最早的,空值默认NULL）    |
| `30_est_arrival_date` | DATE          | 预计到货时间+30天                         |
| `sync_time`           | DATETIME      | ODS同步时间（取最新时间）                |
| `insert_date`         | DATETIME      | DWD记录插入时间（ETL写入,增量更新用）   |
| `update_date`         | DATETIME      | DWD记录更新时间（ETL写入,增量更新用）   |

> 粒度：款号+尺码（style_no_size）
> 注意：该表以 `style_no_size` 为主键,源数据需按此主键聚合后写入；预计到货时间取最早值,ODS同步时间取最新值


---

## 二、SKC与SKU的维度说明(遵守全局范围韦德四个渠道)

| 维度          | 定义         | 构成               | 示例           |
| ------------- | ------------ | ------------------ | -------------- |
| **SKU** | 最小可售单元,表中为`dwd_feishu_product_all_d.style_no-dwd_feishu_product_all_d.size` | CONCAT_WS ('-',style_no,size) | ABAS083-11-12.5 |
| **SKC** | 款号+颜色级,表中为`dwd_feishu_product_all_d.style_no` | style_no        | ABAS083-11    |

> 在DWD层中,SKU由 style_no,size 拼接而成为新的字段style_no_size,所有业务都用这个字段来表示SKU；SKC即 `style_no` 字段值。
> **注意**：style_no_size就是我们之后DWS/ADS/QUICKBI中展示的维度展示字段,等于SKU维度,后续所有业务都用style_no_size来表示SKU。

---

## 三、SKU维度字段口径定义

### 3.1 SKU编码

| 项       | 说明                                       |
| -------- | ------------------------------------------ |
| 数据来源 | `dwd_feishu_product_all_d.style_no` + `dwd_feishu_product_all_d.size` |
| 口径     | 直接取值                                   |
| 粒度     | 一条SKU一条记录                            |
| 边界     | 过滤 `style_no_size IS NOT NULL AND style_no_size <> 'None'` |

---

### 3.2 品牌

| 项       | 说明                               |
| -------- | ---------------------------------- |
| 数据来源 | `dwd_feishu_product_all_d.brand` |
| 口径     | 直接取值,值为'361'或'韦德'        |
| 边界     | 无空值                             |

---

### 3.3 系列

| 项       | 说明                                        |
| -------- | ------------------------------------------- |
| 数据来源 | `dwd_feishu_product_all_d.series`         |
| 口径     | 直接取值。SKU所属系列名称（如"7代"、"8代"） |
| 边界     | 空值兜底为'None'                            |

---

### 3.4 IP

| 项       | 说明                                        |
| -------- | ------------------------------------------- |
| 数据来源 | `dwd_feishu_product_all_d.ip`         |
| 口径     | 直接取值。SKU所属ip名称（如"幻影"、"文化鞋"） |
| 边界     | 空值兜底为'None'  |

---

### 3.5 上架时间（shelf_date）

| 项       | 说明                                                                                          |
| -------- | --------------------------------------------------------------------------------------------- |
| 数据来源 | `dwd_feishu_product_all_d.shelf_date`                                                       |
| 口径     | 直接取值。该SKU的实际上架日期（DATE类型）                                                     |
| 说明     | 韦德取 `shelf_date`,361取 `actual_shelf_date`（已在DWD层ETL中统一映射为 `shelf_date`）,空值兜底为NULL |
| 边界     | 空值兜底为NULL,使用 NULLIF 将默认的 '1970-01-01' 转为 NULL,避免影响上架天数计算,韦德直接取上架日期|

> **字段语义明确**：`shelf_date`（上架日期）**以上架时间作为销售第一天**,参与已上架天数计算,公式：today（）-上架日期+1,以上架日期当天为销售第一天。
> 销售相关指标（累计销量、1~180天逐日分析、销售周期标签等）的计算基准字段为 `shelf_date`（上架日期）。
> **shelf_date为空的情况**：通过`style_no`+`size`关联feishu_dwd.dwd_feishu_brand_order_arrival_d表的`style_no_size`,取 `30_est_arrival_date`（预计到货时间）作为 `shelf_date`。
---

### 3.6 首次销售日期（first_sales_date）

| 项                 | 说明                                                                        |
| ------------------ | --------------------------------------------------------------------------- |
| **业务定义** | **第一次产生销量的日期**仅作展示 |
| **韦德品牌** | `dwd_feishu_product_all_d.first_sales_date`,直接取值                     |
| **361品牌**  | DWD层商品库中 `first_sales_date` 为NULL,**已经预计算：从销售明细表取最早有销量的日期,空值为null**        |
| 361计算逻辑  | 对每个SKU,取 `dwd_feishu_sales_all_d` 中该SKU最早有销量的 `sales_date` |
| 边界 		  | 空值兜底为NULL |


---

### 3.7 已上架天数

| 项       | 说明                                                            |
| -------- | --------------------------------------------------------------- |
| 数据来源 | 计算字段                                                        |
| 口径     | `DATEDIFF(CURRENT_DATE(), shelf_date) + 1`              |
| 说明     | **上架日期当天为销售第一天**（即上架时间,上架时间dwd_feishu_product_all_d.shelf_date,如果上架时间没填则该字段为空）。`CURRENT_DATE()` 为当前日期 |
| 示例     | shelf_date='2026-06-01',今天='2026-06-30',已上架天数=29+1=30 |
| 边界     | 若 `shelf_date` 为NULL,该字段为空,（即上架时间,插入dwd_feishu_product_all_d表时,已实现使用 NULLIF 将默认的 '1970-01-01' 转为 NULL,避免影响上架天数计算|

> **口径明确**：已上架天数 = `DATEDIFF(CURRENT_DATE(), shelf_date) + 1`,以 `shelf_date`（上架日期）作为"第一天"。
> **注意**：本口径与业务文档"已上架天数 = today()-上架日期+1"的描述一致。

---

### 3.8 销售周期标签

| 项       | 说明                          |
| -------- | ----------------------------- |
| 数据来源 | 计算字段（基于已上架天数）    |
| 口径     | 将180天销售周期划分为三个阶段,以 `shelf_date`（上架日期）作为"第一天"开始 |

| 标签   | 条件                           |
| ------ | ------------------------------ |
| 新品期 | 已上架天数 BETWEEN 1 AND 30    |
| 热销期 | 已上架天数 BETWEEN 31 AND 120  |
| 清货期 | 已上架天数 BETWEEN 121 AND 180 |

| 边界 | 已上架天数 > 180 时,标记为"超周期"；已上架天数为空时,标签为空 |

> **"超周期"说明**：已上架天数 > 180 时,标记为"超周期"。超过180天之后的每一天，只关注每天的日销量、日金额、累计销量、累计金额、在仓库存、可提库存、可售周期。

---

### 3.9 在仓库存

| 项       | 说明                                       |
| -------- | ------------------------------------------ |
| 数据来源 | `dwd_feishu_product_all_d.inventory_sku` |
| 口径     | 直接取值。该SKU当前的在仓库存数量（件/双） |
| 说明     | 来自商品库的实时快照,日刷新               |
| 边界     | 空值兜底为0                                |

> **361品牌缺失说明**：`dwd_feishu_product_all_d` 中361品牌的 `inventory_sku` 为NULL（361商品库无SKU维度库存字段）。若361需要SKU维度在仓库存,需从其他来源补充或确认361是否使用品牌方库存表。
> **DWD层361品牌库存逻辑待补充**：等待补充,暂时不参与在仓库存计算，并且我们现在场景仅考虑韦德的四个渠道，不考虑361品牌。
---

### 3.10 可提库存

| 项       | 说明                                                                                  |
| -------- | ------------------------------------------------------------------------------------- |
| 数据来源 | `dwd_feishu_inventory_wdpinpai_d.inventory_qty`                                     |
| 口径     | 直接取值。该SKU对应的品牌方可提货库存数量                                             |
| 说明     | 来自品牌方库存表的当日快照,取最新 `inventory_date` 对应的记录                      |
| 取值逻辑 | 对同一SKU,取 `inventory_date = MAX(inventory_date)` 的那条记录的 `inventory_qty` |
| 边界     | 空值兜底为0；361品牌无品牌方库存数据,该字段为0                                       |

```sql
-- 取最新日期的品牌方库存,对同一sku的MAX(inventory_date)存在多条记录,需要聚合，参考以下SQL：
SELECT
    inv.sku,
    SUM(inv.inventory_qty) AS available_inventory
FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d inv
INNER JOIN (
    SELECT sku, MAX(inventory_date) AS max_date
    FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d
    WHERE 1=1
	-- AND sku = 'BYSku1000000614300829'
    GROUP BY sku
) latest ON inv.sku = latest.sku AND inv.inventory_date = latest.max_date 
-- AND inv.sku = 'BYSku1000000614300829'
GROUP BY inv.sku
```

---

### 3.11 可售周期(天)

| 项       | 说明                                       |
| -------- | ------------------------------------------ |
| 数据来源 | 计算字段                                   |
| 口径     | `在仓库存 / 30天平均日销`                      |
| 说明     | 当前库存在当前销售速度下可维持销售的天数   |
| 分母定义 | 见3.12节"30天平均日销"                           |
| 边界     | 日销量=0或为空时,可售周期为空（防止除零） |

---

### 3.12 30天平均日销

| 项       | 说明                                                         |
| -------- | ------------------------------------------------------------ |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.qty`                |
| 口径     | **30天平均日销**。已售天数不足30天时按实际已售天数计算 |

```
已上架天数 = N（基于 shelf_date 计算：DATEDIFF(CURRENT_DATE(), shelf_date) + 1）
已售天数 = N - 1（今日销量次日才更新,故排除今天）

如果已售天数 = 0:  日销量 = 空（无销售历史）
如果已售天数 < 30: 日销量 = 截至昨日的累计实际销量 / 已售天数
如果已售天数 >= 30: 日销量 = 最近30天的实际销量总和 / 30
```

| 项       | 说明                                                                                                                                        |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| 渠道范围 | **韦德品牌**：4个核心渠道 wd + japan + spanish + germany；**361品牌**：4个渠道 361sport + china_company + 361_sample + staff_hk |
| 数据源   | `dwd_feishu_sales_all_d`,按品牌对应渠道过滤后 SUM(qty)                                                                                   |
| 边界     | 已售天数=0时为空                                                                                                                            |

```sql
-- 参考SQL,韦德品牌：日销量计算示例（假设当前日期为CURRENT_DATE()）
	WITH sales_agg AS (
	    -- 1. 先将销售明细表按 sku+brand 聚合,避免 JOIN 时的一对多数据膨胀
	    SELECT 
	        sku,
	        brand,
	        -- 截至昨日累计销量
	        SUM(CASE WHEN sales_date < CURRENT_DATE() THEN qty ELSE 0 END) AS total_qty_to_date,
	        -- 最近30天销量 (昨日往前推30天)
	        SUM(CASE WHEN sales_date >= DATE_SUB(CURRENT_DATE(), 30) AND sales_date < CURRENT_DATE() THEN qty ELSE 0 END) AS last_30d_qty
	    FROM feishu_dwd.dwd_feishu_sales_all_d
	    WHERE brand = '韦德' 
	      -- 限定韦德品牌及4个核心渠道
	      AND channel_code IN ('wd', 'japan', 'spanish', 'germany')
	    GROUP BY 
	        sku, 
	        brand
	),
	base_data AS (
	    -- 2. 商品表 LEFT JOIN 聚合后的销售数据（此时已是1对1关系,无膨胀风险）
	    SELECT 
	        p.sku,
	        p.brand,
	        p.inventory_sku,
	        -- 已售天数 = DATEDIFF(CURRENT_DATE(), shelf_date) + 1 - 1
	        DATEDIFF(CURRENT_DATE(), p.shelf_date) AS sold_days,
	        COALESCE(s.total_qty_to_date, 0) AS total_qty_to_date,
	        COALESCE(s.last_30d_qty, 0) AS last_30d_qty
	    FROM feishu_dwd.dwd_feishu_product_all_d p
	    LEFT JOIN sales_agg s 
	        ON p.sku = s.sku 
	        AND p.brand = s.brand
	    WHERE p.brand = '韦德' 
	      AND p.shelf_date IS NOT NULL
	),
	daily_sales_calc AS (
	    -- 3. 根据已售天数计算日销量
	    SELECT 
	        sku,
	        brand,
	        inventory_sku,
	        CASE
	            WHEN sold_days <= 0 THEN NULL -- 已售天数=0或上架当天,日销量为空
	            WHEN sold_days < 30 THEN total_qty_to_date * 1.0 / sold_days -- 不足30天按实际已售天数计算
	            ELSE last_30d_qty * 1.0 / 30 -- 满30天按30天平均计算
	        END AS daily_sales
	    FROM base_data
	)
	-- 4. 计算最终可售周期
	SELECT 
	    sku,
	    brand,
	    inventory_sku,
	    daily_sales,
	    CASE 
	        WHEN daily_sales IS NULL OR daily_sales = 0 THEN NULL -- 防止除零,日销量为0或空时返回NULL
	        ELSE inventory_sku / daily_sales 
	    END AS sellable_days -- 可售周期(天)
	FROM daily_sales_calc;
```

> **基准字段明确**：已上架天数 N 基于 `shelf_date`（上架日期）计算,与 3.6 节保持一致。

---

### 3.13 系列日销

| 项       | 说明                          |
| -------- | ----------------------------- |
| 数据来源 | 计算字段                      |
| 口径     | 同系列下所有SKU的"日销量"之和 |

```
系列日销 = SUM(同系列所有SKU的日销量)
```

| 项       | 说明                                             |
| -------- | ------------------------------------------------ |
| 分组依据 | `dwd_feishu_product_all_d.series`,按系列分组  |
| 计算方式 | 先用3.11节逻辑算出每个SKU的日销量,再按系列 SUM  |
| 说明     | 用于评估整个系列的销售热度,而非单SKU，系列和SKU存在层级结构，只要计算了SKU的销量，自然就有了系列的销量|
| 边界     | 系列内某些SKU无销售数据时,其日销量视为0参与汇总 |


---

### 3.14 日销量

| 项       | 说明                                                         |
| -------- | ------------------------------------------------------------ |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.qty`                |
| 口径     | 直接取值，四个渠道金额总和，`dwd_feishu_sales_all_d.qty`这个值就是根据sales_date来的日销量 |
| 边界     | 兜底为0 |

---

### 3.15 日金额

| 项       | 说明                                                    |
| -------- | ------------------------------------------------------- |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.amt`           |
| 口径     | 从首次销售日期到昨日,该SKU在核心渠道的实际销售金额总和，`dwd_feishu_sales_all_d.amt`这个值就是根据sales_date来的日金额 |

```
金额 = SUM(amt)
数据源: dwd_feishu_sales_all_d
条件: sku匹配 AND sales_date BETWEEN first_sales_date AND DATE_SUB(CURRENT_DATE(), 1)
渠道范围: 暂时只关注韦德四个核心渠道。
```

| 项       | 说明                |
| -------- | ------------------- |
| 时间范围 | 同累计销量（首次销售日期~昨天） |
| 渠道范围 | **核心4个渠道**（与累计销量保持一致） |
| 单位     | 元（DECIMAL(18,6)） |

> 1. **时间范围**：基于 `first_sales_date`（首次销售日期）计算,即从首次销售开始累计。
> 2. **渠道范围**：仅取核心渠道,后续调整时再考虑361品牌和韦德其他渠道。

---

### 3.16 累计销量

| 项       | 说明                                                |
| -------- | --------------------------------------------------- |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.qty`       |
| 口径     | 从销售第一天到昨日,该SKU在核心渠道的实际销量总和 |

```
累计销量 = SUM(qty)
数据源: dwd_feishu_sales_all_d
条件: sku匹配 AND sales_date BETWEEN shelf_date AND DATE_SUB(CURRENT_DATE(), 1)
渠道范围: 暂时只关注韦德四个核心渠道。
```

| 项       | 说明                                |
| -------- | ----------------------------------- |
| 时间范围 | 上架日期（shelf_date） ~ 昨天（共已上架天数-1天,因今日销量次日才更新） |
| 渠道范围 | **核心4个渠道**（与日销量、金额保持一致） |
| 边界     | 首次销售当天（已售天数=1）,累计销量=当天的日销量  |

> **重点说明**：
> 1. **时间范围**：基于 `shelf_date`（上架日期）计算,即从上架开始累计。
> 2. **渠道范围**：仅取核心渠道,后续调整时再考虑361品牌和韦德其他渠道。

---

### 3.17 累计金额

| 项       | 说明                                                |
| -------- | --------------------------------------------------- |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.amt`       |
| 口径     | 从销售第一天到昨日,该SKU在核心渠道的实际销售金额总和 |

```
累计金额 = SUM(amt)
数据源: dwd_feishu_sales_all_d
其余逻辑和累计销量一致
```

| 项       | 说明                                |
| -------- | ----------------------------------- |
| 时间范围 | 上架日期（shelf_date） ~ 昨天（共已上架天数-1天,因今日销量次日才更新） |
| 渠道范围 | **核心4个渠道**（与日销量、金额保持一致） |
| 边界     | 首次销售当天（已售天数=1）,累计销量=当天的日销量  |

> **重点说明**：
> 1. **时间范围**：基于 `shelf_date`（上架日期）计算,即从上架开始累计。
> 2. **渠道范围**：仅取核心渠道,后续调整时再考虑361品牌和韦德其他渠道。

---

### 3.18 订货数量

| 项       | 说明                                                                             |
| -------- | -------------------------------------------------------------------------------- |
| 数据来源 | 计算字段,基于 `dwd_feishu_brand_order_arrival_d.order_qty`                                           |
| 口径     | 直接取值。该style_no_size的订货件数                         |
| 说明     | `dwd_feishu_product_all_d`通过 `style_no`+`size`关联feishu_dwd.dwd_feishu_brand_order_arrival_d表的 `style_no_size`取订货数量，和取`30_est_arrival_date`逻辑一致 |
| 边界     | 空值兜底为0                                                                      |

> **SKC维度说明**：即style_no维度,聚合各尺码SKU的 `order_qty` 之和 = SKC维度订货数量。

---

### 3.19 达成比例

| 项       | 说明                    |
| -------- | ----------------------- |
| 数据来源 | 计算字段                |
| 口径     | `累计销量 / 订货数量` |
| 含义     | 已完成订货量的百分比                                                                                             |
| 边界     | 订货数量=0时为空（防止除零）                                                                                     |

```
达成比例 = 3.16节(累计销量) / 3.18节(订货数量)
```

---

### 3.20 总订货数量

| 项       | 说明                    |
| -------- | ----------------------- |
| 数据来源 | 计算字段                |
| 口径     |  `dwd_feishu_brand_order_arrival_d.order_qty` + `dwd_feishu_product_wd_d.replenish_qty` |
| 含义     | `订货数量`+`补货数量`                                                                                             |
| 边界     | 兜底为0                                                                                     |

> **补货字段处理逻辑**：
> - 总订货数量仅作前端展示字段，一切涉及计算逻辑的以订货数量为准。
> - `dwd_feishu_product_all_d`已包含 `is_replenish`（是否补货）和 `replenish_qty`（补货量）字段。
> - **建议处理方式**：在 DWS 层计算"达成比例"时,单独 LEFT JOIN `dwd_feishu_product_all_d` 获取这两个字段。判断逻辑：当 `is_replenish = '是'` 时,总订货数量 = 订货数量 + `replenish_qty`；否则分母 = 订货数量。
> - 361品牌无补货概念,分母直接取订货数量。

---

### 3.21 昨日实际销售

| 项       | 说明                                              |
| -------- | ------------------------------------------------- |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.qty`     |
| 口径     | 昨日（CURRENT_DATE()-1）该style_no_size在指定渠道的销量总和 |

```
昨日实际销售 = SUM(qty)
数据源: dwd_feishu_sales_all_d
条件: sku匹配 AND sales_date = DATE_SUB(CURRENT_DATE(), 1)
      AND channel_code IN ('wd', 'japan', 'spanish', 'germany')
```

| 项           | 说明                                                        |
| ------------ | ----------------------------------------------------------- |
| 韦德渠道范围 | wd + japan + spanish + germany（4个核心渠道）,韦德渠道18目前仅关注这4个核心渠道。 |
| 361渠道范围  | 361sport + china_company + 361_sample + staff_hk（4个渠道）都暂不关注 |
| 时间         | 仅昨天一天                                                  |
| 边界         | 昨日无销售记录时为0                                         |

---

### 3.22 昨日销售达成情况

| 项       | 说明                                      |
| -------- | ----------------------------------------- |
| 数据来源 | 计算字段                                  |
| 口径     | `昨日实际销售 / 昨日的销售计划(销售后)` |
| 说明     | 始终展示当前日期的销售达成情况，无论当前日期是上架第几天,销售计划(销售后)见后面部分说明 |

```
昨日销售达成情况 = 3.17节(昨日实际销售) / 昨日对应的销售计划(销售后)
```

| 项   | 说明                                                               |
| ---- | ------------------------------------------------------------------ |
| 分母 | 昨天是上架第几天,就取第几天的销售计划(销售后)值，销售计划(销售后)见后面部分说明 |
| 示例 | 昨天是上架第5天,则分母=第5天的销售计划(销售后)                    |
| 边界 | 销售计划(销售后)=0时为空                                           |

---

### 3.23 7天销售达成情况

| 项       | 说明                                              |
| -------- | ------------------------------------------------- |
| 数据来源 | 计算字段                                          |
| 口径     | `近7天实际销量总和 / 近7天销售计划(销售后)总和` |
| 说明     | 始终展示当前日期的销售达成情况，无论当前日期是上架第几天,销售计划(销售后)见后面部分说明 |

```
7天销售达成情况 = 近7天实际销量 / 近7天销售计划(销售后)之和
```

| 项   | 说明                                                                  |
| ---- | --------------------------------------------------------------------- |
| 分子 | 最近7天（含昨日）的实际销量总和（核心渠道）                           |
| 分母 | 最近7天每天对应的"销售计划(销售后)"值之和                             |
| 说明 | 逐天计算销售计划(销售后),再求和。不是用7天总销量除以一个固定值       |
| 示例 | 昨天是上市第10天,则分母=第4天+第5天+...+第10天的销售计划(销售后)之和 |
| 边界 | 分母=0时为空                                                          |

---

### 3.24 30天销售达成情况

| 项       | 说明                                                |
| -------- | --------------------------------------------------- |
| 数据来源 | 计算字段                                            |
| 口径     | `近30天实际销量总和 / 近30天销售计划(销售后)总和` |
| 说明     | 始终展示当前日期的销售达成情况，无论当前日期是上架第几天,销售计划(销售后)见后面部分说明 |

```
30天销售达成情况 = 近30天实际销量 / 近30天销售计划(销售后)之和
```

| 项   | 说明                     |
| ---- | ------------------------ |
| 逻辑 | 同3.19节,窗口扩大到30天 |
| 边界 | 分母=0时为空             |

---

### 3.25 今日计划销售数量

| 项       | 说明                           |
| -------- | ------------------------------ |
| 数据来源 | 计算字段                       |
| 口径     | 今天对应的"销售计划(销售后)"值 |
| 说明     | 逻辑和1~180天的销售计划逻辑一致，就是取"销售计划(销售后)"的第N项值，以当前时间为准，比如当前是上架第10天,则取第10天的销售计划(销售后)值，超过180天统称为"超周期",则为0 |

```
今日计划销售数量 = 今天的销售计划(销售后)

```

| 项   | 说明                                                           |
| ---- | -------------------------------------------------------------- |
| 说明 | "今日计划"不是固定值,而是基于截至昨日的实际销售动态调整的计划 |

---

## 四、1~180天逐日口径定义（SKU维度）

> 每个SKU的上市第1天到第180天,每天计算4个子项：
> ① 销售计划(销售前)  ② 销售计划(销售后)  ③ 实际销售  ④ 达成情况

### 4.1 基础变量定义

| 变量          | 定义                                                      | 说明                                             |
| ------------- | --------------------------------------------------------- | ------------------------------------------------ |
| F             | 上市第1天 =shelf_date                                     | 上架时间就是上市第1天,上市第1天=1               |
| N             | 上市第N天 =`DATEDIFF(CURRENT_DATE(), shelf_date) + 1` 	| N 取值 1~180,基于首次销售日期计算               |
| Q             | 订货数量 =`dwd_feishu_brand_order_arrival_d.order_qty`     | 3.18节                                           |
| sold_days     | 已售天数 = N 			                                       | 今天不更新销量,故计算时排除第N天自身，也没有sales_date=CURRENT_DATE()的实际销量 |
| cum_actual(N) | 截至第N天的实际销量总和                                 | = SUM(qty) WHERE lifecycle_day BETWEEN 1 AND N |
| phase(N)      | 第N天所在阶段                                             | 见下方阶段表                                     |
| ratio(N)      | 第N天所在阶段的比例                                       | 见下方阶段表                                     |

> **基准日期明确**：
> - N（上市第N天）基于 `shelf_date`（上架日期）为第一天计算：N 取值 1~180，
> - 即从上架日期算起,第1天为1,第2天为2,以此类推,第180天为180。
> - 以所有SKU中，每个SKU最早上市时间为单个SKU的开始销售日期sale_date,从上架日期算起,作为第一天。
> - 这里用两个字段表示，sale_date表示销售日期,从上架第一天至今，对应feishu_dwd.dwd_feishu_sales_all_d的sales_date字段，区别在于，这是连续的，销量为0的天也会展示。
> - sale_date_label表示销售日期的qbi展示格式，从上架第一天至第180天，1天、2天、3天...180天。每个SKU超过180天的命名为“超周期”。以整体SKU中最晚的上架日期+180天为结束日期。
> - 比如所有SKU中，整体SKU中最早的上架日期为2025-01-01,最晚的上架日期为206-01-01,则最晚的上架日期+180天为2026-06-30。
> - 其中SKC1是最早上市时间为2025-01-01,所以,sale_date为2025-01-01~2026-06-30,sale_date_label在2025-01-01~2025-06-30销售期为1天、2天、3天...180天，2025-06-30以后为“超周期”表示。
> - 其中SKC2是最早上市时间为2026-01-01,所以,sale_date为2026-01-01~2026-06-30,sale_date_label在2026-01-01~2026-06-30销售期为1天、2天、3天...180天，2026-06-30以后为“超周期”表示，直到2026-06-30为止。
> - 其中SKC3是最早上市时间为2025-06-01,所以,sale_date为2025-06-01~2026-06-30,sale_date_label在2025-06-01~2026-11-28销售期为1天、2天、3天...180天，2026-11-28以后为“超周期”表示。


### 4.2 阶段与比例

| 阶段   | 天数范围 | ratio | 含义                    |
| ------ | -------- | ----- | ----------------------- |
| 新品期 | 1~30     | 80%   | 新品期总目标 = Q * 80%  |
| 热销期 | 31~120   | 110%  | 热销期总目标 = Q * 110% |
| 清货期 | 121~180  | 100%  | 清货期总目标 = Q * 100% |
| 销售延长期 | 181~整体SKU中最晚的上架日期+180天为结束日期  | 100%  | 销售延长期总目标 = Q * 100% |

> 销售延长期：只计算可售周期（库存现存量/30天平均销售），重点关注库存清理；以当前日期计算。
> 订货数量：后续以阶段乘以ratio(N)之后的值计算后续逻辑。

---

### 4.3 第①项：销售计划(销售前)

| 项       | 说明                                                            |
| -------- | --------------------------------------------------------------- |
| 口径     | `Q * ratio(N) / 180`                                          |
| 说明     | 固定计划,不依赖实际销售。将阶段目标量等比分配到该阶段的每一天  |
| 数据来源 | Q来自 `dwd_feishu_brand_order_arrival_d.order_qty`,ratio来自阶段定义，聚合到style_no_size维度使用 |
| 特点     | 上架前即可算出180天的计划值,不随实际销售变化                   |

**示例**（Q=1000）：

| 天  | 阶段   | ratio | 计划(前)                 |
| --- | ------ | ----- | ------------------------ |
| 1   | 新品期 | 80%   | 1000 * 0.8 / 180 = 4.444 |
| 30  | 新品期 | 80%   | 每个阶段*每个阶段的ratio，需要减截至昨天的累计实际销量 |
| 31  | 热销期 | 110%  | 每个阶段*每个阶段的ratio，需要减截至昨天的累计实际销量 |
| 120 | 热销期 | 110%  | 每个阶段*每个阶段的ratio，需要减截至昨天的累计实际销量 |
| 121 | 清货期 | 100%  | 每个阶段*每个阶段的ratio，需要减截至昨天的累计实际销量 |
| 180 | 清货期 | 100%  | 每个阶段*每个阶段的ratio，需要减截至昨天的累计实际销量 |
| 超周期 | 销售延长期 | 100%  | 已当前日期为准，只计算可售周期（库存现存量/30天平均销售） |

---

### 4.4 第②项：销售计划(销售后)

| 项       | 说明                                                                                                        |
| -------- | ----------------------------------------------------------------------------------------------------------- |
| 口径     | `(Q - cum_actual(N)) * ratio(N) / (180 - sold_days)`                                                      |
| 展开     | `(订货数量 - 截至昨天的累计实际销量) * 当前阶段比例 / (180 - 昨天是第几天)`                               |
| 说明     | 有了实际销售后,用剩余可销量按当前阶段比例动态分配给剩余天数                                                |
| 数据来源 | Q来自 `dwd_feishu_brand_order_arrival_d.order_qty`；cum_actual来自 `dwd_feishu_sales_all_d` 按lifecycle_day累计 |
| 特点     | 每天更新。实际卖得越多,后续计划越低；反之亦然                                                              |

> **cum_actual口径说明**：cum_actual(N) = 截至第N-1天,该SKU在**韦德核心渠道**的实际销量总和。lifecycle_day 基于上架日期 `shelf_date` 计算（与4.1节保持一致）。

**示例**（Q=1000）：

| 天N | cum_actual(N)   | 阶段   | 计算过程                     | 计划(后) |
| --- | --------------- | ------ | ---------------------------- | -------- |
| 1   | 0（无历史）     | 新品期 | (1000-0) * 0.8 / (180-0)     | 4.444    |
| 2   | 第1天实际=5     | 新品期 | (1000-5) * 0.8 / (180-1)     | 4.469    |
| 5   | 前4天总和=50    | 新品期 | (1000-50) * 0.8 / (180-4)    | 4.318    |
| 31  | 前30天总和=200  | 热销期 | (1000-200) * 1.1 / (180-30)  | 5.867    |
| 121 | 前120天总和=800 | 清货期 | (1000-800) * 1.0 / (180-120) | 3.333    |
| >180天为超周期 | 前180天总和=990 | 销售延长期 | (1000-990) * 1.0 / 近30天平均销售 | 以当前时间为准，每天实时更新  |

**详细递推示例**（新品期2~30天）：

```
订货数量Q=1000,已上架5天,前4天实际销量分别为：5, 8, 6, 10（总和=29）

第5天销售计划(销售后) = (1000 - 29) * 0.8 / (180 - 4) = 971 * 0.8 / 176 = 4.414

第6天（假设第5天实际卖了7）：
  前5天总和 = 29 + 7 = 36
  第6天销售计划(销售后) = (1000 - 36) * 0.8 / (180 - 5) = 964 * 0.8 / 175 = 4.407
```

> **关于cum_actual的口径说明**：cum_actual(N) 中的累计是**截至第N-1天的实际销量总和**,只包含实际卖出的量,不包含计划量。

---

### 4.5 第③项：实际销售

| 项   | 说明                       |
| ---- | -------------------------- |
| 口径 | 该SKU在上市第N天的实际销量 |

```
实际销售(N) = SUM(qty)
数据源: dwd_feishu_sales_all_d
条件: 需要根据每个SKU的shelf_date补齐sales_date,再根据sales_date匹配实际销量，没有的sales_date则为0
渠道范围: 核心渠道（与累计销量、日销量保持一致）
```

| 项       | 说明                                                        |
| -------- | ----------------------------------------------------------- |
| 数据来源 | `dwd_feishu_sales_all_d.qty`,按 sku + sales_date 聚合 |
| 渠道范围 | **核心4个渠道**（韦德4个）                          |
| 边界     | 该天无销售记录时为0                                         |
| 说明     | 匹配方式：`SUM(qty) WHERE 补齐后的表中的sku + sales_date 匹配 按 sku + sales_date 聚合的sales_date`    |

> **说明**：
> 1. **基准日期**：`dwd_feishu_sales_all_d.qty`中的sales_date是不全的，不包括没有销量的sales_date,需要根据每个SKU的shelf_date补齐sales_date,再根据sales_date匹配实际销量，没有的sales_date则为0。4.1节已说明，sales_date和sales_date_label的区别。
> 2. **渠道范围**：已确定"所有销量、金额只采用4个核心渠道"。修正为与日销量、累计销量、金额保持一致,仅取核心渠道。

---

### 4.6 第④项：达成情况

| 项   | 说明                                           |
| ---- | ---------------------------------------------- |
| 口径 | `第③项(实际销售) / 第②项(销售计划-销售后)` |

```
达成情况(N) = 实际销售(N) / 销售计划_后(N)
```

| 项   | 说明                                   |
| ---- | -------------------------------------- |
| 含义 | >100% 表示超预期完成,<100% 表示未达标 |
| 边界 | 销售计划(销售后)=0时为空               |

**示例**（Q=1000）：

| 天 | 实际销售 | 计划(后) | 达成情况            |
| -- | -------- | -------- | ------------------- |
| 1  | 5        | 4.444    | 5 / 4.444 = 112.5%  |
| 2  | 10       | 4.469    | 10 / 4.469 = 223.8% |

---

## 五、SKC维度字段口径定义

> 以下口径与第三节SKU维度逻辑一致，仅维度从 `style_no_size` 聚合到 `style_no`（SKC）。
> **核心聚合规则**：SKC = `style_no`，所有销量/金额/库存按 `style_no` 汇总；时间类字段取该SKC下所有SKU的最早值。

### 5.1 SKC编码

| 项       | 说明                                       |
| -------- | ------------------------------------------ |
| 数据来源 | `dwd_feishu_product_all_d.style_no`           |
| 口径     | 直接取值                                   |
| 粒度     | 一条SKC一条记录                            |
| 边界     | 过滤 `style_no IS NOT NULL AND style_no <> 'None'` |

---

### 5.2 品牌

| 项       | 说明                               |
| -------- | ---------------------------------- |
| 数据来源 | `dwd_feishu_product_all_d.brand` |
| 口径     | 直接取值,值为'361'或'韦德'        |
| 边界     | 无空值                             |

---

### 5.3 系列

| 项       | 说明                                        |
| -------- | ------------------------------------------- |
| 数据来源 | `dwd_feishu_product_all_d.series`         |
| 口径     | 直接取值。SKC所属系列名称（如"7代"、"8代"） |
| 边界     | 空值兜底为'None'                            |

---

### 5.4 IP

| 项       | 说明                                          |
| -------- | --------------------------------------------- |
| 数据来源 | `dwd_feishu_product_all_d.ip`               |
| 口径     | 直接取值。SKC所属ip名称（如"幻影"、"文化鞋"） |
| 边界     | 空值兜底为'None'                              |

---

### 5.5 上架时间（shelf_date）

| 项       | 说明                                                                                          |
| -------- | --------------------------------------------------------------------------------------------- |
| 数据来源 | `dwd_feishu_product_all_d.shelf_date`                                                       |
| 口径     | 该SKC下所有SKU中最早上架日期：`MIN(shelf_date)`                                              |
| 说明     | SKC的上架时间即为该SKC下所有SKU的最早上架时间。韦德取 `shelf_date`,361取 `actual_shelf_date`（已在DWD层ETL中统一映射为 `shelf_date`）,空值兜底为NULL |
| 边界     | 空值兜底为NULL,使用 NULLIF 将默认的 '1970-01-01' 转为 NULL,避免影响上架天数计算 |

> **字段语义明确**：SKC维度的 `shelf_date` 取该SKC下所有SKU的 `MIN(shelf_date)`,即最早上架日期作为SKC的销售第一天。
> 销售相关指标（累计销量、1~180天逐日分析、销售周期标签等）的计算基准字段为 SKC上架时间（`MIN(shelf_date)`）。
> **shelf_date为空的情况**：先对每个SKU按3.5节逻辑补全（通过`style_no`+`size`关联`dwd_feishu_brand_order_arrival_d`表的`style_no_size`,取 `30_est_arrival_date` 作为 `shelf_date`），再取该SKC下所有SKU的 `MIN(shelf_date)`。

---

### 5.6 首次销售日期（first_sales_date）

| 项                 | 说明                                                                        |
| ------------------ | --------------------------------------------------------------------------- |
| **业务定义** | **SKC维度下第一次产生销量的日期**仅作展示 |
| **韦德品牌** | 该SKC下所有SKU的 `MIN(first_sales_date)`                     |
| **361品牌**  | 对该SKC下所有SKU,取 `dwd_feishu_sales_all_d` 中该SKC最早有销量的 `sales_date`        |
| 边界 		  | 空值兜底为NULL |

---

### 5.7 已上架天数

| 项       | 说明                                                            |
| -------- | --------------------------------------------------------------- |
| 数据来源 | 计算字段                                                        |
| 口径     | `DATEDIFF(CURRENT_DATE(), SKC上架时间) + 1`              |
| 说明     | **上架日期当天为销售第一天**（即SKC的最早上架时间,即该SKC下所有SKU的MIN(shelf_date)）。`CURRENT_DATE()` 为当前日期 |
| 示例     | SKC上架时间='2026-06-01',今天='2026-06-30',已上架天数=29+1=30 |
| 边界     | 若 SKC上架时间为NULL,该字段为空 |

> **口径明确**：SKC已上架天数 = `DATEDIFF(CURRENT_DATE(), MIN(shelf_date)) + 1`,以该SKC下最早上架日期作为"第一天"。
> **注意**：本口径与业务文档"已上架天数 = today()-上架日期+1"的描述一致。

---

### 5.8 销售周期标签

| 项       | 说明                          |
| -------- | ----------------------------- |
| 数据来源 | 计算字段（基于SKC已上架天数）    |
| 口径     | 将180天销售周期划分为三个阶段,以SKC上架时间（MIN(shelf_date)）作为"第一天"开始 |

| 标签   | 条件                           |
| ------ | ------------------------------ |
| 新品期 | 已上架天数 BETWEEN 1 AND 30    |
| 热销期 | 已上架天数 BETWEEN 31 AND 120  |
| 清货期 | 已上架天数 BETWEEN 121 AND 180 |

| 边界 | 已上架天数 > 180 时,标记为"超周期"；已上架天数为空时,标签为空 |

> **"超周期"说明**：已上架天数 > 180 时,标记为"超周期"。超过180天之后的每一天，只关注每天的日销量、日金额、累计销量、累计金额、在仓库存、可提库存、可售周期。

---

### 5.9 在仓库存

| 项       | 说明                                       |
| -------- | ------------------------------------------ |
| 数据来源 | `dwd_feishu_product_all_d.inventory_sku` |
| 口径     | 该SKC下所有SKU的在仓库存之和：`SUM(inventory_sku)` |
| 说明     | 将同一style_no下所有尺码SKU的库存数量汇总 |
| 边界     | 空值兜底为0                                |

> **替代取值**：也可直接取 `dwd_feishu_product_all_d.inventory_skc` 字段（韦德有,361为空,空值兜底为0）。
> **361品牌缺失说明**：当前场景仅考虑韦德的四个渠道，不考虑361品牌。

---

### 5.10 可提库存

| 项       | 说明                                                                                  |
| -------- | ------------------------------------------------------------------------------------- |
| 数据来源 | `dwd_feishu_inventory_wdpinpai_d.inventory_qty`                                     |
| 口径     | 该SKC下所有SKU的可提库存之和：`SUM(inventory_qty)`                                   |
| 说明     | 来自品牌方库存表的当日快照,取最新 `inventory_date` 对应的记录,按style_no聚合所有尺码的库存 |
| 取值逻辑 | 对同一style_no下所有SKU,取 `inventory_date = MAX(inventory_date)` 的记录的 `SUM(inventory_qty)` |
| 边界     | 空值兜底为0；361品牌无品牌方库存数据,该字段为0                                       |

```sql
-- 取最新日期的品牌方库存,按SKC(style_no)聚合
SELECT
    inv.style_no,
    SUM(inv.inventory_qty) AS available_inventory
FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d inv
INNER JOIN (
    SELECT style_no, MAX(inventory_date) AS max_date
    FROM feishu_dwd.dwd_feishu_inventory_wdpinpai_d
    WHERE 1=1
    GROUP BY style_no
) latest ON inv.style_no = latest.style_no AND inv.inventory_date = latest.max_date
GROUP BY inv.style_no
```

---

### 5.11 可售周期(天)

| 项       | 说明                                       |
| -------- | ------------------------------------------ |
| 数据来源 | 计算字段                                   |
| 口径     | `SKC在仓库存 / SKC 30天平均日销`                      |
| 说明     | 当前SKC库存在当前销售速度下可维持销售的天数   |
| 分母定义 | 见5.12节"30天平均日销"                           |
| 边界     | SKC日销量=0或为空时,可售周期为空（防止除零） |

---

### 5.12 30天平均日销

| 项       | 说明                                                         |
| -------- | ------------------------------------------------------------ |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.qty`                |
| 口径     | **SKC维度30天平均日销**。已售天数不足30天时按实际已售天数计算 |

```
已上架天数 = N（基于 SKC上架时间 计算：DATEDIFF(CURRENT_DATE(), MIN(shelf_date)) + 1）
已售天数 = N - 1（今日销量次日才更新,故排除今天）

如果已售天数 = 0:  日销量 = 空（无销售历史）
如果已售天数 < 30: 日销量 = 截至昨日的SKC累计实际销量 / 已售天数
如果已售天数 >= 30: 日销量 = 最近30天的SKC实际销量总和 / 30
```

| 项       | 说明                                                                                                                                        |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| 渠道范围 | **韦德品牌**：4个核心渠道 wd + japan + spanish + germany |
| 数据源   | `dwd_feishu_sales_all_d`,按style_no对应渠道过滤后 SUM(qty)                                                                                   |
| 边界     | 已售天数=0时为空                                                                                                                            |

```sql
-- 参考SQL,韦德品牌：SKC维度日销量计算示例（假设当前日期为CURRENT_DATE()）
WITH sales_agg AS (
    -- 1. 先将销售明细表按 style_no+brand 聚合,避免 JOIN 时的一对多数据膨胀
    SELECT
        style_no,
        brand,
        -- 截至昨日累计销量
        SUM(CASE WHEN sales_date < CURRENT_DATE() THEN qty ELSE 0 END) AS total_qty_to_date,
        -- 最近30天销量 (昨日往前推30天)
        SUM(CASE WHEN sales_date >= DATE_SUB(CURRENT_DATE(), 30) AND sales_date < CURRENT_DATE() THEN qty ELSE 0 END) AS last_30d_qty
    FROM feishu_dwd.dwd_feishu_sales_all_d
    WHERE brand = '韦德'
      -- 限定韦德品牌及4个核心渠道
      AND channel_code IN ('wd', 'japan', 'spanish', 'germany')
    GROUP BY
        style_no,
        brand
),
skc_base AS (
    -- 2. 计算每个SKC的最早上架时间和在仓库存
    SELECT
        style_no,
        brand,
        MIN(shelf_date) AS skc_shelf_date,
        SUM(COALESCE(inventory_sku, 0)) AS inventory_skc
    FROM feishu_dwd.dwd_feishu_product_all_d
    WHERE brand = '韦德'
    GROUP BY style_no, brand
),
base_data AS (
    -- 3. SKC基础信息 LEFT JOIN 聚合后的销售数据（此时已是1对1关系,无膨胀风险）
    SELECT
        sk.style_no,
        sk.brand,
        sk.inventory_skc,
        DATEDIFF(CURRENT_DATE(), sk.skc_shelf_date) AS sold_days,
        COALESCE(s.total_qty_to_date, 0) AS total_qty_to_date,
        COALESCE(s.last_30d_qty, 0) AS last_30d_qty
    FROM skc_base sk
    LEFT JOIN sales_agg s
        ON sk.style_no = s.style_no
        AND sk.brand = s.brand
    WHERE sk.skc_shelf_date IS NOT NULL
),
daily_sales_calc AS (
    -- 4. 根据已售天数计算SKC日销量
    SELECT
        style_no,
        brand,
        inventory_skc,
        CASE
            WHEN sold_days <= 0 THEN NULL -- 已售天数=0或上架当天,日销量为空
            WHEN sold_days < 30 THEN total_qty_to_date * 1.0 / sold_days -- 不足30天按实际已售天数计算
            ELSE last_30d_qty * 1.0 / 30 -- 满30天按30天平均计算
        END AS daily_sales
    FROM base_data
)
-- 5. 计算最终可售周期
SELECT
    style_no,
    brand,
    inventory_skc,
    daily_sales,
    CASE
        WHEN daily_sales IS NULL OR daily_sales = 0 THEN NULL -- 防止除零
        ELSE inventory_skc / daily_sales
    END AS sellable_days -- 可售周期(天)
FROM daily_sales_calc;
```

> **基准字段明确**：已上架天数 N 基于 SKC上架时间（`MIN(shelf_date)`）计算,与 5.5 节保持一致。

---

### 5.13 系列日销

| 项       | 说明                          |
| -------- | ----------------------------- |
| 数据来源 | 计算字段                      |
| 口径     | 同系列下所有SKC的"日销量"之和 |

```
系列日销 = SUM(同系列所有SKC的日销量)
```

| 项       | 说明                                             |
| -------- | ------------------------------------------------ |
| 分组依据 | `dwd_feishu_product_all_d.series`,按系列分组  |
| 计算方式 | 先用5.12节逻辑算出每个SKC的日销量,再按系列 SUM  |
| 说明     | 用于评估整个系列的销售热度,而非单SKC，系列和SKC存在层级结构，只要计算了SKC的销量，自然就有了系列的销量|
| 边界     | 系列内某些SKC无销售数据时,其日销量视为0参与汇总 |

---

### 5.14 日销量

| 项       | 说明                                                         |
| -------- | ------------------------------------------------------------ |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.qty`                |
| 口径     | 直接取值，四个渠道销量总和，按style_no聚合 `SUM(qty)`即为SKC日销量 |
| 边界     | 兜底为0 |

---

### 5.15 日金额

| 项       | 说明                                                    |
| -------- | ------------------------------------------------------- |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.amt`           |
| 口径     | 从首次销售日期到昨日,该SKC在核心渠道的实际销售金额总和，按style_no聚合 `SUM(amt)`即为SKC日金额 |

```
金额 = SUM(amt)
数据源: dwd_feishu_sales_all_d
条件: style_no匹配 AND sales_date BETWEEN SKC首次销售日期 AND DATE_SUB(CURRENT_DATE(), 1)
渠道范围: 暂时只关注韦德四个核心渠道。
```

| 项       | 说明                |
| -------- | ------------------- |
| 时间范围 | 同累计销量（SKC首次销售日期~昨天） |
| 渠道范围 | **核心4个渠道**（与累计销量保持一致） |
| 单位     | 元（DECIMAL(18,6)） |

> 1. **时间范围**：基于 SKC首次销售日期（`MIN(first_sales_date)`）计算,即从首次销售开始累计。
> 2. **渠道范围**：仅取核心渠道,后续调整时再考虑361品牌和韦德其他渠道。

---

### 5.16 累计销量

| 项       | 说明                                                |
| -------- | --------------------------------------------------- |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.qty`       |
| 口径     | 从销售第一天到昨日,该SKC在核心渠道的实际销量总和 |

```
累计销量 = SUM(qty)
数据源: dwd_feishu_sales_all_d
条件: style_no匹配 AND sales_date BETWEEN SKC上架时间 AND DATE_SUB(CURRENT_DATE(), 1)
渠道范围: 暂时只关注韦德四个核心渠道。
```

| 项       | 说明                                |
| -------- | ----------------------------------- |
| 时间范围 | SKC上架日期（MIN(shelf_date)） ~ 昨天（共已上架天数-1天,因今日销量次日才更新） |
| 渠道范围 | **核心4个渠道**（与日销量、金额保持一致） |
| 边界     | 首次销售当天（已售天数=1）,累计销量=当天的日销量  |

> **重点说明**：
> 1. **时间范围**：基于 SKC上架时间（`MIN(shelf_date)`）计算,即从最早上架开始累计。
> 2. **渠道范围**：仅取核心渠道,后续调整时再考虑361品牌和韦德其他渠道。

---

### 5.17 累计金额

| 项       | 说明                                                |
| -------- | --------------------------------------------------- |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.amt`       |
| 口径     | 从销售第一天到昨日,该SKC在核心渠道的实际销售金额总和 |

```
累计金额 = SUM(amt)
数据源: dwd_feishu_sales_all_d
其余逻辑和累计销量一致
```

| 项       | 说明                                |
| -------- | ----------------------------------- |
| 时间范围 | SKC上架日期（MIN(shelf_date)） ~ 昨天（共已上架天数-1天,因今日销量次日才更新） |
| 渠道范围 | **核心4个渠道**（与日销量、金额保持一致） |
| 边界     | 首次销售当天（已售天数=1）,累计金额=当天的日金额  |

> **重点说明**：
> 1. **时间范围**：基于 SKC上架时间（`MIN(shelf_date)`）计算,即从最早上架开始累计。
> 2. **渠道范围**：仅取核心渠道,后续调整时再考虑361品牌和韦德其他渠道。

---

### 5.18 订货数量

| 项       | 说明                                                                             |
| -------- | -------------------------------------------------------------------------------- |
| 数据来源 | 计算字段,基于 `dwd_feishu_brand_order_arrival_d.order_qty`                                           |
| 口径     | 该SKC下所有尺码SKU的订货数量之和：`SUM(order_qty)`                         |
| 说明     | 按 `style_no` 关联 `dwd_feishu_brand_order_arrival_d` 表,聚合该SKC下所有 `style_no_size` 的 `order_qty` |
| 边界     | 空值兜底为0                                                                      |

> **替代取值**：也可直接取 `dwd_feishu_product_all_d.order_qty_skc` 字段（韦德有,361为空,空值兜底为0）。

---

### 5.19 达成比例

| 项       | 说明                    |
| -------- | ----------------------- |
| 数据来源 | 计算字段                |
| 口径     | `SKC累计销量 / SKC订货数量` |
| 含义     | 已完成订货量的百分比                                                                                             |
| 边界     | SKC订货数量=0时为空（防止除零）                                                                                     |

```
达成比例 = 5.16节(SKC累计销量) / 5.18节(SKC订货数量)
```

---

### 5.20 总订货数量

| 项       | 说明                    |
| -------- | ----------------------- |
| 数据来源 | 计算字段                |
| 口径     |  `SKC订货数量` + `SKC补货数量` |
| 含义     | `订货数量`+`补货数量`                                                                                             |
| 边界     | 兜底为0                                                                                     |

> **补货字段处理逻辑**：
> - 总订货数量仅作前端展示字段，一切涉及计算逻辑的以订货数量为准。
> - SKC维度补货数量 = 该SKC下所有SKU的 `SUM(replenish_qty)`。
> - 判断逻辑：当该SKC下任一SKU的 `is_replenish = '是'` 时,总订货数量 = SKC订货数量 + SKC补货数量；否则总订货数量 = SKC订货数量。
> - 361品牌无补货概念,总订货数量直接取SKC订货数量。

---

### 5.21 昨日实际销售

| 项       | 说明                                              |
| -------- | ------------------------------------------------- |
| 数据来源 | 计算字段,基于 `dwd_feishu_sales_all_d.qty`     |
| 口径     | 昨日（CURRENT_DATE()-1）该SKC在指定渠道的销量总和 |

```
昨日实际销售 = SUM(qty)
数据源: dwd_feishu_sales_all_d
条件: style_no匹配 AND sales_date = DATE_SUB(CURRENT_DATE(), 1)
      AND channel_code IN ('wd', 'japan', 'spanish', 'germany')
```

| 项           | 说明                                                        |
| ------------ | ----------------------------------------------------------- |
| 韦德渠道范围 | wd + japan + spanish + germany（4个核心渠道） |
| 时间         | 仅昨天一天                                                  |
| 边界         | 昨日无销售记录时为0                                         |

---

### 5.22 昨日销售达成情况

| 项       | 说明                                      |
| -------- | ----------------------------------------- |
| 数据来源 | 计算字段                                  |
| 口径     | `SKC昨日实际销售 / SKC昨日的销售计划(销售后)` |
| 说明     | 始终展示当前日期的销售达成情况，无论当前日期是上架第几天,销售计划(销售后)见第六部分说明 |

```
昨日销售达成情况 = 5.21节(SKC昨日实际销售) / SKC昨日对应的销售计划(销售后)
```

| 项   | 说明                                                               |
| ---- | ------------------------------------------------------------------ |
| 分母 | 昨天是SKC上架第几天,就取第几天的销售计划(销售后)值，销售计划(销售后)见第六部分说明 |
| 示例 | 昨天是上架第5天,则分母=第5天的销售计划(销售后)                    |
| 边界 | 销售计划(销售后)=0时为空                                           |

---

### 5.23 7天销售达成情况

| 项       | 说明                                              |
| -------- | ------------------------------------------------- |
| 数据来源 | 计算字段                                          |
| 口径     | `SKC近7天实际销量总和 / SKC近7天销售计划(销售后)总和` |
| 说明     | 始终展示当前日期的销售达成情况，无论当前日期是上架第几天,销售计划(销售后)见第六部分说明 |

```
7天销售达成情况 = SKC近7天实际销量 / SKC近7天销售计划(销售后)之和
```

| 项   | 说明                                                                  |
| ---- | --------------------------------------------------------------------- |
| 分子 | 最近7天（含昨日）的SKC实际销量总和（核心渠道）                           |
| 分母 | 最近7天每天对应的"SKC销售计划(销售后)"值之和                             |
| 说明 | 逐天计算SKC销售计划(销售后),再求和。不是用7天总销量除以一个固定值       |
| 示例 | 昨天是上市第10天,则分母=第4天+第5天+...+第10天的销售计划(销售后)之和 |
| 边界 | 分母=0时为空                                                          |

---

### 5.24 30天销售达成情况

| 项       | 说明                                                |
| -------- | --------------------------------------------------- |
| 数据来源 | 计算字段                                            |
| 口径     | `SKC近30天实际销量总和 / SKC近30天销售计划(销售后)总和` |
| 说明     | 始终展示当前日期的销售达成情况，无论当前日期是上架第几天,销售计划(销售后)见第六部分说明 |

```
30天销售达成情况 = SKC近30天实际销量 / SKC近30天销售计划(销售后)之和
```

| 项   | 说明                     |
| ---- | ------------------------ |
| 逻辑 | 同5.23节,窗口扩大到30天 |
| 边界 | 分母=0时为空             |

---

### 5.25 今日计划销售数量

| 项       | 说明                           |
| -------- | ------------------------------ |
| 数据来源 | 计算字段                       |
| 口径     | 今天对应的"SKC销售计划(销售后)"值 |
| 说明     | 逻辑和1~180天的销售计划逻辑一致，就是取"销售计划(销售后)"的第N项值，以当前时间为准，比如当前是上架第10天,则取第10天的销售计划(销售后)值，超过180天统称为"超周期",则为0 |

```
今日计划销售数量 = SKC今天的销售计划(销售后)

```

| 项   | 说明                                                           |
| ---- | -------------------------------------------------------------- |
| 说明 | "今日计划"不是固定值,而是基于截至昨日的实际销售动态调整的计划 |

---

## 六、1~180天逐日口径定义（SKC维度）

> 每个SKC的上市第1天到第180天,每天计算4个子项：
> ① 销售计划(销售前)  ② 销售计划(销售后)  ③ 实际销售  ④ 达成情况
> 逻辑与第四节SKU维度完全一致，仅维度从 `style_no_size` 聚合到 `style_no`（SKC）。

### 6.1 基础变量定义

| 变量          | 定义                                                      | 说明                                             |
| ------------- | --------------------------------------------------------- | ------------------------------------------------ |
| F             | 上市第1天 = MIN(shelf_date)                               | SKC上架时间即该SKC下所有SKU的最早上架时间,上市第1天=1               |
| N             | 上市第N天 =`DATEDIFF(CURRENT_DATE(), MIN(shelf_date)) + 1` | N 取值 1~180,基于SKC上架时间计算               |
| Q             | 订货数量 =`SUM(dwd_feishu_brand_order_arrival_d.order_qty)` 按 style_no 聚合   | 5.18节                                           |
| sold_days     | 已售天数 = N 			                                       | 今天不更新销量,故计算时排除第N天自身，也没有sales_date=CURRENT_DATE()的实际销量 |
| cum_actual(N) | 截至第N天的SKC实际销量总和                                 | = SUM(qty) WHERE lifecycle_day BETWEEN 1 AND N,按style_no聚合 |
| phase(N)      | 第N天所在阶段                                             | 见下方阶段表                                     |
| ratio(N)      | 第N天所在阶段的比例                                       | 见下方阶段表                                     |

> **基准日期明确**：
> - N（上市第N天）基于 SKC上架时间（`MIN(shelf_date)`）为第一天计算：N 取值 1~180，
> - 即从SKC最早上架日期算起,第1天为1,第2天为2,以此类推,第180天为180。
> - 以所有SKC中，每个SKC最早上架时间为单个SKC的开始销售日期sale_date,从上架日期算起,作为第一天。
> - 这里用两个字段表示，sale_date表示销售日期,从上架第一天至今，对应feishu_dwd.dwd_feishu_sales_all_d的sales_date字段，区别在于，这是连续的，销量为0的天也会展示。
> - sale_date_label表示销售日期的qbi展示格式，从上架第一天至第180天，1天、2天、3天...180天。每个SKC超过180天的命名为"超周期"。以整体SKC中最晚的上架日期+180天为结束日期。
> - 比如所有SKC中，整体SKC中最早的上架日期为2025-01-01,最晚的上架日期为2026-01-01,则最晚的上架日期+180天为2026-06-30。
> - 其中SKC1是最早上市时间为2025-01-01,所以,sale_date为2025-01-01~2026-06-30,sale_date_label在2025-01-01~2025-06-30销售期为1天、2天、3天...180天，2025-06-30以后为"超周期"表示。
> - 其中SKC2是最早上市时间为2026-01-01,所以,sale_date为2026-01-01~2026-06-30,sale_date_label在2026-01-01~2026-06-30销售期为1天、2天、3天...180天，2026-06-30以后为"超周期"表示，直到2026-06-30为止。
> - 其中SKC3是最早上市时间为2025-06-01,所以,sale_date为2025-06-01~2026-06-30,sale_date_label在2025-06-01~2025-11-28销售期为1天、2天、3天...180天，2025-11-28以后为"超周期"表示。


### 6.2 阶段与比例

| 阶段   | 天数范围 | ratio | 含义                    |
| ------ | -------- | ----- | ----------------------- |
| 新品期 | 1~30     | 80%   | 新品期总目标 = Q * 80%  |
| 热销期 | 31~120   | 110%  | 热销期总目标 = Q * 110% |
| 清货期 | 121~180  | 100%  | 清货期总目标 = Q * 100% |
| 销售延长期 | 181~整体SKC中最晚的上架日期+180天为结束日期  | 100%  | 销售延长期总目标 = Q * 100% |

> 销售延长期：只计算可售周期（库存现存量/30天平均销售），重点关注库存清理；以当前日期计算。
> 订货数量：后续以阶段乘以ratio(N)之后的值计算后续逻辑。

---

### 6.3 第①项：销售计划(销售前)

| 项       | 说明                                                            |
| -------- | --------------------------------------------------------------- |
| 口径     | `Q * ratio(N) / 180`                                          |
| 说明     | 固定计划,不依赖实际销售。将阶段目标量等比分配到该阶段的每一天  |
| 数据来源 | Q来自 `dwd_feishu_brand_order_arrival_d.order_qty` 按 style_no 聚合,ratio来自阶段定义 |
| 特点     | 上架前即可算出180天的计划值,不随实际销售变化                   |

**示例**（Q=1000）：

| 天  | 阶段   | ratio | 计划(前)                 |
| --- | ------ | ----- | ------------------------ |
| 1   | 新品期 | 80%   | 1000 * 0.8 / 180 = 4.444 |
| 30  | 新品期 | 80%   | 每个阶段*每个阶段的ratio，需要减截至昨天的累计实际销量 |
| 31  | 热销期 | 110%  | 每个阶段*每个阶段的ratio，需要减截至昨天的累计实际销量 |
| 120 | 热销期 | 110%  | 每个阶段*每个阶段的ratio，需要减截至昨天的累计实际销量 |
| 121 | 清货期 | 100%  | 每个阶段*每个阶段的ratio，需要减截至昨天的累计实际销量 |
| 180 | 清货期 | 100%  | 每个阶段*每个阶段的ratio，需要减截至昨天的累计实际销量 |
| 超周期 | 销售延长期 | 100%  | 以当前日期为准，只计算可售周期（库存现存量/30天平均销售） |

---

### 6.4 第②项：销售计划(销售后)

| 项       | 说明                                                                                                        |
| -------- | ----------------------------------------------------------------------------------------------------------- |
| 口径     | `(Q - cum_actual(N)) * ratio(N) / (180 - sold_days)`                                                      |
| 展开     | `(SKC订货数量 - 截至昨天的SKC累计实际销量) * 当前阶段比例 / (180 - 昨天是第几天)`                               |
| 说明     | 有了实际销售后,用剩余可销量按当前阶段比例动态分配给剩余天数                                                |
| 数据来源 | Q来自 `dwd_feishu_brand_order_arrival_d.order_qty` 按 style_no 聚合；cum_actual来自 `dwd_feishu_sales_all_d` 按lifecycle_day累计（style_no维度） |
| 特点     | 每天更新。实际卖得越多,后续计划越低；反之亦然                                                              |

> **cum_actual口径说明**：cum_actual(N) = 截至第N-1天,该SKC在**韦德核心渠道**的实际销量总和（按style_no聚合所有尺码SKU的销量）。lifecycle_day 基于SKC上架时间 `MIN(shelf_date)` 计算（与6.1节保持一致）。

**示例**（Q=1000）：

| 天N | cum_actual(N)   | 阶段   | 计算过程                     | 计划(后) |
| --- | --------------- | ------ | ---------------------------- | -------- |
| 1   | 0（无历史）     | 新品期 | (1000-0) * 0.8 / (180-0)     | 4.444    |
| 2   | 第1天实际=5     | 新品期 | (1000-5) * 0.8 / (180-1)     | 4.469    |
| 5   | 前4天总和=50    | 新品期 | (1000-50) * 0.8 / (180-4)    | 4.318    |
| 31  | 前30天总和=200  | 热销期 | (1000-200) * 1.1 / (180-30)  | 5.867    |
| 121 | 前120天总和=800 | 清货期 | (1000-800) * 1.0 / (180-120) | 3.333    |
| >180天为超周期 | 前180天总和=990 | 销售延长期 | (1000-990) * 1.0 / 近30天平均销售 | 以当前时间为准，每天实时更新  |

**详细递推示例**（新品期2~30天）：

```
SKC订货数量Q=1000,已上架5天,前4天SKC实际销量分别为：5, 8, 6, 10（总和=29）

第5天销售计划(销售后) = (1000 - 29) * 0.8 / (180 - 4) = 971 * 0.8 / 176 = 4.414

第6天（假设第5天SKC实际卖了7）：
  前5天总和 = 29 + 7 = 36
  第6天销售计划(销售后) = (1000 - 36) * 0.8 / (180 - 5) = 964 * 0.8 / 175 = 4.407
```

> **关于cum_actual的口径说明**：cum_actual(N) 中的累计是**截至第N-1天的SKC实际销量总和**,只包含实际卖出的量,不包含计划量。

---

### 6.5 第③项：实际销售

| 项   | 说明                       |
| ---- | -------------------------- |
| 口径 | 该SKC在上市第N天的实际销量（按style_no聚合所有尺码SKU的销量） |

```
实际销售(N) = SUM(qty)
数据源: dwd_feishu_sales_all_d
条件: 需要根据每个SKC的MIN(shelf_date)补齐sales_date,再根据sales_date匹配实际销量，没有的sales_date则为0
渠道范围: 核心渠道（与累计销量、日销量保持一致）
```

| 项       | 说明                                                        |
| -------- | ----------------------------------------------------------- |
| 数据来源 | `dwd_feishu_sales_all_d.qty`,按 style_no + sales_date 聚合 |
| 渠道范围 | **核心4个渠道**（韦德4个）                          |
| 边界     | 该天无销售记录时为0                                         |
| 说明     | 匹配方式：`SUM(qty) WHERE 补齐后的表中的style_no + sales_date 匹配 按 style_no + sales_date 聚合的sales_date`    |

> **说明**：
> 1. **基准日期**：`dwd_feishu_sales_all_d.qty`中的sales_date是不全的，不包括没有销量的sales_date,需要根据每个SKC的MIN(shelf_date)补齐sales_date,再根据sales_date匹配实际销量，没有的sales_date则为0。6.1节已说明，sales_date和sales_date_label的区别。
> 2. **渠道范围**：已确定"所有销量、金额只采用4个核心渠道"。修正为与日销量、累计销量、金额保持一致,仅取核心渠道。

---

### 6.6 第④项：达成情况

| 项   | 说明                                           |
| ---- | ---------------------------------------------- |
| 口径 | `第③项(实际销售) / 第②项(销售计划-销售后)` |

```
达成情况(N) = 实际销售(N) / 销售计划_后(N)
```

| 项   | 说明                                   |
| ---- | -------------------------------------- |
| 含义 | >100% 表示超预期完成,<100% 表示未达标 |
| 边界 | 销售计划(销售后)=0时为空               |

**示例**（Q=1000）：

| 天 | 实际销售 | 计划(后) | 达成情况            |
| -- | -------- | -------- | ------------------- |
| 1  | 5        | 4.444    | 5 / 4.444 = 112.5%  |
| 2  | 10       | 4.469    | 10 / 4.469 = 223.8% |

---

## 七、字段与DWD表映射关系汇总

> 韦德4个核心渠道。
> **渠道口径**：所有销量、金额指标、所有计算逻辑都是基于韦德4个核心渠道。
> **适用维度**：以下渠道范围同时适用于SKU维度和SKC维度,两个维度渠道口径一致。

### 8.1 SKU维度

> **映射表**：累计销量、金额、1~180天实际销售的渠道范围为"核心4个渠道"。已上架天数公式基准字段明确为 `shelf_date`（上架日期）。

| 业务字段              | DWD表                              | DWD字段          | 取值方式                                              | 对应章节 |
| --------------------- | ---------------------------------- | ---------------- | ----------------------------------------------------- | -------- |
| SKU                   | product_all_d                      | style_no_size    | 直接取值                                              | 3.1      |
| 品牌                  | product_all_d                      | brand            | 直接取值                                              | 3.2      |
| 系列                  | product_all_d                      | series           | 直接取值,空值兜底'None'                               | 3.3      |
| IP                    | product_all_d                      | ip               | 直接取值,空值兜底'None'                               | 3.4      |
| 上架时间              | product_all_d                      | shelf_date       | 直接取值（仅展示用）,空值取30_est_arrival_date补全    | 3.5      |
| 首次销售日期          | product_all_d                      | first_sales_date | 韦德直接取值；361需从sales_all_d计算MIN(sales_date)   | 3.6      |
| 已上架天数            | 计算                               | -                | DATEDIFF(CURRENT_DATE(), shelf_date) + 1              | 3.7      |
| 销售周期标签          | 计算                               | -                | CASE 已上架天数(新品期/热销期/清货期/超周期)          | 3.8      |
| 在仓库存              | product_all_d                      | inventory_sku    | 直接取值,空值兜底0                                    | 3.9      |
| 可提库存              | inventory_wdpinpai_d               | inventory_qty    | 取最新日期按sku聚合                                    | 3.10     |
| 可售周期(天)          | 计算                               | -                | 在仓库存 / 30天平均日销                               | 3.11     |
| 30天平均日销          | sales_all_d + 计算                 | qty              | 30天平均(核心4个渠道)                                 | 3.12     |
| 系列日销              | sales_all_d + product_all_d + 计算 | qty, series      | 同系列SUM(日销量)                                     | 3.13     |
| 日销量                | sales_all_d                        | qty              | 按sales_date汇总(核心4个渠道)                         | 3.14     |
| 日金额                | sales_all_d                        | amt              | 按sales_date汇总(核心4个渠道)                         | 3.15     |
| 累计销量              | sales_all_d                        | qty              | SUM(核心4个渠道,shelf_date~昨日)                      | 3.16     |
| 累计金额              | sales_all_d                        | amt              | SUM(核心4个渠道,shelf_date~昨日)                      | 3.17     |
| 订货数量              | brand_order_arrival_d              | order_qty        | 按style_no_size关联取值,空值兜底0                     | 3.18     |
| 达成比例              | 计算                               | -                | 累计销量 / 订货数量                                   | 3.19     |
| 总订货数量            | 计算                               | -                | 订货数量 + 补货数量(is_replenish='时')                | 3.20     |
| 昨日实际销售          | sales_all_d                        | qty              | SUM(昨日,核心4个渠道)                                 | 3.21     |
| 昨日销售达成情况      | 计算                               | -                | 昨日实际 / 昨日计划(后)                               | 3.22     |
| 7天销售达成情况       | 计算                               | -                | 近7天实际 / 近7天计划(后)                             | 3.23     |
| 30天销售达成情况      | 计算                               | -                | 近30天实际 / 近30天计划(后)                           | 3.24     |
| 今日计划销售数量      | 计算                               | -                | 今天的销售计划(后)                                    | 3.25     |
| 1~180天①销售计划(前) | 计算                               | -                | Q * ratio / 180                                       | 4.3      |
| 1~180天②销售计划(后) | 计算                               | -                | (Q-cum_actual)*ratio/(180-sold_days)                  | 4.4      |
| 1~180天③实际销售     | sales_all_d                        | qty              | SUM(第N天,核心4个渠道)                                | 4.5      |
| 1~180天④达成情况     | 计算                               | -                | ③ / ②                                               | 4.6      |

### 8.2 SKC维度

> **映射表**：
> 1. SKC维度 = `style_no`（款号/商品货号字段），所有指标按 `style_no` 聚合；
> 2. 已上架天数基于 SKC 上架时间（`MIN(shelf_date)`）计算,作为 SKC 销售逻辑的"第一天"基准；
> 3. 累计销量、金额、1~180天实际销售时间范围遵守sales_date和sales_date_label,  `dwd_feishu_sales_all_d.qty`中的sales_date是不全的，不包括没有销量的sales_date,需要根据每个SKC的MIN(shelf_date)补齐sales_date,再根据sales_date匹配实际销量，没有的sales_date则为0。渠道范围统一为"核心4个渠道"。

| 业务字段              | DWD表                              | DWD字段          | 取值方式                                                | 与SKU维度关系     | 对应章节 |
| --------------------- | ---------------------------------- | ---------------- | ------------------------------------------------------- | ----------------- | -------- |
| SKC                   | product_all_d                      | style_no         | 直接取值,过滤空值和'None'                               | 聚合键            | 5.1      |
| 品牌                  | product_all_d                      | brand            | 直接取值                                                | 同SKU             | 5.2      |
| 系列                  | product_all_d                      | series           | 直接取值,空值兜底'None'                                 | 同SKU             | 5.3      |
| IP                    | product_all_d                      | ip               | 直接取值,空值兜底'None'                                 | 同SKU             | 5.4      |
| 上架时间              | product_all_d                      | shelf_date       | MIN(shelf_date),SKC下取最早（仅展示）                   | SKC下取最早       | 5.5      |
| 首次销售日期          | product_all_d                      | first_sales_date | MIN(first_sales_date),SKC下取最早                       | SKC下取最早       | 5.6      |
| 已上架天数            | 计算                               | -                | DATEDIFF(CURRENT_DATE(), MIN(shelf_date)) + 1           | 独立计算          | 5.7      |
| 销售周期标签          | 计算                               | -                | CASE SKC已上架天数(新品期/热销期/清货期/超周期)         | 独立计算          | 5.8      |
| 在仓库存              | product_all_d                      | inventory_sku    | SUM(inventory_sku)按style_no聚合,空值兜底0              | SKU聚合           | 5.9      |
| 可提库存              | inventory_wdpinpai_d               | inventory_qty    | SUM(inventory_qty)按style_no聚合,取最新日期             | SKU聚合           | 5.10     |
| 可售周期(天)          | 计算                               | -                | SKC在仓库存 / SKC 30天平均日销                          | 独立计算          | 5.11     |
| 30天平均日销          | sales_all_d + 计算                 | qty              | 30天平均(核心4个渠道),按style_no聚合                    | SKU聚合           | 5.12     |
| 系列日销              | sales_all_d + product_all_d + 计算 | qty, series      | 同系列SUM(SKC日销量)                                    | SKC聚合           | 5.13     |
| 日销量                | sales_all_d                        | qty              | 按sales_date+style_no汇总(核心4个渠道)                  | SKU聚合           | 5.14     |
| 日金额                | sales_all_d                        | amt              | 按sales_date+style_no汇总(核心4个渠道)                  | SKU聚合           | 5.15     |
| 累计销量              | sales_all_d                        | qty              | SUM(核心4个渠道,MIN(shelf_date)~昨日),按style_no聚合    | SKU聚合           | 5.16     |
| 累计金额              | sales_all_d                        | amt              | SUM(核心4个渠道,MIN(shelf_date)~昨日),按style_no聚合    | SKU聚合           | 5.17     |
| 订货数量              | brand_order_arrival_d              | order_qty        | SUM(order_qty)按style_no聚合,空值兜底0                  | SKU聚合           | 5.18     |
| 达成比例              | 计算                               | -                | SKC累计销量 / SKC订货数量                               | 独立计算          | 5.19     |
| 总订货数量            | 计算                               | -                | SKC订货数量 + SKC补货数量(SUM(replenish_qty))           | SKU聚合           | 5.20     |
| 昨日实际销售          | sales_all_d                        | qty              | SUM(昨日,核心4个渠道),按style_no聚合                    | SKU聚合           | 5.21     |
| 昨日销售达成情况      | 计算                               | -                | SKC昨日实际 / SKC昨日计划(后)                           | 独立计算          | 5.22     |
| 7天销售达成情况       | 计算                               | -                | SKC近7天实际 / SKC近7天计划(后)                         | 独立计算          | 5.23     |
| 30天销售达成情况      | 计算                               | -                | SKC近30天实际 / SKC近30天计划(后)                       | 独立计算          | 5.24     |
| 今日计划销售数量      | 计算                               | -                | SKC今天的销售计划(后)                                   | 独立计算          | 5.25     |
| 1~180天①销售计划(前) | 计算                               | -                | Q * ratio / 180,Q按style_no聚合                        | 独立计算          | 6.3      |
| 1~180天②销售计划(后) | 计算                               | -                | (Q-cum_actual)*ratio/(180-sold_days),按style_no聚合     | 独立计算          | 6.4      |
| 1~180天③实际销售     | sales_all_d                        | qty              | SUM(第N天,核心4个渠道),按style_no聚合                   | SKU聚合           | 6.5      |
| 1~180天④达成情况     | 计算                               | -                | ③ / ②                                                 | 独立计算          | 6.6      |

---
