class_name PeggingPhase
extends RefCounted

## Pegging flow from the design pseudocode:
## - Play cards until 8 have been pegged (4 per player).
## - Pass / out-of-cards toggles `other_player_passed` and may reset the count.
## - Go is scored for the player who receives the turn after a first pass in a count.

const MAX_CARDS_PLAYED := 8


static func opponent_peer(peer_id: int, player_order: Array) -> int:
	for candidate in player_order:
		if int(candidate) != int(peer_id):
			return int(candidate)
	return -1
