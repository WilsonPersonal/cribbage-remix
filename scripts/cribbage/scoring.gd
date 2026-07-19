class_name CribbageScoring
extends RefCounted

## Show-hand scoring: each pair, 15, and run of 3+ grants one action.
## Pegging coin rewards follow standard cribbage (pair 2, triple 6, quad 12, 15/31 = 2, go = 1, run = length).


static func count_actions_from_cards(cards: Array, cut_card: Dictionary = {}) -> int:
	var all_cards := cards.duplicate()
	if not cut_card.is_empty():
		all_cards.append(cut_card)

	return (
		_count_pair_actions(all_cards)
		+ _count_fifteen_actions(all_cards)
		+ _count_run_actions(all_cards)
	)


static func pegging_event_coins(event_type: String) -> int:
	if event_type.begins_with("run_"):
		return int(event_type.trim_prefix("run_"))

	match event_type:
		"pair":
			return 2
		"triple":
			return 6
		"quadruple":
			return 12
		"fifteen":
			return 2
		"thirty_one":
			return 2
		"go":
			return 1
		"last_card":
			return 1
		_:
			return 0


static func pegging_event_label(event_type: String) -> String:
	if event_type.begins_with("run_"):
		return "Run"

	match event_type:
		"pair":
			return "Pair"
		"triple":
			return "Triple"
		"quadruple":
			return "Quad"
		"fifteen":
			return "15"
		"thirty_one":
			return "31"
		"go":
			return "Go"
		"last_card":
			return "Last card"
		_:
			return event_type.capitalize()


static func _count_pair_actions(cards: Array) -> int:
	var actions := 0
	for i in range(cards.size()):
		for j in range(i + 1, cards.size()):
			if cards[i].get("rank", "") == cards[j].get("rank", ""):
				actions += 1
	return actions


static func _count_fifteen_actions(cards: Array) -> int:
	var actions := 0
	var count := cards.size()

	for mask in range(1, 1 << count):
		var sum := 0
		var size := 0
		for i in range(count):
			if mask & (1 << i):
				sum += int(cards[i].get("value", 0))
				size += 1
		if sum == 15 and size >= 2:
			actions += 1

	return actions


static func _count_run_actions(cards: Array) -> int:
	var actions := 0
	var count := cards.size()

	for mask in range(1, 1 << count):
		var subset: Array = []
		for i in range(count):
			if mask & (1 << i):
				subset.append(cards[i])
		if subset.size() < 3:
			continue
		if _is_consecutive_run(subset):
			actions += 1

	return actions


static func _is_consecutive_run(subset: Array) -> bool:
	var orders: Array = []
	for card in subset:
		orders.append(int(card.get("value", 0)))
	orders.sort()

	for i in range(1, orders.size()):
		if orders[i] == orders[i - 1]:
			return false
		if orders[i] != orders[i - 1] + 1:
			return false
	return true
