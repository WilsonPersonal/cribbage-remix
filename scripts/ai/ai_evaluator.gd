class_name AiEvaluator
extends RefCounted

const Search := preload("res://scripts/ai/ai_search.gd")
const WEIGHT_PRIMARY_CART_CREATE := 180.0
const WEIGHT_OTHER_CART_CREATE := 20.0
const WEIGHT_PRIMARY_CART_MOVE := 240.0
const WEIGHT_PRIMARY_CART_MOVE_PER_STEP := 52.0
const WEIGHT_OTHER_CART_MOVE := 15.0
const WEIGHT_PRIMARY_CART_SCORE := 1300.0
const WEIGHT_OTHER_CART_SCORE := 50.0
const WEIGHT_CART_NEAR_GOAL_URGENCY := 180.0
const WEIGHT_CREATE_CART_WHILE_ACTIVE := -320.0
const WEIGHT_CREATE_CART_NEAR_DELIVERY := -520.0
const WEIGHT_SKIPPED_CART_ESCORT := 0.9
const WEIGHT_PRIMARY_SCORING := 70.0
const WEIGHT_SCORING_FACTION := 55.0
const WEIGHT_PRIMARY_CONTROL := 35.0
const WEIGHT_NON_PRIMARY_CART_ACTION := -120.0
const WEIGHT_NON_PRIMARY_FACTION_ACTION := -95.0
const WEIGHT_NEUTRAL_FACTION_ACTION := -140.0
const WEIGHT_UNINVESTED_FACTION_ACTION := -70.0
const WEIGHT_PRIMARY_FACTION_ACTION := 30.0
const WEIGHT_PRIMARY_MOUNTAIN_APPROACH := 52.0
const WEIGHT_PRIMARY_GAIN_DOMINANCE := 32.0
const WEIGHT_PRIMARY_NON_DOMINANT_DESTINATION := -115.0
const WEIGHT_PRIMARY_NON_DOMINANT_MOUNTAIN_BUILD := -40.0
const WEIGHT_PRIMARY_RECOVER_CUBE := 42.0
const WEIGHT_PRIMARY_RECOVER_FROM_FOREST := 34.0
const WEIGHT_PRIMARY_CLEAR_STRANDED_HEX := 55.0
const WEIGHT_INFLUENCE_GAIN := 40.0
const WEIGHT_BOARD_POWER := 18.0
const WEIGHT_MOUNTAIN_CART_READY := 78.0
const WEIGHT_MOUNTAIN_DOMINANCE_PROGRESS := 34.0
const WEIGHT_BREAK_OPPONENT_ESCORT := 92.0
const WEIGHT_SPLIT_OPPONENT_ESCORT := 30.0
const WEIGHT_OPPONENT_LOST_CONTROL := 24.0
const WEIGHT_SPLIT_OPPONENT_STACK := 16.0
const WEIGHT_SHOP_QUEEN := 45.0
const WEIGHT_SHOP_KING := 30.0
const WEIGHT_SHOP_JACK := 25.0
const WEIGHT_DISCARD_ACTIONS := 100.0
const WEIGHT_DISCARD_CRIB_FACTION := 45.0
const WEIGHT_PEGGING_SCORE := 50.0
const WEIGHT_END_ACTIONS := -5.0


static func choose_best_move(moves: Array, context: AiContext, use_lookahead: bool = true) -> Dictionary:
	if moves.is_empty():
		return {}

	var best_move: Dictionary = moves[0]
	var best_score := -INF
	for move in moves:
		var score := evaluate_move(move, context, use_lookahead)
		if score > best_score:
			best_score = score
			best_move = move
	return best_move


static func evaluate_move(move: Dictionary, context: AiContext, use_lookahead: bool = true) -> float:
	var immediate := _evaluate_immediate(move, context)
	if not use_lookahead:
		return immediate
	var lookahead := evaluate_lookahead(move, context, 1)
	return immediate + lookahead


static func evaluate_lookahead(move: Dictionary, context: AiContext, depth: int) -> float:
	if depth <= 0:
		return 0.0
	if context.phase != GameState.Phase.PEGGING:
		return 0.0
	if str(move.get("kind", "")) not in [AiMoveGenerator.KIND_PEGGING_PLAY, AiMoveGenerator.KIND_PEGGING_PASS]:
		return 0.0

	var snapshot: Dictionary = GameState.export_debug_snapshot()
	Search.restore_snapshot(snapshot)
	Search.apply_move(context.peer_id, move)

	if GameState.current_phase != GameState.Phase.PEGGING:
		Search.restore_snapshot(snapshot)
		return 0.0

	var opponent_id := context.opponent_id
	if GameState.pegging_turn_peer != opponent_id:
		Search.restore_snapshot(snapshot)
		return 0.0

	var opponent_moves: Array = AiMoveGenerator.generate_moves(opponent_id)
	if opponent_moves.is_empty():
		Search.restore_snapshot(snapshot)
		return 0.0

	var opponent_context := AiContext.from_game(opponent_id)
	var worst_reply := -INF
	for reply in opponent_moves:
		Search.restore_snapshot(snapshot)
		Search.apply_move(context.peer_id, move)
		Search.apply_move(opponent_id, reply)
		var reply_score := _evaluate_immediate(reply, opponent_context) * 0.65
		if reply_score > worst_reply:
			worst_reply = reply_score

	Search.restore_snapshot(snapshot)
	if worst_reply == -INF:
		return 0.0
	return -worst_reply


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


static func _score_discard(move: Dictionary, context: AiContext) -> float:
	var hand: Array = GameState.get_hand_for_peer(context.peer_id)
	var discard_indices: Array = move.get("card_indices", [])
	var kept: Array = []
	var discarded: Array = []

	for card_index in range(hand.size()):
		var card: Dictionary = hand[card_index]
		if card_index in discard_indices:
			discarded.append(card)
		else:
			kept.append(card)

	var action_score := float(CribbageScoring.count_actions_from_cards(kept, {})) * WEIGHT_DISCARD_ACTIONS
	var crib_faction_score := _score_discard_crib_factions(discarded, context)
	return action_score + crib_faction_score


static func _score_discard_crib_factions(discarded: Array, context: AiContext) -> float:
	var target_factions := _target_crib_factions()
	var own_crib := int(context.peer_id) == int(GameState.crib_owner_peer_id)
	var score := 0.0

	for card in discarded:
		var faction_id := _card_faction_id(card)
		if faction_id not in Factions.ALL:
			continue
		var is_target := faction_id in target_factions
		if own_crib:
			score += WEIGHT_DISCARD_CRIB_FACTION if is_target else -WEIGHT_DISCARD_CRIB_FACTION * 0.35
		else:
			score += WEIGHT_DISCARD_CRIB_FACTION if not is_target else -WEIGHT_DISCARD_CRIB_FACTION

	return score


static func _target_crib_factions() -> Array:
	var leading_score := -1
	for faction_id in Factions.ALL:
		leading_score = maxi(
			leading_score,
			int(GameState.faction_scores.get(faction_id, 0))
		)

	var targets: Array = []
	for faction_id in Factions.ALL:
		if int(GameState.faction_scores.get(faction_id, 0)) == leading_score:
			targets.append(faction_id)

	var potential := _faction_cart_points_this_round()
	for faction_id in Factions.ALL:
		if faction_id in targets:
			continue
		var projected := int(GameState.faction_scores.get(faction_id, 0)) + int(potential.get(faction_id, 0))
		if int(potential.get(faction_id, 0)) > 0 and projected >= leading_score:
			targets.append(faction_id)

	return targets


static func _faction_cart_points_this_round() -> Dictionary:
	var board := HexBoard.new()
	board.load_state(GameState.get_board_state())
	var potential := {
		Factions.Id.CLUBS: 0,
		Factions.Id.HEARTS: 0,
		Factions.Id.DIAMONDS: 0,
	}

	for hex_index in range(HexBoard.HEX_COUNT):
		for faction_id in Factions.ALL:
			for origin_hex in board.hexes[hex_index]["carts"].get(faction_id, []):
				var steps := board.cart_path_steps_to_goal(int(origin_hex), hex_index)
				if steps == 0:
					potential[faction_id] = int(potential[faction_id]) + 1
				elif steps == 1:
					potential[faction_id] = int(potential[faction_id]) + 1

	return potential


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
			score += _score_faction_influence_alignment(faction_id, context)
			score += _score_create_cart_penalty(faction_id, context)
			if is_primary:
				score += WEIGHT_PRIMARY_CART_CREATE
				score += WEIGHT_PRIMARY_CONTROL
			else:
				score += WEIGHT_OTHER_CART_CREATE
				score += WEIGHT_NON_PRIMARY_CART_ACTION
		ActionSystem.Type.PUSH, ActionSystem.Type.PULL:
			score += _score_faction_influence_alignment(faction_id, context)
			if is_primary:
				score += _score_primary_destination_dominance(
					faction_id,
					hex_index,
					target_hex,
					action_type,
					int(move.get("cube_count", 1)),
					context
				)
			else:
				score += _score_board_control_delta(faction_id, hex_index, target_hex, action_type)
			score += _score_mountain_cart_setup(
				faction_id,
				hex_index,
				target_hex,
				action_type,
				int(move.get("cube_count", 1)),
				context
			)
			score += _score_primary_mountain_approach(
				faction_id,
				hex_index,
				target_hex,
				action_type,
				int(move.get("cube_count", 1)),
				context
			)
			score += _score_primary_cube_recovery(
				faction_id,
				hex_index,
				target_hex,
				action_type,
				int(move.get("cube_count", 1)),
				context
			)
			score += _score_opponent_disruption(
				faction_id,
				hex_index,
				target_hex,
				action_type,
				int(move.get("cube_count", 1)),
				context
			)
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
			else:
				score += _score_skipped_cart_escort(
					faction_id,
					hex_index,
					target_hex,
					action_type,
					context
				)
				if faction_id == context.scoring_faction and not is_primary:
					score += WEIGHT_SCORING_FACTION * 0.5

	score += float(RemixRules.faction_dict_value(GameState.get_faction_power(), faction_id)) * 0.05
	return score


static func _score_mountain_cart_setup(
	faction_id: int,
	hex_index: int,
	target_hex: int,
	action_type: int,
	cube_count: int,
	context: AiContext
) -> float:
	var simulated := _simulate_cube_move(faction_id, hex_index, target_hex, action_type, cube_count)
	if simulated.is_empty():
		return 0.0

	var before: HexBoard = simulated["before"]
	var after: HexBoard = simulated["after"]
	var destination := _cube_move_destination(hex_index, target_hex, action_type)
	if destination not in HexBoard.MOUNTAIN_HEXES:
		return 0.0

	var score := 0.0
	var checked_factions: Array = []
	for setup_faction in [context.primary_faction, context.scoring_faction, faction_id]:
		if setup_faction in checked_factions or setup_faction not in Factions.ALL:
			continue
		checked_factions.append(setup_faction)

		var had_control := before.controls_hex(setup_faction, destination)
		var has_control := after.controls_hex(setup_faction, destination)
		if has_control and after.cube_count_for(setup_faction, destination) > 0:
			var goal_hex := int(HexBoard.CART_GOALS.get(destination, -1))
			if goal_hex >= 0 and not after.faction_has_cart_heading_to(setup_faction, destination, goal_hex):
				var weight := WEIGHT_MOUNTAIN_CART_READY
				if setup_faction == context.primary_faction:
					weight *= 1.35
				if not had_control:
					weight += WEIGHT_MOUNTAIN_DOMINANCE_PROGRESS
				score += weight
				continue

		if has_control or setup_faction != faction_id:
			continue

		var before_count := before.cube_count_for(faction_id, destination)
		var after_count := after.cube_count_for(faction_id, destination)
		if after_count <= before_count:
			continue

		var opp_before := _leading_opponent_cube_count(before, faction_id, destination)
		var opp_after := _leading_opponent_cube_count(after, faction_id, destination)
		if after_count > opp_after and before_count <= opp_before:
			score += WEIGHT_MOUNTAIN_DOMINANCE_PROGRESS * (
				1.25 if faction_id == context.primary_faction else 1.0
			)

	return score


static func _score_opponent_disruption(
	faction_id: int,
	hex_index: int,
	target_hex: int,
	action_type: int,
	cube_count: int,
	context: AiContext
) -> float:
	var simulated := _simulate_cube_move(faction_id, hex_index, target_hex, action_type, cube_count)
	if simulated.is_empty():
		return 0.0

	var before: HexBoard = simulated["before"]
	var after: HexBoard = simulated["after"]
	var opponent_faction := AiContext.highest_influence_faction_for(context.opponent_id)
	var score := 0.0

	for check_hex in range(HexBoard.HEX_COUNT):
		var had_control := before.controls_hex(opponent_faction, check_hex)
		var has_control := after.controls_hex(opponent_faction, check_hex)
		var escorted := _hex_has_faction_carts(before, opponent_faction, check_hex)

		if had_control and not has_control:
			score += WEIGHT_BREAK_OPPONENT_ESCORT if escorted else WEIGHT_OPPONENT_LOST_CONTROL
			continue

		if not had_control or not has_control:
			continue

		var cubes_before := before.cube_count_for(opponent_faction, check_hex)
		var cubes_after := after.cube_count_for(opponent_faction, check_hex)
		if cubes_after >= cubes_before:
			continue

		var split := cubes_before - cubes_after
		if escorted:
			score += float(split) * WEIGHT_SPLIT_OPPONENT_ESCORT
		elif cubes_before >= 2:
			score += float(split) * WEIGHT_SPLIT_OPPONENT_STACK

	return score * _disruption_faction_multiplier(faction_id, context)


static func _disruption_faction_multiplier(faction_id: int, context: AiContext) -> float:
	if faction_id == context.primary_faction:
		return 1.0
	if faction_id == AiContext.highest_influence_faction_for(context.opponent_id):
		return 0.8
	if AiContext.influence_for(context.peer_id, faction_id) <= 0:
		return 0.12
	return 0.35


static func _score_faction_influence_alignment(faction_id: int, context: AiContext) -> float:
	if faction_id == context.primary_faction:
		return WEIGHT_PRIMARY_FACTION_ACTION

	var my_influence := AiContext.influence_for(context.peer_id, faction_id)
	var opponent_influence := AiContext.influence_for(context.opponent_id, faction_id)
	var primary_influence := maxi(
		AiContext.influence_for(context.peer_id, context.primary_faction),
		1
	)

	var score := WEIGHT_NON_PRIMARY_FACTION_ACTION
	if my_influence <= 0 and opponent_influence <= 0:
		score += WEIGHT_NEUTRAL_FACTION_ACTION
	elif my_influence <= 0:
		score += WEIGHT_UNINVESTED_FACTION_ACTION

	if faction_id == context.scoring_faction and my_influence > 0:
		score += WEIGHT_SCORING_FACTION * 0.5
	elif my_influence < primary_influence:
		score -= float(primary_influence - my_influence) * 9.0

	return score


static func _score_primary_mountain_approach(
	faction_id: int,
	hex_index: int,
	target_hex: int,
	action_type: int,
	cube_count: int,
	context: AiContext
) -> float:
	if faction_id != context.primary_faction:
		return 0.0
	if action_type not in [ActionSystem.Type.PUSH, ActionSystem.Type.PULL]:
		return 0.0

	var simulated := _simulate_cube_move(faction_id, hex_index, target_hex, action_type, cube_count)
	if simulated.is_empty():
		return 0.0

	var before: HexBoard = simulated["before"]
	var after: HexBoard = simulated["after"]
	var before_distance := _closest_primary_mountain_distance(before, context.primary_faction)
	var after_distance := _closest_primary_mountain_distance(after, context.primary_faction)
	if after_distance >= before_distance:
		return 0.0

	return float(before_distance - after_distance) * WEIGHT_PRIMARY_MOUNTAIN_APPROACH


static func _score_primary_destination_dominance(
	faction_id: int,
	hex_index: int,
	target_hex: int,
	action_type: int,
	cube_count: int,
	context: AiContext
) -> float:
	if faction_id != context.primary_faction:
		return 0.0
	if action_type not in [ActionSystem.Type.PUSH, ActionSystem.Type.PULL]:
		return 0.0

	var simulated := _simulate_cube_move(faction_id, hex_index, target_hex, action_type, cube_count)
	if simulated.is_empty():
		return 0.0

	var before: HexBoard = simulated["before"]
	var after: HexBoard = simulated["after"]
	var destination := _cube_move_destination(hex_index, target_hex, action_type)
	var had_control := before.controls_hex(faction_id, destination)
	var has_control := after.controls_hex(faction_id, destination)

	if has_control:
		if not had_control:
			return WEIGHT_PRIMARY_GAIN_DOMINANCE
		return WEIGHT_BOARD_POWER * 0.5

	var penalty := WEIGHT_PRIMARY_NON_DOMINANT_DESTINATION
	if destination in HexBoard.MOUNTAIN_HEXES:
		var before_count := before.cube_count_for(faction_id, destination)
		var after_count := after.cube_count_for(faction_id, destination)
		if after_count > before_count:
			penalty = WEIGHT_PRIMARY_NON_DOMINANT_MOUNTAIN_BUILD

	return penalty


static func _score_primary_cube_recovery(
	faction_id: int,
	hex_index: int,
	target_hex: int,
	action_type: int,
	cube_count: int,
	context: AiContext
) -> float:
	if faction_id != context.primary_faction:
		return 0.0
	if action_type != ActionSystem.Type.PULL:
		return 0.0

	var simulated := _simulate_cube_move(faction_id, hex_index, target_hex, action_type, cube_count)
	if simulated.is_empty():
		return 0.0

	var before: HexBoard = simulated["before"]
	var after: HexBoard = simulated["after"]
	var source_hex := _cube_move_source(hex_index, target_hex, action_type)
	if before.controls_hex(faction_id, source_hex):
		return 0.0

	var before_count := before.cube_count_for(faction_id, source_hex)
	var after_count := after.cube_count_for(faction_id, source_hex)
	if after_count >= before_count:
		return 0.0

	var moved := before_count - after_count
	var score := float(moved) * WEIGHT_PRIMARY_RECOVER_CUBE
	if source_hex in HexBoard.FOREST_HEXES:
		score += float(moved) * WEIGHT_PRIMARY_RECOVER_FROM_FOREST
	if after_count <= 0:
		score += WEIGHT_PRIMARY_CLEAR_STRANDED_HEX

	return score


static func _closest_primary_mountain_distance(board: HexBoard, faction_id: int) -> int:
	var best_distance := 999
	for hex_index in range(HexBoard.HEX_COUNT):
		if board.cube_count_for(faction_id, hex_index) <= 0:
			continue
		best_distance = mini(best_distance, _best_viable_mountain_distance(board, faction_id, hex_index))
	return best_distance


static func _best_viable_mountain_distance(board: HexBoard, faction_id: int, from_hex: int) -> int:
	var best_distance := 999
	for mountain_hex in HexBoard.MOUNTAIN_HEXES:
		var goal_hex := int(HexBoard.CART_GOALS.get(mountain_hex, -1))
		if goal_hex < 0:
			continue
		if board.faction_has_cart_heading_to(faction_id, mountain_hex, goal_hex):
			continue
		best_distance = mini(best_distance, _hex_bfs_distance(from_hex, mountain_hex))
	return best_distance


static func _hex_bfs_distance(from_hex: int, to_hex: int) -> int:
	if from_hex == to_hex:
		return 0

	var visited: Dictionary = {from_hex: true}
	var queue: Array = [[from_hex, 0]]
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var hex: int = int(item[0])
		var distance: int = int(item[1])
		for neighbor in HexBoard.ADJACENCY.get(hex, []):
			var next_hex := int(neighbor)
			if next_hex == to_hex:
				return distance + 1
			if visited.has(next_hex):
				continue
			visited[next_hex] = true
			queue.append([next_hex, distance + 1])

	return 999


static func _simulate_cube_move(
	faction_id: int,
	hex_index: int,
	target_hex: int,
	action_type: int,
	cube_count: int
) -> Dictionary:
	if action_type not in [ActionSystem.Type.PUSH, ActionSystem.Type.PULL]:
		return {}

	var before := HexBoard.new()
	before.load_state(GameState.get_board_state())
	var after := HexBoard.new()
	after.load_state(GameState.get_board_state())

	var from_hex := hex_index
	var to_hex := target_hex
	if action_type == ActionSystem.Type.PULL:
		from_hex = target_hex
		to_hex = hex_index

	var available := after.cube_count_for(faction_id, from_hex)
	var space := after.available_cube_space(faction_id, to_hex)
	var move_count := mini(cube_count, mini(available, space))
	if move_count <= 0:
		return {}

	for _i in range(move_count):
		if not after.remove_cube(faction_id, from_hex):
			return {}
		if not after.add_cube(faction_id, to_hex):
			return {}

	return {"before": before, "after": after}


static func _cube_move_destination(hex_index: int, target_hex: int, action_type: int) -> int:
	if action_type == ActionSystem.Type.PUSH:
		return target_hex
	return hex_index


static func _cube_move_source(hex_index: int, target_hex: int, action_type: int) -> int:
	if action_type == ActionSystem.Type.PUSH:
		return hex_index
	return target_hex


static func _leading_opponent_cube_count(board: HexBoard, faction_id: int, hex_index: int) -> int:
	var best := 0
	for other_faction in Factions.ALL:
		if other_faction == faction_id:
			continue
		best = maxi(best, board.cube_count_for(other_faction, hex_index))
	return best


static func _hex_has_faction_carts(board: HexBoard, faction_id: int, hex_index: int) -> bool:
	return board.hexes[hex_index]["carts"].get(faction_id, []).size() > 0


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
				score += WEIGHT_CART_NEAR_GOAL_URGENCY / float(before + 1)
			else:
				score += WEIGHT_OTHER_CART_MOVE
		if after == 0:
			if is_primary:
				score += WEIGHT_PRIMARY_CART_SCORE
			else:
				score += WEIGHT_OTHER_CART_SCORE
	return score


static func _score_create_cart_penalty(faction_id: int, context: AiContext) -> float:
	var cart_info := _faction_active_cart_info(faction_id)
	var active_count := int(cart_info.get("active_count", 0))
	if active_count <= 0:
		return 0.0

	var penalty := WEIGHT_CREATE_CART_WHILE_ACTIVE
	if faction_id == context.primary_faction:
		penalty *= 1.15
	penalty *= float(active_count)

	var closest_steps := int(cart_info.get("closest_steps", 999))
	if closest_steps <= 3:
		penalty += WEIGHT_CREATE_CART_NEAR_DELIVERY * float(4 - closest_steps)

	return penalty


static func _score_skipped_cart_escort(
	faction_id: int,
	hex_index: int,
	target_hex: int,
	action_type: int,
	context: AiContext
) -> float:
	var cart_progress := _score_cart_progress(
		faction_id,
		hex_index,
		target_hex,
		action_type,
		context
	)
	if cart_progress <= 0.0:
		return 0.0

	return -cart_progress * WEIGHT_SKIPPED_CART_ESCORT


static func _faction_active_cart_info(faction_id: int) -> Dictionary:
	var board := HexBoard.new()
	board.load_state(GameState.get_board_state())
	var active_count := 0
	var closest_steps := 999

	for hex_index in range(HexBoard.HEX_COUNT):
		for origin_hex in board.hexes[hex_index]["carts"].get(faction_id, []):
			var steps := board.cart_path_steps_to_goal(int(origin_hex), hex_index)
			if steps <= 0:
				continue
			active_count += 1
			closest_steps = mini(closest_steps, steps)

	return {
		"active_count": active_count,
		"closest_steps": closest_steps,
	}


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
			var from_hex := int(move.get("from_hex", -1))
			var to_hex := int(move.get("to_hex", -1))
			score += _score_board_control_delta(
				faction_id,
				from_hex,
				to_hex,
				ActionSystem.Type.PUSH
			)
			score += _score_mountain_cart_setup(
				faction_id,
				from_hex,
				to_hex,
				ActionSystem.Type.PUSH,
				1,
				context
			)
			score += _score_opponent_disruption(
				faction_id,
				from_hex,
				to_hex,
				ActionSystem.Type.PUSH,
				1,
				context
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
	if AiMoveGenerator.has_actionable_moves(context.peer_id):
		var remaining := float(GameState.get_action_points_for_peer(context.peer_id))
		return WEIGHT_END_ACTIONS - remaining * 80.0
	if not GameState.player_can_afford_any_action(context.peer_id):
		return 10.0
	return WEIGHT_END_ACTIONS


static func _card_faction_id(card: Dictionary) -> int:
	if card.has("faction"):
		return int(card["faction"])
	return Factions.from_suit(str(card.get("suit", "clubs")))
