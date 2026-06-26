# Rules 索引

> 数仓开发强制约束规则清单。主 Skill 及 Subagent 按需读取对应规则文件。
> 所有规则文件源路径：`data_warehouse_engineering_code_copilot/rules/`

## 全量规则清单

| 规则文件 | 标题 | alwaysApply | 适用命令 | 核心约束摘要 |
|---------|------|-------------|---------|------------|
| `sql-style.md` | SQL 编码规范 | ✅ | /sql, /etl, /review | 命名约定（库/表/字段/分区）、格式规范（关键字大写/4空格缩进/头部注释）、SQL编写原则（性能优先/正确性优先/可维护性）、禁止事项（SELECT */INSERT INTO/硬编码日期/跨层引用） |
| `modeling-standards.md` | 数仓建模与分层规范 | ✅ | /model, /review | 五层架构（ODS/DWD/DWS/ADS/DIM）、维度建模（Kimball星型）、事实表设计（事务/快照/累积）、维度表设计（代理键+业务键/SCD2）、关系与关联、物理设计（分区/分桶/存储/生命周期）、度量值与指标分级 |
| `scheduling-standards.md` | 调度与运维规范 | ✅ | /schedule | 调度命名、依赖关系（强/弱）、调度周期、SLA与基线、重试与告警、资源队列、脚本规范、上线流程、监控与可观测、失败回放与回退 |
| `domain-rules.md` | 业务领域约束 | ❌ | /sql, /model, /dq | 金额DECIMAL(18,4)元、百分比保留1位、同环比口径、KPI定义标准、数据质量五维度、历史数据约定、行业特定规则（零售/金融/制造/互联网） |
| `project-context.md` | 数仓项目上下文 | ✅ | 启动时, /init | 项目概况、数据源清单、数仓分层与库、主题域、核心事实表、一致性维度、ADS表/报表、KPI字典、调度与基线、安全配置、已知技术债 |
| `security.md` | 安全红线 | ✅ | 涉及PII/财务/权限 | 数据安全6条红线、字段级脱敏标准（手机/身份证/邮箱/银行卡）、行级权限RLS、数据分级L1-L4、上线安全、回刷安全、业务安全、跨境合规、审计、应急响应 |
| `data-quality.md` | 数据质量规范 | ✅ | /dq | 五维度（完整性/唯一性/一致性/准确性/时效性）、规则强制要求（行数上下限/主键唯一/关键字段非空）、DQ规则模板SQL、严重等级P0-P2、上线流程、文件结构、反模式、SLA |

## 按命令推荐读取顺序

### /sql
1. `sql-style.md` — SQL 编码规范（必读）
2. `domain-rules.md` — 业务领域约束（按需）
3. `security.md` — 安全红线（涉及敏感数据时必读）

### /etl
1. `sql-style.md` — SQL 编码规范
2. `scheduling-standards.md` — 调度与运维规范
3. `security.md` — 安全红线

### /model
1. `modeling-standards.md` — 数仓建模与分层规范（必读）
2. `sql-style.md` — 命名约定
3. `domain-rules.md` — 业务领域约束
4. `project-context.md` — 项目上下文

### /review
1. `modeling-standards.md` — 模型合规审查依据
2. `sql-style.md` — SQL 审查依据
3. `domain-rules.md` — 业务规则审查依据
4. `security.md` — 安全审查依据

### /optimize
1. `sql-style.md` — 性能相关条款
2. `scheduling-standards.md` — 调度相关优化

### /dq
1. `data-quality.md` — 数据质量规范（必读）
2. `domain-rules.md` — 业务规则校验

### /schedule
1. `scheduling-standards.md` — 调度与运维规范（必读）
2. `security.md` — 权限相关

### /propose & /apply
1. `project-context.md` — 项目上下文
2. `modeling-standards.md` — 建模规范
3. `sql-style.md` — SQL 规范
4. `data-quality.md` — DQ 规则
