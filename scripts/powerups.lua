-- ============================================================================
-- 外卖冲冲冲 - 局内道具模块
-- ============================================================================
-- 第一阶段只实现护盾和闹钟：
--   护盾：主动使用后抵消一次正面碰撞。
--   闹钟：主动使用后给当前订单增加时间。
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local rn = require("road_network")
local mats = require("materials")
local player = require("player")

local M = {}

local SHADOW_Y = CONFIG.PLAYER_GROUND_Y + 0.012

M.pool = {}
M.activePowerups = {}
M.heldPowerup = nil
M.shieldCharges = 0
M.nextPowerupId = 1
M.nextSpawnDistance = 0.0
M.lastEdgeId = 0
M.lastEdgeDistance = 0.0
M.lastPlayerLaneX = CONFIG.LANE_X[CONFIG.currentLane] or 0.0
M.context = {}
M.eventSink = {}
M.message = nil
M.messageTimer = 0.0

local function HideNode(node)
    if node then
        node.position = Vector3(0, -100, 0)
    end
end

local function CreateContactShadow(scene, name)
    local shadow = scene:CreateChild(name)
    local model = shadow:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Cylinder.mdl")
    model.material = mats.shadow
    shadow.scale = Vector3(0.55, 0.012, 0.55)
    shadow.position = Vector3(0, -100, 0)
    return shadow
end

local function GetPowerupConfig(typeId)
    local types = CONFIG.POWERUP_TYPES or {}
    return types[typeId] or types.shield or {
        weight = 1,
        label = "?",
        name = "道具",
        color = "#FFFFFF",
    }
end

local function GetPowerupMaterial(typeId)
    if typeId == "clock" then
        return mats.powerupClock or mats.pickupAccent
    end
    return mats.powerupShield or mats.deliveryMarker
end

local function ShowMessage(text)
    M.message = text
    M.messageTimer = 1.4
end

local function ScheduleNextSpawn(fromDistance)
    local minInterval = CONFIG.POWERUP_SPAWN_INTERVAL_MIN or 80.0
    local maxInterval = CONFIG.POWERUP_SPAWN_INTERVAL_MAX or 130.0
    local range = math.max(0.0, maxInterval - minInterval)
    M.nextSpawnDistance = (fromDistance or player.distanceTraveled or 0.0) + minInterval + math.random() * range
end

local function PickPowerupType()
    local types = CONFIG.POWERUP_TYPES or {}
    local totalWeight = 0
    for _, data in pairs(types) do
        totalWeight = totalWeight + (data.weight or 1)
    end

    if totalWeight <= 0 then
        return "shield"
    end

    local roll = math.random() * totalWeight
    for typeId, data in pairs(types) do
        roll = roll - (data.weight or 1)
        if roll <= 0 then
            return typeId
        end
    end
    return "shield"
end

local function CreatePowerupVisual(scene, index)
    local node = scene:CreateChild("Powerup_" .. tostring(index))

    local base = node:CreateChild("Base")
    local baseModel = base:CreateComponent("StaticModel")
    baseModel.model = cache:GetResource("Model", "Models/Cylinder.mdl")
    baseModel.material = mats.powerupBase or mats.delivery
    base.scale = Vector3(0.58, 0.08, 0.58)
    base.position = Vector3(0, -0.28, 0)

    local core = node:CreateChild("Core")
    local coreModel = core:CreateComponent("StaticModel")
    coreModel.model = cache:GetResource("Model", "Models/Sphere.mdl")
    coreModel.material = mats.powerupShield or mats.deliveryMarker
    core.scale = Vector3(0.42, 0.42, 0.42)
    core.position = Vector3(0, 0.08, 0)

    local badge = node:CreateChild("Badge")
    local badgeModel = badge:CreateComponent("StaticModel")
    badgeModel.model = cache:GetResource("Model", "Models/Box.mdl")
    badgeModel.material = mats.powerupShield or mats.deliveryMarker
    badge.scale = Vector3(0.22, 0.22, 0.08)
    badge.position = Vector3(0, 0.55, 0)

    node.position = Vector3(0, -100, 0)
    return {
        node = node,
        core = core,
        coreModel = coreModel,
        badge = badge,
        badgeModel = badgeModel,
        shadow = CreateContactShadow(scene, "PowerupShadow_" .. tostring(index)),
        active = false,
        id = 0,
        typeId = "shield",
        edgeId = 0,
        edgeDist = 0.0,
        lane = 2,
    }
end

local function GetInactivePowerup()
    for _, item in ipairs(M.pool) do
        if not item.active then
            return item
        end
    end
    return nil
end

local function PositionPowerup(item)
    local edge = rn.GetEdge(item.edgeId)
    if not edge then return false end

    local laneX = CONFIG.LANE_X[item.lane] or 0.0
    local worldPos = rn.GetPositionOnEdgeByDist(edge, item.edgeDist, laneX)
    local yaw = rn.HeadingToYaw(edge.heading)
    local material = GetPowerupMaterial(item.typeId)

    if item.coreModel then
        item.coreModel.material = material
    end
    if item.badgeModel then
        item.badgeModel.material = material
    end

    item.node.position = Vector3(worldPos.x, 0.95, worldPos.z)
    item.node.rotation = Quaternion(yaw, Vector3.UP)

    if item.shadow then
        item.shadow.position = Vector3(worldPos.x, SHADOW_Y, worldPos.z)
        item.shadow.rotation = Quaternion(yaw, Vector3.UP)
    end
    return true
end

local function HidePowerup(item)
    if not item then return end
    HideNode(item.node)
    HideNode(item.shadow)
    item.active = false
end

local function WasTargetSwept(edgeId, targetDist, longitudinalThreshold)
    local s = path.state
    if not s.currentEdge then return false end

    longitudinalThreshold = longitudinalThreshold or CONFIG.POWERUP_PICKUP_LONGITUDINAL_THRESHOLD or 2.2
    local currentDist = s.edgeDistance or 0.0
    local currentEdgeId = s.currentEdge.id
    if currentEdgeId ~= edgeId then
        if M.lastEdgeId ~= edgeId then return false end
        local edge = rn.GetEdge(edgeId)
        local endDist = edge and rn.GetEdgeEffectiveLength(edge) or currentDist
        return targetDist >= (M.lastEdgeDistance or 0.0) - longitudinalThreshold
            and targetDist <= endDist + longitudinalThreshold
    elseif M.lastEdgeId ~= edgeId then
        return math.abs(currentDist - targetDist) <= longitudinalThreshold
    end

    local fromDist = math.min(M.lastEdgeDistance or currentDist, currentDist)
    local toDist = math.max(M.lastEdgeDistance or currentDist, currentDist)
    return targetDist >= fromDist - longitudinalThreshold
        and targetDist <= toDist + longitudinalThreshold
end

local function IsPlayerNearLane(lane, lateralThreshold)
    local targetX = CONFIG.LANE_X[lane]
    if not targetX then return false end

    local playerX = player.currentLaneX or CONFIG.LANE_X[CONFIG.currentLane]
    local lastPlayerX = M.lastPlayerLaneX or playerX or 0.0
    local minX = math.min(lastPlayerX, playerX or lastPlayerX)
    local maxX = math.max(lastPlayerX, playerX or lastPlayerX)
    lateralThreshold = lateralThreshold or CONFIG.POWERUP_PICKUP_LATERAL_THRESHOLD or 1.15
    return targetX >= minX - lateralThreshold and targetX <= maxX + lateralThreshold
end

local function IsSpotNearOrder(edgeId, edgeDist, lane)
    if M.context and M.context.isNearOrderPoint then
        return M.context.isNearOrderPoint(edgeId, edgeDist, lane)
    end
    return false
end

local function IsSpawnSpotValid(edge, edgeDist, lane)
    if not edge then return false end

    local effectiveLen = rn.GetEdgeEffectiveLength(edge)
    local minDist = CONFIG.POWERUP_EDGE_START_BUFFER or 18.0
    local maxDist = effectiveLen - (CONFIG.POWERUP_EDGE_END_BUFFER or 18.0)
    if edgeDist < minDist or edgeDist > maxDist then return false end
    if IsSpotNearOrder(edge.id, edgeDist, lane) then return false end
    if M.IsNearPowerupPoint(edge.id, edgeDist, lane) then return false end
    return true
end

local function SpawnOnCurrentEdge()
    local s = path.state
    if not s.currentEdge or s.insideIntersection then return false end

    local edge = s.currentEdge
    local aheadMin = CONFIG.POWERUP_SPAWN_AHEAD_MIN or 35.0
    local aheadMax = CONFIG.POWERUP_SPAWN_AHEAD_MAX or 95.0
    local edgeLen = rn.GetEdgeEffectiveLength(edge)
    local lane = math.random(1, 3)
    local spawnDist = (s.edgeDistance or 0.0) + aheadMin + math.random() * math.max(0.0, aheadMax - aheadMin)

    if spawnDist > edgeLen - (CONFIG.POWERUP_EDGE_END_BUFFER or 18.0) then
        return false
    end
    if not IsSpawnSpotValid(edge, spawnDist, lane) then
        return false
    end

    local item = GetInactivePowerup()
    if not item then return false end

    item.id = M.nextPowerupId
    M.nextPowerupId = M.nextPowerupId + 1
    item.typeId = PickPowerupType()
    item.edgeId = edge.id
    item.edgeDist = spawnDist
    item.lane = lane
    item.active = true

    if not PositionPowerup(item) then
        HidePowerup(item)
        return false
    end

    M.activePowerups[#M.activePowerups + 1] = item
    return true
end

local function RemoveActivePowerupAt(index)
    local item = M.activePowerups[index]
    if item then
        HidePowerup(item)
        table.remove(M.activePowerups, index)
    end
    return item
end

local function UseShield()
    M.heldPowerup = nil
    M.shieldCharges = 1
    ShowMessage("护盾已启动")
    if M.eventSink and M.eventSink.onPowerupUsed then
        M.eventSink.onPowerupUsed("shield")
    end
    return true
end

local function UseClock()
    if not M.context or not M.context.hasActiveOrder or not M.context.hasActiveOrder() then
        ShowMessage("当前没有订单")
        return false
    end

    local seconds = CONFIG.POWERUP_CLOCK_ADD_SECONDS or 6.0
    if M.context.addOrderTime and M.context.addOrderTime(seconds) then
        M.heldPowerup = nil
        ShowMessage("订单时间 +" .. tostring(math.floor(seconds)) .. "s")
        if M.eventSink and M.eventSink.onPowerupUsed then
            M.eventSink.onPowerupUsed("clock")
        end
        return true
    end

    ShowMessage("当前没有订单")
    return false
end

function M.Init(scene)
    M.pool = {}
    M.activePowerups = {}
    local poolSize = CONFIG.POWERUP_POOL_SIZE or 8
    for i = 1, poolSize do
        M.pool[i] = CreatePowerupVisual(scene, i)
    end
end

function M.SetUseContext(context)
    M.context = context or {}
end

function M.SetEventSink(eventSink)
    M.eventSink = eventSink or {}
end

function M.CapturePathSnapshot()
    local s = path.state
    if s and s.currentEdge then
        M.lastEdgeId = s.currentEdge.id
        M.lastEdgeDistance = s.edgeDistance or 0.0
    else
        M.lastEdgeId = 0
        M.lastEdgeDistance = 0.0
    end
    M.lastPlayerLaneX = player.currentLaneX or CONFIG.LANE_X[CONFIG.currentLane] or 0.0
end

function M.Spawn()
    if #M.activePowerups > 0 then return end
    if (player.distanceTraveled or 0.0) < (M.nextSpawnDistance or 0.0) then return end

    if SpawnOnCurrentEdge() then
        ScheduleNextSpawn(player.distanceTraveled or 0.0)
    else
        M.nextSpawnDistance = (player.distanceTraveled or 0.0) + 12.0
    end
end

function M.CheckPickup()
    for i = #M.activePowerups, 1, -1 do
        local item = M.activePowerups[i]
        local hit = WasTargetSwept(
            item.edgeId,
            item.edgeDist,
            CONFIG.POWERUP_PICKUP_LONGITUDINAL_THRESHOLD or 2.2
        ) and IsPlayerNearLane(item.lane, CONFIG.POWERUP_PICKUP_LATERAL_THRESHOLD or 1.15)

        if hit then
            local data = GetPowerupConfig(item.typeId)
            local typeId = item.typeId
            M.heldPowerup = typeId
            RemoveActivePowerupAt(i)
            ShowMessage("获得" .. (data.name or "道具"))
            if M.eventSink and M.eventSink.onPowerupPicked then
                M.eventSink.onPowerupPicked(typeId)
            end
            return true
        end
    end
    return false
end

function M.Recycle()
    local s = path.state
    if not s.currentEdge then return end

    for i = #M.activePowerups, 1, -1 do
        local item = M.activePowerups[i]
        local shouldRemove = false
        if item.edgeId ~= s.currentEdge.id then
            shouldRemove = true
        elseif (item.edgeDist or 0.0) < (s.edgeDistance or 0.0) - (CONFIG.POWERUP_RECYCLE_BEHIND_DISTANCE or 30.0) then
            shouldRemove = true
        end

        if shouldRemove then
            RemoveActivePowerupAt(i)
        end
    end
end

function M.Update(dt)
    if M.messageTimer > 0.0 then
        M.messageTimer = math.max(0.0, M.messageTimer - (dt or 0.0))
        if M.messageTimer <= 0.0 then
            M.message = nil
        end
    end

    for _, item in ipairs(M.activePowerups) do
        if item.active and item.node then
            local pos = item.node.position
            item.node.position = Vector3(pos.x, 0.95 + math.sin(time.elapsedTime * 3.4 + item.id) * 0.18, pos.z)
            if item.shadow then
                item.shadow.scale = Vector3(0.55, 0.012, 0.55)
            end
        end
    end
end

function M.UseCurrent()
    if not M.heldPowerup then
        ShowMessage("无道具")
        return false
    end

    if M.heldPowerup == "shield" then
        return UseShield()
    elseif M.heldPowerup == "clock" then
        return UseClock()
    end

    ShowMessage("暂不可用")
    return false
end

function M.HasShield()
    return (M.shieldCharges or 0) > 0
end

function M.ConsumeShield()
    if not M.HasShield() then return false end

    M.shieldCharges = M.shieldCharges - 1
    ShowMessage("护盾抵消碰撞")
    if M.eventSink and M.eventSink.onShieldConsumed then
        M.eventSink.onShieldConsumed()
    end
    return true
end

function M.IsNearPowerupPoint(edgeId, edgeDist, lane)
    local clearance = CONFIG.POWERUP_OBSTACLE_CLEARANCE or 10.0
    for _, item in ipairs(M.activePowerups) do
        if item.active and item.edgeId == edgeId and item.lane == lane then
            if math.abs((item.edgeDist or 0.0) - edgeDist) < clearance then
                return true
            end
        end
    end
    return false
end

function M.GetHUDData()
    local heldData = M.heldPowerup and GetPowerupConfig(M.heldPowerup) or nil
    local readyText = "无道具"
    if heldData then
        readyText = "E " .. (heldData.name or "道具")
    elseif M.HasShield() then
        readyText = "护盾中"
    end

    return {
        held = M.heldPowerup ~= nil,
        id = M.heldPowerup,
        name = heldData and heldData.name or nil,
        label = heldData and heldData.label or nil,
        readyText = readyText,
        shieldActive = M.HasShield(),
        message = M.messageTimer > 0.0 and M.message or nil,
    }
end

function M.GetMinimapData()
    return {
        active = false,
    }
end

function M.Reset()
    for _, item in ipairs(M.pool) do
        HidePowerup(item)
    end
    M.activePowerups = {}
    M.heldPowerup = nil
    M.shieldCharges = 0
    M.nextPowerupId = 1
    M.message = nil
    M.messageTimer = 0.0
    if path.state then
        M.CapturePathSnapshot()
    end
    M.nextSpawnDistance = (player.distanceTraveled or 0.0) + (CONFIG.POWERUP_INITIAL_SPAWN_DISTANCE or 60.0)
end

return M
