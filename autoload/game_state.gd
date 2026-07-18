extends Node

enum Phase {
	WAITING,
	SETUP_MINI_CRIB,
	DEAL,
	DISCARD_TO_CRIB,
	CUT_CARD,
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
signal cut_card_updated(card: Dictionary)
signal action_turn_updated(peer_id: int)
signal action_history_changed(can_undo: bool)
signal crib_resolution_updated(crib_cards: Array, resolved: Dictionary, resolver_peer: int)
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
var cut_card: Dictionary = {}
var action_turn_peer_id: int = 0
var action_players_finished: Dictionary = {}
var local_crib: Array = []
var local_crib_resolved: Dictionary = {}
var mini_crib_index: int = 0
var mini_crib_resolving_peer: int = 0
var mini_crib_cards: Array = []
var mini_crib_resolved: Dictionary = {}
var end_crib_resolved: Dictionary = {}
var crib_resolver_peer_id: int = 0
var pegging_total: int = 0
var pegging_sequence: Array = []
var pegging_turn_peer: int = 0
var pegging_last_play_peer: int = 0
var active_player_order: Array = []
var discard_ready: Dictionary = {}
var show_hands: Dictionary = {}

var _action_undo_stack: Array = []
var _board := HexBoard.new()
var _deck: Array = []
var _board_setup_complete: bool = false


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
	_broadcast_message("Offline debug: switch players to control each seat. Dealing cards...")


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
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return multiplayer.get_unique_id()
	return sender


func submit_discard(card_indices: Array) -> void:
	if multiplayer.is_server():
		request_discard(card_indices)
	else:
		request_discard.rpc_id(1, card_indices)


func submit_pegging_play(hand_index: int) -> void:
	if multiplayer.is_server():
		request_pegging_play(hand_index)
	else:
		request_pegging_play.rpc_id(1, hand_index)


func submit_pegging_pass() -> void:
	if multiplayer.is_server():
		request_pegging_pass()
	else:
		request_pegging_pass.rpc_id(1)


func submit_shop_purchase(faction_id: int) -> void:
	if multiplayer.is_server():
		request_shop_purchase(faction_id)
	else:
		request_shop_purchase.rpc_id(1, faction_id)


func submit_end_shop_phase() -> void:
	if multiplayer.is_server():
		request_end_shop_phase()
	else:
		request_end_shop_phase.rpc_id(1)


func submit_end_action_phase() -> void:
	if multiplayer.is_server():
		request_end_action_phase()
	else:
		request_end_action_phase.rpc_id(1)


func submit_faction_action(
	hex_index: int,
	action_type: int,
	target_hex: int = -1,
	cube_count: int = 1,
	move_cart_also: bool = false
) -> void:
	if multiplayer.is_server():
		request_faction_action(hex_index, action_type, target_hex, cube_count, move_cart_also)
	else:
		request_faction_action.rpc_id(1, hex_index, action_type, target_hex, cube_count, move_cart_also)


func submit_undo_action() -> void:
	if multiplayer.is_server():
		request_undo_action()
	else:
		request_undo_action.rpc_id(1)


func get_total_actions_for_peer(peer_id: int) -> int:
	var total := get_action_points_for_peer(peer_id)
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	for faction in Factions.ALL:
		total += RemixRules.faction_dict_value(tokens, faction)
	return total


func get_affordable_actions_for_faction(peer_id: int, faction_id: int) -> int:
	return _affordable_action_count(peer_id, faction_id)


func can_undo_action() -> bool:
	return not _action_undo_stack.is_empty()


func get_card_faction_id(card: Dictionary) -> int:
	return _card_faction_id(card)


func get_controlling_faction(hex_index: int) -> int:
	return _board.get_controlling_faction(hex_index)


func get_faction_cubes_on_hex(hex_index: int, faction_id: int) -> int:
	return _board.cube_count_for(faction_id, hex_index)


func get_adjacent_hexes(hex_index: int) -> Array:
	return HexBoard.ADJACENCY.get(hex_index, []).duplicate()


func player_can_afford_action(peer_id: int, faction_id: int) -> bool:
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	if int(RemixRules.faction_dict_value(tokens, faction_id)) > 0:
		return true
	return ActionSystem.can_afford(int(action_points.get(peer_id, 0)))


func player_can_afford_any_action(peer_id: int) -> bool:
	if ActionSystem.can_afford(get_action_points_for_peer(peer_id)):
		return true
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	for faction in Factions.ALL:
		if RemixRules.faction_dict_value(tokens, faction) > 0:
			return true
	return false


func is_action_turn_for_control() -> bool:
	return is_controlled_turn(action_turn_peer_id)


func get_action_turn_peer_id() -> int:
	return action_turn_peer_id


func get_show_hand_for_peer(peer_id: int) -> Array:
	return show_hands.get(peer_id, []).duplicate(true)


func is_crib_owner_for_control() -> bool:
	return is_controlled_turn(crib_owner_peer_id)


func is_crib_resolver_for_control() -> bool:
	return is_controlled_turn(crib_resolver_peer_id)


func submit_crib_card_choice(card_index: int, accept: bool, hex_index: int) -> void:
	if multiplayer.is_server():
		request_crib_card_choice(card_index, accept, hex_index)
	else:
		request_crib_card_choice.rpc_id(1, card_index, accept, hex_index)


func submit_crib_resolution(_choices: Array) -> void:
	pass


func get_action_points_for_peer(peer_id: int) -> int:
	return int(action_points.get(peer_id, 0))


func _update_offline_active_player() -> void:
	if not offline_debug_mode:
		return

	match current_phase:
		Phase.DISCARD_TO_CRIB:
			for peer_id in active_player_order:
				if not discard_ready.get(peer_id, false):
					set_active_control_peer(int(peer_id))
					return
		Phase.SETUP_MINI_CRIB:
			if crib_resolver_peer_id != 0:
				set_active_control_peer(crib_resolver_peer_id)
		Phase.PEGGING:
			if pegging_turn_peer != 0:
				set_active_control_peer(pegging_turn_peer)
		Phase.SPEND_ACTIONS:
			if action_turn_peer_id != 0:
				set_active_control_peer(action_turn_peer_id)
		Phase.RESOLVE_CRIB:
			if crib_resolver_peer_id != 0:
				set_active_control_peer(crib_resolver_peer_id)


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
	_ensure_board_setup()
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
	cut_card.clear()
	action_turn_peer_id = 0
	action_players_finished.clear()
	local_crib.clear()
	mini_crib_index = 0
	mini_crib_resolving_peer = 0
	mini_crib_cards.clear()
	mini_crib_resolved.clear()
	end_crib_resolved.clear()
	crib_resolver_peer_id = 0
	local_crib_resolved.clear()
	pegging_total = 0
	pegging_sequence.clear()
	pegging_turn_peer = 0
	pegging_last_play_peer = 0
	discard_ready.clear()
	crib_owner_peer_id = 0
	show_hands.clear()
	_deck.clear()

	for peer_id in player_names.keys():
		action_points[peer_id] = 0

	_rotate_dealer()
	crib_owner_peer_id = dealer_peer_id
	_begin_mini_crib_setup()
	round_started.emit(round_number)
	_apply_action_points(action_points)
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
		_cut_card()
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
		_finish_pegging()
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
		_finish_pegging()
		return

	pegging_turn_peer = _next_player_with_cards(pegging_last_play_peer)
	if _all_hands_empty() or pegging_turn_peer < 0:
		_finish_pegging()
		return

	_broadcast_pegging_state()


func grant_actions_from_cards(peer_id: int, cards: Array, cut_card_for_scoring: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return

	var gained := CribbageScoring.count_actions_from_cards(cards, cut_card_for_scoring)
	action_points[peer_id] = action_points.get(peer_id, 0) + gained
	_apply_action_points(action_points)
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

	_begin_action_phase()


func _begin_action_phase() -> void:
	action_players_finished.clear()
	for peer_id in active_player_order:
		action_players_finished[int(peer_id)] = false

	action_turn_peer_id = int(active_player_order[0])
	_clear_action_undo_stack()
	_set_phase(Phase.SPEND_ACTIONS)
	_broadcast_action_turn()
	var player_name: String = player_names.get(
		action_turn_peer_id,
		"Player %d" % action_turn_peer_id
	)
	_broadcast_message("%s's action turn — pick Push/Pull/Cart on the map." % player_name)


@rpc("any_peer", "call_remote", "reliable")
func request_faction_action(
	hex_index: int,
	action_type: int,
	target_hex: int = -1,
	cube_count: int = 1,
	move_cart_also: bool = false
) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SPEND_ACTIONS:
		return

	var peer_id := _action_peer_id()
	if peer_id != action_turn_peer_id:
		return

	var faction_id := -1
	var cube_hex := hex_index
	var move_count := 1

	match action_type:
		ActionSystem.Type.PUSH:
			faction_id = _board.get_controlling_faction(hex_index)
		ActionSystem.Type.PULL:
			faction_id = _board.get_controlling_faction(hex_index)
			cube_hex = target_hex
		ActionSystem.Type.CREATE_CART:
			faction_id = _board.get_controlling_faction(hex_index)
			cube_count = 1
			move_cart_also = false

	if faction_id < 0:
		return

	if _affordable_action_count(peer_id, faction_id) < 1:
		return

	match action_type:
		ActionSystem.Type.PUSH, ActionSystem.Type.PULL:
			if cube_count < 1:
				return
			var available_cubes := _board.cube_count_for(faction_id, cube_hex)
			move_count = mini(cube_count, available_cubes)
			if move_count <= 0:
				return
		ActionSystem.Type.CREATE_CART:
			move_count = 1

	_record_action_undo_snapshot()

	var spend_result := _spend_for_faction_action(peer_id, faction_id)
	if not spend_result.spent:
		_action_undo_stack.pop_back()
		_emit_undo_availability()
		return

	var success := false
	match action_type:
		ActionSystem.Type.PUSH:
			success = _board.push(
				faction_id,
				hex_index,
				target_hex,
				move_count,
				move_cart_also
			)
		ActionSystem.Type.PULL:
			success = _board.pull(
				faction_id,
				hex_index,
				target_hex,
				move_count,
				move_cart_also
			)
		ActionSystem.Type.CREATE_CART:
			success = _board.create_cart(faction_id, hex_index)

	if not success:
		_refund_faction_action(peer_id, faction_id, spend_result.used_faction_token)
		_action_undo_stack.pop_back()
		_emit_undo_availability()
		return

	var cart_scores := _board.score_carts_on_goal()
	_apply_faction_scores(cart_scores)
	_broadcast_board()
	_emit_undo_availability()


@rpc("authority", "call_remote", "reliable")
func _sync_undo_availability(can_undo: bool) -> void:
	if multiplayer.is_server():
		return
	action_history_changed.emit(can_undo)


func _emit_undo_availability() -> void:
	var can_undo := can_undo_action()
	action_history_changed.emit(can_undo)
	_sync_undo_availability.rpc(can_undo)


@rpc("any_peer", "call_remote", "reliable")
func request_undo_action() -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SPEND_ACTIONS:
		return

	var peer_id := _action_peer_id()
	if peer_id != action_turn_peer_id:
		return
	if _action_undo_stack.is_empty():
		return

	var snapshot: Dictionary = _action_undo_stack.pop_back()
	_board.load_state(snapshot.get("board", []))
	action_points = snapshot.get("action_points", action_points)
	player_faction_actions = snapshot.get("player_faction_actions", player_faction_actions)
	faction_scores = snapshot.get("faction_scores", faction_scores)
	_apply_action_points(action_points)
	_sync_action_points.rpc(action_points)
	_sync_faction_actions.rpc(player_faction_actions)
	_sync_faction_scores.rpc(faction_scores)
	_broadcast_board()
	_emit_undo_availability()


@rpc("any_peer", "call_remote", "reliable")
func request_end_action_phase() -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SPEND_ACTIONS:
		return

	var peer_id := _action_peer_id()
	if peer_id != action_turn_peer_id:
		return

	action_players_finished[peer_id] = true
	if _all_action_players_finished():
		_begin_crib_resolution()
		return

	_advance_action_turn()


func _all_action_players_finished() -> bool:
	for peer_id in active_player_order:
		if not action_players_finished.get(peer_id, false):
			return false
	return true


func _advance_action_turn() -> void:
	var next_peer := _next_action_player()
	if next_peer < 0:
		_begin_crib_resolution()
		return

	action_turn_peer_id = next_peer
	_clear_action_undo_stack()
	_broadcast_action_turn()
	var player_name: String = player_names.get(
		action_turn_peer_id,
		"Player %d" % action_turn_peer_id
	)
	_broadcast_message("%s's action turn — pick Push/Pull/Cart on the map." % player_name)


func _next_action_player() -> int:
	var peers: Array = active_player_order.duplicate()
	var start_index := peers.find(action_turn_peer_id)
	if start_index < 0:
		start_index = 0

	for step in range(1, peers.size() + 1):
		var candidate: int = peers[(start_index + step) % peers.size()]
		if not action_players_finished.get(candidate, false):
			return candidate

	return -1


func _begin_crib_resolution() -> void:
	end_crib_resolved.clear()
	crib_resolver_peer_id = crib_owner_peer_id
	_set_phase(Phase.RESOLVE_CRIB)
	_broadcast_crib_resolution_state(crib.duplicate(true), end_crib_resolved, crib_owner_peer_id)
	_update_offline_active_player()
	_broadcast_message(
		"%s resolves the crib: accept 2 cards (remove cubes), reject 2 (place cubes)."
		% player_names.get(crib_owner_peer_id, "Dealer")
	)


const MINI_CRIB_COUNT := 3
const MINI_CRIB_SIZE := 2


func _begin_mini_crib_setup() -> void:
	active_player_order = _sorted_peer_ids()
	_deck = CribbageDeck.create_shuffled_deck()
	mini_crib_index = 0
	_set_phase(Phase.SETUP_MINI_CRIB)
	_start_current_mini_crib()


func _start_current_mini_crib() -> void:
	mini_crib_cards.clear()
	mini_crib_resolved.clear()

	for _i in range(MINI_CRIB_SIZE):
		if _deck.is_empty():
			_deck = CribbageDeck.create_shuffled_deck()
		mini_crib_cards.append(_deck.pop_back())

	mini_crib_resolving_peer = _mini_crib_resolver_for_index(mini_crib_index)
	crib_resolver_peer_id = mini_crib_resolving_peer
	_broadcast_crib_resolution_state(
		mini_crib_cards.duplicate(true),
		mini_crib_resolved,
		crib_resolver_peer_id
	)
	_update_offline_active_player()
	var resolver_name: String = player_names.get(crib_resolver_peer_id, "Player %d" % crib_resolver_peer_id)
	_broadcast_message(
		"Mini crib %d / %d — %s accepts 1 card and rejects 1."
		% [mini_crib_index + 1, MINI_CRIB_COUNT, resolver_name]
	)


func _mini_crib_resolver_for_index(index: int) -> int:
	if index == 1:
		return dealer_peer_id
	return _non_dealer_peer()


func _advance_mini_crib() -> void:
	mini_crib_index += 1
	if mini_crib_index >= MINI_CRIB_COUNT:
		_finish_mini_crib_setup()
		return
	_start_current_mini_crib()


func _finish_mini_crib_setup() -> void:
	mini_crib_cards.clear()
	mini_crib_resolved.clear()
	mini_crib_resolving_peer = 0
	crib_resolver_peer_id = 0
	local_crib.clear()
	local_crib_resolved.clear()
	_set_phase(Phase.DEAL)
	_deal_cards()


func _broadcast_crib_resolution_state(
	cards: Array,
	resolved: Dictionary,
	resolver_peer: int
) -> void:
	crib_resolver_peer_id = resolver_peer
	if offline_debug_mode:
		local_crib = cards.duplicate(true)
		local_crib_resolved = resolved.duplicate(true)
		crib_resolution_updated.emit(local_crib, local_crib_resolved, resolver_peer)
		return

	if multiplayer.is_server():
		if resolver_peer == multiplayer.get_unique_id():
			local_crib = cards.duplicate(true)
			local_crib_resolved = resolved.duplicate(true)
			crib_resolution_updated.emit(local_crib, local_crib_resolved, resolver_peer)
		elif resolver_peer > 0:
			_sync_crib_resolution.rpc_id(resolver_peer, cards, resolved, resolver_peer)


@rpc("any_peer", "call_remote", "reliable")
func request_crib_card_choice(card_index: int, accept: bool, hex_index: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := _action_peer_id()
	var cards: Array = []
	var resolved: Dictionary = {}
	var required_accepts := 0
	var total_cards := 0

	match current_phase:
		Phase.SETUP_MINI_CRIB:
			if peer_id != mini_crib_resolving_peer:
				return
			cards = mini_crib_cards
			resolved = mini_crib_resolved
			required_accepts = 1
			total_cards = MINI_CRIB_SIZE
		Phase.RESOLVE_CRIB:
			if peer_id != crib_owner_peer_id:
				return
			cards = crib
			resolved = end_crib_resolved
			required_accepts = 2
			total_cards = crib.size()
		_:
			return

	if card_index < 0 or card_index >= cards.size():
		return
	if resolved.has(card_index):
		return

	var card: Dictionary = cards[card_index]
	if not _can_apply_crib_card(card, accept, hex_index):
		_broadcast_message("Invalid crib placement.")
		return

	var temp_resolved: Dictionary = resolved.duplicate(true)
	temp_resolved[card_index] = {
		"card_index": card_index,
		"accept": accept,
		"hex_index": hex_index,
	}
	if temp_resolved.size() == total_cards:
		if _count_accepts_in_resolved(temp_resolved) != required_accepts:
			_broadcast_message(
				"Need exactly %d accept(s) and %d reject(s)."
				% [required_accepts, total_cards - required_accepts]
			)
			return

	var influence: Dictionary = RemixRules.normalize_faction_dict(
		player_influence.get(peer_id, RemixRules.empty_influence())
	)
	var supply: Dictionary = RemixRules.normalize_faction_dict(
		player_supply.get(peer_id, RemixRules.empty_supply())
	)

	_apply_crib_card(card, accept, hex_index, influence, supply)

	resolved[card_index] = temp_resolved[card_index]
	player_influence[peer_id] = influence
	player_supply[peer_id] = supply
	_sync_influence.rpc(player_influence)
	_sync_supply.rpc(player_supply)
	_broadcast_board()

	var resolver_peer := crib_resolver_peer_id
	if current_phase == Phase.RESOLVE_CRIB:
		resolver_peer = crib_owner_peer_id
	_broadcast_crib_resolution_state(cards.duplicate(true), resolved, resolver_peer)

	if resolved.size() >= total_cards:
		match current_phase:
			Phase.SETUP_MINI_CRIB:
				_advance_mini_crib()
			Phase.RESOLVE_CRIB:
				_finish_round()


func _count_accepts_in_resolved(resolved: Dictionary) -> int:
	var accept_count := 0
	for choice in resolved.values():
		if bool(choice.get("accept", false)):
			accept_count += 1
	return accept_count


func advance_to_shop_phase() -> void:
	if not multiplayer.is_server():
		return

	_set_phase(Phase.SHOP)
	_broadcast_message("Shop phase: spend coins on faction tokens, then click End Shop Phase.")


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
	if _deck.is_empty():
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


func _cut_card() -> void:
	if _deck.is_empty():
		_broadcast_message("Deck empty; cannot cut the card.")
		return

	_set_phase(Phase.CUT_CARD)
	cut_card = _deck.pop_back()
	_sync_cut_card.rpc(cut_card)
	cut_card_updated.emit(cut_card)
	_begin_pegging()


func _begin_pegging() -> void:
	pegging_sequence.clear()
	pegging_total = 0
	pegging_last_play_peer = 0
	pegging_turn_peer = _non_dealer_peer()
	show_hands.clear()
	for peer_id in active_player_order:
		show_hands[peer_id] = hands.get(peer_id, []).duplicate(true)
	_set_phase(Phase.PEGGING)
	_broadcast_pegging_state()
	_broadcast_message("Pegging phase: earn coins for pairs, 15s, 31, and go.")


func _begin_show_hands() -> void:
	_set_phase(Phase.SHOW_HANDS)

	var summary_parts: PackedStringArray = []
	for peer_id in active_player_order:
		var hand: Array = show_hands.get(peer_id, hands.get(peer_id, [])).duplicate(true)
		var before := int(action_points.get(peer_id, 0))
		grant_actions_from_cards(int(peer_id), hand, cut_card)
		var gained := int(action_points.get(peer_id, 0)) - before
		var player_name: String = player_names.get(peer_id, "Player %d" % peer_id)
		summary_parts.append("%s +%d action(s)" % [player_name, gained])

	_broadcast_message("Show hands: %s. Visit the shop, then spend actions." % ", ".join(summary_parts))
	advance_to_shop_phase()


func _advance_pegging_turn() -> void:
	if _all_hands_empty():
		_finish_pegging()
		return

	var next_peer := _next_player_with_cards(pegging_turn_peer)
	if next_peer < 0:
		_finish_pegging()
		return

	pegging_turn_peer = next_peer
	_broadcast_pegging_state()


func _finish_pegging() -> void:
	if current_phase != Phase.PEGGING:
		return

	pegging_sequence.clear()
	pegging_total = 0
	pegging_turn_peer = 0
	_broadcast_pegging_state()
	_begin_show_hands()


func _next_player_with_cards(from_peer: int) -> int:
	var peers: Array = active_player_order.duplicate()
	var start_index := peers.find(from_peer)
	if start_index < 0:
		start_index = 0

	for step in range(1, peers.size() + 1):
		var candidate: int = peers[(start_index + step) % peers.size()]
		if not hands.get(candidate, []).is_empty():
			return candidate

	return -1


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
	_apply_pegging_state(pegging_sequence, pegging_total, pegging_turn_peer)
	_sync_pegging_state.rpc(pegging_sequence, pegging_total, pegging_turn_peer)
	_update_offline_active_player()


func _apply_pegging_state(sequence: Array, total: int, turn_peer: int) -> void:
	pegging_sequence = sequence.duplicate(true)
	pegging_total = total
	pegging_turn_peer = turn_peer
	pegging_state_updated.emit(pegging_sequence, pegging_total, pegging_turn_peer)


func _broadcast_action_turn() -> void:
	_apply_action_turn(action_turn_peer_id)
	_sync_action_turn.rpc(action_turn_peer_id)


func _apply_action_turn(peer_id: int) -> void:
	action_turn_peer_id = peer_id
	action_turn_updated.emit(peer_id)
	_update_offline_active_player()


func _broadcast_message(message: String) -> void:
	game_message.emit(message)
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
			var faction_id := _card_faction_id(card)
			if _board.cube_count_for(faction_id, board_hex) <= 0:
				return false
			accept_count += 1
		else:
			if not HexBoard.is_valid_reject_placement(card, board_hex):
				return false

	return accept_count == 2 and used_indices.size() == crib.size()


func _card_faction_id(card: Dictionary) -> int:
	if card.has("faction"):
		return int(card["faction"])
	return Factions.from_suit(str(card.get("suit", "clubs")))


func _can_apply_crib_card(card: Dictionary, accept: bool, board_hex: int) -> bool:
	var faction_id := _card_faction_id(card)
	if accept:
		return _board.cube_count_for(faction_id, board_hex) > 0
	return HexBoard.is_valid_reject_placement(card, board_hex)


func _apply_crib_card(
	card: Dictionary,
	accept: bool,
	board_hex: int,
	influence: Dictionary,
	supply: Dictionary
) -> void:
	var faction_id := _card_faction_id(card)
	if accept:
		_board.remove_cube(faction_id, board_hex)
		influence[faction_id] = (
			RemixRules.faction_dict_value(influence, faction_id) + RemixRules.INFLUENCE_FROM_CRIB
		)
		supply[faction_id] = RemixRules.faction_dict_value(supply, faction_id) + 1
	else:
		_board.add_cube(faction_id, board_hex)


func _can_apply_crib_choice(choice: Dictionary) -> bool:
	var card_index := int(choice.get("card_index", -1))
	if card_index < 0 or card_index >= crib.size():
		return false
	var card: Dictionary = crib[card_index]
	return _can_apply_crib_card(
		card,
		bool(choice.get("accept", false)),
		int(choice.get("hex_index", -1))
	)


func _apply_crib_choice(
	choice: Dictionary,
	influence: Dictionary,
	supply: Dictionary
) -> void:
	var card_index := int(choice.get("card_index", -1))
	var card: Dictionary = crib[card_index]
	_apply_crib_card(
		card,
		bool(choice.get("accept", false)),
		int(choice.get("hex_index", -1)),
		influence,
		supply
	)


func _affordable_action_count(peer_id: int, faction_id: int) -> int:
	var count := get_action_points_for_peer(peer_id)
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	count += RemixRules.faction_dict_value(tokens, faction_id)
	return count


func _spend_multiple_faction_actions(peer_id: int, faction_id: int, count: int) -> Dictionary:
	var spent := 0
	var faction_tokens_used := 0

	for _i in range(count):
		var result := _spend_for_faction_action(peer_id, faction_id)
		if not result.spent:
			break
		spent += 1
		if result.used_faction_token:
			faction_tokens_used += 1

	return {
		"spent": spent,
		"faction_tokens_used": faction_tokens_used,
	}


func _refund_multiple_faction_actions(
	peer_id: int,
	faction_id: int,
	count: int,
	faction_tokens_used: int
) -> void:
	for _i in range(faction_tokens_used):
		_refund_faction_action(peer_id, faction_id, true)

	var general_refunds := count - faction_tokens_used
	for _i in range(general_refunds):
		_refund_faction_action(peer_id, faction_id, false)


func _record_action_undo_snapshot() -> void:
	_action_undo_stack.append({
		"board": _board.duplicate_state(),
		"action_points": action_points.duplicate(true),
		"player_faction_actions": _duplicate_player_faction_actions(),
		"faction_scores": faction_scores.duplicate(),
	})


func _duplicate_player_faction_actions() -> Dictionary:
	var copy: Dictionary = {}
	for peer_id in player_faction_actions.keys():
		copy[peer_id] = player_faction_actions[peer_id].duplicate(true)
	return copy


func _clear_action_undo_stack() -> void:
	_action_undo_stack.clear()
	_emit_undo_availability()


func _spend_for_faction_action(peer_id: int, faction_id: int) -> Dictionary:
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	var token_count := RemixRules.faction_dict_value(tokens, faction_id)
	if token_count > 0:
		tokens.erase(str(faction_id))
		tokens[faction_id] = token_count - 1
		player_faction_actions[peer_id] = RemixRules.normalize_faction_dict(tokens)
		_sync_faction_actions.rpc(player_faction_actions)
		return {"spent": true, "used_faction_token": true}

	if _spend_action_points(peer_id, ActionSystem.ACTION_COST):
		return {"spent": true, "used_faction_token": false}

	return {"spent": false, "used_faction_token": false}


func _refund_faction_action(peer_id: int, faction_id: int, used_faction_token: bool) -> void:
	if used_faction_token:
		var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
		tokens.erase(str(faction_id))
		tokens[faction_id] = RemixRules.faction_dict_value(tokens, faction_id) + 1
		player_faction_actions[peer_id] = RemixRules.normalize_faction_dict(tokens)
		_sync_faction_actions.rpc(player_faction_actions)
	else:
		action_points[peer_id] = action_points.get(peer_id, 0) + ActionSystem.ACTION_COST
		_apply_action_points(action_points)
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
	_apply_action_points(action_points)
	_sync_action_points.rpc(action_points)
	return true


func _apply_action_points(points: Dictionary) -> void:
	action_points = points.duplicate(true)
	action_points_updated.emit(action_points)


func _broadcast_board() -> void:
	var board_state := _board.duplicate_state()
	var faction_power := _board.get_faction_power()
	_apply_board(board_state, faction_power)
	_sync_board.rpc(board_state, faction_power)


func _ensure_board_setup() -> void:
	if not NetworkManager.is_server():
		return
	if _board_setup_complete:
		return
	if get_player_count() < RemixRules.MIN_PLAYERS:
		return

	var setup_deck := CribbageDeck.create_shuffled_deck()
	var drawn_cards := _board.setup_from_deck(setup_deck)
	drawn_cards.shuffle()
	_deck = drawn_cards
	_board_setup_complete = true


func _apply_board(board_state: Array, faction_power: Dictionary) -> void:
	_board.load_state(board_state)
	board_updated.emit(board_state, faction_power)


func _set_phase(phase: Phase) -> void:
	_apply_phase(phase)
	_sync_phase.rpc(phase)


func _apply_phase(phase: Phase) -> void:
	current_phase = phase
	phase_changed.emit(phase)
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
	if multiplayer.is_server():
		return
	_apply_action_points(points)


@rpc("authority", "call_remote", "reliable")
func _sync_faction_actions(actions: Dictionary) -> void:
	player_faction_actions = actions
	faction_actions_updated.emit(actions)


@rpc("authority", "call_remote", "reliable")
func _sync_board(board_state: Array, faction_power: Dictionary) -> void:
	_apply_board(board_state, faction_power)


@rpc("authority", "call_remote", "reliable")
func _sync_faction_scores(scores: Dictionary) -> void:
	faction_scores = scores
	faction_scores_updated.emit(scores)


@rpc("authority", "call_remote", "reliable")
func _sync_phase(phase: Phase) -> void:
	if multiplayer.is_server():
		return
	_apply_phase(phase)


@rpc("authority", "call_remote", "reliable")
func _sync_winner(peer_id: int, faction_id: int) -> void:
	winner_decided.emit(peer_id, faction_id)


@rpc("authority", "call_remote", "reliable")
func _sync_local_hand(hand: Array) -> void:
	local_hand = hand.duplicate(true)
	local_hand_updated.emit(local_hand)


@rpc("authority", "call_remote", "reliable")
func _sync_cut_card(card: Dictionary) -> void:
	cut_card = card
	cut_card_updated.emit(card)


@rpc("authority", "call_remote", "reliable")
func _sync_action_turn(peer_id: int) -> void:
	if multiplayer.is_server():
		return
	_apply_action_turn(peer_id)


@rpc("authority", "call_remote", "reliable")
func _sync_crib_resolution(crib_cards: Array, resolved: Dictionary, resolver_peer: int) -> void:
	local_crib = crib_cards.duplicate(true)
	local_crib_resolved = resolved.duplicate(true)
	crib_resolver_peer_id = resolver_peer
	crib_resolution_updated.emit(local_crib, local_crib_resolved, resolver_peer)


@rpc("authority", "call_remote", "reliable")
func _sync_pegging_state(sequence: Array, total: int, turn_peer: int) -> void:
	_apply_pegging_state(sequence, total, turn_peer)


@rpc("authority", "call_remote", "reliable")
func _sync_crib_count(count: int) -> void:
	crib_count_updated.emit(count)


@rpc("authority", "call_remote", "reliable")
func _sync_game_message(message: String) -> void:
	game_message.emit(message)
