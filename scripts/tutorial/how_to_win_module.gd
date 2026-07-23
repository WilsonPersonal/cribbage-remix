class_name TutorialHowToWinModule
extends RefCounted


static func steps() -> Array:
	return [
		{
			"title": "How to Win",
			"body": (
				"This tutorial walks through the three factions, influence with those "
				+ "factions, how factions score, and how you win."
			),
			"target": "",
		},
		{
			"title": "Influence Track",
			"body": (
				"There are three factions: Clubs, Hearts, and Diamonds. Each colored dot is "
				+ "an influence you hold with a faction. Your goal is to have the most "
				+ "influence with the faction at the top of the scoreboard at the end of "
				+ "the game. In this example you have 2 influence with Hearts to your rival's "
				+ "1. You are in a great position if Hearts end as the highest scoring faction."
			),
			"target": "influence_track",
			"callout_side": "left",
		},
		{
			"title": "Faction Scores",
			"body": (
				"This is the scoreboard. The factions are ordered "
				+ "top to bottom, with the faction winning at the top."
			),
			"target": "score_legend",
			"callout_side": "below",
		},
		{
			"title": "Carts",
			"body": (
				"Factions score by creating a cart in the mountains and delivering them to "
				+ "the forest. We will cover actions in more depth in a future tutorial, but "
				+ "we will watch Hearts score now."
			),
			"target": "",
			"on_ok": "play_hearts_cart_demo",
		},
		{
			"title": "Recency Tiebreaker",
			"body": (
				"Both Hearts and Clubs are tied at 3 points, but the tiebreaker is who most "
				+ "recently scored. Since Hearts just scored, they are at the top of the "
				+ "scoreboard."
			),
			"target": "score_legend",
			"callout_side": "below",
		},
		{
			"title": "When the Game Ends",
			"body": (
				"The game ends after the round where the combined score reaches 7. You can "
				+ "see the current total here. Since the total just hit 7, the game will end."
			),
			"target": "score_total",
			"callout_side": "below",
		},
		{
			"title": "You Win!",
			"body": (
				"Hearts is the top faction. You have more Hearts influence than your rival, "
				+ "so you win the game."
			),
			"target": "influence_hearts",
			"callout_side": "left",
			"show_winner": true,
			"return_to_menu": true,
		},
	]
