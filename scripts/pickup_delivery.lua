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

local M = {}

-- 取件点状态
M.pickupNode = nil
M.pickupActive = false
M.pickupEdgeId = 0
M.pickupEdgeDist = 0.0
M.pickupLane = 2
M.lastPickupEdgeId = 0
M.nextPickupDistance = 0.0  -- 走多远后才能再生成下一个

-- 送件点状态
M.deliveryNode = nil
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
M.timeRemaining = 30.0
M.totalIncome = 0
M.comboCount = 0

-- ============================================================================
-- 创建视觉节点
-- ============================================================================

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
    local effectiveLen = rn.GetEdgeEffectiveLength()
    local spawnDist = s.edgeDistance + CONFIG.PICKUP_SPAWN_AHEAD
    if spawnDist >= effectiveLen - CONFIG.SAFE_ZONE_DIST then return end  -- 太靠近末端不生成

    -- 安全区检测
    if spawnDist < CONFIG.SAFE_ZONE_DIST then return end

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

    M.lastPickupEdgeId = s.currentEdge.id
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
        M.pickupNode.position = Vector3(0, -100, 0)
        return
    end

    local distDiff = s.edgeDistance - (M.pickupEdgeDist or 0)
    if math.abs(distDiff) < CONFIG.COLLISION_Z_THRESHOLD and CONFIG.currentLane == M.pickupLane then
        -- 成功取件
        M.hasPackage = true
        M.pickupActive = false
        M.pickupNode.position = Vector3(0, -100, 0)
        if M.packageVisualNode then
            M.packageVisualNode.enabled = true
        end
        M.nextDeliveryDistance = s.totalDistance + CONFIG.DELIVERY_INTERVAL_MIN * 0.5
        print("[Pickup] Package collected!")
    elseif distDiff > 3.0 then
        -- 错过了
        M.pickupActive = false
        M.pickupNode.position = Vector3(0, -100, 0)
    end
end

-- ============================================================================
-- 生成送件点（edge-based）
-- ============================================================================

function M.TrySpawnDelivery()
    local s = path.state
    if s.insideIntersection then return end
    if M.deliveryActive or not M.hasPackage then return end
    if not s.currentEdge then return end

    -- 检查距离间隔
    if s.totalDistance < M.nextDeliveryDistance then return end

    -- 生成位置
    local effectiveLen = rn.GetEdgeEffectiveLength()
    local spawnDist = s.edgeDistance + CONFIG.DELIVERY_SPAWN_AHEAD
    if spawnDist >= effectiveLen - CONFIG.SAFE_ZONE_DIST then return end

    -- 安全区检测
    if spawnDist < CONFIG.SAFE_ZONE_DIST then return end

    local lane = math.random(1, 3)
    M.deliveryEdgeId = s.currentEdge.id
    M.deliveryEdgeDist = spawnDist
    M.deliveryLane = lane
    M.deliveryActive = true

    -- 计算世界位置
    local laneX = CONFIG.LANE_X[lane]
    local worldPos = rn.GetPositionOnEdgeByDist(s.currentEdge, spawnDist, laneX)
    M.deliveryNode.position = Vector3(worldPos.x, 0.15, worldPos.z)
    M.deliveryNode.rotation = Quaternion(rn.HeadingToYaw(s.currentEdge.heading), Vector3.UP)

    M.lastDeliveryEdgeId = s.currentEdge.id
    M.nextDeliveryDistance = s.totalDistance + CONFIG.DELIVERY_INTERVAL_MIN + math.random() * (CONFIG.DELIVERY_INTERVAL_MAX - CONFIG.DELIVERY_INTERVAL_MIN)

    -- 设置送件推荐方向（优先级高于随机推荐）
    -- lane 偏左→推荐左转，偏右→推荐右转，中间→随机
    local hint = (lane <= 1) and -1 or ((lane >= 3) and 1 or 0)
    path.state.deliveryHintDir = hint

    print("[Delivery] Spawned at edge " .. s.currentEdge.id .. " dist " .. string.format("%.1f", spawnDist) .. " hint=" .. hint)
end

-- ============================================================================
-- 送件碰撞检测
-- ============================================================================

function M.CheckDelivery()
    if not M.deliveryActive then return end
    local s = path.state
    if not s.currentEdge then return end

    -- 只有在同一条边上才检测
    if M.deliveryEdgeId ~= s.currentEdge.id then
        -- 玩家已离开该边，送件点消失，连击中断
        M.comboCount = 0
        M.deliveryActive = false
        M.deliveryNode.position = Vector3(0, -100, 0)
        return
    end

    local distDiff = s.edgeDistance - (M.deliveryEdgeDist or 0)
    if math.abs(distDiff) < CONFIG.COLLISION_Z_THRESHOLD and CONFIG.currentLane == M.deliveryLane then
        -- 成功送达
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
        -- 清除送件推荐方向
        path.state.deliveryHintDir = nil
        print("[Delivery] Delivered! Income +" .. reward .. " (combo x" .. M.comboCount .. ")")
    elseif distDiff > 3.0 then
        -- 错过了
        M.comboCount = 0
        M.deliveryActive = false
        M.deliveryNode.position = Vector3(0, -100, 0)
        -- 清除送件推荐方向
        path.state.deliveryHintDir = nil
    end
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
end

-- ============================================================================
-- 重置
-- ============================================================================

function M.Reset()
    M.pickupActive = false
    M.pickupNode.position = Vector3(0, -100, 0)
    M.pickupEdgeId = 0
    M.pickupEdgeDist = 0.0
    M.deliveryActive = false
    M.deliveryNode.position = Vector3(0, -100, 0)
    M.deliveryEdgeId = 0
    M.deliveryEdgeDist = 0.0
    M.hasPackage = false
    if M.packageVisualNode then M.packageVisualNode.enabled = false end
    M.nextPickupDistance = 30.0
    M.nextDeliveryDistance = 100.0
    M.timeRemaining = 30.0
    M.totalIncome = 0
    M.comboCount = 0
    -- 清除送件推荐
    path.state.deliveryHintDir = nil
end

return M
