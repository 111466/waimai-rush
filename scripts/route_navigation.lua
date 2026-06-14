-- ============================================================================
-- 外卖冲冲冲 - 配送路线导航模块
-- ============================================================================
-- 基于 RoadGraph 做最短路线搜索，维护当前配送目标、推荐路线和错路后的自动重规划。
-- ============================================================================

local rn = require("road_network")

local M = {}

M.targetEdgeId = 0
M.targetEdgeDist = 0.0
M.routeEdges = {}
M.distanceRemaining = 0.0
M.replanMessageTimer = 0.0
M.replanMessage = ""
M.routeUnreachable = false
M.MINIMAP_PLAYER_EDGE_STEPS = 16

local REPLAN_MESSAGE_TIME = 1.4

-- ============================================================================
-- 基础工具
-- ============================================================================

local function CopyAndAppend(list, value)
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    out[#out + 1] = value
    return out
end

local function StateKey(nodeId, arrivalHeading)
    return tostring(nodeId) .. ":" .. tostring(arrivalHeading)
end

function M.MakeSegmentKey(a, b)
    if a < b then
        return "e" .. a .. "_" .. b
    end
    return "e" .. b .. "_" .. a
end

function M.MakeNodeSlot(nodeId)
    return "n" .. nodeId
end

function M.MakeEdgeSlot(edge)
    if not edge then return nil end
    return M.MakeSegmentKey(edge.fromNode, edge.toNode)
end

function M.MakePlayerEdgeSlot(edge, stepIndex)
    local key = M.MakeEdgeSlot(edge)
    if not key then return nil end
    return "p" .. key .. "_" .. tostring(stepIndex)
end

local function HeadingToChoice(arrivalHeading, exitHeading)
    if exitHeading == arrivalHeading then
        return 0
    elseif exitHeading == rn.TurnLeft(arrivalHeading) then
        return -1
    elseif exitHeading == rn.TurnRight(arrivalHeading) then
        return 1
    end
    return nil
end

local function ChoiceToText(choice)
    if choice == -1 then return "左转" end
    if choice == 1 then return "右转" end
    return "直走"
end

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function M.HasTarget()
    return M.targetEdgeId ~= 0 and rn.edges[M.targetEdgeId] ~= nil
end

function M.HasRoute()
    return M.HasTarget() and #M.routeEdges > 0 and not M.routeUnreachable
end

function M.ClearTarget()
    M.targetEdgeId = 0
    M.targetEdgeDist = 0.0
    M.routeEdges = {}
    M.distanceRemaining = 0.0
    M.replanMessageTimer = 0.0
    M.replanMessage = ""
    M.routeUnreachable = false
end

function M.Reset()
    M.ClearTarget()
end

-- ============================================================================
-- 路线搜索
-- ============================================================================

--- 从当前 edge 出发，搜索到目标 edge 的最短路线。
--- 返回的 routeEdges 会包含 currentEdge.id 和 targetEdgeId。
function M.FindRouteFromEdge(currentEdge, targetEdgeId)
    if not currentEdge then return nil end
    if not rn.edges[targetEdgeId] then return nil end

    if currentEdge.id == targetEdgeId then
        return { currentEdge.id }
    end

    local queue = {
        {
            nodeId = currentEdge.toNode,
            arrivalHeading = currentEdge.heading,
            route = { currentEdge.id },
        }
    }
    local head = 1
    local visited = {}
    visited[StateKey(currentEdge.toNode, currentEdge.heading)] = true

    while head <= #queue do
        local item = queue[head]
        head = head + 1

        local turns = rn.GetAvailableTurns(item.nodeId, item.arrivalHeading)
        for _, turn in ipairs(turns) do
            local edge = turn.edge
            if edge then
                local nextRoute = CopyAndAppend(item.route, edge.id)
                if edge.id == targetEdgeId then
                    return nextRoute
                end

                local key = StateKey(edge.toNode, edge.heading)
                if not visited[key] then
                    visited[key] = true
                    queue[#queue + 1] = {
                        nodeId = edge.toNode,
                        arrivalHeading = edge.heading,
                        route = nextRoute,
                    }
                end
            end
        end
    end

    return nil
end

function M.GetReachableTargetEdges(currentEdge, minHops, maxHops)
    local candidates = {}
    if not currentEdge then return candidates end

    for edgeId = 1, #rn.edges do
        local edge = rn.edges[edgeId]
        if edge and edge.id ~= currentEdge.id then
            local route = M.FindRouteFromEdge(currentEdge, edge.id)
            if route then
                local hops = #route - 1
                if hops >= minHops and hops <= maxHops then
                    candidates[#candidates + 1] = {
                        edge = edge,
                        edgeId = edge.id,
                        hops = hops,
                        route = route,
                    }
                end
            end
        end
    end

    return candidates
end

local function FindRouteIndex(edgeId)
    for i = 1, #M.routeEdges do
        if M.routeEdges[i] == edgeId then
            return i
        end
    end
    return nil
end

local function TrimRouteToIndex(index)
    if not index or index <= 1 then return end

    local trimmed = {}
    for i = index, #M.routeEdges do
        trimmed[#trimmed + 1] = M.routeEdges[i]
    end
    M.routeEdges = trimmed
end

local function EstimateRemainingDistance(pathState)
    if not pathState or not pathState.currentEdge or not M.HasTarget() then
        return 0.0
    end

    local currentEdge = pathState.currentEdge
    local effectiveLen = rn.GetEdgeEffectiveLength()

    if currentEdge.id == M.targetEdgeId then
        return math.max(0.0, M.targetEdgeDist - pathState.edgeDistance)
    end

    local distance = 0.0
    local foundCurrent = false

    for _, edgeId in ipairs(M.routeEdges) do
        if edgeId == currentEdge.id then
            foundCurrent = true
            distance = distance + math.max(0.0, effectiveLen - pathState.edgeDistance)
        elseif foundCurrent then
            if edgeId == M.targetEdgeId then
                distance = distance + M.targetEdgeDist
                return distance
            else
                distance = distance + effectiveLen
            end
        end
    end

    return distance
end

function M.Recalculate(pathState, showMessage)
    if not pathState or not pathState.currentEdge or not M.HasTarget() then
        return false
    end

    local route = M.FindRouteFromEdge(pathState.currentEdge, M.targetEdgeId)
    if route then
        M.routeEdges = route
        M.routeUnreachable = false
        if showMessage then
            M.replanMessage = "已重新规划路线"
            M.replanMessageTimer = REPLAN_MESSAGE_TIME
        end
        M.distanceRemaining = EstimateRemainingDistance(pathState)
        return true
    end

    M.routeEdges = {}
    M.routeUnreachable = true
    if showMessage then
        M.replanMessage = "目标不可达，正在更换目标"
        M.replanMessageTimer = REPLAN_MESSAGE_TIME
    end
    return false
end

function M.SetTarget(edgeId, edgeDist, pathState)
    if not rn.edges[edgeId] then
        M.ClearTarget()
        return false
    end

    M.targetEdgeId = edgeId
    M.targetEdgeDist = edgeDist or 0.0
    M.routeEdges = {}
    M.routeUnreachable = false
    M.replanMessage = ""
    M.replanMessageTimer = 0.0

    return M.Recalculate(pathState, false)
end

function M.NeedsNewTarget()
    return M.HasTarget() and M.routeUnreachable
end

function M.Update(pathState, dt)
    if M.replanMessageTimer > 0.0 then
        M.replanMessageTimer = math.max(0.0, M.replanMessageTimer - (dt or 0.0))
    end

    if not M.HasTarget() then
        return
    end
    if not pathState or not pathState.currentEdge then
        return
    end

    if #M.routeEdges == 0 then
        M.Recalculate(pathState, false)
        return
    end

    local currentEdgeId = pathState.currentEdge.id
    local routeIndex = FindRouteIndex(currentEdgeId)
    if routeIndex then
        TrimRouteToIndex(routeIndex)
        M.routeUnreachable = false
    else
        M.Recalculate(pathState, true)
    end

    M.distanceRemaining = EstimateRemainingDistance(pathState)
end

-- ============================================================================
-- UI 数据
-- ============================================================================

local function FindNextRouteEdgeFromNode(nodeId)
    for _, edgeId in ipairs(M.routeEdges) do
        local edge = rn.edges[edgeId]
        if edge and edge.fromNode == nodeId then
            return edge
        end
    end
    return nil
end

local function GetPlayerEdgeSlot(pathState)
    local edge = pathState and pathState.currentEdge
    if not edge then return nil end

    local effectiveLen = rn.GetEdgeEffectiveLength()
    local effectiveDist = Clamp(pathState.edgeDistance or 0.0, 0.0, effectiveLen)
    local actualDist = rn.INTERSECTION_HALF_SIZE + effectiveDist
    local progress = Clamp(actualDist / edge.length, 0.0, 1.0)

    -- UI 端按较小 nodeId -> 较大 nodeId 的规范方向预生成进度点。
    if edge.fromNode > edge.toNode then
        progress = 1.0 - progress
    end

    local step = math.floor(progress * M.MINIMAP_PLAYER_EDGE_STEPS + 0.5)
    step = Clamp(step, 0, M.MINIMAP_PLAYER_EDGE_STEPS)
    return M.MakePlayerEdgeSlot(edge, step)
end

function M.GetSuggestedTurn(pathState)
    if not pathState or not M.HasRoute() then
        return nil
    end

    local nodeId = 0
    local arrivalHeading = 0

    if pathState.insideIntersection then
        nodeId = pathState.intersectionNodeId
        arrivalHeading = pathState.intersectionArrivalHeading
    elseif pathState.intersectionActive and pathState.currentEdge then
        nodeId = pathState.currentEdge.toNode
        arrivalHeading = pathState.currentHeading
    else
        return nil
    end

    local edge = FindNextRouteEdgeFromNode(nodeId)
    if not edge then return nil end

    local choice = HeadingToChoice(arrivalHeading, edge.heading)
    if choice == nil then return nil end

    return {
        choice = choice,
        text = ChoiceToText(choice),
        edgeId = edge.id,
        heading = edge.heading,
    }
end

function M.GetMinimapData(pathState)
    local routeSegments = {}
    if M.HasRoute() then
        for _, edgeId in ipairs(M.routeEdges) do
            local edge = rn.edges[edgeId]
            local key = M.MakeEdgeSlot(edge)
            if key then
                routeSegments[key] = true
            end
        end
    end

    local playerSlot = nil
    if pathState then
        if pathState.insideIntersection and pathState.intersectionNodeId ~= 0 then
            playerSlot = M.MakeNodeSlot(pathState.intersectionNodeId)
        elseif pathState.currentEdge then
            playerSlot = GetPlayerEdgeSlot(pathState)
        end
    end

    local targetSlot = nil
    if M.HasTarget() then
        targetSlot = M.MakeEdgeSlot(rn.edges[M.targetEdgeId])
    end

    local message = ""
    if M.replanMessageTimer > 0.0 then
        message = M.replanMessage
    elseif M.HasTarget() then
        message = string.format("目标 %.0fm", M.distanceRemaining)
    else
        message = "等待订单"
    end

    return {
        active = M.HasTarget(),
        routeSegments = routeSegments,
        playerSlot = playerSlot,
        targetSlot = targetSlot,
        message = message,
        transientMessage = M.replanMessageTimer > 0.0,
        suggested = M.GetSuggestedTurn(pathState),
        distanceRemaining = M.distanceRemaining,
    }
end

return M
