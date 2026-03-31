# C++ Code Review Checklist

> 本文件是所有 C++ Code Review skill 的统一引用来源。
> Review checklist、报告模板和注意事项均维护在此处。

---

## Review Checklist

### 1. Crash Risks (崩溃风险) — Severity: HIGH

| ID | Category | What to Check |
|----|----------|---------------|
| C1 | **Null pointer dereference** | Every raw pointer dereference (`->`, `*p`) must have a prior null check, or the parameter should be a reference instead of a pointer. Pay special attention to: `GetSkillData()`, `GetSpace()`, `GetOwner()`, `GetController()` etc. that return nullable pointers. |
| C2 | **Division by zero** | All `/` and `%` operations — verify the divisor cannot be zero. High-risk variables: `speed`, `scale`, `delta_time`, `count`, `max_hp`, `frame_time`, `charge_time`. |
| C3 | **Array out of bounds** | Array/vector index access without bounds check; enum-to-int used as index without range validation. Enums from external data/network may contain undefined values. |
| C4 | **Use-after-free / dangling pointer** | Accessing an object after it may have been destroyed by a callback, event, or deferred-delete. Check that `this` is still valid after calling external callbacks. Cache pointers to local variables and add alive-checks before continuing. |
| C5 | **Uninitialized variables** | Variables (especially POD types and structs) used before initialization on any code path. Struct members without in-class initializers. Plain `SomeStruct s;` leaves POD fields indeterminate. |
| C6 | **Iterator invalidation** | Modifying a container (insert/erase) while iterating over it. External calls during iteration that may indirectly modify the container. Must copy before iterating or use safe erase patterns. |
| C7 | **Stack overflow** | Lambda captures that are too large; deep recursion; large stack-allocated arrays. |
| C8 | **Pointer/reference/iterator invalidation across external calls** | Holding a pointer, reference, or iterator to a container element, then calling an external system API that may trigger side-effects invalidating it. **This is the #1 crash pattern in this codebase.** See the "Dangerous APIs" section below. |
| C9 | **Timer ID reuse / stale timer** | Storing a `timer_t` but not resetting it after the timer fires. A subsequent `DelTimer()` on the stale ID may cancel an unrelated timer if the ID has been recycled. Always reset timer IDs in the callback or after cancellation. |
| C10 | **`unordered_dense` value reference invalidation** | `ankerl::unordered_dense::map` 内部使用连续内存（`std::vector`）存储所有元素，任何 insert/erase 都可能触发 rehash，导致所有 value 的引用、指针和迭代器失效。**禁止持有 value 的引用后调用任何可能修改该容器的外部逻辑。** 应在外部调用后重新通过 `find()` 获取。如果 value 是复杂类型（struct、class），引用失效后写入会写坏内存；即使是简单类型，引用也同样会失效。对于需要长期持有引用或在外部调用间保持引用有效的场景，应改用 `std::unordered_map`。 |

#### Dangerous APIs — External Calls That May Invalidate State (C8 Detail)

The following APIs can trigger cascading side-effects (buff removal, skill interruption, actor destruction, container modification). **Any pointer, reference, or iterator cached before these calls may be invalid afterward:**

| API | Why It's Dangerous |
|-----|--------------------|
| `CombatEffectComp::TriggerCombatEvent()` | Triggers all registered combat effects; may add/remove buffs, cast skills, destroy units, kill actors. |
| `CombatEffectComp::CAGroupExecute()` and variants | Executes Condition-Action groups; can trigger arbitrary game logic chains. |
| `CombatEffectComp::ActionExecute()` and variants | Executes combat actions; may call back into the caller's own component. |
| `BuffComp::AddBuff()` / `RemoveBuff()` | May trigger buff events that cascade into skill/effect/actor changes. |
| `SkillComp::StopSkill()` / `BreakAllSkills()` | Skill stop callbacks may destroy units, remove buffs, trigger events. |
| `Actor::Die()` / `DieNextFrame()` | Actor death triggers a chain of cleanup: buff removal, unit destruction, event broadcasting. |
| `UnitComp` unit lifecycle methods | Unit creation/destruction may modify the actor's unit map while iterating. |
| Lua script callbacks (`CallEntityScriptFunc`, `CallScript`) | Lua code can do anything — modify containers, destroy actors, cast skills. |

**Safe pattern:** After calling any dangerous API, do NOT use previously cached pointers/references/iterators. Re-fetch from the container or use ID-based lookups.

**Example (BAD):**
```cpp
for (auto &[unit_id, unit_ptr] : unit_map_) {
    unit_ptr->GetBuffComp().RemoveBuff(buff_id); // may trigger events that destroy/create units, invalidating iterators
    unit_ptr->DoSomething(); // CRASH: iterator invalidated
}
```

**Example (GOOD):**
```cpp
std::vector<uint64_t> unit_ids;
unit_ids.reserve(unit_map_.size());
for (auto &[unit_id, unit_ptr] : unit_map_) {
    unit_ids.push_back(unit_id);
}
for (auto uid : unit_ids) {
    auto it = unit_map_.find(uid); // re-fetch after each external call
    if (it != unit_map_.end()) {
        it->second->GetBuffComp().RemoveBuff(buff_id);
    }
}
```

#### Object Lifecycle & Deferred Destruction (C4/C8/M4 Context)

**Actor、Unit、Skill、Buff 均采用延迟销毁模式**，在当前逻辑执行期间只标记销毁/完成状态，实际内存回收推迟到安全时机，避免在回调/遍历过程中发生 use-after-free。

| 对象 | 延迟机制 | 回收时机 |
|------|----------|----------|
| **Actor** | `Fini()` + `MarkDestroy()` → 入 `detroying_actors_` 延迟队列 | 下帧 `Scene::tick` 开头回收 |
| **Unit** | `StopPerform()` / `Destroy()` → 入 `UnitManager::m_delay_delete_unit_list_` | 当帧 `Space::Tick` 末尾 `UnitManager::DoUnitDelete()` 回收 |
| **Skill** | `Stop()` → `is_running = false`（标记 `IsFinish()`），Skill 实例不立即释放 | 下帧 `SkillComp::Tick` 开头遍历 `skill_map_`，将 `IsFinish()` 的 Skill 通过 `s_skill_pool_.Release()` 回收 |
| **Buff** | `RemoveBuffInstance()` → 从 `buffs_` 移除 → `PushBuffToDestroyVector()` 入 `destroying_buffs_` | 当帧 `BuffComp::Tick` 末尾统一 `KG_DELETE` 回收 |

- Space 在 Tick 中通过 `pending_actor_reqs_` 规避遍历时容器修改
- **子弹 Motion 回调陷阱**: Motion 的 `Tick` 中调用 `OnReachTargetPos` 可能同步销毁 Motion 自身（via `OnFini` → `ReleaseBulletMotion`），后续成员访问导致 use-after-free。应将可能触发销毁的调用放在 Tick 最后，并缓存局部指针

**Review 时应检查：** 任何可能触发对象销毁的调用（危险 API、`RemoveSelf`、`Die` 等），在调用后是否仍然访问了该对象的成员。即使有延迟销毁机制，部分路径（如 Buff `RemoveBuffInstance` 会立即从容器中移除）仍可能导致悬垂引用。

---

### 2. Functional Errors (功能错误) — Severity: HIGH/MEDIUM

| ID | Category | What to Check |
|----|----------|---------------|
| F1 | **Logic inversion** | Conditions reversed (`if (!x)` vs `if (x)`); wrong boolean operator (`&&` vs `\|\|`). |
| F2 | **Missing error handling** | Return values from functions not checked; functions that can fail return `void` instead of `bool`. |
| F3 | **Wrong return value** | Function documented/expected to return error codes returning int instead of bool/enum. |
| F4 | **Off-by-one** | Loop boundaries, index calculations, fence-post errors. |
| F5 | **State inconsistency** | Cache/state not updated when underlying data changes; missing cleanup in error paths. |
| F6 | **Lifecycle violation** | Using an object outside its valid lifecycle phase (e.g. accessing Actor components after destruction). |
| F7 | **Lua stack imbalance** | Lua stack not balanced after operations; input parameters modified directly instead of via `lua_pushvalue`. |
| F8 | **RPC / sync inconsistency** | Server state changed but corresponding client RPC not sent; or RPC sent in some code paths but not others for the same state change. Check that all mutation paths (add/remove/update) have matching client notifications. |
| F9 | **Timestamp / ID semantics mismatch** | Same field name used with different semantics in different code paths (e.g. property sync vs real-time RPC using different timestamps). |

---

### 3. Performance Issues (性能问题) — Severity: MEDIUM/LOW

| ID | Category | What to Check |
|----|----------|---------------|
| P1 | **Container choice** | `std::map` / `std::unordered_map` in hot paths — consider `ankerl::unordered_dense::map` or flat arrays. |
| P2 | **Iteration cost** | O(n²) nested loops on large collections; high-frequency traversals with poor memory layout. |
| P3 | **String abuse** | Unnecessary `std::string` construction/copy; prefer `std::string_view`. Avoid converting Lua strings to `std::string` when a `const char*` suffices. |
| P4 | **Unnecessary copies** | Objects passed by value when `const &` would suffice; missing move semantics on temporaries; `push_back` without `std::move` or `emplace_back`. |
| P5 | **Redundant work** | Repeated calculations that could be cached; unnecessary container clear+rebuild. |
| P6 | **Memory allocation** | Allocations in hot paths (tick functions); missing `reserve()` when size is known; unnecessary `shared_ptr` when unique ownership suffices. |
| P7 | **Parameter passing** | POD types (int, float, bool, pointers) should be passed by value, not `const &`. Complex types should be passed by `const &`. |

---

### 4. Hotfix Compatibility (热更兼容) — Severity: MEDIUM

| ID | Category | What to Check |
|----|----------|---------------|
| H1 | **Local static functions** | `static` free functions are forbidden — prevents hotfix. Use class static members or anonymous namespaces if needed. |
| H2 | **Local static variables** | `static` local variables inside functions are forbidden — breaks hotfix state. |
| H3 | **Template instantiation** | Templates used across translation units must have explicit instantiation declarations in headers, wrapped with `#ifndef HOTFIX`. |

---

### 5. Memory Safety (内存安全) — Severity: HIGH

| ID | Category | What to Check |
|----|----------|---------------|
| M1 | **Ownership clarity** | Every dynamically allocated object must have a clear, unique owner. |
| M2 | **Single exit for allocators** | Functions that allocate must have a single return path to avoid leaks. |
| M3 | **Lifetime management** | Objects outliving their allocator's scope must use reference counting or `shared_ptr`. |
| M4 | **Self-destruction in callbacks** | Object deleting itself during its own method call — ensure no member access after potential self-destruction. |

---

## Report Sections Template

以下为各 review 报告的通用章节模板，不含编码规范章节。

```markdown
## 一、崩溃风险 (Crash Risks)

### [C<N>] <Issue title>
- **位置:** `<file>:<line>`
- **代码:**
  ```cpp
  <code snippet>
  ```
- **问题:** <description>
- **建议:** <fix suggestion>

(如无问题：未发现问题。)

---

## 二、功能错误 (Functional Errors)

### [F<N>] <Issue title>
- **位置:** `<file>:<line>`
- **代码:**
  ```cpp
  <code snippet>
  ```
- **问题:** <description>
- **建议:** <fix suggestion>

(如无问题：未发现问题。)

---

## 三、性能问题 (Performance)

### [P<N>] <Issue title>
- **位置:** `<file>:<line>`
- **代码:**
  ```cpp
  <code snippet>
  ```
- **问题:** <description>
- **建议:** <fix suggestion>

(如无问题：未发现问题。)

---

## 四、热更兼容 (Hotfix Compatibility)

### [H<N>] <Issue title>
- **位置:** `<file>:<line>`
- **问题:** <description>
- **建议:** <fix suggestion>

(如无问题：未发现问题。)

---

## 五、内存安全 (Memory Safety)

### [M<N>] <Issue title>
- **位置:** `<file>:<line>`
- **问题:** <description>
- **建议:** <fix suggestion>

(如无问题：未发现问题。)

---

## 问题汇总

| 类型 | 严重程度 | 数量 |
|------|----------|------|
| 崩溃风险 | 高 | N |
| 功能错误 | 高/中 | N |
| 性能问题 | 中/低 | N |
| 热更兼容 | 中 | N |
| 内存安全 | 高 | N |

**建议优先修复:**
1. <top issue>
2. <second issue>
3. <third issue>
```

---

## Review Priorities

When reviewing, prioritize findings in this order:

1. **Crash risks and memory safety** — these cause production incidents
2. **Functional errors** — these cause bugs
3. **Hotfix compatibility** — these block online fixes
4. **Performance issues** — these affect user experience

---

## Notes

- If no issues are found in a category, write "未发现问题。" and move on.
- For large files (>500 lines), focus on changed/new code if the user specifies a diff or changelist.
- Cross-reference with `references/scene_framework_overview.md` for project-specific patterns (e.g. Actor lifecycle, component tick flow, bullet destruction callbacks).
- When reviewing combat code, pay extra attention to **C8 (pointer invalidation across external calls)** — check every `TriggerCombatEvent`, `CAGroupExecute`, `ActionExecute` call and verify no cached pointer/reference/iterator is used afterward.
- When reviewing bullet/unit code, pay extra attention to **use-after-free** patterns where callbacks may destroy `this` or the owning actor.
- When reviewing Lua-interfacing code, always check **stack balance** and that input parameters are not modified directly.
- When reviewing timer-related code, check for **C9 (stale timer ID)** — verify timer IDs are reset after firing or cancellation.
- When reviewing RPC/sync code, check for **F8 (sync inconsistency)** — verify all state mutation paths send the corresponding client notification.
- When reviewing P4 changelists, only flag style issues in **new/changed code**, not pre-existing violations in unchanged lines.
- On Windows PowerShell, use double quotes for P4 paths with `@=` syntax.
- When multiple files are involved, cross-reference for consistency (e.g. `.hpp` declarations match `.cpp` implementations).
