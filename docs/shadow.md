# 阴影

`At.Panel` / `At.Button` 以及旧式 `At.button` 的阴影都由 [`At.shadow`](../At/core/shadow.lua) 绘制。
默认使用 **GLSL SDF 阴影**：一次 `draw` 画一个带圆角的模糊投影，边缘柔和、没有多层叠加的条纹；
旧的“多层缩放矩形”实现保留，可通过配置切回。

## 切换算法

在 [`At/config.lua`](../At/config.lua) 里改：

```lua
At.config.shadow.algorithm = "glsl"    -- 默认：GLSL SDF，一次绘制
At.config.shadow.algorithm = "legacy"  -- 旧实现：layers 层缩放矩形叠加
At.config.shadow.algorithm = "none"    -- 全部关闭
At.config.apply()
```

运行时也可以直接调用：

```lua
At.shadow.setAlgorithm("legacy")
At.shadow.getAlgorithm()   -- "legacy"
```

`At.lua` 启动时会自动应用一次配置；之后改 `At.config.shadow` 需要再调 `At.config.apply()`。
单个组件仍可用 `shadow = false` 关闭自己的阴影，不受全局配置影响。

## 默认值

组件的 `shadow = true`（不传 `shadowArgs`）时使用 `At.config.shadow`：

| 字段                  | 默认值           | 说明                                                    |
| --------------------- | ---------------- | ------------------------------------------------------- |
| `algorithm`           | `"glsl"`         | 算法                                                    |
| `color`               | `"@primaryDark"` | 阴影颜色，可传主题 token 或 hex                         |
| `alpha`               | `0.4`            | 字符串颜色 / 缺省颜色的最大不透明度（0–1）              |
| `spread`              | `3`              | GLSL 下实际模糊半径是 `spread * 2`，legacy 下是最大扩散 |
| `layers`              | `20`             | 只对 legacy 有效                                        |
| `offsetX` / `offsetY` | `1` / `2`        | 阴影偏移                                                |

```lua
At.config.shadow.spread = 2
At.config.shadow.offsetX = 1
At.config.shadow.offsetY = 1
At.config.shadow.color = "@primaryDark"
At.config.apply()
```

显式传 `shadowArgs` 的组件仍以表里的值为准。

## 参数

组件属性 `shadowArgs` 和 `At.shadow.shadow` 的签名保持不变：

```lua
At.shadow.shadow(x, y, w, h, corner, color, spread, layers, offsetX, offsetY)
```

| 参数                  | 说明                                                                                                        |
| --------------------- | ----------------------------------------------------------------------------------------------------------- |
| `x` / `y` / `w` / `h` | 组件矩形（左上角 + 宽高）                                                                                   |
| `corner`              | 组件圆角；阴影跟随这个形状                                                                                  |
| `color`               | 0–1 的 RGBA 表，或 hex / 主题 token（字符串默认 alpha 0.4）；`color[4]` 是最大不透明度                      |
| `spread`              | 模糊/扩散基准：GLSL 下实际模糊半径是 `spread * 2`，legacy 下是最大缩放扩散（组件 `shadowArgs` 里的第 2 项） |
| `layers`              | **只对 legacy 生效**；GLSL 忽略它                                                                           |
| `offsetX` / `offsetY` | 阴影偏移                                                                                                    |

不传 `shadowArgs` 时使用 `At.config.shadow` 的默认值（`@primaryDark`，spread 3，offset 1/2，alpha 0.4）。
GLSL 的模糊围绕组件边缘内外对称展开，实际半径是 `spread * 2`，并用 smootherstep
和 1/255 的屏幕空间抖动减少浅色背景上的色带；`layers` 不参与计算，所以把算法从
legacy 切到 glsl 时，阴影观感会变化（通常更干净、更省绘制调用）。

## API

| 成员                                                                            | 说明                                             |
| ------------------------------------------------------------------------------- | ------------------------------------------------ |
| `At.shadow.shadow(x, y, w, h, corner, color, spread, layers, offsetX, offsetY)` | 绘制外阴影；组件内部调用，也可自己用             |
| `At.shadow.inner(x, y, w, h, corner, color, alpha, size, offsetX, offsetY)`     | 绘制内阴影；`alpha` 0–1，只画在形状内部          |
| `At.shadow.setAlgorithm(name)`                                                  | `"glsl"` / `"legacy"` / `"none"`；非法值报错     |
| `At.shadow.getAlgorithm()`                                                      | 当前配置的算法                                   |
| `At.shadow.reset()`                                                             | 丢弃缓存的 shader / 1×1 白纹理；窗口重建后可调用 |

## 内阴影

`At.shadow.inner` 给单选圆圈、复选方框这类控件加凹陷感：

```lua
At.shadow.inner(
    x, y, w, h,   -- 组件矩形
    radius,       -- 圆角；圆形传 w/2
    "@primaryDark",
    0.16,         -- alpha 0..1
    3,            -- 向内衰减的像素距离
    0, 0          -- 可选偏移
)
```

- `color` 接受 hex / 主题 token；`alpha` 是 0–1，不是组件的 0–255。
- 只画在圆角矩形内部，shader 输出在形状外的 alpha 为 0。
- 需要 GLSL；没有 shader 时直接跳过，不影响控件交互。
- `At.RadioGroup` / `At.Checkbox` 默认开启，可通过 `innerShadow = false` 关闭，并可用
  `innerShadowColor` / `innerShadowAlpha` / `innerShadowSize` / `innerShadowOffsetX` /
  `innerShadowOffsetY` 调整。

## GLSL 实现说明

- 外阴影用圆角矩形 SDF，围绕边缘内外对称模糊，再用 smootherstep 得到柔和边缘。
- 内阴影用同一 SDF 的负距离：贴边处 alpha 最大，向内 `size` 像素衰减到 0。
- 绘制范围按 `spread + 偏移` 自动外扩，不会裁掉偏移方向上的阴影。
- shader 是内联字符串，不需要额外的 `.glsl` 文件；只有第一次绘制时编译并缓存。
- 如果设备没有 `love.graphics.newShader`、shader 编译失败，或拿不到 1×1 白纹理，会**自动回退 legacy**，不会让组件画不出来。
- 使用 `love.graphics.push("all")` / `pop()` 保存和恢复 shader、混合模式、颜色等状态。

## 性能与限制

- GLSL 阴影每个组件一次 `draw`，比 legacy 的 `layers + 1` 次矩形绘制便宜很多，适合列表、卡片较多的界面。
- legacy 保留用于兼容旧观感或 shader 不可用的环境；层数越多越柔和，也越耗绘制调用。
- 外阴影绘制在组件下方，可能超出组件矩形；父级 `ScrollView` 的 scissor 仍会裁剪它。内阴影绘制在填充之上、边框之下，不会超出控件。
- `shadowArgs` 的颜色 alpha 是 **0–1**（这是阴影表的历史约定），不要按组件的 0–255 alpha 传。
- `At.config.shadow.algorithm = "none"` 会同时跳过外阴影和组件内阴影；如果只想关某个组件，用该组件的 `shadow = false`。

## 示例

```lua
local At = require("At.At")

At.config.shadow.algorithm = "glsl"
At.config.apply()

local card = At.Panel{
    x = 40, y = 40, w = 360, h = 180,
    radius = 18, background = "@surface",
    shadow = { { 0, 0, 0, 0.3 }, 14, 20, 6, 10 },
}

function love.draw()
    card:draw()
end
```

切回旧实现：

```lua
At.shadow.setAlgorithm("legacy")
```
