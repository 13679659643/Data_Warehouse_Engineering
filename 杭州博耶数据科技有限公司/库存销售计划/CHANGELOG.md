# 数仓变更日志

> 本文件由 dwh-copilot version-tracker 自动维护。
> 记录每次数据仓库的 DDL / SQL / ETL / 调度变更历史。

---

## [2026-07-26 16:51] 修改 — 二期口径字段调整：DWS/ADS新增13字段并重构预计收款单价计算逻辑

- **模块**: SQL
- **分层**: DWS + ADS + 跨层(QuickBI可视化层)
- **任务**: 库存销售计划二期口径字段落地
- **操作**: 修改
- **变更内容**:
  - DWS层 `dws_sku_product_info_d` 新增字段：`cum_actual`、`sellable_days_order`、`order_qty_ratio`
  - DWS层 `dws_skc_product_info_d` 新增字段：`cum_actual`、`sellable_days_order`
  - ADS层 `ads_sku_sales_plan_180d_d` 新增字段：`current_lifecycle_day`、`plan_amt`、`cum_plan_amt`(替换占位0)、`sellable_days_order`、`sales_qty_ratio`、`order_qty_ratio`
  - ADS层 `ads_skc_sales_plan_180d_d` 新增字段：`current_lifecycle_day`、`sellable_days_order`，并将 `cum_plan_amt` 改为从 SKU ADS 表按 `style_no + sale_date` 聚合 `SUM(cum_plan_amt)`
  - QuickBI 查询语句同步新增对应字段展示
  - 预计收款单价逻辑：`ip='服配'或'篮球'` 时为 `tag_price*1.2`，其他 ip 为 `销售美金*6.8`(销售美金按吊牌价精确映射8个值,非8个值则为0)
  - `sales_qty_ratio`：从 `dws_sku_product_info_d` 取 `cum_actual`，超周期 SKU 更稳定可靠
- **关联文件**: d:\Users\QiYe\BaoZun\Project\Data_Warehouse_Engineering\杭州博耶数据科技有限公司\库存销售计划\全流程SQL语句-二期版本.md
- **回刷范围**: 全量刷新(TRUNCATE + INSERT INTO)
- **影响下游**:
  - QuickBI 可视化层需同步新增对应字段的展示配置
  - SKC ADS 表 ETL 依赖 SKU ADS 表，需调整调度顺序为"先SKU ADS，后SKC ADS"
- **备注**: 二期口径字段以《二期口径字段.md》为准；SKC ADS 的 `cum_plan_amt` 改为聚合口径后，ETL 执行顺序必须保证 SKU ADS 先于 SKC ADS 完成，否则会出现数据空值或滞后

---
