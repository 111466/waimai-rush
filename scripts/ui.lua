-- ============================================================================
-- 外卖冲冲冲 - UI 模块
-- ============================================================================

local UI = require("urhox-libs/UI")
local cfg = require("config")
local CONFIG = cfg.CONFIG
local rn = require("road_network")
local nav = require("route_navigation")
local cam = require("camera")

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
M.minimapPickupLabels = {}
M.preciseRouteNodes = {}
M.precisePickupNodes = {}
M.onRestart = nil
M.onTogglePause = nil
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
local MINI_PANEL_H = 154
local MINI_MAP_SIZE = 112
local MINI_LEFT = 10
local MINI_TOP = 8
local MINI_MARGIN = 10

local DEBUG_PANEL_W = 214
local DEBUG_PANEL_H = 274
local DEBUG_RIGHT = 12
local DEBUG_TOP = 254
local DEBUG_STEP_SMALL = 0.25
local DEBUG_STEP_BIG = 1.0
local DEBUG_STEP_ANGLE = 2.5
local DEBUG_STEP_PITCH = 0.25

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

local function MakeMiniOrderLabel(id, x, y, text, fontColor)
    return UI.Label {
        id = id,
        text = text or "",
        position = "absolute",
        left = x - 24,
        top = y - 23,
        width = 48,
        height = 16,
        fontSize = 10,
        fontColor = fontColor or {255,211,77,255},
    }
end

local function AddMiniOrderLabel(children, id, x, y)
    table.insert(children, MakeMiniOrderLabel(id, x, y, ""))
end

local function GetOrderMarkerColor(order)
    return (order and (order.markerColor or order.color)) or "#FF5AA5"
end

local function GetOrderLabelColor(order)
    return (order and order.labelColor) or {255,211,77,255}
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
        AddMiniMarker(children, "mini_player_p" .. key .. "_" .. step, x, y, 11, "#A875FF", 6)
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
        RemoveNode(item.label)
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
    if M.minimapPickupLabels[key] then
        M.minimapPickupLabels[key]:SetVisible(false)
        M.minimapPickupLabels[key]:SetText("")
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
                local text = order.displayText or order.label or ""
                local markerColor = GetOrderMarkerColor(order)
                local existing = M.precisePickupNodes[key]
                if not IsMiniPixelVisible(x, y) then
                    if existing then
                        RemoveNode(existing.marker)
                        RemoveNode(existing.label)
                        M.precisePickupNodes[key] = nil
                    end
                    HideLegacyPickupSlot(order.slot)
                    active[key] = true
                else
                    local positionKey = string.format("%.0f,%.0f,%s,%s", x, y, text, markerColor)
                    if existing and existing.positionKey ~= positionKey then
                        RemoveNode(existing.marker)
                        RemoveNode(existing.label)
                        existing = nil
                    end
                    if not existing then
                        local marker = MakeMiniMarkerPanel("mini_pickup_precise_" .. key, x, y, 10, markerColor, 5)
                        local label = MakeMiniOrderLabel("mini_pickup_label_precise_" .. key, x, y, text, GetOrderLabelColor(order))
                        M.minimapPanel:AddChild(marker)
                        M.minimapPanel:AddChild(label)
                        M.precisePickupNodes[key] = {
                            marker = marker,
                            label = label,
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
            RemoveNode(item.label)
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
    M.precisePlayerMarker, M.precisePlayerMarkerKey = SetPreciseMarker(
        M.precisePlayerMarker,
        M.precisePlayerMarkerKey,
        "mini_player_precise",
        navData and navData.playerPoint or nil,
        12,
        "#A875FF",
        6
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
    M.minimapPickupLabels = {}
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
                M.minimapPickupLabels[key] = root:FindById("mini_pickup_label_" .. key)
                if M.minimapRouteSegments[key] then M.minimapRouteSegments[key]:SetVisible(false) end
                if M.minimapTargetMarkers[key] then M.minimapTargetMarkers[key]:SetVisible(false) end
                if M.minimapPickupMarkers[key] then M.minimapPickupMarkers[key]:SetVisible(false) end
                if M.minimapPickupLabels[key] then M.minimapPickupLabels[key]:SetVisible(false) end
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
    local children = {}
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
        AddMiniMarker(children, "mini_pickup_" .. key, x, y, 9, "#FF4FA3", 5)
        AddMiniOrderLabel(children, "mini_pickup_label_" .. key, x, y)
    end

    for key, edge in pairs(segmentPositions) do
        AddMiniPlayerProgressMarkers(children, key, edge)
    end

    rn.ForEachVisibleNode(function(node)
        if node then
            local x, y = MiniPoint(node)
            AddMiniMarker(children, "mini_player_n" .. node.id, x, y, 11, "#A875FF", 6)
        end
    end)

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

function M.Create(onRestart, onTogglePause)
    local wasDebugVisible = M.debugPanelVisible
    M.onRestart = onRestart
    M.onTogglePause = onTogglePause

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
        right = 150,
        top = 92,
        onClick = function()
            M.ToggleDebugPanel()
        end,
    }
    local pauseButton = UI.Button {
        id = "pauseButton",
        text = "暂停",
        width = 52,
        height = 22,
        position = "absolute",
        right = 150,
        top = 118,
        onClick = function()
            if onTogglePause then
                onTogglePause()
            end
        end,
    }

    -- 将 HUD 和 gameOverPanel 合并到同一个根面板
    local root = UI.Panel {
        width = "100%", height = "100%",
        children = {
            hud,
            debugToggle,
            pauseButton,
            M.minimapPanel,
            M.debugPanel,
            M.gameOverPanel,
        },
    }
    M.rootPanel = root
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

    M.minimapRouteSegments = {}
    M.minimapPlayerMarkers = {}
    M.minimapTargetMarkers = {}
    M.minimapPickupMarkers = {}
    M.minimapPickupLabels = {}
    ClearPreciseMinimapNodes()
    BindMinimapRefs(root)

    M.minimapVersion = rn.visibleVersion
    if M.lblMiniStatus then
        M.lblMiniStatus:SetText("等待订单")
    end
    M.SetOrderTimerDisplay(nil)
    RefreshDebugPanel()
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
    if M.minimapPickupLabels[key] then
        M.minimapPickupLabels[key]:SetVisible(false)
        M.minimapPickupLabels[key]:SetText("")
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
                if M.minimapPickupLabels[key] then
                    M.minimapPickupLabels[key]:SetText(order.displayText or order.label or "")
                    M.minimapPickupLabels[key]:SetVisible(true)
                end
            end
        end
    elseif pickupMiniData and pickupMiniData.active and pickupMiniData.slot then
        local key = pickupMiniData.slot
        activeSlots[key] = true
        if M.minimapPickupMarkers[key] then
            M.minimapPickupMarkers[key]:SetVisible(true)
        end
        if M.minimapPickupLabels[key] then
            M.minimapPickupLabels[key]:SetText(pickupMiniData.displayText or "")
            M.minimapPickupLabels[key]:SetVisible(pickupMiniData.displayText ~= nil)
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
end

return M
