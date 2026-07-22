# Cribbage Remix

Online multiplayer strategy game for **Godot 4** — cribbage hands fuel faction maneuvering on a 9-hex map.

## Core loop

```
Deal -> Discard to crib -> Cut starter -> Pegging (coins)
  -> Show hands (actions) -> Shop -> Spend actions -> Resolve crib -> Next round
```

Game ends after the round where **combined faction score first reaches 7**.

## Cards

- **30-card deck**: ranks **1–10** in three suits (no face cards)
- Suits map to factions:
  - **Clubs** (black)
  - **Hearts** (red)
  - **Diamonds** (blue)

## Earning resources

| Phase | Reward |
|---|---|
| **Show hands** | 1 action per pair, 15, or run of 3+; clamped to **2–7** actions (excess → coins, shortfall → pay coins) |
| **Pegging** | Coins (pair, 15, 31, go, etc.) — **not** actions |

## Shop

During the **Shop** phase, spend **3 coins** to buy a **faction-specific action** (Clubs, Hearts, or Diamonds). These tokens can be spent instead of a general action when commanding that faction.

## Map actions

A faction can only act on a hex where it has **strictly more cubes than any other faction**.

Each action costs **1** general action or **1 matching faction token**:

| Action | Effect |
|---|---|
| **Push** | Move cubes **and** carts (if forward) from this hex to an adjacent hex |
| **Pull** | Bring cubes **and** carts (if forward) from adjacent hex to this hex |
| **Create Cart** | Turn 1 cube into a cart (west hexes only) |

**Carts** follow a fixed route from each mountain hex to its goal forest and may not leave that path. For example, a cart from the mountain labeled 1/10 must travel through hex 7, then hex 4, before reaching its forest. Carts score when they reach the goal forest.

## Crib resolution

Always **2 accept / 2 reject** across all 4 crib cards.

| Choice | Effect |
|---|---|
| **Accept** (2 cards) | +1 influence; remove that faction's cube from **any hex** into your supply |
| **Reject** (2 cards) | Place a cube on the board |

**Reject placement rules** (by card rank):

- Rank **1–9** → must go on the hex with that number (hexes numbered 1–9)
- Rank **10** → may go on **any** hex

## Winning

1. Dominant faction = most cubes on the board
2. Winner = most influence in that faction

## Quick start

1. Open `project.godot` in Godot 4.4+.
2. Press **F5** to run.
3. Pick a mode on the main menu:
   - **Offline Debug** — one window, hot-seat both players (best for solo testing)
   - **Host / Join** — online multiplayer on port `7777`

### Offline debug

1. Click **Offline Debug (2 players, 1 window)**.
2. Click **Start Round**.
3. Play as the active player; use **Switch Player** for the other seat.
4. The game auto-switches during discard, pegging turns, and crib resolution.

### Online multiplayer

Use **Debug → Run Multiple Instances**, then host/join on `127.0.0.1`.

## Project structure

```
autoload/           NetworkManager, GameState
scripts/cribbage/   deck, scoring, rules
scripts/game/       factions, hex board, shop, actions
scripts/ui/         menu, HUD, hex board view
```

## API highlights

- `GameState.grant_actions_from_cards()` — show-hand actions
- `GameState.grant_pegging_coins()` — pegging coin events
- `GameState.request_shop_purchase(faction_id)` — buy faction action for 3 coins
- `GameState.request_faction_action()` — Push / Pull / Create Cart
- `GameState.request_crib_resolution(choices)` — 4 entries, 2 accept + 2 reject
