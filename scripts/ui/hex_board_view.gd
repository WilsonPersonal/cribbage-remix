extends Control

const HEX_RADIUS := 42.0

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
	_draw_legend()
	if _board_state.is_empty():
		return
	_draw_hex_map()


func _draw_legend() -> void:
	var y := 24.0
	draw_string(
		ThemeDB.fallback_font,
		Vector2(20, y),
		"West -> East carts | Reject rank 1-9 -> matching hex | 10 -> any hex",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color.WHITE
	)
	y += 20.0

	for faction in Factions.ALL:
		var power := int(_faction_power.get(faction, 0))
		var score := int(GameState.faction_scores.get(faction, 0))
		draw_string(
			ThemeDB.fallback_font,
			Vector2(20, y),
			"%s | cubes: %d | score: %d" % [Factions.name_for(faction), power, score],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Factions.COLORS[faction]
		)
		y += 18.0


func _draw_hex_map() -> void:
	var centers := _hex_centers()
	for hex_index in range(HexBoard.HEX_COUNT):
		_draw_hex(centers[hex_index], hex_index)


func _draw_hex(center: Vector2, hex_index: int) -> void:
	var points := _hex_points(center, HEX_RADIUS)
	var fill := Color(0.18, 0.22, 0.28, 1.0)

	if hex_index in HexBoard.WEST_HEXES:
		fill = Color(0.14, 0.2, 0.26, 1.0)
	elif hex_index in HexBoard.EAST_HEXES:
		fill = Color(0.22, 0.2, 0.14, 1.0)

	draw_colored_polygon(points, fill)
	for i in range(points.size()):
		draw_line(points[i], points[(i + 1) % points.size()], Color(0.35, 0.4, 0.48, 1.0), 2.0)

	var hex_label := str(HexBoard.hex_number(hex_index))
	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(-8, 4),
		hex_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		16,
		Color(0.92, 0.94, 0.98, 1.0)
	)

	if hex_index >= _board_state.size():
		return

	var hex: Dictionary = _board_state[hex_index]
	var cubes: Dictionary = hex.get("cubes", {})
	var carts: Dictionary = hex.get("carts", {})
	var cube_offset := Vector2(-18, 14)

	for faction in Factions.ALL:
		var cube_count := int(cubes.get(faction, 0))
		for cube in range(cube_count):
			draw_circle(center + cube_offset + Vector2(cube * 12, 0), 5.0, Factions.COLORS[faction])

		var cart_count := int(carts.get(faction, 0))
		for cart in range(cart_count):
			var cart_pos := center + Vector2(-10 + cart * 14, 24)
			draw_rect(Rect2(cart_pos, Vector2(10, 8)), Factions.COLORS[faction], false, 2.0)


func _hex_centers() -> Array:
	var origin := Vector2(size.x * 0.5 - 120.0, size.y * 0.5 - 40.0)
	var horizontal := HEX_RADIUS * 1.75
	var vertical := HEX_RADIUS * 1.5
	return [
		origin + Vector2(horizontal, 0),
		origin + Vector2(0, vertical),
		origin + Vector2(horizontal, vertical),
		origin + Vector2(0, vertical * 2.0),
		origin + Vector2(horizontal, vertical * 2.0),
		origin + Vector2(horizontal * 2.0, vertical * 2.0),
		origin + Vector2(0, vertical * 3.0),
		origin + Vector2(horizontal, vertical * 3.0),
		origin + Vector2(horizontal * 2.0, vertical * 3.0),
	]


func _hex_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = []
	for i in range(6):
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points
