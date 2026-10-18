local input = {}

local active = false
local text = ""

-- 按 UTF-8 码点切分（中文/emoji 都算一个字符）
local function splitChars(str)
    local chars = {}
    for char in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars[#chars + 1] = char
    end
    return chars
end

-- 显式设置激活态，组件式调用更直观
function input.setActive(value)
    value = value and true or false
    if value == active then
        return active
    end
    active = value
    if active then
        text = ""
        love.keyboard.setTextInput(true)
    else
        love.keyboard.setTextInput(false)
    end
    return active
end

-- 切换激活态（旧 API 保留）
function input.input()
    return input.setActive(not active)
end

function input.get()
    return text
end

function input.set(value)
    text = value and tostring(value) or ""
end

function input.clear()
    text = ""
end

function input.join(t)
    if active then
        text = text .. t
    end
end

function input.keypressed(key)
    if not active then
        return
    end
    if key == "backspace" then
        text = input.removeLast(text)
    elseif key == "return" or key == "kpenter" then
        input.input()
    end
end

function input.isActive()
    return active
end

-- 字符数（不是字节数）
function input.length(str)
    return #splitChars(str or "")
end

-- 删掉最后一个 UTF-8 字符
function input.removeLast(str)
    if not str or #str == 0 then
        return str or ""
    end

    local chars = splitChars(str)
    if #chars > 0 then
        table.remove(chars)
    end
    return table.concat(chars)
end

-- 旧全局名保留兼容
removeLastUTF8Char = input.removeLast

return input
