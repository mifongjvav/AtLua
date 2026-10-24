# 背景模糊（毛玻璃）

`At.blur` 让**半透明组件**在背后内容上做模糊，形成毛玻璃效果。它抓取组件之前已经画好的画面、
按算法模糊，再裁剪成组件的圆角形状铺在下面。

```lua
At.blur.setEnabled(true)            -- 也可以写 At.blur.enabled = true
At.blur.setStrength(8)              -- 模糊强度（采样步长/降采样倍数）

function love.draw()
    At.blur.beginFrame()            -- 之后的绘制进入内部 canvas
    ui:draw()
    console:draw()
    At.blur.endFrame()              -- 输出到屏幕
end
```

## 什么时候会模糊

组件只有在**背景半透明（alpha < 255）**且 `At.blur` 启用时才会调用模糊。当前自动支持：

| 组件            | 触发条件                                     |
| --------------- | -------------------------------------------- |
| `At.Panel`      | `background` 存在且 `alpha < 255`            |
| `At.Console`    | 默认 `alpha = 205`，一直触发                 |
| `At.ScrollView` | `background` 存在且 `alpha < 255`            |
| `At.TextInput`  | `alpha < 255`                                |
| `At.Button`     | `fillAlpha() < 255`（含禁用态的 45% 透明度） |

`At.Label`、`At.Slider` 等没有背景面板，不参与模糊。

## 每帧必须包住 beginFrame / endFrame

模糊需要一份"当前画面"的副本。只有把绘制放进 `beginFrame`/`endFrame` 之间，组件才能取到
它背后的内容：

```lua
function love.draw()
    At.blur.beginFrame()
    -- 这里画的所有内容会进入内部 canvas
    At.blur.endFrame()
end
```

没有调用 `beginFrame` 时，`At.blur` 会尝试拷贝**当前 canvas**；如果你直接画到屏幕（当前 canvas 为
`nil`），拿不到背景，模糊会被跳过，组件仍然正常绘制——只是没有毛玻璃效果。

## 算法

```lua
At.blur.setAlgorithm("gaussian")    -- 默认：分离式高斯，需要 shader
At.blur.setAlgorithm("downscale")   -- 降采样再放大，无 shader，GLES2 也能用
At.blur.setAlgorithm("none")        -- 只复制背景，不模糊（对比/调试用）
At.blur.setAlgorithm(function(snapshot, x, y, w, h, strength)
    -- 返回 纹理, 源x, 源y, 源w, 源h；返回 nil 表示这次不模糊
    return snapshot, x, y, w, h
end)
At.blur.registerAlgorithm("mine", fn)   -- 注册后可用名字切换
At.blur.getAlgorithms()                  -- 已注册的算法名
```

- `gaussian` 需要 `love.graphics.newShader`；设备/驱动不支持时**自动回退到 `downscale`**。
  实现是"先降到 1/2 分辨率 → 水平/垂直各一遍 9 点高斯（采样点间距只有 radius/4）→ 线性放大"：
  高分辨率下做稀疏采样会把画面复制成几格，正是那种"小方块"感的来源。
- `downscale` 不需要 shader：走多级金字塔（区域 → 1/2 → 1/`strength` → 1/2 → 组件大小），
  每一步只放大 2~3 倍，比"一步缩小再一步放大"平滑得多，性能也最好。
- 自定义算法只负责"产出纹理"，圆角裁剪由 `At.blur` 统一用 stencil 处理。

`strength` 默认 8：`gaussian` 里决定高斯半径（越大越糊），`downscale` 里决定金字塔最低一级的缩小倍数（2–6）。

## API

| 函数                                              | 说明                                                   |
| ------------------------------------------------- | ------------------------------------------------------ |
| `setEnabled(bool)` / `isEnabled()` / `isActive()` | 开关；`At.blur.enabled` 字段读写等价                   |
| `setAlgorithm(nameOrFn)` / `getAlgorithm()`       | 选择算法或自定义函数                                   |
| `setStrength(n)` / `getStrength()`                | 模糊强度（≥1）                                         |
| `beginFrame()` / `endFrame()`                     | 每帧包住绘制；返回是否生效                             |
| `drawBackdrop(x, y, w, h, radius)`                | 在指定区域绘制模糊背景；组件内部调用，返回是否绘制     |
| `registerAlgorithm(name, fn)` / `getAlgorithms()` | 注册/列出算法                                          |
| `stats()`                                         | `{ frames, backdrops, snapshots }`，排查性能与是否触发 |
| `getMSAA()` / `getMaxMSAA()`                      | 当前实际生效的 MSAA 采样数 / 设备支持的最大采样数      |
| `getError()` / `reset()`                          | 失败原因 / 清缓存重试                                  |

## 性能与限制

- 每个触发模糊的组件，每帧要做**一次全画布拷贝**（snapshot）+ 若干次模糊 pass；组件多时开销明显，建议只给控制台、弹窗这类少数面板使用。
- 内部 scene canvas 会跟随窗口的 MSAA（`love.window.getMode()` 里的 `msaa`）；`At/config.lua` 的 `render.msaa` 为 4 时模糊路径也保持抗锯齿。MSAA 会增加显存与带宽开销，低端设备可以改成 2 或 0。
- 模糊区域按组件大小分配缓存画布，尺寸变化会重新创建（`At.blur.reset()` 可强制清理）。
- 需要 LÖVE 11+（canvas / shader / stencil）。不支持 canvas 时 `At.blur` 自动关闭并通过 `At.log.warn` 提示，组件退回普通半透明绘制。
- LÖVE 12 用 `love.graphics.setStencilMode` 写/测/复位模板，LÖVE 11 用 `love.graphics.stencil` + `setStencilTest`；代码按能力检测自动选择，不按版本号分支。模板不可用时退化为普通矩形绘制，不会因此关闭整个模糊功能。窗口需要在 `conf.lua` 里开启 `t.window.stencil = true`（LÖVE 11/12 默认也是开启的，仓库的 `conf.lua` 已显式声明）。
- stencil 不可用时退化为矩形裁剪，圆角处会露出一点直角边缘。
- `beginFrame` 会按 `love.graphics.getBackgroundColor()` 清空内部 canvas；如果你的场景本身是透明的，请自行在 `beginFrame` 后先画背景。
- 模糊源是"当前帧、组件之前的内容"，不依赖上一帧，所以滚动/拖动时没有延迟。

## 示例

```lua
local At = require("At.At")

At.blur.setEnabled(true)
At.blur.setAlgorithm("downscale")   -- 低端设备更稳
At.blur.setStrength(10)

local console = At.Console{ x = 20, y = 20, w = 560, h = 240 }

function love.draw()
    At.blur.beginFrame()
    game:draw()
    console:draw()                  -- alpha = 205，自动毛玻璃
    At.blur.endFrame()
end

function love.keypressed(key)
    if key == "f3" then
        At.blur.enabled = not At.blur.isEnabled()
    end
end
```
