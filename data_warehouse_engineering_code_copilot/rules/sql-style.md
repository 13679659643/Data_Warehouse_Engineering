---
alwaysApply: true
---

# SQL 编码规范

## 1. 命名约定

### 库命名（Database / Schema）
| 用途 | 命名 | 示例 |
|------|------|------|
| 原始落地 | `ods_<source>` | `ods_mysql_orders` |
| 明细层 | `dwh_dwd` 或 `dwd_<domain>` | `dwh_dwd`, `dwd_trade` |
| 汇总层 | `dwh_dws` 或 `dws_<domain>` | `dwh_dws`, `dws_user` |
| 应用层 | `dwh_ads` 或 `ads_<domain>` | `dwh_ads`, `ads_dashboard` |
| 维度层 | `dwh_dim` | `dwh_dim` |
| 临时/中间 | `tmp_<owner>` | `tmp_gutao` |
| 运维 | `ops_<area>` | `ops_log`, `ops_meta` |

### 表命名（统一前缀 + 业务过程 + 粒度后缀）

```
{layer}_{biz_process}_{grain}{period}
```

| 前缀 | 含义 |
|------|------|
| `ods_` | 原始落地（业务库镜像） |
| `dwd_` | 明细事实表 |
| `dws_` | 轻度汇总表 |
| `ads_` | 应用层指标表 |
| `dim_` | 维度表 |
| `bridge_` | 桥接表（多对多） |
| `tmp_` | 临时表 |
| `mid_` | 中间表（不对外） |

| 粒度后缀 | 含义 |
|---------|------|
| `_di` | day incremental（天增量） |
| `_df` | day full（天全量快照） |
| `_da` | day accumulate（天累积快照） |
| `_hi` | hour incremental |
| `_1d` | 按天聚合 |
| `_1h` | 按小时聚合 |
| `_1m` | 按月聚合 |
| `_zip` | 拉链表（SCD2） |
| `_rt` | 实时（real time） |

#### 示例
| 表名 | 含义 |
|------|------|
| `ods_mysql_orders.orders_inc` | 来自 MySQL 的订单增量 |
| `dwd_trade_order_di` | 订单交易明细（天增量） |
| `dws_user_active_1d` | 用户活跃日汇总 |
| `dim_user_zip` | 用户拉链表 |
| `ads_sales_dashboard_1d` | 销售看板日表 |

### 字段命名

#### 主键 / 外键
```sql
order_sk      -- 代理键（surrogate key），BIGINT
order_id      -- 业务键（business key），通常 STRING
user_sk       -- 关联到 dim_user.user_sk
user_id       -- 业务侧用户 ID
```

#### 通用字段
| 类别 | 命名 | 类型 | 说明 |
|------|------|------|------|
| 数值金额 | `*_amt` | DECIMAL(18,4) | 金额 |
| 数量 | `*_qty`, `*_cnt` | BIGINT | 数量 / 计数 |
| 比率 | `*_rate`, `*_pct` | DECIMAL(10,6) | 比率 |
| 标志位 | `is_*`, `has_*` | BOOLEAN | 布尔 |
| 时间戳 | `*_time` | TIMESTAMP | 事件时间 |
| 日期 | `*_date` 或 `*_id`（YYYYMMDD） | STRING | 业务日期 |
| 状态 | `*_status` | STRING | 状态枚举 |
| 创建/更新 | `create_time`, `update_time` | TIMESTAMP | 元信息 |

#### 分区字段
统一使用 `dt`，类型 `STRING`，格式 `YYYYMMDD`。
小时分区使用 `dh`，格式 `YYYYMMDDHH`。

```sql
PARTITIONED BY (dt STRING COMMENT 'YYYYMMDD')
PARTITIONED BY (dt STRING, dh STRING)  -- 小时级
```

#### 命名禁忌
- ❌ 拼音、中文、混拼
- ❌ 与 SQL 保留字相同（user, order, group, date, value 等）
- ❌ 缩写不一致（amt vs amount 混用）
- ❌ camelCase / PascalCase（数仓统一 snake_case）

---

## 2. 格式规范

### 关键字大小写
- SQL 关键字统一**大写**（SELECT、FROM、JOIN、WHERE、GROUP BY、CASE WHEN）
- 函数名统一**小写**（sum, count, coalesce, row_number）
- 表名 / 字段名统一**小写**

### 缩进与换行
```sql
-- ============================================
-- 用途：用户日活汇总（DWS）
-- 依赖：dwd_user_event_di, dim_user_zip
-- 产出：dwh_dws.dws_user_active_1d
-- 调度：daily, 02:00, retry 3
-- 责任人：辜涛
-- ============================================
INSERT OVERWRITE TABLE dwh_dws.dws_user_active_1d PARTITION (dt = '${bizdate}')
SELECT
    e.user_id,
    u.user_name,
    u.level,
    COUNT(DISTINCT e.session_id)        AS session_cnt,
    COUNT(1)                            AS event_cnt,
    SUM(CASE WHEN e.event_type = 'pay'
             THEN e.amount ELSE 0 END)  AS pay_amt
FROM dwh_dwd.dwd_user_event_di e
LEFT JOIN dwh_dim.dim_user_zip u
    ON e.user_id = u.user_id
   AND '${bizdate}' BETWEEN u.start_date AND u.end_date
WHERE e.dt = '${bizdate}'
  AND e.event_type IN ('view', 'click', 'pay')
GROUP BY
    e.user_id,
    u.user_name,
    u.level;
```

### 缩进规则
- 一级缩进 4 个空格
- `SELECT` 后字段独占一行
- 字段别名使用 `AS`，对齐到固定列
- `JOIN` 子句的 `ON` 独占一行，多个条件每个独占一行
- `WHERE` 中多个条件每个独占一行，`AND` / `OR` 放在行首
- 嵌套子查询应改写为 `WITH ... AS (...)` CTE

### 头部注释（强制）
所有正式入库的 SQL 文件必须包含头部注释：

```sql
-- ============================================
-- 用途：xxx
-- 依赖：上游表 1, 上游表 2, ...
-- 产出：库.表 (粒度)
-- 调度：周期, 触发时间, 重试策略
-- 责任人：xxx
-- 变更：YYYY-MM-DD <作者> <一句话描述>
-- ============================================
```

### 行内注释
对非显然的业务规则补充行内注释：
```sql
-- amount 单位历史问题：2024-03 之前为分，需要除以 100
SUM(CASE WHEN dt < '20240301' THEN amount / 100.0 ELSE amount END) AS amt
```

---

## 3. SQL 编写原则

### 性能优先
- ✅ 大型分区表必须有分区裁剪
- ✅ 优先使用 CTE（WITH）替代深层子查询
- ✅ 多次引用的复杂 CTE 应物化为临时表
- ✅ 小表 Join 大表使用 Map Join / Broadcast hint
- ✅ 优先 GROUP BY 替代 DISTINCT（部分场景）
- ❌ 禁止 SELECT *（必须明列字段）
- ❌ 禁止在最外层不必要的 ORDER BY
- ❌ 禁止函数包裹分区字段

### 正确性优先
- ✅ Join 条件必须包含两侧的分区字段（避免膨胀）
- ✅ NULL 必须显式处理（`COALESCE`、`<=>`、`IS NULL`）
- ✅ DECIMAL 优于 FLOAT / DOUBLE（金额必须 DECIMAL）
- ✅ 类型必须显式转换，避免隐式转换 bug
- ✅ 写入大表必须 `INSERT OVERWRITE` 保证幂等

### 可维护性
- ✅ 复杂 SQL 拆为多个 CTE，每个 CTE 单一职责
- ✅ 中间步骤可命名为 `t1, t2` 以外的语义化名（如 `base_orders`, `enriched_users`）
- ✅ 统一使用表别名（即使单表查询也写出别名）
- ✅ 避免超长字段表达式（超过 80 字符换行 / 抽 CTE）

---

## 4. 禁止事项

- ❌ 禁止 `INSERT INTO` 写入分区表（应用 `INSERT OVERWRITE`）
- ❌ 禁止 `DROP TABLE` 出现在调度脚本中（删表必须走运维变更）
- ❌ 禁止在 SQL 中硬编码业务日期（必须使用 `${bizdate}` 等变量）
- ❌ 禁止跨层反向引用（如 DWD 直接读 ADS）
- ❌ 禁止 ADS / DWS 直接 JOIN ODS（应该走 DWD）
- ❌ 禁止使用未注释的"魔法数字"
- ❌ 禁止生产 SQL 中保留 `SELECT * FROM xxx LIMIT 10` 等调试代码

---

## 5. 命名检查清单

### 表命名
- [ ] 使用前缀标识层（ods_/dwd_/dws_/ads_/dim_）
- [ ] 表名清晰描述业务过程，使用单数名词
- [ ] 包含粒度后缀（_di / _df / _1d / _zip 等）
- [ ] 避免使用空格、特殊字符和 SQL 保留字

### 字段命名
- [ ] 主键使用 `_sk`（代理键）或 `_id`（业务键）
- [ ] 外键与关联维度表主键同名
- [ ] 布尔列使用 is_ / has_ 前缀
- [ ] 金额列使用 `_amt`，数量使用 `_qty/_cnt`，比率使用 `_rate/_pct`
- [ ] 全部使用 snake_case，避免大小写混用

### 整体一致性
- [ ] 全项目统一 snake_case
- [ ] 关键字大写，函数小写
- [ ] 缩进 4 空格，AND/OR 放行首

---

## 6. 常见错误对照

```sql
-- ❌ 错误：SELECT *
SELECT * FROM dwd_xxx WHERE dt = '20260601';
-- ✅ 正确
SELECT order_id, user_id, amt FROM dwd_xxx WHERE dt = '20260601';

-- ❌ 错误：函数包裹分区字段
WHERE to_date(dt) >= '2026-06-01'
-- ✅ 正确
WHERE dt >= '20260601'

-- ❌ 错误：FLOAT 存金额
amount FLOAT
-- ✅ 正确
amount DECIMAL(18,4)

-- ❌ 错误：保留字作字段名
order STRING, user STRING, value DECIMAL(10,2)
-- ✅ 正确
order_no STRING, user_id STRING, metric_value DECIMAL(10,2)

-- ❌ 错误：硬编码日期
WHERE dt = '20260601'  -- 调度脚本里
-- ✅ 正确
WHERE dt = '${bizdate}'
```
