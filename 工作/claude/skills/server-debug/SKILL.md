---
name: server-debug
description: 当用户要求调试服务器、在服务端执行 Lua 指令、telnet 连接服务器进程、查看服务器运行时数据、查询玩家/Entity/Service 状态时使用此技能。
---

## 概述

通过 telnet 连接到服务器进程的 Debug Console，实时执行 Lua 语句进行服务器调试。

## 连接方式

### 1) 读取配置

首先读取 `Server/config/conf_personal_base.json`，获取目标进程的 console 配置：

```json
{
    "logic_0": {
        "console": { "ip": "127.0.0.1", "port": 8882 }
    },
    "logic_1": {
        "console": { "ip": "127.0.0.1", "port": 8883 }
    },
    "cluster_manager": {
        "console": { "ip": "127.0.0.1", "port": 8881 }
    }
}
```

### 2) Telnet 连接

#### 推荐方式：使用技能自带的 telnet_client.py（跨平台）

本技能目录下提供了 `telnet_client.py` 脚本，已处理所有已知的连接坑点（CRLF 行结尾、telnet 协商字节清洗、MSYS 路径改写规避、`<end>` 标记等待），**Windows / Linux / Mac 通用**，是执行调试命令的首选方式。

脚本位置：`Server/script_lua/.claude/skills/server-debug/telnet_client.py`

```bash
# 基本用法（默认连接 logic_0，端口 8882，超时 15 秒）
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "print('hello')"

# 执行测试脚本
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "dofile(\"/Test/test_xxx.lua\")"

# 指定进程和超时（长脚本建议加大超时）
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "dofile(\"/Test/test_xxx.lua\")" --port 8883 --timeout 60

# 快速查询
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "getplayers()"
```

**参数说明**：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `command`（位置参数） | 无（必填） | 要执行的 Lua 命令 |
| `--host` | `127.0.0.1` | 服务器地址 |
| `--port` | `8882` | Debug Console 端口（8882=logic_0, 8883=logic_1, 8881=cluster_manager） |
| `--timeout` | `15` | 超时秒数，长脚本（如100次抽奖测试）建议设 30-60 |

> **注意**：
> - 在 Git Bash / MSYS 环境下，必须加 `MSYS_NO_PATHCONV=1` 前缀防止路径改写。
> - 测试文件不用加到 P4，本地新增之后直接运行测试即可。
> - 默认连接 `logic_0`（端口 8882），除非用户指定了其他进程。

#### Linux/Mac 系统（备选）

```bash
# 交互式
telnet 127.0.0.1 8882

# 脚本化（nc）
(echo 'dofile("/Test/xxx.lua")'; sleep 2) | nc 127.0.0.1 8882
```

#### Windows 系统（备选：PowerShell）

```powershell
powershell -Command "
\$client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 8882)
\$stream = \$client.GetStream()
\$writer = New-Object System.IO.StreamWriter(\$stream)
\$reader = New-Object System.IO.StreamReader(\$stream)
\$writer.WriteLine('dofile(\"/Test/your_script.lua\")')
\$writer.Flush()
Start-Sleep -Seconds 2
while (\$stream.DataAvailable) {
    \$line = \$reader.ReadLine()
    Write-Output \$line
}
\$client.Close()
"
```

> **注意**：PowerShell 方式不会自动等待 `<end>` 标记，长脚本可能截断输出，推荐优先使用 `telnet_client.py`。

### 3) 命令执行机制

telnet 控制台的实现细节见 `Engine/Utils/DebugConsole.lua`（即 `Engine.Utils.DebugConsole` 模块）。

**命令执行流程**（`onDebugCmd` 函数）：
1. 首先尝试将输入作为**表达式**求值（`local temp = <input>`），如果成功则用 `tprint` 打印结果
2. 如果表达式解析失败，则作为**语句**直接执行
3. 所有在 telnet session 中定义的 local 变量会被保留到 `_script.debug_info[cid]._local` 中，跨命令持久化
4. 输出通过重定向的 `print` 函数回传给 telnet 客户端
5. 每条输出以 `<end>` 标记结束

**环境链**（metatable 查找顺序）：
```
session._local → debug_shortcuts → _G
```
这意味着在 telnet 中可以**直接调用**快捷方式函数，无需前缀。

## 内置快捷指令

以下函数在 telnet 中可直接调用（定义在 `debug_shortcuts` 中）：

### Entity/Player 查询

| 命令 | 说明 | 示例 |
|------|------|------|
| `getplayers()` | 列出当前进程所有在线玩家 | `getplayers()` |
| `getplayers(nameOrID)` | 按名字或 ID 查找玩家 | `getplayers("张三")` |
| `findplayer(name)` | 按角色名查找 AvatarActor | `findplayer("syz6")` |
| `getaccounts(nameOrId)` | 查找 Account 实体 | `getaccounts()` |
| `getentity(typeName)` | 按类型名查找所有实体 | `getentity("MonsterActor")` |
| `getoneentity(typeName)` | 按类型名查找单个实体 | `getoneentity("MonsterActor")` |
| `getservice(ServiceName)` | 查找所有同名 Service 实体 | `getservice("TeamMatchService")` |
| `getxservice(ServiceName)` | 同上，但若只有一个则直接返回该实体 | `getxservice("FriendClubService")` |

### 脚本热更新

| 命令 | 说明 |
|------|------|
| `refresh()` | 重载所有数据 + 刷新所有脚本 |
| `reloaddata()` | 仅重载所有数据（Excel 等） |
| `reloadincrdata(pathes)` | 增量重载指定数据表，路径用 `;` 分隔 |
| `refreshscript()` | 仅刷新当前进程所有脚本 |
| `refreshchangedscript()` | 仅刷新有变更的脚本 |
| `refreshalllogic()` | 刷新所有 logic 进程的脚本 |

### 文件执行

| 命令 | 说明 |
|------|------|
| `dofile()` | 执行 `/Test/dbg.lua`（默认） |
| `dofile("/Test/xxx.lua")` | 执行指定的测试脚本 |

`dofile` 的关键特性：
- 文件中定义的 **local 变量会保留**在当�� telnet session 中，后续命令可继续使用
- 可以在 `Test/` 目录下新建测试脚本，然后通过 `dofile("/Test/filename.lua")` 执行

### 性能分析

| 命令 | 说明 |
|------|------|
| `profilestart()` | 开始性能采集 |
| `profilestop(topNum)` | 停止采集并输出 Top N 结果（默认 10） |
| `profilereset()` | 重置采集数据 |

### 远程调试 (EmmyLua)

| 命令 | 说明 |
|------|------|
| `dbglisten()` | 启动 EmmyLua 远程调试监听（logic_N 监听端口 8866+N） |

### 其他

| 命令 | 说明 |
|------|------|
| `help()` | 列出所有可用的快捷指令 |

## 重要的运行时全局对象

在 telnet 中可直接访问以下对象：

| 对象 | 说明 |
|------|------|
| `_script.entities` | 当前进程下所有 entity 的表（entID → entity） |
| `_script.ientities` | 按 iid 索引的 entity 表 |
| `_script.process_id` | 当前进程 ID |
| `_script.process_name` | 当前进程名（如 `"logic_0"`） |
| `Game.AvatarActors` | 所有在线玩家的 ID 集合 |
| `Game.TimeInSecCache` | 服务器当前时间（秒级缓存） |
| `Game.Process` | 进程管理对象，可用于跨进程调用 Service |
| `TableData` | 所有 Excel 配置表数据的入口 |
| `Enum` | 枚举定义集合 |

## Entity 与 Component 访问方式

### Component 数据和函数的访问

**重要特性**：Component 上的数据和函数都是**平铺在 Entity 上**的，可以直接通过 Entity 访问。

```lua
-- 获取玩家
local p = findplayer("玩家名")

-- ✓ 正确：直接访问组件的函数和数据（推荐）
p:_doAppearanceLotteryDraw(...)  -- 调用 AppearanceLotteryComponent 的函数
local invInfo = p.invInfo         -- 访问 InventoryComponent 的数据
local equipSlots = p.equipmentSlotInfo  -- 访问 EquipComponent 的数据

-- ✗ 错误：不要尝试通过 p.ComponentName 访问
-- p.AppearanceLotteryComponent  -- 这样访问不到
-- p:getComponent("AppearanceLotteryComponent")  -- 这个方法不存在
```

### 常见 Entity 类型及其组件

**AvatarActor（玩家角色）** 常用组件数据/方法：
- `invInfo` - 背包数据（InventoryComponent）
- `equipmentSlotInfo` - 装备槽数据（EquipComponent）
- `friendList` - 好友列表（FriendComponent）
- `guildID` - 公会ID（GuildComponent）
- `questInfo` - 任务数据（QuestComponent）
- `achievementInfo` - 成就数据（AchievementComponent）
- `:ReqExtraGM(cmd, args)` - 执行 GM 命令（GMComponent）
- `:Die(reason)` - 角色死亡（ActorBase）
- `:Logout(...)` - 登出（LoginComponent）

**Service** 访问：
```lua
-- 获取 Service 实例
local svc = getxservice("TeamMatchService")

-- 访问 Service 的数据和方法
local matchPool = svc.teamMatchPool
svc:SomeMethod(...)
```

详细的 Entity-Component 架构说明参见 `.claude/skills/references/project-framework.md`。

## `kg_require` 注意事项

`kg_require` 与标准 `require` 的区别：
- `kg_require` 返回的是 require 之后的**整个 env 环境**，而非模块的返回值
- 在 telnet 中使用 `kg_require` 引入模块时，需要注意获取正确的对象

```lua
-- 示例：使用 kg_require 获取工具模块
local utils = kg_require("Common.Utils.CommonUtils")
-- utils 是整个环境，里面包含模块导出的所有内容
print(utils.tprint(someTable))
```

## 调试工作流建议

### 查询玩家数据
```lua
-- 1. 找到玩家
local p = findplayer("玩家名")
-- 2. 查看组件数据
local utils = kg_require("Common.Utils.CommonUtils")
print(utils.tprint(p.equipmentSlotInfo))
-- 3. 调用玩家方法
p:ReqExtraGM("SwitchMap", _script.cjson.encode({MapID=5209996}))
```

### 查询 Service 数据
```lua
-- 获取 Service 实例
local svc = getxservice("TeamMatchService")
-- 查看 Service 内部状态
local utils = kg_require("Common.Utils.CommonUtils")
print(utils.tprint(svc.teamMatchPool))
```

### 编写并执行测试脚本
1. 在 `Test/` 目录下新建 Lua 文件（如 `Test/my_test.lua`）
2. 在 telnet 中执行 `dofile("/Test/my_test.lua")`
3. 脚本中的 local 变量会保留，可以在后续命令中继续使用

### Telnet 常见坑

1. **命令必须用 CRLF 结尾**
   - 调试 console 对换行比较敏感
   - 如果只发 `\n`，经常会出现“只回显输入、不返回执行结果、也没有 `<end>`”的假象
   - 建议脚本化发送时统一使用 `\r\n`

2. **Git Bash / MSYS 可能改写 `/Test/...` 路径**
   - 在 bash 环境下执行 `dofile("/Test/xxx.lua")` 时，MSYS 可能把它改成类似 `C:/Program Files/Git/Test/xxx.lua`
   - 出现这种情况时：
     - 优先加 `MSYS_NO_PATHCONV=1`
     - 或直接用 Python `telnetlib` / 原生 socket 连接，绕开 shell 路径转换

3. **console 输出可能带 telnet 协商字节和 ANSI 控制字符**
   - 裸读 socket 时，输出里可能混有 `\xff...` 协商字节和 `\x1b[K` 之类的控制序列
   - 如果要脚本化解析结果，建议先做清洗，或者直接复用现成测试脚本/客户端

4. **先验证“命令是否真的执行”**
   - 在怀疑连接或回车格式有问题时，先执行 `1+1`、`help()`、`print("ok")` 这类最小命令
   - 只有看到返回值和 `<end>`，再继续跑复杂脚本

5. **异步接口调试时，先测入口，再直接测回调**
   - 如果入口没有明显报错，但业务结果没变化，建议直接手工调用回调函数
   - 这样能快速判断问题是在“异步链路前半段”，还是在“回调后的业务逻辑”

### 跨进程调用
```lua
-- 在 logic_0 中向其他 logic 进程发送调试命令
_script.sendServerMsg(targetProcessID, "DoRemoteDebugCmd", 1, "refreshscript()")

-- 通过 Process 调用 Service
Game.Process:CallService("GlobalDataService", "SSReqModifySwitches", nil, nil):Args(logicServerID, modifySwitches)
```

## 使用此技能时的行为指南

1. **连接前**：先读取 `config/conf_personal_base.json` 获取正确的端口
2. **默认目标**：如用户未指定进程，默认连接 `logic_0`
3. **连接方式**：
   - **首选**：使用技能自带的 `telnet_client.py`（跨平台，已处理所有已知坑点）
   - 备选 Linux/Mac：`telnet` 或 `nc`
   - 备选 Windows：PowerShell `TcpClient`
4. **命令执行**：
   - 简单命令直接通过 `telnet_client.py` 的 `command` 参数传入
   - 复杂调试逻辑在 `Test/` 目录下创建脚本文件，通过 `dofile` 执行
   - 长时间运行的脚本（如批量测试）使用 `--timeout 30` 或更大值
5. **MSYS 环境**：在 Git Bash 下执行时，必须加 `MSYS_NO_PATHCONV=1` 前缀
6. **安全意识**：避免执行可能导致服务器崩溃的操作（如大量循环创建对象、修改核心数据结构）
7. **输出格式**：使用 `utils.tprint()` 格式化复杂表结构的输出

## 实战示例

### 示例1：查看在线玩家装备栏

创建测试脚本 `Test/check_equipment.lua`：

```lua
local utils = kg_require("Common.Utils.CommonUtils")
local players = getplayers()

if not players or #players == 0 then
    print("没有在线玩家")
    return
end

print("=== 在线玩家装备信息 ===")

for i, p in pairs(players) do
    print("\n玩家: " .. (p.Name or "未知") .. " (ID: " .. tostring(p.id) .. ")")

    if p.equipmentSlotInfo then
        print("\n装备槽信息:")
        print(utils.tprint(p.equipmentSlotInfo))
    else
        print("  无装备槽信息")
    end
end
```

**执行方式**（通用）：

```bash
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "dofile(\"/Test/check_equipment.lua\")"
```

**备选 - Linux 交互式**：

```bash
telnet 127.0.0.1 8882
# 然后输入: dofile("/Test/check_equipment.lua")
```

### 示例2：组件函数单元测试（外观抽奖）

本技能目录下 `examples/` 包含可直接复用的测试脚本模板。

**示例脚本**：`examples/test_appearance_lottery_draw.lua`

该脚本演示了对 `AppearanceLotteryComponent:_doAppearanceLotteryDraw` 的完整单元测试，覆盖以下场景：

| 测试项 | 说明 |
|--------|------|
| 基本功能 | 验证返回值完整性（lotteryResultID、quality、itemID、bConverted） |
| 绑定/非绑定 | 验证 `isCostItemBind` 对产出绑定位的影响 |
| 奖池限制计数 | 验证 `dayCount`/`totalCount`/`weekMaxDayCount` 累加 |
| 保底计数 | 验证 SSR/SR/R 不同品质命中时保底计数的更新逻辑 |
| 连抽累加 | 验证 `resultItemMap`/`clientResultMap` 多次调用的累加正确性 |
| 道具转换 | 验证 `NumLimit` 达到上限后的道具转换机制 |
| 品质分布 | 100次采样统计 SSR/SR/R 概率分布 |
| 保底必中 | 设置保底计数到上限-1，验证下一抽必出 SSR |

**使用方式**：

1. 将脚本复制到 `Server/script_lua/Test/` 目录：
   ```bash
   cp .claude/skills/server-debug/examples/test_appearance_lottery_draw.lua Test/test_appearance_lottery_draw.lua
   ```
2. 通过 telnet 执行：
   ```
   dofile("/Test/test_appearance_lottery_draw.lua")
   ```

**编写类似测试脚本的要点**：

1. **数据备份与恢复**：测试前深拷贝相关属性，每个测试用例结束后恢复，避免污染玩家数据
2. **断言函数**：使用 `assertEqual`/`assertNotNil`/`assertTrue`/`assertGTE` 统一输出格式
3. **错误捕获**：用 `custom_xpcall` 包裹被测函数调用，防止异常中断整个测试
4. **自动查找测试数据**：从配置表中自动查找可用的测试参数（如抽奖池ID），而非硬编码
5. **结果汇总**：测试结束输出通过/失败数量和失败详情
