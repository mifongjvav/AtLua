-- 集中配置：改这里就能调整库的默认行为，不用逐个模块设。
--
--   At.config.blur.enabled = true
--   At.config.apply()          -- 把当前配置推给各模块（At.lua 启动时已调用一次）
--
-- 想改默认值直接改下面的表即可；运行时临时调整改完记得调 apply()。

local config = {}

-- 背景模糊（毛玻璃）
config.blur = {
	enabled = true, -- 是否启用模糊
	algorithm = "gaussian", -- gaussian / downscale / none，或自定义函数
	strength = 8, -- 模糊强度（gaussian 采样半径基准 / downscale 缩小倍数）
}

-- 日志
config.log = {
	level = "info", -- debug / info / warn / error / fatal
	print = true, -- 是否同时输出到终端（Android 即 logcat）
	maxEntries = 500, -- 缓冲区上限，0 表示不限
	file = false, -- 是否写入文件（LÖVE 下写入存档目录）
	filePattern = "%Y-%m-%d %H:%M:%S.log", -- os.date 格式；Windows 请改用 %H-%M-%S
}

-- 字体（资源目录：At/assets/）
config.font = {
	size = 16, -- At.font.init() 的默认字号
	main = "/At/assets/font.ttf",
	emoji = "/At/assets/emoji.ttf",
}

-- 把配置推给各模块；返回 config 便于链式调用
function config.apply()
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

	return config
end

return config
