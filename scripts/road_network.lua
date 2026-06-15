-- ============================================================================
-- Waimai Rush - RoadGraph
-- ============================================================================
-- Parameterized grid road network. Nodes are intersections; directed edges are
-- drivable road segments. The generated graph keeps a guaranteed forward spine,
-- then removes non-critical roads by seed to create T-junctions, dead ends, and
-- detours while keeping most of the map reachable from the start.
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

-- RoadGraph data.
M.nodes = {}
M.edges = {}
M.reachableNodes = {}
M.currentSeed = M.DEFAULT_SEED
M.reachableRatio = 1.0
M.generationAttempts = 0
M.usedFallback = false
M.bounds = { minX = 0, maxX = 0, minZ = 0, maxZ = 0 }

local MAX_GENERATION_ATTEMPTS = 30

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

local function EdgeKey(a, b)
    if a < b then
        return tostring(a) .. ":" .. tostring(b)
    end
    return tostring(b) .. ":" .. tostring(a)
end

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

-- ============================================================================
-- Grid utilities
-- ============================================================================

function M.GridToNodeId(gx, gz)
    return (gz - 1) * M.GRID_SIZE + gx
end

function M.GridToWorld(gx, gz)
    local node = M.nodes[M.GridToNodeId(gx, gz)]
    if node then
        return node.worldX, node.worldZ
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
-- Generation
-- ============================================================================

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

local function MakeNodes(gridSize, xPositions, zPositions)
    local nodes = {}
    for gz = 1, gridSize do
        for gx = 1, gridSize do
            local id = (gz - 1) * gridSize + gx
            nodes[id] = {
                id = id,
                gridX = gx,
                gridZ = gz,
                worldX = xPositions[gx],
                worldZ = zPositions[gz],
                edges = {},
            }
        end
    end
    return nodes
end

local function AddCandidateEdges(gridSize)
    local edges = {}
    for gz = 1, gridSize do
        for gx = 1, gridSize do
            local id = (gz - 1) * gridSize + gx
            if gx < gridSize then
                edges[#edges + 1] = { a = id, b = (gz - 1) * gridSize + gx + 1 }
            end
            if gz < gridSize then
                edges[#edges + 1] = { a = id, b = gz * gridSize + gx }
            end
        end
    end
    return edges
end

local function BuildKeepSet(rng, gridSize, startGX)
    local keep = {}
    local cursorX = startGX

    for gz = 1, gridSize - 1 do
        if rng() < 0.66 then
            local dir = rng() < 0.5 and -1 or 1
            local nextX = Clamp(cursorX + dir, 1, gridSize)
            if nextX ~= cursorX then
                keep[EdgeKey(M.GridToNodeId(cursorX, gz), M.GridToNodeId(nextX, gz))] = true
                cursorX = nextX
            end
        end
        keep[EdgeKey(M.GridToNodeId(cursorX, gz), M.GridToNodeId(cursorX, gz + 1))] = true
    end

    for gz = 1, gridSize do
        if rng() < 0.55 then
            local fromX = math.floor(RandRange(rng, 1, gridSize))
            local toX = math.floor(RandRange(rng, fromX + 1, gridSize + 1))
            toX = Clamp(toX, fromX + 1, gridSize)
            for gx = fromX, toX - 1 do
                keep[EdgeKey(M.GridToNodeId(gx, gz), M.GridToNodeId(gx + 1, gz))] = true
            end
        end
    end

    for gx = 1, gridSize do
        if rng() < 0.42 then
            local fromZ = math.floor(RandRange(rng, 1, gridSize))
            local toZ = math.floor(RandRange(rng, fromZ + 1, gridSize + 1))
            toZ = Clamp(toZ, fromZ + 1, gridSize)
            for gz = fromZ, toZ - 1 do
                keep[EdgeKey(M.GridToNodeId(gx, gz), M.GridToNodeId(gx, gz + 1))] = true
            end
        end
    end

    return keep
end

local function ChoosePhysicalEdges(rng, candidates, keep, closureRate)
    local chosen = {}
    for _, edge in ipairs(candidates) do
        local key = EdgeKey(edge.a, edge.b)
        if keep[key] or rng() > closureRate then
            chosen[#chosen + 1] = edge
        end
    end
    return chosen
end

local function BuildAdjacency(nodeCount, physicalEdges)
    local adjacency = {}
    for i = 1, nodeCount do adjacency[i] = {} end
    for _, edge in ipairs(physicalEdges) do
        table.insert(adjacency[edge.a], edge.b)
        table.insert(adjacency[edge.b], edge.a)
    end
    return adjacency
end

local function FindReachable(startNodeId, adjacency)
    local reachable = {}
    local queue = { startNodeId }
    reachable[startNodeId] = true

    local head = 1
    while head <= #queue do
        local nodeId = queue[head]
        head = head + 1
        for _, nextId in ipairs(adjacency[nodeId] or {}) do
            if not reachable[nextId] then
                reachable[nextId] = true
                queue[#queue + 1] = nextId
            end
        end
    end

    return reachable
end

local function CountKeys(map)
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    return count
end

local function AddDirectedEdge(edges, nodes, fromNodeId, toNodeId)
    local fromNode = nodes[fromNodeId]
    local toNode = nodes[toNodeId]
    local edgeId = #edges + 1
    local dx = toNode.worldX - fromNode.worldX
    local dz = toNode.worldZ - fromNode.worldZ
    local edge = {
        id = edgeId,
        fromNode = fromNodeId,
        toNode = toNodeId,
        heading = M.CalcHeading(fromNode, toNode),
        length = math.sqrt(dx * dx + dz * dz),
        worldStart = Vector3(fromNode.worldX, 0, fromNode.worldZ),
        worldEnd = Vector3(toNode.worldX, 0, toNode.worldZ),
    }
    edges[edgeId] = edge
    table.insert(fromNode.edges, edgeId)
end

local function BuildDirectedEdges(nodes, physicalEdges)
    local edges = {}
    for _, edge in ipairs(physicalEdges) do
        AddDirectedEdge(edges, nodes, edge.a, edge.b)
        AddDirectedEdge(edges, nodes, edge.b, edge.a)
    end
    return edges
end

local function ComputeBounds(nodes)
    local minX, maxX = math.huge, -math.huge
    local minZ, maxZ = math.huge, -math.huge
    for _, node in pairs(nodes) do
        minX = math.min(minX, node.worldX)
        maxX = math.max(maxX, node.worldX)
        minZ = math.min(minZ, node.worldZ)
        maxZ = math.max(maxZ, node.worldZ)
    end
    return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

local function GenerateCandidate(seed, attempt, closureRate)
    local gridSize = CONFIG.ROAD_GRID_SIZE or 8
    local blockBase = CONFIG.ROAD_BLOCK_BASE or 86.0
    local blockJitter = CONFIG.ROAD_BLOCK_JITTER or 22.0
    local rng = NewRng(seed + attempt * 1013904223)

    M.GRID_SIZE = gridSize
    M.BLOCK_SIZE = blockBase

    local xSteps = BuildSteps(rng, gridSize, blockBase, blockJitter)
    local zSteps = BuildSteps(rng, gridSize, blockBase, blockJitter)
    local xPositions = AccumulatePositions(xSteps)
    local zPositions = AccumulatePositions(zSteps)
    local nodes = MakeNodes(gridSize, xPositions, zPositions)
    local candidates = AddCandidateEdges(gridSize)
    local startGX = math.ceil(gridSize / 2)
    local startNodeId = M.GridToNodeId(startGX, 1)
    local keep = BuildKeepSet(rng, gridSize, startGX)
    local physicalEdges = ChoosePhysicalEdges(rng, candidates, keep, closureRate)
    local adjacency = BuildAdjacency(gridSize * gridSize, physicalEdges)
    local reachable = FindReachable(startNodeId, adjacency)
    local reachableRatio = CountKeys(reachable) / (gridSize * gridSize)
    local startHasExit = #(adjacency[startNodeId] or {}) > 0
    local minReachable = CONFIG.ROAD_MIN_REACHABLE_RATIO or 0.8

    return {
        nodes = nodes,
        edges = BuildDirectedEdges(nodes, physicalEdges),
        reachableNodes = reachable,
        reachableRatio = reachableRatio,
        startNodeId = startNodeId,
        valid = startHasExit and reachableRatio >= minReachable,
        bounds = ComputeBounds(nodes),
        gridSize = gridSize,
        physicalEdgeCount = #physicalEdges,
    }
end

function M.Generate(seed)
    local normalizedSeed = NormalizeSeed(seed or M.currentSeed or M.DEFAULT_SEED)
    local closureRate = CONFIG.ROAD_CLOSURE_RATE or 0.18
    local best = nil

    for attempt = 0, MAX_GENERATION_ATTEMPTS - 1 do
        local candidate = GenerateCandidate(normalizedSeed, attempt, closureRate)
        if not best or candidate.reachableRatio > best.reachableRatio then
            best = candidate
        end
        if candidate.valid then
            M.nodes = candidate.nodes
            M.edges = candidate.edges
            M.reachableNodes = candidate.reachableNodes
            M.currentSeed = normalizedSeed
            M.reachableRatio = candidate.reachableRatio
            M.generationAttempts = attempt + 1
            M.usedFallback = false
            M.bounds = candidate.bounds
            print("[RoadNetwork] Generated seed " .. normalizedSeed ..
                " grid " .. M.GRID_SIZE .. "x" .. M.GRID_SIZE ..
                " nodes " .. #M.nodes ..
                " directedEdges " .. #M.edges ..
                " roads " .. candidate.physicalEdgeCount ..
                " reachable " .. string.format("%.0f%%", M.reachableRatio * 100) ..
                " attempts " .. M.generationAttempts)
            return true
        end
    end

    local safeClosureRate = math.min(closureRate, 0.10)
    local fallback = GenerateCandidate(normalizedSeed + 2654435769, 0, safeClosureRate)
    if fallback and fallback.valid then best = fallback end

    M.nodes = best.nodes
    M.edges = best.edges
    M.reachableNodes = best.reachableNodes
    M.currentSeed = normalizedSeed
    M.reachableRatio = best.reachableRatio
    M.generationAttempts = MAX_GENERATION_ATTEMPTS
    M.usedFallback = true
    M.bounds = best.bounds
    print("[RoadNetwork] Fallback seed " .. normalizedSeed ..
        " grid " .. M.GRID_SIZE .. "x" .. M.GRID_SIZE ..
        " nodes " .. #M.nodes ..
        " directedEdges " .. #M.edges ..
        " reachable " .. string.format("%.0f%%", M.reachableRatio * 100))
    return false
end

function M.GenerateRandom()
    local seed = os.time() + math.random(1, 1000000)
    M.Generate(seed)
    return seed
end

-- ============================================================================
-- Queries
-- ============================================================================

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

function M.GetAvailableTurns(nodeId, arrivalHeading)
    local node = M.nodes[nodeId]
    if not node then return {} end

    local turns = {}
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
    end

    return turns
end

function M.GetPositionOnEdge(edge, progress, laneOffset)
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
    return edge.length * math.max(0, math.min(1, progress))
end

function M.GetStartNodeId()
    local startGX = math.ceil(M.GRID_SIZE / 2)
    return M.GridToNodeId(startGX, 1)
end

function M.GetStartEdge()
    local startNodeId = M.GetStartNodeId()
    local edge = M.GetEdgeByHeading(startNodeId, M.HEADING_POS_Z)
    if edge then return edge, startNodeId end

    local node = M.nodes[startNodeId]
    if not node then return nil, startNodeId end
    for _, edgeId in ipairs(node.edges) do
        local candidate = M.edges[edgeId]
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
