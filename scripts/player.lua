-- ============================================================================
-- 外卖冲冲冲 - 玩家模块（并行道路版）
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local mats = require("materials")

local M = {}

-- 玩家节点
M.node = nil
M.packageVisualNode = nil

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
    M.node.position = Vector3(0, 0, 0)

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
            if M.jumpBuffered then
                M.jumpBuffered = false
                M.StartJump()
            end
        end
        local bodyNode = M.node:GetChild("Body")
        if bodyNode then
            bodyNode.scale = Vector3(0.8, 0.5, 0.6)
            bodyNode.position = Vector3(0, 0.25, 0)
        end
        local headNode = M.node:GetChild("Head")
        if headNode then headNode.position = Vector3(0, 0.6, 0) end
        local hatNode = M.node:GetChild("Hat")
        if hatNode then hatNode.position = Vector3(0, 0.85, 0) end
        local boxNode = M.node:GetChild("DeliveryBox")
        if boxNode then boxNode.position = Vector3(0, 0.45, -0.3) end
    else
        local bodyNode = M.node:GetChild("Body")
        if bodyNode then
            bodyNode.scale = Vector3(0.6, 1.0, 0.6)
            bodyNode.position = Vector3(0, 0.5, 0)
        end
        local headNode = M.node:GetChild("Head")
        if headNode then headNode.position = Vector3(0, 1.25, 0) end
        local hatNode = M.node:GetChild("Hat")
        if hatNode then hatNode.position = Vector3(0, 1.5, 0) end
        local boxNode = M.node:GetChild("DeliveryBox")
        if boxNode then boxNode.position = Vector3(0, 0.9, -0.3) end
    end

    return jumpY
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
    -- 位置直接由 path 模块决定（已含并行道路偏移）
    local worldPos = path.GetWorldPosition()
    M.node.position = Vector3(worldPos.x, jumpY, worldPos.z)

    -- 朝向跟随道路方向
    local yaw = path.GetCurrentYaw()
    M.node.rotation = Quaternion(yaw, Vector3.UP)
end

-- ============================================================================
-- 重置
-- ============================================================================

function M.Reset()
    M.distanceTraveled = 0.0
    M.currentSpeed = CONFIG.BASE_SPEED
    M.isJumping = false
    M.jumpTime = 0.0
    M.jumpBuffered = false
    M.isSliding = false
    M.slideTime = 0.0
    M.slideBuffered = false
    M.node.position = Vector3(0, 0, 0)
    M.node.rotation = Quaternion(0, Vector3.UP)
end

return M
