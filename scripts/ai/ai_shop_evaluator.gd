class_name AiShopEvaluator
extends RefCounted

const POWER_COST_MULTIPLIER := 5.0
const MoveGenerator := preload("res://scripts/ai/ai_move_generator.gd")
const Evaluator := preload("res://scripts/ai/ai_evaluator.gd")
const Search := preload("res://scripts/ai/ai_search.gd")
const PowerRating := preload("res://scripts/ai/faction_power_rating.gd")


static func find_worthwhile_shop_sequence(peer_id: int, context: AiContext) -> Array:
	if GameState.has_pending_shop_action(peer_id):
		return []
	if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
		return []

	var buy_moves: Array = MoveGenerator._generate_shop_buy_moves(peer_id)
	if buy_moves.is_empty():
		return []

	var best_sequence: Array = []
	var best_delta := 0.0

	for buy_move in buy_moves:
		var cost := _buy_move_cost(buy_move)
		if cost <= 0:
			continue

		var threshold := POWER_COST_MULTIPLIER * float(cost)
		var candidate := _best_complete_sequence_for_buy(peer_id, buy_move, context)
		var sequence: Array = candidate.get("sequence", [])
		var delta := float(candidate.get("delta", 0.0))
		if sequence.is_empty():
			continue
		if delta > threshold and delta > best_delta:
			best_delta = delta
			best_sequence = sequence

	return best_sequence.duplicate(true)


static func _best_complete_sequence_for_buy(
	peer_id: int,
	buy_move: Dictionary,
	context: AiContext
) -> Dictionary:
	var snapshot := GameState.export_debug_snapshot()
	Search.apply_move(peer_id, buy_move)

	var prefix: Array = [buy_move.duplicate(true)]
	var best_sequence: Array = []
	var best_delta := -INF

	if _is_queen_buy(buy_move):
		best_delta = _ai_power_delta_for_sequence(peer_id, context, prefix, snapshot)
		best_sequence = prefix.duplicate(true)
		var follow_up := _choose_best_follow_up_move(peer_id, context)
		if not follow_up.is_empty():
			var sequence := prefix.duplicate(true)
			sequence.append(follow_up.duplicate(true))
			var delta := _ai_power_delta_for_sequence(peer_id, context, sequence, snapshot)
			if delta > best_delta:
				best_delta = delta
				best_sequence = sequence
		GameState.import_debug_snapshot(snapshot, false)
		return {"sequence": best_sequence, "delta": best_delta}

	if GameState.pending_shop_needs_faction_choice():
		for deploy_move in _shop_deploy_moves(peer_id):
			var deploy_snapshot := GameState.export_debug_snapshot()
			Search.apply_move(peer_id, deploy_move)
			var follow_up := _choose_best_follow_up_move(peer_id, context)
			if follow_up.is_empty():
				GameState.import_debug_snapshot(deploy_snapshot, false)
				continue

			var sequence := prefix.duplicate(true)
			sequence.append(deploy_move.duplicate(true))
			sequence.append(follow_up.duplicate(true))
			var delta := _ai_power_delta_for_sequence(peer_id, context, sequence, snapshot)
			if delta > best_delta:
				best_delta = delta
				best_sequence = sequence
			GameState.import_debug_snapshot(deploy_snapshot, false)
	else:
		var follow_up := _choose_best_follow_up_move(peer_id, context)
		if not follow_up.is_empty():
			var sequence := prefix.duplicate(true)
			sequence.append(follow_up.duplicate(true))
			best_delta = _ai_power_delta_for_sequence(peer_id, context, sequence, snapshot)
			best_sequence = sequence

	GameState.import_debug_snapshot(snapshot, false)
	return {"sequence": best_sequence, "delta": best_delta}


static func _ai_power_delta_for_sequence(
	peer_id: int,
	context: AiContext,
	sequence: Array,
	base_snapshot: Dictionary
) -> float:
	GameState.import_debug_snapshot(base_snapshot, false)
	var before := _ai_power_total(context)
	for move in sequence:
		Search.apply_move(peer_id, move)
	var after := _ai_power_total(context)
	GameState.import_debug_snapshot(base_snapshot, false)
	return after - before


static func _ai_power_total(context: AiContext) -> float:
	var ratings := PowerRating.compute_all(
		GameState.get_board_state(),
		GameState.faction_scores.duplicate()
	)
	return float(
		PowerRating.compute_ai_power(ratings, context.peer_id, context.opponent_id, context)
		.get("total", 0.0)
	)


static func _choose_best_follow_up_move(peer_id: int, context: AiContext) -> Dictionary:
	var moves := _shop_follow_up_moves(MoveGenerator.generate_moves(peer_id))
	if moves.is_empty():
		return {}
	return Evaluator.choose_best_move(moves, context, true)


static func _shop_follow_up_moves(moves: Array) -> Array:
	var filtered: Array = []
	for move in moves:
		var kind := str(move.get("kind", ""))
		if kind in [
			MoveGenerator.KIND_END_ACTIONS,
			MoveGenerator.KIND_SHOP_BUY,
			MoveGenerator.KIND_SHOP_DEPLOY_FACTION,
		]:
			continue
		filtered.append(move)
	return filtered


static func _shop_deploy_moves(peer_id: int) -> Array:
	var filtered: Array = []
	for move in MoveGenerator.generate_moves(peer_id):
		if str(move.get("kind", "")) == MoveGenerator.KIND_SHOP_DEPLOY_FACTION:
			filtered.append(move)
	return filtered


static func _buy_move_cost(buy_move: Dictionary) -> int:
	var slot_index := int(buy_move.get("slot_index", -1))
	if slot_index >= 0:
		var slots: Array = GameState.get_shop_slots()
		if slot_index < slots.size():
			return int(slots[slot_index].get("cost", Shop.slot_cost(slot_index)))
		return Shop.slot_cost(slot_index)
	return 0


static func _is_queen_buy(buy_move: Dictionary) -> bool:
	return Shop.card_effect(buy_move.get("card", {})) == Shop.EFFECT_QUEEN
