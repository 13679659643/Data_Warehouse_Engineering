# Spec — dwe-copilot 落地为 Qoder Skill + Subagent

> status: **approved**（已实施落地，T1-T4 全部完成）
> created: 2026-06-04
> owner: 辜涛
> complexity: 🟡 中等
> type: 工程化落地（将既有 prompt 资产 → Qoder Skill / Subagent / 自然语言入口）

---

## 1. 背景与目标

### 1.1 背景
当前项目已沉淀完整的 dwh-copilot 提示词资产（位于 `data_warehouse_engineering_code_copilot/` 下），包含：
- `agents/copilot-prompt.md` 主提示词与 11 个命令（/sql /etl /model /propose /apply /review /optimize /dq /schedule /archive /init）
- `agents/{sql,model,performance}-reviewer.md`、`agents/version-tracker.md` 4 个专职审查/追踪 Agent
- `rules/`、`knowledge/`、`changes/templates/` 三段式规范与知识体系

但当前形式只是 Markdown 文档，**用户必须手工把内容复制粘贴**给 AI 才能生效，无法在 Qoder / IDE 插件 / CLI / 自然对话 多种环境下统一调用。

### 1.2 目标
把整套提示词资产**工程化落地**为：
- **1 个主 Skill `/dwe`** — 用户唯一入口，统一受理所有数仓开发请求
- **4 个 Subagent** — 由主 Skill 在适当节点**自动调度**，无需用户手工切换
- **自然语言可达** — 不依赖 `/dwe` 前缀，识别"帮我写个 SQL"等自然语言后自动路由
- **多环境兼容** — Qoder / Cursor / Cline / Claude Code 等支持 Skill+Subagent 的环境通用

### 1.3 验收标准（可观察）
- [ ] 用户在任意会话输入 `/dwe sql 计算月度 GMV`，主 Skill 接管，按 sql-style 规范输出 SQL + 验证 + 性能评估，并自动调用 version-tracker 追加变更日志
- [ ] 用户输入"帮我审一下昨天写的 dws_sales_1d.sql"，主 Skill 识别意图为 `/review`，依次调度 model-reviewer → sql-reviewer，输出三阶段审查报告
- [ ] 用户输入"看看为什么这个作业跑得这么慢"，主 Skill 识别为 `/optimize`，调度 performance-reviewer 输出五层诊断与优化路线图
- [ ] 在 Qoder 中通过 `.qoder/skills/dwe/` + `.qoder/agents/*.md` 自动加载，重启 IDE 后即时生效
- [ ] 同一份 spec/资产可拷贝到 `~/.claude/agents/`、`.cursor/rules/` 等目录后行为一致

---

## 2. 现状分析

### 2.1 现有资产清单

| 路径 | 角色 | 适配方向 |
|------|------|---------|
| `agents/copilot-prompt.md` | 主提示词（身份、法则、命令、调试流程） | → 主 Skill `dwe/SKILL.md` |
| `agents/sql-reviewer.md` | SQL 质量审查 | → Subagent `sql-reviewer` |
| `agents/model-reviewer.md` | 模型/Spec 合规审查 | → Subagent `model-reviewer` |
| `agents/performance-reviewer.md` | 性能诊断 | → Subagent `performance-reviewer` |
| `agents/version-tracker.md` | 变更日志追踪 | → Subagent `version-tracker` |
| `rules/*.md` | 强制约束 | 保持原位 + 由主 Skill 引用 |
| `knowledge/*.md` | 模式/经验库 | 保持原位 + 由主 Skill / Subagent 按需引用 |
| `changes/templates/*.md` | 变更管理模板 | 保持原位 + /propose /apply 时复制实例化 |

### 2.2 多环境差异

| 环境 | Skill 目录 | Subagent 目录 | 命令前缀 | 自然语言 |
|------|-----------|--------------|---------|---------|
| Qoder | `.qoder/skills/<name>/SKILL.md` | `.qoder/agents/<name>.md` | `/<name>` | 主 Skill 自识别 |
| Claude Code | `~/.claude/skills/<name>/SKILL.md` 或项目 `.claude/skills/` | `~/.claude/agents/<name>.md` | `/<name>` | 主 Skill 自识别 |
| Cursor | `.cursor/rules/<name>.mdc` | （无原生 subagent，靠 rules 复合） | `@<name>` | rules alwaysApply |
| Cline / Continue | `.clinerules` / 项目 rules | （无原生 subagent） | `@<name>` | rules 触发 |

**结论**：以 Qoder + Claude Code 的 Skill+Subagent 双层结构为主蓝本，Cursor/Cline 通过将 Subagent 内容内联到主 Skill 末尾实现降级兼容。

---

## 3. 总体架构

### 3.1 调用拓扑

```
                          用户输入
                  （命令 /dwe ... 或 自然语言）
                              │
                              ▼
                    ┌──────────────────────┐
                    │   主 Skill：/dwe     │
                    │   (SKILL.md)         │
                    │  - 意图识别 / 路由     │
                    │  - 加载 rules/*       │
                    │  - 命令分派          │
                    └──────────┬───────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        ▼                      ▼                      ▼
 ┌─────────────┐      ┌──────────────┐      ┌─────────────────┐
 │   命令族 A   │      │   命令族 B    │      │   归档族         │
 │ /sql /etl   │      │ /review      │      │ /archive        │
 │ /model      │      │ /optimize    │      │                 │
 │ /propose    │      │ /dq          │      │                 │
 │ /apply      │      │ /schedule    │      │                 │
 │ /init       │      │              │      │                 │
 └──────┬──────┘      └──────┬───────┘      └────────┬────────┘
        │                    │                       │
        │  完成后自动触发        │  按阶段串行调度        │  按需调度
        ▼                    ▼                       ▼
 ┌──────────────────────────────────────────────────────────┐
 │                      Subagent 池                          │
 │  ┌────────────┐  ┌────────────┐  ┌────────────────┐  ┌──┐│
 │  │ version-   │  │ model-     │  │ sql-reviewer   │  │p ││
 │  │ tracker    │  │ reviewer   │  │                │  │e ││
 │  │ (写日志)    │  │ (合规审查) │  │ (SQL质量)      │  │r ││
 │  └────────────┘  └────────────┘  └────────────────┘  └──┘│
 └──────────────────────────────────────────────────────────┘
```

### 3.2 调度时机矩阵（**关键**）

| 命令 / 触发场景 | 同步调用 Subagent | 调度顺序 | 是否阻塞 |
|----------------|-----------------|---------|---------|
| `/sql` 输出后 | version-tracker | 后置 | 否（异步追加日志） |
| `/etl` 输出后 | version-tracker | 后置 | 否 |
| `/model` 输出后 | version-tracker | 后置 | 否 |
| `/apply` 每个 Task 完成 | version-tracker | 后置 | 否 |
| `/schedule` 输出后 | version-tracker | 后置 | 否 |
| `/dq` 产出新规则后 | version-tracker | 后置 | 否 |
| `/review <change>` | model-reviewer → sql-reviewer | **串行**，前者通过才进后者 | 是 |
| `/review` Spec 阶段 | （主 Skill 内嵌完成 Spec Compliance 阶段） | 阶段一 | 是 |
| `/optimize` | performance-reviewer | 直接调度 | 是 |
| `/archive` 结束 | version-tracker | 后置 | 否 |
| 用户首次任意写操作 | version-tracker（路径初始化询问） | 一次性 | 是 |

### 3.3 自然语言 → 命令路由

主 Skill 在 SKILL.md 中保留意图识别表（沿用 copilot-prompt.md 中现有映射）：

| 用户原话特征 | 路由命令 |
|-------------|---------|
| "写个 SQL"/"查一下"/"算一下" | `/sql` |
| "做同步"/"配数据集成"/"ETL" | `/etl` |
| "建表"/"设计宽表"/"做建模" | `/model` |
| "我要做 xx 需求"/"新建数据需求" | `/propose` |
| "开始实施"/"继续执行" | `/apply` |
| "review 一下"/"帮我看看模型" | `/review` |
| "性能太慢"/"跑得慢"/"优化" | `/optimize` |
| "数据对不上"/"对账"/"质量校验" | `/dq` |
| "配调度"/"上线作业" | `/schedule` |
| "归档 xx" | `/archive` |
| "记录一下变更"/"帮我记一下改动" | `version-tracker` |

主 Skill 在路由前**先复述识别结果让用户确认**（沿用现有"意图确认"协议）。

---

## 4. 文件落地结构

### 4.1 落地后的项目目录

```
Data_Warehouse_Engineering/
├── data_warehouse_engineering_code_copilot/    （提示词资产源）
│   ├── agents/                                  保留作为知识源（不删）
│   ├── changes/templates/
│   ├── knowledge/
│   ├── rules/
│   ├── specs/
│   │   └── dwe-copilot-to-agent.md             ← 本 spec
│   └── 目录结构和设计说明.md
│
└── .qoder/                                      （Qoder 工程化产物）
    ├── skills/
    │   └── dwe/
    │       ├── SKILL.md                         主 Skill 入口
    │       ├── references/                      引用规则与知识（符号链接或拷贝）
    │       │   ├── rules-index.md
    │       │   └── knowledge-index.md
    │       └── assets/                          模板与示例
    │           ├── spec-template.md
    │           ├── tasks-template.md
    │           ├── log-template.md
    │           └── validation-spec-template.md
    └── agents/
        ├── dwh-sql-reviewer.md
        ├── dwh-model-reviewer.md
        ├── dwh-performance-reviewer.md
        └── dwh-version-tracker.md
```

> **rationale**：保留 `data_warehouse_engineering_code_copilot/` 作为唯一**真理源（source of truth）**，`.qoder/` 下的文件是从源派生的工程化产物（用同步脚本生成 / 维护）。

### 4.2 多环境降级落地（可选 Task，按需启用）

| 环境 | 输出路径 | 来源 |
|------|---------|------|
| Qoder | `.qoder/skills/dwe/`、`.qoder/agents/*.md` | 主蓝本 |
| Claude Code | `.claude/agents/*.md` | 由 Qoder 蓝本平移 |
| Cursor | `.cursor/rules/dwe.mdc` | 主 Skill + 子 Agent 内联合并 |
| 通用 / CLI | `data_warehouse_engineering_code_copilot/agents/copilot-prompt.md` | 直接作为系统提示词 |

---

## 5. 主 Skill `/dwe` 设计

### 5.1 SKILL.md frontmatter（Qoder 标准）
```yaml
---
name: dwe
description: 数仓开发 AI 协作助手统一入口。覆盖 SQL 开发、ETL 接入、数仓建模、变更提案、实施、审查、性能优化、数据质量、调度配置、归档全流程；自动识别自然语言意图并调度 sql-reviewer / model-reviewer / performance-reviewer / version-tracker 子 Agent。
when_to_use: |
  - 用户提到 数仓 / 数据仓库 / DWH / ODS / DWD / DWS / ADS / DIM / SQL / 建模 / ETL / 调度 / 数据质量 / 数据回刷 等关键词
  - 用户用自然语言描述数仓相关需求（"帮我写 SQL"、"做个同步"、"建表"、"看看模型"、"性能太慢"、"对账"、"归档" 等）
  - 用户使用 /dwe 或 /dwe <子命令> 显式调用
allowed_tools: [Read, Write, Edit, Bash, Grep, Glob, Task]
---
```

### 5.2 SKILL.md 主体结构

```
1. 身份与核心法则（继承 copilot-prompt.md 全部 4 条铁律）
2. 启动协议（首次：扫 rules/、扫 changes/ 进行中变更、初始化 changelog 路径）
3. 意图识别表（自然语言 → 命令路由）
4. 命令分派表（每个命令的输入/输出/调用 Subagent）
5. Subagent 调度协议（何时调用、传什么上下文、如何回填结果）
6. 变更追踪强约束（每次写操作必须最终触发 version-tracker）
7. 错误处理与降级（Subagent 不可用时退化为内嵌检查清单）
```

### 5.3 关键差异点（vs 当前 copilot-prompt.md）

| 维度 | copilot-prompt.md（现状） | dwe/SKILL.md（目标） |
|------|--------------------------|---------------------|
| 调度方式 | 文字描述"完成后触发 version-tracker" | **真实调用 Task 工具拉起 Subagent** |
| 上下文传递 | 模糊 | 明确传入：变更摘要、关联文件、影响范围 |
| 串行/并行 | 无强制 | `/review` 强制串行；其他命令自动后置异步 |
| 工具权限 | 不约束 | frontmatter 显式声明 |
| 自然语言 | 描述性 | **作为入口能力之一**，与命令等权 |

---

## 6. Subagent 设计（4 个）

### 6.1 dwh-sql-reviewer

```yaml
---
name: dwh-sql-reviewer
description: 专职审查数仓 SQL 代码质量、性能、可维护性。前置条件：必须在 model-reviewer 通过后才启动。返回 Critical/Important/Minor 三级问题清单 + 性能预估。
allowed_tools: [Read, Grep, Glob]
---
```
内容继承自 `agents/sql-reviewer.md`，新增：
- **输入契约**：调用方必须传入 `target_files`（SQL 文件路径列表）+ `change_id`（关联变更名）
- **输出契约**：返回结构化 JSON-like 段落（Critical/Important/Minor + 性能评估），便于主 Skill 解析
- **拒绝条件**：未传入 target_files 或检测到未通过 model-reviewer 时拒绝执行

### 6.2 dwh-model-reviewer

```yaml
---
name: dwh-model-reviewer
description: 专职验证数仓模型 / DDL 是否符合 spec 与建模规范。只读不写，独立于实现者上下文。返回缺失/多余/偏差/合规四类清单。
allowed_tools: [Read, Grep, Glob]
---
```
内容继承 `agents/model-reviewer.md`，新增：
- **输入契约**：`change_id` + `spec_file_path` + `target_tables`
- **输出契约**：模型结构验证 / 字段约束验证 / 分层合规 / 结论 PASS/FAIL
- **不信报告只信元数据**：必须独立读取 DDL，不允许依赖实现者描述

### 6.3 dwh-performance-reviewer

```yaml
---
name: dwh-performance-reviewer
description: 专职诊断数仓 SQL / ETL / 调度作业的性能问题。可独立启动，不依赖其他审查阶段。输出五层（数据源/抽取/数仓/SQL/应用）诊断 + 量化优化路线图。
allowed_tools: [Read, Grep, Glob, Bash]
---
```
内容继承 `agents/performance-reviewer.md`，新增：
- **输入契约**：`target` 可为 SQL 文件 / 表名 / 作业名
- **Bash 仅允许**：`EXPLAIN`、`DESC FORMATTED`、`SHOW PARTITIONS` 等只读元数据查询
- **输出契约**：P0/P1/P2 问题清单 + 优化前后对比表

### 6.4 dwh-version-tracker

```yaml
---
name: dwh-version-tracker
description: 在每次 DDL/SQL/ETL/调度变更后，结构化追加变更日志到指定路径。首次触发时询问日志路径并记忆。
allowed_tools: [Read, Edit, Write]
---
```
内容继承 `agents/version-tracker.md`，新增：
- **输入契约**：`module`（DDL/SQL/ETL/调度/数据质量/权限/项目配置）+ `layer`（ODS/DWD/...）+ `operation`（新建/修改/删除/回刷）+ `summary`（一句话摘要）+ `details`（变更项列表）+ `affected_files` + `downstream_impact` + `refresh_range`（如涉及）
- **路径记忆**：会话级缓存 changelog 路径，避免重复询问
- **不阻塞**：路径无效时仅提示用户，不中断主 Skill

---

## 7. 实施任务拆分（待审核通过后执行）

> 以下为预告，**不在本 spec 审核通过前执行**。

| Task | 内容 | 依赖 | 验收 |
|------|------|------|------|
| T1 | 创建 `.qoder/agents/dwh-{sql,model,performance,version}-*.md` 4 个 Subagent | 无 | 文件存在，frontmatter 合法 |
| T2 | 创建 `.qoder/skills/dwe/SKILL.md` 主 Skill | T1 | 在 Qoder 中可识别 `/dwe` |
| T3 | 创建 `.qoder/skills/dwe/assets/` 4 个模板（从 changes/templates/ 拷贝）| T2 | /propose 能复制实例化 |
| T4 | 创建 `.qoder/skills/dwe/references/` 索引（rules + knowledge 摘要）| T2 | 主 Skill 可按需 Read |
| T5 | 单元验证：`/dwe sql ...` → 输出 + version-tracker 写日志 | T1-T4 | 日志条目格式正确 |
| T6 | 集成验证：`/dwe review <change>` → 串行 model→sql 两阶段 | T1-T4 | 第一阶段失败时不进入第二阶段 |
| T7 | 自然语言验证："帮我看看为什么这个作业慢" → performance-reviewer | T1-T4 | 五层诊断输出 |
| T8 | （可选）多环境降级落地：Cursor `.cursor/rules/dwe.mdc` 内联版 | T2 | 行为与 Qoder 一致 |
| T9 | 同步脚本：从 `data_warehouse_engineering_code_copilot/` → `.qoder/` 一键同步 | T1-T7 | 资产单一真理源不漂移 |

---

## 8. 风险与待澄清

### 8.1 已确认决策
- [x] **Q1**：仅交付 Qoder（`.qoder/`）一个环境（T8 暂不纳入）
- [x] **Q2**：拷贝快照 + 同步脚本（不使用符号链接）
- [x] **Q3**：接受自然语言自动触发（主 Skill `when_to_use` 足够宽泛）
- [x] **Q4**：默认 `data_warehouse_engineering_code_copilot/CHANGELOG.md`
- [x] **Q5**：Subagent 命名前缀使用 `dwh-`

### 8.2 风险
- ⚠️ 不同环境对 frontmatter 字段（`when_to_use` / `allowed_tools` / `description`）的解析略有差异，T8 需要环境实测
- ⚠️ Subagent 之间不能直接通信（无状态），所有上下文必须由主 Skill 显式传递
- ⚠️ `.qoder/` 是工程产物，建议加入 `.gitignore` 或反过来纳入 git 但禁止手改（一切以源目录为准）

### 8.3 实施进度
- [x] T1: 创建 `.qoder/agents/dwh-{sql,model,performance,version}-*.md` 4 个 Subagent
- [x] T2: 创建 `.qoder/skills/dwe/SKILL.md` 主 Skill
- [x] T3: 创建 `.qoder/skills/dwe/assets/` 4 个模板
- [x] T4: 创建 `.qoder/skills/dwe/references/` 索引（rules-index.md + knowledge-index.md）
- [ ] T5: 单元验证：`/dwe sql ...` → 输出 + version-tracker 写日志
- [ ] T6: 集成验证：`/dwe review <change>` → 串行 model→sql 两阶段
- [ ] T7: 自然语言验证："帮我看看为什么这个作业慢" → performance-reviewer
- [ ] T8: （可选）多环境降级落地
- [ ] T9: 同步脚本

---

## 9. 影响范围

- **影响目录**：新增 `.qoder/skills/dwe/`、`.qoder/agents/dwh-*.md`
- **不影响**：`data_warehouse_engineering_code_copilot/` 内已有资产（仅作为引用源）
- **影响用户**：所有使用本仓库的数仓开发者，从"复制粘贴提示词"切换为"`/dwe ...` 或自然语言"
- **是否涉及历史回刷**：否

---

## 10. 验证策略

| 类型 | 方法 | 通过标准 |
|------|------|---------|
| 加载验证 | 重启 Qoder，确认 `/dwe` 在命令面板可见 | 可见 + 描述正确 |
| 命令验证 | 跑 `/dwe sql 计算昨日订单数` | 输出 SQL + 验证 + 性能评估 + 自动追加 changelog |
| 串行验证 | 跑 `/dwe review test-change` | model 失败时不进 sql 阶段 |
| 自然语言验证 | 输入"帮我审一下 dws_xxx.sql" | 主 Skill 复述识别 → 用户确认 → 调度 reviewer |
| 跨环境验证 | （可选）在 Claude Code 中复用 `.claude/agents/` | 行为一致 |

---

### 11. 已确认决策（审核完成）

- [x] Q1: 仅交付 Qoder 一套
- [x] Q2: 拷贝快照 + 同步脚本
- [x] Q3: 接受自然语言自动触发
- [x] Q4: 默认 `data_warehouse_engineering_code_copilot/CHANGELOG.md`
- [x] Q5: Subagent 前缀 dwh-

> **状态**：spec 已批准，T1-T4 已实施落地。T5-T9 待运行时验证。
