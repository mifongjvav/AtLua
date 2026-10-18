-- 动画工具：弹簧（默认）与缓动函数。
-- 全部用 dt 驱动、无 love 依赖，可在无头环境测试。
--
--   local s = At.motion.spring{ value = 0, stiffness = 300, damping = 24 }
--   s:setTarget(1)
--   s:update(dt)          -- 每帧
--   s.value               -- 当前值（可能有过冲，适合 UI 弹入）
--
-- 弹簧用固定子步积分：掉帧时不会数值发散，也不会因为帧率不同而手感不同。

local motion = {}

local DEFAULT_STIFFNESS = 300
local DEFAULT_DAMPING = 24
local MAX_STEP = 1 / 240

local Spring = {}
Spring.__index = Spring

function Spring.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Spring)

	self.value = opts.value or 0
	self.target = opts.target or self.value
	self.velocity = opts.velocity or 0
	self.stiffness = opts.stiffness or DEFAULT_STIFFNESS
	self.damping = opts.damping or DEFAULT_DAMPING
	self.settled = true

	return self
end

function Spring:setTarget(target)
	self.target = target
	return self
end

function Spring:snap(value)
	self.value = value == nil and self.target or value
	self.target = self.value
	self.velocity = 0
	self.settled = true
	return self
end

function Spring:update(dt, epsilon)
	dt = dt or 1 / 60
	epsilon = epsilon or 0.001
	if dt <= 0 then
		return self.value
	end

	local steps = math.max(1, math.ceil(dt / MAX_STEP))
	local h = dt / steps
	for _ = 1, steps do
		local force = (self.target - self.value) * self.stiffness - self.velocity * self.damping
		self.velocity = self.velocity + force * h
		self.value = self.value + self.velocity * h
	end

	if math.abs(self.target - self.value) < epsilon and math.abs(self.velocity) < epsilon * 10 then
		self.value = self.target
		self.velocity = 0
		self.settled = true
	else
		self.settled = false
	end

	return self.value
end

function Spring:isSettled()
	return self.settled
end

function motion.spring(opts)
	return Spring.new(opts)
end

motion.Spring = Spring

-- 指数趋近：没有过冲，适合不需要弹性的场合
function motion.damp(current, target, speed, dt)
	speed = speed or 12
	local k = 1 - math.exp(-speed * (dt or 1 / 60))
	return current + (target - current) * k
end

local function clamp01(t)
	t = tonumber(t) or 0
	if t < 0 then
		return 0
	elseif t > 1 then
		return 1
	end
	return t
end

function motion.easeIn(t)
	t = clamp01(t)
	return t * t * t
end

function motion.easeOut(t)
	t = clamp01(t)
	local p = 1 - t
	return 1 - p * p * p
end

function motion.easeInOut(t)
	t = clamp01(t)
	if t < 0.5 then
		return 4 * t * t * t
	end
	local p = -2 * t + 2
	return 1 - (p * p * p) / 2
end

return motion
