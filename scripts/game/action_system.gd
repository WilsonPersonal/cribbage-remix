class_name ActionSystem
extends RefCounted

enum Type {
	PUSH,
	PULL,
	CREATE_CART,
}

const ACTION_COST := 1


static func can_afford(action_points: int, cost: int = ACTION_COST) -> bool:
	return action_points >= cost
