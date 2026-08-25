-- Solid-color layer: background color modulated by first gradient keypoint

local function sample(record)
	return record.r, record.g, record.b, record.a
end

local function describe(gui)
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

	return {
		sample = sample,
		r = r,
		g = g,
		b = b,
		a = a,
	}
end

return describe
