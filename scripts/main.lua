-- ============================================================================
-- 外卖冲冲冲 - 入口文件（基于 RoadGraph 路网系统）
-- Temple Run 式 90° 转向竖屏跑酷 + 外卖配送
-- ============================================================================

-- 加载模块
local cfg = require("config")
local CONFIG = cfg.CONFIG
local rn = require("road_network")
local path = require("path")
local mats = require("materials")
local pools = require("pools")
local obstacles = require("obstacles")
local pickup = require("pickup_delivery")
local nav = require("route_navigation")
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
local groundNode_ = nil
local zone_ = nil

-- 游戏状态: "running" / "paused" / "gameOver"
local gameState_ = "running"

local function IsPaused()
    return gameState_ == "paused"
end

local function TogglePause()
    if gameState_ == "gameOver" then
        return
    end

    if gameState_ == "paused" then
        gameState_ = "running"
        ui.SetPaused(false)
    else
        gameState_ = "paused"
        ui.SetPaused(true)
    end
end

local function NextRoadSeed()
    if CONFIG.ROAD_RANDOMIZE_ON_RESTART then
        return os.time() + math.random(1, 1000000)
    end
    return rn.currentSeed or rn.DEFAULT_SEED
end

-- ============================================================================
-- 游戏结束
-- ============================================================================

local function GameOver()
    gameState_ = "gameOver"
    ui.ShowGameOver(pickup.totalIncome, player.distanceTraveled)
    print("[Game] Game Over! Income: " .. pickup.totalIncome .. " Distance: " .. string.format("%.0f", player.distanceTraveled))
end

-- ============================================================================
-- 重新开始
-- ============================================================================

local function RestartGame()
    gameState_ = "running"

    -- 重置路径系统（重新选择起始边，内部会重置所有状态机字段）
    path.Init(NextRoadSeed())
    cam.ResetDebugParams()
    pools.Clear()
    pools.Init(scene_)

    -- 重置玩家
    player.Reset()
    player.UpdatePosition(0)

    -- 重置障碍物
    obstacles.ClearAll()
    obstacles.lastSpawnEdgeId = 0
    obstacles.distanceTraveled = 0.0

    -- 重置取件/送件
    pickup.Reset()
    nav.Reset()

    -- 重置路口
    intersection.Hide()

    -- 隐藏结算面板
    ui.Create(RestartGame, TogglePause)
    ui.SetPaused(false)

    print("[Game] Restarted with road seed " .. rn.currentSeed)
end

-- ============================================================================
-- 主更新循环
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
local function HandleUpdate(eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")

    if gameState_ == "gameOver" then return end

    local s = path.state

    if input:GetKeyPress(KEY_P) then
        TogglePause()
    end

    if IsPaused() then
        cam.Update(dt, player.node, player.currentSpeed)
        ui.UpdateCameraDebugReadout()
        return
    end

    -- 清除上一帧的转向确认标记（在本帧输入处理之前）
    s.turnJustCommitted = false

    -- 更新输入状态机（在处理输入之前）
    path.UpdateInputState()

    -- 输入处理
    inp.HandleKeyboard(dt)

    -- 检查死路（玩家选择方向无路或默认直走无路）
    if s.routeBlocked then
        GameOver()
        return
    end

    -- 更新速度
    player.UpdateSpeed()

    -- 计算本帧移动距离
    local moveDist = player.currentSpeed * dt
    player.distanceTraveled = player.distanceTraveled + moveDist
    obstacles.distanceTraveled = player.distanceTraveled

    -- 推进路径（沿边前进 / 弧线过渡）
    pickup.CapturePathSnapshot()
    path.Advance(moveDist)

    -- 再次检查死路（Advance 中的 StartTurnAtNode 可能触发）
    if s.routeBlocked then
        GameOver()
        return
    end

    -- 玩家在路口区域内确认方向时的逻辑
    if s.turnJustCommitted then
        local actuallyTurning = (s.turnArrivalHeading ~= s.turnExitHeading)

        if actuallyTurning then
            -- 实际转弯（左/右）时清除旧边上的障碍物（每次改方向都可触发）
            obstacles.ClearAll()
        end

    end

    -- 路口逻辑（检测、显示箭头）
    intersection.Update()

    -- 跳跃/下滑
    local jumpY = player.UpdateJumpSlide(dt)

    -- 变道
    player.UpdateLaneChange(dt)

    -- 计算玩家世界位置（使用 path 模块）
    player.UpdatePosition(jumpY)
    pools.Update(s)
    if player.node then
        local pp = player.node.position
        if groundNode_ then
            groundNode_.position = Vector3(pp.x, -0.05, pp.z)
        end
        if zone_ then
            local span = 900.0
            zone_.boundingBox = BoundingBox(
                Vector3(pp.x - span, -50, pp.z - span),
                Vector3(pp.x + span, 120, pp.z + span)
            )
        end
    end

    if not pickup.EnsureDeliveryTargetValid() then
        pickup.TrySpawnDelivery(player.currentSpeed)
    end

    -- 先生成取件/送件点，障碍物生成时会避让订单点
    pickup.TrySpawnPickup()
    pickup.TrySpawnDelivery(player.currentSpeed)

    -- 生成障碍物
    obstacles.Spawn()

    -- 碰撞检测
    local collisionType = obstacles.CheckCollisions(
        CONFIG.currentLane,
        player.isJumping,
        player.jumpTime,
        player.isSliding,
        player.slideTime,
        player.GetCollisionState()
    )
    if collisionType == "front" then
        GameOver()
        return
    elseif collisionType == "side" then
        player.BounceBackFromSideCollision()
    end

    -- 回收已过障碍物
    obstacles.Recycle()

    -- 取件/送件
    pickup.CheckPickup()
    pickup.CheckDelivery()

    -- 配送导航：偏离推荐路线后自动重规划，不额外扣时间。
    nav.Update(s, dt)
    if nav.NeedsNewTarget() then
        pickup.ReselectDeliveryTarget(player.currentSpeed)
        nav.Update(s, 0.0)
    end
    pickup.UpdateOrderTimer(dt)

    -- 摄像机跟随
    cam.Update(dt, player.node, player.currentSpeed)

    local navData = nav.GetMinimapData(s)
    local pickupMiniData = pickup.GetMinimapData()

    ui.UpdateMinimap(navData, pickupMiniData)

    -- 更新 HUD
    ui.UpdateHUD(
        pickup.GetOrderTimerData(),
        pickup.totalIncome,
        pickup.comboCount,
        player.currentSpeed,
        s.intersectionActive,
        s.turnChoice,
        s.hasTurnChoice,
        s.availableTurns,
        navData
    )
    ui.UpdateCameraDebugReadout()

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

    local span = 900.0
    local centerX = 0.0
    local centerZ = 0.0
    local groundSizeX = span
    local groundSizeZ = span
    local zoneHalfX = groundSizeX * 0.5 + 120.0
    local zoneHalfZ = groundSizeZ * 0.5 + 120.0

    -- 方向光
    local lightNode = scene_:CreateChild("DirectionalLight")
    lightNode.direction = Vector3(0.3, -1.0, 0.5):Normalized()
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1.0, 0.95, 0.9)
    light.brightness = 1.2
    light.castShadows = false

    -- 环境光 / 雾效
    zone_ = scene_:CreateComponent("Zone")
    zone_.boundingBox = BoundingBox(
        Vector3(centerX - zoneHalfX, -50, centerZ - zoneHalfZ),
        Vector3(centerX + zoneHalfX, 120, centerZ + zoneHalfZ)
    )
    zone_.ambientColor = Color(0.55, 0.6, 0.7)
    zone_.fogColor = Color(0.75, 0.85, 0.95)
    zone_.fogStart = 100.0
    zone_.fogEnd = 220.0

    -- 地面跟随玩家，避免跑出有限地面边界。
    groundNode_ = scene_:CreateChild("Ground")
    local gm = groundNode_:CreateComponent("StaticModel")
    gm.model = cache:GetResource("Model", "Models/Box.mdl")
    gm.material = mats.CreatePBRMaterial(Color(0.35, 0.55, 0.3, 1.0), 0.0, 0.9)
    groundNode_.scale = Vector3(groundSizeX, 0.1, groundSizeZ)
    groundNode_.position = Vector3(centerX, -0.05, centerZ)
end

-- ============================================================================
-- Start() / CreateGameContent()
-- ============================================================================

function Start()
    CreateGameContent()
end

function CreateGameContent()
    math.randomseed(os.time())

    -- 初始化路径系统（生成路网 + 选择起始边）
    path.Init(NextRoadSeed())
    nav.Reset()

    -- 创建场景
    CreateScene()

    -- 初始化材质
    mats.Init()

    -- 创建玩家周围可见窗口内的道路视觉
    pools.Init(scene_)

    -- 初始化障碍物池
    obstacles.Init(scene_)

    -- 创建取件/送件节点
    pickup.CreatePickupNode(scene_)
    pickup.CreateDeliveryNode(scene_)

    -- 创建路口视觉（方向箭头）
    intersection.CreateVisuals(scene_)

    -- 创建玩家
    player.Create(scene_)
    pickup.packageVisualNode = player.packageVisualNode
    pickup.Reset()

    -- 初始化玩家位置
    player.UpdatePosition(0)

    -- 设置摄像机
    cam.Setup(scene_, player.node)

    -- 创建 UI
    ui.Create(RestartGame, TogglePause)

    -- 注册事件
    SubscribeToEvent("Update", HandleUpdate)
    SubscribeToEvent("TouchBegin", HandleTouchBegin)
    SubscribeToEvent("TouchEnd", HandleTouchEnd)

    print("[Game] ==============================")
    print("[Game] 外卖冲冲冲 - RoadGraph 流式路网版启动!")
    print("[Game] ==============================")
    print("[Game] 操作: ← → 变道/转弯 | ↑/空格 跳跃 | ↓ 下滑")
    print("[Game] 路口出现时：←/→ 选择转弯方向，↑ 直走")
    print("[Game] 路网窗口: " .. rn.GRID_SIZE .. "x" .. (CONFIG.ROAD_RENDER_WINDOW_SIZE or 5) ..
        " seed " .. rn.currentSeed ..
        " edges " .. rn.edgeCount)
end


