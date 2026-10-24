# 组件

所有组件都继承 `At.Component`，共享同一套协议：`draw()` 绘制、`update(dt)` 推进悬停与动画、`mousepressed(...)` / `mousereleased(...)` 处理鼠标、`measure(availW, availH)` 报告自然尺寸、`destroy()` 注销并释放。组件**创建即自动登记到 `registry`**（`autoRegister = false` 时需手动 `At.add`；`At.Panel` 是例外，默认不登记），事件由 `At.mousepressed / At.mousereleased / At.textinput / At.keypressed` 统一分发；**同一时刻只有一个组件持有键盘焦点**，`textinput` 与 `keypressed` 只发给它。

公共几何与状态成员：

| 成员                                                                      | 说明                                                                      |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `:draw()`                                                                 | 保存并恢复颜色/字体/线宽后绘制；`Panel` 会先排版再画子项                  |
| `:update(dt)`                                                             | 由 `At.update(dt)` 调用：更新悬停、动画与拖拽                             |
| `:mousepressed(mx, my, button)`                                           | 命中并消费返回 `true`；只处理左键（`button == 1`）                        |
| `:mousereleased(mx, my, button)`                                          | 松开收尾；`Panel` 不参与                                                  |
| `:measure(availW, availH)`                                                | 返回自然尺寸，供 `w/h = "auto"` 使用                                      |
| `:destroy()`                                                              | 从注册表注销；`Panel` 会连带销毁子组件                                    |
| `:contains(px, py)`                                                       | 用传入坐标做圆角命中判断                                                  |
| `:rect()`                                                                 | 返回 `{ x, y, w, h, radius }`                                             |
| `:setRect(x, y, w, h, radius?)` / `:setPosition(x, y)` / `:setSize(w, h)` | 改几何                                                                    |
| `:setEnabled(bool)` / `:setVisible(bool)`                                 | 禁用会中止按压并失焦；隐藏会跳过绘制与更新                                |
| `:isHovered()` / `:isPressed()` / `:isEnabled()` / `:isVisible()`         | 状态查询                                                                  |
| `:isInteractive()`                                                        | 是否响应鼠标：显式 `interactive` 优先，否则看有没有实现 `_press/_release` |
| `:focus()` / `:blur()` / `:isFocused()`                                   | 焦点控制（同一时刻只有一个）                                              |
| `:declaredWidth()` / `:declaredHeight()` / `:invalidateSize()`            | 原始尺寸规格与重新测量                                                    |

`x` / `y` 默认都是 `0`；`enabled`、`visible` 默认 `true`；`autoRegister` 默认 `true`；`passthrough` 默认 `false`。颜色 alpha 一律是 **0–255**，坐标一律是**左上角 + 宽高**。

颜色默认值写的是**主题 token**（`"@primary"`、`"@text"` 这类字符串），绘制时由 `At.theme` 解析，
所以 `At.theme.set{...}` 换主题后已有组件会立即变色。所有颜色属性也接受普通 `"#RRGGBB"`；
显式给 hex 的组件不跟随主题。token 列表与主题 API 见 [theme.md](theme.md)。

**背景模糊**：`At.Panel`、`At.Console`、`At.ScrollView`、`At.TextInput`、`At.Button` 在背景 `alpha < 255`
且 `At.blur` 启用时会自动在背后绘制模糊（毛玻璃），组件本身不需要额外参数。用法见 [blur.md](blur.md)。

**At.Console 是浮动调试面板**：显示 `At.log` 的全部日志，可拖动、可滚动、可显示/隐藏；
它必须最后创建和绘制，才能浮在最上层（详见 [`logging.md`](logging.md)）。

**被动组件**：只做展示、不响应鼠标的组件（`At.Label`）会自动判定为不可交互（`interactive = false`），它们不会消费点击、也不会挡住 `ScrollView` 的拖动。自己写的纯展示组件请显式设 `interactive = false`。

**动画**：开关、勾选、单选圆点、输入框聚焦边框、按钮悬停/按下高光、进度条填充、滚动条变宽、`ScrollView` 触顶/触底回弹、控制台开关都默认带过渡，由 `At.motion` 的弹簧驱动（`animate = true`）。这些动画只在 `At.update(dt)` 里推进，不调用就停在第 0 帧；开关/勾选/单选/输入框/进度条可用 `animate = false` 关闭，或用 `springStiffness` / `springDamping` 调整手感。具体参数见各组件的属性表。

## At.Panel

布局容器：用 CSS 子集把子组件排成一行或一列，可选背景、描边、圆角、阴影，做成卡片。

### 属性

| 属性           | 类型                     | 默认值     | 说明                                                                                                                                                       |
| -------------- | ------------------------ | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `x` / `y`      | 数字                     | `0`        | 左上角坐标                                                                                                                                                 |
| `w` / `h`      | 数字 / 百分比 / `"auto"` | `"auto"`   | 容器尺寸；auto 由子项撑开                                                                                                                                  |
| `direction`    | 字符串                   | `"column"` | 主轴方向：`"column"` / `"row"`                                                                                                                             |
| `gap`          | 数字                     | `8`        | 子项间距                                                                                                                                                   |
| `padding`      | 数字或表                 | `0`        | 内边距，表为 `{ left, top, right, bottom }`                                                                                                                |
| `align`        | 字符串                   | `"start"`  | 交叉轴对齐：`start` / `center` / `end` / `stretch`                                                                                                         |
| `justify`      | 字符串                   | `"start"`  | 主轴分布：`start` / `center` / `end` / `space-between`                                                                                                     |
| `children`     | 表                       | `{}`       | 子组件数组                                                                                                                                                 |
| `background`   | hex / token              | `nil`      | 背景色                                                                                                                                                     |
| `borderColor`  | hex / token              | `nil`      | 描边色                                                                                                                                                     |
| `borderWidth`  | 数字                     | `1`        | 描边线宽                                                                                                                                                   |
| `radius`       | 数字                     | `0`        | 圆角半径                                                                                                                                                   |
| `alpha`        | 数字 0–255               | `255`      | 背景与描边的透明度                                                                                                                                         |
| `shadow`       | 布尔或表                 | `false`    | `true` 用默认阴影；传表等价于直接给 `shadowArgs`。阴影算法由 `At.config.shadow.algorithm` 决定；`shadowArgs` 里颜色的 alpha（0–1）是整体最大不透明度       |
| `shadowArgs`   | 表                       | `nil`      | `{ 颜色, spread, layers, offsetX, offsetY }`；`nil` 时使用 `At.config.shadow` 的默认值（默认深色主题色、较小的 spread/偏移）。颜色可传 RGBA 表或 hex/token |
| `autoRegister` | 布尔                     | `false`    | 容器不登记到 registry                                                                                                                                      |
| `passthrough`  | 布尔                     | `true`     | 不消费鼠标事件                                                                                                                                             |

### 方法

| 方法                       | 说明                                                               |
| -------------------------- | ------------------------------------------------------------------ |
| `:add(child)`              | 追加子组件并让 auto 尺寸失效，返回该子组件                         |
| `:remove(child)`           | 移除子组件，返回是否找到                                           |
| `:clear()`                 | 清空子组件列表                                                     |
| `:measure(availW, availH)` | 按内容测量应有尺寸，不修改坐标                                     |
| `:layout(availW, availH)`  | 立即重排一次，返回 `w, h`；参数决定百分比基数                      |
| `:draw()`                  | 先 `layout()` 再画背景，最后画每个子组件；每次绘制都会重排（幂等） |
| `:destroy()`               | 先销毁全部子组件，再注销自己                                       |

### 回调

无。`Panel` 本身**不接收鼠标事件**（`passthrough = true`）且**不登记到 registry**（`autoRegister = false`），点击由子组件自己处理。

### 示例

```lua
local At = require("At.At")

local card = At.Panel{
    x = 40, y = 40, w = 360, h = "auto",
    gap = 12, padding = 16, radius = 14,
    background = "@surface",
    children = {
        At.Label{ text = "登录" },
        At.Button{ w = "100%", text = "确定" },
    },
}

card:draw()
```

## At.Label

文字标签：布局里最常用的说明与占位组件，支持换行和相对自身宽度的对齐。

### 属性

| 属性         | 类型                     | 默认值    | 说明                                           |
| ------------ | ------------------------ | --------- | ---------------------------------------------- |
| `x` / `y`    | 数字                     | `0`       | 左上角坐标                                     |
| `w` / `h`    | 数字 / 百分比 / `"auto"` | `"auto"`  | 尺寸；auto 时按文字测量                        |
| `text`       | 字符串                   | `""`      | 显示的文字                                     |
| `color`      | hex / token              | `"@text"` | 文字颜色                                       |
| `alpha`      | 数字 0–255               | `255`     | 透明度                                         |
| `align`      | 字符串                   | `"left"`  | 相对自身宽度：`left` / `center` / `right`      |
| `wrap`       | 布尔                     | `false`   | 自动换行；为 `true` 时需要给定宽度             |
| `lineHeight` | 数字                     | `1.2`     | 行高倍数                                       |
| `fontSize`   | 数字                     | 未设置    | 缺省沿用当前字体；设置后走 `At.font.get(size)` |

### 方法

| 方法               | 说明                                                     |
| ------------------ | -------------------------------------------------------- |
| `:setText(text)`   | 改文字并让 auto 尺寸失效，下次绘制/排版重新测量          |
| `:measure(availW)` | 返回文字宽与行高；`wrap = true` 时返回限定宽度与行数高度 |

### 回调

无。

### 示例

```lua
local At = require("At.At")

local hint = At.Label{
    x = 20, y = 20, w = 240,
    text = "这是一段会自动换行的说明文字。",
    wrap = true, lineHeight = 1.4,
    color = "@textMuted",
}

hint:setText("改短一点")
hint:draw()
```

## At.Button

按钮：几何、样式、悬停/按下/禁用状态、涟漪和居中文字全部自带，是库里的主按钮组件。

### 属性

| 属性                                | 类型                     | 默认值        | 说明                                                                                                                                                       |
| ----------------------------------- | ------------------------ | ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `x` / `y`                           | 数字                     | `0`           | 左上角坐标                                                                                                                                                 |
| `w` / `h`                           | 数字 / 百分比 / `"auto"` | `120` / `44`  | 尺寸；auto 时按文字加内边距测量                                                                                                                            |
| `radius`                            | 数字                     | `10`          | 圆角半径                                                                                                                                                   |
| `color`                             | hex / token              | `"@primary"`  | 常态底色                                                                                                                                                   |
| `alpha`                             | 数字 0–255               | `255`         | 透明度；禁用时按 `alpha * 0.45` 变淡                                                                                                                       |
| `hoverColor`                        | hex / token              | `nil`         | 悬停底色；缺省由 `color.shade(color, 0.10)` 推导                                                                                                           |
| `pressedColor`                      | hex / token              | `nil`         | 按下底色；缺省由 `color.shade(color, -0.12)` 推导                                                                                                          |
| `shadow`                            | 布尔或表                 | `true`        | `true` 用默认阴影；传表等价于直接给 `shadowArgs`；算法见 [shadow.md](shadow.md)                                                                            |
| `shadowArgs`                        | 表                       | `nil`         | `{ 颜色, spread, layers, offsetX, offsetY }`；`nil` 时使用 `At.config.shadow` 的默认值（默认深色主题色、较小的 spread/偏移）。颜色可传 RGBA 表或 hex/token |
| `ripple`                            | 布尔或表                 | `true`        | `true` / `false` / `{ color = "@white", alpha = 255, enabled = true }`                                                                                     |
| `text`                              | 字符串                   | `nil`         | 按钮文字；`nil` 或 `""` 时不画文字                                                                                                                         |
| `textColor`                         | hex / token              | `nil`（自动） | 文字颜色；缺省按底色对比度自动选 `@text` / `@onPrimary`                                                                                                    |
| `fontSize`                          | 数字                     | `nil`         | 缺省沿用当前字体                                                                                                                                           |
| `paddingX` / `paddingY`             | 数字                     | `16` / `10`   | 仅用于 auto 尺寸                                                                                                                                           |
| `enabled`                           | 布尔                     | `true`        | 禁用后变淡且不响应事件                                                                                                                                     |
| `animate`                           | 布尔                     | `true`        | 悬停/按下的高光过渡；关掉则高光立即到位                                                                                                                    |
| `springStiffness` / `springDamping` | 数字                     | `500` / `30`  | 高光过渡的弹簧刚度 / 阻尼                                                                                                                                  |

### 方法

| 方法                               | 说明                                      |
| ---------------------------------- | ----------------------------------------- |
| `:setText(text)`                   | 改文字并让 auto 尺寸失效                  |
| `:setColor(hex, alpha?)`           | 改底色，可选同时改 alpha                  |
| `:setRippleEnabled(bool)`          | 开关涟漪                                  |
| `:rippleCount()`                   | 当前存活的涟漪数量（调试用）              |
| `:fillColor()` / `:fillAlpha()`    | 返回当前应使用的底色 / 透明度             |
| `:measure()`                       | 按文字加 `paddingX/paddingY` 返回自然尺寸 |
| `At.Button.setStyle(button, opts)` | 批量覆盖样式并重建涟漪                    |

公共方法（`setEnabled`、`setRect`、`isHovered`、`isPressed`、`destroy` 等）见本节开头的公共成员表。

### 回调

| 回调        | 参数                     | 时机                                                  |
| ----------- | ------------------------ | ----------------------------------------------------- |
| `onPress`   | `(self, mx, my)`         | 在按钮内按下                                          |
| `onRelease` | `(self, mx, my, inside)` | 每次松开都调用；`inside` 表示松开时指针是否仍在按钮内 |
| `onClick`   | `(self, mx, my)`         | 松开时指针在按钮内且 `enabled`                        |

按压语义（容易写错）：

- 在按钮内按下 → 开始一次按压会话，加涟漪，触发 `onPress`。
- 按住拖出按钮 → 涟漪淡出，`isPressed()` 变 `false`，但会话保留。
- 拖回按钮内 → 涟漪重新出现，`isPressed()` 变 `true`。
- 最后在按钮内松开 → 触发 `onClick`；**拖出再拖回也算点击**。
- 无论在哪里松开，都会调用一次 `onRelease`；`inside` 为 `false` 时没有 `onClick`。

### 示例

```lua
local At = require("At.At")

local btn = At.Button{
    x = 60, y = 120, w = 180, h = 48, radius = 12,
    color = "@primary", text = "确定",
    onClick = function(self, mx, my)
        print("点击", self.text, mx, my)
    end,
}

btn:draw()
btn:setEnabled(false)   -- 禁用后变淡且不再响应
```

## At.TextInput

单行文本输入框：点击或拖动定位光标，支持中间插入/删除、方向键移动，回车提交，Esc 失焦。

### 属性

| 属性                                          | 类型                     | 默认值          | 说明                                      |
| --------------------------------------------- | ------------------------ | --------------- | ----------------------------------------- |
| `x` / `y`                                     | 数字                     | `0`             | 左上角坐标                                |
| `w` / `h`                                     | 数字 / 百分比 / `"auto"` | `220` / `44`    | 尺寸；auto 时按文字与内边距测量           |
| `radius`                                      | 数字                     | `10`            | 圆角半径                                  |
| `text`                                        | 字符串                   | `""`            | 当前文本                                  |
| `placeholder`                                 | 字符串                   | `""`            | 无文本时的提示文字                        |
| `fontSize`                                    | 数字                     | `16`            | 字号                                      |
| `paddingX` / `paddingY`                       | 数字                     | `12` / `10`     | 文字内边距                                |
| `color`                                       | hex / token              | `"@surfaceAlt"` | 底色                                      |
| `alpha`                                       | 数字 0–255               | `255`           | 透明度                                    |
| `borderColor`                                 | hex / token              | `"@border"`     | 未聚焦描边色                              |
| `focusBorderColor`                            | hex / token              | `"@primary"`    | 聚焦描边色                                |
| `textColor`                                   | hex / token              | `"@text"`       | 文本颜色                                  |
| `placeholderColor`                            | hex / token              | `"@textFaint"`  | 提示文字颜色                              |
| `caretColor`                                  | hex / token              | `"@primary"`    | 光标颜色                                  |
| `caretWidth`                                  | 数字                     | `2`             | 光标宽度                                  |
| `caretPeriod`                                 | 数字                     | `0.5`           | 闪烁周期（秒），`0` 表示常亮              |
| `maxLength`                                   | 数字                     | `0`             | 最大字符数，`0` 表示不限；按 UTF-8 字符计 |
| `password`                                    | 布尔                     | `false`         | 密码模式，按字符数显示掩码                |
| `maskChar`                                    | 字符串                   | `"*"`           | 密码模式的掩码字符                        |
| `onChange`                                    | 函数                     | `nil`           | 文本变化回调                              |
| `onSubmit`                                    | 函数                     | `nil`           | 回车提交回调                              |
| `animate`                                     | 布尔                     | `true`          | 聚焦/失焦时边框颜色与线宽的过渡           |
| `focusSpringStiffness` / `focusSpringDamping` | 数字                     | `380` / `28`    | 聚焦过渡的弹簧刚度 / 阻尼                 |
| `onFocus`                                     | 函数                     | `nil`           | 获得焦点时（移动端会同时唤起软键盘）      |
| `onBlur`                                      | 函数                     | `nil`           | 失去焦点时（软键盘随之收起）              |

### 方法

| 方法                      | 说明                                                                                              |
| ------------------------- | ------------------------------------------------------------------------------------------------- |
| `:getText()`              | 返回当前文本                                                                                      |
| `:getCaret()`             | 返回光标位置：`0` = 第一个字符前，`length()` = 末尾                                               |
| `:setCaret(index)`        | 设置光标位置（自动夹到 `0..length`），并让文本水平滚动到光标可见                                  |
| `:setText(text, silent?)` | 设文本并把光标移到末尾；`silent` 为真时不触发 `onChange`                                          |
| `:clear()`                | 清空文本（等价于 `setText("")`，会触发 `onChange`）                                               |
| `:length()`               | 返回 UTF-8 字符数                                                                                 |
| `:focus()` / `:blur()`    | 获取 / 放弃键盘焦点                                                                               |
| `:textinput(t)`           | 追加输入（由 `At.textinput` 转发）                                                                |
| `:keypressed(key)`        | 处理 `backspace` / `delete` / `left` / `right` / `home` / `end` / `return` / `kpenter` / `escape` |
| `:measure()`              | 按文本或 placeholder 返回自然尺寸                                                                 |

### 回调

| 回调       | 参数           | 时机                                              |
| ---------- | -------------- | ------------------------------------------------- |
| `onChange` | `(text, self)` | 输入、退格、`setText`（非 silent）时              |
| `onSubmit` | `(text, self)` | 按 `return` / `kpenter` 时；提交后不失焦          |
| `onFocus`  | `(self)`       | 点击或 `:focus()` 获得焦点时                      |
| `onBlur`   | `(self)`       | 点击空白/其他组件、`Esc`、`:blur()`、禁用或销毁时 |

注意：

- **光标可以点击定位**：点击文字之间的位置会吸附到最近的字符边界；按住拖动可以连续移动光标。
- **中间编辑**：`textinput` 在光标处插入，`backspace` 删除光标前一个字符，`delete` 删除光标后一个字符；`left` / `right` / `home` / `end` 移动光标。光标位置是 UTF-8 **字符下标**（0 到字符数），不是字节下标。
- **水平滚动**：文本比输入框宽时，光标移动/输入/点击会让文本水平滚动，保证光标始终在可视区内；失焦后回到开头。
- 密码模式按**字符数**生成掩码（`"密码"` 显示为两个 `*`），不是按字节；光标同样按掩码字符定位。
- `maxLength` 按字符数判断，插入多字符文本时也按总字符数计算。
- 不支持选区、复制/粘贴菜单、撤销/重做；这些需要额外的编辑状态，不在当前实现范围内。
- `escape` 失焦；点击空白或其他组件同样会失焦（由 registry 处理）。
- 文字与光标绘制会与外层裁剪求交（放在 `ScrollView` 里也不会溢出视口），位置对齐到整数像素。
- 只有焦点组件会收到 `At.textinput` / `At.keypressed`。
- 输入框是**可交互**组件（实现了 `_press`），所以会正常拦截点击；旁边的 `At.Label` 不会。
- **移动端软键盘**：聚焦时调用 `love.keyboard.setTextInput(true, x, y, w, h)` 并带上输入框矩形，系统据此弹出并定位软键盘；失焦时调用 `setTextInput(false)` 收起。切到后台请在 `love.focus(false)` 里调 `At.clearFocus()`。
- 软键盘会遮住下半屏，建议把表单放进 `At.ScrollView`，并在 `onFocus` 里调用 `view:scrollToVisible(self)`。

### 示例

```lua
local At = require("At.At")

local name = At.TextInput{
    x = 40, y = 40, w = 240,
    placeholder = "用户名", maxLength = 16,
    onChange = function(text, self) print("输入", text) end,
    onSubmit = function(text, self) print("提交", text) end,
}

name:setText("阿特")   -- 会触发 onChange
name:focus()
name:draw()
```

## At.Switch

开关：点击切换布尔值，旋钮带过渡动画。

### 属性

| 属性                                | 类型        | 默认值       | 说明                                                |
| ----------------------------------- | ----------- | ------------ | --------------------------------------------------- |
| `x` / `y`                           | 数字        | `0`          | 左上角坐标                                          |
| `w` / `h`                           | 数字        | `52` / `28`  | 轨道尺寸                                            |
| `radius`                            | 数字        | `nil`        | 轨道圆角；缺省取 `min(w, h) / 2`（胶囊形）          |
| `value`                             | 布尔        | `false`      | 当前状态                                            |
| `color`                             | hex / token | `"@track"`   | 关闭时的轨道色                                      |
| `onColor`                           | hex / token | `"@primary"` | 打开时的轨道色                                      |
| `knobColor`                         | hex / token | `"@knob"`    | 旋钮颜色                                            |
| `knobInset`                         | 数字        | `3`          | 旋钮与轨道边缘的间距                                |
| `alpha`                             | 数字 0–255  | `255`        | 透明度                                              |
| `animate`                           | 布尔        | `true`       | 是否播放旋钮过渡                                    |
| `springStiffness` / `springDamping` | 数字        | `320` / `26` | 旋钮弹簧刚度 / 阻尼；越大越硬、阻尼越大越不弹       |
| `speed`                             | 数字        | `nil`        | 已弃用；传入时等价于 `springStiffness = speed * 20` |
| `onChange`                          | 函数        | `nil`        | 状态变化回调                                        |

### 方法

| 方法                        | 说明                                               |
| --------------------------- | -------------------------------------------------- |
| `:getValue()`               | 返回当前布尔值                                     |
| `:setValue(value, silent?)` | 设值；`silent` 为真时不触发 `onChange`；返回当前值 |
| `:toggle()`                 | 取反并返回新值                                     |
| `:measure()`                | 使用公共实现，返回声明尺寸                         |

### 回调

| 回调       | 参数            | 时机                                                    |
| ---------- | --------------- | ------------------------------------------------------- |
| `onChange` | `(value, self)` | 用户点击/拖动切换，或非 silent 的 `setValue` / `toggle` |

关于动画 `_t`：

- `_t` 是内部动画进度（`0` 关闭 → `1` 打开），不是公开 API；弹簧会有一点过冲，看起来像"弹"过去。
- `setValue` 只改目标值 `value`；`_t` 在每次 `At.update(dt)` 里由弹簧逼近目标，所以**不调用 `At.update` 时旋钮不会动**。
- 创建时 `_t` 与初始 `value` 对齐，不会从 0 开始播动画；`animate = false` 时立即落位。

### 示例

```lua
local At = require("At.At")

local wifi = At.Switch{
    x = 40, y = 40, value = false,
    onChange = function(value, self) print("开关", value) end,
}

wifi:toggle()          -- 代码里切换，同样触发 onChange

-- 交互：轻点是点击切换；按住后向右拖 → 打开，向左拖 → 关闭。
-- 拖动越过阈值（约宽度的 18%，最少 8px）就切换，松手不会二次切换。
print(wifi:getValue()) -- true
wifi:draw()
```

## At.Checkbox

多选框：方框 + 勾 + 右侧文字，点击整行切换。

### 属性

| 属性                                | 类型                     | 默认值            | 说明                                |
| ----------------------------------- | ------------------------ | ----------------- | ----------------------------------- |
| `x` / `y`                           | 数字                     | `0`               | 左上角坐标                          |
| `w` / `h`                           | 数字 / 百分比 / `"auto"` | `"auto"`          | 尺寸；auto 时按方框、间距和文字测量 |
| `size`                              | 数字                     | `22`              | 方框边长                            |
| `gap`                               | 数字                     | `8`               | 方框与文字的间距                    |
| `radius`                            | 数字                     | `5`               | 方框圆角                            |
| `text`                              | 字符串                   | `""`              | 右侧文字                            |
| `checked`                           | 布尔                     | `false`           | 是否选中                            |
| `color`                             | hex / token              | `"@surfaceAlt"`   | 方框底色                            |
| `borderColor`                       | hex / token              | `"@borderStrong"` | 方框描边色                          |
| `checkColor`                        | hex / token              | `"@primary"`      | 勾的颜色                            |
| `textColor`                         | hex / token              | `"@text"`         | 文字颜色                            |
| `alpha`                             | 数字 0–255               | `255`             | 透明度                              |
| `fontSize`                          | 数字                     | `nil`             | 缺省沿用当前字体                    |
| `animate`                           | 布尔                     | `true`            | 勾从中心弹入/缩回的过渡             |
| `springStiffness` / `springDamping` | 数字                     | `420` / `22`      | 勾动画的弹簧刚度 / 阻尼             |
| `onChange`                          | 函数                     | `nil`             | 选中状态变化回调                    |

### 方法

| 方法                          | 说明                                         |
| ----------------------------- | -------------------------------------------- |
| `:getValue()`                 | 返回是否选中                                 |
| `:setValue(checked, silent?)` | 设选中状态；`silent` 为真时不触发 `onChange` |
| `:toggle()`                   | 取反并返回新状态                             |
| `:setText(text)`              | 改文字并让 auto 尺寸失效                     |
| `:measure()`                  | 返回自然尺寸                                 |

### 回调

| 回调       | 参数              | 时机                                               |
| ---------- | ----------------- | -------------------------------------------------- |
| `onChange` | `(checked, self)` | 用户点击切换，或非 silent 的 `setValue` / `toggle` |

点击整行都有效：命中范围包含方框、间距和右侧文字。

### 示例

```lua
local At = require("At.At")

local remember = At.Checkbox{
    x = 40, y = 40, text = "记住我",
    checked = false,
    onChange = function(checked, self) print("选中", checked) end,
}

remember:setValue(true, true)  -- silent：不触发 onChange
remember:draw()
```

## At.RadioGroup

单选组：一组选项里同时只有一个选中，`value` 是 **1 基下标**。

### 属性

| 属性                                | 类型                     | 默认值            | 说明                                      |
| ----------------------------------- | ------------------------ | ----------------- | ----------------------------------------- |
| `x` / `y`                           | 数字                     | `0`               | 左上角坐标                                |
| `w` / `h`                           | 数字 / 百分比 / `"auto"` | `"auto"`          | 尺寸；auto 时按选项测量                   |
| `options`                           | 表                       | `{}`              | 选项文字数组                              |
| `value`                             | 数字 / `nil`             | `nil`             | 选中项下标（从 1 开始）；`nil` 表示未选中 |
| `direction`                         | 字符串                   | `"column"`        | 排列方向：`"column"` / `"row"`            |
| `gap`                               | 数字                     | `8`               | 选项间距                                  |
| `size`                              | 数字                     | `20`              | 圆形标记直径                              |
| `textGap`                           | 数字                     | `8`               | 圆形标记与文字的间距                      |
| `color`                             | hex / token              | `"@surfaceAlt"`   | 圆形标记底色                              |
| `borderColor`                       | hex / token              | `"@borderStrong"` | 未选中描边色                              |
| `selectedColor`                     | hex / token              | `"@primary"`      | 选中描边与圆点颜色                        |
| `textColor`                         | hex / token              | `"@text"`         | 文字颜色                                  |
| `alpha`                             | 数字 0–255               | `255`             | 透明度                                    |
| `fontSize`                          | 数字                     | `nil`             | 缺省沿用当前字体                          |
| `animate`                           | 布尔                     | `true`            | 选中圆点弹入、旧圆点缩回的过渡            |
| `springStiffness` / `springDamping` | 数字                     | `420` / `22`      | 圆点动画的弹簧刚度 / 阻尼                 |
| `onChange`                          | 函数                     | `nil`             | 选中项变化回调                            |

### 方法

| 方法                        | 说明                                         |
| --------------------------- | -------------------------------------------- |
| `:getValue()`               | 返回当前 1 基下标，未选中返回 `nil`          |
| `:getLabel()`               | 返回当前选中项的文字，未选中返回 `nil`       |
| `:setValue(index, silent?)` | 设选中下标；`silent` 为真时不触发 `onChange` |
| `:measure()`                | 按选项数量、间距和 `direction` 返回自然尺寸  |

### 回调

| 回调       | 参数                   | 时机                                        |
| ---------- | ---------------------- | ------------------------------------------- |
| `onChange` | `(index, label, self)` | 用户点击某个选项，或非 silent 的 `setValue` |

注意：

- `value` **从 1 开始**，不是 0 基，也不是字符串；传 `nil` 可清空选择。
- 点击在松开时生效；点在选项之间的空隙不会改变选择。
- `direction = "row"` 时横向排列，默认纵向。
- 越界的 `value` 不会报错，但不会画出选中项，`getLabel()` 返回 `nil`。

### 示例

```lua
local At = require("At.At")

local size = At.RadioGroup{
    x = 40, y = 40,
    options = { "小", "中", "大" },
    value = 2, direction = "row", gap = 24,
    onChange = function(index, label, self)
        print("选中第 " .. index .. " 项：" .. label)
    end,
}

size:draw()
```

## At.Slider

滑动条：点击轨道跳转、按住拖动、方向键微调（需先点击获得焦点）。

### 属性

| 属性          | 类型                     | 默认值       | 说明                                        |
| ------------- | ------------------------ | ------------ | ------------------------------------------- |
| `x` / `y`     | 数字                     | `0`          | 左上角坐标                                  |
| `w` / `h`     | 数字 / 百分比 / `"auto"` | `200` / `28` | 尺寸；轨道可用宽度为 `w - thumbRadius * 2`  |
| `min` / `max` | 数字                     | `0` / `100`  | 取值范围                                    |
| `step`        | 数字                     | `1`          | 步进；`0` 表示连续取值                      |
| `value`       | 数字                     | `0`          | 当前值；构造时会先吸附到 `step`             |
| `trackColor`  | hex / token              | `"@track"`   | 轨道底色                                    |
| `fillColor`   | hex / token              | `"@primary"` | 已填充部分颜色                              |
| `thumbColor`  | hex / token              | `"@knob"`    | 滑块颜色                                    |
| `trackHeight` | 数字                     | `6`          | 轨道高度                                    |
| `thumbRadius` | 数字                     | `9`          | 滑块半径                                    |
| `alpha`       | 数字 0–255               | `255`        | 透明度                                      |
| `showValue`   | 布尔                     | `false`      | 是否在右侧显示数值                          |
| `valueColor`  | hex / token              | `"@text"`    | 数值文字颜色                                |
| `fontSize`    | 数字                     | `nil`        | 缺省沿用当前字体                            |
| `format`      | 函数                     | `nil`        | `function(value) -> string`，覆盖默认格式化 |
| `onChange`    | 函数                     | `nil`        | 值变化回调                                  |

### 方法

| 方法                        | 说明                                                                |
| --------------------------- | ------------------------------------------------------------------- |
| `:getValue()`               | 返回当前值                                                          |
| `:setValue(value, silent?)` | 吸附到 `step` 并夹到 `[min, max]`；`silent` 为真时不触发 `onChange` |
| `:keypressed(key)`          | `left` / `down` 减一步，`right` / `up` 加一步                       |
| `:focus()` / `:blur()`      | 获取 / 放弃焦点，方向键只发给焦点组件                               |

### 回调

| 回调       | 参数            | 时机                                                 |
| ---------- | --------------- | ---------------------------------------------------- |
| `onChange` | `(value, self)` | 点击、拖动、方向键或非 silent 的 `setValue` 改变值时 |

注意：

- **`step` 吸附**：所有赋值（构造、`setValue`、点击、拖动、方向键）都会归到最近的 `step` 倍数；`step = 0` 时连续取值。
- **方向键微调**：先点击滑动条获得焦点，之后 `left` / `down` 减 `step`、`right` / `up` 加 `step`；`step = 0` 时每次移动 `(max - min) / 20`。
- 拖动在 `update(dt)` 里轮询鼠标，所以必须调用 `At.update(dt)`，否则拖出轨道后不再跟随。
- 点击轨道任意位置会直接跳到该值。
- `showValue = true` 时数值画在 `x + w + 8` 的位置，需要右侧留出空间。
- `min > max` 时吸附会交换上下界，但建议别这么传。

### 示例

```lua
local At = require("At.At")

local volume = At.Slider{
    x = 40, y = 40, w = 220,
    min = 0, max = 100, step = 5, value = 40,
    showValue = true,
    onChange = function(value, self) print("音量", value) end,
}

volume:setValue(73)     -- 吸附到最近的 5：75
volume:focus()          -- 之后左右方向键可微调
volume:draw()
```

## At.Dial

圆形旋钮（QDial 风格）：点击圆盘跳转，按住拖动连续调整；`wrapping = true` 时使用完整 360°，越过最大值会从最小值继续。

### 属性

| 属性              | 类型                     | 默认值            | 说明                                                    |
| ----------------- | ------------------------ | ----------------- | ------------------------------------------------------- |
| `x` / `y`         | 数字                     | `0`               | 左上角坐标                                              |
| `w` / `h`         | 数字 / 百分比 / `"auto"` | `120` / `120`     | 尺寸；非正方形时按短边画圆环                            |
| `min` / `max`     | 数字                     | `0` / `100`       | 取值范围                                                |
| `step`            | 数字                     | `1`               | 步进；`0` 表示连续取值                                  |
| `pageStep`        | 数字                     | `10`              | `PageUp` / `PageDown` 的步长                            |
| `value`           | 数字                     | `0`               | 当前值；构造时会先吸附到 `step`                         |
| `wrapping`        | 布尔                     | `false`           | `true` 时用完整 360° 圆环，值可越过 `max` / `min` 绕回  |
| `startAngle`      | 数字（度）               | `135`             | 起点角度；`0°` 在右侧，顺时针为正                       |
| `endAngle`        | 数字（度）               | `405`             | 非 wrapping 时的终点角度；wrapping 时**不参与**角度映射 |
| `trackWidth`      | 数字                     | `8`               | 圆环线宽                                                |
| `trackColor`      | hex / token              | `"@track"`        | 轨道颜色                                                |
| `fillColor`       | hex / token              | `"@primary"`      | 已填充圆弧颜色                                          |
| `knobColor`       | hex / token              | `"@knob"`         | 旋钮颜色                                                |
| `knobBorderColor` | hex / token              | `"@borderStrong"` | 旋钮描边                                                |
| `pointerColor`    | hex / token              | `"@primary"`      | 指针与中心点颜色                                        |
| `focusColor`      | hex / token              | `"@primary"`      | 聚焦外圈颜色                                            |
| `notchCount`      | 数字                     | `0`               | 刻度数量；`0` 关闭                                      |
| `notchColor`      | hex / token              | `"@borderStrong"` | 刻度颜色                                                |
| `notchWidth`      | 数字                     | `2`               | 刻度线宽                                                |
| `notchLength`     | 数字                     | `6`               | 刻度长度                                                |
| `alpha`           | 数字 0–255               | `255`             | 整体透明度                                              |
| `showValue`       | 布尔                     | `false`           | 是否在旋钮中心显示数值                                  |
| `valueColor`      | hex / token              | `nil`             | 数值颜色；缺省按 `knobColor` 自动取黑/白                |
| `fontSize`        | 数字                     | `nil`             | 数值字号；缺省沿用当前字体                              |
| `format`          | 函数                     | `nil`             | `function(value) -> string`，覆盖默认格式化             |
| `onChange`        | 函数                     | `nil`             | 值变化回调                                              |

### 方法

| 方法                        | 说明                                                                                             |
| --------------------------- | ------------------------------------------------------------------------------------------------ |
| `:getValue()`               | 返回当前值                                                                                       |
| `:setValue(value, silent?)` | 吸附到 `step`；wrapping 时越界按范围取模，否则夹到 `[min, max]`                                  |
| `:getRatio()`               | 返回当前值在范围中的比例 `0..1`                                                                  |
| `:setWrapping(enabled)`     | 开关 wrapping，返回自身                                                                          |
| `:isWrapping()`             | 是否处于 wrapping 模式                                                                           |
| `:keypressed(key)`          | `left` / `down` 减一步，`right` / `up` 加一步，`PageUp` / `PageDown` 翻页，`Home` / `End` 到端点 |

### 回调

| 回调       | 参数            | 时机                                                 |
| ---------- | --------------- | ---------------------------------------------------- |
| `onChange` | `(value, self)` | 点击、拖动、方向键或非 silent 的 `setValue` 改变值时 |

注意：

- **两种角度模式**：`wrapping = false` 时默认画 270° 圆弧（`startAngle = 135`、`endAngle = 405`），底部留缺口；`wrapping = true` 时画完整 360°，`endAngle` 被忽略，`0` 与 `max` 在 `startAngle` 处相接。
- **wrapping 的取模**：`min = 0`、`max = 359` 时，`setValue(360)` 得到 `1`，`setValue(-1)` 得到 `358`；范围内的值（包括 `max`）不会被绕回。
- **点击缺口**：非 wrapping 时点击底部缺口会吸附到更近的端点；wrapping 时没有缺口。
- **拖动依赖 `At.update(dt)`**：和 `Slider` 一样，`_tick` 里轮询鼠标，不调用 `At.update(dt)` 拖出圆盘后不会继续跟随。
- **刻度和数值**：`notchCount > 0` 时在圆环外侧画刻度；`showValue = true` 时数值画在旋钮中心，`valueColor = nil` 会自动根据旋钮颜色选黑/白。
- 方向键需要先点击旋钮获得焦点；`step = 0` 时每次方向键移动 `(max - min) / 20`，`pageStep` 仍用于翻页。

### 示例

```lua
local At = require("At.At")

local angle = At.Dial{
    x = 40, y = 40, w = 140, h = 140,
    min = 0, max = 359, step = 1, value = 45,
    wrapping = true,
    notchCount = 12,
    showValue = true,
    format = function(value) return string.format("%d°", value) end,
    onChange = function(value, self) print("角度", value) end,
}

angle:setValue(360)    -- wrapping：绕回 1
angle:focus()          -- 之后方向键可微调
angle:draw()
```

## At.ProgressBar

确定性进度条：`value` 是 `0`–`1` 的比例，填充宽度用弹簧平滑过渡。

### 属性

| 属性                                | 类型                     | 默认值       | 说明                                     |
| ----------------------------------- | ------------------------ | ------------ | ---------------------------------------- |
| `x` / `y`                           | 数字                     | `0`          | 左上角坐标                               |
| `w` / `h`                           | 数字 / 百分比 / `"auto"` | `220` / `12` | 尺寸                                     |
| `radius`                            | 数字                     | `nil`        | 圆角；缺省取高度的一半（胶囊形）         |
| `value`                             | 数字                     | `0`          | 进度比例 `0..1`，超出范围自动夹紧        |
| `trackColor`                        | hex / token              | `"@track"`   | 轨道底色                                 |
| `fillColor`                         | hex / token              | `"@primary"` | 已填充部分颜色                           |
| `alpha`                             | 数字 0–255               | `255`        | 透明度                                   |
| `animate`                           | 布尔                     | `true`       | 填充宽度是否用弹簧过渡；`false` 立即落位 |
| `springStiffness` / `springDamping` | 数字                     | `260` / `30` | 填充动画的弹簧刚度 / 阻尼                |
| `onChange`                          | 函数                     | `nil`        | 进度变化回调                             |

### 方法

| 方法                        | 说明                                                  |
| --------------------------- | ----------------------------------------------------- |
| `:getValue()`               | 返回当前进度（`0..1`）                                |
| `:setValue(value, silent?)` | 设进度并夹到 `0..1`；`silent` 为真时不触发 `onChange` |
| `:measure()`                | 返回声明尺寸；auto 时用默认宽高                       |

### 回调

| 回调       | 参数            | 时机                 |
| ---------- | --------------- | -------------------- |
| `onChange` | `(value, self)` | 值变化且非 silent 时 |

注意：

- **`value` 是 `0..1`**，不是 `0..100`；要显示百分比请自己乘 100，或放一个 `At.Label`。
- 动画在 `At.update(dt)` 里推进；`animate = false` 时立即到目标值。
- 填充宽度小于 1px 时不画，避免圆角在极窄宽度下糊成一团。
- 不确定总进度时用 [`At.LoadingBar`](#at-loadingbar)。

### 示例

```lua
local At = require("At.At")

local progress = At.ProgressBar{
    x = 40, y = 40, w = 240, h = 12,
    value = 0.35,
}

progress:setValue(0.8)   -- 平滑动画到 80%
progress:draw()
```

## At.LoadingBar

不确定性进度条：一段高光在轨道里循环滑过，适合不知道总进度的加载中状态。

### 属性

| 属性           | 类型                     | 默认值       | 说明                             |
| -------------- | ------------------------ | ------------ | -------------------------------- |
| `x` / `y`      | 数字                     | `0`          | 左上角坐标                       |
| `w` / `h`      | 数字 / 百分比 / `"auto"` | `220` / `12` | 尺寸                             |
| `radius`       | 数字                     | `nil`        | 圆角；缺省取高度的一半（胶囊形） |
| `trackColor`   | hex / token              | `"@track"`   | 轨道底色                         |
| `fillColor`    | hex / token              | `"@primary"` | 滑过高光的颜色                   |
| `alpha`        | 数字 0–255               | `255`        | 透明度                           |
| `speed`        | 数字                     | `1.1`        | 每秒循环次数                     |
| `segmentRatio` | 数字                     | `0.35`       | 高光段占轨道宽度的比例           |
| `minSegment`   | 数字                     | `24`         | 高光段最小像素宽度               |
| `running`      | 布尔                     | `true`       | 是否继续滑动                     |

### 方法

| 方法                   | 说明                            |
| ---------------------- | ------------------------------- |
| `:isRunning()`         | 是否正在滑动                    |
| `:setRunning(running)` | 开始 / 暂停，返回自身           |
| `:measure()`           | 返回声明尺寸；auto 时用默认宽高 |

注意：

- 相位在 `At.update(dt)` 里推进，**不调用不会动**；`setRunning(false)` 只是暂停，相位保留。
- 高光段从左滑到右后回绕，每次都在轨道外，不会看到跳变；`easeInOut` 让两端慢、中间快。
- 高光绘制会与外层裁剪求交，放进 `ScrollView` 也不会溢出视口。
- 任务结束后建议 `setRunning(false)` 或 `destroy()`，它不知道进度，不会自己停。

### 示例

```lua
local At = require("At.At")

local loading = At.LoadingBar{
    x = 40, y = 70, w = 240, h = 10,
    speed = 1.2,
}

function love.update(dt)
    At.update(dt)          -- 推进滑动
end

function love.draw()
    loading:draw()
end
```

## At.ScrollView

可滚动视口：内容比视口高时用滚轮、拖动或触摸上下滑动查看，超出视口的部分会被裁剪（scissor），右侧带滚动条。

### 属性

| 属性                                                  | 类型               | 默认值                    | 说明                                                                             |
| ----------------------------------------------------- | ------------------ | ------------------------- | -------------------------------------------------------------------------------- |
| `x` / `y`                                             | 数字               | `0`                       | 视口左上角                                                                       |
| `w` / `h`                                             | 数字               | `320` / `240`             | 视口尺寸                                                                         |
| `content`                                             | 组件               | `nil`                     | 被滚动的内容，通常是 `At.Panel`                                                  |
| `scrollX` / `scrollY`                                 | 数字               | `0`                       | 当前滚动量，会被自动夹到 `0 .. maxScrollX/Y`                                     |
| `scrollbar`                                           | 布尔               | `true`                    | 是否画滚动条                                                                     |
| `scrollbarWidth`                                      | 数字               | `4`                       | 滚动条宽度（横竖共用）                                                           |
| `scrollbarMargin`                                     | 数字               | `2`                       | 滚动条与视口边缘的间距                                                           |
| `edgeEffect`                                          | 布尔               | `true`                    | 触顶/触底时的橡皮筋过冲与边缘光                                                  |
| `edgeGlowColor` / `edgeGlowSize`                      | hex / token / 数字 | `"@primary"` / `28`       | 边缘光颜色 / 光带宽度                                                            |
| `edgeRadius`                                          | 数字 / `nil`       | `nil`                     | 光带圆角；缺省取内容容器（大卡片）的 `radius`，再退回 ScrollView 自身的 `radius` |
| `overscrollMax` / `overscrollResistance`              | 数字               | `70` / `0.55`             | 光带达到最亮所需的过冲量 / 拉动阻力（越小越硬）                                  |
| `edgeSpringStiffness` / `edgeSpringDamping`           | 数字               | `380` / `30`              | 松手回弹的弹簧刚度 / 阻尼                                                        |
| `scrollbarColor` / `scrollbarThumbColor`              | hex / token        | `"@track"` / `"@primary"` | 轨道/滑块颜色                                                                    |
| `scrollbarActiveWidth`                                | 数字               | `8`                       | 指针靠近或拖动滚动条时的宽度（离开后缩回 `scrollbarWidth`）                      |
| `scrollbarSpringStiffness` / `scrollbarSpringDamping` | 数字               | `700` / `42`              | 滚动条变宽的弹簧刚度 / 阻尼                                                      |
| `scrollbarGrowSpeed`                                  | 数字               | `16`                      | 已弃用；宽度改用上面的弹簧控制                                                   |
| `scrollbarHitWidth`                                   | 数字               | `16`                      | 滚动条的可拖拽宽度（比视觉宽度大，方便手指按住）                                 |
| `wheelStep`                                           | 数字               | `44`                      | 滚轮一格滚动多少像素                                                             |
| `smooth`                                              | 布尔               | `true`                    | 滚轮/代码滚动是否缓动；拖拽始终 1:1 跟手                                         |
| `smoothSpeed`                                         | 数字               | `14`                      | 缓动收敛速度，越大越跟手                                                         |
| `momentum`                                            | 布尔               | `true`                    | 松手后是否保留惯性                                                               |
| `momentumFriction`                                    | 数字               | `6`                       | 惯性衰减速度                                                                     |
| `momentumMin`                                         | 数字               | `1`                       | 小于这个速度（像素/帧）不产生惯性                                                |
| `drag`                                                | 布尔               | `true`                    | 允许按住空白处拖动滚动                                                           |
| `padding`                                             | 数字 / 表          | `0`                       | 视口内边距                                                                       |
| `background` / `radius`                               | hex / 数字         | `nil` / `0`               | 视口背景与圆角                                                                   |
| `onScroll`                                            | 函数               | `nil`                     | 滚动量变化时回调 `(value, maxScroll, self, axis)`，`axis` 为 `"x"` / `"y"`       |

### 方法

| 方法                                                                                        | 说明                                                                                             |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `:setScroll(value, silent?)`                                                                | **立即**设置滚动量并夹紧（拖拽、滚动条、`scrollToVisible` 用）；`silent` 为真时不触发 `onScroll` |
| `:scrollTo(value, silent?)`                                                                 | **平滑**滚动到绝对值；`smooth = false` 时等同 `setScroll`                                        |
| `:scrollBy(delta, silent?)`                                                                 | **平滑**相对滚动；按当前目标累加，连续滚轮不会互相吞掉                                           |
| `:maxScroll()`                                                                              | 最大纵向滚动量（内容高度 - 视口高度）                                                            |
| `:maxScrollX()`                                                                             | 最大横向滚动量（内容宽度 - 视口宽度）                                                            |
| `:setScrollX(value, silent?)` / `:scrollToX(value, silent?)` / `:scrollByX(delta, silent?)` | 横向的立即 / 平滑 / 相对滚动                                                                     |
| `:scrollToVisible(component, margin?)`                                                      | 把某个子组件滚进可视区，配合输入框聚焦防软键盘遮挡                                               |
| `:layout()`                                                                                 | 立即重排：把自身视口宽度作为可用宽度传给内容                                                     |
| `:destroy()`                                                                                | 连同 `content` 一起销毁                                                                          |

### 说明

- **两个方向都会自动生成滚动条**：内容高度超过视口时出现纵向条，宽度超过视口时出现横向条（可同时出现，两端的轨道会互相让位）。没有任何溢出时不画滚动条，也不吞空白处的点击。
- 可以嵌套：`ScrollView` 会把自己声明为可交互，外层收到落在内层上的点击时会交给内层处理。
- 内容宽度自适应视口：比视口窄的内容按视口宽排版（`"100%"` / `"50%"` 以视口为基准）；比视口宽的内容保留自身宽度，从而出现横向滚动。
- 事件顺序：**ScrollView 必须在内容之后创建**，这样它才能在注册表里先于子组件收到点击，判断"这次点击该不该交给子组件"。
- 点在**可交互**子组件（按钮/开关/输入框/滑动条等）上 → 不拦截，交给子组件；点在空白处**或被动组件（文字）上** → 由 `ScrollView` 接管并开始拖动滚动；点在已经滚出视口、但仍压在上述组件上的位置 → 直接吃掉，避免误触。
- 滚轮通过 `At.wheelmoved(dx, dy)` 接入，只有指针在视口内时才消费：`dy` 滚纵向、`dx` 滚横向，`Shift` + 滚轮也走横向；某个轴没有滚动空间时自动退让给另一个轴（例如只有竖滚的视口收到横向滚轮）。滚轮走**平滑滚动**：只设定目标位置，位置每帧缓动逼近（`smoothSpeed`），松手拖动还会带**惯性**（横向、纵向各自独立衰减，撞到边界即停）。
- `scrollY` 是浮点数（平滑动画需要），绘制时会取整；`onScroll` 在平滑滚动过程中会**逐帧触发**，需要节流的话自己处理。
- 右侧滚动条**可以拖**：按在滑块上拖动直接滚动；按在轨道空白处会跳转到对应位置。命中区按 `scrollbarHitWidth` 放大，手指也好按。
- 指针碰到滚动条时它会**变宽**（`scrollbarWidth` → `scrollbarActiveWidth`，带缓动），离开后缩回，方便发现与触控。
- **触顶/触底有边缘光效**：拖到边界后继续拉，内容不会离开边界，而是累积“过冲量”让边缘渐隐光带变亮（`overscrollMax` / `overscrollResistance` 控制达到最亮所需的拉动量与阻力），松手后光带由弹簧淡出。滚轮、惯性或拖动滚动条顶到两端时也会触发同样的边缘光。`edgeGlowColor` / `edgeGlowSize` 分别是颜色与光带宽度，`edgeEffect = false` 可整体关闭。
- **光效始终画在容器内**：光带叠加在容器边缘的内容之上，并用视口裁剪，不会推开内容、不会露出空隙，也不会画到容器外。
- **圆角跟随大卡片容器**：只有内容真正贴住视口的那条边，光带才按内容容器的 `radius` 收角（圆角光带不会糊到卡片圆角外）；滚动到中间是切面，不收角。想强制直角可设 `edgeRadius = 0`，或用数字覆盖。
- **触边特效按轴隔离**：只有存在纵向滚动空间时才可能出现上下光带，只有存在横向滚动空间时才可能出现左右光带；单向滚动视口不会被另一轴的拖动带出特效。
- 过冲只是绘制偏移（内部 `_overY` / `_overX`），**`scrollY` / `scrollX` 始终夹在合法范围内**，不会污染滚动 API 与 `onScroll`；`content.y` 在绘制时才会叠加过冲量。
- 裁剪会与外层裁剪**求交**（见 `At.clip`），所以嵌套滚动、或滚动视口里再放输入框，都不会把内容画到视口外。
- 子组件的坐标会被滚动位移实时改写，所以命中判断、`scrollToVisible` 都用当前的 `y`。
- 不支持边界回弹（惯性已有，但没有橡皮筋效果）、无限滚动，以及嵌套滚动时"内层滚到底再传给外层"的滚动链（内外层各自独立消费滚轮）。

### 示例

```lua
local At = require("At.At")

-- 内容比视口宽：会自动出现横向滚动条
local card = At.Panel{ w = 720, h = "auto", gap = 12, padding = 16 }
for i = 1, 20 do
    card:add(At.Label{ text = "第 " .. i .. " 行" })
end

local view = At.ScrollView{
    x = 40, y = 40,
    w = 360, h = love.graphics.getHeight() - 80,
    content = card,
    scrollbar = true,
}

-- love.draw:           view:draw()
-- love.wheelmoved:     At.wheelmoved(dx, dy)
-- 需要定位到某一行时：view:scrollToVisible(card.children[15])   -- 立即定位
```

## At.Console

浮动控制台：显示 `At.log` 收集的全部日志，按等级着色、半透明背景，可拖动窗口、滚动日志、点 `×` 或调 API 显示/隐藏。日志内容与等级过滤由 [`At.log`](logging.md) 负责。

### 属性

| 属性                                     | 类型        | 默认值                         | 说明                                                |
| ---------------------------------------- | ----------- | ------------------------------ | --------------------------------------------------- |
| `x` / `y`                                | 数字        | `0`                            | 初始位置；拖动时会被夹在窗口内                      |
| `w` / `h`                                | 数字        | `560` / `240`                  | 窗口尺寸                                            |
| `headerH`                                | 数字        | `30`                           | 标题栏高度（也是拖动区域与关闭按钮尺寸）            |
| `padding`                                | 数字        | `8`                            | 日志区左右内边距                                    |
| `radius`                                 | 数字        | `8`                            | 窗口圆角                                            |
| `visible`                                | 布尔        | `false`                        | 默认隐藏，用 `toggle()` / `show()` 打开             |
| `draggable`                              | 布尔        | `true`                         | 是否允许拖动标题栏移动窗口                          |
| `showClose`                              | 布尔        | `true`                         | 是否显示右上角 `×`                                  |
| `showClear`                              | 布尔        | `true`                         | 是否显示标题栏的 `C`（清空日志）按钮                |
| `title`                                  | 字符串      | `"控制台"`                     | 标题栏文字                                          |
| `fontSize`                               | 数字        | `13`                           | 日志字号                                            |
| `lineHeight`                             | 数字        | `1.35`                         | 行高倍数                                            |
| `scrollStep`                             | 数字        | `3`                            | 滚轮一格滚动几行                                    |
| `animate`                                | 布尔        | `true`                         | 打开/关闭动画：弹簧 + 淡入淡出 + 轻微下移           |
| `springStiffness` / `springDamping`      | 数字        | `320` / `26`                   | 开关动画的弹簧刚度 / 阻尼                           |
| `openOffset`                             | 数字        | `12`                           | 关闭时窗口向下偏移多少像素（打开时滑回）            |
| `background`                             | hex / token | `"@background"`                | 背景色                                              |
| `alpha`                                  | 数字 0–255  | `205`                          | 背景透明度（半透明）                                |
| `borderColor` / `dividerColor`           | hex / token | `"@border"` / `"@divider"`     | 边框 / 标题分隔线                                   |
| `titleColor` / `placeholderColor`        | hex / token | `"@text"` / `"@textFaint"`     | 标题 / 无日志提示色                                 |
| `scrollbarColor` / `scrollbarThumbColor` | hex / token | `"@track"` / `"@primary"`      | 滚动条轨道 / 滑块                                   |
| `tab`                                    | 布尔        | `true`                         | 隐藏时在右上角显示可点按的 `LOG` 标签（移动端入口） |
| `tabW` / `tabH`                          | 数字        | `72` / `28`                    | 标签尺寸                                            |
| `tabMargin`                              | 数字        | `12`                           | 标签距屏幕边缘                                      |
| `tabRadius`                              | 数字        | `6`                            | 标签圆角                                            |
| `tabLabel`                               | 字符串      | `"LOG"`                        | 标签文字                                            |
| `tabColor` / `tabTextColor`              | hex / token | `"@surfaceAlt"` / `"@primary"` | 标签底色 / 文字色                                   |
| `tabAlpha`                               | 数字        | `225`                          | 标签底色透明度                                      |
| `tabX` / `tabY`                          | 数字        | `nil`                          | 标签位置；缺省贴屏幕右上角                          |
| `levelColors`                            | 表          | 见下                           | 每个等级的文字颜色                                  |

默认等级配色：

```lua
levelColors = {
    debug = "@textFaint",
    info  = "@primary",
    warn  = "@warning",
    error = "@danger",
    fatal = "@danger",
}
```

`levelColors` 是**每个实例独立的副本**，修改一个控制台不会影响其它控制台。

### 方法

| 方法                                | 说明                                                   |
| ----------------------------------- | ------------------------------------------------------ |
| `:show()` / `:hide()` / `:toggle()` | 显示 / 隐藏 / 切换                                     |
| `:isOpen()`                         | 是否可见                                               |
| `:setTitle(text)`                   | 改标题                                                 |
| `:clear()`                          | 清空 `At.log` 的日志缓冲并把视图回到底部               |
| `:scrollToBottom()`                 | 滚回最新一条（打开控制台时也会自动回到最新）           |
| `:openAmount()`                     | 当前动画进度：`0` 完全关闭、`1` 完全打开（可能略过冲） |
| `:draw()` / `:update(dt)`           | 由调用方每帧调用；`update` 推进开关动画并处理拖动      |

### 交互

- **拖动标题栏**移动窗口，位置会被夹在屏幕内。
- **日志区复用 `At.ScrollView`**：拖动、滚轮、平滑滚动、惯性、可拖滚动条、悬停变宽、触边光效都与普通滚动视口一致；`scrollbarColor` / `scrollbarThumbColor` 会传给内部 ScrollView。
- **拖动日志区**上下滚动；**滚轮**按 `scrollStep` 行滚动（内部换算成像素交给 ScrollView）。
- 隐藏时右上角显示 `LOG` 标签（`tab = true`），**点它打开控制台**；打开过程中标签随窗口淡出，完全显示后标签消失。
- 关闭时窗口先淡出并下移再消失（`animate = false` 则立即消失）；动画期间 `visible` 已是 `false`，窗口不再接收鼠标，但它仍会被绘制。
- 标题栏 `C` 清空日志、`×` 关闭；关闭后不消费任何鼠标/滚轮事件。
- 日志区可显示时最多 `floor(日志区高度 / 行高)` 行，超出部分用滚动查看；滚动条只在内容超高时出现。
- 有新的日志时，若视图停在底部会自动跟随最新；往上翻后保持当前位置，滚回底部再恢复跟随。

### 示例

```lua
local At = require("At.At")

At.log.setLevel("debug")
At.log.setFormat("[%s] - [%s/%s]: %s")

local console = At.Console{
    x = 20, y = 20, w = 560, h = 240,
    title = "At.log 控制台",
    alpha = 205,
}

At.log.info("游戏启动")
At.log.warn("资源 %s 缺失，已用占位图", "enemy.png")

function love.draw()
    ui:draw()
    console:draw()          -- 必须最后画
end

function love.keypressed(key)
    if key == "f1" then
        console:toggle()    -- 显示/隐藏
    end
end
```
