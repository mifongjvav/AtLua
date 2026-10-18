local At = require("At.At")

-- 演示：一张卡片里的表单，由 ScrollView + Panel 排版。
-- 窗口再小也能滚动看全；开关可以点，也可以左右拖动。

local state = {
	ripples = true,
	quality = 2,
	volume = 60,
	nickname = "",
}

local card, viewport, statusLabel, volumeLabel, stateLabel
local volumeProgress
local submitBtn, nameInput, logConsole

local function setStatus(text)
	if statusLabel then
		statusLabel:setText(text)
	end
end

local function refreshState()
	if not stateLabel then
		return
	end
	stateLabel:setText(
		string.format(
			"焦点：%s    昵称：%s",
			(nameInput and nameInput:isFocused()) and "输入框" or "无",
			state.nickname ~= "" and state.nickname or "（空）"
		)
	)
end

local function viewportSize(screenW, screenH)
	if not screenW or not screenH then
		screenW, screenH = love.graphics.getDimensions()
	end
	local w = math.min(420, math.max(240, screenW - 80))
	local h = math.max(160, screenH - 80)
	return w, h, math.max(20, math.floor((screenW - w) / 2))
end

-- ---------- 卡片内容 ----------

card = At.Panel({
	w = "100%",
	h = "auto",
	direction = "column",
	gap = 14,
	padding = 20,
	radius = 16,
	background = "#242A34",
	borderColor = "#39404D",
	shadow = false, -- 想要柔和阴影可改成 { { 0, 0, 0, 0.18 }, 6, 12, 0, 4 }
})

card:add(At.Label({ text = "At 组件演示", fontSize = 22 }))
card:add(At.Label({
	text = "卡片由 Panel 排版；外层 ScrollView 负责裁剪与滚动，窗口小的时候用滚轮或拖动空白处查看下面的内容。",
	wrap = true,
	w = "100%",
	lineHeight = 1.4,
	color = "#A9B2C2",
}))

nameInput = At.TextInput({
	w = "100%",
	placeholder = "输入昵称，回车提交（Esc 失焦）",
	text = state.nickname,
	maxLength = 16,
	onChange = function(text)
		state.nickname = text
		At.log.debug("昵称输入: %s", text)
		refreshState()
	end,
	onFocus = function(self)
		-- 移动端：聚焦时把这个输入框滚进可视区，别被软键盘挡住
		if viewport then
			viewport:scrollToVisible(self, 24)
		end
		At.log.debug("输入框获得焦点")
		refreshState()
		setStatus("输入框已聚焦，软键盘应弹出")
	end,
	onBlur = function()
		At.log.debug("输入框失焦")
		refreshState()
	end,
	onSubmit = function(text)
		if text == "" then
			At.log.warn("提交被拒绝：昵称为空")
			setStatus("请先输入昵称")
		else
			At.log.info("提交昵称: %s", text)
			setStatus("已提交：" .. text)
		end
	end,
})

card:add(nameInput)

card:add(At.Panel({
	direction = "row",
	align = "center",
	gap = 10,
	children = {
		At.Label({ text = "涟漪特效", fontSize = 15 }),
		At.Switch({
			value = state.ripples,
			onChange = function(value)
				state.ripples = value
				At.log.info("涟漪特效: %s", value and "开启" or "关闭")
				if submitBtn then
					submitBtn:setRippleEnabled(value)
				end
				setStatus(value and "涟漪已开启" or "涟漪已关闭")
			end,
		}),
	},
}))

card:add(At.Label({
	text = "开关可以点击切换，也可以按住左右拖动",
	fontSize = 13,
	color = "#8F98A8",
}))

card:add(At.RadioGroup({
	options = { "低", "中", "高" },
	value = state.quality,
	direction = "row",
	gap = 24,
	onChange = function(index, label)
		state.quality = index
		At.log.info("画质切换到 %s（第 %d 项）", label, index)
		setStatus("画质：" .. label)
	end,
}))

volumeLabel = At.Label({ text = "音量：" .. state.volume, fontSize = 15, color = "#A9B2C2" })
card:add(volumeLabel)

card:add(At.Slider({
	w = "100%",
	min = 0,
	max = 100,
	step = 5,
	value = state.volume,
	onChange = function(value)
		state.volume = value
		if value >= 90 then
			At.log.warn("音量过高: %d", value)
		else
			At.log.debug("音量: %d", value)
		end
		volumeLabel:setText("音量：" .. value)
		if volumeProgress then
			volumeProgress:setValue(value / 100)
		end
	end,
}))

card:add(At.Label({ text = "确定性进度条（跟随音量）", fontSize = 13, color = "#8F98A8" }))
volumeProgress = At.ProgressBar({ w = "100%", h = 10, value = state.volume / 100 })
card:add(volumeProgress)

card:add(At.Label({ text = "不确定性进度条", fontSize = 13, color = "#8F98A8" }))
card:add(At.LoadingBar({ w = "100%", h = 10, speed = 1.2 }))

local resetBtn = At.Button({
	w = "48%",
	text = "重置",
	color = "#5A6374",
	onClick = function()
		state.volume = 60
		volumeLabel:setText("音量：60")
		At.log.info("设置已重置")
		setStatus("已重置")
	end,
})

submitBtn = At.Button({
	w = "48%",
	text = "提交",
	color = "#7FA88F",
	onClick = function()
		At.log.info("点击提交按钮")
		setStatus(state.nickname ~= "" and ("已提交：" .. state.nickname) or "请先输入昵称")
	end,
})

card:add(At.Panel({
	direction = "row",
	gap = 12,
	children = { resetBtn, submitBtn },
}))

card:add(At.Checkbox({
	text = "记住昵称",
	checked = false,
	onChange = function(checked)
		At.log.info("记住昵称: %s", checked and "是" or "否")
		setStatus(checked and "下次会记住昵称" or "不再记住昵称")
	end,
}))

statusLabel = At.Label({ text = "试试点击、拖动、输入", fontSize = 15, color = "#9FB3D3" })
card:add(statusLabel)

stateLabel = At.Label({ text = "焦点：无", fontSize = 14, color = "#8F98A8" })
card:add(stateLabel)

-- 横向溢出的示例：标签栏比卡片宽，底部滚动条会自动出现
local tagRow = At.Panel({ w = 760, h = 34, direction = "row", gap = 8, padding = 0 })
for i = 1, 8 do
	tagRow:add(At.Label({ text = "标签 " .. i, fontSize = 14, w = 88 }))
end
card:add(At.ScrollView({ w = "100%", h = 46, content = tagRow }))
card:add(At.Label({
	text = "标签栏比卡片宽：左右拖动或滚轮查看，底部滚动条自动出现",
	fontSize = 12,
	color = "#6E7788",
}))

card:add(At.Label({
	text = "点右上角 LOG（或 F1）开关控制台 · C 清空 · F3 背景模糊",
	fontSize = 13,
	color = "#6E7788",
}))

-- ---------- 滚动视口 ----------

local vw, vh, vx = viewportSize()
viewport = At.ScrollView({
	x = vx,
	y = 40,
	w = vw,
	h = vh,
	content = card,
	scrollbar = true,
})

do
	local screenW, screenH = love.graphics.getDimensions()
	logConsole = At.Console({
		x = 20,
		y = 20,
		w = math.min(560, screenW - 40),
		h = math.min(260, screenH - 80),
		title = "At.log 控制台",
		tab = true,
	})
end

function love.load()
	At.font.init(16)

	-- 统一通过 At/config.lua 的配置项设置（也可以直接改 At.config 再 apply）
	At.config.log.level = "debug"
	At.config.log.file = true
	At.config.blur.enabled = true
	At.config.blur.strength = 8
	At.config.apply()

	if At.log.isFileEnabled() and At.config.log.print then
		print("日志文件: " .. tostring(At.log.getFilePath()))
	end

	At.log.info("演示启动，LÖVE %s", tostring(love.getVersion and love.getVersion() or "?"))
	love.graphics.setBackgroundColor(At.color.hexToRGBA("#1B1F27"))
end

function love.update(dt)
	At.update(dt)
end

function love.draw()
	At.blur.beginFrame() -- 启用模糊时把画面收进内部 canvas
	viewport:draw()
	logConsole:draw() -- 控制台最后画，浮在最上层
	At.blur.endFrame()
end

function love.quit()
	At.log.closeFile()
end

function love.focus(focused)
	if not focused then
		At.log.warn("窗口失去焦点，收起软键盘")
		At.clearFocus()
	end
end

function love.resize(screenW, screenH)
	local sizeW, sizeH, offsetX = viewportSize(screenW, screenH)
	viewport:setRect(offsetX, 40, sizeW, sizeH)

	if logConsole then
		logConsole:setSize(math.min(560, screenW - 40), math.min(260, screenH - 80))
		logConsole.x = math.max(0, math.min(screenW - logConsole.w, logConsole.x))
		logConsole.y = math.max(0, math.min(screenH - logConsole.h, logConsole.y))
	end
	if nameInput and nameInput:isFocused() then
		viewport:scrollToVisible(nameInput, 24)
	end
end

function love.mousepressed(x, y, button)
	At.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
	At.mousereleased(x, y, button)
end

function love.wheelmoved(dx, dy)
	At.wheelmoved(dx, dy)
end

function love.textinput(text)
	At.textinput(text)
end

function love.keypressed(key)
	if key == "f3" then
		At.blur.enabled = not At.blur.isEnabled()
		At.log.info("背景模糊: %s", At.blur.isEnabled() and "开启" or "关闭")
		return
	elseif key == "f1" then
		logConsole:toggle()
		return
	elseif key == "f2" then
		logConsole:clear()
		At.log.info("日志已清空")
		return
	end
	At.keypressed(key)
end
