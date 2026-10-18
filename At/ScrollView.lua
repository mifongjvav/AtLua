-- 可滚动视口：内容比视口高（或宽）时用滚轮 / 拖动 / 拖滚动条查看，自带裁剪与滚动条。
-- 内容一般是 At.Panel；ScrollView 会把自己视口的宽度作为可用宽度传给内容，
-- 所以内容里的 "100%" / "50%" 会跟着视口走。
--
--   local view = At.ScrollView{
--       x = 40, y = 40, w = 420, h = love.graphics.getHeight() - 80,
--       content = card,
--   }
--   view:draw()
--   -- love.wheelmoved(dx, dy) -> At.wheelmoved(dx, dy)
--
-- 注意：请保证 ScrollView 在内容之后创建（事件按创建顺序倒序派发），
-- 这样它才能先判断"这次点击该不该交给子组件"。

local Component = require("At.component")
local color = require("At.color")
local layout = require("At.layout")
local clip = require("At.clip")
local pixel = require("At.pixel")

local ScrollView = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
    w = 320,
    h = 240,
    radius = 0,
    padding = 0,
    background = nil,
    content = nil,
    scrollX = 0,
    scrollY = 0,
    scrollbar = true,
    scrollbarWidth = 4,
    scrollbarActiveWidth = 8,   -- 指针碰到滚动条/拖动时的宽度
    scrollbarGrowSpeed = 16,
    scrollbarColor = "#3A4150",
    scrollbarThumbColor = "#9FB3D3",
    scrollbarHitWidth = 16,   -- 滚动条的可拖拽宽度（比视觉宽度大，方便手指）
    wheelStep = 44,
    drag = true,              -- 允许按住空白处拖动滚动（触屏也走鼠标事件）
    smooth = true,            -- 滚轮/代码滚动是否缓动（拖拽始终 1:1 跟手）
    smoothSpeed = 14,         -- 缓动收敛速度，越大越跟手
    momentum = true,          -- 松手后是否保留惯性
    momentumFriction = 6,     -- 惯性衰减速度
    momentumMin = 1,          -- 小于这个速度（像素/帧）不产生惯性
    alpha = 255,
    onScroll = nil,
}

function ScrollView.new(opts)
    local self = Component.instantiate(proto, opts, DEFAULTS)
    self.scrollX = math.max(0, tonumber(self.scrollX) or 0)
    self.scrollY = math.max(0, tonumber(self.scrollY) or 0)
    self._maxScroll = 0
    self._barW = self.scrollbarWidth or 4
    self._scrollTarget = self.scrollY
    self._scrollVelocity = 0
    self._dragVelocity = 0
    return self
end

-- ---------- 尺寸与滚动量 ----------

function proto:_innerBox()
    self:_ensureSize()
    local pl, pt, pr, pb = layout.sides(self.padding)
    return self.w - pl - pr, self.h - pt - pb
end

function proto:maxScroll()
    return self._maxScroll or 0
end

function proto:_clampScroll(value)
    value = tonumber(value) or 0
    local maxScroll = self._maxScroll or 0
    if value < 0 then
        return 0
    elseif value > maxScroll then
        return maxScroll
    end
    return value
end

-- 直接改当前位置（拖拽、滚动条、scrollToVisible 用这个，保证 1:1 跟手）
function proto:_applyScroll(value, silent)
    value = self:_clampScroll(value)
    if value == self.scrollY then
        return self.scrollY
    end

    self.scrollY = value
    if not silent and self.onScroll then
        self.onScroll(value, self._maxScroll, self)
    end
    return self.scrollY
end

function proto:setScroll(value, silent)
    local clamped = self:_clampScroll(value)
    self._scrollTarget = clamped
    self._scrollVelocity = 0
    self._dragVelocity = 0
    return self:_applyScroll(clamped, silent)
end

-- 平滑滚动：只改目标，位置在 _tickScroll 里缓动逼近
function proto:scrollTo(value, silent)
    local clamped = self:_clampScroll(value)

    if not self.smooth then
        return self:setScroll(clamped, silent)
    end

    self._scrollVelocity = 0
    self._scrollTarget = clamped

    if math.abs(clamped - self.scrollY) < 0.5 then
        return self:_applyScroll(clamped, silent)
    end
    return self.scrollY
end

-- 相对滚动按"目标位置"累加，滚轮连发时不会互相吞掉
function proto:scrollBy(delta, silent)
    local base = self._scrollTarget or self.scrollY
    return self:scrollTo(base + delta, silent)
end

-- 把某个子组件滚动到可见范围内（配合输入框聚焦，避免被软键盘挡住）
function proto:scrollToVisible(component, margin)
    if not component then
        return self.scrollY
    end
    margin = margin or 16
    local _, pt = layout.sides(self.padding)
    local viewH = self.h - pt
    local top = component.y - (self.y + pt)
    local bottom = top + (component.h or 0)

    if top - margin < self.scrollY then
        return self:setScroll(top - margin)
    end
    if bottom + margin > self.scrollY + viewH then
        return self:setScroll(bottom + margin - viewH)
    end
    return self.scrollY
end

-- ---------- 排版 ----------

function proto:layout()
    local content = self.content
    if not content then
        return
    end

    local innerW, innerH = self:_innerBox()
    local _, pt = layout.sides(self.padding)

    content._availW = innerW
    content._availH = nil

    local _, contentH = content:measure(innerW, nil)
    self._maxScroll = math.max(0, pixel.round((contentH or 0) - innerH))

    self._scrollTarget = self:_clampScroll(self._scrollTarget or self.scrollY)
    self:_applyScroll(self.scrollY, true)

    -- 内容整体位移也对齐到像素：拖动滚动时文字才不会发虚/抖动
    content.x = pixel.round(self.x - self.scrollX)
    content.y = pixel.round(self.y + pt - self.scrollY)
end

-- ---------- 滚动条 ----------

function proto:_barMetrics()
    local barW = self._barW or self.scrollbarWidth or 4
    local pad = 2
    local trackX = self.x + self.w - barW - pad
    local trackY = self.y + pad
    local trackH = self.h - pad * 2

    local _, pt, _, pb = layout.sides(self.padding)
    local viewH = self.h - pt - pb
    local maxScroll = self._maxScroll or 0

    local thumbH = trackH
    if maxScroll > 0 and viewH > 0 then
        thumbH = math.max(24, trackH * (viewH / (viewH + maxScroll)))
    end
    if thumbH > trackH then
        thumbH = trackH
    end

    local t = maxScroll > 0 and (self.scrollY / maxScroll) or 0
    local thumbY = trackY + (trackH - thumbH) * t

    return trackX, trackY, barW, trackH, thumbY, thumbH
end

function proto:_barHit(mx, my)
    if not self.scrollbar or (self._maxScroll or 0) <= 0 then
        return false
    end
    local trackX, trackY, _, trackH = self:_barMetrics()
    local barW = self._barW or self.scrollbarWidth or 4
    local hitW = math.max(self.scrollbarHitWidth or 16, barW)
    local left = trackX - (hitW - barW) / 2
    return mx >= left and mx <= left + hitW and my >= trackY and my <= trackY + trackH
end

function proto:_barDragTo(my)
    local _, trackY, _, trackH, _, thumbH = self:_barMetrics()
    local travel = trackH - thumbH
    if travel <= 0 then
        return
    end

    local grab = self._barGrab or thumbH / 2
    local thumbTop = my - grab
    local t = (thumbTop - trackY) / travel
    if t < 0 then
        t = 0
    elseif t > 1 then
        t = 1
    end

    self:setScroll(t * (self._maxScroll or 0))
end

function proto:_drawScrollbar()
    local trackX, trackY, barW, trackH, thumbY, thumbH = self:_barMetrics()
    local radius = barW / 2

    color.setColor(self.scrollbarColor, self.alpha)
    love.graphics.rectangle("fill", trackX, trackY, barW, trackH, radius)

    color.setColor(self.scrollbarThumbColor, self.alpha)
    love.graphics.rectangle("fill", trackX, thumbY, barW, thumbH, radius)
end

-- ---------- 绘制 ----------

function proto:draw()
    if self._destroyed or not self.visible then
        return
    end

    self:_ensureSize()

    local prevR, prevG, prevB, prevA = love.graphics.getColor()
    local prevFont = love.graphics.getFont()
    local prevLineWidth = love.graphics.getLineWidth()

    self:layout()

    if self.background then
        color.setColor(self.background, self.alpha)
        love.graphics.rectangle(
            "fill", pixel.round(self.x), pixel.round(self.y), self.w, self.h, self.radius or 0
        )
    end

    -- 与外层裁剪求交：裁掉视口外的内容，同时不丢掉外层裁剪（支持嵌套滚动）
    local old, visible = clip.apply(pixel.round(self.x), pixel.round(self.y), self.w, self.h)
    if visible then
        if self.content then
            self.content:draw()
        end
        if self.scrollbar and (self._maxScroll or 0) > 0 then
            self:_drawScrollbar()
        end
    end
    clip.restore(old)

    love.graphics.setLineWidth(prevLineWidth)
    love.graphics.setFont(prevFont)
    love.graphics.setColor(prevR, prevG, prevB, prevA)
end

-- ---------- 命中与事件 ----------

-- 指针是否落在内容里的"可交互叶子组件"上。
-- 容器（Panel/ScrollView）本身铺满视口，不能算命中，否则空白处永远拖不动。
local function hitsChildren(node, mx, my)
    local children = node.children
    if not children then
        return false
    end
    for i = 1, #children do
        local child = children[i]
        if child.visible ~= false then
            local isContainer = child.children ~= nil
            if not isContainer
                and child.isInteractive and child:isInteractive()
                and child.contains and child:contains(mx, my) then
                return true
            end
            if hitsChildren(child, mx, my) then
                return true
            end
        end
    end
    return false
end

function proto:containsDescendant(mx, my)
    if not self.content then
        return false
    end
    return hitsChildren(self.content, mx, my)
end

function proto:mousepressed(mx, my, button)
    if not self.visible or not self.enabled then
        return false
    end
    if button ~= nil and button ~= 1 then
        return false
    end

    -- 1. 滚动条优先：按在滑块上可拖动，按在空白轨道则直接跳过去
    if self:_barHit(mx, my) then
        local _, _, _, _, thumbY, thumbH = self:_barMetrics()
        local onThumb = my >= thumbY and my <= thumbY + thumbH
        self._barDragging = true
        self._barGrab = onThumb and (my - thumbY) or thumbH / 2
        self._dragging = false
        self:_barDragTo(my)
        return true
    end

    if not self:contains(mx, my) then
        -- 已经滚出视口、但仍压在子组件上的点击：吃掉，避免误触
        if self:containsDescendant(mx, my) then
            return true
        end
        return false
    end

    -- 2. 点在子组件上：交给子组件，自己不启动拖动
    if self:containsDescendant(mx, my) then
        return false
    end

    if not self.drag then
        return false
    end

    self._dragging = true
    self._lastY = my
    return true
end

function proto:mousereleased(mx, my, button)
    if button ~= nil and button ~= 1 then
        return false
    end

    local wasDrag = self._dragging
    local handled = wasDrag or self._barDragging
    self._dragging = false
    self._barDragging = false
    self._barGrab = nil

    if wasDrag and self.momentum then
        local velocity = self._dragVelocity or 0
        if math.abs(velocity) >= (self.momentumMin or 1) then
            self._scrollVelocity = velocity
            self._scrollTarget = self.scrollY
        else
            self._scrollVelocity = 0
        end
    end
    self._dragVelocity = 0

    return handled == true
end

-- 指针靠近滚动条时把它变宽，方便手指按（离开后缩回去）
function proto:_tickBar(dt)
    local baseW = self.scrollbarWidth or 4
    local activeW = math.max(baseW, self.scrollbarActiveWidth or baseW * 2)

    local mx, my = love.mouse.getPosition()
    local active = self._barDragging or self:_barHit(mx, my)
    local target = active and activeW or baseW

    local k = 1 - math.exp(-(self.scrollbarGrowSpeed or 16) * (dt or 1 / 60))
    local current = self._barW or baseW
    self._barW = current + (target - current) * k
end

-- 平滑滚动 + 惯性：位置向目标缓动，速度按 friction 衰减
function proto:_tickScroll(dt)
    dt = dt or 1 / 60

    local velocity = self._scrollVelocity or 0
    if math.abs(velocity) > 0.01 then
        local nextY = self:_clampScroll(self.scrollY + velocity * dt * 60)
        self:_applyScroll(nextY)
        self._scrollTarget = self.scrollY

        velocity = velocity * math.exp(-(self.momentumFriction or 6) * dt)
        local maxScroll = self._maxScroll or 0
        if nextY <= 0 or nextY >= maxScroll or math.abs(velocity) < 0.05 then
            velocity = 0
        end
        self._scrollVelocity = velocity
        return
    end
    self._scrollVelocity = 0

    local target = self._scrollTarget
    if target == nil then
        return
    end

    local diff = target - self.scrollY
    if math.abs(diff) < 0.5 then
        if diff ~= 0 then
            self:_applyScroll(target)
        end
        return
    end

    local k = 1 - math.exp(-(self.smoothSpeed or 14) * dt)
    self:_applyScroll(self.scrollY + diff * k)
end

function proto:_tick(dt)
    self:_tickBar(dt)

    if self._barDragging then
        if love.mouse.isDown(1) then
            self:_barDragTo((select(2, love.mouse.getPosition())))
        else
            self._barDragging = false
        end
        return
    end

    if self._dragging then
        if love.mouse.isDown(1) then
            local mx, my = love.mouse.getPosition()
            local dy = my - (self._lastY or my)
            self._lastY = my
            -- 拖拽直接跟手，不走缓动
            self:setScroll(self.scrollY - dy)
            -- 记录速度（像素/帧），松手后转成惯性
            self._dragVelocity = (self._dragVelocity or 0) * 0.6 + (-dy) * 0.4
            return
        end
        self._dragging = false
    end

    self:_tickScroll(dt)
end

function proto:wheelmoved(dx, dy)
    if not self.visible or not self.enabled then
        return false
    end
    local mx, my = love.mouse.getPosition()
    if not self:contains(mx, my) then
        return false
    end
    self:scrollBy(-(dy or 0) * (self.wheelStep or 44))
    return true
end

function proto:destroy()
    if self.content and self.content.destroy then
        self.content:destroy()
        self.content = nil
    end
    return Component.destroy(self)
end

setmetatable(ScrollView, {
    __call = function(_, opts)
        return ScrollView.new(opts)
    end,
})

return ScrollView
