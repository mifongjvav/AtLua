-- 单行文本输入框：点击/拖动定位光标，回车提交，Esc 失焦，支持方向键与中间插入/删除。
-- 焦点由 At.registry 统一管理，同一时刻只有一个组件接收 textinput。
--
--   local name = At.TextInput{
--       w = "100%", placeholder = "用户名",
--       onChange = function(text) print(text) end,
--       onSubmit = function(text) print("提交", text) end,
--   }
--
--   love.textinput(t)  -> At.textinput(t)
--   love.keypressed(k) -> At.keypressed(k)

local Component = require("At.core.component")
local color = require("At.core.color")
local input = require("At.core.input")
local clip = require("At.core.clip")
local pixel = require("At.core.pixel")
local blur = require("At.effects.blur")
local motion = require("At.core.motion")

local TextInput = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	w = 220,
	h = 44,
	radius = 10,

	text = "",
	placeholder = "",
	fontSize = 16,
	paddingX = 12,
	paddingY = 10,

	color = "@surfaceAlt",
	alpha = 255,
	borderColor = "@border",
	focusBorderColor = "@primary",
	textColor = "@text",
	placeholderColor = "@textFaint",
	caretColor = "@primary",
	caretWidth = 2,
	caretPeriod = 0.5,

	maxLength = 0, -- 0 = 不限
	password = false,
	maskChar = "*",

	-- 聚焦时边框颜色/线宽的过渡
	animate = true,
	focusSpringStiffness = 380,
	focusSpringDamping = 28,

	onSubmit = nil,
	onChange = nil,
	onFocus = nil,
	onBlur = nil,
}

function TextInput.new(opts)
	local self = Component.instantiate(proto, opts, DEFAULTS)
	self.text = tostring(self.text or "")
	self._caret = input.length(self.text)
	self._scrollX = 0
	self._caretTimer = 0
	self._dragging = false
	self._focus = motion.spring({
		value = self:isFocused() and 1 or 0,
		stiffness = self.focusSpringStiffness,
		damping = self.focusSpringDamping,
	})
	return self
end

-- ---------- 文本 ----------

function proto:getText()
	return self.text
end

-- silent = true 时不触发 onChange；光标移到新文本末尾
function proto:setText(text, silent)
	self.text = tostring(text or "")
	self._caret = input.length(self.text)
	self._scrollX = 0
	self._caretTimer = 0
	self:invalidateSize()
	if not silent and self.onChange then
		self.onChange(self.text, self)
	end
	return self
end

function proto:clear()
	return self:setText("")
end

function proto:length()
	return input.length(self.text)
end

function proto:_displayText()
	if self.password then
		return string.rep(self.maskChar or "*", input.length(self.text))
	end
	return self.text
end

-- 光标位置：0 = 第一个字符前，length = 末尾
function proto:getCaret()
	return self:_clampCaret()
end

function proto:setCaret(index)
	self._caret = math.floor(tonumber(index) or 0)
	self:_clampCaret()
	self._caretTimer = 0
	self:_ensureCaretVisible()
	return self._caret
end

function proto:_clampCaret()
	local len = input.length(self.text)
	self._caret = math.max(0, math.min(math.floor(tonumber(self._caret) or len), len))
	return self._caret
end

-- 当前光标在显示文本里的像素偏移（密码模式下按掩码计算）
function proto:_caretOffset()
	self:_clampCaret()
	return self:font():getWidth(input.sub(self:_displayText(), 1, self._caret))
end

-- 文本比输入框宽时，水平滚动让光标始终在可视区
function proto:_ensureCaretVisible()
	self:_ensureSize()
	local innerW = self.w - self.paddingX * 2
	if innerW < 1 then
		innerW = 1
	end

	local textW = self:font():getWidth(self:_displayText())
	local maxScroll = math.max(0, textW - innerW)
	local caretX = self:_caretOffset()

	if caretX < self._scrollX then
		self._scrollX = caretX
	elseif caretX > self._scrollX + innerW then
		self._scrollX = caretX - innerW
	end
	self._scrollX = math.max(0, math.min(self._scrollX, maxScroll))
	return self._scrollX
end

-- 点击横坐标落在哪个字符边界（取最近的边界）
function proto:_setCaretFromX(mx)
	local f = self:font()
	local display = self:_displayText()
	local left = self.x + self.paddingX - (self._scrollX or 0)
	local localX = mx - left
	local len = input.length(display)
	local caret = len
	local previous = 0

	for i = 1, len do
		local width = f:getWidth(input.sub(display, 1, i))
		local middle = (previous + width) / 2
		if localX < middle then
			caret = i - 1
			break
		end
		previous = width
	end

	return self:setCaret(caret)
end

-- ---------- 焦点与输入 ----------

function proto:_press(mx)
	self._dragging = true
	self:_setCaretFromX(mx)
	self:focus()
	return true
end

function proto:_release()
	self._dragging = false
	return true
end

function proto:_onFocus()
	self._caretTimer = 0
	-- 移动端：带上输入框矩形，系统会把软键盘弹出来并对准它
	if love.keyboard and love.keyboard.setTextInput then
		love.keyboard.setTextInput(true, self.x, self.y, self.w, self.h)
	end
	if self.onFocus then
		self.onFocus(self)
	end
end

function proto:_onBlur()
	self._caretTimer = 0
	self._scrollX = 0
	self._dragging = false
	if love.keyboard and love.keyboard.setTextInput then
		love.keyboard.setTextInput(false)
	end
	if self.onBlur then
		self.onBlur(self)
	end
end

function proto:_tick(dt)
	self._caretTimer = (self._caretTimer or 0) + (dt or 0)

	-- 按住拖动时持续跟随鼠标，和常见输入框一致
	if self._dragging then
		if love.mouse.isDown(1) then
			self:_setCaretFromX(love.mouse.getPosition())
		else
			self._dragging = false
		end
	end

	local target = self:isFocused() and 1 or 0
	self._focus:setTarget(target)
	if self.animate == false then
		self._focus:snap(target)
	else
		self._focus:update(dt)
	end
end

function proto:_caretVisible()
	local period = self.caretPeriod or 0.5
	if period <= 0 then
		return true
	end
	return math.floor((self._caretTimer or 0) / period) % 2 == 0
end

function proto:textinput(t)
	if not self:isFocused() or not self.enabled or t == nil or t == "" then
		return false
	end

	local len = input.length(self.text)
	local add = input.length(t)
	if (self.maxLength or 0) > 0 and len + add > self.maxLength then
		return false
	end

	self:_clampCaret()
	local before = input.sub(self.text, 1, self._caret)
	local after = input.sub(self.text, self._caret + 1, len)
	self.text = before .. t .. after
	self._caret = self._caret + add
	self:_changed()
	return true
end

function proto:_changed()
	self._caretTimer = 0
	self:invalidateSize()
	self:_ensureCaretVisible()
	if self.onChange then
		self.onChange(self.text, self)
	end
end

function proto:keypressed(key)
	local len = input.length(self.text)
	self:_clampCaret()

	if key == "backspace" then
		if self._caret > 0 then
			self.text = input.sub(self.text, 1, self._caret - 1) .. input.sub(self.text, self._caret + 1, len)
			self._caret = self._caret - 1
			self:_changed()
		end
		return true
	end

	if key == "delete" then
		if self._caret < len then
			self.text = input.sub(self.text, 1, self._caret) .. input.sub(self.text, self._caret + 2, len)
			self:_changed()
		end
		return true
	end

	if key == "left" then
		self:setCaret(self._caret - 1)
		return true
	elseif key == "right" then
		self:setCaret(self._caret + 1)
		return true
	elseif key == "home" then
		self:setCaret(0)
		return true
	elseif key == "end" then
		self:setCaret(len)
		return true
	end

	if key == "return" or key == "kpenter" then
		if self.onSubmit then
			self.onSubmit(self.text, self)
		end
		return true
	end

	if key == "escape" then
		self:blur()
		return true
	end

	return false
end

-- ---------- 尺寸与绘制 ----------

function proto:measure()
	local f = self:font()

	local sample = (self.text ~= "" and self.text) or self.placeholder or ""
	if self.password then
		sample = string.rep(self.maskChar or "*", input.length(sample))
	end

	local declaredW, declaredH = self:declaredWidth(), self:declaredHeight()
	local w = type(declaredW) == "number" and declaredW
		or math.max(160, f:getWidth(tostring(sample)) + self.paddingX * 2 + 12)
	local h = type(declaredH) == "number" and declaredH or (f:getHeight() + self.paddingY * 2)

	return w, h
end

function proto:_draw()
	local f = self:font()
	local r = self:rect()
	local x, y = pixel.xy(r.x, r.y)
	local w, h = pixel.round(r.w), pixel.round(r.h)

	if (self.alpha or 255) < 255 then
		blur.drawBackdrop(x, y, w, h, r.radius)
	end

	color.setColor(self.color, self.alpha)
	love.graphics.rectangle("fill", x, y, w, h, r.radius)

	local focused = self:isFocused()
	local focusT = focused and 1 or 0
	if self.animate ~= false then
		focusT = math.min(1, math.max(0, self._focus and self._focus.value or focusT))
	end
	color.setColor(color.mix(self.borderColor or "@border", self.focusBorderColor or "@primary", focusT), self.alpha)
	love.graphics.setLineWidth(1 + focusT)
	love.graphics.rectangle("line", x, y, w, h, r.radius)

	local display = self:_displayText()
	local hasText = self.text ~= ""
	local shown = hasText and display or (self.placeholder or "")
	local textY = pixel.round(y + (h - f:getHeight()) / 2)

	if focused then
		self:_ensureCaretVisible()
	else
		self._scrollX = 0
	end
	local textX = x + self.paddingX - (self._scrollX or 0)

	love.graphics.setFont(f)

	-- 与外层裁剪求交（例如 ScrollView 的视口），不能直接覆盖
	local old, visible = clip.apply(x + 1, y + 1, w - 2, h - 2)
	if visible then
		if shown ~= "" then
			color.setColor(hasText and self.textColor or self.placeholderColor, self.alpha)
			love.graphics.print(shown, pixel.round(textX), textY)
		end

		if focused and self:_caretVisible() then
			local caretX = textX + self:_caretOffset()
			local minX = x + 1
			local maxX = x + w - 1
			caretX = math.max(minX, math.min(maxX, caretX))
			color.setColor(self.caretColor, self.alpha)
			love.graphics.rectangle("fill", pixel.round(caretX), textY, self.caretWidth or 2, f:getHeight())
		end
	end
	clip.restore(old)
end

setmetatable(TextInput, {
	__call = function(_, opts)
		return TextInput.new(opts)
	end,
})

return TextInput
