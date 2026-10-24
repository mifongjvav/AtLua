# 主题色

AtLua 的所有组件默认颜色都来自主题 token，而不是写死的 hex。改主题只改三个基色，
派生色与已有组件会一起更新；单个组件仍可传具体 hex 覆盖默认值。

```lua
local At = require("At.At")

At.theme.set({ color = "7FE0C4" })   -- 运行时换主题色，已创建的组件立即生效
At.theme.get("@surface")             -- 取派生色
At.Label{ color = "@textMuted" }     -- 组件颜色也可以直接写 token
```

## 默认值

| 基色   | 字段                            | 默认值    | 作用                                       |
| ------ | ------------------------------- | --------- | ------------------------------------------ |
| 主题色 | `theme.color` / `theme.primary` | `#A7DCFF` | 主色、强调色（按钮、开关、进度、聚焦边框） |
| 黑     | `theme.black`                   | `#3D3D3D` | 深色槽位，默认背景                         |
| 白     | `theme.white`                   | `#FFFFFF` | 浅色槽位，默认文字、旋钮                   |

配置写在 [`At/config.lua`](../At/config.lua) 的 `theme` 段，运行时改完 `At.config` 需要
`At.config.apply()`；直接调 `At.theme.set{...}` 则不需要。注意 `apply()` 会以 `At.config.theme`
为准重新推一次主题，因此会覆盖之前 `set` 的临时值：

```lua
At.config.theme.color = "7FE0C4"
At.config.apply()
```

## 颜色 token

token 是**以 `@` 开头的字符串**，例如 `"@primary"`。所有接受颜色的属性（`color`、
`textColor`、`fillColor`、`background`、`borderColor` …）都接受 token，也接受普通
`"#RRGGBB"` / `"RRGGBB"`。`At.color.hexToRGBA`、`setColor`、`shade`、`mix` 同样会解析 token。

| token                | 含义                   | 默认值 / 派生规则                                              |
| -------------------- | ---------------------- | -------------------------------------------------------------- |
| `@primary`           | 主题色                 | `#A7DCFF`                                                      |
| `@primaryDark`       | 深色主题色（阴影默认） | `shade(primary, -0.82)` → `#1E282E`                            |
| `@theme` / `@accent` | 主题色别名             | 同 `@primary`                                                  |
| `@black`             | 黑色基色               | `#3D3D3D`                                                      |
| `@white`             | 白色基色               | `#FFFFFF`                                                      |
| `@background`        | 页面背景               | 黑色基色 `#3D3D3D`                                             |
| `@surface`           | 卡片 / 面板背景        | `mix(black, white, 0.06)` → `#494949`                          |
| `@surfaceAlt`        | 输入框 / 控件底        | `mix(black, white, 0.12)` → `#545454`                          |
| `@surfaceStrong`     | 次级按钮 / 更亮的表面  | `mix(black, white, 0.20)` → `#646464`                          |
| `@text`              | 主文字                 | 白色基色 `#FFFFFF`                                             |
| `@textMuted`         | 次级文字               | `mix(white, black, 0.38)` → `#B5B5B5`                          |
| `@textFaint`         | 提示 / 占位文字        | `mix(white, black, 0.56)` → `#929292`                          |
| `@onPrimary`         | 主题色上的文字 / 涟漪  | `black` / `white` 中与主题色对比度更高的一个（默认 `#3D3D3D`） |
| `@border`            | 普通描边               | `mix(black, white, 0.22)` → `#686868`                          |
| `@borderStrong`      | 控件描边               | `mix(black, white, 0.34)` → `#7F7F7F`                          |
| `@divider`           | 分隔线                 | `mix(black, white, 0.14)` → `#585858`                          |
| `@track`             | 轨道 / 滚动条底        | `mix(black, white, 0.17)` → `#5E5E5E`                          |
| `@knob`              | 开关 / 滑块            | 白色基色 `#FFFFFF`                                             |
| `@danger`            | 错误 / 危险            | `#E87979`                                                      |
| `@warning`           | 警告                   | `#E8C07F`                                                      |
| `@success`           | 成功                   | `#7FA88F`                                                      |

`@danger` / `@warning` / `@success` 是固定的语义色，不随三基色派生；控制台的
`debug / info / warn / error / fatal` 默认分别引用 `@textFaint / @primary / @warning /
@danger / @danger`。

## API

| 成员                                                | 说明                                                                        |
| --------------------------------------------------- | --------------------------------------------------------------------------- |
| `At.theme.color` / `.primary` / `.black` / `.white` | 当前三个基色（`primary` 是 `color` 的别名；可读，改它不会重算，请用 `set`） |
| `At.theme.tokens`                                   | 当前全部 token 的具体 hex 表（每次 `set` 后重建）                           |
| `At.theme.set{ color=?, black=?, white=? }`         | 改基色并立即重算派生色，返回 `At.theme`；`color` 也可写成 `primary`         |
| `At.theme.get(name)`                                | 取 token 的具体 hex，`name` 可带或不带 `@`；未知 token 会报错               |
| `At.theme.resolve(value)`                           | token → hex；普通 hex 原样返回                                              |
| `At.theme.isToken(value)`                           | 是否是以 `@` 开头的 token                                                   |
| `At.theme.reset()`                                  | 恢复出厂三基色                                                              |
| `At.theme.foreground(background)`                   | 按底色亮度返回 `black` / `white` 中对比度更高的 hex，供自定义组件选文字色   |
| `At.theme.defaults()`                               | 返回出厂基色的副本                                                          |

颜色值接受带不带 `#` 的 6 位十六进制；`set` 会统一成大写 `#RRGGBB`。非法颜色直接报错，
不会悄悄退化成默认值。

## 组件默认色

组件默认属性里存的是 token，例如：

```lua
At.Label{ }                         -- color = "@text"
At.Button{ text = "确定" }          -- color = "@primary"，文字色按对比度自动选
At.TextInput{ }                     -- color = "@surfaceAlt"，focusBorderColor = "@primary"
At.Switch{ value = true }           -- color = "@track"，onColor = "@primary"
At.ProgressBar{ value = 0.4 }       -- trackColor = "@track"，fillColor = "@primary"
```

因为这些 token 在**绘制时**才解析，所以 `At.theme.set` 之后连已创建的组件都会换色，
不需要重建。显式传 hex 的组件保持自己的颜色：

```lua
At.Button{ text = "固定绿色", color = "#7FA88F" }   -- 不跟随主题
At.Button{ text = "跟随主题" }                       -- 跟随 @primary
```

每个组件可以单独覆盖，也可以传 token 让它继续跟随主题：

```lua
At.Panel{ background = "@surface", borderColor = "@border" }
At.Label{ color = "@textMuted" }
```

## 浅色主题

派生规则把 `black` 当背景、`white` 当文字。想切到浅色主题，把两个槽位对调即可：

```lua
At.theme.set({ black = "FFFFFF", white = "3D3D3D" })
```

这时 `@background` 变成白色、`@text` 变成深灰，`@surface` 等表面色也会自动翻转。

## 系统主题与系统主题色

[`At.system`](../At/core/system.lua) 提供系统明暗与桌面主题色的**尽力探测**：

```lua
local mode, reason = At.system.getThemeMode()
-- mode: "light" / "dark" / nil
-- reason: "system" / "unsupported" / "unknown" / "error"

local accent, source = At.system.getAccentColor()
-- accent: "#RRGGBB" / nil
-- source: "GNOME/GTK" / "KDE/Qt" / "Windows" / "macOS" / "env" / nil
```

- **系统明暗**：只有 LÖVE 12+ 的 `love.window.getSystemTheme` 能提供；LÖVE 11 返回
  `nil, "unsupported"`。桌面返回 `light` / `dark`，无法判断时返回 `nil, "unknown"`。
- **系统主题色**：LÖVE 没有原生 API，`At.system` 在桌面平台按 best-effort 读取：
  - GNOME/GTK：`gsettings get org.gnome.desktop.interface accent-color`（如 `blue` / `pink`）
  - KDE/Qt：`kreadconfig6/5` 或 `~/.config/kdeglobals` 的 `[Colors:View] Highlight`
  - Windows：DWM `ColorizationColor`
  - macOS：`defaults read -g AppleAccentColor`
  - `AT_ACCENT_COLOR`（或 `AT_THEME_COLOR`）环境变量优先级最高，格式 `#RRGGBB`
- 结果会缓存；系统主题色改变后调用 `At.system.reset()` 再取一次。探测失败只返回
  `nil` + 原因，不会报错或阻塞启动；Android/iOS 和没有 `io.popen` 的环境不做探测。
- `getAccentColor(refresh)` 传 `true` 可强制重新探测。

示例里“外观”默认选“系统”（LÖVE 12+ 且系统给出明暗时跟随），也可以手动切“白色”/“深色”；
“主题色”里的“系统色”按钮会尝试使用 Qt/GTK 等桌面主题色，失败时保留当前主题色并给出提示。

```lua
local mode = At.system.getThemeMode()
if mode == "light" then
    At.theme.set({ black = "FFFFFF", white = "3D3D3D" })
end

local accent = At.system.getAccentColor()
if accent then
    At.theme.set({ color = accent })
end
```

## 限制

- 主题只负责颜色，不改变圆角、阴影、字号或布局。
- 语义色 `@danger` / `@warning` / `@success` 固定，不参与三基色派生，也不能通过
  `At.theme.set` 覆盖；需要自定义时直接给组件的 `levelColors` 等属性传 hex。
- `@onPrimary` 按主题色亮度自动选 `black` 或 `white`，因此换深色主题色时按钮文字会自动变白；
  它不保证符合 WCAG，正式项目请自行检查对比度。
- 主题没有多套命名主题（例如 `theme.apply("dark")`）；需要多套方案时在业务层保存
  三基色，切换时调用 `At.theme.set`。
- 已缓存成具体 hex 的地方不会跟随（例如你自己用 `At.theme.get` 存下来的颜色）；
  组件内部都保留 token，绘制时再解析，因此不受影响。
