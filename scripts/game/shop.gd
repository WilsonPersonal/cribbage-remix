class_name Shop
extends RefCounted

## Slot costs left to right: 9, 7, 5, 3 coins.
const SLOT_COSTS := [9, 7, 5, 3]
const SLOT_COUNT := 4

const EFFECT_QUEEN := "queen"
const EFFECT_JACK := "jack"
const EFFECT_KING := "king"


static func slot_cost(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return 0
	return SLOT_COSTS[slot_index]


static func can_afford_slot(coins: int, slot_index: int) -> bool:
	return coins >= slot_cost(slot_index)


static func card_effect(card: Dictionary) -> String:
	match str(card.get("rank", "")):
		"J":
			return EFFECT_JACK
		"K":
			return EFFECT_KING
		"Q", _:
			return EFFECT_QUEEN
