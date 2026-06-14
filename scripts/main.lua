-- ============================================================================
-- 外卖冲冲冲 - 入口文件（整合所有模块）
-- Temple Run 式 90° 转向竖屏跑酷
-- ============================================================================

-- 加载模块
local cfg = require("config")
local CONFIG = cfg.CONFIG
local PATH = cfg.PATH
local path = require("path")
local mats = require("materials")
local pools = require("pools")
local obstacles = require("obstacles")
local pickup = require("pickup_delivery")
local intersection = require("intersection")
local player = require("player")
local cam = require("camera")
local ui = require("ui")
local inp = require("input")

-- ============================================================================
-- 全局变量
-- ============================================================================
---@type Scene
local scene_ = nil

-- 游戏状态: "running" / "gameOver"
local gameState_ = "running"

-- ============================================================================
-- 游戏结束
-- ============================================================================

local function GameOver()
    gameState_ = "gameOver"
    ui.ShowGameOver(pickup.totalIncome, player.distanceTraveled)
end

-- ============================================================================
-- 重新开始
-- ============================================================================

local function RestartGame()
    gameState_ = "running"

    -- 重置路径系统
    path.Init()

    -- 重置玩家
    player.Reset()

    -- 重置障碍物
    obstacles.ClearAll()
    obstacles.lastSpawnDist = 0.0
    obstacles.distanceTraveled = 0.0

    -- 重置取件/送件
    pickup.Reset()

    -- 重置路口
    intersection.Hide()

    -- 重新定位路段
    for i = 1, CONFIG.ROAD_SEGMENTS do
        local dist = (i - 1) * CONFIG.ROAD_SEGMENT_LENGTH
        pools.PositionRoadSegment(pools.roadPool[i], dist)
    end
    for i = 1, CONFIG.LINE_POOL_SIZE do
        local dist = (i - 1) * CONFIG.LINE_SPACING
        pools.PositionLaneLine(pools.linePool[i], dist)
    end
    for i = 1, CONFIG.BUILDING_POOL_SIZE do
        local item = pools.buildingPool[i]
        local dist = (i - 1) * 8.0
        local side = (i % 2 == 0) and 1 or -1
        local lateral = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
        pools.PositionBuilding(item, dist, side, lateral)
    end

    -- 隐藏结算面板
    ui.HideGameOver()
end

-- ============================================================================
-- 回收对象
-- ============================================================================

local function RecycleObjects()
    local s = path.state
    local suppressForwardRoad = s.intersectionActive and s.turnChoice ~= 0

    -- 回收道路段
    local behindThreshold = s.routeDistance - CONFIG.ROAD_SEGMENT_LENGTH * 1.5
    local aheadTarget = s.routeDistance + CONFIG.ROAD_SEGMENT_LENGTH * (CONFIG.ROAD_SEGMENTS - 1)

    for _, seg in ipairs(pools.roadPool) do
        if seg.pathDist < behindThreshold then
            aheadTarget = aheadTarget + CONFIG.ROAD_SEGMENT_LENGTH
            seg.pathDist = aheadTarget
            if suppressForwardRoad and aheadTarget >= s.nextIntersectionDist then
                pools.HideRoadSegment(seg)
            else
                pools.PositionRoadSegment(seg, aheadTarget)
            end
        end
    end

    -- 回收车道线
    local lineBehind = s.routeDistance - CONFIG.LINE_SPACING * 2
    local lineAhead = s.routeDistance + CONFIG.LINE_SPACING * CONFIG.LINE_POOL_SIZE * 0.8

    for _, item in ipairs(pools.linePool) do
        if item.pathDist < lineBehind then
            lineAhead = lineAhead + CONFIG.LINE_SPACING
            item.pathDist = lineAhead
            if suppressForwardRoad and lineAhead >= s.nextIntersectionDist then
                pools.HideLaneLine(item)
            else
                pools.PositionLaneLine(item, lineAhead)
            end
        end
    end

    -- 回收建筑
    local buildBehind = s.routeDistance - 20.0
    local buildAhead = s.routeDistance + 8.0 * CONFIG.BUILDING_POOL_SIZE * 0.7

    for _, item in ipairs(pools.buildingPool) do
        if item.pathDist < buildBehind then
            buildAhead = buildAhead + 8.0 + math.random() * 4.0
            local side = (math.random() > 0.5) and 1 or -1
            local lateral = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
            pools.PositionBuilding(item, buildAhead, side, lateral)
        end
    end

    -- 回收障碍物
    obstacles.Recycle()
end

-- ============================================================================
-- 主更新循环
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
local function HandleUpdate(eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")

    if gameState_ ~= "running" then return end

    local s = path.state

    -- 输入处理
    inp.HandleKeyboard(dt)

    -- 更新速度
    player.UpdateSpeed()

    -- 更新路程距离
    local moveDist = player.currentSpeed * dt
    s.routeDistance = s.routeDistance + moveDist
    player.distanceTraveled = player.distanceTraveled + moveDist
    obstacles.distanceTraveled = player.distanceTraveled

    -- 弯道动画
    intersection.UpdateTurnAnimation(dt, player.node)

    -- 跳跃/下滑
    local jumpY = player.UpdateJumpSlide(dt)

    -- 变道
    player.UpdateLaneChange(dt)

    -- 计算玩家世界位置
    local laneX = CONFIG.LANE_X[CONFIG.currentLane]
    if player.laneChanging then
        local t = math.min(1.0, player.laneChangeTime / CONFIG.LANE_CHANGE_DURATION)
        local smoothT = t * t * (3.0 - 2.0 * t)
        laneX = player.laneChangeFrom + (player.laneChangeTo - player.laneChangeFrom) * smoothT
    end

    local worldPos = path.GetWorldPosOnTrack(s.routeDistance, laneX)
    player.node.position = Vector3(worldPos.x, jumpY, worldPos.z)

    -- 玩家朝向跟随路径切线
    player.node.rotation = Quaternion(path.GetTrackYawAt(s.routeDistance), Vector3.UP)

    -- 路口逻辑
    intersection.Update()

    -- 生成障碍物
    obstacles.Spawn()

    -- 碰撞检测
    if obstacles.CheckCollisions(CONFIG.currentLane, player.isJumping, player.jumpTime, player.isSliding, player.slideTime) then
        GameOver()
        return
    end

    -- 取件/送件
    pickup.TrySpawnPickup()
    pickup.CheckPickup()
    pickup.TrySpawnDelivery()
    pickup.CheckDelivery()

    -- 回收对象
    RecycleObjects()

    -- 摄像机
    cam.Update(dt, player.node, player.currentSpeed)

    -- 计时器
    pickup.timeRemaining = pickup.timeRemaining - dt
    if pickup.timeRemaining <= 0 then
        pickup.timeRemaining = 0
        GameOver()
        return
    end

    -- 更新 HUD
    ui.UpdateHUD(
        pickup.timeRemaining,
        pickup.totalIncome,
        pickup.comboCount,
        player.currentSpeed,
        s.intersectionActive,
        s.intersectionHintDir,
        s.turnChoice
    )

    -- 取件/送件浮动动画
    pickup.UpdateAnimation()
end

-- ============================================================================
-- 触摸事件包装（过滤 gameState）
-- ============================================================================

local function HandleTouchBegin(eventType, eventData)
    if gameState_ ~= "running" then return end
    inp.HandleTouchBegin(eventType, eventData)
end

local function HandleTouchEnd(eventType, eventData)
    if gameState_ ~= "running" then return end
    inp.HandleTouchEnd(eventType, eventData)
end

-- ============================================================================
-- 场景初始化
-- ============================================================================

local function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 灯光
    local lightNode = scene_:CreateChild("DirectionalLight")
    lightNode.direction = Vector3(0.3, -1.0, 0.5):Normalized()
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1.0, 0.95, 0.9)
    light.brightness = 1.2
    light.castShadows = true
    light.shadowCascade = CascadeParameters(15.0, 30.0, 60.0, 120.0, 0.8)

    -- 环境光
    local zone = scene_:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-200, -50, -200), Vector3(200, 100, 200))
    zone.ambientColor = Color(0.55, 0.6, 0.7)
    zone.fogColor = Color(0.75, 0.85, 0.95)
    zone.fogStart = 80.0
    zone.fogEnd = 180.0
end

-- ============================================================================
-- Start() / CreateGameContent()
-- ============================================================================

function Start()
    CreateGameContent()
end

function CreateGameContent()
    math.randomseed(os.time())

    -- 初始化路径系统
    path.Init()

    -- 创建场景
    CreateScene()

    -- 初始化材质
    mats.Init()

    -- 创建对象池
    pools.Init(scene_)

    -- 初始化障碍物池
    obstacles.Init(scene_)

    -- 创建取件/送件节点
    pickup.CreatePickupNode(scene_)
    pickup.CreateDeliveryNode(scene_)
    pickup.nextPickupDist = 30.0
    pickup.nextDeliveryDist = 100.0

    -- 创建路口视觉
    intersection.CreateVisuals(scene_)

    -- 创建玩家
    player.Create(scene_)
    pickup.packageVisualNode = player.packageVisualNode

    -- 设置摄像机
    cam.Setup(scene_, player.node)

    -- 创建 UI
    ui.Create(RestartGame)

    -- 注册事件
    SubscribeToEvent("Update", HandleUpdate)
    SubscribeToEvent("TouchBegin", HandleTouchBegin)
    SubscribeToEvent("TouchEnd", HandleTouchEnd)

    print("[Game] 外卖冲冲冲 - 模块化版已启动!")
    print("[Game] 操作: ← → 变道/转弯 | ↑/空格 跳跃 | ↓ 下滑")
    print("[Game] 路口出现时：←/→ 选择转弯方向，↑ 直走")
end
