-- ============================================================================
-- 外卖冲冲冲 - 路径系统模块（基于 RoadGraph）
-- ============================================================================
-- 管理玩家在路网中的状态：当前边、进度、转弯等
-- 转弯采用连续过渡：到达 turnStartDist 后自动开始弧线
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local rn = require("road_network")

local M = {}

-- ============================================================================
-- 玩家在路网中的运行时状态
-- ============================================================================
M.state = {
    -- 当前所在边
    currentEdge = nil,       -- edge 对象
    edgeProgress = 0.0,      -- 0..1 在当前边上的进度
    edgeDistance = 0.0,      -- 当前边上已走的距离

    -- 当前 heading（前进方向）
    currentHeading = 0,

    -- 上一个经过的节点（用于判断来路方向）
    lastNodeId = 0,

    -- 路口状态（仅用于UI提示）
    intersectionActive = false,   -- 是否在路口提示阶段
    intersectionHintDir = 0,      -- 推荐方向 -1左/0直/1右（仅用于UI提示）
    availableTurns = {},          -- 当前路口可用转向列表

    -- 输入状态机（新增）
    turnInputActive = false,      -- 当前左右滑动是否为转向选择
    laneChangeLocked = false,     -- 当前是否禁止变道
    distanceToNode = 0.0,         -- 当前离目标路口中心的距离
    routeBlocked = false,         -- 是否撞到死路/无路可走

    -- 玩家转向选择
    turnChoice = 0,               -- 玩家实际选择 -1左/0直/1右
    hasTurnChoice = false,        -- 玩家是否已做出选择

    -- 转弯执行状态
    turnExecuting = false,
    turnJustStarted = false,     -- 本帧刚进入转弯（用于外部清理逻辑）
    turnArcProgress = 0.0,       -- 0..1 转弯弧线进度
    turnArrivalHeading = 0,
    turnExitHeading = 0,
    turnNodeWorldPos = nil,      -- 转弯路口世界坐标
    turnNextEdge = nil,          -- 转弯后的下一条边
    turnLength = 0.0,            -- 弧线总长度

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
    s.edgeProgress = 0.05  -- 稍微离开起始路口
    s.edgeDistance = startEdge.length * s.edgeProgress
    s.currentHeading = startEdge.heading
    s.lastNodeId = startNodeId
    s.intersectionActive = false
    s.intersectionHintDir = 0
    s.turnChoice = 0
    s.hasTurnChoice = false
    s.turnExecuting = false
    s.turnJustStarted = false
    s.totalDistance = 0.0
    s.availableTurns = {}
    s.turnArcProgress = 0.0

    -- 新状态机字段
    s.turnInputActive = false
    s.laneChangeLocked = false
    s.distanceToNode = startEdge.length - s.edgeDistance
    s.routeBlocked = false

    print("[Path] Initialized on edge " .. startEdge.id .. " heading " .. startEdge.heading)
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取当前世界坐标
function M.GetWorldPosition(laneOffset)
    local s = M.state

    if s.turnExecuting then
        local pos, _ = rn.GetTurnPosition(
            s.turnNodeWorldPos,
            s.turnArrivalHeading,
            s.turnExitHeading,
            s.turnArcProgress,
            laneOffset
        )
        return pos
    end

    if s.currentEdge then
        return rn.GetPositionOnEdge(s.currentEdge, s.edgeProgress, laneOffset)
    end

    return Vector3(0, 0, 0)
end

--- 获取当前 yaw 角度（转弯时连续插值）
function M.GetCurrentYaw()
    local s = M.state

    if s.turnExecuting then
        local _, yaw = rn.GetTurnPosition(
            s.turnNodeWorldPos,
            s.turnArrivalHeading,
            s.turnExitHeading,
            s.turnArcProgress,
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
    if not s.currentEdge then return false end
    local edgeLen = s.currentEdge.length
    -- 靠近末端的安全区
    if (edgeLen - distFromEdgeStart) < CONFIG.SAFE_ZONE_DIST then
        return true
    end
    -- 刚离开路口的安全区
    if distFromEdgeStart < CONFIG.SAFE_ZONE_DIST then
        return true
    end
    return false
end

-- ============================================================================
-- 输入状态机更新（每帧调用，在 Advance 之前或之后均可）
-- ============================================================================

function M.UpdateInputState()
    local s = M.state

    -- 已经死路，不再更新
    if s.routeBlocked then return end

    -- 转弯执行中：禁止变道，禁止转向选择
    if s.turnExecuting then
        s.turnInputActive = false
        s.laneChangeLocked = true
        return
    end

    -- 不在转弯中：允许变道
    s.laneChangeLocked = false

    -- 计算距离目标路口中心的距离
    if s.currentEdge then
        s.distanceToNode = s.currentEdge.length - s.edgeDistance
    else
        s.distanceToNode = 999.0
    end

    -- 判断是否在转向选择窗口
    -- 条件：距路口 <= TURN_INPUT_START_DIST 且 > TURN_RADIUS
    if s.distanceToNode <= CONFIG.TURN_INPUT_START_DIST and s.distanceToNode > rn.TURN_RADIUS then
        s.turnInputActive = true
    else
        s.turnInputActive = false
    end
end

-- ============================================================================
-- 核心：移动逻辑（连续过渡，无跳变）
-- ============================================================================

--- 每帧前进。返回 false 正常，不需要外部处理
function M.Advance(moveDist)
    local s = M.state

    -- 已经死路，不再移动
    if s.routeBlocked then return false end

    -- 清除上一帧的 turnJustStarted 标记
    s.turnJustStarted = false

    s.totalDistance = s.totalDistance + moveDist

    -- ==========================================
    -- 情况 A：当前正在转弯弧线上
    -- ==========================================
    if s.turnExecuting then
        local arcAdvance = moveDist / s.turnLength
        s.turnArcProgress = s.turnArcProgress + arcAdvance

        if s.turnArcProgress >= 1.0 then
            -- 弧线走完，多余距离带入新边
            local overshoot = (s.turnArcProgress - 1.0) * s.turnLength
            M.FinishTurn(overshoot)
        end
        return false
    end

    -- ==========================================
    -- 情况 B：沿边前进
    -- ==========================================
    if not s.currentEdge then return false end

    s.edgeDistance = s.edgeDistance + moveDist
    s.edgeProgress = s.edgeDistance / s.currentEdge.length

    -- 计算转弯起始距离（距边末端 TURN_RADIUS 处）
    local turnStartDist = s.currentEdge.length - rn.TURN_RADIUS

    -- 到达转弯起始点
    if s.edgeDistance >= turnStartDist then
        -- 计算多余距离（超过转弯起始点的部分）
        local overshoot = s.edgeDistance - turnStartDist

        -- 固定 edgeProgress/edgeDistance 到转弯起始点
        s.edgeDistance = turnStartDist
        s.edgeProgress = turnStartDist / s.currentEdge.length

        -- 开始转弯
        M.StartTurnAtNode()

        -- 如果死路了，不再推进
        if s.routeBlocked then return false end

        -- 把多余距离应用到弧线
        if s.turnExecuting and overshoot > 0 then
            local arcAdvance = overshoot / s.turnLength
            s.turnArcProgress = s.turnArcProgress + arcAdvance
            if s.turnArcProgress >= 1.0 then
                local arcOvershoot = (s.turnArcProgress - 1.0) * s.turnLength
                M.FinishTurn(arcOvershoot)
            end
        end
    end

    return false
end

-- ============================================================================
-- 开始转弯（解析玩家选择，设置弧线参数）
-- 不再自动选择方向 —— 没路就触发死路状态
-- ============================================================================

function M.StartTurnAtNode()
    local s = M.state
    local edge = s.currentEdge
    local targetNodeId = edge.toNode
    local targetNode = rn.nodes[targetNodeId]

    if not targetNode then
        print("[Path] ERROR: Target node not found!")
        s.routeBlocked = true
        return
    end

    -- 确定出口方向
    local exitHeading = s.currentHeading  -- 默认直走

    if s.hasTurnChoice then
        -- 玩家已做出选择
        local choice = s.turnChoice
        if choice == -1 then
            exitHeading = rn.TurnLeft(s.currentHeading)
        elseif choice == 1 then
            exitHeading = rn.TurnRight(s.currentHeading)
        else
            exitHeading = s.currentHeading  -- 玩家明确选择直走
        end
    end
    -- 如果没有选择（hasTurnChoice == false），exitHeading 保持直走

    -- 检查该方向是否有边
    local nextEdge = rn.GetEdgeByHeading(targetNodeId, exitHeading)

    if not nextEdge then
        -- 选择的方向无路 → 死路！
        -- 不自动选择其他方向，直接触发失败
        print("[Path] DEAD END: No road in heading " .. exitHeading .. " at node " .. targetNodeId)
        s.routeBlocked = true
        s.turnExecuting = false
        s.laneChangeLocked = true
        return
    end

    -- 设置转弯参数
    s.turnExecuting = true
    s.turnJustStarted = true
    s.turnArcProgress = 0.0
    s.turnArrivalHeading = s.currentHeading
    s.turnExitHeading = exitHeading
    s.turnNodeWorldPos = Vector3(targetNode.worldX, 0, targetNode.worldZ)
    s.turnNextEdge = nextEdge
    s.turnLength = rn.GetTurnLength(s.currentHeading, exitHeading)

    -- 重置路口状态
    s.intersectionActive = false
    s.turnInputActive = false
    s.turnChoice = 0
    s.hasTurnChoice = false

    print("[Path] Turn started: heading " .. s.currentHeading .. " -> " .. exitHeading .. " at node " .. targetNodeId)
end

-- ============================================================================
-- 转弯完成
-- ============================================================================

function M.FinishTurn(overshootDist)
    local s = M.state

    s.turnExecuting = false
    s.turnArcProgress = 1.0  -- 钳位

    -- 进入新边
    s.currentEdge = s.turnNextEdge
    s.currentHeading = s.turnExitHeading
    s.lastNodeId = s.turnNextEdge.fromNode
    s.turnNextEdge = nil

    -- 弧线结束时角色已在新边离路口中心 TURN_RADIUS 处
    -- 所以新边起始 edgeDistance = TURN_RADIUS + overshoot
    local startDist = rn.TURN_RADIUS + (overshootDist or 0)
    s.edgeDistance = math.min(startDist, s.currentEdge.length * 0.95)  -- clamp 防溢
    s.edgeProgress = s.edgeDistance / s.currentEdge.length

    -- 进入新边后解锁变道
    s.laneChangeLocked = false
    s.turnInputActive = false

    print("[Path] Entered edge " .. s.currentEdge.id .. " heading " .. s.currentHeading)
end

-- ============================================================================
-- 路口检测与提示（只负责UI提示状态，不控制输入含义）
-- ============================================================================

--- 每帧检查是否应该显示路口提示
function M.CheckIntersection()
    local s = M.state
    if s.turnExecuting then return end
    if s.routeBlocked then return end
    if s.intersectionActive then return end
    if not s.currentEdge then return end

    -- 当进度达到阈值时，激活路口提示（仅用于UI）
    if s.edgeProgress >= CONFIG.INTERSECTION_HINT_PROGRESS then
        local targetNodeId = s.currentEdge.toNode
        s.availableTurns = rn.GetAvailableTurns(targetNodeId, s.currentHeading)

        if #s.availableTurns > 0 then
            s.intersectionActive = true
            -- 随机推荐一个方向（仅用于 UI 提示和奖惩）
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
