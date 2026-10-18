-- 不确定性进度条：一段高光在轨道里循环滑过，直到任务结束再隐藏/销毁。
--
--   local loading = At.LoadingBar{ w = "100%", h = 10 }
--   loading:setRunning(false)    -- 任务结束，停住
--
-- 确定性进度条见 At.ProgressBar。

local Component = require("At.core.component")
local color = require("At.core.color")
local clip = require("At.core.clip")
local pixel = require("At.core.pixel")
local motion = require("At.core.motion")

local LoadingBar = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = 220,
	h = 12,
	radius = nil, -- 缺省取高度的一半（胶囊形）

	trackColor = "#4A5160",
	fillColor = "#9FB3D3",
	alpha = 255,

	speed = 1.1, -- 每秒跑几个来回
	segmentRatio = 0.35, -- 滑块占轨道宽度的比例
	minSegment = 24, -- 滑块最小像素宽度（宽轨道上不至于太细）
	running = true,
}

function LoadingBar.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self._phase = 0
	return self
end

function proto:isRunning()
	return self.running ~= false
end

function proto:setRunning(running)
	self.running = running and true or false
	return self
end

function proto:measure()
	local declaredW, declaredH = self:declaredWidth(), self:declaredHeight()
	return (type(declaredW) == "number" and declaredW) or self.w, (type(declaredH) == "number" and declaredH) or self.h
end

function proto:_tick(dt)
	if not self:isRunning() then
		return
	end
	self._phase = ((self._phase or 0) + (dt or 0) * (self.speed or 1.1)) % 1
end

function proto:_draw()
	local r = self:rect()
	local x, y = pixel.xy(r.x, r.y)
	local w, h = pixel.round(r.w), pixel.round(r.h)
	local radius = self.radius or h / 2

	color.setColor(self.trackColor, self.alpha)
	love.graphics.rectangle("fill", x, y, w, h, radius)

	if w <= 0 then
		return
	end

	local segW = math.max(self.minSegment or 24, w * (self.segmentRatio or 0.35))
	if segW > w then
		segW = w
	end

	-- easeInOut 让滑块两端慢、中间快，比匀速更像"在找东西"
	local phase = motion.easeInOut(self._phase or 0)
	local segX = x - segW + phase * (w + segW)

	local old, visible = clip.apply(x, y, w, h)
	if visible then
		color.setColor(self.fillColor, self.alpha)
		local segRadius = math.min(radius, segW / 2)
		love.graphics.rectangle("fill", pixel.round(segX), y, math.floor(segW + 0.5), h, segRadius)
	end
	clip.restore(old)
end

setmetatable(LoadingBar, {
	__call = function(_, opts)
		return LoadingBar.new(opts)
	end,
})

return LoadingBar
