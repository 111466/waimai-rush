# 首页游戏化 UI 实现方案

## 目标

基于 `prototypes/home-ui-redesign/index.html` 和当前截图，在 Lua 中实现接近原型的首页主菜单。

核心目标：
- 首页第一眼像游戏主菜单，而不是应用首页。
- 不再把整个首页烘成一张图。
- 只把 Lua 难以 100% 还原的渐变、描边、阴影、异形底板导出为 PNG。
- 等级、金币、最高单、XP、按钮文字、点击和动效继续由 Lua 渲染。

## 当前依据

原型位置：

```text
prototypes/home-ui-redesign/index.html
```

Lua 入口：

```text
scripts/ui.lua
BuildMainMenu()
```

TapTap 制造 / urhox-libs/UI 已确认：
- `UI.Panel` 支持 `backgroundImage` 和 `backgroundFit`。
- `UI.Button` 支持 `backgroundImage`、`hoverBackgroundImage`、`pressedBackgroundImage`。
- 图片资源放在 `assets/Textures/`，Lua 路径写 `Textures/xxx.png`。
- 透明按钮用 `backgroundColor = {0,0,0,0}` 和 `borderWidth = 0`。
- Label 颜色继续用 `fontColor`。
- children 数组顺序可控制默认层级，后面的节点覆盖前面的节点。
- `Animate()`、`StopAnimation()`、`SetStyle()` 可用于简单动效和样式更新。

## 已落地结构

`BuildMainMenu()` 使用 390x844 设计基准，将像素坐标换算为百分比：

```text
mainMenuPanel
├─ home_scene_bg_static.png 全屏静态背景
├─ home_cloud_one.png / home_cloud_two.png
├─ home_lane_strip.png
├─ home_speed_line_a.png / b / c
├─ home_rider_shadow.png
├─ home_bottom_fade.png
├─ home_level_badge.png + 等级/最高单/XP 动态文字
├─ home_coin_badge_base.png + coinIcon + 金币数字
├─ home_title.png
├─ home_subtitle_badge.png + 副标题文字
├─ home_order_sign.png + 悬赏牌文字
├─ 右侧三个图片入口按钮
├─ home_rider.png
├─ 主按钮 UI.Button，使用图片底图和动态文字
└─ 底部四个图片入口按钮
```

这样背景、云、车道线、速度线、金币图标、骑手、按钮和文字都是独立层，不再依赖旧版整张首页热区图。

## 入口映射

- `接单开冲` -> `M.onStartGame()`
- `任务` -> `M.ShowStaticPage("tasks", "menu")`
- `成就` -> `M.ShowStaticPage("achievements", "menu")`
- `设置` -> `M.ShowStaticPage("settings", "menu")`
- `骑手` -> `M.ShowStaticPage("rider", "menu")`
- `升级` -> `M.ShowStaticPage("upgrades", "menu")`
- `订单` -> 暂时复用 `tasks`
- `背包` -> 暂时复用 `upgrades`

`订单 / 背包` 后续如果有真实系统，只需要替换对应回调。

## 动效

首页显示时调用 `StartHomeAnimations()`，隐藏主菜单、进入游戏、打开静态页、结算页时调用 `StopHomeAnimations()`。

当前动效：
- 云层横向漂移。
- 车道虚线纵向滚动。
- 三条速度线循环闪动和位移。
- 金币图标轻微缩放旋转。
- 骑手上下浮动和轻微旋转。
- 骑手阴影同步缩放和透明度变化。
- 主按钮轻微呼吸。

动效调用都经过防御式检查：

```lua
if node and node.Animate then
    node:Animate(spec)
end
```

因此运行时如果某个节点不支持动画，不会直接中断首页逻辑。

## 动态数据

`M.ShowMainMenu()` 负责刷新：
- `menuRiderLevel`
- `menuCoins`
- `menuBest`
- `menuXpFill`

XP 进度优先使用 `progression.GetHUDData().progress`，避免手写 `xp / xpToNext` 时和等级系统边界不一致。

## 素材来源

素材由脚本生成：

```text
prototypes/home-ui-redesign/export_layers.py
```

主要素材说明见：

```text
docs/home_ui_layer_assets.md
```

如需微调颜色、尺寸、位置，优先改导出脚本后重新导出，避免手工覆盖造成素材来源不清。

## 静态验收

本项目规则要求 Lua 变更只做静态逻辑 review，不运行 Lua、Lua 解释器或 UrhoX/Urho3D runtime。

已检查项：
- 首页图片路径统一为 `Textures/home_*.png`。
- `scripts/ui.lua` 中引用的首页 PNG 均存在于 `assets/Textures/`。
- 主要点击控件使用 `UI.Button`，不是整屏透明热区。
- 主按钮文字已放入按钮自身，避免独立文字层遮挡点击。
- 顶部动态文字继续用 `fontColor`，未使用不可靠的 `color` 别名。

剩余风险：
- `Animate()` 只使用已确认的 `keyframes / duration / easing / loop` 和 transform 属性，静态上可接受，但仍需实际设备预览确认节奏。
- 百分比坐标按 390x844 竖屏比例换算，如果运行环境不是同等比例，视觉会等比铺满但可能需要二次微调。
