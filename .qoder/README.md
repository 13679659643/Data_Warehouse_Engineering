# .qoder/ 目录总览

> 数仓开发 AI 协作助手（DWE）的 Qoder 工程化产物。
> 真理源：`data_warehouse_engineering_code_copilot/`，本目录为派生产物。

## 目录结构

```
.qoder/
├── agents/                                    Subagent 池（4 个专职 Agent）
│   ├── dwh-sql-reviewer.md                    SQL 质量审查（Critical/Important/Minor 三级 + 性能评估）
│   ├── dwh-model-reviewer.md                  模型/DDL 合规审查（缺失/多余/偏差/合规 四类）
│   ├── dwh-performance-reviewer.md            性能诊断（五层：数据源/抽取/数仓/SQL/应用 + P0/P1/P2）
│   └── dwh-version-tracker.md                 变更日志追踪（结构化追加，不阻塞主流程）
│
├── skills/
│   └── dwe/                                   主 Skill：数仓开发 AI 协作助手统一入口
│       ├── SKILL.md                           ⭐ 核心入口（意图识别 → 命令路由 → Subagent 调度）
│       ├── assets/                            变更管理模板（/propose / /apply 时实例化）
│       │   ├── spec-template.md               变更提案 Spec 模板
│       │   ├── tasks-template.md              任务拆分模板
│       │   ├── log-template.md                变更日志模板
│       │   └── validation-spec-template.md    验证 Spec 模板
│       └── references/                        规则与知识索引（按需 Read 源文件）
│           ├── rules-index.md                 规则索引（7 条规则 + 按命令推荐读取顺序）
│           └── knowledge-index.md             知识索引（5 类知识 + 快速检索表）
│
└── specs/
    └── dwe-copilot-to-agent.md                落地 Spec（状态：approved，T1-T4 已完成）
```

## 架构概览

```
用户输入（/dwe ... 或 自然语言）
        │
        ▼
  ┌─────────────┐
  │ 主 Skill     │  SKILL.md
  │ /dwe        │  - 意图识别 / 命令路由
  │             │  - 加载 rules/* 规则
  │             │  - 命令分派
  └──────┬──────┘
         │
   ┌─────┼──────────────────────┐
   │     │                      │
   ▼     ▼                      ▼
 命令族A  命令族B              归档族
 /sql    /review               /archive
 /etl    /optimize
 /model  /dq
 /propose /schedule
 /apply  /init
   │     │                      │
   │     │ 按阶段串行调度         │
   ▼     ▼                      ▼
 ┌─────────────────────────────────────┐
 │           Subagent 池               │
 │  dwh-version-tracker  (后置异步)    │
 │  dwh-model-reviewer   (串行阻塞)    │
 │  dwh-sql-reviewer     (串行阻塞)    │
 │  dwh-performance-reviewer (直接)    │
 └─────────────────────────────────────┘
```

## 调度规则速查

| 命令 | 调度 Subagent | 顺序 | 阻塞 |
|------|--------------|------|------|
| /sql, /etl, /model, /apply, /schedule, /dq, /archive | dwh-version-tracker | 后置 | 否 |
| /review | dwh-model-reviewer → dwh-sql-reviewer | 串行 | 是（前者通过才进后者） |
| /optimize | dwh-performance-reviewer | 直接 | 是 |

## 文件职责明细

### 主 Skill SKILL.md
- 5 条核心法则（No Spec No Change / Spec is Truth / Reverse Sync / 现状必须有出处 / 变更即记录）
- 11 条命令体系（/init /sql /etl /model /propose /apply /review /optimize /dq /schedule /archive）
- 11 条自然语言意图映射
- Subagent 调度时机矩阵 + 上下文传递规范
- 错误处理与降级策略

### Subagent 设计要点

| Subagent | allowed_tools | 输入契约 | 输出契约 |
|----------|--------------|---------|---------|
| dwh-sql-reviewer | Read, Grep, Glob | target_files + change_id + model_review_passed | Critical/Important/Minor + 性能评估 |
| dwh-model-reviewer | Read, Grep, Glob | change_id + spec_file_path + target_tables | 缺失/多余/偏差/合规 + PASS/FAIL |
| dwh-performance-reviewer | Read, Grep, Glob, Bash(只读) | target + symptoms | P0/P1/P2 + 五层诊断 + 优化前后对比 |
| dwh-version-tracker | Read, Edit, Write | module + layer + operation + summary + details + affected_files | 结构化变更日志条目 |

## 真理源与同步

| 维度 | 说明 |
|------|------|
| 真理源 | `data_warehouse_engineering_code_copilot/`（agents/, rules/, knowledge/, changes/） |
| 工程产物 | `.qoder/`（本目录，由源派生） |
| 同步策略 | 拷贝快照 + 手动同步（T9 待实施） |
| 变更日志默认路径 | `data_warehouse_engineering_code_copilot/CHANGELOG.md` |

## 验收状态

- [x] T1: 4 个 Subagent 创建完成
- [x] T2: 主 Skill SKILL.md 创建完成
- [x] T3: 4 个模板拷贝到 assets/
- [x] T4: 2 个索引创建到 references/
- [x] Spec 状态更新为 approved
- [ ] T5-T9: 运行时验证（待用户实测）
