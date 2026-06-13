-- ============================================================================
-- 外卖冲冲冲 - 阶段 3.6：失败原因与教学反馈强化
-- 竖屏跑酷游戏原型
-- 风格：积木阳光城（浅色道路、蓝绿城市基底、大块面、强轮廓）
-- ============================================================================

local UI = require("urhox-libs/UI")

-- ============================================================================
-- 全局变量
-- ============================================================================
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
---@type Node
local playerNode_ = nil

-- 游戏状态: "running" / "gameOver"
local gameState_ = "running"

-- 游戏配置
local CONFIG = {
    -- 三车道横向坐标（左、中、右）
    LANE_X = { -2.0, 0.0, 2.0 },
    -- 玩家当前车道索引（1=左, 2=中, 3=右）
    currentLane = 2,

    -- 跑道参数
    ROAD_WIDTH = 7.0,
    ROAD_SEGMENT_LENGTH = 40.0,
    ROAD_SEGMENTS = 8,

    -- 车道线参数
    LINE_SPACING = 3.0,
    LINE_LENGTH = 1.5,
    LINE_POOL_SIZE = 40,

    -- 建筑参数
    BUILDING_ZONE_START = 4.5,
    BUILDING_ZONE_END = 15.0,
    BUILDING_POOL_SIZE = 40,

    -- 速度参数
    BASE_SPEED = 8.0,            -- 初始速度（米/秒）
    MAX_SPEED = 14.0,            -- 最高速度（米/秒）
    SPEED_DISTANCE_FACTOR = 100.0, -- 每跑多少米增加 1 点速度

    -- 摄像机跟随参数（竖屏跑酷视角）
    CAM_OFFSET_Y = 6.0,
    CAM_OFFSET_Z = -7.0,
    CAM_LOOK_AHEAD = 5.0,

    -- 障碍物参数（每种类型独立池，各 8 个）
    OBSTACLE_POOL_PER_TYPE = 8,
    OBSTACLE_SPAWN_AHEAD = 80.0,
    OBSTACLE_RECYCLE_BEHIND = 10.0,

    -- 障碍间距（会随进度缩短）
    SPACING_MIN_START = 14.0,   -- 初期最小间距
    SPACING_MAX_START = 22.0,   -- 初期最大间距
    SPACING_MIN_END = 10.0,     -- 后期最小间距
    SPACING_MAX_END = 15.0,     -- 后期最大间距
    SPACING_RAMP_DISTANCE = 600.0, -- 间距从起始缩短到结束所需距离

    -- 碰撞参数
    COLLISION_Z_THRESHOLD = 0.8,
}

-- 变道参数
local LANE_CHANGE_DURATION = 0.18
local SWIPE_THRESHOLD = 40.0

-- 变道状态
local laneChangeTimer_ = 0.0
local laneChangeFromX_ = 0.0
local laneChangeToX_ = 0.0

-- 跳跃与下滑参数
local JUMP_DURATION = 0.6
local JUMP_HEIGHT = 1.5
local SLIDE_DURATION = 0.5

-- 动作状态: "run" / "jump" / "slide"
local actionState_ = "run"
local actionTimer_ = 0.0

-- 输入缓冲（动作容错）
local jumpBufferTimer_ = 0.0
local slideBufferTimer_ = 0.0
local inputBufferDuration_ = 0.12

-- 触摸滑动检测
local touchStartX_ = nil
local touchStartY_ = nil
local touchId_ = -1
local touchConsumed_ = false

-- 运行追踪
local distanceTraveled_ = 0.0
local currentSpeed_ = CONFIG.BASE_SPEED   -- 当前速度（随距离递增）
local runTime_ = 0.0                       -- 本次运行时间（秒）
local bestDistance_ = 0                    -- 最高距离（内存保存）

-- 道路循环池
local roadSegments_ = {}
local nextSegmentZ_ = 0.0

-- 车道线池
local laneLines_ = {}
local nextLineZ_ = 0.0

-- 建筑池
local buildings_ = {}
local nextBuildingZ_ = 0.0

-- 障碍物池
local obstacles_ = {}
local nextObstacleZ_ = 30.0

-- 共享材质
local mat_ = {}

-- 取餐点状态
local orderState_ = "none"         -- "none" = 未取餐, "carrying" = 已取餐（送餐中）
---@type Node
local pickupNode_ = nil
local pickupLane_ = 0
local pickupActive_ = false
local nextPickupZ_ = 35.0

-- 送餐点状态
---@type Node
local deliveryNode_ = nil
local deliveryLane_ = 0
local deliveryActive_ = false
local nextDeliveryZ_ = 0.0

-- 送餐倒计时
local deliveryTimeLimit_ = 12.0    -- 送餐限时（秒）
local deliveryTimer_ = 0.0         -- 当前剩余时间

-- 收入
local deliveryReward_ = 8          -- 每次送达收益
local currentIncome_ = 0           -- 本局累计收入

-- 携带容量
local maxCarryOrders_ = 2          -- 最多可携带订单数
local carriedOrderCount_ = 0       -- 当前携带订单数
local deliveredOrderCount_ = 0     -- 本局已送达订单数

-- Toast 提示
local toastTimer_ = 0.0            -- Toast 剩余显示时间

-- 连送系统
local comboCount_ = 0              -- 当前连续送达次数
local maxComboCount_ = 0           -- 本局最高连送

-- 超时警告
local lowTimeWarningShown_ = false -- 本轮倒计时是否已显示快超时提示

-- 送达加速
local boostTimer_ = 0.0            -- 加速剩余时间
local boostDuration_ = 1.5         -- 加速持续时长(秒)
local boostSpeedBonus_ = 2.0       -- 加速额外速度(m/s)

-- 游戏结束 UI 引用
local gameOverPanel_ = nil

-- 开局提示标记（第一帧显示）
local startToastPending_ = true

-- 首分钟节奏保底
local firstDeliveryInRun_ = true       -- 第一次送餐点使用更近间距
local lastOrderPointSeenTime_ = 0.0    -- 最近一次订单相关事件的 runTime_

-- 难度曲线
local highPressureToastShown_ = false  -- 高压期提示是否已显示

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    CreateScene()
    CreateMaterials()
    CreateRoadPool()
    CreateLaneLinePool()
    CreateBuildingPool()
    CreatePlayer()
    CreateObstaclePool()
    CreatePickupPoint()
    CreateDeliveryPoint()
    SetupCamera()
    CreateUI()

    SubscribeToEvent("Update", "HandleUpdate")

    print("=== 外卖冲冲冲 - 阶段 3.6：失败原因与教学反馈强化 ===")
    print("操作: 左右滑动=变道, 上滑/空格=跳跃, 下滑/S=下滑")
    print("新增: 三道封死检测 + 同车道过密检测 + 公平性前推机制")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- 场景创建
-- ============================================================================

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    local zone = lightGroup:GetComponent("Zone", true)
    if zone then
        zone.fogColor = Color(0.75, 0.88, 0.95)
        zone.fogStart = 60.0
        zone.fogEnd = 200.0
    end

    local light = lightGroup:GetComponent("Light", true)
    if light then
        light.color = Color(1.0, 0.95, 0.85)
        light.brightness = 3.5
    end
end

-- ============================================================================
-- 材质
-- ============================================================================

---@param diffuse Color
---@param metallic number
---@param roughness number
---@return Material
local function CreatePBRMaterial(diffuse, metallic, roughness)
    local m = Material:new()
    m:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    m:SetShaderParameter("MatDiffColor", Variant(diffuse))
    m:SetShaderParameter("MatSpecColor", Variant(Color(0.4, 0.4, 0.4, 1.0)))
    m:SetShaderParameter("Metallic", Variant(metallic))
    m:SetShaderParameter("Roughness", Variant(roughness))
    return m
end

function CreateMaterials()
    mat_.road = CreatePBRMaterial(Color(0.88, 0.88, 0.85, 1.0), 0.0, 0.8)
    mat_.laneLine = CreatePBRMaterial(Color(1.0, 1.0, 1.0, 1.0), 0.0, 0.9)
    mat_.sidewalk = CreatePBRMaterial(Color(0.72, 0.82, 0.78, 1.0), 0.0, 0.7)
    mat_.curb = CreatePBRMaterial(Color(0.6, 0.7, 0.65, 1.0), 0.0, 0.6)

    mat_.buildings = {
        CreatePBRMaterial(Color(0.55, 0.82, 0.78, 1.0), 0.0, 0.7),
        CreatePBRMaterial(Color(0.65, 0.80, 0.90, 1.0), 0.0, 0.7),
        CreatePBRMaterial(Color(0.92, 0.85, 0.65, 1.0), 0.0, 0.7),
        CreatePBRMaterial(Color(0.88, 0.70, 0.60, 1.0), 0.0, 0.7),
        CreatePBRMaterial(Color(0.80, 0.75, 0.90, 1.0), 0.0, 0.7),
        CreatePBRMaterial(Color(0.95, 0.92, 0.82, 1.0), 0.0, 0.7),
    }

    mat_.obstacleBlock = CreatePBRMaterial(Color(0.9, 0.25, 0.2, 1.0), 0.0, 0.5)
    mat_.obstacleLow = CreatePBRMaterial(Color(0.2, 0.75, 0.3, 1.0), 0.0, 0.5)
    mat_.obstacleHigh = CreatePBRMaterial(Color(0.6, 0.25, 0.8, 1.0), 0.0, 0.5)

    -- 取餐点材质（橙色，醒目）
    mat_.pickupBase = CreatePBRMaterial(Color(1.0, 0.6, 0.1, 1.0), 0.0, 0.4)
    mat_.pickupTop = CreatePBRMaterial(Color(1.0, 0.85, 0.2, 1.0), 0.0, 0.4)

    -- 取餐点柱子材质（明亮橙黄渐变标识柱）
    mat_.pickupPillar = CreatePBRMaterial(Color(1.0, 0.75, 0.15, 1.0), 0.0, 0.3)

    -- 送餐点材质（蓝绿色，和取餐点区分）
    mat_.deliveryBase = CreatePBRMaterial(Color(0.1, 0.75, 0.65, 1.0), 0.0, 0.4)
    mat_.deliveryTop = CreatePBRMaterial(Color(0.2, 0.9, 0.8, 1.0), 0.0, 0.4)
    -- 送餐点柱子材质
    mat_.deliveryPillar = CreatePBRMaterial(Color(0.15, 0.85, 0.75, 1.0), 0.0, 0.3)
end

-- ============================================================================
-- 道路循环池
-- ============================================================================

local function CreateOneRoadSegment(zCenter)
    local segLen = CONFIG.ROAD_SEGMENT_LENGTH
    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")

    local road = scene_:CreateChild("Road")
    road.position = Vector3(0, -0.05, zCenter)
    road.scale = Vector3(CONFIG.ROAD_WIDTH, 0.1, segLen)
    local rm = road:CreateComponent("StaticModel")
    rm:SetModel(boxMdl)
    rm:SetMaterial(mat_.road)

    local curbL = scene_:CreateChild("CurbL")
    curbL.position = Vector3(-CONFIG.ROAD_WIDTH / 2 - 0.15, 0.05, zCenter)
    curbL.scale = Vector3(0.3, 0.3, segLen)
    local clm = curbL:CreateComponent("StaticModel")
    clm:SetModel(boxMdl)
    clm:SetMaterial(mat_.curb)

    local curbR = scene_:CreateChild("CurbR")
    curbR.position = Vector3(CONFIG.ROAD_WIDTH / 2 + 0.15, 0.05, zCenter)
    curbR.scale = Vector3(0.3, 0.3, segLen)
    local crm = curbR:CreateComponent("StaticModel")
    crm:SetModel(boxMdl)
    crm:SetMaterial(mat_.curb)

    local swL = scene_:CreateChild("SidewalkL")
    swL.position = Vector3(-CONFIG.ROAD_WIDTH / 2 - 1.5, -0.02, zCenter)
    swL.scale = Vector3(2.5, 0.1, segLen)
    local slm = swL:CreateComponent("StaticModel")
    slm:SetModel(boxMdl)
    slm:SetMaterial(mat_.sidewalk)

    local swR = scene_:CreateChild("SidewalkR")
    swR.position = Vector3(CONFIG.ROAD_WIDTH / 2 + 1.5, -0.02, zCenter)
    swR.scale = Vector3(2.5, 0.1, segLen)
    local srm = swR:CreateComponent("StaticModel")
    srm:SetModel(boxMdl)
    srm:SetMaterial(mat_.sidewalk)

    return { road = road, curbL = curbL, curbR = curbR, swL = swL, swR = swR }
end

local function MoveRoadSegment(seg, zCenter)
    seg.road.position = Vector3(0, -0.05, zCenter)
    seg.curbL.position = Vector3(-CONFIG.ROAD_WIDTH / 2 - 0.15, 0.05, zCenter)
    seg.curbR.position = Vector3(CONFIG.ROAD_WIDTH / 2 + 0.15, 0.05, zCenter)
    seg.swL.position = Vector3(-CONFIG.ROAD_WIDTH / 2 - 1.5, -0.02, zCenter)
    seg.swR.position = Vector3(CONFIG.ROAD_WIDTH / 2 + 1.5, -0.02, zCenter)
end

function CreateRoadPool()
    local segLen = CONFIG.ROAD_SEGMENT_LENGTH
    for i = 1, CONFIG.ROAD_SEGMENTS do
        local zCenter = (i - 1) * segLen + segLen / 2
        roadSegments_[i] = CreateOneRoadSegment(zCenter)
    end
    nextSegmentZ_ = CONFIG.ROAD_SEGMENTS * segLen
end

-- ============================================================================
-- 车道线循环池
-- ============================================================================

local function CreateOneLaneLine(z)
    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")
    local lineLen = CONFIG.LINE_LENGTH

    local lineL = scene_:CreateChild("LineL")
    lineL.position = Vector3(-1.0, 0.01, z)
    lineL.scale = Vector3(0.1, 0.02, lineLen)
    local lm = lineL:CreateComponent("StaticModel")
    lm:SetModel(boxMdl)
    lm:SetMaterial(mat_.laneLine)

    local lineR = scene_:CreateChild("LineR")
    lineR.position = Vector3(1.0, 0.01, z)
    lineR.scale = Vector3(0.1, 0.02, lineLen)
    local rm = lineR:CreateComponent("StaticModel")
    rm:SetModel(boxMdl)
    rm:SetMaterial(mat_.laneLine)

    return { lineL = lineL, lineR = lineR }
end

function CreateLaneLinePool()
    local spacing = CONFIG.LINE_SPACING
    for i = 1, CONFIG.LINE_POOL_SIZE do
        local z = (i - 1) * spacing + CONFIG.LINE_LENGTH / 2
        laneLines_[i] = CreateOneLaneLine(z)
    end
    nextLineZ_ = CONFIG.LINE_POOL_SIZE * spacing + CONFIG.LINE_LENGTH / 2
end

-- ============================================================================
-- 建筑循环池
-- ============================================================================

local function RandomBuildingProps(z)
    local side = (math.random() > 0.5) and 1 or -1
    local xDist = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
    local x = side * xDist
    local width = 1.5 + math.random() * 2.5
    local height = 2.0 + math.random() * 8.0
    local depth = 1.5 + math.random() * 2.5
    local matIdx = math.random(1, #mat_.buildings)
    return x, width, height, depth, matIdx
end

local function PlaceBuilding(node, z)
    local x, width, height, depth, matIdx = RandomBuildingProps(z)
    node.position = Vector3(x, height / 2, z)
    node.scale = Vector3(width, height, depth)
    local model = node:GetComponent("StaticModel")
    model:SetMaterial(mat_.buildings[matIdx])
end

function CreateBuildingPool()
    math.randomseed(42)
    local totalVisibleLength = CONFIG.ROAD_SEGMENTS * CONFIG.ROAD_SEGMENT_LENGTH
    local spacing = totalVisibleLength / CONFIG.BUILDING_POOL_SIZE
    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")

    for i = 1, CONFIG.BUILDING_POOL_SIZE do
        local z = (i - 1) * spacing + math.random() * spacing
        local x, width, height, depth, matIdx = RandomBuildingProps(z)

        local node = scene_:CreateChild("Building")
        node.position = Vector3(x, height / 2, z)
        node.scale = Vector3(width, height, depth)
        local model = node:CreateComponent("StaticModel")
        model:SetModel(boxMdl)
        model:SetMaterial(mat_.buildings[matIdx])
        model.castShadows = true

        buildings_[i] = node
    end
    nextBuildingZ_ = totalVisibleLength
end

-- ============================================================================
-- 障碍物对象池
-- ============================================================================

--- 创建单个障碍物节点（初始隐藏）
local function CreateObstacleNode(obstacleType)
    local node = scene_:CreateChild("Obstacle")
    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")

    if obstacleType == "block" then
        node.scale = Vector3(1.0, 1.2, 1.0)
        local model = node:CreateComponent("StaticModel")
        model:SetModel(boxMdl)
        model:SetMaterial(mat_.obstacleBlock)
        model.castShadows = true
    elseif obstacleType == "low" then
        node.scale = Vector3(1.5, 0.6, 0.3)
        local model = node:CreateComponent("StaticModel")
        model:SetModel(boxMdl)
        model:SetMaterial(mat_.obstacleLow)
        model.castShadows = true
    elseif obstacleType == "high" then
        node.scale = Vector3(1.2, 0.4, 0.3)
        local model = node:CreateComponent("StaticModel")
        model:SetModel(boxMdl)
        model:SetMaterial(mat_.obstacleHigh)
        model.castShadows = true
    end

    node.position = Vector3(0, -100, -100)
    node.enabled = false
    return node
end

function CreateObstaclePool()
    local types = { "block", "low", "high" }
    local idx = 0
    for _, obstType in ipairs(types) do
        for _ = 1, CONFIG.OBSTACLE_POOL_PER_TYPE do
            idx = idx + 1
            local node = CreateObstacleNode(obstType)
            obstacles_[idx] = {
                node = node,
                type = obstType,
                lane = 0,
                active = false,
            }
        end
    end
    print(string.format("[障碍物] 对象池: 每类型=%d, 总共=%d", CONFIG.OBSTACLE_POOL_PER_TYPE, idx))
end

local function GetFreeObstacle(desiredType)
    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if not obs.active and obs.type == desiredType then
            return obs
        end
    end
    return nil
end

local function ActivateObstacle(obs, lane, z)
    obs.active = true
    obs.lane = lane

    local laneX = CONFIG.LANE_X[lane]
    local y = 0
    if obs.type == "block" then
        y = 0.6
    elseif obs.type == "low" then
        y = 0.3
    elseif obs.type == "high" then
        y = 1.2
    end

    obs.node.position = Vector3(laneX, y, z)
    obs.node.enabled = true
end

local function DeactivateObstacle(obs)
    obs.active = false
    obs.lane = 0
    obs.node.enabled = false
    obs.node.position = Vector3(0, -100, -100)
end

--- 获取当前难度阶段（1=教学期, 2=正常期, 3=高压期）
---@return integer
local function GetDifficultyPhase()
    if distanceTraveled_ < 150 then
        return 1
    elseif distanceTraveled_ < 500 then
        return 2
    else
        return 3
    end
end

--- 计算当前进度下的障碍间距范围（按难度阶段修正）
local function GetCurrentSpacingRange()
    local progress = math.min(distanceTraveled_ / CONFIG.SPACING_RAMP_DISTANCE, 1.0)
    local spacingMin = CONFIG.SPACING_MIN_START + (CONFIG.SPACING_MIN_END - CONFIG.SPACING_MIN_START) * progress
    local spacingMax = CONFIG.SPACING_MAX_START + (CONFIG.SPACING_MAX_END - CONFIG.SPACING_MAX_START) * progress

    -- 按阶段修正间距
    local phase = GetDifficultyPhase()
    if phase == 1 then
        -- 教学期：更稀疏，最小间距不低于 16m
        spacingMin = math.max(spacingMin, 16.0)
        spacingMax = math.max(spacingMax, spacingMin + 4.0)
    elseif phase == 3 then
        -- 高压期：略密，最小间距可降到 9m
        spacingMin = math.max(spacingMin * 0.85, 9.0)
        spacingMax = math.max(spacingMax * 0.88, spacingMin + 3.0)
    end
    -- phase 2：使用当前正常逻辑，不做修正

    return spacingMin, spacingMax
end

--- 统计某个 z 附近活跃障碍数量（用于避免三道封死）
---@param z number
---@param threshold number
---@return integer
local function CountObstaclesNearZ(z, threshold)
    local count = 0
    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if obs.active and math.abs(obs.node.position.z - z) < threshold then
            count = count + 1
        end
    end
    return count
end

--- 判断某车道在 z 附近是否过密（前后 10m 内已有活跃障碍）
---@param lane integer
---@param z number
---@return boolean
local function IsLaneTooDense(lane, z)
    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if obs.active and obs.lane == lane and math.abs(obs.node.position.z - z) < 10.0 then
            return true
        end
    end
    return false
end

--- 生成新障碍物（在玩家前方，含公平性检测）
local function SpawnObstacles(playerZ)
    local spawnLimit = playerZ + CONFIG.OBSTACLE_SPAWN_AHEAD
    local types = { "block", "low", "high" }
    local maxIterations = 60  -- 防止死循环

    local iterations = 0
    while nextObstacleZ_ < spawnLimit do
        iterations = iterations + 1
        if iterations > maxIterations then break end

        -- 公平性检测 1：避免三道封死
        if CountObstaclesNearZ(nextObstacleZ_, 3.5) >= 2 then
            -- 附近已有 2 个障碍，跳过此次，往前推安全间距
            nextObstacleZ_ = nextObstacleZ_ + 5.0
            print("[障碍公平] 避免三道封死，前推 5m")
            goto continue_spawn
        end

        do
            local typeRoll = math.random(1, 3)
            local obstType = types[typeRoll]
            local lane = math.random(1, 3)

            -- 公平性检测 2：避免同车道过密，最多换 3 次车道
            local laneAttempts = 0
            while IsLaneTooDense(lane, nextObstacleZ_) and laneAttempts < 3 do
                lane = math.random(1, 3)
                laneAttempts = laneAttempts + 1
            end
            -- 如果 3 次都不合适，前推 5m 跳过
            if IsLaneTooDense(lane, nextObstacleZ_) then
                nextObstacleZ_ = nextObstacleZ_ + 5.0
                print("[障碍公平] 同车道过密，前推 5m")
                goto continue_spawn
            end

            local obs = GetFreeObstacle(obstType)
            if not obs then
                for _, fallbackType in ipairs(types) do
                    if fallbackType ~= obstType then
                        obs = GetFreeObstacle(fallbackType)
                        if obs then break end
                    end
                end
            end

            if obs then
                ActivateObstacle(obs, lane, nextObstacleZ_)
            end
        end

        ::continue_spawn::
        local spacingMin, spacingMax = GetCurrentSpacingRange()
        local spacing = spacingMin + math.random() * (spacingMax - spacingMin)
        nextObstacleZ_ = nextObstacleZ_ + spacing
    end
end

local function RecycleObstacles(playerZ)
    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if obs.active then
            if obs.node.position.z < playerZ - CONFIG.OBSTACLE_RECYCLE_BEHIND then
                DeactivateObstacle(obs)
            end
        end
    end
end

-- ============================================================================
-- 取餐点
-- ============================================================================

--- 创建取餐点节点（多部件可视强化，初始隐藏）
function CreatePickupPoint()
    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")
    local cylMdl = cache:GetResource("Model", "Models/Cylinder.mdl")

    pickupNode_ = scene_:CreateChild("PickupPoint")
    pickupNode_.position = Vector3(0, -100, -100)
    pickupNode_.enabled = false

    -- 底座（大橙色圆盘，贴地）
    local base = pickupNode_:CreateChild("Base")
    base.position = Vector3(0, 0.08, 0)
    base.scale = Vector3(1.2, 0.16, 1.2)
    local baseModel = base:CreateComponent("StaticModel")
    baseModel:SetModel(cylMdl)
    baseModel:SetMaterial(mat_.pickupBase)
    baseModel.castShadows = true

    -- 竖直标识柱（细长圆柱）
    local pillar = pickupNode_:CreateChild("Pillar")
    pillar.position = Vector3(0, 0.9, 0)
    pillar.scale = Vector3(0.15, 1.6, 0.15)
    local pillarModel = pillar:CreateComponent("StaticModel")
    pillarModel:SetModel(cylMdl)
    pillarModel:SetMaterial(mat_.pickupPillar)
    pillarModel.castShadows = true

    -- 浮动标志容器（会上下浮动 + 旋转）
    local floater = pickupNode_:CreateChild("Floater")
    floater.position = Vector3(0, 2.0, 0)

    -- 外卖袋主体（黄色方块）
    local bag = floater:CreateChild("Bag")
    bag.position = Vector3(0, 0, 0)
    bag.scale = Vector3(0.55, 0.65, 0.45)
    local bagModel = bag:CreateComponent("StaticModel")
    bagModel:SetModel(boxMdl)
    bagModel:SetMaterial(mat_.pickupTop)
    bagModel.castShadows = true

    -- 提手（橙色小方块）
    local handle = floater:CreateChild("Handle")
    handle.position = Vector3(0, 0.4, 0)
    handle.scale = Vector3(0.28, 0.15, 0.12)
    local handleModel = handle:CreateComponent("StaticModel")
    handleModel:SetModel(boxMdl)
    handleModel:SetMaterial(mat_.pickupBase)

    print("[取餐点] 多部件节点已创建（底座+柱子+浮动标志）")
end

--- 检查某个 z 位置是否与已有障碍物冲突（同车道距离 < 4m）
---@param lane number
---@param z number
---@return boolean
local function IsPickupConflictWithObstacles(lane, z)
    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if obs.active and obs.lane == lane then
            if math.abs(obs.node.position.z - z) < 5.0 then
                return true
            end
        end
    end
    return false
end

--- 判断目标点是否与另一个活跃目标点太近（同车道 z 距离 < 8m）
local function IsOrderPointTooClose(lane, z)
    -- 检查活跃取餐点
    if pickupActive_ and pickupLane_ == lane then
        if math.abs(pickupNode_.position.z - z) < 8.0 then
            return true
        end
    end
    -- 检查活跃送餐点
    if deliveryActive_ and deliveryLane_ == lane then
        if math.abs(deliveryNode_.position.z - z) < 8.0 then
            return true
        end
    end
    return false
end

--- 尝试生成取餐点
local function TrySpawnPickup(playerZ)
    -- 携带已满或当前已有活跃取餐点时不生成
    if carriedOrderCount_ >= maxCarryOrders_ or pickupActive_ then return end

    -- 只在玩家接近 nextPickupZ_ 时生成（提前 60m 内）
    if nextPickupZ_ > playerZ + 60.0 then return end

    -- 随机选车道
    local lane = math.random(1, 3)
    local spawnZ = nextPickupZ_

    -- 避免与障碍物重叠及目标点互近：最多尝试 6 次，每次前推 5m
    for _ = 1, 6 do
        if not IsPickupConflictWithObstacles(lane, spawnZ) and not IsOrderPointTooClose(lane, spawnZ) then
            break
        end
        spawnZ = spawnZ + 5.0
    end

    -- 激活取餐点
    pickupLane_ = lane
    pickupActive_ = true
    local laneX = CONFIG.LANE_X[lane] or 0.0
    pickupNode_.position = Vector3(laneX, 0, spawnZ)
    pickupNode_.enabled = true

    lastOrderPointSeenTime_ = runTime_
    print(string.format("[取餐点] 生成: 车道=%d, Z=%.1f", lane, spawnZ))
end

--- 根据连送计数计算本次送达奖励
---@param combo integer
---@return integer
local function GetComboReward(combo)
    if combo <= 1 then return 8
    elseif combo == 2 then return 9
    elseif combo == 3 then return 10
    else return 12
    end
end

--- 显示 Toast 提示（短暂文字反馈）
---@param text string
local function ShowToast(text)
    local toastLabel = UI.FindById("toast_text")
    if toastLabel then
        toastLabel:SetText(text)
        toastLabel:SetVisible(true)
    end
    toastTimer_ = 1.2
end

--- 安全设置 Label 字体颜色（兼容 SetFontColor 不存在的情况）
---@param label any
---@param color table
local function SafeSetLabelColor(label, color)
    if not label then return end
    if not label.SetFontColor then return end
    pcall(label.SetFontColor, label, color)
end

--- 获取车道名称
---@param lane integer
---@return string
local function GetLaneName(lane)
    if lane == 1 then return "左道"
    elseif lane == 2 then return "中道"
    else return "右道"
    end
end

--- 更新目标提示（距离 + 车道 + 颜色反馈）
---@param playerZ number
local function UpdateTargetHint(playerZ)
    local hintLabel = UI.FindById("target_hint")
    if not hintLabel then return end

    local text = ""
    local r, g, b, a = 255, 200, 60, 255  -- 默认橙黄色

    if carriedOrderCount_ <= 0 then
        -- 未携带订单，找取餐点
        if pickupActive_ then
            local dist = math.max(0, math.floor(pickupNode_.position.z - playerZ))
            text = string.format("目标：取餐点 %dm | %s", dist, GetLaneName(pickupLane_))
        else
            text = "目标：寻找取餐点"
        end
        -- 橙黄色
        r, g, b = 255, 200, 60
    else
        -- 携带订单，送餐
        if deliveryActive_ then
            local dist = math.max(0, math.floor(deliveryNode_.position.z - playerZ))
            local prefix = "目标"
            if carriedOrderCount_ >= maxCarryOrders_ then
                prefix = "满载"
                r, g, b = 255, 240, 0  -- 亮黄色
            else
                r, g, b = 144, 238, 144  -- 浅绿色
            end
            text = string.format("%s：送餐点 %dm | %s | %.1fs", prefix, dist, GetLaneName(deliveryLane_), deliveryTimer_)
        else
            text = string.format("目标：送餐点生成中 | %.1fs", deliveryTimer_)
            if carriedOrderCount_ >= maxCarryOrders_ then
                r, g, b = 255, 240, 0
            else
                r, g, b = 144, 238, 144
            end
        end
        -- 倒计时 <= 3s 时变红色
        if deliveryTimer_ <= 3.0 then
            r, g, b = 255, 60, 60
        end
    end

    hintLabel:SetText(text)
    SafeSetLabelColor(hintLabel, { r, g, b, a })
end

--- 检测玩家是否经过取餐点
local function CheckPickup(playerZ)
    if not pickupActive_ then return end

    -- 必须在同车道
    if CONFIG.currentLane ~= pickupLane_ then return end

    -- Z 轴距离判断
    local pickZ = pickupNode_.position.z
    if math.abs(playerZ - pickZ) < 1.0 then
        -- 取餐成功
        carriedOrderCount_ = math.min(carriedOrderCount_ + 1, maxCarryOrders_)
        orderState_ = "carrying"
        deliveryTimer_ = deliveryTimeLimit_  -- 每次取餐重置倒计时
        lowTimeWarningShown_ = false         -- 新倒计时，重置警告标记
        pickupActive_ = false
        pickupNode_.enabled = false
        pickupNode_.position = Vector3(0, -100, -100)

        -- 如果当前没有活跃送餐点，设置送餐点生成位置
        if not deliveryActive_ then
            if firstDeliveryInRun_ then
                nextDeliveryZ_ = playerZ + 38.0 + math.random() * 17.0  -- 首单：38~55m
                firstDeliveryInRun_ = false
            else
                nextDeliveryZ_ = playerZ + 42.0 + math.random() * 23.0  -- 常规：42~65m
            end
        end

        lastOrderPointSeenTime_ = runTime_

        -- 如果还没满载，安排下一个取餐点
        if carriedOrderCount_ < maxCarryOrders_ then
            nextPickupZ_ = playerZ + 32.0 + math.random() * 18.0
            ShowToast(string.format("取餐 +1，订单 %d/%d", carriedOrderCount_, maxCarryOrders_))
        else
            ShowToast("满载！先去送餐")
        end

        print(string.format("[取餐点] 取餐成功！订单 %d/%d，倒计时 %.1fs", carriedOrderCount_, maxCarryOrders_, deliveryTimer_))
    end
end

--- 回收已超过玩家的取餐点（玩家错过了）
local function RecyclePickupBehind(playerZ)
    if not pickupActive_ then return end

    local pickZ = pickupNode_.position.z
    if pickZ < playerZ - 5.0 then
        -- 玩家错过了，取餐点回收但不改变 orderState_
        -- 此处仍保持 orderState_ = "none"，等下一轮生成
        pickupActive_ = false
        pickupNode_.enabled = false
        pickupNode_.position = Vector3(0, -100, -100)
        -- 设置下一个取餐点位置（前方 32~50m）
        nextPickupZ_ = playerZ + 32.0 + math.random() * 18.0
        lastOrderPointSeenTime_ = runTime_
        ShowToast("错过取餐点")
        print(string.format("[取餐点] 已错过，下一个 Z=%.1f", nextPickupZ_))
    end
end

-- ============================================================================
-- 送餐点
-- ============================================================================

--- 创建送餐点节点（多部件可视强化，初始隐藏）
function CreateDeliveryPoint()
    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")
    local cylMdl = cache:GetResource("Model", "Models/Cylinder.mdl")

    deliveryNode_ = scene_:CreateChild("DeliveryPoint")
    deliveryNode_.position = Vector3(0, -100, -100)
    deliveryNode_.enabled = false

    -- 底座（蓝绿色大圆盘，贴地）
    local base = deliveryNode_:CreateChild("Base")
    base.position = Vector3(0, 0.08, 0)
    base.scale = Vector3(1.2, 0.16, 1.2)
    local baseModel = base:CreateComponent("StaticModel")
    baseModel:SetModel(cylMdl)
    baseModel:SetMaterial(mat_.deliveryBase)
    baseModel.castShadows = true

    -- 竖直标识柱
    local pillar = deliveryNode_:CreateChild("Pillar")
    pillar.position = Vector3(0, 0.9, 0)
    pillar.scale = Vector3(0.15, 1.6, 0.15)
    local pillarModel = pillar:CreateComponent("StaticModel")
    pillarModel:SetModel(cylMdl)
    pillarModel:SetMaterial(mat_.deliveryPillar)
    pillarModel.castShadows = true

    -- 浮动标志容器（会上下浮动 + 旋转）
    local floater = deliveryNode_:CreateChild("Floater")
    floater.position = Vector3(0, 2.0, 0)

    -- 小房子主体（绿色方块门牌造型）
    local house = floater:CreateChild("House")
    house.position = Vector3(0, 0, 0)
    house.scale = Vector3(0.6, 0.7, 0.45)
    local houseModel = house:CreateComponent("StaticModel")
    houseModel:SetModel(boxMdl)
    houseModel:SetMaterial(mat_.deliveryTop)
    houseModel.castShadows = true

    -- 屋顶（扁方块，模拟三角顶）
    local roof = floater:CreateChild("Roof")
    roof.position = Vector3(0, 0.5, 0)
    roof.scale = Vector3(0.7, 0.25, 0.55)
    roof.rotation = Quaternion(45, Vector3.FORWARD)
    local roofModel = roof:CreateComponent("StaticModel")
    roofModel:SetModel(boxMdl)
    roofModel:SetMaterial(mat_.deliveryBase)
    roofModel.castShadows = true

    print("[送餐点] 多部件节点已创建（底座+柱子+浮动标志）")
end

--- 检查某个 z 位置是否与已有障碍物冲突（同车道距离 < 4m）
---@param lane number
---@param z number
---@return boolean
local function IsDeliveryConflictWithObstacles(lane, z)
    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if obs.active and obs.lane == lane then
            if math.abs(obs.node.position.z - z) < 5.0 then
                return true
            end
        end
    end
    return false
end

--- 尝试生成送餐点
local function TrySpawnDelivery(playerZ)
    -- 仅在有订单且当前无活跃送餐点时生成
    if carriedOrderCount_ <= 0 or deliveryActive_ then return end

    -- 只在玩家接近 nextDeliveryZ_ 时生成（提前 80m 内）
    if nextDeliveryZ_ > playerZ + 80.0 then return end

    -- 随机选车道
    local lane = math.random(1, 3)
    local spawnZ = nextDeliveryZ_

    -- 避免与障碍物重叠及目标点互近：最多尝试 6 次，每次前推 5m
    for _ = 1, 6 do
        if not IsDeliveryConflictWithObstacles(lane, spawnZ) and not IsOrderPointTooClose(lane, spawnZ) then
            break
        end
        spawnZ = spawnZ + 5.0
    end

    -- 激活送餐点
    deliveryLane_ = lane
    deliveryActive_ = true
    local laneX = CONFIG.LANE_X[lane] or 0.0
    deliveryNode_.position = Vector3(laneX, 0, spawnZ)
    deliveryNode_.enabled = true

    lastOrderPointSeenTime_ = runTime_
    print(string.format("[送餐点] 生成: 车道=%d, Z=%.1f", lane, spawnZ))
end

--- 检测玩家是否经过送餐点（送达）
local function CheckDelivery(playerZ)
    if not deliveryActive_ then return end

    -- 必须在同车道
    if CONFIG.currentLane ~= deliveryLane_ then return end

    -- Z 轴距离判断
    local delZ = deliveryNode_.position.z
    if math.abs(playerZ - delZ) < 1.0 then
        -- 送达成功：先更新连送计数，再计算奖励
        comboCount_ = comboCount_ + 1
        if comboCount_ > maxComboCount_ then
            maxComboCount_ = comboCount_
        end
        local reward = GetComboReward(comboCount_)
        currentIncome_ = currentIncome_ + reward
        deliveredOrderCount_ = deliveredOrderCount_ + 1
        carriedOrderCount_ = math.max(carriedOrderCount_ - 1, 0)
        deliveryActive_ = false
        deliveryNode_.enabled = false
        deliveryNode_.position = Vector3(0, -100, -100)

        if carriedOrderCount_ > 0 then
            -- 还有剩余订单，继续送餐中
            orderState_ = "carrying"
            deliveryTimer_ = deliveryTimeLimit_  -- 送达后重置倒计时
            lowTimeWarningShown_ = false         -- 新倒计时，重置警告标记
            nextDeliveryZ_ = playerZ + 42.0 + math.random() * 23.0
            -- 允许继续生成取餐点
            if carriedOrderCount_ < maxCarryOrders_ and not pickupActive_ then
                nextPickupZ_ = playerZ + 32.0 + math.random() * 18.0
            end
            boostTimer_ = boostDuration_
            lastOrderPointSeenTime_ = runTime_
            ShowToast(string.format("送达 +¥%d，连送 %d，剩余 %d/%d，加速！", reward, comboCount_, carriedOrderCount_, maxCarryOrders_))
            print(string.format("[送餐点] 送达成功！连送 %d，奖励 +%d，累计 ¥%d，剩余 %d/%d", comboCount_, reward, currentIncome_, carriedOrderCount_, maxCarryOrders_))
        else
            -- 全部送完，回到未取餐
            orderState_ = "none"
            deliveryTimer_ = 0.0
            nextPickupZ_ = playerZ + 32.0 + math.random() * 18.0
            boostTimer_ = boostDuration_
            lastOrderPointSeenTime_ = runTime_
            ShowToast(string.format("全部送完 +¥%d，连送 %d，加速！", reward, comboCount_))
            print(string.format("[送餐点] 送达成功！连送 %d，奖励 +%d，累计 ¥%d，全部送完", comboCount_, reward, currentIncome_))
        end
    end
end

--- 回收已超过玩家的送餐点（玩家错过了）
local function RecycleDeliveryBehind(playerZ)
    if not deliveryActive_ then return end

    local delZ = deliveryNode_.position.z
    if delZ < playerZ - 5.0 then
        -- 玩家错过了，送餐点回收，重新在前方生成
        deliveryActive_ = false
        deliveryNode_.enabled = false
        deliveryNode_.position = Vector3(0, -100, -100)
        -- 在前方重新安排送餐点（前方 42~65m）
        nextDeliveryZ_ = playerZ + 42.0 + math.random() * 23.0
        lastOrderPointSeenTime_ = runTime_
        ShowToast("错过送餐点，前方重新导航")
        print(string.format("[送餐点] 已错过，下一个 Z=%.1f", nextDeliveryZ_))
    end
end

-- ============================================================================
-- 碰撞检测（返回失败原因字符串，nil 表示未碰撞）
-- ============================================================================

---@param playerZ number
---@return string|nil 失败原因
local function CheckCollision(playerZ)
    local playerLane = CONFIG.currentLane

    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if obs.active and obs.lane == playerLane then
            local obsZ = obs.node.position.z
            local zDist = math.abs(playerZ - obsZ)

            if zDist < CONFIG.COLLISION_Z_THRESHOLD then
                if obs.type == "block" then
                    return "撞上路障"
                elseif obs.type == "low" then
                    if actionState_ ~= "jump" then
                        return "没有跳过低矮障碍"
                    end
                elseif obs.type == "high" then
                    if actionState_ ~= "slide" then
                        return "没有下滑躲过高位障碍"
                    end
                end
            end
        end
    end

    return nil
end

-- ============================================================================
-- 速度系统
-- ============================================================================

--- 根据距离计算当前速度（平滑递增）
local function UpdateSpeed()
    -- 每跑 SPEED_DISTANCE_FACTOR 米增加 1 点速度，上限 MAX_SPEED
    local baseSpeed = math.min(
        CONFIG.MAX_SPEED,
        CONFIG.BASE_SPEED + distanceTraveled_ / CONFIG.SPEED_DISTANCE_FACTOR
    )
    if boostTimer_ > 0 then
        currentSpeed_ = math.min(CONFIG.MAX_SPEED + boostSpeedBonus_, baseSpeed + boostSpeedBonus_)
    else
        currentSpeed_ = baseSpeed
    end
end

-- ============================================================================
-- 游戏状态管理
-- ============================================================================

--- 触发游戏结束
---@param reason string 失败原因
local function GetFailureTip(reason)
    if reason == "撞上路障" then
        return "左右变道避开红色路障"
    elseif reason == "没有跳过低矮障碍" then
        return "上滑或空格跳过低矮障碍"
    elseif reason == "没有下滑躲过高位障碍" then
        return "下滑或 S 键躲过高位障碍"
    elseif reason == "送餐超时" then
        return "优先看目标提示，满载时先送餐"
    else
        return "观察前方目标，保持节奏"
    end
end

local function TriggerGameOver(reason)
    gameState_ = "gameOver"

    -- 更新最高距离
    local dist = math.floor(distanceTraveled_)
    if dist > bestDistance_ then
        bestDistance_ = dist
    end

    print(string.format("[游戏结束] 原因: %s, 距离: %d m, 时间: %.1f s", reason, dist, runTime_))

    -- 更新游戏结束面板
    if gameOverPanel_ then
        gameOverPanel_:SetVisible(true)

        local reasonLabel = UI.FindById("go_reason")
        if reasonLabel then
            reasonLabel:SetText(reason)
        end

        local scoreLabel = UI.FindById("go_score")
        if scoreLabel then
            scoreLabel:SetText(string.format("本次距离: %d 米", dist))
        end

        local bestLabel = UI.FindById("go_best")
        if bestLabel then
            bestLabel:SetText(string.format("最高距离: %d 米", bestDistance_))
        end

        local timeLabel = UI.FindById("go_time")
        if timeLabel then
            local minutes = math.floor(runTime_ / 60)
            local seconds = math.floor(runTime_ % 60)
            timeLabel:SetText(string.format("持续时间: %d:%02d", minutes, seconds))
        end

        local incomeLabel = UI.FindById("go_income")
        if incomeLabel then
            incomeLabel:SetText(string.format("本局收入: ¥%d", currentIncome_))
        end

        local deliveredLabel = UI.FindById("go_delivered")
        if deliveredLabel then
            deliveredLabel:SetText(string.format("送达订单: %d 单", deliveredOrderCount_))
        end

        local comboLabel = UI.FindById("go_combo")
        if comboLabel then
            comboLabel:SetText(string.format("最高连送: %d", maxComboCount_))
        end

        -- 评价文案
        local rankLabel = UI.FindById("go_rank_text")
        if rankLabel then
            local rankText
            if deliveredOrderCount_ == 0 then
                rankText = "还没送到，下一单冲！"
            elseif deliveredOrderCount_ < 5 then
                rankText = "跑腿新人，上手了！"
            else
                rankText = "金牌骑手，继续冲！"
            end
            rankLabel:SetText(rankText)
        end

        -- 失败建议
        local tipLabel = UI.FindById("go_tip")
        if tipLabel then
            tipLabel:SetText("提示：" .. GetFailureTip(reason))
        end
    end

    -- 失败 Toast
    ShowToast(GetFailureTip(reason))
end

--- 重置游戏（再来一局）
local function RestartGame()
    print("[重启] 再来一局")

    -- 重置游戏状态
    gameState_ = "running"
    distanceTraveled_ = 0.0
    currentSpeed_ = CONFIG.BASE_SPEED
    runTime_ = 0.0

    -- 重置玩家状态
    CONFIG.currentLane = 2
    actionState_ = "run"
    actionTimer_ = 0.0
    laneChangeTimer_ = 0.0
    touchStartX_ = nil
    touchStartY_ = nil
    touchConsumed_ = false

    -- 重置玩家位置
    playerNode_.position = Vector3(CONFIG.LANE_X[2], 0, 5.0)

    -- 回收所有障碍物
    for i = 1, #obstacles_ do
        if obstacles_[i].active then
            DeactivateObstacle(obstacles_[i])
        end
    end
    nextObstacleZ_ = 35.0  -- 玩家起始 Z=5, 第一个障碍物在前方 30m

    -- 重置取餐点状态
    orderState_ = "none"
    pickupActive_ = false
    pickupLane_ = 0
    nextPickupZ_ = 35.0  -- 玩家起始 Z=5, 取餐点在前方约 30m
    if pickupNode_ then
        pickupNode_.enabled = false
        pickupNode_.position = Vector3(0, -100, -100)
    end

    -- 重置送餐点状态
    deliveryActive_ = false
    deliveryLane_ = 0
    nextDeliveryZ_ = 0.0
    deliveryTimer_ = 0.0
    currentIncome_ = 0
    carriedOrderCount_ = 0
    deliveredOrderCount_ = 0
    toastTimer_ = 0.0
    comboCount_ = 0
    maxComboCount_ = 0
    lowTimeWarningShown_ = false
    boostTimer_ = 0.0
    firstDeliveryInRun_ = true
    lastOrderPointSeenTime_ = 0.0
    highPressureToastShown_ = false
    jumpBufferTimer_ = 0.0
    slideBufferTimer_ = 0.0
    if deliveryNode_ then
        deliveryNode_.enabled = false
        deliveryNode_.position = Vector3(0, -100, -100)
    end

    -- 重置道路池
    local segLen = CONFIG.ROAD_SEGMENT_LENGTH
    for i = 1, #roadSegments_ do
        local zCenter = (i - 1) * segLen + segLen / 2
        MoveRoadSegment(roadSegments_[i], zCenter)
    end
    nextSegmentZ_ = CONFIG.ROAD_SEGMENTS * segLen

    -- 重置车道线
    local spacing = CONFIG.LINE_SPACING
    for i = 1, #laneLines_ do
        local z = (i - 1) * spacing + CONFIG.LINE_LENGTH / 2
        laneLines_[i].lineL.position = Vector3(-1.0, 0.01, z)
        laneLines_[i].lineR.position = Vector3(1.0, 0.01, z)
    end
    nextLineZ_ = CONFIG.LINE_POOL_SIZE * spacing + CONFIG.LINE_LENGTH / 2

    -- 重置建筑
    math.randomseed(42)
    local totalVisibleLength = CONFIG.ROAD_SEGMENTS * CONFIG.ROAD_SEGMENT_LENGTH
    local bSpacing = totalVisibleLength / CONFIG.BUILDING_POOL_SIZE
    for i = 1, #buildings_ do
        local z = (i - 1) * bSpacing + math.random() * bSpacing
        PlaceBuilding(buildings_[i], z)
    end
    nextBuildingZ_ = totalVisibleLength

    -- 隐藏游戏结束面板
    if gameOverPanel_ then
        gameOverPanel_:SetVisible(false)
    end

    -- 隐藏 Toast
    local toastLabel = UI.FindById("toast_text")
    if toastLabel then
        toastLabel:SetVisible(false)
    end

    -- 更新摄像机
    UpdateCameraPosition()

    -- 重开提示
    ShowToast("继续冲！")
end

-- ============================================================================
-- 玩家角色
-- ============================================================================

function CreatePlayer()
    playerNode_ = scene_:CreateChild("Player")
    local laneX = CONFIG.LANE_X[CONFIG.currentLane]
    playerNode_.position = Vector3(laneX, 0, 5.0)

    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")
    local cylMdl = cache:GetResource("Model", "Models/Cylinder.mdl")
    local sphMdl = cache:GetResource("Model", "Models/Sphere.mdl")

    local bodyNode = playerNode_:CreateChild("Body")
    bodyNode.position = Vector3(0, 0.7, 0)
    bodyNode.scale = Vector3(0.5, 1.2, 0.4)
    local bodyModel = bodyNode:CreateComponent("StaticModel")
    bodyModel:SetModel(cylMdl)
    bodyModel:SetMaterial(CreatePBRMaterial(Color(0.2, 0.45, 0.8, 1.0), 0.0, 0.6))
    bodyModel.castShadows = true

    local headNode = playerNode_:CreateChild("Head")
    headNode.position = Vector3(0, 1.5, 0)
    headNode.scale = Vector3(0.4, 0.4, 0.4)
    local headModel = headNode:CreateComponent("StaticModel")
    headModel:SetModel(sphMdl)
    headModel:SetMaterial(CreatePBRMaterial(Color(0.95, 0.82, 0.70, 1.0), 0.0, 0.5))
    headModel.castShadows = true

    local dboxNode = playerNode_:CreateChild("DeliveryBox")
    dboxNode.position = Vector3(0, 1.0, -0.35)
    dboxNode.scale = Vector3(0.5, 0.5, 0.3)
    local dboxModel = dboxNode:CreateComponent("StaticModel")
    dboxModel:SetModel(boxMdl)
    dboxModel:SetMaterial(CreatePBRMaterial(Color(1.0, 0.75, 0.1, 1.0), 0.0, 0.5))
    dboxModel.castShadows = true

    local hatNode = playerNode_:CreateChild("Hat")
    hatNode.position = Vector3(0, 1.75, 0)
    hatNode.scale = Vector3(0.35, 0.12, 0.35)
    local hatModel = hatNode:CreateComponent("StaticModel")
    hatModel:SetModel(cylMdl)
    hatModel:SetMaterial(CreatePBRMaterial(Color(1.0, 0.8, 0.15, 1.0), 0.0, 0.5))
    hatModel.castShadows = true
end

-- ============================================================================
-- 摄像机
-- ============================================================================

function SetupCamera()
    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.nearClip = 0.1
    camera.farClip = 300.0
    camera.fov = 60.0

    renderer:SetViewport(0, Viewport:new(scene_, camera))
    renderer.hdrRendering = true
    UpdateCameraPosition()
end

function UpdateCameraPosition()
    if playerNode_ == nil or cameraNode_ == nil then return end
    local pp = playerNode_.position
    cameraNode_.position = Vector3(0, pp.y + CONFIG.CAM_OFFSET_Y, pp.z + CONFIG.CAM_OFFSET_Z)
    local lookTarget = Vector3(0, pp.y + 0.5, pp.z + CONFIG.CAM_LOOK_AHEAD)
    cameraNode_:LookAt(lookTarget)
end

-- ============================================================================
-- UI
-- ============================================================================

function CreateUI()
    -- 游戏结束面板
    gameOverPanel_ = UI.Panel {
        id = "gameOverPanel",
        visible = false,
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        children = {
            UI.Panel {
                width = 280,
                paddingTop = 28,
                paddingBottom = 28,
                paddingLeft = 24,
                paddingRight = 24,
                borderRadius = 16,
                backgroundColor = { 255, 255, 255, 240 },
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "游戏结束",
                        fontSize = 26,
                        fontWeight = "bold",
                        fontColor = { 50, 50, 50, 255 },
                    },
                    UI.Label {
                        id = "go_reason",
                        text = "",
                        fontSize = 14,
                        fontColor = { 200, 60, 60, 255 },
                        marginTop = 8,
                    },
                    UI.Panel {
                        width = "100%",
                        height = 1,
                        backgroundColor = { 220, 220, 220, 255 },
                        marginTop = 14,
                        marginBottom = 14,
                    },
                    UI.Label {
                        id = "go_score",
                        text = "本次距离: 0 米",
                        fontSize = 15,
                        fontColor = { 80, 80, 80, 255 },
                    },
                    UI.Label {
                        id = "go_best",
                        text = "最高距离: 0 米",
                        fontSize = 15,
                        fontColor = { 80, 80, 80, 255 },
                        marginTop = 6,
                    },
                    UI.Label {
                        id = "go_time",
                        text = "持续时间: 0:00",
                        fontSize = 15,
                        fontColor = { 80, 80, 80, 255 },
                        marginTop = 6,
                    },
                    UI.Label {
                        id = "go_income",
                        text = "本局收入: ¥0",
                        fontSize = 15,
                        fontColor = { 34, 139, 34, 255 },
                        marginTop = 6,
                    },
                    UI.Label {
                        id = "go_delivered",
                        text = "送达订单: 0 单",
                        fontSize = 15,
                        fontColor = { 255, 165, 0, 255 },
                        marginTop = 4,
                    },
                    UI.Label {
                        id = "go_combo",
                        text = "最高连送: 0",
                        fontSize = 15,
                        fontColor = { 255, 100, 50, 255 },
                        marginTop = 4,
                    },
                    UI.Label {
                        id = "go_rank_text",
                        text = "",
                        fontSize = 16,
                        fontColor = { 80, 200, 120, 255 },
                        marginTop = 8,
                    },
                    UI.Label {
                        id = "go_tip",
                        text = "",
                        fontSize = 13,
                        fontColor = { 60, 120, 200, 255 },
                        marginTop = 10,
                    },
                    UI.Button {
                        text = "再来一局 (空格/R)",
                        variant = "primary",
                        marginTop = 22,
                        width = 160,
                        height = 46,
                        onClick = function()
                            RestartGame()
                        end,
                    },
                },
            },
        },
    }

    local uiRoot = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Label {
                id = "title",
                text = "外卖冲冲冲",
                fontSize = 22,
                fontColor = { 255, 255, 255, 230 },
                position = "absolute",
                top = 20,
                left = 0, right = 0,
                textAlign = "center",
            },
            -- HUD: 主状态行
            UI.Label {
                id = "hud_info",
                text = "0 m | 8.0 m/s | 订单 0/2 | ¥0 | 连送 0 | 已送 0",
                fontSize = 14,
                fontColor = { 255, 255, 200, 210 },
                position = "absolute",
                top = 50,
                left = 0, right = 0,
                textAlign = "center",
            },
            -- 目标提示行
            UI.Label {
                id = "target_hint",
                text = "目标：寻找取餐点",
                fontSize = 15,
                fontColor = { 255, 200, 60, 255 },
                position = "absolute",
                top = 72,
                left = 0, right = 0,
                textAlign = "center",
            },
            -- Toast 提示（短暂显示）
            UI.Label {
                id = "toast_text",
                text = "",
                fontSize = 16,
                fontColor = { 255, 220, 50, 255 },
                position = "absolute",
                top = 96,
                left = 0, right = 0,
                textAlign = "center",
                visible = false,
            },
            gameOverPanel_,
        },
    }
    UI.SetRoot(uiRoot)
end

-- ============================================================================
-- 循环回收
-- ============================================================================

local function RecycleRoadSegments(playerZ)
    local segLen = CONFIG.ROAD_SEGMENT_LENGTH
    local recycleThreshold = playerZ - segLen

    for i = 1, #roadSegments_ do
        local seg = roadSegments_[i]
        if seg.road.position.z < recycleThreshold then
            local newZ = nextSegmentZ_ + segLen / 2
            MoveRoadSegment(seg, newZ)
            nextSegmentZ_ = nextSegmentZ_ + segLen
        end
    end
end

local function RecycleLaneLines(playerZ)
    local spacing = CONFIG.LINE_SPACING
    local recycleThreshold = playerZ - spacing * 2

    for i = 1, #laneLines_ do
        local pair = laneLines_[i]
        if pair.lineL.position.z < recycleThreshold then
            pair.lineL.position = Vector3(-1.0, 0.01, nextLineZ_)
            pair.lineR.position = Vector3(1.0, 0.01, nextLineZ_)
            nextLineZ_ = nextLineZ_ + spacing
        end
    end
end

local function RecycleBuildings(playerZ)
    local recycleThreshold = playerZ - 20.0
    local spacing = (CONFIG.ROAD_SEGMENTS * CONFIG.ROAD_SEGMENT_LENGTH) / CONFIG.BUILDING_POOL_SIZE

    for i = 1, #buildings_ do
        local node = buildings_[i]
        if node.position.z < recycleThreshold then
            local newZ = nextBuildingZ_ + math.random() * spacing
            PlaceBuilding(node, newZ)
            nextBuildingZ_ = nextBuildingZ_ + spacing
        end
    end
end

-- ============================================================================
-- 变道逻辑
-- ============================================================================

local function IsChangingLane()
    return laneChangeTimer_ > 0.0
end

local function TryChangeLane(direction)
    if IsChangingLane() then return end
    local newLane = CONFIG.currentLane + direction
    if newLane < 1 or newLane > 3 then return end

    laneChangeFromX_ = CONFIG.LANE_X[CONFIG.currentLane]
    laneChangeToX_ = CONFIG.LANE_X[newLane]
    CONFIG.currentLane = newLane
    laneChangeTimer_ = LANE_CHANGE_DURATION
end

local function UpdateLaneChange(dt)
    if laneChangeTimer_ <= 0.0 then return end

    laneChangeTimer_ = laneChangeTimer_ - dt
    if laneChangeTimer_ <= 0.0 then
        laneChangeTimer_ = 0.0
        local pos = playerNode_.position
        playerNode_.position = Vector3(laneChangeToX_, pos.y, pos.z)
    else
        local progress = 1.0 - (laneChangeTimer_ / LANE_CHANGE_DURATION)
        local t = progress * progress * (3.0 - 2.0 * progress)
        local currentX = laneChangeFromX_ + (laneChangeToX_ - laneChangeFromX_) * t
        local pos = playerNode_.position
        playerNode_.position = Vector3(currentX, pos.y, pos.z)
    end
end

-- ============================================================================
-- 跳跃与下滑
-- ============================================================================

local function CanDoAction()
    return actionState_ == "run"
end

local function TryJump()
    if not CanDoAction() then
        -- 动作中，缓存输入
        jumpBufferTimer_ = inputBufferDuration_
        return
    end
    actionState_ = "jump"
    actionTimer_ = 0.0
    jumpBufferTimer_ = 0.0
    slideBufferTimer_ = 0.0
end

local function TrySlide()
    if not CanDoAction() then
        -- 动作中，缓存输入
        slideBufferTimer_ = inputBufferDuration_
        return
    end
    actionState_ = "slide"
    actionTimer_ = 0.0
    jumpBufferTimer_ = 0.0
    slideBufferTimer_ = 0.0
end

local function UpdateAction(dt)
    -- 递减输入缓冲计时器
    if jumpBufferTimer_ > 0 then
        jumpBufferTimer_ = jumpBufferTimer_ - dt
    end
    if slideBufferTimer_ > 0 then
        slideBufferTimer_ = slideBufferTimer_ - dt
    end

    if actionState_ == "jump" then
        actionTimer_ = actionTimer_ + dt
        if actionTimer_ >= JUMP_DURATION then
            actionState_ = "run"
            actionTimer_ = 0.0
        end
    elseif actionState_ == "slide" then
        actionTimer_ = actionTimer_ + dt
        if actionTimer_ >= SLIDE_DURATION then
            actionState_ = "run"
            actionTimer_ = 0.0
        end
    end

    -- 动作刚结束回到 run，消费缓冲（跳跃优先级 > 滑铲）
    if actionState_ == "run" then
        if jumpBufferTimer_ > 0 then
            actionState_ = "jump"
            actionTimer_ = 0.0
            jumpBufferTimer_ = 0.0
            slideBufferTimer_ = 0.0
        elseif slideBufferTimer_ > 0 then
            actionState_ = "slide"
            actionTimer_ = 0.0
            jumpBufferTimer_ = 0.0
            slideBufferTimer_ = 0.0
        end
    end
end

local function GetJumpY()
    if actionState_ ~= "jump" then return 0.0 end
    local progress = actionTimer_ / JUMP_DURATION
    return math.sin(progress * math.pi) * JUMP_HEIGHT
end

-- ============================================================================
-- 输入系统
-- ============================================================================

local function HandleTouchInput()
    local numTouches = input.numTouches
    if numTouches > 0 then
        local touch = input:GetTouch(0)
        if touchStartX_ == nil then
            touchStartX_ = touch.position.x
            touchStartY_ = touch.position.y
            touchId_ = touch.touchID
            touchConsumed_ = false
        elseif not touchConsumed_ then
            local deltaX = touch.position.x - touchStartX_
            local deltaY = touch.position.y - touchStartY_
            local absDX = math.abs(deltaX)
            local absDY = math.abs(deltaY)

            if absDX > SWIPE_THRESHOLD or absDY > SWIPE_THRESHOLD then
                if absDX > absDY then
                    TryChangeLane(deltaX > 0 and 1 or -1)
                else
                    if deltaY < 0 then TryJump() else TrySlide() end
                end
                touchConsumed_ = true
            end
        end
    else
        touchStartX_ = nil
        touchStartY_ = nil
        touchId_ = -1
        touchConsumed_ = false
    end
end

local function HandleKeyboardInput()
    if input:GetKeyPress(KEY_A) or input:GetKeyPress(KEY_LEFT) then
        TryChangeLane(-1)
    elseif input:GetKeyPress(KEY_D) or input:GetKeyPress(KEY_RIGHT) then
        TryChangeLane(1)
    end

    if input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) then
        TryJump()
    end

    if input:GetKeyPress(KEY_S) or input:GetKeyPress(KEY_DOWN) then
        TrySlide()
    end
end

-- ============================================================================
-- 游戏更新
-- ============================================================================

local runTimer_ = 0.0
local uiTimer_ = 0.0

local function UpdatePlayerPose(dt)
    local bodyNode = playerNode_:GetChild("Body")
    local headNode = playerNode_:GetChild("Head")
    local hatNode = playerNode_:GetChild("Hat")
    local dboxNode = playerNode_:GetChild("DeliveryBox")

    if actionState_ == "run" then
        runTimer_ = runTimer_ + dt * 10.0
        local bobY = math.abs(math.sin(runTimer_)) * 0.08

        if bodyNode then
            bodyNode.position = Vector3(0, 0.7 + bobY, 0)
            bodyNode.scale = Vector3(0.5, 1.2, 0.4)
            bodyNode.rotation = Quaternion.IDENTITY
        end
        if headNode then headNode.position = Vector3(0, 1.5 + bobY, 0); headNode.scale = Vector3(0.4, 0.4, 0.4) end
        if hatNode then hatNode.position = Vector3(0, 1.75 + bobY, 0) end
        if dboxNode then
            local swing = math.sin(runTimer_ * 0.7) * 2.0
            dboxNode.rotation = Quaternion(swing, Vector3.FORWARD)
            dboxNode.position = Vector3(0, 1.0, -0.35)
        end

    elseif actionState_ == "jump" then
        runTimer_ = runTimer_ + dt * 12.0
        if bodyNode then
            bodyNode.position = Vector3(0, 0.7, 0)
            bodyNode.scale = Vector3(0.5, 1.2, 0.4)
            bodyNode.rotation = Quaternion.IDENTITY
        end
        if headNode then headNode.position = Vector3(0, 1.5, 0); headNode.scale = Vector3(0.4, 0.4, 0.4) end
        if hatNode then hatNode.position = Vector3(0, 1.75, 0) end
        if dboxNode then dboxNode.rotation = Quaternion.IDENTITY; dboxNode.position = Vector3(0, 1.0, -0.35) end

    elseif actionState_ == "slide" then
        local progress = actionTimer_ / SLIDE_DURATION
        local slideAmount = progress < 0.8 and 1.0 or (1.0 - ((progress - 0.8) / 0.2))

        if bodyNode then
            local bodyHeight = 1.2 - 0.7 * slideAmount
            local bodyY = 0.3 + (0.7 - 0.3) * (1.0 - slideAmount)
            bodyNode.position = Vector3(0, bodyY, 0)
            bodyNode.scale = Vector3(0.5 + 0.2 * slideAmount, bodyHeight, 0.4 + 0.2 * slideAmount)
            bodyNode.rotation = Quaternion(25 * slideAmount, Vector3.RIGHT)
        end
        if headNode then
            headNode.position = Vector3(0, 1.5 - 0.9 * slideAmount, 0.15 * slideAmount)
            headNode.scale = Vector3(0.4, 0.4, 0.4)
        end
        if hatNode then hatNode.position = Vector3(0, 1.75 - 1.0 * slideAmount, 0.15 * slideAmount) end
        if dboxNode then
            dboxNode.rotation = Quaternion(-15 * slideAmount, Vector3.RIGHT)
            dboxNode.position = Vector3(0, 1.0 - 0.5 * slideAmount, -0.35 - 0.1 * slideAmount)
        end
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if playerNode_ == nil then return end

    if gameState_ == "gameOver" then
        -- 快捷重开：空格键或 R 键
        if input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_R) then
            RestartGame()
        end
        return
    end

    -- 开局提示（第一帧触发）
    if startToastPending_ then
        startToastPending_ = false
        ShowToast("左右滑动变道，上滑跳跃，下滑躲避")
    end

    -- 输入
    HandleTouchInput()
    HandleKeyboardInput()

    -- 更新动作状态
    UpdateAction(dt)
    UpdateLaneChange(dt)

    -- 更新加速计时
    if boostTimer_ > 0 then
        boostTimer_ = math.max(0, boostTimer_ - dt)
    end

    -- 更新速度（基于距离平滑递增）
    UpdateSpeed()

    -- 更新运行时间
    runTime_ = runTime_ + dt

    -- 跳跃偏移
    local jumpY = GetJumpY()

    -- 玩家自动向前跑（使用 currentSpeed_）
    local currentPos = playerNode_.position
    local newZ = currentPos.z + currentSpeed_ * dt
    playerNode_.position = Vector3(currentPos.x, jumpY, newZ)

    -- 更新距离
    distanceTraveled_ = distanceTraveled_ + currentSpeed_ * dt

    -- 高压期首次进入提示
    if not highPressureToastShown_ and GetDifficultyPhase() == 3 then
        highPressureToastShown_ = true
        ShowToast("高压路段！")
        print("[难度] 进入高压期，距离=" .. math.floor(distanceTraveled_))
    end

    -- 角色姿态
    UpdatePlayerPose(dt)

    -- 障碍物
    SpawnObstacles(newZ)
    RecycleObstacles(newZ)

    -- 碰撞检测（返回失败原因）
    local failReason = CheckCollision(newZ)
    if failReason then
        TriggerGameOver(failReason)
        return
    end

    -- 送餐倒计时（只在 carrying 状态递减）
    if orderState_ == "carrying" then
        deliveryTimer_ = deliveryTimer_ - dt
        if deliveryTimer_ <= 0 then
            deliveryTimer_ = 0
            TriggerGameOver("送餐超时")
            return
        end
        -- 快超时警告（每轮倒计时只触发一次）
        if deliveryTimer_ <= 3.0 and not lowTimeWarningShown_ then
            ShowToast("快超时了！")
            lowTimeWarningShown_ = true
        end
    end

    -- 循环回收
    RecycleRoadSegments(newZ)
    RecycleLaneLines(newZ)
    RecycleBuildings(newZ)

    -- 摄像机
    UpdateCameraPosition()

    -- 取餐点逻辑
    TrySpawnPickup(newZ)
    CheckPickup(newZ)
    RecyclePickupBehind(newZ)

    -- 送餐点逻辑
    TrySpawnDelivery(newZ)
    CheckDelivery(newZ)
    RecycleDeliveryBehind(newZ)

    -- 首分钟节奏保底：超过 8 秒没有订单事件时，强制缩短下一个触发距离
    if runTime_ < 60.0 and (runTime_ - lastOrderPointSeenTime_) > 8.0 then
        if carriedOrderCount_ <= 0 and not pickupActive_ then
            -- 没有携带订单且没有活跃取餐点 → 强制缩短取餐点距离
            local forcedZ = newZ + 32.0 + math.random() * 13.0  -- 32~45m
            if nextPickupZ_ > forcedZ then
                nextPickupZ_ = forcedZ
                print(string.format("[节奏保底] 空窗 %.1fs，取餐点提前到 Z=%.1f", runTime_ - lastOrderPointSeenTime_, forcedZ))
            end
            lastOrderPointSeenTime_ = runTime_  -- 重置，避免每帧触发
        elseif carriedOrderCount_ > 0 and not deliveryActive_ then
            -- 有订单但没有活跃送餐点 → 强制缩短送餐点距离
            local forcedZ = newZ + 38.0 + math.random() * 17.0  -- 38~55m
            if nextDeliveryZ_ > forcedZ then
                nextDeliveryZ_ = forcedZ
                print(string.format("[节奏保底] 空窗 %.1fs，送餐点提前到 Z=%.1f", runTime_ - lastOrderPointSeenTime_, forcedZ))
            end
            lastOrderPointSeenTime_ = runTime_  -- 重置，避免每帧触发
        end
    end

    -- 取餐点/送餐点可视强化动画（浮动 + 旋转 + 近距离加速）
    if pickupActive_ and pickupNode_ then
        local pickDist = pickupNode_.position.z - newZ
        local isNear = pickDist < 12.0 and pickDist > 0
        -- 旋转速度：近距离时加快
        local rotSpeed = isNear and 180.0 or 90.0
        pickupNode_.rotation = Quaternion(runTime_ * rotSpeed, Vector3.UP)
        -- 浮动标志上下浮动
        local floater = pickupNode_:GetChild("Floater")
        if floater then
            local floatFreq = isNear and 6.0 or 3.0
            local floatAmp = isNear and 0.3 or 0.18
            floater.position = Vector3(0, 2.0 + math.sin(runTime_ * floatFreq) * floatAmp, 0)
        end
    end
    if deliveryActive_ and deliveryNode_ then
        local delDist = deliveryNode_.position.z - newZ
        local isNear = delDist < 12.0 and delDist > 0
        local rotSpeed = isNear and 150.0 or 60.0
        deliveryNode_.rotation = Quaternion(runTime_ * rotSpeed, Vector3.UP)
        local floater = deliveryNode_:GetChild("Floater")
        if floater then
            local floatFreq = isNear and 5.0 or 2.5
            local floatAmp = isNear and 0.28 or 0.15
            floater.position = Vector3(0, 2.0 + math.sin(runTime_ * floatFreq) * floatAmp, 0)
        end
    end

    -- Toast 提示递减
    if toastTimer_ > 0 then
        toastTimer_ = toastTimer_ - dt
        if toastTimer_ <= 0 then
            toastTimer_ = 0
            local toastLabel = UI.FindById("toast_text")
            if toastLabel then
                toastLabel:SetVisible(false)
            end
        end
    end

    -- HUD 更新（节流 4Hz）
    uiTimer_ = uiTimer_ + dt
    if uiTimer_ >= 0.25 then
        uiTimer_ = uiTimer_ - 0.25
        local hudLabel = UI.FindById("hud_info")
        if hudLabel then
            local speedTag = string.format("%.1f m/s", currentSpeed_)
            if boostTimer_ > 0 then
                speedTag = speedTag .. " 加速"
            end
            local orderTag = string.format("订单 %d/%d", carriedOrderCount_, maxCarryOrders_)
            if orderState_ == "carrying" and deliveryTimer_ <= 3.0 then
                orderTag = orderTag .. " 紧急"
            end
            local phaseNames = { "热身", "冲刺", "高压" }
            local phaseTag = phaseNames[GetDifficultyPhase()] or ""
            hudLabel:SetText(string.format("%d m | %s | %s | ¥%d | 连送 %d | 已送 %d | %s",
                math.floor(distanceTraveled_), speedTag, orderTag, currentIncome_, comboCount_, deliveredOrderCount_, phaseTag))
        end
        UpdateTargetHint(newZ)
    end
end
