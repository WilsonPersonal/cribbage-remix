class_name AiContext
extends RefCounted

var peer_id: int = 0
var opponent_id: int = 0
var primary_faction: int = Factions.Id.CLUBS
var scoring_faction: int = Factions.Id.CLUBS
var phase: GameState.Phase = GameState.Phase.WAITING
var influence_bonus: Dictionary = {}
var player_influence_snapshot: Dictionary = {}
var opponent_influence_snapshot: Dictionary = {}


static func from_game(peer_id: int) -> AiContext:
	var context := AiContext.new()
	context.peer_id = peer_id
	context.opponent_id = _opponent_for(peer_id)
	context.player_influence_snapshot = _snapshot_influence_for(peer_id)
	context.opponent_influence_snapshot = _snapshot_influence_for(context.opponent_id)
	context.influence_bonus = _crib_owner_influence_bonus(peer_id)
	context.primary_faction = highest_influence_faction_for(peer_id, context.influence_bonus)
	context.scoring_faction = _highest_score_faction()
	context.phase = GameState.current_phase
	return context


static func leads_influence_in_any_faction(peer_id: int) -> bool:
	var opponent_id := _opponent_for(peer_id)
	for faction_id in Factions.ALL:
		if influence_for(peer_id, faction_id) > influence_for(opponent_id, faction_id):
			return true
	return false


func effective_influence_for(target_peer_id: int, faction_id: int) -> int:
	var value := 0
	if int(target_peer_id) == int(peer_id):
		value = RemixRules.faction_dict_value(player_influence_snapshot, faction_id)
	elif int(target_peer_id) == int(opponent_id):
		value = RemixRules.faction_dict_value(opponent_influence_snapshot, faction_id)
	else:
		value = influence_for(target_peer_id, faction_id)
	if int(target_peer_id) == int(peer_id):
		value += int(RemixRules.faction_dict_value(influence_bonus, faction_id))
	return value


func influence_diff(faction_id: int) -> int:
	return (
		effective_influence_for(peer_id, faction_id)
		- effective_influence_for(opponent_id, faction_id)
	)


static func highest_influence_faction_for(
	peer_id: int,
	bonus: Dictionary = {}
) -> int:
	var influence: Dictionary = GameState.player_influence.get(
		peer_id,
		RemixRules.empty_influence()
	)
	var best_faction := Factions.Id.CLUBS
	var best_value := -1
	for faction_id in Factions.ALL:
		var value := RemixRules.faction_dict_value(influence, faction_id)
		value += int(RemixRules.faction_dict_value(bonus, faction_id))
		if value > best_value:
			best_value = value
			best_faction = faction_id
	return best_faction


static func _crib_owner_influence_bonus(peer_id: int) -> Dictionary:
	if int(peer_id) != int(GameState.crib_owner_peer_id):
		return {}
	if not _phase_counts_assumed_crib_influence():
		return {}
	if leads_influence_in_any_faction(peer_id):
		return {}
	return _influence_bonus_from_crib_discards(peer_id)


static func _phase_counts_assumed_crib_influence() -> bool:
	return GameState.current_phase == GameState.Phase.SPEND_ACTIONS


static func _influence_bonus_from_crib_discards(peer_id: int) -> Dictionary:
	var bonus := RemixRules.empty_influence()
	for card in GameState.get_crib_discards_for_peer(peer_id):
		var faction_id := GameState.get_card_faction_id(card)
		bonus[faction_id] = RemixRules.faction_dict_value(bonus, faction_id) + 1
	return bonus


static func influence_for(peer_id: int, faction_id: int) -> int:
	var influence: Dictionary = GameState.player_influence.get(
		peer_id,
		RemixRules.empty_influence()
	)
	return int(RemixRules.faction_dict_value(influence, faction_id))


static func _snapshot_influence_for(peer_id: int) -> Dictionary:
	return RemixRules.normalize_faction_dict(
		GameState.player_influence.get(peer_id, RemixRules.empty_influence())
	)


static func _opponent_for(peer_id: int) -> int:
	for candidate in GameState.active_player_order:
		if int(candidate) != int(peer_id):
			return int(candidate)
	return 0


static func _highest_score_faction() -> int:
	var best_faction := Factions.Id.CLUBS
	var best_value := -1
	for faction_id in Factions.ALL:
		var value := RemixRules.faction_dict_value(GameState.faction_scores, faction_id)
		if value > best_value:
			best_value = value
			best_faction = faction_id
	return best_faction
