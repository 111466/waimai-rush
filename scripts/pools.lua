-- ============================================================================
-- 澶栧崠鍐插啿鍐?- 瀵硅薄姹犳ā鍧楋紙鍩轰簬 RoadGraph 鐪熷疄璺綉娓叉煋锛?
-- ============================================================================
-- 鎵€鏈夐亾璺銆佽溅閬撶嚎銆佸缓绛戞牴鎹矾缃?edge 鐪熷疄鎽嗘斁
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local rn = require("road_network")
local mats = require("materials")

local M = {}

local materialCache = {}

local function Mat(name, color, metallic, roughness)
    if not materialCache[name] then
        materialCache[name] = mats.CreatePBRMaterial(color, metallic or 0.0, roughness or 0.75)
    end
    return materialCache[name]
end

local function DistrictRoadMat(district)
    local d = district or rn.GetDistrict("downtown")
    return Mat("road_" .. d.id, d.roadColor or Color(0.85, 0.85, 0.82, 1.0), 0.0, 0.88)
end

-- 鍦烘櫙瀵硅薄鍒楄〃锛堜笉鍐嶆槸寰幆鍥炴敹姹狅紝鑰屾槸涓€娆℃€у垱寤烘墍鏈夎矾缃戣瑙夛級
M.roadSegments = {}    -- 鎵€鏈夐亾璺鑺傜偣
M.lineNodes = {}       -- 鎵€鏈夎溅閬撶嚎鑺傜偣
M.buildingNodes = {}   -- 鎵€鏈夊缓绛戣妭鐐?
M.intersectionNodes = {} -- 鎵€鏈夎矾鍙ｅ湴闈㈣妭鐐?

-- 寤虹瓚鑹叉澘
M.propNodes = {}

local buildingColors = {
    Color(0.55, 0.78, 0.82, 1.0),
    Color(0.75, 0.85, 0.60, 1.0),
    Color(0.90, 0.75, 0.55, 1.0),
    Color(0.70, 0.65, 0.85, 1.0),
    Color(0.85, 0.60, 0.65, 1.0),
    Color(0.60, 0.80, 0.70, 1.0),
}

-- ============================================================================
-- 鍒涘缓閬撹矾娈碉紙涓€涓?edge 閾哄娈碉級
-- ============================================================================

local function CreateRoadSegment(scene, pos, yaw, segLength, district)
    local roadNode = scene:CreateChild("RoadSeg")
    local model = roadNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = DistrictRoadMat(district)
    roadNode.scale = Vector3(CONFIG.ROAD_WIDTH, 0.15, segLength)
    roadNode.position = Vector3(pos.x, 0.075, pos.z)
    roadNode.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.roadSegments, roadNode)

    -- 璺紭鐭?
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

    -- 浜鸿閬?
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
-- 鍒涘缓杞﹂亾绾?
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

        -- 宸﹁溅閬撶嚎
        local nodeL = scene:CreateChild("LineL")
        local mL = nodeL:CreateComponent("StaticModel")
        mL.model = cache:GetResource("Model", "Models/Box.mdl")
        mL.material = mats.laneLine
        nodeL.scale = Vector3(0.12, 0.05, CONFIG.LINE_LENGTH)
        nodeL.position = Vector3(px - right.x * 1.0, 0.16, pz - right.z * 1.0)
        nodeL.rotation = Quaternion(yaw, Vector3.UP)
        table.insert(M.lineNodes, nodeL)

        -- 鍙宠溅閬撶嚎
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
-- 鍒涘缓寤虹瓚锛堟部 edge 涓や晶锛?
-- ============================================================================

local function CreateBuildingsAlongEdge(scene, edgeStart, edgeEnd, heading, edgeLength, district)
    local fwd = rn.HeadingToForward(heading)
    local right = rn.HeadingToRight(heading)

    local d = district or rn.GetDistrict("downtown")
    local palette = d.palette or buildingColors
    local numBuildings = math.max(3, math.floor(CONFIG.BUILDINGS_PER_EDGE * (d.buildingDensity or 1.0)))
    for i = 1, numBuildings do
        local t = (i - 0.5) / numBuildings
        -- 閬垮紑璺彛鍖哄煙锛堢暀绌?15%锛?
        if t > 0.1 and t < 0.9 then
            local px = edgeStart.x + (edgeEnd.x - edgeStart.x) * t
            local pz = edgeStart.z + (edgeEnd.z - edgeStart.z) * t

            for _, side in ipairs({-1, 1}) do
                if math.random() < (d.buildingChance or 0.7) then  -- 70% 姒傜巼鐢熸垚寤虹瓚
                    local lateral = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
                    local bx = px + right.x * side * lateral
                    local bz = pz + right.z * side * lateral

                    local hMin = d.heightMin or 3.0
                    local hMax = d.heightMax or 8.0
                    local h = hMin + math.random() * (hMax - hMin)
                    local w = math.random() * 2.5 + 1.5
                    local depth = math.random() * 2.5 + 1.5

                    local node = scene:CreateChild("Building")
                    local model = node:CreateComponent("StaticModel")
                    model.model = cache:GetResource("Model", "Models/Box.mdl")
                    local colorIdx = math.random(1, #palette)
                    model.material = mats.CreatePBRMaterial(palette[colorIdx], 0.0, 0.7)
                    node.scale = Vector3(w, h, depth)
                    node.position = Vector3(bx, h * 0.5, bz)
                    node.rotation = Quaternion(rn.HeadingToYaw(heading) + math.random(-5, 5), Vector3.UP)
                    table.insert(M.buildingNodes, node)
                end
            end
        end
    end
end

-- ============================================================================
-- 鍒涘缓璺彛鍦伴潰
-- ============================================================================

local function CreateDistrictProp(scene, pos, district, index, heading)
    local node = scene:CreateChild("DistrictProp")
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")

    local d = district or rn.GetDistrict("downtown")
    local palette = d.palette or buildingColors
    local color = palette[((index - 1) % #palette) + 1]
    local variant = index % 4

    model.material = mats.CreatePBRMaterial(color, 0.0, 0.55)
    if variant == 0 then
        node.scale = Vector3(1.8, 0.35, 0.9)
        node.position = Vector3(pos.x, 0.18, pos.z)
    elseif variant == 1 then
        node.scale = Vector3(0.35, 1.8, 0.35)
        node.position = Vector3(pos.x, 0.9, pos.z)
    elseif variant == 2 then
        node.scale = Vector3(0.55, 1.2, 0.55)
        node.position = Vector3(pos.x, 0.6, pos.z)
    else
        node.scale = Vector3(1.0, 0.6, 1.0)
        node.position = Vector3(pos.x, 0.3, pos.z)
    end

    if heading then
        node.rotation = Quaternion(rn.HeadingToYaw(heading), Vector3.UP)
    else
        node.rotation = Quaternion(math.random(0, 360), Vector3.UP)
    end
    table.insert(M.propNodes, node)
end

local function CreateIntersection(scene, node)
    local iNode = scene:CreateChild("Intersection")
    local model = iNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.crossroads
    -- 璺彛鍦伴潰灏哄涓庢櫘閫氶亾璺搴︿竴鑷?    local areaSize = CONFIG.ROAD_WIDTH
    local areaSize = CONFIG.ROAD_WIDTH
    iNode.scale = Vector3(areaSize, 0.16, areaSize)
    iNode.position = Vector3(node.worldX, 0.08, node.worldZ)
    table.insert(M.intersectionNodes, iNode)

    local district = rn.GetNodeDistrict(node.id)
    local propBase = Vector3(node.worldX, 0, node.worldZ)
    local fwd = rn.HeadingToForward(0)
    local right = rn.HeadingToRight(0)
    CreateDistrictProp(scene, Vector3(propBase.x + right.x * 5.8, 0, propBase.z + right.z * 5.8), district, node.id, 0)
    CreateDistrictProp(scene, Vector3(propBase.x - right.x * 5.8, 0, propBase.z - right.z * 5.8), district, node.id + 1, 1)
    if district.id == "market" then
        CreateDistrictProp(scene, Vector3(propBase.x + fwd.x * 6.5, 0, propBase.z + fwd.z * 6.5), district, node.id + 2, 2)
    elseif district.id == "construction" then
        CreateDistrictProp(scene, Vector3(propBase.x - fwd.x * 6.5, 0, propBase.z - fwd.z * 6.5), district, node.id + 3, 3)
    end

    if not CONFIG.DEBUG_INTERSECTION_BORDER then
        return
    end

    -- =========================================
    -- 璋冭瘯锛氬彲瑙嗗寲杞悜閫夋嫨绐楀彛鍖哄煙杈圭晫
    -- =========================================
    local halfSize = rn.INTERSECTION_HALF_SIZE
    local cx, cz = node.worldX, node.worldZ
    local borderH = 0.5    -- 杈规楂樺害
    local borderW = 0.15   -- 杈规绮楃粏
    local borderY = borderH * 0.5 + 0.16  -- 鐣ラ珮浜庤矾闈?
    local fullSize = halfSize * 2.0  -- 9.0m

    local debugMat = mats.CreatePBRMaterial(Color(0.0, 0.6, 1.0, 1.0), 0.3, 0.4)

    -- 鍖楄竟锛?Z 渚э級
    local borderN = scene:CreateChild("DbgBorderN")
    local bmN = borderN:CreateComponent("StaticModel")
    bmN.model = cache:GetResource("Model", "Models/Box.mdl")
    bmN.material = debugMat
    borderN.scale = Vector3(fullSize, borderH, borderW)
    borderN.position = Vector3(cx, borderY, cz + halfSize)
    table.insert(M.intersectionNodes, borderN)

    -- 鍗楄竟锛?Z 渚э級
    local borderS = scene:CreateChild("DbgBorderS")
    local bmS = borderS:CreateComponent("StaticModel")
    bmS.model = cache:GetResource("Model", "Models/Box.mdl")
    bmS.material = debugMat
    borderS.scale = Vector3(fullSize, borderH, borderW)
    borderS.position = Vector3(cx, borderY, cz - halfSize)
    table.insert(M.intersectionNodes, borderS)

    -- 涓滆竟锛?X 渚э級
    local borderE = scene:CreateChild("DbgBorderE")
    local bmE = borderE:CreateComponent("StaticModel")
    bmE.model = cache:GetResource("Model", "Models/Box.mdl")
    bmE.material = debugMat
    borderE.scale = Vector3(borderW, borderH, fullSize)
    borderE.position = Vector3(cx + halfSize, borderY, cz)
    table.insert(M.intersectionNodes, borderE)

    -- 瑗胯竟锛?X 渚э級
    local borderW_node = scene:CreateChild("DbgBorderW")
    local bmW = borderW_node:CreateComponent("StaticModel")
    bmW.model = cache:GetResource("Model", "Models/Box.mdl")
    bmW.material = debugMat
    borderW_node.scale = Vector3(borderW, borderH, fullSize)
    borderW_node.position = Vector3(cx - halfSize, borderY, cz)
    table.insert(M.intersectionNodes, borderW_node)
end

local function CreateEntryLine(scene, pos, yaw)
    local node = scene:CreateChild("IntersectionEntryLine")
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.laneLine
    node.scale = Vector3(CONFIG.ROAD_WIDTH * 0.85, 0.04, 0.28)
    node.position = Vector3(pos.x, 0.18, pos.z)
    node.rotation = Quaternion(yaw, Vector3.UP)
    table.insert(M.lineNodes, node)
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

-- ============================================================================
-- 鍒濆鍖栵細鏍规嵁璺綉鐢熸垚鍏ㄩ儴閬撹矾瑙嗚
-- ============================================================================

function M.Init(scene)
    print("[Pools] Building road visuals from RoadGraph...")

    for _, node in pairs(rn.nodes) do
        CreateIntersection(scene, node)
        if CONFIG.SHOW_INTERSECTION_CLOSED_MARKERS then
            for heading = 0, 3 do
                if not rn.GetEdgeByHeading(node.id, heading) then
                    CreateClosedExitCurb(scene, node, heading)
                end
            end
        end
    end

    local renderedPairs = {}
    for _, edge in pairs(rn.edges) do
        local pairKey = math.min(edge.fromNode, edge.toNode) * 1000 + math.max(edge.fromNode, edge.toNode)
        if not renderedPairs[pairKey] then
            renderedPairs[pairKey] = true

            local start = edge.worldStart
            local finish = edge.worldEnd
            local heading = edge.heading
            local length = edge.length
            local numSegs = CONFIG.ROAD_SEGMENTS_PER_EDGE
            local yaw = rn.HeadingToYaw(heading)
            local shrink = rn.INTERSECTION_HALF_SIZE
            local forward = rn.HeadingToForward(heading)
            local district = rn.GetEdgeDistrict(edge)

            local effectiveStart = Vector3(
                start.x + forward.x * shrink,
                0,
                start.z + forward.z * shrink
            )
            local effectiveEnd = Vector3(
                finish.x - forward.x * shrink,
                0,
                finish.z - forward.z * shrink
            )
            local effectiveLength = length - shrink * 2

            if effectiveLength > 0 then
                local effSegLen = effectiveLength / numSegs
                for i = 1, numSegs do
                    local t = (i - 0.5) / numSegs
                    local px = effectiveStart.x + (effectiveEnd.x - effectiveStart.x) * t
                    local pz = effectiveStart.z + (effectiveEnd.z - effectiveStart.z) * t
                    CreateRoadSegment(scene, Vector3(px, 0, pz), yaw, effSegLen, district)
                end

                CreateLaneLines(scene, effectiveStart, effectiveEnd, heading, effectiveLength)

                if CONFIG.SHOW_INTERSECTION_ENTRY_LINES then
                    CreateEntryLine(scene, effectiveStart, yaw)
                    CreateEntryLine(scene, effectiveEnd, yaw)
                end
            end

            CreateBuildingsAlongEdge(scene, start, finish, heading, length, district)
        end
    end

    print("[Pools] Created " .. #M.roadSegments .. " road parts, " .. #M.lineNodes .. " lane lines, " .. #M.buildingNodes .. " buildings, " .. #M.intersectionNodes .. " intersections")
end

return M
