class_name CribbageScoring
extends RefCounted

## Show-hand scoring: each pair, 15, and run of 3+ grants one action.
## Pegging coin rewards follow standard cribbage (pair 2, triple 6, quad 12, 15/31 = 2, go = 1, run = length).


static func count_actions_from_cards(cards: Array, cut_card: Dictionary = {}) -> int:
	var breakdown := explain_actions_from_cards(cards, cut_card)
	return int(breakdown.get("total", 0))


static func explain_actions_from_cards(cards: Array, cut_card: Dictionary = {}) -> Dictionary:
	var all_cards := _all_scoring_cards(cards, cut_card)
	var pairs := _find_pairs(all_cards)
	var fifteens := _find_fifteens(all_cards)
	var runs := _find_runs(all_cards)
	return {
		"pairs": pairs,
		"fifteens": fifteens,
		"runs": runs,
		"total": pairs.size() + fifteens.size() + runs.size(),
		"includes_cut_card": not cut_card.is_empty(),
	}


static func format_action_breakdown(breakdown: Dictionary) -> String:
	var lines: PackedStringArray = ["Show-hand scoring (1 action each):"]
	if bool(breakdown.get("includes_cut_card", false)):
		lines.append("Includes cut card.")

	var pairs: Array = breakdown.get("pairs", [])
	lines.append("")
	lines.append("Pairs (%d):" % pairs.size())
	if pairs.is_empty():
		lines.append("  (none)")
	else:
		for entry in pairs:
			lines.append("  • %s" % entry.get("label", ""))

	var fifteens: Array = breakdown.get("fifteens", [])
	lines.append("")
	lines.append("15s (%d):" % fifteens.size())
	if fifteens.is_empty():
		lines.append("  (none)")
	else:
		for entry in fifteens:
			lines.append("  • %s" % entry.get("label", ""))

	var runs: Array = breakdown.get("runs", [])
	lines.append("")
	lines.append("Runs (%d):" % runs.size())
	if runs.is_empty():
		lines.append("  (none)")
	else:
		for entry in runs:
			lines.append("  • %s" % entry.get("label", ""))

	lines.append("")
	lines.append("Total actions: %d" % int(breakdown.get("total", 0)))
	return "\n".join(lines)


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


static func _all_scoring_cards(cards: Array, cut_card: Dictionary) -> Array:
	var all_cards := cards.duplicate(true)
	if not cut_card.is_empty():
		all_cards.append(cut_card)
	return all_cards


static func _find_pairs(cards: Array) -> Array:
	var pairs: Array = []
	for i in range(cards.size()):
		for j in range(i + 1, cards.size()):
			if cards[i].get("rank", "") == cards[j].get("rank", ""):
				pairs.append({
					"label": "%s & %s" % [_card_short(cards[i]), _card_short(cards[j])],
					"cards": [cards[i], cards[j]],
				})
	return pairs


static func _find_fifteens(cards: Array) -> Array:
	var fifteens: Array = []
	var count := cards.size()

	for mask in range(1, 1 << count):
		var subset: Array = []
		var sum := 0
		for i in range(count):
			if mask & (1 << i):
				subset.append(cards[i])
				sum += int(cards[i].get("value", 0))
		if sum == 15 and subset.size() >= 2:
			var parts: PackedStringArray = []
			for card in subset:
				parts.append(_card_short(card))
			fifteens.append({
				"label": "%s = 15" % " + ".join(parts),
				"cards": subset,
			})

	return fifteens


static func _find_runs(cards: Array) -> Array:
	var by_value: Dictionary = {}
	for card in cards:
		var value := int(card.get("value", 0))
		if not by_value.has(value):
			by_value[value] = []
		by_value[value].append(card)

	var values: Array = by_value.keys()
	values.sort()

	var runs: Array = []
	var start := 0
	while start < values.size():
		var end := start
		while end + 1 < values.size() and int(values[end + 1]) == int(values[end]) + 1:
			end += 1

		if end - start + 1 >= 3:
			var rank_values: Array = values.slice(start, end + 1)
			_collect_run_combinations(runs, by_value, rank_values)

		start = end + 1

	return runs


static func _collect_run_combinations(
	runs: Array,
	by_value: Dictionary,
	rank_values: Array
) -> void:
	var current: Array = []
	_build_run_combinations(runs, by_value, rank_values, 0, current)


static func _build_run_combinations(
	runs: Array,
	by_value: Dictionary,
	rank_values: Array,
	index: int,
	current: Array
) -> void:
	if index >= rank_values.size():
		if current.size() >= 3:
			var parts: PackedStringArray = []
			for card in current:
				parts.append(str(card.get("rank", "?")))
			runs.append({
				"label": "Run %s" % "-".join(parts),
				"cards": current.duplicate(true),
			})
		return

	var value := int(rank_values[index])
	for card in by_value[value]:
		current.append(card)
		_build_run_combinations(runs, by_value, rank_values, index + 1, current)
		current.pop_back()


static func _card_short(card: Dictionary) -> String:
	return CribbageDeck.card_label(card)
