class_name FactionPowerRating
extends RefCounted

const SCORE_MULTIPLIER := 100
const CART_ONE_AWAY_FROM_FOREST := 70
const CART_TWO_AWAY_FROM_FOREST := 45
const CART_ON_MOUNTAIN := 25
const DOMINANCE_WITH_OWN_CART := 10.0
const MOUNTAIN_DOMINANCE := 5.0
const PASTURE_DOMINANCE := 2.5
const FOREST_DOMINANCE := 1.5
const CUBE_ON_DOMINATED_HEX := 1
const CUBE_ON_MOUNTAIN := 0.75
const CUBE_ON_PASTURE := 0.5
const CUBE_ON_FOREST := 0.25


static func compute_all(board_state: Array, faction_scores: Dictionary) -> Dictionary:
	var board := HexBoard.new()
	board.load_state(board_state)
	var ratings := {}

	for faction_id in Factions.ALL:
		var score := int(RemixRules.faction_dict_value(faction_scores, faction_id))
		ratings[faction_id] = _compute_faction_power(board, faction_id, score)

	return ratings


static func format_ratings_line(ratings: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for faction_id in Factions.ALL:
		var entry: Dictionary = ratings.get(faction_id, {})
		parts.append("%s %s" % [Factions.name_for(faction_id), _format_power_value(entry.get("total", 0.0))])
	return ", ".join(parts)


static func format_ratings_change(before: Dictionary, after: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for faction_id in Factions.ALL:
		var before_entry: Dictionary = before.get(faction_id, {})
		var after_entry: Dictionary = after.get(faction_id, {})
		var before_total := float(before_entry.get("total", 0.0))
		var after_total := float(after_entry.get("total", 0.0))
		var delta := after_total - before_total
		var delta_text := ""
		if absf(delta) >= 0.01:
			if delta > 0.0:
				delta_text = " (+%s)" % _format_power_value(delta)
			else:
				delta_text = " (%s)" % _format_power_value(delta)
		lines.append(
			"  %s: %s -> %s%s"
			% [
				Factions.name_for(faction_id),
				_format_power_value(before_total),
				_format_power_value(after_total),
				delta_text,
			]
		)
	return "\n".join(lines)


static func compute_ai_power(
	ratings: Dictionary,
	peer_id: int,
	opponent_id: int,
	context: AiContext = null
) -> Dictionary:
	var total := 0.0
	var by_faction := {}

	for faction_id in Factions.ALL:
		var faction_power := float(ratings.get(faction_id, {}).get("total", 0.0))
		var influence_diff := _influence_diff(peer_id, opponent_id, faction_id, context)
		var contribution := faction_power * float(influence_diff)
		by_faction[faction_id] = {
			"faction_power": faction_power,
			"influence_diff": influence_diff,
			"contribution": contribution,
		}
		total += contribution

	return {
		"total": total,
		"by_faction": by_faction,
		"assumed_influence_bonus": (
			context.influence_bonus.duplicate(true) if context != null else {}
		),
	}


static func format_ai_power(
	ratings: Dictionary,
	peer_id: int,
	opponent_id: int,
	context: AiContext = null
) -> String:
	var ai_power := compute_ai_power(ratings, peer_id, opponent_id, context)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("  Total: %s" % _format_power_value(float(ai_power.get("total", 0.0))))

	var by_faction: Dictionary = ai_power.get("by_faction", {})
	for faction_id in Factions.ALL:
		var entry: Dictionary = by_faction.get(faction_id, {})
		var faction_power := float(entry.get("faction_power", 0.0))
		var influence_diff := int(entry.get("influence_diff", 0))
		var contribution := float(entry.get("contribution", 0.0))
		lines.append(
			"  %s: %s x %+d = %s"
			% [
				Factions.name_for(faction_id),
				_format_power_value(faction_power),
				influence_diff,
				_format_power_value(contribution),
			]
		)

	return "\n".join(lines)


static func format_ai_power_change(
	before: Dictionary,
	after: Dictionary,
	peer_id: int,
	opponent_id: int,
	before_context: AiContext = null,
	after_context: AiContext = null
) -> String:
	var before_power := compute_ai_power(before, peer_id, opponent_id, before_context)
	var after_power := compute_ai_power(after, peer_id, opponent_id, after_context)
	var before_total := float(before_power.get("total", 0.0))
	var after_total := float(after_power.get("total", 0.0))
	var delta := after_total - before_total
	var delta_text := ""
	if absf(delta) >= 0.01:
		if delta > 0.0:
			delta_text = " (+%s)" % _format_power_value(delta)
		else:
			delta_text = " (%s)" % _format_power_value(delta)

	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		"  Total: %s -> %s%s"
		% [_format_power_value(before_total), _format_power_value(after_total), delta_text]
	)

	for faction_id in Factions.ALL:
		var before_entry: Dictionary = before_power.get("by_faction", {}).get(faction_id, {})
		var after_entry: Dictionary = after_power.get("by_faction", {}).get(faction_id, {})
		var before_faction_power := float(before_entry.get("faction_power", 0.0))
		var after_faction_power := float(after_entry.get("faction_power", 0.0))
		var before_influence_diff := int(before_entry.get("influence_diff", 0))
		var after_influence_diff := int(after_entry.get("influence_diff", 0))
		var before_contribution := float(before_entry.get("contribution", 0.0))
		var after_contribution := float(after_entry.get("contribution", 0.0))
		var faction_delta := after_contribution - before_contribution
		var faction_delta_text := ""
		if absf(faction_delta) >= 0.01:
			if faction_delta > 0.0:
				faction_delta_text = " (+%s)" % _format_power_value(faction_delta)
			else:
				faction_delta_text = " (%s)" % _format_power_value(faction_delta)

		lines.append(
			"  %s: %s x %+d = %s -> %s x %+d = %s%s"
			% [
				Factions.name_for(faction_id),
				_format_power_value(before_faction_power),
				before_influence_diff,
				_format_power_value(before_contribution),
				_format_power_value(after_faction_power),
				after_influence_diff,
				_format_power_value(after_contribution),
				faction_delta_text,
			]
		)

	return "\n".join(lines)


static func format_ai_power_totals(before: Dictionary, after: Dictionary) -> String:
	var before_total := float(before.get("total", 0.0))
	var after_total := float(after.get("total", before_total))
	var delta := after_total - before_total
	var delta_text := ""
	if absf(delta) >= 0.01:
		if delta > 0.0:
			delta_text = " (+%s)" % _format_power_value(delta)
		else:
			delta_text = " (%s)" % _format_power_value(delta)
	return "  Total: %s -> %s%s" % [
		_format_power_value(before_total),
		_format_power_value(after_total),
		delta_text,
	]


static func compute_ai_power_delta(
	before_ratings: Dictionary,
	after_ratings: Dictionary,
	peer_id: int,
	opponent_id: int,
	before_context: AiContext = null,
	after_context: AiContext = null,
	factors = null
) -> Dictionary:
	var before_power := compute_ai_power(before_ratings, peer_id, opponent_id, before_context)
	var after_power := compute_ai_power(after_ratings, peer_id, opponent_id, after_context)
	var before_total := float(before_power.get("total", 0.0))
	var after_total := float(after_power.get("total", 0.0))
	var total := after_total - before_total

	if factors != null:
		for faction_id in Factions.ALL:
			var before_entry: Dictionary = before_power.get("by_faction", {}).get(faction_id, {})
			var after_entry: Dictionary = after_power.get("by_faction", {}).get(faction_id, {})
			var before_contribution := float(before_entry.get("contribution", 0.0))
			var after_contribution := float(after_entry.get("contribution", 0.0))
			var delta := after_contribution - before_contribution
			if absf(delta) >= 0.01:
				var before_influence_diff := int(before_entry.get("influence_diff", 0))
				var after_influence_diff := int(after_entry.get("influence_diff", 0))
				_add_factor(
					factors,
					"%s: AI power %s -> %s (influence %+d -> %+d)"
					% [
						Factions.name_for(faction_id),
						_format_power_value(before_contribution),
						_format_power_value(after_contribution),
						before_influence_diff,
						after_influence_diff,
					],
					delta
				)

	return {
		"total": total,
		"before": before_power,
		"after": after_power,
	}


static func score_rating_change(
	before: Dictionary,
	after: Dictionary,
	peer_id: int,
	opponent_id: int,
	factors = null,
	context: AiContext = null
) -> Dictionary:
	var total := 0.0

	for faction_id in Factions.ALL:
		var before_total := float(before.get(faction_id, {}).get("total", 0.0))
		var after_total := float(after.get(faction_id, {}).get("total", 0.0))
		var delta := after_total - before_total
		var influence_diff := _influence_diff(peer_id, opponent_id, faction_id, context)
		var contribution := delta * float(influence_diff)
		total += contribution

		if factors != null and (absf(contribution) >= 0.01 or absf(delta) >= 0.01):
			_add_factor(
				factors,
				"%s: power %s x influence %+d"
				% [Factions.name_for(faction_id), _format_signed_power_value(delta), influence_diff],
				contribution
			)

	return {"total": total}


static func _influence_diff(
	peer_id: int,
	opponent_id: int,
	faction_id: int,
	context: AiContext = null
) -> int:
	if (
		context != null
		and int(peer_id) == int(context.peer_id)
		and int(opponent_id) == int(context.opponent_id)
	):
		return context.influence_diff(faction_id)
	return (
		AiContext.influence_for(peer_id, faction_id)
		- AiContext.influence_for(opponent_id, faction_id)
	)


static func _compute_faction_power(board: HexBoard, faction_id: int, score: int) -> Dictionary:
	var base := float(score * SCORE_MULTIPLIER)
	var cart_one_away := 0
	var cart_two_away := 0
	var cart_on_mountain := 0
	var dominance_with_cart := 0.0
	var mountain_dominance := 0.0
	var pasture_dominance := 0.0
	var forest_dominance := 0.0
	var cubes_on_dominated := 0.0
	var cubes_on_mountain := 0.0
	var cubes_on_pasture := 0.0
	var cubes_on_forest := 0.0

	for hex_index in range(HexBoard.HEX_COUNT):
		var cube_count := board.cube_count_for(faction_id, hex_index)
		if cube_count > 0:
			if hex_index in HexBoard.MOUNTAIN_HEXES:
				cubes_on_mountain += float(cube_count) * CUBE_ON_MOUNTAIN
			elif hex_index in HexBoard.PASTURE_HEXES:
				cubes_on_pasture += float(cube_count) * CUBE_ON_PASTURE
			elif hex_index in HexBoard.FOREST_HEXES:
				cubes_on_forest += float(cube_count) * CUBE_ON_FOREST

		if board.controls_hex(faction_id, hex_index):
			if hex_index in HexBoard.MOUNTAIN_HEXES:
				if cube_count >= 2:
					mountain_dominance += MOUNTAIN_DOMINANCE
			elif hex_index in HexBoard.PASTURE_HEXES:
				pasture_dominance += PASTURE_DOMINANCE
			elif hex_index in HexBoard.FOREST_HEXES:
				forest_dominance += FOREST_DOMINANCE

			if _faction_has_cart_on_hex(board, faction_id, hex_index):
				dominance_with_cart += DOMINANCE_WITH_OWN_CART

			if cube_count > 0:
				cubes_on_dominated += float(cube_count) * CUBE_ON_DOMINATED_HEX

	for hex_index in range(HexBoard.HEX_COUNT):
		var mountain_cubes := board.cube_count_for(faction_id, hex_index)
		for _origin in board.hexes[hex_index]["carts"].get(faction_id, []):
			var origin_hex := int(_origin)
			var steps := board.cart_path_steps_to_goal(origin_hex, hex_index)
			if steps == 1:
				cart_one_away += CART_ONE_AWAY_FROM_FOREST
			elif steps == 2:
				cart_two_away += CART_TWO_AWAY_FROM_FOREST
			if hex_index in HexBoard.MOUNTAIN_HEXES and mountain_cubes >= 1:
				cart_on_mountain += CART_ON_MOUNTAIN

	var board_bonus := (
		float(cart_one_away + cart_two_away + cart_on_mountain)
		+ dominance_with_cart
		+ mountain_dominance
		+ pasture_dominance
		+ forest_dominance
		+ cubes_on_dominated
		+ cubes_on_mountain
		+ cubes_on_pasture
		+ cubes_on_forest
	)

	return {
		"score": score,
		"base": base,
		"cart_one_away": cart_one_away,
		"cart_two_away": cart_two_away,
		"cart_on_mountain": cart_on_mountain,
		"dominance_with_cart": dominance_with_cart,
		"mountain_dominance": mountain_dominance,
		"pasture_dominance": pasture_dominance,
		"forest_dominance": forest_dominance,
		"cubes_on_dominated": cubes_on_dominated,
		"cubes_on_mountain": cubes_on_mountain,
		"cubes_on_pasture": cubes_on_pasture,
		"cubes_on_forest": cubes_on_forest,
		"board_bonus": board_bonus,
		"total": base + board_bonus,
	}


static func _faction_has_cart_on_hex(board: HexBoard, faction_id: int, hex_index: int) -> bool:
	return not board.hexes[hex_index]["carts"].get(faction_id, []).is_empty()


static func _format_power_value(value: float) -> String:
	if absf(value - roundf(value)) < 0.01:
		return str(int(roundf(value)))
	return "%.2f" % value


static func _format_signed_power_value(value: float) -> String:
	var formatted := _format_power_value(absf(value))
	if value >= 0.01:
		return "+%s" % formatted
	if value <= -0.01:
		return "-%s" % formatted
	return "0"


static func _add_factor(factors: Array, name: String, score: float) -> float:
	if absf(score) >= 0.01:
		factors.append({"name": name, "score": score})
	return score
