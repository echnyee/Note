# 系统开发 Checklist（Agent 精简版）

> 源文件：`Server/docs/00-core/系统开发checklist.md`（含完整 Bad/Good Case 示例）
> 本文件为 Agent 编码时的快速检查清单，逐条对照。

---

## 1. 属性

### 1.1 上线后严禁修改原有属性的数据类型
- `Persistent="true"` 的属性会落库，修改类型（含 `alias.xml` 中 dict Key/Value、tuple 子字段）导致旧数据反序列化失败
- 正确做法：tuple 加新字段；改动大时新建外层属性名，旧属性保留 `Default="nil"`
- 存盘字段不要直接删除

### 1.2 重构时考虑历史数据兼容
- 新字段必须 `or` 兜底：`mailData.attachments or Game.EmptyTable`

### 1.3 大数据不宜放玩家属性
- 大量、低频访问的数据应独立写库（`MongoFindOne`/`MongoUpdateOne`），`Properties` 保持空
- 客户端打开 UI 时才请求加载

### 1.4 bool 属性在 BoolPropDefs 中定义
- 不要在 XML 中为每个 bool 单独声明属性
- 统一在 `Shared/BoolPropDefs.lua` 用位运算管理

### 1.5 自定义类型定义在各自 XML 的 DataTypes 中
- 减少 `alias.xml` 大小和冲突

---

## 2. 组件

### 2.1 组件初始化不执行过多逻辑

**2.1.1 `__component_OnCreate__`**：
- 此阶段无客户端连接，禁止 RPC 下行
- 避免每次登录遍历配置表，使用 MD5 缓存仅在配置变更时重新注册

**2.1.2 `__component_ClientConnected__`**：
- 禁止立刻推送全量数据
- 只同步增量；大数据延迟到客户端打开 UI 时请求
- 非紧急同步放 `AvatarActor:delayLoad`（登录后 1~5 秒）

### 2.2 必须有功能开关
- 总开关：`CheckSwitchStatusWithTip("EnableXXX", false)`
- 重要子模块：独立子开关
- 开关变更增量同步客户端

---

## 3. 持久化

### 3.1 重要操作后 DoPersistent
- 使用 `self:DoPersistent(Enum.DoPersistentReason.XXX)`，必须传 reason
- 不要滥用（如低等级升级不触发，设合理阈值）
- 两种场景：①重要数据更新时存盘 ②独立写库成功后同步关联数据

### 3.2 严禁 MongoDB API 直接修改 Entity 数据
- Entity 持久化统一走 `DoPersistent`，禁止 `MongoUpdateOne` 直操 Entity 集合

### 3.3 禁止持久化配置表数据
- 只存玩家自身数据（ID + 等级），运行时从 `TableData` 查询静态数据

---

## 4. RPC

### 4.1 上行 RPC 必须设 CD
| 操作类型 | CD 范围 |
|---------|--------|
| 高频（移动/战斗） | 0.001~0.1s |
| 普通交互（登录/领奖） | 0.5s |
| 标准（创角/删角） | 1s |
| 较重（AI 对话/Service） | 3s |
| 敏感（验证码） | 5s |
| 重量级（全服消息） | 10s |

### 4.2 上行 RPC 参数禁止 None 类型
- 使用 tuple + `Default="nil"` 代替，支持增量同步和向后兼容

### 4.3 大量数据分包发送
- 登录同步简要信息 tuple（BRIEF），客户端按需拉取详情

### 4.4 数据同步：初次全量 + 增量更新
- 首次推送全量后，后续变更只推增量
- 可用 `OWN_INITIAL_ONLY` / `ALL_INITIAL_ONLY` 属性自动初始化 + RPC 增量

---

## 5. 数据库

### 5.1 查询必须有索引
- 索引定义在 `Server/Tools/OperateDb/Config/collection_info.json`
- 新集合 / 新查询模式必须配对应索引

### 5.2 禁止使用 skip
- 引擎 `DBProxy:commonCheck` 已拦截 skip
- 替代方案：`_id` 游标分页（`$gt`）或 `$slice` + `$filter`

### 5.3 排序字段检查索引覆盖
- 无索引覆盖 → MongoDB 内存排序 → 大数据量可能超 100MB 限制
- 排序优先用 `_id`（自带索引）

### 5.4 非实时查询设 read_preference
- `{ read_preference = Game.ReadModeSecondary }`，从从节点读取减轻主节点压力

### 5.5 频繁读操作使用缓存
- Entity 组件：用非持久化临时属性（`self.xxxList`）做内存缓存，`__after_ctor_or_migrate` 清空
- Service：用 LRU 缓存（`lru_cache.LRUCache:create`）

### 5.6 字段名禁止包含 `.`
- MongoDB 将 `.` 解析为嵌套路径，使用驼峰命名

### 5.7 批量操作用 bulk 接口
- 构建 operations 数组 → `Game.DBProxy:MongoBulk` 一次提交

### 5.8 大数据初始化分批读取
- `Game.DBProxy:MongoBatchLoadDatabase` 或 `Service:BatchLoadDataFromDB`

### 5.9 玩家 DB 回调必须用字符串函数名
- 禁止闭包（Entity 迁移后 self 丢失）
- 额外参数通过回调末尾参数传递
- Service 无迁移，闭包可放宽，但推荐一致用函数名

---

## 6. Timer

### 6.1 一律使用 setTimer 或 addTimer
- **`setTimer(timeout, interval, timerConst, funcName, ...)`**：推荐，通过 `timer_const` 常量自动取消旧 timer
- **`addTimer(timeout, interval, funcName, userData)`**：多 timer 动态管理场景
- **禁止 `addTimerEx`**：迁移时不一定清除，内外服表现不一致

---

## 7. 数值

### 7.1 数据错误时 error 中断
- 扣款余额不足必须 `error()` 中断，禁止 `math.max(0, ...)` 静默修正

### 7.2 重要数值修改必须有完整 SA Log
- 记录：修改前值、修改后值、修改来源（sourceId）、操作唯一标识（opNUID）

### 7.3 交易 SA Log 记录唯一 uuid
- 入口生成 `opNUID = _script.genUUID()`，贯穿扣币→发货→交易日志全链路

### 7.4 新系统投放必须新建渠道
- 在 `Shared/ItemConstSource.lua` 新增常量，禁止借用已有渠道

### 7.5 购买：先校验→先扣币→再发放
- `canBuyGoods`（服务端校验）→ `ConsumeTokens`（检查返回值）→ `addItems`

### 7.6 所有投放必须使用限次奖励
- `DropConst.lua` 注册 `LimitNo` + `SerialNo`
- `LimitConst.lua` 注册限次规则
- 业务层主动防重 + `DropItems` 走限次

### 7.7 发放奖励：先标记再发放
- 先写 `dict[id] = true` 标记，再调用 `DropItems` / `addItems`
- 避免发奖后崩溃导致重复发奖

---

## 8. 异步

### 8.1 异步操作必须容错
- DB 超时不代表操作失败（可能已插入），禁止在超时回调中反向补偿
- 正确做法：记录错误日志，等待排查

### 8.2 避免异步 RPC 死循环
- 不要形成 A → B → A 的 RPC 调用链

### 8.3 重要操作 RPC 保证幂等
- 执行前检查状态标记，避免重复执行

---

## 9. 外部服务

### 9.1 调用外部服务必须容错
- 错误感知 + 错误处理 + 服务降级/保底方案

### 9.2 调用地址配置在 config 中
- 禁止硬编码 URL，通过 `Game.LogicConfig` 读取

### 9.3 考虑外部服务回档
- 支付等场景需对账机制：订单 DB 标记已发货状态，防重发

### 9.4 外部服务字段必须验证
- `tonumber()` 转换 + 判空 + 错误日志

### 9.5 外部回调尽量幂等
- 用 DB 原子操作（`$setOnInsert`、条件 `UpdateOne`）保证幂等

---

## 10. 时间

### 10.1 禁止超过 1 天的定时器
- 在日刷新 `onDailyRefresh` 中检查和设置

### 10.2 多时间节点系统需 QA 改时间跑完测试

### 10.3 时间节点必须兼容错过情况
- 初始化时补刷（判断 `IsSameDay`）
- 触发时防重（检查 `dayRefreshTimestamp`）

### 10.4 服务器时间同步客户端
- 客户端用 `Game:GetGameTime()`（基于服务器时间）
- 重要信息服务端二次校验（如限时折扣价比对）

---

## 11. 策划配置表

### 11.1 时间字符串导表时转为时间戳
- 使用 `Timestamp()` 类型，禁止运行时 `parseTimestamp`

### 11.2 禁止代码遍历整张表
- 导表后处理导出索引表 / 映射表

### 11.3 禁止缓存 data 数据
- 每次使用时从 `TableData.GetXxxRow()` 读取，热更才能生效

### 11.4 data 数据只读
- 需要修改时复制一份副本，禁止直接修改 `TableData` 返回的 table

### 11.5 禁止 loadstring 处理公式
- 导表时导出为 Lua 函数

---

## 12. 性能

### 12.1 高频操作复用 table
- 模块级 `local _temp = {}` 复用，避免每帧创建新 table

### 12.2 批量删除用 table.batchremove
- 收集索引后一次性删除，禁止循环 `table.remove`

### 12.3 避免批量往 list 中间插入
- 先追加末尾，最后统一 `table.sort`

### 12.4 增删查优先用 map
- `t[key] = value` / `t[key] = nil`，O(1) 操作
- 只有需要顺序/数量时才用 list

### 12.5 高频访问用 local 缓存
- `local GetXxxRow = TableData.GetXxxRow` 减少 `.` 操作

### 12.6 批量操作分帧处理
- 延迟任务队列 + timer 每帧执行有限数量

### 12.7 集中进入的多人场景需扰动
- 300 人以下：随机延迟
- 500 人以上：必须有进入队列
- 以压测为准

### 12.8 匹配需求必须有队列和上限
- 每 tick 只处理有限数量匹配，避免瞬间创建过多场景
