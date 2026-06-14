-- ============================================================================
-- 外卖冲冲冲 - 摄像机模块
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local PATH = cfg.PATH
local path = require("path")

local M = {}

M.node = nil

---@param scene Scene
---@param playerNode Node
function M.Setup(scene, playerNode)
    M.node = scene:CreateChild("Camera")
    local camera = M.node:CreateComponent("Camera")
    camera.fov = CONFIG.CAM_FOV_BASE
    camera.nearClip = 0.5
    camera.farClip = 200.0

    renderer:SetViewport(0, Viewport:new(scene, camera))

    local pp = playerNode.position
    M.node.position = Vector3(pp.x, pp.y + CONFIG.CAM_OFFSET_Y, pp.z + CONFIG.CAM_OFFSET_Z)
    local lookTarget = Vector3(pp.x, pp.y + 0.5, pp.z + CONFIG.CAM_LOOK_AHEAD)
    M.node:LookAt(lookTarget)
end

function M.Update(dt, playerNode, currentSpeed)
    if not playerNode or not M.node then return end
    local s = path.state

    local pp = playerNode.position
    local targetYaw = path.GetTrackYawAt(s.routeDistance)
    local currentYaw = targetYaw

    if s.camTurning then
        s.camTurnAnimTime = s.camTurnAnimTime + dt
        local t = math.min(1.0, s.camTurnAnimTime / PATH.CAM_TURN_DURATION)
        local smoothT = t * t * (3.0 - 2.0 * t)
        currentYaw = s.camTurnFrom + (s.camTurnTo - s.camTurnFrom) * smoothT
        if t >= 1.0 then
            s.camTurning = false
            currentYaw = s.camTurnTo
        end
    end

    local yawRad = math.rad(currentYaw)
    local camFwdX = math.sin(yawRad)
    local camFwdZ = math.cos(yawRad)

    local camTargetX = pp.x - camFwdX * (-CONFIG.CAM_OFFSET_Z)
    local camTargetZ = pp.z - camFwdZ * (-CONFIG.CAM_OFFSET_Z)
    local camTargetY = pp.y + CONFIG.CAM_OFFSET_Y

    local camPos = M.node.position
    local lerpFactor = math.min(1.0, dt * CONFIG.CAM_SMOOTH)
    local newX = camPos.x + (camTargetX - camPos.x) * lerpFactor
    local newY = camPos.y + (camTargetY - camPos.y) * lerpFactor
    local newZ = camPos.z + (camTargetZ - camPos.z) * lerpFactor
    M.node.position = Vector3(newX, newY, newZ)

    local lookX = pp.x + camFwdX * CONFIG.CAM_LOOK_AHEAD
    local lookZ = pp.z + camFwdZ * CONFIG.CAM_LOOK_AHEAD
    M.node:LookAt(Vector3(lookX, pp.y + 0.5, lookZ))

    local camera = M.node:GetComponent("Camera")
    if camera then
        local speedFactor = (currentSpeed - CONFIG.BASE_SPEED) / (CONFIG.MAX_SPEED - CONFIG.BASE_SPEED)
        local targetFov = CONFIG.CAM_FOV_BASE + (CONFIG.CAM_FOV_MAX - CONFIG.CAM_FOV_BASE) * speedFactor * CONFIG.CAM_FOV_SPEED_FACTOR
        camera.fov = camera.fov + (targetFov - camera.fov) * lerpFactor
    end
end

return M
