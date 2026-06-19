# 首页游戏化 UI 实现方案

## 目标

基于 `prototypes/home-ui-redesign/index.html` 和当前截图，实现一版接近 100% 还原的首页主菜单。

核心目标：
- 首页第一眼像游戏主菜单，而不是应用首页。
- 保留截图中的城市、道路、标题、骑手、悬赏牌、右侧按钮、底部大按钮和底部入口。
- Lua 只负责动态文字、点击、少量动效和页面跳转。
- 复杂视觉不在 Lua 里硬拼，统一烘焙成 PNG 贴图。

## 当前依据

原型位置：

```text
prototypes/home-ui-redesign/index.html
```

现有首页入口位置：

```text
scripts/ui.lua
BuildMainMenu()
```

TapTap 制造 / urhox-libs/UI 已确认：
- `UI.Panel` 支持 `backgroundImage` 和 `backgroundFit`。
- `UI.Button` 支持 `backgroundImage`、`hoverBackgroundImage`、`pressedBackgroundImage`。
- 图片资源放在 `assets/Textures/`。
- Lua 路径写 `Textures/xxx.png`，不写 `assets/`。
- 不需要 `.meta` 文件，不需要编辑器导入。
- 透明按钮用 `backgroundColor = {0,0,0,0}` 和 `borderWidth = 0`。
- Label 颜色继续用 `fontColor`。
- `Animate()`、`StopAnimation()`、`SetProp()`、`SetStyle()` 可用于简单动效。

## 实现原则

不要把 HTML/CSS 逐条翻译成 Lua。

HTML 中这些效果应烘焙为图片：
- 渐变天空。
- 太阳、云朵。
- 城市楼群。
- 透视道路。
- 路面阴影、速度线、车道线静态底稿。
- 标题描边和投影。
- 悬赏牌外观。
- 圆形入口按钮外观。
- 底部按钮和底部浅色渐变区域。

Lua 中保留这些动态层：
- `Lv.1 新手骑手`。
- `最高 0 单 / 连击 0`。
- XP 进度条宽度。
- 金币数量。
- `接单开冲` 点击。
- 骑手轻微浮动。
- 主按钮轻微呼吸。
- 入口按钮点击热区。

## 素材拆分

建议以 390x844 为设计基准，导出 2 倍图用于清晰显示。

第一版推荐素材：

```text
assets/Textures/home_bg.png
assets/Textures/home_rider.png
assets/Textures/home_start_button.png
assets/Textures/home_start_button_pressed.png
assets/Textures/home_level_badge.png
assets/Textures/home_coin_badge.png
assets/Textures/home_xp_track.png
assets/Textures/home_xp_fill.png
```

如果希望按钮和入口后续独立换状态，再增加：

```text
assets/Textures/home_task_button.png
assets/Textures/home_achievement_button.png
assets/Textures/home_settings_button.png
assets/Textures/home_rider_button.png
assets/Textures/home_upgrade_button.png
assets/Textures/home_order_button.png
assets/Textures/home_bag_button.png
```

### `home_bg.png`

包含：
- 天空、太阳、云。
- 城市楼群。
- 透视道路。
- 标题“外卖冲冲冲”。
- 副标题“接单上路，准时送达”。
- 悬赏牌底图和文字。
- 右侧 `任务 / 成就 / 设置` 按钮外观。
- 底部浅色渐变区域。
- 底部四个入口按钮外观。

不包含：
- 顶部等级文字。
- 顶部最高单/连击文字。
- XP 绿色进度条。
- 金币数字。
- 骑手图。
- 主按钮图。

这样能最大限度减少 Lua 布局复杂度，同时保留动态数据。

### `home_rider.png`

包含骑手完整形象，保持透明背景。

第一版可以继续使用当前白色圆角底板效果，因为截图里它已经成立。后续如果要更强跑酷感，再替换为透明骑手。

### `home_start_button.png`

包含橙色按钮外观、白色描边、厚阴影、两侧短白线和文字 `接单开冲`。

Lua 按钮 `text = ""`，只使用图片和点击事件。

### 顶部 HUD 素材

为了动态显示等级和金币，顶部两个 Badge 建议分开：
- `home_level_badge.png`：深色等级底板，不含文字。
- `home_coin_badge.png`：橙色金币底板和金币小图，不含金币数字。
- `home_xp_track.png`：XP 灰色底槽。
- `home_xp_fill.png`：XP 绿色填充，可用宽度裁切或直接用 Panel 背景色。

## Lua 层级结构

建议 `BuildMainMenu()` 改为绝对定位层叠结构：

```text
mainMenuPanel
├─ home_bg.png 全屏背景
├─ home_level_badge.png
│  ├─ menuRiderLevel Label
│  ├─ menuBest Label
│  └─ XP 进度条
├─ home_coin_badge.png
│  └─ menuCoins Label
├─ home_rider.png
├─ home_start_button.png Button
├─ 右侧透明热区：任务
├─ 右侧透明热区：成就
├─ 右侧透明热区：设置
├─ 底部透明热区：骑手
├─ 底部透明热区：升级
├─ 底部透明热区：订单
└─ 底部透明热区：背包
```

`home_bg.png` 已经包含视觉按钮，因此透明热区只负责点击。

## 首页入口映射

截图底部是：

```text
骑手 / 升级 / 订单 / 背包
```

当前项目已有页面是：

```text
骑手 / 升级 / 任务 / 成就 / 设置
```

建议第一版映射：
- `骑手` -> `M.ShowStaticPage("rider", "menu")`
- `升级` -> `M.ShowStaticPage("upgrades", "menu")`
- `订单` -> 暂时打开 `任务`，或后续新增订单页
- `背包` -> 暂时打开 `升级` 或道具页，后续有背包系统再接真实页面
- `任务` -> `M.ShowStaticPage("tasks", "menu")`
- `成就` -> `M.ShowStaticPage("achievements", "menu")`
- `设置` -> `M.ShowStaticPage("settings", "menu")`

如果不想产生临时映射，建议把底部 `订单 / 背包` 改回现有功能再导出素材。

## 坐标建议

以原型 390x844 为基准。

核心坐标可按截图估算：

```text
等级底板: x=20, y=20, w=170, h=86
金币底板: x=295, y=20, w=116, h=64
骑手图: x=115, y=325, w=220, h=240
开始按钮: x=35, y=700, w=370, h=86
右侧任务: x=350, y=288, w=64, h=64
右侧成就: x=350, y=365, w=64, h=64
右侧设置: x=350, y=442, w=64, h=64
底部骑手: x=38, y=803, w=86, h=86
底部升级: x=132, y=803, w=86, h=86
底部订单: x=226, y=803, w=86, h=86
底部背包: x=320, y=803, w=86, h=86
```

实际 Lua 中需要结合游戏画布尺寸微调。如果首页运行在全屏竖屏，建议先按百分比和 `left="50%" + marginLeft` 定位主按钮和骑手。

## 动效方案

第一版只做 2 个动效：

1. 骑手浮动：

```lua
riderPanel:Animate({
    keyframes = {
        [0] = { translateY = 0 },
        [0.5] = { translateY = -8 },
        [1] = { translateY = 0 },
    },
    duration = 2.0,
    easing = "easeInOut",
    loop = true,
})
```

2. 主按钮呼吸：

```lua
startBtn:Animate({
    keyframes = {
        [0] = { scale = 1.0 },
        [0.5] = { scale = 1.04 },
        [1] = { scale = 1.0 },
    },
    duration = 1.8,
    easing = "easeInOut",
    loop = true,
})
```

隐藏主菜单时调用：

```lua
if riderPanel then riderPanel:StopAnimation() end
if startBtn then startBtn:StopAnimation() end
```

重新显示时再次调用 `Animate()`。

## `scripts/ui.lua` 修改点

主要修改：

1. 新增首页控件引用：

```lua
M.menuRiderPanel = nil
M.menuStartButton = nil
M.menuXpFill = nil
```

2. 替换 `BuildMainMenu()`。

3. `M.ShowMainMenu()` 中继续更新：

```lua
M.lblMenuRiderLevel
M.lblMenuCoins
M.lblMenuBest
```

4. 如果接入 XP 进度条，需要根据成长数据更新 `menuXpFill` 宽度。

5. `HideMainMenu()` 或进入游戏时停止首页动画。

## 代码骨架

示意结构：

```lua
local function MakeTransparentHotspot(left, top, width, height, onClick)
    return UI.Button {
        text = "",
        position = "absolute",
        left = left,
        top = top,
        width = width,
        height = height,
        backgroundColor = {0,0,0,0},
        borderWidth = 0,
        borderRadius = 0,
        onClick = onClick,
    }
end
```

首页根节点：

```lua
local function BuildMainMenu()
    local riderPanel = UI.Panel {
        id = "menuRiderImage",
        position = "absolute",
        left = "50%",
        top = 325,
        marginLeft = -110,
        width = 220,
        height = 240,
        backgroundImage = "Textures/home_rider.png",
        backgroundFit = "contain",
    }

    local startBtn = UI.Button {
        id = "menuStartButton",
        text = "",
        position = "absolute",
        left = "50%",
        bottom = 58,
        marginLeft = -185,
        width = 370,
        height = 86,
        backgroundImage = "Textures/home_start_button.png",
        pressedBackgroundImage = "Textures/home_start_button_pressed.png",
        backgroundFit = "contain",
        borderWidth = 0,
        borderRadius = 0,
        onClick = function()
            if M.onStartGame then
                M.onStartGame()
            end
        end,
    }

    M.menuRiderPanel = riderPanel
    M.menuStartButton = startBtn

    return UI.Panel {
        id = "mainMenuPanel",
        width = "100%",
        height = "100%",
        position = "absolute",
        children = {
            UI.Panel {
                position = "absolute",
                left = 0, top = 0, right = 0, bottom = 0,
                backgroundImage = "Textures/home_bg.png",
                backgroundFit = "cover",
            },
            UI.Panel {
                position = "absolute",
                left = 20, top = 20,
                width = 170, height = 86,
                backgroundImage = "Textures/home_level_badge.png",
                backgroundFit = "contain",
                children = {
                    UI.Label {
                        id = "menuRiderLevel",
                        text = "Lv.1 新手骑手",
                        fontSize = 15,
                        fontWeight = "bold",
                        fontColor = {255,255,255,255},
                        marginLeft = 14,
                        marginTop = 10,
                    },
                    UI.Label {
                        id = "menuBest",
                        text = "最高 0 单 / 连击 0",
                        fontSize = 11,
                        fontWeight = "bold",
                        fontColor = {190,220,230,255},
                        marginLeft = 14,
                        marginTop = 4,
                    },
                },
            },
            UI.Panel {
                position = "absolute",
                right = 20, top = 20,
                width = 116, height = 64,
                backgroundImage = "Textures/home_coin_badge.png",
                backgroundFit = "contain",
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        id = "menuCoins",
                        text = "0",
                        fontSize = 24,
                        fontWeight = "bold",
                        fontColor = {255,255,255,255},
                    },
                },
            },
            riderPanel,
            startBtn,
            MakeTransparentHotspot(350, 288, 64, 64, function() M.ShowStaticPage("tasks", "menu") end),
            MakeTransparentHotspot(350, 365, 64, 64, function() M.ShowStaticPage("achievements", "menu") end),
            MakeTransparentHotspot(350, 442, 64, 64, function() M.ShowStaticPage("settings", "menu") end),
            MakeTransparentHotspot(38, 803, 86, 86, function() M.ShowStaticPage("rider", "menu") end),
            MakeTransparentHotspot(132, 803, 86, 86, function() M.ShowStaticPage("upgrades", "menu") end),
        },
    }
end
```

具体坐标要在实际预览后微调。

## 验收标准

视觉：
- 首页整体与原型截图保持一致。
- 主视觉仍然是道路、标题、骑手和 `接单开冲`。
- 顶部等级、金币没有溢出。
- 底部按钮热区与视觉按钮对齐。

交互：
- 点击 `接单开冲` 进入游戏。
- 点击 `骑手` 进入骑手成长页。
- 点击 `升级` 进入升级页。
- 点击 `任务 / 成就 / 设置` 进入对应页面。
- 返回主菜单后首页动画恢复。

技术：
- 不运行 Lua 或游戏运行时做验证，除非用户改变规则。
- 修改后通过静态审查确认引用 ID、回调和路径无明显错误。
- 图片路径统一使用 `Textures/xxx.png`。
- 不使用 `color`，Label 继续用 `fontColor`。

## 风险与决策点

1. `订单 / 背包` 是否要保留。
   - 保留会产生新入口语义，需要后续页面。
   - 不保留则应在导出素材前改成现有功能。

2. 骑手是否保留白色图标底板。
   - 保留：和当前截图一致，落地风险低。
   - 去掉：更像跑酷角色，但可能改变当前观感。

3. 背景是否包含标题。
   - 包含：还原度最高，Lua 最简单。
   - 不包含：标题可动态替换，但描边投影在 Lua 中较难 100% 还原。

第一版实际落地：
- 使用 `home_bg.png` 烘焙首页完整视觉。
- 擦除背景图中顶部等级、最高单/连击、金币数字，改由 Lua 动态绘制。
- 主按钮视觉保留在背景图中，Lua 使用透明热区处理点击。
- 右侧和底部入口视觉保留在背景图中，Lua 使用透明热区处理点击。
- `订单` 暂时跳转任务页，`背包` 暂时跳转升级页，后续有真实页面后再替换。
