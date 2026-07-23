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
const FOREST_SETUP_CUBES := 1
const MOUNTAIN_SETUP_CUBES := 5
const FACTION_STARTING_CUBES := 9
const MAX_CUBES_PER_FACTION_PER_HEX := 5

## Map layout (hex index -> terrain / labels):
##       [0 M 2]
##   [1 F9]   [8 F3]
##       [4 P7] [2 P1]
##   [3 F6]   [5 P4]
## [6 M8]     [7 M5]
const MOUNTAIN_HEXES := [0, 6, 7]
const FOREST_HEXES := [1, 3, 8]
const PASTURE_HEXES := [2, 4, 5]

const CART_GOALS := {
	0: 3,
	6: 8,
	7: 1,
}

## Fixed routes from each mountain spawn to its goal forest. Carts must follow these hexes in order.
## Hex 7 (label 5): 7 -> 5 (label 4) -> 4 (label 7) -> forest 1 (label 9)
## Hex 0 (label 2): 0 -> 2 (label 1) -> 5 (label 4) -> forest 3 (label 6)
## Hex 6 (label 8): 6 -> 4 (label 7) -> 2 (label 1) -> forest 8 (label 3)
const CART_PATHS := {
	0: [0, 2, 5, 3],
	6: [6, 4, 2, 8],
	7: [7, 5, 4, 1],
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
	0: [2],
	1: [9],
	2: [1],
	3: [6],
	4: [7],
	5: [4],
	6: [8],
	7: [5],
	8: [3],
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
## Each faction starts with FACTION_STARTING_CUBES cubes across all hexes.
## Remaining deck cards are left in the passed deck array.
func setup_from_deck(deck: Array) -> Array:
	reset()
	var drawn: Array = []

	var placement_slots: Array = []
	for hex_index in range(HEX_COUNT):
		var draw_count := setup_cube_count_for(hex_index)
		for _i in range(draw_count):
			placement_slots.append(hex_index)

	placement_slots.shuffle()

	var cards_by_faction: Dictionary = {}
	for faction_id in Factions.ALL:
		cards_by_faction[faction_id] = []

	var remaining: Array = []
	for card in deck:
		var faction_id := int(
			card.get("faction", Factions.from_suit(str(card.get("suit", "clubs"))))
		)
		if (
			faction_id in cards_by_faction
			and cards_by_faction[faction_id].size() < FACTION_STARTING_CUBES
		):
			cards_by_faction[faction_id].append(card)
		else:
			remaining.append(card)

	deck.clear()
	deck.append_array(remaining)

	var setup_cards: Array = []
	for faction_id in Factions.ALL:
		for card in cards_by_faction.get(faction_id, []):
			setup_cards.append(card)
	setup_cards.shuffle()

	for index in range(mini(setup_cards.size(), placement_slots.size())):
		var card: Dictionary = setup_cards[index]
		var hex_index: int = int(placement_slots[index])
		drawn.append(card)
		var faction: int = int(
			card.get("faction", Factions.from_suit(str(card.get("suit", "clubs"))))
		)
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


static func reject_hexes_for(card: Dictionary) -> Array:
	var hexes: Array = []
	for hex_index in range(HEX_COUNT):
		if is_valid_reject_placement(card, hex_index):
			hexes.append(hex_index)
	return hexes


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


func _cart_goal_for_origin(origin_hex: int) -> int:
	return int(CART_GOALS.get(origin_hex, -1))


static func cart_path_for_origin(origin_hex: int) -> Array:
	var path: Array = CART_PATHS.get(origin_hex, [])
	var copy: Array = []
	for hex_index in path:
		copy.append(int(hex_index))
	return copy


static func next_cart_path_hex(origin_hex: int, current_hex: int) -> int:
	var path: Array = cart_path_for_origin(origin_hex)
	var index := path.find(current_hex)
	if index < 0 or index + 1 >= path.size():
		return -1
	return int(path[index + 1])


static func cart_path_steps_to_goal(origin_hex: int, current_hex: int) -> int:
	var path: Array = cart_path_for_origin(origin_hex)
	var index := path.find(current_hex)
	if index < 0:
		return 999
	return path.size() - 1 - index


func faction_has_undelivered_cart_from_origin(faction: int, origin_hex: int) -> bool:
	if origin_hex < 0 or origin_hex >= HEX_COUNT:
		return false

	for hex_index in range(HEX_COUNT):
		for existing_origin in hexes[hex_index]["carts"].get(faction, []):
			if int(existing_origin) == origin_hex:
				return true

	return false


func faction_has_cart_heading_to(faction: int, hex_index: int, goal_hex: int) -> bool:
	if hex_index < 0 or hex_index >= HEX_COUNT or goal_hex < 0:
		return false

	for existing_origin in hexes[hex_index]["carts"].get(faction, []):
		if _cart_goal_for_origin(int(existing_origin)) == goal_hex:
			return true

	return false


func cart_can_advance(faction: int, from_hex: int, to_hex: int, origin_hex: int) -> bool:
	if not are_adjacent(from_hex, to_hex):
		return false

	var goal_hex := _cart_goal_for_origin(origin_hex)
	if goal_hex < 0:
		return false

	if faction_has_cart_heading_to(faction, to_hex, goal_hex):
		return false

	return to_hex == next_cart_path_hex(origin_hex, from_hex)


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


func carts_scoring_on_advance(faction: int, from_hex: int, to_hex: int) -> int:
	if from_hex < 0 or to_hex < 0:
		return 0

	for origin in hexes[from_hex]["carts"].get(faction, []):
		var origin_hex := int(origin)
		if not cart_can_advance(faction, from_hex, to_hex, origin_hex):
			continue
		if _cart_goal_for_origin(origin_hex) == to_hex:
			return 1

	return 0


func available_cube_space_for_move(
	faction: int,
	dest_hex: int,
	from_hex: int = -1,
	move_cart_also: bool = false
) -> int:
	var space := available_cube_space(faction, dest_hex)
	if from_hex >= 0 and move_cart_also:
		space -= carts_scoring_on_advance(faction, from_hex, dest_hex)
	return maxi(0, space)


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


var last_cart_move: Dictionary = {
	"moved": false,
	"faction": -1,
	"from_hex": -1,
	"to_hex": -1,
	"origin_hex": -1,
}


func _clear_last_cart_move() -> void:
	last_cart_move = {
		"moved": false,
		"faction": -1,
		"from_hex": -1,
		"to_hex": -1,
		"origin_hex": -1,
	}


func clear_last_cart_move() -> void:
	_clear_last_cart_move()


func advance_cart(faction: int, from_hex: int, to_hex: int) -> bool:
	_clear_last_cart_move()
	if not are_adjacent(from_hex, to_hex):
		return false

	var cart_origins: Array = hexes[from_hex]["carts"].get(faction, [])
	for i in range(cart_origins.size()):
		var origin_hex := int(cart_origins[i])
		if not cart_can_advance(faction, from_hex, to_hex, origin_hex):
			continue
		cart_origins.remove_at(i)
		hexes[to_hex]["carts"][faction] = hexes[to_hex]["carts"].get(faction, [])
		hexes[to_hex]["carts"][faction].append(origin_hex)
		last_cart_move = {
			"moved": true,
			"faction": faction,
			"from_hex": from_hex,
			"to_hex": to_hex,
			"origin_hex": origin_hex,
		}
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
		var space := available_cube_space_for_move(faction, to_hex, from_hex, move_cart_also)
		var move_count := mini(cube_count, mini(available, space))
		if move_count > 0:
			_remove_cubes(faction, from_hex, move_count)
			_add_cubes(faction, to_hex, move_count)
			moved = true

	if move_cart_also:
		moved = advance_cart(faction, from_hex, to_hex) or moved

	return moved


func push_ignoring_dominance(
	faction: int,
	from_hex: int,
	to_hex: int,
	cube_count: int = 1,
	move_cart_also: bool = false
) -> bool:
	if not are_adjacent(from_hex, to_hex):
		return false
	if cube_count_for(faction, from_hex) <= 0:
		return false

	var moved := false

	if cube_count > 0:
		var available := cube_count_for(faction, from_hex)
		var space := available_cube_space_for_move(faction, to_hex, from_hex, move_cart_also)
		var move_count := mini(cube_count, mini(available, space))
		if move_count > 0:
			_remove_cubes(faction, from_hex, move_count)
			_add_cubes(faction, to_hex, move_count)
			moved = true

	if move_cart_also:
		moved = advance_cart(faction, from_hex, to_hex) or moved

	return moved


func pull_ignoring_dominance(
	faction: int,
	to_hex: int,
	from_hex: int,
	cube_count: int = 1,
	move_cart_also: bool = false
) -> bool:
	if not are_adjacent(from_hex, to_hex):
		return false
	if cube_count_for(faction, from_hex) <= 0:
		return false

	var moved := false

	if cube_count > 0:
		var available := cube_count_for(faction, from_hex)
		var space := available_cube_space_for_move(faction, to_hex, from_hex, move_cart_also)
		var move_count := mini(cube_count, mini(available, space))
		if move_count > 0:
			_remove_cubes(faction, from_hex, move_count)
			_add_cubes(faction, to_hex, move_count)
			moved = true

	if move_cart_also:
		moved = advance_cart(faction, from_hex, to_hex) or moved

	return moved


func create_cart_ignoring_dominance(faction: int, hex_index: int) -> bool:
	if hex_index not in MOUNTAIN_HEXES:
		return false
	if cube_count_for(faction, hex_index) <= 0:
		return false
	if faction_has_undelivered_cart_from_origin(faction, hex_index):
		return false

	_remove_cubes(faction, hex_index, 1)
	hexes[hex_index]["carts"][faction].append(hex_index)
	return true


func deploy_cube(faction: int, hex_index: int) -> bool:
	if not can_add_cubes(faction, hex_index, 1):
		return false
	_add_cubes(faction, hex_index, 1)
	return true


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
		var space := available_cube_space_for_move(faction, to_hex, from_hex, move_cart_also)
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
	if faction_has_undelivered_cart_from_origin(faction, hex_index):
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


func add_cubes_with_spillover(faction: int, preferred_hex: int, count: int) -> int:
	if count <= 0 or preferred_hex < 0 or preferred_hex >= HEX_COUNT:
		return 0

	var placed := 0
	var remaining := count

	var preferred_space := available_cube_space(faction, preferred_hex)
	if preferred_space > 0:
		var here := mini(remaining, preferred_space)
		_add_cubes(faction, preferred_hex, here)
		placed += here
		remaining -= here

	if remaining <= 0:
		return placed

	for hex_index in range(HEX_COUNT):
		if hex_index == preferred_hex:
			continue
		var space := available_cube_space(faction, hex_index)
		if space <= 0:
			continue
		var here := mini(remaining, space)
		_add_cubes(faction, hex_index, here)
		placed += here
		remaining -= here
		if remaining <= 0:
			break

	return placed


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
