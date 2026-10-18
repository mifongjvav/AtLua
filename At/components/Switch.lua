-- 开关：点击切换，旋钮带过渡动画。
--
--   local wifi = At.Switch{ w = 52, h = 28, value = true,
--       onChange = function(value) print(value) end }

local Component = require("At.core.component")
local color = require("At.core.color")
local pixel = require("At.core.pixel")

local Switch = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = 52,
	h = 28,
	radius = nil, -- 缺省取高度的一半（胶囊形）
	value = false,
	color = "#4A5160", -- 关闭时的轨道色
	onColor = "#7FA88F", -- 打开时的轨道色
	knobColor = "#F2F5FA",
	knobInset = 3,
	alpha = 255,
	speed = 16, -- 动画收敛速度（越大越快）
	onChange = nil,
}

function Switch.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self.value = self.value and true or false
	self._t = self.value and 1 or 0
	return self
end

function proto:getValue()
	return self.value
end

function proto:setValue(value, silent)
	value = value and true or false
	if value == self.value then
		return self.value
	end
	self.value = value
	if not silent and self.onChange then
		self.onChange(value, self)
	end
	return self.value
end

function proto:toggle()
	return self:setValue(not self.value)
end

function proto:_press(mx)
	self._pressStartX = mx
	self._dragOffset = 0
	self._dragged = false
	return true
end

function proto:_release(mx, my, inside)
	local dragged = self._dragged
	self._dragged = false
	self._dragOffset = 0
	self._pressStartX = nil

	-- 拖动过程中已经决定了开关；没拖过才按点击切换
	if inside and not dragged then
		self:toggle()
	end
	return inside
end

function proto:_tick(dt)
	local target = self.value and 1 or 0
	local speed = self.speed or 16
	local k = 1 - math.exp(-speed * (dt or 0))
	self._t = self._t + (target - self._t) * k

	-- 按住后左右拖动：越过阈值就切换（可以来回拖，松手不再二次切换）
	if self._pressed and self._pressStartX then
		local mx = love.mouse.getPosition()
		local dx = mx - self._pressStartX
		local threshold = math.max(8, (self.w or 52) * 0.18)

		if math.abs(dx) >= threshold then
			self._dragged = true
			local wanted = dx > 0
			if wanted ~= self.value then
				self:setValue(wanted)
			end
		end

		self._dragOffset = math.max(-6, math.min(6, dx * 0.12))
	else
		self._dragOffset = 0
	end
end

function proto:_draw()
	local r = self:rect()
	local x, y = pixel.xy(r.x, r.y)
	local w, h = pixel.round(r.w), pixel.round(r.h)
	local radius = self.radius or (math.min(w, h) / 2)
	local track = color.mix(self.color, self.onColor, self._t)
	if not self.enabled then
		track = color.shade(track, -0.25)
	end

	color.setColor(track, self.alpha)
	love.graphics.rectangle("fill", x, y, w, h, radius)

	local inset = self.knobInset or 3
	local knob = h - inset * 2
	local travel = w - inset * 2 - knob
	local knobX = x + inset + travel * self._t + (self._dragOffset or 0)
	knobX = math.max(x + inset, math.min(x + inset + travel, knobX))

	color.setColor(self.knobColor, self.alpha)
	love.graphics.rectangle("fill", pixel.round(knobX), y + inset, knob, knob, knob / 2)
end

setmetatable(Switch, {
	__call = function(_, opts)
		return Switch.new(opts)
	end,
})

return Switch
