extends Control

@onready var status_label: Label = $HUD/Margin/VBox/StatusLabel
@onready var phase_label: Label = $HUD/Margin/VBox/PhaseLabel
@onready var influence_label: Label = $HUD/Margin/VBox/InfluenceLabel
@onready var coins_label: Label = $HUD/Margin/VBox/CoinsLabel
@onready var action_points_label: Label = $HUD/Margin/VBox/ActionPointsLabel
@onready var faction_actions_label: Label = $HUD/Margin/VBox/FactionActionsLabel
@onready var faction_scores_label: Label = $HUD/Margin/VBox/FactionScoresLabel
@onready var start_round_button: Button = $HUD/Margin/VBox/StartRoundButton
@onready var end_shop_button: Button = $HUD/Margin/VBox/EndShopButton
@onready var end_actions_button: Button = $HUD/Margin/VBox/EndActionsButton
@onready var shop_buttons: HBoxContainer = $HUD/Margin/VBox/ShopButtons
@onready var buy_clubs_button: Button = $HUD/Margin/VBox/ShopButtons/BuyClubsButton
@onready var buy_hearts_button: Button = $HUD/Margin/VBox/ShopButtons/BuyHeartsButton
@onready var buy_diamonds_button: Button = $HUD/Margin/VBox/ShopButtons/BuyDiamondsButton
@onready var board: Control = $Board
@onready var card_panel: PanelContainer = $CardPlayPanel


func _ready() -> void:
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.round_started.connect(_on_round_started)
	GameState.influence_updated.connect(_on_influence_updated)
	GameState.supply_updated.connect(_on_supply_updated)
	GameState.coins_updated.connect(_on_coins_updated)
	GameState.action_points_updated.connect(_on_action_points_updated)
	GameState.faction_actions_updated.connect(_on_faction_actions_updated)
	GameState.faction_scores_updated.connect(_on_faction_scores_updated)
	GameState.winner_decided.connect(_on_winner_decided)
	GameState.game_message.connect(_on_game_message)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	start_round_button.visible = NetworkManager.is_server() and GameState.current_phase in [
		GameState.Phase.WAITING,
		GameState.Phase.ROUND_END,
	]
	start_round_button.pressed.connect(_on_start_round_pressed)
	end_shop_button.pressed.connect(_on_end_shop_pressed)
	end_actions_button.pressed.connect(_on_end_actions_pressed)
	buy_clubs_button.pressed.connect(_on_buy_clubs_pressed)
	buy_hearts_button.pressed.connect(_on_buy_hearts_pressed)
	buy_diamonds_button.pressed.connect(_on_buy_diamonds_pressed)
	card_panel.discard_submitted.connect(_on_discard_submitted)
	card_panel.pegging_play_requested.connect(_on_pegging_play_requested)
	card_panel.pegging_pass_requested.connect(_on_pegging_pass_requested)

	if NetworkManager.is_server():
		GameState.register_player(NetworkManager.get_local_peer_id())

	_refresh_ui()


func _on_player_connected(_peer_id: int) -> void:
	_refresh_ui()


func _on_player_disconnected(_peer_id: int) -> void:
	_refresh_ui()


func _on_start_round_pressed() -> void:
	if NetworkManager.is_server():
		GameState.start_new_round()


func _on_end_shop_pressed() -> void:
	GameState.request_end_shop_phase.rpc_id(1)


func _on_end_actions_pressed() -> void:
	GameState.request_end_action_phase.rpc_id(1)


func _on_buy_clubs_pressed() -> void:
	_buy_faction_action(Factions.Id.CLUBS)


func _on_buy_hearts_pressed() -> void:
	_buy_faction_action(Factions.Id.HEARTS)


func _on_buy_diamonds_pressed() -> void:
	_buy_faction_action(Factions.Id.DIAMONDS)


func _buy_faction_action(faction_id: int) -> void:
	GameState.request_shop_purchase.rpc_id(1, faction_id)


func _on_discard_submitted(card_indices: Array) -> void:
	GameState.request_discard.rpc_id(1, card_indices)


func _on_pegging_play_requested(hand_index: int) -> void:
	GameState.request_pegging_play.rpc_id(1, hand_index)


func _on_pegging_pass_requested() -> void:
	GameState.request_pegging_pass.rpc_id(1)


func _on_game_message(message: String) -> void:
	status_label.text = message


func _on_phase_changed(_phase: GameState.Phase) -> void:
	var in_shop := GameState.current_phase == GameState.Phase.SHOP
	end_shop_button.visible = in_shop
	shop_buttons.visible = in_shop
	end_actions_button.visible = GameState.current_phase == GameState.Phase.SPEND_ACTIONS
	start_round_button.visible = NetworkManager.is_server() and GameState.current_phase in [
		GameState.Phase.WAITING,
		GameState.Phase.ROUND_END,
	]
	_refresh_ui()


func _on_influence_updated(_influence: Dictionary) -> void:
	_refresh_ui()


func _on_supply_updated(_supply: Dictionary) -> void:
	_refresh_ui()


func _on_coins_updated(_coins: Dictionary) -> void:
	_refresh_ui()


func _on_action_points_updated(_action_points: Dictionary) -> void:
	_refresh_ui()


func _on_faction_actions_updated(_actions: Dictionary) -> void:
	_refresh_ui()


func _on_faction_scores_updated(_scores: Dictionary) -> void:
	_refresh_ui()


func _on_round_started(round_number: int) -> void:
	var total := GameState.get_total_faction_score()
	status_label.text = "Round %d started. Combined faction score: %d / %d." % [
		round_number,
		total,
		RemixRules.ENDING_SCORE_TOTAL,
	]


func _on_winner_decided(peer_id: int, faction_id: int) -> void:
	var winner_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
	status_label.text = "%s wins with the most influence in %s." % [
		winner_name,
		Factions.name_for(faction_id),
	]


func _refresh_ui() -> void:
	var player_count := multiplayer.get_peers().size() + 1
	status_label.text = "%s | %d player(s) connected" % [
		"Host" if NetworkManager.is_server() else "Client",
		player_count,
	]
	phase_label.text = "Phase: %s" % _phase_name(GameState.current_phase)
	influence_label.text = _format_influence()
	coins_label.text = _format_coins()
	action_points_label.text = _format_action_points()
	faction_actions_label.text = _format_faction_actions()
	faction_scores_label.text = _format_faction_scores()
	board.queue_redraw()


func _format_influence() -> String:
	if GameState.player_influence.is_empty():
		return "Influence: waiting for players..."

	var lines: PackedStringArray = ["Influence / supply:"]
	for peer_id in GameState.player_influence.keys():
		var player_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
		var influence: Dictionary = GameState.player_influence[peer_id]
		var supply: Dictionary = GameState.player_supply.get(peer_id, RemixRules.empty_supply())
		var parts: PackedStringArray = []
		for faction in Factions.ALL:
			parts.append(
				"%s inf %d sup %d" % [
					Factions.name_for(faction),
					influence.get(faction, 0),
					supply.get(faction, 0),
				]
			)
		lines.append("%s: %s" % [player_name, ", ".join(parts)])

	return "\n".join(lines)


func _format_coins() -> String:
	if GameState.player_coins.is_empty():
		return "Coins: none yet"

	var lines: PackedStringArray = ["Coins (from pegging):"]
	for peer_id in GameState.player_coins.keys():
		var player_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
		lines.append("%s: %d" % [player_name, GameState.player_coins[peer_id]])

	return "\n".join(lines)


func _format_action_points() -> String:
	if GameState.action_points.is_empty():
		return "Actions: none yet"

	var lines: PackedStringArray = ["General actions (from show hands):"]
	for peer_id in GameState.action_points.keys():
		var player_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
		lines.append("%s: %d" % [player_name, GameState.action_points[peer_id]])

	return "\n".join(lines)


func _format_faction_actions() -> String:
	if GameState.player_faction_actions.is_empty():
		return "Faction shop actions: none yet"

	var lines: PackedStringArray = [
		"Faction shop actions (%d coins each):" % Shop.FACTION_ACTION_COST,
	]
	for peer_id in GameState.player_faction_actions.keys():
		var player_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
		var tokens: Dictionary = GameState.player_faction_actions[peer_id]
		var parts: PackedStringArray = []
		for faction in Factions.ALL:
			parts.append("%s %d" % [Factions.name_for(faction), tokens.get(faction, 0)])
		lines.append("%s: %s" % [player_name, ", ".join(parts)])

	return "\n".join(lines)


func _format_faction_scores() -> String:
	var total := GameState.get_total_faction_score()
	var lines: PackedStringArray = [
		"Faction scores (game ends after round hitting %d total):" % RemixRules.ENDING_SCORE_TOTAL,
		"Combined: %d / %d" % [total, RemixRules.ENDING_SCORE_TOTAL],
	]
	for faction in Factions.ALL:
		lines.append("%s: %d" % [Factions.name_for(faction), GameState.faction_scores.get(faction, 0)])
	return "\n".join(lines)


func _phase_name(phase: GameState.Phase) -> String:
	match phase:
		GameState.Phase.WAITING:
			return "Waiting for players"
		GameState.Phase.DEAL:
			return "Deal hands"
		GameState.Phase.DISCARD_TO_CRIB:
			return "Discard to crib"
		GameState.Phase.CUT_STARTER:
			return "Cut starter"
		GameState.Phase.PEGGING:
			return "Pegging for coins"
		GameState.Phase.SHOW_HANDS:
			return "Show hands for actions"
		GameState.Phase.SHOP:
			return "Buy faction actions"
		GameState.Phase.SPEND_ACTIONS:
			return "Spend actions (Push / Pull / Cart)"
		GameState.Phase.RESOLVE_CRIB:
			return "Resolve crib suits"
		GameState.Phase.ROUND_END:
			return "Round complete"
		GameState.Phase.GAME_OVER:
			return "Game over"
		_:
			return "Unknown"
