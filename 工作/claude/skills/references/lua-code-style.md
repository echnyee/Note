<!-- 源地址：https://docs.corp.kuaishou.com/k/home/VV6omNFrJ4X4/fcABrWLJmbpyDFEi2x0b0a77U -->

# Lua 代码风格速查（C7 项目）

## 命名
- 文件夹 / 文件名 / 类名：CamelCase
- kg_require 模块名：全小写下划线（`local activity_const = kg_require("Common.ActivityConst")`）
- public 成员函数：`Class:UpperCamelCase()`，private：`Class:lowerCamelCase()`
- local 函数：`local function lowerCamelCase()`
- RPC 函数：`CS/SC/SS` + 模块名 + 功能（如 `CSTeamJoin`）
- 变量：lowerCamelCase；缩写非首字母时全大写（`entityID`，`uuid`）
- 常量 / 枚举：ALL_UPPER_SNAKE
- 组件：`XxxComponent`，玩家专用：`AvatarXxxComponent`
- 数据库名/表名：小写下划线
- 禁止添加全局变量和全局函数（业务逻辑）

## 格式
- 四空格缩进，双引号字符串
- table 用初始化语法，不在 table 内定义 function
- 用 `function` 声明而非变量赋值
- 鼓励多出口提前 return，避免深嵌套
- if 不加多余括号，不用 Yoda 条件

## 模块引入
- 业务逻辑必须用 `kg_require`，只 require 到模块，内部成员运行时访问
- 不要底层模块引用上层模块

## Hotfix 兼容
- 不要在 table 中持有 function（存函数名代替）
- 不要用模块级 local 函数
- 模块枚举/常量不用 local
- 不要在模块级别执行注册等逻辑
- 不要返回动态创建的 function

## 日志
- 用 `self:logInfoFmt` / `logErrorFmt` / `logWarnFmt`，不拼接字符串
- 格式符统一 `%s`，table 用 `%v`，禁止 `%d` `%f`

## 性能
- 循环内缓存频繁访问的表字段为local局部变量
- 谨慎创建临时 table 和闭包
- 避免在运行时进行字符串拼接和tostring转换

## 常见陷阱
- 判空用 `next(t) == nil`，不用 `#t == 0`
- `0` 和 `""` 在 Lua 中是 true，条件判断要显式比较
- 遍历中删除元素：pairs 可置 nil；list 用从后往前 + table.remove
- 模块级变量用 `Game = Game or {}` 防 reload 清空
- 字符串判空用 `string.isNilOrEmpty(s)`
- 业务模块持有 entityID 而非 Entity 引用
- 禁止 `pcall`，用 `xpcall` 代替
- 类字段用类名访问（`PetComponent.WEAPON_SLOT`），不用 `self.xxx`
