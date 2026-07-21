extends PanelContainer

signal discard_submitted(card_indices: Array)
signal pegging_play_requested(hand_index: int)
signal pegging_pass_requested
signal crib_hex_highlights_changed(target_hexes: Array)

const CardWidgetScene := preload("res://scenes/card_widget.tscn")

@onready var message_label: Label = $Margin/VBox/MessageLabel
@onready var cut_card_label: Label = $Margin/VBox/CutCardLabel
@onready var pegging_label: Label = $Margin/VBox/PeggingLabel
@onready var pegging_count_label: Label = $Margin/VBox/PeggingCountLabel
@onready var pegging_turn_label: Label = $Margin/VBox/PeggingTurnLabel
@onready var pegging_score_layer: Control = $Margin/VBox/PeggingScoreLayer
@onready var hand_container: HBoxContainer = $Margin/VBox/HandContainer
@onready var pegging_container: HBoxContainer = $Margin/VBox/PeggingContainer
@onready var action_row: HBoxContainer = $Margin/VBox/ActionRow
@onready var confirm_discard_button: Button = $Margin/VBox/ActionRow/ConfirmDiscardButton
@onready var pass_button: Button = $Margin/VBox/ActionRow/PassButton
@onready var crib_panel: VBoxContainer = $Margin/VBox/CribPanel
@onready var crib_help_label: Label = $Margin/VBox/CribPanel/CribHelpLabel
@onready var crib_container: HBoxContainer = $Margin/VBox/CribPanel/CribContainer
@onready var crib_action_row: HBoxContainer = $Margin/VBox/CribPanel/CribActionRow
@onready var crib_accept_button: Button = $Margin/VBox/CribPanel/CribActionRow/CribAcceptButton
@onready var crib_reject_button: Button = $Margin/VBox/CribPanel/CribActionRow/CribRejectButton
@onready var confirm_crib_button: Button = $Margin/VBox/CribPanel/CribActionRow/ConfirmCribButton

var _local_hand: Array = []
var _selected_indices: Array = []
var _display_hand: Array = []
var _crib_cards: Array = []
var _selected_crib_card: int = -1
var _crib_mode_selected: bool = false
var _pending_crib_accept: bool = false
var _crib_choices: Dictionary = {}
var _required_accepts: int = 0
var _pegging_popup_count: int = 0


func _ready() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.12, 0.16, 0.92)
	panel_style.set_content_margin_all(0)
	panel_style.expand_margin_left = 0
	panel_style.expand_margin_top = 0
	panel_style.expand_margin_right = 0
	panel_style.expand_margin_bottom = 0
	add_theme_stylebox_override("panel", panel_style)
	clip_contents = true

	confirm_discard_button.pressed.connect(_on_confirm_discard_pressed)
	pass_button.pressed.connect(_on_pass_pressed)
	crib_accept_button.pressed.connect(_on_crib_accept_pressed)
	crib_reject_button.pressed.connect(_on_crib_reject_pressed)
	confirm_crib_button.visible = false
	crib_accept_button.toggle_mode = true
	crib_reject_button.toggle_mode = true

	GameState.local_hand_updated.connect(_on_local_hand_updated)
	GameState.cut_card_updated.connect(_on_cut_card_updated)
	GameState.pegging_state_updated.connect(_on_pegging_state_updated)
	GameState.pegging_score_scored.connect(_on_pegging_score_scored)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.game_message.connect(_on_game_message)
	GameState.active_control_changed.connect(_on_active_control_changed)
	GameState.action_turn_updated.connect(_on_action_turn_updated)
	GameState.crib_resolution_updated.connect(_on_crib_resolution_updated)
	GameState.show_hands_updated.connect(_on_show_hands_updated)

	_on_phase_changed(GameState.current_phase)
	_refresh_hand_display()


func handle_crib_hex(hex_index: int) -> void:
	if not _is_crib_resolution_phase():
		return
	if not GameState.is_crib_resolver_for_control():
		return
	if _selected_crib_card < 0:
		crib_help_label.text = "Select a crib card first."
		return
	if not _crib_mode_selected:
		crib_help_label.text = "Choose Accept or Reject first."
		return
	if _crib_choices.has(_selected_crib_card):
		crib_help_label.text = "That card already has a placement. Select another."
		return

	var card: Dictionary = _crib_cards[_selected_crib_card]
	if _pending_crib_accept:
		if not _would_accept_be_valid():
			crib_help_label.text = "You can only accept %d crib card(s)." % _required_accepts
			return
		var faction_id := GameState.get_card_faction_id(card)
		if GameState.get_faction_cubes_on_hex(hex_index, faction_id) <= 0:
			crib_help_label.text = "Accept: pick a hex with a %s cube." % Factions.name_for(faction_id)
			return
	else:
		if not _would_reject_be_valid():
			crib_help_label.text = "You must accept %d crib card(s)." % _required_accepts
			return
		if not HexBoard.is_valid_reject_placement(card, hex_index):
			crib_help_label.text = "Reject: card rank must match a hex label (10s go anywhere)."
			return

	GameState.submit_crib_card_choice(_selected_crib_card, _pending_crib_accept, hex_index)
	_selected_crib_card = -1
	_clear_crib_placement_mode()
	_update_crib_help()
	_update_crib_action_buttons_visibility()


func get_crib_card_global_center(card_index: int) -> Vector2:
	if card_index < 0 or card_index >= crib_container.get_child_count():
		return global_position

	var card_widget: Control = crib_container.get_child(card_index)
	return card_widget.get_global_rect().get_center()


func _on_confirm_discard_pressed() -> void:
	var expected := RemixRules.crib_discard_count(max(GameState.get_player_count(), 2))
	if _selected_indices.size() != expected:
		message_label.text = "Select exactly %d cards to discard." % expected
		return
	discard_submitted.emit(_selected_indices.duplicate())


func _on_pass_pressed() -> void:
	pegging_pass_requested.emit()


func _on_crib_accept_pressed() -> void:
	if _selected_crib_card < 0:
		crib_help_label.text = "Select a crib card first."
		return
	if not _would_accept_be_valid():
		crib_help_label.text = "You can only accept %d crib card(s)." % _required_accepts
		return
	_pending_crib_accept = true
	_crib_mode_selected = true
	_update_crib_action_button_styles()
	_update_crib_hex_highlights()
	_update_crib_mode_help()


func _on_crib_reject_pressed() -> void:
	if _selected_crib_card < 0:
		crib_help_label.text = "Select a crib card first."
		return
	if not _would_reject_be_valid():
		crib_help_label.text = "You must accept %d crib card(s)." % _required_accepts
		return
	_pending_crib_accept = false
	_crib_mode_selected = true
	_update_crib_action_button_styles()
	_update_crib_hex_highlights()
	_update_crib_mode_help()


func _update_crib_mode_help() -> void:
	if not _crib_mode_selected or _selected_crib_card < 0:
		return
	if _pending_crib_accept:
		crib_help_label.text = "Accept — click a hex with a matching cube."
	else:
		crib_help_label.text = "Reject — click a hex matching the card rank."


func _clear_crib_placement_mode() -> void:
	_crib_mode_selected = false
	_update_crib_action_button_styles()
	_update_crib_hex_highlights()


func _update_crib_action_button_styles() -> void:
	var accept_active := _crib_mode_selected and _pending_crib_accept
	var reject_active := _crib_mode_selected and not _pending_crib_accept
	crib_accept_button.button_pressed = accept_active
	crib_reject_button.button_pressed = reject_active
	if not _crib_mode_selected:
		crib_accept_button.release_focus()
		crib_reject_button.release_focus()


func _update_crib_hex_highlights() -> void:
	var hexes: Array = []
	if (
		_crib_mode_selected
		and not _pending_crib_accept
		and _selected_crib_card >= 0
		and _selected_crib_card < _crib_cards.size()
	):
		var card: Dictionary = _crib_cards[_selected_crib_card]
		for hex_index in range(HexBoard.HEX_COUNT):
			if HexBoard.is_valid_reject_placement(card, hex_index):
				hexes.append(hex_index)
	crib_hex_highlights_changed.emit(hexes)


func _on_local_hand_updated(hand: Array) -> void:
	_local_hand = hand
	if GameState.current_phase not in [GameState.Phase.SPEND_ACTIONS]:
		_selected_indices.clear()
	_refresh_hand_display()


func _on_cut_card_updated(card: Dictionary) -> void:
	if card.is_empty():
		cut_card_label.text = "Cut card: (not cut yet)"
	else:
		cut_card_label.text = "Cut card: %s" % CribbageDeck.card_label(card)


func _on_action_turn_updated(_peer_id: int) -> void:
	if GameState.current_phase == GameState.Phase.SPEND_ACTIONS:
		_refresh_action_hand_display()


func _on_show_hands_updated() -> void:
	if GameState.current_phase == GameState.Phase.SPEND_ACTIONS:
		_refresh_action_hand_display()


func _on_crib_resolution_updated(crib_cards: Array, resolved: Dictionary, _resolver_peer: int) -> void:
	_crib_cards = crib_cards.duplicate(true)
	_crib_choices = resolved.duplicate(true)
	if _crib_choices.has(_selected_crib_card):
		_selected_crib_card = -1
	_clear_crib_placement_mode()
	_update_crib_visibility(GameState.current_phase)
	_refresh_crib_display()
	_update_crib_help()
	_update_crib_action_buttons_visibility()


func _on_pegging_state_updated(sequence: Array, total: int, turn_peer: int) -> void:
	pegging_count_label.text = "Count: %d / %d" % [total, PeggingRules.MAX_TOTAL]
	pegging_turn_label.text = "Turn: %s" % GameState.player_names.get(
		turn_peer,
		"Player %d" % turn_peer
	)
	message_label.text = "Count: %d / %d — play a card or pass if you cannot." % [
		total,
		PeggingRules.MAX_TOTAL,
	]
	_refresh_pegging_display(sequence)
	_update_action_buttons()


func _on_pegging_score_scored(_peer_id: int, event_type: String, points: int) -> void:
	var score_name := CribbageScoring.pegging_event_label(event_type)
	_show_pegging_score_popup("%s: +%d" % [score_name, points])


func _show_pegging_score_popup(text: String) -> void:
	var overlay: Control = get_parent()
	var popup := Label.new()
	popup.text = text
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	popup.autowrap_mode = TextServer.AUTOWRAP_OFF
	popup.add_theme_font_size_override("font_size", 22)
	popup.add_theme_color_override("font_color", Color(1.0, 0.94, 0.55))
	popup.modulate.a = 0.0
	popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	popup.anchor_left = 0.0
	popup.anchor_top = 1.0
	popup.anchor_right = float(overlay.get("MAIN_WIDTH_RATIO"))
	popup.anchor_bottom = 1.0
	var card_panel_height := float(overlay.get("CARD_PANEL_HEIGHT"))
	var bottom := -card_panel_height - 10.0 - float(_pegging_popup_count * 26)
	popup.offset_bottom = bottom
	popup.offset_top = bottom - 24.0
	popup.offset_left = 0.0
	popup.offset_right = 0.0
	popup.z_index = 20
	overlay.add_child(popup)
	_pegging_popup_count += 1

	var start_y := popup.offset_top
	var tween := popup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "modulate:a", 1.0, 0.12)
	tween.tween_property(popup, "offset_top", start_y - 18.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "offset_bottom", start_y - 18.0 + 24.0, 0.85).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)
	tween.set_parallel(false)
	tween.tween_property(popup, "modulate:a", 0.0, 0.25).set_delay(0.45)
	tween.tween_callback(func() -> void:
		popup.queue_free()
		_pegging_popup_count = maxi(0, _pegging_popup_count - 1)
	)


func _on_phase_changed(phase: GameState.Phase) -> void:
	_selected_indices.clear()
	_selected_crib_card = -1
	_crib_choices.clear()
	_clear_crib_placement_mode()
	_update_action_buttons()
	_update_pegging_visibility(phase)
	_update_crib_visibility(phase)
	if not _is_crib_resolution_phase():
		crib_hex_highlights_changed.emit([])
	match phase:
		GameState.Phase.SETUP_MINI_CRIB:
			message_label.text = "Setup: resolve mini cribs before dealing hands."
		GameState.Phase.DISCARD_TO_CRIB:
			message_label.text = "Select cards to discard to the crib."
		GameState.Phase.PEGGING:
			message_label.text = "Count: %d / %d — play a card or pass if you cannot." % [
				GameState.pegging_total,
				PeggingRules.MAX_TOTAL,
			]
		GameState.Phase.SHOW_HANDS:
			message_label.text = "Scoring hands for actions..."
		GameState.Phase.SHOP:
			message_label.text = "Spend actions — buy face cards from the shop on your turn."
		GameState.Phase.SPEND_ACTIONS:
			_refresh_action_hand_display()
			if GameState.is_action_turn_for_control():
				message_label.text = "Your action turn — use the map or buy from the shop above."
			else:
				message_label.text = "Waiting for another player to take actions."
		GameState.Phase.RESOLVE_CRIB:
			message_label.text = "Resolve the crib (dealer only)."
			_update_crib_help()
		_:
			if phase == GameState.Phase.WAITING:
				if NetworkManager.is_offline_debug():
					message_label.text = "Starting round..."
				else:
					message_label.text = "Click Start Round (right panel) to deal cards."
			elif phase == GameState.Phase.DEAL:
				message_label.text = "Dealing cards..."
			elif phase == GameState.Phase.ROUND_END:
				message_label.text = "Round complete. Click Start Round for the next round."
	_refresh_hand_display()


func _on_game_message(message: String) -> void:
	message_label.text = message


func _on_active_control_changed(_peer_id: int) -> void:
	_selected_indices.clear()
	_update_action_buttons()
	_refresh_hand_display()
	if GameState.current_phase == GameState.Phase.SPEND_ACTIONS:
		_refresh_action_hand_display()
	if _is_crib_resolution_phase():
		_update_crib_visibility(GameState.current_phase)
		_update_crib_help()


func _refresh_action_hand_display() -> void:
	var turn_peer := GameState.get_action_turn_peer_id()
	var turn_name: String = GameState.player_names.get(turn_peer, "Player %d" % turn_peer)
	if GameState.is_action_turn_for_control():
		message_label.text = "Your action turn — spend actions on the map."
	else:
		message_label.text = "%s is taking actions..." % turn_name
	_display_hand = GameState.get_show_hand_for_peer(turn_peer)
	_refresh_hand_display()


func _refresh_hand_display() -> void:
	for child in hand_container.get_children():
		child.queue_free()

	var cards_to_show := _display_hand
	if GameState.current_phase in [
		GameState.Phase.DISCARD_TO_CRIB,
		GameState.Phase.PEGGING,
	]:
		cards_to_show = _local_hand
	elif GameState.current_phase == GameState.Phase.SPEND_ACTIONS:
		cards_to_show = _display_hand
	else:
		cards_to_show = _local_hand

	for i in range(cards_to_show.size()):
		var card_widget: CardWidget = CardWidgetScene.instantiate()
		hand_container.add_child(card_widget)
		card_widget.setup(i, cards_to_show[i])
		card_widget.card_pressed.connect(_on_card_pressed)
		if GameState.current_phase == GameState.Phase.DISCARD_TO_CRIB and _selected_indices.has(i):
			card_widget.modulate = Color(1, 1, 0.7)
		elif GameState.current_phase in [GameState.Phase.SPEND_ACTIONS, GameState.Phase.SHOW_HANDS]:
			card_widget.disabled = true


func _refresh_crib_display() -> void:
	for child in crib_container.get_children():
		child.queue_free()

	for i in range(_crib_cards.size()):
		var card_widget: CardWidget = CardWidgetScene.instantiate()
		crib_container.add_child(card_widget)
		card_widget.setup(i, _crib_cards[i])
		card_widget.card_pressed.connect(_on_crib_card_pressed)
		if _crib_choices.has(i):
			card_widget.modulate = Color(0.7, 1.0, 0.7)
			card_widget.disabled = true
		elif i == _selected_crib_card:
			card_widget.modulate = Color(1, 1, 0.7)
		else:
			card_widget.disabled = false


func _refresh_pegging_display(sequence: Array) -> void:
	for child in pegging_container.get_children():
		child.queue_free()

	for i in range(sequence.size()):
		var card_widget: CardWidget = CardWidgetScene.instantiate()
		pegging_container.add_child(card_widget)
		card_widget.setup(i, sequence[i])
		card_widget.disabled = true


func _on_card_pressed(index: int) -> void:
	match GameState.current_phase:
		GameState.Phase.DISCARD_TO_CRIB:
			_toggle_discard_selection(index)
		GameState.Phase.PEGGING:
			if _is_my_pegging_turn():
				pegging_play_requested.emit(index)
	_refresh_hand_display()


func _on_crib_card_pressed(index: int) -> void:
	if _crib_choices.has(index):
		return
	_selected_crib_card = index
	_clear_crib_placement_mode()
	_refresh_crib_display()
	_update_crib_help()
	_update_crib_action_buttons_visibility()


func _toggle_discard_selection(index: int) -> void:
	if _selected_indices.has(index):
		_selected_indices.erase(index)
	else:
		_selected_indices.append(index)


func _is_crib_resolution_phase() -> bool:
	return GameState.current_phase in [
		GameState.Phase.SETUP_MINI_CRIB,
		GameState.Phase.RESOLVE_CRIB,
	]


func _update_crib_visibility(phase: GameState.Phase) -> void:
	var show_crib := _is_crib_resolution_phase() and GameState.is_crib_resolver_for_control()
	crib_panel.visible = show_crib
	if phase == GameState.Phase.SETUP_MINI_CRIB:
		_required_accepts = 1
	elif phase == GameState.Phase.RESOLVE_CRIB:
		_required_accepts = 2
	else:
		_required_accepts = 0
	_update_crib_action_buttons_visibility()


func _update_crib_action_buttons_visibility() -> void:
	var show_crib := _is_crib_resolution_phase() and GameState.is_crib_resolver_for_control()
	var card_selected := (
		_selected_crib_card >= 0
		and _selected_crib_card < _crib_cards.size()
		and not _crib_choices.has(_selected_crib_card)
	)

	if not show_crib or not card_selected:
		crib_action_row.visible = false
		crib_accept_button.visible = false
		crib_reject_button.visible = false
		_clear_crib_placement_mode()
		return

	var can_accept := _would_accept_be_valid()
	var can_reject := _would_reject_be_valid()

	if can_accept and not can_reject:
		_pending_crib_accept = true
		_crib_mode_selected = true
	elif can_reject and not can_accept:
		_pending_crib_accept = false
		_crib_mode_selected = true
	elif not can_accept and not can_reject:
		crib_action_row.visible = false
		crib_accept_button.visible = false
		crib_reject_button.visible = false
		_clear_crib_placement_mode()
		return

	crib_accept_button.visible = can_accept
	crib_reject_button.visible = can_reject
	crib_action_row.visible = can_accept or can_reject
	_update_crib_action_button_styles()
	_update_crib_hex_highlights()
	_update_crib_mode_help()


func _current_accept_count() -> int:
	var accept_count := 0
	for choice in _crib_choices.values():
		if bool(choice.get("accept", false)):
			accept_count += 1
	return accept_count


func _remaining_unplaced_crib_cards() -> int:
	return _crib_cards.size() - _crib_choices.size()


func _would_accept_be_valid() -> bool:
	var accepts := _current_accept_count()
	if accepts >= _required_accepts:
		return false
	var remaining_after := _remaining_unplaced_crib_cards() - 1
	return accepts + 1 + remaining_after >= _required_accepts


func _would_reject_be_valid() -> bool:
	var accepts := _current_accept_count()
	var remaining_after := _remaining_unplaced_crib_cards() - 1
	return accepts + remaining_after >= _required_accepts


func _update_crib_help() -> void:
	if not _is_crib_resolution_phase():
		return

	var accept_count := 0
	for choice in _crib_choices.values():
		if bool(choice.get("accept", false)):
			accept_count += 1

	if GameState.current_phase == GameState.Phase.SETUP_MINI_CRIB:
		crib_help_label.text = "Mini crib: %d / %d placed | accepts: %d / %d" % [
			_crib_choices.size(),
			_crib_cards.size(),
			accept_count,
			_required_accepts,
		]
	else:
		crib_help_label.text = "Crib: %d / %d placed | accepts: %d / %d" % [
			_crib_choices.size(),
			_crib_cards.size(),
			accept_count,
			_required_accepts,
		]


func _update_action_buttons() -> void:
	var phase := GameState.current_phase
	confirm_discard_button.visible = phase == GameState.Phase.DISCARD_TO_CRIB and _can_discard_for_control()
	pass_button.visible = phase == GameState.Phase.PEGGING and _is_my_pegging_turn()
	pass_button.disabled = not _can_pass_pegging()


func _is_my_pegging_turn() -> bool:
	return GameState.is_controlled_turn(GameState.pegging_turn_peer)


func _can_discard_for_control() -> bool:
	return GameState.is_discard_pending_for_control()


func _can_pass_pegging() -> bool:
	return not PeggingRules.has_any_play(_local_hand, GameState.pegging_total)


func _update_pegging_visibility(phase: GameState.Phase) -> void:
	var in_pegging := phase == GameState.Phase.PEGGING
	pegging_label.visible = in_pegging
	pegging_count_label.visible = in_pegging
	pegging_turn_label.visible = in_pegging
	pegging_score_layer.visible = in_pegging
	pegging_container.visible = in_pegging
	if not in_pegging:
		_pegging_popup_count = 0

	if in_pegging:
		pegging_count_label.text = "Count: %d / %d" % [
			GameState.pegging_total,
			PeggingRules.MAX_TOTAL,
		]
		pegging_turn_label.text = "Turn: %s" % GameState.player_names.get(
			GameState.pegging_turn_peer,
			"Player %d" % GameState.pegging_turn_peer
		)
		_refresh_pegging_display(GameState.pegging_sequence)
