# 系统通知

`At.notify` 是一个可选的系统通知工具：Linux 下调用 `notify-send`，把通知交给桌面通知守护进程。
它不依赖 LÖVE 之外的 Lua 库，也不需要引入原生模块；桌面环境支持 `notify-send` 时才能获得
图标、超时和 `critical` 等重要通知能力。

## 快速使用

```lua
local At = require("At.At")

local ok, reason = At.notify.available()
if ok then
    At.notify.send{
        title = "At",
        body = "保存成功",
        level = "success",
    }
else
    print("系统通知不可用: " .. tostring(reason))
end
```

`available()` 首次调用时会探测 `command -v notify-send`，结果缓存。没有桌面、没有
`notify-send` 或不是 Linux 时返回 `false, reason`，不会报错，也不会阻塞启动。

## API

### `At.notify.available()`

```lua
local ok, reason = At.notify.available()
-- ok: true / false
-- reason: "notify-send" / "unsupported" / "notify-send missing" / "no io.popen"
```

### `At.notify.send(opts)`

```lua
local ok, reason = At.notify.send{
    title = "重要通知",
    body = "磁盘空间不足",
    level = "error",       -- info / success / warning / error / critical
    urgency = "critical",  -- 可选覆盖：low / normal / critical
    icon = "dialog-error",
    timeout = 8,           -- 秒；不传则使用桌面默认
    appName = "AtLua",
    category = "device",
    transient = true,      -- 不进入通知中心（如果桌面支持）
}
```

返回 `true, "notify-send"` 或 `false, reason`。

`level` 会决定默认的 `urgency` 和图标：

| `level`    | `urgency`  | 默认图标             |
| ---------- | ---------- | -------------------- |
| `info`     | `normal`   | `dialog-information` |
| `success`  | `normal`   | `emblem-default`     |
| `warning`  | `normal`   | `dialog-warning`     |
| `error`    | `critical` | `dialog-error`       |
| `critical` | `critical` | `dialog-error`       |

`error` / `critical` 会以 `--urgency critical` 发送；是否能显示为“重要通知”取决于桌面的
通知守护进程和勿扰设置。

### `At.notify.level(level)`

返回该等级的默认 `urgency, icon`，便于复用：

```lua
local urgency, icon = At.notify.level("warning")
```

### `At.notify.reset()`

清空 `available()` 的缓存。切换桌面、安装 `notify-send` 后可以重新探测。

## 参数

| 字段        | 类型   | 默认值     | 说明                                         |
| ----------- | ------ | ---------- | -------------------------------------------- |
| `title`     | 字符串 | `"At"`     | 通知标题                                     |
| `body`      | 字符串 | `""`       | 通知正文；也可写成 `message`                 |
| `level`     | 字符串 | `"info"`   | 决定默认 urgency / 图标                      |
| `urgency`   | 字符串 | 等级默认值 | `low` / `normal` / `critical`                |
| `icon`      | 字符串 | 等级默认值 | 图标主题名，例如 `dialog-information`        |
| `timeout`   | 数字   | 桌面默认   | 显示秒数；`0` 表示不自动过期（桌面可能忽略） |
| `appName`   | 字符串 | `"AtLua"`  | 应用名                                       |
| `category`  | 字符串 | `nil`      | 通知分类，例如 `device` / `im`               |
| `transient` | 布尔   | `false`    | 使用 `int:transient:1` 提示                  |

## 限制

- 只在 Linux 上探测并调用 `notify-send`；Windows/macOS 返回 `unsupported`。
- `notify-send` 只负责向桌面发送通知，实际外观（图标、按钮、重要程度）由桌面通知守护进程决定；
  没有守护进程时命令可能失败。
- 命令行 `notify-send` 不支持通知内联按钮/动作；需要点击动作时应使用桌面自己的通知 API。
- 发送会等待命令结束，但 `notify-send` 通常立即返回；不要把高频通知放在每帧循环里。
- 和 `At.Toast` 不同，系统通知是进程外的，窗口失焦或最小化后仍然可见（取决于桌面）。

## 与 Toast 配合

普通操作结果用 `At.Toast` 显示在窗口内；需要离开窗口仍可见、或需要更高优先级时再发系统通知：

```lua
local function save()
    -- ... 保存逻辑 ...
    local toast = At.Toast{ text = "保存成功", level = "success" }
    if At.notify.available() then
        At.notify.send{ title = "At", body = "保存成功", level = "success" }
    end
    return toast
end
```
