-- 组件注册表：让"创建即生效"，调用方不用逐个组件手动转发事件。
--
-- 职责：
--   登记/注销组件、按帧推进、把鼠标事件投递给组件、维护唯一的键盘焦点。
-- 组件只要实现 update / draw / mousepressed / mousereleased / textinput / keypressed
-- 中的任意一个就能接入。

local registry = {}

-- 按创建顺序保存，鼠标事件从后往前派发：后创建的组件画在更上层，先收到事件。
local components = {}

-- 同一时刻只有一个组件持有键盘焦点（文本输入框、滑动条等）
local focused = nil

function registry.add(component)
    if type(component) ~= "table" then
        error("registry.add 需要一个组件表，收到 " .. type(component), 2)
    end
    for i = 1, #components do
        if components[i] == component then
            return component
        end
    end
    components[#components + 1] = component
    return component
end

function registry.remove(component)
    for i = #components, 1, -1 do
        if components[i] == component then
            table.remove(components, i)
            if focused == component then
                focused = nil
            end
            return true
        end
    end
    return false
end

function registry.contains(component)
    for i = 1, #components do
        if components[i] == component then
            return true
        end
    end
    return false
end

function registry.all()
    return components
end

-- 清空注册表（换场景/重启时用）
function registry.clear()
    for i = #components, 1, -1 do
        components[i] = nil
    end
    focused = nil
end

-- ---------- 焦点 ----------

function registry.setFocus(component)
    if focused == component then
        return component
    end

    local previous = focused
    focused = component

    if previous and previous._onBlur then
        previous:_onBlur()
    end
    if component and component._onFocus then
        component:_onFocus()
    end

    return previous
end

function registry.getFocus()
    return focused
end

function registry.clearFocus()
    return registry.setFocus(nil)
end

function registry.isFocused(component)
    return focused == component
end

-- ---------- 事件分发 ----------

-- 正序遍历：组件可能在 update 里注销自己，所以每次取用前重新判空
function registry.update(dt)
    local i = 1
    while i <= #components do
        local component = components[i]
        if component and component.update then
            component:update(dt)
        end
        i = i + 1
    end
end

-- 倒序并在第一个命中处停止：避免底层组件"穿透"点击
-- 点到焦点之外的组件、或者点空白处，都会收走键盘焦点
function registry.mousepressed(x, y, button, istouch, presses)
    for i = #components, 1, -1 do
        local component = components[i]
        if component and component.mousepressed
            and component:mousepressed(x, y, button, istouch, presses) then
            if focused and focused ~= component then
                registry.setFocus(nil)
            end
            return true
        end
    end

    if focused then
        registry.setFocus(nil)
    end
    return false
end

-- 松开事件要发给所有组件：按下的组件可能已不在鼠标下方，需要它自己收尾
function registry.mousereleased(x, y, button, istouch, presses)
    local handled = false
    for i = #components, 1, -1 do
        local component = components[i]
        if component and component.mousereleased
            and component:mousereleased(x, y, button, istouch, presses) then
            handled = true
        end
    end
    return handled
end

-- 滚轮：按倒序派发，第一个消费即停（滚动容器用）
function registry.wheelmoved(dx, dy)
    for i = #components, 1, -1 do
        local component = components[i]
        if component and component.wheelmoved and component:wheelmoved(dx, dy) then
            return true
        end
    end
    return false
end

-- 文本输入只发给焦点组件
function registry.textinput(text)
    if focused and focused.textinput then
        return focused:textinput(text) ~= false
    end
    return false
end

-- 按键只发给焦点组件
function registry.keypressed(key, scancode, isrepeat)
    if focused and focused.keypressed then
        return focused:keypressed(key, scancode, isrepeat) ~= false
    end
    return false
end

return registry
