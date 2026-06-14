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
M.PATH = {
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
    TURN_INPUT_WINDOW = 45.0,
    TURN_EXECUTE_DIST = 0.0,

    -- 弯道几何
    TURN_RADIUS = 14.0,
    TURN_ARC_LENGTH = 14.0 * math.pi * 0.5,
    TURN_VISUAL_SEGMENTS = 9,
    TURN_EXIT_PREVIEW_LENGTH = 24.0,

    -- 动画
    TURN_ANIM_DURATION = 0.40,
    CAM_TURN_DURATION = 0.45,

    -- 安全区
    SAFE_ZONE_BEFORE = 25.0,
    SAFE_ZONE_AFTER = 35.0,

    -- 奖惩
    CORRECT_TURN_BONUS = 2.0,
    WRONG_TURN_PENALTY = 3.0,

    -- 视觉
    CROSSROADS_SIZE = 8.0,
    PREVIEW_ROAD_LENGTH = 6.0,
}

return M
