class_name AiTurnPlanner
extends RefCounted

const MoveGenerator := preload("res://scripts/ai/ai_move_generator.gd")
const Mcts := preload("res://scripts/ai/ai_mcts.gd")
const ContextBuilder := preload("res://scripts/ai/ai_context.gd")
const Search := preload("res://scripts/ai/ai_search.gd")

const MAX_ACTIONS_PER_TURN := 24
const MAX_STALL_ATTEMPTS := 3


static func plan_spend_actions_turn(
	peer_id: int,
	blocked_moves: Dictionary,
	stall_signature: String,
	stall_attempts: int
) -> Dictionary:
	var planned: Array = []
	var blocked := blocked_moves.duplicate()
	var signature := stall_signature
	var attempts := stall_attempts
	var turn_snapshot: Dictionary = GameState.export_debug_snapshot()

	GameState.push_ai_search_silence()
	for _step in range(MAX_ACTIONS_PER_TURN):
		if not _is_spend_actions_turn(peer_id):
			break

		var moves: Array = _filter_blocked_moves(MoveGenerator.generate_moves(peer_id), blocked)
		if moves.is_empty():
			if MoveGenerator.generate_moves(peer_id).is_empty():
				var recovery := _try_recover_stuck_turn(peer_id, signature, attempts)
				if recovery.get("recovered", false):
					signature = recovery.get("signature", signature)
					attempts = int(recovery.get("attempts", attempts))
					continue
			break

		var context: AiContext = ContextBuilder.from_game(peer_id)
		var move: Dictionary = await Mcts.choose_move(moves, context)
		if move.is_empty() or str(move.get("kind", "")) == MoveGenerator.KIND_END_ACTIONS:
			break

		var before := _snapshot_action_state(peer_id)
		Search.apply_move(peer_id, move)
		var after := _snapshot_action_state(peer_id)

		if not _action_state_changed(before, after):
			blocked[_move_key(move)] = true
			continue

		if str(move.get("kind", "")) != MoveGenerator.KIND_SHOP_BUY:
			attempts = 0

		planned.append(move.duplicate(true))

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

	var should_end := false
	if _is_spend_actions_turn(peer_id):
		if planned.is_empty():
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
	while _is_crib_resolution_turn(peer_id):
		var moves: Array = MoveGenerator.generate_moves(peer_id)
		if moves.is_empty():
			break

		var context: AiContext = ContextBuilder.from_game(peer_id)
		var move: Dictionary = await Mcts.choose_move(moves, context)
		if move.is_empty():
			break

		Search.apply_move(peer_id, move)
		planned.append(move.duplicate(true))

	GameState.import_debug_snapshot(turn_snapshot, false)
	GameState.pop_ai_search_silence()
	return planned


static func choose_move(peer_id: int) -> Dictionary:
	var moves: Array = MoveGenerator.generate_moves(peer_id)
	if moves.is_empty():
		return {}
	var context: AiContext = ContextBuilder.from_game(peer_id)
	return await Mcts.choose_move(moves, context)


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

	if not GameState.has_pending_shop_action(peer_id) or not GameState.can_undo_action():
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


static func _move_key(move: Dictionary) -> String:
	return Search.move_key(move)


static func _snapshot_action_state(peer_id: int) -> Dictionary:
	return {
		"total_actions": GameState.get_total_actions_for_peer(peer_id),
		"pending_shop": GameState.has_pending_shop_action(peer_id),
	}


static func _action_state_changed(before: Dictionary, after: Dictionary) -> bool:
	if int(before.get("total_actions", 0)) != int(after.get("total_actions", 0)):
		return true
	return bool(before.get("pending_shop", false)) != bool(after.get("pending_shop", false))
