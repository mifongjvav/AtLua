-- 极简 CSS 式布局引擎：只算矩形，不画像素，因此可以在无 LÖVE 环境里测试。
--
-- 支持的 CSS 子集：
--   direction  column / row          ≈ flex-direction
--   gap                              ≈ gap
--   padding / margin                 ≈ number 或 { left, top, right, bottom }
--   w / h                            ≈ width / height：数字、"50%"、"auto"
--   grow                             ≈ flex-grow（瓜分主轴上剩余空间）
--   align                            ≈ align-items：start / center / end / stretch
--   justify                          ≈ justify-content：start / center / end / space-between
--   wrap / flexWrap                  ≈ flex-wrap：wrap
--   alignContent                     ≈ align-content（换行后的多行/多列整体对齐）
--   display = "grid" + grid          ≈ grid：基础行优先网格
--   position = "absolute"            ≈ position: absolute；left/top/right/bottom
--   zIndex                           ≈ 绘制层级（由 Panel 排序，非布局）
--
-- 不支持：flex-shrink、grid span/命名区域、wrap-reverse、aspect-ratio。

local pixel = require("At.core.pixel")

local layout = {}

-- 边距/内边距：number → 四边相同；table → { left, top, right, bottom }
function layout.sides(value)
	if value == nil then
		return 0, 0, 0, 0
	end
	if type(value) == "number" then
		return value, value, value, value
	end
	return value.left or 0, value.top or 0, value.right or 0, value.bottom or 0
end

-- 尺寸解析：数字、"50%"、"auto"（返回 nil）
function layout.pixels(value, base)
	if type(value) == "number" then
		return value
	end
	if type(value) ~= "string" then
		return nil
	end
	if value == "auto" or value == "" then
		return nil
	end
	local percent = string.match(value, "^%s*([%d%.]+)%%%s*$")
	if percent then
		if base == nil then
			return nil -- 父容器没给可用宽度时，百分比退化成 auto
		end
		return tonumber(percent) / 100 * base
	end
	return tonumber(value)
end

-- 子项自然尺寸：显式尺寸优先，auto 时问组件要 measure
function layout.childMeasure(child, availW, availH)
	-- 优先用原始规格：排版会把 w/h 写成像素，直接读会丢掉 "auto"/"50%"
	local specW = child._specW ~= nil and child._specW or child.w
	local specH = child._specH ~= nil and child._specH or child.h
	local w = layout.pixels(specW, availW)
	local h = layout.pixels(specH, availH)
	if (w == nil or h == nil) and child.measure then
		local measuredW, measuredH = child:measure(availW, availH)
		if w == nil then
			w = measuredW or 0
		end
		if h == nil then
			h = measuredH or 0
		end
	end
	return w or 0, h or 0
end

-- 只测量：返回容器按内容应有的尺寸，不修改任何位置
function layout.measureLinear(node, availW, availH)
	local pl, pt, pr, pb = layout.sides(node.padding)
	local w = layout.pixels(node._specW ~= nil and node._specW or node.w, availW)
	local h = layout.pixels(node._specH ~= nil and node._specH or node.h, availH)

	local children = node.children or {}
	local column = (node.direction or "column") ~= "row"
	local gap = node.gap or 0

	local childAvailW = w and (w - pl - pr) or (availW and (availW - pl - pr))
	local childAvailH = h and (h - pt - pb) or (availH and (availH - pt - pb))

	local sumW, sumH, count = 0, 0, 0

	for i = 1, #children do
		local child = children[i]
		if child.visible ~= false and child.position ~= "absolute" then
			local cw, ch = layout.childMeasure(child, childAvailW, childAvailH)
			local ml, mt, mr, mb = layout.sides(child.margin)
			local outerW, outerH = cw + ml + mr, ch + mt + mb

			if column then
				if outerW > sumW then
					sumW = outerW
				end
				sumH = sumH + outerH
			else
				sumW = sumW + outerW
				if outerH > sumH then
					sumH = outerH
				end
			end
			count = count + 1
		end
	end

	if count > 1 then
		if column then
			sumH = sumH + gap * (count - 1)
		else
			sumW = sumW + gap * (count - 1)
		end
	end

	return w or (sumW + pl + pr), h or (sumH + pt + pb)
end

-- 完整排版：确定容器自身尺寸，再把子项摆到 x/y/w/h 上（容器子项会递归）
function layout.arrangeLinear(node, availW, availH)
	-- auto 尺寸排版后会变成像素，重排时先还原成原始规格
	if node._specW == nil then
		node._specW, node._specH = node.w, node.h
	end
	node.w, node.h = node._specW, node._specH

	local pl, pt, pr, pb = layout.sides(node.padding)
	local gap = node.gap or 0
	local column = (node.direction or "column") ~= "row"
	local align = node.align or "start"
	local justify = node.justify or "start"

	local children = node.children or {}

	local fixedW = layout.pixels(node._specW, availW)
	local fixedH = layout.pixels(node._specH, availH)
	local contentW = fixedW and (fixedW - pl - pr) or (availW and (availW - pl - pr))
	local contentH = fixedH and (fixedH - pt - pb) or (availH and (availH - pt - pb))

	-- 1. 解析每个子项的尺寸
	local items = {}

	for i = 1, #children do
		local child = children[i]
		if child.visible ~= false and child.position ~= "absolute" then
			if child._specW == nil then
				child._specW, child._specH = child.w, child.h
			end
			child.w, child.h = child._specW, child._specH

			local ml, mt, mr, mb = layout.sides(child.margin)
			local cw = layout.pixels(child._specW, contentW)
			local ch = layout.pixels(child._specH, contentH)
			local autoW, autoH = cw == nil, ch == nil

			if autoW or autoH then
				local measuredW, measuredH = 0, 0
				if child.measure then
					measuredW, measuredH = child:measure(contentW, contentH)
				end
				if autoW then
					cw = measuredW or 0
				end
				if autoH then
					ch = measuredH or 0
				end
			end

			-- 交叉轴 stretch：auto 的子项撑满内容区
			if align == "stretch" and contentW then
				if column and autoW then
					cw = contentW - ml - mr
				elseif not column and autoH then
					ch = contentH - mt - mb
				end
			end

			items[#items + 1] = {
				child = child,
				w = cw,
				h = ch,
				autoW = autoW,
				autoH = autoH,
				ml = ml,
				mt = mt,
				mr = mr,
				mb = mb,
			}
		end
	end

	local n = #items

	-- 2. 容器自身 auto 尺寸：由子项外框求和
	if not contentW or not contentH then
		local sumW, sumH = 0, 0
		for i = 1, n do
			local it = items[i]
			local outerW = it.w + it.ml + it.mr
			local outerH = it.h + it.mt + it.mb
			if column then
				if outerW > sumW then
					sumW = outerW
				end
				sumH = sumH + outerH
			else
				sumW = sumW + outerW
				if outerH > sumH then
					sumH = outerH
				end
			end
		end
		if n > 1 then
			if column then
				sumH = sumH + gap * (n - 1)
			else
				sumW = sumW + gap * (n - 1)
			end
		end
		contentW = contentW or sumW
		contentH = contentH or sumH
	end

	node.w = pixel.round(contentW + pl + pr)
	node.h = pixel.round(contentH + pt + pb)
	node._contentW, node._contentH = contentW, contentH

	-- 3. grow：主轴上剩余空间按权重分配
	local growTotal, outerMain = 0, 0
	for i = 1, n do
		local it = items[i]
		local mainSize = column and it.h or it.w
		local margins = column and (it.mt + it.mb) or (it.ml + it.mr)
		outerMain = outerMain + mainSize + margins
		if (it.child.grow or 0) > 0 then
			growTotal = growTotal + it.child.grow
		end
	end

	local gaps = n > 1 and gap * (n - 1) or 0
	local leftover = (column and contentH or contentW) - outerMain - gaps

	if leftover > 0 and growTotal > 0 then
		for i = 1, n do
			local it = items[i]
			local grow = it.child.grow or 0
			if grow > 0 then
				local add = leftover * grow / growTotal
				if column then
					it.h = it.h + add
				else
					it.w = it.w + add
				end
			end
		end
		leftover = 0
	end

	-- 4. 主轴上按 justify 处理剩余空间
	local cursor = 0
	local extraGap = 0
	if leftover > 0 then
		if justify == "center" then
			cursor = leftover / 2
		elseif justify == "end" then
			cursor = leftover
		elseif justify == "space-between" and n > 1 then
			extraGap = leftover / (n - 1)
		end
	end

	local function crossOffset(contentSize, outer)
		if align == "center" then
			return (contentSize - outer) / 2
		elseif align == "end" then
			return contentSize - outer
		end
		return 0
	end

	-- 5. 写入坐标；容器子项递归排版
	for i = 1, n do
		local it = items[i]
		local child = it.child

		-- 对齐到整数像素：文字、圆角、1px 边框才不会发虚
		child.w, child.h = pixel.round(it.w), pixel.round(it.h)

		if column then
			child.x = pixel.round(node.x + pl + it.ml + crossOffset(contentW, it.w + it.ml + it.mr))
			child.y = pixel.round(node.y + pt + cursor + it.mt)
			cursor = cursor + it.h + it.mt + it.mb + gap + extraGap
		else
			child.y = pixel.round(node.y + pt + it.mt + crossOffset(contentH, it.h + it.mt + it.mb))
			child.x = pixel.round(node.x + pl + cursor + it.ml)
			cursor = cursor + it.w + it.ml + it.mr + gap + extraGap
		end

		if child.children then
			-- 记住父容器给的可视区：容器稍后自己 :draw() 时要用同样的可用宽高重排，
			-- 否则百分比尺寸会因为拿不到基数而退回 auto
			child._availW, child._availH = child.w, child.h
			layout.arrange(child, child.w, child.h)
		end
	end

	return node.w, node.h
end

-- ---------- 绝对定位、flex-wrap、grid ----------

local function ensureSpec(child)
	if child._specW == nil then
		child._specW, child._specH = child.w, child.h
	end
	child.w, child.h = child._specW, child._specH
end

local function marginOf(child)
	return layout.sides(child.margin)
end

-- 只测量一个流式子项（不处理 align/stretch）
local function flowItem(child, contentW, contentH)
	ensureSpec(child)
	local ml, mt, mr, mb = marginOf(child)
	local cw = layout.pixels(child._specW, contentW)
	local ch = layout.pixels(child._specH, contentH)
	local autoW, autoH = cw == nil, ch == nil
	if autoW or autoH then
		local mw, mh = 0, 0
		if child.measure then
			mw, mh = child:measure(contentW, contentH)
		end
		if autoW then
			cw = mw or 0
		end
		if autoH then
			ch = mh or 0
		end
	end
	return {
		child = child,
		w = cw,
		h = ch,
		autoW = autoW,
		autoH = autoH,
		ml = ml,
		mt = mt,
		mr = mr,
		mb = mb,
	}
end

local function collectFlow(node, contentW, contentH)
	local items = {}
	local children = node.children or {}
	for i = 1, #children do
		local child = children[i]
		if child.visible ~= false and child.position ~= "absolute" then
			items[#items + 1] = flowItem(child, contentW, contentH)
		end
	end
	return items
end

-- 把流式子项按主轴可用空间分组；mainAvail 为 nil 时全部放一行
local function buildLines(items, mainAvail, gap, column)
	local lines = {}
	local line

	local function newLine()
		line = { items = {}, main = 0, cross = 0 }
		lines[#lines + 1] = line
	end

	for i = 1, #items do
		local it = items[i]
		local outerMain = column and (it.h + it.mt + it.mb) or (it.w + it.ml + it.mr)
		local outerCross = column and (it.w + it.ml + it.mr) or (it.h + it.mt + it.mb)
		if not line then
			newLine()
		end
		local candidate = line.main + (line.items[1] and gap or 0) + outerMain
		if mainAvail and line.items[1] and candidate > mainAvail then
			newLine()
			candidate = outerMain
		end
		line.items[#line.items + 1] = it
		line.main = candidate
		if outerCross > line.cross then
			line.cross = outerCross
		end
	end

	return lines
end

local function measureWrap(node, availW, availH)
	local pl, pt, pr, pb = layout.sides(node.padding)
	local gap = node.gap or 0
	local column = (node.direction or "column") ~= "row"
	local fixedW = layout.pixels(node._specW ~= nil and node._specW or node.w, availW)
	local fixedH = layout.pixels(node._specH ~= nil and node._specH or node.h, availH)
	local contentW = fixedW and (fixedW - pl - pr) or (availW and (availW - pl - pr))
	local contentH = fixedH and (fixedH - pt - pb) or (availH and (availH - pt - pb))
	local items = collectFlow(node, contentW, contentH)
	local mainAvail = column and contentH or contentW
	local lines = buildLines(items, mainAvail, gap, column)

	local autoMain, autoCross = 0, 0
	for i = 1, #lines do
		local line = lines[i]
		if line.main > autoMain then
			autoMain = line.main
		end
		autoCross = autoCross + line.cross
	end
	if #lines > 1 then
		autoCross = autoCross + gap * (#lines - 1)
	end

	local contentMain, contentCross
	if column then
		contentMain = fixedH or autoMain
		contentCross = fixedW or autoCross
	else
		contentMain = fixedW or autoMain
		contentCross = fixedH or autoCross
	end
	local w = column and (contentCross + pl + pr) or (contentMain + pl + pr)
	local h = column and (contentMain + pt + pb) or (contentCross + pt + pb)
	return pixel.round(w), pixel.round(h)
end

local function arrangeWrap(node, availW, availH)
	if node._specW == nil then
		node._specW, node._specH = node.w, node.h
	end
	node.w, node.h = node._specW, node._specH

	local pl, pt, pr, pb = layout.sides(node.padding)
	local gap = node.gap or 0
	local column = (node.direction or "column") ~= "row"
	local align = node.align or "start"
	local justify = node.justify or "start"
	local alignContent = node.alignContent or "start"
	local fixedW = layout.pixels(node._specW, availW)
	local fixedH = layout.pixels(node._specH, availH)
	local contentW = fixedW and (fixedW - pl - pr) or (availW and (availW - pl - pr))
	local contentH = fixedH and (fixedH - pt - pb) or (availH and (availH - pt - pb))
	local items = collectFlow(node, contentW, contentH)
	local mainAvail = column and contentH or contentW
	local lines = buildLines(items, mainAvail, gap, column)

	local fixedMain, fixedCross
	if column then
		fixedMain, fixedCross = fixedH, fixedW
	else
		fixedMain, fixedCross = fixedW, fixedH
	end
	local autoMain = 0
	local autoCross = 0
	for i = 1, #lines do
		autoMain = math.max(autoMain, lines[i].main)
		autoCross = autoCross + lines[i].cross
	end
	if #lines > 1 then
		autoCross = autoCross + gap * (#lines - 1)
	end
	local contentMain = fixedMain or autoMain
	local contentCross = fixedCross or autoCross

	local w = column and (contentCross + pl + pr) or (contentMain + pl + pr)
	local h = column and (contentMain + pt + pb) or (contentCross + pt + pb)
	node.w, node.h = pixel.round(w), pixel.round(h)
	node._contentW, node._contentH = column and contentCross or contentMain, column and contentMain or contentCross

	-- 跨行的 alignContent
	local totalCross = 0
	for i = 1, #lines do
		totalCross = totalCross + lines[i].cross
	end
	if #lines > 1 then
		totalCross = totalCross + gap * (#lines - 1)
	end
	local crossExtra = contentCross - totalCross
	local crossCursor, crossGap, crossStretch = 0, 0, 0
	if crossExtra > 0 then
		if alignContent == "center" then
			crossCursor = crossExtra / 2
		elseif alignContent == "end" then
			crossCursor = crossExtra
		elseif alignContent == "space-between" and #lines > 1 then
			crossGap = crossExtra / (#lines - 1)
		elseif alignContent == "stretch" then
			crossStretch = crossExtra / #lines
		end
	end

	local function crossOffset(limit, outer)
		if align == "center" then
			return (limit - outer) / 2
		elseif align == "end" then
			return limit - outer
		end
		return 0
	end

	for li = 1, #lines do
		local line = lines[li]
		line.cross = line.cross + crossStretch
		local lineCross = line.cross
		local lineCrossStart = crossCursor
		crossCursor = crossCursor + lineCross + gap + crossGap

		-- 这一行的 grow
		local outerMain, growTotal = 0, 0
		for i = 1, #line.items do
			local it = line.items[i]
			local main = column and it.h or it.w
			local margins = column and (it.mt + it.mb) or (it.ml + it.mr)
			outerMain = outerMain + main + margins
			if (it.child.grow or 0) > 0 then
				growTotal = growTotal + it.child.grow
			end
		end
		local gaps = #line.items > 1 and gap * (#line.items - 1) or 0
		local mainLimit = fixedMain or line.main
		local leftover = mainLimit - outerMain - gaps
		if leftover > 0 and growTotal > 0 then
			for i = 1, #line.items do
				local it = line.items[i]
				local grow = it.child.grow or 0
				if grow > 0 then
					local add = leftover * grow / growTotal
					if column then
						it.h = it.h + add
					else
						it.w = it.w + add
					end
				end
			end
			line.main = mainLimit
			leftover = 0
		end

		local mainExtra = mainLimit - line.main
		local cursor, lineGap = 0, 0
		if mainExtra > 0 then
			if justify == "center" then
				cursor = mainExtra / 2
			elseif justify == "end" then
				cursor = mainExtra
			elseif justify == "space-between" and #line.items > 1 then
				lineGap = mainExtra / (#line.items - 1)
			end
		end

		for i = 1, #line.items do
			local it = line.items[i]
			local child = it.child
			local cw, ch = it.w, it.h
			if column then
				if it.autoW and align == "stretch" then
					cw = lineCross - it.ml - it.mr
				end
			else
				if it.autoH and align == "stretch" then
					ch = lineCross - it.mt - it.mb
				end
			end
			child.w, child.h = pixel.round(cw), pixel.round(ch)
			if column then
				child.x = pixel.round(node.x + pl + lineCrossStart + crossOffset(lineCross, cw + it.ml + it.mr) + it.ml)
				child.y = pixel.round(node.y + pt + cursor + it.mt)
				cursor = cursor + it.h + it.mt + it.mb + gap + lineGap
			else
				child.y = pixel.round(node.y + pt + lineCrossStart + crossOffset(lineCross, ch + it.mt + it.mb) + it.mt)
				child.x = pixel.round(node.x + pl + cursor + it.ml)
				cursor = cursor + it.w + it.ml + it.mr + gap + lineGap
			end
			if child.children then
				child._availW, child._availH = child.w, child.h
				layout.arrange(child, child.w, child.h)
			end
		end
	end

	return node.w, node.h
end

-- 绝对定位：x/y 由 left/top/right/bottom 决定，不参与父容器流式尺寸计算
local function placeAbsolute(node, contentW, contentH)
	if not contentW or not contentH then
		return
	end
	local pl, pt = layout.sides(node.padding)
	local children = node.children or {}
	for i = 1, #children do
		local child = children[i]
		if child.visible ~= false and child.position == "absolute" then
			ensureSpec(child)
			if child._absX == nil then
				child._absX, child._absY = child.x, child.y
			end
			local left = layout.pixels(child.left, contentW)
			local right = layout.pixels(child.right, contentW)
			local top = layout.pixels(child.top, contentH)
			local bottom = layout.pixels(child.bottom, contentH)
			if left == nil and right == nil then
				left = layout.pixels(child._absX, contentW) or 0
			end
			if top == nil and bottom == nil then
				top = layout.pixels(child._absY, contentH) or 0
			end
			local w = layout.pixels(child._specW, contentW)
			local h = layout.pixels(child._specH, contentH)
			if w == nil and left ~= nil and right ~= nil then
				w = math.max(0, contentW - left - right)
			end
			if h == nil and top ~= nil and bottom ~= nil then
				h = math.max(0, contentH - top - bottom)
			end
			if w == nil or h == nil then
				local mw, mh = 0, 0
				if child.measure then
					mw, mh = child:measure(contentW, contentH)
				end
				w = w or mw or 0
				h = h or mh or 0
			end
			local x = left
			if x == nil and right ~= nil then
				x = contentW - w - right
			end
			local y = top
			if y == nil and bottom ~= nil then
				y = contentH - h - bottom
			end
			child.w, child.h = pixel.round(w), pixel.round(h)
			child.x = pixel.round(node.x + pl + (x or 0))
			child.y = pixel.round(node.y + pt + (y or 0))
			if child.children then
				child._availW, child._availH = child.w, child.h
				layout.arrange(child, child.w, child.h)
			end
		end
	end
end

-- ---------- grid ----------

local function gridSettings(node)
	local g = node.grid
	if type(g) == "number" then
		g = { columns = g }
	end
	if type(g) ~= "table" then
		g = {}
	end
	local columns = g.columns or node.columns or 2
	local gap = g.gap or node.gap or 0
	return {
		columns = columns,
		rows = g.rows or node.rows,
		columnGap = g.columnGap or g.gap or gap,
		rowGap = g.rowGap or g.gap or gap,
	}
end

local function columnSpecs(columns)
	if type(columns) == "number" then
		local specs = {}
		for i = 1, math.max(1, math.floor(columns)) do
			specs[i] = "1fr"
		end
		return specs
	elseif type(columns) == "table" then
		return columns
	end
	return { "1fr", "1fr" }
end

local function maxChildWidths(node, colCount)
	local maxes = {}
	local flow = 0
	local children = node.children or {}
	for i = 1, #children do
		local child = children[i]
		if child.visible ~= false and child.position ~= "absolute" then
			flow = flow + 1
			local col = (flow - 1) % colCount + 1
			local w = layout.childMeasure(child, nil, nil)
			if w and w > (maxes[col] or 0) then
				maxes[col] = w
			end
		end
	end
	return maxes
end

local function resolveColumns(settings, contentW, node)
	local specs = columnSpecs(settings.columns)
	local maxes = maxChildWidths(node, #specs)
	local widths, fixed, fr = {}, 0, 0
	local gap = settings.columnGap
	for i = 1, #specs do
		local spec = specs[i]
		if type(spec) == "number" then
			widths[i] = spec
			fixed = fixed + spec
		elseif type(spec) == "string" and spec:match("fr$") then
			widths[i] = nil
			fr = fr + (tonumber(spec:match("([%d%.]+)fr")) or 1)
		elseif spec == "auto" then
			widths[i] = maxes[i] or 0
			fixed = fixed + widths[i]
		else
			local px = layout.pixels(spec, contentW)
			widths[i] = px or maxes[i] or 0
			fixed = fixed + widths[i]
		end
	end
	local gaps = #specs > 1 and gap * (#specs - 1) or 0
	local available = (contentW or 0) - fixed - gaps
	if available < 0 then
		available = 0
	end
	for i = 1, #specs do
		if widths[i] == nil then
			local weight = tonumber(tostring(specs[i]):match("([%d%.]+)fr")) or 1
			if contentW then
				widths[i] = fr > 0 and available * weight / fr or 0
			else
				widths[i] = maxes[i] or 100
			end
		end
	end
	return widths, specs
end

local function gridItems(node, widths, settings, contentH)
	local items = {}
	local children = node.children or {}
	local colCount = #widths
	local flow = 0
	for i = 1, #children do
		local child = children[i]
		if child.visible ~= false and child.position ~= "absolute" then
			flow = flow + 1
			local col = (flow - 1) % colCount + 1
			local row = math.floor((flow - 1) / colCount) + 1
			ensureSpec(child)
			local ml, mt, mr, mb = marginOf(child)
			local cellW = widths[col]
			local w = layout.pixels(child._specW, cellW)
			local h = layout.pixels(child._specH, contentH)
			local autoW, autoH = w == nil, h == nil
			if autoW or autoH then
				local mw, mh = 0, 0
				if child.measure then
					mw, mh = child:measure(cellW, nil)
				end
				w = w or mw or 0
				h = h or mh or 0
			end
			items[#items + 1] = {
				child = child,
				row = row,
				col = col,
				w = w,
				h = h,
				autoW = autoW,
				autoH = autoH,
				ml = ml,
				mt = mt,
				mr = mr,
				mb = mb,
			}
		end
	end
	return items
end

local function gridRows(items, settings, contentH)
	local rowCount = 0
	for i = 1, #items do
		rowCount = math.max(rowCount, items[i].row)
	end
	local rows = {}
	for r = 1, rowCount do
		rows[r] = 0
	end
	for i = 1, #items do
		local it = items[i]
		local outerH = it.h + it.mt + it.mb
		if outerH > rows[it.row] then
			rows[it.row] = outerH
		end
	end
	-- 可选的固定行高表
	if type(settings.rows) == "table" then
		for r = 1, math.min(#settings.rows, rowCount) do
			local spec = settings.rows[r]
			if type(spec) == "number" then
				rows[r] = spec
			elseif type(spec) == "string" and spec ~= "auto" then
				local px = layout.pixels(spec, contentH)
				if px then
					rows[r] = px
				end
			end
		end
	end
	return rows
end

local function measureGrid(node, availW, availH)
	local pl, pt, pr, pb = layout.sides(node.padding)
	local settings = gridSettings(node)
	local fixedW = layout.pixels(node._specW ~= nil and node._specW or node.w, availW)
	local fixedH = layout.pixels(node._specH ~= nil and node._specH or node.h, availH)
	local contentW = fixedW and (fixedW - pl - pr) or (availW and (availW - pl - pr))
	local contentH = fixedH and (fixedH - pt - pb) or (availH and (availH - pt - pb))
	local widths = resolveColumns(settings, contentW, node)
	local items = gridItems(node, widths, settings, contentH)
	local rows = gridRows(items, settings, contentH)
	local w = 0
	for i = 1, #widths do
		w = w + widths[i]
	end
	if #widths > 1 then
		w = w + settings.columnGap * (#widths - 1)
	end
	local h = 0
	for i = 1, #rows do
		h = h + rows[i]
	end
	if #rows > 1 then
		h = h + settings.rowGap * (#rows - 1)
	end
	return pixel.round((fixedW or (w + pl + pr))), pixel.round((fixedH or (h + pt + pb)))
end

local function arrangeGrid(node, availW, availH)
	if node._specW == nil then
		node._specW, node._specH = node.w, node.h
	end
	node.w, node.h = node._specW, node._specH
	local pl, pt, pr, pb = layout.sides(node.padding)
	local settings = gridSettings(node)
	local fixedW = layout.pixels(node._specW, availW)
	local fixedH = layout.pixels(node._specH, availH)
	local contentW = fixedW and (fixedW - pl - pr) or (availW and (availW - pl - pr))
	local contentH = fixedH and (fixedH - pt - pb) or (availH and (availH - pt - pb))
	local widths = resolveColumns(settings, contentW, node)
	local items = gridItems(node, widths, settings, contentH)
	local rows = gridRows(items, settings, contentH)

	local gridW, gridH = 0, 0
	for i = 1, #widths do
		gridW = gridW + widths[i]
	end
	if #widths > 1 then
		gridW = gridW + settings.columnGap * (#widths - 1)
	end
	for i = 1, #rows do
		gridH = gridH + rows[i]
	end
	if #rows > 1 then
		gridH = gridH + settings.rowGap * (#rows - 1)
	end
	node.w = pixel.round((fixedW or (gridW + pl + pr)))
	node.h = pixel.round((fixedH or (gridH + pt + pb)))
	node._contentW, node._contentH = contentW or gridW, contentH or gridH

	local align = node.align or "start"
	local justify = node.justify or "start"
	local function axisOffset(limit, size, mode)
		local extra = limit - size
		if extra <= 0 then
			return 0
		end
		if mode == "center" then
			return extra / 2
		elseif mode == "end" then
			return extra
		end
		return 0
	end

	local rowY = 0
	for r = 1, #rows do
		local colX = 0
		for c = 1, #widths do
			local cellW, cellH = widths[c], rows[r]
			for i = 1, #items do
				local it = items[i]
				if it.row == r and it.col == c then
					local child = it.child
					local cw, ch = it.w, it.h
					if it.autoW and (justify == "stretch" or justify == "start") then
						cw = math.max(0, cellW - it.ml - it.mr)
					end
					if it.autoH and align == "stretch" then
						ch = math.max(0, cellH - it.mt - it.mb)
					end
					local ox = axisOffset(cellW, cw + it.ml + it.mr, justify)
					local oy = axisOffset(cellH, ch + it.mt + it.mb, align)
					child.w, child.h = pixel.round(cw), pixel.round(ch)
					child.x = pixel.round(node.x + pl + colX + ox + it.ml)
					child.y = pixel.round(node.y + pt + rowY + oy + it.mt)
					if child.children then
						child._availW, child._availH = child.w, child.h
						layout.arrange(child, child.w, child.h)
					end
				end
			end
			colX = colX + cellW + settings.columnGap
		end
		rowY = rowY + rows[r] + settings.rowGap
	end

	return node.w, node.h
end

function layout.measure(node, availW, availH)
	if node.display == "grid" or node.grid ~= nil then
		return measureGrid(node, availW, availH)
	elseif node.wrap or node.flexWrap == "wrap" then
		return measureWrap(node, availW, availH)
	end
	return layout.measureLinear(node, availW, availH)
end

function layout.arrange(node, availW, availH)
	local w, h
	if node.display == "grid" or node.grid ~= nil then
		w, h = arrangeGrid(node, availW, availH)
	elseif node.wrap or node.flexWrap == "wrap" then
		w, h = arrangeWrap(node, availW, availH)
	else
		w, h = layout.arrangeLinear(node, availW, availH)
	end
	placeAbsolute(node, node._contentW, node._contentH)
	return w, h
end

return layout
