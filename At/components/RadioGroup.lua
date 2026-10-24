-- 单选组：一组选项里同时只有一个选中，value 为 1 基下标。
--
--   local size = At.RadioGroup{
--       options = { "小", "中", "大" }, value = 2,
--       onChange = function(index, label) print(index, label) end,
--   }

local Component = require("At.core.component")
local color = require("At.core.color")
local pixel = require("At.core.pixel")
local motion = require("At.core.motion")

local RadioGroup = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = "auto",
	h = "auto",
	options = {},
	value = nil, -- 1 基下标；nil = 未选中
	direction = "column", -- column / row
	gap = 8,
	size = 20,
	textGap = 8,
	color = "@surfaceAlt",
	borderColor = "@borderStrong",
	selectedColor = "@primary",
	textColor = "@text",
	alpha = 255,
	fontSize = nil,

	-- 选中圆点的弹入动画
	animate = true,
	springStiffness = 420,
	springDamping = 22,

	onChange = nil,
}

function RadioGroup.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self.options = self.options or {}
	self._pops = {} -- 每个选项一个弹簧：切换时旧的点缩回、新的点弹出
	return self
end

function proto:getValue()
	return self.value
end

function proto:getLabel()
	if self.value and self.options[self.value] then
		return self.options[self.value]
	end
	return nil
end

function proto:setValue(index, silent)
	if index == self.value then
		return self.value
	end
	self.value = index
	if not silent and self.onChange then
		self.onChange(index, self.options[index], self)
	end
	return self.value
end

function proto:_itemHeight()
	return math.max(self.size, self:font():getHeight())
end

-- 每个选项的矩形（用于绘制与命中）
function proto:_items()
	local f = self:font()
	local itemH = self:_itemHeight()
	local items = {}
	local offset = 0
	local row = (self.direction or "column") == "row"
	local itemW = self:_itemWidth()

	for i = 1, #self.options do
		local x, y, w, h
		if row then
			x, y, w, h = self.x + offset, self.y, itemW, itemH
			offset = offset + itemW + self.gap
		else
			x, y, w, h = self.x, self.y + offset, itemW, itemH
			offset = offset + itemH + self.gap
		end
		items[i] = { index = i, label = self.options[i], x = x, y = y, w = w, h = h, font = f }
	end

	return items
end

function proto:_itemWidth()
	local f = self:font()
	local maxTextW = 0
	for i = 1, #self.options do
		local textW = f:getWidth(tostring(self.options[i]))
		if textW > maxTextW then
			maxTextW = textW
		end
	end
	return self.size + self.textGap + maxTextW
end

function proto:measure()
	local f = self:font()
	local itemH = math.max(self.size, f:getHeight())
	local itemW = self:_itemWidth()
	local n = #self.options
	local gaps = n > 1 and (n - 1) * self.gap or 0

	local w, h
	if (self.direction or "column") == "row" then
		w = n * itemW + gaps
		h = itemH
	else
		w = itemW
		h = n * itemH + gaps
	end

	local declaredW, declaredH = self:declaredWidth(), self:declaredHeight()
	return (type(declaredW) == "number" and declaredW) or w, (type(declaredH) == "number" and declaredH) or h
end

function proto:_itemAt(mx, my)
	local items = self:_items()
	for i = 1, #items do
		local it = items[i]
		if mx >= it.x and mx <= it.x + it.w and my >= it.y and my <= it.y + it.h then
			return i
		end
	end
	return nil
end

function proto:_tick(dt)
	for i = 1, #self.options do
		local pop = self._pops[i]
		if not pop then
			pop = motion.spring({
				value = self.value == i and 1 or 0,
				stiffness = self.springStiffness,
				damping = self.springDamping,
			})
			self._pops[i] = pop
		end
		local target = self.value == i and 1 or 0
		pop:setTarget(target)
		if self.animate == false then
			pop:snap(target)
		else
			pop:update(dt)
		end
	end
end

function proto:_press()
	return true
end

function proto:_release(mx, my, inside)
	if not inside then
		return false
	end
	local index = self:_itemAt(mx, my)
	if index then
		self:setValue(index)
	end
	return index ~= nil
end

function proto:_draw()
	local items = self:_items()

	for i = 1, #items do
		local it = items[i]
		local radius = self.size / 2
		local cx = pixel.round(it.x + radius)
		local cy = pixel.round(it.y + it.h / 2)
		local selected = self.value == it.index

		color.setColor(self.color, self.alpha)
		love.graphics.circle("fill", cx, cy, radius)

		color.setColor(selected and self.selectedColor or self.borderColor, self.alpha)
		love.graphics.setLineWidth(selected and 2 or 1)
		love.graphics.circle("line", cx, cy, radius)

		local pop
		if self.animate == false then
			pop = selected and 1 or 0
		else
			pop = self._pops[i] and self._pops[i].value or 0
		end
		if selected or pop > 0.01 then
			local t = math.min(1, math.max(0, pop))
			color.setColor(self.selectedColor, math.floor((self.alpha or 255) * t))
			love.graphics.circle("fill", cx, cy, radius * (0.18 + 0.27 * t))
		end

		color.setColor(self.textColor, self.alpha)
		love.graphics.setFont(it.font)
		love.graphics.print(
			tostring(it.label),
			pixel.round(it.x + self.size + self.textGap),
			pixel.round(it.y + (it.h - it.font:getHeight()) / 2)
		)
	end
end

setmetatable(RadioGroup, {
	__call = function(_, opts)
		return RadioGroup.new(opts)
	end,
})

return RadioGroup
