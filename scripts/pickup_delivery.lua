-- ============================================================================
-- 外卖冲冲冲 - 取件/送件模块
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local mats = require("materials")

local M = {}

-- 状态
M.pickupNode = nil
M.pickupActive = false
M.pickupPathDist = 0.0
M.pickupLane = 2
M.lastPickupDist = 0.0
M.nextPickupDist = 0.0

M.deliveryNode = nil
M.deliveryActive = false
M.deliveryPathDist = 0.0
M.deliveryLane = 2
M.lastDeliveryDist = 0.0
M.nextDeliveryDist = 0.0

M.hasPackage = false
M.packageVisualNode = nil

-- 计分
M.timeRemaining = 30.0
M.totalIncome = 0
M.comboCount = 0

function M.CreatePickupNode(scene)
    local node = scene:CreateChild("Pickup")
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.pickup
    node.scale = Vector3(0.8, 0.8, 0.8)
    node.position = Vector3(0, -100, 0)
    M.pickupNode = node
    return node
end

function M.CreateDeliveryNode(scene)
    local node = scene:CreateChild("Delivery")
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.delivery
    node.scale = Vector3(1.0, 0.3, 1.0)
    node.position = Vector3(0, -100, 0)
    M.deliveryNode = node
    return node
end

function M.TrySpawnPickup()
    local s = path.state
    if s.turnExecuting then return end
    if M.pickupActive or M.hasPackage then return end
    if s.routeDistance < M.nextPickupDist then return end

    local spawnDist = s.routeDistance + CONFIG.PICKUP_SPAWN_AHEAD
    if path.IsInSafeZone(spawnDist) then return end

    local lane = math.random(1, 3)
    M.pickupPathDist = spawnDist
    M.pickupLane = lane
    M.pickupActive = true

    local laneX = CONFIG.LANE_X[lane]
    local worldPos = path.GetWorldPosForObject(spawnDist, laneX)
    M.pickupNode.position = Vector3(worldPos.x, 0.6, worldPos.z)
    M.pickupNode.rotation = Quaternion(path.HeadingToYaw(s.currentHeading), Vector3.UP)

    M.lastPickupDist = spawnDist
    M.nextPickupDist = spawnDist + CONFIG.PICKUP_INTERVAL_MIN + math.random() * (CONFIG.PICKUP_INTERVAL_MAX - CONFIG.PICKUP_INTERVAL_MIN)
end

function M.CheckPickup()
    if not M.pickupActive then return end
    local s = path.state
    local distDiff = s.routeDistance - M.pickupPathDist
    if math.abs(distDiff) < CONFIG.COLLISION_Z_THRESHOLD and CONFIG.currentLane == M.pickupLane then
        M.hasPackage = true
        M.pickupActive = false
        M.pickupNode.position = Vector3(0, -100, 0)
        if M.packageVisualNode then
            M.packageVisualNode.enabled = true
        end
        M.nextDeliveryDist = s.routeDistance + CONFIG.DELIVERY_INTERVAL_MIN * 0.5
    elseif distDiff > 3.0 then
        M.pickupActive = false
        M.pickupNode.position = Vector3(0, -100, 0)
    end
end

function M.TrySpawnDelivery()
    local s = path.state
    if s.turnExecuting then return end
    if M.deliveryActive or not M.hasPackage then return end
    if s.routeDistance < M.nextDeliveryDist then return end

    local spawnDist = s.routeDistance + CONFIG.DELIVERY_SPAWN_AHEAD
    if path.IsInSafeZone(spawnDist) then return end

    local lane = math.random(1, 3)
    M.deliveryPathDist = spawnDist
    M.deliveryLane = lane
    M.deliveryActive = true

    local laneX = CONFIG.LANE_X[lane]
    local worldPos = path.GetWorldPosForObject(spawnDist, laneX)
    M.deliveryNode.position = Vector3(worldPos.x, 0.15, worldPos.z)
    M.deliveryNode.rotation = Quaternion(path.HeadingToYaw(s.currentHeading), Vector3.UP)

    M.lastDeliveryDist = spawnDist
    M.nextDeliveryDist = spawnDist + CONFIG.DELIVERY_INTERVAL_MIN + math.random() * (CONFIG.DELIVERY_INTERVAL_MAX - CONFIG.DELIVERY_INTERVAL_MIN)

    s.intersectionCorrectDir = (lane <= 1) and -1 or ((lane >= 3) and 1 or 0)
end

function M.CheckDelivery()
    if not M.deliveryActive then return end
    local s = path.state
    local distDiff = s.routeDistance - M.deliveryPathDist
    if math.abs(distDiff) < CONFIG.COLLISION_Z_THRESHOLD and CONFIG.currentLane == M.deliveryLane then
        M.comboCount = M.comboCount + 1
        local baseReward = 10
        local comboBonus = math.floor(M.comboCount * CONFIG.DELIVERY_COMBO_MULTIPLIER)
        local reward = baseReward + comboBonus
        M.totalIncome = M.totalIncome + reward
        M.timeRemaining = M.timeRemaining + 3.0

        M.hasPackage = false
        M.deliveryActive = false
        M.deliveryNode.position = Vector3(0, -100, 0)
        if M.packageVisualNode then
            M.packageVisualNode.enabled = false
        end
    elseif distDiff > 3.0 then
        M.comboCount = 0
        M.deliveryActive = false
        M.deliveryNode.position = Vector3(0, -100, 0)
    end
end

function M.UpdateAnimation()
    if M.pickupActive and M.pickupNode then
        M.pickupNode.position = Vector3(M.pickupNode.position.x, 0.6 + math.sin(time.elapsedTime * 3.0) * 0.2, M.pickupNode.position.z)
    end
    if M.deliveryActive and M.deliveryNode then
        M.deliveryNode.position = Vector3(M.deliveryNode.position.x, 0.15 + math.sin(time.elapsedTime * 2.5) * 0.1, M.deliveryNode.position.z)
    end
end

function M.Reset()
    local s = path.state
    M.pickupActive = false
    M.pickupNode.position = Vector3(0, -100, 0)
    M.deliveryActive = false
    M.deliveryNode.position = Vector3(0, -100, 0)
    M.hasPackage = false
    if M.packageVisualNode then M.packageVisualNode.enabled = false end
    M.lastPickupDist = 0.0
    M.nextPickupDist = 30.0
    M.lastDeliveryDist = 0.0
    M.nextDeliveryDist = 100.0
    M.timeRemaining = 30.0
    M.totalIncome = 0
    M.comboCount = 0
end

return M
