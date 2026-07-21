extends Control
class_name FlyingCube

const DEFAULT_RADIUS := 5.0
const DEFAULT_DURATION := 0.75
const MAP_CUBE_RADIUS := 4.5

var _color: Color = Color.WHITE
var _radius: float = DEFAULT_RADIUS


func _draw() -> void:
	var center := Vector2(_radius, _radius)
	Factions.draw_cube(self, center, _radius, _color)


func _set_radius(new_radius: float) -> void:
	_radius = new_radius
	custom_minimum_size = Vector2(_radius * 2.0, _radius * 2.0)
	size = custom_minimum_size
	queue_redraw()


static func fly(
	parent: Node,
	from_global: Vector2,
	to_global: Vector2,
	color: Color,
	radius: float = MAP_CUBE_RADIUS,
	duration: float = DEFAULT_DURATION,
	end_radius: float = -1.0,
	start_delay: float = 0.0,
	on_complete: Callable = Callable()
) -> void:
	var cube := FlyingCube.new()
	cube._color = color
	cube._set_radius(radius)
	cube.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cube.z_index = 100
	parent.add_child(cube)
	cube.global_position = from_global - Vector2(radius, radius)

	var target_radius := end_radius if end_radius > 0.0 else radius
	var target := to_global - Vector2(target_radius, target_radius)
	var tween := cube.create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if start_delay > 0.0:
		tween.tween_interval(start_delay)
	tween.set_parallel(true)
	tween.tween_property(cube, "global_position", target, duration)
	if not is_equal_approx(target_radius, radius):
		tween.tween_method(cube._set_radius, radius, target_radius, duration)
	tween.set_parallel(false)
	if on_complete.is_valid():
		tween.tween_callback(on_complete)
	tween.tween_callback(cube.queue_free)
