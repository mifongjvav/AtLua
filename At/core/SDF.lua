SDF = {}

function SDF.roundRectSDF(px, py, rect)
    -- 从表中提取参数
    local x, y, w, h, radius = rect.x, rect.y, rect.w, rect.h, rect.radius
    
    -- 把点转换到矩形的局部坐标系（中心为原点）
    local cx = px - (x + w/2)
    local cy = py - (y + h/2)
    local halfW = w/2 - radius
    local halfH = h/2 - radius
    
    -- SDF 计算
    local d = {x = math.abs(cx) - halfW, y = math.abs(cy) - halfH}
    local dist = math.sqrt(math.max(d.x, 0)^2 + math.max(d.y, 0)^2) 
                + math.min(math.max(d.x, d.y), 0) - radius
    
    return dist  -- 负数 = 内部，正数 = 外部
end

-- 判断是否点击到
function SDF.isClick(rect)
    local mx, my = love.mouse.getPosition()
    return SDF.roundRectSDF(mx, my, rect) <= 0
end

return SDF