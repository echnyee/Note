---
name: new-component
description: 当用户要求创建新的服务端组件、新建 Component 时使用此技能。
---

## 组件模板

按以下模板创建新的服务端组件：

```lua
---@class {ComponentName} : ComponentBase
local {ComponentName} = DefineComponent("{ComponentName}")

function {ComponentName}:ctor()
    -- 初始化
end

function {ComponentName}:dtor()
    -- 清理资源
end

return {ComponentName}
```

## 要求
- 组件名使用 PascalCase
- 组件文件放在 `Logic/Components/` 目录下
- 如果有网络协议，需要同步在 `NetDefs/` 目录中创建对应的 XML 定义
- 使用 EmmyLua 注解标注类型（`---@class`、`---@param`、`---@return`）
- 使用 `kg_require` 引入依赖模块
- 日志使用 `self:logInfoFmt` / `self:logErrorFmt` / `self:logWarnFmt`
- 日志格式符统一使用 `%s`，table 类型使用 `%v`
- 遵循 `../references/lua-code-style.md` 中的代码规范
