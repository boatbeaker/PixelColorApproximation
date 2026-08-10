local ClassHandlers = require(script.ClassHandlers)

return function(queryPoint: Vector2, gui: GuiObject): (number, number, number, number)
	return ClassHandlers[gui.ClassName](queryPoint, gui)
end
