# 局内道具系统设计文档

## 目标

局内道具系统用于给配送跑酷增加短期决策和容错空间，但第一版必须保持轻量，不打断玩家驾驶、接单和送达节奏。

第一阶段只实现两个道具：

- 护盾：抵消一次正面碰撞。
- 闹钟：给当前订单增加数秒时间。

导航针和加速餐箱先做接口预留，等小地图强化和速度倍率系统稳定后再实现。

核心体验：

```text
地图刷新道具
-> 玩家驶过道具点自动拾取
-> 玩家最多持有 1 个主动道具
-> 按 E 或点击 HUD 道具按钮使用
-> 道具效果作用到碰撞或订单计时
-> HUD 显示当前持有道具和关键效果状态
```

## 范围

### 第一阶段实现

- 新增 `scripts/powerups.lua`。
- 地图随机刷新道具点。
- 玩家触碰道具点后拾取。
- 同一时间只允许持有 1 个道具。
- 如果已经持有道具，拾取新道具时直接替换。
- 支持键盘 `E` 使用当前道具。
- 支持 HUD 道具按钮使用当前道具。
- 实现护盾。
- 实现闹钟。
- HUD 显示当前道具和护盾状态。
- 主循环在碰撞、订单计时、UI 更新位置接入道具模块。

### 第一阶段不实现

- 复杂背包。
- 多个道具槽。
- 道具升级。
- 道具商店。
- 开局携带道具。
- 任务奖励道具。
- 导航针实际小地图强化。
- 加速餐箱实际速度和收入倍率。
- 存档。

## 当前系统依赖

### 碰撞

当前碰撞在 `main.lua` 中处理：

```lua
local collisionType = obstacles.CheckCollisions(...)
pickup.HandleCollision(collisionType)
if collisionType == "front" then
    GameOver()
elseif collisionType == "side" then
    player.BounceBackFromSideCollision()
end
```

护盾应接在 `pickup.HandleCollision(collisionType)` 之后、`GameOver()` 之前。

原因：

- 易碎单仍然需要先收到碰撞事件，判断订单是否破损。
- 护盾只抵消游戏结束，不应该让其他系统完全不知道发生过碰撞。

第一阶段规则：

```text
front 碰撞 + 有护盾效果
-> 消耗护盾
-> 不 GameOver
-> 可播放护盾破裂提示

side 碰撞
-> 不消耗护盾
-> 继续沿用侧撞反弹
```

### 订单计时

当前订单计时在 `pickup_delivery.lua`：

```lua
M.orderTimeRemaining
M.orderLateSeconds
M.UpdateOrderTimer(dt)
M.GetOrderTimerData()
```

闹钟需要给当前订单增加时间。建议由订单模块提供明确接口：

```lua
pickup.AddOrderTime(seconds)
```

不要让 `powerups.lua` 直接修改 `pickup.orderTimeRemaining`，避免后续订单状态变化时耦合过深。

### 输入

当前输入集中在 `input.lua`，第一阶段新增：

```text
E 使用当前道具
```

建议不要把 `powerups` 直接 require 到 `input.lua`，而是在 `main.lua` 里处理 `E`：

```lua
if input:GetKeyPress(KEY_E) then
    powerups.UseCurrent()
end
```

这样输入模块继续只负责移动、跳跃、下滑和转向。

### HUD

当前 HUD 由 `ui.UpdateHUD(...)` 更新订单计时、收入、连击、速度和路口提示。

道具系统新增：

```lua
powerups.GetHUDData()
```

再扩展 `ui.UpdateHUD(...)` 或新增：

```lua
ui.UpdatePowerupHUD(powerupData)
```

建议第一版使用独立接口 `UpdatePowerupHUD`，减少修改现有 HUD 参数列表的风险。

## 道具定义

### 护盾

| 字段 | 内容 |
| --- | --- |
| id | `shield` |
| 名称 | 护盾 |
| 类型 | 主动道具 |
| 使用条件 | 持有护盾时可以随时使用 |
| 使用效果 | 获得 1 层护盾效果 |
| 消耗时机 | 下一次 `front` 碰撞 |
| 持续时间 | 第一版不限时，直到抵消碰撞 |
| 是否影响订单 | 易碎单仍然会因碰撞失败，第一版护盾只保护玩家不死亡 |

设计说明：

- 护盾不是拾取后自动生效，而是主动使用后生效。
- 如果玩家持有护盾但没有使用，撞上障碍仍然会失败。
- 这样道具按钮有明确意义，也为后续“开局携带道具”和任务奖励留空间。

### 闹钟

| 字段 | 内容 |
| --- | --- |
| id | `clock` |
| 名称 | 闹钟 |
| 类型 | 主动道具 |
| 使用条件 | 当前存在进行中的订单 |
| 使用效果 | 当前订单剩余时间增加 `POWERUP_CLOCK_ADD_SECONDS` |
| 默认加时 | 6 秒 |
| 迟到状态 | 如果已迟到，优先抵消迟到秒数，使剩余时间可以回到正数 |
| 无订单使用 | 不消耗，HUD 提示“暂无订单” |

设计说明：

- 闹钟只影响当前订单，不影响未接订单。
- 如果没有当前订单，使用失败且不消耗道具。
- 如果订单已经迟到 3 秒，使用 +6 秒后应变为剩余 3 秒。

## 后续预留道具

### 导航针

| 字段 | 内容 |
| --- | --- |
| id | `nav_pin` |
| 目标阶段 | 第二阶段 |
| 效果 | 短时间强化小地图路线提示 |
| 依赖 | 小地图路线渲染、路线重规划提示 |

预留接口：

```lua
powerups.IsNavigationBoostActive()
powerups.GetNavigationBoostRemaining()
```

`ui.UpdateMinimap(...)` 后续可以根据这个状态提高路线亮度、加粗路线、显示下一路口方向。

### 加速餐箱

| 字段 | 内容 |
| --- | --- |
| id | `boost_box` |
| 目标阶段 | 第二阶段 |
| 效果 | 短时间提高速度和收入倍率 |
| 依赖 | 速度倍率、收入倍率、限时效果管理 |

预留接口：

```lua
powerups.GetSpeedMultiplier()
powerups.GetIncomeMultiplier()
```

第一阶段先返回 `1.0`。

## 数据结构

### 道具配置

建议在 `config.lua` 中新增：

```lua
POWERUP_POOL_SIZE = 8,
POWERUP_SPAWN_AHEAD_MIN = 35.0,
POWERUP_SPAWN_AHEAD_MAX = 95.0,
POWERUP_SPAWN_INTERVAL_MIN = 80.0,
POWERUP_SPAWN_INTERVAL_MAX = 130.0,
POWERUP_EDGE_START_BUFFER = 18.0,
POWERUP_EDGE_END_BUFFER = 18.0,
POWERUP_PICKUP_LONGITUDINAL_THRESHOLD = 2.2,
POWERUP_PICKUP_LATERAL_THRESHOLD = 1.15,
POWERUP_OBSTACLE_CLEARANCE = 10.0,
POWERUP_CLOCK_ADD_SECONDS = 6.0,
POWERUP_TYPES = {
    shield = {
        weight = 55,
        label = "盾",
        name = "护盾",
        color = "#4DA3FF",
    },
    clock = {
        weight = 45,
        label = "钟",
        name = "闹钟",
        color = "#FFD34D",
    },
},
```

### 道具实例

```lua
{
    id = 1,
    typeId = "shield",
    label = "盾",
    name = "护盾",
    color = "#4DA3FF",

    edgeId = 12,
    edgeDist = 42.0,
    lane = 2,

    node = nil,
    shadowNode = nil,
    active = true,
}
```

### 模块状态

`powerups.lua` 建议维护：

```lua
M.activePowerups = {}
M.heldPowerup = nil
M.shieldCharges = 0
M.nextPowerupId = 1
M.nextSpawnDistance = 0.0
```

第一版 `shieldCharges` 最大为 1。

## 模块接口

建议新增 `scripts/powerups.lua`：

```lua
powerups.Init(scene)
powerups.Reset()

powerups.Spawn()
powerups.CheckPickup()
powerups.Recycle()
powerups.Update(dt)

powerups.UseCurrent()
powerups.SetUseContext(context)

powerups.HasShield()
powerups.ConsumeShield()

powerups.IsNearPowerupPoint(edgeId, edgeDist, lane)
powerups.GetHUDData()
powerups.GetMinimapData()
```

### UseCurrent 上下文

闹钟需要调用订单模块。为避免 `powerups.lua` 强依赖太多模块，可以在初始化后设置上下文：

```lua
powerups.SetUseContext({
    addOrderTime = pickup.AddOrderTime,
    hasActiveOrder = pickup.HasActiveOrder,
    showHint = ui.ShowPowerupHint,
})
```

如果项目更偏向直接 require，也可以在 `powerups.lua` 内部 require `pickup_delivery`，但推荐先用上下文接口，后续任务系统监听道具事件时更清晰。

## 生成规则

### 生成位置

第一版道具点只生成在玩家当前 edge 的前方，降低路线可达性复杂度。

规则：

1. 不在路口内生成。
2. 不靠近 edge 起点和终点。
3. 不与订单取餐点、送达点过近。
4. 不与障碍物生成点过近。
5. 每次只保持 0 到 1 个可拾取道具，避免地图信息过载。

建议第一版不要把道具放到小地图上。主视野能看到即可，HUD 只显示持有状态。

### 刷新节奏

```text
玩家行驶距离达到 nextSpawnDistance
-> 尝试在前方生成 1 个道具
-> 生成成功后设置下一次刷新距离
-> 玩家拾取或错过后，道具回收
```

初始刷新距离建议：

```lua
nextSpawnDistance = player.distanceTraveled + 60.0
```

后续刷新间隔：

```lua
80m - 130m
```

### 错过回收

如果道具点在当前 edge 且落后玩家超过一定距离：

```lua
POWERUP_RECYCLE_BEHIND_DISTANCE = 30.0
```

则隐藏并回收。

## 拾取与持有规则

### 拾取判断

与订单取餐点类似，使用扫过判断，避免高速时穿过：

```text
同一 edge
玩家本帧路径扫过 edgeDist
玩家横向位置接近道具 lane
```

拾取后：

```text
heldPowerup = powerup.typeId
隐藏地图道具节点
从 activePowerups 移除
更新 HUD
```

如果已有道具：

```text
直接替换 heldPowerup
显示“已替换为 XX”
```

第一版不做丢弃、不做选择弹窗。

## 使用规则

### 护盾使用

```lua
function UseShield()
    M.heldPowerup = nil
    M.shieldCharges = 1
    return true
end
```

主循环碰撞处理：

```lua
pickup.HandleCollision(collisionType)

if collisionType == "front" then
    if powerups.ConsumeShield() then
        -- 不 GameOver
    else
        GameOver()
        return
    end
elseif collisionType == "side" then
    player.BounceBackFromSideCollision()
end
```

护盾消费：

```lua
function powerups.ConsumeShield()
    if M.shieldCharges <= 0 then return false end
    M.shieldCharges = M.shieldCharges - 1
    return true
end
```

### 闹钟使用

```lua
function UseClock()
    if not context.hasActiveOrder() then
        return false
    end

    context.addOrderTime(CONFIG.POWERUP_CLOCK_ADD_SECONDS)
    M.heldPowerup = nil
    return true
end
```

订单模块新增：

```lua
function pickup.HasActiveOrder()
    return M.activeOrder ~= nil and M.orderTimerActive
end

function pickup.AddOrderTime(seconds)
    if not M.orderTimerActive then return false end
    M.orderTimeRemaining = M.orderTimeRemaining + seconds
    M.orderLateSeconds = math.max(0.0, -M.orderTimeRemaining)
    return true
end
```

## 主循环接入顺序

建议 `main.lua` 顺序：

```text
输入
E 使用当前道具
速度/移动
路径推进
玩家位置更新
订单刷新与取餐检测
道具刷新与拾取检测
障碍物生成
碰撞检测
订单碰撞通知
护盾判断
障碍物回收
道具回收
送达检测
导航更新
订单计时
道具状态更新
UI 更新
```

关键点：

- 道具生成应早于障碍物生成，这样障碍物可以避让道具点。
- 护盾判断必须在 `GameOver()` 之前。
- 闹钟使用发生在输入阶段即可，效果会在同一帧订单计时前生效。

## 与障碍物的避让关系

第一阶段建议新增：

```lua
powerups.IsNearPowerupPoint(edgeId, edgeDist, lane)
```

然后在 `obstacles.lua` 生成前判断：

```lua
if pickup.IsNearOrderPoint(edge.id, edgeDist, lane) then return false end
if powerups.IsNearPowerupPoint(edge.id, edgeDist, lane) then return false end
```

这样可以避免道具和障碍物贴在一起，让玩家误判。

注意循环依赖：

- 当前 `obstacles.lua` 已 require `pickup_delivery`。
- 如果再 require `powerups`，通常可以接受。
- 但不要让 `powerups.lua` require `obstacles.lua`。

## 视觉与 UI

### 地图道具点

第一版可以用简单几何体：

| 道具 | 视觉建议 |
| --- | --- |
| 护盾 | 蓝色圆柱底座 + 蓝色球体 |
| 闹钟 | 黄色圆柱底座 + 黄色方块或球体 |

表现规则：

- 悬浮在车道上方。
- 轻微上下浮动。
- 有接触阴影。
- 与取餐点颜色明显区分。

### HUD

HUD 新增一个小面板，建议放在右侧或顶部靠右、小地图下方，避免遮挡道路：

```text
[E] 护盾
护盾已激活
[E] 闹钟
无道具
```

第一版 HUD 状态：

```lua
{
    held = true,
    id = "shield",
    name = "护盾",
    label = "盾",
    readyText = "E 护盾",
    shieldActive = false,
}
```

护盾已使用但未消耗：

```lua
{
    held = false,
    shieldActive = true,
    readyText = "护盾中",
}
```

无道具：

```lua
{
    held = false,
    shieldActive = false,
    readyText = "无道具",
}
```

### 提示文案

第一版只需要短提示，不做弹窗：

```text
获得护盾
获得闹钟
护盾已启动
护盾抵消碰撞
当前没有订单
订单时间 +6s
```

提示复用现有 HUD 中间提示区域，或新增 `ui.ShowPowerupHint(text, duration)`。

## 事件预留

任务系统后续会监听道具事件，所以第一版建议在 `powerups.lua` 内部预留事件回调：

```lua
powerups.SetEventSink({
    onPowerupPicked = function(powerupType) end,
    onPowerupUsed = function(powerupType) end,
    onShieldConsumed = function() end,
})
```

第一阶段可以先不接任务系统，但接口先留好，避免之后到处补回调。

## 边界情况

### 没有当前订单时使用闹钟

- 不消耗道具。
- 显示“当前没有订单”。

### 已经迟到时使用闹钟

- 直接增加 `orderTimeRemaining`。
- 重新计算 `orderLateSeconds`。
- 如果加时后 `orderTimeRemaining >= 0`，HUD 从迟到状态恢复到倒计时状态。

### 持有护盾又拾取护盾

- 替换为护盾，效果没有变化。
- 不自动增加护盾层数。

### 护盾已激活又使用护盾

- 第一版不允许，因为激活后 `heldPowerup` 已为空。
- 后续如果支持多层护盾，再扩展。

### 护盾与易碎单

第一版明确：

```text
护盾抵消玩家死亡，不抵消易碎单破损。
```

也就是说，玩家撞到正面障碍且有护盾：

- 易碎单失败。
- 护盾消耗。
- 玩家继续跑。

后续如果想降低挫败，可以改为“护盾同时保护易碎单”，但第一版先保持系统语义清晰。

### 侧撞

- 侧撞不消耗护盾。
- 继续调用 `player.BounceBackFromSideCollision()`。

### 暂停

- 暂停时不生成道具。
- 暂停时不更新道具动画和限时效果。
- 暂停时 HUD 保持当前状态。

### 重开局

`powerups.Reset()` 需要：

- 隐藏所有地图道具。
- 清空 `activePowerups`。
- 清空 `heldPowerup`。
- 清空 `shieldCharges`。
- 重置 `nextSpawnDistance`。

## 实现步骤

### 第 1 步：配置和模块骨架

- 在 `config.lua` 增加道具配置。
- 新增 `scripts/powerups.lua`。
- 实现 `Init`、`Reset`、`GetHUDData`。

验收：

```text
游戏能启动。
重开局不报错。
HUD 能拿到“无道具”状态。
```

### 第 2 步：地图道具点

- 创建道具节点池。
- 实现道具点显示、隐藏、浮动动画。
- 实现 `Spawn` 和 `Recycle`。

验收：

```text
玩家前方能偶尔看到道具点。
错过后道具能回收。
重开局后旧道具不会残留。
```

### 第 3 步：拾取和持有

- 实现 `CheckPickup`。
- 实现持有 1 个道具。
- 已持有时拾取新道具直接替换。

验收：

```text
驶过道具点能获得道具。
HUD 显示当前道具。
拾取新道具会替换旧道具。
```

### 第 4 步：护盾

- 实现 `UseCurrent` 中的护盾使用。
- 实现 `HasShield` 和 `ConsumeShield`。
- 在 `main.lua` 正面碰撞 GameOver 前接入护盾判断。

验收：

```text
持有护盾但未使用时，正面碰撞仍失败。
使用护盾后，下一次正面碰撞不 GameOver。
护盾抵消一次后消失。
侧撞不消耗护盾。
```

### 第 5 步：闹钟

- 在 `pickup_delivery.lua` 增加 `HasActiveOrder` 和 `AddOrderTime`。
- 实现 `UseCurrent` 中的闹钟使用。
- 无订单时使用不消耗。

验收：

```text
有当前订单时使用闹钟，订单剩余时间增加。
迟到后使用闹钟，迟到秒数能被抵消。
无订单时使用闹钟不会消耗。
```

### 第 6 步：HUD 和提示

- 新增 HUD 道具面板。
- 支持点击道具按钮使用当前道具。
- 显示拾取、使用、失败和护盾抵消提示。

验收：

```text
HUD 能显示无道具、持有道具、护盾激活。
点击 HUD 道具按钮等价于按 E。
提示不遮挡核心驾驶区域。
```

### 第 7 步：障碍物避让

- 实现 `powerups.IsNearPowerupPoint`。
- `obstacles.lua` 生成障碍物时避开道具点。

验收：

```text
障碍物不会贴着道具生成。
道具点不会被障碍物完全遮挡。
```

## 验收清单

第一阶段完成后应满足：

- 地图上能刷新护盾和闹钟道具。
- 玩家驶过道具点能自动拾取。
- 玩家同一时间最多持有 1 个道具。
- 拾取新道具会替换旧道具。
- 按 `E` 能使用当前道具。
- HUD 道具按钮能使用当前道具。
- 护盾使用后能抵消一次正面碰撞。
- 护盾不抵消侧撞。
- 护盾不阻止易碎单因碰撞失败。
- 闹钟能给当前订单加时。
- 无订单时使用闹钟不会消耗。
- 迟到时使用闹钟能正确修正迟到秒数。
- 暂停时道具逻辑不继续推进。
- 重开局后地图道具、持有道具和护盾状态全部清空。
- 障碍物不会与道具点重叠生成。

## 后续扩展顺序

建议后续顺序：

1. 第一阶段：护盾、闹钟。
2. 任务系统接入道具事件：拾取、使用、护盾抵消。
3. 导航针：强化小地图路线和下一路口提示。
4. 加速餐箱：接入速度倍率和收入倍率。
5. 局外升级：开局携带道具、提高道具刷新概率、增强道具效果。
6. 存档：保存局外升级和长期道具相关统计。

