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

local M = {}

-- 障碍物类型定义
M.types = {
    { name = "block", scaleY = 1.2, offsetY = 0.6, jumpable = false, slidable = false },
    { name = "low",   scaleY = 0.4, offsetY = 0.2, jumpable = true,  slidable = false },
    { name = "high",  scaleY = 1.0, offsetY = 1.5, jumpable = false, slidable = true  },
}

-- 对象池和活跃列表
M.pool = {}
M.active = {}
M.lastSpawnEdgeId = 0
M.lastSpawnDist = 0.0
M.distanceTraveled = 0.0

function M.CreateOne(scene, typeIdx)
    local info = M.types[typeIdx]
    local node = scene:CreateChild("Obstacle_" .. info.name)
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")

    if typeIdx == 1 then model.material = mats.obstacleBlock
    elseif typeIdx == 2 then model.material = mats.obstacleLow
    else model.material = mats.obstacleHigh end

    node.scale = Vector3(1.4, info.scaleY, 0.6)
    node.position = Vector3(0, -100, 0)

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

--- 在指定边上指定位置放置障碍物
--- edgeDist: 在有效区段内的距离（0 = 刚出路口区域）
local function PositionObstacle(obs, edge, edgeDist, lane)
    obs.edgeId = edge.id
    obs.edgeDist = edgeDist
    obs.lane = lane
    obs.active = true

    -- 新系统：找到对应 lane 的并行 edge，获取其世界坐标
    local targetEdge = rn.GetParallelExitEdge(edge.fromNode, edge.heading, lane)
    if not targetEdge then targetEdge = edge end
    local worldPos = rn.GetPositionOnEdgeByDist(targetEdge, edgeDist)
    obs.node.position = Vector3(worldPos.x, obs.info.offsetY, worldPos.z)
    obs.node.rotation = Quaternion(rn.HeadingToYaw(edge.heading), Vector3.UP)
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

    -- 计算生成范围（玩家前方 effectiveDist）
    local spawnAheadDist = math.min(effectiveLen, playerDist + CONFIG.OBSTACLE_SPAWN_AHEAD)

    -- 确定下次生成的位置（距离有效区段起点的距离）
    if M.lastSpawnEdgeId ~= edge.id then
        -- 进入新边，从安全区之后开始
        M.lastSpawnEdgeId = edge.id
        M.lastSpawnDist = CONFIG.SAFE_ZONE_DIST
    end

    while (M.lastSpawnDist or 0) + spacing < spawnAheadDist do
        local spawnDist = (M.lastSpawnDist or 0) + spacing
        M.lastSpawnDist = spawnDist

        -- 跳过安全区（靠近两端路口区域边界的位置）
        if spawnDist < CONFIG.SAFE_ZONE_DIST or (effectiveLen - spawnDist) < CONFIG.SAFE_ZONE_DIST then
            goto continue_spawn
        end

        -- 生成 1-2 个障碍物
        local numObs = 1
        if GetDifficultyFactor() > 0.3 and math.random() < 0.4 then
            numObs = 2
        end

        local lanes = {1, 2, 3}
        for i = #lanes, 2, -1 do
            local j = math.random(1, i)
            lanes[i], lanes[j] = lanes[j], lanes[i]
        end

        local placed = 0
        for _, lane in ipairs(lanes) do
            if placed >= numObs then break end

            local typeIdx = math.random(1, #M.types)
            local obs = GetInactive(typeIdx)
            if not obs then
                obs = GetInactive(1) or GetInactive(2) or GetInactive(3)
            end
            if obs then
                PositionObstacle(obs, edge, spawnDist, lane)
                table.insert(M.active, obs)
                placed = placed + 1
            end
        end

        ::continue_spawn::
    end
end

--- 碰撞检测
function M.CheckCollisions(playerLane, isJumping, jumpTime, isSliding, slideTime)
    local s = path.state
    if not s.currentEdge then return false end

    -- 使用 fromNode + heading 匹配同组并行道路上的障碍物
    local playerFromNode = s.currentEdge.fromNode
    local playerHeading = s.currentEdge.heading

    for idx = #M.active, 1, -1 do
        local obs = M.active[idx]
        -- 检查障碍物是否在同组并行道路上（相同 fromNode + heading）
        local obsEdge = rn.edges[obs.edgeId]
        if obsEdge and obsEdge.fromNode == playerFromNode and obsEdge.heading == playerHeading then
            local distDiff = math.abs(s.edgeDistance - (obs.edgeDist or 0))
            if distDiff < CONFIG.COLLISION_Z_THRESHOLD and obs.lane == playerLane then
                local canPass = false
                if obs.info.jumpable and isJumping and jumpTime > 0.1 then
                    canPass = true
                end
                if obs.info.slidable and isSliding and slideTime > 0.05 then
                    canPass = true
                end
                if not canPass then
                    return true
                end
            end
        end
    end
    return false
end

--- 回收已过的障碍物
function M.Recycle()
    local s = path.state
    if not s.currentEdge then return end

    local playerFromNode = s.currentEdge.fromNode
    local playerHeading = s.currentEdge.heading

    for idx = #M.active, 1, -1 do
        local obs = M.active[idx]
        -- 不在同组并行道路上，或者已经在玩家后面很远
        local shouldRemove = false
        local obsEdge = rn.edges[obs.edgeId]
        if not obsEdge or obsEdge.fromNode ~= playerFromNode or obsEdge.heading ~= playerHeading then
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
    M.lastSpawnDist = 0.0
end

return M
