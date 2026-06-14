-- ============================================================================
-- 外卖冲冲冲 - 配置模块
-- ============================================================================

local M = {}

-- ============================================================================
-- 游戏配置
-- ============================================================================
M.CONFIG = {
    -- 三车道横向坐标（左、中、右）
    LANE_X = { -2.0, 0.0, 2.0 },
    -- 玩家当前车道索引（1=左, 2=中, 3=右）
    currentLane = 2,

    -- 跑道参数
    ROAD_WIDTH = 7.0,
    ROAD_SEGMENT_LENGTH = 10.0,  -- 每段道路长度（用于铺路段贴片）
    ROAD_SEGMENTS_PER_EDGE = 8,  -- 每条边上铺多少段道路

    -- 车道线参数
    LINE_SPACING = 3.0,
    LINE_LENGTH = 1.5,
    LINES_PER_EDGE = 26,  -- 每条边上车道线数量

    -- 建筑参数
    BUILDING_ZONE_START = 5.5,
    BUILDING_ZONE_END = 18.0,
    BUILDINGS_PER_EDGE = 8,  -- 每条边上两侧建筑数

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
    OBSTACLE_POOL_PER_TYPE = 10,
    OBSTACLE_SPAWN_AHEAD = 60.0,
    OBSTACLE_MIN_SPACING = 12.0,
    OBSTACLE_MAX_PER_ROW = 2,
    COLLISION_Z_THRESHOLD = 1.0,

    -- 难度渐进
    DIFFICULTY_START_DISTANCE = 50.0,
    DIFFICULTY_RAMP_DISTANCE = 400.0,
    OBSTACLE_SPACING_MIN = 10.0,
    OBSTACLE_SPACING_MAX = 20.0,

    -- 取件/送件
    PICKUP_SPAWN_AHEAD = 50.0,
    PICKUP_INTERVAL_MIN = 40.0,
    PICKUP_INTERVAL_MAX = 70.0,
    DELIVERY_SPAWN_AHEAD = 50.0,
    DELIVERY_INTERVAL_MIN = 50.0,
    DELIVERY_INTERVAL_MAX = 80.0,
    DELIVERY_COMBO_MULTIPLIER = 0.5,

    -- 跳跃与下滑
    JUMP_DURATION = 0.6,
    JUMP_HEIGHT = 1.5,
    SLIDE_DURATION = 0.5,

    -- 变道平滑
    LANE_CHANGE_DURATION = 0.18,

    -- 路口接近提示距离（进度百分比）
    INTERSECTION_HINT_PROGRESS = 0.7,  -- 到达边的 70% 时提示
    -- 转弯执行距离（进度百分比）
    INTERSECTION_EXECUTE_PROGRESS = 0.92,  -- 到达边的 92% 时执行转弯

    -- 路口安全区（距离路口中心的 pathDistance）
    SAFE_ZONE_DIST = 15.0,

    -- 转弯动画
    TURN_ANIM_SPEED = 1.8,  -- 转弯时速度系数(较快通过弧线)
    CAM_TURN_DURATION = 0.4,

    -- 奖惩
    CORRECT_TURN_BONUS = 2.0,
    WRONG_TURN_PENALTY = 3.0,

    -- 路网可见范围（显示玩家附近多远的道路）
    VISIBLE_RANGE = 120.0,
}

return M
