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
signal local_hand_updated(hand: Array)
signal starter_updated(card: Dictionary)
signal pegging_state_updated(sequence: Array, total: int, turn_peer: int)
signal crib_count_updated(count: int)
signal game_message(message: String)
signal active_control_changed(peer_id: int)

var offline_debug_mode: bool = false
var active_control_peer_id: int = 1

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
var local_hand: Array = []
var crib: Array = []
var starter_card: Dictionary = {}
var pegging_total: int = 0
var pegging_sequence: Array = []
var pegging_turn_peer: int = 0
var pegging_last_play_peer: int = 0
var active_player_order: Array = []
var discard_ready: Dictionary = {}

var _board := HexBoard.new()
var _deck: Array = []


func setup_offline_session(player_one_name: String = "Player 1", player_two_name: String = "Player 2") -> void:
	if not NetworkManager.is_offline_debug():
		return

	offline_debug_mode = true
	player_names.clear()
	player_influence.clear()
	player_supply.clear()
	player_coins.clear()
	action_points.clear()
	player_faction_actions.clear()
	register_player(1, player_one_name)
	register_player(2, player_two_name)
	set_active_control_peer(1)
	_broadcast_message("Offline debug: switch players to control each seat.")


func get_control_peer_id() -> int:
	if offline_debug_mode:
		return active_control_peer_id
	return multiplayer.get_unique_id()


func set_active_control_peer(peer_id: int) -> void:
	if not hands.has(peer_id) and not player_names.has(peer_id):
		return

	active_control_peer_id = peer_id
	local_hand = hands.get(peer_id, []).duplicate(true)
	local_hand_updated.emit(local_hand)
	active_control_changed.emit(peer_id)


func toggle_control_peer() -> void:
	if not offline_debug_mode:
		return

	var peers := _sorted_peer_ids()
	if peers.size() < 2:
		return

	var index := peers.find(active_control_peer_id)
	if index < 0:
		index = 0
	set_active_control_peer(int(peers[(index + 1) % peers.size()]))


func is_discard_pending_for_control() -> bool:
	if current_phase != Phase.DISCARD_TO_CRIB:
		return false
	return not discard_ready.get(get_control_peer_id(), false)


func is_controlled_turn(peer_id: int) -> bool:
	return get_control_peer_id() == peer_id


func _action_peer_id() -> int:
	if offline_debug_mode:
		return active_control_peer_id
	return multiplayer.get_remote_sender_id()


func _update_offline_active_player() -> void:
	if not offline_debug_mode:
		return

	match current_phase:
		Phase.DISCARD_TO_CRIB:
			for peer_id in active_player_order:
				if not discard_ready.get(peer_id, false):
					set_active_control_peer(int(peer_id))
					return
		Phase.PEGGING:
			if pegging_turn_peer != 0:
				set_active_control_peer(pegging_turn_peer)
		Phase.RESOLVE_CRIB:
			if crib_owner_peer_id != 0:
				set_active_control_peer(crib_owner_peer_id)


func register_player(peer_id: int, player_name: String = "") -> void:
	if not NetworkManager.is_server():
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

	if get_player_count() < RemixRules.MIN_PLAYERS:
		_broadcast_message("Need at least %d players to start a round." % RemixRules.MIN_PLAYERS)
		return

	round_number += 1
	hands.clear()
	local_hand.clear()
	crib.clear()
	starter_card.clear()
	pegging_total = 0
	pegging_sequence.clear()
	pegging_turn_peer = 0
	pegging_last_play_peer = 0
	discard_ready.clear()
	crib_owner_peer_id = 0
	_deck.clear()

	for peer_id in player_names.keys():
		action_points[peer_id] = 0

	_rotate_dealer()
	_set_phase(Phase.DEAL)
	_deal_cards()
	round_started.emit(round_number)
	_sync_action_points.rpc(action_points)


@rpc("any_peer", "call_remote", "reliable")
func request_discard(card_indices: Array) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.DISCARD_TO_CRIB:
		return

	var peer_id := _action_peer_id()
	if discard_ready.get(peer_id, false):
		return

	var expected := RemixRules.crib_discard_count(get_player_count())
	if card_indices.size() != expected:
		return

	var hand: Array = hands.get(peer_id, []).duplicate(true)
	if not _validate_card_indices(hand, card_indices):
		return

	var sorted_indices: Array = card_indices.duplicate()
	sorted_indices.sort()
	sorted_indices.reverse()
	for index in sorted_indices:
		crib.append(hand[index])
		hand.remove_at(index)

	hands[peer_id] = hand
	discard_ready[peer_id] = true
	_send_local_hand(peer_id, hand)
	_sync_crib_count.rpc(crib.size())

	if _all_players_discarded():
		_cut_starter()
	else:
		_update_offline_active_player()


@rpc("any_peer", "call_remote", "reliable")
func request_pegging_play(hand_index: int) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.PEGGING:
		return

	var peer_id := _action_peer_id()
	if peer_id != pegging_turn_peer:
		return

	var hand: Array = hands.get(peer_id, [])
	if hand_index < 0 or hand_index >= hand.size():
		return

	var card: Dictionary = hand[hand_index]
	if not PeggingRules.can_play(card, pegging_total):
		return

	hand.remove_at(hand_index)
	hands[peer_id] = hand
	pegging_sequence.append(card)
	pegging_total += int(card.get("value", 0))
	pegging_last_play_peer = peer_id

	for event in PeggingRules.score_events(pegging_sequence, pegging_total):
		grant_pegging_coins(peer_id, event)

	_send_local_hand(peer_id, hand)

	if pegging_total == PeggingRules.MAX_TOTAL:
		pegging_total = 0
		pegging_sequence.clear()

	if _all_hands_empty():
		_begin_show_hands()
		return

	_advance_pegging_turn()


@rpc("any_peer", "call_remote", "reliable")
func request_pegging_pass() -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.PEGGING:
		return

	var peer_id := _action_peer_id()
	if peer_id != pegging_turn_peer:
		return

	var hand: Array = hands.get(peer_id, [])
	if PeggingRules.has_any_play(hand, pegging_total):
		return

	if not pegging_sequence.is_empty() and pegging_last_play_peer != 0:
		grant_pegging_coins(pegging_last_play_peer, "go")

	pegging_sequence.clear()
	pegging_total = 0

	if _all_hands_empty():
		_begin_show_hands()
		return

	pegging_turn_peer = _next_player_with_cards(pegging_last_play_peer)
	_broadcast_pegging_state()


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


@rpc("any_peer", "call_remote", "reliable")
func request_shop_purchase(faction_id: int) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SHOP:
		return
	if faction_id not in Factions.ALL:
		return

	var peer_id := _action_peer_id()
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

	var peer_id := _action_peer_id()
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

	var peer_id := _action_peer_id()
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


func advance_to_shop_phase() -> void:
	if not multiplayer.is_server():
		return

	_set_phase(Phase.SHOP)


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


func _deal_cards() -> void:
	active_player_order = _sorted_peer_ids()
	_deck = CribbageDeck.create_shuffled_deck()
	crib.clear()
	discard_ready.clear()

	for peer_id in active_player_order:
		var hand: Array = []
		var card_count := RemixRules.cards_per_hand(active_player_order.size())
		for _i in range(card_count):
			if _deck.is_empty():
				break
			hand.append(_deck.pop_back())
		hands[peer_id] = hand
		_send_local_hand(int(peer_id), hand)

	crib_owner_peer_id = dealer_peer_id
	_sync_crib_count.rpc(crib.size())
	_set_phase(Phase.DISCARD_TO_CRIB)
	_update_offline_active_player()
	_broadcast_message("Discard %d cards to the crib." % RemixRules.crib_discard_count(active_player_order.size()))


func _cut_starter() -> void:
	if _deck.is_empty():
		_broadcast_message("Deck empty; cannot cut starter.")
		return

	_set_phase(Phase.CUT_STARTER)
	starter_card = _deck.pop_back()
	_sync_starter.rpc(starter_card)
	starter_updated.emit(starter_card)
	_begin_pegging()


func _begin_pegging() -> void:
	pegging_sequence.clear()
	pegging_total = 0
	pegging_last_play_peer = 0
	pegging_turn_peer = _non_dealer_peer()
	_set_phase(Phase.PEGGING)
	_broadcast_pegging_state()
	_broadcast_message("Pegging phase: earn coins for pairs, 15s, 31, and go.")


func _begin_show_hands() -> void:
	_set_phase(Phase.SHOW_HANDS)

	for peer_id in active_player_order:
		var hand: Array = hands.get(peer_id, [])
		grant_actions_from_cards(int(peer_id), hand, starter_card)

	_broadcast_message("Show hands scored. Visit the shop, then spend actions.")
	advance_to_shop_phase()


func _advance_pegging_turn() -> void:
	pegging_turn_peer = _next_player_with_cards(pegging_turn_peer)
	_broadcast_pegging_state()


func _next_player_with_cards(from_peer: int) -> int:
	var peers: Array = active_player_order.duplicate()
	var start_index := peers.find(from_peer)
	if start_index < 0:
		start_index = 0

	for step in range(1, peers.size() + 1):
		var candidate: int = peers[(start_index + step) % peers.size()]
		if not hands.get(candidate, []).is_empty():
			return candidate

	return int(from_peer)


func _all_players_discarded() -> bool:
	for peer_id in active_player_order:
		if not discard_ready.get(peer_id, false):
			return false
	return true


func _all_hands_empty() -> bool:
	for peer_id in active_player_order:
		if not hands.get(peer_id, []).is_empty():
			return false
	return true


func _validate_card_indices(hand: Array, indices: Array) -> bool:
	var used: Dictionary = {}
	for index in indices:
		var card_index := int(index)
		if card_index < 0 or card_index >= hand.size():
			return false
		if used.has(card_index):
			return false
		used[card_index] = true
	return true


func _rotate_dealer() -> void:
	var peers := _sorted_peer_ids()
	if peers.is_empty():
		return
	if dealer_peer_id == 0 or not peers.has(dealer_peer_id):
		dealer_peer_id = peers[0]
		return

	var index := peers.find(dealer_peer_id)
	dealer_peer_id = peers[(index + 1) % peers.size()]


func _non_dealer_peer() -> int:
	for peer_id in active_player_order:
		if int(peer_id) != dealer_peer_id:
			return int(peer_id)
	return int(active_player_order[0])


func _sorted_peer_ids() -> Array:
	var peers: Array = player_names.keys()
	peers.sort()
	return peers


func _send_local_hand(peer_id: int, hand: Array) -> void:
	if offline_debug_mode:
		if peer_id == active_control_peer_id:
			local_hand = hand.duplicate(true)
			local_hand_updated.emit(local_hand)
		return

	_sync_local_hand.rpc_id(peer_id, hand)
	if peer_id == multiplayer.get_unique_id():
		local_hand = hand.duplicate(true)
		local_hand_updated.emit(local_hand)


func _broadcast_pegging_state() -> void:
	_sync_pegging_state.rpc(pegging_sequence, pegging_total, pegging_turn_peer)
	_update_offline_active_player()


func _broadcast_message(message: String) -> void:
	_sync_game_message.rpc(message)


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
	_update_offline_active_player()


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


@rpc("authority", "call_remote", "reliable")
func _sync_local_hand(hand: Array) -> void:
	local_hand = hand.duplicate(true)
	local_hand_updated.emit(local_hand)


@rpc("authority", "call_remote", "reliable")
func _sync_starter(card: Dictionary) -> void:
	starter_card = card
	starter_updated.emit(card)


@rpc("authority", "call_remote", "reliable")
func _sync_pegging_state(sequence: Array, total: int, turn_peer: int) -> void:
	pegging_sequence = sequence.duplicate(true)
	pegging_total = total
	pegging_turn_peer = turn_peer
	pegging_state_updated.emit(pegging_sequence, pegging_total, pegging_turn_peer)


@rpc("authority", "call_remote", "reliable")
func _sync_crib_count(count: int) -> void:
	crib_count_updated.emit(count)


@rpc("authority", "call_remote", "reliable")
func _sync_game_message(message: String) -> void:
	game_message.emit(message)
