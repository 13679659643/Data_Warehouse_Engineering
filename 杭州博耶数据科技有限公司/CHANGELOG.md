# 数仓变更日志

> 本文件由 dwh-copilot version-tracker 自动维护。
> 记录每次数据仓库的 DDL / SQL / ETL / 调度变更历史。

---

## [2026-07-12 00:44] 新建 — 基于DWD层字段口径定义文档，完成DWS层、ADS层和QuickBI可视化方案的完整解决方案

- **模块**: SQL + DDL + 项目配置
- **分层**: DWS + ADS + 跨层(QuickBI)
- **任务**: dws_ads_quickbi_solution — 库存销售计划 DWS/ADS/QuickBI 完整方案建设
- **操作**: 新建
- **变更内容**:
  - DWS层新建表 `feishu_dws.dws_sku_product_info_d` — SKU商品维表
  - DWS层新建表 `feishu_dws.dws_skc_product_info_d` — SKC商品维表
  - DWS层新建表 `feishu_dws.dws_sku_sales_plan_180d_d` — SKU维度1~180天销售计划表(核心)
  - DWS层新建表 `feishu_dws.dws_skc_sales_plan_180d_d` — SKC维度1~180天销售计划表(核心)
  - DWS层新建表 `feishu_dws.dws_sku_abnormal_d` — SKU异常表
  - DWS层新建表 `feishu_dws.dws_skc_abnormal_d` — SKC异常表
  - ADS层新建表 `feishu_ads.ads_sku_sales_plan_180d_d` — SKU维度1~180天销售计划ADS表
  - ADS层新建表 `feishu_ads.ads_skc_sales_plan_180d_d` — SKC维度1~180天销售计划ADS表
  - ADS层新建表 `feishu_ads.ads_sku_skc_summary_d` — SKU/SKC汇总表
  - QuickBI方案：3个数据集设计、6个核心仪表板、筛选器/计算字段/刷新调度方案
  - 关键口径实现：韦德4个核心渠道(wd/japan/spanish/germany)
  - 维度定义：SKU维度=style_no_size，SKC维度=style_no
  - shelf_date补全逻辑：优先取product_all_d.shelf_date，为空降级取brand_order_arrival_d.30_est_arrival_date
  - 订货数量Q：SKU维度按style_no_size关联，SKC维度SUM(order_qty) by style_no
  - 销售计划公式：plan_pre=Q*ratio/180，plan_post=(Q-cum_actual)*ratio/(181-N)
  - 累计销量：cum_actual(N)=截至第N-1天累计销量
  - 日期补齐：shelf_date到全局最晚shelf_date+180天
  - 超周期处理(>180天)：仅计算日销量/日金额/累计/库存/可售周期，不计算销售计划
  - 异常SKU/SKC单独输出至独立表存储
- **关联文件**: 杭州博耶数据科技有限公司/库存销售计划/DWS.md, 杭州博耶数据科技有限公司/库存销售计划/ADS.md, 杭州博耶数据科技有限公司/库存销售计划/QUICKBI.md
- **回刷范围**: 日刷新(与DWD层同步)
- **影响下游**: QuickBI可直接连接ADS层3张表(ads_sku_sales_plan_180d_d / ads_skc_sales_plan_180d_d / ads_sku_skc_summary_d)展示; 不影响现有DWD层表结构; 不影响现有ODS层数据
- **备注**: 本次为DWS+ADS+QuickBI整体方案首次落地，依赖前置DWD层字段口径定义文档(DWD.md); QuickBI侧需配置数据源连接至ADS层并按方案建立3个数据集与6个仪表板; 异常表独立输出以避免污染主销售计划表

---
