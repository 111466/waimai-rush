-- ============================================================================
-- 外卖冲冲冲 - 首页功能页 UI
-- ============================================================================

local UI = require("urhox-libs/UI")
local cfg = require("config")
local CONFIG = cfg.CONFIG
local progression = require("progression")
local meta = require("meta_progress")
local pickup = require("pickup_delivery")

local M = {}

local PAGE_W = 390
local PAGE_H = 844

local ORDER_TYPE_NAMES = {
    normal = "普通",
    nearby = "顺路",
    rush = "急送",
    long = "远距",
    fragile = "易碎",
}

local PAGE_DATA = {
    rider = { title = "骑手成长", subtitle = "升级解锁更多订单和高价路线" },
    upgrades = { title = "局外升级", subtitle = "把每局收入变成永久能力" },
    orders = { title = "订单图鉴", subtitle = "看懂收益、距离和风险" },
    backpack = { title = "背包道具", subtitle = "背包系统暂缓开放" },
    tasks = { title = "今日任务", subtitle = "完成短目标，拿金币和 XP" },
    achievements = { title = "成就墙", subtitle = "记录长期挑战和里程碑" },
    settings = { title = "设置", subtitle = "声音、震动和操作方式" },
}

local PAGE_KEYS = { "rider", "upgrades", "orders", "backpack", "tasks", "achievements", "settings" }

local SETTINGS_ACTIONS = {
    { key = "sound", text = "音效", desc = "按钮、金币、送达反馈", icon = "音", color = "orange" },
    { key = "music", text = "音乐", desc = "首页与跑单背景音乐", icon = "乐", color = "blue" },
    { key = "vibration", text = "震动", desc = "接单、碰撞、完成订单", icon = "震", color = "green" },
    { key = "controlMode", text = "操作方式", desc = "滑动 / 键盘 / 混合", icon = "操", color = "red" },
    { key = "debugPanel", text = "调试面板", desc = "开发相机参数入口", icon = "调", color = "gray" },
}

local UPGRADE_META = {
    rewardBonusLevel = { icon = "奖", color = "orange" },
    powerupDurationLevel = { icon = "时", color = "green" },
    maxOrdersLevel = { icon = "单", color = "blue" },
}

local PROGRESS_ICONS = { "1", "2", "3", "4", "5", "6", "7" }

local ICON_COLORS = {
    blue = "#2A9DF4",
    orange = "#FF8618",
    green = "#22C979",
    red = "#F25F68",
    gray = "#65727C",
}

local function Pct(value)
    return string.format("%.3f%%", value)
end

local function X(value)
    return Pct(value / PAGE_W * 100)
end

local function Y(value)
    return Pct(value / PAGE_H * 100)
end

local function W(value)
    return Pct(value / PAGE_W * 100)
end

local function H(value)
    return Pct(value / PAGE_H * 100)
end

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function SetNodeText(node, text)
    if node and node.SetText then
        node:SetText(text or "")
    end
end

local function SetNodeVisible(node, visible)
    if node and node.SetVisible then
        node:SetVisible(visible == true)
    end
end

local function SetNodeStyle(node, style)
    if node and node.SetStyle then
        node:SetStyle(style)
    end
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

local function MakeText(id, text, left, top, width, height, fontSize, color, align, weight)
    return UI.Label {
        id = id,
        text = text or "",
        position = "absolute",
        left = X(left),
        top = Y(top),
        width = W(width),
        height = H(height),
        fontSize = fontSize,
        fontWeight = weight or "bold",
        fontColor = color or {31,52,66,255},
        textAlign = align or "left",
    }
end

local function MakeLocalText(id, text, left, top, width, height, fontSize, color, align, weight)
    return UI.Label {
        id = id,
        text = text or "",
        position = "absolute",
        left = left,
        top = top,
        width = width,
        height = height,
        fontSize = fontSize,
        fontWeight = weight or "bold",
        fontColor = color or {31,52,66,255},
        textAlign = align or "left",
    }
end

local function MakeImage(id, image, left, top, width, height, fit, opacity)
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

local function MakeLocalImage(id, image, left, top, width, height, fit, opacity)
    return UI.Panel {
        id = id,
        position = "absolute",
        left = left,
        top = top,
        width = width,
        height = height,
        backgroundImage = image,
        backgroundFit = fit or "fill",
        opacity = opacity,
    }
end

local function MakeButton(id, text, left, top, width, height, onClick, color, fontSize)
    return UI.Button {
        id = id,
        text = text or "",
        position = "absolute",
        left = X(left),
        top = Y(top),
        width = W(width),
        height = H(height),
        backgroundColor = color or "#FF8618",
        borderRadius = math.floor(height * 0.5),
        borderWidth = 0,
        fontSize = fontSize or 13,
        fontWeight = "bold",
        fontColor = {255,255,255,255},
        onClick = onClick,
    }
end

local function AddRefs(refs, ids)
    for _, id in ipairs(ids or {}) do
        refs[id] = false
    end
end

local function FindRefs(root, refs)
    for id, _ in pairs(refs) do
        refs[id] = root:FindById(id)
    end
end

local function FormatOnOff(value)
    return value and "开" or "关"
end

local function FormatReward(row)
    local parts = {}
    if (row.coins or 0) > 0 then
        parts[#parts + 1] = "¥" .. tostring(row.coins)
    end
    if (row.xp or 0) > 0 then
        parts[#parts + 1] = "XP " .. tostring(row.xp)
    end
    if #parts == 0 then
        return "无奖励"
    end
    return table.concat(parts, " · ")
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

local function FindNextUnlockText(level)
    local bestLevel = nil
    local parts = {}

    for _, row in ipairs(CONFIG.RIDER_ORDER_COUNT_UNLOCKS or {}) do
        if row.level and row.level > level and (not bestLevel or row.level < bestLevel) then
            bestLevel = row.level
        end
    end
    for _, unlockLevel in pairs(CONFIG.RIDER_ORDER_TYPE_UNLOCKS or {}) do
        if unlockLevel and unlockLevel > level and (not bestLevel or unlockLevel < bestLevel) then
            bestLevel = unlockLevel
        end
    end

    if not bestLevel then
        return "已解锁全部骑手成长内容"
    end

    for _, row in ipairs(CONFIG.RIDER_ORDER_COUNT_UNLOCKS or {}) do
        if row.level == bestLevel then
            parts[#parts + 1] = tostring(row.count or 0) .. " 个同时订单"
        end
    end
    for typeId, unlockLevel in pairs(CONFIG.RIDER_ORDER_TYPE_UNLOCKS or {}) do
        if unlockLevel == bestLevel then
            parts[#parts + 1] = (ORDER_TYPE_NAMES[typeId] or typeId) .. "单"
        end
    end

    if #parts == 0 then
        return "下一等级继续提升订单能力"
    end
    return "下一等级 Lv." .. tostring(bestLevel) .. ": " .. table.concat(parts, " / ")
end

local function ExtractUpgradeRows()
    local raw = meta.GetUpgradeRows and meta.GetUpgradeRows() or {}
    local result = {}
    local keys = meta.GetUpgradeKeys and meta.GetUpgradeKeys() or {}
    for i, key in ipairs(keys) do
        local text = raw[i + 1] or ""
        local name = meta.GetUpgradeName and meta.GetUpgradeName(key) or key
        local level, maxLevel = string.match(text, "Lv%.(%d+)/(%d+)")
        local cost = string.match(text, "升级 ¥(%d+)")
        local desc = string.match(text, "%s%s([^%s].-)升级 ¥")
        if not desc then
            desc = string.match(text, "%s%s([^%s].-)已满级")
        end
        result[#result + 1] = {
            key = key,
            name = name,
            desc = desc or text,
            level = tonumber(level) or 0,
            maxLevel = tonumber(maxLevel) or 1,
            cost = cost and tonumber(cost) or nil,
        }
    end
    return result
end

local function MakeIcon(id, text, left, top, size, colorName)
    local color = ICON_COLORS[colorName or "blue"] or ICON_COLORS.blue
    return UI.Panel {
        id = id,
        position = "absolute",
        left = X(left),
        top = Y(top),
        width = W(size),
        height = H(size),
        backgroundColor = color,
        borderRadius = 14,
        borderWidth = 0,
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Label {
                id = id and (id .. "Text") or nil,
                text = text or "",
                width = "100%",
                height = "70%",
                fontSize = 18,
                fontWeight = "bold",
                fontColor = {255,255,255,255},
                textAlign = "center",
            },
        },
    }
end

local function MakeProgress(id, left, top, width, fillId)
    return UI.Panel {
        id = id,
        position = "absolute",
        left = X(left),
        top = Y(top),
        width = W(width),
        height = H(8),
        backgroundColor = "rgba(34,52,63,0.14)",
        borderRadius = 8,
        children = {
            UI.Panel {
                id = fillId,
                position = "absolute",
                left = 0,
                top = 0,
                width = W(2),
                height = "100%",
                backgroundColor = "#22C979",
                borderRadius = 8,
            },
        },
    }
end

local function MakeLocalProgress(id, left, top, width, fillId)
    return UI.Panel {
        id = id,
        position = "absolute",
        left = left,
        top = top,
        width = width,
        height = 8,
        backgroundColor = "rgba(34,52,63,0.14)",
        borderRadius = 8,
        children = {
            UI.Panel {
                id = fillId,
                position = "absolute",
                left = 0,
                top = 0,
                width = 2,
                height = 8,
                backgroundColor = "#22C979",
                borderRadius = 8,
            },
        },
    }
end

local function SetProgressFill(node, width)
    SetNodeStyle(node, {
        width = math.max(2, width),
    })
end

local function MakeRowShell(id, left, top, width, height)
    return UI.Panel {
        id = id,
        position = "absolute",
        left = X(left),
        top = Y(top),
        width = W(width),
        height = H(height),
        backgroundColor = "rgba(255,255,255,0.72)",
        borderRadius = 16,
        borderWidth = 3,
    }
end

local function MakeLocalRect(id, left, top, width, height, color, radius)
    return UI.Panel {
        id = id,
        position = "absolute",
        left = left,
        top = top,
        width = width,
        height = height,
        backgroundColor = color,
        borderRadius = radius or 0,
    }
end

local function MakeWallet()
    return UI.Panel {
        position = "absolute",
        left = X(258),
        top = Y(14),
        width = W(116),
        height = H(44),
        backgroundColor = "#FF8618",
        borderRadius = 22,
        borderWidth = 3,
        children = {
            MakeLocalImage(nil, "Textures/home_coin_icon.png", 12, 9, 24, 24),
            UI.Label {
                id = "systemWalletCoins",
                text = "0",
                position = "absolute",
                left = 43,
                top = 7,
                width = 62,
                height = 27,
                fontSize = 20,
                fontWeight = "bold",
                fontColor = {255,255,255,255},
                textAlign = "left",
            },
        },
    }
end

local function MakeTopShell(context)
    return {
        MakeImage("systemBg", "Textures/home_scene_bg_static.png", 0, 0, 390, 844),
        UI.Panel {
            position = "absolute",
            left = 0,
            top = 0,
            right = 0,
            bottom = 0,
            backgroundColor = "rgba(126,220,255,0.18)",
        },
        MakeImage("systemCloudOne", "Textures/home_cloud_one.png", 24, 72, 104, 48, "fill", 0.78),
        MakeImage("systemCloudTwo", "Textures/home_cloud_two.png", 236, 126, 122, 58, "fill", 0.70),
        UI.Panel {
            id = "systemSheet",
            position = "absolute",
            left = X(16),
            top = Y(160),
            width = W(358),
            height = H(666),
            backgroundColor = "#FFF1BB",
            borderRadius = 22,
            borderWidth = 4,
        },
    }
end

local function MakeTopOverlay(context)
    return {
        MakeButton("systemBackButton", "‹", 16, 14, 44, 44, function()
            if context and context.onBack then
                context.onBack()
            end
        end, "#28B8F0", 24),
        MakeWallet(),
        MakeText("systemPageTitle", "骑手成长", 70, 84, 250, 38, 30, {255,255,255,255}, "center"),
        UI.Panel {
            id = "systemSubtitleBadge",
            position = "absolute",
            left = X(70),
            top = Y(122),
            width = W(250),
            height = H(26),
            backgroundColor = "rgba(255,247,223,0.94)",
            borderRadius = 13,
            borderWidth = 2,
            justifyContent = "center",
            children = {
                UI.Label {
                    id = "systemPageSubtitle",
                    text = "",
                    width = "100%",
                    height = "70%",
                    fontSize = 12,
                    fontWeight = "bold",
                    fontColor = {102,51,5,255},
                    textAlign = "center",
                },
            },
        },
    }
end

local function MakePagePanel(id, children)
    return UI.Panel {
        id = id,
        width = "100%",
        height = "100%",
        position = "absolute",
        children = children,
    }
end

local function MakeRiderPage()
    local children = {
        UI.Panel {
            id = "systemRiderAvatar",
            position = "absolute",
            left = X(42),
            top = Y(206),
            width = W(112),
            height = H(112),
            backgroundColor = "#E6F7FF",
            borderRadius = 30,
            borderWidth = 4,
            children = {
                MakeLocalImage(nil, "Textures/home_rider.png", -18, -10, 148, 148),
            },
        },
        UI.Panel {
            position = "absolute",
            left = X(178),
            top = Y(218),
            width = W(176),
            height = H(94),
            backgroundColor = "#172A37",
            borderRadius = 18,
            children = {
                MakeLocalText("riderLevelText", "Lv.1 新手骑手", 12, 11, 152, 21, 18, {255,255,255,255}, "left"),
                MakeLocalText("riderXpText", "XP 0 / 60", 12, 39, 152, 15, 12, {183,231,255,255}, "left"),
                MakeLocalProgress(nil, 12, 65, 152, "riderXpFill"),
            },
        },
        MakeRowShell("riderStatRow1", 34, 340, 155, 72),
        MakeRowShell("riderStatRow2", 201, 340, 155, 72),
        MakeRowShell("riderStatRow3", 34, 424, 155, 72),
        MakeRowShell("riderStatRow4", 201, 424, 155, 72),
        MakeText("riderStatValue1", "2", 48, 354, 128, 25, 22, {255,134,24,255}, "left"),
        MakeText("riderStatLabel1", "同时订单点", 48, 388, 128, 16, 12, {95,74,34,255}, "left"),
        MakeText("riderStatValue2", "+0%", 215, 354, 128, 25, 22, {255,134,24,255}, "left"),
        MakeText("riderStatLabel2", "配送奖励", 215, 388, 128, 16, 12, {95,74,34,255}, "left"),
        MakeText("riderStatValue3", "0", 48, 438, 128, 25, 22, {255,134,24,255}, "left"),
        MakeText("riderStatLabel3", "累计送达", 48, 472, 128, 16, 12, {95,74,34,255}, "left"),
        MakeText("riderStatValue4", "x0", 215, 438, 128, 25, 22, {255,134,24,255}, "left"),
        MakeText("riderStatLabel4", "最高连击", 215, 472, 128, 16, 12, {95,74,34,255}, "left"),
        UI.Panel {
            position = "absolute",
            left = X(34),
            top = Y(516),
            width = W(322),
            height = H(56),
            backgroundColor = "rgba(255,236,170,0.82)",
            borderRadius = 15,
            justifyContent = "center",
            children = {
                UI.Label {
                    id = "riderNextUnlock",
                    text = "",
                    width = "100%",
                    height = "70%",
                    fontSize = 12,
                    fontWeight = "bold",
                    fontColor = {122,57,0,255},
                    textAlign = "center",
                },
            },
        },
        MakeText("riderUnlockedTypes", "已解锁: 普通", 42, 596, 306, 18, 12, {102,51,5,255}, "center"),
    }
    return MakePagePanel("systemPageRider", children)
end

local function MakeUpgradeRow(index, y, context)
    local id = tostring(index)
    return {
        MakeRowShell("upgradeRow" .. id, 34, y, 322, 72),
        MakeIcon("upgradeIcon" .. id, "", 46, y + 15, 42, "blue"),
        MakeText("upgradeName" .. id, "", 98, y + 11, 154, 18, 14, {31,52,66,255}, "left"),
        MakeText("upgradeDesc" .. id, "", 98, y + 35, 154, 15, 11, {106,125,136,255}, "left"),
        MakeProgress("upgradeProgress" .. id, 98, y + 56, 154, "upgradeFill" .. id),
        MakeButton("upgradeButton" .. id, "升级", 270, y + 21, 66, 30, function()
            if context and context.onUpgrade then
                context.onUpgrade(index)
            end
        end, "#FF8618", 12),
    }
end

local function MakeUpgradePage(context)
    local children = {}
    local ys = {206, 290, 374}
    for i = 1, 3 do
        local row = MakeUpgradeRow(i, ys[i], context)
        for _, child in ipairs(row) do
            children[#children + 1] = child
        end
    end
    children[#children + 1] = MakeButton("upgradeBuyAllButton", "购买当前可升级项", 42, 740, 306, 52, function()
        if context and context.onUpgradeAll then
            context.onUpgradeAll()
        end
    end, "#FF8618", 20)
    return MakePagePanel("systemPageUpgrades", children)
end

local function MakeOrdersPage()
    local children = {
        UI.Panel {
            id = "ordersMiniMap",
            position = "absolute",
            left = X(34),
            top = Y(196),
            width = W(322),
            height = H(126),
            backgroundColor = "rgba(22,45,59,0.86)",
            borderRadius = 18,
            borderWidth = 3,
            children = {
                MakeLocalRect(nil, 28, 58, 252, 6, "#2EE6C0", 6),
                MakeLocalRect(nil, 150, 28, 6, 78, "#2EE6C0", 6),
                UI.Panel { position = "absolute", left = 72, top = 49, width = 16, height = 16, backgroundColor = "#FFD447", borderRadius = 8, borderWidth = 3 },
                UI.Panel { position = "absolute", left = 148, top = 82, width = 16, height = 16, backgroundColor = "#22C979", borderRadius = 8, borderWidth = 3 },
                UI.Panel { position = "absolute", left = 220, top = 49, width = 16, height = 16, backgroundColor = "#F25F68", borderRadius = 8, borderWidth = 3 },
            },
        },
        MakeText("ordersCapacity", "", 44, 330, 302, 16, 12, {102,51,5,255}, "center"),
    }

    local ys = {358, 430, 502, 574, 646}
    for i = 1, 5 do
        local id = tostring(i)
        children[#children + 1] = MakeRowShell("orderRow" .. id, 34, ys[i], 322, 62)
        children[#children + 1] = MakeIcon("orderIcon" .. id, "", 46, ys[i] + 10, 40, "green")
        children[#children + 1] = MakeText("orderName" .. id, "", 98, ys[i] + 10, 148, 17, 14, {31,52,66,255}, "left")
        children[#children + 1] = MakeText("orderDesc" .. id, "", 98, ys[i] + 33, 154, 15, 11, {106,125,136,255}, "left")
        children[#children + 1] = UI.Panel {
            id = "orderPricePanel" .. id,
            position = "absolute",
            left = X(286),
            top = Y(ys[i] + 17),
            width = W(52),
            height = H(28),
            backgroundColor = "#FF8618",
            borderRadius = 14,
            justifyContent = "center",
            children = {
                UI.Label {
                    id = "orderPrice" .. id,
                    text = "",
                    width = "100%",
                    height = "70%",
                    fontSize = 13,
                    fontWeight = "bold",
                    fontColor = {255,255,255,255},
                    textAlign = "center",
                },
            },
        }
    end
    return MakePagePanel("systemPageOrders", children)
end

local function MakeProgressItemRow(prefix, index, y, context)
    local id = tostring(index)
    local claimFunc = function()
        if context and context.onClaimOne then
            context.onClaimOne(prefix, index)
        end
    end
    return {
        MakeRowShell(prefix .. "Row" .. id, 34, y, 322, 68),
        MakeIcon(prefix .. "Icon" .. id, "", 46, y + 13, 42, "orange"),
        MakeText(prefix .. "Name" .. id, "", 98, y + 10, 154, 17, 14, {31,52,66,255}, "left"),
        MakeText(prefix .. "Desc" .. id, "", 98, y + 32, 154, 15, 11, {106,125,136,255}, "left"),
        MakeProgress(prefix .. "Progress" .. id, 98, y + 53, 154, prefix .. "Fill" .. id),
        MakeButton(prefix .. "Claim" .. id, "进行中", 270, y + 20, 66, 30, claimFunc, "#A8B5BD", 12),
    }
end

local function MakeTasksPage(context)
    local children = {}
    local ys = {204, 282, 360, 438, 516, 594}
    for i = 1, 6 do
        local row = MakeProgressItemRow("task", i, ys[i], context)
        for _, child in ipairs(row) do
            children[#children + 1] = child
        end
    end
    children[#children + 1] = MakeButton("taskClaimAllButton", "领取已完成任务", 42, 740, 306, 52, function()
        if context and context.onClaimAllTasks then
            context.onClaimAllTasks()
        end
    end, "#FF8618", 20)
    return MakePagePanel("systemPageTasks", children)
end

local function MakeAchievementsPage(context)
    local children = {}
    local ys = {188, 256, 324, 392, 460, 528, 596, 664}
    for i = 1, 8 do
        local row = MakeProgressItemRow("achievement", i, ys[i], context)
        for _, child in ipairs(row) do
            children[#children + 1] = child
        end
    end
    children[#children + 1] = MakeButton("achievementClaimAllButton", "领取可领成就", 42, 740, 306, 52, function()
        if context and context.onClaimAllAchievements then
            context.onClaimAllAchievements()
        end
    end, "#FF8618", 20)
    return MakePagePanel("systemPageAchievements", children)
end

local function MakeSettingsPage(context)
    local children = {}
    local ys = {204, 282, 360, 438, 516}
    for i, action in ipairs(SETTINGS_ACTIONS) do
        local id = tostring(i)
        children[#children + 1] = MakeRowShell("settingRow" .. id, 34, ys[i], 322, 68)
        children[#children + 1] = MakeIcon("settingIcon" .. id, action.icon, 46, ys[i] + 13, 42, action.color)
        children[#children + 1] = MakeText("settingName" .. id, action.text, 98, ys[i] + 12, 154, 17, 14, {31,52,66,255}, "left")
        children[#children + 1] = MakeText("settingDesc" .. id, action.desc, 98, ys[i] + 36, 154, 15, 11, {106,125,136,255}, "left")
        children[#children + 1] = MakeButton("settingButton" .. id, "", 270, ys[i] + 20, 66, 30, function()
            if context and context.onSetting then
                context.onSetting(action.key)
            end
        end, "#22C979", 12)
    end
    children[#children + 1] = UI.Panel {
        position = "absolute",
        left = X(42),
        top = Y(616),
        width = W(306),
        height = H(48),
        backgroundColor = "rgba(255,236,170,0.82)",
        borderRadius = 15,
        justifyContent = "center",
        children = {
            UI.Label {
                text = "设置会自动写入本地存档",
                width = "100%",
                height = "70%",
                fontSize = 12,
                fontWeight = "bold",
                fontColor = {122,57,0,255},
                textAlign = "center",
            },
        },
    }
    children[#children + 1] = MakeButton("settingsSaveButton", "保存设置", 42, 740, 306, 52, function()
        if context and context.onSaveSettings then
            context.onSaveSettings()
        end
    end, "#FF8618", 20)
    return MakePagePanel("systemPageSettings", children)
end

local function MakeBackpackPage()
    return MakePagePanel("systemPageBackpack", {
        UI.Panel {
            position = "absolute",
            left = X(34),
            top = Y(234),
            width = W(322),
            height = H(128),
            backgroundColor = "rgba(255,236,170,0.86)",
            borderRadius = 18,
            borderWidth = 3,
            justifyContent = "center",
            children = {
                UI.Label {
                    id = "backpackNote",
                    text = "背包系统暂缓开放\n当前局内道具仍会在路上刷新",
                    width = "100%",
                    height = "70%",
                    fontSize = 16,
                    fontWeight = "bold",
                    fontColor = {122,57,0,255},
                    textAlign = "center",
                },
            },
        },
    })
end

local function GatherRefs(root)
    local refs = {}
    AddRefs(refs, {
        "systemWalletCoins", "systemPageTitle", "systemPageSubtitle",
        "systemCloudOne", "systemCloudTwo", "systemRiderAvatar",
        "systemPageRider", "systemPageUpgrades", "systemPageOrders", "systemPageBackpack",
        "systemPageTasks", "systemPageAchievements", "systemPageSettings",
        "riderLevelText", "riderXpText", "riderXpFill", "riderNextUnlock", "riderUnlockedTypes",
        "riderStatValue1", "riderStatValue2", "riderStatValue3", "riderStatValue4",
        "ordersCapacity",
        "upgradeBuyAllButton", "taskClaimAllButton", "achievementClaimAllButton",
    })
    for i = 1, 4 do
        AddRefs(refs, { "riderStatRow" .. tostring(i) })
    end
    for i = 1, 3 do
        AddRefs(refs, {
            "upgradeRow" .. tostring(i), "upgradeIcon" .. tostring(i), "upgradeName" .. tostring(i),
            "upgradeIcon" .. tostring(i) .. "Text", "upgradeDesc" .. tostring(i),
            "upgradeProgress" .. tostring(i), "upgradeFill" .. tostring(i), "upgradeButton" .. tostring(i),
        })
    end
    for i = 1, 5 do
        AddRefs(refs, {
            "orderRow" .. tostring(i), "orderIcon" .. tostring(i), "orderName" .. tostring(i),
            "orderIcon" .. tostring(i) .. "Text", "orderDesc" .. tostring(i),
            "orderPricePanel" .. tostring(i), "orderPrice" .. tostring(i),
        })
    end
    for i = 1, 6 do
        AddRefs(refs, {
            "taskRow" .. tostring(i), "taskIcon" .. tostring(i), "taskName" .. tostring(i),
            "taskIcon" .. tostring(i) .. "Text", "taskDesc" .. tostring(i),
            "taskProgress" .. tostring(i), "taskFill" .. tostring(i), "taskClaim" .. tostring(i),
        })
    end
    for i = 1, 8 do
        AddRefs(refs, {
            "achievementRow" .. tostring(i), "achievementIcon" .. tostring(i), "achievementName" .. tostring(i),
            "achievementIcon" .. tostring(i) .. "Text", "achievementDesc" .. tostring(i),
            "achievementProgress" .. tostring(i), "achievementFill" .. tostring(i), "achievementClaim" .. tostring(i),
        })
    end
    for i = 1, 5 do
        AddRefs(refs, { "settingButton" .. tostring(i) })
    end
    FindRefs(root, refs)
    return refs
end

function M.Build(context)
    local children = {}
    for _, child in ipairs(MakeTopShell(context)) do
        children[#children + 1] = child
    end
    children[#children + 1] = MakeRiderPage()
    children[#children + 1] = MakeUpgradePage(context)
    children[#children + 1] = MakeOrdersPage()
    children[#children + 1] = MakeBackpackPage()
    children[#children + 1] = MakeTasksPage(context)
    children[#children + 1] = MakeAchievementsPage(context)
    children[#children + 1] = MakeSettingsPage(context)
    for _, child in ipairs(MakeTopOverlay(context)) do
        children[#children + 1] = child
    end

    return UI.Panel {
        id = "staticPagePanel",
        width = "100%",
        height = "100%",
        position = "absolute",
        children = children,
    }
end

function M.Bind(root)
    return GatherRefs(root)
end

local function SetPageCommon(refs, key)
    local data = PAGE_DATA[key] or PAGE_DATA.rider
    for _, pageKey in ipairs(PAGE_KEYS) do
        local refName = "systemPage" .. string.upper(string.sub(pageKey, 1, 1)) .. string.sub(pageKey, 2)
        SetNodeVisible(refs[refName], pageKey == key)
    end
    SetNodeText(refs.systemPageTitle, data.title)
    SetNodeText(refs.systemPageSubtitle, data.subtitle)
    local summary = meta.GetSummary and meta.GetSummary() or {}
    SetNodeText(refs.systemWalletCoins, tostring(summary.coins or 0))
end

local function UpdateRider(refs)
    local data = progression.GetHUDData and progression.GetHUDData() or {}
    local summary = meta.GetSummary and meta.GetSummary() or {}
    local xpProgress = Clamp(data.progress or 1.0, 0.0, 1.0)
    local xpText = data.maxLevel and "XP MAX" or ("XP " .. tostring(data.xp or 0) .. " / " .. tostring(data.xpToNext or 0))

    SetNodeText(refs.riderLevelText, "Lv." .. tostring(data.level or summary.riderLevel or 1) .. " " .. tostring(data.title or summary.riderTitle or "骑手"))
    SetNodeText(refs.riderXpText, xpText)
    SetProgressFill(refs.riderXpFill, 152 * xpProgress)
    SetNodeText(refs.riderStatValue1, tostring(progression.GetMaxAvailableOrders and progression.GetMaxAvailableOrders() or 2))
    SetNodeText(refs.riderStatValue2, "+" .. tostring(summary.rewardBonusPercent or 0) .. "%")
    SetNodeText(refs.riderStatValue3, tostring(summary.totalDeliveries or 0))
    SetNodeText(refs.riderStatValue4, "x" .. tostring(summary.bestCombo or 0))
    SetNodeText(refs.riderNextUnlock, FindNextUnlockText(data.level or summary.riderLevel or 1))
    SetNodeText(refs.riderUnlockedTypes, "已解锁: " .. FormatUnlockedOrderTypes(progression.GetUnlockedOrderTypes and progression.GetUnlockedOrderTypes() or {}))
end

local function UpdateUpgrades(refs)
    local rows = ExtractUpgradeRows()
    local summary = meta.GetSummary and meta.GetSummary() or {}
    SetNodeText(refs.systemWalletCoins, tostring(summary.coins or 0))
    for i = 1, 3 do
        local row = rows[i]
        local suffix = tostring(i)
        SetNodeVisible(refs["upgradeRow" .. suffix], row ~= nil)
        SetNodeVisible(refs["upgradeIcon" .. suffix], row ~= nil)
        SetNodeVisible(refs["upgradeName" .. suffix], row ~= nil)
        SetNodeVisible(refs["upgradeDesc" .. suffix], row ~= nil)
        SetNodeVisible(refs["upgradeProgress" .. suffix], row ~= nil)
        SetNodeVisible(refs["upgradeButton" .. suffix], row ~= nil)
        if row then
            local visual = UPGRADE_META[row.key] or { icon = "升", color = "blue" }
            local icon = refs["upgradeIcon" .. suffix]
            SetNodeText(refs["upgradeName" .. suffix], row.name .. " Lv." .. tostring(row.level))
            SetNodeText(refs["upgradeDesc" .. suffix], row.desc)
            if icon and icon.SetStyle then
                icon:SetStyle({ backgroundColor = ICON_COLORS[visual.color] or ICON_COLORS.blue })
            end
            SetNodeText(refs["upgradeIcon" .. suffix .. "Text"], visual.icon or "升")
            SetProgressFill(refs["upgradeFill" .. suffix], 154 * Clamp(row.level / math.max(1, row.maxLevel), 0, 1))
            local button = refs["upgradeButton" .. suffix]
            if button then
                if row.cost then
                    button:SetText("¥" .. tostring(row.cost))
                    button:SetStyle({ backgroundColor = "#FF8618" })
                else
                    button:SetText("满级")
                    button:SetStyle({ backgroundColor = "#A8B5BD" })
                end
            end
        end
    end
end

local function UpdateOrders(refs)
    local orderRows = pickup.GetOrderTypeRows and pickup.GetOrderTypeRows() or {}
    SetNodeText(refs.ordersCapacity, "当前可同时显示 " .. tostring(progression.GetMaxAvailableOrders and progression.GetMaxAvailableOrders() or 2) .. " 个取餐点")
    for i = 1, 5 do
        local row = orderRows[i]
        local suffix = tostring(i)
        local visible = row ~= nil
        SetNodeVisible(refs["orderRow" .. suffix], visible)
        SetNodeVisible(refs["orderIcon" .. suffix], visible)
        SetNodeVisible(refs["orderName" .. suffix], visible)
        SetNodeVisible(refs["orderDesc" .. suffix], visible)
        SetNodeVisible(refs["orderPricePanel" .. suffix], visible)
        if row then
            local unlockLevel = progression.GetOrderTypeUnlockLevel and progression.GetOrderTypeUnlockLevel(row.id) or 1
            local unlocked = progression.IsOrderTypeUnlocked and progression.IsOrderTypeUnlocked(row.id)
            local status = unlocked and "已解锁" or ("Lv." .. tostring(unlockLevel or 1) .. " 解锁")
            local risk = row.fragile and "碰撞会失败" or ("罚时x" .. string.format("%.1f", row.latePenaltyMultiplier or 1.0))
            local delivered = meta.GetDeliveredOrderTypeCount and meta.GetDeliveredOrderTypeCount(row.id) or 0
            local icon = refs["orderIcon" .. suffix]
            if icon and icon.SetStyle then
                icon:SetStyle({ backgroundColor = row.color or ICON_COLORS.green })
            end
            SetNodeText(refs["orderIcon" .. suffix .. "Text"], row.label or "单")
            SetNodeText(refs["orderName" .. suffix], tostring(row.name or ORDER_TYPE_NAMES[row.id] or "订单") .. "单")
            SetNodeText(refs["orderDesc" .. suffix], status .. " · " .. risk .. " · 已送" .. tostring(delivered))
            SetNodeText(refs["orderPrice" .. suffix], "¥" .. tostring(row.reward or 0))
        end
    end
end

local function UpdateProgressRows(refs, prefix, rows, maxRows)
    for i = 1, maxRows do
        local row = rows[i]
        local suffix = tostring(i)
        local visible = row ~= nil
        SetNodeVisible(refs[prefix .. "Row" .. suffix], visible)
        SetNodeVisible(refs[prefix .. "Icon" .. suffix], visible)
        SetNodeVisible(refs[prefix .. "Name" .. suffix], visible)
        SetNodeVisible(refs[prefix .. "Desc" .. suffix], visible)
        SetNodeVisible(refs[prefix .. "Progress" .. suffix], visible)
        SetNodeVisible(refs[prefix .. "Claim" .. suffix], visible)
        if row then
            local progress = Clamp((row.current or 0) / math.max(1, row.target or 1), 0, 1)
            local state = "进行中"
            local color = "#A8B5BD"
            if row.claimed then
                state = "已领"
                color = "#A8B5BD"
            elseif row.done then
                state = "领取"
                color = "#FF8618"
            end
            SetNodeText(refs[prefix .. "Name" .. suffix], row.name or "")
            SetNodeText(refs[prefix .. "Icon" .. suffix .. "Text"], PROGRESS_ICONS[i] or tostring(i))
            SetNodeText(refs[prefix .. "Desc" .. suffix], tostring(row.current or 0) .. " / " .. tostring(row.target or 1) .. " · " .. FormatReward(row))
            SetProgressFill(refs[prefix .. "Fill" .. suffix], 154 * progress)
            local button = refs[prefix .. "Claim" .. suffix]
            if button then
                button:SetText(state)
                button:SetStyle({ backgroundColor = color })
            end
        end
    end
end

local function UpdateSettings(refs)
    local settings = meta.GetSettings and meta.GetSettings() or {}
    local values = {
        sound = FormatOnOff(settings.sound ~= false),
        music = FormatOnOff(settings.music ~= false),
        vibration = FormatOnOff(settings.vibration ~= false),
        controlMode = tostring(settings.controlMode or "混合"),
        debugPanel = FormatOnOff(settings.debugPanel == true),
    }
    for i, action in ipairs(SETTINGS_ACTIONS) do
        local button = refs["settingButton" .. tostring(i)]
        if button then
            button:SetText(values[action.key] or action.text)
            local enabled = true
            if action.key == "debugPanel" then
                enabled = settings.debugPanel == true
            elseif action.key ~= "controlMode" then
                enabled = settings[action.key] ~= false
            end
            button:SetStyle({ backgroundColor = enabled and "#22C979" or "#A8B5BD" })
        end
    end
end

function M.Refresh(refs, key)
    if not refs then return end
    SetPageCommon(refs, key)
    if key == "rider" then
        UpdateRider(refs)
    elseif key == "upgrades" then
        UpdateUpgrades(refs)
    elseif key == "orders" then
        UpdateOrders(refs)
    elseif key == "tasks" then
        UpdateProgressRows(refs, "task", meta.GetTaskRows and meta.GetTaskRows() or {}, 6)
    elseif key == "achievements" then
        UpdateProgressRows(refs, "achievement", meta.GetAchievementRows and meta.GetAchievementRows() or {}, 8)
    elseif key == "settings" then
        UpdateSettings(refs)
    end
end

function M.StartAnimations(refs)
    if not refs then return end
    PlayNodeAnimation(refs.systemCloudOne, {
        keyframes = {
            [0] = { translateX = 0 },
            [0.5] = { translateX = 12 },
            [1] = { translateX = 0 },
        },
        duration = 7.0,
        easing = "easeInOut",
        loop = true,
    })
    PlayNodeAnimation(refs.systemCloudTwo, {
        keyframes = {
            [0] = { translateX = 10 },
            [0.5] = { translateX = -8 },
            [1] = { translateX = 10 },
        },
        duration = 8.0,
        easing = "easeInOut",
        loop = true,
    })
    PlayNodeAnimation(refs.systemRiderAvatar, {
        keyframes = {
            [0] = { translateY = 0 },
            [0.5] = { translateY = -6 },
            [1] = { translateY = 0 },
        },
        duration = 1.2,
        easing = "easeInOut",
        loop = true,
    })
end

function M.StopAnimations(refs)
    if not refs then return end
    StopNodeAnimation(refs.systemCloudOne)
    StopNodeAnimation(refs.systemCloudTwo)
    StopNodeAnimation(refs.systemRiderAvatar)
end

function M.GetSettingAction(indexOrKey)
    if type(indexOrKey) == "number" then
        return SETTINGS_ACTIONS[indexOrKey]
    end
    for _, action in ipairs(SETTINGS_ACTIONS) do
        if action.key == indexOrKey then
            return action
        end
    end
    return nil
end

function M.GetUpgradeKey(index)
    local keys = meta.GetUpgradeKeys and meta.GetUpgradeKeys() or {}
    return keys[index]
end

return M
