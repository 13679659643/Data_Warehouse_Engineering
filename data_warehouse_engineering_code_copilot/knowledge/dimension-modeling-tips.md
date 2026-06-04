# 维度建模技巧

> Kimball 维度建模在数仓中的落地经验：维度、事实、缓慢变化维、桥接、退化维度、一致性维度。

## 1. 代理键 vs 业务键

### 概念
- **业务键（Business / Natural Key）**：源系统中的标识（如 `order_no = 'NO20260601001'`）
- **代理键（Surrogate Key）**：数仓内自增/哈希/雪花 ID（如 `order_sk = 12345`）

### 推荐：双键并存
```sql
CREATE TABLE dwh_dim.dim_user (
    user_sk      BIGINT      COMMENT '代理键，数仓内自增/哈希',
    user_id      STRING      COMMENT '业务键，源系统 ID',
    name         STRING,
    level        STRING,
    start_date   STRING,
    end_date     STRING,
    is_current   BOOLEAN,
    PRIMARY KEY (user_sk) NOT ENFORCED
) ...;
```

### 选型建议
| 场景 | 用代理键 | 用业务键 |
|------|---------|---------|
| 拉链表 / SCD2 | ✅ 必用 | 配合使用 |
| 跨系统集成（同实体多源） | ✅ 推荐 | 仅追溯用 |
| 简单维度（系统内唯一稳定） | 可省 | ✅ 直接用 |
| 性能敏感 Join | ✅ 整数代理键 | 文本 ID 慢 |

### 踩坑
- ❌ 用业务键做拉链表的主键，导致历史版本无法区分
- ⚠️ 代理键生成必须保证幂等（哈希函数固定，或集中分配 ID）

---

## 2. 缓慢变化维（SCD）三种类型

### Type 1：覆盖（不保留历史）

适用场景：纠错型变更（如修正用户姓名拼写）。
```sql
-- 直接 UPDATE / 全量 INSERT OVERWRITE
INSERT OVERWRITE TABLE dwh_dim.dim_user
SELECT user_id, name, level, current_date AS update_date
FROM dwh_ods.ods_user_full WHERE dt = '${bizdate}';
```

### Type 2：拉链（保留完整历史）

适用场景：业务上需要追溯历史状态（如用户等级变化对历史订单的影响）。
```
user_id  level   start_date  end_date   is_current
1001     普通    20240101    20250630   FALSE
1001     金牌    20250701    20260315   FALSE
1001     钻石    20260316    99991231   TRUE
```

详见 sql-patterns.md §2 拉链表实现。

### Type 3：双列对照（保留前一版本）

适用场景：只关心"上一次"的状态（如组织架构调整对比）。
```sql
ALTER TABLE dim_dept ADD COLUMNS (
    dept_name_prev   STRING,
    change_date      STRING
);
```

### 选型对照
| 类型 | 历史完整性 | 存储开销 | Join 复杂度 | 适用场景 |
|------|----------|---------|-----------|---------|
| Type 1 | ❌ | 🟢 最小 | 🟢 简单 | 纠错、不关心历史 |
| Type 2 | ✅ 完整 | 🔴 大 | 🟡 需带时间 | 业务追溯 |
| Type 3 | 🟡 仅前一版本 | 🟢 小 | 🟢 简单 | 简单对比 |

### 踩坑
- ❌ 全部维度一刀切用 SCD2 → 模型膨胀，性能差
- ⚠️ SCD2 的 Join 必须带时间窗口：`fact.dt BETWEEN dim.start_date AND dim.end_date`

---

## 3. 桥接表（Bridge Table）

### 概念
解决"多对多"或"多值维度"问题（如一个客户多个标签、一份订单多个销售员）。

### 示例
```sql
-- 客户标签桥接表
CREATE TABLE dwh_dim.bridge_user_tag (
    user_sk     BIGINT,
    tag_sk      BIGINT,
    weight      DECIMAL(5,4) COMMENT '权重，分摊用',
    start_date  STRING,
    end_date    STRING
);
```

### 用法
```sql
-- 计算"持有 VIP 标签的用户的订单总额"
SELECT SUM(f.amt * b.weight) AS amt_vip
FROM dwh_dwd.dwd_order f
JOIN dwh_dim.bridge_user_tag b ON f.user_sk = b.user_sk
JOIN dwh_dim.dim_tag t ON b.tag_sk = t.tag_sk
WHERE t.tag_name = 'VIP'
  AND f.dt = '${bizdate}';
```

### 关键约定
- **权重字段**：决定是否做分摊（避免重复计算）
- **时间窗口**：标签可能随时间变化，必要时带 start_date / end_date
- **基数控制**：桥接表行数 = 用户数 × 平均标签数，注意爆炸

### 踩坑
- ❌ 不带权重直接 SUM，会重复计算订单金额
- ⚠️ 桥接表过大时考虑预计算成宽表

---

## 4. 退化维度（Degenerate Dimension）

### 概念
某些"维度属性"低基数 / 仅事实表内使用，不值得单独建维度表，直接退化为事实表内的列。

### 示例
```sql
-- 订单事实表中的退化维度
CREATE TABLE dwh_dwd.dwd_order (
    order_sk       BIGINT,
    user_sk        BIGINT,
    sku_sk         BIGINT,
    -- 退化维度（业务键，无独立维度表）
    order_no       STRING COMMENT '订单业务编号',
    pay_channel    STRING COMMENT '支付渠道，枚举少不建表',
    -- 度量
    amt            DECIMAL(18,4),
    qty            INT,
    -- 分区
    dt             STRING
);
```

### 适用场景
- 订单号、发票号、流水号（高基数但只在该事实表使用）
- 低基数枚举（支付方式、订单状态）—— 也可以作为简化维度但成本/收益不划算时退化

### 踩坑
- ❌ 把所有低基数枚举都退化 → 语义维护混乱、改一次值要改 N 张表
- ⚠️ 真正高复用的枚举（如订单状态在多个事实表都有）应该建 dim 表

---

## 5. 一致性维度（Conformed Dimension）

### 概念
跨主题/跨事实表共享的维度，避免重复建设。

### 典型例子
- `dim_date`：所有主题共享
- `dim_user`：会员、订单、行为都用同一张
- `dim_product`：商品中心化管理

### 实施要点
- **公共维度集中建设**：由数据底层团队负责，业务侧只读
- **物理化复用**：所有事实表外键直接关联同一张维度表
- **变更预警**：维度变更需要广播给所有下游主题

### 反模式
- ❌ 各主题各自维护一套 `dim_user_xxx`，造成 user_id 在不同主题口径不一致
- ⚠️ 一致性维度过度膨胀（一张表上百列）→ 拆分为核心维 + 扩展维

---

## 6. 事实表类型选择

| 类型 | 含义 | 典型粒度 | 适用场景 |
|------|------|---------|---------|
| **事务事实表** | 业务事件流水 | 单事件 | 订单、支付、点击 |
| **周期快照** | 等间隔的状态拍照 | 日/月 | 库存、账户余额 |
| **累积快照** | 流程多个里程碑的快照 | 单实例 | 订单全生命周期（下单→支付→发货→签收） |
| **无事实事实表** | 仅记录"事件发生" | 单事件 | 学生选课、客户问询 |

### 选型示例
```sql
-- 事务事实表（粒度：每笔订单）
dwh_dwd.dwd_trade_order_di

-- 周期快照（粒度：每用户每日的余额）
dwh_dwd.dwd_account_balance_1d

-- 累积快照（粒度：每个订单的整个生命周期）
dwh_dwd.dwd_order_lifecycle
-- 字段：create_time, pay_time, ship_time, sign_time, refund_time, current_status
```

### 踩坑
- ❌ 用事务事实表回答"截至 X 日的库存"问题 → 计算量爆炸
- ⚠️ 累积快照需要在状态变更时更新，注意幂等

---

## 7. 维度表分级

### 分级
- **核心维度（Core Dim）**：高复用、低变化（用户、商品、组织）
- **扩展维度（Extension Dim）**：仅特定主题使用（订单标签、风险评分）
- **杂项维度（Junk Dim）**：低基数标志位的组合（is_vip × is_new × source）

### 杂项维度示例
```sql
-- 把多个低基数标志组合成一张小维度
CREATE TABLE dwh_dim.dim_order_flag (
    flag_sk     INT,
    is_vip      BOOLEAN,
    is_new_buy  BOOLEAN,
    source_chl  STRING,
    PRIMARY KEY (flag_sk) NOT ENFORCED
);
-- 行数 = 各维度基数乘积，通常 < 1000
```

### 收益
- 事实表外键从 N 列降到 1 列
- 多维分析筛选更高效

---

## 8. 数仓分层归属判定

| 表类型 | 落在层 | 命名前缀 | 例子 |
|--------|-------|---------|------|
| 原始落地（保留源端字段，不加工） | ODS | ods_ | ods_mysql_orders_inc |
| 清洗 + 维度退化 + 业务过程 | DWD | dwd_ | dwd_trade_order_di |
| 轻度聚合（多维度组合） | DWS | dws_ | dws_user_order_1d |
| 应用层（指标 + 业务口径） | ADS | ads_ | ads_sales_dashboard_1d |
| 维度表 | DIM | dim_ | dim_user, dim_date |

### 判定原则
- **是否做了清洗 / 业务过程切分** → 进 DWD
- **是否按主题做了聚合** → 进 DWS
- **是否直接服务于报表 / API（指标级）** → 进 ADS
- **是否是描述性属性（不可加和）** → 进 DIM

### 反模式
- ❌ ADS 直接读 ODS（绕过 DWD/DWS） → 重复建设、口径分裂
- ❌ DWD 表里包含汇总指标 → 应该上提到 DWS
- ⚠️ DWS 横向爆炸（每个产品组都建一张 dws） → 公共聚合统一在共享 DWS
