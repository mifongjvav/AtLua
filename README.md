# AtLua

**LÖVE 的轻量 UI 组件库**：CSS 子集式布局 + 自绘组件，纯 Lua、零第三方依赖。

按钮、开关、输入框、单/多选、滑动条、滚动视口都自带状态与交互；布局用类似 flex 的
`direction / gap / padding / align / justify / grow` 描述，不需要手写坐标。

```lua
local At = require("At.At")

local card = At.Panel{
    x = 40, y = 40, w = 380, h = "auto",
    direction = "column", gap = 12, padding = 20,
    background = "@surface", radius = 16,
}

card:add(At.Label{ text = "设置", fontSize = 22 })
card:add(At.TextInput{ w = "100%", placeholder = "昵称" })
card:add(At.Switch{ value = true, onChange = function(v) print(v) end })
card:add(At.Slider{ w = "100%", min = 0, max = 100, step = 5, value = 60 })

function love.draw() card:draw() end
```

## 特性

- **布局引擎**（`At.Panel` / `At.layout`）：`column`/`row`、`gap`、`padding`/`margin`、
  数字/百分比/`auto` 尺寸、`grow` 瓜分剩余空间、`align`/`justify` 对齐，支持嵌套。
- **组件**全部继承同一个基类，统一 `draw/update/mousepressed/mousereleased/measure/destroy` 协议：
  `Panel`、`Label`、`Button`、`TextInput`、`Switch`、`Checkbox`、`RadioGroup`、`Slider`、`Dial`、`ScrollView`。
- **系统主题**：LÖVE 12+ 默认跟随系统明暗；`At.system.getAccentColor()` 尽力读取 Qt/GTK 等桌面主题色，示例可切换白色主题与系统主题色。
- **主题色系统**：三个基色（主题色 `#A7DCFF`、黑 `#3D3D3D`、白 `#FFFFFF`）派生整套语义色；组件默认颜色是 `@primary` / `@text` 这类 token，运行时 `At.theme.set{...}` 换色，已有组件立即生效。
- **交互细节**：按钮涟漪与拖出/拖回语义、开关左右拖动、滑动条拖动与方向键微调、圆形旋钮拖动与 wrapping、输入框软键盘与光标、
  唯一键盘焦点、点空白自动失焦。
- **滚动视口**：横向/纵向都支持，内容超出宽或高时**自动出现对应滚动条**；平滑滚动、双向惯性、可拖滚动条、悬停变宽、支持嵌套、`scrollToVisible`。
- **渲染细节**：坐标对齐整数像素、嵌套裁剪求交、1px 边框使用 rough 线型；默认 GLSL SDF 单次绘制阴影，可切回旧式多层阴影（legacy 按层数归一化）；`At/config.lua` 的 `render.msaa` 默认 4，圆角/圆形/边框与模糊路径都有抗锯齿。
- **背景模糊（毛玻璃）**：`At.blur` 抓取组件背后的画面并按算法模糊，半透明组件（控制台、半透明卡片/输入框/按钮）自动生效；内置 gaussian / downscale / none，可注册自定义算法。
- **Toast、Dialog 与系统通知**：`At.Toast` 是窗口下方居中、自动关闭的一次性通知条；
  `At.Dialog` 支持全屏（压暗背景、可毛玻璃、不可拖动）和浮动（可拖动、不压暗）两种模态对话框；
  `At.notify` 在 Linux 通过 `notify-send` 发送系统通知，支持 `critical` 等重要级别。
- **日志与控制台**：`At.log` 提供 debug/info/warn/error/fatal 五级、可配置格式、条目缓冲，
  默认同时输出到终端 / logcat；`At.Console` 是半透明浮动面板，按等级着色、可拖动、可滚动、
  可显示/隐藏（隐藏时留一个 `LOG` 标签，移动端也能点开）。
- **自带无头测试**：不需要 LÖVE 也能跑逻辑回归。
- **一键打包**：`./pack.sh` 生成 `.love`（不依赖 `zip`，有 `python3` 即可）。

## 环境要求

- [LÖVE](https://love2d.org/) **11.x / 12.x**（LuaJIT / Lua 5.1 语义）
- 无第三方 Lua 库、无 shader、无构建工具

## 快速开始

```bash
git clone https://github.com/mifongjvav/AtLua.git
cd AtLua
love .
```

也可以打包成单个文件再运行：

```bash
./pack.sh && love AtLua.love
```

把 `At/` 目录和 `main.lua` 放进你自己的 LÖVE 项目即可使用；`main.lua` 是演示，可以删掉。

### 接入自己的项目

```lua
local At = require("At.At")

function love.load()   At.font.init(16) end          -- 必须先初始化字体
function love.update(dt) At.update(dt) end            -- 涟漪/动画/平滑滚动
function love.draw()   ui:draw() end                  -- ui 为任意容器/组件

function love.mousepressed(x, y, b)  At.mousepressed(x, y, b)  end
function love.mousereleased(x, y, b) At.mousereleased(x, y, b) end
function love.wheelmoved(dx, dy)     At.wheelmoved(dx, dy)     end
function love.textinput(t)           At.textinput(t)           end
function love.keypressed(k)          At.keypressed(k)          end
```

组件创建即自动登记到注册表，事件由 `At.*` 统一派发；`At.Panel` 不接收事件，只负责排版。

### 日志与控制台

```lua
At.log.setLevel("debug")                      -- debug/info/warn/error/fatal，默认 info
At.log.info("玩家 %d 进入", 3)                 -- 支持 string.format
At.log.setFormat("[%s] - [%s/%s]: %s")        -- 时间/等级/函数名/内容（默认格式）

At.blur.setEnabled(true)                      -- 半透明组件自动毛玻璃
At.theme.set({ color = "7FE0C4" })            -- 换主题色，已有组件立即更新
At.log.setFile(true)                          -- 同时写入 "YYYY-MM-DD_HH-MM-SS.log"
print("日志文件:", At.log.getFilePath())       -- Android 上在应用存档目录

local console = At.Console{ x = 20, y = 20, w = 560, h = 240 }
console:toggle()                              -- 或 show() / hide()

function love.draw()
    At.blur.beginFrame()                      -- 启用模糊时包住整帧
    ui:draw()
    console:draw()                            -- 最后画，浮在最上层
    At.blur.endFrame()
end
```

默认输出形如 `[15:04:05] - [INFO/love.load]: 演示启动`，并**同时打印到终端**（Android 上进入
`adb logcat -s love`）；`At.log.setFile(true)` 还能按 `YYYY-MM-DD_HH-MM-SS.log` 落盘（`love.quit` 里
`At.log.closeFile()` 收尾）。控制台可拖动标题栏移动、滚轮或拖动日志区滚动；隐藏时右上角有 `LOG` 标签
可点开（移动端入口），标题栏 `C` 清空、`×` 关闭；桌面上也可用 `F1` / `F2`。

## 组件一览

| 组件            | 作用                                                                 |
| --------------- | -------------------------------------------------------------------- |
| `At.Panel`      | 布局容器 / 卡片，支持背景、描边、圆角、阴影                          |
| `At.Label`      | 文字标签，支持换行与对齐                                             |
| `At.Button`     | 按钮：悬停/按下/禁用、涟漪、居中文字、回调                           |
| `At.TextInput`  | 单行输入框：点击定位光标、方向键、中间编辑、密码、长度限制、回车提交 |
| `At.Switch`     | 开关：点击或左右拖动切换，带过渡动画                                 |
| `At.Checkbox`   | 多选框                                                               |
| `At.RadioGroup` | 单选组（`value` 为 1 基下标）                                        |
| `At.Slider`     | 滑动条：点击跳转、拖动、方向键微调、步长吸附                         |
| `At.Dial`       | 圆形旋钮：点击/拖动、角度映射、wrapping、刻度与数值显示              |
| `At.ScrollView` | 可滚动视口：横向/纵向自动滚动条、平滑滚动、惯性                      |
| `At.Console`    | 浮动调试控制台：显示 `At.log` 日志、着色、可拖动                     |
| `At.Toast`      | 窗口下方居中、自动关闭的一次性 Toast 通知                            |

## 布局速查（CSS 子集）

| 本库                 | CSS                | 说明                                         |
| -------------------- | ------------------ | -------------------------------------------- |
| `direction`          | `flex-direction`   | `column` / `row`                             |
| `gap`                | `gap`              | 子项间距                                     |
| `padding` / `margin` | 同名               | 数字或 `{ left, top, right, bottom }`        |
| `w` / `h`            | `width` / `height` | 数字、`"50%"`、`"auto"`                      |
| `grow`               | `flex-grow`        | 瓜分主轴剩余空间                             |
| `align`              | `align-items`      | `start` / `center` / `end` / `stretch`       |
| `justify`            | `justify-content`  | `start` / `center` / `end` / `space-between` |

不支持 `flex-wrap`、`grid`、绝对定位、`z-index`。父容器没有确定宽度时百分比会退化成 `auto`。

## 文档

- [docs/README.md](docs/README.md) — 快速开始、事件模型、常见问题
- [docs/layout.md](docs/layout.md) — 布局规则、尺寸与像素对齐、限制、示例
- [docs/components.md](docs/components.md) — 每个组件的属性/方法/回调/示例
- [docs/theme.md](docs/theme.md) — 主题色、token 表、运行时换色、浅色主题
- [docs/shadow.md](docs/shadow.md) — GLSL / 旧式阴影的切换、参数与性能
- [docs/logging.md](docs/logging.md) — 日志等级、输出格式、控制台配合
- [docs/blur.md](docs/blur.md) — 背景模糊的启用方式、算法与性能说明
- [docs/notifications.md](docs/notifications.md) — Linux notify-send 系统通知与 Toast 配合

## 测试

无头逻辑测试，不需要 LÖVE（在项目根目录执行）：

```bash
lua test_smoke.lua      # 通过时打印 SMOKE OK
```

覆盖布局数值、按压会话、焦点转移、开关拖动、滑动条吸附、滚动/惯性、裁剪求交、像素对齐、
许可证文件与文档同步等断言。语法检查：

```bash
for f in conf.lua main.lua At/*.lua At/core/*.lua At/components/*.lua At/effects/*.lua test_smoke.lua; do luac -p "$f"; done
```

## 打包

```bash
./pack.sh              # 生成 AtLua.love
./pack.sh MyGame       # 生成 MyGame.love
```

`.love` 就是 zip 包，可直接用 `love AtLua.love` 运行，或改名/分发。脚本会排除
`docs/`、`*.md`、`test_smoke.lua`，但**保留 `LICENSE` 与 `LICENSES/`**（字体的 OFL 要求）。

## 目录结构

```
main.lua        # 演示程序
conf.lua        # 创建窗口前读取 At/config.lua（MSAA）
pack.sh         # 打包脚本
test_smoke.lua  # 无头测试
docs/           # 使用文档（README / layout / components / theme / shadow / logging / blur / notifications）
LICENSES/       # 第三方许可全文（随包分发）
At/
  At.lua        # 门面：require 一次拿到全部模块
  config.lua    # 集中配置：theme / blur / log / font
  core/         # 基础设施：registry、component、layout、clip、pixel、color、theme、
                #   render、SDF、shadow、font、input、system、notify、log
  components/   # 组件：Panel、Label、Button、TextInput、Switch、Checkbox、
                #   RadioGroup、Slider、Dial、ScrollView、Console、Toast、Dialog
  effects/      # 视觉效果：Ripple、blur
  assets/       # 字体资源：font.ttf、emoji.ttf
AGENTS.md       # 给 AI 代理/协作者的约定与陷阱
```

配置集中在 `At/config.lua`：

```lua
At.config.theme.color = "7FE0C4"     -- 主题色（派生全部默认配色）
At.config.render.msaa = 4            -- 抗锯齿采样数（0 关闭）
At.config.shadow.algorithm = "glsl"  -- 阴影：glsl / legacy / none
At.config.shadow.color = "@primaryDark"
At.config.shadow.spread = 3
At.config.blur.enabled = true        -- 毛玻璃
At.config.log.level = "debug"        -- 日志等级
At.config.font.size = 16             -- 默认字号
At.config.apply()                    -- 推给各模块（At.lua 启动时已调用一次）
```

## 已知限制

- 文本输入支持点击/拖动定位光标与方向键，但不支持选区、复制粘贴和撤销/重做。
- 布局不支持换行（`flex-wrap`）、grid、绝对定位；百分比需要父容器宽度已知。
- `legacy` 阴影是多次绘制叠加的近似模糊，层数越多越柔和也越耗绘制调用；默认 `glsl` 是单次 SDF 绘制。
- 无自动化渲染测试，圆角、阴影、字体观感需在真机确认。

## 许可证

- 项目代码：**MIT**，见 [LICENSE](LICENSE)。
- 字体：`At/assets/font.ttf`（Noto Sans SC Bold 2.004，© Adobe / Google）与
  `At/assets/emoji.ttf`（Noto Emoji 3.005，© Google LLC）均为 **SIL Open Font License 1.1**。
  许可全文与逐字体版权声明见 [LICENSES/](LICENSES/)，总览见
  [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

OFL 要求随字体分发版权声明与许可全文，因此 `LICENSE` 与 `LICENSES/` 也会被打进 `.love`。

## 贡献

- 改代码前请读 [AGENTS.md](AGENTS.md)：里面有生命周期顺序、尺寸/像素约定、以及一批
  "看起来能顺手改、实际会坏"的陷阱。
- 提交前跑 `lua test_smoke.lua`；改动行为时补充断言。
- 修改对外 API 时同步更新 `docs/` 与 README 的组件/布局表格。
