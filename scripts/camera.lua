-- ============================================================================
-- 外卖冲冲冲 - 摄像机模块（基于 RoadGraph）
-- ============================================================================
-- 摄像机直接跟随 path.GetCurrentYaw()，使用角度平滑插值
-- 不再有独立的转弯动画定时器
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")

local M = {}

M.node = nil
M.currentYaw = 0.0  -- 当前摄像机 yaw（平滑跟随用）

local DEBUG_LIMITS = {
    offsetY = { min = 3.0, max = 12.0 },
    offsetZ = { min = -16.0, max = -4.0 },
    lookAhead = { min = 2.0, max = 12.0 },
    yawOffset = { min = -45.0, max = 45.0 },
    pitchOffset = { min = -2.0, max = 2.0 },
    fovBase = { min = 35.0, max = 75.0 },
    fovMax = { min = 35.0, max = 85.0 },
}

local DEBUG_DEFAULTS = {
    offsetY = CONFIG.CAM_OFFSET_Y,
    offsetZ = CONFIG.CAM_OFFSET_Z,
    lookAhead = CONFIG.CAM_LOOK_AHEAD,
    yawOffset = CONFIG.CAM_YAW_OFFSET or 0.0,
    pitchOffset = CONFIG.CAM_PITCH_OFFSET or 0.0,
    fovBase = CONFIG.CAM_FOV_BASE,
    fovMax = CONFIG.CAM_FOV_MAX,
}

M.debugParams = {
    offsetY = DEBUG_DEFAULTS.offsetY,
    offsetZ = DEBUG_DEFAULTS.offsetZ,
    lookAhead = DEBUG_DEFAULTS.lookAhead,
    yawOffset = DEBUG_DEFAULTS.yawOffset,
    pitchOffset = DEBUG_DEFAULTS.pitchOffset,
    fovBase = DEBUG_DEFAULTS.fovBase,
    fovMax = DEBUG_DEFAULTS.fovMax,
}

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function ClampDebugParam(key, value)
    local limit = DEBUG_LIMITS[key]
    if not limit then
        return value
    end
    return Clamp(value, limit.min, limit.max)
end

local function KeepFovRangeValid()
    M.debugParams.fovBase = ClampDebugParam("fovBase", M.debugParams.fovBase)
    M.debugParams.fovMax = ClampDebugParam("fovMax", M.debugParams.fovMax)
    if M.debugParams.fovMax < M.debugParams.fovBase then
        M.debugParams.fovMax = M.debugParams.fovBase
    end
end

local function GetForwardFromYaw(yaw)
    local yawRad = math.rad(yaw)
    return math.sin(yawRad), math.cos(yawRad)
end

--- 角度差归一化到 [-180, 180]
local function NormalizeAngle(angle)
    while angle > 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    return angle
end

---@param scene Scene
---@param playerNode Node
function M.Setup(scene, playerNode)
    M.node = scene:CreateChild("Camera")
    local camera = M.node:CreateComponent("Camera")
    camera.fov = M.debugParams.fovBase
    camera.nearClip = 0.5
    camera.farClip = 250.0

    renderer:SetViewport(0, Viewport:new(scene, camera))

    -- 初始化 yaw 到当前路径方向
    M.currentYaw = path.GetCurrentYaw()

    local pp = playerNode.position
    local baseFwdX, baseFwdZ = GetForwardFromYaw(M.currentYaw)
    local viewFwdX, viewFwdZ = GetForwardFromYaw(M.currentYaw + M.debugParams.yawOffset)
    local backDist = -M.debugParams.offsetZ

    M.node.position = Vector3(
        pp.x - viewFwdX * backDist,
        pp.y + M.debugParams.offsetY,
        pp.z - viewFwdZ * backDist
    )
    local lookTarget = Vector3(
        pp.x + baseFwdX * M.debugParams.lookAhead,
        pp.y + 0.5 + M.debugParams.pitchOffset,
        pp.z + baseFwdZ * M.debugParams.lookAhead
    )
    M.node:LookAt(lookTarget)
end

function M.Update(dt, playerNode, currentSpeed)
    if not playerNode or not M.node then return end

    local pp = playerNode.position

    -- 直接跟随 path.GetCurrentYaw()，使用平滑插值
    local targetYaw = path.GetCurrentYaw()
    local yawDiff = NormalizeAngle(targetYaw - M.currentYaw)

    -- 平滑系数：转弯时也是连续角度变化，只需平滑跟随即可
    local yawLerp = math.min(1.0, dt * CONFIG.CAM_SMOOTH)
    M.currentYaw = M.currentYaw + yawDiff * yawLerp

    -- 根据 yaw 计算摄像机位置（在玩家后方）
    local baseFwdX, baseFwdZ = GetForwardFromYaw(M.currentYaw)
    local viewFwdX, viewFwdZ = GetForwardFromYaw(M.currentYaw + M.debugParams.yawOffset)

    -- CAM_OFFSET_Z 是负值（在玩家身后），取反得到后方偏移量
    local backDist = -M.debugParams.offsetZ
    local camTargetX = pp.x - viewFwdX * backDist
    local camTargetZ = pp.z - viewFwdZ * backDist
    local camTargetY = pp.y + M.debugParams.offsetY

    -- 位置平滑跟随
    local camPos = M.node.position
    local lerpFactor = math.min(1.0, dt * CONFIG.CAM_SMOOTH)
    local newX = camPos.x + (camTargetX - camPos.x) * lerpFactor
    local newY = camPos.y + (camTargetY - camPos.y) * lerpFactor
    local newZ = camPos.z + (camTargetZ - camPos.z) * lerpFactor
    M.node.position = Vector3(newX, newY, newZ)

    -- 摄像机看向玩家前方
    local lookX = pp.x + baseFwdX * M.debugParams.lookAhead
    local lookZ = pp.z + baseFwdZ * M.debugParams.lookAhead
    M.node:LookAt(Vector3(lookX, pp.y + 0.5 + M.debugParams.pitchOffset, lookZ))

    -- FOV 随速度变化
    local camera = M.node:GetComponent("Camera")
    if camera then
        local speedFactor = (currentSpeed - CONFIG.BASE_SPEED) / (CONFIG.MAX_SPEED - CONFIG.BASE_SPEED)
        speedFactor = math.max(0, math.min(1, speedFactor))
        local targetFov = M.debugParams.fovBase + (M.debugParams.fovMax - M.debugParams.fovBase) * speedFactor * CONFIG.CAM_FOV_SPEED_FACTOR
        camera.fov = camera.fov + (targetFov - camera.fov) * lerpFactor
    end
end

function M.GetDebugParams()
    return {
        offsetY = M.debugParams.offsetY,
        offsetZ = M.debugParams.offsetZ,
        lookAhead = M.debugParams.lookAhead,
        yawOffset = M.debugParams.yawOffset,
        pitchOffset = M.debugParams.pitchOffset,
        fovBase = M.debugParams.fovBase,
        fovMax = M.debugParams.fovMax,
    }
end

function M.AdjustDebugParam(key, delta)
    if M.debugParams[key] == nil or not DEBUG_LIMITS[key] then
        return nil
    end

    M.debugParams[key] = ClampDebugParam(key, M.debugParams[key] + delta)
    KeepFovRangeValid()
    return M.debugParams[key]
end

function M.ResetDebugParams()
    for key, value in pairs(DEBUG_DEFAULTS) do
        M.debugParams[key] = value
    end
    KeepFovRangeValid()
end

function M.GetCurrentFov()
    if not M.node then
        return M.debugParams.fovBase
    end

    local camera = M.node:GetComponent("Camera")
    if not camera then
        return M.debugParams.fovBase
    end
    return camera.fov
end

return M
