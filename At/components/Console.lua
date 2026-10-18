-- 浮动控制台：显示 At.log 的全部日志，按等级着色，可拖动、可滚动、可显示/隐藏。
--
--   local console = At.Console{ x = 20, y = 20, w = 560, h = 240 }
--   console:toggle()          -- 或 show() / hide()
--   -- love.draw: console:draw()   （放在最后画，才能浮在最上层）
--
-- 日志本身由 At.log 收集（等级过滤、格式都在那边），控制台只负责显示。

local Component = require("At.core.component")
local color = require("At.core.color")
local font = require("At.core.font")
local clip = require("At.core.clip")
local pixel = require("At.core.pixel")
local log = require("At.core.log")
local blur = require("At.effects.blur")

local Console = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = 560,
	h = 240,
	headerH = 30,
	padding = 8,
	radius = 8,

	visible = false, -- 默认隐藏，用 toggle()/show() 打开
	draggable = true,
	showClose = true,
	showClear = true, -- 标题栏的 C（清空）按钮，移动端没有 F2 也能清空
	title = "控制台",

	fontSize = 13,
	lineHeight = 1.35,
	scrollStep = 3, -- 滚轮一格滚几行

	background = "#0D1117",
	alpha = 205, -- 半透明背景
	borderColor = "#3A4150",
	titleColor = "#DCE3EE",
	placeholderColor = "#6B7385",
	dividerColor = "#2A303B",
	scrollbarColor = "#2F3542",
	scrollbarThumbColor = "#59627A",

	-- 隐藏时显示的可点按标签（移动端没有 F1，用这个开关控制台）
	tab = true,
	tabW = 72,
	tabH = 28,
	tabMargin = 12,
	tabRadius = 6,
	tabLabel = "LOG",
	tabColor = "#1F2530",
	tabTextColor = "#A9C7E8",
	tabAlpha = 225,
	tabX = nil, -- 缺省贴屏幕右上角
	tabY = nil,

	levelColors = {
		debug = "#7D8698",
		info = "#A9C7E8",
		warn = "#E8C07F",
		error = "#E87979",
		fatal = "#FF5555",
	},
}

function Console.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)

	-- levelColors 不能与 DEFAULTS 共享引用（否则一处改动影响所有控制台）
	self.levelColors = {}
	local source = (opts and opts.levelColors) or DEFAULTS.levelColors
	for name, hex in pairs(source) do
		self.levelColors[name] = hex
	end

	self._offset = 0 -- 从末尾往前滚了多少行：0 = 跟随最新
	self._windowDrag = nil
	self._contentDrag = nil

	return self
end

-- ---------- 显示 / 隐藏 ----------

function proto:show()
	self.visible = true
	return self
end

function proto:hide()
	self.visible = false
	self._windowDrag = nil
	self._contentDrag = nil
	return self
end

function proto:toggle()
	if self.visible then
		return self:hide()
	end
	return self:show()
end

function proto:isOpen()
	return self.visible
end

function proto:setTitle(title)
	self.title = tostring(title or "")
	return self
end

-- 清空日志缓冲（日志由 At.log 持有）
function proto:clear()
	log.clear()
	self._offset = 0
	return self
end

-- ---------- 布局辅助 ----------

function proto:_lineHeight()
	return font.get(self.fontSize or 13):getHeight() * (self.lineHeight or 1.35)
end

function proto:_bodyRect()
	local pad = self.padding or 8
	return {
		x = self.x + pad,
		y = self.y + (self.headerH or 30) + 2,
		w = math.max(10, self.w - pad * 2 - 8),
		h = math.max(1, self.h - (self.headerH or 30) - 4),
	}
end

function proto:_clearRect()
	local headerH = self.headerH or 30
	return {
		x = self.x + self.w - headerH * 2,
		y = self.y,
		w = headerH,
		h = headerH,
	}
end

function proto:_tabRect()
	local w = self.tabW or 72
	local h = self.tabH or 28
	local margin = self.tabMargin or 12
	local screenW = (love.graphics.getWidth and love.graphics.getWidth()) or 800
	return {
		x = self.tabX or (screenW - w - margin),
		y = self.tabY or margin,
		w = w,
		h = h,
	}
end

function proto:_drawTab()
	local r = self:_tabRect()
	local x, y = pixel.xy(r.x, r.y)
	local w, h = pixel.round(r.w), pixel.round(r.h)

	color.setColor(self.tabColor, self.tabAlpha or 225)
	love.graphics.rectangle("fill", x, y, w, h, self.tabRadius or 6)

	color.setColor(self.borderColor, 255)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, y, w, h, self.tabRadius or 6)

	local f = font.get(self.fontSize or 13)
	love.graphics.setFont(f)
	color.setColor(self.tabTextColor, 255)
	local label = tostring(self.tabLabel or "LOG")
	love.graphics.print(label, pixel.round(x + (w - f:getWidth(label)) / 2), pixel.round(y + (h - f:getHeight()) / 2))
end

-- 隐藏时只画 LOG 标签；显示时交给 Component:draw 走完整绘制
function proto:draw()
	if self._destroyed then
		return
	end

	if self.visible then
		Component.draw(self)
		return
	end

	if not self.tab then
		return
	end

	local prevR, prevG, prevB, prevA = love.graphics.getColor()
	local prevFont = love.graphics.getFont()
	local prevLineWidth = love.graphics.getLineWidth()
	local prevLineStyle = love.graphics.getLineStyle()

	love.graphics.setLineStyle("rough")
	self:_drawTab()

	love.graphics.setLineStyle(prevLineStyle)
	love.graphics.setLineWidth(prevLineWidth)
	love.graphics.setFont(prevFont)
	love.graphics.setColor(prevR, prevG, prevB, prevA)
end

function proto:_closeRect()
	local headerH = self.headerH or 30
	return {
		x = self.x + self.w - headerH,
		y = self.y,
		w = headerH,
		h = headerH,
	}
end

function proto:_visibleLines()
	local body = self:_bodyRect()
	return math.max(1, math.floor(body.h / self:_lineHeight()))
end

function proto:_maxOffset()
	return math.max(0, log.count() - self:_visibleLines())
end

function proto:_scrollLines(delta)
	self._offset = math.max(0, math.min(self:_maxOffset(), (self._offset or 0) + delta))
	return self._offset
end

function proto:scrollToBottom()
	self._offset = 0
	return self
end

-- ---------- 绘制 ----------

function proto:_draw()
	local x, y = pixel.xy(self.x, self.y)
	local w, h = pixel.round(self.w), pixel.round(self.h)
	local radius = self.radius or 0

	-- 半透明窗口：先模糊背后的内容，再叠半透明底色
	if (self.alpha or 255) < 255 then
		blur.drawBackdrop(x, y, w, h, radius)
	end

	color.setColor(self.background, self.alpha)
	love.graphics.rectangle("fill", x, y, w, h, radius)

	color.setColor(self.borderColor, 255)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, y, w, h, radius)

	local f = font.get(self.fontSize or 13)
	love.graphics.setFont(f)

	-- 标题
	local headerH = self.headerH or 30
	color.setColor(self.titleColor, 255)
	love.graphics.print(self.title or "", x + 10, pixel.round(y + (headerH - f:getHeight()) / 2))

	-- 清空按钮
	if self.showClear then
		local clear = self:_clearRect()
		color.setColor(self.titleColor, 150)
		local clearW = f:getWidth("C")
		love.graphics.print(
			"C",
			pixel.round(clear.x + (clear.w - clearW) / 2),
			pixel.round(clear.y + (clear.h - f:getHeight()) / 2)
		)
	end

	-- 关闭按钮
	if self.showClose then
		local close = self:_closeRect()
		color.setColor(self.titleColor, 180)
		local closeW = f:getWidth("×")
		love.graphics.print(
			"×",
			pixel.round(close.x + (close.w - closeW) / 2),
			pixel.round(close.y + (close.h - f:getHeight()) / 2)
		)
	end

	-- 分隔线
	color.setColor(self.dividerColor, 255)
	love.graphics.line(x + 1, y + headerH, x + w - 1, y + headerH)

	-- 日志区
	local body = self:_bodyRect()
	local entries = log.getEntries()
	local total = #entries
	local lineH = self:_lineHeight()

	-- 拖动滚动时 offset 可能是小数（delta / 行高）；绘制前对齐到整行，
	-- 否则会拿 2.6 这样的值当下标去取 entries[i]，得到 nil。
	local maxOffset = self:_maxOffset()
	local offset = math.max(0, math.min(maxOffset, math.floor((self._offset or 0) + 0.5)))
	self._offset = offset

	local old, visible = clip.apply(pixel.round(body.x), pixel.round(body.y), pixel.round(body.w), pixel.round(body.h))

	if visible then
		if total == 0 then
			color.setColor(self.placeholderColor, 255)
			love.graphics.print("（暂无日志）", body.x, body.y)
		else
			local visibleLines = self:_visibleLines()
			local lastIndex = math.max(1, total - offset)
			local firstIndex = math.max(1, lastIndex - visibleLines + 1)

			local lineY = pixel.round(body.y)
			for i = firstIndex, lastIndex do
				local entry = entries[i]
				if entry then
					local hex = self.levelColors[(entry.levelName or ""):lower()] or self.titleColor
					color.setColor(hex, 255)
					love.graphics.print(log.formatEntry(entry), pixel.round(body.x), lineY)
					lineY = lineY + lineH
				end
			end
		end
	end
	clip.restore(old)

	-- 滚动条（内容超出时）
	local visibleLines = self:_visibleLines()
	if total > visibleLines then
		local trackX = x + w - 6
		local trackY = body.y
		local trackH = body.h
		local thumbH = math.max(18, trackH * visibleLines / total)
		local barMaxOffset = math.max(1, total - visibleLines)
		local t = (barMaxOffset - offset) / barMaxOffset
		local thumbY = trackY + (trackH - thumbH) * t

		color.setColor(self.scrollbarColor, 160)
		love.graphics.rectangle("fill", trackX, trackY, 3, trackH, 1.5)
		color.setColor(self.scrollbarThumbColor, 220)
		love.graphics.rectangle("fill", trackX, thumbY, 3, thumbH, 1.5)
	end
end

-- ---------- 交互 ----------

function proto:mousepressed(mx, my, button)
	if not self.enabled then
		return false
	end
	if button ~= nil and button ~= 1 then
		return false
	end

	-- 隐藏状态：只有右上角 LOG 标签可点，点开控制台
	if not self.visible then
		if self.tab then
			local r = self:_tabRect()
			if mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h then
				self:show()
				return true
			end
		end
		return false
	end

	if not self:contains(mx, my) then
		return false
	end

	local clear = self:_clearRect()
	if self.showClear and mx >= clear.x and mx <= clear.x + clear.w and my >= clear.y and my <= clear.y + clear.h then
		self:clear()
		return true
	end

	local close = self:_closeRect()
	if self.showClose and mx >= close.x and mx <= close.x + close.w and my >= close.y and my <= close.y + close.h then
		self:hide()
		return true
	end

	if self.draggable and my <= self.y + (self.headerH or 30) then
		self._windowDrag = { dx = mx - self.x, dy = my - self.y }
		return true
	end

	self._contentDrag = { lastY = my }
	return true
end

function proto:mousereleased(mx, my, button)
	if button ~= nil and button ~= 1 then
		return false
	end
	local handled = self._windowDrag ~= nil or self._contentDrag ~= nil
	self._windowDrag = nil
	self._contentDrag = nil
	return handled
end

function proto:wheelmoved(dx, dy)
	if not self.visible or not self.enabled then
		return false
	end
	local mx, my = love.mouse.getPosition()
	if not self:contains(mx, my) then
		return false
	end
	-- 滚轮向上（dy > 0）看更早的日志
	self:_scrollLines((dy or 0) * (self.scrollStep or 3))
	return true
end

function proto:_tick()
	if self._windowDrag then
		if love.mouse.isDown(1) then
			local mx, my = love.mouse.getPosition()
			local screenW, screenH = love.graphics.getDimensions()
			self.x = math.max(0, math.min(screenW - self.w, mx - self._windowDrag.dx))
			self.y = math.max(0, math.min(screenH - self.h, my - self._windowDrag.dy))
		else
			self._windowDrag = nil
		end
	end

	if self._contentDrag then
		if love.mouse.isDown(1) then
			local _, my = love.mouse.getPosition()
			local delta = my - self._contentDrag.lastY
			self._contentDrag.lastY = my
			self:_scrollLines(delta / self:_lineHeight())
		else
			self._contentDrag = nil
		end
	end
end

setmetatable(Console, {
	__call = function(_, opts)
		return Console.new(opts)
	end,
})

return Console
