# AGENTS.md

给在本仓库中工作的 AI 编码代理（以及人类协作者）的说明。**改代码前先读第 4、6、7 节**；**写/改文档前先读第 10 节**。

## 1. 项目是什么

一个 **LÖVE (Love2D) 的轻量 UI 组件库 + 演示程序**，纯 Lua，无第三方依赖、无包管理器。

- `At/` 是库本体（命名空间 `At`）。核心是**组件式**用法：组件创建即登记到注册表，事件由 `At.update / At.mousepressed / At.mousereleased / At.textinput / At.keypressed` 统一分发。
- **布局**：`At.Panel` 提供 CSS 子集式排版（column/row、gap、padding、margin、百分比、auto、grow、align、justify），子组件不需要手写坐标。
- **组件**：`At.Button`、`At.Label`、`At.TextInput`、`At.Switch`、`At.Checkbox`、`At.RadioGroup`、`At.Slider`、`At.ScrollView`、`At.Console`，全部继承 `At.Component` 基类。
- **日志**：`At.log` 提供五级日志、可配置格式与条目缓冲；`At.Console` 显示这些日志。
- 仍保留**立即模式**函数 `At.button(...)`（只画不记状态，无涟漪），仅供旧代码使用。
- `main.lua` 是演示：一张卡片里排了全部组件。
- `test_smoke.lua` 用假 `love` 环境做逻辑回归，**不需要 LÖVE 也能跑**。

使用文档在 `docs/`（`README.md` / `layout.md` / `components.md` / `logging.md` / `blur.md`），
对外口径以文档为准。默认配置集中在 `At/config.lua`（blur / log / font）。

## 2. 环境与常用命令

目标运行时是 **LÖVE 11.x（Lua 5.1 / LuaJIT 语义）**。

```bash
# 运行（需要 love 可执行文件；本机当前未安装）
love .

# 逻辑回归测试（不需要 LÖVE；必须在项目根目录执行）
lua test_smoke.lua

# 格式化（提交前必须跑；配置在 stylua.toml：tab 缩进、列宽 120）
stylua .

# 语法检查（全部文件必须通过）
for f in main.lua At/At.lua At/config.lua At/core/*.lua At/components/*.lua At/effects/*.lua test_smoke.lua; do luac -p "$f" || echo "FAIL $f"; done

# 打包成 .love（纯 POSIX sh，自动切到脚本所在目录，可在任意 cwd 调用）
./pack.sh            # 输出 ./AtLua.love（目录名）
./pack.sh MyGame     # 输出 ./MyGame.love
sh /path/to/pack.sh  # 从外部调用；项目在 /sdcard 等无执行位的位置时用这种写法
```

环境现状（截至本机实测，勿在文档里假设相反）：

- `luac` / `lua` 可用（系统 `lua` 是 5.5，**只用于 `luac -p` 与 `test_smoke.lua`，不能拿来跑游戏**）。
- `love`、`zip` 未安装；`python3`、`unzip` 可用（`pack.sh` 靠 `python3` 的 `zipfile` 打包，不需要 `zip`）。
- `/bin/bash`、`/usr/bin/env` **不存在**（Termux 环境），所以脚本一律写 `#!/bin/sh` 或由调用方显式 `bash xxx.sh`。
- 外部存储 `/sdcard`、`/storage/*` **默认不可访问**，需先 `termux-setup-storage`；项目位于内部存储 `~/AtLua`。项目放在 SD 卡上时无法 `./pack.sh`（无执行位），要用 `sh /storage/<UUID>/AtLua/pack.sh`。
- git 仓库已初始化并提交到 `main`；代理只在本地 `git commit`，**不要 push**（由用户自己推）。

没有测试框架、没有 CI；格式化用 `stylua`（配置见 `stylua.toml`）。验收 = `luac -p` 全通过 + `lua test_smoke.lua` 打印 `SMOKE OK` + 有 LÖVE 时手动跑一次 + （改了资源/目录时）成功打包。

## 3. 目录结构

```
main.lua            # 演示程序：卡片 + 全部组件 + 日志/控制台/模糊
pack.sh             # 打包脚本，产出 <名字>.love
test_smoke.lua      # 无头逻辑测试（假 love 环境），不参与打包
LICENSE             # 项目 MIT 许可（会打进 .love）
THIRD_PARTY_NOTICES.md  # 第三方资源与许可证总览（不入包）
LICENSES/           # 第三方许可全文与逐字体版权（会打进 .love）
AGENTS.md           # 本文件（代理约束），不参与打包
docs/               # 使用文档，不参与打包
  README.md         #   快速开始、事件模型、配置、组件一览、常见问题
  layout.md         #   布局引擎（CSS 子集对照、尺寸规则、限制）
  components.md     #   每个组件的属性/方法/回调/示例
  logging.md        #   日志等级、输出格式、文件、控制台
  blur.md           #   背景模糊：启用、算法、性能
AtLua.love          # 构建产物（约 12 MB，已打进字体），不要手改、不要当源码
At/
  At.lua            # 门面：聚合模块 + 生命周期入口 + 旧式 At.button
  config.lua        # 集中配置：blur / log / font，改完调 At.config.apply()
  core/             # 基础设施（不画具体控件）
    registry.lua    #   组件注册表、事件分发、唯一键盘焦点
    component.lua   #   组件基类：几何/状态/焦点/measure/生命周期
    layout.lua      #   CSS 子集布局引擎（纯函数）
    clip.lua        #   裁剪求交（嵌套 scissor 必须用它）
    motion.lua      #   动画：弹簧（固定子步积分）与缓动函数
    pixel.lua       #   像素对齐
    color.lua       #   hex → RGBA、shade、mix
    SDF.lua         #   圆角矩形 SDF + 点击命中
    shadow.lua      #   多层缩放矩形模拟阴影
    font.lua        #   字体装配与缓存（资源路径来自 config.font）
    input.lua       #   旧的全局文本输入 + UTF-8 工具
    log.lua         #   日志：等级、格式、缓冲、stdout、文件
  components/       # 具体组件
    Panel.lua Label.lua Button.lua TextInput.lua Switch.lua Checkbox.lua
    RadioGroup.lua Slider.lua ScrollView.lua Console.lua
  effects/          # 视觉效果
    Ripple.lua      #   涟漪发射器
    blur.lua        #   背景模糊：canvas 快照 + 可插拔算法
  assets/           # 运行时资源
    font.ttf        #   主字体，约 10.5 MB
    emoji.ttf       #   emoji 字体（仅作回退，主字体是当前字体），约 0.9 MB
```

## 4. 生命周期与每帧顺序（最容易踩的地方）

```lua
function love.load()                   At.font.init(16)                  end
function love.update(dt)               At.update(dt)                     end
function love.draw()                   card:draw()                       end
function love.mousepressed(x, y, b)    At.mousepressed(x, y, b)          end
function love.mousereleased(x, y, b)   At.mousereleased(x, y, b)         end
function love.textinput(t)             At.textinput(t)                   end
function love.keypressed(k)            At.keypressed(k)                  end
function love.wheelmoved(dx, dy)       At.wheelmoved(dx, dy)             end
```

- `At.update(dt)`：推进悬停检测、涟漪、开关/滑动条/控制台等动画。**不调用它，涟漪与动画会卡住**；隐藏但正在播关闭动画的组件（例如 `At.Console`）也只有在 `At.update` 里才会继续推进。
- `At.mousepressed`：按创建顺序**倒序**派发（后创建的在上层），第一个消费即停；点到焦点组件之外的组件或空白处会**收走键盘焦点**。
- `At.mousereleased`：广播给所有组件（按下的组件可能已不在指针下）。
- `At.textinput` / `At.keypressed`：**只发给当前焦点组件**（`At.getFocus()`）。
- `At.mousepressed` 内部会遍历组件；`At.Panel` **不登记**（`autoRegister=false` + `passthrough=true`），所以容器永不抢点击。
- `At.font.init(size)` 必须在任何文字绘制前调用；组件用 `At.font.get(size)` 取缓存字体，不改全局当前字体。
- 组件的 `draw()` 会保存/恢复颜色、字体、线宽；`TextInput` 还会保存/恢复 scissor。
- `Panel:draw()` 每次都先 `layout()` 再画（幂等），所以拖窗口/改文本后下次绘制自动重排。
- `At.wheelmoved` 倒序派发、首个消费即停；目前只有 `ScrollView` 实现，且只在指针位于视口内时消费。
- `TextInput` 聚焦时会调 `love.keyboard.setTextInput(true, x, y, w, h)` 唤起移动端软键盘，失焦时调 `setTextInput(false)` 收起；建议在 `love.focus(false)` 里 `At.clearFocus()`。
- `ScrollView:draw()` 先 `layout()`（把视口宽度作为可用宽度传给内容、算出 `maxScroll`）再带 scissor 画内容；窗口变化时调 `view:setRect(...)` 并重启排版。

## 5. API 速查

对外坐标一律"左上角 + 宽高"；颜色 alpha 对外 **0–255**，内部转 0–1。

### 布局（`At.Panel` + `At.layout`）

```lua
At.Panel{
    x, y, w, h,                    -- 数字 / "50%" / "auto"
    direction = "column",          -- column / row
    gap = 8,
    padding = 0,                   -- number 或 { left, top, right, bottom }
    align = "start",               -- start / center / end / stretch
    justify = "start",             -- start / center / end / space-between
    background, borderColor, borderWidth, radius, shadow, alpha,
    children = { ... },
}
```

子组件可用 `w/h`（数字/百分比/auto）、`margin`（数字或具名表）、`grow`（数字，>0 才参与瓜分主轴剩余空间）、`visible`。
`At.layout` 纯函数：`pixels(value, base)`、`sides(value)`、`childMeasure(child, availW, availH)`、`measure(node, availW, availH)`、`arrange(node, availW, availH)`。
`At.clip`：`capture/apply/restore/resolve`，所有嵌套裁剪必须用 `clip.apply` 求交，不能直接 `setScissor`。
`At.pixel`：`round(value)`、`xy(x, y)`，绘制前对齐整数像素。
**百分比在父容器没有可用宽度时退化成 auto**（不会变 0）。

### 组件（全部继承 `At.Component`）

| 组件 | 关键属性 | 回调 |
| --- | --- | --- |
| `At.Panel` | 见上表 | 无（不接收事件） |
| `At.Label` | `text, color, fontSize, align, wrap, lineHeight` | 无 |
| `At.Button` | `text, color, alpha, hoverColor, pressedColor, shadow, shadowArgs, ripple, paddingX/paddingY` | `onPress(self,mx,my)` / `onRelease(self,mx,my,inside)` / `onClick(self,mx,my)` |
| `At.TextInput` | `text, placeholder, password, maxLength, borderColor, focusBorderColor, caretColor` | `onChange(text,self)` / `onSubmit(text,self)` |
| `At.Switch` | `value, color, onColor, knobColor, animate, springStiffness/springDamping` | `onChange(value,self)` |
| `At.Checkbox` | `text, checked, size, gap, checkColor` | `onChange(checked,self)` |
| `At.RadioGroup` | `options, value(1 基), direction, gap, size, selectedColor` | `onChange(index,label,self)` |
| `At.Slider` | `min,max,step,value, showValue, trackColor, fillColor, thumbColor` | `onChange(value,self)` |
| `At.ScrollView` | `content, w, h, scrollX, scrollY, scrollbar, wheelStep, drag, smooth, smoothSpeed, momentum, padding` | `onScroll(value,maxScroll,self,axis)` |
| `At.Console` | `w, h, visible, title, headerH, padding, levelColors, alpha, fontSize, animate, springStiffness/springDamping, openOffset` | 无（内部读 `At.log`） |

基类方法：`draw/update/mousepressed/mousereleased/measure/destroy`、`contains(px,py)`、`setRect/setPosition/setSize`、`setEnabled/setVisible`、`isHovered/isPressed/isFocused/isInteractive`、`focus/blur`、`declaredWidth/declaredHeight/invalidateSize`、`font()`。

### At 入口

`At.update(dt)`、`At.mousepressed(...)`、`At.mousereleased(...)`、`At.textinput(t)`、`At.keypressed(k)`、`At.wheelmoved(dx,dy)`、`At.focus(c)`、`At.clearFocus()`、`At.getFocus()`、`At.add(c)`、`At.remove(c)`、`At.registry`、`At.layout`、`At.Component`、`At.motion`、`At.blur`（`setEnabled/isEnabled/setAlgorithm/registerAlgorithm/setStrength/beginFrame/endFrame/drawBackdrop/stats/reset`）。

`At.config`（`At/config.lua`）：`blur = {enabled, algorithm, strength}`、`log = {level, print, maxEntries, file, filePattern}`、`font = {size, main, emoji}`；`At.config.apply()` 把配置推给各模块（`At.lua` 启动时已自动调用一次）。

旧式立即模式：`At.button(x, y, w, h, res, hex, alpha, shadow, shadowArgs) -> rect`。**无状态、无涟漪、会留下非白当前颜色。**

### 其它模块

- `color.hexToRGBA(hex, alpha?)`、`color.setColor(hex, alpha?)`、`color.shade(hex, factor)`、`color.mix(hexA, hexB, t)`。
- `SDF.roundRectSDF(px, py, rect)`（负数在内部）、`SDF.isClick(rect)`（读实时鼠标位置）。
- `Ripple.new{...}` 实例（`:add/:release/:update/:draw/:count`）+ 旧单例 `At.Ripple.*`。动画按 `dt` 衰减，不传按 60Hz。
- `input.setActive/input()/get/set/clear/join/keypressed/isActive` + `input.length(str)`、`input.removeLast(str)`（UTF-8 安全）。
- `font.get(size)` 缓存字体；`font.init(size)` 设置全局 `mainFont`/`emoji`，并以**主字体**为当前字体。主字体优先、emoji 只作 fallback：反过来（emoji 当主字体）会让数字、空格、`#`/`*` 用上 keycap 的长宽字，排版明显变宽。
- `shadow(x, y, w, h, res, color, radius, layers, offsetX, offsetY)`：`color[4]` 是整体最大不透明度（内部已按 `layers` 归一化，改层数不会让阴影变黑），`layers` 只影响柔和度。
- `motion.spring{value, target, stiffness, damping, velocity}` → `Spring`（`:setTarget/:snap/:update/:isSettled`，`.value/.target/.velocity`）；`motion.damp(current, target, speed, dt)`；`motion.easeIn/easeOut/easeInOut(t)`（`0..1`）。弹簧用固定子步（1/240s）积分，掉帧不发散；`update` 的 `dt <= 0` 直接返回。
- `log.debug/info/warn/error/fatal(...)`（写日志，被过滤时返回 nil）、`setLevel/getLevel/setFormat/setMaxEntries/setPrint/getPrint/setFile/setFilePattern/getFileName/getFilePath/closeFile/isFileEnabled/clear/count/getEntries/formatEntry`。默认格式 `[时间] - [等级/函数名]: 内容`，过滤发生在写入时，默认同时 `print` 到 stdout（Android 即 logcat）。

## 6. 代码约定

- **缩进用 tab（显示宽度 4）**，由 `stylua .` 统一；提交前必须在仓库根目录跑一次 `stylua .`，不要手工对齐或混入空格缩进（GLSL 字符串里的缩进属于 shader 代码，不受影响）。格式化配置在 `stylua.toml`（tab、列宽 120、Unix 换行），不要改回空格。
- 模块形状：`local M = {} ... return M`。require 路径从源码根开始且**不带 `.lua`**：`require("At.core.color")`。
- **目录分层固定**：`At/core/`（基础设施）、`At/components/`（组件）、`At/effects/`（视觉特效）、`At/assets/`（资源）。新组件放 `At/components/`，新基础设施放 `At/core/`。
- **新组件必须继承 `At.Component`**（`require("At.core.component")`）：`local proto = setmetatable({}, { __index = Component })`，构造函数调 `Component.instantiate(proto, opts, DEFAULTS)`，并导出 `setmetatable(MyComp, { __call = ... })` 以便 `At.Xxx{...}`。
- **默认值写进 `At/config.lua`**，不要在组件里散落魔法数字；运行时改 `At.config` 后需要 `At.config.apply()` 才会生效（直接设 `At.blur.*` / `At.log.*` 仍然立即生效）。
- **尺寸分两层**：`_specW/_specH` 是原始规格（"auto"/"50%"/数字），`w/h` 是当前像素。需要声明值时用 `declaredWidth()/declaredHeight()`；内容变化后调 `invalidateSize()`，**不要**手写 `self.w = nil` 或清 `_specW`。
- 新组件要实现 `measure(availW, availH)` 返回自然尺寸，布局引擎在 `auto` 时依赖它。
- **日志统一走 `At.log`**：不要在组件里直接 `print`（控制台看不到）；新增日志等级或格式语义要同步 `docs/logging.md`。
- **纯展示组件必须 `interactive = false`**（或干脆不实现 `_press`）：否则它会消费点击、并在 `ScrollView` 里挡住拖动。`Label` 就是这样处理的。
- 命中判断用传入坐标（`contains(px,py)`）；需要鼠标位置的地方（拖拽）用 `love.mouse.getPosition()` 并在 `_tick` 里轮询，不要假设有 `love.mousemoved`。
- 绘制改动 `love.graphics` 状态（颜色/字体/线宽/线型/scissor）必须保存并恢复；`Component:draw` 已处理颜色/字体/线宽/线型（并强制 `lineStyle = "rough"` 让 1px 边框清晰），scissor 必须用 `At.clip` 配对处理。
- **坐标一律对齐整数像素**：绘制前用 `At.pixel.xy/round`；布局已经对齐过一次，但滚动位移、动画插值、居中计算仍可能产生小数。
- **动画统一用 `At.motion.spring`**（需要缓动再用 `easeIn/Out/InOut`），不要自己写 `value = value + (target - value) * k` 的指数逼近；每个组件在 `_tick(dt)` 或 `update(dt)` 里推进自己的弹簧，并给 `animate = false` 留立即落位的分支。
- 焦点只通过 `self:focus()/self:blur()` 或 `registry.setFocus` 改，不要自建 `isFocused` 字段。
- 命名沿用现状，不要"统一"：大写开头是 `At`、`SDF`、`Ripple`、`Button`、`Label`、`Panel`、`TextInput`、`Switch`、`Checkbox`、`RadioGroup`、`Slider`、`Component`；小写是 `color`、`shadow`、`input`、`font`、`layout`、`registry`。
- 颜色对外接受 `hex` + 0–255 `alpha`，不要引入 0–1 风格的第二套接口。
- 新增模块**不要**创建全局变量；已有全局（`SDF`、`color`、`shadow`、`mainFont`、`emoji`、`removeLastUTF8Char`）是遗留兼容面，可以读取，别扩散。
- 不引入第三方库、shader 文件或构建工具。
- **第三方资源必须登记许可证**：许可证全文放 `LICENSES/`（`.txt`，会随包分发），总览写入 `THIRD_PARTY_NOTICES.md`；不得删除资源内部的版权/许可元数据（例如字体 `name` 表）。
- **不要从 `pack.sh` 排除 `LICENSE` 与 `LICENSES/`**：OFL 要求随字体一起分发版权声明和许可全文。
- 改对外 API / 新组件 / 布局语义 → **同步写文档（第 10 节）** 并在 `test_smoke.lua` 补断言。

## 7. 已知限制与陷阱

1. **注册表只增不减**：组件创建即登记，不 `destroy()` 就永远留在 `registry` 里（收事件 + 占内存）；`Panel:destroy()` 会连带销毁子组件。
2. **`Panel` 不登记、不消费事件**：容器点击由子组件自己处理；不要给 Panel 加 `mousepressed`，否则会挡住子组件。
3. **`auto` 尺寸会被排版写成像素**：原始规格保存在 `_specW/_specH` 里，重排会还原；但如果你绕过 `setText`/`invalidateSize` 直接改 `self.w`，就会固化错误尺寸。
4. **百分比需要已知宽度**：父容器 `w` 为 auto 且没有 `_availW` 时，`"50%"` 退化成 auto，不会变成 0。
5. **嵌套容器靠 `_availW` 记住可用区**：`layout.arrange` 会写子容器的 `_availW/_availH`；容器自己 `:draw()` 时用它重排。绕过 `arrange` 直接调用会丢失百分比基数。
6. **单一键盘焦点**：同一时刻只有一个组件收 `textinput`；点空白或点其他组件会失焦。旧 `At.input` 是另一套全局状态，不要和新焦点混用。
7. **`At.button`（立即模式）仍是旧语义**：无状态、无涟漪、会把当前颜色留成按钮色。
8. **涟漪不会自己消失**：只有 `release()` 过的涟漪才会被回收（组件的拖出/松开已处理）。
9. **`unpack` 依赖 Lua 5.1/LuaJIT**（`At.button`、`Button:draw`、`Panel:_draw` 展开 `shadowArgs` 处）；Lua 5.2+ 直接运行会 `attempt to call a nil value`，`luac -p` 查不出来。
10. **阴影是 O(layers) 次 `rectangle`**，默认 20 层；字体两个 TTF 约占包体 99%；`AtLua.love` 是产物不要手改。
11. **渲染类问题无法用测试证明**：`test_smoke.lua` 是假 `love` 的逻辑回归，圆角、阴影、裁剪、字体观感必须在真机 `love .` 看。
12. **`ScrollView` 必须晚于内容创建**：事件按注册表倒序派发，这样它才能先判断点击该不该交给子组件。它把"落在空白处或被动组件上的拖动"当作滚动，只有可交互子组件（按钮/输入框/滑动条等）才不拦截。
13. **滚出视口的子组件仍会被点击**：`ScrollView` 用 `containsDescendant` 把这类点击吃掉，但前提是它先收到事件；如果它比子组件先创建，就会失效（见上一条）。
14. **软键盘依赖 `setTextInput`**：桌面端不弹键盘是正常的；移动端聚焦时会带输入框矩形调用 `love.keyboard.setTextInput(true, x, y, w, h)`，失焦收起。别忘了把 `love.textinput`/`love.keypressed`/`love.wheelmoved` 接到 `At.*`。
15. **阴影透明度必须按层数归一化**：`shadow` 用多层叠加模拟模糊，曾经每层固定 7.5%，20 层叠出约 80% 不透明，看起来像卡片底下有一圈黑底。现在 `layerAlpha = color[4] * 2 / (layers + 1)`，`color[4]` 即最终最大不透明度；不要再改回"按层直接给 alpha"。
16. **嵌套 scissor 必须求交**：`TextInput` 曾直接 `setScissor` 覆盖了 `ScrollView` 的裁剪，导致滚动时输入框文字画到视口外（看起来像"图层错乱"）。新代码一律用 `At.clip.apply/restore`，不要直接 `love.graphics.setScissor`。
17. **`scrollY` 保持浮点**：平滑滚动与惯性都靠它，`layout()` 里只对内容位移做 `pixel.round`；不要取整存回（会破坏缓动、让滚动条抖）。滚动 API 分工：`setScroll` 立即（拖拽/滚动条/`scrollToVisible`）、`scrollTo/scrollBy` 平滑（只改 `_scrollTarget`，由 `_tickScroll` 缓动），`onScroll` 在平滑过程中逐帧触发。
18. **被动组件会挡住拖动（已踩过）**：`Label` 早期没有 `interactive = false`，它的矩形几乎铺满整行，`ScrollView` 误判"点在子组件上"而拒绝拖动，表现为"大片区域拖不动"。现在 `ScrollView` 只把 `isInteractive()` 为真的子组件当作拦截目标；新增纯展示组件务必设 `interactive = false` 或不实现 `_press`。
19. **滚动条宽度是动画值**：`_barW` 每帧向 `scrollbarWidth` / `scrollbarActiveWidth` 收敛，`_barMetrics` 用的是它；命中判定另用 `scrollbarHitWidth`，两者不要混用。
20. **Android 没有终端窗口，也没有 F1**：`At.log` 默认 `print` 到 stdout → logcat（`adb logcat -s love`）；`At.Console` 隐藏时靠右上角 `LOG` 标签（`tab = true`）点开，标题栏 `C` 清空，不要只依赖键盘快捷键。自定义输出用 `At.log.setPrint(function(text, entry) ... end)`。
21. **日志文件默认关闭且写入存档目录**：`At.log.setFile(true)` 才写文件，文件名是 `os.date` pattern（默认 `%Y-%m-%d %H:%M:%S.log`）。LÖVE 下必须走 `love.filesystem`（源码目录只读，Android 只有应用存档目录可写），普通 Lua 才用 `io`；Windows 文件名不能含 `:`，跨平台用 `%H-%M-%S`。记得在 `love.quit` 调 `closeFile()`。
22. **控制台必须最后创建/绘制**：事件按注册表倒序派发、绘制按调用顺序，`At.Console` 晚于页面内容创建并在 `love.draw` 最后 `:draw()`，否则会被内容盖住或被抢先消费事件。日志的等级过滤发生在**写入时**（调高等级看不到旧日志），格式则在**显示时**应用（`formatEntry`），所以改格式会影响历史日志的显示。
23. **字体主次不能反**：`At/core/font.lua` 里 `main:setFallbacks(emojiFont)`，当前字体是主字体。若改回"emoji 为当前字体、主字体作回退"，数字/空格会变成 emoji 字体的长宽字（keycap 设计），看起来"空格和数字特别宽"。
24. **`ScrollView` 是双向的**：`layout()` 先量内容自然宽度，`_availW` 取 `max(视口内宽, 自然宽)`——比视口窄的内容按视口宽排版（保证 `"100%"` 有效），更宽的内容保留自身宽度以产生横向滚动。横竖滚动条只在对应 `maxScrollX/Y > 0` 时绘制，两条轨道互相让出对方厚度；命中判定分 `_barHit`（纵）与 `_hbarHit`（横），别只改一个。滚轮 `dx` 横向、`dy` 纵向、`Shift+滚轮` 走横向，某个轴没有滚动空间时会退让给另一轴。`ScrollView` 自身 `interactive = true`，所以嵌套时外层会让事件给内层（但滚轮不做"内层滚到底再传给外层"的链式滚动）。
25. **背景模糊需要每帧包住 `beginFrame/endFrame`**：组件只在 `alpha < 255` 时调用 `drawBackdrop`，且必须能从当前 canvas 取到背景快照；直接画到屏幕（当前 canvas 为 nil）时模糊会被跳过而不报错。每个模糊组件每帧一次全画布拷贝，组件多时开销明显。`gaussian` 需要 shader，失败自动回退 `downscale`；canvas 不支持时 `At.blur` 自动关闭。模糊一定要"先降采样再密集采样"：高分辨率 + 稀疏采样会把画面复制成小方块，`gaussian` 固定先降到 1/2、采样间距 radius/4，`downscale` 用多级金字塔，勿改回一步大倍数缩放。
26. **改 `At.config` 不会自动生效**：`At.lua` 只在启动时 `apply()` 一次；运行时改完 `At.config.blur/log/font` 要再调 `At.config.apply()`。字体路径来自 `config.font`（`At/core/font.lua` 读取），移动资源时同步改这里与 `LICENSES/`。
27. **许可证不能只写一句"MIT/OFL"**：字体版权与 OFL 全文必须实际随包分发（`LICENSES/`），且 `pack.sh` 不能把它们排除掉；替换字体时要重新读字体的 `name` 表确认版权方，不要凭文件名猜。
28. `pack.sh` 直接覆盖同名 `.love`，排除 `pack.sh`、`test_*.lua`、`AGENTS.md`、`*.md`、`docs/`、`*.love`、`*.zip`、`*.bash`、`*.log`、`*.tmp`、`.gitignore` 与 `.git`/`.vscode`/`.idea`/`__pycache__`/`temp_package`/`node_modules`。排除规则在 python 与 zip 两条分支各写一份，新增产物类型时两处都要改。
29. **动画不要自己积分**：手写 `value = value + (target - value) * (1 - exp(-speed*dt))` 在不同帧率下手感不同、且没法过冲。统一用 `At.motion.spring`（固定子步 1/240s），把它放在 `_tick(dt)`（可见组件）或组件自己的 `update(dt)`（隐藏时还要继续的动画，如控制台关闭）里推进；`animate = false` 时必须 `:snap()` 到目标，保证测试与低性能路径立即一致。绘制时把弹簧值 `math.min/max` 夹到用途需要的范围（例如 alpha 用 `min(1, v)`，否则 `>1` 会让半透明判定失效）。
30. **控制台的开关动画跨越 `visible`**：`hide()` 只把 `visible` 置 `false`，窗口还要淡出，所以 `Console:update` 独立推进弹簧、`draw` 在 `visible or open > 0.001` 时继续画窗口，`open < 0.999` 时画 `LOG` 标签并让标签随进度淡出。动画期间窗口不接收鼠标事件（`visible == false`），这是有意的；改这里别把"隐藏"直接当成"不画"。

## 8. 改动检查清单

- [ ] `for f in main.lua At/At.lua At/config.lua At/core/*.lua At/components/*.lua At/effects/*.lua test_smoke.lua; do luac -p "$f"; done` 全部通过。
- [ ] `lua test_smoke.lua` 打印 `SMOKE OK`；行为变了就补断言（布局数值、组件状态、焦点）。
- [ ] 没有新增全局变量；模块仍 `return` 表；组件继承 `Component` 且实现 `measure`；纯展示组件 `interactive = false`。
- [ ] 尺寸读写走 `declaredWidth/declaredHeight` + `invalidateSize`，没有手动清 `_specW`。
- [ ] `love.update` 仍调用 `At.update(dt)`；`draw` 里每个组件都 `:draw()`；`mousepressed/mousereleased/textinput/keypressed/wheelmoved` 都已接线。
- [ ] 绘制后颜色/字体/线宽/线型/scissor 已恢复；嵌套裁剪走 `At.clip`；文字与形状坐标已对齐整数像素。
- [ ] 对外 API 变了：更新 `docs/`（第 10 节）、本文件第 3/5 节、`main.lua` 演示与测试。
- [ ] 新增可配置项时放进 `At/config.lua` 并同步 `docs/README.md` 的配置表与 `At.config.apply()`。
- [ ] 有 LÖVE 时 `love .` 手动过一遍：悬停、按下、拖出/拖回、输入、开关动画、拖动滑动条、滚轮平滑滚动、拖拽惯性。
- [ ] 涉及平滑滚动/惯性的断言必须模拟若干帧（`At.update(1/60)`），不能只改目标就断言位置。
- [ ] 日志改动覆盖等级过滤、格式（字符串与函数）、缓冲裁剪；控制台改动覆盖显隐、拖动、滚动、开关动画。
- [ ] 动画改动模拟多帧 `At.update(1/60)` 再断言（不能改完目标就断言最终值），并覆盖 `animate = false` 的立即落位。
- [ ] 提交前跑过 `stylua .`，且 `stylua --check .` 通过。
- [ ] 改了目录/资源后跑 `./pack.sh`，并 `unzip -Z1 AtLua.love` 抽查（不应出现 docs/、*.md、test_*.lua；**应包含 LICENSE 与 LICENSES/**）。
- [ ] 新增/替换字体或其它第三方资源时，`LICENSES/` 与 `THIRD_PARTY_NOTICES.md` 已更新，且版权信息未被删除。

## 9. 不要做

- 不要重命名或移动 `At/` 下的文件与模块（`require("At.core.x")` 等路径、`.love` 内路径、文档里的结构图都依赖当前分层：`core/`、`components/`、`effects/`、`assets/`）。
- 不要删除/替换 `At/assets/*.ttf`，也不要改 `At/core/font.lua` 里字体路径的写法（路径在 `At/config.lua` 的 `font` 段）。
- 不要把组件私有字段（`_hover`、`_pressed`、`_ripple`、`_specW`、`_availW`）当公开 API 用；要暴露就加方法。
- 不要在 `Component:draw` 之外留下未恢复的 `love.graphics` 状态，也不要绕过注册表自建组件列表。
- 不要让 `Panel` 消费鼠标事件或参与焦点。
- 不要在未手动运行的情况下声称 UI/视觉效果正常——测试只背书逻辑。
- 不要把 `docs/` 的内容整段抄进本文件：这里写约束，文档写用法。
- 不要把 `temp_package/`、新生成的 `.love`、系统缓存目录留在工作区。

## 10. 文档规范

文档是 API 的一部分，**和代码在同一次改动里完成**。

### 目录与职责

| 文件 | 写什么 | 不写什么 |
| --- | --- | --- |
| `docs/README.md` | 快速开始、事件模型、组件一览、常见问题 | 内部实现、逐属性细节 |
| `docs/layout.md` | CSS 子集对照、尺寸规则、排版时机、限制、示例 | 组件属性表 |
| `docs/components.md` | 每个组件的属性表、方法、回调、示例 | 布局算法细节 |
| `docs/logging.md` | 日志等级、格式、缓冲、与控制台配合 | 组件属性表 |
| `docs/blur.md` | 背景模糊的启用、算法、性能与限制 | 组件属性表 |
| `AGENTS.md`（本文件） | 代理约束、约定、陷阱、改哪里 | 使用教程正文 |

### 什么时候必须更新文档

- 新增组件，或新增/修改公开属性、方法、回调参数。
- 布局能力或语义变化（例如百分比退化规则、stretch 生效条件）。
- 破坏性变更：在对应小节开头加"变更说明"，给出旧写法与新写法。
- 修 bug 改变了可观察行为（例如按压会话、焦点转移规则）。

### 怎么写

- 全中文；面向使用者，不贴大段内部实现；用表格列属性/方法，示例用 ```lua 且能直接跑。
- 每个组件固定骨架：**一句话定位 → 属性表（属性/类型/默认值/说明）→ 方法表 → 回调 → 示例**。
- 默认值必须与源码 `DEFAULTS` 一致，签名必须与 `proto` 方法一致；没实现的能力不要写成"支持"。
- 示例用具体数字或百分比，不要引用未定义变量；组件标题统一 `## At.Xxx`（GitHub 锚点 `#at-xxx`）。
- 写不了的能力放进"限制"，不要写 TODO 或"未来会支持"。

### 同步与校验

- `lua test_smoke.lua` 末尾有文档断言：`docs/components.md` 必须出现全部组件名，`docs/layout.md` 必须出现 `grow`/`justify`，`docs/README.md` 必须出现 `love.update`，本文件必须出现"文档规范"。新增组件时同步加断言。
- 改对外 API 的顺序：源码 → `docs/components.md` → 本文件第 5 节 → `main.lua` 演示 → `test_smoke.lua`。
- `docs/` 与 `*.md` 不参与打包（`pack.sh` 已排除），不要把它们当运行时资源引用。
