extends PanelContainer

const PANEL_BG_COLOR := Color(0.14, 0.17, 0.22, 0.98)
const PANEL_BORDER_COLOR := Color(0.45, 0.55, 0.72, 0.55)

@onready var _spinner: Control = $Margin/HBox/Spinner
@onready var _label: Label = $Margin/HBox/Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG_COLOR
	panel_style.border_color = PANEL_BORDER_COLOR
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel", panel_style)


func show_for_peer(peer_id: int) -> void:
	var player_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
	_label.text = "%s is thinking..." % player_name
	visible = true
	_spinner.set_active(true)


func hide_thinking() -> void:
	visible = false
	_spinner.set_active(false)
