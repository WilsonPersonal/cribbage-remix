extends Control

const DOT_RADIUS := 5.0
const X_SPACING := 12.0
const Y_SPACING := 11.0
const COLUMNS := 10
const PLAYER_NAME_WIDTH := 88.0
const HEADER_HEIGHT := 18.0
const PLAYER_ROW_HEIGHT := 20.0
const EMPTY_ROW_HEIGHT := 16.0

const TEXT_COLOR := Color(0.96, 0.97, 0.99, 1.0)
const MUTED_TEXT_COLOR := Color(0.78, 0.8, 0.84, 1.0)


func refresh() -> void:
	custom_minimum_size.y = _content_height()
	queue_redraw()


func _content_height() -> float:
	if GameState.player_influence.is_empty():
		return EMPTY_ROW_HEIGHT

	if not _any_player_has_influence():
		return HEADER_HEIGHT + EMPTY_ROW_HEIGHT

	return HEADER_HEIGHT + float(GameState.player_influence.size()) * PLAYER_ROW_HEIGHT


func _draw() -> void:
	if GameState.player_influence.is_empty():
		_draw_line_text(Vector2.ZERO, "Influence: waiting for players...", MUTED_TEXT_COLOR)
		return

	draw_string(
		ThemeDB.fallback_font,
		Vector2.ZERO,
		"Influence:",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		TEXT_COLOR
	)

	if not _any_player_has_influence():
		_draw_line_text(Vector2(0.0, HEADER_HEIGHT), "none yet", MUTED_TEXT_COLOR)
		return

	var y := HEADER_HEIGHT
	var peer_ids: Array = GameState.player_influence.keys()
	peer_ids.sort()

	for peer_id in peer_ids:
		var player_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
		_draw_line_text(Vector2(0.0, y), player_name + ":", TEXT_COLOR)
		var influence: Dictionary = GameState.player_influence[peer_id]
		_draw_influence_cubes(Vector2(PLAYER_NAME_WIDTH, y + PLAYER_ROW_HEIGHT * 0.5), influence)
		y += PLAYER_ROW_HEIGHT


func _draw_line_text(origin: Vector2, text: String, color: Color) -> void:
	draw_string(
		ThemeDB.fallback_font,
		origin + Vector2(0.0, 12.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		color
	)


func _draw_influence_cubes(origin: Vector2, influence: Dictionary) -> void:
	var dot_colors: Array = []
	for faction in Factions.ALL:
		for _cube in range(RemixRules.faction_dict_value(influence, faction)):
			dot_colors.append(Factions.COLORS[faction])

	if dot_colors.is_empty():
		return

	var columns := mini(dot_colors.size(), COLUMNS)
	for dot_index in range(dot_colors.size()):
		var row: int = int(float(dot_index) / float(columns))
		var col := dot_index % columns
		var dots_in_row := mini(columns, dot_colors.size() - row * columns)
		var row_start_x := -float(dots_in_row - 1) * X_SPACING * 0.5
		var pos := origin + Vector2(
			row_start_x + float(col) * X_SPACING,
			-4.0 + float(row) * Y_SPACING
		)
		draw_circle(pos, DOT_RADIUS, dot_colors[dot_index])
		draw_arc(pos, DOT_RADIUS, 0.0, TAU, 16, Color(0.0, 0.0, 0.0, 0.35), 1.0)


func _any_player_has_influence() -> bool:
	for peer_id in GameState.player_influence.keys():
		var influence: Dictionary = GameState.player_influence[peer_id]
		for faction in Factions.ALL:
			if RemixRules.faction_dict_value(influence, faction) > 0:
				return true
	return false
