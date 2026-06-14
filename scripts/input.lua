-- ============================================================================
-- 外卖冲冲冲 - 输入处理模块
-- ============================================================================
-- 输入状态机：
--   路口中心区域内 (turnInputActive=true)：
--     第1次左右滑 = 选择转弯方向
--     后续左右滑 = 换道（选择出口路线）
--   路口外：左右滑 = 普通变道
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local player = require("player")

local M = {}

-- 触摸状态
local touchStartX = 0
local touchStartY = 0
local touchActive = false

-- ============================================================================
-- 通用左右输入处理
-- ============================================================================

--- 处理左右方向输入（统一键盘和触摸）
--- @param dir integer -1=左, 1=右
local function HandleHorizontalInput(dir)
    local s = path.state

    if s.turnInputActive then
        -- 在路口中心区域内（turnInputActive 仅在 insideIntersection 时为 true）
        if not s.hasTurnChoice then
            -- 第一次滑动：选择转弯方向
            s.turnChoice = dir --[[@as integer]]
            s.hasTurnChoice = true
            -- 立即更新出口方向（实时生效）
            path.UpdateExitChoice()
        else
            -- 已选过方向，后续滑动：换道（选择从哪条出口路出去）
            local targetLane = CONFIG.currentLane + dir
            player.StartLaneChange(targetLane)
        end
    else
        -- 普通道路（路口外）：左右 = 变道
        local targetLane = CONFIG.currentLane + dir
        player.StartLaneChange(targetLane)
    end
end

--- 处理上方向输入（跳跃 + 可选直走选择）
local function HandleUpInput()
    local s = path.state

    -- 如果在转向选择窗口，上滑同时表示选择直走
    if s.turnInputActive then
        s.turnChoice = 0
        s.hasTurnChoice = true
        if s.insideIntersection then
            path.UpdateExitChoice()
        end
    end

    -- 跳跃始终生效
    player.StartJump()
end

--- 处理下方向输入（滑铲）
local function HandleDownInput()
    player.StartSlide()
end

-- ============================================================================
-- 触摸输入
-- ============================================================================

function M.HandleTouchBegin(eventType, eventData)
    touchStartX = eventData:GetInt("X")
    touchStartY = eventData:GetInt("Y")
    touchActive = true
end

function M.HandleTouchEnd(eventType, eventData)
    if not touchActive then return end
    touchActive = false

    local endX = eventData:GetInt("X")
    local endY = eventData:GetInt("Y")
    local dx = endX - touchStartX
    local dy = endY - touchStartY

    local threshold = 40

    if math.abs(dx) > math.abs(dy) and math.abs(dx) > threshold then
        if dx < 0 then
            HandleHorizontalInput(-1)
        else
            HandleHorizontalInput(1)
        end
    elseif math.abs(dy) > threshold then
        if dy < 0 then
            HandleUpInput()
        else
            HandleDownInput()
        end
    end
end

-- ============================================================================
-- 键盘输入
-- ============================================================================

function M.HandleKeyboard(dt)
    if input:GetKeyPress(KEY_A) or input:GetKeyPress(KEY_LEFT) then
        HandleHorizontalInput(-1)
    end
    if input:GetKeyPress(KEY_D) or input:GetKeyPress(KEY_RIGHT) then
        HandleHorizontalInput(1)
    end
    if input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) or input:GetKeyPress(KEY_SPACE) then
        HandleUpInput()
    end
    if input:GetKeyPress(KEY_S) or input:GetKeyPress(KEY_DOWN) then
        HandleDownInput()
    end
end

return M
