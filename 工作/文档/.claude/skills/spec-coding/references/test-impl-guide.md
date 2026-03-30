# 测试脚本实现指南（C7 游戏服务端）

> 定义从测试文档到 telnet 测试脚本的实现工作流。

---

## 1. 触发场景

当用户说以下内容时触发：
- "写测试脚本"
- "把测试文档转成脚本"
- "跑测试"
- "写一个 telnet 测试"

**前置条件**：测试文档 `F00X-testing.md` 已存在（或至少有明确的测试目标）。

---

## 2. 测试脚本实现流程

```
测试文档/目标已明确
        ↓
Step 1: 文档预读
        - 阅读需求文档（理解功能）
        - 阅读技术文档（理解实现、数据结构）
        - 阅读测试文档（理解用例）
        - 阅读被测代码（理解方法签名）
        ↓
Step 2: 生成测试骨架
        - 在 Test/ 目录新建脚本文件
        - 定义断言工具函数
        - 按用例 ID 生成测试函数
        ↓
Step 3: 实现测试代码
        - 逐个实现测试用例
        - 设置数据备份/恢复
        - 编写断言
        ↓
Step 4: 运行测试
        - 通过 telnet 执行脚本
        - 分析失败原因
        ↓
Step 5: 迭代修复
        - T/D/B 分类
        - 修复问题
        - 重新运行
        ↓
Step 6: 最终验证
        - 全部测试通过
        - 输出报告
        ↓
完成
```

---

## 3. 测试脚本结构

### 3.1 目录与命名

```
script_lua/
└── Test/
    ├── test_xxx_component.lua       # Component 测试
    ├── test_xxx_service.lua         # Service 测试
    └── test_xxx_integration.lua     # 集成测试
```

**命名规则**：`test_{系统名}_{测试类型}.lua`

### 3.2 测试脚本骨架

```lua
-- =======================
-- 文件: Test/test_xxx_component.lua
-- 功能: XxxComponent 测试
-- =======================

local utils = kg_require("Common.Utils.CommonUtils")

-- ==================== 断言工具 ====================

local passCount = 0
local failCount = 0
local failDetails = {}

local function assertEqual(actual, expected, desc)
    if actual == expected then
        passCount = passCount + 1
        print("[PASS] " .. desc)
    else
        failCount = failCount + 1
        local msg = string.format("[FAIL] %s: expected=%s, actual=%s", desc, tostring(expected), tostring(actual))
        print(msg)
        table.insert(failDetails, msg)
    end
end

local function assertNotNil(value, desc)
    if value ~= nil then
        passCount = passCount + 1
        print("[PASS] " .. desc)
    else
        failCount = failCount + 1
        local msg = string.format("[FAIL] %s: value is nil", desc)
        print(msg)
        table.insert(failDetails, msg)
    end
end

local function assertTrue(value, desc)
    if value then
        passCount = passCount + 1
        print("[PASS] " .. desc)
    else
        failCount = failCount + 1
        local msg = string.format("[FAIL] %s: value is falsy (%s)", desc, tostring(value))
        print(msg)
        table.insert(failDetails, msg)
    end
end

local function assertGTE(actual, expected, desc)
    if actual >= expected then
        passCount = passCount + 1
        print("[PASS] " .. desc)
    else
        failCount = failCount + 1
        local msg = string.format("[FAIL] %s: %s < %s", desc, tostring(actual), tostring(expected))
        print(msg)
        table.insert(failDetails, msg)
    end
end

-- ==================== 测试数据准备 ====================

-- 自动查找测试玩家
local p = findplayer()  -- 查找第一个在线玩家
if not p then
    p = (function()
        local players = getplayers()
        if players and next(players) then
            for _, v in pairs(players) do return v end
        end
    end)()
end

if not p then
    print("[ERROR] 没有在线玩家，无法执行测试")
    return
end

print(string.format("=== 测试玩家: %s (ID: %s) ===", p.Name or "未知", tostring(p.id)))

-- 自动从配表查找测试数据（示例）
-- local testConfigId = nil
-- local allConfigs = TableData.GetXxxConfigAllRow()
-- if allConfigs then
--     for id, row in pairs(allConfigs) do
--         testConfigId = id
--         break
--     end
-- end

-- ==================== 数据备份 ====================

-- 深拷贝备份被测数据（测试结束后恢复）
local function deepCopy(orig)
    local origType = type(orig)
    local copy
    if origType == "table" then
        copy = {}
        for origKey, origValue in next, orig, nil do
            copy[deepCopy(origKey)] = deepCopy(origValue)
        end
        setmetatable(copy, deepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

local backupData = deepCopy(p.xxxInfo or {})

-- ==================== 测试用例 ====================

print("\n=== 开始测试 ===\n")

-- TC001: 正常操作 - 基本流程
print("--- TC001: 正常操作 ---")
do
    local ok, ret = custom_xpcall(function()
        -- Arrange: 设置前置条件

        -- Act: 调用被测方法
        -- local result = p:MethodName(param1, param2)

        -- Assert: 验证结果
        -- assertNotNil(result, "TC001: 返回值不为空")
        -- assertEqual(result.code, 0, "TC001: 返回码为0")
    end)
    if not ok then
        failCount = failCount + 1
        local msg = "[FAIL] TC001: 异常 - " .. tostring(ret)
        print(msg)
        table.insert(failDetails, msg)
    end
end

-- TC002: 异常 - 参数非法
print("\n--- TC002: 参数非法 ---")
do
    local ok, ret = custom_xpcall(function()
        -- Act: 传入非法参数
        -- local result = p:MethodName(nil, -1)

        -- Assert: 验证错误处理
        -- assertEqual(result, nil, "TC002: 非法参数返回nil")
    end)
    if not ok then
        failCount = failCount + 1
        local msg = "[FAIL] TC002: 异常 - " .. tostring(ret)
        print(msg)
        table.insert(failDetails, msg)
    end
end

-- ==================== 数据恢复 ====================

print("\n=== 恢复测试数据 ===")
-- p.xxxInfo = backupData
-- 或使用相应的 setter 方法恢复

-- ==================== 测试报告 ====================

print("\n========================================")
print(string.format("测试结果: 通过 %d, 失败 %d, 总计 %d", passCount, failCount, passCount + failCount))
print("========================================")

if failCount > 0 then
    print("\n失败详情:")
    for _, detail in ipairs(failDetails) do
        print("  " .. detail)
    end
end
```

---

## 4. 测试执行

### 4.1 运行测试脚本

```bash
# 通过 telnet_client.py 执行（推荐）
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "dofile(\"/Test/test_xxx_component.lua\")" --timeout 30

# 如果测试涉及多次抽奖等耗时操作，加大超时
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "dofile(\"/Test/test_xxx_component.lua\")" --timeout 60
```

### 4.2 热更后重新测试

```bash
# 先热更脚本
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "refreshscript()"

# 再跑测试
MSYS_NO_PATHCONV=1 python Server/script_lua/.claude/skills/server-debug/telnet_client.py "dofile(\"/Test/test_xxx_component.lua\")"
```

---

## 5. 关键实践

### 5.1 数据安全

| 实践 | 说明 |
|------|------|
| **备份恢复** | 测试前 deepCopy 备份，测试后恢复 |
| **不修改核心数据** | 避免修改可能影响其他系统的数据 |
| **使用 custom_xpcall** | 包裹每个测试用例，防止一个用例失败导致全部中断 |

### 5.2 测试数据

| 实践 | 说明 |
|------|------|
| **自动查找** | 从 TableData 自动获取可用配表 ID |
| **不硬编码** | 避免写死配表 ID、玩家 ID 等 |
| **自动创建** | 需要特定条件时，通过代码自动构造 |

### 5.3 断言规范

| 断言函数 | 用途 |
|----------|------|
| `assertEqual(actual, expected, desc)` | 值相等 |
| `assertNotNil(value, desc)` | 值非 nil |
| `assertTrue(value, desc)` | 值为 true |
| `assertGTE(actual, expected, desc)` | 大于等于 |

每个断言必须包含描述（desc），格式：`"TC{编号}: 描述"`

---

## 6. T/D/B 问题分类

### 6.1 分类判断

```
测试失败
    ↓
1. custom_xpcall 捕获异常（方法不存在、类型错误等）？
   → 检查调用方式和参数 → 可能是 T 问题
    ↓
2. 断言值不匹配（预期 vs 实际）？
   → 阅读业务代码确认实际逻辑
    ↓
3. 实际逻辑符合需求文档？
   → 是：测试设计有误 → D 问题
   → 否：业务代码有 Bug → B 问题
```

### 6.2 修复规则

| 规则 | 说明 |
|------|------|
| 每轮最多修 10 个用例 | 避免改动过大 |
| 修复后必须重新运行 | 确认修复有效 |
| 最多 5 轮迭代 | 超过则输出报告让用户决策 |
| B 类问题需用户确认 | 不擅自修改业务代码 |

---

## 7. 测试结果报告模板

```markdown
## 测试运行报告

**运行时间**：YYYY-MM-DD HH:mm
**运行范围**：F00X 全部测试
**测试脚本**：Test/test_xxx_component.lua

### 结果概览

| 指标 | 数值 |
|------|------|
| 总用例数 | 10 |
| 通过 | 8 |
| 失败 | 2 |

### 失败用例分析

| Case ID | 分类 | 原因 | 修复状态 |
|---------|------|------|----------|
| TC003 | T | 断言条件写错 | 已修复 |
| TC005 | B | 迁移后回调未检查 Entity 有效性 | 待修复 |

### 发现的 Bug

| 编号 | 描述 | 代码位置 |
|------|------|----------|
| B-001 | 迁移后回调崩溃 | `Logic/Components/XxxComponent.lua:L150` |
```

---

## 8. 测试文件管理

- 测试脚本放在 `Test/` 目录下
- **测试文件不需要加到 P4**，本地新建后直接运行
- 如果测试脚本有复用价值，可以参考 `server-debug` skill 的 `examples/` 目录组织

---

*指南版本: 1.0.0*
