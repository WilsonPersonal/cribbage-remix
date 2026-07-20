extends VBoxContainer

const DOT_RADIUS := 5.0
const X_SPACING := 12.0
const Y_SPACING := 11.0
const MAX_COLUMNS := 10
const PLAYER_NAME_WIDTH := 88.0

var _crib_anim_mask: Dictionary = {}


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.x = 0


func refresh() -> void:
	for child in get_children():
		child.free()

	if GameState.player_influence.is_empty():
		_add_text_label("Influence: none yet")
		return

	_add_text_label("Influence:")
	if not _any_player_has_influence():
		_add_text_label("none yet")
		return

	var peer_ids: Array = GameState.player_influence.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		_add_player_row(int(peer_id))


func set_crib_influence_anim_mask(peer_id: int, faction_id: int) -> void:
	_crib_anim_mask = {
		"peer_id": peer_id,
		"faction_id": faction_id,
	}
	refresh()


func clear_crib_influence_anim_mask() -> void:
	_crib_anim_mask.clear()
	refresh()


func get_last_dot_global(peer_id: int) -> Vector2:
	var row := _find_row_for_peer(peer_id)
	if row == null:
		return global_position
	return row.get_last_dot_global()


func get_dot_global(peer_id: int, dot_index: int) -> Vector2:
	var row := _find_row_for_peer(peer_id)
	if row == null:
		return global_position
	return row.get_dot_global(dot_index)


func _find_row_for_peer(peer_id: int) -> InfluenceRowDots:
	for child in get_children():
		if child is HBoxContainer:
			for row_child in child.get_children():
				if row_child is InfluenceRowDots and int(row_child.peer_id) == int(peer_id):
					return row_child
	return null


func _add_text_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)


func _add_player_row(peer_id: int) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = "%s:" % GameState.player_names.get(peer_id, "Player %d" % peer_id)
	name_label.custom_minimum_size.x = PLAYER_NAME_WIDTH
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)

	var influence: Dictionary = _display_influence_for_peer(
		peer_id,
		GameState.player_influence.get(peer_id, RemixRules.empty_influence())
	)
	var dots := InfluenceRowDots.new()
	dots.setup(peer_id, influence, _content_width())
	row.add_child(dots)
	add_child(row)


func _display_influence_for_peer(peer_id: int, influence: Dictionary) -> Dictionary:
	if _crib_anim_mask.is_empty() or int(_crib_anim_mask.get("peer_id", -1)) != int(peer_id):
		return influence

	var display := RemixRules.normalize_faction_dict(influence)
	var faction_id: int = _crib_anim_mask.get("faction_id", -1)
	display[faction_id] = maxi(0, RemixRules.faction_dict_value(display, faction_id) - 1)
	return display


func _content_width() -> float:
	if size.x > 1.0:
		return size.x

	var parent_control := get_parent_control()
	if parent_control:
		return maxf(parent_control.size.x, 1.0)

	return 1.0


func _any_player_has_influence() -> bool:
	for check_peer_id in GameState.player_influence.keys():
		var influence: Dictionary = GameState.player_influence[check_peer_id]
		for faction in Factions.ALL:
			if RemixRules.faction_dict_value(influence, faction) > 0:
				return true
	return false


class InfluenceRowDots extends Control:
	var peer_id: int = -1

	var _influence: Dictionary = {}
	var _columns: int = 1


	func setup(target_peer_id: int, influence: Dictionary, available_width: float) -> void:
		peer_id = target_peer_id
		_influence = influence
		_columns = _max_columns_for_width(available_width - PLAYER_NAME_WIDTH)
		custom_minimum_size.y = _row_height()
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		queue_redraw()


	func get_last_dot_global() -> Vector2:
		var dot_count := _dot_count()
		if dot_count <= 0:
			return global_position + Vector2(DOT_RADIUS, DOT_RADIUS)
		return get_dot_global(dot_count - 1)


	func get_dot_global(dot_index: int) -> Vector2:
		return global_position + _dot_local_position(dot_index)


	func _dot_count() -> int:
		var total := 0
		for faction in Factions.ALL:
			total += RemixRules.faction_dict_value(_influence, faction)
		return total


	func _row_height() -> float:
		var dot_count := _dot_count()
		if dot_count <= 0:
			return DOT_RADIUS * 2.0
		var columns := mini(dot_count, _columns)
		var rows := int(ceil(float(dot_count) / float(columns)))
		return maxf(DOT_RADIUS * 2.0, DOT_RADIUS * 2.0 + float(rows - 1) * Y_SPACING)


	func _max_columns_for_width(content_width: float) -> int:
		var available := maxf(content_width, X_SPACING)
		return clampi(int(floor(available / X_SPACING)), 1, MAX_COLUMNS)


	func _dot_local_position(dot_index: int) -> Vector2:
		var dot_colors := _dot_colors()
		if dot_index < 0 or dot_index >= dot_colors.size():
			return Vector2(DOT_RADIUS, DOT_RADIUS)

		var columns := maxi(1, mini(_columns, dot_colors.size()))
		var row: int = int(float(dot_index) / float(columns))
		var col := dot_index % columns
		var dots_in_row := mini(columns, dot_colors.size() - row * columns)
		var row_start_x := -float(dots_in_row - 1) * X_SPACING * 0.5
		return Vector2(
			DOT_RADIUS + row_start_x + float(col) * X_SPACING,
			DOT_RADIUS + float(row) * Y_SPACING
		)


	func _dot_colors() -> Array:
		var dot_colors: Array = []
		for faction in Factions.ALL:
			for _cube in range(RemixRules.faction_dict_value(_influence, faction)):
				dot_colors.append(Factions.COLORS[faction])
		return dot_colors


	func _draw() -> void:
		var dot_colors := _dot_colors()
		if dot_colors.is_empty():
			return

		var columns := maxi(1, mini(_columns, dot_colors.size()))
		for dot_index in range(dot_colors.size()):
			var pos := _dot_local_position(dot_index)
			draw_circle(pos, DOT_RADIUS, dot_colors[dot_index])
			draw_arc(pos, DOT_RADIUS, 0.0, TAU, 16, Color(0.0, 0.0, 0.0, 0.35), 1.0)
