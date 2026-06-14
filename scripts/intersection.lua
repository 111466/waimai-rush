-- ============================================================================
-- 外卖冲冲冲 - 路口系统模块（基于 RoadGraph）
-- ============================================================================
-- 路口逻辑简化：只负责显示/隐藏方向箭头
-- 转弯执行完全由 path.Advance() 内部触发，不再由本模块强制
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local rn = require("road_network")

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

    -- 隐藏所有箭头先
    for _, node in ipairs(M.arrowNodes) do
        node.position = Vector3(0, -100, 0)
        node.scale = Vector3(1.0, 0.3, 1.5)
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

    -- 高亮当前选择的箭头（通过Y偏移和放大）
    if s.hasTurnChoice then
        local choiceIdx = 2  -- 直走
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
-- 路口逻辑更新（只负责检测和显示箭头）
-- ============================================================================

function M.Update()
    local s = path.state

    -- 检测是否到达路口提示区域
    path.CheckIntersection()

    -- 更新箭头显示
    if s.intersectionActive and not s.turnExecuting then
        M.ShowArrows()
    elseif M.arrowsVisible then
        M.HideArrows()
    end
end

-- ============================================================================
-- 隐藏（重置用）
-- ============================================================================

function M.Hide()
    M.HideArrows()
end

-- 兼容接口
function M.Show()
    M.ShowArrows()
end

return M
