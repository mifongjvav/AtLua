-- 布局容器：CSS 式排列子组件，可选背景/描边/阴影做成卡片。
-- 容器本身不参与鼠标事件（passthrough），点击由子组件自己处理。
--
--   local card = At.Panel{
--       x = 40, y = 40, w = 360, h = "auto",
--       gap = 12, padding = 16, radius = 14,
--       background = "#242A34",
--       children = {
--           At.Label{ text = "登录" },
--           At.TextInput{ w = "100%" },
--           At.Button{ w = "100%", text = "确定" },
--       },
--   }

local Component = require("At.core.component")
local layout = require("At.core.layout")
local color = require("At.core.color")
local shadow = require("At.core.shadow")
local pixel = require("At.core.pixel")
local blur = require("At.effects.blur")

local Panel = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = "auto",
	h = "auto",
	direction = "column", -- column / row
	gap = 8,
	padding = 0, -- number 或 { left, top, right, bottom }
	align = "start", -- start / center / end / stretch
	justify = "start", -- start / center / end / space-between
	children = {},
	background = nil,
	borderColor = nil,
	borderWidth = 1,
	radius = 0,
	alpha = 255,
	shadow = false,
	shadowArgs = nil,
	autoRegister = false, -- 容器不接收事件
	passthrough = true,
}

function Panel.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)

	-- children 表不能与 DEFAULTS 共享引用
	local children = (opts and opts.children) or {}
	self.children = {}
	for i = 1, #children do
		self.children[i] = children[i]
	end

	if type(self.shadow) == "table" then
		self.shadowArgs = self.shadow
		self.shadow = true
	end
	if self.shadow and not self.shadowArgs then
		self.shadowArgs = { { 0, 0, 0, 0.2 }, 5, 20, 2, 3 }
	end

	return self
end

-- ---------- 子项管理 ----------

function proto:add(child)
	self.children[#self.children + 1] = child
	self:invalidateSize()
	return child
end

function proto:remove(child)
	for i = #self.children, 1, -1 do
		if self.children[i] == child then
			table.remove(self.children, i)
			self:invalidateSize()
			return true
		end
	end
	return false
end

function proto:clear()
	for i = #self.children, 1, -1 do
		self.children[i] = nil
	end
	self:invalidateSize()
end

-- ---------- 排版 ----------

function proto:measure(availW, availH)
	return layout.measure(self, availW, availH)
end

-- 立即重排一次；availW/availH 是父容器给出的可用空间（决定百分比尺寸）
function proto:layout(availW, availH)
	if availW ~= nil then
		self._availW = availW
	end
	if availH ~= nil then
		self._availH = availH
	end
	return layout.arrange(self, self._availW, self._availH)
end

-- ---------- 绘制 ----------

function proto:draw()
	if self._destroyed or not self.visible then
		return
	end

	local prevR, prevG, prevB, prevA = love.graphics.getColor()
	local prevFont = love.graphics.getFont()
	local prevLineWidth = love.graphics.getLineWidth()

	-- 先排版再画：容器尺寸与子项位置都由 layout 决定
	self:layout()
	self:_draw()

	for i = 1, #self.children do
		local child = self.children[i]
		if child.draw then
			child:draw()
		end
	end

	love.graphics.setLineWidth(prevLineWidth)
	love.graphics.setFont(prevFont)
	love.graphics.setColor(prevR, prevG, prevB, prevA)
end

function proto:_draw()
	local radius = self.radius or 0
	local x, y = pixel.xy(self.x, self.y)
	local w, h = pixel.round(self.w), pixel.round(self.h)

	if self.shadow then
		shadow.shadow(x, y, w, h, radius, unpack(self.shadowArgs))
	end

	if self.background then
		-- 半透明背景自动取背后的画面做模糊（At.blur 关闭时是空操作）
		if (self.alpha or 255) < 255 then
			blur.drawBackdrop(x, y, w, h, radius)
		end
		color.setColor(self.background, self.alpha)
		love.graphics.rectangle("fill", x, y, w, h, radius)
	end

	if self.borderColor then
		color.setColor(self.borderColor, self.alpha)
		love.graphics.setLineWidth(self.borderWidth or 1)
		love.graphics.rectangle("line", x, y, w, h, radius)
	end
end

function proto:_tick(dt)
	-- 容器自己不需要动画；子项由各自的 update 处理
end

function proto:destroy()
	for i = #self.children, 1, -1 do
		local child = self.children[i]
		if child.destroy then
			child:destroy()
		end
		self.children[i] = nil
	end
	return Component.destroy(self)
end

setmetatable(Panel, {
	__call = function(_, opts)
		return Panel.new(opts)
	end,
})

return Panel
