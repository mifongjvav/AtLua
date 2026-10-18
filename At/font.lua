local font = {}

local MAIN_PATH = "/At/font/font.ttf"
local EMOJI_PATH = "/At/font/emoji.ttf"

-- 按字号缓存：emoji 作为当前字体，主字体作为回退（覆盖中文与常见 emoji）
local cache = {}

local function build(size)
    local main = love.graphics.newFont(MAIN_PATH, size)
    local emojiFont = love.graphics.newFont(EMOJI_PATH, size)
    emojiFont:setFallbacks(main)
    return { main = main, emoji = emojiFont }
end

local function entry(size)
    size = size or 12
    local cached = cache[size]
    if not cached then
        cached = build(size)
        cache[size] = cached
    end
    return cached
end

-- 取指定字号的字体（带缓存），不改变当前绘制字体
function font.get(size)
    return entry(size).emoji
end

-- 初始化默认字体：保留旧行为，设置全局 mainFont / emoji 并应用为当前字体
function font.init(size)
    local cached = entry(size)
    mainFont = cached.main
    emoji = cached.emoji
    love.graphics.setFont(cached.emoji)
end

return font
