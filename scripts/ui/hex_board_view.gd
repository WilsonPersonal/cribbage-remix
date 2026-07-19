extends Control

signal hex_clicked(hex_index: int)

const HEX_RADIUS := 62.0
const BOARD_OFFSET := Vector2(-40.0, 0.0)

const TERRAIN_COLORS := {
	HexBoard.Terrain.MOUNTAIN: Color("#8a9098"),
	HexBoard.Terrain.FOREST: Color("#3f7a43"),
	HexBoard.Terrain.PASTURE: Color("#b8c86a"),
}

const WATER_COLOR := Color("#4a8ec4")
const BRIDGE_COLOR := Color("#7a5236")
const LEGEND_TEXT_COLOR := Color(0.96, 0.97, 0.99, 1.0)

var _board_state: Array = []
var _faction_power: Dictionary = {}
var _action_selected_hex: int = -1
var _action_target_hexes: Array = []
var _crib_target_hexes: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameState.board_updated.connect(_on_board_updated)
	GameState.phase_changed.connect(_on_phase_changed)
	if GameState.get_board_state().size() > 0:
		_on_board_updated(GameState.get_board_state(), GameState.get_faction_power())


func _on_phase_changed(_phase: GameState.Phase) -> void:
	clear_action_selection()
	clear_crib_selection()


func clear_action_selection() -> void:
	_action_selected_hex = -1
	_action_target_hexes.clear()
	queue_redraw()


func clear_crib_selection() -> void:
	_crib_target_hexes.clear()
	queue_redraw()


func set_crib_selection(target_hexes: Array) -> void:
	_crib_target_hexes = target_hexes.duplicate()
	queue_redraw()


func set_action_selection(selected_hex: int, target_hexes: Array = []) -> void:
	_action_selected_hex = selected_hex
	_action_target_hexes = target_hexes.duplicate()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if GameState.current_phase in [
		GameState.Phase.SETUP_MINI_CRIB,
		GameState.Phase.RESOLVE_CRIB,
	]:
		if not GameState.is_crib_resolver_for_control():
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var hex_index := _hex_index_at(event.position)
			if hex_index >= 0:
				hex_clicked.emit(hex_index)
				accept_event()
		return
	if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hex_index := _hex_index_at(event.position)
		if hex_index >= 0:
			hex_clicked.emit(hex_index)
			accept_event()


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
	_draw_carts(centers)
	_draw_action_highlights(centers)
	_draw_spawn_arrows(centers)


func _draw_legend() -> void:
	var panel_rect := Rect2(8.0, 8.0, 260.0, 88.0)
	draw_rect(panel_rect, Color(0.07, 0.09, 0.12, 0.88))

	var y := 22.0
	for faction in GameState.get_factions_by_rank():
		var power := int(_faction_power.get(faction, 0))
		var score := int(GameState.faction_scores.get(faction, 0))
		draw_circle(Vector2(18.0, y - 4.0), 5.0, Factions.COLORS[faction])
		draw_string(
			ThemeDB.fallback_font,
			Vector2(28, y),
			"%s | score: %d | cubes: %d" % [Factions.name_for(faction), score, power],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			LEGEND_TEXT_COLOR
		)
		y += 16.0

	var total := GameState.get_total_faction_score()
	draw_string(
		ThemeDB.fallback_font,
		Vector2(28, y),
		"%d / %d" % [total, RemixRules.ENDING_SCORE_TOTAL],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		LEGEND_TEXT_COLOR
	)


func _draw_action_highlights(centers: Array) -> void:
	for hex_index in _crib_target_hexes:
		var crib_index := int(hex_index)
		if crib_index >= 0 and crib_index < centers.size():
			_draw_hex_ring(centers[crib_index], Color(0.55, 0.85, 1.0, 0.95), 3.0)

	if _action_selected_hex >= 0 and _action_selected_hex < centers.size():
		_draw_hex_ring(centers[_action_selected_hex], Color(1.0, 0.92, 0.35, 0.95), 3.0)

	for hex_index in _action_target_hexes:
		var index := int(hex_index)
		if index >= 0 and index < centers.size():
			_draw_hex_ring(centers[index], Color(0.45, 0.95, 0.55, 0.95), 2.5)


func _draw_hex_ring(center: Vector2, color: Color, width: float) -> void:
	var points := _hex_points(center, HEX_RADIUS + 4.0)
	for i in range(points.size()):
		draw_line(points[i], points[(i + 1) % points.size()], color, width)

func _draw_bridges(centers: Array) -> void:
	for pair in HexBoard.BRIDGE_PAIRS:
		var a: int = pair[0]
		var b: int = pair[1]
		var start: Vector2 = centers[a]
		var end: Vector2 = centers[b]
		var direction := (end - start).normalized()
		var perpendicular := Vector2(-direction.y, direction.x)
		var boundary_a := _hex_boundary_point(start, end)
		var boundary_b := _hex_boundary_point(end, start)
		var gap_length := boundary_a.distance_to(boundary_b)
		var segment_half_length := gap_length * 0.11
		for segment_ratio in [0.33, 0.67]:
			var segment_center := boundary_a.lerp(boundary_b, segment_ratio)
			var segment_start := segment_center - direction * segment_half_length
			var segment_end := segment_center + direction * segment_half_length
			for offset in [-4.0, 4.0]:
				draw_line(
					segment_start + perpendicular * offset,
					segment_end + perpendicular * offset,
					BRIDGE_COLOR,
					4.0
				)


func _draw_spawn_arrows(centers: Array) -> void:
	for hex_index in HexBoard.MOUNTAIN_HEXES:
		var goal_hex: int = int(HexBoard.CART_GOALS.get(hex_index, -1))
		if goal_hex < 0 or goal_hex >= centers.size():
			continue

		var center: Vector2 = centers[hex_index]
		var goal_center: Vector2 = centers[goal_hex]
		var toward_goal := (goal_center - center).normalized()
		if toward_goal == Vector2.ZERO:
			continue

		# Place the arrow in open water on the side opposite the goal, pointing toward it.
		var water_outward := -toward_goal
		var back_edge := _hex_boundary_point(center, center + water_outward * 1000.0)
		var arrow_start := back_edge + water_outward * 26.0
		var arrow_end := arrow_start + toward_goal * 22.0
		draw_line(arrow_start, arrow_end, Color("#27ae60"), 3.0)
		_draw_arrow_head(arrow_end, toward_goal)


func _draw_colored_arrow_head(tip: Vector2, direction: Vector2, color: Color) -> void:
	var side := Vector2(-direction.y, direction.x)
	var p1 := tip - direction * 10.0 + side * 5.0
	var p2 := tip - direction * 10.0 - side * 5.0
	draw_colored_polygon(PackedVector2Array([tip, p1, p2]), color)


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


func _draw_carts(centers: Array) -> void:
	for hex_index in range(_board_state.size()):
		var hex: Dictionary = _board_state[hex_index]
		var center: Vector2 = centers[hex_index]
		var carts: Dictionary = hex.get("carts", {})
		for faction in Factions.ALL:
			var cart_origins: Array = carts.get(faction, [])
			for cart_index in range(cart_origins.size()):
				var origin_hex := int(cart_origins[cart_index])
				var goal_hex := int(HexBoard.CART_GOALS.get(origin_hex, -1))
				if goal_hex < 0 or goal_hex >= centers.size():
					continue

				var goal_center: Vector2 = centers[goal_hex]
				var toward_goal := (goal_center - center).normalized()
				if toward_goal == Vector2.ZERO:
					continue

				var side := Vector2(-toward_goal.y, toward_goal.x)
				var lane_offset := float(cart_index - float(cart_origins.size() - 1) * 0.5) * 10.0
				var arrow_start := center + toward_goal * 14.0 + side * lane_offset
				var arrow_end := center + toward_goal * 34.0 + side * lane_offset
				var color: Color = Factions.COLORS[faction]
				draw_line(arrow_start, arrow_end, color, 3.0)
				_draw_colored_arrow_head(arrow_end, toward_goal, color)


func _draw_cube_dots(center: Vector2, cubes: Dictionary) -> void:
	var dot_colors: Array = []
	for faction in Factions.ALL:
		for _cube in range(RemixRules.faction_dict_value(cubes, faction)):
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

	var label_y := _hex_top_baseline(center)
	var label_color := Color(0.05, 0.05, 0.05, 1.0)

	if labels.size() == 1:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(center.x - 20.0, label_y),
			str(labels[0]),
			HORIZONTAL_ALIGNMENT_CENTER,
			40,
			18,
			label_color
		)
		return

	draw_string(
		ThemeDB.fallback_font,
		Vector2(center.x - 26.0, label_y),
		str(labels[0]),
		HORIZONTAL_ALIGNMENT_CENTER,
		24,
		18,
		label_color
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(center.x + 2.0, label_y),
		str(labels[1]),
		HORIZONTAL_ALIGNMENT_CENTER,
		24,
		18,
		label_color
	)


func _hex_top_baseline(center: Vector2) -> float:
	return center.y - HEX_RADIUS * sqrt(3.0) * 0.5 + 18.0


func _hex_centers() -> Array:
	var bounds := HexBoard.board_pixel_bounds(HEX_RADIUS)
	var origin := Vector2(size.x * 0.5, size.y * 0.5) - bounds.get_center() + BOARD_OFFSET

	var centers: Array = []
	for hex_index in range(HexBoard.HEX_COUNT):
		centers.append(HexBoard.pixel_center(hex_index, HEX_RADIUS, origin))
	return centers


func _hex_index_at(position: Vector2) -> int:
	var centers := _hex_centers()
	var best_index := -1
	var best_distance := INF

	for hex_index in range(centers.size()):
		var center: Vector2 = centers[hex_index]
		var distance := center.distance_squared_to(position)
		if distance < best_distance:
			best_distance = distance
			best_index = hex_index

	if best_index < 0 or best_distance > (HEX_RADIUS * HEX_RADIUS):
		return -1

	return best_index


func _hex_boundary_point(center: Vector2, toward: Vector2) -> Vector2:
	var direction := (toward - center).normalized()
	if direction == Vector2.ZERO:
		return center

	var max_projection := 0.0
	for i in range(6):
		var corner := center + HexBoard.hex_corner_offset(i, HEX_RADIUS)
		max_projection = max(max_projection, (corner - center).dot(direction))

	return center + direction * max_projection


func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i in range(6):
		points.append(center + HexBoard.hex_corner_offset(i, radius))
	return points
