-- ============================================================================
-- 外卖冲冲冲 - 对象池模块（并行道路渲染）
-- ============================================================================
-- 每个方向渲染 3 条并行道路，路口中心渲染为 3x3 大方形区域
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local rn = require("road_network")
local mats = require("materials")

local M = {}

M.roadSegments = {}
M.lineNodes = {}
M.buildingNodes = {}
M.intersectionNodes = {}

-- 建筑色板
local buildingColors = {
    Color(0.55, 0.78, 0.82, 1.0),
    Color(0.75, 0.85, 0.60, 1.0),
    Color(0.90, 0.75, 0.55, 1.0),
    Color(0.70, 0.65, 0.85, 1.0),
    Color(0.85, 0.60, 0.65, 1.0),
    Color(0.60, 0.80, 0.70, 1.0),
}

-- ============================================================================
-- 创建单条道路段
-- ============================================================================

local function CreateRoadSegment(scene, pos, yaw, segLength, roadWidth)
    local w = roadWidth or rn.ROAD_WIDTH
    local roadNode = scene:CreateChild("RoadSeg")
    local model = roadNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.road
    roadNode.scale = Vector3(w, 0.15, segLength)
    roadNode.position = Vector3(pos.x, 0.075, pos.z)
    roadNode.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, roadNode)
end

-- ============================================================================
-- 创建路缘和人行道（只在最外侧道路两边）
-- ============================================================================

local function CreateCurbAndSidewalk(scene, pos, yaw, segLength, halfGroupWidth)
    local yawRad = math.rad(yaw)
    local rx = math.cos(yawRad)
    local rz = -math.sin(yawRad)

    -- 左侧路缘石
    local curbL = scene:CreateChild("CurbL")
    local cm = curbL:CreateComponent("StaticModel")
    cm.model = cache:GetResource("Model", "Models/Box.mdl")
    cm.material = mats.curb
    curbL.scale = Vector3(0.3, 0.35, segLength)
    curbL.position = Vector3(pos.x + rx * (halfGroupWidth + 0.15), 0.175, pos.z + rz * (halfGroupWidth + 0.15))
    curbL.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, curbL)

    -- 右侧路缘石
    local curbR = scene:CreateChild("CurbR")
    local cm2 = curbR:CreateComponent("StaticModel")
    cm2.model = cache:GetResource("Model", "Models/Box.mdl")
    cm2.material = mats.curb
    curbR.scale = Vector3(0.3, 0.35, segLength)
    curbR.position = Vector3(pos.x - rx * (halfGroupWidth + 0.15), 0.175, pos.z - rz * (halfGroupWidth + 0.15))
    curbR.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, curbR)

    -- 人行道
    local swL = scene:CreateChild("SwL")
    local sm = swL:CreateComponent("StaticModel")
    sm.model = cache:GetResource("Model", "Models/Box.mdl")
    sm.material = mats.sidewalk
    swL.scale = Vector3(2.0, 0.12, segLength)
    swL.position = Vector3(pos.x + rx * (halfGroupWidth + 1.3), 0.06, pos.z + rz * (halfGroupWidth + 1.3))
    swL.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, swL)

    local swR = scene:CreateChild("SwR")
    local sm2 = swR:CreateComponent("StaticModel")
    sm2.model = cache:GetResource("Model", "Models/Box.mdl")
    sm2.material = mats.sidewalk
    swR.scale = Vector3(2.0, 0.12, segLength)
    swR.position = Vector3(pos.x - rx * (halfGroupWidth + 1.3), 0.06, pos.z - rz * (halfGroupWidth + 1.3))
    swR.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, swR)
end

-- ============================================================================
-- 创建一组并行道路（3条）之间的分隔线
-- ============================================================================

local function CreateLaneMarkers(scene, edgeStart, edgeEnd, heading, effectiveLength)
    local yaw = rn.HeadingToYaw(heading)
    local right = rn.HeadingToRight(heading)

    -- 道路间分隔线（在 lane 1-2 和 lane 2-3 之间）
    local numLines = math.floor(effectiveLength / CONFIG.LINE_SPACING)
    for _, gapOffset in ipairs({ -rn.LANE_SPACING * 0.5, rn.LANE_SPACING * 0.5 }) do
        for i = 1, numLines do
            local t = (i - 0.5) / numLines
            local px = edgeStart.x + (edgeEnd.x - edgeStart.x) * t
            local pz = edgeStart.z + (edgeEnd.z - edgeStart.z) * t

            -- 偏移到分隔线位置
            local lx = px + right.x * gapOffset
            local lz = pz + right.z * gapOffset

            local lineNode = scene:CreateChild("LnMark")
            local lm = lineNode:CreateComponent("StaticModel")
            lm.model = cache:GetResource("Model", "Models/Box.mdl")
            lm.material = mats.laneLine
            lineNode.scale = Vector3(0.12, 0.05, CONFIG.LINE_LENGTH)
            lineNode.position = Vector3(lx, 0.16, lz)
            lineNode.rotation = Quaternion(yaw, Vector3.UP)
            table.insert(M.lineNodes, lineNode)
        end
    end
end

-- ============================================================================
-- 创建建筑（沿路段两侧）
-- ============================================================================

local function CreateBuildingsAlongEdge(scene, edgeStart, edgeEnd, heading, edgeLength)
    local right = rn.HeadingToRight(heading)
    local numBuildings = CONFIG.BUILDINGS_PER_EDGE

    -- 建筑区域从道路组外侧开始
    local groupHalfWidth = rn.LANE_SPACING + rn.ROAD_WIDTH * 0.5 + 2.5
    local buildStart = groupHalfWidth + 2.0
    local buildEnd = groupHalfWidth + 12.0

    for i = 1, numBuildings do
        local t = (i - 0.5) / numBuildings
        if t > 0.1 and t < 0.9 then
            local px = edgeStart.x + (edgeEnd.x - edgeStart.x) * t
            local pz = edgeStart.z + (edgeEnd.z - edgeStart.z) * t

            for _, side in ipairs({-1, 1}) do
                if math.random() > 0.3 then
                    local lateral = buildStart + math.random() * (buildEnd - buildStart)
                    local bx = px + right.x * side * lateral
                    local bz = pz + right.z * side * lateral

                    local h = math.random() * 8 + 3
                    local w = math.random() * 2.5 + 1.5
                    local d = math.random() * 2.5 + 1.5

                    local node = scene:CreateChild("Building")
                    local model = node:CreateComponent("StaticModel")
                    model.model = cache:GetResource("Model", "Models/Box.mdl")
                    local colorIdx = math.random(1, #buildingColors)
                    model.material = mats.CreatePBRMaterial(buildingColors[colorIdx], 0.0, 0.7)
                    node.scale = Vector3(w, h, d)
                    node.position = Vector3(bx, h * 0.5, bz)
                    node.rotation = Quaternion(rn.HeadingToYaw(heading) + math.random(-5, 5), Vector3.UP)
                    table.insert(M.buildingNodes, node)
                end
            end
        end
    end
end

-- ============================================================================
-- 创建路口地面（3x3 大方形区域）
-- ============================================================================

local function CreateIntersection(scene, node)
    local iNode = scene:CreateChild("Intersection")
    local model = iNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.crossroads
    -- 区域尺寸：需覆盖 3 条并行道路的宽度
    -- 总宽 = LANE_SPACING * 2 + ROAD_WIDTH * 3 （加点余量）
    local groupWidth = rn.LANE_SPACING * 2 + rn.ROAD_WIDTH
    local areaSize = math.max(rn.INTERSECTION_HALF_SIZE * 2.0, groupWidth) + 2.0
    iNode.scale = Vector3(areaSize, 0.16, areaSize)
    iNode.position = Vector3(node.worldX, 0.08, node.worldZ)
    table.insert(M.intersectionNodes, iNode)
end

-- ============================================================================
-- 初始化：根据路网生成全部道路视觉
-- ============================================================================

function M.Init(scene)
    print("[Pools] Building road visuals from RoadGraph (parallel roads)...")

    -- 渲染所有路口
    for _, node in pairs(rn.nodes) do
        CreateIntersection(scene, node)
    end

    -- 渲染并行道路
    -- 对每对相邻节点只渲染一次（避免正反 edge 重复）
    local renderedPairs = {}

    for _, edge in pairs(rn.edges) do
        -- 只处理 heading 0 (+Z) 或 heading 1 (+X) 避免重复
        if edge.heading == rn.HEADING_POS_Z or edge.heading == rn.HEADING_POS_X then
            local pairKey = math.min(edge.fromNode, edge.toNode) * 10000 +
                math.max(edge.fromNode, edge.toNode) * 10 + edge.laneIndex
            if not renderedPairs[pairKey] then
                renderedPairs[pairKey] = true

                local heading = edge.heading
                local yaw = rn.HeadingToYaw(heading)
                local fwd = rn.HeadingToForward(heading)

                -- 缩短道路，避免与路口区域重叠
                local shrink = rn.INTERSECTION_HALF_SIZE + 0.5
                local effectiveStart = Vector3(
                    edge.worldStart.x + fwd.x * shrink,
                    0,
                    edge.worldStart.z + fwd.z * shrink
                )
                local effectiveEnd = Vector3(
                    edge.worldEnd.x - fwd.x * shrink,
                    0,
                    edge.worldEnd.z - fwd.z * shrink
                )
                local effectiveLength = edge.length - shrink * 2

                if effectiveLength > 0 then
                    -- 铺设道路段
                    local numSegs = CONFIG.ROAD_SEGMENTS_PER_EDGE
                    local effSegLen = effectiveLength / numSegs
                    for i = 1, numSegs do
                        local t = (i - 0.5) / numSegs
                        local px = effectiveStart.x + (effectiveEnd.x - effectiveStart.x) * t
                        local pz = effectiveStart.z + (effectiveEnd.z - effectiveStart.z) * t
                        CreateRoadSegment(scene, Vector3(px, 0, pz), yaw, effSegLen, rn.ROAD_WIDTH)
                    end
                end
            end
        end
    end

    -- 为每个"道路组"（3条并行道路）渲染分隔线、路缘、人行道、建筑
    -- 只需要按方向对处理一次
    local renderedGroups = {}
    for _, edge in pairs(rn.edges) do
        if (edge.heading == rn.HEADING_POS_Z or edge.heading == rn.HEADING_POS_X) and edge.laneIndex == 2 then
            local groupKey = math.min(edge.fromNode, edge.toNode) * 100 + math.max(edge.fromNode, edge.toNode)
            if not renderedGroups[groupKey] then
                renderedGroups[groupKey] = true

                local heading = edge.heading
                local fwd = rn.HeadingToForward(heading)
                local yaw = rn.HeadingToYaw(heading)
                local shrink = rn.INTERSECTION_HALF_SIZE + 0.5

                local effectiveStart = Vector3(
                    edge.worldStart.x + fwd.x * shrink,
                    0,
                    edge.worldStart.z + fwd.z * shrink
                )
                local effectiveEnd = Vector3(
                    edge.worldEnd.x - fwd.x * shrink,
                    0,
                    edge.worldEnd.z - fwd.z * shrink
                )
                local effectiveLength = edge.length - shrink * 2

                if effectiveLength > 0 then
                    -- 分隔线
                    CreateLaneMarkers(scene, effectiveStart, effectiveEnd, heading, effectiveLength)

                    -- 路缘和人行道（在道路组的中心线位置）
                    local midT = 0.5
                    local midX = effectiveStart.x + (effectiveEnd.x - effectiveStart.x) * midT
                    local midZ = effectiveStart.z + (effectiveEnd.z - effectiveStart.z) * midT
                    local halfGroupWidth = rn.LANE_SPACING + rn.ROAD_WIDTH * 0.5
                    CreateCurbAndSidewalk(scene, Vector3(midX, 0, midZ), yaw, effectiveLength, halfGroupWidth)
                end

                -- 建筑：使用原始 edge 坐标
                local fromNode = rn.nodes[edge.fromNode]
                local toNode = rn.nodes[edge.toNode]
                local fullStart = Vector3(fromNode.worldX, 0, fromNode.worldZ)
                local fullEnd = Vector3(toNode.worldX, 0, toNode.worldZ)
                CreateBuildingsAlongEdge(scene, fullStart, fullEnd, heading, edge.length)
            end
        end
    end

    print("[Pools] Created " .. #M.roadSegments .. " road parts, " ..
        #M.lineNodes .. " lane markers, " ..
        #M.buildingNodes .. " buildings, " ..
        #M.intersectionNodes .. " intersections")
end

return M
