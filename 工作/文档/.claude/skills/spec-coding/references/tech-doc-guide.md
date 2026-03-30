# 技术文档生成指南（C7 游戏服务端）

> 定义从需求文档到技术设计文档的生成工作流。

---

## 1. 触发场景

当用户说以下内容时触发：
- "生成技术文档"
- "写技术方案"
- "技术设计"
- "F00X 的技术设计"

**前置条件**：需求文档 `F00X-requirement.md` 已存在。

---

## 2. 工作流程
核确认
        ↓
```
需求文档已就绪
        ↓
Step 1: 读取上下文
        - 读取需求文档
        - 读取 project-framework.md 了解架构
        - 读取相关现有代码（同类系统实现）
        - 读取 system-dev-checklist.md 了解开发约束
        ↓
Step 2: 设计讨论（可选）
        - 如有多种方案，与用户讨论
        - 确定 Entity/Component/Service 拆分
        ↓
Step 3: 生成技术文档
        - 按模板生成 F00X-technical-design.md
        - 用户审
完成
```

---

## 3. 技术设计要点

### 3.1 C7 架构特有考量

| 维度 | 设计问题 |
|------|----------|
| **Entity 设计** | 需要新增 Entity 类型吗？在哪个 Entity 上扩展？ |
| **Component 设计** | 新增的组件叫什么？挂载到哪个 Entity？ |
| **Service 设计** | 需要全局 Service 吗？几个 Shard？分片策略？ |
| **属性设计** | 新增哪些 XML 属性？类型定义？是否存盘？ |
| **RPC 设计** | CS/SC/SS 分别需要哪些？参数和返回值？ |
| **配表设计** | 需要新增/修改哪些 Excel 表？字段和索引？ |
| **数据存储** | 挂在 Entity 属性上还是独立写库？数据量预估？ |
| **迁移安全** | AvatarActor 迁移时数据如何处理？callback 是否安全？ |
| **热更兼容** | 是否遵循 Hotfix 兼容规范（无闭包、无模块级 local 函数）？ |
| **性能** | 高频操作避免创建临时 table？批量操作是否需要分帧？ |

### 3.2 代码位置规划

技术文档必须明确每个功能点的代码位置：

```markdown
| 功能点 | 文件路径 | 修改类型 |
|--------|----------|----------|
| Entity 属性 | `Logic/Entities/AvatarActor.xml` | 修改 |
| 组件挂载 | `Logic/Entities/ComponentDefine/AvatarActorComponents.lua` | 修改 |
| 组件实现 | `Logic/Components/XxxComponent.lua` | 新增 |
| Service | `Logic/Service/XxxService.lua` | 新增 |
| RPC 协议 | `NetDefs/AvatarActor.xml` | 修改 |
| 常量定义 | `Logic/Const/XxxConst.lua` | 新增 |
| 配表接入 | `Data/Excel/TableData.lua` | 自动生成 |
```

---

## 4. 技术文档模板

```markdown
# F00X 功能名称 - 技术设计

> 创建时间：YYYY-MM-DD
> 需求文档：[F00X-requirement.md](./F00X-requirement.md)

---

## 1. 概述

### 1.1 背景
（简述需求背景，引用需求文档）

### 1.2 技术目标
（技术实现要达成什么效果）

---

## 2. 系统设计

### 2.1 Entity-Component-Service 设计

**新增/修改的 Entity**：
（如需要新增 Entity 类型，说明其继承关系和职责）

**新增的 Component**：

| Component | 挂载 Entity | 职责 |
|-----------|-------------|------|
| `XxxComponent` | AvatarActor | 玩家 XXX 功能逻辑 |

**新增的 Service**：

| Service | Shard 数 | 分片策略 | 职责 |
|---------|----------|----------|------|
| `XxxService` | 1 | 单 Shard | 全服 XXX 管理 |

### 2.2 数据流

```
Client 点击操作
  → CS RPC 到达 AvatarActor
  → XxxComponent 处理逻辑
  → CallService("XxxService", ...)
  → XxxService 处理全服逻辑
  → SC RPC 推送结果给客户端
```

---

## 3. 数据模型

### 3.1 Entity XML 属性

**AvatarActor.xml 新增属性**：

| 属性名 | 类型 | 存盘 | 说明 |
|--------|------|------|------|
| `xxxInfo` | `XXX_INFO` | 是 | 玩家 XXX 数据 |

**类型定义（alias.xml 或系统内 DataTypes）**：

```xml
<XXX_INFO>
    FIXED_DICT
    <Properties>
        <field1> INT32 </field1>
        <field2> UNICODE </field2>
    </Properties>
</XXX_INFO>
```

### 3.2 Service 属性

| 属性名 | 类型 | 说明 |
|--------|------|------|
| `xxxData` | `XXX_DATA` | 全服 XXX 数据 |

### 3.3 MongoDB 存储（如需独立写库）

**Collection**: `xxx_collection`

| 字段 | 类型 | 说明 | 索引 |
|------|------|------|------|
| `_id` | ObjectId | 主键 | 默认 |
| `playerId` | Int64 | 玩家ID | 是 |

---

## 4. RPC 协议设计

### 4.1 Client → Server（CS）

| RPC 名称 | 参数 | 说明 |
|----------|------|------|
| `CSXxxRequest` | `(INT32 param1, UNICODE param2)` | 客户端请求 XXX |

### 4.2 Server → Client（SC）

| RPC 名称 | 参数 | 说明 |
|----------|------|------|
| `SCXxxNotify` | `(XXX_INFO info)` | 推送 XXX 数据 |
| `SCXxxResult` | `(INT32 result)` | 操作结果 |

### 4.3 Server → Server（SS）

| RPC 名称 | 参数 | 说明 |
|----------|------|------|
| `SSXxxSync` | `(INT64 playerId, ...)` | 跨进程同步 |

### 4.4 RPC 安全约束

- CS RPC 每个参数必须做类型和范围检查
- 高频 CS RPC 需要 CD 限制（异步操作 0.5-1s，数据库/广播类 3s+）
- 客户端参数禁止使用 None 类型
- 大量数据必须分包/分页拉取

---

## 5. 策划配置表设计

| 配置表 | 用途 | 关键字段 | 索引方式 |
|--------|------|----------|----------|
| `XxxConfig` | XXX 基础配置 | id, name, param1 | 按 id 索引 |

**TableData 访问方式**：
```lua
local row = TableData.GetXxxConfigRow(id)
if not row then
    self:logErrorFmt("XxxConfig not found, id=%s", id)
    return
end
```

---

## 6. 核心逻辑

### 6.1 业务流程

```
1. CS RPC 参数校验
2. 前置条件检查（等级、资源、冷却等）
3. 核心业务处理
4. 数据持久化（更新 Entity 属性）
5. SC RPC 推送结果
6. SA 日志记录
```

### 6.2 关键算法
（如果有复杂算法、概率计算等，在此说明）

---

## 7. 涉及文件

| 文件路径 | 修改类型 | 说明 |
|----------|----------|------|
| `Logic/Components/XxxComponent.lua` | 新增 | 组件实现 |
| `Logic/Entities/ComponentDefine/AvatarActorComponents.lua` | 修改 | 挂载组件 |
| `Logic/Entities/AvatarActor.xml` | 修改 | 新增属性 |
| `NetDefs/AvatarActor.xml` | 修改 | RPC 协议 |
| `Logic/Const/XxxConst.lua` | 新增 | 常量定义 |
| | | |

---

## 8. 注意事项

### 8.1 迁移安全
- AvatarActor 会跨进程迁移，callback 必须使用字符串形式（方法名），不能用闭包
- 定时器使用 `addSerializeTimer` 支持迁移
- 异步操作回调执行时必须检查 Entity 有效性

### 8.2 热更兼容
- 不在 table 中持有 function（存函数名代替）
- 不使用模块级 local 函数
- 模块枚举/常量不用 local
- 不在模块级别执行注册等逻辑

### 8.3 数据安全
- 涉及数值修改必须有 SA Log（修改前、修改后、来源）
- 购买操作先扣币再发放
- 所有投放使用限次奖励
- 发放奖励先设标记再发放

### 8.4 性能
- 高频操作避免创建临时 table 和闭包
- 批量操作需分帧处理
- 配表数据禁止缓存（影响热更）

### 8.5 兼容性
（对现有功能的影响、历史数据兼容）

### 8.6 风险点
- 风险 1：应对措施
- 风险 2：应对措施

---

## 9. 测试要点

| 测试类型 | 覆盖点 |
|----------|--------|
| 功能测试 | 核心玩法流程 |
| 边界测试 | 迁移场景、断线重连、时间边界 |
| 性能测试 | 高并发、大数据量 |
| 安全测试 | RPC 参数攻击、刷漏洞 |
```

---

## 5. 检查清单

生成技术文档后，确保：

- [ ] Entity/Component/Service 设计清晰
- [ ] 数据模型完整（XML 属性、类型定义、MongoDB）
- [ ] RPC 协议设计规范（CS/SC/SS、参数类型）
- [ ] 策划配表需求明确
- [ ] 涉及文件列表完整
- [ ] 迁移安全已考虑
- [ ] 热更兼容已考虑
- [ ] 数据安全（SA Log、防刷）已考虑
- [ ] 性能影响已评估
- [ ] 可直接用于生成 TODO 清单
- [ ] 符合 `system-dev-checklist.md` 规范

---

*指南版本: 1.0.0*
