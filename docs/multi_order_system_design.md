# 多订单系统设计文档

## 目标

多订单系统是玩法扩展的第一阶段。目标是把当前“地图上只有一个取件点”的流程，升级为“地图上同时存在多个可接订单，玩家通过驶向取餐点完成订单选择”的流程。

第一版只解决订单选择和订单流程，不引入骑手等级、局内道具、任务成就、局外升级和存档。

核心体验：

```text
地图同时刷新多个取餐点
-> 小地图显示多个订单位置和简要信息
-> 玩家驶向某个取餐点即接单
-> 接单后生成送达点和导航路线
-> 玩家完成或失败订单
-> 系统补足新的可接订单
```

## 范围

### 本阶段实现

- 同时刷新多个可接订单。
- 每个订单拥有独立取餐点位置、订单类型、奖励和预计距离。
- 玩家碰到某个取餐点后接取该订单。
- 同一时间只允许持有一个订单。
- 接单后复用当前送达点和导航逻辑。
- 未接订单不显示接单倒计时，不给玩家额外时间压力。
- 未接订单会稳定保留，只有在玩家明显驶离、订单不可达、或完成当前订单后由系统低频轮换。
- 当前订单完成、失败或取消后，系统继续补足可接订单。
- 小地图显示多个可接订单点和低负担摘要信息。

### 本阶段不实现

- 骑手等级影响订单数量。
- 局内道具。
- 任务和成就。
- 局外升级。
- 本地存档。
- 同时持有多个订单。
- 弹窗式订单选择。

这些内容在后续系统中接入。

## 当前系统分析

当前 `pickup_delivery.lua` 采用单订单结构：

```lua
pickupActive
pickupEdgeId
pickupEdgeDist
pickupLane

deliveryActive
deliveryEdgeId
deliveryEdgeDist
deliveryLane

hasPackage
orderTimerActive
orderTimeRemaining
```

当前流程：

```text
TrySpawnPickup()
-> CheckPickup()
-> hasPackage = true
-> TrySpawnDelivery()
-> nav.SetTarget()
-> CheckDelivery()
```

多订单系统要做的核心改造是：

- 把单个 `pickupActive` 改为 `availableOrders` 列表。
- 把“取件点”变成“可接订单入口”。
- 保留单个 `activeOrder`，保证导航和送达流程仍然一次只服务一个订单。
- 尽量复用现有 `deliveryActive`、订单倒计时、导航和结算逻辑。

## 数据结构

### 订单状态

```text
available  可接取，显示取餐点
accepted   已接取，显示送达点和导航
delivered  已送达，等待回收
failed     已失败，等待回收
recycled   未接取但已驶离/不可达，由系统回收刷新
```

### 订单类型

第一版保留 5 种订单类型，但可以先只启用普通单和急送单验证流程。

```lua
ORDER_TYPES = {
    normal = {
        label = "普通",
        color = "#FF5AA5",
        reward = 10,
        xp = 8,
        minHops = 2,
        maxHops = 4,
        timeFactor = 1.35,
        extraSeconds = 5.0,
        latePenalty = 2,
        fragile = false,
    },
    rush = {
        label = "急送",
        color = "#FF4D4D",
        reward = 16,
        xp = 12,
        minHops = 2,
        maxHops = 4,
        timeFactor = 1.05,
        extraSeconds = 3.0,
        latePenalty = 4,
        fragile = false,
    },
    long = {
        label = "远单",
        color = "#FFD34D",
        reward = 18,
        xp = 14,
        minHops = 4,
        maxHops = 7,
        timeFactor = 1.45,
        extraSeconds = 6.0,
        latePenalty = 2,
        fragile = false,
    },
    nearby = {
        label = "顺路",
        color = "#2EE66B",
        reward = 8,
        xp = 6,
        minHops = 1,
        maxHops = 2,
        timeFactor = 1.55,
        extraSeconds = 5.0,
        latePenalty = 1,
        fragile = false,
    },
    fragile = {
        label = "易碎",
        color = "#4DA3FF",
        reward = 15,
        xp = 12,
        minHops = 2,
        maxHops = 4,
        timeFactor = 1.30,
        extraSeconds = 5.0,
        latePenalty = 2,
        fragile = true,
    },
}
```

### 订单实例

```lua
{
    id = 1,
    status = "available",

    type = "rush",
    label = "急送",
    color = "#FF4D4D",

    pickupEdgeId = 12,
    pickupEdgeDist = 36.0,
    pickupLane = 2,

    deliveryEdgeId = 42,
    deliveryEdgeDist = 28.0,
    deliveryLane = 1,

    routeDistance = 138.0,
    reward = 16,
    xp = 12,

    pickupDistance = 58.0,
    routePreviewDistance = 138.0,
    miniPriority = 1,

    orderTimeLimit = 21.0,
    orderTimeRemaining = 21.0,
    orderLateSeconds = 0.0,

    fragile = false,
    latePenalty = 4,

    pickupNode = nil,
    pickupShadowNode = nil,
}
```

## 配置建议

在 `config.lua` 增加多订单参数：

```lua
ORDER_AVAILABLE_COUNT_DEFAULT = 2,
ORDER_AVAILABLE_COUNT_MAX = 5,
ORDER_PICKUP_SPAWN_AHEAD_MIN = 30.0,
ORDER_PICKUP_SPAWN_AHEAD_MAX = 110.0,
ORDER_PICKUP_MIN_DISTANCE_BETWEEN = 22.0,
ORDER_PICKUP_MAX_ATTEMPTS = 24,
ORDER_RECYCLE_BEHIND_DISTANCE = 45.0,
ORDER_RECYCLE_UNREACHABLE = true,
ORDER_REFRESH_ON_DELIVERY = true,
ORDER_TYPE_WEIGHTS = {
    normal = 45,
    nearby = 20,
    rush = 18,
    long = 12,
    fragile = 5,
},
```

第一版固定 `ORDER_AVAILABLE_COUNT_DEFAULT = 2`，后续骑手等级系统再接管数量。

## 核心流程

### 初始化

```text
CreatePickupNode(scene)
-> 改为创建 pickup node 池
-> Reset()
-> 清空 availableOrders
-> 清空 activeOrder
-> 补足 2 个可接订单
```

建议将旧接口保留为兼容：

```lua
pickup.CreatePickupNode(scene)
```

内部改为创建多个取餐点节点。

### 可接订单刷新

每帧或定时调用：

```lua
pickup.TrySpawnOrders()
```

逻辑：

1. 如果玩家正在路口内，不生成新订单。
2. 如果可接订单数量达到上限，不生成。
3. 从当前玩家 edge 出发，寻找可达候选 edge。
4. 随机选择订单类型。
5. 为订单选择取餐位置。
6. 为订单预选送达位置。
7. 如果订单有效，则加入 `availableOrders` 并显示取餐点。
8. 如果已有订单被玩家甩到身后较远处，系统可静默回收并补新订单。

### 接单

```lua
pickup.CheckOrderPickup()
```

逻辑：

1. 如果已经有 `activeOrder`，不接新订单。
2. 遍历 `availableOrders`。
3. 只检测与玩家当前 edge 相同的订单。
4. 距离和车道满足碰撞条件时，将该订单设为 `activeOrder`。
5. 其他可接订单保持存在。
6. 隐藏该订单的取餐点。
7. 显示送达点。
8. 调用 `nav.SetTarget(deliveryEdgeId, deliveryEdgeDist, path.state)`。
9. 启动该订单的送达倒计时。

### 送达

复用当前 `CheckDelivery()`，但数据来源改为 `activeOrder`。

送达成功：

```text
根据订单类型和迟到时间计算收入
增加总收入
处理连击
清理 activeOrder
隐藏送达点
清空导航目标
补足可接订单
```

送达失败：

```text
清空连击
清理 activeOrder
隐藏送达点
清空导航目标
补足可接订单
```

### 未接订单轮换

```lua
pickup.RefreshAvailableOrders()
```

逻辑：

1. 未接订单不倒计时，不因为停留时间过长而消失。
2. 如果订单取餐点已经在玩家身后较远距离，标记为 `recycled`。
3. 如果订单所在 edge 因重规划或路网变化不可达，标记为 `recycled`。
4. 玩家完成或失败当前订单后，可以轮换距离最远或价值最低的未接订单。
5. 被回收订单隐藏取餐点并释放节点。
6. 系统补足到目标可接订单数量。

这个规则的目的不是给玩家制造倒计时压力，而是保持地图前方始终有可选订单。

## 生成规则

### 取餐点位置

第一版优先简单稳定：

- 从当前 edge 开始，使用导航模块获取可达 edge。
- 订单取餐点可以生成在当前 edge 前方，也可以生成在 1 到 3 跳以内的可达 edge。
- 同一 edge 上取餐点之间保持最小距离。
- 取餐点不能靠近路口安全区。
- 取餐点不能与当前送达点或其他订单点太近。

### 送达目标

送达目标在生成订单时预先确定。

原因：

- 小地图可以展示订单预计距离。
- 订单奖励和时限可提前计算。
- 玩家接单时不需要再临时随机目标，体验更稳定。

如果预选送达目标失败，则该订单生成失败并重新尝试。

### 候选目标

使用现有：

```lua
nav.GetReachableTargetEdges(currentEdge, minHops, maxHops)
```

不同订单类型传入不同 `minHops / maxHops`。

## UI 和小地图设计

### 设计目标

小地图承担“轻量订单选择”的职责，但不能变成第二个操作界面。玩家在高速跑酷时只需要快速判断：

```text
哪里有订单
哪个订单更值钱
哪个订单更近
我现在大概该往哪个方向走
```

因此小地图遵循三条原则：

- 不显示接单倒计时。
- 不堆叠大量文字。
- 用颜色、大小、排序和短标签表达订单差异。

### 小地图数据

`pickup.GetMinimapData()` 从单个点改为多个点：

```lua
{
    active = true,
    orders = {
        {
            id = 1,
            slot = "e4_12",
            label = "急",
            displayText = "急/16￥",
            reward = 16,
            pickupDistance = 58.0,
            routePreviewDistance = 138.0,
            color = "#FF4D4D",
            priority = 1,
            nearest = true,
        },
        {
            id = 2,
            slot = "e6_14",
            label = "顺",
            displayText = "顺/8￥",
            reward = 8,
            pickupDistance = 92.0,
            routePreviewDistance = 80.0,
            color = "#2EE66B",
            priority = 2,
            nearest = false,
        },
    },
}
```

### 小地图布局

小地图继续使用右上角面板，但内部信息分成三层：

```text
地图层：路网、玩家、路线
订单层：多个可接订单 marker + 类型/金额短标签
状态层：底部 1 行当前状态
```

第一版面板尺寸可以保持当前 `132 x 154`。如果文字拥挤，再扩展到 `150 x 170`。

### 订单 marker 和标签样式

每个可接订单显示一个固定尺寸 marker，并在 marker 上方显示短标签。

| 订单类型 | marker 颜色 | marker 形状 | 含义 |
| --- | --- | --- | --- |
| 普通 | `#FF5AA5` | 圆点 | 标准订单 |
| 急送 | `#FF4D4D` | 圆点 + 外圈 | 高奖励、时间紧 |
| 远单 | `#FFD34D` | 方点 | 远距离高收益 |
| 顺路 | `#2EE66B` | 圆点 | 短路线保连击 |
| 易碎 | `#4DA3FF` | 菱形或方点 | 撞击失败 |

尺寸规则：

- 普通订单：`8 x 8`
- 高价值订单：`10 x 10`
- 最近订单：额外显示 1 个白色描边或浅色外圈
- 当前已接订单：不再显示取餐 marker，改显示送达目标 marker

标签格式：

```text
类型/金额￥
```

示例：

```text
普/12￥
急/16￥
远/18￥
顺/8￥
碎/15￥
```

标签规则：

- 标签显示在订单 marker 上方。
- 标签只显示短类型，不显示完整订单名。
- 金额直接放在接单点上，不再依赖底部摘要。
- 第一版最多同时显示 5 个标签；如果重叠严重，优先显示最近 2 个和最高价值 1 个，其余只显示 marker。

如果 UI 库不支持描边，使用两个叠放 panel：

```text
outer marker: 12 x 12, 白色/浅色
inner marker: 8 x 8, 类型颜色
```

### 底部状态文字

可接订单选择态下，底部不再显示“近/高”摘要，只显示状态：

```text
当前订单
```

原因：

- 订单金额已经显示在各接单点标签上。
- 底部摘要继续显示“近/高”会让玩家重复读两套信息。
- “当前订单”用于提示当前处于可选订单地图状态，未接单时不会显示送达倒计时。

如果没有可接订单：

```text
正在刷新订单
```

如果已有当前配送订单：

```text
当前 急送 120m
```

### 靠近订单时的提示

当玩家距离某个可接订单较近时，小地图和 HUD 做轻提示：

- 小地图中该订单 marker 放大或外圈闪烁。
- 订单标签继续使用同一格式，例如：

```text
急/16￥
```

- `miniStatus` 显示：

```text
前方 急送 ¥16
```

- HUD 中间提示区可以短暂显示：

```text
靠近急送单
```

```text
靠近急送单
```

触发条件建议：

```lua
ORDER_APPROACH_HINT_DISTANCE = 22.0
```

提示不能阻塞输入，也不弹窗。

### 接单后的显示切换

玩家接到订单后，小地图状态切换：

```text
可接订单选择模式 -> 当前订单导航模式
```

变化规则：

- 被接取的取餐 marker 隐藏。
- 送达目标 marker 显示。
- 推荐路线高亮。
- 其他未接订单 marker 保留，但透明度降低或尺寸减小。
- 底部摘要从订单列表切换为当前订单：

```text
当前 急送 120m
```

这样玩家仍知道地图上还有其他订单，但不会和当前导航目标抢注意力。

### 未接订单显示降噪

当玩家正在配送时，未接订单不应干扰导航。

配送中未接订单显示规则：

- marker 尺寸减小 20%。
- 不参与底部摘要。
- 不显示靠近提示。
- 不触发接单检测，直到当前订单结束。

### 订单选择交互逻辑

玩家不点击小地图，不在小地图里选择订单。小地图只提供信息。

真正的接单交互是：

```text
玩家驶入某个可接订单取餐点
-> 车道匹配
-> 自动接单
```

判断规则：

```text
同一 edge
同一 lane
距离差小于碰撞阈值
当前没有 activeOrder
```

如果玩家经过取餐点但车道不匹配：

- 不接单。
- 不惩罚。
- 订单继续保留。

### 小地图实现建议

第一版最小实现：

- 预创建最多 5 个订单 marker。
- marker 根据订单数据设置位置、颜色、尺寸和显隐。
- 当前 UI 若不支持动态颜色，则先用固定颜色 marker 分组，或用同色 marker + 底部摘要区分类型。
- 小地图底部 `miniStatus` 显示“当前订单”或当前配送状态，订单金额显示在各订单 marker 标签上。

预创建节点建议：

```text
mini_order_outer_1
mini_order_inner_1
...
mini_order_outer_5
mini_order_inner_5
```

每帧根据订单数据移动或显隐。

### HUD

当前订单倒计时沿用原 HUD。

未接订单不进入顶部倒计时，只在小地图展示。

接单后顶部显示：

```text
急送 18s
远单 25s
迟到 3s
```

## 与其他系统的关系

### 导航系统

导航仍然只追踪一个目标。

```text
availableOrders 不进入导航
activeOrder 进入导航
```

### 障碍物系统

障碍物避让需要从单个订单点改为多个订单点：

当前：

```lua
if pickup.pickupActive and pickup.pickupEdgeId == edgeId then ...
if pickup.deliveryActive and pickup.deliveryEdgeId == edgeId then ...
```

改为：

```lua
pickup.IsNearOrderPoint(edgeId, edgeDist, lane)
```

由订单模块统一判断所有可接取餐点和当前送达点。

### 后续骑手等级

多订单系统第一版使用固定数量 2。

后续成长系统接入时，只替换：

```lua
pickup.GetMaxAvailableOrders()
```

从固定值改为：

```lua
progression.GetMaxAvailableOrders()
```

## 接口设计

建议 `pickup_delivery.lua` 对外提供：

```lua
pickup.CreatePickupNode(scene)
pickup.CreateDeliveryNode(scene)
pickup.TrySpawnOrders()
pickup.CheckOrderPickup()
pickup.CheckDelivery()
pickup.UpdateOrderTimers(dt)
pickup.UpdateAnimation()
pickup.GetOrderTimerData()
pickup.GetMinimapData()
pickup.IsNearOrderPoint(edgeId, edgeDist, lane)
pickup.ReselectDeliveryTarget(currentSpeed)
pickup.Reset()
```

保留兼容旧调用：

```lua
pickup.TrySpawnPickup()
pickup.TrySpawnDelivery(currentSpeed)
pickup.CheckPickup()
pickup.UpdateOrderTimer(dt)
```

兼容方式：

- `TrySpawnPickup()` 内部调用 `TrySpawnOrders()`。
- `TrySpawnDelivery()` 在多订单系统中可以变为空操作，因为接单时已经生成送达目标。
- `CheckPickup()` 内部调用 `CheckOrderPickup()`。
- `UpdateOrderTimer(dt)` 内部调用 `UpdateOrderTimers(dt)`。

这样主循环可以分阶段改造，降低一次性风险。

## 失败与边界处理

### 找不到取餐点

如果候选取餐点生成失败：

- 本帧跳过。
- 下帧继续尝试。
- 不阻塞游戏。

### 找不到送达目标

如果订单送达目标生成失败：

- 放弃该订单。
- 重新尝试生成另一个订单。

### 玩家接单后目标不可达

如果 `nav.SetTarget()` 失败：

- 该订单接单失败。
- 隐藏送达点。
- 清理 `activeOrder`。
- 重新补足可接订单。

### 玩家进入死路

沿用当前游戏结束逻辑。

### 玩家错过取餐点

第一版不因错过取餐点惩罚玩家。

如果订单仍在玩家前方或仍然可达，可以绕路再去取。若订单已经被玩家甩到身后较远处，系统会静默回收并在前方补新订单。

### 玩家错过送达点

沿用当前送达失败逻辑：

- 清空连击。
- 订单失败。
- 隐藏送达点。
- 清空导航。

## 实现步骤

### 第 1 步：数据结构改造

- 新增 `availableOrders`。
- 新增 `activeOrder`。
- 定义订单类型配置。
- 保留旧字段作为兼容层，避免一次性改完所有调用。

验收：

```text
游戏能启动。
Reset 后订单列表为空。
旧 HUD 不报错。
```

### 第 2 步：取餐点节点池

- 把单个取餐点节点扩展为最多 5 个节点。
- 每个订单绑定一个取餐点节点。
- 支持隐藏、显示、移动和浮动动画。

验收：

```text
地图上可以同时显示 2 个取餐点。
节点不会无限创建。
重开局后旧取餐点隐藏。
```

### 第 3 步：可接订单刷新

- 实现订单生成和补足。
- 实现未接订单稳定保留。
- 实现驶离过远或不可达后的静默轮换。

验收：

```text
Lv.1 固定同时存在 2 个可接订单。
玩家不接单时，订单不会因为倒计时消失。
订单被甩到身后较远处后，前方会补新订单。
```

### 第 4 步：接单流程

- 玩家碰到某个取餐点后设为 `activeOrder`。
- 隐藏该取餐点。
- 显示送达点。
- 启动导航和订单倒计时。

验收：

```text
碰到 A 取餐点只接 A 订单。
接单后出现送达点。
小地图出现送达路线。
未接订单仍存在。
```

### 第 5 步：送达和失败

- `CheckDelivery()` 使用 `activeOrder`。
- 收入、迟到、连击沿用当前逻辑。
- 完成或失败后清理订单并补足可接订单。

验收：

```text
成功送达增加收入。
迟到送达可扣收益。
错过送达点会失败。
完成后继续刷新可接订单。
```

### 第 6 步：小地图支持多个订单

- `GetMinimapData()` 返回 `orders` 列表。
- UI 预创建最多 5 个可接订单 marker。
- 不同订单类型使用不同颜色。
- 小地图状态文字显示当前地图状态，订单 marker 标签显示类型和金额。
- 玩家接单后，未接订单降噪显示，当前路线和目标成为视觉重点。

验收：

```text
小地图能同时显示 2 个订单点。
小地图不显示未接订单倒计时。
接单后该订单点消失，送达目标出现。
配送中未接订单不会抢当前路线的视觉焦点。
```

### 第 7 步：障碍物避让改造

- 新增 `pickup.IsNearOrderPoint()`。
- `obstacles.lua` 改为调用该接口。

验收：

```text
障碍物不会贴着任意可接取餐点或当前送达点生成。
```

## 验收清单

第一版多订单系统完成后，应满足：

- 开局可同时看到 2 个取餐点。
- 两个取餐点对应不同订单实例。
- 玩家接触哪个取餐点，就接取哪个订单。
- 接单后只显示一个当前送达目标和一条导航路线。
- 未接订单不会因为倒计时自动清空。
- 未接订单被甩到玩家身后较远处后能静默轮换。
- 完成订单后可接订单数量会补足。
- 失败订单后可接订单数量会补足。
- 小地图能展示多个可接订单的位置、类型和简短摘要。
- 小地图在配送中能突出当前路线，同时弱化未接订单。
- 障碍物不会与订单点重叠。
- 重开局后订单、取餐点、送达点和导航都正确清空。
