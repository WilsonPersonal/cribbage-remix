extends Node

signal thinking_started(peer_id: int)
signal thinking_finished(peer_id: int)

const EXECUTE_DELAY_SEC := 1.0
const MoveGenerator := preload("res://scripts/ai/ai_move_generator.gd")
const TurnPlanner := preload("res://scripts/ai/ai_turn_planner.gd")

var enabled: bool = false
var ai_peer_ids: Array[int] = []
var _busy: bool = false
var _acting: bool = false
var _queued_peer_id: int = 0
var _schedule_pending: bool = false
var _stall_attempts: int = 0
var _stall_signature: String = ""
var _blocked_moves: Dictionary = {}
var _thinking_depth: int = 0
var _thinking_peer_id: int = 0


func _ready() -> void:
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.pegging_state_updated.connect(_on_pegging_state_updated)
	GameState.action_turn_updated.connect(_on_action_turn_updated)
	GameState.crib_resolution_updated.connect(_on_crib_resolution_updated)
	GameState.round_started.connect(_on_round_started)
	GameState.crib_discards_updated.connect(_on_crib_discards_updated)
	GameState.board_updated.connect(_on_board_updated)
	GameState.action_points_updated.connect(_on_action_points_updated)
	GameState.faction_actions_updated.connect(_on_faction_actions_updated)
	GameState.shop_action_pending_updated.connect(_on_shop_action_pending_updated)


func enable_for_peers(peer_ids: Array) -> void:
	enabled = true
	ai_peer_ids.clear()
	for peer_id in peer_ids:
		ai_peer_ids.append(int(peer_id))
	call_deferred("_schedule_for_current_turn")


func request_turn() -> void:
	if not enabled:
		return
	call_deferred("_schedule_for_current_turn")


func disable() -> void:
	enabled = false
	ai_peer_ids.clear()
	_busy = false
	_acting = false
	_queued_peer_id = 0
	_schedule_pending = false
	_stall_attempts = 0
	_stall_signature = ""
	_blocked_moves.clear()
	_clear_thinking()


func _begin_thinking(peer_id: int) -> void:
	if _thinking_depth == 0:
		_thinking_peer_id = peer_id
		thinking_started.emit(peer_id)
	_thinking_depth += 1


func _end_thinking() -> void:
	_thinking_depth = maxi(_thinking_depth - 1, 0)
	if _thinking_depth == 0 and _thinking_peer_id != 0:
		var peer_id := _thinking_peer_id
		_thinking_peer_id = 0
		thinking_finished.emit(peer_id)


func _clear_thinking() -> void:
	if _thinking_depth > 0 and _thinking_peer_id != 0:
		var peer_id := _thinking_peer_id
		_thinking_depth = 0
		_thinking_peer_id = 0
		thinking_finished.emit(peer_id)
	else:
		_thinking_depth = 0
		_thinking_peer_id = 0


func is_ai_peer(peer_id: int) -> bool:
	return enabled and int(peer_id) in ai_peer_ids


func _ai_debug(text: String) -> void:
	if not enabled:
		return
	var line := text.strip_edges()
	if line.is_empty():
		return
	print("[AI Debug] ", line)


func _on_phase_changed(_phase: GameState.Phase) -> void:
	_reset_stall_tracking()
	_schedule_for_current_turn()


func _on_pegging_state_updated(_sequence: Array, _total: int, _turn_peer: int) -> void:
	_schedule_for_peer(GameState.pegging_turn_peer)


func _on_action_turn_updated(peer_id: int) -> void:
	_reset_stall_tracking()
	if is_ai_peer(peer_id):
		_ai_debug("Action turn started | total actions=%d" % GameState.get_total_actions_for_peer(peer_id))
	_schedule_for_peer(peer_id)


func _on_crib_resolution_updated(_cards: Array, _resolved: Dictionary, resolver_peer: int) -> void:
	_schedule_for_peer(resolver_peer)


func _on_round_started(_round_number: int) -> void:
	_reset_stall_tracking()
	call_deferred("_schedule_for_current_turn")


func _on_crib_discards_updated() -> void:
	if GameState.current_phase == GameState.Phase.DISCARD_TO_CRIB:
		_schedule_for_current_turn()


func _on_board_updated(_board_state: Array, _faction_power: Dictionary) -> void:
	_schedule_action_phase_turn()


func _on_action_points_updated(_action_points: Dictionary) -> void:
	_schedule_action_phase_turn()


func _on_faction_actions_updated(_tokens: Dictionary) -> void:
	_schedule_action_phase_turn()


func _on_shop_action_pending_updated(_pending: Dictionary) -> void:
	_schedule_action_phase_turn()


func _schedule_action_phase_turn() -> void:
	if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
		return
	if _acting:
		return
	_schedule_for_peer(GameState.action_turn_peer_id)


func _schedule_for_current_turn() -> void:
	var peer_id := _current_turn_peer()
	_schedule_for_peer(peer_id)


func _schedule_for_peer(peer_id: int) -> void:
	if not is_ai_peer(peer_id):
		return
	if not NetworkManager.is_server():
		return
	_queued_peer_id = peer_id
	if _acting or _busy:
		_schedule_pending = true
		return
	call_deferred("_think_and_act")


func _think_and_act() -> void:
	if _acting:
		return

	_busy = true
	_acting = true
	_schedule_pending = false

	var peer_id := _queued_peer_id
	_busy = false

	if not is_ai_peer(peer_id):
		_acting = false
		return
	if not NetworkManager.is_server():
		_acting = false
		return

	match GameState.current_phase:
		GameState.Phase.SPEND_ACTIONS:
			if GameState.action_turn_peer_id == peer_id:
				await _execute_planned_spend_actions_turn(peer_id)
		GameState.Phase.SETUP_MINI_CRIB, GameState.Phase.RESOLVE_CRIB:
			await _execute_planned_crib_turn(peer_id)
		_:
			await _execute_single_planned_move(peer_id)

	_acting = false
	if _schedule_pending:
		call_deferred("_think_and_act")


func _execute_planned_spend_actions_turn(peer_id: int) -> void:
	while _is_ai_spend_actions_turn(peer_id):
		_ai_debug(
			"Planning action turn | total actions=%d points=%d"
			% [
				GameState.get_total_actions_for_peer(peer_id),
				GameState.get_action_points_for_peer(peer_id),
			]
		)

		_begin_thinking(peer_id)
		await get_tree().process_frame
		var plan: Dictionary = await TurnPlanner.plan_spend_actions_turn(
			peer_id,
			_blocked_moves,
			_stall_signature,
			_stall_attempts
		)
		_end_thinking()
		_blocked_moves = plan.get("blocked_moves", {})
		_stall_signature = str(plan.get("stall_signature", ""))
		_stall_attempts = int(plan.get("stall_attempts", 0))

		var moves: Array = plan.get("moves", [])
		_ai_debug("Planned %d action(s)" % moves.size())

		if moves.is_empty():
			if bool(plan.get("should_end_turn", false)) or _should_end_action_turn(peer_id):
				await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
				_finish_action_turn(peer_id, "planned turn complete")
			else:
				_finish_action_turn(peer_id, "no planned moves")
			return

		for step in range(moves.size()):
			if not _is_ai_spend_actions_turn(peer_id):
				return

			var move: Dictionary = moves[step]
			if move.is_empty():
				continue

			await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
			if not _is_ai_spend_actions_turn(peer_id):
				return

			var before := _snapshot_action_state(peer_id)
			_reset_stall_if_progress(peer_id, move)
			_ai_debug("Execute %d | %s" % [step, _describe_move(move)])
			GameState.run_as_peer(peer_id, func() -> void:
				_execute_move(move)
			)
			var after := _snapshot_action_state(peer_id)

			if not _action_state_changed(before, after):
				_blocked_moves[_move_key(move)] = true
				_ai_debug("Move rejected during execution: %s" % _describe_move(move))
				return

		if bool(plan.get("should_end_turn", false)) or _should_end_action_turn(peer_id):
			await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
			_finish_action_turn(peer_id, "planned turn complete")
			return


func _execute_planned_crib_turn(peer_id: int) -> void:
	_begin_thinking(peer_id)
	await get_tree().process_frame
	var moves: Array = await TurnPlanner.plan_crib_choices(peer_id)
	_end_thinking()
	if moves.is_empty():
		return

	_ai_debug("Planned %d crib choice(s)" % moves.size())
	for step in range(moves.size()):
		if not _is_crib_resolution_turn(peer_id):
			return

		var move: Dictionary = moves[step]
		await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
		if not _is_crib_resolution_turn(peer_id):
			return

		_ai_debug("Execute crib %d | %s" % [step, _describe_move(move)])
		GameState.run_as_peer(peer_id, func() -> void:
			_execute_move(move)
		)


func _execute_single_planned_move(peer_id: int) -> void:
	_begin_thinking(peer_id)
	await get_tree().process_frame
	var move: Dictionary = await TurnPlanner.choose_move(peer_id)
	_end_thinking()
	if move.is_empty():
		if GameState.current_phase == GameState.Phase.SPEND_ACTIONS:
			_finish_action_turn(peer_id, "no move available")
		return

	if str(move.get("kind", "")) == MoveGenerator.KIND_END_ACTIONS:
		_finish_action_turn(peer_id, "end only")
		return

	_reset_stall_if_progress(peer_id, move)
	_ai_debug("Planned | %s" % _describe_move(move))

	await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout

	if not is_ai_peer(peer_id):
		return
	if GameState.current_phase == GameState.Phase.PEGGING and GameState.pegging_turn_peer != peer_id:
		return
	if GameState.current_phase == GameState.Phase.DISCARD_TO_CRIB:
		if bool(GameState.discard_ready.get(peer_id, false)):
			return

	GameState.run_as_peer(peer_id, func() -> void:
		_execute_move(move)
	)


func _is_ai_spend_actions_turn(peer_id: int) -> bool:
	return (
		GameState.current_phase == GameState.Phase.SPEND_ACTIONS
		and GameState.action_turn_peer_id == peer_id
	)


func _is_crib_resolution_turn(peer_id: int) -> bool:
	return TurnPlanner.is_crib_resolution_turn(peer_id)


func _should_end_action_turn(peer_id: int) -> bool:
	if not _is_ai_spend_actions_turn(peer_id):
		return false
	if GameState.has_pending_shop_action(peer_id):
		return false
	if GameState.get_total_actions_for_peer(peer_id) <= 0:
		return true
	return not MoveGenerator.has_actionable_moves(peer_id)


func _execute_move(move: Dictionary) -> void:
	match str(move.get("kind", "")):
		MoveGenerator.KIND_DISCARD:
			GameState.submit_discard(move.get("card_indices", []))
		MoveGenerator.KIND_PEGGING_PLAY:
			GameState.submit_pegging_play(int(move.get("hand_index", -1)))
		MoveGenerator.KIND_PEGGING_PASS:
			GameState.submit_pegging_pass()
		MoveGenerator.KIND_FACTION_ACTION:
			GameState.submit_faction_action(
				int(move.get("hex_index", -1)),
				int(move.get("action_type", -1)),
				int(move.get("target_hex", -1)),
				int(move.get("cube_count", 1)),
				bool(move.get("move_cart_also", false))
			)
		MoveGenerator.KIND_SHOP_BUY:
			GameState.submit_shop_slot_purchase(int(move.get("slot_index", -1)))
		MoveGenerator.KIND_SHOP_DEPLOY_FACTION:
			GameState.submit_shop_deploy_faction(int(move.get("faction_id", -1)))
		MoveGenerator.KIND_SHOP_JACK_PUSH:
			GameState.submit_shop_jack_push(
				int(move.get("from_hex", -1)),
				int(move.get("to_hex", -1))
			)
		MoveGenerator.KIND_SHOP_KING_DEPLOY:
			GameState.submit_shop_king_deploy(int(move.get("hex_index", -1)))
		MoveGenerator.KIND_CRIB_CHOICE:
			GameState.submit_crib_card_choice(
				int(move.get("card_index", -1)),
				bool(move.get("accept", false)),
				int(move.get("hex_index", -1))
			)
		MoveGenerator.KIND_END_ACTIONS:
			GameState.submit_end_action_phase()


func _move_key(move: Dictionary) -> String:
	return "%s|%d|%d|%d|%d|%d|%d|%d" % [
		str(move.get("kind", "")),
		int(move.get("action_type", -1)),
		int(move.get("hex_index", -1)),
		int(move.get("target_hex", -1)),
		int(move.get("from_hex", -1)),
		int(move.get("to_hex", -1)),
		int(move.get("faction_id", -1)),
		int(bool(move.get("move_cart_also", false))),
	]


func _describe_move(move: Dictionary) -> String:
	match str(move.get("kind", "")):
		MoveGenerator.KIND_FACTION_ACTION:
			var cart_note := "+cart " if bool(move.get("move_cart_also", false)) else ""
			return "map %s%shex=%d target=%d faction=%d" % [
				cart_note,
				_action_type_name(int(move.get("action_type", -1))),
				int(move.get("hex_index", -1)),
				int(move.get("target_hex", -1)),
				int(move.get("faction_id", -1)),
			]
		MoveGenerator.KIND_SHOP_BUY:
			return "shop buy slot=%d" % int(move.get("slot_index", -1))
		MoveGenerator.KIND_SHOP_DEPLOY_FACTION:
			return "shop deploy faction=%d" % int(move.get("faction_id", -1))
		MoveGenerator.KIND_SHOP_JACK_PUSH:
			return "shop jack %d -> %d" % [int(move.get("from_hex", -1)), int(move.get("to_hex", -1))]
		MoveGenerator.KIND_SHOP_KING_DEPLOY:
			return "shop king deploy hex=%d" % int(move.get("hex_index", -1))
		MoveGenerator.KIND_CRIB_CHOICE:
			var choice := "accept" if bool(move.get("accept", false)) else "reject"
			return "crib %s card=%d hex=%d" % [
				choice,
				int(move.get("card_index", -1)),
				int(move.get("hex_index", -1)),
			]
	return str(move.get("kind", "unknown"))


func _action_type_name(action_type: int) -> String:
	match action_type:
		ActionSystem.Type.PUSH:
			return "push"
		ActionSystem.Type.PULL:
			return "pull"
		ActionSystem.Type.CREATE_CART:
			return "cart"
	return "action"


func _snapshot_action_state(peer_id: int) -> Dictionary:
	return {
		"total_actions": GameState.get_total_actions_for_peer(peer_id),
		"pending_shop": GameState.has_pending_shop_action(peer_id),
	}


func _action_state_changed(before: Dictionary, after: Dictionary) -> bool:
	if int(before.get("total_actions", 0)) != int(after.get("total_actions", 0)):
		return true
	return bool(before.get("pending_shop", false)) != bool(after.get("pending_shop", false))


func _finish_action_turn(peer_id: int, reason: String = "") -> void:
	if not _is_ai_spend_actions_turn(peer_id):
		return
	if not reason.is_empty():
		_ai_debug("Ending turn: %s" % reason)
	if GameState.has_pending_shop_action(peer_id):
		if GameState.can_undo_action():
			GameState.run_as_peer(peer_id, func() -> void:
				GameState.submit_undo_action()
			)
			_ai_debug("Undid pending shop before ending")
		if GameState.has_pending_shop_action(peer_id):
			_ai_debug("Cannot end turn while shop action is still pending")
			return
	GameState.run_as_peer(peer_id, func() -> void:
		GameState.submit_end_action_phase()
	)
	_ai_debug("Submitted end action phase")


func _reset_stall_if_progress(peer_id: int, move: Dictionary) -> void:
	var signature := _action_stall_signature(peer_id)
	if signature != _stall_signature:
		_stall_signature = signature
		_stall_attempts = 0
	if str(move.get("kind", "")) != MoveGenerator.KIND_SHOP_BUY:
		_stall_attempts = 0


func _action_stall_signature(peer_id: int) -> String:
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


func _reset_stall_tracking() -> void:
	_stall_attempts = 0
	_stall_signature = ""
	_blocked_moves.clear()


func _current_turn_peer() -> int:
	match GameState.current_phase:
		GameState.Phase.DISCARD_TO_CRIB:
			for peer_id in GameState.active_player_order:
				if not bool(GameState.discard_ready.get(int(peer_id), false)):
					return int(peer_id)
		GameState.Phase.PEGGING:
			return GameState.pegging_turn_peer
		GameState.Phase.SPEND_ACTIONS:
			return GameState.action_turn_peer_id
		GameState.Phase.SETUP_MINI_CRIB, GameState.Phase.RESOLVE_CRIB:
			return GameState.crib_resolver_peer_id
	return 0
