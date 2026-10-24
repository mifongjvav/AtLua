-- 阴影：默认用 GLSL 的 SDF 圆角矩形做柔和投影，也可以切回旧的多层缩放矩形。
--
--   At.config.shadow.algorithm = "glsl"    -- 默认；一次 draw 完成，边缘更干净
--   At.config.shadow.algorithm = "legacy"  -- 旧实现：layers 层缩放矩形叠加
--   At.config.shadow.algorithm = "none"    -- 全部关闭（单个组件仍可用 shadow = false）
--
-- 参数沿用旧签名，组件不需要改：
--   shadow.shadow(x, y, w, h, corner, color, spread, layers, offsetX, offsetY)
--   color 可以是 0..1 的 RGBA 表，也可以是 hex / 主题 token（如 "@primaryDark"，
--   字符串形式默认 alpha 0.4）。spread 在 GLSL 下是尺寸基准（实际模糊半径 = spread*2），layers 只对 legacy 生效。
--
-- GLSL 失败（shader 编译失败、没有可用的 1x1 纹理）时自动退回 legacy。
-- 内阴影 shadow.inner 复用 1x1 纹理，但需要单独的 shader；失败时直接不画。
-- GLSL 以组件边缘为中心向内外对称模糊，并用 1/255 抖动打散 8 位 alpha 的色带。

shadow = {}

local colorlib = require("At.core.color")

local algorithm = "glsl"

local defaults = {
	color = "@primaryDark",
	alpha = 0.4,
	spread = 3,
	layers = 20,
	offsetX = 1,
	offsetY = 2,
}

local SHADER = [[
extern vec2 shadowSize;
extern vec2 rectSize;
extern vec2 rectCenter;
extern float rectRadius;
extern float blur;
extern vec4 shadowColor;

float sdRoundRect(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    vec2 p = uv * shadowSize;
    float d = sdRoundRect(p - rectCenter, rectSize * 0.5, rectRadius);
    // 以边缘为中心向内外各模糊 blur，使用 smootherstep 让过渡更柔和
    float t = clamp((d + blur) / (2.0 * blur), 0.0, 1.0);
    float a = 1.0 - t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
    // 1/255 的屏幕空间抖动，打散 8 位 alpha 在浅色背景上的色带
    float noise = fract(52.9829189 * fract(dot(floor(sc), vec2(0.06711056, 0.00583715))));
    a = clamp(a + (noise - 0.5) / 255.0, 0.0, 1.0);
    return vec4(shadowColor.rgb, shadowColor.a * a);
}
]]

local INNER_SHADER = [[
extern vec2 shadowSize;
extern vec2 rectSize;
extern vec2 rectCenter;
extern float rectRadius;
extern float innerSize;
extern vec2 innerOffset;
extern vec4 shadowColor;

float sdRoundRect(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    vec2 p = uv * shadowSize;
    vec2 base = p - rectCenter;
    float d0 = sdRoundRect(base, rectSize * 0.5, rectRadius);
    float d1 = sdRoundRect(base + innerOffset, rectSize * 0.5, rectRadius);
    float inside = 1.0 - smoothstep(0.0, 1.0, d0);
    float t = clamp(-d1 / max(innerSize, 0.001), 0.0, 1.0);
    float a = (1.0 - t) * inside;
    float noise = fract(52.9829189 * fract(dot(floor(sc), vec2(0.06711056, 0.00583715))));
    a = clamp(a + (noise - 0.5) / 255.0, 0.0, 1.0);
    return vec4(shadowColor.rgb, shadowColor.a * a);
}
]]

local shader
local innerShader
local whiteTexture
local shaderTried = false
local innerTried = false

local function makeWhiteTexture()
	-- 优先 ImageData → Image，避免依赖 canvas 状态
	if love.image and love.image.newImageData and love.graphics.newImage then
		local okData, data = pcall(love.image.newImageData, 1, 1)
		if okData and data and data.setPixel then
			data:setPixel(0, 0, 1, 1, 1, 1)
			local okImage, image = pcall(love.graphics.newImage, data)
			if okImage and image then
				return image
			end
		end
	end

	-- 没有 image 模块时用 1x1 白 canvas 兜底
	if love.graphics.newCanvas and love.graphics.setCanvas then
		local previous = love.graphics.getCanvas and love.graphics.getCanvas()
		local okCanvas, canvas = pcall(love.graphics.newCanvas, 1, 1)
		if okCanvas and canvas then
			local ok = pcall(function()
				love.graphics.push("all")
				love.graphics.setCanvas(canvas)
				love.graphics.clear(1, 1, 1, 1)
				love.graphics.setCanvas(previous)
				love.graphics.pop()
			end)
			if ok then
				return canvas
			end
			pcall(function()
				canvas:release()
			end)
		end
	end

	return nil
end

local function getResources()
	if shader and whiteTexture then
		return shader, whiteTexture
	end
	if shaderTried then
		return nil
	end
	shaderTried = true

	if not (love and love.graphics and love.graphics.newShader) then
		return nil
	end
	local ok, compiled = pcall(love.graphics.newShader, SHADER)
	if not ok or not compiled then
		return nil
	end

	local texture = makeWhiteTexture()
	if not texture then
		return nil
	end

	shader, whiteTexture = compiled, texture
	return shader, whiteTexture
end

local function getInnerResources()
	if innerShader and whiteTexture then
		return innerShader, whiteTexture
	end
	if innerTried then
		return nil
	end
	if not whiteTexture then
		whiteTexture = makeWhiteTexture()
	end
	if not whiteTexture then
		innerTried = true
		return nil
	end
	if not (love and love.graphics and love.graphics.newShader) then
		innerTried = true
		return nil
	end
	local ok, compiled = pcall(love.graphics.newShader, INNER_SHADER)
	innerTried = true
	if not ok or not compiled then
		return nil
	end
	innerShader = compiled
	return innerShader, whiteTexture
end

-- ---------- 旧实现：多层缩放矩形 ----------

local function normalizeColor(value)
	if value == nil then
		value = defaults.color
	end
	if type(value) == "string" then
		local r, g, b = colorlib.hexToRGBA(value)
		return { r, g, b, defaults.alpha }
	end
	if type(value) == "table" then
		return {
			value[1] or 0,
			value[2] or 0,
			value[3] or 0,
			value[4] or defaults.alpha,
		}
	end
	return { 0, 0, 0, defaults.alpha }
end

local function legacy(x, y, w, h, corner, color, spread, layers, offsetX, offsetY)
	layers = layers or 20
	offsetX = offsetX or 0
	offsetY = offsetY or 0
	spread = spread or 3

	-- 每层都很淡，靠"层数"做柔和度。必须按层数归一化：
	-- 否则 20 层各 7.5% 叠加后接近 80% 不透明，看起来就是一圈黑底。
	local layerCount = layers + 1
	local layerAlpha = color[4] * 2 / layerCount

	for i = layers, 0, -1 do
		local progress = i / layers
		local alpha = layerAlpha * (1 - progress)

		local spread_pixels = progress * spread
		local scale_w = 1 + (spread_pixels * 2) / w
		local scale_h = 1 + (spread_pixels * 2) / h

		local base_offset_x = (scale_w - 1) * w / 2
		local base_offset_y = (scale_h - 1) * h / 2

		local layer_offset_x = offsetX * (1 - progress * 0.5)
		local layer_offset_y = offsetY * (1 - progress * 0.5)

		love.graphics.setColor(color[1], color[2], color[3], alpha)
		love.graphics.rectangle(
			"fill",
			x - base_offset_x + layer_offset_x,
			y - base_offset_y + layer_offset_y,
			w * scale_w,
			h * scale_h,
			corner
		)
	end
end

-- ---------- GLSL 实现 ----------

local function drawGLSL(x, y, w, h, corner, color, spread, offsetX, offsetY, shaderObject, texture)
	local blur = math.max(2, (tonumber(spread) or 3) * 2)
	local ox = tonumber(offsetX) or 0
	local oy = tonumber(offsetY) or 0
	local pad = math.ceil(blur + math.abs(ox) + math.abs(oy) + 1)
	local quadW = w + pad * 2
	local quadH = h + pad * 2
	local radius = math.min(tonumber(corner) or 0, math.min(w, h) / 2)

	shaderObject:send("shadowSize", { quadW, quadH })
	shaderObject:send("rectSize", { w, h })
	shaderObject:send("rectCenter", { quadW / 2 + ox, quadH / 2 + oy })
	shaderObject:send("rectRadius", radius)
	shaderObject:send("blur", blur)
	shaderObject:send("shadowColor", { color[1], color[2], color[3], color[4] })

	love.graphics.push("all")
	love.graphics.setShader(shaderObject)
	love.graphics.setBlendMode("alpha")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(texture, x - pad, y - pad, 0, quadW, quadH)
	love.graphics.pop()
end

local function drawInner(x, y, w, h, corner, color, size, offsetX, offsetY, shaderObject, texture)
	local innerSize = math.max(1, tonumber(size) or 3)
	local ox = tonumber(offsetX) or 0
	local oy = tonumber(offsetY) or 0
	local radius = math.min(tonumber(corner) or 0, math.min(w, h) / 2)

	shaderObject:send("shadowSize", { w, h })
	shaderObject:send("rectSize", { w, h })
	shaderObject:send("rectCenter", { w / 2, h / 2 })
	shaderObject:send("rectRadius", radius)
	shaderObject:send("innerSize", innerSize)
	shaderObject:send("innerOffset", { ox, oy })
	shaderObject:send("shadowColor", { color[1], color[2], color[3], color[4] })

	love.graphics.push("all")
	love.graphics.setShader(shaderObject)
	love.graphics.setBlendMode("alpha")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(texture, x, y, 0, w, h)
	love.graphics.pop()
end

local function innerColor(value, alpha)
	alpha = tonumber(alpha) or 0.18
	if type(value) == "table" then
		return { value[1] or 0, value[2] or 0, value[3] or 0, alpha }
	end
	local r, g, b = colorlib.hexToRGBA(value or defaults.color)
	return { r, g, b, alpha }
end

-- ---------- 对外 API ----------

function shadow.setAlgorithm(name)
	name = tostring(name or "glsl")
	if name ~= "glsl" and name ~= "legacy" and name ~= "none" then
		error("未知阴影算法: " .. name .. "（可用: glsl / legacy / none）", 2)
	end
	algorithm = name
	return algorithm
end

function shadow.getAlgorithm()
	return algorithm
end

-- 覆盖默认阴影参数；config.apply() 会把 At.config.shadow 传进来
function shadow.configure(opts)
	if type(opts) ~= "table" then
		return shadow
	end
	for _, key in ipairs({ "color", "alpha", "spread", "layers", "offsetX", "offsetY" }) do
		if opts[key] ~= nil then
			defaults[key] = opts[key]
		end
	end
	if opts.algorithm ~= nil then
		shadow.setAlgorithm(opts.algorithm)
	end
	return shadow
end

-- 当前默认参数（副本，改它不会影响阴影）
function shadow.defaults()
	local copy = {}
	for key, value in pairs(defaults) do
		copy[key] = value
	end
	return copy
end

-- 内阴影：只画在矩形/圆角形状内部，适合单选圆圈、复选方框这类凹陷控件
--   At.shadow.inner(x, y, w, h, corner, color, alpha 0..1, size, offsetX, offsetY)
-- color 支持 hex / 主题 token；size 是向内衰减的像素距离。
function shadow.inner(x, y, w, h, corner, innerColorValue, alpha, size, offsetX, offsetY)
	if w <= 0 or h <= 0 or algorithm == "none" then
		return
	end
	local shaderObject, texture = getInnerResources()
	if not shaderObject or not texture then
		return
	end
	drawInner(x, y, w, h, corner, innerColor(innerColorValue, alpha), size, offsetX, offsetY, shaderObject, texture)
	return true
end

-- 丢掉 shader 与白纹理；窗口重建、换图形上下文后调用
function shadow.reset()
	pcall(function()
		if whiteTexture and whiteTexture.release then
			whiteTexture:release()
		end
	end)
	shader, innerShader, whiteTexture = nil, nil, nil
	shaderTried = false
	innerTried = false
	return shadow
end

function shadow.shadow(x, y, w, h, corner, color, spread, layers, offsetX, offsetY)
	if w <= 0 or h <= 0 then
		return
	end

	if algorithm == "none" then
		return
	end

	color = normalizeColor(color)
	spread = tonumber(spread) or defaults.spread
	layers = tonumber(layers) or defaults.layers
	offsetX = tonumber(offsetX) or defaults.offsetX
	offsetY = tonumber(offsetY) or defaults.offsetY

	if algorithm == "glsl" then
		local shaderObject, texture = getResources()
		if shaderObject and texture then
			drawGLSL(x, y, w, h, corner, color, spread, offsetX, offsetY, shaderObject, texture)
			return
		end
	end

	legacy(x, y, w, h, corner, color, spread, layers, offsetX, offsetY)
end

return shadow
