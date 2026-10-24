-- 集中配置：改这里就能调整库的默认行为，不用逐个模块设。
--
--   At.config.theme.color = "7FE0C4"
--   At.config.blur.enabled = true
--   At.config.apply()          -- 把当前配置推给各模块（At.lua 启动时已调用一次）
--
-- 想改默认值直接改下面的表即可；运行时临时调整改完记得调 apply()。

local config = {}

-- 主题色：三个基色派生全部语义色，组件默认颜色都是主题 token
config.theme = {
	color = "#A7DCFF", -- 主题色 / 强调色
	black = "#3D3D3D", -- 深色槽位（默认背景）
	white = "#FFFFFF", -- 浅色槽位（默认文字 / 旋钮）
}

-- 背景模糊（毛玻璃）
config.blur = {
	enabled = true, -- 是否启用模糊
	algorithm = "gaussian", -- gaussian / downscale / none，或自定义函数
	strength = 8, -- 模糊强度（gaussian 采样半径基准 / downscale 缩小倍数）
}

-- 渲染 / 窗口
config.render = {
	msaa = 4, -- 抗锯齿采样数：0 关闭，建议 2 或 4；设备不支持会自动取上限
}

-- 阴影：glsl 为单次 SDF 投影，legacy 为旧的多层缩放矩形，none 全部关闭
config.shadow = {
	algorithm = "glsl", -- glsl / legacy / none
	color = "@primaryDark", -- 阴影颜色：主题 token 或 hex；默认深色主题色
	alpha = 0.4, -- 字符串颜色 / 缺省颜色使用的最大不透明度（0–1）
	spread = 3, -- 模糊半径（GLSL）/ 最大扩散（legacy）
	layers = 20, -- 只对 legacy 生效
	offsetX = 1,
	offsetY = 2,
}

-- 日志
config.log = {
	level = "info", -- debug / info / warn / error / fatal
	print = true, -- 是否同时输出到终端（Android 即 logcat）
	maxEntries = 500, -- 缓冲区上限，0 表示不限
	file = false, -- 是否写入文件（LÖVE 下写入存档目录）
	filePattern = "%Y-%m-%d_%H-%M-%S.log", -- os.date 格式；不要用冒号，Windows 不合法
}

-- 字体（资源目录：At/assets/）
config.font = {
	size = 16, -- At.font.init() 的默认字号
	main = "/At/assets/font.ttf",
	emoji = "/At/assets/emoji.ttf",
}

-- 把配置推给各模块；返回 config 便于链式调用
function config.apply()
	local theme = require("At.core.theme")
	if config.theme then
		theme.set(config.theme)
	end

	local log = require("At.core.log")
	if config.log then
		if config.log.level then
			log.setLevel(config.log.level)
		end
		if config.log.print ~= nil then
			log.setPrint(config.log.print)
		end
		if config.log.maxEntries then
			log.setMaxEntries(config.log.maxEntries)
		end
		if config.log.filePattern then
			log.setFilePattern(config.log.filePattern)
		end
		if config.log.file ~= nil then
			log.setFile(config.log.file)
		end
	end

	local blur = require("At.effects.blur")
	if config.blur then
		if config.blur.strength then
			blur.setStrength(config.blur.strength)
		end
		if config.blur.algorithm then
			blur.setAlgorithm(config.blur.algorithm)
		end
		if config.blur.enabled ~= nil then
			blur.setEnabled(config.blur.enabled)
		end
	end

	local shadow = require("At.core.shadow")
	if config.shadow then
		shadow.configure(config.shadow)
	end

	local render = require("At.core.render")
	if config.render and config.render.msaa ~= nil then
		-- MSAA 是窗口属性：设置后后缓冲重建，缓存画布/阴影纹理也要一起清掉
		local _, changed = render.setMSAA(config.render.msaa)
		if changed then
			blur.reset()
			shadow.reset()
		end
	end

	return config
end

return config
