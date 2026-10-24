-- Dialog：一次性模态对话框。两种模式使用相同大小的卡片：
-- fullscreen 时整窗铺一层压暗/模糊背景，卡片不可拖动；
-- 非 fullscreen 时是可拖标题栏的浮动窗口，不压暗背景。
--
--   local dialog = At.Dialog{
--       title = "确认操作",
--       message = "确定要删除吗？",
--       fullscreen = false,
--       actions = {
--           { text = "取消" },
--           { text = "确定", color = "@primary", onClick = function(d) ... end },
--       },
--   }
--
-- Dialog 自动登记；要盖在页面最上层，需在 love.draw 最后调用 dialog:draw()。
-- 关闭动画结束后自动 destroy()；At.update(dt) 负责推进动画与拖动。

local Component = require("At.core.component")
local registry = require("At.core.registry")
local motion = require("At.core.motion")
local pixel = require("At.core.pixel")
local color = require("At.core.color")
local Panel = require("At.components.Panel")
local Button = require("At.components.Button")
local Label = require("At.components.Label")
local blur = require("At.effects.blur")

local Dialog = {}
local proto = setmetatable({}, { __index = Component })
proto.__index = proto

local DEFAULTS = {
	fullscreen = false, -- true：不可拖动、压暗背景；false：浮动可拖动、不压暗
	title = "对话框",
	message = "",
	width = 380,
	padding = 20,
	gap = 12,
	radius = 14,
	background = "@surface",
	borderColor = "@border",
	shadow = true,
	titleColor = "@text",
	textColor = "@textMuted",
	actions = {},
	content = {},
	closeButton = true,
	dimAlpha = 0.55,
	animate = true,
	springStiffness = 380,
	springDamping = 28,
	onClose = nil,
}

-- 把卡片里的组件移到注册表末尾，确保它们先于 Dialog 收到事件；
-- 否则用户传入的 content 在 Dialog 之前创建时会被全屏遮罩吃掉点击。
local function lift(component)
	if not component then
		return
	end
	if component.autoRegister ~= false then
		registry.remove(component)
		registry.add(component)
	end
	if component.children then
		for i = 1, #component.children do
			lift(component.children[i])
		end
	end
end

function Dialog.new(opts)
	opts = opts or {}
	local self = Component.instantiate(proto, opts, DEFAULTS)

	self._open = motion.spring({
		value = self.animate == false and 1 or 0,
		stiffness = self.springStiffness,
		damping = self.springDamping,
	})
	self._closing = false
	self._finished = false
	self._dragging = false
	self._dragged = false
	self._cardX = nil
	self._cardY = nil

	self.card = Panel({
		direction = "column",
		gap = self.gap,
		padding = self.padding,
		align = "stretch",
		background = self.background,
		borderColor = self.borderColor,
		borderWidth = 1,
		radius = self.radius,
		shadow = self.shadow and not self.fullscreen,
		autoRegister = false,
	})

	if self.closeButton ~= false then
		-- 关闭按钮不参与 header 的布局：header 里的 wrap Label 在 row 中会把
		-- 可用宽度全部吃掉，导致按钮被推到卡片外；这里固定在卡片右上角。
		self.closeButton = Button({
			w = 30,
			h = 30,
			text = "×",
			color = "@surfaceStrong",
			onClick = function()
				self:close()
			end,
		})
	end

	local header = Panel({
		direction = "row",
		align = "center",
		padding = { right = self.closeButton and 38 or 0 },
		autoRegister = false,
	})
	header:add(Label({
		text = tostring(self.title or ""),
		fontSize = 18,
		color = self.titleColor,
		wrap = true,
	}))
	self.header = header
	self.card:add(header)

	self.messageLabel = Label({
		text = tostring(self.message or ""),
		fontSize = 15,
		color = self.textColor,
		wrap = true,
	})
	if self.message ~= nil and tostring(self.message) ~= "" then
		self.card:add(self.messageLabel)
	end

	local content = self.content or {}
	for i = 1, #content do
		self.card:add(content[i])
	end

	if self.fullscreen then
		-- 全屏时把操作区推到卡片底部
		self.card:add(Panel({ grow = 1, autoRegister = false }))
	end

	local actions = self.actions or {}
	if #actions > 0 then
		local row = Panel({
			direction = "row",
			justify = "end",
			gap = 8,
			autoRegister = false,
		})
		for i = 1, #actions do
			local action = actions[i]
			local button = Button({
				w = action.width or 96,
				h = 36,
				text = tostring(action.text or "确定"),
				color = action.color or "@surfaceStrong",
			})
			button.onClick = function(btn, mx, my)
				if action.onClick then
					action.onClick(self, btn, mx, my)
				end
				if action.close ~= false then
					self:close()
				end
			end
			row:add(button)
		end
		self.card:add(row)
	end

	-- 确保卡片内部组件（尤其是用户传入的 content）排在 Dialog 之后。
	for i = 1, #self.card.children do
		lift(self.card.children[i])
	end
	if self.closeButton then
		lift(self.closeButton)
	end

	return self
end

function proto:isOpen()
	return not self._finished and not self._closing
end

function proto:close()
	if self._closing or self._finished then
		return self
	end
	self._closing = true
	if self.animate == false then
		self._open:snap(0)
		self:_finish()
	end
	return self
end

function proto:_finish()
	if self._finished then
		return
	end
	self._finished = true
	if self.onClose then
		self.onClose(self)
	end
	self:destroy()
end

function proto:destroy()
	if self.closeButton then
		self.closeButton:destroy()
		self.closeButton = nil
	end
	if self.card then
		self.card:destroy()
		self.card = nil
	end
	return Component.destroy(self)
end

local function clamp(value, low, high)
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

-- 计算窗口区域和 card 的位置/尺寸
function proto:_layout()
	local sw, sh = love.graphics.getDimensions()
	self.x, self.y, self.w, self.h = 0, 0, sw, sh

	-- 两种模式共用同一套卡片尺寸；fullscreen 只改变背景遮罩和是否可拖动。
	local w = math.min(self.width or 380, math.max(120, sw - 80))
	self.card:setSize(w, "auto")
	local _, measuredH = self.card:measure(w, 0)
	local h = math.min(measuredH or 120, math.max(1, sh - 40))

	local x, y
	if not self.fullscreen and self._dragged and self._cardX and self._cardY then
		x = clamp(self._cardX, 0, math.max(0, sw - w))
		y = clamp(self._cardY, 0, math.max(0, sh - h))
	else
		x = math.max(0, (sw - w) / 2)
		y = math.max(0, (sh - h) / 2)
	end
	self._cardX, self._cardY = x, y
	self.card.alpha = 255
	self.card:setRect(x, y, w, h)
end

function proto:_tick(dt)
	self:_layout()

	local target = self._closing and 0 or 1
	self._open:setTarget(target)
	if self.animate == false then
		self._open:snap(target)
	else
		self._open:update(dt)
	end

	if self._closing then
		if self._open.value <= 0.01 then
			self:_finish()
		end
		return
	end

	if self._dragging and not self.fullscreen and self.card then
		if love.mouse.isDown and not love.mouse.isDown(1) then
			self._dragging = false
		end
	end
	if self._dragging and not self.fullscreen and self.card then
		local mx, my = love.mouse.getPosition()
		local sw, sh = love.graphics.getDimensions()
		local w, h = self.card.w, self.card.h
		self._dragged = true
		self._cardX = clamp(mx - (self._dragDX or 0), 0, math.max(0, sw - w))
		self._cardY = clamp(my - (self._dragDY or 0), 0, math.max(0, sh - h))
	end
end

function proto:_press(mx, my)
	if self.fullscreen or not self.card then
		return true
	end

	local headerH = 56
	if my >= self.card.y and my <= self.card.y + headerH and mx >= self.card.x and mx <= self.card.x + self.card.w then
		self._dragging = true
		self._dragDX = mx - self.card.x
		self._dragDY = my - self.card.y
		self._dragged = true
	end
	return true
end

function proto:_release()
	self._dragging = false
	return true
end

function proto:_draw()
	if not self.card then
		return
	end
	self:_layout()

	local open = math.min(1, math.max(0, self._open.value))
	if open <= 0 then
		return
	end

	if self.fullscreen then
		-- 全屏模式只是铺满窗口的模态遮罩，卡片本身与浮动模式同尺寸。
		if blur.isEnabled() then
			blur.drawBackdrop(0, 0, self.w, self.h, 0)
		end
		color.setColor("000000", math.floor(255 * (self.dimAlpha or 0.55) * open))
		love.graphics.rectangle("fill", 0, 0, self.w, self.h)
	end

	if self.animate and not self.fullscreen then
		self.card.y = self.card.y + (1 - open) * 12
	end

	self.card:draw()
	if self.closeButton then
		local pad = self.padding or 20
		local headerH = self.header and self.header.h or 30
		self.closeButton:setPosition(
			self.card.x + self.card.w - pad - self.closeButton.w,
			self.card.y + pad + math.max(0, (headerH - self.closeButton.h) / 2)
		)
		self.closeButton:draw()
	end
end

setmetatable(Dialog, {
	__call = function(_, opts)
		return Dialog.new(opts)
	end,
})

return Dialog
