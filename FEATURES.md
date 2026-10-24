# AtLua 功能清单

当前 `main` 分支的功能总览。AtLua 是一个纯 Lua、无第三方运行时依赖的 LÖVE UI 组件库与演示程序，兼容 LÖVE 11.x / 12.x。

## 1. 布局引擎

### 基础布局

- `At.Panel` / `At.layout` 的 CSS 子集布局
- `direction = "column" / "row"`
- `gap`
- `padding` / `margin`
- 数字、百分比、`"auto"` 尺寸
- `grow` 按权重瓜分主轴剩余空间
- `align`：`start` / `center` / `end` / `stretch`
- `justify`：`start` / `center` / `end` / `space-between`
- 任意层级嵌套
- 百分比在父容器宽度未知时退化为 `auto`
- 像素对齐、布局幂等、`Panel:draw()` 时自动重排

### flex-wrap

- `wrap = true` 或 `flexWrap = "wrap"`
- row 横向换行
- column 纵向换列
- `alignContent`：`start` / `center` / `end` / `space-between` / `stretch`
- 每一行/列内部独立 `align` / `justify` / `grow`
- 行高取该行最高子项，列宽取该列最宽子项

### grid

- `display = "grid"`，或直接提供 `grid` 表
- `grid.columns`：数字等宽列，或固定像素 / 百分比 / `"auto"` / `"1fr"` 列宽表
- `grid.rows`：可选固定行高表
- 自动行高
- `grid.gap` / `columnGap` / `rowGap`
- 行优先自动填充
- 子项 `w = "100%"` 填满单元格
- 单元格内 `align` / `justify`
- 容器 auto 宽高时按子项自然尺寸估算
- 网格子项可继续嵌套 flex / grid

### 绝对定位

- `position = "absolute"`
- `left` / `top` / `right` / `bottom`
- 数字或百分比偏移
- 初始 `x` / `y` 作为 `left` / `top` 别名
- 左右同时存在且宽度 auto 时自动拉伸
- 上下同时存在且高度 auto 时自动拉伸
- 脱离流式布局
- 不参与父容器 auto 尺寸计算
- 仍参与绘制与事件

### zIndex

- 子项 `zIndex` 或 `z`
- 同一 `Panel` 内按数值升序绘制
- 相同值按创建顺序
- 嵌套 Panel 各自排序

**限制**：`zIndex` 只影响绘制层级，不改变 registry 的事件顺序。点击层级仍由创建顺序决定。

## 2. 组件

共 15 个组件。

| 组件             | 功能                                                                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `At.Panel`       | 布局容器/卡片；flex、wrap、grid、absolute、zIndex、背景、边框、圆角、阴影、透明度                                                                |
| `At.Label`       | 文字、字号、颜色、对齐、自动换行、行高                                                                                                           |
| `At.Button`      | 悬停、按下、禁用、涟漪、阴影、自动对比色、`onPress/onRelease/onClick`、拖出/拖回                                                                 |
| `At.TextInput`   | 单行输入、占位文字、密码、最大长度、点击定位光标、UTF-8 编辑、方向键、Home/End、回车提交、焦点边框、水平滚动、移动端软键盘                       |
| `At.Switch`      | 点击切换、按住左右拖动切换、弹簧动画、自定义颜色                                                                                                 |
| `At.Checkbox`    | 整行点击、勾选动画、主题色背景、自动深/浅勾色、内阴影                                                                                            |
| `At.RadioGroup`  | 1 基单选值、row/column、选中圆点动画、内阴影                                                                                                     |
| `At.Slider`      | 点击跳转、拖动、方向键微调、步长吸附、数值显示                                                                                                   |
| `At.Dial`        | 圆形旋钮、点击/拖动、角度映射、360° wrapping、270° 缺口吸附、刻度、数值                                                                          |
| `At.ProgressBar` | 确定性进度、弹簧过渡、圆角、轨道/填充色                                                                                                          |
| `At.LoadingBar`  | 不确定性循环加载条、速度/段落长度配置                                                                                                            |
| `At.ScrollView`  | 横纵滚动、自动滚动条、滚轮、Shift+滚轮、拖动、平滑滚动、双向惯性、滚动条拖动/悬停变宽、触顶/触底光效、嵌套、`scrollToVisible`                    |
| `At.Console`     | 浮动日志控制台；可拖动、可滚动、等级着色、显示/隐藏动画、`LOG` 标签、清空/关闭                                                                   |
| `At.Toast`       | 底部居中一次性通知、淡入/上滑、倒计时、淡出、自动销毁、info/success/warning/error、自动换行                                                      |
| `At.Dialog`      | 全屏/浮动一次性模态 Dialog；卡片同尺寸；全屏压暗/模糊且不可拖动；浮动可拖动、不压暗；标题、正文、content、actions、关闭按钮、`onClose`、自动销毁 |

## 3. 交互与输入

- 组件统一继承 `At.Component`
- 自动注册到 registry
- 鼠标事件倒序派发
- 单一键盘焦点
- 点击空白或其他组件自动转移/清除焦点
- 悬停、按下、禁用、可见性状态
- 拖出按钮后松开不触发点击
- 输入框 UTF-8 光标与编辑
- 移动端软键盘唤起/收起
- `At.update(dt)` 推进悬停、涟漪和所有动画
- 坐标整数像素对齐
- 嵌套裁剪统一走 `At.clip`

## 4. 主题与系统外观

- 三基色主题：
  - 主题色 `#A7DCFF`
  - 深色槽位 `#3D3D3D`
  - 浅色槽位 `#FFFFFF`
- 完整派生 token：
  - `@primary`、`@primaryDark`
  - `@background`、`@surface`、`@surfaceAlt`、`@surfaceStrong`
  - `@text`、`@textMuted`、`@textFaint`、`@onPrimary`
  - `@border`、`@borderStrong`、`@divider`
  - `@track`、`@knob`
- `At.theme.set{...}` 运行时热切换
- 已有组件立即换色
- `At.theme.foreground(bg)` 自动选择深/浅前景
- `At.theme.reset()` 恢复默认
- 浅色/白色主题专门调色
- 系统明暗：
  - LÖVE 12+ 读取系统 light/dark
  - 不支持时返回 unsupported，演示回退深色
- 系统主题色：
  - GNOME/GTK `gsettings`
  - qt6ct / qt5ct 调色板
  - KDE `kdeglobals`
  - Windows DWM
  - macOS defaults
  - `AT_ACCENT_COLOR` 环境变量覆盖
  - 可选自动 / GTK / Qt 来源
- 系统主题色缓存与手动重置

## 5. 阴影

- 默认 GLSL SDF 外阴影，单次绘制
- smootherstep 边缘衰减
- 1/255 屏幕空间抖动，减少色带
- 可配置颜色、alpha、spread、偏移
- `legacy` 多层矩形阴影
- `none` 全局关闭
- `At.shadow.inner(...)` 内阴影
- RadioGroup / Checkbox 默认启用内阴影
- shader / 白纹理惰性缓存
- 窗口上下文重建后可 reset

## 6. 背景模糊

- `At.blur` 抓取组件背后的画面
- 内置算法：
  - `gaussian`
  - `downscale`
  - `none`
- 支持注册自定义算法
- 可配置强度
- 半透明组件自动使用毛玻璃
- MSAA 感知的 canvas
- `beginFrame/endFrame` 帧包装
- 全屏 Dialog 开启 `At.blur` 时整窗背景模糊
- 关闭时只压暗

## 7. 渲染

- `At.config.render.msaa` 默认 4
- `conf.lua` 建窗前应用 MSAA，避免黑闪
- 运行时查询/设置最大采样
- 圆角、圆形、边框抗锯齿
- 1px 边框 rough 线型
- 嵌套 scissor 求交
- 像素对齐
- 阴影/模糊在窗口重建后重置
- 字体主字体 + emoji fallback

## 8. 日志

- 五级日志：debug / info / warn / error / fatal
- 写入时按等级过滤
- 字符串或函数格式
- 最大缓冲条目数
- 默认输出 stdout / logcat
- 可选文件输出
- 文件名 pattern
- `At.Console` 可视化日志
- 控制台可拖动、滚动、清空、关闭、显隐动画
- 隐藏时保留 `LOG` 入口
- 移动端可点开
- 演示快捷键 F1/F2/F3

## 9. 系统通知

- `At.notify` Linux `notify-send`
- 可用性探测与缓存
- 等级映射 urgency / icon
- 支持：
  - title
  - body / message
  - level
  - urgency
  - icon
  - timeout
  - appName
  - category
  - transient
- `error` / `critical` 映射 critical
- 参数 shell quote
- 非 Linux、缺少 notify-send 或桌面对话失败时返回 `false, reason`
- 不阻塞启动、不报错

## 10. 动画与工具

- `At.motion.spring`：
  - 固定子步积分
  - 刚度/阻尼
  - `setTarget/snap/update/isSettled`
  - 掉帧不发散
- `At.motion.damp`
- `At.motion.easeIn/easeOut/easeInOut`
- `At.color`：hex/token、shade、mix、前景色
- `At.SDF`：圆角矩形 SDF、点击命中
- `At.clip`：嵌套裁剪
- `At.pixel`：像素对齐
- `At.render`：MSAA
- `At.font`：字体缓存
- `At.registry`：注册、事件、焦点
- `At.input`：旧全局输入 + UTF-8 工具
- 旧式立即模式 `At.button(...)`

## 11. 演示程序

- 单个可调整大小的窗口
- 外层纵向 ScrollView
- 组件展示卡片
- 昵称输入、提交、重置
- 涟漪开关
- 画质单选
- 外观：系统 / 深色 / 白色
- 主题色：默认 / 薄荷 / 暖橙
- 系统色来源：自动 / GTK / Qt
- 白色主题专门调色
- QDial 风格旋钮 + wrapping
- 音量 Slider + ProgressBar
- LoadingBar
- Checkbox
- Toast 按钮
- 系统通知 / 重要通知按钮
- 浮动 Dialog / 全屏 Dialog
- 全屏 Dialog 背景压暗 + 可选模糊
- flex-wrap 示例
- 三列 grid 示例
- absolute + zIndex 重叠角标示例
- 标签栏横向溢出 + 嵌套 ScrollView
- 日志控制台
- 背景模糊开关
- 窄窗口内容卡固定宽度 + 外层横向滚动

## 12. 测试、打包与兼容性

- 纯 Lua，无第三方运行时依赖
- LÖVE 11.x / 12.x 兼容
- 能力检测兼容新旧 API
- 无头测试 `lua test_smoke.lua`
- 覆盖布局、wrap、grid、absolute、zIndex、事件、焦点、动画、主题、阴影、模糊、日志、Toast、Dialog、通知 mock、文档同步
- `./pack.sh` 生成 `.love`
- 纯 POSIX sh
- `python3` 打包，不依赖 `zip`
- 排除文档/测试/构建产物
- 保留 `LICENSE` 与 `LICENSES/`
- 字体与第三方资源许可证登记
- 文档：布局、组件、主题、阴影、日志、模糊、通知

## 13. 当前限制

- 不支持 `flex-shrink`、`min-width` / `max-width`、`order`、`aspect-ratio`
- grid 不支持跨行/跨列、命名区域、`auto-flow: column`
- 不支持 `wrap-reverse`
- `zIndex` 只影响绘制，不影响事件命中顺序
- 百分比需要父容器宽度已知
- 布局是单遍排版，没有 CSS 多轮内在尺寸迭代
- Toast 建议同一时刻只显示一个
- Dialog 没有自动超时，`Esc` 不自动关闭
- 系统通知仅 Linux，依赖桌面通知守护进程
- 系统明暗需要 LÖVE 12+
- 系统主题色是 best-effort，失败返回 `nil` + 原因
- 没有 CI，验收依赖无头测试 + 手动 LÖVE 运行
