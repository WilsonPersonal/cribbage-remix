extends Control

signal panel_closed

const PANEL_BG_COLOR := Color(0.1, 0.12, 0.16, 0.98)
const PANEL_BORDER_COLOR := Color(0.45, 0.55, 0.72, 0.55)
const HexBoardMiniView := preload("res://scripts/ui/hex_board_mini_view.gd")
const PowerRating := preload("res://scripts/ai/faction_power_rating.gd")
const MoveGenerator := preload("res://scripts/ai/ai_move_generator.gd")

@onready var _panel: PanelContainer = $Panel
@onready var _list_container: VBoxContainer = $Panel/Margin/VBox/Body/ListScroll/ListVBox
@onready var _map_row: HBoxContainer = $Panel/Margin/VBox/Body/DetailScroll/DetailVBox/MapRow
@onready var _before_map: HexBoardMiniView = $Panel/Margin/VBox/Body/DetailScroll/DetailVBox/MapRow/BeforeColumn/BeforeMap
@onready var _after_map: HexBoardMiniView = $Panel/Margin/VBox/Body/DetailScroll/DetailVBox/MapRow/AfterColumn/AfterMap
@onready var _influence_label: Label = $Panel/Margin/VBox/Body/DetailScroll/DetailVBox/InfluenceDiff
@onready var _detail_label: Label = $Panel/Margin/VBox/Body/DetailScroll/DetailVBox/DetailLabel
@onready var _summary_label: Label = $Panel/Margin/VBox/SummaryLabel
@onready var _close_button: Button = $Panel/Margin/VBox/Header/CloseButton

var _selected_entry_id: int = -1


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_panel_style()
	_close_button.pressed.connect(hide_panel)
	$Backdrop.gui_input.connect(_on_backdrop_gui_input)
	AiController.action_logged.connect(_on_action_logged)
	AiController.history_cleared.connect(_on_history_cleared)
	_summary_label.text = "No AI actions recorded yet."


func show_panel() -> void:
	z_as_relative = false
	z_index = 50
	var game := get_parent()
	if game is Control:
		game.move_child(self, game.get_child_count() - 1)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	_rebuild_list()
	_update_detail()


func hide_panel() -> void:
	if not visible:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_closed.emit()


func _apply_panel_style() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG_COLOR
	panel_style.border_color = PANEL_BORDER_COLOR
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", panel_style)


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide_panel()


func _on_action_logged(_entry: Dictionary) -> void:
	if visible:
		_rebuild_list()
		_update_detail()
	else:
		_summary_label.text = "%d AI action(s) recorded. Open history to inspect." % AiController.get_action_history().size()


func _on_history_cleared() -> void:
	_selected_entry_id = -1
	if visible:
		_rebuild_list()
	_update_detail()


func _rebuild_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()

	var history: Array = AiController.get_action_history()
	if history.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No actions yet this game."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_container.add_child(empty_label)
		return

	for entry in history:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = _format_list_entry(entry)
		button.toggle_mode = true
		button.button_pressed = int(entry.get("id", -1)) == _selected_entry_id
		var entry_id := int(entry.get("id", -1))
		button.pressed.connect(func() -> void:
			_selected_entry_id = entry_id
			_rebuild_list()
			_update_detail()
		)
		_list_container.add_child(button)


func _update_detail() -> void:
	var history: Array = AiController.get_action_history()
	if history.is_empty():
		_detail_label.text = "Select an action to see scoring factors."
		_summary_label.text = "No AI actions recorded yet."
		_map_row.visible = false
		_before_map.set_board([])
		_after_map.set_board([])
		_influence_label.text = ""
		return

	_summary_label.text = "%d AI action(s) recorded." % history.size()

	var entry: Dictionary = {}
	for candidate in history:
		if int(candidate.get("id", -1)) == _selected_entry_id:
			entry = candidate
			break

	if entry.is_empty():
		entry = history[history.size() - 1]
		_selected_entry_id = int(entry.get("id", -1))

	var before_board: Array = entry.get("before_board", [])
	var after_board: Array = entry.get("after_board", [])
	var highlights: Array = entry.get("highlight_hexes", [])
	var has_maps := not before_board.is_empty()
	_map_row.visible = has_maps
	if has_maps:
		_before_map.set_board(before_board, highlights)
		_after_map.set_board(after_board, highlights)
		_influence_label.text = _format_influence_diff_summary(
			entry.get("ai_power_before", {}),
			entry.get("ai_power_after", {})
		)
	else:
		_before_map.set_board([])
		_after_map.set_board([])
		_influence_label.text = ""

	_detail_label.text = _format_detail(entry)


func _format_list_entry(entry: Dictionary) -> String:
	return str(entry.get("summary", entry.get("description", "")))


func _format_detail(entry: Dictionary) -> String:
	if _is_discard_entry(entry):
		return _format_discard_detail(entry)

	var explanation: Dictionary = entry.get("explanation", {})
	var factors: Array = explanation.get("factors", [])
	var decision: Dictionary = entry.get("decision", {})
	var alternatives: Array = entry.get("alternatives", [])
	var lines: PackedStringArray = PackedStringArray()

	lines.append(str(entry.get("summary", entry.get("description", ""))))
	lines.append("")
	lines.append(_format_decision_summary(decision, explanation))
	lines.append("")
	lines.append("Faction power ratings:")
	lines.append(
		_format_power_ratings(
			entry.get("power_ratings_before", {}),
			entry.get("power_ratings_after", {})
		)
	)
	lines.append("")
	lines.append("AI power (faction power x influence difference):")
	lines.append(_format_ai_power(entry))
	lines.append("")
	lines.append("AI power increase (largest first):")

	if factors.is_empty():
		lines.append("  (no significant factors)")
	else:
		for factor in factors:
			var score := float(factor.get("score", 0.0))
			var sign := "+" if score >= 0.0 else ""
			lines.append("  %s%.1f  %s" % [sign, score, str(factor.get("name", ""))])

	if not alternatives.is_empty():
		lines.append("")
		lines.append("Other options considered:")
		for option_index in range(alternatives.size()):
			var option: Dictionary = alternatives[option_index]
			var rank := option_index + 2
			lines.append(
				"  %d. %s (AI power delta: %.1f)"
				% [
					rank,
					str(option.get("summary", "")),
					float(option.get("evaluator_score", 0.0)),
				]
			)

	return "\n".join(lines)


func _is_discard_entry(entry: Dictionary) -> bool:
	return str(entry.get("move", {}).get("kind", "")) == MoveGenerator.KIND_DISCARD


func _format_discard_detail(entry: Dictionary) -> String:
	var explanation: Dictionary = entry.get("explanation", {})
	var scoring: Dictionary = explanation.get("discard_scoring", {})
	var lines: PackedStringArray = PackedStringArray()

	lines.append(str(entry.get("summary", entry.get("description", ""))))
	lines.append("")

	var action_count := int(scoring.get("action_count", 0))
	var top_faction_count := int(scoring.get("top_faction_count", 0))
	var top_faction_names := str(scoring.get("top_faction_names", ""))
	var own_crib := bool(scoring.get("own_crib", false))
	var crib_label := "your crib" if own_crib else "opponent's crib"
	var top_faction_ids: Array = scoring.get("top_faction_ids", [])
	if top_faction_ids.is_empty():
		top_faction_ids = _derive_top_faction_ids(scoring, explanation)

	lines.append("Faction power:")
	for faction_id in Factions.ALL:
		var power := _discard_faction_power(scoring, explanation, faction_id)
		var suffix := " (most powerful)" if faction_id in top_faction_ids else ""
		lines.append(
			"  %s: %s%s"
			% [Factions.name_for(faction_id), _format_discard_power_value(power), suffix]
		)

	lines.append("")
	lines.append("Kept hand actions: %d" % action_count)
	if top_faction_names.is_empty():
		lines.append("Most powerful faction cards to crib: %d" % top_faction_count)
	else:
		lines.append(
			"Most powerful faction cards to crib: %d (%s)"
			% [top_faction_count, top_faction_names]
		)

	lines.append("")
	lines.append("Score calculation:")

	var action_points := float(scoring.get("action_points", float(action_count) * 7.0))
	if action_count > 0:
		lines.append("  %d actions × 7 = %.0f" % [action_count, action_points])
	else:
		lines.append("  0 actions × 7 = 0")

	if top_faction_count == 1:
		var faction_points := 10.0 if own_crib else -10.0
		lines.append(
			"  1 %s card to %s = %+.0f"
			% [_discard_top_faction_label(top_faction_names), crib_label, faction_points]
		)
	elif top_faction_count >= 2:
		var faction_points := 15.0 if own_crib else -15.0
		lines.append(
			"  2 %s cards to %s = %+.0f"
			% [_discard_top_faction_label(top_faction_names), crib_label, faction_points]
		)
	else:
		lines.append("  0 most-powerful-faction cards to crib = 0")

	var total := float(scoring.get("total", explanation.get("total", 0.0)))
	lines.append("  Total: %.0f" % total)

	return "\n".join(lines)


func _discard_faction_power(
	scoring: Dictionary,
	explanation: Dictionary,
	faction_id: int
) -> float:
	var faction_powers: Dictionary = scoring.get("faction_powers", {})
	if faction_powers.has(faction_id):
		return float(faction_powers[faction_id])
	if faction_powers.has(str(faction_id)):
		return float(faction_powers[str(faction_id)])

	var ratings: Dictionary = explanation.get("power_ratings_before", {})
	return float(ratings.get(faction_id, {}).get("total", 0.0))


func _format_discard_power_value(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return "%.2f" % value


func _derive_top_faction_ids(scoring: Dictionary, explanation: Dictionary) -> Array:
	var best_power := -INF
	for faction_id in Factions.ALL:
		best_power = maxf(best_power, _discard_faction_power(scoring, explanation, faction_id))

	if best_power <= -INF:
		return []

	var top_ids: Array = []
	for faction_id in Factions.ALL:
		var power := _discard_faction_power(scoring, explanation, faction_id)
		if is_equal_approx(power, best_power):
			top_ids.append(faction_id)
	return top_ids


func _discard_top_faction_label(top_faction_names: String) -> String:
	if top_faction_names.is_empty():
		return "most-powerful-faction"
	return top_faction_names


func _format_decision_summary(decision: Dictionary, explanation: Dictionary) -> String:
	if decision.is_empty():
		return "Total score: %.1f" % float(explanation.get("total", 0.0))

	var lines: PackedStringArray = PackedStringArray()
	lines.append("Decision: Highest positive AI power increase")
	var rank := int(decision.get("evaluator_rank", 0))
	var total := int(decision.get("evaluator_total", 0))
	if rank > 0 and total > 0:
		lines.append(
			"AI power delta: %.1f (rank %d of %d legal moves)"
			% [
				float(decision.get("chosen_evaluator_score", explanation.get("total", 0.0))),
				rank,
				total,
			]
		)
	else:
		lines.append(
			"AI power delta: %.1f"
			% float(decision.get("chosen_evaluator_score", explanation.get("total", 0.0)))
		)

	if absf(float(explanation.get("lookahead", 0.0))) >= 0.01:
		lines.append("Pegging lookahead: %.1f" % float(explanation.get("lookahead", 0.0)))

	lines.append("Score = positive change in total AI power (faction power x influence difference)")

	return "\n".join(lines)


func _format_influence_diff_summary(before: Dictionary, after: Dictionary) -> String:
	var before_line := _format_influence_diff_line(
		before,
		before.get("assumed_influence_bonus", {})
	)
	var after_line := _format_influence_diff_line(
		after,
		after.get("assumed_influence_bonus", {})
	)
	if before_line.is_empty() and after_line.is_empty():
		return ""
	if after_line.is_empty() or before_line == after_line:
		return before_line
	if before_line.is_empty():
		return after_line
	return "%s  →  %s" % [before_line, after_line]


func _format_influence_diff_line(ai_power: Dictionary, assumed_bonus: Dictionary = {}) -> String:
	if ai_power.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for faction_id in Factions.ALL:
		var diff := int(
			ai_power.get("by_faction", {}).get(faction_id, {}).get("influence_diff", 0)
		)
		var faction_label := Factions.name_for(faction_id)
		if RemixRules.faction_dict_value(assumed_bonus, faction_id) > 0:
			faction_label = "%s (assumed)" % faction_label
		parts.append("%s %s" % [_format_influence_diff_value(diff), faction_label])
	return " | ".join(parts)


func _format_influence_diff_value(diff: int) -> String:
	if diff > 0:
		return "+%d" % diff
	if diff < 0:
		return "%d" % diff
	return "+/-0"


func _format_power_ratings(before: Dictionary, after: Dictionary) -> String:
	if before.is_empty() and after.is_empty():
		return "  (not available)"
	if before.is_empty():
		return "  After: %s" % PowerRating.format_ratings_line(after)
	if after.is_empty():
		return "  Before: %s" % PowerRating.format_ratings_line(before)
	return PowerRating.format_ratings_change(before, after)


func _format_ai_power(entry: Dictionary) -> String:
	var ai_power_before: Dictionary = entry.get("ai_power_before", {})
	var ai_power_after: Dictionary = entry.get("ai_power_after", {})
	if not ai_power_before.is_empty() or not ai_power_after.is_empty():
		return PowerRating.format_ai_power_totals(ai_power_before, ai_power_after)

	var peer_id := int(entry.get("peer_id", 0))
	if peer_id == 0:
		return "  (not available)"
	var before_context := AiContext.from_game(peer_id)
	var before: Dictionary = entry.get("power_ratings_before", {})
	var after: Dictionary = entry.get("power_ratings_after", {})
	if not before.is_empty() and not after.is_empty():
		return PowerRating.format_ai_power_change(
			before,
			after,
			peer_id,
			before_context.opponent_id,
			before_context,
			null
		)

	return "  (not available)"
