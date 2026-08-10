return function(_queryPoint: Vector2, gui: GuiObject): (number, number, number, number)
	local backgroundColor = gui.BackgroundColor3
	local r, g, b, a = backgroundColor.R, backgroundColor.G, backgroundColor.B, 1 - gui.BackgroundTransparency

	local gradient = gui:FindFirstChildWhichIsA("UIGradient")
	if gradient then
		-- TODO: Figure out where in the gradient we are
		local colorKeypoint = gradient.Color.Keypoints[1]
		local alphaKeypoint = gradient.Transparency.Keypoints[1]

		r *= colorKeypoint.Value.R
		g *= colorKeypoint.Value.G
		b *= colorKeypoint.Value.B
		a *= 1 - alphaKeypoint.Value
	end

	return r, g, b, a
end
