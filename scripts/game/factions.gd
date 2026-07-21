class_name Factions
extends RefCounted

enum Id {
	CLUBS,
	HEARTS,
	DIAMONDS,
	SPADES,
}

const NAMES := {
	Id.CLUBS: "Clubs",
	Id.HEARTS: "Hearts",
	Id.DIAMONDS: "Diamonds",
	Id.SPADES: "Wild",
}

const COLORS := {
	Id.CLUBS: Color("#1a1a1a"),
	Id.HEARTS: Color("#c0392b"),
	Id.DIAMONDS: Color("#2980b9"),
	Id.SPADES: Color("#7b5ea7"),
}

const SUITS := {
	"clubs": Id.CLUBS,
	"hearts": Id.HEARTS,
	"diamonds": Id.DIAMONDS,
	"spades": Id.SPADES,
}

## Board cubes and scoring factions (no spades on the map).
const ALL := [Id.CLUBS, Id.HEARTS, Id.DIAMONDS]

## Faction action tokens purchasable from the face-card shop (spades = wild).
const SHOP_FACTIONS := [Id.CLUBS, Id.HEARTS, Id.DIAMONDS, Id.SPADES]


static func name_for(faction_id: int) -> String:
	return NAMES.get(faction_id, "Unknown")


static func cube_needs_stripe(color: Color) -> bool:
	return color.get_luminance() < 0.22


static func draw_cube(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	color: Color,
	outline: Color = Color(0.0, 0.0, 0.0, 0.35)
) -> void:
	canvas.draw_circle(center, radius, color)
	if cube_needs_stripe(color):
		var stripe_height := maxf(1.2, radius * 0.42)
		var stripe_width := radius * 1.75
		canvas.draw_rect(
			Rect2(
				center.x - stripe_width * 0.5,
				center.y - stripe_height * 0.5,
				stripe_width,
				stripe_height
			),
			Color(1.0, 1.0, 1.0, 0.92)
		)
	if outline.a > 0.0:
		canvas.draw_arc(center, radius, 0.0, TAU, 16, outline, 1.0)


static func from_suit(suit: String) -> int:
	return SUITS.get(suit, Id.CLUBS)


static func suit_for(faction_id: int) -> String:
	for suit in SUITS.keys():
		if SUITS[suit] == faction_id:
			return suit
	return "clubs"
