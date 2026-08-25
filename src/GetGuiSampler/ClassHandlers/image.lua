-- Image layer: describe() snapshots image, transform, fit, rect; sample() is pure math with one pixel read

local Utils = require(script.Parent.Parent.Parent.Utils)
local describeDefault = require(script.Parent.default)

local function sample(record, x, y, footprint)
	local r, g, b, a = record.r, record.g, record.b, record.a
	local image = record.image
	if not image then
		return r, g, b, a
	end

	-- Transform to object space with cached rotation
	local translatedX = x - record.posX
	local translatedY = y - record.posY
	local objectX = (record.cos * translatedX - record.sin * translatedY) * record.invSizeX
	local objectY = (record.sin * translatedX + record.cos * translatedY) * record.invSizeY

	-- Fit letterboxing: reject the bars, stretch the rest back to the image
	local fitAxis = record.fitAxis
	if fitAxis == "y" then
		if objectY < record.fitMin or objectY > record.fitMax then
			return r, g, b, a
		end
		objectY = (objectY - record.fitMin) / record.fitRange
	elseif fitAxis == "x" then
		if objectX < record.fitMin or objectX > record.fitMax then
			return r, g, b, a
		end
		objectX = (objectX - record.fitMin) / record.fitRange
	end

	local rectScaleX, rectScaleY = record.rectScaleX, record.rectScaleY
	if rectScaleX ~= 0 or rectScaleY ~= 0 then
		objectX = math.clamp(objectX * rectScaleX + record.rectPosX, 0, 1)
		objectY = math.clamp(objectY * rectScaleY + record.rectPosY, 0, 1)
	end

	if objectX < 0 or objectX > 1 or objectY < 0 or objectY > 1 then
		return r, g, b, a
	end

	-- Sample with footprint filtering to prevent aliasing
	local imageR, imageG, imageB, imageA =
		Utils.readPixelFiltered(image, objectX, objectY, (footprint or 1) * record.texelScale)

	imageR *= record.multR
	imageG *= record.multG
	imageB *= record.multB
	imageA *= record.alphaMult

	return (1 - imageA) * (r * a) + imageA * imageR,
		(1 - imageA) * (g * a) + imageA * imageG,
		(1 - imageA) * (b * a) + imageA * imageB,
		math.max(imageA, a)
end

local function describe(gui)
	local record = describeDefault(gui)
	record.sample = sample
	record.image = nil

	local imageTransparency = gui.ImageTransparency
	if imageTransparency == 1 then
		return record
	end
	-- Image/IsLoaded checks only apply to URI sources
	if gui.ImageContent.SourceType ~= Enum.ContentSourceType.Object and (gui.Image == "" or gui.IsLoaded == false) then
		return record
	end

	local image, isDownscaled = Utils.getImage(gui)
	if not image then
		return record
	end
	record.image = image

	local absolutePosition, absoluteSize = gui.AbsolutePosition, gui.AbsoluteSize
	local rotation = math.rad(gui.Rotation)
	record.posX, record.posY = absolutePosition.X, absolutePosition.Y
	record.cos, record.sin = math.cos(-rotation), math.sin(-rotation)
	record.invSizeX, record.invSizeY = 1 / absoluteSize.X, 1 / absoluteSize.Y

	local imageWidth, imageHeight = image.width, image.height
	local objectWidth, objectHeight = absoluteSize.X, absoluteSize.Y
	record.fitAxis = nil
	if gui.ScaleType == Enum.ScaleType.Fit then
		if objectWidth <= objectHeight then
			-- Image constrained by width; adjust object-space Y to image-space Y
			local imageSizeInObject = objectWidth / imageWidth * imageHeight
			local minimumObjectSpace = ((objectHeight - imageSizeInObject) / 2) / objectHeight
			record.fitAxis = "y"
			record.fitMin = minimumObjectSpace
			record.fitMax = 1 - minimumObjectSpace
			record.fitRange = record.fitMax - record.fitMin
		else
			-- Image constrained by height; adjust object-space X to image-space X
			local imageSizeInObject = objectHeight / imageHeight * imageWidth
			local minimumObjectSpace = ((objectWidth - imageSizeInObject) / 2) / objectWidth
			record.fitAxis = "x"
			record.fitMin = minimumObjectSpace
			record.fitMax = 1 - minimumObjectSpace
			record.fitRange = record.fitMax - record.fitMin
		end
		--TODO: elseif object.ScaleType == Enum.ScaleType.Crop then
	end

	local downScaleFactor = (if isDownscaled then Utils.IMAGE_DOWNSCALE_FACTOR else 1)
	local imageRectSize, imageRectOffset = gui.ImageRectSize, gui.ImageRectOffset
	record.rectScaleX = imageRectSize.X * downScaleFactor / imageWidth
	record.rectScaleY = imageRectSize.Y * downScaleFactor / imageHeight
	record.rectPosX = imageRectOffset.X * downScaleFactor / imageWidth
	record.rectPosY = imageRectOffset.Y * downScaleFactor / imageHeight

	-- Texel scale: screen px to texels through object scale, fit, and rect. Larger axis wins to cover spacing on both
	local rectActive = record.rectScaleX ~= 0 or record.rectScaleY ~= 0
	local uScale = (if record.fitAxis == "x" then 1 / record.fitRange else 1)
		* (if rectActive then record.rectScaleX else 1)
	local vScale = (if record.fitAxis == "y" then 1 / record.fitRange else 1)
		* (if rectActive then record.rectScaleY else 1)
	record.texelScale = math.max(uScale * imageWidth * record.invSizeX, vScale * imageHeight * record.invSizeY)

	local multColor = gui.ImageColor3
	record.multR = multColor.R
	record.multG = multColor.G
	record.multB = multColor.B
	record.alphaMult = 1 - imageTransparency

	return record
end

return describe
