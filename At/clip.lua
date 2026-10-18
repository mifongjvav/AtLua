-- 裁剪区工具：所有组件嵌套裁剪都应该"求交"而不是"直接覆盖"。
-- 直接覆盖会把外层的裁剪（例如 ScrollView 的视口）丢掉，导致文字/图形画到视口外。

local clip = {}

function clip.capture()
    local x, y, w, h = love.graphics.getScissor()
    if x == nil then
        return nil
    end
    return { x = x, y = y, w = w, h = h }
end

function clip.intersect(ax, ay, aw, ah, bx, by, bw, bh)
    local left = math.max(ax, bx)
    local top = math.max(ay, by)
    local right = math.min(ax + aw, bx + bw)
    local bottom = math.min(ay + ah, by + bh)
    if right <= left or bottom <= top then
        return nil
    end
    return left, top, right - left, bottom - top
end

-- 在当前裁剪基础上再叠加一块区域；返回旧裁剪和"是否还有可见区域"
function clip.apply(x, y, w, h)
    local old = clip.capture()

    -- 宽高为 0 表示不该画；负数会让 LÖVE 直接报错，这里统一拦掉
    if w <= 0 or h <= 0 then
        return old, false
    end

    local cx, cy, cw, ch = x, y, w, h

    if old then
        cx, cy, cw, ch = clip.intersect(old.x, old.y, old.w, old.h, x, y, w, h)
        if cx == nil then
            return old, false
        end
    end

    love.graphics.setScissor(cx, cy, cw, ch)
    return old, true
end

function clip.restore(old)
    if old then
        love.graphics.setScissor(old.x, old.y, old.w, old.h)
    else
        love.graphics.setScissor()
    end
end

-- 与当前裁剪求交后的矩形（不改状态），用于绘制前的可见性判断
function clip.resolve(x, y, w, h)
    local old = clip.capture()
    if not old then
        return x, y, w, h
    end
    return clip.intersect(old.x, old.y, old.w, old.h, x, y, w, h)
end

return clip
