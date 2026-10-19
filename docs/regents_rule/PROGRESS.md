# Regent's Rule — the build order, and where it stands

The owner's order (2026-10-18): **nail the skilling loop first** (gather, refine, smith), **then make the
combat really fun**. The design is `RULE_DESIGN.md` (§7.4 for the skilling loop's decisions); this file
says what is built, how to play it and how it is tested. Every game decision goes to Luke first.

## Step 1: woodcutting in the frontier glade (built 2026-10-18)

Play it: open the project and press Play (F5; the main scene is `game/regents/regents_game.tscn`). You
stand in the frontier glade with a **Bronze axe** in your bag (top right). Walk up to a tree:

- **Tap E**: chop it **AFK**. A log every 4 s (Tree), 6 s (Oak), 9 s (Yew); walk away (1 m) or tap E
  again to stop. Each log may fell the tree (1 in 4 for a Tree, 1 in 8 an Oak, 1 in 10 a Yew).
- **Hold E**: play a **round** of woodcutting's minigame, **branch dodge**, over the game: A / D (or
  the arrows, or a click on either side) chops from that side; a branch at your head on your side hits
  you. The round pays what AFK would have in its 10 s **x 1.25 x your score** (a poor round pays less
  than AFK: design #23), and finds the rare **Bird's nest** 1.3x as often.
- A felled tree falls over for everyone, is a **stump** for 30 s (Tree), 45 s (Oak) or 90 s (Yew), and
  grows back. Two players can chop one tree; either one's log can fell it.

The glade: 8 Trees by the spawn, 5 Oaks to the east, 4 Yews in the far west corner, with the Stylized
Nature MegaKit's trees (CommonTree, TallThick, TwistedTree), rocks, bushes, grass and flowers. It is an
ordinary scene: `game/regents/levels/frontier.tscn`. A tree is a `LevelPoint` of kind `tree` tagged with
its TreeDef's name; move one, add one, then press LevelInfo's **Bake For The Server** and publish.

The minigame alone: `game/regents/skilling/woodcutting/chop_lab.tscn` (F6), Tree / Oak / Yew buttons.

### What makes it
| Piece | Where |
|---|---|
| The trees and items (content, baked; the server compiles the same numbers in) | `game/regents/content/tree/`, `item/` (`TreeDef`, `ItemDef`); `server/build/regents.rs` |
| The minigame, a pure model the server replays | `ChopModel` (GDScript), `genre::regents::chop` (Rust), held to `shared/golden/regents/chop.json` made by a third version (`game/regents/tests/make_chop_golden.py`) |
| The server's half: trees from the level, `chop(tree, active)`, AFK ticks, a round's replay and pay | `server/src/game/regents.rs`; the pure rules (yield, rolls) in `server/src/genre/regents/mod.rs` |
| The player's half: tap or hold E, rounds, harvest news | `SkillingComponent` (on `game/regents/adventurer.tscn`) |
| A tree drawn: its look, falling, its stump, growing back | `TreeNodeComponent` (`skilling/woodcutting/tree_node.tscn`) |
| The prompt, the round over the game, "+3 Logs", the bag | `RegentsHud` |
| Chopping, shown on every client: the swing (UAL's TreeChopping as the set's `pose.chop`, `game/regents/anim/adventurer.tres`) and the Bronze axe in hand (a `HeldItem`, `skilling/woodcutting/axe.tscn`, its grips fitted in `axe_grip_preview.tscn`) | `SkillingLook` |
| The numbers tuned live (the Rules page) | `regents.active_yield_mult` 1.25, `active_rare_mult` 1.3, `chop_reach_m` 3, `afk_stop_moving_m` 1 |

Foundation pieces it rides on, unchanged: a genre challenge kind (`issue_genre_challenge`,
`resolve_challenge`: dealt with the server's seed, private to its player, consumed once), statuses with
timers (Felled), `InteractionComponent.interact_handler` (the genre claims E on trees),
`LocalInputComponent.hold_still` and `MouseCapture.hold_free` (a round over the game).

### Tested
- `server/tests/regents.rs`: the Rust twin plays every golden round; a submission is whole pairs or
  nothing; the content compiled in; the yield formula; rolls spread evenly and played rounds find rares
  more often.
- The `regents` unit suite (`-- --only=regents`): the GDScript twin plays every golden round; the trunk;
  every chop rule; a perfect player; a replay of tampered inputs; the minigame and the lab.
- `tests/integration_test.sh` (its `game/regents/tests/hooks/integration_genre.sh`): the glade's 17 trees
  planted from the level; the starter axe (once per character); too far, not a tree, a stump, no axe
  refused; a round submitted at once (before its presses could have happened), malformed, or from 10 m
  away pays nothing; a round played by a bot (`chop_bot_cli.gd`) is replayed and paid, once; a level
  change takes the trees away.
- `game/regents/tests/chop_playtest.sh`: two real clients at 150 ms: tap E (AFK logs come, walking away
  stops it), hold E (a round played with A and D while held still, paid by the server), a buddy chopping
  the same tree; the axe and the swing while chopping (AFK and in a round), gone when it stops, and the
  other player's swing drawn on each client.

### Left for later (named, not forgotten)
- **Gathering mastery** (XP and ranks, design #3) and what a better axe does (round speed): items and
  numbers exist, the progression does not.
- **The other tiers' minigames** (woodcutting 4-5 and 6: owner, 2026-10-18) and the other skills (mining,
  smelting, smithing: to design with Luke).
- **Effects and sound**: chips flying, a thud, the fall's crash, leaves. Greybox stumps.
- Chunked subscriptions (template 1.0, M18) are not needed yet: one glade.
