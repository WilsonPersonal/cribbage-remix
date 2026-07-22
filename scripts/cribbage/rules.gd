class_name RemixRules
extends RefCounted

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const ENDING_SCORE_TOTAL := 7
const INFLUENCE_FROM_CRIB := 1
const INFLUENCE_ACTION_LOCK_GAP := 2
const CRIB_SIZE_TWO_PLAYER := 4
const FACTION_ACTION_SHOP_COST := 3
const MIN_TURN_ACTIONS := 2
const MAX_TURN_ACTIONS := 7


static func cards_per_hand(player_count: int) -> int:
	match player_count:
		2:
			return 6
		3, 4:
			return 5
		_:
			return 6


static func crib_discard_count(player_count: int) -> int:
	match player_count:
		2, 3:
			return 2
		4:
			return 1
		_:
			return 2


static func is_valid_player_count(count: int) -> bool:
	return count >= MIN_PLAYERS and count <= MAX_PLAYERS


static func empty_influence() -> Dictionary:
	return {
		Factions.Id.CLUBS: 0,
		Factions.Id.HEARTS: 0,
		Factions.Id.DIAMONDS: 0,
	}


static func empty_supply() -> Dictionary:
	return empty_influence()


static func empty_faction_actions() -> Dictionary:
	return {
		Factions.Id.CLUBS: 0,
		Factions.Id.HEARTS: 0,
		Factions.Id.DIAMONDS: 0,
		Factions.Id.SPADES: 0,
	}


static func normalize_action_tokens(values: Dictionary) -> Dictionary:
	var out := {}
	for faction in Factions.SHOP_FACTIONS:
		out[faction] = faction_dict_value(values, faction)
	return out


static func faction_dict_value(values: Dictionary, faction_id: int) -> int:
	if values.has(faction_id):
		return int(values[faction_id])
	var string_key := str(faction_id)
	if values.has(string_key):
		return int(values[string_key])
	return 0


static func clamp_turn_actions(raw_actions: int) -> Dictionary:
	var clamped := raw_actions
	var coin_delta := 0
	if raw_actions > MAX_TURN_ACTIONS:
		clamped = MAX_TURN_ACTIONS
		coin_delta = raw_actions - MAX_TURN_ACTIONS
	elif raw_actions < MIN_TURN_ACTIONS:
		clamped = MIN_TURN_ACTIONS
		coin_delta = -(MIN_TURN_ACTIONS - raw_actions)
	return {
		"raw": raw_actions,
		"clamped": clamped,
		"coin_delta": coin_delta,
	}


static func format_turn_action_limit(raw_actions: int) -> String:
	var result := clamp_turn_actions(raw_actions)
	var clamped := int(result.get("clamped", raw_actions))
	var coin_delta := int(result.get("coin_delta", 0))
	if coin_delta > 0:
		return "%d scored → %d actions (+%d coins)" % [raw_actions, clamped, coin_delta]
	if coin_delta < 0:
		return "%d scored → %d actions (%d coins)" % [raw_actions, clamped, coin_delta]
	return "%d action(s)" % clamped


static func normalize_faction_dict(values: Dictionary) -> Dictionary:
	var out := {}
	for faction in Factions.ALL:
		out[faction] = faction_dict_value(values, faction)
	return out
