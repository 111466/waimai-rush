-- ============================================================================
-- 外卖冲冲冲 - 真实路网系统 (RoadGraph)
-- ============================================================================
-- 城市网格路网：节点 = 交叉路口，边 = 道路段
-- 5x5 网格，间距 80m，所有道路同时存在
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG

local M = {}

-- ============================================================================
-- 路网配置
-- ============================================================================
M.GRID_SIZE = 5          -- 5x5 网格
M.BLOCK_SIZE = 80.0      -- 路口间距 80 米
M.ROAD_WIDTH = 7.0       -- 道路宽度（与 CONFIG 一致）

-- 方向枚举 (heading): 0=+Z, 1=+X, 2=-Z, 3=-X
M.HEADING_POS_Z = 0
M.HEADING_POS_X = 1
M.HEADING_NEG_Z = 2
M.HEADING_NEG_X = 3

-- 路网数据
M.nodes = {}    -- [nodeId] = { id, gridX, gridZ, worldX, worldZ, edges={edgeId...} }
M.edges = {}    -- [edgeId] = { id, fromNode, toNode, heading, length, worldStart, worldEnd }

-- ============================================================================
-- 路网生成
-- ============================================================================

--- 网格坐标 → 节点ID
function M.GridToNodeId(gx, gz)
    return (gz - 1) * M.GRID_SIZE + gx
end

--- 网格坐标 → 世界坐标（路口中心）
function M.GridToWorld(gx, gz)
    -- 网格中心在原点附近，玩家从 (3,1) 起步朝 +Z
    local offsetX = (gx - math.ceil(M.GRID_SIZE / 2)) * M.BLOCK_SIZE
    local offsetZ = (gz - 1) * M.BLOCK_SIZE  -- Z从0开始向前
    return offsetX, offsetZ
end

--- 根据两个节点的相对位置计算 heading
function M.CalcHeading(fromNode, toNode)
    local dx = toNode.worldX - fromNode.worldX
    local dz = toNode.worldZ - fromNode.worldZ
    if math.abs(dz) > math.abs(dx) then
        return dz > 0 and M.HEADING_POS_Z or M.HEADING_NEG_Z
    else
        return dx > 0 and M.HEADING_POS_X or M.HEADING_NEG_X
    end
end

--- heading → 前进方向向量
function M.HeadingToForward(heading)
    if heading == 0 then return Vector3(0, 0, 1)
    elseif heading == 1 then return Vector3(1, 0, 0)
    elseif heading == 2 then return Vector3(0, 0, -1)
    elseif heading == 3 then return Vector3(-1, 0, 0)
    end
    return Vector3(0, 0, 1)
end

--- heading → 右侧方向向量
function M.HeadingToRight(heading)
    if heading == 0 then return Vector3(1, 0, 0)
    elseif heading == 1 then return Vector3(0, 0, -1)
    elseif heading == 2 then return Vector3(-1, 0, 0)
    elseif heading == 3 then return Vector3(0, 0, 1)
    end
    return Vector3(1, 0, 0)
end

--- heading → yaw 角度
function M.HeadingToYaw(heading)
    return heading * 90.0
end

--- 反转 heading
function M.ReverseHeading(heading)
    return (heading + 2) % 4
end

--- 左转 heading
function M.TurnLeft(heading)
    return (heading + 3) % 4
end

--- 右转 heading
function M.TurnRight(heading)
    return (heading + 1) % 4
end

--- 生成完整路网
function M.Generate()
    M.nodes = {}
    M.edges = {}

    -- 1) 创建所有节点
    for gz = 1, M.GRID_SIZE do
        for gx = 1, M.GRID_SIZE do
            local id = M.GridToNodeId(gx, gz)
            local wx, wz = M.GridToWorld(gx, gz)
            M.nodes[id] = {
                id = id,
                gridX = gx,
                gridZ = gz,
                worldX = wx,
                worldZ = wz,
                edges = {},  -- 从该节点出发的 edgeId 列表
            }
        end
    end

    -- 2) 创建所有边（双向：每对相邻节点产生 2 条有向边）
    local edgeId = 0
    for gz = 1, M.GRID_SIZE do
        for gx = 1, M.GRID_SIZE do
            local nodeId = M.GridToNodeId(gx, gz)
            local node = M.nodes[nodeId]

            -- +X 方向的边
            if gx < M.GRID_SIZE then
                local neighborId = M.GridToNodeId(gx + 1, gz)
                local neighbor = M.nodes[neighborId]
                edgeId = edgeId + 1
                local edge = {
                    id = edgeId,
                    fromNode = nodeId,
                    toNode = neighborId,
                    heading = M.HEADING_POS_X,
                    length = M.BLOCK_SIZE,
                    worldStart = Vector3(node.worldX, 0, node.worldZ),
                    worldEnd = Vector3(neighbor.worldX, 0, neighbor.worldZ),
                }
                M.edges[edgeId] = edge
                table.insert(node.edges, edgeId)

                -- 反向边
                edgeId = edgeId + 1
                local revEdge = {
                    id = edgeId,
                    fromNode = neighborId,
                    toNode = nodeId,
                    heading = M.HEADING_NEG_X,
                    length = M.BLOCK_SIZE,
                    worldStart = Vector3(neighbor.worldX, 0, neighbor.worldZ),
                    worldEnd = Vector3(node.worldX, 0, node.worldZ),
                }
                M.edges[edgeId] = revEdge
                table.insert(neighbor.edges, edgeId)
            end

            -- +Z 方向的边
            if gz < M.GRID_SIZE then
                local neighborId = M.GridToNodeId(gx, gz + 1)
                local neighbor = M.nodes[neighborId]
                edgeId = edgeId + 1
                local edge = {
                    id = edgeId,
                    fromNode = nodeId,
                    toNode = neighborId,
                    heading = M.HEADING_POS_Z,
                    length = M.BLOCK_SIZE,
                    worldStart = Vector3(node.worldX, 0, node.worldZ),
                    worldEnd = Vector3(neighbor.worldX, 0, neighbor.worldZ),
                }
                M.edges[edgeId] = edge
                table.insert(node.edges, edgeId)

                -- 反向边
                edgeId = edgeId + 1
                local revEdge = {
                    id = edgeId,
                    fromNode = neighborId,
                    toNode = nodeId,
                    heading = M.HEADING_NEG_Z,
                    length = M.BLOCK_SIZE,
                    worldStart = Vector3(neighbor.worldX, 0, neighbor.worldZ),
                    worldEnd = Vector3(node.worldX, 0, node.worldZ),
                }
                M.edges[edgeId] = revEdge
                table.insert(neighbor.edges, edgeId)
            end
        end
    end

    print("[RoadNetwork] Generated " .. #M.nodes .. " nodes, " .. #M.edges .. " edges")
end

-- ============================================================================
-- 路网查询
-- ============================================================================

--- 获取从某节点出发、指定 heading 的边
function M.GetEdgeByHeading(nodeId, heading)
    local node = M.nodes[nodeId]
    if not node then return nil end
    for _, eid in ipairs(node.edges) do
        local edge = M.edges[eid]
        if edge and edge.heading == heading then
            return edge
        end
    end
    return nil
end

--- 获取从某节点出发的所有可用方向（排除来路）
function M.GetAvailableTurns(nodeId, arrivalHeading)
    local node = M.nodes[nodeId]
    if not node then return {} end

    local backHeading = M.ReverseHeading(arrivalHeading)
    local turns = {}  -- { direction="left"/"straight"/"right", edge=edge, heading=h }

    local leftH = M.TurnLeft(arrivalHeading)
    local straightH = arrivalHeading
    local rightH = M.TurnRight(arrivalHeading)

    for _, eid in ipairs(node.edges) do
        local edge = M.edges[eid]
        if edge.heading == straightH then
            table.insert(turns, { direction = "straight", edge = edge, heading = straightH })
        elseif edge.heading == leftH then
            table.insert(turns, { direction = "left", edge = edge, heading = leftH })
        elseif edge.heading == rightH then
            table.insert(turns, { direction = "right", edge = edge, heading = rightH })
        end
        -- 排除 backHeading（掉头）
    end

    return turns
end

--- 在边上插值获取世界坐标
--- progress: 0..1 表示在该边上的进度
--- laneOffset: 左右偏移（车道）
function M.GetPositionOnEdge(edge, progress, laneOffset)
    local t = math.max(0, math.min(1, progress))
    local sx, sz = edge.worldStart.x, edge.worldStart.z
    local ex, ez = edge.worldEnd.x, edge.worldEnd.z
    local px = sx + (ex - sx) * t
    local pz = sz + (ez - sz) * t

    -- 加上车道偏移（垂直于前进方向）
    local right = M.HeadingToRight(edge.heading)
    px = px + right.x * laneOffset
    pz = pz + right.z * laneOffset

    return Vector3(px, 0, pz)
end

--- 获取边上某进度处的距离（从边起点算）
function M.GetDistanceOnEdge(edge, progress)
    return edge.length * math.max(0, math.min(1, progress))
end

--- 找到玩家起始位置对应的边
function M.GetStartEdge()
    -- 从网格中间底部出发，朝 +Z
    local startGX = math.ceil(M.GRID_SIZE / 2)
    local startGZ = 1
    local startNodeId = M.GridToNodeId(startGX, startGZ)
    local edge = M.GetEdgeByHeading(startNodeId, M.HEADING_POS_Z)
    return edge, startNodeId
end

-- ============================================================================
-- 转弯几何（圆弧过渡）
-- ============================================================================
M.TURN_RADIUS = 6.0         -- 转弯半径
M.TURN_ARC_LENGTH = 6.0 * math.pi * 0.5  -- 四分之一圆弧

--- 计算转弯圆弧上的点
--- nodeWorldPos: 路口中心世界坐标
--- arrivalHeading: 进入路口时的 heading
--- exitHeading: 离开路口时的 heading
--- arcProgress: 0..1 圆弧进度
--- laneOffset: 车道偏移
function M.GetTurnPosition(nodeWorldPos, arrivalHeading, exitHeading, arcProgress, laneOffset)
    local radius = M.TURN_RADIUS
    local angle = math.min(math.max(arcProgress, 0.0), 1.0) * math.pi * 0.5

    local fwd = M.HeadingToForward(arrivalHeading)
    local right = M.HeadingToRight(arrivalHeading)

    -- 判断转弯方向
    local turnDir  -- 1=右转, -1=左转
    local diff = (exitHeading - arrivalHeading + 4) % 4
    if diff == 1 then
        turnDir = 1   -- 右转
    elseif diff == 3 then
        turnDir = -1  -- 左转
    else
        -- 直走不需要弧线，线性插值即可
        local startPos = Vector3(
            nodeWorldPos.x - fwd.x * radius,
            0,
            nodeWorldPos.z - fwd.z * radius
        )
        local endFwd = M.HeadingToForward(exitHeading)
        local endPos = Vector3(
            nodeWorldPos.x + endFwd.x * radius,
            0,
            nodeWorldPos.z + endFwd.z * radius
        )
        local px = startPos.x + (endPos.x - startPos.x) * arcProgress
        local pz = startPos.z + (endPos.z - startPos.z) * arcProgress
        local tangentRight = M.HeadingToRight(arrivalHeading)
        px = px + tangentRight.x * laneOffset
        pz = pz + tangentRight.z * laneOffset
        return Vector3(px, 0, pz), arrivalHeading
    end

    -- 圆弧中心
    local center = Vector3(
        nodeWorldPos.x + right.x * turnDir * radius - fwd.x * radius,
        0,
        nodeWorldPos.z + right.z * turnDir * radius - fwd.z * radius
    )

    -- 从圆心出发的径向 起始方向
    local radialStart = Vector3(-right.x * turnDir, 0, -right.z * turnDir)

    local cosA = math.cos(angle)
    local sinA = math.sin(angle)

    local radial = Vector3(
        radialStart.x * cosA + fwd.x * sinA,
        0,
        radialStart.z * cosA + fwd.z * sinA
    )

    -- 切线方向（用于车道偏移）
    local tangent = Vector3(
        -radialStart.x * sinA + fwd.x * cosA,
        0,
        -radialStart.z * sinA + fwd.z * cosA
    )
    local tangentRight = Vector3(tangent.z, 0, -tangent.x)
    if turnDir == -1 then
        tangentRight = Vector3(-tangent.z, 0, tangent.x)
    end

    local pos = Vector3(
        center.x + radial.x * radius + tangentRight.x * laneOffset,
        0,
        center.z + radial.z * radius + tangentRight.z * laneOffset
    )

    -- 计算当前 yaw
    local fromYaw = M.HeadingToYaw(arrivalHeading)
    local toYaw = M.HeadingToYaw(exitHeading)
    local yawDiff = toYaw - fromYaw
    if yawDiff > 180 then toYaw = toYaw - 360
    elseif yawDiff < -180 then toYaw = toYaw + 360 end
    local currentYaw = fromYaw + (toYaw - fromYaw) * arcProgress

    return pos, currentYaw
end

--- 获取弧线过渡的总长度
function M.GetTurnLength(arrivalHeading, exitHeading)
    local diff = (exitHeading - arrivalHeading + 4) % 4
    if diff == 1 or diff == 3 then
        return M.TURN_ARC_LENGTH  -- 90度弧
    else
        return M.TURN_RADIUS * 2  -- 直走穿过路口
    end
end

return M
