# Debug 调试指南（C7 游戏服务端）

> 定义基于日志和 telnet 的服务端调试工作流。
>
> **注意**：telnet 连接和调试命令的详细用法参见 `server-debug` skill。本指南聚焦于调试思路和流程。

---

## 1. 触发场景

当用户说以下内容时触发：
- "帮我调试一下这个功能"
- "查看日志"
- "这个功能报错了"
- "加一些 debug 日志"
- "定位一下这个问题"

---

## 2. 调试工作流

```
用户报告问题
        ↓
Step 1: 问题理解
        - 什么现象？（报错 / 数据异常 / 无响应）
        - 期望行为是什么？
        - 实际行为是什么？
        - 哪个进程？（logic_0 / logic_1 / cluster_manager）
        ↓
Step 2: 定位代码
        - 找到相关 Component / Service / Entity
        - 理解相关 RPC 调用链
        - 检查配表数据
        ↓
Step 3: 添加诊断日志
        - 在关键节点添加日志
        - 热更脚本使诊断日志生效
        ↓
Step 4: 复现和分析
        - 通过 telnet 或客户端操作复现
        - 查看服务器日志输出
        - 定位问题根因
        ↓
Step 5: 修复问题
        - 修改代码
        - 热更验证修复
        ↓
Step 6: 清理日志（可选）
        - 移除临时调试日志
        - 保留有价值的日志
        ↓
完成
```

---

## 3. C7 日志规范

### 3.1 Entity 内日志（推荐）

Entity 和 Component 内使用实例方法（自动带 Entity 上下文信息）：

```lua
self:logInfoFmt("[XxxComponent.MethodName] 描述, param=%s", param)
self:logWarnFmt("[XxxComponent.MethodName] 警告, state=%s", state)
self:logErrorFmt("[XxxComponent.MethodName] 错误, err=%s", err)
```

### 3.2 全局日志

非 Entity 上下文使用全局日志：

```lua
LOG_INFO_FMT("[ModuleName.funcName] 描述, param=%s", param)
LOG_WARN_FMT("[ModuleName.funcName] 警告")
LOG_ERROR_FMT("[ModuleName.funcName] 错误")
```

### 3.3 日志格式要求

| 规则 | 说明 |
|------|------|
| 格式符统一 `%s` | 数字、字符串统一用 `%s` |
| table 用 `%v` | table 类型参数用 `%v` 自动序列化 |
| 禁止 `%d` `%f` | 不使用 `%d`、`%f` 格式符 |
| 禁止 `print` | 业务代码禁止使用 `print` |
| 禁止字符串拼接 | 使用 Fmt 系列函数，不要 `..` 拼接 |

### 3.4 关键日志点

| 位置 | 日志内容 |
|------|----------|
| RPC 入口 | CS RPC 接收参数 |
| 前置检查失败 | 失败原因和参数 |
| 核心业务分支 | 进入哪个逻辑分支 |
| Service 调用前 | 调用的 Service 和参数 |
| Service 回调 | 回调结果 |
| DB 操作前后 | 查询条件和返回结果 |
| 异常捕获 | 错误信息和上下文 |
| 数值变更 | 变更前值、变更后值、来源 |

---

## 4. 通过 telnet 调试

### 4.1 热更脚本

修改代码后，通过 telnet 热更使修改生效：

```bash
# 刷新所有脚本
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "refreshscript()"

# 仅刷新有变更的脚本
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "refreshchangedscript()"
```

### 4.2 实时查询

```lua
-- 查找玩家
local p = findplayer("玩家名")

-- 查看组件数据
local utils = kg_require("Common.Utils.CommonUtils")
print(utils.tprint(p.xxxInfo))

-- 查看 Service 状态
local svc = getxservice("XxxService")
print(utils.tprint(svc.xxxData))
```

### 4.3 手工触发逻辑

```lua
-- 直接调用组件方法
local p = findplayer("玩家名")
p:MethodName(arg1, arg2)

-- 通过 GM 命令触发
p:ReqExtraGM("CmdName", _script.cjson.encode({param1=value1}))
```

---

## 5. 常见问题定位

### 5.1 CS RPC 无响应

```
检查顺序：
1. 客户端请求是否发出？（抓包/客户端日志）
2. 服务器是否收到？（RPC 入口日志）
3. 参数校验是否通过？
4. 业务逻辑执行到哪一步？
5. SC RPC 是否正确推送？
```

### 5.2 数据不一致

```
检查顺序：
1. Entity 属性值是什么？（telnet 查询）
2. 数据库里的值是什么？
3. 客户端显示的值是什么？
4. 数据同步 RPC 是否正确推送？
5. 是否有迁移导致的数据丢失？
```

### 5.3 Service 调用失败

```
检查顺序：
1. Service 是否正常启动？（getservice/getxservice）
2. Shard 路由是否正确？（serialKey）
3. 调用参数是否正确？
4. Service 内部逻辑是否报错？
5. 回调是否正确处理？
```

### 5.4 迁移相关问题

```
检查顺序：
1. 迁移前后 Entity 属性是否一致？
2. 是否有闭包回调在迁移后失效？
3. 定时器是否使用了 addSerializeTimer？
4. 异步操作回调是否检查了 Entity 有效性？
```

### 5.5 配表数据问题

```
检查顺序：
1. TableData 返回值是否为 nil？（配表 ID 是否正确）
2. 配表字段名是否正确？
3. 配表是否已重载？（reloaddata()）
4. 是否有配表后处理逻辑异常？
```

---

## 6. 调试报告模板

```markdown
# 问题调试报告

## 1. 问题描述

**现象**: [用户描述的问题]
**期望行为**: [应该是什么样]
**实际行为**: [实际是什么样]
**影响范围**: [影响哪些玩家/功能]

## 2. 复现步骤

1. 步骤一
2. 步骤二
3. ...

## 3. 调试过程

### 3.1 添加的日志

| 位置 | 日志内容 | 观察结果 |
|------|----------|----------|
| `XxxComponent:Method` L10 | RPC 入口参数 | 参数正常 |
| `XxxComponent:Method` L25 | 条件判断 | 进入了错误分支 |

### 3.2 关键发现

- 发现 1：...
- 发现 2：...

## 4. 根因分析

**根本原因**: [问题的根本原因]
**代码位置**: `Logic/Components/XxxComponent.lua` 第 N 行

## 5. 修复方案

**修改内容**: [具体修改]
**修改文件**: `Logic/Components/XxxComponent.lua`

## 6. 验证结果

- [x] 问题已修复
- [x] 相关功能正常
- [x] 热更验证通过
- [x] 无新增问题
```

---

## 7. 调试最佳实践

### 7.1 推荐做法

- 先理解代码逻辑和 RPC 调用链，再添加日志
- 日志要有上下文（Component 名、方法名、关键参数）
- 利用 telnet 实时查询 Entity/Service 状态
- 利用热更快速迭代（改日志 → refreshscript → 复现 → 分析）
- 修复后通过 telnet 验证，再提交代码

### 7.2 禁止做法

- 不看日志就猜测问题
- 添加无意义的日志（如只打印 'here'）
- 日志中使用 `%d` `%f` 格式符
- 使用 `print` 而非 `logInfoFmt`
- 使用 `pcall` 而非 `custom_xpcall`
- 修复后不验证就提交
- 修改核心数据结构进行调试（可能导致服务器崩溃）

---

*指南版本: 1.0.0*
