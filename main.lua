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
local submitBtn, nameInput

local function setStatus(text)
    if statusLabel then
        statusLabel:setText(text)
    end
end

local function refreshState()
    if not stateLabel then
        return
    end
    stateLabel:setText(string.format(
        "焦点：%s    昵称：%s",
        (nameInput and nameInput:isFocused()) and "输入框" or "无",
        state.nickname ~= "" and state.nickname or "（空）"
    ))
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

card = At.Panel{
    w = "100%", h = "auto",
    direction = "column",
    gap = 14,
    padding = 20,
    radius = 16,
    background = "#242A34",
    borderColor = "#39404D",
    shadow = false,   -- 想要柔和阴影可改成 { { 0, 0, 0, 0.18 }, 6, 12, 0, 4 }
}

card:add(At.Label{ text = "At 组件演示", fontSize = 22 })
card:add(At.Label{
    text = "卡片由 Panel 排版；外层 ScrollView 负责裁剪与滚动，窗口小的时候用滚轮或拖动空白处查看下面的内容。",
    wrap = true, w = "100%", lineHeight = 1.4, color = "#A9B2C2",
})

nameInput = At.TextInput{
    w = "100%",
    placeholder = "输入昵称，回车提交（Esc 失焦）",
    text = state.nickname,
    maxLength = 16,
    onChange = function(text)
        state.nickname = text
        refreshState()
    end,
    onFocus = function(self)
        -- 移动端：聚焦时把这个输入框滚进可视区，别被软键盘挡住
        if viewport then
            viewport:scrollToVisible(self, 24)
        end
        refreshState()
        setStatus("输入框已聚焦，软键盘应弹出")
    end,
    onBlur = function()
        refreshState()
    end,
    onSubmit = function(text)
        if text == "" then
            setStatus("请先输入昵称")
        else
            setStatus("已提交：" .. text)
        end
    end,
}

card:add(nameInput)

card:add(At.Panel{
    direction = "row", align = "center", gap = 10,
    children = {
        At.Label{ text = "涟漪特效", fontSize = 15 },
        At.Switch{
            value = state.ripples,
            onChange = function(value)
                state.ripples = value
                if submitBtn then
                    submitBtn:setRippleEnabled(value)
                end
                setStatus(value and "涟漪已开启" or "涟漪已关闭")
            end,
        },
    },
})

card:add(At.Label{
    text = "开关可以点击切换，也可以按住左右拖动",
    fontSize = 13, color = "#8F98A8",
})

card:add(At.RadioGroup{
    options = { "低", "中", "高" },
    value = state.quality,
    direction = "row",
    gap = 24,
    onChange = function(index, label)
        state.quality = index
        setStatus("画质：" .. label)
    end,
})

volumeLabel = At.Label{ text = "音量：" .. state.volume, fontSize = 15, color = "#A9B2C2" }
card:add(volumeLabel)

card:add(At.Slider{
    w = "100%",
    min = 0, max = 100, step = 5,
    value = state.volume,
    onChange = function(value)
        state.volume = value
        volumeLabel:setText("音量：" .. value)
    end,
})

local resetBtn = At.Button{
    w = "48%",
    text = "重置",
    color = "#5A6374",
    onClick = function()
        state.volume = 60
        volumeLabel:setText("音量：60")
        setStatus("已重置")
    end,
}

submitBtn = At.Button{
    w = "48%",
    text = "提交",
    color = "#7FA88F",
    onClick = function()
        setStatus(state.nickname ~= "" and ("已提交：" .. state.nickname) or "请先输入昵称")
    end,
}

card:add(At.Panel{
    direction = "row", gap = 12,
    children = { resetBtn, submitBtn },
})

card:add(At.Checkbox{
    text = "记住昵称",
    checked = false,
    onChange = function(checked)
        setStatus(checked and "下次会记住昵称" or "不再记住昵称")
    end,
})

statusLabel = At.Label{ text = "试试点击、拖动、输入", fontSize = 15, color = "#9FB3D3" }
card:add(statusLabel)

stateLabel = At.Label{ text = "焦点：无", fontSize = 14, color = "#8F98A8" }
card:add(stateLabel)

-- ---------- 滚动视口 ----------

local vw, vh, vx = viewportSize()
viewport = At.ScrollView{
    x = vx, y = 40,
    w = vw, h = vh,
    content = card,
    scrollbar = true,
}

function love.load()
    At.font.init(16)
    love.graphics.setBackgroundColor(At.color.hexToRGBA("#1B1F27"))
end

function love.update(dt)
    At.update(dt)
end

function love.draw()
    viewport:draw()
end

function love.resize(screenW, screenH)
    local sizeW, sizeH, offsetX = viewportSize(screenW, screenH)
    viewport:setRect(offsetX, 40, sizeW, sizeH)
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
    At.keypressed(key)
end

-- 切到后台时收起软键盘
function love.focus(focused)
    if not focused then
        At.blur()
    end
end
