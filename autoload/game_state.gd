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
signal crib_cube_anim_requested(accept: bool, hex_index: int, faction_id: int, card_index: int, peer_id: int)
signal action_cube_anim_requested(faction_id: int, from_hex: int, to_hex: int, move_count: int)
signal action_cart_anim_requested(
	faction_id: int, from_hex: int, to_hex: int, origin_hex: int
)
signal pegging_state_updated(sequence: Array, total: int, turn_peer: int)
signal pegging_score_scored(peer_id: int, event_type: String, points: int)
signal faction_score_scored(faction_id: int, points: int, old_rank: int, new_rank: int)
signal crib_count_updated(count: int)
signal show_hands_updated
signal crib_discards_updated
signal round_context_updated(dealer_peer_id: int, crib_owner_peer_id: int)
signal shop_updated(slots: Array)
signal shop_action_pending_updated(pending: Dictionary)
signal game_message(message: String)
signal active_control_changed(peer_id: int)
signal lobby_updated

var offline_debug_mode: bool = false
var vs_ai_mode: bool = false
var pending_vs_ai: bool = false
var active_control_peer_id: int = 1
var pending_local_player_name: String = ""
var _acting_peer_override: int = -1
var _ai_search_silence: int = 0

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
var faction_score_recency: Dictionary = {
	Factions.Id.CLUBS: 0,
	Factions.Id.HEARTS: 0,
	Factions.Id.DIAMONDS: 0,
}
var _faction_score_recency_counter: int = 0

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
var _mini_cribs_completed_for_round: bool = false
var pegging_total: int = 0
var pegging_sequence: Array = []
var pegging_turn_peer: int = 0
var pegging_last_play_peer: int = 0
var active_player_order: Array = []
var discard_ready: Dictionary = {}
var show_hands: Dictionary = {}
var player_crib_discards: Dictionary = {}

var _action_undo_stack: Array = []
var _board := HexBoard.new()
var _deck: Array = []
var _face_card_deck: Array = []
var shop_slots: Array = []
var _pending_shop_action: Dictionary = {}
var _board_setup_complete: bool = false


func setup_offline_session(player_one_name: String = "Player 1", player_two_name: String = "Player 2") -> void:
	if not NetworkManager.is_offline_debug():
		return

	offline_debug_mode = true
	vs_ai_mode = false
	AiController.disable()
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


func setup_offline_vs_ai(human_name: String = "You", ai_name: String = "AI") -> void:
	setup_offline_session(human_name, ai_name)
	vs_ai_mode = true
	AiController.enable_for_peers([2])
	_broadcast_message("Playing vs %s. You are %s." % [ai_name, human_name])


func is_ai_peer(peer_id: int) -> bool:
	return vs_ai_mode and AiController.is_ai_peer(peer_id)


func get_hand_for_peer(peer_id: int) -> Array:
	return hands.get(peer_id, []).duplicate(true)


func get_available_cube_space(faction_id: int, hex_index: int) -> int:
	return _board.available_cube_space(faction_id, hex_index)


func run_as_peer(peer_id: int, callback: Callable) -> void:
	if not multiplayer.is_server():
		return
	var previous_override := _acting_peer_override
	_acting_peer_override = peer_id
	callback.call()
	_acting_peer_override = previous_override


func push_ai_search_silence() -> void:
	_ai_search_silence += 1


func pop_ai_search_silence() -> void:
	_ai_search_silence = maxi(0, _ai_search_silence - 1)


func is_ai_search_silence() -> bool:
	return _ai_search_silence > 0


func set_pending_local_player_name(player_name: String) -> void:
	pending_local_player_name = player_name.strip_edges()


func consume_pending_local_player_name() -> String:
	var player_name := pending_local_player_name.strip_edges()
	pending_local_player_name = ""
	if player_name.is_empty():
		return "Player %d" % multiplayer.get_unique_id()
	return player_name


func prepare_online_session() -> void:
	if NetworkManager.is_offline_debug():
		return

	offline_debug_mode = false
	player_names.clear()
	player_influence.clear()
	player_supply.clear()
	player_coins.clear()
	action_points.clear()
	player_faction_actions.clear()
	player_crib_discards.clear()
	hands.clear()
	local_hand.clear()
	active_player_order.clear()
	crib.clear()
	cut_card.clear()
	show_hands.clear()
	discard_ready.clear()
	action_players_finished.clear()
	_action_undo_stack.clear()
	_board_setup_complete = false
	_board.reset()
	round_number = 0
	ending_round_triggered = false
	dealer_peer_id = 1
	crib_owner_peer_id = 0
	faction_scores = {
		Factions.Id.CLUBS: 0,
		Factions.Id.HEARTS: 0,
		Factions.Id.DIAMONDS: 0,
	}
	faction_score_recency = {
		Factions.Id.CLUBS: 0,
		Factions.Id.HEARTS: 0,
		Factions.Id.DIAMONDS: 0,
	}
	_faction_score_recency_counter = 0

	if NetworkManager.is_server():
		_set_phase(Phase.WAITING)
	else:
		current_phase = Phase.WAITING

	lobby_updated.emit()


func submit_local_player_name(player_name: String = "") -> void:
	var cleaned := player_name.strip_edges()
	if cleaned.is_empty():
		cleaned = consume_pending_local_player_name()
	if NetworkManager.is_server():
		register_player(multiplayer.get_unique_id(), cleaned)
	else:
		request_player_name.rpc_id(1, cleaned)


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
	return not bool(discard_ready.get(get_control_peer_id(), false))


func is_controlled_turn(peer_id: int) -> bool:
	return get_control_peer_id() == peer_id


func _action_peer_id() -> int:
	if _acting_peer_override >= 0:
		return _acting_peer_override
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


func submit_shop_slot_purchase(slot_index: int) -> void:
	if multiplayer.is_server():
		request_shop_slot_purchase(slot_index)
	else:
		request_shop_slot_purchase.rpc_id(1, slot_index)


func submit_shop_deploy_faction(faction_id: int) -> void:
	if multiplayer.is_server():
		request_shop_deploy_faction(faction_id)
	else:
		request_shop_deploy_faction.rpc_id(1, faction_id)


func submit_shop_jack_push(from_hex: int, to_hex: int) -> void:
	if multiplayer.is_server():
		request_shop_jack_push(from_hex, to_hex)
	else:
		request_shop_jack_push.rpc_id(1, from_hex, to_hex)


func submit_shop_king_deploy(hex_index: int) -> void:
	if multiplayer.is_server():
		request_shop_king_deploy(hex_index)
	else:
		request_shop_king_deploy.rpc_id(1, hex_index)


func submit_end_shop_phase() -> void:
	pass


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
	for faction in Factions.SHOP_FACTIONS:
		total += RemixRules.faction_dict_value(tokens, faction)
	return total


func get_affordable_actions_for_faction(peer_id: int, faction_id: int) -> int:
	return _affordable_action_count(peer_id, faction_id)


func can_undo_action() -> bool:
	if current_phase != Phase.SPEND_ACTIONS:
		return false
	if _action_undo_stack.is_empty():
		return false
	var snapshot: Dictionary = _action_undo_stack[_action_undo_stack.size() - 1]
	return int(snapshot.get("peer_id", -1)) == int(action_turn_peer_id)


func get_card_faction_id(card: Dictionary) -> int:
	return _card_faction_id(card)


func get_controlling_faction(hex_index: int) -> int:
	return _board.get_controlling_faction(hex_index)


func faction_has_dominance(faction_id: int) -> bool:
	if faction_id == Factions.Id.SPADES:
		return true
	return not get_faction_dominance_hexes(faction_id).is_empty()


func get_faction_dominance_hexes(faction_id: int) -> Array:
	if faction_id not in Factions.ALL:
		return []

	var hexes: Array = []
	for hex_index in range(HexBoard.HEX_COUNT):
		if _board.controls_hex(faction_id, hex_index):
			hexes.append(hex_index)
	return hexes


func faction_has_cubes_on_board(faction_id: int) -> bool:
	if faction_id not in Factions.ALL:
		return false
	return not get_hexes_with_faction_cubes(faction_id).is_empty()


func any_board_faction_has_cubes() -> bool:
	for faction_id in Factions.ALL:
		if faction_has_cubes_on_board(faction_id):
			return true
	return false


func get_hexes_with_faction_cubes(faction_id: int) -> Array:
	if faction_id not in Factions.ALL:
		return []

	var hexes: Array = []
	for hex_index in range(HexBoard.HEX_COUNT):
		if _board.cube_count_for(faction_id, hex_index) > 0:
			hexes.append(hex_index)
	return hexes


func get_hexes_with_deploy_space(faction_id: int) -> Array:
	if faction_id not in Factions.ALL:
		return []

	var hexes: Array = []
	for hex_index in range(HexBoard.HEX_COUNT):
		if _board.available_cube_space(faction_id, hex_index) > 0:
			hexes.append(hex_index)
	return hexes


func can_purchase_shop_card(card: Dictionary) -> bool:
	var faction_id := _shop_card_faction_id(card)
	if faction_id < 0:
		return false

	match Shop.card_effect(card):
		Shop.EFFECT_QUEEN:
			return faction_has_dominance(faction_id)
		Shop.EFFECT_JACK:
			if faction_id == Factions.Id.SPADES:
				return any_board_faction_has_cubes()
			return faction_has_cubes_on_board(faction_id)
		Shop.EFFECT_KING:
			return true
	return false


func shop_purchase_has_valid_follow_up(peer_id: int, card: Dictionary) -> bool:
	var faction_id := _shop_card_faction_id(card)
	match Shop.card_effect(card):
		Shop.EFFECT_JACK:
			if faction_id == Factions.Id.SPADES:
				for board_faction in Factions.ALL:
					if _has_valid_jack_pushes(peer_id, board_faction):
						return true
				return false
			return _has_valid_jack_pushes(peer_id, faction_id)
		Shop.EFFECT_KING:
			if faction_id == Factions.Id.SPADES:
				for board_faction in Factions.ALL:
					if _has_valid_king_deploys(peer_id, board_faction):
						return true
				return false
			return _has_valid_king_deploys(peer_id, faction_id)
		Shop.EFFECT_QUEEN:
			if faction_id == Factions.Id.SPADES:
				for board_faction in Factions.ALL:
					if faction_has_dominance(board_faction) and _has_queen_map_actions(
						peer_id,
						board_faction
					):
						return true
				return false
			if not faction_has_dominance(faction_id):
				return false
			return _has_queen_map_actions(peer_id, faction_id)
	return true


func can_buy_shop_slot(peer_id: int, slot_index: int) -> bool:
	return get_shop_slot_block_reason(peer_id, slot_index).is_empty()


func get_shop_slot_block_reason(peer_id: int, slot_index: int) -> String:
	if current_phase != Phase.SPEND_ACTIONS:
		return "Shop purchases are only available during the action phase."
	if not is_action_turn_for_control():
		return "Wait for your action turn to buy from the shop."
	if int(peer_id) != int(get_control_peer_id()):
		return "Shop purchases are only available for the active player."
	if int(peer_id) != int(action_turn_peer_id):
		return "Shop purchases are only allowed on your action turn."
	if _has_pending_shop_action(peer_id):
		return "Complete your current shop purchase on the map first."
	if slot_index < 0 or slot_index >= Shop.SLOT_COUNT:
		return "That shop slot is invalid."

	var slot: Dictionary = _shop_slot(slot_index)
	var card: Dictionary = _shop_slot_card(slot)
	if slot.is_empty() or card.is_empty():
		return "That shop slot is empty."

	var cost := int(slot.get("cost", Shop.slot_cost(slot_index)))
	if int(player_coins.get(peer_id, 0)) < cost:
		return "Not enough coins for that shop card."

	if not can_purchase_shop_card(card):
		var card_faction_id := _shop_card_faction_id(card)
		match Shop.card_effect(card):
			Shop.EFFECT_QUEEN:
				if card_faction_id == Factions.Id.SPADES:
					return "That wild Queen needs at least one dominated hex on the board."
				return "%s needs a dominated hex before that Queen can be bought." % Factions.name_for(
					card_faction_id
				)
			Shop.EFFECT_JACK:
				if card_faction_id == Factions.Id.SPADES:
					return "That wild Jack needs cubes from at least one faction on the board."
				return "%s needs cubes on the board before that Jack can be bought." % Factions.name_for(
					card_faction_id
				)
			Shop.EFFECT_KING:
				return "That shop card cannot be purchased right now."
		return "That shop card cannot be purchased right now."

	if not shop_purchase_has_valid_follow_up(peer_id, card):
		match Shop.card_effect(card):
			Shop.EFFECT_QUEEN:
				return "That Queen has no legal Push, Pull, or Cart follow-up right now."
			Shop.EFFECT_JACK:
				return "That Jack has no legal cube push right now."
			Shop.EFFECT_KING:
				return "That King has no legal deploy space right now."
		return "That shop card has no legal follow-up action right now."

	return ""


func notify_ui_message(message: String) -> void:
	game_message.emit(message)


func _has_valid_jack_pushes(peer_id: int, faction_id: int) -> bool:
	if not faction_has_cubes_on_board(faction_id):
		return false
	if not player_can_act_with_faction(peer_id, faction_id):
		return false
	for from_hex in get_hexes_with_faction_cubes(faction_id):
		if get_faction_cubes_on_hex(from_hex, faction_id) <= 0:
			continue
		for to_hex in get_adjacent_hexes(from_hex):
			if get_available_cube_space(faction_id, to_hex) > 0:
				return true
	return false


func _has_valid_king_deploys(peer_id: int, faction_id: int) -> bool:
	if not player_can_act_with_faction(peer_id, faction_id):
		return false
	return not get_hexes_with_deploy_space(faction_id).is_empty()


func _has_queen_map_actions(_peer_id: int, faction_id: int) -> bool:
	for hex_index in range(HexBoard.HEX_COUNT):
		if get_controlling_faction(hex_index) != faction_id:
			continue
		var available_cubes := get_faction_cubes_on_hex(hex_index, faction_id)
		if available_cubes > 0:
			for target_hex in get_adjacent_hexes(hex_index):
				if get_available_cube_space(faction_id, target_hex) > 0:
					return true
		for source_hex in get_adjacent_hexes(hex_index):
			if get_faction_cubes_on_hex(source_hex, faction_id) <= 0:
				continue
			if get_available_cube_space(faction_id, hex_index) > 0:
				return true
		if hex_index in HexBoard.MOUNTAIN_HEXES and available_cubes > 0:
			return true
	return false


func get_pending_shop_deploy_faction() -> int:
	if _pending_shop_action.is_empty():
		return -1

	var card_faction := int(_pending_shop_action.get("faction_id", -1))
	var deploy_faction := int(_pending_shop_action.get("deploy_faction_id", -1))
	if card_faction == Factions.Id.SPADES:
		if deploy_faction in Factions.ALL:
			return deploy_faction
		return -1

	if deploy_faction in Factions.ALL:
		return deploy_faction
	if card_faction in Factions.ALL:
		return card_faction
	return -1


func pending_shop_needs_faction_choice() -> bool:
	if _pending_shop_action.is_empty():
		return false
	if int(_pending_shop_action.get("faction_id", -1)) != Factions.Id.SPADES:
		return false
	var deploy_faction := int(_pending_shop_action.get("deploy_faction_id", -1))
	return deploy_faction not in Factions.ALL


func get_pending_shop_effect() -> String:
	if _pending_shop_action.is_empty():
		return ""
	return str(_pending_shop_action.get("effect", Shop.EFFECT_QUEEN))


func get_faction_cubes_on_hex(hex_index: int, faction_id: int) -> int:
	return _board.cube_count_for(faction_id, hex_index)


func get_adjacent_hexes(hex_index: int) -> Array:
	return HexBoard.ADJACENCY.get(hex_index, []).duplicate()


func is_faction_influence_locked(peer_id: int, faction_id: int) -> bool:
	if faction_id not in Factions.ALL:
		return false

	var my_influence := RemixRules.faction_dict_value(
		player_influence.get(peer_id, RemixRules.empty_influence()),
		faction_id
	)
	for opponent_id in active_player_order:
		var opponent := int(opponent_id)
		if opponent == int(peer_id):
			continue
		var opponent_influence := RemixRules.faction_dict_value(
			player_influence.get(opponent, RemixRules.empty_influence()),
			faction_id
		)
		if opponent_influence - my_influence >= RemixRules.INFLUENCE_ACTION_LOCK_GAP:
			return true
	return false


func player_can_act_with_faction(peer_id: int, faction_id: int) -> bool:
	if faction_id not in Factions.ALL:
		return true
	if _has_queen_shop_bypass(peer_id, faction_id):
		return true
	return not is_faction_influence_locked(peer_id, faction_id)


func player_can_afford_action(peer_id: int, faction_id: int) -> bool:
	if _has_pending_shop_action(peer_id):
		if get_pending_shop_effect() != Shop.EFFECT_QUEEN:
			return false
		return _pending_shop_action_matches_faction(faction_id)
	if not player_can_act_with_faction(peer_id, faction_id):
		return false
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	if RemixRules.faction_dict_value(tokens, faction_id) > 0:
		return true
	if RemixRules.faction_dict_value(tokens, Factions.Id.SPADES) > 0:
		return true
	return ActionSystem.can_afford(int(action_points.get(peer_id, 0)))


func player_can_afford_any_action(peer_id: int) -> bool:
	if _has_pending_shop_action(peer_id):
		return true
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	for faction in Factions.SHOP_FACTIONS:
		if RemixRules.faction_dict_value(tokens, faction) <= 0:
			continue
		if faction == Factions.Id.SPADES:
			for board_faction in Factions.ALL:
				if player_can_act_with_faction(peer_id, board_faction):
					return true
		elif player_can_act_with_faction(peer_id, faction):
			return true
	if ActionSystem.can_afford(get_action_points_for_peer(peer_id)):
		for board_faction in Factions.ALL:
			if player_can_act_with_faction(peer_id, board_faction):
				return true
	return false


func has_pending_shop_action(peer_id: int = -1) -> bool:
	return _has_pending_shop_action(peer_id)


func get_pending_shop_action() -> Dictionary:
	return _pending_shop_action.duplicate(true)


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

	var target_peer := _offline_turn_peer()
	if target_peer == 0:
		return
	if is_ai_peer(target_peer):
		AiController.request_turn()
		return

	set_active_control_peer(target_peer)


func _offline_turn_peer() -> int:
	match current_phase:
		Phase.DISCARD_TO_CRIB:
			for peer_id in active_player_order:
				if not bool(discard_ready.get(int(peer_id), false)):
					return int(peer_id)
		Phase.SETUP_MINI_CRIB:
			return crib_resolver_peer_id
		Phase.PEGGING:
			return pegging_turn_peer
		Phase.SPEND_ACTIONS:
			return action_turn_peer_id
		Phase.RESOLVE_CRIB:
			return crib_resolver_peer_id
	return 0


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
	_broadcast_coins()
	_sync_action_points.rpc(action_points)
	_sync_faction_actions.rpc(player_faction_actions)
	_sync_faction_scores.rpc(faction_scores, faction_score_recency)
	_ensure_board_setup()
	_broadcast_board()
	lobby_updated.emit()
	_try_auto_start_online_round()


func _try_auto_start_online_round() -> void:
	if not NetworkManager.is_server() or NetworkManager.is_offline_debug():
		return
	if current_phase != Phase.WAITING:
		return
	if get_player_count() < RemixRules.MIN_PLAYERS:
		return

	_broadcast_message(
		"Starting round with %d players." % get_player_count()
	)
	start_new_round()


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
	_broadcast_cut_card_clear()
	action_turn_peer_id = 0
	action_players_finished.clear()
	local_crib.clear()
	mini_crib_index = 0
	mini_crib_resolving_peer = 0
	mini_crib_cards.clear()
	mini_crib_resolved.clear()
	end_crib_resolved.clear()
	crib_resolver_peer_id = 0
	_mini_cribs_completed_for_round = false
	local_crib_resolved.clear()
	pegging_total = 0
	pegging_sequence.clear()
	pegging_turn_peer = 0
	pegging_last_play_peer = 0
	discard_ready.clear()
	crib_owner_peer_id = 0
	show_hands.clear()
	_clear_and_sync_crib_discards()
	if round_number == 1:
		_setup_face_card_shop()
	else:
		_refill_empty_shop_slots()
		if multiplayer.is_server():
			_broadcast_shop_state()
	_deck.clear()

	for peer_id in player_names.keys():
		action_points[peer_id] = 0

	_rotate_dealer()
	crib_owner_peer_id = dealer_peer_id
	_broadcast_round_context()
	if round_number == 1:
		_begin_mini_crib_setup()
	else:
		_mini_cribs_completed_for_round = true
		_set_phase(Phase.DEAL)
		_deal_cards()
	round_started.emit(round_number)
	_apply_action_points(action_points)
	_sync_action_points.rpc(action_points)


@rpc("any_peer", "call_remote", "reliable")
func request_discard(card_indices: Array) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.DISCARD_TO_CRIB:
		return

	var peer_id := int(_action_peer_id())
	if bool(discard_ready.get(peer_id, false)):
		return

	var expected := RemixRules.crib_discard_count(get_player_count())
	if card_indices.size() != expected:
		return

	var hand: Array = hands.get(peer_id, []).duplicate(true)
	if not _validate_card_indices(hand, card_indices):
		return

	var sorted_indices: Array = card_indices.duplicate()
	sorted_indices.sort()
	var discarded_to_crib: Array = []
	for index in sorted_indices:
		discarded_to_crib.append(hand[index].duplicate(true))
	sorted_indices.reverse()
	for index in sorted_indices:
		crib.append(hand[index])
		hand.remove_at(index)

	hands[peer_id] = hand
	player_crib_discards[peer_id] = discarded_to_crib
	discard_ready[peer_id] = true
	_send_local_hand(peer_id, hand)
	_broadcast_crib_discards()
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
	var played_to_thirty_one := pegging_total == PeggingRules.MAX_TOTAL

	for event in PeggingRules.score_events(pegging_sequence, pegging_total):
		grant_pegging_coins(peer_id, event)

	_send_local_hand(peer_id, hand)

	if _all_hands_empty():
		_broadcast_pegging_state(pegging_total)
		if not played_to_thirty_one:
			grant_pegging_coins(peer_id, "last_card")
			_schedule_finish_pegging(1.1)
		else:
			pegging_total = 0
			pegging_sequence.clear()
			_finish_pegging()
		return

	if played_to_thirty_one:
		_broadcast_pegging_state(pegging_total)
		pegging_total = 0
		pegging_sequence.clear()
	else:
		_broadcast_pegging_state()

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

	var forced_peer := _peer_who_must_play_after_pass(peer_id)
	if forced_peer >= 0:
		pegging_turn_peer = forced_peer
		_broadcast_pegging_state()
		return

	if (
		not pegging_sequence.is_empty()
		and pegging_last_play_peer != 0
		and _count_players_with_cards() >= 2
	):
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
	if is_ai_search_silence():
		return
	_broadcast_coins()
	_broadcast_pegging_score(peer_id, event_type, gained)


func _broadcast_pegging_score(peer_id: int, event_type: String, points: int) -> void:
	_apply_pegging_score(peer_id, event_type, points)
	_sync_pegging_score.rpc(peer_id, event_type, points)


func _apply_pegging_score(peer_id: int, event_type: String, points: int) -> void:
	if is_ai_search_silence():
		return
	pegging_score_scored.emit(peer_id, event_type, points)


@rpc("any_peer", "call_remote", "reliable")
func request_shop_slot_purchase(slot_index: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := _action_peer_id()
	var block_reason := get_shop_slot_block_reason(peer_id, slot_index)
	if not block_reason.is_empty():
		_broadcast_message(block_reason)
		return

	var slot: Dictionary = _shop_slot(slot_index)
	var cost := int(slot.get("cost", Shop.slot_cost(slot_index)))
	var coins := int(player_coins.get(peer_id, 0))
	var card: Dictionary = _shop_slot_card(slot).duplicate(true)
	var faction_id := _shop_card_faction_id(card)
	var effect := Shop.card_effect(card)

	_record_action_undo_snapshot(peer_id)

	player_coins[peer_id] = coins - cost
	slot["card"] = {}
	var deploy_faction_id := -1
	if faction_id in Factions.ALL:
		deploy_faction_id = faction_id
	_pending_shop_action = {
		"peer_id": peer_id,
		"faction_id": faction_id,
		"effect": effect,
		"deploy_faction_id": deploy_faction_id,
		"slot_index": slot_index,
		"cost": cost,
		"card": card,
	}

	_broadcast_coins()
	_broadcast_shop_state()
	_broadcast_pending_shop_action()
	_emit_undo_availability()

	var player_name: String = player_names.get(peer_id, "Player %d" % peer_id)
	var card_label := CribbageDeck.card_label(card)
	match effect:
		Shop.EFFECT_JACK:
			if faction_id == Factions.Id.SPADES:
				_broadcast_message(
					"%s bought %s for %d coins — choose a faction, then push 1 cube (ignoring dominance)."
					% [player_name, card_label, cost]
				)
			else:
				_broadcast_message(
					"%s bought %s for %d coins — push 1 %s cube (ignoring dominance)."
					% [player_name, card_label, cost, Factions.name_for(faction_id)]
				)
		Shop.EFFECT_KING:
			if faction_id == Factions.Id.SPADES:
				_broadcast_message(
					"%s bought %s for %d coins — choose a faction, then deploy 1 cube."
					% [player_name, card_label, cost]
				)
			else:
				_broadcast_message(
					"%s bought %s for %d coins — deploy 1 %s cube to any hex."
					% [player_name, card_label, cost, Factions.name_for(faction_id)]
				)
		_:
			var token_name := Factions.name_for(faction_id)
			_broadcast_message(
				"%s bought %s for %d coins — take a %s action on the map."
				% [player_name, card_label, cost, token_name]
			)


@rpc("any_peer", "call_remote", "reliable")
func request_shop_deploy_faction(faction_id: int) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SPEND_ACTIONS:
		return

	var peer_id := _action_peer_id()
	if peer_id != action_turn_peer_id:
		return
	if not _has_pending_shop_action(peer_id):
		return
	if int(_pending_shop_action.get("faction_id", -1)) != Factions.Id.SPADES:
		return
	if faction_id not in Factions.ALL:
		return

	var effect := get_pending_shop_effect()
	if effect not in [Shop.EFFECT_JACK, Shop.EFFECT_KING]:
		return
	if effect == Shop.EFFECT_JACK and not faction_has_cubes_on_board(faction_id):
		return

	_pending_shop_action["deploy_faction_id"] = faction_id
	_broadcast_pending_shop_action()


@rpc("any_peer", "call_remote", "reliable")
func request_shop_jack_push(from_hex: int, to_hex: int) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SPEND_ACTIONS:
		return

	var peer_id := _action_peer_id()
	if peer_id != action_turn_peer_id:
		return
	if not _has_pending_shop_action(peer_id):
		return
	if get_pending_shop_effect() != Shop.EFFECT_JACK:
		return

	var deploy_faction := get_pending_shop_deploy_faction()
	if deploy_faction < 0:
		return
	if not player_can_act_with_faction(peer_id, deploy_faction):
		return
	if from_hex < 0 or to_hex < 0:
		return
	if from_hex == to_hex:
		return
	if to_hex not in HexBoard.ADJACENCY.get(from_hex, []):
		return

	_record_action_undo_snapshot(peer_id)

	if not _board.push_cube_ignoring_dominance(deploy_faction, from_hex, to_hex):
		_action_undo_stack.pop_back()
		_emit_undo_availability()
		return

	_clear_pending_shop_action()
	_broadcast_board()
	_emit_undo_availability()
	_notify_action_cube_anim(deploy_faction, from_hex, to_hex, 1)


@rpc("any_peer", "call_remote", "reliable")
func request_shop_king_deploy(hex_index: int) -> void:
	if not multiplayer.is_server():
		return
	if current_phase != Phase.SPEND_ACTIONS:
		return

	var peer_id := _action_peer_id()
	if peer_id != action_turn_peer_id:
		return
	if not _has_pending_shop_action(peer_id):
		return
	if get_pending_shop_effect() != Shop.EFFECT_KING:
		return

	var deploy_faction := get_pending_shop_deploy_faction()
	if deploy_faction < 0:
		return
	if not player_can_act_with_faction(peer_id, deploy_faction):
		return
	if hex_index < 0 or hex_index >= HexBoard.HEX_COUNT:
		return

	_record_action_undo_snapshot(peer_id)

	if not _board.deploy_cube(deploy_faction, hex_index):
		_action_undo_stack.pop_back()
		_emit_undo_availability()
		return

	_clear_pending_shop_action()
	_broadcast_board()
	_emit_undo_availability()


@rpc("any_peer", "call_remote", "reliable")
func request_end_shop_phase() -> void:
	pass


func _begin_action_phase() -> void:
	action_players_finished.clear()
	for peer_id in active_player_order:
		action_players_finished[int(peer_id)] = false

	action_turn_peer_id = _first_action_peer()
	_clear_action_undo_stack()
	_clear_pending_shop_action()
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

	var using_shop_action := _has_pending_shop_action(peer_id)
	if using_shop_action:
		if get_pending_shop_effect() != Shop.EFFECT_QUEEN:
			return
		if not _pending_shop_action_matches_faction(faction_id):
			return
	elif _affordable_action_count(peer_id, faction_id) < 1:
		return

	match action_type:
		ActionSystem.Type.PUSH, ActionSystem.Type.PULL:
			if cube_count < 1:
				return
			var available_cubes := _board.cube_count_for(faction_id, cube_hex)
			move_count = mini(cube_count, available_cubes)
			var dest_hex := target_hex if action_type == ActionSystem.Type.PUSH else hex_index
			move_count = mini(move_count, _board.available_cube_space(faction_id, dest_hex))
			if move_count <= 0:
				return
		ActionSystem.Type.CREATE_CART:
			move_count = 1

	_record_action_undo_snapshot(peer_id)

	var spend_result: Dictionary
	if using_shop_action:
		spend_result = {
			"spent": true,
			"used_faction_token": false,
			"used_wild_token": false,
			"used_shop_action": true,
		}
	else:
		spend_result = _spend_for_faction_action(peer_id, faction_id)
	if not spend_result.spent:
		_action_undo_stack.pop_back()
		_emit_undo_availability()
		return

	_board.clear_last_cart_move()

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
		if not using_shop_action:
			_refund_faction_action(
				peer_id,
				faction_id,
				spend_result.used_faction_token,
				spend_result.get("used_wild_token", false)
			)
		_action_undo_stack.pop_back()
		_emit_undo_availability()
		return

	if using_shop_action:
		_clear_pending_shop_action()

	var cart_scores := _board.score_carts_on_goal()
	_apply_faction_scores(cart_scores)

	var anim_from_hex := -1
	var anim_to_hex := -1
	if action_type == ActionSystem.Type.PUSH and move_count > 0:
		anim_from_hex = hex_index
		anim_to_hex = target_hex
	elif action_type == ActionSystem.Type.PULL and move_count > 0:
		anim_from_hex = target_hex
		anim_to_hex = hex_index

	if anim_from_hex >= 0:
		_notify_action_cube_anim(faction_id, anim_from_hex, anim_to_hex, move_count)

	if bool(_board.last_cart_move.get("moved", false)):
		var cart_move: Dictionary = _board.last_cart_move
		_notify_action_cart_anim(
			int(cart_move.get("faction", -1)),
			int(cart_move.get("from_hex", -1)),
			int(cart_move.get("to_hex", -1)),
			int(cart_move.get("origin_hex", -1))
		)

	_broadcast_board()
	_emit_undo_availability()


@rpc("authority", "call_remote", "reliable")
func _sync_undo_availability(can_undo: bool) -> void:
	if multiplayer.is_server():
		return
	action_history_changed.emit(can_undo)


func _emit_undo_availability() -> void:
	if is_ai_search_silence():
		return
	var can_undo := can_undo_action()
	action_history_changed.emit(can_undo)
	if multiplayer.is_server():
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

	var snapshot: Dictionary = _action_undo_stack[_action_undo_stack.size() - 1]
	if int(snapshot.get("peer_id", -1)) != int(action_turn_peer_id):
		_clear_action_undo_stack()
		return

	_action_undo_stack.pop_back()
	_board.load_state(snapshot.get("board", []))
	action_points = snapshot.get("action_points", action_points)
	player_faction_actions = snapshot.get("player_faction_actions", player_faction_actions)
	player_coins = snapshot.get("player_coins", player_coins)
	shop_slots = snapshot.get("shop_slots", shop_slots)
	_pending_shop_action = snapshot.get("pending_shop_action", {}).duplicate(true)
	faction_scores = snapshot.get("faction_scores", faction_scores)
	faction_score_recency = snapshot.get("faction_score_recency", faction_score_recency)
	_faction_score_recency_counter = int(snapshot.get("faction_score_recency_counter", _faction_score_recency_counter))
	_apply_action_points(action_points)
	_apply_faction_scores_state(faction_scores, faction_score_recency)
	_broadcast_coins()
	_sync_action_points.rpc(action_points)
	_sync_faction_actions.rpc(player_faction_actions)
	_sync_faction_scores.rpc(faction_scores, faction_score_recency)
	_broadcast_shop_state()
	_broadcast_pending_shop_action()
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
	if _has_pending_shop_action(peer_id):
		_broadcast_message("Complete your shop purchase action on the map first.")
		return

	action_players_finished[peer_id] = true
	_clear_action_undo_stack()
	if _all_action_players_finished():
		_begin_crib_resolution()
		return

	_advance_action_turn()


func _all_action_players_finished() -> bool:
	for peer_id in active_player_order:
		if not bool(action_players_finished.get(int(peer_id), false)):
			return false
	return true


func _advance_action_turn() -> void:
	var next_peer := _next_action_player()
	if next_peer < 0:
		_clear_action_undo_stack()
		_begin_crib_resolution()
		return

	_clear_action_undo_stack()
	action_turn_peer_id = next_peer
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
		var candidate: int = int(peers[(start_index + step) % peers.size()])
		if not bool(action_players_finished.get(candidate, false)):
			return candidate

	return -1


func _begin_crib_resolution() -> void:
	_clear_action_undo_stack()
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
		return int(dealer_peer_id)
	return int(_non_dealer_peer())


func _advance_mini_crib() -> void:
	if is_ai_search_silence():
		return
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
	mini_crib_index = 0
	local_crib.clear()
	local_crib_resolved.clear()
	_mini_cribs_completed_for_round = true
	_set_phase(Phase.DEAL)
	_deal_cards()


func _broadcast_crib_resolution_state(
	cards: Array,
	resolved: Dictionary,
	resolver_peer: int
) -> void:
	if is_ai_search_silence():
		return
	crib_resolver_peer_id = resolver_peer
	if current_phase == Phase.SETUP_MINI_CRIB:
		mini_crib_resolving_peer = resolver_peer

	if offline_debug_mode:
		local_crib = cards.duplicate(true)
		local_crib_resolved = resolved.duplicate(true)
		crib_resolution_updated.emit(local_crib, local_crib_resolved, resolver_peer)
		_update_offline_active_player()
		return

	if not multiplayer.is_server():
		return

	_sync_crib_resolver.rpc(resolver_peer)

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
			if int(peer_id) != int(mini_crib_resolving_peer):
				return
			cards = mini_crib_cards
			resolved = mini_crib_resolved
			required_accepts = 1
			total_cards = MINI_CRIB_SIZE
		Phase.RESOLVE_CRIB:
			if int(peer_id) != int(crib_owner_peer_id):
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
	if not _is_valid_crib_resolution_progress(
		resolved,
		temp_resolved[card_index],
		required_accepts,
		total_cards
	):
		if accept and _count_accepts_in_resolved(temp_resolved) > required_accepts:
			_broadcast_message("You can only accept %d crib card(s)." % required_accepts)
		else:
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
	_notify_crib_cube_anim(accept, hex_index, _card_faction_id(card), card_index, peer_id)
	_broadcast_influence()
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


func _is_valid_crib_resolution_progress(
	resolved: Dictionary,
	new_choice: Dictionary,
	required_accepts: int,
	total_cards: int
) -> bool:
	var temp_resolved: Dictionary = resolved.duplicate(true)
	temp_resolved[int(new_choice.get("card_index", -1))] = new_choice

	var accept_count := _count_accepts_in_resolved(temp_resolved)
	if accept_count > required_accepts:
		return false

	var placed_count := temp_resolved.size()
	var remaining_slots := total_cards - placed_count
	if accept_count + remaining_slots < required_accepts:
		return false

	if placed_count == total_cards:
		return accept_count == required_accepts

	return true


func advance_to_shop_phase() -> void:
	if not multiplayer.is_server():
		return
	_begin_action_phase()


func get_total_faction_score() -> int:
	var total := 0
	for faction in Factions.ALL:
		total += int(faction_scores.get(faction, 0))
	return total


func get_factions_by_rank() -> Array:
	var ranked: Array = Factions.ALL.duplicate()
	ranked.sort_custom(func(a: int, b: int) -> bool:
		var score_a := int(faction_scores.get(a, 0))
		var score_b := int(faction_scores.get(b, 0))
		if score_a != score_b:
			return score_a > score_b
		var recency_a := int(faction_score_recency.get(a, 0))
		var recency_b := int(faction_score_recency.get(b, 0))
		if recency_a != recency_b:
			return recency_a > recency_b
		return a < b
	)
	return ranked


func get_faction_rank_map() -> Dictionary:
	var ranks := {}
	var ranked := get_factions_by_rank()
	for rank_index in range(ranked.size()):
		ranks[ranked[rank_index]] = rank_index
	return ranks


func get_crib_discards_for_peer(peer_id: int) -> Array:
	return player_crib_discards.get(peer_id, [])


func get_crib_owner_peer_id() -> int:
	return crib_owner_peer_id


func get_dealer_peer_id() -> int:
	return dealer_peer_id


func get_player_count() -> int:
	return player_names.size()


const DEBUG_SAVE_VERSION := 1
const DEBUG_SAVE_PATH := "user://cribbage_remix_debug_save.json"


func save_debug_snapshot(path: String = DEBUG_SAVE_PATH) -> bool:
	if not offline_debug_mode:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(export_debug_snapshot(), "\t"))
	return true


func load_debug_snapshot(path: String = DEBUG_SAVE_PATH) -> bool:
	if not offline_debug_mode:
		return false
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	return import_debug_snapshot(parsed)


func export_debug_snapshot() -> Dictionary:
	return {
		"version": DEBUG_SAVE_VERSION,
		"current_phase": int(current_phase),
		"round_number": round_number,
		"ending_round_triggered": ending_round_triggered,
		"offline_debug_mode": offline_debug_mode,
		"active_control_peer_id": active_control_peer_id,
		"player_names": player_names.duplicate(),
		"player_influence": _duplicate_player_faction_actions_from(player_influence),
		"player_supply": _duplicate_player_faction_actions_from(player_supply),
		"player_coins": player_coins.duplicate(true),
		"action_points": action_points.duplicate(true),
		"player_faction_actions": _duplicate_player_faction_actions(),
		"faction_scores": faction_scores.duplicate(),
		"faction_score_recency": faction_score_recency.duplicate(),
		"faction_score_recency_counter": _faction_score_recency_counter,
		"dealer_peer_id": dealer_peer_id,
		"crib_owner_peer_id": crib_owner_peer_id,
		"hands": _duplicate_peer_array_dict(hands),
		"crib": crib.duplicate(true),
		"cut_card": cut_card.duplicate(true),
		"action_turn_peer_id": action_turn_peer_id,
		"action_players_finished": action_players_finished.duplicate(true),
		"mini_crib_index": mini_crib_index,
		"mini_crib_resolving_peer": mini_crib_resolving_peer,
		"mini_crib_cards": mini_crib_cards.duplicate(true),
		"mini_crib_resolved": mini_crib_resolved.duplicate(true),
		"end_crib_resolved": end_crib_resolved.duplicate(true),
		"crib_resolver_peer_id": crib_resolver_peer_id,
		"mini_cribs_completed_for_round": _mini_cribs_completed_for_round,
		"pegging_total": pegging_total,
		"pegging_sequence": pegging_sequence.duplicate(true),
		"pegging_turn_peer": pegging_turn_peer,
		"pegging_last_play_peer": pegging_last_play_peer,
		"active_player_order": _normalize_peer_id_array(active_player_order),
		"discard_ready": discard_ready.duplicate(true),
		"show_hands": _duplicate_peer_array_dict(show_hands),
		"player_crib_discards": _duplicate_peer_array_dict(player_crib_discards),
		"board_state": _board.duplicate_state(),
		"deck": _deck.duplicate(true),
		"face_card_deck": _face_card_deck.duplicate(true),
		"shop_slots": _duplicate_shop_slots(),
		"pending_shop_action": _pending_shop_action.duplicate(true),
		"board_setup_complete": _board_setup_complete,
	}


func import_debug_snapshot(data: Dictionary, apply_views: bool = true) -> bool:
	if int(data.get("version", 0)) != DEBUG_SAVE_VERSION:
		return false

	current_phase = int(data.get("current_phase", Phase.WAITING)) as Phase
	round_number = int(data.get("round_number", 0))
	ending_round_triggered = bool(data.get("ending_round_triggered", false))
	active_control_peer_id = int(data.get("active_control_peer_id", 1))
	player_names = _normalize_peer_key_dict(data.get("player_names", {}))
	player_influence = _normalize_peer_faction_dicts(data.get("player_influence", {}))
	player_supply = _normalize_peer_faction_dicts(data.get("player_supply", {}))
	player_coins = _normalize_peer_key_dict(data.get("player_coins", {}))
	action_points = _normalize_peer_key_dict(data.get("action_points", {}))
	player_faction_actions = _normalize_peer_faction_dicts(data.get("player_faction_actions", {}))
	faction_scores = RemixRules.normalize_faction_dict(data.get("faction_scores", faction_scores))
	faction_score_recency = RemixRules.normalize_faction_dict(
		data.get("faction_score_recency", faction_score_recency)
	)
	_faction_score_recency_counter = int(data.get("faction_score_recency_counter", 0))
	dealer_peer_id = int(data.get("dealer_peer_id", 1))
	crib_owner_peer_id = int(data.get("crib_owner_peer_id", 0))
	hands = _normalize_peer_array_dict(data.get("hands", {}))
	crib = _variant_array(data.get("crib", []))
	cut_card = data.get("cut_card", {}).duplicate(true) if typeof(data.get("cut_card", {})) == TYPE_DICTIONARY else {}
	action_turn_peer_id = int(data.get("action_turn_peer_id", 0))
	action_players_finished = _normalize_peer_key_dict(data.get("action_players_finished", {}))
	mini_crib_index = int(data.get("mini_crib_index", 0))
	mini_crib_resolving_peer = int(data.get("mini_crib_resolving_peer", 0))
	mini_crib_cards = _variant_array(data.get("mini_crib_cards", []))
	mini_crib_resolved = _normalize_choice_dict(data.get("mini_crib_resolved", {}))
	end_crib_resolved = _normalize_choice_dict(data.get("end_crib_resolved", {}))
	crib_resolver_peer_id = int(data.get("crib_resolver_peer_id", 0))
	_mini_cribs_completed_for_round = bool(data.get("mini_cribs_completed_for_round", false))
	pegging_total = int(data.get("pegging_total", 0))
	pegging_sequence = _variant_array(data.get("pegging_sequence", []))
	pegging_turn_peer = int(data.get("pegging_turn_peer", 0))
	pegging_last_play_peer = int(data.get("pegging_last_play_peer", 0))
	active_player_order = _normalize_peer_id_array(_variant_array(data.get("active_player_order", [])))
	discard_ready = _normalize_peer_key_dict(data.get("discard_ready", {}))
	show_hands = _normalize_peer_array_dict(data.get("show_hands", {}))
	player_crib_discards = _normalize_peer_array_dict(data.get("player_crib_discards", {}))
	_deck = _variant_array(data.get("deck", []))
	_face_card_deck = _variant_array(data.get("face_card_deck", []))
	shop_slots = _normalize_shop_slots(data.get("shop_slots", shop_slots))
	_pending_shop_action = data.get("pending_shop_action", {}).duplicate(true) if typeof(data.get("pending_shop_action", {})) == TYPE_DICTIONARY else {}
	_board_setup_complete = bool(data.get("board_setup_complete", true))
	_clear_action_undo_stack()

	var board_state := _variant_array(data.get("board_state", []))
	_board.load_state(board_state)
	if apply_views:
		_apply_debug_snapshot_views()
	return true


func _duplicate_peer_array_dict(source: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for peer_id in source.keys():
		copy[peer_id] = source[peer_id].duplicate(true)
	return copy


func _duplicate_player_faction_actions_from(source: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for peer_id in source.keys():
		copy[peer_id] = RemixRules.normalize_faction_dict(source[peer_id])
	return copy


func _normalize_peer_id_array(raw: Array) -> Array:
	var copy: Array = []
	for value in raw:
		copy.append(int(value))
	return copy


func _normalize_peer_key_dict(raw: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for key in raw.keys():
		copy[int(key)] = raw[key]
	return copy


func _normalize_peer_faction_dicts(raw: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for key in raw.keys():
		copy[int(key)] = RemixRules.normalize_faction_dict(raw[key])
	return copy


func _normalize_peer_array_dict(raw: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for key in raw.keys():
		copy[int(key)] = _variant_array(raw[key])
	return copy


func _normalize_choice_dict(raw: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for key in raw.keys():
		var choice = raw[key]
		if typeof(choice) == TYPE_DICTIONARY:
			copy[int(key)] = choice.duplicate(true)
	return copy


func _variant_array(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value.duplicate(true)


func _apply_debug_snapshot_views() -> void:
	_apply_board(_board.duplicate_state(), _board.get_faction_power())
	_apply_phase(current_phase)
	_apply_influence(player_influence)
	supply_updated.emit(player_supply)
	_apply_action_points(action_points)
	coins_updated.emit(player_coins)
	faction_actions_updated.emit(player_faction_actions)
	faction_scores_updated.emit(faction_scores)
	cut_card_updated.emit(cut_card)
	_broadcast_shop_state()
	_broadcast_pending_shop_action()
	action_turn_updated.emit(action_turn_peer_id)
	pegging_state_updated.emit(pegging_sequence, pegging_total, pegging_turn_peer)
	crib_count_updated.emit(crib.size())

	local_hand = hands.get(active_control_peer_id, []).duplicate(true)
	local_hand_updated.emit(local_hand)

	match current_phase:
		Phase.SETUP_MINI_CRIB:
			local_crib = mini_crib_cards.duplicate(true)
			local_crib_resolved = mini_crib_resolved.duplicate(true)
			crib_resolution_updated.emit(local_crib, local_crib_resolved, mini_crib_resolving_peer)
		Phase.RESOLVE_CRIB:
			local_crib = crib.duplicate(true)
			local_crib_resolved = end_crib_resolved.duplicate(true)
			crib_resolution_updated.emit(local_crib, local_crib_resolved, crib_resolver_peer_id)
		_:
			local_crib.clear()
			local_crib_resolved.clear()

	_update_offline_active_player()
	_broadcast_message("Debug snapshot loaded.")


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
	if round_number == 1 and not _mini_cribs_completed_for_round:
		_begin_mini_crib_setup()
		return

	active_player_order = _sorted_peer_ids()
	if _deck.is_empty():
		_deck = CribbageDeck.create_shuffled_deck()
	crib.clear()
	discard_ready.clear()
	_clear_and_sync_crib_discards()

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
	_broadcast_round_context()
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


func _broadcast_cut_card_clear() -> void:
	cut_card.clear()
	cut_card_updated.emit({})
	_sync_cut_card.rpc({})


func _begin_pegging() -> void:
	pegging_sequence.clear()
	pegging_total = 0
	pegging_last_play_peer = 0
	pegging_turn_peer = _non_dealer_peer()
	show_hands.clear()
	for peer_id in active_player_order:
		show_hands[peer_id] = hands.get(peer_id, []).duplicate(true)
	_set_phase(Phase.PEGGING)
	_broadcast_show_hands()
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

	_broadcast_message(
		"Show hands: %s. Spend actions on the map; buy face cards from the shop on your turn."
		% ", ".join(summary_parts)
	)
	_begin_action_phase()


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


func _schedule_finish_pegging(delay_seconds: float) -> void:
	get_tree().create_timer(delay_seconds).timeout.connect(_finish_pegging, CONNECT_ONE_SHOT)


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


func _peer_who_must_play_after_pass(passing_peer: int) -> int:
	for candidate in active_player_order:
		if int(candidate) == int(passing_peer):
			continue
		var other_hand: Array = hands.get(candidate, [])
		if other_hand.is_empty():
			continue
		if PeggingRules.has_any_play(other_hand, pegging_total):
			return int(candidate)
	return -1


func _all_players_discarded() -> bool:
	for peer_id in active_player_order:
		if not bool(discard_ready.get(int(peer_id), false)):
			return false
	return true


func _all_hands_empty() -> bool:
	for peer_id in active_player_order:
		if not hands.get(peer_id, []).is_empty():
			return false
	return true


func _count_players_with_cards() -> int:
	var count := 0
	for peer_id in active_player_order:
		if not hands.get(int(peer_id), []).is_empty():
			count += 1
	return count


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


func _first_action_peer() -> int:
	var peers: Array = active_player_order.duplicate()
	if peers.is_empty():
		return 0
	var crib_index := peers.find(crib_owner_peer_id)
	if crib_index < 0:
		return int(peers[0])
	return int(peers[(crib_index + 1) % peers.size()])


func _sorted_peer_ids() -> Array:
	var peers: Array = player_names.keys()
	peers.sort()
	return peers


func _send_local_hand(peer_id: int, hand: Array) -> void:
	if is_ai_search_silence():
		return
	peer_id = int(peer_id)
	if offline_debug_mode:
		if peer_id == active_control_peer_id:
			local_hand = hand.duplicate(true)
			local_hand_updated.emit(local_hand)
		return

	if peer_id == multiplayer.get_unique_id():
		local_hand = hand.duplicate(true)
		local_hand_updated.emit(local_hand)
	else:
		_sync_local_hand.rpc_id(peer_id, hand)


func _broadcast_show_hands() -> void:
	show_hands_updated.emit()
	_sync_show_hands.rpc(_duplicate_peer_array_dict(show_hands))


func _broadcast_crib_discards() -> void:
	crib_discards_updated.emit()
	_sync_crib_discards.rpc(_duplicate_peer_array_dict(player_crib_discards))


func _clear_and_sync_crib_discards() -> void:
	player_crib_discards.clear()
	if multiplayer.is_server():
		_broadcast_crib_discards()


func _broadcast_round_context() -> void:
	round_context_updated.emit(dealer_peer_id, crib_owner_peer_id)
	_sync_round_context.rpc(dealer_peer_id, crib_owner_peer_id)


func get_shop_slots() -> Array:
	return _duplicate_shop_slots()


func _setup_face_card_shop() -> void:
	_face_card_deck = CribbageDeck.create_shuffled_face_deck()
	shop_slots.clear()
	for slot_index in range(Shop.SLOT_COUNT):
		shop_slots.append({
			"cost": Shop.slot_cost(slot_index),
			"card": {},
		})
	_refill_empty_shop_slots()
	if multiplayer.is_server():
		_broadcast_shop_state()


func _refill_empty_shop_slots() -> void:
	for slot_index in range(shop_slots.size()):
		_refill_shop_slot(slot_index)


func _refill_shop_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= shop_slots.size():
		return
	var slot: Dictionary = shop_slots[slot_index]
	if not _shop_slot_card(slot).is_empty():
		return
	if _face_card_deck.is_empty():
		return
	slot["card"] = _face_card_deck.pop_back().duplicate(true)


func _compact_shop_after_round() -> void:
	if shop_slots.is_empty():
		return
	Shop.compact_after_round(shop_slots)
	if multiplayer.is_server():
		_broadcast_shop_state()


func _shop_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= shop_slots.size():
		return {}
	return shop_slots[slot_index]


func _shop_slot_card(slot: Dictionary) -> Dictionary:
	var card = slot.get("card", {})
	if typeof(card) != TYPE_DICTIONARY:
		return {}
	return card


func _shop_card_faction_id(card: Dictionary) -> int:
	if card.is_empty():
		return -1
	if card.has("faction"):
		return int(card.get("faction", -1))
	return Factions.from_suit(str(card.get("suit", "")))


func _duplicate_shop_slots() -> Array:
	var copy: Array = []
	for slot in shop_slots:
		var slot_copy: Dictionary = slot.duplicate(true)
		var card: Dictionary = _shop_slot_card(slot)
		slot_copy["card"] = card.duplicate(true) if not card.is_empty() else {}
		copy.append(slot_copy)
	return copy


func _normalize_shop_slots(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return _duplicate_shop_slots()

	var copy: Array = []
	for slot in raw:
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var slot_copy: Dictionary = slot.duplicate(true)
		var card = slot_copy.get("card", {})
		if typeof(card) != TYPE_DICTIONARY:
			slot_copy["card"] = {}
		else:
			slot_copy["card"] = card.duplicate(true)
		copy.append(slot_copy)
	return copy


func _broadcast_shop_state() -> void:
	var slots := _duplicate_shop_slots()
	shop_updated.emit(slots)
	_sync_shop_state.rpc(slots)


func _broadcast_pending_shop_action() -> void:
	if is_ai_search_silence():
		return
	shop_action_pending_updated.emit(_pending_shop_action.duplicate(true))
	_sync_pending_shop_action.rpc(_pending_shop_action.duplicate(true))


func _clear_pending_shop_action() -> void:
	if _pending_shop_action.is_empty():
		return
	_pending_shop_action.clear()
	if multiplayer.is_server():
		_broadcast_pending_shop_action()


func _has_pending_shop_action(peer_id: int = -1) -> bool:
	if _pending_shop_action.is_empty():
		return false
	if peer_id < 0:
		return true
	return int(_pending_shop_action.get("peer_id", -1)) == int(peer_id)


func _pending_shop_action_matches_faction(hex_faction_id: int) -> bool:
	if _pending_shop_action.is_empty():
		return true
	if get_pending_shop_effect() != Shop.EFFECT_QUEEN:
		return false
	var pending_faction := int(_pending_shop_action.get("faction_id", -1))
	if pending_faction == Factions.Id.SPADES:
		return hex_faction_id in Factions.ALL
	return pending_faction == hex_faction_id


func _has_queen_shop_bypass(peer_id: int, faction_id: int) -> bool:
	if not _has_pending_shop_action(peer_id):
		return false
	if get_pending_shop_effect() != Shop.EFFECT_QUEEN:
		return false
	return _pending_shop_action_matches_faction(faction_id)


func _broadcast_faction_actions() -> void:
	if is_ai_search_silence():
		return
	faction_actions_updated.emit(player_faction_actions)
	_sync_faction_actions.rpc(player_faction_actions)


func _broadcast_pegging_state(display_total: int = -1) -> void:
	if is_ai_search_silence():
		return
	var total := pegging_total if display_total < 0 else display_total
	_apply_pegging_state(pegging_sequence, total, pegging_turn_peer)
	_sync_pegging_state.rpc(pegging_sequence, total, pegging_turn_peer)
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
	if multiplayer.is_server() and int(action_turn_peer_id) != int(peer_id):
		_clear_action_undo_stack()
		_clear_pending_shop_action()
	action_turn_peer_id = peer_id
	_update_offline_active_player()
	action_turn_updated.emit(peer_id)


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
	if not _board.can_add_cubes(faction_id, board_hex, 1):
		return false
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
	if not player_can_act_with_faction(peer_id, faction_id):
		return 0
	var count := get_action_points_for_peer(peer_id)
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	count += RemixRules.faction_dict_value(tokens, faction_id)
	count += RemixRules.faction_dict_value(tokens, Factions.Id.SPADES)
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


func _record_action_undo_snapshot(peer_id: int) -> void:
	_action_undo_stack.append({
		"peer_id": peer_id,
		"board": _board.duplicate_state(),
		"action_points": action_points.duplicate(true),
		"player_faction_actions": _duplicate_player_faction_actions(),
		"player_coins": player_coins.duplicate(true),
		"shop_slots": _duplicate_shop_slots(),
		"pending_shop_action": _pending_shop_action.duplicate(true),
		"faction_scores": faction_scores.duplicate(),
		"faction_score_recency": faction_score_recency.duplicate(),
		"faction_score_recency_counter": _faction_score_recency_counter,
	})


func _duplicate_player_faction_actions() -> Dictionary:
	var copy: Dictionary = {}
	for peer_id in player_faction_actions.keys():
		copy[peer_id] = player_faction_actions[peer_id].duplicate(true)
	return copy


func _clear_action_undo_stack() -> void:
	if not multiplayer.is_server():
		return
	_action_undo_stack.clear()
	_emit_undo_availability()


func _spend_for_faction_action(peer_id: int, faction_id: int) -> Dictionary:
	var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
	var faction_count := RemixRules.faction_dict_value(tokens, faction_id)
	if faction_count > 0:
		tokens[faction_id] = faction_count - 1
		player_faction_actions[peer_id] = RemixRules.normalize_action_tokens(tokens)
		_broadcast_faction_actions()
		return {"spent": true, "used_faction_token": true, "used_wild_token": false}

	var wild_count := RemixRules.faction_dict_value(tokens, Factions.Id.SPADES)
	if wild_count > 0:
		tokens[Factions.Id.SPADES] = wild_count - 1
		player_faction_actions[peer_id] = RemixRules.normalize_action_tokens(tokens)
		_broadcast_faction_actions()
		return {"spent": true, "used_faction_token": true, "used_wild_token": true}

	if _spend_action_points(peer_id, ActionSystem.ACTION_COST):
		return {"spent": true, "used_faction_token": false, "used_wild_token": false}

	return {"spent": false, "used_faction_token": false, "used_wild_token": false}


func _refund_faction_action(
	peer_id: int,
	faction_id: int,
	used_faction_token: bool,
	used_wild_token: bool = false
) -> void:
	if used_faction_token:
		var tokens: Dictionary = player_faction_actions.get(peer_id, RemixRules.empty_faction_actions())
		if used_wild_token:
			tokens[Factions.Id.SPADES] = RemixRules.faction_dict_value(tokens, Factions.Id.SPADES) + 1
		else:
			tokens[faction_id] = RemixRules.faction_dict_value(tokens, faction_id) + 1
		player_faction_actions[peer_id] = RemixRules.normalize_action_tokens(tokens)
		_broadcast_faction_actions()
	else:
		action_points[peer_id] = action_points.get(peer_id, 0) + ActionSystem.ACTION_COST
		_apply_action_points(action_points)
		_sync_action_points.rpc(action_points)


func _apply_faction_scores(scored: Dictionary) -> void:
	var old_ranks := get_faction_rank_map()
	var scoring_events: Array = []

	for faction in Factions.ALL:
		var points := int(scored.get(faction, 0))
		if points <= 0:
			continue
		faction_scores[faction] = faction_scores.get(faction, 0) + points
		for _i in range(points):
			_faction_score_recency_counter += 1
			faction_score_recency[faction] = _faction_score_recency_counter
		scoring_events.append({"faction_id": faction, "points": points})

	var new_ranks := get_faction_rank_map()

	if is_ai_search_silence():
		return

	for event in scoring_events:
		var faction_id: int = event.get("faction_id", -1)
		var points: int = int(event.get("points", 0))
		if faction_id < 0 or points <= 0:
			continue
		_apply_faction_score_scored(
			faction_id,
			points,
			int(old_ranks.get(faction_id, 0)),
			int(new_ranks.get(faction_id, 0))
		)

	_apply_faction_scores_state(faction_scores, faction_score_recency)
	_sync_faction_scores.rpc(faction_scores, faction_score_recency)

	for event in scoring_events:
		var faction_id: int = event.get("faction_id", -1)
		var points: int = int(event.get("points", 0))
		if faction_id < 0 or points <= 0:
			continue
		_sync_faction_score_scored.rpc(
			faction_id,
			points,
			int(old_ranks.get(faction_id, 0)),
			int(new_ranks.get(faction_id, 0))
		)


func _apply_faction_score_scored(
	faction_id: int,
	points: int,
	old_rank: int,
	new_rank: int
) -> void:
	faction_score_scored.emit(faction_id, points, old_rank, new_rank)


func _apply_faction_scores_state(scores: Dictionary, recency: Dictionary) -> void:
	faction_scores = scores
	faction_score_recency = recency
	faction_scores_updated.emit(faction_scores)


func _finish_round() -> void:
	if is_ai_search_silence():
		return
	_mini_cribs_completed_for_round = false
	_clear_pending_shop_action()
	_compact_shop_after_round()
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
	if not is_ai_search_silence():
		_sync_action_points.rpc(action_points)
	return true


func _apply_action_points(points: Dictionary) -> void:
	action_points = points.duplicate(true)
	if is_ai_search_silence():
		return
	action_points_updated.emit(action_points)


func _broadcast_board() -> void:
	if is_ai_search_silence():
		return
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
	if is_ai_search_silence():
		return
	_sync_phase.rpc(phase)


func _apply_phase(phase: Phase) -> void:
	current_phase = phase
	if is_ai_search_silence():
		return
	phase_changed.emit(phase)
	_update_offline_active_player()


@rpc("authority", "call_remote", "reliable")
func _sync_player_names(names: Dictionary) -> void:
	if multiplayer.is_server():
		return
	player_names = names
	lobby_updated.emit()


func _broadcast_influence() -> void:
	if is_ai_search_silence():
		return
	_apply_influence(player_influence)
	_sync_influence.rpc(player_influence)


func _apply_influence(influence: Dictionary) -> void:
	var copy: Dictionary = {}
	for peer_id in influence.keys():
		copy[int(peer_id)] = RemixRules.normalize_faction_dict(influence[peer_id])
	player_influence = copy
	influence_updated.emit(player_influence)


@rpc("authority", "call_remote", "reliable")
func _sync_influence(influence: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_apply_influence(influence)


@rpc("authority", "call_remote", "reliable")
func _sync_supply(supply: Dictionary) -> void:
	player_supply = supply
	supply_updated.emit(supply)


func _broadcast_coins() -> void:
	if is_ai_search_silence():
		return
	coins_updated.emit(player_coins)
	_sync_coins.rpc(player_coins)


@rpc("authority", "call_remote", "reliable")
func _sync_coins(coins: Dictionary) -> void:
	if multiplayer.is_server():
		return
	player_coins = coins
	coins_updated.emit(coins)


@rpc("authority", "call_remote", "reliable")
func _sync_action_points(points: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_apply_action_points(points)


@rpc("authority", "call_remote", "reliable")
func _sync_faction_actions(actions: Dictionary) -> void:
	if multiplayer.is_server():
		return
	player_faction_actions = actions
	faction_actions_updated.emit(actions)


@rpc("authority", "call_remote", "reliable")
func _sync_shop_state(slots: Array) -> void:
	if multiplayer.is_server():
		return
	shop_slots = slots.duplicate(true)
	shop_updated.emit(_duplicate_shop_slots())


@rpc("authority", "call_remote", "reliable")
func _sync_pending_shop_action(pending: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_pending_shop_action = pending.duplicate(true)
	shop_action_pending_updated.emit(_pending_shop_action.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _sync_board(board_state: Array, faction_power: Dictionary) -> void:
	_apply_board(board_state, faction_power)


@rpc("authority", "call_remote", "reliable")
func _sync_faction_scores(scores: Dictionary, recency: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_apply_faction_scores_state(scores, recency)


@rpc("authority", "call_remote", "reliable")
func _sync_faction_score_scored(
	faction_id: int,
	points: int,
	old_rank: int,
	new_rank: int
) -> void:
	if multiplayer.is_server():
		return
	_apply_faction_score_scored(faction_id, points, old_rank, new_rank)


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
func _sync_crib_resolver(resolver_peer: int) -> void:
	if multiplayer.is_server():
		return
	crib_resolver_peer_id = resolver_peer
	if current_phase == Phase.SETUP_MINI_CRIB:
		mini_crib_resolving_peer = resolver_peer


@rpc("authority", "call_remote", "reliable")
func _sync_crib_resolution(crib_cards: Array, resolved: Dictionary, resolver_peer: int) -> void:
	if multiplayer.is_server():
		return
	local_crib = crib_cards.duplicate(true)
	local_crib_resolved = resolved.duplicate(true)
	crib_resolver_peer_id = resolver_peer
	if current_phase == Phase.SETUP_MINI_CRIB:
		mini_crib_resolving_peer = resolver_peer
	crib_resolution_updated.emit(local_crib, local_crib_resolved, resolver_peer)


@rpc("authority", "call_remote", "reliable")
func _sync_pegging_state(sequence: Array, total: int, turn_peer: int) -> void:
	if multiplayer.is_server():
		return
	_apply_pegging_state(sequence, total, turn_peer)


@rpc("authority", "call_remote", "reliable")
func _sync_pegging_score(peer_id: int, event_type: String, points: int) -> void:
	if multiplayer.is_server():
		return
	_apply_pegging_score(peer_id, event_type, points)


func _notify_crib_cube_anim(
	accept: bool,
	hex_index: int,
	faction_id: int,
	card_index: int,
	peer_id: int
) -> void:
	if is_ai_search_silence():
		return
	crib_cube_anim_requested.emit(accept, hex_index, faction_id, card_index, peer_id)
	_sync_crib_cube_anim.rpc(accept, hex_index, faction_id, card_index, peer_id)


func _notify_action_cube_anim(
	faction_id: int,
	from_hex: int,
	to_hex: int,
	move_count: int
) -> void:
	if is_ai_search_silence():
		return
	action_cube_anim_requested.emit(faction_id, from_hex, to_hex, move_count)
	_sync_action_cube_anim.rpc(faction_id, from_hex, to_hex, move_count)


func _notify_action_cart_anim(
	faction_id: int,
	from_hex: int,
	to_hex: int,
	origin_hex: int
) -> void:
	if is_ai_search_silence():
		return
	action_cart_anim_requested.emit(faction_id, from_hex, to_hex, origin_hex)
	_sync_action_cart_anim.rpc(faction_id, from_hex, to_hex, origin_hex)


@rpc("authority", "call_remote", "reliable")
func _sync_crib_cube_anim(
	accept: bool,
	hex_index: int,
	faction_id: int,
	card_index: int,
	peer_id: int
) -> void:
	if multiplayer.is_server():
		return
	crib_cube_anim_requested.emit(accept, hex_index, faction_id, card_index, peer_id)


@rpc("authority", "call_remote", "reliable")
func _sync_action_cube_anim(
	faction_id: int,
	from_hex: int,
	to_hex: int,
	move_count: int
) -> void:
	if multiplayer.is_server():
		return
	action_cube_anim_requested.emit(faction_id, from_hex, to_hex, move_count)


@rpc("authority", "call_remote", "reliable")
func _sync_action_cart_anim(
	faction_id: int,
	from_hex: int,
	to_hex: int,
	origin_hex: int
) -> void:
	if multiplayer.is_server():
		return
	action_cart_anim_requested.emit(faction_id, from_hex, to_hex, origin_hex)


@rpc("authority", "call_remote", "reliable")
func _sync_show_hands(hands_dict: Dictionary) -> void:
	if multiplayer.is_server():
		return
	show_hands = _normalize_peer_array_dict(hands_dict)
	show_hands_updated.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_crib_discards(discards_dict: Dictionary) -> void:
	if multiplayer.is_server():
		return
	player_crib_discards = _normalize_peer_array_dict(discards_dict)
	crib_discards_updated.emit()


@rpc("authority", "call_remote", "reliable")
func _sync_round_context(dealer: int, crib_owner: int) -> void:
	if multiplayer.is_server():
		return
	dealer_peer_id = dealer
	crib_owner_peer_id = crib_owner
	round_context_updated.emit(dealer_peer_id, crib_owner_peer_id)


@rpc("authority", "call_remote", "reliable")
func _sync_crib_count(count: int) -> void:
	crib_count_updated.emit(count)


@rpc("authority", "call_remote", "reliable")
func _sync_game_message(message: String) -> void:
	game_message.emit(message)
