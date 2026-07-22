class_name Shop
extends RefCounted

## Slot costs left to right: 9, 7, 5, 3 coins.
const SLOT_COSTS := [9, 7, 5, 3]
const SLOT_COUNT := 4

const EFFECT_QUEEN := "queen"
const EFFECT_JACK := "jack"
const EFFECT_KING := "king"
const QUEEN_ACTION_GRANT := 2


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

	slots[rightmost]["card"] = {}

	for target_index in range(rightmost, 0, -1):
		var target_slot: Dictionary = slots[target_index]
		if not _slot_card(target_slot).is_empty():
			continue
		for source_index in range(target_index - 1, -1, -1):
			var source_slot: Dictionary = slots[source_index]
			var card: Dictionary = _slot_card(source_slot)
			if card.is_empty():
				continue
			target_slot["card"] = card.duplicate(true)
			source_slot["card"] = {}
			break


static func _slot_card(slot: Dictionary) -> Dictionary:
	var card = slot.get("card", {})
	if typeof(card) != TYPE_DICTIONARY:
		return {}
	return card
