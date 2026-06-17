-- ============================================================================
-- 外卖冲冲冲 - 对象池模块（基于 RoadGraph 流式渲染）
-- ============================================================================
-- 只维护玩家周围可见窗口的道路、车道线、建筑和路口视觉。
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local rn = require("road_network")
local mats = require("materials")

local M = {}

local ROAD_SURFACE_HEIGHT = 0.15
local ROAD_SURFACE_Y = ROAD_SURFACE_HEIGHT * 0.5

M.scene = nil
M.roadSegments = {}
M.lineNodes = {}
M.buildingNodes = {}
M.intersectionNodes = {}
M.visibleEdgeKeys = {}
M.visibleNodeKeys = {}
M.visibleVersion = -1

local buildingColors = {
    Color(0.55, 0.78, 0.82, 1.0),
    Color(0.75, 0.85, 0.60, 1.0),
    Color(0.90, 0.75, 0.55, 1.0),
    Color(0.70, 0.65, 0.85, 1.0),
    Color(0.85, 0.60, 0.65, 1.0),
    Color(0.60, 0.80, 0.70, 1.0),
}

local function RemoveNodes(list)
    for _, node in ipairs(list or {}) do
        if node then
            node:Remove()
        end
    end
end

local function ResetList(list)
    for i = 1, #list do
        list[i] = nil
    end
end

function M.Clear()
    local scene = M.scene
    RemoveNodes(M.roadSegments)
    RemoveNodes(M.lineNodes)
    RemoveNodes(M.buildingNodes)
    RemoveNodes(M.intersectionNodes)
    M.roadSegments = {}
    M.lineNodes = {}
    M.buildingNodes = {}
    M.intersectionNodes = {}
    M.visibleEdgeKeys = {}
    M.visibleNodeKeys = {}
    M.visibleVersion = -1
    M.scene = scene
end

local function CreateRoadSegment(scene, pos, yaw, segLength)
    local roadNode = scene:CreateChild("RoadSeg")
    local model = roadNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.road
    roadNode.scale = Vector3(CONFIG.ROAD_WIDTH, ROAD_SURFACE_HEIGHT, segLength)
    roadNode.position = Vector3(pos.x, ROAD_SURFACE_Y, pos.z)
    roadNode.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, roadNode)

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

local function CreateLaneLines(scene, edgeStart, edgeEnd, heading, edgeLength)
    local yaw = rn.HeadingToYaw(heading)
    local right = rn.HeadingToRight(heading)

    local numLines = math.floor(edgeLength / CONFIG.LINE_SPACING)
    for i = 1, numLines do
        local t = (i - 0.5) / numLines
        local px = edgeStart.x + (edgeEnd.x - edgeStart.x) * t
        local pz = edgeStart.z + (edgeEnd.z - edgeStart.z) * t

        local nodeL = scene:CreateChild("LineL")
        local mL = nodeL:CreateComponent("StaticModel")
        mL.model = cache:GetResource("Model", "Models/Box.mdl")
        mL.material = mats.laneLine
        nodeL.scale = Vector3(0.12, 0.05, CONFIG.LINE_LENGTH)
        nodeL.position = Vector3(px - right.x * 1.0, 0.16, pz - right.z * 1.0)
        nodeL.rotation = Quaternion(yaw, Vector3.UP)
        table.insert(M.lineNodes, nodeL)

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

local function GetStraightOnlyHeading(node)
    if not node or not node.edges or #node.edges ~= 2 then return nil end

    local edgeA = rn.GetEdge(node.edges[1])
    local edgeB = rn.GetEdge(node.edges[2])
    if not edgeA or not edgeB then return nil end

    if edgeB.heading == rn.ReverseHeading(edgeA.heading) then
        return edgeA.heading
    end
    return nil
end

local function CreateIntersectionLaneLines(scene, node, heading)
    local fwd = rn.HeadingToForward(heading)
    local halfSize = rn.INTERSECTION_HALF_SIZE
    local startPos = Vector3(node.worldX - fwd.x * halfSize, 0, node.worldZ - fwd.z * halfSize)
    local endPos = Vector3(node.worldX + fwd.x * halfSize, 0, node.worldZ + fwd.z * halfSize)
    CreateLaneLines(scene, startPos, endPos, heading, halfSize * 2.0)
end

local function CreateBuildingsAlongEdge(scene, edgeStart, edgeEnd, heading, edgeLength, edgeKey)
    local right = rn.HeadingToRight(heading)
    local numBuildings = CONFIG.BUILDINGS_PER_EDGE
    local rng = rn.NewDeterministicRng(edgeKey, edgeLength * 10, 77)

    for i = 1, numBuildings do
        local t = (i - 0.5) / numBuildings
        if t > 0.1 and t < 0.9 then
            local px = edgeStart.x + (edgeEnd.x - edgeStart.x) * t
            local pz = edgeStart.z + (edgeEnd.z - edgeStart.z) * t

            for _, side in ipairs({ -1, 1 }) do
                if rng() > 0.3 then
                    local h = rng() * 8 + 3
                    local w = rng() * 2.5 + 1.5
                    local d = rng() * 2.5 + 1.5
                    local buildingRadius = math.max(w, d) * 0.5
                    local roadHalfWidth = CONFIG.ROAD_WIDTH * 0.5
                    local minLateral = math.max(
                        CONFIG.BUILDING_ZONE_START,
                        roadHalfWidth + 0.3 + 2.5 + CONFIG.BUILDING_SIDEWALK_SETBACK + buildingRadius
                    )

                    if minLateral <= CONFIG.BUILDING_ZONE_END then
                        local lateral = minLateral + rng() * (CONFIG.BUILDING_ZONE_END - minLateral)
                        local bx = px + right.x * side * lateral
                        local bz = pz + right.z * side * lateral

                        local node = scene:CreateChild("Building")
                        local model = node:CreateComponent("StaticModel")
                        model.model = cache:GetResource("Model", "Models/Box.mdl")
                        local colorIdx = math.floor(rng() * #buildingColors) + 1
                        model.material = mats.CreatePBRMaterial(buildingColors[colorIdx], 0.0, 0.7)
                        node.scale = Vector3(w, h, d)
                        node.position = Vector3(bx, h * 0.5, bz)
                        node.rotation = Quaternion(rn.HeadingToYaw(heading) + math.floor(rng() * 11) - 5, Vector3.UP)
                        table.insert(M.buildingNodes, node)
                    end
                end
            end
        end
    end
end

local function CreateIntersection(scene, node, useRoadSurface)
    local iNode = scene:CreateChild("Intersection")
    local model = iNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = useRoadSurface and mats.road or mats.crossroads
    local areaSize = CONFIG.ROAD_WIDTH
    iNode.scale = Vector3(areaSize, ROAD_SURFACE_HEIGHT, areaSize)
    iNode.position = Vector3(node.worldX, ROAD_SURFACE_Y, node.worldZ)
    table.insert(M.intersectionNodes, iNode)
end

local function CreateClosedExitCurb(scene, node, heading)
    local fwd = rn.HeadingToForward(heading)
    local yaw = rn.HeadingToYaw(heading)
    local curbDepth = 0.3
    local sidewalkDepth = 2.5
    local closureWidth = CONFIG.ROAD_WIDTH + 0.6

    local curbPos = Vector3(
        node.worldX + fwd.x * (rn.INTERSECTION_HALF_SIZE + curbDepth * 0.5),
        0.175,
        node.worldZ + fwd.z * (rn.INTERSECTION_HALF_SIZE + curbDepth * 0.5)
    )

    local curb = scene:CreateChild("ClosedExitCurb")
    local curbModel = curb:CreateComponent("StaticModel")
    curbModel.model = cache:GetResource("Model", "Models/Box.mdl")
    curbModel.material = mats.curb
    curb.scale = Vector3(closureWidth, 0.35, curbDepth)
    curb.position = curbPos
    curb.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.intersectionNodes, curb)

    local sidewalkPos = Vector3(
        node.worldX + fwd.x * (rn.INTERSECTION_HALF_SIZE + curbDepth + sidewalkDepth * 0.5),
        0.06,
        node.worldZ + fwd.z * (rn.INTERSECTION_HALF_SIZE + curbDepth + sidewalkDepth * 0.5)
    )

    local sidewalk = scene:CreateChild("ClosedExitSidewalk")
    local sidewalkModel = sidewalk:CreateComponent("StaticModel")
    sidewalkModel.model = cache:GetResource("Model", "Models/Box.mdl")
    sidewalkModel.material = mats.sidewalk
    sidewalk.scale = Vector3(closureWidth, 0.12, sidewalkDepth)
    sidewalk.position = sidewalkPos
    sidewalk.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.intersectionNodes, sidewalk)
end

local function BuildVisibleNodeSet()
    local nodeSet = {}
    rn.ForEachVisibleNode(function(node)
        nodeSet[node.id] = node
    end)
    return nodeSet
end

local function BuildVisibleEdgeSet()
    local edgeSet = {}
    rn.ForEachVisibleEdge(function(edge)
        edgeSet[edge.id] = edge
    end)
    return edgeSet
end

local function CreateVisibleNodeVisuals(scene, node)
    local straightHeading = GetStraightOnlyHeading(node)
    CreateIntersection(scene, node, straightHeading ~= nil)
    if straightHeading ~= nil then
        CreateIntersectionLaneLines(scene, node, straightHeading)
    end

    for heading = 0, 3 do
        if not rn.GetEdgeByHeading(node.id, heading) then
            CreateClosedExitCurb(scene, node, heading)
        end
    end
end

local function CreateVisibleEdgeVisuals(scene, edge)
    local start = edge.worldStart
    local finish = edge.worldEnd
    local heading = edge.heading
    local length = edge.length
    local yaw = rn.HeadingToYaw(heading)
    local shrink = rn.INTERSECTION_HALF_SIZE
    local fwd = rn.HeadingToForward(heading)
    local effectiveStart = Vector3(start.x + fwd.x * shrink, 0, start.z + fwd.z * shrink)
    local effectiveEnd = Vector3(finish.x - fwd.x * shrink, 0, finish.z - fwd.z * shrink)
    local effectiveLength = length - shrink * 2

    if effectiveLength > 0 then
        local px = (effectiveStart.x + effectiveEnd.x) * 0.5
        local pz = (effectiveStart.z + effectiveEnd.z) * 0.5
        CreateRoadSegment(scene, Vector3(px, 0, pz), yaw, effectiveLength)
        CreateLaneLines(scene, effectiveStart, effectiveEnd, heading, effectiveLength)
    end

    CreateBuildingsAlongEdge(scene, start, finish, heading, length, edge.physicalKey or edge.id)
end

local function RefreshVisibleVisuals(scene)
    if not scene then return end

    local visibleNodes = BuildVisibleNodeSet()
    local visibleEdges = BuildVisibleEdgeSet()
    local versionChanged = rn.visibleVersion ~= M.visibleVersion

    if not versionChanged then
        local same = true
        for id in pairs(visibleNodes) do
            if not M.visibleNodeKeys[id] then same = false break end
        end
        for id in pairs(M.visibleNodeKeys) do
            if not visibleNodes[id] then same = false break end
        end
        if same then
            same = true
            for id in pairs(visibleEdges) do
                if not M.visibleEdgeKeys[id] then same = false break end
            end
            for id in pairs(M.visibleEdgeKeys) do
                if not visibleEdges[id] then same = false break end
            end
        end
        versionChanged = not same
    end

    if not versionChanged then return end

    M.Clear()
    M.scene = scene

    for _, node in pairs(visibleNodes) do
        CreateVisibleNodeVisuals(scene, node)
    end
    for _, edge in pairs(visibleEdges) do
        CreateVisibleEdgeVisuals(scene, edge)
    end

    M.visibleNodeKeys = visibleNodes
    M.visibleEdgeKeys = visibleEdges
    M.visibleVersion = rn.visibleVersion
end

function M.Init(scene)
    M.scene = scene
    RefreshVisibleVisuals(scene)
    print("[Pools] Initialized streaming road visuals")
end

function M.Update(pathState)
    if not CONFIG.ROAD_STREAMING_ENABLED then return end
    rn.EnsureRowsAroundPath(pathState)
    RefreshVisibleVisuals(M.scene)
end

return M
