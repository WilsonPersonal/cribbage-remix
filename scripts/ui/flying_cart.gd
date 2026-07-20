extends Control
class_name FlyingCart

const DEFAULT_DURATION := 0.75
const ARROW_LENGTH := 20.0
const ARROW_WIDTH := 3.0

var _color: Color = Color.WHITE
var _direction: Vector2 = Vector2.RIGHT


func _draw() -> void:
	var center := size * 0.5
	var tip := center + _direction * ARROW_LENGTH * 0.5
	var tail := center - _direction * ARROW_LENGTH * 0.5
	draw_line(tail, tip, _color, ARROW_WIDTH)
	_draw_arrow_head(tip, _direction, _color)


func _draw_arrow_head(tip: Vector2, direction: Vector2, color: Color) -> void:
	var side := Vector2(-direction.y, direction.x)
	var p1 := tip - direction * 10.0 + side * 5.0
	var p2 := tip - direction * 10.0 - side * 5.0
	draw_colored_polygon(PackedVector2Array([tip, p1, p2]), color)


func set_direction(direction: Vector2) -> void:
	if direction.length_squared() <= 0.001:
		return
	_direction = direction.normalized()
	queue_redraw()


static func fly(
	parent: Node,
	from_global: Vector2,
	to_global: Vector2,
	color: Color,
	start_direction: Vector2,
	end_direction: Vector2,
	duration: float = DEFAULT_DURATION,
	start_delay: float = 0.0,
	on_complete: Callable = Callable()
) -> void:
	var cart := FlyingCart.new()
	cart._color = color
	cart.custom_minimum_size = Vector2(48.0, 48.0)
	cart.size = cart.custom_minimum_size
	cart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cart.z_index = 100
	parent.add_child(cart)
	cart.set_direction(start_direction)
	cart.global_position = from_global - cart.size * 0.5

	var target := to_global - cart.size * 0.5
	var tween := cart.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if start_delay > 0.0:
		tween.tween_interval(start_delay)
	tween.set_parallel(true)
	tween.tween_property(cart, "global_position", target, duration)
	var start_dir := (
		start_direction
		if start_direction.length_squared() > 0.001
		else (to_global - from_global).normalized()
	)
	var end_dir := (
		end_direction
		if end_direction.length_squared() > 0.001
		else (to_global - from_global).normalized()
	)
	tween.tween_method(cart.set_direction, start_dir, end_dir, duration)
	tween.set_parallel(false)
	if on_complete.is_valid():
		tween.tween_callback(on_complete)
	tween.tween_callback(cart.queue_free)
