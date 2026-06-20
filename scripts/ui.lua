-- ============================================================================
-- 外卖冲冲冲 - UI 模块
-- ============================================================================

local UI = require("urhox-libs/UI")
local cfg = require("config")
local CONFIG = cfg.CONFIG
local rn = require("road_network")
local nav = require("route_navigation")
local cam = require("camera")
local progression = require("progression")
local meta = require("meta_progress")
local systemPages = require("ui_system_pages")

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
M.lblRiderLevel = nil
M.lblRiderXP = nil
M.lblMenuRiderLevel = nil
M.lblMenuCoins = nil
M.lblMenuBest = nil
M.powerupPanel = nil
M.btnPowerup = nil
M.lblPowerupStatus = nil
M.hudPanel = nil
M.mainMenuPanel = nil
M.menuCloudOne = nil
M.menuCloudTwo = nil
M.menuLaneStrip = nil
M.menuLaneStrips = {}
M.menuSpeedLineA = nil
M.menuSpeedLineB = nil
M.menuSpeedLineC = nil
M.menuCoinIcon = nil
M.menuRiderShadow = nil
M.menuRiderPanel = nil
M.menuStartButton = nil
M.menuXpFill = nil
M.pauseOverlayPanel = nil
M.staticPagePanel = nil
M.systemPageRefs = nil
M.staticBackMode = "menu"
M.staticPageKey = nil
M.gameOverPanel = nil
M.lblFinalIncome = nil
M.lblFinalDist = nil
M.lblFinalStats = nil
M.lblFinalGain = nil
M.lblFinalLevel = nil
M.lblFinalUnlocks = nil
M.minimapPanel = nil
M.minimapOrderListPanel = nil
M.lblMiniStatus = nil
M.debugPanel = nil
M.btnDebugToggle = nil
M.debugPanelVisible = false
M.lblDebugOffsetY = nil
M.lblDebugOffsetZ = nil
M.lblDebugLookAhead = nil
M.lblDebugYawOffset = nil
M.lblDebugPitchOffset = nil
M.lblDebugFovBase = nil
M.lblDebugFovMax = nil
M.lblDebugFovCurrent = nil
M.btnPause = nil
M.minimapRouteSegments = {}
M.minimapPlayerMarkers = {}
M.minimapTargetMarkers = {}
M.minimapPickupMarkers = {}
M.minimapOrderRows = {}
M.minimapOrderDots = {}
M.minimapOrderTexts = {}
M.preciseRouteNodes = {}
M.precisePickupNodes = {}
M.onRestart = nil
M.onTogglePause = nil
M.onStartGame = nil
M.onReturnMenu = nil
M.onUsePowerup = nil
M.minimapVersion = -1
M.rootPanel = nil
M.activePickupSlot = nil
M.activePickupSlots = {}
M.activePlayerSlot = nil
M.activeTargetSlot = nil
M.activeRouteSegments = {}
M.lastRouteSegments = {}
M.lastPreciseRouteKey = nil
M.precisePlayerMarker = nil
M.preciseTargetMarker = nil
M.precisePlayerMarkerKey = nil
M.preciseTargetMarkerKey = nil

local MINI_PANEL_W = 132
local MINI_PANEL_H = 148
local MINI_ORDER_LIST_W = 132
local MINI_ORDER_LIST_TOP = 248
local MINI_ORDER_ROW_H = 18
local MINI_ORDER_ROW_GAP = 5
local MINI_ORDER_LIST_PADDING_Y = 8
local MINI_MAP_SIZE = 104
local MINI_LEFT = 10
local MINI_TOP = 28
local MINI_MARGIN = 10

local DEBUG_PANEL_W = 214
local DEBUG_PANEL_H = 274
local DEBUG_RIGHT = 12
local DEBUG_TOP = 374
local DEBUG_STEP_SMALL = 0.25
local DEBUG_STEP_BIG = 1.0
local DEBUG_STEP_ANGLE = 2.5
local DEBUG_STEP_PITCH = 0.25

local ORDER_TYPE_NAMES = {
    normal = "普通",
    nearby = "顺路",
    rush = "急送",
    long = "远距",
    fragile = "易碎",
}

local function Pct(value)
    return string.format("%.3f%%", value)
end

local function X(value)
    return Pct(value / 390 * 100)
end

local function Y(value)
    return Pct(value / 844 * 100)
end

local function W(value)
    return Pct(value / 390 * 100)
end

local function H(value)
    return Pct(value / 844 * 100)
end

local function MakeImagePanel(id, image, left, top, width, height, fit, opacity)
    return UI.Panel {
        id = id,
        position = "absolute",
        left = X(left),
        top = Y(top),
        width = W(width),
        height = H(height),
        backgroundImage = image,
        backgroundFit = fit or "fill",
        opacity = opacity,
    }
end

local function SetNodeStyle(node, style)
    if node and node.SetStyle then
        node:SetStyle(style)
    end
end

local function MakeLocalImagePanel(id, image, left, top, width, height, fit)
    return UI.Panel {
        id = id,
        position = "absolute",
        left = left,
        top = top,
        width = width,
        height = height,
        backgroundImage = image,
        backgroundFit = fit or "fill",
    }
end

local function FormatSigned(value)
    if value >= 0 then
        return string.format("+%.2f", value)
    end
    return string.format("%.2f", value)
end

local function MakeRowLabel(prefix, valueText)
    return UI.Label {
        id = prefix,
        text = valueText,
        fontSize = 12,
        fontColor = {230,235,240,255},
    }
end

local function MakeStepButton(text, onClick)
    return UI.Button {
        text = text,
        width = 24,
        height = 22,
        onClick = onClick,
    }
end

local function MakeNavButton(text, onClick)
    return UI.Button {
        text = text,
        width = 58,
        height = 50,
        marginLeft = 3,
        marginRight = 3,
        onClick = onClick,
    }
end

local function MakeMenuStat(text, id)
    return UI.Label {
        id = id,
        text = text,
        fontSize = 13,
        fontWeight = "bold",
        fontColor = {255,255,255,255},
    }
end

local function FormatUnlockedOrderTypes(typeIds)
    local parts = {}
    for _, typeId in ipairs(typeIds or {}) do
        parts[#parts + 1] = ORDER_TYPE_NAMES[typeId] or typeId
    end
    if #parts == 0 then
        return "普通"
    end
    return table.concat(parts, " / ")
end

local function FormatOnOff(value)
    return value and "开" or "关"
end

local function MakePanelTitle(text)
    return UI.Label {
        text = text,
        fontSize = 24,
        fontWeight = "bold",
        fontColor = {30,38,46,255},
    }
end

local function HandleUpgradeClick(key)
    if not key then
        return
    end
    local ok, message = meta.TryUpgrade(key)
    progression.ApplyMetaState(meta.GetRiderState())
    print("[UI] " .. tostring(message))
    M.ShowStaticPage("upgrades", M.staticBackMode)
end

local function HandleUpgradeIndexClick(index)
    local key = systemPages.GetUpgradeKey and systemPages.GetUpgradeKey(index)
    HandleUpgradeClick(key)
end

local function HandleUpgradeAllClick()
    local keys = meta.GetUpgradeKeys and meta.GetUpgradeKeys() or {}
    local upgraded = 0
    local messages = {}
    for _, key in ipairs(keys) do
        local ok, message = meta.TryUpgrade(key)
        if ok then
            upgraded = upgraded + 1
            messages[#messages + 1] = message
        end
    end
    progression.ApplyMetaState(meta.GetRiderState())
    if upgraded > 0 then
        print("[UI] 批量升级 " .. tostring(upgraded) .. " 项: " .. table.concat(messages, " / "))
    else
        print("[UI] 没有可购买升级项")
    end
    M.ShowStaticPage("upgrades", M.staticBackMode)
end

local function HandleSettingClick(action)
    if not action then
        return
    end

    local message = ""
    if action.key == "controlMode" then
        local mode = meta.CycleControlMode and meta.CycleControlMode() or "混合"
        message = "操作方式: " .. tostring(mode)
    elseif action.key == "debugPanel" then
        local ok, value = meta.ToggleSetting(action.key)
        message = ok and ("调试面板: " .. FormatOnOff(value)) or tostring(value)
        if not value and M.debugPanel then
            M.debugPanelVisible = false
            M.debugPanel:SetVisible(false)
        end
    else
        local ok, value = false, nil
        if meta.ToggleSetting then
            ok, value = meta.ToggleSetting(action.key)
        end
        message = ok and (action.text .. ": " .. FormatOnOff(value)) or tostring(value)
    end

    print("[UI] " .. tostring(message))
    M.ShowStaticPage("settings", M.staticBackMode)
end

local function HandleSettingKeyClick(key)
    HandleSettingClick(systemPages.GetSettingAction and systemPages.GetSettingAction(key))
end

local function HandleSettingsSaveClick()
    if meta.Save then
        meta.Save()
    end
    print("[UI] 设置已保存")
    M.ShowStaticPage("settings", M.staticBackMode)
end

local function ClaimAvailable(claimFunc)
    if not claimFunc then
        return false, "领取接口不存在"
    end
    return claimFunc()
end

local function HandleTaskClaimClick()
    local ok, message = ClaimAvailable(meta.ClaimAvailableTasks)
    progression.ApplyMetaState(meta.GetRiderState())
    print("[UI] " .. tostring(message))
    M.ShowStaticPage("tasks", M.staticBackMode)
end

local function HandleAchievementClaimClick()
    local ok, message = ClaimAvailable(meta.ClaimAvailableAchievements)
    progression.ApplyMetaState(meta.GetRiderState())
    print("[UI] " .. tostring(message))
    M.ShowStaticPage("achievements", M.staticBackMode)
end

local function HandleProgressClaimOne(prefix, index)
    local rows = {}
    local claimFunc = nil
    local pageKey = nil

    if prefix == "task" then
        rows = meta.GetTaskRows and meta.GetTaskRows() or {}
        claimFunc = meta.ClaimTask
        pageKey = "tasks"
    elseif prefix == "achievement" then
        rows = meta.GetAchievementRows and meta.GetAchievementRows() or {}
        claimFunc = meta.ClaimAchievement
        pageKey = "achievements"
    end

    local row = rows[index or 0]
    if not row or not row.id or not claimFunc then
        print("[UI] 没有可领取目标")
        return
    end

    local ok, message = claimFunc(row.id)
    progression.ApplyMetaState(meta.GetRiderState())
    print("[UI] " .. tostring(message))
    if pageKey then
        M.ShowStaticPage(pageKey, M.staticBackMode)
    end
end

local function MiniWorldPoint(worldX, worldZ)
    local usable = MINI_MAP_SIZE - MINI_MARGIN * 2
    local bounds = rn.GetVisibleBounds and rn.GetVisibleBounds() or rn.bounds or { minX = 0, maxX = 1, minZ = 0, maxZ = 1 }
    local width = math.max(1.0, bounds.maxX - bounds.minX)
    local depth = math.max(1.0, bounds.maxZ - bounds.minZ)
    local x = MINI_LEFT + MINI_MARGIN + ((worldX - bounds.minX) / width) * usable
    local y = MINI_TOP + MINI_MARGIN + (1.0 - ((worldZ - bounds.minZ) / depth)) * usable
    return x, y
end

local function MiniPoint(node)
    return MiniWorldPoint(node.worldX, node.worldZ)
end

local function IsMiniPixelVisible(x, y)
    return x >= MINI_LEFT and x <= MINI_LEFT + MINI_MAP_SIZE
        and y >= MINI_TOP and y <= MINI_TOP + MINI_MAP_SIZE
end

local function MakeMiniSegmentPanel(id, x1, y1, x2, y2, color, thickness)
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

    return UI.Panel {
        id = id,
        position = "absolute",
        left = left,
        top = top,
        width = width,
        height = height,
        backgroundColor = color,
        borderRadius = thickness,
    }
end

local function AddMiniSegment(children, id, edge, color, thickness)
    local fromNode = rn.GetNode(edge.fromNode)
    local toNode = rn.GetNode(edge.toNode)
    if not fromNode or not toNode then return end

    local x1, y1 = MiniPoint(fromNode)
    local x2, y2 = MiniPoint(toNode)
    table.insert(children, MakeMiniSegmentPanel(id, x1, y1, x2, y2, color, thickness))
end

local function MakeMiniMarkerPanel(id, x, y, size, color, radius)
    return UI.Panel {
        id = id,
        position = "absolute",
        left = x - size * 0.5,
        top = y - size * 0.5,
        width = size,
        height = size,
        backgroundColor = color,
        borderRadius = radius or size * 0.5,
    }
end

local function AddMiniMarker(children, id, x, y, size, color, radius)
    table.insert(children, MakeMiniMarkerPanel(id, x, y, size, color, radius))
end

local function MakeMiniPlayerMarkerPanel(id, x, y, heading)
    local symbol = "▲"
    if heading == 1 then
        symbol = "▶"
    elseif heading == 2 then
        symbol = "▼"
    elseif heading == 3 then
        symbol = "◀"
    end

    return UI.Label {
        id = id,
        text = symbol,
        position = "absolute",
        left = x - 8,
        top = y - 10,
        width = 16,
        height = 18,
        fontSize = 15,
        fontWeight = "bold",
        fontColor = {255,47,47,255},
        textAlign = "center",
    }
end

local function AddMiniPlayerMarker(children, id, x, y, heading)
    table.insert(children, MakeMiniPlayerMarkerPanel(id, x, y, heading))
end

local function GetOrderMarkerColor(order)
    return (order and (order.markerColor or order.color)) or "#2DD4BF"
end

local function GetOrderListDotColor(order)
    return (order and order.labelColor) or GetOrderMarkerColor(order)
end

local function MakeMiniOrderRow(index)
    return UI.Panel {
        id = "miniOrderRow" .. tostring(index),
        width = MINI_ORDER_LIST_W - 16,
        height = MINI_ORDER_ROW_H,
        flexDirection = "row",
        alignItems = "center",
        children = {
            UI.Panel {
                id = "miniOrderDot" .. tostring(index),
                width = 9,
                height = 9,
                backgroundColor = "#2DD4BF",
                borderRadius = 5,
            },
            UI.Label {
                id = "miniOrderText" .. tostring(index),
                text = "",
                width = MINI_ORDER_LIST_W - 31,
                height = MINI_ORDER_ROW_H,
                marginLeft = 6,
                fontSize = 12,
                fontWeight = "bold",
                fontColor = {36,54,64,255},
            },
        },
    }
end

local function BuildMiniOrderList()
    ---@type any[]
    local children = {
        UI.Label {
            text = "可接订单",
            width = MINI_ORDER_LIST_W - 16,
            height = 16,
            fontSize = 11,
            fontWeight = "bold",
            fontColor = {255,138,31,255},
            textAlign = "center",
        },
    }
    local maxRows = CONFIG.ORDER_AVAILABLE_COUNT_MAX or 5
    for i = 1, maxRows do
        children[#children + 1] = MakeMiniOrderRow(i)
    end

    return UI.Panel {
        id = "miniOrderList",
        width = MINI_ORDER_LIST_W,
        height = 16 + maxRows * MINI_ORDER_ROW_H + maxRows * MINI_ORDER_ROW_GAP + MINI_ORDER_LIST_PADDING_Y * 2,
        position = "absolute",
        right = 12,
        top = MINI_ORDER_LIST_TOP,
        padding = MINI_ORDER_LIST_PADDING_Y,
        flexDirection = "column",
        gap = MINI_ORDER_ROW_GAP,
        backgroundColor = "rgba(255,248,224,0.94)",
        borderRadius = 12,
        children = children,
    }
end

local function BuildPowerupPanel()
    return UI.Panel {
        id = "powerupPanel",
        width = 142,
        height = 66,
        position = "absolute",
        left = 14,
        top = 724,
        padding = 7,
        flexDirection = "column",
        alignItems = "center",
        backgroundColor = "rgba(255,248,224,0.94)",
        borderRadius = 18,
        children = {
            UI.Button {
                id = "powerupButton",
                text = "无道具",
                width = 128,
                height = 34,
                backgroundColor = "#28B8F0",
                borderRadius = 17,
                borderWidth = 0,
                fontSize = 16,
                fontWeight = "bold",
                fontColor = {255,255,255,255},
                onClick = function()
                    if M.onUsePowerup then
                        M.onUsePowerup()
                    end
                end,
            },
            UI.Label {
                id = "powerupStatus",
                text = "",
                width = 128,
                height = 16,
                marginTop = 3,
                fontSize = 11,
                fontWeight = "bold",
                fontColor = {91,54,8,255},
                textAlign = "center",
            },
        },
    }
end

local function AddMiniPlayerProgressMarkers(children, key, edge)
    local nodeA = rn.GetNode(math.min(edge.fromNode, edge.toNode))
    local nodeB = rn.GetNode(math.max(edge.fromNode, edge.toNode))
    if not nodeA or not nodeB then return end

    local x1, y1 = MiniPoint(nodeA)
    local x2, y2 = MiniPoint(nodeB)
    for step = 0, nav.MINIMAP_PLAYER_EDGE_STEPS do
        local t = step / nav.MINIMAP_PLAYER_EDGE_STEPS
        local x = x1 + (x2 - x1) * t
        local y = y1 + (y2 - y1) * t
        AddMiniPlayerMarker(children, "mini_player_p" .. key .. "_" .. step, x, y, edge.heading)
    end
end

local function RemoveNode(node)
    if node then
        node:Remove()
    end
end

local function ClearPreciseMinimapNodes()
    for _, node in ipairs(M.preciseRouteNodes or {}) do
        RemoveNode(node)
    end
    M.preciseRouteNodes = {}

    for _, item in pairs(M.precisePickupNodes or {}) do
        RemoveNode(item.marker)
    end
    M.precisePickupNodes = {}

    RemoveNode(M.precisePlayerMarker)
    RemoveNode(M.preciseTargetMarker)
    M.precisePlayerMarker = nil
    M.preciseTargetMarker = nil
    M.precisePlayerMarkerKey = nil
    M.preciseTargetMarkerKey = nil
    M.lastPreciseRouteKey = nil
end

local function RouteLinesKey(lines)
    if not lines or #lines == 0 then return "" end

    local parts = {}
    for i, line in ipairs(lines) do
        local x1, y1 = MiniWorldPoint(line.x1, line.z1)
        local x2, y2 = MiniWorldPoint(line.x2, line.z2)
        parts[i] = string.format(
            "%d:%.0f,%.0f,%.0f,%.0f",
            line.edgeId or 0,
            x1,
            y1,
            x2,
            y2
        )
    end
    return table.concat(parts, "|")
end

local function RebuildPreciseRouteLines(lines)
    if not M.minimapPanel then return end

    for _, node in ipairs(M.preciseRouteNodes or {}) do
        RemoveNode(node)
    end
    M.preciseRouteNodes = {}

    for i, line in ipairs(lines or {}) do
        local x1, y1 = MiniWorldPoint(line.x1, line.z1)
        local x2, y2 = MiniWorldPoint(line.x2, line.z2)
        if IsMiniPixelVisible(x1, y1) or IsMiniPixelVisible(x2, y2) then
            local node = MakeMiniSegmentPanel("mini_route_precise_" .. i, x1, y1, x2, y2, "#00E6B8", 4)
            M.minimapPanel:AddChild(node)
            M.preciseRouteNodes[#M.preciseRouteNodes + 1] = node
        end
    end
end

local function SetPreciseMarker(existingNode, existingKey, id, point, size, color, radius)
    if not M.minimapPanel or not point then
        if existingNode then
            existingNode:Remove()
        end
        return nil, nil
    end

    local x, y = MiniWorldPoint(point.x, point.z)
    if not IsMiniPixelVisible(x, y) then
        if existingNode then
            existingNode:Remove()
        end
        return nil, nil
    end

    local nextKey = string.format("%.0f,%.0f", x, y)
    if existingNode and existingKey == nextKey then
        return existingNode, existingKey
    end

    if existingNode then
        existingNode:Remove()
        existingNode = nil
    end

    local node = MakeMiniMarkerPanel(id, x, y, size, color, radius)
    M.minimapPanel:AddChild(node)
    return node, nextKey
end

local function SetPrecisePlayerMarker(existingNode, existingKey, point)
    if not M.minimapPanel or not point then
        if existingNode then
            existingNode:Remove()
        end
        return nil, nil
    end

    local x, y = MiniWorldPoint(point.x, point.z)
    if not IsMiniPixelVisible(x, y) then
        if existingNode then
            existingNode:Remove()
        end
        return nil, nil
    end

    local heading = point.heading or 0
    local nextKey = string.format("%.0f,%.0f,%s", x, y, tostring(heading))
    if existingNode and existingKey == nextKey then
        return existingNode, existingKey
    end

    if existingNode then
        existingNode:Remove()
    end

    local node = MakeMiniPlayerMarkerPanel("mini_player_precise", x, y, heading)
    M.minimapPanel:AddChild(node)
    return node, nextKey
end

local function MakeOrderPoint(order)
    if not order or not order.edgeId or not order.edgeDist then return nil end

    local edge = rn.GetEdge(order.edgeId)
    if not edge then return nil end

    local laneOffset = 0.0
    if order.lane and CONFIG.LANE_X then
        laneOffset = CONFIG.LANE_X[order.lane] or 0.0
    end

    local pos = rn.GetPositionOnEdgeByDist(edge, order.edgeDist, laneOffset)
    return {
        x = pos.x,
        z = pos.z,
    }
end

local function HideLegacyPickupSlot(key)
    if not key then return end
    if M.minimapPickupMarkers[key] then
        M.minimapPickupMarkers[key]:SetVisible(false)
    end
end

local function SetPrecisePickupOrders(pickupMiniData)
    local active = {}

    if pickupMiniData and pickupMiniData.orders then
        for index, order in ipairs(pickupMiniData.orders) do
            local key = tostring(order.id or order.slot or index)
            local point = MakeOrderPoint(order)
            if key and point and M.minimapPanel then
                local x, y = MiniWorldPoint(point.x, point.z)
                local markerColor = GetOrderMarkerColor(order)
                local existing = M.precisePickupNodes[key]
                if not IsMiniPixelVisible(x, y) then
                    if existing then
                        RemoveNode(existing.marker)
                        M.precisePickupNodes[key] = nil
                    end
                    HideLegacyPickupSlot(order.slot)
                    active[key] = true
                else
                    local positionKey = string.format("%.0f,%.0f,%s", x, y, markerColor)
                    if existing and existing.positionKey ~= positionKey then
                        RemoveNode(existing.marker)
                        existing = nil
                    end
                    if not existing then
                        local marker = MakeMiniMarkerPanel("mini_pickup_precise_" .. key, x, y, 10, markerColor, 5)
                        M.minimapPanel:AddChild(marker)
                        M.precisePickupNodes[key] = {
                            marker = marker,
                            positionKey = positionKey,
                        }
                    end
                    active[key] = true
                    HideLegacyPickupSlot(order.slot)
                end
            end
        end
    end

    for key, item in pairs(M.precisePickupNodes or {}) do
        if not active[key] then
            RemoveNode(item.marker)
            M.precisePickupNodes[key] = nil
        end
    end
end

local function UpdatePreciseNavigation(navData)
    local hasPrecise = navData and navData.active and navData.routeLines and #navData.routeLines > 0
    if hasPrecise then
        local key = RouteLinesKey(navData.routeLines)
        if key ~= M.lastPreciseRouteKey then
            RebuildPreciseRouteLines(navData.routeLines)
            M.lastPreciseRouteKey = key
        end
    else
        RebuildPreciseRouteLines({})
        M.lastPreciseRouteKey = nil
    end

    return hasPrecise
end

local function UpdatePreciseNavigationMarkers(navData)
    M.precisePlayerMarker, M.precisePlayerMarkerKey = SetPrecisePlayerMarker(
        M.precisePlayerMarker,
        M.precisePlayerMarkerKey,
        navData and navData.playerPoint or nil
    )

    M.preciseTargetMarker, M.preciseTargetMarkerKey = SetPreciseMarker(
        M.preciseTargetMarker,
        M.preciseTargetMarkerKey,
        "mini_target_precise",
        navData and navData.active and navData.targetPoint or nil,
        12,
        "#FFE15A",
        2
    )
end

local function BindMinimapRefs(root)
    M.minimapRouteSegments = {}
    M.minimapPlayerMarkers = {}
    M.minimapTargetMarkers = {}
    M.minimapPickupMarkers = {}
    M.activePickupSlot = nil
    M.activePickupSlots = {}
    M.activePlayerSlot = nil
    M.activeTargetSlot = nil
    M.activeRouteSegments = {}
    M.lastRouteSegments = {}

    rn.ForEachVisibleEdge(function(edge)
        if edge then
            local key = nav.MakeEdgeSlot(edge)
            if key and not M.minimapRouteSegments[key] then
                M.minimapRouteSegments[key] = root:FindById("mini_route_" .. key)
                M.minimapTargetMarkers[key] = root:FindById("mini_target_" .. key)
                M.minimapPickupMarkers[key] = root:FindById("mini_pickup_" .. key)
                if M.minimapRouteSegments[key] then M.minimapRouteSegments[key]:SetVisible(false) end
                if M.minimapTargetMarkers[key] then M.minimapTargetMarkers[key]:SetVisible(false) end
                if M.minimapPickupMarkers[key] then M.minimapPickupMarkers[key]:SetVisible(false) end
                for step = 0, nav.MINIMAP_PLAYER_EDGE_STEPS do
                    local playerKey = "p" .. key .. "_" .. step
                    M.minimapPlayerMarkers[playerKey] = root:FindById("mini_player_" .. playerKey)
                    if M.minimapPlayerMarkers[playerKey] then
                        M.minimapPlayerMarkers[playerKey]:SetVisible(false)
                    end
                end
            end
        end
    end)

    rn.ForEachVisibleNode(function(node)
        local key = nav.MakeNodeSlot(node.id)
        M.minimapPlayerMarkers[key] = root:FindById("mini_player_" .. key)
        M.minimapTargetMarkers[key] = root:FindById("mini_target_" .. key)
        if M.minimapPlayerMarkers[key] then M.minimapPlayerMarkers[key]:SetVisible(false) end
        if M.minimapTargetMarkers[key] then M.minimapTargetMarkers[key]:SetVisible(false) end
    end)
end

local function BuildMinimap()
    local children = {
        UI.Label {
            text = "路线雷达",
            position = "absolute",
            left = 10,
            top = 7,
            width = 74,
            height = 17,
            fontSize = 12,
            fontWeight = "bold",
            fontColor = {255,255,255,255},
        },
        UI.Label {
            text = "N",
            position = "absolute",
            left = 102,
            top = 7,
            width = 20,
            height = 17,
            fontSize = 11,
            fontWeight = "bold",
            fontColor = {92,221,255,255},
            textAlign = "right",
        },
    }
    local seenSegments = {}
    local segmentPositions = {}

    rn.ForEachVisibleEdge(function(edge)
        if edge then
            local key = nav.MakeEdgeSlot(edge)
            if key and not seenSegments[key] then
                seenSegments[key] = true
                AddMiniSegment(children, "mini_base_" .. key, edge, "rgba(145,155,165,0.32)", 2)
                segmentPositions[key] = edge
            end
        end
    end)

    for key, edge in pairs(segmentPositions) do
        AddMiniSegment(children, "mini_route_" .. key, edge, "#00E6B8", 4)
    end

    rn.ForEachVisibleNode(function(node)
        if node then
            local x, y = MiniPoint(node)
            AddMiniMarker(children, "mini_node_" .. node.id, x, y, 4, "rgba(215,220,225,0.7)", 2)
        end
    end)

    for key, edge in pairs(segmentPositions) do
        local fromNode = rn.GetNode(edge.fromNode)
        local toNode = rn.GetNode(edge.toNode)
        local x1, y1 = MiniPoint(fromNode)
        local x2, y2 = MiniPoint(toNode)
        local x = (x1 + x2) * 0.5
        local y = (y1 + y2) * 0.5
        AddMiniMarker(children, "mini_target_" .. key, x, y, 11, "#FFE15A", 2)
    end

    rn.ForEachVisibleNode(function(node)
        if node then
            local x, y = MiniPoint(node)
            AddMiniMarker(children, "mini_target_n" .. node.id, x, y, 11, "#FFE15A", 2)
        end
    end)

    for key, edge in pairs(segmentPositions) do
        local fromNode = rn.GetNode(edge.fromNode)
        local toNode = rn.GetNode(edge.toNode)
        local x1, y1 = MiniPoint(fromNode)
        local x2, y2 = MiniPoint(toNode)
        local x = (x1 + x2) * 0.5
        local y = (y1 + y2) * 0.5
        AddMiniMarker(children, "mini_pickup_" .. key, x, y, 9, "#2DD4BF", 5)
    end

    for key, edge in pairs(segmentPositions) do
        AddMiniPlayerProgressMarkers(children, key, edge)
    end

    rn.ForEachVisibleNode(function(node)
        if node then
            local x, y = MiniPoint(node)
            AddMiniPlayerMarker(children, "mini_player_n" .. node.id, x, y, 0)
        end
    end)

    table.insert(children, UI.Label {
        id = "miniStatus",
        text = "等待订单",
        position = "absolute",
        left = 10,
        top = 132,
        width = MINI_PANEL_W - 20,
        height = 15,
        fontSize = 12,
        fontWeight = "bold",
        fontColor = {255,232,118,255},
        textAlign = "center",
    })

    return UI.Panel {
        id = "minimapPanel",
        width = MINI_PANEL_W,
        height = MINI_PANEL_H,
        position = "absolute",
        right = 12,
        top = 92,
        backgroundColor = "rgba(15,28,42,0.78)",
        borderRadius = 14,
        children = children,
    }
end

local RefreshDebugPanel

local function ApplyDebugParam(label, key, delta, formatter)
    local value = cam.AdjustDebugParam(key, delta)
    if label and value ~= nil then
        label:SetText(formatter and formatter(value) or tostring(value))
    end
    RefreshDebugPanel()
end

RefreshDebugPanel = function()
    local params = cam.GetDebugParams()
    if M.lblDebugOffsetY then
        M.lblDebugOffsetY:SetText(string.format("高度: %s", FormatSigned(params.offsetY)))
    end
    if M.lblDebugOffsetZ then
        M.lblDebugOffsetZ:SetText(string.format("距离: %s", FormatSigned(params.offsetZ)))
    end
    if M.lblDebugLookAhead then
        M.lblDebugLookAhead:SetText(string.format("前视: %s", FormatSigned(params.lookAhead)))
    end
    if M.lblDebugYawOffset then
        M.lblDebugYawOffset:SetText(string.format("侧角: %s°", FormatSigned(params.yawOffset)))
    end
    if M.lblDebugPitchOffset then
        M.lblDebugPitchOffset:SetText(string.format("俯仰: %s", FormatSigned(params.pitchOffset)))
    end
    if M.lblDebugFovBase then
        M.lblDebugFovBase:SetText(string.format("基础FOV: %.1f", params.fovBase))
    end
    if M.lblDebugFovMax then
        M.lblDebugFovMax:SetText(string.format("最大FOV: %.1f", params.fovMax))
    end
    if M.lblDebugFovCurrent then
        M.lblDebugFovCurrent:SetText(string.format("当前FOV: %.1f", cam.GetCurrentFov()))
    end
end

local function BuildDebugPanel()
    local rows = {
        UI.Panel {
            width = "100%",
            height = 24,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                UI.Label { text = "相机调试", fontSize = 14, fontColor = {255,255,255,255} },
                UI.Button {
                    text = "收起",
                    width = 42,
                    height = 22,
                    onClick = function()
                        if M.debugPanel then
                            M.debugPanel:SetVisible(false)
                        end
                        M.debugPanelVisible = false
                        if M.btnDebugToggle then
                            M.btnDebugToggle:SetText("相机")
                        end
                    end,
                },
            },
        },
        UI.Panel {
            width = "100%",
            height = 22,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                M.lblDebugOffsetY or MakeRowLabel("dbgOffsetY", "高度"),
                UI.Panel {
                    width = 78,
                    height = 22,
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    children = {
                        MakeStepButton("-", function() ApplyDebugParam(M.lblDebugOffsetY, "offsetY", -DEBUG_STEP_SMALL, function(v) return string.format("高度: %s", FormatSigned(v)) end) end),
                        MakeStepButton("+", function() ApplyDebugParam(M.lblDebugOffsetY, "offsetY", DEBUG_STEP_SMALL, function(v) return string.format("高度: %s", FormatSigned(v)) end) end),
                    },
                },
            },
        },
        UI.Panel {
            width = "100%",
            height = 22,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                M.lblDebugYawOffset or MakeRowLabel("dbgYawOffset", "侧角"),
                UI.Panel {
                    width = 78,
                    height = 22,
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    children = {
                        MakeStepButton("-", function() ApplyDebugParam(M.lblDebugYawOffset, "yawOffset", -DEBUG_STEP_ANGLE, function(v) return string.format("侧角: %s°", FormatSigned(v)) end) end),
                        MakeStepButton("+", function() ApplyDebugParam(M.lblDebugYawOffset, "yawOffset", DEBUG_STEP_ANGLE, function(v) return string.format("侧角: %s°", FormatSigned(v)) end) end),
                    },
                },
            },
        },
        UI.Panel {
            width = "100%",
            height = 22,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                M.lblDebugPitchOffset or MakeRowLabel("dbgPitchOffset", "俯仰"),
                UI.Panel {
                    width = 78,
                    height = 22,
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    children = {
                        MakeStepButton("-", function() ApplyDebugParam(M.lblDebugPitchOffset, "pitchOffset", -DEBUG_STEP_PITCH, function(v) return string.format("俯仰: %s", FormatSigned(v)) end) end),
                        MakeStepButton("+", function() ApplyDebugParam(M.lblDebugPitchOffset, "pitchOffset", DEBUG_STEP_PITCH, function(v) return string.format("俯仰: %s", FormatSigned(v)) end) end),
                    },
                },
            },
        },
        UI.Panel {
            width = "100%",
            height = 22,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                M.lblDebugOffsetZ or MakeRowLabel("dbgOffsetZ", "距离"),
                UI.Panel {
                    width = 78,
                    height = 22,
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    children = {
                        MakeStepButton("-", function() ApplyDebugParam(M.lblDebugOffsetZ, "offsetZ", -DEBUG_STEP_SMALL, function(v) return string.format("距离: %s", FormatSigned(v)) end) end),
                        MakeStepButton("+", function() ApplyDebugParam(M.lblDebugOffsetZ, "offsetZ", DEBUG_STEP_SMALL, function(v) return string.format("距离: %s", FormatSigned(v)) end) end),
                    },
                },
            },
        },
        UI.Panel {
            width = "100%",
            height = 22,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                M.lblDebugLookAhead or MakeRowLabel("dbgLookAhead", "前视"),
                UI.Panel {
                    width = 78,
                    height = 22,
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    children = {
                        MakeStepButton("-", function() ApplyDebugParam(M.lblDebugLookAhead, "lookAhead", -DEBUG_STEP_SMALL, function(v) return string.format("前视: %s", FormatSigned(v)) end) end),
                        MakeStepButton("+", function() ApplyDebugParam(M.lblDebugLookAhead, "lookAhead", DEBUG_STEP_SMALL, function(v) return string.format("前视: %s", FormatSigned(v)) end) end),
                    },
                },
            },
        },
        UI.Panel {
            width = "100%",
            height = 22,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                M.lblDebugFovBase or MakeRowLabel("dbgFovBase", "基础FOV"),
                UI.Panel {
                    width = 78,
                    height = 22,
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    children = {
                        MakeStepButton("-", function() ApplyDebugParam(M.lblDebugFovBase, "fovBase", -DEBUG_STEP_BIG, function(v) return string.format("基础FOV: %.1f", v) end) end),
                        MakeStepButton("+", function() ApplyDebugParam(M.lblDebugFovBase, "fovBase", DEBUG_STEP_BIG, function(v) return string.format("基础FOV: %.1f", v) end) end),
                    },
                },
            },
        },
        UI.Panel {
            width = "100%",
            height = 22,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                M.lblDebugFovMax or MakeRowLabel("dbgFovMax", "最大FOV"),
                UI.Panel {
                    width = 78,
                    height = 22,
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    children = {
                        MakeStepButton("-", function() ApplyDebugParam(M.lblDebugFovMax, "fovMax", -DEBUG_STEP_BIG, function(v) return string.format("最大FOV: %.1f", v) end) end),
                        MakeStepButton("+", function() ApplyDebugParam(M.lblDebugFovMax, "fovMax", DEBUG_STEP_BIG, function(v) return string.format("最大FOV: %.1f", v) end) end),
                    },
                },
            },
        },
        UI.Label {
            id = "dbgFovCurrent",
            text = "当前FOV",
            fontSize = 11,
            fontColor = {185,195,205,255},
            marginTop = 2,
        },
        UI.Panel {
            width = "100%",
            height = 24,
            flexDirection = "row",
            justifyContent = "space-between",
            children = {
                UI.Button {
                    text = "重置",
                    width = 76,
                    height = 24,
                    onClick = function()
                        cam.ResetDebugParams()
                        RefreshDebugPanel()
                    end,
                },
                UI.Button {
                    text = "隐藏",
                    width = 76,
                    height = 24,
                    onClick = function()
                        if M.debugPanel then
                            M.debugPanel:SetVisible(false)
                        end
                        M.debugPanelVisible = false
                        if M.btnDebugToggle then
                            M.btnDebugToggle:SetText("相机")
                        end
                    end,
                },
            },
        },
    }

    local panel = UI.Panel {
        id = "debugPanel",
        width = DEBUG_PANEL_W,
        height = DEBUG_PANEL_H,
        position = "absolute",
        right = DEBUG_RIGHT,
        top = DEBUG_TOP,
        backgroundColor = "rgba(18,22,28,0.82)",
        borderRadius = 8,
        padding = 10,
        children = rows,
    }

    return panel
end

local function BuildMainMenu()
    local function MakeLocalTextLabel(id, text, left, top, width, height, fontSize, fontColor, align)
        return UI.Panel {
            position = "absolute",
            left = left,
            top = top,
            width = width,
            height = height,
            justifyContent = "center",
            children = {
                UI.Label {
                    id = id,
                    text = text,
                    width = "100%",
                    height = fontSize + 4,
                    fontSize = fontSize,
                    fontWeight = "bold",
                    fontColor = fontColor,
                    textAlign = align or "center",
                },
            },
        }
    end

    local function MakeMenuImageButton(id, text, image, pressedImage, left, top, width, height, onClick)
        return UI.Panel {
            id = id,
            position = "absolute",
            left = X(left),
            top = Y(top),
            width = W(width),
            height = H(height),
            backgroundImage = image,
            backgroundFit = "fill",
            children = {
                UI.Button {
                    text = "",
                    position = "absolute",
                    left = 0,
                    top = 0,
                    width = "100%",
                    height = "100%",
                    backgroundImage = image,
                    pressedBackgroundImage = pressedImage,
                    backgroundFit = "fill",
                    backgroundColor = {0,0,0,0},
                    borderWidth = 0,
                    borderRadius = 0,
                    onClick = onClick,
                },
                MakeLocalTextLabel(nil, text or "", 0, "18%", "100%", "50%", 30, {255,255,255,255}, "center"),
            },
        }
    end

    local function MakeTextLabel(id, text, left, top, width, height, fontSize, fontColor, align)
        return UI.Panel {
            position = "absolute",
            left = X(left),
            top = Y(top),
            width = W(width),
            height = H(height),
            justifyContent = "center",
            children = {
                UI.Label {
                    id = id,
                    text = text,
                    width = "100%",
                    height = fontSize + 4,
                    fontSize = fontSize,
                    fontWeight = "bold",
                    fontColor = fontColor,
                    textAlign = align or "center",
                },
            },
        }
    end

    local function MakeDockEntry(x, iconImage, iconGlyphImage, label, onClick)
        return UI.Panel {
            position = "absolute",
            left = X(x),
            top = Y(725),
            width = W(80),
            height = H(78),
            backgroundImage = "Textures/home_dock_button.png",
            backgroundFit = "fill",
            children = {
                MakeLocalImagePanel(nil, iconImage, "31.250%", "15.385%", "37.500%", "38.462%"),
                MakeLocalImagePanel(nil, iconGlyphImage, "31.250%", "15.385%", "37.500%", "38.462%"),
                MakeLocalTextLabel(nil, label, 0, "58.974%", "100%", "26.923%", 13, {99,51,5,255}, "center"),
                UI.Button {
                    text = "",
                    position = "absolute",
                    left = 0,
                    top = 0,
                    width = "100%",
                    height = "100%",
                    backgroundColor = {0,0,0,0},
                    borderWidth = 0,
                    borderRadius = 0,
                    onClick = onClick,
                },
            },
        }
    end

    local function MakeRoundEntry(id, image, iconImage, left, top, onClick)
        return UI.Panel {
            id = id,
            position = "absolute",
            left = X(left),
            top = Y(top),
            width = W(64),
            height = H(66),
            backgroundImage = image,
            backgroundFit = "fill",
            children = {
                MakeLocalImagePanel(nil, iconImage, "26.563%", "25.758%", "46.875%", "45.455%"),
                UI.Button {
                    text = "",
                    position = "absolute",
                    left = 0,
                    top = 0,
                    width = "100%",
                    height = "100%",
                    backgroundColor = {0,0,0,0},
                    borderWidth = 0,
                    borderRadius = 0,
                    onClick = onClick,
                },
            },
        }
    end

    local cloudOne = MakeImagePanel("menuCloudOne", "Textures/home_cloud_one.png", 24, 62, 104, 48)
    local cloudTwo = MakeImagePanel("menuCloudTwo", "Textures/home_cloud_two.png", 236, 110, 122, 58)
    local laneStrips = {
        MakeImagePanel("menuLaneStrip", "Textures/home_lane_strip.png", 189, 236, 12, 530, nil, 1),
        MakeImagePanel("menuLaneStrip2", "Textures/home_lane_strip_1.png", 189, 236, 12, 530, nil, 0),
        MakeImagePanel("menuLaneStrip3", "Textures/home_lane_strip_2.png", 189, 236, 12, 530, nil, 0),
        MakeImagePanel("menuLaneStrip4", "Textures/home_lane_strip_3.png", 189, 236, 12, 530, nil, 0),
        MakeImagePanel("menuLaneStrip5", "Textures/home_lane_strip_4.png", 189, 236, 12, 530, nil, 0),
        MakeImagePanel("menuLaneStrip6", "Textures/home_lane_strip_5.png", 189, 236, 12, 530, nil, 0),
    }
    local speedLineA = MakeImagePanel("menuSpeedLineA", "Textures/home_speed_line_a.png", 28, 318, 96, 23)
    local speedLineB = MakeImagePanel("menuSpeedLineB", "Textures/home_speed_line_b.png", 296, 384, 96, 23)
    local speedLineC = MakeImagePanel("menuSpeedLineC", "Textures/home_speed_line_c.png", 64, 466, 66, 23)
    local riderShadow = MakeImagePanel("menuRiderShadow", "Textures/home_rider_shadow.png", 121, 510, 148, 44)
    local riderPanel = MakeImagePanel("menuRiderImage", "Textures/home_rider.png", 101, 314, 188, 188)
    local startButton = MakeMenuImageButton(
        "menuStartButton",
        "接单开冲",
        "Textures/home_start_button_base.png",
        "Textures/home_start_button_base_pressed.png",
        22,
        630,
        346,
        84,
        function()
            if M.onStartGame then
                M.onStartGame()
            end
        end
    )
    local xpFill = MakeImagePanel("menuXpFill", "Textures/home_xp_fill.png", 27, 56, 48, 8)
    local coinIcon = MakeImagePanel("menuCoinIcon", "Textures/home_coin_icon.png", 282, 14, 26, 26)

    M.menuCloudOne = cloudOne
    M.menuCloudTwo = cloudTwo
    M.menuLaneStrip = laneStrips[1]
    M.menuLaneStrips = laneStrips
    M.menuSpeedLineA = speedLineA
    M.menuSpeedLineB = speedLineB
    M.menuSpeedLineC = speedLineC
    M.menuCoinIcon = coinIcon
    M.menuRiderShadow = riderShadow
    M.menuRiderPanel = riderPanel
    M.menuStartButton = startButton
    M.menuXpFill = xpFill

    return UI.Panel {
        id = "mainMenuPanel",
        width = "100%",
        height = "100%",
        position = "absolute",
        children = {
            UI.Panel {
                position = "absolute",
                left = 0,
                top = 0,
                right = 0,
                bottom = 0,
                backgroundImage = "Textures/home_scene_bg_static.png",
                backgroundFit = "fill",
            },
            cloudOne,
            cloudTwo,
            laneStrips[1],
            laneStrips[2],
            laneStrips[3],
            laneStrips[4],
            laneStrips[5],
            laneStrips[6],
            speedLineA,
            speedLineB,
            speedLineC,
            riderShadow,
            MakeImagePanel(nil, "Textures/home_bottom_fade.png", 0, 622, 390, 222),
            MakeImagePanel(nil, "Textures/home_level_badge.png", 7, 8, 166, 72),
            MakeTextLabel("menuRiderLevel", "Lv.1 新手骑手", 26, 20, 132, 19, 15, {255,255,255,255}, "left"),
            MakeTextLabel("menuBest", "最高 0 单 / 连击 0", 26, 42, 132, 15, 11, {183,231,255,255}, "left"),
            MakeImagePanel(nil, "Textures/home_xp_track.png", 27, 56, 132, 8),
            xpFill,
            MakeImagePanel(nil, "Textures/home_coin_badge_base.png", 258, 0, 114, 58),
            coinIcon,
            MakeTextLabel("menuCoins", "0", 322, 4, 36, 36, 22, {255,255,255,255}, "left"),
            MakeImagePanel(nil, "Textures/home_title.png", 70, 96, 250, 138),
            MakeImagePanel(nil, "Textures/home_subtitle_badge.png", 111, 220, 168, 34),
            MakeTextLabel(nil, "接单上路，准时送达", 123, 226, 144, 17, 13, {92,43,0,255}, "center"),
            MakeImagePanel(nil, "Textures/home_order_sign.png", 0, 250, 159, 146),
            MakeRoundEntry("menuTaskButton", "Textures/home_round_blue.png", "Textures/home_icon_task.png", 303, 272, function() M.ShowStaticPage("tasks", "menu") end),
            MakeRoundEntry("menuAchievementButton", "Textures/home_round_green.png", "Textures/home_icon_achievement.png", 303, 350, function() M.ShowStaticPage("achievements", "menu") end),
            MakeRoundEntry("menuSettingsButton", "Textures/home_round_red.png", "Textures/home_icon_settings.png", 303, 428, function() M.ShowStaticPage("settings", "menu") end),
            riderPanel,
            startButton,
            MakeDockEntry(17, "Textures/home_dock_icon_orange.png", "Textures/home_icon_rider.png", "骑手", function() M.ShowStaticPage("rider", "menu") end),
            MakeDockEntry(105, "Textures/home_dock_icon_blue.png", "Textures/home_icon_upgrade.png", "升级", function() M.ShowStaticPage("upgrades", "menu") end),
            MakeDockEntry(193, "Textures/home_dock_icon_green.png", "Textures/home_icon_order.png", "订单", function() M.ShowStaticPage("orders", "menu") end),
            MakeDockEntry(281, "Textures/home_dock_icon_gray.png", "Textures/home_icon_bag.png", "背包", function() M.ShowStaticPage("backpack", "menu") end),
        },
    }
end

local function StopNodeAnimation(node)
    if node and node.StopAnimation then
        node:StopAnimation()
    end
end

local function PlayNodeAnimation(node, spec)
    if not node or not node.Animate then
        return
    end
    StopNodeAnimation(node)
    node:Animate(spec)
end

local function StopHomeAnimations()
    StopNodeAnimation(M.menuCloudOne)
    StopNodeAnimation(M.menuCloudTwo)
    for _, node in ipairs(M.menuLaneStrips or {}) do
        StopNodeAnimation(node)
    end
    StopNodeAnimation(M.menuSpeedLineA)
    StopNodeAnimation(M.menuSpeedLineB)
    StopNodeAnimation(M.menuSpeedLineC)
    StopNodeAnimation(M.menuCoinIcon)
    StopNodeAnimation(M.menuRiderShadow)
    StopNodeAnimation(M.menuRiderPanel)
    StopNodeAnimation(M.menuStartButton)
end

local function PlayLaneStripAnimations()
    local laneStrips = M.menuLaneStrips or {}
    local count = #laneStrips
    if count <= 0 then
        return
    end

    for i, node in ipairs(laneStrips) do
        local segment = 1 / count
        local startAt = (i - 1) * segment
        local endAt = i * segment
        local keyframes = {
            [0] = { opacity = 0 },
            [1] = { opacity = 0 },
        }

        if i == 1 then
            keyframes[0] = { opacity = 1 }
            keyframes[segment] = { opacity = 0 }
            keyframes[1 - segment] = { opacity = 0 }
            keyframes[1] = { opacity = 1 }
        else
            keyframes[math.max(0, startAt - segment)] = { opacity = 0 }
            keyframes[startAt] = { opacity = 1 }
            keyframes[math.min(1, endAt)] = { opacity = 0 }
        end

        PlayNodeAnimation(node, {
            keyframes = keyframes,
            duration = 0.9,
            easing = "linear",
            loop = true,
        })
    end
end

local function StartHomeAnimations()
    PlayNodeAnimation(M.menuCloudOne, {
        keyframes = {
            [0] = { translateX = 0 },
            [0.5] = { translateX = 20 },
            [1] = { translateX = 0 },
        },
        duration = 9.0,
        easing = "easeInOut",
        loop = true,
    })
    PlayNodeAnimation(M.menuCloudTwo, {
        keyframes = {
            [0] = { translateX = 12 },
            [0.5] = { translateX = -8 },
            [1] = { translateX = 12 },
        },
        duration = 9.0,
        easing = "easeInOut",
        loop = true,
    })
    PlayLaneStripAnimations()
    PlayNodeAnimation(M.menuSpeedLineA, {
        keyframes = {
            [0] = { opacity = 0.18, translateY = 0 },
            [0.5] = { opacity = 0.8, translateY = 12 },
            [1] = { opacity = 0.18, translateY = 0 },
        },
        duration = 1.2,
        easing = "easeInOut",
        loop = true,
    })
    PlayNodeAnimation(M.menuSpeedLineB, {
        keyframes = {
            [0] = { opacity = 0.44, translateY = 8 },
            [0.5] = { opacity = 0.18, translateY = 0 },
            [1] = { opacity = 0.44, translateY = 8 },
        },
        duration = 1.2,
        easing = "easeInOut",
        loop = true,
    })
    PlayNodeAnimation(M.menuSpeedLineC, {
        keyframes = {
            [0] = { opacity = 0.7, translateY = 10 },
            [0.5] = { opacity = 0.18, translateY = 0 },
            [1] = { opacity = 0.7, translateY = 10 },
        },
        duration = 1.2,
        easing = "easeInOut",
        loop = true,
    })
    PlayNodeAnimation(M.menuCoinIcon, {
        keyframes = {
            [0] = { scale = 1.0, rotate = 0 },
            [0.5] = { scale = 1.12, rotate = 9 },
            [1] = { scale = 1.0, rotate = 0 },
        },
        duration = 1.7,
        easing = "easeInOut",
        loop = true,
    })
    PlayNodeAnimation(M.menuRiderPanel, {
        keyframes = {
            [0] = { translateY = 0, rotate = -1 },
            [0.5] = { translateY = -8, rotate = 1.5 },
            [1] = { translateY = 0, rotate = -1 },
        },
        duration = 1.25,
        easing = "easeInOut",
        loop = true,
    })
    PlayNodeAnimation(M.menuRiderShadow, {
        keyframes = {
            [0] = { opacity = 0.28, scale = 1.0 },
            [0.5] = { opacity = 0.18, scale = 0.88 },
            [1] = { opacity = 0.28, scale = 1.0 },
        },
        duration = 1.25,
        easing = "easeInOut",
        loop = true,
    })
    PlayNodeAnimation(M.menuStartButton, {
        keyframes = {
            [0] = { translateY = 0, scale = 1.0 },
            [0.5] = { translateY = -2, scale = 1.02 },
            [1] = { translateY = 0, scale = 1.0 },
        },
        duration = 1.45,
        easing = "easeInOut",
        loop = true,
    })
end

local function BuildPauseOverlay()
    return UI.Panel {
        id = "pauseOverlayPanel",
        width = "100%",
        height = "100%",
        position = "absolute",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = "rgba(0,0,0,0.58)",
        children = {
            UI.Panel {
                width = 286,
                height = 286,
                backgroundColor = "#FFFFFF",
                borderRadius = 14,
                padding = 18,
                alignItems = "center",
                children = {
                    MakePanelTitle("已暂停"),
                    UI.Label {
                        text = "配送节奏已冻结",
                        fontSize = 13,
                        fontColor = {92,104,114,255},
                        marginTop = 6,
                    },
                    UI.Button {
                        text = "继续",
                        variant = "primary",
                        width = 210,
                        height = 40,
                        marginTop = 22,
                        onClick = function()
                            if M.onTogglePause then
                                M.onTogglePause()
                            end
                        end,
                    },
                    UI.Button {
                        text = "重新开始",
                        width = 210,
                        height = 36,
                        marginTop = 10,
                        onClick = function()
                            if M.onRestart then
                                M.onRestart()
                            end
                        end,
                    },
                    UI.Button {
                        text = "设置",
                        width = 210,
                        height = 36,
                        marginTop = 10,
                        onClick = function()
                            M.ShowStaticPage("settings", "pause")
                        end,
                    },
                    UI.Button {
                        text = "返回主菜单",
                        width = 210,
                        height = 36,
                        marginTop = 10,
                        onClick = function()
                            if M.onReturnMenu then
                                M.onReturnMenu()
                            end
                        end,
                    },
                },
            },
        },
    }
end

local function BuildGameOverPanel(onRestart)
    return UI.Panel {
        id = "gameOverPanel",
        width = "100%",
        height = "100%",
        position = "absolute",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = "rgba(0,0,0,0.7)",
        children = {
            UI.Panel {
                width = 318,
                height = 410,
                backgroundColor = "#FFFFFF",
                borderRadius = 14,
                padding = 18,
                alignItems = "center",
                children = {
                    MakePanelTitle("配送完成"),
                    UI.Label { id = "finalIncome", text = "本局收入: ¥0", fontSize = 22, fontWeight = "bold", fontColor = {255,138,31,255}, marginTop = 12 },
                    UI.Label { id = "finalStats", text = "送达 0 单  准时 0 单", fontSize = 14, fontWeight = "bold", fontColor = {45,58,70,255}, marginTop = 8 },
                    UI.Label { id = "finalDist", text = "距离: 0m  连击: 0", fontSize = 14, fontColor = {70,82,92,255}, marginTop = 6 },
                    UI.Panel {
                        width = 250,
                        height = 74,
                        marginTop = 12,
                        padding = 10,
                        backgroundColor = "#FFF7E8",
                        borderRadius = 10,
                        children = {
                            UI.Label { id = "finalGain", text = "金币 +0  XP +0", fontSize = 17, fontWeight = "bold", fontColor = {210,105,18,255} },
                            UI.Label { id = "finalLevel", text = "Lv.1  XP 0/60", fontSize = 13, fontColor = {80,72,60,255}, marginTop = 8 },
                        },
                    },
                    UI.Label { id = "finalUnlocks", text = "继续配送提升等级", width = 250, height = 34, fontSize = 12, fontColor = {92,104,114,255}, marginTop = 8, textAlign = "center" },
                    UI.Button {
                        text = "再来一单",
                        variant = "primary",
                        width = 220,
                        height = 40,
                        marginTop = 14,
                        onClick = function()
                            onRestart()
                        end,
                    },
                    UI.Panel {
                        width = 220,
                        height = 40,
                        flexDirection = "row",
                        justifyContent = "space-between",
                        marginTop = 10,
                        children = {
                            UI.Button {
                                text = "骑手成长",
                                width = 104,
                                height = 36,
                                onClick = function() M.ShowStaticPage("rider", "result") end,
                            },
                            UI.Button {
                                text = "主菜单",
                                width = 104,
                                height = 36,
                                onClick = function()
                                    if M.onReturnMenu then
                                        M.onReturnMenu()
                                    end
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

local function BuildStaticPage()
    return systemPages.Build({
        onBack = function()
            if M.staticBackMode == "pause" then
                M.ShowPauseOverlay(true)
            elseif M.staticBackMode == "result" then
                systemPages.StopAnimations(M.systemPageRefs)
                if M.staticPagePanel then M.staticPagePanel:SetVisible(false) end
                if M.gameOverPanel then M.gameOverPanel:SetVisible(true) end
            else
                M.ShowMainMenu()
            end
        end,
        onUpgrade = HandleUpgradeIndexClick,
        onUpgradeAll = HandleUpgradeAllClick,
        onSetting = HandleSettingKeyClick,
        onSaveSettings = HandleSettingsSaveClick,
        onClaimOne = HandleProgressClaimOne,
        onClaimAllTasks = HandleTaskClaimClick,
        onClaimAllAchievements = HandleAchievementClaimClick,
    })
end

function M.Create(onRestart, onTogglePause, onStartGame, onReturnMenu, onUsePowerup)
    local wasDebugVisible = M.debugPanelVisible
    M.onRestart = onRestart
    M.onTogglePause = onTogglePause
    M.onStartGame = onStartGame
    M.onReturnMenu = onReturnMenu
    M.onUsePowerup = onUsePowerup

    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })

    local hud = UI.Panel {
        id = "hudPanel",
        width = "100%", height = "100%",
        children = {
            UI.Panel {
                position = "absolute",
                left = 14,
                top = 14,
                width = 128,
                height = 58,
                backgroundColor = "rgba(16,38,52,0.74)",
                borderRadius = 16,
                children = {
                    UI.Label {
                        id = "income",
                        text = "¥0",
                        position = "absolute",
                        left = 12,
                        top = 5,
                        width = 104,
                        height = 26,
                        fontSize = 22,
                        fontWeight = "bold",
                        fontColor = {255,215,0,255},
                    },
                    UI.Label {
                        id = "riderLevel",
                        text = "Lv.1 新手骑手",
                        position = "absolute",
                        left = 12,
                        top = 31,
                        width = 104,
                        height = 14,
                        fontSize = 11,
                        fontWeight = "bold",
                        fontColor = {220,245,255,255},
                    },
                    UI.Label {
                        id = "riderXP",
                        text = "XP 0/60",
                        position = "absolute",
                        left = 12,
                        top = 44,
                        width = 104,
                        height = 12,
                        fontSize = 10,
                        fontColor = {145,223,255,255},
                    },
                },
            },
            UI.Panel {
                position = "absolute",
                left = 146,
                top = 18,
                width = 112,
                height = 44,
                backgroundColor = "rgba(255,248,224,0.90)",
                borderRadius = 18,
                children = {
                    UI.Label {
                        id = "timerNormal",
                        text = "等待订单",
                        position = "absolute",
                        left = 0,
                        top = 8,
                        width = 112,
                        height = 26,
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = {255,138,31,255},
                        textAlign = "center",
                    },
                    UI.Label {
                        id = "timerWarning",
                        text = "",
                        position = "absolute",
                        left = 0,
                        top = 8,
                        width = 112,
                        height = 26,
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = {226,120,0,255},
                        textAlign = "center",
                    },
                    UI.Label {
                        id = "timerLate",
                        text = "",
                        position = "absolute",
                        left = 0,
                        top = 8,
                        width = 112,
                        height = 26,
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = {255,73,73,255},
                        textAlign = "center",
                    },
                },
            },
            UI.Panel {
                position = "absolute",
                left = 268,
                top = 18,
                width = 58,
                height = 34,
                backgroundColor = "rgba(16,38,52,0.68)",
                borderRadius = 14,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label { id = "speed", text = "", width = 58, height = 22, fontSize = 14, fontWeight = "bold", fontColor = {220,245,255,255}, textAlign = "center" },
                },
            },
            UI.Label {
                id = "combo",
                text = "",
                position = "absolute",
                left = 242,
                top = 56,
                width = 82,
                height = 22,
                fontSize = 16,
                fontWeight = "bold",
                fontColor = {0,229,184,255},
                textAlign = "center",
            },
            UI.Label {
                id = "hint",
                text = "",
                position = "absolute",
                left = 52,
                top = 82,
                width = 184,
                height = 34,
                fontSize = 15,
                fontWeight = "bold",
                fontColor = {255,232,118,255},
                textAlign = "center",
            },
        },
    }
    M.gameOverPanel = BuildGameOverPanel(onRestart)
    M.gameOverPanel:SetVisible(false)
    M.minimapPanel = BuildMinimap()
    M.minimapOrderListPanel = BuildMiniOrderList()
    M.minimapOrderListPanel:SetVisible(false)
    M.powerupPanel = BuildPowerupPanel()
    M.debugPanel = BuildDebugPanel()
    M.debugPanel:SetVisible(false)
    M.debugPanelVisible = wasDebugVisible
    M.debugPanel:SetVisible(M.debugPanelVisible)

    local debugToggle = UI.Button {
        id = "debugToggle",
        text = "相机",
        width = 52,
        height = 22,
        position = "absolute",
        left = 14,
        top = 88,
        onClick = function()
            M.ToggleDebugPanel()
        end,
    }
    debugToggle:SetVisible(false)
    local pauseButton = UI.Button {
        id = "pauseButton",
        text = "暂停",
        width = 50,
        height = 30,
        position = "absolute",
        left = 330,
        top = 18,
        backgroundColor = "#28B8F0",
        borderRadius = 15,
        borderWidth = 0,
        fontSize = 13,
        fontWeight = "bold",
        fontColor = {255,255,255,255},
        onClick = function()
            if onTogglePause then
                onTogglePause()
            end
        end,
    }
    M.mainMenuPanel = BuildMainMenu()
    M.pauseOverlayPanel = BuildPauseOverlay()
    M.pauseOverlayPanel:SetVisible(false)
    M.staticPagePanel = BuildStaticPage()
    M.staticPagePanel:SetVisible(false)

    -- 将 HUD 和 gameOverPanel 合并到同一个根面板
    local root = UI.Panel {
        width = "100%", height = "100%",
        children = {
            hud,
            debugToggle,
            pauseButton,
            M.minimapPanel,
            M.minimapOrderListPanel,
            M.powerupPanel,
            M.debugPanel,
            M.mainMenuPanel,
            M.pauseOverlayPanel,
            M.gameOverPanel,
            M.staticPagePanel,
        },
    }
    M.rootPanel = root
    UI.SetRoot(root)

    M.hudPanel = root:FindById("hudPanel")
    M.lblTimerNormal = root:FindById("timerNormal")
    M.lblTimerWarning = root:FindById("timerWarning")
    M.lblTimerLate = root:FindById("timerLate")
    M.lblTimer = M.lblTimerNormal
    M.lblIncome = root:FindById("income")
    M.lblCombo = root:FindById("combo")
    M.lblSpeed = root:FindById("speed")
    M.lblHint = root:FindById("hint")
    M.lblRiderLevel = root:FindById("riderLevel")
    M.lblRiderXP = root:FindById("riderXP")
    M.lblMenuRiderLevel = root:FindById("menuRiderLevel")
    M.lblMenuCoins = root:FindById("menuCoins")
    M.lblMenuBest = root:FindById("menuBest")
    M.menuCloudOne = root:FindById("menuCloudOne") or M.menuCloudOne
    M.menuCloudTwo = root:FindById("menuCloudTwo") or M.menuCloudTwo
    M.menuLaneStrip = root:FindById("menuLaneStrip") or M.menuLaneStrip
    M.menuLaneStrips = {
        root:FindById("menuLaneStrip") or (M.menuLaneStrips and M.menuLaneStrips[1]) or M.menuLaneStrip,
        root:FindById("menuLaneStrip2") or (M.menuLaneStrips and M.menuLaneStrips[2]),
        root:FindById("menuLaneStrip3") or (M.menuLaneStrips and M.menuLaneStrips[3]),
        root:FindById("menuLaneStrip4") or (M.menuLaneStrips and M.menuLaneStrips[4]),
        root:FindById("menuLaneStrip5") or (M.menuLaneStrips and M.menuLaneStrips[5]),
        root:FindById("menuLaneStrip6") or (M.menuLaneStrips and M.menuLaneStrips[6]),
    }
    M.menuSpeedLineA = root:FindById("menuSpeedLineA") or M.menuSpeedLineA
    M.menuSpeedLineB = root:FindById("menuSpeedLineB") or M.menuSpeedLineB
    M.menuSpeedLineC = root:FindById("menuSpeedLineC") or M.menuSpeedLineC
    M.menuCoinIcon = root:FindById("menuCoinIcon") or M.menuCoinIcon
    M.menuRiderShadow = root:FindById("menuRiderShadow") or M.menuRiderShadow
    M.menuRiderPanel = root:FindById("menuRiderImage") or M.menuRiderPanel
    M.menuStartButton = root:FindById("menuStartButton") or M.menuStartButton
    M.menuXpFill = root:FindById("menuXpFill") or M.menuXpFill
    M.powerupPanel = root:FindById("powerupPanel")
    M.btnPowerup = root:FindById("powerupButton")
    M.lblPowerupStatus = root:FindById("powerupStatus")
    M.lblFinalIncome = root:FindById("finalIncome")
    M.lblFinalDist = root:FindById("finalDist")
    M.lblFinalStats = root:FindById("finalStats")
    M.lblFinalGain = root:FindById("finalGain")
    M.lblFinalLevel = root:FindById("finalLevel")
    M.lblFinalUnlocks = root:FindById("finalUnlocks")
    M.lblMiniStatus = root:FindById("miniStatus")
    M.btnDebugToggle = root:FindById("debugToggle")
    M.lblDebugOffsetY = root:FindById("dbgOffsetY")
    M.lblDebugOffsetZ = root:FindById("dbgOffsetZ")
    M.lblDebugLookAhead = root:FindById("dbgLookAhead")
    M.lblDebugYawOffset = root:FindById("dbgYawOffset")
    M.lblDebugPitchOffset = root:FindById("dbgPitchOffset")
    M.lblDebugFovBase = root:FindById("dbgFovBase")
    M.lblDebugFovMax = root:FindById("dbgFovMax")
    M.lblDebugFovCurrent = root:FindById("dbgFovCurrent")
    M.btnPause = root:FindById("pauseButton")
    M.systemPageRefs = systemPages.Bind(root)

    M.minimapOrderRows = {}
    M.minimapOrderDots = {}
    M.minimapOrderTexts = {}
    for i = 1, (CONFIG.ORDER_AVAILABLE_COUNT_MAX or 5) do
        M.minimapOrderRows[i] = root:FindById("miniOrderRow" .. tostring(i))
        M.minimapOrderDots[i] = root:FindById("miniOrderDot" .. tostring(i))
        M.minimapOrderTexts[i] = root:FindById("miniOrderText" .. tostring(i))
        if M.minimapOrderRows[i] then
            M.minimapOrderRows[i]:SetVisible(false)
        end
    end

    M.minimapRouteSegments = {}
    M.minimapPlayerMarkers = {}
    M.minimapTargetMarkers = {}
    M.minimapPickupMarkers = {}
    ClearPreciseMinimapNodes()
    BindMinimapRefs(root)

    M.minimapVersion = rn.visibleVersion
    if M.lblMiniStatus then
        M.lblMiniStatus:SetText("等待订单")
    end
    M.SetOrderTimerDisplay(nil)
    RefreshDebugPanel()
    M.ShowMainMenu()
end

function M.RebuildMinimap()
    if not M.rootPanel then return end

    if M.minimapPanel then
        ClearPreciseMinimapNodes()
        M.rootPanel:RemoveChild(M.minimapPanel)
        M.minimapPanel:Remove()
    end

    M.minimapPanel = BuildMinimap()
    M.rootPanel:AddChild(M.minimapPanel)
    BindMinimapRefs(M.rootPanel)
    M.lblMiniStatus = M.rootPanel:FindById("miniStatus")
    M.minimapVersion = rn.visibleVersion
end

local function SetGameplayUIVisible(visible)
    local settings = meta.GetSettings and meta.GetSettings() or {}
    local debugAllowed = settings.debugPanel == true
    if M.hudPanel then M.hudPanel:SetVisible(visible) end
    if M.minimapPanel then M.minimapPanel:SetVisible(visible) end
    if M.minimapOrderListPanel and not visible then M.minimapOrderListPanel:SetVisible(false) end
    if M.powerupPanel then M.powerupPanel:SetVisible(visible) end
    if M.btnDebugToggle then M.btnDebugToggle:SetVisible(visible and debugAllowed) end
    if M.btnPause then M.btnPause:SetVisible(visible) end
    if M.debugPanel then
        M.debugPanel:SetVisible(visible and debugAllowed and M.debugPanelVisible)
    end
end

local function HideTopLevelPanels()
    if M.mainMenuPanel then
        M.mainMenuPanel:SetVisible(false)
        StopHomeAnimations()
    end
    if M.pauseOverlayPanel then M.pauseOverlayPanel:SetVisible(false) end
    if M.staticPagePanel then
        systemPages.StopAnimations(M.systemPageRefs)
        M.staticPagePanel:SetVisible(false)
    end
    if M.gameOverPanel then M.gameOverPanel:SetVisible(false) end
end

function M.ShowMainMenu()
    SetGameplayUIVisible(false)
    HideTopLevelPanels()
    local summary = meta.GetSummary()
    local progressData = progression.GetHUDData and progression.GetHUDData() or nil
    local xpProgress = (progressData and progressData.progress) or 1.0
    xpProgress = math.max(0.0, math.min(1.0, xpProgress))
    if M.lblMenuRiderLevel then
        M.lblMenuRiderLevel:SetText("Lv." .. tostring(summary.riderLevel or 1) .. " " .. (summary.riderTitle or "骑手"))
    end
    if M.lblMenuCoins then
        M.lblMenuCoins:SetText(tostring(summary.coins or 0))
    end
    if M.lblMenuBest then
        M.lblMenuBest:SetText("最高 " .. tostring(summary.bestDeliveries or 0) .. " 单 / 连击 " .. tostring(summary.bestCombo or 0))
    end
    SetNodeStyle(M.menuXpFill, {
        width = W(math.max(2, 132 * xpProgress)),
    })
    if M.mainMenuPanel then
        M.mainMenuPanel:SetVisible(true)
        StartHomeAnimations()
    end
end

function M.ShowGameplay()
    StopHomeAnimations()
    HideTopLevelPanels()
    SetGameplayUIVisible(true)
end

function M.ShowPauseOverlay(show)
    if show then
        SetGameplayUIVisible(true)
        if M.staticPagePanel then M.staticPagePanel:SetVisible(false) end
        if M.pauseOverlayPanel then M.pauseOverlayPanel:SetVisible(true) end
    else
        if M.pauseOverlayPanel then M.pauseOverlayPanel:SetVisible(false) end
        SetGameplayUIVisible(true)
    end
end

function M.ShowStaticPage(key, backMode)
    local allowed = {
        rider = true,
        upgrades = true,
        orders = true,
        backpack = true,
        tasks = true,
        achievements = true,
        settings = true,
    }
    if not allowed[key] then return end
    M.staticBackMode = backMode or "menu"
    M.staticPageKey = key
    if M.mainMenuPanel then
        M.mainMenuPanel:SetVisible(false)
        StopHomeAnimations()
    end
    if M.pauseOverlayPanel then M.pauseOverlayPanel:SetVisible(false) end
    if M.gameOverPanel then M.gameOverPanel:SetVisible(false) end
    SetGameplayUIVisible(false)

    if M.staticPagePanel then
        M.staticPagePanel:SetVisible(true)
    end
    systemPages.Refresh(M.systemPageRefs, key)
    systemPages.StartAnimations(M.systemPageRefs)
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

function M.UpdateHUD(orderTimerData, totalIncome, comboCount, currentSpeed, intersectionActive, turnChoice, hasTurnChoice, availableTurns, navData, progressionData)
    M.SetOrderTimerDisplay(orderTimerData)

    if progressionData then
        if M.lblRiderLevel then
            M.lblRiderLevel:SetText("Lv." .. tostring(progressionData.level or 1) .. " " .. (progressionData.title or "骑手"))
        end
        if M.lblRiderXP then
            if progressionData.maxLevel then
                M.lblRiderXP:SetText("XP MAX")
            else
                M.lblRiderXP:SetText("XP " .. tostring(progressionData.xp or 0) .. "/" .. tostring(progressionData.xpToNext or 0))
            end
        end
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

function M.UpdatePowerupHUD(powerupData)
    local data = powerupData or {}
    local buttonText = data.readyText or "无道具"
    local statusText = ""

    if data.message and data.message ~= "" then
        statusText = data.message
    elseif data.shieldActive then
        statusText = "护盾已启动"
    elseif data.held and data.name then
        statusText = "当前: " .. data.name
    end

    if M.btnPowerup then
        M.btnPowerup:SetText(buttonText)
    end
    if M.lblPowerupStatus then
        M.lblPowerupStatus:SetText(statusText)
    end
end

local function FormatUnlocks(unlocks)
    local parts = {}
    for _, item in ipairs(unlocks or {}) do
        if item.type == "order_count" then
            parts[#parts + 1] = "同时订单 " .. tostring(item.value)
        elseif item.type == "order_type" then
            parts[#parts + 1] = "解锁" .. FormatUnlockedOrderTypes({item.value})
        end
    end
    if #parts == 0 then
        return "继续配送提升等级"
    end
    return table.concat(parts, " / ")
end

function M.ShowGameOver(result)
    result = result or {}
    SetGameplayUIVisible(false)
    if M.mainMenuPanel then
        M.mainMenuPanel:SetVisible(false)
        StopHomeAnimations()
    end
    if M.pauseOverlayPanel then M.pauseOverlayPanel:SetVisible(false) end
    if M.staticPagePanel then M.staticPagePanel:SetVisible(false) end
    if M.gameOverPanel then
        M.gameOverPanel:SetVisible(true)
        if M.lblFinalIncome then
            M.lblFinalIncome:SetText("本局收入: ¥" .. tostring(result.income or result.coinsEarned or 0))
        end
        if M.lblFinalStats then
            M.lblFinalStats:SetText("送达 " .. tostring(result.deliveries or 0) .. " 单  准时 " .. tostring(result.onTimeDeliveries or 0) .. " 单")
        end
        if M.lblFinalDist then
            M.lblFinalDist:SetText("距离: " .. tostring(math.floor(result.distance or 0)) .. "m  连击: " .. tostring(result.bestCombo or 0))
        end
        if M.lblFinalGain then
            M.lblFinalGain:SetText("金币 +" .. tostring(result.coinsEarned or 0) .. "  XP +" .. tostring(result.xpEarned or 0))
        end
        if M.lblFinalLevel then
            local levelText = "Lv." .. tostring(result.levelAfter or 1)
            if result.leveledUp then
                levelText = "升级! Lv." .. tostring(result.levelBefore or 1) .. " → Lv." .. tostring(result.levelAfter or 1)
            elseif (result.xpToNext or 0) > 0 then
                levelText = levelText .. "  XP " .. tostring(result.xpAfter or 0) .. "/" .. tostring(result.xpToNext or 0)
            end
            M.lblFinalLevel:SetText(levelText)
        end
        if M.lblFinalUnlocks then
            M.lblFinalUnlocks:SetText(FormatUnlocks(result.unlocks))
        end
    end
end

function M.HideGameOver()
    if M.gameOverPanel then
        M.gameOverPanel:SetVisible(false)
    end
end

local function SetOnlyVisible(markers, currentKey, previousKey)
    if previousKey == currentKey then return currentKey end
    if previousKey and markers and markers[previousKey] then
        markers[previousKey]:SetVisible(false)
    end
    if currentKey and markers and markers[currentKey] then
        markers[currentKey]:SetVisible(true)
    end
    return currentKey
end

local function SetRouteSegmentsVisible(activeKeys)
    activeKeys = activeKeys or {}
    for key in pairs(M.activeRouteSegments) do
        if not activeKeys[key] and M.minimapRouteSegments[key] then
            M.minimapRouteSegments[key]:SetVisible(false)
        end
    end
    for key in pairs(activeKeys) do
        local segment = M.minimapRouteSegments[key]
        if segment and not M.activeRouteSegments[key] then
            segment:SetVisible(true)
        end
    end
    M.activeRouteSegments = activeKeys
end

local function HidePickupSlot(key)
    if not key then return end
    if M.minimapPickupMarkers[key] then
        M.minimapPickupMarkers[key]:SetVisible(false)
    end
end

local function SetMiniOrderListVisible(pickupMiniData)
    local orders = pickupMiniData and pickupMiniData.orders or {}
    local maxRows = CONFIG.ORDER_AVAILABLE_COUNT_MAX or 5
    local visibleCount = math.min(#orders, maxRows)
    local hasOrders = visibleCount > 0

    if M.minimapOrderListPanel then
        M.minimapOrderListPanel:SetVisible(hasOrders)
        if hasOrders and M.minimapOrderListPanel.SetStyle then
            M.minimapOrderListPanel:SetStyle({
                height = 16
                    + visibleCount * MINI_ORDER_ROW_H
                    + visibleCount * MINI_ORDER_ROW_GAP
                    + MINI_ORDER_LIST_PADDING_Y * 2,
            })
        end
    end

    for i = 1, maxRows do
        local order = orders[i]
        local row = M.minimapOrderRows[i]
        if row then
            row:SetVisible(order ~= nil)
        end
        if order then
            if M.minimapOrderDots[i] and M.minimapOrderDots[i].SetStyle then
                M.minimapOrderDots[i]:SetStyle({
                    backgroundColor = GetOrderListDotColor(order),
                })
            end
            if M.minimapOrderTexts[i] then
                M.minimapOrderTexts[i]:SetText(order.displayText or order.label or "")
            end
        elseif M.minimapOrderTexts[i] then
            M.minimapOrderTexts[i]:SetText("")
        end
    end
end

local function SetPickupOrdersVisible(pickupMiniData)
    local activeSlots = {}

    if pickupMiniData and pickupMiniData.orders then
        for _, order in ipairs(pickupMiniData.orders) do
            local key = order.slot
            if key then
                activeSlots[key] = true
                if M.minimapPickupMarkers[key] then
                    M.minimapPickupMarkers[key]:SetVisible(true)
                end
            end
        end
    elseif pickupMiniData and pickupMiniData.active and pickupMiniData.slot then
        local key = pickupMiniData.slot
        activeSlots[key] = true
        if M.minimapPickupMarkers[key] then
            M.minimapPickupMarkers[key]:SetVisible(true)
        end
    end

    for key in pairs(M.activePickupSlots or {}) do
        if not activeSlots[key] then
            HidePickupSlot(key)
        end
    end

    M.activePickupSlots = activeSlots
    M.activePickupSlot = nil
end

function M.UpdateMinimap(navData, pickupMiniData)
    if M.minimapVersion ~= rn.visibleVersion and M.onRestart then
        M.RebuildMinimap()
    end

    if M.lblMiniStatus then
        if navData and (navData.active or navData.transientMessage) and navData.message then
            M.lblMiniStatus:SetText(navData.message)
        elseif pickupMiniData and pickupMiniData.statusText then
            M.lblMiniStatus:SetText(pickupMiniData.statusText)
        elseif navData and navData.message then
            M.lblMiniStatus:SetText(navData.message)
        else
            M.lblMiniStatus:SetText("等待订单")
        end
    end

    local hasPreciseRoute = UpdatePreciseNavigation(navData)
    local hasPreciseData = navData and navData.routeLines ~= nil
    local hasPreciseTarget = navData and navData.active and navData.targetPoint ~= nil
    local routeSegments = (not hasPreciseData and navData and navData.active) and navData.routeSegments or {}
    if routeSegments ~= M.lastRouteSegments then
        SetRouteSegmentsVisible(routeSegments)
        M.lastRouteSegments = routeSegments
    end

    if pickupMiniData and pickupMiniData.orders then
        SetPickupOrdersVisible(nil)
        SetPrecisePickupOrders(pickupMiniData)
    else
        SetPickupOrdersVisible(pickupMiniData)
        SetPrecisePickupOrders(nil)
    end
    SetMiniOrderListVisible(pickupMiniData)
    UpdatePreciseNavigationMarkers(navData)
    M.activePlayerSlot = SetOnlyVisible(M.minimapPlayerMarkers, (not navData or not navData.playerPoint) and navData and navData.playerSlot or nil, M.activePlayerSlot)
    M.activeTargetSlot = SetOnlyVisible(M.minimapTargetMarkers, (not hasPreciseTarget and navData and navData.active) and navData.targetSlot or nil, M.activeTargetSlot)
end

function M.ToggleDebugPanel()
    if not M.debugPanel then
        return
    end
    M.debugPanelVisible = not M.debugPanelVisible
    M.debugPanel:SetVisible(M.debugPanelVisible)
    if M.btnDebugToggle then
        M.btnDebugToggle:SetText(M.debugPanelVisible and "收起" or "相机")
    end
    if M.debugPanelVisible then
        RefreshDebugPanel()
    end
end

function M.UpdateCameraDebugReadout()
    if M.debugPanelVisible and M.lblDebugFovCurrent then
        M.lblDebugFovCurrent:SetText(string.format("当前FOV: %.1f", cam.GetCurrentFov()))
    end
end

function M.SetPaused(paused)
    if M.btnPause then
        M.btnPause:SetText(paused and "继续" or "暂停")
    end
    if M.lblHint then
        M.lblHint:SetText(paused and "已暂停" or "")
    end
    M.ShowPauseOverlay(paused)
end

return M
