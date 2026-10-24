-- 系统主题探测（LÖVE 12+，仅桌面平台；全部是 best-effort）。
--
--   local mode, reason = At.system.getThemeMode()
--     -- mode: "light" | "dark" | nil
--     -- reason: "system" | "unsupported" | "unknown" | "error"
--
--   local accent, source = At.system.getAccentColor()
--     -- accent: "#RRGGBB" | nil
--     -- source: "env" | "GNOME/GTK" | "KDE/Qt" | "Windows" | "macOS" | nil
--
-- 系统主题明暗由 LÖVE 12 的 love.window.getSystemTheme 提供；LÖVE 11 没有
-- 这个 API，本模块会返回 unsupported。主题色没有 LÖVE 原生 API，因此只在
-- 桌面平台通过固定命令/配置文件尽力读取：GNOME/GTK 的 accent-color、
-- KDE/Qt 的 kdeglobals Highlight、Windows DWM、macOS AppleAccentColor。
-- 也可以用 AT_ACCENT_COLOR（或 AT_THEME_COLOR）显式覆盖，格式 "#RRGGBB"。
--
-- 外部命令只在第一次调用 getAccentColor 时执行，之后缓存；At.system.reset()
-- 可强制重新探测。Android/iOS 或没有 io.popen 的环境直接返回 nil。

local system = {}

local accentColor
local accentSource
local accentChecked = false

local GNOME_ACCENTS = {
	blue = "#3584E4",
	teal = "#2190A4",
	green = "#3A944A",
	yellow = "#C88800",
	orange = "#ED5B00",
	red = "#E62D42",
	pink = "#D56199",
	purple = "#9141AC",
	slate = "#6F8396",
	brown = "#986A44",
}

local MAC_ACCENTS = {
	[-1] = "#8E8E93", -- graphite
	[0] = "#FF5257", -- red
	[1] = "#FF9F0A", -- orange
	[2] = "#FFD60A", -- yellow
	[3] = "#30D158", -- green
	[4] = "#0A84FF", -- blue
	[5] = "#BF5AF2", -- purple
	[6] = "#FF375F", -- pink
}

local function trim(value)
	return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeHex(value)
	if type(value) ~= "string" then
		return nil
	end
	local hex = value:gsub("#", ""):gsub("%s", "")
	if hex:match("^%x%x%x%x%x%x$") then
		return "#" .. hex:upper()
	end
	return nil
end

local function rgbHex(r, g, b)
	r, g, b = tonumber(r), tonumber(g), tonumber(b)
	if not r or not g or not b or r < 0 or g < 0 or b < 0 or r > 255 or g > 255 or b > 255 then
		return nil
	end
	return string.format("#%02X%02X%02X", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

local function parseColor(value)
	local trimmed = trim(value)
	local hex = normalizeHex(trimmed)
	if hex then
		return hex
	end
	local r, g, b = trimmed:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
	return rgbHex(r, g, b)
end

local function run(command)
	if not io or not io.popen then
		return nil
	end
	local ok, pipe = pcall(io.popen, command)
	if not ok or not pipe then
		return nil
	end
	local okRead, output = pcall(pipe.read, pipe, "*a")
	pcall(pipe.close, pipe)
	if not okRead then
		return nil
	end
	return output
end

local function currentOS()
	if love and love.system and love.system.getOS then
		local ok, osName = pcall(love.system.getOS)
		if ok then
			return osName
		end
	end
	return nil
end

local function tryEnv()
	local color = normalizeHex(os.getenv("AT_ACCENT_COLOR") or os.getenv("AT_THEME_COLOR"))
	if color then
		return color, "env"
	end
end

local function tryGnome()
	local output = run("gsettings get org.gnome.desktop.interface accent-color 2>/dev/null")
	if not output then
		return nil
	end
	local name = output:lower():match("'([%w%-]+)'") or output:lower():match("^%s*([%w%-]+)")
	if not name then
		return nil
	end
	local color = GNOME_ACCENTS[name]
	if color then
		return color, "GNOME/GTK"
	end
end

local function tryKdeCommand()
	for _, command in ipairs({ "kreadconfig6", "kreadconfig5" }) do
		local output = run(command .. " --file kdeglobals --group Colors:View --key Highlight 2>/dev/null")
		local color = parseColor(output)
		if color then
			return color, "KDE/Qt"
		end
	end
end

local function tryKdeFile()
	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	if not home then
		return nil
	end
	for _, path in ipairs({ home .. "/.config/kdeglobals", home .. "/.config/kdedefaults/kdeglobals" }) do
		local file = io.open(path, "r")
		if file then
			local section
			for line in file:lines() do
				local nextSection = line:match("^%[([^%]]+)%]")
				if nextSection then
					section = nextSection:lower()
				end
				if section == "colors:view" then
					local value = line:match("^Highlight=(.+)$")
					local color = parseColor(value)
					if color then
						file:close()
						return color, "KDE/Qt"
					end
				end
			end
			file:close()
		end
	end
end

local function tryWindows()
	local output = run('reg query "HKCU\\Software\\Microsoft\\Windows\\DWM" /v ColorizationColor')
	if not output then
		return nil
	end
	local raw = output:match("0x(%x+)")
	local number = raw and tonumber(raw, 16)
	if not number then
		return nil
	end
	local r = math.floor(number / 65536) % 256
	local g = math.floor(number / 256) % 256
	local b = number % 256
	return rgbHex(r, g, b), "Windows"
end

local function tryMac()
	local output = run("defaults read -g AppleAccentColor 2>/dev/null")
	local number = tonumber(trim(output))
	if number and MAC_ACCENTS[number] then
		return MAC_ACCENTS[number], "macOS"
	end
	local r, g, b = trim(output):match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
	if r then
		return rgbHex(tonumber(r) * 255, tonumber(g) * 255, tonumber(b) * 255), "macOS"
	end
end

-- LÖVE 12+ 才有 love.window.getSystemTheme；LÖVE 11 返回 false
function system.hasThemeApi()
	return love ~= nil and love.window ~= nil and type(love.window.getSystemTheme) == "function"
end

-- 返回 "light" / "dark"，或 nil + 原因（unsupported / unknown / error）
function system.getThemeMode()
	if not system.hasThemeApi() then
		return nil, "unsupported"
	end
	local ok, mode = pcall(love.window.getSystemTheme)
	if not ok then
		return nil, "error"
	end
	mode = tostring(mode or ""):lower()
	if mode == "light" or mode == "dark" then
		return mode, "system"
	end
	return nil, "unknown"
end

-- 返回系统主题色与来源；第一次调用会探测并缓存
function system.getAccentColor(refresh)
	if refresh then
		accentChecked = false
	end
	if accentChecked then
		return accentColor, accentSource
	end
	accentChecked = true
	accentColor, accentSource = nil, nil

	local envColor, envSource = tryEnv()
	if envColor then
		accentColor, accentSource = envColor, envSource
		return accentColor, accentSource
	end

	if not system.hasThemeApi() then
		accentSource = "unsupported"
		return nil, accentSource
	end

	local osName = currentOS()
	local color, source
	if osName == "Linux" or osName == "FreeBSD" then
		local desktop = (os.getenv("XDG_CURRENT_DESKTOP") or os.getenv("DESKTOP_SESSION") or ""):lower()
		if desktop:find("kde", 1, true) or desktop:find("plasma", 1, true) then
			color, source = tryKdeCommand()
			if not color then
				color, source = tryKdeFile()
			end
			if not color then
				color, source = tryGnome()
			end
		else
			color, source = tryGnome()
			if not color then
				color, source = tryKdeCommand()
			end
			if not color then
				color, source = tryKdeFile()
			end
		end
	elseif osName == "Windows" then
		color, source = tryWindows()
	elseif osName == "OS X" then
		color, source = tryMac()
	end

	accentColor, accentSource = color, source or "unavailable"
	return accentColor, accentSource
end

-- 清空主题色缓存；环境/系统主题色切换后调用
function system.reset()
	accentChecked = false
	accentColor = nil
	accentSource = nil
	return system
end

return system
