class_name HexBoard
extends RefCounted

enum Terrain {
	MOUNTAIN,
	FOREST,
	PASTURE,
}

const HEX_COUNT := 9

## Pasture (light green), forest (dark green), and mountain (grey) setup counts.
const PASTURE_SETUP_CUBES := 3
const FOREST_SETUP_CUBES := 2
const MOUNTAIN_SETUP_CUBES := 5
const MAX_CUBES_PER_FACTION_PER_HEX := 5

## Map layout (hex index -> terrain / labels):
##       [0 M 3,8]
##   [1 F5]   [8 F5]
##       [4 P4] [2 P6]
##   [3 F5]   [5 P7]
## [6 M29]     [7 M110]
const MOUNTAIN_HEXES := [0, 6, 7]
const FOREST_HEXES := [1, 3, 8]
const PASTURE_HEXES := [2, 4, 5]

const CART_GOALS := {
	0: 3,
	6: 8,
	7: 1,
}

const BRIDGE_PAIRS := [
	[0, 1],
	[7, 8],
	[6, 3],
]

## Grid neighbors plus bridge links (0-1, 7-8, 6-3).
const ADJACENCY := {
	0: [1, 2, 8],
	1: [0, 4, 6],
	2: [0, 4, 5, 8],
	3: [5, 6, 7],
	4: [1, 2, 5, 6],
	5: [2, 3, 4, 7],
	6: [1, 3, 4],
	7: [3, 5, 8],
	8: [0, 2, 7],
}

## Axial coordinates (q, r) on a flat-top hex grid.
## Pixel spacing uses center-to-vertex radius R:
##   x = R * 1.5 * q
##   y = R * sqrt(3) * (r + q * 0.5)
const HEX_COORDS := {
	0: Vector2i(1, -2),
	1: Vector2i(-1, 0),
	2: Vector2i(1, -1),
	3: Vector2i(1, 1),
	4: Vector2i(0, 0),
	5: Vector2i(1, 0),
	6: Vector2i(-1, 1),
	7: Vector2i(2, 0),
	8: Vector2i(2, -2),
}

const TERRAIN := {
	0: Terrain.MOUNTAIN,
	1: Terrain.FOREST,
	2: Terrain.PASTURE,
	3: Terrain.FOREST,
	4: Terrain.PASTURE,
	5: Terrain.PASTURE,
	6: Terrain.MOUNTAIN,
	7: Terrain.MOUNTAIN,
	8: Terrain.FOREST,
}

const HEX_LABELS := {
	0: [3, 8],
	1: [5],
	2: [6],
	3: [5],
	4: [4],
	5: [7],
	6: [2, 9],
	7: [1, 10],
	8: [5],
}

var hexes: Array = []
var _distance_cache: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	hexes.clear()
	_distance_cache.clear()

	for _i in range(HEX_COUNT):
		hexes.append(_empty_hex())


## Draw setup cards from the deck, place matching suit cubes, and return the drawn cards.
func setup_from_deck(deck: Array) -> Array:
	reset()
	var drawn: Array = []

	for hex_index in range(HEX_COUNT):
		var draw_count := setup_cube_count_for(hex_index)

		for _draw in range(draw_count):
			if deck.is_empty():
				push_warning("Setup deck ran out while placing cubes on hex %d." % hex_index)
				break

			var card: Dictionary = deck.pop_back()
			drawn.append(card)
			var faction: int = int(card.get("faction", Factions.from_suit(str(card.get("suit", "clubs")))))
			hexes[hex_index]["cubes"][faction] = int(hexes[hex_index]["cubes"].get(faction, 0)) + 1

	return drawn


static func setup_cube_count_for(hex_index: int) -> int:
	return setup_cube_count_for_terrain(terrain_for(hex_index))


static func setup_cube_count_for_terrain(terrain: int) -> int:
	match terrain:
		Terrain.MOUNTAIN:
			return MOUNTAIN_SETUP_CUBES
		Terrain.FOREST:
			return FOREST_SETUP_CUBES
		Terrain.PASTURE:
			return PASTURE_SETUP_CUBES
		_:
			return 0


static func terrain_name(terrain: int) -> String:
	match terrain:
		Terrain.MOUNTAIN:
			return "mountain"
		Terrain.FOREST:
			return "forest"
		Terrain.PASTURE:
			return "pasture"
		_:
			return "unknown"


static func terrain_for(hex_index: int) -> int:
	return TERRAIN.get(hex_index, Terrain.PASTURE)


static func labels_for(hex_index: int) -> Array:
	return HEX_LABELS.get(hex_index, [])


static func axial_coord(hex_index: int) -> Vector2i:
	return HEX_COORDS.get(hex_index, Vector2i.ZERO)


static func pixel_center(hex_index: int, radius: float, origin: Vector2) -> Vector2:
	var coord := axial_coord(hex_index)
	var x := radius * 1.5 * float(coord.x)
	var y := radius * sqrt(3.0) * (float(coord.y) + float(coord.x) * 0.5)
	return origin + Vector2(x, y)


static func hex_corner_offset(vertex_index: int, radius: float) -> Vector2:
	var angle := deg_to_rad(60.0 * vertex_index)
	return Vector2(cos(angle), sin(angle)) * radius


static func board_pixel_bounds(radius: float) -> Rect2:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF

	for hex_index in range(HEX_COUNT):
		var center := pixel_center(hex_index, radius, Vector2.ZERO)
		for i in range(6):
			var point := center + hex_corner_offset(i, radius)
			min_x = min(min_x, point.x)
			min_y = min(min_y, point.y)
			max_x = max(max_x, point.x)
			max_y = max(max_y, point.y)

	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


static func hex_number(hex_index: int) -> int:
	var labels: Array = labels_for(hex_index)
	if labels.is_empty():
		return hex_index + 1
	return int(labels[0])


static func is_valid_reject_placement(card: Dictionary, hex_index: int) -> bool:
	if hex_index < 0 or hex_index >= HEX_COUNT:
		return false

	var rank := str(card.get("rank", ""))
	if rank == "10":
		return true

	var rank_number := int(rank)
	return rank_number in labels_for(hex_index)


func duplicate_state() -> Array:
	var copy: Array = []
	for hex in hexes:
		copy.append(_duplicate_hex(hex))
	return copy


func load_state(state: Array) -> void:
	hexes.clear()
	_distance_cache.clear()
	for hex in state:
		if hex.has("cubes"):
			hexes.append(_duplicate_hex(hex))
		else:
			hexes.append(_empty_hex())


func are_adjacent(a: int, b: int) -> bool:
	return ADJACENCY.get(a, []).has(b)


func controls_hex(faction: int, hex_index: int) -> bool:
	if hex_index < 0 or hex_index >= HEX_COUNT:
		return false

	var cubes: Dictionary = hexes[hex_index]["cubes"]
	var faction_cubes := RemixRules.faction_dict_value(cubes, faction)
	if faction_cubes <= 0:
		return false

	for other in Factions.ALL:
		if other == faction:
			continue
		if int(RemixRules.faction_dict_value(cubes, other)) >= faction_cubes:
			return false

	return true


func cart_can_advance(from_hex: int, to_hex: int, origin_hex: int) -> bool:
	if not are_adjacent(from_hex, to_hex):
		return false

	var goal_hex := int(CART_GOALS.get(origin_hex, -1))
	if goal_hex < 0:
		return false

	var from_distance := _distance_to_hex(from_hex, goal_hex)
	var to_distance := _distance_to_hex(to_hex, goal_hex)
	return to_distance < from_distance


func get_faction_power() -> Dictionary:
	var power := {
		Factions.Id.CLUBS: 0,
		Factions.Id.HEARTS: 0,
		Factions.Id.DIAMONDS: 0,
	}

	for hex in hexes:
		for faction in Factions.ALL:
			power[faction] += RemixRules.faction_dict_value(hex["cubes"], faction)

	return power


func get_dominant_faction() -> int:
	var power := get_faction_power()
	var best_faction := Factions.Id.CLUBS
	var best_value := -1

	for faction in Factions.ALL:
		if power[faction] > best_value:
			best_value = power[faction]
			best_faction = faction

	return best_faction


func get_controlling_faction(hex_index: int) -> int:
	for faction in Factions.ALL:
		if controls_hex(faction, hex_index):
			return faction
	return -1


func cube_count_for(faction: int, hex_index: int) -> int:
	if hex_index < 0 or hex_index >= HEX_COUNT:
		return 0
	return RemixRules.faction_dict_value(hexes[hex_index]["cubes"], faction)


func available_cube_space(faction: int, hex_index: int) -> int:
	return maxi(0, MAX_CUBES_PER_FACTION_PER_HEX - cube_count_for(faction, hex_index))


func can_add_cubes(faction: int, hex_index: int, amount: int = 1) -> bool:
	return available_cube_space(faction, hex_index) >= amount


func _set_cube_count(faction: int, hex_index: int, count: int) -> void:
	var cubes: Dictionary = hexes[hex_index]["cubes"]
	cubes.erase(str(faction))
	cubes[faction] = maxi(0, count)
	hexes[hex_index]["cubes"] = RemixRules.normalize_faction_dict(cubes)


func _add_cubes(faction: int, hex_index: int, amount: int) -> void:
	if amount <= 0:
		return
	var allowed := mini(amount, available_cube_space(faction, hex_index))
	if allowed <= 0:
		return
	_set_cube_count(faction, hex_index, cube_count_for(faction, hex_index) + allowed)


func _remove_cubes(faction: int, hex_index: int, amount: int) -> void:
	if amount <= 0:
		return
	_set_cube_count(faction, hex_index, cube_count_for(faction, hex_index) - amount)


func advance_cart(faction: int, from_hex: int, to_hex: int) -> bool:
	if not are_adjacent(from_hex, to_hex):
		return false

	var cart_origins: Array = hexes[from_hex]["carts"].get(faction, [])
	for i in range(cart_origins.size()):
		var origin_hex := int(cart_origins[i])
		if not cart_can_advance(from_hex, to_hex, origin_hex):
			continue
		cart_origins.remove_at(i)
		hexes[to_hex]["carts"][faction] = hexes[to_hex]["carts"].get(faction, [])
		hexes[to_hex]["carts"][faction].append(origin_hex)
		return true

	return false


func push(
	faction: int,
	from_hex: int,
	to_hex: int,
	cube_count: int = 1,
	move_cart_also: bool = false
) -> bool:
	if not controls_hex(faction, from_hex):
		return false
	if not are_adjacent(from_hex, to_hex):
		return false

	var moved := false

	if cube_count > 0:
		var available := cube_count_for(faction, from_hex)
		var space := available_cube_space(faction, to_hex)
		var move_count := mini(cube_count, mini(available, space))
		if move_count > 0:
			_remove_cubes(faction, from_hex, move_count)
			_add_cubes(faction, to_hex, move_count)
			moved = true

	if move_cart_also:
		moved = advance_cart(faction, from_hex, to_hex) or moved

	return moved


func pull(
	faction: int,
	to_hex: int,
	from_hex: int,
	cube_count: int = 1,
	move_cart_also: bool = false
) -> bool:
	if not controls_hex(faction, to_hex):
		return false
	if not are_adjacent(from_hex, to_hex):
		return false

	var moved := false

	if cube_count > 0:
		var available := cube_count_for(faction, from_hex)
		var space := available_cube_space(faction, to_hex)
		var move_count := mini(cube_count, mini(available, space))
		if move_count > 0:
			_remove_cubes(faction, from_hex, move_count)
			_add_cubes(faction, to_hex, move_count)
			moved = true

	if move_cart_also:
		moved = advance_cart(faction, from_hex, to_hex) or moved

	return moved


func move_cart(faction: int, from_hex: int, to_hex: int) -> bool:
	if not controls_hex(faction, from_hex):
		return false
	return advance_cart(faction, from_hex, to_hex)


func create_cart(faction: int, hex_index: int) -> bool:
	if hex_index not in MOUNTAIN_HEXES:
		return false
	if not controls_hex(faction, hex_index):
		return false
	if cube_count_for(faction, hex_index) <= 0:
		return false

	_remove_cubes(faction, hex_index, 1)
	hexes[hex_index]["carts"][faction].append(hex_index)
	return true


func score_carts_on_goal() -> Dictionary:
	var scored := {
		Factions.Id.CLUBS: 0,
		Factions.Id.HEARTS: 0,
		Factions.Id.DIAMONDS: 0,
	}

	for hex_index in range(HEX_COUNT):
		for faction in Factions.ALL:
			var origins: Array = hexes[hex_index]["carts"].get(faction, [])
			var remaining: Array = []
			for origin_hex in origins:
				if int(CART_GOALS.get(int(origin_hex), -1)) == hex_index:
					scored[faction] += 1
					_add_cubes(faction, hex_index, 1)
				else:
					remaining.append(origin_hex)
			hexes[hex_index]["carts"][faction] = remaining

	return scored


func remove_cube(faction: int, hex_index: int) -> bool:
	if hex_index < 0 or hex_index >= HEX_COUNT:
		return false
	if cube_count_for(faction, hex_index) <= 0:
		return false

	_remove_cubes(faction, hex_index, 1)
	return true


func add_cube(faction: int, hex_index: int) -> bool:
	if hex_index < 0 or hex_index >= HEX_COUNT:
		return false
	if not can_add_cubes(faction, hex_index, 1):
		return false

	_add_cubes(faction, hex_index, 1)
	return true


func _distance_to_hex(from_hex: int, to_hex: int) -> int:
	var cache_key := "%d_%d" % [from_hex, to_hex]
	if _distance_cache.has(cache_key):
		return int(_distance_cache[cache_key])

	var distances: Dictionary = {from_hex: 0}
	var queue: Array = [from_hex]
	var head := 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		if current == to_hex:
			break
		for neighbor in ADJACENCY.get(current, []):
			if distances.has(neighbor):
				continue
			distances[neighbor] = int(distances[current]) + 1
			queue.append(neighbor)

	_distance_cache[cache_key] = distances.get(to_hex, 999)
	return int(_distance_cache[cache_key])


func _duplicate_hex(hex: Dictionary) -> Dictionary:
	return {
		"cubes": RemixRules.normalize_faction_dict(hex.get("cubes", {})),
		"carts": _normalize_carts_dict(hex.get("carts", {})),
	}


static func _normalize_carts_dict(carts: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for faction in Factions.ALL:
		var raw_origins: Variant = carts.get(faction, carts.get(str(faction), []))
		var origins: Array = []
		if typeof(raw_origins) == TYPE_ARRAY:
			for origin_hex in raw_origins:
				origins.append(int(origin_hex))
		copy[faction] = origins
	return copy


func _empty_hex() -> Dictionary:
	return {
		"cubes": {
			Factions.Id.CLUBS: 0,
			Factions.Id.HEARTS: 0,
			Factions.Id.DIAMONDS: 0,
		},
		"carts": {
			Factions.Id.CLUBS: [],
			Factions.Id.HEARTS: [],
			Factions.Id.DIAMONDS: [],
		},
	}
