-- ============================================================================
-- 外卖冲冲冲 - 对象池模块（基于 RoadGraph 真实路网渲染）
-- ============================================================================
-- 所有道路段、车道线、建筑根据路网 edge 真实摆放
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local rn = require("road_network")
local mats = require("materials")

local M = {}

-- 场景对象列表（不再是循环回收池，而是一次性创建所有路网视觉）
M.roadSegments = {}    -- 所有道路段节点
M.lineNodes = {}       -- 所有车道线节点
M.buildingNodes = {}   -- 所有建筑节点
M.intersectionNodes = {} -- 所有路口地面节点

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
-- 创建道路段（一个 edge 铺多段）
-- ============================================================================

local function CreateRoadSegment(scene, pos, yaw, segLength)
    local roadNode = scene:CreateChild("RoadSeg")
    local model = roadNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.road
    roadNode.scale = Vector3(CONFIG.ROAD_WIDTH, 0.15, segLength)
    roadNode.position = Vector3(pos.x, 0.075, pos.z)
    roadNode.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, roadNode)

    -- 路缘石
    local halfRoad = CONFIG.ROAD_WIDTH * 0.5
    local yawRad = math.rad(yaw)
    local rx = math.cos(yawRad)
    local rz = -math.sin(yawRad)

    local curbL = scene:CreateChild("CurbL")
    local cm = curbL:CreateComponent("StaticModel")
    cm.model = cache:GetResource("Model", "Models/Box.mdl")
    cm.material = mats.curb
    curbL.scale = Vector3(0.3, 0.35, segLength)
    curbL.position = Vector3(pos.x + rx * (halfRoad + 0.15), 0.175, pos.z + rz * (halfRoad + 0.15))
    curbL.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, curbL)

    local curbR = scene:CreateChild("CurbR")
    local cm2 = curbR:CreateComponent("StaticModel")
    cm2.model = cache:GetResource("Model", "Models/Box.mdl")
    cm2.material = mats.curb
    curbR.scale = Vector3(0.3, 0.35, segLength)
    curbR.position = Vector3(pos.x - rx * (halfRoad + 0.15), 0.175, pos.z - rz * (halfRoad + 0.15))
    curbR.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, curbR)

    -- 人行道
    local swL = scene:CreateChild("SwL")
    local sm = swL:CreateComponent("StaticModel")
    sm.model = cache:GetResource("Model", "Models/Box.mdl")
    sm.material = mats.sidewalk
    swL.scale = Vector3(2.5, 0.12, segLength)
    swL.position = Vector3(pos.x + rx * (halfRoad + 1.55), 0.06, pos.z + rz * (halfRoad + 1.55))
    swL.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, swL)

    local swR = scene:CreateChild("SwR")
    local sm2 = swR:CreateComponent("StaticModel")
    sm2.model = cache:GetResource("Model", "Models/Box.mdl")
    sm2.material = mats.sidewalk
    swR.scale = Vector3(2.5, 0.12, segLength)
    swR.position = Vector3(pos.x - rx * (halfRoad + 1.55), 0.06, pos.z - rz * (halfRoad + 1.55))
    swR.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, swR)
end

-- ============================================================================
-- 创建车道线
-- ============================================================================

local function CreateLaneLines(scene, edgeStart, edgeEnd, heading, edgeLength)
    local yaw = rn.HeadingToYaw(heading)
    local fwd = rn.HeadingToForward(heading)
    local right = rn.HeadingToRight(heading)

    local numLines = math.floor(edgeLength / CONFIG.LINE_SPACING)
    for i = 1, numLines do
        local t = (i - 0.5) / numLines
        local px = edgeStart.x + (edgeEnd.x - edgeStart.x) * t
        local pz = edgeStart.z + (edgeEnd.z - edgeStart.z) * t

        -- 左车道线
        local nodeL = scene:CreateChild("LineL")
        local mL = nodeL:CreateComponent("StaticModel")
        mL.model = cache:GetResource("Model", "Models/Box.mdl")
        mL.material = mats.laneLine
        nodeL.scale = Vector3(0.12, 0.05, CONFIG.LINE_LENGTH)
        nodeL.position = Vector3(px - right.x * 1.0, 0.16, pz - right.z * 1.0)
        nodeL.rotation = Quaternion(yaw, Vector3.UP)
        table.insert(M.lineNodes, nodeL)

        -- 右车道线
        local nodeR = scene:CreateChild("LineR")
        local mR = nodeR:CreateComponent("StaticModel")
        mR.model = cache:GetResource("Model", "Models/Box.mdl")
        mR.material = mats.laneLine
        nodeR.scale = Vector3(0.12, 0.05, CONFIG.LINE_LENGTH)
        nodeR.position = Vector3(px + right.x * 1.0, 0.16, pz + right.z * 1.0)
        nodeR.rotation = Quaternion(yaw, Vector3.UP)
        table.insert(M.lineNodes, nodeR)
    end
end

-- ============================================================================
-- 创建建筑（沿 edge 两侧）
-- ============================================================================

local function CreateBuildingsAlongEdge(scene, edgeStart, edgeEnd, heading, edgeLength)
    local fwd = rn.HeadingToForward(heading)
    local right = rn.HeadingToRight(heading)

    local numBuildings = CONFIG.BUILDINGS_PER_EDGE
    for i = 1, numBuildings do
        local t = (i - 0.5) / numBuildings
        -- 避开路口区域（留空 15%）
        if t > 0.1 and t < 0.9 then
            local px = edgeStart.x + (edgeEnd.x - edgeStart.x) * t
            local pz = edgeStart.z + (edgeEnd.z - edgeStart.z) * t

            for _, side in ipairs({-1, 1}) do
                if math.random() > 0.3 then  -- 70% 概率生成建筑
                    local lateral = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
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
-- 创建路口地面
-- ============================================================================

local function CreateIntersection(scene, node)
    local iNode = scene:CreateChild("Intersection")
    local model = iNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.crossroads
    -- 路口是正方形区域
    local size = CONFIG.ROAD_WIDTH + 1.0
    iNode.scale = Vector3(size, 0.16, size)
    iNode.position = Vector3(node.worldX, 0.08, node.worldZ)
    table.insert(M.intersectionNodes, iNode)
end

-- ============================================================================
-- 初始化：根据路网生成全部道路视觉
-- ============================================================================

function M.Init(scene)
    print("[Pools] Building road visuals from RoadGraph...")

    -- 渲染所有路口
    for _, node in pairs(rn.nodes) do
        CreateIntersection(scene, node)
    end

    -- 渲染所有边（只渲染正向避免重复：heading 0 或 1）
    -- 实际上每条有向边都渲染一次会导致重叠，我们只渲染 "物理道路" 一次
    local renderedPairs = {}
    for _, edge in pairs(rn.edges) do
        -- 用较小的 nodeId 作为 key 避免重复
        local pairKey = math.min(edge.fromNode, edge.toNode) * 1000 + math.max(edge.fromNode, edge.toNode)
        if not renderedPairs[pairKey] then
            renderedPairs[pairKey] = true

            local start = edge.worldStart
            local finish = edge.worldEnd
            local heading = edge.heading
            local length = edge.length

            -- 道路段铺设（沿 edge 中心线铺设多段）
            local numSegs = CONFIG.ROAD_SEGMENTS_PER_EDGE
            local segLen = length / numSegs
            local yaw = rn.HeadingToYaw(heading)

            -- 缩短道路段，避免与路口地面重叠
            local shrink = CONFIG.ROAD_WIDTH * 0.5 + 0.5  -- 路口一半宽度
            local effectiveStart = Vector3(
                start.x + rn.HeadingToForward(heading).x * shrink,
                0,
                start.z + rn.HeadingToForward(heading).z * shrink
            )
            local effectiveEnd = Vector3(
                finish.x - rn.HeadingToForward(heading).x * shrink,
                0,
                finish.z - rn.HeadingToForward(heading).z * shrink
            )
            local effectiveLength = length - shrink * 2

            if effectiveLength > 0 then
                local effSegLen = effectiveLength / numSegs
                for i = 1, numSegs do
                    local t = (i - 0.5) / numSegs
                    local px = effectiveStart.x + (effectiveEnd.x - effectiveStart.x) * t
                    local pz = effectiveStart.z + (effectiveEnd.z - effectiveStart.z) * t
                    CreateRoadSegment(scene, Vector3(px, 0, pz), yaw, effSegLen)
                end

                -- 车道线
                CreateLaneLines(scene, effectiveStart, effectiveEnd, heading, effectiveLength)
            end

            -- 建筑
            CreateBuildingsAlongEdge(scene, start, finish, heading, length)
        end
    end

    print("[Pools] Created " .. #M.roadSegments .. " road parts, " .. #M.lineNodes .. " lane lines, " .. #M.buildingNodes .. " buildings, " .. #M.intersectionNodes .. " intersections")
end

return M
