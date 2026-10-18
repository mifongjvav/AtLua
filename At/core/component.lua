-- 组件基类：几何、状态、事件、生命周期与排版协议的公共实现。
--
-- 子类继承方式：
--   local proto = setmetatable({}, { __index = Component })
--   proto.__index = proto
--   function MyComp.new(opts)
--       return Component.instantiate(proto, opts, DEFAULTS)
--   end
--
-- 可选钩子（按需实现，不要全部实现）：
--   _draw()                      画自己（draw 已负责保存/恢复颜色与字体）
--   _press(mx, my)               按下；返回 false 表示不消费事件
--   _release(mx, my, inside)     松开；inside 表示指针是否仍在组件内
--   _tick(dt)                    每帧逻辑（动画、拖拽轮询）
--   _onHoverChanged(hover)       悬停状态变化
--   _onFocus() / _onBlur()       焦点变化
--   measure(availW, availH)      自然尺寸，供布局引擎在 w/h = "auto" 时调用

local registry = require("At.core.registry")
local SDF = require("At.core.SDF")
local font = require("At.core.font")

local Component = {}

local DEFAULTS = {
	x = 0,
	y = 0,
	w = 0,
	h = 0,
	enabled = true,
	visible = true,
	autoRegister = true,
	passthrough = false, -- true: 不消费鼠标事件（容器组件用）
}

-- 子类调用：Component.instantiate(proto, opts, defaults)
function Component.instantiate(proto, opts, defaults)
	local self = setmetatable({}, proto)

	for key, value in pairs(DEFAULTS) do
		self[key] = value
	end
	for key, value in pairs(defaults or {}) do
		self[key] = value
	end
	for key, value in pairs(opts or {}) do
		self[key] = value
	end

	-- 原始尺寸规格（"auto" / "50%" / 数字）与当前像素值分开保存：
	-- 排版会把 w/h 写成像素，规格用于下次重排与内容变化时重新测量。
	if self._specW == nil then
		self._specW, self._specH = self.w, self.h
	end

	self._hover = false
	self._pressed = false
	self._destroyed = false

	if self.autoRegister ~= false then
		registry.add(self)
	end

	return self
end

-- ---------- 几何 ----------

-- auto 尺寸在使用前落成像素（独立使用、没走布局引擎时也能正常绘制）
function Component:_ensureSize()
	if type(self.w) == "number" and type(self.h) == "number" then
		return
	end
	local w, h = self:measure()
	if type(self.w) ~= "number" then
		self.w = w or 0
	end
	if type(self.h) ~= "number" then
		self.h = h or 0
	end
end

function Component:rect()
	self:_ensureSize()
	return { x = self.x, y = self.y, w = self.w, h = self.h, radius = self.radius or 0 }
end

-- 用传入坐标判断命中（不读实时鼠标位置，触屏与无头测试都能用）
function Component:contains(px, py)
	self:_ensureSize()
	return SDF.roundRectSDF(px, py, {
		x = self.x,
		y = self.y,
		w = self.w,
		h = self.h,
		radius = self.radius or 0,
	}) <= 0
end

function Component:setPosition(x, y)
	self.x, self.y = x, y
	return self
end

function Component:setSize(w, h)
	self._specW, self._specH = w, h
	self.w, self.h = w, h
	return self
end

function Component:setRect(x, y, w, h, radius)
	self.x, self.y = x, y
	if w ~= nil then
		self._specW, self.w = w, w
	end
	if h ~= nil then
		self._specH, self.h = h, h
	end
	if radius ~= nil then
		self.radius = radius
	end
	return self
end

-- ---------- 状态 ----------

function Component:setEnabled(enabled)
	self.enabled = enabled and true or false
	if not self.enabled then
		self._pressed = false
		if self:isFocused() then
			self:blur()
		end
		if self._onDisable then
			self:_onDisable()
		end
	end
	return self
end

function Component:isEnabled()
	return self.enabled
end

function Component:setVisible(visible)
	self.visible = visible and true or false
	if not self.visible then
		self._pressed = false
		if self:isFocused() then
			self:blur()
		end
	end
	return self
end

function Component:isVisible()
	return self.visible
end

-- 是否响应鼠标：显式 interactive 优先，否则看有没有实现 _press/_release。
-- Label 这类纯展示组件不该消费点击，否则会挡住容器拖动。
function Component:isInteractive()
	if self.interactive ~= nil then
		return self.interactive and true or false
	end
	return self._press ~= nil or self._release ~= nil
end

function Component:isHovered()
	return self._hover
end

-- 按住且指针仍在组件内才算"按下态"（拖出去恢复常态，但仍记得这次按压）
function Component:isPressed()
	return self._pressed and self._hover
end

-- ---------- 焦点（同一时刻只有一个组件持有） ----------

function Component:focus()
	registry.setFocus(self)
	return self
end

function Component:blur()
	if registry.getFocus() == self then
		registry.setFocus(nil)
	end
	return self
end

function Component:isFocused()
	return registry.getFocus() == self
end

-- ---------- 排版协议 ----------

-- 声明的尺寸（原始规格），与当前像素值区分开
function Component:declaredWidth()
	local value = self._specW
	if value == nil then
		value = self.w
	end
	return value
end

function Component:declaredHeight()
	local value = self._specH
	if value == nil then
		value = self.h
	end
	return value
end

-- 默认自然尺寸：显式像素优先，否则 0（子类通常要覆盖）
function Component:measure()
	local w, h = self:declaredWidth(), self:declaredHeight()
	return (type(w) == "number" and w) or 0, (type(h) == "number" and h) or 0
end

-- 内容变化后让 auto 尺寸重新测量（回到原始规格，下次使用/排版时再落成像素）
function Component:invalidateSize()
	self.w, self.h = self._specW, self._specH
	return self
end

function Component:font()
	if self.fontSize then
		return font.get(self.fontSize)
	end
	return love.graphics.getFont()
end

-- ---------- 生命周期 ----------

function Component:update(dt)
	if self._destroyed or not self.visible then
		return
	end

	-- 被动组件不需要悬停检测，省掉每帧命中计算
	if self:isInteractive() then
		local mx, my = love.mouse.getPosition()
		local wasHover = self._hover
		self._hover = (self.enabled and self:contains(mx, my)) or false

		if self._hover ~= wasHover and self._onHoverChanged then
			self:_onHoverChanged(self._hover)
		end
	end

	if self._tick then
		self:_tick(dt)
	end
end

function Component:draw()
	if self._destroyed or not self.visible then
		return
	end

	self:_ensureSize()

	local prevR, prevG, prevB, prevA = love.graphics.getColor()
	local prevFont = love.graphics.getFont()
	local prevLineWidth = love.graphics.getLineWidth()
	local prevLineStyle = love.graphics.getLineStyle()

	-- 1px 边框/勾线用 rough 画，smooth 会在亚像素处发虚
	love.graphics.setLineStyle("rough")
	self:_draw()
	love.graphics.setLineStyle(prevLineStyle)

	love.graphics.setLineWidth(prevLineWidth)
	love.graphics.setFont(prevFont)
	love.graphics.setColor(prevR, prevG, prevB, prevA)
end

function Component:mousepressed(mx, my, button)
	if self._destroyed or not self.visible or not self.enabled then
		return false
	end
	if self.passthrough or not self:isInteractive() then
		return false
	end
	if button ~= nil and button ~= 1 then
		return false
	end
	if not self:contains(mx, my) then
		return false
	end

	self._pressed = true
	self._hover = true

	if self._press then
		return self:_press(mx, my) ~= false
	end
	return true
end

function Component:mousereleased(mx, my, button)
	if button ~= nil and button ~= 1 then
		return false
	end
	if not self._pressed then
		return false
	end

	self._pressed = false
	local inside = (self.enabled and self:contains(mx, my)) or false
	self._hover = inside

	if self._release then
		local handled = self:_release(mx, my, inside)
		if handled ~= nil then
			return handled ~= false
		end
	end

	return inside
end

function Component:destroy()
	if self._destroyed then
		return false
	end
	registry.remove(self)
	if registry.getFocus() == self then
		registry.setFocus(nil)
	end
	self._destroyed = true
	if self._onDestroy then
		self:_onDestroy()
	end
	return true
end

function Component:isDestroyed()
	return self._destroyed
end

return Component
