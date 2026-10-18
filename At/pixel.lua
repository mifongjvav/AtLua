-- 像素对齐：文字、1px 边框、圆角矩形在整数坐标上才清晰。
-- 布局会把位置算成小数（百分比/居中），绘制前统一对齐到像素。

local pixel = {}

function pixel.round(value)
    if value == nil then
        return 0
    end
    return math.floor(value + 0.5)
end

-- 只对齐位置（宽高通常由布局给出，保持原值以免相邻元素出现 1px 缝）
function pixel.xy(x, y)
    return pixel.round(x), pixel.round(y)
end

return pixel
