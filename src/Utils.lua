local AssetService = game:GetService("AssetService")

local Utils = {}

function Utils.worldToLocal(vector, position, size, rotation)
	local translated = vector - position
	local cosAngle = math.cos(-rotation)
	local sinAngle = math.sin(-rotation)
	local rotatedX = cosAngle * translated.X - sinAngle * translated.Y
	local rotatedY = sinAngle * translated.X + cosAngle * translated.Y
	local scaledX = rotatedX / size.X
	local scaledY = rotatedY / size.Y
	return Vector2.new(scaledX, scaledY)
end

-- A sampleable image: either pixels cached CPU-side (static uri assets) or a
-- live EditableImage whose content can change between reads (object sources)
export type ImageRecord = {
	pixels: buffer?,
	editable: EditableImage?,
	width: number,
	height: number,
}

Utils.IMAGE_DOWNSCALE_FACTOR = 0.75 -- Sample images at lower resolution to improve performance
Utils.IMAGE_CACHE = {} :: { [string]: ImageRecord }

function Utils.getImage(source: string | Instance): (ImageRecord?, boolean?)
	local assetUri: string

	local sourceType = typeof(source)
	if sourceType == "string" then
		assetUri = source :: string
	elseif sourceType == "Instance" then
		local sourceInstance = source :: Instance
		if sourceInstance:IsA("ImageLabel") or sourceInstance:IsA("ImageButton") then
			local content = sourceInstance.ImageContent
			if content.SourceType == Enum.ContentSourceType.Object then
				local object = content.Object
				if object and object:IsA("EditableImage") then
					local size = object.Size
					return { editable = object, width = size.X, height = size.Y }, false
				end
				return
			end
			assetUri = sourceInstance.Image
		elseif sourceInstance:IsA("Texture") or sourceInstance:IsA("Decal") then
			assetUri = sourceInstance.Texture
		elseif sourceInstance:IsA("SurfaceAppearance") then
			assetUri = sourceInstance.ColorMap
		end
	else
		return
	end

	if assetUri == nil or assetUri == "" then
		return
	end

	local assetId: string? = string.match(assetUri, "%d+$")
	if assetId == nil then
		return
	end

	if Utils.IMAGE_CACHE[assetId] then
		return Utils.IMAGE_CACHE[assetId], true
	end

	local success, record = pcall(function()
		local fullImage = AssetService:CreateEditableImageAsync(Content.fromUri(assetUri))
		-- EditableImage lost its Resize method, so downscale by drawing into a smaller image
		local downscaledSize = Vector2.new(
			math.max(1, math.floor(fullImage.Size.X * Utils.IMAGE_DOWNSCALE_FACTOR)),
			math.max(1, math.floor(fullImage.Size.Y * Utils.IMAGE_DOWNSCALE_FACTOR))
		)
		local downscaled = AssetService:CreateEditableImage({ Size = downscaledSize })
		downscaled:DrawImageTransformed(Vector2.zero, downscaledSize / fullImage.Size, 0, fullImage, {
			CombineType = Enum.ImageCombineType.Overwrite,
			PivotPoint = Vector2.zero,
		})
		fullImage:Destroy()

		-- Cache the pixels CPU-side and destroy the image: buffer reads skip
		-- the per-sample engine call, and the editable memory is returned to
		-- the device budget
		local pixels = downscaled:ReadPixelsBuffer(Vector2.zero, downscaledSize)
		downscaled:Destroy()

		local newRecord: ImageRecord = {
			pixels = pixels,
			width = downscaledSize.X,
			height = downscaledSize.Y,
		}
		Utils.IMAGE_CACHE[assetId] = newRecord
		return newRecord
	end)

	if success then
		return record, true
	end

	return
end

function Utils.readPixel(image: ImageRecord, x: number, y: number): (number, number, number, number)
	local pixels = image.pixels
	if pixels then
		local index = (y * image.width + x) * 4
		return buffer.readu8(pixels, index) / 255,
			buffer.readu8(pixels, index + 1) / 255,
			buffer.readu8(pixels, index + 2) / 255,
			buffer.readu8(pixels, index + 3) / 255
	end

	local pixelBuffer = (image.editable :: EditableImage):ReadPixelsBuffer(Vector2.new(x, y), Vector2.one)
	return buffer.readu8(pixelBuffer, 0) / 255,
		buffer.readu8(pixelBuffer, 1) / 255,
		buffer.readu8(pixelBuffer, 2) / 255,
		buffer.readu8(pixelBuffer, 3) / 255
end

function Utils.getSkyboxFaceAndCoords(lookDirection: Vector3): (string, number, number)
	local absX = math.abs(lookDirection.X)
	local absY = math.abs(lookDirection.Y)
	local absZ = math.abs(lookDirection.Z)
	local face, u, v

	-- Determine the primary direction of the lookDirection vector and calculate 2D coordinates
	if absX > absY and absX > absZ then
		if lookDirection.X < 0 then
			face = "SkyboxRt"
			u = 1 - (lookDirection.Z / absX + 1) / 2
			v = (lookDirection.Y / absX + 1) / 2
		else
			face = "SkyboxLf"
			u = (lookDirection.Z / absX + 1) / 2
			v = (lookDirection.Y / absX + 1) / 2
		end
	elseif absY > absZ then
		if lookDirection.Y > 0 then
			face = "SkyboxUp"
			u = 1 - (lookDirection.Z / absY + 1) / 2
			v = (lookDirection.X / absY + 1) / 2
		else
			face = "SkyboxDn"
			u = 1 - (lookDirection.Z / absY + 1) / 2
			v = 1 - (lookDirection.X / absY + 1) / 2
		end
	else
		if lookDirection.Z < 0 then
			face = "SkyboxFt"
			u = (lookDirection.X / absZ + 1) / 2
			v = (lookDirection.Y / absZ + 1) / 2
		else
			face = "SkyboxBk"
			u = 1 - (lookDirection.X / absZ + 1) / 2
			v = (lookDirection.Y / absZ + 1) / 2
		end
	end

	-- Invert v to map the coordinate system correctly
	v = 1 - v

	return face, u, v
end

return Utils
