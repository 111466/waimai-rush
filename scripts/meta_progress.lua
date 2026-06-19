-- ============================================================================
-- 外卖冲冲冲 - 局外成长与本地存档模块
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG

local M = {}

local SAVE_DIR = "save"
local SAVE_PATH = SAVE_DIR .. "/meta_progress.json"

local UPGRADE_DEFS = {
    rewardBonusLevel = {
        name = "配送奖励",
        desc = "每级 +5% 收入",
        maxLevel = 10,
        costs = {100, 200, 350, 500, 700, 950, 1250, 1600, 2000, 2500},
    },
    powerupDurationLevel = {
        name = "道具时长",
        desc = "闹钟每级 +0.5s",
        maxLevel = 10,
        costs = {100, 200, 350, 500, 700, 950, 1250, 1600, 2000, 2500},
    },
    maxOrdersLevel = {
        name = "接单上限",
        desc = "每级 +1 个取餐点",
        maxLevel = 3,
        costs = {300, 600, 1000},
    },
}

local UPGRADE_ORDER = {"rewardBonusLevel", "powerupDurationLevel", "maxOrdersLevel"}

local function CloneTable(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            copy[key] = CloneTable(value)
        else
            copy[key] = value
        end
    end
    return copy
end

local function CreateDefaultData()
    return {
        version = 1,
        riderLevel = 1,
        riderXp = 0,
        totalXp = 0,
        coins = 0,
        totalRuns = 0,
        totalDeliveries = 0,
        totalOnTimeDeliveries = 0,
        totalDistance = 0,
        bestDeliveries = 0,
        bestCombo = 0,
        bestIncome = 0,
        upgrades = {
            rewardBonusLevel = 0,
            powerupDurationLevel = 0,
            maxOrdersLevel = 0,
        },
    }
end

M.data = CreateDefaultData()
M.lastRunResult = nil

local function MergeDefaults(data)
    local defaults = CreateDefaultData()
    data = data or {}
    for key, value in pairs(defaults) do
        if data[key] == nil then
            data[key] = CloneTable(value)
        elseif type(value) == "table" then
            for subKey, subValue in pairs(value) do
                if data[key][subKey] == nil then
                    data[key][subKey] = subValue
                end
            end
        end
    end
    return data
end

local function GetJson()
    if cjson then
        return cjson
    end
    local ok, json = pcall(require, "cjson")
    if ok then
        return json
    end
    return nil
end

local function GetRiderTitle(level)
    local rows = CONFIG.RIDER_LEVELS or {}
    for _, row in ipairs(rows) do
        if row.level == level then
            return row.title or "骑手"
        end
    end
    return "骑手"
end

local function GetUpgradeLevel(key)
    local upgrades = M.data.upgrades or {}
    return math.max(0, math.floor(upgrades[key] or 0))
end

local function GetUpgradeCost(key)
    local def = UPGRADE_DEFS[key]
    if not def then return nil end
    local level = GetUpgradeLevel(key)
    if level >= def.maxLevel then return nil end
    return def.costs[level + 1] or (100 * (level + 1) * (level + 1))
end

function M.Load()
    M.data = CreateDefaultData()
    if not fileSystem or not fileSystem:FileExists(SAVE_PATH) then
        print("[MetaProgress] No save found, using defaults")
        return false
    end

    local file = File(SAVE_PATH, FILE_READ)
    if not file or not file:IsOpen() then
        print("[MetaProgress] Failed to open save")
        return false
    end

    local text = file:ReadString()
    file:Close()

    local json = GetJson()
    if not json then
        print("[MetaProgress] cjson unavailable")
        return false
    end

    local ok, data = pcall(json.decode, text)
    if ok and type(data) == "table" then
        M.data = MergeDefaults(data)
        print("[MetaProgress] Loaded save Lv." .. tostring(M.data.riderLevel) .. " coins " .. tostring(M.data.coins))
        return true
    end

    print("[MetaProgress] Save decode failed, using defaults")
    return false
end

function M.Save()
    local json = GetJson()
    if not json then
        print("[MetaProgress] cjson unavailable, save skipped")
        return false
    end

    if fileSystem then
        fileSystem:CreateDir(SAVE_DIR)
    end

    local file = File(SAVE_PATH, FILE_WRITE)
    if not file or not file:IsOpen() then
        print("[MetaProgress] Failed to write save")
        return false
    end

    file:WriteString(json.encode(M.data))
    file:Close()
    return true
end

function M.GetData()
    return M.data
end

function M.GetRiderState()
    return {
        level = M.data.riderLevel or 1,
        xp = M.data.riderXp or 0,
        totalXp = M.data.totalXp or 0,
    }
end

function M.GetSummary()
    local level = M.data.riderLevel or 1
    return {
        riderLevel = level,
        riderTitle = GetRiderTitle(level),
        riderXp = M.data.riderXp or 0,
        totalXp = M.data.totalXp or 0,
        coins = M.data.coins or 0,
        totalRuns = M.data.totalRuns or 0,
        totalDeliveries = M.data.totalDeliveries or 0,
        totalOnTimeDeliveries = M.data.totalOnTimeDeliveries or 0,
        bestDeliveries = M.data.bestDeliveries or 0,
        bestCombo = M.data.bestCombo or 0,
        bestIncome = M.data.bestIncome or 0,
        rewardBonusPercent = math.floor((M.GetRewardMultiplier() - 1.0) * 100 + 0.5),
        powerupDurationBonus = M.GetPowerupDurationBonus(),
        maxOrdersBonus = M.GetMaxActiveOrdersBonus(),
    }
end

function M.ApplyRunResult(runStats, progressBefore, progressAfter)
    runStats = runStats or {}
    progressBefore = progressBefore or {}
    progressAfter = progressAfter or progressBefore

    local income = math.floor(math.max(0, runStats.income or 0))
    local deliveries = math.floor(math.max(0, runStats.deliveries or 0))
    local onTimeDeliveries = math.floor(math.max(0, runStats.onTimeDeliveries or 0))
    local bestCombo = math.floor(math.max(0, runStats.bestCombo or 0))
    local distance = math.floor(math.max(0, runStats.distance or 0))
    local xpEarned = math.floor(math.max(0, (progressAfter.runXp or 0) - (progressBefore.runXp or 0)))
    if xpEarned <= 0 then
        xpEarned = math.floor(math.max(0, progressAfter.runXp or 0))
    end

    M.data.riderLevel = progressAfter.level or M.data.riderLevel or 1
    M.data.riderXp = progressAfter.xp or M.data.riderXp or 0
    M.data.totalXp = progressAfter.totalXp or M.data.totalXp or 0
    M.data.coins = math.floor(math.max(0, (M.data.coins or 0) + income))
    M.data.totalRuns = (M.data.totalRuns or 0) + 1
    M.data.totalDeliveries = (M.data.totalDeliveries or 0) + deliveries
    M.data.totalOnTimeDeliveries = (M.data.totalOnTimeDeliveries or 0) + onTimeDeliveries
    M.data.totalDistance = math.floor((M.data.totalDistance or 0) + distance)
    M.data.bestDeliveries = math.max(M.data.bestDeliveries or 0, deliveries)
    M.data.bestCombo = math.max(M.data.bestCombo or 0, bestCombo)
    M.data.bestIncome = math.max(M.data.bestIncome or 0, income)

    local result = {
        coinsEarned = income,
        xpEarned = xpEarned,
        deliveries = deliveries,
        onTimeDeliveries = onTimeDeliveries,
        bestCombo = bestCombo,
        distance = distance,
        income = income,
        levelBefore = progressBefore.level or M.data.riderLevel,
        levelAfter = progressAfter.level or M.data.riderLevel,
        xpBefore = progressBefore.xp or 0,
        xpAfter = progressAfter.xp or M.data.riderXp or 0,
        xpToNext = progressAfter.xpToNext or 0,
        leveledUp = (progressAfter.level or 1) > (progressBefore.level or 1),
        unlocks = progressAfter.lastLevelUp and progressAfter.lastLevelUp.unlocks or {},
        totalCoins = M.data.coins,
    }

    M.lastRunResult = result
    M.Save()
    return result
end

function M.TryUpgrade(key)
    local def = UPGRADE_DEFS[key]
    if not def then
        return false, "升级项不存在"
    end

    M.data.upgrades = M.data.upgrades or {}
    local level = GetUpgradeLevel(key)
    if level >= def.maxLevel then
        return false, "已达到最高等级"
    end

    local cost = GetUpgradeCost(key) or 0
    if (M.data.coins or 0) < cost then
        return false, "金币不足，需要 ¥" .. tostring(cost)
    end

    M.data.coins = (M.data.coins or 0) - cost
    M.data.upgrades[key] = level + 1
    M.Save()
    return true, def.name .. "提升到 Lv." .. tostring(level + 1)
end

function M.GetRewardMultiplier()
    return 1.0 + GetUpgradeLevel("rewardBonusLevel") * 0.05
end

function M.GetPowerupDurationBonus()
    return GetUpgradeLevel("powerupDurationLevel") * 0.5
end

function M.GetMaxActiveOrdersBonus()
    return GetUpgradeLevel("maxOrdersLevel")
end

function M.GetUpgradeRows()
    local rows = {
        "金币: ¥" .. tostring(M.data.coins or 0),
    }

    for _, key in ipairs(UPGRADE_ORDER) do
        local def = UPGRADE_DEFS[key]
        local level = GetUpgradeLevel(key)
        local cost = GetUpgradeCost(key)
        local suffix = cost and ("  升级 ¥" .. tostring(cost)) or "  已满级"
        rows[#rows + 1] = def.name .. " Lv." .. tostring(level) .. "/" .. tostring(def.maxLevel) .. "  " .. def.desc .. suffix
    end

    rows[#rows + 1] = "加成会在下一局和当前订单结算中生效"
    return rows
end

function M.GetUpgradeKeys()
    return UPGRADE_ORDER
end

function M.GetUpgradeName(key)
    local def = UPGRADE_DEFS[key]
    return def and def.name or key
end

return M
