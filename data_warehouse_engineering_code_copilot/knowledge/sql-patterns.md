# SQL 常用模式库

> 经过验证的高质量数仓 SQL 模式，可直接复用。每个模式包含：场景、代码、解释、性能说明。
> 默认方言为 ANSI SQL / Hive SQL，特殊引擎差异会单独标注。

## 1. 去重保留最新

### 场景
源端可能有重复或变更记录，需要按主键保留最新一条（CDC 后处理 / 全量去重）。

### 代码
```sql
-- 保留每个 user_id 的最新一条记录
SELECT *
FROM (
    SELECT
        t.*,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY update_time DESC, op_seq DESC
        ) AS rn
    FROM ods_mysql_user.user_inc t
    WHERE dt = '${bizdate}'
) x
WHERE x.rn = 1;
```

### 解释
- `ORDER BY update_time DESC` 取最新；`op_seq` 用作并列时刻的 tie-breaker（来自 binlog 的递增序号）
- 等价的 `QUALIFY` 写法（Snowflake / Databricks / 部分版本 Flink SQL）：
  ```sql
  SELECT * FROM ods_mysql_user.user_inc
  WHERE dt='${bizdate}'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY update_time DESC) = 1;
  ```

### 性能说明
🟢 性能良好。注意 PARTITION BY 列的基数过低会引发数据倾斜，可加 `DISTRIBUTE BY user_id` 提示散列。

---

## 2. 拉链表（SCD Type 2）

### 场景
维度表需要保留历史变化（如用户等级变迁），用 `start_date / end_date / is_current` 三列标记每条版本的生效区间。

### 代码
```sql
-- 拉链表结构
-- dim_user_zip (
--   user_id, name, level, start_date, end_date, is_current, ...
-- )

INSERT OVERWRITE TABLE dwh_dim.dim_user_zip
SELECT
    -- 1) 历史链路保持不变 + 闭合当日发生变更的旧链
    CASE
        WHEN base.user_id IS NOT NULL AND base.is_current = TRUE
             AND chg.user_id IS NOT NULL
        THEN '${bizdate_minus_1}'                     -- 闭合
        ELSE base.end_date
    END AS end_date,
    CASE
        WHEN base.user_id IS NOT NULL AND base.is_current = TRUE
             AND chg.user_id IS NOT NULL
        THEN FALSE
        ELSE base.is_current
    END AS is_current,
    base.user_id, base.name, base.level, base.start_date
FROM dwh_dim.dim_user_zip base
LEFT JOIN (
    SELECT user_id FROM dwh_ods.ods_user_inc WHERE dt='${bizdate}'
) chg ON base.user_id = chg.user_id

UNION ALL

-- 2) 当日新链路（新增 or 变更后的最新版本）
SELECT
    '99991231'  AS end_date,
    TRUE        AS is_current,
    user_id, name, level,
    '${bizdate}' AS start_date
FROM dwh_ods.ods_user_inc
WHERE dt = '${bizdate}';
```

### 解释
- 拉链表的核心是"老链关，新链开"
- `end_date = '99991231'` 表示当前有效；查询历史时用 `start_date <= ds AND end_date > ds`
- 写入必须 `INSERT OVERWRITE`（保证幂等）

### 性能说明
🟡 中等。拉链表全量重写代价随历史累积增大，建议每年/每季度做归档拆分。

---

## 3. 同环比（YoY / MoM）

### 场景
计算指标的同比 / 环比，必须处理空值与除零。

### 代码
```sql
WITH base AS (
    SELECT dt, biz_date,
           SUM(amount) AS cur_amt
    FROM dwh_dws.dws_sales_1d
    WHERE dt BETWEEN '${bizdate_minus_400}' AND '${bizdate}'
    GROUP BY dt, biz_date
)
SELECT
    cur.biz_date,
    cur.cur_amt,
    yoy.cur_amt AS yoy_amt,
    mom.cur_amt AS mom_amt,
    -- 同比增长率：处理 0/NULL
    CASE
        WHEN yoy.cur_amt IS NULL OR yoy.cur_amt = 0 THEN NULL
        WHEN cur.cur_amt IS NULL OR cur.cur_amt = 0 THEN -1
        ELSE (cur.cur_amt - yoy.cur_amt) / yoy.cur_amt
    END AS yoy_rate,
    -- 环比增长率
    CASE
        WHEN mom.cur_amt IS NULL OR mom.cur_amt = 0 THEN NULL
        WHEN cur.cur_amt IS NULL OR cur.cur_amt = 0 THEN -1
        ELSE (cur.cur_amt - mom.cur_amt) / mom.cur_amt
    END AS mom_rate
FROM base cur
LEFT JOIN base yoy
    ON yoy.biz_date = date_sub(cur.biz_date, 365)
LEFT JOIN base mom
    ON mom.biz_date = date_sub(cur.biz_date, 30);
```

### 解释
- 处理"双零返 NULL，本期 0 同期非 0 返 -1（即 -100%）"约定
- 自连接日期偏移；闰年/财年场景需切换为 `dim_date` 的 yoy_date_id

### 性能说明
🟢 性能良好。base CTE 限定窗口避免全表扫，dim_date 关联会更稳健。

---

## 4. 分组 TopN

### 场景
取每个店铺销售额前 3 的 SKU。

### 代码
```sql
SELECT shop_id, sku_id, sale_amt
FROM (
    SELECT
        shop_id, sku_id, sale_amt,
        ROW_NUMBER() OVER (PARTITION BY shop_id ORDER BY sale_amt DESC) AS rn
    FROM dwh_dws.dws_shop_sku_1d
    WHERE dt = '${bizdate}'
) x
WHERE rn <= 3;
```

### 解释
- `ROW_NUMBER`：严格唯一序号；`RANK`：并列同名次但跳号；`DENSE_RANK`：并列同名次不跳号
- 大型表注意 PARTITION BY 列的基数

### 性能说明
🟡 中等。窗口函数会触发 Shuffle，必要时配合 `DISTRIBUTE BY shop_id SORT BY sale_amt DESC` 减少二次排序。

---

## 5. 累计求和（Running Total）

### 场景
按订单时间序列展示从期初到当前的累计销售。

### 代码
```sql
SELECT
    biz_date,
    daily_amt,
    SUM(daily_amt) OVER (
        ORDER BY biz_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cum_amt
FROM dwh_dws.dws_sales_1d
WHERE dt BETWEEN '${bizdate_minus_30}' AND '${bizdate}';
```

### 解释
- `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW` 是累计求和的标准写法
- 跨年/跨月分组：加 `PARTITION BY year_month`

### 性能说明
🟢 性能良好。

---

## 6. 行转列 / 列转行

### 场景
将每日销售按月份做透视，或将多列指标 unpivot 为长表。

### 代码
```sql
-- 行转列（CASE WHEN 法，通用）
SELECT
    shop_id,
    SUM(CASE WHEN month_id = '202601' THEN amt ELSE 0 END) AS amt_202601,
    SUM(CASE WHEN month_id = '202602' THEN amt ELSE 0 END) AS amt_202602,
    SUM(CASE WHEN month_id = '202603' THEN amt ELSE 0 END) AS amt_202603
FROM dwh_dws.dws_shop_month
WHERE month_id BETWEEN '202601' AND '202603'
GROUP BY shop_id;

-- 列转行（Hive：UNION ALL；Spark：stack()；Presto/Trino：UNNEST）
-- Spark 写法
SELECT shop_id, metric, value
FROM dwh_dws.dws_shop_summary
LATERAL VIEW stack(3,
    'amt',  amt,
    'qty',  qty,
    'cust', cust_cnt
) t AS metric, value
WHERE dt = '${bizdate}';
```

### 性能说明
🟢 行转列性能可控；列转行注意展开后的行数膨胀。

---

## 7. 数据回刷（幂等覆盖）

### 场景
历史分区因口径调整需要重跑，必须保证可重入。

### 代码
```sql
-- ✅ 推荐：INSERT OVERWRITE 单分区
INSERT OVERWRITE TABLE dwh_dwd.dwd_xxx_di PARTITION (dt='${bizdate}')
SELECT ...
FROM ...
WHERE biz_date = '${bizdate}';

-- ❌ 禁止：INSERT INTO（重复跑会追加重复数据）
-- INSERT INTO TABLE dwh_dwd.dwd_xxx_di PARTITION (dt='${bizdate}') ...

-- 多分区批量回刷的封装思路（伪代码）
-- for d in 20260101..20260531:
--     INSERT OVERWRITE TABLE dwh_dwd.dwd_xxx_di PARTITION (dt='${d}') ...
```

### 性能说明
🟡 单次扫描成本视加工逻辑而定。批量回刷注意控制并发与队列资源占用。

---

## 8. 增量 + 全量合并（Lambda）

### 场景
ODS 层全量 + 增量同时存在，需要合并出当日的最新全量快照。

### 代码
```sql
INSERT OVERWRITE TABLE dwh_ods.ods_user_full PARTITION (dt='${bizdate}')
SELECT * FROM (
    SELECT
        t.*,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY update_time DESC) AS rn
    FROM (
        -- 昨日全量 + 今日增量
        SELECT * FROM dwh_ods.ods_user_full WHERE dt='${bizdate_minus_1}'
        UNION ALL
        SELECT * FROM dwh_ods.ods_user_inc  WHERE dt='${bizdate}'
    ) t
) x
WHERE x.rn = 1;
```

### 解释
- 增量优先（更新时间最新）覆盖昨日全量
- 注意 schema 一致；列变更时需要在 UNION ALL 两侧补齐字段

### 性能说明
🟡 全量重写代价随用户表规模线性增长；超大表建议改用拉链或基于 ACID 表的 MERGE。

---

## 9. 缺失日期补齐

### 场景
按日维度展示指标，但事实表只在有交易的日期有记录，需要左关联日期维度表补全。

### 代码
```sql
SELECT
    d.date_id,
    COALESCE(s.amt, 0) AS amt
FROM dwh_dim.dim_date d
LEFT JOIN dwh_dws.dws_sales_1d s
    ON s.biz_date = d.date_id
   AND s.dt      = '${bizdate}'
WHERE d.date_id BETWEEN '${bizdate_minus_30}' AND '${bizdate}';
```

### 性能说明
🟢 dim_date 行数小，LEFT JOIN 代价可忽略。

---

## 10. NULL 安全比较

### 场景
Join 条件中允许两侧同时为 NULL 时匹配（业务上等价）。

### 代码
```sql
-- ❌ 标准 SQL 中 NULL <> NULL，下面 Join 会丢行
ON a.k1 = b.k1 AND a.k2 = b.k2

-- ✅ NULL 安全等于（Spark / Hive）
ON a.k1 <=> b.k1 AND a.k2 <=> b.k2

-- ✅ 通用写法（兼容所有引擎）
ON  (a.k1 = b.k1 OR (a.k1 IS NULL AND b.k1 IS NULL))
AND (a.k2 = b.k2 OR (a.k2 IS NULL AND b.k2 IS NULL))
```

### 性能说明
🟢 通用写法略慢；优先在 Hive/Spark 中使用 `<=>`。
