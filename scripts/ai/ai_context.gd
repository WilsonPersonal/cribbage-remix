class_name AiContext
extends RefCounted

var peer_id: int = 0
var opponent_id: int = 0
var primary_faction: int = Factions.Id.CLUBS
var scoring_faction: int = Factions.Id.CLUBS
var phase: GameState.Phase = GameState.Phase.WAITING


static func from_game(peer_id: int) -> AiContext:
	var context := AiContext.new()
	context.peer_id = peer_id
	context.opponent_id = _opponent_for(peer_id)
	context.primary_faction = highest_influence_faction_for(peer_id)
	context.scoring_faction = _highest_score_faction()
	context.phase = GameState.current_phase
	return context


static func highest_influence_faction_for(peer_id: int) -> int:
	var influence: Dictionary = GameState.player_influence.get(
		peer_id,
		RemixRules.empty_influence()
	)
	var best_faction := Factions.Id.CLUBS
	var best_value := -1
	for faction_id in Factions.ALL:
		var value := RemixRules.faction_dict_value(influence, faction_id)
		if value > best_value:
			best_value = value
			best_faction = faction_id
	return best_faction


static func influence_for(peer_id: int, faction_id: int) -> int:
	var influence: Dictionary = GameState.player_influence.get(
		peer_id,
		RemixRules.empty_influence()
	)
	return int(RemixRules.faction_dict_value(influence, faction_id))


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
