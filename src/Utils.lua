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

export type ImageLevel = {
	pixels: buffer,
	width: number,
	height: number,
}

-- CPU-cached pixels or live EditableImage. Cached images have a mip chain for footprint reads
export type ImageRecord = {
	pixels: buffer?,
	editable: EditableImage?,
	width: number,
	height: number,
	levels: { ImageLevel }?,
}

Utils.IMAGE_DOWNSCALE_FACTOR = 0.75 -- Sample images at lower resolution to improve performance
Utils.IMAGE_CACHE = {} :: { [string]: ImageRecord }

-- Assets decoding in background thread; getImage returns nil until pixels land in cache
local loadingAssets: { [string]: boolean } = {}

-- Build half-resolution mip chain: each level is 2x2 average of previous, one-time work per asset
local function buildMipLevels(pixels: buffer, width: number, height: number): { ImageLevel }
	local levels: { ImageLevel } = { { pixels = pixels, width = width, height = height } }
	while (width > 1 or height > 1) and #levels < 8 do
		local newWidth, newHeight = math.max(1, width // 2), math.max(1, height // 2)
		local reduced = buffer.create(newWidth * newHeight * 4)
		for y = 0, newHeight - 1 do
			local y0 = math.min(y * 2, height - 1)
			local y1 = math.min(y * 2 + 1, height - 1)
			for x = 0, newWidth - 1 do
				local x0 = math.min(x * 2, width - 1)
				local x1 = math.min(x * 2 + 1, width - 1)
				local i00 = (y0 * width + x0) * 4
				local i10 = (y0 * width + x1) * 4
				local i01 = (y1 * width + x0) * 4
				local i11 = (y1 * width + x1) * 4
				local target = (y * newWidth + x) * 4
				for channel = 0, 3 do
					local sum = buffer.readu8(pixels, i00 + channel)
						+ buffer.readu8(pixels, i10 + channel)
						+ buffer.readu8(pixels, i01 + channel)
						+ buffer.readu8(pixels, i11 + channel)
					buffer.writeu8(reduced, target + channel, (sum + 2) // 4)
				end
			end
		end
		table.insert(levels, { pixels = reduced, width = newWidth, height = newHeight })
		pixels, width, height = reduced, newWidth, newHeight
	end
	return levels
end

-- Decode and cache asset in background thread to avoid stalling sampling loops
local function loadImageAsync(assetUri: string, assetId: string)
	pcall(function()
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

		-- Read pixels to buffer: skips per-sample engine calls and frees device memory
		local pixels = downscaled:ReadPixelsBuffer(Vector2.zero, downscaledSize)
		downscaled:Destroy()

		Utils.IMAGE_CACHE[assetId] = {
			pixels = pixels,
			width = downscaledSize.X,
			height = downscaledSize.Y,
			levels = buildMipLevels(pixels, downscaledSize.X, downscaledSize.Y),
		}
	end)
	-- On failure the next cache miss retries
	loadingAssets[assetId] = nil
end

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

	-- Cache miss: start background decode
	if not loadingAssets[assetId] then
		loadingAssets[assetId] = true
		task.spawn(loadImageAsync, assetUri, assetId)
	end

	return
end

-- Bilinear blend of four texels around (u, v); returns 0-255 channels
local function bilinearAt(
	pixels: buffer,
	width: number,
	height: number,
	u: number,
	v: number
): (number, number, number, number)
	local px = math.clamp(u * width - 0.5, 0, width - 1)
	local py = math.clamp(v * height - 0.5, 0, height - 1)
	local x0 = px // 1
	local y0 = py // 1
	local fx = px - x0
	local fy = py - y0
	local x1 = math.min(x0 + 1, width - 1)
	local y1 = math.min(y0 + 1, height - 1)
	local w11 = fx * fy
	local w10 = fx - w11
	local w01 = fy - w11
	local w00 = 1 - fx - fy + w11
	local i00 = (y0 * width + x0) * 4
	local i10 = (y0 * width + x1) * 4
	local i01 = (y1 * width + x0) * 4
	local i11 = (y1 * width + x1) * 4
	local r = buffer.readu8(pixels, i00) * w00
		+ buffer.readu8(pixels, i10) * w10
		+ buffer.readu8(pixels, i01) * w01
		+ buffer.readu8(pixels, i11) * w11
	local g = buffer.readu8(pixels, i00 + 1) * w00
		+ buffer.readu8(pixels, i10 + 1) * w10
		+ buffer.readu8(pixels, i01 + 1) * w01
		+ buffer.readu8(pixels, i11 + 1) * w11
	local b = buffer.readu8(pixels, i00 + 2) * w00
		+ buffer.readu8(pixels, i10 + 2) * w10
		+ buffer.readu8(pixels, i01 + 2) * w01
		+ buffer.readu8(pixels, i11 + 2) * w11
	local a = buffer.readu8(pixels, i00 + 3) * w00
		+ buffer.readu8(pixels, i10 + 3) * w10
		+ buffer.readu8(pixels, i01 + 3) * w01
		+ buffer.readu8(pixels, i11 + 3) * w11
	return r, g, b, a
end

-- Bilinear read at [0, 1] coordinates. Blends four texels to prevent shimmer from point sampling
function Utils.readPixelBilinear(image: ImageRecord, u: number, v: number): (number, number, number, number)
	local pixels = image.pixels
	if pixels then
		local r, g, b, a = bilinearAt(pixels, image.width, image.height, u, v)
		return r / 255, g / 255, b / 255, a / 255
	end

	-- Live EditableImage: read block covering corner texels, then blend
	local width, height = image.width, image.height
	local px = math.clamp(u * width - 0.5, 0, width - 1)
	local py = math.clamp(v * height - 0.5, 0, height - 1)
	local x0 = px // 1
	local y0 = py // 1
	local x1 = math.min(x0 + 1, width - 1)
	local y1 = math.min(y0 + 1, height - 1)
	local blockW = x1 - x0 + 1
	local block = (image.editable :: EditableImage):ReadPixelsBuffer(
		Vector2.new(x0, y0),
		Vector2.new(blockW, y1 - y0 + 1)
	)
	local fx = px - x0
	local fy = py - y0
	local w11 = fx * fy
	local w10 = fx - w11
	local w01 = fy - w11
	local w00 = 1 - fx - fy + w11
	local i10 = (blockW - 1) * 4
	local i01 = (y1 - y0) * blockW * 4
	local i11 = i01 + i10
	local r = buffer.readu8(block, 0) * w00
		+ buffer.readu8(block, i10) * w10
		+ buffer.readu8(block, i01) * w01
		+ buffer.readu8(block, i11) * w11
	local g = buffer.readu8(block, 1) * w00
		+ buffer.readu8(block, i10 + 1) * w10
		+ buffer.readu8(block, i01 + 1) * w01
		+ buffer.readu8(block, i11 + 1) * w11
	local b = buffer.readu8(block, 2) * w00
		+ buffer.readu8(block, i10 + 2) * w10
		+ buffer.readu8(block, i01 + 2) * w01
		+ buffer.readu8(block, i11 + 2) * w11
	local a = buffer.readu8(block, 3) * w00
		+ buffer.readu8(block, i10 + 3) * w10
		+ buffer.readu8(block, i01 + 3) * w01
		+ buffer.readu8(block, i11 + 3) * w11
	return r / 255, g / 255, b / 255, a / 255
end

-- Footprint read using mip levels to band-limit before sampling. Prevents aliasing shimmer
function Utils.readPixelFiltered(
	image: ImageRecord,
	u: number,
	v: number,
	footprintTexels: number
): (number, number, number, number)
	local levels = image.levels
	if not levels or footprintTexels <= 1 then
		return Utils.readPixelBilinear(image, u, v)
	end

	local level = math.log(footprintTexels, 2)
	local topIndex = #levels
	if level >= topIndex - 1 then
		local top = levels[topIndex]
		local r, g, b, a = bilinearAt(top.pixels, top.width, top.height, u, v)
		return r / 255, g / 255, b / 255, a / 255
	end

	local lowIndex = level // 1
	local fraction = level - lowIndex
	local low = levels[lowIndex + 1]
	local high = levels[lowIndex + 2]
	local lowR, lowG, lowB, lowA = bilinearAt(low.pixels, low.width, low.height, u, v)
	local highR, highG, highB, highA = bilinearAt(high.pixels, high.width, high.height, u, v)
	return (lowR + (highR - lowR) * fraction) / 255,
		(lowG + (highG - lowG) * fraction) / 255,
		(lowB + (highB - lowB) * fraction) / 255,
		(lowA + (highA - lowA) * fraction) / 255
end

function Utils.getSkyboxFaceAndCoords(lookDirection: Vector3): (string, number, number)
	local absX = math.abs(lookDirection.X)
	local absY = math.abs(lookDirection.Y)
	local absZ = math.abs(lookDirection.Z)
	local face, u, v

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

	v = 1 - v

	return face, u, v
end

return Utils
