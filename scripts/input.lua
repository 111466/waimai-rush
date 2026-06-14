-- ============================================================================
-- 外卖冲冲冲 - 输入处理模块
-- ============================================================================

local cfg = require("config")
local CONFIG = cfg.CONFIG
local path = require("path")
local player = require("player")
local intersection = require("intersection")

local M = {}

-- 触摸状态
local touchStartX = 0
local touchStartY = 0
local touchActive = false

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
    local s = path.state

    if math.abs(dx) > math.abs(dy) and math.abs(dx) > threshold then
        -- 水平滑动
        if s.intersectionActive then
            if dx < 0 then
                s.turnChoice = -1
            else
                s.turnChoice = 1
            end
            s.hasTurnChoice = true
            intersection.Show()
        else
            if dx < 0 then
                player.StartLaneChange(CONFIG.currentLane - 1)
            else
                player.StartLaneChange(CONFIG.currentLane + 1)
            end
        end
    elseif math.abs(dy) > threshold then
        -- 垂直滑动
        if dy < 0 then
            -- 上滑 = 跳（路口时同时表示选择直走）
            if s.intersectionActive then
                s.turnChoice = 0
                s.hasTurnChoice = true
                intersection.Show()
            end
            player.StartJump()
        else
            -- 下滑 = 滑铲
            player.StartSlide()
        end
    end
end

-- ============================================================================
-- 键盘输入
-- ============================================================================

function M.HandleKeyboard(dt)
    local s = path.state

    -- 左右（变道/转弯）
    if input:GetKeyPress(KEY_A) or input:GetKeyPress(KEY_LEFT) then
        if s.intersectionActive then
            s.turnChoice = -1
            s.hasTurnChoice = true
            intersection.Show()
        else
            player.StartLaneChange(CONFIG.currentLane - 1)
        end
    end
    if input:GetKeyPress(KEY_D) or input:GetKeyPress(KEY_RIGHT) then
        if s.intersectionActive then
            s.turnChoice = 1
            s.hasTurnChoice = true
            intersection.Show()
        else
            player.StartLaneChange(CONFIG.currentLane + 1)
        end
    end

    -- 跳跃（路口时同时表示选择直走）
    if input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) or input:GetKeyPress(KEY_SPACE) then
        if s.intersectionActive then
            s.turnChoice = 0
            s.hasTurnChoice = true
            intersection.Show()
        end
        player.StartJump()
    end

    -- 下滑
    if input:GetKeyPress(KEY_S) or input:GetKeyPress(KEY_DOWN) then
        player.StartSlide()
    end
end

return M
