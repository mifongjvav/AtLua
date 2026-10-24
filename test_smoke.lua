-- 无头冒烟测试：用假的 love 环境跑组件逻辑，不需要 LÖVE 运行时。
--
--   lua test_smoke.lua      -- 在项目根目录执行，全部通过会打印 SMOKE OK
--
-- 覆盖：组件注册/事件分发、命中与圆角边界、按压会话（拖出/拖回）、
-- 涟漪生成与回收、帧率无关性、主题 token 与热切换、旧 API 兼容、演示程序回调接线。
-- 只做逻辑回归，不验证真实渲染效果。不会被打包进 .love。
package.path = "./?.lua;" .. package.path
unpack = table.unpack -- 兼容 LÖVE(LuaJIT) 的 unpack，系统 Lua 5.2+ 没有它

local mouseX, mouseY = 0, 0
local scissor = nil
local colorState = { 1, 1, 1, 1 }
local currentFont = nil
local draws = { rect = 0, print = 0, line = 0, circle = 0 }
local textInputOn = false
local lineWidth = 1
local lineStyle = "smooth"
local lastPrint = nil
local mouseDown = false
local textInputRect = nil
local currentCanvas = nil
local shiftDown = false
local canvasCalls = {}
local windowMSAAValue = 4

local function makeFont(size)
	return {
		size = size,
		setFallbacks = function(self, fallback)
			self.fallback = fallback
		end,
		getWidth = function(_, s)
			return #s * size * 0.5
		end,
		getHeight = function()
			return size
		end,
		getWrap = function(_, s, limit)
			return limit, { s }
		end,
	}
end

love = {
	graphics = {
		setColor = function(r, g, b, a)
			colorState = { r, g, b, a }
		end,
		getColor = function()
			return colorState[1], colorState[2], colorState[3], colorState[4]
		end,
		setFont = function(f)
			currentFont = f
		end,
		getFont = function()
			return currentFont or makeFont(16)
		end,
		newFont = function(_, size)
			return makeFont(size)
		end,
		rectangle = function()
			draws.rect = draws.rect + 1
		end,
		print = function(text, x, y)
			draws.print = draws.print + 1
			lastPrint = { text = text, x = x, y = y }
		end,
		printf = function()
			draws.print = draws.print + 1
		end,
		line = function()
			draws.line = (draws.line or 0) + 1
		end,
		circle = function()
			draws.circle = (draws.circle or 0) + 1
		end,
		setLineWidth = function(w)
			lineWidth = w
		end,
		getLineWidth = function()
			return lineWidth
		end,
		setLineStyle = function(style)
			lineStyle = style
		end,
		getLineStyle = function()
			return lineStyle
		end,
		setScissor = function(x, y, w, h)
			if x == nil then
				scissor = nil
			else
				scissor = { x, y, w, h }
			end
		end,
		getScissor = function()
			if scissor then
				return scissor[1], scissor[2], scissor[3], scissor[4]
			end
			return nil
		end,
		setBackgroundColor = function() end,
		getBackgroundColor = function()
			return 0.1, 0.1, 0.1, 1
		end,
		draw = function()
			draws.draw = (draws.draw or 0) + 1
		end,
		clear = function() end,
		setCanvas = function(canvas)
			currentCanvas = canvas
		end,
		getCanvas = function()
			return currentCanvas
		end,
		newCanvas = function(w, h, settings)
			canvasCalls[#canvasCalls + 1] = settings
			return {
				width = w,
				height = h,
				msaa = settings and settings.msaa,
				getMSAA = function(canvas)
					return canvas.msaa or 1
				end,
				getWidth = function()
					return w
				end,
				getHeight = function()
					return h
				end,
				getDimensions = function()
					return w, h
				end,
				setFilter = function() end,
				release = function() end,
			}
		end,
		newShader = function()
			return { send = function() end }
		end,
		newQuad = function(qx, qy, qw, qh)
			return { x = qx, y = qy, w = qw, h = qh }
		end,
		setShader = function() end,
		getShader = function()
			return nil
		end,
		stencil = function() end,
		setStencilTest = function() end,
		push = function() end,
		pop = function() end,
		translate = function() end,
		setBlendMode = function() end,
		getDimensions = function()
			return 800, 600
		end,
		getWidth = function()
			return 800
		end,
		getHeight = function()
			return 600
		end,
		getSystemLimits = function()
			return { msaa = 8 }
		end,
	},
	mouse = {
		getPosition = function()
			return mouseX, mouseY
		end,
		isDown = function(button)
			return mouseDown and button == 1
		end,
	},
	window = {
		getMode = function()
			return 800, 600, { msaa = windowMSAAValue }
		end,
		setMode = function(w, h, flags)
			windowMSAAValue = flags and flags.msaa or 0
			return true
		end,
	},
	keyboard = {
		setTextInput = function(enabled, x, y, w, h)
			textInputOn = enabled and true or false
			textInputRect = { x, y, w, h }
		end,
		isDown = function(key)
			return shiftDown and (key == "lshift" or key == "rshift")
		end,
	},
}

local At = require("At.At")
At.log.setPrint(false) -- 测试期间不要污染 stdout（镜像能力单独断言）
At.config.log.print = false -- 防止之后 config.apply() 又把镜像打开

local function check(cond, msg)
	if not cond then
		error("FAIL: " .. msg, 2)
	end
end

-- ---------- 字体 ----------
At.font.init(16)
check(love.graphics.getFont() ~= nil, "font.init 设置了当前字体")
check(At.font.get(16) == At.font.get(16), "font.get 按字号缓存")
check(At.font.get(16) ~= At.font.get(20), "不同字号不同字体")
check(love.graphics.getFont() == At.font.get(16), "当前字体是主字体（数字/空格不会被 emoji 撑宽）")
check(At.font.get(16).fallback ~= nil, "emoji 字体作为回退")

-- ---------- 颜色 ----------
local light = At.color.shade("#808080", 0.1)
local dark = At.color.shade("#808080", -0.12)
check(light == "#8D8D8D", "shade 调亮: " .. light)
check(dark == "#717171", "shade 调暗: " .. dark)

-- ---------- 主题 ----------
check(At.theme.color == "#A7DCFF", "主题色默认 A7DCFF: " .. At.theme.color)
check(At.theme.primary == "#A7DCFF", "primary 是 color 的只读别名")
check(At.theme.black == "#3D3D3D", "黑色默认 3D3D3D: " .. At.theme.black)
check(At.theme.white == "#FFFFFF", "白色默认 FFFFFF: " .. At.theme.white)
check(At.theme.get("@primary") == "#A7DCFF", "primary token 解析")
check(At.theme.get("primary") == "#A7DCFF", "token 可不带 @")
check(At.theme.get("@theme") == "#A7DCFF", "@theme 是 primary 别名")
check(At.theme.get("@primaryDark") == At.color.shade("#A7DCFF", -0.82), "primaryDark 是深色主题色")
check(At.theme.get("@background") == "#3D3D3D", "background 取黑色槽位")
check(At.theme.get("@text") == "#FFFFFF", "text 取白色槽位")
check(At.theme.get("@surface") == At.color.mix("#3D3D3D", "#FFFFFF", 0.06), "surface 由基色派生")
check(At.color.resolve("@textMuted") == At.theme.get("@textMuted"), "color.resolve 解析 token")
check(At.color.resolve("A7DCFF") == "A7DCFF", "普通 hex 原样返回")

local r, g, b = At.color.hexToRGBA("@primary")
check(
	math.abs(r - 167 / 255) < 1e-9 and math.abs(g - 220 / 255) < 1e-9 and math.abs(b - 1) < 1e-9,
	"token 可用于 hexToRGBA"
)

-- 组件默认色是 token，改主题后无需重建组件
local themeBtn = At.Button({ text = "主题", w = 80, h = 32 })
check(themeBtn.color == "@primary", "按钮默认底色是 @primary")
check(themeBtn:fillColor() == "#A7DCFF", "按钮默认取当前主题色")
At.config.theme.color = "00AAFF"
At.config.apply()
check(At.theme.color == "#00AAFF", "config.apply 把 theme 配置推给 At.theme")
At.config.theme.color = "A7DCFF"
At.config.apply()
check(At.theme.color == "#A7DCFF", "主题配置复位")
At.theme.set({ color = "112233" })
check(At.theme.get("@primary") == "#112233", "set 后主题色更新")
check(themeBtn:fillColor() == "#112233", "已有组件跟着主题更新")
check(At.theme.get("@background") == "#3D3D3D", "只改主题色不影响黑色槽位")
check(At.theme.get("@onPrimary") == "#FFFFFF", "深色主题色自动用白字")
At.theme.reset()
check(At.theme.get("@onPrimary") == "#3D3D3D", "浅色主题色自动用深色字")
At.theme.set({ black = "FFFFFF", white = "3D3D3D" })
check(At.theme.get("@background") == "#FFFFFF", "浅色主题背景取黑色槽位")
check(At.theme.get("@text") == "#3D3D3D", "浅色主题文字取白色槽位")
check(At.theme.get("@onPrimary") == "#3D3D3D", "浅色主题下主题色仍用深色字")
At.theme.reset()
check(themeBtn:fillColor() == "#A7DCFF", "reset 后恢复默认主题色")
check(At.theme.get("@surface") ~= At.theme.get("@surfaceStrong"), "不同派生 token 有区分度")
check(At.theme.foreground("@primary") == "#3D3D3D", "浅色主题色上的前景是深色")
check(At.theme.foreground("@surfaceStrong") == "#FFFFFF", "深色表面上的前景是白色")
check(not pcall(function()
	At.theme.set({ color = "not-a-color" })
end), "非法主题色会报错")
At.theme.reset()

-- ---------- 渲染 / MSAA ----------
check(At.render.getMSAA() == 4, "窗口默认 MSAA 为 4")
check(At.render.getMaxMSAA() == 8, "设备最大 MSAA 为 8")
At.config.render.msaa = 2
At.config.apply()
check(At.render.getMSAA() == 2, "config.render.msaa 可以改 MSAA")
check(windowMSAAValue == 2, "setMode 收到新的 msaa")
At.config.render.msaa = 4
At.config.apply()
check(At.render.getMSAA() == 4, "MSAA 配置可复位")
check(At.render.setMSAA(99) == 8, "超过上限的 MSAA 被夹到设备上限")
At.render.setMSAA(4)
check(At.render.getMSAA() == 4, "setMSAA 可恢复")
themeBtn:destroy()

-- ---------- 按钮基本行为 ----------
local clicks, presses, releases = 0, 0, 0
local btn = At.Button({
	x = 100,
	y = 100,
	w = 160,
	h = 60,
	radius = 12,
	text = "OK",
	fontSize = 16,
	onPress = function()
		presses = presses + 1
	end,
	onRelease = function()
		releases = releases + 1
	end,
	onClick = function()
		clicks = clicks + 1
	end,
})
check(At.registry.contains(btn), "创建即自动登记")
check(btn:contains(150, 130), "中心点命中")
check(not btn:contains(20, 20), "外部点不命中")
check(not btn:contains(101, 101), "圆角角落不算命中")

mouseX, mouseY = 150, 130
At.update(1 / 60)
btn:draw()
check(draws.rect > 0 and draws.print > 0, "draw 画了矩形和文字")
check(colorState[1] == 1 and colorState[4] == 1, "draw 还原了颜色状态")
check(love.graphics.getFont() ~= nil, "draw 后字体仍可用")

-- 点外部：事件穿透
check(At.mousepressed(10, 10, 1) == false, "点空白不消费事件")
check(btn:isPressed() == false, "未按下")

-- 点内部：消费事件、产生涟漪
check(At.mousepressed(150, 130, 1) == true, "点按钮消费事件")
check(btn:isPressed(), "按下状态")
check(btn:isHovered(), "悬停状态")
check(btn:rippleCount() == 1, "按下产生涟漪")
check(presses == 1, "触发 onPress")

-- 拖出按钮：按下态消失、涟漪淡出
mouseX, mouseY = 600, 600
At.update(1 / 60)
check(not btn:isPressed(), "拖出后不算按下态")
check(btn:rippleCount() >= 1, "拖出后涟漪进入淡出（尚未回收）")

-- 拖回来松开：仍算点击
mouseX, mouseY = 150, 130
At.update(1 / 60)
check(btn:isPressed(), "拖回按钮内恢复按下态")
At.mousereleased(150, 130, 1)
check(clicks == 1, "拖回后松开触发 onClick")
check(releases == 1, "onRelease 触发一次")

-- 拖出去再松开：不触发点击
mouseX, mouseY = 150, 130
At.mousepressed(150, 130, 1)
mouseX, mouseY = 600, 600
At.update(1 / 60)
check(At.mousereleased(600, 600, 1) == false, "拖出后松开不算点击")
check(clicks == 1, "拖出不触发 onClick")
check(releases == 2, "取消也走 onRelease(inside=false)")
check(btn:rippleCount() >= 1, "拖出后涟漪在淡出")

-- 正常点击（鼠标坐标在按钮内）
mouseX, mouseY = 150, 130
At.mousepressed(150, 130, 1)
At.mousereleased(150, 130, 1)
check(clicks == 2, "点击触发 onClick")
check(releases == 3, "每次松开都触发 onRelease")
check(not btn:isPressed(), "松开后复位")

-- 涟漪最终回收
for _ = 1, 240 do
	At.update(1 / 60)
end
check(btn:rippleCount() == 0, "涟漪淡出后被回收")

-- ---------- 涟漪帧率无关性 ----------
local fx60 = At.Ripple.new()
local fx120 = At.Ripple.new()
fx60:add(0, 0, 100, 100, 100, 50, 10)
fx120:add(0, 0, 100, 100, 100, 50, 10)
fx60:release()
fx120:release()
for _ = 1, 60 do
	fx60:update(1 / 60)
end
for _ = 1, 120 do
	fx120:update(1 / 120)
end
local a60 = fx60.ripples[1] and fx60.ripples[1].alpha or 0
local a120 = fx120.ripples[1] and fx120.ripples[1].alpha or 0
check(math.abs(a60 - a120) < 0.02, "1s 后透明度与帧率无关: " .. a60 .. " vs " .. a120)

-- ---------- 旧单例 API 兼容 ----------
At.Ripple.add(1, 1, 0, 0, 50, 20, 4)
check(At.Ripple.count() == 1, "旧 Ripple.add 可用")
At.Ripple.release() -- 不松手的涟漪不会被回收（与旧实现一致）
for _ = 1, 240 do
	At.Ripple.update()
end
check(At.Ripple.count() == 0, "旧 Ripple.update 回收")
At.Ripple.setEnabled(false)
check(At.Ripple.add(1, 1, 0, 0, 50, 20, 4) == false, "旧 Ripple.setEnabled 生效")
At.Ripple.setEnabled(true)

-- ---------- 旧立即模式 ----------
local rect = At.button(10, 10, 50, 20, 4, "#000000", 255, true, { { 0, 0, 0, 0.2 }, 5, 20, 2, 3 })
check(rect.w == 50 and rect.radius == 4, "旧 At.button 仍返回矩形表")

-- ---------- 禁用 / 销毁 ----------
local disabled = At.Button({ x = 0, y = 0, w = 50, h = 50, enabled = false, text = "X" })
disabled:draw()
check(At.mousepressed(10, 10, 1) == false, "禁用按钮不消费事件")
check(disabled:rippleCount() == 0, "禁用按钮不产生涟漪")

local temp = At.Button({ x = 700, y = 700, w = 50, h = 50 })
check(At.registry.contains(temp), "临时按钮已登记")
temp:destroy()
check(not At.registry.contains(temp), "destroy 后注销")
check(At.mousepressed(710, 710, 1) == false, "注销后不再接收事件")

-- ---------- 输入模块 ----------
At.input.setActive(true)
check(At.input.isActive() and textInputOn, "setActive(true) 打开文本输入")
At.input.set("abc")
At.input.join("d")
check(At.input.get() == "abcd", "set/join 拼接")
At.input.clear()
check(At.input.get() == "", "clear 清空")
At.input.keypressed("backspace")
check(At.input.get() == "", "空串退格不报错")
At.input.join("你")
At.input.join("好")
At.input.keypressed("backspace")
check(At.input.get() == "你", "退格按 UTF-8 码点删除")
At.input.keypressed("return")
check(not At.input.isActive(), "回车退出输入态")
At.input.input()
check(At.input.isActive(), "旧 input() 仍可切换")

-- ---------- 样式解析 ----------
local styled = At.Button({ x = 0, y = 0, w = 10, h = 10, color = "#808080" })
styled._hover = true
check(styled:fillColor() == "#8D8D8D", "悬停色由 shade 推导: " .. styled:fillColor())
styled._pressed = true
check(styled:fillColor() == "#717171", "按下色由 shade 推导: " .. styled:fillColor())
styled._hover, styled._pressed = false, false
styled:setEnabled(false)
check(styled:fillAlpha() < styled.alpha, "禁用降低透明度")
styled:destroy()

-- ---------- 布局引擎 ----------
At.registry.clear()

local function approx(a, b, eps)
	return math.abs(a - b) < (eps or 1e-6)
end

check(At.layout.pixels(120) == 120, "pixels 数字")
check(At.layout.pixels("50%", 300) == 150, "pixels 百分比")
check(At.layout.pixels("auto") == nil, "pixels auto")
check(At.layout.pixels("120") == 120, "pixels 数字字符串")
local sl1, st1, sr1, sb1 = At.layout.sides({ left = 1, top = 2 })
check(sl1 == 1 and st1 == 2 and sr1 == 0 and sb1 == 0, "sides 具名表")
local sl2, st2, sr2, sb2 = At.layout.sides(4)
check(sl2 == 4 and st2 == 4 and sr2 == 4 and sb2 == 4, "sides 数字")

-- 列方向：gap + padding + auto 高度
local col = At.Panel({
	x = 100,
	y = 50,
	w = 200,
	h = "auto",
	direction = "column",
	gap = 10,
	padding = 10,
	children = {
		At.Label({ text = "A", fontSize = 10 }),
		At.Label({ text = "BB", fontSize = 10 }),
	},
})
col:draw()
check(approx(col.h, 54), "列方向 auto 高度 = 12+10+12+20: " .. col.h)
check(approx(col.children[1].y, 60), "第一个子项 y")
check(approx(col.children[2].y, 82), "第二个子项 y")
check(approx(col.children[1].w, 5), "Label auto 宽度")
check(approx(col.children[1].x, 110), "左边距 + padding")

-- 行方向 + 百分比
local rowPct = At.Panel({
	x = 0,
	y = 0,
	w = 200,
	h = 40,
	direction = "row",
	gap = 0,
	padding = 0,
	children = { At.Label({ text = "x", w = "50%", fontSize = 10 }) },
})
rowPct:draw()
check(approx(rowPct.children[1].w, 100), "百分比宽度: " .. rowPct.children[1].w)

-- grow：主轴上瓜分剩余空间
local rowGrow = At.Panel({
	x = 0,
	y = 0,
	w = 200,
	h = 40,
	direction = "row",
	gap = 10,
	padding = 0,
	children = {
		At.Button({ w = 50, h = 40, text = "" }),
		At.Button({ w = "auto", h = 40, grow = 1, text = "b", fontSize = 10 }),
	},
})
rowGrow:draw()
check(approx(rowGrow.children[2].w, 140), "grow 撑满剩余: " .. rowGrow.children[2].w)

-- 交叉轴居中
local centered = At.Panel({
	x = 0,
	y = 0,
	w = 100,
	h = 30,
	direction = "column",
	align = "center",
	children = { At.Label({ text = "x", w = 40, h = 10, fontSize = 10 }) },
})
centered:draw()
check(approx(centered.children[1].x, 30), "align center: " .. centered.children[1].x)

-- 主轴居中（justify）
local justified = At.Panel({
	x = 0,
	y = 0,
	w = 50,
	h = 100,
	direction = "column",
	justify = "center",
	children = { At.Label({ text = "x", w = 10, h = 20, fontSize = 10 }) },
})
justified:draw()
check(approx(justified.children[1].y, 40), "justify center: " .. justified.children[1].y)

-- margin 与嵌套容器
local outer = At.Panel({
	x = 10,
	y = 10,
	w = "auto",
	h = "auto",
	padding = 5,
	children = {
		At.Panel({
			direction = "row",
			gap = 6,
			padding = 0,
			children = {
				At.Label({ text = "aa", fontSize = 10 }),
				At.Label({ text = "bb", fontSize = 10 }),
			},
		}),
		At.Label({ text = "z", fontSize = 10, margin = { left = 4 } }),
	},
})
outer:draw()
check(approx(outer.w, 10 + 6 + 10 + 10), "嵌套容器 auto 宽度: " .. outer.w)
check(approx(outer.children[2].x, 15 + 4), "margin.left 生效")
check(approx(outer.children[1].children[2].x, 15 + 10 + 6), "嵌套行方向排布")

-- 重排不会把 auto 尺寸固化死
local relayout = At.Panel({
	x = 0,
	y = 0,
	w = 100,
	h = "auto",
	padding = 0,
	children = { At.Label({ text = "abc", fontSize = 10 }) },
})
relayout:draw()
check(approx(relayout.h, 12), "首次排版高度")
relayout.children[1]:setText("abcdef")
relayout:draw()
check(approx(relayout.h, 12), "高度仍是单行")
check(relayout.children[1].w == 30, "文字变长后重新测量: " .. relayout.children[1].w)

-- ---------- TextInput ----------
At.registry.clear()

local typed, submitted
local ti = At.TextInput({
	x = 10,
	y = 10,
	w = 200,
	h = 40,
	onChange = function(text)
		typed = text
	end,
	onSubmit = function(text)
		submitted = text
	end,
})

mouseX, mouseY = 20, 20
check(At.mousepressed(20, 20, 1) == true, "输入框消费点击")
At.mousereleased(20, 20, 1)
check(ti:isFocused(), "点击后获得焦点")
check(textInputOn == true, "聚焦时启用文本输入（唤起软键盘）")
check(
	textInputRect ~= nil and textInputRect[3] == ti.w and textInputRect[4] == ti.h,
	"把输入框矩形传给 setTextInput，系统据此定位软键盘"
)

At.textinput("你")
At.textinput("好")
check(ti:getText() == "你好", "文本输入追加")
check(typed == "你好", "onChange 收到新值")
At.keypressed("backspace")
check(ti:getText() == "你", "退格按 UTF-8 码点删除")
At.keypressed("return")
check(submitted == "你", "回车触发 onSubmit")

ti.maxLength = 2
ti:setText("ab", true)
check(At.textinput("c") == false and ti:getText() == "ab", "超过 maxLength 被拒绝")

ti:draw()
check(draws.print > 0, "输入框绘制了文字")

mouseX, mouseY = 600, 600
check(At.mousepressed(600, 600, 1) == false, "点空白不消费")
check(not ti:isFocused(), "点空白失焦")
check(textInputOn == false, "失焦时关闭文本输入（收起软键盘）")

-- 输入框绘制不应泄漏 scissor
mouseX, mouseY = 20, 20
At.mousepressed(20, 20, 1)
ti:draw()
check(love.graphics.getScissor() == nil, "绘制后 scissor 已恢复")

-- 光标定位、中间插入与删除
ti:destroy()
At.registry.clear()
local caretTi = At.TextInput({ x = 100, y = 100, w = 200, h = 40, text = "abcd", fontSize = 16 })
mouseX, mouseY = 125, 110
check(At.mousepressed(125, 110, 1) == true, "点击输入框")
At.mousereleased(125, 110, 1)
check(caretTi:getCaret() == 2, "点击字符中间定位光标: " .. caretTi:getCaret())
At.keypressed("backspace")
check(caretTi:getText() == "acd" and caretTi:getCaret() == 1, "中间退格删除光标前字符")
At.textinput("X")
check(caretTi:getText() == "aXcd" and caretTi:getCaret() == 2, "在光标处插入字符")
At.keypressed("delete")
check(caretTi:getText() == "aXd" and caretTi:getCaret() == 2, "delete 删除光标后字符")
At.keypressed("home")
check(caretTi:getCaret() == 0, "home 移到开头")
At.keypressed("right")
check(caretTi:getCaret() == 1, "right 右移一位")
At.keypressed("end")
check(caretTi:getCaret() == 3, "end 移到末尾")
At.keypressed("left")
check(caretTi:getCaret() == 2, "left 左移一位")
caretTi:setText("abcdefghijklmnopqrstuvwxyz", true)
caretTi:setCaret(26)
caretTi:draw()
check(caretTi._scrollX > 0, "长文本下光标保持在可视区")
caretTi:setCaret(0)
check(caretTi:getCaret() == 0, "setCaret 可设置光标位置")
check(At.input.sub("你好abc", 2, 3) == "好a", "input.sub 按字符取子串")
caretTi:destroy()

-- ---------- Switch ----------
At.registry.clear()

local swValue
local sw = At.Switch({
	x = 0,
	y = 0,
	value = false,
	onChange = function(value)
		swValue = value
	end,
})

check(sw.value == false, "开关初始关闭")
mouseX, mouseY = 10, 10
At.mousepressed(10, 10, 1)
At.mousereleased(10, 10, 1)
check(sw.value == true and swValue == true, "点击后打开")

for _ = 1, 60 do
	sw:update(1 / 60)
end
check(sw._t > 0.95, "打开动画收敛: " .. sw._t)

sw:setValue(false)
check(sw._t > 0.5, "刚关闭时旋钮还没走完: " .. sw._t)
sw:draw()

-- 左右拖动开关
sw:setValue(false)
mouseX, mouseY = 26, 14
At.mousepressed(26, 14, 1)
check(sw.value == false, "按下本身不切换")
mouseX = 46
sw:update(1 / 60)
check(sw.value == true, "向右拖打开")
mouseX = 26
sw:update(1 / 60)
At.mousereleased(26, 14, 1)
check(sw.value == true, "拖动后松手不再二次切换")

mouseX = 26
At.mousepressed(26, 14, 1)
mouseX = 6
sw:update(1 / 60)
check(sw.value == false, "向左拖关闭")
At.mousereleased(6, 14, 1)

-- 轻点仍然是点击语义
sw:setValue(false)
mouseX, mouseY = 26, 14
At.mousepressed(26, 14, 1)
At.mousereleased(26, 14, 1)
check(sw.value == true, "没拖动时按点击切换")

-- ---------- Checkbox ----------
At.registry.clear()

local cbValue
local cb = At.Checkbox({
	x = 0,
	y = 0,
	text = "记住我",
	onChange = function(value)
		cbValue = value
	end,
})

check(cb.checked == false, "多选框初始未选")
mouseX, mouseY = 5, 5
At.mousepressed(5, 5, 1)
At.mousereleased(5, 5, 1)
check(cb.checked == true and cbValue == true, "点击后勾选")
cb:draw()
check(draws.line > 0, "勾选画了线段")

-- ---------- RadioGroup ----------
At.registry.clear()

local rgValue
local rg = At.RadioGroup({
	x = 0,
	y = 0,
	options = { "A", "B", "C" },
	value = 1,
	gap = 4,
	size = 20,
	textGap = 8,
	onChange = function(index, label)
		rgValue = tostring(index) .. label
	end,
})

check(approx(rg:_itemHeight(), 20), "选项高度取 size 与字高较大值")
mouseX, mouseY = 5, 30
At.mousepressed(5, 30, 1)
At.mousereleased(5, 30, 1)
check(rg.value == 2 and rgValue == "2B", "点击第二个选项: " .. tostring(rg.value))

At.mousepressed(5, 30, 1)
At.mousereleased(5, 30, 1)
check(rg.value == 2, "重复点同一项不触发变更")
rg:draw()
check(draws.circle > 0, "单选框画了圆")

local rgRow = At.RadioGroup({
	x = 0,
	y = 100,
	options = { "a", "b" },
	direction = "row",
	gap = 10,
})
rgRow:draw()
check(rgRow.children == nil, "RadioGroup 不持有子组件")
check(approx(rgRow.w, (20 + 8 + 8) * 2 + 10), "横排 auto 宽度: " .. rgRow.w)

-- ---------- Slider ----------
At.registry.clear()

local slValue
local sl = At.Slider({
	x = 0,
	y = 0,
	w = 200,
	h = 28,
	min = 0,
	max = 100,
	step = 5,
	value = 0,
	onChange = function(value)
		slValue = value
	end,
})

mouseX, mouseY = 100, 14
At.mousepressed(100, 14, 1)
check(sl.value == 50 and slValue == 50, "点击轨道跳到中点并吸附: " .. tostring(sl.value))
check(sl:isFocused(), "滑动条获得焦点")

mouseDown = true
mouseX, mouseY = 191, 14
sl:update(1 / 60)
check(sl.value == 100, "拖到最右: " .. tostring(sl.value))

mouseDown = false
sl:update(1 / 60)
check(sl._dragging == false, "松开鼠标停止拖动")
At.mousereleased(191, 14, 1)

At.keypressed("left")
check(sl.value == 95, "方向键微调: " .. tostring(sl.value))
At.keypressed("right")
check(sl.value == 100, "方向键上限")

sl:draw()

-- 步长吸附
local slStep = At.Slider({ x = 0, y = 0, min = 0, max = 10, step = 3, value = 0 })
slStep:setValue(7)
check(slStep.value == 6, "按 step 吸附: " .. tostring(slStep.value))
slStep:setValue(100)
check(slStep.value == 9, "clamp 到能取到的最大值: " .. tostring(slStep.value))

-- ---------- Dial ----------
At.registry.clear()

local dialValue
local dial = At.Dial({
	x = 0,
	y = 0,
	w = 200,
	h = 200,
	min = 0,
	max = 100,
	step = 0,
	value = 0,
	notchCount = 9,
	onChange = function(value)
		dialValue = value
	end,
})

-- 顶部是 50%，左下起点是 0%，右下终点是 100%
At.mousepressed(100, 5, 1)
At.mousereleased(100, 5, 1)
check(approx(dial.value, 50) and approx(dialValue, 50), "Dial 点击顶部映射到 50%")
At.mousepressed(50, 150, 1)
At.mousereleased(50, 150, 1)
check(approx(dial.value, 0), "Dial 点击起点映射到 min")
At.mousepressed(150, 150, 1)
At.mousereleased(150, 150, 1)
check(approx(dial.value, 100), "Dial 点击终点映射到 max")

-- 按住拖动：从顶部拖到右侧
At.mousepressed(100, 5, 1)
mouseDown = true
mouseX, mouseY = 195, 100
dial:update(1 / 60)
check(math.abs(dial.value - 83.333333) < 0.01, "Dial 拖动跟随鼠标: " .. tostring(dial.value))
mouseDown = false
dial:update(1 / 60)
check(dial._dragging == false, "Dial 松开后停止拖动")
At.mousereleased(195, 100, 1)

dial:setValue(120)
check(dial.value == 100, "Dial 非 wrapping 夹到 max")
dial:setValue(-10)
check(dial.value == 0, "Dial 非 wrapping 夹到 min")
At.keypressed("right")
check(approx(dial.value, 5), "Dial 方向键微调")

dial:draw()
check(draws.circle > 0, "Dial 绘制了圆环/旋钮")

-- wrapping：完整 360°，越过 max 从 min 继续
local wrapped = At.Dial({
	x = 0,
	y = 0,
	w = 200,
	h = 200,
	min = 0,
	max = 359,
	step = 1,
	value = 0,
	wrapping = true,
})
local function pointAt(degrees)
	return 100 + math.cos(math.rad(degrees)) * 80, 100 + math.sin(math.rad(degrees)) * 80
end
local wx, wy = pointAt(136)
At.mousepressed(wx, wy, 1)
At.mousereleased(wx, wy, 1)
check(wrapped.value == 1, "wrapping 起点顺时针一格: " .. tostring(wrapped.value))
local bx, by = pointAt(134)
At.mousepressed(bx, by, 1)
At.mousereleased(bx, by, 1)
check(wrapped.value == 358, "wrapping 起点逆时针一格: " .. tostring(wrapped.value))
wrapped:setValue(360)
check(wrapped.value == 1, "wrapping setValue 越界取模")
wrapped:setValue(-1)
check(wrapped.value == 358, "wrapping setValue 下界取模")
check(wrapped:isWrapping() == true, "Dial isWrapping")
wrapped:setWrapping(false)
wrapped:setValue(360)
check(wrapped.value == 359, "关闭 wrapping 后夹到 max")
wrapped:draw()

-- ---------- Panel 的穿透与排版 ----------
At.registry.clear()

local clicked = 0
local inner = At.Button({
	x = 0,
	y = 0,
	w = 60,
	h = 24,
	text = "in",
	onClick = function()
		clicked = clicked + 1
	end,
})
local wrap = At.Panel({
	x = 0,
	y = 0,
	w = 200,
	h = 100,
	gap = 8,
	padding = 0,
	background = "#222831",
	children = { At.Label({ text = "t", fontSize = 10 }), inner },
})

check(not At.registry.contains(wrap), "Panel 不登记到事件表")
wrap:draw()
check(approx(inner.y, 20), "Panel 把子按钮排到第二行: " .. inner.y)

check(At.mousepressed(20, 30, 1) == true, "容器内的按钮能收到点击")
At.mousereleased(20, 30, 1)
check(clicked == 1, "容器内的按钮点击生效")

-- ---------- ScrollView ----------
At.registry.clear()

local contentPanel = At.Panel({ w = "100%", h = "auto", gap = 10, padding = 10, direction = "column" })
for i = 1, 8 do
	contentPanel:add(At.Label({ text = "行 " .. i, fontSize = 12, w = 60 }))
end

local view = At.ScrollView({ x = 0, y = 0, w = 200, h = 100, content = contentPanel })
view:draw()

check(view:maxScroll() > 0, "内容超出视口可滚动: " .. view:maxScroll())
check(view.scrollY == 0, "初始在顶部")

mouseX, mouseY = 100, 50
check(At.wheelmoved(0, -1) == true, "滚轮被视口消费")
check(view._scrollTarget == 44, "滚轮只设置平滑滚动目标: " .. tostring(view._scrollTarget))
check(view.scrollY == 0, "平滑滚动不会瞬移")
for _ = 1, 60 do
	view:update(1 / 60)
end
check(approx(view.scrollY, 44, 0.6), "平滑滚动收敛到目标: " .. view.scrollY)

-- 连续滚轮按目标累加
view:setScroll(0)
view:scrollBy(20)
view:scrollBy(20)
check(view._scrollTarget == 40, "连续滚动累加目标: " .. tostring(view._scrollTarget))
view:setScroll(0)

-- setScroll 仍然是立即生效（拖拽/滚动条/scrollToVisible 的基础）
view:setScroll(30)
check(view.scrollY == 30, "setScroll 立即生效: " .. view.scrollY)
view:setScroll(0)

-- 空白处拖动（标签只有 60 宽，右侧是空的）
mouseDown = true
mouseX, mouseY = 180, 60
check(At.mousepressed(180, 60, 1) == true, "空白处按下由视口接管")
mouseY = 20
view:update(1 / 60)
check(view.scrollY == 40, "上拖 40 就滚动 40: " .. view.scrollY)
mouseDown = false
view:update(1 / 60)
At.mousereleased(180, 20, 1)

-- 松手惯性
view:setScroll(0)
mouseDown = true
mouseX, mouseY = 180, 90
At.mousepressed(180, 90, 1)
mouseY = 70
view:update(1 / 60)
check(view.scrollY == 20, "拖动仍然 1:1 跟手: " .. view.scrollY)

mouseDown = false
At.mousereleased(180, 70, 1)
for _ = 1, 5 do
	view:update(1 / 60)
end
check(view.scrollY > 20, "松手后惯性继续滚动: " .. view.scrollY)

for _ = 1, 180 do
	view:update(1 / 60)
end
check(view._scrollVelocity == 0, "惯性最终停止")

-- smooth = false 时立即到位
local instantView = At.ScrollView({
	x = 0,
	y = 0,
	w = 200,
	h = 60,
	content = contentPanel,
	smooth = false,
})
instantView:layout()
instantView:scrollTo(30)
check(instantView.scrollY == 30, "smooth = false 时直接到位: " .. instantView.scrollY)
instantView.content = nil -- 内容与 view 共用，别连带销毁
instantView:destroy()

-- Label 是被动组件：压在文字上也能拖动滚动
view:setScroll(0)
local firstLabel = contentPanel.children[1]
check(firstLabel:isInteractive() == false, "Label 不是可交互组件")

mouseDown = true
mouseX, mouseY = firstLabel.x + 5, firstLabel.y + firstLabel.h / 2
check(At.mousepressed(mouseX, mouseY, 1) == true, "在文字上按下能开始拖动")
check(view._dragging == true, "文字不会挡住容器拖动")
check(firstLabel._pressed ~= true, "文字不记录按下状态")

mouseY = mouseY - 30
view:update(1 / 60)
check(view.scrollY > 0, "在文字上拖动可以滚动: " .. view.scrollY)
mouseDown = false
view:update(1 / 60)
At.mousereleased(mouseX, mouseY, 1)

-- 可交互子组件才拦截拖动
local blockContent = At.Panel({
	w = "100%",
	h = "auto",
	padding = 0,
	children = {
		At.Button({ x = 0, y = 0, w = 100, h = 40, text = "b" }),
	},
})
local blockView = At.ScrollView({ x = 0, y = 0, w = 200, h = 100, content = blockContent })
blockView:draw()

local blockBtn = blockContent.children[1]
check(blockBtn:isInteractive() == true, "Button 是可交互组件")

mouseDown = true
mouseX, mouseY = blockBtn.x + 10, blockBtn.y + 10
At.mousepressed(mouseX, mouseY, 1)
check(blockView._dragging ~= true, "可交互组件上不启动拖动")
mouseDown = false
At.mousereleased(mouseX, mouseY, 1)

blockBtn:destroy()
blockView.content = nil
blockView:destroy()

-- 边界与 scrollToVisible
view:setScroll(10000)
check(view.scrollY == view:maxScroll(), "滚动量夹到最大值")
view:setScroll(0)
view:scrollToVisible(contentPanel.children[1], 0)
check(view.scrollY == 0, "已在可视区时不滚动")

view:draw()
check(love.graphics.getScissor() == nil, "ScrollView 绘制后 scissor 已恢复")

-- ---------- 裁剪求交 ----------
love.graphics.setScissor(0, 0, 100, 100)
local oldClip, clipVisible = At.clip.apply(50, 50, 100, 100)
check(clipVisible == true, "裁剪可见")
local ccx, ccy, ccw, cch = love.graphics.getScissor()
check(ccx == 50 and ccy == 50 and ccw == 50 and cch == 50, "嵌套裁剪应求交而不是覆盖")
At.clip.restore(oldClip)
check(select(1, love.graphics.getScissor()) == 0, "恢复外层裁剪")
love.graphics.setScissor()

love.graphics.setScissor(0, 0, 10, 10)
local _, clipVisible2 = At.clip.apply(100, 100, 10, 10)
check(clipVisible2 == false, "完全在裁剪外时报告不可见")
At.clip.restore(nil)
check(love.graphics.getScissor() == nil, "clip.restore(nil) 关闭裁剪")

-- ---------- 滚动条可拖动 ----------
view:setScroll(0)
view:draw()
local barX, barY, barW, barH, thumbY, thumbH = view:_barMetrics()
check(barH > 0 and thumbH > 0, "滚动条几何有效")

mouseDown = true
mouseX, mouseY = barX + barW / 2, thumbY + thumbH / 2
check(At.mousepressed(mouseX, mouseY, 1) == true, "按在滚动条上由视口接管")
mouseY = barY + barH - 1
view:update(1 / 60)
check(view.scrollY == view:maxScroll(), "拖滚动条到底部: " .. view.scrollY)
mouseDown = false
view:update(1 / 60)
At.mousereleased(barX, barY + barH - 1, 1)
check(view._barDragging == false, "松手后停止拖动滚动条")

-- 点轨道空白处直接跳转
view:setScroll(0)
mouseDown = true
mouseX, mouseY = barX + barW / 2, barY + barH - 2
At.mousepressed(mouseX, mouseY, 1)
mouseDown = false
view:update(1 / 60)
At.mousereleased(mouseX, mouseY, 1)
check(view.scrollY > 0, "点轨道跳转: " .. view.scrollY)

-- ---------- 阴影 ----------
check(At.shadow.getAlgorithm() == "glsl", "阴影默认使用 GLSL")
local shadowBtn = At.Button({ text = "S" })
local shadowDefaults = At.shadow.defaults()
check(shadowBtn.shadowArgs == nil, "默认阴影参数来自 config.shadow")
check(shadowDefaults.color == "@primaryDark", "默认阴影用深色主题色")
check(shadowDefaults.spread == 3 and shadowDefaults.offsetX == 1 and shadowDefaults.offsetY == 2, "默认阴影更小")
shadowBtn:destroy()
At.config.shadow.spread = 2
At.config.apply()
check(At.shadow.defaults().spread == 2, "config.apply 可覆盖阴影大小")
At.config.shadow.spread = 3
At.config.apply()
check(not pcall(At.shadow.setAlgorithm, "nope"), "未知阴影算法报错")
At.config.shadow.algorithm = "legacy"
At.config.apply()
check(At.shadow.getAlgorithm() == "legacy", "config 可切到旧式阴影")

local alphas = {}
local realSetColor = love.graphics.setColor
love.graphics.setColor = function(r, g, b, a)
	alphas[#alphas + 1] = a
	realSetColor(r, g, b, a)
end
At.shadow.shadow(0, 0, 100, 50, 6, { 0, 0, 0, 0.25 }, 6, 20, 0, 4)
love.graphics.setColor = realSetColor

check(#alphas == 21, "旧式阴影按 layers+1 层绘制: " .. #alphas)
local alphaSum = 0
for _, a in ipairs(alphas) do
	alphaSum = alphaSum + a
end
check(alphaSum < 0.6, "旧式阴影透明度按层数归一化: " .. alphaSum)
check(alphaSum > 0.1, "旧式阴影仍然可见: " .. alphaSum)

At.shadow.setAlgorithm("glsl")
local drawBefore = draws.draw
At.shadow.shadow(0, 0, 100, 50, 6, { 0, 0, 0, 0.25 }, 6, 20, 0, 4)
check(draws.draw == drawBefore + 1, "GLSL 阴影只画一次")

-- shader 不可用时自动回退旧实现
local realNewShader = love.graphics.newShader
love.graphics.newShader = nil
At.shadow.reset()
alphas = {}
love.graphics.setColor = function(r, g, b, a)
	alphas[#alphas + 1] = a
	realSetColor(r, g, b, a)
end
At.shadow.shadow(0, 0, 100, 50, 6, { 0, 0, 0, 0.25 }, 6, 20, 0, 4)
love.graphics.setColor = realSetColor
love.graphics.newShader = realNewShader
At.shadow.reset()
check(#alphas == 21, "GLSL 不可用时回退旧式阴影: " .. #alphas)

At.config.shadow.algorithm = "glsl"
At.config.apply()
check(At.shadow.getAlgorithm() == "glsl", "阴影算法可复位")

-- 滚动条悬停变宽
view:setScroll(0)
view:draw()
local baseBarW = select(3, view:_barMetrics())

local hoverX, hoverY = view:_barMetrics()
mouseX, mouseY = hoverX + 2, view.y + view.h / 2
for _ = 1, 40 do
	view:update(1 / 60)
end
local grownBarW = select(3, view:_barMetrics())
check(grownBarW > baseBarW, "指针碰到滚动条后变宽: " .. baseBarW .. " → " .. grownBarW)

mouseX, mouseY = 5, 5
for _ = 1, 60 do
	view:update(1 / 60)
end
check(select(3, view:_barMetrics()) < grownBarW, "移开后滚动条恢复宽度")

-- ---------- 横向滚动 ----------
At.registry.clear()
local wide = At.Panel({ w = 420, h = 80, padding = 0 })
local hview = At.ScrollView({ x = 0, y = 0, w = 200, h = 100, content = wide })
hview:draw()
check(hview:maxScrollX() > 0, "内容超宽时出现横向滚动: " .. hview:maxScrollX())
check(hview:maxScroll() == 0, "高度不超时没有纵向滚动")
check(hview.scrollX == 0, "初始水平位置为 0")

check(hview:isInteractive() == true, "ScrollView 声明为可交互（支持嵌套）")
check(hview:setScrollX(30) == 30, "setScrollX 立即生效")
check(hview.scrollX == 30, "scrollX 更新")
check(hview:setScrollX(100000) == hview:maxScrollX(), "横向滚动夹紧")
hview:setScrollX(0)

mouseX, mouseY = 100, 50
check(hview:wheelmoved(1, 0) == true, "横向滚轮被消费")
check(hview._scrollTargetX > 0, "横向滚轮设置目标")
for _ = 1, 30 do
	hview:update(1 / 60)
end
check(hview.scrollX > 0, "横向平滑滚动到位: " .. hview.scrollX)

-- 横向滚动条可拖
hview:setScrollX(0)
hview:draw()
mouseDown = true
local hbx, hby, hbw, hbTrack, hThumbX, hThumbW = hview:_hbarMetrics()
check(hbTrack > 0 and hThumbW > 0, "横向滚动条几何有效")
mouseX, mouseY = hThumbX + hThumbW / 2, hby + hbw / 2
check(hview:mousepressed(mouseX, mouseY, 1) == true, "按在横向滚动条上")
mouseX = hbx + hbTrack - 1
hview:update(1 / 60)
check(hview.scrollX == hview:maxScrollX(), "拖横向滚动条到底: " .. hview.scrollX)
mouseDown = false
hview:update(1 / 60)
At.mousereleased(mouseX, mouseY, 1)
-- Shift + 滚轮 = 横向
hview:setScrollX(0)
shiftDown = true
mouseX, mouseY = 100, 50
check(hview:wheelmoved(0, -1) == true, "Shift+滚轮被消费")
check(hview._scrollTargetX > 0, "Shift+滚轮走横向: " .. tostring(hview._scrollTargetX))
shiftDown = false
hview:destroy()

-- 只有纵向空间时，横向滚轮退化为纵向
At.registry.clear()
local tall = At.Panel({ w = 100, h = 400, padding = 0 })
local vview = At.ScrollView({ x = 0, y = 0, w = 200, h = 100, content = tall })
vview:draw()
mouseX, mouseY = 100, 50
check(vview:wheelmoved(1, 0) == true, "只有纵向空间时横向滚轮也消费")
check(vview._scrollTarget > 0, "退化为纵向滚动: " .. tostring(vview._scrollTarget))
vview.content = nil
vview:destroy()

-- 嵌套滚动：外层不抢内层的事件
At.registry.clear()
local innerContent = At.Panel({ w = 600, h = 40, padding = 0 })
local innerView = At.ScrollView({ x = 0, y = 0, w = 200, h = 60, content = innerContent })
local outerContent = At.Panel({ w = 200, h = 800, padding = 0, children = { innerView } })
local outerView = At.ScrollView({ x = 0, y = 0, w = 220, h = 120, content = outerContent })
outerView:draw()
check(outerView:maxScroll() > 0, "外层可纵向滚动")
mouseDown = true
mouseX, mouseY = innerView.x + 10, innerView.y + 10
At.mousepressed(mouseX, mouseY, 1)
check(innerView._dragging == true, "嵌套的 ScrollView 收到拖动")
check(outerView._dragging ~= true, "外层没有抢走拖动")
mouseDown = false
At.mousereleased(mouseX, mouseY, 1)
outerView.content = nil
innerView.content = nil
outerView:destroy()
innerView:destroy()

-- 内容不超出宽高时：没有滚动空间，也不吞点击
At.registry.clear()
local narrow = At.Panel({ w = 100, h = 40, padding = 0 })
local nview = At.ScrollView({ x = 0, y = 0, w = 200, h = 100, content = narrow })
nview:draw()
check(nview:maxScrollX() == 0 and nview:maxScroll() == 0, "内容不超出时没有滚动空间")
check(At.mousepressed(100, 50, 1) == false, "无滚动空间时不吞点击")
nview.content = nil
nview:destroy()

-- ---------- 像素对齐 / 线型 ----------
local aligned = At.Panel({
	x = 0,
	y = 0,
	w = 101,
	h = "auto",
	padding = 0,
	direction = "row",
	children = {
		At.Label({ text = "a", w = "33%", fontSize = 10 }),
		At.Label({ text = "b", w = "33%", fontSize = 10 }),
		At.Label({ text = "c", w = "33%", fontSize = 10 }),
	},
})
aligned:draw()
for i = 1, #aligned.children do
	local child = aligned.children[i]
	check(child.x == math.floor(child.x), "子项 x 对齐整数: " .. child.x)
	check(child.w == math.floor(child.w), "子项 w 对齐整数: " .. child.w)
end

aligned.children[1]:draw()
check(lastPrint ~= nil, "文字已经绘制")
check(
	lastPrint.x == math.floor(lastPrint.x) and lastPrint.y == math.floor(lastPrint.y),
	"文字位置对齐整数像素"
)

check(love.graphics.getLineStyle() == "smooth", "绘制后线型已恢复为 smooth")
check(love.graphics.getLineWidth() == 1, "绘制后线宽已恢复")

-- ---------- 演示程序接线（main.lua 回调） ----------
At.input.setActive(false)
At.registry.clear()
At.config.log.print = false -- 演示里的 config.apply 不要把日志打到测试输出
dofile("main.lua")

love.load()
love.update(1 / 60)
love.draw()
check(love.graphics.getFont() ~= nil, "演示绘制后字体状态可用")

local function findComponent(predicate)
	for _, component in ipairs(At.registry.all()) do
		if predicate(component) then
			return component
		end
	end
	return nil
end

local demoInput = findComponent(function(c)
	return c.textinput ~= nil
end)
check(demoInput ~= nil, "演示里有 TextInput")

mouseX, mouseY = demoInput.x + demoInput.w / 2, demoInput.y + demoInput.h / 2
love.update(1 / 60)
love.mousepressed(mouseX, mouseY, 1)
love.mousereleased(mouseX, mouseY, 1)
check(demoInput:isFocused(), "演示里点击输入框获得焦点")

love.textinput("测")
love.textinput("试")
check(demoInput:getText() == "测试", "演示里能输入中文")

local submit = findComponent(function(c)
	return c.onClick ~= nil and c.text == "提交"
end)
check(submit ~= nil, "演示里有提交按钮")

-- 这里直接走按钮自己的按下/松开：演示卡片现在比视口高，提交按钮不一定在可视区，
-- 点击事件由 ScrollView 的测试覆盖，这里只验证演示的 onClick 接线。
submit:mousepressed(submit.x + 10, submit.y + 10, 1)
submit:mousereleased(submit.x + 10, submit.y + 10, 1)

local statusShown = findComponent(function(c)
	return c.text ~= nil and type(c.text) == "string" and c.text:find("已提交", 1, true) ~= nil
end)
check(statusShown ~= nil, "提交按钮更新了状态标签")

local demoDial = findComponent(function(c)
	return c.getRatio ~= nil and c.setWrapping ~= nil
end)
check(demoDial ~= nil, "演示里有 Dial")

local demoConsole = findComponent(function(c)
	return c.levelColors ~= nil
end)
check(demoConsole ~= nil, "演示创建了控制台")
check(demoConsole.visible == false, "演示控制台初始隐藏")
love.keypressed("f1")
check(demoConsole.visible == true, "F1 打开控制台")
love.keypressed("f2")
check(At.log.count() == 1, "F2 清空后只保留一条提示: " .. At.log.count())
love.draw()

-- 演示接线：滚轮、窗口缩放、切后台收起键盘
mouseX, mouseY = 100, 100
check(love.wheelmoved ~= nil, "演示接入了滚轮")
love.wheelmoved(0, -1)
check(love.resize ~= nil, "演示接入了窗口缩放")
love.resize(500, 360)
love.draw()
love.focus(false)
check(At.getFocus() == nil, "切到后台后失焦（收起软键盘）")
love.focus(true)
love.draw()

-- 演示开启了文件日志，测试结束后清理（不要在仓库里留下 .log）
local demoLogFile = At.log.getFileName()
At.log.closeFile()
if demoLogFile then
	os.remove(demoLogFile)
end

-- 演示改过全局 config，复位，避免后续用例继承 log.file=true / blur=true
At.config.log.file = false
At.config.blur.enabled = false
At.config.apply()

-- ---------- 文档同步 ----------
local function fileContains(path, needle)
	local file = io.open(path, "r")
	if not file then
		return false
	end
	local content = file:read("*a")
	file:close()
	return content:find(needle, 1, true) ~= nil
end

for _, name in ipairs({
	"At.Button",
	"At.Label",
	"At.Panel",
	"At.TextInput",
	"At.Switch",
	"At.Checkbox",
	"At.RadioGroup",
	"At.Slider",
	"At.Dial",
	"At.ScrollView",
	"At.Console",
	"At.ProgressBar",
	"At.LoadingBar",
}) do
	check(fileContains("docs/components.md", name), "docs/components.md 缺少 " .. name)
end

check(fileContains("docs/layout.md", "grow"), "docs/layout.md 缺少 grow 说明")
check(fileContains("docs/layout.md", "justify"), "docs/layout.md 缺少 justify 说明")
check(fileContains("docs/README.md", "love.update"), "docs/README.md 缺少快速开始")
check(fileContains("docs/README.md", "At.log"), "docs/README.md 缺少日志说明")
check(fileContains("docs/logging.md", "setLevel"), "docs/logging.md 缺少 setLevel")
check(fileContains("docs/logging.md", "setFormat"), "docs/logging.md 缺少 setFormat")
check(fileContains("docs/blur.md", "setAlgorithm"), "docs/blur.md 缺少 setAlgorithm")
check(fileContains("docs/blur.md", "beginFrame"), "docs/blur.md 缺少 beginFrame")
check(fileContains("docs/README.md", "At.Dial"), "docs/README.md 缺少 Dial 说明")
check(fileContains("AGENTS.md", "At.Dial"), "AGENTS.md 缺少 Dial 说明")
check(fileContains("docs/components.md", "wrapping"), "docs/components.md 缺少 Dial wrapping 说明")
check(fileContains("docs/README.md", "At.blur"), "docs/README.md 缺少模糊说明")
check(fileContains("At/config.lua", "blur"), "At/config.lua 缺少 blur 配置")
check(fileContains("At/config.lua", "theme"), "At/config.lua 缺少 theme 配置")
check(fileContains("docs/theme.md", "A7DCFF"), "docs/theme.md 缺少默认主题色")
check(fileContains("docs/theme.md", "@primary"), "docs/theme.md 缺少 token 说明")
check(fileContains("docs/theme.md", "At.theme.set"), "docs/theme.md 缺少运行时切换说明")
check(fileContains("At/config.lua", "msaa"), "At/config.lua 缺少 msaa 配置")
check(fileContains("conf.lua", "render.msaa"), "conf.lua 没有从 At/config 读取 msaa")
check(fileContains("conf.lua", "stencil"), "conf.lua 没有开启 stencil")
check(fileContains("docs/blur.md", "setStencilMode"), "docs/blur.md 缺少 LÖVE 12 模板说明")
check(fileContains("At/config.lua", "shadow"), "At/config.lua 缺少 shadow 配置")
check(fileContains("docs/shadow.md", "At.shadow.setAlgorithm"), "docs/shadow.md 缺少算法切换说明")
check(fileContains("docs/shadow.md", "glsl"), "docs/shadow.md 缺少 glsl 说明")
check(fileContains("docs/README.md", "At.shadow"), "docs/README.md 缺少阴影说明")
check(fileContains("docs/README.md", "config.render.msaa"), "docs/README.md 缺少 MSAA 配置说明")
check(fileContains("AGENTS.md", "At.render"), "AGENTS.md 缺少渲染模块说明")
check(fileContains("docs/README.md", "MSAA"), "docs/README.md 缺少抗锯齿说明")
check(fileContains("docs/blur.md", "MSAA"), "docs/blur.md 缺少 MSAA 说明")
check(fileContains("docs/README.md", "At.theme"), "docs/README.md 缺少主题说明")
check(fileContains("docs/components.md", "@primary"), "docs/components.md 缺少主题 token 默认值")
check(fileContains("AGENTS.md", "At.theme"), "AGENTS.md 缺少主题说明")
check(fileContains("docs/README.md", "At.config"), "docs/README.md 缺少配置说明")
check(fileContains("AGENTS.md", "At/config.lua"), "AGENTS.md 缺少配置说明")
check(fileContains("AGENTS.md", "文档规范"), "AGENTS.md 缺少文档规范章节")

-- ---------- 背景模糊 ----------
At.registry.clear()
At.blur.reset()
At.blur.setEnabled(false)
check(At.blur.isEnabled() == false, "模糊默认关闭")
check(At.blur.drawBackdrop(0, 0, 10, 10, 0) == false, "关闭时不绘制背景")

At.blur.setEnabled(true)
check(At.blur.isEnabled() == true, "可以开启模糊")
check(At.blur.enabled == true, "enabled 字段可读")
At.blur.enabled = false
check(At.blur.isEnabled() == false, "enabled 字段可写")
At.blur.enabled = true

At.blur.setAlgorithm("downscale")
check(At.blur.getAlgorithm() == "downscale", "可以切换算法")
check(pcall(At.blur.setAlgorithm, "no-such-algorithm") == false, "未知算法报错")
local customAlgorithm = function(snapshot, x, y, w, h)
	return snapshot, x, y, w, h
end
At.blur.setAlgorithm(customAlgorithm)
check(At.blur.getAlgorithm() == customAlgorithm, "可以传自定义函数")
At.blur.setAlgorithm("downscale")

At.blur.resetStats()
canvasCalls = {}
check(At.blur.beginFrame() == true, "beginFrame 生效")
check(canvasCalls[1] and canvasCalls[1].msaa == 4, "模糊场景画布跟随窗口 MSAA")
check(At.blur.getMSAA() == 4, "getMSAA 返回当前实际采样数")
check(At.blur.getMaxMSAA() == 8, "getMaxMSAA 返回设备上限")
local translucentPanel = At.Panel({
	x = 10,
	y = 10,
	w = 120,
	h = 80,
	radius = 8,
	background = "#202020",
	alpha = 180,
})
translucentPanel:draw()
check(At.blur.stats().backdrops == 1, "半透明 Panel 触发模糊")
local opaquePanel = At.Panel({
	x = 10,
	y = 10,
	w = 120,
	h = 80,
	radius = 8,
	background = "#202020",
	alpha = 255,
})
opaquePanel:draw()
check(At.blur.stats().backdrops == 1, "不透明 Panel 不触发模糊")
opaquePanel:destroy()
translucentPanel:destroy()
check(At.blur.endFrame() == true, "endFrame 生效")

-- 自定义算法收到的区域参数
local captured = {}
At.blur.setAlgorithm(function(snapshot, x, y, w, h, strength)
	captured = { x = x, y = y, w = w, h = h, strength = strength }
	return snapshot, x, y, w, h
end)
At.blur.beginFrame()
check(At.blur.drawBackdrop(5, 6, 30, 40, 4) == true, "自定义算法被调用")
check(captured.x == 5 and captured.y == 6 and captured.w == 30 and captured.h == 40, "算法收到正确的区域")
At.blur.endFrame()

-- 控制台默认半透明（alpha=205），绘制时也会触发模糊
At.blur.setAlgorithm("downscale")
At.blur.beginFrame()
local blurConsole = At.Console({ x = 0, y = 0, w = 200, h = 100 })
blurConsole:show()
blurConsole:update(0.2) -- 打开动画推进后再画，半透明窗口才真正可见
local beforeConsole = At.blur.stats().backdrops
blurConsole:draw()
check(At.blur.stats().backdrops == beforeConsole + 1, "半透明控制台触发模糊")
blurConsole:destroy()
At.blur.endFrame()

-- LÖVE 12 的 setStencilMode 路径（LÖVE 11 走上面的 stencil/setStencilTest 路径）
canvasCalls = {}
love.graphics.setStencilMode = function(mode)
	canvasCalls[#canvasCalls + 1] = mode or "off"
end
At.blur.beginFrame()
blurConsole = At.Panel({
	x = 10,
	y = 10,
	w = 80,
	h = 60,
	background = "#202020",
	alpha = 180,
})
blurConsole:draw()
blurConsole:destroy()
At.blur.endFrame()
check(canvasCalls[1] == "draw", "LÖVE 12 模板写入模式: " .. tostring(canvasCalls[1]))
check(canvasCalls[2] == "test", "LÖVE 12 模板测试模式: " .. tostring(canvasCalls[2]))
check(canvasCalls[#canvasCalls] == "off", "LÖVE 12 模板状态复位")
love.graphics.setStencilMode = nil

At.blur.setAlgorithm("gaussian")
At.blur.setEnabled(false)
At.blur.reset()
check(At.blur.isEnabled() == false, "复位后保持关闭")

-- ---------- 日志 ----------
At.registry.clear()
At.log.clear()
local savedLevel = At.log.getLevel()
local savedFormat = At.log.getFormat()

check(At.log.getPrint() == false, "测试里已关闭 stdout 镜像")

local mirrored = {}
At.log.setPrint(function(text)
	mirrored[#mirrored + 1] = text
end)
At.log.setLevel("debug")
At.log.info("镜像 %d", 1)
check(#mirrored == 1, "stdout 镜像被调用")
check(mirrored[1]:find("镜像 1", 1, true) ~= nil, "镜像内容是格式化后的文本")
At.log.setPrint(false)
At.log.info("不镜像")
check(#mirrored == 1, "关闭后不再镜像")
check(At.log.count() == 2, "关闭镜像不影响缓冲")
At.log.clear()

At.log.setLevel("warn")
check(At.log.debug("被过滤的 debug") == nil, "低于等级的 debug 被丢弃")
check(At.log.info("被过滤的 info") == nil, "低于等级的 info 被丢弃")

local warnEntry = At.log.warn("警告 %d", 7)
check(warnEntry ~= nil and warnEntry.levelName == "WARN", "warn 写入成功")
check(warnEntry.message == "警告 7", "字符串格式化: " .. warnEntry.message)
check(warnEntry.func ~= nil and warnEntry.func ~= "", "记录了函数名: " .. tostring(warnEntry.func))
check(warnEntry.time:match("^%d%d:%d%d:%d%d$") ~= nil, "时间格式 HH:MM:SS: " .. warnEntry.time)
check(At.log.count() == 1, "计数正确")

local namedEntry
local function logFromNamed()
	namedEntry = At.log.error("命名调用")
end
logFromNamed()
check(
	namedEntry ~= nil and namedEntry.func == "logFromNamed",
	"函数名取自调用者: " .. tostring(namedEntry and namedEntry.func)
)

local defaultText = At.log.formatEntry(warnEntry)
check(defaultText:find("WARN", 1, true) ~= nil, "默认格式含等级")
check(defaultText:find("警告 7", 1, true) ~= nil, "默认格式含内容")
check(defaultText:sub(1, 1) == "[", "默认格式以时间开头: " .. defaultText)

At.log.setFormat("[%s]%s/%s>%s")
local customText = At.log.formatEntry(warnEntry)
check(
	customText:find("WARN/", 1, true) ~= nil and customText:find(">警告 7", 1, true) ~= nil,
	"自定义格式生效: " .. customText
)

At.log.setFormat(function(entry)
	return "F:" .. entry.levelName .. ":" .. entry.message
end)
check(At.log.formatEntry(warnEntry) == "F:WARN:警告 7", "格式函数生效")

check(pcall(At.log.setLevel, "nope") == false, "非法等级报错")

At.log.setLevel("debug")
At.log.setMaxEntries(3)
At.log.clear()
for i = 1, 5 do
	At.log.info("第 %d 条", i)
end
check(At.log.count() == 3, "缓冲按上限裁剪: " .. At.log.count())
check(At.log.getEntries()[1].message == "第 3 条", "最旧的被丢弃")

At.log.setMaxEntries(500)
At.log.setFormat(savedFormat)
At.log.setLevel(savedLevel)
At.log.clear()

-- 文件输出（默认关闭，显式开启；用安全文件名测试）
At.log.setFilePattern("test_atlog_%Y%m%d_%H%M%S.log")
check(At.log.setFile(true) == true, "开启文件输出")
check(At.log.isFileEnabled() == true, "文件输出已启用")
local logFileName = At.log.getFileName()
check(logFileName:match("^test_atlog_%d+_%d+%.log$") ~= nil, "文件名按 pattern 生成: " .. tostring(logFileName))

At.log.setLevel("debug")
At.log.clear()
At.log.info("文件行 %d", 1)
At.log.error("错误行")
At.log.closeFile()

local logHandle = assert(io.open(logFileName, "r"))
local logContent = logHandle:read("*a")
logHandle:close()
check(logContent:find("文件行 1", 1, true) ~= nil, "info 写入文件")
check(logContent:find("错误行", 1, true) ~= nil, "error 写入文件")
local _, newlines = logContent:gsub("\n", "")
check(newlines >= 2, "按行写入: " .. newlines)
os.remove(logFileName)

check(At.log.setFile(false) == false, "可以关闭文件输出")
check(At.log.isFileEnabled() == false, "关闭后不再写入")

-- love.filesystem 不可写时退回 io.open（当前工作目录）
local oldFilesystem = love.filesystem
love.filesystem = {
	newFile = function()
		return nil
	end,
	getSaveDirectory = function()
		return "/readonly"
	end,
}
At.log.setFilePattern("test_atlog_fallback_%Y%m%d_%H%M%S.log")
check(At.log.setFile(true) == true, "存档目录不可写时退回 io")
local fallbackName = At.log.getFileName()
At.log.info("fallback line")
At.log.closeFile()
love.filesystem = oldFilesystem
local fallbackHandle = assert(io.open(fallbackName, "r"))
local fallbackContent = fallbackHandle:read("*a")
fallbackHandle:close()
check(fallbackContent:find("fallback line", 1, true) ~= nil, "io fallback 写入成功")
os.remove(fallbackName)

-- LÖVE 12：优先使用 openFile；缺少 openFile 的 LÖVE 11 才用 newFile
oldFilesystem = love.filesystem
love.filesystem = {
	opened = false,
	openFile = function()
		love.filesystem.opened = true
		return {
			write = function() end,
			flush = function() end,
			close = function() end,
		}
	end,
	newFile = function()
		error("LÖVE 12 应优先使用 openFile")
	end,
	getSaveDirectory = function()
		return "/save"
	end,
}
At.log.setFilePattern("test_openfile.log")
check(At.log.setFile(true) == true, "openFile 可打开日志")
check(love.filesystem.opened == true, "LÖVE 12 优先使用 openFile")
At.log.closeFile()
love.filesystem = oldFilesystem

At.log.setFilePattern(nil)
check(At.log.getFilePattern() == "%Y-%m-%d_%H-%M-%S.log", "默认文件名格式")
local sampleName = os.date(At.log.getFilePattern())
check(
	sampleName:match("^%d%d%d%d%-%d%d%-%d%d_%d%d%-%d%d%-%d%d%.log$") ~= nil,
	"默认文件名形如 2026-10-18_16-43-40.log: " .. sampleName
)

At.log.setFilePattern("%Y-%m-%d_%H-%M-%S.log")
At.log.setLevel(savedLevel)
At.log.clear()

-- ---------- 控制台 ----------
At.registry.clear()
At.log.setLevel("debug")
for i = 1, 20 do
	At.log.info("第 %d 行日志", i)
end

local console = At.Console({ x = 100, y = 100, w = 300, h = 100 })
check(console.visible == false, "控制台默认隐藏")
check(console:contains(150, 110), "命中窗口区域")
check(not console:contains(150, 400), "窗口外不命中")

console:toggle()
check(console.visible == true and console:isOpen(), "toggle 打开")

mouseX, mouseY = 150, 150
local cview = console._view
check(console:wheelmoved(0, 1) == true, "滚轮被控制台消费")
for _ = 1, 30 do
	console:update(1 / 60)
end
check(cview.scrollY > 0, "滚轮向上翻看历史: " .. cview.scrollY)
console:scrollToBottom()
check(cview.scrollY == cview:maxScroll(), "回到底部")

mouseDown = true
mouseX, mouseY = 110, 110
check(console:mousepressed(110, 110, 1) == true, "标题栏按下被消费")
check(console._windowDrag ~= nil, "进入窗口拖动")
mouseX, mouseY = 200, 200
console:update(1 / 60)
check(console.x > 100 and console.y > 100, "窗口被拖动: " .. console.x .. "," .. console.y)
mouseDown = false
console:update(1 / 60)
At.mousereleased(200, 200, 1)
check(console._windowDrag == nil, "松手结束拖动")

local closeX, closeY = console.x + console.w - 4, console.y + 4
check(console:mousepressed(closeX, closeY, 1) == true, "点关闭按钮")
check(console.visible == false, "关闭后隐藏")

console:show()
console:draw()
check(love.graphics.getScissor() == nil, "控制台绘制后 scissor 已恢复")

local console2 = At.Console({ x = 0, y = 0, w = 200, h = 80 })
console.levelColors.info = "#000001"
check(console2.levelColors.info ~= "#000001", "levelColors 不在实例间共享")

-- 滚动量由 ScrollView 夹紧（不再有"小数行下标"这种自家实现）
console:show()
At.log.clear()
for i = 1, 10 do
	At.log.info("滚动夹紧 %d", i)
end
console:_syncView(1 / 60)
local v = console._view
v:setScroll(99999)
check(v.scrollY == v:maxScroll(), "滚动量被夹紧到最大值")
v:setScroll(-5)
check(v.scrollY == 0, "滚动量被夹紧到 0")
At.log.clear()

console:clear()
check(At.log.count() == 0, "clear 清空日志缓冲")

-- C 按钮清空
for i = 1, 3 do
	At.log.info("待清空 %d", i)
end
console:show()
local clearX, clearY = console.x + console.w - 45, console.y + 4
check(console:mousepressed(clearX, clearY, 1) == true, "点 C 按钮")
check(At.log.count() == 0, "C 按钮清空日志")

-- 日志区复用 ScrollView，而不是控制台自己再写一套滚动条
check(console._view ~= nil, "控制台内部使用 ScrollView")
check(console._view.autoRegister == false, "内部 ScrollView 不注册到全局")
check(console._view.content == console._lines, "内部 ScrollView 的内容是日志行")

-- 停在底部时自动跟随最新；往上翻后保持位置
At.log.clear()
for i = 1, 8 do
	At.log.info("跟随 %d", i)
end
console:show()
console:update(1 / 60)
local followView = console._view
check(followView.scrollY == followView:maxScroll(), "停在底部自动跟随最新")
mouseX, mouseY = console.x + 40, console.y + 60
console:wheelmoved(0, 1)
for _ = 1, 30 do
	console:update(1 / 60)
end
local heldScroll = followView.scrollY
check(heldScroll < followView:maxScroll(), "滚轮可以往上翻")
for i = 1, 4 do
	At.log.info("新日志 %d", i)
end
console:update(1 / 60)
check(followView.scrollY <= heldScroll + 1, "往上翻后不被新日志拽回底部")
console:scrollToBottom()
check(followView.scrollY == followView:maxScroll(), "scrollToBottom 回到底部并恢复跟随")

console:destroy()
console2:destroy()

-- 隐藏时的 LOG 标签（移动端入口）
local tabConsole = At.Console({ x = 0, y = 0, w = 200, h = 100 })
check(tabConsole.tab == true, "默认显示 LOG 标签")
local tab = tabConsole:_tabRect()
check(tabConsole:mousepressed(tab.x + 2, tab.y + 2, 1) == true, "点 LOG 标签")
check(tabConsole.visible == true, "点标签后打开控制台")
check(tabConsole:mousepressed(tab.x + 2, tab.y + 2, 1) == false, "打开后标签不再响应")
tabConsole:hide()
check(tabConsole:mousepressed(tab.x + 2, tab.y + 2, 1) == true, "隐藏后可再次点开")
tabConsole:hide()
tabConsole:draw()
check(love.graphics.getScissor() == nil, "只画标签时状态正常")
tabConsole:destroy()

-- ---------- 触顶/触底特效（ScrollView 过冲） ----------
At.registry.clear()
local edgeContent = At.Panel({ w = 200, h = 400, padding = 0, radius = 16 })
local edgeView = At.ScrollView({ x = 0, y = 0, w = 200, h = 100, content = edgeContent })
edgeView:layout()
check(edgeView:maxScroll() == 300, "过冲用例的内容可滚动: " .. edgeView:maxScroll())
local restingY = edgeView.content.y

mouseDown = true
mouseX, mouseY = 20, 20
check(edgeView:mousepressed(20, 20, 1) == true, "顶部按下开始拖动")
mouseY = 60
edgeView:update(1 / 60)
check(edgeView.scrollY == 0, "触顶后 scrollY 仍夹在 0")
check(edgeView._overY > 0, "顶部下拉产生过冲: " .. edgeView._overY)
check(edgeView._edgePulse.top == 0, "过冲光带由拉动量驱动，不额外打脉冲")
-- 光带外圈应按内容容器（大卡片）的圆角收角
local topRowWidths = {}
local rectBeforeGlow = draws.rect
local realRectGlow = love.graphics.rectangle
love.graphics.rectangle = function(mode, rx, ry, rw, rh, rr)
	if ry == edgeView.y and rh == 1 then
		topRowWidths[#topRowWidths + 1] = { x = rx, w = rw }
	end
	realRectGlow(mode, rx, ry, rw, rh, rr)
end
edgeView:draw()
love.graphics.rectangle = realRectGlow
check(edgeView.content.y == restingY, "过冲只画边缘光，不把内容推出容器")
check(draws.rect > rectBeforeGlow, "边缘光带参与绘制")
check(#topRowWidths > 0, "顶部光带绘制在最外圈")
check(topRowWidths[1].w < edgeView.w, "光带外圈按容器圆角收角: " .. topRowWidths[1].w)
check(topRowWidths[1].x > edgeView.x, "光带外圈左侧内缩")

-- edgeRadius 可以覆盖默认（这里设 0 就画成直角）
edgeView.edgeRadius = 0
local squareWidths = {}
love.graphics.rectangle = function(mode, rx, ry, rw, rh, rr)
	if ry == edgeView.y and rh == 1 then
		squareWidths[#squareWidths + 1] = rw
	end
	realRectGlow(mode, rx, ry, rw, rh, rr)
end
edgeView:draw()
love.graphics.rectangle = realRectGlow
check(squareWidths[1] == edgeView.w, "edgeRadius=0 时光带是直角")
edgeView.edgeRadius = nil

mouseDown = false
edgeView:update(1 / 60)
check(edgeView._overY > 0, "松手后仍在回弹")
for _ = 1, 120 do
	edgeView:update(1 / 60)
end
check(math.abs(edgeView._overY) < 0.1, "顶部过冲回弹收敛: " .. edgeView._overY)

-- 触底（在底部继续向上拉）
edgeView:setScroll(edgeView:maxScroll())
mouseDown = true
mouseX, mouseY = 20, 50
edgeView:mousepressed(20, 50, 1)
mouseY = 10
edgeView:update(1 / 60)
check(edgeView.scrollY == edgeView:maxScroll(), "触底后 scrollY 停在最大值")
check(edgeView._overY < 0, "底部上拉产生反向过冲: " .. edgeView._overY)
mouseDown = false
edgeView:update(1 / 60)
for _ = 1, 120 do
	edgeView:update(1 / 60)
end
check(math.abs(edgeView._overY) < 0.1, "底部过冲也会回弹")

-- 纵滚容器上横向拖动不应触发左右特效（反之亦然）
edgeView:setScroll(0)
mouseDown = true
mouseX, mouseY = 100, 30
edgeView:mousepressed(100, 30, 1)
mouseX = 180
edgeView:update(1 / 60)
check(edgeView._overX == 0, "纵滚容器不产生横向过冲: " .. edgeView._overX)
check(edgeView._edgePulse.left == 0 and edgeView._edgePulse.right == 0, "纵滚容器不触发左右特效")
mouseDown = false
edgeView:update(1 / 60)
for _ = 1, 60 do
	edgeView:update(1 / 60)
end
check(edgeView._edgePulse.left == 0 and edgeView._edgePulse.right == 0, "纵滚容器松手后也没有左右脉冲")

-- 滚轮顶到边界：没有过冲也要有触边脉冲
edgeView:setScroll(edgeView:maxScroll())
edgeView._edgePulse.bottom = 0
mouseX, mouseY = 20, 20
check(edgeView:wheelmoved(0, -1) == true, "滚轮在触底时仍被消费")
check(edgeView._edgePulse.bottom > 0, "滚轮触底触发脉冲")
edgeView:setScroll(0)
edgeView._edgePulse.top = 0
check(edgeView:wheelmoved(0, 1) == true, "滚轮在触顶时仍被消费")
check(edgeView._edgePulse.top > 0, "滚轮触顶触发脉冲")

-- 纵向滚动条拖到两端也会触发
edgeView:setScroll(0)
edgeView._edgePulse.top = 0
edgeView:_barDragTo(edgeView.y + edgeView.h + 10)
check(edgeView._edgePulse.bottom > 0, "纵向滚动条拖到底触发底部脉冲")
edgeView._edgePulse.top = 0
edgeView:_barDragTo(edgeView.y - 10)
check(edgeView._edgePulse.top > 0, "纵向滚动条拖到顶触发顶部脉冲")

-- 横向过冲与纵向互不影响
local wideView = At.ScrollView({ x = 0, y = 0, w = 200, h = 100, content = At.Panel({ w = 500, h = 100 }) })
wideView:layout()
check(wideView:maxScroll() == 0 and wideView:maxScrollX() == 300, "横向用例只有横向可滚")
wideView:setScrollX(wideView:maxScrollX())
mouseDown = true
mouseX, mouseY = 150, 20
wideView:mousepressed(150, 20, 1)
mouseX = 50
wideView:update(1 / 60)
check(wideView._overX < 0, "右边界继续左拖产生横向过冲: " .. wideView._overX)
check(wideView._edgePulse.right == 0, "靠过冲量画右侧光带，不额外打脉冲")

-- 光带不能画到容器外（横竖都靠视口裁剪）
local realRect = love.graphics.rectangle
local escaped = false
love.graphics.rectangle = function(mode, rx, ry, rw, rh, rr)
	if
		rx < wideView.x - 0.5
		or ry < wideView.y - 0.5
		or rx + rw > wideView.x + wideView.w + 0.5
		or ry + rh > wideView.y + wideView.h + 0.5
	then
		escaped = true
	end
	realRect(mode, rx, ry, rw, rh, rr)
end
wideView:draw()
love.graphics.rectangle = realRect
check(not escaped, "边缘光带没有画到 ScrollView 之外")

-- 拖动滚动条到两端也能触发边缘光（不只有拖动内容）
wideView:setScrollX(0)
wideView._edgePulse.right = 0
wideView:_hbarDragTo(wideView.x + wideView.w + 10)
check(wideView._edgePulse.right > 0, "横向滚动条拖到底触发右侧脉冲")
wideView._edgePulse.left = 0
wideView:_hbarDragTo(wideView.x - 10)
check(wideView._edgePulse.left > 0, "横向滚动条拖到顶触发左侧脉冲")
check(wideView._overY == 0, "横向过冲不影响纵向")
mouseDown = false
wideView:update(1 / 60)
for _ = 1, 120 do
	wideView:update(1 / 60)
end
check(math.abs(wideView._overX) < 0.1, "横向过冲回弹收敛")

-- 横滚容器上垂直拖动不应触发上下特效
wideView:setScrollX(0)
mouseDown = true
mouseX, mouseY = 100, 20
wideView:mousepressed(100, 20, 1)
mouseY = 80
wideView:update(1 / 60)
check(wideView._overY == 0, "横滚容器不产生纵向过冲: " .. wideView._overY)
check(wideView._edgePulse.top == 0 and wideView._edgePulse.bottom == 0, "横滚容器不触发上下特效")
mouseDown = false
wideView:update(1 / 60)
for _ = 1, 60 do
	wideView:update(1 / 60)
end
check(wideView._edgePulse.top == 0 and wideView._edgePulse.bottom == 0, "横滚容器松手后也没有上下脉冲")
wideView:destroy()

-- edgeEffect = false 时不产生过冲
local plainView = At.ScrollView({
	x = 0,
	y = 0,
	w = 200,
	h = 100,
	edgeEffect = false,
	content = At.Panel({ w = 200, h = 400 }),
})
plainView:layout()
mouseDown = true
mouseX, mouseY = 20, 20
plainView:mousepressed(20, 20, 1)
mouseY = 60
plainView:update(1 / 60)
check(plainView._overY == 0, "关闭 edgeEffect 后不产生过冲")
mouseDown = false
plainView:update(1 / 60)
plainView:destroy()
edgeView:destroy()

-- ---------- 进度条 ----------
At.registry.clear()
local progress = At.ProgressBar({ x = 0, y = 0, w = 200, h = 12, value = 0.25 })
check(progress:getValue() == 0.25, "确定性进度条初始值")
progress:setValue(1.7)
check(progress:getValue() == 1, "进度值夹到 1")
progress:setValue(0.5)
progress:update(1 / 60)
check(progress._fill.value > 0.25 and progress._fill.value < 0.5, "进度条弹簧过渡")
for _ = 1, 120 do
	progress:update(1 / 60)
end
check(math.abs(progress._fill.value - 0.5) < 0.01, "进度条动画收敛: " .. progress._fill.value)

local barRects = draws.rect
progress:draw()
check(draws.rect >= barRects + 2, "进度条画轨道与填充")
progress:destroy()

local instantBar = At.ProgressBar({ value = 0.7, animate = false })
instantBar:update(1 / 60)
check(instantBar._fill.value == 0.7, "animate=false 的进度条立即落位")
instantBar:destroy()

local loading = At.LoadingBar({ x = 0, y = 0, w = 200, h = 10 })
check(loading:isRunning(), "不确定性进度条默认运行")
loading:update(0.25)
check(loading._phase > 0 and loading._phase < 1, "滑块相位在 0..1")
local frozenPhase = loading._phase
loading:setRunning(false)
loading:update(1)
check(loading._phase == frozenPhase, "停止后相位不再推进")
loading:setRunning(true)
barRects = draws.rect
loading:draw()
check(draws.rect > barRects, "不确定性进度条参与绘制")
loading:destroy()

local rolling = At.LoadingBar({ speed = 2 })
rolling._phase = 0.9
rolling:update(0.25)
check(rolling._phase >= 0 and rolling._phase < 1, "相位会回绕到 0..1: " .. rolling._phase)
rolling:destroy()

-- ---------- 动画：弹簧与缓动 ----------
local spring = At.motion.spring({ value = 0, stiffness = 300, damping = 24 })
check(spring.value == 0 and spring:isSettled(), "弹簧初始状态")
spring:setTarget(1)
for _ = 1, 10 do
	spring:update(1 / 60)
end
check(spring.value > 0.2 and spring.value < 1.6, "弹簧向目标推进: " .. spring.value)
for _ = 1, 180 do
	spring:update(1 / 60)
end
check(math.abs(spring.value - 1) < 0.01, "弹簧收敛到目标: " .. spring.value)

-- 掉帧不能把显式积分打飞：0.5s 一帧也要稳定
local bigStep = At.motion.spring({ stiffness = 320, damping = 26 })
bigStep:setTarget(1)
bigStep:update(0.5)
check(bigStep.value > 0 and bigStep.value < 2.5, "大 dt 用子步积分不发散: " .. bigStep.value)

check(At.motion.easeInOut(0) == 0 and At.motion.easeInOut(0.5) == 0.5, "easeInOut 端点/中点")
check(At.motion.easeOut(0.25) > 0.25, "easeOut 先快后慢")
check(At.motion.easeIn(0.25) < 0.25, "easeIn 先慢后快")
check(At.motion.damp(0, 1, 12, 1 / 60) > 0, "damp 向目标靠近")

-- 控制台开关动画：弹簧驱动，关闭时窗口还要淡出
At.registry.clear()
local animConsole = At.Console({ x = 0, y = 0, w = 200, h = 100 })
check(animConsole:openAmount() == 0, "控制台初始完全关闭")
animConsole:show()
animConsole:update(1 / 60)
local opening = animConsole:openAmount()
check(opening > 0 and opening < 1, "打开时存在过渡: " .. opening)
for _ = 1, 120 do
	animConsole:update(1 / 60)
end
check(math.abs(animConsole:openAmount() - 1) < 0.01, "打开动画收敛: " .. animConsole:openAmount())
animConsole:hide()
animConsole:update(1 / 60)
local closing = animConsole:openAmount()
check(closing > 0 and closing < 1, "关闭时先淡出而不是瞬间消失: " .. closing)
animConsole:draw() -- visible=false 但 open>0：窗口与标签都在画
for _ = 1, 120 do
	animConsole:update(1 / 60)
end
check(animConsole:openAmount() < 0.01, "关闭动画收敛: " .. animConsole:openAmount())
animConsole:destroy()

-- 勾选/单选/输入框/按钮的动画值
local animCb = At.Checkbox({ x = 0, y = 0, size = 22 })
animCb:setValue(true)
animCb:update(1 / 60)
check(animCb._pop.value > 0 and animCb._pop.value < 1, "勾选有弹入过渡")
for _ = 1, 90 do
	animCb:update(1 / 60)
end
check(animCb._pop.value > 0.99, "勾选动画收敛")
animCb:destroy()

local animRg = At.RadioGroup({ x = 0, y = 0, options = { "A", "B" }, value = 1, size = 20 })
animRg:update(1 / 60)
animRg:setValue(2)
animRg:update(1 / 60)
check(animRg._pops[2].value < 0.5 and animRg._pops[1].value > 0.1, "单选圆点交叉过渡")
animRg:destroy()

local animTi = At.TextInput({ x = 0, y = 0, w = 160, h = 36 })
animTi:focus()
animTi:update(1 / 60)
check(animTi._focus.value > 0 and animTi._focus.value < 1, "输入框聚焦边框过渡")
for _ = 1, 90 do
	animTi:update(1 / 60)
end
check(animTi._focus.value > 0.99, "聚焦动画收敛")
animTi:blur()
animTi:destroy()

mouseX, mouseY = 10, 10
local animBtn = At.Button({ x = 0, y = 0, w = 100, h = 40, ripple = false })
animBtn:update(1 / 60)
check(animBtn._hoverT.value > 0, "按钮悬停高光过渡")
animBtn:update(0) -- 零 dt 不推进也不报错
check(animBtn._hoverT.value > 0, "零 dt 不改变动画值")
animBtn:destroy()

-- 非动画模式立即落位（无障碍/低性能场景）
local stillConsole = At.Console({ x = 0, y = 0, w = 100, h = 60, animate = false })
stillConsole:show()
check(stillConsole:openAmount() == 1, "animate=false 立即打开")
stillConsole:hide()
check(stillConsole:openAmount() == 0, "animate=false 立即关闭")
stillConsole:destroy()

-- ---------- 许可证 ----------
check(fileContains("LICENSE", "MIT License"), "LICENSE 是 MIT 许可")
check(fileContains("docs/README.md", "LICENSE"), "README 有许可证章节")

check(fileContains("LICENSES/OFL-1.1.txt", "SIL OPEN FONT LICENSE Version 1.1"), "OFL 1.1 许可全文存在")
check(fileContains("THIRD_PARTY_NOTICES.md", "Noto Sans SC"), "第三方声明缺少 Noto Sans SC")
check(fileContains("THIRD_PARTY_NOTICES.md", "Noto Emoji"), "第三方声明缺少 Noto Emoji")
check(fileContains("THIRD_PARTY_NOTICES.md", "SIL Open Font License"), "第三方声明缺少 OFL 说明")
check(fileContains("LICENSES/Noto-Sans-SC.txt", "Adobe"), "Noto Sans SC 缺少版权方声明")
check(fileContains("LICENSES/Noto-Emoji.txt", "Google"), "Noto Emoji 缺少版权方声明")
check(fileContains("LICENSES/README.txt", "MIT"), "LICENSES/README.txt 汇总许可说明")

print(string.format("SMOKE OK  绘制调用: rect=%d print=%d", draws.rect, draws.print))
