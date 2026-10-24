-- 系统通知：Linux 下通过 notify-send 发送，best-effort。
--
--   local ok, reason = At.notify.available()
--   if ok then
--       At.notify.send{
--           title = "At",
--           body = "保存成功",
--           level = "success",       -- info / success / warning / error / critical
--           urgency = "normal",      -- 可覆盖：low / normal / critical
--           timeout = 5,             -- 秒；不传则用桌面默认
--       }
--   end
--
-- 需要桌面通知守护进程（GNOME/KDE/Xfce 等）。headless 环境或没有
-- notify-send 时 available() 返回 false，不报错、不阻塞启动。

local notify = {}

local DEFAULT_TITLE = "At"
local currentOS = function()
	if love and love.system and love.system.getOS then
		return love.system.getOS()
	end
	return "Unknown"
end

local LEVELS = {
	info = { urgency = "normal", icon = "dialog-information" },
	success = { urgency = "normal", icon = "emblem-default" },
	warning = { urgency = "normal", icon = "dialog-warning" },
	error = { urgency = "critical", icon = "dialog-error" },
	critical = { urgency = "critical", icon = "dialog-error" },
}

local checked = false
local available = false
local availabilityReason = nil

local function shellQuote(value)
	value = tostring(value or "")
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function detect()
	if checked then
		return available, availabilityReason
	end
	checked = true

	if currentOS() ~= "Linux" then
		availabilityReason = "unsupported"
		return false, availabilityReason
	end
	if not io or not io.popen then
		availabilityReason = "no io.popen"
		return false, availabilityReason
	end

	local ok, handle = pcall(io.popen, "command -v notify-send 2>/dev/null")
	if not ok or not handle then
		availabilityReason = "notify-send missing"
		return false, availabilityReason
	end
	local path = handle:read("*a") or ""
	handle:close()
	if path:match("%S") then
		available = true
		availabilityReason = "notify-send"
		return true, availabilityReason
	end
	availabilityReason = "notify-send missing"
	return false, availabilityReason
end

local function levelData(level)
	return LEVELS[(tostring(level or "info"):lower())] or LEVELS.info
end

-- 返回是否可用与来源/原因；首次调用会探测 command -v notify-send
function notify.available()
	return detect()
end

-- 返回某个 level 对应的 urgency 与 icon（方便调用方展示/复用）
function notify.level(level)
	local data = levelData(level)
	return data.urgency, data.icon
end

-- 清空可用性缓存；切换桌面/安装 notify-send 后调用
function notify.reset()
	checked = false
	available = false
	availabilityReason = nil
	return notify
end

-- opts:
--   title, body/message, level, urgency, icon, timeout（秒）,
--   appName, category, transient（布尔）
function notify.send(opts)
	opts = opts or {}
	local ok, reason = notify.available()
	if not ok then
		return false, reason
	end

	local level = levelData(opts.level)
	local urgency = tostring(opts.urgency or level.urgency):lower()
	if urgency ~= "low" and urgency ~= "normal" and urgency ~= "critical" then
		urgency = level.urgency
	end

	local parts = {
		"notify-send",
		"--app-name",
		shellQuote(opts.appName or "AtLua"),
		"--urgency",
		shellQuote(urgency),
		"--icon",
		shellQuote(opts.icon or level.icon),
	}

	local timeout = tonumber(opts.timeout)
	if timeout then
		local ms = math.max(0, math.floor(timeout * 1000))
		parts[#parts + 1] = "--expire-time"
		parts[#parts + 1] = tostring(ms)
	end
	if opts.category then
		parts[#parts + 1] = "--category"
		parts[#parts + 1] = shellQuote(opts.category)
	end
	if opts.transient then
		parts[#parts + 1] = "--hint"
		parts[#parts + 1] = "int:transient:1"
	end

	parts[#parts + 1] = shellQuote(opts.title or DEFAULT_TITLE)
	parts[#parts + 1] = shellQuote(opts.body or opts.message or "")

	local execOk, result = pcall(os.execute, table.concat(parts, " "))
	if not execOk then
		return false, "execute failed"
	end
	-- Lua 5.1 / LuaJIT 返回退出码；Lua 5.2+ 返回 true/nil, "exit", code
	if result == true or result == 0 then
		return true, "notify-send"
	end
	return false, "notify-send failed"
end

return notify
