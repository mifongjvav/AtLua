-- Toast：一次性通知条，贴在窗口下方居中，自动关闭。
--
--   local toast = At.Toast{ text = "保存成功", level = "success", duration = 3 }
--   function love.draw()
--       -- 其他内容
--       toast:draw() -- 最后画，盖在内容上
--   end
--
-- 需要每帧调用 At.update(dt) 才会推进进出动画和倒计时；关闭后组件会
-- 自动从 registry 移除。同一时刻只建议显示一个 Toast。

local Component = require("At.core.component")
local color = require("At.core.color")
local motion = require("At.core.motion")
local pixel = require("At.core.pixel")
local shadow = require("At.core.shadow")

local Toast = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local LEVEL_COLORS = {
	info = "@primary",
	success = "@success",
	warning = "@warning",
	error = "@danger",
	critical = "@danger",
}

local DEFAULTS = {
	w = "auto",
	h = "auto",
	text = "",
	level = "info",
	duration = 3,
	margin = 24,
	maxWidth = 420,
	minWidth = 160,
	fontSize = 15,
	lineHeight = 1.25,
	paddingX = 16,
	paddingY = 12,
	radius = 12,
	background = "@surfaceStrong",
	borderColor = "@borderStrong",
	textColor = "@text",
	accentColor = nil, -- nil 时按 level 取
	shadow = true,
	shadowArgs = nil,
	alpha = 255,
	animate = true,
	springStiffness = 360,
	springDamping = 28,
	interactive = false, -- 不挡下面的点击
	onClose = nil,
}

function Toast.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self.text = tostring(self.text or "")
	self._open = motion.spring({
		value = self.animate == false and 1 or 0,
		stiffness = self.springStiffness,
		damping = self.springDamping,
	})
	self._elapsed = 0
	self._closing = false
	self._finished = false
	self._screenW = nil
	return self
end

function proto:setText(text)
	self.text = tostring(text or "")
	self._elapsed = 0
	self:invalidateSize()
	return self
end

function proto:isOpen()
	return not self._finished and not self._closing
end

function proto:close()
	if self._closing or self._finished then
		return self
	end
	self._closing = true
	if self.animate == false then
		self._open:snap(0)
		self:_finish()
	end
	return self
end

function proto:_finish()
	if self._finished then
		return
	end
	self._finished = true
	if self.onClose then
		self.onClose(self)
	end
	self:destroy()
end

function proto:measure()
	local f = self:font()
	local text = tostring(self.text or "")
	local screenW = love.graphics.getWidth and love.graphics.getWidth() or 0
	local maxW = math.min(self.maxWidth or 420, math.max(80, screenW - 2 * (self.margin or 24)))
	local indent = 14
	local textW = math.max(20, maxW - 2 * self.paddingX - indent)

	local _, lines = f:getWrap(text, textW)
	if not lines or #lines == 0 then
		lines = { text }
	end

	local contentW = 0
	for i = 1, #lines do
		contentW = math.max(contentW, f:getWidth(lines[i]))
	end

	local w = math.min(maxW, math.max(self.minWidth or 160, contentW + 2 * self.paddingX + indent))
	local lineH = f:getHeight() * (self.lineHeight or 1.25)
	local h = math.max(f:getHeight(), #lines * lineH) + 2 * self.paddingY

	self._lines = lines
	self._lineHeightPx = lineH
	self._textX = self.paddingX + indent
	return pixel.round(w), pixel.round(h)
end

function proto:_tick(dt)
	local screenW = love.graphics.getWidth and love.graphics.getWidth() or 0
	if self._screenW ~= screenW then
		self._screenW = screenW
		self:invalidateSize()
	end

	local target = self._closing and 0 or 1
	self._open:setTarget(target)
	if self.animate == false then
		self._open:snap(target)
	else
		self._open:update(dt)
	end

	if self._closing then
		if self._open.value <= 0.01 then
			self:_finish()
		end
		return
	end

	self._elapsed = self._elapsed + dt
	if self.duration and self._elapsed >= self.duration then
		self:close()
	end
end

function proto:_draw()
	local open = math.min(1, math.max(0, self._open.value))
	if open <= 0 then
		return
	end

	local screenW, screenH = love.graphics.getDimensions()
	local w, h = self.w, self.h
	local x = math.max(0, math.floor((screenW - w) / 2))
	local y = math.max(0, screenH - h - self.margin + (1 - open) * 8)
	local alpha = math.floor((self.alpha or 255) * open)

	if self.shadow then
		if self.shadowArgs then
			shadow.shadow(x, y, w, h, self.radius, unpack(self.shadowArgs))
		else
			shadow.shadow(x, y, w, h, self.radius, { 0, 0, 0, 0.35 * open })
		end
	end

	color.setColor(self.background, alpha)
	love.graphics.rectangle("fill", x, y, w, h, self.radius)

	color.setColor(self.borderColor, alpha)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, y, w, h, self.radius)

	local accent = self.accentColor or LEVEL_COLORS[(self.level or "info"):lower()] or "@primary"
	color.setColor(accent, alpha)
	love.graphics.circle("fill", x + self.paddingX + 3, y + h / 2, 4)

	local f = self:font()
	love.graphics.setFont(f)
	local lines = self._lines or { tostring(self.text or "") }
	local lineH = self._lineHeightPx or f:getHeight() * (self.lineHeight or 1.25)
	local textX = x + (self._textX or self.paddingX + 14)
	local textY = y + self.paddingY

	color.setColor(self.textColor, alpha)
	for i = 1, #lines do
		love.graphics.print(lines[i], pixel.round(textX), pixel.round(textY + (i - 1) * lineH))
	end
end

setmetatable(Toast, {
	__call = function(_, opts)
		return Toast.new(opts)
	end,
})

return Toast
