-- ============================================================================
-- 外卖冲冲冲 - 路径系统模块（并行道路 + 3x3 路口区域）
-- ============================================================================
-- 状态机：
--   onEdge → 沿某条并行 edge 前进
--   insideIntersection → 进入路口 3x3 区域（玩家位置决定出口）
--   exitIntersection → 进入新的并行 edge
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local rn = require("road_network")

local M = {}

-- ============================================================================
-- 玩家在路网中的运行时状态
-- ============================================================================
M.state = {
    -- 当前所在边（在 onEdge 阶段有效）
    currentEdge = nil,       -- edge 对象（含 laneIndex）
    edgeDistance = 0.0,      -- 有效区段内走的距离

    -- 当前 heading 和 laneIndex
    currentHeading = 0,
    currentLaneIndex = 2,    -- 当前在第几条并行道路上 (1/2/3)

    -- 上一个经过的节点
    lastNodeId = 0,

    -- =========== 路口区域状态 ===========
    insideIntersection = false,
    intersectionProgress = 0.0,
    intersectionNodeId = 0,
    intersectionNodePos = nil,       -- Vector3
    intersectionArrivalHeading = 0,
    intersectionExitHeading = 0,     -- 确定的出口 heading
    entryLaneIndex = 2,              -- 进入时的 laneIndex

    -- =========== 出口选择状态 ===========
    desiredTurn = 0,                 -- -1=左/0=直/1=右
    hasTurnChoice = false,           -- 玩家是否已做出选择
    selectedExitEdge = nil,          -- 选中的出口 edge
    selectedExitLaneIndex = nil,     -- 选中的出口 laneIndex
    choiceWorldPos = nil,            -- 做出选择时的玩家世界坐标
    routeBlocked = false,            -- 选中方向无路

    -- =========== 输入状态机 ===========
    turnInputActive = false,         -- 路口区域内为 true
    laneChangeLocked = false,        -- 路口区域内为 true

    -- UI 提示
    intersectionActive = false,
    intersectionHintDir = 0,
    availableTurns = {},

    -- 转弯记录
    turnJustCommitted = false,
    turnArrivalHeading = 0,
    turnExitHeading = 0,

    -- 全局里程
    totalDistance = 0.0,
}

-- ============================================================================
-- 初始化
-- ============================================================================

function M.Init()
    rn.Generate()

    local startEdge, startNodeId = rn.GetStartEdge()
    if not startEdge then
        print("[Path] ERROR: No start edge found!")
        return
    end

    local s = M.state
    s.currentEdge = startEdge
    s.edgeDistance = 5.0
    s.currentHeading = startEdge.heading
    s.currentLaneIndex = startEdge.laneIndex
    s.lastNodeId = startNodeId

    s.insideIntersection = false
    s.intersectionProgress = 0.0
    s.intersectionNodeId = 0
    s.intersectionNodePos = nil
    s.intersectionArrivalHeading = 0
    s.intersectionExitHeading = 0
    s.entryLaneIndex = 2

    s.desiredTurn = 0
    s.hasTurnChoice = false
    s.selectedExitEdge = nil
    s.selectedExitLaneIndex = nil
    s.choiceWorldPos = nil
    s.routeBlocked = false

    s.turnInputActive = false
    s.laneChangeLocked = false
    s.intersectionActive = false
    s.intersectionHintDir = 0
    s.availableTurns = {}
    s.turnJustCommitted = false
    s.turnArrivalHeading = 0
    s.turnExitHeading = 0
    s.totalDistance = 0.0

    print("[Path] Initialized on edge " .. startEdge.id ..
        " heading=" .. startEdge.heading .. " lane=" .. startEdge.laneIndex)
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取当前世界坐标
function M.GetWorldPosition()
    local s = M.state

    if s.insideIntersection then
        local exitLane = s.selectedExitLaneIndex or s.entryLaneIndex
        local pos, _ = rn.GetIntersectionPosition(
            s.intersectionNodePos,
            s.intersectionArrivalHeading,
            s.intersectionExitHeading,
            s.intersectionProgress,
            s.entryLaneIndex,
            exitLane
        )
        return pos
    end

    if s.currentEdge then
        return rn.GetPositionOnEdgeByDist(s.currentEdge, s.edgeDistance)
    end

    return Vector3(0, 0, 0)
end

--- 获取当前 yaw 角度
function M.GetCurrentYaw()
    local s = M.state

    if s.insideIntersection then
        local exitLane = s.selectedExitLaneIndex or s.entryLaneIndex
        local _, yaw = rn.GetIntersectionPosition(
            s.intersectionNodePos,
            s.intersectionArrivalHeading,
            s.intersectionExitHeading,
            s.intersectionProgress,
            s.entryLaneIndex,
            exitLane
        )
        return yaw
    end

    return rn.HeadingToYaw(s.currentHeading)
end

--- heading 到 yaw
function M.HeadingToYaw(heading)
    return rn.HeadingToYaw(heading)
end

--- 前进方向向量
function M.GetForwardVector(heading)
    return rn.HeadingToForward(heading)
end

--- 右侧方向向量
function M.GetRightVector(heading)
    return rn.HeadingToRight(heading)
end

--- 判断某个边距离是否在安全区内
function M.IsInSafeZone(distFromEdgeStart)
    local s = M.state
    if s.insideIntersection then return true end
    if not s.currentEdge then return false end
    local effectiveLen = rn.GetEdgeEffectiveLength()
    if distFromEdgeStart < CONFIG.SAFE_ZONE_DIST then return true end
    if (effectiveLen - distFromEdgeStart) < CONFIG.SAFE_ZONE_DIST then return true end
    return false
end

-- ============================================================================
-- 输入状态机更新
-- ============================================================================

function M.UpdateInputState()
    local s = M.state

    if s.routeBlocked then return end

    if s.insideIntersection then
        -- 路口区域内：接受转向选择，锁定变道
        s.turnInputActive = true
        s.laneChangeLocked = true
        return
    end

    -- 在边上：变道自由，转向输入关闭
    s.laneChangeLocked = false
    s.turnInputActive = false
end

-- ============================================================================
-- 核心：移动逻辑
-- ============================================================================

--- 每帧前进
function M.Advance(moveDist)
    local s = M.state

    if s.routeBlocked then return end

    s.turnJustCommitted = false
    s.totalDistance = s.totalDistance + moveDist

    -- 情况 A：在路口区域内穿越
    if s.insideIntersection then
        local traverseLen = rn.GetIntersectionTraverseLength()
        local advance = moveDist / traverseLen
        s.intersectionProgress = s.intersectionProgress + advance

        if s.intersectionProgress >= 1.0 then
            local overshoot = (s.intersectionProgress - 1.0) * traverseLen
            M.ExitIntersection(overshoot)
        end
        return
    end

    -- 情况 B：沿边有效区段前进
    if not s.currentEdge then return end

    local effectiveLen = rn.GetEdgeEffectiveLength()
    s.edgeDistance = s.edgeDistance + moveDist

    if s.edgeDistance >= effectiveLen then
        local overshoot = s.edgeDistance - effectiveLen
        s.edgeDistance = effectiveLen
        M.EnterIntersection(overshoot)
    end
end

-- ============================================================================
-- 进入路口区域
-- ============================================================================

function M.EnterIntersection(overshoot)
    local s = M.state
    local edge = s.currentEdge
    local targetNodeId = edge.toNode
    local targetNode = rn.nodes[targetNodeId]

    if not targetNode then
        print("[Path] ERROR: Target node not found!")
        s.routeBlocked = true
        return
    end

    -- 设置路口区域状态
    s.insideIntersection = true
    s.intersectionProgress = 0.0
    s.intersectionNodeId = targetNodeId
    s.intersectionNodePos = Vector3(targetNode.worldX, 0, targetNode.worldZ)
    s.intersectionArrivalHeading = s.currentHeading
    s.entryLaneIndex = s.currentLaneIndex

    -- 默认直走（如果玩家不输入）
    s.intersectionExitHeading = s.currentHeading
    s.desiredTurn = 0
    s.hasTurnChoice = false
    s.selectedExitEdge = nil
    s.selectedExitLaneIndex = nil
    s.choiceWorldPos = nil

    -- 获取可用转向（用于 UI 提示）
    s.availableTurns = rn.GetAvailableTurns(targetNodeId, s.currentHeading)
    s.intersectionActive = true
    if #s.availableTurns > 0 then
        local r = math.random(1, #s.availableTurns)
        local recommended = s.availableTurns[r]
        if recommended.direction == "left" then
            s.intersectionHintDir = -1
        elseif recommended.direction == "right" then
            s.intersectionHintDir = 1
        else
            s.intersectionHintDir = 0
        end
    end

    print("[Path] Entered intersection at node " .. targetNodeId ..
        " heading=" .. s.currentHeading .. " entryLane=" .. s.entryLaneIndex)

    -- 把 overshoot 应用到路口穿越
    if overshoot > 0 then
        local traverseLen = rn.GetIntersectionTraverseLength()
        s.intersectionProgress = overshoot / traverseLen
        if s.intersectionProgress >= 1.0 then
            local remainOvershoot = (s.intersectionProgress - 1.0) * traverseLen
            M.ExitIntersection(remainOvershoot)
        end
    end
end

-- ============================================================================
-- 离开路口区域 → 进入新的并行 edge
-- ============================================================================

function M.ExitIntersection(overshoot)
    local s = M.state

    -- 如果玩家从未输入，使用默认：直走，按当前位置选出口
    if not s.hasTurnChoice then
        s.desiredTurn = 0
        local currentPos = M.GetWorldPosition()
        local exitEdge, exitLane, exitHeading = rn.SelectExitByIntersectionPosition(
            s.intersectionNodeId,
            s.intersectionArrivalHeading,
            0,  -- 直走
            currentPos
        )
        s.selectedExitEdge = exitEdge
        s.selectedExitLaneIndex = exitLane
        s.intersectionExitHeading = exitHeading or s.intersectionArrivalHeading
    end

    -- 检查出口是否存在
    if not s.selectedExitEdge then
        print("[Path] ROUTE BLOCKED: No exit edge at node " .. s.intersectionNodeId ..
            " heading=" .. s.intersectionExitHeading)
        s.routeBlocked = true
        return
    end

    -- 记录转弯信息
    s.turnJustCommitted = true
    s.turnArrivalHeading = s.intersectionArrivalHeading
    s.turnExitHeading = s.intersectionExitHeading

    -- 进入新边
    s.currentEdge = s.selectedExitEdge
    s.currentHeading = s.selectedExitEdge.heading
    s.currentLaneIndex = s.selectedExitEdge.laneIndex
    s.lastNodeId = s.selectedExitEdge.fromNode
    s.edgeDistance = overshoot or 0

    -- 同步 CONFIG.currentLane 用于障碍物系统兼容
    CONFIG.currentLane = s.currentLaneIndex

    -- 清除路口状态
    s.insideIntersection = false
    s.intersectionProgress = 1.0
    s.intersectionNodeId = 0
    s.intersectionNodePos = nil

    s.laneChangeLocked = false
    s.turnInputActive = false
    s.desiredTurn = 0
    s.hasTurnChoice = false
    s.selectedExitEdge = nil
    s.selectedExitLaneIndex = nil
    s.choiceWorldPos = nil
    s.intersectionActive = false

    print("[Path] Exited intersection -> edge " .. s.currentEdge.id ..
        " heading=" .. s.currentHeading .. " lane=" .. s.currentLaneIndex)
end

-- ============================================================================
-- 路口区域内实时更新出口方向（玩家输入时调用）
-- ============================================================================

function M.UpdateExitChoice()
    local s = M.state
    if not s.insideIntersection then return end
    if s.routeBlocked then return end

    -- 获取玩家当前在路口内的世界坐标
    local playerPos = M.GetWorldPosition()
    s.choiceWorldPos = playerPos

    -- 调用核心出口选择函数
    local exitEdge, exitLane, exitHeading = rn.SelectExitByIntersectionPosition(
        s.intersectionNodeId,
        s.intersectionArrivalHeading,
        s.desiredTurn,
        playerPos
    )

    if exitEdge then
        s.selectedExitEdge = exitEdge
        s.selectedExitLaneIndex = exitLane
        s.intersectionExitHeading = exitHeading
    else
        -- 选择的方向无路 → routeBlocked
        print("[Path] ROUTE BLOCKED (in-area choice): heading=" ..
            (exitHeading or "nil") .. " lane=" .. (exitLane or "nil"))
        s.routeBlocked = true
    end
end

-- ============================================================================
-- 路口检测与提示（边上时的预判显示）
-- ============================================================================

function M.CheckIntersection()
    local s = M.state
    if s.insideIntersection then return end
    if s.routeBlocked then return end
    if s.intersectionActive then return end
    if not s.currentEdge then return end

    local effectiveLen = rn.GetEdgeEffectiveLength()
    local progress = s.edgeDistance / effectiveLen
    if progress >= CONFIG.INTERSECTION_HINT_PROGRESS then
        local targetNodeId = s.currentEdge.toNode
        s.availableTurns = rn.GetAvailableTurns(targetNodeId, s.currentHeading)
        if #s.availableTurns > 0 then
            s.intersectionActive = true
            local r = math.random(1, #s.availableTurns)
            local recommended = s.availableTurns[r]
            if recommended.direction == "left" then
                s.intersectionHintDir = -1
            elseif recommended.direction == "right" then
                s.intersectionHintDir = 1
            else
                s.intersectionHintDir = 0
            end
        end
    end
end

-- ============================================================================
-- 变道（在边上时切换并行道路）
-- ============================================================================

--- 在边上切换到相邻的并行道路
--- @param direction integer -1=左, 1=右
--- @return boolean success
function M.ChangeLane(direction)
    local s = M.state
    if s.insideIntersection then return false end
    if s.laneChangeLocked then return false end
    if not s.currentEdge then return false end

    local targetLane = s.currentLaneIndex + direction
    if targetLane < 1 or targetLane > rn.PARALLEL_COUNT then
        return false
    end

    -- 找到同方向相邻 lane 的 edge
    local newEdge = rn.GetParallelExitEdge(s.lastNodeId, s.currentHeading, targetLane)
    if not newEdge then
        return false
    end

    s.currentEdge = newEdge
    s.currentLaneIndex = targetLane
    CONFIG.currentLane = targetLane
    return true
end

return M
