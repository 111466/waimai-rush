-- ============================================================================
-- 外卖冲冲冲 - 真实转弯跑酷（Temple Run 式 90° 转向）
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

-- ============================================================================
-- 游戏配置
-- ============================================================================
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
    BASE_SPEED = 8.0,
    MAX_SPEED = 14.0,
    SPEED_DISTANCE_FACTOR = 100.0,

    -- 摄像机跟随参数（竖屏跑酷视角）
    CAM_OFFSET_Y = 6.0,
    CAM_OFFSET_Z = -7.0,
    CAM_LOOK_AHEAD = 5.0,
    CAM_SMOOTH = 8.0,
    CAM_FOV_BASE = 50.0,
    CAM_FOV_MAX = 58.0,
    CAM_FOV_SPEED_FACTOR = 0.5,
    CAM_TILT_FACTOR = 1.5,

    -- 障碍物
    OBSTACLE_POOL_PER_TYPE = 8,
    OBSTACLE_SPAWN_AHEAD = 80.0,
    OBSTACLE_MIN_SPACING = 12.0,
    OBSTACLE_MAX_PER_ROW = 2,
    COLLISION_Z_THRESHOLD = 0.8,

    -- 难度渐进
    DIFFICULTY_START_DISTANCE = 50.0,
    DIFFICULTY_RAMP_DISTANCE = 400.0,
    OBSTACLE_SPACING_MIN = 8.0,
    OBSTACLE_SPACING_MAX = 18.0,

    -- 取件/送件
    PICKUP_SPAWN_AHEAD = 70.0,
    PICKUP_INTERVAL_MIN = 40.0,
    PICKUP_INTERVAL_MAX = 70.0,
    DELIVERY_SPAWN_AHEAD = 70.0,
    DELIVERY_INTERVAL_MIN = 50.0,
    DELIVERY_INTERVAL_MAX = 80.0,
    DELIVERY_COMBO_MULTIPLIER = 0.5,

    -- 跳跃与下滑
    JUMP_DURATION = 0.6,
    JUMP_HEIGHT = 1.5,
    SLIDE_DURATION = 0.5,

    -- 变道平滑
    LANE_CHANGE_DURATION = 0.18,
}

-- ============================================================================
-- 路径系统配置（真实转弯）
-- ============================================================================
local PATH = {
    -- 方向枚举: 0=+Z, 1=+X, 2=-Z, 3=-X
    HEADING_POS_Z = 0,
    HEADING_POS_X = 1,
    HEADING_NEG_Z = 2,
    HEADING_NEG_X = 3,

    -- 路口参数
    FIRST_INTERSECTION_DIST = 120.0,
    INTERVAL_MIN = 150.0,
    INTERVAL_MAX = 220.0,

    -- 转弯输入窗口
    TURN_INPUT_WINDOW = 20.0,       -- 路口前多少米开始接受转弯输入
    TURN_EXECUTE_DIST = 2.0,        -- 到路口多近时执行转弯

    -- 动画
    TURN_ANIM_DURATION = 0.40,      -- 转弯动画时长(秒)
    CAM_TURN_DURATION = 0.45,       -- 摄像机转弯动画时长

    -- 安全区
    SAFE_ZONE_BEFORE = 25.0,        -- 路口前安全区（无障碍）
    SAFE_ZONE_AFTER = 35.0,         -- 路口后安全区（无障碍）

    -- 奖惩
    CORRECT_TURN_BONUS = 2.0,       -- 正确转弯 +2秒
    WRONG_TURN_PENALTY = 3.0,       -- 错误转弯 -3秒（最低2秒）

    -- 视觉
    CROSSROADS_SIZE = 12.0,         -- 十字路口平台尺寸
    PREVIEW_ROAD_LENGTH = 30.0,     -- 预览路段长度
}

-- ============================================================================
-- 路径系统运行时状态
-- ============================================================================
local routeDistance_ = 0.0              -- 已跑总路程
local currentHeading_ = 0              -- 当前朝向（0=+Z, 1=+X, 2=-Z, 3=-X）
local currentSegmentOrigin_ = nil      -- 当前直道段起点世界坐标 Vector3
local currentSegmentStartDist_ = 0.0   -- 当前段开始时的 routeDistance_

-- 转弯状态
local nextIntersectionDist_ = 0.0      -- 下一个路口的 routeDistance
local intersectionActive_ = false      -- 是否在路口输入窗口内
local turnChoice_ = 0                  -- 0=直走, -1=左转, 1=右转
local turnExecuting_ = false           -- 正在执行转弯动画
local turnAnimTime_ = 0.0              -- 转弯动画已用时间
local turnFromHeading_ = 0             -- 转弯前朝向
local turnToHeading_ = 0               -- 转弯后朝向
local turnWorldPos_ = nil              -- 转弯点世界坐标

-- 摄像机转弯
local camTurnAnimTime_ = 0.0
local camTurnFrom_ = 0.0               -- 起始 yaw 角度
local camTurnTo_ = 0.0                 -- 目标 yaw 角度
local camTurning_ = false

-- 路口视觉节点
local crossroadsNode_ = nil
local previewRoadNodes_ = {}
local arrowNodes_ = {}

-- 路口方向提示
local intersectionHintDir_ = 0         -- 推荐方向 -1=左, 1=右, 0=直
local intersectionCorrectDir_ = 0      -- 正确方向(送件点方向)

-- ============================================================================
-- 前向声明（解决定义顺序问题）
-- ============================================================================
local IsInSafeZone
local GetForwardVector
local GetRightVector
local GetWorldPosOnTrack
local HeadingToYaw

-- ============================================================================
-- 其他运行时状态
-- ============================================================================
local distanceTraveled_ = 0.0
local currentSpeed_ = CONFIG.BASE_SPEED
local lastObstacleSpawnDist_ = 0.0

-- 变道动画
local laneChanging_ = false
local laneChangeFrom_ = 0.0
local laneChangeTo_ = 0.0
local laneChangeTime_ = 0.0

-- 跳跃
local isJumping_ = false
local jumpTime_ = 0.0
local jumpBuffered_ = false

-- 下滑
local isSliding_ = false
local slideTime_ = 0.0
local slideBuffered_ = false

-- 取件/送件
local pickupNode_ = nil
local pickupActive_ = false
local pickupPathDist_ = 0.0
local pickupLane_ = 2
local lastPickupDist_ = 0.0
local nextPickupDist_ = 0.0

local deliveryNode_ = nil
local deliveryActive_ = false
local deliveryPathDist_ = 0.0
local deliveryLane_ = 2
local lastDeliveryDist_ = 0.0
local nextDeliveryDist_ = 0.0

local hasPackage_ = false
local packageVisualNode_ = nil

-- 计时器/收入/连击
local timeRemaining_ = 30.0
local totalIncome_ = 0
local comboCount_ = 0

-- 对象池
local roadPool_ = {}
local linePool_ = {}
local buildingPool_ = {}
local obstaclePool_ = {}
local activeObstacles_ = {}

-- 材质缓存
local mat_road_, mat_laneLine_, mat_sidewalk_, mat_curb_
local mat_building_base_
local mat_obstacle_block_, mat_obstacle_low_, mat_obstacle_high_
local mat_pickup_, mat_delivery_, mat_arrow_
local mat_crossroads_

-- UI 引用
local lblTimer_, lblIncome_, lblCombo_, lblSpeed_, lblHint_
local gameOverPanel_, lblFinalIncome_, lblFinalDist_

-- ============================================================================
-- 路径系统辅助函数
-- ============================================================================

--- 朝向 → 前进方向向量
GetForwardVector = function(heading)
    if heading == 0 then return Vector3(0, 0, 1)
    elseif heading == 1 then return Vector3(1, 0, 0)
    elseif heading == 2 then return Vector3(0, 0, -1)
    elseif heading == 3 then return Vector3(-1, 0, 0)
    end
    return Vector3(0, 0, 1)
end

--- 朝向 → 右侧方向向量
GetRightVector = function(heading)
    if heading == 0 then return Vector3(1, 0, 0)
    elseif heading == 1 then return Vector3(0, 0, -1)
    elseif heading == 2 then return Vector3(-1, 0, 0)
    elseif heading == 3 then return Vector3(0, 0, 1)
    end
    return Vector3(1, 0, 0)
end

--- 朝向 → 摄像机 yaw 角(度)
HeadingToYaw = function(heading)
    -- heading 0=+Z → yaw=0, 1=+X → yaw=90, 2=-Z → yaw=180, 3=-X → yaw=270
    return heading * 90.0
end

--- 根据路程和车道偏移计算世界坐标
GetWorldPosOnTrack = function(pathDist, laneOffset)
    local localDist = pathDist - currentSegmentStartDist_
    local fwd = GetForwardVector(currentHeading_)
    local right = GetRightVector(currentHeading_)
    local pos = Vector3(
        currentSegmentOrigin_.x + fwd.x * localDist + right.x * laneOffset,
        0,
        currentSegmentOrigin_.z + fwd.z * localDist + right.z * laneOffset
    )
    return pos
end

--- 检查某个路程距离是否在安全区内（路口前后不生成障碍）
IsInSafeZone = function(pathDist)
    if nextIntersectionDist_ <= 0 then return false end
    local distToIntersection = nextIntersectionDist_ - pathDist
    if distToIntersection > 0 and distToIntersection < PATH.SAFE_ZONE_BEFORE then
        return true
    end
    if distToIntersection <= 0 and distToIntersection > -PATH.SAFE_ZONE_AFTER then
        return true
    end
    return false
end

--- 根据路程距离计算世界坐标（通用版，考虑转弯点）
local function GetWorldPosForObject(pathDist, laneOffset)
    -- 如果对象在当前段，直接计算
    local localDist = pathDist - currentSegmentStartDist_
    local fwd = GetForwardVector(currentHeading_)
    local right = GetRightVector(currentHeading_)
    return Vector3(
        currentSegmentOrigin_.x + fwd.x * localDist + right.x * laneOffset,
        0,
        currentSegmentOrigin_.z + fwd.z * localDist + right.z * laneOffset
    )
end

-- ============================================================================
-- 材质工具
-- ============================================================================

local function CreatePBRMaterial(diffuseColor, metallic, roughness)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", diffuseColor)
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.8))
    return mat
end

local function InitMaterials()
    -- 道路 - 浅灰白
    mat_road_ = CreatePBRMaterial(Color(0.85, 0.85, 0.82, 1.0), 0.0, 0.9)
    -- 车道线 - 淡蓝
    mat_laneLine_ = CreatePBRMaterial(Color(0.6, 0.75, 0.88, 1.0), 0.0, 0.7)
    -- 人行道 - 暖米色
    mat_sidewalk_ = CreatePBRMaterial(Color(0.92, 0.88, 0.78, 1.0), 0.0, 0.85)
    -- 路缘石 - 中灰绿
    mat_curb_ = CreatePBRMaterial(Color(0.65, 0.72, 0.68, 1.0), 0.0, 0.75)
    -- 建筑基础色
    mat_building_base_ = CreatePBRMaterial(Color(0.55, 0.78, 0.82, 1.0), 0.0, 0.7)
    -- 障碍物
    mat_obstacle_block_ = CreatePBRMaterial(Color(0.95, 0.45, 0.35, 1.0), 0.1, 0.6)
    mat_obstacle_low_   = CreatePBRMaterial(Color(0.95, 0.75, 0.25, 1.0), 0.0, 0.7)
    mat_obstacle_high_  = CreatePBRMaterial(Color(0.85, 0.35, 0.75, 1.0), 0.1, 0.6)
    -- 取件点 - 绿色
    mat_pickup_ = CreatePBRMaterial(Color(0.3, 0.9, 0.4, 1.0), 0.2, 0.5)
    -- 送件点 - 金色
    mat_delivery_ = CreatePBRMaterial(Color(1.0, 0.85, 0.2, 1.0), 0.3, 0.4)
    -- 方向箭头
    mat_arrow_ = CreatePBRMaterial(Color(0.2, 0.9, 1.0, 1.0), 0.3, 0.4)
    -- 十字路口平台
    mat_crossroads_ = CreatePBRMaterial(Color(0.78, 0.80, 0.76, 1.0), 0.0, 0.85)
end

-- ============================================================================
-- 道路池（朝向感知）
-- ============================================================================

local function CreateOneRoadSegment()
    local seg = {}
    -- 主路面
    local roadNode = scene_:CreateChild("Road")
    local model = roadNode:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mat_road_
    roadNode.scale = Vector3(CONFIG.ROAD_WIDTH, 0.15, CONFIG.ROAD_SEGMENT_LENGTH)
    seg.road = roadNode

    -- 路缘石左
    local curbL = scene_:CreateChild("CurbL")
    local cm = curbL:CreateComponent("StaticModel")
    cm.model = cache:GetResource("Model", "Models/Box.mdl")
    cm.material = mat_curb_
    curbL.scale = Vector3(0.3, 0.35, CONFIG.ROAD_SEGMENT_LENGTH)
    seg.curbL = curbL

    -- 路缘石右
    local curbR = scene_:CreateChild("CurbR")
    local cm2 = curbR:CreateComponent("StaticModel")
    cm2.model = cache:GetResource("Model", "Models/Box.mdl")
    cm2.material = mat_curb_
    curbR.scale = Vector3(0.3, 0.35, CONFIG.ROAD_SEGMENT_LENGTH)
    seg.curbR = curbR

    -- 人行道左
    local swL = scene_:CreateChild("SidewalkL")
    local sm = swL:CreateComponent("StaticModel")
    sm.model = cache:GetResource("Model", "Models/Box.mdl")
    sm.material = mat_sidewalk_
    swL.scale = Vector3(2.5, 0.12, CONFIG.ROAD_SEGMENT_LENGTH)
    seg.swL = swL

    -- 人行道右
    local swR = scene_:CreateChild("SidewalkR")
    local sm2 = swR:CreateComponent("StaticModel")
    sm2.model = cache:GetResource("Model", "Models/Box.mdl")
    sm2.material = mat_sidewalk_
    swR.scale = Vector3(2.5, 0.12, CONFIG.ROAD_SEGMENT_LENGTH)
    seg.swR = swR

    -- 存储路段的路程距离（中心点对应的 pathDist）
    seg.pathDist = 0.0
    seg.active = false

    return seg
end

--- 将路段移动到指定路程距离的世界位置
local function PositionRoadSegment(seg, pathDist)
    seg.pathDist = pathDist
    seg.active = true
    local fwd = GetForwardVector(currentHeading_)
    local right = GetRightVector(currentHeading_)
    local localDist = pathDist - currentSegmentStartDist_
    local cx = currentSegmentOrigin_.x + fwd.x * localDist
    local cz = currentSegmentOrigin_.z + fwd.z * localDist

    -- 根据朝向设置路段旋转
    local yaw = HeadingToYaw(currentHeading_)

    seg.road.position = Vector3(cx, 0.075, cz)
    seg.road.rotation = Quaternion(yaw, Vector3.UP)

    local halfRoad = CONFIG.ROAD_WIDTH * 0.5
    seg.curbL.position = Vector3(cx + right.x * (halfRoad + 0.15), 0.175, cz + right.z * (halfRoad + 0.15))
    seg.curbL.rotation = Quaternion(yaw, Vector3.UP)
    seg.curbR.position = Vector3(cx - right.x * (halfRoad + 0.15), 0.175, cz - right.z * (halfRoad + 0.15))
    seg.curbR.rotation = Quaternion(yaw, Vector3.UP)

    seg.swL.position = Vector3(cx + right.x * (halfRoad + 1.55), 0.06, cz + right.z * (halfRoad + 1.55))
    seg.swL.rotation = Quaternion(yaw, Vector3.UP)
    seg.swR.position = Vector3(cx - right.x * (halfRoad + 1.55), 0.06, cz - right.z * (halfRoad + 1.55))
    seg.swR.rotation = Quaternion(yaw, Vector3.UP)
end

local function InitRoadPool()
    for i = 1, CONFIG.ROAD_SEGMENTS do
        local seg = CreateOneRoadSegment()
        local dist = (i - 1) * CONFIG.ROAD_SEGMENT_LENGTH
        PositionRoadSegment(seg, dist)
        roadPool_[i] = seg
    end
end

-- ============================================================================
-- 车道线池
-- ============================================================================

local function CreateOneLaneLine()
    local item = {}
    -- 左车道线（X=-1.0 相对于道路中心）
    local nodeL = scene_:CreateChild("LineL")
    local mL = nodeL:CreateComponent("StaticModel")
    mL.model = cache:GetResource("Model", "Models/Box.mdl")
    mL.material = mat_laneLine_
    nodeL.scale = Vector3(0.12, 0.05, CONFIG.LINE_LENGTH)
    item.nodeL = nodeL

    -- 右车道线（X=+1.0 相对于道路中心）
    local nodeR = scene_:CreateChild("LineR")
    local mR = nodeR:CreateComponent("StaticModel")
    mR.model = cache:GetResource("Model", "Models/Box.mdl")
    mR.material = mat_laneLine_
    nodeR.scale = Vector3(0.12, 0.05, CONFIG.LINE_LENGTH)
    item.nodeR = nodeR

    item.pathDist = 0.0
    item.active = false
    return item
end

local function PositionLaneLine(item, pathDist)
    item.pathDist = pathDist
    item.active = true
    local fwd = GetForwardVector(currentHeading_)
    local right = GetRightVector(currentHeading_)
    local localDist = pathDist - currentSegmentStartDist_
    local cx = currentSegmentOrigin_.x + fwd.x * localDist
    local cz = currentSegmentOrigin_.z + fwd.z * localDist
    local yaw = HeadingToYaw(currentHeading_)

    -- 左线偏移 -1.0（相对右方向取反）
    item.nodeL.position = Vector3(cx - right.x * 1.0, 0.16, cz - right.z * 1.0)
    item.nodeL.rotation = Quaternion(yaw, Vector3.UP)
    -- 右线偏移 +1.0
    item.nodeR.position = Vector3(cx + right.x * 1.0, 0.16, cz + right.z * 1.0)
    item.nodeR.rotation = Quaternion(yaw, Vector3.UP)
end

local function InitLinePool()
    for i = 1, CONFIG.LINE_POOL_SIZE do
        local item = CreateOneLaneLine()
        local dist = (i - 1) * CONFIG.LINE_SPACING
        PositionLaneLine(item, dist)
        linePool_[i] = item
    end
end

-- ============================================================================
-- 建筑池
-- ============================================================================

local buildingColors_ = {
    Color(0.55, 0.78, 0.82, 1.0),  -- 蓝绿
    Color(0.75, 0.85, 0.60, 1.0),  -- 黄绿
    Color(0.90, 0.75, 0.55, 1.0),  -- 暖橙
    Color(0.70, 0.65, 0.85, 1.0),  -- 淡紫
    Color(0.85, 0.60, 0.65, 1.0),  -- 粉红
    Color(0.60, 0.80, 0.70, 1.0),  -- 薄荷
}

local function CreateOneBuilding()
    local item = {}
    local node = scene_:CreateChild("Building")
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")

    local colorIdx = math.random(1, #buildingColors_)
    local mat = CreatePBRMaterial(buildingColors_[colorIdx], 0.0, 0.7)
    model.material = mat

    local h = math.random() * 8 + 3
    local w = math.random() * 2 + 1.5
    local d = math.random() * 2 + 1.5
    node.scale = Vector3(w, h, d)

    item.node = node
    item.height = h
    item.pathDist = 0.0
    item.side = 1  -- 1=右侧, -1=左侧
    item.lateralOffset = 0.0
    item.active = false
    return item
end

local function PositionBuilding(item, pathDist, side, lateralOffset)
    item.pathDist = pathDist
    item.side = side
    item.lateralOffset = lateralOffset
    item.active = true

    local fwd = GetForwardVector(currentHeading_)
    local right = GetRightVector(currentHeading_)
    local localDist = pathDist - currentSegmentStartDist_
    local cx = currentSegmentOrigin_.x + fwd.x * localDist
    local cz = currentSegmentOrigin_.z + fwd.z * localDist
    local yaw = HeadingToYaw(currentHeading_)

    local offset = side * lateralOffset
    local px = cx + right.x * offset
    local pz = cz + right.z * offset

    item.node.position = Vector3(px, item.height * 0.5, pz)
    item.node.rotation = Quaternion(yaw + math.random(-10, 10), Vector3.UP)
end

local function InitBuildingPool()
    for i = 1, CONFIG.BUILDING_POOL_SIZE do
        local item = CreateOneBuilding()
        local dist = (i - 1) * 8.0
        local side = (i % 2 == 0) and 1 or -1
        local lateral = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
        PositionBuilding(item, dist, side, lateral)
        buildingPool_[i] = item
    end
end

-- ============================================================================
-- 障碍物池
-- ============================================================================

local obstacleTypes_ = {
    { name = "block", scaleY = 1.2, offsetY = 0.6, jumpable = false, slidable = false },
    { name = "low",   scaleY = 0.4, offsetY = 0.2, jumpable = true,  slidable = false },
    { name = "high",  scaleY = 1.0, offsetY = 1.5, jumpable = false, slidable = true  },
}

local function CreateOneObstacle(typeIdx)
    local info = obstacleTypes_[typeIdx]
    local node = scene_:CreateChild("Obstacle_" .. info.name)
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")

    if typeIdx == 1 then model.material = mat_obstacle_block_
    elseif typeIdx == 2 then model.material = mat_obstacle_low_
    else model.material = mat_obstacle_high_ end

    node.scale = Vector3(1.4, info.scaleY, 0.6)
    node.position = Vector3(0, -100, 0) -- 隐藏

    return {
        node = node,
        typeIdx = typeIdx,
        info = info,
        pathDist = 0.0,
        lane = 2,
        active = false,
    }
end

local function InitObstaclePool()
    for t = 1, #obstacleTypes_ do
        for i = 1, CONFIG.OBSTACLE_POOL_PER_TYPE do
            local obs = CreateOneObstacle(t)
            table.insert(obstaclePool_, obs)
        end
    end
end

local function GetInactiveObstacle(typeIdx)
    for _, obs in ipairs(obstaclePool_) do
        if not obs.active and obs.typeIdx == typeIdx then
            return obs
        end
    end
    return nil
end

--- 计算某个路程距离附近的障碍物密度（公平性检测）
local function CountObstaclesNearDist(pathDist, range)
    local count = 0
    for _, obs in ipairs(activeObstacles_) do
        if math.abs(obs.pathDist - pathDist) < range then
            count = count + 1
        end
    end
    return count
end

--- 指定车道在路程距离附近是否太密集
local function IsLaneTooDense(lane, pathDist)
    for _, obs in ipairs(activeObstacles_) do
        if obs.lane == lane and math.abs(obs.pathDist - pathDist) < CONFIG.OBSTACLE_MIN_SPACING * 0.6 then
            return true
        end
    end
    return false
end

--- 获取当前难度因子 [0, 1]
local function GetDifficultyFactor()
    local d = math.max(0, distanceTraveled_ - CONFIG.DIFFICULTY_START_DISTANCE)
    return math.min(1.0, d / CONFIG.DIFFICULTY_RAMP_DISTANCE)
end

--- 获取当前生成间距
local function GetCurrentSpacing()
    local factor = GetDifficultyFactor()
    return CONFIG.OBSTACLE_SPACING_MAX - (CONFIG.OBSTACLE_SPACING_MAX - CONFIG.OBSTACLE_SPACING_MIN) * factor
end

--- 放置障碍物到世界
local function PositionObstacle(obs, pathDist, lane)
    obs.pathDist = pathDist
    obs.lane = lane
    obs.active = true

    local laneX = CONFIG.LANE_X[lane]
    local worldPos = GetWorldPosForObject(pathDist, laneX)
    obs.node.position = Vector3(worldPos.x, obs.info.offsetY, worldPos.z)
    obs.node.rotation = Quaternion(HeadingToYaw(currentHeading_), Vector3.UP)
end

--- 尝试生成障碍物
local function SpawnObstacles()
    local spawnAhead = routeDistance_ + CONFIG.OBSTACLE_SPAWN_AHEAD
    local spacing = GetCurrentSpacing()

    while lastObstacleSpawnDist_ + spacing < spawnAhead do
        local spawnDist = lastObstacleSpawnDist_ + spacing
        lastObstacleSpawnDist_ = spawnDist

        -- 安全区检查
        if IsInSafeZone(spawnDist) then
            goto continue_spawn
        end

        -- 公平性检查
        if CountObstaclesNearDist(spawnDist, spacing * 0.7) >= CONFIG.OBSTACLE_MAX_PER_ROW then
            goto continue_spawn
        end

        -- 确定本行生成几个障碍（难度越高越多）
        local numObs = 1
        if GetDifficultyFactor() > 0.3 and math.random() < 0.4 then
            numObs = 2
        end

        -- 选择车道
        local lanes = {1, 2, 3}
        -- 打乱顺序
        for i = #lanes, 2, -1 do
            local j = math.random(1, i)
            lanes[i], lanes[j] = lanes[j], lanes[i]
        end

        local placed = 0
        for _, lane in ipairs(lanes) do
            if placed >= numObs then break end
            if IsLaneTooDense(lane, spawnDist) then goto next_lane end

            -- 随机选类型
            local typeIdx = math.random(1, #obstacleTypes_)
            local obs = GetInactiveObstacle(typeIdx)
            if not obs then
                -- 任意类型
                obs = GetInactiveObstacle(1) or GetInactiveObstacle(2) or GetInactiveObstacle(3)
            end
            if obs then
                PositionObstacle(obs, spawnDist, lane)
                table.insert(activeObstacles_, obs)
                placed = placed + 1
            end

            ::next_lane::
        end

        ::continue_spawn::
    end
end

-- ============================================================================
-- 取件点
-- ============================================================================

local function CreatePickupNode()
    local node = scene_:CreateChild("Pickup")
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mat_pickup_
    node.scale = Vector3(0.8, 0.8, 0.8)
    node.position = Vector3(0, -100, 0)
    return node
end

local function TrySpawnPickup()
    if pickupActive_ or hasPackage_ then return end
    if routeDistance_ < nextPickupDist_ then return end

    local spawnDist = routeDistance_ + CONFIG.PICKUP_SPAWN_AHEAD
    if IsInSafeZone(spawnDist) then return end

    local lane = math.random(1, 3)
    pickupPathDist_ = spawnDist
    pickupLane_ = lane
    pickupActive_ = true

    local laneX = CONFIG.LANE_X[lane]
    local worldPos = GetWorldPosForObject(spawnDist, laneX)
    pickupNode_.position = Vector3(worldPos.x, 0.6, worldPos.z)
    pickupNode_.rotation = Quaternion(HeadingToYaw(currentHeading_), Vector3.UP)

    lastPickupDist_ = spawnDist
    nextPickupDist_ = spawnDist + CONFIG.PICKUP_INTERVAL_MIN + math.random() * (CONFIG.PICKUP_INTERVAL_MAX - CONFIG.PICKUP_INTERVAL_MIN)
end

local function CheckPickup()
    if not pickupActive_ then return end
    local distDiff = routeDistance_ - pickupPathDist_
    if math.abs(distDiff) < CONFIG.COLLISION_Z_THRESHOLD and CONFIG.currentLane == pickupLane_ then
        -- 拾取成功
        hasPackage_ = true
        pickupActive_ = false
        pickupNode_.position = Vector3(0, -100, 0)
        if packageVisualNode_ then
            packageVisualNode_.enabled = true
        end
        -- 生成送件点
        nextDeliveryDist_ = routeDistance_ + CONFIG.DELIVERY_INTERVAL_MIN * 0.5
    elseif distDiff > 3.0 then
        -- 错过了
        pickupActive_ = false
        pickupNode_.position = Vector3(0, -100, 0)
    end
end

-- ============================================================================
-- 送件点
-- ============================================================================

local function CreateDeliveryNode()
    local node = scene_:CreateChild("Delivery")
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mat_delivery_
    node.scale = Vector3(1.0, 0.3, 1.0)
    node.position = Vector3(0, -100, 0)
    return node
end

local function TrySpawnDelivery()
    if deliveryActive_ or not hasPackage_ then return end
    if routeDistance_ < nextDeliveryDist_ then return end

    local spawnDist = routeDistance_ + CONFIG.DELIVERY_SPAWN_AHEAD
    if IsInSafeZone(spawnDist) then return end

    local lane = math.random(1, 3)
    deliveryPathDist_ = spawnDist
    deliveryLane_ = lane
    deliveryActive_ = true

    local laneX = CONFIG.LANE_X[lane]
    local worldPos = GetWorldPosForObject(spawnDist, laneX)
    deliveryNode_.position = Vector3(worldPos.x, 0.15, worldPos.z)
    deliveryNode_.rotation = Quaternion(HeadingToYaw(currentHeading_), Vector3.UP)

    lastDeliveryDist_ = spawnDist
    nextDeliveryDist_ = spawnDist + CONFIG.DELIVERY_INTERVAL_MIN + math.random() * (CONFIG.DELIVERY_INTERVAL_MAX - CONFIG.DELIVERY_INTERVAL_MIN)

    -- 设置推荐方向（影响路口奖励判断）
    intersectionCorrectDir_ = (lane <= 1) and -1 or ((lane >= 3) and 1 or 0)
end

local function CheckDelivery()
    if not deliveryActive_ then return end
    local distDiff = routeDistance_ - deliveryPathDist_
    if math.abs(distDiff) < CONFIG.COLLISION_Z_THRESHOLD and CONFIG.currentLane == deliveryLane_ then
        -- 送达成功
        comboCount_ = comboCount_ + 1
        local baseReward = 10
        local comboBonus = math.floor(comboCount_ * CONFIG.DELIVERY_COMBO_MULTIPLIER)
        local reward = baseReward + comboBonus
        totalIncome_ = totalIncome_ + reward
        timeRemaining_ = timeRemaining_ + 3.0

        hasPackage_ = false
        deliveryActive_ = false
        deliveryNode_.position = Vector3(0, -100, 0)
        if packageVisualNode_ then
            packageVisualNode_.enabled = false
        end
    elseif distDiff > 3.0 then
        -- 错过送件点
        comboCount_ = 0
        deliveryActive_ = false
        deliveryNode_.position = Vector3(0, -100, 0)
    end
end

-- ============================================================================
-- 路口系统（真实转弯）
-- ============================================================================

--- 创建十字路口视觉节点
local function CreateCrossroadsVisuals()
    -- 十字路口平台
    crossroadsNode_ = scene_:CreateChild("Crossroads")
    local model = crossroadsNode_:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = mat_crossroads_
    crossroadsNode_.scale = Vector3(PATH.CROSSROADS_SIZE, 0.16, PATH.CROSSROADS_SIZE)
    crossroadsNode_.position = Vector3(0, -100, 0)

    -- 预览路段（左/右/直 三个方向）
    for i = 1, 3 do
        local pNode = scene_:CreateChild("PreviewRoad" .. i)
        local pm = pNode:CreateComponent("StaticModel")
        pm.model = cache:GetResource("Model", "Models/Box.mdl")
        pm.material = mat_road_
        pNode.scale = Vector3(CONFIG.ROAD_WIDTH, 0.14, PATH.PREVIEW_ROAD_LENGTH)
        pNode.position = Vector3(0, -100, 0)
        previewRoadNodes_[i] = pNode
    end

    -- 方向箭头（左/右/直）
    for i = 1, 3 do
        local aNode = scene_:CreateChild("Arrow" .. i)
        local am = aNode:CreateComponent("StaticModel")
        am.model = cache:GetResource("Model", "Models/Cone.mdl")
        am.material = mat_arrow_
        aNode.scale = Vector3(1.0, 0.3, 1.5)
        aNode.position = Vector3(0, -100, 0)
        arrowNodes_[i] = aNode
    end
end

--- 显示路口视觉
local function ShowIntersection()
    if not crossroadsNode_ then return end

    -- 计算路口世界位置
    local intLocalDist = nextIntersectionDist_ - currentSegmentStartDist_
    local fwd = GetForwardVector(currentHeading_)
    local right = GetRightVector(currentHeading_)
    local intX = currentSegmentOrigin_.x + fwd.x * intLocalDist
    local intZ = currentSegmentOrigin_.z + fwd.z * intLocalDist

    turnWorldPos_ = Vector3(intX, 0, intZ)

    -- 十字路口平台
    crossroadsNode_.position = Vector3(intX, 0.08, intZ)
    crossroadsNode_.rotation = Quaternion(HeadingToYaw(currentHeading_), Vector3.UP)

    -- 三个预览路段：直/左/右
    local previewOffset = PATH.CROSSROADS_SIZE * 0.5 + PATH.PREVIEW_ROAD_LENGTH * 0.5

    -- 直走
    local straightFwd = fwd
    previewRoadNodes_[1].position = Vector3(
        intX + straightFwd.x * previewOffset,
        0.07,
        intZ + straightFwd.z * previewOffset
    )
    previewRoadNodes_[1].rotation = Quaternion(HeadingToYaw(currentHeading_), Vector3.UP)

    -- 左转（heading - 1）
    local leftHeading = (currentHeading_ + 3) % 4
    local leftFwd = GetForwardVector(leftHeading)
    previewRoadNodes_[2].position = Vector3(
        intX + leftFwd.x * previewOffset,
        0.07,
        intZ + leftFwd.z * previewOffset
    )
    previewRoadNodes_[2].rotation = Quaternion(HeadingToYaw(leftHeading), Vector3.UP)

    -- 右转（heading + 1）
    local rightHeading = (currentHeading_ + 1) % 4
    local rightFwd = GetForwardVector(rightHeading)
    previewRoadNodes_[3].position = Vector3(
        intX + rightFwd.x * previewOffset,
        0.07,
        intZ + rightFwd.z * previewOffset
    )
    previewRoadNodes_[3].rotation = Quaternion(HeadingToYaw(rightHeading), Vector3.UP)

    -- 箭头
    local arrowDist = PATH.CROSSROADS_SIZE * 0.3
    -- 直走箭头
    arrowNodes_[1].position = Vector3(intX + fwd.x * arrowDist, 0.5, intZ + fwd.z * arrowDist)
    arrowNodes_[1].rotation = Quaternion(HeadingToYaw(currentHeading_) - 90, Vector3.UP)

    -- 左箭头
    arrowNodes_[2].position = Vector3(intX + leftFwd.x * arrowDist, 0.5, intZ + leftFwd.z * arrowDist)
    arrowNodes_[2].rotation = Quaternion(HeadingToYaw(leftHeading) - 90, Vector3.UP)

    -- 右箭头
    arrowNodes_[3].position = Vector3(intX + rightFwd.x * arrowDist, 0.5, intZ + rightFwd.z * arrowDist)
    arrowNodes_[3].rotation = Quaternion(HeadingToYaw(rightHeading) - 90, Vector3.UP)
end

--- 隐藏路口视觉
local function HideIntersection()
    if crossroadsNode_ then
        crossroadsNode_.position = Vector3(0, -100, 0)
    end
    for i = 1, 3 do
        if previewRoadNodes_[i] then
            previewRoadNodes_[i].position = Vector3(0, -100, 0)
        end
        if arrowNodes_[i] then
            arrowNodes_[i].position = Vector3(0, -100, 0)
        end
    end
end

--- 安排下一个路口
local function ScheduleNextIntersection()
    local interval = PATH.INTERVAL_MIN + math.random() * (PATH.INTERVAL_MAX - PATH.INTERVAL_MIN)
    nextIntersectionDist_ = routeDistance_ + interval
    intersectionActive_ = false
    turnChoice_ = 0
end

--- 执行转弯：立即改变朝向，启动动画
local function ExecuteTurn(turnDir)
    -- turnDir: -1=左转, 1=右转, 0=直走
    if turnDir == 0 then
        -- 直走，不改变方向，直接继续
        HideIntersection()
        ScheduleNextIntersection()

        -- 奖惩判断
        if intersectionCorrectDir_ == 0 then
            timeRemaining_ = timeRemaining_ + PATH.CORRECT_TURN_BONUS
        else
            timeRemaining_ = math.max(2.0, timeRemaining_ - PATH.WRONG_TURN_PENALTY)
        end
        return
    end

    -- 计算新朝向
    turnFromHeading_ = currentHeading_
    if turnDir == 1 then
        -- 右转
        turnToHeading_ = (currentHeading_ + 1) % 4
    else
        -- 左转
        turnToHeading_ = (currentHeading_ + 3) % 4
    end

    -- 记录转弯点信息
    local intLocalDist = nextIntersectionDist_ - currentSegmentStartDist_
    local fwd = GetForwardVector(currentHeading_)
    local intX = currentSegmentOrigin_.x + fwd.x * intLocalDist
    local intZ = currentSegmentOrigin_.z + fwd.z * intLocalDist
    turnWorldPos_ = Vector3(intX, 0, intZ)

    -- 立即更新路径系统
    currentHeading_ = turnToHeading_
    currentSegmentOrigin_ = Vector3(turnWorldPos_.x, 0, turnWorldPos_.z)
    currentSegmentStartDist_ = nextIntersectionDist_

    -- 启动转弯动画
    turnExecuting_ = true
    turnAnimTime_ = 0.0

    -- 启动摄像机转弯动画
    camTurning_ = true
    camTurnAnimTime_ = 0.0
    camTurnFrom_ = HeadingToYaw(turnFromHeading_)
    camTurnTo_ = HeadingToYaw(turnToHeading_)

    -- 处理角度差（选最短路径）
    local diff = camTurnTo_ - camTurnFrom_
    if diff > 180 then camTurnTo_ = camTurnTo_ - 360
    elseif diff < -180 then camTurnTo_ = camTurnTo_ + 360 end

    -- 隐藏路口视觉
    HideIntersection()

    -- 重新定位所有已有的路段/线/建筑
    -- 沿新方向重新铺设道路
    for i = 1, CONFIG.ROAD_SEGMENTS do
        local dist = currentSegmentStartDist_ + (i - 1) * CONFIG.ROAD_SEGMENT_LENGTH
        PositionRoadSegment(roadPool_[i], dist)
    end
    for i = 1, CONFIG.LINE_POOL_SIZE do
        local dist = currentSegmentStartDist_ + (i - 1) * CONFIG.LINE_SPACING
        PositionLaneLine(linePool_[i], dist)
    end
    for i = 1, CONFIG.BUILDING_POOL_SIZE do
        local item = buildingPool_[i]
        local dist = currentSegmentStartDist_ + (i - 1) * 8.0
        local side = (i % 2 == 0) and 1 or -1
        local lateral = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
        PositionBuilding(item, dist, side, lateral)
    end

    -- 清除所有活跃障碍物（转弯后重新生成）
    for _, obs in ipairs(activeObstacles_) do
        obs.active = false
        obs.node.position = Vector3(0, -100, 0)
    end
    activeObstacles_ = {}
    lastObstacleSpawnDist_ = currentSegmentStartDist_ + PATH.SAFE_ZONE_AFTER

    -- 隐藏取件/送件（如果在视野外）
    if pickupActive_ and pickupPathDist_ < currentSegmentStartDist_ then
        pickupActive_ = false
        pickupNode_.position = Vector3(0, -100, 0)
    end
    if deliveryActive_ and deliveryPathDist_ < currentSegmentStartDist_ then
        deliveryActive_ = false
        deliveryNode_.position = Vector3(0, -100, 0)
    end

    -- 安排下一个路口
    ScheduleNextIntersection()

    -- 奖惩判断
    if intersectionCorrectDir_ == turnDir then
        timeRemaining_ = timeRemaining_ + PATH.CORRECT_TURN_BONUS
    else
        timeRemaining_ = math.max(2.0, timeRemaining_ - PATH.WRONG_TURN_PENALTY)
    end
end

--- 更新路口逻辑（每帧调用）
local function UpdateIntersection()
    if turnExecuting_ then return end
    if nextIntersectionDist_ <= 0 then return end

    local distToInt = nextIntersectionDist_ - routeDistance_

    -- 进入输入窗口：显示路口
    if distToInt < PATH.TURN_INPUT_WINDOW and distToInt > 0 and not intersectionActive_ then
        intersectionActive_ = true
        ShowIntersection()

        -- 随机推荐方向
        local r = math.random()
        if r < 0.33 then intersectionHintDir_ = -1
        elseif r < 0.66 then intersectionHintDir_ = 1
        else intersectionHintDir_ = 0 end
    end

    -- 到达路口执行点
    if distToInt <= PATH.TURN_EXECUTE_DIST and intersectionActive_ then
        intersectionActive_ = false
        ExecuteTurn(turnChoice_)
        turnChoice_ = 0
    end
end

--- 更新转弯动画（玩家模型旋转）
local function UpdateTurnAnimation(dt)
    if not turnExecuting_ then return end

    turnAnimTime_ = turnAnimTime_ + dt
    local t = math.min(1.0, turnAnimTime_ / PATH.TURN_ANIM_DURATION)

    -- 使用平滑插值
    local smoothT = t * t * (3.0 - 2.0 * t)

    -- 玩家模型旋转
    local fromYaw = HeadingToYaw(turnFromHeading_)
    local toYaw = HeadingToYaw(turnToHeading_)
    local diff = toYaw - fromYaw
    if diff > 180 then toYaw = toYaw - 360
    elseif diff < -180 then toYaw = toYaw + 360 end

    local currentYaw = fromYaw + (toYaw - fromYaw) * smoothT
    playerNode_.rotation = Quaternion(currentYaw, Vector3.UP)

    if t >= 1.0 then
        turnExecuting_ = false
        playerNode_.rotation = Quaternion(HeadingToYaw(currentHeading_), Vector3.UP)
    end
end

-- ============================================================================
-- 碰撞检测
-- ============================================================================

local function CheckCollisions()
    local playerDist = routeDistance_
    local playerLane = CONFIG.currentLane

    for idx = #activeObstacles_, 1, -1 do
        local obs = activeObstacles_[idx]
        local distDiff = math.abs(playerDist - obs.pathDist)

        if distDiff < CONFIG.COLLISION_Z_THRESHOLD and obs.lane == playerLane then
            -- 检查是否可以通过（跳跃/下滑）
            local canPass = false
            if obs.info.jumpable and isJumping_ and jumpTime_ > 0.1 then
                canPass = true
            end
            if obs.info.slidable and isSliding_ and slideTime_ > 0.05 then
                canPass = true
            end

            if not canPass then
                return true -- 碰撞！
            end
        end
    end
    return false
end

-- ============================================================================
-- 速度系统
-- ============================================================================

local function UpdateSpeed()
    local speedIncrease = distanceTraveled_ / CONFIG.SPEED_DISTANCE_FACTOR
    currentSpeed_ = math.min(CONFIG.MAX_SPEED, CONFIG.BASE_SPEED + speedIncrease)
end

-- ============================================================================
-- 游戏结束
-- ============================================================================

local function GameOver()
    gameState_ = "gameOver"
    if gameOverPanel_ then
        gameOverPanel_:SetVisible(true)
        if lblFinalIncome_ then
            lblFinalIncome_:SetText("收入: ¥" .. totalIncome_)
        end
        if lblFinalDist_ then
            lblFinalDist_:SetText("距离: " .. math.floor(distanceTraveled_) .. "m")
        end
    end
end

-- ============================================================================
-- 重新开始
-- ============================================================================

local function RestartGame()
    gameState_ = "running"

    -- 重置路径系统
    routeDistance_ = 0.0
    currentHeading_ = PATH.HEADING_POS_Z
    currentSegmentOrigin_ = Vector3(0, 0, 0)
    currentSegmentStartDist_ = 0.0
    nextIntersectionDist_ = PATH.FIRST_INTERSECTION_DIST
    intersectionActive_ = false
    turnChoice_ = 0
    turnExecuting_ = false
    camTurning_ = false
    HideIntersection()

    -- 重置游戏状态
    distanceTraveled_ = 0.0
    currentSpeed_ = CONFIG.BASE_SPEED
    CONFIG.currentLane = 2
    lastObstacleSpawnDist_ = 0.0

    -- 重置变道/跳跃/下滑
    laneChanging_ = false
    isJumping_ = false
    jumpTime_ = 0.0
    jumpBuffered_ = false
    isSliding_ = false
    slideTime_ = 0.0
    slideBuffered_ = false

    -- 重置取件/送件
    pickupActive_ = false
    pickupNode_.position = Vector3(0, -100, 0)
    deliveryActive_ = false
    deliveryNode_.position = Vector3(0, -100, 0)
    hasPackage_ = false
    if packageVisualNode_ then packageVisualNode_.enabled = false end
    lastPickupDist_ = 0.0
    nextPickupDist_ = 30.0
    lastDeliveryDist_ = 0.0
    nextDeliveryDist_ = 100.0

    -- 重置计时/收入/连击
    timeRemaining_ = 30.0
    totalIncome_ = 0
    comboCount_ = 0

    -- 重新定位玩家
    playerNode_.position = Vector3(0, 0, 0)
    playerNode_.rotation = Quaternion(0, Vector3.UP)

    -- 重新定位路段
    for i = 1, CONFIG.ROAD_SEGMENTS do
        local dist = (i - 1) * CONFIG.ROAD_SEGMENT_LENGTH
        PositionRoadSegment(roadPool_[i], dist)
    end
    for i = 1, CONFIG.LINE_POOL_SIZE do
        local dist = (i - 1) * CONFIG.LINE_SPACING
        PositionLaneLine(linePool_[i], dist)
    end
    for i = 1, CONFIG.BUILDING_POOL_SIZE do
        local item = buildingPool_[i]
        local dist = (i - 1) * 8.0
        local side = (i % 2 == 0) and 1 or -1
        local lateral = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
        PositionBuilding(item, dist, side, lateral)
    end

    -- 清除障碍
    for _, obs in ipairs(activeObstacles_) do
        obs.active = false
        obs.node.position = Vector3(0, -100, 0)
    end
    activeObstacles_ = {}

    -- 隐藏结算面板
    if gameOverPanel_ then
        gameOverPanel_:SetVisible(false)
    end
end

-- ============================================================================
-- 创建玩家
-- ============================================================================

local function CreatePlayer()
    playerNode_ = scene_:CreateChild("Player")
    playerNode_.position = Vector3(0, 0, 0)

    -- 身体（圆柱）
    local body = playerNode_:CreateChild("Body")
    local bm = body:CreateComponent("StaticModel")
    bm.model = cache:GetResource("Model", "Models/Cylinder.mdl")
    bm.material = CreatePBRMaterial(Color(0.3, 0.6, 0.9, 1.0), 0.1, 0.6)
    body.scale = Vector3(0.6, 1.0, 0.6)
    body.position = Vector3(0, 0.5, 0)

    -- 头（球）
    local head = playerNode_:CreateChild("Head")
    local hm = head:CreateComponent("StaticModel")
    hm.model = cache:GetResource("Model", "Models/Sphere.mdl")
    hm.material = CreatePBRMaterial(Color(1.0, 0.85, 0.7, 1.0), 0.0, 0.8)
    head.scale = Vector3(0.45, 0.45, 0.45)
    head.position = Vector3(0, 1.25, 0)

    -- 外卖箱（背上的方块）
    local box = playerNode_:CreateChild("DeliveryBox")
    local boxm = box:CreateComponent("StaticModel")
    boxm.model = cache:GetResource("Model", "Models/Box.mdl")
    boxm.material = CreatePBRMaterial(Color(0.2, 0.7, 0.3, 1.0), 0.1, 0.7)
    box.scale = Vector3(0.5, 0.5, 0.3)
    box.position = Vector3(0, 0.9, -0.3)
    packageVisualNode_ = box
    packageVisualNode_.enabled = false

    -- 帽子
    local hat = playerNode_:CreateChild("Hat")
    local hatm = hat:CreateComponent("StaticModel")
    hatm.model = cache:GetResource("Model", "Models/Cylinder.mdl")
    hatm.material = CreatePBRMaterial(Color(1.0, 0.8, 0.1, 1.0), 0.0, 0.7)
    hat.scale = Vector3(0.5, 0.12, 0.5)
    hat.position = Vector3(0, 1.5, 0)
end

-- ============================================================================
-- 摄像机
-- ============================================================================

local function SetupCamera()
    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.fov = CONFIG.CAM_FOV_BASE
    camera.nearClip = 0.5
    camera.farClip = 200.0

    renderer:SetViewport(0, Viewport:new(scene_, camera))

    -- 初始位置
    local pp = playerNode_.position
    cameraNode_.position = Vector3(pp.x, pp.y + CONFIG.CAM_OFFSET_Y, pp.z + CONFIG.CAM_OFFSET_Z)
    local lookTarget = Vector3(pp.x, pp.y + 0.5, pp.z + CONFIG.CAM_LOOK_AHEAD)
    cameraNode_:LookAt(lookTarget)
end

local function UpdateCamera(dt)
    if not playerNode_ or not cameraNode_ then return end

    local pp = playerNode_.position

    -- 计算摄像机当前的 yaw
    local targetYaw = HeadingToYaw(currentHeading_)
    local currentYaw = targetYaw

    if camTurning_ then
        camTurnAnimTime_ = camTurnAnimTime_ + dt
        local t = math.min(1.0, camTurnAnimTime_ / PATH.CAM_TURN_DURATION)
        local smoothT = t * t * (3.0 - 2.0 * t)
        currentYaw = camTurnFrom_ + (camTurnTo_ - camTurnFrom_) * smoothT
        if t >= 1.0 then
            camTurning_ = false
            currentYaw = camTurnTo_
        end
    end

    -- 基于当前 yaw 计算偏移方向
    local yawRad = math.rad(currentYaw)
    local camFwdX = math.sin(yawRad)
    local camFwdZ = math.cos(yawRad)

    -- 摄像机目标位置（在玩家后方偏上）
    local camTargetX = pp.x - camFwdX * (-CONFIG.CAM_OFFSET_Z)
    local camTargetZ = pp.z - camFwdZ * (-CONFIG.CAM_OFFSET_Z)
    local camTargetY = pp.y + CONFIG.CAM_OFFSET_Y

    -- 平滑跟随
    local camPos = cameraNode_.position
    local lerpFactor = math.min(1.0, dt * CONFIG.CAM_SMOOTH)
    local newX = camPos.x + (camTargetX - camPos.x) * lerpFactor
    local newY = camPos.y + (camTargetY - camPos.y) * lerpFactor
    local newZ = camPos.z + (camTargetZ - camPos.z) * lerpFactor
    cameraNode_.position = Vector3(newX, newY, newZ)

    -- 注视点（玩家前方）
    local lookX = pp.x + camFwdX * CONFIG.CAM_LOOK_AHEAD
    local lookZ = pp.z + camFwdZ * CONFIG.CAM_LOOK_AHEAD
    cameraNode_:LookAt(Vector3(lookX, pp.y + 0.5, lookZ))

    -- FOV 动态调整
    local camera = cameraNode_:GetComponent("Camera")
    if camera then
        local speedFactor = (currentSpeed_ - CONFIG.BASE_SPEED) / (CONFIG.MAX_SPEED - CONFIG.BASE_SPEED)
        local targetFov = CONFIG.CAM_FOV_BASE + (CONFIG.CAM_FOV_MAX - CONFIG.CAM_FOV_BASE) * speedFactor * CONFIG.CAM_FOV_SPEED_FACTOR
        camera.fov = camera.fov + (targetFov - camera.fov) * lerpFactor
    end
end

-- ============================================================================
-- UI 创建
-- ============================================================================

local function CreateUI()
    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })

    -- HUD
    local hud = UI.Panel {
        width = "100%", height = "100%",
        children = {
            -- 顶部信息栏
            UI.Panel {
                width = "100%", height = 80,
                flexDirection = "row",
                justifyContent = "space-around",
                alignItems = "center",
                paddingTop = 10,
                children = {
                    UI.Label { id = "timer", text = "⏱ 30s", fontSize = 20, fontColor = {255,255,255,255} },
                    UI.Label { id = "income", text = "¥0", fontSize = 20, fontColor = {255,215,0,255} },
                    UI.Label { id = "combo", text = "", fontSize = 16, fontColor = {0,255,136,255} },
                    UI.Label { id = "speed", text = "8m/s", fontSize = 14, fontColor = {170,170,170,255} },
                },
            },
            -- 方向提示
            UI.Panel {
                width = "100%", height = 40,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { id = "hint", text = "", fontSize = 18, fontColor = {0,221,255,255} },
                },
            },
        },
    }
    UI.SetRoot(hud)

    -- 获取引用
    lblTimer_ = hud:FindById("timer")
    lblIncome_ = hud:FindById("income")
    lblCombo_ = hud:FindById("combo")
    lblSpeed_ = hud:FindById("speed")
    lblHint_ = hud:FindById("hint")

    -- 游戏结束面板
    gameOverPanel_ = UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = "rgba(0,0,0,0.7)",
        children = {
            UI.Panel {
                width = 280, height = 220,
                backgroundColor = "#222222",
                borderRadius = 12,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { text = "配送结束", fontSize = 22, fontColor = {255,255,255,255} },
                    UI.Label { id = "finalIncome", text = "收入: ¥0", fontSize = 18, fontColor = {255,215,0,255}, marginTop = 12 },
                    UI.Label { id = "finalDist", text = "距离: 0m", fontSize = 16, fontColor = {170,170,170,255}, marginTop = 8 },
                    UI.Button {
                        text = "再来一单",
                        variant = "primary",
                        marginTop = 20,
                        onClick = function()
                            RestartGame()
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(gameOverPanel_)
    gameOverPanel_:SetVisible(false)

    lblFinalIncome_ = gameOverPanel_:FindById("finalIncome")
    lblFinalDist_ = gameOverPanel_:FindById("finalDist")
end

-- ============================================================================
-- 回收系统
-- ============================================================================

local function RecycleObjects()
    -- 回收道路段：如果路程距离远远落后于玩家，移到前方
    local behindThreshold = routeDistance_ - CONFIG.ROAD_SEGMENT_LENGTH * 1.5
    local aheadTarget = routeDistance_ + CONFIG.ROAD_SEGMENT_LENGTH * (CONFIG.ROAD_SEGMENTS - 1)

    for _, seg in ipairs(roadPool_) do
        if seg.pathDist < behindThreshold then
            aheadTarget = aheadTarget + CONFIG.ROAD_SEGMENT_LENGTH
            PositionRoadSegment(seg, aheadTarget)
        end
    end

    -- 回收车道线
    local lineBehind = routeDistance_ - CONFIG.LINE_SPACING * 2
    local lineAhead = routeDistance_ + CONFIG.LINE_SPACING * CONFIG.LINE_POOL_SIZE * 0.8

    for _, item in ipairs(linePool_) do
        if item.pathDist < lineBehind then
            lineAhead = lineAhead + CONFIG.LINE_SPACING
            PositionLaneLine(item, lineAhead)
        end
    end

    -- 回收建筑
    local buildBehind = routeDistance_ - 20.0
    local buildAhead = routeDistance_ + 8.0 * CONFIG.BUILDING_POOL_SIZE * 0.7

    for _, item in ipairs(buildingPool_) do
        if item.pathDist < buildBehind then
            buildAhead = buildAhead + 8.0 + math.random() * 4.0
            local side = (math.random() > 0.5) and 1 or -1
            local lateral = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
            PositionBuilding(item, buildAhead, side, lateral)
        end
    end

    -- 回收障碍物
    local obsBehind = routeDistance_ - 10.0
    for idx = #activeObstacles_, 1, -1 do
        local obs = activeObstacles_[idx]
        if obs.pathDist < obsBehind then
            obs.active = false
            obs.node.position = Vector3(0, -100, 0)
            table.remove(activeObstacles_, idx)
        end
    end
end

-- ============================================================================
-- 变道动画
-- ============================================================================

local function UpdateLaneChange(dt)
    if not laneChanging_ then return end

    laneChangeTime_ = laneChangeTime_ + dt
    local t = math.min(1.0, laneChangeTime_ / CONFIG.LANE_CHANGE_DURATION)
    local smoothT = t * t * (3.0 - 2.0 * t)

    local currentX = laneChangeFrom_ + (laneChangeTo_ - laneChangeFrom_) * smoothT

    -- 更新玩家 X（相对于当前方向的右侧偏移）
    local worldPos = GetWorldPosOnTrack(routeDistance_, currentX)
    local pp = playerNode_.position
    playerNode_.position = Vector3(worldPos.x, pp.y, worldPos.z)

    if t >= 1.0 then
        laneChanging_ = false
    end
end

local function StartLaneChange(targetLane)
    if laneChanging_ then return end
    if targetLane < 1 or targetLane > 3 then return end

    laneChangeFrom_ = CONFIG.LANE_X[CONFIG.currentLane]
    laneChangeTo_ = CONFIG.LANE_X[targetLane]
    CONFIG.currentLane = targetLane
    laneChangeTime_ = 0.0
    laneChanging_ = true
end

-- ============================================================================
-- 跳跃 / 下滑
-- ============================================================================

local function StartJump()
    if isJumping_ or isSliding_ then
        jumpBuffered_ = true
        return
    end
    isJumping_ = true
    jumpTime_ = 0.0
end

local function StartSlide()
    if isSliding_ or isJumping_ then
        slideBuffered_ = true
        return
    end
    isSliding_ = true
    slideTime_ = 0.0
end

local function UpdateJumpSlide(dt)
    local jumpY = 0.0

    if isJumping_ then
        jumpTime_ = jumpTime_ + dt
        if jumpTime_ >= CONFIG.JUMP_DURATION then
            isJumping_ = false
            jumpTime_ = 0.0
            -- 检查缓冲
            if slideBuffered_ then
                slideBuffered_ = false
                StartSlide()
            end
        else
            local t = jumpTime_ / CONFIG.JUMP_DURATION
            jumpY = 4.0 * CONFIG.JUMP_HEIGHT * t * (1.0 - t)
        end
    end

    if isSliding_ then
        slideTime_ = slideTime_ + dt
        if slideTime_ >= CONFIG.SLIDE_DURATION then
            isSliding_ = false
            slideTime_ = 0.0
            -- 检查缓冲
            if jumpBuffered_ then
                jumpBuffered_ = false
                StartJump()
            end
        end
        -- 下滑缩放身体
        local bodyNode = playerNode_:GetChild("Body")
        if bodyNode then
            bodyNode.scale = Vector3(0.8, 0.5, 0.6)
            bodyNode.position = Vector3(0, 0.25, 0)
        end
    else
        local bodyNode = playerNode_:GetChild("Body")
        if bodyNode then
            bodyNode.scale = Vector3(0.6, 1.0, 0.6)
            bodyNode.position = Vector3(0, 0.5, 0)
        end
    end

    return jumpY
end

-- ============================================================================
-- 输入处理
-- ============================================================================

local touchStartX_ = 0
local touchStartY_ = 0
local touchActive_ = false

local function HandleTouchBegin(eventType, eventData)
    if gameState_ ~= "running" then return end
    touchStartX_ = eventData:GetInt("X")
    touchStartY_ = eventData:GetInt("Y")
    touchActive_ = true
end

local function HandleTouchEnd(eventType, eventData)
    if not touchActive_ then return end
    if gameState_ ~= "running" then return end
    touchActive_ = false

    local endX = eventData:GetInt("X")
    local endY = eventData:GetInt("Y")
    local dx = endX - touchStartX_
    local dy = endY - touchStartY_

    local threshold = 40

    if math.abs(dx) > math.abs(dy) and math.abs(dx) > threshold then
        -- 水平滑动
        if intersectionActive_ then
            -- 在路口输入窗口中：转弯选择
            if dx < 0 then
                turnChoice_ = -1  -- 左转
            else
                turnChoice_ = 1   -- 右转
            end
        else
            -- 正常变道
            if dx < 0 then
                StartLaneChange(CONFIG.currentLane - 1)
            else
                StartLaneChange(CONFIG.currentLane + 1)
            end
        end
    elseif math.abs(dy) > threshold then
        -- 垂直滑动
        if dy < 0 then
            -- 上滑 = 跳
            if intersectionActive_ then
                turnChoice_ = 0  -- 直走
            end
            StartJump()
        else
            -- 下滑 = 滑铲
            StartSlide()
        end
    end
end

local function HandleKeyboard(dt)
    if gameState_ ~= "running" then return end

    -- 左右（变道/转弯）
    if input:GetKeyPress(KEY_A) or input:GetKeyPress(KEY_LEFT) then
        if intersectionActive_ then
            turnChoice_ = -1
        else
            StartLaneChange(CONFIG.currentLane - 1)
        end
    end
    if input:GetKeyPress(KEY_D) or input:GetKeyPress(KEY_RIGHT) then
        if intersectionActive_ then
            turnChoice_ = 1
        else
            StartLaneChange(CONFIG.currentLane + 1)
        end
    end

    -- 跳跃
    if input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) or input:GetKeyPress(KEY_SPACE) then
        if intersectionActive_ then
            turnChoice_ = 0  -- 直走
        end
        StartJump()
    end

    -- 下滑
    if input:GetKeyPress(KEY_S) or input:GetKeyPress(KEY_DOWN) then
        StartSlide()
    end
end

-- ============================================================================
-- 主更新循环
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
local function HandleUpdate(eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")

    if gameState_ ~= "running" then return end

    -- 输入处理
    HandleKeyboard(dt)

    -- 更新速度
    UpdateSpeed()

    -- 更新路程距离
    local moveDist = currentSpeed_ * dt
    routeDistance_ = routeDistance_ + moveDist
    distanceTraveled_ = distanceTraveled_ + moveDist

    -- 跳跃/下滑
    local jumpY = UpdateJumpSlide(dt)

    -- 变道
    UpdateLaneChange(dt)

    -- 计算玩家世界位置
    local laneX = CONFIG.LANE_X[CONFIG.currentLane]
    if laneChanging_ then
        local t = math.min(1.0, laneChangeTime_ / CONFIG.LANE_CHANGE_DURATION)
        local smoothT = t * t * (3.0 - 2.0 * t)
        laneX = laneChangeFrom_ + (laneChangeTo_ - laneChangeFrom_) * smoothT
    end

    local worldPos = GetWorldPosOnTrack(routeDistance_, laneX)
    playerNode_.position = Vector3(worldPos.x, jumpY, worldPos.z)

    -- 玩家朝向（如果不在转弯动画中）
    if not turnExecuting_ then
        playerNode_.rotation = Quaternion(HeadingToYaw(currentHeading_), Vector3.UP)
    end

    -- 转弯动画
    UpdateTurnAnimation(dt)

    -- 路口逻辑
    UpdateIntersection()

    -- 生成障碍物
    SpawnObstacles()

    -- 碰撞检测
    if CheckCollisions() then
        GameOver()
        return
    end

    -- 取件/送件
    TrySpawnPickup()
    CheckPickup()
    TrySpawnDelivery()
    CheckDelivery()

    -- 回收对象
    RecycleObjects()

    -- 摄像机
    UpdateCamera(dt)

    -- 计时器
    timeRemaining_ = timeRemaining_ - dt
    if timeRemaining_ <= 0 then
        timeRemaining_ = 0
        GameOver()
        return
    end

    -- 更新 HUD
    if lblTimer_ then
        local timeColor = timeRemaining_ < 5 and "#FF4444" or "#FFFFFF"
        lblTimer_:SetText(string.format("⏱ %.0fs", timeRemaining_))
    end
    if lblIncome_ then
        lblIncome_:SetText("¥" .. totalIncome_)
    end
    if lblCombo_ then
        if comboCount_ > 1 then
            lblCombo_:SetText("x" .. comboCount_ .. " 连击!")
        else
            lblCombo_:SetText("")
        end
    end
    if lblSpeed_ then
        lblSpeed_:SetText(string.format("%.0fm/s", currentSpeed_))
    end
    if lblHint_ then
        if intersectionActive_ then
            local hintText = ""
            if intersectionHintDir_ == -1 then hintText = "← 左转推荐"
            elseif intersectionHintDir_ == 1 then hintText = "→ 右转推荐"
            else hintText = "↑ 直走推荐" end
            if turnChoice_ == -1 then hintText = "← 已选: 左转"
            elseif turnChoice_ == 1 then hintText = "→ 已选: 右转"
            elseif turnChoice_ ~= 0 then hintText = "↑ 已选: 直走" end
            lblHint_:SetText(hintText)
        else
            lblHint_:SetText("")
        end
    end

    -- 取件/送件浮动动画
    if pickupActive_ and pickupNode_ then
        local py = pickupNode_.position.y
        pickupNode_.position = Vector3(pickupNode_.position.x, 0.6 + math.sin(time.elapsedTime * 3.0) * 0.2, pickupNode_.position.z)
    end
    if deliveryActive_ and deliveryNode_ then
        deliveryNode_.position = Vector3(deliveryNode_.position.x, 0.15 + math.sin(time.elapsedTime * 2.5) * 0.1, deliveryNode_.position.z)
    end
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
    -- 在 Start 里面只做转发
    CreateGameContent()
end

function CreateGameContent()
    math.randomseed(os.time())

    -- 初始化路径系统
    currentSegmentOrigin_ = Vector3(0, 0, 0)
    currentSegmentStartDist_ = 0.0
    currentHeading_ = PATH.HEADING_POS_Z
    nextIntersectionDist_ = PATH.FIRST_INTERSECTION_DIST

    -- 创建场景
    CreateScene()

    -- 初始化材质
    InitMaterials()

    -- 创建对象池
    InitRoadPool()
    InitLinePool()
    InitBuildingPool()
    InitObstaclePool()

    -- 创建取件/送件节点
    pickupNode_ = CreatePickupNode()
    deliveryNode_ = CreateDeliveryNode()
    nextPickupDist_ = 30.0
    nextDeliveryDist_ = 100.0

    -- 创建路口视觉
    CreateCrossroadsVisuals()

    -- 创建玩家
    CreatePlayer()

    -- 设置摄像机
    SetupCamera()

    -- 创建 UI
    CreateUI()

    -- 注册事件
    SubscribeToEvent("Update", HandleUpdate)
    SubscribeToEvent("TouchBegin", HandleTouchBegin)
    SubscribeToEvent("TouchEnd", HandleTouchEnd)

    print("[Game] 外卖冲冲冲 - 真实转弯版已启动!")
    print("[Game] 操作: ← → 变道/转弯 | ↑/空格 跳跃 | ↓ 下滑")
    print("[Game] 路口出现时：←/→ 选择转弯方向，↑ 直走")
end
