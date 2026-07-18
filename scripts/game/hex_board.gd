class_name HexBoard
extends RefCounted

const HEX_COUNT := 9
const CUBES_PER_FACTION := 3

const WEST_HEXES := [0, 1, 6]
const EAST_HEXES := [8, 5, 2]

const ADJACENCY := {
	0: [1, 2],
	1: [0, 2, 3, 4],
	2: [0, 1, 4, 5],
	3: [1, 4, 6],
	4: [1, 2, 3, 5, 6, 7],
	5: [2, 4, 7, 8],
	6: [3, 4, 7],
	7: [4, 5, 6, 8],
	8: [5, 7],
}

## Hex indices 0-8 display as numbers 1-9 for crib reject placement.
const HEX_NUMBERS := {
	0: 1,
	1: 2,
	2: 3,
	3: 4,
	4: 5,
	5: 6,
	6: 7,
	7: 8,
	8: 9,
}

var hexes: Array = []
var _distance_to_east: Dictionary = {}


func _init() -> void:
	_distance_to_east = _compute_distances_to_east()
	reset()


func reset(cubes_per_faction: int = CUBES_PER_FACTION) -> void:
	hexes.clear()

	for _i in range(HEX_COUNT):
		hexes.append(_empty_hex())

	var faction_index := 0
	for faction in Factions.ALL:
		for cube in range(cubes_per_faction):
			var hex_index := (faction_index * HEX_COUNT + cube * 2) % HEX_COUNT
			hexes[hex_index]["cubes"][faction] += 1
		faction_index += 1


static func hex_number(hex_index: int) -> int:
	return HEX_NUMBERS.get(hex_index, hex_index + 1)


static func hex_index_for_number(number: int) -> int:
	for hex_index in HEX_NUMBERS.keys():
		if HEX_NUMBERS[hex_index] == number:
			return hex_index
	return number - 1


static func is_valid_reject_placement(card: Dictionary, hex_index: int) -> bool:
	if hex_index < 0 or hex_index >= HEX_COUNT:
		return false

	var rank := str(card.get("rank", ""))
	if rank == "10":
		return true

	var rank_number := int(rank)
	return rank_number >= 1 and rank_number <= 9 and hex_number(hex_index) == rank_number


func duplicate_state() -> Array:
	var copy: Array = []
	for hex in hexes:
		copy.append({
			"cubes": hex["cubes"].duplicate(true),
			"carts": hex["carts"].duplicate(true),
		})
	return copy


func load_state(state: Array) -> void:
	hexes.clear()
	for hex in state:
		if hex.has("cubes"):
			hexes.append({
				"cubes": hex["cubes"].duplicate(true),
				"carts": hex["carts"].duplicate(true),
			})
		else:
			hexes.append({
				"cubes": hex.duplicate(true),
				"carts": RemixRules.empty_supply(),
			})


func are_adjacent(a: int, b: int) -> bool:
	return ADJACENCY.get(a, []).has(b)


func controls_hex(faction: int, hex_index: int) -> bool:
	if hex_index < 0 or hex_index >= HEX_COUNT:
		return false

	var cubes: Dictionary = hexes[hex_index]["cubes"]
	var faction_cubes := int(cubes.get(faction, 0))
	if faction_cubes <= 0:
		return false

	for other in Factions.ALL:
		if other == faction:
			continue
		if int(cubes.get(other, 0)) >= faction_cubes:
			return false

	return true


func cart_can_advance(from_hex: int, to_hex: int) -> bool:
	if not are_adjacent(from_hex, to_hex):
		return false

	var from_distance := int(_distance_to_east.get(from_hex, 999))
	var to_distance := int(_distance_to_east.get(to_hex, 999))
	return to_distance < from_distance


func get_faction_power() -> Dictionary:
	var power := {
		Factions.Id.CLUBS: 0,
		Factions.Id.HEARTS: 0,
		Factions.Id.DIAMONDS: 0,
	}

	for hex in hexes:
		for faction in Factions.ALL:
			power[faction] += int(hex["cubes"].get(faction, 0))

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


func push(faction: int, from_hex: int, to_hex: int) -> bool:
	if not controls_hex(faction, from_hex):
		return false
	if not are_adjacent(from_hex, to_hex):
		return false

	var moved := false

	if int(hexes[from_hex]["cubes"].get(faction, 0)) > 0:
		hexes[from_hex]["cubes"][faction] -= 1
		hexes[to_hex]["cubes"][faction] = int(hexes[to_hex]["cubes"].get(faction, 0)) + 1
		moved = true

	if int(hexes[from_hex]["carts"].get(faction, 0)) > 0 and cart_can_advance(from_hex, to_hex):
		hexes[from_hex]["carts"][faction] -= 1
		hexes[to_hex]["carts"][faction] = int(hexes[to_hex]["carts"].get(faction, 0)) + 1
		moved = true

	return moved


func pull(faction: int, to_hex: int, from_hex: int) -> bool:
	if not controls_hex(faction, to_hex):
		return false
	if not are_adjacent(from_hex, to_hex):
		return false

	var moved := false

	if int(hexes[from_hex]["cubes"].get(faction, 0)) > 0:
		hexes[from_hex]["cubes"][faction] -= 1
		hexes[to_hex]["cubes"][faction] = int(hexes[to_hex]["cubes"].get(faction, 0)) + 1
		moved = true

	if int(hexes[from_hex]["carts"].get(faction, 0)) > 0 and cart_can_advance(from_hex, to_hex):
		hexes[from_hex]["carts"][faction] -= 1
		hexes[to_hex]["carts"][faction] = int(hexes[to_hex]["carts"].get(faction, 0)) + 1
		moved = true

	return moved


func create_cart(faction: int, hex_index: int) -> bool:
	if hex_index not in WEST_HEXES:
		return false
	if not controls_hex(faction, hex_index):
		return false
	if int(hexes[hex_index]["cubes"].get(faction, 0)) <= 0:
		return false

	hexes[hex_index]["cubes"][faction] -= 1
	hexes[hex_index]["carts"][faction] = int(hexes[hex_index]["carts"].get(faction, 0)) + 1
	return true


func score_carts_on_goal() -> Dictionary:
	var scored := {
		Factions.Id.CLUBS: 0,
		Factions.Id.HEARTS: 0,
		Factions.Id.DIAMONDS: 0,
	}

	for hex_index in EAST_HEXES:
		for faction in Factions.ALL:
			var cart_count := int(hexes[hex_index]["carts"].get(faction, 0))
			if cart_count <= 0:
				continue
			scored[faction] += cart_count
			hexes[hex_index]["carts"][faction] = 0

	return scored


func remove_cube(faction: int, hex_index: int) -> bool:
	if hex_index < 0 or hex_index >= HEX_COUNT:
		return false
	if int(hexes[hex_index]["cubes"].get(faction, 0)) <= 0:
		return false

	hexes[hex_index]["cubes"][faction] -= 1
	return true


func add_cube(faction: int, hex_index: int) -> bool:
	if hex_index < 0 or hex_index >= HEX_COUNT:
		return false

	hexes[hex_index]["cubes"][faction] = int(hexes[hex_index]["cubes"].get(faction, 0)) + 1
	return true


func _compute_distances_to_east() -> Dictionary:
	var distances: Dictionary = {}
	var queue: Array = []

	for hex_index in EAST_HEXES:
		distances[hex_index] = 0
		queue.append(hex_index)

	var head := 0
	while head < queue.size():
		var current: int = queue[head]
		head += 1
		for neighbor in ADJACENCY.get(current, []):
			if distances.has(neighbor):
				continue
			distances[neighbor] = int(distances[current]) + 1
			queue.append(neighbor)

	return distances


func _empty_hex() -> Dictionary:
	return {
		"cubes": {
			Factions.Id.CLUBS: 0,
			Factions.Id.HEARTS: 0,
			Factions.Id.DIAMONDS: 0,
		},
		"carts": {
			Factions.Id.CLUBS: 0,
			Factions.Id.HEARTS: 0,
			Factions.Id.DIAMONDS: 0,
		},
	}
