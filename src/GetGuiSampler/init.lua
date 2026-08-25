-- Layer records: per-object snapshot cached per frame to skip Instance reads in the sampling path

local RunService = game:GetService("RunService")

local ClassHandlers = require(script.ClassHandlers)

local layerCache = setmetatable({}, { __mode = "k" })

local frameNumber = 0
RunService.PostSimulation:Connect(function()
	frameNumber += 1
end)

return function(gui)
	local record = layerCache[gui]
	if record and record.describedAt == frameNumber then
		return record
	end

	record = ClassHandlers[gui.ClassName](gui)
	record.describedAt = frameNumber
	layerCache[gui] = record
	return record
end
