-- ============================================================================
-- 外卖冲冲冲 - 输入处理模块（并行道路版）
-- ============================================================================
-- 输入状态机：
--   insideIntersection == true → 左右滑动 = 选择转向方向
--   insideIntersection == false → 左右滑动 = 切换并行道路
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
        -- 路口区域内：左右 = 选择转弯方向
        s.desiredTurn = dir --[[@as integer]]
        s.hasTurnChoice = true
        -- 实时更新出口选择
        path.UpdateExitChoice()
    elseif not s.laneChangeLocked then
        -- 普通道路：左右 = 切换并行道路
        path.ChangeLane(dir)
    end
end

--- 处理上方向输入（跳跃 + 路口内选择直走）
local function HandleUpInput()
    local s = path.state

    if s.turnInputActive then
        -- 路口区域内：上 = 选择直走
        s.desiredTurn = 0
        s.hasTurnChoice = true
        path.UpdateExitChoice()
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
