-- ============================================================================
-- 外卖冲冲冲 - 障碍物模块
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
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
        pathDist = 0.0,
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

local function CountNearDist(pathDist, range)
    local count = 0
    for _, obs in ipairs(M.active) do
        if math.abs(obs.pathDist - pathDist) < range then
            count = count + 1
        end
    end
    return count
end

local function IsLaneTooDense(lane, pathDist)
    for _, obs in ipairs(M.active) do
        if obs.lane == lane and math.abs(obs.pathDist - pathDist) < CONFIG.OBSTACLE_MIN_SPACING * 0.6 then
            return true
        end
    end
    return false
end

local function GetDifficultyFactor()
    local d = math.max(0, M.distanceTraveled - CONFIG.DIFFICULTY_START_DISTANCE)
    return math.min(1.0, d / CONFIG.DIFFICULTY_RAMP_DISTANCE)
end

local function GetCurrentSpacing()
    local factor = GetDifficultyFactor()
    return CONFIG.OBSTACLE_SPACING_MAX - (CONFIG.OBSTACLE_SPACING_MAX - CONFIG.OBSTACLE_SPACING_MIN) * factor
end

local function PositionObstacle(obs, pathDist, lane)
    local s = path.state
    obs.pathDist = pathDist
    obs.lane = lane
    obs.active = true

    local laneX = CONFIG.LANE_X[lane]
    local worldPos = path.GetWorldPosForObject(pathDist, laneX)
    obs.node.position = Vector3(worldPos.x, obs.info.offsetY, worldPos.z)
    obs.node.rotation = Quaternion(path.HeadingToYaw(s.currentHeading), Vector3.UP)
end

function M.Spawn()
    local s = path.state
    if s.turnExecuting then return end

    local spawnAhead = s.routeDistance + CONFIG.OBSTACLE_SPAWN_AHEAD
    local spacing = GetCurrentSpacing()

    while M.lastSpawnDist + spacing < spawnAhead do
        local spawnDist = M.lastSpawnDist + spacing
        M.lastSpawnDist = spawnDist

        if path.IsInSafeZone(spawnDist) then
            goto continue_spawn
        end

        if CountNearDist(spawnDist, spacing * 0.7) >= CONFIG.OBSTACLE_MAX_PER_ROW then
            goto continue_spawn
        end

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
            if IsLaneTooDense(lane, spawnDist) then goto next_lane end

            local typeIdx = math.random(1, #M.types)
            local obs = GetInactive(typeIdx)
            if not obs then
                obs = GetInactive(1) or GetInactive(2) or GetInactive(3)
            end
            if obs then
                PositionObstacle(obs, spawnDist, lane)
                table.insert(M.active, obs)
                placed = placed + 1
            end

            ::next_lane::
        end

        ::continue_spawn::
    end
end

function M.CheckCollisions(playerLane, isJumping, jumpTime, isSliding, slideTime)
    local s = path.state
    for idx = #M.active, 1, -1 do
        local obs = M.active[idx]
        local distDiff = math.abs(s.routeDistance - obs.pathDist)

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
    return false
end

function M.Recycle()
    local s = path.state
    local obsBehind = s.routeDistance - 10.0
    for idx = #M.active, 1, -1 do
        local obs = M.active[idx]
        if obs.pathDist < obsBehind then
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
end

return M
