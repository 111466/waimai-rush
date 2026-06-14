-- ============================================================================
-- 外卖冲冲冲 - 路口系统模块（基于 RoadGraph）
-- ============================================================================
-- 路口逻辑：检测玩家接近真实路口节点 → 显示方向提示 → 执行转弯
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local rn = require("road_network")
local obstacles = require("obstacles")
local pickup = require("pickup_delivery")

local M = {}

-- 方向箭头视觉节点
M.arrowNodes = {}
M.arrowsVisible = false

-- ============================================================================
-- 创建方向箭头视觉（3个: 左/直/右）
-- ============================================================================

function M.CreateVisuals(scene)
    local mats = require("materials")
    for i = 1, 3 do
        local aNode = scene:CreateChild("Arrow" .. i)
        local am = aNode:CreateComponent("StaticModel")
        am.model = cache:GetResource("Model", "Models/Cone.mdl")
        am.material = mats.arrow
        aNode.scale = Vector3(1.0, 0.3, 1.5)
        aNode.position = Vector3(0, -100, 0)
        M.arrowNodes[i] = aNode
    end
end

-- ============================================================================
-- 显示/隐藏方向箭头
-- ============================================================================

function M.ShowArrows()
    local s = path.state
    if not s.currentEdge then return end

    local targetNodeId = s.currentEdge.toNode
    local targetNode = rn.nodes[targetNodeId]
    if not targetNode then return end

    local nodePos = Vector3(targetNode.worldX, 0, targetNode.worldZ)
    local arrivalHeading = s.currentHeading

    -- 隐藏所有箭头先
    for _, node in ipairs(M.arrowNodes) do
        node.position = Vector3(0, -100, 0)
    end

    -- 为每个可用方向放置箭头
    for _, turn in ipairs(s.availableTurns) do
        local arrowIdx = 0
        if turn.direction == "left" then arrowIdx = 1
        elseif turn.direction == "straight" then arrowIdx = 2
        elseif turn.direction == "right" then arrowIdx = 3
        end

        if arrowIdx > 0 and M.arrowNodes[arrowIdx] then
            local exitFwd = rn.HeadingToForward(turn.heading)
            local arrowDist = 4.0
            local arrowPos = Vector3(
                nodePos.x + exitFwd.x * arrowDist,
                0.8,
                nodePos.z + exitFwd.z * arrowDist
            )
            M.arrowNodes[arrowIdx].position = arrowPos
            M.arrowNodes[arrowIdx].rotation = Quaternion(rn.HeadingToYaw(turn.heading) - 90, Vector3.UP)
        end
    end

    -- 高亮当前选择的箭头（通过Y偏移）
    local choiceIdx = 2  -- 默认直走
    if s.turnChoice == -1 then choiceIdx = 1
    elseif s.turnChoice == 1 then choiceIdx = 3
    end
    if M.arrowNodes[choiceIdx] then
        local pos = M.arrowNodes[choiceIdx].position
        if pos.y > 0 then
            M.arrowNodes[choiceIdx].position = Vector3(pos.x, 1.2, pos.z)
            M.arrowNodes[choiceIdx].scale = Vector3(1.4, 0.4, 2.0)
        end
    end

    M.arrowsVisible = true
end

function M.HideArrows()
    for _, node in ipairs(M.arrowNodes) do
        node.position = Vector3(0, -100, 0)
        node.scale = Vector3(1.0, 0.3, 1.5)
    end
    M.arrowsVisible = false
end

-- ============================================================================
-- 路口逻辑更新
-- ============================================================================

function M.Update()
    local s = path.state

    -- 检测是否到达路口提示区域
    path.CheckIntersection()

    -- 如果路口激活且到达执行点
    if path.CheckExecutePoint() then
        M.ExecuteTurn()
        return
    end

    -- 更新箭头显示
    if s.intersectionActive and not s.turnExecuting then
        M.ShowArrows()
    elseif M.arrowsVisible then
        M.HideArrows()
    end
end

-- ============================================================================
-- 执行转弯
-- ============================================================================

function M.ExecuteTurn()
    local s = path.state

    -- 清除前方障碍物
    obstacles.ClearAll()

    -- 清除取件/送件
    pickup.pickupActive = false
    if pickup.pickupNode then
        pickup.pickupNode.position = Vector3(0, -100, 0)
    end
    pickup.deliveryActive = false
    if pickup.deliveryNode then
        pickup.deliveryNode.position = Vector3(0, -100, 0)
    end

    -- 奖惩逻辑
    if pickup.hasPackage then
        local correctDir = s.intersectionHintDir
        if s.turnChoice == correctDir then
            pickup.timeRemaining = pickup.timeRemaining + CONFIG.CORRECT_TURN_BONUS
        else
            pickup.timeRemaining = math.max(2.0, pickup.timeRemaining - CONFIG.WRONG_TURN_PENALTY)
        end
    end

    -- 设置 edge progress 到末端，触发 path 的转弯逻辑
    s.edgeProgress = 1.0
    s.edgeDistance = s.currentEdge.length
    path.ExecuteTurnAtNode()

    -- 隐藏箭头
    M.HideArrows()
end

-- ============================================================================
-- 隐藏（重置用）
-- ============================================================================

function M.Hide()
    M.HideArrows()
end

-- 兼容接口（input.lua 调用 intersection.Show()）
function M.Show()
    M.ShowArrows()
end

return M
