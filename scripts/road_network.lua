-- ============================================================================
-- Waimai Rush - RoadGraph
-- ============================================================================
-- 前向流式路网。横向列数固定，纵向按玩家前进方向持续追加。
-- 节点和有向边使用稳定 ID，因此视觉窗口卸载/重载不会影响玩法引用。
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG

local M = {}

-- Network config, mirrored after generation for legacy callers/UI.
M.GRID_SIZE = CONFIG.ROAD_GRID_SIZE or 8
M.BLOCK_SIZE = CONFIG.ROAD_BLOCK_BASE or 86.0
M.ROAD_WIDTH = 7.0
M.DEFAULT_SEED = 1001

-- Direction enum (heading): 0=+Z, 1=+X, 2=-Z, 3=-X
M.HEADING_POS_Z = 0
M.HEADING_POS_X = 1
M.HEADING_NEG_Z = 2
M.HEADING_NEG_X = 3

-- RoadGraph data. nodes/edges are sparse tables keyed by stable IDs.
M.nodes = {}
M.edges = {}
M.physicalEdges = {}
M.generatedRows = {}
M.reachableNodes = {}
M.currentSeed = M.DEFAULT_SEED
M.reachableRatio = 1.0
M.generationAttempts = 1
M.usedFallback = false
M.bounds = { minX = 0, maxX = 0, minZ = 0, maxZ = 0 }

M.nodeCount = 0
M.edgeCount = 0
M.physicalEdgeCount = 0
M.generatedMaxRow = 0
M.generatedMinRow = 1
M.visibleVersion = 0
M.visibleCenterGX = 1
M.visibleCenterGZ = 1
M.visibleMinGX = 1
M.visibleMaxGX = 1
M.visibleMinGZ = 1
M.visibleMaxGZ = 1

local xPositions = {}
local zPositions = {}
local zSteps = {}
local spineXByRow = {}
local maxPositionRow = 0

-- ============================================================================
-- Deterministic RNG
-- ============================================================================

local function NormalizeSeed(seed)
    if type(seed) == "number" then
        return math.max(1, math.floor(seed))
    end

    if type(seed) == "string" then
        local hash = 2166136261
        for i = 1, #seed do
            hash = (hash * 33 + string.byte(seed, i)) % 2147483647
        end
        return math.max(1, hash)
    end

    return M.DEFAULT_SEED
end

local function NewRng(seed)
    local state = NormalizeSeed(seed) % 2147483647
    if state <= 0 then state = state + 2147483646 end

    return function()
        state = (state * 48271) % 2147483647
        return state / 2147483647
    end
end

local function RandRange(rng, minValue, maxValue)
    return minValue + rng() * (maxValue - minValue)
end

local function SeedPart(value)
    if type(value) == "number" then
        return math.floor(math.abs(value)) % 2147483647
    end

    if type(value) == "string" then
        local hash = 2166136261
        for i = 1, #value do
            hash = (hash * 33 + string.byte(value, i)) % 2147483647
        end
        return hash
    end

    if value == nil then
        return 0
    end

    return SeedPart(tostring(value))
end

local function SeedFromParts(...)
    local seed = NormalizeSeed(M.currentSeed)
    local count = select("#", ...)
    for i = 1, count do
        seed = (seed * 1664525 + SeedPart(select(i, ...))) % 2147483647
    end
    return seed
end

local function UnitFor(a, b, salt)
    return NewRng(SeedFromParts(a, b, salt))()
end

function M.NewDeterministicRng(a, b, salt)
    return NewRng(SeedFromParts(a, b, salt))
end

local function EdgeKey(a, b)
    if a < b then
        return tostring(a) .. ":" .. tostring(b)
    end
    return tostring(b) .. ":" .. tostring(a)
end

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function WindowBounds(center, minLimit, maxLimit, size)
    size = math.max(1, math.floor(size or 1))
    local before = math.floor((size - 1) * 0.5)
    local after = size - 1 - before
    local minValue = center - before
    local maxValue = center + after

    if minValue < minLimit then
        maxValue = maxValue + (minLimit - minValue)
        minValue = minLimit
    end

    if maxLimit and maxValue > maxLimit then
        minValue = minValue - (maxValue - maxLimit)
        maxValue = maxLimit
        minValue = math.max(minLimit, minValue)
    end

    return minValue, maxValue
end

-- ============================================================================
-- Grid utilities
-- ============================================================================

function M.GridToNodeId(gx, gz)
    return (gz - 1) * M.GRID_SIZE + gx
end

local function DecodeNodeId(nodeId)
    local gz = math.floor((nodeId - 1) / M.GRID_SIZE) + 1
    local gx = nodeId - (gz - 1) * M.GRID_SIZE
    return gx, gz
end

local function DirectedEdgeId(fromNodeId, heading)
    return fromNodeId * 4 + heading + 1
end

local function RowForNodeId(nodeId)
    return math.floor((nodeId - 1) / M.GRID_SIZE) + 1
end

local function BuildSteps(rng, count, baseLength, jitter)
    local steps = {}
    for i = 1, count - 1 do
        steps[i] = math.max(55.0, baseLength + RandRange(rng, -jitter, jitter))
    end
    return steps
end

local function AccumulatePositions(steps)
    local values = { 0.0 }
    for i = 1, #steps do
        values[i + 1] = values[i] + steps[i]
    end

    local center = (values[1] + values[#values]) * 0.5
    for i = 1, #values do
        values[i] = values[i] - center
    end
    return values
end

local function BuildColumnPositions()
    local gridSize = CONFIG.ROAD_GRID_SIZE or 8
    local blockBase = CONFIG.ROAD_BLOCK_BASE or 86.0
    local blockJitter = CONFIG.ROAD_BLOCK_JITTER or 22.0
    local rng = NewRng(M.currentSeed + 17)
    return AccumulatePositions(BuildSteps(rng, gridSize, blockBase, blockJitter))
end

local function EnsureZPosition(gz)
    if gz < 1 then gz = 1 end

    if maxPositionRow == 0 then
        zPositions[1] = 0.0
        maxPositionRow = 1
    end

    local blockBase = CONFIG.ROAD_BLOCK_BASE or 86.0
    local blockJitter = CONFIG.ROAD_BLOCK_JITTER or 22.0
    while maxPositionRow < gz do
        local row = maxPositionRow
        local rng = M.NewDeterministicRng(row, 0, 31)
        zSteps[row] = math.max(55.0, blockBase + RandRange(rng, -blockJitter, blockJitter))
        zPositions[row + 1] = zPositions[row] + zSteps[row]
        maxPositionRow = row + 1
    end
end

function M.GridToWorld(gx, gz)
    if gx >= 1 and gx <= M.GRID_SIZE and gz >= 1 then
        EnsureZPosition(gz)
        return xPositions[gx] or 0.0, zPositions[gz] or 0.0
    end

    local offsetX = (gx - math.ceil(M.GRID_SIZE / 2)) * M.BLOCK_SIZE
    local offsetZ = (gz - 1) * M.BLOCK_SIZE
    return offsetX, offsetZ
end

function M.CalcHeading(fromNode, toNode)
    local dx = toNode.worldX - fromNode.worldX
    local dz = toNode.worldZ - fromNode.worldZ
    if math.abs(dz) > math.abs(dx) then
        return dz > 0 and M.HEADING_POS_Z or M.HEADING_NEG_Z
    else
        return dx > 0 and M.HEADING_POS_X or M.HEADING_NEG_X
    end
end

function M.HeadingToForward(heading)
    if heading == M.HEADING_POS_Z then return Vector3(0, 0, 1)
    elseif heading == M.HEADING_POS_X then return Vector3(1, 0, 0)
    elseif heading == M.HEADING_NEG_Z then return Vector3(0, 0, -1)
    elseif heading == M.HEADING_NEG_X then return Vector3(-1, 0, 0)
    end
    return Vector3(0, 0, 1)
end

function M.HeadingToRight(heading)
    if heading == M.HEADING_POS_Z then return Vector3(1, 0, 0)
    elseif heading == M.HEADING_POS_X then return Vector3(0, 0, -1)
    elseif heading == M.HEADING_NEG_Z then return Vector3(-1, 0, 0)
    elseif heading == M.HEADING_NEG_X then return Vector3(0, 0, 1)
    end
    return Vector3(1, 0, 0)
end

function M.HeadingToYaw(heading)
    return heading * 90.0
end

function M.ReverseHeading(heading)
    return (heading + 2) % 4
end

function M.TurnLeft(heading)
    return (heading + 3) % 4
end

function M.TurnRight(heading)
    return (heading + 1) % 4
end

-- ============================================================================
-- Streaming generation
-- ============================================================================

local function EnsureSpineRow(gz)
    if spineXByRow[gz] then
        return spineXByRow[gz]
    end

    local startGX = math.ceil(M.GRID_SIZE / 2)
    spineXByRow[1] = startGX
    local row = 2
    while row <= gz do
        local prev = spineXByRow[row - 1] or startGX
        local r = UnitFor(row, prev, 43)
        local dir = 0
        if r < 0.34 then dir = -1
        elseif r > 0.66 then dir = 1
        end
        spineXByRow[row] = Clamp(prev + dir, 1, M.GRID_SIZE)
        row = row + 1
    end

    return spineXByRow[gz]
end

local function EnsureNode(gx, gz)
    if gx < 1 or gx > M.GRID_SIZE or gz < 1 then return nil end

    local id = M.GridToNodeId(gx, gz)
    local node = M.nodes[id]
    if node then return node end

    local wx, wz = M.GridToWorld(gx, gz)
    node = {
        id = id,
        gridX = gx,
        gridZ = gz,
        worldX = wx,
        worldZ = wz,
        edges = {},
        edgeByHeading = {},
    }
    M.nodes[id] = node
    M.reachableNodes[id] = true
    M.nodeCount = M.nodeCount + 1
    return node
end

local function AddDirectedEdge(fromNodeId, toNodeId)
    local fromNode = M.nodes[fromNodeId]
    local toNode = M.nodes[toNodeId]
    if not fromNode or not toNode then return nil end

    local heading = M.CalcHeading(fromNode, toNode)
    local edgeId = DirectedEdgeId(fromNodeId, heading)
    if M.edges[edgeId] then
        return M.edges[edgeId]
    end

    local dx = toNode.worldX - fromNode.worldX
    local dz = toNode.worldZ - fromNode.worldZ
    local edge = {
        id = edgeId,
        fromNode = fromNodeId,
        toNode = toNodeId,
        heading = heading,
        length = math.sqrt(dx * dx + dz * dz),
        worldStart = Vector3(fromNode.worldX, 0, fromNode.worldZ),
        worldEnd = Vector3(toNode.worldX, 0, toNode.worldZ),
        physicalKey = EdgeKey(fromNodeId, toNodeId),
    }

    M.edges[edgeId] = edge
    fromNode.edgeByHeading[heading] = edgeId
    table.insert(fromNode.edges, edgeId)
    M.edgeCount = M.edgeCount + 1
    return edge
end

local function AddPhysicalEdge(aNodeId, bNodeId)
    if aNodeId == bNodeId then return false end

    local key = EdgeKey(aNodeId, bNodeId)
    if M.physicalEdges[key] then return false end

    M.physicalEdges[key] = true
    M.physicalEdgeCount = M.physicalEdgeCount + 1
    AddDirectedEdge(aNodeId, bNodeId)
    AddDirectedEdge(bNodeId, aNodeId)
    return true
end

local function NeighborGrid(gx, gz, heading)
    if heading == M.HEADING_POS_Z then
        return gx, gz + 1
    elseif heading == M.HEADING_POS_X then
        return gx + 1, gz
    elseif heading == M.HEADING_NEG_Z then
        return gx, gz - 1
    elseif heading == M.HEADING_NEG_X then
        return gx - 1, gz
    end
    return gx, gz
end

local function TryAddExitEdge(node, heading)
    if not node then return false end

    local gx, gz = NeighborGrid(node.gridX, node.gridZ, heading)
    if gx < 1 or gx > M.GRID_SIZE or gz < 1 then
        return false
    end

    EnsureNode(gx, gz)
    return AddPhysicalEdge(node.id, M.GridToNodeId(gx, gz))
end

local function HasAnyExit(node, headings)
    if not node or not node.edgeByHeading then return false end
    for _, heading in ipairs(headings) do
        if node.edgeByHeading[heading] then
            return true
        end
    end
    return false
end

local function OrderedExitHeadings(arrivalHeading)
    if arrivalHeading == M.HEADING_POS_Z then
        return { M.HEADING_POS_Z }
    elseif arrivalHeading == M.HEADING_POS_X or arrivalHeading == M.HEADING_NEG_X then
        return { M.HEADING_POS_Z, arrivalHeading }
    end
    return {}
end

local function EnsurePlayableExitForArrival(nodeId, arrivalHeading)
    -- 前向无限地图不主动补回头路，只补 +Z 或横向延续出口。
    if arrivalHeading == M.HEADING_NEG_Z then return false end

    local node = M.GetNode(nodeId)
    if not node then return false end

    local preferred = OrderedExitHeadings(arrivalHeading)
    if HasAnyExit(node, preferred) then
        return false
    end

    for _, heading in ipairs(preferred) do
        if TryAddExitEdge(node, heading) then
            return true
        end
    end
    return false
end

local function EnsurePlayableExitsForRow(gz)
    local changed = false

    for gx = 1, M.GRID_SIZE do
        local node = M.GetNode(M.GridToNodeId(gx, gz))
        if node and node.edges then
            local edgeIds = {}
            for i = 1, #node.edges do
                edgeIds[i] = node.edges[i]
            end

            for _, edgeId in ipairs(edgeIds) do
                local edge = M.GetEdge(edgeId)
                if edge then
                    local arrivalHeading = M.ReverseHeading(edge.heading)
                    if EnsurePlayableExitForArrival(node.id, arrivalHeading) then
                        changed = true
                    end
                end
            end
        end
    end

    return changed
end

local function ShouldOpenRoad(gz, gx, salt, keep)
    if keep then return true end
    local closureRate = CONFIG.ROAD_CLOSURE_RATE or 0.18
    return UnitFor(gz, gx, salt) > closureRate
end

local function GenerateRow(gz)
    if gz < M.generatedMinRow or M.generatedRows[gz] then return end

    EnsureSpineRow(gz + 1)
    for gx = 1, M.GRID_SIZE do
        EnsureNode(gx, gz)
        EnsureNode(gx, gz + 1)
    end

    local prevSpine = gz > 1 and EnsureSpineRow(gz - 1) or nil
    local rowSpine = EnsureSpineRow(gz)
    local nextSpine = EnsureSpineRow(gz + 1)

    -- 行内横向路：随机保留，并强制连接上一行主干到当前行主干。
    for gx = 1, M.GRID_SIZE - 1 do
        local keepConnector = false
        if prevSpine and prevSpine ~= rowSpine then
            keepConnector = gx >= math.min(prevSpine, rowSpine) and gx < math.max(prevSpine, rowSpine)
        end

        if ShouldOpenRoad(gz, gx, 101, keepConnector) then
            AddPhysicalEdge(M.GridToNodeId(gx, gz), M.GridToNodeId(gx + 1, gz))
        end
    end

    -- 前向路：随机保留，并强制当前主干继续通往下一行。
    for gx = 1, M.GRID_SIZE do
        local keepSpine = gx == rowSpine
        if ShouldOpenRoad(gz, gx, 211, keepSpine) then
            AddPhysicalEdge(M.GridToNodeId(gx, gz), M.GridToNodeId(gx, gz + 1))
        end
    end

    -- 下一行如果主干横向移动，提前补一段横向连接，避免玩家抵达时视觉/逻辑空窗。
    if nextSpine ~= rowSpine then
        for gx = math.min(rowSpine, nextSpine), math.max(rowSpine, nextSpine) - 1 do
            AddPhysicalEdge(M.GridToNodeId(gx, gz + 1), M.GridToNodeId(gx + 1, gz + 1))
        end
    end

    EnsurePlayableExitsForRow(gz)
    EnsurePlayableExitsForRow(gz + 1)

    M.generatedRows[gz] = true
    M.generatedMaxRow = math.max(M.generatedMaxRow, gz)
end

function M.EnsureRowsGeneratedTo(maxRow)
    maxRow = math.max(1, math.floor(maxRow or 1))
    local startRow = math.max(M.generatedMinRow, math.min(maxRow, M.generatedMaxRow + 1))
    for gz = startRow, maxRow do
        GenerateRow(gz)
    end
end

local function RemoveValue(list, value)
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == value then
            table.remove(list, i)
            return
        end
    end
end

local function RemoveDirectedEdge(edge)
    if not edge then return end

    local fromNode = M.nodes[edge.fromNode]
    if fromNode then
        if fromNode.edgeByHeading and fromNode.edgeByHeading[edge.heading] == edge.id then
            fromNode.edgeByHeading[edge.heading] = nil
        end
        RemoveValue(fromNode.edges, edge.id)
    end

    if M.edges[edge.id] then
        M.edges[edge.id] = nil
        M.edgeCount = math.max(0, M.edgeCount - 1)
    end
end

function M.PruneRowsBefore(minRow)
    minRow = math.max(M.generatedMinRow, math.floor(minRow or 1))
    if minRow <= M.generatedMinRow then
        return false
    end

    local edgeIdsToRemove = {}
    for edgeId, edge in pairs(M.edges) do
        local fromRow = RowForNodeId(edge.fromNode)
        local toRow = RowForNodeId(edge.toNode)
        if fromRow < minRow or toRow < minRow then
            edgeIdsToRemove[#edgeIdsToRemove + 1] = edgeId
        end
    end

    local removedPhysical = {}
    local removedNodes = 0
    for _, edgeId in ipairs(edgeIdsToRemove) do
        local edge = M.edges[edgeId]
        if edge then
            removedPhysical[edge.physicalKey] = true
            RemoveDirectedEdge(edge)
        end
    end

    for nodeId, node in pairs(M.nodes) do
        if node.gridZ < minRow then
            M.nodes[nodeId] = nil
            M.reachableNodes[nodeId] = nil
            removedNodes = removedNodes + 1
        end
    end

    local removedPhysicalCount = 0
    for key in pairs(removedPhysical) do
        if M.physicalEdges[key] then
            M.physicalEdges[key] = nil
            removedPhysicalCount = removedPhysicalCount + 1
        end
    end

    for gz = M.generatedMinRow, minRow - 1 do
        M.generatedRows[gz] = nil
    end

    M.nodeCount = math.max(0, M.nodeCount - removedNodes)
    M.physicalEdgeCount = math.max(0, M.physicalEdgeCount - removedPhysicalCount)
    M.generatedMinRow = minRow
    return removedNodes > 0 or removedPhysicalCount > 0
end

local function GetPathGrid(pathState)
    local startGX = math.ceil(M.GRID_SIZE / 2)
    if not pathState then
        return startGX, 1
    end

    if pathState.insideIntersection and pathState.intersectionNodeId and pathState.intersectionNodeId ~= 0 then
        local node = M.GetNode(pathState.intersectionNodeId)
        if node then return node.gridX, node.gridZ end
    end

    local edge = pathState.currentEdge and M.GetEdge(pathState.currentEdge.id)
    if edge then
        local fromNode = M.GetNode(edge.fromNode)
        local toNode = M.GetNode(edge.toNode)
        if fromNode and toNode then
            local effectiveLen = M.GetEdgeEffectiveLength(edge)
            local actualDist = M.INTERSECTION_HALF_SIZE + Clamp(pathState.edgeDistance or 0.0, 0.0, effectiveLen)
            local progress = Clamp(actualDist / math.max(1.0, edge.length), 0.0, 1.0)
            local center = progress < 0.5 and fromNode or toNode
            return center.gridX, center.gridZ
        end
    end

    return startGX, 1
end

local function RefreshVisibleBounds()
    EnsureZPosition(M.visibleMaxGZ)

    local minX = xPositions[M.visibleMinGX] or 0.0
    local maxX = xPositions[M.visibleMaxGX] or minX
    local minZ = zPositions[M.visibleMinGZ] or 0.0
    local maxZ = zPositions[M.visibleMaxGZ] or minZ

    M.bounds = {
        minX = math.min(minX, maxX),
        maxX = math.max(minX, maxX),
        minZ = math.min(minZ, maxZ),
        maxZ = math.max(minZ, maxZ),
    }
end

local function GetPathMinGridZ(pathState, fallbackGZ)
    local minGZ = fallbackGZ or 1
    if not pathState or not pathState.currentEdge then
        return minGZ
    end

    local edge = M.GetEdge(pathState.currentEdge.id)
    if not edge then return minGZ end

    local fromNode = M.GetNode(edge.fromNode)
    local toNode = M.GetNode(edge.toNode)
    if fromNode and toNode then
        minGZ = math.min(fromNode.gridZ, toNode.gridZ)
    end
    return minGZ
end

function M.EnsureRowsAroundPath(pathState)
    local centerGX, centerGZ = GetPathGrid(pathState)
    local windowSize = CONFIG.ROAD_RENDER_WINDOW_SIZE or 5
    local aheadRows = CONFIG.ROAD_GENERATE_AHEAD_ROWS or 8
    local keepBehindRows = CONFIG.ROAD_KEEP_BEHIND_ROWS or 4

    local minGX, maxGX = WindowBounds(centerGX, 1, M.GRID_SIZE, windowSize)
    local minGZ, maxGZ = WindowBounds(centerGZ, 1, nil, windowSize)
    local needMaxRow = math.max(maxGZ + 1, centerGZ + aheadRows)
    local pruneAnchorGZ = GetPathMinGridZ(pathState, centerGZ)
    local pruneBefore = math.max(1, pruneAnchorGZ - keepBehindRows)

    M.EnsureRowsGeneratedTo(needMaxRow)
    local pruned = M.PruneRowsBefore(pruneBefore)

    local changed =
        centerGX ~= M.visibleCenterGX or centerGZ ~= M.visibleCenterGZ or
        minGX ~= M.visibleMinGX or maxGX ~= M.visibleMaxGX or
        minGZ ~= M.visibleMinGZ or maxGZ ~= M.visibleMaxGZ

    if changed then
        M.visibleCenterGX = centerGX
        M.visibleCenterGZ = centerGZ
        M.visibleMinGX = minGX
        M.visibleMaxGX = maxGX
        M.visibleMinGZ = minGZ
        M.visibleMaxGZ = maxGZ
        M.visibleVersion = M.visibleVersion + 1
        RefreshVisibleBounds()
    end

    return changed or pruned
end

function M.Generate(seed)
    local normalizedSeed = NormalizeSeed(seed or M.currentSeed or M.DEFAULT_SEED)
    M.currentSeed = normalizedSeed
    M.GRID_SIZE = CONFIG.ROAD_GRID_SIZE or 8
    M.BLOCK_SIZE = CONFIG.ROAD_BLOCK_BASE or 86.0

    M.nodes = {}
    M.edges = {}
    M.physicalEdges = {}
    M.generatedRows = {}
    M.reachableNodes = {}
    M.nodeCount = 0
    M.edgeCount = 0
    M.physicalEdgeCount = 0
    M.generatedMaxRow = 0
    M.generatedMinRow = 1
    M.reachableRatio = 1.0
    M.generationAttempts = 1
    M.usedFallback = false

    xPositions = BuildColumnPositions()
    zPositions = {}
    zSteps = {}
    spineXByRow = {}
    maxPositionRow = 0

    local initialRows = math.max(CONFIG.ROAD_GENERATE_AHEAD_ROWS or 8, CONFIG.ROAD_RENDER_WINDOW_SIZE or 5) + 2
    M.EnsureRowsGeneratedTo(initialRows)

    local startGX = math.ceil(M.GRID_SIZE / 2)
    local windowSize = CONFIG.ROAD_RENDER_WINDOW_SIZE or 5
    M.visibleCenterGX = startGX
    M.visibleCenterGZ = 1
    M.visibleMinGX, M.visibleMaxGX = WindowBounds(startGX, 1, M.GRID_SIZE, windowSize)
    M.visibleMinGZ, M.visibleMaxGZ = WindowBounds(1, 1, nil, windowSize)
    M.visibleVersion = M.visibleVersion + 1
    RefreshVisibleBounds()

    print("[RoadNetwork] Generated streaming seed " .. normalizedSeed ..
        " width " .. M.GRID_SIZE ..
        " rows " .. M.generatedMaxRow ..
        " nodes " .. M.nodeCount ..
        " directedEdges " .. M.edgeCount ..
        " roads " .. M.physicalEdgeCount)
    return true
end

function M.GenerateRandom()
    local seed = os.time() + math.random(1, 1000000)
    M.Generate(seed)
    return seed
end

-- ============================================================================
-- Queries
-- ============================================================================

function M.GetNode(nodeId)
    if not nodeId then return nil end
    local node = M.nodes[nodeId]
    if node then return node end

    local gx, gz = DecodeNodeId(nodeId)
    if gx < 1 or gx > M.GRID_SIZE or gz < 1 then return nil end
    if gz < M.generatedMinRow then return nil end
    M.EnsureRowsGeneratedTo(gz)
    return M.nodes[nodeId]
end

function M.GetEdge(edgeId)
    if not edgeId then return nil end
    return M.edges[edgeId]
end

function M.ForEachNode(fn)
    for _, node in pairs(M.nodes) do
        fn(node)
    end
end

function M.ForEachEdge(fn)
    for _, edge in pairs(M.edges) do
        fn(edge)
    end
end

function M.IsNodeVisible(node)
    if not node then return false end
    return node.gridX >= M.visibleMinGX and node.gridX <= M.visibleMaxGX
        and node.gridZ >= M.visibleMinGZ and node.gridZ <= M.visibleMaxGZ
end

function M.IsEdgeVisible(edge)
    if not edge then return false end
    local fromNode = M.GetNode(edge.fromNode)
    local toNode = M.GetNode(edge.toNode)
    return M.IsNodeVisible(fromNode) and M.IsNodeVisible(toNode)
end

function M.IsEdgeRenderable(edge)
    if not edge then return false end
    local fromNode = M.GetNode(edge.fromNode)
    local toNode = M.GetNode(edge.toNode)
    return M.IsNodeVisible(fromNode) or M.IsNodeVisible(toNode)
end

function M.ForEachVisibleNode(fn)
    for _, node in pairs(M.nodes) do
        if M.IsNodeVisible(node) then
            fn(node)
        end
    end
end

function M.ForEachVisibleEdge(fn)
    local seen = {}
    for _, edge in pairs(M.edges) do
        if edge and not seen[edge.physicalKey] and M.IsEdgeVisible(edge) then
            local normalized = edge
            if edge.fromNode > edge.toNode then
                normalized = M.GetEdge(DirectedEdgeId(edge.toNode, M.ReverseHeading(edge.heading))) or edge
            end
            seen[edge.physicalKey] = true
            fn(normalized)
        end
    end
end

function M.ForEachRenderableEdge(fn)
    local seen = {}
    for _, edge in pairs(M.edges) do
        if edge and not seen[edge.physicalKey] and M.IsEdgeRenderable(edge) then
            local normalized = edge
            if edge.fromNode > edge.toNode then
                normalized = M.GetEdge(DirectedEdgeId(edge.toNode, M.ReverseHeading(edge.heading))) or edge
            end
            seen[edge.physicalKey] = true
            fn(normalized)
        end
    end
end

function M.GetVisibleBounds()
    return M.bounds
end

function M.GetEdgeByHeading(nodeId, heading)
    local node = M.GetNode(nodeId)
    if not node then return nil end
    local edgeId = node.edgeByHeading and node.edgeByHeading[heading]
    return edgeId and M.GetEdge(edgeId) or nil
end

function M.GetAvailableTurns(nodeId, arrivalHeading)
    local node = M.GetNode(nodeId)
    if not node then return {} end

    local turns = {}
    local leftH = M.TurnLeft(arrivalHeading)
    local straightH = arrivalHeading
    local rightH = M.TurnRight(arrivalHeading)

    for _, eid in ipairs(node.edges) do
        local edge = M.GetEdge(eid)
        if edge and edge.heading == straightH then
            table.insert(turns, { direction = "straight", edge = edge, heading = straightH })
        elseif edge and edge.heading == leftH then
            table.insert(turns, { direction = "left", edge = edge, heading = leftH })
        elseif edge and edge.heading == rightH then
            table.insert(turns, { direction = "right", edge = edge, heading = rightH })
        end
    end

    return turns
end

function M.GetPositionOnEdge(edge, progress, laneOffset)
    edge = edge and M.GetEdge(edge.id) or nil
    if not edge then return Vector3(0, 0, 0) end

    local t = math.max(0, math.min(1, progress))
    local sx, sz = edge.worldStart.x, edge.worldStart.z
    local ex, ez = edge.worldEnd.x, edge.worldEnd.z
    local px = sx + (ex - sx) * t
    local pz = sz + (ez - sz) * t

    local right = M.HeadingToRight(edge.heading)
    px = px + right.x * laneOffset
    pz = pz + right.z * laneOffset

    return Vector3(px, 0, pz)
end

function M.GetDistanceOnEdge(edge, progress)
    return (edge and edge.length or 0.0) * math.max(0, math.min(1, progress))
end

function M.GetStartNodeId()
    local startGX = math.ceil(M.GRID_SIZE / 2)
    return M.GridToNodeId(startGX, 1)
end

function M.GetStartEdge()
    local startNodeId = M.GetStartNodeId()
    M.EnsureRowsGeneratedTo(2)

    local edge = M.GetEdgeByHeading(startNodeId, M.HEADING_POS_Z)
    if edge then return edge, startNodeId end

    local node = M.GetNode(startNodeId)
    if not node then return nil, startNodeId end
    for _, edgeId in ipairs(node.edges) do
        local candidate = M.GetEdge(edgeId)
        if candidate then
            return candidate, startNodeId
        end
    end
    return nil, startNodeId
end

-- ============================================================================
-- Intersection area
-- ============================================================================

M.INTERSECTION_HALF_SIZE = CONFIG.INTERSECTION_HALF_SIZE

function M.GetIntersectionTraverseLength()
    return M.INTERSECTION_HALF_SIZE * 2.0
end

function M.GetIntersectionPosition(nodeWorldPos, arrivalHeading, exitHeading, progress, laneOffset, exitLaneOffset)
    local halfSize = M.INTERSECTION_HALF_SIZE
    local t = math.max(0.0, math.min(1.0, progress))

    local entryFwd = M.HeadingToForward(arrivalHeading)
    local exitFwd = M.HeadingToForward(exitHeading)

    local entryPos = Vector3(
        nodeWorldPos.x - entryFwd.x * halfSize,
        0,
        nodeWorldPos.z - entryFwd.z * halfSize
    )

    local exitPos = Vector3(
        nodeWorldPos.x + exitFwd.x * halfSize,
        0,
        nodeWorldPos.z + exitFwd.z * halfSize
    )

    local centerPos = Vector3(nodeWorldPos.x, 0, nodeWorldPos.z)

    local omt = 1.0 - t
    local px = omt * omt * entryPos.x + 2 * omt * t * centerPos.x + t * t * exitPos.x
    local pz = omt * omt * entryPos.z + 2 * omt * t * centerPos.z + t * t * exitPos.z

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

    local tangentRightX = tangentZ
    local tangentRightZ = -tangentX

    local effectiveLaneOffset = laneOffset
    if arrivalHeading ~= exitHeading then
        local targetOffset = exitLaneOffset or (-laneOffset)
        effectiveLaneOffset = laneOffset + (targetOffset - laneOffset) * t
    end
    px = px + tangentRightX * effectiveLaneOffset
    pz = pz + tangentRightZ * effectiveLaneOffset

    local yaw = math.deg(math.atan(tangentX, tangentZ))

    return Vector3(px, 0, pz), yaw
end

function M.SelectExitLane(arrivalHeading, exitHeading, progress, currentLane)
    if arrivalHeading == exitHeading then
        return currentLane
    end

    local isRightTurn = (exitHeading == (arrivalHeading + 1) % 4)
    if isRightTurn then
        if progress >= 0.667 then
            return 1
        elseif progress >= 0.333 then
            return 2
        end
        return 3
    end

    if progress >= 0.667 then
        return 3
    elseif progress >= 0.333 then
        return 2
    end
    return 1
end

function M.GetEdgeEffectiveLength(edge)
    local length = edge and edge.length or M.BLOCK_SIZE
    return math.max(1.0, length - M.INTERSECTION_HALF_SIZE * 2.0)
end

function M.GetPositionOnEdgeByDist(edge, effectiveDist, laneOffset)
    edge = edge and M.GetEdge(edge.id) or nil
    if not edge then return Vector3(0, 0, 0) end

    local halfSize = M.INTERSECTION_HALF_SIZE
    local effectiveLen = M.GetEdgeEffectiveLength(edge)
    local actualDist = halfSize + math.max(0, math.min(effectiveLen, effectiveDist))
    local t = actualDist / edge.length

    local sx, sz = edge.worldStart.x, edge.worldStart.z
    local ex, ez = edge.worldEnd.x, edge.worldEnd.z
    local px = sx + (ex - sx) * t
    local pz = sz + (ez - sz) * t

    local right = M.HeadingToRight(edge.heading)
    px = px + right.x * laneOffset
    pz = pz + right.z * laneOffset

    return Vector3(px, 0, pz)
end

return M
