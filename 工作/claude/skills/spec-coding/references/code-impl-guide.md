# 代码实现工作流指南（C7 游戏服务端）

> 定义从技术文档到代码实现的完整工作流。

---

## 1. 触发场景

当用户说以下内容时触发：
- "实现功能"
- "开始写代码"
- "继续实现 F00X"
- "按 TODO 实现"

**前置条件**：技术文档 `F00X-technical-design.md` 已存在。

---

## 2. 工作流程

```
技术文档已就绪
        ↓
Step 1: 生成 TODO 清单
        - 从技术文档提取任务
        - 生成 F00X-todo.md
        ↓
Step 2: 逐个实现 TODO
        - p4 edit 相关文件
        - 按顺序处理每个 TODO
        - 完成后更新状态
        ↓
Step 3: 运行测试
        - 通过 telnet 执行测试脚本
        - 修复问题
        ↓
完成
```

---

## 3. TODO 清单规范

### 3.1 TODO 清单模板

```markdown
# F00X 功能名称 - 实现进度

## 实现状态：进行中

| 状态符号 | 含义 |
|----------|------|
| 待开始 | 未开始 |
| 进行中 | 正在实现 |
| 已完成 | 已完成 |
| 已阻塞 | 有阻塞 |

---

## TODO 清单

| ID | 任务 | 状态 | 涉及文件 | 备注 |
|----|------|------|----------|------|
| 1 | 定义 Entity XML 属性 | 已完成 | `AvatarActor.xml`, `alias.xml` | |
| 2 | 实现 Component | 已完成 | `Logic/Components/XxxComponent.lua` | |
| 3 | 定义 RPC 协议 | 进行中 | `NetDefs/AvatarActor.xml` | |
| 4 | 挂载 Component | 待开始 | `Logic/Entities/ComponentDefine/...` | |
| 5 | 实现 Service | 待开始 | `Logic/Service/XxxService.lua` | |
| 6 | 常量定义 | 待开始 | `Logic/Const/XxxConst.lua` | |
| 7 | 策划配表接入 | 待开始 | TableData 访问 | |
| 8 | GM 命令 | 待开始 | `Logic/GM/...` | |
| 9 | 编写测试脚本 | 待开始 | `Test/test_xxx.lua` | |
| 10 | 代码规范 & Checklist 检查 | 待开始 | | 对照 lua-code-style + system-dev-checklist |

---

## 完成记录

### TODO-1: 定义 Entity XML 属性 - 已完成

**修改文件**: `Logic/Entities/AvatarActor.xml`
**说明**: 新增 xxxInfo 属性，类型 XXX_INFO

### TODO-2: 实现 Component - 已完成

**修改文件**: `Logic/Components/XxxComponent.lua`
**说明**: 实现 XxxComponent，包含初始化、核心逻辑、RPC 处理
```

### 3.2 TODO 拆分原则

| 原则 | 说明 |
|------|------|
| **单一职责** | 每个 TODO 只做一件事 |
| **可验证** | 每个 TODO 完成后可以独立验证 |
| **有序** | TODO 之间有依赖关系时，顺序正确 |
| **粒度适中** | 每个 TODO 覆盖一个文件或一组紧密关联的文件 |

### 3.3 C7 典型 TODO 顺序

```
1. 数据层（Entity XML + 类型定义）
   └─ Entity 属性定义（.xml）
   └─ 类型定义（alias.xml 或 DataTypes）
        ↓
2. 协议层（RPC 定义）
   └─ NetDefs XML 定义（CS/SC/SS）
        ↓
3. 常量层
   └─ 常量/枚举定义（Const/）
        ↓
4. 业务层（Component + Service）
   └─ Component 实现
   └─ Service 实现
   └─ Component 挂载
        ↓
5. 配表接入
   └─ TableData 访问代码
   └─ 配表后处理（如需要）
        ↓
6. 测试与收尾
   └─ GM 命令（方便 QA 测试）
   └─ 测试脚本
   └─ Checklist 检查
```

---

## 4. 实现规范

### 4.1 每个 TODO 的执行流程

```
1. 更新 TODO 状态为"进行中"
        ↓
2. p4 edit 相关文件（编辑已有文件）
        ↓
3. 阅读相关技术文档和参考代码
        ↓
4. 编写代码（遵循 lua-code-style.md）
        ↓
5. p4 add 新文件（新创建的文件）
        ↓
6. 更新 TODO 状态为"已完成"
        ↓
7. 记录完成说明
```

### 4.2 Perforce 操作

```bash
# 编辑已有文件前（必须先 checkout）
p4 edit Logic/Components/XxxComponent.lua

# 批量 checkout
p4 edit Logic/Components/XxxComponent.lua Logic/Entities/AvatarActor.xml NetDefs/AvatarActor.xml

# 新文件创建后
p4 add Logic/Components/NewComponent.lua

# 查看当前 checkout 文件
p4 opened
```

**P4 超时处理**：
- 轻量操作（edit/add）：15 秒超时
- 最多自动重试 2 次（共 3 次）
- 超时不阻断后续开发工作

### 4.3 代码规范要点

实现代码时**必须先阅读** `Server/docs/00-core/lua-code-style.md`，以下为核心要点：

**命名**：
- `kg_require` 模块名全小写下划线；文件 / 类名 CamelCase
- public 方法 `UpperCamelCase`，private `lowerCamelCase`
- RPC 函数：`CS/SC/SS` + 模块名 + 功能
- 常量 / 枚举 `ALL_UPPER_SNAKE`

**模块 & Hotfix 兼容**：
- 业务逻辑必须用 `kg_require`，只 require 到模块
- 禁止模块级 `local` 函数、`local` 常量
- 禁止在 table 中持有 function（存函数名代替）
- 禁止返回动态创建的匿名函数
- 回调使用字符串方法名（不用闭包，支持 Entity 迁移）

**日志**：
- 用 `self:logInfoFmt` / `logErrorFmt` / `logWarnFmt`
- 格式符统一 `%s`，table 用 `%v`，禁止 `%d` `%f`

**性能**：
- 频繁访问字段提前缓存为 local 局部变量
- 谨慎创建临时 table 和闭包
- 策划配置表数据不允许缓存（热更时无法更新）

**常见陷阱**：
- 判空用 `next(t) == nil`，不用 `#t == 0`
- `0` 和 `""` 在 Lua 中是 true
- 禁止 `pcall`，用 `custom_xpcall` 代替
- 持有 entityID 而非 Entity 引用

### 4.4 Changelist 描述规范

```
feat(F00X): TODO-{id} {任务简述}

- 具体改动说明
- 涉及文件列表
```

示例：
```
feat(F001): TODO-2 实现 GuildComponent

- 新增 GuildComponent，实现公会基础功能
- 包含创建公会、加入公会、退出公会逻辑
- 涉及文件: Logic/Components/GuildComponent.lua
```

---

## 5. 阻塞处理

当 TODO 被阻塞时：

1. 更新状态为"已阻塞"
2. 记录阻塞原因
3. 创建新的 TODO 解决阻塞问题或跳过
4. 向用户询问如何处理

```markdown
### TODO-3: 实现 Service 层 - 已阻塞

**阻塞原因**: 依赖客户端 UI 协议未确定
**处理方案**:
- 方案 A: 等待客户端协议确定
- 方案 B: 先按草案实现，后续调整
**用户决策**: 【待确认】
```

---

## 6. 测试验证

### 6.1 验证方式

C7 项目通过 **telnet debug console** 进行功能验证（详见 `server-debug` skill）：

```bash
# 通过 telnet_client.py 执行测试脚本
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "dofile(\"/Test/test_xxx.lua\")"

# 热更脚本后验证
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "refreshscript()"
```

### 6.2 GM 命令验证

为 QA 测试提供 GM 命令：
```lua
-- GM 命令示例
function XxxComponent:GMTestXxx(args)
    -- GM 测试逻辑
end
```

### 6.3 测试失败处理

使用 T/D/B 分类法：
- **T**: 测试脚本问题 → 修改测试脚本
- **D**: 测试文档/设计问题 → 修改文档
- **B**: 业务代码 Bug → 修改业务代码

---

## 7. 检查清单

### 7.1 代码规范检查（对照 `docs/00-core/lua-code-style.md`）

- [ ] 命名规范：文件/类 CamelCase，变量 lowerCamelCase，常量 ALL_UPPER_SNAKE
- [ ] 模块引入使用 `kg_require`，只 require 到模块
- [ ] 无模块级 `local` 函数和 `local` 常量
- [ ] 无 table 中持有 function、无动态创建匿名函数
- [ ] 回调使用字符串方法名（迁移安全 + 热更兼容）
- [ ] 日志格式正确（`logInfoFmt`，`%s`/`%v`，禁止 `%d` `%f`）
- [ ] 配表数据未被缓存
- [ ] 无 `pcall`，统一使用 `custom_xpcall`
- [ ] 持有 entityID 而非 Entity 引用

### 7.2 系统设计检查（对照 `references/system-dev-checklist.md`）

- [ ] 所有 TODO 已完成
- [ ] Entity XML 属性定义正确（类型、存盘标记、不修改已有类型）
- [ ] RPC 协议定义与实现一致，上行 RPC 有 CD 限制
- [ ] CS RPC 参数全部做了服务端校验
- [ ] 涉及数值修改有完整 SA Log（含 opNUID 串联）
- [ ] 重要操作后触发 `DoPersistent`
- [ ] 投放使用限次奖励，先标记再发放
- [ ] 购买流程：校验→扣币→发放
- [ ] DB 查询有索引，非实时查询设 `read_preference`
- [ ] 功能总开关 + 子开关就绪
- [ ] 高频操作无临时 table 创建，批量操作已分帧
- [ ] GM 命令可测试核心功能
- [ ] CHANGELOG 已更新

---

## 8. 常见问题

### Q: TODO 顺序可以调整吗？

可以，但要注意依赖关系。Entity XML 和 RPC 协议定义通常需要先完成，因为 Component/Service 实现依赖它们。

### Q: 实现过程中发现技术文档有误怎么办？

先修改技术文档，再继续实现。保持文档与代码一致。

### Q: 一个 TODO 太大怎么办？

拆分成多个小 TODO，如 `TODO-3a`、`TODO-3b`。

### Q: 需要修改其他系统的代码怎么办？

在涉及文件中标注，并在备注中说明跨系统影响。如果影响范围大，建议先和用户确认。

---

*指南版本: 1.0.0*
