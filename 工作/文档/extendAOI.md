ExtendAoi使用和实现

在一些需求中，策划想某些Npc或者怪能或者任意有需求的entity能超出玩家视野范围就能被看见。

### 使用接口

对应的接口分别为：

1. 全场景可见
    

这种在底层实现是利用引擎的Attention机制，无论和被观察对象有多远，对方永远在我的“视野”里，对方的allclients属性同步和rpc  场景中所有的玩家都可以收到。

entity可以通过继承ActorBase上的NeedsAoiAttention方法来确定是否需要 "场景中所有的玩家都能看见我"

```
---@brief 是否需要被全场景的人attention, 默认不需要
function ActorBase:NeedsAoiAttention(space)
    return false
end
```

  

2. 远距离可见（目前统一是100米）
    

目前是通过给对应的npc加了一个100米的circlTrap，然后监听on_enter_trap/on_leave_trap事件来让玩家Attention/UnAttention该entity。

同上全场景可见的接口，entity可以通过继承ActorBase上的NeedsExtendAoi方法来确定是否需要  "场景中的所有玩家能100米就能看见我 (即使他的aoi范围只有30米)"

```
---@brief 是否需要更大被可见范围, 默认不需要
function ActorBase:NeedsExtendAoi(space)
    return false
end
```

接口使用上到这里就可以了。

  

### 实现原理

在逻辑实现上，实现上述方法后，在进入场景后会自动:

```
---@param Actor ActorBase
function Space:OnActorEnter(actor)
		....
  
    self:safeCall(self.onActorEnterEvent, actor)
    -- 放在onActorEnterEvent之后，方便业务可以在OnNpcActorEnter(actor)中设置NeedAoiAttention中的条件
    if actor:NeedsAoiAttention(self) then
        self:AddAttentionEntity(actor.id)
    elseif actor:NeedsExtendAoi(self) then
        actor:AddExtendAoiTrap()
    end
		
  .......
end
```

全场景可见对象：

1. 让场景中所有的avatar 能看到我
    
2. 加入到space._attentionEntities, 让后面进入场景的avatar也能看到我
    

```
---@brief 让所有avatar attention entityId
--- 时机：需要entity已经在space中
function Space:AddAttentionEntity(entityId)
    if self:ForbidenAoiAttention() then
        self:logWarnFmt("space forbidden attention with space type %s", self.Type)
        return
    end
    if self._attentionEntities[entityId] then
        return
    end
    self._attentionEntities[entityId] = true

    for _, avatarId in pairs(self.AvatarActors) do
        if avatarId == entityId then
            goto continue
        end
        local avatar = self.entities[avatarId]
        if avatar and not avatar.bDestroying and not avatar:IsBot() and avatar.witness then
            self:SafeCallNotMe(avatar.Attention, avatar, entityId)
        end
        ::continue::
    end
end
```

  

远距离可见：

1. entity进入Space会加一个以自己为中心100米的CircleTrap
    

```
EXTEND_AOI_RADIUS = 10000   -- 100米
function ActorBase:AddExtendAoiTrap()
    local space = self.Space
    if not space then
        return
    end
    if self:NeedsAoiAttention(space) then
        self:logErrorFmt("ExtendAoiTrap already attention, no need extendAoiTrap")
        return
    end
    if self.extendAoiTrapId then
        self:logErrorFmt("ExtendAoiTrap already exist extendAoiTrapId=%s", self.extendAoiTrapId)
        return
    end
    self.extendAoiTrapId = self:addCircleTrap(EXTEND_AOI_RADIUS, nil, false, aoi_tag.avatar)
    self:logInfoFmt("ExtendAoiTrap add extendAoiTrapId=%s", self.extendAoiTrapId)
end
```

2. 监听on_enter_trap、on_leave_trap事件
    

```
function ActorBase:on_enter_trap(trapId, otherEntId)
    local other_ent = _script.ientities[otherEntId]
    if not other_ent then
        return
    end
    if trapId == self.extendAoiTrapId then
        self:onEnterExtendAoiTrap(other_ent)
    end
    
    self:triggerTrapSingleCB(true, trapId, other_ent)
end

function ActorBase:on_leave_trap(trapId, otherEntId)
    local other_ent = _script.ientities[otherEntId]
    if not other_ent then
        return
    end
    if trapId == self.extendAoiTrapId then
        self:onLeaveExtendAoiTrap(other_ent)
    end
    self:triggerTrapSingleCB(false, trapId, other_ent)
end
```

3. avatar进入Trap 触发Attention ，离开Trap 触发unAttention
    

```
function ActorBase:onEnterExtendAoiTrap(avatar)
    if avatar and avatar.IsPlayer then
        avatar:Attention(self.id)
        self:logDebugFmt("ExtendAoiTrap onEnterExtendAoiTrap avatar:%s attention entity:%s", avatar.id, self.id)
    end 
end

function ActorBase:onLeaveExtendAoiTrap(avatar)
    if avatar and avatar.IsPlayer and avatar.Space then
        avatar:UnAttention(self.id)
        self:logDebugFmt("ExtendAoiTrap onLeaveExtendAoiTrap avatar:%s unAttention entity:%s", avatar.id, self.id)
    end 
end
```


### NpcActor

目前策划侧可以配置出哪些NpcActor需要实现上上述两种机制：

1. Monster_怪物表
    
![[Pasted image 20260214180154.png]]


其中BossExtendAOI 被策划填1的话，表示需要100米就能看见该Npc

2. 场编数据中Npc的AOIRange
    
![[Pasted image 20260214180207.png]]

Far：表示100米能看见该Npc

FullMap: 表示无论有多远都能看见该对象，也就是策划常说的全场景可见，譬如公会联赛中的防御塔。

  

```
---@brief 重载是否需要被attention方法
---@return boolean
---@override
function NpcActor:NeedsAoiAttention(space)
    local aoiExtendTag = self:getAoiTagByNpcType(space)
    return bit_and(aoiExtendTag, aoi_tag.full_map) ~= 0
end

---@brief 重载是否需要更大被可见范围
---@return boolean
---@override
function NpcActor:NeedsExtendAoi(space)
    local aoiExtendTag = self:getAoiTagByNpcType(space)
    return bit_and(aoiExtendTag, aoi_tag.boss) ~= 0
end
```

  

除此之外还有一些业务需要改变Npc的类型（可以搜索self:setAoiTagByNpcType(self.Space, true), 调用到UpdateBaseAoiTag， 最终实现从全图可见到100米(或者相反）的视野需求切换。

```

---@brief 进场景后，一些特殊的逻辑导致aoiTag需要变更时调用， 比SetBaseAoiTag多一层attention
function ActorBase:UpdateBaseAoiTag(aoiExtendTag, actorTypeTag)
    local oldAoiTag = self:getAoiTag()
    self:SetBaseAoiTag(aoiExtendTag, actorTypeTag)
    local newAoiTag = self:getAoiTag()
    
    local space = self.Space
    if not space then
        return
    end
    local attentionTag = aoi_tag.full_map
    local extendTag = aoi_tag.boss

    if bit_and(oldAoiTag, attentionTag) ~= 0 and bit_and(newAoiTag, attentionTag) == 0 then
        -- 变成了不需要全场景attention的actor
        space:RemoveAttentionEntity(self.id)
    end
    if bit_and(oldAoiTag, extendTag) ~= 0 and bit_and(newAoiTag, extendTag) == 0 then
        -- 变成了不需要更大可见范围的actor
        self:RemoveExtendAoiTrap()
    end

    if bit_and(oldAoiTag, attentionTag) == 0 and bit_and(newAoiTag, attentionTag) ~= 0 then
        -- 变成了需要全场attention的actor
        space:AddAttentionEntity(self.id)
    end

    if bit_and(oldAoiTag, extendTag) == 0 and bit_and(newAoiTag, extendTag) ~= 0 then
        -- 变成了需要更大可见范围的actor
        self:AddExtendAoiTrap()
    end
end
```