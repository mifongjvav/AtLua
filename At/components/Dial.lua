-- 圆形旋钮（QDial 风格）：点击/拖动圆盘改变值，支持 wrapping。
--
--   local dial = At.Dial{
--       w = 120, h = 120,
--       min = 0, max = 100, step = 1, value = 40,
--       wrapping = true,
--       onChange = function(value) print(value) end,
--   }
--
-- 角度单位是度，0° 在右侧、顺时针为正。非 wrapping 时默认从 135°（左下）
-- 扫到 405°（右下），即 270° 圆弧，底部留出缺口；wrapping = true 时使用
-- 完整 360°，endAngle 不再参与映射，0 与最大值在 startAngle 处相接。
--
-- 拖动在 _tick 里轮询鼠标，和 Slider 一样需要每帧调用 At.update(dt)。

local Component = require("At.core.component")
local color = require("At.core.color")
local pixel = require("At.core.pixel")
local theme = require("At.core.theme")

-- LuaJIT 用 math.atan2，Lua 5.3+ 用 math.atan(y, x)
local atan2 = math.atan2 or function(y, x)
	return math.atan(y, x)
end

local Dial = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = 120,
	h = 120,

	min = 0,
	max = 100,
	step = 1, -- 0 = 连续
	pageStep = 10,
	value = 0,

	-- true 时用完整 360° 圆环，值可以越过 max/min 绕回
	wrapping = false,

	-- 非 wrapping 时的可见圆弧；wrapping 时只用 startAngle
	startAngle = 135,
	endAngle = 405,

	trackWidth = 8,
	trackColor = "@track",
	fillColor = "@primary",
	knobColor = "@knob",
	knobBorderColor = "@borderStrong",
	pointerColor = "@primary",
	focusColor = "@primary",

	notchCount = 0, -- 0 = 不画刻度
	notchColor = "@borderStrong",
	notchWidth = 2,
	notchLength = 6,

	alpha = 255,
	showValue = false,
	valueColor = nil, -- nil = 按旋钮底色自动取黑/白
	fontSize = nil,
	format = nil, -- function(value) -> string
	onChange = nil,
}

function Dial.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self._dragging = false
	self.value = self:_snap(self.value)
	return self
end

-- ---------- 取值 ----------

function proto:_range()
	local min = tonumber(self.min) or 0
	local max = tonumber(self.max) or 100
	if min > max then
		min, max = max, min
	end
	return min, max
end

-- wrapping 时越界值按范围取模；非 wrapping 时夹紧
function proto:_snap(value)
	local min, max = self:_range()
	value = tonumber(value) or min

	local span = max - min
	if span <= 0 then
		return min
	end

	if self.wrapping then
		if value < min or value > max then
			value = min + ((value - min) % span)
		end
	else
		value = math.max(min, math.min(max, value))
	end

	local step = tonumber(self.step) or 0
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
	local snapped = self:_snap(value)
	if snapped == self.value then
		return self.value
	end
	self.value = snapped
	if not silent and self.onChange then
		self.onChange(snapped, self)
	end
	return self.value
end

function proto:getRatio()
	local min, max = self:_range()
	if max == min then
		return 0
	end
	local ratio = (self.value - min) / (max - min)
	return math.max(0, math.min(1, ratio))
end

function proto:setWrapping(enabled)
	self.wrapping = enabled and true or false
	return self
end

function proto:isWrapping()
	return self.wrapping and true or false
end

-- 非 wrapping 时圆弧跨度；wrapping 时固定完整一圈
function proto:_sweep()
	if self.wrapping then
		return 360
	end
	local sweep = ((tonumber(self.endAngle) or 405) - (tonumber(self.startAngle) or 135)) % 360
	if sweep <= 0 then
		sweep = 360
	end
	return sweep
end

-- 鼠标点对应的值；缺口里选最近的一端
function proto:_setFromPoint(mx, my)
	local r = self:rect()
	local cx = r.x + r.w / 2
	local cy = r.y + r.h / 2
	local dx = mx - cx
	local dy = my - cy

	-- 正中心角度没有意义，别让一次误点跳值
	if dx * dx + dy * dy < 4 then
		return
	end

	local angle = math.deg(atan2(dy, dx))
	local rel = (angle - (tonumber(self.startAngle) or 135)) % 360
	local sweep = self:_sweep()
	local ratio

	if rel <= sweep then
		ratio = rel / sweep
	else
		-- 非 wrapping 的底部缺口：吸附到更近的端点
		local toEnd = rel - sweep
		local toStart = 360 - rel
		ratio = toEnd < toStart and 1 or 0
	end

	local min, max = self:_range()
	self:setValue(min + ratio * (max - min))
end

-- ---------- 交互 ----------

function proto:_press(mx, my)
	self._dragging = true
	self:_setFromPoint(mx, my)
	self:focus()
	return true
end

function proto:_release(mx, my, inside)
	if self._dragging and inside then
		self:_setFromPoint(mx, my)
	end
	self._dragging = false
	return true
end

function proto:_tick()
	if not self._dragging then
		return
	end
	if love.mouse.isDown(1) then
		local mx, my = love.mouse.getPosition()
		self:_setFromPoint(mx, my)
	else
		self._dragging = false
	end
end

function proto:_stepBy(delta)
	self:setValue(self.value + delta)
end

function proto:_singleStep()
	local min, max = self:_range()
	local step = tonumber(self.step) or 0
	if step <= 0 then
		step = (max - min) / 20
	end
	return step
end

function proto:keypressed(key)
	local min, max = self:_range()
	local step = self:_singleStep()
	if step <= 0 then
		return false
	end

	if key == "left" or key == "down" then
		self:_stepBy(-step)
		return true
	elseif key == "right" or key == "up" then
		self:_stepBy(step)
		return true
	elseif key == "pagedown" then
		self:_stepBy(-(tonumber(self.pageStep) or step * 10))
		return true
	elseif key == "pageup" then
		self:_stepBy(tonumber(self.pageStep) or step * 10)
		return true
	elseif key == "home" then
		self:setValue(min)
		return true
	elseif key == "end" then
		self:setValue(max)
		return true
	end
	return false
end

-- ---------- 尺寸与绘制 ----------

function proto:measure()
	local declaredW, declaredH = self:declaredWidth(), self:declaredHeight()
	local w = type(declaredW) == "number" and declaredW or (type(declaredH) == "number" and declaredH or 120)
	local h = type(declaredH) == "number" and declaredH or w
	return w, h
end

function proto:_formatValue()
	if self.format then
		return self.format(self.value)
	end
	if self.value == math.floor(self.value) then
		return string.format("%d", self.value)
	end
	return string.format("%.2f", self.value)
end

local function arcPoints(cx, cy, radius, a1, a2, segments)
	local points = {}
	for i = 0, segments do
		local a = a1 + (a2 - a1) * (i / segments)
		points[#points + 1] = cx + math.cos(a) * radius
		points[#points + 1] = cy + math.sin(a) * radius
	end
	return points
end

local function cap(cx, cy, radius, angle, width)
	love.graphics.circle("fill", cx + math.cos(angle) * radius, cy + math.sin(angle) * radius, width / 2)
end

function proto:_draw()
	local r = self:rect()
	local x, y = pixel.xy(r.x, r.y)
	local w, h = pixel.round(r.w), pixel.round(r.h)
	local size = math.min(w, h)
	local cx, cy = pixel.round(x + w / 2), pixel.round(y + h / 2)

	local notches = math.max(0, math.floor(tonumber(self.notchCount) or 0))
	local margin = notches > 0 and 12 or 6
	local radius = math.max(6, size / 2 - margin)
	local ringW = math.max(1, math.min(tonumber(self.trackWidth) or 8, radius * 0.5))

	local start = math.rad(tonumber(self.startAngle) or 135)
	local sweep = self:_sweep()
	local sweepRad = math.rad(sweep)
	local ratio = self:getRatio()
	local pointer = start + sweepRad * ratio
	local segments = math.max(16, math.ceil(64 * sweep / 360))

	love.graphics.setLineStyle("smooth")
	love.graphics.setLineWidth(ringW)

	-- 刻度画在圆环外侧
	if notches > 0 then
		local notchW = math.max(1, tonumber(self.notchWidth) or 2)
		local notchLen = math.max(1, tonumber(self.notchLength) or 6)
		local inner = radius + ringW / 2 + 2
		local outer = math.min(size / 2 - 2, inner + notchLen)

		love.graphics.setLineWidth(notchW)
		color.setColor(self.notchColor, self.alpha)
		for i = 0, notches - 1 do
			local t
			if sweep >= 360 - 1e-4 then
				t = i / notches
			elseif notches > 1 then
				t = i / (notches - 1)
			else
				t = 0
			end
			local a = start + sweepRad * t
			local cosA, sinA = math.cos(a), math.sin(a)
			love.graphics.line(cx + cosA * inner, cy + sinA * inner, cx + cosA * outer, cy + sinA * outer)
		end
		love.graphics.setLineWidth(ringW)
	end

	-- 轨道
	color.setColor(self.trackColor, self.alpha)
	if sweep >= 360 - 1e-4 then
		love.graphics.circle("line", cx, cy, radius, segments)
	else
		love.graphics.line(arcPoints(cx, cy, radius, start, start + sweepRad, segments))
		cap(cx, cy, radius, start, ringW)
		cap(cx, cy, radius, start + sweepRad, ringW)
	end

	-- 已填充的圆弧
	if ratio > 0 then
		color.setColor(self.fillColor, self.alpha)
		local fillRad = sweepRad * ratio
		if fillRad >= math.pi * 2 - 1e-4 then
			love.graphics.circle("line", cx, cy, radius, segments)
		else
			love.graphics.line(arcPoints(cx, cy, radius, start, start + fillRad, segments))
			cap(cx, cy, radius, start, ringW)
			cap(cx, cy, radius, pointer, ringW)
		end
	end

	-- 聚焦外圈
	if self:isFocused() then
		love.graphics.setLineWidth(2)
		color.setColor(self.focusColor, self.alpha)
		love.graphics.circle("line", cx, cy, radius + ringW / 2 + 2, segments)
	end

	-- 旋钮
	local knobR = math.max(2, radius - ringW - 6)
	color.setColor(self.knobColor, self.alpha)
	love.graphics.circle("fill", cx, cy, knobR, segments)
	love.graphics.setLineWidth(1)
	color.setColor(self.knobBorderColor, self.alpha)
	love.graphics.circle("line", cx, cy, knobR, segments)

	-- 指针
	local pointerW = math.max(2, ringW * 0.45)
	local inner = knobR * 0.15
	local outer = knobR * 0.88
	local cosP, sinP = math.cos(pointer), math.sin(pointer)
	love.graphics.setLineWidth(pointerW)
	color.setColor(self.pointerColor, self.alpha)
	love.graphics.line(cx + cosP * inner, cy + sinP * inner, cx + cosP * outer, cy + sinP * outer)
	love.graphics.circle("fill", cx + cosP * outer, cy + sinP * outer, pointerW / 2)

	-- 中心点
	love.graphics.circle("fill", cx, cy, math.max(1.5, knobR * 0.1))

	-- 数值
	if self.showValue then
		local f = self:font()
		local text = self:_formatValue()
		color.setColor(self.valueColor or theme.foreground(self.knobColor), self.alpha)
		love.graphics.setFont(f)
		love.graphics.print(text, pixel.round(cx - f:getWidth(text) / 2), pixel.round(cy - f:getHeight() / 2))
	end
end

setmetatable(Dial, {
	__call = function(_, opts)
		return Dial.new(opts)
	end,
})

return Dial
