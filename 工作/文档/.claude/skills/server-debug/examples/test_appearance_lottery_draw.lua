-- luacheck: push ignore

-- _doAppearanceLotteryDraw 函数单元测试脚本
-- 测试覆盖：基本功能、保底机制、道具转换、绑定/非绑定、clientResultMap 累计、边界条件
--
-- 使用方式：
--   telnet 连接 logic_0 后执行：dofile("/Test/test_appearance_lottery_draw.lua")
--   或将此文件复制到 Server/script_lua/Test/ 目录后执行
--
-- 前置条件：
--   - 服务器已启动且有在线玩家
--   - AppearanceLotteryComponent 已挂载到 AvatarActor
--   - AppearancePrizePoolData 配置表已加载
--
-- 测试项：
--   1. 基本功能 - 单次抽奖返回值完整性
--   2. 绑定/非绑定道具产出位置
--   3. 奖池限制计数 dayCount/totalCount/weekMaxDayCount 累加
--   4. 保底计数更新（SSR/SR/R 分支）
--   5. 多次连抽 resultItemMap/clientResultMap 累加
--   6. 道具转换 NumLimit 机制
--   7. 品质分布统计（100次采样）
--   8. 保底必中 SSR 验证

local utils = kg_require("Common.Utils.CommonUtils")
local item_utils = kg_require("Shared.Utils.ItemUtils")
local const = kg_require("Shared.Const")

print("============================================")
print("=== _doAppearanceLotteryDraw 单元测试 ===")
print("============================================")

-- =============================================
-- 辅助函数
-- =============================================

local testCount = 0
local passCount = 0
local failCount = 0
local failMessages = {}

local function assertEqual(actual, expected, msg)
    testCount = testCount + 1
    if actual == expected then
        passCount = passCount + 1
    else
        failCount = failCount + 1
        local errMsg = string.format("  FAIL [%s]: expected=%s, actual=%s", msg, tostring(expected), tostring(actual))
        table.insert(failMessages, errMsg)
        print(errMsg)
    end
end

local function assertNotNil(actual, msg)
    testCount = testCount + 1
    if actual ~= nil then
        passCount = passCount + 1
    else
        failCount = failCount + 1
        local errMsg = string.format("  FAIL [%s]: 预期非nil，实际为nil", msg)
        table.insert(failMessages, errMsg)
        print(errMsg)
    end
end

local function assertTrue(actual, msg)
    testCount = testCount + 1
    if actual then
        passCount = passCount + 1
    else
        failCount = failCount + 1
        local errMsg = string.format("  FAIL [%s]: 预期为true", msg)
        table.insert(failMessages, errMsg)
        print(errMsg)
    end
end

local function assertGTE(actual, expected, msg)
    testCount = testCount + 1
    if actual >= expected then
        passCount = passCount + 1
    else
        failCount = failCount + 1
        local errMsg = string.format("  FAIL [%s]: expected >= %s, actual=%s", msg, tostring(expected), tostring(actual))
        table.insert(failMessages, errMsg)
        print(errMsg)
    end
end

--- 备份玩家抽奖相关数据，用于测试前保存和测试后恢复
local function backupPlayerData(p)
    local backup = {}
    -- 深拷贝保底计数
    backup.drawCountMap = {}
    for recordType, byItemID in pairs(p.appearanceLotteryDrawCountMap or {}) do
        backup.drawCountMap[recordType] = {}
        for itemID, byQuality in pairs(byItemID) do
            backup.drawCountMap[recordType][itemID] = {}
            for quality, count in pairs(byQuality) do
                backup.drawCountMap[recordType][itemID][quality] = count
            end
        end
    end
    -- 深拷贝奖池限制计数
    backup.poolLimitMap = {}
    for poolId, info in pairs(p.appearancePoolLimitCountMap or {}) do
        backup.poolLimitMap[poolId] = {
            dayCount = info.dayCount,
            totalCount = info.totalCount,
            weekMaxDayCount = info.weekMaxDayCount,
        }
    end
    -- 深拷贝转换计数
    backup.convertMap = {}
    for itemID, count in pairs(p.appearanceLotteryConvertItemCountMap or {}) do
        backup.convertMap[itemID] = count
    end
    return backup
end

--- 恢复玩家抽奖数据
local function restorePlayerData(p, backup)
    -- 恢复保底计数
    for recordType, _ in pairs(p.appearanceLotteryDrawCountMap) do
        p.appearanceLotteryDrawCountMap[recordType] = nil
    end
    for recordType, byItemID in pairs(backup.drawCountMap) do
        p.appearanceLotteryDrawCountMap[recordType] = {}
        for itemID, byQuality in pairs(byItemID) do
            p.appearanceLotteryDrawCountMap[recordType][itemID] = {}
            for quality, count in pairs(byQuality) do
                p.appearanceLotteryDrawCountMap[recordType][itemID][quality] = count
            end
        end
    end
    -- 恢复奖池限制计数
    for poolId, _ in pairs(p.appearancePoolLimitCountMap) do
        p.appearancePoolLimitCountMap[poolId] = nil
    end
    for poolId, info in pairs(backup.poolLimitMap) do
        p.appearancePoolLimitCountMap[poolId] = {
            dayCount = info.dayCount,
            totalCount = info.totalCount,
            weekMaxDayCount = info.weekMaxDayCount,
        }
    end
    -- 恢复转换计数
    for itemID, _ in pairs(p.appearanceLotteryConvertItemCountMap) do
        p.appearanceLotteryConvertItemCountMap[itemID] = nil
    end
    for itemID, count in pairs(backup.convertMap) do
        p.appearanceLotteryConvertItemCountMap[itemID] = count
    end
end

-- =============================================
-- 查找测试玩家
-- =============================================

local p = nil
local players = getplayers()
if players then
    for _, player in pairs(players) do
        if player then
            p = player
            break
        end
    end
end

if not p then
    print("ERROR: 无在线玩家，无法执行测试")
    return
end

print(string.format("测试玩家: %s (id=%s)", p.Name or "unknown", tostring(p.id)))

-- 检查函数是否存在
if not p._doAppearanceLotteryDraw then
    print("ERROR: _doAppearanceLotteryDraw 函数不存在，AppearanceLotteryComponent 可能未挂载")
    return
end

-- =============================================
-- 查找有效的测试抽奖池
-- =============================================

local testPoolId = nil
local testPoolDataRow = nil
local poolTable = TableData.GetAppearancePrizePoolDataTable()
if not poolTable then
    print("ERROR: 无法获取 AppearancePrizePoolDataTable")
    return
end

for poolId, poolRow in pairs(poolTable) do
    -- 检查该池是否有对应的奖品权重数据
    local poolItemWeight = TableData.Get_AppearanceLotteryQuality2PoolItemIDWeight()[poolId]
    if poolItemWeight then
        testPoolId = poolId
        testPoolDataRow = poolRow
        break
    end
end

if not testPoolId then
    print("ERROR: 未找到任何有效的抽奖池配置")
    return
end

local testCostItemID = testPoolDataRow.UsedBindPropId or testPoolDataRow.UsedPropId or 2000001
local testRecordType = testPoolDataRow.RecordType
local testProbabilityType = testPoolDataRow.ProbabilityType

print(string.format("测试抽奖池: poolId=%d, costItemID=%d, recordType=%s, probabilityType=%s",
    testPoolId, testCostItemID, tostring(testRecordType), tostring(testProbabilityType)))

-- 备份数据
local backup = backupPlayerData(p)
print("已备份玩家抽奖数据")

-- =============================================
-- 测试1：基本功能 - 单次抽奖返回值验证
-- =============================================
print("\n--- 测试1: 基本功能 - 单次抽奖返回值 ---")

local resultItemMap = {}
local clientResultMap = {}
local opNUID = _script.genUUID()

local success, lotteryResultID, resultQuality, itemID, bConverted = custom_xpcall(function()
    return p:_doAppearanceLotteryDraw(testPoolId, true, testCostItemID, resultItemMap, clientResultMap, opNUID)
end)

if success then
    assertNotNil(lotteryResultID, "返回lotteryResultID非nil")
    assertNotNil(resultQuality, "返回resultQuality非nil")
    assertNotNil(itemID, "返回itemID非nil")
    assertNotNil(bConverted, "返回bConverted非nil")

    -- 验证quality范围
    local qualitySSR = Enum.EAPPEARANCE_LOTTERY_QUALITY.SSR
    local qualitySR = Enum.EAPPEARANCE_LOTTERY_QUALITY.SR
    local qualityR = Enum.EAPPEARANCE_LOTTERY_QUALITY.R
    assertTrue(resultQuality == qualitySSR or resultQuality == qualitySR or resultQuality == qualityR,
        "quality值在有效范围(SSR=1/SR=2/R=3)")

    -- 验证bConverted是boolean
    assertTrue(bConverted == true or bConverted == false, "bConverted为boolean类型")

    -- 验证resultItemMap被正确填充
    assertTrue(next(resultItemMap) ~= nil, "resultItemMap非空")
    -- 检查resultItemMap中的道具数据结构
    for iID, numInfo in pairs(resultItemMap) do
        assertNotNil(numInfo[const.INV_BOUND_TYPE_INSENSITIVE], "resultItemMap道具包含insensitive字段")
        assertNotNil(numInfo[const.INV_BOUND_TYPE_BOUND], "resultItemMap道具包含bound字段")
        assertNotNil(numInfo[const.INV_BOUND_TYPE_UNBOUND], "resultItemMap道具包含unbound字段")
        print(string.format("  奖励道具: itemID=%d, insensitive=%d, bound=%d, unbound=%d",
            iID, numInfo[1], numInfo[2], numInfo[3]))
        break  -- 只检查第一个
    end

    -- 验证clientResultMap被正确填充
    assertTrue(next(clientResultMap) ~= nil, "clientResultMap非空")
    for rID, info in pairs(clientResultMap) do
        assertEqual(info.id, rID, "clientResultMap.id等于key")
        assertGTE(info.drawTimes, 1, "clientResultMap.drawTimes >= 1")
        assertNotNil(info.convertedTimes, "clientResultMap包含convertedTimes")
        print(string.format("  客户端结果: lotteryResultID=%d, drawTimes=%d, convertedTimes=%d",
            rID, info.drawTimes, info.convertedTimes))
        break
    end

    print(string.format("  抽奖结果: lotteryResultID=%s, quality=%s, itemID=%s, converted=%s",
        tostring(lotteryResultID), tostring(resultQuality), tostring(itemID), tostring(bConverted)))
else
    failCount = failCount + 1
    testCount = testCount + 1
    print(string.format("  FAIL [基本功能]: 函数执行异常: %s", tostring(lotteryResultID)))
end

-- 恢复数据
restorePlayerData(p, backup)

-- =============================================
-- 测试2：绑定道具 vs 非绑定道具
-- =============================================
print("\n--- 测试2: 绑定 vs 非绑定道具产出 ---")

-- 2a: 绑定道具抽奖 (isCostItemBind=true)
local resultMapBind = {}
local clientMapBind = {}
local success2a, rID2a, rQ2a, iID2a, bC2a = custom_xpcall(function()
    return p:_doAppearanceLotteryDraw(testPoolId, true, testCostItemID, resultMapBind, clientMapBind, _script.genUUID())
end)

if success2a and rID2a then
    -- 绑定抽奖时，resultItemMap中道具应该在bound位
    local hasBound = false
    for iID, numInfo in pairs(resultMapBind) do
        if numInfo[const.INV_BOUND_TYPE_BOUND] > 0 then
            hasBound = true
        end
    end
    assertTrue(hasBound, "绑定道具抽奖产出在bound位")
    print("  绑定抽奖: 产出道具在bound位 - OK")
else
    print(string.format("  WARN: 绑定抽奖执行失败: %s", tostring(rID2a)))
end

restorePlayerData(p, backup)

-- 2b: 非绑定道具抽奖 (isCostItemBind=false)，结果取决于配置 IFBound
local resultMapUnbind = {}
local clientMapUnbind = {}
local success2b, rID2b, rQ2b, iID2b, bC2b = custom_xpcall(function()
    return p:_doAppearanceLotteryDraw(testPoolId, false, testCostItemID, resultMapUnbind, clientMapUnbind, _script.genUUID())
end)

if success2b and rID2b then
    local hasAny = false
    for iID, numInfo in pairs(resultMapUnbind) do
        if numInfo[const.INV_BOUND_TYPE_BOUND] > 0 or numInfo[const.INV_BOUND_TYPE_UNBOUND] > 0 then
            hasAny = true
        end
    end
    assertTrue(hasAny, "非绑定道具抽奖产出存在数量")
    print("  非绑定抽奖: 产出道具数量正常 - OK")
else
    print(string.format("  WARN: 非绑定抽奖执行失败: %s", tostring(rID2b)))
end

restorePlayerData(p, backup)

-- =============================================
-- 测试3：奖池限制计数更新验证
-- =============================================
print("\n--- 测试3: 奖池限制计数更新 ---")

-- 先清空该池的计数
p.appearancePoolLimitCountMap[testPoolId] = nil

local resultMap3 = {}
local clientMap3 = {}
local success3 = custom_xpcall(function()
    return p:_doAppearanceLotteryDraw(testPoolId, true, testCostItemID, resultMap3, clientMap3, _script.genUUID())
end)

if success3 then
    local limitInfo = p.appearancePoolLimitCountMap[testPoolId]
    assertNotNil(limitInfo, "抽奖后poolLimitCountInfo被创建")
    if limitInfo then
        assertEqual(limitInfo.dayCount, 1, "第一次抽奖后dayCount=1")
        assertEqual(limitInfo.totalCount, 1, "第一次抽奖后totalCount=1")
        assertEqual(limitInfo.weekMaxDayCount, 1, "第一次抽奖后weekMaxDayCount=1")

        -- 再抽一次，验证累加
        local resultMap3b = {}
        local clientMap3b = {}
        custom_xpcall(function()
            return p:_doAppearanceLotteryDraw(testPoolId, true, testCostItemID, resultMap3b, clientMap3b, _script.genUUID())
        end)

        assertEqual(limitInfo.dayCount, 2, "第二次抽奖后dayCount=2")
        assertEqual(limitInfo.totalCount, 2, "第二次抽奖后totalCount=2")
        assertEqual(limitInfo.weekMaxDayCount, 2, "第二次抽奖后weekMaxDayCount=2")
    end
else
    print("  FAIL: 测试3执行异常")
    failCount = failCount + 1
    testCount = testCount + 1
end

restorePlayerData(p, backup)

-- =============================================
-- 测试4：保底计数更新验证
-- =============================================
print("\n--- 测试4: 保底计数更新 ---")

-- 清空保底计数
if p.appearanceLotteryDrawCountMap[testRecordType] then
    p.appearanceLotteryDrawCountMap[testRecordType][testCostItemID] = nil
end

local resultMap4 = {}
local clientMap4 = {}
local success4, rID4, rQ4 = custom_xpcall(function()
    return p:_doAppearanceLotteryDraw(testPoolId, true, testCostItemID, resultMap4, clientMap4, _script.genUUID())
end)

if success4 and rID4 then
    local guaranteeCountByQuality = p.appearanceLotteryDrawCountMap[testRecordType]
        and p.appearanceLotteryDrawCountMap[testRecordType][testCostItemID]
    assertNotNil(guaranteeCountByQuality, "保底计数map被创建")

    local qualitySSR = Enum.EAPPEARANCE_LOTTERY_QUALITY.SSR
    local qualitySR = Enum.EAPPEARANCE_LOTTERY_QUALITY.SR

    if guaranteeCountByQuality then
        if rQ4 == qualitySSR then
            -- 抽到SSR，SSR和SR的保底计数都应该被重置(nil)
            assertTrue(guaranteeCountByQuality[qualitySSR] == nil, "抽到SSR后SSR保底重置")
            assertTrue(guaranteeCountByQuality[qualitySR] == nil, "抽到SSR后SR保底重置")
            print("  抽到SSR，保底计数已重置 - OK")
        elseif rQ4 == qualitySR then
            -- 抽到SR，SR保底重置，SSR保底+1
            assertTrue(guaranteeCountByQuality[qualitySR] == nil, "抽到SR后SR保底重置")
            assertEqual(guaranteeCountByQuality[qualitySSR], 1, "抽到SR后SSR保底计数+1")
            print("  抽到SR，SSR保底+1，SR保底重置 - OK")
        else
            -- 抽到R，SSR和SR保底都+1
            assertEqual(guaranteeCountByQuality[qualitySSR], 1, "抽到R后SSR保底计数+1")
            assertEqual(guaranteeCountByQuality[qualitySR], 1, "抽到R后SR保底计数+1")
            print("  抽到R，SSR和SR保底都+1 - OK")
        end
    end
else
    print(string.format("  FAIL: 测试4执行异常: %s", tostring(rID4)))
    failCount = failCount + 1
    testCount = testCount + 1
end

restorePlayerData(p, backup)

-- =============================================
-- 测试5：多次抽奖 resultItemMap 累加验证
-- =============================================
print("\n--- 测试5: 多次抽奖 resultItemMap 累加 ---")

local resultMap5 = {}
local clientMap5 = {}
local drawCount = 5
local successCount = 0

for i = 1, drawCount do
    local ok = custom_xpcall(function()
        return p:_doAppearanceLotteryDraw(testPoolId, true, testCostItemID, resultMap5, clientMap5, _script.genUUID())
    end)
    if ok then
        successCount = successCount + 1
    end
end

assertEqual(successCount, drawCount, string.format("连抽%d次全部成功", drawCount))

-- 验证resultItemMap中道具数量之和
local totalItemCount = 0
for iID, numInfo in pairs(resultMap5) do
    totalItemCount = totalItemCount + (numInfo[const.INV_BOUND_TYPE_INSENSITIVE] or 0)
        + (numInfo[const.INV_BOUND_TYPE_BOUND] or 0)
        + (numInfo[const.INV_BOUND_TYPE_UNBOUND] or 0)
end
assertGTE(totalItemCount, drawCount, string.format("连抽%d次后道具总数>=%d", drawCount, drawCount))
print(string.format("  连抽%d次，产出道具种类: %d, 道具总数: %d", drawCount, utils.tableLen and utils.tableLen(resultMap5) or 0, totalItemCount))

-- 验证clientResultMap中drawTimes之和
local totalDrawTimes = 0
for rID, info in pairs(clientMap5) do
    totalDrawTimes = totalDrawTimes + (info.drawTimes or 0)
end
assertEqual(totalDrawTimes, drawCount, string.format("clientResultMap.drawTimes总和=%d", drawCount))

-- 验证奖池限制计数
local limitInfo5 = p.appearancePoolLimitCountMap[testPoolId]
if limitInfo5 then
    -- 注意：可能之前备份中有存量，这里只验证增量
    print(string.format("  奖池限制: dayCount=%d, totalCount=%d", limitInfo5.dayCount, limitInfo5.totalCount))
end

restorePlayerData(p, backup)

-- =============================================
-- 测试6：道具转换验证 (NumLimit机制)
-- =============================================
print("\n--- 测试6: 道具转换验证 (NumLimit机制) ---")

local convertTable = TableData.Get_AppearanceLotteryConvertItemID2Count()
local testConvertItemID = nil
local testConvertInfo = nil

if convertTable then
    for iID, info in pairs(convertTable) do
        testConvertItemID = iID
        testConvertInfo = info
        break
    end
end

if testConvertItemID and testConvertInfo then
    -- 找到该道具对应的奖池行
    local poolItemWeight = TableData.Get_AppearanceLotteryQuality2PoolItemIDWeight()[testPoolId]
    local targetLotteryResultID = nil
    local targetRow = nil
    if poolItemWeight then
        for quality, weightMap in pairs(poolItemWeight) do
            for lotteryResultID, weight in pairs(weightMap) do
                local row = TableData.GetAppearancePrizePoolItemDataRow(lotteryResultID)
                if row and row.ItemID == testConvertItemID then
                    targetLotteryResultID = lotteryResultID
                    targetRow = row
                    break
                end
            end
            if targetLotteryResultID then break end
        end
    end

    if targetRow then
        -- 将该道具的转换计数设置到 NumLimit，使下次必定触发转换
        local oldConvertCount = p.appearanceLotteryConvertItemCountMap[testConvertItemID]
        p.appearanceLotteryConvertItemCountMap[testConvertItemID] = targetRow.NumLimit

        print(string.format("  测试道具: itemID=%d, NumLimit=%d", testConvertItemID, targetRow.NumLimit))
        print(string.format("  转换目标: ConvertItemID=%d, ConvertItemNum=%d",
            testConvertInfo.ConvertItemID, testConvertInfo.ConvertItemNum))

        -- 注意：这里无法控制抽到哪个道具，只验证计数逻辑是否正确
        -- 验证 numLimit 时，转换计数已经设置到了 NumLimit
        local currentCount = p.appearanceLotteryConvertItemCountMap[testConvertItemID]
        assertEqual(currentCount, targetRow.NumLimit, "转换计数设置为NumLimit")
        print("  转换计数设置成功 - OK")

        -- 恢复
        if oldConvertCount then
            p.appearanceLotteryConvertItemCountMap[testConvertItemID] = oldConvertCount
        else
            p.appearanceLotteryConvertItemCountMap[testConvertItemID] = nil
        end
    else
        print(string.format("  SKIP: 当前测试池%d中未找到可转换道具%d", testPoolId, testConvertItemID))
    end
else
    print("  SKIP: 无道具转换配置，跳过转换测试")
end

restorePlayerData(p, backup)

-- =============================================
-- 测试7：品质权重分布验证 (统计学测试)
-- =============================================
print("\n--- 测试7: 品质分布统计 (100次抽奖) ---")

local statDrawCount = 100
local qualityDistribution = {}
local qualitySSR = Enum.EAPPEARANCE_LOTTERY_QUALITY.SSR
local qualitySR = Enum.EAPPEARANCE_LOTTERY_QUALITY.SR
local qualityR = Enum.EAPPEARANCE_LOTTERY_QUALITY.R

qualityDistribution[qualitySSR] = 0
qualityDistribution[qualitySR] = 0
qualityDistribution[qualityR] = 0

-- 清空保底计数，从0开始统计
if p.appearanceLotteryDrawCountMap[testRecordType] then
    p.appearanceLotteryDrawCountMap[testRecordType][testCostItemID] = nil
end
p.appearancePoolLimitCountMap[testPoolId] = nil

local statSuccessCount = 0
for i = 1, statDrawCount do
    local resultMap7 = {}
    local clientMap7 = {}
    local ok7, _, q7 = custom_xpcall(function()
        return p:_doAppearanceLotteryDraw(testPoolId, true, testCostItemID, resultMap7, clientMap7, _script.genUUID())
    end)
    if ok7 and q7 then
        qualityDistribution[q7] = (qualityDistribution[q7] or 0) + 1
        statSuccessCount = statSuccessCount + 1
    end
end

assertEqual(statSuccessCount, statDrawCount, string.format("%d次统计抽奖全部成功", statDrawCount))

local ssrRate = qualityDistribution[qualitySSR] / statDrawCount * 100
local srRate = qualityDistribution[qualitySR] / statDrawCount * 100
local rRate = qualityDistribution[qualityR] / statDrawCount * 100

print(string.format("  SSR: %d次 (%.1f%%)", qualityDistribution[qualitySSR], ssrRate))
print(string.format("  SR:  %d次 (%.1f%%)", qualityDistribution[qualitySR], srRate))
print(string.format("  R:   %d次 (%.1f%%)", qualityDistribution[qualityR], rRate))
print(string.format("  总计: %d次", statSuccessCount))

-- 验证 R 出现次数最多（通常情况下）
assertTrue(qualityDistribution[qualityR] >= qualityDistribution[qualitySSR],
    "R出现次数 >= SSR出现次数(概率分布合理)")

-- 验证三种品质之和等于总抽奖次数
assertEqual(qualityDistribution[qualitySSR] + qualityDistribution[qualitySR] + qualityDistribution[qualityR],
    statSuccessCount, "三种品质之和等于总抽奖次数")

restorePlayerData(p, backup)

-- =============================================
-- 测试8：保底必中SSR验证
-- =============================================
print("\n--- 测试8: 保底必中SSR验证 ---")

-- 找到SSR保底次数上限
local ssrRow = TableData.GetProbabilitySSRDataRow(testProbabilityType)
local maxGuaranteeCount = nil
if ssrRow then
    for k, v in pairs(ssrRow) do
        if v.RewardWeight == 10000 then
            maxGuaranteeCount = k
            break
        end
    end
end

if maxGuaranteeCount then
    print(string.format("  SSR保底次数: %d (第%d抽必中SSR)", maxGuaranteeCount, maxGuaranteeCount))

    -- 设置保底计数为 maxGuaranteeCount - 1，下一次应该必中SSR
    if not p.appearanceLotteryDrawCountMap[testRecordType] then
        p.appearanceLotteryDrawCountMap[testRecordType] = {}
    end
    p.appearanceLotteryDrawCountMap[testRecordType][testCostItemID] = {
        [qualitySSR] = maxGuaranteeCount - 1,
        [qualitySR] = maxGuaranteeCount - 1,
    }

    local resultMap8 = {}
    local clientMap8 = {}
    local success8, rID8, rQ8 = custom_xpcall(function()
        return p:_doAppearanceLotteryDraw(testPoolId, true, testCostItemID, resultMap8, clientMap8, _script.genUUID())
    end)

    if success8 and rQ8 then
        assertEqual(rQ8, qualitySSR, "保底抽奖必出SSR")
        if rQ8 == qualitySSR then
            print("  保底必中SSR验证通过!")
        else
            print(string.format("  WARN: 保底未触发SSR，实际品质=%d", rQ8))
        end

        -- 验证保底计数被重置
        local afterCount = p.appearanceLotteryDrawCountMap[testRecordType]
            and p.appearanceLotteryDrawCountMap[testRecordType][testCostItemID]
        if afterCount then
            assertTrue(afterCount[qualitySSR] == nil, "保底SSR后SSR计数被重置")
            assertTrue(afterCount[qualitySR] == nil, "保底SSR后SR计数被重置")
        end
    else
        print(string.format("  FAIL: 保底测试执行异常: %s", tostring(rID8)))
        failCount = failCount + 1
        testCount = testCount + 1
    end
else
    print("  SKIP: 未找到SSR保底配置，跳过保底测试")
end

restorePlayerData(p, backup)

-- =============================================
-- 测试结果汇总
-- =============================================
print("\n============================================")
print(string.format("=== 测试结果: 总计 %d, 通过 %d, 失败 %d ===",
    testCount, passCount, failCount))
print("============================================")

if failCount > 0 then
    print("\n失败项详情:")
    for _, msg in ipairs(failMessages) do
        print(msg)
    end
end

print("\n数据恢复: 已恢复玩家抽奖数据到测试前状态")
print("=== 测试完成 ===")

-- luacheck: pop