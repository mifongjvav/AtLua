-- 多选框：方框 + 勾 + 右侧文字，点击整行切换。
--
--   local remember = At.Checkbox{ text = "记住我",
--       onChange = function(checked) print(checked) end }

local Component = require("At.core.component")
local color = require("At.core.color")
local pixel = require("At.core.pixel")

local Checkbox = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = "auto",
	h = "auto",
	size = 22,
	gap = 8,
	radius = 5,
	text = "",
	checked = false,
	color = "#3A4150",
	borderColor = "#6A7386",
	checkColor = "#9FB3D3",
	textColor = "#E8ECF2",
	alpha = 255,
	fontSize = nil,
	onChange = nil,
}

function Checkbox.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self.checked = self.checked and true or false
	return self
end

function proto:getValue()
	return self.checked
end

function proto:setValue(checked, silent)
	checked = checked and true or false
	if checked == self.checked then
		return self.checked
	end
	self.checked = checked
	if not silent and self.onChange then
		self.onChange(checked, self)
	end
	return self.checked
end

function proto:toggle()
	return self:setValue(not self.checked)
end

function proto:setText(text)
	self.text = text
	self:invalidateSize()
	return self
end

function proto:measure()
	local f = self:font()
	local label = tostring(self.text or "")
	local textW = label ~= "" and f:getWidth(label) or 0

	local w = self.size + (label ~= "" and (self.gap + textW) or 0)
	local h = math.max(self.size, f:getHeight())

	local declaredW, declaredH = self:declaredWidth(), self:declaredHeight()
	return (type(declaredW) == "number" and declaredW) or w, (type(declaredH) == "number" and declaredH) or h
end

function proto:_press()
	return true
end

function proto:_release(mx, my, inside)
	if inside then
		self:toggle()
	end
	return inside
end

function proto:_draw()
	local f = self:font()
	local r = self:rect()
	local box = pixel.round(self.size)
	local x, y = pixel.xy(r.x, r.y)
	local boxY = pixel.round(y + (r.h - box) / 2)

	color.setColor(self.color, self.alpha)
	love.graphics.rectangle("fill", x, boxY, box, box, self.radius)

	color.setColor(self.borderColor, self.alpha)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, boxY, box, box, self.radius)

	if self.checked then
		color.setColor(self.checkColor, self.alpha)
		love.graphics.setLineWidth(2)
		love.graphics.line(
			pixel.round(x + box * 0.24),
			pixel.round(boxY + box * 0.52),
			pixel.round(x + box * 0.44),
			pixel.round(boxY + box * 0.72),
			pixel.round(x + box * 0.78),
			pixel.round(boxY + box * 0.28)
		)
	end

	local label = tostring(self.text or "")
	if label ~= "" then
		color.setColor(self.textColor, self.alpha)
		love.graphics.setFont(f)
		love.graphics.print(label, x + box + self.gap, pixel.round(y + (r.h - f:getHeight()) / 2))
	end
end

setmetatable(Checkbox, {
	__call = function(_, opts)
		return Checkbox.new(opts)
	end,
})

return Checkbox
