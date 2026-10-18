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
--
-- 不支持：flex-wrap、grid、position absolute、z-index、aspect-ratio。

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
function layout.measure(node, availW, availH)
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
		if child.visible ~= false then
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
function layout.arrange(node, availW, availH)
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
		if child.visible ~= false then
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

return layout
