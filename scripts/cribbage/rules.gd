class_name RemixRules
extends RefCounted

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const ENDING_SCORE_TOTAL := 7
const INFLUENCE_FROM_CRIB := 1
const CRIB_SIZE_TWO_PLAYER := 4
const FACTION_ACTION_SHOP_COST := 3


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
	return empty_influence()
