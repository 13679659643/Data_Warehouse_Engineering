# StarRocks 建表语法规范

## 一、Key 列规范

### 1.1 顺序一致性
- **Key 列必须是表结构定义中的前 N 列**
- **Key 列的顺序必须与表结构定义中的顺序完全一致**
- **不允许跳过中间列**

```sql
-- ❌ 错误示例：brand 被跳过
DUPLICATE KEY(`id`, `record_id`, `sku`, `sales_date`)
-- 表结构中 brand 在 record_id 之后，sku 之前

-- ✅ 正确示例
DUPLICATE KEY(`id`, `record_id`, `brand`, `sku`, `sales_date`)
```

### 1.2 Key 列数量限制
| 数据模型 | Key 列限制 |
|---------|-----------|
| DUPLICATE KEY | 建议不超过 3 列（或受前缀索引长度限制）|
| AGGREGATE KEY | 同上 |
| UNIQUE KEY | 同上 |
| PRIMARY KEY | 同上 |

### 1.3 Key 列类型建议
- 优先使用 **整型**（`INT`、`BIGINT`）或 **定长字符串**（`VARCHAR` 较短）
- 避免在 Key 列使用大字段（`VARCHAR(65533)`、`TEXT` 等）
- `DATE`、`DATETIME` 可以作为 Key 列

---

## 二、副本数（replication_num）规范

### 2.1 基本规则
```
replication_num <= 可用 BE 节点数
```

### 2.2 环境配置建议
| 环境 | BE 节点数 | replication_num |
|-----|----------|----------------|
| 本地开发/单机测试 | 1 | 1 |
| 测试环境 | 1~2 | 1 |
| 生产环境（最小） | 3 | 3 |
| 生产环境（推荐） | >=3 | 3 |

### 2.3 查看 BE 节点状态
```sql
-- 查看所有 BE 节点
SHOW BACKENDS;

-- 或
SHOW PROC '/backends';
```
关注 `Alive = true` 的节点数量。

### 2.4 修改副本数
```sql
-- 修改表级别的默认副本数
ALTER TABLE table_name SET ("default.replication_num" = "1");

-- 修改已有分区的副本数
ALTER TABLE table_name MODIFY PARTITION partition_name SET ("replication_num" = "1");
```

---

## 三、列定义规范

### 3.1 列顺序建议
```
Key 列 -> 常用过滤列 -> 维度列 -> 度量列 -> 时间戳列 -> 技术字段
```

### 3.2 常用数据类型
| 类型 | 适用场景 |
|-----|---------|
| `BIGINT` | 主键、ID、计数 |
| `INT` | 状态码、小范围整数 |
| `VARCHAR(n)` | 字符串，n 尽量小 |
| `DATE` | 日期分区键 |
| `DATETIME` | 时间戳 |
| `DECIMAL(p,s)` | 金额，推荐 `DECIMAL(18,6)` |
| `BOOLEAN` | 是否标志 |

### 3.3 注释规范
- 每个字段必须添加 `COMMENT`
- 注释清晰说明字段含义、来源、特殊取值
- **COMMENT 字符串必须使用双引号 `"` 包裹，不要使用单引号 `'`**
- StarRocks 官方文档全部使用双引号 `"` 包裹注释内容
- **COMMENT 中避免使用中文括号 `（）` 和特殊符号（如 `°`）**，应使用英文括号 `()`

```sql
-- ❌ 错误：使用单引号
`id` BIGINT COMMENT '自增主键(来源ODS的id)'

-- ❌ 错误：使用中文括号
`brand` VARCHAR(20) COMMENT "品牌:361（DWD新增字段）"

-- ✅ 正确：使用双引号 + 英文括号
`id` BIGINT COMMENT "自增主键(来源ODS的id)"
`brand` VARCHAR(20) COMMENT "品牌:361(DWD新增字段)"
```

---

## 四、分区与分桶规范

### 4.1 分区（PARTITION）
```sql
-- 动态分区（推荐）
PARTITION BY RANGE(`sales_date`) ()
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-30",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "16",
    "dynamic_partition.history_partition_num" = "30"
)

-- 静态分区
PARTITION BY RANGE(`sales_date`) (
    PARTITION p202401 VALUES LESS THAN ("2024-02-01"),
    PARTITION p202402 VALUES LESS THAN ("2024-03-01")
)
```

### 4.2 分桶（DISTRIBUTED BY）
```sql
-- Hash 分桶（常用）
DISTRIBUTED BY HASH(`record_id`) BUCKETS 16

-- 分桶数建议
-- 单分区数据量 < 100万：BUCKETS 4~8
-- 单分区数据量 100万~1000万：BUCKETS 16~32
-- 单分区数据量 > 1000万：BUCKETS 64+
```

### 4.3 分桶键选择
- 选择 **高基数字段**（去重后值多），避免数据倾斜
- 选择 **查询常用过滤条件**，减少扫描范围
- 避免选择频繁更新的字段

---

## 五、PROPERTIES 常用配置详解

### 5.1 存储与副本

| 参数 | 说明 | 默认值 | 示例 |
|-----|------|--------|------|
| `replication_num` | 每个 Tablet 的副本数，必须 <= 可用 BE 节点数 | `3` | `"replication_num" = "1"` |
| `storage_medium` | 初始存储介质：`SSD` 或 `HDD` | 自动推断 | `"storage_medium" = "SSD"` |
| `storage_cooldown_time` | 数据从 SSD 自动迁移到 HDD 的绝对时间 | 无 | `"storage_cooldown_time" = "2025-12-31 00:00:00"` |
| `storage_cooldown_ttl` | 数据从 SSD 自动迁移到 HDD 的相对时间间隔 | 无 | `"storage_cooldown_ttl" = "7 DAY"` |
| `in_memory` | 是否将数据全部加载到内存（仅小表热数据） | `false` | `"in_memory" = "false"` |

### 5.2 压缩算法

| 参数 | 说明 | 默认值 | 可选值 |
|-----|------|--------|--------|
| `compression` | 数据压缩算法 | 无 | `LZ4` / `ZSTD` / `ZLIB` / `SNAPPY` |

- **LZ4**：压缩/解压速度最快，压缩比一般，适合追求查询性能的场景
- **ZSTD**：压缩比高，速度适中，适合存储敏感场景（可指定压缩级别 `zstd(3)`）
- **ZLIB**：压缩比最高，速度最慢
- **SNAPPY**：Google 出品，速度和压缩比均衡

```sql
-- 指定 ZSTD 压缩级别（1~22，默认 3，越大压缩比越高）
PROPERTIES ("compression" = "zstd(3)")
```

### 5.3 数据写入与复制模式

| 参数 | 说明 | 默认值 | 版本 |
|-----|------|--------|------|
| `replicated_storage` | 副本数据写入模式 | `true` (v3.0+) | v2.5+ |

- **`true`**（单 Leader 复制）：数据只写入主副本，其他副本从主副本同步。大幅降低 CPU 开销，推荐默认使用
- **`false`**（无 Leader 复制）：数据直接写入所有副本，CPU 开销随副本数倍增

### 5.4 快速 Schema 变更

| 参数 | 说明 | 默认值 | 版本 |
|-----|------|--------|------|
| `fast_schema_evolution` | 是否启用快速 Schema 变更 | `false` | v3.2+ (存算一体) / v3.3+ (存算分离默认 true) |

- 启用后，**加列/删列**速度更快，资源消耗更低
- **只能在建表时设置**，建表后无法通过 `ALTER TABLE` 修改
- 复杂类型（ARRAY/MAP/STRUCT）的默认值仅在 `fast_schema_evolution = true` 时支持

### 5.5 持久化索引（主键表专用）

| 参数 | 说明 | 默认值 | 版本 |
|-----|------|--------|------|
| `enable_persistent_index` | 主键表是否启用持久化索引 | `false` | v3.0+ |

- 启用后，主键索引持久化存储到磁盘，**降低内存占用**
- 主键表数据量大时强烈建议开启，避免 FE 内存不足
- 会有轻微的写入性能损耗

```sql
-- 主键表推荐配置
PRIMARY KEY(`id`)
PROPERTIES (
    "enable_persistent_index" = "true"
)
```

### 5.6 动态分区

| 参数 | 必填 | 说明 | 示例 |
|-----|------|------|------|
| `dynamic_partition.enable` | 否 | 是否启用动态分区 | `"true"` |
| `dynamic_partition.time_unit` | **是** | 分区时间粒度：`DAY`/`WEEK`/`MONTH` | `"DAY"` |
| `dynamic_partition.start` | 否 | 起始偏移（负数），过期分区自动删除 | `"-365"` |
| `dynamic_partition.end` | **是** | 结束偏移（正数），提前创建未来分区 | `"3"` |
| `dynamic_partition.prefix` | 否 | 分区名前缀 | `"p"` |
| `dynamic_partition.buckets` | 否 | 每个动态分区的分桶数 | `"16"` |
| `dynamic_partition.history_partition_num` | 否 | 建表时创建多少个历史分区 | `"365"` |
| `dynamic_partition.time_zone` | 否 | 动态分区时区 | `"Asia/Shanghai"` |
| `dynamic_partition.start_day_of_week` | 否 | WEEK 模式下每周第一天（1=周一，7=周日） | `"1"` |
| `dynamic_partition.start_day_of_month` | 否 | MONTH 模式下每月第一天（1~28） | `"1"` |
| `dynamic_partition.replication_num` | 否 | 动态分区的副本数，默认与表级 replication_num 一致 | `"1"` |

**工作原理**：
- 以当前时间为基准，自动创建 `[当前+end]` 个未来分区
- 自动删除早于 `[当前+start]` 的历史分区
- 分区名格式：`prefix + yyyyMMdd`（DAY）、`prefix + yyyy_ww`（WEEK）、`prefix + yyyyMM`（MONTH）

```sql
-- 示例：保留最近 365 天数据，提前创建未来 3 天分区，建表时创建 365 个历史分区
PROPERTIES (
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.buckets" = "16",
    "dynamic_partition.history_partition_num" = "365",
    "dynamic_partition.time_zone" = "Asia/Shanghai"
)
```

### 5.7 写入 Quorum（多副本场景）

| 参数 | 说明 | 默认值 |
|-----|------|--------|
| `write_quorum` | 数据加载成功所需的副本确认数 | `MAJORITY` |

- `MAJORITY`：多数副本写入成功即返回成功（默认，推荐）
- `ONE`：一个副本写入成功即返回（风险高，可能数据不可访问）
- `ALL`：所有副本写入成功才返回（最安全，但延迟高）

### 5.8 其他常用参数

| 参数 | 说明 | 默认值 |
|-----|------|--------|
| `storage_format` | 存储格式 | `DEFAULT` |
| `bloom_filter_columns` | 布隆过滤索引列，加速 `=` 和 `IN` 查询 | 无 |
| `colocate_with` | Colocate Join 组名，关联表同组分桶可免 Shuffle Join | 无 |
| `bucket_size` | 随机分桶的桶大小（字节），v3.2+ 支持按需动态增桶 | 无 |

---

## 六、完整规范示例

### 6.1 PRIMARY KEY 模型（单副本，参考你的格式）

```sql
CREATE TABLE `a_upc` (
  `id` int(11) NOT NULL COMMENT "",
  `upc` varchar(192) NULL COMMENT ""
) ENGINE=OLAP 
PRIMARY KEY(`id`)
DISTRIBUTED BY HASH(`id`)
PROPERTIES (
"compression" = "LZ4",
"enable_persistent_index" = "true",
"fast_schema_evolution" = "true",
"replicated_storage" = "true",
"replication_num" = "1"
);
```

### 6.2 DUPLICATE KEY 模型（明细表，动态分区）

```sql
DROP TABLE IF EXISTS feishu_dwd.dwd_feishu_sales_361_d;

CREATE TABLE IF NOT EXISTS feishu_dwd.dwd_feishu_sales_361_d (
    -- 1. Key 列（前 N 列，顺序与 DUPLICATE KEY 一致）
    `id`              BIGINT          COMMENT "自增主键(来源ODS的id)",
    `record_id`       VARCHAR(64)     COMMENT "飞书记录唯一ID(去重依据)",
    `brand`           VARCHAR(20)     COMMENT "品牌:361(DWD新增字段)",
    `sku`             VARCHAR(64)     COMMENT "SKU编码",
    `sales_date`      DATE            COMMENT "销售日期(分区键)",
    -- 2. 度量列：4个渠道的销量（件/双，整数类型）
    `qty_361sport`    BIGINT          COMMENT "361sport渠道销量",
    `qty_china`       BIGINT          COMMENT "中国公司(361客户)渠道销量",
    `qty_sample`      BIGINT          COMMENT "361寄样渠道销量",
    `qty_staff_hk`    BIGINT          COMMENT "员工内购(香港)渠道销量",
    -- 3. 度量列：4个渠道的金额（元，保留6位小数）
    `amt_361sport`    DECIMAL(18,6)   COMMENT "361sport渠道金额",
    `amt_china`       DECIMAL(18,6)   COMMENT "中国公司(361客户)渠道金额",
    `amt_sample`      DECIMAL(18,6)   COMMENT "361寄样渠道金额",
    `amt_staff_hk`    DECIMAL(18,6)   COMMENT "员工内购(香港)渠道金额",
    -- 4. 技术字段
    `sync_time`       DATETIME        COMMENT "ODS同步时间",
    `insert_date`     DATETIME        COMMENT "DWD记录插入时间(ETL写入,增量更新用)",
    `update_date`     DATETIME        COMMENT "DWD记录更新时间(ETL写入,增量更新用)"
) ENGINE=OLAP
DUPLICATE KEY(`id`, `record_id`, `brand`, `sku`, `sales_date`)
COMMENT "DWD层-361品牌销售日明细表(50张分表合并,日刷新)"
PARTITION BY RANGE(`sales_date`) ()
DISTRIBUTED BY HASH(`record_id`) BUCKETS 16
PROPERTIES (
    "replication_num" = "1",
    "compression" = "LZ4",
    "in_memory" = "false",
    "storage_format" = "DEFAULT",
    "dynamic_partition.enable" = "true",
    "dynamic_partition.time_unit" = "DAY",
    "dynamic_partition.start" = "-365",
    "dynamic_partition.end" = "3",
    "dynamic_partition.prefix" = "p",
    "dynamic_partition.history_partition_num" = "365"
);
```

---

## 七、常见错误速查

| 错误信息 | 原因 | 解决 |
|---------|------|------|
| `Key columns must be the first few columns` | Key 列不是前 N 列 / 顺序不一致 | 调整列顺序或 Key 定义 |
| `Table replication num should be less than or equal to the number of available BE nodes` | 副本数 > 可用 BE 数 | 降低 replication_num 或扩容 BE |
| `Duplicate key column should not be float or double` | Key 列使用了浮点型 | 改用 DECIMAL 或整型 |
| `The partition column must be key column` | 分区列不是 Key 列 | 将分区列加入 Key |
| `Failed to create partition. Timeout` | BE 节点不足或状态异常 | 检查 BE 状态，调整副本数 |
| `Distribution column not found` | 分桶键不存在 | 检查分桶键拼写，确保在列定义中 |
| `Unknown properties: {dynamic_partition.create_history_partition=true}` | 使用了不存在的动态分区参数 | 改为 `dynamic_partition.history_partition_num` |
| `Unexpected input '自增主键'` | COMMENT 使用了单引号 `'` 或中文括号 `（）` | 改用双引号 `"` 包裹注释，使用英文括号 `()` |

## 八、StarRocks 规范与最佳实践 总结

### 1. 数据类型与转换规范
- **BIGINT（整数型）**：是“8字节整数类型”，且**默认自带“有符号（能存负数）”属性**。在 ETL 中用于平替 MySQL 的 `CAST(... AS SIGNED)`，既能安全存储负数（如库存差异、补货修正），又符合 StarRocks 标准语法。
- **DECIMAL（高精度数值）**：金额（如吊牌价、回款价）和比值（如折扣、达成率）统一使用 `DECIMAL(18,6)`，保留 6 位小数以确保财务与指标计算的精度。
- **DATE / DATETIME（时间型）**：日期类字段使用 `DATE()` 函数截断时间部分；系统同步时间等需要精确到秒的字段使用 `DATETIME`。

### 2. 主键与表模型规范（PRIMARY KEY 模型）
- **主键位置**：在 `PRIMARY KEY` 模型中，作为业务主键的列（如 `sku`）**必须定义在表结构的前 N 列**。
- **更新机制**：`PRIMARY KEY` 模型原生支持按主键进行 Upsert（更新/插入），非常适合日刷新的 DWD 维表或状态流水表。
- **分桶策略**：使用 `DISTRIBUTED BY HASH(主键)`，确保同一个 SKU 的数据路由到同一个 Tablet，最大化主键更新和点查的性能。

### 3. 表属性与存储优化规范（PROPERTIES）
- **持久化索引**：`"enable_persistent_index" = "true"` 是 `PRIMARY KEY` 模型的专属核心优化，将主键索引持久化到磁盘，大幅降低内存占用并提升导入性能。
- **压缩算法**：`"compression" = "LZ4"`，在压缩比和 CPU 解压性能之间取得最佳平衡，是 OLAP 场景的默认推荐。
- **Schema 演进**：`"fast_schema_evolution" = "true"`，开启后支持轻量级的加减列操作，无需重写底层数据文件。

### 4. 数据清洗与空值处理规范（ETL 逻辑）
- **字符串空值兜底**：使用 `COALESCE(NULLIF(TRIM(col), ''), 'None')` 组合，同时处理 `NULL`、纯空格和空字符串，赋予统一的默认值（如 `'None'`）。
- **数值空值兜底**：使用 `COALESCE(CAST(... AS BIGINT/DECIMAL), 0)`，确保数值计算时不会因为 `NULL` 导致整个表达式结果变为 `NULL`。
- **日期空值兜底**：使用 `COALESCE(DATE(...), DATE('1970-01-01'))` 赋予极小默认日期，防止下游 BI 工具因 `NULL` 日期报错。
- **主备字段容错**：在 `WHERE` 过滤和主键取值时，使用 `COALESCE(NULLIF(SKU), NULLIF(SKU1))` 实现“主字段为空则降级取备用字段”，避免使用 `AND` 导致误杀有效数据。

### 5. SQL 编写与命名规范
- **显式指定列名与别名**：`INSERT INTO` 必须显式写出目标列名；`SELECT` 子句中必须为每个字段显式指定 `AS alias`。这能防止源表或目标表字段顺序变更导致的数据错位（Data Shift）。
- **特殊字符转义**：ODS 层源自飞书/Excel 的中文或带全角/半角括号的字段名（如 **`实际销售价（$）`**、**`订货数量(sku)`**），在 SQL 中**必须使用反引号（`` ` ``）严格包裹**，防止解析报错。
- **DWD 命名规范**：DWD 层字段统一摒弃中文和特殊符号，采用英文 `snake_case`（下划线命名法），提升下游查询的兼容性和书写体验。

 
