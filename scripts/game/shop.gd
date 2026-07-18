class_name Shop
extends RefCounted

const FACTION_ACTION_COST := RemixRules.FACTION_ACTION_SHOP_COST


static func can_buy_faction_action(coins: int) -> bool:
	return coins >= FACTION_ACTION_COST
