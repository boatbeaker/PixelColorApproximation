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
	-- No skybox, just roughly estimate the default blue sky
	local clockTime = Lighting.ClockTime
	local distFromNoon = math.abs(12 - clockTime) / 12
	local noise = math.noise(origin.X * 70, origin.Y * 70, origin.Z * 70) / 10
	local color = dayColor:Lerp(nightColor, distFromNoon + noise)

	return color.R, color.G, color.B, 1
end

local function getSkyboxColor(origin: Vector3, direction: Vector3): (number, number, number, number)
	if not currentSkybox then
		return estimateDefaultSky(origin)
	end

	local skyboxFace, u, v = Utils.getSkyboxFaceAndCoords(direction.Unit)
	local skyboxTexture = currentSkybox[skyboxFace]
	local skyboxImage = Utils.getImage(skyboxTexture)
	if not skyboxImage then
		return estimateDefaultSky(origin)
	end

	local imageWidth, imageHeight = skyboxImage.width, skyboxImage.height
	return Utils.readPixel(
		skyboxImage,
		math.clamp(math.floor(u * imageWidth), 0, imageWidth - 1),
		math.clamp(math.floor(v * imageHeight), 0, imageHeight - 1)
	)
end

-- Shared across queries so the common no-passthrough ray allocates nothing;
-- the filter list only rebuilds when a query passes through transparent parts
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = false

local ignoreList: { Instance } = {}

local function raycastUntilColor(origin: Vector3, direction: Vector3, length: number): (number, number, number, number)
	if #ignoreList > 0 then
		table.clear(ignoreList)
		raycastParams.FilterDescendantsInstances = ignoreList
	end

	while true do
		local raycastResult = workspace:Raycast(origin, direction * length, raycastParams)

		if not raycastResult or not raycastResult.Instance then
			return getSkyboxColor(origin, direction)
		end

		-- We should techincally be casting through semi-transparent objects and blending the result,
		-- but that's super costly and we need to be fast so we just use the first object we find

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
			-- Note that this can be wildly wrong for textured or decaled items
			-- but again- speed is more important here. We aren't writing a raycast renderer,
			-- we're just approximating colors.
			local color = hit.Color:Lerp(Lighting.FogColor, fogBlend)
			return color.R, color.G, color.B, 1 - hit.Transparency
		end
	end
end

return function(queryPoint: Vector2): (number, number, number, number)
	local ray = workspace.CurrentCamera:ScreenPointToRay(queryPoint.X, queryPoint.Y, 0)
	return raycastUntilColor(ray.Origin, ray.Direction, 500)
end
