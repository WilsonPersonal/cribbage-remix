extends Control
class_name FactionCubeRow

const CUBE_RADIUS := 5.0
const CUBE_SPACING := 12.0

var _faction_ids: Array = []


func set_factions(faction_ids: Array) -> void:
	_faction_ids = faction_ids.duplicate()
	var width := CUBE_RADIUS * 2.0
	if _faction_ids.size() > 1:
		width += float(_faction_ids.size() - 1) * CUBE_SPACING
	custom_minimum_size = Vector2(width, CUBE_RADIUS * 2.0)
	queue_redraw()


func _draw() -> void:
	for index in range(_faction_ids.size()):
		var pos := Vector2(CUBE_RADIUS + float(index) * CUBE_SPACING, CUBE_RADIUS)
		var color: Color = Factions.COLORS[int(_faction_ids[index])]
		Factions.draw_cube(self, pos, CUBE_RADIUS, color)
