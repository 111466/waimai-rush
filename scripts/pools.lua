-- ============================================================================
-- 外卖冲冲冲 - 对象池模块（道路/车道线/建筑）
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local PATH = cfg.PATH
local path = require("path")
local mats = require("materials")

local M = {}

-- 对象池
M.roadPool = {}
M.linePool = {}
M.buildingPool = {}

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
-- 道路池
-- ============================================================================

function M.CreateOneRoadSegment(scene)
    local seg = {}
    local roadNode = scene:CreateChild("Road")
    local model = roadNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.road
    roadNode.scale = Vector3(CONFIG.ROAD_WIDTH, 0.15, CONFIG.ROAD_SEGMENT_LENGTH)
    seg.road = roadNode

    local curbL = scene:CreateChild("CurbL")
    local cm = curbL:CreateComponent("StaticModel")
    cm.model = cache:GetResource("Model", "Models/Box.mdl")
    cm.material = mats.curb
    curbL.scale = Vector3(0.3, 0.35, CONFIG.ROAD_SEGMENT_LENGTH)
    seg.curbL = curbL

    local curbR = scene:CreateChild("CurbR")
    local cm2 = curbR:CreateComponent("StaticModel")
    cm2.model = cache:GetResource("Model", "Models/Box.mdl")
    cm2.material = mats.curb
    curbR.scale = Vector3(0.3, 0.35, CONFIG.ROAD_SEGMENT_LENGTH)
    seg.curbR = curbR

    local swL = scene:CreateChild("SidewalkL")
    local sm = swL:CreateComponent("StaticModel")
    sm.model = cache:GetResource("Model", "Models/Box.mdl")
    sm.material = mats.sidewalk
    swL.scale = Vector3(2.5, 0.12, CONFIG.ROAD_SEGMENT_LENGTH)
    seg.swL = swL

    local swR = scene:CreateChild("SidewalkR")
    local sm2 = swR:CreateComponent("StaticModel")
    sm2.model = cache:GetResource("Model", "Models/Box.mdl")
    sm2.material = mats.sidewalk
    swR.scale = Vector3(2.5, 0.12, CONFIG.ROAD_SEGMENT_LENGTH)
    seg.swR = swR

    seg.pathDist = 0.0
    seg.active = false
    return seg
end

function M.PositionRoadSegment(seg, pathDist)
    local s = path.state
    seg.pathDist = pathDist
    seg.active = true
    local center = path.GetWorldPosForObject(pathDist, 0.0)
    local right
    if s.turnExecuting and pathDist >= s.turnStartDist and pathDist <= s.turnEndDist then
        local yawRad = math.rad(path.GetTrackYawAt(pathDist))
        right = Vector3(math.cos(yawRad), 0, -math.sin(yawRad))
    else
        right = path.GetRightVector(s.currentHeading)
    end

    local cx = center.x
    local cz = center.z
    local yaw = path.GetTrackYawAt(pathDist)

    seg.road.position = Vector3(cx, 0.075, cz)
    seg.road.rotation = Quaternion(yaw, Vector3.UP)

    local halfRoad = CONFIG.ROAD_WIDTH * 0.5
    seg.curbL.position = Vector3(cx + right.x * (halfRoad + 0.15), 0.175, cz + right.z * (halfRoad + 0.15))
    seg.curbL.rotation = Quaternion(yaw, Vector3.UP)
    seg.curbR.position = Vector3(cx - right.x * (halfRoad + 0.15), 0.175, cz - right.z * (halfRoad + 0.15))
    seg.curbR.rotation = Quaternion(yaw, Vector3.UP)

    seg.swL.position = Vector3(cx + right.x * (halfRoad + 1.55), 0.06, cz + right.z * (halfRoad + 1.55))
    seg.swL.rotation = Quaternion(yaw, Vector3.UP)
    seg.swR.position = Vector3(cx - right.x * (halfRoad + 1.55), 0.06, cz - right.z * (halfRoad + 1.55))
    seg.swR.rotation = Quaternion(yaw, Vector3.UP)
end

function M.HideRoadSegment(seg)
    seg.road.position = Vector3(0, -100, 0)
    seg.curbL.position = Vector3(0, -100, 0)
    seg.curbR.position = Vector3(0, -100, 0)
    seg.swL.position = Vector3(0, -100, 0)
    seg.swR.position = Vector3(0, -100, 0)
end

-- ============================================================================
-- 车道线池
-- ============================================================================

function M.CreateOneLaneLine(scene)
    local item = {}
    local nodeL = scene:CreateChild("LineL")
    local mL = nodeL:CreateComponent("StaticModel")
    mL.model = cache:GetResource("Model", "Models/Box.mdl")
    mL.material = mats.laneLine
    nodeL.scale = Vector3(0.12, 0.05, CONFIG.LINE_LENGTH)
    item.nodeL = nodeL

    local nodeR = scene:CreateChild("LineR")
    local mR = nodeR:CreateComponent("StaticModel")
    mR.model = cache:GetResource("Model", "Models/Box.mdl")
    mR.material = mats.laneLine
    nodeR.scale = Vector3(0.12, 0.05, CONFIG.LINE_LENGTH)
    item.nodeR = nodeR

    item.pathDist = 0.0
    item.active = false
    return item
end

function M.PositionLaneLine(item, pathDist)
    item.pathDist = pathDist
    item.active = true
    local center = path.GetWorldPosForObject(pathDist, 0.0)
    local yaw = path.GetTrackYawAt(pathDist)
    local yawRad = math.rad(yaw)
    local right = Vector3(math.cos(yawRad), 0, -math.sin(yawRad))
    local cx = center.x
    local cz = center.z

    item.nodeL.position = Vector3(cx - right.x * 1.0, 0.16, cz - right.z * 1.0)
    item.nodeL.rotation = Quaternion(yaw, Vector3.UP)
    item.nodeR.position = Vector3(cx + right.x * 1.0, 0.16, cz + right.z * 1.0)
    item.nodeR.rotation = Quaternion(yaw, Vector3.UP)
end

function M.HideLaneLine(item)
    item.nodeL.position = Vector3(0, -100, 0)
    item.nodeR.position = Vector3(0, -100, 0)
end

-- ============================================================================
-- 建筑池
-- ============================================================================

function M.CreateOneBuilding(scene)
    local item = {}
    local node = scene:CreateChild("Building")
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")

    local colorIdx = math.random(1, #buildingColors)
    local mat = mats.CreatePBRMaterial(buildingColors[colorIdx], 0.0, 0.7)
    model.material = mat

    local h = math.random() * 8 + 3
    local w = math.random() * 2 + 1.5
    local d = math.random() * 2 + 1.5
    node.scale = Vector3(w, h, d)

    item.node = node
    item.height = h
    item.pathDist = 0.0
    item.side = 1
    item.lateralOffset = 0.0
    item.active = false
    return item
end

function M.PositionBuilding(item, pathDist, side, lateralOffset)
    item.pathDist = pathDist
    item.side = side
    item.lateralOffset = lateralOffset
    item.active = true

    local center = path.GetWorldPosForObject(pathDist, 0.0)
    local yaw = path.GetTrackYawAt(pathDist)
    local yawRad = math.rad(yaw)
    local right = Vector3(math.cos(yawRad), 0, -math.sin(yawRad))
    local cx = center.x
    local cz = center.z

    local offset = side * lateralOffset
    local px = cx + right.x * offset
    local pz = cz + right.z * offset

    item.node.position = Vector3(px, item.height * 0.5, pz)
    item.node.rotation = Quaternion(yaw + math.random(-10, 10), Vector3.UP)
end

-- ============================================================================
-- 初始化所有对象池
-- ============================================================================

function M.Init(scene)
    -- 道路
    for i = 1, CONFIG.ROAD_SEGMENTS do
        local seg = M.CreateOneRoadSegment(scene)
        local dist = (i - 1) * CONFIG.ROAD_SEGMENT_LENGTH
        M.PositionRoadSegment(seg, dist)
        M.roadPool[i] = seg
    end

    -- 车道线
    for i = 1, CONFIG.LINE_POOL_SIZE do
        local item = M.CreateOneLaneLine(scene)
        local dist = (i - 1) * CONFIG.LINE_SPACING
        M.PositionLaneLine(item, dist)
        M.linePool[i] = item
    end

    -- 建筑
    for i = 1, CONFIG.BUILDING_POOL_SIZE do
        local item = M.CreateOneBuilding(scene)
        local dist = (i - 1) * 8.0
        local side = (i % 2 == 0) and 1 or -1
        local lateral = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
        M.PositionBuilding(item, dist, side, lateral)
        M.buildingPool[i] = item
    end
end

return M
