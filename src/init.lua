local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui", math.huge)

local GetGuiSampler = require(script.GetGuiSampler)
local GetWorldColor = require(script.GetWorldColor)

local PixelColorApproximation = {}

-- Hot-path form: no allocations per call. footprint is diameter in screen px; layers average over it to prevent aliasing
function PixelColorApproximation:GetColorXY(
	x: number,
	y: number,
	topLayer: GuiObject?,
	footprint: number?
): (number, number, number, number)
	local guisAtPosition = PlayerGui:GetGuiObjectsAtPosition(x, y)

	-- Blend front to back through transmittance
	local r, g, b = 0, 0, 0
	local transmittance = 1
	local topLayerIndex = if topLayer then table.find(guisAtPosition, topLayer) else nil

	for i = (topLayerIndex or 0) + 1, #guisAtPosition do
		local sampler = GetGuiSampler(guisAtPosition[i])

		local guiR, guiG, guiB, guiA = sampler:sample(x, y, footprint)
		if guiA <= 0 then
			continue
		end

		local weight = transmittance * guiA
		r += weight * guiR
		g += weight * guiG
		b += weight * guiB
		transmittance *= 1 - guiA

		if transmittance <= 0 then
			break
		end
	end

	-- Sample world color if UI is not opaque
	if transmittance > 0 then
		local worldR, worldG, worldB, worldA = GetWorldColor(x, y, footprint)
		local weight = transmittance * worldA
		r += weight * worldR
		g += weight * worldG
		b += weight * worldB
	end

	return r, g, b, 1
end

function PixelColorApproximation:GetColor(queryPoint: Vector2, topLayer: GuiObject?, footprint: number?): { number }
	local r, g, b, a = self:GetColorXY(queryPoint.X, queryPoint.Y, topLayer, footprint)
	return { r, g, b, a }
end

return PixelColorApproximation
