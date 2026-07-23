class_name AiTurnPlanner
extends RefCounted

const MoveGenerator := preload("res://scripts/ai/ai_move_generator.gd")
const Evaluator := preload("res://scripts/ai/ai_evaluator.gd")
const ContextBuilder := preload("res://scripts/ai/ai_context.gd")
const Search := preload("res://scripts/ai/ai_search.gd")
const ShopEvaluator := preload("res://scripts/ai/ai_shop_evaluator.gd")

const MAX_ACTIONS_PER_TURN := 24
const MAX_CRIB_PLAN_STEPS := 16
const MAX_STALL_ATTEMPTS := 3


static func plan_spend_actions_turn(
	peer_id: int,
	blocked_moves: Dictionary,
	stall_signature: String,
	stall_attempts: int,
	skip_shop: bool = false
) -> Dictionary:
	var planned: Array = []
	var blocked := blocked_moves.duplicate()
	var signature := stall_signature
	var attempts := stall_attempts
	var should_end := false
	var shop_sequence_planned := false
	var turn_snapshot: Dictionary = GameState.export_debug_snapshot()

	GameState.push_ai_search_silence()
	ShopEvaluator.clear_evaluation_cache()
	for _step in range(MAX_ACTIONS_PER_TURN):
		if not _is_spend_actions_turn(peer_id):
			break

		if not skip_shop and not shop_sequence_planned and not GameState.has_pending_shop_action(peer_id):
			var shop_context: AiContext = ContextBuilder.from_game(peer_id)
			var shop_sequence: Array = ShopEvaluator.find_worthwhile_shop_sequence(peer_id, shop_context)
			if not shop_sequence.is_empty():
				shop_sequence_planned = true
				var applied_shop := false
				for shop_move_value in shop_sequence:
					var shop_move: Dictionary = shop_move_value
					if not _is_spend_actions_turn(peer_id):
						break

					var shop_before := _snapshot_action_state(peer_id)
					Search.apply_move(peer_id, shop_move)
					var shop_after := _snapshot_action_state(peer_id)
					if not _action_state_changed(shop_before, shop_after):
						blocked[_move_key(shop_move)] = true
						break

					var shop_delta := float(shop_move.get("_shop_sequence_delta", 0.0))
					if shop_delta == 0.0:
						shop_delta = ShopEvaluator.evaluate_move_delta(
							peer_id,
							shop_move,
							shop_context
						)

					var stored_shop_move: Dictionary = shop_move.duplicate(true)
					stored_shop_move["_decision"] = {
						"method": "shop_power_threshold",
						"chosen_evaluator_score": shop_delta,
						"evaluator_rank": 1,
						"evaluator_total": 1,
						"alternatives": [],
					}
					if str(stored_shop_move.get("kind", "")) == MoveGenerator.KIND_SHOP_BUY:
						stored_shop_move["_queen_follow_up_summary"] = (
							ShopEvaluator.summarize_shop_sequence_follow_ups(
								shop_sequence,
								Shop.card_effect(stored_shop_move.get("card", {}))
							)
						)
					planned.append(stored_shop_move)
					applied_shop = true

				if applied_shop:
					attempts = 0
					if not _is_spend_actions_turn(peer_id):
						break
					if GameState.has_pending_shop_action(peer_id):
						break
					if GameState.get_total_actions_for_peer(peer_id) <= 0:
						break
					if (
						not MoveGenerator.has_actionable_moves(peer_id)
						and not GameState.has_pending_shop_action(peer_id)
					):
						break
					continue

		var moves: Array = _without_shop_buys(
			_filter_blocked_moves(MoveGenerator.generate_moves(peer_id), blocked)
		)
		if moves.is_empty():
			if MoveGenerator.generate_moves(peer_id).is_empty():
				var recovery := _try_recover_stuck_turn(peer_id, signature, attempts)
				if recovery.get("recovered", false):
					signature = recovery.get("signature", signature)
					attempts = int(recovery.get("attempts", attempts))
					continue
			break

		var context: AiContext = ContextBuilder.from_game(peer_id)
		var require_positive := not GameState.has_pending_shop_action(peer_id)
		var decision: Dictionary = Evaluator.choose_move_decision(moves, context, require_positive)
		var move: Dictionary = decision.get("move", {})
		if move.is_empty() or str(move.get("kind", "")) == MoveGenerator.KIND_END_ACTIONS:
			if GameState.has_pending_shop_action(peer_id) and not moves.is_empty():
				move = moves[0]
				decision = {
					"method": "pending_shop_required",
					"chosen_evaluator_score": 0.0,
					"evaluator_rank": 1,
					"evaluator_total": moves.size(),
					"alternatives": [],
				}
			elif not moves.is_empty():
				should_end = true
				break
			else:
				break

		var before := _snapshot_action_state(peer_id)
		Search.apply_move(peer_id, move)
		var after := _snapshot_action_state(peer_id)

		if not _action_state_changed(before, after):
			blocked[_move_key(move)] = true
			continue

		if str(move.get("kind", "")) != MoveGenerator.KIND_SHOP_BUY:
			attempts = 0

		var stored_move: Dictionary = move.duplicate(true)
		stored_move["_decision"] = decision
		planned.append(stored_move)

		if not _is_spend_actions_turn(peer_id):
			break
		if GameState.has_pending_shop_action(peer_id):
			continue
		if GameState.get_total_actions_for_peer(peer_id) <= 0:
			break
		if not MoveGenerator.has_actionable_moves(peer_id):
			break

	GameState.import_debug_snapshot(turn_snapshot, false)
	GameState.pop_ai_search_silence()
	ShopEvaluator.clear_evaluation_cache()

	if _is_spend_actions_turn(peer_id):
		if GameState.has_pending_shop_action(peer_id):
			should_end = false
		elif planned.is_empty():
			should_end = true
		elif GameState.get_total_actions_for_peer(peer_id) <= 0:
			should_end = true
		elif not MoveGenerator.has_actionable_moves(peer_id):
			should_end = true

	return {
		"moves": planned,
		"blocked_moves": blocked,
		"stall_signature": signature,
		"stall_attempts": attempts,
		"should_end_turn": should_end,
	}


static func plan_crib_choices(peer_id: int) -> Array:
	if not _is_crib_resolution_turn(peer_id):
		return []

	var planned: Array = []
	var turn_snapshot: Dictionary = GameState.export_debug_snapshot()

	GameState.push_ai_search_silence()
	for _step in range(MAX_CRIB_PLAN_STEPS):
		if not _is_crib_resolution_turn(peer_id):
			break

		var moves: Array = MoveGenerator.generate_moves(peer_id)
		if moves.is_empty():
			break

		var resolved_before := _crib_resolved_count()
		var pending_before := 0
		if GameState.has_pending_crib_reject():
			pending_before = GameState.get_pending_crib_reject_placed_count()
		var context: AiContext = ContextBuilder.from_game(peer_id)
		var decision: Dictionary = Evaluator.choose_move_decision(moves, context, false, false)
		var move: Dictionary = decision.get("move", {})
		if move.is_empty():
			break

		Search.apply_move(peer_id, move)
		var resolved_after := _crib_resolved_count()
		var pending_after := 0
		if GameState.has_pending_crib_reject():
			pending_after = GameState.get_pending_crib_reject_placed_count()
		if resolved_after <= resolved_before and pending_after <= pending_before:
			break

		var stored_move: Dictionary = move.duplicate(true)
		stored_move["_decision"] = decision
		planned.append(stored_move)

	GameState.import_debug_snapshot(turn_snapshot, false)
	GameState.pop_ai_search_silence()
	return planned


static func _crib_resolved_count() -> int:
	match GameState.current_phase:
		GameState.Phase.SETUP_MINI_CRIB:
			return GameState.mini_crib_resolved.size()
		GameState.Phase.RESOLVE_CRIB:
			return GameState.end_crib_resolved.size()
	return 0


static func choose_move(peer_id: int) -> Dictionary:
	var moves: Array = MoveGenerator.generate_moves(peer_id)
	if moves.is_empty():
		return {}
	var context: AiContext = ContextBuilder.from_game(peer_id)
	var require_positive := GameState.current_phase == GameState.Phase.SPEND_ACTIONS
	return Evaluator.choose_move_decision(moves, context, require_positive)


static func _is_spend_actions_turn(peer_id: int) -> bool:
	return (
		GameState.current_phase == GameState.Phase.SPEND_ACTIONS
		and GameState.action_turn_peer_id == peer_id
	)


static func is_crib_resolution_turn(peer_id: int) -> bool:
	return _is_crib_resolution_turn(peer_id)


static func _is_crib_resolution_turn(peer_id: int) -> bool:
	match GameState.current_phase:
		GameState.Phase.SETUP_MINI_CRIB:
			return int(peer_id) == int(GameState.crib_resolver_peer_id)
		GameState.Phase.RESOLVE_CRIB:
			return int(peer_id) == int(GameState.crib_owner_peer_id)
	return false


static func _try_recover_stuck_turn(
	peer_id: int,
	signature: String,
	attempts: int
) -> Dictionary:
	if not _is_spend_actions_turn(peer_id):
		return {"recovered": false}

	var current_signature := _action_stall_signature(peer_id)
	var next_attempts := attempts
	if current_signature != signature:
		next_attempts = 0
	next_attempts += 1
	if next_attempts > MAX_STALL_ATTEMPTS:
		return {"recovered": false, "signature": current_signature, "attempts": next_attempts}

	if not GameState.has_pending_shop_action(peer_id):
		return {"recovered": false, "signature": current_signature, "attempts": next_attempts}

	GameState.run_as_peer(peer_id, func() -> void:
		GameState.submit_undo_action()
	)
	return {
		"recovered": true,
		"signature": current_signature,
		"attempts": 0,
	}


static func _action_stall_signature(peer_id: int) -> String:
	var pending := GameState.get_pending_shop_action()
	var pending_effect := str(pending.get("effect", ""))
	var deploy_faction := GameState.get_pending_shop_deploy_faction()
	return "%d|%s|%s|%d|%d" % [
		peer_id,
		pending_effect,
		str(GameState.has_pending_shop_action(peer_id)),
		deploy_faction,
		GameState.get_action_points_for_peer(peer_id),
	]


static func _filter_blocked_moves(moves: Array, blocked_moves: Dictionary) -> Array:
	var filtered: Array = []
	for move in moves:
		if str(move.get("kind", "")) == MoveGenerator.KIND_END_ACTIONS:
			continue
		if blocked_moves.has(_move_key(move)):
			continue
		filtered.append(move)
	return filtered


static func _without_shop_buys(moves: Array) -> Array:
	var filtered: Array = []
	for move in moves:
		if str(move.get("kind", "")) == MoveGenerator.KIND_SHOP_BUY:
			continue
		filtered.append(move)
	return filtered


static func _move_key(move: Dictionary) -> String:
	return Search.move_key(move)


static func _snapshot_action_state(peer_id: int) -> Dictionary:
	return {
		"total_actions": GameState.get_total_actions_for_peer(peer_id),
		"pending_shop": GameState.has_pending_shop_action(peer_id),
		"coins": int(GameState.player_coins.get(peer_id, 0)),
	}


static func _action_state_changed(before: Dictionary, after: Dictionary) -> bool:
	if int(before.get("total_actions", 0)) != int(after.get("total_actions", 0)):
		return true
	if bool(before.get("pending_shop", false)) != bool(after.get("pending_shop", false)):
		return true
	return int(before.get("coins", 0)) != int(after.get("coins", 0))
