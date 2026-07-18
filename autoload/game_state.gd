extends Node

enum Phase {
	WAITING,
	DEAL,
	DISCARD_TO_CRIB,
	CUT_STARTER,
	PEGGING,
	SHOW_HANDS,
	SHOP,
	SPEND_ACTIONS,
	RESOLVE_CRIB,
	ROUND_END,
	GAME_OVER,
}

signal phase_changed(new_phase: Phase)
signal round_started(round_number: int)
signal board_updated(board_state: Array, faction_power: Dictionary)
signal influence_updated(influence: Dictionary)
signal supply_updated(supply: Dictionary)
signal coins_updated(coins: Dictionary)
signal action_points_updated(action_points: Dictionary)
signal faction_actions_updated(faction_actions: Dictionary)
signal faction_scores_updated(faction_scores: Dictionary)
signal winner_decided(peer_id: int, faction_id: int)

var current_phase: Phase = Phase.WAITING
var round_number: int = 0
var ending_round_triggered: bool = false
var player_names: Dictionary = {}
var player_influence: Dictionary = {}
var player_supply: Dictionary = {}
var player_coins: Dictionary = {}
var action_points: Dictionary = {}
var player_faction_actions: Dictionary = {}
var faction_scores: Dictionary = {
	Factions.Id.CLUBS: 0,
	Factions.Id.HEARTS: 0,
	Factions.Id.DIAMONDS: 0,
}

var dealer_peer_id: int = 1
var crib_owner_peer_id: int = 0
var hands: Dictionary = {}
var crib: Array = []
var starter_card: Dictionary = {}
var pegging_total: int = 0

var _board := HexBoard.new()


func register_player(peer_id: int, player_name: String = "") -> void:
	if not multiplayer.is_server():
		return

	if player_name.is_empty():
		player_name = "Player %d" % peer_id

	player_names[peer_id] = player_name
	if not player_influence.has(peer_id):
		player_influence[peer_id] = RemixRules.empty_influence()
	if not player_supply.has(peer_id):
		player_supply[peer_id] = RemixRules.empty_supply()
	if not player_coins.has(peer_id):
		player_coins[peer_id] = 0
	if not action_points.has(peer_id):
		action_points[peer_id] = 0
	if not player_faction_actions.has(peer_id):
		player_faction_actions[peer_id] = RemixRules.empty_faction_actions()

	_sync_player_names.rpc(player_names)
	_sync_influence.rpc(player_influence)
	_sync_supply.rpc(player_supply)
	_sync_coins.rpc(player_coins)
	_sync_action_points.rpc(action_points)
	_sync_faction_actions.rpc(player_faction_actions)
	_sync_faction_scores.rpc(faction_scores)
	_broadcast_board()


@rpc("any_peer", "call_remote", "reliable")
func request_player_name(name: String) -> void:
	if not multiplayer.is_server():
		return

	register_player(multiplayer.get_remote_sender_id(), name)


func start_new_round() -> void:
	if not multiplayer.is_server():
		return

	if ending_round_triggered and current_phase == Phase.ROUND_END:
		_finish_game()
		return

	round_number += 1
	hands.clear()
	crib.clear()
	starter_card.clear()
	pegging_total = 0
	crib_owner_peer_id = 0

	for peer_id in player_names.keys():
		action_points[peer_id] = 0

	_set_phase(Phase.DEAL)
	round_started.emit(round_number)
	_sync_action_points.rpc(action_points)


func grant_actions_from_cards(peer_id: int, cards: Array, starter: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return

	var gained := CribbageScoring.count_actions_from_cards(cards, starter)
	action_points[peer_id] = action_points.get(peer_id, 0) + gained
	_sync_action_points.rpc(action_points)


func grant_pegging_coins(peer_id: int, event_type: String) -> void:
	if not multiplayer.is_server():
		return

	var gained := CribbageScoring.pegging_event_coins(event_type)
	if gained <= 0:
		return

	player_coins[peer_id] = player_coins.get(peer_id, 0) + gained
	_sync_coins.rpc(player_coins)


func grant_pegging_coin_amount(peer_id: int, amount: int) -> void:
	if not multiplayer.is_server():
		return
	if amount <= 0:
		return

	player_coins[peer_id] = player_coins.get(peer_id, 0) + amount
	_sync_coins.rpc(player_coins)


@rpc("any_peer", "call_remote", "reliable")
func request_shop_purchase(faction_id: int) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SHOP:
		return
	if faction_id not in Factions.ALL:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var coins := int(player_coins.get(peer_id, 0))
	if not Shop.can_buy_faction_action(coins):
		return

	player_coins[peer_id] = coins - Shop.FACTION_ACTION_COST
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	tokens[faction_id] = tokens.get(faction_id, 0) + 1
	player_faction_actions[peer_id] = tokens

	_sync_coins.rpc(player_coins)
	_sync_faction_actions.rpc(player_faction_actions)


@rpc("any_peer", "call_remote", "reliable")
func request_end_shop_phase() -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SHOP:
		return

	_set_phase(Phase.SPEND_ACTIONS)


@rpc("any_peer", "call_remote", "reliable")
func request_faction_action(
	hex_index: int,
	faction_id: int,
	action_type: int,
	target_hex: int = -1
) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SPEND_ACTIONS:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	var spend_result := _spend_for_faction_action(peer_id, faction_id)
	if not spend_result.spent:
		return

	var success := false
	match action_type:
		ActionSystem.Type.PUSH:
			success = _board.push(faction_id, hex_index, target_hex)
		ActionSystem.Type.PULL:
			success = _board.pull(faction_id, hex_index, target_hex)
		ActionSystem.Type.CREATE_CART:
			success = _board.create_cart(faction_id, hex_index)

	if not success:
		_refund_faction_action(peer_id, faction_id, spend_result.used_faction_token)
		return

	var cart_scores := _board.score_carts_on_goal()
	_apply_faction_scores(cart_scores)
	_broadcast_board()


@rpc("any_peer", "call_remote", "reliable")
func request_end_action_phase() -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SPEND_ACTIONS:
		return

	_set_phase(Phase.RESOLVE_CRIB)


@rpc("any_peer", "call_remote", "reliable")
func request_crib_resolution(choices: Array) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.RESOLVE_CRIB:
		return

	var peer_id := multiplayer.get_remote_sender_id()
	if crib_owner_peer_id != 0 and peer_id != crib_owner_peer_id:
		return
	if not _validate_crib_choices(choices):
		return

	var influence: Dictionary = player_influence.get(peer_id, RemixRules.empty_influence())
	var supply: Dictionary = player_supply.get(peer_id, RemixRules.empty_supply())

	for choice in choices:
		var card_index := int(choice.get("card_index", -1))
		var card: Dictionary = crib[card_index]
		var faction_id := int(card.get("faction", Factions.from_suit(card.get("suit", "clubs"))))
		var board_hex := int(choice.get("hex_index", -1))

		if bool(choice.get("accept", false)):
			if not _board.remove_cube(faction_id, board_hex):
				return
			influence[faction_id] = influence.get(faction_id, 0) + RemixRules.INFLUENCE_FROM_CRIB
			supply[faction_id] = supply.get(faction_id, 0) + 1
		elif not _board.add_cube(faction_id, board_hex):
			return

	player_influence[peer_id] = influence
	player_supply[peer_id] = supply
	_sync_influence.rpc(player_influence)
	_sync_supply.rpc(player_supply)
	_broadcast_board()
	_finish_round()


func set_crib_owner(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	crib_owner_peer_id = peer_id


func advance_to_shop_phase() -> void:
	if not multiplayer.is_server():
		return

	_set_phase(Phase.SHOP)


func advance_to_action_phase() -> void:
	if not multiplayer.is_server():
		return

	_set_phase(Phase.SPEND_ACTIONS)


func get_total_faction_score() -> int:
	var total := 0
	for faction in Factions.ALL:
		total += int(faction_scores.get(faction, 0))
	return total


func get_player_count() -> int:
	return player_names.size()


func get_board_state() -> Array:
	return _board.duplicate_state()


func get_faction_power() -> Dictionary:
	return _board.get_faction_power()


func get_dominant_faction() -> int:
	return _board.get_dominant_faction()


func get_winner_peer_id() -> int:
	var dominant_faction := get_dominant_faction()
	var best_peer_id := 0
	var best_influence := -1

	for peer_id in player_influence.keys():
		var influence: Dictionary = player_influence[peer_id]
		var value := int(influence.get(dominant_faction, 0))
		if value > best_influence:
			best_influence = value
			best_peer_id = int(peer_id)

	return best_peer_id


func _validate_crib_choices(choices: Array) -> bool:
	if choices.size() != crib.size():
		return false

	var used_indices: Dictionary = {}
	var accept_count := 0

	for choice in choices:
		var card_index := int(choice.get("card_index", -1))
		if card_index < 0 or card_index >= crib.size():
			return false
		if used_indices.has(card_index):
			return false
		used_indices[card_index] = true

		var board_hex := int(choice.get("hex_index", -1))
		var card: Dictionary = crib[card_index]

		if bool(choice.get("accept", false)):
			if board_hex < 0 or board_hex >= HexBoard.HEX_COUNT:
				return false
			accept_count += 1
		else:
			if not HexBoard.is_valid_reject_placement(card, board_hex):
				return false

	return accept_count == 2 and used_indices.size() == crib.size()


func _spend_for_faction_action(peer_id: int, faction_id: int) -> Dictionary:
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	if int(tokens.get(faction_id, 0)) > 0:
		tokens[faction_id] = int(tokens[faction_id]) - 1
		player_faction_actions[peer_id] = tokens
		_sync_faction_actions.rpc(player_faction_actions)
		return {"spent": true, "used_faction_token": true}

	if _spend_action_points(peer_id, ActionSystem.ACTION_COST):
		return {"spent": true, "used_faction_token": false}

	return {"spent": false, "used_faction_token": false}


func _refund_faction_action(peer_id: int, faction_id: int, used_faction_token: bool) -> void:
	if used_faction_token:
		var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
		tokens[faction_id] = tokens.get(faction_id, 0) + 1
		player_faction_actions[peer_id] = tokens
		_sync_faction_actions.rpc(player_faction_actions)
	else:
		action_points[peer_id] = action_points.get(peer_id, 0) + ActionSystem.ACTION_COST
		_sync_action_points.rpc(action_points)


func _apply_faction_scores(scored: Dictionary) -> void:
	for faction in Factions.ALL:
		faction_scores[faction] = faction_scores.get(faction, 0) + int(scored.get(faction, 0))
	_sync_faction_scores.rpc(faction_scores)


func _finish_round() -> void:
	if get_total_faction_score() >= RemixRules.ENDING_SCORE_TOTAL:
		ending_round_triggered = true
		_set_phase(Phase.ROUND_END)
		return

	_set_phase(Phase.ROUND_END)


func _finish_game() -> void:
	_set_phase(Phase.GAME_OVER)
	var winner := get_winner_peer_id()
	winner_decided.emit(winner, get_dominant_faction())
	_sync_winner.rpc(winner, get_dominant_faction())


func _spend_action_points(peer_id: int, cost: int) -> bool:
	var current := int(action_points.get(peer_id, 0))
	if not ActionSystem.can_afford(current, cost):
		return false

	action_points[peer_id] = current - cost
	_sync_action_points.rpc(action_points)
	return true


func _broadcast_board() -> void:
	_sync_board.rpc(_board.duplicate_state(), _board.get_faction_power())


func _set_phase(phase: Phase) -> void:
	current_phase = phase
	_sync_phase.rpc(phase)


@rpc("authority", "call_remote", "reliable")
func _sync_player_names(names: Dictionary) -> void:
	player_names = names


@rpc("authority", "call_remote", "reliable")
func _sync_influence(influence: Dictionary) -> void:
	player_influence = influence
	influence_updated.emit(influence)


@rpc("authority", "call_remote", "reliable")
func _sync_supply(supply: Dictionary) -> void:
	player_supply = supply
	supply_updated.emit(supply)


@rpc("authority", "call_remote", "reliable")
func _sync_coins(coins: Dictionary) -> void:
	player_coins = coins
	coins_updated.emit(coins)


@rpc("authority", "call_remote", "reliable")
func _sync_action_points(points: Dictionary) -> void:
	action_points = points
	action_points_updated.emit(points)


@rpc("authority", "call_remote", "reliable")
func _sync_faction_actions(actions: Dictionary) -> void:
	player_faction_actions = actions
	faction_actions_updated.emit(actions)


@rpc("authority", "call_remote", "reliable")
func _sync_board(board_state: Array, faction_power: Dictionary) -> void:
	_board.load_state(board_state)
	board_updated.emit(board_state, faction_power)


@rpc("authority", "call_remote", "reliable")
func _sync_faction_scores(scores: Dictionary) -> void:
	faction_scores = scores
	faction_scores_updated.emit(scores)


@rpc("authority", "call_remote", "reliable")
func _sync_phase(phase: Phase) -> void:
	current_phase = phase
	phase_changed.emit(phase)


@rpc("authority", "call_remote", "reliable")
func _sync_winner(peer_id: int, faction_id: int) -> void:
	winner_decided.emit(peer_id, faction_id)
