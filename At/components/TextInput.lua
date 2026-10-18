-- 单行文本输入框：点击获取焦点，回车提交，Esc 失焦，光标固定在末尾。
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

	color = "#2A2F3A",
	alpha = 255,
	borderColor = "#4A5160",
	focusBorderColor = "#9FB3D3",
	textColor = "#E8ECF2",
	placeholderColor = "#7C8494",
	caretColor = "#9FB3D3",
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
	self._caretTimer = 0
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

-- silent = true 时不触发 onChange
function proto:setText(text, silent)
	self.text = tostring(text or "")
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

-- ---------- 焦点与输入 ----------

function proto:_press()
	self:focus()
	self._caretTimer = 0
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
	if love.keyboard and love.keyboard.setTextInput then
		love.keyboard.setTextInput(false)
	end
	if self.onBlur then
		self.onBlur(self)
	end
end

function proto:_tick(dt)
	self._caretTimer = (self._caretTimer or 0) + (dt or 0)

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

	local nextText = self.text .. t
	if (self.maxLength or 0) > 0 and input.length(nextText) > self.maxLength then
		return false
	end

	self.text = nextText
	self._caretTimer = 0
	self:invalidateSize()

	if self.onChange then
		self.onChange(self.text, self)
	end
	return true
end

function proto:keypressed(key)
	if key == "backspace" then
		if self.text ~= "" then
			self.text = input.removeLast(self.text)
			self._caretTimer = 0
			self:invalidateSize()
			if self.onChange then
				self.onChange(self.text, self)
			end
		end
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
	color.setColor(color.mix(self.borderColor or "#4A5160", self.focusBorderColor or "#9FB3D3", focusT), self.alpha)
	love.graphics.setLineWidth(1 + focusT)
	love.graphics.rectangle("line", x, y, w, h, r.radius)

	local display = self:_displayText()
	local hasText = self.text ~= ""
	local shown = hasText and display or (self.placeholder or "")
	local textY = pixel.round(y + (h - f:getHeight()) / 2)
	local textX = x + self.paddingX

	love.graphics.setFont(f)

	-- 与外层裁剪求交（例如 ScrollView 的视口），不能直接覆盖
	local old, visible = clip.apply(x + 1, y + 1, w - 2, h - 2)
	if visible then
		if shown ~= "" then
			color.setColor(hasText and self.textColor or self.placeholderColor, self.alpha)
			love.graphics.print(shown, textX, textY)
		end

		if focused and self:_caretVisible() then
			local caretX = textX + f:getWidth(display)
			local maxX = x + w - self.paddingX
			if caretX > maxX then
				caretX = maxX
			end
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
