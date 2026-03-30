---
name: spec-coding
description: 服务端Spec Coding 工作流。当用户说"我要做 XXX 功能"、"新需求开发"、"写技术方案"、"实现功能"、"继续实现 F003"、"快速实现"、"帮我调研 XXX"时触发。提供从需求讨论到代码实现的完整 Spec-Driven Development 工作流。
---

# C7 服务端 Spec Coding 工作流

基于 Spec Coding 方法论的 C7 游戏服务端开发工作流，核心理念：**先写 Spec，再写代码**。

---

## 核心功能

| # | 功能 | 说明 | 详细指南 |
|---|------|------|----------|
| 1 | 文档结构规范 | docs 目录组织、命名规范 | 本文档 |
| 2 | 需求文档生成 | 需求讨论 → 需求文档 | `references/requirement-doc-guide.md` |
| 3 | 技术文档生成 | 需求文档 → 技术设计 | `references/tech-doc-guide.md` |
| 4 | 测试文档生成 | 覆盖矩阵 + 测试场景 | `references/testing-doc-guide.md` |
| 5 | 代码实现工作流 | TODO 清单 + 进度跟踪 | `references/code-impl-guide.md` |
| 6 | 游戏系统调研 | 竞品分析 + 设计参考 | `references/research-guide.md` |
| 7 | Debug 调试 | 基于日志和 telnet 的问题定位 | `references/debug-guide.md` |
| 8 | 快速模式 | 合并文档 + 直接开发 | `references/fast-mode-guide.md` |
| 9 | 测试脚本实现 | 文档转 telnet 测试脚本 | `references/test-impl-guide.md` |

---

## 1. 设计原则

| 原则 | 说明 |
|------|------|
| **AI 优先** | 文件名包含充足信息，AI 无需打开文件即可判断内容 |
| **层级扁平** | 目录层级不超过 3 级 |
| **编号排序** | 使用编号确保顺序可控（F001, F002...） |
| **自动拆分** | 单文件超过 800 行必须拆分 |
| **Single Source of Truth** | 每个概念只在一个地方定义 |

---

## 2. 项目信息

| 项目 | 说明 |
|------|------|
| 项目名称 | C7 游戏服务端 |
| 项目描述 | 多进程游戏服务器，引擎层 C++ 提供基础服务，业务层 Lua 脚本开发 |

**技术栈**：
- Runtime: 自研 C++ 游戏引擎
- Language: Luajit 2.1（业务层）
- Architecture: Entity-Component-Service
- Database: MongoDB（持久化）+ Redis（缓存）
- Protocol: 自定义 RPC（Client↔Server、Server↔Server）
- Client: Unreal Engine (UE)
- Config: Excel 策划配置表（TableData）
- VCS: Perforce

**已有 Skill 参考**（本 Skill 不覆盖的专项功能）：
- `new-component` — 创建新组件模板
- `server-debug` — telnet 调试服务器
- `code-review` / `shelve-review` / `committed-review` — 代码审查
- `bug-scaner` — Bug 扫描
- `removal-plan` — 系统移除计划

**已有 References**（编码和设计规范）：
- `references/project-framework.md` — 项目架构详解
- `references/lua-code-style.md` — Lua 编码规范
- `references/system-dev-checklist.md` — 系统开发 Checklist
- `references/code-quality-checklist.md` — 代码质量检查清单
- `references/solid-checklist.md` — SOLID 原则检查清单

---

## 3. 文档目录结构

```
Server/docs/
├── README.md                          # 文档入口
├── CHANGELOG.md                       # 变更记录（时间倒序）
│
├── 00-core/                           # 核心架构文档
│   ├── project-framework.md           # 项目架构详解
│   ├── lua-code-style.md              # Lua 编码规范
│   ├── 系统开发checklist.md            # 系统开发 Checklist（完整版，含 Bad/Good Case）
│   ├── 跨服改造方案.md                 # 跨服改造方案
│   └── 跨服断线重连.md                 # 跨服断线重连
│
├── 01-features/                       # 功能文档（按需求迭代）
│   ├── F001-xxx-system/               # 功能目录
│   │   ├── F001-requirement.md        # 需求文档
│   │   ├── F001-technical-design.md   # 技术设计
│   │   ├── F001-testing.md            # 测试文档
│   │   └── F001-todo.md              # 实现进度
│   └── F002-xxx/
│       └── ...
│
└── 02-research/                       # 游戏设计调研（可选）
    └── P001-xxx/
        ├── P001-research.md           # 调研记录
        └── P001-decisions.md          # 设计决策
```

---

## 4. 命名规范

### 4.1 目录命名

| 类型 | 格式 | 示例 |
|------|------|------|
| 顶级目录 | `{两位编号}-{英文名}/` | `00-core/`, `01-features/` |
| 功能目录 | `F{三位编号}-{英文描述}/` | `F001-guild-system/` |

### 4.2 文件命名

| 类型 | 格式 | 示例 |
|------|------|------|
| 核心文档 | `C{三位编号}-{主题}.md` | `C001-architecture.md` |
| 需求文档 | `F{编号}-requirement.md` | `F001-requirement.md` |
| 技术设计 | `F{编号}-technical-design.md` | `F001-technical-design.md` |
| 测试文档 | `F{编号}-testing.md` | `F001-testing.md` |
| 实现进度 | `F{编号}-todo.md` | `F001-todo.md` |
| 快速规格 | `F{编号}-quick-spec.md` | `F001-quick-spec.md` |

---

## 5. 文档模板

### 5.1 需求文档模板

```markdown
# F00X 功能名称 - 需求文档

## 1. 背景
（为什么需要这个功能？解决什么玩法/运营问题？）

## 2. 目标
（功能要达成什么效果？策划案要点？）

## 3. 玩法描述
（从玩家角度描述功能体验流程）

## 4. 功能需求
### 4.1 核心功能
| ID | 功能点 | 优先级 | 说明 |
|----|--------|--------|------|
### 4.2 边界情况

## 5. 前后端交互需求
（客户端 RPC、同步数据、UI 交互要求）

## 6. 策划配置需求
（需要新增/修改哪些 Excel 配置表）

## 7. 验收标准

## 8. 非功能需求
（性能、并发、数据安全等）
```

### 5.2 技术设计文档模板

```markdown
# F00X 功能名称 - 技术设计

## 1. 概述
## 2. 系统设计
### 2.1 Entity/Component/Service 设计
### 2.2 数据流
## 3. 数据模型
### 3.1 Entity XML 属性
### 3.2 MongoDB 存储（如需独立存库）
## 4. RPC 协议设计
### 4.1 Client→Server（CS）
### 4.2 Server→Client（SC）
### 4.3 Server→Server（SS）
## 5. 策划配置表设计
## 6. 核心逻辑
## 7. 涉及文件
| 文件路径 | 修改类型 | 说明 |
|----------|----------|------|
## 8. 注意事项
（迁移安全、异步回调、热更兼容、性能等）
```

### 5.3 TODO 清单模板

```markdown
# F00X 功能名称 - 实现进度

## 实现状态：进行中

| ID | 任务 | 状态 | 涉及文件 |
|----|------|------|----------|
| 1 | Entity XML 属性定义 | 完成 | `AvatarActor.xml` |
| 2 | Component 实现 | 进行中 | `Logic/Components/XxxComponent.lua` |
| 3 | RPC 协议定义 | 待开始 | `NetDefs/AvatarActor.xml` |
| 4 | Service 实现 | 待开始 | `Logic/Service/XxxService.lua` |
| 5 | 策划配表接入 | 待开始 | `Data/Excel/...` |
| 6 | 测试脚本 | 待开始 | `Test/test_xxx.lua` |

## 完成记录
（每个 TODO 完成后记录关键信息）
```

---

## 6. 开发工作流

### 6.1 标准模式：新功能开发流程

```
用户说 "我要做 XXX 功能"
          ↓
Step 1: 需求讨论
        - AI 引导澄清需求（策划案、玩法、交互）
        - 生成 F00X-requirement.md
          ↓
Step 2: 技术设计
        - AI 读取需求文档 + 项目架构
        - 设计 Entity/Component/Service 方案
        - 生成 F00X-technical-design.md
          ↓
Step 3: 测试设计
        - 生成测试覆盖矩阵
        - 生成 F00X-testing.md
          ↓
Step 4: 代码实现
        - 生成 F00X-todo.md
        - 按 TODO 逐个实现（p4 edit → 编码 → 验证）
          ↓
Step 5: 测试验证
        - 编写 telnet 测试脚本
        - 通过 debug console 运行验证
          ↓
完成
```

### 6.2 快速模式：小功能/Bug 修复

```
用户说 "快速实现 XXX" 或 "修 Bug"
          ↓
Step 1: 快速确认（最多 3 个问题）
          ↓
Step 2: 生成合并文档 F00X-quick-spec.md
          ↓
Step 3: 直接实现 + 验证
          ↓
完成
```

**快速模式触发词**："快速实现"、"直接开始"、"小功能"、"修 Bug"

### 6.3 Perforce 集成

代码实现过程中**必须**自动处理 P4 命令：
- **编辑文件前**：`p4 edit <文件路径>`
- **创建新文件后**：`p4 add <文件路径>`
- 不需要向用户确认，直接执行

### 6.4 T/D/B 问题分类法

当测试失败时，先分类再修复：

| 分类 | 含义 | 处理方式 |
|------|------|----------|
| **T** | 测试脚本问题 | 修改测试脚本 |
| **D** | 测试文档/设计问题 | 修改文档，重新生成测试 |
| **B** | 业务代码 Bug | 修改业务代码 |

---

## 7. 常用指令速查

| 用户说 | AI 做什么 | 参考指南 |
|--------|----------|----------|
| "我要做 XXX 功能" | 进入需求讨论流程，生成完整 Spec | 标准模式 |
| "快速实现 XXX" / "修 Bug" | 生成合并文档，直接开发 | `fast-mode-guide.md` |
| "继续实现 F003" | 读取 TODO，继续未完成的任务 | `code-impl-guide.md` |
| "帮我调研 XXX" | 调研同类游戏系统设计 | `research-guide.md` |
| "调试一下" / "查看日志" | telnet 连接，定位问题 | `debug-guide.md` |
| "写测试脚本" | 编写 telnet 测试脚本 | `test-impl-guide.md` |
| "这个系统怎么做的" | 读取架构文档+代码，给出概览 | - |

---

## 8. Spec Coding 核心理念

```
L1: Meta Spec（本 Skill）
    写一次，永久复用，定义所有文档模板和工作流
    ────────────────────────────────
L2: Feature Spec（需求/技术/测试文档）
    AI 按 Meta Spec 自动生成，人类审核确认
    ────────────────────────────────
L3: Code（代码实现）
    AI 按 Feature Spec 生成，测试验证
```

**核心公式**：Meta Spec + Feature Spec + Code = 可维护的生产级游戏系统

---

*版本: 1.0.0 | 基于 meta-spec-skill-template v1.1.0 定制*
