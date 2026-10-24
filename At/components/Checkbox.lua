-- 多选框：方框 + 勾 + 右侧文字，点击整行切换。
--
--   local remember = At.Checkbox{ text = "记住我",
--       onChange = function(checked) print(checked) end }

local Component = require("At.core.component")
local color = require("At.core.color")
local pixel = require("At.core.pixel")
local motion = require("At.core.motion")
local shadow = require("At.core.shadow")

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
	color = "@surfaceAlt",
	borderColor = "@borderStrong",
	checkColor = "@primary",
	textColor = "@text",
	innerShadow = true,
	innerShadowColor = "@primaryDark",
	innerShadowAlpha = 0.16,
	innerShadowSize = 3,
	innerShadowOffsetX = 0,
	innerShadowOffsetY = 0,
	alpha = 255,
	fontSize = nil,

	-- 勾的弹入动画（0→1，带一点过冲）
	animate = true,
	springStiffness = 420,
	springDamping = 22,

	onChange = nil,
}

function Checkbox.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self.checked = self.checked and true or false
	self._pop = motion.spring({
		value = self.checked and 1 or 0,
		stiffness = self.springStiffness,
		damping = self.springDamping,
	})
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

function proto:_tick(dt)
	local target = self.checked and 1 or 0
	self._pop:setTarget(target)
	if self.animate == false then
		self._pop:snap(target)
	else
		self._pop:update(dt)
	end
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

	if self.innerShadow ~= false then
		shadow.inner(
			x,
			boxY,
			box,
			box,
			self.radius,
			self.innerShadowColor,
			(self.innerShadowAlpha or 0.16) * (self.alpha or 255) / 255,
			self.innerShadowSize,
			self.innerShadowOffsetX,
			self.innerShadowOffsetY
		)
	end

	color.setColor(self.borderColor, self.alpha)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, boxY, box, box, self.radius)

	-- 勾从中心缩放弹入：pop 0 = 不可见，1 = 完整大小
	local pop = self.animate == false and (self.checked and 1 or 0) or (self._pop and self._pop.value or 0)
	if self.checked or pop > 0.01 then
		local t = math.min(1, math.max(0, pop))
		local scale = 0.55 + 0.45 * t
		local cx, cy = x + box / 2, boxY + box / 2
		local function pt(fx, fy)
			return pixel.round(cx + (fx - 0.5) * box * scale), pixel.round(cy + (fy - 0.5) * box * scale)
		end
		color.setColor(self.checkColor, math.floor((self.alpha or 255) * t))
		love.graphics.setLineWidth(2)
		local ax, ay = pt(0.24, 0.52)
		local bx, by = pt(0.44, 0.72)
		local dx, dy = pt(0.78, 0.28)
		love.graphics.line(ax, ay, bx, by, dx, dy)
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
