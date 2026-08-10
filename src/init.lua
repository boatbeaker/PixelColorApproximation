local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui", math.huge)

local GetGuiColor = require(script.GetGuiColor)
local GetWorldColor = require(script.GetWorldColor)

local PixelColorApproximation = {}

function PixelColorApproximation:GetColor(queryPoint: Vector2, topLayer: GuiObject?): { number }
	local guisAtPosition = PlayerGui:GetGuiObjectsAtPosition(queryPoint.X, queryPoint.Y)

	-- Blend front to back: each layer contributes through the combined
	-- transmittance of the layers above it
	local r, g, b = 0, 0, 0
	local transmittance = 1
	local topLayerIndex = if topLayer then table.find(guisAtPosition, topLayer) else nil

	for i = (topLayerIndex or 0) + 1, #guisAtPosition do
		local gui = guisAtPosition[i]

		local layerR, layerG, layerB, layerA = GetGuiColor(queryPoint, gui)
		if layerA <= 0 then
			-- Skip invisible objects
			continue
		end

		local weight = transmittance * layerA
		r += weight * layerR
		g += weight * layerG
		b += weight * layerB
		transmittance *= 1 - layerA

		-- Everything beneath an opaque layer is covered
		if transmittance <= 0 then
			break
		end
	end

	-- If the UI is not opaque, we'll roughly get world color underneath
	if transmittance > 0 then
		local worldR, worldG, worldB, worldA = GetWorldColor(queryPoint)
		local weight = transmittance * worldA
		r += weight * worldR
		g += weight * worldG
		b += weight * worldB
	end

	return { r, g, b, 1 }
end

return PixelColorApproximation
