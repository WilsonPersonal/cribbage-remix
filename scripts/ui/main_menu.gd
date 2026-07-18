extends Control

@onready var host_button: Button = $Panel/VBox/HostButton
@onready var join_button: Button = $Panel/VBox/JoinButton
@onready var address_input: LineEdit = $Panel/VBox/AddressInput
@onready var port_input: LineEdit = $Panel/VBox/PortInput
@onready var name_input: LineEdit = $Panel/VBox/NameInput
@onready var status_label: Label = $Panel/VBox/StatusLabel

const GAME_SCENE := preload("res://scenes/game.tscn")


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	port_input.text = str(NetworkManager.DEFAULT_PORT)
	address_input.text = "127.0.0.1"


func _on_host_pressed() -> void:
	var port := _read_port()
	status_label.text = "Starting host on port %d..." % port

	var err := NetworkManager.host_game(port)
	if err != OK:
		status_label.text = "Failed to host (error %d)" % err


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"

	status_label.text = "Connecting to %s..." % address
	var err := NetworkManager.join_game(address, _read_port())
	if err != OK:
		status_label.text = "Failed to connect (error %d)" % err


func _on_server_started() -> void:
	status_label.text = "Host ready. Loading game..."
	_enter_game()


func _on_connected_to_server() -> void:
	status_label.text = "Connected. Loading game..."
	_enter_game()


func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check address and port."


func _enter_game() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"

	get_tree().change_scene_to_packed(GAME_SCENE)
	call_deferred("_register_player", player_name)


func _register_player(player_name: String) -> void:
	if NetworkManager.is_server():
		GameState.register_player(NetworkManager.get_local_peer_id(), player_name)
	else:
		GameState.request_player_name.rpc_id(1, player_name)


func _read_port() -> int:
	if port_input.text.is_valid_int():
		return int(port_input.text)
	return NetworkManager.DEFAULT_PORT
