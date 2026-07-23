class_name TutorialActionsAndInfluenceModule
extends RefCounted


static func steps() -> Array:
	return [
		{
			"title": "Actions from Your Hand",
			"body": (
				"When you show your hand, each pair, 15, and run of three or more earns "
				+ "one action. You can click this to see how each hand scores. Actions are "
				+ "spent during the action phase to move cubes on the map."
			),
			"target": "show_action_scoring_button",
			"callout_side": "left",
			"ui_mode": "show_hands",
		},
		{
			"title": "Dominance",
			"body": (
				"A faction can only act on a hex where it has more cubes than any other "
				+ "faction. This is called dominance."
			),
			"target": "dominance_hex",
			"callout_side": "right",
			"ui_mode": "board",
			"board_highlight": "dominance",
		},
		{
			"title": "Push",
			"body": (
				"Push moves cubes from a hex you control into an adjacent hex. You can move "
				+ "a cart along with the cubes."
			),
			"target": "push_button",
			"callout_side": "left",
			"ui_mode": "actions",
			"board_highlight": "push",
		},
		{
			"title": "Pull",
			"body": (
				"Pull brings cubes from an adjacent hex into a hex you control. You can pull "
				+ "a cart along with the cubes."
			),
			"target": "pull_button",
			"callout_side": "left",
			"ui_mode": "actions",
			"board_highlight": "pull",
		},
		{
			"title": "Create Cart",
			"body": (
				"Create Cart spends a cube on a mountain hex you control to spawn a cart. "
				+ "The cart follows the route toward its goal forest."
			),
			"target": "cart_button",
			"callout_side": "left",
			"ui_mode": "actions",
			"board_highlight": "cart_spawn",
		},
		{
			"title": "Accepting from the Crib",
			"body": (
				"When you accept a crib card, you gain one influence with that card's "
				+ "faction. Click a hex that has that faction's cube to remove it into your "
				+ "supply."
			),
			"target": "crib_accept_button",
			"callout_side": "above",
			"ui_mode": "crib_accept",
			"board_highlight": "crib_accept",
		},
		{
			"title": "Rejecting from the Crib",
			"body": (
				"When you reject a crib card, you place cubes on the board. Ranks 1–9 must "
				+ "go on the matching hex label; rank 10 can go on any hex."
			),
			"target": "crib_reject_button",
			"callout_side": "above",
			"ui_mode": "crib_reject",
			"board_highlight": "crib_reject",
			"return_to_menu": true,
		},
	]
