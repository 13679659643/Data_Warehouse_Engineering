# QuickBI 数据集字段口径汇总

> 编写日期：2026-07-23
> 数据来源：SKU数据集 = `feishu_ads.ads_sku_sales_plan_180d_d`；SKC数据集 = `feishu_ads.ads_skc_sales_plan_180d_d`
> 口径依据：`基于DWD层的字段口径定义.md`、`DWS.md`、`ADS.md`
> 全局范围：韦德品牌4个核心渠道 `channel_code IN ('wd', 'japan', 'spanish', 'germany')`

---

## 一、SKU数据集字段口径（按查询顺序）

1. style_no_size  SKU编码  `dwd_feishu_product_all_d.style_no` + `dwd_feishu_product_all_d.size`，`CONCAT_WS('-', style_no, size)`，过滤`style_no_size IS NOT NULL AND style_no_size <> 'None'`

2. style_no  款号  `dwd_feishu_product_all_d.style_no`，直接取值

3. brand  品牌  `dwd_feishu_product_all_d.brand`，直接取值，值为'韦德'

4. series  系列  `dwd_feishu_product_all_d.series`，`COALESCE(NULLIF(TRIM(series), ''), 'None')`，空值兜底'None'

5. ip  IP  `dwd_feishu_product_all_d.ip`，`COALESCE(NULLIF(TRIM(ip), ''), 'None')`，空值兜底'None'

6. size  尺码  `dwd_feishu_product_all_d.size`，直接取值

7. color_name  配色名  `dwd_feishu_product_all_d.color_name`，`COALESCE(NULLIF(TRIM(color_name), ''), 'None')`，空值兜底'None'

8. product_name  商品名称  `dwd_feishu_product_all_d.product_name`，直接取值

9. category  品类  `dwd_feishu_product_all_d.category`，直接取值

10. tag_price  吊牌价  `dwd_feishu_product_all_d.tag_price`，`COALESCE(tag_price, 0)`，空值兜底0

11. shelf_date  上架日期  优先取`dwd_feishu_product_all_d.shelf_date`，为空则关联`dwd_feishu_brand_order_arrival_d.30_est_arrival_date`(按style_no_size取MIN)，`COALESCE(NULLIF(shelf_date, DATE('1970-01-01')), est_arrival_date)`

12. first_sales_date  首次销售日期  `dwd_feishu_product_all_d.first_sales_date`，韦德直接取值，`NULLIF(first_sales_date, DATE('1970-01-01'))`

13. sale_date  销售日期  从SKU自身shelf_date到全局最晚shelf_date+180天逐日补齐，`DATE_ADD(shelf_date, INTERVAL day_offset DAY)`，通过`GENERATE_SERIES(0, DATEDIFF(全局最晚shelf_date+180, shelf_date))`生成

14. lifecycle_day  上市第N天  `DATEDIFF(sale_date, shelf_date) + 1`，day_offset + 1

15. sale_date_label  销售日期标签  `CASE WHEN lifecycle_day BETWEEN 1 AND 180 THEN CONCAT('第', CAST(lifecycle_day AS VARCHAR), '天') ELSE '超周期' END`

16. 销售日期标签_排序  `CASE WHEN sale_date_label='超周期' THEN '999' ELSE LPAD(REPLACE(REPLACE(sale_date_label,'第',''),'天',''),3,'0') END`

17. sales_phase  销售阶段  `CASE WHEN lifecycle_day BETWEEN 1 AND 30 THEN '新品期' / 31~120 THEN '热销期' / 121~180 THEN '清货期' / >180 THEN '超周期'`

18. is_over_cycle  是否超周期  `CASE WHEN lifecycle_day > 180 THEN 1 ELSE 0 END`

19. plan_pre  销售计划(销售前)  `Q * ratio / 180`，1~180天计算，超周期NULL；Q=`dwd_feishu_brand_order_arrival_d.order_qty`，ratio=新品期0.8/热销期1.1/清货期1.0

20. plan_post  销售计划(销售后)  `(Q - cum_actual) * ratio / NULLIF(181 - N, 0)`，1~180天计算，超周期NULL；cum_actual=截至第N-1天的`SUM(dwd_feishu_sales_all_d.qty)`(核心4渠道，按style_no_size+sales_date聚合)

21. daily_qty  日销量  `dwd_feishu_sales_all_d.qty`，按style_no_size+sales_date聚合`SUM(qty)`，核心4渠道，`COALESCE(daily_qty, 0)`空值兜底0

22. daily_amt  日金额  `dwd_feishu_sales_all_d.amt`，按style_no_size+sales_date聚合`SUM(amt)`，核心4渠道，`COALESCE(daily_amt, 0)`空值兜底0

23. cum_qty  累计销量  `cum_actual(N-1) + actual_qty(N)`，截至当天N的累计；基础`dwd_feishu_sales_all_d.qty`，时间范围shelf_date~昨日，核心4渠道，窗口函数`SUM(qty) OVER(PARTITION BY style_no_size ORDER BY sale_date ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + actual_qty`

24. cum_amt  累计金额  `cum_actual_amt(N-1) + actual_amt(N)`，截至当天N的累计；基础`dwd_feishu_sales_all_d.amt`，时间范围shelf_date~昨日，核心4渠道

25. achievement_rate  达成情况  `daily_qty / plan_post`，1~180天计算，plan_post=0或超周期时NULL

26. achievement_ratio  达成比例  `累计销量 / 订货数量`，`CAST(cum_actual AS DECIMAL(18,6)) / NULLIF(CAST(order_qty AS DECIMAL(18,6)), 0)`，order_qty=0时NULL

27. inventory_sku  在仓库存  `dwd_feishu_product_all_d.inventory_sku`，`COALESCE(inventory_sku, 0)`，空值兜底0

28. available_inventory  可提库存  `dwd_feishu_inventory_wdpinpai_d.inventory_qty`，取最新`inventory_date=MAX(inventory_date)`，按sku聚合`SUM(inventory_qty)`，`COALESCE(available_inventory, 0)`

29. daily_avg_qty_30d  30天平均日销  基于`dwd_feishu_sales_all_d.qty`(核心4渠道)；已售天数=0→NULL，已售天数<30→cum_actual/sold_days，已售天数≥30→last_30d_qty/30；sold_days=N-1(排除今天)

30. sellable_days  可售周期天数  `在仓库存 / 30天平均日销`；1~180天用滚动近30天日销(不含当天，`SUM(qty) ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING` / LEAST(lifecycle_day-1, 30))，超周期用当前时间近30天日销；日销=0或无库存时NULL

31. yesterday_actual_qty  昨日实际销售  `dwd_feishu_sales_all_d.qty`，`SUM(qty) WHERE sale_date = DATE_SUB(CURRENT_DATE(), 1)`，核心4渠道，`COALESCE(..., 0)`空值兜底0

32. yesterday_achievement  昨日销售达成情况  `昨日实际销售 / 昨日销售计划(销售后)`，即`SUM(qty)(昨日) / plan_post(昨日lifecycle_day)`，plan_post=0时NULL

33. 7d_achievement  7天销售达成情况  `近7天(含昨日)实际销量之和 / 近7天销售计划(销售后)之和`，`SUM(actual_qty WHERE sale_date BETWEEN DATE_SUB(CURRENT_DATE(),7) AND DATE_SUB(CURRENT_DATE(),1)) / NULLIF(SUM(plan_post 同窗口), 0)`，分母=0时NULL

34. 30d_achievement  30天销售达成情况  `近30天(含昨日)实际销量之和 / 近30天销售计划(销售后)之和`，`SUM(actual_qty WHERE sale_date BETWEEN DATE_SUB(CURRENT_DATE(),30) AND DATE_SUB(CURRENT_DATE(),1)) / NULLIF(SUM(plan_post 同窗口), 0)`，分母=0时NULL

35. today_plan_qty  今日计划销售数量  `今天的销售计划(销售后)`，即`plan_post WHERE sale_date = CURRENT_DATE()`，超周期为0，`COALESCE(..., 0)`

36. order_qty  订货数量  `dwd_feishu_brand_order_arrival_d.order_qty`，按style_no_size关联取值(`CONCAT_WS('-', style_no, size) = boa.style_no_size`)，`COALESCE(order_qty, 0)`空值兜底0

37. total_order_qty  总订货数量  `CASE WHEN is_replenish='是' THEN order_qty + replenish_qty ELSE order_qty END`；补货量来自`dwd_feishu_product_all_d.replenish_qty`，`is_replenish`来自`dwd_feishu_product_all_d.is_replenish`

---

## 二、SKC数据集字段口径（按查询顺序）

> SKC维度 = `style_no`，所有指标按style_no聚合；时间类字段取该SKC下所有SKU的最早值(MIN)

1. style_no  SKC编码  `dwd_feishu_product_all_d.style_no`，直接取值，过滤`style_no IS NOT NULL AND style_no <> 'None'`

2. brand  品牌  `dwd_feishu_product_all_d.brand`，`MAX(brand)`按style_no聚合，直接取值，值为'韦德'

3. series  系列  `dwd_feishu_product_all_d.series`，`MAX(CASE WHEN NULLIF(TRIM(series),'')<>'None' THEN series ELSE NULL END)`按style_no聚合，`COALESCE(..., 'None')`空值兜底'None'

4. ip  IP  `dwd_feishu_product_all_d.ip`，`MAX(CASE WHEN NULLIF(TRIM(ip),'')<>'None' THEN ip ELSE NULL END)`按style_no聚合，`COALESCE(..., 'None')`空值兜底'None'

5. product_name  商品名称  `dwd_feishu_product_all_d.product_name`，`MAX(CASE WHEN NULLIF(TRIM(product_name),'')<>'None' THEN product_name ELSE NULL END)`按style_no聚合，`COALESCE(..., 'None')`空值兜底'None'

6. category  品类  `dwd_feishu_product_all_d.category`，`MAX(CASE WHEN NULLIF(TRIM(category),'')<>'None' THEN category ELSE NULL END)`按style_no聚合，`COALESCE(..., 'None')`空值兜底'None'

7. tag_price  吊牌价  SKC暂无吊牌价逻辑，固定为0

8. shelf_date  SKC上架日期  `MIN(shelf_date)`按style_no聚合，其中每个SKU的shelf_date先按SKU维度补全(优先`dwd_feishu_product_all_d.shelf_date`，为空取`dwd_feishu_brand_order_arrival_d.30_est_arrival_date`)；`MIN(COALESCE(NULLIF(p.shelf_date, DATE('1970-01-01')), boa.est_arrival_date))`

9. first_sales_date  SKC首次销售日期  `MIN(first_sales_date)`按style_no聚合，`MIN(NULLIF(first_sales_date, DATE('1970-01-01')))`

10. sale_date  销售日期  从SKC的MIN(shelf_date)到全局最晚shelf_date+180天逐日补齐，`DATE_ADD(shelf_date, INTERVAL day_offset DAY)`

11. lifecycle_day  上市第N天  `DATEDIFF(sale_date, MIN(shelf_date)) + 1`，day_offset + 1

12. sale_date_label  销售日期标签  `CASE WHEN lifecycle_day BETWEEN 1 AND 180 THEN CONCAT('第', CAST(lifecycle_day AS VARCHAR), '天') ELSE '超周期' END`

13. 销售日期标签_排序  `CASE WHEN sale_date_label='超周期' THEN '999' ELSE LPAD(REPLACE(REPLACE(sale_date_label,'第',''),'天',''),3,'0') END`

14. sales_phase  销售阶段  `CASE WHEN lifecycle_day BETWEEN 1 AND 30 THEN '新品期' / 31~120 THEN '热销期' / 121~180 THEN '清货期' / >180 THEN '超周期'`

15. is_over_cycle  是否超周期  `CASE WHEN lifecycle_day > 180 THEN 1 ELSE 0 END`

16. plan_pre  销售计划(销售前)  `Q * ratio / 180`，1~180天计算，超周期NULL；Q=`SUM(dwd_feishu_brand_order_arrival_d.order_qty)`按style_no聚合，ratio=新品期0.8/热销期1.1/清货期1.0

17. plan_post  销售计划(销售后)  `(Q - cum_actual) * ratio / NULLIF(181 - N, 0)`，1~180天计算，超周期NULL；cum_actual=截至第N-1天的`SUM(dwd_feishu_sales_all_d.qty)`(核心4渠道，按style_no+sales_date聚合)

18. daily_qty  日销量  `dwd_feishu_sales_all_d.qty`，按style_no+sales_date聚合`SUM(qty)`，核心4渠道，`COALESCE(daily_qty, 0)`空值兜底0

19. daily_amt  日金额  `dwd_feishu_sales_all_d.amt`，按style_no+sales_date聚合`SUM(amt)`，核心4渠道，`COALESCE(daily_amt, 0)`空值兜底0

20. cum_qty  累计销量  `cum_actual(N-1) + actual_qty(N)`，截至当天N的累计；基础`dwd_feishu_sales_all_d.qty`，时间范围MIN(shelf_date)~昨日，核心4渠道，窗口函数`SUM(qty) OVER(PARTITION BY style_no ORDER BY sale_date ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) + actual_qty`

21. cum_amt  累计金额  `cum_actual_amt(N-1) + actual_amt(N)`，截至当天N的累计；基础`dwd_feishu_sales_all_d.amt`，时间范围MIN(shelf_date)~昨日，核心4渠道

22. achievement_rate  达成情况  `daily_qty / plan_post`，1~180天计算，plan_post=0或超周期时NULL

23. achievement_ratio  SKC达成比例  `SKC累计销量 / SKC订货数量`，`CAST(cum_actual AS DECIMAL(18,6)) / NULLIF(CAST(order_qty AS DECIMAL(18,6)), 0)`，order_qty=0时NULL

24. inventory_skc  SKC在仓库存  `dwd_feishu_product_all_d.inventory_sku`，`SUM(inventory_sku)`按style_no聚合，`COALESCE(..., 0)`空值兜底0

25. available_inventory  SKC可提库存  `dwd_feishu_inventory_wdpinpai_d.inventory_qty`，取最新`inventory_date=MAX(inventory_date)`，按style_no聚合`SUM(inventory_qty)`，`COALESCE(..., 0)`

26. daily_avg_qty_30d  SKC30天平均日销  基于`dwd_feishu_sales_all_d.qty`(核心4渠道，按style_no聚合)；已售天数=0→NULL，已售天数<30→cum_actual/sold_days，已售天数≥30→last_30d_qty/30；sold_days=N-1(排除今天)

27. sellable_days  SKC可售周期天数  `SKC在仓库存 / SKC 30天平均日销`；1~180天用滚动近30天日销(不含当天，`SUM(qty) ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING` / LEAST(lifecycle_day-1, 30))，超周期用当前时间近30天日销；日销=0或无库存时NULL

28. yesterday_actual_qty  昨日实际销售  `dwd_feishu_sales_all_d.qty`，`SUM(qty) WHERE sale_date = DATE_SUB(CURRENT_DATE(), 1)`，按style_no聚合，核心4渠道，`COALESCE(..., 0)`空值兜底0

29. yesterday_achievement  昨日销售达成情况  `SKC昨日实际销售 / SKC昨日销售计划(销售后)`，即`SUM(qty)(昨日) / plan_post(昨日lifecycle_day)`，plan_post=0时NULL

30. 7d_achievement  7天销售达成情况  `近7天(含昨日)SKC实际销量之和 / 近7天SKC销售计划(销售后)之和`，`SUM(actual_qty WHERE sale_date BETWEEN DATE_SUB(CURRENT_DATE(),7) AND DATE_SUB(CURRENT_DATE(),1)) / NULLIF(SUM(plan_post 同窗口), 0)`，分母=0时NULL

31. 30d_achievement  30天销售达成情况  `近30天(含昨日)SKC实际销量之和 / 近30天SKC销售计划(销售后)之和`，`SUM(actual_qty WHERE sale_date BETWEEN DATE_SUB(CURRENT_DATE(),30) AND DATE_SUB(CURRENT_DATE(),1)) / NULLIF(SUM(plan_post 同窗口), 0)`，分母=0时NULL

32. today_plan_qty  今日计划销售数量  `SKC今天的销售计划(销售后)`，即`plan_post WHERE sale_date = CURRENT_DATE()`，超周期为0，`COALESCE(..., 0)`

33. order_qty  SKC订货数量  `dwd_feishu_brand_order_arrival_d.order_qty`，`SUM(order_qty)`按style_no聚合，`COALESCE(order_qty, 0)`空值兜底0

34. total_order_qty  SKC总订货数量  `CASE WHEN has_replenish=1 THEN order_qty + replenish_qty ELSE order_qty END`；`SUM(replenish_qty)`按style_no聚合，`MAX(CASE WHEN is_replenish='是' THEN 1 ELSE 0 END)`判断是否含补货

---

> **口径要点说明**
> - **渠道范围**：所有销量/金额指标限定韦德4个核心渠道 `channel_code IN ('wd','japan','spanish','germany')`
> - **时间基准**：已上架天数 N = `DATEDIFF(sale_date, shelf_date) + 1`，shelf_date当天为第1天
> - **阶段比例 ratio**：新品期(1~30)=0.8，热销期(31~120)=1.1，清货期(121~180)=1.0，超周期NULL
> - **cum_actual**：截至第 N-1 天的累计销量（不含当天N），窗口函数 `ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING`
> - **超周期(>180天)**：plan_pre/plan_post/achievement_rate = NULL，仅保留日销/日金额/累计/在仓/可提/可售周期
> - **日期补齐范围**：每个SKU/SKC从自身shelf_date到全局最晚shelf_date+180天
> - **SKU vs SKC 差异**：SKC无 size/color_name 字段，tag_price固定0，库存/订货/销量均按style_no聚合，时间字段取MIN
