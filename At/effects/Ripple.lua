-- 涟漪特效。两种用法：
--
--   实例式（组件内部用，每个按钮一份状态，互不干扰）：
--     local fx = Ripple.new{ color = "#FFFFFF" }
--     fx:add(mx, my, x, y, w, h, radius)   -- 按下
--     fx:update(dt); fx:draw()             -- 每帧
--     fx:release()                         -- 松手淡出
--
--   单例式（旧代码兼容，等于一个全局实例）：
--     At.Ripple.add(...); At.Ripple.update(); At.Ripple.draw()
--
-- 动画按真实时间推进，不再依赖帧率；不传 dt 时按 60Hz 处理，旧代码手感不变。

local Ripple = {}

local SDF = require("At.core.SDF")
local color = require("At.core.color")

-- 实例方法放在独立表里，模块表本身保留旧的单例函数，两者不冲突。
local proto = {}
proto.__index = proto

-- 60Hz 下每帧走掉 1/5 剩余距离，等价的时间常数（约 13.4 / 秒）
local DECAY = -60 * math.log(0.8)
local FALLBACK_DT = 1 / 60

local function newEmitter(opts)
	local self = setmetatable({
		enabled = true,
		color = { 1, 1, 1 },
		ripples = {},
	}, proto)

	if opts then
		if opts.enabled ~= nil then
			self.enabled = opts.enabled and true or false
		end
		if opts.color then
			self:setColor(opts.color, opts.alpha)
		end
	end

	return self
end

function proto:setEnabled(enabled)
	self.enabled = enabled and true or false
end

function proto:isEnabled()
	return self.enabled
end

-- alpha 沿用库的对外约定：0-255
function proto:setColor(hex, alpha)
	local r, g, b = color.hexToRGBA(hex, alpha or 255)
	self.color = { r, g, b }
end

function proto:add(mx, my, x, y, w, h, radius, startScale, endScale, startAlpha, endAlpha)
	if not self.enabled then
		return false
	end

	startScale = startScale or 0.1
	endScale = endScale or 1.0
	startAlpha = startAlpha or 0.8
	endAlpha = endAlpha or 0.2

	self.ripples[#self.ripples + 1] = {
		x = mx,
		y = my,
		targetX = x + w / 2,
		targetY = y + h / 2,
		w = w,
		h = h,
		radius = radius,
		scale = startScale,
		targetScale = endScale,
		alpha = startAlpha,
		targetAlpha = endAlpha,
	}

	return true
end

-- 命中判断用调用方给的坐标（不读实时鼠标位置），便于触屏与复用
function proto:handlePress(mx, my, rect)
	if not self.enabled then
		return SDF.roundRectSDF(mx, my, rect) <= 0
	end

	if SDF.roundRectSDF(mx, my, rect) <= 0 then
		self:add(mx, my, rect.x, rect.y, rect.w, rect.h, rect.radius)
		return true
	end

	return false
end

function proto:release()
	if not self.enabled then
		return
	end
	for i = 1, #self.ripples do
		self.ripples[i].targetAlpha = 0.0
	end
end

function proto:update(dt)
	dt = dt or FALLBACK_DT
	if dt <= 0 or #self.ripples == 0 then
		return
	end

	-- 指数趋近：同样时间内推进相同比例，因此与帧率无关
	local k = 1 - math.exp(-DECAY * dt)
	if k > 1 then
		k = 1
	end

	for i = #self.ripples, 1, -1 do
		local r = self.ripples[i]
		r.x = r.x + (r.targetX - r.x) * k
		r.y = r.y + (r.targetY - r.y) * k
		r.scale = r.scale + (r.targetScale - r.scale) * k
		r.alpha = r.alpha + (r.targetAlpha - r.alpha) * k

		-- 只有淡出到 0 且各通道都收敛的涟漪才回收，避免视觉上被"掐断"
		if
			r.targetAlpha == 0
			and math.abs(r.x - r.targetX) < 0.5
			and math.abs(r.y - r.targetY) < 0.5
			and math.abs(r.scale - r.targetScale) < 0.001
			and math.abs(r.alpha - r.targetAlpha) < 0.001
		then
			table.remove(self.ripples, i)
		end
	end
end

function proto:draw()
	local c = self.color
	for i = 1, #self.ripples do
		local r = self.ripples[i]
		local s = r.scale
		love.graphics.setColor(c[1], c[2], c[3], r.alpha)
		love.graphics.rectangle("fill", r.x - r.w * s / 2, r.y - r.h * s / 2, r.w * s, r.h * s, r.radius)
	end
end

function proto:clear()
	for i = #self.ripples, 1, -1 do
		table.remove(self.ripples, i)
	end
end

function proto:count()
	return #self.ripples
end

function Ripple.new(opts)
	return newEmitter(opts)
end

-- ---- 旧单例 API（保持向后兼容） ----

local default = newEmitter()

function Ripple.setEnabled(enabled)
	default:setEnabled(enabled)
end

function Ripple.setColor(hex, alpha)
	default:setColor(hex, alpha)
end

function Ripple.add(...)
	return default:add(...)
end

function Ripple.handlePress(...)
	return default:handlePress(...)
end

function Ripple.release()
	return default:release()
end

function Ripple.update(dt)
	return default:update(dt)
end

function Ripple.draw()
	return default:draw()
end

function Ripple.clear()
	return default:clear()
end

function Ripple.count()
	return default:count()
end

return Ripple
