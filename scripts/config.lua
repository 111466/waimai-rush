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
    -- 玩家根节点站立高度，对齐道路/路口地面顶面
    PLAYER_GROUND_Y = 0.16,

    -- 跑道参数
    ROAD_GRID_SIZE = 8,
    ROAD_BLOCK_BASE = 86.0,
    ROAD_BLOCK_JITTER = 22.0,
    ROAD_CLOSURE_RATE = 0.18,
    ROAD_MIN_REACHABLE_RATIO = 0.8,
    ROAD_RANDOMIZE_ON_RESTART = true,
    ROAD_STREAMING_ENABLED = true,
    ROAD_RENDER_WINDOW_SIZE = 5,
    ROAD_GENERATE_AHEAD_ROWS = 8,
    ROAD_KEEP_BEHIND_ROWS = 4,
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
    BUILDING_SIDEWALK_SETBACK = 0.8,
    BUILDINGS_PER_EDGE = 8,  -- 每条边上两侧建筑数

    -- 速度参数
    BASE_SPEED = 8.0,
    MAX_SPEED = 14.0,
    SPEED_DISTANCE_FACTOR = 100.0,

    -- 摄像机跟随参数（竖屏跑酷视角）
    CAM_OFFSET_Y = 6.75,
    CAM_OFFSET_Z = -10.25,
    CAM_LOOK_AHEAD = 7.5,
    CAM_YAW_OFFSET = 0.0,
    CAM_PITCH_OFFSET = 0.25,
    CAM_SMOOTH = 8.0,
    CAM_FOV_BASE = 58.0,
    CAM_FOV_MAX = 68.0,
    CAM_FOV_SPEED_FACTOR = 0.5,
    CAM_TILT_FACTOR = 1.5,

    -- 障碍物
    OBSTACLE_POOL_PER_TYPE = 16,
    OBSTACLE_SPAWN_AHEAD = 65.0,
    OBSTACLE_MIN_SPACING = 12.0,
    OBSTACLE_MAX_PER_ROW = 2,
    COLLISION_Z_THRESHOLD = 1.0,
    COLLISION_BACK_Z_THRESHOLD = 0.35,
    COLLISION_FRONT_X_THRESHOLD = 0.65,
    COLLISION_SIDE_X_THRESHOLD = 1.25,
    LOW_OBSTACLE_TOP_Y = 0.5,
    TOP_LANDING_MIN_CLEARANCE = 0.05,
    OBSTACLE_EDGE_START_BUFFER = 18.0,
    OBSTACLE_EDGE_END_BUFFER = 22.0,
    OBSTACLE_ORDER_CLEARANCE = 10.0,
    OBSTACLE_SEQUENCE_GAP = 12.0,
    OBSTACLE_COMPLEX_START_DISTANCE = 100.0,
    OBSTACLE_ADVANCED_START_DISTANCE = 400.0,

    -- 难度渐进
    DIFFICULTY_START_DISTANCE = 50.0,
    DIFFICULTY_RAMP_DISTANCE = 400.0,
    OBSTACLE_SPACING_MIN = 10.0,
    OBSTACLE_SPACING_MAX = 20.0,

    -- 取件/送件
    PICKUP_INITIAL_SPAWN_AHEAD = 35.0,
    PICKUP_SPAWN_AHEAD = 50.0,
    PICKUP_INTERVAL_MIN = 40.0,
    PICKUP_INTERVAL_MAX = 70.0,
    DELIVERY_SPAWN_AHEAD = 50.0,
    DELIVERY_INTERVAL_MIN = 50.0,
    DELIVERY_INTERVAL_MAX = 80.0,
    DELIVERY_TARGET_MIN_HOPS = 2,
    DELIVERY_TARGET_MAX_HOPS = 4,
    DELIVERY_COMBO_MULTIPLIER = 0.5,
    ORDER_TIME_ROUTE_FACTOR = 1.35,
    ORDER_TIME_EXTRA_SECONDS = 5.0,
    ORDER_TIME_MIN_SECONDS = 12.0,
    ORDER_TIME_MAX_SECONDS = 35.0,
    ORDER_TIME_WARNING_SECONDS = 5.0,
    ORDER_LATE_PENALTY_PER_SEC = 2,
    ORDER_EDGE_START_BUFFER = 18.0,
    ORDER_EDGE_END_BUFFER = 18.0,

    -- 跳跃与下滑
    JUMP_DURATION = 0.6,
    JUMP_HEIGHT = 1.5,
    SLIDE_DURATION = 0.5,

    -- 变道平滑
    LANE_CHANGE_DURATION = 0.18,

    -- 路口接近提示距离（进度百分比，仅用于UI提示）
    INTERSECTION_HINT_PROGRESS = 0.7,  -- 到达边的 70% 时提示
    -- 转弯执行距离（进度百分比，已废弃）
    INTERSECTION_EXECUTE_PROGRESS = 0.92,

    -- 路口转向输入窗口（基于距路口中心的距离，单位：米）
    TURN_INPUT_START_DIST = 12.0,  -- 距路口 <= 12m 时左右滑动变为转向选择

    -- 路口区域参数
    INTERSECTION_HALF_SIZE = 3.5,  -- 路口区域半径（总区域 7m × 7m）
    DEBUG_INTERSECTION_BORDER = false,
    SHOW_INTERSECTION_ENTRY_LINES = true,
    SHOW_INTERSECTION_CLOSED_MARKERS = true,
    -- 玩家进入路口区域后，根据位置确定出口车道：
    --   转弯时：前进方向进度 → 出口车道 (后1/3→lane1, 中1/3→lane2, 前1/3→lane3)
    --   直行时：横向位置 → 出口车道 (当前lane直接映射)

    -- 路口安全区（距离路口中心的 pathDistance）
    SAFE_ZONE_DIST = 15.0,

    -- 转弯动画
    TURN_ANIM_SPEED = 1.8,  -- 转弯时速度系数(较快通过弧线)
    CAM_TURN_DURATION = 0.4,

    -- 路网可见范围（显示玩家附近多远的道路）
    VISIBLE_RANGE = 120.0,
}

return M
