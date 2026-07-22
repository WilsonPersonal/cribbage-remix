class_name AiMoveGenerator
extends RefCounted

const KIND_DISCARD := "discard"
const KIND_PEGGING_PLAY := "pegging_play"
const KIND_PEGGING_PASS := "pegging_pass"
const KIND_FACTION_ACTION := "faction_action"
const KIND_SHOP_BUY := "shop_buy"
const KIND_SHOP_DEPLOY_FACTION := "shop_deploy_faction"
const KIND_SHOP_KING_DEPLOY := "shop_king_deploy"
const KIND_CRIB_CHOICE := "crib_choice"
const KIND_END_ACTIONS := "end_actions"


static func generate_moves(peer_id: int) -> Array:
	match GameState.current_phase:
		GameState.Phase.DISCARD_TO_CRIB:
			return _generate_discard_moves(peer_id)
		GameState.Phase.PEGGING:
			return _generate_pegging_moves(peer_id)
		GameState.Phase.SPEND_ACTIONS:
			return _generate_action_phase_moves(peer_id)
		GameState.Phase.SETUP_MINI_CRIB, GameState.Phase.RESOLVE_CRIB:
			return _generate_crib_moves(peer_id)
	return []


static func _generate_discard_moves(peer_id: int) -> Array:
	if bool(GameState.discard_ready.get(peer_id, false)):
		return []

	var hand: Array = GameState.get_hand_for_peer(peer_id)
	var expected := RemixRules.crib_discard_count(GameState.get_player_count())
	if hand.size() < expected:
		return []

	var combos: Array = _enumerate_index_combinations(hand.size(), expected, 24)
	var moves: Array = []
	for indices in combos:
		moves.append({
			"kind": KIND_DISCARD,
			"peer_id": peer_id,
			"card_indices": indices,
		})
	return moves


static func _enumerate_index_combinations(size: int, choose: int, max_count: int) -> Array:
	var results: Array = []
	_collect_index_combinations(0, size, choose, [], results, max_count)
	return results


static func _collect_index_combinations(
	start: int,
	size: int,
	remaining: int,
	current: Array,
	results: Array,
	max_count: int
) -> void:
	if results.size() >= max_count:
		return
	if remaining == 0:
		results.append(current.duplicate())
		return
	if start >= size:
		return

	_collect_index_combinations(start + 1, size, remaining, current, results, max_count)
	current.append(start)
	_collect_index_combinations(start + 1, size, remaining - 1, current, results, max_count)
	current.pop_back()


static func _generate_pegging_moves(peer_id: int) -> Array:
	if GameState.pegging_turn_peer != peer_id:
		return []

	var hand: Array = GameState.get_hand_for_peer(peer_id)
	var moves: Array = []
	for hand_index in range(hand.size()):
		if PeggingRules.can_play(hand[hand_index], GameState.pegging_total):
			moves.append({
				"kind": KIND_PEGGING_PLAY,
				"peer_id": peer_id,
				"hand_index": hand_index,
			})

	if moves.is_empty():
		moves.append({"kind": KIND_PEGGING_PASS, "peer_id": peer_id})
	return moves


static func _generate_action_phase_moves(peer_id: int) -> Array:
	if GameState.action_turn_peer_id != peer_id:
		return []

	if GameState.has_pending_shop_action(peer_id):
		return _generate_pending_shop_moves(peer_id)

	var moves: Array = _generate_map_action_moves(peer_id)
	moves.append_array(_generate_shop_buy_moves(peer_id))
	if moves.is_empty() and not GameState.has_pending_shop_action(peer_id):
		moves.append({"kind": KIND_END_ACTIONS, "peer_id": peer_id})
	return moves


static func _generate_pending_shop_moves(peer_id: int) -> Array:
	var moves: Array = []
	var effect := GameState.get_pending_shop_effect()
	if GameState.pending_shop_needs_faction_choice():
		for faction_id in Factions.ALL:
			if effect == Shop.EFFECT_JACK and not _has_jack_map_actions(peer_id, faction_id):
				continue
			if effect == Shop.EFFECT_KING and not _has_valid_king_deploys(peer_id, faction_id):
				continue
			moves.append({
				"kind": KIND_SHOP_DEPLOY_FACTION,
				"peer_id": peer_id,
				"faction_id": faction_id,
			})
		return moves

	var deploy_faction := GameState.get_pending_shop_deploy_faction()
	if deploy_faction < 0:
		return moves

	match effect:
		Shop.EFFECT_JACK:
			moves.append_array(_generate_map_action_moves(peer_id, Shop.EFFECT_JACK))
		Shop.EFFECT_KING:
			if not GameState.player_can_act_with_faction(peer_id, deploy_faction):
				return moves
			for hex_index in GameState.get_hexes_with_deploy_space(deploy_faction):
				moves.append({
					"kind": KIND_SHOP_KING_DEPLOY,
					"peer_id": peer_id,
					"hex_index": hex_index,
					"faction_id": deploy_faction,
				})
	return moves


static func _generate_shop_buy_moves(peer_id: int) -> Array:
	var moves: Array = []
	var coins := int(GameState.player_coins.get(peer_id, 0))
	var slots: Array = GameState.get_shop_slots()
	for slot_index in range(slots.size()):
		var slot: Dictionary = slots[slot_index]
		var card: Dictionary = slot.get("card", {})
		if card.is_empty():
			continue
		var cost := int(slot.get("cost", Shop.slot_cost(slot_index)))
		if coins < cost:
			continue
		if not GameState.can_purchase_shop_card(card):
			continue
		if not GameState.shop_purchase_has_valid_follow_up(peer_id, card):
			continue
		moves.append({
			"kind": KIND_SHOP_BUY,
			"peer_id": peer_id,
			"slot_index": slot_index,
			"card": card.duplicate(true),
		})
	return moves


static func _generate_map_action_moves(peer_id: int, shop_effect: String = "") -> Array:
	var jack_mode := shop_effect == Shop.EFFECT_JACK
	var deploy_faction := -1
	if jack_mode:
		if (
			not GameState.has_pending_shop_action(peer_id)
			or GameState.get_pending_shop_effect() != Shop.EFFECT_JACK
		):
			return []
		deploy_faction = GameState.get_pending_shop_deploy_faction()
		if deploy_faction < 0:
			return []

	var moves: Array = []
	for hex_index in range(HexBoard.HEX_COUNT):
		var faction_id := -1
		if jack_mode:
			faction_id = deploy_faction
			if GameState.get_faction_cubes_on_hex(hex_index, faction_id) <= 0:
				continue
		else:
			faction_id = GameState.get_controlling_faction(hex_index)
			if faction_id < 0:
				continue
		if not GameState.player_can_afford_action(peer_id, faction_id):
			continue

		var available_cubes := GameState.get_faction_cubes_on_hex(hex_index, faction_id)
		if available_cubes > 0:
			for target_hex in GameState.get_adjacent_hexes(hex_index):
				var move_count := mini(
					available_cubes,
					GameState.get_available_cube_space_for_move(
						faction_id,
						target_hex,
						hex_index,
						false
					)
				)
				if move_count > 0:
					moves.append({
						"kind": KIND_FACTION_ACTION,
						"peer_id": peer_id,
						"action_type": ActionSystem.Type.PUSH,
						"hex_index": hex_index,
						"target_hex": target_hex,
						"cube_count": move_count,
						"move_cart_also": false,
						"faction_id": faction_id,
					})
				if not jack_mode and _can_advance_any_cart(faction_id, hex_index, target_hex):
					var cart_move_count := mini(
						available_cubes,
						GameState.get_available_cube_space_for_move(
							faction_id,
							target_hex,
							hex_index,
							true
						)
					)
					if cart_move_count > 0:
						moves.append({
							"kind": KIND_FACTION_ACTION,
							"peer_id": peer_id,
							"action_type": ActionSystem.Type.PUSH,
							"hex_index": hex_index,
							"target_hex": target_hex,
							"cube_count": cart_move_count,
							"move_cart_also": true,
							"faction_id": faction_id,
						})

		if not jack_mode:
			for source_hex in GameState.get_adjacent_hexes(hex_index):
				var source_cubes := GameState.get_faction_cubes_on_hex(source_hex, faction_id)
				var pull_count := mini(
					source_cubes,
					GameState.get_available_cube_space_for_move(
						faction_id,
						hex_index,
						source_hex,
						false
					)
				)
				if pull_count > 0:
					moves.append({
						"kind": KIND_FACTION_ACTION,
						"peer_id": peer_id,
						"action_type": ActionSystem.Type.PULL,
						"hex_index": hex_index,
						"target_hex": source_hex,
						"cube_count": pull_count,
						"move_cart_also": false,
						"faction_id": faction_id,
					})
				if _can_advance_any_cart(faction_id, source_hex, hex_index):
					var cart_pull_count := mini(
						source_cubes,
						GameState.get_available_cube_space_for_move(
							faction_id,
							hex_index,
							source_hex,
							true
						)
					)
					if cart_pull_count > 0:
						moves.append({
							"kind": KIND_FACTION_ACTION,
							"peer_id": peer_id,
							"action_type": ActionSystem.Type.PULL,
							"hex_index": hex_index,
							"target_hex": source_hex,
							"cube_count": cart_pull_count,
							"move_cart_also": true,
							"faction_id": faction_id,
						})

		if hex_index in HexBoard.MOUNTAIN_HEXES and not jack_mode:
			var can_cart := _can_create_cart_on_hex(faction_id, hex_index)
			if can_cart:
				moves.append({
				"kind": KIND_FACTION_ACTION,
				"peer_id": peer_id,
				"action_type": ActionSystem.Type.CREATE_CART,
				"hex_index": hex_index,
				"target_hex": -1,
				"cube_count": 1,
				"move_cart_also": false,
				"faction_id": faction_id,
			})

	return moves


static func _shop_purchase_has_valid_follow_up(peer_id: int, card: Dictionary) -> bool:
	return GameState.shop_purchase_has_valid_follow_up(peer_id, card)


static func has_actionable_moves(peer_id: int) -> bool:
	for move in generate_moves(peer_id):
		if str(move.get("kind", "")) != KIND_END_ACTIONS:
			return true
	return false


static func _can_create_cart_on_hex(faction_id: int, hex_index: int) -> bool:
	return GameState.can_create_cart_on_hex(faction_id, hex_index)


static func _can_advance_any_cart(faction_id: int, from_hex: int, to_hex: int) -> bool:
	var board := HexBoard.new()
	board.load_state(GameState.get_board_state())
	for origin_hex in board.hexes[from_hex]["carts"].get(faction_id, []):
		if board.cart_can_advance(faction_id, from_hex, to_hex, int(origin_hex)):
			return true
	return false


static func _has_jack_map_actions(peer_id: int, faction_id: int) -> bool:
	return GameState._has_jack_map_actions(peer_id, faction_id)


static func _has_valid_king_deploys(peer_id: int, faction_id: int) -> bool:
	return GameState._has_valid_king_deploys(peer_id, faction_id)


static func _shop_card_faction_id(card: Dictionary) -> int:
	if card.has("faction"):
		return int(card["faction"])
	return Factions.from_suit(str(card.get("suit", "clubs")))


static func _generate_crib_moves(peer_id: int) -> Array:
	var cards: Array = []
	var resolved: Dictionary = {}
	var required_accepts := 0

	match GameState.current_phase:
		GameState.Phase.SETUP_MINI_CRIB:
			if peer_id != GameState.crib_resolver_peer_id:
				return []
			cards = GameState.mini_crib_cards
			resolved = GameState.mini_crib_resolved
			required_accepts = 1
		GameState.Phase.RESOLVE_CRIB:
			if peer_id != GameState.crib_owner_peer_id:
				return []
			cards = GameState.crib
			resolved = GameState.end_crib_resolved
			required_accepts = GameState.get_crib_required_accepts()
		_:
			return []

	var ending_crib := (
		GameState.current_phase == GameState.Phase.RESOLVE_CRIB
		and GameState.is_ending_crib_resolution()
	)
	var moves: Array = []
	var accept_count := _count_accepts(resolved)
	for card_index in range(cards.size()):
		if resolved.has(card_index):
			continue
		var card: Dictionary = cards[card_index]
		var faction_id := GameState.get_card_faction_id(card)

		if accept_count < required_accepts:
			for hex_index in range(HexBoard.HEX_COUNT):
				if GameState.get_faction_cubes_on_hex(hex_index, faction_id) <= 0:
					continue
				if not GameState.can_submit_crib_card_choice(
					card_index,
					true,
					hex_index,
					peer_id
				):
					continue
				moves.append({
					"kind": KIND_CRIB_CHOICE,
					"peer_id": peer_id,
					"card_index": card_index,
					"accept": true,
					"hex_index": hex_index,
					"faction_id": faction_id,
				})

		if ending_crib:
			continue

		for hex_index in GameState.get_valid_reject_hexes_for_card(card):
			if not GameState.can_submit_crib_card_choice(
				card_index,
				false,
				hex_index,
				peer_id
			):
				continue
			moves.append({
				"kind": KIND_CRIB_CHOICE,
				"peer_id": peer_id,
				"card_index": card_index,
				"accept": false,
				"hex_index": hex_index,
				"faction_id": faction_id,
			})

	return moves


static func _count_accepts(resolved: Dictionary) -> int:
	var accept_count := 0
	for choice in resolved.values():
		if bool(choice.get("accept", false)):
			accept_count += 1
	return accept_count
