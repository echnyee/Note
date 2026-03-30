# 项目框架说明

## 1. 服务器架构

本项目是一个多进程游戏服务器，包括四种不同的进程：

| 进程 | 职责 |
|------|------|
| **logic** | 承载具体业务逻辑，运行 Lua 脚本 |
| **router** | 负责路由分发，处理客户端连接，将消息转发到对应 logic 进程 |
| **cluster_manager** | 负责集群管理，集群内进程的健康检查等 |
| **db_manager** | logic 进程与数据库的交互通过 db_manager 进程代理 |

引擎层（C++）提供基础服务和通用组件，业务层使用 Lua 脚本开发，运行在 logic 进程。

## 2. 目录结构

```
script_lua/
├── Engine/          # 引擎层 Lua 框架
│   ├── Framework/   # 核心框架（EntityBase、Service、日志等）
│   │   ├── EntityBase.lua          # Entity 基类
│   │   ├── Service/                # Service 框架
│   │   │   ├── Service.lua         # Service 基类
│   │   │   ├── CallServiceWrapper.lua    # Service 调用封装
│   │   │   ├── CallMultiServiceWrapper.lua # 多 Service 调用封装
│   │   │   ├── Accessor.lua        # Service 寻址
│   │   │   └── ServiceContext.lua  # Service 上下文
│   │   ├── Log.lua                 # 日志系统
│   │   ├── GlobalFunctions.lua     # 全局函数
│   │   ├── GlobalUtils.lua         # 全局工具
│   │   └── ScriptRefresh.lua       # 脚本热更新
│   ├── Config/      # 服务器配置
│   │   ├── LogicConfig.lua         # Logic 进程配置
│   │   ├── ServiceConfig.lua       # Service 配置
│   │   └── CrossServerConfig.lua   # 跨服配置
│   ├── Lib/         # 引擎级通用库
│   ├── Utils/       # 引擎工具（LogicServerUtils 等）
│   └── Loader.lua   # 模块加载入口
│
├── Logic/           # 业务层逻辑
│   ├── Entities/    # Entity 定义
│   │   ├── AvatarActor.lua         # 玩家角色
│   │   ├── NpcActor.lua            # NPC
│   │   ├── Account.lua             # 账号
│   │   ├── ActorBase.lua           # Actor 基类（战斗实体）
│   │   ├── Process.lua             # 进程 Entity
│   │   ├── DBProxy.lua             # 数据库操作代理
│   │   ├── ComponentDefine/        # Entity 组件挂载定义
│   │   ├── SceneEntities/          # 场景物件 Entity
│   │   ├── Space/                  # 场景 Space Entity
│   │   ├── Worlds/                 # 世界 Entity（副本、大世界等）
│   │   └── Guilds/                 # 公会相关 Entity
│   ├── Components/  # 组件实现（约 180+ 个组件 挂载在 Entity 上）
│   ├── Service/     # Service 实现（约 40+ 个服务 跨 Entity 逻辑）
│   ├── Class/       # 工具类和管理器
│   ├── Combat/      # 战斗系统（技能、Buff、被动技能等）
│   ├── Const/       # 常量定义
│   ├── GM/          # GM 命令
│   ├── Quest/       # 任务系统
│   ├── Utils/       # 业务工具函数
│   ├── init.lua     # Logic 层初始化入口
│   └── Preload.lua  # 预加载
│
├── Common/          # 跨层通用代码
│   ├── Lib/         # 第三方库（lume、JSON、crc32、inspect 等）
│   ├── DataStruct/  # 数据结构（TimeWheel、Heap、Queue、LinkedList 等）
│   ├── Utils/       # 通用工具
│   └── Const.lua    # 通用常量
│
├── Data/            # 策划配置数据
│   ├── Excel/       # 策划导表数据
│   ├── Flowchart/   # 流程图配置
│   ├── Quest/       # 任务配置
│   ├── SkillData/   # 技能数据
│   └── ...          # 其他数据
│
└── Hotfix/          # 热修复
    ├── Version/     # Hotfix 文件存放
    ├── manifest.json # Hotfix 清单
    └── README.md    # Hotfix 规范说明
```

## 3. 核心概念

### 3.1 Entity（实体）

游戏中所有对象的抽象，玩家、怪物、NPC、场景、服务都是 Entity。

**定义方式**：
```lua
-- 定义 Entity，指定基类和挂载的组件
XxxEntity = DefineEntity("XxxEntity", { 基类 }, { 组件列表 })
```

**Entity Def（XML 定义文件）**：每个 Entity 对应一个同名 XML 文件（如 `AvatarActor.xml`），定义：
- 属性及其类型（类型定义在 `alias.xml` 中）
- `ClientMethods`：暴露给客户端调用的 RPC 方法
- `ServerMethods`：暴露给 logic 进程间调用的 RPC 方法

**继承层次**：
```
EntityBase                    # 所有 Entity 的基类
├── ActorBase                 # 战斗实体基类（有位置、血量等）
│   ├── AvatarActor           # 玩家角色
│   ├── NpcActor              # NPC/怪物
│   ├── Transport             # 载具
│   └── SceneEntities/*       # 场景物件（触发器、战斗区域等）
├── World                     # 世界基类
│   ├── Dungeon               # 副本
│   ├── Plane                 # 位面
│   ├── Homeland              # 家园
│   └── ...                   # 其他世界类型
├── Space                     # 场景空间基类
│   ├── MainCitySpace         # 主城
│   ├── DungeonSpace          # 副本空间
│   └── ...                   # 其他空间类型
├── Account                   # 账号
├── Process                   # 进程 Entity
├── DBProxy                   # 数据库代理
├── Guild                     # 公会
└── Service（见 3.3 节）       # 服务
```

**生命周期**：
- `ctor()` → 构造函数，属性初始化
- `__after_ctor_or_migrate()` → 构造或迁移后的初始化
- `onInit()` → 初始化完成
- `onProxyReady()` → 代理就绪
- `onFini()` → 清理
- `dtor()` → 析构

**迁移**：
- entity可能会在不同logic进程间迁移，- 迁移时会触发 `onMigrateOut()` 和 `onMigrateIn()` 回调
- 项目中只有AvatarActor会迁移，在处理timer和数据库回调时要考虑迁移的影响，一般回调不能传递一个lua闭包

### 3.2 Component（组件）

Entity 的组成部件，每个 Component 实现一组相关功能，挂载到 Entity 上生效。

**定义方式**：
```lua
XxxComponent = DefineComponent("XxxComponent")

function XxxComponent:onInit()
    -- 组件初始化
end
```

**挂载方式**（在 `ComponentDefine/` 下）：
```lua
componentList = {
    kg_require("Logic.Components.LoginComponent").LoginComponent,
    kg_require("Logic.Components.Bag.BagComponentV2").InventoryComponent,
    -- ...
}
AvatarActor = DefineEntity("AvatarActor", { ActorBase }, componentList)
```

**常见组件分类**：
- 属性系统：`PropComponent`、`FightPropComponent`
- 背包/道具：`InventoryComponent`、`ItemComponent`、`MoneyComponent`、`EquipComponent`
- 社交：`FriendComponent`、`GuildComponent`、`ChatComponent`、`PartyComponent`
- 战斗：`SkillListComponent`、`BuffComponentNew`、`TakeDamageComponent`
- 场景：`MoveComponent`、`DungeonComponent`、`WorldComponent`
- 系统：`LoginComponent`、`HotfixComponent`、`GMComponent`

### 3.3 Service（全局服务）

一类特殊的 Entity，继承自 `Service` 基类，提供全局性功能。同一类 Service 可以有多个 Shard，通过 `shardIndex` 区分，分布在不同 logic 进程上。

**定义方式**：
```lua
local service = kg_require("Engine.Framework.Service.Service")
XxxService = DefineEntity("XxxService", { service.Service })

function XxxService:ctor()
    -- 初始化
end

function XxxService:onServiceInit(finishCB)
    -- 服务初始化完成后调用 finishCB(true)
end
```

**调用 Service**：
```lua
-- 基本调用（不带回调）
self:CallService("OnlineService", "MethodName", serialKey, nil):Args(arg1, arg2)

-- 带回调调用
self:CallService("OnlineService", "MethodName", serialKey, "OnCallbackName"):Args(arg1, arg2)

-- 调用所有 Shard
self:CallAllService("OnlineService", "MethodName", "OnCallbackName"):Args(arg1, arg2)

-- 向指定逻辑服的所有 Shard 发送（不带回包）
self:SendAllShardService("OnlineService", "MethodName", nil, arg1, arg2)
```

**常见 Service**：
`OnlineService`、`WorldService`、`GuildService`、`FriendService`、`ChatServiceLua`、`RankServiceV2`、`DataCenterService`、`RouterService`、`LoginQueueService` 等

### 3.4 异步 RPC

所有 RPC 调用都是异步的：

| 方向 | 说明 |
|------|------|
| Client → Logic | Router 将客户端消息转发给 Logic 进程 |
| Logic → Logic | Logic 进程间通过 Service 调用通信 |
| Logic → DB | Logic 通过 DBProxy/db_manager 访问数据库 |

**注意事项**：
- 回调执行时必须检查对象有效性（Entity 可能已销毁或迁移）
- 使用 `custom_xpcall` 而非 `pcall` 进行安全调用
- 迁移场景下，callback 必须使用字符串形式（方法名），不能用闭包

### 3.5 Class 系统

使用 `DefineClass` 定义普通类：
```lua
MyClass = DefineClass("MyClass", ParentClass)

function MyClass:ctor()
    -- 构造函数
end
```

## 4. 关键系统

### 4.1 模块加载

使用 `kg_require` 加载模块（支持热更新追踪），路径使用 `.` 分隔：
```lua
local module = kg_require("Logic.Components.LoginComponent")
```

**模块隔离**：`kg_require` 内部封装了模块加载环境，模块内声明的全局变量不会污染 `_G`，而是作为模块级别的全局变量存在，外部通过返回的 module table 访问。

### 4.2 配置表（TableData）

Data/Excel/TableData.lua` — 数据表访问接口（自动生成，勿手动修改）
策划数据通过 `TableData` 全局接口访问：

```lua
local row = TableData.GetXxxDataRow(id)   -- 可能返回 nil，必须检查
local value = TableData.GetConstDataRow("CONST_KEY")
```

### 4.3 数据库

- **MongoDB**：持久化存储，通过 `DBProxy` Entity 代理访问
- **Redis**：缓存数据库

**DBProxy 常用操作**：
```lua
-- 从数据库创建 Entity
DBProxy:CreateEntityFromDB(dbName, colName, entityType, entityID, canMigrate, callback)

-- 数据库操作回调格式：callback(res)，res[1] 为 bool 表示成功/失败
```

### 4.4 日志系统

Entity 内使用实例方法（自动带 Entity 上下文信息）：
```lua
self:logInfo("message")
self:logInfoFmt("format %s %s", arg1, arg2)     -- 推荐：使用 format API
self:logWarnFmt("warning %s", arg)
self:logErrorFmt("error %s", arg)
```

全局日志函数：
```lua
LOG_INFO(...)
LOG_INFO_FMT(format, ...)
LOG_WARN(...)
LOG_ERROR(...)
```

**规范**：禁止使用 `print`；格式符统一使用 `%s`（table 用 `%v`），禁止 `%d`、`%f`

### 4.5 定时器

```lua
-- 添加定时器（秒，是否循环，回调方法名）
self:addTimerEx(seconds, isLoop, "CallbackMethodName")

-- 序列化定时器（支持迁移）
self:addSerializeTimer(isLoop, seconds, 0, "CallbackMethodName", userData)
```

### 4.6 广播

```lua
-- 广播到本逻辑服所有 Entity
self:BroadcastRpc("MethodName", arg1, arg2)

-- 向指定 Entity 列表发送 RPC
self:SendEntitiesRpc(entityIDs, "MethodName", rpcArgs)

-- 向指定 Entity 列表发送客户端 RPC
self:SendEntitiesClientRpc(entityIDs, "MethodName", rpcArgs)
```

### 4.7 热更新（Hotfix）

支持不停服热修复，通过 `Hotfix/` 目录管理：

```lua
-- Component 方法热更新
HotfixComponentFunction("XxxComponent", "MethodName", newFunction)

-- Entity 方法热更新
local mod = kg_require("LogicScript.Entities.AvatarActor")
mod.AvatarActor.MethodName = function(self, ...) end

-- 模块方法热更新
local utils = kg_require("Shared.Utils")
utils.FuncName = function(...) end
```

脚本热更新通过 `ScriptRefresh.refreshAllScript()` 重新加载所有已加载模块。
**重要**：允许业务脚本更改refresh后不兼容，只需要确保写法上可热更，Hotfix目录下的代码才需要保证运行时兼容。

### 4.8 全局对象

| 全局变量 | 说明 |
|----------|------|
| `Game` | 游戏全局上下文，包含各种管理器和配置 |
| `_script` | 引擎脚本接口，提供底层 API |
| `Enum` | 枚举定义集合 |
| `TableData` | 策划配置数据接口 |
| `FVector` / `FRotator` | 数学向量/旋转 |

### 4.9 Entity 寻址与 Mailbox

Entity 之间通过 `mailbox` 进行远程调用：
```lua
mailbox:callLuaEntity("MethodName", ...)              -- 调用 Lua Entity 方法
mailbox:callLuaEntityWithCallback("MethodName", cbInfo, ...)  -- 带回调调用
```

Service 寻址通过 `Game.Accessor` 获取 mailbox：
```lua
local mailbox, shardIndex = Game.Accessor:getServiceMailbox(serviceName, serialKey, logicServerID)
```
