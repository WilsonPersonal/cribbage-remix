class_name AiEvaluator
extends RefCounted

const Search := preload("res://scripts/ai/ai_search.gd")
const PowerRating := preload("res://scripts/ai/faction_power_rating.gd")
const ShopEvaluator := preload("res://scripts/ai/ai_shop_evaluator.gd")
const AiMoveGenerator := preload("res://scripts/ai/ai_move_generator.gd")
const PeggingPhase := preload("res://scripts/cribbage/pegging_phase.gd")
const PeggingRules := preload("res://scripts/cribbage/pegging.gd")

const MIN_POSITIVE_SCORE := 0.01

const DISCARD_POINTS_PER_ACTION := 7.0
const DISCARD_OWN_CRIB_ONE_TOP_FACTION := 10.0
const DISCARD_OWN_CRIB_TWO_TOP_FACTION := 15.0
const DISCARD_OPP_CRIB_ONE_TOP_FACTION := -10.0
const DISCARD_OPP_CRIB_TWO_TOP_FACTION := -15.0


static func choose_best_move(
	moves: Array,
	context: AiContext,
	require_positive: bool = false,
	_use_lookahead: bool = true
) -> Dictionary:
	var ranked: Array = rank_moves(moves, context, _use_lookahead)
	if require_positive:
		ranked = _filter_positive_ranked(ranked)
	if ranked.is_empty():
		return {}
	return ranked[0].get("move", {})


static func rank_moves(moves: Array, context: AiContext, _use_lookahead: bool = true) -> Array:
	var ranked: Array = []
	for move in moves:
		if str(move.get("kind", "")) == AiMoveGenerator.KIND_END_ACTIONS:
			continue
		ranked.append({
			"move": move,
			"score": evaluate_move(move, context),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	return ranked


static func choose_move_decision(
	moves: Array,
	context: AiContext,
	require_positive: bool = false,
	_use_lookahead: bool = true
) -> Dictionary:
	var all_ranked: Array = rank_moves(moves, context, _use_lookahead)
	var legal_total := all_ranked.size()
	if all_ranked.is_empty():
		return {
			"move": {},
			"method": _decision_method(require_positive),
			"chosen_evaluator_score": 0.0,
			"evaluator_rank": 0,
			"evaluator_total": 0,
			"legal_move_total": 0,
			"positive_move_total": 0,
			"alternatives": [],
		}

	var positive_ranked: Array = _filter_positive_ranked(all_ranked)
	var chosen_entry: Dictionary = all_ranked[0]
	var alternatives: Array = []
	for index in range(1, mini(3, all_ranked.size())):
		var entry: Dictionary = all_ranked[index]
		alternatives.append({
			"move": entry.get("move", {}),
			"evaluator_score": float(entry.get("score", 0.0)),
		})

	return {
		"move": chosen_entry.get("move", {}),
		"method": _decision_method(require_positive),
		"chosen_evaluator_score": float(chosen_entry.get("score", 0.0)),
		"evaluator_rank": 1,
		"evaluator_total": legal_total,
		"legal_move_total": legal_total,
		"positive_move_total": positive_ranked.size(),
		"alternatives": alternatives,
	}


static func _filter_positive_ranked(ranked: Array) -> Array:
	var positive: Array = []
	for entry in ranked:
		if float(entry.get("score", 0.0)) >= MIN_POSITIVE_SCORE:
			positive.append(entry)
	return positive


static func evaluate_move(move: Dictionary, context: AiContext, _use_lookahead: bool = true) -> float:
	return explain_move(move, context)["total"]


static func explain_move(move: Dictionary, context: AiContext, _use_lookahead: bool = true) -> Dictionary:
	var factors: Array = []
	var peer_id := context.peer_id
	var opponent_id := context.opponent_id
	var before_ratings := PowerRating.compute_all(
		GameState.get_board_state(),
		GameState.faction_scores.duplicate()
	)
	var before_ai := PowerRating.compute_ai_power(
		before_ratings,
		peer_id,
		opponent_id,
		context
	)

	if str(move.get("kind", "")) == AiMoveGenerator.KIND_END_ACTIONS:
		return _build_explanation(
			before_ratings,
			before_ratings,
			before_ai,
			before_ai,
			0.0,
			factors,
			context
		)

	if str(move.get("kind", "")) == AiMoveGenerator.KIND_DISCARD:
		return _explain_discard_move(move, context, before_ratings, before_ai)

	var move_kind := str(move.get("kind", ""))
	if move_kind in [
		AiMoveGenerator.KIND_SHOP_BUY,
		AiMoveGenerator.KIND_SHOP_DEPLOY_FACTION,
		AiMoveGenerator.KIND_SHOP_KING_DEPLOY,
	]:
		return _explain_shop_move(move, context, before_ratings, before_ai)

	if move_kind in [AiMoveGenerator.KIND_PEGGING_PLAY, AiMoveGenerator.KIND_PEGGING_PASS]:
		return _explain_pegging_move(move, before_ratings, before_ai, context)

	if move_kind == AiMoveGenerator.KIND_CRIB_CHOICE:
		return _explain_crib_choice_move(move, context, before_ratings, before_ai)

	if not _use_lookahead:
		return _build_explanation(
			before_ratings,
			before_ratings,
			before_ai,
			before_ai,
			0.0,
			factors,
			context
		)

	var snapshot: Dictionary = GameState.export_debug_snapshot()
	Search.apply_move(peer_id, move)
	var after_ratings := PowerRating.compute_all(
		GameState.get_board_state(),
		GameState.faction_scores.duplicate()
	)
	var after_context := AiContext.from_game(peer_id)
	var scored := PowerRating.compute_ai_power_delta(
		before_ratings,
		after_ratings,
		peer_id,
		opponent_id,
		context,
		after_context,
		factors
	)
	Search.restore_snapshot(snapshot)

	var total := float(scored.get("total", 0.0))
	factors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a.get("score", 0.0))) > absf(float(b.get("score", 0.0)))
	)
	return _build_explanation(
		before_ratings,
		after_ratings,
		scored.get("before", before_ai),
		scored.get("after", {}),
		total,
		factors,
		context
	)


static func _decision_method(require_positive: bool) -> String:
	if GameState.current_phase == GameState.Phase.DISCARD_TO_CRIB:
		return "discard_heuristic"
	if require_positive:
		return "ai_power_positive"
	return "ai_power"


static func _explain_shop_move(
	move: Dictionary,
	context: AiContext,
	before_ratings: Dictionary,
	before_ai: Dictionary
) -> Dictionary:
	var factors: Array = []
	var sequence_eval := ShopEvaluator.evaluate_buy_sequence(context.peer_id, move, context)
	var total := float(move.get("_shop_sequence_delta", 0.0))
	if sequence_eval.is_empty():
		if absf(total) < 0.01:
			var decision: Dictionary = move.get("_decision", {})
			total = float(decision.get("chosen_evaluator_score", 0.0))
		return _build_explanation(
			before_ratings,
			before_ratings,
			before_ai,
			before_ai,
			total,
			factors,
			context
		)

	if absf(total) < 0.01:
		total = float(sequence_eval.get("delta", 0.0))

	return _build_explanation(
		sequence_eval.get("before_ratings", before_ratings),
		sequence_eval.get("after_ratings", before_ratings),
		sequence_eval.get("before_ai", before_ai),
		sequence_eval.get("after_ai", {}),
		total,
		factors,
		context
	)


static func _explain_pegging_move(
	move: Dictionary,
	before_ratings: Dictionary,
	before_ai: Dictionary,
	context: AiContext
) -> Dictionary:
	var factors: Array = []
	var total := 0.0
	var kind := str(move.get("kind", ""))

	if kind == AiMoveGenerator.KIND_PEGGING_PLAY:
		var hand_index := int(move.get("hand_index", -1))
		var hand: Array = GameState.get_hand_for_peer(context.peer_id)
		if hand_index < 0 or hand_index >= hand.size():
			total = -100.0
		else:
			var card: Dictionary = hand[hand_index]
			var new_total := GameState.pegging_total + int(card.get("value", 0))
			var sequence: Array = GameState.pegging_sequence.duplicate(true)
			sequence.append(card)
			var is_last_pegging_card := (
				GameState.get_total_pegging_cards_played() + 1 >= PeggingPhase.MAX_CARDS_PLAYED
			)
			for event in PeggingRules.score_events(sequence, new_total):
				if event == "thirty_one":
					total += float(
						CribbageScoring.pegging_thirty_one_coins(
							GameState.pegging_go_awarded_this_count()
						)
					)
					continue
				total += float(CribbageScoring.pegging_event_coins(event))
			if is_last_pegging_card:
				total += float(CribbageScoring.pegging_event_coins("last_card"))
	elif kind == AiMoveGenerator.KIND_PEGGING_PASS:
		total = 0.0

	return _build_explanation(
		before_ratings,
		before_ratings,
		before_ai,
		before_ai,
		total,
		factors,
		context
	)


static func _explain_crib_choice_move(
	move: Dictionary,
	context: AiContext,
	before_ratings: Dictionary,
	before_ai: Dictionary
) -> Dictionary:
	var factors: Array = []
	var snapshot: Dictionary = GameState.export_debug_snapshot()
	Search.apply_move(context.peer_id, move)

	var after_ratings := PowerRating.compute_all(
		GameState.get_board_state(),
		GameState.faction_scores.duplicate()
	)
	var after_context := AiContext.from_game(context.peer_id)
	var scored := PowerRating.compute_ai_power_delta(
		before_ratings,
		after_ratings,
		context.peer_id,
		context.opponent_id,
		context,
		after_context,
		factors
	)

	Search.restore_snapshot(snapshot)

	return _build_explanation(
		before_ratings,
		after_ratings,
		before_ai,
		scored.get("after", before_ai),
		float(scored.get("total", 0.0)),
		factors,
		after_context
	)


static func _explain_discard_move(
	move: Dictionary,
	context: AiContext,
	before_ratings: Dictionary,
	before_ai: Dictionary
) -> Dictionary:
	var factors: Array = []
	var hand: Array = GameState.get_hand_for_peer(context.peer_id)
	var discard_indices: Dictionary = {}
	for index in move.get("card_indices", []):
		discard_indices[int(index)] = true

	var kept: Array = []
	var discarded: Array = []
	for card_index in range(hand.size()):
		var card: Dictionary = hand[card_index]
		if discard_indices.has(card_index):
			discarded.append(card)
		else:
			kept.append(card)

	var action_count := CribbageScoring.count_actions_from_cards(kept, {})
	var action_score := float(action_count) * DISCARD_POINTS_PER_ACTION
	if action_count > 0:
		factors.append({
			"label": "Show-hand actions kept (%d × 7)" % action_count,
			"score": action_score,
		})

	var top_factions := _most_powerful_factions_by_rating(before_ratings)
	var top_faction_count := 0
	for card in discarded:
		if GameState.get_card_faction_id(card) in top_factions:
			top_faction_count += 1

	var own_crib := int(context.peer_id) == int(GameState.crib_owner_peer_id)
	var faction_score := _append_discard_top_faction_factor(
		top_faction_count,
		top_factions,
		own_crib,
		factors
	)
	var total := action_score + faction_score
	factors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a.get("score", 0.0))) > absf(float(b.get("score", 0.0)))
	)
	var explanation := _build_explanation(
		before_ratings,
		before_ratings,
		before_ai,
		before_ai,
		total,
		factors,
		context
	)
	explanation["discard_scoring"] = {
		"action_count": action_count,
		"action_points": action_score,
		"top_faction_count": top_faction_count,
		"top_faction_ids": top_factions,
		"top_faction_names": _faction_names(top_factions),
		"top_faction_points": faction_score,
		"own_crib": own_crib,
		"total": total,
		"faction_powers": _faction_power_totals(before_ratings),
	}
	return explanation


static func _append_discard_top_faction_factor(
	top_faction_count: int,
	top_factions: Array,
	own_crib: bool,
	factors: Array
) -> float:
	if top_faction_count <= 0 or top_factions.is_empty():
		return 0.0

	var score := 0.0
	var label := ""
	var faction_names := _faction_names(top_factions)

	if top_faction_count == 1:
		score = DISCARD_OWN_CRIB_ONE_TOP_FACTION if own_crib else DISCARD_OPP_CRIB_ONE_TOP_FACTION
		label = "1 %s card to %s crib" % [
			faction_names,
			"own" if own_crib else "opponent",
		]
	else:
		score = DISCARD_OWN_CRIB_TWO_TOP_FACTION if own_crib else DISCARD_OPP_CRIB_TWO_TOP_FACTION
		label = "2 %s cards to %s crib" % [
			faction_names,
			"own" if own_crib else "opponent",
		]

	factors.append({
		"label": label,
		"score": score,
	})
	return score


static func _most_powerful_factions_by_rating(ratings: Dictionary) -> Array:
	var best_power := -INF
	for faction_id in Factions.ALL:
		best_power = maxf(
			best_power,
			float(ratings.get(faction_id, {}).get("total", 0.0))
		)

	if best_power <= -INF:
		return []

	var top_factions: Array = []
	for faction_id in Factions.ALL:
		var power := float(ratings.get(faction_id, {}).get("total", 0.0))
		if is_equal_approx(power, best_power):
			top_factions.append(faction_id)
	return top_factions


static func _faction_power_totals(ratings: Dictionary) -> Dictionary:
	var totals := {}
	for faction_id in Factions.ALL:
		totals[faction_id] = float(ratings.get(faction_id, {}).get("total", 0.0))
	return totals


static func _faction_names(faction_ids: Array) -> String:
	var names: PackedStringArray = PackedStringArray()
	for faction_id in faction_ids:
		names.append(Factions.name_for(int(faction_id)))
	return "/".join(names)


static func _build_explanation(
	before_ratings: Dictionary,
	after_ratings: Dictionary,
	ai_power_before: Dictionary,
	ai_power_after: Dictionary,
	total: float,
	factors: Array,
	context: AiContext
) -> Dictionary:
	return {
		"total": total,
		"immediate": total,
		"lookahead": 0.0,
		"factors": factors,
		"power_ratings_before": before_ratings,
		"power_ratings_after": after_ratings,
		"ai_power_before": ai_power_before,
		"ai_power_after": ai_power_after,
		"primary_faction": context.primary_faction,
		"scoring_faction": context.scoring_faction,
	}
