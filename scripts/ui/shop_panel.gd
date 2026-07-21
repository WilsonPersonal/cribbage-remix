extends PanelContainer

const CardWidgetScene := preload("res://scenes/card_widget.tscn")
const HOVER_BRIGHTEN := 1.18

@onready var slots_row: HBoxContainer = $Margin/VBox/SlotsRow
@onready var coins_row: HBoxContainer = $Margin/VBox/CoinsRow

var _slot_buttons: Array = []
var _slot_cost_labels: Array = []
var _slot_base_modulates: Array = []
var _slot_hovered: Array = []
var _coin_labels: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_slots()
	GameState.shop_updated.connect(_on_shop_updated)
	GameState.shop_action_pending_updated.connect(_on_shop_action_pending_updated)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.action_turn_updated.connect(_on_action_turn_updated)
	GameState.coins_updated.connect(_on_coins_updated)
	GameState.board_updated.connect(_on_board_updated)
	GameState.active_control_changed.connect(_on_active_control_updated)
	GameState.lobby_updated.connect(_on_lobby_updated)
	_refresh()


func _build_slots() -> void:
	for child in slots_row.get_children():
		child.queue_free()
	_slot_buttons.clear()
	_slot_cost_labels.clear()
	_slot_base_modulates.clear()
	_slot_hovered.clear()

	for slot_index in range(Shop.SLOT_COUNT):
		var slot_box := VBoxContainer.new()
		slot_box.add_theme_constant_override("separation", 2)
		slot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_box.mouse_filter = Control.MOUSE_FILTER_PASS

		var cost_label := Label.new()
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label.text = "%d coins" % Shop.slot_cost(slot_index)
		cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_box.add_child(cost_label)

		var card_button := CardWidgetScene.instantiate()
		card_button.disabled = false
		card_button.focus_mode = Control.FOCUS_NONE
		card_button.custom_minimum_size = Vector2(56, 80)
		card_button.mouse_filter = Control.MOUSE_FILTER_STOP
		card_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var captured_index := slot_index
		card_button.pressed.connect(func() -> void:
			_on_slot_pressed(captured_index)
		)
		card_button.mouse_entered.connect(func() -> void:
			_on_card_mouse_entered(captured_index)
		)
		card_button.mouse_exited.connect(func() -> void:
			_on_card_mouse_exited(captured_index)
		)
		slot_box.add_child(card_button)

		slots_row.add_child(slot_box)
		_slot_cost_labels.append(cost_label)
		_slot_buttons.append(card_button)
		_slot_base_modulates.append(Color.WHITE)
		_slot_hovered.append(false)


func _on_shop_updated(_slots: Array) -> void:
	_refresh()


func _on_phase_changed(_phase: GameState.Phase) -> void:
	_refresh()


func _on_action_turn_updated(_peer_id: int) -> void:
	_refresh()


func _on_coins_updated(_coins: Dictionary) -> void:
	_refresh()


func _on_board_updated(_board_state: Array, _faction_power: Dictionary) -> void:
	_refresh()


func _on_shop_action_pending_updated(_pending: Dictionary) -> void:
	_refresh()


func _on_active_control_updated(_peer_id: int) -> void:
	_refresh()


func _on_lobby_updated() -> void:
	_refresh()


func _on_card_mouse_entered(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slot_hovered.size():
		return
	var card_button: Button = _slot_buttons[slot_index]
	if card_button.disabled:
		return
	_slot_hovered[slot_index] = true
	_apply_card_modulate(slot_index)


func _on_card_mouse_exited(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slot_hovered.size():
		return
	_slot_hovered[slot_index] = false
	_apply_card_modulate(slot_index)


func _on_slot_pressed(slot_index: int) -> void:
	var peer_id := GameState.get_control_peer_id()
	var block_reason := GameState.get_shop_slot_block_reason(peer_id, slot_index)
	if not block_reason.is_empty():
		GameState.notify_ui_message(block_reason)
		return
	GameState.submit_shop_slot_purchase(slot_index)


func get_coin_display_rect_for_peer(peer_id: int) -> Rect2:
	var label: Label = _coin_labels.get(int(peer_id))
	if label == null:
		return Rect2(global_position + Vector2(0.0, size.y), Vector2(size.x, 0.0))
	return label.get_global_rect()


func _apply_card_modulate(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slot_buttons.size():
		return
	var card_button: Button = _slot_buttons[slot_index]
	var base_color: Color = _slot_base_modulates[slot_index]
	if _slot_hovered[slot_index] and not card_button.disabled:
		card_button.modulate = base_color * HOVER_BRIGHTEN
	else:
		card_button.modulate = base_color


func _refresh() -> void:
	_refresh_coin_labels()

	var slots: Array = GameState.get_shop_slots()
	var peer_id := GameState.get_control_peer_id()

	for slot_index in range(Shop.SLOT_COUNT):
		var card_button: Button = _slot_buttons[slot_index]
		var cost_label: Label = _slot_cost_labels[slot_index]
		var slot: Dictionary = slots[slot_index] if slot_index < slots.size() else {}
		var card: Dictionary = slot.get("card", {}) if typeof(slot.get("card", {})) == TYPE_DICTIONARY else {}
		var cost := int(slot.get("cost", Shop.slot_cost(slot_index)))

		cost_label.text = "%d coins" % cost

		if card.is_empty():
			card_button.text = "Empty"
			_slot_base_modulates[slot_index] = Color(0.7, 0.7, 0.7, 1.0)
			card_button.disabled = true
			card_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_button.mouse_default_cursor_shape = Control.CURSOR_ARROW
			cost_label.modulate = Color(0.7, 0.7, 0.7, 1.0)
			_apply_card_modulate(slot_index)
			continue

		if card_button is CardWidget:
			card_button.setup(slot_index, card)

		var block_reason := GameState.get_shop_slot_block_reason(peer_id, slot_index)
		var affordable := block_reason.is_empty()
		var card_color := card_button.modulate
		_slot_base_modulates[slot_index] = (
			card_color if affordable else card_color * Color(0.45, 0.45, 0.45, 1.0)
		)
		card_button.disabled = false
		card_button.mouse_filter = Control.MOUSE_FILTER_STOP
		card_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cost_label.modulate = Color.WHITE if affordable else Color(0.45, 0.45, 0.45, 1.0)
		_apply_card_modulate(slot_index)


func _refresh_coin_labels() -> void:
	var peer_ids: Array = GameState.player_coins.keys()
	peer_ids.sort()

	for peer_id in _coin_labels.keys():
		if int(peer_id) not in peer_ids:
			_coin_labels[peer_id].queue_free()
			_coin_labels.erase(peer_id)

	if peer_ids.is_empty():
		if _coin_labels.is_empty():
			var placeholder := Label.new()
			placeholder.text = "\u2014"
			placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			coins_row.add_child(placeholder)
			_coin_labels[-1] = placeholder
		return

	if _coin_labels.has(-1):
		_coin_labels[-1].queue_free()
		_coin_labels.erase(-1)

	for index in range(peer_ids.size()):
		var peer_id: int = int(peer_ids[index])
		if not _coin_labels.has(peer_id):
			var label := Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			coins_row.add_child(label)
			_coin_labels[peer_id] = label
		var player_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
		var label: Label = _coin_labels[peer_id]
		label.text = "%s: %d\u00a2" % [player_name, int(GameState.player_coins[peer_id])]
		coins_row.move_child(label, index)
