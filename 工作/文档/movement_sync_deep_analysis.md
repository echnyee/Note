# 玩家移动同步流程深度分析

> 本文档是 `player_movement_system.md` 的补充，深入剖析移动同步的完整链路。
> 第一部分（一~十五章）分析客户端主控移动：协议编解码、服务端校验、AOI 广播、外推预测。
> 第二部分（十六~十八章）分析服务端主控移动：玩家被接管的触发机制、NPC/怪物移动系统、广播 flags 与 locomotion_state。

---

## 一、总体架构：客户端权威 + 服务端校验

本项目的移动同步采用 **客户端权威（Client-Authoritative）** 模型：

1. **客户端**直接计算自己的位置，以 ~12-14Hz 频率上报给服务端（实测中位间隔 ~73ms）最高频率是15Hz，玩家移动状态变化少的时候会更低
2. **服务端**不做物理模拟，只做合法性校验（速度、位置）
3. 校验通过后，服务端将原始二进制数据 **零拷贝转发** 给 AOI 范围内的其他客户端
4. 校验不通过时，服务端执行 **位置回拉（CorrectClientPosition）**

核心移动同步 **不走 Lua RPC**，而是通过 **unreliable 二进制通道** 直接在 C++ 层处理：
- 上行协议字节: `ClientSyncMovement = 1`
- 下行协议字节: `ServerSyncMovement = 2`（全量）、`ServerSyncBriefMovement = 6`（简要）

```
┌──────────┐    unreliable binary     ┌──────────┐    AOI broadcast     ┌──────────┐
│  Client A │  ──────────────────────> │  Server  │  ─────────────────> │  Client B │
│ (自己移动) │   ClientSyncMovement=1  │  (C++层)  │  ServerSyncMove=2  │ (远端渲染) │
└──────────┘                          └──────────┘   or raw relay      └──────────┘
```

---

## 二、上行协议：ClientSyncMovement 二进制格式

### 2.1 协议结构

客户端每次移动状态变化时通过 unreliable channel 发送 `ClientSyncMovement` 报文，实测频率约 12-14Hz。

**源码**: `protocol.cpp:72-97` — `PackClientMoveMsg`

```
字节布局:
[1B] protocol = 1 (ClientSyncMovement)
[4B] timestamp (int32, 微秒, 循环计数器, 上限 1800000000us = 30min)
[12B] position (3 × float32: x, y, z)
[2B] rotation.yaw (int16)
[12B] velocity (3 × float32: vx, vy, vz)
[2B] move_time (int16, 毫秒, 表示"按当前速度还能移动多久")
[1B] locomotion_state (uint8, 动画状态)
[1B] flags (uint8, 低8位; 若 FLAG_EXTENSION 置位则再追加1B高8位)
--- 可选字段 ---
[?B] 骑乘数据 (FLAG_RIDING): pitch(2B) + root_offset(2B) + roll(2B)
[?B] 相对坐标 (FLAG_RELATIVE): relative_pos(12B) + relative_yaw(2B) + relative_vel(12B)
[?B] 重力缩放 (FLAG_JUMPING & FLAG_GRAVITY_SCALE): gravity_scale(2B)
[?B] 控制实体 (FLAG_CONTROL_ENTITY): control_entity_id(8B)
```

### 2.2 标志位定义

**源码**: `protocol.hpp:26-37`

| 标志位 | 值 | 含义 |
|--------|------|------|
| `FLAG_IS_LOCO_START` | `1` | 移动开始标记（用于客户端动画状态切换） |
| `FLAG_JUMPING` | `1<<1` | 跳跃中 |
| `FLAG_RIDING` | `1<<2` | 骑乘中（携带额外骑乘数据） |
| `FLAG_RESET_LOCO_PROGRESS` | `1<<3` | 重置动画进度 |
| `FLAG_RELATIVE` | `1<<4` | 相对坐标模式（在移动平台上） |
| `FLAG_FLOATING` | `1<<5` | 浮空状态 |
| `FLAG_GRAVITY_SCALE` | `1<<6` | 自定义重力缩放（与 JUMPING 配合） |
| `FLAG_EXTENSION` | `1<<7` | 扩展标志（高8位在下一字节） |
| `FLAG_3D_ROTATION` | `1<<8` | 3D旋转（含 pitch/roll） |
| `FLAG_TARGET_DIRECTION` | `1<<9` | 目标朝向 |
| `FLAG_SERVER_LOCO_STATE` | `1<<10` | 服务端动画状态 |
| `FLAG_CONTROL_ENTITY` | `1<<11` | 控制其他实体移动 |

### 2.3 基础包大小

最小包体（无可选字段）: 1 + 4 + 12 + 2 + 12 + 2 + 1 + 1 = **35 字节**

---

## 三、服务端入口：HandleSyncMove 逐行分析

**源码**: `actor_move.cpp:402-492`

### 3.1 入口函数（消息解包 + 控制实体转发）

```cpp
void ActorMove::HandleSyncMove(ReadBuffer &&buffer)    // :402
{
    ClientMovementMsg msg = UnpackClientMoveMsg(&buffer);  // 反序列化
    if (msg.control_entity_id != INVALID_ENTITY_IID) {     // FLAG_CONTROL_ENTITY
        // 客户端控制的不是自己，而是另一个实体（如载具）
        if (Actor *control_actor = SCENE.GetActorByIID(msg.control_entity_id))
            control_actor->GetActorMove().HandleSyncMove(msg, buffer.GetData(), buffer.GetSize());
    } else {
        HandleSyncMove(msg, buffer.GetData(), buffer.GetSize());  // 正常处理
    }
}
```

关键点：`control_entity_id` 机制允许客户端移动一个"被控实体"而非自身角色（如骑乘的坐骑）。

### 3.2 核心处理函数

```cpp
void ActorMove::HandleSyncMove(const ClientMovementMsg &msg, const char *data, size_t size)  // :414
```

**前置检查链**（任一不通过则丢弃消息）:

| 行号 | 检查 | 说明 |
|------|------|------|
| 417 | `ControlledBy::SERVER` | 服务端控制中，忽略客户端移动 |
| 420 | `!space` | 不在场景中 |
| 424 | `need_handshake_` | 需要握手确认（进入场景/传送后） |
| 428-433 | `teleport_wait_ack_sequence_` | 等待传送确认中（超时 10s 后强制跳过） |
| 437-439 | 特殊移动状态 | `STRAIGHT_MOVE`/`PHYSIC_FALL`/`CLIENT_PERFORM`/`ROOT_MOTION` 期间拒绝客户端同步 |

**核心处理流程**:

```
1. 坐标转换: to_pos.z -= actor_.GetModelHalfHeight()    // :442 客户端发的是胶囊体中心，转脚底
2. 速度校验: VerifyClientMove(msg)                       // :443
   └─ 失败 → CorrectClientPosition(SPEED, to_pos)       // :444 回拉
3. 位置校验: ClientControlledMoveTo(to_pos, false)       // :448 体素寻路检测
   └─ 失败且开启位置校验 → CorrectClientPosition(POSITION, to_pos)  // :450
4. 更新速度: real_velocity_ = msg.velocity               // :462
5. 进入状态: EnterMoveState<MoveStateClientControlled>(msg)  // :464 外推状态
6. 处理旋转: 检查 rotate_wait_ack，设置 yaw              // :466-474
7. 设置变换: actor_.SetTransform(...)                     // :483
8. 更新体素: voxel_agent_.world_position = ...           // :484
9. 设置动画: SetLocomotionState(msg.locomotion_state)    // :485
10. 缓存原始数据: msg_cache_buffer_.write(data, size)    // :487-488
11. AOI广播: actor_.SendAoiMessage(...)                  // :490  ← 零拷贝转发!
12. 简要广播: TryBroadcastMoveBrief()                    // :491
```

---

## 四、速度校验：VerifyClientMove 详解

**源码**: `actor_move.cpp:1313-1390`

速度校验是防外挂的核心机制。采用 **抖动累加器（Jitter Accumulator）** 方案，而非瞬时拒绝。

### 4.1 开关控制

```cpp
if (!verify_info_.enable || !(GetMoveVerifyFlagGlobal() & VERIFY_FLAG_SPEED))
    return true;  // 未开启校验，直接通过
```

校验受两级开关控制：
- `verify_info_.enable`：单个 Actor 的校验开关（Lua 层通过 `SetMoveVerifyEnable` 设置）
- `GetMoveVerifyFlagGlobal()`：全局校验标志位（`VERIFY_FLAG_SPEED=1`, `VERIFY_FLAG_POSITION=2`）

### 4.2 时间戳校验（防加速器）

```cpp
float client_time = (msg.timestamp - last_client_timestamp) / 1000000.0f;  // 客户端经过时间(秒)
float server_time = (now - last_server_timestamp) / 1000.0f;               // 服务端经过时间(秒)
float new_time_discrepancy = time_discrepancy + (client_time - server_time);
```

累计客户端与服务端的时间差。若客户端使用加速器，`client_time` 会大于 `server_time`，差值会持续增长。

**注意**：当前 `time_discrepancy > MAX_MARGIN` 的检查 **已被注释掉**（:1349-1355），原因是弱网场景误判率太高。仅靠速度/距离校验。

### 4.3 速度限制计算

```cpp
float speed_limit = actor_.IsInMount() ? verify_info_.mount_speed_limit : verify_info_.speed_limit;
speed_limit = std::max(speed_limit, params_.speed);  // 取配置速度和当前速度的较大值
```

骑乘和步行使用不同限速。`verify_info_.speed_limit` 和 `verify_info_.mount_speed_limit` 由 Lua 层设置（默认 1000/1000）。

### 4.4 相对坐标豁免

```cpp
if (msg.flags & FLAG_RELATIVE) {
    // 在移动平台上，可能速度超快 → TODO: 之后补相对位置校验
    return true;
}
```

当角色在移动平台上（电梯、载具），使用相对坐标模式，当前 **直接跳过校验**。这是一个已知的安全风险点。

### 4.5 抖动累加器算法

```cpp
Position delta = msg.position - last_client_position;
float dist = delta.length_2d();                              // 只算水平距离
float dist_limit = speed_limit * min(client_time, 1.0f);    // 最大允许距离

if (jitter > 0 || dist > dist_limit) {
    float new_jitter = jitter + (dist - dist_limit) / max(speed_limit, 1.0f);
    if (new_jitter < 0)       → jitter = 0;          // 恢复正常
    if (new_jitter < 1.0)     → jitter = new_jitter;  // 积累但未超限
    if (new_jitter >= 1.0)    → return false;          // 超限! 触发回拉
}
```

**算法解析**:
- `dist - dist_limit`：当次超速距离
- 除以 `speed_limit` 后归一化为"超速秒数"
- 累加到 `jitter`，当 `jitter >= POSITION_JITTER_LIMIT(1.0)` 时触发校验失败
- 如果当次移动距离在合法范围内，`dist - dist_limit` 为负值，会减小 jitter
- 这意味着偶尔的网络抖动不会触发回拉，只有 **持续超速** 才会被检测

**设计优势**: 对网络波动有天然容忍度。瞬时抖动会在后续正常帧中自然恢复。

---

## 五、位置校验：ClientControlledMoveTo

**源码**: `actor_move.cpp:1392-1400`

```cpp
bool ActorMove::ClientControlledMoveTo(const Position &pos, bool force)
{
    return space->MoveToNearby(&voxel_agent_.voxel_position, pos, false,
                                LARGE_CLIMB_HEIGHT, GetAgentHeight(), 0, force);
}
```

这不是简单的坐标赋值，而是通过 **体素寻路系统（Voxel Navigation）** 检测目标位置是否可达：
- `LARGE_CLIMB_HEIGHT = 1000cm`：允许的最大攀爬高度
- `GetAgentHeight()`：角色高度（基于 ModelHalfHeight × 2，默认 144cm）
- 返回 `false` 表示目标位置不可达（如穿墙、卡地形）

当位置校验失败且全局开启了 `VERIFY_FLAG_POSITION` 时，触发回拉。

---

## 六、位置回拉：CorrectClientPosition

**源码**: `actor_move.cpp:1402-1418`

```cpp
void ActorMove::CorrectClientPosition(CorrectPositionReason reason, const Position &to_pos)
{
    StopMove();                                           // 停止移动状态机
    uint32_t sequence = ++msg_sequence_count_;            // 递增序列号
    teleport_wait_ack_sequence_ = sequence;               // 记录等待确认
    teleport_wait_ack_frame_ = SCENE.GetFrame();          // 记录等待帧
    verify_info_.last_client_position = actor_.GetPosition();  // 重置校验基准
    verify_info_.correct_client_sequence = sequence;

    // 发送强制传送包
    BroadcastTeleport(sequence, actor_.GetPositionF(), actor_.GetYaw(),
                      TeleportType::ServerForce, true, static_cast<uint32_t>(reason));
}
```

回拉流程:
1. 停止当前移动，切到 IDLE
2. 生成唯一序列号 `sequence`
3. 向客户端发送 `Teleport` 包（`TeleportType::ServerForce`），`need_ack=true`
4. 进入"等待确认"状态：在收到 `TeleportAck` 之前，所有客户端移动包被 **丢弃**（:428-432）
5. 超时保护：等待超过 10 秒（`MAX_WAIT_ACK_TIME`）后强制跳过

---

## 七、AOI 广播：零拷贝转发 vs 服务端重打包

移动数据的下行广播有两条路径，取决于移动的控制方：

### 7.1 客户端控制的移动（零拷贝转发）

**源码**: `actor_move.cpp:490`

```cpp
actor_.SendAoiMessage(enable_debug_, 
    enable_sync_degradation_ ? AOI_MSG_LV_PRIMARY : AOI_MSG_LV_ALL,
    data, size);
```

客户端上报的 **原始二进制数据** 直接作为 AOI 消息转发，不经过任何重新序列化。这是性能优化的关键：
- `data` / `size` 就是 `UnpackClientMoveMsg` 前的原始 buffer
- 其他客户端收到的协议字节仍是 `ClientSyncMovement = 1`
- 服务端开销极低：仅解包校验，不重新打包

### 7.2 服务端控制的移动（重新打包）

**源码**: `actor_move.cpp:1420-1440` — `BroadcastMoveFull`

```cpp
void ActorMove::BroadcastMoveFull(const FVector3 &velocity, uint16_t flags, bool force_all)
{
    float move_time = state_ == IDLE ? 0.0f : min(GetPredictMoveTime(), 1.0f);
    WriteBuffer &buffer = actor_.GetSendBuffer();
    PackServerMoveMsg(&buffer, sync_timestamp_, actor_.GetPosition(), actor_.GetDirection(),
                      velocity, (int16_t)(move_time * 1000), flags, target_yaw_, locomotion_state_);
    actor_.SendAoiMessage(true, ..., buffer.GetDataBegin(), buffer.GetWritten());
}
```

服务端主动移动（寻路、技能位移等）使用 `ServerSyncMovement = 2` 协议，需要重新序列化。包含额外字段如 `target_yaw`（目标朝向）和 `locomotion_state`（动画状态）。

### 7.3 AOI 层级与同步降级

**源码**: `scene_logic_define.hpp:32-35`

```cpp
AOI_MSG_LV_PRIMARY   = 1   // 一级 AOI（近距离）
AOI_MSG_LV_SECONDARY = 2   // 二级 AOI（远距离）
AOI_MSG_LV_ALL       = 3   // 全部 AOI
```

AOI 系统分两层：

| 层级 | 接收内容 | 频率 | 说明 |
|------|---------|------|------|
| **PRIMARY** | 全量移动数据（位置+速度+旋转+动画） | ~12-14Hz（每次客户端上报） | 近距离玩家，完整同步 |
| **SECONDARY** | 简要移动数据（仅位置） | 1Hz（每秒一次） | 远距离玩家，低频降级 |

开启同步降级时（`enable_sync_degradation_ = true`）：
- 客户端移动：全量数据只发 PRIMARY 层，SECONDARY 层走简要广播
- 服务端移动：可通过 `force_all` 参数强制发给所有层

### 7.4 简要广播：TryBroadcastMoveBrief

**源码**: `actor_move.cpp:1482-1504`

```cpp
void ActorMove::TryBroadcastMoveBrief()
{
    if (!enable_sync_degradation_ || cur_frame < need_sync_brief_frame_)
        return;
    if (!equalf(last_sync_brief_position_, actor_.GetPosition())) {
        PackServerBriefMoveMsg(&buffer, sync_timestamp_, actor_.GetPosition());
        actor_.SendAoiMessage(false, AOI_MSG_LV_SECONDARY, ...);
        need_sync_brief_frame_ = cur_frame + SCENE.GetFrameRate();  // 下次=1秒后
    }
}
```

简要广播包体极小: `1B(protocol=6) + 4B(timestamp) + 12B(position)` = **17 字节**。
仅在位置实际变化时才发送。

---

## 八、服务端外推：MoveStateClientControlled

**源码**: `actor_move_state.cpp:409-453`

当客户端移动包到达服务端后，通过 `EnterMoveState<MoveStateClientControlled>(msg)` 进入此状态。

### 8.1 状态初始化

```cpp
bool MoveStateClientControlled::Enter(const ClientMovementMsg &msg)
{
    remain_move_time_ = msg.move_time;    // 客户端报告的剩余可移动时间
    velocity_ = msg.velocity;              // 当前速度向量
    flags_ = msg.flags;
    is_jumping_ = flags_ & FLAG_JUMPING;
    gravity_ = PHYSIC_GRAVITY * msg.gravity_scale / DEFAULT_GRAVITY_SCALE;  // 3185 * scale / 3.25
    handle_sync_frame_ = SCENE.GetFrame();
    return true;
}
```

### 8.2 帧更新（外推）

```cpp
void MoveStateClientControlled::OnUpdate(frame_t frame)
{
    if (frame <= handle_sync_frame_ + 1)   // 接收帧+1帧内不外推
        return;
    if (remain_move_time_ <= 0.0f)         // 外推时间耗尽
        return;

    float move_time = min(SCENE.GetFrameTime(), remain_move_time_);
    remain_move_time_ -= move_time;

    if (is_jumping_) {
        // 跳跃：速度受重力影响
        float final_vz = velocity_.z - move_time * gravity_;
        velocity_.z = (velocity_.z + final_vz) / 2.0f;  // 梯形积分
        pos += velocity_ * move_time;
        velocity_.z = final_vz;
    } else {
        // 地面：匀速外推
        pos += velocity_ * move_time;
    }
    ClientControlledMoveTo(pos, false);   // 体素碰撞检测
}
```

**外推策略**:
- 外推时间 = `msg.move_time`（客户端硬编码 1.5s，作为外推燃料的最大窗口，详见第十五章分析）
- 正常情况下，下一个客户端包到达（~73ms 后）即重置 `remain_move_time_`，实际只消耗 2-3 帧
- 收到包后的 **下一帧** 才开始外推（`handle_sync_frame_ + 1`），避免当帧双重移动
- 跳跃使用梯形积分计算重力加速度
- 外推位置经过体素碰撞检测

**核心意义**: 外推使服务端在两次客户端上报之间也能持续更新 Actor 位置，AOI 范围判断、碰撞检测等都能基于更精确的位置工作。

---

## 九、服务端移动的全量广播触发条件

**源码**: `actor_move.cpp:1442-1480` — `TryBroadcastMoveFull`

此函数仅在服务端控制的移动（`ControlledBy::SERVER`）时触发。每帧 Tick 末尾调用。

### 9.1 触发条件（任一满足即广播）

```cpp
if (prev_state != state_                              // 移动状态变化
    || prev_rotate_state != rotate_state_              // 旋转状态变化
    || rotation_changed                                 // 朝向变化
    || !equalf(last_sync_velocity_, sync_velocity)     // 速度变化
    || last_sync_flags_ != flags                       // 标志位变化
    || last_sync_locomotion_state_ != locomotion_state_ // 动画状态变化
    || (velocity_zero && !equalf(last_sync_position_, position))  // 静止但位置变化
    || cur_frame >= need_sync_full_frame_)              // 定时强制同步
{
    BroadcastMoveFull(sync_velocity, flags);
}
```

### 9.2 定时强制同步

```cpp
frame_t move_frame = (state_ == IDLE)
    ? 10 * frame_rate    // 静止状态: 每10秒
    : ceil(move_time / frame_time);  // 移动状态: 按move_time计算(约1帧)
need_sync_full_frame_ = cur_frame + move_frame;
```

- **移动中**: 几乎每帧都会因速度/位置变化而触发广播
- **静止时**: 最多每 10 秒同步一次（确保新进入 AOI 的玩家能看到正确位置）

---

## 十、握手机制：Handshake

**源码**: `actor_move.cpp` + `move_define.hpp:40-41`

进入新场景或传送后，客户端和服务端需要进行握手同步。

### 10.1 触发时机

```cpp
void ActorMove::OnEnterSpace()
{
    need_handshake_ = (actor_.GetControlledBy() == ControlledBy::CLIENT);
    ResetVerifyInfo();
}
```

### 10.2 握手流程

```
Client                          Server
  │                                │
  │  ←── HandshakeRequest ──────  │   (服务端定期发送, 每15帧检查一次)
  │                                │
  │  ──── HandshakeAck ────────→  │   (客户端回复确认)
  │                                │
  │  need_handshake_ = false       │
  │  开始接受移动同步消息           │
```

在 `need_handshake_` 为 `true` 期间，所有 `HandleSyncMove` 消息被 **丢弃**（:424-427）。

握手协议使用 `Handshake = 9`，包体仅 `1B(protocol) + 4B(space_id)` = 5 字节。

---

## 十一、Tick 帧循环总览

**源码**: `actor_move.cpp:93-149`

每个服务端逻辑帧（默认 30Hz），ActorMove::Tick 执行以下步骤:

```
1. sync_timestamp_ += frame_time * 1000000   // 微秒级时间戳递增
2. 检查位置变化 → UpdateVoxelPoint()          // 体素坐标重算
3. states_[state_]->OnUpdate(frame)           // 移动状态机 Tick
4. 旋转状态机 Tick
5. 逻辑位移叠加器 Tick                         // 引力场等外力
6. ApplyGravity()                              // 重力
7. real_velocity_ = (pos_after - pos_before) / dt  // 计算实际速度
8. CheckTriggerMoveEvent()                     // 移动事件检测
9. CheckNeedHandshakeRequest()                 // 握手检查
10. CheckOnFallingFloor()                      // 掉落检测
11. ConsumeMoveEvent()                         // 消费移动事件
12. TryBroadcastMoveFull()                     // 全量广播(服务端移动)
13. TryBroadcastMoveBrief()                    // 简要广播(同步降级)
```

---

## 十二、关键常量速查表

| 常量 | 值 | 含义 | 源文件 |
|------|------|------|--------|
| `DEFAULT_SPEED` | 300 cm/s | 默认移动速度 | `move_define.hpp:31` |
| `PHYSIC_GRAVITY` | 3185 cm/s² | 物理重力加速度 | `move_define.hpp:46` |
| `JUMP_INIT_VELOCITY` | 1170 cm/s | 跳跃初速度 | `move_define.hpp:45` |
| `VELOCITY_ZMAX` | 2000 cm/s | Z轴速度上限 | `move_define.hpp:47` |
| `VELOCITY_ZMIN` | -4000 cm/s | Z轴速度下限 | `move_define.hpp:48` |
| `MAX_SYNC_TIMESTAMP` | 1800000000 us | 时间戳循环上限(30min) | `move_define.hpp:50` |
| `MAX_WAIT_ACK_TIME` | 10 s | 传送确认超时 | `move_define.hpp:51` |
| `MOVE_EXTRAPOLATION_RATIO` | 0.5 | 外推比例 | `move_define.hpp:43` |
| `POSITION_JITTER_LIMIT` | 1.0 | 抖动累加器阈值 | `move_define.hpp:67` |
| `VERIFY_MAX_CLIENT_TIME` | 1.0 s | 单次校验最大时间窗口 | `move_define.hpp:68` |
| `DEFAULT_GRAVITY_SCALE` | 3.25 | 默认重力缩放 | `protocol.hpp:42` |
| `DEFAULT_CLIMB_HEIGHT` | 35 cm | 默认攀爬高度 | `move_define.hpp:25` |
| `LARGE_CLIMB_HEIGHT` | 1000 cm | 客户端控制最大攀爬高度 | `move_define.hpp:28` |
| `DEFAULT_AGENT_HEIGHT` | 144 cm | 默认角色高度 | `move_define.hpp:26` |
| `HANDSHAKE_REQUEST_INTERVAL` | 15 帧 | 握手请求间隔 | `move_define.hpp:40` |

---

## 十三、安全风险与优化建议

### 已知风险

1. **FLAG_RELATIVE 跳过校验** (`:1362-1367`): 移动平台上的相对坐标模式完全跳过速度校验，注释标注为 TODO
2. **时间差校验被注释** (`:1349-1355`): 客户端加速器检测被禁用，仅靠位移距离校验
3. **零拷贝转发的信任问题**: 客户端原始数据直接转发给其他客户端，恶意构造的数据包可能影响其他客户端渲染

### 优化方向

1. **相对坐标校验**: 实现移动平台上的相对速度校验
2. **时间差校验恢复**: 改进抗抖动算法后重新启用时间差检测
3. **服务端重打包模式**: 对高安全场景（PvP），考虑不零拷贝转发，改为服务端重新打包

---

## 十四、数据流总结图

```
                         ┌─────────────────────────────────────────────────────┐
                         │                    Server (C++ Layer)                │
                         │                                                     │
  Client A               │   HandleSyncMove                                    │   Client B (PRIMARY AOI)
  ─────────────────────> │   ├── UnpackClientMoveMsg()                         │ ──────────────────────>
  ClientSyncMovement=1   │   ├── VerifyClientMove()     ┌─→ SendAoiMessage()  │  原始二进制数据(零拷贝)
  ~35 bytes, ~12-14Hz       │   │   └── 抖动累加器校验     │   (PRIMARY层)        │  ~35 bytes, ~12-14Hz
                         │   ├── ClientControlledMoveTo()│                     │
                         │   │   └── 体素碰撞检测       │                     │   Client C (SECONDARY AOI)
                         │   ├── SetTransform()          │                     │ ──────────────────────>
                         │   ├── EnterMoveState()        │                     │  ServerSyncBriefMove=6
                         │   └── 零拷贝转发 ─────────────┘                     │  ~17 bytes, ~1Hz
                         │                                                     │
                         │   [校验失败时]                                       │
                         │   └── CorrectClientPosition()                       │
                         │       └── BroadcastTeleport() → Client A            │
                         │           (ServerForce, need_ack=true)              │
                         └─────────────────────────────────────────────────────┘
```

---

## 十五、实战日志分析：移动包上行行为

> 本章基于真实抓包日志（`debug_move.log`，40 行），通过在 `HandleSyncMove` 内添加 `[MOVE_DEBUG]` 日志，
> 完整记录了一次"向左走 → 停下 → 转身 → 向右冲刺 → 跑步 → 停下"的操作过程。
> 用于验证上行协议的实际行为，包括 locomotion_state 状态机、同步频率、move_time 含义、flags 规律和速度曲线。

### 15.1 LocoAnimState ID 名称映射

日志中出现的 `locomotion_state` 均为 uint8 整数。其含义定义在客户端 Lua 层：

**源码**: `Shared/Const/ParallelBehaviorControlConst.lua:61-134` — `LOCO_ANIM_STATE_CONST`

| ID | 常量名 | 含义 | 对应 MoveCorrector 类型 |
|----|--------|------|-------------------------|
| 1 | `Idle` | 静止站立 | None（无插值） |
| 2 | `RunStart` | 起步加速阶段 | OnGroundCorrector |
| 3 | `Run` | 稳定奔跑 | OnGroundCorrector |
| 4 | `RunEnd` | 减速制动（松开方向键后的惯性滑行） | OnGroundCorrector |
| 5 | `MoveTurn` | 移动中转向（低速/静止时改变方向） | None |
| 59 | `Dash` | 冲刺（短暂爆发加速） | None |
| 60 | `DashRestart` | 冲刺后恢复跑步的过渡状态 | OnGroundCorrector |

> 完整的 LocoAnimState 共 80+ 种，覆盖跳跃、游泳、骑乘、攀爬、眩晕等。
> MoveCorrector 类型决定了远端客户端如何对该状态下的运动做插值（详见 `LocoAnimStateDefineData.lua`）。

### 15.2 日志阶段划分

完整操作分为 6 个阶段，下面逐阶段分析服务端收到的移动包：

#### 阶段 1：向左起步加速（Line 1-8, t=43.187~44.144, loco=2 RunStart）

```
行  时间戳     loco  speed   flags   yaw    说明
1   43.187     2     0.0     0x0001  -107   起步帧，速度为 0，刚按下方向键
2   43.238     2     21.0    0x0001  -142   开始加速，yaw 转向左方
3   43.301     2     436.3   0x0001  -165   急剧加速
4   43.374     2     453.2   0x0001  -173   继续加速
5   43.461     2     589.3   0x0001  -176   接近最大步行速度
6   43.524     2     565.3   0x0001  -178   yaw 趋于稳定
7   43.598     2     527.3   0x0001  -178   速度在 ~560 cm/s 附近震荡
8   44.144     2     572.3   0x0001  -178   RunStart 持续约 960ms
```

**观察**：
- RunStart 持续约 **960ms**（Line 1→8），之后才切到 Run
- yaw 从 -107° → -178°，角色朝向逐渐转向正左方（-180°）
- 速度从 0 加速到 ~590 cm/s，加速率约 **2200 cm/s²**
- Line 7→8 间隔 **546ms**——推测中间有丢包或客户端降低了发送频率

#### 阶段 2：稳定向左跑（Line 9-11, t=44.216~44.342, loco=3 Run）

```
行  时间戳     loco  speed   flags   yaw
9   44.216     3     442.3   0x0001  -178
10  44.269     3     582.3   0x0001  -178
11  44.342     3     595.3   0x0001  -178
```

**观察**：Run 状态仅持续 ~130ms（3 个包），说明玩家很快松开了方向键。

#### 阶段 3：向左减速停下（Line 12-16, t=44.612~44.884, loco=4 RunEnd）

```
行  时间戳     loco  speed   flags   yaw    说明
12  44.612     4     547.3   0x0000  -178   松开方向键，flags 立刻清零
13  44.676     4     364.2   0x0000  -178   减速中
14  44.738     4     200.1   0x0000  -178   减速中
15  44.821     4     68.0    0x0000  -178   即将停下
16  44.884     4     0.0     0x0000  -178   完全停止，move_time=0.000
```

**关键发现**：
- **flags 在松开按键瞬间变为 0x0000**：`FLAG_IS_LOCO_START` 清零，表示玩家不再有输入
- 减速曲线：547 → 364 → 200 → 68 → 0，约 **272ms** 从 547 降到 0
- 减速率约 **2000 cm/s²**，与 UE `MaxBrakingDeceleration=2048` 高度吻合
- **Line 16 speed=0 且 move_time=0.000**：确认完全静止，客户端不再上报运动数据

#### 阶段 4：转向——从左到右（Line 17-21, t=45.367~45.650, loco=5 MoveTurn）

```
行  时间戳     loco  speed   flags   yaw    说明
17  45.367     5     14.0    0x0001  -178   停下 ~480ms 后重新按键，开始转向
18  45.437     5     160.1   0x0001  -178   惯性仍朝左运动
19  45.511     5     30.0    0x0001  +101   yaw 突变！角色开始转向右方
20  45.586     5     0.0     0x0001  +17    转向中速度降为 0
21  45.650     5     281.1   0x0001  +2     转向完成，开始朝右加速
```

**关键发现**：
- 停下后 **~480ms 间隔**（Line 16→17, 44.884→45.367）才收到转向包
- yaw 在 Line 18→19 之间发生剧变：-178° → +101° → +17° → +2°
- 表明客户端在 MoveTurn 状态中执行了一次 **快速插值转向**
- 速度曲线先降后升：14→160→30→0→281，先因惯性滑向旧方向，再朝新方向加速
- flags 回到 0x0001，因为这是新的输入开始

#### 阶段 5：冲刺 + 冲刺恢复（Line 22-27, t=45.692~46.914, loco=59→60）

```
行  时间戳     loco  speed    flags   yaw   说明
22  45.692     59    531.3    0x0001  2     进入 Dash（冲刺）
23  45.742     59    2245.4   0x0001  2     冲刺峰值！接近 mount_speed_limit=3000
24  46.701     59    1184.7   0x0001  2     冲刺减速（中间 959ms 间隔）
25  46.735     60    58.0     0x0001  2     切到 DashRestart，速度骤降
26  46.838     60    747.5    0x0001  2     恢复加速
27  46.914     60    925.6    0x0001  2     DashRestart 阶段速度偏高
```

**关键发现**：
- **Dash 峰值速度 2245 cm/s**，约 3.8 倍正常跑速，接近安全上限 `mount_speed_limit=3000`
- Line 23→24 间隔 **959ms**——冲刺期间可能丢包或客户端降低上传频率
- DashRestart(60) 即冲刺结束后过渡回跑步，速度从 58 快速回升到 925

#### 阶段 6：稳定跑 → 减速停下 → Idle（Line 28-40, t=47.706~50.952, loco=3→4→1）

```
行  时间戳     loco  speed   flags   yaw   说明
28  47.706     3     921.6   0x0001  2     稳定跑步
29  47.775     3     886.5   0x0001  2     跑步中
30  47.934     4     276.1   0x0000  2     松键，进入 RunEnd
31  48.018     4     181.1   0x0000  2     减速
32  48.367     4     209.1   0x0000  2     ┐ 两包同一毫秒到达
33  48.367     4     183.1   0x0000  2     ┘ （服务端同 Tick 处理）
34  48.569     4     110.0   0x0000  2     减速
35  48.678     4     54.0    0x0000  2     减速
36  48.817     4     29.0    0x0000  2     减速
37  48.900     4     18.0    0x0000  2     低速
38  50.276     4     7.0     0x0000  2     ← 间隔 1376ms，低速时上传频率大幅降低
39  50.784     1     2.0     0x0000  2     切到 Idle
40  50.952     1     0.0     0x0000  2     完全静止，move_time=0.000
```

**关键发现**：
- 第二次 RunEnd 持续更长（**~900ms**），因为从更高速度减速
- Line 32-33 时间戳完全相同（48.367），两个包在同一个服务端 Tick 中被处理
- Line 37→38 间隔 **1376ms**——当速度已非常低时，客户端显著降低了上传频率
- 从 RunEnd 到 Idle 需要速度降到接近 0

### 15.3 locomotion_state 状态机

从日志中观察到的状态转换规则：

```
                    ┌──────────────────────────────────────────────────────┐
                    │                                                      │
                    ▼                                                      │
    Idle(1) ──[按键]──→ RunStart(2) ──[速度稳定]──→ Run(3) ──[松键]──→ RunEnd(4) ──[停止]──→ Idle(1)
                                                       │
                                                       ├──[冲刺键]──→ Dash(59) ──→ DashRestart(60) ──→ Run(3)
                                                       │
    RunEnd(4)/Idle(1) ──[反向按键]──→ MoveTurn(5) ──→ Dash(59) 或 RunStart(2)
```

**状态转换规则**：
- **RunStart(2)** 是起步加速的过渡状态，持续到速度稳定后切到 Run(3)
- **Run(3)** 是稳定奔跑，只要有持续输入就维持
- **RunEnd(4)** 松开方向键后的惯性制动，由 UE 的 `MaxBrakingDeceleration` 控制
- **MoveTurn(5)** 仅在已停下或低速时改变方向使用；高速跑步中直接改变 yaw 不触发 MoveTurn
- **Dash(59)** 是短暂冲刺爆发，持续约 1 秒
- **DashRestart(60)** 是冲刺结束后的过渡，速度从冲刺峰值逐渐回落到正常跑速

### 15.4 同步频率分析

对 40 行日志计算相邻包的时间间隔统计（排除 > 300ms 的操作间隔/丢包）：

| 指标 | 值 |
|------|-----|
| 有效样本 | 32 对 |
| 最小间隔 | 0.06 ms（两包在同一 Tick） |
| 最大间隔（滤除 gap） | 269.9 ms |
| **平均间隔** | **86.0 ms** |
| **中位间隔** | **72.6 ms** |
| **对应频率** | **~12-14 Hz** |

**分位数分布**：

| 分位数 | 间隔 |
|--------|------|
| P10 | 49.9 ms |
| P25 | 62.9 ms |
| **P50** | **72.9 ms** |
| P75 | 86.7 ms |
| P90 | 159.5 ms |

**关键结论**：
- 实际上传频率约 **12-14 Hz**，远低于之前推测的 30Hz
- 主要集中在 **50-90ms** 区间（21/32 个样本），对应约 4-5 个客户端渲染帧（@60fps）一次上报
- 存在明显的 **自适应降频** 行为：
  - 低速/接近停止时间隔增大（Line 37→38: 1376ms）
  - 冲刺中间间隔增大（Line 23→24: 959ms）
  - 这可能是客户端引擎层的优化策略：速度越低或状态越稳定，上报越稀疏

### 15.5 move_time 字段分析

日志中 `move_time` 只出现两个值：

| move_time | 出现条件 | 出现行号 |
|-----------|----------|----------|
| **0.000** | speed = 0（完全静止帧） | Line 1, 16, 40 |
| **1.500** | speed > 0（任何有运动的帧） | Line 2-15, 17-39 |

#### 协议编解码

`move_time` 以 int16 传输，单位毫秒（`protocol.cpp:13`）：

```cpp
// 解包
msg.move_time = (float)(buffer->ReadInt16()) / 1000.0f;  // 1500 → 1.5f

// 打包（客户端侧，C++ 引擎层硬编码）
buffer->PutInt16(1500);  // 移动中固定写 1500
buffer->PutInt16(0);     // 静止时写 0
```

#### 服务端如何消费 move_time

`move_time` 在服务端的唯一消费方是 `MoveStateClientControlled`：

```cpp
// Enter() — 每收到一个客户端包就重置
remain_move_time_ = msg.move_time;  // = 1.5s

// OnUpdate() — 每帧消耗
float move_time = min(frame_time, remain_move_time_);  // 每帧 ~33ms
remain_move_time_ -= move_time;
pos += velocity_ * move_time;  // 按最后速度外推
```

正常情况下，下一个客户端包在 ~73ms 后到达，`Enter()` 重置 `remain_move_time_`，
实际只消耗了 **1-2 帧（33-66ms）** 的外推量。1.5s 的窗口远远用不完。

#### 1.5s 的设计意图

1.5s 是一个**容灾窗口**，而非预期的两包间隔：

| 场景 | 到下一包的间隔 | 实际消耗的外推量 | 效果 |
|------|---------------|-----------------|------|
| 正常 | ~73ms | 1-2 帧 | 无感知，下个包立刻覆盖 |
| 轻度丢包 | 200-300ms | 6-9 帧 | 服务端位置仍在平滑前进 |
| 严重丢包 | ~1s | ~30 帧 | entity 沿最后速度滑行 |
| 极端断连 | >1.5s | 1.5s 耗尽 | entity 停止，等待下一包 |

按 13Hz 计算，1.5s ≈ 可以容忍连续 **~20 个包丢失**，entity 仍能在服务端和远端客户端上平滑移动。

#### 零拷贝转发的影响

由于客户端控制的移动是**零拷贝转发**（`actor_move.cpp:499`），`move_time=1500` 被原样广播给其他客户端。
远端客户端的 `MoveCorrector` 也使用这个值作为预测窗口——如果网络抖动导致下一个包迟到，
远端仍能按 1.5s 的余量继续插值，避免远程玩家"走走停停"。

#### 与服务端自身广播的对比

服务端控制的移动（寻路、技能位移等）通过 `BroadcastMoveFull` 重新打包时，move_time 上限为 **1.0s**：

```cpp
float move_time = state_ == IDLE ? 0.0f : min(GetPredictMoveTime(), 1.0f);  // 上限 1.0
```

客户端写 1.5s 而服务端自己用 1.0s，可能是客户端需要多留 0.5s 余量，
因为客户端→服务端→远端客户端路径上有 **双倍延迟**。

### 15.6 flags 标志位规律

日志中 flags 只出现两个值：

| flags | 含义 | 出现时的 locomotion_state |
|-------|------|--------------------------|
| `0x0001` (FLAG_IS_LOCO_START) | 玩家正在主动输入 | RunStart(2), Run(3), MoveTurn(5), Dash(59), DashRestart(60) |
| `0x0000` | 玩家无输入，被动运动 | RunEnd(4), Idle(1) |

**规则**: flags 严格反映 **"玩家是否有方向输入"**，而非"是否还有速度"。
RunEnd 阶段虽然角色仍在移动（speed > 0），但 flags=0，因为玩家已松开方向键。

客户端用 `FLAG_IS_LOCO_START` 来告知远端：
- `0x0001`：这是主动移动，远端应该播放起步/跑步动画
- `0x0000`：这是被动减速，远端应该播放刹车/停止动画

### 15.7 速度曲线特征

从日志提取的各阶段速度特征：

| 阶段 | 峰值速度 | 持续时间 | 速率 | 说明 |
|------|---------|---------|------|------|
| 起步加速 (RunStart) | ~590 cm/s | ~270ms | 加速 ~2200 cm/s² | 0 → 590 |
| 稳定跑步 (Run) | ~580-600 cm/s | 持续 | 匀速 | 步行最大速度 |
| 减速制动 (RunEnd) | → 0 cm/s | ~272ms | 减速 ~2000 cm/s² | 与 UE `MaxBrakingDeceleration=2048` 吻合 |
| 冲刺 (Dash) | **2245 cm/s** | ~1s | 爆发 | 约 3.8× 正常跑速 |
| 冲刺恢复 (DashRestart) | ~925 cm/s | ~200ms | 衰减 | 冲刺后速度偏高，逐渐回落 |

**速度曲线图示**（横轴为时间，纵轴为 speed cm/s）：

```
speed
2245 |                                          *  ← Dash 峰值
     |                                         / \
     |                                        /   \
 925 |                                       /     * ← DashRestart
     |                                      /       \
 590 |  **---*****                          /         ****
     | /         \                         /
 400 |/           \                       * ← MoveTurn 加速
     |             \                     /
 200 |              \                   /
     |               \                 /
   0 |*               *----*---------*                    *---*
     |─────────────────────────────────────────────────────────→ time
      起步    跑步  减速  停  转向    冲刺  恢复跑  减速   Idle
      (2)     (3)  (4)        (5)    (59)  (60)(3) (4)    (1)
```

---

## 十六、服务端主控移动：ControlledBy 机制

前面章节分析的都是 **客户端主控（ControlledBy::CLIENT）** 的移动同步流程。本章开始分析另一面——**服务端主控（ControlledBy::SERVER）** 的移动，包括玩家被服务端接管的场景，以及 NPC/怪物的移动系统。

### 16.1 ControlledBy 枚举与切换

**源码**: `actor.hpp:56-60`

```cpp
enum class ControlledBy : uint8_t
{
    CLIENT = 1,
    SERVER = 2,
};
```

所有 Actor 默认是 `ControlledBy::SERVER`。玩家在 `AvatarActor:ctor` 中被设为 CLIENT（`AvatarActor.lua:107`）。

切换时 C++ 会调用 `OnControlByChanged()`（`actor.cpp:1627`），通知移动模块状态变化。

### 16.2 C++ 层 bitmask 机制

**源码**: `actor.cpp:1632-1649`

C++ 提供了带原因的 bitmask 控制接口：

```cpp
enum class ServerControlReasonType : uint64_t
{
    MOVE,              // bit 0
    WEIGHTLESSNESS,    // bit 1 (失重/击飞)
    ROTATE,            // bit 2 (技能旋转)
    Max = 64,
};

void Actor::SetServerControl(bool is_server_control, ServerControlReasonType reason)
{
    uint64_t flag = 1ull << stdx::to_underlying(reason);
    if (is_server_control) {
        server_control_mask_ |= flag;     // 置位
    } else {
        server_control_mask_ &= (~flag);  // 清位
    }
    // 只有当所有原因都清除后，才恢复 CLIENT
    ControlledBy new_controlled_by = server_control_mask_ ? ControlledBy::SERVER : ControlledBy::CLIENT;
    if (GetControlledBy() != new_controlled_by) {
        SetControlledBy(new_controlled_by);
        CallOwnClient_OnMsgSetServerControl(stdx::to_underlying(new_controlled_by) - 1);
    }
}
```

**关键设计**：多个系统可以同时请求 SERVER 控制，只有当 **所有原因都被清除** 时才归还 CLIENT 控制权。例如"击飞 + 技能旋转"同时存在时，击飞结束后如果旋转还没结束，控制权不会归还。

### 16.3 Lua 层控制接口

**源码**: `ActorBase.lua:1943-1988`

```lua
function ActorBase:SetServerControl(bServerControl, reason)
    self.serverControlSource = self.serverControlSource or {}
    if bServerControl then
        self.serverControlSource[Enum.EServerControlReason.MOVE] = true
    else
        self.serverControlSource[Enum.EServerControlReason.MOVE] = nil
    end
    local newValue = next(self.serverControlSource) and 1 or 0
    if newValue == 1 then
        self.actor:set_controlled_by(2) -- server
    else
        self.actor:set_controlled_by(1) -- client
    end
end
```

**架构缺陷**: Lua 层 `SetServerControl` 的 `reason` 参数仅用于日志，实际存储时 **始终使用 `EServerControlReason.MOVE`（值=1）作为 key**。这意味着 Lua 层的 bitmask 退化为单 bit——任何一个系统调用 `SetServerControl(false, ...)` 都会直接清除所有 Lua 层的锁定。

源码注释也承认了这个问题（`ActorBase.lua:1957`）：
> "这些状态控制变量之后全部做到C++去，否则有两套容易出问题"

C++ 的 `SetServerControl` 有正确的多 bit 支持，但 **仅被技能旋转（`movement_span_task.cpp:320`）直接调用**。其余场景都走 Lua 的 `set_controlled_by(2)` 或 Lua `SetServerControl`。

### 16.4 HandleSyncMove 中的拦截

**源码**: `actor_move.cpp:417-440`

当玩家被切到 SERVER 主控后，客户端上行的移动包在 `HandleSyncMove` 入口处被直接丢弃：

```cpp
void ActorMove::HandleSyncMove(const ClientMovementMsg &msg)
{
    if (actor_.GetControlledBy() == ControlledBy::SERVER) {
        return;  // ← 直接忽略客户端移动包
    }
    // ...
    // 即使没有切到 SERVER，某些移动状态也拒绝客户端包：
    if (state_ == MoveState::STRAIGHT_MOVE || state_ == MoveState::PHYSIC_FALL
        || state_ == MoveState::CLIENT_PERFORM || IsRootMotionState()) {
        return;
    }
    // ...正常处理客户端移动...
}
```

注意第二个拦截条件：即使 `ControlledBy` 仍然是 CLIENT，如果当前 MoveState 是 `STRAIGHT_MOVE`、`PHYSIC_FALL`、`CLIENT_PERFORM` 或任意 `ROOT_MOTION` 状态，客户端移动包同样被忽略。这是因为这些状态由服务端物理或动画驱动位置。

### 16.5 玩家被服务端接管的完整触发场景

以下是代码中所有会将玩家切换到 `ControlledBy::SERVER` 的场景：

| # | 触发场景 | Reason / 备注 | 代码位置 | 接管方式 |
|---|---------|--------------|---------|---------|
| 1 | **击飞/失重（被炸飞）** | `EServerControlReason.WEIGHTLESSNESS` | `MoveComponent.lua:973` | Lua `SetServerControl` + C++ `set_weightlessness` |
| 2 | **技能旋转** | `ServerControlReasonType::ROTATE` | C++ `movement_span_task.cpp:320` | **C++ bitmask**（唯一使用 C++ bitmask 的场景） |
| 3 | **技能旋转（Lua路径）** | `"RotateAction"` | `TaskMovementSpan.lua:167` | Lua `SetServerControl` |
| 4 | **恐惧效果** | `"ActivateEffectTerror"` | `StateComponent.lua:174` | Lua `SetServerControl` |
| 5 | **角色恐惧效果** | `"ActivateEffectCharTerror"` | `StateComponent.lua:193` | Lua `SetServerControl` |
| 6 | **任务过场/剧情控制** | `"EnterQuestControl"` | `QuestActionComponent.lua:159` | Lua `SetServerControl` |
| 7 | **自动战斗（行为树AI）** | `"OnStartFlowchartAI"` | `FlowchartAvatarComponent.lua:179` | Lua `SetServerControl` |
| 8 | **战斗载具下马** | `"CombatVehicle"` | `CombatVehicleComponent.lua:91` | Lua `SetServerControl` |
| 9 | **取消客户端NPC同步** | `"CancelClientSyncNpcMove"` | `AvatarActor.lua:3966,4023` | Lua `SetServerControl` |
| 10 | **GM调试移动** | `"GMAvatarMoveToLocation"` | `GMAvatarDebug.lua:1443` | Lua `SetServerControl` |
| 11 | **机器人/Bot** | 直接设置 | `RobotUtils.lua`, `AutoBattleComponent.lua` | `set_controlled_by(2)` |

### 16.6 客户端通知与防拉扯

当 `ControlledBy` 发生变化时，C++ 会 RPC 通知客户端：

```cpp
// actor.cpp:1648
CallOwnClient_OnMsgSetServerControl(stdx::to_underlying(new_controlled_by) - 1);
// 参数: 0 = CLIENT, 1 = SERVER
```

`ActorBase.lua:1961-1965` 的注释描述了防拉扯流程设计：

```
控制由客户端切到服务器，如果瞬切可能因为服务器还没更新到客户端最新位置而造成拉扯问题
需走以下流程:
1. 客户端禁止移动，并且感知到切换控制模式，同步一次最新位置
2. 服务器更新最新位置（通过标志位），并在服务器切换主控
3. 告知外部系统切换完成
```

### 16.7 控制权归还

各系统在自己的逻辑结束后调用 `SetServerControl(false, reason)` 归还控制权：

- 击飞结束 → `MoveComponent:SetWeightlessness(false)` → `SetServerControl(false, WEIGHTLESSNESS)`
- 恐惧结束 → `StateComponent` 回调 → `SetServerControl(false, ...)`
- 任务过场结束 → `QuestActionComponent` → `SetServerControl(false, "LeaveQuestControl")`
- GM移动完成 → `MoveComponent:1679` → `SetServerControl(false, "OnGMAvatarMoveToLocationFinish")`
- 全清 → `ActorBase:ClearServerControl()` 直接清空 `serverControlSource` 并设回 CLIENT

---

## 十七、NPC/怪物移动系统

NPC 和怪物始终是 `ControlledBy::SERVER`，其移动完全由服务端驱动。本章分析服务端如何管理 NPC 的各种移动行为。

### 17.1 13 种 MoveState

**源码**: `actor_move_state.hpp:28-44`

```cpp
enum class MoveState
{
    IDLE,                    // 0 - 静止
    NAVI_TO_POINT,           // 1 - 寻路到坐标点
    NAVI_TO_ENTITY,          // 2 - 寻路追踪实体
    CUSTOM_MOVE,             // 3 - 自定义移动（Lua控制方向/速度）
    CLIENT_CONTROLLED_MOVE,  // 4 - 客户端同步移动（玩家专用）
    STRAIGHT_MOVE,           // 5 - 直线移动（无视导航网格）
    ROOT_MOTION,             // 6 - 动画驱动位移（有目标点）
    ROOT_MOTION_BY_CURVE,    // 7 - 曲线驱动位移
    ROOT_MOTION_NO_DEST,     // 8 - 动画驱动位移（无目标点）
    PHYSIC_FALL,             // 9 - 物理下落（重力加速度）
    CLIENT_PERFORM,          // 10 - 客户端表演
    WAY_POINT_MOVE,          // 11 - 路径点巡逻
    FIXED_PATH_MOVE,         // 12 - 固定路径移动
    MAX,
};
```

每种 MoveState 对应一个状态类，实现 `Enter()`、`OnUpdate(frame)`、`OnLeave()` 三个生命周期方法。

### 17.2 核心 MoveState 详解

#### IDLE（静止）

**源码**: `actor_move_state.cpp:139-147`

进入 IDLE 时自动将 `locomotion_state` 设为 0（仅 SERVER 控制的 actor）：
```cpp
bool MoveStateIdle::Enter()
{
    if (actor_.GetControlledBy() == ControlledBy::SERVER) {
        owner_.SetLocomotionState(0);
    }
    owner_.ClearStartStopSmooth();
    owner_.SetLastIdlePosition(actor_.GetPositionF());
    return true;
}
```

#### NAVI_TO_POINT（寻路到坐标点）

**源码**: `actor_move_state.cpp:238-276`

最常用的 NPC 移动状态。使用 Recast 导航网格寻路：

1. `Enter()` → 调用 `GetNaviPath(dest_pos)` 计算路径点列表
2. `OnUpdate(frame)` → 每帧沿路径点移动，到达当前路径点后前进到下一个
3. 支持到达范围（`arrive_range_`）和部分路径（`partial_result`）
4. 支持停止平滑减速（`stop_smooth_`）

```cpp
bool MoveStateNaviBase::GetNaviPath(const Position &dest_pos, bool partial_result)
{
    // 使用 Recast navmesh 寻路
    if (!space->FindPath(cur_pos, dest_pos, arrive_range_, &path_list_, &options) || path_list_.empty()) {
        return false;
    }
    return true;
}
```

#### NAVI_TO_ENTITY（寻路追踪实体）

类似 `NAVI_TO_POINT`，但目标是一个实体。每隔一定帧数重新计算路径以追踪移动目标（如追击玩家的怪物）。

#### STRAIGHT_MOVE（直线移动）

无视导航网格，沿直线移动。用于特殊场景如技能位移、弹道等。即使 `ControlledBy` 是 CLIENT，处于此状态时也会拒绝客户端移动包。

#### ROOT_MOTION 系列（动画驱动）

三种 Root Motion 状态：
- `ROOT_MOTION`: 有目标点，动画驱动从当前位置到目标
- `ROOT_MOTION_BY_CURVE`: 曲线插值驱动，支持复杂轨迹（`actor_move_state.cpp:687-756`）
- `ROOT_MOTION_NO_DEST`: 无目标点，纯动画驱动（如原地攻击时的微小位移）

#### PHYSIC_FALL（物理下落）

模拟重力下落。核心参数：
- `PHYSIC_GRAVITY = 3185` cm/s²
- `DEFAULT_GRAVITY_SCALE = 3.25`
- `JUMP_INIT_VELOCITY = 1170` cm/s

#### WAY_POINT_MOVE（路径点巡逻）

沿预设的路径点列表移动，支持循环巡逻和往返。通常用于 NPC 的固定巡逻路线。

#### FIXED_PATH_MOVE（固定路径移动）

沿固定路径移动，与 WAY_POINT 类似但更刚性——路径由配置定义，不可中途变更。

### 17.3 行为树移动系统（BehaviorMove）

**源码**: `behavior_move_state.hpp`, `BehaviorMoveComponent.lua`

在 13 种 MoveState 之上，还有一套 **并行的行为树移动系统**，由 `BehaviorMoveComponent` 管理。它封装了更高级的 AI 移动行为：

| BehaviorMoveState | 用途 | 典型场景 |
|-------------------|------|---------|
| `WANDER_MOVE` | 随机游荡 | 野怪闲逛、恐惧状态乱跑 |
| `NAVI_FORCIBLY` | 强制寻路 | 追击玩家（不可被打断） |
| `UNIFORM_ACCELERATE` | 匀加速运动 | 特殊冲刺/加速 |
| `FOLLOW_FORCIBLY` | 强制跟随 | 跟随主人/队长 |
| `ORBIT_MOVE` | 环绕移动 | 围绕目标转圈 |

`BehaviorMoveComponent` 提供的核心 API（共 100+ 方法）：

```lua
-- 追踪实体
BehaviorMoveComponent:reqFollowUpActor(TargetID, RangeRadius, SpreadRadius, Speed, ExtraParams)
BehaviorMoveComponent:reqFollowUpActorSimple(TargetID, AcceptanceRadius, Speed, MaxMoveTime, bKeepFollow)

-- 移动到位置
BehaviorMoveComponent:reqMoveToLocationV2(pos, rangeRadius, spreadRadius, Speed, ExtraParams)

-- 路径点巡逻
BehaviorMoveComponent:reqWayPathMove(ID, startIdx, endIdx, patrolType, speed)
BehaviorMoveComponent:reqWayPathCurveMove(ID, startIdx, endIdx, patrolType, speed)

-- 自动巡逻（随机范围）
BehaviorMoveComponent:reqAutoPatrol(spawnLocation, spawnRotator, scopeType, scopeParams, ...)

-- 包围/环绕
BehaviorMoveComponent:reqEncirclement(targetID, pos, nearDis, farDis, duration, ...)
BehaviorMoveComponent:reqOrbitMove(centerPos, radius, duration, speed, clockwise)

-- 逃跑
BehaviorMoveComponent:reqFlee(targetID, pos, minDist, maxDist, maxMoveTime, ...)

-- 恐惧乱跑
BehaviorMoveComponent:reqTerror(InstigatorId)
BehaviorMoveComponent:reqCharTerror(InstigatorId, attackBoxCenterX, attackBoxCenterY, attackBoxCenterZ)

-- 随机游荡
BehaviorMoveComponent:reqWanderMove(Target, Duration, WalkRightRatio, ...)

-- 相对跟随（保持相对位置）
BehaviorMoveComponent:reqRelativeFollow(TargetID, followRange, deltaYaw, ...)

-- 控制
BehaviorMoveComponent:ReqStartBehaviorMove(MoveActionType, InstigatorActorID, Callback, ...)
BehaviorMoveComponent:ReqStopBehaviorMove(reason, stopType, moveActionType)
BehaviorMoveComponent:ReqPauseBehaviorMove()
BehaviorMoveComponent:ReqResumeBehaviorMove()
```

### 17.4 底层 MoveComponent Lua API

**源码**: `MoveComponent.lua`

`MoveComponent` 是更底层的移动接口，直接操作 C++ Actor 的 MoveState：

```lua
-- 基础移动
MoveComponent:PositionMove(pos)             -- → NAVI_TO_POINT
MoveComponent:NaviToEntity(entityId)        -- → NAVI_TO_ENTITY
MoveComponent:StraightMove(dest, speed)     -- → STRAIGHT_MOVE
MoveComponent:CustomMove(direction, speed)  -- → CUSTOM_MOVE

-- 动画驱动
MoveComponent:ApplyRootMotion(data, dest, duration, stickToFloor)  -- → ROOT_MOTION
MoveComponent:ApplyRootMotionByCurve(data, dest, duration, ...)    -- → ROOT_MOTION_BY_CURVE

-- 物理
MoveComponent:ApplyPhysicFall(velocity)     -- → PHYSIC_FALL
MoveComponent:SetWeightlessness(bool)       -- 失重状态 + 服务端主控

-- 停止
MoveComponent:StopMove()                    -- → IDLE
MoveComponent:StopMoveAtPosition(pos)       -- → IDLE at specified pos
```

### 17.5 NPC 移动的服务端广播

NPC 移动通过 `BroadcastMoveFull` 广播给客户端（详见第九章），协议字节为 `ServerSyncMovement = 2`。

**与玩家移动的核心区别**：

| 对比项 | 玩家（CLIENT 主控） | NPC（SERVER 主控） |
|--------|-------------------|-------------------|
| 协议 | 零拷贝转发客户端原始包 | `PackServerMoveMsg` 服务端构造 |
| 速度来源 | 客户端上报 `msg.velocity` | 服务端计算 `real_velocity_ = Δpos/Δt` |
| move_time | 客户端硬编码 1500ms | `min(predict_move_time_, 1.0)` 秒 |
| 触发条件 | 收到客户端包时转发 | 每帧 `TryBroadcastMoveFull` 检测变化 |
| 频率 | ~12-14Hz（客户端上报频率） | 移动中每帧发送，静止时每10秒 |

---

## 十八、服务端主控广播的 flags 与 locomotion_state

### 18.1 TryBroadcastMoveFull 的 flags 构建

**源码**: `actor_move.cpp:1451-1489`

服务端主控 actor 的广播由 `TryBroadcastMoveFull` 驱动，flags 在其中自动计算：

```cpp
void ActorMove::TryBroadcastMoveFull(MoveState prev_state, RotateState prev_rotate_state)
{
    if (actor_.GetControlledBy() != ControlledBy::SERVER || !enable_sync_move_) {
        return;  // 仅 SERVER 控制的 actor 走此路径
    }

    uint16_t flags = 0;

    // FLAG_IS_LOCO_START: actor 处于移动状态
    if ((IsLocoStartState(state_) || IsLocoStartState(prev_state) || locomotion_state_ != 0)
        && cur_frame > disable_loco_before_frame_) {
        flags |= FLAG_IS_LOCO_START;
    }

    // FLAG_FLOATING: 不贴地
    if (IsFloating()) {
        flags |= FLAG_FLOATING;
    }

    // FLAG_3D_ROTATION: 3D旋转（如飞行单位）
    if (use_3d_rotation_) {
        flags |= FLAG_3D_ROTATION;
    }

    // FLAG_TARGET_DIRECTION: 有目标朝向
    if (enable_sync_target_direction_) {
        flags |= FLAG_TARGET_DIRECTION;
    }

    // FLAG_SERVER_LOCO_STATE: 服务端设置了非零 locomotion_state
    if (locomotion_state_ != 0) {
        flags |= FLAG_SERVER_LOCO_STATE;
    }
}
```

**关键区别——服务端 vs 客户端 flags**：

| Flag | 客户端会设置 | 服务端会设置 | 说明 |
|------|:----------:|:----------:|------|
| `FLAG_IS_LOCO_START` | ✓ | ✓ | 含义不同：客户端="有方向输入"；服务端="在移动状态" |
| `FLAG_FLOATING` | ✓ | ✓ | 不贴地 |
| `FLAG_JUMPING` | ✓ | ✗ | **纯客户端标记**，服务端从不设置 |
| `FLAG_RIDING` | ✓ | ✗ | **纯客户端标记**，服务端从不设置 |
| `FLAG_RELATIVE` | ✓ | ✗ | 移动平台相对坐标 |
| `FLAG_3D_ROTATION` | ✗ | ✓ | 3D旋转（飞行单位） |
| `FLAG_TARGET_DIRECTION` | ✗ | ✓ | 同步目标朝向 |
| `FLAG_SERVER_LOCO_STATE` | ✗ | ✓ | 标记服务端 loco state |

### 18.2 IsLocoStartState 判定

哪些 MoveState 被视为"移动中"：

```cpp
// 以下状态 NOT 视为 loco start:
// - IDLE
// - PHYSIC_FALL
// - ROOT_MOTION, ROOT_MOTION_BY_CURVE, ROOT_MOTION_NO_DEST
// 其余状态（NAVI_TO_POINT, NAVI_TO_ENTITY, CUSTOM_MOVE, STRAIGHT_MOVE, 
//           CLIENT_CONTROLLED_MOVE, CLIENT_PERFORM, WAY_POINT_MOVE, FIXED_PATH_MOVE）都是 loco start
```

### 18.3 locomotion_state 的管理

`locomotion_state` 是一个 uint8 值，低 7 位表示动画状态 ID，bit 7 为 inner index。

**掩码**: `LOCO_STATE_MASK = 0x7F`

**服务端主控 actor 的 locomotion_state 来源**：

1. **进入 IDLE 时自动清零**（`actor_move_state.cpp:142`）
2. **Lua 主动设置**：通过 `actor:set_locomotion_state(value)` 接口
3. **从客户端同步**：仅 `CLIENT_CONTROLLED_MOVE` 状态下从 `msg.locomotion_state` 读取

对于 NPC，通常只用到场景 1 和 2。行为树驱动移动时，Lua 层可以根据移动类型设置对应的动画状态：

```lua
-- 示例：设置 NPC 的 locomotion state
actor:set_locomotion_state(3)  -- 3 = Run 状态
```

### 18.4 广播变化检测

`TryBroadcastMoveFull` 每帧调用，但只有检测到变化时才真正发包：

```cpp
// actor_move.cpp:1482-1488
if (prev_state != state_                          // MoveState 变化
    || prev_rotate_state != rotate_state_          // RotateState 变化
    || rotation_changed                            // 朝向变化
    || !equalf(last_sync_velocity_, sync_velocity) // 速度变化
    || last_sync_flags_ != flags                   // flags 变化
    || last_sync_locomotion_state_ != locomotion_state_  // locomotion 变化
    || (sync_velocity.is_nearly_zero() && !equalf(last_sync_position_, actor_.GetPosition()))  // 静止位置变化
    || cur_frame >= need_sync_full_frame_) {       // 定时强制重发
    BroadcastMoveFull(sync_velocity, flags);
}
```

**定时重发周期**（`actor_move.cpp:1446-1448`）：
- 静止状态：每 10 秒
- 移动状态：`ceil(predict_move_time / frame_time)` 帧后（通常约等于1帧，即每帧发送）

### 18.5 速度计算

NPC 的广播速度不是来自客户端上报，而是服务端自己计算：

```cpp
real_velocity_ = (current_position - previous_position) / frame_time;
```

进入 IDLE 时速度归零：`sync_velocity = state_ == MoveState::IDLE ? FVector3::zero : real_velocity_`

### 18.6 服务端主控移动的完整数据流

```
                    服务端                                      客户端
┌─────────────────────────────────────────┐      ┌──────────────────────────┐
│ 行为树/AI系统                            │      │                          │
│   ↓                                     │      │                          │
│ BehaviorMoveComponent                    │      │                          │
│   ↓ reqFollowUpActor / reqFlee / ...    │      │                          │
│ MoveComponent                            │      │                          │
│   ↓ PositionMove / NaviToEntity / ...   │      │                          │
│ C++ ActorMove (状态机)                   │      │                          │
│   ↓ MoveState::OnUpdate(frame)          │      │                          │
│   ↓ 更新 position, real_velocity_       │      │                          │
│   ↓ TryBroadcastMoveFull()              │      │                          │
│   ↓ 检测变化 → BroadcastMoveFull()      │      │                          │
│   ↓ PackServerMoveMsg (proto=2)         │      │                          │
│   ↓ SendAoiMessage (PRIMARY/ALL)        │──────→│ 收到 ServerSyncMovement  │
│                                         │      │   ↓ 解析位置/速度/flags  │
│                                         │      │   ↓ MoveCorrector 平滑   │
│                                         │      │   ↓ 渲染                 │
└─────────────────────────────────────────┘      └──────────────────────────┘
```

---

*文档生成时间: 2026-04-02*
*基于源码版本: actor_move.cpp (2079行), actor_move_state.cpp (1488行), actor.cpp (1694行), protocol.cpp (215行), move_define.hpp (149行)*
*实战日志: debug_move.log (40行, 2026-04-02 16:02:43~16:02:50)*
*服务端主控分析: ActorBase.lua, MoveComponent.lua, BehaviorMoveComponent.lua, actor_move_state.hpp*
