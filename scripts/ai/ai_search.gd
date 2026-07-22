class_name AiSearch
extends RefCounted

const MoveGenerator := preload("res://scripts/ai/ai_move_generator.gd")


static func move_key(move: Dictionary) -> String:
	return "%s|%d|%d|%d|%d|%d|%d|%d|%d" % [
		str(move.get("kind", "")),
		int(move.get("hand_index", -1)),
		int(move.get("action_type", -1)),
		int(move.get("hex_index", -1)),
		int(move.get("target_hex", -1)),
		int(move.get("from_hex", -1)),
		int(move.get("to_hex", -1)),
		int(move.get("faction_id", -1)),
		int(bool(move.get("move_cart_also", false))),
	]


static func apply_move(peer_id: int, move: Dictionary) -> void:
	GameState.push_ai_search_silence()
	GameState.run_as_peer(peer_id, func() -> void:
		_apply_move_on_server(move)
	)
	GameState.pop_ai_search_silence()


static func _apply_move_on_server(move: Dictionary) -> void:
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
			GameState.submit_crib_card_choice(
				int(move.get("card_index", -1)),
				bool(move.get("accept", false)),
				int(move.get("hex_index", -1))
			)
		MoveGenerator.KIND_END_ACTIONS:
			GameState.submit_end_action_phase()


static func restore_snapshot(snapshot: Dictionary) -> void:
	GameState.import_debug_snapshot(snapshot, false)


static func actionable_moves(peer_id: int) -> Array:
	var moves: Array = []
	for move in MoveGenerator.generate_moves(peer_id):
		if str(move.get("kind", "")) == MoveGenerator.KIND_END_ACTIONS:
			continue
		moves.append(move)
	return moves
