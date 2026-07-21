extends Control

signal hex_clicked(hex_index: int)

const HEX_RADIUS := 62.0
const BOARD_OFFSET := Vector2(-60.0, 0.0)

const TERRAIN_COLORS := {
	HexBoard.Terrain.MOUNTAIN: Color("#8a9098"),
	HexBoard.Terrain.FOREST: Color("#3f7a43"),
	HexBoard.Terrain.PASTURE: Color("#b8c86a"),
}

const WATER_COLOR := Color("#4a8ec4")
const BRIDGE_COLOR := Color("#7a5236")
const LEGEND_TEXT_COLOR := Color(0.96, 0.97, 0.99, 1.0)
const LEGEND_PANEL_RECT := Rect2(8.0, 8.0, 260.0, 88.0)
const LEGEND_ROW_START_Y := 22.0
const LEGEND_ROW_STEP := 16.0
const LEGEND_TOTAL_SCORE_Y := LEGEND_ROW_START_Y + LEGEND_ROW_STEP * 3.0 + 4.0

var _board_state: Array = []
var _faction_power: Dictionary = {}
var _action_selected_hex: int = -1
var _action_target_hexes: Array = []
var _shop_dominance_hexes: Array = []
var _shop_dominance_faction: int = -1
var _crib_target_hexes: Array = []
var _crib_anim_mask: Dictionary = {}
var _action_anim_mask: Dictionary = {}
var _action_cart_anim_mask: Dictionary = {}
var _legend_row_y: Dictionary = {}
var _legend_row_glow: Dictionary = {}
var _legend_panel_flash: float = 0.0
var _rank_banner_alpha: float = 0.0
var _rank_banner_text: String = ""
var _rank_banner_color: Color = Color.WHITE
var _legend_animating: bool = false
var _legend_layout_generation: int = 0
var _last_faction_scores: Dictionary = {}
var _score_popup_count: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	GameState.board_updated.connect(_on_board_updated)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.faction_score_scored.connect(_on_faction_score_scored)
	GameState.faction_scores_updated.connect(_on_faction_scores_updated)
	_last_faction_scores = _duplicate_faction_scores(GameState.faction_scores)
	_init_legend_layout()
	if GameState.get_board_state().size() > 0:
		_on_board_updated(GameState.get_board_state(), GameState.get_faction_power())


func _on_phase_changed(_phase: GameState.Phase) -> void:
	clear_action_selection()
	clear_crib_selection()
	clear_shop_dominance_highlights()


func clear_action_selection() -> void:
	_action_selected_hex = -1
	_action_target_hexes.clear()
	queue_redraw()


func clear_crib_selection() -> void:
	_crib_target_hexes.clear()
	queue_redraw()


func set_crib_cube_anim_mask(hex_index: int, faction_id: int) -> void:
	_crib_anim_mask = {
		"hex_index": hex_index,
		"faction_id": faction_id,
	}
	queue_redraw()


func clear_crib_cube_anim_mask() -> void:
	_crib_anim_mask.clear()
	queue_redraw()


func set_action_cube_anim_mask(from_hex: int, to_hex: int, faction_id: int, move_count: int) -> void:
	_action_anim_mask = {
		"from_hex": from_hex,
		"to_hex": to_hex,
		"faction_id": faction_id,
		"move_count": move_count,
		"revealed_count": 0,
	}
	queue_redraw()


func reveal_action_cube_at_destination() -> void:
	if _action_anim_mask.is_empty():
		return

	var move_count: int = int(_action_anim_mask.get("move_count", 0))
	var revealed_count: int = int(_action_anim_mask.get("revealed_count", 0))
	_action_anim_mask["revealed_count"] = mini(revealed_count + 1, move_count)
	queue_redraw()


func clear_action_cube_anim_mask() -> void:
	_action_anim_mask.clear()
	_sync_board_state_from_game()
	queue_redraw()


func set_action_cart_anim_mask(
	from_hex: int,
	to_hex: int,
	faction_id: int,
	origin_hex: int
) -> void:
	_action_cart_anim_mask = {
		"from_hex": from_hex,
		"to_hex": to_hex,
		"faction_id": faction_id,
		"origin_hex": origin_hex,
		"revealed": false,
	}
	queue_redraw()


func reveal_action_cart_at_destination() -> void:
	if _action_cart_anim_mask.is_empty():
		return
	_action_cart_anim_mask["revealed"] = true
	queue_redraw()


func clear_action_cart_anim_mask() -> void:
	_action_cart_anim_mask.clear()
	_sync_board_state_from_game()
	queue_redraw()


func _should_hide_cart(
	hex_index: int,
	faction_id: int,
	origin_hex: int
) -> bool:
	if _action_cart_anim_mask.is_empty():
		return false

	var mask_faction: int = int(_action_cart_anim_mask.get("faction_id", -1))
	var mask_origin: int = int(_action_cart_anim_mask.get("origin_hex", -1))
	if faction_id != mask_faction or origin_hex != mask_origin:
		return false

	if hex_index == int(_action_cart_anim_mask.get("from_hex", -1)):
		return true

	if (
		hex_index == int(_action_cart_anim_mask.get("to_hex", -1))
		and not bool(_action_cart_anim_mask.get("revealed", false))
	):
		return true

	return false


func _sync_board_state_from_game() -> void:
	var board_state: Array = GameState.get_board_state()
	if board_state.is_empty():
		return
	_board_state = board_state


func _display_cubes_for_hex(hex_index: int, cubes: Dictionary) -> Dictionary:
	var display := _duplicate_cubes(cubes)

	if (
		not _crib_anim_mask.is_empty()
		and int(_crib_anim_mask.get("hex_index", -1)) == hex_index
	):
		var crib_faction_id: int = _crib_anim_mask.get("faction_id", -1)
		display[crib_faction_id] = maxi(
			0,
			RemixRules.faction_dict_value(display, crib_faction_id) - 1
		)

	if (
		not _action_anim_mask.is_empty()
		and int(_action_anim_mask.get("to_hex", -1)) == hex_index
	):
		var action_faction_id: int = _action_anim_mask.get("faction_id", -1)
		var move_count: int = int(_action_anim_mask.get("move_count", 1))
		var revealed_count: int = int(_action_anim_mask.get("revealed_count", 0))
		var hidden_count: int = maxi(0, move_count - revealed_count)
		display[action_faction_id] = maxi(
			0,
			RemixRules.faction_dict_value(display, action_faction_id) - hidden_count
		)

	return display


func set_crib_selection(target_hexes: Array) -> void:
	_crib_target_hexes = target_hexes.duplicate()
	queue_redraw()


func set_action_selection(selected_hex: int, target_hexes: Array = []) -> void:
	_action_selected_hex = selected_hex
	_action_target_hexes = target_hexes.duplicate()
	queue_redraw()


func set_shop_dominance_highlights(hexes: Array, faction_id: int) -> void:
	_shop_dominance_hexes = hexes.duplicate()
	_shop_dominance_faction = faction_id
	queue_redraw()


func clear_shop_dominance_highlights() -> void:
	_shop_dominance_hexes.clear()
	_shop_dominance_faction = -1
	queue_redraw()


func _is_point_over_shop(local_point: Vector2) -> bool:
	var game := get_parent()
	if game == null or not game.has_method("get_shop_panel_global_rect"):
		return false
	var global_point := get_global_transform() * local_point
	return game.get_shop_panel_global_rect().has_point(global_point)


func _has_point(point: Vector2) -> bool:
	if _is_point_over_shop(point):
		return false
	return Rect2(Vector2.ZERO, size).has_point(point)


func _gui_input(event: InputEvent) -> void:
	if _is_point_over_shop(get_local_mouse_position()):
		return
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


func _on_faction_scores_updated(scores: Dictionary) -> void:
	var scores_decreased := _faction_scores_decreased(scores)
	_last_faction_scores = _duplicate_faction_scores(scores)

	if scores_decreased:
		_cancel_legend_animations()
		_reset_legend_visual_effects()

	if _legend_animating and not scores_decreased:
		return

	_sync_legend_layout(false, false)


func _duplicate_faction_scores(scores: Dictionary) -> Dictionary:
	var copy := {}
	for faction in Factions.ALL:
		copy[faction] = int(scores.get(faction, 0))
	return copy


func _faction_scores_decreased(scores: Dictionary) -> bool:
	for faction in Factions.ALL:
		if int(scores.get(faction, 0)) < int(_last_faction_scores.get(faction, 0)):
			return true
	return false


func _cancel_legend_animations() -> void:
	_legend_layout_generation += 1
	_legend_animating = false


func _reset_legend_visual_effects() -> void:
	_legend_panel_flash = 0.0
	_rank_banner_alpha = 0.0
	_rank_banner_text = ""
	for faction in Factions.ALL:
		_legend_row_glow[faction] = 0.0


func _on_faction_score_scored(
	faction_id: int,
	points: int,
	old_rank: int,
	new_rank: int
) -> void:
	_pulse_legend_row(faction_id)
	_show_faction_score_popup(faction_id, points)

	var rank_changed := new_rank != old_rank
	if rank_changed:
		_legend_panel_flash = 1.0
		var flash_tween := create_tween()
		flash_tween.tween_method(
			func(strength: float) -> void:
				_legend_panel_flash = strength
				queue_redraw(),
			1.0,
			0.0,
			0.9
		)
		_show_rank_change_banner(faction_id, new_rank)
		_sync_legend_layout(true, true)
	else:
		queue_redraw()


func _init_legend_layout() -> void:
	for faction in Factions.ALL:
		_legend_row_y[faction] = LEGEND_ROW_START_Y
		_legend_row_glow[faction] = 0.0
	_sync_legend_layout(false, false)


func _sync_legend_layout(animate: bool, dramatic: bool) -> void:
	if not animate:
		_cancel_legend_animations()

	var ranked := GameState.get_factions_by_rank()
	var layout_generation := _legend_layout_generation
	_legend_animating = animate

	for rank_index in range(ranked.size()):
		var faction: int = ranked[rank_index]
		var target_y := LEGEND_ROW_START_Y + float(rank_index) * LEGEND_ROW_STEP
		if not animate:
			_legend_row_y[faction] = target_y
			continue
		_tween_legend_row(faction, target_y, dramatic, layout_generation)

	if animate:
		var finish_delay := 0.95 if dramatic else 0.5
		var tween := create_tween()
		tween.tween_interval(finish_delay)
		tween.tween_callback(func() -> void:
			if layout_generation != _legend_layout_generation:
				return
			_legend_animating = false
		)

	queue_redraw()


func _tween_legend_row(
	faction_id: int,
	target_y: float,
	dramatic: bool,
	layout_generation: int
) -> void:
	var start_y: float = float(_legend_row_y.get(faction_id, target_y))
	if is_equal_approx(start_y, target_y):
		_legend_row_y[faction_id] = target_y
		queue_redraw()
		return

	var tween := create_tween()
	if dramatic:
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(y: float) -> void:
			if layout_generation != _legend_layout_generation:
				return
			_legend_row_y[faction_id] = y
			queue_redraw(),
		start_y,
		target_y,
		0.95 if dramatic else 0.5
	)


func _pulse_legend_row(faction_id: int) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(strength: float) -> void:
			_legend_row_glow[faction_id] = strength
			queue_redraw(),
		0.0,
		1.0,
		0.12
	)
	tween.tween_method(
		func(strength: float) -> void:
			_legend_row_glow[faction_id] = strength
			queue_redraw(),
		1.0,
		0.0,
		0.75
	)


func _show_rank_change_banner(faction_id: int, new_rank: int) -> void:
	var rank_labels: Array[String] = ["1st", "2nd", "3rd"]
	var rank_label: String = rank_labels[clampi(new_rank, 0, rank_labels.size() - 1)]
	if new_rank == 0:
		_rank_banner_text = "%s takes the lead!" % Factions.name_for(faction_id)
	else:
		_rank_banner_text = "%s moves to %s place!" % [Factions.name_for(faction_id), rank_label]
	_rank_banner_color = Factions.COLORS[faction_id]
	_rank_banner_alpha = 0.0

	var tween := create_tween()
	tween.tween_method(
		func(alpha: float) -> void:
			_rank_banner_alpha = alpha
			queue_redraw(),
		0.0,
		1.0,
		0.18
	)
	tween.tween_interval(1.35)
	tween.tween_method(
		func(alpha: float) -> void:
			_rank_banner_alpha = alpha
			queue_redraw(),
		1.0,
		0.0,
		0.45
	)


func _show_faction_score_popup(faction_id: int, points: int) -> void:
	var popup := Label.new()
	popup.text = "%s: +%d" % [Factions.name_for(faction_id), points]
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	popup.autowrap_mode = TextServer.AUTOWRAP_OFF
	popup.add_theme_font_size_override("font_size", 24)
	var faction_color: Color = Factions.COLORS[faction_id]
	popup.add_theme_color_override(
		"font_color",
		faction_color.lightened(0.45) if faction_id != Factions.Id.CLUBS else Color(0.92, 0.94, 0.98)
	)
	popup.modulate.a = 0.0
	popup.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	popup.offset_left = LEGEND_PANEL_RECT.position.x
	popup.offset_right = LEGEND_PANEL_RECT.end.x
	var start_top := LEGEND_PANEL_RECT.end.y + 8.0 + float(_score_popup_count * 28.0)
	popup.offset_top = start_top
	popup.offset_bottom = start_top + 26.0
	popup.z_index = 30
	add_child(popup)
	_score_popup_count += 1

	var start_y := popup.offset_top
	var tween := popup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "modulate:a", 1.0, 0.12)
	tween.tween_property(popup, "offset_top", start_y - 22.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(popup, "offset_bottom", start_y - 22.0 + 26.0, 0.85).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_property(popup, "modulate:a", 0.0, 0.25).set_delay(0.45)
	tween.tween_callback(func() -> void:
		popup.queue_free()
		_score_popup_count = maxi(0, _score_popup_count - 1)
	)


func _legend_draw_order() -> Array:
	var factions := Factions.ALL.duplicate()
	factions.sort_custom(func(a: int, b: int) -> bool:
		var y_a: float = float(_legend_row_y.get(a, LEGEND_ROW_START_Y))
		var y_b: float = float(_legend_row_y.get(b, LEGEND_ROW_START_Y))
		if is_equal_approx(y_a, y_b):
			return a < b
		return y_a < y_b
	)
	return factions


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
	var panel_color := Color(0.07, 0.09, 0.12, 0.88)
	if _legend_panel_flash > 0.0:
		panel_color = panel_color.lerp(Color(0.95, 0.82, 0.28, 0.95), _legend_panel_flash * 0.55)
	draw_rect(LEGEND_PANEL_RECT, panel_color)

	if _legend_panel_flash > 0.0:
		draw_rect(
			LEGEND_PANEL_RECT.grow(3.0),
			Color(1.0, 0.88, 0.35, _legend_panel_flash * 0.45),
			false,
			3.0
		)

	for faction in _legend_draw_order():
		var y: float = float(_legend_row_y.get(faction, LEGEND_ROW_START_Y))
		var power := int(_faction_power.get(faction, 0))
		var score := int(GameState.faction_scores.get(faction, 0))
		var glow: float = float(_legend_row_glow.get(faction, 0.0))

		if glow > 0.0:
			var glow_rect := Rect2(12.0, y - 13.0, 236.0, 15.0)
			draw_rect(glow_rect, Factions.COLORS[faction].lightened(0.2), false, 1.5)
			draw_rect(
				glow_rect,
				Color(1.0, 0.92, 0.45, 0.18 + glow * 0.35)
			)

		var dot_color: Color = Factions.COLORS[faction]
		if glow > 0.0:
			dot_color = dot_color.lightened(0.25 + glow * 0.2)
		var dot_radius := 5.0 + glow * 2.5
		Factions.draw_cube(self, Vector2(18.0, y - 4.0), dot_radius, dot_color)

		var text_color := LEGEND_TEXT_COLOR
		if glow > 0.0:
			text_color = text_color.lerp(Color(1.0, 0.94, 0.55), glow * 0.85)

		draw_string(
			ThemeDB.fallback_font,
			Vector2(28, y),
			"%s | score: %d | cubes: %d" % [Factions.name_for(faction), score, power],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			text_color
		)

	var total := GameState.get_total_faction_score()
	draw_string(
		ThemeDB.fallback_font,
		Vector2(28, LEGEND_TOTAL_SCORE_Y),
		"%d / %d" % [total, RemixRules.ENDING_SCORE_TOTAL],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		13,
		LEGEND_TEXT_COLOR
	)

	if _rank_banner_alpha > 0.0 and not _rank_banner_text.is_empty():
		var banner_pos := Vector2(LEGEND_PANEL_RECT.position.x + 8.0, LEGEND_PANEL_RECT.end.y + 18.0)
		var banner_color := _rank_banner_color.lightened(0.35)
		banner_color.a = _rank_banner_alpha
		draw_string(
			ThemeDB.fallback_font,
			banner_pos,
			_rank_banner_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			20,
			banner_color
		)


func _draw_action_highlights(centers: Array) -> void:
	for hex_index in _shop_dominance_hexes:
		var dominance_index := int(hex_index)
		if dominance_index >= 0 and dominance_index < centers.size():
			var ring_color: Color = Factions.COLORS.get(_shop_dominance_faction, Color.WHITE)
			ring_color.a = 0.95
			_draw_hex_ring(centers[dominance_index], ring_color.lightened(0.2), 3.0)

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
	_draw_cube_dots(center, _display_cubes_for_hex(hex_index, hex.get("cubes", {})))


func _draw_carts(centers: Array) -> void:
	for hex_index in range(_board_state.size()):
		var hex: Dictionary = _board_state[hex_index]
		var center: Vector2 = centers[hex_index]
		var carts: Dictionary = hex.get("carts", {})
		var entries: Array = _sorted_cart_entries(_cart_entries_for_hex(hex_index, carts))
		for entry_index in range(entries.size()):
			var entry: Dictionary = entries[entry_index]
			var faction: int = int(entry.get("faction", -1))
			var origin_hex := int(entry.get("origin_hex", -1))
			if _should_hide_cart(hex_index, faction, origin_hex):
				continue

			var arrow := _cart_arrow_geometry(
				hex_index,
				center,
				centers,
				origin_hex,
				entries.size(),
				entry_index
			)
			if arrow.is_empty():
				continue

			var color: Color = Factions.COLORS[faction]
			draw_line(arrow.start, arrow.end, color, 3.0)
			_draw_colored_arrow_head(arrow.end, arrow.toward_goal, color)


const CART_LANE_SPACING := 10.0


func _cart_entries_for_hex(hex_index: int, carts: Dictionary) -> Array:
	var entries: Array = []
	for faction in Factions.ALL:
		var cart_origins: Array = carts.get(faction, [])
		for cart_index in range(cart_origins.size()):
			entries.append({
				"faction": faction,
				"origin_hex": int(cart_origins[cart_index]),
				"faction_cart_index": cart_index,
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


func _cart_lane_offset(total_carts: int, global_index: int) -> float:
	return float(global_index - float(total_carts - 1) * 0.5) * CART_LANE_SPACING


func _cart_arrow_geometry(
	current_hex: int,
	hex_center: Vector2,
	centers: Array,
	origin_hex: int,
	total_carts: int,
	global_index: int
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

	var side := Vector2(-toward_goal.y, toward_goal.x)
	var lane_offset := _cart_lane_offset(total_carts, global_index)
	var arrow_start := hex_center + toward_goal * 14.0 + side * lane_offset
	var arrow_end := hex_center + toward_goal * 34.0 + side * lane_offset
	return {
		"start": arrow_start,
		"end": arrow_end,
		"toward_goal": toward_goal,
		"midpoint": (arrow_start + arrow_end) * 0.5,
	}


func _authoritative_carts_for_hex(hex_index: int) -> Dictionary:
	var board_state: Array = GameState.get_board_state()
	if hex_index >= 0 and hex_index < board_state.size():
		return board_state[hex_index].get("carts", {})
	if hex_index >= 0 and hex_index < _board_state.size():
		return _board_state[hex_index].get("carts", {})
	return {}


func _cart_entries_with_virtual(
	hex_index: int,
	faction_id: int,
	origin_hex: int,
	include_virtual: bool
) -> Array:
	var entries: Array = _cart_entries_for_hex(hex_index, _authoritative_carts_for_hex(hex_index))
	if not include_virtual:
		return _sorted_cart_entries(entries)

	for entry in entries:
		if int(entry.get("faction", -1)) == faction_id and int(entry.get("origin_hex", -1)) == origin_hex:
			return _sorted_cart_entries(entries)

	entries.append({
		"faction": faction_id,
		"origin_hex": origin_hex,
		"faction_cart_index": 0,
	})
	return _sorted_cart_entries(entries)


func _cart_entry_global_index(entries: Array, faction_id: int, origin_hex: int) -> int:
	for entry_index in range(entries.size()):
		var entry: Dictionary = entries[entry_index]
		if int(entry.get("faction", -1)) == faction_id and int(entry.get("origin_hex", -1)) == origin_hex:
			return entry_index
	return maxi(entries.size() - 1, 0)


func get_cart_arrow_global_midpoint(
	hex_index: int,
	faction_id: int,
	origin_hex: int,
	include_virtual: bool = false
) -> Vector2:
	if hex_index < 0:
		return global_position

	var centers := _hex_centers()
	if hex_index >= centers.size():
		return global_position

	var entries: Array = _cart_entries_with_virtual(hex_index, faction_id, origin_hex, include_virtual)
	var entry_index := _cart_entry_global_index(entries, faction_id, origin_hex)
	var arrow := _cart_arrow_geometry(
		hex_index,
		centers[hex_index],
		centers,
		origin_hex,
		entries.size(),
		entry_index
	)
	if arrow.is_empty():
		return global_position + centers[hex_index]
	return global_position + arrow.midpoint


func get_cart_arrow_global_direction(hex_index: int, origin_hex: int) -> Vector2:
	if hex_index < 0:
		return Vector2.RIGHT

	var centers := _hex_centers()
	if hex_index >= centers.size():
		return Vector2.RIGHT

	var goal_hex := int(HexBoard.CART_GOALS.get(origin_hex, -1))
	if goal_hex < 0 or goal_hex >= centers.size():
		return Vector2.RIGHT

	var next_hex := HexBoard.next_cart_path_hex(origin_hex, hex_index)
	if next_hex < 0:
		next_hex = goal_hex

	var toward_goal: Vector2 = (centers[next_hex] - centers[hex_index]).normalized()
	if toward_goal == Vector2.ZERO:
		return Vector2.RIGHT
	return toward_goal


func _draw_cube_dots(center: Vector2, cubes: Dictionary) -> void:
	var dot_colors := _cube_dot_colors(cubes)
	if dot_colors.is_empty():
		return

	for dot_index in range(dot_colors.size()):
		var pos := _cube_dot_local_pos(center, dot_colors.size(), dot_index)
		Factions.draw_cube(self, pos, CUBE_DOT_RADIUS, dot_colors[dot_index])


const CUBE_DOT_RADIUS := 4.5
const CUBE_X_SPACING := 11.0
const CUBE_Y_SPACING := 10.0
const CUBE_MAX_COLUMNS := 5


func _cube_dot_colors(cubes: Dictionary) -> Array:
	var dot_colors: Array = []
	for faction in Factions.ALL:
		for _cube in range(RemixRules.faction_dict_value(cubes, faction)):
			dot_colors.append(Factions.COLORS[faction])
	return dot_colors


func _cube_dot_local_pos(hex_center: Vector2, dot_count: int, dot_index: int) -> Vector2:
	if dot_count <= 0 or dot_index < 0 or dot_index >= dot_count:
		return hex_center

	var columns := mini(dot_count, CUBE_MAX_COLUMNS)
	var row: int = int(float(dot_index) / float(columns))
	var col := dot_index % columns
	var dots_in_row := mini(columns, dot_count - row * columns)
	var row_start_x := -float(dots_in_row - 1) * CUBE_X_SPACING * 0.5
	return hex_center + Vector2(
		row_start_x + float(col) * CUBE_X_SPACING,
		8.0 + float(row) * CUBE_Y_SPACING
	)


func _duplicate_cubes(cubes: Dictionary) -> Dictionary:
	var copy := RemixRules.empty_influence()
	for faction in Factions.ALL:
		copy[faction] = RemixRules.faction_dict_value(cubes, faction)
	return copy


func _last_faction_dot_index(cubes: Dictionary, faction_id: int) -> int:
	var index := 0
	var last_index := -1
	for faction in Factions.ALL:
		var count := RemixRules.faction_dict_value(cubes, faction)
		for _i in range(count):
			if faction == faction_id:
				last_index = index
			index += 1
	return last_index


func get_last_faction_cube_dot_global(hex_index: int, faction_id: int) -> Vector2:
	return _get_faction_cube_dot_global(hex_index, faction_id, 0)


func get_faction_cube_dot_global_after_add(hex_index: int, faction_id: int) -> Vector2:
	return _get_faction_cube_dot_global(hex_index, faction_id, 1)


func get_faction_cube_dot_global_before_remove(hex_index: int, faction_id: int) -> Vector2:
	return _get_faction_cube_dot_global(hex_index, faction_id, -1)


func _get_faction_cube_dot_global(hex_index: int, faction_id: int, count_delta: int) -> Vector2:
	if hex_index < 0:
		return global_position

	var centers := _hex_centers()
	if hex_index >= centers.size():
		return global_position

	var hex_center: Vector2 = centers[hex_index]
	var cubes: Dictionary = _duplicate_cubes(_authoritative_cubes_for_hex(hex_index))
	cubes[faction_id] = maxi(0, RemixRules.faction_dict_value(cubes, faction_id) + count_delta)
	var dot_index := _last_faction_dot_index(cubes, faction_id)
	if dot_index < 0:
		return global_position + hex_center

	var dot_colors := _cube_dot_colors(cubes)
	return global_position + _cube_dot_local_pos(hex_center, dot_colors.size(), dot_index)


func _faction_cube_overall_index(cubes: Dictionary, faction_id: int, faction_cube_index: int) -> int:
	var overall_index := 0
	for faction in Factions.ALL:
		var count := RemixRules.faction_dict_value(cubes, faction)
		if faction == faction_id:
			return overall_index + clampi(faction_cube_index, 0, maxi(count - 1, 0))
		overall_index += count
	return overall_index


func get_faction_cube_dot_global_at_index(hex_index: int, faction_id: int, faction_cube_index: int) -> Vector2:
	return _get_faction_cube_dot_global_for_cubes(hex_index, faction_id, faction_cube_index, 0)


func get_faction_cube_dot_global_at_index_with_extra(
	hex_index: int,
	faction_id: int,
	faction_cube_index: int,
	extra_count: int
) -> Vector2:
	return _get_faction_cube_dot_global_for_cubes(hex_index, faction_id, faction_cube_index, extra_count)


func _get_faction_cube_dot_global_for_cubes(
	hex_index: int,
	faction_id: int,
	faction_cube_index: int,
	extra_count: int
) -> Vector2:
	if hex_index < 0:
		return global_position

	var centers := _hex_centers()
	if hex_index >= centers.size():
		return global_position

	var hex_center: Vector2 = centers[hex_index]
	var cubes: Dictionary = _duplicate_cubes(_authoritative_cubes_for_hex(hex_index))
	cubes[faction_id] = maxi(0, RemixRules.faction_dict_value(cubes, faction_id) + extra_count)
	var overall_index := _faction_cube_overall_index(cubes, faction_id, faction_cube_index)
	var dot_colors := _cube_dot_colors(cubes)
	if overall_index < 0 or overall_index >= dot_colors.size():
		return global_position + hex_center
	return global_position + _cube_dot_local_pos(hex_center, dot_colors.size(), overall_index)


func _authoritative_cubes_for_hex(hex_index: int) -> Dictionary:
	var board_state: Array = GameState.get_board_state()
	if hex_index >= 0 and hex_index < board_state.size():
		return board_state[hex_index].get("cubes", {})
	if hex_index >= 0 and hex_index < _board_state.size():
		return _board_state[hex_index].get("cubes", {})
	return RemixRules.empty_influence()


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
