-- ============================================================================
-- 外卖冲冲冲 - 真实路网系统 (RoadGraph) - 并行道路版
-- ============================================================================
-- 城市网格路网：节点 = 交叉路口，边 = 道路段
-- 每个方向真实存在 3 条并行道路（laneIndex 1/2/3）
-- 路口中心是 3x3 复合区域，玩家位置决定进入哪条出口路
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG

local M = {}

-- ============================================================================
-- 路网配置
-- ============================================================================
M.GRID_SIZE = 5          -- 5x5 网格
M.BLOCK_SIZE = 80.0      -- 路口间距 80 米
M.ROAD_WIDTH = 2.5       -- 单条道路宽度
M.LANE_SPACING = 3.0     -- 并行道路间距（中心到中心）
M.PARALLEL_COUNT = 3     -- 每个方向 3 条并行道路

-- 方向枚举 (heading): 0=+Z, 1=+X, 2=-Z, 3=-X
M.HEADING_POS_Z = 0
M.HEADING_POS_X = 1
M.HEADING_NEG_Z = 2
M.HEADING_NEG_X = 3

-- 路网数据
M.nodes = {}    -- [nodeId] = { id, gridX, gridZ, worldX, worldZ, edges={edgeId...} }
M.edges = {}    -- [edgeId] = { id, fromNode, toNode, heading, laneIndex, length, worldStart, worldEnd }

-- 并行 edge 快速查找表
-- parallelEdges[nodeId][heading][laneIndex] = edge
M.parallelEdges = {}

-- ============================================================================
-- 路口区域配置
-- ============================================================================
M.INTERSECTION_HALF_SIZE = CONFIG.INTERSECTION_HALF_SIZE  -- 路口区域半径

-- ============================================================================
-- 路网生成
-- ============================================================================

--- 网格坐标 → 节点ID
function M.GridToNodeId(gx, gz)
    return (gz - 1) * M.GRID_SIZE + gx
end

--- 网格坐标 → 世界坐标（路口中心）
function M.GridToWorld(gx, gz)
    local offsetX = (gx - math.ceil(M.GRID_SIZE / 2)) * M.BLOCK_SIZE
    local offsetZ = (gz - 1) * M.BLOCK_SIZE
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

--- 计算并行道路在垂直于行进方向上的偏移
--- 对竖向道路(+Z/-Z): laneIndex 影响 X 偏移 (1=左, 2=中, 3=右)
--- 对横向道路(+X/-X): laneIndex 影响 Z 偏移 (1=左侧, 2=中, 3=右侧)
--- "左/右" 以行进方向的右手侧为正
function M.GetParallelOffsetForHeading(heading, laneIndex)
    -- laneIndex: 1=左, 2=中, 3=右 (相对行进方向的右侧)
    -- 偏移量: lane1 = -LANE_SPACING, lane2 = 0, lane3 = +LANE_SPACING
    local offsetAmount = (laneIndex - 2) * M.LANE_SPACING
    local right = M.HeadingToRight(heading)
    return Vector3(right.x * offsetAmount, 0, right.z * offsetAmount)
end

--- 生成完整路网（含并行道路）
function M.Generate()
    M.nodes = {}
    M.edges = {}
    M.parallelEdges = {}

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
                edges = {},
            }
            M.parallelEdges[id] = {}
        end
    end

    -- 2) 创建所有边：每对相邻节点之间生成 3 条并行 edge
    local edgeId = 0
    for gz = 1, M.GRID_SIZE do
        for gx = 1, M.GRID_SIZE do
            local nodeId = M.GridToNodeId(gx, gz)
            local node = M.nodes[nodeId]

            -- +X 方向
            if gx < M.GRID_SIZE then
                local neighborId = M.GridToNodeId(gx + 1, gz)
                local neighbor = M.nodes[neighborId]

                for lane = 1, M.PARALLEL_COUNT do
                    local offset = M.GetParallelOffsetForHeading(M.HEADING_POS_X, lane)
                    edgeId = edgeId + 1
                    local edge = {
                        id = edgeId,
                        fromNode = nodeId,
                        toNode = neighborId,
                        heading = M.HEADING_POS_X,
                        laneIndex = lane,
                        length = M.BLOCK_SIZE,
                        worldStart = Vector3(node.worldX + offset.x, 0, node.worldZ + offset.z),
                        worldEnd = Vector3(neighbor.worldX + offset.x, 0, neighbor.worldZ + offset.z),
                    }
                    M.edges[edgeId] = edge
                    table.insert(node.edges, edgeId)

                    -- 注册快速查找
                    if not M.parallelEdges[nodeId][M.HEADING_POS_X] then
                        M.parallelEdges[nodeId][M.HEADING_POS_X] = {}
                    end
                    M.parallelEdges[nodeId][M.HEADING_POS_X][lane] = edge

                    -- 反向边
                    local revOffset = M.GetParallelOffsetForHeading(M.HEADING_NEG_X, lane)
                    edgeId = edgeId + 1
                    local revEdge = {
                        id = edgeId,
                        fromNode = neighborId,
                        toNode = nodeId,
                        heading = M.HEADING_NEG_X,
                        laneIndex = lane,
                        length = M.BLOCK_SIZE,
                        worldStart = Vector3(neighbor.worldX + revOffset.x, 0, neighbor.worldZ + revOffset.z),
                        worldEnd = Vector3(node.worldX + revOffset.x, 0, node.worldZ + revOffset.z),
                    }
                    M.edges[edgeId] = revEdge
                    table.insert(neighbor.edges, edgeId)

                    if not M.parallelEdges[neighborId][M.HEADING_NEG_X] then
                        M.parallelEdges[neighborId][M.HEADING_NEG_X] = {}
                    end
                    M.parallelEdges[neighborId][M.HEADING_NEG_X][lane] = revEdge
                end
            end

            -- +Z 方向
            if gz < M.GRID_SIZE then
                local neighborId = M.GridToNodeId(gx, gz + 1)
                local neighbor = M.nodes[neighborId]

                for lane = 1, M.PARALLEL_COUNT do
                    local offset = M.GetParallelOffsetForHeading(M.HEADING_POS_Z, lane)
                    edgeId = edgeId + 1
                    local edge = {
                        id = edgeId,
                        fromNode = nodeId,
                        toNode = neighborId,
                        heading = M.HEADING_POS_Z,
                        laneIndex = lane,
                        length = M.BLOCK_SIZE,
                        worldStart = Vector3(node.worldX + offset.x, 0, node.worldZ + offset.z),
                        worldEnd = Vector3(neighbor.worldX + offset.x, 0, neighbor.worldZ + offset.z),
                    }
                    M.edges[edgeId] = edge
                    table.insert(node.edges, edgeId)

                    if not M.parallelEdges[nodeId][M.HEADING_POS_Z] then
                        M.parallelEdges[nodeId][M.HEADING_POS_Z] = {}
                    end
                    M.parallelEdges[nodeId][M.HEADING_POS_Z][lane] = edge

                    -- 反向边
                    local revOffset = M.GetParallelOffsetForHeading(M.HEADING_NEG_Z, lane)
                    edgeId = edgeId + 1
                    local revEdge = {
                        id = edgeId,
                        fromNode = neighborId,
                        toNode = nodeId,
                        heading = M.HEADING_NEG_Z,
                        laneIndex = lane,
                        length = M.BLOCK_SIZE,
                        worldStart = Vector3(neighbor.worldX + revOffset.x, 0, neighbor.worldZ + revOffset.z),
                        worldEnd = Vector3(node.worldX + revOffset.x, 0, node.worldZ + revOffset.z),
                    }
                    M.edges[edgeId] = revEdge
                    table.insert(neighbor.edges, edgeId)

                    if not M.parallelEdges[neighborId][M.HEADING_NEG_Z] then
                        M.parallelEdges[neighborId][M.HEADING_NEG_Z] = {}
                    end
                    M.parallelEdges[neighborId][M.HEADING_NEG_Z][lane] = revEdge
                end
            end
        end
    end

    print("[RoadNetwork] Generated " .. M.GRID_SIZE * M.GRID_SIZE .. " nodes, " .. edgeId .. " edges (3 parallel per direction)")
end

-- ============================================================================
-- 路网查询
-- ============================================================================

--- 获取从某节点出发、指定 heading + laneIndex 的并行出口边
--- 核心函数：路口出口选择必须使用此函数
function M.GetParallelExitEdge(nodeId, heading, laneIndex)
    local nodeTable = M.parallelEdges[nodeId]
    if not nodeTable then return nil end
    local headingTable = nodeTable[heading]
    if not headingTable then return nil end
    return headingTable[laneIndex] or nil
end

--- 兼容旧接口：获取某节点某 heading 的中间车道 edge（lane=2）
function M.GetEdgeByHeading(nodeId, heading)
    return M.GetParallelExitEdge(nodeId, heading, 2)
end

--- 检查某节点某方向是否有出口（任意 lane 存在即可）
function M.HasExitInDirection(nodeId, heading)
    local nodeTable = M.parallelEdges[nodeId]
    if not nodeTable then return false end
    local headingTable = nodeTable[heading]
    if not headingTable then return false end
    -- 只要有任一 lane 存在就算有路
    for lane = 1, M.PARALLEL_COUNT do
        if headingTable[lane] then return true end
    end
    return false
end

--- 获取从某节点出发的所有可用方向（排除来路）
function M.GetAvailableTurns(nodeId, arrivalHeading)
    local backHeading = M.ReverseHeading(arrivalHeading)
    local turns = {}

    local leftH = M.TurnLeft(arrivalHeading)
    local straightH = arrivalHeading
    local rightH = M.TurnRight(arrivalHeading)

    if M.HasExitInDirection(nodeId, straightH) then
        table.insert(turns, { direction = "straight", heading = straightH })
    end
    if M.HasExitInDirection(nodeId, leftH) then
        table.insert(turns, { direction = "left", heading = leftH })
    end
    if M.HasExitInDirection(nodeId, rightH) then
        table.insert(turns, { direction = "right", heading = rightH })
    end

    return turns
end

-- ============================================================================
-- 路口出口选择（核心新逻辑）
-- ============================================================================

--- 将 localForward 值分成三段 → laneIndex
--- 后 1/3 → 1, 中 1/3 → 2, 前 1/3 → 3
function M.SegmentByForward(localForward, halfSize)
    local normalized = localForward / halfSize  -- -1 到 +1
    if normalized < -0.333 then
        return 1  -- 后 1/3
    elseif normalized < 0.333 then
        return 2  -- 中 1/3
    else
        return 3  -- 前 1/3
    end
end

--- 将 localRight 值分成三段 → laneIndex
--- 左 1/3 → 1, 中 1/3 → 2, 右 1/3 → 3
function M.SegmentByRight(localRight, halfSize)
    local normalized = localRight / halfSize  -- -1 到 +1
    if normalized < -0.333 then
        return 1  -- 左 1/3
    elseif normalized < 0.333 then
        return 2  -- 中 1/3
    else
        return 3  -- 右 1/3
    end
end

--- 根据玩家在路口中心区域的位置选择出口 edge
--- @param nodeId integer 路口节点 ID
--- @param approachHeading integer 进入方向
--- @param desiredTurn integer -1=左转, 0=直走, 1=右转
--- @param playerWorldPos Vector3 玩家世界坐标
--- @return table|nil exitEdge, integer|nil laneIndex
function M.SelectExitByIntersectionPosition(nodeId, approachHeading, desiredTurn, playerWorldPos)
    local node = M.nodes[nodeId]
    if not node then return nil, nil end

    local nodeCenter = Vector3(node.worldX, 0, node.worldZ)
    local fwd = M.HeadingToForward(approachHeading)
    local right = M.HeadingToRight(approachHeading)

    -- 玩家相对路口中心的偏移
    local relX = playerWorldPos.x - nodeCenter.x
    local relZ = playerWorldPos.z - nodeCenter.z

    -- 投影到进入方向的前进轴和右侧轴
    local localForward = relX * fwd.x + relZ * fwd.z
    local localRight = relX * right.x + relZ * right.z

    local halfSize = M.INTERSECTION_HALF_SIZE
    local exitHeading
    local laneIndex

    if desiredTurn == -1 then
        -- 左转：出口方向 = TurnLeft, laneIndex 由 localForward 决定
        exitHeading = M.TurnLeft(approachHeading)
        laneIndex = M.SegmentByForward(localForward, halfSize)
    elseif desiredTurn == 1 then
        -- 右转：出口方向 = TurnRight, laneIndex 由 localForward 决定
        exitHeading = M.TurnRight(approachHeading)
        laneIndex = M.SegmentByForward(localForward, halfSize)
    else
        -- 直走：出口方向 = approachHeading, laneIndex 由 localRight 决定
        exitHeading = approachHeading
        laneIndex = M.SegmentByRight(localRight, halfSize)
    end

    local edge = M.GetParallelExitEdge(nodeId, exitHeading, laneIndex)
    return edge, laneIndex, exitHeading
end

-- ============================================================================
-- 位置计算
-- ============================================================================

--- 在边上按距离获取世界坐标（考虑路口区域扣除）
--- effectiveDist: 在有效区段内走了多远（0 = 刚出路口区域）
function M.GetPositionOnEdgeByDist(edge, effectiveDist)
    local halfSize = M.INTERSECTION_HALF_SIZE
    local effectiveLen = M.GetEdgeEffectiveLength()

    -- 实际在完整边上的距离（跳过起始路口区域）
    local actualDist = halfSize + math.max(0, math.min(effectiveLen, effectiveDist))
    local t = actualDist / edge.length

    local sx, sz = edge.worldStart.x, edge.worldStart.z
    local ex, ez = edge.worldEnd.x, edge.worldEnd.z
    local px = sx + (ex - sx) * t
    local pz = sz + (ez - sz) * t

    return Vector3(px, 0, pz)
end

--- 获取边的有效行驶长度（扣除两端路口区域）
function M.GetEdgeEffectiveLength()
    return M.BLOCK_SIZE - M.INTERSECTION_HALF_SIZE * 2.0
end

--- 获取路口区域穿越总距离
function M.GetIntersectionTraverseLength()
    return M.INTERSECTION_HALF_SIZE * 2.0
end

--- 计算玩家在路口区域内的世界坐标（贝塞尔曲线穿越）
--- @param nodeWorldPos Vector3 路口中心
--- @param arrivalHeading integer 进入方向
--- @param exitHeading integer 出口方向
--- @param progress number 0..1 穿越进度
--- @param entryLaneIndex integer 进入时的 laneIndex
--- @param exitLaneIndex integer|nil 出口 laneIndex（未确定时传 nil 则使用 entryLaneIndex）
--- @return Vector3 position, number yaw
function M.GetIntersectionPosition(nodeWorldPos, arrivalHeading, exitHeading, progress, entryLaneIndex, exitLaneIndex)
    local halfSize = M.INTERSECTION_HALF_SIZE
    local t = math.max(0.0, math.min(1.0, progress))

    local entryFwd = M.HeadingToForward(arrivalHeading)
    local exitFwd = M.HeadingToForward(exitHeading)

    -- 入口 lane 偏移
    local entryOffset = M.GetParallelOffsetForHeading(arrivalHeading, entryLaneIndex)
    -- 出口 lane 偏移
    local actualExitLane = exitLaneIndex or entryLaneIndex
    local exitOffset = M.GetParallelOffsetForHeading(exitHeading, actualExitLane)

    -- 入口点：路口中心 - halfSize * 入口方向 + 入口 lane 偏移
    local entryPos = Vector3(
        nodeWorldPos.x - entryFwd.x * halfSize + entryOffset.x,
        0,
        nodeWorldPos.z - entryFwd.z * halfSize + entryOffset.z
    )

    -- 出口点：路口中心 + halfSize * 出口方向 + 出口 lane 偏移
    local exitPos = Vector3(
        nodeWorldPos.x + exitFwd.x * halfSize + exitOffset.x,
        0,
        nodeWorldPos.z + exitFwd.z * halfSize + exitOffset.z
    )

    -- 中心控制点
    local centerPos = Vector3(nodeWorldPos.x, 0, nodeWorldPos.z)

    -- 二次贝塞尔曲线
    local omt = 1.0 - t
    local px = omt * omt * entryPos.x + 2 * omt * t * centerPos.x + t * t * exitPos.x
    local pz = omt * omt * entryPos.z + 2 * omt * t * centerPos.z + t * t * exitPos.z

    -- 切线方向
    local tangentX = 2 * omt * (centerPos.x - entryPos.x) + 2 * t * (exitPos.x - centerPos.x)
    local tangentZ = 2 * omt * (centerPos.z - entryPos.z) + 2 * t * (exitPos.z - centerPos.z)
    local tangentLen = math.sqrt(tangentX * tangentX + tangentZ * tangentZ)
    if tangentLen > 0.001 then
        tangentX = tangentX / tangentLen
        tangentZ = tangentZ / tangentLen
    else
        tangentX = entryFwd.x
        tangentZ = entryFwd.z
    end

    local yaw = math.deg(math.atan(tangentX, tangentZ))

    return Vector3(px, 0, pz), yaw
end

--- 找到玩家起始位置对应的边（中间 lane）
function M.GetStartEdge()
    local startGX = math.ceil(M.GRID_SIZE / 2)
    local startGZ = 1
    local startNodeId = M.GridToNodeId(startGX, startGZ)
    local edge = M.GetParallelExitEdge(startNodeId, M.HEADING_POS_Z, 2)  -- 中间道路
    return edge, startNodeId
end

return M
