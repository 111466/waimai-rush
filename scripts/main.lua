-- ============================================================================
-- 外卖冲冲冲 - 阶段 0.4：障碍与碰撞失败
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
    ROAD_WIDTH = 7.0,           -- 跑道总宽度（米）
    ROAD_SEGMENT_LENGTH = 40.0, -- 每段跑道长度
    ROAD_SEGMENTS = 8,          -- 同时存在的跑道段数（循环池）

    -- 车道线参数
    LINE_SPACING = 3.0,         -- 车道线间距
    LINE_LENGTH = 1.5,          -- 每段线长
    LINE_POOL_SIZE = 40,        -- 车道线池大小（单侧）

    -- 建筑参数
    BUILDING_ZONE_START = 4.5,
    BUILDING_ZONE_END = 15.0,
    BUILDING_POOL_SIZE = 40,    -- 建筑池大小（两侧总计）

    -- 玩家参数
    RUN_SPEED = 8.0,            -- 奔跑速度（米/秒）

    -- 摄像机跟随参数（竖屏跑酷视角）
    CAM_OFFSET_Y = 6.0,
    CAM_OFFSET_Z = -7.0,
    CAM_LOOK_AHEAD = 5.0,

    -- 障碍物参数
    OBSTACLE_POOL_SIZE = 10,         -- 障碍物池大小
    OBSTACLE_SPACING_MIN = 14.0,     -- 障碍物最小间距（米）≈ 1.75s at 8m/s
    OBSTACLE_SPACING_MAX = 22.0,     -- 障碍物最大间距（米）
    OBSTACLE_SPAWN_AHEAD = 80.0,     -- 在玩家前方多远生成
    OBSTACLE_RECYCLE_BEHIND = 10.0,  -- 玩家后方多远回收

    -- 碰撞参数
    COLLISION_Z_THRESHOLD = 0.8,     -- Z 方向碰撞半径
}

-- 变道参数
local LANE_CHANGE_DURATION = 0.2     -- 变道持续时间（秒）
local SWIPE_THRESHOLD = 40.0         -- 滑动触发阈值（像素）

-- 变道状态
local laneChangeTimer_ = 0.0         -- 变道计时器（>0 表示正在变道中）
local laneChangeFromX_ = 0.0         -- 变道起始 X
local laneChangeToX_ = 0.0           -- 变道目标 X

-- 跳跃与下滑参数
local JUMP_DURATION = 0.6            -- 跳跃持续时间（秒）
local JUMP_HEIGHT = 1.5              -- 跳跃最大高度（米）
local SLIDE_DURATION = 0.5           -- 下滑持续时间（秒）

-- 动作状态: "run" / "jump" / "slide"
local actionState_ = "run"
local actionTimer_ = 0.0             -- 当前动作已经持续的时间

-- 触摸滑动检测（方向感知）
local touchStartX_ = nil             -- 触摸开始时的 X 坐标（像素）
local touchStartY_ = nil             -- 触摸开始时的 Y 坐标（像素）
local touchId_ = -1                  -- 正在追踪的触摸 ID
local touchConsumed_ = false         -- 本次触摸是否已消耗（触发过动作）

-- 运行距离追踪
local distanceTraveled_ = 0.0

-- 道路循环池
local roadSegments_ = {}   -- 每项: { road, curbL, curbR, sidewalkL, sidewalkR }
local nextSegmentZ_ = 0.0  -- 下一段路面应该放置的 Z 位置

-- 车道线池
local laneLines_ = {}      -- 每项: { lineL, lineR }
local nextLineZ_ = 0.0     -- 下一条线的 Z

-- 建筑池
local buildings_ = {}      -- 节点列表
local nextBuildingZ_ = 0.0

-- 障碍物池
-- 每项: { node, type("block"/"low"/"high"), lane(1~3), active(bool) }
local obstacles_ = {}
local nextObstacleZ_ = 30.0  -- 第一个障碍物在玩家前方 30m 处

-- 共享材质（避免重复创建）
local mat_ = {}

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
    SetupCamera()
    CreateUI()

    SubscribeToEvent("Update", "HandleUpdate")

    print("=== 外卖冲冲冲 - 阶段 0.4：障碍与碰撞失败 ===")
    print("操作: 左右滑动=变道, 上滑/空格=跳跃, 下滑/S=下滑")
    print("障碍: 红色方块=变道躲避, 绿色低栏=跳跃, 紫色高杆=下滑")
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

    -- 加载 Daytime 光照预设
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    -- 调整雾效
    local zone = lightGroup:GetComponent("Zone", true)
    if zone then
        zone.fogColor = Color(0.75, 0.88, 0.95)
        zone.fogStart = 60.0
        zone.fogEnd = 200.0
    end

    -- 暖白阳光
    local light = lightGroup:GetComponent("Light", true)
    if light then
        light.color = Color(1.0, 0.95, 0.85)
        light.brightness = 3.5
    end
end

-- ============================================================================
-- 材质（只创建一次）
-- ============================================================================

--- 创建一个 PBR 无贴图材质
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

    -- 建筑配色
    mat_.buildings = {
        CreatePBRMaterial(Color(0.55, 0.82, 0.78, 1.0), 0.0, 0.7),  -- 薄荷绿
        CreatePBRMaterial(Color(0.65, 0.80, 0.90, 1.0), 0.0, 0.7),  -- 天蓝
        CreatePBRMaterial(Color(0.92, 0.85, 0.65, 1.0), 0.0, 0.7),  -- 暖黄
        CreatePBRMaterial(Color(0.88, 0.70, 0.60, 1.0), 0.0, 0.7),  -- 珊瑚橙
        CreatePBRMaterial(Color(0.80, 0.75, 0.90, 1.0), 0.0, 0.7),  -- 淡紫
        CreatePBRMaterial(Color(0.95, 0.92, 0.82, 1.0), 0.0, 0.7),  -- 奶白
    }

    -- 障碍物材质
    mat_.obstacleBlock = CreatePBRMaterial(Color(0.9, 0.25, 0.2, 1.0), 0.0, 0.5)   -- 红色方块
    mat_.obstacleLow = CreatePBRMaterial(Color(0.2, 0.75, 0.3, 1.0), 0.0, 0.5)     -- 绿色低栏
    mat_.obstacleHigh = CreatePBRMaterial(Color(0.6, 0.25, 0.8, 1.0), 0.0, 0.5)    -- 紫色高杆
end

-- ============================================================================
-- 道路循环池
-- ============================================================================

--- 创建一段道路（路面 + 路缘 + 人行道）并返回节点表
local function CreateOneRoadSegment(zCenter)
    local segLen = CONFIG.ROAD_SEGMENT_LENGTH
    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")

    -- 主路面
    local road = scene_:CreateChild("Road")
    road.position = Vector3(0, -0.05, zCenter)
    road.scale = Vector3(CONFIG.ROAD_WIDTH, 0.1, segLen)
    local rm = road:CreateComponent("StaticModel")
    rm:SetModel(boxMdl)
    rm:SetMaterial(mat_.road)

    -- 左路缘
    local curbL = scene_:CreateChild("CurbL")
    curbL.position = Vector3(-CONFIG.ROAD_WIDTH / 2 - 0.15, 0.05, zCenter)
    curbL.scale = Vector3(0.3, 0.3, segLen)
    local clm = curbL:CreateComponent("StaticModel")
    clm:SetModel(boxMdl)
    clm:SetMaterial(mat_.curb)

    -- 右路缘
    local curbR = scene_:CreateChild("CurbR")
    curbR.position = Vector3(CONFIG.ROAD_WIDTH / 2 + 0.15, 0.05, zCenter)
    curbR.scale = Vector3(0.3, 0.3, segLen)
    local crm = curbR:CreateComponent("StaticModel")
    crm:SetModel(boxMdl)
    crm:SetMaterial(mat_.curb)

    -- 左人行道
    local swL = scene_:CreateChild("SidewalkL")
    swL.position = Vector3(-CONFIG.ROAD_WIDTH / 2 - 1.5, -0.02, zCenter)
    swL.scale = Vector3(2.5, 0.1, segLen)
    local slm = swL:CreateComponent("StaticModel")
    slm:SetModel(boxMdl)
    slm:SetMaterial(mat_.sidewalk)

    -- 右人行道
    local swR = scene_:CreateChild("SidewalkR")
    swR.position = Vector3(CONFIG.ROAD_WIDTH / 2 + 1.5, -0.02, zCenter)
    swR.scale = Vector3(2.5, 0.1, segLen)
    local srm = swR:CreateComponent("StaticModel")
    srm:SetModel(boxMdl)
    srm:SetMaterial(mat_.sidewalk)

    return { road = road, curbL = curbL, curbR = curbR, swL = swL, swR = swR }
end

--- 移动一段道路到新的 Z 位置
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
    -- 随机左右侧
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

--[[
  三种障碍物类型：
  ┌─────────┬───────────────────────────┬──────────────────┐
  │  type   │  外观                      │  躲避方式         │
  ├─────────┼───────────────────────────┼──────────────────┤
  │ "block" │  红色方块 (1.0×1.2×1.0)   │  变道躲避         │
  │ "low"   │  绿色低栏 (1.5×0.6×0.3)   │  跳跃越过         │
  │ "high"  │  紫色高杆 (1.2×2.5×0.3)   │  下滑穿过         │
  └─────────┴───────────────────────────┴──────────────────┘

  碰撞检测示意：
  - 同车道（lane index 相同）
  - Z 距离 < COLLISION_Z_THRESHOLD (0.8m)
  - 检查玩家当前动作是否能躲避该障碍
]]

--- 创建单个障碍物节点（初始隐藏）
---@param obstacleType string "block" / "low" / "high"
---@return Node
local function CreateObstacleNode(obstacleType)
    local node = scene_:CreateChild("Obstacle")
    local boxMdl = cache:GetResource("Model", "Models/Box.mdl")

    if obstacleType == "block" then
        -- 红色方块：宽 1.0，高 1.2，深 1.0
        node.scale = Vector3(1.0, 1.2, 1.0)
        local model = node:CreateComponent("StaticModel")
        model:SetModel(boxMdl)
        model:SetMaterial(mat_.obstacleBlock)
        model.castShadows = true

    elseif obstacleType == "low" then
        -- 绿色低栏：宽 1.5，高 0.6，深 0.3（放在地面，需跳跃越过）
        node.scale = Vector3(1.5, 0.6, 0.3)
        local model = node:CreateComponent("StaticModel")
        model:SetModel(boxMdl)
        model:SetMaterial(mat_.obstacleLow)
        model.castShadows = true

    elseif obstacleType == "high" then
        -- 紫色高杆：宽 1.2，高 0.4，深 0.3（悬空在上方，需下滑穿过）
        node.scale = Vector3(1.2, 0.4, 0.3)
        local model = node:CreateComponent("StaticModel")
        model:SetModel(boxMdl)
        model:SetMaterial(mat_.obstacleHigh)
        model.castShadows = true
    end

    -- 初始隐藏，放在远处
    node.position = Vector3(0, -100, -100)
    node.enabled = false

    return node
end

function CreateObstaclePool()
    for i = 1, CONFIG.OBSTACLE_POOL_SIZE do
        -- 均匀分配三种类型
        local typeIdx = ((i - 1) % 3) + 1
        local types = { "block", "low", "high" }
        local obstType = types[typeIdx]

        local node = CreateObstacleNode(obstType)
        obstacles_[i] = {
            node = node,
            type = obstType,
            lane = 0,
            active = false,
        }
    end
    print(string.format("[障碍物] 对象池创建完毕, 大小=%d", CONFIG.OBSTACLE_POOL_SIZE))
end

--- 从池中获取一个空闲的障碍物
---@param desiredType string
---@return table|nil 障碍物条目
local function GetFreeObstacle(desiredType)
    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if not obs.active and obs.type == desiredType then
            return obs
        end
    end
    return nil
end

--- 激活障碍物到指定位置
---@param obs table 障碍物条目
---@param lane number 车道索引 1~3
---@param z number Z 位置
local function ActivateObstacle(obs, lane, z)
    obs.active = true
    obs.lane = lane

    local laneX = CONFIG.LANE_X[lane]
    local y = 0

    if obs.type == "block" then
        -- 方块底部在地面，中心 Y = 高度/2 = 0.6
        y = 0.6
    elseif obs.type == "low" then
        -- 低栏底部在地面，中心 Y = 高度/2 = 0.3
        y = 0.3
    elseif obs.type == "high" then
        -- 高杆悬空：底部约在 1.0m 高度，中心 Y = 1.0 + 高度/2 = 1.2
        y = 1.2
    end

    obs.node.position = Vector3(laneX, y, z)
    obs.node.enabled = true
end

--- 回收障碍物（隐藏并标记为空闲）
local function DeactivateObstacle(obs)
    obs.active = false
    obs.lane = 0
    obs.node.enabled = false
    obs.node.position = Vector3(0, -100, -100)
end

--- 生成新障碍物（在玩家前方）
local function SpawnObstacles(playerZ)
    local spawnLimit = playerZ + CONFIG.OBSTACLE_SPAWN_AHEAD

    while nextObstacleZ_ < spawnLimit do
        -- 随机选择障碍类型
        local typeRoll = math.random(1, 3)
        local types = { "block", "low", "high" }
        local obstType = types[typeRoll]

        -- 随机选择车道
        local lane = math.random(1, 3)

        -- 获取空闲障碍物
        local obs = GetFreeObstacle(obstType)
        if obs then
            ActivateObstacle(obs, lane, nextObstacleZ_)
        end

        -- 计算下一个障碍物位置（随机间距）
        local spacing = CONFIG.OBSTACLE_SPACING_MIN +
            math.random() * (CONFIG.OBSTACLE_SPACING_MAX - CONFIG.OBSTACLE_SPACING_MIN)
        nextObstacleZ_ = nextObstacleZ_ + spacing
    end
end

--- 回收在玩家后方的障碍物
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
-- 碰撞检测
-- ============================================================================

--- 检测玩家与障碍物的碰撞
---@param playerZ number 玩家当前 Z 坐标
---@return boolean 是否发生碰撞（游戏结束）
local function CheckCollision(playerZ)
    local playerLane = CONFIG.currentLane

    for i = 1, #obstacles_ do
        local obs = obstacles_[i]
        if obs.active then
            -- 同车道检测
            if obs.lane == playerLane then
                local obsZ = obs.node.position.z
                local zDist = math.abs(playerZ - obsZ)

                if zDist < CONFIG.COLLISION_Z_THRESHOLD then
                    -- 碰撞发生！检查是否能躲避
                    if obs.type == "block" then
                        -- 方块：只能通过变道躲避，不能跳跃或下滑通过
                        print(string.format("[碰撞] 撞到方块! lane=%d, z=%.1f", obs.lane, obsZ))
                        return true

                    elseif obs.type == "low" then
                        -- 低栏：跳跃中可以躲避
                        if actionState_ ~= "jump" then
                            print(string.format("[碰撞] 被低栏绊倒! lane=%d, z=%.1f, action=%s", obs.lane, obsZ, actionState_))
                            return true
                        end

                    elseif obs.type == "high" then
                        -- 高杆：下滑中可以躲避
                        if actionState_ ~= "slide" then
                            print(string.format("[碰撞] 撞到高杆! lane=%d, z=%.1f, action=%s", obs.lane, obsZ, actionState_))
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

-- ============================================================================
-- 游戏状态管理
-- ============================================================================

--- 触发游戏结束
local function TriggerGameOver()
    gameState_ = "gameOver"
    print(string.format("[游戏结束] 距离: %d m", math.floor(distanceTraveled_)))

    -- 显示游戏结束面板
    if gameOverPanel_ then
        gameOverPanel_:SetVisible(true)
        -- 更新距离显示
        local scoreLabel = UI.FindById("go_score")
        if scoreLabel then
            scoreLabel:SetText(string.format("本次距离: %d 米", math.floor(distanceTraveled_)))
        end
    end
end

--- 重置游戏（再来一局）
local function RestartGame()
    print("[重启] 再来一局")

    -- 重置游戏状态
    gameState_ = "running"
    distanceTraveled_ = 0.0

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
    nextObstacleZ_ = 30.0 + 5.0  -- 玩家起始 Z=5, 第一个障碍物在前方 30m

    -- 重置道路池（将所有路段重新分配）
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

    -- 身体（圆柱体）
    local bodyNode = playerNode_:CreateChild("Body")
    bodyNode.position = Vector3(0, 0.7, 0)
    bodyNode.scale = Vector3(0.5, 1.2, 0.4)
    local bodyModel = bodyNode:CreateComponent("StaticModel")
    bodyModel:SetModel(cylMdl)
    bodyModel:SetMaterial(CreatePBRMaterial(Color(0.2, 0.45, 0.8, 1.0), 0.0, 0.6))
    bodyModel.castShadows = true

    -- 头部（球体）
    local headNode = playerNode_:CreateChild("Head")
    headNode.position = Vector3(0, 1.5, 0)
    headNode.scale = Vector3(0.4, 0.4, 0.4)
    local headModel = headNode:CreateComponent("StaticModel")
    headModel:SetModel(sphMdl)
    headModel:SetMaterial(CreatePBRMaterial(Color(0.95, 0.82, 0.70, 1.0), 0.0, 0.5))
    headModel.castShadows = true

    -- 外卖箱（方块）
    local dboxNode = playerNode_:CreateChild("DeliveryBox")
    dboxNode.position = Vector3(0, 1.0, -0.35)
    dboxNode.scale = Vector3(0.5, 0.5, 0.3)
    local dboxModel = dboxNode:CreateComponent("StaticModel")
    dboxModel:SetModel(boxMdl)
    dboxModel:SetMaterial(CreatePBRMaterial(Color(1.0, 0.75, 0.1, 1.0), 0.0, 0.5))
    dboxModel.castShadows = true

    -- 帽子（小圆柱）
    local hatNode = playerNode_:CreateChild("Hat")
    hatNode.position = Vector3(0, 1.75, 0)
    hatNode.scale = Vector3(0.35, 0.12, 0.35)
    local hatModel = hatNode:CreateComponent("StaticModel")
    hatModel:SetModel(cylMdl)
    hatModel:SetMaterial(CreatePBRMaterial(Color(1.0, 0.8, 0.15, 1.0), 0.0, 0.5))
    hatModel.castShadows = true
end

-- ============================================================================
-- 摄像机（竖屏跑酷视角）
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
    -- 游戏结束面板（初始隐藏）
    gameOverPanel_ = UI.Panel {
        id = "gameOverPanel",
        visible = false,
        position = "absolute",
        top = 0,
        left = 0,
        right = 0,
        bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        children = {
            UI.Panel {
                width = 260,
                paddingTop = 30,
                paddingBottom = 30,
                paddingLeft = 20,
                paddingRight = 20,
                borderRadius = 16,
                backgroundColor = { 255, 255, 255, 240 },
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "游戏结束",
                        fontSize = 28,
                        fontWeight = "bold",
                        fontColor = { 50, 50, 50, 255 },
                    },
                    UI.Label {
                        id = "go_score",
                        text = "本次距离: 0 米",
                        fontSize = 16,
                        fontColor = { 100, 100, 100, 255 },
                        marginTop = 12,
                    },
                    UI.Button {
                        text = "再来一局",
                        variant = "primary",
                        marginTop = 24,
                        width = 160,
                        height = 48,
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
                left = 0,
                right = 0,
                textAlign = "center",
            },
            UI.Label {
                id = "distance",
                text = "距离: 0 m",
                fontSize = 14,
                fontColor = { 255, 255, 200, 200 },
                position = "absolute",
                top = 50,
                left = 0,
                right = 0,
                textAlign = "center",
            },
            gameOverPanel_,
        },
    }
    UI.SetRoot(uiRoot)
end

-- ============================================================================
-- 循环回收逻辑
-- ============================================================================

--- 回收已经在玩家后方的道路段，移到前方
local function RecycleRoadSegments(playerZ)
    local segLen = CONFIG.ROAD_SEGMENT_LENGTH
    local recycleThreshold = playerZ - segLen

    for i = 1, #roadSegments_ do
        local seg = roadSegments_[i]
        local segZ = seg.road.position.z
        if segZ < recycleThreshold then
            local newZ = nextSegmentZ_ + segLen / 2
            MoveRoadSegment(seg, newZ)
            nextSegmentZ_ = nextSegmentZ_ + segLen
        end
    end
end

--- 回收车道线
local function RecycleLaneLines(playerZ)
    local spacing = CONFIG.LINE_SPACING
    local recycleThreshold = playerZ - spacing * 2

    for i = 1, #laneLines_ do
        local pair = laneLines_[i]
        local lineZ = pair.lineL.position.z
        if lineZ < recycleThreshold then
            pair.lineL.position = Vector3(-1.0, 0.01, nextLineZ_)
            pair.lineR.position = Vector3(1.0, 0.01, nextLineZ_)
            nextLineZ_ = nextLineZ_ + spacing
        end
    end
end

--- 回收建筑
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

--- 判断是否正在变道中
local function IsChangingLane()
    return laneChangeTimer_ > 0.0
end

--- 发起变道（direction: -1 左移, +1 右移）
local function TryChangeLane(direction)
    if IsChangingLane() then return end

    local newLane = CONFIG.currentLane + direction
    if newLane < 1 or newLane > 3 then return end

    laneChangeFromX_ = CONFIG.LANE_X[CONFIG.currentLane]
    laneChangeToX_ = CONFIG.LANE_X[newLane]
    CONFIG.currentLane = newLane
    laneChangeTimer_ = LANE_CHANGE_DURATION
end

--- 更新变道平滑移动
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
-- 跳跃与下滑逻辑
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
-- 输入系统（方向感知触摸 + 键盘）
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
            local currentX = touch.position.x
            local currentY = touch.position.y
            local deltaX = currentX - touchStartX_
            local deltaY = currentY - touchStartY_
            local absDX = math.abs(deltaX)
            local absDY = math.abs(deltaY)

            if absDX > SWIPE_THRESHOLD or absDY > SWIPE_THRESHOLD then
                if absDX > absDY then
                    if deltaX > 0 then
                        TryChangeLane(1)
                    else
                        TryChangeLane(-1)
                    end
                else
                    if deltaY < 0 then
                        TryJump()
                    else
                        TrySlide()
                    end
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

--- 更新角色子节点姿态（跑步摆动 / 跳跃 / 下滑）
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
        if headNode then
            headNode.position = Vector3(0, 1.5 + bobY, 0)
            headNode.scale = Vector3(0.4, 0.4, 0.4)
        end
        if hatNode then
            hatNode.position = Vector3(0, 1.75 + bobY, 0)
        end
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
        if headNode then
            headNode.position = Vector3(0, 1.5, 0)
            headNode.scale = Vector3(0.4, 0.4, 0.4)
        end
        if hatNode then
            hatNode.position = Vector3(0, 1.75, 0)
        end
        if dboxNode then
            dboxNode.rotation = Quaternion.IDENTITY
            dboxNode.position = Vector3(0, 1.0, -0.35)
        end

    elseif actionState_ == "slide" then
        local progress = actionTimer_ / SLIDE_DURATION
        local slideAmount
        if progress < 0.8 then
            slideAmount = 1.0
        else
            slideAmount = 1.0 - ((progress - 0.8) / 0.2)
        end

        if bodyNode then
            local bodyHeight = 1.2 - 0.7 * slideAmount
            local bodyY = 0.3 + (0.7 - 0.3) * (1.0 - slideAmount)
            bodyNode.position = Vector3(0, bodyY, 0)
            bodyNode.scale = Vector3(0.5 + 0.2 * slideAmount, bodyHeight, 0.4 + 0.2 * slideAmount)
            bodyNode.rotation = Quaternion(25 * slideAmount, Vector3.RIGHT)
        end
        if headNode then
            local headY = 1.5 - 0.9 * slideAmount
            headNode.position = Vector3(0, headY, 0.15 * slideAmount)
            headNode.scale = Vector3(0.4, 0.4, 0.4)
        end
        if hatNode then
            local hatY = 1.75 - 1.0 * slideAmount
            hatNode.position = Vector3(0, hatY, 0.15 * slideAmount)
        end
        if dboxNode then
            dboxNode.rotation = Quaternion(-15 * slideAmount, Vector3.RIGHT)
            local dboxY = 1.0 - 0.5 * slideAmount
            dboxNode.position = Vector3(0, dboxY, -0.35 - 0.1 * slideAmount)
        end
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if playerNode_ == nil then return end

    -- 游戏结束时不处理输入和运动
    if gameState_ == "gameOver" then
        return
    end

    -- 输入检测（触摸 + 键盘）
    HandleTouchInput()
    HandleKeyboardInput()

    -- 更新动作状态（跳跃/下滑计时）
    UpdateAction(dt)

    -- 更新变道平滑移动
    UpdateLaneChange(dt)

    -- 计算跳跃 Y 偏移
    local jumpY = GetJumpY()

    -- 玩家自动向前跑
    local currentPos = playerNode_.position
    local newZ = currentPos.z + CONFIG.RUN_SPEED * dt
    playerNode_.position = Vector3(currentPos.x, jumpY, newZ)

    -- 更新距离
    distanceTraveled_ = distanceTraveled_ + CONFIG.RUN_SPEED * dt

    -- 更新角色子节点姿态
    UpdatePlayerPose(dt)

    -- 障碍物生成与回收
    SpawnObstacles(newZ)
    RecycleObstacles(newZ)

    -- 碰撞检测
    if CheckCollision(newZ) then
        TriggerGameOver()
        return
    end

    -- 循环回收道路、车道线、建筑
    RecycleRoadSegments(newZ)
    RecycleLaneLines(newZ)
    RecycleBuildings(newZ)

    -- 更新摄像机
    UpdateCameraPosition()

    -- 更新 UI（节流）
    uiTimer_ = uiTimer_ + dt
    if uiTimer_ >= 0.25 then
        uiTimer_ = uiTimer_ - 0.25
        local distLabel = UI.FindById("distance")
        if distLabel then
            distLabel:SetText(string.format("距离: %d m", math.floor(distanceTraveled_)))
        end
    end
end
