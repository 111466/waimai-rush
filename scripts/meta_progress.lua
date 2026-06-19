-- ============================================================================
-- 外卖冲冲冲 - 局外成长与本地存档模块
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG

local M = {}

local SAVE_DIR = "save"
local SAVE_PATH = SAVE_DIR .. "/meta_progress.json"

local DEFAULT_SETTINGS = {
    sound = true,
    music = true,
    vibration = true,
    controlMode = "混合",
    debugPanel = false,
}

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

local TASK_DEFS = {
    { id = "task_first_run", name = "完成首局配送", metric = "totalRuns", target = 1, coins = 50, xp = 0 },
    { id = "task_run_three", name = "单局送达 3 单", metric = "bestDeliveries", target = 3, coins = 80, xp = 10 },
    { id = "task_ontime_two", name = "单局准时 2 单", metric = "bestOnTimeDeliveries", target = 2, coins = 80, xp = 10 },
    { id = "task_combo_three", name = "最高连击达到 3", metric = "bestCombo", target = 3, coins = 100, xp = 12 },
    { id = "task_income_120", name = "单局收入达到 ¥120", metric = "bestIncome", target = 120, coins = 120, xp = 15 },
    { id = "task_total_20", name = "累计送达 20 单", metric = "totalDeliveries", target = 20, coins = 180, xp = 20 },
}

local ACHIEVEMENT_DEFS = {
    { id = "ach_first_order", name = "完成首单", metric = "totalDeliveries", target = 1, coins = 100, xp = 10 },
    { id = "ach_total_50", name = "累计完成 50 单", metric = "totalDeliveries", target = 50, coins = 300, xp = 30 },
    { id = "ach_ontime_30", name = "累计准时 30 单", metric = "totalOnTimeDeliveries", target = 30, coins = 260, xp = 28 },
    { id = "ach_runs_10", name = "累计跑单 10 局", metric = "totalRuns", target = 10, coins = 180, xp = 20 },
    { id = "ach_combo_8", name = "最高连击达到 8", metric = "bestCombo", target = 8, coins = 240, xp = 26 },
    { id = "ach_income_300", name = "单局收入达到 ¥300", metric = "bestIncome", target = 300, coins = 300, xp = 32 },
    { id = "ach_distance_5000", name = "累计骑行 5000m", metric = "totalDistance", target = 5000, coins = 350, xp = 35 },
    { id = "ach_rush_20", name = "累计完成 20 个急送单", metric = "orderType", typeId = "rush", target = 20, coins = 400, xp = 40 },
}

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
        bestOnTimeDeliveries = 0,
        bestCombo = 0,
        bestIncome = 0,
        deliveredOrderTypes = {},
        claimedTasks = {},
        claimedAchievements = {},
        settings = CloneTable(DEFAULT_SETTINGS),
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
            if type(data[key]) ~= "table" then
                data[key] = CloneTable(value)
            else
                for subKey, subValue in pairs(value) do
                    if data[key][subKey] == nil then
                        data[key][subKey] = subValue
                    end
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

local function EnsureProgressTables()
    if type(M.data.deliveredOrderTypes) ~= "table" then
        M.data.deliveredOrderTypes = {}
    end
    if type(M.data.claimedTasks) ~= "table" then
        M.data.claimedTasks = {}
    end
    if type(M.data.claimedAchievements) ~= "table" then
        M.data.claimedAchievements = {}
    end
end

local function GetMetricValue(def)
    if not def then return 0 end
    if def.metric == "orderType" then
        EnsureProgressTables()
        return M.data.deliveredOrderTypes[def.typeId] or 0
    end
    return M.data[def.metric] or 0
end

local function BuildProgressRows(defs, claimedTable)
    EnsureProgressTables()
    local rows = {}
    for _, def in ipairs(defs or {}) do
        local current = math.max(0, math.floor(GetMetricValue(def)))
        local target = math.max(1, math.floor(def.target or 1))
        local done = current >= target
        local claimed = claimedTable and claimedTable[def.id] == true
        rows[#rows + 1] = {
            id = def.id,
            name = def.name,
            current = current,
            target = target,
            done = done,
            claimed = claimed,
            coins = def.coins or 0,
            xp = def.xp or 0,
        }
    end
    return rows
end

local function ApplyClaimReward(def)
    local coins = math.max(0, math.floor(def.coins or 0))
    local xp = math.max(0, math.floor(def.xp or 0))
    M.data.coins = math.floor(math.max(0, (M.data.coins or 0) + coins))

    local xpResult = nil
    if xp > 0 then
        local progression = require("progression")
        progression.ApplyMetaState(M.GetRiderState())
        xpResult = progression.AddXP(xp, "claim:" .. tostring(def.id))
        local hud = progression.GetHUDData()
        M.data.riderLevel = hud.level or M.data.riderLevel or 1
        M.data.riderXp = hud.xp or M.data.riderXp or 0
        M.data.totalXp = hud.totalXp or M.data.totalXp or 0
    end

    return {
        coins = coins,
        xp = xp,
        xpResult = xpResult,
    }
end

local function ClaimFromList(defs, claimedTable, id)
    EnsureProgressTables()
    for _, def in ipairs(defs or {}) do
        if def.id == id then
            if claimedTable[def.id] then
                return false, "奖励已领取"
            end
            local current = GetMetricValue(def)
            if current < (def.target or 1) then
                return false, "目标未完成"
            end
            claimedTable[def.id] = true
            local reward = ApplyClaimReward(def)
            M.Save()
            return true, "领取 " .. def.name .. "  ¥" .. tostring(reward.coins) .. " / XP " .. tostring(reward.xp)
        end
    end
    return false, "目标不存在"
end

local function ClaimAvailableFromList(defs, claimedTable)
    EnsureProgressTables()
    local claimedCount = 0
    local totalCoins = 0
    local totalXp = 0

    for _, def in ipairs(defs or {}) do
        if not claimedTable[def.id] and GetMetricValue(def) >= (def.target or 1) then
            claimedTable[def.id] = true
            local reward = ApplyClaimReward(def)
            claimedCount = claimedCount + 1
            totalCoins = totalCoins + (reward.coins or 0)
            totalXp = totalXp + (reward.xp or 0)
        end
    end

    if claimedCount <= 0 then
        return false, "没有可领取奖励"
    end

    M.Save()
    return true, "领取 " .. tostring(claimedCount) .. " 项奖励  ¥" .. tostring(totalCoins) .. " / XP " .. tostring(totalXp)
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
        totalDistance = M.data.totalDistance or 0,
        bestDeliveries = M.data.bestDeliveries or 0,
        bestOnTimeDeliveries = M.data.bestOnTimeDeliveries or 0,
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
    M.data.bestOnTimeDeliveries = math.max(M.data.bestOnTimeDeliveries or 0, onTimeDeliveries)
    M.data.bestCombo = math.max(M.data.bestCombo or 0, bestCombo)
    M.data.bestIncome = math.max(M.data.bestIncome or 0, income)
    EnsureProgressTables()
    for typeId, count in pairs(runStats.orderTypeCounts or {}) do
        M.data.deliveredOrderTypes[typeId] = (M.data.deliveredOrderTypes[typeId] or 0) + math.floor(math.max(0, count or 0))
    end

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
        orderTypeCounts = CloneTable(runStats.orderTypeCounts or {}),
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

function M.GetTaskRows()
    EnsureProgressTables()
    return BuildProgressRows(TASK_DEFS, M.data.claimedTasks)
end

function M.GetAchievementRows()
    EnsureProgressTables()
    return BuildProgressRows(ACHIEVEMENT_DEFS, M.data.claimedAchievements)
end

function M.ClaimTask(id)
    EnsureProgressTables()
    return ClaimFromList(TASK_DEFS, M.data.claimedTasks, id)
end

function M.ClaimAchievement(id)
    EnsureProgressTables()
    return ClaimFromList(ACHIEVEMENT_DEFS, M.data.claimedAchievements, id)
end

function M.ClaimAvailableTasks()
    EnsureProgressTables()
    return ClaimAvailableFromList(TASK_DEFS, M.data.claimedTasks)
end

function M.ClaimAvailableAchievements()
    EnsureProgressTables()
    return ClaimAvailableFromList(ACHIEVEMENT_DEFS, M.data.claimedAchievements)
end

function M.GetDeliveredOrderTypeCount(typeId)
    EnsureProgressTables()
    return M.data.deliveredOrderTypes[typeId] or 0
end

function M.GetLastRunResult()
    return M.lastRunResult
end

function M.GetSettings()
    if type(M.data.settings) ~= "table" then
        M.data.settings = CloneTable(DEFAULT_SETTINGS)
    end
    for key, value in pairs(DEFAULT_SETTINGS) do
        if M.data.settings[key] == nil then
            M.data.settings[key] = value
        end
    end
    return CloneTable(M.data.settings)
end

function M.ToggleSetting(key)
    if type(M.data.settings) ~= "table" then
        M.data.settings = CloneTable(DEFAULT_SETTINGS)
    end
    if type(M.data.settings[key]) ~= "boolean" then
        return false, "设置项不可切换"
    end
    M.data.settings[key] = not M.data.settings[key]
    M.Save()
    return true, M.data.settings[key]
end

function M.CycleControlMode()
    local modes = {"混合", "滑动", "键盘"}
    if type(M.data.settings) ~= "table" then
        M.data.settings = CloneTable(DEFAULT_SETTINGS)
    end
    local current = M.data.settings.controlMode or DEFAULT_SETTINGS.controlMode
    local nextIndex = 1
    for i, mode in ipairs(modes) do
        if mode == current then
            nextIndex = i + 1
            break
        end
    end
    if nextIndex > #modes then
        nextIndex = 1
    end
    M.data.settings.controlMode = modes[nextIndex]
    M.Save()
    return M.data.settings.controlMode
end

return M
