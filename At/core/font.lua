local font = {}

local config = require("At.config")

local CONFIG = config.font or {}

-- 按字号缓存。
-- 主字体作为当前字体，emoji 字体只作 fallback：
-- Noto Emoji 里的数字/空格是为 keycap 设计的长宽字，若把 emoji 当主字体，
-- 数字和空格会比中文还宽。反过来用主字体优先、emoji 兜底才是正常的排版。
local cache = {}

local function build(size)
	local mainPath = CONFIG.main or "/At/assets/font.ttf"
	local emojiPath = CONFIG.emoji or "/At/assets/emoji.ttf"
	local main = love.graphics.newFont(mainPath, size)
	local emojiFont = love.graphics.newFont(emojiPath, size)
	main:setFallbacks(emojiFont)
	return { main = main, emoji = emojiFont }
end

local function entry(size)
	size = size or CONFIG.size or 12
	local cached = cache[size]
	if not cached then
		cached = build(size)
		cache[size] = cached
	end
	return cached
end

-- 取指定字号的字体（带缓存），不改变当前绘制字体
function font.get(size)
	return entry(size).main
end

-- 初始化默认字体：设置全局 mainFont / emoji，并把主字体应用为当前字体
function font.init(size)
	local cached = entry(size)
	mainFont = cached.main
	emoji = cached.emoji
	love.graphics.setFont(cached.main)
end

return font
