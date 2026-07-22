class_name HexBoardMiniView
extends Control

const REFERENCE_RADIUS := 62.0
const WATER_COLOR := Color("#4a8ec4")
const BRIDGE_COLOR := Color("#7a5236")
const HIGHLIGHT_COLOR := Color(1.0, 0.88, 0.35, 0.95)

const TERRAIN_COLORS := {
	HexBoard.Terrain.MOUNTAIN: Color("#8a9098"),
	HexBoard.Terrain.FOREST: Color("#3f7a43"),
	HexBoard.Terrain.PASTURE: Color("#b8c86a"),
}

var board_state: Array = []
var highlight_hexes: Array = []


func set_board(state: Array, highlights: Array = []) -> void:
	board_state = state
	highlight_hexes = highlights.duplicate()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WATER_COLOR)

	if board_state.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			Vector2(8.0, size.y * 0.5),
			"No map data",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12,
			Color(0.85, 0.88, 0.92, 0.8)
		)
		return

	var hex_radius := _fit_hex_radius()
	var scale := hex_radius / REFERENCE_RADIUS
	var centers := _hex_centers(hex_radius)
	_draw_bridges(centers, hex_radius, scale)

	for hex_index in range(HexBoard.HEX_COUNT):
		_draw_hex(centers[hex_index], hex_index, hex_radius, scale)

	_draw_carts(centers, hex_radius, scale)

	for hex_index in highlight_hexes:
		var index := int(hex_index)
		if index >= 0 and index < centers.size():
			_draw_hex_ring(centers[index], hex_radius, HIGHLIGHT_COLOR, maxf(1.5, 2.5 * scale))


func _fit_hex_radius() -> float:
	var unit_bounds := HexBoard.board_pixel_bounds(1.0)
	var margin := 6.0
	var scale_x := (size.x - margin * 2.0) / unit_bounds.size.x
	var scale_y := (size.y - margin * 2.0) / unit_bounds.size.y
	return maxf(16.0, minf(scale_x, scale_y))


func _hex_centers(hex_radius: float) -> Array:
	var bounds := HexBoard.board_pixel_bounds(hex_radius)
	var origin := Vector2(size.x * 0.5, size.y * 0.5) - bounds.get_center()
	var centers: Array = []
	for hex_index in range(HexBoard.HEX_COUNT):
		centers.append(HexBoard.pixel_center(hex_index, hex_radius, origin))
	return centers


func _draw_bridges(centers: Array, hex_radius: float, scale: float) -> void:
	for pair in HexBoard.BRIDGE_PAIRS:
		var start: Vector2 = centers[pair[0]]
		var end: Vector2 = centers[pair[1]]
		var direction := (end - start).normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		var boundary_a := _hex_boundary_point(start, end, hex_radius)
		var boundary_b := _hex_boundary_point(end, start, hex_radius)
		var gap_length := boundary_a.distance_to(boundary_b)
		var segment_half_length := gap_length * 0.11
		for segment_ratio in [0.33, 0.67]:
			var segment_center := boundary_a.lerp(boundary_b, segment_ratio)
			var segment_start := segment_center - direction * segment_half_length
			var segment_end := segment_center + direction * segment_half_length
			for offset in [-4.0 * scale, 4.0 * scale]:
				draw_line(
					segment_start + perpendicular * offset,
					segment_end + perpendicular * offset,
					BRIDGE_COLOR,
					maxf(2.0, 4.0 * scale)
				)


func _draw_hex(center: Vector2, hex_index: int, hex_radius: float, scale: float) -> void:
	var terrain: int = HexBoard.terrain_for(hex_index)
	var points := _hex_points(center, hex_radius)
	var fill: Color = TERRAIN_COLORS.get(terrain, Color.GRAY)
	if hex_index in HexBoard.FOREST_HEXES:
		fill = fill.lightened(0.08)

	draw_colored_polygon(points, fill)
	for i in range(points.size()):
		draw_line(
			points[i],
			points[(i + 1) % points.size()],
			Color(0.15, 0.15, 0.18, 1.0),
			maxf(1.0, 2.5 * scale)
		)

	_draw_hex_labels(center, hex_index, hex_radius, scale)

	if hex_index >= board_state.size():
		return

	var cubes: Dictionary = board_state[hex_index].get("cubes", {})
	_draw_cube_dots(center, cubes, scale)


func _draw_hex_labels(center: Vector2, hex_index: int, hex_radius: float, scale: float) -> void:
	var labels: Array = HexBoard.labels_for(hex_index)
	if labels.is_empty():
		return

	var font_size := maxi(8, int(round(18.0 * scale)))
	var label_y := center.y - hex_radius * sqrt(3.0) * 0.5 + float(font_size)
	var label_color := Color(0.05, 0.05, 0.05, 1.0)

	if labels.size() == 1:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(center.x - 20.0 * scale, label_y),
			str(labels[0]),
			HORIZONTAL_ALIGNMENT_CENTER,
			int(40.0 * scale),
			font_size,
			label_color
		)
		return

	draw_string(
		ThemeDB.fallback_font,
		Vector2(center.x - 26.0 * scale, label_y),
		str(labels[0]),
		HORIZONTAL_ALIGNMENT_CENTER,
		int(24.0 * scale),
		font_size,
		label_color
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center.x + 2.0 * scale, label_y),
		str(labels[1]),
		HORIZONTAL_ALIGNMENT_CENTER,
		int(24.0 * scale),
		font_size,
		label_color
	)


func _draw_cube_dots(hex_center: Vector2, cubes: Dictionary, scale: float) -> void:
	var dot_colors: Array = []
	for faction in Factions.ALL:
		for _cube in range(RemixRules.faction_dict_value(cubes, faction)):
			dot_colors.append(Factions.COLORS[faction])

	var dot_radius := 4.5 * scale
	var x_spacing := 11.0 * scale
	var y_spacing := 10.0 * scale
	var max_columns := 5

	for dot_index in range(dot_colors.size()):
		var columns := mini(dot_colors.size(), max_columns)
		var row: int = int(float(dot_index) / float(columns))
		var col := dot_index % columns
		var dots_in_row := mini(columns, dot_colors.size() - row * columns)
		var row_start_x := -float(dots_in_row - 1) * x_spacing * 0.5
		var pos := hex_center + Vector2(
			row_start_x + float(col) * x_spacing,
			8.0 * scale + float(row) * y_spacing
		)
		Factions.draw_cube(self, pos, dot_radius, dot_colors[dot_index])


func _draw_carts(centers: Array, hex_radius: float, scale: float) -> void:
	for hex_index in range(board_state.size()):
		var hex: Dictionary = board_state[hex_index]
		var center: Vector2 = centers[hex_index]
		var carts: Dictionary = hex.get("carts", {})
		var entries: Array = _sorted_cart_entries(_cart_entries_for_hex(hex_index, carts))
		for entry_index in range(entries.size()):
			var entry: Dictionary = entries[entry_index]
			var faction: int = int(entry.get("faction", -1))
			var origin_hex := int(entry.get("origin_hex", -1))
			var arrow := _cart_arrow_geometry(
				hex_index,
				center,
				centers,
				origin_hex,
				entries.size(),
				entry_index,
				scale
			)
			if arrow.is_empty():
				continue
			var color: Color = Factions.COLORS[faction]
			draw_line(arrow.start, arrow.end, color, maxf(1.5, 3.0 * scale))
			_draw_colored_arrow_head(arrow.end, arrow.toward_goal, color, scale)


func _cart_entries_for_hex(hex_index: int, carts: Dictionary) -> Array:
	var entries: Array = []
	for faction in Factions.ALL:
		var cart_origins: Array = carts.get(faction, [])
		for cart_index in range(cart_origins.size()):
			entries.append({
				"faction": faction,
				"origin_hex": int(cart_origins[cart_index]),
			})
	return entries


func _sorted_cart_entries(entries: Array) -> Array:
	var sorted: Array = entries.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var faction_a: int = int(a.get("faction", -1))
		var faction_b: int = int(b.get("faction", -1))
		if faction_a != faction_b:
			return faction_a < faction_b
		return int(a.get("origin_hex", -1)) < int(b.get("origin_hex", -1))
	)
	return sorted


func _cart_arrow_geometry(
	current_hex: int,
	hex_center: Vector2,
	centers: Array,
	origin_hex: int,
	total_carts: int,
	global_index: int,
	scale: float
) -> Dictionary:
	var goal_hex := int(HexBoard.CART_GOALS.get(origin_hex, -1))
	if goal_hex < 0 or goal_hex >= centers.size():
		return {}

	var next_hex := HexBoard.next_cart_path_hex(origin_hex, current_hex)
	if next_hex < 0:
		next_hex = goal_hex

	var next_center: Vector2 = centers[next_hex]
	var toward_goal := (next_center - hex_center).normalized()
	if toward_goal == Vector2.ZERO:
		return {}

	var lane_spacing := 10.0 * scale
	var side := Vector2(-toward_goal.y, toward_goal.x)
	var lane_offset := float(global_index - float(total_carts - 1) * 0.5) * lane_spacing
	var arrow_start := hex_center + toward_goal * 14.0 * scale + side * lane_offset
	var arrow_end := hex_center + toward_goal * 34.0 * scale + side * lane_offset
	return {
		"start": arrow_start,
		"end": arrow_end,
		"toward_goal": toward_goal,
	}


func _draw_colored_arrow_head(tip: Vector2, direction: Vector2, color: Color, scale: float) -> void:
	var side := Vector2(-direction.y, direction.x)
	var back := 10.0 * scale
	var wing := 5.0 * scale
	var p1 := tip - direction * back + side * wing
	var p2 := tip - direction * back - side * wing
	draw_colored_polygon(PackedVector2Array([tip, p1, p2]), color)


func _draw_hex_ring(center: Vector2, hex_radius: float, color: Color, width: float) -> void:
	var points := _hex_points(center, hex_radius + 4.0 * (hex_radius / REFERENCE_RADIUS))
	for i in range(points.size()):
		draw_line(points[i], points[(i + 1) % points.size()], color, width)


func _hex_boundary_point(center: Vector2, toward: Vector2, hex_radius: float) -> Vector2:
	var direction := (toward - center).normalized()
	if direction == Vector2.ZERO:
		return center

	var max_projection := 0.0
	for i in range(6):
		var corner := center + HexBoard.hex_corner_offset(i, hex_radius)
		max_projection = max(max_projection, (corner - center).dot(direction))
	return center + direction * max_projection


func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i in range(6):
		points.append(center + HexBoard.hex_corner_offset(i, radius))
	return points
