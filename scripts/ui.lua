-- ============================================================================
-- 外卖冲冲冲 - UI 模块
-- ============================================================================

local UI = require("urhox-libs/UI")
local cfg = require("config")
local CONFIG = cfg.CONFIG
local rn = require("road_network")
local nav = require("route_navigation")

local M = {}

-- UI 引用
M.lblTimer = nil
M.lblTimerNormal = nil
M.lblTimerWarning = nil
M.lblTimerLate = nil
M.lblIncome = nil
M.lblCombo = nil
M.lblSpeed = nil
M.lblHint = nil
M.gameOverPanel = nil
M.lblFinalIncome = nil
M.lblFinalDist = nil
M.minimapPanel = nil
M.lblMiniStatus = nil
M.minimapRouteSegments = {}
M.minimapPlayerMarkers = {}
M.minimapTargetMarkers = {}
M.minimapPickupMarkers = {}

local MINI_PANEL_W = 132
local MINI_PANEL_H = 154
local MINI_MAP_SIZE = 112
local MINI_LEFT = 10
local MINI_TOP = 8
local MINI_MARGIN = 10

local function MiniPoint(node)
    local usable = MINI_MAP_SIZE - MINI_MARGIN * 2
    local bounds = rn.bounds or { minX = 0, maxX = 1, minZ = 0, maxZ = 1 }
    local width = math.max(1.0, bounds.maxX - bounds.minX)
    local depth = math.max(1.0, bounds.maxZ - bounds.minZ)
    local x = MINI_LEFT + MINI_MARGIN + ((node.worldX - bounds.minX) / width) * usable
    local y = MINI_TOP + MINI_MARGIN + (1.0 - ((node.worldZ - bounds.minZ) / depth)) * usable
    return x, y
end

local function AddMiniSegment(children, id, edge, color, thickness)
    local fromNode = rn.nodes[edge.fromNode]
    local toNode = rn.nodes[edge.toNode]
    if not fromNode or not toNode then return end

    local x1, y1 = MiniPoint(fromNode)
    local x2, y2 = MiniPoint(toNode)
    local dx = math.abs(x2 - x1)
    local dz = math.abs(y2 - y1)
    local left, top, width, height

    if dx >= dz then
        left = math.min(x1, x2)
        top = y1 - thickness * 0.5
        width = math.max(thickness, dx)
        height = thickness
    else
        left = x1 - thickness * 0.5
        top = math.min(y1, y2)
        width = thickness
        height = math.max(thickness, dz)
    end

    table.insert(children, UI.Panel {
        id = id,
        position = "absolute",
        left = left,
        top = top,
        width = width,
        height = height,
        backgroundColor = color,
        borderRadius = thickness,
    })
end

local function AddMiniMarker(children, id, x, y, size, color, radius)
    table.insert(children, UI.Panel {
        id = id,
        position = "absolute",
        left = x - size * 0.5,
        top = y - size * 0.5,
        width = size,
        height = size,
        backgroundColor = color,
        borderRadius = radius or size * 0.5,
    })
end

local function AddMiniPlayerProgressMarkers(children, key, edge)
    local nodeA = rn.nodes[math.min(edge.fromNode, edge.toNode)]
    local nodeB = rn.nodes[math.max(edge.fromNode, edge.toNode)]
    if not nodeA or not nodeB then return end

    local x1, y1 = MiniPoint(nodeA)
    local x2, y2 = MiniPoint(nodeB)
    for step = 0, nav.MINIMAP_PLAYER_EDGE_STEPS do
        local t = step / nav.MINIMAP_PLAYER_EDGE_STEPS
        local x = x1 + (x2 - x1) * t
        local y = y1 + (y2 - y1) * t
        AddMiniMarker(children, "mini_player_p" .. key .. "_" .. step, x, y, 8, "#8A5CFF", 4)
    end
end

local function BuildMinimap()
    local children = {}
    local seenSegments = {}
    local segmentPositions = {}

    for edgeId = 1, #rn.edges do
        local edge = rn.edges[edgeId]
        if edge then
            local key = nav.MakeEdgeSlot(edge)
            if key and not seenSegments[key] then
                seenSegments[key] = true
                AddMiniSegment(children, "mini_base_" .. key, edge, "rgba(145,155,165,0.45)", 2)
                segmentPositions[key] = edge
            end
        end
    end

    for key, edge in pairs(segmentPositions) do
        AddMiniSegment(children, "mini_route_" .. key, edge, "#2EE66B", 5)
    end

    for nodeId = 1, #rn.nodes do
        local node = rn.nodes[nodeId]
        if node then
            local x, y = MiniPoint(node)
            AddMiniMarker(children, "mini_node_" .. nodeId, x, y, 4, "rgba(215,220,225,0.7)", 2)
        end
    end

    for key, edge in pairs(segmentPositions) do
        local fromNode = rn.nodes[edge.fromNode]
        local toNode = rn.nodes[edge.toNode]
        local x1, y1 = MiniPoint(fromNode)
        local x2, y2 = MiniPoint(toNode)
        local x = (x1 + x2) * 0.5
        local y = (y1 + y2) * 0.5
        AddMiniMarker(children, "mini_target_" .. key, x, y, 10, "#FFD34D", 2)
    end

    for nodeId = 1, #rn.nodes do
        local node = rn.nodes[nodeId]
        if node then
            local x, y = MiniPoint(node)
            AddMiniMarker(children, "mini_target_n" .. nodeId, x, y, 10, "#FFD34D", 2)
        end
    end

    for key, edge in pairs(segmentPositions) do
        local fromNode = rn.nodes[edge.fromNode]
        local toNode = rn.nodes[edge.toNode]
        local x1, y1 = MiniPoint(fromNode)
        local x2, y2 = MiniPoint(toNode)
        local x = (x1 + x2) * 0.5
        local y = (y1 + y2) * 0.5
        AddMiniMarker(children, "mini_pickup_" .. key, x, y, 9, "#FF5AA5", 5)
    end

    for key, edge in pairs(segmentPositions) do
        AddMiniPlayerProgressMarkers(children, key, edge)
    end

    for nodeId = 1, #rn.nodes do
        local node = rn.nodes[nodeId]
        if node then
            local x, y = MiniPoint(node)
            AddMiniMarker(children, "mini_player_n" .. nodeId, x, y, 8, "#8A5CFF", 4)
        end
    end

    table.insert(children, UI.Label {
        id = "miniStatus",
        text = "等待订单",
        position = "absolute",
        left = 8,
        top = 126,
        width = MINI_PANEL_W - 16,
        height = 20,
        fontSize = 12,
        fontColor = {220,230,235,255},
    })

    return UI.Panel {
        id = "minimapPanel",
        width = MINI_PANEL_W,
        height = MINI_PANEL_H,
        position = "absolute",
        right = 12,
        top = 92,
        backgroundColor = "rgba(12,18,24,0.72)",
        borderRadius = 8,
        children = children,
    }
end

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
                    UI.Panel {
                        width = 112,
                        height = 28,
                        children = {
                            UI.Label {
                                id = "timerNormal",
                                text = "等待订单",
                                position = "absolute",
                                left = 0,
                                top = 0,
                                width = 112,
                                height = 28,
                                fontSize = 18,
                                fontColor = {235,235,235,255},
                            },
                            UI.Label {
                                id = "timerWarning",
                                text = "订单 5s",
                                position = "absolute",
                                left = 0,
                                top = 0,
                                width = 112,
                                height = 28,
                                fontSize = 18,
                                fontColor = {255,210,64,255},
                            },
                            UI.Label {
                                id = "timerLate",
                                text = "迟到 1s",
                                position = "absolute",
                                left = 0,
                                top = 0,
                                width = 112,
                                height = 28,
                                fontSize = 18,
                                fontColor = {255,88,88,255},
                            },
                        },
                    },
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
    M.gameOverPanel = UI.Panel {
        id = "gameOverPanel",
        width = "100%", height = "100%",
        position = "absolute",
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
    M.gameOverPanel:SetVisible(false)
    M.minimapPanel = BuildMinimap()

    -- 将 HUD 和 gameOverPanel 合并到同一个根面板
    local root = UI.Panel {
        width = "100%", height = "100%",
        children = {
            hud,
            M.minimapPanel,
            M.gameOverPanel,
        },
    }
    UI.SetRoot(root)

    M.lblTimerNormal = root:FindById("timerNormal")
    M.lblTimerWarning = root:FindById("timerWarning")
    M.lblTimerLate = root:FindById("timerLate")
    M.lblTimer = M.lblTimerNormal
    M.lblIncome = root:FindById("income")
    M.lblCombo = root:FindById("combo")
    M.lblSpeed = root:FindById("speed")
    M.lblHint = root:FindById("hint")
    M.lblFinalIncome = root:FindById("finalIncome")
    M.lblFinalDist = root:FindById("finalDist")
    M.lblMiniStatus = root:FindById("miniStatus")

    M.minimapRouteSegments = {}
    M.minimapPlayerMarkers = {}
    M.minimapTargetMarkers = {}
    M.minimapPickupMarkers = {}
    for edgeId = 1, #rn.edges do
        local edge = rn.edges[edgeId]
        if edge then
            local key = nav.MakeEdgeSlot(edge)
            if key and not M.minimapRouteSegments[key] then
                M.minimapRouteSegments[key] = root:FindById("mini_route_" .. key)
                M.minimapTargetMarkers[key] = root:FindById("mini_target_" .. key)
                M.minimapPickupMarkers[key] = root:FindById("mini_pickup_" .. key)
                for step = 0, nav.MINIMAP_PLAYER_EDGE_STEPS do
                    local playerKey = "p" .. key .. "_" .. step
                    M.minimapPlayerMarkers[playerKey] = root:FindById("mini_player_" .. playerKey)
                end
            end
        end
    end
    for nodeId = 1, #rn.nodes do
        local key = nav.MakeNodeSlot(nodeId)
        M.minimapPlayerMarkers[key] = root:FindById("mini_player_" .. key)
        M.minimapTargetMarkers[key] = root:FindById("mini_target_" .. key)
    end

    M.UpdateMinimap(nil)
    M.SetOrderTimerDisplay(nil)
end

local function BuildAvailableTurnsText(availableTurns)
    local hasLeft = false
    local hasStraight = false
    local hasRight = false

    for _, turn in ipairs(availableTurns or {}) do
        if turn.direction == "left" then
            hasLeft = true
        elseif turn.direction == "straight" then
            hasStraight = true
        elseif turn.direction == "right" then
            hasRight = true
        end
    end

    local parts = {}
    if hasLeft then table.insert(parts, "←左转") end
    if hasStraight then table.insert(parts, "↑直走") end
    if hasRight then table.insert(parts, "→右转") end

    if #parts == 0 then
        return "路口"
    end
    return "路口: " .. table.concat(parts, "  ")
end

local function AppendSuggestedTurn(text, navData)
    if navData and navData.suggested and navData.suggested.text then
        local suggested = "建议: " .. navData.suggested.text
        if text and text ~= "" then
            return text .. "  " .. suggested
        end
        return suggested
    end
    return text
end

function M.SetOrderTimerDisplay(orderTimerData)
    local data = orderTimerData or { state = "waiting", text = "等待订单" }
    local state = data.state or "waiting"
    local text = data.text or "等待订单"

    if M.lblTimerNormal then
        M.lblTimerNormal:SetText(text)
        if state ~= "waiting" and state ~= "normal" then
            M.lblTimerNormal:SetText("")
        end
    end
    if M.lblTimerWarning then
        if state == "warning" then
            M.lblTimerWarning:SetText(text)
        else
            M.lblTimerWarning:SetText("")
        end
    end
    if M.lblTimerLate then
        if state == "late" then
            M.lblTimerLate:SetText(text)
        else
            M.lblTimerLate:SetText("")
        end
    end
end

function M.UpdateHUD(orderTimerData, totalIncome, comboCount, currentSpeed, intersectionActive, turnChoice, hasTurnChoice, availableTurns, navData)
    M.SetOrderTimerDisplay(orderTimerData)

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
            if hasTurnChoice then
                -- 玩家已做出选择
                if turnChoice == -1 then
                    hintText = "← 已选: 左转"
                elseif turnChoice == 1 then
                    hintText = "→ 已选: 右转"
                else
                    hintText = "↑ 已选: 直走"
                end
            else
                hintText = BuildAvailableTurnsText(availableTurns)
            end
            M.lblHint:SetText(AppendSuggestedTurn(hintText, navData))
        elseif navData and navData.transientMessage and navData.message ~= "" then
            M.lblHint:SetText(navData.message)
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

local function SetOnlyVisible(markers, activeKey)
    for key, marker in pairs(markers or {}) do
        if marker then
            marker:SetVisible(activeKey ~= nil and key == activeKey)
        end
    end
end

function M.UpdateMinimap(navData, pickupMiniData)
    if M.lblMiniStatus then
        if navData and navData.message then
            M.lblMiniStatus:SetText(navData.message)
        else
            M.lblMiniStatus:SetText("等待订单")
        end
    end

    local routeSegments = navData and navData.routeSegments or {}
    for key, segment in pairs(M.minimapRouteSegments or {}) do
        if segment then
            segment:SetVisible(navData ~= nil and navData.active and routeSegments[key] == true)
        end
    end

    SetOnlyVisible(M.minimapPickupMarkers, pickupMiniData and pickupMiniData.active and pickupMiniData.slot or nil)
    SetOnlyVisible(M.minimapPlayerMarkers, navData and navData.playerSlot or nil)
    SetOnlyVisible(M.minimapTargetMarkers, navData and navData.active and navData.targetSlot or nil)
end

return M
