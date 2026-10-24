-- 窗口渲染设置（目前是 MSAA）。
--
--   At.config.render.msaa = 4      -- 在 At/config.lua 里改默认值
--   At.render.setMSAA(2)           -- 运行时改（会重建窗口，下一帧模糊画布自动重建）
--   At.render.getMSAA()            -- 当前窗口实际采样数
--   At.render.getMaxMSAA()         -- 设备支持的最大采样数
--
-- 注意：MSAA 是窗口/后缓冲的属性，不是单个组件能决定的；设置后窗口会被
-- 重新创建，画布内容（包括模糊缓存）会失效，所以 At.config.apply() 里改完
-- 会重置 At.blur 的内部画布。

local log = require("At.core.log")

local render = {}

-- 当前窗口模式；拿不到窗口时返回 nil
function render.getMode()
	if not (love and love.window and love.window.getMode) then
		return nil
	end
	local ok, width, height, flags = pcall(love.window.getMode)
	if not ok or type(width) ~= "number" or type(height) ~= "number" then
		return nil
	end
	return width, height, type(flags) == "table" and flags or {}
end

-- 当前窗口实际使用的 MSAA 采样数（0 = 关闭/未知）
function render.getMSAA()
	local _, _, flags = render.getMode()
	if not flags then
		return 0
	end
	return math.max(0, math.floor(tonumber(flags.msaa) or 0))
end

-- 设备支持的最大 MSAA 采样数（0 = 未知/不支持）
function render.getMaxMSAA()
	if love and love.graphics and love.graphics.getSystemLimits then
		local ok, limits = pcall(love.graphics.getSystemLimits)
		if ok and type(limits) == "table" then
			return math.max(0, math.floor(tonumber(limits.msaa) or 0))
		end
	end
	return 0
end

-- 设置窗口 MSAA；返回（实际采样数, 是否发生了重建）。
-- 不支持 setMode 的环境（例如无头测试）返回当前值且不报错。
function render.setMSAA(msaa)
	msaa = math.max(0, math.floor(tonumber(msaa) or 0))

	local width, height, flags = render.getMode()
	if not width or not flags or not (love.window and love.window.setMode) then
		return render.getMSAA(), false
	end

	local maxMSAA = render.getMaxMSAA()
	if maxMSAA > 0 and msaa > maxMSAA then
		msaa = maxMSAA
	end

	local current = math.max(0, math.floor(tonumber(flags.msaa) or 0))
	if current == msaa then
		return current, false
	end

	flags.msaa = msaa
	local ok, err = pcall(love.window.setMode, width, height, flags)
	if not ok then
		log.warn("MSAA 设置为 %d 失败：%s", msaa, tostring(err))
		return render.getMSAA(), false
	end
	return render.getMSAA(), true
end

return render
