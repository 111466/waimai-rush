-- ============================================================================
-- 外卖冲冲冲 - 路径系统模块（基于 RoadGraph）
-- ============================================================================
-- 管理玩家在路网中的状态：当前边、进度、转弯等
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

    -- 路口状态
    intersectionActive = false,   -- 是否在路口选择阶段
    intersectionHintDir = 0,      -- 推荐方向 -1左/0直/1右
    turnChoice = 0,               -- 玩家选择 -1左/0直/1右
    availableTurns = {},          -- 当前路口可用转向

    -- 转弯执行状态
    turnExecuting = false,
    turnArcProgress = 0.0,       -- 0..1 转弯弧线进度
    turnArrivalHeading = 0,
    turnExitHeading = 0,
    turnNodeWorldPos = nil,      -- 转弯路口世界坐标
    turnNextEdge = nil,          -- 转弯后的下一条边
    turnLength = 0.0,            -- 弧线总长度

    -- 摄像机转弯
    camTurning = false,
    camTurnFrom = 0.0,
    camTurnTo = 0.0,
    camTurnAnimTime = 0.0,

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
    s.turnChoice = 0
    s.turnExecuting = false
    s.totalDistance = 0.0
    s.camTurning = false
    s.availableTurns = {}

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

--- 获取当前 yaw 角度
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

--- 判断某个距离是否在当前路口安全区内
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
-- 移动逻辑：前进 / 到达路口 / 执行转弯
-- ============================================================================

--- 每帧前进
--- 返回 true 表示到达了路口末端需要转弯
function M.Advance(moveDist)
    local s = M.state

    s.totalDistance = s.totalDistance + moveDist

    -- 如果在转弯中
    if s.turnExecuting then
        local arcAdvance = moveDist / s.turnLength
        s.turnArcProgress = s.turnArcProgress + arcAdvance

        if s.turnArcProgress >= 1.0 then
            -- 转弯完成，进入新边
            M.FinishTurn()
        end
        return false
    end

    -- 正常沿边前进
    if not s.currentEdge then return false end

    s.edgeDistance = s.edgeDistance + moveDist
    s.edgeProgress = s.edgeDistance / s.currentEdge.length

    -- 检查是否到达边的末端
    if s.edgeProgress >= 1.0 then
        -- 到达路口，需要执行转弯
        M.ExecuteTurnAtNode()
        return true
    end

    return false
end

--- 到达路口节点，执行转弯
function M.ExecuteTurnAtNode()
    local s = M.state
    local edge = s.currentEdge
    local targetNodeId = edge.toNode
    local targetNode = rn.nodes[targetNodeId]

    if not targetNode then
        print("[Path] ERROR: Target node not found!")
        return
    end

    -- 确定出口方向
    local exitHeading = s.currentHeading  -- 默认直走
    local choice = s.turnChoice

    if choice == -1 then
        exitHeading = rn.TurnLeft(s.currentHeading)
    elseif choice == 1 then
        exitHeading = rn.TurnRight(s.currentHeading)
    end

    -- 检查该方向是否有边
    local nextEdge = rn.GetEdgeByHeading(targetNodeId, exitHeading)
    if not nextEdge then
        -- 该方向无路，尝试直走
        nextEdge = rn.GetEdgeByHeading(targetNodeId, s.currentHeading)
        if not nextEdge then
            -- 直走也无路，随机选一条（不掉头）
            local turns = rn.GetAvailableTurns(targetNodeId, s.currentHeading)
            if #turns > 0 then
                local pick = turns[math.random(1, #turns)]
                nextEdge = pick.edge
                exitHeading = pick.heading
            else
                -- 死路：掉头
                exitHeading = rn.ReverseHeading(s.currentHeading)
                nextEdge = rn.GetEdgeByHeading(targetNodeId, exitHeading)
            end
        else
            exitHeading = s.currentHeading
        end
    end

    if not nextEdge then
        print("[Path] ERROR: No exit edge at node " .. targetNodeId)
        return
    end

    -- 开始转弯动画
    s.turnExecuting = true
    s.turnArcProgress = 0.0
    s.turnArrivalHeading = s.currentHeading
    s.turnExitHeading = exitHeading
    s.turnNodeWorldPos = Vector3(targetNode.worldX, 0, targetNode.worldZ)
    s.turnNextEdge = nextEdge
    s.turnLength = rn.GetTurnLength(s.currentHeading, exitHeading)

    -- 启动摄像机转弯
    if s.currentHeading ~= exitHeading then
        s.camTurning = true
        s.camTurnFrom = rn.HeadingToYaw(s.currentHeading)
        s.camTurnTo = rn.HeadingToYaw(exitHeading)
        -- 处理 yaw 环绕
        local diff = s.camTurnTo - s.camTurnFrom
        if diff > 180 then s.camTurnTo = s.camTurnTo - 360
        elseif diff < -180 then s.camTurnTo = s.camTurnTo + 360 end
        s.camTurnAnimTime = 0.0
    end

    -- 重置路口状态
    s.intersectionActive = false
    s.turnChoice = 0
end

--- 转弯完成
function M.FinishTurn()
    local s = M.state

    s.turnExecuting = false
    s.currentEdge = s.turnNextEdge
    s.currentHeading = s.turnExitHeading
    s.lastNodeId = s.turnNextEdge.fromNode
    s.edgeProgress = 0.0
    s.edgeDistance = 0.0
    s.turnNextEdge = nil

    print("[Path] Entered edge " .. s.currentEdge.id .. " heading " .. s.currentHeading)
end

-- ============================================================================
-- 路口检测与提示
-- ============================================================================

--- 每帧检查是否应该显示路口提示
function M.CheckIntersection()
    local s = M.state
    if s.turnExecuting then return end
    if s.intersectionActive then return end
    if not s.currentEdge then return end

    -- 当进度达到阈值时，显示路口选择
    if s.edgeProgress >= CONFIG.INTERSECTION_HINT_PROGRESS then
        local targetNodeId = s.currentEdge.toNode
        s.availableTurns = rn.GetAvailableTurns(targetNodeId, s.currentHeading)

        if #s.availableTurns > 0 then
            s.intersectionActive = true
            -- 随机推荐一个方向
            local r = math.random(1, #s.availableTurns)
            local recommended = s.availableTurns[r]
            if recommended.direction == "left" then
                s.intersectionHintDir = -1
            elseif recommended.direction == "right" then
                s.intersectionHintDir = 1
            else
                s.intersectionHintDir = 0
            end
            s.turnChoice = s.intersectionHintDir
        end
    end
end

--- 检查是否到达执行点
function M.CheckExecutePoint()
    local s = M.state
    if not s.intersectionActive then return false end
    if s.turnExecuting then return false end

    if s.edgeProgress >= CONFIG.INTERSECTION_EXECUTE_PROGRESS then
        return true
    end
    return false
end

return M
