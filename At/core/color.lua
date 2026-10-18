color = {}

function color.hexToRGBA(hex, alpha)
    hex = hex:gsub("#", "")
    local r = tonumber("0x" .. hex:sub(1,2)) / 255  -- 转为 0-1
    local g = tonumber("0x" .. hex:sub(3,4)) / 255
    local b = tonumber("0x" .. hex:sub(5,6)) / 255
    local a = (alpha or 255) / 255                  -- 透明度也转
    return r, g, b, a
end

function color.setColor(hex, alpha)
    local r, g, b, a = color.hexToRGBA(hex, alpha)
    love.graphics.setColor(r, g, b, a)
end

-- 按比例调亮 / 调暗同一种颜色：factor = 0.1 亮 10%，-0.12 暗 12%
-- 用于按钮的悬停 / 按下态，省得为每个颜色手写三份
function color.shade(hex, factor)
    local r, g, b = color.hexToRGBA(hex)
    local f = 1 + (factor or 0)

    local function toByte(value)
        value = value * f
        if value < 0 then
            value = 0
        elseif value > 1 then
            value = 1
        end
        return math.floor(value * 255 + 0.5)
    end

    return string.format("#%02X%02X%02X", toByte(r), toByte(g), toByte(b))
end

-- 在两个颜色之间插值：t = 0 → hexA，t = 1 → hexB
function color.mix(hexA, hexB, t)
    t = t or 0
    if t <= 0 then
        return hexA
    end
    if t >= 1 then
        return hexB
    end

    local ar, ag, ab = color.hexToRGBA(hexA)
    local br, bg, bb = color.hexToRGBA(hexB)

    local function toByte(a, b)
        local value = a + (b - a) * t
        if value < 0 then
            value = 0
        elseif value > 1 then
            value = 1
        end
        return math.floor(value * 255 + 0.5)
    end

    return string.format("#%02X%02X%02X", toByte(ar, br), toByte(ag, bg), toByte(ab, bb))
end

return color