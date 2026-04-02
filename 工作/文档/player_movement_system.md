# 玩家移动系统文档

基于 `Server/crates/src/biz/scene/move/` C++ 实现与 `Server/script_lua/Logic/Components/` Lua 业务层代码，用于系统理解、问题定位与功能开发参考。

---

## 一、系统概述

移动系统采用 **C++ 引擎层 + Lua 业务层** 的双层架构：

- **C++ 层**（`crates/src/biz/scene/move/`）：状态机驱动实际位移、碰撞检测、客户端同步校验、物理模拟
- **Lua 层**（`script_lua/Logic/Components/`）：速度管理、传送逻辑、RootMotion 发起、载具/双人移动等业务功能
- **客户端**（`Client/Content/Script/`）：输入处理、自动寻路、表现层位移、UE 引擎 API 调用

数据流向：

```
玩家输入 (Client)
    |
    v
InputMoveMgr --> Client MoveComponent <--> AutoNavigationSystem
    |                    |
    |            [UE Engine APIs]
    |          KAPI_Movement_xxx
    |                    |
    v                    v
======== 网络层 (RPC / 二进制协议 MoveComponent.xml) ========
    |                    |
    v                    v
Server MoveComponent <--> C++ ActorMove (状态机)
    |                         |
    |-- BehaviorMoveComponent |-> Navmesh / 寻路 (Space)
    |-- FlowchartMoveComponent|-> 物理 (地面/重力/坠落)
    |-- CurveMovementComponent|-> 碰撞 / 附着
    |-- DualMoveComponent     |-> RootMotion 引擎
    +-- MovePlatformPassenger +-> 路点 / 样条曲线引擎
```

---

## 二、目录结构

### C++ 引擎层

```
crates/src/biz/scene/move/
|-- actor_move.hpp/cpp            # 底层移动组件（状态机 + 旋转 + 同步校验）
|-- actor_move_state.hpp/cpp      # 移动状态实现（13 种状态）
|-- actor_rotate_state.hpp/cpp    # 旋转状态
|-- actor_collision.hpp/cpp       # 碰撞检测
|-- move_define.hpp               # 移动常量定义
|-- move_data_manager.hpp/cpp     # 移动配置数据管理
|-- move_state_base.hpp           # 状态基类模板
|-- gravitational_field.hpp/cpp   # 引力场移动效果
|-- spline_curve.hpp/cpp          # 样条曲线插值
|-- logic_move_calculator.hpp     # 移动计算辅助
+-- behavior/                     # 行为层移动（AI/NPC）
    |-- behavior_move.hpp/cpp            # 行为移动组件
    |-- behavior_move_state.hpp          # 行为状态枚举
    |-- wander_move.hpp/cpp              # 游荡
    |-- navi_forcibly.hpp/cpp            # 强制导航
    |-- follow_forcibly.hpp/cpp          # 强制跟随
    +-- uniform_accelerate.hpp/cpp       # 匀加速
```

### Lua 业务层

| 文件 | 路径 | 说明 |
|------|------|------|
| MoveComponent | `Logic/Components/MoveComponent.lua` | 核心移动组件（~1500+ 行），速度/传送/RootMotion/载具 |
| BehaviorMoveComponent | `Logic/Components/BehaviorMoveComponent.lua` | AI 行为移动（~1450+ 行），巡逻/跟随/逃跑/环绕 |
| CurveMovementComponent | `Logic/Components/CurveMovementComponent.lua` | 样条/路点曲线移动（载具用） |
| DualMoveComponent | `Logic/Components/DualMoveComponent.lua` | 双人搬运系统 |
| FlowchartMoveComponent | `Logic/Components/Flowchart/FlowchartMoveComponent.lua` | 剧情/任务脚本移动（~1261 行） |
| MovePlatformPassengerComponent | `Logic/Components/MovePlatformPassengerComponent.lua` | 移动平台乘客系统 |

### 网络协议

| 文件 | 说明 |
|------|------|
| `Data/NetDefs/MoveComponent.xml` | 移动组件 RPC 定义（核心） |
| `Data/NetDefs/ActorBase.xml` | 旋转/注视 RPC |
| `Data/NetDefs/AvatarActor.xml` | 玩家传送 RPC |
| `Data/NetDefs/NpcActor.xml` | NPC 路点/曲线移动 RPC |
| `Data/NetDefs/LocomotionControlComponent.xml` | 运动姿态/运动组 RPC |
| `Data/NetDefs/MovePlatformPassengerComponent.xml` | 移动平台 RPC |

---

## 三、C++ 移动状态机（ActorMove）

### 3.1 状态总览

ActorMove 是 Actor 的底层移动组件，通过状态机驱动实际位移。共 13 种移动状态：

| 状态 | 枚举值 | 说明 | 主动/被动 |
|------|--------|------|-----------|
| IDLE | 0 | 静止 | - |
| NAVI_TO_POINT | 1 | 导航到目标点（Navmesh 寻路） | 主动 |
| NAVI_TO_ENTITY | 2 | 导航追踪实体 | 主动 |
| CUSTOM_MOVE | 3 | 自定义移动（ICustomMove 接口） | 被动 |
| CLIENT_CONTROLLED_MOVE | 4 | 客户端控制移动（服务端校验） | 主动 |
| STRAIGHT_MOVE | 5 | 直线移动（支持跳跃抛物线） | 主动 |
| ROOT_MOTION | 6 | RootMotion 到目标点 | 被动 |
| ROOT_MOTION_BY_CURVE | 7 | RootMotion 曲线移动 | 被动 |
| ROOT_MOTION_NO_DEST | 8 | RootMotion 无目标点 | 被动 |
| PHYSIC_FALL | 9 | 物理坠落 | 被动 |
| CLIENT_PERFORM | 10 | 客户端表演（跳跃/闪避等） | 主动 |
| WAY_POINT_MOVE | 11 | 路点移动（循环/往返/单程） | 主动 |
| FIXED_PATH_MOVE | 12 | 固定路径移动（样条曲线） | 主动 |

**主动移动**：可被主动打断（如新的移动请求）
**被动移动**：由外部系统驱动（如技能 RootMotion），不可被主动移动打断

### 3.2 状态转换规则

```
                    +------> NAVI_TO_POINT ------+
                    |                             |
     主动移动请求 --+------> NAVI_TO_ENTITY -----+
                    |                             |
                    +------> STRAIGHT_MOVE ------+----> IDLE (到达/停止)
                    |                             |
                    +------> WAY_POINT_MOVE -----+
                    |                             |
                    +------> FIXED_PATH_MOVE ----+

     客户端同步 ---------> CLIENT_CONTROLLED_MOVE --> IDLE (停止)

     技能/Buff ------+----> ROOT_MOTION ----------+
                     |                             |
                     +----> ROOT_MOTION_BY_CURVE --+----> IDLE (完成)
                     |                             |
                     +----> ROOT_MOTION_NO_DEST ---+

     物理 ---------------> PHYSIC_FALL -------------> IDLE (落地)

     客户端表演 ----------> CLIENT_PERFORM ---------> IDLE (完成)
```

**关键规则**：
- 进入新状态前调用当前状态的 `OnExit()`，再调用新状态的 `OnEnter()`
- 被动移动（RootMotion/PhysicFall）期间，拒绝主动移动请求
- `is_disable_proactive_move()` 可全局禁止主动移动（由 Buff/技能控制）

### 3.3 Tick 流程

每帧 Actor::Tick 中按顺序执行：

```
Actor::Tick
  |-- BehaviorMove::Tick     # AI 行为层（决定去哪）
  +-- ActorMove::Tick        # 底层移动（实际位移）
        |-- 当前 MoveState::Tick   # 状态逻辑（寻路/直线/曲线等）
        +-- 当前 RotateState::Tick # 旋转逻辑
```

---

## 四、旋转系统

### 旋转状态

| 状态 | 说明 |
|------|------|
| IDLE | 无旋转 |
| ROTATE_TO_DIRECTION | 旋转到目标方向（指定速度/时长） |
| ROTATE_FOLLOW_ENTITY | 持续面朝目标实体 |
| ROTATE_KEEP_DIRECTION | 保持当前朝向不变 |
| ROTATE_KEEP_ROTATE | 持续旋转（指定速度+方向） |

### 旋转 API

| Lua API | 说明 |
|---------|------|
| `actor:rotate_to_direction_instantly(yaw)` | 瞬间转向 |
| `actor:rotate_to_direction(yaw, speed, duration, need_callback)` | 匀速旋转到目标方向 |
| `actor:rotate_follow_entity(actor_id, check_block)` | 持续面朝目标 |
| `actor:rotate_keep_direction()` | 锁定当前朝向 |
| `actor:rotate_keep_rotate(speed, clockwise)` | 持续旋转 |
| `actor:stop_rotate(rotate_id)` | 停止旋转 |

### 坐标系转换

- C++ 业务层使用**度数制 Yaw**
- 引擎层使用 UE 坐标系（Y/Z 互换，Yaw 弧度制偏移 90 度）
- `EngineProxy` 统一做转换：`ToEngineYaw(degree) = DegreeToRadian(90 - degree)`

---

## 五、速度系统

### 5.1 速度优先级

速度计算采用优先级覆盖机制（从高到低）：

```
最终速度 = FixedSpeed > OverrideSpeedN > Speed(Speed_N * (1 + Speed_P))
```

| 优先级 | 字段 | 说明 |
|--------|------|------|
| 最高 | FixedSpeed | 固定速度覆盖（技能/Buff 强制设定） |
| 高 | OverrideSpeedN | 速度覆盖（骑乘/特殊状态） |
| 普通 | Speed_N * (1 + Speed_P) | 基础速度 * 百分比加成 |

附加限制：
- `LimitMoveSpeed`：速度上限
- `speedLimiters[]`：多个速度限制器取最小值
- 姿态速度：Walk / Run / Sprint 各有独立系数

### 5.2 C++ 层速度

```cpp
// ActorMove / CombatComp 管理
base_speed_    // 基础速度（属性系统计算结果）
fix_speed_     // 固定速度覆盖
max_speed_     // 速度上限
GetFinalSpeed() // = fix_speed_ > 0 ? fix_speed_ : min(base_speed_ * 属性加成, max_speed_)
```

### 5.3 速度同步 RPC

| RPC | 方向 | 说明 |
|-----|------|------|
| `OnMsgSyncFinalSpeed` | S -> C | 同步最终计算速度 |
| `OnMsgSyncBaseSpeedN` | S -> C | 同步基础速度 N 分量 |
| `OnMsgSyncOverrideSpeedN` | S -> C | 同步覆盖速度 |
| `OnMsgSyncFixSpeed` | S -> C | 同步固定速度 |
| `OnMsgSyncMaxSpeed` | S -> C | 同步速度上限 |

---

## 六、客户端同步与反作弊

### 6.1 同步机制

玩家移动采用**客户端预测 + 服务端校验**模型：

1. 客户端每帧通过二进制协议 `ClientSyncMovement` 上报位置/速度/加速度
2. 服务端 `ActorMove::HandleSyncMove` 接收并校验
3. 校验通过后更新服务端位置，并通过 AOI 广播给周围玩家
4. 校验失败时执行纠偏（强制传送到服务端位置）

### 6.2 同步数据结构（PredictMoveParams）

| 字段 | 类型 | 说明 |
|------|------|------|
| tickCount | int | Tick 计数器 |
| moveSyncType | int | 移动同步类型 |
| moveMode | int | 移动模式 |
| currentLocation | Vector3 | 当前位置 |
| predictRotation | float | 预测朝向 |
| acceleration | Vector3 | 加速度 |
| velocity | Vector3 | 速度向量 |
| extraMask | int | 额外标志位 |
| spaceId | string | 场景 ID |

### 6.3 校验机制（VerifyInfo）

| 校验项 | 说明 |
|--------|------|
| 速度校验 | 客户端上报速度不得超过 `speed_limit` |
| 位置校验 | 位置偏差不得超过阈值 |
| 时间差校验 | 防止加速外挂 |
| 超限处理 | 服务端强制传送纠偏 |

速度限制默认值：
- 普通状态：`set_speed_limit(2000)`
- 骑乘状态：`set_speed_limit(3000, 1)`
- 可按地图关闭校验：`set_enable_move_verify(false)`

### 6.4 移动广播分级

| 级别 | 说明 |
|------|------|
| Full | 完整移动数据（位置+速度+加速度） |
| Brief | 简化数据（仅位置+朝向） |
| FixedPath | 固定路径专用广播 |

### 6.5 握手与心跳

| 协议 | 说明 |
|------|------|
| `Handshake` | 连接握手（请求/响应），建立时间基准 |
| `Heartbeat` | 心跳包，服务端回复时间戳 |
| `TeleportAck` | 传送确认（客户端确认到达传送目标点） |

---

## 七、传送系统

### 7.1 传送类型

| 类型 | 说明 |
|------|------|
| TELEPORT_FAR | 远距传送（触发客户端 Loading 画面） |
| TELEPORT_NEAR | 近距传送 |
| SKILL | 技能传送 |

### 7.2 传送流程

```
客户端请求传送 (ReqTeleportPoint / ReqTeleportToAvatar)
    |
    v
服务端 MoveComponent 校验
    |
    v
调用 actor:teleport(x,y,z,yaw,type,...)
    |
    v
C++ ActorMove 执行传送
    |-- 更新服务端位置
    |-- 通知客户端 OnMsgSetPosition
    +-- 如果是 TELEPORT_FAR:
          |-- 等待客户端场景加载
          +-- 客户端发送 ClientNotifySceneLoaded(sequence)
                |
                v
              服务端确认完成，恢复正常同步
```

### 7.3 传送相关 RPC

| RPC | 方向 | CD | 说明 |
|-----|------|-----|------|
| `ReqTeleportPoint` | C -> S | 1s | 请求传送到传送点 |
| `ReqTeleportToAvatar` | C -> S | 5s | 请求传送到其他玩家 |
| `ReqForceLeaveTeleport` | C -> S | - | 强制脱离卡住的传送状态 |
| `ReqForceLeaveTeleportToRespawnPoint` | C -> S | 3s | 强制传送到复活点 |
| `ClientNotifySceneLoaded` | C -> S | 0.1s | 通知场景加载完成 |
| `OnMsgSetPosition` | S -> C | - | 强制设置客户端位置 |
| `RetTeleportPoint` | S -> C | - | 传送结果响应 |

---

## 八、RootMotion 系统

### 8.1 概述

RootMotion 是技能/动画驱动的位移，由战斗系统发起，移动系统执行。三种 RootMotion 状态：

| 状态 | 说明 |
|------|------|
| ROOT_MOTION | 从起点到终点的位移，有明确目标点 |
| ROOT_MOTION_BY_CURVE | 沿曲线移动（CurveGUID 指定曲线） |
| ROOT_MOTION_NO_DEST | 无目标点，仅播放动画时长（不修改位置） |

### 8.2 发起流程

```lua
-- Lua 层发起 RootMotion
MoveComponent:ApplyRootMotion(params)
    |
    v
actor:start_root_motion(dx,dy,dz, duration, stick_ground, disable_sync, curve_id, callback_id, use_rotation)
-- 或
actor:start_root_motion_no_dest(duration, stick_ground, curve_id, is_loco, scale, callback_id)
```

### 8.3 同步类型

| 类型 | 说明 |
|------|------|
| All | RPC + 二进制消息双通道同步 |
| None | 不同步到客户端 |
| OnlyRpc | 仅 RPC 同步 |
| OnlyMsg | 仅二进制消息同步 |

### 8.4 RootMotion RPC

| RPC | 方向 | 说明 |
|-----|------|------|
| `ReqStartRootMotion` | C -> S | 客户端请求开始 RootMotion |
| `ReqCancelRootMotion` | C -> S | 客户端请求取消 RootMotion |
| `OnMsgStartRootMotion` | S -> C | 通知客户端开始 RootMotion |
| `OnMsgStartServerRootMotion` | S -> C | 服务端权威 RootMotion（带 Min/Max 速度） |
| `OnMsgFinishRootMotion` | S -> C | 通知客户端 RootMotion 完成 |

---

## 九、行为移动（BehaviorMove）

### 9.1 概述

BehaviorMove 是 AI/NPC 的行为层移动组件，在 ActorMove 之上提供高层行为逻辑。

### 9.2 行为状态

| 状态 | 说明 |
|------|------|
| NONE | 无行为 |
| WANDER | 游荡（随机巡逻） |
| NAVI_FORCIBLY | 强制导航到目标点（忽略 Navmesh 间隙） |
| UNIFORM_ACCELERATE | 匀加速移动 |
| FOLLOW_FORCIBLY | 强制跟随目标实体 |

### 9.3 Lua BehaviorMoveComponent

提供更丰富的行为类型：

| 行为 | 说明 |
|------|------|
| Patrol | 路径巡逻 |
| CurvePatrol | 曲线巡逻（客户端走曲线，服务端走直线） |
| FollowUp | 跟随 |
| Flee | 逃跑 |
| AutoPatrol | 自动巡逻 |
| Encirclement | 包围 |
| RelativeFollow | 相对跟随 |
| WanderMove | 游荡 |
| Orbit | 环绕 |

### 9.4 曲线巡逻特殊处理

```
客户端：沿样条曲线平滑移动（表现好）
服务端：沿直线移动（性能优）
```

使用 `set_enable_sync_move(false)` 禁止服务端位置覆盖客户端曲线路径。

---

## 十、空间导航能力

### 10.1 Space 级 API

| 方法 | 说明 |
|------|------|
| `Space:FindPathByPosition(start, target, maxDepth, agentHeight)` | Navmesh A* 寻路 |
| `Space:FindPathStraight(start, target, agentHeight, stick, tolerance, outPos)` | 直线路径验证 + 地面吸附 |
| `Space:MoveToCalculate(start, target, halfHeight, stick)` | 计算实际可达目标点 |

### 10.2 C++ 层导航

| 功能 | 说明 |
|------|------|
| Navmesh | 导航网格寻路（异步加载到子线程） |
| Voxel | 体素移动（Space::MoveTo / MoveToNearby） |
| Floor Detection | 地面检测（GetFloorUnsafe / GetNearestFloor） |
| Block Check | 阻挡判定（IsBlock） |
| Dynamic Obstacle | 动态阻挡物（AddDynamicCube / AddDynamicCylinder） |

### 10.3 碰撞系统

- **Channel 机制**：基于通道的碰撞检测
- **Impetus 系统**：推力效果（如技能击退）
- **Sweep 检测**：线段-点距离碰撞
- `actor:set_collision_info()` 设置碰撞参数
- `actor:change_impetus_actor()` 改变推力源

---

## 十一、特殊移动系统

### 11.1 路点移动（WAY_POINT_MOVE）

用于 NPC/载具沿预设路点移动，支持三种模式：

| 模式 | 说明 |
|------|------|
| 循环 | 到达终点后从起点重新开始 |
| 往返 | 到达终点后反向移动 |
| 单程 | 到达终点后停止 |

```lua
actor:way_point_move(path_id, start_index, end_index, type, range)
actor:control_way_point_move(control_type)  -- 暂停/恢复/停止
```

### 11.2 固定路径移动（FIXED_PATH_MOVE）

沿 PCG 样条曲线移动，使用 `spline_curve.hpp` 插值计算。

```lua
actor:fixed_path_move(path_id, flag)
actor:control_fixed_path_move(is_pause)
```

### 11.3 物理坠落（PHYSIC_FALL）

```lua
actor:start_physic_fall()        -- 开始坠落
actor:physic_fall_caculate()     -- 计算坠落位置
actor:is_on_floor()              -- 是否在地面上
actor:set_to_floor()             -- 强制吸附到地面
```

物理常量与 UE4 客户端对齐：重力加速度、跳跃初速度等。

### 11.4 载具系统

```lua
-- 上下载具（Lua MoveComponent）
MoveComponent:GetOnVehicle(vehicleId)    -- actor:attach_by_actor(id, offset)
MoveComponent:GetOffVehicle(vehicleId)   -- actor:detach_by_actor(id)
```

### 11.5 双人搬运（DualMoveComponent）

三种状态：`NORMAL`、`CARRYING`（搬运者）、`BE_CARRIED`（被搬运者）。复用载具附着系统。

### 11.6 移动平台乘客

用于火车、马车等移动平台：

| RPC | 方向 | 说明 |
|-----|------|------|
| `ReqGetOnMovePlatform` | C -> S | 上车 |
| `ReqGetOffMovePlatform` | C -> S | 下车 |
| `ReqInteractGetOnMovePlatform` | C -> S | 交互上车 |
| `OnMsgGetOnMovePlatform` | S -> C | 通知上车成功 |
| `OnMsgGetOffMovePlatform` | S -> C | 通知下车成功 |
| `ReqGetOnSightMount` / `ReqGetOffSightMount` | C -> S | 观光座上下 |

### 11.7 引力场

```lua
actor:enter_gravitational_field(field_id)
actor:leave_gravitational_field(field_id)
```

服务端通过 `GravitationalField` 组件管理引力场效果，客户端通过 RPC 同步：
- `OnMsgRebuildGravitationalField`：重建引力场列表
- `OnMsgEnterGravitationalField`：进入引力场
- `OnMsgLeaveGravitationalField`：离开引力场

---

## 十二、运动姿态系统（LocomotionControl）

### 12.1 运动姿态

客户端通过 `ReqSetMovePosture` 请求切换运动姿态（Idle/Walk/Run/Sprint 等）。

### 12.2 运动组（LocoGroup）

不同运动场景切换不同运动组：

| RPC | 方向 | 说明 |
|-----|------|------|
| `ReqSetLocoGroup` | C -> S | 请求切换运动组（普通/游泳/攀爬/滑翔） |
| `RetSetLocoGroupFailed` | S -> C | 运动组切换失败通知 |
| `ReqSetIsInWater` | C -> S | 报告进入/离开水域 |
| `ReqConsumeStamina` | C -> S | 请求消耗体力（闪避/跳跃） |
| `ReqChangeGlideLoop` | C -> S | 进入/退出滑翔漂浮状态 |

---

## 十三、C++ 引擎 API 速查

以下为 Lua 通过 `actor:xxx()` 调用的 C++ 移动 API 完整列表。

### 导航

| API | 说明 |
|-----|------|
| `navi_to_point(x,y,z,range,partial)` | Navmesh 寻路到目标点 |
| `navi_to_entity(iid,range)` | 导航追踪实体 |
| `navi_forcibly(x,y,z,range)` | 强制导航（忽略间隙） |
| `navi_forcibly_can_jump(x,y,z,jh,jd,jdur,range)` | 强制导航（可跳跃） |

### 直线移动

| API | 说明 |
|-----|------|
| `straight_move(x,y,z,stick_to_floor)` | 直线移动到目标点 |
| `straight_move_can_jump(x,y,z,jh,jd,jdur)` | 直线移动（可跳跃） |

### 停止与状态

| API | 说明 |
|-----|------|
| `stop_move(stop_type)` | 停止移动 |
| `get_move_state()` | 获取当前移动状态 |
| `get_behavior_move_state()` | 获取行为移动状态 |
| `get_move_snapshot()` | 获取移动快照 |
| `get_real_velocity()` | 获取实际速度向量 |

### 传送

| API | 说明 |
|-----|------|
| `teleport(x,y,z,yaw,type,path_check,stick,force,config_id)` | 传送 |
| `teleport_to_target(target_id,x,y,z,ryaw,type,force,config_id)` | 传送到目标实体附近 |
| `client_teleport(x,y,z,yaw,type)` | 客户端传送 |

### RootMotion

| API | 说明 |
|-----|------|
| `start_root_motion(dx,dy,dz,dur,stick,disable_sync,curve,cb,use_rot)` | 开始 RootMotion |
| `start_root_motion_no_dest(dur,stick,curve,is_loco,scale,cb)` | 无目标 RootMotion |
| `mark_in_root_motion()` / `mark_not_in_root_motion()` | 标记 RootMotion 状态 |

### 速度

| API | 说明 |
|-----|------|
| `get_base_speed()` / `set_base_speed(speed)` | 基础速度 |
| `modify_base_speed(delta)` | 修改基础速度增量 |
| `get_fixed_speed()` / `set_fixed_speed(speed)` | 固定速度 |
| `set_move_cast_base_speed()` / `get_move_cast_base_speed()` | 移动施法速度 |

### 行为移动

| API | 说明 |
|-----|------|
| `wander_move(...)` | 游荡 |
| `uniform_accelerate(accel,limit,init)` | 匀加速 |
| `follow_forcibly(iid,range,delta_yaw,dest1,dest2,tp_range,mode)` | 强制跟随 |
| `orbit_move(cx,cy,cz,radius,speed,clockwise)` | 环绕移动 |

### 配置与控制

| API | 说明 |
|-----|------|
| `set_move_params(speed,climb_h,pass_mask,start_t,stop_t)` | 设置移动参数 |
| `set_move_type(type)` | 设置移动类型 |
| `set_enable_move_verify(bool)` | 开关移动校验 |
| `set_speed_limit(limit,type)` | 设置速度限制 |
| `set_locomotion_state(state)` | 设置运动状态 |
| `set_weightlessness(bool)` | 设置失重状态 |
| `set_need_apply_gravity(bool)` | 设置是否应用重力 |
| `set_controlled_by(role)` | 设置控制权 |
| `set_enable_sync_move(bool)` | 开关移动同步 |
| `set_enable_sync_degradation(bool)` | 开关同步降级 |
| `set_listen_move_event(bool)` | 开关移动事件监听 |

---

## 十四、网络协议完整列表

### 14.1 Server -> Client（共 35 个）

#### MoveComponent

| RPC | 参数 | 说明 |
|-----|------|------|
| OnMsgMoveUpdateBroadCast | PredictMoveParams, specialMoveType | 移动广播 |
| OnMsgSetPosition | reason, pos, rot | 强制设置位置 |
| OnMsgStartRootMotion | SyncSign, Start/Target XYZ, Duration, StickGround, CurveGUID, Scale | 开始 RootMotion |
| OnMsgStartServerRootMotion | SyncSign, Start/Target XYZ, Duration, MinS, MaxS, StickGround, CurveGUID, Scale | 服务端权威 RootMotion |
| OnMsgFinishRootMotion | SyncSign | 完成 RootMotion |
| OnMsgRebuildGravitationalField | GravitationFieldList | 重建引力场 |
| OnMsgEnterGravitationalField | GravitationFieldInfo | 进入引力场 |
| OnMsgLeaveGravitationalField | GravitationalFieldID | 离开引力场 |
| OnJumpToPoint | X, Y, Z, Yaw, Duration, MaxHeight | 跳跃到目标点 |
| OnMsgStartCurveMove | PathID, Speed, PatrolType, PathIndex | 开始曲线移动 |
| OnMsgStopCurveMove | - | 停止曲线移动 |
| OnMsgCurveToPoint | CurvePathIndex | 曲线移动到路点 |
| OnMsgCurveReachPoint | index | 到达曲线路点 |
| OnMsgCurvePauseMove | - | 暂停曲线移动 |
| OnMsgCurveResumeMove | index | 恢复曲线移动 |
| OnMsgSyncFinalSpeed | speed | 同步最终速度 |
| OnMsgSyncBaseSpeedN | speed | 同步基础速度 |
| OnMsgSyncOverrideSpeedN | speed | 同步覆盖速度 |
| OnMsgSyncFixSpeed | speed | 同步固定速度 |
| OnMsgSyncMaxSpeed | speed | 同步速度上限 |
| OnMsgCombatRotateToDir | TargetYaw, RotateSpeed | 战斗旋转到方向 |
| OnMsgCombatRotateClockWise | ClockWise, RotateSpeed | 持续旋转 |
| OnMsgCombatRotateFollowEntity | TargetEntityID, RotateSpeed | 面朝目标旋转 |
| OnMsgCombatStopRotate | - | 停止战斗旋转 |

#### ActorBase

| RPC | 说明 |
|-----|------|
| OnMsgRotateToAng | 旋转到角度 |
| OnMsgRotateToEntity | 旋转朝向实体 |
| OnMsgRotateToLoc | 旋转朝向位置 |
| OnMsgStopRotate | 停止旋转 |
| OnMsgGazeToSpawner / GazeToEntity / GazeToLoc / GazeBack / GazeBackDelay | 注视系统 |

### 14.2 Client -> Server（共 20 个）

| RPC | CD | 说明 |
|-----|-----|------|
| ReqStartRootMotion | 0.1s | 请求开始 RootMotion |
| ReqCancelRootMotion | 0.1s | 取消 RootMotion |
| ClientNotifySceneLoaded | 0.1s | 场景加载完成 |
| ReqSetNpcTransform | 0.1s | 设置 NPC 位置 |
| ReqSceneEstatePortal | 0.1s | 庄园传送门 |
| ReqForceLeaveTeleport | 0.1s | 强制脱离传送 |
| ReqTeleportPoint | 1s | 传送到传送点 |
| ReqTeleportToAvatar | 5s | 传送到其他玩家 |
| ReqForceLeaveTeleportToRespawnPoint | 3s | 传送到复活点 |
| ReqClientSyncNpcMove | 2s | 开始客户端 NPC 同步 |
| ReqCancelClientSyncNpcMove | 2s | 取消客户端 NPC 同步 |
| ReqSetMovePosture | 0.001s | 切换运动姿态 |
| ReqSetLocoGroup | 0.001s | 切换运动组 |
| ReqSetIsInWater | 0.001s | 报告水域状态 |
| ReqConsumeStamina | 0.001s | 消耗体力 |
| ReqChangeGlideLoop | 0.001s | 切换滑翔 |
| ReqGetOnMovePlatform | 0.1s | 上移动平台 |
| ReqGetOffMovePlatform | 0.1s | 下移动平台 |
| ReqGetOnSightMount | 0.1s | 上观光座 |
| ReqGetOffSightMount | 0.1s | 下观光座 |

### 14.3 二进制协议（C++ 直接处理）

| 协议 | 说明 |
|------|------|
| ClientSyncMovement | 客户端移动同步上报 |
| Handshake | 握手协议 |
| TeleportAck | 传送确认 |
| RotateInstantly | 即时转向 |
| Heartbeat | 心跳 |

### 14.4 同步属性

| 属性 | 同步范围 | 说明 |
|------|----------|------|
| FixedSpeed | ALL_CLIENTS | 固定速度 |
| FinalSpeed | ALL_CLIENTS | 最终速度 |
| LimitMoveSpeed | ALL_CLIENTS | 速度上限 |
| OverrideSpeedN | OWN_INITIAL_ONLY | 覆盖速度 |
| MoveStateNew | ALL_INITIAL_ONLY | 移动状态 |
| bCurveMove | ALL_INITIAL_ONLY | 是否曲线移动 |
| EnableMoveVerify | SERVER_ONLY | 是否开启校验 |
| MovePosture | ALL_CLIENTS | 运动姿态 |
| LocoGroup | ALL_CLIENTS | 运动组 |
| IsInWater | ALL_CLIENTS | 水域状态 |

---

## 十五、GM 调试命令

| 命令 | 说明 |
|------|------|
| `GMPauseSplineMove` | 暂停样条/曲线移动 |
| `GMResumeSplineMove` | 恢复样条/曲线移动 |
| `GMServerShowMovePos` | 显示目标实体的服务端位置 |
| `GMServerShowSelfMovePos` | 显示自己的服务端位置 |
| `GMAvatarMoveToLocation` | 服务端控制移动到指定位置 |
| `GMMoveVerifySwitch` | 全局开关移动校验 |

---

## 十六、关键文件索引

| 模块 | 关键文件 |
|------|---------|
| C++ 移动核心 | `move/actor_move.hpp/cpp` |
| C++ 移动状态 | `move/actor_move_state.hpp/cpp` |
| C++ 旋转状态 | `move/actor_rotate_state.hpp/cpp` |
| C++ 碰撞检测 | `move/actor_collision.hpp/cpp` |
| C++ 行为移动 | `move/behavior/behavior_move.hpp/cpp` |
| C++ 移动常量 | `move/move_define.hpp` |
| C++ 引力场 | `move/gravitational_field.hpp/cpp` |
| C++ 样条曲线 | `move/spline_curve.hpp/cpp` |
| C++ Lua 绑定 | `lua_actor.hpp/cpp` |
| C++ 协议 | `protocol.hpp/cpp` |
| Lua 移动组件 | `Logic/Components/MoveComponent.lua` |
| Lua AI 移动 | `Logic/Components/BehaviorMoveComponent.lua` |
| Lua 曲线移动 | `Logic/Components/CurveMovementComponent.lua` |
| Lua 剧情移动 | `Logic/Components/Flowchart/FlowchartMoveComponent.lua` |
| Lua 双人移动 | `Logic/Components/DualMoveComponent.lua` |
| Lua 平台乘客 | `Logic/Components/MovePlatformPassengerComponent.lua` |
| 客户端移动 | `Client/Content/Script/Gameplay/NetEntities/Comps/MoveComponent.lua` |
| 客户端自动寻路 | `Client/Content/Script/Gameplay/LogicSystem/AutoNavigation/AutoNavigationSystem.lua` |
| 客户端输入 | `Client/Content/Script/Gameplay/3C/Input/Module/InputMoveMgr.lua` |
| 网络协议定义 | `Client/Content/Script/Data/NetDefs/MoveComponent.xml` |
| GM 命令 | `Logic/GM/Avatar/GMAvatarMove.lua`, `Logic/GM/Avatar/GMAvatarDebug.lua` |

---

## 十七、时序速览

### 玩家自由移动（每帧）

```
客户端:
  InputMoveMgr 处理输入 -> UE Movement 组件执行本地位移
  -> 二进制协议 ClientSyncMovement 上报服务端

服务端:
  Actor::OnRecvClientMsg(ClientSyncMovement)
    -> ActorMove::HandleSyncMove
      -> VerifyInfo 校验速度/位置
      -> 校验通过: 更新服务端位置, AOI 广播 OnMsgMoveUpdateBroadCast
      -> 校验失败: 强制纠偏 OnMsgSetPosition
```

### NPC 寻路移动

```
AI 行为树决策 -> BehaviorMoveComponent:ReqStartBehaviorMove(target)
  -> MoveComponent:PositionMove(target, moveType)
    -> actor:navi_to_point(x, y, z, range, partial)
      -> C++ ActorMove 切换到 NAVI_TO_POINT 状态
        -> 每帧 Tick: Navmesh 寻路 + 沿路径移动
          -> 到达目标: onMoveFinish() 回调 Lua
```

### 技能 RootMotion

```
SkillComp::PlayerCastSkill
  -> CombatEffectComp 执行 movement_frame_task / movement_span_task
    -> MoveComponent:ApplyRootMotion(params)
      -> actor:start_root_motion(dx,dy,dz,duration,...)
        -> C++ ActorMove 切换到 ROOT_MOTION 状态
          -> 同步客户端 OnMsgStartRootMotion
          -> 每帧 Tick: 插值位移
            -> 完成: 切回 IDLE, 回调 Lua onMoveFinish()
```

### 传送流程

```
客户端: ReqTeleportPoint(pointID)
  -> 服务端 MoveComponent 校验 (CD/条件/距离)
    -> actor:teleport(x, y, z, yaw, TELEPORT_FAR)
      -> C++ 更新位置
      -> 通知客户端 OnMsgSetPosition
        -> 客户端开始 Loading
          -> 场景加载完成
            -> ClientNotifySceneLoaded(sequence)
              -> 服务端确认, 恢复正常同步
```

---

## 十八、扩展指南

### 新增移动状态

1. 在 `MoveState` 枚举中添加新状态
2. 在 `actor_move_state.hpp/cpp` 中实现对应状态类（继承状态基类）
3. 在 `ActorMove` 中添加实例并注册到状态数组
4. 在 `lua_actor.cpp` 中添加 Lua 绑定（如需 Lua 调用）

### 新增行为移动

1. 在 `move/behavior/` 下实现状态类（继承 `BehaviorMoveStateBase`）
2. 在 `BehaviorMove` 中添加到 `states_[]` 数组
3. 在 `lua_actor.cpp` 中添加 Lua 绑定

### 新增移动 RPC

1. 在 `Data/NetDefs/MoveComponent.xml` 中定义新的 RPC 方法
2. 服务端 `MoveComponent.lua` 中实现 Handler
3. 客户端 `MoveComponent.lua` 中实现对应处理

### 新增移动 Effect Action

1. 在 `combat/effect/task/frame/movement_frame_task.cpp` 或 `span/movement_span_task.cpp` 中实现
2. 在 `CombatEffectManager::RegisterActions()` 中注册
3. 确保配置数据中已定义对应 Action 类型
