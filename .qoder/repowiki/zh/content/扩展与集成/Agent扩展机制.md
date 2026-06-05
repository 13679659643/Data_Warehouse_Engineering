# Agent扩展机制

<cite>
**本文档引用的文件**
- [目录结构和设计说明.md](file://目录结构和设计说明.md)
- [copilot-prompt.md](file://agents/copilot-prompt.md)
- [sql-reviewer.md](file://agents/sql-reviewer.md)
- [version-tracker.md](file://agents/version-tracker.md)
- [index.md](file://knowledge/index.md)
- [domain-rules.md](file://rules/domain-rules.md)
- [security.md](file://rules/security.md)
- [sql-style.md](file://rules/sql-style.md)
- [spec.md](file://changes/templates/spec.md)
- [tasks.md](file://changes/templates/tasks.md)
- [log.md](file://changes/templates/log.md)
</cite>

## 目录
1. [简介](#简介)
2. [项目结构](#项目结构)
3. [核心组件](#核心组件)
4. [架构概览](#架构概览)
5. [详细组件分析](#详细组件分析)
6. [依赖关系分析](#依赖关系分析)
7. [性能考虑](#性能考虑)
8. [故障排除指南](#故障排除指南)
9. [结论](#结论)
10. [附录](#附录)

## 简介

dwh-copilot是一个面向数据仓库开发场景的AI协作助手，采用"Spec驱动 + 三段式知识库 + 强制变更追踪"的设计理念。该项目通过精心设计的Agent机制，实现了数仓开发全流程的智能化协作，包括需求分析、模型设计、SQL编写、ETL开发、性能优化、数据质量检查等多个方面。

该系统的核心价值在于：
- **标准化流程**：通过严格的命令体系确保数仓开发的规范性和可追溯性
- **知识复用**：构建了完整的知识库体系，支持经验的沉淀和传承
- **强制审计**：所有变更都必须记录在案，确保可审计、可回溯
- **智能协作**：AI Agent能够理解复杂的数仓场景，提供专业的技术指导

## 项目结构

项目采用模块化设计，主要分为四个核心目录：

```mermaid
graph TB
subgraph "核心目录结构"
A[agents/] --> A1[主提示词 copilot-prompt.md]
A[agents/] --> A2[SQL审查器 sql-reviewer.md]
A[agents/] --> A3[版本追踪器 version-tracker.md]
B[changes/] --> B1[模板 templates/]
B1 --> B2[spec.md]
B1 --> B3[tasks.md]
B1 --> B4[log.md]
C[knowledge/] --> C1[知识索引 index.md]
C1 --> C2[SQL模式库]
C1 --> C3[ETL模式库]
C1 --> C4[建模技巧]
C1 --> C5[性能优化]
D[rules/] --> D1[领域规则 domain-rules.md]
D --> D2[安全规范 security.md]
D --> D3[SQL编码规范 sql-style.md]
end
```

**图表来源**
- [目录结构和设计说明.md:21-55](file://目录结构和设计说明.md#L21-L55)
- [目录结构和设计说明.md:186-193](file://目录结构和设计说明.md#L186-L193)

**章节来源**
- [目录结构和设计说明.md:19-55](file://目录结构和设计说明.md#L19-L55)

## 核心组件

### Agent架构设计原理

dwh-copilot的Agent架构基于以下核心设计原则：

#### 1. Spec驱动原则
- **核心理念**：需求文档（Spec）是昂贵的核心资产，SQL脚本和模型DDL都是可重建的消耗品
- **执行规则**：
  - No Spec, No Change（没有spec，不准改）
  - Spec is Truth（spec与实现冲突时，错的一定是实现）
  - Reverse Sync（发现偏差先改spec再改实现）
  - 变更即记录（任何变更必须更新changes/与changelog）

#### 2. 三段式知识结构
系统将知识分为三个层次：
- **rules/**：约束 - 必须遵守的"红线"（强制）
- **knowledge/**：经验 - 可复用的"工具箱"（推荐）
- **changes/**：过程 - 每次变更的"病历"（历史）

#### 3. 命令式协作
通过标准化的命令体系实现AI与用户的协作：
- `/init`：项目初始化
- `/sql`：SQL开发
- `/etl`：ETL开发
- `/model`：数仓建模
- `/propose`：创建变更提案
- `/apply`：实施变更
- `/review`：三阶段审查
- `/optimize`：性能优化
- `/dq`：数据质量检查
- `/schedule`：调度配置
- `/archive`：归档与知识沉淀

**章节来源**
- [目录结构和设计说明.md:59-106](file://目录结构和设计说明.md#L59-L106)
- [目录结构和设计说明.md:186-193](file://目录结构和设计说明.md#L186-L193)

## 架构概览

### Agent协作架构

```mermaid
graph TB
subgraph "用户交互层"
U[用户] --> C[命令解析器]
end
subgraph "Agent协调层"
C --> P[主提示词Agent]
P --> R[SQL审查Agent]
P --> V[版本追踪Agent]
P --> O[性能诊断Agent]
P --> Q[数据质量Agent]
end
subgraph "知识库层"
K1[规则库 rules/] --> P
K2[知识库 knowledge/] --> P
K3[变更库 changes/] --> P
end
subgraph "外部系统"
E[数据源] --> P
S[调度系统] --> P
T[监控系统] --> P
end
P --> O
P --> Q
P --> R
P --> V
```

**图表来源**
- [copilot-prompt.md:63-147](file://agents/copilot-prompt.md#L63-L147)
- [目录结构和设计说明.md:24-29](file://目录结构和设计说明.md#L24-L29)

### Agent生命周期管理

```mermaid
stateDiagram-v2
[*] --> 初始化
初始化 --> 命令识别
命令识别 --> 参数解析
参数解析 --> Agent执行
Agent执行 --> 状态检查
状态检查 --> 命令识别
Agent执行 --> 版本追踪
版本追踪 --> 命令识别
命令识别 --> [*] : 结束
state Agent执行 {
[*] --> 数据研究
数据研究 --> 方案设计
方案设计 --> 具体实现
具体实现 --> 验证方法
验证方法 --> 性能评估
性能评估 --> [*]
}
```

**图表来源**
- [copilot-prompt.md:65-136](file://agents/copilot-prompt.md#L65-L136)

## 详细组件分析

### 主提示词Agent（copilot-prompt.md）

主提示词Agent是整个系统的中枢，负责协调各个子Agent的工作。

#### 核心功能

1. **身份与原则**
   - 顶尖数仓工程师搭档
   - 用中文输出，技术术语保留英文
   - 不确定就问，不假设，不编造

2. **回答框架**
   每个回答必须包含七个结构化部分：
   - 问题理解
   - 现状分析
   - 方案设计
   - 具体实现
   - 验证方法
   - 性能与成本考量
   - 注意事项

3. **命令系统**
   - `/init`：初始化项目上下文
   - `/sql`：SQL开发
   - `/etl`：ETL开发
   - `/model`：数仓建模
   - `/propose`：创建变更提案
   - `/apply`：执行实施
   - `/review`：三阶段审查
   - `/optimize`：性能诊断
   - `/dq`：数据质量检查
   - `/schedule`：调度配置
   - `/archive`：归档与知识沉淀

#### 调试流程

```mermaid
flowchart TD
A[现象收集] --> B[根因定位]
B --> C[方案验证]
C --> D[实施修复]
E[数据源层] --> F[抽取层]
F --> G[数仓层]
G --> H[应用层]
E --> I[业务库结构变更]
E --> J[源表迟到/重复]
E --> K[事务边界问题]
F --> L[同步成功率]
F --> M[增量字段单调性]
F --> N[CDC binlog丢失]
G --> O[ODS层落表行数]
G --> P[DWD层业务过程]
G --> Q[DWS层聚合粒度]
G --> R[ADS层指标计算]
H --> S[下游BI/API二次聚合]
H --> T[时区/币种处理]
```

**图表来源**
- [copilot-prompt.md:133-147](file://agents/copilot-prompt.md#L133-L147)

**章节来源**
- [copilot-prompt.md:1-147](file://agents/copilot-prompt.md#L1-L147)

### SQL审查Agent（sql-reviewer.md）

SQL审查Agent专注于数仓SQL代码的质量、性能和可维护性审查。

#### 审查分级体系

```mermaid
graph LR
subgraph "审查级别"
A[Critical - 阻塞]
B[Important - 应修复]
C[Minor - 建议]
end
subgraph "Critical问题"
A1[计算结果错误]
A2[Join笛卡尔积]
A3[全表扫描]
A4[主键重复]
A5[数据回刷无幂等]
A6[跨库引用未声明]
end
subgraph "Important问题"
B1[子查询未使用CTE]
B2[重复计算未提取]
B3[字符串隐式类型转换]
B4[NULL处理缺失]
B5[分区裁剪阻断]
B6[WHERE条件位置不当]
end
subgraph "Minor问题"
C1[关键字大小写不统一]
C2[缩进/换行风格不一致]
C3[字段顺序不一致]
C4[可合并的多次INSERT]
end
A --> A1
A --> A2
A --> A3
A --> A4
A --> A5
A --> A6
B --> B1
B --> B2
B --> B3
B --> B4
B --> B5
B --> B6
C --> C1
C --> C2
C --> C3
C --> C4
```

**图表来源**
- [sql-reviewer.md:5-68](file://agents/sql-reviewer.md#L5-L68)

#### 性能审查清单

| 审查维度 | 检查要点 | 优化建议 |
|---------|---------|---------|
| 分区裁剪 | 大型分区表是否使用dt/ds/pt | 确保WHERE条件直接命中分区字段 |
| Join顺序 | 大表在前、小表在后 | 按引擎特性调整Join顺序 |
| 广播Join | 小表阈值判断 | 启用Map Join/Broadcast Join |
| 数据倾斜 | 高频空值/默认值处理 | 添加盐值或拆分SQL |
| 聚合下推 | 外层Group By优化 | 将聚合下推到子查询 |
| 字段选择 | SELECT *使用 | 明列字段减少扫描量 |

**章节来源**
- [sql-reviewer.md:1-68](file://agents/sql-reviewer.md#L1-L68)

### 版本追踪Agent（version-tracker.md）

版本追踪Agent负责在每次DDL/SQL/ETL/调度变更后自动记录结构化的变更条目。

#### 触发时机

```mermaid
sequenceDiagram
participant U as 用户
participant A as 主提示词Agent
participant S as 具体Agent
participant V as 版本追踪Agent
participant F as 变更日志文件
U->>A : 执行命令
A->>S : 调用具体Agent
S->>S : 执行具体操作
S->>V : 触发版本追踪
V->>V : 检查路径初始化
V->>F : 追加变更条目
F-->>V : 写入成功
V-->>A : 记录完成
A-->>U : 返回结果
```

**图表来源**
- [version-tracker.md:5-16](file://agents/version-tracker.md#L5-L16)

#### 变更条目格式

每次记录包含以下结构化信息：

```mermaid
graph TB
subgraph "变更条目结构"
A[时间戳] --> B[操作类型]
B --> C[一句话摘要]
C --> D[模块分类]
D --> E[分层信息]
E --> F[任务名称]
F --> G[操作类型]
G --> H[变更内容列表]
H --> I[关联文件]
I --> J[回刷范围]
J --> K[影响下游]
K --> L[备注说明]
end
```

**图表来源**
- [version-tracker.md:44-64](file://agents/version-tracker.md#L44-L64)

**章节来源**
- [version-tracker.md:1-120](file://agents/version-tracker.md#L1-L120)

### 知识库Agent群

#### 知识索引Agent（index.md）

知识索引Agent提供轻量级的知识检索功能，通过关键词快速定位相关知识内容。

##### 知识分类体系

```mermaid
graph TB
subgraph "知识库结构"
A[SQL模式库]
B[ETL模式库]
C[维度建模技巧]
D[性能优化技巧]
E[业务知识]
F[技术约定]
G[踩坑记录]
end
A --> A1[去重保留最新]
A --> A2[拉链表SCD2]
A --> A3[同环比计算]
A --> A4[TopN分组排名]
B --> B1[CDC增量同步]
B --> B2[JDBC增量抽取]
B --> B3[Merge/Upser]
B --> B4[小文件合并]
C --> C1[代理键vs业务键]
C --> C2[缓慢变化维SCD]
C --> C3[桥接表]
C --> C4[退化维度]
```

**图表来源**
- [index.md:6-48](file://knowledge/index.md#L6-L48)

**章节来源**
- [index.md:1-60](file://knowledge/index.md#L1-L60)

## 依赖关系分析

### Agent间协作关系

```mermaid
graph TB
subgraph "Agent协作关系"
P[主提示词Agent] --> S[SQL审查Agent]
P --> V[版本追踪Agent]
P --> K[知识库Agent群]
S --> R[规则库]
S --> K
V --> C[变更库]
V --> R
K --> R
K --> C
end
subgraph "外部依赖"
R --> R1[领域规则]
R --> R2[安全规范]
R --> R3[SQL规范]
C --> C1[Spec模板]
C --> C2[Tasks模板]
C --> C3[Log模板]
K --> K1[SQL模式]
K --> K2[ETL模式]
K --> K3[建模技巧]
K --> K4[性能优化]
end
```

**图表来源**
- [目录结构和设计说明.md:24-53](file://目录结构和设计说明.md#L24-L53)

### 数据流分析

```mermaid
flowchart LR
subgraph "输入数据流"
A[用户需求] --> B[命令解析]
B --> C[Agent选择]
C --> D[知识库检索]
D --> E[规则检查]
end
subgraph "处理流程"
E --> F[方案设计]
F --> G[具体实现]
G --> H[验证执行]
H --> I[性能评估]
end
subgraph "输出数据流"
I --> J[结果反馈]
J --> K[版本追踪]
K --> L[知识沉淀]
end
subgraph "外部系统"
M[数据源] --> E
N[调度系统] --> H
O[监控系统] --> I
end
```

**图表来源**
- [copilot-prompt.md:23-34](file://agents/copilot-prompt.md#L23-L34)

**章节来源**
- [目录结构和设计说明.md:109-123](file://目录结构和设计说明.md#L109-L123)

## 性能考虑

### Agent执行效率优化

1. **并行处理能力**
   - 多个Agent可以并行执行，提高整体响应速度
   - 知识库检索支持缓存机制，减少重复查询
   - 版本追踪采用异步写入，不影响主流程执行

2. **内存使用优化**
   - Agent状态管理采用轻量级数据结构
   - 知识库内容按需加载，避免内存溢出
   - 变更日志采用流式写入，控制内存占用

3. **网络通信优化**
   - Agent间通信采用本地进程间通信
   - 知识库访问支持本地文件系统缓存
   - 外部系统集成采用连接池管理

### 性能监控指标

| 指标类型 | 监控内容 | 阈值标准 |
|---------|---------|---------|
| 响应时间 | Agent平均响应时间 | < 5秒 |
| 并发处理 | 同时处理的Agent数量 | 支持10个以上 |
| 内存使用 | Agent内存占用峰值 | < 500MB |
| 磁盘IO | 版本追踪写入频率 | < 100次/分钟 |
| 网络延迟 | 外部系统调用延迟 | < 2秒 |

## 故障排除指南

### 常见问题诊断

#### Agent启动问题

```mermaid
flowchart TD
A[Agent启动失败] --> B{检查配置文件}
B --> |配置错误| C[修正配置]
B --> |文件缺失| D[创建缺失文件]
B --> |权限不足| E[修改文件权限]
C --> F[重启Agent]
D --> F
E --> F
F --> G{问题是否解决}
G --> |否| H[查看日志文件]
G --> |是| I[正常运行]
H --> J[分析错误信息]
J --> K[定位问题根源]
K --> L[修复问题]
```

#### 性能问题排查

```mermaid
flowchart TD
A[性能问题] --> B[收集性能指标]
B --> C[分析瓶颈环节]
C --> D[制定优化方案]
D --> E[实施优化措施]
E --> F[验证优化效果]
G[内存泄漏] --> H[GC日志分析]
G --> I[内存快照分析]
J[CPU占用过高] --> K[线程分析]
J --> L[热点代码定位]
M[磁盘IO瓶颈] --> N[文件系统监控]
M --> O[缓存命中率分析]
```

### 调试技巧

1. **日志分析**
   - 启用详细日志模式，记录Agent执行过程
   - 分析Agent间的调用关系和数据传递
   - 监控异常情况和错误堆栈信息

2. **性能分析**
   - 使用性能监控工具分析Agent执行时间
   - 分析内存使用情况和垃圾回收行为
   - 监控外部系统调用的响应时间

3. **集成测试**
   - 编写单元测试验证Agent功能
   - 进行集成测试验证Agent协作
   - 模拟异常情况测试容错能力

**章节来源**
- [copilot-prompt.md:133-147](file://agents/copilot-prompt.md#L133-L147)

## 结论

dwh-copilot的Agent扩展机制通过精心设计的架构和规范，实现了数仓开发全流程的智能化协作。该系统的主要优势包括：

1. **标准化流程**：严格的命令体系确保了数仓开发的规范性和一致性
2. **知识复用**：完整的知识库体系支持经验的沉淀和传承
3. **强制审计**：所有变更都必须记录在案，确保可审计、可回溯
4. **智能协作**：AI Agent能够理解复杂的数仓场景，提供专业的技术指导

对于新Agent的开发，建议遵循以下最佳实践：
- 明确Agent的职责边界和功能范围
- 设计清晰的接口定义和数据交换格式
- 实现完善的错误处理和异常恢复机制
- 提供详细的日志记录和性能监控
- 遵循系统的规范和约束要求

## 附录

### Agent开发规范

#### 接口定义规范

1. **输入参数规范**
   - 参数类型必须明确且一致
   - 提供参数验证和错误处理
   - 支持参数的默认值和可选性

2. **输出格式规范**
   - 统一的JSON/XML格式
   - 标准化的错误码和消息
   - 完整的状态信息和进度报告

3. **通信协议规范**
   - 支持同步和异步调用
   - 实现超时和重试机制
   - 提供心跳检测和健康检查

#### 集成流程规范

```mermaid
sequenceDiagram
participant Dev as 开发者
participant Test as 测试环境
participant Prod as 生产环境
Dev->>Test : 开发Agent
Test->>Test : 单元测试
Test->>Test : 集成测试
Test->>Prod : 部署Agent
Prod->>Prod : 功能验证
Prod->>Prod : 性能测试
Prod->>Prod : 正式上线
```

#### 生命周期管理

1. **开发阶段**
   - 需求分析和设计
   - 编码实现和单元测试
   - 代码审查和重构

2. **测试阶段**
   - 单元测试和集成测试
   - 性能测试和压力测试
   - 安全测试和合规检查

3. **部署阶段**
   - 环境准备和配置
   - 服务注册和发现
   - 监控和告警设置

4. **运维阶段**
   - 日常监控和维护
   - 性能优化和调优
   - 故障处理和恢复

### 最佳实践建议

1. **设计原则**
   - 单一职责原则：每个Agent专注于特定功能
   - 开闭原则：对扩展开放，对修改封闭
   - 依赖倒置原则：依赖抽象而非具体实现

2. **代码质量**
   - 代码注释和文档齐全
   - 异常处理和错误恢复完善
   - 性能优化和资源管理合理

3. **安全性**
   - 输入验证和参数过滤
   - 权限控制和访问限制
   - 数据加密和传输安全

4. **可维护性**
   - 代码结构清晰，易于理解和修改
   - 配置管理集中，便于维护
   - 日志记录完整，便于排查问题