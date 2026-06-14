-- ============================================================================
-- 澶栧崠鍐插啿锟?- 鍙栦欢/閫佷欢妯″潡锛堝熀锟?RoadGraph锟?
-- ============================================================================
-- 鍙栦欢/閫佷欢鐐圭粦瀹氬埌鐪熷疄 edge 涓婏紝鏍规嵁 edgeProgress 鐢熸垚
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local rn = require("road_network")
local mats = require("materials")
local nav = require("route_navigation")

local M = {}

-- 鍙栦欢鐐圭姸锟?
M.pickupNode = nil
M.pickupActive = false
M.pickupEdgeId = 0
M.pickupEdgeDist = 0.0
M.pickupLane = 2
M.lastPickupEdgeId = 0
M.nextPickupDistance = 0.0  -- 璧板杩滃悗鎵嶈兘鍐嶇敓鎴愪笅涓€锟?

-- 閫佷欢鐐圭姸锟?
M.deliveryNode = nil
M.deliveryActive = false
M.deliveryEdgeId = 0
M.deliveryEdgeDist = 0.0
M.deliveryLane = 2
M.lastDeliveryEdgeId = 0
M.nextDeliveryDistance = 0.0
M.deliveryDistrictId = "downtown"

-- 娓告垙鐘讹拷?
M.hasPackage = false
M.packageVisualNode = nil

-- 璁″垎
M.totalIncome = 0
M.comboCount = 0

-- 褰撳墠璁㈠崟鍊掕锟?M.orderTimerActive = false
M.orderTimerActive = false
M.orderTimeLimit = 0.0
M.orderTimeRemaining = 0.0
M.orderLateSeconds = 0.0

-- ============================================================================
-- 鍒涘缓瑙嗚鑺傜偣
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

    node.position = Vector3(0, -100, 0)
    M.deliveryNode = node
    return node
end

-- ============================================================================
-- 閫佷欢鐩爣宸ュ叿
-- ============================================================================

local function HideDeliveryNode()
    if M.deliveryNode then
        M.deliveryNode.position = Vector3(0, -100, 0)
    end
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

local function StartOrderTimer(routeDistance, currentSpeed, district)
    local safeSpeed = math.max(1.0, currentSpeed or CONFIG.BASE_SPEED)
    local estimatedTime = routeDistance / safeSpeed
    local orderTimeMult = district and district.orderTime or 1.0
    local limit = (estimatedTime * CONFIG.ORDER_TIME_ROUTE_FACTOR + CONFIG.ORDER_TIME_EXTRA_SECONDS) * orderTimeMult

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
    M.deliveryDistrictId = "downtown"
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
    local effectiveLen = rn.GetEdgeEffectiveLength()
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
    local district = rn.GetEdgeDistrict(edge)
    M.deliveryDistrictId = district.id

    local laneX = CONFIG.LANE_X[lane]
    local worldPos = rn.GetPositionOnEdgeByDist(edge, targetDist, laneX)
    M.deliveryNode.position = Vector3(worldPos.x, 0.15, worldPos.z)
    M.deliveryNode.rotation = Quaternion(rn.HeadingToYaw(edge.heading), Vector3.UP)

    M.lastDeliveryEdgeId = edge.id
    M.nextDeliveryDistance = s.totalDistance + CONFIG.DELIVERY_INTERVAL_MIN + math.random() * (CONFIG.DELIVERY_INTERVAL_MAX - CONFIG.DELIVERY_INTERVAL_MIN)
    StartOrderTimer(nav.distanceRemaining or 0.0, currentSpeed, district)

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
-- 鐢熸垚鍙栦欢鐐癸紙edge-based锟?-- ============================================================================

function M.TrySpawnPickup()
    local s = path.state
    if s.insideIntersection then return end
    if M.pickupActive or M.hasPackage then return end
    if not s.currentEdge then return end

    -- 妫€鏌ヨ蛋杩囩殑璺濈鏄惁婊¤冻闂撮殧瑕佹眰
    if s.totalDistance < M.nextPickupDistance then return end

    -- 鐢熸垚浣嶇疆锛氬綋锟?edge 鏈夋晥鍖烘涓婄帺瀹跺墠锟?
    local effectiveLen = rn.GetEdgeEffectiveLength()
    local spawnDist = s.edgeDistance + CONFIG.PICKUP_SPAWN_AHEAD
    if spawnDist >= effectiveLen - CONFIG.ORDER_EDGE_END_BUFFER then return end  -- 澶潬杩戞湯绔笉鐢熸垚


    if spawnDist < CONFIG.ORDER_EDGE_START_BUFFER then return end

    local lane = math.random(1, 3)
    M.pickupEdgeId = s.currentEdge.id
    M.pickupEdgeDist = spawnDist
    M.pickupLane = lane
    M.pickupActive = true

    -- 璁＄畻涓栫晫浣嶇疆
    local laneX = CONFIG.LANE_X[lane]
    local worldPos = rn.GetPositionOnEdgeByDist(s.currentEdge, spawnDist, laneX)
    M.pickupNode.position = Vector3(worldPos.x, 0.6, worldPos.z)
    M.pickupNode.rotation = Quaternion(rn.HeadingToYaw(s.currentEdge.heading), Vector3.UP)

    M.lastPickupEdgeId = s.currentEdge.id
    local district = rn.GetEdgeDistrict(s.currentEdge)
    local pickupMult = district.pickupInterval or 1.0
    local pickupGap = CONFIG.PICKUP_INTERVAL_MIN + math.random() * (CONFIG.PICKUP_INTERVAL_MAX - CONFIG.PICKUP_INTERVAL_MIN)
    M.nextPickupDistance = s.totalDistance + pickupGap * pickupMult

    print("[Pickup] Spawned at edge " .. s.currentEdge.id .. " dist " .. string.format("%.1f", spawnDist))
end

-- ============================================================================
-- 鍙栦欢纰版挒妫€锟?
-- ============================================================================

function M.CheckPickup()
    if not M.pickupActive then return end
    local s = path.state
    if not s.currentEdge then return end

    if M.pickupEdgeId ~= s.currentEdge.id then
        M.pickupActive = false
        M.pickupNode.position = Vector3(0, -100, 0)
        return
    end

    local distDiff = s.edgeDistance - (M.pickupEdgeDist or 0)
    if math.abs(distDiff) < CONFIG.COLLISION_Z_THRESHOLD and CONFIG.currentLane == M.pickupLane then
        M.hasPackage = true
        M.pickupActive = false
        M.pickupNode.position = Vector3(0, -100, 0)
        if M.packageVisualNode then
            M.packageVisualNode.enabled = true
        end
        M.nextDeliveryDistance = s.totalDistance
        print("[Pickup] Package collected!")
    elseif distDiff > 3.0 then
        M.pickupActive = false
        M.pickupNode.position = Vector3(0, -100, 0)
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
-- 鐢熸垚閫佷欢鐐癸紙edge-based锟?-- ============================================================================

function M.TrySpawnDelivery(currentSpeed)
    local s = path.state
    if s.insideIntersection then return end
    if M.deliveryActive or not M.hasPackage then return end
    if not s.currentEdge then return end
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
-- 閫佷欢纰版挒妫€锟?
-- ============================================================================

function M.CheckDelivery()
    if not M.deliveryActive then return end
    local s = path.state
    if not s.currentEdge then return end
    if M.deliveryEdgeId ~= s.currentEdge.id then
        return
    end

    local distDiff = s.edgeDistance - (M.deliveryEdgeDist or 0)
    if math.abs(distDiff) < CONFIG.COLLISION_Z_THRESHOLD and CONFIG.currentLane == M.deliveryLane then
        local district = rn.GetEdgeDistrict(rn.edges[M.deliveryEdgeId])
        local baseReward = math.floor(10 * (district.reward or 1.0))
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
            text = "绛夊緟璁㈠崟",
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
            text = "璁㈠崟 " .. displaySeconds .. "s",
            remaining = M.orderTimeRemaining,
            lateSeconds = 0.0,
        }
    end

    local lateSeconds = math.max(1, math.ceil(M.orderLateSeconds))
    return {
        active = true,
        state = "late",
        text = "杩熷埌 " .. lateSeconds .. "s",
        remaining = M.orderTimeRemaining,
        lateSeconds = M.orderLateSeconds,
    }
end

-- ============================================================================
-- 娴姩鍔ㄧ敾
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
-- 閲嶇疆
-- ============================================================================

function M.Reset()
    M.pickupActive = false
    M.pickupNode.position = Vector3(0, -100, 0)
    M.pickupEdgeId = 0
    M.pickupEdgeDist = 0.0
    ClearDeliveryTarget()
    M.hasPackage = false
    if M.packageVisualNode then M.packageVisualNode.enabled = false end
    M.nextPickupDistance = 30.0
    M.nextDeliveryDistance = 100.0
    M.deliveryDistrictId = "downtown"
    StopOrderTimer()
    M.totalIncome = 0
    M.comboCount = 0
end

return M
