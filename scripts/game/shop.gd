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


static func rightmost_slot_index() -> int:
	return SLOT_COUNT - 1


static func compact_after_round(slots: Array) -> void:
	if slots.is_empty():
		return

	var rightmost := rightmost_slot_index()
	if rightmost < 0 or rightmost >= slots.size():
		return

	var right_slot: Dictionary = slots[rightmost]
	if typeof(right_slot.get("card", {})) == TYPE_DICTIONARY:
		right_slot["card"] = {}

	var remaining_cards: Array = []
	for slot_index in range(rightmost):
		var slot: Dictionary = slots[slot_index]
		var card: Dictionary = slot.get("card", {}) if typeof(slot.get("card", {})) == TYPE_DICTIONARY else {}
		if not card.is_empty():
			remaining_cards.append(card.duplicate(true))
		slot["card"] = {}

	if remaining_cards.is_empty():
		return

	var start_index := rightmost - remaining_cards.size() + 1
	for card_index in range(remaining_cards.size()):
		var target_index := start_index + card_index
		if target_index < 0 or target_index >= slots.size():
			continue
		slots[target_index]["card"] = remaining_cards[card_index]
