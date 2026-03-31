# Scene 模块框架梳理（Skills 参考）

基于 `src/biz/scene` 当前代码实现，用于代码导航、问题定位与功能开发参考。

---

## 一、目录结构

```
src/biz/scene/
├── scene.hpp/cpp           # 全局单例入口，DLL 导出
├── space.hpp/cpp            # 空间容器（Space）
├── actor.hpp/cpp            # 实体聚合根（Actor）
├── comp_base.hpp            # 组件基类
├── engine_proxy.hpp/cpp     # 引擎 API 封装层
├── scene_define.hpp         # 类型别名、日志模块名、常量
├── actor_def.hpp            # Actor 枚举/常量定义
├── actor_relation.hpp/cpp   # 阵营关系判定
├── actor_aoi_level.hpp/cpp  # AOI 层级计算
├── actor_rpc.hpp            # 自动生成的客户端 RPC 包装
├── entity_query_utils.hpp   # 目标筛选工具
├── protocol.hpp/cpp         # 客户端二进制协议打包/解包
├── switch_options.hpp       # 运行时开关（性能采集等）
├── misc.hpp/cpp             # 杂项工具函数
├── lua_actor.hpp/cpp        # Actor 的 Lua 绑定
├── lua_space.hpp/cpp        # Space 的 Lua 绑定
│
├── bullet/                  # 子弹运动系统（运动策略）
│   ├── bullet_motion.hpp/cpp         # 四种运动：Linear/Curve/Parabolic/Surrounding
│   ├── bullet_motion_params.hpp      # 运动参数结构体
│   ├── bullet_motion_maker.hpp/cpp   # 运动对象工厂 + 对象池
│   └── bullet_body.hpp/cpp           # 旧版子弹体（已注释废弃）
│
├── combat/                  # 战斗子系统
│   ├── combat_comp.hpp/cpp           # 伤害结算、HP/Shield/Speed 管理
│   ├── combat_formula.hpp/cpp        # 伤害公式计算
│   ├── combat_context.hpp/cpp        # 战斗上下文（施法者/目标/来源等）
│   ├── combat_data_manager.hpp/cpp   # 战斗配置数据管理器
│   ├── combat_data_getter.hpp        # 数据获取辅助
│   ├── fight_attrib_comp.hpp/cpp     # 战斗属性组件
│   ├── break_defense_comp.hpp/cpp    # 破防组件
│   ├── combat_fmt.hpp                # fmt 格式化辅助
│   │
│   ├── aggro/                        # 仇恨系统
│   │   ├── combat_aggro_comp.hpp/cpp
│   │   └── aggro_info.hpp/cpp
│   │
│   ├── buff/                         # Buff 系统
│   │   ├── buff.hpp/cpp
│   │   ├── buff_comp.hpp/cpp
│   │   ├── buff_define.hpp
│   │   └── buff_fmt.hpp
│   │
│   ├── client_attack/                # 客户端攻击校验
│   │   └── client_attack_comp.hpp/cpp
│   │
│   ├── damage/                       # 伤害计算相关
│   │   ├── damage_context.hpp
│   │   ├── damage_formula_define.hpp/cpp
│   │   ├── damage_formula_utils.hpp
│   │   └── damage_fmt.hpp
│   │
│   ├── effect/                       # 效果系统（核心）
│   │   ├── combat_effect_comp.hpp/cpp       # 效果组件（EffectRecord 管理、事件触发）
│   │   ├── combat_effect_manager.hpp/cpp    # 注册中心（Action/Condition/Event 映射）
│   │   ├── combat_effect_utils.hpp/cpp      # 效果工具函数
│   │   ├── combat_effect_consts.hpp         # 效果常量
│   │   ├── effect_record.hpp/cpp            # EffectRecord / EffectRecordNode
│   │   ├── scaffold.hpp/cpp                 # Effect/Event/Condition/Action 基类与代理
│   │   ├── tick_action.hpp/cpp              # TickAction 定义
│   │   ├── tick_action_comp.hpp/cpp         # TickAction 组件
│   │   ├── tick_action_const.hpp            # TickAction 常量
│   │   │
│   │   ├── condition/                       # 条件实现
│   │   │   └── condition_impl.hpp/cpp
│   │   ├── event/                           # 事件实现
│   │   │   └── event_impl.hpp/cpp
│   │   └── task/                            # Action 实现（frame 瞬发 / span 持续）
│   │       ├── task_utils.hpp/cpp
│   │       ├── frame/                       # 瞬发类 Action
│   │       │   ├── actor_frame_task.*
│   │       │   ├── battle_frame_task.*
│   │       │   ├── buff_frame_task.*
│   │       │   ├── skill_frame_task.*
│   │       │   ├── movement_frame_task.*
│   │       │   ├── system_frame_task.*
│   │       │   ├── attribute_frame_task.*
│   │       │   └── settlement_frame_task.*
│   │       └── span/                        # 持续类 Action
│   │           ├── actor_span_task.*
│   │           ├── battle_span_task.*
│   │           ├── buff_span_task.*
│   │           ├── skill_span_task.*
│   │           ├── movement_span_task.*
│   │           ├── system_span_task.*
│   │           ├── attribute_span_task.*
│   │           ├── model_span_task.*
│   │           └── wooden_man_task.*
│   │
│   ├── hitfeed/                      # 受击反馈系统
│   │   ├── hit_feed_comp.hpp/cpp
│   │   └── hit_feed_state.hpp/cpp
│   │
│   ├── profession/                   # 职业系统
│   │   ├── profession.hpp/cpp
│   │   ├── profession_comp.hpp/cpp
│   │   └── profession_factory.hpp
│   │
│   ├── selector/                     # 目标选择器
│   │   ├── target_selector.hpp/cpp
│   │   └── selector_utils.hpp/cpp
│   │
│   ├── skill/                        # 技能系统
│   │   ├── skill.hpp/cpp                    # 技能实例
│   │   ├── skill_comp.hpp/cpp               # 技能组件（施放/CD/充能/连招/禁用）
│   │   ├── skill_state.hpp/cpp              # 技能状态机
│   │   ├── skill_list_comp.hpp/cpp          # 技能列表管理
│   │   ├── passive_skill_comp.hpp/cpp       # 被动技能组件
│   │   ├── skill_combo_comp.hpp/cpp         # 连招组件
│   │   └── skill_define.hpp                 # 技能枚举/结构体
│   │
│   ├── unit/                         # 战斗单位系统
│   │   ├── unit_base.hpp/cpp                # Unit 基类（生命周期/定时器/位置）
│   │   ├── unit.hpp/cpp                     # Unit 中间类（阶段/Trap/Attach）
│   │   ├── unit_comp.hpp/cpp                # Actor 上的 Unit 管理组件
│   │   ├── unit_manager.hpp/cpp             # Space 级 Unit 管理器（延迟删除）
│   │   ├── unit_factory.hpp/cpp             # Unit 创建工厂
│   │   ├── unit_const.hpp                   # 枚举（LogicUnitType/DestroyReason 等）
│   │   ├── aura.hpp/cpp                     # 光环
│   │   ├── trap.hpp/cpp                     # 陷阱
│   │   ├── spell_field.hpp/cpp              # 法术场
│   │   ├── spell_agent.hpp/cpp              # 施法代理
│   │   ├── velocity.hpp/cpp                 # 引力场（VelocityField，继承 Aura）
│   │   ├── lbullet_base.hpp/cpp             # Sweep 子弹基类
│   │   ├── lbullet_sweep.hpp/cpp            # Sweep 子弹实现
│   │   ├── lbullet_must_hit.hpp/cpp         # 必中子弹
│   │   └── interactor.hpp                   # 交互物代理
│   │
│   └── data/                         # 战斗数据定义目录（空）
│
├── move/                    # 移动子系统
│   ├── actor_move.hpp/cpp            # 底层移动组件（状态机 + 旋转 + 同步校验）
│   ├── actor_move_state.hpp/cpp      # 移动状态实现（13 种状态）
│   ├── actor_rotate_state.hpp/cpp    # 旋转状态
│   ├── actor_collision.hpp/cpp       # 碰撞检测
│   ├── move_define.hpp               # 移动常量定义
│   ├── move_data_manager.hpp/cpp     # 移动配置数据管理
│   ├── move_state_base.hpp           # 状态基类模板
│   ├── gravitational_field.hpp/cpp   # 引力场移动效果
│   ├── spline_curve.hpp/cpp          # 样条曲线插值
│   ├── logic_move_calculator.hpp     # 移动计算辅助
│   └── behavior/                     # 行为层移动
│       ├── behavior_move.hpp/cpp            # 行为移动组件
│       ├── behavior_move_state.hpp          # 行为状态枚举
│       ├── wander_move.hpp/cpp              # 游荡
│       ├── navi_forcibly.hpp/cpp             # 强制导航
│       ├── follow_forcibly.hpp/cpp           # 强制跟随
│       └── uniform_accelerate.hpp/cpp       # 匀加速
│
├── trap/                    # Trap 信息管理
│   ├── actor_trap.hpp/cpp           # Actor 级 Trap
│   ├── space_trap.hpp/cpp           # Space 级 Trap
│   └── trap_info_define.hpp/cpp     # Trap 通用定义
│
├── debug/                   # 调试组件
│   └── debug_comp.hpp/cpp
│
├── internal/                # 内部实现
│   ├── rpc_define.hpp                # RPC 方法声明（被 Actor 头文件 include）
│   ├── rpc_handler_register.cpp      # C++ RPC 注册
│   └── rpc_call_impl.cpp            # RPC 调用实现
│
└── property/                # 属性目录（当前为空）
```

---

## 二、核心对象模型

### Scene（全局单例）

- **文件**: `scene.hpp/cpp`
- **职责**: DLL 导出入口，对接引擎 `SceneLogicManager` 回调
- **核心数据**:
  - `IndexIteratePool<Space> spaces_` — 空间池（支持遍历）
  - `IndexPool<Actor> actors_` — Actor 池
  - `eiid_to_aid_map_` — entity_iid → actor_id 映射
  - `detroying_actors_` — 延迟销毁队列
  - `main_thread_callback_queue_` / `sub_thread_callback_queue_` — 双线程回调队列
- **tick 主流程**:
  1. 回收 `detroying_actors_`（上帧标记的延迟销毁 Actor）
  2. 遍历所有 Space 调用 `Space::Tick`
  3. 执行主线程回调队列
- **Actor 销毁**: `destroy_actor` → `Fini()` + `MarkDestroy()` + 入延迟队列 → 下帧回收
- **坐标转换**: 引擎回调中 Y/Z 互换（`actor_before_enter_space` 传入 `(x, z, y)`)

### Space（场景容器）

- **文件**: `space.hpp/cpp`
- **职责**: 管理空间内 Actor 集合与空间级服务
- **核心数据**:
  - `actors_` / `actors_by_eiid_` — Actor 容器（按 ID / 按 entity_iid）
  - `pending_actor_reqs_` — Tick 期间缓存的 Actor 进出请求，避免遍历时容器修改
  - `navmesh_` / `voxel_` — 导航网格和体素（支持异步加载到子线程）
  - `m_unit_manager` — 空间级 Unit 管理器
  - `gravi_field_mgr_` — 引力场管理器
  - `shared_aggro_map_` — 共享仇恨表
- **Tick 流程**:
  1. 遍历 Actor 调用 `Actor::Tick`
  2. Tick 引力场
  3. 处理 `pending_actor_reqs_`
  4. `UnitManager::DoUnitDelete()` 延迟删除已销毁 Unit
- **空间查询**: 支持圆形/环形/矩形/扇形范围查询（转发到引擎 AOI）
- **Trap**: Actor 级 Trap + Space 级 Trap，C++ 回调 + Lua 脚本回调两条路径

### Actor（实体聚合根）

- **文件**: `actor.hpp/cpp`
- **职责**: 组合所有业务组件，统一承接帧更新、生命周期、协议处理、脚本调用
- **组件列表**（在 Actor 中以成员变量直接持有）:
  - `BehaviorMove` — 行为层移动
  - `ActorMove` — 底层移动
  - `CombatAggroComp` — 仇恨
  - `SkillComp` — 技能
  - `SkillComboComp` — 连招
  - `FightAttribComp` — 战斗属性
  - `BuffComp` — Buff
  - `CombatEffectComp` — 效果系统
  - `ProfessionComp` — 职业
  - `CombatComp` — 伤害结算/HP/速度
  - `UnitComp` — Unit 管理
  - `HitFeedComp` — 受击反馈
  - `TickActionComp` — TickAction
  - `BreakDefenseComp` — 破防
  - `ClientAttackComp` — 客户端攻击校验
  - `DebugComp` — 调试
- **Tick 顺序**（每步都检查 `!IsDestroying()`）:
  1. `BehaviorMove` → `ActorMove`
  2. `CombatAggroComp`
  3. `SkillComp` → `SkillComboComp`
  4. `FightAttribComp` → `BuffComp` → `CombatEffectComp`
  5. `ProfessionComp`（仅玩家）
  6. `CombatComp`
  7. `UnitComp` → `HitFeedComp` → `TickActionComp`
- **生命周期**:
  - `OnBeforeEnterSpace`: 绑定 `space_` + 加入空间容器 + `ResetVolatile`
  - `OnAfterEnterSpace`: move/buff/passive 初始化
  - `OnBeforeLeaveSpace`: 清 Trap 关系/阵营/组件 Leave → 出空间容器
  - `OnAfterLeaveSpace`: 解绑 `space_ = nullptr`
- **客户端协议处理** (`OnRecvClientMsg`):
  - `ClientSyncMovement` → `ActorMove::HandleSyncMove`
  - `TeleportAck` → `ActorMove::HandleTeleportAck`
  - `RotateInstantly` → `ActorMove::HandleRotateInstantly`
  - `Handshake` → `ActorMove::HandleHandshake`
  - `Heartbeat` → 回复服务器时间戳
- **客户端 RPC**: `CallOwnClient` / `CallAllClients` / `CallOtherClients` / `CallSpecificClient` 等模板方法

### CompBase（组件基类）

- **文件**: `comp_base.hpp`
- **职责**: 持有 `Actor&` 引用，提供 `EnableTick` / `ShouldTick` 控制帧更新开关
- 所有战斗/移动组件继承 `CompBase`

---

## 三、战斗子系统

### 效果系统（CombatEffectComp + CombatEffectManager）

**核心架构**: 数据驱动的效果执行框架

- `CombatEffectManager`（全局单例）: 注册中心
  - `RegisterActions()`: 注册所有 Action 类型到 `actions_[]`
  - `RegisterConditions()`: 注册所有 Condition 类型到 `conditions_[]`
  - `RegisterEvents()`: 注册所有 Event 类型到 `events_[]`
  - 形成 **配置枚举 → C++ 函数** 的映射表
- `CombatEffectComp`（Actor 组件）: 运行时执行
  - 维护 `effect_records_`（按 `gid_count_t execute_id` 索引）
  - 三种触发模型:
    - `TRIGGER_KEEP`: 添加时立即执行，移除时 End
    - `TRIGGER_REPEAT`: Tick 驱动的周期执行
    - `TRIGGER_BY_EVENT`: 事件监听触发
  - 支持条件组判定（AND/OR/NOT）
  - Action 分两类:
    - **Frame Task**（瞬发）: 执行后立即完成
    - **Span Task**（持续）: 有 Execute / End 成对调用
  - 执行路径: `ActionExecute` → 查 `CombatEffectManager.GetAction(type)` → 调用注册的执行函数
- `scaffold.hpp`: 定义 `Effect`/`Event`/`Condition`/`ActionProxy` 基类

**Action 分类** (`effect/task/`):

| 类别 | Frame（瞬发） | Span（持续） |
|------|------|------|
| Actor | actor_frame_task | actor_span_task |
| Battle | battle_frame_task | battle_span_task |
| Buff | buff_frame_task | buff_span_task |
| Skill | skill_frame_task | skill_span_task |
| Movement | movement_frame_task | movement_span_task |
| Attribute | attribute_frame_task | attribute_span_task |
| System | system_frame_task | system_span_task |
| Settlement | settlement_frame_task | — |
| Model | — | model_span_task |

### 技能系统（SkillComp）

- **入口**: `Handle_ReqCastSkillNew` / `Handle_ReqCastSkillBenchmarkC` → `SkillComp::PlayerCastSkill`
- **施放流程**:
  1. 校验: 死亡/CD/充能/目标/距离/禁用/连招窗口
  2. 打断非并行技能 `BreakNoParallelSkills`
  3. 消耗资源与 CD/GCD/TeamGCD
  4. 创建 Skill 实例并 `Start` → 进入状态机
  5. 触发 `OnSkillCastEvent`
  6. 通过 `SCCastSkill` 同步施法结果到客户端
- **技能类型**:
  - `PlayerCastSkill`: 完整校验（玩家/AI 机器人）
  - `SimpleCastSkill`: 简单校验（怪物）
  - `ActionSimpleCastSkill`: 不走校验（Action 内部调用）
  - `CastControlledActorSkill`: 控制单位施法
- **技能状态**: `SkillState`（skill_state.hpp）驱动技能阶段流转
- **CD 体系**: 技能 CD + GCD（组 CD）+ TeamGCD + 充能系统

### 伤害结算（CombatComp）

- **主入口**: `CombatComp::TakeDamage`
- **流程**:
  1. 构造 `DamageContext`
  2. 免疫判定（`HasImmuneDamage`）
  3. 格挡判定（`CalcAttackBlock`）
  4. 暴击判定（`CalcAttackCrit`）
  5. 公式计算（`CombatFormula`）→ `DamageResult`
  6. Buff 伤害加成 / 额外加成 / 伤害修正
  7. HP/Shield/锁血更新
  8. 战斗统计记录
  9. 触发战斗事件（受伤/暴击/死亡）
  10. 同步跳字 + 受击消息到客户端
- **速度管理**: `base_speed_` + `fix_speed_`（固定）+ `max_speed_`（上限）+ 属性加成 → `GetFinalSpeed`

### Buff 系统（BuffComp）

- 管理 Buff 实例的添加/移除/叠层/免疫
- 支持 Buff 屏蔽规则（`EffectBlockRules`）
- 入战/出战/死亡/离开场景时的 Buff 清理

### 仇恨系统（CombatAggroComp）

- 管理 NPC 仇恨列表，支持共享仇恨
- 提供仇恨排序、激活/休眠

---

## 四、Unit 子系统

### 类型体系

```
UnitBase (unit_base.hpp)
├── Unit (unit.hpp)               — 中间类，管理阶段/Trap/Attach
│   ├── Aura (aura.hpp)           — 光环（Trap + 条件筛选 + 效果生效/移除）
│   │   └── VelocityField         — 引力场（继承 Aura，与 GravitationalField 联动）
│   ├── Trap (trap.hpp)           — 陷阱（触发/充能/阶段状态机）
│   ├── SpellField                — 法术场（周期 Tick + 范围生效）
│   ├── SpellAgent                — 施法代理（自主移动/旋转/释放技能）
│   └── Interactor                — 交互物代理
│
├── LBulletBase (lbullet_base.hpp) — 子弹基类
│   ├── LBulletSweep              — Sweep 子弹（运动 + 碰撞检测）
│   └── LBulletMustHit            — 必中子弹
```

### 生命周期管理

- **创建**: `UnitFactory::CreateBullet` / `CreateUnitAtPositionByType` / `CreateUnitAtSpaceByType`
- **注册**: 创建后调用 `UnitComp::OnUnitAdd` 注册到 instigator 的 UnitComp
- **空间注册**: `UnitManager::EmplaceUnit` 注册到 Space 的 UnitManager
- **Tick**: 需要 Tick 的 Unit 调用 `EnableTick()` 注册到 `UnitComp.m_tick_unit_set_`，由 `UnitComp::Tick` 驱动
- **销毁**: `StopPerform` / `Destroy` → `OnFini` → 从 UnitComp/UnitManager 移除 → 延迟删除
- **延迟删除**: `UnitManager::DoUnitDelete` 在 `Space::Tick` 末尾执行

### 子弹系统

- **运动策略**（`bullet/bullet_motion.hpp`）:
  - `BulletLinearMotion`: 直线运动（支持加速 + 追踪转向）
  - `BulletCurveMotion`: 曲线运动（预留，当前未实现）
  - `BulletParabolicMotion`: 抛物线运动（重力 + 追踪目标点）
  - `BulletSurroundingMotion`: 环绕运动（绕目标点旋转）
- **运动对象工厂**: `BulletMotionMaker`（含对象池）
- **碰撞检测**: `LBulletSweep::DoSweep` — 线段-点距离检测 + Trap 区域碰撞
- **Tick 流程** (`LBulletSweep::DoTick`):
  1. 检查 `IsbulletAlive()`
  2. `m_use_motion_->Tick(delta_time)` — 运动更新 + sweep 碰撞
  3. 检查飞行时间是否到期
- **注意**: Motion 的 `Tick` 内部可能触发 `OnReachTargetPos` → 同步销毁链释放 Motion 对象本身，需要防止 use-after-free

### Aura（光环）

- 基于 Trap 检测进出
- 条件筛选：满足 Condition 的 Actor 才生效
- 最大生效数限制，超限时按规则淘汰
- 同模板 Aura 进入时，`UnitComp::ChooseAuraTakeEffect` 选择最优生效（等级/层数比较）

---

## 五、移动子系统

### 两层移动体系

- **ActorMove**（底层）: 状态机驱动实际位移
- **BehaviorMove**（行为层）: AI 行为驱动，内部调用 ActorMove

### ActorMove 状态机

13 种移动状态 (`MoveState` 枚举):

| 状态 | 说明 |
|------|------|
| IDLE | 静止 |
| NAVI_TO_POINT | 导航到目标点 |
| NAVI_TO_ENTITY | 导航追踪实体 |
| CUSTOM_MOVE | 自定义移动（ICustomMove 接口） |
| CLIENT_CONTROLLED_MOVE | 客户端控制移动（服务端校验） |
| STRAIGHT_MOVE | 直线移动（支持跳跃抛物线） |
| ROOT_MOTION | RootMotion（到目标点） |
| ROOT_MOTION_BY_CURVE | RootMotion（曲线） |
| ROOT_MOTION_NO_DEST | RootMotion（无目标点） |
| PHYSIC_FALL | 物理坠落 |
| CLIENT_PERFORM | 客户端表演 |
| WAY_POINT_MOVE | 路点移动（循环/往返/单程） |
| FIXED_PATH_MOVE | 固定路径移动（样条曲线） |

### 客户端同步校验

- `VerifyInfo`: 速度/位置/时间差校验
- 超限时执行服务端纠偏（强制传送）
- 移动广播分级: Full / Brief / FixedPath 专用

### BehaviorMove 行为状态

| 状态 | 说明 |
|------|------|
| NONE | 无行为 |
| WANDER | 游荡（随机巡逻） |
| NAVI_FORCIBLY | 强制导航到目标点 |
| UNIFORM_ACCELERATE | 匀加速移动 |
| FOLLOW_FORCIBLY | 强制跟随目标 |

### 空间导航能力

- `Space::MoveTo` / `MoveToNearby` — 体素移动
- `Space::FindPath` — 导航网格寻路
- `Space::GetFloorUnsafe` / `GetNearestFloor` — 地面检测
- `Space::IsBlock` — 阻挡判定
- 支持动态阻挡物: `AddDynamicCube` / `AddDynamicCylinder` 等

---

## 六、引擎桥接层（EngineProxy）

- **文件**: `engine_proxy.hpp/cpp`
- **职责**: 封装引擎 API，统一处理坐标系转换
- **坐标转换**:
  - Yaw: `ToEngineYaw(degree) = DegreeToRadian(90 - degree)` / `FromEngineYaw` 反向
  - Pitch/Roll: 当前不做转换，直接透传
- **核心封装**:
  - 时间: `NowMilliseconds()` / `NowSeconds()`
  - 位置同步: `UpdatePosition` / `UpdateDirection` / `UpdateTransform`
  - 消息发送: `SendOwnMsg` / `SendAoiMsg` / `CallOwnClient` / `CallAllClients`
  - AOI/Trap: `EntityAddTrap` / `EntityRemoveTrap` / `EntityEntitiesInRange*`
  - 定时器: `EntityAddTimer` / `EntityDelTimer`
  - Lua 调用: `CallLuaEntity` / `CallLuaSpace` / `CallScript`

---

## 七、协议与 RPC

### 客户端二进制协议（`protocol.hpp/cpp`）

| 协议 | 说明 |
|------|------|
| `ClientSyncMovement` | 客户端上报移动同步 |
| `Handshake` | 握手（请求/响应） |
| `TeleportAck` | 传送确认 |
| `RotateInstantly` | 即时转向 |
| `Heartbeat` | 心跳 |

### C++ RPC（`internal/`）

- **注册**: `rpc_handler_register.cpp` → `ActorCppRpcHandler`
- **分发**: `Scene::on_recv_client_cpp_msg` → `ActorCppRpcHandler::Dispatch`
- **Handler 声明**: `rpc_define.hpp`（被 `actor.hpp` include）
- **典型 Handler**:
  - `Handle_ReqCastSkillNew` / `Handle_ReqCastSkillBenchmarkC` — 施法
  - `Handle_ReqBreakSkill` — 断招
  - `Handle_ReqReportHitTarget` — 客户端攻击上报
  - `Handle_ReqReportPerfectDodge` — 完美闪避上报
  - `Handle_ReqQTEEventNew` — QTE 事件
  - `Handle_ReqTriggerSkillPressEvent` — 技能按键事件

### 客户端调用封装（`actor_rpc.hpp`）

- 自动生成 `CallOwnClient_*` / `CallAllClients_*` 等包装函数
- 业务组件通过 Actor 上的这些函数进行网络同步

---

## 八、时序速览

### 每帧逻辑

```
Scene::tick
  ├── 回收延迟销毁的 Actor
  ├── for each Space:
  │     Space::Tick
  │       ├── for each Actor:
  │       │     Actor::Tick
  │       │       ├── BehaviorMove.Tick
  │       │       ├── ActorMove.Tick
  │       │       ├── CombatAggroComp.Tick
  │       │       ├── SkillComp.Tick
  │       │       ├── SkillComboComp.Tick
  │       │       ├── FightAttribComp.Tick
  │       │       ├── BuffComp.Tick
  │       │       ├── CombatEffectComp.Tick
  │       │       ├── ProfessionComp.Tick (玩家)
  │       │       ├── CombatComp.Tick
  │       │       ├── UnitComp.Tick
  │       │       │     └── for each TickUnit: UnitBase::Tick → DoTick
  │       │       ├── HitFeedComp.Tick
  │       │       └── TickActionComp.Tick
  │       ├── Tick 引力场
  │       ├── 处理 pending_actor_reqs_
  │       └── UnitManager::DoUnitDelete
  └── 处理主线程回调队列
```

### 进出空间

```
Enter:
  Scene 回调 → actor_before_enter_space → OnBeforeEnterSpace(绑定 space, 入容器)
            → actor_after_enter_space  → OnAfterEnterSpace(move/buff/passive 初始化)

Leave:
  Scene 回调 → actor_before_leave_space → OnBeforeLeaveSpace(清 trap/组件/出容器)
            → actor_after_leave_space  → OnAfterLeaveSpace(解绑 space)
```

### 技能到伤害

```
客户端 RPC 请求
  → SkillComp::PlayerCastSkill (校验 + 创建 Skill)
    → Skill 状态机执行
      → CombatEffectComp::CastAttack / SkillAttack
        → ActionExecute (查 CombatEffectManager 映射)
          → battle_frame_task::DoFightAction
            → CombatComp::TakeDamage (公式/结算/事件)
              → 客户端同步 (跳字/受击/死亡)
```

### 子弹生命周期

```
UnitFactory::CreateBullet
  → LBulletSweep::Init (初始化参数/运动策略)
    → BulletMotionMaker 创建 Motion
    → EnableTick 注册到 UnitComp
  → DoTick (每帧)
    → Motion::Tick
      → SimulateMove (更新速度/位置)
      → DoSweep (碰撞检测)
        → OnHitTarget / OnReachTargetPos
          → CheckDelayStopPerform
            → StopPerform → Destroy → OnFini
              → BulletMotionMaker::ReleaseBulletMotion (回池)
```

---

## 九、扩展入口

### 新增 Action

1. 在 `combat/effect/task/frame/` 或 `span/` 下实现 Action 类，继承 `Effect`
2. 在 `CombatEffectManager::RegisterActions()` 中 `RegisterAction<AT, DT>()`
3. 确保对应数据结构已在配置数据中定义

### 新增 Condition

1. 在 `combat/effect/condition/condition_impl.*` 中实现
2. 在 `CombatEffectManager::RegisterConditions()` 中 `RegisterCondition<CT, DT>()`

### 新增 Event

1. 在 `combat/effect/event/event_impl.*` 中实现
2. 在 `CombatEffectManager::RegisterEvents()` 中 `RegisterEvent<ET, DT>()`

### 新增移动行为

1. 在 `move/behavior/` 下实现状态类，继承 `BehaviorMoveStateBase`
2. 在 `BehaviorMove` 中添加到 `states_[]` 数组

### 新增移动状态

1. 在 `MoveState` 枚举中添加新状态
2. 在 `actor_move_state.*` 中实现对应状态类
3. 在 `ActorMove` 中添加实例并注册

### 新增 Unit 类型

1. 在 `LogicUnitType` 枚举中添加
2. 实现 Unit 子类（可继承 `Unit` 或 `UnitBase`）
3. 在 `UnitFactory` 中添加创建逻辑
4. 在 `UnitComp` 中添加同步逻辑

### 新增子弹运动类型

1. 在 `bullet_motion.hpp/cpp` 中继承 `BulletBaseMotion` 实现新运动
2. 在 `BulletMotionMaker` 中添加创建/回收逻辑
3. 添加运动类型枚举

---

## 十、实现特征与注意事项

### 生命周期安全

> 详细内容已移至 `cpp-code-review-checklist.md` → "Object Lifecycle & Deferred Destruction (C4/C8/M4 Context)" 章节，与 Review 检查项统一维护。

### 坐标系

- 引擎使用 UE 坐标系（Y/Z 互换、Yaw 弧度制偏移 90°）
- `EngineProxy` 统一做转换，业务层使用度数制 Yaw

### 脚本交互

- C++ 保持**框架 + 性能敏感逻辑**，业务规则下沉 Lua
- `CallEntityScriptFunc` / `CallSpaceEntityScriptFunc` 为主要脚本调用入口
- 使用 `LuaNameWithRefAndCounter` 缓存 Lua 函数引用避免重复查找

### 组件间耦合

- 组件通过 `Actor` 聚合访问（`actor_.GetXxxComp()`），避免组件间直接持有
- `CombatContext` 在战斗调用链中传递上下文（施法者/目标/来源技能等）
- `DynamicBlackboard` 在效果执行链中传递临时数据

### 性能相关

- 使用 `ankerl::unordered_dense` 替代 `std::unordered_map` 提升查找性能
- Actor 维护静态 `send_buffer_` 复用网络发送缓冲区
- Unit/Bullet Motion 使用对象池（`Pool<T>`）减少分配
- 组件通过 `ShouldTick()` 按需参与帧更新

---

## 十一、文件索引（按优先阅读排序）

| 模块 | 关键文件 |
|------|---------|
| 入口与生命周期 | `scene.hpp/cpp` |
| 空间管理 | `space.hpp/cpp` |
| 实体聚合 | `actor.hpp/cpp` |
| 组件基类 | `comp_base.hpp` |
| 引擎桥接 | `engine_proxy.hpp/cpp` |
| 效果系统 | `combat/effect/combat_effect_comp.*`, `combat_effect_manager.*`, `scaffold.*` |
| 技能系统 | `combat/skill/skill_comp.*`, `skill.*`, `skill_state.*` |
| 伤害结算 | `combat/combat_comp.*`, `combat_formula.*` |
| Buff 系统 | `combat/buff/buff_comp.*`, `buff.*` |
| 移动系统 | `move/actor_move.*`, `actor_move_state.*` |
| 行为移动 | `move/behavior/behavior_move.*` |
| Unit 管理 | `combat/unit/unit_comp.*`, `unit_manager.*`, `unit_factory.*` |
| Unit 类型 | `combat/unit/unit.hpp`, `aura.*`, `trap.*`, `spell_field.*`, `spell_agent.*` |
| 子弹系统 | `combat/unit/lbullet_sweep.*`, `bullet/bullet_motion.*` |
| 目标选择 | `combat/selector/target_selector.*` |
| 仇恨系统 | `combat/aggro/combat_aggro_comp.*` |
| RPC | `internal/rpc_handler_register.cpp`, `rpc_define.hpp` |
| 协议 | `protocol.hpp/cpp` |
