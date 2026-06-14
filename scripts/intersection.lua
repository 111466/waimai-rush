-- ============================================================================
-- 外卖冲冲冲 - 路口系统模块
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local PATH = cfg.PATH
local path = require("path")
local mats = require("materials")
local pools = require("pools")
local obstacles = require("obstacles")
local pickup = require("pickup_delivery")

local M = {}

-- 路口视觉节点
M.crossroadsNode = nil
M.previewRoadNodes = {}
M.arrowNodes = {}

-- 前向声明
local ApplyForwardRoadPreview

-- ============================================================================
-- 创建路口视觉
-- ============================================================================

function M.CreateVisuals(scene)
    M.crossroadsNode = scene:CreateChild("Crossroads")
    local model = M.crossroadsNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mats.crossroads
    M.crossroadsNode.scale = Vector3(CONFIG.ROAD_WIDTH, 0.16, PATH.CROSSROADS_SIZE)
    M.crossroadsNode.position = Vector3(0, -100, 0)

    for i = 1, PATH.TURN_VISUAL_SEGMENTS + 2 do
        local pNode = scene:CreateChild("PreviewRoad" .. i)
        local pm = pNode:CreateComponent("StaticModel")
        pm.model = cache:GetResource("Model", "Models/Box.mdl")
        pm.material = mats.road
        pNode.scale = Vector3(CONFIG.ROAD_WIDTH, 0.14, PATH.PREVIEW_ROAD_LENGTH)
        pNode.position = Vector3(0, -100, 0)
        M.previewRoadNodes[i] = pNode
    end

    for i = 1, 3 do
        local aNode = scene:CreateChild("Arrow" .. i)
        local am = aNode:CreateComponent("StaticModel")
        am.model = cache:GetResource("Model", "Models/Cone.mdl")
        am.material = mats.arrow
        aNode.scale = Vector3(1.0, 0.3, 1.5)
        aNode.position = Vector3(0, -100, 0)
        M.arrowNodes[i] = aNode
    end
end

-- ============================================================================
-- 显示/隐藏路口
-- ============================================================================

ApplyForwardRoadPreview = function(displayDir)
    local s = path.state
    local cutoff = s.nextIntersectionDist + PATH.CROSSROADS_SIZE * 0.25
    for _, seg in ipairs(pools.roadPool) do
        if displayDir ~= 0 and seg.pathDist >= cutoff then
            pools.HideRoadSegment(seg)
        else
            pools.PositionRoadSegment(seg, seg.pathDist)
        end
    end

    for _, item in ipairs(pools.linePool) do
        if displayDir ~= 0 and item.pathDist >= cutoff then
            pools.HideLaneLine(item)
        else
            pools.PositionLaneLine(item, item.pathDist)
        end
    end
end

function M.Show()
    local s = path.state
    if not M.crossroadsNode then return end

    local intLocalDist = s.nextIntersectionDist - s.currentSegmentStartDist
    local fwd = path.GetForwardVector(s.currentHeading)
    local intX = s.currentSegmentOrigin.x + fwd.x * intLocalDist
    local intZ = s.currentSegmentOrigin.z + fwd.z * intLocalDist

    s.turnWorldPos = Vector3(intX, 0, intZ)

    M.crossroadsNode.position = Vector3(intX, 0.08, intZ)
    M.crossroadsNode.rotation = Quaternion(path.HeadingToYaw(s.currentHeading), Vector3.UP)

    local displayDir = s.turnChoice
    if displayDir == nil then displayDir = s.intersectionHintDir end
    ApplyForwardRoadPreview(displayDir)

    for _, node in ipairs(M.previewRoadNodes) do
        node.position = Vector3(0, -100, 0)
    end
    for _, node in ipairs(M.arrowNodes) do
        node.position = Vector3(0, -100, 0)
    end

    if displayDir == 0 then
        for i = 1, math.min(#M.previewRoadNodes, 5) do
            local dist = PATH.CROSSROADS_SIZE * 0.5 + PATH.PREVIEW_ROAD_LENGTH * (i - 0.5)
            local node = M.previewRoadNodes[i]
            node.position = Vector3(intX + fwd.x * dist, 0.07, intZ + fwd.z * dist)
            node.rotation = Quaternion(path.HeadingToYaw(s.currentHeading), Vector3.UP)
        end
        M.arrowNodes[1].position = Vector3(intX + fwd.x * 3.5, 0.5, intZ + fwd.z * 3.5)
        M.arrowNodes[1].rotation = Quaternion(path.HeadingToYaw(s.currentHeading) - 90, Vector3.UP)
        return
    end

    local startOrigin = Vector3(intX, 0, intZ)
    for i = 1, PATH.TURN_VISUAL_SEGMENTS do
        local arcDist = (i - 0.35) / PATH.TURN_VISUAL_SEGMENTS * PATH.TURN_ARC_LENGTH
        local pos = path.GetTurnPoint(startOrigin, s.currentHeading, displayDir, arcDist, 0.0)
        local yaw = path.HeadingToYaw(s.currentHeading) + displayDir * math.deg(arcDist / PATH.TURN_RADIUS)
        local node = M.previewRoadNodes[i]
        node.position = Vector3(pos.x, 0.07, pos.z)
        node.rotation = Quaternion(yaw, Vector3.UP)
    end

    local exitHeading = path.GetTurnEndHeading(s.currentHeading, displayDir)
    local exitFwd = path.GetForwardVector(exitHeading)
    local exitPos = path.GetTurnPoint(startOrigin, s.currentHeading, displayDir, PATH.TURN_ARC_LENGTH, 0.0)
    for i = 1, 2 do
        local node = M.previewRoadNodes[PATH.TURN_VISUAL_SEGMENTS + i]
        local dist = PATH.PREVIEW_ROAD_LENGTH * (i - 0.5)
        node.position = Vector3(exitPos.x + exitFwd.x * dist, 0.07, exitPos.z + exitFwd.z * dist)
        node.rotation = Quaternion(path.HeadingToYaw(exitHeading), Vector3.UP)
    end

    local arrowIdx = displayDir < 0 and 2 or 3
    local arrowPos = path.GetTurnPoint(startOrigin, s.currentHeading, displayDir, PATH.TURN_ARC_LENGTH * 0.45, 0.0)
    M.arrowNodes[arrowIdx].position = Vector3(arrowPos.x, 0.5, arrowPos.z)
    M.arrowNodes[arrowIdx].rotation = Quaternion(path.HeadingToYaw(exitHeading) - 90, Vector3.UP)
end

function M.Hide()
    if M.crossroadsNode then
        M.crossroadsNode.position = Vector3(0, -100, 0)
    end
    for i = 1, #M.previewRoadNodes do
        if M.previewRoadNodes[i] then
            M.previewRoadNodes[i].position = Vector3(0, -100, 0)
        end
    end
    for i = 1, #M.arrowNodes do
        if M.arrowNodes[i] then
            M.arrowNodes[i].position = Vector3(0, -100, 0)
        end
    end
end

-- ============================================================================
-- 路口逻辑
-- ============================================================================

function M.ScheduleNext()
    local s = path.state
    local interval = PATH.INTERVAL_MIN + math.random() * (PATH.INTERVAL_MAX - PATH.INTERVAL_MIN)
    s.nextIntersectionDist = s.routeDistance + interval
    s.intersectionActive = false
    s.turnChoice = 0
end

function M.ExecuteTurn(turnDir)
    local s = path.state

    if turnDir == 0 then
        M.Hide()
        M.ScheduleNext()
        if pickup.hasPackage and s.intersectionCorrectDir == 0 then
            pickup.timeRemaining = pickup.timeRemaining + PATH.CORRECT_TURN_BONUS
        elseif pickup.hasPackage then
            pickup.timeRemaining = math.max(2.0, pickup.timeRemaining - PATH.WRONG_TURN_PENALTY)
        end
        return
    end

    s.turnFromHeading = s.currentHeading
    s.turnToHeading = path.GetTurnEndHeading(s.currentHeading, turnDir)
    s.turnDir = turnDir

    local intLocalDist = s.nextIntersectionDist - s.currentSegmentStartDist
    local fwd = path.GetForwardVector(s.currentHeading)
    local intX = s.currentSegmentOrigin.x + fwd.x * intLocalDist
    local intZ = s.currentSegmentOrigin.z + fwd.z * intLocalDist
    s.turnWorldPos = Vector3(intX, 0, intZ)
    s.turnStartOrigin = Vector3(intX, 0, intZ)
    s.turnStartDist = s.nextIntersectionDist
    s.turnEndDist = s.turnStartDist + PATH.TURN_ARC_LENGTH
    s.turnEndOrigin = path.GetTurnPoint(s.turnStartOrigin, s.turnFromHeading, turnDir, PATH.TURN_ARC_LENGTH, 0.0)

    s.turnExecuting = true
    s.turnAnimTime = 0.0
    s.camTurning = false

    -- 清场
    obstacles.ClearAll()
    obstacles.lastSpawnDist = s.turnEndDist + PATH.SAFE_ZONE_AFTER

    pickup.pickupActive = false
    pickup.pickupNode.position = Vector3(0, -100, 0)
    pickup.deliveryActive = false
    pickup.deliveryNode.position = Vector3(0, -100, 0)

    -- 奖惩
    if pickup.hasPackage and s.intersectionCorrectDir == turnDir then
        pickup.timeRemaining = pickup.timeRemaining + PATH.CORRECT_TURN_BONUS
    elseif pickup.hasPackage then
        pickup.timeRemaining = math.max(2.0, pickup.timeRemaining - PATH.WRONG_TURN_PENALTY)
    end
end

function M.Update()
    local s = path.state
    if s.turnExecuting then return end
    if s.nextIntersectionDist <= 0 then return end

    local distToInt = s.nextIntersectionDist - s.routeDistance

    if distToInt < PATH.TURN_INPUT_WINDOW and distToInt > 0 and not s.intersectionActive then
        s.intersectionActive = true
        local r = math.random()
        if r < 0.33 then s.intersectionHintDir = -1
        elseif r < 0.66 then s.intersectionHintDir = 1
        else s.intersectionHintDir = 0 end
        s.turnChoice = s.intersectionHintDir
        M.Show()
    end

    if distToInt <= PATH.TURN_EXECUTE_DIST and s.intersectionActive then
        s.intersectionActive = false
        M.ExecuteTurn(s.turnChoice)
        s.turnChoice = 0
    end
end

function M.UpdateTurnAnimation(dt, playerNode)
    local s = path.state
    if not s.turnExecuting then return end

    s.turnAnimTime = s.turnAnimTime + dt

    if s.routeDistance >= s.turnEndDist then
        s.turnExecuting = false
        s.currentHeading = s.turnToHeading
        s.currentSegmentOrigin = Vector3(s.turnEndOrigin.x, 0, s.turnEndOrigin.z)
        s.currentSegmentStartDist = s.turnEndDist
        playerNode.rotation = Quaternion(path.HeadingToYaw(s.currentHeading), Vector3.UP)

        -- 重新铺设对象池
        for i = 1, CONFIG.ROAD_SEGMENTS do
            local dist = s.currentSegmentStartDist + (i - 1) * CONFIG.ROAD_SEGMENT_LENGTH
            pools.PositionRoadSegment(pools.roadPool[i], dist)
        end
        for i = 1, CONFIG.LINE_POOL_SIZE do
            local dist = s.currentSegmentStartDist + (i - 1) * CONFIG.LINE_SPACING
            pools.PositionLaneLine(pools.linePool[i], dist)
        end
        for i = 1, CONFIG.BUILDING_POOL_SIZE do
            local item = pools.buildingPool[i]
            local dist = s.currentSegmentStartDist + (i - 1) * 8.0
            local side = (i % 2 == 0) and 1 or -1
            local lateral = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
            pools.PositionBuilding(item, dist, side, lateral)
        end

        obstacles.lastSpawnDist = s.currentSegmentStartDist + PATH.SAFE_ZONE_AFTER
        pickup.nextPickupDist = s.routeDistance + 30.0
        pickup.nextDeliveryDist = s.routeDistance + 50.0
        M.Hide()
        M.ScheduleNext()
    end
end

return M
