extends Control

const HEX_RADIUS := 46.0
const FLAT_TOP_Y := sqrt(3.0) * 0.5

const TERRAIN_COLORS := {
	HexBoard.Terrain.MOUNTAIN: Color("#8a9098"),
	HexBoard.Terrain.FOREST: Color("#3f7a43"),
	HexBoard.Terrain.PASTURE: Color("#b8c86a"),
}

const WATER_COLOR := Color("#4a8ec4")
const BRIDGE_COLOR := Color("#7a5236")

var _board_state: Array = []
var _faction_power: Dictionary = {}


func _ready() -> void:
	GameState.board_updated.connect(_on_board_updated)
	if GameState.get_board_state().size() > 0:
		_on_board_updated(GameState.get_board_state(), GameState.get_faction_power())


func _on_board_updated(board_state: Array, faction_power: Dictionary) -> void:
	_board_state = board_state
	_faction_power = faction_power
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WATER_COLOR)

	_draw_legend()
	if _board_state.is_empty():
		return

	var centers := _hex_centers()
	_draw_bridges(centers)
	for hex_index in range(HexBoard.HEX_COUNT):
		_draw_hex(centers[hex_index], hex_index)
	_draw_spawn_arrows(centers)


func _draw_legend() -> void:
	var y := 20.0
	draw_string(
		ThemeDB.fallback_font,
		Vector2(16, y),
		"Carts: mountain -> opposite forest | Cubes placed from setup card suits",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color.WHITE
	)
	y += 18.0

	for faction in Factions.ALL:
		var power := int(_faction_power.get(faction, 0))
		var score := int(GameState.faction_scores.get(faction, 0))
		draw_string(
			ThemeDB.fallback_font,
			Vector2(16, y),
			"%s | cubes: %d | score: %d" % [Factions.name_for(faction), power, score],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Factions.COLORS[faction]
		)
		y += 16.0


func _draw_bridges(centers: Array) -> void:
	for pair in HexBoard.BRIDGE_PAIRS:
		var a: int = pair[0]
		var b: int = pair[1]
		var edge := _shared_edge(centers[a], centers[b])
		var edge_a: Vector2 = edge["a"]
		var edge_b: Vector2 = edge["b"]
		var direction := (edge_b - edge_a).normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		for offset in [-3.0, 3.0]:
			draw_line(
				edge_a + perpendicular * offset,
				edge_b + perpendicular * offset,
				BRIDGE_COLOR,
				4.0
			)


func _draw_spawn_arrows(centers: Array) -> void:
	for hex_index in HexBoard.MOUNTAIN_HEXES:
		var center: Vector2 = centers[hex_index]
		var arrow_start := center
		var arrow_end := center
		match hex_index:
			0:
				arrow_start = center + Vector2(0, -HEX_RADIUS * (FLAT_TOP_Y + 0.55))
				arrow_end = center + Vector2(0, -HEX_RADIUS * FLAT_TOP_Y)
			6:
				arrow_start = center + Vector2(-HEX_RADIUS * 1.2, HEX_RADIUS * (FLAT_TOP_Y + 0.15))
				arrow_end = center + Vector2(-HEX_RADIUS * 0.78, HEX_RADIUS * FLAT_TOP_Y * 0.35)
			7:
				arrow_start = center + Vector2(HEX_RADIUS * 1.2, HEX_RADIUS * (FLAT_TOP_Y + 0.15))
				arrow_end = center + Vector2(HEX_RADIUS * 0.78, HEX_RADIUS * FLAT_TOP_Y * 0.35)
		draw_line(arrow_start, arrow_end, Color("#27ae60"), 3.0)
		_draw_arrow_head(arrow_end, (arrow_end - arrow_start).normalized())


func _draw_arrow_head(tip: Vector2, direction: Vector2) -> void:
	var side := Vector2(-direction.y, direction.x)
	var p1 := tip - direction * 10.0 + side * 5.0
	var p2 := tip - direction * 10.0 - side * 5.0
	draw_colored_polygon(PackedVector2Array([tip, p1, p2]), Color("#27ae60"))


func _draw_hex(center: Vector2, hex_index: int) -> void:
	var terrain: int = HexBoard.terrain_for(hex_index)
	var points := _hex_points(center, HEX_RADIUS)
	var fill: Color = TERRAIN_COLORS.get(terrain, Color.GRAY)

	if hex_index in HexBoard.FOREST_HEXES:
		fill = fill.lightened(0.08)

	draw_colored_polygon(points, fill)
	for i in range(points.size()):
		draw_line(points[i], points[(i + 1) % points.size()], Color(0.15, 0.15, 0.18, 1.0), 2.5)

	_draw_hex_labels(center, hex_index)

	if hex_index >= _board_state.size():
		return

	var hex: Dictionary = _board_state[hex_index]
	_draw_cube_dots(center, hex.get("cubes", {}))

	var carts: Dictionary = hex.get("carts", {})
	for faction in Factions.ALL:
		var cart_origins: Array = carts.get(faction, [])
		for cart_index in range(cart_origins.size()):
			var cart_pos := center + Vector2(-12 + cart_index * 14, 28)
			draw_rect(Rect2(cart_pos, Vector2(10, 8)), Factions.COLORS[faction], false, 2.0)


func _draw_cube_dots(center: Vector2, cubes: Dictionary) -> void:
	var dot_colors: Array = []
	for faction in Factions.ALL:
		for _cube in range(int(cubes.get(faction, 0))):
			dot_colors.append(Factions.COLORS[faction])

	if dot_colors.is_empty():
		return

	var columns := mini(dot_colors.size(), 5)
	var dot_radius := 4.5
	var x_spacing := 11.0
	var y_spacing := 10.0

	for dot_index in range(dot_colors.size()):
		var row: int = int(float(dot_index) / float(columns))
		var col := dot_index % columns
		var dots_in_row := mini(columns, dot_colors.size() - row * columns)
		var row_start_x := -float(dots_in_row - 1) * x_spacing * 0.5
		var pos := center + Vector2(row_start_x + float(col) * x_spacing, 8.0 + float(row) * y_spacing)
		draw_circle(pos, dot_radius, dot_colors[dot_index])


func _draw_hex_labels(center: Vector2, hex_index: int) -> void:
	var labels: Array = HexBoard.labels_for(hex_index)
	if labels.is_empty():
		return

	if labels.size() == 1:
		draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-6, 4),
			str(labels[0]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			18,
			Color(0.05, 0.05, 0.05, 1.0)
		)
		return

	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(-16, -6),
		str(labels[0]),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		Color(0.05, 0.05, 0.05, 1.0)
	)
	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(4, 10),
		str(labels[1]),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		Color(0.05, 0.05, 0.05, 1.0)
	)


func _hex_centers() -> Array:
	var bounds := HexBoard.board_pixel_bounds(HEX_RADIUS)
	var origin := Vector2(size.x * 0.5, size.y * 0.5) - bounds.get_center()

	var centers: Array = []
	for hex_index in range(HexBoard.HEX_COUNT):
		centers.append(HexBoard.pixel_center(hex_index, HEX_RADIUS, origin))
	return centers


func _shared_edge(center_a: Vector2, center_b: Vector2) -> Dictionary:
	var midpoint := (center_a + center_b) * 0.5
	var direction := (center_b - center_a).normalized()
	var edge_direction := Vector2(-direction.y, direction.x)
	var half_edge := HEX_RADIUS * 0.5
	return {
		"a": midpoint - edge_direction * half_edge,
		"b": midpoint + edge_direction * half_edge,
	}


func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i in range(6):
		points.append(center + HexBoard.hex_corner_offset(i, radius))
	return points
