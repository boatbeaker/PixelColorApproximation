local Terrain = workspace.Terrain
local Lighting = game:GetService("Lighting")

local Utils = require(script.Parent.Utils)

local currentSkybox = Lighting:FindFirstChildWhichIsA("Sky")
Lighting.ChildAdded:Connect(function(child)
	if child:IsA("Sky") then
		currentSkybox = child
	end
end)
Lighting.ChildRemoved:Connect(function(child)
	if child == currentSkybox then
		currentSkybox = Lighting:FindFirstChildWhichIsA("Sky")
	end
end)

local nightColor, dayColor = Color3.fromRGB(2, 7, 30), Color3.fromRGB(89, 178, 210)
local function estimateDefaultSky(origin: Vector3): (number, number, number, number)
	-- Estimate default sky color based on time of day
	local clockTime = Lighting.ClockTime
	local distFromNoon = math.abs(12 - clockTime) / 12
	local noise = math.noise(origin.X * 70, origin.Y * 70, origin.Z * 70) / 10
	local color = dayColor:Lerp(nightColor, distFromNoon + noise)

	return color.R, color.G, color.B, 1
end

local function getSkyboxColor(origin: Vector3, direction: Vector3, footprint: number): (number, number, number, number)
	if not currentSkybox then
		return estimateDefaultSky(origin)
	end

	local skyboxFace, u, v = Utils.getSkyboxFaceAndCoords(direction.Unit)
	local skyboxTexture = currentSkybox[skyboxFace]
	local skyboxImage = Utils.getImage(skyboxTexture)
	if not skyboxImage then
		return estimateDefaultSky(origin)
	end

	-- Convert screen px to texels: face height = viewport height on screen
	local footprintTexels = footprint * skyboxImage.height / workspace.CurrentCamera.ViewportSize.Y
	return Utils.readPixelFiltered(skyboxImage, u, v, footprintTexels)
end

-- Reused across queries to avoid allocation; filter list rebuilds only when transparent hits occur
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = false

local ignoreList: { Instance } = {}

local function raycastUntilColor(
	origin: Vector3,
	direction: Vector3,
	length: number,
	footprint: number
): (number, number, number, number)
	if #ignoreList > 0 then
		table.clear(ignoreList)
		raycastParams.FilterDescendantsInstances = ignoreList
	end

	while true do
		local raycastResult = workspace:Raycast(origin, direction * length, raycastParams)

		if not raycastResult or not raycastResult.Instance then
			return getSkyboxColor(origin, direction, footprint)
		end

		-- Casting through semi-transparent objects is too slow; use the first opaque hit

		local hit = raycastResult.Instance
		local fogBlend = if raycastResult.Distance >= Lighting.FogStart
			then (raycastResult.Distance - Lighting.FogStart) / (Lighting.FogEnd - Lighting.FogStart) * 0.9
			else 0

		if hit == Terrain then
			if raycastResult.Material == Enum.Material.Water then
				local color = Terrain.WaterColor:Lerp(Lighting.FogColor, fogBlend)
				return color.R, color.G, color.B, 1 - Terrain.WaterTransparency
			else
				local color = Terrain:GetMaterialColor(raycastResult.Material):Lerp(Lighting.FogColor, fogBlend)
				return color.R, color.G, color.B, 1
			end
		end

		if (1 - hit.Transparency) * (1 - hit.LocalTransparencyModifier) <= 0.05 then
			-- Pass through it
			table.insert(ignoreList, hit)
			raycastParams.FilterDescendantsInstances = ignoreList
			origin = raycastResult.Position
			length -= raycastResult.Distance
		else
			-- Textured/decaled items use base color only; prioritizes speed over accuracy
			local color = hit.Color:Lerp(Lighting.FogColor, fogBlend)
			return color.R, color.G, color.B, 1 - hit.Transparency
		end
	end
end

return function(x: number, y: number, footprint: number?): (number, number, number, number)
	local ray = workspace.CurrentCamera:ScreenPointToRay(x, y, 0)
	return raycastUntilColor(ray.Origin, ray.Direction, 500, footprint or 1)
end
