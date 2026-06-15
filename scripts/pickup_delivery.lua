-- ============================================================================
-- 外卖冲冲冲 - 取件/送件模块（基于 RoadGraph）
-- ============================================================================
-- 取件/送件点绑定到真实 edge 上，根据 edgeProgress 生成
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local rn = require("road_network")
local mats = require("materials")
local nav = require("route_navigation")

local M = {}

local SHADOW_Y = CONFIG.PLAYER_GROUND_Y + 0.012

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

-- 取件点状态
M.pickupNode = nil
M.pickupShadowNode = nil
M.pickupActive = false
M.pickupEdgeId = 0
M.pickupEdgeDist = 0.0
M.pickupLane = 2
M.lastPickupEdgeId = 0
M.firstPickupPending = true
M.nextPickupDistance = 0.0  -- 走多远后才能再生成下一个

-- 送件点状态
M.deliveryNode = nil
M.deliveryShadowNode = nil
M.deliveryActive = false
M.deliveryEdgeId = 0
M.deliveryEdgeDist = 0.0
M.deliveryLane = 2
M.lastDeliveryEdgeId = 0
M.nextDeliveryDistance = 0.0

-- 游戏状态
M.hasPackage = false
M.packageVisualNode = nil

-- 计分
M.totalIncome = 0
M.comboCount = 0

-- 当前订单倒计时
M.orderTimerActive = false
M.orderTimeLimit = 0.0
M.orderTimeRemaining = 0.0
M.orderLateSeconds = 0.0

-- ============================================================================
-- 创建视觉节点
-- ============================================================================

function M.CreatePickupNode(scene)
    local node = scene:CreateChild("Pickup")

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

    M.pickupShadowNode = CreateContactShadow(scene, "PickupShadow", 0.62, 0.46)
    node.position = Vector3(0, -100, 0)
    M.pickupNode = node
    return node
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

-- ============================================================================
-- 送件目标工具
-- ============================================================================

local function HideDeliveryNode()
    HideNode(M.deliveryNode)
    HideNode(M.deliveryShadowNode)
end

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function StopOrderTimer()
    M.orderTimerActive = false
    M.orderTimeLimit = 0.0
    M.orderTimeRemaining = 0.0
    M.orderLateSeconds = 0.0
end

local function StartOrderTimer(routeDistance, currentSpeed)
    local safeSpeed = math.max(1.0, currentSpeed or CONFIG.BASE_SPEED)
    local estimatedTime = routeDistance / safeSpeed
    local limit = estimatedTime * CONFIG.ORDER_TIME_ROUTE_FACTOR + CONFIG.ORDER_TIME_EXTRA_SECONDS

    M.orderTimeLimit = Clamp(limit, CONFIG.ORDER_TIME_MIN_SECONDS, CONFIG.ORDER_TIME_MAX_SECONDS)
    M.orderTimeRemaining = M.orderTimeLimit
    M.orderLateSeconds = 0.0
    M.orderTimerActive = true
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

local function SelectDeliveryCandidates(currentEdge)
    local minHops = CONFIG.DELIVERY_TARGET_MIN_HOPS or 2
    local maxHops = CONFIG.DELIVERY_TARGET_MAX_HOPS or 4
    local candidates = nav.GetReachableTargetEdges(currentEdge, minHops, maxHops)

    if #candidates == 0 then
        candidates = nav.GetReachableTargetEdges(currentEdge, 1, 8)
    end

    return candidates
end

local function PlaceDeliveryOnCandidate(candidate, currentSpeed)
    local s = path.state
    if not candidate or not candidate.edge then return false end

    local edge = candidate.edge
    local effectiveLen = rn.GetEdgeEffectiveLength(edge)
    local minDist = CONFIG.ORDER_EDGE_START_BUFFER
    local maxDist = effectiveLen - CONFIG.ORDER_EDGE_END_BUFFER
    if maxDist <= minDist then return false end

    local targetDist = minDist + math.random() * (maxDist - minDist)
    local lane = math.random(1, 3)

    if not nav.SetTarget(edge.id, targetDist, s) then
        return false
    end

    M.deliveryEdgeId = edge.id
    M.deliveryEdgeDist = targetDist
    M.deliveryLane = lane
    M.deliveryActive = true

    local laneX = CONFIG.LANE_X[lane]
    local worldPos = rn.GetPositionOnEdgeByDist(edge, targetDist, laneX)
    M.deliveryNode.position = Vector3(worldPos.x, 0.15, worldPos.z)
    M.deliveryNode.rotation = Quaternion(rn.HeadingToYaw(edge.heading), Vector3.UP)
    PlaceShadow(M.deliveryShadowNode, worldPos, rn.HeadingToYaw(edge.heading))

    M.lastDeliveryEdgeId = edge.id
    M.nextDeliveryDistance = s.totalDistance + CONFIG.DELIVERY_INTERVAL_MIN + math.random() * (CONFIG.DELIVERY_INTERVAL_MAX - CONFIG.DELIVERY_INTERVAL_MIN)
    StartOrderTimer(nav.distanceRemaining or 0.0, currentSpeed)

    print("[Delivery] Spawned target edge " .. edge.id ..
        " hops " .. candidate.hops ..
        " dist " .. string.format("%.1f", targetDist) ..
        " limit " .. string.format("%.1f", M.orderTimeLimit) .. "s")
    return true
end

local function SpawnReachableDeliveryTarget(currentSpeed)
    local s = path.state
    if not s.currentEdge then return false end

    local candidates = SelectDeliveryCandidates(s.currentEdge)
    while #candidates > 0 do
        local index = math.random(1, #candidates)
        local candidate = candidates[index]
        table.remove(candidates, index)
        if PlaceDeliveryOnCandidate(candidate, currentSpeed) then
            return true
        end
    end

    return false
end

-- ============================================================================
-- 生成取件点（edge-based）
-- ============================================================================

function M.TrySpawnPickup()
    local s = path.state
    if s.insideIntersection then return end
    if M.pickupActive or M.hasPackage then return end
    if not s.currentEdge then return end

    -- 检查走过的距离是否满足间隔要求
    if s.totalDistance < M.nextPickupDistance then return end

    -- 生成位置：当前 edge 有效区段上玩家前方
    local effectiveLen = rn.GetEdgeEffectiveLength(s.currentEdge)
    local spawnAhead = M.firstPickupPending and (CONFIG.PICKUP_INITIAL_SPAWN_AHEAD or CONFIG.PICKUP_SPAWN_AHEAD) or CONFIG.PICKUP_SPAWN_AHEAD
    local spawnDist = s.edgeDistance + spawnAhead
    if spawnDist >= effectiveLen - CONFIG.ORDER_EDGE_END_BUFFER then return end  -- 太靠近末端不生成

    -- 安全区检测
    if spawnDist < CONFIG.ORDER_EDGE_START_BUFFER then return end

    local lane = math.random(1, 3)
    M.pickupEdgeId = s.currentEdge.id
    M.pickupEdgeDist = spawnDist
    M.pickupLane = lane
    M.pickupActive = true

    -- 计算世界位置
    local laneX = CONFIG.LANE_X[lane]
    local worldPos = rn.GetPositionOnEdgeByDist(s.currentEdge, spawnDist, laneX)
    M.pickupNode.position = Vector3(worldPos.x, 0.6, worldPos.z)
    M.pickupNode.rotation = Quaternion(rn.HeadingToYaw(s.currentEdge.heading), Vector3.UP)
    PlaceShadow(M.pickupShadowNode, worldPos, rn.HeadingToYaw(s.currentEdge.heading))

    M.lastPickupEdgeId = s.currentEdge.id
    M.firstPickupPending = false
    M.nextPickupDistance = s.totalDistance + CONFIG.PICKUP_INTERVAL_MIN + math.random() * (CONFIG.PICKUP_INTERVAL_MAX - CONFIG.PICKUP_INTERVAL_MIN)

    print("[Pickup] Spawned at edge " .. s.currentEdge.id .. " dist " .. string.format("%.1f", spawnDist))
end

-- ============================================================================
-- 取件碰撞检测
-- ============================================================================

function M.CheckPickup()
    if not M.pickupActive then return end
    local s = path.state
    if not s.currentEdge then return end

    -- 只有在同一条边上才检测
    if M.pickupEdgeId ~= s.currentEdge.id then
        -- 玩家已离开该边，取件点消失
        M.pickupActive = false
        HideNode(M.pickupNode)
        HideNode(M.pickupShadowNode)
        return
    end

    local distDiff = s.edgeDistance - (M.pickupEdgeDist or 0)
    if math.abs(distDiff) < CONFIG.COLLISION_Z_THRESHOLD and CONFIG.currentLane == M.pickupLane then
        -- 成功取件
        M.hasPackage = true
        M.pickupActive = false
        HideNode(M.pickupNode)
        HideNode(M.pickupShadowNode)
        if M.packageVisualNode then
            M.packageVisualNode.enabled = true
        end
        M.nextDeliveryDistance = s.totalDistance
        print("[Pickup] Package collected!")
    elseif distDiff > 3.0 then
        -- 错过了
        M.pickupActive = false
        HideNode(M.pickupNode)
        HideNode(M.pickupShadowNode)
    end
end

function M.GetMinimapData()
    if not M.pickupActive then
        return {
            active = false,
            slot = nil,
        }
    end

    local edge = rn.edges[M.pickupEdgeId]
    if not edge then
        return {
            active = false,
            slot = nil,
        }
    end

    local slot = nav.MakeEdgeSlot(edge)
    if not slot then
        return {
            active = false,
            slot = nil,
        }
    end

    return {
        active = true,
        slot = slot,
    }
end

-- ============================================================================
-- 生成送件点（edge-based）
-- ============================================================================

function M.TrySpawnDelivery(currentSpeed)
    local s = path.state
    if s.insideIntersection then return end
    if M.deliveryActive or not M.hasPackage then return end
    if not s.currentEdge then return end

    -- 检查距离间隔
    if s.totalDistance < M.nextDeliveryDistance then return end

    SpawnReachableDeliveryTarget(currentSpeed)
end

function M.ReselectDeliveryTarget(currentSpeed)
    if not M.hasPackage then return false end
    if not M.deliveryActive then return false end

    local ok = SpawnReachableDeliveryTarget(currentSpeed)
    if ok then
        print("[Delivery] Reselected reachable target")
        return true
    end

    ClearDeliveryTarget()
    return false
end

-- ============================================================================
-- 送件碰撞检测
-- ============================================================================

function M.CheckDelivery()
    if not M.deliveryActive then return end
    local s = path.state
    if not s.currentEdge then return end

    -- 送件点是持久目标，离开/绕路不会清空，只有进入目标 edge 后才检测送达或错过。
    if M.deliveryEdgeId ~= s.currentEdge.id then
        return
    end

    local distDiff = s.edgeDistance - (M.deliveryEdgeDist or 0)
    if math.abs(distDiff) < CONFIG.COLLISION_Z_THRESHOLD and CONFIG.currentLane == M.deliveryLane then
        -- 成功送达
        local baseReward = 10
        local reward = baseReward

        if M.orderLateSeconds > 0.0 then
            reward = baseReward - math.floor(M.orderLateSeconds * CONFIG.ORDER_LATE_PENALTY_PER_SEC)
            M.comboCount = 0
        else
            M.comboCount = M.comboCount + 1
            local comboBonus = math.floor(M.comboCount * CONFIG.DELIVERY_COMBO_MULTIPLIER)
            reward = baseReward + comboBonus
        end

        M.totalIncome = M.totalIncome + reward

        M.hasPackage = false
        ClearDeliveryTarget()
        if M.packageVisualNode then
            M.packageVisualNode.enabled = false
        end
        print("[Delivery] Delivered! Income " .. reward .. " (combo x" .. M.comboCount .. ")")
    elseif distDiff > 3.0 then
        -- 真正越过目标点才算错过；普通走错路只会触发导航重规划。
        M.comboCount = 0
        M.hasPackage = false
        ClearDeliveryTarget()
        if M.packageVisualNode then
            M.packageVisualNode.enabled = false
        end
        M.nextPickupDistance = s.totalDistance + CONFIG.PICKUP_INTERVAL_MIN * 0.5
        print("[Delivery] Missed target, combo reset")
    end
end

function M.UpdateOrderTimer(dt)
    if not M.orderTimerActive then return end

    M.orderTimeRemaining = M.orderTimeRemaining - (dt or 0.0)
    M.orderLateSeconds = math.max(0.0, -M.orderTimeRemaining)
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

    if M.orderTimeRemaining >= 0.0 then
        local displaySeconds = math.max(1, math.ceil(M.orderTimeRemaining))
        local state = "normal"
        if M.orderTimeRemaining <= CONFIG.ORDER_TIME_WARNING_SECONDS then
            state = "warning"
        end
        return {
            active = true,
            state = state,
            text = "订单 " .. displaySeconds .. "s",
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

-- ============================================================================
-- 浮动动画
-- ============================================================================

function M.UpdateAnimation()
    if M.pickupActive and M.pickupNode then
        local pos = M.pickupNode.position
        M.pickupNode.position = Vector3(pos.x, 0.6 + math.sin(time.elapsedTime * 3.0) * 0.2, pos.z)
    end
    if M.deliveryActive and M.deliveryNode then
        local pos = M.deliveryNode.position
        M.deliveryNode.position = Vector3(pos.x, 0.15 + math.sin(time.elapsedTime * 2.5) * 0.1, pos.z)
    end
    if M.pickupActive and M.pickupShadowNode and M.pickupNode then
        M.pickupShadowNode.rotation = M.pickupNode.rotation
        M.pickupShadowNode.scale = Vector3(0.62, 0.012, 0.46)
    end
    if M.deliveryActive and M.deliveryShadowNode and M.deliveryNode then
        M.deliveryShadowNode.rotation = M.deliveryNode.rotation
        M.deliveryShadowNode.scale = Vector3(0.66, 0.012, 0.66)
    end
end

-- ============================================================================
-- 重置
-- ============================================================================

function M.Reset()
    M.pickupActive = false
    HideNode(M.pickupNode)
    HideNode(M.pickupShadowNode)
    M.pickupEdgeId = 0
    M.pickupEdgeDist = 0.0
    ClearDeliveryTarget()
    M.hasPackage = false
    if M.packageVisualNode then M.packageVisualNode.enabled = false end
    M.firstPickupPending = true
    M.nextPickupDistance = 0.0
    M.nextDeliveryDistance = 100.0
    StopOrderTimer()
    M.totalIncome = 0
    M.comboCount = 0
end

return M
