class_name CribbageScoring
extends RefCounted

## Show-hand scoring: each pair, 15, and run of 3+ grants one action.
## Pegging uses coin rewards instead (see pegging_event_coins).


static func count_actions_from_cards(cards: Array, starter: Dictionary = {}) -> int:
	var all_cards := cards.duplicate()
	if not starter.is_empty():
		all_cards.append(starter)

	return (
		_count_pair_actions(all_cards)
		+ _count_fifteen_actions(all_cards)
		+ _count_run_actions(all_cards)
	)


static func pegging_event_coins(event_type: String) -> int:
	match event_type:
		"pair":
			return 1
		"triple":
			return 2
		"quadruple":
			return 3
		"fifteen":
			return 1
		"thirty_one":
			return 2
		"go":
			return 1
		"run":
			return 1
		_:
			return 0


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
