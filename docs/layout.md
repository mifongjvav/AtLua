# 布局

`At.layout` 是一个 CSS 子集式的布局引擎：**只计算矩形，不画像素**，因此不依赖 `love.graphics`，可以在没有 LÖVE 的环境里无头测试。

日常使用时通常不直接调用它，而是把子组件放进 `At.Panel`（见 [components.md](components.md#at-panel)），由 `Panel:draw()` 自动排版。

## 与 CSS 的对照

| 本库写法                                                         | 对应的 CSS                       | 说明                                                   |
| ---------------------------------------------------------------- | -------------------------------- | ------------------------------------------------------ |
| `direction = "column"` / `"row"`                                 | `flex-direction: column` / `row` | 主轴方向，默认 `column`                                |
| `gap = 12`                                                       | `gap: 12px`                      | 子项间距，单位是像素，不带 `px`                        |
| `padding = 16` 或 `padding = { left, top, right, bottom }`       | `padding`                        | `Panel` 的内边距                                       |
| 子项上的 `margin = 8` 或 `margin = { left, top, right, bottom }` | `margin`                         | 写子组件上，不是容器上                                 |
| `w = 120` / `w = "50%"` / `w = "auto"`                           | `width: 120px` / `50%` / `auto`  | `h` 同理                                               |
| `grow = 1`                                                       | `flex-grow: 1`                   | 按权重瓜分主轴剩余空间                                 |
| `align = "center"`                                               | `align-items: center`            | 交叉轴对齐：`start` / `center` / `end` / `stretch`     |
| `justify = "center"`                                             | `justify-content: center`        | 主轴分布：`start` / `center` / `end` / `space-between` |
| `wrap = true` / `flexWrap = "wrap"`                              | `flex-wrap: wrap`                | 主轴空间不足时换行/换列                                |
| `alignContent = "center"`                                        | `align-content: center`          | 换行后的多行/多列整体对齐                              |
| `display = "grid"` + `grid = { columns = 2 }`                    | `display: grid`                  | 基础 grid；行优先填充                                  |
| `position = "absolute"` + `left/top/right/bottom`                | `position: absolute`             | 脱离流式布局，相对父内容区定位                         |
| `zIndex = 2`                                                     | `z-index: 2`                     | 同一 Panel 内的绘制层级                                |

与 CSS 的差异：

- 数字就是像素，不需要也不能写 `px`。
- `direction` 默认是 `column`（纵向），不是 `row`；`Panel` 的 `gap` 默认 `8`。
- `align` 默认 `start`，不是 CSS 的 `stretch`。
- 没有 `flex-shrink`，空间不够时子项**不会自动缩小**。
- `margin` 没有 `auto`。
- `zIndex` 只影响绘制顺序；事件顺序仍由组件创建顺序决定（后创建先收事件）。
- grid 不支持命名区域、`grid-column`/`grid-row` 跨格和 `auto-flow: column`。

## 尺寸：`pixels` 支持三种写法

`At.layout.pixels(value, base)` 把声明值解析成像素：

| 写法                   | 结果                               |
| ---------------------- | ---------------------------------- |
| `120`（数字）          | `120`                              |
| `"50%"`                | `base * 0.5`                       |
| `"auto"`（或空字符串） | `nil`，交给 `measure()` 求自然尺寸 |

**百分比在父容器没有可用宽度时会退化成 auto**：此时 `pixels("50%", nil)` 返回 `nil`，组件按自身内容测量，而不是变成 `0`。

- 子项的宽度百分比基数 = 父容器的内容宽度（父宽减去左右 `padding`）；高度百分比同理用内容高度。
- 根 `Panel` 的百分比基数来自 `_availW` / `_availH`：要么由外层 `layout.arrange` 写入，要么显式调用 `panel:layout(availW, availH)`。
- 根 `Panel` 如果 `w = "auto"` 又没有可用宽度，里面所有百分比都会退化成 auto。

## 边距：`sides` 支持数字或四边表

`At.layout.sides(value)` 返回 `left, top, right, bottom`：

```lua
At.layout.sides(8)                                  -- 8, 8, 8, 8
At.layout.sides{ left = 8, right = 8 }              -- 8, 0, 8, 0
At.layout.sides(nil)                                -- 0, 0, 0, 0
```

`padding` 和 `margin` 都走这套规则。表里缺的边按 `0` 处理。

## 排版时机

- `Panel:draw()` 每次绘制都会先 `self:layout()` 再画，**幂等**：同一份数据重复排版结果相同。
- 也可以手动排版：`panel:layout(availW, availH)`。`availW/availH` 是父容器给的可用空间，决定百分比基数；不传就沿用上次记录的值。
- `auto` 尺寸在排版后会写成像素，但**原始规格保存在 `_specW/_specH` 里**；下次排版先还原规格再重新测量。所以内容变化后仍会重新计算：

```lua
local label = At.Label{ text = "短" }   -- 宽度是第一次测量出来的像素值
print(label:declaredWidth())            -- "auto"：原始规格还在

label:setText("更长的一段文字")         -- 内部调用 invalidateSize()
-- 下一次 label:draw() 或 panel:layout() 时宽度自动更新
```

`Panel:add / remove / clear` 同样会让容器重新测量，所以动态加子项后不需要手动改 `h`。

- 只想量尺寸、不想改任何坐标时，用纯函数 `At.layout.measure(node, availW, availH)`。

## `grow`

`grow` 写在**子项**上，表示在主轴上按权重瓜分剩余空间，作用类似 CSS 的 `flex-grow`。

- 只影响主轴：`direction = "column"` 时加高度，`"row"` 时加宽度。
- 只有 `grow > 0` 的子项参与分配；权重按 `grow` 的比例分。
- 先算已有尺寸和外边距，再算 `gap`，剩下的才是可分配空间。
- **没有剩余空间时不生效**（也不会让子项缩小）；`grow` 分配完剩余空间后，`justify` 通常就没有可分配的量了。
- 交叉轴尺寸不受 `grow` 影响。

工具栏里让标题吃掉中间空档就是典型用法：

```lua
At.Panel{
    direction = "row", w = 600, h = 56, padding = 8, gap = 8,
    children = {
        At.Button{ w = 80, text = "新建" },
        At.Label{ text = "标题", grow = 1 },
        At.Button{ w = 80, text = "保存" },
    },
}
```

## `justify`

`justify` 控制**主轴**上剩余空间的分布，类似 CSS 的 `justify-content`：

| 取值              | 效果                                                |
| ----------------- | --------------------------------------------------- |
| `"start"`         | 靠主轴起点（默认）                                  |
| `"center"`        | 整体居中                                            |
| `"end"`           | 靠主轴终点                                          |
| `"space-between"` | 首尾贴边，剩余空间平均塞进子项之间（至少 2 个子项） |

- 只在有剩余空间时生效；被 `grow` 分完之后剩余为 0，`justify` 就看不出效果。
- 它不改变子项尺寸，只改变摆放位置和额外间距。

## `align`

`align` 控制**交叉轴**对齐，类似 CSS 的 `align-items`：

| 取值        | 效果                 |
| ----------- | -------------------- |
| `"start"`   | 靠交叉轴起点（默认） |
| `"center"`  | 交叉轴居中           |
| `"end"`     | 靠交叉轴终点         |
| `"stretch"` | 拉伸到内容区大小     |

`stretch` 只对**声明为 `auto` 的尺寸**生效：`column` 里拉伸 `auto` 的宽度，`row` 里拉伸 `auto` 的高度。显式写了数字或百分比的子项保持原尺寸。交叉轴内容尺寸未知时也无法拉伸。

## flex-wrap

在 `At.Panel` 上设 `wrap = true`（或 CSS 风格的 `flexWrap = "wrap"`）后，主轴空间不足会换行/换列：

```lua
At.Panel{
    direction = "row",
    wrap = true,
    alignContent = "start",
    gap = 8,
    w = 300,
    children = { ... },
}
```

- `direction = "row"`：宽度不够时换到下一行。
- `direction = "column"`：高度不够时换到下一列。
- `align` 控制每一行/列内部的交叉轴对齐。
- `alignContent` 控制多行/多列整体在交叉轴上的位置：`start` / `center` / `end` / `space-between` / `stretch`。
- `justify` 逐行/逐列生效；`grow` 也在每一行/列内部瓜分剩余空间。
- 行的交叉轴尺寸取该行最高的子项；列的交叉轴尺寸取该列最宽的子项。
- `wrap` 依赖主轴可用尺寸；父容器主轴上没有确定尺寸时不会换行。

## grid

`display = "grid"` 使用基础网格布局，按行优先放置子项：

```lua
At.Panel{
    display = "grid",
    grid = {
        columns = 2,          -- 等宽两列；也可写 { 120, "1fr" }
        rows = nil,           -- 可选：固定行高表，如 { 40, "auto" }
        gap = 10,             -- 行列间距
        columnGap = nil,      -- 可分别覆盖
        rowGap = nil,
    },
    w = 400,
    children = {
        At.Label{ text = "左上" },
        At.Label{ text = "右上" },
        At.Label{ text = "左下" },
        At.Label{ text = "右下" },
    },
}
```

- `columns`：
  - 数字：等宽列数。
  - 表：每一项可以是固定像素、`"50%"`、`"auto"`、`"1fr"`。
- `rows`：可选固定行高表；不传时行高由该行最高子项决定。
- `gap` 同时作为默认行列间距；`columnGap` / `rowGap` 可覆盖。
- 子项的百分比宽度以所在单元格为基数；`"100%"` 会填满单元格。
- 单元格内的水平/垂直对齐使用 `justify` / `align`。
- 子项可以继续嵌套自己的布局；不支持跨行/跨列。
- grid 和 flex 一样可以包含绝对定位子项。

## 绝对定位

子项设 `position = "absolute"` 后不再参与流式排版，也不会影响父容器的 auto 尺寸：

```lua
At.Panel{
    w = 320, h = 180,
    children = {
        At.Label{ text = "流式内容" },
        At.Label{
            text = "角标",
            position = "absolute",
            right = 12, bottom = 12,
            w = 48, h = 28,
        },
    },
}
```

- `left` / `top` / `right` / `bottom` 相对父容器的**内容区**（减去 padding）；也可以把初始 `x` / `y` 当作 `left` / `top` 的别名。
- 同时给左右偏移且 `w = "auto"` 时，宽度会被拉伸到两者之间；上下同理。
- 同时给 `left` 和 `right` 且显式给 `w` 时，以 `left` 为准。
- 绝对定位子项仍然可以在 `Panel.children` 里，参与绘制与 registry 事件；z 顺序由 `zIndex` 控制绘制。

## z-index

子项的 `zIndex`（别名 `z`）控制它在同一个 `Panel` 内的绘制顺序：

```lua
At.Panel{
    children = {
        At.Panel{ zIndex = 0, ... },
        At.Panel{ zIndex = 10, ... }, -- 后画，盖在上面
    },
}
```

- 数值越大越后绘制；相同值按创建顺序。
- 只影响绘制顺序，不改变事件注册顺序；需要点击在上层时，仍建议后创建它，或把交互组件放进对应的高 zIndex 子容器。
- 嵌套 Panel 各自排序，跨层级的 zIndex 不互相比较。

## 像素对齐

排版结果会四舍五入到整数：`x/y/w/h` 都对齐到像素（`At.pixel.round`），这样文字、圆角与 1px 边框不会落在半个像素上发虚。副作用是百分比/居中会产生 ±1px 的取整差，例如三个 `"33%"` 的子项实际宽度是 `33/33/35`（总和仍等于容器宽度）。

需要严格等宽时用 `grow = 1` 均分，而不是百分比。

## 内容超出视口

布局引擎只负责"算矩形"，**不裁剪也不滚动**。内容比窗口高时，把它放进 `At.ScrollView`：

```lua
local view = At.ScrollView{
    x = 40, y = 40,
    w = 360, h = love.graphics.getHeight() - 80,
    content = card,     -- card 的 w 用 "100%" 就会跟着视口宽度
}
```

滚动和裁剪都在 ScrollView 里完成，布局规则不受影响（见 [components.md](components.md#at-scrollview)）。

## 限制

- 不支持 `flex-shrink`、`min-width` / `max-width`、`order`、`aspect-ratio`。
- 不支持 grid 的命名区域、跨行/跨列、`auto-flow: column`。
- 不支持 `wrap-reverse`；换行始终从主轴起点开始。
- `zIndex` 只影响绘制，不影响事件命中顺序。
- 交叉轴 `stretch` 只对 `auto` 尺寸生效。
- 百分比需要父容器宽度已知；否则按 auto 处理。
- 只做单遍排版：没有 CSS 那样的多轮内在尺寸迭代。
- grid 的 `auto`/`fr` 列在容器宽度未知时按子项自然宽度估算。

## 示例

### 表单卡片（column + 百分比 + gap + padding）

```lua
local At = require("At.At")

local card = At.Panel{
    x = 40, y = 40, w = 360, h = "auto",
    direction = "column", gap = 12, padding = 16,
    radius = 14, background = "@surface",
    children = {
        At.Label{ text = "登录" },
        At.TextInput{ w = "100%", placeholder = "用户名" },
        At.TextInput{ w = "100%", placeholder = "密码", password = true },
        At.Button{ w = "100%", text = "确定" },
    },
}

function love.draw() card:draw() end
```

### 工具栏（row + grow）

```lua
local At = require("At.At")

local toolbar = At.Panel{
    x = 20, y = 20, w = 600, h = 56,
    direction = "row", align = "center", gap = 8, padding = 8,
    background = "@surface",
    children = {
        At.Button{ w = 80, text = "新建" },
        At.Label{ text = "标题", grow = 1, align = "center" },
        At.Button{ w = 80, text = "保存" },
    },
}

function love.draw() toolbar:draw() end
```

### 居中按钮（align + justify）

```lua
local At = require("At.At")

local panel = At.Panel{
    x = 40, y = 40, w = 400, h = 200,
    direction = "column", align = "center", justify = "center",
    padding = 16, background = "@surface",
    children = {
        At.Button{ w = 160, text = "开始" },
    },
}

function love.draw() panel:draw() end
```
