-- ============================================================================
-- 外卖冲冲冲 - 阶段 1.2：送餐点与单订单闭环
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
local LANE_CHANGE_DURATION = 0.2
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
local nextPickupZ_ = 45.0

-- 送餐点状态
---@type Node
local deliveryNode_ = nil
local deliveryLane_ = 0
local deliveryActive_ = false
local nextDeliveryZ_ = 0.0

-- 游戏结束 UI 引用
local gameOverPanel_ = nil

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

    print("=== 外卖冲冲冲 - 阶段 1.2：送餐点与单订单闭环 ===")
    print("操作: 左右滑动=变道, 上滑/空格=跳跃, 下滑/S=下滑")
    print("闭环: 未取餐→经过橙色取餐点→送餐中→经过绿色送餐点→循环")
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

    -- 送餐点材质（蓝绿色，和取餐点区分）
    mat_.deliveryBase = CreatePBRMaterial(Color(0.1, 0.75, 0.65, 1.0), 0.0, 0.4)
    mat_.deliveryTop = CreatePBRMaterial(Color(0.2, 0.9, 0.8, 1.0), 0.0, 0.4)
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

--- 计算当前进度下的障碍间距范围
local function GetCurrentSpacingRange()
    local progress = math.min(distanceTraveled_ / CONFIG.SPACING_RAMP_DISTANCE, 1.0)
    local spacingMin = CONFIG.SPACING_MIN_START + (CONFIG.SPACING_MIN_END - CONFIG.SPACING_MIN_START) * progress
    local spacingMax = CONFIG.SPACING_MAX_START + (CONFIG.SPACING_MAX_END - CONFIG.SPACING_MAX_START) * progress
    return spacingMin, spacingMax
end

--- 生成新障碍物（在玩家前方）
local function SpawnObstacles(playerZ)
    local spawnLimit = playerZ + CONFIG.OBSTACLE_SPAWN_AHEAD
    local types = { "block", "low", "high" }

    while nextObstacleZ_ < spawnLimit do
        local typeRoll = math.random(1, 3)
        local obstType = types[typeRoll]
        local lane = math.random(1, 3)

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

--- 创建取餐点节点（初始隐藏）
function CreatePickupPoint()
    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")
    local cylMdl = cache:GetResource("Model", "Models/Cylinder.mdl")

    pickupNode_ = scene_:CreateChild("PickupPoint")
    pickupNode_.position = Vector3(0, -100, -100)
    pickupNode_.enabled = false

    -- 底座（橙色圆柱）
    local base = pickupNode_:CreateChild("Base")
    base.position = Vector3(0, 0.25, 0)
    base.scale = Vector3(0.8, 0.5, 0.8)
    local baseModel = base:CreateComponent("StaticModel")
    baseModel:SetModel(cylMdl)
    baseModel:SetMaterial(mat_.pickupBase)
    baseModel.castShadows = true

    -- 外卖袋（黄色方块）
    local bag = pickupNode_:CreateChild("Bag")
    bag.position = Vector3(0, 0.8, 0)
    bag.scale = Vector3(0.5, 0.6, 0.4)
    local bagModel = bag:CreateComponent("StaticModel")
    bagModel:SetModel(boxMdl)
    bagModel:SetMaterial(mat_.pickupTop)
    bagModel.castShadows = true

    -- 提手（小方块）
    local handle = pickupNode_:CreateChild("Handle")
    handle.position = Vector3(0, 1.2, 0)
    handle.scale = Vector3(0.25, 0.15, 0.1)
    local handleModel = handle:CreateComponent("StaticModel")
    handleModel:SetModel(boxMdl)
    handleModel:SetMaterial(mat_.pickupTop)

    print("[取餐点] 节点已创建")
end

--- 检查某个 z 位置是否与已有障碍物冲突（同车道距离 < 4m）
---@param lane number
---@param z number
---@return boolean
local function IsPickupConflictWithObstacles(lane, z)
    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if obs.active and obs.lane == lane then
            if math.abs(obs.node.position.z - z) < 4.0 then
                return true
            end
        end
    end
    return false
end

--- 尝试生成取餐点
local function TrySpawnPickup(playerZ)
    -- 仅在未取餐且当前无活跃取餐点时生成
    if orderState_ ~= "none" or pickupActive_ then return end

    -- 只在玩家接近 nextPickupZ_ 时生成（提前 60m 内）
    if nextPickupZ_ > playerZ + 60.0 then return end

    -- 随机选车道
    local lane = math.random(1, 3)
    local spawnZ = nextPickupZ_

    -- 避免与障碍物重叠：如果冲突，向前推 5m，最多尝试 5 次
    for _ = 1, 5 do
        if not IsPickupConflictWithObstacles(lane, spawnZ) then
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

    print(string.format("[取餐点] 生成: 车道=%d, Z=%.1f", lane, spawnZ))
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
        orderState_ = "carrying"
        pickupActive_ = false
        pickupNode_.enabled = false
        pickupNode_.position = Vector3(0, -100, -100)
        -- 设置送餐点生成位置
        nextDeliveryZ_ = playerZ + 45.0 + math.random() * 25.0
        print(string.format("[取餐点] 取餐成功！送餐点将在 Z=%.1f 生成", nextDeliveryZ_))
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
        -- 设置下一个取餐点位置（前方 35~55m）
        nextPickupZ_ = playerZ + 35.0 + math.random() * 20.0
        print(string.format("[取餐点] 已错过，下一个 Z=%.1f", nextPickupZ_))
    end
end

-- ============================================================================
-- 送餐点
-- ============================================================================

--- 创建送餐点节点（初始隐藏）
function CreateDeliveryPoint()
    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")
    local cylMdl = cache:GetResource("Model", "Models/Cylinder.mdl")

    deliveryNode_ = scene_:CreateChild("DeliveryPoint")
    deliveryNode_.position = Vector3(0, -100, -100)
    deliveryNode_.enabled = false

    -- 底座（蓝绿色圆柱）
    local base = deliveryNode_:CreateChild("Base")
    base.position = Vector3(0, 0.15, 0)
    base.scale = Vector3(0.9, 0.3, 0.9)
    local baseModel = base:CreateComponent("StaticModel")
    baseModel:SetModel(cylMdl)
    baseModel:SetMaterial(mat_.deliveryBase)
    baseModel.castShadows = true

    -- 小房子主体（方块）
    local house = deliveryNode_:CreateChild("House")
    house.position = Vector3(0, 0.7, 0)
    house.scale = Vector3(0.6, 0.8, 0.5)
    local houseModel = house:CreateComponent("StaticModel")
    houseModel:SetModel(boxMdl)
    houseModel:SetMaterial(mat_.deliveryTop)
    houseModel.castShadows = true

    -- 屋顶（扁方块模拟三角形屋顶）
    local roof = deliveryNode_:CreateChild("Roof")
    roof.position = Vector3(0, 1.2, 0)
    roof.scale = Vector3(0.7, 0.25, 0.6)
    roof.rotation = Quaternion(45, Vector3.FORWARD)
    local roofModel = roof:CreateComponent("StaticModel")
    roofModel:SetModel(boxMdl)
    roofModel:SetMaterial(mat_.deliveryBase)
    roofModel.castShadows = true

    print("[送餐点] 节点已创建")
end

--- 检查某个 z 位置是否与已有障碍物冲突（同车道距离 < 4m）
---@param lane number
---@param z number
---@return boolean
local function IsDeliveryConflictWithObstacles(lane, z)
    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if obs.active and obs.lane == lane then
            if math.abs(obs.node.position.z - z) < 4.0 then
                return true
            end
        end
    end
    return false
end

--- 尝试生成送餐点
local function TrySpawnDelivery(playerZ)
    -- 仅在已取餐且当前无活跃送餐点时生成
    if orderState_ ~= "carrying" or deliveryActive_ then return end

    -- 只在玩家接近 nextDeliveryZ_ 时生成（提前 80m 内）
    if nextDeliveryZ_ > playerZ + 80.0 then return end

    -- 随机选车道
    local lane = math.random(1, 3)
    local spawnZ = nextDeliveryZ_

    -- 避免与障碍物重叠：如果冲突，向前推 5m，最多尝试 5 次
    for _ = 1, 5 do
        if not IsDeliveryConflictWithObstacles(lane, spawnZ) then
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
        -- 送达成功
        orderState_ = "none"
        deliveryActive_ = false
        deliveryNode_.enabled = false
        deliveryNode_.position = Vector3(0, -100, -100)
        -- 设置新的取餐点位置，形成闭环
        nextPickupZ_ = playerZ + 35.0 + math.random() * 20.0
        print(string.format("[送餐点] 送达成功！下一个取餐点 Z=%.1f", nextPickupZ_))
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
        -- 在前方重新安排送餐点
        nextDeliveryZ_ = playerZ + 45.0 + math.random() * 25.0
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
    currentSpeed_ = math.min(
        CONFIG.MAX_SPEED,
        CONFIG.BASE_SPEED + distanceTraveled_ / CONFIG.SPEED_DISTANCE_FACTOR
    )
end

-- ============================================================================
-- 游戏状态管理
-- ============================================================================

--- 触发游戏结束
---@param reason string 失败原因
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
    end
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
    nextPickupZ_ = 50.0  -- 玩家起始 Z=5, 取餐点在前方约 45m
    if pickupNode_ then
        pickupNode_.enabled = false
        pickupNode_.position = Vector3(0, -100, -100)
    end

    -- 重置送餐点状态
    deliveryActive_ = false
    deliveryLane_ = 0
    nextDeliveryZ_ = 0.0
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

    -- 更新摄像机
    UpdateCameraPosition()
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
                    UI.Button {
                        text = "再来一局",
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
            -- HUD: 距离 + 速度
            UI.Label {
                id = "hud_info",
                text = "0 m  |  8.0 m/s",
                fontSize = 14,
                fontColor = { 255, 255, 200, 210 },
                position = "absolute",
                top = 50,
                left = 0, right = 0,
                textAlign = "center",
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
    if not CanDoAction() then return end
    actionState_ = "jump"
    actionTimer_ = 0.0
end

local function TrySlide()
    if not CanDoAction() then return end
    actionState_ = "slide"
    actionTimer_ = 0.0
end

local function UpdateAction(dt)
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
        return
    end

    -- 输入
    HandleTouchInput()
    HandleKeyboardInput()

    -- 更新动作状态
    UpdateAction(dt)
    UpdateLaneChange(dt)

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

    -- 取餐点/送餐点旋转动画（更醒目）
    if pickupActive_ and pickupNode_ then
        pickupNode_.rotation = Quaternion(runTime_ * 90.0, Vector3.UP)
    end
    if deliveryActive_ and deliveryNode_ then
        deliveryNode_.rotation = Quaternion(runTime_ * 60.0, Vector3.UP)
    end

    -- HUD 更新（节流 4Hz）
    uiTimer_ = uiTimer_ + dt
    if uiTimer_ >= 0.25 then
        uiTimer_ = uiTimer_ - 0.25
        local hudLabel = UI.FindById("hud_info")
        if hudLabel then
            local orderText = orderState_ == "carrying" and "送餐中" or "未取餐"
            hudLabel:SetText(string.format("%d m | %.1f m/s | %s", math.floor(distanceTraveled_), currentSpeed_, orderText))
        end
    end
end
