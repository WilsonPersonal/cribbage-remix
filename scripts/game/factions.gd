class_name Factions
extends RefCounted

enum Id {
	CLUBS,
	HEARTS,
	DIAMONDS,
}

const NAMES := {
	Id.CLUBS: "Clubs",
	Id.HEARTS: "Hearts",
	Id.DIAMONDS: "Diamonds",
}

const COLORS := {
	Id.CLUBS: Color("#1a1a1a"),
	Id.HEARTS: Color("#c0392b"),
	Id.DIAMONDS: Color("#2980b9"),
}

const SUITS := {
	"clubs": Id.CLUBS,
	"hearts": Id.HEARTS,
	"diamonds": Id.DIAMONDS,
}

const ALL := [Id.CLUBS, Id.HEARTS, Id.DIAMONDS]


static func name_for(faction_id: int) -> String:
	return NAMES.get(faction_id, "Unknown")


static func from_suit(suit: String) -> int:
	return SUITS.get(suit, Id.CLUBS)


static func suit_for(faction_id: int) -> String:
	for suit in SUITS.keys():
		if SUITS[suit] == faction_id:
			return suit
	return "clubs"
