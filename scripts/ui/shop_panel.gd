extends PanelContainer

const CardWidgetScene := preload("res://scenes/card_widget.tscn")

@onready var slots_row: HBoxContainer = $Margin/VBox/SlotsRow

var _slot_buttons: Array = []
var _slot_cost_labels: Array = []


func _ready() -> void:
	_build_slots()
	GameState.shop_updated.connect(_on_shop_updated)
	GameState.shop_action_pending_updated.connect(_on_shop_action_pending_updated)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.action_turn_updated.connect(_on_action_turn_updated)
	GameState.coins_updated.connect(_on_coins_updated)
	GameState.board_updated.connect(_on_board_updated)
	GameState.active_control_changed.connect(_on_active_control_changed)
	_on_phase_changed(GameState.current_phase)
	_refresh()


func _build_slots() -> void:
	for child in slots_row.get_children():
		child.queue_free()
	_slot_buttons.clear()
	_slot_cost_labels.clear()

	for slot_index in range(Shop.SLOT_COUNT):
		var slot_box := VBoxContainer.new()
		slot_box.add_theme_constant_override("separation", 2)
		slot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var cost_label := Label.new()
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label.text = "%d coins" % Shop.slot_cost(slot_index)
		slot_box.add_child(cost_label)

		var card_button := CardWidgetScene.instantiate()
		card_button.disabled = true
		card_button.custom_minimum_size = Vector2(48, 68)
		var captured_index := slot_index
		card_button.card_pressed.connect(func(index: int) -> void:
			_on_slot_pressed(captured_index)
		)
		slot_box.add_child(card_button)

		slots_row.add_child(slot_box)
		_slot_cost_labels.append(cost_label)
		_slot_buttons.append(card_button)


func _on_shop_updated(_slots: Array) -> void:
	_refresh()


func _on_phase_changed(_phase: GameState.Phase) -> void:
	visible = GameState.current_phase == GameState.Phase.SPEND_ACTIONS
	_refresh()


func _on_action_turn_updated(_peer_id: int) -> void:
	_refresh()


func _on_coins_updated(_coins: Dictionary) -> void:
	_refresh()


func _on_board_updated(_board_state: Array, _faction_power: Dictionary) -> void:
	_refresh()


func _on_shop_action_pending_updated(_pending: Dictionary) -> void:
	_refresh()


func _on_active_control_changed(_peer_id: int) -> void:
	_refresh()


func _on_slot_pressed(slot_index: int) -> void:
	if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
		return
	if not GameState.is_action_turn_for_control():
		return
	if GameState.has_pending_shop_action(GameState.get_control_peer_id()):
		return
	GameState.submit_shop_slot_purchase(slot_index)


func _refresh() -> void:
	if not visible:
		return

	var slots: Array = GameState.get_shop_slots()
	var coins := int(GameState.player_coins.get(GameState.get_control_peer_id(), 0))
	var can_buy := GameState.is_action_turn_for_control()
	can_buy = can_buy and not GameState.has_pending_shop_action(GameState.get_control_peer_id())

	for slot_index in range(Shop.SLOT_COUNT):
		var card_button: Button = _slot_buttons[slot_index]
		var cost_label: Label = _slot_cost_labels[slot_index]
		var slot: Dictionary = slots[slot_index] if slot_index < slots.size() else {}
		var card: Dictionary = slot.get("card", {}) if typeof(slot.get("card", {})) == TYPE_DICTIONARY else {}
		var cost := int(slot.get("cost", Shop.slot_cost(slot_index)))

		cost_label.text = "%d coins" % cost

		if card.is_empty():
			card_button.text = "Empty"
			card_button.modulate = Color(0.7, 0.7, 0.7, 1.0)
			card_button.disabled = true
			cost_label.modulate = Color(0.7, 0.7, 0.7, 1.0)
			continue

		var card_color := Color.WHITE
		if card_button is CardWidget:
			card_button.setup(slot_index, card)
			card_color = card_button.modulate

		var purchasable := GameState.can_purchase_shop_card(card)
		var affordable := can_buy and coins >= cost and purchasable
		card_button.disabled = not affordable
		card_button.modulate = card_color if affordable else Color(0.65, 0.65, 0.65, 1.0)
		cost_label.modulate = Color.WHITE if affordable else Color(0.65, 0.65, 0.65, 1.0)
