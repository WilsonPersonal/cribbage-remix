class_name CardWidget
extends Button

signal card_pressed(card_index: int)

var card_index: int = -1
var card_data: Dictionary = {}


func setup(index: int, data: Dictionary) -> void:
	card_index = index
	card_data = data
	custom_minimum_size = Vector2(64, 92)
	text = "%s\n%s" % [data.get("rank", "?"), _suit_symbol(data.get("suit", ""))]
	modulate = _suit_color(data.get("suit", ""))
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


func _on_pressed() -> void:
	card_pressed.emit(card_index)


func _suit_symbol(suit: String) -> String:
	match suit:
		"hearts":
			return "H"
		"diamonds":
			return "D"
		"clubs":
			return "C"
		"spades":
			return "S*"
		_:
			return "?"


func _suit_color(suit: String) -> Color:
	match suit:
		"hearts":
			return Color("#ffb3b3")
		"diamonds":
			return Color("#a8c8ff")
		"clubs":
			return Color("#cccccc")
		"spades":
			return Color("#d4b8ff")
		_:
			return Color.WHITE
