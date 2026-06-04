# 知识索引

> 数仓领域知识的轻量索引。每条用一句话说清核心逻辑。
> 格式：- **触发关键词**: 一句话核心逻辑 → `相关表/作业/文件`（可选）

# SQL 模式库

> 详见 sql-patterns.md

- **去重保留最新**: ROW_NUMBER() OVER PARTITION BY pk ORDER BY update_time DESC → 见 sql-patterns.md §1
- **拉链表 SCD2**: 全量 LEFT JOIN 当日新增/变更，分别处理 close 旧链 + 开 新链 → 见 sql-patterns.md §2
- **同环比**: 自连接 / 时间窗口偏移；注意空值除零 → 见 sql-patterns.md §3
- **TopN 分组排名**: ROW_NUMBER / DENSE_RANK + QUALIFY（部分引擎）→ 见 sql-patterns.md §4
- **累计求和**: SUM() OVER (PARTITION BY .. ORDER BY ..) → 见 sql-patterns.md §5
- **行转列/列转行**: PIVOT/UNPIVOT 或 CASE WHEN + LATERAL VIEW EXPLODE → 见 sql-patterns.md §6

# ETL 模式库

> 详见 etl-patterns.md

- **CDC 增量同步**: 基于 binlog 位点的实时同步与幂等回放 → 见 etl-patterns.md §1
- **JDBC 增量抽取**: 基于 update_time 水位的批量抽取 → 见 etl-patterns.md §2
- **MERGE / UPSERT**: 基于主键的幂等写入 → 见 etl-patterns.md §3
- **小文件合并**: 输出端控制并发与文件大小 → 见 etl-patterns.md §4
- **历史回刷**: 分批回刷 + 进度跟踪 + 失败重试 → 见 etl-patterns.md §5

# 维度建模技巧

> 详见 dimension-modeling-tips.md

- **代理键 vs 业务键**: 代理键稳定、业务键追溯，建议双键并存 → 见 dimension-modeling-tips.md §1
- **缓慢变化维 SCD**: Type 1 覆盖 / Type 2 拉链 / Type 3 双列对照 → 见 dimension-modeling-tips.md §2
- **桥接表**: 解决多对多与多值维度 → 见 dimension-modeling-tips.md §3
- **退化维度**: 事实表内嵌业务键，避免低价值维度表 → 见 dimension-modeling-tips.md §4
- **一致性维度**: 跨主题复用，避免重复建设 → 见 dimension-modeling-tips.md §5
- **快照事实表**: 周期快照 vs 累积快照的选型 → 见 dimension-modeling-tips.md §6

# 性能优化技巧

> 详见 performance-tips.md

- **分区裁剪**: WHERE 条件直接命中分区字段，禁止函数包裹 → 见 performance-tips.md §1
- **数据倾斜**: 高频空值/默认值加盐打散，或拆分 SQL → 见 performance-tips.md §2
- **Map Join**: 小表广播加速 → 见 performance-tips.md §3
- **Broadcast 阈值**: 各引擎默认阈值与调参 → 见 performance-tips.md §3
- **小文件合并**: distribute by + reduce 数控制 → 见 performance-tips.md §4
- **CTE 物化**: 各引擎对 WITH 的物化策略差异 → 见 performance-tips.md §5

# 业务知识

（随实践积累补充：行业口径、公司内部 KPI 定义、跨系统对齐结论）

# 技术约定

（随实践积累补充：命名、分区、生命周期、调度时间窗）

# 踩坑记录

（随实践积累补充：每次 /archive 时沉淀，附原因与解决方案）
