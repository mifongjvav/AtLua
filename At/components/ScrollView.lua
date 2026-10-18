-- 可滚动视口：内容超出宽或高时自动出现对应的滚动条，支持双向拖动、滚轮、惯性。
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

local Component = require("At.core.component")
local color = require("At.core.color")
local layout = require("At.core.layout")
local clip = require("At.core.clip")
local pixel = require("At.core.pixel")
local motion = require("At.core.motion")
local blur = require("At.effects.blur")

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
	scrollbarActiveWidth = 8, -- 指针碰到滚动条/拖动时的宽度
	scrollbarGrowSpeed = 16, -- 已弃用：滚动条宽度改用弹簧
	scrollbarSpringStiffness = 700,
	scrollbarSpringDamping = 42,
	scrollbarColor = "#3A4150",
	scrollbarThumbColor = "#9FB3D3",
	scrollbarHitWidth = 16, -- 滚动条的可拖拽宽度（比视觉宽度大，方便手指）
	scrollbarMargin = 2,
	wheelStep = 44,
	-- 触顶/触底：拖到边界后可以再拉出一点（橡皮筋），松开弹回，并在边缘泛光
	edgeEffect = true,
	edgeGlowColor = "#9FB3D3",
	edgeGlowSize = 28,
	overscrollMax = 70, -- 最多能拉出多少像素
	overscrollResistance = 0.55, -- 拉出距离的衰减（越小越硬）
	edgeSpringStiffness = 380,
	edgeSpringDamping = 30,
	drag = true, -- 允许按住空白处拖动滚动（触屏也走鼠标事件）
	smooth = true, -- 滚轮/代码滚动是否缓动（拖拽始终 1:1 跟手）
	smoothSpeed = 14,
	momentum = true, -- 松手后是否保留惯性
	momentumFriction = 6,
	momentumMin = 1,
	alpha = 255,
	interactive = true, -- 嵌套在别的 ScrollView 里时，外层会把事件让给它
	onScroll = nil,
}

function ScrollView.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self.scrollX = math.max(0, tonumber(self.scrollX) or 0)
	self.scrollY = math.max(0, tonumber(self.scrollY) or 0)
	self._maxScrollX = 0
	self._maxScrollY = 0
	self._barW = self.scrollbarWidth or 4
	self._barSpring = motion.spring({
		value = self._barW,
		stiffness = self.scrollbarSpringStiffness,
		damping = self.scrollbarSpringDamping,
	})
	self._scrollTarget = self.scrollY
	self._scrollTargetX = self.scrollX
	self._scrollVelocity = 0
	self._scrollVelocityX = 0
	self._dragVelocity = 0
	self._dragVelocityX = 0

	-- 过冲量：正数 = 内容被往下/往右拉，负数相反；绘制时叠加到 scroll 上
	self._overX = 0
	self._overY = 0
	self._overSpringX = motion.spring({
		stiffness = self.edgeSpringStiffness,
		damping = self.edgeSpringDamping,
	})
	self._overSpringY = motion.spring({
		stiffness = self.edgeSpringStiffness,
		damping = self.edgeSpringDamping,
	})
	-- 触边脉冲：滚轮/惯性顶到边界时闪一下边缘光，没有过冲也看得见
	self._edgePulse = { top = 0, bottom = 0, left = 0, right = 0 }
	return self
end

-- ---------- 尺寸与滚动量 ----------

function proto:_innerBox()
	self:_ensureSize()
	local pl, pt, pr, pb = layout.sides(self.padding)
	return self.w - pl - pr, self.h - pt - pb
end

function proto:maxScroll()
	return self._maxScrollY or 0
end

function proto:maxScrollX()
	return self._maxScrollX or 0
end

local function clamp(value, maxValue)
	value = tonumber(value) or 0
	if value < 0 then
		return 0
	elseif value > maxValue then
		return maxValue
	end
	return value
end

function proto:_clampScroll(value)
	return clamp(value, self._maxScrollY or 0)
end

function proto:_clampScrollX(value)
	return clamp(value, self._maxScrollX or 0)
end

-- 触边时点亮对应边缘（top/bottom/left/right），由 _tick 衰减
function proto:_pulseEdge(side)
	if not self.edgeEffect or not side then
		return
	end
	-- 横向滚动不触发上下边缘，纵向滚动不触发左右边缘
	if side == "top" or side == "bottom" then
		if (self._maxScrollY or 0) <= 0 then
			return
		end
	elseif (self._maxScrollX or 0) <= 0 then
		return
	end

	local pulses = self._edgePulse
	if pulses and pulses[side] ~= nil then
		pulses[side] = 1
	end
end

-- 过冲量的软限位：越拉越硬，避免拉出视口之外太远
function proto:_clampOver(value)
	local maxOver = self.overscrollMax or 70
	if value > maxOver then
		return maxOver + (value - maxOver) * 0.25
	elseif value < -maxOver then
		return -maxOver + (value + maxOver) * 0.25
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
		self.onScroll(value, self._maxScrollY, self, "y")
	end
	return self.scrollY
end

function proto:_applyScrollX(value, silent)
	value = self:_clampScrollX(value)
	if value == self.scrollX then
		return self.scrollX
	end

	self.scrollX = value
	if not silent and self.onScroll then
		self.onScroll(value, self._maxScrollX, self, "x")
	end
	return self.scrollX
end

function proto:setScroll(value, silent)
	local clamped = self:_clampScroll(value)
	self._scrollTarget = clamped
	self._scrollVelocity = 0
	self._dragVelocity = 0
	return self:_applyScroll(clamped, silent)
end

function proto:setScrollX(value, silent)
	local clamped = self:_clampScrollX(value)
	self._scrollTargetX = clamped
	self._scrollVelocityX = 0
	self._dragVelocityX = 0
	return self:_applyScrollX(clamped, silent)
end

-- 平滑滚动：只改目标，位置在 _tick 里缓动逼近
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

function proto:scrollToX(value, silent)
	local clamped = self:_clampScrollX(value)

	if not self.smooth then
		return self:setScrollX(clamped, silent)
	end

	self._scrollVelocityX = 0
	self._scrollTargetX = clamped

	if math.abs(clamped - self.scrollX) < 0.5 then
		return self:_applyScrollX(clamped, silent)
	end
	return self.scrollX
end

-- 相对滚动按"目标位置"累加，滚轮连发时不会互相吞掉
function proto:scrollBy(delta, silent)
	local base = self._scrollTarget or self.scrollY
	return self:scrollTo(base + delta, silent)
end

function proto:scrollByX(delta, silent)
	local base = self._scrollTargetX or self.scrollX
	return self:scrollToX(base + delta, silent)
end

-- 把某个子组件滚动到可见范围内（横竖两个方向都会处理）
function proto:scrollToVisible(component, margin)
	if not component then
		return self.scrollY
	end
	margin = margin or 16

	local pl, pt, pr, pb = layout.sides(self.padding)
	local viewW = self.w - pl - pr
	local viewH = self.h - pt - pb

	local left = component.x - (self.x + pl)
	local top = component.y - (self.y + pt)
	local right = left + (component.w or 0)
	local bottom = top + (component.h or 0)

	if left - margin < self.scrollX then
		self:setScrollX(left - margin)
	elseif right + margin > self.scrollX + viewW then
		self:setScrollX(right + margin - viewW)
	end

	if top - margin < self.scrollY then
		self:setScroll(top - margin)
	elseif bottom + margin > self.scrollY + viewH then
		self:setScroll(bottom + margin - viewH)
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
	local pl, pt = layout.sides(self.padding)

	-- 先量一次，决定内容可用宽度：
	-- 内容自然宽度比视口窄时按视口宽排版（这样 "100%" 有效）；
	-- 比视口宽时保留它的自然宽度，才会出现横向滚动。
	local naturalW = content:measure(innerW, nil)
	local availW = math.max(innerW, naturalW or 0)
	content._availW = availW
	content._availH = nil

	local finalW, contentH = content:measure(availW, nil)
	availW = math.max(innerW, finalW or availW)
	content._availW = availW

	-- 宽度变了可能影响换行，再量一次高度
	if finalW ~= naturalW then
		local _, remeasuredH = content:measure(availW, nil)
		contentH = math.max(contentH or 0, remeasuredH or 0)
	end

	self._maxScrollX = math.max(0, pixel.round((finalW or availW) - innerW))
	self._maxScrollY = math.max(0, pixel.round((contentH or 0) - innerH))

	self.scrollX = self:_clampScrollX(self.scrollX)
	self.scrollY = self:_clampScroll(self.scrollY)
	self._scrollTargetX = self:_clampScrollX(self._scrollTargetX or self.scrollX)
	self._scrollTarget = self:_clampScroll(self._scrollTarget or self.scrollY)

	-- 没有滚动空间的轴不该保留过冲或触边光（内容变短/单向滚动时尤其明显）
	if self._maxScrollY <= 0 then
		self._overY = 0
		if self._overSpringY then
			self._overSpringY:snap(0)
		end
		if self._edgePulse then
			self._edgePulse.top, self._edgePulse.bottom = 0, 0
		end
	end
	if self._maxScrollX <= 0 then
		self._overX = 0
		if self._overSpringX then
			self._overSpringX:snap(0)
		end
		if self._edgePulse then
			self._edgePulse.left, self._edgePulse.right = 0, 0
		end
	end

	-- 内容整体位移对齐到像素：拖动滚动时文字才不会发虚/抖动。
	-- 触边过冲只驱动边缘光，不推开内容（避免在容器里留出空隙、看起来像画到外面）。
	content.x = pixel.round(self.x + pl - self.scrollX)
	content.y = pixel.round(self.y + pt - self.scrollY)
end

-- ---------- 滚动条几何 ----------

-- 纵向：返回 trackX, trackY, barW, trackH, thumbY, thumbH
function proto:_barMetrics()
	local barW = self._barW or self.scrollbarWidth or 4
	local pad = self.scrollbarMargin or 2
	local trackX = self.x + self.w - barW - pad
	local trackY = self.y + pad
	local trackH = self.h - pad * 2

	-- 横向滚动条占住底部时，纵向轨道要让出位置
	if (self._maxScrollX or 0) > 0 then
		trackH = trackH - (barW + pad)
	end

	local _, pt, _, pb = layout.sides(self.padding)
	local viewH = self.h - pt - pb
	local maxScroll = self._maxScrollY or 0

	local thumbH = trackH
	if maxScroll > 0 and viewH > 0 and trackH > 0 then
		thumbH = math.max(24, trackH * (viewH / (viewH + maxScroll)))
	end
	if thumbH > trackH then
		thumbH = trackH
	end

	local t = maxScroll > 0 and (self.scrollY / maxScroll) or 0
	local thumbY = trackY + (trackH - thumbH) * t

	return trackX, trackY, barW, trackH, thumbY, thumbH
end

-- 横向：返回 trackX, trackY, barW, trackW, thumbX, thumbW
function proto:_hbarMetrics()
	local barW = self._barW or self.scrollbarWidth or 4
	local pad = self.scrollbarMargin or 2
	local trackX = self.x + pad
	local trackY = self.y + self.h - barW - pad
	local trackW = self.w - pad * 2

	-- 纵向滚动条占住右侧时，横向轨道要让出位置
	if (self._maxScrollY or 0) > 0 then
		trackW = trackW - (barW + pad)
	end

	local pl, _, pr = layout.sides(self.padding)
	local viewW = self.w - pl - pr
	local maxScroll = self._maxScrollX or 0

	local thumbW = trackW
	if maxScroll > 0 and viewW > 0 and trackW > 0 then
		thumbW = math.max(24, trackW * (viewW / (viewW + maxScroll)))
	end
	if thumbW > trackW then
		thumbW = trackW
	end

	local t = maxScroll > 0 and (self.scrollX / maxScroll) or 0
	local thumbX = trackX + (trackW - thumbW) * t

	return trackX, trackY, barW, trackW, thumbX, thumbW
end

function proto:_barHit(mx, my)
	if not self.scrollbar or (self._maxScrollY or 0) <= 0 then
		return false
	end
	local trackX, trackY, barW, trackH = self:_barMetrics()
	local hitW = math.max(self.scrollbarHitWidth or 16, barW)
	local left = trackX - (hitW - barW) / 2
	return mx >= left and mx <= left + hitW and my >= trackY and my <= trackY + trackH
end

function proto:_hbarHit(mx, my)
	if not self.scrollbar or (self._maxScrollX or 0) <= 0 then
		return false
	end
	local trackX, trackY, barW, trackW = self:_hbarMetrics()
	local hitW = math.max(self.scrollbarHitWidth or 16, barW)
	local top = trackY - (hitW - barW) / 2
	return my >= top and my <= top + hitW and mx >= trackX and mx <= trackX + trackW
end

function proto:_barDragTo(my)
	local _, trackY, _, trackH, _, thumbH = self:_barMetrics()
	local travel = trackH - thumbH
	if travel <= 0 then
		return
	end

	local grab = self._barGrab or thumbH / 2
	local t = (my - grab - trackY) / travel
	if t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end

	if t <= 0 then
		self:_pulseEdge("top")
	elseif t >= 1 then
		self:_pulseEdge("bottom")
	end

	self:setScroll(t * (self._maxScrollY or 0))
end

function proto:_hbarDragTo(mx)
	local trackX, _, _, trackW, _, thumbW = self:_hbarMetrics()
	local travel = trackW - thumbW
	if travel <= 0 then
		return
	end

	local grab = self._hbarGrab or thumbW / 2
	local t = (mx - grab - trackX) / travel
	if t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end

	if t <= 0 then
		self:_pulseEdge("left")
	elseif t >= 1 then
		self:_pulseEdge("right")
	end

	self:setScrollX(t * (self._maxScrollX or 0))
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
		if (self.alpha or 255) < 255 then
			blur.drawBackdrop(pixel.round(self.x), pixel.round(self.y), self.w, self.h, self.radius or 0)
		end
		color.setColor(self.background, self.alpha)
		love.graphics.rectangle("fill", pixel.round(self.x), pixel.round(self.y), self.w, self.h, self.radius or 0)
	end

	-- 与外层裁剪求交：裁掉视口外的内容，同时不丢掉外层裁剪（支持嵌套滚动）
	local old, visible = clip.apply(pixel.round(self.x), pixel.round(self.y), self.w, self.h)
	if visible then
		if self.content then
			self.content:draw()
		end
		self:_drawEdgeEffects()
		if self.scrollbar then
			self:_drawScrollbars()
		end
	end
	clip.restore(old)

	love.graphics.setLineWidth(prevLineWidth)
	love.graphics.setFont(prevFont)
	love.graphics.setColor(prevR, prevG, prevB, prevA)
end

function proto:_drawScrollbars()
	local barRadius = (self._barW or self.scrollbarWidth or 4) / 2

	-- 纵向：只有内容超出高度才画
	if (self._maxScrollY or 0) > 0 then
		local trackX, trackY, barW, trackH, thumbY, thumbH = self:_barMetrics()
		color.setColor(self.scrollbarColor, self.alpha)
		love.graphics.rectangle("fill", trackX, trackY, barW, trackH, barRadius)
		color.setColor(self.scrollbarThumbColor, self.alpha)
		love.graphics.rectangle("fill", trackX, thumbY, barW, thumbH, barRadius)
	end

	-- 横向：只有内容超出宽度才画
	if (self._maxScrollX or 0) > 0 then
		local trackX, trackY, barW, trackW, thumbX, thumbW = self:_hbarMetrics()
		color.setColor(self.scrollbarColor, self.alpha)
		love.graphics.rectangle("fill", trackX, trackY, trackW, barW, barRadius)
		color.setColor(self.scrollbarThumbColor, self.alpha)
		love.graphics.rectangle("fill", thumbX, trackY, thumbW, barW, barRadius)
	end
end

-- 触顶/触底：在容器边缘叠一条渐隐光带（始终在容器内）。
-- 拖动时强度跟过冲量走，滚轮/惯性/滚动条拖到头时用脉冲闪一下。
function proto:_drawEdgeEffects()
	if not self.edgeEffect then
		return
	end

	local canY = (self._maxScrollY or 0) > 0
	local canX = (self._maxScrollX or 0) > 0
	if not canY and not canX then
		return
	end

	local maxOver = math.max(1, self.overscrollMax or 70)
	local pulses = self._edgePulse or {}
	local overX, overY = self._overX or 0, self._overY or 0
	local baseAlpha = (self.alpha or 255) / 255

	local r = self:rect()
	local x, y = pixel.xy(r.x, r.y)
	local w, h = pixel.round(r.w), pixel.round(r.h)
	local size = math.max(2, math.floor(self.edgeGlowSize or 28))

	local function drawBand(side, pull, pulse)
		local distance = math.abs(pull or 0)
		local amount = math.max(pulse or 0, math.min(1, distance / maxOver))
		if amount <= 0.01 then
			return
		end

		-- 宽度固定，靠 alpha 平滑变化；光带只覆盖容器边缘，不会画到外面
		local peak = 0.6 * amount * baseAlpha
		local last = math.max(1, size - 1)
		for i = 0, size - 1 do
			-- 0 = 贴边缘，1 = 光带内侧；smoothstep 让起止都不出现硬边
			local t = i / last
			local f = 1 - t
			f = f * f * (3 - 2 * f)
			local alpha = math.floor(255 * peak * f)
			if alpha > 0 then
				color.setColor(self.edgeGlowColor, alpha)
				if side == "top" then
					love.graphics.rectangle("fill", x, y + i, w, 1)
				elseif side == "bottom" then
					love.graphics.rectangle("fill", x, y + h - 1 - i, w, 1)
				elseif side == "left" then
					love.graphics.rectangle("fill", x + i, y, 1, h)
				else
					love.graphics.rectangle("fill", x + w - 1 - i, y, 1, h)
				end
			end
		end
	end

	if canY then
		drawBand("top", overY > 0 and overY or 0, pulses.top)
		drawBand("bottom", overY < 0 and -overY or 0, pulses.bottom)
	end
	if canX then
		drawBand("left", overX > 0 and overX or 0, pulses.left)
		drawBand("right", overX < 0 and -overX or 0, pulses.right)
	end
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
			if
				not isContainer
				and child.isInteractive
				and child:isInteractive()
				and child.contains
				and child:contains(mx, my)
			then
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
		self._barDragAxis = "y"
		self._barGrab = onThumb and (my - thumbY) or thumbH / 2
		self._dragging = false
		self:_barDragTo(my)
		return true
	end

	if self:_hbarHit(mx, my) then
		local _, _, _, _, thumbX, thumbW = self:_hbarMetrics()
		local onThumb = mx >= thumbX and mx <= thumbX + thumbW
		self._barDragging = true
		self._barDragAxis = "x"
		self._hbarGrab = onThumb and (mx - thumbX) or thumbW / 2
		self._dragging = false
		self:_hbarDragTo(mx)
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

	-- 3. 没有可滚动空间时不要吞点击
	if not self.drag or ((self._maxScrollX or 0) <= 0 and (self._maxScrollY or 0) <= 0) then
		return false
	end

	self._dragging = true
	self._lastX = mx
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
	self._barDragAxis = nil
	self._barGrab = nil
	self._hbarGrab = nil

	if wasDrag and self.momentum then
		local minSpeed = self.momentumMin or 1
		local vy = self._dragVelocity or 0
		local vx = self._dragVelocityX or 0
		-- 拉出边界后先回弹，别再叠一层惯性
		if math.abs(self._overY or 0) > 0.5 then
			vy = 0
		end
		if math.abs(self._overX or 0) > 0.5 then
			vx = 0
		end

		if math.abs(vy) >= minSpeed then
			self._scrollVelocity = vy
			self._scrollTarget = self.scrollY
		else
			self._scrollVelocity = 0
		end

		if math.abs(vx) >= minSpeed then
			self._scrollVelocityX = vx
			self._scrollTargetX = self.scrollX
		else
			self._scrollVelocityX = 0
		end
	end
	self._dragVelocity = 0
	self._dragVelocityX = 0

	return handled == true
end

-- 指针靠近滚动条时把它变宽，方便手指按（离开后缩回去）
function proto:_tickBars(dt)
	local baseW = self.scrollbarWidth or 4
	local activeW = math.max(baseW, self.scrollbarActiveWidth or baseW * 2)

	local mx, my = love.mouse.getPosition()
	local active = self._barDragging or self:_barHit(mx, my) or self:_hbarHit(mx, my)
	local target = active and activeW or baseW

	self._barSpring:setTarget(target)
	self._barSpring:update(dt)
	self._barW = self._barSpring.value
end

-- 过冲回弹 + 触边脉冲衰减。拖拽期间 over 由 _tick 直接写入，不在这里收敛。
function proto:_tickEdges(dt)
	local pulses = self._edgePulse
	if pulses then
		local k = math.exp(-4.5 * (dt or 0))
		for side in pairs(pulses) do
			if pulses[side] > 0 then
				local value = pulses[side] * k
				pulses[side] = value < 0.01 and 0 or value
			end
		end
	end

	if not self._dragging then
		self._overX = self._overSpringX:update(dt)
		self._overY = self._overSpringY:update(dt)
		if math.abs(self._overX) < 0.05 then
			self._overX = 0
		end
		if math.abs(self._overY) < 0.05 then
			self._overY = 0
		end
	end
end

-- 单轴缓动/惯性；vertical=true 操作 Y，否则操作 X
local function tickAxis(self, dt, vertical)
	local target = vertical and self._scrollTarget or self._scrollTargetX
	local velocity = vertical and self._scrollVelocity or self._scrollVelocityX
	local position = vertical and self.scrollY or self.scrollX
	local maxValue = vertical and (self._maxScrollY or 0) or (self._maxScrollX or 0)

	-- 没有滚动空间的轴不参与惯性/脉冲，避免"横滚触发上下光"这类串轴
	if maxValue <= 0 then
		if vertical then
			self._scrollVelocity = 0
			self._scrollTarget = 0
		else
			self._scrollVelocityX = 0
			self._scrollTargetX = 0
		end
		return
	end

	if math.abs(velocity or 0) > 0.01 then
		local rawValue = position + velocity * dt * 60
		if rawValue < 0 then
			self:_pulseEdge(vertical and "top" or "left")
		elseif rawValue > maxValue then
			self:_pulseEdge(vertical and "bottom" or "right")
		end
		local nextValue = clamp(rawValue, maxValue)

		if vertical then
			self:_applyScroll(nextValue)
			self._scrollTarget = self.scrollY
		else
			self:_applyScrollX(nextValue)
			self._scrollTargetX = self.scrollX
		end

		velocity = velocity * math.exp(-(self.momentumFriction or 6) * dt)
		if nextValue <= 0 or nextValue >= maxValue or math.abs(velocity) < 0.05 then
			velocity = 0
		end

		if vertical then
			self._scrollVelocity = velocity
		else
			self._scrollVelocityX = velocity
		end
		return
	end

	if vertical then
		self._scrollVelocity = 0
	else
		self._scrollVelocityX = 0
	end

	if target == nil then
		return
	end

	local diff = target - position
	if math.abs(diff) < 0.5 then
		if diff ~= 0 then
			if vertical then
				self:_applyScroll(target)
			else
				self:_applyScrollX(target)
			end
		end
		return
	end

	local k = 1 - math.exp(-(self.smoothSpeed or 14) * dt)
	if vertical then
		self:_applyScroll(self.scrollY + diff * k)
	else
		self:_applyScrollX(self.scrollX + diff * k)
	end
end

function proto:_tick(dt)
	dt = dt or 1 / 60
	self:_tickBars(dt)
	self:_tickEdges(dt)

	if self._barDragging then
		if love.mouse.isDown(1) then
			local mx, my = love.mouse.getPosition()
			if self._barDragAxis == "x" then
				self:_hbarDragTo(mx)
			else
				self:_barDragTo(my)
			end
		else
			self._barDragging = false
			self._barDragAxis = nil
		end
		return
	end

	if self._dragging then
		if love.mouse.isDown(1) then
			local mx, my = love.mouse.getPosition()
			local dx = mx - (self._lastX or mx)
			local dy = my - (self._lastY or my)
			self._lastX, self._lastY = mx, my

			-- 拖拽直接跟手，不走缓动；超出边界的部分转成过冲（橡皮筋）
			local maxY = self._maxScrollY or 0
			local maxX = self._maxScrollX or 0
			local desiredY = self.scrollY - dy
			local desiredX = self.scrollX - dx
			local clampedY = clamp(desiredY, maxY)
			local clampedX = clamp(desiredX, maxX)

			self:setScroll(clampedY)
			self:setScrollX(clampedX)

			-- 只有该轴真的能滚动时才做过冲（单向滚动视口不会被另一轴的拖动带偏）
			if self.edgeEffect and maxY > 0 then
				if desiredY ~= clampedY then
					local excess = desiredY - clampedY
					self._overY = self:_clampOver(self._overY - excess * (self.overscrollResistance or 0.55))
					self._overSpringY.value = self._overY
					self._overSpringY.velocity = 0
				else
					self._overY = motion.damp(self._overY, 0, 22, dt)
					self._overSpringY.value = self._overY
					self._overSpringY.velocity = 0
				end
			end

			if self.edgeEffect and maxX > 0 then
				if desiredX ~= clampedX then
					local excess = desiredX - clampedX
					self._overX = self:_clampOver(self._overX - excess * (self.overscrollResistance or 0.55))
					self._overSpringX.value = self._overX
					self._overSpringX.velocity = 0
				else
					self._overX = motion.damp(self._overX, 0, 22, dt)
					self._overSpringX.value = self._overX
					self._overSpringX.velocity = 0
				end
			end

			-- 记录速度（像素/帧），松手后转成惯性；不可滚动轴不要记录，
			-- 否则松手后会在另一轴上产生一次边界脉冲
			if maxY > 0 then
				self._dragVelocity = (self._dragVelocity or 0) * 0.6 + -dy * 0.4
			else
				self._dragVelocity = 0
			end
			if maxX > 0 then
				self._dragVelocityX = (self._dragVelocityX or 0) * 0.6 + -dx * 0.4
			else
				self._dragVelocityX = 0
			end
			return
		end
		self._dragging = false
	end

	tickAxis(self, dt, true)
	tickAxis(self, dt, false)
end

function proto:wheelmoved(dx, dy)
	if not self.visible or not self.enabled then
		return false
	end
	local mx, my = love.mouse.getPosition()
	if not self:contains(mx, my) then
		return false
	end

	local step = self.wheelStep or 44
	local shift = false
	if love.keyboard and love.keyboard.isDown then
		shift = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
	end

	local deltaX, deltaY = 0, 0
	if dx and dx ~= 0 then
		deltaX = deltaX + dx * step -- 触控板横向滚动
	end
	if dy and dy ~= 0 then
		if shift then
			deltaX = deltaX - dy * step -- Shift+滚轮 = 横向
		else
			deltaY = deltaY - dy * step
		end
	end

	local canX = (self._maxScrollX or 0) > 0
	local canY = (self._maxScrollY or 0) > 0
	local handled = false

	-- 某个方向没有滚动空间时，退让给另一个方向（例如只有竖滚的视口收到横向滚轮）
	if deltaX ~= 0 then
		if canX then
			local base = self._scrollTargetX or self.scrollX
			if base + deltaX < 0 then
				self:_pulseEdge("left")
			elseif base + deltaX > (self._maxScrollX or 0) then
				self:_pulseEdge("right")
			end
			self:scrollByX(deltaX)
			handled = true
		elseif deltaY == 0 and canY then
			self:scrollBy(deltaX)
			handled = true
		end
	end
	if deltaY ~= 0 then
		if canY then
			local base = self._scrollTarget or self.scrollY
			if base + deltaY < 0 then
				self:_pulseEdge("top")
			elseif base + deltaY > (self._maxScrollY or 0) then
				self:_pulseEdge("bottom")
			end
			self:scrollBy(deltaY)
			handled = true
		elseif deltaX == 0 and canX then
			self:scrollByX(deltaY)
			handled = true
		end
	end

	return handled
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
