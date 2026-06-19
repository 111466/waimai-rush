-- ============================================================================
-- 外卖冲冲冲 - 骑手等级/经验模块
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local meta = require("meta_progress")

local M = {}

local DEFAULT_LEVELS = {
    { level = 1, xpToNext = 60,  title = "新手骑手" },
    { level = 2, xpToNext = 90,  title = "街区熟手" },
    { level = 3, xpToNext = 130, title = "城市快骑" },
    { level = 4, xpToNext = 180, title = "准时达人" },
    { level = 5, xpToNext = 240, title = "远单能手" },
    { level = 6, xpToNext = 320, title = "金牌骑手" },
    { level = 7, xpToNext = 420, title = "路线专家" },
    { level = 8, xpToNext = 540, title = "稳送先锋" },
    { level = 9, xpToNext = 680, title = "派单王牌" },
    { level = 10, xpToNext = 0, title = "冲刺之星" },
}

local DEFAULT_ORDER_COUNT_UNLOCKS = {
    { level = 1, count = 2 },
    { level = 3, count = 3 },
    { level = 6, count = 4 },
    { level = 10, count = 5 },
}

local DEFAULT_ORDER_TYPE_UNLOCKS = {
    normal = 1,
    nearby = 1,
    rush = 2,
    long = 5,
    fragile = 8,
}

local DEFAULT_ORDER_TYPE_ORDER = { "normal", "nearby", "rush", "long", "fragile" }

local DEFAULT_HIGH_VALUE_WEIGHT_BONUS = {
    { level = 1, bonus = 0.00 },
    { level = 3, bonus = 0.10 },
    { level = 5, bonus = 0.20 },
    { level = 8, bonus = 0.30 },
    { level = 10, bonus = 0.40 },
}

local DEFAULT_HIGH_VALUE_ORDER_TYPES = {
    rush = true,
    long = true,
    fragile = true,
}

M.level = 1
M.xp = 0
M.totalXp = 0
M.runXp = 0
M.lastLevelUp = nil

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function GetLevelRows()
    return CONFIG.RIDER_LEVELS or DEFAULT_LEVELS
end

local function GetMaxLevel()
    local maxLevel = CONFIG.RIDER_LEVEL_MAX or 0
    local rows = GetLevelRows()
    for _, row in ipairs(rows) do
        if row.level and row.level > maxLevel then
            maxLevel = row.level
        end
    end
    return math.max(1, maxLevel)
end

local function GetLevelConfig(level)
    local rows = GetLevelRows()
    for _, row in ipairs(rows) do
        if row.level == level then
            return row
        end
    end
    return rows[1] or DEFAULT_LEVELS[1]
end

local function GetXPToNextForLevel(level)
    local row = GetLevelConfig(level)
    return math.max(0, row and row.xpToNext or 0)
end

local function GetTitleForLevel(level)
    local row = GetLevelConfig(level)
    return (row and row.title) or "骑手"
end

local function GetOrderCountUnlocks()
    return CONFIG.RIDER_ORDER_COUNT_UNLOCKS or DEFAULT_ORDER_COUNT_UNLOCKS
end

local function GetOrderTypeUnlocks()
    return CONFIG.RIDER_ORDER_TYPE_UNLOCKS or DEFAULT_ORDER_TYPE_UNLOCKS
end

local function GetOrderTypeOrder()
    return CONFIG.RIDER_ORDER_TYPE_ORDER or DEFAULT_ORDER_TYPE_ORDER
end

local function GetHighValueWeightBonusRows()
    return CONFIG.RIDER_HIGH_VALUE_WEIGHT_BONUS or DEFAULT_HIGH_VALUE_WEIGHT_BONUS
end

local function GetHighValueOrderTypes()
    return CONFIG.RIDER_HIGH_VALUE_ORDER_TYPES or DEFAULT_HIGH_VALUE_ORDER_TYPES
end

local function AddUnlocksBetween(oldLevel, newLevel, unlocks)
    unlocks = unlocks or {}
    if newLevel <= oldLevel then
        return unlocks
    end

    for level = oldLevel + 1, newLevel do
        for _, row in ipairs(GetOrderCountUnlocks()) do
            if row.level == level then
                unlocks[#unlocks + 1] = {
                    type = "order_count",
                    value = row.count,
                    level = level,
                }
            end
        end

        for typeId, unlockLevel in pairs(GetOrderTypeUnlocks()) do
            if unlockLevel == level then
                unlocks[#unlocks + 1] = {
                    type = "order_type",
                    value = typeId,
                    level = level,
                }
            end
        end
    end

    return unlocks
end

local function GetHighValueWeightBonus()
    local bonus = 0.0
    for _, row in ipairs(GetHighValueWeightBonusRows()) do
        if row.level and M.level >= row.level then
            bonus = row.bonus or bonus
        end
    end
    return bonus
end

function M.ResetAll()
    M.level = 1
    M.xp = 0
    M.totalXp = 0
    M.runXp = 0
    M.lastLevelUp = nil
end

function M.ResetRun()
    M.runXp = 0
    M.lastLevelUp = nil
end

function M.ApplyMetaState(state)
    if not state then return end
    M.level = Clamp(math.floor(state.level or M.level or 1), 1, GetMaxLevel())
    M.xp = math.max(0, math.floor(state.xp or M.xp or 0))
    M.totalXp = math.max(0, math.floor(state.totalXp or M.totalXp or 0))
    M.runXp = 0
    M.lastLevelUp = nil
end

function M.AddXP(amount, source)
    amount = math.floor(math.max(0, amount or 0))

    local result = {
        xpGained = amount,
        source = source,
        leveledUp = false,
        oldLevel = M.level,
        newLevel = M.level,
        unlocks = {},
    }

    if amount <= 0 then
        return result
    end

    M.totalXp = M.totalXp + amount
    M.runXp = M.runXp + amount

    local maxLevel = GetMaxLevel()
    if M.level >= maxLevel then
        M.level = maxLevel
        M.xp = 0
        return result
    end

    M.xp = M.xp + amount

    while M.level < maxLevel do
        local xpToNext = GetXPToNextForLevel(M.level)
        if xpToNext <= 0 or M.xp < xpToNext then
            break
        end

        M.xp = M.xp - xpToNext
        M.level = M.level + 1
        result.leveledUp = true
        result.newLevel = M.level
    end

    if M.level >= maxLevel then
        M.level = maxLevel
        M.xp = 0
    end

    if result.leveledUp then
        AddUnlocksBetween(result.oldLevel, result.newLevel, result.unlocks)
        M.lastLevelUp = {
            oldLevel = result.oldLevel,
            newLevel = result.newLevel,
            unlocks = result.unlocks,
        }
        print("[Progression] Level up Lv." .. tostring(result.oldLevel) .. " -> Lv." .. tostring(result.newLevel))
    end

    return result
end

function M.OnOrderDelivered(order, result)
    local baseXp = order and order.xp or CONFIG.PROGRESSION_DEFAULT_ORDER_XP or 8
    local onTime = result and result.onTime == true
    local comboCount = result and result.comboCount or 0
    local totalXp = baseXp
    local onTimeXp = 0
    local comboXp = 0

    if onTime then
        local rate = CONFIG.PROGRESSION_ON_TIME_XP_RATE or 0.25
        onTimeXp = math.max(1, math.floor(baseXp * rate))
        local step = math.max(1, CONFIG.PROGRESSION_COMBO_XP_STEP or 2)
        local maxComboXp = math.max(0, CONFIG.PROGRESSION_COMBO_XP_MAX or 5)
        comboXp = math.min(maxComboXp, math.floor(math.max(0, comboCount) / step))
    end

    totalXp = totalXp + onTimeXp + comboXp

    local xpResult = M.AddXP(totalXp, "order:" .. tostring(order and order.typeId or "unknown"))
    xpResult.baseXp = baseXp
    xpResult.onTimeXp = onTimeXp
    xpResult.comboXp = comboXp
    return xpResult
end

function M.OnOrderFailed(order, reason)
    return {
        xpGained = 0,
        source = "order_failed:" .. tostring(reason or "unknown"),
        orderType = order and order.typeId or nil,
        leveledUp = false,
        oldLevel = M.level,
        newLevel = M.level,
        unlocks = {},
    }
end

function M.GetRiderLevel()
    return M.level
end

function M.GetCurrentXP()
    return M.xp
end

function M.GetXPToNext()
    return GetXPToNextForLevel(M.level)
end

function M.GetTitle()
    return GetTitleForLevel(M.level)
end

function M.GetHUDData()
    local maxLevel = GetMaxLevel()
    local xpToNext = GetXPToNextForLevel(M.level)
    local isMaxLevel = M.level >= maxLevel or xpToNext <= 0
    local progress = 1.0

    if not isMaxLevel then
        progress = Clamp(M.xp / math.max(1, xpToNext), 0.0, 1.0)
    end

    return {
        level = M.level,
        title = GetTitleForLevel(M.level),
        xp = M.xp,
        xpToNext = xpToNext,
        progress = progress,
        maxLevel = isMaxLevel,
        runXp = M.runXp,
        totalXp = M.totalXp,
        lastLevelUp = M.lastLevelUp,
    }
end

function M.GetMaxAvailableOrders()
    local count = CONFIG.ORDER_AVAILABLE_COUNT_DEFAULT or 2
    for _, row in ipairs(GetOrderCountUnlocks()) do
        if row.level and M.level >= row.level then
            count = row.count or count
        end
    end

    count = count + (meta.GetMaxActiveOrdersBonus and meta.GetMaxActiveOrdersBonus() or 0)
    local cap = CONFIG.ORDER_AVAILABLE_COUNT_MAX or count
    return Clamp(math.floor(count), 1, math.max(1, cap))
end

function M.GetOrderTypeUnlockLevel(typeId)
    local unlocks = GetOrderTypeUnlocks()
    return unlocks[typeId]
end

function M.IsOrderTypeUnlocked(typeId)
    local unlockLevel = M.GetOrderTypeUnlockLevel(typeId)
    if not unlockLevel then
        return typeId == "normal"
    end
    return M.level >= unlockLevel
end

function M.GetUnlockedOrderTypes()
    local list = {}
    local seen = {}

    for _, typeId in ipairs(GetOrderTypeOrder()) do
        if M.IsOrderTypeUnlocked(typeId) then
            list[#list + 1] = typeId
            seen[typeId] = true
        end
    end

    for typeId in pairs(GetOrderTypeUnlocks()) do
        if not seen[typeId] and M.IsOrderTypeUnlocked(typeId) then
            list[#list + 1] = typeId
        end
    end

    return list
end

function M.GetOrderWeightMultiplier(typeId)
    if not M.IsOrderTypeUnlocked(typeId) then
        return 0.0
    end

    if GetHighValueOrderTypes()[typeId] then
        return 1.0 + GetHighValueWeightBonus()
    end

    return 1.0
end

function M.DebugAddXP(amount)
    return M.AddXP(amount, "debug")
end

function M.DebugSetLevel(level)
    local maxLevel = GetMaxLevel()
    M.level = Clamp(math.floor(level or 1), 1, maxLevel)
    M.xp = 0
    M.lastLevelUp = nil
end

return M

