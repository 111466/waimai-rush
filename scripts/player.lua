-- ============================================================================
-- 外卖冲冲冲 - 玩家模块（基于 RoadGraph）
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local mats = require("materials")

local M = {}

-- 玩家节点
M.node = nil
M.packageVisualNode = nil
M.shadowNode = nil

-- 变道动画
M.laneChanging = false
M.laneChangeFrom = 0.0
M.laneChangeTo = 0.0
M.laneChangeTime = 0.0
M.laneChangeFromLane = 2
M.laneChangeToLane = 2
M.currentLaneX = CONFIG.LANE_X[2]

-- 跳跃
M.isJumping = false
M.jumpTime = 0.0
M.jumpBuffered = false

-- 下滑
M.isSliding = false
M.slideTime = 0.0
M.slideBuffered = false

-- 速度/距离
M.currentSpeed = CONFIG.BASE_SPEED
M.distanceTraveled = 0.0

-- ============================================================================
-- 创建玩家
-- ============================================================================

function M.Create(scene)
    M.node = scene:CreateChild("Player")
    M.node.position = Vector3(0, CONFIG.PLAYER_GROUND_Y, 0)

    local body = M.node:CreateChild("Body")
    local bm = body:CreateComponent("StaticModel")
    bm.model = cache:GetResource("Model", "Models/Cylinder.mdl")
    bm.material = mats.CreatePBRMaterial(Color(0.3, 0.6, 0.9, 1.0), 0.1, 0.6)
    body.scale = Vector3(0.6, 1.0, 0.6)
    body.position = Vector3(0, 0.5, 0)

    local head = M.node:CreateChild("Head")
    local hm = head:CreateComponent("StaticModel")
    hm.model = cache:GetResource("Model", "Models/Sphere.mdl")
    hm.material = mats.CreatePBRMaterial(Color(1.0, 0.85, 0.7, 1.0), 0.0, 0.8)
    head.scale = Vector3(0.45, 0.45, 0.45)
    head.position = Vector3(0, 1.25, 0)

    local box = M.node:CreateChild("DeliveryBox")
    local boxm = box:CreateComponent("StaticModel")
    boxm.model = cache:GetResource("Model", "Models/Box.mdl")
    boxm.material = mats.CreatePBRMaterial(Color(0.2, 0.7, 0.3, 1.0), 0.1, 0.7)
    box.scale = Vector3(0.5, 0.5, 0.3)
    box.position = Vector3(0, 0.9, -0.3)
    M.packageVisualNode = box
    M.packageVisualNode.enabled = false

    local hat = M.node:CreateChild("Hat")
    local hatm = hat:CreateComponent("StaticModel")
    hatm.model = cache:GetResource("Model", "Models/Cylinder.mdl")
    hatm.material = mats.CreatePBRMaterial(Color(1.0, 0.8, 0.1, 1.0), 0.0, 0.7)
    hat.scale = Vector3(0.5, 0.12, 0.5)
    hat.position = Vector3(0, 1.5, 0)

    local shadow = scene:CreateChild("PlayerShadow")
    local sm = shadow:CreateComponent("StaticModel")
    sm.model = cache:GetResource("Model", "Models/Cylinder.mdl")
    sm.material = mats.shadow
    shadow.scale = Vector3(0.55, 0.015, 0.38)
    shadow.position = Vector3(0, CONFIG.PLAYER_GROUND_Y + 0.012, 0)
    M.shadowNode = shadow
end

-- ============================================================================
-- 变道
-- ============================================================================

function M.StartLaneChange(targetLane)
    if M.laneChanging then return end
    if targetLane < 1 or targetLane > 3 then return end

    M.laneChangeFromLane = CONFIG.currentLane
    M.laneChangeToLane = targetLane
    M.laneChangeFrom = CONFIG.LANE_X[CONFIG.currentLane]
    M.laneChangeTo = CONFIG.LANE_X[targetLane]
    CONFIG.currentLane = targetLane
    M.laneChangeTime = 0.0
    M.laneChanging = true
end

function M.UpdateLaneChange(dt)
    if not M.laneChanging then return end

    M.laneChangeTime = M.laneChangeTime + dt
    local t = math.min(1.0, M.laneChangeTime / CONFIG.LANE_CHANGE_DURATION)

    if t >= 1.0 then
        M.laneChanging = false
        M.currentLaneX = M.laneChangeTo
    end
end

function M.BounceBackFromSideCollision()
    if not M.laneChanging then return end

    local returnLane = M.laneChangeFromLane
    M.laneChangeFrom = M.currentLaneX
    M.laneChangeTo = CONFIG.LANE_X[returnLane]
    M.laneChangeToLane = returnLane
    CONFIG.currentLane = returnLane
    M.laneChangeTime = 0.0
    M.laneChanging = true
end

-- ============================================================================
-- 跳跃 / 下滑
-- ============================================================================

function M.StartJump()
    if M.isJumping or M.isSliding then
        M.jumpBuffered = true
        return
    end
    M.isJumping = true
    M.jumpTime = 0.0
end

function M.StartSlide()
    if M.isSliding or M.isJumping then
        M.slideBuffered = true
        return
    end
    M.isSliding = true
    M.slideTime = 0.0
end

function M.UpdateJumpSlide(dt)
    local jumpY = 0.0

    if M.isJumping then
        M.jumpTime = M.jumpTime + dt
        if M.jumpTime >= CONFIG.JUMP_DURATION then
            M.isJumping = false
            M.jumpTime = 0.0
            -- 清除过期的 slideBuffered
            if M.slideBuffered then
                M.slideBuffered = false
                M.StartSlide()
            end
        else
            local t = M.jumpTime / CONFIG.JUMP_DURATION
            jumpY = 4.0 * CONFIG.JUMP_HEIGHT * t * (1.0 - t)
        end
    end

    if M.isSliding then
        M.slideTime = M.slideTime + dt
        if M.slideTime >= CONFIG.SLIDE_DURATION then
            M.isSliding = false
            M.slideTime = 0.0
            -- 清除过期的 jumpBuffered
            if M.jumpBuffered then
                M.jumpBuffered = false
                M.StartJump()
            end
        end
        -- 下滑：整体压低（Body压扁 + Head/Hat/DeliveryBox 降低）
        local bodyNode = M.node:GetChild("Body")
        if bodyNode then
            bodyNode.scale = Vector3(0.8, 0.5, 0.6)
            bodyNode.position = Vector3(0, 0.25, 0)
        end
        local headNode = M.node:GetChild("Head")
        if headNode then
            headNode.position = Vector3(0, 0.6, 0)  -- 从 1.25 降到 0.6
        end
        local hatNode = M.node:GetChild("Hat")
        if hatNode then
            hatNode.position = Vector3(0, 0.85, 0)  -- 从 1.5 降到 0.85
        end
        local boxNode = M.node:GetChild("DeliveryBox")
        if boxNode then
            boxNode.position = Vector3(0, 0.45, -0.3)  -- 从 0.9 降到 0.45
        end
    else
        -- 恢复所有子节点的正常位置
        local bodyNode = M.node:GetChild("Body")
        if bodyNode then
            bodyNode.scale = Vector3(0.6, 1.0, 0.6)
            bodyNode.position = Vector3(0, 0.5, 0)
        end
        local headNode = M.node:GetChild("Head")
        if headNode then
            headNode.position = Vector3(0, 1.25, 0)
        end
        local hatNode = M.node:GetChild("Hat")
        if hatNode then
            hatNode.position = Vector3(0, 1.5, 0)
        end
        local boxNode = M.node:GetChild("DeliveryBox")
        if boxNode then
            boxNode.position = Vector3(0, 0.9, -0.3)
        end
    end

    return jumpY
end

function M.GetJumpHeight()
    if not M.isJumping then
        return 0.0
    end

    local t = math.max(0.0, math.min(1.0, M.jumpTime / CONFIG.JUMP_DURATION))
    return 4.0 * CONFIG.JUMP_HEIGHT * t * (1.0 - t)
end

-- ============================================================================
-- 速度
-- ============================================================================

function M.UpdateSpeed()
    local speedIncrease = M.distanceTraveled / CONFIG.SPEED_DISTANCE_FACTOR
    M.currentSpeed = math.min(CONFIG.MAX_SPEED, CONFIG.BASE_SPEED + speedIncrease)
end

-- ============================================================================
-- 更新玩家世界位置（每帧调用）
-- ============================================================================

function M.UpdatePosition(jumpY)
    local laneX = CONFIG.LANE_X[CONFIG.currentLane]
    if M.laneChanging then
        local t = math.min(1.0, M.laneChangeTime / CONFIG.LANE_CHANGE_DURATION)
        local smoothT = t * t * (3.0 - 2.0 * t)
        laneX = M.laneChangeFrom + (M.laneChangeTo - M.laneChangeFrom) * smoothT
    end
    M.currentLaneX = laneX

    local worldPos = path.GetWorldPosition(laneX)
    M.node.position = Vector3(worldPos.x, CONFIG.PLAYER_GROUND_Y + jumpY, worldPos.z)

    -- 朝向跟随道路方向
    local yaw = path.GetCurrentYaw()
    M.node.rotation = Quaternion(yaw, Vector3.UP)

    if M.shadowNode then
        local jumpFactor = 0.0
        if CONFIG.JUMP_HEIGHT > 0 then
            jumpFactor = math.min(1.0, jumpY / CONFIG.JUMP_HEIGHT)
        end
        local shadowScale = 1.0 - jumpFactor * 0.35
        M.shadowNode.position = Vector3(worldPos.x, CONFIG.PLAYER_GROUND_Y + 0.012, worldPos.z)
        M.shadowNode.rotation = Quaternion(yaw, Vector3.UP)
        M.shadowNode.scale = Vector3(0.55 * shadowScale, 0.015, 0.38 * shadowScale)
    end
end

function M.GetCollisionState()
    return {
        laneChanging = M.laneChanging,
        fromLane = M.laneChangeFromLane,
        toLane = M.laneChangeToLane,
        laneX = M.currentLaneX,
        jumpY = M.GetJumpHeight(),
    }
end

-- ============================================================================
-- 重置
-- ============================================================================

function M.Reset()
    M.distanceTraveled = 0.0
    M.currentSpeed = CONFIG.BASE_SPEED
    CONFIG.currentLane = 2
    M.laneChanging = false
    M.laneChangeFromLane = 2
    M.laneChangeToLane = 2
    M.laneChangeFrom = CONFIG.LANE_X[2]
    M.laneChangeTo = CONFIG.LANE_X[2]
    M.laneChangeTime = 0.0
    M.currentLaneX = CONFIG.LANE_X[2]
    M.isJumping = false
    M.jumpTime = 0.0
    M.jumpBuffered = false
    M.isSliding = false
    M.slideTime = 0.0
    M.slideBuffered = false
    M.node.position = Vector3(0, CONFIG.PLAYER_GROUND_Y, 0)
    M.node.rotation = Quaternion(0, Vector3.UP)
    if M.shadowNode then
        M.shadowNode.position = Vector3(0, CONFIG.PLAYER_GROUND_Y + 0.012, 0)
        M.shadowNode.rotation = Quaternion(0, Vector3.UP)
        M.shadowNode.scale = Vector3(0.55, 0.015, 0.38)
    end
end

return M
