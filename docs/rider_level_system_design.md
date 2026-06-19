# 骑手等级系统设计文档

## 目标

骑手等级系统是多订单系统稳定后的第一层长期成长。目标是让玩家完成订单后获得经验，并通过升级逐步解锁更丰富的订单选择空间。

第一版只解决“经验产出、等级提升、订单数量、订单类型解锁、高价值订单概率”这 5 件事，不提前实现局内道具、任务、成就、局外升级和真实存档。

核心体验：

```text
完成订单
-> 根据订单类型、准时状态和连击获得经验
-> 经验达到阈值后提升骑手等级
-> 等级影响地图同时刷新订单数量
-> 等级解锁新的订单类型
-> 等级提高高价值订单出现概率
```

## 范围

### 本阶段实现

- 新增骑手等级和经验数据。
- 完成订单后产出经验。
- 准时送达和连击提供额外经验。
- 经验达到阈值后自动升级。
- 等级决定地图同时存在的可接订单数量。
- 等级决定可刷新的订单类型。
- 等级影响高价值订单刷新概率。
- HUD 显示骑手等级和经验进度。
- 预留任务、成就、局外升级和存档接口。

### 本阶段不实现

- 局内道具解锁和生成。
- 局内任务经验奖励。
- 长期成就经验奖励。
- 局外升级项上限。
- 本地存档。
- 复杂称号、声望、外观系统。
- 单局结束后的等级结算动画。

这些内容等对应系统实现时再接入，等级系统只暴露稳定接口。

## 设计原则

1. 等级系统只管理成长数据，不直接生成订单、不直接修改 UI 节点、不直接处理碰撞。
2. 订单系统只向等级系统报告订单结果，并从等级系统读取刷单参数。
3. 第一版等级数据保存在内存中，重开局不重置，刷新页面或重启运行环境后可以丢失。
4. 等级带来选择空间和收益倾向，不直接降低游戏操作难度。
5. 解锁节奏要保守，避免玩家刚开始就被过多订单类型和高价值订单压住信息负担。

## 当前系统接入点

当前多订单系统已经具备以下基础：

- `pickup_delivery.lua` 中有 `availableOrders` 和 `activeOrder`。
- 订单类型已包含 `normal`、`rush`、`long`、`nearby`、`fragile`。
- 完成订单时已经计算收入、迟到和连击。
- `config.lua` 中已有 `ORDER_AVAILABLE_COUNT_DEFAULT` 和 `ORDER_AVAILABLE_COUNT_MAX`。
- `ui.lua` 中已有等级展示的临时文案，需要改为真实数据。

等级系统需要接管或影响：

```text
订单完成 -> 获得 XP
订单刷新数量 -> 由等级返回
订单类型池 -> 由等级过滤
订单类型权重 -> 由等级修正
HUD 等级文本 -> 由等级系统提供
```

## 等级配置

### 等级上限

第一版等级上限设为 Lv.10。原因：

- 刚好覆盖当前设计中的 2/3/4/5 个订单数量节点。
- 可以容纳 5 种订单类型的逐步解锁。
- 数值规模可控，便于测试。

后续可以把等级上限扩展到 Lv.20 或 Lv.30，但第一版不需要。

### 等级经验表

建议使用显式表，而不是公式。这样方便手调节奏。

```lua
RIDER_LEVELS = {
    { level = 1, xpToNext = 60,  title = "新手骑手" },
    { level = 2, xpToNext = 90,  title = "街区熟手" },
    { level = 3, xpToNext = 130, title = "城市快骑" },
    { level = 4, xpToNext = 180, title = "准时达人" },
    { level = 5, xpToNext = 240, title = "远单能手" },
    { level = 6, xpToNext = 320, title = "金牌骑手" },
    { level = 7, xpToNext = 420, title = "路线专家" },
    { level = 8, xpToNext = 540, title = "稳送先锋" },
    { level = 9, xpToNext = 680, title = "派单王牌" },
    { level = 10, xpToNext = 0, title = "冲刺之星" },
}
```

字段含义：

| 字段 | 含义 |
| --- | --- |
| `level` | 骑手等级 |
| `xpToNext` | 从当前等级升到下一级需要的经验 |
| `title` | HUD 或后续结算展示用称号 |

经验采用“当前等级经验槽”结构：

```lua
level = 3
xp = 42
xpToNext = 130
```

到达阈值后扣除阈值并升级：

```text
Lv.3 XP 128/130，获得 12 XP
-> 升到 Lv.4
-> 剩余 XP 10/180
```

这样一次高额奖励可以连续升级。

## 解锁规则

### 订单数量解锁

等级决定可接订单数量：

| 等级 | 可接订单数量 |
| --- | --- |
| Lv.1-Lv.2 | 2 |
| Lv.3-Lv.5 | 3 |
| Lv.6-Lv.9 | 4 |
| Lv.10 | 5 |

对应接口：

```lua
progression.GetMaxAvailableOrders()
```

多订单系统中：

```lua
local targetCount = progression.GetMaxAvailableOrders()
```

替换当前固定读取：

```lua
CONFIG.ORDER_AVAILABLE_COUNT_DEFAULT
```

### 订单类型解锁

订单类型随等级逐步开放：

| 等级 | 解锁订单类型 | 说明 |
| --- | --- | --- |
| Lv.1 | 普通单、顺路单 | 标准和短距离订单，帮助玩家建立路线选择习惯 |
| Lv.2 | 急送单 | 引入时间压力和高奖励选择 |
| Lv.5 | 远距离单 | 引入更复杂路线和更高收益 |
| Lv.8 | 易碎单 | 引入碰撞失败风险 |

对应接口：

```lua
progression.IsOrderTypeUnlocked(typeId)
progression.GetUnlockedOrderTypes()
```

第一版推荐默认类型池：

```text
Lv.1: normal, nearby
Lv.2: normal, nearby, rush
Lv.5: normal, nearby, rush, long
Lv.8: normal, nearby, rush, long, fragile
```

### 高价值订单概率

高价值订单包括：

```text
rush
long
fragile
```

等级不直接强制刷新高价值订单，而是通过权重修正提高概率。

建议权重修正：

| 等级段 | 高价值权重加成 |
| --- | --- |
| Lv.1-Lv.2 | +0% |
| Lv.3-Lv.4 | +10% |
| Lv.5-Lv.7 | +20% |
| Lv.8-Lv.9 | +30% |
| Lv.10 | +40% |

对应接口：

```lua
progression.GetOrderWeightMultiplier(typeId)
```

订单系统选择类型时：

```lua
effectiveWeight = baseWeight * progression.GetOrderWeightMultiplier(orderType.id)
```

如果订单类型未解锁，权重视为 0。

## 经验产出

### 基础经验

经验主要来自完成订单。订单类型越难，基础经验越高。

| 订单类型 | 基础 XP |
| --- | --- |
| 普通单 | 8 |
| 顺路单 | 6 |
| 急送单 | 12 |
| 远距离单 | 14 |
| 易碎单 | 12 |

这些值可以放在订单类型配置里：

```lua
xp = 8
```

如果订单配置没有 `xp`，则使用默认值：

```lua
PROGRESSION_DEFAULT_ORDER_XP = 8
```

### 准时奖励

准时送达提供额外 XP：

```text
准时奖励 XP = max(1, floor(基础 XP * 0.25))
```

示例：

```text
普通单 8 XP，准时 +2 XP
急送单 12 XP，准时 +3 XP
```

迟到送达仍然获得基础 XP，但没有准时奖励。

原因：

- 迟到仍代表玩家完成了一次配送流程。
- 不给准时奖励即可表达效率差异。
- 避免迟到订单完全没有成长反馈。

### 连击奖励

连击提供少量额外 XP，避免经验膨胀：

```text
连击奖励 XP = min(5, floor(comboCount / 2))
```

示例：

| 连击数 | 额外 XP |
| --- | --- |
| x1 | 0 |
| x2-x3 | 1 |
| x4-x5 | 2 |
| x6-x7 | 3 |
| x8-x9 | 4 |
| x10+ | 5 |

注意：这里使用“送达后的连击数”。迟到会清空连击，因此迟到没有连击 XP。

### 失败订单

第一版订单失败不奖励 XP。

失败包括：

- 错过送达点。
- 易碎单碰撞破损。
- 后续取消订单。

如果后续希望降低挫败感，可以增加“失败保底 XP”，但第一版先不做。

## 经验结算流程

订单完成时，订单系统计算收入和连击后，再通知等级系统。

建议流程：

```text
CheckDelivery()
-> 判断是否命中送达点
-> 计算迟到状态
-> 计算收入
-> 更新 comboCount
-> progression.OnOrderDelivered(order, result)
-> 增加总收入
-> FinishActiveOrder()
```

`result` 建议结构：

```lua
{
    onTime = true,
    lateSeconds = 0.0,
    comboCount = 3,
    reward = 18,
}
```

等级系统返回：

```lua
{
    xpGained = 15,
    leveledUp = true,
    oldLevel = 2,
    newLevel = 3,
    unlocks = {
        { type = "order_count", value = 3 },
    },
}
```

第一版可以只打印升级日志并更新 HUD，后续再做升级提示动画。

## 数据结构

建议新增 `scripts/progression.lua`。

模块状态：

```lua
local M = {}

M.level = 1
M.xp = 0
M.totalXp = 0
M.runXp = 0
M.lastLevelUp = nil

return M
```

字段说明：

| 字段 | 含义 |
| --- | --- |
| `level` | 当前骑手等级 |
| `xp` | 当前等级经验槽 |
| `totalXp` | 历史累计经验，供后续成就或统计使用 |
| `runXp` | 当前局获得经验，供结算和调试使用 |
| `lastLevelUp` | 最近一次升级结果，供 HUD 短提示使用 |

### 配置建议

在 `config.lua` 增加：

```lua
RIDER_LEVEL_MAX = 10,
RIDER_LEVELS = {
    { level = 1, xpToNext = 60,  title = "新手骑手" },
    { level = 2, xpToNext = 90,  title = "街区熟手" },
    { level = 3, xpToNext = 130, title = "城市快骑" },
    { level = 4, xpToNext = 180, title = "准时达人" },
    { level = 5, xpToNext = 240, title = "远单能手" },
    { level = 6, xpToNext = 320, title = "金牌骑手" },
    { level = 7, xpToNext = 420, title = "路线专家" },
    { level = 8, xpToNext = 540, title = "稳送先锋" },
    { level = 9, xpToNext = 680, title = "派单王牌" },
    { level = 10, xpToNext = 0, title = "冲刺之星" },
},
RIDER_ORDER_COUNT_UNLOCKS = {
    { level = 1, count = 2 },
    { level = 3, count = 3 },
    { level = 6, count = 4 },
    { level = 10, count = 5 },
},
RIDER_ORDER_TYPE_UNLOCKS = {
    normal = 1,
    nearby = 1,
    rush = 2,
    long = 5,
    fragile = 8,
},
RIDER_HIGH_VALUE_WEIGHT_BONUS = {
    { level = 1, bonus = 0.00 },
    { level = 3, bonus = 0.10 },
    { level = 5, bonus = 0.20 },
    { level = 8, bonus = 0.30 },
    { level = 10, bonus = 0.40 },
},
RIDER_HIGH_VALUE_ORDER_TYPES = {
    rush = true,
    long = true,
    fragile = true,
},
PROGRESSION_DEFAULT_ORDER_XP = 8,
PROGRESSION_ON_TIME_XP_RATE = 0.25,
PROGRESSION_COMBO_XP_STEP = 2,
PROGRESSION_COMBO_XP_MAX = 5,
```

## 接口设计

### 初始化与重置

```lua
progression.ResetAll()
progression.ResetRun()
```

`ResetAll()`：

- 重置等级到 Lv.1。
- 清空经验。
- 后续接存档时只在清档或新账号时调用。

`ResetRun()`：

- 清空当前局经验 `runXp`。
- 清空最近升级提示 `lastLevelUp`。
- 不重置等级和当前经验。
- 每次重新开始一局时调用。

### 经验接口

```lua
progression.AddXP(amount, source)
progression.OnOrderDelivered(order, result)
progression.OnOrderFailed(order, reason)
```

`AddXP(amount, source)`：

- 所有经验入口最终都走这里。
- 支持连续升级。
- 返回升级结果。

`OnOrderDelivered(order, result)`：

- 从订单和送达结果计算 XP。
- 内部调用 `AddXP()`。

`OnOrderFailed(order, reason)`：

- 第一版不加经验。
- 保留接口给后续任务和失败保底。

### 等级读取接口

```lua
progression.GetRiderLevel()
progression.GetCurrentXP()
progression.GetXPToNext()
progression.GetTitle()
progression.GetHUDData()
```

`GetHUDData()` 返回：

```lua
{
    level = 3,
    title = "城市快骑",
    xp = 42,
    xpToNext = 130,
    progress = 0.32,
    maxLevel = false,
    lastLevelUp = nil,
}
```

满级时：

```lua
{
    level = 10,
    title = "冲刺之星",
    xp = 0,
    xpToNext = 0,
    progress = 1.0,
    maxLevel = true,
}
```

### 订单系统读取接口

```lua
progression.GetMaxAvailableOrders()
progression.IsOrderTypeUnlocked(typeId)
progression.GetUnlockedOrderTypes()
progression.GetOrderWeightMultiplier(typeId)
progression.GetOrderTypeUnlockLevel(typeId)
```

`GetMaxAvailableOrders()`：

- 返回当前等级允许的可接订单数量。
- 结果需要被 `CONFIG.ORDER_AVAILABLE_COUNT_MAX` 限制，避免超过节点池。

`GetOrderWeightMultiplier(typeId)`：

- 未解锁返回 `0`。
- 普通订单返回 `1.0`。
- 高价值订单根据等级返回 `1.0 + bonus`。

示例：

```text
Lv.5，rush 权重倍率 1.2
Lv.5，fragile 未解锁，权重倍率 0
```

## 模块关系

### 与多订单系统

多订单系统依赖等级系统提供 3 个能力：

```text
可刷几个订单
哪些订单类型可刷
每种订单类型当前权重是多少
```

订单模块接入点：

```lua
local progression = require("progression")
```

替换订单数量：

```lua
local function GetTargetOrderCount()
    return progression.GetMaxAvailableOrders()
end
```

调整订单类型选择：

```lua
local multiplier = progression.GetOrderWeightMultiplier(orderType.id)
local effectiveWeight = (orderType.weight or 1) * multiplier
```

完成订单后：

```lua
progression.OnOrderDelivered(order, {
    onTime = M.orderLateSeconds <= 0.0,
    lateSeconds = M.orderLateSeconds,
    comboCount = M.comboCount,
    reward = reward,
})
```

失败订单后：

```lua
progression.OnOrderFailed(M.activeOrder, reason)
```

### 与 HUD

UI 不直接计算经验进度，只展示 `progression.GetHUDData()`。

建议 `ui.UpdateHUD()` 增加一个可选参数：

```lua
ui.UpdateHUD(orderTimerData, totalIncome, comboCount, currentSpeed, intersectionActive, turnChoice, hasTurnChoice, availableTurns, navData, progressionData)
```

第一版 HUD 显示：

```text
Lv.3 城市快骑
XP 42/130
```

如果 UI 空间紧张，可以先显示：

```text
Lv.3 XP 42/130
```

升级提示第一版可用短文本：

```text
升级到 Lv.4
```

### 与任务系统

任务系统后续可以调用：

```lua
progression.AddXP(task.xpReward, "task")
```

等级系统不关心任务条件，只接收经验值。

### 与成就系统

成就系统后续可以调用：

```lua
progression.AddXP(achievement.xpReward, "achievement")
```

长期成就统计不放在等级系统里，避免职责膨胀。

### 与局外升级和存档

第一版等级系统只做内存长期数据。

后续存档接入时，等级系统需要提供：

```lua
progression.ExportState()
progression.ImportState(data)
```

数据格式建议：

```lua
{
    level = 4,
    xp = 27,
    totalXp = 312,
}
```

局外升级项上限后续可以通过：

```lua
progression.GetUpgradeLevelCap(upgradeKey)
```

第一版先不实现，避免局外系统过早影响调试。

## HUD 设计

### 展示位置

建议把骑手等级放在左上或左侧信息区，不挤占订单倒计时。

布局优先级：

```text
订单倒计时：最高
收入/连击/速度：高
骑手等级/经验：中
任务/道具：后续系统再排
```

第一版可以使用紧凑两行：

```text
Lv.3 城市快骑
XP 42/130
```

或单行：

```text
Lv.3 XP 42/130
```

### 升级反馈

第一版不做大弹窗，避免打断跑酷。

建议使用轻提示：

```text
升级 Lv.4
```

持续 1.5 秒后淡出。没有淡出能力时，显示 1.5 秒后清空即可。

解锁内容提示可后续增加：

```text
解锁 3 个订单点
解锁 远距离单
```

第一版也可以只打印日志，等 UI 稳定后再做视觉提示。

## 数值示例

### 新手阶段

玩家 Lv.1，只会刷普通单和顺路单，同时 2 个取餐点。

完成普通单，准时，当前连击 x1：

```text
基础 XP 8
准时 XP 2
连击 XP 0
总计 XP 10
```

### 升到 Lv.2

Lv.2 解锁急送单。

订单池变为：

```text
普通单
顺路单
急送单
```

同时订单数量仍然是 2。

### 升到 Lv.3

Lv.3 解锁 3 个取餐点，并提高高价值订单权重 10%。

玩家小地图上开始同时看到 3 个取餐点，路线选择明显变丰富。

### 升到 Lv.5

Lv.5 解锁远距离单，高价值订单权重加成提高到 20%。

订单池变为：

```text
普通单
顺路单
急送单
远距离单
```

### 升到 Lv.8

Lv.8 解锁易碎单。

易碎单依赖碰撞失败逻辑，若当前碰撞事件还不稳定，可以临时把易碎单解锁等级保留在配置中，但权重设为 0，等碰撞和失败逻辑验证后再打开。

## 实现步骤

### 第 1 步：新增 progression 模块

- 新增 `scripts/progression.lua`。
- 实现等级、经验、升级表读取。
- 实现 `AddXP()` 和 `GetHUDData()`。

验收：

```text
默认 Lv.1，XP 0/60。
AddXP(10) 后 XP 10/60。
AddXP(60) 后能升到 Lv.2 并保留溢出经验。
满级后不会继续升级或报错。
```

### 第 2 步：订单完成产出 XP

- 在 `pickup_delivery.lua` 中引入 `progression`。
- 给订单类型增加 `xp` 字段。
- 成功送达后调用 `progression.OnOrderDelivered()`。
- 订单失败后调用 `progression.OnOrderFailed()`。

验收：

```text
完成普通单增加 XP。
准时送达有额外 XP。
迟到送达只有基础 XP。
连续准时送达有少量连击 XP。
失败订单不增加 XP。
```

### 第 3 步：等级接管订单数量

- `pickup_delivery.lua` 的 `GetTargetOrderCount()` 改为读取 `progression.GetMaxAvailableOrders()`。
- 保留 `CONFIG.ORDER_AVAILABLE_COUNT_MAX` 作为硬上限。

验收：

```text
Lv.1 同时 2 个可接订单。
升到 Lv.3 后自动补足到 3 个可接订单。
升到 Lv.6 后最多 4 个。
升到 Lv.10 后最多 5 个。
```

### 第 4 步：等级过滤订单类型

- `PickOrderType()` 计算权重时跳过未解锁类型。
- 高价值订单按等级获得权重倍率。

验收：

```text
Lv.1 不会刷急送、远距离、易碎。
Lv.2 开始刷急送。
Lv.5 开始刷远距离。
Lv.8 开始刷易碎。
高等级时高价值订单出现频率明显提升。
```

### 第 5 步：HUD 显示真实等级

- `main.lua` 引入 `progression`。
- `ResetRun()` 调用 `progression.ResetRun()`。
- `ui.UpdateHUD()` 增加可选 `progressionData`。
- 替换当前 UI 中临时等级文案。

验收：

```text
HUD 显示当前等级。
HUD 显示 XP 当前值和升级所需值。
完成订单后 XP 数字更新。
升级后等级数字更新。
```

### 第 6 步：调试辅助

可选增加临时调试接口：

```lua
progression.DebugAddXP(amount)
progression.DebugSetLevel(level)
```

只用于本地验证，后续可以移除。

验收：

```text
可以快速验证 Lv.3、Lv.6、Lv.10 的订单数量变化。
```

## 边界处理

### 一次获得大量 XP

`AddXP()` 必须支持连续升级。

```text
Lv.1 50/60，获得 300 XP
-> Lv.4，并保留正确溢出 XP
```

### 满级

Lv.10 时：

- `xpToNext = 0`。
- `progress = 1.0`。
- 继续获得 XP 时可以增加 `totalXp` 和 `runXp`。
- `xp` 不再进入升级槽。

### 配置缺失

如果配置缺失，使用安全默认值：

```text
等级默认 1
订单数量默认 2
订单类型默认只开放 normal
订单 XP 默认 8
```

### 订单类型全被过滤

如果当前等级或配置导致所有订单权重为 0，则回退到普通单：

```lua
normal
```

避免刷单失败。

### 重开局

重开局调用 `progression.ResetRun()`，只清空本局经验和升级提示，不重置等级和经验。

### 游戏结束

第一版游戏结束不做额外结算。经验在订单完成瞬间已经发放。

## 测试计划

### 等级与经验

- 初始状态为 Lv.1，XP 0/60。
- 完成普通单后增加基础 XP。
- 准时送达获得额外 XP。
- 迟到送达不获得准时 XP。
- 连击送达获得连击 XP。
- XP 达到阈值后升级。
- 一次获得大量 XP 时可以连续升级。
- Lv.10 满级后不会继续升级。

### 订单数量

- Lv.1 地图同时存在 2 个可接订单。
- 设置到 Lv.3 后补足到 3 个可接订单。
- 设置到 Lv.6 后补足到 4 个可接订单。
- 设置到 Lv.10 后补足到 5 个可接订单。
- 可接订单数量不会超过取餐点节点池上限。

### 订单类型解锁

- Lv.1 只生成普通单和顺路单。
- Lv.2 可以生成急送单。
- Lv.5 可以生成远距离单。
- Lv.8 可以生成易碎单。
- 未解锁订单类型不会出现在小地图和主画面。

### 权重修正

- Lv.1 高价值订单没有额外权重。
- Lv.5 高价值订单权重高于 Lv.2。
- Lv.10 高价值订单权重最高。
- 如果某个高价值订单未解锁，权重加成不会让它提前出现。

### HUD

- HUD 展示真实等级。
- HUD 展示真实 XP 进度。
- 完成订单后 HUD 刷新。
- 升级后 HUD 刷新。
- 满级时 HUD 不显示异常的 `0/0` 进度。

### 重开局

- 重开局后等级和当前 XP 保留。
- 重开局后本局 XP 清零。
- 重开局后订单数量仍按当前等级刷新。

## 验收清单

第一版骑手等级系统完成后，应满足：

- 完成订单会获得经验。
- 准时和连击会提高经验收益。
- 迟到订单仍有基础经验，但没有准时和连击经验。
- 失败订单不获得经验。
- 经验达到阈值后自动升级。
- 骑手等级会影响同时刷新订单数量。
- 骑手等级会控制订单类型解锁。
- 骑手等级会提高高价值订单概率。
- HUD 能展示真实等级和经验。
- 重开局不会清空等级。
- 不依赖任务、成就、道具、局外升级或本地存档。

