-- 日志：等级过滤 + 可配置格式 + 条目缓冲，供 At.Console 之类的显示端消费。
--
--   At.log.setLevel("debug")          -- debug / info / warn / error / fatal
--   At.log.setFormat("[%s] - [%s/%s]: %s")  -- 时间 / 等级 / 函数名 / 内容
--   At.log.info("玩家 %d 进入", 3)
--   At.log.error("资源缺失: %s", path)
--
-- 默认等级是 info：debug 日志默认被丢弃（在写入时过滤，不占用缓冲）。
-- 默认格式：[时时:分分:秒秒] - [等级/函数名]: 内容，例如
--   [15:04:05] - [INFO/love.load]: 演示启动

local log = {}

-- 数值越大越严重；等级过滤用 >= 比较
local LEVELS = {
	debug = 1,
	info = 2,
	warn = 3,
	error = 4,
	fatal = 5,
}

log.levels = LEVELS

local state = {
	level = LEVELS.info,
	format = "[%s] - [%s/%s]: %s",
	maxEntries = 500,
	entries = {},
	-- 默认镜像到 stdout：桌面端是终端，Android 端是 logcat
	print = true,
	-- 文件输出（默认关闭，用 setFile(true) 开启）
	file = {
		enabled = false,
		pattern = "%Y-%m-%d_%H-%M-%S.log", -- os.date 格式；不用冒号，Windows 也合法
		name = nil,
		absolute = nil,
		handle = nil,
		viaLove = false,
	},
}

-- 本模块自己的函数：查找调用者时要跳过
local ownFunctions = {}

-- 取调用者函数名；拿不到名字时退化为 "文件:行号"（debug 库缺失时为 "?"）
local function callerName()
	if not (debug and debug.getinfo) then
		return "?"
	end

	-- 从 3 开始向上找：1 = callerName，2 = emit，3 起才是调用方。
	-- 注意 log.xxx 里 `return emit(...)` 是尾调用，会复用栈帧，所以层级不固定，
	-- 必须逐层跳过本模块自己的函数。
	for level = 3, 8 do
		local info = debug.getinfo(level, "nSlf")
		if not info then
			return "?"
		end

		if not ownFunctions[info.func] then
			if info.name and info.name ~= "" then
				return info.name
			end
			if info.what ~= "C" and info.currentline and info.currentline > 0 then
				local file = (info.short_src or "?"):match("[^/\\]+$") or "?"
				return file .. ":" .. info.currentline
			end
			return "?"
		end
	end

	return "?"
end

-- 支持 "a=%d" 这种格式化，也支持多个值用空格拼接
local function formatArgs(...)
	local count = select("#", ...)
	if count == 0 then
		return ""
	end

	local first = ...
	if count > 1 and type(first) == "string" and first:find("%%", 1, false) then
		local ok, formatted = pcall(string.format, ...)
		if ok then
			return formatted
		end
	end

	local parts = {}
	for i = 1, count do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

local writeFile -- 前置声明：emit 里要用，具体实现在文件输出一节

local function emit(levelName, ...)
	local level = LEVELS[levelName]
	if level < state.level then
		return nil
	end

	local entry = {
		level = level,
		levelName = levelName:upper(),
		time = os.date("%H:%M:%S"),
		func = callerName(),
		message = formatArgs(...),
	}

	-- 统一渲染一次：终端镜像与文件输出共用同一行文本
	local text = log.formatEntry(entry)

	-- 终端 / logcat 镜像。用 pcall 包住：自定义 sink 出错不该影响游戏逻辑
	if state.print then
		if type(state.print) == "function" then
			pcall(state.print, text, entry)
		else
			print(text)
		end
	end

	writeFile(text)

	local entries = state.entries
	entries[#entries + 1] = entry

	local maxEntries = state.maxEntries
	if maxEntries and maxEntries > 0 and #entries > maxEntries then
		table.remove(entries, 1)
	end

	return entry
end

function log.debug(...)
	return emit("debug", ...)
end

function log.info(...)
	return emit("info", ...)
end

function log.warn(...)
	return emit("warn", ...)
end

function log.error(...)
	return emit("error", ...)
end

function log.fatal(...)
	return emit("fatal", ...)
end

for _, fn in ipairs({ log.debug, log.info, log.warn, log.error, log.fatal, emit }) do
	ownFunctions[fn] = true
end

-- ---------- 配置 ----------

function log.setLevel(level)
	if type(level) == "number" then
		state.level = math.max(1, math.min(5, math.floor(level)))
		return state.level
	end

	local name = tostring(level):lower()
	local value = LEVELS[name]
	if not value then
		error("未知日志等级: " .. tostring(level) .. "（可用: debug/info/warn/error/fatal）", 2)
	end
	state.level = value
	return state.level
end

function log.getLevel()
	return state.level
end

function log.getLevelName()
	for name, value in pairs(LEVELS) do
		if value == state.level then
			return name
		end
	end
	return "info"
end

-- 字符串模板（%s 依次对应 时间/等级/函数名/内容），或 function(entry) -> string
function log.setFormat(format)
	if type(format) ~= "string" and type(format) ~= "function" then
		error("日志格式必须是字符串模板或函数", 2)
	end
	state.format = format
end

function log.getFormat()
	return state.format
end

-- 创建文件所在目录（love.filesystem 只允许写存档目录，子目录要显式建）
local function ensureDirectory(name)
	local dir = name:match("^(.*)/[^/]+$")
	if dir and love and love.filesystem and love.filesystem.createDirectory then
		pcall(love.filesystem.createDirectory, dir)
	end
end

-- 打开日志文件：优先 love.filesystem（Android 写入应用存档目录），否则退回 io
local function openFile()
	local f = state.file
	local name = os.date(f.pattern)
	f.name = name
	f.handle = nil
	f.viaLove = false
	f.absolute = name
	ensureDirectory(name)

	-- 优先写 LÖVE 存档目录（Android 上唯一稳定可写的位置）。
	-- LÖVE 12 把 newFile 改名为 openFile；LÖVE 11 只有 newFile。
	local filesystem = love and love.filesystem
	local openFileFn = filesystem and (filesystem.openFile or filesystem.newFile)
	if openFileFn then
		local ok, file = pcall(openFileFn, name, "a")
		if ok and file then
			f.handle = file
			f.viaLove = true
			local okDir, saveDir = pcall(love.filesystem.getSaveDirectory)
			f.absolute = okDir and saveDir and (saveDir .. "/" .. name) or name
			return true
		end
	end

	-- 存档目录只读、文件名被 PhysFS 拒绝或没有 LÖVE 时，退回普通 io。
	-- 在桌面开发环境里通常就是当前工作目录，至少不会“开了文件输出却什么都没写”。
	local okIO, handle = pcall(io.open, name, "a")
	if okIO and handle then
		f.handle = handle
		f.viaLove = false
		local okCwd, cwd = pcall(function()
			return love
				and love.filesystem
				and love.filesystem.getWorkingDirectory
				and love.filesystem.getWorkingDirectory()
		end)
		f.absolute = okCwd and cwd and (cwd .. "/" .. name) or name
		return true
	end

	f.enabled = false
	f.handle = nil
	-- 打开失败时直接提示（不能用 log 自身，避免递归）
	print("[At.log] 无法创建日志文件: " .. tostring(name) .. "（存档目录和当前目录都不可写）")
	return false
end

writeFile = function(text)
	local f = state.file
	if not f.enabled or not f.handle then
		return
	end

	local ok = pcall(function()
		f.handle:write(text .. "\n")
		f.handle:flush()
	end)

	if not ok then
		f.enabled = false
		pcall(function()
			f.handle:close()
		end)
		f.handle = nil
	end
end

function log.closeFile()
	local f = state.file
	if f.handle then
		pcall(function()
			f.handle:flush()
			f.handle:close()
		end)
	end
	f.handle = nil
	f.enabled = false
	return true
end

-- 开启/关闭文件输出；默认文件名按 pattern 用启动时间生成
function log.setFile(enabled)
	if enabled == nil then
		enabled = true
	end
	if enabled == false then
		log.closeFile()
		return false
	end
	state.file.enabled = true
	return openFile()
end

function log.isFileEnabled()
	return state.file.enabled
end

-- 文件名 pattern（os.date 格式）。例如 "%Y-%m-%d_%H-%M-%S.log" 可避开 Windows 的非法字符
function log.setFilePattern(pattern)
	state.file.pattern = tostring(pattern or "%Y-%m-%d_%H-%M-%S.log")
	if state.file.enabled then
		log.closeFile()
		state.file.enabled = true
		openFile()
	end
	return state.file.pattern
end

function log.getFilePattern()
	return state.file.pattern
end

-- 实际文件名（相对存档目录）与完整路径（用于展示）
function log.getFileName()
	return state.file.name
end

function log.getFilePath()
	return state.file.absolute
end

-- 是否同时输出到终端（Android 上就是 logcat）。
-- 传 true/false，或传 function(text, entry) 自定义输出目标
function log.setPrint(enabled)
	if enabled == nil then
		enabled = true
	end
	if type(enabled) == "function" then
		state.print = enabled
	else
		state.print = enabled and true or false
	end
	return state.print
end

function log.getPrint()
	return state.print
end

-- 缓冲区上限，0 表示不限（控制台只画可见行，但仍会占内存）
function log.setMaxEntries(maxEntries)
	state.maxEntries = math.max(0, math.floor(tonumber(maxEntries) or 0))
	return state.maxEntries
end

function log.getMaxEntries()
	return state.maxEntries
end

-- ---------- 读取 ----------

function log.getEntries()
	return state.entries
end

function log.count()
	return #state.entries
end

function log.clear()
	local entries = state.entries
	for i = #entries, 1, -1 do
		entries[i] = nil
	end
end

-- 把一条日志渲染成文本（显示端每帧调用，所以格式改了会影响已有日志的显示）
function log.formatEntry(entry)
	local format = state.format
	if type(format) == "function" then
		return tostring(format(entry))
	end
	return string.format(format, entry.time, entry.levelName, entry.func, entry.message)
end

return log
