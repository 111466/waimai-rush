-- ============================================================================
-- 外卖冲冲冲 - 路径系统模块
-- ============================================================================

local cfg = require("config")
local PATH = cfg.PATH

local M = {}

-- ============================================================================
-- 路径系统运行时状态（共享）
-- ============================================================================
M.state = {
    routeDistance = 0.0,
    currentHeading = 0,
    currentSegmentOrigin = nil,
    currentSegmentStartDist = 0.0,

    -- 转弯状态
    nextIntersectionDist = 0.0,
    intersectionActive = false,
    turnChoice = 0,
    turnExecuting = false,
    turnAnimTime = 0.0,
    turnFromHeading = 0,
    turnToHeading = 0,
    turnWorldPos = nil,
    turnDir = 0,
    turnStartDist = 0.0,
    turnEndDist = 0.0,
    turnStartOrigin = nil,
    turnEndOrigin = nil,

    -- 摄像机转弯
    camTurnAnimTime = 0.0,
    camTurnFrom = 0.0,
    camTurnTo = 0.0,
    camTurning = false,

    -- 路口方向提示
    intersectionHintDir = 0,
    intersectionCorrectDir = 0,
}

-- ============================================================================
-- 路径系统辅助函数
-- ============================================================================

--- 朝向 → 前进方向向量
function M.GetForwardVector(heading)
    if heading == 0 then return Vector3(0, 0, 1)
    elseif heading == 1 then return Vector3(1, 0, 0)
    elseif heading == 2 then return Vector3(0, 0, -1)
    elseif heading == 3 then return Vector3(-1, 0, 0)
    end
    return Vector3(0, 0, 1)
end

--- 朝向 → 右侧方向向量
function M.GetRightVector(heading)
    if heading == 0 then return Vector3(1, 0, 0)
    elseif heading == 1 then return Vector3(0, 0, -1)
    elseif heading == 2 then return Vector3(-1, 0, 0)
    elseif heading == 3 then return Vector3(0, 0, 1)
    end
    return Vector3(1, 0, 0)
end

--- 朝向 → 摄像机 yaw 角(度)
function M.HeadingToYaw(heading)
    return heading * 90.0
end

function M.NormalizeHeading(heading)
    return ((heading % 4) + 4) % 4
end

function M.SmoothStep(t)
    return t * t * (3.0 - 2.0 * t)
end

function M.GetTurnEndHeading(fromHeading, turnDir)
    if turnDir == 1 then
        return M.NormalizeHeading(fromHeading + 1)
    elseif turnDir == -1 then
        return M.NormalizeHeading(fromHeading + 3)
    end
    return fromHeading
end

function M.GetTurnPoint(startOrigin, startHeading, turnDir, arcDist, laneOffset)
    local radius = PATH.TURN_RADIUS
    local angle = math.min(math.max(arcDist / radius, 0.0), math.pi * 0.5)
    local fwd = M.GetForwardVector(startHeading)
    local right = M.GetRightVector(startHeading)
    local turnSide = turnDir

    local center = Vector3(
        startOrigin.x + right.x * turnSide * radius,
        0,
        startOrigin.z + right.z * turnSide * radius
    )

    local radialStart = Vector3(-right.x * turnSide, 0, -right.z * turnSide)
    local cosA = math.cos(angle)
    local sinA = math.sin(angle)

    local radial = Vector3(
        radialStart.x * cosA + fwd.x * sinA,
        0,
        radialStart.z * cosA + fwd.z * sinA
    )
    local tangent = Vector3(
        radialStart.x * (-math.sin(angle)) + fwd.x * math.cos(angle),
        0,
        radialStart.z * (-math.sin(angle)) + fwd.z * math.cos(angle)
    )
    local laneRight = Vector3(tangent.z, 0, -tangent.x)

    local pos = Vector3(
        center.x + radial.x * radius + laneRight.x * laneOffset,
        0,
        center.z + radial.z * radius + laneRight.z * laneOffset
    )

    return pos, tangent
end

function M.GetTrackYawAt(pathDist)
    local s = M.state
    if s.turnExecuting and pathDist >= s.turnStartDist and pathDist <= s.turnEndDist then
        local t = math.min(math.max((pathDist - s.turnStartDist) / PATH.TURN_ARC_LENGTH, 0.0), 1.0)
        local fromYaw = M.HeadingToYaw(s.turnFromHeading)
        local toYaw = M.HeadingToYaw(s.turnToHeading)
        local diff = toYaw - fromYaw
        if diff > 180 then toYaw = toYaw - 360
        elseif diff < -180 then toYaw = toYaw + 360 end
        return fromYaw + (toYaw - fromYaw) * t
    end
    return M.HeadingToYaw(s.currentHeading)
end

--- 根据路程和车道偏移计算世界坐标
function M.GetWorldPosOnTrack(pathDist, laneOffset)
    local s = M.state
    if s.turnExecuting and pathDist >= s.turnStartDist and pathDist <= s.turnEndDist then
        local pos = M.GetTurnPoint(s.turnStartOrigin, s.turnFromHeading, s.turnDir, pathDist - s.turnStartDist, laneOffset)
        return pos
    end

    local localDist = pathDist - s.currentSegmentStartDist
    local fwd = M.GetForwardVector(s.currentHeading)
    local right = M.GetRightVector(s.currentHeading)
    local pos = Vector3(
        s.currentSegmentOrigin.x + fwd.x * localDist + right.x * laneOffset,
        0,
        s.currentSegmentOrigin.z + fwd.z * localDist + right.z * laneOffset
    )
    return pos
end

--- 检查某个路程距离是否在安全区内
function M.IsInSafeZone(pathDist)
    local s = M.state
    if s.nextIntersectionDist <= 0 then return false end
    local distToIntersection = s.nextIntersectionDist - pathDist
    if distToIntersection > 0 and distToIntersection < PATH.SAFE_ZONE_BEFORE then
        return true
    end
    if distToIntersection <= 0 and distToIntersection > -(PATH.TURN_ARC_LENGTH + PATH.SAFE_ZONE_AFTER) then
        return true
    end
    return false
end

--- 根据路程距离计算世界坐标（通用版，考虑转弯点）
function M.GetWorldPosForObject(pathDist, laneOffset)
    local s = M.state
    if s.turnExecuting and pathDist >= s.turnStartDist and pathDist <= s.turnEndDist then
        local pos = M.GetTurnPoint(s.turnStartOrigin, s.turnFromHeading, s.turnDir, pathDist - s.turnStartDist, laneOffset)
        return pos
    end

    local localDist = pathDist - s.currentSegmentStartDist
    local fwd = M.GetForwardVector(s.currentHeading)
    local right = M.GetRightVector(s.currentHeading)
    return Vector3(
        s.currentSegmentOrigin.x + fwd.x * localDist + right.x * laneOffset,
        0,
        s.currentSegmentOrigin.z + fwd.z * localDist + right.z * laneOffset
    )
end

--- 初始化路径状态
function M.Init()
    local s = M.state
    s.currentSegmentOrigin = Vector3(0, 0, 0)
    s.currentSegmentStartDist = 0.0
    s.currentHeading = PATH.HEADING_POS_Z
    s.nextIntersectionDist = PATH.FIRST_INTERSECTION_DIST
    s.routeDistance = 0.0
    s.intersectionActive = false
    s.turnChoice = 0
    s.turnExecuting = false
    s.camTurning = false
end

return M
