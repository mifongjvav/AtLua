-- 滑动条：点击轨道跳转、按住拖动、方向键微调（需先点击获得焦点）。
--
--   local volume = At.Slider{
--       w = 220, min = 0, max = 100, step = 5, value = 40,
--       showValue = true,
--       onChange = function(value) print(value) end,
--   }

local Component = require("At.core.component")
local color = require("At.core.color")
local pixel = require("At.core.pixel")

local Slider = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = 200,
	h = 28,
	min = 0,
	max = 100,
	step = 1, -- 0 表示连续
	value = 0,
	trackColor = "@track",
	fillColor = "@primary",
	thumbColor = "@knob",
	trackHeight = 6,
	thumbRadius = 9,
	alpha = 255,
	showValue = false,
	valueColor = "@text",
	fontSize = nil,
	format = nil, -- function(value) -> string，覆盖默认格式化
	onChange = nil,
}

function Slider.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self._dragging = false
	self.value = self:_snap(tonumber(self.value) or 0)
	return self
end

-- ---------- 取值 ----------

function proto:_snap(value)
	local min, max = self.min, self.max
	if min > max then
		min, max = max, min
	end

	if value < min then
		value = min
	end
	if value > max then
		value = max
	end

	local step = self.step or 0
	if step > 0 then
		value = min + math.floor((value - min) / step + 0.5) * step
		if value > max then
			value = max
		end
	end

	-- 消掉浮点误差
	return math.floor(value * 1e6 + 0.5) / 1e6
end

function proto:getValue()
	return self.value
end

function proto:setValue(value, silent)
	local snapped = self:_snap(tonumber(value) or 0)
	if snapped == self.value then
		return self.value
	end
	self.value = snapped
	if not silent and self.onChange then
		self.onChange(snapped, self)
	end
	return self.value
end

function proto:_ratio()
	local span = self.max - self.min
	if span == 0 then
		return 0
	end
	local ratio = (self.value - self.min) / span
	if ratio < 0 then
		ratio = 0
	elseif ratio > 1 then
		ratio = 1
	end
	return ratio
end

function proto:_setFromX(mx)
	local r = self:rect()
	local usable = r.w - self.thumbRadius * 2
	if usable <= 0 then
		return
	end

	local ratio = (mx - (r.x + self.thumbRadius)) / usable
	if ratio < 0 then
		ratio = 0
	elseif ratio > 1 then
		ratio = 1
	end

	self:setValue(self.min + ratio * (self.max - self.min))
end

-- ---------- 交互 ----------

function proto:_press(mx)
	self:focus()
	self._dragging = true
	self:_setFromX(mx)
	return true
end

function proto:_release()
	self._dragging = false
	return true
end

function proto:_tick()
	if not self._dragging then
		return
	end
	if love.mouse.isDown(1) then
		local mx = love.mouse.getPosition()
		self:_setFromX(mx)
	else
		self._dragging = false
	end
end

function proto:keypressed(key)
	local step = self.step > 0 and self.step or (self.max - self.min) / 20
	if key == "left" or key == "down" then
		self:setValue(self.value - step)
		return true
	elseif key == "right" or key == "up" then
		self:setValue(self.value + step)
		return true
	end
	return false
end

-- ---------- 绘制 ----------

function proto:_formatValue()
	if self.format then
		return self.format(self.value)
	end
	if self.value == math.floor(self.value) then
		return string.format("%d", self.value)
	end
	return string.format("%.2f", self.value)
end

function proto:_draw()
	local r = self:rect()
	local x, y = pixel.xy(r.x, r.y)
	local cy = pixel.round(y + r.h / 2)
	local thumbR = self.thumbRadius
	local usable = r.w - thumbR * 2
	local ratio = self:_ratio()
	local trackH = self.trackHeight

	local trackY = pixel.round(cy - trackH / 2)

	color.setColor(self.trackColor, self.alpha)
	love.graphics.rectangle("fill", x + thumbR, trackY, usable, trackH, trackH / 2)

	color.setColor(self.fillColor, self.alpha)
	love.graphics.rectangle("fill", x + thumbR, trackY, usable * ratio, trackH, trackH / 2)

	color.setColor(self.thumbColor, self.alpha)
	local cx = pixel.round(x + thumbR + usable * ratio)
	love.graphics.rectangle("fill", cx - thumbR, cy - thumbR, thumbR * 2, thumbR * 2, thumbR)

	if self.showValue then
		local f = self:font()
		color.setColor(self.valueColor, self.alpha)
		love.graphics.setFont(f)
		love.graphics.print(self:_formatValue(), pixel.round(x + r.w + 8), pixel.round(cy - f:getHeight() / 2))
	end
end

setmetatable(Slider, {
	__call = function(_, opts)
		return Slider.new(opts)
	end,
})

return Slider
