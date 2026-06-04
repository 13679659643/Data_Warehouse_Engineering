---
alwaysApply: true
---

# 数据质量规范

> 数据质量（Data Quality, DQ）是数仓的生命线。所有上线作业必须配套 DQ 规则。

## 1. 质量五维度

| 维度 | 含义 | 典型规则 | 优先级 |
|------|------|---------|--------|
| **完整性** | 数据是否齐全、必填字段非空 | 非空率 ≥ 99.9% | P0 |
| **唯一性** | 主键 / 业务唯一键不重复 | 重复行数 = 0 | P0 |
| **一致性** | 跨表 / 跨系统对齐 | 行数差异 < 0.1% | P1 |
| **准确性** | 与真实业务数据匹配 | 与业务库直查对账误差 < 0.5% | P0 |
| **时效性** | 按时产出 | 产出时间 ≤ SLA 基线 | P1 |

## 2. 规则强制要求

### 每张表必须的 DQ
- [ ] **行数下限**：当日分区行数 ≥ 历史 P10 × 0.5（防止数据丢失）
- [ ] **行数上限**：当日分区行数 ≤ 历史 P95 × 3（防止数据膨胀）
- [ ] **主键唯一**：每张事实/维度表
- [ ] **关键字段非空**：核心业务字段（如 user_id、order_id、amt）

### 维度表额外规则
- [ ] **一致性维度跨表对齐**：dim_user 中 user_id 必须存在于上游业务库
- [ ] **拉链表无重叠**：同一业务键的有效区间不重叠

### 事实表额外规则
- [ ] **维度可关联**：外键能 100% 关联到维度表（缺失率 < 0.1%）
- [ ] **数值合理**：金额非负（除退款类）、数量非负、比率在 [0, 1] 或 [-1, 1]

## 3. DQ 规则模板

### 完整性
```sql
-- 关键字段非空率
SELECT
    COUNT(1)                                  AS total_cnt,
    COUNT(user_id)                            AS user_id_not_null_cnt,
    COUNT(user_id) / COUNT(1)                 AS user_id_not_null_rate
FROM dwh_dwd.dwd_trade_order_di
WHERE dt = '${bizdate}';
-- 期望：user_id_not_null_rate >= 0.999
```

### 唯一性
```sql
-- 主键唯一
SELECT COUNT(1) AS dup_cnt FROM (
    SELECT order_id, COUNT(1) AS cnt
    FROM dwh_dwd.dwd_trade_order_di
    WHERE dt = '${bizdate}'
    GROUP BY order_id
    HAVING COUNT(1) > 1
) t;
-- 期望：dup_cnt = 0
```

### 一致性（行数对齐）
```sql
-- 数仓 vs 业务库行数差异
WITH dwh_cnt AS (
    SELECT COUNT(1) AS cnt FROM dwh_dwd.dwd_trade_order_di WHERE dt = '${bizdate}'
),
src_cnt AS (
    -- 通过外部表 / 跨集群查询拉取业务库当日订单数
    SELECT cnt FROM ods_meta.business_src_count WHERE table_name = 'orders' AND dt = '${bizdate}'
)
SELECT
    dwh_cnt.cnt                              AS dwh,
    src_cnt.cnt                              AS src,
    ABS(dwh_cnt.cnt - src_cnt.cnt) / src_cnt.cnt AS diff_rate
FROM dwh_cnt CROSS JOIN src_cnt;
-- 期望：diff_rate < 0.001
```

### 准确性（指标对账）
```sql
-- 与基准来源对比关键指标
SELECT
    SUM(amt) AS dwh_amt,
    (SELECT amt FROM ops_meta.benchmark WHERE metric = 'gmv' AND dt = '${bizdate}') AS bench_amt
FROM dwh_dws.dws_sales_1d
WHERE dt = '${bizdate}';
-- 期望：ABS(dwh - bench) / bench < 0.005
```

### 时效性
```sql
-- 当日分区是否在基线前产出
SELECT
    MAX(modified_time) AS last_update,
    UNIX_TIMESTAMP(CONCAT(SUBSTR(dt, 1, 4), '-', SUBSTR(dt, 5, 2), '-', SUBSTR(dt, 7, 2), ' 06:00:00')) AS sla
FROM information_schema.partitions
WHERE table_schema = 'dwh_dws' AND table_name = 'dws_sales_1d' AND dt = '${bizdate}';
-- 期望：last_update <= sla
```

## 4. 规则严重等级

| 等级 | 行为 | 通知 |
|------|------|------|
| **P0 阻断** | DQ 失败 → 停下游 + 当前任务标记失败 | 短信 + 电话 |
| **P1 告警** | DQ 失败 → 下游继续运行，但需 24 小时内修复 | 短信 + IM |
| **P2 监控** | 仅记录，进入日报 | 邮件 / 日报 |

### 等级选择
- 主键唯一、行数下限、关键字段非空 → **P0**
- 行数上限、跨系统一致性、指标对账 → **P1**
- 字段值分布、典型值占比、长尾分析 → **P2**

## 5. DQ 规则上线流程

1. **设计**：在 spec 的"§9 数据质量规则（DQ）"中列明
2. **实现**：与作业 SQL 一同提交，统一存放 `dq/<schema>/<table>.sql`
3. **测试**：在测试环境跑 7 天确认阈值合理
4. **上线**：DQ 与作业同步上线，启用告警
5. **运营**：周度 review DQ 通过率，调整阈值

## 6. DQ 规则文件结构

推荐目录结构：
```
dq/
├── dwd/
│   ├── dwd_trade_order_di.sql       -- 单表所有 DQ 规则
│   └── ...
├── dws/
└── ads/
```

单文件示例（`dq/dwd/dwd_trade_order_di.sql`）：
```sql
-- ============================================
-- DQ 规则集：dwh_dwd.dwd_trade_order_di
-- 责任人：xxx
-- ============================================

-- [P0][完整性] user_id 非空率
SELECT 'user_id_not_null' AS rule_id,
       'P0' AS level,
       0.999 AS threshold,
       COUNT(user_id) / COUNT(1) AS metric
FROM dwh_dwd.dwd_trade_order_di
WHERE dt = '${bizdate}';

-- [P0][唯一性] order_id 主键唯一
SELECT 'order_id_unique' AS rule_id,
       'P0' AS level,
       0 AS threshold,
       COUNT(1) AS metric
FROM (
    SELECT order_id FROM dwh_dwd.dwd_trade_order_di
    WHERE dt = '${bizdate}'
    GROUP BY order_id HAVING COUNT(1) > 1
) t;

-- 更多规则...
```

## 7. DQ 历史趋势

- 维护 DQ 结果历史表 `ops_dq.dq_result`，每次执行追加结果
- 用于分析趋势 / 识别突变 / 评估治理效果

```sql
CREATE TABLE ops_dq.dq_result (
    rule_id    STRING,
    table_name STRING,
    level      STRING,
    threshold  DOUBLE,
    metric     DOUBLE,
    is_pass    BOOLEAN,
    run_time   TIMESTAMP,
    bizdate    STRING
)
PARTITIONED BY (dt STRING);
```

## 8. 反模式

- ❌ 仅在出问题后才补 DQ → 应该上线即配套
- ❌ 规则只有"通过/失败"二值 → 应该有数值趋势
- ❌ DQ 规则与业务变化不同步 → 业务变更时同步评审
- ❌ DQ 失败但下游继续运行 → P0 必须阻断
- ❌ DQ 规则集中在一个超大文件 → 应按表组织

## 9. 与业务方 SLA

- 核心 ADS 必须在 SLA 协议中明示 DQ 通过标准
- 月度向业务方提供 DQ 报告（通过率、Top 失败规则、改进措施）
