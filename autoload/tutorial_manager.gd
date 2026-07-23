extends Node

const MODULE_HOW_TO_WIN := "how_to_win"
const MODULE_ACTIONS_AND_INFLUENCE := "actions_and_influence"
const HowToWinModule := preload("res://scripts/tutorial/how_to_win_module.gd")
const ActionsAndInfluenceModule := preload("res://scripts/tutorial/actions_and_influence_module.gd")

var pending_module: String = ""


func queue_module(module_id: String) -> void:
	pending_module = module_id


func consume_pending_module() -> String:
	var module_id := pending_module
	pending_module = ""
	return module_id


func get_module_steps(module_id: String) -> Array:
	match module_id:
		MODULE_HOW_TO_WIN:
			return HowToWinModule.steps()
		MODULE_ACTIONS_AND_INFLUENCE:
			return ActionsAndInfluenceModule.steps()
		_:
			return []
