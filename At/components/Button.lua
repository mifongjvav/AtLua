-- 按钮组件：几何 + 样式 + 交互状态 + 涟漪 + 居中文字，全部自带。
--
--   local btn = At.Button{
--       x = 60, y = 60, w = 180, h = 48, radius = 12,
--       color = "#9FB3D3", text = "确定",
--       onClick = function(self) print("click", self.text) end,
--   }
--
--   love.update(dt)        -> At.update(dt)          -- 推进涟漪与悬停状态
--   love.draw()            -> btn:draw()            -- 阴影/底色/涟漪/文字一起画
--   love.mousepressed(...)   -> At.mousepressed(x, y, b)
--   love.mousereleased(...)  -> At.mousereleased(x, y, b)

local Component = require("At.core.component")
local color = require("At.core.color")
local shadow = require("At.core.shadow")
local pixel = require("At.core.pixel")
local blur = require("At.effects.blur")
local Ripple = require("At.effects.Ripple")
local motion = require("At.core.motion")

local Button = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = 120,
	h = 44,
	radius = 10,

	color = "#9FB3D3",
	alpha = 255,
	hoverColor = nil, -- 缺省由 color.shade 自动算
	pressedColor = nil,

	shadow = true,
	shadowArgs = nil, -- {颜色RGBA表, radius, layers, offsetX, offsetY}

	ripple = true, -- true / false / { color = "#FFFFFF", alpha = 255 }
	text = nil,
	textColor = "#FFFFFF",
	fontSize = nil, -- 缺省沿用当前 love.graphics 字体
	paddingX = 16, -- 仅用于 auto 尺寸
	paddingY = 10,

	-- 悬停/按下的高光过渡（不影响 fillColor 的精确取值）
	animate = true,
	springStiffness = 500,
	springDamping = 30,
}

-- shadow = {颜色表, radius, layers, offsetX, offsetY} 这种简写也算开启阴影
local function normalizeStyle(self)
	if type(self.shadow) == "table" then
		self.shadowArgs = self.shadow
		self.shadow = true
	end
	if self.shadow and not self.shadowArgs then
		self.shadowArgs = { { 0, 0, 0, 0.2 }, 5, 20, 2, 3 }
	end

	if type(self.ripple) == "table" then
		local opts = self.ripple
		self.ripple = true
		self._ripple = Ripple.new({
			enabled = opts.enabled,
			color = opts.color or "#FFFFFF",
			alpha = opts.alpha,
		})
	elseif self.ripple then
		self._ripple = Ripple.new({ color = "#FFFFFF" })
	else
		self._ripple = nil
	end
end

function Button.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	normalizeStyle(self)
	self._hoverT = motion.spring({ stiffness = self.springStiffness, damping = self.springDamping })
	self._pressT = motion.spring({ stiffness = self.springStiffness, damping = self.springDamping })
	return self
end

function Button.setStyle(button, opts)
	for key, value in pairs(opts or {}) do
		button[key] = value
	end
	normalizeStyle(button)
	return button
end

-- ---------- 尺寸 ----------

function proto:measure()
	local f = self:font()
	local text = self.text ~= nil and tostring(self.text) or ""
	local textW = f:getWidth(text)
	local textH = f:getHeight()

	local declaredW, declaredH = self:declaredWidth(), self:declaredHeight()
	local w = type(declaredW) == "number" and declaredW or (textW + self.paddingX * 2)
	local h = type(declaredH) == "number" and declaredH or (textH + self.paddingY * 2)
	return w, h
end

-- ---------- 样式 ----------

function proto:setColor(hex, alpha)
	self.color = hex
	if alpha then
		self.alpha = alpha
	end
	return self
end

function proto:setText(text)
	self.text = text
	self:invalidateSize()
	return self
end

function proto:setRippleEnabled(enabled)
	if not self._ripple then
		if enabled then
			self._ripple = Ripple.new({ color = "#FFFFFF" })
		end
		return self
	end
	self._ripple:setEnabled(enabled)
	return self
end

-- 当前存活的涟漪数量（调试/测试用）
function proto:rippleCount()
	if not self._ripple then
		return 0
	end
	return self._ripple:count()
end

-- 底色优先级：按下 > 悬停 > 常态；禁用时回到底色
function proto:fillColor()
	if not self.enabled then
		return self.color
	end
	if self._pressed and self._hover then
		return self.pressedColor or color.shade(self.color, -0.12)
	end
	if self._hover then
		return self.hoverColor or color.shade(self.color, 0.10)
	end
	return self.color
end

function proto:fillAlpha()
	if self.enabled then
		return self.alpha
	end
	return math.floor(self.alpha * 0.45 + 0.5)
end

-- ---------- 生命周期钩子 ----------

function proto:_draw()
	local r = self:rect()
	local x, y = pixel.xy(r.x, r.y)
	local w, h = pixel.round(r.w), pixel.round(r.h)
	r = { x = x, y = y, w = w, h = h, radius = r.radius }

	if self.shadow then
		shadow.shadow(x, y, w, h, r.radius, unpack(self.shadowArgs))
	end

	if self:fillAlpha() < 255 then
		blur.drawBackdrop(x, y, w, h, r.radius)
	end

	color.setColor(self:fillColor(), self:fillAlpha())
	love.graphics.rectangle("fill", x, y, w, h, r.radius)

	-- 悬停/按下的高光：单独一层叠加，fillColor() 仍只反映离散状态
	if self.animate ~= false then
		local hoverT = self._hoverT and self._hoverT.value or 0
		local pressT = self._pressT and self._pressT.value or 0
		local glow = math.min(0.13, hoverT * 0.05 + pressT * 0.08)
		if glow > 0.004 then
			color.setColor("#FFFFFF", math.floor(self:fillAlpha() * glow))
			love.graphics.rectangle("fill", x, y, w, h, r.radius)
		end
	end

	if self._ripple then
		-- 涟漪裁剪在按钮内部，避免边角溢出
		local sx, sy, sw, sh = love.graphics.getScissor()
		love.graphics.setScissor(r.x, r.y, r.w, r.h)
		self._ripple:draw()
		if sx then
			love.graphics.setScissor(sx, sy, sw, sh)
		else
			love.graphics.setScissor()
		end
	end

	self:_drawText(r)
end

function proto:_drawText(r)
	if self.text == nil or self.text == "" then
		return
	end

	if self.fontSize then
		love.graphics.setFont(self:font())
	end

	local f = love.graphics.getFont()
	local text = tostring(self.text)
	local textW = f:getWidth(text)
	local textH = f:getHeight()

	color.setColor(self.textColor, self:fillAlpha())
	love.graphics.print(text, math.floor(r.x + (r.w - textW) / 2), math.floor(r.y + (r.h - textH) / 2))
end

function proto:_press(mx, my)
	if self._ripple then
		self._ripple:add(mx, my, self.x, self.y, self.w, self.h, self.radius)
	end
	if self.onPress then
		self.onPress(self, mx, my)
	end
	return true
end

function proto:_release(mx, my, inside)
	if self._ripple then
		self._ripple:release()
	end
	if self.onRelease then
		self.onRelease(self, mx, my, inside)
	end
	if inside and self.onClick then
		self.onClick(self, mx, my)
	end
	return inside
end

-- 按压中拖出按钮：涟漪淡出；拖回来还能继续（松开时仍算点击）
function proto:_onHoverChanged(hover)
	if not self._pressed or not self._ripple then
		return
	end
	if hover then
		local mx, my = love.mouse.getPosition()
		self._ripple:add(mx, my, self.x, self.y, self.w, self.h, self.radius)
	else
		self._ripple:release()
	end
end

function proto:_tick(dt)
	if self._ripple then
		self._ripple:update(dt)
	end
	if self.animate ~= false then
		self._hoverT:setTarget(self._hover and 1 or 0)
		self._pressT:setTarget((self._pressed and self._hover) and 1 or 0)
		self._hoverT:update(dt)
		self._pressT:update(dt)
	end
end

function proto:_onDisable()
	if self._ripple then
		self._ripple:release()
	end
end

-- 允许 At.Button{...} 直接当构造函数用
setmetatable(Button, {
	__call = function(_, opts)
		return Button.new(opts)
	end,
})

return Button
