extends Control

const HUD_WIDTH_RATIO := 0.28
const MAIN_WIDTH_RATIO := 0.72
const CARD_PANEL_HEIGHT := 200
const CUBE_MOVE_SPIN_MAX := 5
const PANEL_BG_COLOR := Color(0.1, 0.12, 0.16, 0.92)

@onready var hud: PanelContainer = $HUD
@onready var status_label: Label = $HUD/Margin/VBox/StatusLabel
@onready var phase_label: Label = $HUD/Margin/VBox/PhaseLabel
@onready var pegging_count_label: Label = $HUD/Margin/VBox/PeggingCountLabel
@onready var pegging_turn_label: Label = $HUD/Margin/VBox/PeggingTurnLabel
@onready var influence_display: VBoxContainer = $HUD/Margin/VBox/InfluenceDisplay
@onready var coins_label: Label = $HUD/Margin/VBox/CoinsLabel
@onready var crib_discards_label: Label = $HUD/Margin/VBox/CribDiscardsLabel
@onready var action_points_label: Label = $HUD/Margin/VBox/ActionPointsLabel
@onready var faction_actions_label: Label = $HUD/Margin/VBox/FactionActionsLabel
@onready var start_round_button: Button = $HUD/Margin/VBox/StartRoundButton
@onready var end_shop_button: Button = $HUD/Margin/VBox/EndShopButton
@onready var end_actions_button: Button = $HUD/Margin/VBox/EndActionsButton
@onready var shop_buttons: HBoxContainer = $HUD/Margin/VBox/ShopButtons
@onready var buy_clubs_button: Button = $HUD/Margin/VBox/ShopButtons/BuyClubsButton
@onready var buy_hearts_button: Button = $HUD/Margin/VBox/ShopButtons/BuyHeartsButton
@onready var buy_diamonds_button: Button = $HUD/Margin/VBox/ShopButtons/BuyDiamondsButton
@onready var action_panel: VBoxContainer = $HUD/Margin/VBox/ActionPanel
@onready var actions_left_big_label: Label = $HUD/Margin/VBox/ActionPanel/ActionsLeftBigLabel
@onready var action_help_label: Label = $HUD/Margin/VBox/ActionPanel/ActionHelpLabel
@onready var cube_count_row: HBoxContainer = $HUD/Margin/VBox/ActionPanel/CubeCountRow
@onready var cube_count_spin: SpinBox = $HUD/Margin/VBox/ActionPanel/CubeCountRow/CubeCountSpin
@onready var move_cart_check: CheckBox = $HUD/Margin/VBox/ActionPanel/CubeCountRow/MoveCartCheck
@onready var push_button: Button = $HUD/Margin/VBox/ActionPanel/ActionButtons/PushButton
@onready var pull_button: Button = $HUD/Margin/VBox/ActionPanel/ActionButtons/PullButton
@onready var cart_button: Button = $HUD/Margin/VBox/ActionPanel/ActionButtons/CartButton
@onready var undo_action_button: Button = $HUD/Margin/VBox/ActionPanel/UndoActionButton
@onready var clear_action_button: Button = $HUD/Margin/VBox/ActionPanel/ClearActionButton
@onready var board: Control = $Board
@onready var card_panel = $CardPlayPanel
@onready var offline_bar: VBoxContainer = $HUD/Margin/VBox/OfflineBar
@onready var control_peer_label: Label = $HUD/Margin/VBox/OfflineBar/ControlPeerLabel
@onready var switch_player_button: Button = $HUD/Margin/VBox/OfflineBar/OfflineButtons/SwitchPlayerButton
@onready var save_debug_button: Button = $HUD/Margin/VBox/OfflineBar/OfflineButtons/SaveDebugButton
@onready var load_debug_button: Button = $HUD/Margin/VBox/OfflineBar/OfflineButtons/LoadDebugButton

var _selected_action_type: int = -1
var _selected_source_hex: int = -1


func _ready() -> void:
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.round_started.connect(_on_round_started)
	GameState.influence_updated.connect(_on_influence_updated)
	GameState.coins_updated.connect(_on_coins_updated)
	GameState.action_points_updated.connect(_on_action_points_updated)
	GameState.faction_actions_updated.connect(_on_faction_actions_updated)
	GameState.faction_scores_updated.connect(_on_faction_scores_updated)
	GameState.winner_decided.connect(_on_winner_decided)
	GameState.game_message.connect(_on_game_message)
	GameState.active_control_changed.connect(_on_active_control_changed)
	GameState.pegging_state_updated.connect(_on_pegging_state_updated)
	GameState.board_updated.connect(_on_board_updated)
	GameState.action_turn_updated.connect(_on_action_turn_updated)
	GameState.action_history_changed.connect(_on_action_history_changed)
	GameState.crib_cube_anim_requested.connect(_on_crib_cube_anim_requested)
	GameState.action_cube_anim_requested.connect(_on_action_cube_anim_requested)
	GameState.action_cart_anim_requested.connect(_on_action_cart_anim_requested)
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
	card_panel.crib_hex_highlights_changed.connect(_on_crib_hex_highlights_changed)
	switch_player_button.pressed.connect(_on_switch_player_pressed)
	save_debug_button.pressed.connect(_on_save_debug_pressed)
	load_debug_button.pressed.connect(_on_load_debug_pressed)
	board.hex_clicked.connect(_on_board_hex_clicked)

	push_button.pressed.connect(_on_push_pressed)
	pull_button.pressed.connect(_on_pull_pressed)
	cart_button.pressed.connect(_on_cart_pressed)
	undo_action_button.pressed.connect(_on_undo_action_pressed)
	clear_action_button.pressed.connect(_on_clear_action_pressed)

	if NetworkManager.is_offline_debug():
		offline_bar.visible = true
		GameState.setup_offline_session("Player 1", "Player 2")
		call_deferred("_auto_start_offline_round")
	else:
		offline_bar.visible = false
		if NetworkManager.is_server():
			GameState.register_player(NetworkManager.get_local_peer_id())

	_apply_panel_style(hud)
	_apply_hud_content_width()
	_setup_cube_count_spin()
	resized.connect(_apply_layout)
	call_deferred("_apply_layout")
	_refresh_ui()


func _apply_panel_style(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.set_content_margin_all(0)
	style.expand_margin_left = 0
	style.expand_margin_top = 0
	style.expand_margin_right = 0
	style.expand_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", style)
	panel.clip_contents = true


func _apply_hud_content_width() -> void:
	var hud_content := hud.get_node("Margin/VBox")
	for child in hud_content.get_children():
		if child is Control:
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if child is Label:
				child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	influence_display.custom_minimum_size.x = 0


func _apply_layout() -> void:
	var main_right := MAIN_WIDTH_RATIO
	var card_height := float(CARD_PANEL_HEIGHT)

	hud.set_anchors_preset(Control.PRESET_TOP_RIGHT, true)
	hud.anchor_left = main_right
	hud.anchor_top = 0.0
	hud.anchor_right = 1.0
	hud.anchor_bottom = 1.0
	hud.offset_left = 0.0
	hud.offset_top = 0.0
	hud.offset_right = 0.0
	hud.offset_bottom = 0.0
	hud.z_index = 2

	board.set_anchors_preset(Control.PRESET_FULL_RECT, true)
	board.anchor_left = 0.0
	board.anchor_top = 0.0
	board.anchor_right = main_right
	board.anchor_bottom = 1.0
	board.offset_left = 0.0
	board.offset_top = 0.0
	board.offset_right = 0.0
	board.offset_bottom = -card_height

	card_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	card_panel.anchor_left = 0.0
	card_panel.anchor_top = 1.0
	card_panel.anchor_right = main_right
	card_panel.anchor_bottom = 1.0
	card_panel.offset_left = 0.0
	card_panel.offset_top = -card_height
	card_panel.offset_right = 0.0
	card_panel.offset_bottom = 0.0
	card_panel.z_index = 1

	influence_display.refresh()


func _on_action_history_changed(can_undo: bool) -> void:
	undo_action_button.disabled = not can_undo or not GameState.is_action_turn_for_control()


func _on_undo_action_pressed() -> void:
	GameState.submit_undo_action()


func _on_action_turn_updated(_peer_id: int) -> void:
	_clear_action_selection()
	_update_action_phase_ui()
	_refresh_ui()
	if _selected_source_hex >= 0:
		_update_action_highlights()


func _on_board_updated(_board_state: Array, _faction_power: Dictionary) -> void:
	if _selected_source_hex >= 0:
		_update_action_highlights()


func _on_crib_cube_anim_requested(
	accept: bool,
	hex_index: int,
	faction_id: int,
	card_index: int,
	peer_id: int
) -> void:
	var from_pos: Vector2
	var to_pos: Vector2
	var end_radius := FlyingCube.MAP_CUBE_RADIUS
	var on_complete := _clear_crib_cube_anim_visuals

	if accept:
		influence_display.set_crib_influence_anim_mask(peer_id, faction_id)
		from_pos = board.get_faction_cube_dot_global_before_remove(hex_index, faction_id)
		to_pos = influence_display.get_last_dot_global(peer_id)
		end_radius = influence_display.DOT_RADIUS
	else:
		board.set_crib_cube_anim_mask(hex_index, faction_id)
		from_pos = card_panel.get_crib_card_global_center(card_index)
		to_pos = board.get_faction_cube_dot_global_after_add(hex_index, faction_id)

	FlyingCube.fly(
		self,
		from_pos,
		to_pos,
		Factions.COLORS[faction_id],
		FlyingCube.MAP_CUBE_RADIUS,
		FlyingCube.DEFAULT_DURATION,
		end_radius,
		0.0,
		on_complete
	)


func _clear_crib_cube_anim_visuals() -> void:
	board.clear_crib_cube_anim_mask()
	influence_display.clear_crib_influence_anim_mask()


func _on_action_cube_anim_requested(
	faction_id: int,
	from_hex: int,
	to_hex: int,
	move_count: int
) -> void:
	if move_count <= 0:
		return

	board.set_action_cube_anim_mask(from_hex, to_hex, faction_id, move_count)

	var remaining := move_count
	var on_cube_landed := func() -> void:
		board.reveal_action_cube_at_destination()
		remaining -= 1
		if remaining <= 0:
			board.clear_action_cube_anim_mask()

	var source_count := GameState.get_faction_cubes_on_hex(from_hex, faction_id)
	var dest_count := GameState.get_faction_cubes_on_hex(to_hex, faction_id)
	var color: Color = Factions.COLORS[faction_id]

	for cube_index in range(move_count):
		var from_pos: Vector2 = board.get_faction_cube_dot_global_at_index_with_extra(
			from_hex,
			faction_id,
			source_count + cube_index,
			move_count
		)
		var to_pos: Vector2 = board.get_faction_cube_dot_global_at_index(
			to_hex,
			faction_id,
			dest_count - move_count + cube_index
		)
		FlyingCube.fly(
			self,
			from_pos,
			to_pos,
			color,
			FlyingCube.MAP_CUBE_RADIUS,
			FlyingCube.DEFAULT_DURATION,
			-1.0,
			float(cube_index) * 0.07,
			on_cube_landed
		)


func _on_action_cart_anim_requested(
	faction_id: int,
	from_hex: int,
	to_hex: int,
	origin_hex: int
) -> void:
	if from_hex < 0 or to_hex < 0 or origin_hex < 0:
		return

	board.set_action_cart_anim_mask(from_hex, to_hex, faction_id, origin_hex)

	var on_cart_landed := func() -> void:
		board.reveal_action_cart_at_destination()
		board.clear_action_cart_anim_mask()

	var from_pos: Vector2 = board.get_cart_arrow_global_midpoint(
		from_hex,
		faction_id,
		origin_hex,
		true
	)
	var to_pos: Vector2 = board.get_cart_arrow_global_midpoint(
		to_hex,
		faction_id,
		origin_hex,
		true
	)
	var from_dir: Vector2 = board.get_cart_arrow_global_direction(from_hex, origin_hex)
	var to_dir: Vector2 = board.get_cart_arrow_global_direction(to_hex, origin_hex)
	var color: Color = Factions.COLORS[faction_id]

	FlyingCart.fly(
		self,
		from_pos,
		to_pos,
		color,
		from_dir,
		to_dir,
		FlyingCart.DEFAULT_DURATION,
		0.0,
		on_cart_landed
	)


func _on_player_connected(peer_id: int) -> void:
	if NetworkManager.is_offline_debug():
		return
	if NetworkManager.is_server():
		GameState.register_player(peer_id)
	_refresh_ui()


func _on_player_disconnected(_peer_id: int) -> void:
	_refresh_ui()


func _on_start_round_pressed() -> void:
	if NetworkManager.is_server():
		GameState.start_new_round()


func _auto_start_offline_round() -> void:
	if NetworkManager.is_offline_debug() and GameState.current_phase == GameState.Phase.WAITING:
		GameState.start_new_round()


func _on_end_shop_pressed() -> void:
	GameState.submit_end_shop_phase()


func _on_end_actions_pressed() -> void:
	GameState.submit_end_action_phase()


func _on_buy_clubs_pressed() -> void:
	_buy_faction_action(Factions.Id.CLUBS)


func _on_buy_hearts_pressed() -> void:
	_buy_faction_action(Factions.Id.HEARTS)


func _on_buy_diamonds_pressed() -> void:
	_buy_faction_action(Factions.Id.DIAMONDS)


func _buy_faction_action(faction_id: int) -> void:
	GameState.submit_shop_purchase(faction_id)


func _on_discard_submitted(card_indices: Array) -> void:
	GameState.submit_discard(card_indices)


func _on_pegging_play_requested(hand_index: int) -> void:
	GameState.submit_pegging_play(hand_index)


func _on_pegging_pass_requested() -> void:
	GameState.submit_pegging_pass()


func _on_crib_hex_highlights_changed(target_hexes: Array) -> void:
	if target_hexes.is_empty():
		board.clear_crib_selection()
	else:
		board.set_crib_selection(target_hexes)


func _on_game_message(message: String) -> void:
	status_label.text = message


func _on_active_control_changed(_peer_id: int) -> void:
	_clear_action_selection()
	_update_action_phase_ui()
	_refresh_ui()


func _on_switch_player_pressed() -> void:
	GameState.toggle_control_peer()


func _on_save_debug_pressed() -> void:
	if GameState.save_debug_snapshot():
		status_label.text = "Debug save written to %s" % GameState.DEBUG_SAVE_PATH
	else:
		status_label.text = "Failed to write debug save."


func _on_load_debug_pressed() -> void:
	_clear_action_selection()
	if GameState.load_debug_snapshot():
		_refresh_ui()
	else:
		status_label.text = "Failed to load debug save from %s" % GameState.DEBUG_SAVE_PATH


func _on_pegging_state_updated(_sequence: Array, total: int, turn_peer: int) -> void:
	_update_pegging_hud(total, turn_peer)


func _on_phase_changed(_phase: GameState.Phase) -> void:
	var in_shop := GameState.current_phase == GameState.Phase.SHOP
	var in_actions := GameState.current_phase == GameState.Phase.SPEND_ACTIONS
	end_shop_button.visible = in_shop
	shop_buttons.visible = in_shop
	end_actions_button.visible = in_actions and GameState.is_action_turn_for_control()
	action_panel.visible = in_actions and GameState.is_action_turn_for_control()
	start_round_button.visible = NetworkManager.is_server() and GameState.current_phase in [
		GameState.Phase.WAITING,
		GameState.Phase.ROUND_END,
	]

	if not in_actions:
		_clear_action_selection()

	_update_action_phase_ui()
	_update_pegging_hud(GameState.pegging_total, GameState.pegging_turn_peer)
	_update_action_help()
	_refresh_ui()


func _update_action_phase_ui() -> void:
	var in_actions := GameState.current_phase == GameState.Phase.SPEND_ACTIONS
	end_actions_button.visible = in_actions and GameState.is_action_turn_for_control()
	action_panel.visible = in_actions and GameState.is_action_turn_for_control()
	if in_actions:
		end_actions_button.text = "End My Actions"


func _on_influence_updated(_influence: Dictionary) -> void:
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


func _on_push_pressed() -> void:
	_select_action(ActionSystem.Type.PUSH)


func _on_pull_pressed() -> void:
	_select_action(ActionSystem.Type.PULL)


func _on_cart_pressed() -> void:
	_select_action(ActionSystem.Type.CREATE_CART)


func _on_clear_action_pressed() -> void:
	_clear_action_selection()


func _on_board_hex_clicked(hex_index: int) -> void:
	if GameState.current_phase in [
		GameState.Phase.SETUP_MINI_CRIB,
		GameState.Phase.RESOLVE_CRIB,
	]:
		card_panel.handle_crib_hex(hex_index)
		return
	if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
		return
	if not GameState.is_action_turn_for_control():
		action_help_label.text = "Wait for the other player's action turn."
		return
	if not _action_selection_ready():
		action_help_label.text = "Choose an action first."
		return

	var peer_id := GameState.get_action_turn_peer_id()
	if not GameState.player_can_afford_any_action(peer_id):
		action_help_label.text = "No actions left."
		return

	match _selected_action_type:
		ActionSystem.Type.CREATE_CART:
			_try_create_cart(hex_index, peer_id)
		ActionSystem.Type.PUSH:
			_try_push(hex_index, peer_id)
		ActionSystem.Type.PULL:
			_try_pull(hex_index, peer_id)


func _select_action(action_type: int) -> void:
	_selected_action_type = action_type
	_selected_source_hex = -1
	_update_action_button_styles()
	_update_cube_count_visibility()
	_update_action_help()
	_update_action_highlights()


func _clear_action_selection() -> void:
	_selected_action_type = -1
	_selected_source_hex = -1
	_update_action_button_styles()
	_update_cube_count_visibility()
	board.clear_action_selection()
	board.clear_crib_selection()
	_update_action_help()


func _action_selection_ready() -> bool:
	return _selected_action_type >= 0


func _try_create_cart(hex_index: int, peer_id: int) -> void:
	if hex_index not in HexBoard.MOUNTAIN_HEXES:
		action_help_label.text = "Carts can only be created on mountain hexes."
		return

	var faction_id := GameState.get_controlling_faction(hex_index)
	if faction_id < 0:
		action_help_label.text = "No faction controls that hex."
		return
	if not GameState.player_can_afford_action(peer_id, faction_id):
		action_help_label.text = "No actions left for %s." % Factions.name_for(faction_id)
		return

	GameState.submit_faction_action(hex_index, ActionSystem.Type.CREATE_CART)
	action_help_label.text = "Created a %s cart on hex %d." % [
		Factions.name_for(faction_id),
		hex_index,
	]
	_selected_source_hex = -1
	_update_action_highlights()


func _try_push(hex_index: int, peer_id: int) -> void:
	if _selected_source_hex < 0:
		var faction_id := GameState.get_controlling_faction(hex_index)
		if faction_id < 0:
			action_help_label.text = "No faction controls that hex."
			return
		if not GameState.player_can_afford_action(peer_id, faction_id):
			action_help_label.text = "No actions left for %s." % Factions.name_for(faction_id)
			return

		var max_cubes := _effective_cube_max(peer_id, faction_id, hex_index)
		if max_cubes <= 0:
			action_help_label.text = "No %s cubes or actions available to push." % Factions.name_for(
				faction_id
			)
			return

		_selected_source_hex = hex_index
		action_help_label.text = "Push %s: click an adjacent hex." % Factions.name_for(faction_id)
		_update_action_highlights()
		return

	if hex_index == _selected_source_hex:
		return
	if hex_index not in GameState.get_adjacent_hexes(_selected_source_hex):
		action_help_label.text = "Push target must be adjacent."
		return

	var faction_id := GameState.get_controlling_faction(_selected_source_hex)
	var max_cubes := _effective_cube_max(
		peer_id,
		faction_id,
		_selected_source_hex
	)
	var cube_count := mini(roundi(cube_count_spin.value), max_cubes)
	if cube_count <= 0:
		action_help_label.text = "No cubes or actions available to push."
		return

	GameState.submit_faction_action(
		_selected_source_hex,
		ActionSystem.Type.PUSH,
		hex_index,
		cube_count,
		move_cart_check.button_pressed
	)
	var cart_note := " + cart" if move_cart_check.button_pressed else ""
	action_help_label.text = "Pushed %d cube(s)%s." % [cube_count, cart_note]
	_selected_source_hex = -1
	_update_action_highlights()


func _try_pull(hex_index: int, peer_id: int) -> void:
	if _selected_source_hex < 0:
		var faction_id := GameState.get_controlling_faction(hex_index)
		if faction_id < 0:
			action_help_label.text = "No faction controls that hex."
			return
		if not GameState.player_can_afford_action(peer_id, faction_id):
			action_help_label.text = "No actions left for %s." % Factions.name_for(faction_id)
			return

		_selected_source_hex = hex_index
		action_help_label.text = "Pull %s: click an adjacent hex to pull from." % Factions.name_for(faction_id)
		_update_action_highlights()
		return

	if hex_index == _selected_source_hex:
		return
	if hex_index not in GameState.get_adjacent_hexes(_selected_source_hex):
		action_help_label.text = "Pull source must be adjacent."
		return

	var faction_id := GameState.get_controlling_faction(_selected_source_hex)
	var max_cubes := _effective_cube_max(peer_id, faction_id, hex_index)
	if max_cubes <= 0:
		action_help_label.text = "No %s cubes or actions available to pull." % Factions.name_for(
			faction_id
		)
		return

	var cube_count := mini(roundi(cube_count_spin.value), max_cubes)
	if cube_count <= 0:
		action_help_label.text = "No cubes or actions available to pull."
		return

	GameState.submit_faction_action(
		_selected_source_hex,
		ActionSystem.Type.PULL,
		hex_index,
		cube_count,
		move_cart_check.button_pressed
	)
	var cart_note := " + cart" if move_cart_check.button_pressed else ""
	action_help_label.text = "Pulled %d cube(s)%s." % [cube_count, cart_note]
	_selected_source_hex = -1
	_update_action_highlights()


func _setup_cube_count_spin() -> void:
	cube_count_spin.min_value = 1.0
	cube_count_spin.max_value = float(CUBE_MOVE_SPIN_MAX)
	cube_count_spin.value = clampf(cube_count_spin.value, 1.0, float(CUBE_MOVE_SPIN_MAX))


func _effective_cube_max(_peer_id: int, faction_id: int, hex_index: int) -> int:
	return GameState.get_faction_cubes_on_hex(hex_index, faction_id)


func _update_cube_count_visibility() -> void:
	var show_cubes := _selected_action_type in [
		ActionSystem.Type.PUSH,
		ActionSystem.Type.PULL,
	]
	cube_count_row.visible = show_cubes
	move_cart_check.visible = show_cubes


func _update_actions_left_big_display() -> void:
	var in_actions := GameState.current_phase == GameState.Phase.SPEND_ACTIONS
	actions_left_big_label.visible = in_actions
	if not in_actions:
		return

	var turn_peer := GameState.get_action_turn_peer_id()
	var total := GameState.get_total_actions_for_peer(turn_peer)
	actions_left_big_label.text = "%d actions left" % total


func _update_action_highlights() -> void:
	if _selected_source_hex < 0:
		board.clear_action_selection()
		return

	var targets: Array = GameState.get_adjacent_hexes(_selected_source_hex)
	board.set_action_selection(_selected_source_hex, targets)


func _update_action_button_styles() -> void:
	_style_toggle_button(push_button, _selected_action_type == ActionSystem.Type.PUSH)
	_style_toggle_button(pull_button, _selected_action_type == ActionSystem.Type.PULL)
	_style_toggle_button(cart_button, _selected_action_type == ActionSystem.Type.CREATE_CART)


func _style_toggle_button(button: Button, selected: bool) -> void:
	button.modulate = Color(1.0, 1.0, 0.75) if selected else Color.WHITE


func _update_action_help() -> void:
	if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
		return

	_update_cube_count_visibility()
	_update_actions_left_big_display()
	_on_action_history_changed(GameState.can_undo_action())


func _refresh_ui() -> void:
	var player_count := GameState.get_player_count() if NetworkManager.is_offline_debug() else multiplayer.get_peers().size() + 1
	if NetworkManager.is_offline_debug():
		status_label.text = "Offline debug | %d local players" % player_count
		var control_id := GameState.get_control_peer_id()
		var control_name: String = GameState.player_names.get(control_id, "Player %d" % control_id)
		control_peer_label.text = "Controlling: %s" % control_name
	elif NetworkManager.is_server():
		status_label.text = "Host | %d player(s) connected" % player_count
	else:
		status_label.text = "Client | %d player(s) connected" % player_count
	phase_label.text = "Phase: %s" % _phase_name(GameState.current_phase)
	_update_pegging_hud(GameState.pegging_total, GameState.pegging_turn_peer)
	influence_display.refresh()
	coins_label.text = _format_coins()
	crib_discards_label.text = _format_crib_discards()
	action_points_label.text = _format_action_points()
	faction_actions_label.text = _format_faction_actions()
	_update_actions_left_big_display()
	board.queue_redraw()


func _format_coins() -> String:
	if GameState.player_coins.is_empty():
		return "Coins: none yet"

	var lines: PackedStringArray = ["Coins (from pegging):"]
	for peer_id in GameState.player_coins.keys():
		var player_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
		lines.append("%s: %d" % [player_name, GameState.player_coins[peer_id]])

	return "\n".join(lines)


func _format_crib_discards() -> String:
	var peer_id := GameState.get_control_peer_id()
	var cards: Array = GameState.get_crib_discards_for_peer(peer_id)
	var show_phase := GameState.current_phase in [
		GameState.Phase.CUT_CARD,
		GameState.Phase.PEGGING,
		GameState.Phase.SHOW_HANDS,
		GameState.Phase.SHOP,
		GameState.Phase.SPEND_ACTIONS,
		GameState.Phase.RESOLVE_CRIB,
	]
	crib_discards_label.visible = show_phase and not cards.is_empty()
	if not crib_discards_label.visible:
		return ""

	var suit_names: PackedStringArray = []
	for card in cards:
		var faction_id := int(card.get("faction", Factions.from_suit(str(card.get("suit", "clubs")))))
		suit_names.append(Factions.name_for(faction_id))
	return "Your crib discards: %s" % ", ".join(suit_names)


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
			parts.append("%s %d" % [Factions.name_for(faction), RemixRules.faction_dict_value(tokens, faction)])
		lines.append("%s: %s" % [player_name, ", ".join(parts)])

	return "\n".join(lines)


func _update_pegging_hud(total: int, turn_peer: int) -> void:
	var in_pegging := GameState.current_phase == GameState.Phase.PEGGING
	pegging_count_label.visible = in_pegging
	pegging_turn_label.visible = in_pegging

	if not in_pegging:
		return

	pegging_count_label.text = "Count: %d / %d" % [total, PeggingRules.MAX_TOTAL]
	pegging_turn_label.text = "Turn: %s" % GameState.player_names.get(
		turn_peer,
		"Player %d" % turn_peer
	)


func _phase_name(phase: GameState.Phase) -> String:
	match phase:
		GameState.Phase.WAITING:
			return "Waiting for players"
		GameState.Phase.SETUP_MINI_CRIB:
			return "Mini crib setup"
		GameState.Phase.DEAL:
			return "Deal hands"
		GameState.Phase.DISCARD_TO_CRIB:
			return "Discard to crib"
		GameState.Phase.CUT_CARD:
			return "Cut card"
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
