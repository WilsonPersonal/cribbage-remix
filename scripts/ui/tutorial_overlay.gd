extends Control

signal finished
signal step_action_requested(action: String, advance: Callable)
signal step_shown(step_index: int, step: Dictionary)

const PANEL_BG := Color(0.1, 0.12, 0.16, 0.98)
const PANEL_BORDER := Color(0.45, 0.55, 0.72, 0.85)
const HIGHLIGHT_COLOR := Color(1.0, 0.88, 0.35, 0.95)
const CALLOUT_WIDTH := 300.0
const CALLOUT_MARGIN := 16.0
const CONTENT_WIDTH := CALLOUT_WIDTH - 20.0

var _steps: Array = []
var _step_index := 0
var _target_resolver: Callable = Callable()
var _highlight_rect := Rect2()
var _callout_panel: PanelContainer
var _title_label: Label
var _body_label: Label
var _back_button: Button
var _next_button: Button
var _step_label: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_build_ui()


func start(steps: Array, target_resolver: Callable) -> void:
	_steps = steps.duplicate(true)
	_step_index = 0
	_target_resolver = target_resolver
	z_as_relative = false
	z_index = 60
	var game := get_parent()
	if game is Control:
		game.move_child(self, game.get_child_count() - 1)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	_show_step(_step_index)


func stop() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_steps.clear()
	_highlight_rect = Rect2()
	queue_redraw()
	finished.emit()


func _build_ui() -> void:
	_callout_panel = PanelContainer.new()
	_callout_panel.name = "CalloutPanel"
	_callout_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_callout_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.border_color = PANEL_BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(10)
	_callout_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 0)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_right", 0)
	margin.add_theme_constant_override("margin_bottom", 0)
	_callout_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 11)
	_step_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
	vbox.add_child(_step_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 17)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.custom_minimum_size.x = CONTENT_WIDTH
	_title_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size.x = CONTENT_WIDTH
	_body_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_body_label.add_theme_font_size_override("font_size", 14)
	_body_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	vbox.add_child(_body_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	button_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(button_row)

	_back_button = Button.new()
	_back_button.text = "Go Back"
	_back_button.custom_minimum_size = Vector2(88, 28)
	_back_button.pressed.connect(_on_back_pressed)
	button_row.add_child(_back_button)

	_next_button = Button.new()
	_next_button.text = "Next"
	_next_button.custom_minimum_size = Vector2(88, 28)
	_next_button.pressed.connect(_on_next_pressed)
	button_row.add_child(_next_button)


func _on_back_pressed() -> void:
	if _step_index <= 0:
		return
	_set_navigation_enabled(true)
	_callout_panel.visible = true
	_step_index -= 1
	_show_step(_step_index, false)


func _on_next_pressed() -> void:
	if _step_index >= 0 and _step_index < _steps.size():
		var step: Dictionary = _steps[_step_index]
		if bool(step.get("return_to_menu", false)):
			if _target_resolver.is_valid():
				_target_resolver.call("return_to_main_menu")
			else:
				stop()
			return
		var on_ok := str(step.get("on_ok", ""))
		if not on_ok.is_empty():
			_set_navigation_enabled(false)
			_callout_panel.visible = false
			_highlight_rect = Rect2()
			queue_redraw()
			step_action_requested.emit(on_ok, Callable(self, "advance_after_action"))
			return
	if _step_index + 1 >= _steps.size():
		stop()
		return
	_step_index += 1
	_show_step(_step_index)


func advance_after_action() -> void:
	_set_navigation_enabled(true)
	_callout_panel.visible = true
	if _step_index + 1 >= _steps.size():
		stop()
		return
	_step_index += 1
	_show_step(_step_index)


func _set_navigation_enabled(enabled: bool) -> void:
	_next_button.disabled = not enabled
	_back_button.disabled = not enabled or _step_index <= 0


func _show_step(index: int, run_side_effects: bool = true) -> void:
	if index < 0 or index >= _steps.size():
		stop()
		return

	var step: Dictionary = _steps[index]
	_step_label.text = "Step %d of %d" % [index + 1, _steps.size()]
	_title_label.text = str(step.get("title", "Tutorial"))
	_body_label.text = str(step.get("body", ""))
	_update_label_heights()
	_set_navigation_enabled(true)
	_back_button.visible = index > 0
	if bool(step.get("return_to_menu", false)):
		_next_button.text = "Return to Menu"
		_next_button.custom_minimum_size.x = 120.0
	else:
		_next_button.text = "Next"
		_next_button.custom_minimum_size.x = 88.0

	if _target_resolver.is_valid():
		if bool(step.get("flash_legend", false)):
			_target_resolver.call("flash_legend")
		else:
			_target_resolver.call("clear_legend_flash")

	var target_id := str(step.get("target", ""))
	_highlight_rect = Rect2()
	if not target_id.is_empty() and _target_resolver.is_valid():
		var resolved: Variant = _target_resolver.call(target_id)
		if resolved is Rect2:
			_highlight_rect = resolved

	if run_side_effects:
		if bool(step.get("show_winner", false)) and _target_resolver.is_valid():
			_target_resolver.call("show_tutorial_winner")
	elif _target_resolver.is_valid():
		_target_resolver.call("clear_tutorial_winner")

	call_deferred("_fit_callout_panel", str(step.get("callout_side", "center")))
	step_shown.emit(index, step)


func _update_label_heights() -> void:
	_title_label.custom_minimum_size.y = 0.0
	_body_label.custom_minimum_size.y = 0.0
	_title_label.custom_minimum_size.y = _measure_wrapped_text_height(_title_label)
	_body_label.custom_minimum_size.y = _measure_wrapped_text_height(_body_label)


func _measure_wrapped_text_height(label: Label) -> float:
	if label.text.is_empty():
		return 0.0

	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font")
	if font == null:
		label.reset_size()
		return label.get_minimum_size().y

	var text_size := font.get_multiline_string_size(
		label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		CONTENT_WIDTH,
		font_size
	)
	return text_size.y


func _fit_callout_panel(side: String) -> void:
	if not visible:
		return

	_callout_panel.custom_minimum_size = Vector2.ZERO
	_callout_panel.size = Vector2.ZERO
	_update_label_heights()
	_title_label.reset_size()
	_body_label.reset_size()
	_callout_panel.reset_size()

	var callout_size := _callout_panel.get_combined_minimum_size()
	callout_size.x = maxf(callout_size.x, CALLOUT_WIDTH)
	_callout_panel.custom_minimum_size = callout_size
	_callout_panel.size = callout_size
	_position_callout(side)
	queue_redraw()


func _position_callout(side: String) -> void:
	var viewport_size := get_viewport_rect().size
	var callout_size := _callout_panel.size
	if callout_size == Vector2.ZERO:
		callout_size = _callout_panel.get_combined_minimum_size()

	var pos := Vector2(
		(viewport_size.x - callout_size.x) * 0.5,
		(viewport_size.y - callout_size.y) * 0.5
	)

	if not _highlight_rect.has_area():
		_callout_panel.position = pos
		_callout_panel.size = callout_size
		return

	match side:
		"left":
			pos = Vector2(
				_highlight_rect.position.x - callout_size.x - CALLOUT_MARGIN,
				_highlight_rect.position.y + _highlight_rect.size.y * 0.5 - callout_size.y * 0.5
			)
		"right":
			pos = Vector2(
				_highlight_rect.end.x + CALLOUT_MARGIN,
				_highlight_rect.position.y + _highlight_rect.size.y * 0.5 - callout_size.y * 0.5
			)
		"above":
			pos = Vector2(
				_highlight_rect.position.x + _highlight_rect.size.x * 0.5 - callout_size.x * 0.5,
				_highlight_rect.position.y - callout_size.y - CALLOUT_MARGIN
			)
		"below":
			pos = Vector2(
				_highlight_rect.position.x + _highlight_rect.size.x * 0.5 - callout_size.x * 0.5,
				_highlight_rect.end.y + CALLOUT_MARGIN
			)

	pos.x = clampf(pos.x, CALLOUT_MARGIN, viewport_size.x - callout_size.x - CALLOUT_MARGIN)
	pos.y = clampf(pos.y, CALLOUT_MARGIN, viewport_size.y - callout_size.y - CALLOUT_MARGIN)
	_callout_panel.position = pos
	_callout_panel.size = callout_size


func _process(_delta: float) -> void:
	if not visible:
		return
	if _step_index < 0 or _step_index >= _steps.size():
		return
	var target_id := str(_steps[_step_index].get("target", ""))
	if target_id.is_empty() or not _target_resolver.is_valid():
		return
	var resolved: Variant = _target_resolver.call(target_id)
	if resolved is Rect2 and resolved != _highlight_rect:
		_highlight_rect = resolved
		call_deferred("_fit_callout_panel", str(_steps[_step_index].get("callout_side", "center")))


func _draw() -> void:
	if not _highlight_rect.has_area():
		return

	var padded := _highlight_rect.grow(6.0)
	draw_rect(padded, HIGHLIGHT_COLOR, false, 3.0)
