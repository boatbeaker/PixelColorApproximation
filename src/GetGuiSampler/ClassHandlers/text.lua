-- Text layer: describe() snapshots transform, bounds, alignment, metrics; sample() is pure math

local describeDefault = require(script.Parent.default)

local function sample(record, x, y)
	local r, g, b, a = record.r, record.g, record.b, record.a
	if not record.hasText then
		return r, g, b, a
	end

	-- Transform to object pixels with cached rotation
	local translatedX = x - record.posX
	local translatedY = y - record.posY
	local pixelsX = record.cos * translatedX - record.sin * translatedY
	local pixelsY = record.sin * translatedX + record.cos * translatedY

	-- TODO: Estimate the spacing between words not just lines
	-- TODO: Don't assume all lines are the max textBounds.X
	-- TODO: Support UIPadding altering alignment

	local sizeX, sizeY = record.sizeX, record.sizeY
	local textBoundsX, textBoundsY = record.textBoundsX, record.textBoundsY

	local textXAlignment = record.textXAlignment
	if textXAlignment == Enum.TextXAlignment.Left then
		if pixelsX > textBoundsX then
			return r, g, b, a
		end
	elseif textXAlignment == Enum.TextXAlignment.Right then
		if pixelsX < sizeX - textBoundsX then
			return r, g, b, a
		end
	elseif textXAlignment == Enum.TextXAlignment.Center then
		local mid = sizeX / 2
		local textOffset = textBoundsX / 2
		if pixelsX < mid - textOffset then
			return r, g, b, a
		elseif pixelsX > mid + textOffset then
			return r, g, b, a
		end
	end
	local textYAlignment = record.textYAlignment
	if textYAlignment == Enum.TextYAlignment.Top then
		if pixelsY > textBoundsY then
			return r, g, b, a
		end
	elseif textYAlignment == Enum.TextYAlignment.Bottom then
		if pixelsY < sizeY - textBoundsY then
			return r, g, b, a
		end
	elseif textYAlignment == Enum.TextYAlignment.Center then
		local mid = sizeY / 2
		local textOffset = textBoundsY / 2
		if pixelsY < mid - textOffset then
			return r, g, b, a
		elseif pixelsY > mid + textOffset then
			return r, g, b, a
		end
	end

	local lineStride = record.lineStride
	local textHeight = record.textHeight
	if textYAlignment == Enum.TextYAlignment.Top then
		if (pixelsY % lineStride) > textHeight then
			return r, g, b, a
		end
	elseif textYAlignment == Enum.TextYAlignment.Bottom then
		local padding = sizeY - textBoundsY
		if ((pixelsY + padding) % lineStride) > textHeight then
			return r, g, b, a
		end
	elseif textYAlignment == Enum.TextYAlignment.Center then
		local padding = (sizeY - textBoundsY) / 2
		if ((pixelsY + padding) % lineStride) > textHeight then
			return r, g, b, a
		end
	end

	-- Text pixel: blend with background if available, else use text with reduced alpha
	if a > 0 then
		return (0.6 * record.textR) + (0.4 * r),
			(0.6 * record.textG) + (0.4 * g),
			(0.6 * record.textB) + (0.4 * b),
			record.textAlpha
	else
		return record.textR, record.textG, record.textB, record.textAlpha * 0.6
	end
end

local function describe(gui)
	local record = describeDefault(gui)
	record.sample = sample

	local textAlpha = 1 - gui.TextTransparency
	record.hasText = textAlpha ~= 0 and string.find(gui.Text, "%S") ~= nil
	if not record.hasText then
		return record
	end

	local absolutePosition, absoluteSize = gui.AbsolutePosition, gui.AbsoluteSize
	local rotation = math.rad(gui.Rotation)
	record.posX, record.posY = absolutePosition.X, absolutePosition.Y
	record.cos, record.sin = math.cos(-rotation), math.sin(-rotation)
	record.sizeX, record.sizeY = absoluteSize.X, absoluteSize.Y

	local textBounds = gui.TextBounds
	record.textBoundsX, record.textBoundsY = textBounds.X, textBounds.Y
	record.textXAlignment = gui.TextXAlignment
	record.textYAlignment = gui.TextYAlignment

	local textHeight = gui.TextSize
	local lineCount = textBounds.Y // textHeight
	local lineSpacing = (textBounds.Y - (textHeight * lineCount)) / (lineCount - 1)
	record.textHeight = textHeight
	record.lineStride = textHeight + lineSpacing

	local textColor = gui.TextColor3
	record.textR, record.textG, record.textB = textColor.R, textColor.G, textColor.B
	record.textAlpha = textAlpha

	return record
end

return describe
