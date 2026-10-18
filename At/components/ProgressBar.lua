-- 确定性进度条：value 是 0..1，填充宽度用弹簧平滑过渡。
--
--   local progress = At.ProgressBar{ w = "100%", h = 12, value = 0.4 }
--   progress:setValue(0.8)        -- 会自动动画到 80%
--
-- 不确定性进度条见 At.LoadingBar。

local Component = require("At.core.component")
local color = require("At.core.color")
local pixel = require("At.core.pixel")
local motion = require("At.core.motion")

local ProgressBar = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = 220,
	h = 12,
	radius = nil, -- 缺省取高度的一半（胶囊形）

	value = 0, -- 0..1
	trackColor = "#4A5160",
	fillColor = "#9FB3D3",
	alpha = 255,

	animate = true,
	springStiffness = 260,
	springDamping = 30,

	onChange = nil,
}

local function clamp01(value)
	value = tonumber(value) or 0
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

function ProgressBar.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self.value = clamp01(self.value)
	self._fill = motion.spring({
		value = self.value,
		stiffness = self.springStiffness,
		damping = self.springDamping,
	})
	return self
end

function proto:getValue()
	return self.value
end

function proto:setValue(value, silent)
	value = clamp01(value)
	if value == self.value then
		return self.value
	end
	self.value = value
	if not silent and self.onChange then
		self.onChange(value, self)
	end
	return self.value
end

function proto:measure()
	local declaredW, declaredH = self:declaredWidth(), self:declaredHeight()
	return (type(declaredW) == "number" and declaredW) or self.w, (type(declaredH) == "number" and declaredH) or self.h
end

function proto:_tick(dt)
	local target = self.value
	self._fill:setTarget(target)
	if self.animate == false then
		self._fill:snap(target)
	else
		self._fill:update(dt)
	end
end

function proto:_draw()
	local r = self:rect()
	local x, y = pixel.xy(r.x, r.y)
	local w, h = pixel.round(r.w), pixel.round(r.h)
	local radius = self.radius or h / 2

	color.setColor(self.trackColor, self.alpha)
	love.graphics.rectangle("fill", x, y, w, h, radius)

	-- 弹簧可能轻微过冲，宽度夹回 0..1，避免填出轨道
	local progress = self._fill and self._fill.value or self.value
	progress = math.min(1, math.max(0, progress))
	local fillW = math.floor(w * progress + 0.5)
	if fillW > 0 then
		local fillRadius = math.min(radius, fillW / 2)
		color.setColor(self.fillColor, self.alpha)
		love.graphics.rectangle("fill", x, y, fillW, h, fillRadius)
	end
end

setmetatable(ProgressBar, {
	__call = function(_, opts)
		return ProgressBar.new(opts)
	end,
})

return ProgressBar
