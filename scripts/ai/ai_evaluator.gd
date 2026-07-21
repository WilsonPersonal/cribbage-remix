class_name AiEvaluator
extends RefCounted

const WEIGHT_PRIMARY_CART_CREATE := 220.0
const WEIGHT_OTHER_CART_CREATE := 20.0
const WEIGHT_PRIMARY_CART_MOVE := 160.0
const WEIGHT_PRIMARY_CART_MOVE_PER_STEP := 30.0
const WEIGHT_OTHER_CART_MOVE := 15.0
const WEIGHT_PRIMARY_CART_SCORE := 900.0
const WEIGHT_OTHER_CART_SCORE := 50.0
const WEIGHT_PRIMARY_SCORING := 70.0
const WEIGHT_SCORING_FACTION := 55.0
const WEIGHT_PRIMARY_CONTROL := 35.0
const WEIGHT_NON_PRIMARY_CART_ACTION := -120.0
const WEIGHT_INFLUENCE_GAIN := 40.0
const WEIGHT_BOARD_POWER := 18.0
const WEIGHT_SHOP_QUEEN := 45.0
const WEIGHT_SHOP_KING := 30.0
const WEIGHT_SHOP_JACK := 25.0
const WEIGHT_PEGGING_SCORE := 50.0
const WEIGHT_END_ACTIONS := -5.0


static func choose_best_move(moves: Array, context: AiContext) -> Dictionary:
	if moves.is_empty():
		return {}

	var best_move: Dictionary = moves[0]
	var best_score := -INF
	for move in moves:
		var score := evaluate_move(move, context)
		if score > best_score:
			best_score = score
			best_move = move
	return best_move


static func evaluate_move(move: Dictionary, context: AiContext) -> float:
	var immediate := _evaluate_immediate(move, context)
	var lookahead := evaluate_lookahead(move, context, 1)
	return immediate + lookahead


static func evaluate_lookahead(_move: Dictionary, _context: AiContext, depth: int) -> float:
	if depth <= 0:
		return 0.0
	# Reserved for simulating alternating player replies.
	return 0.0


static func _evaluate_immediate(move: Dictionary, context: AiContext) -> float:
	match str(move.get("kind", "")):
		AiMoveGenerator.KIND_DISCARD:
			return _score_discard(move, context)
		AiMoveGenerator.KIND_PEGGING_PLAY:
			return _score_pegging_play(move, context)
		AiMoveGenerator.KIND_PEGGING_PASS:
			return 0.0
		AiMoveGenerator.KIND_FACTION_ACTION:
			return _score_faction_action(move, context)
		AiMoveGenerator.KIND_SHOP_BUY:
			return _score_shop_buy(move, context)
		AiMoveGenerator.KIND_SHOP_DEPLOY_FACTION:
			return _score_shop_deploy_faction(move, context)
		AiMoveGenerator.KIND_SHOP_JACK_PUSH, AiMoveGenerator.KIND_SHOP_KING_DEPLOY:
			return _score_shop_follow_up(move, context)
		AiMoveGenerator.KIND_CRIB_CHOICE:
			return _score_crib_choice(move, context)
		AiMoveGenerator.KIND_END_ACTIONS:
			return _score_end_actions(context)
	return 0.0


static func _score_discard(_move: Dictionary, context: AiContext) -> float:
	return 1.0 + float(context.primary_faction) * 0.01


static func _score_pegging_play(move: Dictionary, context: AiContext) -> float:
	var hand: Array = GameState.get_hand_for_peer(context.peer_id)
	var hand_index := int(move.get("hand_index", -1))
	if hand_index < 0 or hand_index >= hand.size():
		return -100.0

	var card: Dictionary = hand[hand_index]
	var next_total := GameState.pegging_total + int(card.get("value", 0))
	var sequence: Array = GameState.pegging_sequence.duplicate(true)
	sequence.append(card)
	var score := 0.0
	for event_type in PeggingRules.score_events(sequence, next_total):
		score += WEIGHT_PEGGING_SCORE + float(CribbageScoring.pegging_event_coins(event_type))

	# Prefer keeping lower cards when not scoring.
	if score <= 0.0:
		score -= float(int(card.get("value", 0))) * 0.5
	return score


static func _score_faction_action(move: Dictionary, context: AiContext) -> float:
	var faction_id := int(move.get("faction_id", -1))
	var action_type := int(move.get("action_type", -1))
	var hex_index := int(move.get("hex_index", -1))
	var target_hex := int(move.get("target_hex", -1))
	var move_cart_also := bool(move.get("move_cart_also", false))
	var score := 0.0
	var is_primary := faction_id == context.primary_faction

	match action_type:
		ActionSystem.Type.CREATE_CART:
			if is_primary:
				score += WEIGHT_PRIMARY_CART_CREATE
				score += WEIGHT_PRIMARY_CONTROL
			else:
				score += WEIGHT_OTHER_CART_CREATE
				score += WEIGHT_NON_PRIMARY_CART_ACTION
		ActionSystem.Type.PUSH, ActionSystem.Type.PULL:
			score += _score_board_control_delta(faction_id, hex_index, target_hex, action_type)
			if move_cart_also:
				score += _score_cart_progress(
					faction_id,
					hex_index,
					target_hex,
					action_type,
					context
				)
				if not is_primary:
					score += WEIGHT_NON_PRIMARY_CART_ACTION
			elif is_primary:
				score += WEIGHT_PRIMARY_CONTROL * 0.35
			elif faction_id == context.scoring_faction:
				score += WEIGHT_SCORING_FACTION * 0.5

	score += float(RemixRules.faction_dict_value(GameState.get_faction_power(), faction_id)) * 0.05
	return score


static func _score_board_control_delta(
	faction_id: int,
	hex_index: int,
	target_hex: int,
	action_type: int
) -> float:
	var score := 0.0
	var destination := target_hex if action_type == ActionSystem.Type.PUSH else hex_index
	if GameState.get_controlling_faction(destination) == faction_id:
		score += WEIGHT_BOARD_POWER * 0.5
	if GameState.get_controlling_faction(destination) != faction_id:
		score += WEIGHT_BOARD_POWER
	return score


static func _score_cart_progress(
	faction_id: int,
	hex_index: int,
	target_hex: int,
	action_type: int,
	context: AiContext
) -> float:
	var score := 0.0
	var is_primary := faction_id == context.primary_faction
	var board := HexBoard.new()
	board.load_state(GameState.get_board_state())

	var from_hex := hex_index
	var to_hex := target_hex
	if action_type == ActionSystem.Type.PULL:
		from_hex = target_hex
		to_hex = hex_index

	for origin_hex in board.hexes[from_hex]["carts"].get(faction_id, []):
		if not board.cart_can_advance(faction_id, from_hex, to_hex, int(origin_hex)):
			continue
		var goal_hex := int(HexBoard.CART_GOALS.get(int(origin_hex), -1))
		if goal_hex < 0:
			continue
		var before := board.cart_path_steps_to_goal(int(origin_hex), from_hex)
		var after := board.cart_path_steps_to_goal(int(origin_hex), to_hex)
		if after < before:
			var steps := float(before - after)
			if is_primary:
				score += WEIGHT_PRIMARY_CART_MOVE + steps * WEIGHT_PRIMARY_CART_MOVE_PER_STEP
			else:
				score += WEIGHT_OTHER_CART_MOVE
		if after == 0:
			if is_primary:
				score += WEIGHT_PRIMARY_CART_SCORE
			else:
				score += WEIGHT_OTHER_CART_SCORE
	return score


static func _score_shop_buy(move: Dictionary, context: AiContext) -> float:
	var card: Dictionary = move.get("card", {})
	var faction_id := _card_faction_id(card)
	var score := 0.0
	match Shop.card_effect(card):
		Shop.EFFECT_QUEEN:
			score += WEIGHT_SHOP_QUEEN
			if faction_id == context.primary_faction:
				score += WEIGHT_PRIMARY_SCORING * 0.5
			if faction_id == context.scoring_faction:
				score += WEIGHT_SCORING_FACTION * 0.5
		Shop.EFFECT_KING:
			score += WEIGHT_SHOP_KING
			if faction_id == context.scoring_faction or faction_id == Factions.Id.SPADES:
				score += 10.0
		Shop.EFFECT_JACK:
			score += WEIGHT_SHOP_JACK
	score -= float(int(move.get("slot_index", 0))) * 0.5
	return score


static func _score_shop_deploy_faction(move: Dictionary, context: AiContext) -> float:
	var faction_id := int(move.get("faction_id", -1))
	var score := 10.0
	if faction_id == context.scoring_faction:
		score += WEIGHT_SCORING_FACTION
	if faction_id == context.primary_faction:
		score += WEIGHT_PRIMARY_CONTROL
	match GameState.get_pending_shop_effect():
		Shop.EFFECT_JACK:
			score += float(_count_valid_jack_pushes(context.peer_id, faction_id)) * 8.0
		Shop.EFFECT_KING:
			score += float(GameState.get_hexes_with_deploy_space(faction_id).size()) * 4.0
	return score


static func _score_shop_follow_up(move: Dictionary, context: AiContext) -> float:
	var faction_id := int(move.get("faction_id", GameState.get_pending_shop_deploy_faction()))
	var score := 15.0
	if faction_id == context.scoring_faction:
		score += WEIGHT_SCORING_FACTION
	if faction_id == context.primary_faction:
		score += WEIGHT_PRIMARY_CONTROL
	match str(move.get("kind", "")):
		AiMoveGenerator.KIND_SHOP_JACK_PUSH:
			score += _score_board_control_delta(
				faction_id,
				int(move.get("from_hex", -1)),
				int(move.get("to_hex", -1)),
				ActionSystem.Type.PUSH
			)
		AiMoveGenerator.KIND_SHOP_KING_DEPLOY:
			score += float(RemixRules.faction_dict_value(GameState.get_faction_power(), faction_id)) * 0.1
	return score


static func _count_valid_jack_pushes(peer_id: int, faction_id: int) -> int:
	if not GameState.faction_has_cubes_on_board(faction_id):
		return 0
	if not GameState.player_can_act_with_faction(peer_id, faction_id):
		return 0
	var count := 0
	for from_hex in GameState.get_hexes_with_faction_cubes(faction_id):
		if GameState.get_faction_cubes_on_hex(from_hex, faction_id) <= 0:
			continue
		for to_hex in GameState.get_adjacent_hexes(from_hex):
			if GameState.get_available_cube_space(faction_id, to_hex) > 0:
				count += 1
	return count


static func _score_crib_choice(move: Dictionary, context: AiContext) -> float:
	var faction_id := int(move.get("faction_id", -1))
	var score := 0.0
	if bool(move.get("accept", false)):
		score += WEIGHT_INFLUENCE_GAIN
		if faction_id == context.scoring_faction:
			score += WEIGHT_SCORING_FACTION
		if faction_id == context.primary_faction:
			score += WEIGHT_PRIMARY_CONTROL
	else:
		score += WEIGHT_BOARD_POWER
		if faction_id == context.scoring_faction:
			score += WEIGHT_SCORING_FACTION * 0.75
	return score


static func _score_end_actions(context: AiContext) -> float:
	if GameState.has_pending_shop_action(context.peer_id):
		return -100.0
	if not GameState.player_can_afford_any_action(context.peer_id):
		return 10.0
	var remaining := float(GameState.get_action_points_for_peer(context.peer_id))
	return WEIGHT_END_ACTIONS - remaining * 50.0


static func _card_faction_id(card: Dictionary) -> int:
	if card.has("faction"):
		return int(card["faction"])
	return Factions.from_suit(str(card.get("suit", "clubs")))
