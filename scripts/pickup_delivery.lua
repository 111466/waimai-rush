-- ============================================================================
-- 外卖冲冲冲 - 多订单取餐/送达模块
-- ============================================================================
-- 第一版多订单流程：
--   1. 地图上同时保留多个可接取餐点。
--   2. 玩家驶过某个取餐点即接下该订单。
--   3. 只有当前接取订单会生成送达目标和导航路线。
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local rn = require("road_network")
local mats = require("materials")
local nav = require("route_navigation")
local player = require("player")
local progression = require("progression")
local meta = require("meta_progress")

local M = {}

local SHADOW_Y = CONFIG.PLAYER_GROUND_Y + 0.012
local DELIVERY_LATERAL_THRESHOLD = 0.85

local ORDER_TYPES = {
    {
        id = "normal",
        label = "普",
        name = "普通",
        reward = 12,
        xp = 8,
        weight = 42,
        minHops = 2,
        maxHops = 4,
        timeFactor = CONFIG.ORDER_TIME_ROUTE_FACTOR,
        timeExtra = CONFIG.ORDER_TIME_EXTRA_SECONDS,
        latePenaltyMultiplier = 1.0,
        color = "#2DD4BF",
        labelColor = {45, 212, 191, 255},
    },
    {
        id = "rush",
        label = "急",
        name = "急送",
        reward = 16,
        xp = 12,
        weight = 20,
        minHops = 1,
        maxHops = 3,
        timeFactor = 1.05,
        timeExtra = 2.0,
        latePenaltyMultiplier = 1.8,
        color = "#FF8C2A",
        labelColor = {255, 140, 42, 255},
    },
    {
        id = "long",
        label = "远",
        name = "远距",
        reward = 18,
        xp = 14,
        weight = 18,
        minHops = 3,
        maxHops = 5,
        timeFactor = 1.45,
        timeExtra = 6.0,
        latePenaltyMultiplier = 1.0,
        color = "#F6D743",
        labelColor = {246, 215, 67, 255},
    },
    {
        id = "nearby",
        label = "顺",
        name = "顺路",
        reward = 8,
        xp = 6,
        weight = 15,
        minHops = 1,
        maxHops = 2,
        timeFactor = CONFIG.ORDER_TIME_ROUTE_FACTOR,
        timeExtra = CONFIG.ORDER_TIME_EXTRA_SECONDS,
        latePenaltyMultiplier = 0.8,
        color = "#4ADE80",
        labelColor = {74, 222, 128, 255},
    },
    {
        id = "fragile",
        label = "碎",
        name = "易碎",
        reward = 15,
        xp = 12,
        weight = 5,
        minHops = 2,
        maxHops = 4,
        timeFactor = 1.3,
        timeExtra = 4.0,
        latePenaltyMultiplier = 1.2,
        fragile = true,
        color = "#60A5FA",
        labelColor = {96, 165, 250, 255},
    },
}

local ORDER_TYPE_BY_ID = {}
for _, orderType in ipairs(ORDER_TYPES) do
    ORDER_TYPE_BY_ID[orderType.id] = orderType
end

local function CreateContactShadow(scene, name, scaleX, scaleZ)
    local shadow = scene:CreateChild(name)
    local model = shadow:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Cylinder.mdl")
    model.material = mats.shadow
    shadow.scale = Vector3(scaleX, 0.012, scaleZ)
    shadow.position = Vector3(0, -100, 0)
    return shadow
end

local function HideNode(node)
    if node then
        node.position = Vector3(0, -100, 0)
    end
end

local function PlaceShadow(node, worldPos, yaw)
    if node then
        node.position = Vector3(worldPos.x, SHADOW_Y, worldPos.z)
        node.rotation = Quaternion(yaw, Vector3.UP)
    end
end

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function Shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(1, i)
        list[i], list[j] = list[j], list[i]
    end
end

-- 旧单订单字段保持同步，便于旧调用方和调试面板继续读取。
M.pickupNode = nil
M.pickupShadowNode = nil
M.pickupActive = false
M.pickupEdgeId = 0
M.pickupEdgeDist = 0.0
M.pickupLane = 2
M.lastPickupEdgeId = 0
M.firstPickupPending = true
M.nextPickupDistance = 0.0

M.deliveryNode = nil
M.deliveryShadowNode = nil
M.deliveryActive = false
M.deliveryEdgeId = 0
M.deliveryEdgeDist = 0.0
M.deliveryLane = 2
M.lastDeliveryEdgeId = 0
M.nextDeliveryDistance = 0.0

M.hasPackage = false
M.packageVisualNode = nil

M.totalIncome = 0
M.comboCount = 0
M.runDeliveries = 0
M.runOnTimeDeliveries = 0
M.runBestCombo = 0

M.orderTimerActive = false
M.orderTimeLimit = 0.0
M.orderTimeRemaining = 0.0
M.orderLateSeconds = 0.0
M.lastEdgeId = 0
M.lastEdgeDistance = 0.0
M.lastPlayerLaneX = CONFIG.LANE_X[CONFIG.currentLane] or 0.0

M.pickupNodes = {}
M.pickupShadowNodes = {}
M.availableOrders = {}
M.activeOrder = nil
M.nextOrderId = 1

local function GetMaxOrderCount()
    return math.max(1, CONFIG.ORDER_AVAILABLE_COUNT_MAX or 5)
end

local function GetTargetOrderCount()
    local count = progression.GetMaxAvailableOrders()
    return Clamp(math.floor(count), 1, GetMaxOrderCount())
end

local function GetOrderType(typeId)
    return ORDER_TYPE_BY_ID[typeId] or ORDER_TYPES[1]
end

local function PickOrderType()
    local totalWeight = 0
    for _, orderType in ipairs(ORDER_TYPES) do
        local multiplier = progression.GetOrderWeightMultiplier(orderType.id)
        if multiplier > 0.0 then
            totalWeight = totalWeight + (orderType.weight or 1) * multiplier
        end
    end

    if totalWeight <= 0.0 then
        return ORDER_TYPE_BY_ID.normal or ORDER_TYPES[1]
    end

    local roll = math.random() * totalWeight
    for _, orderType in ipairs(ORDER_TYPES) do
        local multiplier = progression.GetOrderWeightMultiplier(orderType.id)
        if multiplier > 0.0 then
            roll = roll - (orderType.weight or 1) * multiplier
            if roll <= 0 then
                return orderType
            end
        end
    end
    return ORDER_TYPE_BY_ID.normal or ORDER_TYPES[1]
end

local function SyncLegacyPickupFields()
    local order = M.availableOrders[1]
    if order and not M.hasPackage then
        M.pickupActive = true
        M.pickupEdgeId = order.pickupEdgeId
        M.pickupEdgeDist = order.pickupEdgeDist
        M.pickupLane = order.pickupLane
    else
        M.pickupActive = false
        M.pickupEdgeId = 0
        M.pickupEdgeDist = 0.0
        M.pickupLane = 2
    end
end

local function CreatePickupVisual(scene, index)
    local node = scene:CreateChild("Pickup_" .. index)

    local bag = node:CreateChild("Bag")
    local bagModel = bag:CreateComponent("StaticModel")
    bagModel.model = cache:GetResource("Model", "Models/Box.mdl")
    bagModel.material = mats.pickup
    bag.scale = Vector3(0.8, 0.75, 0.55)
    bag.position = Vector3(0, 0, 0)

    local flap = node:CreateChild("BagFlap")
    local flapModel = flap:CreateComponent("StaticModel")
    flapModel.model = cache:GetResource("Model", "Models/Box.mdl")
    flapModel.material = mats.pickupAccent
    flap.scale = Vector3(0.62, 0.08, 0.58)
    flap.position = Vector3(0, 0.42, 0)

    local handleLeft = node:CreateChild("HandleLeft")
    local handleLeftModel = handleLeft:CreateComponent("StaticModel")
    handleLeftModel.model = cache:GetResource("Model", "Models/Box.mdl")
    handleLeftModel.material = mats.pickupHandle
    handleLeft.scale = Vector3(0.08, 0.34, 0.08)
    handleLeft.position = Vector3(-0.22, 0.66, 0)

    local handleRight = node:CreateChild("HandleRight")
    local handleRightModel = handleRight:CreateComponent("StaticModel")
    handleRightModel.model = cache:GetResource("Model", "Models/Box.mdl")
    handleRightModel.material = mats.pickupHandle
    handleRight.scale = Vector3(0.08, 0.34, 0.08)
    handleRight.position = Vector3(0.22, 0.66, 0)

    local handleTop = node:CreateChild("HandleTop")
    local handleTopModel = handleTop:CreateComponent("StaticModel")
    handleTopModel.model = cache:GetResource("Model", "Models/Box.mdl")
    handleTopModel.material = mats.pickupHandle
    handleTop.scale = Vector3(0.52, 0.08, 0.08)
    handleTop.position = Vector3(0, 0.83, 0)

    node.position = Vector3(0, -100, 0)
    return node
end

function M.CreatePickupNode(scene)
    M.pickupNodes = {}
    M.pickupShadowNodes = {}

    for i = 1, GetMaxOrderCount() do
        local node = CreatePickupVisual(scene, i)
        local shadow = CreateContactShadow(scene, "PickupShadow_" .. i, 0.62, 0.46)
        M.pickupNodes[i] = node
        M.pickupShadowNodes[i] = shadow
    end

    M.pickupNode = M.pickupNodes[1]
    M.pickupShadowNode = M.pickupShadowNodes[1]
    return M.pickupNode
end

function M.CreateDeliveryNode(scene)
    local node = scene:CreateChild("Delivery")

    local pad = node:CreateChild("DeliveryPad")
    local padModel = pad:CreateComponent("StaticModel")
    padModel.model = cache:GetResource("Model", "Models/Cylinder.mdl")
    padModel.material = mats.delivery
    pad.scale = Vector3(0.85, 0.08, 0.85)
    pad.position = Vector3(0, 0, 0)

    local ring = node:CreateChild("DeliveryRing")
    local ringModel = ring:CreateComponent("StaticModel")
    ringModel.model = cache:GetResource("Model", "Models/Cylinder.mdl")
    ringModel.material = mats.deliveryAccent
    ring.scale = Vector3(1.05, 0.03, 1.05)
    ring.position = Vector3(0, 0.08, 0)

    local stem = node:CreateChild("DeliveryStem")
    local stemModel = stem:CreateComponent("StaticModel")
    stemModel.model = cache:GetResource("Model", "Models/Box.mdl")
    stemModel.material = mats.deliveryAccent
    stem.scale = Vector3(0.12, 0.8, 0.12)
    stem.position = Vector3(0, 0.52, 0)

    local marker = node:CreateChild("DeliveryMarker")
    local markerModel = marker:CreateComponent("StaticModel")
    markerModel.model = cache:GetResource("Model", "Models/Sphere.mdl")
    markerModel.material = mats.deliveryMarker
    marker.scale = Vector3(0.34, 0.34, 0.34)
    marker.position = Vector3(0, 1.05, 0)

    M.deliveryShadowNode = CreateContactShadow(scene, "DeliveryShadow", 0.66, 0.66)
    node.position = Vector3(0, -100, 0)
    M.deliveryNode = node
    return node
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
    M.lastPlayerLaneX = player and player.currentLaneX or CONFIG.LANE_X[CONFIG.currentLane] or 0.0
end

local function WasTargetSwept(edgeId, targetDist, longitudinalThreshold)
    local s = path.state
    if not s.currentEdge then return false end

    longitudinalThreshold = longitudinalThreshold or CONFIG.COLLISION_Z_THRESHOLD or 1.0
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

    local playerX = player and player.currentLaneX or CONFIG.LANE_X[CONFIG.currentLane]
    local lastPlayerX = M.lastPlayerLaneX or playerX or 0.0
    local minX = math.min(lastPlayerX, playerX or lastPlayerX)
    local maxX = math.max(lastPlayerX, playerX or lastPlayerX)
    lateralThreshold = lateralThreshold or DELIVERY_LATERAL_THRESHOLD
    return targetX >= minX - lateralThreshold and targetX <= maxX + lateralThreshold
end

local function StopOrderTimer()
    M.orderTimerActive = false
    M.orderTimeLimit = 0.0
    M.orderTimeRemaining = 0.0
    M.orderLateSeconds = 0.0
end

local function StartOrderTimer(order, routeDistance, currentSpeed)
    local orderType = GetOrderType(order and order.typeId)
    local safeSpeed = math.max(1.0, currentSpeed or CONFIG.BASE_SPEED)
    local estimatedTime = (routeDistance or 0.0) / safeSpeed
    local factor = orderType.timeFactor or CONFIG.ORDER_TIME_ROUTE_FACTOR
    local extra = orderType.timeExtra or CONFIG.ORDER_TIME_EXTRA_SECONDS
    local limit = estimatedTime * factor + extra

    M.orderTimeLimit = Clamp(limit, CONFIG.ORDER_TIME_MIN_SECONDS, CONFIG.ORDER_TIME_MAX_SECONDS)
    M.orderTimeRemaining = M.orderTimeLimit
    M.orderLateSeconds = 0.0
    M.orderTimerActive = true
end

local function HideDeliveryNode()
    HideNode(M.deliveryNode)
    HideNode(M.deliveryShadowNode)
end

local function ClearDeliveryTarget()
    M.deliveryActive = false
    M.deliveryEdgeId = 0
    M.deliveryEdgeDist = 0.0
    M.deliveryLane = 2
    HideDeliveryNode()
    nav.ClearTarget()
    StopOrderTimer()
end

local function HidePickupOrderVisual(order)
    if not order then return end
    if order.nodeIndex then
        HideNode(M.pickupNodes[order.nodeIndex])
        HideNode(M.pickupShadowNodes[order.nodeIndex])
    end
    order.nodeIndex = nil
end

local function FindFreePickupNodeIndex()
    local used = {}
    for _, order in ipairs(M.availableOrders) do
        if order.nodeIndex then
            used[order.nodeIndex] = true
        end
    end

    for i = 1, GetMaxOrderCount() do
        if not used[i] then
            return i
        end
    end
    return nil
end

local function PlacePickupOrderVisual(order)
    if not order then return end
    if M.hasPackage then
        HidePickupOrderVisual(order)
        return
    end

    local edge = rn.GetEdge(order.pickupEdgeId)
    if not edge then
        HidePickupOrderVisual(order)
        return
    end

    if not order.nodeIndex then
        order.nodeIndex = FindFreePickupNodeIndex()
    end
    if not order.nodeIndex then return end

    local node = M.pickupNodes[order.nodeIndex]
    local shadow = M.pickupShadowNodes[order.nodeIndex]
    if not node then return end

    local laneX = CONFIG.LANE_X[order.pickupLane]
    local worldPos = rn.GetPositionOnEdgeByDist(edge, order.pickupEdgeDist, laneX)
    local yaw = rn.HeadingToYaw(edge.heading)
    node.position = Vector3(worldPos.x, 0.6, worldPos.z)
    node.rotation = Quaternion(yaw, Vector3.UP)
    PlaceShadow(shadow, worldPos, yaw)
end

local function RefreshPickupVisuals()
    for _, order in ipairs(M.availableOrders) do
        PlacePickupOrderVisual(order)
    end
end

local function EstimateRouteDistance(route, startDist, targetDist)
    if not route or #route == 0 then return 0.0 end

    local distance = 0.0
    for i, edgeId in ipairs(route) do
        local edge = rn.GetEdge(edgeId)
        if edge then
            local effectiveLen = rn.GetEdgeEffectiveLength(edge)
            if #route == 1 then
                distance = distance + math.max(0.0, (targetDist or 0.0) - (startDist or 0.0))
            elseif i == 1 then
                distance = distance + math.max(0.0, effectiveLen - (startDist or 0.0))
            elseif i == #route then
                distance = distance + Clamp(targetDist or 0.0, 0.0, effectiveLen)
            else
                distance = distance + effectiveLen
            end
        end
    end
    return distance
end

local function IsOrderSlotUsed(slot)
    if not slot then return false end
    for _, order in ipairs(M.availableOrders) do
        if order.pickupSlot == slot then
            return true
        end
    end
    return false
end

local function GetPickupWorldPoint(edgeId, edgeDist, lane)
    local edge = rn.GetEdge(edgeId)
    if not edge then return nil end

    local laneOffset = 0.0
    if lane and CONFIG.LANE_X then
        laneOffset = CONFIG.LANE_X[lane] or 0.0
    end
    return rn.GetPositionOnEdgeByDist(edge, edgeDist or 0.0, laneOffset)
end

local function IsPickupWorldTooClose(edgeId, edgeDist, lane)
    local minWorldGap = CONFIG.ORDER_PICKUP_MIN_WORLD_DISTANCE or 0.0
    if minWorldGap <= 0.0 then return false end

    local pos = GetPickupWorldPoint(edgeId, edgeDist, lane)
    if not pos then return false end

    local minSq = minWorldGap * minWorldGap
    for _, order in ipairs(M.availableOrders) do
        local otherPos = GetPickupWorldPoint(order.pickupEdgeId, order.pickupEdgeDist, order.pickupLane)
        if otherPos then
            local dx = pos.x - otherPos.x
            local dz = pos.z - otherPos.z
            if dx * dx + dz * dz < minSq then
                return true
            end
        end
    end

    return false
end

local function IsPickupSpotReserved(edgeId, edgeDist, lane)
    local minGap = CONFIG.ORDER_PICKUP_MIN_DISTANCE_BETWEEN or 36.0
    for _, order in ipairs(M.availableOrders) do
        if order.pickupEdgeId == edgeId and math.abs((order.pickupEdgeDist or 0.0) - edgeDist) < minGap then
            return true
        end
    end
    return IsPickupWorldTooClose(edgeId, edgeDist, lane)
end

local function IsDeliverySpotReserved(edgeId, edgeDist, lane)
    local minGap = CONFIG.OBSTACLE_ORDER_CLEARANCE or 10.0
    if M.deliveryActive and M.deliveryEdgeId == edgeId and M.deliveryLane == lane then
        if math.abs((M.deliveryEdgeDist or 0.0) - edgeDist) < minGap then
            return true
        end
    end
    return false
end

local function IsPickupCandidateValid(edge, edgeDist)
    if not edge then return false end

    local effectiveLen = rn.GetEdgeEffectiveLength(edge)
    local minDist = CONFIG.ORDER_EDGE_START_BUFFER
    local maxDist = effectiveLen - CONFIG.ORDER_EDGE_END_BUFFER
    if edgeDist < minDist or edgeDist > maxDist then return false end

    local slot = nav.MakeEdgeSlot(edge)
    if IsOrderSlotUsed(slot) then return false end
    if IsPickupSpotReserved(edge.id, edgeDist) then return false end
    return true
end

local function AddPickupCandidate(candidates, edge, edgeDist)
    if IsPickupCandidateValid(edge, edgeDist) then
        candidates[#candidates + 1] = {
            edge = edge,
            edgeId = edge.id,
            edgeDist = edgeDist,
        }
    end
end

local function BuildPickupCandidates()
    local s = path.state
    local candidates = {}
    if not s.currentEdge or s.insideIntersection then
        return candidates
    end

    local currentEdge = s.currentEdge
    local currentLen = rn.GetEdgeEffectiveLength(currentEdge)
    local aheadMin = CONFIG.ORDER_PICKUP_SPAWN_AHEAD_MIN or 30.0
    local aheadMax = CONFIG.ORDER_PICKUP_SPAWN_AHEAD_MAX or 110.0
    local aheadRange = math.max(1.0, aheadMax - aheadMin)

    for _ = 1, 4 do
        local spawnDist = (s.edgeDistance or 0.0) + aheadMin + math.random() * aheadRange
        if spawnDist < currentLen then
            AddPickupCandidate(candidates, currentEdge, spawnDist)
        end
    end

    local minHops = CONFIG.ORDER_PICKUP_REACHABLE_MIN_HOPS or 1
    local maxHops = CONFIG.ORDER_PICKUP_REACHABLE_MAX_HOPS or 3
    local reachable = nav.GetReachableTargetEdges(currentEdge, minHops, maxHops)
    Shuffle(reachable)

    for _, item in ipairs(reachable) do
        local edge = item.edge
        if edge then
            local effectiveLen = rn.GetEdgeEffectiveLength(edge)
            local minDist = CONFIG.ORDER_EDGE_START_BUFFER
            local maxDist = effectiveLen - CONFIG.ORDER_EDGE_END_BUFFER
            if maxDist > minDist then
                AddPickupCandidate(candidates, edge, minDist + math.random() * (maxDist - minDist))
            end
        end
    end

    Shuffle(candidates)
    return candidates
end

local function SelectDeliveryForOrder(orderType, pickupEdge, pickupDist)
    if not pickupEdge then return nil end

    local candidates = nav.GetReachableTargetEdges(
        pickupEdge,
        orderType.minHops or CONFIG.DELIVERY_TARGET_MIN_HOPS or 2,
        orderType.maxHops or CONFIG.DELIVERY_TARGET_MAX_HOPS or 4
    )

    if #candidates == 0 then
        candidates = nav.GetReachableTargetEdges(pickupEdge, 1, 8) or {}
    end

    Shuffle(candidates)
    for _, candidate in ipairs(candidates) do
        local edge = candidate.edge
        if edge then
            local effectiveLen = rn.GetEdgeEffectiveLength(edge)
            local minDist = CONFIG.ORDER_EDGE_START_BUFFER
            local maxDist = effectiveLen - CONFIG.ORDER_EDGE_END_BUFFER
            if maxDist > minDist then
                local targetDist = minDist + math.random() * (maxDist - minDist)
                local lane = math.random(1, 3)
                if not IsDeliverySpotReserved(edge.id, targetDist, lane) then
                    local route = candidate.route or nav.FindRouteFromEdge(pickupEdge, edge.id)
                    local distance = EstimateRouteDistance(route, pickupDist, targetDist)
                    return {
                        edgeId = edge.id,
                        edgeDist = targetDist,
                        lane = lane,
                        route = route,
                        distance = distance,
                        slot = nav.MakeEdgeSlot(edge),
                    }
                end
            end
        end
    end

    return nil
end

local function BuildOrderFromPickupCandidate(candidate)
    if not candidate or not candidate.edge then return nil end

    local orderType = PickOrderType()
    local lane = math.random(1, 3)
    if IsPickupSpotReserved(candidate.edgeId, candidate.edgeDist, lane) then
        return nil
    end

    local delivery = SelectDeliveryForOrder(orderType, candidate.edge, candidate.edgeDist)
    if not delivery then
        return nil
    end

    local id = M.nextOrderId
    M.nextOrderId = M.nextOrderId + 1

    return {
        id = id,
        typeId = orderType.id,
        label = orderType.label,
        name = orderType.name,
        reward = orderType.reward,
        xp = orderType.xp or CONFIG.PROGRESSION_DEFAULT_ORDER_XP or 8,
        fragile = orderType.fragile == true,
        color = orderType.color,
        markerColor = orderType.color,
        labelColor = orderType.labelColor,
        displayText = orderType.label .. "/" .. tostring(orderType.reward) .. "￥",
        pickupEdgeId = candidate.edgeId,
        pickupEdgeDist = candidate.edgeDist,
        pickupLane = lane,
        pickupSlot = nav.MakeEdgeSlot(candidate.edge),
        deliveryEdgeId = delivery.edgeId,
        deliveryEdgeDist = delivery.edgeDist,
        deliveryLane = delivery.lane,
        deliverySlot = delivery.slot,
        route = delivery.route,
        routeDistance = delivery.distance,
    }
end

local function GenerateOneOrder()
    local attempts = CONFIG.ORDER_PICKUP_MAX_ATTEMPTS or 24
    for _ = 1, attempts do
        local candidates = BuildPickupCandidates()
        for _, candidate in ipairs(candidates) do
            local order = BuildOrderFromPickupCandidate(candidate)
            if order then
                return order
            end
        end
    end
    return nil
end

local function RemoveAvailableOrderAt(index)
    local order = M.availableOrders[index]
    if order then
        HidePickupOrderVisual(order)
        table.remove(M.availableOrders, index)
    end
    SyncLegacyPickupFields()
    return order
end

local function ShouldRecycleOrder(order)
    if not order then return true end
    if not rn.GetEdge(order.pickupEdgeId) then return true end
    if not rn.GetEdge(order.deliveryEdgeId) then return true end

    local s = path.state
    if s.currentEdge and order.pickupEdgeId == s.currentEdge.id then
        local behind = CONFIG.ORDER_RECYCLE_BEHIND_DISTANCE or 45.0
        if (order.pickupEdgeDist or 0.0) < (s.edgeDistance or 0.0) - behind then
            return true
        end
    elseif CONFIG.ORDER_RECYCLE_UNREACHABLE and s.currentEdge and not nav.FindRouteFromEdge(s.currentEdge, order.pickupEdgeId) then
        return true
    end

    return false
end

local function RecycleInvalidOrders()
    for i = #M.availableOrders, 1, -1 do
        if ShouldRecycleOrder(M.availableOrders[i]) then
            RemoveAvailableOrderAt(i)
        end
    end
end

local function FillAvailableOrders()
    if M.hasPackage then
        RefreshPickupVisuals()
        SyncLegacyPickupFields()
        return
    end

    local targetCount = GetTargetOrderCount()
    while #M.availableOrders < targetCount do
        local order = GenerateOneOrder()
        if not order then
            break
        end
        M.availableOrders[#M.availableOrders + 1] = order
        PlacePickupOrderVisual(order)
        print("[Order] Available " .. order.displayText ..
            " pickup edge " .. order.pickupEdgeId ..
            " -> delivery edge " .. order.deliveryEdgeId)
    end

    RefreshPickupVisuals()
    SyncLegacyPickupFields()
end

local function PlaceDeliveryForOrder(order)
    if not order or not M.deliveryNode then return false end

    local edge = rn.GetEdge(order.deliveryEdgeId)
    if not edge then return false end

    M.deliveryEdgeId = order.deliveryEdgeId
    M.deliveryEdgeDist = order.deliveryEdgeDist
    M.deliveryLane = order.deliveryLane
    M.deliveryActive = true

    local laneX = CONFIG.LANE_X[M.deliveryLane]
    local worldPos = rn.GetPositionOnEdgeByDist(edge, M.deliveryEdgeDist, laneX)
    local yaw = rn.HeadingToYaw(edge.heading)
    M.deliveryNode.position = Vector3(worldPos.x, 0.15, worldPos.z)
    M.deliveryNode.rotation = Quaternion(yaw, Vector3.UP)
    PlaceShadow(M.deliveryShadowNode, worldPos, yaw)
    return true
end

local function ActivateDeliveryTarget(order, currentSpeed)
    if not order then return false end
    if not rn.GetEdge(order.deliveryEdgeId) then return false end

    local s = path.state
    if not nav.SetTarget(order.deliveryEdgeId, order.deliveryEdgeDist, s, order.deliveryLane) then
        return false
    end

    if not PlaceDeliveryForOrder(order) then
        nav.ClearTarget()
        return false
    end

    local routeDistance = nav.distanceRemaining
    if not routeDistance or routeDistance <= 0.0 then
        routeDistance = order.routeDistance or 0.0
    end
    StartOrderTimer(order, routeDistance, currentSpeed)

    M.lastDeliveryEdgeId = order.deliveryEdgeId
    M.nextDeliveryDistance = (s.totalDistance or 0.0) + CONFIG.DELIVERY_INTERVAL_MIN
    print("[Delivery] Active order " .. order.displayText ..
        " target edge " .. order.deliveryEdgeId ..
        " limit " .. string.format("%.1f", M.orderTimeLimit) .. "s")
    return true
end

local function AssignNewDeliveryForActiveOrder(currentSpeed)
    local order = M.activeOrder
    local s = path.state
    if not order or not s.currentEdge then return false end

    local orderType = GetOrderType(order.typeId)
    local delivery = SelectDeliveryForOrder(orderType, s.currentEdge, s.edgeDistance or 0.0)
    if not delivery then
        return false
    end

    order.deliveryEdgeId = delivery.edgeId
    order.deliveryEdgeDist = delivery.edgeDist
    order.deliveryLane = delivery.lane
    order.deliverySlot = delivery.slot
    order.route = delivery.route
    order.routeDistance = delivery.distance

    return ActivateDeliveryTarget(order, currentSpeed)
end

local function AcceptOrderAt(index)
    local order = RemoveAvailableOrderAt(index)
    if not order then return false end

    M.activeOrder = order
    M.hasPackage = true
    if M.packageVisualNode then
        M.packageVisualNode.enabled = true
    end

    RefreshPickupVisuals()
    M.nextDeliveryDistance = path.state.totalDistance or 0.0

    if not ActivateDeliveryTarget(order, player.currentSpeed) then
        AssignNewDeliveryForActiveOrder(player.currentSpeed)
    end

    print("[Pickup] Accepted " .. order.displayText .. " order")
    SyncLegacyPickupFields()
    return true
end

local function FinishActiveOrder()
    M.activeOrder = nil
    M.hasPackage = false
    if M.packageVisualNode then
        M.packageVisualNode.enabled = false
    end
    ClearDeliveryTarget()
    if CONFIG.ORDER_REFRESH_ON_DELIVERY then
        RecycleInvalidOrders()
        FillAvailableOrders()
    end
    SyncLegacyPickupFields()
end

local function FailActiveOrder(reason)
    if M.activeOrder then
        print("[Order] Failed " .. M.activeOrder.displayText .. " reason " .. (reason or "unknown"))
        progression.OnOrderFailed(M.activeOrder, reason)
    end
    M.comboCount = 0
    FinishActiveOrder()
end

-- 兼容旧主循环命名：这里实际负责补齐可接订单列表。
function M.TrySpawnPickup()
    RecycleInvalidOrders()
    FillAvailableOrders()
end

function M.CheckPickup()
    if M.hasPackage then return end

    local s = path.state
    if not s.currentEdge then return end

    for i = #M.availableOrders, 1, -1 do
        local order = M.availableOrders[i]
        local hit = WasTargetSwept(
            order.pickupEdgeId,
            order.pickupEdgeDist,
            CONFIG.ORDER_PICKUP_LONGITUDINAL_THRESHOLD or CONFIG.COLLISION_Z_THRESHOLD
        ) and IsPlayerNearLane(order.pickupLane, CONFIG.ORDER_PICKUP_LATERAL_THRESHOLD or 1.15)
        if hit then
            AcceptOrderAt(i)
            return
        end
    end
end

function M.TrySpawnDelivery(currentSpeed)
    if M.deliveryActive or not M.hasPackage or not M.activeOrder then return end
    if not path.state.currentEdge then return end

    if (path.state.totalDistance or 0.0) < (M.nextDeliveryDistance or 0.0) then
        return
    end

    if not ActivateDeliveryTarget(M.activeOrder, currentSpeed) then
        AssignNewDeliveryForActiveOrder(currentSpeed)
    end
end

function M.EnsureDeliveryTargetValid()
    if not M.deliveryActive then return true end
    if rn.GetEdge(M.deliveryEdgeId) then return true end

    ClearDeliveryTarget()
    if M.hasPackage then
        M.nextDeliveryDistance = path.state.totalDistance or 0.0
    end
    return false
end

function M.ReselectDeliveryTarget(currentSpeed)
    if not M.hasPackage or not M.activeOrder then return false end

    ClearDeliveryTarget()
    if AssignNewDeliveryForActiveOrder(currentSpeed) then
        print("[Delivery] Reselected reachable target")
        return true
    end

    M.nextDeliveryDistance = path.state.totalDistance or 0.0
    return false
end

function M.CheckDelivery()
    if not M.deliveryActive or not M.activeOrder then return end
    local s = path.state
    if not s.currentEdge then return end

    local targetDist = M.deliveryEdgeDist or 0.0
    local hit = WasTargetSwept(M.deliveryEdgeId, targetDist, CONFIG.COLLISION_Z_THRESHOLD)
        and IsPlayerNearLane(M.deliveryLane, DELIVERY_LATERAL_THRESHOLD)

    if not hit and M.deliveryEdgeId ~= s.currentEdge.id then
        return
    end

    local distDiff = (s.edgeDistance or 0.0) - targetDist
    if hit then
        local order = M.activeOrder
        local orderType = GetOrderType(order.typeId)
        local baseReward = math.floor((order.reward or orderType.reward or 10) * (meta.GetRewardMultiplier and meta.GetRewardMultiplier() or 1.0))
        local reward = baseReward

        local onTime = M.orderLateSeconds <= 0.0
        local lateSeconds = M.orderLateSeconds

        if not onTime then
            local penaltyRate = (CONFIG.ORDER_LATE_PENALTY_PER_SEC or 2) * (orderType.latePenaltyMultiplier or 1.0)
            reward = math.max(0, baseReward - math.floor(lateSeconds * penaltyRate))
            M.comboCount = 0
        else
            M.comboCount = M.comboCount + 1
            local comboBonus = math.floor(M.comboCount * CONFIG.DELIVERY_COMBO_MULTIPLIER)
            reward = baseReward + comboBonus
        end

        local xpResult = progression.OnOrderDelivered(order, {
            onTime = onTime,
            lateSeconds = lateSeconds,
            comboCount = M.comboCount,
            reward = reward,
        })

        M.runDeliveries = (M.runDeliveries or 0) + 1
        if onTime then
            M.runOnTimeDeliveries = (M.runOnTimeDeliveries or 0) + 1
        end
        M.runOrderTypeCounts = M.runOrderTypeCounts or {}
        M.runOrderTypeCounts[order.typeId] = (M.runOrderTypeCounts[order.typeId] or 0) + 1
        M.runBestCombo = math.max(M.runBestCombo or 0, M.comboCount or 0)
        M.totalIncome = M.totalIncome + reward
        print("[Delivery] Delivered " .. order.displayText ..
            "! Income " .. reward ..
            " XP " .. tostring(xpResult.xpGained or 0) ..
            " (combo x" .. M.comboCount .. ")")
        FinishActiveOrder()
    elseif distDiff > 3.0 then
        FailActiveOrder("missed delivery")
        M.nextPickupDistance = (s.totalDistance or 0.0) + CONFIG.PICKUP_INTERVAL_MIN * 0.5
    end
end

function M.UpdateOrderTimer(dt)
    if not M.orderTimerActive then return end

    M.orderTimeRemaining = M.orderTimeRemaining - (dt or 0.0)
    M.orderLateSeconds = math.max(0.0, -M.orderTimeRemaining)
end

function M.HasActiveOrder()
    return M.activeOrder ~= nil and M.orderTimerActive
end

function M.AddOrderTime(seconds)
    if not M.orderTimerActive then return false end

    M.orderTimeRemaining = M.orderTimeRemaining + (seconds or 0.0)
    M.orderLateSeconds = math.max(0.0, -M.orderTimeRemaining)
    return true
end

function M.GetOrderTimerData()
    if not M.orderTimerActive then
        return {
            active = false,
            state = "waiting",
            text = "等待订单",
            remaining = 0.0,
            lateSeconds = 0.0,
        }
    end

    local orderName = M.activeOrder and M.activeOrder.name or "订单"
    if M.orderTimeRemaining >= 0.0 then
        local displaySeconds = math.max(1, math.ceil(M.orderTimeRemaining))
        local state = "normal"
        if M.orderTimeRemaining <= CONFIG.ORDER_TIME_WARNING_SECONDS then
            state = "warning"
        end
        return {
            active = true,
            state = state,
            text = orderName .. " " .. displaySeconds .. "s",
            remaining = M.orderTimeRemaining,
            lateSeconds = 0.0,
        }
    end

    local lateSeconds = math.max(1, math.ceil(M.orderLateSeconds))
    return {
        active = true,
        state = "late",
        text = "迟到 " .. lateSeconds .. "s",
        remaining = M.orderTimeRemaining,
        lateSeconds = M.orderLateSeconds,
    }
end

function M.GetOrderTypeRows()
    local rows = {}
    for _, orderType in ipairs(ORDER_TYPES) do
        rows[#rows + 1] = {
            id = orderType.id,
            label = orderType.label,
            name = orderType.name,
            reward = orderType.reward,
            xp = orderType.xp or CONFIG.PROGRESSION_DEFAULT_ORDER_XP or 8,
            minHops = orderType.minHops,
            maxHops = orderType.maxHops,
            timeFactor = orderType.timeFactor,
            timeExtra = orderType.timeExtra,
            latePenaltyMultiplier = orderType.latePenaltyMultiplier,
            fragile = orderType.fragile == true,
            color = orderType.color,
        }
    end
    return rows
end

function M.GetMinimapData()
    local orders = {}

    if not M.hasPackage then
        for _, order in ipairs(M.availableOrders) do
            local edge = rn.GetEdge(order.pickupEdgeId)
            local slot = edge and nav.MakeEdgeSlot(edge) or nil
            if slot then
                orders[#orders + 1] = {
                    id = order.id,
                    slot = slot,
                    edgeId = order.pickupEdgeId,
                    edgeDist = order.pickupEdgeDist,
                    lane = order.pickupLane,
                    label = order.label,
                    reward = order.reward,
                    displayText = order.displayText,
                    typeId = order.typeId,
                    color = order.color,
                    markerColor = order.markerColor,
                    labelColor = order.labelColor,
                }
            end
        end
    end

    return {
        active = #orders > 0,
        orders = orders,
        slot = orders[1] and orders[1].slot or nil,
        statusText = (#orders > 0 and not M.hasPackage) and "当前订单" or nil,
    }
end

function M.IsNearOrderPoint(edgeId, edgeDist, lane)
    local clearance = CONFIG.OBSTACLE_ORDER_CLEARANCE or 10.0

    for _, order in ipairs(M.availableOrders) do
        if order.pickupEdgeId == edgeId and order.pickupLane == lane then
            if math.abs(edgeDist - (order.pickupEdgeDist or 0.0)) < clearance then
                return true
            end
        end
    end

    if M.deliveryActive and M.deliveryEdgeId == edgeId and M.deliveryLane == lane then
        if math.abs(edgeDist - (M.deliveryEdgeDist or 0.0)) < clearance then
            return true
        end
    end

    return false
end

function M.HandleCollision(collisionType)
    if collisionType and M.activeOrder and M.activeOrder.fragile then
        FailActiveOrder("fragile collision")
        return true
    end
    return false
end

function M.UpdateAnimation()
    for _, order in ipairs(M.availableOrders) do
        if order.nodeIndex and not M.hasPackage then
            local node = M.pickupNodes[order.nodeIndex]
            local shadow = M.pickupShadowNodes[order.nodeIndex]
            if node then
                local pos = node.position
                node.position = Vector3(pos.x, 0.6 + math.sin(time.elapsedTime * 3.0 + order.id) * 0.2, pos.z)
            end
            if shadow and node then
                shadow.rotation = node.rotation
                shadow.scale = Vector3(0.62, 0.012, 0.46)
            end
        end
    end

    if M.deliveryActive and M.deliveryNode then
        local pos = M.deliveryNode.position
        M.deliveryNode.position = Vector3(pos.x, 0.15 + math.sin(time.elapsedTime * 2.5) * 0.1, pos.z)
    end
    if M.deliveryActive and M.deliveryShadowNode and M.deliveryNode then
        M.deliveryShadowNode.rotation = M.deliveryNode.rotation
        M.deliveryShadowNode.scale = Vector3(0.66, 0.012, 0.66)
    end
end

function M.Reset()
    for _, order in ipairs(M.availableOrders) do
        HidePickupOrderVisual(order)
    end
    M.availableOrders = {}
    M.activeOrder = nil
    M.nextOrderId = 1

    for _, node in ipairs(M.pickupNodes) do
        HideNode(node)
    end
    for _, node in ipairs(M.pickupShadowNodes) do
        HideNode(node)
    end

    M.pickupActive = false
    M.pickupEdgeId = 0
    M.pickupEdgeDist = 0.0
    M.pickupLane = 2
    M.lastPickupEdgeId = 0
    M.firstPickupPending = true
    M.nextPickupDistance = 0.0
    M.lastPlayerLaneX = CONFIG.LANE_X[CONFIG.currentLane] or 0.0

    ClearDeliveryTarget()
    M.hasPackage = false
    if M.packageVisualNode then M.packageVisualNode.enabled = false end

    M.nextDeliveryDistance = 100.0
    StopOrderTimer()
    M.totalIncome = 0
    M.comboCount = 0
    M.runDeliveries = 0
    M.runOnTimeDeliveries = 0
    M.runBestCombo = 0
    M.runOrderTypeCounts = {}
    M.CapturePathSnapshot()
end

function M.GetRunStats()
    return {
        income = M.totalIncome or 0,
        deliveries = M.runDeliveries or 0,
        onTimeDeliveries = M.runOnTimeDeliveries or 0,
        bestCombo = M.runBestCombo or 0,
        orderTypeCounts = M.runOrderTypeCounts or {},
        distance = player.distanceTraveled or 0,
    }
end

return M
