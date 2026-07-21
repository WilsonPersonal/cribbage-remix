class_name AiPositionEval
extends RefCounted

const WEIGHT_SCORING_FACTION_SCORE := 130.0
const WEIGHT_PRIMARY_FACTION_SCORE := 45.0
const WEIGHT_OTHER_FACTION_SCORE := 18.0
const WEIGHT_INFLUENCE_PRIMARY := 22.0
const WEIGHT_INFLUENCE_SCORING := 28.0
const WEIGHT_COINS := 9.0
const WEIGHT_ACTION_BUDGET := 24.0
const WEIGHT_BOARD_POWER_PRIMARY := 4.0
const WEIGHT_BOARD_POWER_OTHER := 1.5
const WEIGHT_CART_STEP_PRIMARY := 32.0
const WEIGHT_CART_STEP_OTHER := 4.0
const WEIGHT_CART_AT_GOAL_PRIMARY := 260.0
const WEIGHT_CART_AT_GOAL_OTHER := 35.0
const WEIGHT_ACTIVE_CART_COUNT_PRIMARY := -45.0


static func evaluate(peer_id: int, context: AiContext = null) -> float:
	if context == null:
		context = AiContext.from_game(peer_id)
	var opponent_context := AiContext.from_game(context.opponent_id)
	return _score_peer(peer_id, context) - _score_peer(context.opponent_id, opponent_context) * 0.9


static func _score_peer(peer_id: int, context: AiContext) -> float:
	var score := 0.0
	for faction_id in Factions.ALL:
		var faction_score := float(
			RemixRules.faction_dict_value(GameState.faction_scores, faction_id)
		)
		if faction_id == context.scoring_faction:
			score += faction_score * WEIGHT_SCORING_FACTION_SCORE
		elif faction_id == context.primary_faction:
			score += faction_score * WEIGHT_PRIMARY_FACTION_SCORE
		else:
			score += faction_score * WEIGHT_OTHER_FACTION_SCORE

	var influence: Dictionary = GameState.player_influence.get(
		peer_id,
		RemixRules.empty_influence()
	)
	score += float(RemixRules.faction_dict_value(influence, context.primary_faction)) * WEIGHT_INFLUENCE_PRIMARY
	score += float(RemixRules.faction_dict_value(influence, context.scoring_faction)) * WEIGHT_INFLUENCE_SCORING

	score += float(int(GameState.player_coins.get(peer_id, 0))) * WEIGHT_COINS

	if GameState.current_phase == GameState.Phase.SPEND_ACTIONS:
		score += float(GameState.get_total_actions_for_peer(peer_id)) * WEIGHT_ACTION_BUDGET
		score += float(GameState.get_action_points_for_peer(peer_id)) * WEIGHT_ACTION_BUDGET * 0.35

	var board_power: Dictionary = GameState.get_faction_power()
	for faction_id in Factions.ALL:
		var power := float(RemixRules.faction_dict_value(board_power, faction_id))
		if faction_id == context.primary_faction:
			score += power * WEIGHT_BOARD_POWER_PRIMARY
		else:
			score += power * WEIGHT_BOARD_POWER_OTHER

	score += _score_cart_positions(context)
	return score


static func _score_cart_positions(context: AiContext) -> float:
	var board := HexBoard.new()
	board.load_state(GameState.get_board_state())
	var score := 0.0
	var primary_active_carts := 0

	for hex_index in range(HexBoard.HEX_COUNT):
		var carts: Dictionary = board.hexes[hex_index].get("carts", {})
		for faction_id in carts.keys():
			var is_primary := int(faction_id) == context.primary_faction
			for origin_hex in carts[faction_id]:
				var goal_hex := int(HexBoard.CART_GOALS.get(int(origin_hex), -1))
				if goal_hex < 0:
					continue
				var steps := board.cart_path_steps_to_goal(int(origin_hex), hex_index)
				if steps <= 0:
					score += WEIGHT_CART_AT_GOAL_PRIMARY if is_primary else WEIGHT_CART_AT_GOAL_OTHER
				else:
					if is_primary:
						primary_active_carts += 1
					var step_weight := WEIGHT_CART_STEP_PRIMARY if is_primary else WEIGHT_CART_STEP_OTHER
					score += step_weight / float(steps)

	if primary_active_carts > 1:
		score += float(primary_active_carts - 1) * WEIGHT_ACTIVE_CART_COUNT_PRIMARY

	return score
