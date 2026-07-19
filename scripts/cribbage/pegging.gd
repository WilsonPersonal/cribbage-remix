class_name PeggingRules
extends RefCounted

const MAX_TOTAL := 31


static func can_play(card: Dictionary, running_total: int) -> bool:
	return running_total + int(card.get("value", 0)) <= MAX_TOTAL


static func has_any_play(hand: Array, running_total: int) -> bool:
	for card in hand:
		if can_play(card, running_total):
			return true
	return false


static func score_events(sequence: Array, running_total: int) -> Array:
	var events: Array = []

	if running_total == 15:
		events.append("fifteen")
	if running_total == 31:
		events.append("thirty_one")

	if sequence.size() >= 2:
		var tail_rank: String = sequence[-1].get("rank", "")
		var matching := 1
		for i in range(sequence.size() - 2, -1, -1):
			if sequence[i].get("rank", "") == tail_rank:
				matching += 1
			else:
				break

		match matching:
			2:
				events.append("pair")
			3:
				events.append("triple")
			4:
				events.append("quadruple")

	var run_length := _tail_run_length(sequence)
	if run_length >= 3:
		events.append("run_%d" % run_length)

	return events


static func _tail_run_length(sequence: Array) -> int:
	if sequence.size() < 3:
		return 0

	for length in range(mini(sequence.size(), 5), 2, -1):
		var start := sequence.size() - length
		var tail: Array = sequence.slice(start, sequence.size())
		if _is_consecutive_run(tail):
			return length

	return 0


static func _is_consecutive_run(cards: Array) -> bool:
	if cards.size() < 3:
		return false

	var values: Array = []
	for card in cards:
		values.append(int(card.get("value", 0)))
	values.sort()

	for i in range(1, values.size()):
		if values[i] == values[i - 1]:
			return false
		if values[i] != values[i - 1] + 1:
			return false

	return true
