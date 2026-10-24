# 日志

`At.log` 负责收集日志：等级过滤、条目缓冲、格式化。显示交给 `At.Console`（浮动控制台）。

```lua
local At = require("At.At")

At.log.setLevel("debug")              -- debug / info / warn / error / fatal
At.log.info("玩家 %d 进入房间", 3)     -- 支持 string.format
At.log.warn("帧率偏低", fps)           -- 多参数用空格拼接
At.log.error("资源缺失: %s", path)
```

## 输出到终端（Android 上是 logcat）

默认 `print = true`：每条日志格式化后**同时** `print()` 到 stdout，所以桌面端的终端能看到，
Android 端则进入 **logcat**（Android 没有终端窗口，`print` 会被 LÖVE 写进系统日志）。

```lua
At.log.setPrint(false)                    -- 关掉 stdout 镜像（只留控制台）
At.log.setPrint(true)                     -- 打开（默认）
At.log.setPrint(function(text, entry)     -- 自定义输出目标，例如写文件
    -- text 是格式化后的整行，entry 是原始条目
end)
At.log.getPrint()                         -- 当前设置（布尔或函数）
```

Android 上查看：

```bash
adb logcat -s love            # LÖVE 的日志标签
adb logcat | grep -i love     # 或者不过滤标签，自己 grep
```

手机端也可以装 logcat 阅读器类应用（部分需要 root 或开发者权限）看同一份日志。
注意 LÖVE 自己的报错（如 `Error: ...`）也走 logcat，找不到日志时先确认 `adb devices` 能看到设备。

镜像发生在**写入时**，所以同样受等级过滤影响：`setLevel("warn")` 后 `info` 既不进缓冲也不会打印。

## 写入文件

默认关闭。开启后每条日志按同一格式**追加**写入文件，每行写完立即 `flush`：

```lua
At.log.setFile(true)          -- 文件名取自启动时间，默认 "YYYY-MM-DD_HH-MM-SS.log"
At.log.getFileName()          -- "2026-10-18_16-43-40.log"（相对存档目录）
At.log.getFilePath()          -- 完整路径，便于在日志里打印出来
At.log.setFile(false)         -- 关闭并 flush
At.log.closeFile()            -- 同上；建议在 love.quit 里调用
```

写入位置：

- **LÖVE 项目**优先走 `love.filesystem`：桌面是存档目录（`love.filesystem.getSaveDirectory()`），
  Android 是应用存档目录（`.../files/save/` 下）。LÖVE 12 使用 `love.filesystem.openFile`，LÖVE 11
  只有 `newFile`，`At.log` 会按能力自动选择，避免触发废弃 API 警告。
- 如果存档目录不可写（只读容器、受限环境）或文件名被 PhysFS 拒绝，会**自动退回 `io.open`**，
  写到当前工作目录；用 `At.log.getFilePath()` 查看实际落点。
- **普通 Lua**（没有 `love.filesystem`）同样走 `io.open`，写到当前工作目录。
- 两边都失败时才会打印 `[At.log] 无法创建日志文件: ...（存档目录和当前目录都不可写）`。

文件名 pattern 用 `os.date` 语法，默认 `"%Y-%m-%d_%H-%M-%S.log"`（不用冒号，Windows 也合法）：

```lua
At.log.setFilePattern("%Y-%m-%d_%H-%M-%S.log")  -- 避开 Windows 的非法字符 ':'
At.log.setFilePattern("logs/%Y-%m-%d.log")      -- 按天一个文件（存档目录下会自动建子目录）
```

注意：

- `:` 和空格在 Linux/Android 文件名里合法，**Windows 不允许 `:`**；默认 pattern 已使用 `_` 和 `-`，自定义时也请避开冒号。
- 一次运行只打开一个文件；再次 `setFile(true)` 会按当时的时间重新生成文件名。
- 文件输出与终端镜像、控制台互相独立：`setPrint(false)` 不影响写文件，`clear()` 也不会清空已写入的内容。
- 每行 `flush` 是为了崩溃时保留现场；正常情况下在 `love.quit` 调 `closeFile()` 收尾。

## 等级

| 等级    | 数值 | 说明                 |
| ------- | ---- | -------------------- |
| `debug` | 1    | 细节，默认不显示     |
| `info`  | 2    | 常规信息（默认等级） |
| `warn`  | 3    | 可恢复的异常         |
| `error` | 4    | 操作失败             |
| `fatal` | 5    | 致命错误             |

**过滤发生在写入时**：低于当前等级的日志不会进入缓冲区，之后调高显示等级也看不到（要看到就重新产生）。所以调试期用 `setLevel("debug")`，发布时 `setLevel("info")` 或 `"warn"`。

## 输出格式

默认格式：

```
[时时:分分:秒秒] - [等级/函数名]: 内容
```

例如：

```
[15:04:05] - [INFO/love.load]: 演示启动
[15:04:07] - [WARN/onSubmit]: 提交被拒绝：昵称为空
```

### `At.log.setFormat(format)`

- **字符串模板**：`%s` 依次对应 `时间`、`等级`、`函数名`、`内容`。
  ```lua
  At.log.setFormat("[%s] %s %s: %s")
  -- [15:04:05] INFO love.load: 演示启动
  ```
- **函数**：`function(entry) -> string`，完全自定义。
  ```lua
  At.log.setFormat(function(e)
      return ("%s | %-5s | %s"):format(e.time, e.levelName, e.message)
  end)
  ```

格式在**显示时**应用（`At.log.formatEntry`），所以修改格式会同时影响已经产生的日志在控制台里的显示。

## API

| 函数                                                         | 说明                                           |
| ------------------------------------------------------------ | ---------------------------------------------- |
| `At.log.debug/info/warn/error/fatal(...)`                    | 写一条日志；返回 entry，被等级过滤时返回 `nil` |
| `At.log.setLevel(level)`                                     | 设置等级，接受字符串或 1–5 的数字；非法值报错  |
| `At.log.getLevel()` / `At.log.getLevelName()`                | 当前等级数值 / 名称                            |
| `At.log.setFormat(fmt)` / `At.log.getFormat()`               | 格式模板或函数                                 |
| `At.log.setMaxEntries(n)` / `At.log.getMaxEntries()`         | 缓冲区上限（默认 500，0 = 不限）               |
| `At.log.getEntries()`                                        | 条目数组（按时间升序，只读使用）               |
| `At.log.count()`                                             | 当前条数                                       |
| `At.log.clear()`                                             | 清空缓冲区                                     |
| `At.log.formatEntry(entry)`                                  | 把一条日志渲染成文本（显示端每帧调用）         |
| `At.log.setFile(enabled)`                                    | 开启/关闭文件输出，开启时按 pattern 生成文件名 |
| `At.log.setFilePattern(pattern)` / `At.log.getFilePattern()` | 文件名 pattern（`os.date` 语法）               |
| `At.log.getFileName()` / `At.log.getFilePath()`              | 实际文件名（相对存档目录）/ 完整路径           |
| `At.log.closeFile()` / `At.log.isFileEnabled()`              | 收起文件句柄 / 是否在写文件                    |

条目结构：

```lua
{
    level = 2,           -- 数值等级
    levelName = "INFO",  -- 大写名称
    time = "15:04:05",   -- 仅时分秒
    func = "love.load",  -- 调用者函数名；无法解析时为 "?"
    message = "演示启动",
}
```

### 参数拼接规则

- 只有一个参数：直接 `tostring`。
- 多个参数且第一个是含 `%` 的字符串：尝试 `string.format`，失败则退回空格拼接。
- 其它情况：所有参数 `tostring` 后用空格连接。

## 与控制台配合

```lua
local console = At.Console{ x = 20, y = 20, w = 560, h = 240 }
console:toggle()   -- 或 show() / hide()

function love.draw()
    ui:draw()
    console:draw()     -- 最后画，浮在最上层
end
```

控制台显示 `At.log` 缓冲区里的全部日志，按等级着色：

- **隐藏时**右上角有一个 `LOG` 标签，点它即可打开（移动端没有 `F1`，用这个入口）。
- 打开/关闭默认有动画（淡入淡出 + 轻微下移，弹簧驱动）；`At.Console{ animate = false }` 可关掉。
- 标题栏的 `C` 清空日志、`×` 关闭；桌面上也可以用 `F1` 开关、`F2` 清空。
- 拖动标题栏移动窗口，拖动日志区或滚轮滚动；日志区内部复用 `At.ScrollView`，滚动条与触边光效和普通滚动视口一致。

## 注意

- 函数名来自 `debug.getinfo`，匿名函数或经由包装器调用时可能得到 `"?"`。
- 每条日志都会调用一次 `os.date`，高频日志（例如每帧）建议先做节流。
- 缓冲区满后丢弃最旧的条目；`maxEntries = 0` 时无限增长。
- `At.log` 不依赖 `love`，可以在 `love.load` 之前调用（但 `At.Console` 需要 `love.graphics`）。
- 默认会 `print` 到终端/logcat；如果你用别的日志库或不想污染输出，记得 `At.log.setPrint(false)`。
