-- ============================================================================
-- 外卖冲冲冲 - 障碍物模块（基于 RoadGraph）
-- ============================================================================
-- 障碍物绑定到真实 edge，根据 edgeProgress 生成/回收
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local rn = require("road_network")
local mats = require("materials")
local pickup = require("pickup_delivery")

local M = {}

-- 障碍物类型定义
M.types = {
    { name = "block", offsetY = 0.785, jumpable = false, slidable = false },
    { name = "low",   offsetY = 0.30,  jumpable = true,  slidable = false, topLandable = true },
    { name = "high",  offsetY = 1.01,  jumpable = false, slidable = true  },
}

local TYPE_BLOCK = 1
local TYPE_LOW = 2
local TYPE_HIGH = 3

-- 对象池和活跃列表
M.pool = {}
M.active = {}
M.lastSpawnEdgeId = 0
M.lastSpawnDist = 0.0
M.distanceTraveled = 0.0

function M.CreateOne(scene, typeIdx)
    local info = M.types[typeIdx]
    local node = scene:CreateChild("Obstacle_" .. info.name)
    node.position = Vector3(0, -100, 0)

    if typeIdx == TYPE_BLOCK then
        local barrier = node:CreateChild("Barrier")
        local model = barrier:CreateComponent("StaticModel")
        model.model = cache:GetResource("Model", "Models/Box.mdl")
        model.material = mats.obstacleBlock
        barrier.scale = Vector3(1.35, 1.25, 0.65)
        barrier.position = Vector3(0, 0, 0)

        local cap = node:CreateChild("Cap")
        local capModel = cap:CreateComponent("StaticModel")
        capModel.model = cache:GetResource("Model", "Models/Box.mdl")
        capModel.material = mats.obstacleBlock
        cap.scale = Vector3(1.55, 0.18, 0.78)
        cap.position = Vector3(0, 0.68, 0)
    elseif typeIdx == TYPE_LOW then
        local bump = node:CreateChild("SpeedBump")
        local model = bump:CreateComponent("StaticModel")
        model.model = cache:GetResource("Model", "Models/Box.mdl")
        model.material = mats.obstacleLow
        bump.scale = Vector3(1.65, 0.28, 0.9)
        bump.position = Vector3(0, 0, 0)

        local stripe = node:CreateChild("Stripe")
        local stripeModel = stripe:CreateComponent("StaticModel")
        stripeModel.model = cache:GetResource("Model", "Models/Box.mdl")
        stripeModel.material = mats.laneLine
        stripe.scale = Vector3(1.5, 0.04, 0.18)
        stripe.position = Vector3(0, 0.17, 0)
    else
        local leftPost = node:CreateChild("LeftPost")
        local leftModel = leftPost:CreateComponent("StaticModel")
        leftModel.model = cache:GetResource("Model", "Models/Box.mdl")
        leftModel.material = mats.obstacleHigh
        leftPost.scale = Vector3(0.18, 1.4, 0.25)
        leftPost.position = Vector3(-0.65, -0.15, 0)

        local rightPost = node:CreateChild("RightPost")
        local rightModel = rightPost:CreateComponent("StaticModel")
        rightModel.model = cache:GetResource("Model", "Models/Box.mdl")
        rightModel.material = mats.obstacleHigh
        rightPost.scale = Vector3(0.18, 1.4, 0.25)
        rightPost.position = Vector3(0.65, -0.15, 0)

        local bar = node:CreateChild("TopBar")
        local barModel = bar:CreateComponent("StaticModel")
        barModel.model = cache:GetResource("Model", "Models/Box.mdl")
        barModel.material = mats.obstacleHigh
        bar.scale = Vector3(1.55, 0.22, 0.32)
        bar.position = Vector3(0, 0.58, 0)
    end

    return {
        node = node,
        typeIdx = typeIdx,
        info = info,
        edgeId = 0,
        edgeDist = 0.0,
        lane = 2,
        active = false,
    }
end

function M.Init(scene)
    for t = 1, #M.types do
        for i = 1, CONFIG.OBSTACLE_POOL_PER_TYPE do
            local obs = M.CreateOne(scene, t)
            table.insert(M.pool, obs)
        end
    end
end

local function GetInactive(typeIdx)
    for _, obs in ipairs(M.pool) do
        if not obs.active and obs.typeIdx == typeIdx then
            return obs
        end
    end
    return nil
end

local function GetDifficultyFactor()
    local d = math.max(0, M.distanceTraveled - CONFIG.DIFFICULTY_START_DISTANCE)
    return math.min(1.0, d / CONFIG.DIFFICULTY_RAMP_DISTANCE)
end

local function GetCurrentSpacing()
    local factor = GetDifficultyFactor()
    return CONFIG.OBSTACLE_SPACING_MAX - (CONFIG.OBSTACLE_SPACING_MAX - CONFIG.OBSTACLE_SPACING_MIN) * factor
end

local function Shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(1, i)
        list[i], list[j] = list[j], list[i]
    end
end

local function GetSpawnAheadDist(playerDist, effectiveLen)
    local ahead = CONFIG.OBSTACLE_SPAWN_AHEAD + GetDifficultyFactor() * 10.0
    return math.min(effectiveLen, playerDist + ahead)
end

local function IsNearOrderPoint(edgeId, edgeDist, lane)
    local clearance = CONFIG.OBSTACLE_ORDER_CLEARANCE

    if pickup.pickupActive and pickup.pickupEdgeId == edgeId and pickup.pickupLane == lane then
        if math.abs(edgeDist - pickup.pickupEdgeDist) < clearance then
            return true
        end
    end

    if pickup.deliveryActive and pickup.deliveryEdgeId == edgeId and pickup.deliveryLane == lane then
        if math.abs(edgeDist - pickup.deliveryEdgeDist) < clearance then
            return true
        end
    end

    return false
end

local function IsSpawnDistSafe(edgeDist, effectiveLen, complex)
    local startBuffer = complex and CONFIG.OBSTACLE_EDGE_START_BUFFER or CONFIG.SAFE_ZONE_DIST
    local endBuffer = complex and CONFIG.OBSTACLE_EDGE_END_BUFFER or CONFIG.SAFE_ZONE_DIST
    if edgeDist < startBuffer then return false end
    if (effectiveLen - edgeDist) < endBuffer then return false end
    return true
end

local function PickTypeForSingle()
    local r = math.random()
    if r < 0.4 then return TYPE_BLOCK end
    if r < 0.7 then return TYPE_LOW end
    return TYPE_HIGH
end

local function PickPattern()
    local d = M.distanceTraveled
    local factor = GetDifficultyFactor()

    if d < CONFIG.OBSTACLE_COMPLEX_START_DISTANCE then
        local r = math.random()
        if r < 0.45 then return "single_block" end
        if r < 0.75 then return "single_low" end
        return "single_high"
    end

    if d < CONFIG.OBSTACLE_ADVANCED_START_DISTANCE then
        local r = math.random()
        if r < 0.28 then return "single_block" end
        if r < 0.48 then return "single_low" end
        if r < 0.68 then return "single_high" end
        return "double_block"
    end

    local r = math.random()
    if r < 0.20 then return "single_block" end
    if r < 0.36 then return "single_low" end
    if r < 0.52 then return "single_high" end
    if r < 0.76 then return "double_block" end
    if r < 0.88 then return "low_then_high" end
    if factor > 0.75 then return "zigzag_blocks" end
    return "double_block"
end

local function BuildObstacleRows(pattern)
    local lanes = { 1, 2, 3 }
    Shuffle(lanes)

    if pattern == "single_block" then
        return { { distOffset = 0, entries = { { lane = lanes[1], typeIdx = TYPE_BLOCK } } } }
    elseif pattern == "single_low" then
        return { { distOffset = 0, entries = { { lane = lanes[1], typeIdx = TYPE_LOW } } } }
    elseif pattern == "single_high" then
        return { { distOffset = 0, entries = { { lane = lanes[1], typeIdx = TYPE_HIGH } } } }
    elseif pattern == "double_block" then
        return {
            {
                distOffset = 0,
                entries = {
                    { lane = lanes[1], typeIdx = TYPE_BLOCK },
                    { lane = lanes[2], typeIdx = math.random() < 0.35 and TYPE_LOW or TYPE_BLOCK },
                }
            }
        }
    elseif pattern == "low_then_high" then
        local lane = lanes[1]
        return {
            { distOffset = 0, entries = { { lane = lane, typeIdx = TYPE_LOW } } },
            { distOffset = CONFIG.OBSTACLE_SEQUENCE_GAP, entries = { { lane = lane, typeIdx = TYPE_HIGH } } },
        }
    elseif pattern == "zigzag_blocks" then
        return {
            { distOffset = 0, entries = { { lane = lanes[1], typeIdx = TYPE_BLOCK } } },
            { distOffset = CONFIG.OBSTACLE_SEQUENCE_GAP, entries = { { lane = lanes[2], typeIdx = PickTypeForSingle() } } },
        }
    end

    return { { distOffset = 0, entries = { { lane = lanes[1], typeIdx = PickTypeForSingle() } } } }
end

--- 在指定边上指定位置放置障碍物
--- edgeDist: 在有效区段内的距离（0 = 刚出路口区域）
local function PositionObstacle(obs, edge, edgeDist, lane)
    obs.edgeId = edge.id
    obs.edgeDist = edgeDist
    obs.lane = lane
    obs.active = true

    local laneX = CONFIG.LANE_X[lane]
    local worldPos = rn.GetPositionOnEdgeByDist(edge, edgeDist, laneX)
    obs.node.position = Vector3(worldPos.x, obs.info.offsetY, worldPos.z)
    obs.node.rotation = Quaternion(rn.HeadingToYaw(edge.heading), Vector3.UP)
end

local function TryPlaceEntry(edge, edgeDist, entry)
    if IsNearOrderPoint(edge.id, edgeDist, entry.lane) then
        return false
    end

    local obs = GetInactive(entry.typeIdx)
    if not obs then
        obs = GetInactive(TYPE_BLOCK) or GetInactive(TYPE_LOW) or GetInactive(TYPE_HIGH)
    end
    if not obs then return false end

    PositionObstacle(obs, edge, edgeDist, entry.lane)
    table.insert(M.active, obs)
    return true
end

local function CanPlaceRow(edge, edgeDist, row)
    local placeable = 0
    for _, entry in ipairs(row.entries) do
        if not IsNearOrderPoint(edge.id, edgeDist, entry.lane) then
            placeable = placeable + 1
        end
    end

    if #row.entries == 1 then
        return placeable == 1
    end
    return placeable > 0
end

local function TryPlacePattern(edge, baseDist, pattern, effectiveLen)
    local rows = BuildObstacleRows(pattern)
    local complex = #rows > 1 or pattern == "double_block"

    for _, row in ipairs(rows) do
        local rowDist = baseDist + row.distOffset
        if not IsSpawnDistSafe(rowDist, effectiveLen, complex) then
            return false
        end
        if not CanPlaceRow(edge, rowDist, row) then
            return false
        end
    end

    for _, row in ipairs(rows) do
        local rowDist = baseDist + row.distOffset
        for _, entry in ipairs(row.entries) do
            TryPlaceEntry(edge, rowDist, entry)
        end
    end

    return true
end

local function ClearOrderConflicts()
    for idx = #M.active, 1, -1 do
        local obs = M.active[idx]
        if IsNearOrderPoint(obs.edgeId, obs.edgeDist, obs.lane) then
            obs.active = false
            obs.node.position = Vector3(0, -100, 0)
            table.remove(M.active, idx)
        end
    end
end

--- 生成障碍物（在当前边的前方）
function M.Spawn()
    local s = path.state
    if s.insideIntersection then return end
    if not s.currentEdge then return end

    local edge = s.currentEdge
    local effectiveLen = rn.GetEdgeEffectiveLength()
    local playerDist = s.edgeDistance
    local spacing = GetCurrentSpacing()

    ClearOrderConflicts()

    -- 计算生成范围（玩家前方 effectiveDist）
    local spawnAheadDist = GetSpawnAheadDist(playerDist, effectiveLen)

    -- 确定下次生成的位置（距离有效区段起点的距离）
    if M.lastSpawnEdgeId ~= edge.id then
        -- 进入新边，从安全区之后开始
        M.lastSpawnEdgeId = edge.id
        M.lastSpawnDist = CONFIG.SAFE_ZONE_DIST
    end

    while (M.lastSpawnDist or 0) + spacing < spawnAheadDist do
        local spawnDist = (M.lastSpawnDist or 0) + spacing
        M.lastSpawnDist = spawnDist

        local pattern = PickPattern()
        local isComplex = pattern == "double_block" or pattern == "low_then_high" or pattern == "zigzag_blocks"

        -- 跳过安全区（靠近两端路口区域边界的位置）
        if not IsSpawnDistSafe(spawnDist, effectiveLen, isComplex) then
            goto continue_spawn
        end

        if TryPlacePattern(edge, spawnDist, pattern, effectiveLen) then
            if pattern == "low_then_high" or pattern == "zigzag_blocks" then
                M.lastSpawnDist = spawnDist + CONFIG.OBSTACLE_SEQUENCE_GAP
            end
        end

        ::continue_spawn::
    end
end

--- 碰撞检测
function M.CheckCollisions(playerLane, isJumping, jumpTime, isSliding, slideTime, collisionState)
    local s = path.state
    if not s.currentEdge then return nil end

    local playerX = collisionState and collisionState.laneX or CONFIG.LANE_X[playerLane]
    local isChangingLane = collisionState and collisionState.laneChanging
    local targetLane = collisionState and collisionState.toLane or playerLane
    local jumpY = collisionState and collisionState.jumpY or 0.0

    for idx = #M.active, 1, -1 do
        local obs = M.active[idx]
        -- 只检测同一条边上的障碍物
        if obs.edgeId == s.currentEdge.id then
            local distDiff = math.abs(s.edgeDistance - (obs.edgeDist or 0))
            if distDiff < CONFIG.COLLISION_Z_THRESHOLD then
                local obstacleX = CONFIG.LANE_X[obs.lane]
                local xDiff = math.abs(playerX - obstacleX)
                local canPass = false
                if obs.info.jumpable and isJumping and jumpTime > 0.1 then
                    canPass = true
                end
                if obs.info.slidable and isSliding and slideTime > 0.05 then
                    canPass = true
                end
                if obs.info.topLandable and jumpY >= (CONFIG.LOW_OBSTACLE_TOP_Y + CONFIG.TOP_LANDING_MIN_CLEARANCE) then
                    canPass = true
                end
                if not canPass then
                    if xDiff <= CONFIG.COLLISION_FRONT_X_THRESHOLD then
                        return "front"
                    end
                    if isChangingLane and obs.lane == targetLane and xDiff <= CONFIG.COLLISION_SIDE_X_THRESHOLD then
                        return "side"
                    end
                end
            end
        end
    end
    return nil
end

--- 回收已过的障碍物
function M.Recycle()
    local s = path.state
    if not s.currentEdge then return end

    for idx = #M.active, 1, -1 do
        local obs = M.active[idx]
        -- 不在当前边上，或者已经在玩家后面很远
        local shouldRemove = false
        if obs.edgeId ~= s.currentEdge.id then
            shouldRemove = true
        elseif (obs.edgeDist or 0) < s.edgeDistance - 10.0 then
            shouldRemove = true
        end

        if shouldRemove then
            obs.active = false
            obs.node.position = Vector3(0, -100, 0)
            table.remove(M.active, idx)
        end
    end
end

function M.ClearAll()
    for _, obs in ipairs(M.active) do
        obs.active = false
        obs.node.position = Vector3(0, -100, 0)
    end
    M.active = {}
    M.lastSpawnDist = CONFIG.OBSTACLE_EDGE_START_BUFFER
end

return M
