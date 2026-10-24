local At = require("At.At")

-- 演示：一张卡片里的表单，由 ScrollView + Panel 排版。
-- 窗口再小也能滚动看全；开关可以点，也可以左右拖动。

-- 默认跟随系统明暗（LÖVE 12+ 且桌面支持时）；不支持则退回深色。
local initialSystemMode = At.system.getThemeMode()
local initialAppearance = (initialSystemMode == "light" or initialSystemMode == "dark") and "system" or "dark"
local lastSystemMode = initialSystemMode
local systemOS = love.system and love.system.getOS and love.system.getOS() or ""
local showGtkQt = systemOS == "Linux" or systemOS == "FreeBSD"
local CONTENT_WIDTH = 420

local state = {
	ripples = true,
	quality = 2,
	volume = 60,
	angle = 45,
	nickname = "",
	appearance = initialAppearance, -- system / dark / light
	themeColor = "A7DCFF",
	themeSource = "默认",
}

local card, viewport, statusLabel, volumeLabel, stateLabel
local volumeProgress
local angleLabel, angleDial, angleSwitch
local themeStateLabel
local submitBtn, nameInput, logConsole

local function setStatus(text)
	if statusLabel then
		statusLabel:setText(text)
	end
end

-- 背景跟随主题的深色槽位；换主题后重新取一次
local function syncBackground()
	local r, g, b = At.color.hexToRGBA("@background")
	love.graphics.setBackgroundColor(r, g, b)
end

local function resolvedAppearance()
	if state.appearance == "light" or state.appearance == "dark" then
		return state.appearance, "manual"
	end
	local mode, reason = At.system.getThemeMode()
	if mode == "light" or mode == "dark" then
		return mode, "system"
	end
	return "dark", reason or "unsupported"
end

local function themeStateText()
	local mode, reason = resolvedAppearance()
	local label = mode == "light" and "白色" or "深色"
	if state.appearance ~= "system" then
		return "外观：" .. label
	end
	if reason == "system" then
		return string.format("外观：系统（%s）", label)
	elseif reason == "unsupported" then
		return "外观：LÖVE/桌面不支持系统主题，使用深色"
	elseif reason == "unknown" then
		return "外观：系统主题未知，使用深色"
	end
	return "外观：系统主题读取失败，使用深色"
end

-- 同时更新主题 token 与 At/config 的 theme 段，避免 love.load 里的 apply() 把它冲掉
local function applyTheme()
	local mode, reason = resolvedAppearance()
	local light = mode == "light"
	-- 浅色主题不是简单把黑色槽位设成纯白：页面用柔和冷灰，卡片保持纯白；
	-- 这样卡片/输入框/边框才有层次，也不会出现“整页一张白纸”的感觉。
	local black = light and "EEF1F5" or "3D3D3D"
	local white = light and "1F2329" or "FFFFFF"

	At.config.theme.color = state.themeColor
	At.config.theme.black = black
	At.config.theme.white = white
	At.theme.set({ color = state.themeColor, black = black, white = white })
	syncBackground()

	if state.appearance == "system" and reason == "system" then
		lastSystemMode = mode
	end
	if card then
		card.background = light and "#FFFFFF" or "@surface"
	end
	if logConsole then
		-- LOG 标签在浅色底部用主题色会太淡，切回正文色
		logConsole.tabTextColor = light and "@text" or "@primary"
	end
	if nameInput then
		-- 浅色输入框底比深色更亮，占位文字用 textMuted 才够清晰
		nameInput.placeholderColor = light and "@textMuted" or "@textFaint"
	end
	if themeStateLabel then
		themeStateLabel:setText(themeStateText() .. " · 主题色：" .. state.themeSource)
	end
end

applyTheme()

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
	-- 内容卡固定宽度，窗口更窄时让外层 ScrollView 出现横向滚动条，
	-- 而不是把固定宽度的行（主题色、系统色、旋钮行）裁掉。
	local w = math.min(CONTENT_WIDTH, math.max(160, screenW - 40))
	local h = math.max(160, screenH - 80)
	return w, h, math.max(10, math.floor((screenW - w) / 2))
end

-- ---------- 卡片内容 ----------

card = At.Panel({
	w = CONTENT_WIDTH,
	h = "auto",
	direction = "column",
	gap = 14,
	padding = 20,
	radius = 16,
	background = "@surface",
	borderColor = "@border",
	shadow = false, -- 想要柔和阴影可改成 { { 0, 0, 0, 0.18 }, 6, 12, 0, 4 }
})
card.background = resolvedAppearance() == "light" and "#FFFFFF" or "@surface"

card:add(At.Label({ text = "At 组件演示", fontSize = 22 }))
card:add(At.Label({
	text = "卡片由 Panel 排版；外层 ScrollView 负责裁剪与滚动，窗口小的时候用滚轮或拖动空白处查看下面的内容，极窄时可用横向滚动查看右侧。",
	wrap = true,
	w = "100%",
	lineHeight = 1.4,
	color = "@textMuted",
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

nameInput.placeholderColor = resolvedAppearance() == "light" and "@textMuted" or "@textFaint"
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
	color = "@textFaint",
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

-- 主题色切换：At.theme 改的是全局 token，下面所有默认配色会立即跟着变
local APPEARANCE_MODES = { "system", "dark", "light" }
local appearanceIndex = state.appearance == "system" and 1 or (state.appearance == "light" and 3 or 2)
local appearanceGroup = At.RadioGroup({
	options = { "系统", "深色", "白色" },
	value = appearanceIndex,
	direction = "row",
	gap = 16,
	onChange = function(index, label)
		state.appearance = APPEARANCE_MODES[index]
		applyTheme()
		local mode, reason = resolvedAppearance()
		if state.appearance == "system" and reason ~= "system" then
			setStatus("系统主题不可用，已使用" .. (mode == "light" and "白色" or "深色") .. "主题")
		else
			setStatus("外观：" .. label)
		end
		At.log.info("外观切换为 %s", label)
	end,
})
card:add(At.Panel({
	direction = "row",
	align = "center",
	gap = 12,
	children = {
		At.Label({ text = "外观", fontSize = 13, color = "@textMuted" }),
		appearanceGroup,
	},
}))

themeStateLabel = At.Label({ text = "", fontSize = 12, color = "@textFaint", w = "100%", wrap = true })
themeStateLabel:setText(themeStateText() .. " · 主题色：" .. state.themeSource)
card:add(themeStateLabel)

local themeRow = At.Panel({ direction = "row", align = "center", gap = 8 })
themeRow:add(At.Label({ text = "主题色", fontSize = 13, color = "@textMuted" }))
for _, preset in ipairs({
	{ label = "默认", color = "A7DCFF" },
	{ label = "薄荷", color = "7FE0C4" },
	{ label = "暖橙", color = "FFC08A" },
}) do
	themeRow:add(At.Button({
		w = 64,
		h = 30,
		radius = 8,
		text = preset.label,
		color = preset.color,
		onClick = function()
			state.themeColor = preset.color
			state.themeSource = preset.label
			applyTheme()
			At.log.info("主题色切换为 %s", preset.color)
			setStatus("主题色：" .. preset.label)
		end,
	}))
end
card:add(themeRow)

-- 系统主题色来源：自动 / GTK / Qt（LÖVE 12+；GTK/Qt 按钮只在 Linux 显示）
if At.system.hasThemeApi() then
	local systemColorRow = At.Panel({ direction = "row", align = "center", gap = 8 })
	systemColorRow:add(At.Label({ text = "系统色", fontSize = 13, color = "@textMuted" }))

	local function addSystemColorButton(label, source)
		systemColorRow:add(At.Button({
			w = 58,
			h = 30,
			radius = 8,
			text = label,
			color = "@surfaceStrong",
			onClick = function()
				local accent, actual = At.system.getAccentColor(true, source)
				if accent then
					state.themeColor = accent
					state.themeSource = source and label or ("系统（" .. tostring(actual) .. "）")
					applyTheme()
					At.log.info("系统主题色[%s]: %s (%s)", label, accent, tostring(actual))
					setStatus("系统主题色：" .. tostring(actual))
				else
					At.log.warn("%s 主题色不可用: %s", label, tostring(actual))
					setStatus(label .. " 主题色不可用（" .. tostring(actual) .. "）")
				end
			end,
		}))
	end

	addSystemColorButton("自动", nil)
	if showGtkQt then
		addSystemColorButton("GTK", "gtk")
		addSystemColorButton("Qt", "qt")
	end
	card:add(systemColorRow)
end

-- QDial 风格的圆形旋钮：wrapping 时用完整 360°，越过 359° 从 0° 继续
angleLabel = At.Label({ text = "角度：45°", fontSize = 14, color = "@textMuted" })
angleDial = At.Dial({
	w = 100,
	h = 100,
	min = 0,
	max = 359,
	step = 1,
	value = state.angle,
	wrapping = true,
	notchCount = 12,
	trackWidth = 7,
	showValue = true,
	format = function(value)
		return string.format("%d°", value)
	end,
	onChange = function(value)
		state.angle = value
		angleLabel:setText("角度：" .. value .. "°")
		At.log.debug("旋钮角度: %d", value)
		setStatus("角度：" .. value .. "°")
	end,
})
angleSwitch = At.Switch({
	value = true,
	onChange = function(value)
		angleDial:setWrapping(value)
		At.log.info("旋钮 wrapping: %s", value and "开启" or "关闭")
		setStatus(value and "旋钮可绕回" or "旋钮已限制在端点")
	end,
})
card:add(At.Panel({
	direction = "row",
	align = "center",
	gap = 16,
	children = {
		angleDial,
		At.Panel({
			direction = "column",
			gap = 6,
			children = {
				At.Label({ text = "旋转滑动条（QDial 风格）", fontSize = 15 }),
				angleLabel,
				At.Panel({
					direction = "row",
					align = "center",
					gap = 8,
					children = {
						At.Label({ text = "wrapping", fontSize = 13, color = "@textFaint" }),
						angleSwitch,
					},
				}),
			},
		}),
	},
}))

volumeLabel = At.Label({ text = "音量：" .. state.volume, fontSize = 15, color = "@textMuted" })
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

card:add(At.Label({ text = "确定性进度条（跟随音量）", fontSize = 13, color = "@textFaint" }))
volumeProgress = At.ProgressBar({ w = "100%", h = 10, value = state.volume / 100 })
card:add(volumeProgress)

card:add(At.Label({ text = "不确定性进度条", fontSize = 13, color = "@textFaint" }))
card:add(At.LoadingBar({ w = "100%", h = 10, speed = 1.2 }))

local resetBtn = At.Button({
	w = "48%",
	text = "重置",
	color = "@surfaceStrong",
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
	color = "@primary",
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

statusLabel = At.Label({ text = "试试点击、拖动、输入", fontSize = 15, color = "@primary" })
card:add(statusLabel)

stateLabel = At.Label({ text = "焦点：无", fontSize = 14, color = "@textFaint" })
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
	color = "@textFaint",
}))

card:add(At.Label({
	text = "点右上角 LOG（或 F1）开关控制台 · C 清空 · F3 背景模糊",
	fontSize = 13,
	color = "@textFaint",
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
	logConsole.tabTextColor = resolvedAppearance() == "light" and "@text" or "@primary"
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
	At.log.info("MSAA: 窗口 %d / 设备上限 %d", At.render.getMSAA(), At.render.getMaxMSAA())
	love.graphics.setBackgroundColor(At.color.hexToRGBA("@background"))
end

function love.update(dt)
	if state.appearance == "system" then
		local mode = At.system.getThemeMode()
		if (mode == "light" or mode == "dark") and mode ~= lastSystemMode then
			lastSystemMode = mode
			applyTheme()
			setStatus("系统外观已切换为" .. (mode == "light" and "白色" or "深色"))
			At.log.info("系统外观切换为 %s", mode)
		end
	end
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
