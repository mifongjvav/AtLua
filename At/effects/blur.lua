-- 背景模糊（毛玻璃）：抓取组件背后的画面，模糊后作为半透明组件的底。
--
--   At.blur.setEnabled(true)          -- At.blur.enabled = true 也行
--   At.blur.setAlgorithm("downscale") -- gaussian / downscale / none / 自定义函数
--   At.blur.setStrength(8)
--
--   function love.draw()
--       At.blur.beginFrame()   -- 之后画到内部 canvas
--       ui:draw()
--       At.blur.endFrame()     -- 输出到屏幕
--   end
--
-- 半透明组件（Panel/Console/ScrollView/TextInput/Button，alpha < 255）会自动调用
-- At.blur.drawBackdrop()，不需要在组件里写额外代码。
--
-- 原理：beginFrame 把后续绘制收集到 scene canvas；某个组件要模糊时，把 scene 当前内容
-- 复制到 snapshot，再按算法模糊，最后用圆角模板把它画回该组件的位置。因此模糊的是
-- "组件之前已经画上去的内容"，不依赖上一帧，也没有延迟。

local log = require("At.core.log")

local blur = {}

local state = {
	enabled = false,
	algorithm = "gaussian",
	strength = 8,
	failed = false,
	error = nil,
	scene = nil,
	snapshot = nil,
	active = false,
	previousCanvas = nil,
	width = 0,
	height = 0,
	scratch = {},
	stats = { frames = 0, backdrops = 0, snapshots = 0 },
}

local algorithms = {}

local releaseScratch -- 前置声明：reset 在画布管理之前定义

-- ---------- 算法注册 ----------

function blur.registerAlgorithm(name, fn)
	if type(name) ~= "string" or type(fn) ~= "function" then
		error("registerAlgorithm(name, fn) 参数不合法", 2)
	end
	algorithms[name] = fn
	return blur
end

function blur.getAlgorithms()
	local names = {}
	for name in pairs(algorithms) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

function blur.setAlgorithm(algorithm)
	if type(algorithm) == "function" then
		state.algorithm = algorithm
		return algorithm
	end
	if type(algorithm) ~= "string" or not algorithms[algorithm] then
		error(
			"未知模糊算法: "
				.. tostring(algorithm)
				.. "（可用: "
				.. table.concat(blur.getAlgorithms(), "/")
				.. "，或传函数）",
			2
		)
	end
	state.algorithm = algorithm
	return algorithm
end

function blur.getAlgorithm()
	return state.algorithm
end

function blur.setStrength(strength)
	state.strength = math.max(1, math.floor(tonumber(strength) or 8))
	return state.strength
end

function blur.getStrength()
	return state.strength
end

-- ---------- 开关 ----------

function blur.setEnabled(enabled)
	state.enabled = enabled and true or false
	if not state.enabled then
		state.active = false
		state.previousCanvas = nil
	end
	return state.enabled
end

function blur.isEnabled()
	return state.enabled and not state.failed
end

function blur.isActive()
	return state.active
end

function blur.getError()
	return state.error
end

function blur.stats()
	local s = state.stats
	return { frames = s.frames, backdrops = s.backdrops, snapshots = s.snapshots }
end

-- 清掉失败状态与缓存画布，便于换设备/换配置后重试
function blur.reset()
	state.failed = false
	state.error = nil
	pcall(function()
		if state.scene then
			state.scene:release()
		end
		if state.snapshot then
			state.snapshot:release()
		end
	end)
	state.scene, state.snapshot = nil, nil
	state.width, state.height = 0, 0
	releaseScratch()
	return blur
end

function blur.resetStats()
	state.stats = { frames = 0, backdrops = 0, snapshots = 0 }
end

-- ---------- 画布管理 ----------

local function fail(message)
	if state.failed then
		return nil
	end
	state.failed = true
	state.error = message
	state.enabled = false
	state.active = false
	log.warn("At.blur 已关闭：%s", message)
	return nil
end

local function newCanvas(width, height)
	if not (love and love.graphics and love.graphics.newCanvas) then
		return fail("当前环境不支持 canvas")
	end
	local ok, canvas = pcall(love.graphics.newCanvas, width, height)
	if not ok or not canvas then
		return fail("创建 canvas 失败")
	end
	pcall(function()
		canvas:setFilter("linear", "linear")
	end)
	return canvas
end

releaseScratch = function()
	for _, canvas in pairs(state.scratch) do
		pcall(function()
			canvas:release()
		end)
	end
	state.scratch = {}
end

local function ensureSize()
	local width, height = love.graphics.getDimensions()
	if state.scene and state.width == width and state.height == height then
		return true
	end

	pcall(function()
		if state.scene then
			state.scene:release()
		end
		if state.snapshot then
			state.snapshot:release()
		end
	end)
	releaseScratch()

	state.scene = newCanvas(width, height)
	if not state.scene then
		return false
	end
	state.snapshot = newCanvas(width, height)
	if not state.snapshot then
		return false
	end

	state.width, state.height = width, height
	return true
end

local function scratchCanvas(key, width, height)
	local canvas = state.scratch[key]
	if canvas and canvas:getWidth() == width and canvas:getHeight() == height then
		return canvas
	end
	pcall(function()
		if canvas then
			canvas:release()
		end
	end)
	canvas = newCanvas(width, height)
	state.scratch[key] = canvas
	return canvas
end

-- 把纹理里的 (qx,qy,qw,qh) 区域画到 (dx,dy)，按 scale 缩放
local function drawRegion(texture, qx, qy, qw, qh, dx, dy, scaleX, scaleY)
	local tw, th = texture:getDimensions()
	local quad = love.graphics.newQuad(qx, qy, qw, qh, tw, th)
	love.graphics.draw(texture, quad, dx, dy, 0, scaleX or 1, scaleY or 1)
end

-- ---------- 内置算法 ----------
-- 约定：fn(snapshot, x, y, w, h, strength) -> texture, quadX, quadY, quadWidth, quadHeight
-- 返回 nil 表示这次不做模糊。

-- 不模糊，只把背景原样画回来（用于调试/开关对比）
blur.registerAlgorithm("none", function(snapshot, x, y, w, h)
	return snapshot, x, y, w, h
end)

-- 降采样再放大：不需要 shader，GLES2/低端机也能用，效果偏"柔和"而不是光学模糊
blur.registerAlgorithm("downscale", function(snapshot, x, y, w, h, strength)
	-- 纯 canvas 方案（不需要 shader）：
	-- 先降到 1/2，再降到 1/scale，然后逐级线性放大回去。
	-- 一步降太多再放大，双线性会放大成明显的方格；多级金字塔就没那么硬。
	local scale = math.max(2, math.min(6, math.floor((strength or 8) / 2)))

	local halfW = math.max(1, math.ceil(w / 2))
	local halfH = math.max(1, math.ceil(h / 2))
	local smallW = math.max(1, math.ceil(w / scale))
	local smallH = math.max(1, math.ceil(h / scale))

	local half = scratchCanvas("downHalf", halfW, halfH)
	local small = scratchCanvas("downSmall", smallW, smallH)
	if not half or not small then
		return nil
	end

	local target = love.graphics.getCanvas()
	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setShader()
	love.graphics.setBlendMode("replace")

	-- 1) 区域 -> 1/2
	love.graphics.setCanvas(half)
	love.graphics.clear(0, 0, 0, 0)
	drawRegion(snapshot, x, y, w, h, 0, 0, 1 / 2, 1 / 2)

	-- 2) 1/2 -> 1/scale
	love.graphics.setCanvas(small)
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.draw(half, 0, 0, 0, smallW / halfW, smallH / halfH)

	-- 3) 1/scale -> 1/2（线性放大一次，交给 drawBackdrop 再放大到组件大小）
	love.graphics.setCanvas(half)
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.draw(small, 0, 0, 0, halfW / smallW, halfH / smallH)

	love.graphics.setCanvas(target)
	love.graphics.pop()

	return half, 0, 0, halfW, halfH
end)

local GAUSSIAN_SHADER = [[
uniform vec2 blurDirection;
uniform vec2 texelSize;
uniform float radius;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    vec4 sum = vec4(0.0);
    float total = 0.0;
    // 9 个采样点之间只隔 radius/4 个纹素：密集采样才平滑。
    // 间距太大（比如 radius/1）会把画面复制成几份，出现"小方块"。
    for (int i = -4; i <= 4; i++) {
        float weight = exp(-float(i * i) / 8.0);
        vec2 offset = blurDirection * texelSize * (radius * 0.25) * float(i);
        sum += Texel(tex, uv + offset) * weight;
        total += weight;
    }
    return vec4(sum.rgb / total, 1.0);
}
]]

local gaussianShader

local function getShader()
	if gaussianShader then
		return gaussianShader
	end
	if not (love and love.graphics and love.graphics.newShader) then
		return nil
	end
	local ok, shader = pcall(love.graphics.newShader, GAUSSIAN_SHADER)
	if not ok or not shader then
		return nil
	end
	gaussianShader = shader
	return shader
end

-- 分离式高斯：水平与垂直各一遍，比一次性 2D 卷积省很多采样
blur.registerAlgorithm("gaussian", function(snapshot, x, y, w, h, strength)
	local shader = getShader()
	if not shader then
		return nil -- 交给上层回退到 downscale
	end

	-- 先降到 1/2 分辨率再模糊：高分辨率 + 稀疏采样会留下明显的采样格，
	-- 降采样本身也是一次平滑，最后线性放大就能得到连续的毛玻璃。
	local scale = 2
	local sw = math.max(1, math.ceil(w / scale))
	local sh = math.max(1, math.ceil(h / scale))

	local pass1 = scratchCanvas("gaussianA", sw, sh)
	local pass2 = scratchCanvas("gaussianB", sw, sh)
	if not pass1 or not pass2 then
		return nil
	end

	local target = love.graphics.getCanvas()

	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setShader()
	love.graphics.setBlendMode("replace")

	-- 1) 把 snapshot 的对应区域降采样进 pass1
	love.graphics.setCanvas(pass1)
	love.graphics.clear(0, 0, 0, 0)
	drawRegion(snapshot, x, y, w, h, 0, 0, 1 / scale, 1 / scale)

	-- 2) 水平高斯：pass1 -> pass2
	shader:send("blurDirection", { 1, 0 })
	shader:send("texelSize", { 1 / sw, 1 / sh })
	shader:send("radius", math.max(1, (strength or 8) / 2))
	love.graphics.setShader(shader)
	love.graphics.setCanvas(pass2)
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.draw(pass1, 0, 0)

	-- 3) 垂直高斯：pass2 -> pass1（pass1 的内容已经用不到了）
	shader:send("blurDirection", { 0, 1 })
	love.graphics.setCanvas(pass1)
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.draw(pass2, 0, 0)

	love.graphics.setShader()
	love.graphics.setCanvas(target)
	love.graphics.pop()

	-- 交回 1/2 分辨率的画布，drawBackdrop 会线性放大到组件大小
	return pass1, 0, 0, sw, sh
end)

-- ---------- 帧控制 ----------

function blur.beginFrame()
	if not state.enabled or state.failed then
		return false
	end
	if not ensureSize() then
		return false
	end

	state.previousCanvas = love.graphics.getCanvas()
	love.graphics.setCanvas(state.scene)
	love.graphics.clear(love.graphics.getBackgroundColor())
	state.active = true
	state.stats.frames = state.stats.frames + 1
	return true
end

function blur.endFrame()
	if not state.active then
		return false
	end

	love.graphics.setCanvas(state.previousCanvas)
	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setBlendMode("replace")
	love.graphics.draw(state.scene, 0, 0)
	love.graphics.pop()

	state.active = false
	state.previousCanvas = nil
	return true
end

-- ---------- 供组件调用 ----------

local function resolveAlgorithm()
	local algorithm = state.algorithm
	if type(algorithm) == "function" then
		return algorithm
	end
	return algorithms[algorithm] or algorithms.downscale
end

-- 把当前画布内容复制到 snapshot（不改变当前目标）
local function takeSnapshot()
	local source = love.graphics.getCanvas()
	if not source or not state.snapshot then
		return nil
	end

	love.graphics.push("all")
	love.graphics.setCanvas(state.snapshot)
	love.graphics.clear(0, 0, 0, 0)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setBlendMode("replace")
	love.graphics.draw(source, 0, 0)
	love.graphics.setCanvas(source)
	love.graphics.pop()

	state.stats.snapshots = state.stats.snapshots + 1
	return state.snapshot
end

-- 在 (x, y, w, h, radius) 处绘制模糊后的背景；返回是否真的画了
function blur.drawBackdrop(x, y, w, h, radius)
	if not state.enabled or state.failed then
		return false
	end
	if w <= 0 or h <= 0 then
		return false
	end
	if not state.scene and not state.active then
		return false
	end

	local snapshot = takeSnapshot()
	if not snapshot then
		return false
	end

	local algorithm = resolveAlgorithm()
	local texture, qx, qy, qw, qh = algorithm(snapshot, x, y, w, h, state.strength)

	-- gaussian 需要 shader；拿不到时自动退回降采样算法
	if not texture and state.algorithm ~= "downscale" then
		texture, qx, qy, qw, qh = algorithms.downscale(snapshot, x, y, w, h, state.strength)
	end

	if not texture or not qx or not qy or not qw or not qh or qw <= 0 or qh <= 0 then
		return false
	end

	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setShader()

	-- 圆角裁剪：优先 stencil，失败则退化为矩形 scissor
	local stencilOk = false
	if love.graphics.stencil and love.graphics.setStencilTest then
		stencilOk = pcall(function()
			love.graphics.stencil(function()
				love.graphics.rectangle("fill", x, y, w, h, radius or 0)
			end, "replace", 1)
			love.graphics.setStencilTest("greater", 0)
		end)
	end

	local okDraw = pcall(function()
		local quad = love.graphics.newQuad(qx, qy, qw, qh, texture:getDimensions())
		love.graphics.draw(texture, quad, x, y, 0, w / qw, h / qh)
	end)

	if stencilOk then
		pcall(love.graphics.setStencilTest)
		-- 复位本区域的模板值，避免多个模糊组件共用同一块遮罩
		pcall(function()
			love.graphics.stencil(function()
				love.graphics.rectangle("fill", x, y, w, h, radius or 0)
			end, "replace", 0)
		end)
	end
	love.graphics.pop()

	if not okDraw then
		return false
	end

	state.stats.backdrops = state.stats.backdrops + 1
	return true
end

-- `At.blur.enabled = true` 也能用（等价于 setEnabled）
setmetatable(blur, {
	__index = function(_, key)
		if key == "enabled" then
			return blur.isEnabled()
		end
		return nil
	end,
	__newindex = function(_, key, value)
		if key == "enabled" then
			blur.setEnabled(value)
			return
		end
		rawset(blur, key, value)
	end,
})

return blur
