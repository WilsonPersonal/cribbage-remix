class_name CribbageDeck
extends RefCounted

const SUITS := ["clubs", "hearts", "diamonds"]
const RANKS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]


static func create_shuffled_deck(_rng: RandomNumberGenerator = null) -> Array:
	var deck: Array = []

	for suit in SUITS:
		for rank in RANKS:
			deck.append({
				"suit": suit,
				"rank": rank,
				"value": card_value(rank),
				"faction": Factions.from_suit(suit),
			})

	deck.shuffle()
	return deck


static func card_value(rank: String) -> int:
	return int(rank)


static func card_label(card: Dictionary) -> String:
	return "%s of %s" % [card.get("rank", "?"), card.get("suit", "?")]
