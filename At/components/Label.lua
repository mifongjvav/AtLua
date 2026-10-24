-- 文字标签：布局里最常用的占位/说明组件。
--
--   At.Label{ x = 20, y = 20, text = "用户名", fontSize = 16 }
--   At.Label{ text = "很长的说明……", wrap = true, w = 240, lineHeight = 1.4 }

local Component = require("At.core.component")
local color = require("At.core.color")
local layout = require("At.core.layout")
local pixel = require("At.core.pixel")

local Label = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = "auto",
	h = "auto",
	text = "",
	color = "@text",
	alpha = 255,
	align = "left", -- 相对自身宽度：left / center / right
	wrap = false, -- true 时需要给定宽度（数字或百分比）
	lineHeight = 1.2,
	interactive = false, -- 纯展示：不消费点击，不挡住容器拖动
}

function Label.new(opts)
	return Component.instantiate(proto, opts, DEFAULTS)
end

function proto:setText(text)
	self.text = text
	self:invalidateSize()
	return self
end

function proto:measure(availW)
	local f = self:font()
	local text = tostring(self.text or "")
	local lineH = f:getHeight() * (self.lineHeight or 1.2)

	if self.wrap then
		local limit = layout.pixels(self._specW, availW) or availW
		if limit and limit > 0 and f.getWrap then
			local _, lines = f:getWrap(text, limit)
			return limit, #lines * lineH
		end
	end

	return f:getWidth(text), lineH
end

function proto:_draw()
	local text = tostring(self.text or "")
	if text == "" then
		return
	end

	if self.fontSize then
		love.graphics.setFont(self:font())
	end

	color.setColor(self.color, self.alpha)

	local x, y = pixel.xy(self.x, self.y)

	if self.wrap then
		love.graphics.printf(text, x, y, pixel.round(self.w), self.align or "left")
		return
	end

	local f = love.graphics.getFont()
	local dx = 0
	if self.align == "center" then
		dx = pixel.round((self.w - f:getWidth(text)) / 2)
	elseif self.align == "right" then
		dx = pixel.round(self.w - f:getWidth(text))
	end

	love.graphics.print(text, x + dx, y)
end

setmetatable(Label, {
	__call = function(_, opts)
		return Label.new(opts)
	end,
})

return Label
