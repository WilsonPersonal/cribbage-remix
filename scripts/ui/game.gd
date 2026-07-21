extends Control

const HUD_WIDTH_RATIO := 0.28
const MAIN_WIDTH_RATIO := 0.72
const SHOP_PANEL_WIDTH_RATIO := MAIN_WIDTH_RATIO / 3.0
const CARD_PANEL_HEIGHT := 200
const SHOP_PANEL_HEIGHT := 132
const CUBE_MOVE_SPIN_MAX := 5
const PANEL_BG_COLOR := Color(0.1, 0.12, 0.16, 0.92)

@onready var hud: PanelContainer = $HUD
@onready var shop_panel: PanelContainer = $ShopPanel
@onready var status_label: Label = $HUD/Margin/VBox/StatusLabel
@onready var phase_label: Label = $HUD/Margin/VBox/PhaseLabel
@onready var pegging_count_label: Label = $HUD/Margin/VBox/PeggingCountLabel
@onready var pegging_turn_label: Label = $HUD/Margin/VBox/PeggingTurnLabel
@onready var influence_display: VBoxContainer = $HUD/Margin/VBox/InfluenceDisplay
@onready var coins_label: Label = $HUD/Margin/VBox/CoinsLabel
@onready var crib_reminder_panel: VBoxContainer = $HUD/Margin/VBox/CribReminderPanel
@onready var crib_owner_label: Label = $HUD/Margin/VBox/CribReminderPanel/CribOwnerLabel
@onready var crib_discards_row: HBoxContainer = $HUD/Margin/VBox/CribReminderPanel/CribDiscardsRow
@onready var crib_discard_cubes = $HUD/Margin/VBox/CribReminderPanel/CribDiscardsRow/CribDiscardCubes
@onready var action_points_label: Label = $HUD/Margin/VBox/ActionPointsLabel
@onready var show_action_scoring_button: Button = $HUD/Margin/VBox/ShowActionScoringButton
@onready var action_scoring_panel: PanelContainer = $HUD/Margin/VBox/ActionScoringPanel
@onready var action_scoring_label: Label = $HUD/Margin/VBox/ActionScoringPanel/ActionScoringLabel
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
@onready var faction_buttons: HBoxContainer = $HUD/Margin/VBox/ActionPanel/FactionButtons
@onready var clubs_faction_button: Button = $HUD/Margin/VBox/ActionPanel/FactionButtons/ClubsFactionButton
@onready var hearts_faction_button: Button = $HUD/Margin/VBox/ActionPanel/FactionButtons/HeartsFactionButton
@onready var diamonds_faction_button: Button = $HUD/Margin/VBox/ActionPanel/FactionButtons/DiamondsFactionButton
@onready var action_buttons: HBoxContainer = $HUD/Margin/VBox/ActionPanel/ActionButtons
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
var _shop_jack_source_hex: int = -1


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
	GameState.shop_action_pending_updated.connect(_on_shop_action_pending_updated)
	GameState.crib_cube_anim_requested.connect(_on_crib_cube_anim_requested)
	GameState.action_cube_anim_requested.connect(_on_action_cube_anim_requested)
	GameState.action_cart_anim_requested.connect(_on_action_cart_anim_requested)
	GameState.lobby_updated.connect(_on_lobby_updated)
	GameState.show_hands_updated.connect(_on_show_hands_updated)
	GameState.crib_discards_updated.connect(_on_crib_discards_updated)
	GameState.round_context_updated.connect(_on_round_context_updated)
	GameState.cut_card_updated.connect(_on_cut_card_updated_for_scoring)
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
	show_action_scoring_button.pressed.connect(_on_show_action_scoring_pressed)
	board.hex_clicked.connect(_on_board_hex_clicked)

	push_button.pressed.connect(_on_push_pressed)
	pull_button.pressed.connect(_on_pull_pressed)
	cart_button.pressed.connect(_on_cart_pressed)
	undo_action_button.pressed.connect(_on_undo_action_pressed)
	clear_action_button.pressed.connect(_on_clear_action_pressed)
	clubs_faction_button.pressed.connect(func() -> void: _on_shop_faction_picked(Factions.Id.CLUBS))
	hearts_faction_button.pressed.connect(func() -> void: _on_shop_faction_picked(Factions.Id.HEARTS))
	diamonds_faction_button.pressed.connect(func() -> void: _on_shop_faction_picked(Factions.Id.DIAMONDS))

	if NetworkManager.is_offline_debug():
		offline_bar.visible = true
		GameState.setup_offline_session("Player 1", "Player 2")
		call_deferred("_auto_start_offline_round")
	else:
		offline_bar.visible = false
		call_deferred("_register_online_players")

	_apply_panel_style(hud)
	_apply_panel_style(shop_panel)
	_apply_panel_style(action_scoring_panel)
	hud.clip_contents = true
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
	_configure_hud_control_width(hud_content)


func _configure_hud_control_width(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			child.custom_minimum_size.x = 0
			if child is Label:
				child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if child.get_child_count() > 0:
			_configure_hud_control_width(child)
	influence_display.custom_minimum_size.x = 0


func _apply_layout() -> void:
	var main_right := MAIN_WIDTH_RATIO
	var card_height := float(CARD_PANEL_HEIGHT)
	var shop_height := float(SHOP_PANEL_HEIGHT)
	var in_actions := GameState.current_phase == GameState.Phase.SPEND_ACTIONS
	var board_top := shop_height if in_actions else 0.0

	shop_panel.visible = in_actions
	shop_panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	shop_panel.anchor_left = main_right - SHOP_PANEL_WIDTH_RATIO
	shop_panel.anchor_top = 0.0
	shop_panel.anchor_right = main_right
	shop_panel.anchor_bottom = 0.0
	shop_panel.offset_left = 0.0
	shop_panel.offset_top = 0.0
	shop_panel.offset_right = 0.0
	shop_panel.offset_bottom = shop_height
	shop_panel.z_index = 2

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
	board.offset_top = board_top
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


func _on_shop_action_pending_updated(pending: Dictionary) -> void:
	_shop_jack_source_hex = -1
	board.clear_action_selection()

	if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
		_update_shop_action_panel()
		return
	if not GameState.is_action_turn_for_control():
		_update_shop_action_panel()
		return

	if pending.is_empty():
		action_help_label.text = "Choose Push, Pull, or Cart, then click the map."
		_update_shop_action_panel()
		_update_shop_dominance_highlights()
		return

	var effect := str(pending.get("effect", Shop.EFFECT_QUEEN))
	match effect:
		Shop.EFFECT_JACK:
			if GameState.pending_shop_needs_faction_choice():
				action_help_label.text = "Jack (wild): choose a faction to push."
			else:
				var faction_id := GameState.get_pending_shop_deploy_faction()
				action_help_label.text = (
					"Jack: click a hex with a %s cube, then an adjacent hex."
					% Factions.name_for(faction_id)
				)
		Shop.EFFECT_KING:
			if GameState.pending_shop_needs_faction_choice():
				action_help_label.text = "King (wild): choose a faction to deploy."
			else:
				var faction_id := GameState.get_pending_shop_deploy_faction()
				action_help_label.text = (
					"King: click a hex to deploy 1 %s cube."
					% Factions.name_for(faction_id)
				)
		_:
			var faction_id := int(pending.get("faction_id", -1))
			if faction_id == Factions.Id.SPADES:
				action_help_label.text = (
					"Shop purchase: take a Push, Pull, or Cart action using any faction you control."
				)
			else:
				action_help_label.text = (
					"Shop purchase: take a %s Push, Pull, or Cart action on highlighted hexes."
					% Factions.name_for(faction_id)
				)
			_select_action(ActionSystem.Type.PUSH)

	_update_shop_action_panel()
	_update_shop_dominance_highlights()


func _on_action_turn_updated(_peer_id: int) -> void:
	_clear_action_selection()
	_update_action_phase_ui()
	_refresh_ui()
	if _selected_source_hex >= 0:
		_update_action_highlights()


func _on_board_updated(_board_state: Array, _faction_power: Dictionary) -> void:
	if _selected_source_hex >= 0:
		_update_action_highlights()
	_update_shop_dominance_highlights()


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


func _register_online_players() -> void:
	if NetworkManager.is_offline_debug():
		return

	var player_name := GameState.consume_pending_local_player_name()
	if NetworkManager.is_server():
		GameState.register_player(NetworkManager.get_local_peer_id(), player_name)
		for peer_id in multiplayer.get_peers():
			GameState.register_player(peer_id)
	else:
		GameState.submit_local_player_name(player_name)

	_refresh_ui()


func _on_lobby_updated() -> void:
	_refresh_ui()


func _on_show_hands_updated() -> void:
	_update_crib_reminder()
	_update_action_scoring_ui()


func _on_crib_discards_updated() -> void:
	_update_crib_reminder()


func _on_round_context_updated(_dealer_peer_id: int, _crib_owner_peer_id: int) -> void:
	_update_crib_reminder()


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
		_apply_hud_content_width()
		_apply_layout()
		_refresh_ui()
	else:
		status_label.text = "Failed to load debug save from %s" % GameState.DEBUG_SAVE_PATH


func _on_pegging_state_updated(_sequence: Array, total: int, turn_peer: int) -> void:
	_update_pegging_hud(total, turn_peer)


func _on_phase_changed(_phase: GameState.Phase) -> void:
	var in_actions := GameState.current_phase == GameState.Phase.SPEND_ACTIONS
	end_shop_button.visible = false
	shop_buttons.visible = false
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
	_update_crib_reminder()
	_update_action_scoring_ui()
	_apply_layout()
	_refresh_ui()


func _update_action_phase_ui() -> void:
	var in_actions := GameState.current_phase == GameState.Phase.SPEND_ACTIONS
	end_actions_button.visible = in_actions and GameState.is_action_turn_for_control()
	action_panel.visible = in_actions and GameState.is_action_turn_for_control()
	if in_actions:
		end_actions_button.text = "End My Actions"
	_update_shop_action_panel()


func _on_influence_updated(_influence: Dictionary) -> void:
	_refresh_ui()


func _on_coins_updated(_coins: Dictionary) -> void:
	_refresh_ui()


func _on_cut_card_updated_for_scoring(_card: Dictionary) -> void:
	_update_action_scoring_ui()
	if action_scoring_panel.visible:
		action_scoring_label.text = _format_action_scoring_breakdown(GameState.get_control_peer_id())


func _on_action_points_updated(_action_points: Dictionary) -> void:
	_refresh_ui()
	_update_action_scoring_ui()


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

	if GameState.has_pending_shop_action(GameState.get_control_peer_id()):
		var effect := GameState.get_pending_shop_effect()
		match effect:
			Shop.EFFECT_JACK:
				_try_shop_jack_push(hex_index)
				return
			Shop.EFFECT_KING:
				_try_shop_king_deploy(hex_index)
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
	_shop_jack_source_hex = -1
	_update_action_button_styles()
	_update_cube_count_visibility()
	board.clear_action_selection()
	board.clear_crib_selection()
	_update_action_help()
	_update_shop_action_panel()
	_update_shop_dominance_highlights()


func _action_selection_ready() -> bool:
	return _selected_action_type >= 0


func _action_blocked_message(peer_id: int, faction_id: int) -> String:
	if GameState.is_faction_influence_locked(peer_id, faction_id):
		return (
			"An opponent leads %s influence by %d+ — buy a Queen to act."
			% [Factions.name_for(faction_id), RemixRules.INFLUENCE_ACTION_LOCK_GAP]
		)
	return "No actions left for %s." % Factions.name_for(faction_id)


func _try_create_cart(hex_index: int, peer_id: int) -> void:
	if hex_index not in HexBoard.MOUNTAIN_HEXES:
		action_help_label.text = "Carts can only be created on mountain hexes."
		return

	var faction_id := GameState.get_controlling_faction(hex_index)
	if faction_id < 0:
		action_help_label.text = "No faction controls that hex."
		return
	if not GameState.player_can_afford_action(peer_id, faction_id):
		action_help_label.text = _action_blocked_message(peer_id, faction_id)
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
			action_help_label.text = _action_blocked_message(peer_id, faction_id)
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
			action_help_label.text = _action_blocked_message(peer_id, faction_id)
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


func _update_shop_dominance_highlights() -> void:
	if GameState.current_phase != GameState.Phase.SPEND_ACTIONS:
		board.clear_shop_dominance_highlights()
		return
	if not GameState.is_action_turn_for_control():
		board.clear_shop_dominance_highlights()
		return

	var pending := GameState.get_pending_shop_action()
	if pending.is_empty():
		board.clear_shop_dominance_highlights()
		return

	var effect := str(pending.get("effect", Shop.EFFECT_QUEEN))
	match effect:
		Shop.EFFECT_QUEEN:
			var faction_id := int(pending.get("faction_id", -1))
			if faction_id == Factions.Id.SPADES:
				board.clear_shop_dominance_highlights()
			else:
				board.set_shop_dominance_highlights(
					GameState.get_faction_dominance_hexes(faction_id),
					faction_id
				)
		Shop.EFFECT_JACK:
			if GameState.pending_shop_needs_faction_choice():
				board.clear_shop_dominance_highlights()
				return
			if _shop_jack_source_hex >= 0:
				board.clear_shop_dominance_highlights()
				return
			var jack_faction := GameState.get_pending_shop_deploy_faction()
			if jack_faction < 0:
				board.clear_shop_dominance_highlights()
			else:
				board.set_shop_dominance_highlights(
					GameState.get_hexes_with_faction_cubes(jack_faction),
					jack_faction
				)
		Shop.EFFECT_KING:
			board.clear_shop_dominance_highlights()
		_:
			board.clear_shop_dominance_highlights()


func _update_shop_action_panel() -> void:
	var in_actions := GameState.current_phase == GameState.Phase.SPEND_ACTIONS
	var on_turn := GameState.is_action_turn_for_control()
	if not in_actions or not on_turn:
		faction_buttons.visible = false
		return

	action_help_label.visible = true
	var pending := GameState.get_pending_shop_action()
	var effect := GameState.get_pending_shop_effect() if not pending.is_empty() else ""
	var shop_special := effect in [Shop.EFFECT_JACK, Shop.EFFECT_KING]

	action_buttons.visible = not shop_special
	clear_action_button.visible = not shop_special
	cube_count_row.visible = (
		not shop_special
		and _selected_action_type in [ActionSystem.Type.PUSH, ActionSystem.Type.PULL]
	)
	faction_buttons.visible = shop_special and GameState.pending_shop_needs_faction_choice()
	_update_shop_faction_button_states()
	_on_action_history_changed(GameState.can_undo_action())


func _update_shop_faction_button_states() -> void:
	if not faction_buttons.visible:
		return

	var effect := GameState.get_pending_shop_effect()
	var faction_buttons_map := {
		Factions.Id.CLUBS: clubs_faction_button,
		Factions.Id.HEARTS: hearts_faction_button,
		Factions.Id.DIAMONDS: diamonds_faction_button,
	}
	for faction_id in Factions.ALL:
		var button: Button = faction_buttons_map.get(faction_id)
		if button == null:
			continue
		var enabled := true
		if effect == Shop.EFFECT_JACK:
			enabled = GameState.faction_has_cubes_on_board(faction_id)
		button.disabled = not enabled


func _on_shop_faction_picked(faction_id: int) -> void:
	if not GameState.is_action_turn_for_control():
		return
	if not GameState.pending_shop_needs_faction_choice():
		return
	GameState.submit_shop_deploy_faction(faction_id)


func _try_shop_jack_push(hex_index: int) -> void:
	if GameState.pending_shop_needs_faction_choice():
		action_help_label.text = "Choose a faction first."
		return

	var faction_id := GameState.get_pending_shop_deploy_faction()
	if faction_id < 0:
		return
	if not GameState.player_can_act_with_faction(GameState.get_action_turn_peer_id(), faction_id):
		action_help_label.text = _action_blocked_message(
			GameState.get_action_turn_peer_id(),
			faction_id
		)
		return

	if _shop_jack_source_hex < 0:
		if GameState.get_faction_cubes_on_hex(hex_index, faction_id) <= 0:
			action_help_label.text = "That hex has no %s cubes." % Factions.name_for(faction_id)
			return
		_shop_jack_source_hex = hex_index
		action_help_label.text = "Jack: click an adjacent hex to push into."
		_update_shop_jack_target_highlights()
		return

	if hex_index == _shop_jack_source_hex:
		return
	if hex_index not in GameState.get_adjacent_hexes(_shop_jack_source_hex):
		action_help_label.text = "Push target must be adjacent."
		return
	if GameState.get_faction_cubes_on_hex(_shop_jack_source_hex, faction_id) <= 0:
		action_help_label.text = "No %s cubes left on that hex." % Factions.name_for(faction_id)
		return

	var space := HexBoard.MAX_CUBES_PER_FACTION_PER_HEX - GameState.get_faction_cubes_on_hex(
		hex_index,
		faction_id
	)
	if space <= 0:
		action_help_label.text = "That hex has no room for another %s cube." % Factions.name_for(
			faction_id
		)
		return

	GameState.submit_shop_jack_push(_shop_jack_source_hex, hex_index)
	action_help_label.text = "Pushed 1 %s cube." % Factions.name_for(faction_id)
	_shop_jack_source_hex = -1
	board.clear_action_selection()
	_update_shop_dominance_highlights()


func _update_shop_jack_target_highlights() -> void:
	if _shop_jack_source_hex < 0:
		board.clear_action_selection()
		return

	var faction_id := GameState.get_pending_shop_deploy_faction()
	var targets: Array = []
	for adjacent_hex in GameState.get_adjacent_hexes(_shop_jack_source_hex):
		var adjacent_index := int(adjacent_hex)
		if GameState.get_faction_cubes_on_hex(adjacent_index, faction_id) < HexBoard.MAX_CUBES_PER_FACTION_PER_HEX:
			targets.append(adjacent_index)

	board.set_action_selection(_shop_jack_source_hex, targets)
	_update_shop_dominance_highlights()


func _try_shop_king_deploy(hex_index: int) -> void:
	if GameState.pending_shop_needs_faction_choice():
		action_help_label.text = "Choose a faction first."
		return

	var faction_id := GameState.get_pending_shop_deploy_faction()
	if faction_id < 0:
		return
	if not GameState.player_can_act_with_faction(GameState.get_action_turn_peer_id(), faction_id):
		action_help_label.text = _action_blocked_message(
			GameState.get_action_turn_peer_id(),
			faction_id
		)
		return

	if hex_index not in GameState.get_hexes_with_deploy_space(faction_id):
		action_help_label.text = "That hex has no room for another %s cube." % Factions.name_for(
			faction_id
		)
		return

	GameState.submit_shop_king_deploy(hex_index)
	action_help_label.text = "Deployed 1 %s cube." % Factions.name_for(faction_id)
	_update_shop_dominance_highlights()


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
	var player_count := GameState.get_player_count()
	if NetworkManager.is_offline_debug():
		status_label.text = "Offline debug | %d local players" % player_count
		var control_id := GameState.get_control_peer_id()
		var control_name: String = GameState.player_names.get(control_id, "Player %d" % control_id)
		control_peer_label.text = "Controlling: %s" % control_name
	elif GameState.current_phase == GameState.Phase.WAITING:
		if NetworkManager.is_server():
			if player_count < RemixRules.MIN_PLAYERS:
				status_label.text = "Host | waiting for players (%d/%d)" % [
					player_count,
					RemixRules.MIN_PLAYERS,
				]
			else:
				status_label.text = "Host | %d players connected" % player_count
		else:
			if player_count < RemixRules.MIN_PLAYERS:
				status_label.text = "Connected | waiting for players (%d/%d)" % [
					player_count,
					RemixRules.MIN_PLAYERS,
				]
			else:
				status_label.text = "Connected | %d players ready" % player_count
	elif NetworkManager.is_server():
		status_label.text = "Host | %d player(s) connected" % player_count
	else:
		status_label.text = "Client | %d player(s) connected" % player_count
	phase_label.text = "Phase: %s" % _phase_name(GameState.current_phase)
	_update_pegging_hud(GameState.pegging_total, GameState.pegging_turn_peer)
	influence_display.refresh()
	coins_label.text = _format_coins()
	_update_crib_reminder()
	_update_action_scoring_ui()
	action_points_label.text = _format_action_points()
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


func _update_crib_reminder() -> void:
	var show_phase := GameState.current_phase in [
		GameState.Phase.DISCARD_TO_CRIB,
		GameState.Phase.CUT_CARD,
		GameState.Phase.PEGGING,
		GameState.Phase.SHOW_HANDS,
		GameState.Phase.SHOP,
		GameState.Phase.SPEND_ACTIONS,
		GameState.Phase.RESOLVE_CRIB,
	]
	var crib_owner := GameState.get_crib_owner_peer_id()
	var has_crib_owner := crib_owner != 0
	crib_reminder_panel.visible = show_phase and has_crib_owner
	if not crib_reminder_panel.visible:
		return

	var owner_name: String = GameState.player_names.get(crib_owner, "Player %d" % crib_owner)
	var control_peer := GameState.get_control_peer_id()
	if crib_owner == control_peer:
		crib_owner_label.text = "Crib belongs to you."
	else:
		crib_owner_label.text = "Crib belongs to %s." % owner_name

	var cards: Array = GameState.get_crib_discards_for_peer(control_peer)
	if cards.is_empty():
		crib_discards_row.visible = false
	else:
		crib_discards_row.visible = true
		var faction_ids: Array = []
		for card in cards:
			faction_ids.append(Factions.from_suit(str(card.get("suit", "clubs"))))
		crib_discard_cubes.set_factions(faction_ids)


func _update_action_scoring_ui() -> void:
	var show_phase := GameState.current_phase in [
		GameState.Phase.SHOW_HANDS,
		GameState.Phase.SHOP,
		GameState.Phase.SPEND_ACTIONS,
		GameState.Phase.RESOLVE_CRIB,
	]
	var peer_id := GameState.get_control_peer_id()
	var has_show_hand := not GameState.get_show_hand_for_peer(peer_id).is_empty()
	show_action_scoring_button.visible = show_phase and has_show_hand
	if not show_action_scoring_button.visible:
		action_scoring_panel.visible = false
		show_action_scoring_button.text = "Show action scoring"
	elif action_scoring_panel.visible:
		action_scoring_label.text = _format_action_scoring_breakdown(peer_id)


func _format_action_scoring_breakdown(peer_id: int) -> String:
	var hand: Array = GameState.get_show_hand_for_peer(peer_id)
	if hand.is_empty():
		return "No show-hand cards recorded yet."
	var breakdown := CribbageScoring.explain_actions_from_cards(hand, GameState.cut_card)
	return CribbageScoring.format_action_breakdown(breakdown)


func _on_show_action_scoring_pressed() -> void:
	action_scoring_panel.visible = not action_scoring_panel.visible
	show_action_scoring_button.text = (
		"Hide action scoring" if action_scoring_panel.visible else "Show action scoring"
	)
	if action_scoring_panel.visible:
		action_scoring_label.text = _format_action_scoring_breakdown(GameState.get_control_peer_id())


func _format_action_points() -> String:
	if GameState.action_points.is_empty():
		return "Actions: none yet"

	var lines: PackedStringArray = ["General actions (from show hands):"]
	for peer_id in GameState.action_points.keys():
		var player_name: String = GameState.player_names.get(peer_id, "Player %d" % peer_id)
		lines.append("%s: %d" % [player_name, GameState.action_points[peer_id]])

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
