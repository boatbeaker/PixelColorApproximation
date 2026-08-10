local Utils = require(script.Parent.Parent.Parent.Utils)
local defaultHandler = require(script.Parent.default)

return function(queryPoint: Vector2, gui: ImageLabel | ImageButton): (number, number, number, number)
	local r, g, b, a = defaultHandler(queryPoint, gui)
	if gui.ImageTransparency == 1 then
		return r, g, b, a
	end
	-- The Image/IsLoaded checks only apply to uri sources; object sources have no uri
	if gui.ImageContent.SourceType ~= Enum.ContentSourceType.Object and (gui.Image == "" or gui.IsLoaded == false) then
		return r, g, b, a
	end

	local image, isDownscaled = Utils.getImage(gui)
	if not image then
		return r, g, b, a
	end

	local queryInObjectSpace =
		Utils.worldToLocal(queryPoint, gui.AbsolutePosition, gui.AbsoluteSize, math.rad(gui.Rotation))
	local imageWidth, imageHeight = image.width, image.height
	local objectWidth, objectHeight = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	local queryInImageSpace = queryInObjectSpace

	-- Find where on the image we'll be sampling
	if gui.ScaleType == Enum.ScaleType.Fit then
		if objectWidth <= objectHeight then
			-- Image will display across width, so we need to adjust our objectSpace Y into imageSpace Y
			local imageSizeInObject = Vector2.new(objectWidth, objectWidth / imageWidth * imageHeight)
			local imagePositionInObject = Vector2.new(0, (objectHeight - imageSizeInObject.Y) / 2)
			local minimumObjectSpace = imagePositionInObject.Y / objectHeight
			if queryInObjectSpace.Y < minimumObjectSpace then
				return r, g, b, a
			end
			local maximumObjectSpace = 1 - minimumObjectSpace
			if queryInObjectSpace.Y > maximumObjectSpace then
				return r, g, b, a
			end
			local range = maximumObjectSpace - minimumObjectSpace

			queryInImageSpace = Vector2.new(queryInObjectSpace.X, (queryInObjectSpace.Y - minimumObjectSpace) / range)
		else
			-- Image will display across height, so we need to adjust our objectSpace X into imageSpace X
			local imageSizeInObject = Vector2.new(objectHeight / imageHeight * imageWidth, objectHeight)
			local imagePositionInObject = Vector2.new((objectWidth - imageSizeInObject.X) / 2, 0)
			local minimumObjectSpace = imagePositionInObject.X / objectWidth
			if queryInObjectSpace.X < minimumObjectSpace then
				return r, g, b, a
			end
			local maximumObjectSpace = 1 - minimumObjectSpace
			if queryInObjectSpace.X > maximumObjectSpace then
				return r, g, b, a
			end
			local range = maximumObjectSpace - minimumObjectSpace

			queryInImageSpace = Vector2.new((queryInObjectSpace.X - minimumObjectSpace) / range, queryInObjectSpace.Y)
		end
		--TODO: elseif object.ScaleType == Enum.ScaleType.Crop then
	end

	local downScaleFactor = (if isDownscaled then Utils.IMAGE_DOWNSCALE_FACTOR else 1)
	local rectScaleX = gui.ImageRectSize.X * downScaleFactor / imageWidth
	local rectScaleY = gui.ImageRectSize.Y * downScaleFactor / imageHeight
	if rectScaleX ~= 0 or rectScaleY ~= 0 then
		-- Adjust queryInImageSpace based on rect cutout
		local rectPosX = gui.ImageRectOffset.X * downScaleFactor / imageWidth
		local rectPosY = gui.ImageRectOffset.Y * downScaleFactor / imageHeight
		queryInImageSpace = Vector2.new(
			math.clamp(queryInImageSpace.X * rectScaleX + rectPosX, 0, 1),
			math.clamp(queryInImageSpace.Y * rectScaleY + rectPosY, 0, 1)
		)
	end

	-- If the query point is outside the image, return the background color
	if queryInImageSpace.X < 0 or queryInImageSpace.X > 1 or queryInImageSpace.Y < 0 or queryInImageSpace.Y > 1 then
		return r, g, b, a
	end

	-- Get the pixel color at the query point
	local imageR, imageG, imageB, imageA = Utils.readPixel(
		image,
		math.clamp(math.floor(queryInImageSpace.X * imageWidth), 0, imageWidth - 1),
		math.clamp(math.floor(queryInImageSpace.Y * imageHeight), 0, imageHeight - 1)
	)

	-- Blend the gui properties
	local multColor = gui.ImageColor3
	imageR *= multColor.R
	imageG *= multColor.G
	imageB *= multColor.B
	imageA *= 1 - gui.ImageTransparency

	-- Blend this pixel over the background
	return (1 - imageA) * (r * a) + imageA * imageR,
		(1 - imageA) * (g * a) + imageA * imageG,
		(1 - imageA) * (b * a) + imageA * imageB,
		math.max(imageA, a)
end
