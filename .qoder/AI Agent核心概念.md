
以下是 Qoder 中这四个核心概念的解释：

---

## Agent（子智能体）

**比喻：专科医生**

Agent 是一个专职的 AI 子角色，负责执行某一类特定任务。它有明确的职责边界和受限的工具权限。

- 存放位置：`.qoder/agents/`
- 例如你项目中的 `dwh-sql-reviewer`（SQL审查）、`dwh-model-reviewer`（模型审查）
- **被 Skill 调度**，用户通常不直接调用

---

## Skill（技能）

**比喻：全科医生 / 前台调度中心**

Skill 是面向用户的统一入口，负责意图识别、命令路由、Agent 调度。

- 存放位置：`.qoder/skills/<技能名>/SKILL.md`
- 例如你项目的 `/dwe` 就是主 Skill，通过它调度各个子 Agent
- **用户直接调用**（如 `/dwe sql 计算月度 GMV`）

---

## Spec（规格说明）

**比喻：施工图纸 / 手术方案**

Spec 是变更需求规格说明书，在做重要变更之前先明确"改什么、为什么改、怎么改"。核心理念是 **"No Spec, No Change"**。

- 存放位置：`.qoder/specs/`
- 通过 `/propose` 创建，`/apply` 执行
- **纯文档**，不执行逻辑，是变更的"真理源"

---

## Wiki / RepoWiki（项目知识库）

**比喻：百科全书 / 教科书**

RepoWiki 是 Qoder 自动生成的项目文档，帮助 AI 和人快速理解项目架构和全貌。

- 存放位置：`.qoder/repowiki/`
- **被动参考资料**，AI 回答问题时自动引用

---

## 四者关系

```
用户: /dwe review xxx.sql
        │
        ▼
   Skill(dwe)  ← 识别意图，加载规则和 Wiki 知识
        │
        ├─ 查 Spec（是否有批准的变更依据）
        │
        ├─ 调度 model-reviewer Agent（审查模型）
        │
        ├─ 调度 sql-reviewer Agent（审查 SQL）
        │
        └─ 调度 version-tracker Agent（记录变更）
```

**一句话总结：Skill 是大脑（调度），Agent 是手脚（执行），Spec 是图纸（变更依据），Wiki 是百科（背景知识）。**