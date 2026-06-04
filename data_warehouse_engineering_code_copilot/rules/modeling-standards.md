---
alwaysApply: true
---

# 数仓建模与分层规范

## 1. 分层架构

### 标准分层
```
                      ┌────────────────────┐
                      │   ADS（应用层）    │  ← BI / API 直接消费
                      │  指标 + 业务口径    │
                      └─────────▲──────────┘
                                │
                      ┌────────────────────┐
                      │   DWS（汇总层）    │  ← 主题域轻度聚合
                      │  多维聚合，可加和   │
                      └─────────▲──────────┘
                                │
                      ┌────────────────────┐    ┌────────────────────┐
                      │   DWD（明细层）    │ ←→ │   DIM（维度层）    │
                      │  清洗 + 业务过程    │    │  一致性维度共享    │
                      └─────────▲──────────┘    └────────────────────┘
                                │
                      ┌────────────────────┐
                      │   ODS（贴源层）    │  ← 源系统镜像 / CDC
                      │  原始落地不加工     │
                      └─────────▲──────────┘
                                │
                      ┌────────────────────┐
                      │   数据源（业务库）  │
                      └────────────────────┘
```

### 分层职责

| 层 | 职责 | 是否对外 | 生命周期 |
|----|------|---------|---------|
| **ODS** | 原始落地，保留源端字段，不做加工 | ❌ 不直接对业务 | 增量永久 / 全量短期 |
| **DWD** | 业务过程切分，清洗、维度退化、关联维度 | ❌ 一般不直接对业务 | 永久 |
| **DIM** | 一致性维度，跨主题复用 | ✅ 可被 DWD/DWS 关联 | 永久 |
| **DWS** | 主题域轻度聚合，可加和指标 | ✅ 可对外（开发/分析师） | 永久 |
| **ADS** | 业务口径完整指标，直接服务报表 / API | ✅ 直接对业务 | 永久 |
| **mid_/tmp_** | 中间过渡 / 探索 | ❌ 内部 | 短期（7-30 天） |

---

## 2. 模型架构

### 维度建模优先（Kimball）
- 所有面向分析的模型必须基于**星型模型**（Star Schema）
- **事实表**（Fact）：可度量的业务事件
- **维度表**（Dim）：描述性属性
- 仅在维度有强层级 / 强复用 / 强治理需要时使用**雪花型**（需说明原因）

### 表类型标识
```
ods_xxx       — 贴源层
dwd_xxx_di    — 明细事实表（天增量）
dwd_xxx_da    — 累积快照
dws_xxx_1d    — 主题汇总（天）
ads_xxx       — 应用层指标
dim_xxx       — 维度表
dim_xxx_zip   — 拉链维度（SCD2）
bridge_xxx    — 桥接表
tmp_xxx       — 临时表
mid_xxx       — 中间表
```

---

## 3. 事实表设计

### 设计原则
- 只保留外键、退化维度（业务键）、度量值
- 描述性属性不冗余到事实表（除非必要的查询性能优化）
- 大型事实表必须按 `dt` 分区
- 事务事实表 `_di` 与累积快照 `_da` 严格区分

### 类型选择
| 类型 | 命名 | 粒度 | 写入方式 |
|------|------|------|---------|
| 事务事实表 | `dwd_xxx_di` | 单事件 | INSERT OVERWRITE 当日分区 |
| 周期快照 | `dwd_xxx_1d` | 实体 × 周期 | INSERT OVERWRITE 当日分区 |
| 累积快照 | `dwd_xxx_da` | 单实体（订单生命周期） | MERGE / 全量重写 |
| 无事实事实表 | `dwd_xxx_di` | 单事件（无金额） | INSERT OVERWRITE 当日分区 |

### 标准字段（事实表）
```sql
CREATE TABLE dwh_dwd.dwd_trade_order_di (
    -- 业务键
    order_id           STRING       COMMENT '订单业务编号',
    -- 外键（关联维度）
    user_sk            BIGINT       COMMENT '用户代理键',
    sku_sk             BIGINT       COMMENT 'SKU 代理键',
    shop_sk            BIGINT       COMMENT '店铺代理键',
    -- 退化维度
    pay_channel        STRING       COMMENT '支付渠道',
    order_status       STRING       COMMENT '订单状态',
    -- 度量值
    qty                BIGINT       COMMENT '商品数量',
    amt                DECIMAL(18,4) COMMENT '订单金额（元）',
    discount_amt       DECIMAL(18,4) COMMENT '优惠金额（元）',
    -- 元信息
    create_time        TIMESTAMP    COMMENT '订单创建时间',
    update_time        TIMESTAMP    COMMENT '最近更新时间',
    etl_time           TIMESTAMP    COMMENT '入仓时间'
)
COMMENT '订单交易明细（天增量）'
PARTITIONED BY (dt STRING COMMENT 'YYYYMMDD，按订单创建日落表')
STORED AS ORC
TBLPROPERTIES ('orc.compress' = 'ZSTD', 'lifecycle' = '3650');
```

---

## 4. 维度表设计

### 设计原则
- **代理键**（surrogate key）+ **业务键**（business key）双键并存
- 包含所有描述性属性
- 拉链表（SCD2）必须有 `start_date / end_date / is_current`
- 小型维度表使用全量快照即可，无需拉链

### 标准字段（维度表）
```sql
CREATE TABLE dwh_dim.dim_user_zip (
    user_sk        BIGINT      COMMENT '用户代理键',
    user_id        STRING      COMMENT '业务键',
    user_name      STRING      COMMENT '用户名',
    level          STRING      COMMENT '会员等级',
    register_date  STRING      COMMENT '注册日期',
    -- SCD2 标记字段
    start_date     STRING      COMMENT '版本生效日期 YYYYMMDD',
    end_date       STRING      COMMENT '版本失效日期，最新版本为 99991231',
    is_current     BOOLEAN     COMMENT '是否当前版本',
    -- 元信息
    etl_time       TIMESTAMP   COMMENT '入仓时间'
)
COMMENT '用户拉链维度表（SCD2）';
```

### 必须的维度表
- **dim_date**：日期维度，覆盖未来 5-10 年；包含年/季/月/周/日属性，财年标记，节假日，工作日标记
- **dim_user**：用户主维度（按需选 SCD1 / SCD2）
- **dim_org**：组织架构（通常 SCD2）

---

## 5. 关系与关联

### 关联约定
- 事实表外键 = 维度表代理键（性能 + 历史一致性）
- 拉链维度的关联必须带时间窗口：
  ```sql
  ON f.user_id = u.user_id
 AND f.biz_date BETWEEN u.start_date AND u.end_date
  ```
- 默认 LEFT JOIN（避免维度缺失导致事实丢失）
- INNER JOIN 仅在业务上要求"必须有维度"时使用

### 禁止的依赖
- ❌ 跨层反向：DWD 不能读 DWS / ADS
- ❌ 跨层跳跃：ADS 不能直接读 ODS
- ❌ 循环依赖：A → B → A
- ❌ 跨主题强耦合（DWS_topic1 直接读 DWS_topic2）

---

## 6. 物理设计

### 分区
- 主分区统一 `dt STRING`（YYYYMMDD）
- 二级分区按需（`dh STRING` 小时 / `region STRING` 地域）
- 单表分区数建议 ≤ 5000（HDFS NameNode 压力）

### 分桶（可选）
- 大表 Join 同一主键时启用，桶数为 2 的幂（128 / 256 / 512）
- 两侧表的桶数相同 + 桶字段相同 → Bucket Join

### 存储格式
- 大表：**ORC**（Hive）/ **Parquet**（Spark / Iceberg）
- 压缩：**ZSTD** 优先，否则 Snappy
- 临时表：Parquet + Snappy

### 生命周期
- ODS 增量分区：永久（或按法规要求）
- DWD：永久
- DWS / ADS：永久
- mid_/tmp_：30 天
- 调试 / 探索：7 天

---

## 7. 度量值与指标

### 指标分级
| 级别 | 命名 | 说明 |
|------|------|------|
| 原子指标 | `*_amt`, `*_cnt`, `*_qty` | 不可拆分（如 销售额） |
| 派生指标 | `*_rate`, `*_pct`, `avg_*` | 原子指标的运算（如 客单价） |
| 复合指标 | `kpi_*` | 多原子+派生组合（如 GMV / 净利率） |

### 跨表口径对齐
- 同名指标在不同表中**口径必须一致**
- 出现差异必须改名（例：`gmv` vs `gmv_excl_refund`）
- 一致性指标定义集中在 rules/domain-rules.md

---

## 8. 禁止事项

- ❌ 禁止使用自动日期表 / 系统隐藏维度
- ❌ 禁止事实表之间直接 JOIN（必须经维度桥接或在 DWS/ADS 层做）
- ❌ 禁止多对多关系不通过桥接表
- ❌ 禁止在模型中保留未使用的表或列
- ❌ 禁止在 DWD 层做主题汇总（应该上提到 DWS）
- ❌ 禁止在 DWS 层做业务口径加工（应该上提到 ADS）
- ❌ 禁止在 ADS 层做底层清洗（应该回到 DWD）

---

## 9. 模型评审清单

新建 / 变更模型前必须自查：

- [ ] 表名前缀符合分层规范
- [ ] 表名包含粒度后缀
- [ ] 业务过程清晰（一个事实表只表达一个业务过程）
- [ ] 主键 / 外键命名规范
- [ ] 分区字段为 `dt STRING`
- [ ] 字段类型最小化（不滥用 BIGINT / STRING）
- [ ] 金额字段为 DECIMAL，精度合理
- [ ] 字段全部有 COMMENT
- [ ] 表有 COMMENT 描述用途
- [ ] 配置了生命周期（lifecycle）
- [ ] 选择了合适的存储格式与压缩
- [ ] 分层归属正确（不跨层）
- [ ] 维度复用一致性维度，未重复建设
- [ ] 已声明上下游依赖
