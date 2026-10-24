-- 创建窗口前读取 At/config.lua 的 render.msaa，避免启动后才 setMode 重建窗口
-- （那会先出现一次黑窗口/闪屏）。At.config 是纯 Lua 模块，可以在 conf 阶段 require。
function love.conf(t)
	local ok, config = pcall(require, "At.config")
	if ok and type(config) == "table" and config.render and config.render.msaa ~= nil then
		t.window.msaa = config.render.msaa
	end

	-- 背景模糊的圆角模板需要 stencil；LÖVE 11/12 默认也是 true，这里显式声明
	t.window.stencil = true
end
