extends PanelContainer

signal discard_submitted(card_indices: Array)
signal pegging_play_requested(hand_index: int)
signal pegging_pass_requested

const CardWidgetScene := preload("res://scenes/card_widget.tscn")

@onready var message_label: Label = $Margin/VBox/MessageLabel
@onready var starter_label: Label = $Margin/VBox/StarterLabel
@onready var pegging_label: Label = $Margin/VBox/PeggingLabel
@onready var pegging_count_label: Label = $Margin/VBox/PeggingCountLabel
@onready var pegging_turn_label: Label = $Margin/VBox/PeggingTurnLabel
@onready var hand_container: HBoxContainer = $Margin/VBox/HandContainer
@onready var pegging_container: HBoxContainer = $Margin/VBox/PeggingContainer
@onready var action_row: HBoxContainer = $Margin/VBox/ActionRow
@onready var confirm_discard_button: Button = $Margin/VBox/ActionRow/ConfirmDiscardButton
@onready var pass_button: Button = $Margin/VBox/ActionRow/PassButton

var _local_hand: Array = []
var _selected_indices: Array = []


func _ready() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.12, 0.16, 0.92)
	add_theme_stylebox_override("panel", panel_style)

	confirm_discard_button.pressed.connect(_on_confirm_discard_pressed)
	pass_button.pressed.connect(_on_pass_pressed)
	GameState.local_hand_updated.connect(_on_local_hand_updated)
	GameState.starter_updated.connect(_on_starter_updated)
	GameState.pegging_state_updated.connect(_on_pegging_state_updated)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.game_message.connect(_on_game_message)
	GameState.active_control_changed.connect(_on_active_control_changed)
	_on_phase_changed(GameState.current_phase)
	_refresh_hand_display()


func _on_confirm_discard_pressed() -> void:
	var expected := RemixRules.crib_discard_count(max(GameState.get_player_count(), 2))
	if _selected_indices.size() != expected:
		message_label.text = "Select exactly %d cards to discard." % expected
		return
	discard_submitted.emit(_selected_indices.duplicate())


func _on_pass_pressed() -> void:
	pegging_pass_requested.emit()


func _on_local_hand_updated(hand: Array) -> void:
	_local_hand = hand
	_selected_indices.clear()
	_refresh_hand_display()


func _on_starter_updated(card: Dictionary) -> void:
	if card.is_empty():
		starter_label.text = "Starter: (not cut yet)"
	else:
		starter_label.text = "Starter: %s" % CribbageDeck.card_label(card)


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


func _on_phase_changed(phase: GameState.Phase) -> void:
	_selected_indices.clear()
	_update_action_buttons()
	_update_pegging_visibility(phase)
	match phase:
		GameState.Phase.DISCARD_TO_CRIB:
			message_label.text = "Select cards to discard to the crib."
		GameState.Phase.PEGGING:
			message_label.text = "Count: %d / %d — play a card or pass if you cannot." % [
				GameState.pegging_total,
				PeggingRules.MAX_TOTAL,
			]
		GameState.Phase.SHOW_HANDS:
			message_label.text = "Scoring hands for actions..."
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


func _refresh_hand_display() -> void:
	for child in hand_container.get_children():
		child.queue_free()

	for i in range(_local_hand.size()):
		var card_widget: CardWidget = CardWidgetScene.instantiate()
		hand_container.add_child(card_widget)
		card_widget.setup(i, _local_hand[i])
		card_widget.card_pressed.connect(_on_card_pressed)
		if _selected_indices.has(i):
			card_widget.modulate = Color(1, 1, 0.7)


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


func _toggle_discard_selection(index: int) -> void:
	if _selected_indices.has(index):
		_selected_indices.erase(index)
	else:
		_selected_indices.append(index)


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
	pegging_container.visible = in_pegging

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
