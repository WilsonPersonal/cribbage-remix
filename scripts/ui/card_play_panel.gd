extends PanelContainer

signal discard_submitted(card_indices: Array)
signal pegging_play_requested(hand_index: int)
signal pegging_pass_requested
signal crib_hex_highlights_changed(target_hexes: Array)

const CardWidgetScene := preload("res://scenes/card_widget.tscn")
const HAND_CARD_SIZE := Vector2(64, 92)
const UNPLAYABLE_CARD_DIM := Color(0.42, 0.42, 0.42, 1.0)

@onready var message_label: Label = $Margin/RootHBox/ContentVBox/MessageLabel
@onready var cut_card_label: Label = $Margin/RootHBox/ContentVBox/HeaderBlock/InfoRow/CutCardLabel
@onready var pegging_section: VBoxContainer = $Margin/RootHBox/ContentVBox/PeggingSection
@onready var pegging_label: Label = $Margin/RootHBox/ContentVBox/PeggingSection/PeggingLabel
@onready var pegging_count_label: Label = $Margin/RootHBox/ContentVBox/PeggingSection/PeggingCountLabel
@onready var pegging_turn_label: Label = $Margin/RootHBox/ContentVBox/PeggingSection/PeggingTurnLabel
@onready var cards_block: VBoxContainer = $Margin/RootHBox/ContentVBox/CardsBlock
@onready var hand_row: HBoxContainer = $Margin/RootHBox/ContentVBox/CardsBlock/HandRow
@onready var hand_container: HBoxContainer = $Margin/RootHBox/ContentVBox/CardsBlock/HandRow/HandContainer
@onready var pegging_container: HBoxContainer = $Margin/RootHBox/ContentVBox/PeggingSection/PeggingContainer
@onready var action_row: HBoxContainer = $Margin/RootHBox/ContentVBox/ActionRow
@onready var confirm_discard_button: Button = $Margin/RootHBox/ContentVBox/ActionRow/ConfirmDiscardButton
@onready var pass_button: Button = $Margin/RootHBox/ContentVBox/ActionRow/PassButton
@onready var crib_panel: VBoxContainer = $Margin/RootHBox/ContentVBox/HeaderBlock/CribPanel
@onready var crib_help_label: Label = $Margin/RootHBox/ContentVBox/HeaderBlock/CribPanel/CribHelpLabel
@onready var crib_container: HBoxContainer = $Margin/RootHBox/ContentVBox/HeaderBlock/CribPanel/CribContainer
@onready var crib_action_row: HBoxContainer = $Margin/RootHBox/ContentVBox/HeaderBlock/CribPanel/CribActionRow
@onready var crib_accept_button: Button = $Margin/RootHBox/ContentVBox/HeaderBlock/CribPanel/CribActionRow/CribAcceptButton
@onready var crib_reject_button: Button = $Margin/RootHBox/ContentVBox/HeaderBlock/CribPanel/CribActionRow/CribRejectButton
@onready var confirm_crib_button: Button = $Margin/RootHBox/ContentVBox/HeaderBlock/CribPanel/CribActionRow/ConfirmCribButton
@onready var crib_owner_label: Label = $Margin/RootHBox/ContentVBox/HeaderBlock/InfoRow/CribOwnerLabel
@onready var crib_discards_container: HBoxContainer = $Margin/RootHBox/ContentVBox/CardsBlock/HandRow/CribDiscardsContainer

var _local_hand: Array = []
var _selected_indices: Array = []
var _display_hand: Array = []
var _crib_cards: Array = []
var _selected_crib_card: int = -1
var _crib_mode_selected: bool = false
var _pending_crib_accept: bool = false
var _crib_choices: Dictionary = {}
var _required_accepts: int = 0


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
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.game_message.connect(_on_game_message)
	GameState.active_control_changed.connect(_on_active_control_changed)
	GameState.action_turn_updated.connect(_on_action_turn_updated)
	GameState.crib_resolution_updated.connect(_on_crib_resolution_updated)
	GameState.show_hands_updated.connect(_on_show_hands_updated)
	GameState.crib_discards_updated.connect(_on_crib_discards_updated)
	GameState.round_context_updated.connect(_on_round_context_updated)
	GameState.lobby_updated.connect(_on_lobby_updated)

	_on_phase_changed(GameState.current_phase)
	_refresh_hand_display()
	_refresh_crib_reminder()


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
	_refresh_crib_reminder()


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
	_refresh_hand_display()
	_update_action_buttons()


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
	_refresh_crib_reminder()


func _on_game_message(message: String) -> void:
	message_label.text = message


func _on_active_control_changed(_peer_id: int) -> void:
	_selected_indices.clear()
	_update_action_buttons()
	_refresh_hand_display()
	_refresh_crib_reminder()
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


func _on_show_hands_updated() -> void:
	if GameState.current_phase == GameState.Phase.SPEND_ACTIONS:
		_refresh_action_hand_display()
	elif GameState.current_phase == GameState.Phase.SHOW_HANDS:
		_refresh_hand_display()


func _on_crib_discards_updated() -> void:
	_refresh_crib_reminder()


func _on_round_context_updated(_dealer_peer_id: int, _crib_owner_peer_id: int) -> void:
	_refresh_crib_reminder()


func _on_lobby_updated() -> void:
	_refresh_crib_reminder()


func _refresh_crib_reminder() -> void:
	var show_phase := GameState.current_phase in [
		GameState.Phase.DISCARD_TO_CRIB,
		GameState.Phase.CUT_CARD,
		GameState.Phase.PEGGING,
		GameState.Phase.SHOW_HANDS,
		GameState.Phase.SHOP,
		GameState.Phase.SPEND_ACTIONS,
		GameState.Phase.RESOLVE_CRIB,
	]
	var crib_owner := GameState.get_crib_owner_peer_id()
	var resolving_crib := _is_crib_resolution_phase() and GameState.is_crib_resolver_for_control()
	var show_crib := show_phase and crib_owner != 0 and not resolving_crib
	crib_owner_label.visible = show_crib
	crib_discards_container.visible = show_crib
	if not show_crib:
		for child in crib_discards_container.get_children():
			child.queue_free()
		_update_cards_block_visibility()
		return

	var control_peer := GameState.get_control_peer_id()
	if crib_owner == control_peer:
		crib_owner_label.text = "Your Crib"
	else:
		var owner_name: String = GameState.player_names.get(crib_owner, "Player %d" % crib_owner)
		crib_owner_label.text = "%s's Crib" % owner_name

	for child in crib_discards_container.get_children():
		child.queue_free()

	var cards: Array = GameState.get_crib_discards_for_peer(control_peer)
	var card_count := maxi(cards.size(), 2)
	var crib_width := card_count * int(HAND_CARD_SIZE.x) + maxi(0, card_count - 1) * 4
	crib_owner_label.custom_minimum_size.x = crib_width
	for card_index in range(cards.size()):
		var card_widget: CardWidget = _make_card_widget(card_index, cards[card_index], true)
		crib_discards_container.add_child(card_widget)

	_update_cards_block_visibility()


func _update_cards_block_visibility() -> void:
	var has_hand := hand_container.get_child_count() > 0
	var show_crib := crib_discards_container.visible
	var resolving_crib := _is_crib_resolution_phase() and GameState.is_crib_resolver_for_control()
	cards_block.visible = (has_hand or show_crib) and not resolving_crib
	hand_row.custom_minimum_size = Vector2(0, 92 if cards_block.visible else 0)


func _make_card_widget(index: int, card: Dictionary, disabled: bool = false) -> CardWidget:
	var card_widget: CardWidget = CardWidgetScene.instantiate()
	card_widget.custom_minimum_size = HAND_CARD_SIZE
	card_widget.size = HAND_CARD_SIZE
	card_widget.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card_widget.disabled = disabled
	card_widget.setup(index, card)
	return card_widget


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
		var card_widget: CardWidget = _make_card_widget(i, cards_to_show[i])
		hand_container.add_child(card_widget)
		card_widget.card_pressed.connect(_on_card_pressed)
		if GameState.current_phase == GameState.Phase.DISCARD_TO_CRIB and _selected_indices.has(i):
			card_widget.modulate = Color(1, 1, 0.7)
		elif GameState.current_phase == GameState.Phase.PEGGING:
			if not PeggingRules.can_play(cards_to_show[i], GameState.pegging_total):
				card_widget.modulate *= UNPLAYABLE_CARD_DIM
				card_widget.disabled = true
		elif GameState.current_phase in [GameState.Phase.SPEND_ACTIONS, GameState.Phase.SHOW_HANDS]:
			card_widget.disabled = true

	_update_cards_block_visibility()


func _refresh_crib_display() -> void:
	for child in crib_container.get_children():
		child.queue_free()

	for i in range(_crib_cards.size()):
		var card_widget: CardWidget = _make_card_widget(i, _crib_cards[i])
		crib_container.add_child(card_widget)
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
		var card_widget: CardWidget = _make_card_widget(i, sequence[i], true)
		pegging_container.add_child(card_widget)


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
	_refresh_crib_reminder()


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
	action_row.visible = confirm_discard_button.visible or pass_button.visible


func _is_my_pegging_turn() -> bool:
	return GameState.is_controlled_turn(GameState.pegging_turn_peer)


func _can_discard_for_control() -> bool:
	return GameState.is_discard_pending_for_control()


func _can_pass_pegging() -> bool:
	return not PeggingRules.has_any_play(_local_hand, GameState.pegging_total)


func _update_pegging_visibility(phase: GameState.Phase) -> void:
	var in_pegging := phase == GameState.Phase.PEGGING
	pegging_section.visible = in_pegging

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
