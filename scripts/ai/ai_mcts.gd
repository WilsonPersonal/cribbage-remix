class_name AiMcts
extends RefCounted

const MoveGenerator := preload("res://scripts/ai/ai_move_generator.gd")
const Evaluator := preload("res://scripts/ai/ai_evaluator.gd")
const Search := preload("res://scripts/ai/ai_search.gd")
const PositionEval := preload("res://scripts/ai/ai_position_eval.gd")

const EXPLORATION_C := 1.35
const MAX_BRANCH_MOVES := 10
const DEFAULT_ITERATIONS := 32
const MAX_ROLLOUT_STEPS := 10
const UI_YIELD_EVERY_N_ITERATIONS := 2


static func choose_move(moves: Array, context: AiContext, iterations: int = DEFAULT_ITERATIONS) -> Dictionary:
	if moves.is_empty():
		return {}

	var actionable := _actionable_moves(moves)
	if actionable.is_empty():
		await _yield_ui_frame()
		return Evaluator.choose_best_move(moves, context)

	if not _should_use_mcts(context, actionable):
		await _yield_ui_frame()
		return Evaluator.choose_best_move(moves, context)

	GameState.push_ai_search_silence()
	var branch_moves := _prune_moves(actionable, context, MAX_BRANCH_MOVES)
	var snapshot: Dictionary = GameState.export_debug_snapshot()
	var stats: Dictionary = {}

	for move in branch_moves:
		stats[Search.move_key(move)] = {
			"move": move,
			"visits": 0,
			"value": 0.0,
		}

	await _yield_ui_frame()
	for visit_index in range(iterations):
		if visit_index > 0 and visit_index % UI_YIELD_EVERY_N_ITERATIONS == 0:
			await _yield_ui_frame()
		var key := _select_ucb_key(stats, visit_index + 1)
		Search.restore_snapshot(snapshot)
		var rollout_value := _rollout(context, stats[key]["move"])
		stats[key]["visits"] += 1
		stats[key]["value"] += rollout_value

	Search.restore_snapshot(snapshot)
	var chosen := _best_move(stats, context, moves)
	GameState.pop_ai_search_silence()
	return chosen


static func _yield_ui_frame() -> void:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		await tree.process_frame


static func _should_use_mcts(context: AiContext, actionable: Array) -> bool:
	if actionable.size() <= 1:
		return false
	match context.phase:
		GameState.Phase.SPEND_ACTIONS:
			return actionable.size() >= 4
		GameState.Phase.PEGGING:
			return false
		GameState.Phase.SETUP_MINI_CRIB, GameState.Phase.RESOLVE_CRIB:
			return false
		GameState.Phase.DISCARD_TO_CRIB:
			return false
	return false


static func _actionable_moves(moves: Array) -> Array:
	var actionable: Array = []
	for move in moves:
		if str(move.get("kind", "")) == MoveGenerator.KIND_END_ACTIONS:
			continue
		actionable.append(move)
	return actionable


static func _prune_moves(moves: Array, context: AiContext, max_branch: int) -> Array:
	if moves.size() <= max_branch:
		return moves.duplicate(true)

	var scored: Array = []
	for move in moves:
		scored.append({
			"move": move,
			"score": Evaluator.evaluate_move(move, context, false),
		})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)

	var pruned: Array = []
	for entry in scored.slice(0, max_branch):
		pruned.append(entry["move"])
	return pruned


static func _select_ucb_key(stats: Dictionary, total_visits: int) -> String:
	var best_key := ""
	var best_ucb := -INF
	var log_total := log(float(total_visits))

	for key in stats.keys():
		var entry: Dictionary = stats[key]
		var visits := int(entry.get("visits", 0))
		if visits <= 0:
			return key

		var avg_value := float(entry.get("value", 0.0)) / float(visits)
		var exploration := EXPLORATION_C * sqrt(log_total / float(visits))
		var ucb := avg_value + exploration
		if ucb > best_ucb:
			best_ucb = ucb
			best_key = key

	return best_key


static func _rollout(context: AiContext, first_move: Dictionary) -> float:
	Search.apply_move(context.peer_id, first_move)

	match context.phase:
		GameState.Phase.SPEND_ACTIONS:
			return _rollout_action_turn(context)
		GameState.Phase.PEGGING:
			return _rollout_pegging(context)
		_:
			return PositionEval.evaluate(context.peer_id, context)


static func _rollout_action_turn(context: AiContext) -> float:
	for _step in range(MAX_ROLLOUT_STEPS):
		if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
			break
		if GameState.action_turn_peer_id != context.peer_id:
			break
		if GameState.has_pending_shop_action(context.peer_id):
			break

		var moves := Search.actionable_moves(context.peer_id)
		if moves.is_empty():
			break

		var ranked := _prune_moves(moves, context, 3)
		var move: Dictionary = ranked[randi() % ranked.size()]
		Search.apply_move(context.peer_id, move)

	return PositionEval.evaluate(context.peer_id, context)


static func _rollout_pegging(context: AiContext) -> float:
	for _step in range(4):
		var active_peer := GameState.pegging_turn_peer
		var moves := MoveGenerator.generate_moves(active_peer)
		if moves.is_empty():
			break

		var active_context := AiContext.from_game(active_peer)
		var move := Evaluator.choose_best_move(moves, active_context, false)
		if move.is_empty():
			break
		Search.apply_move(active_peer, move)

		if GameState.current_phase != GameState.Phase.PEGGING:
			break

	return PositionEval.evaluate(context.peer_id, context)


static func _best_move(stats: Dictionary, context: AiContext, fallback_moves: Array) -> Dictionary:
	var best_key := ""
	var best_visits := -1
	var best_value := -INF

	for key in stats.keys():
		var entry: Dictionary = stats[key]
		var visits := int(entry.get("visits", 0))
		if visits <= 0:
			continue
		var avg_value := float(entry.get("value", 0.0)) / float(visits)
		if visits > best_visits or (visits == best_visits and avg_value > best_value):
			best_visits = visits
			best_value = avg_value
			best_key = key

	if best_key.is_empty():
		return Evaluator.choose_best_move(fallback_moves, context)
	return stats[best_key]["move"]
