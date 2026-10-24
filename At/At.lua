local At = {}

At.config = require("At.config")

At.color = require("At.core.color")
At.theme = require("At.core.theme")
At.SDF = require("At.core.SDF")
At.shadow = require("At.core.shadow")
At.input = require("At.core.input")
At.font = require("At.core.font")
At.Ripple = require("At.effects.Ripple")
At.registry = require("At.core.registry")
At.layout = require("At.core.layout")
At.clip = require("At.core.clip")
At.pixel = require("At.core.pixel")
At.motion = require("At.core.motion")
At.render = require("At.core.render")
At.Component = require("At.core.component")
At.log = require("At.core.log")
At.system = require("At.core.system")
At.blur = require("At.effects.blur")

-- 组件
At.Button = require("At.components.Button")
At.Label = require("At.components.Label")
At.Panel = require("At.components.Panel")
At.TextInput = require("At.components.TextInput")
At.Switch = require("At.components.Switch")
At.Checkbox = require("At.components.Checkbox")
At.RadioGroup = require("At.components.RadioGroup")
At.Slider = require("At.components.Slider")
At.Dial = require("At.components.Dial")
At.ProgressBar = require("At.components.ProgressBar")
At.LoadingBar = require("At.components.LoadingBar")
At.ScrollView = require("At.components.ScrollView")
At.Console = require("At.components.Console")

-- ---------- 组件生命周期 ----------
-- 组件创建时自动登记，调用方只需把这几个入口接到 love 回调上。
-- 返回值表示事件是否被某个组件消费，可用于"点空白处关闭面板"之类的判断。

function At.add(component)
	return At.registry.add(component)
end

function At.remove(component)
	return At.registry.remove(component)
end

function At.update(dt)
	At.registry.update(dt)
end

function At.mousepressed(x, y, button, istouch, presses)
	return At.registry.mousepressed(x, y, button, istouch, presses)
end

function At.mousereleased(x, y, button, istouch, presses)
	return At.registry.mousereleased(x, y, button, istouch, presses)
end

-- 文本输入与按键只发给当前焦点组件（TextInput / Slider 等）
function At.textinput(text)
	return At.registry.textinput(text)
end

function At.keypressed(key, scancode, isrepeat)
	return At.registry.keypressed(key, scancode, isrepeat)
end

function At.wheelmoved(dx, dy)
	return At.registry.wheelmoved(dx, dy)
end

function At.focus(component)
	return At.registry.setFocus(component)
end

function At.clearFocus()
	return At.registry.setFocus(nil)
end

function At.getFocus()
	return At.registry.getFocus()
end

-- 便捷构造：At.button 是旧式立即绘制，At.Button 是组件式（推荐）
function At.newButton(opts)
	return At.Button.new(opts)
end

-- ---------- 旧式立即模式绘制（保留兼容） ----------
-- 注意：它不持有任何状态，也没有涟漪；新代码请用 At.Button。
function At.button(x, y, w, h, res, hex, alpha, shadow, shadowArgs)
	if shadow then
		if shadowArgs then
			At.shadow.shadow(x, y, w, h, res, unpack(shadowArgs))
		else
			At.shadow.shadow(x, y, w, h, res)
		end
	end
	if hex then
		At.color.setColor(hex, alpha)
	else
		At.color.setColor("000000")
	end
	love.graphics.rectangle("fill", x, y, w, h, res)
	return { x = x, y = y, w = w, h = h, radius = res }
end

-- 把 At/config.lua 的默认值推给各模块；运行时改了 config 再调一次 apply() 即可
At.config.apply()

return At
