local Utils = require(script.Parent.Parent.Parent.Utils)
local defaultHandler = require(script.Parent.default)

return function(queryPoint: Vector2, gui: TextBox | TextLabel | TextButton): (number, number, number, number)
	local r, g, b, a = defaultHandler(queryPoint, gui)

	local textAlpha = 1 - gui.TextTransparency
	if textAlpha == 0 or string.find(gui.Text, "%S") == nil then
		return r, g, b, a
	end

	local queryInObjectSpace =
		Utils.worldToLocal(queryPoint, gui.AbsolutePosition, gui.AbsoluteSize, math.rad(gui.Rotation))
	local queryInObjectPixels = queryInObjectSpace * gui.AbsoluteSize

	-- TODO: Estimate the spacing between words not just lines
	-- TODO: Don't assume all lines are the max textBounds.X
	-- TODO: Support UIPadding altering alignment

	local textBounds = gui.TextBounds

	-- Return background color if we're outside the text bounds with respect to alignment
	local textXAlignment = gui.TextXAlignment
	if textXAlignment == Enum.TextXAlignment.Left then
		if queryInObjectPixels.X > textBounds.X then
			return r, g, b, a
		end
	elseif textXAlignment == Enum.TextXAlignment.Right then
		if queryInObjectPixels.X < gui.AbsoluteSize.X - textBounds.X then
			return r, g, b, a
		end
	elseif textXAlignment == Enum.TextXAlignment.Center then
		local mid = gui.AbsoluteSize.X / 2
		local textOffset = textBounds.X / 2
		if queryInObjectPixels.X < mid - textOffset then
			return r, g, b, a
		elseif queryInObjectPixels.X > mid + textOffset then
			return r, g, b, a
		end
	end
	local textYAlignment = gui.TextYAlignment
	if textYAlignment == Enum.TextYAlignment.Top then
		if queryInObjectPixels.Y > textBounds.Y then
			return r, g, b, a
		end
	elseif textYAlignment == Enum.TextYAlignment.Bottom then
		if queryInObjectPixels.Y < gui.AbsoluteSize.Y - textBounds.Y then
			return r, g, b, a
		end
	elseif textYAlignment == Enum.TextYAlignment.Center then
		local mid = gui.AbsoluteSize.Y / 2
		local textOffset = textBounds.Y / 2
		if queryInObjectPixels.Y < mid - textOffset then
			return r, g, b, a
		elseif queryInObjectPixels.Y > mid + textOffset then
			return r, g, b, a
		end
	end

	-- Return background color if we're between the lines of text

	local textHeight = gui.TextSize
	local lineCount = textBounds.Y // textHeight
	local lineSpacing = (textBounds.Y - (textHeight * lineCount)) / (lineCount - 1)
	if textYAlignment == Enum.TextYAlignment.Top then
		if (queryInObjectPixels.Y % (textHeight + lineSpacing)) > textHeight then
			return r, g, b, a
		end
	elseif textYAlignment == Enum.TextYAlignment.Bottom then
		local padding = gui.AbsoluteSize.Y - textBounds.Y
		if ((queryInObjectPixels.Y + padding) % (textHeight + lineSpacing)) > textHeight then
			return r, g, b, a
		end
	elseif textYAlignment == Enum.TextYAlignment.Center then
		local padding = (gui.AbsoluteSize.Y - textBounds.Y) / 2
		if ((queryInObjectPixels.Y + padding) % (textHeight + lineSpacing)) > textHeight then
			return r, g, b, a
		end
	end

	-- Return the text color since we're probably inside the text area
	-- However, text is not a solid so we just force it to be partially transparent
	local textColor = gui.TextColor3

	if a > 0 then
		-- We can blend with our background
		return (0.6 * textColor.R) + (0.4 * r),
			(0.6 * textColor.G) + (0.4 * g),
			(0.6 * textColor.B) + (0.4 * b),
			textAlpha
	else
		-- We don't have a background, so we can just be partially transparent
		return textColor.R, textColor.G, textColor.B, textAlpha * 0.6
	end
end
