-- ============================================================================
-- 外卖冲冲冲 - 阶段 0.1：基础场景与三车道
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
    ROAD_WIDTH = 7.0,        -- 跑道总宽度（米）
    ROAD_SEGMENT_LENGTH = 40.0, -- 每段跑道长度
    ROAD_SEGMENTS = 10,      -- 跑道段数

    -- 玩家参数
    RUN_SPEED = 8.0,         -- 奔跑速度（米/秒）

    -- 摄像机跟随参数（竖屏跑酷视角）
    CAM_OFFSET_Y = 6.0,      -- 相机在玩家上方的高度
    CAM_OFFSET_Z = -7.0,     -- 相机在玩家后方的距离
    CAM_LOOK_AHEAD = 5.0,    -- 相机看向玩家前方的距离

    -- 城市建筑参数
    BUILDING_ZONE_START = 4.5,  -- 建筑距离道路中心的最小距离
    BUILDING_ZONE_END = 15.0,   -- 建筑区域最远距离
    BUILDING_COUNT = 60,         -- 建筑数量（两侧各一半）
}

-- 运行距离追踪
local distanceTraveled_ = 0.0

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    -- 初始化 UI
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 创建场景
    CreateScene()

    -- 创建跑道
    CreateRoad()

    -- 创建城市装饰
    CreateCityBuildings()

    -- 创建玩家角色
    CreatePlayer()

    -- 设置摄像机
    SetupCamera()

    -- 创建 HUD
    CreateUI()

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")

    print("=== 外卖冲冲冲 - 阶段 0.1 启动 ===")
    print("三车道已就绪，外卖员自动向前奔跑")
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
    scene_:CreateComponent("DebugRenderer")

    -- 加载 Daytime 光照预设（明亮清爽）
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    -- 调整雾效让远处更清爽
    local zone = lightGroup:GetComponent("Zone", true)
    if zone then
        zone.fogColor = Color(0.75, 0.88, 0.95)  -- 浅蓝天色
        zone.fogStart = 60.0
        zone.fogEnd = 200.0
    end

    -- 调整主光色温为暖白，增强卡通阳光感
    local light = lightGroup:GetComponent("Light", true)
    if light then
        light.color = Color(1.0, 0.95, 0.85)
        light.brightness = 3.5
    end

    print("[Scene] 场景创建完成")
end

-- ============================================================================
-- 跑道创建
-- ============================================================================

--- 创建一个 PBR 无贴图材质
---@param diffuse Color
---@param metallic number
---@param roughness number
---@return Material
local function CreatePBRMaterial(diffuse, metallic, roughness)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(diffuse))
    mat:SetShaderParameter("MatSpecColor", Variant(Color(0.4, 0.4, 0.4, 1.0)))
    mat:SetShaderParameter("Metallic", Variant(metallic))
    mat:SetShaderParameter("Roughness", Variant(roughness))
    return mat
end

function CreateRoad()
    -- 材质定义（积木阳光城风格）
    local roadMat = CreatePBRMaterial(Color(0.88, 0.88, 0.85, 1.0), 0.0, 0.8)    -- 浅灰道路
    local laneMat = CreatePBRMaterial(Color(1.0, 1.0, 1.0, 1.0), 0.0, 0.9)       -- 白色车道线
    local sidewalkMat = CreatePBRMaterial(Color(0.72, 0.82, 0.78, 1.0), 0.0, 0.7) -- 蓝绿人行道
    local curbMat = CreatePBRMaterial(Color(0.6, 0.7, 0.65, 1.0), 0.0, 0.6)      -- 路缘石

    local segLen = CONFIG.ROAD_SEGMENT_LENGTH

    for i = 1, CONFIG.ROAD_SEGMENTS do
        local zStart = (i - 1) * segLen
        local zCenter = zStart + segLen / 2

        -- 主路面
        local roadNode = scene_:CreateChild("Road_" .. i)
        roadNode.position = Vector3(0, -0.05, zCenter)
        roadNode.scale = Vector3(CONFIG.ROAD_WIDTH, 0.1, segLen)
        local roadModel = roadNode:CreateComponent("StaticModel")
        roadModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        roadModel:SetMaterial(roadMat)

        -- 左侧路缘
        local leftCurb = scene_:CreateChild("CurbL_" .. i)
        leftCurb.position = Vector3(-CONFIG.ROAD_WIDTH / 2 - 0.15, 0.05, zCenter)
        leftCurb.scale = Vector3(0.3, 0.3, segLen)
        local lcModel = leftCurb:CreateComponent("StaticModel")
        lcModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        lcModel:SetMaterial(curbMat)

        -- 右侧路缘
        local rightCurb = scene_:CreateChild("CurbR_" .. i)
        rightCurb.position = Vector3(CONFIG.ROAD_WIDTH / 2 + 0.15, 0.05, zCenter)
        rightCurb.scale = Vector3(0.3, 0.3, segLen)
        local rcModel = rightCurb:CreateComponent("StaticModel")
        rcModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        rcModel:SetMaterial(curbMat)

        -- 左侧人行道
        local leftSidewalk = scene_:CreateChild("SidewalkL_" .. i)
        leftSidewalk.position = Vector3(-CONFIG.ROAD_WIDTH / 2 - 1.5, -0.02, zCenter)
        leftSidewalk.scale = Vector3(2.5, 0.1, segLen)
        local lsModel = leftSidewalk:CreateComponent("StaticModel")
        lsModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        lsModel:SetMaterial(sidewalkMat)

        -- 右侧人行道
        local rightSidewalk = scene_:CreateChild("SidewalkR_" .. i)
        rightSidewalk.position = Vector3(CONFIG.ROAD_WIDTH / 2 + 1.5, -0.02, zCenter)
        rightSidewalk.scale = Vector3(2.5, 0.1, segLen)
        local rsModel = rightSidewalk:CreateComponent("StaticModel")
        rsModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        rsModel:SetMaterial(sidewalkMat)
    end

    -- 车道分隔线（虚线效果：每隔固定距离放一条短白线）
    local totalLength = CONFIG.ROAD_SEGMENTS * segLen
    local lineSpacing = 3.0   -- 线间距
    local lineLength = 1.5    -- 每段线长
    for z = 0, totalLength - lineSpacing, lineSpacing do
        -- 左/中车道分隔线（x = -1.0）
        local lineL = scene_:CreateChild("LaneLineL")
        lineL.position = Vector3(-1.0, 0.01, z + lineLength / 2)
        lineL.scale = Vector3(0.1, 0.02, lineLength)
        local llModel = lineL:CreateComponent("StaticModel")
        llModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        llModel:SetMaterial(laneMat)

        -- 中/右车道分隔线（x = 1.0）
        local lineR = scene_:CreateChild("LaneLineR")
        lineR.position = Vector3(1.0, 0.01, z + lineLength / 2)
        lineR.scale = Vector3(0.1, 0.02, lineLength)
        local lrModel = lineR:CreateComponent("StaticModel")
        lrModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        lrModel:SetMaterial(laneMat)
    end

    print("[Road] 跑道创建完成: " .. CONFIG.ROAD_SEGMENTS .. " 段, 总长 " .. totalLength .. " 米")
end

-- ============================================================================
-- 城市装饰建筑
-- ============================================================================

function CreateCityBuildings()
    -- 积木阳光城配色
    local buildingColors = {
        Color(0.55, 0.82, 0.78, 1.0),  -- 薄荷绿
        Color(0.65, 0.80, 0.90, 1.0),  -- 天蓝
        Color(0.92, 0.85, 0.65, 1.0),  -- 暖黄
        Color(0.88, 0.70, 0.60, 1.0),  -- 珊瑚橙
        Color(0.80, 0.75, 0.90, 1.0),  -- 淡紫
        Color(0.95, 0.92, 0.82, 1.0),  -- 奶白
    }

    local totalLength = CONFIG.ROAD_SEGMENTS * CONFIG.ROAD_SEGMENT_LENGTH
    math.randomseed(42)  -- 固定种子，保证每次运行一致

    for i = 1, CONFIG.BUILDING_COUNT do
        -- 随机决定左侧还是右侧
        local side = (i % 2 == 0) and 1 or -1

        -- 随机位置
        local xDist = CONFIG.BUILDING_ZONE_START + math.random() * (CONFIG.BUILDING_ZONE_END - CONFIG.BUILDING_ZONE_START)
        local x = side * xDist
        local z = math.random() * totalLength

        -- 随机大小（积木块风格：高度差异大，宽度较统一）
        local width = 1.5 + math.random() * 2.5
        local height = 2.0 + math.random() * 8.0
        local depth = 1.5 + math.random() * 2.5

        -- 随机颜色
        local colorIdx = math.random(1, #buildingColors)
        local color = buildingColors[colorIdx]

        -- 创建建筑方块
        local buildingNode = scene_:CreateChild("Building_" .. i)
        buildingNode.position = Vector3(x, height / 2, z)
        buildingNode.scale = Vector3(width, height, depth)

        local model = buildingNode:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        model:SetMaterial(CreatePBRMaterial(color, 0.0, 0.7))
        model.castShadows = true
    end

    print("[City] 城市装饰建筑创建完成: " .. CONFIG.BUILDING_COUNT .. " 栋")
end

-- ============================================================================
-- 玩家角色
-- ============================================================================

function CreatePlayer()
    -- 外卖员角色（用胶囊体+方块组合表示）
    playerNode_ = scene_:CreateChild("Player")
    local laneX = CONFIG.LANE_X[CONFIG.currentLane]
    playerNode_.position = Vector3(laneX, 0, 5.0)

    -- 身体（竖直圆柱体代替胶囊）
    local bodyNode = playerNode_:CreateChild("Body")
    bodyNode.position = Vector3(0, 0.7, 0)
    bodyNode.scale = Vector3(0.5, 1.2, 0.4)
    local bodyModel = bodyNode:CreateComponent("StaticModel")
    bodyModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    -- 蓝色工服
    bodyModel:SetMaterial(CreatePBRMaterial(Color(0.2, 0.45, 0.8, 1.0), 0.0, 0.6))
    bodyModel.castShadows = true

    -- 头部（球体）
    local headNode = playerNode_:CreateChild("Head")
    headNode.position = Vector3(0, 1.5, 0)
    headNode.scale = Vector3(0.4, 0.4, 0.4)
    local headModel = headNode:CreateComponent("StaticModel")
    headModel:SetModel(cache:GetResource("Model", "Models/Sphere.mdl"))
    -- 肤色
    headModel:SetMaterial(CreatePBRMaterial(Color(0.95, 0.82, 0.70, 1.0), 0.0, 0.5))
    headModel.castShadows = true

    -- 外卖箱（背后的方块）
    local boxNode = playerNode_:CreateChild("DeliveryBox")
    boxNode.position = Vector3(0, 1.0, -0.35)
    boxNode.scale = Vector3(0.5, 0.5, 0.3)
    local boxModel = boxNode:CreateComponent("StaticModel")
    boxModel:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    -- 黄色外卖箱
    boxModel:SetMaterial(CreatePBRMaterial(Color(1.0, 0.75, 0.1, 1.0), 0.0, 0.5))
    boxModel.castShadows = true

    -- 帽子（小圆柱）
    local hatNode = playerNode_:CreateChild("Hat")
    hatNode.position = Vector3(0, 1.75, 0)
    hatNode.scale = Vector3(0.35, 0.12, 0.35)
    local hatModel = hatNode:CreateComponent("StaticModel")
    hatModel:SetModel(cache:GetResource("Model", "Models/Cylinder.mdl"))
    -- 黄色帽子
    hatModel:SetMaterial(CreatePBRMaterial(Color(1.0, 0.8, 0.15, 1.0), 0.0, 0.5))
    hatModel.castShadows = true

    print("[Player] 外卖员角色创建完成，位于中车道")
end

-- ============================================================================
-- 摄像机设置（竖屏跑酷视角）
-- ============================================================================

function SetupCamera()
    cameraNode_ = scene_:CreateChild("Camera")

    local camera = cameraNode_:CreateComponent("Camera")
    camera.nearClip = 0.1
    camera.farClip = 300.0
    camera.fov = 60.0

    -- 设置视口
    renderer:SetViewport(0, Viewport:new(scene_, camera))
    renderer.hdrRendering = true

    -- 初始化摄像机位置
    UpdateCameraPosition()

    print("[Camera] 竖屏跑酷视角已设置")
end

--- 更新摄像机位置（跟随玩家）
function UpdateCameraPosition()
    if playerNode_ == nil or cameraNode_ == nil then return end

    local playerPos = playerNode_.position

    -- 摄像机在玩家后上方
    cameraNode_.position = Vector3(
        0,                                          -- X：始终居中
        playerPos.y + CONFIG.CAM_OFFSET_Y,          -- Y：玩家上方
        playerPos.z + CONFIG.CAM_OFFSET_Z            -- Z：玩家后方
    )

    -- 看向玩家前方一段距离
    local lookTarget = Vector3(0, playerPos.y + 0.5, playerPos.z + CONFIG.CAM_LOOK_AHEAD)
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
            -- 游戏标题
            UI.Label {
                id = "title",
                text = "外卖冲冲冲",
                fontSize = 22,
                fontWeight = "bold",
                fontColor = { 255, 255, 255, 230 },
                position = "absolute",
                top = 20,
                left = 0,
                right = 0,
                textAlign = "center",
            },
            -- 距离显示
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
-- 游戏更新
-- ============================================================================

-- 简单的跑步摆动动画
local runTimer_ = 0.0

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    if playerNode_ == nil then return end

    -- 玩家自动向前跑
    local currentPos = playerNode_.position
    local newZ = currentPos.z + CONFIG.RUN_SPEED * dt
    playerNode_.position = Vector3(currentPos.x, currentPos.y, newZ)

    -- 更新距离
    distanceTraveled_ = distanceTraveled_ + CONFIG.RUN_SPEED * dt

    -- 跑步摆动动画（简单的左右+上下摆动）
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
    local boxNode = playerNode_:GetChild("DeliveryBox")
    if boxNode then
        -- 外卖箱轻微摇晃
        local boxSwing = math.sin(runTimer_ * 0.7) * 2.0
        boxNode.rotation = Quaternion(boxSwing, Vector3.FORWARD)
    end

    -- 更新摄像机跟随
    UpdateCameraPosition()

    -- 更新 UI 距离显示
    local distLabel = UI.FindById("distance")
    if distLabel then
        distLabel:SetText(string.format("距离: %d m", math.floor(distanceTraveled_)))
    end
end
