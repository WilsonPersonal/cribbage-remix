extends Control

signal panel_closed

const PANEL_BG_COLOR := Color(0.1, 0.12, 0.16, 0.98)
const PANEL_BORDER_COLOR := Color(0.45, 0.55, 0.72, 0.55)
const COIN_POSITIVE_COLOR := Color(1.0, 0.94, 0.55)
const COIN_ZERO_COLOR := Color(0.65, 0.68, 0.74)
const CardWidgetScene := preload("res://scenes/card_widget.tscn")
const CARD_SIZE := Vector2(64, 92)

@onready var _panel: PanelContainer = $Panel
@onready var _summary_label: Label = $Panel/Margin/VBox/SummaryLabel
@onready var _cards_row: HBoxContainer = $Panel/Margin/VBox/CardsScroll/CardsRow
@onready var _close_button: Button = $Panel/Margin/VBox/Header/CloseButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_panel_style()
	_close_button.pressed.connect(hide_panel)
	$Backdrop.gui_input.connect(_on_backdrop_gui_input)
	GameState.pegging_history_updated.connect(_on_pegging_history_updated)
	_summary_label.text = "No pegging plays recorded yet."


func show_panel() -> void:
	z_as_relative = false
	z_index = 50
	var game := get_parent()
	if game is Control:
		game.move_child(self, game.get_child_count() - 1)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	_rebuild_display()


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


func _on_pegging_history_updated(_log: Array) -> void:
	if visible:
		_rebuild_display()


func _rebuild_display() -> void:
	for child in _cards_row.get_children():
		child.queue_free()

	var log: Array = GameState.get_pegging_history_for_display()
	if log.is_empty():
		_summary_label.text = "No pegging plays recorded yet."
		var empty_label := Label.new()
		empty_label.text = "Complete a pegging phase to see cards played and coins earned."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_cards_row.add_child(empty_label)
		return

	var totals: Dictionary = {}
	for entry in log:
		var peer_id := int(entry.get("peer_id", -1))
		if peer_id < 0:
			continue
		totals[peer_id] = int(totals.get(peer_id, 0)) + int(entry.get("coins", 0))

	var summary_parts: PackedStringArray = PackedStringArray()
	for peer_id in totals.keys():
		var player_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
		summary_parts.append("%s: +%d coins" % [player_name, int(totals[peer_id])])

	var phase_note := ""
	if GameState.current_phase == GameState.Phase.PEGGING:
		phase_note = " (in progress)"
	_summary_label.text = "%d play(s)%s | %s" % [log.size(), phase_note, ", ".join(summary_parts)]

	for entry in log:
		_cards_row.add_child(_make_entry_column(entry))


func _make_entry_column(entry: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.custom_minimum_size.x = 76.0

	var kind := str(entry.get("kind", "card"))
	if kind == "go":
		var go_panel := PanelContainer.new()
		go_panel.custom_minimum_size = CARD_SIZE
		var go_label := Label.new()
		go_label.text = "Go"
		go_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		go_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		go_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		go_panel.add_child(go_label)
		column.add_child(go_panel)
	else:
		var running_total := int(entry.get("running_total", 0))
		var count_label := Label.new()
		count_label.text = str(running_total)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.add_theme_font_size_override("font_size", 14)
		count_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
		column.add_child(count_label)

		var card: Dictionary = entry.get("card", {})
		var card_widget: CardWidget = CardWidgetScene.instantiate()
		card_widget.custom_minimum_size = CARD_SIZE
		card_widget.size = CARD_SIZE
		card_widget.disabled = true
		card_widget.setup(0, card)
		column.add_child(card_widget)

	var peer_id := int(entry.get("peer_id", -1))
	var player_label := Label.new()
	player_label.text = GameState.player_names.get(peer_id, "P%d" % peer_id)
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_label.add_theme_font_size_override("font_size", 11)
	player_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	column.add_child(player_label)

	var coins := int(entry.get("coins", 0))
	var coins_label := Label.new()
	coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if coins > 0:
		coins_label.text = "+%d" % coins
		coins_label.add_theme_color_override("font_color", COIN_POSITIVE_COLOR)
	else:
		coins_label.text = "—"
		coins_label.add_theme_color_override("font_color", COIN_ZERO_COLOR)
	column.add_child(coins_label)

	var events: Array = entry.get("events", [])
	if not events.is_empty():
		var detail_label := Label.new()
		detail_label.text = _format_events(events)
		detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_label.custom_minimum_size.x = 72.0
		detail_label.add_theme_font_size_override("font_size", 10)
		detail_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
		column.add_child(detail_label)

	return column


func _format_events(events: Array) -> String:
	var labels: PackedStringArray = PackedStringArray()
	for event_type in events:
		labels.append(CribbageScoring.pegging_event_label(str(event_type)))
	return ", ".join(labels)
