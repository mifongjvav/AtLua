-- 主题色系统：用三个基色（主题色 / 黑 / 白）派生整套语义色。
--
--   At.theme.set{ color = "7FE0C4" }          -- 运行时换主题色，已有组件立即生效
--   At.theme.get("@surface")                  -- 取派生色（带 @ 的 token）
--   At.theme.foreground("@surface")           -- 按底色挑可读的前景色
--   At.Label{ color = "@textMuted" }           -- 组件颜色也可以直接写 token
--
-- 组件默认颜色使用 token（如 "@primary"），在绘制时由 At.color 解析，
-- 所以改主题不需要重建组件；显式传具体 hex 的组件保持自己的颜色。
--
-- 派生规则（b = 黑、w = 白、p = 主题色）：
--   background = b                 text        = w
--   surface    = mix(b, w, 0.06)   textMuted   = mix(w, b, 0.38)
--   surfaceAlt = mix(b, w, 0.12)   textFaint   = mix(w, b, 0.56)
--   border     = mix(b, w, 0.22)   track       = mix(b, w, 0.17)
--   onPrimary  = b / w 中与主题色对比度更高的一个
--   knob       = w
--
-- 想换成浅色主题，把 black/white 两个槽位对调即可（black = "FFFFFF"、
-- white = "3D3D3D"），派生色会一起翻转。

local color = require("At.core.color")

local theme = {}

-- 三个基色的出厂值；用户配置在 At/config.lua 的 theme 段
local DEFAULTS = {
	color = "#A7DCFF", -- 主题色（主色 / 强调色）
	black = "#3D3D3D", -- 深色槽位（默认背景）
	white = "#FFFFFF", -- 浅色槽位（默认文字 / 旋钮）
}

-- 语义色不参与三基色派生，但同样可以用 token 引用
local SEMANTIC = {
	danger = "#E87979",
	warning = "#E8C07F",
	success = "#7FA88F",
}

local function normalize(hex, name)
	if type(hex) ~= "string" then
		error(string.format("At.theme: %s 必须是十六进制颜色字符串，收到 %s", name, tostring(hex)), 3)
	end

	local value = hex:gsub("#", "")
	if not value:match("^%x%x%x%x%x%x$") then
		error(string.format("At.theme: %s 必须是 6 位十六进制颜色，收到 %q", name, hex), 3)
	end
	return "#" .. value:upper()
end

-- 粗略感知亮度，用来给主题色挑对比度更高的前景色
local function luminance(hex)
	local r, g, b = color.hexToRGBA(hex)
	return 0.299 * r + 0.587 * g + 0.114 * b
end

-- 重新计算派生 token；三基色变化后调用
function theme._rebuild()
	local c = theme.color
	local b = theme.black
	local w = theme.white
	local primaryLum = luminance(c)
	local onPrimary = b
	if math.abs(primaryLum - luminance(w)) > math.abs(primaryLum - luminance(b)) then
		onPrimary = w
	end

	theme.tokens = {
		-- 基色
		primary = c,
		primaryDark = color.shade(c, -0.82), -- 深色主题色（阴影等）
		theme = c, -- @primary 的别名
		accent = c, -- @primary 的别名
		black = b,
		white = w,

		-- 背景与表面
		background = b,
		surface = color.mix(b, w, 0.06),
		surfaceAlt = color.mix(b, w, 0.12),
		surfaceStrong = color.mix(b, w, 0.20),

		-- 文字
		text = w,
		textMuted = color.mix(w, b, 0.38),
		textFaint = color.mix(w, b, 0.56),
		onPrimary = onPrimary,

		-- 描边与轨道
		border = color.mix(b, w, 0.22),
		borderStrong = color.mix(b, w, 0.34),
		divider = color.mix(b, w, 0.14),
		track = color.mix(b, w, 0.17),
		knob = w,

		-- 语义色
		danger = SEMANTIC.danger,
		warning = SEMANTIC.warning,
		success = SEMANTIC.success,
	}

	theme.primary = c
end

-- 主题 token 必须以 @ 开头，避免和普通 hex 字符串混淆
function theme.isToken(value)
	return type(value) == "string" and value:sub(1, 1) == "@"
end

-- 取 token 对应的具体 hex；name 可带或不带 @
function theme.get(name)
	if type(name) ~= "string" then
		error("At.theme.get: 需要一个主题 token 名称", 2)
	end

	local key = name:gsub("^@", "")
	if key == "color" then
		return theme.color
	end

	local value = theme.tokens[key]
	if not value then
		error(string.format("At.theme: 未知主题色 token %q", name), 2)
	end
	return value
end

-- 把 token 解析成 hex；普通 hex 原样返回（At.color 内部也调用它）
function theme.resolve(value)
	if not theme.isToken(value) then
		return value
	end
	return theme.get(value)
end

-- 给任意底色挑一个可读的前景基色（返回 black / white 槽位中对比度更高的）
function theme.foreground(background)
	local bgLum = luminance(theme.resolve(background))
	local blackLum = luminance(theme.black)
	local whiteLum = luminance(theme.white)
	if math.abs(bgLum - blackLum) >= math.abs(bgLum - whiteLum) then
		return theme.black
	end
	return theme.white
end

-- 运行时修改基色；支持 { color = ..., black = ..., white = ... }，
-- color 也可写成 primary。改动立即影响所有使用 token 的组件。
function theme.set(opts)
	opts = opts or {}

	local nextColor = opts.color
	if nextColor == nil then
		nextColor = opts.primary
	end
	local nextBlack = opts.black
	local nextWhite = opts.white

	-- 先全部校验，避免改了一半才发现非法值，留下不一致的三基色
	if nextColor ~= nil then
		nextColor = normalize(nextColor, "color")
	end
	if nextBlack ~= nil then
		nextBlack = normalize(nextBlack, "black")
	end
	if nextWhite ~= nil then
		nextWhite = normalize(nextWhite, "white")
	end

	theme.color = nextColor or theme.color
	theme.black = nextBlack or theme.black
	theme.white = nextWhite or theme.white

	theme:_rebuild()
	return theme
end

-- 回到出厂的三基色
function theme.reset()
	theme.color = DEFAULTS.color
	theme.black = DEFAULTS.black
	theme.white = DEFAULTS.white
	theme:_rebuild()
	return theme
end

-- 出厂值（只读副本，改它不会影响主题）
function theme.defaults()
	local copy = {}
	for key, value in pairs(DEFAULTS) do
		copy[key] = value
	end
	return copy
end

theme.color = DEFAULTS.color
theme.black = DEFAULTS.black
theme.white = DEFAULTS.white
theme:_rebuild()

return theme
