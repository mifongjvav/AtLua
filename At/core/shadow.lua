shadow = {}

function shadow.shadow(x, y, w, h, res, color, radius, layers, offsetX, offsetY)
	layers = layers or 20
	offsetX = offsetX or 0
	offsetY = offsetY or 0

	-- 每层都很淡，靠"层数"做柔和度。必须按层数归一化：
	-- 否则 20 层各 7.5% 叠加后接近 80% 不透明，看起来就是一圈黑底。
	local layerCount = layers + 1
	local layerAlpha = color[4] * 2 / layerCount

	for i = layers, 0, -1 do
		local progress = i / layers
		local alpha = layerAlpha * (1 - progress)

		local spread_pixels = progress * radius
		local scale_w = 1 + (spread_pixels * 2) / w
		local scale_h = 1 + (spread_pixels * 2) / h

		local base_offset_x = (scale_w - 1) * w / 2
		local base_offset_y = (scale_h - 1) * h / 2

		local layer_offset_x = offsetX * (1 - progress * 0.5)
		local layer_offset_y = offsetY * (1 - progress * 0.5)

		love.graphics.setColor(color[1], color[2], color[3], alpha)
		love.graphics.rectangle(
			"fill",
			x - base_offset_x + layer_offset_x,
			y - base_offset_y + layer_offset_y,
			w * scale_w,
			h * scale_h,
			res
		)
	end
end

return shadow
