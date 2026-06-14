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
    camera.fov = CONFIG.CAM_FOV_BASE
    camera.nearClip = 0.5
    camera.farClip = 250.0

    renderer:SetViewport(0, Viewport:new(scene, camera))

    -- 初始化 yaw 到当前路径方向
    M.currentYaw = path.GetCurrentYaw()

    local pp = playerNode.position
    M.node.position = Vector3(pp.x, pp.y + CONFIG.CAM_OFFSET_Y, pp.z + CONFIG.CAM_OFFSET_Z)
    local lookTarget = Vector3(pp.x, pp.y + 0.5, pp.z + CONFIG.CAM_LOOK_AHEAD)
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
    local yawRad = math.rad(M.currentYaw)
    local camFwdX = math.sin(yawRad)
    local camFwdZ = math.cos(yawRad)

    -- CAM_OFFSET_Z 是负值（在玩家身后），取反得到后方偏移量
    local backDist = -CONFIG.CAM_OFFSET_Z
    local camTargetX = pp.x - camFwdX * backDist
    local camTargetZ = pp.z - camFwdZ * backDist
    local camTargetY = pp.y + CONFIG.CAM_OFFSET_Y

    -- 位置平滑跟随
    local camPos = M.node.position
    local lerpFactor = math.min(1.0, dt * CONFIG.CAM_SMOOTH)
    local newX = camPos.x + (camTargetX - camPos.x) * lerpFactor
    local newY = camPos.y + (camTargetY - camPos.y) * lerpFactor
    local newZ = camPos.z + (camTargetZ - camPos.z) * lerpFactor
    M.node.position = Vector3(newX, newY, newZ)

    -- 摄像机看向玩家前方
    local lookX = pp.x + camFwdX * CONFIG.CAM_LOOK_AHEAD
    local lookZ = pp.z + camFwdZ * CONFIG.CAM_LOOK_AHEAD
    M.node:LookAt(Vector3(lookX, pp.y + 0.5, lookZ))

    -- FOV 随速度变化
    local camera = M.node:GetComponent("Camera")
    if camera then
        local speedFactor = (currentSpeed - CONFIG.BASE_SPEED) / (CONFIG.MAX_SPEED - CONFIG.BASE_SPEED)
        speedFactor = math.max(0, math.min(1, speedFactor))
        local targetFov = CONFIG.CAM_FOV_BASE + (CONFIG.CAM_FOV_MAX - CONFIG.CAM_FOV_BASE) * speedFactor * CONFIG.CAM_FOV_SPEED_FACTOR
        camera.fov = camera.fov + (targetFov - camera.fov) * lerpFactor
    end
end

return M
