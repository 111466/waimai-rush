-- ============================================================================
-- 外卖冲冲冲 - 入口文件（并行道路 + 3x3 路口系统）
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
    print("[Game] Game Over! Income: " .. pickup.totalIncome .. " Distance: " .. string.format("%.0f", player.distanceTraveled))
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
    obstacles.lastSpawnEdgeId = 0
    obstacles.lastSpawnProgress = 0.0
    obstacles.distanceTraveled = 0.0

    -- 重置取件/送件
    pickup.Reset()

    -- 重置路口
    intersection.Hide()

    -- 隐藏结算面板
    ui.HideGameOver()

    print("[Game] Restarted!")
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

    -- 更新输入状态机
    path.UpdateInputState()

    -- 输入处理
    inp.HandleKeyboard(dt)

    -- 检查死路
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

    -- 推进路径
    path.Advance(moveDist)

    -- 再次检查死路
    if s.routeBlocked then
        GameOver()
        return
    end

    -- 刚确定路口出口时的逻辑
    if s.turnJustCommitted then
        local actuallyTurning = (s.turnArrivalHeading ~= s.turnExitHeading)

        if actuallyTurning then
            obstacles.ClearAll()
        end

        -- 奖惩逻辑
        if pickup.hasPackage and actuallyTurning then
            local correctDir = s.intersectionHintDir
            local actualDir = 0
            local leftH = rn.TurnLeft(s.turnArrivalHeading)
            local rightH = rn.TurnRight(s.turnArrivalHeading)
            if s.turnExitHeading == leftH then
                actualDir = -1
            elseif s.turnExitHeading == rightH then
                actualDir = 1
            end
            if actualDir == correctDir then
                pickup.timeRemaining = pickup.timeRemaining + CONFIG.CORRECT_TURN_BONUS
            else
                pickup.timeRemaining = math.max(2.0, pickup.timeRemaining - CONFIG.WRONG_TURN_PENALTY)
            end
        end
    end

    -- 路口逻辑
    intersection.Update()

    -- 跳跃/下滑
    local jumpY = player.UpdateJumpSlide(dt)

    -- 计算玩家世界位置
    player.UpdatePosition(jumpY)

    -- 生成障碍物
    obstacles.Spawn()

    -- 碰撞检测
    if obstacles.CheckCollisions(CONFIG.currentLane, player.isJumping, player.jumpTime, player.isSliding, player.slideTime) then
        GameOver()
        return
    end

    -- 回收已过障碍物
    obstacles.Recycle()

    -- 取件/送件
    pickup.TrySpawnPickup()
    pickup.CheckPickup()
    pickup.TrySpawnDelivery()
    pickup.CheckDelivery()

    -- 摄像机跟随
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
        s.desiredTurn
    )

    -- 取件/送件浮动动画
    pickup.UpdateAnimation()
end

-- ============================================================================
-- 触摸事件包装
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

    -- 方向光
    local lightNode = scene_:CreateChild("DirectionalLight")
    lightNode.direction = Vector3(0.3, -1.0, 0.5):Normalized()
    local light = lightNode:CreateComponent("Light")
    light.lightType = LIGHT_DIRECTIONAL
    light.color = Color(1.0, 0.95, 0.9)
    light.brightness = 1.2
    light.castShadows = true
    light.shadowCascade = CascadeParameters(15.0, 30.0, 60.0, 120.0, 0.8)

    -- 环境光 / 雾效
    local zone = scene_:CreateComponent("Zone")
    zone.boundingBox = BoundingBox(Vector3(-500, -50, -500), Vector3(500, 100, 500))
    zone.ambientColor = Color(0.55, 0.6, 0.7)
    zone.fogColor = Color(0.75, 0.85, 0.95)
    zone.fogStart = 100.0
    zone.fogEnd = 220.0

    -- 地面
    local groundNode = scene_:CreateChild("Ground")
    local gm = groundNode:CreateComponent("StaticModel")
    gm.model = cache:GetResource("Model", "Models/Box.mdl")
    gm.material = mats.CreatePBRMaterial(Color(0.35, 0.55, 0.3, 1.0), 0.0, 0.9)
    groundNode.scale = Vector3(600, 0.1, 600)
    groundNode.position = Vector3(0, -0.05, 150)
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
    path.Init()

    -- 创建场景
    CreateScene()

    -- 初始化材质
    mats.Init()

    -- 创建道路视觉（基于路网渲染所有并行道路）
    pools.Init(scene_)

    -- 初始化障碍物池
    obstacles.Init(scene_)

    -- 创建取件/送件节点
    pickup.CreatePickupNode(scene_)
    pickup.CreateDeliveryNode(scene_)
    pickup.nextPickupDistance = 30.0
    pickup.nextDeliveryDistance = 100.0

    -- 创建路口视觉
    intersection.CreateVisuals(scene_)

    -- 创建玩家
    player.Create(scene_)
    pickup.packageVisualNode = player.packageVisualNode

    -- 初始化玩家位置
    player.UpdatePosition(0)

    -- 设置摄像机
    cam.Setup(scene_, player.node)

    -- 创建 UI
    ui.Create(RestartGame)

    -- 注册事件
    SubscribeToEvent("Update", HandleUpdate)
    SubscribeToEvent("TouchBegin", HandleTouchBegin)
    SubscribeToEvent("TouchEnd", HandleTouchEnd)

    print("[Game] ==============================")
    print("[Game] 外卖冲冲冲 - 并行道路版启动!")
    print("[Game] ==============================")
    print("[Game] 操作: ← → 切换道路/选择转弯 | ↑/空格 跳跃+直走 | ↓ 下滑")
    print("[Game] 路口内：←/→ 选择转弯方向，↑ 选择直走")
    print("[Game] 路网规模: " .. rn.GRID_SIZE .. "x" .. rn.GRID_SIZE .. " 网格, 间距 " .. rn.BLOCK_SIZE .. "m")
    print("[Game] 每方向 " .. rn.PARALLEL_COUNT .. " 条并行道路，间距 " .. rn.LANE_SPACING .. "m")
end
