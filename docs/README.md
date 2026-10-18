# AtLua 使用文档

AtLua 是一个 LÖVE (Love2D) 的轻量 UI 组件库：纯 Lua、无第三方依赖，组件自带几何、状态与事件分发，`At.Panel` 提供 CSS 子集式的自动布局。

## 运行、测试与打包

在项目根目录执行：

```bash
love .                # 运行演示程序（需要装了 LÖVE 11.x）
lua test_smoke.lua    # 无头逻辑测试，不需要 LÖVE，成功时打印 SMOKE OK
./pack.sh             # 打包成 AtLua.love；./pack.sh MyGame 输出 MyGame.love
```

## 快速开始

把库入口接到 LÖVE 的回调上即可。下面这份骨架可以直接跑：

```lua
local At = require("At.At")

local card
local nameInput
local submitBtn

function love.load()
    At.font.init(16)

    nameInput = At.TextInput{
        w = "100%", placeholder = "昵称",
    }
    submitBtn = At.Button{
        w = "100%", text = "提交",
        onClick = function()
            print("你好，" .. nameInput:getText())
        end,
    }
    card = At.Panel{
        x = 40, y = 40, w = 320, h = "auto",
        gap = 12, padding = 16, radius = 14,
        background = "#242A34",
        children = {
            At.Label{ text = "示例" },
            nameInput,
            submitBtn,
        },
    }
end

function love.update(dt)
    At.update(dt)
end

function love.draw()
    card:draw()
end

function love.mousepressed(x, y, button)
    At.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    At.mousereleased(x, y, button)
end

function love.textinput(text)
    At.textinput(text)
end

function love.keypressed(key)
    At.keypressed(key)
end
```

要点：

- `At.font.init(16)` 必须在任何文字绘制之前调用。
- `love.update` 里必须调用 `At.update(dt)`，否则悬停、涟漪、开关与滑动条动画都不会推进。
- 每个组件都要在 `love.draw` 里 `:draw()`；`Panel` 会顺带画它的子组件。
- 文本输入框还需要 `love.textinput` 与 `love.keypressed` 两条接线，否则无法输入和提交。

## 配置

集中在 [`At/config.lua`](../At/config.lua)，改默认值或运行时调整后调用 `At.config.apply()`：

```lua
At.config.blur.enabled = true          -- 背景模糊（毛玻璃）
At.config.blur.algorithm = "downscale"
At.config.log.level = "debug"          -- 日志等级
At.config.log.file = true              -- 同时写文件
At.config.font.size = 16               -- At.font.init() 的默认字号
At.config.apply()
```

| 配置段 | 字段 |
| --- | --- |
| `blur` | `enabled` / `algorithm` / `strength` |
| `log` | `level` / `print` / `maxEntries` / `file` / `filePattern` |
| `font` | `size` / `main` / `emoji` |

`At.lua` 启动时会自动 `apply()` 一次；之后改 `At.config` 需要再调 `apply()`。

## 组件一览

| 组件 | 一句话作用 | 文档 |
| --- | --- | --- |
| `At.Panel` | CSS 子集式布局容器，可做卡片背景 | [components.md#at-panel](components.md#at-panel) |
| `At.Label` | 文字标签，支持换行与对齐 | [components.md#at-label](components.md#at-label) |
| `At.Button` | 带状态、涟漪、阴影与回调的按钮 | [components.md#at-button](components.md#at-button) |
| `At.TextInput` | 单行输入框，支持密码、回车提交、Esc 失焦 | [components.md#at-textinput](components.md#at-textinput) |
| `At.Switch` | 带过渡动画的开关 | [components.md#at-switch](components.md#at-switch) |
| `At.Checkbox` | 多选框，点击整行切换 | [components.md#at-checkbox](components.md#at-checkbox) |
| `At.RadioGroup` | 单选组，`value` 是 1 基下标 | [components.md#at-radiogroup](components.md#at-radiogroup) |
| `At.Slider` | 滑动条，支持步进、拖动与方向键 | [components.md#at-slider](components.md#at-slider) |
| `At.ProgressBar` | 确定性进度条，填充宽度弹簧过渡 | [components.md#at-progressbar](components.md#at-progressbar) |
| `At.LoadingBar` | 不确定性进度条，高光循环滑动 | [components.md#at-loadingbar](components.md#at-loadingbar) |
| `At.ScrollView` | 可滚动视口：横纵自动滚动条、平滑滚动、惯性、触顶触底光效 | [components.md#at-scrollview](components.md#at-scrollview) |
| `At.Console` | 浮动调试控制台：显示 `At.log` 日志、着色、可拖动 | [components.md#at-console](components.md#at-console) |

### 动画

组件默认带过渡动画，统一由 `At.motion` 的弹簧驱动：

- `At.Switch` 旋钮、`At.Checkbox` 勾、`At.RadioGroup` 圆点：状态变化时弹入/缩回。
- `At.TextInput` 聚焦边框、`At.Button` 悬停/按下高光：颜色与宽度平滑过渡。
- `At.ProgressBar` 的填充宽度；`At.ScrollView` 滚动条碰到指针时变宽、触顶/触底有边缘光（按轴隔离）；`At.Console` 打开/关闭时淡入淡出并轻微滑动。

所有动画都在 `At.update(dt)` 里推进，参数（`springStiffness` / `springDamping`）见各组件属性表；`animate = false` 可关闭。
想给自己的组件加动画，直接用公开的 `At.motion`：

```lua
local s = At.motion.spring{ value = 0, stiffness = 320, damping = 26 }
s:setTarget(1)
function love.update(dt) s:update(dt) end   -- 之后读 s.value（0..1，可能过冲）
```

`At.motion` 还提供 `damp(current, target, speed, dt)`、`easeIn/easeOut/easeInOut(t)`；弹簧内部按固定子步积分，掉帧也不会发散。

布局规则见 [layout.md](layout.md)，每个组件的完整属性/方法/回调见 [components.md](components.md)，
日志与浮动控制台见 [logging.md](logging.md)，背景模糊（毛玻璃）见 [blur.md](blur.md)。

## 事件模型

组件**创建即自动登记**到 `At.registry`（传 `autoRegister = false` 时需手动 `At.add`）。调用方不需要逐个转发事件，只要接四个入口：

- `At.mousepressed(x, y, button)`：按创建顺序**倒序**派发——后创建的画在上层、先收到事件；**第一个返回 `true` 的组件消费事件后立即停止**。只处理左键（`button == 1`）。
- `At.mousereleased(x, y, button)`：**广播**给所有组件（按下的组件可能已不在指针下方，需要它自己收尾），任意组件消费则返回 `true`。
- `At.textinput(text)` / `At.keypressed(key, ...)`：**只发给当前焦点组件**；没有焦点时不处理。
- `At.wheelmoved(dx, dy)`：按倒序派发给实现了滚轮事件的组件（目前是 `At.ScrollView`），第一个消费即停。
- 点击空白处、或点击焦点组件之外的其他组件，都会**收走键盘焦点**（`At.getFocus()` 变 `nil`）。

```lua
local focused = At.getFocus()   -- 当前焦点组件或 nil
At.clearFocus()                 -- 主动清空焦点
```

`At.Panel` 不登记、不消费鼠标事件，所以容器不会挡住子组件；`At.ScrollView` 会登记，但它只接管"落在空白处的拖动"与滚轮，点在子组件上仍然交给子组件。

焦点组件是 `At.TextInput` 时，聚焦会自动调用 `love.keyboard.setTextInput(true, x, y, w, h)` 唤起移动端软键盘，失焦时收起。

## 约定

- **颜色 alpha 是 0–255**，不是 0–1。内部会转成 LÖVE 需要的 0–1；对外始终传 0–255。
- **坐标是左上角 + 宽高**：几何参数统一为 `x, y, w, h, radius`，`x/y` 指组件左上角，不是中心。
- **绘制位置对齐整数像素**：布局算出的坐标、`ScrollView` 的滚动量、文字位置都会四舍五入到整数（`At.pixel.round`），这样文字不虚、1px 边框不毛。需要亚像素动画时请自己在绘制前处理。
- **模块命名沿用现状**：大写开头的是 `At`、`SDF`、`Ripple`、`Button`、`Panel`、`Label`、`TextInput`、`Switch`、`Checkbox`、`RadioGroup`、`Slider`、`ScrollView`、`Component`；小写的是 `color`、`shadow`、`input`、`font`、`layout`、`registry`。
- **`require` 路径从源码根开始、不带 `.lua`**：`local At = require("At.At")`。
- **`At.button`（立即模式）与 `At.Button`（组件式）不是一回事**：
    - `At.button(x, y, w, h, res, hex, alpha, shadow, shadowArgs)` 只画一个矩形，无状态、无涟漪、无回调，还会把当前颜色留成按钮色，仅用于兼容旧代码。
    - `At.Button{...}` 是组件：自带悬停/按下/禁用、涟漪、文字、回调和注册表生命周期，新代码请用它。

## 常见问题

**为什么涟漪不动？**

没有调用 `At.update(dt)`。涟漪、开关动画和滑动条拖动都在 `update` 里推进；不调用会卡在第一帧，且涟漪不会回收。

**为什么百分比宽度变成了 0 或 auto？**

百分比需要父容器有可用宽度。父容器 `w = "auto"` 且没有 `_availW` 时，`"50%"` 会**退化成 auto**，按组件内容测量（可能看起来像 0，例如空标签）。给父 `Panel` 一个数字宽度，或显式调用 `panel:layout(availW, availH)`。

**为什么按钮不响应？**

按顺序检查：`enabled` 是否被设为 `false`；组件是否 `passthrough = true`；是否用了 `autoRegister = false` 又没有 `At.add`；是否被更上层组件先消费了事件；是否按的不是左键。`Panel` 本身不接收点击，点容器空白不会触发任何按钮。

**为什么文字颜色不对？**

旧式 `At.button` 会把 `love.graphics` 的当前颜色留成按钮色，后续直接 `love.graphics.print` 就会带上这个颜色。改用 `At.Button`（绘制后会恢复颜色），或在自绘文字前显式 `love.graphics.setColor(1, 1, 1, 1)`。

**输入框点了但弹不出软键盘？**

先确认 `love.textinput` 已接到 `At.textinput`（Windows/macOS 上不需要软键盘，输入框也能收到字符）。移动端需要系统层支持：聚焦时组件会调用 `love.keyboard.setTextInput(true, x, y, w, h)`；如果仍然不弹，检查 LÖVE 版本是否 ≥ 11、设备是否禁用了系统键盘。软键盘挡住控件时，把表单放进 `At.ScrollView` 并在 `onFocus` 里 `view:scrollToVisible(self)`。

**横屏/小窗口下内容被截断？**

`At.Panel` 只负责排版，不裁剪也不滚动。把内容放进 `At.ScrollView`：它按视口宽度排版内容、裁剪超出部分，并支持滚轮与拖动滚动。记得把 `love.wheelmoved` 接到 `At.wheelmoved`。

**卡片/按钮底部有一圈发黑的光晕？**

旧版 `shadow` 把多层半透明黑矩形直接叠加（20 层各约 7.5%），累积后接近 80% 不透明，看起来就是黑底。现在已经按层数归一化：`shadowArgs` 里颜色的 alpha 即整体最大不透明度。确实不想要阴影时把它设为 `shadow = false`。

**Android 上看不到日志 / 控制台？**

Android 没有终端窗口，`At.log` 默认会把日志 `print` 到 **logcat**（`adb logcat -s love`），也可以用手机上的 logcat 阅读器。想把日志留在设备上就开文件输出：`At.log.setFile(true)`，文件在应用存档目录里（路径见 `At.log.getFilePath()`，Android 上是 `.../files/save/YYYY-MM-DD HH:MM:SS.log`）。浮动控制台默认隐藏，但右上角有个 `LOG` 标签，点它就能打开（移动端没有 `F1`）；打开后点标题栏的 `C` 清空、`×` 关闭。

**半透明组件没有毛玻璃效果？**

需要同时满足：`At.blur.setEnabled(true)`，并且绘制包在 `At.blur.beginFrame()` / `At.blur.endFrame()` 之间（否则拿不到背景快照）；组件背景的 `alpha` 必须小于 255（控制台默认 205，Panel/输入框/按钮要把 alpha 调低）。细节见 [blur.md](blur.md)。

**为什么数字和空格看起来特别宽？**

字体主次反了。`At/core/font.lua` 必须以**主字体**（Noto Sans SC）为当前字体、emoji 字体只作 `setFallbacks`；若反过来把 emoji 当当前字体，数字、空格、`#`/`*` 会取到 Noto Emoji 里为 keycap 设计的长宽字。

**为什么文字/空白区域拖不动滚动？**

`ScrollView` 只把"可交互子组件"当作拦截目标。`At.Label` 是**被动组件**（`interactive = false`），不消费点击，所以压在文字上也能拖。若你自己写了纯展示组件却拖不动，把它设为 `interactive = false`；反之，如果某个区域"明明不该拦却拦住了"，检查那个组件是不是实现了 `_press`（实现了就会被视为可交互）。

**为什么改了文本，尺寸没变？**

用 `label:setText(...)` / `button:setText(...)`，它们会调用 `invalidateSize()` 让 auto 尺寸重新测量。直接改 `self.text` 不会触发重排。

## 许可证

- **本项目代码**：MIT，见根目录 [`LICENSE`](../LICENSE)。
- **字体**：`At/assets/font.ttf` 是 Noto Sans SC Bold，`At/assets/emoji.ttf` 是 Noto Emoji，
  均为 **SIL Open Font License 1.1**，版权分别属于 Adobe / Google LLC。
  许可全文与逐字体版权声明见 [`LICENSES/`](../LICENSES/)，总览见
  [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)。

OFL 要求分发字体时携带版权声明与许可全文，因此 `LICENSE` 与 `LICENSES/` **也会被打进
`.love` 包**；替换或子集化字体时必须同步更新这两处的说明。
