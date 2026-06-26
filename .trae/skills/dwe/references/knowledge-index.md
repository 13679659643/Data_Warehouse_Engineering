# Knowledge 索引

> 数仓领域知识的轻量索引。每条用一句话说清核心逻辑。
> 所有知识文件源路径：`data_warehouse_engineering_code_copilot/knowledge/`

## 知识文件清单

| 知识文件 | 标题 | 适用命令 | 内容摘要 |
|---------|------|---------|---------|
| `index.md` | 知识索引 | 全局 | 轻量级关键词索引，快速定位模式 |
| `sql-patterns.md` | SQL 模式库 | /sql | 去重保留最新、拉链表SCD2、同环比、TopN分组排名、累计求和、行转列/列转行等6大类SQL模式 |
| `etl-patterns.md` | ETL 模式库 | /etl | CDC增量同步、JDBC增量抽取、MERGE/UPSERT、小文件合并、历史回刷等5大类ETL模式 |
| `dimension-modeling-tips.md` | 维度建模技巧 | /model | 代理键vs业务键、SCD Type1/2/3、桥接表、退化维度、一致性维度、快照事实表等6大建模技巧 |
| `performance-tips.md` | 性能优化技巧 | /optimize | 分区裁剪、数据倾斜、Map Join、Broadcast阈值、小文件合并、CTE物化等6大优化技巧 |

## 快速检索（关键词 → 知识文件）

### SQL 模式
- **去重保留最新**: ROW_NUMBER() OVER PARTITION BY pk ORDER BY update_time DESC → `sql-patterns.md` §1
- **拉链表 SCD2**: 全量 LEFT JOIN 当日新增/变更 → `sql-patterns.md` §2
- **同环比**: 自连接 / 时间窗口偏移；注意空值除零 → `sql-patterns.md` §3
- **TopN 分组排名**: ROW_NUMBER / DENSE_RANK + QUALIFY → `sql-patterns.md` §4
- **累计求和**: SUM() OVER (PARTITION BY .. ORDER BY ..) → `sql-patterns.md` §5
- **行转列/列转行**: PIVOT/UNPIVOT 或 CASE WHEN + LATERAL VIEW EXPLODE → `sql-patterns.md` §6

### ETL 模式
- **CDC 增量同步**: 基于 binlog 位点的实时同步与幂等回放 → `etl-patterns.md` §1
- **JDBC 增量抽取**: 基于 update_time 水位的批量抽取 → `etl-patterns.md` §2
- **MERGE / UPSERT**: 基于主键的幂等写入 → `etl-patterns.md` §3
- **小文件合并**: 输出端控制并发与文件大小 → `etl-patterns.md` §4
- **历史回刷**: 分批回刷 + 进度跟踪 + 失败重试 → `etl-patterns.md` §5

### 维度建模
- **代理键 vs 业务键**: 代理键稳定、业务键追溯，建议双键并存 → `dimension-modeling-tips.md` §1
- **缓慢变化维 SCD**: Type 1 覆盖 / Type 2 拉链 / Type 3 双列对照 → `dimension-modeling-tips.md` §2
- **桥接表**: 解决多对多与多值维度 → `dimension-modeling-tips.md` §3
- **退化维度**: 事实表内嵌业务键，避免低价值维度表 → `dimension-modeling-tips.md` §4
- **一致性维度**: 跨主题复用，避免重复建设 → `dimension-modeling-tips.md` §5
- **快照事实表**: 周期快照 vs 累积快照的选型 → `dimension-modeling-tips.md` §6

### 性能优化
- **分区裁剪**: WHERE 条件直接命中分区字段，禁止函数包裹 → `performance-tips.md` §1
- **数据倾斜**: 高频空值/默认值加盐打散，或拆分 SQL → `performance-tips.md` §2
- **Map Join**: 小表广播加速 → `performance-tips.md` §3
- **Broadcast 阈值**: 各引擎默认阈值与调参 → `performance-tips.md` §3
- **小文件合并**: distribute by + reduce 数控制 → `performance-tips.md` §4
- **CTE 物化**: 各引擎对 WITH 的物化策略差异 → `performance-tips.md` §5
