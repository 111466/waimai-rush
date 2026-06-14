-- ============================================================================
-- 外卖冲冲冲 - UI 模块
-- ============================================================================

local UI = require("urhox-libs/UI")
local cfg = require("config")
local CONFIG = cfg.CONFIG

local M = {}

-- UI 引用
M.lblTimer = nil
M.lblIncome = nil
M.lblCombo = nil
M.lblSpeed = nil
M.lblHint = nil
M.gameOverPanel = nil
M.lblFinalIncome = nil
M.lblFinalDist = nil

function M.Create(onRestart)
    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })

    local hud = UI.Panel {
        width = "100%", height = "100%",
        children = {
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

    M.lblTimer = hud:FindById("timer")
    M.lblIncome = hud:FindById("income")
    M.lblCombo = hud:FindById("combo")
    M.lblSpeed = hud:FindById("speed")
    M.lblHint = hud:FindById("hint")

    M.gameOverPanel = UI.Panel {
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
                            onRestart()
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(M.gameOverPanel)
    M.gameOverPanel:SetVisible(false)

    M.lblFinalIncome = M.gameOverPanel:FindById("finalIncome")
    M.lblFinalDist = M.gameOverPanel:FindById("finalDist")
end

function M.UpdateHUD(timeRemaining, totalIncome, comboCount, currentSpeed, intersectionActive, intersectionHintDir, turnChoice)
    if M.lblTimer then
        M.lblTimer:SetText(string.format("⏱ %.0fs", timeRemaining))
    end
    if M.lblIncome then
        M.lblIncome:SetText("¥" .. totalIncome)
    end
    if M.lblCombo then
        if comboCount > 1 then
            M.lblCombo:SetText("x" .. comboCount .. " 连击!")
        else
            M.lblCombo:SetText("")
        end
    end
    if M.lblSpeed then
        M.lblSpeed:SetText(string.format("%.0fm/s", currentSpeed))
    end
    if M.lblHint then
        if intersectionActive then
            local hintText = ""
            if intersectionHintDir == -1 then hintText = "← 左转推荐"
            elseif intersectionHintDir == 1 then hintText = "→ 右转推荐"
            else hintText = "↑ 直走推荐" end
            if turnChoice == -1 then hintText = "← 已选: 左转"
            elseif turnChoice == 1 then hintText = "→ 已选: 右转"
            elseif turnChoice ~= 0 then hintText = "↑ 已选: 直走" end
            M.lblHint:SetText(hintText)
        else
            M.lblHint:SetText("")
        end
    end
end

function M.ShowGameOver(totalIncome, distanceTraveled)
    if M.gameOverPanel then
        M.gameOverPanel:SetVisible(true)
        if M.lblFinalIncome then
            M.lblFinalIncome:SetText("收入: ¥" .. totalIncome)
        end
        if M.lblFinalDist then
            M.lblFinalDist:SetText("距离: " .. math.floor(distanceTraveled) .. "m")
        end
    end
end

function M.HideGameOver()
    if M.gameOverPanel then
        M.gameOverPanel:SetVisible(false)
    end
end

return M
