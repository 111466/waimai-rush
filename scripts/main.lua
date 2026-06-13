-- ============================================================================
-- 外卖冲冲冲 - 阶段 0.2：左右变道
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
}

-- 变道参数
local LANE_CHANGE_DURATION = 0.2     -- 变道持续时间（秒）
local SWIPE_THRESHOLD = 40.0         -- 滑动触发阈值（像素）

-- 变道状态
local laneChangeTimer_ = 0.0         -- 变道计时器（>0 表示正在变道中）
local laneChangeFromX_ = 0.0         -- 变道起始 X
local laneChangeToX_ = 0.0           -- 变道目标 X

-- 触摸滑动检测
local touchStartX_ = nil             -- 触摸开始时的 X 坐标（像素）
local touchId_ = -1                  -- 正在追踪的触摸 ID

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

-- 共享材质（避免重复创建）
local mat_ = {}

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
    SetupCamera()
    CreateUI()

    SubscribeToEvent("Update", "HandleUpdate")

    print("=== 外卖冲冲冲 - 阶段 0.1 启动 ===")
    print("三车道循环道路已就绪，外卖员无限向前奔跑")
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
    local segLen = CONFIG.ROAD_SEGMENT_LENGTH
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
        }
    }
    UI.SetRoot(uiRoot)
end

-- ============================================================================
-- 循环回收逻辑
-- ============================================================================

--- 回收已经在玩家后方的道路段，移到前方
local function RecycleRoadSegments(playerZ)
    local segLen = CONFIG.ROAD_SEGMENT_LENGTH
    -- 回收阈值：段中心在玩家后方超过一个段长
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
    -- 变道中，忽略新输入
    if IsChangingLane() then return end

    local newLane = CONFIG.currentLane + direction
    -- 边界限制（车道 1~3）
    if newLane < 1 or newLane > 3 then return end

    -- 开始变道
    laneChangeFromX_ = CONFIG.LANE_X[CONFIG.currentLane]
    laneChangeToX_ = CONFIG.LANE_X[newLane]
    CONFIG.currentLane = newLane
    laneChangeTimer_ = LANE_CHANGE_DURATION

    print(string.format("[变道] 方向=%d, 目标车道=%d, 目标X=%.1f", direction, newLane, laneChangeToX_))
end

--- 在有触摸时实时检测滑动距离是否超过阈值
local function HandleTouchSwipe()
    if IsChangingLane() then
        -- 变道中，清除触摸追踪状态
        touchStartX_ = nil
        touchId_ = -1
        return
    end

    local numTouches = input.numTouches
    if numTouches > 0 then
        local touch = input:GetTouch(0)
        if touchStartX_ == nil then
            -- 新触摸开始，记录起始 X
            touchStartX_ = touch.position.x
            touchId_ = touch.touchID
        else
            -- 持续追踪，判断是否超过阈值
            local currentX = touch.position.x
            local deltaX = currentX - touchStartX_

            if deltaX > SWIPE_THRESHOLD then
                -- 向右滑动 → 右变道
                TryChangeLane(1)
                touchStartX_ = nil
                touchId_ = -1
            elseif deltaX < -SWIPE_THRESHOLD then
                -- 向左滑动 → 左变道
                TryChangeLane(-1)
                touchStartX_ = nil
                touchId_ = -1
            end
        end
    else
        -- 触摸释放，清除追踪
        touchStartX_ = nil
        touchId_ = -1
    end
end

--- 处理键盘输入（调试用）
local function HandleKeyboardInput()
    if IsChangingLane() then return end

    if input:GetKeyPress(KEY_A) or input:GetKeyPress(KEY_LEFT) then
        TryChangeLane(-1)
    elseif input:GetKeyPress(KEY_D) or input:GetKeyPress(KEY_RIGHT) then
        TryChangeLane(1)
    end
end

--- 更新变道平滑移动
local function UpdateLaneChange(dt)
    if laneChangeTimer_ <= 0.0 then return end

    laneChangeTimer_ = laneChangeTimer_ - dt
    if laneChangeTimer_ <= 0.0 then
        -- 变道完成，精确到目标位置
        laneChangeTimer_ = 0.0
        local pos = playerNode_.position
        playerNode_.position = Vector3(laneChangeToX_, pos.y, pos.z)
    else
        -- 线性插值（从起始到目标）
        local progress = 1.0 - (laneChangeTimer_ / LANE_CHANGE_DURATION)
        -- 使用 smoothstep 让动作更自然
        local t = progress * progress * (3.0 - 2.0 * progress)
        local currentX = laneChangeFromX_ + (laneChangeToX_ - laneChangeFromX_) * t
        local pos = playerNode_.position
        playerNode_.position = Vector3(currentX, pos.y, pos.z)
    end
end

-- ============================================================================
-- 游戏更新
-- ============================================================================

local runTimer_ = 0.0
local uiTimer_ = 0.0

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    if playerNode_ == nil then return end

    -- 输入检测（触摸 + 键盘）
    HandleTouchSwipe()
    HandleKeyboardInput()

    -- 更新变道平滑移动
    UpdateLaneChange(dt)

    -- 玩家自动向前跑
    local currentPos = playerNode_.position
    local newZ = currentPos.z + CONFIG.RUN_SPEED * dt
    playerNode_.position = Vector3(currentPos.x, currentPos.y, newZ)

    -- 更新距离
    distanceTraveled_ = distanceTraveled_ + CONFIG.RUN_SPEED * dt

    -- 跑步摆动动画
    runTimer_ = runTimer_ + dt * 10.0
    local bobY = math.abs(math.sin(runTimer_)) * 0.08
    local bodyNode = playerNode_:GetChild("Body")
    if bodyNode then
        bodyNode.position = Vector3(0, 0.7 + bobY, 0)
    end
    local headNode = playerNode_:GetChild("Head")
    if headNode then
        headNode.position = Vector3(0, 1.5 + bobY, 0)
    end
    local hatNode = playerNode_:GetChild("Hat")
    if hatNode then
        hatNode.position = Vector3(0, 1.75 + bobY, 0)
    end
    local dboxNode = playerNode_:GetChild("DeliveryBox")
    if dboxNode then
        local swing = math.sin(runTimer_ * 0.7) * 2.0
        dboxNode.rotation = Quaternion(swing, Vector3.FORWARD)
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
