-- ============================================================================
-- 外卖冲冲冲 - 路径系统模块（基于 RoadGraph + 3x3 路口区域）
-- ============================================================================
-- 状态机：
--   onEdge → 沿边前进（有效区段）
--   insideIntersection → 进入路口区域（选择方向、穿越区域）
--   提交出口 → 进入新边
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
    currentEdge = nil,       -- edge 对象
    edgeDistance = 0.0,      -- 有效区段内走的距离（0 = 刚出路口区域）

    -- 当前 heading（前进方向）
    currentHeading = 0,

    -- 上一个经过的节点（用于判断来路方向）
    lastNodeId = 0,

    -- =========== 路口区域状态 ===========
    insideIntersection = false,   -- 是否在路口区域内
    intersectionProgress = 0.0,   -- 0..1 路口区域穿越进度
    intersectionNodeId = 0,       -- 当前路口的节点 ID
    intersectionNodePos = nil,    -- 路口世界坐标 Vector3
    intersectionArrivalHeading = 0, -- 进入路口时的 heading
    intersectionExitHeading = 0,    -- 确定的出口 heading（默认=arrivalHeading，即直走）

    -- =========== 输入状态机 ===========
    turnInputActive = false,      -- 当前左右滑动是否为转向选择（在路口区域内为 true）
    laneChangeLocked = false,     -- 当前是否禁止变道（在路口区域内为 true）
    distanceToNode = 0.0,         -- 距离下一个路口中心的距离
    routeBlocked = false,         -- 是否撞到死路/无路可走

    -- 玩家转向选择
    turnChoice = 0,               -- 玩家实际选择 -1左/0直/1右
    hasTurnChoice = false,        -- 玩家是否已做出选择
    turnChoiceProgress = 0.0,     -- 做出转向选择时的路口内进度（用于决定出口车道）
    exitLaneOffset = 0.0,         -- 出口车道的 laneOffset 目标值（用于平滑过渡）

    -- UI 提示
    intersectionActive = false,   -- 是否在路口提示阶段（兼容旧 UI）
    intersectionHintDir = 0,      -- 推荐方向 -1左/0直/1右
    availableTurns = {},          -- 当前路口可用转向列表

    -- 转弯记录（用于外部奖惩逻辑）
    turnJustCommitted = false,    -- 本帧刚确定出口
    turnArrivalHeading = 0,       -- 记录（供外部读取）
    turnExitHeading = 0,          -- 记录（供外部读取）

    -- 全局里程（用于计分/难度等）
    totalDistance = 0.0,
}

-- ============================================================================
-- 初始化
-- ============================================================================

function M.Init()
    -- 生成路网
    rn.Generate()

    -- 获取起始边
    local startEdge, startNodeId = rn.GetStartEdge()
    if not startEdge then
        print("[Path] ERROR: No start edge found!")
        return
    end

    local s = M.state
    s.currentEdge = startEdge
    s.edgeDistance = 5.0  -- 稍微离开起始路口
    s.currentHeading = startEdge.heading
    s.lastNodeId = startNodeId
    s.insideIntersection = false
    s.intersectionProgress = 0.0
    s.intersectionNodeId = 0
    s.intersectionNodePos = nil
    s.intersectionArrivalHeading = 0
    s.intersectionExitHeading = 0
    s.turnChoice = 0
    s.hasTurnChoice = false
    s.totalDistance = 0.0
    s.availableTurns = {}
    s.turnInputActive = false
    s.laneChangeLocked = false
    s.distanceToNode = 0.0
    s.routeBlocked = false
    s.intersectionActive = false
    s.intersectionHintDir = 0
    s.turnJustCommitted = false
    s.turnArrivalHeading = 0
    s.turnExitHeading = 0

    print("[Path] Initialized on edge " .. startEdge.id .. " heading " .. startEdge.heading)
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取当前世界坐标
function M.GetWorldPosition(laneOffset)
    local s = M.state

    if s.insideIntersection then
        local pos, _ = rn.GetIntersectionPosition(
            s.intersectionNodePos,
            s.intersectionArrivalHeading,
            s.intersectionExitHeading,
            s.intersectionProgress,
            laneOffset,
            s.exitLaneOffset
        )
        return pos
    end

    if s.currentEdge then
        return rn.GetPositionOnEdgeByDist(s.currentEdge, s.edgeDistance, laneOffset)
    end

    return Vector3(0, 0, 0)
end

--- 获取当前 yaw 角度
function M.GetCurrentYaw()
    local s = M.state

    if s.insideIntersection then
        local _, yaw = rn.GetIntersectionPosition(
            s.intersectionNodePos,
            s.intersectionArrivalHeading,
            s.intersectionExitHeading,
            s.intersectionProgress,
            0,
            0
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
    if s.insideIntersection then return true end  -- 路口区域内不生成障碍
    if not s.currentEdge then return false end
    local effectiveLen = rn.GetEdgeEffectiveLength()
    if distFromEdgeStart < CONFIG.SAFE_ZONE_DIST then return true end
    if (effectiveLen - distFromEdgeStart) < CONFIG.SAFE_ZONE_DIST then return true end
    return false
end

-- ============================================================================
-- 输入状态机更新（每帧调用）
-- ============================================================================

function M.UpdateInputState()
    local s = M.state

    if s.routeBlocked then return end

    if s.insideIntersection then
        -- 路口中心区域内：这就是转向选择窗口
        s.turnInputActive = true    -- 在路口区域内可以选择方向
        s.laneChangeLocked = false  -- 也允许换道（选方向后换道决定出口路线）
        return
    end

    -- 在边上：普通状态
    s.turnInputActive = false   -- 不在路口内，不能选转向
    s.laneChangeLocked = false  -- 可以自由换道

    -- 计算到下一个路口中心的距离（仅用于 UI 提示）
    if s.currentEdge then
        local effectiveLen = rn.GetEdgeEffectiveLength()
        s.distanceToNode = effectiveLen - s.edgeDistance + rn.INTERSECTION_HALF_SIZE
    else
        s.distanceToNode = 999.0
    end
end

-- ============================================================================
-- 核心：移动逻辑
-- ============================================================================

--- 每帧前进
function M.Advance(moveDist)
    local s = M.state

    if s.routeBlocked then return end

    -- 清除上一帧的标记
    s.turnJustCommitted = false

    s.totalDistance = s.totalDistance + moveDist

    -- ==========================================
    -- 情况 A：在路口区域内穿越
    -- ==========================================
    if s.insideIntersection then
        local traverseLen = rn.GetIntersectionTraverseLength()
        local advance = moveDist / traverseLen
        s.intersectionProgress = s.intersectionProgress + advance

        if s.intersectionProgress >= 1.0 then
            -- 穿越完毕，多余距离带入新边
            local overshoot = (s.intersectionProgress - 1.0) * traverseLen
            M.ExitIntersection(overshoot)
        end
        return
    end

    -- ==========================================
    -- 情况 B：沿边有效区段前进
    -- ==========================================
    if not s.currentEdge then return end

    local effectiveLen = rn.GetEdgeEffectiveLength()
    s.edgeDistance = s.edgeDistance + moveDist

    -- 到达边有效区段末端 → 进入路口区域
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

    -- 进入路口时默认直走，玩家在路口内实时选择方向
    s.intersectionExitHeading = s.currentHeading
    s.turnChoice = 0
    s.hasTurnChoice = false
    s.turnChoiceProgress = 0.5
    s.exitLaneOffset = CONFIG.LANE_X[CONFIG.currentLane]  -- 默认直走保持当前车道

    -- 检查出口方向是否有效
    local exitEdge = rn.GetEdgeByHeading(targetNodeId, s.intersectionExitHeading)
    if not exitEdge then
        -- 选择的方向无路 → 死路
        print("[Path] DEAD END at node " .. targetNodeId .. " heading " .. s.intersectionExitHeading)
        s.routeBlocked = true
        return
    end

    -- 激活 UI 提示
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

    -- 记录（供外部奖惩用）
    s.turnJustCommitted = true
    s.turnArrivalHeading = s.currentHeading
    s.turnExitHeading = s.intersectionExitHeading

    print("[Path] Entered intersection at node " .. targetNodeId ..
        " heading " .. s.currentHeading .. " -> " .. s.intersectionExitHeading)

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
-- 离开路口区域 → 进入新边
-- ============================================================================

function M.ExitIntersection(overshoot)
    local s = M.state

    -- 确定出口车道（转弯时用做出选择时的进度，直走用当前车道）
    local progressForLane = s.turnChoiceProgress
    if not s.hasTurnChoice then
        progressForLane = 0.5  -- 没有主动选择时，默认中间进度
    end
    local exitLane = rn.SelectExitLane(
        s.intersectionArrivalHeading,
        s.intersectionExitHeading,
        progressForLane,
        CONFIG.currentLane
    )

    -- 获取出口边
    local exitEdge = rn.GetEdgeByHeading(s.intersectionNodeId, s.intersectionExitHeading)
    if not exitEdge then
        print("[Path] ERROR: Exit edge disappeared!")
        s.routeBlocked = true
        return
    end

    -- 更新车道（转弯时根据进度决定出口车道）
    CONFIG.currentLane = exitLane

    -- 进入新边
    s.currentEdge = exitEdge
    s.currentHeading = s.intersectionExitHeading
    s.lastNodeId = exitEdge.fromNode
    s.edgeDistance = overshoot or 0

    -- 清除路口状态
    s.insideIntersection = false
    s.intersectionProgress = 1.0
    s.intersectionNodeId = 0
    s.intersectionNodePos = nil

    -- 解锁变道，清除转向选择
    s.laneChangeLocked = false
    s.turnInputActive = false
    s.turnChoice = 0
    s.hasTurnChoice = false
    s.intersectionActive = false

    print("[Path] Exited intersection -> edge " .. exitEdge.id ..
        " heading " .. s.currentHeading .. " exitLane " .. exitLane)
end

-- ============================================================================
-- 路口区域内实时更新出口方向（玩家可以在区域内改变主意）
-- ============================================================================

function M.UpdateExitChoice()
    local s = M.state
    if not s.insideIntersection then return end
    if s.routeBlocked then return end

    -- 玩家在路口区域内做出新选择
    if s.hasTurnChoice then
        local choice = s.turnChoice
        local newExitHeading = s.currentHeading  -- 从 arrivalHeading 出发计算
        if choice == -1 then
            newExitHeading = rn.TurnLeft(s.intersectionArrivalHeading)
        elseif choice == 1 then
            newExitHeading = rn.TurnRight(s.intersectionArrivalHeading)
        else
            newExitHeading = s.intersectionArrivalHeading
        end

        -- 验证新方向是否有边
        local exitEdge = rn.GetEdgeByHeading(s.intersectionNodeId, newExitHeading)
        if exitEdge then
            s.intersectionExitHeading = newExitHeading
            -- 记录做出选择时的进度（决定出口车道用）
            s.turnChoiceProgress = s.intersectionProgress
            -- 立即计算出口车道的 laneOffset 目标（用于平滑过渡）
            local exitLane = rn.SelectExitLane(
                s.intersectionArrivalHeading, newExitHeading,
                s.intersectionProgress, CONFIG.currentLane
            )
            s.exitLaneOffset = CONFIG.LANE_X[exitLane]
        else
            -- 新方向无路 → 死路
            print("[Path] DEAD END (in-area choice): heading " .. newExitHeading)
            s.routeBlocked = true
        end
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

    -- 距路口较近时提前显示提示
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

return M
