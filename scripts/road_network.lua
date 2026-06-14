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
-- 路口区域（3x3 复合模型）
-- ============================================================================
-- 路口中心是一个正方形区域，尺寸 = INTERSECTION_HALF_SIZE * 2
-- 玩家物理进入区域后选择方向，根据区域内位置决定出口车道
-- ============================================================================

M.INTERSECTION_HALF_SIZE = CONFIG.INTERSECTION_HALF_SIZE  -- 引用 config

--- 获取路口区域穿越的总距离（从入边界到出边界 = 整个区域对角方向不需要，实际就是全宽）
function M.GetIntersectionTraverseLength()
    return M.INTERSECTION_HALF_SIZE * 2.0
end

--- 计算玩家在路口区域内的世界坐标
--- nodeWorldPos: 路口中心世界坐标
--- arrivalHeading: 进入路口时的 heading
--- exitHeading: 离开路口时的 heading（可能和 arrival 不同，即转弯）
--- progress: 0..1 在路口区域内的线性进度
--- laneOffset: 车道偏移（进入路口时的车道偏移）
--- exitLaneOffset: 出口车道的偏移目标值（转弯时用于平滑过渡）
function M.GetIntersectionPosition(nodeWorldPos, arrivalHeading, exitHeading, progress, laneOffset, exitLaneOffset)
    local halfSize = M.INTERSECTION_HALF_SIZE
    local t = math.max(0.0, math.min(1.0, progress))

    local entryFwd = M.HeadingToForward(arrivalHeading)
    local exitFwd = M.HeadingToForward(exitHeading)
    local entryRight = M.HeadingToRight(arrivalHeading)

    -- 入口点：路口中心 - halfSize * 入口方向（区域边缘）
    local entryPos = Vector3(
        nodeWorldPos.x - entryFwd.x * halfSize,
        0,
        nodeWorldPos.z - entryFwd.z * halfSize
    )

    -- 出口点：路口中心 + halfSize * 出口方向（区域边缘）
    local exitPos = Vector3(
        nodeWorldPos.x + exitFwd.x * halfSize,
        0,
        nodeWorldPos.z + exitFwd.z * halfSize
    )

    -- 路口中心（可选：S型曲线的中间控制点）
    local centerPos = Vector3(nodeWorldPos.x, 0, nodeWorldPos.z)

    -- 使用二次贝塞尔曲线让转弯更自然
    -- B(t) = (1-t)² * P0 + 2(1-t)t * P1 + t² * P2
    local omt = 1.0 - t
    local px = omt * omt * entryPos.x + 2 * omt * t * centerPos.x + t * t * exitPos.x
    local pz = omt * omt * entryPos.z + 2 * omt * t * centerPos.z + t * t * exitPos.z

    -- 切线方向（贝塞尔导数）：B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1)
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

    -- 切线的右侧方向（用于车道偏移）
    local tangentRightX = tangentZ
    local tangentRightZ = -tangentX

    -- 应用车道偏移
    local effectiveLaneOffset = laneOffset
    if arrivalHeading ~= exitHeading then
        -- 转弯时：从入口偏移平滑过渡到出口偏移
        -- t=0: laneOffset（入口车道位置），t=1: exitLaneOffset（出口车道位置）
        local targetOffset = exitLaneOffset or (-laneOffset)  -- fallback 兼容
        effectiveLaneOffset = laneOffset + (targetOffset - laneOffset) * t
    end
    px = px + tangentRightX * effectiveLaneOffset
    pz = pz + tangentRightZ * effectiveLaneOffset

    -- 计算 yaw（从切线方向得到）
    local yaw = math.deg(math.atan(tangentX, tangentZ))

    return Vector3(px, 0, pz), yaw
end

--- 根据玩家在路口区域内的位置决定出口车道
--- 规则：
---   直行时：保持当前车道不变（横向位置直接映射）
---   转弯（左转/右转）时：由进入时的纵向位置（进度）决定出口车道
---     高进度（上区，接近路口远端）→ exit lane 对应 "上路"
---     低进度（下区，接近路口入口）→ exit lane 对应 "下路"
---
---   几何原理：90° 转弯时，入口方向的纵向坐标映射为出口方向的横向坐标
---   例如 heading +Z 右转到 +X 时：
---     高 Z（高进度）→ 高 Z 在 +X 路上 = 右上路 = exit lane 1
---     低 Z（低进度）→ 低 Z 在 +X 路上 = 右下路 = exit lane 3
---
--- @param arrivalHeading integer 进入方向
--- @param exitHeading integer 出口方向
--- @param progress number 0..1 路口内前进进度（选择方向时的进度快照）
--- @param currentLane integer 当前车道 1/2/3
--- @return integer exitLane 出口车道 1/2/3
function M.SelectExitLane(arrivalHeading, exitHeading, progress, currentLane)
    if arrivalHeading == exitHeading then
        -- 直走：保持当前车道
        return currentLane
    else
        -- 转弯：由纵向进度决定出口车道
        -- 几何原理：90°转弯将入口纵向坐标映射到出口横向坐标
        -- 右转和左转的映射方向相反（坐标轴翻转）
        local isRightTurn = (exitHeading == (arrivalHeading + 1) % 4)

        if isRightTurn then
            -- 右转：高进度 → lane 1（保持空间"上"位置）
            if progress >= 0.667 then
                return 1
            elseif progress >= 0.333 then
                return 2
            else
                return 3
            end
        else
            -- 左转：高进度 → lane 3（镜像，保持空间"上"位置）
            if progress >= 0.667 then
                return 3
            elseif progress >= 0.333 then
                return 2
            else
                return 1
            end
        end
    end
end

--- 获取边的有效起始距离（从路口区域边界开始）
--- 边的世界坐标包含路口区域内的部分，实际可行驶长度需要扣除两端路口区域
function M.GetEdgeEffectiveLength()
    return M.BLOCK_SIZE - M.INTERSECTION_HALF_SIZE * 2.0
end

--- 获取边上某进度对应的世界坐标（考虑路口区域扣除）
--- effectiveDist: 在有效区段内走了多远（0 = 刚出路口区域）
function M.GetPositionOnEdgeByDist(edge, effectiveDist, laneOffset)
    local halfSize = M.INTERSECTION_HALF_SIZE
    local effectiveLen = M.GetEdgeEffectiveLength()

    -- 实际在完整边上的距离（跳过起始路口区域）
    local actualDist = halfSize + math.max(0, math.min(effectiveLen, effectiveDist))
    local t = actualDist / edge.length

    local sx, sz = edge.worldStart.x, edge.worldStart.z
    local ex, ez = edge.worldEnd.x, edge.worldEnd.z
    local px = sx + (ex - sx) * t
    local pz = sz + (ez - sz) * t

    -- 车道偏移
    local right = M.HeadingToRight(edge.heading)
    px = px + right.x * laneOffset
    pz = pz + right.z * laneOffset

    return Vector3(px, 0, pz)
end

return M
