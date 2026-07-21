extends Control

const SPINNER_RADIUS := 14.0
const SPINNER_WIDTH := 3.0
const SPINNER_COLOR := Color(0.78, 0.86, 1.0, 0.95)
const SPINNER_TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.12)

var _active := false
var _spin_angle := 0.0


func set_active(active: bool) -> void:
	_active = active
	set_process(active)
	if active:
		_spin_angle = 0.0
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(36.0, 36.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not _active:
		return
	_spin_angle += delta * TAU * 1.15
	queue_redraw()


func _draw() -> void:
	if not _active:
		return

	var center := size * 0.5
	draw_arc(center, SPINNER_RADIUS, 0.0, TAU, SPINNER_WIDTH, SPINNER_TRACK_COLOR, true)
	draw_arc(
		center,
		SPINNER_RADIUS,
		_spin_angle,
		_spin_angle + TAU * 0.62,
		SPINNER_WIDTH,
		SPINNER_COLOR,
		true
	)
