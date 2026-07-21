class_name CribbageDeck
extends RefCounted

const SUITS := ["clubs", "hearts", "diamonds"]
const FACE_SUITS := ["clubs", "hearts", "diamonds", "spades"]
const RANKS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
const FACE_RANKS := ["J", "Q", "K"]


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
	var rank: String = str(card.get("rank", "?"))
	var suit: String = str(card.get("suit", "?"))
	if suit == "spades":
		return "%s of spades (wild)" % rank
	return "%s of %s" % [rank, suit]


static func create_shuffled_face_deck(_rng: RandomNumberGenerator = null) -> Array:
	var deck: Array = []
	for suit in FACE_SUITS:
		for rank in FACE_RANKS:
			deck.append({
				"suit": suit,
				"rank": rank,
				"value": 10,
				"faction": Factions.from_suit(suit),
				"is_face": true,
			})
	deck.shuffle()
	return deck
