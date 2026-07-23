class_name AiShopEvaluator
extends RefCounted

const POWER_COST_MULTIPLIER := 5.0
const QUEEN_SEARCH_DEPTH := 2
const DEBUG_SHOP := false
const MoveGenerator := preload("res://scripts/ai/ai_move_generator.gd")
const Search := preload("res://scripts/ai/ai_search.gd")
const PowerRating := preload("res://scripts/ai/faction_power_rating.gd")

static var _slot_evaluation_cache: Dictionary = {}


static func clear_evaluation_cache() -> void:
	_slot_evaluation_cache.clear()


static func find_worthwhile_shop_sequence(peer_id: int, context: AiContext) -> Array:
	clear_evaluation_cache()
	if GameState.has_pending_shop_action(peer_id):
		_debug("peer=%d skipped: pending shop action" % peer_id)
		return []
	if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
		_debug("peer=%d skipped: not in spend actions phase" % peer_id)
		return []

	var buy_moves: Array = _shop_buy_moves_by_cost(peer_id)
	var coins := int(GameState.player_coins.get(peer_id, 0))
	_debug(
		"peer=%d evaluating shop | coins=%d legal_buys=%d"
		% [peer_id, coins, buy_moves.size()]
	)
	if buy_moves.is_empty():
		return []

	var best_sequence: Array = []
	var best_delta := 0.0

	for buy_move in buy_moves:
		var cost := _buy_move_cost(buy_move)
		if cost <= 0:
			continue

		var card: Dictionary = buy_move.get("card", {})
		var threshold := POWER_COST_MULTIPLIER * float(cost)
		var candidate := _best_complete_sequence_for_buy(peer_id, buy_move, context)
		var sequence: Array = candidate.get("sequence", [])
		var delta := float(candidate.get("delta", 0.0))
		var slot_index := int(buy_move.get("slot_index", -1))
		var worthwhile := (
			not sequence.is_empty()
			and is_finite(delta)
			and delta > threshold
		)
		_debug(
			"  slot=%d %s %s cost=%d delta=%.1f threshold=%.1f seq=%d worthwhile=%s"
			% [
				slot_index,
				Shop.card_effect(card),
				Factions.name_for(GameState.get_card_faction_id(card)),
				cost,
				delta,
				threshold,
				sequence.size(),
				str(worthwhile),
			]
		)
		if sequence.is_empty() or not is_finite(delta):
			continue
		if delta > threshold and delta > best_delta:
			best_delta = delta
			best_sequence = sequence

	if best_sequence.is_empty():
		_debug("peer=%d no worthwhile shop sequence" % peer_id)
		return []

	if not sequence_completes_pending_shop(peer_id, best_sequence):
		_debug("peer=%d rejected incomplete shop sequence" % peer_id)
		return []

	var result := best_sequence.duplicate(true)
	result[0]["_shop_sequence_delta"] = best_delta
	_debug(
		"peer=%d selected shop sequence | delta=%.1f moves=%d follow_up=%s"
		% [
			peer_id,
			best_delta,
			result.size(),
			summarize_shop_sequence_follow_ups(result, Shop.card_effect(result[0].get("card", {}))),
		]
	)
	return result


static func sequence_completes_pending_shop(peer_id: int, sequence: Array) -> bool:
	if sequence.is_empty():
		return false

	var snapshot := GameState.export_debug_snapshot()
	for move in sequence:
		Search.apply_move(peer_id, move)
	var complete := not GameState.has_pending_shop_action(peer_id)
	GameState.import_debug_snapshot(snapshot, false)
	return complete


static func _debug(message: String) -> void:
	if DEBUG_SHOP:
		print("[AI Shop] %s" % message)


static func _slot_cache_key(peer_id: int, buy_move: Dictionary) -> String:
	return "%d|%d" % [peer_id, int(buy_move.get("slot_index", -1))]


static func evaluate_all_shop_buy_deltas(peer_id: int, context: AiContext) -> Array:
	clear_evaluation_cache()
	if GameState.has_pending_shop_action(peer_id):
		return []
	if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
		return []

	var results: Array = []
	for buy_move in _shop_buy_moves_by_cost(peer_id):
		var cost := _buy_move_cost(buy_move)
		var card: Dictionary = buy_move.get("card", {})
		var candidate := _best_complete_sequence_for_buy(peer_id, buy_move, context)
		var delta := float(candidate.get("delta", 0.0))
		var threshold := POWER_COST_MULTIPLIER * float(cost)
		results.append({
			"slot_index": int(buy_move.get("slot_index", -1)),
			"effect": Shop.card_effect(card),
			"faction_id": GameState.get_card_faction_id(card),
			"rank": str(card.get("rank", "")),
			"suit": str(card.get("suit", "")),
			"cost": cost,
			"delta": delta,
			"threshold": threshold,
			"worthwhile": is_finite(delta) and delta > threshold,
			"follow_up_summary": summarize_shop_sequence_follow_ups(
				candidate.get("sequence", []),
				Shop.card_effect(card)
			),
		})

	return results


static func evaluate_move_delta(peer_id: int, move: Dictionary, context: AiContext) -> float:
	if move.is_empty():
		return 0.0
	if move.has("_shop_sequence_delta"):
		return float(move.get("_shop_sequence_delta", 0.0))
	if str(move.get("kind", "")) == MoveGenerator.KIND_SHOP_BUY:
		return float(
			_best_complete_sequence_for_buy(peer_id, move, context).get("delta", 0.0)
		)

	var snapshot := GameState.export_debug_snapshot()
	return _ai_power_delta_for_sequence(
		peer_id,
		context,
		[move.duplicate(true)],
		snapshot
	)


static func evaluate_buy_sequence(peer_id: int, buy_move: Dictionary, context: AiContext) -> Dictionary:
	if str(buy_move.get("kind", "")) != MoveGenerator.KIND_SHOP_BUY:
		return {}
	return _best_complete_sequence_for_buy(peer_id, buy_move, context)


static func _best_complete_sequence_for_buy(
	peer_id: int,
	buy_move: Dictionary,
	context: AiContext
) -> Dictionary:
	var cache_key := _slot_cache_key(peer_id, buy_move)
	if _slot_evaluation_cache.has(cache_key):
		return _slot_evaluation_cache[cache_key].duplicate(true)

	var snapshot := GameState.export_debug_snapshot()
	Search.apply_move(peer_id, buy_move)

	var prefix: Array = [buy_move.duplicate(true)]
	var best := {"sequence": [], "delta": -INF}
	var effect := Shop.card_effect(buy_move.get("card", {}))
	var card_faction := GameState.get_card_faction_id(buy_move.get("card", {}))

	if effect == Shop.EFFECT_QUEEN:
		best = _best_of(
			best,
			_best_queen_map_sequence(peer_id, context, prefix, snapshot, card_faction)
		)
	elif effect == Shop.EFFECT_KING:
		best = _best_of(
			best,
			_best_king_sequence(peer_id, context, prefix, snapshot, card_faction)
		)
	elif effect == Shop.EFFECT_JACK:
		best = _best_of(
			best,
			_best_jack_sequence(peer_id, context, prefix, snapshot, card_faction)
		)

	if best.get("sequence", []).is_empty():
		best = _sequence_result(peer_id, context, prefix, snapshot)

	GameState.import_debug_snapshot(snapshot, false)
	_slot_evaluation_cache[cache_key] = best.duplicate(true)
	return best


static func _best_king_sequence(
	peer_id: int,
	context: AiContext,
	prefix: Array,
	base_snapshot: Dictionary,
	card_faction: int
) -> Dictionary:
	var best := {"sequence": [], "delta": -INF}
	for faction_id in _king_deploy_factions(peer_id, card_faction):
		var sequence_prefix := prefix.duplicate(true)
		if card_faction == Factions.Id.SPADES:
			sequence_prefix.append(_shop_deploy_move(peer_id, faction_id))

		var branch_snapshot := GameState.export_debug_snapshot()
		GameState.import_debug_snapshot(base_snapshot, false)
		for move in sequence_prefix:
			Search.apply_move(peer_id, move)
		for king_move in _shop_king_deploy_moves(peer_id):
			var sequence := sequence_prefix.duplicate(true)
			sequence.append(king_move.duplicate(true))
			best = _best_of(best, _sequence_result(peer_id, context, sequence, base_snapshot))
		GameState.import_debug_snapshot(branch_snapshot, false)

	if best.get("sequence", []).is_empty():
		best = _sequence_result(peer_id, context, prefix, base_snapshot)
	return best


static func _best_jack_sequence(
	peer_id: int,
	context: AiContext,
	prefix: Array,
	base_snapshot: Dictionary,
	card_faction: int
) -> Dictionary:
	var best := {"sequence": [], "delta": -INF}
	for faction_id in _jack_deploy_factions(peer_id, card_faction):
		var sequence_prefix := prefix.duplicate(true)
		if card_faction == Factions.Id.SPADES:
			sequence_prefix.append(_shop_deploy_move(peer_id, faction_id))

		var branch_snapshot := GameState.export_debug_snapshot()
		GameState.import_debug_snapshot(base_snapshot, false)
		for move in sequence_prefix:
			Search.apply_move(peer_id, move)
		for jack_move in _shop_jack_push_moves(peer_id):
			var sequence := sequence_prefix.duplicate(true)
			sequence.append(jack_move.duplicate(true))
			best = _best_of(best, _sequence_result(peer_id, context, sequence, base_snapshot))
		GameState.import_debug_snapshot(branch_snapshot, false)

	if best.get("sequence", []).is_empty():
		best = _sequence_result(peer_id, context, prefix, base_snapshot)
	return best


static func _king_deploy_factions(peer_id: int, card_faction: int) -> Array:
	if card_faction == Factions.Id.SPADES:
		var factions: Array = []
		for faction_id in Factions.ALL:
			if GameState._has_valid_king_deploys(peer_id, faction_id):
				factions.append(faction_id)
		return factions
	if GameState._has_valid_king_deploys(peer_id, card_faction):
		return [card_faction]
	return []


static func _jack_deploy_factions(peer_id: int, card_faction: int) -> Array:
	if card_faction == Factions.Id.SPADES:
		var factions: Array = []
		for faction_id in Factions.ALL:
			if MoveGenerator._has_jack_map_actions(peer_id, faction_id):
				factions.append(faction_id)
		return factions
	if MoveGenerator._has_jack_map_actions(peer_id, card_faction):
		return [card_faction]
	return []


static func _shop_deploy_move(peer_id: int, faction_id: int) -> Dictionary:
	return {
		"kind": MoveGenerator.KIND_SHOP_DEPLOY_FACTION,
		"peer_id": peer_id,
		"faction_id": faction_id,
	}


static func _shop_jack_push_moves(peer_id: int) -> Array:
	return _shop_follow_up_moves(
		MoveGenerator._generate_map_action_moves(peer_id, Shop.EFFECT_JACK)
	)


static func _queen_action_factions(card_faction: int) -> Array:
	if card_faction == Factions.Id.SPADES:
		return Factions.ALL.duplicate()
	if card_faction in Factions.ALL:
		return [card_faction]
	return []


static func _best_queen_map_sequence(
	peer_id: int,
	context: AiContext,
	prefix: Array,
	base_snapshot: Dictionary,
	card_faction: int
) -> Dictionary:
	var best := _sequence_result(peer_id, context, prefix, base_snapshot)
	return _extend_queen_map_sequence(
		peer_id,
		context,
		prefix,
		base_snapshot,
		_queen_action_factions(card_faction),
		QUEEN_SEARCH_DEPTH,
		best
	)


static func _extend_queen_map_sequence(
	peer_id: int,
	context: AiContext,
	prefix: Array,
	base_snapshot: Dictionary,
	allowed_factions: Array,
	depth_remaining: int,
	best: Dictionary
) -> Dictionary:
	if depth_remaining <= 0:
		return best

	GameState.import_debug_snapshot(base_snapshot, false)
	for move in prefix:
		Search.apply_move(peer_id, move)
	var follow_ups := _queen_map_follow_up_moves(peer_id, allowed_factions)
	GameState.import_debug_snapshot(base_snapshot, false)

	for follow_up in follow_ups:
		var sequence := prefix.duplicate(true)
		sequence.append(follow_up.duplicate(true))
		best = _best_of(best, _sequence_result(peer_id, context, sequence, base_snapshot))
		best = _extend_queen_map_sequence(
			peer_id,
			context,
			sequence,
			base_snapshot,
			allowed_factions,
			depth_remaining - 1,
			best
		)
	return best


static func _queen_map_follow_up_moves(peer_id: int, allowed_factions: Array) -> Array:
	return _shop_follow_up_moves(
		MoveGenerator.generate_moves(peer_id),
		allowed_factions
	)


static func _sequence_result(
	peer_id: int,
	context: AiContext,
	sequence: Array,
	base_snapshot: Dictionary
) -> Dictionary:
	var scored := _score_sequence_delta(peer_id, context, sequence, base_snapshot)
	return {
		"sequence": sequence.duplicate(true),
		"delta": float(scored.get("delta", 0.0)),
		"before_ratings": scored.get("before_ratings", {}),
		"after_ratings": scored.get("after_ratings", {}),
		"before_ai": scored.get("before_ai", {}),
		"after_ai": scored.get("after_ai", {}),
	}


static func _best_of(current: Dictionary, candidate: Dictionary) -> Dictionary:
	if float(candidate.get("delta", -INF)) > float(current.get("delta", -INF)):
		return candidate
	return current


static func _score_sequence_delta(
	peer_id: int,
	context: AiContext,
	sequence: Array,
	base_snapshot: Dictionary
) -> Dictionary:
	GameState.import_debug_snapshot(base_snapshot, false)
	var before_ratings := PowerRating.compute_all(
		GameState.get_board_state(),
		GameState.faction_scores.duplicate()
	)
	for move in sequence:
		Search.apply_move(peer_id, move)
	var after_context := AiContext.from_game(peer_id)
	var after_ratings := PowerRating.compute_all(
		GameState.get_board_state(),
		GameState.faction_scores.duplicate()
	)
	var scored := PowerRating.compute_ai_power_delta(
		before_ratings,
		after_ratings,
		peer_id,
		context.opponent_id,
		context,
		after_context,
		null
	)
	GameState.import_debug_snapshot(base_snapshot, false)
	return {
		"delta": float(scored.get("total", 0.0)),
		"before_ratings": before_ratings,
		"after_ratings": after_ratings,
		"before_ai": scored.get("before", {}),
		"after_ai": scored.get("after", {}),
	}


static func _ai_power_delta_for_sequence(
	peer_id: int,
	context: AiContext,
	sequence: Array,
	base_snapshot: Dictionary
) -> float:
	return float(
		_score_sequence_delta(peer_id, context, sequence, base_snapshot).get("delta", 0.0)
	)


static func queen_follow_up_summary(
	peer_id: int,
	buy_move: Dictionary,
	context: AiContext
) -> String:
	var card: Dictionary = buy_move.get("card", {})
	if card.is_empty() or Shop.card_effect(card) != Shop.EFFECT_QUEEN:
		return ""

	var candidate := _best_complete_sequence_for_buy(peer_id, buy_move, context)
	return summarize_sequence_follow_ups(candidate.get("sequence", []), true)


static func summarize_shop_sequence_follow_ups(sequence: Array, effect: String) -> String:
	if sequence.size() <= 1:
		return ""
	if effect == Shop.EFFECT_QUEEN:
		return summarize_sequence_follow_ups(sequence, true)

	var parts: PackedStringArray = PackedStringArray()
	for index in range(1, sequence.size()):
		var move: Dictionary = sequence[index]
		var kind := str(move.get("kind", ""))
		if kind == MoveGenerator.KIND_SHOP_DEPLOY_FACTION:
			parts.append("Deploy %s" % Factions.name_for(int(move.get("faction_id", -1))))
		elif kind == MoveGenerator.KIND_SHOP_KING_DEPLOY:
			parts.append(
				"King deploy %s hex %d"
				% [
					Factions.name_for(int(move.get("faction_id", -1))),
					int(move.get("hex_index", -1)),
				]
			)
		elif kind == MoveGenerator.KIND_FACTION_ACTION:
			parts.append(format_map_move_short(move))
	return ", ".join(parts)


static func summarize_sequence_follow_ups(sequence: Array, queen_only: bool = false) -> String:
	if queen_only and sequence.is_empty():
		return ""

	var parts: PackedStringArray = PackedStringArray()
	for index in range(1, mini(sequence.size(), QUEEN_SEARCH_DEPTH + 1)):
		var move: Dictionary = sequence[index]
		if str(move.get("kind", "")) != MoveGenerator.KIND_FACTION_ACTION:
			continue
		parts.append(format_map_move_short(move))
	return ", ".join(parts)


static func format_map_move_short(move: Dictionary) -> String:
	var action_type := int(move.get("action_type", -1))
	var action_label := "Move"
	match action_type:
		ActionSystem.Type.PUSH:
			action_label = "Push"
		ActionSystem.Type.PULL:
			action_label = "Pull"
		ActionSystem.Type.CREATE_CART:
			action_label = "Cart"

	var from_hex := int(move.get("hex_index", -1))
	var to_hex := int(move.get("target_hex", -1))
	if action_type == ActionSystem.Type.PULL:
		from_hex = int(move.get("target_hex", -1))
		to_hex = int(move.get("hex_index", -1))

	var cart_note := " +cart" if bool(move.get("move_cart_also", false)) else ""
	var faction_id := int(move.get("faction_id", -1))
	var faction_note := ""
	if faction_id in Factions.ALL:
		faction_note = "%s " % Factions.name_for(faction_id)

	return "%s%s%d→%d%s" % [action_label, faction_note, from_hex, to_hex, cart_note]


static func _shop_follow_up_moves(moves: Array, allowed_factions: Array = []) -> Array:
	var filtered: Array = []
	for move in moves:
		var kind := str(move.get("kind", ""))
		if kind in [
			MoveGenerator.KIND_END_ACTIONS,
			MoveGenerator.KIND_SHOP_BUY,
			MoveGenerator.KIND_SHOP_DEPLOY_FACTION,
			MoveGenerator.KIND_SHOP_KING_DEPLOY,
		]:
			continue
		if (
			not allowed_factions.is_empty()
			and kind == MoveGenerator.KIND_FACTION_ACTION
			and int(move.get("faction_id", -1)) not in allowed_factions
		):
			continue
		filtered.append(move)
	return filtered


static func _shop_king_deploy_moves(peer_id: int) -> Array:
	var filtered: Array = []
	for move in MoveGenerator.generate_moves(peer_id):
		if str(move.get("kind", "")) == MoveGenerator.KIND_SHOP_KING_DEPLOY:
			filtered.append(move)
	return filtered


static func format_shop_power_delta(value: float) -> String:
	if not is_finite(value):
		return "no valid sequence"
	if absf(value - roundf(value)) < 0.01:
		return "%.0f" % value
	return "%.1f" % value


static func _shop_buy_moves_by_cost(peer_id: int) -> Array:
	var buy_moves: Array = MoveGenerator._generate_shop_buy_moves(peer_id)
	buy_moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var cost_a := _buy_move_cost(a)
		var cost_b := _buy_move_cost(b)
		if cost_a != cost_b:
			return cost_a < cost_b
		return int(a.get("slot_index", -1)) < int(b.get("slot_index", -1))
	)
	return buy_moves


static func _buy_move_cost(buy_move: Dictionary) -> int:
	var slot_index := int(buy_move.get("slot_index", -1))
	if slot_index >= 0:
		var slots: Array = GameState.get_shop_slots()
		if slot_index < slots.size():
			return int(slots[slot_index].get("cost", Shop.slot_cost(slot_index)))
		return Shop.slot_cost(slot_index)
	return 0
