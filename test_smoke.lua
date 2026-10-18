-- 无头冒烟测试：用假的 love 环境跑组件逻辑，不需要 LÖVE 运行时。
--
--   lua test_smoke.lua      -- 在项目根目录执行，全部通过会打印 SMOKE OK
--
-- 覆盖：组件注册/事件分发、命中与圆角边界、按压会话（拖出/拖回）、
-- 涟漪生成与回收、帧率无关性、旧 API 兼容、演示程序回调接线。
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

local function makeFont(size)
    return {
        size = size,
        setFallbacks = function() end,
        getWidth = function(_, s) return #s * size * 0.5 end,
        getHeight = function() return size end,
        getWrap = function(_, s, limit) return limit, { s } end,
    }
end

love = {
    graphics = {
        setColor = function(r, g, b, a) colorState = { r, g, b, a } end,
        getColor = function()
            return colorState[1], colorState[2], colorState[3], colorState[4]
        end,
        setFont = function(f) currentFont = f end,
        getFont = function() return currentFont or makeFont(16) end,
        newFont = function(_, size) return makeFont(size) end,
        rectangle = function() draws.rect = draws.rect + 1 end,
        print = function(text, x, y)
            draws.print = draws.print + 1
            lastPrint = { text = text, x = x, y = y }
        end,
        printf = function() draws.print = draws.print + 1 end,
        line = function() draws.line = (draws.line or 0) + 1 end,
        circle = function() draws.circle = (draws.circle or 0) + 1 end,
        setLineWidth = function(w) lineWidth = w end,
        getLineWidth = function() return lineWidth end,
        setLineStyle = function(style) lineStyle = style end,
        getLineStyle = function() return lineStyle end,
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
        getDimensions = function() return 800, 600 end,
        getWidth = function() return 800 end,
        getHeight = function() return 600 end,
    },
    mouse = {
        getPosition = function() return mouseX, mouseY end,
        isDown = function(button) return mouseDown and button == 1 end,
    },
    keyboard = {
        setTextInput = function(enabled, x, y, w, h)
            textInputOn = enabled and true or false
            textInputRect = { x, y, w, h }
        end,
    },
}

local At = require("At.At")

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

-- ---------- 颜色 ----------
local light = At.color.shade("#808080", 0.1)
local dark = At.color.shade("#808080", -0.12)
check(light == "#8D8D8D", "shade 调亮: " .. light)
check(dark == "#717171", "shade 调暗: " .. dark)

-- ---------- 按钮基本行为 ----------
local clicks, presses, releases = 0, 0, 0
local btn = At.Button{
    x = 100, y = 100, w = 160, h = 60, radius = 12,
    text = "OK",
    fontSize = 16,
    onPress = function() presses = presses + 1 end,
    onRelease = function() releases = releases + 1 end,
    onClick = function() clicks = clicks + 1 end,
}
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
for _ = 1, 60 do fx60:update(1 / 60) end
for _ = 1, 120 do fx120:update(1 / 120) end
local a60 = fx60.ripples[1] and fx60.ripples[1].alpha or 0
local a120 = fx120.ripples[1] and fx120.ripples[1].alpha or 0
check(math.abs(a60 - a120) < 0.02, "1s 后透明度与帧率无关: " .. a60 .. " vs " .. a120)

-- ---------- 旧单例 API 兼容 ----------
At.Ripple.add(1, 1, 0, 0, 50, 20, 4)
check(At.Ripple.count() == 1, "旧 Ripple.add 可用")
At.Ripple.release() -- 不松手的涟漪不会被回收（与旧实现一致）
for _ = 1, 240 do At.Ripple.update() end
check(At.Ripple.count() == 0, "旧 Ripple.update 回收")
At.Ripple.setEnabled(false)
check(At.Ripple.add(1, 1, 0, 0, 50, 20, 4) == false, "旧 Ripple.setEnabled 生效")
At.Ripple.setEnabled(true)

-- ---------- 旧立即模式 ----------
local rect = At.button(10, 10, 50, 20, 4, "#000000", 255, true, { { 0, 0, 0, 0.2 }, 5, 20, 2, 3 })
check(rect.w == 50 and rect.radius == 4, "旧 At.button 仍返回矩形表")

-- ---------- 禁用 / 销毁 ----------
local disabled = At.Button{ x = 0, y = 0, w = 50, h = 50, enabled = false, text = "X" }
disabled:draw()
check(At.mousepressed(10, 10, 1) == false, "禁用按钮不消费事件")
check(disabled:rippleCount() == 0, "禁用按钮不产生涟漪")

local temp = At.Button{ x = 700, y = 700, w = 50, h = 50 }
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
local styled = At.Button{ x = 0, y = 0, w = 10, h = 10, color = "#808080" }
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
local col = At.Panel{
    x = 100, y = 50, w = 200, h = "auto",
    direction = "column", gap = 10, padding = 10,
    children = {
        At.Label{ text = "A", fontSize = 10 },
        At.Label{ text = "BB", fontSize = 10 },
    },
}
col:draw()
check(approx(col.h, 54), "列方向 auto 高度 = 12+10+12+20: " .. col.h)
check(approx(col.children[1].y, 60), "第一个子项 y")
check(approx(col.children[2].y, 82), "第二个子项 y")
check(approx(col.children[1].w, 5), "Label auto 宽度")
check(approx(col.children[1].x, 110), "左边距 + padding")

-- 行方向 + 百分比
local rowPct = At.Panel{
    x = 0, y = 0, w = 200, h = 40, direction = "row", gap = 0, padding = 0,
    children = { At.Label{ text = "x", w = "50%", fontSize = 10 } },
}
rowPct:draw()
check(approx(rowPct.children[1].w, 100), "百分比宽度: " .. rowPct.children[1].w)

-- grow：主轴上瓜分剩余空间
local rowGrow = At.Panel{
    x = 0, y = 0, w = 200, h = 40, direction = "row", gap = 10, padding = 0,
    children = {
        At.Button{ w = 50, h = 40, text = "" },
        At.Button{ w = "auto", h = 40, grow = 1, text = "b", fontSize = 10 },
    },
}
rowGrow:draw()
check(approx(rowGrow.children[2].w, 140), "grow 撑满剩余: " .. rowGrow.children[2].w)

-- 交叉轴居中
local centered = At.Panel{
    x = 0, y = 0, w = 100, h = 30, direction = "column", align = "center",
    children = { At.Label{ text = "x", w = 40, h = 10, fontSize = 10 } },
}
centered:draw()
check(approx(centered.children[1].x, 30), "align center: " .. centered.children[1].x)

-- 主轴居中（justify）
local justified = At.Panel{
    x = 0, y = 0, w = 50, h = 100, direction = "column", justify = "center",
    children = { At.Label{ text = "x", w = 10, h = 20, fontSize = 10 } },
}
justified:draw()
check(approx(justified.children[1].y, 40), "justify center: " .. justified.children[1].y)

-- margin 与嵌套容器
local outer = At.Panel{
    x = 10, y = 10, w = "auto", h = "auto", padding = 5,
    children = {
        At.Panel{
            direction = "row", gap = 6, padding = 0,
            children = {
                At.Label{ text = "aa", fontSize = 10 },
                At.Label{ text = "bb", fontSize = 10 },
            },
        },
        At.Label{ text = "z", fontSize = 10, margin = { left = 4 } },
    },
}
outer:draw()
check(approx(outer.w, 10 + 6 + 10 + 10), "嵌套容器 auto 宽度: " .. outer.w)
check(approx(outer.children[2].x, 15 + 4), "margin.left 生效")
check(approx(outer.children[1].children[2].x, 15 + 10 + 6), "嵌套行方向排布")

-- 重排不会把 auto 尺寸固化死
local relayout = At.Panel{
    x = 0, y = 0, w = 100, h = "auto", padding = 0,
    children = { At.Label{ text = "abc", fontSize = 10 } },
}
relayout:draw()
check(approx(relayout.h, 12), "首次排版高度")
relayout.children[1]:setText("abcdef")
relayout:draw()
check(approx(relayout.h, 12), "高度仍是单行")
check(relayout.children[1].w == 30, "文字变长后重新测量: " .. relayout.children[1].w)

-- ---------- TextInput ----------
At.registry.clear()

local typed, submitted
local ti = At.TextInput{
    x = 10, y = 10, w = 200, h = 40,
    onChange = function(text) typed = text end,
    onSubmit = function(text) submitted = text end,
}

mouseX, mouseY = 20, 20
check(At.mousepressed(20, 20, 1) == true, "输入框消费点击")
At.mousereleased(20, 20, 1)
check(ti:isFocused(), "点击后获得焦点")
check(textInputOn == true, "聚焦时启用文本输入（唤起软键盘）")
check(textInputRect ~= nil and textInputRect[3] == ti.w and textInputRect[4] == ti.h,
    "把输入框矩形传给 setTextInput，系统据此定位软键盘")

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

-- ---------- Switch ----------
At.registry.clear()

local swValue
local sw = At.Switch{
    x = 0, y = 0, value = false,
    onChange = function(value) swValue = value end,
}

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
local cb = At.Checkbox{
    x = 0, y = 0, text = "记住我",
    onChange = function(value) cbValue = value end,
}

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
local rg = At.RadioGroup{
    x = 0, y = 0,
    options = { "A", "B", "C" },
    value = 1,
    gap = 4, size = 20, textGap = 8,
    onChange = function(index, label) rgValue = tostring(index) .. label end,
}

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

local rgRow = At.RadioGroup{
    x = 0, y = 100, options = { "a", "b" }, direction = "row", gap = 10,
}
rgRow:draw()
check(rgRow.children == nil, "RadioGroup 不持有子组件")
check(approx(rgRow.w, (20 + 8 + 8) * 2 + 10), "横排 auto 宽度: " .. rgRow.w)

-- ---------- Slider ----------
At.registry.clear()

local slValue
local sl = At.Slider{
    x = 0, y = 0, w = 200, h = 28,
    min = 0, max = 100, step = 5, value = 0,
    onChange = function(value) slValue = value end,
}

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
local slStep = At.Slider{ x = 0, y = 0, min = 0, max = 10, step = 3, value = 0 }
slStep:setValue(7)
check(slStep.value == 6, "按 step 吸附: " .. tostring(slStep.value))
slStep:setValue(100)
check(slStep.value == 9, "clamp 到能取到的最大值: " .. tostring(slStep.value))

-- ---------- Panel 的穿透与排版 ----------
At.registry.clear()

local clicked = 0
local inner = At.Button{
    x = 0, y = 0, w = 60, h = 24, text = "in",
    onClick = function() clicked = clicked + 1 end,
}
local wrap = At.Panel{
    x = 0, y = 0, w = 200, h = 100, gap = 8, padding = 0,
    background = "#222831",
    children = { At.Label{ text = "t", fontSize = 10 }, inner },
}

check(not At.registry.contains(wrap), "Panel 不登记到事件表")
wrap:draw()
check(approx(inner.y, 20), "Panel 把子按钮排到第二行: " .. inner.y)

check(At.mousepressed(20, 30, 1) == true, "容器内的按钮能收到点击")
At.mousereleased(20, 30, 1)
check(clicked == 1, "容器内的按钮点击生效")

-- ---------- ScrollView ----------
At.registry.clear()

local contentPanel = At.Panel{ w = "100%", h = "auto", gap = 10, padding = 10, direction = "column" }
for i = 1, 8 do
    contentPanel:add(At.Label{ text = "行 " .. i, fontSize = 12, w = 60 })
end

local view = At.ScrollView{ x = 0, y = 0, w = 200, h = 100, content = contentPanel }
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
local instantView = At.ScrollView{
    x = 0, y = 0, w = 200, h = 60, content = contentPanel, smooth = false,
}
instantView:layout()
instantView:scrollTo(30)
check(instantView.scrollY == 30, "smooth = false 时直接到位: " .. instantView.scrollY)
instantView.content = nil   -- 内容与 view 共用，别连带销毁
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
local blockContent = At.Panel{ w = "100%", h = "auto", padding = 0, children = {
    At.Button{ x = 0, y = 0, w = 100, h = 40, text = "b" },
} }
local blockView = At.ScrollView{ x = 0, y = 0, w = 200, h = 100, content = blockContent }
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

-- ---------- 阴影层数归一化 ----------
local alphas = {}
local realSetColor = love.graphics.setColor
love.graphics.setColor = function(r, g, b, a)
    alphas[#alphas + 1] = a
    realSetColor(r, g, b, a)
end
At.shadow.shadow(0, 0, 100, 50, 6, { 0, 0, 0, 0.25 }, 6, 20, 0, 4)
love.graphics.setColor = realSetColor

check(#alphas == 21, "阴影按 layers+1 层绘制: " .. #alphas)
local alphaSum = 0
for _, a in ipairs(alphas) do
    alphaSum = alphaSum + a
end
check(alphaSum < 0.6, "阴影透明度按层数归一化，不会叠成黑底: " .. alphaSum)
check(alphaSum > 0.1, "阴影仍然可见: " .. alphaSum)

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

-- ---------- 像素对齐 / 线型 ----------
local aligned = At.Panel{
    x = 0, y = 0, w = 101, h = "auto", padding = 0, direction = "row",
    children = {
        At.Label{ text = "a", w = "33%", fontSize = 10 },
        At.Label{ text = "b", w = "33%", fontSize = 10 },
        At.Label{ text = "c", w = "33%", fontSize = 10 },
    },
}
aligned:draw()
for i = 1, #aligned.children do
    local child = aligned.children[i]
    check(child.x == math.floor(child.x), "子项 x 对齐整数: " .. child.x)
    check(child.w == math.floor(child.w), "子项 w 对齐整数: " .. child.w)
end

aligned.children[1]:draw()
check(lastPrint ~= nil, "文字已经绘制")
check(lastPrint.x == math.floor(lastPrint.x) and lastPrint.y == math.floor(lastPrint.y),
    "文字位置对齐整数像素")

check(love.graphics.getLineStyle() == "smooth", "绘制后线型已恢复为 smooth")
check(love.graphics.getLineWidth() == 1, "绘制后线宽已恢复")

-- ---------- 演示程序接线（main.lua 回调） ----------
At.input.setActive(false)
At.registry.clear()
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

local demoInput = findComponent(function(c) return c.textinput ~= nil end)
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

mouseX, mouseY = submit.x + 10, submit.y + 10
love.update(1 / 60)
love.mousepressed(mouseX, mouseY, 1)
love.mousereleased(mouseX, mouseY, 1)

local statusShown = findComponent(function(c)
    return c.text ~= nil and type(c.text) == "string" and c.text:find("已提交", 1, true) ~= nil
end)
check(statusShown ~= nil, "提交按钮更新了状态标签")

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
    "At.Button", "At.Label", "At.Panel", "At.TextInput",
    "At.Switch", "At.Checkbox", "At.RadioGroup", "At.Slider", "At.ScrollView",
}) do
    check(fileContains("docs/components.md", name), "docs/components.md 缺少 " .. name)
end

check(fileContains("docs/layout.md", "grow"), "docs/layout.md 缺少 grow 说明")
check(fileContains("docs/layout.md", "justify"), "docs/layout.md 缺少 justify 说明")
check(fileContains("docs/README.md", "love.update"), "docs/README.md 缺少快速开始")
check(fileContains("AGENTS.md", "文档规范"), "AGENTS.md 缺少文档规范章节")

-- ---------- 许可证 ----------
check(fileContains("LICENSE", "MIT License"), "LICENSE 是 MIT 许可")
check(fileContains("docs/README.md", "LICENSE"), "README 有许可证章节")

check(fileContains("LICENSES/OFL-1.1.txt", "SIL OPEN FONT LICENSE Version 1.1"),
    "OFL 1.1 许可全文存在")
check(fileContains("THIRD_PARTY_NOTICES.md", "Noto Sans SC"), "第三方声明缺少 Noto Sans SC")
check(fileContains("THIRD_PARTY_NOTICES.md", "Noto Emoji"), "第三方声明缺少 Noto Emoji")
check(fileContains("THIRD_PARTY_NOTICES.md", "SIL Open Font License"),
    "第三方声明缺少 OFL 说明")
check(fileContains("LICENSES/Noto-Sans-SC.txt", "Adobe"),
    "Noto Sans SC 缺少版权方声明")
check(fileContains("LICENSES/Noto-Emoji.txt", "Google"),
    "Noto Emoji 缺少版权方声明")
check(fileContains("LICENSES/README.txt", "MIT"), "LICENSES/README.txt 汇总许可说明")

print(string.format("SMOKE OK  绘制调用: rect=%d print=%d", draws.rect, draws.print))
