# 首页分层图片清单

## 目标

这批素材用于替代“整张首页烘成一张图”的方案。原则是：

- Lua 难以 100% 还原的渐变、描边、阴影、异形底板导出成 PNG。
- 等级、金币、任务奖励、按钮文案、入口文字等动态内容继续由 Lua 渲染。
- 当前素材已经接入 `scripts/ui.lua` 的 `BuildMainMenu()`，Lua 负责动态文字、点击和动效。

## 已导出素材

| 文件 | 尺寸 | 内容 | 动态文字 |
| --- | ---: | --- | --- |
| `assets/Textures/home_scene_bg_static.png` | 390x844 | 静态背景，不含云、车道虚线、速度线、骑手阴影、底部渐变 | 不包含 |
| `assets/Textures/home_cloud_one.png` | 104x48 | 左上云，供 `cloudDrift` 动效使用 | 不包含 |
| `assets/Textures/home_cloud_two.png` | 122x58 | 太阳前方云，供 `cloudDrift` 动效使用 | 不包含 |
| `assets/Textures/home_lane_strip.png` | 12x530 | 中央车道虚线，供 `laneRun` 动效使用 | 不包含 |
| `assets/Textures/home_lane_strip_1.png` ~ `home_lane_strip_5.png` | 12x530 | 中央车道虚线相位帧，用于 Lua 中交替淡入淡出，避免整张贴图位移回跳 | 不包含 |
| `assets/Textures/home_speed_line_a.png` | 96x23 | 左侧速度线 A，供 `streak` 动效使用 | 不包含 |
| `assets/Textures/home_speed_line_b.png` | 96x23 | 右侧速度线 B，供 `streak` 动效使用 | 不包含 |
| `assets/Textures/home_speed_line_c.png` | 66x23 | 左下速度线 C，供 `streak` 动效使用 | 不包含 |
| `assets/Textures/home_rider_shadow.png` | 148x44 | 骑手脚下阴影，供 `shadowBeat` 动效使用 | 不包含 |
| `assets/Textures/home_bottom_fade.png` | 390x222 | 底部浅色渐变层，应盖在车道线和背景之上 | 不包含 |
| `assets/Textures/home_title.png` | 250x138 | 标题“外卖冲冲冲”的描边和投影效果 | 固定标题，允许包含 |
| `assets/Textures/home_subtitle_badge.png` | 168x34 | 副标题胶囊底板 | 不包含 |
| `assets/Textures/home_level_badge.png` | 166x72 | 左上等级 HUD 底板 | 不包含 |
| `assets/Textures/home_coin_badge_base.png` | 114x58 | 右上金币 HUD 底板，不含金币图标，供金币图标独立动效使用 | 不包含 |
| `assets/Textures/home_coin_icon.png` | 26x26 | 金币图标，供 `coinPop` 动效使用 | 不包含 |
| `assets/Textures/home_xp_track.png` | 132x8 | XP 灰色底槽 | 不包含 |
| `assets/Textures/home_xp_fill.png` | 132x8 | XP 彩色填充条 | 不包含 |
| `assets/Textures/home_order_sign.png` | 159x146 | 左侧悬赏牌底图 | 不包含奖励文字 |
| `assets/Textures/home_rider.png` | 188x188 | 骑手主体图，保留白色圆角底板 | 不包含动态文字 |
| `assets/Textures/home_start_button_base.png` | 346x84 | 主按钮普通态底图 | 不包含“接单开冲” |
| `assets/Textures/home_start_button_base_pressed.png` | 346x84 | 主按钮按下态底图 | 不包含“接单开冲” |
| `assets/Textures/home_round_blue.png` | 64x66 | 右侧蓝色圆按钮底图 | 不包含“任务” |
| `assets/Textures/home_round_green.png` | 64x66 | 右侧绿色圆按钮底图 | 不包含“成就” |
| `assets/Textures/home_round_red.png` | 64x66 | 右侧红色圆按钮底图 | 不包含“设置” |
| `assets/Textures/home_dock_button.png` | 80x78 | 底部入口按钮底图 | 不包含图标文字 |
| `assets/Textures/home_dock_icon_orange.png` | 30x30 | 底部橙色圆图标底 | 不包含“骑” |
| `assets/Textures/home_dock_icon_blue.png` | 30x30 | 底部蓝色圆图标底 | 不包含“升” |
| `assets/Textures/home_dock_icon_green.png` | 30x30 | 底部绿色圆图标底 | 不包含“单” |
| `assets/Textures/home_dock_icon_gray.png` | 30x30 | 底部灰色圆图标底 | 不包含“包” |
| `assets/Textures/home_icon_rider.png` | 30x30 | 底部“骑手”白色 SVG 图标，来自原型 HTML | 不包含 |
| `assets/Textures/home_icon_upgrade.png` | 30x30 | 底部“升级”白色 SVG 图标，来自原型 HTML | 不包含 |
| `assets/Textures/home_icon_order.png` | 30x30 | 底部“订单”白色 SVG 图标，来自原型 HTML | 不包含 |
| `assets/Textures/home_icon_bag.png` | 30x30 | 底部“背包”白色 SVG 图标，来自原型 HTML | 不包含 |
| `assets/Textures/home_icon_task.png` | 30x30 | 右侧“任务”白色 SVG 图标，来自原型 HTML | 不包含 |
| `assets/Textures/home_icon_achievement.png` | 30x30 | 右侧“成就”白色 SVG 图标，来自原型 HTML | 不包含 |
| `assets/Textures/home_icon_settings.png` | 30x30 | 右侧“设置”白色 SVG 图标，来自原型 HTML | 不包含 |

## 动态层级顺序

100% 接近 HTML 原型时，首页背景建议按这个顺序渲染：

1. `home_scene_bg_static.png`
2. `home_cloud_one.png`、`home_cloud_two.png`
3. `home_lane_strip.png` 及 `home_lane_strip_1.png` ~ `home_lane_strip_5.png`
4. `home_speed_line_a.png`、`home_speed_line_b.png`、`home_speed_line_c.png`
5. `home_rider_shadow.png`
6. `home_bottom_fade.png`
7. 顶部 HUD、标题、悬赏牌、右侧按钮、骑手、主按钮、底部入口

说明：`home_bottom_fade.png` 必须在车道线之后渲染，才能保持原型里底部逐渐泛白的效果。

## 清理说明

- 旧整图、分层预览图、对比检查图、旧主按钮整图已删除，避免运行时资源目录混入调试产物。
- 当前 `assets/Textures/` 保留的是 Lua 首页和系统页会直接引用的 PNG。
- 如需重新生成对比检查图，可运行 `prototypes/home-ui-redesign/export_layers.py` 临时导出，确认后不要把检查图作为运行时资源保留。

## Lua 叠字建议

后续实现时，建议 Lua 负责叠加这些文字：

- `Lv.1 新手骑手`
- `最高 0 单 / 连击 0`
- 金币数字 `0`
- 副标题 `接单上路，准时送达`
- 悬赏牌 `+¥30`、`准时送达 2 单`
- 右侧入口 `任务 / 成就 / 设置`
- 主按钮 `接单开冲`
- 底部入口 `骑手 / 升级 / 订单 / 背包`

## 生成方式

素材由脚本生成：

```text
prototypes/home-ui-redesign/export_layers.py
```

如需微调颜色、尺寸、位置，优先改这个脚本后重新导出，避免手工覆盖造成素材来源不清。
