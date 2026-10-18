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
local pixel = require("At.core.pixel")
local log = require("At.core.log")
local motion = require("At.core.motion")
local ScrollView = require("At.components.ScrollView")
local blur = require("At.effects.blur")

-- 日志内容：只负责把日志按行画出来，滚动/滚动条/触边光全部交给 At.ScrollView。
-- 它不是对外组件，autoRegister = false，也不会挡事件（没有 _press）。
local LogLines = {}
LogLines.__index = LogLines

function LogLines.new(console)
	local self = setmetatable({}, LogLines)
	self.console = console
	self.x, self.y, self.w, self.h = 0, 0, 1, 1
	self.visible = true
	self.autoRegister = false
	self.interactive = false
	return self
end

function LogLines:measure(availW)
	self.w = availW or self.w or 1
	local lineH = self.console:_lineHeight()
	local count = log.count()
	self.h = math.max(lineH, count * lineH)
	return self.w, self.h
end

function LogLines:draw()
	local console = self.console
	local total = log.count()
	local lineH = console:_lineHeight()
	local alpha = console._drawAlpha or console.alpha or 255
	local f = font.get(console.fontSize or 13)

	love.graphics.setFont(f)

	if total == 0 then
		color.setColor(console.placeholderColor, alpha)
		love.graphics.print("（暂无日志）", pixel.round(self.x), pixel.round(self.y))
		return
	end

	-- 只画视口内的行，日志很多时也不至于每帧画几百条
	local view = console._view
	local scroll = view and view.scrollY or 0
	local viewH = view and view.h or self.h
	local first = math.max(1, math.floor(scroll / lineH) + 1)
	local last = math.min(total, math.ceil((scroll + math.max(1, viewH)) / lineH))
	local entries = log.getEntries()

	for i = first, last do
		local entry = entries[i]
		if entry then
			local hex = console.levelColors[(entry.levelName or ""):lower()] or console.titleColor
			color.setColor(hex, alpha)
			love.graphics.print(log.formatEntry(entry), pixel.round(self.x), pixel.round(self.y + (i - 1) * lineH))
		end
	end
end

function LogLines:destroy()
	self._destroyed = true
end

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

	-- 开关动画：弹簧驱动 0→1，窗口淡入 + 下移，LOG 标签同步淡出
	animate = true,
	springStiffness = 320,
	springDamping = 26,
	openOffset = 12, -- 关闭时窗口向下偏移的像素（打开时滑回原位）

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

	self._windowDrag = nil
	self._open = motion.spring({
		value = self.visible and 1 or 0,
		stiffness = self.springStiffness,
		damping = self.springDamping,
	})

	-- 日志区复用 ScrollView：滚动条、平滑滚动、惯性、触边光效都不再单独实现
	self._lines = LogLines.new(self)
	self._view = ScrollView({
		x = 0,
		y = 0,
		w = 1,
		h = 1,
		content = self._lines,
		autoRegister = false, -- 由控制台手动转发事件，不参与全局注册表
		visible = false,
		scrollbar = true,
		drag = true,
		smooth = true,
		momentum = true,
		edgeEffect = true,
		scrollbarColor = self.scrollbarColor,
		scrollbarThumbColor = self.scrollbarThumbColor,
	})
	self._stick = true -- 是否跟随最新日志（用户往上翻后暂停跟随）
	self._lastMax = 0

	return self
end

-- ---------- 显示 / 隐藏 ----------

function proto:show()
	self.visible = true
	if self.animate == false and self._open then
		self._open:snap(1)
	end
	-- 重新打开时回到最新一条，和常见控制台行为一致
	self:scrollToBottom()
	return self
end

function proto:hide()
	self.visible = false
	self._windowDrag = nil
	self._stick = false
	if self.animate == false and self._open then
		self._open:snap(0)
	end
	return self
end

-- 0 = 完全关闭，1 = 完全打开；绘制与命中用它做插值
function proto:openAmount()
	return self._open and self._open.value or (self.visible and 1 or 0)
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
	self:scrollToBottom()
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

function proto:_drawTab(factor)
	factor = factor or 1
	if factor <= 0.01 then
		return
	end

	local r = self:_tabRect()
	local x, y = pixel.xy(r.x, r.y)
	local w, h = pixel.round(r.w), pixel.round(r.h)
	local a = math.floor((self.tabAlpha or 225) * factor)

	color.setColor(self.tabColor, a)
	love.graphics.rectangle("fill", x, y, w, h, self.tabRadius or 6)

	color.setColor(self.borderColor, math.floor(255 * factor))
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, y, w, h, self.tabRadius or 6)

	local f = font.get(self.fontSize or 13)
	love.graphics.setFont(f)
	color.setColor(self.tabTextColor, math.floor(255 * factor))
	local label = tostring(self.tabLabel or "LOG")
	love.graphics.print(label, pixel.round(x + (w - f:getWidth(label)) / 2), pixel.round(y + (h - f:getHeight()) / 2))
end

-- 打开时窗口淡入/上滑，关闭时反向；未完全打开时 LOG 标签按进度淡出。
-- 不直接复用 Component:draw：隐藏（visible=false）时仍要播完关闭动画。
function proto:draw()
	if self._destroyed then
		return
	end

	local open = self:openAmount()
	local showWindow = self.visible or open > 0.001

	local prevR, prevG, prevB, prevA = love.graphics.getColor()
	local prevFont = love.graphics.getFont()
	local prevLineWidth = love.graphics.getLineWidth()
	local prevLineStyle = love.graphics.getLineStyle()

	love.graphics.setLineStyle("rough")

	if showWindow then
		-- 关闭时往下滑一点再淡出；打开时从下方滑回，像抽屉。
		-- 这里临时挪 self.y 而不是 translate：scissor 是屏幕坐标，translate
		-- 会让日志区裁剪对不上窗口（动画期间上半截文字被切掉）。
		local dy = (1 - open) * (self.openOffset or 12)
		local originalY = self.y
		self.y = originalY + dy
		self:_draw(self.alpha * math.max(0, math.min(1, open)))
		self.y = originalY
	end

	-- 窗口还没完全打开时 LOG 标签淡出（完全打开后由窗口接管开关）
	local tabFactor = 1 - open
	if self.tab and tabFactor > 0.001 then
		self:_drawTab(math.min(1, tabFactor))
	end

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

-- 只更新内部 ScrollView 的矩形（事件/绘制前调用，保证命中和绘制位置一致）
function proto:_syncViewRect()
	local view = self._view
	if not view then
		return
	end
	local body = self:_bodyRect()
	view.x, view.y = body.x, body.y
	view.w, view.h = body.w, body.h
	view.visible = true
end

-- 更新内容尺寸、推进 ScrollView 的动画/拖拽，并处理“跟随最新日志”
function proto:_syncView(dt)
	local view = self._view
	if not view then
		return
	end

	self:_syncViewRect()
	view.alpha = self._drawAlpha or self.alpha or 255
	view.scrollbarColor = self.scrollbarColor
	view.scrollbarThumbColor = self.scrollbarThumbColor
	view.wheelStep = self:_lineHeight() * (self.scrollStep or 3)
	view.visible = self.visible or self:openAmount() > 0.001

	view:layout()
	if dt and view.visible then
		view:update(dt)
	end

	-- 先让 ScrollView 处理滚轮/拖动，再判断是否还在底部：
	-- 否则用户刚往上翻的第一帧会被"跟随最新"直接拽回去。
	if view.scrollY >= (self._lastMax or 0) - 1 then
		self._stick = true
	else
		self._stick = false
	end
	if self._stick then
		view:setScroll(view:maxScroll())
	end
	self._lastMax = view:maxScroll()
end

function proto:scrollToBottom()
	local view = self._view
	if not view then
		return self
	end
	self:_syncViewRect()
	view:layout()
	view:setScroll(view:maxScroll())
	self._stick = true
	self._lastMax = view:maxScroll()
	return self
end

-- ---------- 绘制 ----------

function proto:_draw(alpha)
	alpha = alpha or self.alpha
	local x, y = pixel.xy(self.x, self.y)
	local w, h = pixel.round(self.w), pixel.round(self.h)
	local radius = self.radius or 0

	-- 半透明窗口：先模糊背后的内容，再叠半透明底色
	-- 动画淡入到几乎透明时不做模糊（省一次全画布拷贝）
	if alpha >= 1 and alpha < 255 then
		blur.drawBackdrop(x, y, w, h, radius)
	end

	color.setColor(self.background, alpha)
	love.graphics.rectangle("fill", x, y, w, h, radius)

	color.setColor(self.borderColor, alpha)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, y, w, h, radius)

	local f = font.get(self.fontSize or 13)
	love.graphics.setFont(f)

	-- 标题
	local headerH = self.headerH or 30
	color.setColor(self.titleColor, alpha)
	love.graphics.print(self.title or "", x + 10, pixel.round(y + (headerH - f:getHeight()) / 2))

	-- 清空按钮
	if self.showClear then
		local clear = self:_clearRect()
		color.setColor(self.titleColor, math.floor(alpha * 150 / 255))
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
		color.setColor(self.titleColor, math.floor(alpha * 180 / 255))
		local closeW = f:getWidth("×")
		love.graphics.print(
			"×",
			pixel.round(close.x + (close.w - closeW) / 2),
			pixel.round(close.y + (close.h - f:getHeight()) / 2)
		)
	end

	-- 分隔线
	color.setColor(self.dividerColor, alpha)
	love.graphics.line(x + 1, y + headerH, x + w - 1, y + headerH)

	-- 日志区：内容、滚动条、平滑滚动、触边光效都复用 ScrollView
	self._drawAlpha = alpha
	self:_syncViewRect()
	local view = self._view
	if view then
		view.alpha = alpha
		view.visible = true
		view:draw()
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

	local view = self._view
	if view then
		self:_syncViewRect()
		view:layout()
		view:mousepressed(mx, my, button)
	end
	return true
end

function proto:mousereleased(mx, my, button)
	if button ~= nil and button ~= 1 then
		return false
	end
	local handled = self._windowDrag ~= nil
	self._windowDrag = nil
	if self._view then
		self:_syncViewRect()
		handled = self._view:mousereleased(mx, my, button) or handled
	end
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
	if not self._view then
		return false
	end
	self:_syncViewRect()
	self._view:layout()
	self._view:wheelmoved(dx, dy)
	-- 控制台是浮层：指针在窗口内时就吃掉滚轮，别让游戏背景跟着滚
	return true
end

function proto:update(dt)
	if self._destroyed then
		return
	end

	-- 关闭时 visible 已是 false，但窗口还要淡出，所以弹簧在 update 里独立推进
	local target = self.visible and 1 or 0
	self._open:setTarget(target)
	if self.animate == false then
		self._open:snap(target)
	else
		self._open:update(dt)
	end

	if self.visible then
		Component.update(self, dt)
	end

	if self.visible or self:openAmount() > 0.001 then
		self:_syncView(dt)
	end
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
end

function proto:destroy()
	if self._view then
		self._view:destroy()
		self._view = nil
	end
	self._lines = nil
	return Component.destroy(self)
end

setmetatable(Console, {
	__call = function(_, opts)
		return Console.new(opts)
	end,
})

return Console
