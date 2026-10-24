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
--   local colors = At.system.getAccentColors()   -- 全部可用来源
--   At.system.getAccentColor(true, "gtk")        -- 只取 GTK / "qt"
--
-- 系统主题明暗由 LÖVE 12 的 love.window.getSystemTheme 提供；LÖVE 11 没有
-- 这个 API，本模块会返回 unsupported。主题色没有 LÖVE 原生 API，因此只在
-- 桌面平台通过固定命令/配置文件尽力读取：GNOME/GTK 的 accent-color、
-- qt6ct/qt5ct 调色板、KDE kdeglobals、Windows DWM、macOS AppleAccentColor。
-- 也可以用 AT_ACCENT_COLOR（或 AT_THEME_COLOR）显式覆盖，格式 "#RRGGBB"。
--
-- 外部命令只在第一次调用 getAccentColor 时执行，之后缓存；At.system.reset()
-- 可强制重新探测。Android/iOS 或没有 io.popen 的环境直接返回 nil。

local system = {}

local accentColors = {}
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

local function readIniValue(path, sectionName, key)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local wanted = sectionName:lower()
	local section
	for line in file:lines() do
		local nextSection = line:match("^%[([^%]]+)%]")
		if nextSection then
			section = nextSection:lower()
		end
		if section == wanted then
			local value = line:match("^%s*" .. key .. "%s*=%s*(.+)$")
			if value then
				file:close()
				return trim(value)
			end
		end
	end
	file:close()
	return nil
end

local function homePath()
	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	if not home then
		return nil
	end
	return home
end

-- qt6ct/qt5ct 的 active_colors 是 Qt 调色板；最后一项是 accent，
-- 没有 accent 的旧版本回退到第 13 项 highlight。
local function readQtScheme(path)
	local value = readIniValue(path, "ColorScheme", "active_colors")
	if not value then
		return nil
	end
	local colors = {}
	for part in value:gmatch("[^,]+") do
		colors[#colors + 1] = trim(part)
	end
	local accent = normalizeHex(colors[#colors])
	if accent then
		return accent
	end
	return normalizeHex(colors[13])
end

local function tryQt()
	local home = homePath()
	if not home then
		return nil
	end
	local configs = {
		{ path = home .. "/.config/qt6ct/qt6ct.conf", source = "Qt/qt6ct" },
		{ path = home .. "/.config/qt5ct/qt5ct.conf", source = "Qt/qt5ct" },
	}
	local theme = (os.getenv("QT_QPA_PLATFORMTHEME") or ""):lower()
	if theme:find("qt5ct", 1, true) then
		configs[1], configs[2] = configs[2], configs[1]
	end

	for _, config in ipairs(configs) do
		local scheme = readIniValue(config.path, "Appearance", "color_scheme_path")
		if scheme then
			scheme = scheme:gsub('^"(.*)"$', "%1")
			local color = readQtScheme(scheme)
			if color then
				return color, config.source
			end
		end
	end
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
	local queries = {
		{ "Colors:Selection", "BackgroundNormal" },
		{ "Colors:View", "Highlight" },
		{ "Colors:View", "DecorationFocus" },
		{ "Colors:Window", "DecorationFocus" },
	}
	for _, command in ipairs({ "kreadconfig6", "kreadconfig5" }) do
		for _, query in ipairs(queries) do
			local output =
				run(command .. " --file kdeglobals --group " .. query[1] .. " --key " .. query[2] .. " 2>/dev/null")
			local color = parseColor(output)
			if color then
				return color, "KDE/Qt"
			end
		end
	end
end

local function tryKdeFile()
	local home = homePath()
	if not home then
		return nil
	end
	local queries = {
		{ "Colors:Selection", "BackgroundNormal" },
		{ "Colors:View", "Highlight" },
		{ "Colors:View", "DecorationFocus" },
		{ "Colors:Window", "DecorationFocus" },
	}
	for _, path in ipairs({ home .. "/.config/kdeglobals", home .. "/.config/kdedefaults/kdeglobals" }) do
		for _, query in ipairs(queries) do
			local color = parseColor(readIniValue(path, query[1], query[2]))
			if color then
				return color, "KDE/Qt"
			end
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

-- 探测所有可用的系统主题色来源；第一次调用后缓存
local function detectAccentColors()
	local colors = {}
	local envColor = tryEnv()
	if envColor then
		colors.env = envColor
	end
	if not system.hasThemeApi() then
		return colors
	end

	local osName = currentOS()
	if osName == "Linux" or osName == "FreeBSD" then
		local gtk = tryGnome()
		local qt = tryQt()
		if not qt then
			qt = tryKdeCommand()
		end
		if not qt then
			qt = tryKdeFile()
		end
		colors.gtk = gtk
		colors.qt = qt
	elseif osName == "Windows" then
		colors.windows = tryWindows()
	elseif osName == "OS X" then
		colors.macos = tryMac()
	end
	return colors
end

-- 返回所有可用来源的副本：{ env=?, gtk=?, qt=?, windows=?, macos=? }
function system.getAccentColors(refresh)
	if refresh then
		accentChecked = false
	end
	if not accentChecked then
		accentChecked = true
		accentColors = detectAccentColors()
	end
	local copy = {}
	for key, value in pairs(accentColors) do
		copy[key] = value
	end
	return copy
end

local function sourceLabel(source)
	if source == "gtk" then
		return "GNOME/GTK"
	elseif source == "qt" then
		return "KDE/Qt"
	elseif source == "windows" then
		return "Windows"
	elseif source == "macos" then
		return "macOS"
	elseif source == "env" then
		return "env"
	end
	return tostring(source)
end

-- 返回主题色与来源。
--   getAccentColor(refresh?)            -- 自动：env > 当前桌面优先的 GTK/Qt > 其它
--   getAccentColor(refresh?, "gtk")     -- 只取 GTK
--   getAccentColor(refresh?, "qt")      -- 只取 Qt
-- 指定 gtk/qt 时忽略 env 覆盖；没有对应来源时返回 nil + 来源名。
function system.getAccentColor(refresh, source)
	local colors = system.getAccentColors(refresh)

	if source == "gtk" then
		if colors.gtk then
			return colors.gtk, sourceLabel("gtk")
		end
		return nil, "gtk"
	elseif source == "qt" then
		if colors.qt then
			return colors.qt, sourceLabel("qt")
		end
		return nil, "qt"
	elseif source == "windows" then
		if colors.windows then
			return colors.windows, sourceLabel("windows")
		end
		return nil, "windows"
	elseif source == "macos" then
		if colors.macos then
			return colors.macos, sourceLabel("macos")
		end
		return nil, "macos"
	elseif source == "env" then
		if colors.env then
			return colors.env, sourceLabel("env")
		end
		return nil, "env"
	end

	if colors.env then
		return colors.env, sourceLabel("env")
	end

	local osName = currentOS()
	if osName == "Linux" or osName == "FreeBSD" then
		local desktop = (os.getenv("XDG_CURRENT_DESKTOP") or os.getenv("DESKTOP_SESSION") or ""):lower()
		local kdeFirst = desktop:find("kde", 1, true) or desktop:find("plasma", 1, true)
		local order = kdeFirst and { "qt", "gtk" } or { "gtk", "qt" }
		for _, key in ipairs(order) do
			if colors[key] then
				return colors[key], sourceLabel(key)
			end
		end
	elseif osName == "Windows" then
		if colors.windows then
			return colors.windows, sourceLabel("windows")
		end
	elseif osName == "OS X" then
		if colors.macos then
			return colors.macos, sourceLabel("macos")
		end
	end

	if not system.hasThemeApi() then
		return nil, "unsupported"
	end
	return nil, "unavailable"
end
-- 清空主题色缓存；环境/系统主题色切换后调用
function system.reset()
	accentChecked = false
	accentColors = {}
	return system
end

return system
