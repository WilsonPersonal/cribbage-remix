extends Node

signal thinking_started(peer_id: int)
signal thinking_finished(peer_id: int)
signal action_logged(entry: Dictionary)
signal history_cleared

const EXECUTE_DELAY_SEC := 1.0
const MAX_CRIB_STALL_ATTEMPTS := 8
const MAX_ACTION_TURN_LOOPS := 32
const DEBUG_AI := false
const MoveGenerator := preload("res://scripts/ai/ai_move_generator.gd")
const TurnPlanner := preload("res://scripts/ai/ai_turn_planner.gd")
const Search := preload("res://scripts/ai/ai_search.gd")
const Evaluator := preload("res://scripts/ai/ai_evaluator.gd")
const ContextBuilder := preload("res://scripts/ai/ai_context.gd")
const PowerRating := preload("res://scripts/ai/faction_power_rating.gd")
const ShopEvaluator := preload("res://scripts/ai/ai_shop_evaluator.gd")

var enabled: bool = false
var ai_peer_ids: Array[int] = []
var action_history: Array = []
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
	GameState.pending_crib_reject_updated.connect(_on_pending_crib_reject_updated)
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
	action_history.clear()
	history_cleared.emit()
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


func get_action_history() -> Array:
	return action_history.duplicate(true)


func _record_ai_action(peer_id: int, move: Dictionary) -> void:
	if not is_ai_peer(peer_id):
		return
	var kind := str(move.get("kind", ""))
	if kind in [MoveGenerator.KIND_PEGGING_PLAY, MoveGenerator.KIND_PEGGING_PASS]:
		return
	var action_id := action_history.size() + 1
	var context := AiContext.from_game(peer_id)
	var explanation := AiEvaluator.explain_move(move, context, true)
	var board_snapshots := _capture_board_snapshots(peer_id, move)
	var before_board: Array = board_snapshots.get("before_board", [])
	var after_board: Array = board_snapshots.get("after_board", before_board)
	var decision := _decision_from_move(move)
	var alternatives: Array = []
	if decision.is_empty():
		alternatives = _rank_alternative_moves(peer_id, move, context)
	else:
		alternatives = _alternatives_from_decision(decision)
	var shop_card_evaluations: Array = []
	if (
		GameState.current_phase == GameState.Phase.SPEND_ACTIONS
		and kind == MoveGenerator.KIND_SHOP_BUY
	):
		shop_card_evaluations = ShopEvaluator.evaluate_all_shop_buy_deltas(peer_id, context)
	var queen_follow_up_summary := ""
	if kind == MoveGenerator.KIND_SHOP_BUY:
		queen_follow_up_summary = str(move.get("_queen_follow_up_summary", ""))
		if queen_follow_up_summary.is_empty() and not shop_card_evaluations.is_empty():
			var slot_index := int(move.get("slot_index", -1))
			for evaluation in shop_card_evaluations:
				if int(evaluation.get("slot_index", -2)) != slot_index:
					continue
				queen_follow_up_summary = str(evaluation.get("follow_up_summary", ""))
				break
	var entry := {
		"id": action_id,
		"round": GameState.round_number,
		"phase": GameState.current_phase,
		"peer_id": peer_id,
		"summary": format_action_summary(move, action_id, queen_follow_up_summary),
		"description": _describe_move(move),
		"move": _move_without_decision(move),
		"explanation": explanation,
		"decision": decision,
		"alternatives": alternatives,
		"before_board": before_board,
		"after_board": after_board,
		"highlight_hexes": board_snapshots.get("highlight_hexes", []),
		"power_ratings_before": explanation.get("power_ratings_before", {}),
		"power_ratings_after": explanation.get("power_ratings_after", {}),
		"ai_power_before": explanation.get("ai_power_before", {}),
		"ai_power_after": explanation.get("ai_power_after", {}),
		"shop_card_evaluations": shop_card_evaluations,
		"queen_follow_up_summary": queen_follow_up_summary,
	}
	action_history.append(entry)
	action_logged.emit(entry)


func _decision_from_move(move: Dictionary) -> Dictionary:
	var raw: Dictionary = move.get("_decision", {})
	if raw.is_empty():
		return {}
	return _snapshot_decision(raw)


func _move_without_decision(move: Dictionary) -> Dictionary:
	var copy := move.duplicate(true)
	copy.erase("_decision")
	return copy


func _snapshot_decision(decision: Dictionary) -> Dictionary:
	var snapshot := {
		"method": str(decision.get("method", "heuristic")),
		"chosen_evaluator_score": float(decision.get("chosen_evaluator_score", 0.0)),
		"evaluator_rank": int(decision.get("evaluator_rank", 0)),
		"evaluator_total": int(decision.get("evaluator_total", 0)),
		"alternatives": [],
	}
	var alternatives: Array = []
	for option in decision.get("alternatives", []):
		var option_move: Dictionary = option.get("move", {})
		alternatives.append({
			"summary": format_action_summary(option_move),
			"evaluator_score": float(option.get("evaluator_score", 0.0)),
		})
	snapshot["alternatives"] = alternatives
	return snapshot


func _alternatives_from_decision(decision: Dictionary) -> Array:
	return decision.get("alternatives", []).duplicate(true)


func format_action_summary(
	move: Dictionary,
	action_id: int = -1,
	queen_follow_up_summary: String = ""
) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if action_id > 0:
		parts.append("#%d" % action_id)

	match str(move.get("kind", "")):
		MoveGenerator.KIND_FACTION_ACTION:
			parts.append(_action_type_label(int(move.get("action_type", -1))))
			parts.append(_move_faction_name(move))
		MoveGenerator.KIND_END_ACTIONS:
			parts.append("End turn")
			parts.append("—")
		MoveGenerator.KIND_CRIB_CHOICE:
			parts.append("Accept" if bool(move.get("accept", false)) else "Reject")
			parts.append(_move_faction_name(move))
		MoveGenerator.KIND_SHOP_BUY:
			parts.append("Shop buy")
			parts.append(_shop_card_faction_name(move))
			if queen_follow_up_summary.is_empty():
				queen_follow_up_summary = str(move.get("_queen_follow_up_summary", ""))
			if not queen_follow_up_summary.is_empty():
				parts.append(queen_follow_up_summary)
		MoveGenerator.KIND_SHOP_DEPLOY_FACTION:
			parts.append("Deploy")
			parts.append(Factions.name_for(int(move.get("faction_id", -1))))
		MoveGenerator.KIND_SHOP_KING_DEPLOY:
			parts.append("King deploy")
			parts.append(
				Factions.name_for(int(move.get("faction_id", GameState.get_pending_shop_deploy_faction())))
			)
		MoveGenerator.KIND_PEGGING_PLAY:
			parts.append("Peg")
			parts.append("—")
		MoveGenerator.KIND_PEGGING_PASS:
			parts.append("Pass")
			parts.append("—")
		MoveGenerator.KIND_DISCARD:
			parts.append("Discard")
			parts.append(_discard_cards_summary(move))
		_:
			parts.append(str(move.get("kind", "Action")))
			parts.append("—")

	return "%s." % " | ".join(parts)


func _rank_alternative_moves(peer_id: int, chosen: Dictionary, context: AiContext) -> Array:
	var moves: Array = MoveGenerator.generate_moves(peer_id)
	var ranked: Array = AiEvaluator.rank_moves(moves, context, true)
	var alternatives: Array = []
	var chosen_key := _move_key(chosen)

	for entry in ranked:
		var move: Dictionary = entry.get("move", {})
		if _move_key(move) == chosen_key:
			continue
		alternatives.append({
			"summary": format_action_summary(move),
			"evaluator_score": float(entry.get("score", 0.0)),
		})
		if alternatives.size() >= 2:
			break

	return alternatives


func _action_type_label(action_type: int) -> String:
	match action_type:
		ActionSystem.Type.PUSH:
			return "Push"
		ActionSystem.Type.PULL:
			return "Pull"
		ActionSystem.Type.CREATE_CART:
			return "Cart"
	return "Action"


func _move_faction_name(move: Dictionary) -> String:
	var faction_id := int(move.get("faction_id", -1))
	if faction_id in Factions.ALL:
		return Factions.name_for(faction_id)
	return "—"


func _shop_card_faction_name(move: Dictionary) -> String:
	var card: Dictionary = move.get("card", {})
	if card.is_empty():
		return "—"
	if card.has("faction"):
		return Factions.name_for(int(card.get("faction", -1)))
	return Factions.name_for(Factions.from_suit(str(card.get("suit", "clubs"))))


func _discard_cards_summary(move: Dictionary) -> String:
	var peer_id := int(move.get("peer_id", 0))
	var hand: Array = GameState.get_hand_for_peer(peer_id)
	var indices: Array = move.get("card_indices", [])
	var discard_indices := {}
	for index in indices:
		discard_indices[int(index)] = true

	var discarded: PackedStringArray = PackedStringArray()
	var kept: PackedStringArray = PackedStringArray()
	for card_index in range(hand.size()):
		var label := _short_card_label(hand[card_index])
		if discard_indices.has(card_index):
			discarded.append(label)
		else:
			kept.append(label)

	if discarded.is_empty() and kept.is_empty():
		return "—"
	return "to crib: %s | kept: %s" % [", ".join(discarded), ", ".join(kept)]


func _short_card_label(card: Dictionary) -> String:
	var rank := str(card.get("rank", "?"))
	match str(card.get("suit", "")):
		"hearts":
			return "%sH" % rank
		"diamonds":
			return "%sD" % rank
		"clubs":
			return "%sC" % rank
		"spades":
			return "%sS*" % rank
		_:
			return rank


func _capture_board_snapshots(peer_id: int, move: Dictionary) -> Dictionary:
	var before_board := GameState.get_board_state()
	var before_scores := GameState.faction_scores.duplicate()
	var after_board := before_board
	var after_scores := before_scores
	var highlight_hexes := _move_board_hexes(move)

	if _move_changes_board(move):
		var snapshot := GameState.export_debug_snapshot()
		Search.apply_move(peer_id, move)
		after_board = GameState.get_board_state()
		after_scores = GameState.faction_scores.duplicate()
		Search.restore_snapshot(snapshot)

	return {
		"before_board": before_board,
		"after_board": after_board,
		"before_scores": before_scores,
		"after_scores": after_scores,
		"highlight_hexes": highlight_hexes,
	}


func _move_changes_board(move: Dictionary) -> bool:
	var kind := str(move.get("kind", ""))
	return kind in [
		MoveGenerator.KIND_FACTION_ACTION,
		MoveGenerator.KIND_SHOP_KING_DEPLOY,
		MoveGenerator.KIND_CRIB_CHOICE,
	]


func _move_board_hexes(move: Dictionary) -> Array:
	var hexes: Array = []
	match str(move.get("kind", "")):
		MoveGenerator.KIND_FACTION_ACTION:
			_append_board_hex(hexes, int(move.get("hex_index", -1)))
			_append_board_hex(hexes, int(move.get("target_hex", -1)))
		MoveGenerator.KIND_SHOP_KING_DEPLOY:
			_append_board_hex(hexes, int(move.get("hex_index", -1)))
		MoveGenerator.KIND_CRIB_CHOICE:
			_append_board_hex(hexes, int(move.get("hex_index", -1)))
	return hexes


func _append_board_hex(hexes: Array, hex_index: int) -> void:
	if hex_index < 0 or hex_index >= HexBoard.HEX_COUNT:
		return
	if hex_index not in hexes:
		hexes.append(hex_index)


func _ai_debug(text: String) -> void:
	if DEBUG_AI:
		print("[AI] %s" % text)


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


func _on_pending_crib_reject_updated() -> void:
	if GameState.current_phase not in [GameState.Phase.SETUP_MINI_CRIB, GameState.Phase.RESOLVE_CRIB]:
		return
	var peer_id := GameState.crib_owner_peer_id
	if GameState.current_phase == GameState.Phase.SETUP_MINI_CRIB:
		peer_id = GameState.crib_resolver_peer_id
	_schedule_for_peer(peer_id)


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
	if _acting or _busy:
		_schedule_pending = true
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
	var shop_purchased_this_turn := false
	var turn_loops := 0
	while _is_ai_spend_actions_turn(peer_id):
		turn_loops += 1
		if turn_loops > MAX_ACTION_TURN_LOOPS:
			_ai_debug("Action turn loop limit reached — forcing shop recovery")
			_force_pending_shop_recovery(peer_id)
			break

		var pending_shop := GameState.get_pending_shop_action()
		_ai_debug(
			"Planning action turn | total actions=%d points=%d coins=%d pending_shop=%s effect=%s deploy=%d"
			% [
				GameState.get_total_actions_for_peer(peer_id),
				GameState.get_action_points_for_peer(peer_id),
				int(GameState.player_coins.get(peer_id, 0)),
				str(GameState.has_pending_shop_action(peer_id)),
				str(pending_shop.get("effect", "")),
				GameState.get_pending_shop_deploy_faction(),
			]
		)

		_begin_thinking(peer_id)
		await get_tree().process_frame
		var plan: Dictionary = await TurnPlanner.plan_spend_actions_turn(
			peer_id,
			_blocked_moves,
			_stall_signature,
			_stall_attempts,
			shop_purchased_this_turn
		)
		_end_thinking()
		_blocked_moves = plan.get("blocked_moves", {})
		_stall_signature = str(plan.get("stall_signature", ""))
		_stall_attempts = int(plan.get("stall_attempts", 0))

		var moves: Array = plan.get("moves", [])
		_ai_debug("Planned %d action(s)" % moves.size())

		if moves.is_empty():
			if GameState.has_pending_shop_action(peer_id):
				_stall_attempts += 1
				_ai_debug(
					"Pending shop with no executable moves (stall %d, blocked=%d)"
					% [_stall_attempts, _blocked_moves.size()]
				)
				var recovery_move := _first_pending_shop_move(peer_id)
				if not recovery_move.is_empty():
					_ai_debug("Executing pending shop recovery move | %s" % _describe_move(recovery_move))
					await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
					GameState.run_as_peer(peer_id, func() -> void:
						_execute_move(recovery_move)
					)
					if not GameState.has_pending_shop_action(peer_id):
						_stall_attempts = 0
						continue
				_force_pending_shop_recovery(peer_id)
				if not _is_ai_spend_actions_turn(peer_id):
					return
				if GameState.has_pending_shop_action(peer_id):
					if _stall_attempts >= TurnPlanner.MAX_STALL_ATTEMPTS:
						_blocked_moves.clear()
						_stall_attempts = 0
					await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
					continue
			if bool(plan.get("should_end_turn", false)) or _should_end_action_turn(peer_id):
				await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
				_finish_action_turn(peer_id, "planned turn complete")
			else:
				_stall_attempts += 1
				_ai_debug("No planned moves (stall %d)" % _stall_attempts)
				if _stall_attempts >= TurnPlanner.MAX_STALL_ATTEMPTS:
					_finish_action_turn(peer_id, "stall limit reached")
					return
				await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
				continue
			return

		for step in range(moves.size()):
			if not _is_ai_spend_actions_turn(peer_id):
				return

			var move: Dictionary = moves[step]
			if move.is_empty():
				continue

			if _is_invalid_pending_shop_step(peer_id, move):
				_blocked_moves[_move_key(move)] = true
				_stall_attempts += 1
				_ai_debug("Skipped invalid pending shop step: %s" % _describe_move(move))
				break

			await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
			if not _is_ai_spend_actions_turn(peer_id):
				return

			var before := _snapshot_action_state(peer_id)
			_reset_stall_if_progress(peer_id, move)
			_ai_debug("Execute %d | %s" % [step, _describe_move(move)])
			_record_ai_action(peer_id, move)
			GameState.run_as_peer(peer_id, func() -> void:
				_execute_move(move)
			)
			if str(move.get("kind", "")) == MoveGenerator.KIND_SHOP_BUY:
				shop_purchased_this_turn = true
			var after := _snapshot_action_state(peer_id)

			if not _action_state_changed(before, after):
				_blocked_moves[_move_key(move)] = true
				_stall_attempts += 1
				_ai_debug("Move rejected during execution: %s" % _describe_move(move))
				break

		if bool(plan.get("should_end_turn", false)) or _should_end_action_turn(peer_id):
			await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
			_finish_action_turn(peer_id, "planned turn complete")
			return


func _execute_planned_crib_turn(peer_id: int) -> void:
	var crib_blocked_moves: Dictionary = {}
	var crib_stall_attempts := 0

	_ai_debug(
		"Crib turn start | resolved=%d/%d pending_reject=%s pending_shop=%s"
		% [
			_crib_resolved_count(),
			_crib_total_count(),
			str(GameState.has_pending_crib_reject()),
			str(GameState.has_pending_shop_action(peer_id)),
		]
	)

	while _is_crib_resolution_turn(peer_id):
		if GameState.is_crib_resolution_complete():
			break

		var progress_before := _crib_progress_signature()

		_begin_thinking(peer_id)
		await get_tree().process_frame

		var moves: Array = _filter_blocked_crib_moves(
			MoveGenerator.generate_moves(peer_id),
			crib_blocked_moves
		)
		if moves.is_empty():
			_end_thinking()
			crib_stall_attempts += 1
			_ai_debug(
				"No crib moves available (%d/%d resolved, stall %d/%d)"
				% [
					_crib_resolved_count(),
					_crib_total_count(),
					crib_stall_attempts,
					MAX_CRIB_STALL_ATTEMPTS,
				]
			)
			if crib_stall_attempts >= MAX_CRIB_STALL_ATTEMPTS:
				break
			await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
			continue

		var context: AiContext = ContextBuilder.from_game(peer_id)
		var decision: Dictionary = Evaluator.choose_move_decision(moves, context, false, false)
		_end_thinking()

		var move: Dictionary = decision.get("move", {})
		if move.is_empty():
			crib_stall_attempts += 1
			if crib_stall_attempts >= MAX_CRIB_STALL_ATTEMPTS:
				break
			continue

		move = move.duplicate(true)
		move["_decision"] = decision

		await get_tree().create_timer(EXECUTE_DELAY_SEC).timeout
		if not _is_crib_resolution_turn(peer_id):
			return

		_ai_debug("Execute crib | %s" % _describe_move(move))
		_record_ai_action(peer_id, move)
		GameState.run_as_peer(peer_id, func() -> void:
			_execute_move(move)
		)

		var progress_after := _crib_progress_signature()
		if progress_after == progress_before:
			crib_blocked_moves[_move_key(move)] = true
			crib_stall_attempts += 1
			_ai_debug("Crib move made no progress: %s" % _describe_move(move))
			if crib_stall_attempts >= MAX_CRIB_STALL_ATTEMPTS:
				break
		else:
			crib_stall_attempts = 0


func _crib_progress_signature() -> String:
	var pending := 0
	if GameState.has_pending_crib_reject():
		pending = GameState.get_pending_crib_reject_placed_count()
	return "%d|%d" % [_crib_resolved_count(), pending]


func _filter_blocked_crib_moves(moves: Array, blocked_moves: Dictionary) -> Array:
	var filtered: Array = []
	for move in moves:
		if blocked_moves.has(_move_key(move)):
			continue
		filtered.append(move)
	return filtered


func _crib_resolved_count() -> int:
	match GameState.current_phase:
		GameState.Phase.SETUP_MINI_CRIB:
			return GameState.mini_crib_resolved.size()
		GameState.Phase.RESOLVE_CRIB:
			return GameState.end_crib_resolved.size()
	return 0


func _crib_total_count() -> int:
	match GameState.current_phase:
		GameState.Phase.SETUP_MINI_CRIB:
			return GameState.MINI_CRIB_SIZE
		GameState.Phase.RESOLVE_CRIB:
			return GameState.crib.size()
	return 0


func _execute_single_planned_move(peer_id: int) -> void:
	_begin_thinking(peer_id)
	await get_tree().process_frame
	var decision: Dictionary = await TurnPlanner.choose_move(peer_id)
	GameState.reconcile_pegging_hand_state()
	_end_thinking()
	var move: Dictionary = decision.get("move", {})
	if move.is_empty():
		if GameState.current_phase == GameState.Phase.SPEND_ACTIONS:
			_finish_action_turn(peer_id, "no move available")
		return

	move = move.duplicate(true)
	move["_decision"] = decision

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

	_record_ai_action(peer_id, move)
	var pegging_hand_before := GameState.get_hand_for_peer(peer_id).size()
	GameState.run_as_peer(peer_id, func() -> void:
		_execute_move(move)
	)
	GameState.reconcile_pegging_hand_state()

	if (
		GameState.current_phase == GameState.Phase.PEGGING
		and GameState.pegging_turn_peer == peer_id
		and (
			GameState.is_pegging_settling()
			or (
				str(move.get("kind", "")) == MoveGenerator.KIND_PEGGING_PLAY
				and GameState.get_hand_for_peer(peer_id).size() == pegging_hand_before
			)
		)
	):
		_schedule_for_peer(peer_id)


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
		MoveGenerator.KIND_SHOP_KING_DEPLOY:
			GameState.submit_shop_king_deploy(int(move.get("hex_index", -1)))
		MoveGenerator.KIND_CRIB_CHOICE:
			if bool(move.get("accept", false)):
				GameState.submit_crib_card_choice(
					int(move.get("card_index", -1)),
					true,
					int(move.get("hex_index", -1))
				)
			else:
				GameState.submit_crib_reject_cube(
					int(move.get("card_index", -1)),
					int(move.get("hex_index", -1))
				)
		MoveGenerator.KIND_END_ACTIONS:
			GameState.submit_end_action_phase()


func _move_key(move: Dictionary) -> String:
	if str(move.get("kind", "")) == MoveGenerator.KIND_CRIB_CHOICE:
		return "%s|%d|%d|%d|%d" % [
			MoveGenerator.KIND_CRIB_CHOICE,
			int(move.get("card_index", -1)),
			int(bool(move.get("accept", false))),
			int(move.get("hex_index", -1)),
			int(move.get("faction_id", -1)),
		]
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
		MoveGenerator.KIND_DISCARD:
			return "discard indices %s" % str(move.get("card_indices", []))
		MoveGenerator.KIND_PEGGING_PLAY:
			return "pegging play card=%d" % int(move.get("hand_index", -1))
		MoveGenerator.KIND_PEGGING_PASS:
			return "pegging pass"
		MoveGenerator.KIND_END_ACTIONS:
			return "end action phase"
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
		"coins": int(GameState.player_coins.get(peer_id, 0)),
	}


func _action_state_changed(before: Dictionary, after: Dictionary) -> bool:
	if int(before.get("total_actions", 0)) != int(after.get("total_actions", 0)):
		return true
	if bool(before.get("pending_shop", false)) != bool(after.get("pending_shop", false)):
		return true
	return int(before.get("coins", 0)) != int(after.get("coins", 0))


func _finish_action_turn(peer_id: int, reason: String = "") -> void:
	if not _is_ai_spend_actions_turn(peer_id):
		return
	if not reason.is_empty():
		_ai_debug("Ending turn: %s" % reason)
	if GameState.has_pending_shop_action(peer_id):
		GameState.run_as_peer(peer_id, func() -> void:
			GameState.submit_undo_action()
		)
		_ai_debug("Undid pending shop before ending")
		if GameState.has_pending_shop_action(peer_id):
			_ai_debug("Cannot end turn while shop action is still pending")
			return
	_record_ai_action(peer_id, {"kind": MoveGenerator.KIND_END_ACTIONS})
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


func _first_pending_shop_move(peer_id: int) -> Dictionary:
	for move in MoveGenerator.generate_moves(peer_id):
		if _blocked_moves.has(_move_key(move)):
			continue
		return move
	return {}


func _is_invalid_pending_shop_step(peer_id: int, move: Dictionary) -> bool:
	if not GameState.has_pending_shop_action(peer_id):
		return false

	var kind := str(move.get("kind", ""))
	if GameState.pending_shop_needs_faction_choice():
		return kind != MoveGenerator.KIND_SHOP_DEPLOY_FACTION

	match GameState.get_pending_shop_effect():
		Shop.EFFECT_KING:
			return kind != MoveGenerator.KIND_SHOP_KING_DEPLOY
		Shop.EFFECT_JACK:
			return kind != MoveGenerator.KIND_FACTION_ACTION
	return false


func _force_pending_shop_recovery(peer_id: int) -> void:
	if not GameState.has_pending_shop_action(peer_id):
		return

	GameState.run_as_peer(peer_id, func() -> void:
		GameState.submit_undo_action()
	)
	if not GameState.has_pending_shop_action(peer_id):
		_blocked_moves.clear()
		_stall_attempts = 0
		_ai_debug("Recovered by undoing shop purchase")
		return

	var recovery_move := _first_pending_shop_move(peer_id)
	if recovery_move.is_empty():
		_blocked_moves.clear()
		_ai_debug("No pending shop recovery moves remain")
		return

	GameState.run_as_peer(peer_id, func() -> void:
		_execute_move(recovery_move)
	)
	if not GameState.has_pending_shop_action(peer_id):
		_blocked_moves.clear()
		_stall_attempts = 0
		_ai_debug("Recovered pending shop with %s" % _describe_move(recovery_move))


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
		GameState.Phase.RESOLVE_CRIB:
			return GameState.crib_owner_peer_id
		GameState.Phase.SETUP_MINI_CRIB:
			return GameState.crib_resolver_peer_id
	return 0
