extends Node

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_started
signal connected_to_server
signal connection_failed
signal server_disconnected

var _peer: ENetMultiplayerPeer


func host_game(port: int = DEFAULT_PORT) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = _peer
	server_started.emit()
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = _peer
	return OK


func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


func is_server() -> bool:
	return multiplayer.is_server()


func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	connected_to_server.emit()


func _on_connection_failed() -> void:
	connection_failed.emit()


func _on_server_disconnected() -> void:
	disconnect_from_game()
	server_disconnected.emit()
