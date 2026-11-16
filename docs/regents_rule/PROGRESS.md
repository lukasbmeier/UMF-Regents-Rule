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

The minigame alone: `game/regents/skilling/skilling_lab.tscn` (F6), Tree / Oak / Yew buttons.

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
- `game/regents/tests/skilling_playtest.sh`: two real clients at 150 ms: tap E (AFK logs come, walking away
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

## Step 2: the skilling chain (built 2026-10-19)

Owner decisions (2026-10-19): mining is **crack the rock**, smelting is **bellows then pour**, smithing is
**shape to the outline**; the whole chain before the next playtest. Trees became general **gathering
nodes** (trees, rocks, later herbs and fishing spots: one content type that names its skill, its tool and
its minigame), so a tier band's own minigame is a node naming another round.

Play it: press Play. A Bronze axe AND a Bronze pickaxe in your bag; the skills and their ranks under it.
- **Mining**: the copper rocks south-east of the spawn (5), the iron rocks south-west (4, mining rank 2).
  Tap E: AFK. Hold E: **crack the rock**: a weak point glows on the rock face; click it before it fades
  (the ring shrinks); a click on solid rock jars the pick. The rock crumbles to rubble when worked out.
- **The camp** by the spawn: a **furnace**, an **anvil**, a **workbench**. At one, **Q** picks what to make
  (the prompt says what it takes and how many you have); **tap E** makes it AFK until the bag runs out;
  **hold E** plays its round, where it has one:
  - furnace: Copper bar, Iron bar (1 ore each). **Bellows then pour**: Space or click pumps the bellows,
    keep the needle in the green band (it drifts and narrows; red is burning); then hold to pour the
    crucible and let go at the white line (past the brim, it spills).
  - anvil: Copper rivets (1 bar makes 4, AFK only); Iron axe head (2 iron bars). **Shape to the outline**:
    click a column of the hot bar to beat it down (some spreads to its neighbors) until it matches the
    white outline; it cools as you work (right click or R reheats). The head's **quality** is your score
    (AFK makes a 35 % one).
  - workbench: Handle (2 logs), **Iron axe** (the head, a handle, 2 rivets; as good as its head). AFK.
- **The Iron axe**: tier 2, 85 % of the time (a better quality takes up to a tenth more off), so faster
  AFK and a faster swing in branch dodge; the **Yew** needs it (and woodcutting rank 4). You hold whatever
  you work with: the bronze or the iron axe, the pickaxe, the smith's hammer.
- **Mastery**: every item gives XP in its skill; ranks 1-10 from each skill's curve (`SkillDef`); ranks
  gate nodes (Oak: woodcutting 2, Yew 4, Iron rock: mining 2) and recipes, and take 3 % off the work per
  rank. "+12 Mining XP", "Mining rank 2!".

All four minigames in one place: `game/regents/skilling/skilling_lab.tscn` (F6), a button per round.

### What makes it
| Piece | Where |
|---|---|
| The content: skills, nodes, recipes, stations, items (baked; the server compiles the same numbers in) | `game/regents/content/{skill,node,recipe,station,item}/` (`SkillDef`, `NodeDef`, `RecipeDef`, `StationDef`, `ItemDef`); `server/build/regents.rs` |
| Four pure minigame models, each a GDScript class and its Rust twin, held to golden files a third (Python) version made | `skilling/{woodcutting,mining,smelting,smithing}/*_model.gd`; `server/src/genre/regents/{chop,crack,smelt,shape}.rs`; `game/regents/tests/make_{chop_golden,skill_goldens}.py` |
| The minigames in one place (kinds, challenge kinds, a faster tool's swing, the UIs) | `SkillMinigames`; each UI a `SkillMinigame` |
| The server: nodes and stations from the level, `gather`/`craft`/`work_stop`, AFK ticks, a round's replay and pay, quality, mastery | `server/src/game/regents.rs`; the pure rules (ranks, speed, yields, rolls) in `server/src/genre/regents/mod.rs` |
| The player: tap or hold E, Q at a station, rounds, results, XP | `SkillingComponent` |
| Nodes and stations, drawn (a tree falls, a rock crumbles, ore shows; a furnace glows) | `NodeComponent`, `StationComponent` (`skilling/node.tscn`, `station.tscn`) |
| Working, shown on every client: each skill's pose (UAL's TreeChopping, Mining, Push, Interact) and the tool in the hand (grips fitted in each tool's `*_grip_preview.tscn`) | `SkillingLook` |
| The prompt, the round over the game, the notices, the bag (with quality), the skills | `RegentsHud` |

### Tested
- `server/tests/regents.rs` (11): every twin against its golden file; submissions; the chain compiled in; ranks,
  speed, quality, payloads; yields; rolls; every minigame scores a real round and refuses what is not one.
- The `regents` unit suite (86): the content and the chain's links; every model against its golden; chop
  rules; every minigame UI played to its end (the replay agrees); the registry; the looks; the lab.
- `tests/integration_test.sh` (its hook): the glade's 26 nodes and 3 stations; refusals (reach, rank, inputs,
  the wrong station, a worked-out node, no tool); a round of each of the four minigames played by a bot
  (`game/regents/tests/skill_bot_cli.gd`) and replayed, paid, with XP and (the head) the score as quality; a
  better axe's speed in the round's payload; a round early, malformed or from afar pays nothing.
- `game/regents/tests/skilling_playtest.sh`: two real clients at 150 ms: the whole chain through keys and
  clicks, from a log to an Iron axe in the hand; and a buddy who sees the chopper swing.

### Left for later (named, not forgotten)
- **Tool durability and repair** (owner, 2026-10-18: the material sink), **gear XP** (the handle's trait came in step 3).
- Sound and effects for the new work (sparks at the anvil, the furnace's roar, rock chips in the world).
- Mining tiers 4-5 and 6's own minigames; Herbalism; Fishing as a skill.
- The furnace is a greybox stone with the pack's bellows; stumps and rubble are greybox.

## Step 3: the first playtest's notes (2026-10-19)
The owner played the chain once and asked for these; each is his call (RULE_DESIGN §7.4, fifth pass).

- **No press is ever dropped.** A press during a swing is HELD (the latest one) and lands the moment the
  swing ends, in branch dodge, crack the rock and shape to the outline; a press while staggered (a branch
  hit, a jarred pick) is still lost, as the penalty. In all three models, their Rust twins and the goldens.
- **The bellows take every press**: mash faster to heat it (`pump_ms` is 40 ms: it only stops a macro),
  ease off to cool it. **The pour waits** `pour_ready_ms` (600) after the heat, so mashing never tilts the
  crucible, and **tilting again tops it up** (no single pour).
- **Mining is FOLLOW THE SEAM**: a faint crack outline runs across the rock; strike its glowing next notch,
  then the next; open it end to end and the rock splits and the next seam shows (even seams top to bottom,
  odd ones left to right). Off the seam the pick jars. Harder rocks: tighter notches, a wilder seam
  (`bend_pm`) and less of it shown ahead (`reveal_ahead`; iron shows 2).
- **Two ores to a bar** (copper and iron), set in each recipe's `input_qty`.
- **Oak and yew handles** (workbench, crafting rank 2 and 4): a handle's wood is the tool's trait, Tinkers'-
  style: oak +15 quality, yew a 10 % faster swing. A recipe's `part_slot` takes any item of its kind
  (`ItemDef.part_tag`), so the one Iron axe recipe takes a plain, an oak or a yew handle: Q at the
  workbench steps through them (the ones in your bag). The tool remembers its handle (`{"q":N,"h":item}`).
- **Crafting keeps pace with gathering** (the anti-glassblowing goal), four ways, every number a hot rule:
  - *the work in it*: a batch pays its own XP plus `craft_work_share_pct` (60 %) of the XP its inputs took
    (`work_xp`: gathered, its node's XP; made, its recipe's and its inputs', the cheapest way);
  - *variety*: repeating one recipe wears it stale (`variety_drain_pm_per_min` 60), XP falling to
    `variety_floor_pct` (50 %); time away brings it back (`variety_recover_pm_per_min` 30);
  - *first make*: the first batch a character ever makes of a recipe pays `first_make_mult` (5) x more;
  - *work orders*: the ORDER BOARD at camp has three orders (each about `order_minutes` of a recipe's AFK
    work, paying `order_bonus_pct` of that XP again), replaced every `order_rotate_min` (20); each player
    fills each once (E at the board, Q for the next order).
  The prompt says what a batch pays, a first make, how fresh a recipe is.
- **The recipe bench** (`game/regents/workbench/recipe_workbench.tscn`, from the Content dock): a recipe at
  its station, its sheet, an hour of it AFK and played (XP fresh and worn stale, what it eats), the raw
  materials and gathering minutes behind one batch, and an hour of it against an hour of gathering its
  inputs. Tune `input_qty`, `xp`, `afk_ms` in the Inspector and read the effect.

New server pieces: `craft_with` (a part chosen; `craft` unchanged), `fill_order`, tables `recipe_log`,
`work_order`, `order_filled`; tests: 13 Rust (handles, craft XP, variety), the unit suite, the
integration hook (ratios, first make, refusals of a wrong part, the board end to end), the playtest (the
seam, an oak handle carved and an Iron axe assembled with it).

## Step 4: combat, the first slice (2026-10-19)
The owner's calls (RULE_DESIGN §7.4): hybrid action combat, the weapon is the kit, Tab targeting with a
ring for reference, a training dummy first, then wild creatures. In this slice:

- **Wield a weapon from the bag** (I opens the bag panel; Wield / Put away on each weapon). The bronze and
  iron axes are weapons as well as tools (the axe kit); the **Iron sword** is smithed like the axe: a blade
  shaped at the anvil (smithing rank 2, its own outline), assembled at the workbench with any handle.
- **The keys** (owner, 2026-10-19): LMB tap the light combo (the sword's three slashes, the axe's two
  chops; each tap the next inside `combo_window_ms`), LMB held the heavy, RMB held block (a hit within
  `regents.parry_ms` of raising it is parried: none, and the attacker staggered; else `block_damage_pct`),
  Ctrl the dodge roll (the Rolling status: nothing hits you, and its burst carries you; slow-walk is now
  Alt), Q E R F the kit's skills at mastery 1/3/6/9 (Lunge, Cleave on Q so far), Tab the next target in
  front (a ring under it, its health at the top), Esc drops it. In stance (a target, or a swing in the
  last 5 s) Q and E are skills; out of it E works stations and Q picks there, as before.
- **Aimed, judged**: every swing is a foundation ability the world's referee judges along the way the body
  faces (the body faces the camera in stance). The server says what a hit does: the ability's damage x
  the weapon (`weapon_damage_pct`) x its quality (up to +20 %) x the mastery (3 % a rank). Every hit pays
  mastery XP in the kit's skill (Swordsmanship, Axemanship; `combat_xp_per_damage`).
- **The training dummies** at camp (two, on `dummy` points): hit them, the numbers float up; they never
  fall and are whole again `dummy_reset_s` after the last hit; they pay `dummy_xp_pct` of the XP.
- Content: `KitDef` (`content/kit/`), the abilities (`content/ability/`), statuses Rolling, Blocking,
  Staggered, the dummy (`content/character/dummy.tres`); every number above a hot rule or the content's.

**A foundation change came with it** (DECISIONS #254, made in the template too, commit 7334ba6 there,
not yet shipped): a player is the foundation's kind 0, and the ability hooks went only to the genre that
claims a kind, so our players' swings never reached us. Now every genre hears a foundation kind's.

Tested: Rust 14 (kits, the damage formula, the combo's order), the unit suite (the combo's steps, stance,
the bar, the keys, the content), the integration hook (wield refusals, a kit's ability with the wrong
weapon or out of the combo's order, two chops judged on the dummy with their exact damage and XP, the
roll, the block, the dummy whole again), and `game/regents/tests/combat_playtest.sh`: a real client with
the world's real referee wields from the bag panel, Tabs onto a dummy, chops, combos, holds a heavy, rolls,
blocks, lets go.

Known, for the next slice: the roll's burst begins when its status arrives (a round trip after Ctrl);
a predicted dash needs the foundation's own tests to stop assuming kind 0 moves by the default
(template). An entity a referee drives that has a `blocker_size` pushes itself away (found with the
dummy, which so has none: you can walk through it): a foundation bug to fix in the template. Creatures'
hits on players reach our block and parry now (#254), but no creature hits yet.
Next: wild creatures (Quaternius' Ultimate Animated Animals), the yew bow, the sword's E/R/F, the station
UI the owner asked for in place of Q at stations.

## Step 5: combat timing, and two fixes (2026-10-19)
After the owner's first combat playtest ("I can spam attack... the attack should be synced to the
animation"; the visuals must match the server). His four calls, each enforced by the server and played
the same by the client:

- **Animation-locked, with a buffer.** A swing lands at its wind-up and holds its fighter for its CLIP'S
  LENGTH (`KitDef.lock_ms`: the clip in `timing_set` at its speed, baked for the server). A press while
  it holds you is queued (the latest wins; it lapses after the combo's window) and fires the moment it
  may: the combo's next light step from just after the hit (`chain_ms`), anything else once the lock is
  over. Mashing swings one swing per animation, never faster, and no press is lost. Change a clip's
  speed in the animation set and the swing's timing follows, on both sides.
- **Committed swings.** From a swing's start until just after it lands (`regents.swing_hold_ms`) you walk
  (the server's Swinging status bounds you at 30 %), so the whole swing plays; in the recovery you move
  freely, and running cuts the swing's tail (the adventurer's animation cancels above 1.6 m/s).
- **A roll cancels.** In a swing's wind-up the roll cancels it: it never lands, on screen or on the
  server (`swing.cancelled`). In its recovery the roll ends it.
- **Heavies flinch lights.** A heavy hit in a light swing's wind-up cancels it and flinches its fighter
  (`regents.flinch_ms`, the Flinched status); a heavy's own wind-up has armor; lights never interrupt;
  a parry still staggers. (Needs a second fighter to see: creatures, or a duel.)
- Server: the `swing` table, `game/regents.rs` `may_fight` / `fought` / `hit`; `regents.swing_slack_ms`
  forgives the network. Light and heavy cooldowns never outlast their locks.

Fixed: every swing played Interact (the foundation plays an ability's clip under `ability.<id>`; the set
had other names: now `ability.40001`... and the light swings slowed to readable speeds); the lag near
the workbench (the station prompt re-read every content file dozens of times a frame: content is now
looked up once, `RegentsContent`, and a recipe's work-XP worked out once).

**The roll is a predicted dash** (owner, 2026-10-19). The first roll was a server status that burst you
forward: right locally, but at 150 ms the server checked each frame a round trip late, found the burst
over and corrected the player back (the combat playtest caught it). Now Ctrl is the foundation's DASH
(the adventurer's movement profile: a 16 m/s impulse, 0.9 s apart), moved by the client the moment
it is pressed and bounded by the server like any movement; the Dodge roll ability still gives the
i-frames (Rolling) and cancels a swing. Ctrl is the `dash` action (the foundation binds Q when a game has
not; Q is a skill here). A status's speed scales the dash too, so the Swinging status forbids sprint and
jump but no longer caps speed (a roll in a wind-up must be a full roll); the committed walk is the
client's. A cheating client could run while swinging: closing that is a foundation tweak (a status's
speed not scaling the dash). For the dash the template's own integration test learned to take the
player's kind as the game made it (DECISIONS #255, made in the template too).

**Combat polish after the second combat playtest** (owner, 2026-10-19). Swings play in place (the
clips' root travel is taken out, template #256) and play through to their hit however you move; no
swing starts in the air or mid-roll (a press waits for the ground or the roll's end; the server refuses
both). The roll plays its Roll whole, facing the way it goes, 1.5 s apart; Ctrl dashes only when the roll
is taken, and a correction no longer forgets the dash's cooldown (template #264). The server bounds a
swing's walk (Swinging: a quarter of a run) now that a status leaves the dash whole and the dash counts
only when one happens (template #256, #258). Grips: one grip for all per body, spot fixes, a typed Hold,
Spin buttons, written on the scene's save (template #257, #259-#263).

## Step 6: the first enemies, a skeleton camp (owner, 2026-10-19)

Two skeletons from the Bestiary pack (Quaternius, `game/regents/art/monsters/`): the **Skeleton
warrior** (Skeleton_B, a sword: the sword kit) and the **Skeleton axeman** (Skeleton_A, an axe: the axe
kit). Their weapons are part of their models, and they play the adventurer's animations (the same
skeleton). Three stand at a camp east of the spawn (the frontier's `Foes` points, x 33-37).

- **Attack on sight.** A foe notices a player within `notice_m` (10 m) in sight, chases (it runs at
  4.2 m/s, a little slower than you), stops at `reach_m` and fights with its kit exactly as a player
  does: the same swings, wind-ups, Swinging status, blocks, parries, flinches, judged by the same
  referee. Every third swing is its heavy; a combo ends with a breath (`rest_ms`): your opening. Past
  `leash_m` (25 m) from home it gives up and walks back, deaf to everyone until it is home.
- **Slain** (the Slain status: nothing moves, acts or is hit): your mastery XP for every hit (its
  `xp_pct`), a roll of its loot into your bag (placeholder: copper ore 60 %, iron ore 30 %, a gem 4 %),
  a line on the HUD. Its body lies `regents.foe_corpse_s` (6 s), and it comes back on its point
  `regents.foe_respawn_s` (60 s) after it fell. Both hot rules.
- **You, slain**, get up at the spawn, whole, `regents.player_respawn_s` (5 s) later. A placeholder
  until a death penalty is decided.

**Adding a foe is content, no code**: a character (`content/character/`: its model, the animation set,
a movement profile, `brain = "regents/foe"`, a kind 103-119), listed in `genre.tres`'s entity
definitions; a FoeDef (`content/foe/`: its key, character, kit, health, damage %, XP %, behavior, loot);
level points of kind = its key (a LevelPoint in the level scene, then bake the level). Bake the content
and republish. A foe whose weapon is not part of its model needs a held item (not done yet).

Server: `foe` and `foe_kill` tables, `game/regents.rs` `populate_foes` / `fell` / `tick_foes` /
`get_up`; the brain is `sidecar/npc/brains/regents/foe.gd` (the referee drives it). Proven: native tests
(the camp's content, loot rolls), the integration suite (spawn, its hit at its damage, a kill, the loot
in the bag, XP, the body gone, the respawn, a slain player up at the spawn, a level change clears them),
the combat playtest at 150 ms with a real referee (it notices, comes, swings its sword and hits, your
chop hits back, past its leash it walks home).

Not yet: a foe bench (workbench); death penalty; foes that block or roll; the axeman's own playtest; a
loot table worth having; foes in groups pulling together.

## Step 7: windows instead of text (owner, 2026-10-20)

"Dedicated UI preferred", matching the Escape menu, its look changeable later for a fantasy theme. The
foundation now has a UI kit (template DECISIONS #265): one style file (`UiStyle`: colors, sizes, fonts)
draws every control in the game, and a window, an item slot and row pieces to build screens with. To
reskin Regent's Rule later: a `UiStyle` `.tres` and the project setting `umf/ui/style` (handbook, "The
game's look").

- **Stations: tap E opens the station's window** (Q no longer picks). Left, what can be made there (a
  recipe with a handle once per handle in your bag); right, the one picked: what it makes, what it takes
  (have / need, green or red), what it pays (first make, freshness) and the buttons: MAKE (AFK; the window
  stays open, says it is working and offers STOP) and PLAY A ROUND (when the recipe has one). At the
  order board, each order and HAND THEM OVER. Hold E at a station still plays a round of what was picked
  there last. Walk away and it closes.
- **I: the bag** (right): every stack as a slot; click one for what it is (a tool's work and tier, a
  weapon's kit, damage and moves, a handle's trait, its quality and handle) and WIELD / PUT AWAY.
- **K: skills** (left): each skill, its rank, a bar to the next.
- The always-on bag and skills text is gone; the screen says "I: bag  K: skills".

Code: `game/regents/ui/` (`RegentsStationWindow`, `RegentsBagWindow`, `RegentsSkillsWindow`), opened by
`RegentsHud`; `SkillingComponent.station_opened` (a tap at a station). Proven: the skilling playtest
works the anvil and the workbench through the window (MAKE, STOP, picking the axe head for a round, the
iron axe with the oak handle) and, with `SHOTS=<dir>`, plays in a window and saves pictures of them; the
combat playtest wields the axe from the bag window.

**Health comes back out of the fight** (2026-10-20, a placeholder until you decide food or potions):
`regents.regen_delay_s` (8 s) after the last hit that landed on you, `regents.regen_pct_per_s` (4 %) of your
health a second, until you are whole. Foes too: one led off and left heals as it walks home. Both are
hot rules. Proven: native test (the step), the combat playtest (after the skeleton fight your health
climbs back; without the tick it does not).

**The foe bench** (`game/regents/workbench/foe_workbench.tscn`, opened from a FoeDef in the Content Dock):
the foe's model playing its swings, and its fight worked out from the content: its swings' damage, its
damage a second over its whole rhythm, how long it takes to kill a player, the XP a kill pays; how long
each weapon in the game takes to kill it (rank 1, its light combo); what a kill drops on average. Amber
when nothing kills it in a minute or it kills a player in under 3 s. Today: the warrior (120 health) dies
in 4.6 s to the iron axe, 5.6 s to the iron sword, 6.5 s to the bronze axe, and kills you in 14 s; the
axeman (150) in 5.7 / 7.0 / 8.1 s, you in 12 s. (The sword's light combo is slower to kill than the
axe's: a balance question.)

## Step 8: the yew bow (owner, 2026-10-20)

Your answers: with a Tab target the arrow auto-aims, with a hit chance the server rolls, lower with distance
and against a moving (or rolling) target; with no target it flies where you look (bow skills come later as
skill shots). The draw scales the damage (you were torn: look again after the playtest). Best at range,
worse but usable up close. You walk while drawn. A real arrow that arcs. Crafted arrows, some recovered
from the kill. Made at the workbench; shooting trains a new mastery, Archery.

- **Hold LMB: draw.** The server's Drawing status (107): you walk (a quarter of your speed), no sprint
  or jump; the arms draw back, then hold aim (a pose on the upper body only, so the legs keep walking).
  A bar under the crosshair fills over the bow's `draw_full_ms` (800 ms). **Let go: loose.** A release
  under 120 ms lets the draw go instead. **RMB** lets it go; a **roll** does too. Not in the air, not
  mid-roll or mid-swing, not with no arrows ("No arrows").
- **The shot** (`loose_arrow`): the server takes an arrow from the bag and works out the draw it saw
  (at least `regents.draw_min_power_pct` 30 %). With a target in `regents.bow_range_m` (40 m), it rolls the
  hit: `hit_near_pct` 95 % at `hit_near_m` 8 m down to `hit_far_pct` 55 % at `hit_far_m` 40 m, minus
  `hit_moving_pct` 15 if the target is moving. A hit is aimed to land on the target (a ballistic arc at a
  speed from `arrow_speed_min` 20 to `arrow_speed_max` 50 m/s by the draw); a miss is aimed at a point
  beside it. With no target it flies along your look. The HUD shows the chance as you aim.
- **The arrow is a real body** (BodyDef 40001), flown by the world's referee like the fishing bobber,
  nose into the wind (`ArrowFlight`). What it hits, the referee reports, and the server deals the damage:
  the shot's 14 × the draw × the arrow's `ammo_damage_pct` × the mastery, at `point_blank_pct` 60 % if it
  hits inside `point_blank_m` 4 m. Archery XP on a hit. An arrow that hits a foe stays in it; when the foe
  falls, `arrow_recover_pct` 40 % of those come back to the bag of whoever shot them.
- **Crafting** (workbench, Crafting): the yew bow from 2 yew logs; 15 arrow shafts from 1 log; 15 copper
  arrows from 15 shafts and 1 copper bar.

Every number above is a hot rule (`rules/regents.tres`) or on the content (`kit/bow.tres`,
`ability/bow_loose.tres`, `item/copper_arrows.tres`). Code: server `game/regents.rs` (`draw_bow`,
`loose_arrow`, `arrow_hit`), the pure maths in `genre/regents/mod.rs` (`draw_power`, `hit_chance_pct`,
`aim_velocity`, `miss_point`, `arrow_damage`); client `CombatComponent` (a kit with `draws`).

**Its grip is a placeholder.** It hangs well at your side, but in the aim pose the bow lies flat across
the hands: `combat/weapons/yew_bow_grip_preview.tscn`, pick `pose.bow_aim` (and `pose.bow_draw`), stand
it upright in the left fist.

Proven: native tests (the draw's power, the hit chance, a hit's arc landing on the target, a miss
landing beside it, point blank); the integration (a draw, a loose at a skeleton ten meters off with the
server's roll, the arrow taken, the referee's hit for 14, Archery XP, point blank under 60 %, the killing
arrow and one of three back, free aim flying east, no arrows no draw); the combat playtest with a real
referee (draw, walk, the arms, an arrow that flies and hits the dummy for 14, free aim hits, RMB lets
go). Negative: with the referee's contacts ignored, the playtest's hit checks fail.

Left for later: bow skills (skill shots), more arrow kinds, an arrow model on the string while drawn, a
quiver slot (arrows come from the bag), the draw-scales-damage question.

## Step 9: grades and Power (owner, 2026-10-20, `LOOT_AND_STYLES.md` order item 1)

- **Grades are bands of quality.** A made item keeps its 0-1000 quality; **Common** under
  `regents.grade_fine_q` (400), **Fine** from it, **Masterwork** from `regents.grade_masterwork_q` (800).
  Both are hot rules. A material has no grade.
- **The grade is a color**: a slot's edge (two wide; a picked slot keeps it) and the item's name. The
  colors are the game's style (`UiStyle.grade_colors`: gray, green, gold), so a fantasy reskin recolors
  them (template DECISIONS #267).
- **Names**: "Fine iron axe", "Masterwork iron sword"; a Common one keeps its plain name.
- **Power**: the one number to compare, the weapon's damage in percent of its kit's with its quality in:
  an iron weapon 100 to 120, a bronze one 70 to 84; arrows their own percent. It is exactly the hit
  the server deals. Tools show their tier and work instead (a node asks for a tier).
- **The bag** shows it all: the graded name, "Masterwork · quality 85% · oak handle", and
  "Power 117 (+6 on your Fine iron sword)" in green (red when worse) against the weapon you wield. A
  crafted item's notice is in its grade's color.
- **Tier dominates**, checked: an item's check in the Content Dock (and the bake) refuses a weapon whose
  best reaches the next tier's worst in its kit.
- Fixed on the way: a made item with a handle showed a garbage quality in the bag (`"q":850,"h":40016`
  read as 85040016); quality is now read as JSON.

Code: `content/item_grade.gd` (`RegentsGrade`), the bag window, the HUD's notice. Proven: the regents
suite (bands, names, Power against the server's damage rule, tier dominance and a bronze axe at 90 %
caught, the bag window's slots, name color and Power lines); negative: Power ignoring quality and the
bag ignoring grades fail six checks.

## Step 10: loot tables and personal rolls (owner, 2026-10-20, `LOOT_AND_STYLES.md` order item 2)

Loot is now foundation content (template DECISIONS #268), so every game gets it.
- **A loot table** (`content/loot_table/`, a `LootTableDef`) is lines; a line is an item or another table,
  with a chance and a from..to count. **Each** tables roll every line on its own (adding a line changes no
  other's odds); **one-of** tables pick one line by the shares you type (10 / 20 / 30 / 40), the rest is
  nothing, past 100 refused. A line can be marked **pity**: a player who keeps missing it gets likelier
  each kill (doubled after its usual run of kills, certain at five times it; `foundation.loot_pity_ramp_x`
  and `_cap_x`). The Content Dock shows what one roll gives on average.
- **Personal rolls**: every player who did at least `foundation.loot_share_min_pct` (5 %) of the recent
  damage (hits within `foundation.loot_share_forget_s`, 60 s) gets their own roll, with their own pity. A
  foe that heals whole forgets who hurt it.
- **The skeletons** drop from one shared table, **Skeleton camp** (copper ore 60 %, iron ore 30 %, an uncut
  gem 4 % with pity). FoeDef's old loot lists are gone; the foe bench reads the table.

## Step 11: items on the ground (order item 3)

Template DECISIONS #269. A kill's drops fall where it died as **sacks**, a ring under each glowing in its
grade's color and its name above. Each is **yours alone for a minute** (nobody else is even sent it),
then **anyone's for a minute**, then gone (`foundation.ground_owner_s`, `ground_public_s`). **Walk over a
sack to pick it up.** The bag has a **Drop** button (not on what you wield): yours a minute, then anyone's:
a way to hand a friend something. Lines marked `to_bag` (none yet; currency later) skip the ground.

## Step 12: the Staff (order item 4)

Your design (§4-5), on a generic resource (template DECISIONS #270: `ResourceDef`, `ResourceComponent`).
- **Mana, the Staff's only**: 100, filling 10 a second out of a fight and 4 in one (a fight: 5 s after
  the last spell). Wielding a staff gives it; changing weapons keeps it as it is.
- **LMB: Bolt** (9, no mana): at your Tab target the server aims it and rolls the hit like the bow's (ranged
  can miss); with none it flies where you look. A real missile the referee flies.
- **Q: Fireball** (Sorcery 1, 25 mana, 7 s): a 0.6 s cast you can walk through; 20 to what it hits, 40 %
  to anything within 3 m, and it burns (3 a second for 3 s).
- **E: Frost Ring** (Sorcery 3, 30 mana, 14 s): a 1 s cast that roots you (moving or rolling lets it go,
  nothing paid); a 4 m circle where the crosshair meets the ground (within 20 m), filling on the ground,
  landing a second later: 6 and Slowed (40 % slower, no sprint) for 3 s.
- **R: Blink** (Sorcery 6, 20 mana, 15 s): 8 m the way you look, at once, onto ground you can stand on.
- **F: Gale** (Sorcery 9, 35 mana, 20 s): everything within 8 m and 45° of your look takes 6 and is thrown
  back.
- **No global cooldown**: each spell its own. A press during a cast or a clip is held and fires the
  moment it ends (as a swing's). Mana is paid when a spell lands. The HUD shows mana, each spell's cost and
  cooldown, and a cast bar.
- Every spell is content (`content/spell/`, a `SpellDef`: one of four kinds, bolt, area, blink or cone,
  with its cost, cast time, missile, splash, burn, radius, delay, cone and status), so a new spell of a kind
  is a new file. `regents.mana_cost_pct` scales every cost live.
- **Getting one**: the workbench makes a **yew staff** from a yew log and an uncut gem (a skeleton's rare
  drop), or an admin grant (item 40023). To try the higher spells now: `grant_xp <your entity> 40009 5000`
  (admin) puts Sorcery at 9.
- **Its grip is a placeholder**: held fine at your side, tilted in the casting pose
  (`combat/weapons/yew_staff_grip_preview.tscn`, `pose.spell_cast`).

Proven: native tests (the staff's content, a long cast roots, the cone and the blink); the regents suite
(the content, the client's casting: a free instant Bolt, Fireball refused without mana, cast with it, each
spell on its own cooldown, the bar landing, a cooldown refused; the ground ring filling); the integration
(mana on wielding; a Bolt for 9 and Sorcery XP; its cooldown; Fireball not paid until it lands, one cast at
a time, 25 paid, 20 and 8 splash, the burn; Frost Ring too far, a cast let go costing nothing, its circle
landing a second later and Slowed; Blink 8 m; too little mana refused; Gale's push and its damage at
Sorcery 9). Negative: the client ignoring a cooldown fails its check.

Left for later: the server-side cast queue (today the client holds a press and sends it when the cast
ends; the server queuing it would hide the round trip), others seeing your release animation (they see
your cast pose and the missile), reagents, the spellbook and utility spells, summons.

## Step 13: icons from the models (order item 5)

Template DECISIONS #271. An item's bag picture is drawn from its 3D model (its held scene, or its
`world_model`: the arrows'), along the diagonal, lit, on a transparent square: the axes, the sword, the bow,
the staff, the pickaxe and the arrows have theirs (`game/regents/icons/`). Materials without a model
(logs, ore, bars, the gem) keep their initials until they have a model or a hand-drawn `icon_picture`.
**After changing or adding an item with a model**, draw them again: `godot --path . res://tools/render_icons.tscn`
in a window, then `godot --headless --path . --import`.

**The design doc's slice order (§10) is done**: grades and Power, loot tables, ground items, the Staff,
icons. Next in its list: trait atoms and the v1 trait pools (with handle traits' downsides), meta
telemetry, salvage and components, reagents, the teleport spell, the Pareto check, enchanting, summons.

## Step 14: the playtest of the loot, the Staff and the bow (owner, 2026-10-20)

What you found, and what was done:
- **The skeletons never attacked.** The world's referee (which drives every foe) had been started by
  `tools\host.cmd` the evening before, before the skeletons existed: it had no definition for them, so no
  brain drove them. And Play never started a fresh one: your editor was not an admin of the database (its
  log said so), and a referee was already online. Now (template DECISIONS #272): **a referee stops once
  the project is newer than it** (a publish, a bake, changed code) and Play or `host.cmd` starts a fresh
  one; and **`tools\publish.cmd` makes your editor an admin** of the game's database, so Play starts the
  referee itself.
- **"Player 30" blinking in and out**: the database's own CLI (the host's feedback watcher polled as the
  admin, and any query connects as it), given a player entity like anyone. **A nameless admin is a tool and
  is never shown** now.
- **The bow lost to melee by far**: its full draw is **30** (was 14): about 21 a second at range against
  the iron axe's 26 up close, 18 at point blank. In `content/ability/bow_loose.tres` if it wants tuning.
- **E at the workbench cast a skill**: E works what is in front of you unless you are fighting (a target
  picked); a key with no skill on it is never taken.
- **Attacking with no target**: **what your swing, arrow or spell hits becomes your target** (on the hit,
  so the bow and the staff still aim freely with none).
- **The UI lagged**: the station window rebuilt every button twice a second (losing clicks, jumping the
  list's scroll); it now redraws only when something it shows changed. The station prompt by a bench was
  worked out every frame; four times a second now.
- **Burning showed no fire** (found on the way: it listened in the wrong place): the fire is on what
  burns, from its row.

Proven: the combat playtest (what an arrow hits becomes the target; without it, that check fails); the
skilling playtest (in stance with a staff, no target, E at the workbench opens its window; the open window
is not redrawn while idle); the regents suite (a burning row lights a fire, its end puts it out); the
template's suites (a sidecar whose project is newer is stale; the CLI is never seen, a named admin and a
nameless player are).

## Step 15: the friends' playtest fixes, chat, and traits (2026-10-20 to 21)

**From the friends' playtest:**
- **Dropping** puts a stack 1.4 m in front of you, and your own fresh drop is left alone until you have
  walked away from it (it came straight back "like a magnet").
- **Chat** (template DECISIONS #273): **Enter** to write, **Enter** to send, **Esc** to cancel. You stand
  still while you type. Lines show bottom left and over the speaker's head.
- **No friendly fire or PvP**: a swing, an arrow or a spell only hurts what it may (foes hurt players;
  players hurt foes).
- **Dying mid-chop** no longer leaves the chop's pose playing (Fin's "head nod"): dying stops the work.
- **Jumping near an object** no longer double-jumps (template DECISIONS #274).
- **The furnace's bellows** heat 50 a press (were 45).

**TRAITS** (template DECISIONS #275; `LOOT_AND_STYLES.md` §2 and §6). A trait changes how an item plays,
never its Power, and every one trades. They are content: `game/regents/content/trait/`. Each says in words
what it gives and what it costs, and the bag's card shows them under the item.
- **Handles give the tool its trait, whatever its grade** (your call): oak gives **Steady** (nodes 20% less
  likely to run out, work 5% slower), yew gives **Springy** (work 5% faster, nodes 10% likelier to run
  out). Toned to the early game as you asked; the materials deep-dive may rework them. **The oak no longer
  adds +15 quality**: quality is Power, and a trait never touches Power.
- **The v1 pools**: Balanced, Heavy, Brutal (the *target's* health, your call), Thirsting (weapons);
  Swift Draw, Hunter's (bows); Gentle, Lucky, Prospector's (tools). Prospector's costs "work 15% slower"
  instead of "base yield -1" (a success yields one, so -1 would be nothing).
- **Waiting**: Keen (needs crits and Bleeding), Padded and Warded (need armor), Reaching (needs the
  referee to judge each swing at the wielder's own reach: a new side table). **Drops roll traits by grade**
  once drops roll a grade (the loot line's grade distribution is not built; nothing drops gear yet).
- **Trying one**: `set_item_traits <bag row> [<trait ids>]` (dev tools on) gives an item exactly those.
  `foundation.trait_strength_pct` on the Rules page turns every trait up, down or off live.

What each trait word does in this game (an atom's `what`, and `on`):

| `what` | where it acts | on |
|---|---|---|
| damage | a hit's damage (swing, arrow, spell), with the target's health and family for conditions | basic, combo_last, heavy, skill |
| recovery | a swing's lock after its wind-up (the client predicts the same) | basic, heavy, skill |
| stagger | a chance in % that a hit Staggers what it hits (and stops its cast) | heavy, combo_last |
| heal_on_hit | % of a hit's damage back as health (not off a dummy) | basic |
| healing_received | out-of-fight regeneration | |
| draw_time | the bow's full draw (the client's draw bar too) | |
| projectile_speed | an arrow's speed | |
| work_time | a tool's speed in rounds and AFK | |
| depletion | the chance a node runs out per item | |
| extra_yield | a chance in % of one more per item | |
| rare_chance | % added to a node's rare find | |

A foe's family is its `FoeDef.family` (the skeletons: undead). An item's tags (what a trait may be on):
a tool is "tool" and its tag; a weapon is "weapon", its kit, and "melee", "bow" or "staff".

Proven: the template's `traits` tests (native and client: the same numbers on both sides; breaking them
fails them); Regent's Rule's native tests (the handles' traits; a tool's speed with them; a tool made before
traits gets its handle's; every trait trades; what an item and an action are; Balanced's lock 825 for 900,
Heavy's 975; Swift Draw 640 for 800; Brutal, Hunter's; depletion and rare chances through the tool's traits);
the regents suite (the pools; the client's twins give the server's numbers; scaling the whole lock fails it);
the integration (refusals; Balanced's lock read from the server's swing; Brutal's 6.93 off a dummy above
30 %; Heavy staggers the dummy; the dial at 0 gives the kit's own lock); the skilling playtest (an iron axe
made with an oak handle carries Steady, and its card in the bag shows it: the `bag_traits` shot).

## Step 16: telemetry for looking back, and a polish round (2026-10-21)

**TELEMETRY** (Luke: "ideally live telemetry exists for looking back ... full historical data in
positions, skills, and all other data points"; he chose **both** a chronicle on disk and in-database
rollups, **a place every 5 s**, and **a local dashboard**). The foundation's part is template DECISIONS
#276, shipped here by hand (`git merge template/main`: Luke's grip edits keep `ship_template.sh` out).
- **To look back: double-click `tools\telemetry.cmd`** on the machine that hosts. A page opens in your
  browser with the foundation's panels (players online, where they were as a heatmap, who played, frame
  rate, ping, chat, feedback, what was kept) and **Regent's Rule's own**: the meta (each weapon's share of
  an hour's damage to foes), meta alarms, mastery XP gained by skill and over time, mastery by player,
  foes slain, abilities used by players (kit share), what was gathered and made, and what was dropped.
  Pick the last hour, day, week or all, and everyone or one player.
- **What records it**: `tools\host.cmd` while hosting, pressing Play in the editor (your own playtests),
  or the page itself when nothing else does. Everything lands in `build/telemetry/regents-rule.sqlite`,
  kept forever.
- **The meta in the database** (`LOOT_AND_STYLES.md` §7.5): every player hit on a foe (never a training
  dummy) adds to a private `meta_tally` (period, activity "overworld", weapon type, hits, damage: a hit's whole damage, as XP counts it). When
  its period ends (`regents.meta_period_s`, an hour; shortening the rule closes open tallies sooner), it
  becomes `meta_share` rows: each weapon's share of the damage, and an **alarm** when one passes
  `regents.meta_alarm_pct` (45 %) in a period of at least `regents.meta_alarm_min_hits` (50) hits. An
  alarm is a `META ALARM` warning in the server's log and a row on the page. `regents.meta_keep_days` (14)
  is how long the database keeps them; the chronicle keeps every one.
- The panels are data: `shared/regents/telemetry.json` (SQL over the chronicle's file; the HANDBOOK's
  "Looking back at everything" explains adding one). `meta_tally`, `hurt`, `spell_cooldown` and
  `combat_state` are not recorded (they change on every hit or swing); the dummy's `last_hit_at` alone
  is no line.

**THE POLISH ROUND** (Luke: "more visually telling and easy to read"):
- **Health bar** bottom left (under the chat), with the Staff's **mana** under it while it is wielded and
  a thin **roll** bar that refills over the roll's 1.5 s cooldown (gray while it does; its tooltip says
  how long).
- **A work bar** under the prompt while you work AFK: it fills to the next piece (bar, batch, ore, log),
  piece after piece, from the server's own `next_at`. The station's window shows the same bar.
- **Make 1, Make X, Make all** in the station's window (X is the number box beside it; 5 to start).
  Make X stops itself after that many batches (the client asks `work_stop` after the last), Make all
  works until the bag runs out (what Make did before). The prompt and the window say "Making 2 of 5".
- **The minimap**, top right, OSRS style: round, turning with the camera so ahead is up, N on the rim, the
  level drawn once from straight above when it loads, dots for players (white), foes (yellow), trees
  (green), rocks (gray), stations (blue) and the dummy (orange), your arrow in the middle. The mouse
  wheel over it zooms (15 to 90 m) while the cursor is free (a window open, or Alt). Open for iterations: click-to-walk, a world map, quest markers.
- **Hits flash**: whatever is hit lights up white for a moment, you light up red, and the screen's edge
  pulses red (more for a bigger hit); a hit taken while blocking flashes steel blue and says "Blocked";
  a stagger (your parry, a Heavy trait) flashes gold and says "Staggered". On top of the numbers and the
  shake that were there.

**Tested**: native `regents` (the meta's period, shares and alarm; each weapon type's skill); the
integration hook (a chop on a foe tallies one axe hit of 2 damage; the dummy never counts; the period
closes into one share: axe, 1 hit, 100 %, an alarm); the template's `telemetry_test.sh` (21 checks on a
real server); the regents suite's polish checks (the minimap's sums and colors, the work's progress and
Make X counting, the flashes, the bars; flipping the map's turn fails two, losing the block flash one); the
skilling playtest (Make X of 1 makes exactly one batch of rivets and stops by itself, the work bar fills,
then Make all uses the rest).

**Left for later**: trait share and time-to-kill by foe as panels (the design's §7.5 "same rollup"); the
minimap's click-to-walk and a recapture when trees fall; an activity other than "overworld" (lairs,
dungeons, duels once they exist); the meta alarm on screen in game for an admin.

**After Luke's first play of step 16 (same day)**:
- **The hit reaction no longer loops** (template DECISIONS #277). Flinched and Staggered hold `react.hit`
  as a looping pose, and the builder made a clip loop by changing the clip itself, which every node shares:
  after the first flinch anywhere, every hit reaction played for ever, through death. A loop is now the
  node's own. Proven by the template's `animation` and `animation_scene` suites (putting the old way back
  fails four checks, one a body stuck in its hit reaction while dead).
- **Everything you see stops you** (`game/regents/solid.gd`, `RegentsSolid`): a convex hull per mesh of
  the model as drawn. Rocks (copper and iron) block across their whole shape (Rock_Medium_1 is 3.2 m wide:
  the old 0.75 m cylinder let you into it), stations across every piece (the anvil, the workbench and the
  order board are pieces with no box), trees at their trunk. The level's props: `SolidProps` in
  `frontier.tscn` (`RegentsSolidProps`) makes every model under `Decor` whose file starts with `Rock_` or
  `Bush_` solid; grass, flowers, ferns, pebbles and mushrooms are walked through. Add a prefix there for
  more.
- **The ore on the rocks, by hand**: `game/regents/skilling/mining/ore/<rock model>_ore.tscn`, one per rock
  model (Rock_Medium_1, Rock_Medium_2, Rock_Big_1: copper and iron use them). **Open one, move, turn or
  size the nuggets (`Ore1`..`Ore5`; add or delete some), save**: every rock of that model, copper or iron,
  shows its ore so (gray in the scene, the ore's color in the game). They start snapped onto the surface,
  so none floats. A new rock model: run `make_ore_layouts.tscn` (headless) for its starting layout; with
  none, nuggets are snapped onto the surface at runtime (`RegentsOreSpots`).
- **The skeletons face the way they fight**: the same Quaternius rig as the adventurer, now turned the
  same (`visual_yaw_deg = 180` on both definitions); they were drawn backwards while their swings went
  forwards.
- The skilling playtest's chat check failed headless since step 15 (no chat box without a display): the
  chopper now gets its box as the buddy does.

Tested: regents suite 2391/0 (hulls where the mesh is drawn; every copper and iron rock model solid across
its shape, its nuggets where its layout puts them, rubble not solid; with no layout each nugget lies on
the surface; a tree's trunk; each station wherever it is drawn; a level's rock solid and its grass not;
the skeletons turned as the adventurer; breaking the hulls, the layouts or the props list fails its
checks); skilling playtest 62/0 + 7/0; combat playtest 50/0; content bake 18/0. Not seen yet by Luke:
the collisions, the ore and the skeletons in play.

## Step 17: the material table (MATERIALS.md step 1, 2026-10-23)

Luke's materials deep-dive (`MATERIALS.md`, his calls in `GAME.md`) starts here: **materials are a
generated table**. Nothing a player sees changes in this step: today's chain is re-expressed as the
table's cells, with every id kept, and the baked `item.json` and `recipe.json` are byte for byte as before.

- **Two new content types**: `MaterialDef` (`content/material/`: copper, iron, plain wood, oak, yew; each
  its tier, the Power and tool speed it gives as a core, the trait it gives as a handle, what it is
  gathered as) and `PatternDef` (`content/pattern/`: bar, axe head, sword blade, handle, axe, sword; each
  what is made, its station and skill, and its PARTS, `PartSlot`: the material's raw form, this
  material's cell of another pattern, any material's (the player's pick at the station), or a fixed item).
  A pattern lists as many slots as it needs; one is its CORE.
- **The cells are ordinary items and recipes** (`content/item/`, `content/recipe/`), marked: an item's
  `material` and `pattern` (the group "In the material table"), a recipe's `from_table`. The nine cells
  today: copper and iron bars, the iron axe head and sword blade, the iron axe and sword, the plain, oak
  and yew handles. Copper is a hole in the head, blade, axe and sword columns (`not_made_of`) until step 2.
  The bronze starters, rivets, arrows, the bow and the staff stay written by hand.
- **Make the table** (`MaterialTable`): a button on every material and pattern in the Inspector, or
  `godot --headless --path . -s res://game/regents/tools/make_material_table.gd` (`-- --check` only says).
  It writes the cells that are missing and sets, on the ones there, ONLY what the table decides: an item's
  name, stack, tool and tier, weapon and Power, part and trait; a recipe's name, station, skill, inputs,
  output and part slot. **Everything else is yours and stays**: an item's color, look and words; a
  recipe's XP, rank, AFK time, how many of each input and its round (so the recipe bench keeps working).
  A new cell starts those from its pattern and material ("New cells start with": the pattern's XP and
  time scaled by the material's `work_scale_pct`, at the material's `rank`).
- **A cell by hand**: tick its `by_hand` and the table leaves it and its recipe alone (steel's bar, made
  from iron and coal, will be one). The table never deletes a file: a cell it no longer makes (a new hole)
  is reported, to settle by hand, since its id may be in players' bags.
- **The bake refuses a table out of date** (each material's `validate_with`): the Content panel and the
  bake name the file, the field ("weapon_damage_pct: has 90, makes 100") and the fix (Make the table).
- **Try it**: open `content/material/iron.tres`, set Weapon Damage Pct to 110, press **Make the table**:
  the iron axe and sword go to 110 (the item check still holds tier dominance: no iron below the best
  bronze). Put it back and press it again. A new metal is one new material: press the button and its bar, head, blade,
  axe and sword appear with their recipes.
- Not in this step (MATERIALS.md §10): copper as tier 1, coal and steel (step 2); the station's slots and
  the player's trait pick (step 3; the recipe still has one pickable part, so a pattern may have one);
  optional slots (an oil); bindings and wood-core bows (step 4); the Materials bench (step 7). The server
  does not read materials or patterns yet (their JSON is baked for when it does).

Tested: regents suite 2421/0 (30 new: five materials and six patterns, valid; the nine cells each the
item it was, ids pinned; the table current and making it again a no-op; an iron axe at 90 % named by
iron's own check with the file, the field and the fix, copper's silent; iron to tier 3 stales the axe
alone; a recipe's inputs drifting caught; tuned XP never stale; a cell with no pattern, a pattern with no
core or no {m}, a table recipe for a non-cell, refused; in a scratch project a new metal and wood made for
real (four cells, four recipes, tier, speed, Power and trait from the material, new ids and files, seeded
XP and time), made again a no-op, a renamed cell restored with its color and XP kept, a tier change
touching the axe alone, a hole that keeps its file, `by_hand` left alone). Each negative proven by
breaking the table: drift never reported (6 checks fail), links equal whatever their id (1), `by_hand`
made over (1), a tool's tier not its material's (3). The bake: `item.json` and `recipe.json` unchanged;
content bake 18/0; `cargo check` (wasm) clean; skilling playtest 61/0 + 7/0 (61 or 62 by the dice: two
of its checks run only when the AFK tree stands and the smelt leaves bars over). Published to
`regents-rule` (data kept). Not seen by Luke yet: the Make the table button in his editor.

## Step 18: copper, iron, steel (MATERIALS.md step 2, 2026-10-23)

The slice's ladder (Luke, `MATERIALS.md` §8): **copper tier 1, iron tier 2, steel tier 3**, and coal.
- **Copper is tier 1**: out of the table's holes, so it has an axe head, a sword blade, a pickaxe head, an
  axe, a sword and a pickaxe like iron. **The starters are copper's cells**: the Bronze axe and Bronze
  pickaxe are now the **Copper axe** and **Copper pickaxe**, the same items (ids 40001 and 40006, so every
  bag that has one keeps it; their files are `copper_axe.tres`, `copper_pickaxe.tres`). Copper's Power is
  the starter's 70, its tool speed 100.
- **Two new patterns**, the pickaxe head (anvil, its own outline: thin points, a thick eye) and the pickaxe
  (head, handle, rivets), so every metal has a pick. The **iron pickaxe** (tier 2) is the way to coal.
- **Coal** (an item) from the **coal rock** (`content/node/coal_rock.tres`): mining tier 3, needs mining
  rank 3 and a pick of tier 2, a harder seam than iron's (nine notches, a steeper bend, quicker strikes).
  Three stand southwest of the iron rocks (`coal_1`..`coal_3` in `frontier.tscn`; the level re-baked).
- **Steel** (`content/material/steel.tres`): tier 3, Power 140 (its swords and axes 140 to 168: tier
  still dominates), tools at 75 % of the time, no ore of its own. **The steel bar is a cell by hand**:
  two iron ore and two coal at the furnace (`recipe/steel_bar.tres`, smelting rank 3, a
  hotter, narrower round than iron's). Everything else steel (heads, blades, axe, sword, pickaxe) is the
  table's, from that bar.
- **New cells' numbers** came from the patterns scaled by each material (copper half of iron's XP and
  time, steel half again more, at rank 1, 1 and 3) and are yours to tune on the recipe bench; the iron
  pickaxe's two recipes were set to rank 1, as the iron axe's are. Icons: the new items show their
  initials until `tools/render_icons.tscn` is run (windowed).
- **The table found its own bug** while making these: a new item and the recipe that takes it, made in
  one run, wrote the item INSIDE the recipe (the item did not yet know its file), and the bake refused it.
  Fixed (`MaterialTable._save` gives a new piece its path), and the suite now reads made recipes back from
  disk. And "no recipe from the table" no longer hides why the table cannot make one (steel's bar,
  unticked from `by_hand`, says "Steel has no raw form").
- **Play it**: Play; mine copper (the starter pick), smelt, smith and assemble a copper pickaxe if you like;
  mine iron, smelt iron bars, smith an **iron pickaxe head** and assemble the **iron pickaxe**; mine the
  **coal rocks** (southwest, past the iron) at mining rank 3; smelt **steel bars** (2 iron ore + 2 coal, at
  smelting rank 3); smith steel parts and assemble a steel axe, sword or pickaxe.

Tested: regents suite 2426/0 (the ladder; the starters as copper's cells under 40001 and 40006; swords by
tier 70-84, 100-120, 140-168, no overlap; the steel bar by hand, two iron ore and two coal, and the table's
steel head taking it; the coal rock's tier, pick and rank; the iron pick works coal and the copper one not;
iron to tier 3 stales both its axe and pickaxe; made recipes read back from disk link their cells; the
lab's eighteen rounds). Negatives by breaking the table: a new piece not taking its path (the read-back
check fails, naming every recipe that carried an item inside), "no recipe" hiding why (the steel check
fails). Native `cargo test` all green (the regents test: six nodes, steel's coal); integration 1021/0 (29
nodes placed); skilling playtest 62/0 + 7/0; combat playtest 50/0 (the Copper axe on the skill bar);
content bake 18/0; `cargo check` (wasm) clean. Published to `regents-rule` (data kept: a returning player's
arrival places the coal rocks and renames the starters in every bag). Not seen by Luke yet: any of it in
play; the new items' icons (run `tools/render_icons.tscn`, windowed).

## Step 19: the Tester page (owner, 2026-10-23)

Luke, before playing the ladder: "I think Tester should have an admin button to reset the stats or maybe
manually adjust them". He chose all four tools, on **any player**.
- **Escape, Tester (admin)**: shown only to the admin (the identity your editor plays as, `Roles`), like
  Rules (admin). Pick the player (you first, then everyone in the world by name; Refresh list), then:
  - **Skills**: each skill's rank and XP for that player, a rank box and **Set** (down as well as up: the
    XP becomes that rank's start).
  - **Reset all skills**: every skill to rank 1 with no XP, no recipe on record (the first-make bonus back,
    nothing stale), no work order filled; any work stops.
  - **Give**: any item, how many, and a quality (0 to 1000, its grade shown) for one that does not stack;
    a stacking item ignores it. Up to 10 000 of a stack at once, 20 of a tool or weapon.
  - **Reset the bag**: emptied, the weapon put away, the starter kit (Copper axe and pickaxe) again.
- The server does each (`admin_set_rank`, `admin_reset_skills`, `admin_give_item`, `admin_reset_bag` in
  `server/src/game/regents.rs`) and refuses anyone who is not the admin, a target who is no player, a
  rank past the skill's, a count past the caps. New reducers (rule 17: nothing an older build calls
  changed), so a publish with `--codegen`; no wipe. The page: `game/regents/ui/tester_page.gd`, added to the
  menu by the HUD (`regents_hud.gd`).
- To try the ladder quickly: set mining and smithing and smelting to 3, give 20 iron ore and 20 coal, and
  go to the furnace.

Tested (step 19): regents suite (offline: each control sends its reducer with the right arguments; the grade
shown for a quality; stacking items show no quality; the menu's button for the admin only, added once);
integration (a stranger's four calls refused AND the player's XP, records, coal and bag unchanged; ranks set
up and down, past the skill's refused, a rock no player; coal and two Masterwork steel axes given; caps;
skills reset with records and orders; the bag reset to the starter kit, the held weapon put away). Negatives:
the button shown to everyone (1 check fails), added every frame (1), the admin check taken out (8). Published
with `--codegen` (data kept): a friend's build needs a NEW EXPORT.

## Step 20: the crafting rework, choosing parts and traits (MATERIALS.md step 3, 2026-10-23)

Luke's calls (`GAME.md`, `MATERIALS.md` §3-§4): a crafted item holds traits by grade, **Common 1, Fine 2,
Masterwork 3**, and **the player picks which**; the station must say plainly how many this grade holds and
which are in use. Built while Luke was away ("start the crafting rework ... I'll playtest it at the end").
- **The station window lists each recipe once**, under what it makes (Handles, Axes, Swords, Pickaxes, Bars,
  Axe heads...; what is no cell of the material table under Other): no more a line per handle.
- **Each part slot is a list** of every part of its kind (the handle: plain, oak, yew, with how many you
  have); pick one there.
- **Traits**: "Made Fine (quality 650): holds 2 traits" (the grade from the best input in the bag, as the
  server takes it: best first), then each trait the picked parts offer, a box to want it, numbered in the
  order wanted, marked **in use**, **left out**, or **no room at this grade**. Before you have a head: what
  each grade holds.
- **The server** (`craft_choosing`: the part in each slot and the traits wanted, in order) keeps the choice
  (`craft_choice`) for every batch, AFK or a round; each batch's made item keeps as many of the wanted traits
  as ITS grade holds, the first first. **None wanted is a choice**: the item says `"t":[]` and has none (not
  its handle's). `craft` and `craft_with` (older builds) are unchanged: every trait the parts offer.
- **Hot rules** `regents.crafted_traits_common / _fine / _masterwork` (1, 2, 3; the Rules page).
- **Recipes may now have several part slots** (`RecipeDef.part_slots`, from the pattern's player-picked
  slots; `part_slot` stays the first, for older builds), so a binding or an oil that offers a trait is
  content, not code. Today only the handle offers one (bindings with traits are step 4, Luke's §11).
- **Defaults I chose while Luke was away (his to change)**: changing a part starts its recipe's trait picks
  over (every trait the parts now offer, ticked); a lower-grade batch keeps the FIRST traits in the order
  wanted; the pick is made at assembly and fixed (re-picking later stays §11's open question); the server's
  reducer is `craft_choosing` (SpacetimeDB names `craft_v2` `craft_v_2`, so a digit was avoided).
- **What a player sees today**: the same items as before (a Common axe holds one trait, and a handle is the
  only part with one), now with the choice shown and the option to leave a handle's trait out.
- **Play it**: at the workbench pick Iron axe; in Takes, set the handle's list to Oak; under Traits see the
  grade your best head makes and Steady in use; untick it to make an axe with no trait; MAKE.
- Luke confirmed these defaults the same day (`GAME.md`).
- **Found by the playtest, fixed**: a list argument's type hint to the SDK is its ELEMENT's (`u32`, not
  `vec_u32`: the SDK writes the length, then each element), and SpacetimeDB names a reducer `craft_v2`
  `craft_v_2` (so it is `craft_choosing`). The unit suite cannot see either (offline, a call fails before it
  is written); the skilling playtest does. And the integration suite's order board could leave a steel axe in
  the bag (an order may now want a tool), which then was "the best axe": it now puts away what it gave.

Tested: regents suite 2454/0 (new: traits by grade from the hot rules; the iron axe's slot, the plain
handle to start; the oak picked offers Steady, sent to `craft_choosing` with it; unticked, none is sent; the
yew re-ticks its Springy; logs are no handle; headings; the window: sixteen lines under five headings, the
slot's list of three handles, "Made Fine (quality 650): holds 2 traits", Steady first and in use, unticked
left out, a Common head's room for one, MAKE grayed with the oak handle gone); native `cargo test` all (the
room by grade; the player's order; a lower grade keeps the first; offered only, none twice; none on purpose
stays none, an old tool still has its handle's); integration 1024/0 (`craft_choosing` refuses a copper bar
as a handle, a trait no part offers, one twice, two parts for one slot, a part for a recipe with none, an
oak handle not in the bag; keeps the choice as sent, and none as none); skilling playtest 63/0 + 7/0 (the
Iron axe made through the window: the oak handle in its slot, Steady in use, `{"q":..,"h":40016,"t":[40001]}`);
combat playtest 50/0; content 18/0. Negatives by breaking the code: the grade's room ignored (native fails),
none falling back to the handle (native), the picks ignored on the client (2 unit checks), the server taking
any trait (2 integration checks). Published with `--codegen` (data kept). Not seen by Luke yet: all of it.

## Step 21: after Luke's first look at the crafting rework (2026-10-23)

Luke, with the station window open: the wording should lose the quality number; pick WHICH head (a Common
or a Masterwork), grayed when you have none; there is no benefit to more than one trait yet (only handles
offer one); and earlier materials should say what to expect at the workbench. His calls (`GAME.md`):
- **The head by grade**: in Takes, the head is a list, "1 / 1  Masterwork iron axe head", "Fine ...",
  "Common ..." (a grade you lack grayed; none at all, the list grayed). The window sends it
  (`set_craft_grade`, then `craft_choosing`); every batch of that run takes only that grade's heads and the
  run stops when they run out (`craft_grade`). When the grade picked is gone from the bag, the list shows the
  best you have. An older build's `craft` takes the best of any grade, as before.
- **Plainer traits**: "A Fine iron axe holds 2 traits"; before you have a head, what each grade holds. The
  boxes are drawn as checkboxes (the style's button look had reached them).
- **Rivets are a pattern now** (copper, iron, steel; copper rivets keep their id 40012), and the axe, sword and
  pickaxe take ANY rivets in their binding slot, so Fine and Masterwork have something to hold.
- **Every part offers a tool trait and a weapon trait**, and only the one that fits counts (an axe is a tool
  first): oak Steady / Heavy, yew Springy / Balanced, copper rivets Gentle / Thirsting, iron Lucky / Brutal,
  steel Prospector's / nothing until Keen (crits). This also fixed a step-20 mistake: an oak handle's Steady
  was offered to a sword, where it does nothing. Each part's list says what it gives the item being made
  ("Oak handle: Steady").
- **Refit** (swap a made item's parts): at the workbench, under "Refit (swap its parts)", each made item in
  your bag; pick new parts and traits as when making it; it costs each new part (the old one is lost) and
  `regents.refit_bars` (2) bars of its head's metal; its head, quality and anything else it carries stay;
  its traits are picked again within its grade's room. A made item now records its parts (`"p"`).
- **Tooltips**: a material or a part says what it makes ("Makes: Iron axe head, Iron rivets...") and, for a
  part, the trait it gives tools and weapons; in a part's list, the one it gives the item being made. In the
  bag's card, the same lines.
- **Trait ranks** were discussed, not built: both a better-made part and upgrades through use are liked, but
  the minigames must be harder first and AFK crafting must still pay (`GAME.md`, `MATERIALS.md` §11).
- **Play it**: Tester page: give two iron axe heads (quality 300 and 900), an oak handle, iron rivets, iron bars;
  at the workbench pick Iron axe; the head's list by grade; the rivets' list (Iron rivets: Lucky); Masterwork
  holds 3; make it; then under Refit pick it, swap the handle, see the cost, Refit.

Tested (step 21): regents suite 2469/0 (each part's trait by what it is made into; two part slots, copper
rivets' Gentle by default; the oak's Steady and Heavy; a sword's Heavy and Thirsting; the head's list by grade
with the missing grade grayed and the best as fallback; "A Fine iron axe holds 2 traits"; a checkbox drawn
as one; Gentle with no room at Common, moving up when Steady is left out; the refit line, its cost, REFIT
grayed when nothing changes or bars are short; tooltips: what a material makes, a part's traits); native
`cargo test` all (regents 35/0: the trait that fits, grades, the parts noted); integration 1051/0 (rivets'
traits by kind; the grade refused when absent, kept, forgotten by an older build's craft; refit's refusals,
its cost paid, the row rewritten with its parts and traits, nothing-to-change refused); skilling playtest
63/0 + 7/0 (the axe made with Steady and Gentle as its grade holds, its parts noted); combat 50/0; content
18/0. Negatives: a part giving its tool trait to a sword (native fails), a missing grade selectable (unit),
a refit charging no bars (2 integration checks), the grade ignored (integration). Found while testing: the
CLI's SQL runs an array's numbers together, and the integration's own crafted head can be any grade (it now
clears heads first). Published with `--codegen` (data kept). Not seen by Luke yet: step 21 in play.

## Step 22: this game's half of the template 1.0 (2026-10-24)

The template 1.0 (cells, the ring, streaming, accounts) was taken in the morning; this is Regent's own part
of it (`../UMF Template/docs/TEMPLATE_1_0.md`, template DECISIONS #278-#281).
- **Ring interest**: the game's Boot now has a net config of its own (`game/regents/regents_net_config.tres`,
  `interest` RING): a player is sent only the 3 x 3 cells (64 m each) round them, plus their own rows
  wherever they are. The frontier glade fits inside one ring from the spawn, so nothing looks different
  today; it matters once the world is bigger than ~190 m across.
- **The overrides** (`game/regents/content/rules/regents.tres`, Luke's 1.0 answers 4 and 10):
  `foundation.characters_per_account` 3, `foundation.park_offline_s` 30 (a character whose player left
  stays where it stood for 30 s, then is put away until they sign in again; nothing of theirs is deleted).
- **Regent's own tables carry the cell** (Luke, 2026-10-24: "reshape now"; a second wipe, `compat` 3,
  because no compat-2 build had gone to friends): `gather_node`, `station`, `dummy`, `foe` (placed things),
  `afk_work`, `casting`, `burning`, `wielded`, `combat_state` (they follow a player or a foe: `follow_place`,
  the genre's `on_place_changed` hook; `wielded` and `combat_state` gained `world_id` too), `work_result` and
  `spell_area` (events, cut where they happened). Each is asked for by cell (`cell_tables`), the five that
  can be a player's also by id (`follow_tables`), and every one is a world table for a WORLD client (the
  referee).
- **Left world-wide on purpose**: `skill_xp`, `recipe_log`, `spell_cooldown`, `order_filled`, `foe_kill` are
  a player's own records, sent to everyone today (the template has no "your own only" query yet; the 1.0
  doc named it for `inventory_item`). `work_order` is the world's board. The 300-bot test decides whether
  any of it matters. Server-only tables (`arrow`, `missile`, `hurt`, `stuck_arrow`) are never sent.
- **Play it**: Play as before; nothing in the glade looks different (it fits one ring). Two characters per
  account beyond the first come with a sign-in (the SpacetimeAuth client id is still Luke's to set up); a
  guest's character is put away 30 s after they quit and is back where they stood when they connect again.
- **Two test fixes found on the way**: the integration hook's traits block let its CLI referee lapse (a
  referee is online 5 s after it was last seen; the calls took longer, so it failed twice): a fresh referee
  now judges the traited chop, and the chop is measured from a whole dummy (it heals 5 s after its last hit,
  which a slower run crossed). And the foundation's ACCOUNTS suite assumed the foundation's defaults; under
  Regent's 3 characters a guest's character joined the account at the link, so its "second character" was a
  third. Fixed in the TEMPLATE (`tests/accounts_test.sh` sets 1 character and no parking after it publishes),
  uncommitted there beside the low-end hardware work; this game's copy is the old one until the next pull.

Tested (step 22): `cargo check` (wasm) clean, `cargo test` all green; unit 2572/0 (39 new: the game's Boot
has ring interest; each cell table is subscribed, a world table, and its rows carry `world_id` and `chunk`;
each follow table is keyed by `entity_id`; every table of ours with a `chunk` is a cell table); integration
1096/0 (new: `wielded` and `combat_state` in the camp's cell, the dummy's row in the cell it stands in; three
cells away both follow, the weapon no longer in the camp's cell; back, it comes back); skilling playtest 63/0
+ 7/0 and combat playtest 50/0, both on the ring (a WORLD run of the skilling playtest for comparison: the same
63 + 7 and the same `session_member` bind warnings, which are the CLI's own players and older than this);
accounts 65/0 with the template's fix (6 failed without it). Negatives: `burning` left out of the cell tables
(2 unit checks fail), the `on_place_changed` hook switched off (3 integration checks fail). Published:
`regents-rule` `--fresh --codegen` (wiped, Luke's say-so), then again keeping data. Not run: e2e and the
template's ring suite (foundation only, unchanged here). Not seen by Luke yet.

## Step 23: the continent, a greybox for the ring and the load test (2026-10-24)

Luke, with his map (`game/regents/levels/continent/continent_map.webp`): load test first, but on a world bigger
than the glade (which fits inside one ring, so nothing in it ever crosses cells). His calls: the main
continent only (no islands, no name), **about 3 km across its widest**, the camp in the **center-west
lowlands**.
- **The shape is read off the map** (`continent_shape.gd`): its green is land, its gray-brown ridge the
  mountain spine, the rest sea; only the largest landmass is kept. 2.25 x 3 km, peaks to ~160 m, the sea at
  y = -6, and the camp's point flattened to y = 0 at the world's origin.
- **The level is generated** (`build_continent.tscn`, seeded, re-run to change anything; ~20 s): Terrain3D
  at 2 m (42 regions, 7.5 MB) with generated ground textures (grass, rock, sand, tinted), the sea plane, an
  invisible wall at wading depth (the server's bake says the same water is not standable), and under
  `LevelInfo/Cells` everything placed: **the glade's camp copied in unchanged** (its 38 points at the same
  places, so whatever works in the glade works here) and a **TEST placement**: 516 nodes (trees, oaks, yews
  in forest patches; copper, iron, coal by the hills and mountains, the better the farther out), 16 skeleton
  camps (48 skeletons), 917 decor pieces. Luke's own placement replaces the test one.
- **Level 21 "continent", streamed**: the bake writes `shared/world/continent.json` (602 points, a 4 m depth
  grid, 0.4 MB, compiled into the server) and cuts 484 cell scenes (`continent_cells/`); a player's game
  loads the 5 x 5 round them. Probes for the Rust/GDScript parity: `shared/golden/level/continent_probes.json`.
- **Rocks and bushes stay solid when streamed** (`solid_props.gd`): each cell's are wrapped as it arrives.
- Found on the way: Terrain3D puts an import's corner on its region grid, so a terrain not started on one
  was 248 m and 346 m off its shape (the unit checks caught it: points "in the sea"). It now starts on one.
- **Play it**: a fresh database still starts in the glade (level 20; the suites run there). The play
  database's world 0 is put on the continent with `spacetime call regents-rule set_world_level 0 21`
  (back: `... 0 20`; bags and skills are kept either way). Press Play: the camp as before, the continent round
  it; walk out (sprint is ~6 min from end to end).

Tested (step 23): unit 2643/0 (11 new: level 21 baked, streamed, cut; the glade's points all in its camp;
every point a node or foe the game has, on dry land; the camp dry, the open sea not standable; a streamed
cell's rock wrapped as it arrives, the grass not, its shape gone with the cell; the continent's 82 probes on
both sides); `cargo test` green; the new **continent playtest** 17/0 (`game/regents/tests/continent_playtest.sh`:
a real client at 150 ms on the continent: 19 of 484 cells loaded round it, the nodes it is sent all in its
3 x 3 cells; 700 m out the ring and the cells follow, the camp's tree is let go, it stands on the ground;
a cell east, the nodes both rings share kept, none spawned again). Negatives: WORLD interest instead of the
ring (6 playtest checks fail; it is then sent all 545 nodes and 603 entities, against 7 on the ring), the
streamed wrapping switched off and a camp point moved (a unit check each).

### The world map (Luke, 2026-10-26: "M should open full world map with hoverable icons")
- **M** opens `RegentsWorldMap` (`game/regents/ui/world_map.gd`): the level from straight above (one 1024 px
  picture, the capture camera freed after one frame), every node, station and point of interest of its bake,
  you as the arrow; wheel zooms at the mouse, drag pans; hover says what an icon is. A node you have
  DISCOVERED is named ("Coal rock"), any other is "<skill> ???" ("Mining ???"). POI names are drawn unless
  they would overlap one already drawn; a "minor" POI (the camp's workshop) only once zoomed in.
- **Discovered = been within `regents.seen_reach_m` (25 m, hot) of THAT node** (Luke chose per node, by
  being near). `RegentsDiscovery` (`game/regents/discovery.gd`) asks `saw_nodes` once a second with the
  nodes drawn near you; the server measures from where it has you (+5 m slack) and keeps a `node_seen` row
  per character and point, sent to its player only (a row filter). Rate limit `saw` (4, 1/s).
- **POIs** are level points of kind `poi`, first tag the name: the glade has The frontier camp, Workshop,
  Training yard, Skeleton camp (`frontier.tscn` "Places", rebaked); the continent copies them and its
  generator adds one per skeleton camp and a harvest zone wherever 4+ nodes of a kind stand in a 384 m
  square (25 zones; no random draws, so the 602 placed points are exactly where they were).
- Tested: the regents suite (icons for every node, "Mining ???" unseen / "Coal rock" seen, the continent's
  map holds every point), the integration suite 1085/0 (saw_nodes: far not seen, near seen once, nonsense
  skipped, 33 refused, another player sent none). Seen in a window: the continent's terrain, zones and
  camps drawn (a screenshot). **The continent playtest's dropped connection (found 2026-10-27)**: not the network. Opening M froze the
  game's main thread ~90 s (twice: the HUD's open and the test's own count), so it answered no keep-alive and
  the server closed it for idle. `RegentsWorldMap.icons_of` looked each node point's content up with
  `ContentLibrary.items`, which lists the content folders and loads every piece each call: 545 times on the
  continent (38 in the glade, so the unit suite never felt it). Now the node defs are listed once per call,
  through `RegentsContent` (the genre's cache). Found by timing the playtest's steps (the gap sat between
  "M opens" and the next step); restarting `spacetime start` changed nothing. Tested: the regents suite
  2661/0 (new: the continent's icons in under 2 s, every node known; with the per-point lookup back it FAILS
  at 19.6 s); the continent playtest 22/0 headless (27 s, was 6.5 min) and 23/0 windowed, its discovery and M
  checks green. Client only: no publish needed.

### Luke's solo playtest of the continent (2026-10-24 night): his notes, sorted; worked through 2026-10-26 (each marked)
Nine notes (`tools\feedback.cmd`), most at the camp, one out on the continent. Sorted for the next work:
- **Small, with or before the load test** (each to look into first):
  - **#9 FIXED 2026-10-26** (template 1.1.1, `AnimationDriverComponent`): the server spawns a skeleton at its
    point in one step (the chronicle agrees: the camp is at the continent's origin). Since #282 a character's
    tree is advanced only by its driver, and a new one was drawn in its rest pose until then; it is posed the
    moment it is built now. Tested: the remote_animation suite (0 of 65 bones posed without the fix).
  - #9 a skeleton T-poses near the origin for a moment as it spawns (Luke's guess: spawned at 0, then moved
    to its point). Likely its entity drawn before its place and pose arrived; check on the ring, where a
    foe's rows come in cell sets.
  - **#7 WORKED ON 2026-10-26** (template 1.1.1): "Player 39" is the database CLI's own player (an admin with no
    name, at the spawn), drawn though `PresenceComponent` hides a tool. Its exact cause on Luke's night is not
    proven; two real foundation bugs found on the way are fixed: (a) `Cells.recentre` held the old ring center
    after a long jump onto a cell's EDGE, and the spawn (0, 0, 8) is on one: back at the camp from far away a
    player kept a ring 600 m off and was sent nothing round them (now a jump past the neighboring cells
    re-centers at once); (b) a nameless player whose admin row comes after theirs is asked after again
    (`is_tool_row`). The continent playtest now keeps the CLI coming back every 3 s (as the host's watcher
    did), checks it is hidden as a tool at the camp, and again after a trip out and back (19/0). If Luke still
    sees it, the next look is the nameplate/presence of an entity that re-enters the ring.
  - #7 a nameless "Player 39" is shown (once "Player 30", DECISIONS #272: a tool is not a person). Likely
    the CLI's own player again (this session's `spacetime call`/`sql` made one); why it is drawn is the bug.
  - **#5 FIXED 2026-10-26** (the minimap; the M world map is an idea, Luke's call): it pictured a level once,
    at most 400 m square round its points. A level too big for that (the continent) is now pictured round
    the player (288 m, inside the 5 x 5 streamed cells) and again as their widest view nears the picture's
    edge; the camera is 400 m up (the mountains). Tested: the genre suite's sums, and the continent playtest
    in a window (`WINDOWED=1`): 850 m out the picture is round them (20/0; the old minimap fails it).
  - #5 the minimap stops updating out on the continent (it was built for the glade's size); **idea: M opens
    a full world map**.
  - **#4 bushes DONE 2026-10-26** (Luke's words, to confirm; GAME.md): `solid_models` is rocks only, in the
    script and in the continent's scene (its one line edited to what the generator now writes, not rebuilt:
    the bake is water depth only). A foe now sees and walks through a bush too. Tested: the genre suite (a
    level's bush is not made solid), the continent playtest 19/0. Not looked at: the shadows near them.
  - #4 **bushes should not be solid** (Luke: "the bushes have 3d collisions when I don't think they should":
    a change to his 2026-10-21 "every 3d object should have collisions"; rocks stay solid). Shadows "seem a
    little messed up" near them (to look at).
- **The combat deep-dive** (Luke: "we can fix in combat rework/deep dive"):
  - **#8, the Lunge part DONE 2026-10-26** (`CombatComponent.commit_seconds`): a swing's animation was held only
    to just after its hit; the Lunge moves the body itself, so its own dash let go of the clip halfway. A
    lunging ability is held its whole clip now. Tested: the genre suite's sum only; NOT seen in a game (the
    combat playtest wields the axe): Luke's look. The LMB spam (the next light may start just after the last
    one's hit, cutting its tail) is combo design: left for the deep-dive.
  - #8 the sword: spamming LMB cuts off the second swing's animation; Q (Lunge) is cut off halfway.
  - **#6 FIXED 2026-10-26** (`combat_component.gd`): Ctrl in the air is held and rolls as you land (within
    1.5 s), as a swing already did. Client-side only: the server does not refuse a roll in the air yet (for the
    deep-dive's cast queue). Tested: the combat playtest live (51/0; 50/1 without the hold).
  - #6 a roll in the air should not happen: queue it for the landing (the cast queue).
  - **FIXED 2026-10-26** (template 1.1.1, DECISIONS #283): the referee's sweep hit the FIRST person in its
    path, the skeleton beside, which the genre then spared. A hot flag `foundation.referee_two_sides`, ON here
    (an override in `game/regents/content/rules/regents.tres`): a sweep passes through its user's own side
    (the players, or everyone else) to the first of the other; a player still hits a training dummy. Tested:
    the referee suite's two sides (off and on), unit 2649/0, the combat playtest 50/0 live.
  - #2 + #3 skeletons hit once, then keep swinging for no damage; two side by side were hitting EACH OTHER
    (friendly fire off, so nothing), and once one died he took damage again. Likely the referee's sweep
    stopping at the first body it meets (the other skeleton), not the player behind it.
  - #4 foes do not path round obstacles: a bush blocks a skeleton's sight and it turns back (NPC tiers and
    brains).
- **Performance, for the load test**: #1 a lag spike sprinting at the start (Luke's guess: the referee
  starting). The reports agree: network spikes of 600-950 ms at 22:03:23-25 for him; the REFEREE had 111
  spikes in 16 min, stalls of 3.0 s (22:03:41) and 4.5 s (22:06:49), its worst frame 144 ms. It now loads
  the whole continent (Terrain3D's full collision, ~600 entities, ~900 props wrapped solid): the first
  suspect, and exactly what the harness should measure.

## Step 24: the load test on the continent, and what holds the referee back (2026-10-29)

**The harness** is the template's (1.2.0, DECISIONS #284; 1.2.1 here, pushed there): `tests/load_test.sh`, light
Python bots in steps, measured from both ends. Regent's Rule's part:
- `game/regents/load_bot.py`, the bots' play: every bot wields its starter Copper axe; every third swings the
  axe's two-step combo (judged by the referee; standing for each swing's committed part, as a client
  slow-walks), the next gathers the nearest tree or copper rock AFK for 6-12 s after saying it saw it, the next
  only walks. A node worked out as a bot reaches it is play (`EXPECTED_REFUSALS`); any other refusal fails the
  run. `LOAD_BOT_PLAY=0`: every bot only walks.
- `shared/regents/load.json`: the continent (level 21), steps 50, 100, 200, 300.
- `game/regents/tests/load_300.sh`: the foundation's suite, then this game's checks that the bots really played
  (swings, gathers, nodes seen, every step), and a negative (a report with no gathering fails them).
- **To run it**: `tools\run.cmd game\regents\tests\load_300.sh` (~25 minutes, the test database).

**What it found** (the full record and the order of fixes: `REFEREE_SCALING.md`):
- The server keeps up at 300 (movement tick p95 23.6 ms of 50 with honest bots; reducers queue 44.5 ms at p95).
- The referee breaks at 50-100 as it is. 80 % of what it is sent is `input_queue`, which it never reads. Sent only
  what it reads, it holds at 100. A referee for a part of the world (5 x 5 cells, 5 of the 51 foes) holds at
  300 with room (16 ms). Brains and foe writes are paid per NPC, whether a player is near or not.
- Per player on the wire: ~35 KB/s at 50, ~80 at 200, ~120 at 300.

**Found and fixed on the way**:
- **The walk map on the continent** (template 1.2.1, DECISIONS #285): baking the whole continent was refused by the
  engine, so no foe could go round anything, and the referee stalled trying. Now a tile at a time, off the main
  thread. **Foes chase round obstacles** (`foe.gd`: `go_to`, the walk map), and a target lost from sight is
  chased to where it was last seen for `FoeDef.lose_sight_ms` (2500, a default for Luke to tune) (#4).
- **No roll in the air, on the server too** (#6): `may_fight` refuses it ("no roll in the air").
- **The skeletons' family**: `family = &"undead"` sat above `script =` in their `.tres`, so Godot dropped it;
  moved, baked.

**Tested**: genre unit 2672/0 (the foe's chase round the walk map and its memory; the family; each fails with
its fix taken out); native 35/0; integration 1068/0 (a roll in the air refused, the same roll on the ground
taken; the old server takes it); combat playtest 51/0; continent playtest 22/0; content 18/0; `load_300.sh` run
to the end with both negatives; template unit 2211/0 (the 3 km walk map fails baked whole). Published to
`regents-rule` (data kept).

**Also written**: `COMBAT_CURRENT.md`, the combat as built, for Luke's combat overhaul.

### The referee's first two fixes (Luke, 2026-10-29: "lets do them in order", the suites each touches)
Template 1.2.2 + 1.3.0 (DECISIONS #286, #287), pulled here (local merge commits):
- **A referee is sent only what it reads** (#286): no `input_queue`; its tables, its entities' components'
  (`required_tables`, the new `also_reads`), the genre's `referee_tables`, the recorder's while recording.
  Here `game/regents/genre.tres` `referee_tables` is empty (the foes' brains read only the world view):
  37 tables. `SkillingComponent.also_reads` names `work_order`. A read of anything else is an error in the
  referee's log; `combat_playtest.sh` now fails on one, and on `input_queue` in its feed.
- **NPC tiers on** (#287; RULE_DESIGN §6.1's numbers: awake within 200 m, asleep after 30 s with nobody within
  400 m): `foundation.npc_tiers` overridden on in `game/regents/content/rules/regents.tres`. The brains' world
  view is built once a think period. It had never known who the players were (fixed in the template).
- **A swing cut short has its own refusal** (`combo_refusal`, `server/src/genre/regents/mod.rs`): the combo's
  next step after a heavy's flinch or a roll is refused "the swing before was cut short: the combo starts
  again", not "out of the combo's order". The load bots read no statuses, so that one is play for them
  (`load_bot.py` `EXPECTED_REFUSALS`); any other order refusal still fails the run. Native check added.

**Measured** (`REFEREE_SCALING.md`, "After fixes 1 and 2"): the referee holds at 100 bots with room (19.5 ms
p95, was 127); it still breaks at 200 (118) and 300 (147). What is left grows with the players it watches:
the next fix is region referees (template milestone).

**Tested**: template unit 2237/0 (the feed: dropping the scenes' tables fails it; tiers: the count not
restarted by a passing player fails it), template integration 644/0 (its referee's log: the feed, no
`input_queue`, no unasked read; the first run caught a bot's SessionComponent reading `session_match`),
sidecar 13/0, bodies 20/0 + 10/0, native 92/0; here: genre unit 2698/0, native 35/0, combat playtest 51/0
(tiers on; with the old player lookup the foe never comes), `load_300.sh` to the end with both negatives.

### Fix 3, region referees: 300 holds (Luke, 2026-10-29: "continue if there is more work on the load test")
Template 1.4.0 (DECISIONS #288), pulled here and published to `regents-rule` with `--codegen` (a table added,
data kept). Several referees for one world, each for a rectangle of cells; the module keeps who drives each NPC
(`npc_driver`). Here `shared/regents/load.json` `"referees": [2, 2]`: the load test runs four.
- **Measured** (`REFEREE_SCALING.md`, "After fix 3"): at 300 bots the worst referee is 16.2 ms p95, the
  server's tick 46.0 and its reducers' wait 47.7 (both of 50). 300 holds. The server is the ceiling now.
- A flaky integration check fixed: the dummy's Stagger (800 ms) is read before the server's log, not after.

**Tested**: template unit 2260/0, integration 644/0, `regions_test.sh` 25/0 (its negative fails 4),
`test_load.py`; here genre unit 2716/0, integration 1099/0, `load_300.sh` with four referees to the end, both negatives.

**Left for later**: the server at 300 (`prune_action_events`' whole-table scan first); one unexplained "net
stall" a referee at the 50 and 100 steps; the cast queue (server-side) and the LMB spam (#8) for the combat
overhaul.

### The server at 300, read right (Luke, 2026-10-30: "start on the server's headroom at 300")
Template 1.4.1 (DECISIONS #289), pulled here. Code only: a plain republish, no `--codegen`.
- **The load test misread the server**: each call is two transactions in SpacetimeDB's metrics (the reducer,
  then its subscription update) and it summed them; its p95s are guesses inside 1/5/10/50 ms buckets. Read
  right (exact means, `busy ms/s`, the module's busy %): `prune_action_events` costs 2 ms a second and
  `work_tick` 5, so neither needed a fix. The movement tick was 438 ms a second, 76 % of the module busy at 300.
- The tick now reads each world's rows once a tick: its own code halved (3.2 ms a tick at 300), the module
  68 % busy, round trips p50 11.2 to 7.9 ms (`REFEREE_SCALING.md`, "The server at 300, read right").
- What is left is SpacetimeDB's subscription updates (15 ms a tick at 300: each moved row to everyone who
  sees it). The levers are design (Luke's): density, cell size, how often others' movement is written,
  `input_batch_size`. Gzip stays (no compression: 14 % less update for 2.2x the bytes).

**Tested**: template integration 644/0 (the tick ignoring statuses fails 2), e2e 11/0, movement playtest
41/0, native, `test_load.py` 23/0; here `load_test.sh` at 100 and 300 (and 300 with no compression), the
integration suite.

**Left for later**: judge `module_busy_pct` instead of the bucketed p95s (Luke); the "net stall" at 50 and
100 (still once a referee, ~30 s after it starts).

## Step 25: a Skyrim-size world, 300 bots spread over it, and how many referees (2026-10-30)

Luke: "finish the server work and make sure referees/sidecars are in the best spot performance wise and then
commit and ship everything for me to play test ... try it on a world close to the same size as skyrim with 300
players to see if there is a way to test how many refs I need and simulate that many bots with me playing a
local user as well to see them all run around and sync." Template 1.5.0-1.5.4 (DECISIONS #290-#294), pulled here.

- **The expanse** (level 22, a TEST world): `build_continent.gd` now builds either world (`world` on its node;
  the continent's settings are the defaults, so it comes out as before): `build_expanse.tscn` is the continent's
  map at 3.7 times its width, 8.3 x 11.1 km, **36.9 km2 of land** (Skyrim's is ~37), hills and mountains twice
  as tall, terrain at 4 m, the continent's test placement at the same density (10,245 nodes, 220 skeleton camps,
  660 skeletons, 544 harvest zones), the decor thinned to 40 %, 7,248 cells; its bake writes the ground's height
  too (`LevelInfo.bake_ground`) so bots walk on its hills. ~75 s to build. Never hand-edit it.
- **300 bots over it**: `shared/regents/load_expanse.json` (`LOAD=expanse`): a fifth in a 6 x 6-cell town round
  the camp, the rest anywhere on land, each roaming 8 cells round home; the referees cut so each has a like share
  of bots and skeletons (`npc_kinds`).
- **Watch, and play among them**: `tools\run.cmd game\regents\tests\expanse_watch.sh` measures one step, then
  keeps the bots playing and opens the game on the test database for you (`PLAYER=0`: no window; `REFEREES=3x2`,
  `STEPS=150`, `WATCH=900`). A line every 10 s: bots playing, the module's busy %, each referee's frames, what the
  referees take of this machine. Ctrl+C stops it.
- **How many referees**: `tools\run.cmd game\regents\tests\expanse_referees.sh` (the template's
  `tests/referee_sweep.sh`): the step once per cut, then `build/load/sweep.md`.
- **Found and fixed on the way** (`REFEREE_SCALING.md`, "A Skyrim-size world"): every connection compared each
  node point with every node (`populate`, here: hash sets); and in the template the ring's queries the server
  could not narrow, the tick reading 12,000 still rows, walk-map bakes all at once, idle skeletons stepped and
  written every tick, and the big one, the brains' view searching every node for the nearest player.
- The gatherer bots wait until the server has them in reach before tapping E, and walk on when no node is near.

**Measured** (300 bots, four referees, this PC): worst referee frame p95 147 → **26-30 ms**; the four took
3.9 cores and **4.0 GB, flat** (each 700-730 MB of its own: the whole level is ~375 MB of it); the module 78 %
busy; round trips 38 ms p95; 24 KB/s a player at p95 (spread out: 2.4 others seen). ONE referee for the whole
world drops out (7,513 swings refused with nobody judging): four is the least that runs it here.

**Tested**: template unit 2272/0 (new: the ground bake and its negative, the cell queries by number and another
world's rows kept back, and its negative, the walk-map queue, a still frame for a body at rest, the view's kind
index), integration 644/0, e2e 11/0, ring 15+47/0, sidecar 13/0, regions 25/0, `test_load.py` 33/0 (spread,
cuts, usage, the sweep table); here genre unit 2726/0, native 127/0, the expanse runs above.

Template 1.5.5 (no animation trees in a referee) and three bot fixes after (a gatherer waits for the server to
have it in reach, walks on when no node is near, and does not pick a node across a bay; a gatherer stopped at its
spot and nudged by a correction walked no more): every bot moves, nothing is refused, and every limit holds at
300 but one, **referee net stalls**: two of four referees lose their connection once or twice early on (a 30 s
main-thread stall just after their skeletons bind; not found yet).

**The stall, found and fixed** (Luke: "find what stalls ... fix it, then run expanse_referees.sh to the end"):
the 15-65 s frame was Godot's default physics engine (the project never named one): **Jolt** in every game now
(Luke: "We definitely want to be using jolt"; template 1.6.0); every level re-baked on Jolt's rays (the
continent's and the expanse's depth grids moved 0.1 m at rounding edges). The rest, a 0.5-1.5 s stall every 10 s
in every referee, was its look for a changed project walking 8,217 files on the main thread (template 1.6.2: on
a worker thread). And the level baker as a bare script cut a streamed level into one cell (template 1.6.1).
**The sweep, to the end**: two region referees hold 300 bots on the expanse (38.8 ms frames, no stalls, ~1 GB
and one core each, the module 55 % busy); one cannot; four and six give each referee room but break the
server (82-87 % busy: their column queries are not narrowed; `REFEREE_SCALING.md`, last section).

**Tested (the stall)**: template unit 2274/0 (new: the bake button runs a scene, and its negative; the
referee's look on a worker thread), integration 644/0, movement playtest 41/0 at 0/100/200 ms, remote 30+7,
e2e 47+11, sidecar 13/0, regions 25/0, press 6+7, native 92/0 (the example re-baked); here genre unit 2736/0,
combat playtest 51/0, continent playtest 22/0, native 127/0, the sweep above.

**A strip, one range** (2026-10-31; Luke: "make region referees ask for their cells in a way SpacetimeDB can
narrow ... then rerun expanse_referees.sh"): template 1.6.3 (DECISIONS #297): a region as tall as the level asks
for its columns as one range a table (it asked a range a column, 12-46 a referee, each checked against every moved
row). The sweep cuts strips now (`expanse_referees.sh`: `1x1 2x1 3x1 4x1 6x1`). Result: the module 34-40 % busy at
two to six referees (55-87 % before); two hold (40.0 ms); three, four and six break only on one ~0.9 s stall in
each referee (six: 10-16 ms frames). `load_bot.py`: "you cannot while slain" is an in-play refusal (a skeleton
killed a fighter as it swung). `REFEREE_SCALING.md`, last section.
**Tested (the strip)**: template unit 2281/0 (new: a strip is one range, a region cut across the level a range a
column, each holds exactly the level's cells it watches; their negative fails 3 with no merging), regions 25/0;
the sweep above (2x1, 3x1, 4x1, 6x1, run twice).

**The last stall, and two referees that drove nothing** (2026-10-31; Luke: "find the ~0.9 s stall in each
region referee of three or more, fix it, then rerun expanse_referees.sh"): template 1.6.4 (#298): a skeleton's
first swing asked for every kit, and `ContentLibrary.items` loaded the whole library for it (1.7 s a call): now a
type's own folders only (116 ms cold, 1 ms after); Telemetry times a frame by the clock (Godot caps `delta` near
133 ms, so the freeze read only as rows stopping). Template 1.6.5 (#299): a region referee asked the module for
all its NPCs in one call and the module refuses past 256: the two-referee runs drove NO skeleton ("two hold" was
wrong); now 256 a call, and the load test fails if an NPC has no driver. **Result**, every skeleton driven: four
strips hold 300 (37.5 ms), six with room (25.1 ms); one, two and three break; no net stall at any count.
`load_expanse.json` cuts four strips (`expanse_watch.sh`). `REFEREE_SCALING.md`, last section.
**Tested (the last stall)**: template unit 2285/0 then 2287/0 (new: a frozen frame by the clock, a type read from
its folders, wants_referee, the keeper's batches and its cap read from regions.rs; each negative fails), sidecar
13/0, regions 25/0 (once 24/1: its admin check read a hand-off over the edge as the admin's take; it now
allows either live referee), the load test's own tests (33); every game's unit suite after the merges (Fishing 3066/0, Fowl
Play 2570/0, DiscGolf 2360/0, here 2748/0); the harness's NPC check failed on the old keeper ("0 of 665"); the
sweep above.

**The strip with the town** (2026-10-31; Luke: "find why the strip with the town runs about twice the other
strips' frame times, and fix it"): template 1.6.6 (#300). A referee's frame timed by part and by table: the SDK's
index on `world_id` searched its list of every movement row of the world (~4,000, nodes included) for each row
that moved, ~85 us a row, and the town strip gets the most player rows; the judge looked at every movement row
for each swing. Now the index notes each row's place (the first UMF patch to the vendored SDK, kept by
`tests/suites/sdk_patches.gd`), and the judge looks at the people only. **Result**: three strips hold 300 (43.7 ms,
the town at its neighbors' frame time; was 102), four 30.4, six 21.2. `REFEREE_SCALING.md`, last section.
**Tested (the town strip)**: template unit 2309/0 (new: the index's slots through 1,500 updates, a removal, a move
between worlds; who is a person by each row; 7 mutations each fail 1-3 checks), e2e 11/0, sidecar 13/0, regions
25/0; every game's unit suite after the merge; the sweep above.

**Left for later**: a region referee loading only its part of the level; how often an idle skeleton thinks (the
combat overhaul's to set); the 2-3 s start-up stalls as a referee's skeletons bind; three strips or four (Luke's).

## Step 26: the combat overhaul, step 1: foes you can read (2026-10-31)

Luke: "let's get started on the ground work and first steps" of `COMBAT_OVERHAUL.md` (the playtest: combat
too fast, the skeletons' attacks landing together and hard to read). Its §9 step 1, pace and readability.

- **Foe kits of their own** (`game/regents/content/kit/skeleton_sword.tres`, `skeleton_axe.tres`; abilities
  40017-40021, `content/ability/foe_*.tres`): the warrior swings Rusted cut (550 ms wind-up), Rusted backswing
  (580), Skull splitter (850, unblockable); the axeman Hack (590), Crushing overhead (880, unblockable). The
  clips are UAL2's already in the project, slowed (`anim/adventurer.tres`, `ability.40017`-`40021`), each wind-up
  set where the clip's hand moves fastest (measured on the bones, matching the old Slash and Heavy cut to ~30 ms).
  Damage per hit is bigger and rarer: warrior 7 / 8 / 14, axeman 11 / 18.7. Player kits untouched; no weapon names
  a foe kit (both suites check).
- **Unblockable** (`KitDef.unblockable`, baked, `KitSeed::unblockable`): `hit` lets no block or parry stop it
  (`server/src/game/regents.rs`). **The red glint**: a foe's `HitFeedbackComponent` hears the use start
  (`started_elsewhere`) and, for an unblockable ability, flares a red spark at its head and flashes it red.
- **Turns** (`sidecar/npc/brains/regents/foe.gd`, per referee): at most `regents.attack_tokens` (2) foes swing at
  one player; the others CIRCLE at reach + 1.5 m, facing them; no foe swing lands sooner than
  `regents.token_gap_ms` (600) after another landed on that player, whatever it did; a turn is a whole string,
  given back when the finisher's lock ends. Rests 2 s ± 0.5 s (`FoeDef.rest_ms`, `rest_jitter_ms`).
- **Aim tracks, then locks** (`regents.foe_aim_lock_ms`, 300): the foe stops turning 300 ms before its hit
  lands. FOUND: the referee already judged along the foe's facing AT THE LANDING, and the brain turned to you every
  think, so foes tracked you to the hit (the spec said the opposite; corrected). No template change was needed.
- **The foe bench** shows hits on you a second, the least gap between its own hits, and the group's rule.
- Not done: **loot per minute** (judged once the playtest says how much kills slowed; foe HP untouched).

**How to play it**: restart the game (the play database is republished, data kept). Walk to the skeleton camp.
Two skeletons at most come at you; the third circles. Watch for the red glint on a skeleton's head: that swing
cannot be blocked; roll (Ctrl) or step out late in its wind-up. Hold the right button against the others' lights
(a quarter comes through). The rule numbers are live on the Rules page (`regents.attack_tokens`, `token_gap_ms`,
`foe_aim_lock_ms`); a foe's swings, rest and damage are its `FoeDef` and kit in the Inspector.

**Tested**: genre unit 2843/0 (new: foe kits slow and their finisher unblockable, no weapon wields one, nothing a
player has is unblockable, a kit listing another's ability refused; three skeletons on one player for 30 s: at most
two fight, the third circles, 48 swings never within 600 ms, each takes its turn, a turn is the whole string; the
aim follows a step 450 ms before the hit, holds for one 250 ms before, and turns again after; both negatives: no
gap gives a 0 ms gap, no lock lets the aim follow); native 128/0 (a foe finisher is unblockable, a player kit
has none); **combat playtest 55/0 at 150 ms** (new: blocking against the camp, a finisher glinted, came through
the block in full, 14.0 and 18.7, lights still blocked, 1.75 / 2.0 / 2.75, hits never two together: least gap
608-649 ms over four runs; negative: with `hit`'s rule off the finisher came through at 3.5 and the check failed).
The old playtest's "chop it back" now waits, guarded, for the warrior to step in: a circling foe is out of reach,
and two skeletons kill a player who stands there unguarded.
`load_300.sh` (continent, four referees; the referee session's CPU-heavy sweep ran on this PC for part of it): **300 bots hold every limit** (referee frames 6.9 ms p95, no stalls, the module 39.7 % busy, 64.9 swings a second judged); 200 holds; 100 says BREAKS on ONE referee net stall (714 ms; run again alone: 708 ms), the stall `REFEREE_SCALING.md` already records at 50 and 100 (~30 s after a referee starts), not the foes; both negatives fail as they should.

**Left for later**: the step-2 rules (the finisher's armor, so a player's heavy no longer flinches a foe's
finisher; the parry judged on the seen hit); "Blocked" still floats up when an unblockable hit lands on a
block; the clips are slowed placeholders until `ANIMATIONS.md` §3's foe clips; loot per minute; threat (step 6)
decides who gets a turn first (today: the first to ask).

## Step 27: the combat overhaul, step 2: one string and the guard (2026-10-31)

Luke: "skip the playtest for now: start combat overhaul step 2 (the merged finisher, parry on the seen hit,
riposte, blocks)". `COMBAT_OVERHAUL.md` §3-§4. His three calls before it was built (in `GAME.md`): the riposte
is the string's first step with bonus damage; the parry is front-only like the block; every player has the
weak block until roles come (step 4).

- **One string; its last hit is the finisher** (`KitDef`: `heavy`, `heavy_hold_ms`, `chain_ms` and the kit's
  `combo_window_ms` retired). The sword: Slash 220 ms / 8, Slash 240 / 10, the finisher 380 / 20 (reach 2.1);
  the axe: Chop 320 / 12, the Overhead 550 / 26. Their clips retimed so each hit is where the hand moves
  fastest (`anim/adventurer.tres`; the axe's finisher now plays the old heavy cut's `Sword_Heavy_A`). The heavy
  cut (40004) and the second chop (40007) are retired: a database kept across publishes still has their rows,
  so the server refuses them by name (`RETIRED_ABILITIES`). The sword and the axe kill at a like pace (both
  about 24 a second at 100 %, a string of 38 in ~1.57 s; a native test holds them within a tenth).
- **The finisher** (`hit`, `deal`): armor (never flinched); it flinches a step in its wind-up; landing
  unblocked it STAGGERS (`regents.stagger_ms`). Foes have the same grammar: a skeleton's finisher staggers you.
- **The follow-through** (`KitDef.follow_ms`, one per step, 200 ms): the next step waits for the arc (Luke's
  #8). **The window** is the hot rule `regents.combo_window_ms`, 2 s; a guard press restarts it.
- **The guard** (`guard(on, seen_delay_ms)`; `block` stays for old builds): a press PARRIES a hit in front
  landing within `regents.parry_ms` (200) before it or `parry_late_ms` (50) after, judged ON THE HIT AS SEEN:
  the press's arrival less its trip (half the round trip the server measured, #210; until one is, the
  client's own half round trip, capped by `foundation.press_credit_cap_ms`) and how late the client shows
  another's swing (half a round trip: a swing's animation starts as its event arrives; capped by
  `foundation.rewind_max_ms`). Every hit on a player WAITS for a press still on its way (`held_hit`, a
  private scheduled table, until ~320 ms after the landing), then is dealt as it was judged; an unparryable
  one (unblockable, from behind) waits as long, so hits keep the spacing they landed with (the playtest
  caught a 457 ms gap against the 600 ms rule when only parryable ones waited).
  A parry: nothing dealt, the attacker Staggered, a riposte window. **The whiff lockout**
  (`parry_whiff_ms`, 400): a press that soon after one that parried nothing parries nothing. **Front-only**
  (`guard_arc_deg`, 120°) for the parry and the block. **The weak block** (`weak_block_pct`, 60 % through) for
  every player (`role_of` says Damage until step 4; the Tank's is `block_damage_pct`, 25 %).
- **The riposte** (`riposte_ms` 1 s, `riposte_damage_pct` 150 %): the first step begun inside it; the client
  sees its parry as the attacker Staggered by it just after its press, and the next tap is the riposte. **The
  bow's**: a draw begun in the window is full in `riposte_draw_pct` (50 %) of its time; RMB while drawing lets
  the draw go and parries. The staff's riposte is not built.
- **Heavy, repurposed**: the finisher's stagger ×1.35 (`stagger_time`, on `combo_last`); the old 100 % stagger
  roll is gone. Oak handles still offer it; nothing in a bag changed.
- **Feedback**: "Blocked" only when the guard stopped it (in front, not a glinted swing); "Parried" over you
  when yours lands. The HUD's key line: "LMB Slash - Slash, the finisher ...   RMB tap parry, hold block".
- New tables `guard_state`, `held_hit` (both private) and the `guard` reducer: published with `--codegen`.

**How to play it**: restart the game. Wield the sword or axe: tap LMB for the string; the last hit staggers
the dummy (a gold flash). At the skeleton camp, tap RMB just as a skeleton's swing lands (not when it starts)
and face it: "Parried", the skeleton staggers gold; tap LMB at once for the riposte (half again the damage).
Hold RMB to block what is in front (60 % comes through); from behind it does nothing. The red-glinting
finisher goes through any guard: roll. Every number is on the Rules page (`regents.combo_window_ms`,
`parry_ms`, `parry_late_ms`, `parry_whiff_ms`, `riposte_*`, `weak_block_pct`, `guard_arc_deg`); a step's
damage, wind-up and follow-through are the kit and ability in the Inspector.

**Tested**: genre unit 2857/0 (new: the finisher is the last step and only it; each step heavier and slower;
the retired ids gone; a stray follow-through refused; the 2 s window; the riposte opens on a parry and closes on a
swing or the window; the follow-through holds the next step past the old 60 ms chain; Heavy's stagger x1.35; the
guard's arc twinned with the server's); native 130/0 (new: the parry as seen, with and without the credit; the
deadline; the whiff lockout; the arc; the blocks; the riposte; the press's trip, measured or reported, capped; the
string steps up and the sword and axe kill within a tenth); **combat playtest 60/0 at 150 ms** (new: the
string, the overhead in place, the finisher staggers the dummy, mashing never faster than a follow-through; at the
camp a press a whole wind-up early parries nothing and the light lands in full (8.0); a press 60 ms before a
light lands as shown PARRIES it (the skeleton staggered by us, no damage); the tap after is the riposte, 12.6
(the chop's 8.4 at 150 %); blocking, an unblockable finisher through in full (14.0, 18.7), a light through the
weak block (6.6 = 11 at 60 %); with the back turned a light in full (7.0); foe hits never closer than 593 ms
against the 600 ms rule); integration 1080/2 (new: the string's second only after its first's follow-through,
26.6 off the dummy, the finisher's stagger logged; the retired chop refused; `guard` raises the block and a
second press in the lockout parries nothing; Heavy's 1080 ms stagger; the two failures are outside this step:
the Slain status read after a 1 s corpse went on a busy machine, and the fireball's fire at 6 of ~9);
**load_300 HOLDS** at 50-300 (300 bots: module 38.9 % busy, referee frame p95 16.0 ms, no net stalls,
64.9 swings/s; `land_held_hit` 0.5 ms p95 a call).
**Negatives**, each caught: no lag correction on the press (the playtest's parry failed, 2 tries); the guard
facing everything (the back-turned lights came through blocked: 4.2, 4.8, 6.6); no riposte bonus (8.40, not
12.60); the client never opening the riposte (the unit suite); only parryable hits held (the playtest: two foe
hits shown 457 ms apart: why every hit on a player is held).

**Left for later**: the staff's riposte (a point-blank bolt); the axe finisher's cleave (two targets); roles
(step 4) bring the Tank's full block; a hit held for a parry shows on the player's health up to ~0.3 s after
it lands (the price of judging the parry where it was seen); the clips are placeholders (`ANIMATIONS.md`).

## Step 28: the combat overhaul's first feel pass (2026-10-31)

Luke played steps 1-2 and left three notes in the game (feedback 4097-4099): the refusals "in the middle of the
screen"; "the stagger needs a animation for player and enemy, right now the hits dont have any weight to them
... spamming left click looks weird with the animations"; "players and skeletons can attack or move while
dying". And: "we can adjust values after stagger has visual clarity and animations feel better". His calls for
this pass (in `GAME.md`): a HIT-STOP and a SPARK where the blow lands; no screen shake, no finisher shove, no
sound yet; the foundation's part in the template, then pulled.

- **Refusals to the side** (`regents_hud.gd` `refused`): a small column pinned to the right edge, three at
  most, the newest last; the middle keeps what you got. And fewer of them: a swing or a roll pressed while
  Staggered, Flinched or Slain WAITS on the client (`CombatComponent.can_act`) and goes once you can act,
  where it was sent and refused.
- **The stagger reads**: the Staggered status holds its own clip, `react.stagger` (Q2 `Idle_Shield_Break`, a
  guard knocked aside; `anim/adventurer.tres`), on the player and the skeletons (one set); Flinched keeps
  the quick hit react.
- **Weight**: a SPARK at the chest where the blow lands, facing the attacker (`HitFeedbackComponent.spark`:
  warm, bigger on a hit of 20+, steel on a block, gold on a stagger or your own parry); a HIT-STOP, both
  bodies' animation held `regents.hitstop_ms` (60), a big hit or a stagger `regents.hitstop_big_ms` (110),
  live on the Rules page. The local player's own swing is not held: it played before the server's word, and
  holding it then would stop it a round trip after its blow.
- **Death interrupts at once**: the server cancels a falling fighter's swing and drops its hits held for a
  parry (`die_mid_swing`, from `fell`), and `hit` lands nothing a dead fighter swung. On screen the template's
  driver fades the swing as the fall begins (1.6.7).
- **Swing follows swing** with a cross-fade: the template's second action slot (1.6.7).
- **Template 1.6.7** (DECISIONS #301, `../UMF Template`, pushed; merged here `37e1b136`, pushed; NOT yet in
  Fishing, Fowl Play or DiscGolf): `AnimationDriverComponent.hold_still`, death fading both action slots and the
  upper one-shot, two action slots (`action2` over `action`).
- **The fireball check** (Luke: "look into the fireball's fire dealing 6 instead of ~9"): the game was right.
  A kept server log showed all 12 ticks (9 of fire). The Bolt's hit was 8 s old before the slow test Fireball
  landed, so the skeleton was REGENERATING while the check read its health (+3 to +6). The hook now holds
  regeneration off while it measures, and waits for the fire by the clock. Two other checks were fixed the same
  way: the Slain status read from the server's log (the test's 1 s body went before the read), and a stand-in
  referee re-claimed after the new death check (its 5 s lapsed).

**How to play it**: restart the game. At the skeleton camp: each blow sparks and both bodies catch for a
moment; a parry or a finisher sends the skeleton reeling (a guard knocked aside), gold; mash LMB and the steps
blend into each other; a skeleton killed mid-swing drops it and falls. Pressing while staggered no longer
complains: the press goes once you can act. Refusals show small at the right. Tune the hit-stop on the Rules
page (`regents.hitstop_ms`, `hitstop_big_ms`; 0 turns it off).

**Tested**: unit 2890/0 (all suites, the template's animation ones too; new: a hit sparks, a big hit a bigger spark, a
block a steel one, a stagger a gold one, a heal none; each hit asks a hit-stop, a big one longer; Staggered holds
`react.stagger`, Flinched the hit react; refusals in the right-hand column, three at most, none in the middle;
staggered, a swing waits and goes once it may); native 130/0; **integration 1091/0** (new: a skeleton that swings
and dies before the sweep is judged lands nothing, "91 is dead: its 40001 lands nothing"; the fireball's fire
measured with regeneration held off, 29 of 29; Slain read from the server's log); **combat playtest 60/0 at 150 ms**
with template 1.6.7 under it (the string, the parry, the riposte, the blocks; its bow shots made certain by rule,
since a rolled miss failed one run in twelve: "92 % to hit: wide"); template 1.6.7: unit 2314/0 and three
mutations of the driver, each caught (no slot switch, no hit-stop, no death fade). Published to `regents-rule`
(data kept, no codegen).

**Left for later**: hit reactions from four sides; sounds (Luke: not yet); a per-clip cross-fade time (the
slots fade at the interact clip's 0.15 s); 1.6.7 into the other three games; the values (Luke: after the feel).

## Step 29: the combat overhaul, step 3: statuses that stack (2026-11-01)

Luke, going to bed: "finish any pre role work that needs done". `COMBAT_OVERHAUL.md` §9 step 3, the one step
of code the order puts before roles (its decisions for roles are `ROLES_PREP.md`, his to answer).

- **Template 1.7.0** (`../UMF Template`, DECISIONS #302, pushed; merged here `19cb55a6`, pushed; NOT yet in
  Fishing, Fowl Play or DiscGolf): EFFECTS, statuses held alongside an entity's one state (`status_effect`,
  public, a cell and follow table; `effect_expiry`). `add_effect_internal` / `remove_effect_internal` / the
  authority reducer `set_effect`; the same effect again refreshes it. What an entity may do is its state's and
  every effect's: it moves as the STRICTER (`status::stricter`, mirrored by `StatusComponent.movement_config`),
  acts only if all let it (`require_can_act`; `StatusComponent.can_act()`), is hit only if all allow
  (`is_hittable`).
- **Here**: the Frost Ring's Slowed is an EFFECT (`add_effect_internal`), so a slowed skeleton's own swing
  (Swinging) or a stagger no longer wipes it; arrows and spells ask `is_hittable`; the combat component's
  `can_act` reads the state and the effects. Published with `--codegen` (data kept).
- Ready for roles: Shielded, Weakened and a Support's help can now be effects beside Blocking or Swinging.

**How to play it**: restart the game. Frost Ring a skeleton: it stays slowed while it swings at you.

**Tested**: template 1.7.0: unit 2324/0, native 93/0 (the stricter of two bounds), integration 667/0 (effects
beside a state, refreshed, two at once, a timed one off alone, off and off again refused, one that cannot act
stops an ability, a step clamped to its crawl), e2e 47/0 + 11/0; two mutations (the client ignoring effects, a
`stricter` that loosened), each caught. Here: unit 2900/0 (one re-run: the workbench's 300 ms cooldown check
slipped once on a loaded machine), native 131/0, **integration 1146/0** (new: the Frost Ring's Slowed lands as an
effect and stays while the skeleton swings), **combat playtest 60/0 at 150 ms** on a client subscribed to effects.
Published to `regents-rule` with `--codegen` (data kept).

**Left for later**: an effect's own pose or tag on screen (today a genre shows effects through
`effect_changed`); 1.6.7 and 1.7.0 into the other three games.

## Step 30: the combat overhaul, step 4: roles by the handle, the sword first (2026-11-01)

Luke answered `ROLES_PREP.md` (2026-11-01, in `GAME.md` "Roles, settled before building them"); this builds
`COMBAT_OVERHAUL.md` §9 step 4 for the sword, exactly as settled. SHOW, DON'T NAME: the roles' names and
"finisher" are in code and docs only; the player sees a badge and what a handle does.

- **Three handle shapes** (`content/pattern/crossguard_hilt.tres` 40010, `banner_hilt.tres` 40011; Make the
  table): the plain grip is today's handle (Handle 40013, Oak 40016, Yew 40017: the plain role); Crossguard hilt
  40040, Oak 40042, Yew 40044; Banner hilt 40041, Oak 40043, Yew 40045, each with its wood's trait. Recipes
  40032-40037, the same cost, time and Crafting rank as the handle of the same wood. `fits_kit` "sword": an
  axe or a pickaxe refuses one. One mesh. Listed under Handles at the workbench.
- **`RoleDef`** (new type, `content/role/`: damage 40001 the plain one, tank 40002, support 40003): the guard
  (full: `block_damage_pct`; light: `weak_block_pct`), threat (`threat_pct`, or a live rule:
  `regents.guard_threat_pct` and its scope `regents.guard_threat_bosses_only` for the guard handle; healing
  draws no more than damage), the drop weight's rule, a badge (shape and color) and its guard in words.
  THREAT IS STORED, NOT USED (step 6): `role_threat_pct`, `rules::threat_pct`, `heal_threat`; `FoeDef.boss`
  added for the scope (no foe is one yet).
- **The role map on `KitDef`** (`roles`, a `KitRole` each: role, last hit, `stagger_pct`, `heal`,
  `heal_radius_m`, `does`): the sword's Piercing thrust (40003, retuned: 26, 2.4 m, 380 ms), Pommel bash
  (40022: 14, 340 ms, stagger x1.5 = 1.2 s), Rallying cut (40023: 14, 400 ms, a sweep of 0.9 m against 0.5,
  heals players within 6 m for 8; you all 8 alone, `regents.rally_self_share_pct` with players near).
- **Clips** (`anim/adventurer.tres`; `ANIMATIONS.md` §5), each wind-up where the hand moves fastest (measured on
  the bones; the unit suite now measures it too): Pommel bash Q2 `Melee_Hook` x0.735 (340 ms, lock 635), Rallying
  cut `Sword_Heavy_C` x1.21 (399 ms, lock 579). The thrust keeps `Sword_Light_C` x1.18: Q2's real thrust
  (`Sword_Light_D`) holds the arm out 1.3 s, a 2.1 s lock.
- **The server picks the last hit** (template 1.7.1, DECISIONS #303, `resolve_ability`): pressing the string's
  last step fires the one the wielded weapon's handle gives (`role_of`: its parts, `"p"`), whatever the client
  asked for; an older build always asks for the thrust and gets its handle's. The client predicts the same
  (`CombatComponent.role()`, `KitDef.light_at`): the clip and the lock.
- **The guard by role**: `blocked_damage` reads the role's `full_block` (the crossguard: 25 % through).
- **Re-hilting** is the refit at the workbench: the new hilt used up, the old one lost, plus 2 bars.
- **Drops** (template 1.7.1 `loot_data`): a dropped weapon of a kit with roles rolls a plain-wood handle by the
  roles' weights (`regents.drop_handle_damage_pct` / `_tank_pct` / `_support_pct`: 50 / 25 / 25). NO LOOT TABLE
  DROPS A SWORD YET: dormant until one does (Luke's loot to decide).
- **UI** (`game/regents/ui/role_badge.gd`, `RegentsRoleBadge`): the craft window's handle list badges each handle
  and says under the row what the picked one does (the refit too); the bag puts the badge in a sword's corner,
  and its tooltip and detail name its last hit and say what the handle does; the HUD key line names the string
  by its moves ("LMB Slash - Slash (second) - Pommel bash   RMB tap parry, hold for a full guard"). No role word
  anywhere (the unit suite checks every line for one).
- **No table or reducer added** (a "once a swing" table for the heal was dropped: `resolve_action` lands one
  hit a swing), so no `--codegen` and the schema fingerprint did not move: friends' builds keep connecting.
- The native "the sword and the axe kill at a like pace" check is restated for roles: the plain sword kills
  fastest (the +30 % thrust), the other roles slower, the roleless axe inside that range.

**Not Luke's, chosen to build it (his to confirm or change)**: the live rules' first values (the guard handle's
threat 250 %, every foe; the rallying cut's own share with players near 50 %, the sheet's "half"); the rallying
cut heals only off a foe, not a training dummy (as Thirsting); the pommel bash's and rallying cut's reach 2.1 m
(today's last hit's; his table left them blank) and the rallying cut's sweep 0.9 m for "a wider arc"; "holds the
foe" built as the longer stagger alone; the badges (a point, a shield, a cross; warm, steel blue, green); the
words (each `does` line and guard words); dropped handles are the plain wood's (no trait); the placeholder clips.

**How to play it**: restart the game (the play database is republished, data kept). Make a sword at the
workbench and pick its handle: each shows its badge, and the line under it says what it does. Or re-hilt a
sword you have (it is listed under Refit). Wield it: the key line names your string's last hit. At the dummy
the crossguard's pommel bash staggers it longer; at the skeleton camp hold RMB with it and a light barely
scratches; with the banner hilt, land the string's last cut on a skeleton while hurt and you mend 8. The Tester
page gives any hilt (40040-40045). Live: `regents.guard_threat_pct`, `guard_threat_bosses_only`,
`rally_self_share_pct`, `drop_handle_*_pct`.

**Tested**: genre unit 623/0, all suites 2953/0 (new `_run_roles`: three roles, one plain; the guards; threat live;
each sword last hit per role and only the last step changes; every last hit the finisher to traits; Luke's numbers;
the server's baked locks equal the client's; EACH LAST HIT'S CLIP HAS ITS HAND FASTEST AT ITS WIND-UP, measured on
the bones; the hilts fit a sword and not an axe (nine handles against three); a weapon's role from its parts;
badges distinct; every line on screen free of role words; the craft window's handle list badged with its line, an
axe's neither; the bag's corner badge, tooltip and detail; negatives: a role naming itself, an undeclared rule,
two plain roles, a role map with the plain role not last, a step reused, a role named, no plain role, a shaped
part that is no part; mutation: the pommel bash's wind-up set to 300 was caught, 2 failures). Native 135/0 (new: a
handle's shape is its role, the hilts' ids, costs and fit; each role's last hit and Luke's numbers; the drop roll
50 / 25 / 25, live, none for an axe; threat and its scope, healing no more than damage, the rally's own share; the
like-pace check restated for roles). **Combat playtest 90/0 at 150 ms** (new: two swords re-hilted at the
workbench through its window, the handle list badged and its line read; each of the three handles wielded, its
key line, its last hit PREDICTED by the client and FIRED by the server, its clip, its damage 29.38 / 15.82 /
15.82, its stagger 800 / 1200 / 800; the bag's three badges; the crossguard's full guard at the camp: lights
through at 1.75 / 2.0 / 2.75; the rallying cut landing on a skeleton heals you 8). Mutation run: the client
predicting the plain last hit (A) and the server's `role_of` always plain (B) together failed 10 checks (A: the
prediction, the clip; B: what the server fired, the damage, the 1.2 s stagger, the full guard). Integration: every
roles check passed in each of the last seven runs; the best whole run 1279/1 (run 7; its one failure, the Frost
Ring's circle, fixed and passing since); the last, 1185/5, all five in the combat section's oldest axe checks (a
chop's answer expiring behind slow calls; a roll that must land inside a 550 ms wind-up), which need sub-second CLI
calls the busy local server no longer gave (each call 0.5-1 s by the end). NOT a clean green run: those two want
the same hardening (answer the chop before the overhead; the roll sent over HTTP or retried) (new: a hilt in an axe refused; re-hilting keeps the quality, uses the hilt, LOSES the old one;
an old client's thrust fires the crossguard's pommel bash, its lock 635, 14 dealt, 1.2 s stagger; a plain sword
asking for the pommel bash fires the thrust; the pommel bash first in the string refused; the rallying cut heals
nothing off a dummy, 8 off a foe alone). Template 1.7.1: `cargo check` (wasm) and `cargo test` green.
The playtest's older camp checks were hardened while this ran (they read one skeleton when the sweep hit its
neighbor, gave up while the player was staggered, or stopped the block phase at 45 health after ~5 s): each now
reads every skeleton, waits until the player can act, and keeps the phase going with the shell's heal. So were
the integration suite's older wall-clock checks, which a ~1 s CLI call had begun to miss (they passed in the first
two runs, failed in later ones): the roll is sent 0.3 s behind the overhead it must cancel; a stagger is read from
its status's own log line; the foe section and each string get a fresh stand-in referee (online 5 s after a claim)
and hold regeneration off while measuring; the slow's "a state no longer wipes it" is read from the effect's on/off
log times; the Frost Ring's circle from the server's own times (the cast's end, the circle's landing: 1 s apart);
the Fireball's stand-in referee is claimed once, before its cast (a second claim after it revoked the first,
and on a slow CLI the cast landed with no referee and no missile); and the foundation's push check (template
1.7.1, mirrored) reads its 5 s push first.

**Left for later**: threat targeting (step 6) and the guard handle's "foes come for you"; the rallying cut's share
with players near played by two clients; a loot table that drops swords; real clips for the three; the axe, bow
and staff role maps (step 7); a hilt's own mesh.

## Step 31: Luke's look at roles: the hit's light, the swing's return, the stagger (2026-11-01)

Luke, after playing step 30: the glint and the hit spark "are just billboards with no texture"; "the end of the swing
animation transition back to the idle/locomotion animation is instant ... swing -> snap back ... feels rushed"; "a
status bar under the enemy hp ... so the player can see how long the enemy is staggered for (with heavy trait plus
tank handle, hard to know what the time is with both modifiers)"; "the enemy keeps moving while staggered ... a stagger
should keep them in one spot and dazed animation for the length? we can experiment with both"; and the workbench
showed "two handle sections".

- **The hit's light** (`combat/hit_feedback_component.gd`): FOUND the squares were every ember drawn a whole meter
  wide: a billboard ignores its node's and particle's scale unless `billboard_keep_scale` is on. Now every spark,
  streak and glint is SOFT LIGHT (a round fall-off texture, `soft_light()`), embers fade over their life, the glint is
  a red STAR (a core and two crossed streaks, drawn over rather than added, so it stays red on a pale skull), and the
  body's flash is a RIM of light round its edge (`_rim_shader`), not a flat white wash the bloom blew into a block.
  Checked by renders of the dummy hit and glinted.
- **The swing's return** (`combat_component.gd`, `anim/adventurer.tres`): each strike clip is followed by its own
  recovery (the Quaternius `_Rec` clip: `recover.<ability id>` in the set, at the strike's speed), cross-faded in
  through the second action slot 0.15 s before the strike ends. Presentation only: the lock is still the strike's, so
  the pace (and the server) is unchanged; moving or the next swing cuts the recovery. Every body's swings, the
  skeletons' too. 13 strikes have one (the lunge's clip has none).
- **The stagger shows its time**: under the target's health, a draining bar for each status done to it ("Staggered
  1.1 s"), and every effect ("Slowed"); never its own swing or block (`regents_hud.gd`, `status_rows`). It needed the
  foundation's `StatusComponent` to say a status's whole length and an effect's time left (`seconds_total`,
  `effect_seconds_left`, `effect_seconds_total`): template 1.7.1, uncommitted, mirrored here.
- **The stagger roots and dazes** (`content/status/staggered.tres`): speed 0 (was 0.4); the guard knocked aside plays
  once (`react.stagger`, the hit feedback's), then a dazed sway is held for its length (`react.dazed`: Q2
  `Zombie_Idle`, a groggy, hunched sway). The player's and the skeletons' alike. To try it moving: `speed` on the
  Staggered status (0.4 was the old), then bake and publish.
- **One Handles heading**: the hilts' patterns sorted after the pickaxes, so a second "Handles" heading came further
  down; they now sort with the plain handle (`SkillingComponent.group_pattern`). The unit check had missed it (it found
  headings by node name, and Godot renamed the second): it now reads every heading in order.

**How to play it**: restart the game. Hit the dummy: a streak and a spray of embers, the dummy rimmed in light. A
skeleton's red-glinting swing shows a red star at its head. Swing the string and stop: the arm comes back down. Parry a
skeleton or land the pommel bash: it stands swaying, dazed, rooted, and the bar under its health counts the stagger
down. The workbench lists Handles once, the hilts with them.

**Tested**: all unit suites 2973/0 (new: the stagger rooted and dazed, its reaction once; 13 strikes with a recovery at
their speed, each clip in the library; the target's status bars: two at once, the longest first, its own swing none,
a status with no end none; the workbench's headings each once and the hilts under Handles: with the old sort the check
failed, "Handles" twice). Native 135/0. **Combat playtest 95/0 at 150 ms** (new: the overhead blends back through
`Sword_Heavy_A_Rec`; a parried skeleton stands rooted, 0.00 m, in the dazed sway; under the dummy's health its stagger
shows and drains, for each of the three last hits). Integration not run again this round (the change to the server is
the Staggered status's speed; the integration's stagger checks read its time). Published to `regents-rule` (no codegen).

**Left for later**: Luke's call on the handles (below in GAME.md: one family of shaped handles for every tool and
weapon, or as now); a real dazed clip (`ANIMATIONS.md`); the tutorial (next).

## Step 32: one family of grips for every tool and weapon (2026-11-01)

Luke chose option (b): "one family of three shapes (grip, guard, banner) for every tool and weapon; a shape only
matters when swung".

- **Names** (Make the table; ids kept): the plain handle pattern is the GRIP (items Grip 40013, Oak grip 40016, Yew grip
  40017); the shaped ones are the CROSSGUARD GRIP (40040, 40042, 40044) and the BANNER GRIP (40041, 40043, 40045). The
  patterns' keys (`handle`, `crossguard_hilt`, `banner_hilt`) are internal and unchanged. The workbench lists them under
  Grips.
- **Every tool and weapon takes any shape**: the shaped patterns no longer name `fits_kit` (the mechanism stays, for
  content that wants a part for one kit; unit and native negatives keep it honest). An axe or a pickaxe lists all nine.
- **A shape matters only where it is swung with roles**: the server's `role_of` gives the shape's role only to a weapon
  whose kit has a role map (the sword); a crossguard axe guards as any axe. The client already showed no badge or line
  for a kit without roles. Tools as weak weapons (a pickaxe's own kit) are later (option (c)).

**Tested**: all unit suites 2974/0 (the axe's grip slot nine, no badges; the plain and shaped grips fit sword and axe; a
part for swords alone fits no axe); native 135/0 (nine grips fit an axe; a sword-only part fits no axe or pickaxe);
combat playtest 95/0 at 150 ms (the rallying cut's +8 now read from each health update: a skeleton's hit in the same
frame hid it once); skilling playtest 63/0 + 7/0 (it makes a Grip and an Oak grip). Integration: its roles section's
"a crossguard in an axe is refused" became "is taken"; not run again this round. Published to `regents-rule`.

## Step 33: the tutorial's first pass: make your own sword, then fight with it (2026-11-01)

Luke: "a walk through with crafting + combat to teach the basics", then two answers: MAKE YOUR OWN SWORD first, and
PROGRESS ON THE SERVER. With T1-T5 (ROLES_PREP.md §4-5): the camp's yard, offered, mostly play, a few words, the first
friendly NPC, the parry ring in the yard only.

- **Lessons are content** (`LessonDef`, `game/regents/content/lesson/`, fifteen, ids 40001-40015): each its place in the
  run (`order`), the deed that ticks it (`done_when`: gathered, made, wielded, the string's last hit, a roll through a
  swing, a parry, a strike back, a held guard, a roll through the glint, a shaped grip's last hit), the item it wants
  (or any of its kind: any grip, any sword), where it sends you (`at`, a level point) and the guide's few `words`. Its
  checks: words naming a role or "finisher" are refused, an item where the deed names none, a kind with no item, a
  weapon that is none, two at one place. The run: Chop wood, Carve a grip, Mine copper, Smelt copper, Smith a blade,
  Smith rivets, Make your sword (pick the grip's shape), Take it in hand, Three in a row, Roll through, Parry, Strike
  back, Hold your guard, The red glint, Your grip.
- **The server ticks them** (`server/src/game/regents.rs`, "the tutorial"): a `tutorial` table, one row a character
  (state offered / under way / finished / set aside, the lessons done, reminded), each player sent only their own;
  `lesson_done` called where each deed happens (a node's yield, a station's make, `wield`, the last hit's stagger,
  `parried`, the riposte, a block, and a ROLL THROUGH: a foe's swing the referee judged a miss while the player was
  rolling in its reach, `on_ability_missed`); any lesson not yet done is ticked, in any order. (A first try judged the
  roll by the swing's nominal landing; at 150 ms a roll begun as the blow is seen starts after it, so the playtest
  never ticked: the referee's miss is the truth.) `tutorial_begin` (at a guide only; finished, from the start), `tutorial_set_aside`. A new
  character, and one from before, is offered it; one who set it aside is offered it again after a death, once.
  Add-only: published with `--codegen`; older builds keep playing.
- **The Drillmaster** (`content/character/guide.tres`, kind 120): stands on the glade's `guide` point by the yard
  (a private `guide` table says which); nobody can hurt them. E on them: their offer (`TutorialComponent.greeting`,
  editable in the Inspector on the adventurer's Tutorial node); E again begins; N sets it aside.
- **The sparring skeleton** (`content/foe/sparring_skeleton.tres`, kind 105, on `sparring_1`): the warrior's model,
  its own kit (`sparring_sword`: 950, 950 and a 1200 ms glinting overhead), 10 % damage, no XP or loot, notices you at
  4 m. `FoeDef.parry_ring`: a ring closes on each of its swings, shut as the blow lands (`HitFeedbackComponent`); it is
  the only foe with it.
- **The card** (`ui/tutorial_card.gd`): left of the screen under the bag's line: offered, where the guide is; E on them,
  their words and the keys; under way, the lesson now ("Chop wood   1 / 15") in the guide's words; each tick a green
  "Done: ..." notice; the last, the farewell.
- **The continent** copies the glade's camp: its generator takes the new `Yard` group too (rebuilt; only the camp's
  cell and the scene changed besides Godot's random node ids, which were put back).

**How to play it**: restart the game (a new table). A new character sees the card; walk to the Drillmaster by the
training yard (west of the dummies), E, E. Make the sword at the furnace, anvil and workbench as the card says; take it
in hand (I); then the yard: the dummy for three in a row, the sparring skeleton for the rest. N sets it aside.

**Not built yet** (next passes): the minimap pointing to a lesson's `at`; the "two foes" lesson (ROLES_PREP §4.6); the
guide facing the yard (its yaw is the point's hash, as every placed thing's); a private copy of the yard; the yard on
the expanse (a test world, not rebuilt).

**Tested**: unit 3062/0 (the lessons as content and their checks with negatives, the component reading its row, the
card's words with no role names, the partner's clips and slowness); native 137/0 (the run, kinds and their negatives,
ticks once, finishing; the roll's miss rule and its negatives; mutations of `ticked_by` and the roll rule each failed
it); integration 1225/0 (the guide and partner placed; begun away from the guide refused, twice refused, set aside and
taken; the suite's own real work ticked six lessons; set aside, a wield ticks nothing; the death's reminder once; a
blade smithed in a round ticks; the level change takes the guide and partner away); skilling playtest 73/0 + 8/0 at
150 ms (E on the guide, the offer, begun; the chain's work ticks its lessons; a copper sword made, blade and sword
ticked; the buddy offered, not begun); combat playtest 108/0 at 150 ms (the yard: parry, strike back, held guard, roll
through, the glint, three in a row, each the server's tick; a ring over each of its swings' wind-ups). Published to
`regents-rule` with `--codegen`, then again for the roll's miss rule.

**Luke's to decide**: the guide's and lessons' words (first drafts); the partner's numbers (950/950/1200 ms, 10 %,
notice 4 m); whether the sword lessons should give the copper (a new character must mine 8 ore); whether "Your grip"
should ask for a re-fit when the sword was made with a plain grip (it does now: "give your sword a crossguard or a
banner grip at the workbench").

**Luke, 2026-11-02**: no "Staggered" word over the foe's body (the status bar under its health says it, and how long);
a stagger still flashes gold and sparks. `HitFeedbackComponent.said` records the words (a unit check, with "Blocked"
still said as its negative). Client only: no publish.

**Luke, 2026-11-02, the banner grip's last hit "looks more jumpy"** than the other two: its clip (`Sword_Heavy_C`) began
turned away, so the blend from the second slash whipped the body round (the chest 1258 deg/s in the fade; the thrust
604, the bash 815). Now `Sword_Light_D` at 0.75, a wide sweep facing forward (279 deg/s), cut into a strike and a
recovery by `game/regents/tools/cut_clips.gd` into the game's own library (`anim/regents_cuts.res`, named `cuts` in
the set): its lock 667 ms (was 579; baked, published). The regents suite holds every last hit's fade-in to 1000 deg/s
(the old clip, its negative, fails). And his stagger question (tank plus Heavy staggers almost forever): the options
are in `COMBAT_OVERHAUL.md` §8, his to choose.

## Step 34: poise, shown on the target marker (2026-11-02)

Luke: "tank sword seems too strong as the heavy trait plus its role allows for almost infinite stagger. even the
normal stagger is a lot when fighting one enemy"; then, of the options (`COMBAT_OVERHAUL.md` §8): "lets try option A
with short B after each"; for showing it, not a bar under the health: "lets do target marker".

- **Poise** (`server/src/game/regents.rs` `wear_poise`, `steady`; the rules `genre/regents/mod.rs` `poise_hit`,
  `poise_now`): a foe's (`FoeDef.poise`, 70 for all three) or a dummy's (`regents.dummy_poise`, 50: any weapon's first
  string breaks it). Every melee hit wears it (`regents.poise_light` 10; the string's last `regents.poise_finisher` 40);
  only the last hit can break it, a light stops at 1. Broken: whole again, the stagger as before (the pommel bash's
  ×1.5), then **Steadied** for `regents.steadied_ms` (3 s) after the stagger, when nothing wears it. Unhit for
  `regents.poise_regen_ms` (8 s; at 3 s one fighter's strings never added up) it is whole. A parry staggers whatever
  the poise; a player has none (a foe's last hit staggers you as before). FoeDef.poise 0: the old rule.
- **Heavy** now wears 35 % more poise with the last hit (`poise`), not a 35 % longer stagger; its words: "the third
  blow knocks a foe off balance sooner (35% more)". With 70 poise: a plain sword string (10 + 10 + 40) leaves 10, the
  next one breaks it; a Heavy one (10 + 10 + 54) breaks it at once.
- **The target marker** (`CombatComponent._place_poise_arc`, `HitFeedbackComponent.poise_worn`): an arc just outside
  the ring under your target fills clockwise from the front as its poise wears, pale turning red near the break; it
  bursts as it breaks and is gray while Steadied; nothing for a player. Its state is the public `poise_state` table
  (by cell, as every placed thing of ours); the private `poise` table published an hour before it is retired, kept
  declared (a published table is never removed).

**Tested**: native (poise_hit: lights stop at 1, the last hit breaks, Steadied wears nothing, Heavy breaks 70 in one
string; poise_now), unit (Heavy's poise and words; the marker's reading: worn, whole again unhit, steadied, a burst once
and not twice), integration (a real referee: a chop wears 10 of 60, the last hit leaves 10 and no stagger, a light stops
at 1, the next last hit breaks and staggers, Steadied a chop wears nothing, Heavy breaks a fresh 60 in one string; the
older stagger checks run on a dummy without poise), combat playtest (a chop fills a fifth of the arc; broken, the arc is
gray; the yard's three in a row breaks the partner). The camp phases now bring a slain player back (three skeletons
killed it once). A render of the arc at 30 / 75 / 98 % and Steadied checked by eye.

**Luke's to tune** (live rules and FoeDef): poise 70 / dummy 50, wear 10 and 40, Heavy x1.35, Steadied 3 s, regrowth
8 s. Players without poise for now.

## Step 35: Luke's play of 2026-11-03 (feedback #8193-#8196); the armor prep sheet (2026-11-03)

Four notes sent with F8 while hosting (`tools\feedback.cmd` has them, with the frame and ping numbers of each).

- **#8194 / #8195 "lag spikes ... common short freezes", "fps stuck at 50-70, dropping to 30s"**: not the server
  (0 network stalls, ping ~40 ms). The perf reports showed single frames of almost exactly 139 or 208 ms, up to 100 in
  30 s, in two bursts; the chronicle placed both by the WORKBENCH (4, 15), none at the anvil 4 m away. The station
  window looks again every 500 ms (`RegentsStationWindow.refresh`) and its list's sort compared recipes by
  `SkillingComponent._order_key`, whose `group_pattern` (the handle shapes, PROGRESS 32) called
  `MaterialTable.patterns()`, which listed the patterns folder from disk (`ContentLibrary.items`) on every comparison:
  **199 ms a look** at the workbench. Fixed: `MaterialTable.materials()`/`patterns()` go through `RegentsContent` (the
  genre's cache; it now also skips its cache while `ContentLibrary.root_override` points at a scratch project, where a
  test writes content), and the sort computes each key once. A look is now under 4 ms; the HUD's prompt facing a
  station (written every frame) under 1.5 ms.
- **#8193 "need to be able to cancel out of anvil minigame if you accidentally started one, maybe for all games, for
  harvesting can reward what we get, for refining/crafting can just cancel and not use resources"**: built as he said.
  **Escape during a round leaves it** (`RegentsHud._input` / `leave_round`, before `MouseCapture`, so the menu does not
  open; a line under the time bar says what Escape does). A GATHERING round (chop, crack) ends at once and sends what
  was played: their scores count only the work done (clean chops, hits over a target), so it pays what was got, no
  more. A REFINING or CRAFTING round (smelt, shape) is withdrawn by the new reducer **`round_cancel(challenge_id)`**
  (`server/src/game/regents.rs`; rate `round_cancel` in `shared/rules.json`): inputs are only taken when a round
  resolves, so nothing is used and nothing made ("Stopped: nothing used."). It refuses a gathering round, a round that
  is over, and someone else's.
- **#8196 "Sparring skeleton walks right through the copper mine ore"**: found, NOT fixed (needs the foundation). The
  referee builds only the NPCs it drives; nodes and stations exist there only as the foundation's wall boxes
  (`EntityDefinition.blocker_size`, DECISIONS #229), which no Regent's definition sets, so every foe walks through every
  rock, tree and station (the player is stopped by the client's own hulls, `RegentsSolid`). One box per definition
  cannot fit both a 0.9 m trunk and a 3.2 m rock (all nodes are kind 100), and changing kinds would strand every node
  already in the play database. Proposed to Luke: a template change so a genre sizes a referee's wall per entity (a
  rock its footprint from its NodeDef, a tree its trunk, a station its box), with the walk map routing round them.

**Tested**: unit 3081/0 (the workbench window's look under 4 ms: it failed at 199.39 ms before the fix, the negative;
the prompt under 1.5 ms; leaving a crafting round forgets it here, a gathering one is not withdrawn); native
`cargo test` 138/0 (the full set, the first since poise); integration (`round_cancel`: a gathering round refused, a
round that is not there refused, an anvil round left: gone, both bars still in the bag, no head, and it cannot be sent
after; the suite 1284/20 then 1289/25, every
failure a CLI-timed referee check, both runs while Luke's host ran on the same server: to rerun with it stopped). Not run: the skilling and combat playtests (no flow they drive changed but Escape, which they do not press).

**The armor prep sheet**: `docs/regents_rule/ARMOR_PREP.md` (A1-A10, each with options and a recommendation), for
Luke's answers before any armor is built.

**Left**: #8196 (the template change above, Luke's go-ahead); the foundation's `content` check "a script runs from the
repo root" failed 2 of 5 unit runs here (it waits 600 headless frames for Git Bash under load: flaky, a template fix).

## Step 36: foes stop at rocks, trees and stations (#8196, template 1.7.2) (2026-11-04)
Luke, 2026-11-04: "Lets get everything up to date and committed/pushed so we can fix the walls on the map". Template
1.7.1 and 1.7.2 (DECISIONS #303, #304) were committed and shipped to every game, this repo's steps 26-35 committed
first; then Regent's half of #8196 ("Sparring skeleton walks right through the copper mine ore").

**Built**:
- `sidecar/genres/regents.gd` (in `tools/template/genres/regents.paths`): Regent's say to its referee (`RefereeGenre`).
  It sizes nodes (kind 100) and stations (kind 101) per entity, from the same numbers the client builds its collision
  from: a ROCK, the box of each mesh of the model `NodeComponent` picks for that entity id, times `model_scale`
  (measured once per model); a TREE, its trunk only (`NodeComponent.TRUNK_RADIUS` x `model_scale`, `TRUNK_HEIGHT`
  tall: new constants the client's cylinder now reads too); a STATION, its body box and each piece's meshes where its
  StationDef places them (the client's fallback box with neither). It reads `gather_node` and `station` (the referee is
  sent them for it), and puts up nothing until the entity's row has come.
- `content/character/node.tres`: Blocks In = [Normal], so a worked-out node (Depleted, 100: rubble, a stump) puts up
  no wall and the walk map is baked again round it; `blocker_size` stays zero (the genre sizes).
- No table, reducer or client change (the trunk constants are the same numbers); the play database republished (the
  content manifest moved). Restart the game and its referee.

**How to play it**: a skeleton chasing you round a copper rock, a tree or the anvil goes round it now, where it walked
through. Work a rock out and it walks over the rubble.

**Tested**:
- Unit (the regents suite, `_run_referee_walls`): the genre loads as the referee loads it; each of the copper and
  iron rocks' models, the tree and the four stations: the referee's walls cover the client's own hulls and are no more
  than 15 % wider; nothing before a row, nothing with no def; the node's wall up in Normal and down in Depleted.
  Its negative: the rock scaled to 0.6, a 0.3 m trunk and a station with no body fail 7 checks. Full sweep 3138/0.
- `game/regents/tests/walls_playtest.sh` (new): the world's real referee in the glade, a bot patrolling along z = 14
  straight through copper rock 20 at (23, 14): standing, it crossed the rock's line 2.30 / 2.33 m off its lane both
  ways and reached each end; worked out (status Depleted), the map was baked again and it walked straight through
  (0.08 / 0.00 m off). 16/0. Its negative: with `sidecar/genres/regents.gd` taken away (Luke's bug), the walk map had
  0 wall boxes and the bot crossed through the rock (0.00 m): 4 checks fail.
- Integration 1268/15, run with no host on the server: the same CLI-timed referee checks as step 35's 20 and 25 (the
  overhead's cancel race and what cascades from it, mana regrown between calls) and the hold tick; to harden.

**Left**: the continent with busy mines: a node worked out or back re-bakes its 256 m walk map tile (1 s after, at
most every 5 s a map, one at a time); not measured under `load_300.sh` (watch for `[Sidecar] a walk map ... again`
lines piling up). The template's walk map read of the level warns that it parses visual meshes at runtime (once per
area, kept): a template look if the continent's reads are slow.

## Step 37: the integration suite's referee checks hold on a busy machine (2026-11-04)

**Why**: integration failed 15 to 26 of its referee checks every run (1268/15 with no host running), all on the CLI's
pace, not the game's: a `spacetime call` takes 0.5 to 3 s to start here. A stand-in referee claimed by an anonymous
CLI call counts as there for 5 s and never beats again, so a string outlasted it; a request runs out 3 s after it is
due, a missile lives 3 s, a cast is 1 s, a string's window is 2 s, a dummy is whole 4 s after its last hit, and the
CLI's calls between the two ends of each ran past them.

**Built** (tests only; no game, table or rule change):
- `game/regents/tests/timed_calls.py`: steps sent over one kept-alive HTTP connection with the CLI's own token, each a
  set number of ms after the last; `sql NAME <query>` / `sqlwait NAME <query>` steps read a value the next steps use
  as `{NAME}` (a request's id, a missile's id).
- `game/regents/tests/hooks/integration_genre.sh`:
  - `standin_up CODE LABEL` / `standin_down`: a stand-in referee minted over HTTP that beats twice a second until it
    is let go, in place of every offer + anonymous claim (and the "a fresh referee: the last one lapsed" dances).
  - `timed`, `timed_ok`, `timed_refused`, `timed_val`, `num_is`; `hits LABEL TARGET ABILITY:PREDICTED[:MS] ...`: a
    string of swings, each answered at once and the target's health (and `HITS_READ`) read after each answer.
  - In timed runs: the first string (chop, overhead, Cleave in its hold), the roll that cancels the overhead, the
    traits' and poise's strings, the dying skeleton's swing, the slaying chop, the Bolt and the Fireball (cast, reads
    while it goes, its missile's hit, the burn, the price, its cooldown), Frost Ring let go 200 ms in, and Frost Ring
    again (its circle's times, its Slowed, the skeleton's swing while Slowed, then Blink).
  - The camp's respawn 40 s for the test (was 15: the checks between the kill and "the camp waits" took longer).
- Template 1.7.3 (tests only, merged here): `tests/integration_test.sh` looks for the hold tick while the first
  helper holds alone, and a failed call names the server's words, not the CLI's "UNSTABLE" warning.

**Tested**: integration 1328/0, then 1328/1 (the template's timed-press check: fixed in 1.7.3), then 1298/0 (the
count moves by about 30 between runs, as it did before: loops over random rolls). Its negative: the Cleave sent past
the overhead's hold and the roll past its wind-up (the run otherwise the same) fail exactly "Cleave ... refused", "the
overhead is canceled" and "no damage" (481.8). The first negative showed "no damage" passing anyway (read by the CLI
after the dummy was whole again): it is read in the run now. Template integration 667/0.

**Left**: the integration suite still takes ~25 min (the CLI's pace); the remaining CLI-timed checks pass with room.

## Step 38: American spelling, and armor parked (2026-11-04)
**Why**: Luke, 2026-11-04: "all spelling in the game is not English version, but American" (`GAME.md`). The same
sit-down parked armor (`ARMOR_PREP.md` §0) and set the order of work: this pass, the minigame overhaul, herbalism
and hunting, then armor.

**Built** (no game rule, table or behavior change):
- Every genre file (the manifest's, less the GENERATED level cells, `continent.tscn`/`expanse.tscn` and bakes), plus
  `GAME.md`, `CLAUDE.md` and this repo's rules: about 370 words in 53 files (most: color, armor, center, gray,
  canceled, meter, mold), by a word-by-word map of British to American
  forms (snake_case and camelCase parts, case kept).
- `ARMOUR_PREP.md` renamed `ARMOR_PREP.md`, every link with it.
- Genre-only code names renamed with their uses: `CombatComponent.swing_canceled`, `RegentsMinimap.color_of`, the
  HUD's status rows' `"color"` key, locals and parameters (`color`, `gray`, `mold`, `center`).
- KEPT, not ours to rename: the `swing` table's `cancelled` column (published: rule 17; the server's field and the
  integration suite's SQL read it); the foundation's `UiKit.colour`, `InterestManager.centre`, `Cells.recentre`.
- Content rebaked (two abilities' designer notes changed: only the manifest moves).

**Found**: the genre's player-facing text was already American; the pass changed notes, docs, test messages and code
names. The one British word a player sees is the FOUNDATION's: "Cancelled." on the connect screen
(`foundation/ui/connect_screen.gd`), a template change for every game: Luke's call.

**Tested**: `cargo check --target wasm32-unknown-unknown`; `cargo test --test regents` 45/0; the unit suite (lints +
regents) below. No server behavior changed, so no integration run; nothing to publish but the manifest (content).

**Left**: the foundation's "Cancelled." (template); older docs outside this repo's genre (the template's) stay as
the template writes them.

## Step 39: the minigame prep sheet (2026-11-04)
**Why**: Luke, 2026-11-04: "Let's start the minigame rework. First summarize where we are currently, and forecast ones
we will need in the future", with tiers "increasingly hard but similar" and the 2D minigames' look "a little low
compared to the 3d assets". Item (2) of `GAME.md`'s order of work.

**Written**: `docs/regents_rule/MINIGAMES_PREP.md` (as `ARMOR_PREP.md` was for armor): the four built minigames and
what each score pays; the tier ladder today; what a minigame costs; why they look as they do; every coming skill
sorted into five model families; one minigame per craft (a pattern feeds it data) rather than per item; tiers as one
game per skill with a new thing per band and rank easing the round; what a score is worth; three ways to the look
(2D re-skin, in the world, a 3D stage in the panel) and the assets (Gemini as a mockup tool only); a difficulty
readout by simulated players; decisions M1-M10 with proposed answers; the order of work once answered.

**Found** (checked against the content): smithing's copper, iron and steel rounds are identical (only the pattern's
outline differs), so Masterwork steel is as easy as Masterwork copper; bars have no quality, so smelting skill never
reaches a grade; grips, the yew bow and the yew staff have no minigame and no quality, so a wood-core weapon can never
be Fine or Masterwork from crafting; rank never changes how a round plays; the copper and steel axe heads' rounds are
titled "Iron axe head" and both sword blades' "Iron sword blade" (params `display_name`; fix in the overhaul's first
step).

**Tested**: nothing to test (a doc only; no code or content changed).

**Left**: Luke's answers to M1-M10, then the sheet's §8.

**Revision 2 (2026-11-05)**: an outside review, checked against the code, folded in (`MINIGAMES_PREP.md` §9 lists
taken and not). Found while checking: a round scored 80 % pays exactly AFK (1.25 x 0.8), so only near-perfect play
gains; each hold of E is one round and the panel closes after it; assembly takes the BEST input's quality
(`make_batch`, `QUALITY_FROM_INPUTS`), harmless today but a Masterwork grip would lift a Common blade once grips have
a quality. New in the sheet: §3.1 (two anvil strikes, a rhythmic bellows, sound from the start), §4.1 (the core alone
sets an assembled item's quality; a part's grade starts its trait higher), §5.3 (gathering's rounds back to back in a
side panel), M11-M12, §9. The review's wrong claims (one bar a smelting round; latency) and invented numbers are not
taken.

**A second note on revision 2 (2026-11-05)**, all three taken in some form (`MINIGAMES_PREP.md` §9): a gathering run
goes on hands free once started (holding E while tapping A / D is a claw grip), ending on E, Escape, the node worked
out, or a round with no input (added here); each round is paid as it ends, as the code already does (the sheet's
wording fixed); the anvil's buttons become a UI setting so Luke tries LMB strike / RMB tap / R reheat against
LMB / Shift+LMB / RMB in step 2.

## Step 40: the minigame overhaul, step 1: the difficulty readout, the core sets quality, the round titles (2026-11-05)
**Why**: Luke answered `MINIGAMES_PREP.md` (2026-11-05: "all as proposed" but M2's band 3 waits on the metals after
steel, and M7 tries gathering as a 3D stage in the side panel too; `GAME.md` "The minigame overhaul, ANSWERED"), then
"Lets start on the work". This is the sheet's §8 step 1.

**Built**:
- **The difficulty readout** (§6): `SimPlayer` (a Resource: reaction, timing spread, aim spread, slips, mash rate,
  plans a strike ahead or not; four presets, flawless, skilled, average, careless, their numbers a first guess at
  human hands, `# ASSUMPTION:` in the file) and `MinigameReadout` (`game/regents/skilling/`): each preset plays a
  round of any minigame through its own model on many seeds; every simulated round is a real one (its inputs
  replayed through `SkillMinigames.play` must give what the bot saw); it reports the mean, the Fine and Masterwork
  shares (the anvil) or how often a round beats AFK (gathering, smelting; break-even 1 / `regents.active_yield_mult`).
  In the lab: **T** (`skilling_lab.gd`); from a shell: `tools\run.cmd game\regents\tests\minigame_readout.sh [rounds]`
  (a scene, `minigame_readout_cli.tscn`, so the hot rules' autoload is there; ~11 s at 200 seeds).
- **The core alone sets an assembled item's quality** (M12): `rules::sets_quality` (an input no part slot names);
  `make_batch` takes every input but keeps only the core's qualities (it took the best of ALL inputs); the client's
  `SkillingComponent.made_quality` the same (the core only). Nothing plays differently today (no part has a quality
  yet); it is in before carving gives grips one.
- **Round titles**: the material table copied a pattern's round title and all ("Iron axe head" on the copper and
  steel heads); it now titles the round as its recipe (`material_table.gd`), and the seven copied titles are fixed.
  Content rebaked (the manifest).

**Found, by the readout at 200 seeds** (what steps 2-5 work against):
- **The anvil** (shape to the outline): almost nobody makes Common (careless 0-2 %); a flawless player makes
  Masterwork axe heads 59 % of the time, a careless one 14 %; sword blades: average 77 % Masterwork. **The game's
  ceiling is ~80 %**: a search three strikes ahead with all the time and heat in the world reaches 801 on average
  (best 840) from a starting error of 110 (the outline's tall columns only rise by spread). So Masterwork is the
  seed's more than the hand's. Copper, iron and steel heads read the same (known). Step 3 starts here.
- **Smelting**: only the flawless player beats AFK (skilled 20 % of copper rounds, 0-2 % of iron and steel): playing
  it actively pays LESS than AFK for nearly everyone (M11).
- **Gathering**: the tree, oak and copper rock max out for any attentive player; iron and coal split average from
  skilled (54 % / 39 % beat AFK).

**Tested**: the unit suite (lints + regents) 3147/0, up 9: every simulated round replays as played (18 rounds x 4
players x 16 seeds), more skill never scores less, the readout is the same every run, the flawless player maxes every
tree, a player who never presses scores an untouched round (no Fine, no gain on AFK), the readout reads; the lab's
T; a Masterwork handle never lifts a 900 head (client). Its negative: the flawless player made to slip half the
time fails the ordering and the trees. `cargo test --test regents` 45/0 with a new check (only the core sets quality;
negative: every input setting it fails); `cargo check --target wasm32-unknown-unknown`. Not run: integration (the
server change keeps today's play: no part has a quality), so the play database is unpublished for this step.

**Left**: §8 step 2, the look on smithing (a 3D stage in the panel, sparks, sound, the two strikes); the readout's
target shares (M4) pinned when smithing's ladder is tuned (step 3); the presets' numbers set against Luke's own play.

## Step 41: the minigame overhaul, step 2: smithing's look and its two strikes (2026-11-05)
**Why**: `MINIGAMES_PREP.md` §8 step 2 (Luke, 2026-11-05: "Commit, start step 2"): the look on smithing first (M7:
a 3D stage in the panel, sound from the start), and band 1's new thing, the two strikes (M9, §3.1).

**Built**:
- **Two strikes** (§3.1): the strike is now the HEAVY one; a LIGHT TAP is sent as column `ShapeModel.TAP + c`
  (1000 + c) and beats the column down `tap_drop` with `tap_spread_pct` into its neighbors. Add-only params on
  `ShapeParams` (default 0: a tap is then ignored and costs no swing, so every round from before replays unchanged),
  in all three models (`shape_model.gd`, `server/src/genre/regents/shape.rs`, `make_skill_goldens.py`) and the build
  step (`server/build/regents.rs`: a bake without them reads 0). Goldens: three new cases (two strikes rough and
  finish; taps switched off; taps that spread and taps off the bar); the old six unchanged.
- **The content**: the nine anvil recipes and their three patterns: heavy 6 down, 17 % a side (1 a side), tap 1 down,
  no spread. **Found doing it**: at 4 x 20 % the spread was 0.8, rounded to 0, so a column could never rise: the
  outline's columns taller than the bar were out of reach, half of step 40's ~80 % ceiling.
- **Which buttons tap is a setting** (Controls, "Smithing: the light tap", `ShapeMinigame.SETTING`), both ways:
  left click strikes; right click taps and R reheats (the default), or Shift + left click taps and right click
  reheats. A round with no tap reheats on right click in both. The lab's **B** switches it.
- **The 3D stage** (`AnvilStage`, `game/regents/skilling/smithing/anvil_stage.tscn`, its own world): Quaternius's anvil,
  the bronze hammer (follows the mouse over the bar, falls on a strike), the fire pit behind with its light flaring as
  the bar goes back in; the bar as 16 glowing columns (emission by heat squared; the struck column flashes white);
  sparks (many for a strike, a few for a tap), a little camera shake. The 2D readouts stay where 2D is clearer: the
  outline drawn over the 3D bar (projected), the heat bar, the words. Presentation only: it is told what
  `ShapeModel` landed and decides nothing. Designers move the camera, lights and props in the scene.
- **Sound** (ours, synthesized: `game/regents/tools/make_skill_sounds.py` -> `art/sound/smithing/`, CC0): the
  clang (pitched down as the bar cools), the tap, a cold strike's thud, the reheat's whoosh. On the Effects bus.
- **Type**: `MinigameLook` (the machine's book serif, warm ink and gold, a shadow under words over a 3D stage), on
  smithing now, the others as they get their look (§8 step 5).
- **The readout's smith taps**: a planner strikes what brings the bar nearest (a spread counted) and plays the round
  both ways (planned and by the tallest bulge), keeping the better, so its top lines are the round's ceiling (on the
  pickaxe head the plain way scored 1 per mille more; a two-strikes-ahead planner changed nothing and was 25x slower).

**The readout now** (60 seeds; Fine at 40 %, Masterwork at 80 %): axe heads flawless 88 % (Masterwork 100 %), skilled
87 % (98 %), average 79 % (45 %), careless 69 % (1 %); sword blades 87 / 85 / 70 (8 %) / 53 (7 % Common); pickaxe heads
89 / 88 / 89 / 81 (73 %). The ceiling rose from ~80 % to ~89 %; Masterwork is now too easy for skilled hands, which is
step 3's to tune (M4's targets) with Luke's play.

**How to play it**: the lab (`skilling_lab.tscn`, F6), any axe head, sword blade or pickaxe head: left click a column
to rough it out, right click to tap it to the line, R before it goes cold. **B** tries the other buttons. In the game:
the anvil's round, the same.

**Tested**: the unit suite (lints + regents) 3160/0, up 13: the two strikes in the model (a heavy strike spreads,
a tap does not, a tap is held through a swing, off the bar is no tap, tap_drop 0 ignores taps at no swing's cost),
every anvil recipe has both, the readout's smith taps and taps lift the ceiling, the setting (Controls, two
choices), both mappings by real clicks on the 3D bar (every column is clicked where it is drawn), a round with no
tap reheats on right click, the stage flashes and sparks where the model landed. Its negative: right click made to
strike fails the mappings check. Goldens: Rust plays every case (45/0); its negative (a tap that drops as a heavy
strike) fails the new two-strikes case. `cargo check --target wasm32-unknown-unknown`. The skilling playtest (a
real client at 150 ms on the test database) 73 + 8 / 0: the iron axe head shaped by left and right clicks, reheated
with R, 840, the server's replay the same. Looked at in windowed shots (the lab, and the 960 x 620 game panel).
Not run: integration. Published to the play database (no wipe).

**Left**: Luke's play (the look, the sounds, the strikes' numbers, which buttons); step 3, smithing's ladder (tune
Masterwork to M4's targets: it is now too easy for skilled hands); the other minigames' look (step 5) uses
`MinigameLook` and a stage of their own.

## Step 42: the anvil's bands, a test: heats, the pattern, a varying outline, red heat, the quench (2026-11-05)
**Why**: Luke played step 41 ("the time between hitting reheat and then being able to use the hammer again was too
long, could only ever get two reheats"; the 15 s clock fitted two) and chose (`GAME.md`, "The anvil, after playing
step 2" and "The anvil's bands, A TEST"): a set number of heats instead of a clock, each reheat lowering the
ceiling; the outline varying every round; the pattern laid on to see the outline, no strikes while it is on; and
as a test, copper band 1, iron band 2 (harder metal, each lay costs too), steel band 3 (red heat, the quench). Also
"rank eases the numbers, a band adds one rule" for every skill (Luke: yes), and a direction on outranked XP.

**Built** (`ShapeModel`, its Rust twin and the Python goldens' copy; every rule a new param, 0 off, so all
earlier rounds replay unchanged; new inputs are positive codes an old server ignores, since the server refuses a
round with any value under -1):
- **Heats, not a clock** (`max_reheats`, `reheat_cost_pm`): only so many reheats (the sixth is ignored); the smith
  SETS THE PART DOWN (`DONE`, 2000: Enter or a button; nothing counts after); `duration_ms` is then only a cap
  (60 s); the round also ends when cold with no heats left. Each reheat takes its cost off the CEILING (the best
  the part can be); the score is the shape's, never above the ceiling.
- **The pattern** (`hide_outline`, `lay_cost_pm`): the round starts with it on the bar; `LIFT` (2002) and `LAY`
  (2001) by Space or a button, or a click while it is on (which strikes nothing); NO STRIKES while it is on (a
  reheat may). Iron and steel take `lay_cost_pm` off the ceiling for each lay after the first.
- **The outline varies** (`outline_vary`): three smooth seeded bumps on the part's outline, the total kept (the
  same metal to beat off); drawn from the seed after the bar's own draws.
- **Red heat** (`red_ms`, `crack_cost_pm`): the last 1.2 s of a heat the bar is red; a strike then does not move
  it, it CRACKS (a mark stays on the column; `crack_cost_pm` off the ceiling).
- **The quench** (`quench_lo_pm`..`quench_hi_pm`, `quench_bonus_pm`, `quench_loss_pm`): on steel, Enter quenches;
  set down while the bar's heat is in the window (25-45 %, just above red, marked gold on the heat bar) +6 %; outside
  it, up to -15 % (a window's width out: all of it); never above the ceiling nor below nothing.
- **The content** (the nine anvil recipes; the three patterns carry band 1): all: 5 heats at 4 % each, reheat 0.6 s,
  the pattern, outline varying by 3, `error_scale` 50 (at 100 being off the line cost so little that the
  cheapest player won: the readout's careless smith beat the skilled one), heavy 6 / 17 %, tap 1, the bar 23 high.
  Iron and steel: heavy 5 / 20 %, a bar 25 high, each lay 3 %. Steel: red 1.2 s and a crack 6 %, the quench.
- **The UI** (`ShapeMinigame`): heats left as marks and "The best it can be now" where the clock was; "Lift the
  pattern / Lay the pattern on (Space)" and "Set it down / Quench (Enter)" buttons; the outline shown only with the
  pattern on (a pale plate) and after the round; the heat bar's red end and the quench's gold window; the words say
  what to do. `AnvilStage`: a red bar when red, crack marks. `SkillMinigame`: a round may end early (`is_over`) and
  hide its clock (`shows_clock`).
- **The readout's smiths** learn it: they look, lift, and work from MEMORY (`SimPlayer.memory_strikes`, then each
  column remembered a little off; `looks_again`: lay it on once more before finishing, never during roughing,
  which the first try did and paid for); reheat only while a heat is worth its cost; set down, in the quench's
  window when there is one (a heat spent to get back into it). The integration hook's bot (`skill_bot_cli.gd`)
  plays the new rules too.

**The readout now** (60 seeds; Fine 40 %, Masterwork 80 %; skilled / average / careless): copper axe head 87 / 82 / 68
% (Masterwork 98 / 90 / 8 %); iron 78 / 69 / 63 (28 / 0 / 5 %); steel 74 / 67 / 34 (0 / 0 / 0; careless 52 % Common).
Sword blades the hardest (steel: average 97 % Common). Every part: each metal harder than the last for every hand.

**How to play it**: the lab (F6): a copper, iron or steel axe head. The pattern is on at the start: look, then
click (or Space) to lift it; strike from memory; Space to look again (iron and steel: 3 % each); R to reheat (5
heats, 4 % each); Enter to set it down, or on steel to quench when the heat bar is in the gold mark. Don't strike
while the bar is red (steel).

## Step 43: the minigame overhaul, step 5 (the look): woodcutting, mining and smelting on 3D stages (2026-11-05)
**Why**: Luke, 2026-11-05: "lets move on to the other minigames for now (we can always change or tweak the games
themself) to get them looking like smithing". `MINIGAMES_PREP.md` §8 step 5's look, ahead of step 4 (gathering's
cadence, M11: not built); his M7: gathering as a 3D stage too, in a smaller side panel, as a test.

**Built** (presentation only: no model, twin, golden or content changed; every round plays and replays as before):
- **`StageWorker`** (`game/regents/skilling/`): a character on a stage: one of the adventurer's looks, the animation
  set's own clips on a plain `AnimationPlayer` (no AnimationTree: rule 11's is the body's), the skill's real tool by
  its grip (`HeldItem.attach`). A swing starts its clip just before the clip's own blow (measured: chop 0.26 s,
  mine 0.14 s), so the blow lands when the model says; a swing or a flinch plays once, then rest (`Idle`).
- **Woodcutting** (`WoodStage`, `woodcutting/wood_stage.tscn`): the trunk in a glade (bark by tree: yew twisted, oak
  pine-barked, else common), its pieces and branches with leaf clumps, the woodcutter beside it with the copper axe
  on the model's side; a clean chop swings, throws chips and the piece (it lands with a thud), the trunk drops; a
  branch at the head: a flinch, leaves, "Ouch!".
- **Mining** (`MineStage`, `mining/mine_stage.tscn`): the node's own rock model with its ore nuggets in the ore's
  color (`RegentsOreSpots`, as the world), sized to one height, the miner beside it with the copper pick; the seam
  stays the 2D readout, its face square placed on the rock; a strike throws chips and dust from the notch's spot on
  the rock, a split jolts the rock, a jar sparks and makes the miner flinch.
- **Smelting** (`SmeltStage`, `smelting/smelt_stage.tscn`): the brazier's fire (brighter with the heat), the game's
  bellows prop (squashes on each pump) worked by the smelter (`Push` clip), the crucible on the fire, carried to the
  mold and tilted to pour a molten stream, the metal rising in the mold, a spill when over. The heat's band and the
  mold's line stay 2D gauges at the panel's edges.
- **Sounds** (ours, synthesized: `game/regents/tools/make_skill_sounds.py`, which replaces the smithing-only script
  and makes smithing's the same, byte for byte): woodcutting's chop, branch, fall; mining's strike, split, miss;
  smelting's bellows and pour. `MinigameLook`'s type on all four.
- **The side panel** (M7's test, `regents_hud.gd` `place_round_box`): woodcutting and mining in a 460 x 600 panel at
  the right side of the screen (the character and the node stay in view); smelting and smithing in the 960 x 620
  middle one.

**How to play it**: the lab (F6): a tree, oak or yew; a copper, iron or coal rock; a copper, iron or steel bar (the
lab is full screen). In the game (after a publish): hold E at a tree or rock: the round opens at the right side.

**Tested**: unit (lints + regents) 3166/0, up 3: each stage follows its model (the woodcutter on the model's side,
a clean chop throws the piece, a branch makes them flinch; mining's rock is the node's own and the seam's face sits
on it, chips on a strike, sparks on a jar; smelting's pump works the bellows, pouring shows the stream and the
metal, stopping stops it), each round's replay unchanged. Negative: the woodcutter kept on one side fails it. The
skilling playtest checks each round's panel (side for gathering, middle for making) and its stage: SEE HANDOFF.
Looked at in windowed shots at the side panel's and the middle panel's sizes.

**Left**: Luke plays the four; the back-to-back gathering runs and their pay (M11, §8 step 4); each band's new rule
for the other three (M9: knots, brittle notches, slag; prototyped and played first); the character wears one of
the adventurer's looks, not the player's own (the player's look on the stage: later, if wanted).

**Revised after Luke's look (2026-11-06)**: "the positioning of the minigame is right where the minimap is" and "does
it feel weird to have a character on a small panel while you see your main character ... consistent with hammer
floating, pick floating, axe floating" (his calls: `GAME.md` M7).
- Every round in the 960 x 620 middle panel (`place_round_box()`, no side panel).
- No character on any stage: `StageWorker` deleted, `FloatingTool` (`game/regents/skilling/floating_tool.gd`) in its
  place: the tool scene's model alone, resting in one pose and swinging to another (two `Marker3D`s in the stage's
  scene a designer moves: `AxeRest`/`AxeHit`, `PickRest`/`PickHit`), `aim` puts its head (the axe's edge, the pick's
  tip) on a point; a blow falls fast and rises slower; a jar bounces back with a shudder.
- Woodcutting: the axe chops at an angle into the side the model says (the right side mirrors the left's poses); a
  branch knocks it back (the view shakes, the leaves, "Ouch!"). The camera is closer.
- Mining: the pick hovers raised by the mouse (kept on the seam's face) and comes down with its tip on the strike;
  a jar bounces it. The camera is centered and closer.
- Smelting: the bellows pump on their own.
- The tests: the stages' check now asks for no character on any stage (`_no_character`: no `Skeleton3D`), the axe's
  blow on the model's side at the bottom piece (both sides seen), the pick's tip landing on the strike's point, a
  jar marking the tool; the skilling playtest asks for every round in the middle panel. Unit (lints + regents)
  3166/0; negative: the axe never mirrored and the pick never aimed fail both stage checks. Skilling
  playtest 76 + 8 / 0 (77 on the run before: a check that only runs on some timings; every panel check passed).
  Looked at in windowed shots (at rest and at the blow).

**Then, from Luke's play of the stages (2026-11-06)**: "the tree base bark doesnt seem to change" (the stump now
wears the round's bark, `WoodStage.set_tree`); "the pick swings more like a hammer than with its point" (the pick
now swings in its own plane, the point leading, and lands on the point: `pick_tip` (-0.31, 0.52, 0), new `PickRest`
and `PickHit`); "the pick is instantiated later so cant edit it in editor" (each pose marker now holds a preview of
the tool, `Preview`, taken away in play by `FloatingTool.marker`: drag the marker and see the tool move).
Then (2026-11-06): "make it like the original but with the swing coming in left to right": `PickRest` and `PickHit`
mirrored across the rock's middle (each turned half round its handle, so the point still leads); and the pick's point
is the model's own (-0.31, 0.67, 0): 0.52 was guessed from a picture and landed the head ~15 cm off the notch.

**Also asked (2026-11-06)**: the world character's pick and axe clip into big rocks and trees while gathering:
PROGRESS 44.

## Step 44: the work spot: the player steps to where the swing meets the rock or the bark (2026-11-06)
**Asked** (Luke, 2026-11-06, with two shots): gathering in the world, the pick swung deep into a big rock and the axe
sat inside a big trunk. "Is there a good/easy way to make the tools collide/stop animation when they hit the rock."
A side session ("Stop gathering tools clipping into rocks and trees") found the cause and first built a picture-only
stand-off (the drawn model slid back, then also in, from the body); Luke chose **"Move the player"** (`GAME.md`), so
that was replaced by this.

**The cause** (measured): a worker works wherever it stopped walking (the server's `work_reach_m` is 3 m from the
node's middle), and walking up stops the body at its 0.4 m capsule against the node's collider. The swing reaches
much farther: the pick ~1.25 m in front of the feet low down, the axe ~1.07 m but only high (1.4-1.6 m). Trees are
worse: the trunk that blocks the way is `TRUNK_RADIUS` 0.45 m x `model_scale`, the drawn trunk ~0.7-1.1 m. Pressed
against them the tool went 0.5-0.97 m inside; from farther off it swung at the air (the yew at 2.95 m: 1.46 m short).

**Built**:
- `WorkSpot` (`game/regents/skilling/work_spot.gd`): how far to step BACK (or, negative, IN) so the swing's front
  stops `clearance` short of the node's DRAWN surface, looking along where the player faces; 0 when the node is not
  ahead (its middle behind, or not met within reach + 2 m); never back past the server's reach (`regents.work_reach_m`
  less 0.3 m from the node's middle). The swing's front is a profile by height.
- `SkillingComponent.begin(target, active)`: a press on a node (tap or hold) first takes the player to the work
  spot, then calls `work` there (AFK stops after `regents.afk_stop_moving_m`, so the step comes first). Luke, after
  the first version: "move the player as visuals and server body should match in case they get attacked or shot at
  while harvesting ... just make sure its smooth and not jarring when you move them, facing them is probaly the right
  call too". So: the body eases round to face the node, then the walk key and slow are held for the player (a walk,
  not a run: frames as their own, bounded by the server, relative to the body) until the body would slide the rest;
  at rest and facing it, the work starts. Then Luke: "have the model face them but allow the camera to rotate as it
  is since we are standing still": a first version turned the view (`set_look`) to turn the body; the template's
  1.7.4 (`LocalInputComponent.hold_body_yaw`, DECISIONS #305, made in the template and shipped to every game) turns
  the body alone, the camera untouched. And: "the walk back when reposition is too slow ... dont want to wait more
  than a few moments (.5 maybe less?) and should be natural": the step is taken at the plain gait (5 m/s, back 0.65 of
  it) not the slow walk (1.2 m/s, back 0.78 m/s: over a second for 0.9 m), and the turn eases faster; the playtest
  holds the step to 0.6 s (`step_took_s`). Gives up after 3 s (a wall); a turn under 4 degrees and a
  step under 6 cm are not taken. (A first version pushed at run speed with `force_move`, which cannot walk.)
  Exports on the adventurer's Skilling node: `swing_front` (by skill pose: (height, reach) points; a skill not listed,
  a station's, never steps) and `work_spot_clearance_m` (0.04).
- MOVING STOPS AFK WORK (Luke's play, 2026-11-06: after the step he could walk with S or W and keep harvesting,
  the server stopping AFK only at `regents.afk_stop_moving_m`, 1 m): the client stops its AFK run once the body is
  `SkillingComponent.afk_leave_m` (0.15 m) from where it began (`_stop_afk_if_moved`); the server's 1 m stays the
  backstop. The skilling playtest: a short step back stops it.
- `NodeComponent.surface_along` (the side session's): how far along a ray the node's drawn model is; only a face the
  ray goes INTO counts.
- `game/regents/tests/work_spot_shot.tscn` (the side session's shot, reworked): a character with the real tool and
  clip at each node, shot at the swing's deepest frame where it stopped walking, then at the work spot; prints the
  gap and the swing's FRONT profile (paste it into `swing_front` after a clip or tool changes).
  `godot --path . res://game/regents/tests/work_spot_shot.tscn -- <out dir>`.

**Tested**: the skilling playtest (a real client at 150 ms): after a tap of E at the tree and a hold at the copper
rock, the BODY faces the node (its predicted heading), the camera's yaw is as it was before E, and it stands at the
work spot (`_check_work_spot`): 79 + 8 / 0; negative (no step):
both fail (the tree wanted 0.16 m in, the rock 0.83 m back). Unit (lints + regents) 3168/0. The shot: copper rock 0.97 m inside, now 0.03 m short; oak 0.72 inside, 0.01 short; yew 0.73 inside,
0.05 short; the common tree 0.48 inside, 0.13 short. Unit: `_run_work_spot` (pressed against the copper rock it steps
back ~1 m and then needs no more; 1.6 m farther it steps in by the rest; facing away 0; out of reach 0; kept inside
the server's reach; the smith never steps). Negatives: facing away first asked for 1.5 m (rays from behind the feet
began inside the rock: fixed by the node's middle having to be ahead); stepping in turned off fails the check.

**The reach from a node's edge** (Luke, 2026-11-06, for the big iron rock: pressed against it the feet were 2.72 m
from its middle, past the 2.7 m the step could go, so it did not step and the pick still went in): "Measure from its
edge". `NodeDef.radii_cm()` is each model's footprint in whole centimeters, worked out from the model at bake time
(nothing typed): a rock's farthest drawn point under 2 m from its middle (it is solid as drawn), a tree's trunk
(`NodeComponent.TRUNK_RADIUS` x scale: its crown and low boughs are walked under; measured as drawn, a yew's low
boughs came to 4 m). Baked into `node.json` (`radii_cm`: tree, oak 45; yew 37; copper 205/207; iron and coal 257/169),
compiled into `NodeSeed.radii_cm` (`server/build/regents.rs`; absent: 0, from the middle) and picked by entity as the
client picks the look (`NodeSeed::radius_m`). `gather` and a round's scoring (`resolve_round`) measure from the edge;
a station's reach is still from its middle. The client's step cap is the same (`NodeDef.radius_for`). Tested: the
Rust suite (the iron rock's two footprints, by entity; every tree's under 50 cm), integration (4.4 m from the copper
rock's middle works; 5.6 m is refused "from its edge"), the shot: the big iron rock now steps back 0.93 m and stops
0.05 m short (it went 0.88 m in); from 2.95 m off, the copper rock steps in 0.31 m (0.03 short) and the yew 1.42 m
(0.05 short). Published to `regents-rule` (no wipe).

**Left** (Luke's calls):
- The step only looks straight ahead (where the camera faces): a node off to one side of the 120 degree arc is
  worked from where the player stands.
- Stations (the anvil) do not step.


## Step 45: smelting is a rhythm track (2026-11-07)
**Why**: Luke, 2026-11-07: "smelting needs to be changed to a rhythm game". Of a full rhythm track or beat-timed bellows
on the old band, he chose **"Full rhythm track"** (`GAME.md`). The old round was mash-to-heat (M6 already said "in
rhythm, never mashing"), and the readout (step 40) had active smelting paying less than AFK for all but a flawless hand.

**Built** (a NEW challenge kind, `beat` = 104, so the old `smelt` = 102 keeps scoring old rounds and an old client,
which does not know 104, ignores the round instead of playing the wrong game; no table or reducer changed):
- `BeatParams` / `BeatModel` (`game/regents/skilling/smelting/`), the Rust twin `server/src/genre/regents/beat.rs`, a
  third copy in `make_skill_goldens.py` writing `shared/golden/regents/beat.json` (10 cases; its own random source, so
  the other goldens are byte for byte unchanged). The rules are written out on `BeatModel`:
  - THE TRACK from the seed: a count-in (`lead_beats`), then `beats` beats of `beat_ms`; a bar's first beat always has
    a note; other beats rest by `rest_pm`; an off-beat note half a beat later by `offbeat_pm`; a beat's note is a LONG
    DRAW (`hold_beats` long) by `hold_pm`, nothing else played inside it, ending by the last beat.
  - A PRESS (DOWN 1 / UP 2, one button): the earliest unplayed note within `good_ms` is hit, full value within
    `perfect_ms`, else `good_pm`; a draw is paid when let go (all of it from `good_ms` before its end, else the share
    held); a press on no note is a STRAY, `stray_pm` off the track. Mashing scores 0.
  - THE POUR as before (from `pour_ready_ms` after the track: hold to tilt, let go at the line), `track_weight_pct` 70.
- The content: the copper, iron and steel bars and the bar pattern: copper 600 ms beats (100 bpm), 16 beats, windows
  70/150 ms; iron 540 ms, more off-beats, 60/130; steel 480 ms, 20 beats, many off-beats and draws, 50/115. A round
  is 14.8-16 s (the old one 11-12). `build/regents.rs` refuses a round whose windows could meet (a beat under four
  times `good_ms`).
- `BeatMinigame` on smelting's stage: the track low across the panel, embers coming from the right to the bellows'
  mark, the long draws as glowing bars, the beat as lines (a bar's first brighter), a big count-in, a word at the
  mark (Perfect, Good, Missed, Wasted breath); the fire's gauge shows how the track is going, the mold's gauge the
  pour. `SmeltStage`: the beat knocked on the furnace (`knock`, a bar's first brighter), a note's pump, a long draw
  closing the bellows slowly (`draw_on`), a wasted press sputtering. New sounds (`make_skill_sounds.py`): beat,
  accent, draw, sputter.
- The readout's players (`MinigameReadout._beat`: a note pressed on its time give or take the hand's spread; a slip
  misses it or presses it off the beat), the integration hook's bot (`skill_bot_cli.gd --kind=beat`), the skilling
  playtest's player (by the frame, as a person).
- Kept: `SmeltParams`/`SmeltModel`/`SmeltMinigame`, its twin and goldens (old rounds); no content uses them.

**The readout** (200 seeds; AFK pays the same at an 80 % score today): copper flawless 98 / skilled 91 / average 77 /
careless 57 % (skilled beats AFK 94 % of rounds); iron 97 / 88 / 72 / 50 (92 %); steel 97 / 86 / 68 / 46 (91 %).

**How to play it**: the lab (F6): a copper, iron or steel bar. In the game (after a publish): hold E at the furnace.
Four knocks count in; press Space or click as each ember reaches the mark at the left; hold the long ones to their
end; then hold to pour and let go at the line.

**Tested**: Rust (`cargo test`): the twin plays every golden round exactly (10 cases); negative: a press 70 ms off
judged perfect, or a draw paid only when held to its very end, fails it. Unit (lints + regents) 3183/0 at this step:
the goldens, the track's shape over 40 seeds, judging, mashing (0), the draws, the pour, the metals ordered, the
stage (a note pumps, a draw holds, a wasted press sputters, the pour); negative: a stray never counted fails 6 checks.
Integration: the furnace round is kind 104, the bot's round scores 998 and pays bars and XP (its round lookup took
100-103 only: widened). Skilling playtest (a real client at 150 ms, pressing by the frame): track 1000, 0 wasted,
bars and XP paid, 91 + 8 / 0. Windowed shots of the count-in, the track with a draw held, and the pour.

**Left**: Luke plays it (the tempo, the windows, the draws, whether the pour stays); a timing offset in Controls if
his hands land late (audio or display lag); its band rule (slag on a second key, an alloy's two lanes: prototype
first); the back-to-back runs and the pay curve (M11, §8 step 4).

## Step 46: the minigame overhaul, step 4 (M11): rounds back to back, and what a played round pays (2026-11-07)
**Why**: `MINIGAMES_PREP.md` §8 step 4, Luke's M11 (2026-11-05, "as proposed"): a good round beats AFK and a poor one
still falls short, the break-even near half a score (not 80 %); the catalysts lean hard to active play; gathering and
smelting rounds run back to back hands free once started (E or Escape ends a run, as does a round with no input), each
round paid as it ends. Luke, 2026-11-07: "after smelting is done, continue with the next order as I will be away".

**Built**:
- THE PAY CURVE (`genre::regents::active_yield_milli`, a new `floor` argument): a round pays what AFK makes in its time
  times a factor running straight from `regents.active_yield_floor` (a NEW hot rule, 0.75) at a score of 0 to
  `regents.active_yield_mult` (1.25, unchanged) at a full score: half a score breaks even, a full one is the old 1.25,
  nothing played 0.75 of AFK. A floor of 0 is the curve before. `SkillingRules` (client) has the same for the readout
  (its break-even now 50 %) and the recipe bench.
- THE RARE EDGE (`active_rare_mult`): `regents.active_rare_mult` 1.3 -> **3.0** at a full score (max 6), and it now
  GROWS WITH THE SCORE (1 at 0): before, a round nobody played had the whole edge. Smelting has no catalysts yet.
- RUNS (`SkillingComponent`, `RegentsHud`): a round dealt at a node, or at a station whose recipe pays in batches
  (smelting; never the anvil: `SkillingComponent.runs`), starts a run. As each round closes the next is asked for
  (`run_gap_s`, 0.9 s, an export) into the SAME panel (the HUD reuses the minigame; the player stays held, the cursor
  free); the panel shows the run's tally under the leave hint ("This run: 2 rounds: 5 Logs, 1 rare find"). A run ends:
  on E (the round on now plays out and pays, then it stops), on Escape (now: gathering keeps what it got, smelting
  withdraws the round), after a round with nothing pressed, when a node is worked out or the furnace runs out (said),
  or on any refusal of the next round. Its end is said with the tally.
- No table, reducer or argument changed (the next round is the same `gather` / `craft` call): old clients play on.

**How to play it**: publish, then hold E at a tree: play a round, and the next comes by itself; press E to stop after
the round on now, Escape to stop at once; leave one untouched and the run stops. The same at a rock and the furnace.

**Tested**: Rust: the curve with and without the floor, the rare edge by the score. Unit: the content's numbers, the
break-even (50 %, 80 % with no floor), which rounds run (never the anvil), a run's tally (only its own played rounds),
E mid-round, a node worked out; negative: the anvil allowed to run fails it. Skilling playtest: at the tree the next
round came by itself into the same panel, the tally read "This run: 1 round", a round with nothing pressed ended the
run and no third came (or, when the tree was worked out in the first round, the run ended saying so); E during the
rock's and the furnace's rounds stopped the run after them.

**Left**: the numbers are first guesses for Luke's play (the floor, 1.25, the rare edge 3x, the gap); smelting's
catalysts (MATERIALS.md §6); whether E should end a run at once instead of after the round.

## Step 47: the minigame overhaul, step 3's M3: rank eases the round (2026-11-07)
**Why**: Luke's M3 (2026-11-05, "as proposed"): "a few percent wider windows a rank above the requirement, capped at
three (hot rules)", and for every skill "rank eases the numbers; a band adds one rule". The next decided piece of §8
in order (step 3's tuning to M4's shares waits for his play of the anvil).

**Built**:
- `regents.rank_ease_pct` (4) and `regents.rank_ease_ranks` (3), new hot rules: `rules::rank_ease_pct` is the ranks
  above a node's or recipe's `min_rank`, at most 3, times 4 % (12 % at most).
- The server works it out when it deals a round and writes it as the payload's FIFTH field
  ("<target> <def> <speed> <part> <ease>"; with no ease the payload is as before, so an old client reads every round
  the same; one would play an eased round un-eased, which only ever helps it). `Minigame::score_eased` replays it eased;
  the client's `SkillMinigames.eased` plays it the same, number for number: a branch staggers 12 % less, the rock's
  notch 12 % wider, the furnace's band (old kind) or the beat's windows wider (the outer window never past a quarter
  beat: copper's is there already, so only its inner window widens), the anvil's bar hot 12 % longer and its error
  scale 12 % larger (the error scale alone moved nothing for a skilled smith: what caps them is the reheats' cost).
- The readout prints each anvil round again "3 ranks on (12 % easier)", beside M4's targets. The integration hook and
  its bot read the payload's fields by place (the speed was taken as the LAST field) and play the round eased.

**The readout** (100 seeds, skilled smith, Masterwork share): iron axe head 23 % -> 62 % three ranks on (M4 wants ~10
-> ~33 %); copper axe head 99 % -> 100 % (far too easy already: step 3's tuning, after Luke's play).

**Tested**: Rust: the ease by rank (0 at the requirement, 8 % two above, capped), the payload with and without it,
and a strike 6 % past the rock's notch jars as authored and lands eased; negative: the server's notch not widened
fails it. Unit: the eased numbers on the content (and the content untouched), a skilled smith better three ranks on
(at first equal: the heat added). 3196/0.

**Left**: the 4 % and the 3 ranks are first guesses; tuning the anvil to M4's shares (step 3, after Luke plays it);
gathering already swings faster with rank (`speed_pct`, 3 % a rank), so M3 there is on top of it.

## Step 48: band 2's new rules, a TEST for Luke's play: knots, brittle notches, slag (2026-11-07)
**Why**: `MINIGAMES_PREP.md` §8 step 5, the part left after the look: "their band rules (knots, brittle notches, slag)
not yet ... prototyped and played before deciding" (Luke's M9). Built as the anvil's bands were (2026-11-05): each a
new param, 0 = off, so every round before replays unchanged; ON for band 2's content only (the yew, the coal rock,
the steel bar), as a test to play and keep or back out (each `designer_notes` says how).

**Built** (each in the GDScript model, its Rust twin and the Python goldens' copy; each drawn from its OWN seeded
stream, the seed folded with a salt, so the branches, seams and tracks never change):
- KNOTS (woodcutting; `ChopParams.knot_permille`, `knot_beat_ms`): a knotted piece takes two chops from the same side,
  the second within the beat (600 ms) of the first; the first only BITES (the axe sticks with a deeper knock, a few
  chips, "Again!"); the other side, a late chop or a branch's stagger start it over. The piece shows a dark burl. The
  yew: 20 % knotted, its target 28 -> 24 (so a flawless round still scores full: 24 is the fewest cuts a flawless
  woodcutter made over 200 seeds).
- BRITTLE NOTCHES (mining; `CrackParams.brittle_permille`, `ring_ms`): after a hit the rock rings 450 ms; a brittle
  notch struck in the ring CRACKS WRONG (a jar, "Cracked wrong!"); a strike pressed mid-swing is held to the swing's end
  (250 ms), still in the ring, so the player must wait. A seam's first notch never is. Drawn pale and cracked, rings
  spreading from it while the rock rings, not glowing ready until it stops. The coal rock: 30 %.
- SLAG (smelting; `BeatParams.slag_pm`, a new input SKIM = 3): a press note may be slag (a gray square), skimmed with
  the SECOND button (F or right click); the main button never plays it; a skim on no slag is wasted breath. A round
  with no slag ignores a skim (so the copper and iron rounds replay exactly as before). Steel: 15 %.
- The readout's players, the integration bot and the goldens know each rule (the players wait out a ring, skim slag,
  chop a knot twice; a slip does not).

**The readout** (100 seeds; AFK pays the same at 50 % now): yew 100 / 98 / 87 / 60 (flawless / skilled / average /
careless); coal 100 / 100 / 68 / 28; steel bar 97 / 86 / 69 / 46. The simulated players know every rule perfectly, so
how hard a knot or a ring is to SEE is only Luke's play to tell.

**How to play it**: the lab (F6): the yew, the coal rock, the steel bar. In the game: those three need their ranks
(woodcutting 4, mining 3, smelting 3).

**Tested**: Rust: every golden round exactly (4 knot, 3 brittle, 4 slag cases added; the older cases byte for byte the
same); negatives: a knot cut from either side, brittle notches that never ring, the main button playing slag: each
fails its golden. Unit 3200/0: the goldens (knots, brittle, slag lists too), the yew's knots on its stage (a burl; a
bite, the other side and a late chop bite again, the next same-side chop cuts; the replay agrees), brittle (a held
strike lands in the ring and jars; struck as it fades it opens; never a seam's first), slag (skimmed full value, pumped
wasted, copper ignores a skim). Two older checks updated for knots: "a harder tier" may add knots instead of a higher
target; a perfect round's every swing is a cut or a bite.

**Left**: Luke plays and keeps or backs out each (and their numbers); band 3's rules (deadwood, a fault, an alloy).

## Step 49: woodworking's carve: a vertical stave, wood off either side, on the yew bow and staff (2026-11-07)
**Why**: `MINIGAMES_PREP.md` §8 step 6 (M5). Luke played and found no "play a round" at the grips: woodworking had no
round. Asked whether a grip with a grade stops stacking: "Yes, stop stacking"; then, told a grip's grade does nothing
yet (an assembled item takes its quality from the head alone, M12; a grip's grade only starts its trait a rank higher
once trait ranks are built, `MATERIALS.md` §10 step 5), he chose **"Bow and staff first"** (`GAME.md`): grips keep
stacking, with no round, until trait ranks give their grade a job. A first version reused the anvil's model at a bench;
Luke: "I think I want to have woodcarve/woodworking be vertical and have wood you can take of from either side (to allow
asymmetry for bows/staffs) instead of just being a duplicate of smithing". So it is its own game; the bench version was
taken out (the anvil is exactly as before).

**Built** (a NEW kind, `carve` = challenge 105):
- `CarveParams` / `CarveModel` (`game/regents/skilling/woodworking/`), Rust `server/src/genre/regents/carve.rs`, a
  third copy in `make_skill_goldens.py` writing `shared/golden/regents/carve.json` (9 cases). The rules are on
  `CarveModel`: a stave in ROWS, each with a LEFT and a RIGHT edge out from the middle line; a cut (row, side, deep or
  fine) takes that edge in, never back; the two PROFILES may differ, each bent by a seeded bump each round; the pattern
  is laid on at the start (no cuts while it is; each look after the first costs 3 % of the ceiling); a cut mid-swing is
  held to the swing's end; Enter sets it down; the score from both sides' error, capped by the ceiling.
- `CarveStage`: the stave standing on the game's own workbench (placed by the model's size), each row a block whose
  edges move separately, a carving knife coming in from the side cut, chips, the knock (deeper for a deep cut).
- `CarveMinigame`: click a row LEFT of its middle to cut its left edge, RIGHT of it for the right; left click deep (4),
  right click a fine shave (1); the profiles drawn while the pattern is on (gold) and after the round.
- SIGNED EDGES AND THE FLIP (Luke, on the shots: "it looks like you carve a strung bow ... make it a unstrung bow shape
  and backwards (curve going right or left) with variation for difficulty"; stringing comes later, with herbalism's
  string): an edge may cross the middle line (a curved stave), a cut stops at the other edge; with `mirror` on, one
  seeded draw swaps the two profiles, so the piece bends left or right, the seeded bumps on top.
- The yew bow (40011) and staff (40014): quality from the round (AFK makes Common, 350), 24 s, 12 rows, `mirror` on:
  the bow an UNSTRUNG stave, a C bending up to 6 units off the line at the middle, thicker at the grip; the staff a
  straight shaft, its head hooked to one side. Error scale 40, a deep cut 4.
- Rank eases it (M3: the error scale wider); the readout's carvers (work from memory, look again when only shaves are
  left, a slip cuts the row beside); the integration bot.

**The readout** (100 seeds; fresh band): bow skilled 48 % mean, Fine 66 %, Masterwork 5 %; staff 44 %, 50 %, 6 % (M4
wants Fine ~50 %, Masterwork ~10 %). The simulated carvers needed to be careful to read right (deep cuts with a unit to
spare once the picture blurs, a look before the fine work), else skilled scored below careless.

**Tested**: Rust: every golden round exactly (12 cases: the flip both ways, a cut stopped at the other edge);
negative: a fine shave as deep as a deep cut fails it. Unit 3202/0: the bow at the bench (a click lifts the pattern;
left of a row's middle, as the wood is NOW, cuts its left edge deep; right of it a fine shave; Enter sets it down; the
replay agrees); cuts landing before the stage has drawn (no error; negative: without the fix the run fails on the
errors). Integration: a round of kind 105 dealt at the workbench, the bot carves both sides to the line, the bow's
quality is the score, its two yew logs taken. Windowed shots of the C both ways.

**Left**: Luke plays it (the rows, the cuts, the profiles, whether the pattern stays); its numbers (M4); grips (with
trait ranks); hilts; its band rules (grain, figured wood: §3).

## Step 50: herbalism, step 1: flax pulled AFK with a trowel; the bowstring; stringing the bow (2026-11-07)
**Why**: `HERBALISM_HUNTING_PREP.md` §7 step 1, after Luke answered H1-H11 ("Yes, start step 1"; `GAME.md`
"Herbalism and hunting, ANSWERED").

**Built** (content, and two small code changes):
- HERBALISM (`content/skill/herbalism.tres`, 40010; its pose the reach `pose.craft` until a pulling clip is in the
  animation set: `adventurer.tres` holds Luke's uncommitted editor changes, so it was not touched).
- FLAX (`content/node/flax.tres`, 40007): tier 1, a TROWEL of tier 1 from the bag, 3.5 s an item AFK, 20 % to deplete
  per item, regrows in 30 s; its rare the SEED POD (40047, 6 per mille); the nature pack's Flower_3_Group, bigger.
  NO ROUND YET (pull the root is step 2): a node may now have none (`NodeDef.validate`, `build/regents.rs`), and holding
  E at it works it AFK as a tap does (`gather`: a round only `if active && !matches!(minigame, None)`); its prompt says
  "E: pull the flax (AFK)" and offers no round (the verb by the tool: chop, mine, pull).
- THE TROWEL (H2): two patterns of the material table, `trowel_blade` (the anvil, one bar, a smithing round as the
  other heads, quality from it) and `trowel` (the workbench: the blade the core, a grip; quality from the blade);
  "Make the table" made copper, iron and steel cells (items 40050-40055, recipes 40040-40045). The COPPER TROWEL
  (40051) joins the STARTER KIT (new characters only: one made before has to smith one). No model in the hand yet.
- FLAX (40046), the SPINNING WHEEL (`content/station/spinning_wheel.tres`, 40005: an AFK station trained by Crafting,
  H6; a PLACEHOLDER BLOCK until a model is found), the BOWSTRING (40048: three flax, recipe 40038).
- STRINGING (H8): the carve round (recipe 40011) now makes the UNSTRUNG YEW BOW (40049, no weapon kit, its quality the
  carve's); "Yew bow" (recipe 40039, the workbench) strings it with a bowstring into the Yew bow (40020), quality from
  the inputs (the stave's: a bowstring has none). Yew bows already in bags stay bows.
- PLACED: four flax patches and the wheel in the glade (`frontier.tscn`: the flax west of the spawn, a "Flax meadow"
  label for the map; the wheel by the workbench); the continent copies the glade's camp, and its open meadows got 64
  more patches from FLAX'S OWN RANDOM STREAM (`build_continent.gd`), so all 649 points before are exactly where they
  were (checked against the last bake).

**How to play it**: publish (done), restart. A NEW character has a copper trowel; an old one smiths a trowel blade (a
copper bar at the anvil) and assembles a copper trowel (the blade and a grip, the workbench). Walk west of the spawn to
the flax, tap E. Three flax at the spinning wheel (by the workbench) make a bowstring; a carved unstrung yew bow and a
bowstring at the workbench make the yew bow.

**Tested**: Rust: the chain lists (seven nodes, ten skills, five stations; flax the one node with no round). Unit:
the content's counts grown by the trowels, flax and the wheel (fifteen anvil recipes, twenty-six at the workbench, one
at the wheel; thirteen patterns, 39 cells, the copper trowel 40051; "Trowels" in the workbench's list; 23 rounds in the
lab); flax valid with no round; the bow's two steps. Integration (2026-11-08): every herbalism and carve check
passes (flax AFK with no round, no trowel no flax, three flax to a bowstring at the wheel only, no stave no bow); its 10
failures are the referee-paced combat checks and the foundation's referee and hold checks (they fail on `54c1973b` too:
the combat-check session's task). Skilling playtest (2026-11-08): 94/0 and 8/0, the herbalism leg included (flax pulled
AFK, the prompt offering no round, spun, strung into a yew bow of the stave's quality 650).

**Left**: pull the root (step 2); a trowel model and a pulling clip; a spinning wheel model; the station refusal says
the station's key ("spinning_wheel"), not its name.

## Step 50b: the integration suite's last CLI-timed combat checks, in timed runs (2026-11-07)
(A side session's, on its own branch `claude/compassionate-panini-246b25`, commit `4ede0bfa`; it was numbered 50 there, as
herbalism's step above is here. MERGED INTO MAIN 2026-11-11, after steps 51-57 were committed: the hook merged with no
conflict. Every integration run in steps 53-56 was WITHOUT it: their "known red" combat checks are the ones it fixes.)

**Why**: integration failed 5 to 8 combat checks on every run, a clean worktree of `54c1973b` too: the pommel bash's
14 (got 0.00), "(its hit, so nothing is left waiting)", the thrust's 800 ms stagger, the slain skeleton's loot ('')
on the ground and in the bag, the bow's full draw (30), archery XP and point blank. The pass count swung ~40 a run.

**The cause** (the test, not the game): each had two or more `spacetime` CLI calls (1-3 s each here, more under
load) between something that runs out and the step that needs it, left over from before step 37:
- A judged request runs out 3 s after it is due (`REQUEST_GRACE_MICROS`, `module/referee.rs`): the string's last
  (943, 953) was read by one CLI call and answered by another, so it often ran out first: "no such request", or an
  empty id ("Invalid arguments ... `resolve_action`"), and then no stagger in the log.
- A dummy is whole again 4 s after its last hit (`regents.dummy_reset_s`): when the pommel bash did land, the dummy's
  health was read three CLI calls later and had already come back (0.00).
- A kill's `foe_kill` row lasts 10 s (`RESULT_TTL_MICROS`, `game/regents.rs`), and five CLI checks came between the
  slaying chop and the loot read: the loot read as '' (and the sacks on the ground did not match it).
- An arrow lives 8 s (`content/body/arrow.tres` `lifetime_s`) and `report_body_contacts` passes over a body that is
  gone without an error: six CLI calls between the loose and the report, so the shot landed nothing (no 30, no XP),
  and point blank measured against the unhurt skeleton.

**Built** (tests only; no game, table or rule change; `game/regents/tests/hooks/integration_genre.sh`): each in one
`timed` run (`game/regents/tests/timed_calls.py`, step 37), the reads it needs taken in the run:
- Roles: the string's last (943, 953, 963), its request read (`sqlwait`), the fired ability read, answered at once, the
  dummy's health after; 700 ms after the second (past its lock, as a press comes). The first two still lapse as misses.
- Foes: the skeleton's slash at you, its sweep on skeleton_2, the new skeleton's slash, the rallying cut at the
  skeleton (your health just before and after the answer, so regrowth is not counted).
- The slaying chop reads its `foe_kill` loot in the run (`HITS_READ`), and a new check: the server's log says you slew
  it, and what dropped.
- The bow: `shot NAME DRAW_MS Z` draws, looses DRAW_MS later, finds the arrow, reads the arrows left, the
  skeleton's health, reports the hit and reads the health after and whether it fell, all in one run.
- What the first runs of the fix taught (each a mistake of the new reads, not the game's):
  - A FOE'S HIT ON A PLAYER IS HELD for a late parry (`held_hit`), to its landing + `regents.parry_late_ms` +
    `foundation.rewind_max_ms` + `press_credit_cap_ms` (~540 ms after the swing): your health is read 1 s after the
    answer, and the "you are slain" log check waits 1 s (read at once, the slash did nothing: 100 -> 100).
  - "a second on, its body is gone" and "the camp waits" are read straight after "the camp knows it fell": after
    the loot and the meta's checks, twenty CLI calls outlasted the test's 40 s respawn (the camp was back).
  - An empty stack has no `inventory_item` row: an in-run read of none is "-", counted 0 as `QTY` counts it.
  - `timed_val` took awk's third field, so an EMPTY string (a kill that dropped nothing: `foe_kill.loot` '') read as
    the step's ms ('9'); it now takes everything between the name and the ms.

**Tested**: integration on the test database alone, three runs in a row on the final hook: 1303/0, 1290/1, 1286/2, none of the combat checks above among the failures (the three are the
foundation's: "the push stays where it happened", the body contact read "once", Help up's third helper "again";
each a row or a hold that ends 2-5 s on, read two or more CLI calls later: the template's to time, `../UMF Template`). The server's
log of each has the pommel bash's 1200 ms stagger and the thrust's 800 ms, both kills (one dropped nothing, the
empty-loot case), two 30-point shots and the point-blank 5.4, the rallying cut's 8. The negative: the old hook, the
same checks CLI-timed, failed them every run (the task's report; the cause above); the first runs of the fix failed
on each new read taken too early (the held hit, an empty stack, an empty loot), so the reads check what they say.
(An earlier attempt at a baseline ran two of this session's suites on the database at once, from a stop that left
`integration_test.sh` running: its failures, foundation and skilling ones too, were that, not the game. Stop a
suite by its whole process tree.)

**Left**: the skilling chain's `play_round` sleeps the round's length from when the bot ENDS, not from when the round
was dealt: three CLI reads + the bot (6-7 s) + the sleep reach close to the round's 30 s (10 s + `ROUND_GRACE_MICROS`)
when the CLI is slow; it passed on every clean run (a margin, not a failure). The main checkout's minigame session
has the helper in its work.

## Step 51: herbalism, step 2: PULL THE ROOT, flax's round (2026-11-08)
**Why**: `HERBALISM_HUNTING_PREP.md` §7 step 2, Luke's H3 (2026-11-07, `GAME.md`): "hold to pull, strain rises and eases
when let go, the plant trembles before a jump, past the top it snaps; band 2 roots that branch, band 3 a wilting
clock"; H2: the round shows the trowel loosening the soil before the pull. Flax (step 50) was AFK only.

**Built** (a NEW kind, `pull` = challenge 106; no table, reducer or argument changed: an old client, which does not know
106, ignores the round, as with 104 and 105):
- `PullParams` / `PullModel` (`game/regents/skilling/herbalism/`), the Rust twin `server/src/genre/regents/pull.rs`
  (`Minigame::Pull`, `CHALLENGE_PULL`, claimed in `CLAIMS`; the bake `server/build/regents.rs` takes kind "pull" on a
  node and refuses one that cannot be played), a third copy in `make_skill_goldens.py` writing
  `shared/golden/regents/pull.json` (16 cases; the older golden files byte for byte the same). The rules are written
  out on `PullModel`, in ticks of 50 ms:
  - the trowel LOOSENS the soil for `loosen_ms` (600; a faster trowel shorter, as an axe's swing: `with_speed`);
  - HELD: the strain rises 40 a tick, the root comes up `pull_rate` + strain x `pull_gain` / 1000 (3 + up to 12: a
    harder pull brings it up faster); LET GO: the strain eases 60 a tick;
  - CATCHES: three a root, each in its own stretch of it, from the seed; pulling through one jumps the strain
    200-400; the plant TREMBLES from `tremble_depth` (250 of the root's 1000) below it. Nobody sees where or how big;
  - past 1000 it SNAPS: worth `snap_keep_pm` of what came up; up whole is worth 1000; (as first built, the round ended
    there: since Luke's answer below it is a CLUMP, the next stem starting);
  - `target_plants`: whole roots for a full score. Rank eases it (M3): the catches jump less.
- `PullStage` (`pull_stage.tscn`, a scene a designer can open: the camera, the mound, the meadow, the trowel's two
  poses `TrowelRest` / `TrowelDig`): the nature pack's flax plant in a mound of soil, a placeholder copper TROWEL
  (`trowel.tscn`, no model in the packs) floating beside it and digging while the soil loosens. Pulled, the plant rises
  out of the mound with its root; the stem STRETCHES and LEANS as the strain rises and creaks louder and higher (no
  strain meter: the player reads the plant, H3); it SHIVERS while it trembles; a catch jolts it; a snap throws the top
  off with a stub of root and fibers; whole, it comes out with all its root. Sounds (`make_skill_sounds.py`, ours):
  dig, strain, catch, snap, up.
- `PullMinigame`: hold Space or the left mouse button to pull, let go to ease; "Loosening the soil...", "Snapped!",
  "Up whole!". Registered in `SkillMinigames` (kind, challenge 106, UI, replay, speed, ease); `NodeDef.validate`
  takes a `PullParams`. The HUD's prompt at flax now offers "Hold E: play" (it gates on the node having a round).
- FLAX (`content/node/flax.tres`): the round (first built 12 s, ONE plant; now a clump: below). The readout's players
  (`MinigameReadout._pull`: read the strain off the plant give or take their aim, a press a moment late, let go at a
  margin under the top; a tremble seen `react_ms` late, eased under the worst catch and pulled through; a slip misses
  it), the integration hook's bot (`skill_bot_cli.gd --kind=pull`).

**Tuning, first pass (mine; the numbers are Luke's after his play)**: a gathering round is paid for its whole length,
so with ONE plant a round a quick clean pull would pay more per minute than M11's 1.25x. A first pass (the pull 10 +
40 a tick) came up in about 3 s of 12: five times AFK. The pull was slowed (3 + 12) so a clean pull takes most of the
round (the flawless player's ends at 10.7 s on average, so at most ~12 % over M11). The tremble was lengthened (120 ->
250 of the root) after the first readout: at 120 a skilled player (200 ms to react) had pulled into the catch before
seeing it. A CLUMP (8 plants, 4 for a full score, 15 s) was measured too and came out too easy at the bottom (careless
69 %, beats AFK 98 %); it stays in the model as a number (`plants`) for Luke's choice. Asked of Luke through the session
that started this one: one plant a round or a clump (no answer by the end of this step; flax follows the sheet).

**The readout** (200 seeds; AFK pays the same at 50 %): flax flawless 100 / skilled 89 / average 68 / careless 44 %
mean; beats AFK 100 / 86 / 50 / 14 %. Three ranks on (12 % easier catches): 100 / 93 / 79 / 49, beats AFK 100 / 91 /
71 / 21. For comparison the tree is 100 / 100 / 99 / 95 and the copper rock 100 / 100 / 98 / 56 (the smelt 98 / 91 /
77 / 57): flax is the hardest tier-1 gathering round, and the only one where a poor round falls short of AFK as M11
asks. Luke's play decides (the windows, the tremble's length, the snap's share, one plant or a clump).

**How to play it**: publish (done), restart. Walk west of the spawn to the flax with a trowel; hold E: the trowel
loosens the soil, then hold Space (or the mouse) to pull and let go before the stem strains too far; when the plant
shivers, ease right off, then pull through gently. The lab (F6): Flax. In the readout: Flax.

**Tested**: Rust (`cargo test`, every suite green): the twin plays the 16 golden rounds exactly; rank eases
the catches and a faster trowel loosens sooner (a catch that snaps a root as authored lets it up whole eased); flax is
dealt as 106 and the genre claims it. Negatives: the top read as `>= 1000` fails the goldens on both sides ("held to
exactly the top: 1000 holds", added when the first negative passed: no case landed on exactly 1000); the root's rise
taken before the strain's fails the Rust golden. Unit (lints + regents) 3252/0: the goldens; the rules (the
loosening, the rise and ease, a snap past 1000 and not at it, a catch trembling first then jumping, whole, a clump, a
root still in the ground); the registry (106, the speed, the ease); 24 rounds in the lab; flax valid with its round, a
node with none still valid, a station's round on a node refused; the stage driven by Space (it digs, rises and
stretches, eases, snaps; the replay agrees); A PULL ROUND DEALT BY THE SERVER FINDS THE NODE (the skilling playtest
found the client looked a node's round up only for chop and crack, so it looked for a recipe and dropped the round;
now `SkillMinigames.GATHERING` / `gathers()` is the one list, used by the component, `NodeDef.validate`, `with_speed`
and the bot; negative: the old lookup fails the check). The readout: every simulated round replays exactly.
Integration 1315/13: kind 106 dealt at flax at the trowel's speed, the bot pulls it up whole and is paid flax and XP
(the `work_result` row), a snapped round scores under half, tap E still works it AFK, no trowel no flax nor round,
no flax no bowstring (the bag emptied first now: the rounds pay flax). The 13 are the referee-paced combat checks and
the foundation's referee, hold and push races, none of them skilling. The first run lost the pull round (and the
copper rock's) to "no such challenge": the hook's `play_round` waited its full time AFTER the bot's Godot started,
which took up to 20 s on the loaded machine, past the server's grace; it now counts from the deal. Skilling playtest
105/0 + 8/0: a real client at 150 ms, the prompt offering a round, the round in the middle panel on its stage, played
by the frame (pulled up whole through its three catches), flax and herbalism XP paid, E stopping the run after it.
Windowed shots (`build/pull_*.png`, ignored): the first had the nature pack's plant at 1.3x filling the panel (the
model is 2 m tall); it is 0.3x now, the camera further back.

**Left**: Luke plays it (the feel, the numbers); a trowel model and a pulling clip (needs
`adventurer.tres`, his editor's); band 2's branching roots (hemp, nettle: §7 step 6) and band 3's wilting clock.

### Then: A ROUND IS A CLUMP (Luke, 2026-11-08, the same day; `GAME.md`)
Asked one plant a round or a clump, Luke: "A: a clump". Stems are pulled one after another until the time runs out; a
snap loses the rest of that stem, never the round (as chop and crack count pieces). Everything above that describes
one plant a round (the slowed pull, "the round ends there") was the first build, superseded here.
- THE MODEL (all three copies): `PullParams.plants` is gone (no count: the round runs to its time). Each stem DRAWS
  ITS OWN CATCHES from the seed's stream as it starts (the first at the start; `start` returns the first stem's, which
  is what the goldens hold). A stem done, whole or snapped, the next starts on the next tick with its own loosening; the
  button stays as it was (held on, it pulls again once the soil is loose). At the end a stem still in the ground is
  worth `snap_keep_pm` of what came up. `over` is now only the round's end. The minigame counts "Whole n   Snapped n".
- FLAX, FIRST TUNING AS A CLUMP (mine; his after his play): 12.5 s, three whole for a full score (`target_plants` 3),
  the pull back to 10 + 40 a tick (a clean stem ~3 s with its loosening: the round no longer needs to be slow, since it
  runs its full time whatever the pace), a snapped stem worth a QUARTER of what came up (`snap_keep_pm` 250: at half,
  a careless player snapping stem after stem still scored 66 % and beat AFK 90 % of rounds). Catches, jumps (200-400)
  and the tremble (250) unchanged. `PullParams`' defaults are flax's numbers.
- Measured on the way (`build/pull_tune.gd`, ignored; flawless / skilled / average / careless, mean %): 10 + 40, keep
  500, 12 s: 100 / 82 / 76 / 67; keep 250: 97 / 83 / 68 / 55 (the flawless player one stem short in some rounds);
  keep 0: 96 / 78 / 58 / 42; 12.5 s, keep 250: 100 / 89 / 72 / 58 (chosen); 13 s: 100 / 90 / 76 / 61.
- **The readout** (200 seeds): flax 100 / 89 / 72 / 58 % mean, beats AFK 100 / 99 / 92 / 62 %. Three ranks on (12 %
  easier catches): 99 / 88 / 77 / 63, beats AFK 100 / 100 / 96 / 78. Easier at the bottom than the one-plant round
  (careless 44 %), close to the copper rock (careless 56 %) and the smelt (57 %). His to change after he plays.
- Tests: the goldens (17 cases; the one-plant ones are clumps now, plus "held through the clump: stem after stem
  snaps, each after its loosening" and "a clump runs to the end"), the unit rules (a snap loses that stem, the next
  loosens with nothing up; held on, stem after stem snaps; whole stems every 700 ms to the end, 17 in 12.5 s and the
  18th worth a quarter of its 800), the stage (a snap, then the next stem loosens; the round ends at its time), the hook
  (the bot pulls three whole: its puller scored 1000 on all 200 seeds offline; held from the start, every stem snaps,
  under half), the skilling playtest (two whole or more by the frame). Negatives: a stem that does not draw its own
  catches fails the goldens on both sides.

### Then: THE TROWEL DOES THE WORK, and the stage redrawn (Luke's play, 2026-11-08, the same night)
Luke played the one-plant round: "it was not very fun, I think in addition to changing it to clumps, we use the trowel
more to outline and dig in the earth, cut roots that are snagging etc", and "the shaking was too much it looked like
jittering and the root was strange looking and abnormally long. definite polish and redesign of the visual storytelling
of the minigame is needed". Going to bed, he left the choice to me: "it can choose the best path forward, right now the
other minigames are in a decent place so matching those in terms of difficulty and skill plus reward". EVERY CHOICE
BELOW IS MINE, for him to change after he plays; only the clump is his (`GAME.md`). The clump work above (no plant
count, each stem its own draws) carried over; its tuning (12.5 s, the automatic loosening) did not.
- THE ROUND, TWO HANDS (`PullParams` / `PullModel`, the Rust twin, the Python copy; challenge 106 and its payload
  unchanged, new input codes LEFT 3 / RIGHT 4):
  - A / D (or the arrows) STROKE THE TROWEL on that side, a stroke taking `stroke_ms` (250; a better trowel faster, as
    an axe's swing: `with_speed` now scales the stroke), no other stroke and NO PULLING while it runs (the strain
    eases). Chop's keys, so the left hand already knows them.
  - DIG: each stem starts PACKED on both sides (1000); a stroke digs its side `dig_pm` (500: two strokes a side).
    Packed soil HOLDS THE ROOT: it comes up at (1000 - mean pack x `hold_pm` / 1000) of its pace (`hold_pm` 600:
    packed all round, 40 %). The automatic loosening (`loosen_ms`) is gone: the player outlines the stem.
  - CUT: each stem has `snags` side roots (2), each at a seeded depth, jump and SIDE. Once the root is coming up, the
    next side root within `show_depth` (350 of the root) below what is up makes the soil CRACK on its side; a stroke on
    that side cuts it (it never catches); a stroke on the other side only digs. Uncut, pulling through it jumps the
    strain (200-400) as before. (First built, a side root shallower than `show_depth` showed before any pulling, so the
    opening dig on that side cut it instead: it shows only once some of the root is up.)
  - PULL as before: hold to pull, the strain rises 40 a tick and the root comes up faster at a higher strain (10 + 40
    at full), let go it eases 60; past 1000 it snaps, worth `snap_keep_pm` (250) of what came up; whole is 1000. Stem
    after stem until the time runs out (15 s), three whole for a full score.
  - Rank (M3) eases the side roots' jumps AND the packed soil's hold (both 12 % at three ranks on): the jumps alone did
    nothing to a player who cuts every side root.
- THE STAGE, REDRAWN (`pull_stage.tscn` / `.gd`): the camera low and close on the mound; a CLUMP of three stems behind
  the front one (it thins as stems are taken and grows back); the mound in two halves that SINK as each side is dug, a
  dark furrow opening; the trowel (scaled to the plants by its markers) rests at the left and stabs into the side
  pressed (`DigLeft` / `DigRight`, a designer drags them), throwing clods. NO SHAKING: a side root about to catch
  CRACKS the soil on its side, heaves a few clods and pushes its pale tip out, and the stem leans a hair away; cut, the
  tip flies off; pulled through, the soil bursts on that side and the stem dips. THE ROOT: short (0.08 m, about a
  quarter of the stem) and tapering, with three rootlets (it was a 0.3 m cylinder, half the plant's height). Whole, the
  stem is lifted clear and laid on a PILE beside the mound, root to the mound; snapped, the top falls away. The stem
  still stretches a little (8 %) and leans with the strain, and creaks. Shots: `build/pull_1_digging.png`,
  `pull_2_crack.png`, `pull_3_pile.png` (ignored; `build/pull_shot.tscn` retakes them).
- THE MINIGAME (`PullMinigame`): A / D and the arrows stroke, Space or the left mouse button pulls; "Cut!", "Snapped!",
  "Up whole!"; counts whole and snapped; the summary adds the cuts.
- THE PLAYERS: the readout's (`MinigameReadout._pull`: dig both sides round first, a stroke a moment after the last, a
  slip forgetting the rest of the digging; pull with the strain read give or take their aim; stroke a crack's side
  `react_ms` after it starts, a slip the wrong side), the hook's bot (`skill_bot_cli.gd`: dig, cut every crack, pull
  880/450; a full score on all 200 seeds offline), the skilling playtest's frame player (real A / D key events).
- TUNING, FIRST PASS (mine; `build/pull_tune.gd`, 120 seeds; flawless / skilled / average / careless mean %):
  - the round is a race against the clock (more stems), so a skilled player pulls ~70 % of a flawless one's stems
    whatever the numbers; the tree and rock rounds answer this with a target under a flawless pace, and so does flax:
    `target_plants` 3 where a flawless player pulls ~4;
  - 3 side roots, one stroke digs a side, 15 s, target 3: 100 / 85 / 75 / 62; 2 side roots: 100 / 92 / 83 / 67; two
    strokes a side, a 250 ms stroke, 15 s: 100 / 86 / 71 / 62 (CHOSEN: more trowel work, as Luke asked, at a pace
    near the copper bar's 98 / 91 / 77 / 57); 16 s: 100 / 91 / 76 / 67; a stronger hold (700): skilled 74;
  - the snap's quarter, the strain's rise and ease, the pull's rate and the jumps unchanged from the clump's tuning.
- **The readout** (200 seeds): flax 100 / 86 / 74 / 63 % mean, beats AFK 100 / 100 / 96 / 78 % (pay inside M11's
  0.75-1.25: the hot rules, untouched). Three ranks on: 100 / 94 / 81 / 68, beats AFK 100 / 100 / 99 / 92. For
  comparison: the yew 100 / 98 / 88 / 61, the copper rock 100 / 100 / 98 / 56, the copper bar 98 / 91 / 77 / 57.
- **How to play it**: publish (done), restart. At the flax with a trowel, hold E. Dig round the front stem: A twice,
  D twice (the mound sinks on each side). Hold Space to pull; let go before the stem strains too far. When the soil
  cracks on a side, press that side to cut the root there. Up whole, it goes on the pile and the next stem comes
  forward. The lab (F6): Flax.
- **Tested**: Rust (every suite green): the twin plays the 19 golden rounds exactly (dug round and cut; cut late;
  never digs; never cuts; greedy; held from the start; only strokes; a stroke stopping the pull; the wrong side digs;
  every code out of order; still in the ground; no side roots; exactly the top and one past; a quick trowel, eased;
  flax as tuned, two ways); rank eases the jumps (a side root that snaps stems as authored never does eased) and a
  faster trowel starts the pull sooner. Negatives: a stroke on either side cutting fails the goldens on both sides; a
  stem not drawing its own side roots failed them too (the clump's step). Unit (lints + regents) 3252/0: the goldens
  with each stem's sides; the rules (packed 4 a tick, dug 11; strokes dig 500, none while one runs, none past loose; a
  stroke stops the pull; exactly 1000 holds, one past snaps worth a quarter, the next stem packed; a side root shows
  near it on its side once the root comes up, the other side digs, its side cuts; uncut it jumps the strain; stems dug
  anew, whole after whole); the registry (a stroke at half the time at 50 %, the jumps and the hold eased); the dealt
  round (a 125 ms stroke at 50 %); the stage (A digs the left: the half sinks, the furrow opens; held, the stem rises
  with its root; the crack and its tip on the right side only; a stroke there cuts, "Cut!", the tip flies; held on it
  snaps and the next stem comes forward packed; the round ends at its time; the replay agrees). The readout first
  caught a simulated stroke landing before the moment the model had run to (live and replay disagreed for the jittery
  players): fixed in the sim.
  Integration 1319/9: kind 106 dealt at flax at the trowel's speed; the bot digs round, cuts and pulls three whole
  (a full score) and is paid flax and XP (the `work_result` row); held from the start every stem snaps (under half);
  tap E still works it AFK; no trowel no flax nor round; no flax no bowstring. The 9 are the referee-paced combat checks
  (pommel, thrust, the foe's loot, the camp, archery) and the foundation's hold, none of them skilling. Skilling
  playtest 105/0 + 8/0 (the first run failed one smithing check, the Iron axe's assembly, and passed on the rerun):
  a real client at 150 ms played the round by the frame with real A / D keys: 4 whole, 8 cut, 17 dug, a full score,
  the replay agreeing; flax and herbalism XP paid. Published `regents-rule` (no wipe, no codegen). The trowel's
  markers were first written transposed (a scene's `Transform3D` is by rows), so its blade pointed outward; the shots
  caught it.

## Step 52: Luke's play of every minigame: the pattern fades, a hold sets it down, no quench, the pay shown, pull the root's cutaway (2026-11-09)
**Why**: Luke played every minigame (2026-11-09). His words: mining and woodcutting "feel good from tiers 1-3"; smelting
"decent", but "the slag being the f key threw me off ... a slower start to read the directions would be nice"; "all
minigames should have woodcutting like overview where it shows how many rounds and the current pay off"; smithing and
the carve "much harder than the others"; "the smithing bands were much too hard as enter turns in the tool and stops the
minigame"; "the herbalism game is not as fun". HIS SCORES (the play database's log, all 52 rounds that day): yew 63-100 %,
coal 47-84 %, copper and iron rock 100 %, smelting 84-91 % (copper, iron), 58-76 % (steel, with slag), flax 7-100 %;
the anvil 57 % (copper sword), 0 then 57 % (iron trowel), 61 % (steel trowel), 6 % and 0 (steel pickaxe), 6 % (steel
axe); the yew bow 0 twice. Every 0 and 6 % was a part set down far off the outline by ONE Enter (6 % = the quench's
bonus on nothing). The readout had the anvil easy because its simulated smiths see the outline the whole round.
Asked, he chose (`GAME.md`, "Luke's play of every minigame"): the pattern fades by band (copper 3 s to a faint ghost
that stays, iron 1.5 s to a fainter one, steel 3 s to nothing; the carve too); the quench out for now ("im confused on
what the quench does ... maybe we get rid of quenching for now or redesign it"); pull the root "Cutaway, no chore".
He did not pick how a round is finished: a HOLD is mine (his question showed one Enter ending the round was the trap).

**Built**:
- **The pattern fades** (`ShapeParams` / `CarveParams` `pattern_fade_ms`, `pattern_ghost_pm`; `MinigameLook.pattern_alpha`):
  full while laid on; lifted, the outline fades to the ghost and stays. Presentation only: the round, its score and the
  server's replay are unchanged (no Rust, no goldens). Set on every anvil recipe and pattern by metal, and the yew bow
  and staff as copper (the carve's only wood, so its gentlest).
- **Finishing is a HOLD** (`SkillMinigame.finish_key`, `finish_hold_begin/end`, `_finish_held`, `FINISH_HOLD_MS` 600):
  Enter or the anvil's button held 0.6 s sets the part down (the carve's piece too); a bar fills (under the anvil's
  buttons; the carve's at the foot); a tap says "Hold Enter to set it down" and does nothing else.
- **No quench**: the quench's four numbers off the three steel heads (the model keeps it, 0 = off; red heat stays).
- **The trowel blades' bands**: the material table had made the iron and steel trowel blades from the copper pattern,
  so they had copper's rules; now iron's (more metal, a lighter strike, each look costs) and steel's (+ red heat).
- **The pay shown on every round** (`SkillMinigame.pay_afk` / `pay_item` / `pay_words`, set by the HUD from
  `SkillingComponent.afk_items_in` and the two hot rules): "This round: about 2.1 Copper ore" under the time bar, top
  right, from the score so far as the server pays it; the run's tally under it ("This run: 2 rounds: 5 Copper ore",
  moved from the left). Gathering and smelting; the anvil and the carve make one graded thing and show none.
- **Smelting's slower start**: the count-in 4 -> 8 beats on all three bars; through it the directions big over the
  stage, each note drawn as it looks with its key (the slag's square: "F or right click skims it").
- **PULL THE ROOT, CUTAWAY, NO CHORE** (a rule in all three copies: `PullModel`, `genre::regents::pull`, the goldens'
  Python; `PullParams.loose_pm`, 0 = as before): each side of each stem starts LOOSE with a chance, from the soil's OWN
  stream (`seed ^ LOOSE_SALT`, so the side roots never change); flax: loose half the time, ONE stroke digs a packed
  side (`dig_pm` 1000), FOUR whole stems for a full score (three made it too easy: the readout's careless player 89 %).
  THE CUTAWAY (`PullMinigame._draw_cutaway`): a slice of the soil left of the mound: each side packed (dark, "A: dig")
  or loose; the root rising as pulled; every side root still on it climbing to the surface (where an uncut one catches);
  the gold band where the trowel reaches one ("A: cut"); and a STRAIN BAR beside it with the next catch's jump marked
  (the stem still stretches, leans and creaks). The 3D stage draws a loose side already dug.
- Readout: flax 100 / 94 / 88 / 69 % (the yew 100 / 98 / 88 / 61, the copper rock 100 / 100 / 98 / 56).

**How to play it**: publish (done), restart. The anvil: lay the pattern (Space), lift it, watch it fade; HOLD Enter (or
the button) to set the part down. Smelting: the count-in shows each note and its key. Gathering: the pay so far and the
run, top right. Flax: the slice on the left says which side is packed (A or D digs it), where a side root can be cut
(gold), and the strain.

**Tested**: Rust (every suite, the wasm check) green: the pull twin plays the 23 goldens exactly, the 19 old ones
unchanged (the Python's loose stream draws nothing at `loose_pm` 0) and 4 new (only the packed sides dug; never digs;
every side loose; a stroke into loose soil scrapes); the smelt's length pinned at 18.4 s. Unit (lints + regents)
3253/0: every anvil band's rules by metal, the trowel blades included (steel: red heat, no quench), and each band's fade
(3000 / 250, 1500 / 120, 3000 / 0); the iron anvil's outline fading 1.00 -> mid -> 0.12 once lifted; the carve's
Enter: a tap kept, a part-way hold not yet, a full hold sets it down (negative: the old one-press test failed against
the hold, as it should); flax's 80 sides of 40 seeds loose and packed, the side roots the same as with none, a loose
left side drawn dug and the packed right not. Readout: flax 100 / 94 / 88 / 69. Integration 1337/20: none skilling (the
bot dug only the packed sides, cut, pulled four whole, a full score, paid); the 20: the 13 referee-timed combat checks
known red (pommel, thrust, loot, camp, rallying cut, archery: their fix `4ede0bfa` is unmerged) and 7 foundation
checks (chat, the hold, interact, push) this change does not touch, run while shot scenes loaded the machine. Skilling
playtest 102/0 + 8/0: a real client held Enter to set the anvil's part down, pulled four whole at a full score (8 dug,
10 cut), the replay agreeing. Shots: `build/cut_*.png`, `build/look_*.png`. Published `regents-rule` (no wipe, no
codegen).

**Left**: Luke plays it all again (the fades, the hold, the pay line, the cutaway, four stems); the quench redesigned or
dropped (his call: "redesign it so it makes more sense as a skill thing and described better in instructions"); the
readout's smiths still see the outline all round (the anvil's M4 tuning needs a sim that forgets it); a new cell of the
material table copies its pattern's round, not its metal's band (the trowels were fixed by hand).

## Step 53: hunting, step 3: THE DEER (2026-11-09)
**Why**: Luke, 2026-11-09, after playing step 52: "lets move on to next steps (hunting I believe)".
`HERBALISM_HUNTING_PREP.md` §7 step 3, his H5 (2026-11-07): the deer, tier 1, flees, never fights. (Pull the root
is parked, his: "I cant put my finger on it so lets leave it for now".)

**Built** (no table, reducer or argument changed: an old client draws nothing new and plays on):
- THE MODEL: Quaternius's CC0 deer (Ultimate Animated Animals, `game/regents/art/animals/Deer.gltf`, its license
  beside it), 4.4 m long as made, drawn at 0.38. ITS OWN CLIPS: `game/regents/anim/build_animal_sets.gd` (Fowl Play's
  wolf generator's way, the same pack) writes `deer_clips.res` and `deer_animation.tres`: standing it GRAZES (Eating),
  walks, gallops (run and sprint), Gallop_Jump, the hit react, Death; skeleton family `deer`, its neck and head the
  upper-body bones. No foundation change: the tree builder drives a non-humanoid as Fowl Play's birds.
- CONTENT: `content/foe/deer.tres` (40004: 60 health, a beast, poise that never breaks so a hit never staggers it, no
  loot yet), `content/character/deer.tres` (40009, kind 106, brain `regents/deer`, in `genre.tres`),
  `content/movement/deer.tres` (40003: walks 1.4, gallops 8.6 m/s, a little faster than a player's 8 sprint),
  `content/status/startled.tres` (40010, status 109), the hot rule `regents.startle_ms` (2500).
- A FOE THAT NEVER FIGHTS (`FoeDef.fights`, off: no kit needed, its character's brain runs it; new flee numbers
  `startle_m` 5, `flee_m` 25, `calm_ms` 6000, `graze_m` 6; it sees within `notice_m` 16, never past `leash_m` 45).
  Baked with its brain; the server's `FoeSeed` has `fights` and `brain`; `spawn_foe` writes the seed's brain;
  `hurt_now` STARTLES a creature that never fights on any hit (not once it has fallen).
- THE BRAIN (`sidecar/npc/brains/regents/deer.gd`): graze (a few steps at a walk to a spot near home, then stands
  4-10 s), flee (a player seen within 16 m, heard within 5 m, or the nearest within 60 m once Startled: 25 m straight
  away at a gallop, inside its leash; on while anyone is near), home (calm 6 s with nobody near: back at a walk),
  slain. A route is planned once per threat, not each think.
- PLACED: one in the glade (`frontier.tscn` deer_1 at (-30, 5), west past the flax; the continent copies the glade's
  camp, so one is near the continent's start too) and 61 more in PAIRS over the continent's open meadows from THEIR
  OWN random stream (`build_continent.gd` `_deer_pair`, `DEER_SHARE` 0.1): all 719 points before are where they were
  (checked against the last bake); 782 now. The cell files' churn is only Godot's fresh node ids, as every rebuild.
- Slain, it pays weapon mastery XP and drops NOTHING: its carcass is skinning's (step 4, H1).

**How to play it**: publish (done), restart. Walk west past the flax (glade or the continent's start), or roam the
continent's meadows: deer graze in pairs. Close in and it bolts; a bow is the way (or corner it). Hit it from out of
its sight and it bolts too.

**Claude's defaults, Luke's to change**: every number above; standing it always grazes (head down) even just after
fleeing; 2 a herd; no loot until skinning.

**Tested**: Rust (every suite, the wasm check) green, with `the_deer_never_fights_and_has_its_own_brain` (no kit, its
brain, a foe kind; every other foe fights with a kit and the foe brain); the finisher test now covers only fighters.
Unit (lints + regents) 3261/0: the deer's content (never fights, no kit, its brain, the genre's, a beast, its own
clips: it gallops, faster than a sprint, never staggered; a fighter with no kit still refused) and ITS BRAIN on a
made-up world: nobody near it grazes at a walk within 6 m; a player seen 12 m off sends it 25 m straight away at a
gallop, the route planned ONCE over six thinks; calm 6 s it walks home; heard 4 m off unseen it bolts; an archer 40 m
off unseen leaves it grazing until it is Startled, then it runs from them; chased at its leash's edge it runs no
further; slain it lies still. The calm-and-go-home test caught a real bug first (its flight's goal was never let go,
so it never walked home). Integration (re-run) 1324/23: the deer's every check passes (kind 106, 60 health, its brain;
not startled unhurt; a chop Startles it, from the server's log as the 2.5 s status outlasts the CLI's calls; worn
down, the killing chop leaves it Slain, never Startled after; it fell; its loot empty, no kill row; XP paid); the 23
are the referee-timed combat checks known red (their fix `4ede0bfa` is unmerged) and foundation checks (chat, holds,
pushes) this does not touch, on a run that took ~70 min. DEER PLAYTEST (new, `game/regents/tests/deer_playtest.sh`, a
REAL REFEREE) 13/0: the deer driven by its brain; nobody near, it stays within 4.4 m of home (the negative); a
standing bot (the player's kind) 9 m off: it is off at a gallop (at the least 3 m/s from the bot's coming to the next
look; the CLI's looks are seconds apart), 21-26 m from home, 30 m from the bot; the bot gone, it walks back near
home and never gallops there. NEGATIVE: a brain that walks while fleeing fails it (1.36 m/s). A shot
(`build/deer_look.png`): shoulder high to a person, grazing head down, galloping. Published `regents-rule` (no wipe,
no codegen): deer_1 and the continent's pairs are standing there.

## Step 54: hunting, step 4 (first half): SKINNING, AFK; the knife; tanning (2026-11-09)
**Why**: Luke, 2026-11-09: "Start skinning". `HERBALISM_HUNTING_PREP.md` §7 step 4, his H1 (a Skinning skill, a
carcass you skin), H6 (tanning at an AFK rack), H7 (Deer hide, Soft leather). Asked first (`GAME.md`): the tool, "A
smithed knife"; who skins, "Killer first, then anyone". Like herbalism, AFK first: the drag-the-knife round (H4) is the
next step.

**Built** (one table added, private: `carcass`; published with `--codegen`):
- SKINNING (`content/skill/skinning.tres`, 40011; its pose the reach until a skinning clip is in).
- THE KNIFE: two patterns of the material table, `knife_blade` (40014: the anvil, one bar, a smithing round, a long back
  and a curved edge) and `knife` (40015: the workbench, the blade the core and a grip; tool tag `knife`); "Make the
  table" made copper, iron and steel cells (items 40058-40063, recipes 40047-40052); the iron and steel blades given
  their metal's anvil band by hand (the table copies the pattern's copper round). The COPPER KNIFE (40059) joins the
  STARTER KIT (new characters only).
- THE CARCASS: `FoeDef.carcass` (a NodeDef: what a kill LEAVES); the deer's is `content/node/deer_carcass.tres` (40008:
  Skinning rank 1, a knife of tier 1, ONE Deer hide (40056) and it is worked out, 5 s AFK, 15 XP, no round yet). Its
  look is the deer held at its Death clip's end (`art/animals/deer_carcass.tscn`, `posed_clip.gd`); skinned, it sinks
  away (the rubble look, dark red). Server (`game/regents.rs`): `fell` leaves it where the deer fell (`leave_carcass`:
  a gather node, point id `carcass_<foe>`) and takes the body away at once; the `carcass` row says whose it is (the top
  damager among players, from `damage_share`, else the killer; nobody's for an admin's felling) and when it fell;
  `gather` refuses another player for `regents.carcass_own_s` (60 s; `genre::regents::carcass_owned_ms`); `deplete`
  marks it skinned and `tick_carcasses` takes it away 2 s later, or once it has lain `regents.carcass_rot_s` (180 s).
  The prompt says "E: skin the deer carcass (AFK)" (the knife's verb).
- TANNING: the TANNING RACK (`content/station/tanning_rack.tres`, 40006; an AFK station trained by Crafting, a
  PLACEHOLDER BLOCK until a model is found), placed by the spinning wheel in the glade (and so in the continent's camp:
  rebuilt, no other point moved); SOFT LEATHER (40057) from one deer hide (recipe 40046).
- The workbench's list heads the knives "Knives" (`SkillingComponent.plural`), not "Knifes".
- `admin_slay(foe, killer)` (a new ADMIN reducer): a foe slain as `killer`'s kill (any entity, 0 nobody) through the
  genre's own fall (loot, carcass); an admin's `apply_damage` never reached it. For the suites, and for an admin.

**How to play it**: publish (done), restart. A NEW character has a copper knife; an old one smiths a knife blade (a
copper bar at the anvil) and assembles a copper knife (the blade and a grip at the workbench). Kill a deer (west past
the flax): it lies where it fell; tap or hold E at it to skin it (5 s); the hide to the tanning rack (by the spinning
wheel) for soft leather.

**Tested**: Rust (every suite, wasm) green: the chain lists (eight nodes with the carcass, eleven skills, six stations),
the carcass (a knife, one hide, no rare, the deer's), the copper knife in the starter kit, `carcass_owned_ms` (the
owner at once, another the rest of the minute, then anyone; nobody's is anyone's), tanning. Unit (lints + regents)
3287/0 then 3286/1 (a tools check timing a script while an integration suite ran: TO RECHECK): the counts (eighteen at
the anvil, twenty-nine at the workbench, one at the rack; fifteen patterns, 45 cells, the copper knife 40059; four
tiers out of date with iron moved; 27 rounds in the lab), the carcass node (knife, no round, one hide, the deer's,
its footprint), the workbench's "Knives". SKILLING PLAYTEST (a real client) 113/0 + 8/0 with a new skinning leg: the
glade's deer slain as the client's kill (`admin_slay`), its carcass in the client's world, the prompt "E: skin the
deer carcass (AFK)" with no round, tap E, one deer hide and Skinning XP, the carcass taken away, the hide tanned at
the rack into soft leather. INTEGRATION: the carcass where the deer fell, its body gone at once, yours first (the
log); skinning begun; ANOTHER'S KILL (a bot's, by `admin_slay`) refused you, then (its time made 0) anyone's; an
admin's slaying needs a killer that is, and not twice; unskinned it rots (its node, entity and row); the rack refuses
with no hide, tans with one. (The CLI's player is offline between calls, so AFK work pays nothing there: the payouts
are the playtest's.) RESULT (a clean run, 2026-11-09): 1363/31, NONE of the deer, skinning or tanning checks; the 31 are
the referee-timed combat checks (fix `4ede0bfa` unmerged) and the steps that follow them (the player slain, the
string at the skeleton, archery's kill and arrows) and foundation timing checks (chat, holds, the ball, a push). A shot (`build/carcass_look.png`): it lies on its side. Published `regents-rule`
with `--codegen` (the `carcass` table and `admin_slay`).

**Not yet**: the drag-the-knife round (H4, next); the leather wrap (its traits are Luke's to design with him, H8); a
knife model in the hand; a tanning rack model; a skinning clip.


## Step 55: the deer smooth shaded; each node says its own "worked out"; SKINNING'S ROUND, THE CUT LINE; a deer holds several hides (2026-11-10)
**Why**: Luke, 2026-11-10, after playing the deer and skinning: "The deer seems fine and is working. I think id prefer it
to be smooth shading instead of low poly"; "the skinning has mining text in it" (a skinned carcass said "The rock is
worked out"), "i think herb has tree text" (picked flax said "Timber!"); then "we can get started on skinning minigame".
Asked what a better cut should get when a carcass held one hide (today's pay could not show skill on it): "Skinning a
whole deer would get you multiple hides so we can have it be like a node depletion and good rounds reward more up to a
cap of course" (`GAME.md`). Asked about tanning's and spinning's rounds after it: "Neither yet, wolf next".

**Built**:
- **THE DEER, SMOOTH SHADED**: an import script on `Deer.gltf` (`art/animals/smooth_shading_import.gd`, its `.import`'s
  `import_script/path`) gives every corner at a point the average normal of the faces round it (SurfaceTool's normals
  by point), tangents remade; the shape, colors, skin and clips untouched; edges between surfaces stay crisp. The
  carcass is the same model, so it is smooth too. Another of the pack's animals takes the same script in its `.import`.
- **EACH NODE SAYS ITS OWN** (`NodeDef.depleted_notice`, `depleted_prompt`, presentation only, no bake): trees "Timber!"
  / "felled, growing back"; rocks "The rock is worked out" / "worked out, coming back"; flax "The flax is picked bare" /
  "picked bare, growing back"; the carcass "The carcass is skinned" / "skinned". The HUD guessed tree or rock before.
- **THE CUT LINE** (a NEW kind, `skin` = challenge 107; inputs are (time, x, y) triples like the rock's; an old client,
  which does not know 107, ignores the round): `SkinParams` / `SkinModel` (`game/regents/skilling/skinning/`), the Rust
  twin `server/src/genre/regents/skin.rs` (`Minigame::Skin`, claimed; the bake takes kind "skin" on a node), a third
  copy in `make_skill_goldens.py` writing `shared/golden/regents/skin.json` (15 cases; the older golden files byte for
  byte the same). The rules, written out on `SkinModel`, in ticks of 50 ms, whole numbers:
  - the hide is 1000 x 1000; each LINE is drawn from the seed as it starts: left to right or back, `points` points
    (5) from 100 to 900 across, each up or down by up to `wobble` (120);
  - the knife HELD in the hide at K: on the line (within `near`, 45, of the tip's stretch or the next) and within
    `reach` (120) of the cut's end, it CUTS: the cut runs to K's place along the line, no faster than `cut_speed` (30 a
    tick; a better knife faster, as an axe's swing); anywhere else it TEARS (each tear costs that line `tear_pm`, 35 of
    its 1000). Lifted, nothing happens: let go to stop safely, press again at the cut's end;
  - A BEND: a knife already on the next stretch, past the bend, runs the cut to the bend (the readout's flawless hand
    stuck at sharp bends without it: its projection on the old stretch was behind the tip);
  - a line cut through: worth 1000 less its tears, the knife lifts, the next line is drawn; at the round's end a line
    part cut is worth half (`part_keep_pm`) of what was cut; the score is the lines' worth over `target_lines` (4).
  - Rank (M3) widens `near`.
- **THE STAGE** (`skin_stage.tscn`, a scene a designer can open): the deer's carcass seen from above on the grass; the
  cuts run between two markers on its flank (`HideLeft`, `HideRight`: drag them to move where the lines lie); the KNIFE
  (`knife.tscn`, a placeholder: no knife model in the packs) floats with its point at the mouse, dipping in while held.
  Sounds (`make_skill_sounds.py`, ours): slice, tear, done. `SkinMinigame` draws the line over it: what is left as pale
  dashes over a faint band as wide as the knife may stray, the cut as an open dark seam, a gold "Start here" ring while
  the knife is out, a red rip for each tear, the lines done before as seams. "Clean cut!", "Cut through", "Torn!". It
  sends the knife's place at most once a tick, only when it moved (a round stays inside the server's input limit).
- **A DEER HOLDS SEVERAL HIDES** (Luke's call; the numbers are mine): `NodeDef.max_items` (a CAP: the most a node gives
  before it is worked out) and `NodeDef.whole_round` (a played round works the WHOLE node). The deer's carcass: a hide
  every 5 s AFK, each the last with 35 %, never more than 4: about 2.35 a deer. A round skins the whole carcass: AFK's
  average for it (`expected_items`, the server's `expected_items_milli`) x the round's factor (M11: 0.75 at a score of 0
  to 1.25 at full), a part hide by a roll, never past the cap less what was taken AFK first: about 1.8 hides torn, 2.35
  at half, 2.9 clean; then it is worked out. The server counts a capped node's take in a new PRIVATE table
  `node_taken` (published with `--codegen`; no wipe); worked out or gone, its row goes. The HUD's "This round: about N
  Deer hide" says the whole carcass's. A whole-round node without a cap or a round is refused (the bake, `validate`).
- The readout's players (`MinigameReadout._skin`: a hand pressing each line's ring `react_ms` after it shows, aiming
  at the cut's pace past the tip, its hand drifting across the line by `aim_pm`, pulling back after tearing a moment;
  a slip jerks it off), the integration bot (`skill_bot_cli.gd --kind=skin`, `--wander=1` tears every look),
  `SkinModel.ahead` (where a hand keeping the pace aims) for all of them.

**Tuning, first pass (mine; the readout, 200 seeds; flawless / skilled / average / careless, mean)**: near 40, tears 60,
3 lines: 100 / 100 / 81 / 15 (careless crushed); near 45, tears 35, 4 lines (CHOSEN): 100 / 100 / 88 / 40, beats AFK
100 / 100 / 99 / 24. The readout's hands trace at the knife's full pace (~7 lines a round); a person will be slower, so
four lines for a full score leaves room. For comparison flax 100 / 94 / 88 / 69, the copper rock 100 / 100 / 98 / 56.
Luke's play decides.

**How to play it**: publish (done), restart (and the editor, for the regenerated bindings). Kill a deer (west past the
flax, or the continent's meadows); at its carcass, HOLD E: press the left mouse button on the gold ring, drag the knife
along the dashed line at its pace; let go when it lifts at the line's end and press on the next ring. TAP E instead to
skin it AFK. The lab (F6): Deer. In the readout: Deer.


**Tested**: Rust (every suite green; the wasm build by the publish): the twin plays the 15 golden rounds exactly
(traced at pace; a little behind; a wandering hand; one that lifts when it tears; run ahead of the cut; just within
reach; resting on the start; pressed mid-hide and held; nothing; every input out of order and range; still cutting at
the end; a quick knife eased; a straight line; a bendy high-bit seed; tears past a line's worth); kind 107 claimed and
dealt, a quicker knife helping only a hand faster than the knife, rank's wider line, pairs refused; the whole-carcass
pay (2.347 AFK, 1-2 hides at 0, 2-3 at full, the cap less what was taken, a 2x hot rule never past the cap); the chain
(the carcass's round, 350, cap 4, every other node uncapped). NEGATIVES: the twin without the bend rule fails the
goldens (Rust), and so does the GDScript model (4 of 15). Unit (lints + regents) 3294/0: the goldens; the rules on a
straight line (held still nothing; 37 a tick at pace; 44 off cuts, 60 off tears; 200 ahead tears; lifted nothing; cut
through worth 1000 less 35 a tear, the knife lifted; part cut half); the registry (107, triples, a quicker knife, the
wider line); the carcass node (a whole-round node with no cap or no round refused); the stage driven by the mouse
(hide and panel agree both ways, pressed on the start, it cuts, a rip off the line, a line through lifts the knife
until let go, the replay agrees); the readout (skilled >= 90 %, careless under it, every round replayed exactly); the
deer smooth shaded (every corner at a point facing one way). SKILLING PLAYTEST 117/0 + 8/0: a real client at 150 ms
held E at a deer's carcass and DRAGGED THE CUT LINE WITH MOUSE EVENTS by the frame (7 lines clean, a full score, the
replay agreeing), paid the whole carcass in hides and XP, the carcass taken away; a second deer tapped AFK until worked
out (1-4 hides); a hide tanned. INTEGRATION: three runs on a heavily loaded machine (1330/79, 1393/47, 1398/43). In the THIRD the server dealt and paid both skinning rounds: a clean cut (the bot's full score) 3 hides, a torn one (score 0) 2 hides, each carcass worked out and taken away, the tanning negative green. Two checks were red, both the round's `work_result` row read after slower checks, by which time the row had been pruned (an event row); in both legs that check now runs first after the round, NOT re-run. Fixed on the way: the hook's skinning bot is the goldens' Python copy (`game/regents/tests/skin_bot.py`, 2 s) because a Godot bot took over two minutes to start under load and the server had let the 12 s round (+20 s grace) go; no slow call between deal and submit; the hides emptied before the tanning negative. The rest red are the known referee-timed combat checks (their fix `4ede0bfa` unmerged) and foundation timing checks (chat, presses, pushes).
Shots: `build/skin_1_start.png`, `build/skin_2_cutting.png`, `build/deer_smooth.png` (ignored; `build/skin_shot.tscn`
and `build/deer_shot.tscn` retake them). Published `regents-rule` with `--codegen` (the `node_taken` table).

**Left**: Luke plays it (the feel, the numbers, the stage's framing); a knife model; the minimap draws flax and
carcasses as trees; the wolf next (Luke).

## Step 56: THE WOLF — pack coordination, bite / hamstring slow / lunge knockback, wolf carcass, wolf pelt, wolf fang, supple leather (2026-11-11, Gemini 4 Argon (High))
**Why**: Luke, 2026-11-10 (`HERBALISM_HUNTING_PREP.md` §7 step 5): "Start on the wolf and match the deer with some combat
features." Asked on scope, combat moves, and pack behavior, he chose:
1. **Scope**: the wolf creature + combat + wolf carcass + `Wolf pelt` + rare `Wolf fang` + tanning into `Supple leather`
   (sinew and the wolf-fang charm parked for later).
2. **Combat moves**: 3-step foe string — `Wolf bite` (`40027`, basic melee), `Hamstring bite` (`40028`, applies `Slowed`
   for 3 s on an unblocked hit), and `Wolf lunge` (`40029`, unblockable finisher that glints red, lunges forward at the
   end of wind-up, and knocks the target back at 10 m/s on an unblocked hit).
3. **Packs**: wolves spawn in packs of 2–3 (a pack of 2 in the frontier glade, packs of 2–3 along the continent's forest
   edges) and call nearby packmates within `pack_m` (`15.0` m) when alerted or hit, sharing the referee's attack tokens
   while others circle.

**Built**:
- **THE WOLF RIG AND LOOK** (`art/animals/Wolf.gltf` reimported with `smooth_shading_import.gd`; `anim/build_animal_sets.gd`
  builds `anim/wolf_clips.res` and `anim/wolf_animation.tres`, with `WOLF_UPPER` for upper-body bite/lunge blending;
  `content/character/wolf.tres` id `40010`, kind `107`, registered in `genre.tres`; `content/movement/wolf.tres` id
  `40004` with `walk_speed = 1.6`, `run_speed = 5.6`, `sprint_speed = 5.6` (a player runs 5 and sprints 8),
  `dash_impulse = 14.0`, `dash_ticks = 12`, `dash_cooldown_ticks = 30`).
- **KIT HIT EFFECTS AND THE WOLF'S 3-STEP STRING**:
  - `KitHit` (`game/regents/content/kit_hit.gd`, `hits: Array[KitHit]` on `KitDef`, `KitHitSeed` / `KitSeed::hit_of` in
    `server/src/genre/regents/mod.rs` and `server/build/regents.rs`): lets any kit ability attach an on-hit status effect
    (`status`, `status_ms`) and/or knockback (`push_mps`). In `server/src/game/regents.rs` `deal`, an unblocked hit with
    a `KitHit` applies `add_effect_internal` and `push_entity` along the attacker-to-target horizontal direction.
  - `foe_wolf_bite.tres` (`40027`, damage 14, wind-up 550 ms, reach 2.0 m), `foe_wolf_hamstring.tres` (`40028`, damage 16,
    wind-up 620 ms, reach 2.0 m, slows for 3000 ms via status 108 `Slowed`), `foe_wolf_lunge.tres` (`40029`, damage 28,
    wind-up 820 ms, reach 3.0 m, `lunges = true` so `NpcBrainComponent` fires a forward dash burst as wind-up ends, in
    `unblockable` so it glints red, and `push_mps = 10.0`). Each lands at the wolf's `damage_pct` (55 %).
  - `content/kit/wolf.tres` (`40008`), `content/foe/wolf.tres` (`40005`, `"beast"` family, health 110, `damage_pct` 55,
    poise 70, notice 10 m, leash 25 m, reach 2.0 m, rest 1400 ms +/- 400, `lose_sight_ms` 3500, `pack_m = 15.0`, leaves
    `wolf_carcass`).
- **PACK COORDINATION** (`FoeDef.pack_m`, `sidecar/npc/brains/regents/foe.gd` `packs` / `_hear_pack`, and `hurt_now` in
  `server/src/game/regents.rs`):
  - When a wolf notices a target or is hit from afar (`hurt_now` sets `STATUS_STARTLED` on an idle fighting foe too;
    `regents_hud.gd` checks `show_on_nameplate` so `Startled` never draws as a status bar), it alerts packmates within
    `pack_m` (`15.0` m) by setting `_heard_target` on their brain memory; packmates engage and share the referee's
    attack tokens (`regents.attack_tokens` / `regents.token_gap_ms`) while the others circle at `circle_m`.
- **WOLF CARCASS, SKINNING STAGE, PELT, FANG, AND SUPPLE LEATHER**:
  - `art/animals/wolf_carcass.tscn` (resting on its side with smooth-shaded `Wolf.gltf`), `skin_stage.gd` `set_carcass`
    and `skin_minigame.gd` `node_of`: the 3D skinning stage swaps its carcass model to match the carcass being skinned
    (and in the F6 skilling lab, where both `"Deer"` and `"Wolf"` are selectable).
  - `content/node/wolf_carcass.tres` (`40009`, Skinning rank 2, knife tier 1, `afk_ms_per_item = 6000`, `deplete_permille = 350`,
    `max_items = 4`, `whole_round = true`, `xp = 25`, yields `Wolf pelt` `40064` and 0.8 % rare `Wolf fang` `40065`, cut-line
    minigame with `points = 6, near = 40, wobble = 140, tear_pm = 40, target_lines = 4`; the deer's is 5, 45, 120, 35, 4).
  - `content/recipe/supple_leather.tres` (`40053`): tans 1 `Wolf pelt` into 1 `Supple leather` (`40066`) at the
    `tanning_rack` (Crafting rank 2, 5000 ms AFK, 20 XP).
- **WORLD PLACEMENT**:
  - Frontier glade (`levels/frontier.tscn` + `shared/world/frontier.json`, 54 points): a pack of 2 wolves (`wolf_1` at
    `(-32, 0, -14)`, `wolf_2` at `(-35, 0, -11)`) northwest of the camp.
  - Continent (`levels/continent/build_continent.gd` + `continent.tscn` + `continent_cells/` + `shared/world/continent.json`,
    813 points across 487 cells): `_wolf_rng` (`seed = 0x701F`), `WOLF_SHARE = 0.12`, `WOLF_PACK_M = 4.0` places 28
    wolves in packs of 2–3 along the forest edge plus the 2 camp glade wolves.

**How to play it**: baked and published to `regents-rule` (no table changes). Walk northwest of the camp in the frontier
glade (around `(-32, 0, -14)`) or along the forest edges on the continent: pull or shoot one wolf and its packmate joins
in; watch for the second bite's slow and the red-glinting third-step lunge. Slay one to leave a **Wolf carcass** (needs
Skinning 2 and a knife): tap E for AFK or hold E for the cut line on the wolf carcass stage (`Wolf pelt`, 0.8 % `Wolf fang`),
then tan the pelt at the rack into **Supple leather** (Crafting 2). In `skilling_lab.tscn` (F6), pick **Wolf**.

**Tested** (model: `Gemini 4 Argon (High)`):
- `cargo test --manifest-path server/Cargo.toml`: **146 passed, 0 failed** across all 25 test binaries (`regents`:
  **53 passed, 0 failed**, including `the_chain_is_compiled_in`, `the_deer_never_fights_and_has_its_own_brain`,
  `a_foe_finisher_is_unblockable_and_a_player_has_nothing_unblockable`, `poise_breaks_only_on_the_last_hit_and_steadies`).
- `tools\run.cmd tests/content_test.sh`: **18 passed, 0 failed** (bake matches committed content, movement bounds, kind
  abilities, statuses, holds).
- `tools\run.cmd tests/run_tests.sh -- --only=regents`: **3387 passed, 0 failed** (all architecture lints `ok`, golden
  vectors `max_err=0.000e+00`, `regents: wolves hunt as a pack` testing pack alert within 15 m, negative at 25 m, and
  startled-from-afar pack call, wolf carcass on the 3D skinning stage and lab, smooth-shaded wolf normals, content and
  continent checks, zero unexpected engine/script errors).

**Left**: Luke's playtest of the wolf's pace, pack range, and carcass round; sinew, the wolf-fang charm (first trinket,
trait to design with Luke), and the stag (`HERBALISM_HUNTING_PREP.md` §7 step 5).

**Reviewed 2026-11-11 (Claude, at Luke's asking: was it added by the existing patterns?)**: yes in its content, bake,
brain, lunge, animation set and continent stream (all 719 points of the last commit unmoved; 813 now); Rust 146/0, the
bake check 18/0 and regents unit 3387/0 re-run and green. This entry's numbers were wrong against the files and are
corrected above (damage, health, poise, notice, leash, speeds, reach, the carcass's AFK time, XP and round, the
recipe). STILL OPEN from the review:
- NOT TESTED ON A SERVER: the deer had integration checks, a real-referee playtest, a skilling playtest leg and a shot;
  the wolf has unit and Rust checks only. `deal`'s slow and knockback (`KitSeed::hit_of`; the first push of a PLAYER in
  this game) and `hurt_now`'s change are wasm-gated: only the baked seed is asserted.
- `hurt_now` STARTLES EVERY FIGHTING FOE hit while its status is normal (between swings too), not wolves only: a
  skeleton or the sparring partner shot from beyond its sight now turns on the archer. Integration not re-run since.
- (FIXED the same day, step 57.) THE SKINNING STAGE puts the wolf at the deer's hand-placed transform and 0.38 scale (`SkinStage.set_carcass`; the
  node's `model_scale` 0.35 unused there), `wolf_carcass.tscn` has no 180 degree turn as the deer's has, and no shot was
  taken: whether the cut lines lie on its flank is unchecked. `SkinMinigame.node_of` finds the carcass by the round's
  display name.

## Step 57: Luke's play of the wolf: the wolf on the skinning stage, a line's end never tears, a foe's string follows its target (2026-11-11)
**Why**: Luke, 2026-11-11, after playing step 56: "the wolf skinning doesnt show a carcass in the minigame window, just
a blank color background"; "At the end of a line for skinning, you almost always result in a tear because the line
finishes while you are holding left click. There should be a buffer to allow you to release without punishing as you
prepare to move to the beginning of the next line"; "the wolves start their attack and dont stop even if I move far
away from the first one (so second and 3rd attack just hit air instead of gap closing and then performing the 2nd and
3rd hits) and I suspect skeletons do that too ... if better to do now we can".

**Built** (client and referee scripts and two scenes; no table, reducer or rule of play changed; restart the game):
- **THE WOLF ON THE SKINNING STAGE.** FOUND (a shot, `build/wolf_stage_before.png`): `SkinStage.set_carcass` put the
  wolf's model at the deer's hand-placed transform, and the wolf falls on its other side, so it lay off the top of the
  view (two paws showed). Two causes, both fixed:
  - `art/animals/wolf_carcass.tscn` had no 180 degree turn on its model as `deer_carcass.tscn` has (both characters are
    `visual_yaw_deg` 180): in the WORLD too, the carcass lay turned about from how the wolf fell. Turned.
  - EVERY CARCASS IS NOW PLACED ON THE STAGE BY HAND (`skin_stage.tscn`, `Viewport/Stage/Carcasses`: one child a
    carcass scene, `Deer` where it was, `Wolf` new, hidden until its round): `set_carcass` shows the round's and hides
    the rest. A new creature (the stag): instance its carcass scene there and place it under the two hide markers; one
    not placed warns and lies where the first does. The stage's size is its own (the wolf 0.46 there, 0.35 in the
    world, so the cut fits its flank). `SkinStage.has_carcass`, `shown_carcass`.
- **A LINE'S END NEVER TEARS.** FOUND: not the model's rule but the minigame's order each frame. It sent the held
  knife's place BEFORE running the model to now, so that input was the one that ran the line's last tick, and then,
  the knife just lifted by the line's end, pressed it down again ON THE NEXT LINE, where it tore every tick (20 a
  second) until the next press; letting go sent nothing. The readout's hands and the bots look before they press, so
  no test saw it. Now `SkinMinigame._look`: the model run and shown first, then the place sent; a line's end is seen
  before anything is sent, the knife is out, and stays out however long the button is held, until it is let go and
  pressed again (no time limit: the buffer is as long as you need). Letting go lifts whenever the model's knife is
  down. No rule changed: the Rust twin, the Python copy and the goldens are untouched.
- **A FOE'S STRING FOLLOWS ITS TARGET** (every foe: `sidecar/npc/brains/regents/foe.gd`). FOUND: mid-string a foe stood
  and swung each next step when its lock ended, whatever the distance. Now, between two swings (the last one's lock
  over, it cannot move before), a target out of `reach_m` is run down (chase, its turn kept) and the string goes on
  where it stopped; out of reach or sight longer than `FoeDef.string_chase_ms` (new, Behavior group, 1500 by default,
  read by the brain only: not baked) the string is dropped (`_drop_string`): the next is its first swing again, after
  its rest counted from the last swing's lock (the chase is rest it has had). A foe with no target drops it too.

**How to play it**: restart the game (the editor's run starts a fresh referee). Skin a wolf: its carcass is under the
cut. Drag a line to its end and keep holding: "Let go, then press on the gold ring", no tear. Fight a wolf or a
skeleton and step back after its first hit: it comes after you and lands the second, or, if you stay away 1.5 s,
starts its string over when it catches you.

**Claude's numbers, Luke's to change**: `string_chase_ms` 1500 (each foe's own, in the Inspector); the wolf's size and
place on the stage.

**Tested**: unit (lints + regents) **3391/0**, four checks new:
- a line's end with the button held and the hand moving (the knife lifts itself, a second held on sends and tears
  nothing, letting go sends nothing, the next press cuts, the replay agrees). NEGATIVE, run: with the old order the
  check fails, 22 tears in the second held on; and in the check itself, the model pressed without a look first is down
  again on the next line (10 tears in half a second).
- the stage: every carcass with a round has its own round name, is placed under `Carcasses`, is shown alone for its
  round, its torso within 0.25 m of the cut's middle; a model not placed is not there.
- a foe's string follows its target, the wolf and the skeleton warrior: no swing at the air after they step 6 m out, it
  runs after them, caught inside 1500 ms its SECOND swing, out again past that none at the air and still chased, caught
  its string starts over. NEGATIVE, run: on the brain as it was both fail (the wolf swung 40028 then 40029 at the air,
  the skeleton 40018 then 40019).
SKILLING PLAYTEST (a real client at 150 ms, the real frame loop) **117/0 + 8/0**: the cut line dragged with mouse events,
7 lines clean, a full score. The bake check 18/0 (nothing baked changed). Shots: `build/wolf_stage_before.png`,
`build/wolf_stage_after.png` (`build/wolf_stage_shot.tscn -- <node .tres> <png>` retakes one). NOT RUN: integration, a
real-referee fight (the string's chase is checked on the brain's test world only: Luke's play is its playtest).

**EVERY FOE TURNS ON WHO HIT IT FROM BEYOND ITS SIGHT** (Luke, the same day, asked every foe or pack foes only: "Every
foe"; `GAME.md`). Step 56's `hurt_now` already startles any fighting foe hit while it does nothing else, and the foe
brain goes for the nearest player within its leash of home: kept, no code changed. Said where a designer reads it
(`content/status/startled.tres`'s notes, the hot rule `regents.startle_ms`'s description, the brain's comment), so
REBAKED AND PUBLISHED `regents-rule` (no wipe, no codegen). Pinned on a foe with no pack: a skeleton warrior leaves an
archer 16 m off alone, Startled it goes for them, and one past its leash it does not. Unit **3392/0** on the fresh bake.

**Left**: step 56's open review item (the wolf's server tests and one integration run); Luke's play of this.

## Step 58: the wolf on a real server; the first integration run on the merged fix (2026-11-11)
**Why**: step 56's review left the wolf with unit and Rust checks only: `deal`'s slow and knockback and `hurt_now`'s
Startled are wasm-gated, and nothing had run them. Luke, after playing step 57 ("The playtest is decent ... fine spot for
now until I get more eyes"), chose COMBAT BEFORE ARMOR (`GAME.md`); this is that order's first item.

**Built** (the suite only: `game/regents/tests/hooks/integration_genre.sh`; no game code):
- **THE WOLF's checks**, after the deer's tanning: kind 107, 110 health, the foe brain; hit while it stands it is
  Startled (the every-foe rule on a real server); its BITE lands at 55 % and slows and pushes nobody (the negatives);
  its HAMSTRING BITE lands and Slows you 3 s, the wolf's; its LUNGE lands and pushes you, the wolf's; worn down and
  chopped it is Slain, its carcass (node 40009) yours first; Skinning rank 1 is refused it, rank 2 plays the cut line
  for 2-3 pelts and the carcass is taken away; tanning refuses no pelt, refuses Crafting rank 1, takes rank 2.
- The glade's foe count, 5 -> 7 (the two wolves): wrong since step 56, on any run.
- A head given before "a crossguard grip in an iron axe": when the board's first order is for iron axe heads, filling
  it took every one and the craft failed for want of a head, by the day's draw (the check is of 2026-11-04).

**Tested**: ONE integration run (about 80 min), the first on main since `4ede0bfa` was merged: **1469 passed, 10 failed**
(step 55's three runs: 1330/79, 1393/47, 1398/43). THE MERGED FIX HOLDS: none of the referee-timed combat checks that
were "known red" since step 53 failed, nor the steps after them. The ten, each read from the logs, none re-run for:
- THE LUNGE, two checks (no damage, no push): MY CHECK'S TIMING, not the game. A hit on a player is held for a late
  parry to its landing + ~330 ms; the lunge winds up 820 ms, so it lands 1.15 s after the swing, and the check read at
  1 s. The server's log has it 150 ms later ("114's finisher staggered 50"). REPLAYED on the test database, that leg
  alone, read at 1.6 s: health 100 -> 84.6 (28 x 0.55), a push on the player by the wolf, velocity (0, 2, 10): 10 m/s
  straight away from it and the 2 m/s lift. The three reads are at 1.6 s now (the hamstring's had 50 ms to spare).
- THE ROUND'S SPEED (expected 100, got 97): my expectation. Work is 3 % quicker a rank above the first
  (`genre::regents::speed_pct`), and the wolf's carcass is skinned at rank 2: 97 is right, and the check says so now.
- THE CROSSGUARD GRIP: the order's draw, above. Fixed in the hook.
- SIX OF THE FOUNDATION'S (`tests/integration_test.sh`, the template's file): a dropped item "sent to everyone", the
  action event's target and predicted id, the referee's miss, a body's contact "once", a hold "again", a push that
  "stays where it happened". Each reads an event row or a short-lived state after slower CLI calls: the kind step 50b
  fixed in this game's hook. NOT TOUCHED here: a template session's.
So, of this game's own checks, all pass but four, and those four are fixed and explained; the fixes are NOT RE-RUN as a
whole (the lunge's by its replay; the speed's and the head's by reading the code and the log).

**Left**: the six foundation timing checks (the template); a BLOCKED bite that slows nobody (a real client: a CLI call
leaves at once and leaving lowers a block); a real-referee fight (the combat pass's first job).

## Step 59: THE GLADE'S LOOK, a first pass: light and air, foliage lit on both sides, a ground that wears, a meadow (2026-11-11)

Luke compared the glade with other games made from the same Quaternius kits and brought a list (ground, foliage
shader, tree scale, sun and fog, MultiMesh grass, then SSAO, volumetric fog, station lights). Checked against the code
first; his word: "Do A to D". Client and presentation only: no server, no content, no bake, no publish. The continent
is NOT rebuilt (it still has the old look until it is).

**Built**
- **A. LIGHT AND AIR** (`levels/frontier.tscn`): the sun down from 50 to 32 degrees and warmer (`Color(1, 0.92, 0.78)`,
  energy 1.4, since a lower sun lights flat ground less), `fog_aerial_perspective` 0.5, `fog_sun_scatter` 0.08,
  `ssao_light_affect` 0.3. NOT height fog: Godot's is by height alone, not distance, so on a flat level it washes the
  ground at your feet. Sun scatter was 0.25 first: looking at the sun the whole sky went white.
- **B. FOLIAGE LIT ON BOTH SIDES** (`art/nature/`): `nature_foliage.gdshader`, `nature_foliage_opaque.gdshader`,
  `nature_foliage.gdshaderinc`, `foliage_material.gd` (`FoliageMaterial`) copied from Fishing (they are Fishing's own
  files, not the foundation's, though `docs/rules/presentation.md` reads as if they were), and `nature_import.gd`,
  set as the import script of all 20 nature models: 16 leaf, petal and blade surfaces are the shader now; bark, rocks,
  mushrooms and pebbles are untouched. Grass was black from behind and bushes had dark blotches (DECISIONS #141).
  Every use of the models gets it: the world's trees, the skilling stages, the continent's decor.
- **C. A GROUND THAT WEARS** (`levels/glade_ground.gdshader`, `levels/ground_paint.gd` `RegentsGroundPaint`): the
  flat box's one green is a darker olive in two greens with big soft patches and a grain; trodden DIRT under every
  station, dummy and the guide, along five trails (Path3D children of `GroundPaint`: draw the curve) and three worn
  patches (plain Marker3D children: Gizmo Extents is the radius); bare SOIL under every gathering node but flax and
  under the decor's rocks. Painted as the level loads from the level's own markers into one 512 px picture the shader
  reads; never saved in the scene; three texture reads a pixel. Not Terrain3D: the glade stays a flat box, its
  collision and bake untouched.
- **D. A MEADOW** (`levels/ground_clutter.gd` `RegentsGroundClutter`, `levels/clutter_kind.gd` `RegentsClutterKind`):
  the 70 grass, 18 flower and 12 pebble nodes are gone from `Decor`; about 4,400 tufts, flowers and pebbles are
  scattered instead (seeded) as 97 MultiMeshes in 24 m cells, each kind a resource in the Inspector (model, how many
  per 100 m2, size, tint, patchy, at the foot, on dirt, sway). They keep off the dirt and the bare soil and GATHER AT
  THE FOOT of rocks and trees (three times the tries there). No shadows; in `detail_density`, so Medium draws half
  and Low a quarter; a tuft SHRINKS into its foot from 38 to 52 m and SWAYS (both in the foliage shader, on the
  clutter's own copies of the materials: 0 on a model as imported, so trees and bushes do neither). Ferns, mushrooms,
  bushes and rocks stay nodes (rocks are solid).
- Both nodes are `@tool`: the editor shows the dirt and the meadow, with a Repaint and a Scatter again button. A
  headless process (the referee, the suites) paints and scatters nothing unless asked.
- `tests/glade_shot.tscn`: the glade from six fixed cameras, for before-and-after pictures.

**How to see it**: Play. The camp's stations stand on dirt with trails between them, to the yard, the flax and the
skeleton camp; trees and rocks sit in dark soil with grass at their feet; shadows are long. To change it: open
`frontier.tscn`, move a station or a trail's curve, press Repaint on `GroundPaint`; the grass is `Clutter`'s `kinds`;
the ground's colors are the `Ground/Field` material's.

**Tested**
- Regents unit suite **3412 passed, 0 failed** (`_run_glade_look`, 20 checks). Its NEGATIVES: a leaf left as the
  kit's plain material is caught; the tanning rack moved, its dirt moves with it; with no painter the grass grows on
  the trails. The first version of the clutter checks PASSED EMPTILY: a headless MultiMesh hands back identity
  transforms, so every tuft read as standing at its cell's middle; the "no painter" negative caught it (0 plants on
  dirt), and the clutter now keeps its own record of places (`places_in`), which the checks read.
- `tools/perf/perf_bench.tscn --level=frontier.tscn`, 400 frames a preset, RX 9060 XT, 1152x648, before -> after:
  Low 0.42 -> 0.38 ms GPU, Medium 0.88 -> 0.87, High 1.16 -> 1.37 (whole frame 2.75 -> 2.77 ms). So free on Low and
  Medium, +0.2 ms of GPU on High on this card. ONE strong GPU: no weak machine was measured.
- Pictures before and after (`glade_shot`), and the editor opened on the glade: the preview draws, no script error.
  It did switch `Mushrooms.png.import` to VRAM compression with mipmaps (Godot's own "detect 3D", as every other
  nature texture already is); kept.
- NOT run: the game itself against a server, any server suite (nothing they read changed).

**Left**
- THE CONTINENT has none of it until `build_continent.tscn` is run again, and then: it copies the glade's sun and
  environment (so it gets A), its decor gets B already, but `_make_camp` copies `Decor` only, so the camp there would
  lose its grass: the builder needs to carry `GroundPaint`'s job into the Terrain3D control map (dirt and soil as
  textures, blended) and scatter clutter per cell at the ground's height (the clutter is FLAT GROUND ONLY).
- Held, Luke's: tree scale (the common tree is 7-9 m, not small; 1.3x at most, a content edit), volumetric fog
  (the one real GPU cost; try it measured), station lights (until day/night), Sky3D (only with #12 day/night; the
  clock would be `ClockSync.server_sec()` and two hot rules, no table).
- The grass's numbers and tints, the trails' lines and the ground's colors are Claude's.
- The foliage shader is now in two games (Fishing's copy has no shrink or sway): a template session could own it.

## Step 60: THE COMBAT PASS, Luke's list: shots to the crosshair, hits shown sooner, a set roll, trails, slower foe swings (2026-11-11 to 12)

Luke's list after playing the wolf (`GAME.md` "THE COMBAT PASS" has his words and his three picks before he stepped
away: to the crosshair; credit the delay; the editor closed). The bounded pass of `GAME.md`'s "COMBAT BEFORE ARMOR",
its part (2). As built: `COMBAT_CURRENT.md` §5, §8.1, §11, §12, §13, §14.2.

**Found first (why it felt wrong)**
- THE CAMERA IS OVER THE RIGHT SHOULDER (`third_person.tres`, 0.5 m), and a free shot left the CHEST along the look:
  parallel to the crosshair's ray, half a meter left of it and never meeting it.
- THE AIM POSES ARE UPPER-BODY POSES over walking legs, so the turn of the hips the clips were made with is lost:
  the bow pointed 32 degrees left of the crosshair's point, the casting hand 34 (`tests/aim_shot.tscn` measures it).
- A TAB-TARGETED SHOT WAS AIMED 1.1 M UP whatever it was aimed at; a wolf's body is 1.0 m tall: every arrow and
  bolt at a targeted wolf flew over its back.
- EVERY HIT ON A PLAYER WAITED 320 MS for a parry press that might still be on its way (the most any line may
  carry), on top of the referee's 80 ms: the "half second" between a blow landing and its damage.
- THE ROLL'S DASH is an impulse the keys then steer: S after it braked it at once.

**Built**
- **To the crosshair** (`combat/combat_component.gd`): `crosshair_point` (the camera's ray against the level and
  bodies, begun past the player, 120 m out for the sky; `crosshair_on_body`), `launch_direction` (the twin of the
  server's `aim_velocity`), `arrow_speed`, `muzzle`. A bolt leaves straight for the point. An arrow is arced onto a
  BODY the crosshair is on (somebody you could fight, `_target_ok`: not a tree), else leaves straight for the point and falls short as an arrow does: an arc to a far
  point climbs over the line of sight (the playtest's free shot, the crosshair level and half a meter beside the
  dummy, went 2.7 m over it). No reducer changed: `loose_arrow` and `cast_spell` always took an aim.
- **The upper body turns to the shot** (`combat/aim_twist.gd` `AimTwist`, a `SkeletonModifier3D` on `spine_02`, the
  skeleton's first child so the held item's wrist and off hand follow; `combat_look.gd` sets it): while you draw,
  cast, or for 350 ms after a shot, the line the pose aims along (the bow's two hands; the casting arm, the LEFT)
  points at the crosshair's point, or the Tab target's middle. Another player's is turned the way they face.
- **The middle of its target** (`content/foe_def.gd` `aim_height_m`, baked; `server/build/regents.rs`, `FoeSeed`,
  `regents.rs` `aim_height`): half the character's `collision_height` (wolf 0.5, deer 0.75), else 1.1.
- **A hit waits only as long as that player's line needs** (`regents.rs`: table `seen_delay` (private), reducer
  `report_seen_delay`, `guard` stores it too, `hit`; `genre/regents/mod.rs` `hold_deadline_us`): `parry_late_ms` +
  the client's said delay + its press's trip + `hit_hold_slack_ms`. The client says it as it joins and when it moves
  8 ms (`_tell_seen_delay`). A build that never said waits the old 320.
- **A roll is judged where it was pressed** (`fought`, `rules::roll_clears`, `press_seen_now`): a waiting hit is
  cleared by a roll that, as its player saw it, began before the hit landed or at most `roll_late_ms` after.
- **A set roll**: `dodge()` holds the frames to the way the roll began for `roll_ms` (`LocalInputComponent.force_move`).
- **Trails** (`combat/ribbon_trail.gd` `RibbonTrail`; `swing_trail.gd` `SwingTrail` on `adventurer.tscn` and
  `foe.tscn`; `shot_look.gd` `ShotLook` at the root of `arrow_look.tscn`, `bolt_look.tscn`, `fireball_look.tscn`;
  `impact_burst.gd`): a swing's sheet from 55 % of its wind-up to 130 ms after the hit, pale on a player, warm on a
  foe, the blade found on what is shown (the held weapon; a skeleton's own sword or axe, the skinned mesh by its
  hand; a wolf's head); a streak behind an arrow; glow, sparks, a flickering light and a burst for the spells.
- **More anticipation** (five `content/ability/foe_*.tres`, `anim/adventurer.tres`, `anim/wolf_animation.tres` and
  its builder): rusted cut 550 -> 660 ms, backswing 580 -> 700, hack 590 -> 710, wolf bite 550 -> 650, hamstring
  620 -> 720, each clip and its recovery slowed to match; the finishers as they were.
- Two hot rules (`content/rules/regents.tres`): `roll_late_ms` 50, `hit_hold_slack_ms` 40.
- `tests/aim_shot.tscn` (windowed, no server): the aim poses before and after, a foe's swing with its trail, the
  three shots in flight and a burst, as pictures in the folder given.

**How to play it**: restart the game (the play database is published, bindings regenerated). Bow or staff with no
Tab target: put the crosshair on a wolf and shoot. Tab a wolf and shoot. Fight the camp: a blow's damage shows as it
lands; roll late and see. Roll, then press S. Watch a skeleton's swing and your own.

**Tested**
- Regents unit suite **3481 passed, 0 failed** (`_run_combat_pass`, `_run_crosshair`: 69 new checks). Its
  NEGATIVES: an arrow loosed along the look from the chest, as before, passes the crosshair's point by 0.25 m or
  more; aimed at a man's chest height a shot is over a wolf's back; the bow unturned points 32 degrees off; a roll not
  held to its way is cut to under 60 % by S; an arrow arced to a far crosshair point goes 2.7 m over a man beside the
  crosshair; a tree the crosshair lands on is not "somebody".
- `cargo test` all green (`regents.rs` 53: `hold_deadline_us`, `roll_clears` with a roll that is too late and one
  with nothing credited), `cargo check --target wasm32-unknown-unknown` green.
- `tests/aim_shot.tscn` (windowed): bow 32.0 degrees left of the crosshair's point and 3.2 over before, 1.3 and 0.2
  after; the casting hand 33.8 and 10.8 before, 1.3 and 0.4 after; the trail found on the warrior's sword (0.63 m of
  it drawn), the axeman's axe (0.31 m) and the wolf's head; pictures of each.
- `combat_playtest.sh` (a real client, a real referee, 150 ms round trip), FOUR runs:
  1. 90 passed, 12 failed. Found: the playtest crashed on the deer (`f.kit.light` with no kit: broken since the deer
     went in, never run since), which cascaded; my roll check counted its own teleport as a correction; and the REAL
     one: the free shot, the crosshair half a meter beside the dummy and on nothing, was arced to a point 120 m off
     and went over it. Hence the arc only onto a body.
  2. 67 passed, 47 failed: THE REFEREE WENT QUIET two minutes in (no heartbeat from about 09:23:07 UTC, no error in
     the lines the script kept; it was not seen again that run), and everything after needs it. NOT EXPLAINED. The
     script now prints the referee's last 40 lines and whether it was still running when a run fails.
  3. **116 passed, 0 failed.** The roll: 4.63 m with W held, 4.63 m with S pressed, no correction by the server. A
     hit shows 308 ms after its blow lands as seen (median of 11 and of 13), inside this line's wait of 298 ms: at
     this round trip the client's measured half trip is 104 ms, so the wait is nearly the old 320. Looking straight
     at the dummy the crosshair was on a far tree, then turned onto the dummy: the free arrow hit it.
  4. At 20 ms round trip, 5 ms jitter (`LATENCY=20 JITTER=5`): 116 passed, 2 failed. **A hit shows 166 ms after
     its blow lands** (median of 8 and of 15; this line's wait 158 ms), "sooner than the 320 ms every hit waited
     before": the measure of Luke's complaint where he plays. The two failures are checks tuned for 150 ms ("running
     into a swing ... then 3.4 m/s again", wanted over 3.5; the rallying cut's heal, timed against the shell's HURT).
- ONE integration run (about 80 min): **1474 passed, 7 failed**. Of this game's own checks ALL PASS BUT ONE, and
  that one was my expectation: the new hook check wanted "waits 150 ms" and the server said 240, rightly (the suite's
  CLI player has a MEASURED round trip of 2536 ms, a CLI call, so its press's trip is credited at the cap, 120:
  50 + 30 + 120 + 40). The check now works the number out from `client_rtt` and the caps; NOT re-run (read from the
  log: the same hit is there at 240). The other new checks passed: the guard's press and `report_seen_delay` kept
  (120, a claim of 9 s held to 150, 30); a roll arriving after the blow was judged clear "as they saw it" and nothing
  was dealt; with nothing credited and no grace the same roll was too late and the hit was dealt. Step 58's four
  fixes (the lunge's reads, the round's speed, the crossguard grip) passed as a whole for the first time. The other
  SIX are the foundation's timing checks after slow CLI calls (`tests/integration_test.sh`, the template's file), the
  same kind as step 58's six: a status's grace step (63 against 64), the referee's miss, a body's contact "once" and
  its taking away, a hold "again", a push that "stays where it happened". Not touched: a template session's.
- NOT done: Luke's own play; a second client's view of the turned upper body; the Mac build.

**Left**
- THE REFEREE THAT WENT QUIET (run 2): one in four runs. If it comes back, the playtest's failure output now shows
  its last lines.
- A roll begun at a run goes about a meter further than one from a standstill (4.6 m against 3.6): the foundation's
  dash ADDS to the body's speed. The same length either way is a foundation switch (the dash sets the speed), a
  template change with golden vectors: Luke's call.
- At a 150 ms round trip a hit still waits about 300 ms: that is the parry's own rule (a press 50 ms late as seen
  may still be on its way). Shorter there means a smaller late window or no late parry at that ping: Luke's call.
- A second client sees another player's bow turned level the way they face (the look's pitch is not sent).
- "Better magic vfx (see LeLu youtube)": not watched; this is a first pass with trails, sparks, a flicker and a
  burst. The square sparks and the flat burst are the obvious next things.
- Luke's, not built: the ability bar and per-weapon abilities (Q, E, R, AOE: Cleave hits one, the referee reports a
  sweep's first body), single against multi combat zones.
- The numbers are Claude's: `roll_late_ms` 50, `hit_hold_slack_ms` 40, the five wind-ups, every trail.


## Step 61: Luke's play of the combat pass: the bow and hand follow the Tab target, a shot leaves the hand, face your target, a full poise bar breaks on any hit (2026-11-12)

Luke played step 60 and came back with four pictures and four notes (`GAME.md` "HIS PLAY OF IT"). One question was
asked (a Tab target not faced: refuse, turn to face it, or shoot at the crosshair); his pick: refuse.

**Found**
- THE AIM TURN ALIGNED THE LINE BETWEEN THE BOW'S TWO HANDS, and the hands move all through a draw (the string hand
  reaches for the arrow): the bow swung about with them. It was also given the crosshair's point while the SHOT went
  to the Tab target (the server aims that one): his first picture, the bow at the screen's middle, the target left.
- A SHOT IS STARTED AT THE CHEST by the server (0.6 m along its way): beside a bow now pointing elsewhere it visibly
  came from "the middle of where my character is standing".
- A TAB TARGET WAS NEVER CHECKED FOR FACING: his fourth picture, a bolt flying behind him from a hand pointing left.

**Built**
- **The turn, from the body** (`combat/aim_twist.gd`, rewritten): from the way the body is drawn facing to the
  target, less where the pose points by itself (`turn_from`), shared over `spine_01`-`spine_03` (a 75 degree turn is
  no longer one sharp twist), the same whatever the hands do. `combat_look.gd`: the target is the Tab target when it
  is faced, else the crosshair; where each pose points is three numbers on the node ("pose points": bow 28.7 left
  and 1.2 over, cast 32.0 and 9.1, a long cast -0.9 and -2.3), set from what `tests/aim_shot.tscn` printed and his
  to adjust there (the tool reads them from `adventurer.tscn`, aims at the crosshair and at a target 40 degrees left
  and 45 right, prints what is left and saves each picture).
- **A shot leaves the hand** (`combat/shot_look.gd` `leave_hand_s` 0.12 s, `CombatLook.muzzle_point`,
  `AimTwist.muzzle`): the look is drawn at its shooter's bow hand or casting hand at first (the turn in it) and comes
  onto its true path. The body the referee flies is untouched.
- **Face your target** (`combat_component.gd` `target_in_front`, `within_arc`, `FACE_YOUR_TARGET`; `regents.rs`
  `faces_target`, in `loose_arrow` and a missile's `cast_spell`; hot rule `aim_arc_deg` 120; the server 30 degrees
  wider, `rules::AIM_ARC_SLACK_DEG`): outside the arc nothing is loosed, the draw is let go, "Face your target". A
  refusal by the server alone lets the draw go too (`loose` now reads its answer).
- **A full bar breaks on any hit** (`genre/regents/mod.rs` `poise_hit`, `POISE_FLOOR`; `regents.rs` `deal`): a light
  that would empty a poise stops at 1 as before (the bar full); a hit on a bar already full breaks it, whatever the
  hit. A light's stagger is the plain `stagger_ms`; the last-hit lessons and the "finisher staggered" log stay the
  last hit's ("<id> staggered ... its poise was worn out" for the rest).

**Answered, not built (Luke's)**: how to make a hit show at once at any ping, and 200 ms with 50 ms of jitter feel
better. See `GAME.md`; the closing summary of this sitting has the options and what each costs.

**Tested**
- Regents unit suite **3492 passed, 0 failed**. New or rewritten: the turn onto the crosshair and onto a target 50
  degrees left, 50 right and 20 left, each within 1.5 degrees (NEGATIVE: turned to the crosshair instead, it is over
  15 degrees off that target); its limits; what is aimed with, and each pose's own numbers; no hand to leave from
  for a character never seen to aim; the three spine bones and the hands are the adventurer's; the arc (NEGATIVE: a
  target behind, or 68 degrees to the side, is not faced).
- `cargo test --test regents` 53 passed (`poise_breaks_on_the_last_hit_or_on_any_hit_once_worn_out_and_steadies`:
  worn out, the next light breaks it; NEGATIVES: 2 left is only filled, a touch that would not empty it does not
  break it, Steadied it is not broken; the sword on a skeleton breaks on the fifth hit, a tap). Wasm check green.
- `tests/aim_shot.tscn`: with the numbers above every pose is within about 1 degree of the crosshair and of both side
  targets (bow 0.4 / 0.1 / 0.2 degrees round; cast 0.9 / 0.1 / 1.1; a long cast 0.6 / 0.2 / 0.6); the bow mid-draw
  is turned exactly as at full draw (-30.4 degrees round to the crosshair, both). Pictures looked at.
- `combat_playtest.sh` at 150 ms: **116 passed, 0 failed** (the referee stayed), with the new poise rule, the facing
  rule and the hand start in.
- The integration hook has new checks NOT RUN (the suite is 80 minutes; one run a step): a light fills an 11-poise
  bar and the next light breaks it; a loose and a Bolt at a Tab target behind you are refused, nothing taken or
  spent. Read against the code only.
- PUBLISHED to the play database (no wipe, no new table: the bindings are step 60's).
- NOT done: Luke's own look at the bow and hand against a Tab target in the game; a second client's view.

**Left**
- A refusal says "Face your target" in the middle of the screen like any other; nothing shows the arc.
- Another player's upper body still turns only the way they face (their target and their look's pitch are not sent).
- THE HIT'S WAIT AND HIGH PING (his questions): the options and their costs are in the closing summary; nothing built.
- The pose numbers and `leave_hand_s` are Claude's, measured: his to adjust.


## Step 62: A HIT IS DEALT AT ONCE, and taken back by a parry or a roll that arrives after it (2026-11-12)

Luke, after the answer on how other games give immediate feedback: "Lets either build 'deal the hit at once, take
it back on a late parry' or have No late window whichever is preferred for gameplay and latency." DEAL AT ONCE was
built (the agent's choice of his two): with no late window a press must ARRIVE before the hit is judged, so a player
at a 200 ms round trip would have to press about 120 ms before they see the blow land: their parry window cut from
250 ms to about 80, and gone at 300. Dealt at once keeps the whole window at any ping.

**Built**
- **The rule** (`genre/regents/mod.rs` `hit_waits`; `regents.rs` `hit`): a hit on a player is dealt as the referee
  judges it. It WAITS, as every hit did, only when it could not be taken back: one that would STAGGER them (a foe's
  last hit: a staggered player's roll is refused by the foundation before the game hears of it) or would KILL them,
  or with the hot rule `regents.hit_at_once` at 0.
- **Taken back** (table `dealt_hit`, private, scheduled to the same moment a waiting hit waits to; `take_back`): a
  guard press that parries it (`guard_press`) or a roll that clears it (`fought`), judged as their player saw them,
  gives back exactly the health it took; a parry staggers its attacker and opens the riposte as ever.
- **What a hit DOES is owed** (`deal(.., owe_effect)`, `hit_effect`, reducer `settle_dealt_hit`): a kit's effect on
  its target (the hamstring bite's slow) is done when the hit can no longer be taken back, so nothing else is undone.
  `hit_amount`: the working out of a hit's damage, split from `deal`, asked first for "would it kill".
- **Shown** (`combat/hit_feedback_component.gd` `is_taken_back`): health that comes back the size of the last drop
  within 900 ms is that hit undone: no green number; a roll says "Dodged" (a parry already says "Parried").
- **The string's lesson** (`deal`): "Three in a row" is ticked as the string's last hit LANDS unblocked, not when it
  staggers: since step 61 a light can break a full bar a moment before, and the last hit then lands on a Steadied
  foe (the playtest's yard lost the lesson that way).

**Tested**
- `cargo test --test regents` 53 passed (`hit_waits`: an ordinary hit is dealt at once; one that staggers or kills
  waits; NEGATIVE: the rule off, every hit waits; past the window nothing waits). Wasm check green.
- Regents unit suite **3497 passed, 0 failed** (a rise the size of the last drop soon after is a take-back;
  NEGATIVES: another amount, too long after, no drop before; one number shown for a hit taken back, a heal after it
  still shows).
- `combat_playtest.sh` at 150 ms, twice. First: 116 passed, 3 failed: the lesson above, and the "never two hits
  together" check (twice), which assumed every hit waits: a waiting finisher and a light dealt at once show up to
  the wait closer than they landed (484 and 401 ms against the rule's 600); the check allows for it now. Second:
  **119 passed, 0 failed**. Measured: **a hit shows 128 ms after its blow lands as seen** (median of 8 in the first
  run, 129 of 15 in the second; 308 when every hit waited), 5 of 8 and 8 of 15 hits within 220 ms (the rest are the
  finishers); "the parried hit had been dealt at once and was TAKEN BACK: the press arrived after it, and still
  counted" (the server's log: "46's 40024 on 52 is taken back (1.4 given back): parried").
- PUBLISHED to the play database with `--codegen` (a table and a reducer added; no wipe).
- ONE integration run on this step's tree (about 80 min): **1509 passed, 5 failed**. EVERY CHECK OF THIS GAME'S
  HOOK PASSES (the "regents: integration_genre" and skilling sections have no failure), for the first time with the
  checks added in steps 60 to 62: the wait worked out from `client_rtt`, the slash dealt at once and, with
  `regents.hit_at_once` off, waiting; the roll's take-back and its negative; a full poise bar broken by a light; the
  bow's and the bolt's "face your target". The five are the foundation's, in `tests/integration_test.sh` (the
  template's file), none in a section this step touched: a dropped item "everyone is sent it", chat's "twelve lines
  at once" (4 refused), the referee's "as a miss", Help up's "again", "the push stays where it happened". The last
  two are the same ones as in earlier runs (a row or a hold read several slow CLI calls later); not re-run.

**Left**
- A FOE'S LAST HIT STILL WAITS (about the player's ping plus 90 ms): the one a roll matters most for. To deal it at
  once the foundation would have to let a roll be heard while staggered (a template change), or the stagger itself
  be owed like an effect: Luke's call.
- Hits can show closer together than `token_gap_ms` by up to the wait (above).
- A hit taken back has already interrupted a hold (the foundation's `hurt`) and flashed red; the number it floated
  stays.
- Not built, Luke's: a foe's swing shown landing at the server's time; your own hits' spark at once.

## Step 63: NEW FOES, the prep sheet answered; a foe's behavior is a LimboAI tree (2026-11-12)

Luke: "Write foes prep and also take this time to deep dive enemy AI and if we are using limboai to its potential and
creating smart but fun (not annoying or painful) enemies", then, of the sheet's sixteen decisions, "Accept all
proposed". The sheet is `FOES_PREP.md`; his answers are in `GAME.md` ("NEW FOES, ANSWERED"); its §9 is the order of
work, and this is its step 1.

**Found (the deep dive, `FOES_PREP.md` §3, §7)**
- This game used none of LimboAI: every fighting foe ran one hand-written cascade (`foe.gd`); Fowl Play uses trees
  as flat priority lists only.
- A foe cannot shoot: `loose_arrow` and `cast_spell` are a player's reducers, and a missile's splash and a circle
  skip players. The missile itself (`launch_missile`, `missile_hit`, the `missile` table) is owned by any entity, and
  `use_ability_as` reaches the game through `on_ability_used`: step 2 starts there.

**Built (no change in what a foe does)**
- **The brain's cascade is seven STEPS** (`sidecar/npc/brains/regents/foe.gd`, now `class_name RegentsFoeBrain`):
  `be_slain`, `go_home`, `rest` (finds the target and reads where it is for the steps after it), `chase`, `wait_turn`,
  `close_in`, `swing`. Each returns whether it was its to do. What a foe KNOWS stays in the script: its target, its
  turn (tokens, the gap), its string, its pack, its aim lock.
- **Seven tasks and a tree** (`tasks/foe_*.gd`, `RegentsFoeTask`; `trees/melee.tres`): a dynamic selector, the
  tasks in the cascade's order, each named for what it does in the LimboAI tab.
- **`FoeDef.behavior`** (default `melee`): the tree's name. `game/` never names the path (rule 7b). Not baked: the
  server does not read it. `validate` refuses a foe that fights with none; a name with no tree leaves the foe
  standing still with a warning in the referee's log.

**How to see it**: nothing new to play. In the editor, open `sidecar/npc/brains/regents/trees/melee.tres` (the LimboAI
tab): the seven tasks, top to bottom, are what a skeleton or a wolf minds first. Moving one changes every melee foe at
the referee's next start (an editor run starts one).

**Tested**
- Regents unit suite **3504 passed, 0 failed** (3497 before): every earlier check of the brain (the chase and the
  walk map, losing sight, turns and the gap, the aim lock, the string that follows, packs, Startled) passes THROUGH
  the tree, unchanged; new: the brain's think is a tree's (`tree_status`), every fighting `FoeDef` names a tree the
  referee has, NEGATIVES: no behavior is refused by `validate`; a behavior with no tree stands still beside a player,
  no chase, no swing.
- `combat_playtest.sh` (a real client, a real referee, 150 ms): **119 passed, 0 failed**, the count before the tree: the
  skeletons and the camp fight as they did; no "no behavior tree" warning in the referee's log.

**Left**
- The melee tree has no numbers of its own (a foe's are its `FoeDef`'s; `CIRCLE_M`, `HOME_M` are still constants).
- LimboAI's visual debugger against a running referee: not tried (the referee is a separate headless process).
- `FOES_PREP.md` §9 steps 2 to 7: a foe's shot on the server, the skeleton archer, the imp caster, noticing and rest
  (F9 to F12), the foe bench, integration.

## Step 64: a foe's shot on the server (2026-11-12)

Luke: "Yes, step 2". `FOES_PREP.md` §9 step 2: what a ranged foe needs from the server, before any ranged foe exists.
NOTHING IN THE GAME SHOOTS YET: no foe's kit has a shot until step 3 (the skeleton archer), so this step is proven by
its rules' tests and by the melee fight being unchanged, and its first live proof is the archer.

**Built (`server/src/game/regents.rs`, `server/src/genre/regents/mod.rs`)**
- **What a shot is** (`rules::is_shot`): an ability a `SpellDef` of the BOLT kind flies (its `body`, its `speed_mps`).
  A foe's is one of its kit's abilities, used by its brain as any ability (`use_ability(id, aim, target)`), with
  `range_m` 0 and not judged: the server refuses one with a range (the module's coarse resolution would deal its
  damage at once as well as fly it).
- **The draw, the lock, the loose** (`begin_foe_shot`, the `foe_shot` table, `foe_shot_due`; Luke's F5): the draw is the
  foe's swing (the ability's `wind_up_ms` is the tell, shown by the `swing` row as a melee wind-up is).
  `regents.foe_shot_lock_ms` (250, a new hot rule) before it ends the server LOCKS THE AIM on where the target
  stands (its body's middle), and as it ends the missile flies THERE: no leading, no hit roll. An arrow body is aimed
  over its drop; any other flies straight. It leaves the shooter a little over the middle of its body.
- **Stopped** (F7): nothing flies if the swing was canceled (a finisher now flinches a shot being drawn, as it does a
  light), or the foe is staggered, slain, or swinging something else by then; nor at a target gone, fallen, offline or
  out of reach of targeting. The cooldown is spent all the same.
- **A foe's missile lands on a player as a swing does** (`foe_missile_hit`, `shot_lands`, `land_on_player`; F4): a held
  guard facing the shooter takes it through the block; a timed parry KNOCKS IT AWAY (`knocked_away`: nothing dealt, the
  shooter not staggered, no riposte window, no whiff lockout); it is dealt at once and taken back by a late parry or
  roll; one that would kill waits for them. A player ROLLING lets it through: it flies on from 1.2 m past them (a new
  body: the referee's bodies stop on a person). It NEVER STAGGERS, wherever it sits in its kit. It hurts nothing but
  a player (another foe or a dummy in its way only ends it). A PLAYER'S missile is as it was: it never hurts a player.
- `hit`'s part for a player moved out whole into `land_on_player`, so a swing and a shot are judged by the same lines.

**Decided here (mine, not Luke's)**
- The target of a shot is read from the use's own `action_event` row: the game's `on_ability_used` hook is not told the
  target, and the brain's `npc_brain.target_id` is written at most once a second. A wider hook is a TEMPLATE ask.
- A shot already loosed still lands when its shooter has fallen since (a swing of the dead lands nothing).
- A roll through an arrow ticks no tutorial lesson, and a knocked-away shot does not tick "Parried".

**How to see it**: not yet. Step 3 gives the skeleton archer a kit with a shot.

**Tested**
- `cargo test --test regents` **54 passed, 0 failed** (53 before): `a_foes_shot_locks_its_aim_then_flies_and_a_roll_lets_it_through`
  (which abilities are shots; the lock and loose times, a lock longer than the tell; the height; the way on past a
  roller; NEGATIVES: a stopped or NaN missile has no way on, a hit that staggers still waits). Mutation: the lock taken
  off unclamped fails it.
- `cargo check --target wasm32-unknown-unknown`: clean.
- Regents unit suite **3504 passed, 0 failed**.
- `combat_playtest.sh` at 150 ms: **119 passed, 0 failed** (the parry, the late parry, the roll, the block and the hit dealt at
  once all go through `land_on_player` now).

**Left**
- No live check of a shot: no reducer-level suite can make one until a foe has a shot (step 3's leg of the combat
  playtest: loosed, blocked, knocked away, rolled through, stopped by a flinch; a player's call refused).
- The client shows nothing for "knocked away" (no stagger to read it from): step 3, with the glint.
- `regents.ranged_tokens` (F6) is the brain's: step 3.

## Step 65: THE SKELETON ARCHER, the first foe that shoots (2026-11-12)

Luke: "Yes, the archer". `FOES_PREP.md` §9 step 3, on step 64's server. Its numbers are the sheet's §6, all first
guesses and Luke's to change.

**How to play it**: one archer stands BY THE SKELETON CAMP (Luke's F15), a few steps south-east of the three (41, 3).
It is the warrior's skeleton in dark red with a bow. Come at the camp: at 16 m it notices you, and inside
14 m it stands and draws (the pose 1200 ms, a pale gold glint 300 ms before it looses). The arrow goes where you stood
250 ms before it flew: keep moving and it misses; stand and it hits for 16.5. Hold the guard facing it (9.9 through
with an axe), tap the guard as the arrow arrives (knocked away: nothing), or roll as it comes (it flies on past).
1800 ms between shots is your time to close. Within 4 m it backs off 5 m, once, then not again for 6 s: reach it
and it kicks you off it (4.4, a push, no stagger) and is helpless in the kick's recovery. 80 health, poise 50.

**Built**
- **Content**: `ability/foe_arrow.tres` (40030: the tell 1200 ms, 30 damage, range 0, not judged) and its
  `spell/foe_arrow.tres` (a bolt spell: the arrow body, 26 m/s); `ability/foe_bow_shove.tres` (40031: a kick, 650 ms);
  `kit/skeleton_bow.tres` (the shove its string, the arrow its skill; the shove pushes 6 m/s);
  `character/skeleton_archer.tres` (kind 108, Skeleton_B), `foe/skeleton_archer.tres`; clips in `anim/adventurer.tres`
  (`ability.40030` Bow_Aim_Neutral held 1200 ms, `recover.40030` Bow_Shoot, `ability.40031` Kick); the pack's second
  texture set copied in (`art/monsters/T_Skeleton_BaseColor_2.png`); the character in `genre.tres`.
- **`FoeDef`, a foe that shoots**: `shot_range_m`, `shot_near_m`, `shot_rest_ms`, `back_within_m`, `back_m`,
  `back_every_ms`; `shot()` (its kit's first skill a bolt spell flies); `validate` refuses the ranged tree with no
  shot, or a shot with a range or judged. **Its look**: `held_scene`, `hidden_meshes`, `albedo`, put on by a new
  component on every foe, `combat/foe_look.gd` (`FoeLook`): a new foe that reuses a model needs no new scene.
- **The ranged tree** (`sidecar/npc/brains/regents/trees/ranged.tres`): slain, go home, rest, then five new steps of
  `RegentsFoeBrain` with a task each: `hold_lock` (mid-draw it stands), `shove`, `step_back`, `approach`, `shoot`.
  The shot names its target; the server aims it.
- **Turns for shots** (F6): `regents.ranged_tokens` (1, a new hot rule): one foe drawing on or with a shot in the air
  at a player; a shot takes no melee turn, and keeps `token_gap_ms` from every other foe's hit (by when its arrow
  arrives).
- **The glint** (F5): `HitFeedbackComponent.shot_glint`, pale gold, 300 ms before the loose, not shown if the draw was
  stopped; never the red of an unblockable swing.
- **A STRING OF ONE STEP HAS NO FINISHER** (`KitSeed::is_finisher`, `KitDef.is_finisher`): the archer's lone shove
  must not stagger or be unblockable. No player kit has a one-step melee string.
- `foe_missile_hit` logs where a shot ended when it hurt nobody.

**Decided here (mine, Luke's to change)**
- WHERE BY THE CAMP: south-east of it (41, 3), so it can be met from the south without the three (its point is
  `skeleton_archer_1` in `frontier.tscn`; moving it is a level bake and a publish). To meet it ALONE, come from the
  south-east edge; from the west you get the camp and its arrows together.
- `regents.ranged_tokens` may be 0 ("no foe shoots"): `combat_playtest.sh` sets it, because that suite measures the
  melee camp's hits one at a time; the archer's own suite slays the three for its close-up leg.
- It backs off at its own pace (4.2 m/s), not at a walk: at a walk the 5 m took over six seconds of doing nothing.
- At 2 to 4 m with its step back spent it shoots point blank rather than circling: the draw is the opening.
- The continent has no archer: `build_continent.tscn` was NOT run (it also carries the glade's new look over, step
  59's "Left": Luke's say-so). The suite lists `skeleton_archer_1` as not yet built in, and fails the day it is.

**Tested**
- `game/regents/tests/archer_playtest.sh` (NEW; a real client at 150 ms, a real referee, ~3 min): **19 passed, 0
  failed**, and five on the server's own log. Past its notice it draws nothing; at 11 m the arrow lands for 16.50,
  1645 ms after the draw is seen (the tell, then the flight); the pale glint, no red; no stagger; a held guard 9.90
  through; a roll as it comes: nothing taken, and the server's "rolled through: it flies on"; a tapped guard:
  nothing taken, "knocked away", the hit dealt at once and taken back, the archer NOT staggered; within 4 m it steps
  back 4.5 m; followed into reach it holds its ground and shoves: 4.40, pushed 1.7 m, no stagger. NEGATIVES: a
  player's `use_ability` of the shot is refused ("wield a skeleton_bow first"); no shot staggered anyone.
- Regents unit suite **3612 passed, 0 failed** (3504): `_run_foe_archer` (content, the tree's steps by a fake world:
  walks in, draws naming its target, holds the draw, steps back and not twice, shoves, never shoots unseen, two
  archers never overlap a shot on one player, its look; NEGATIVES: no shot refused, out of sight no shot, the
  warrior keeps its sword and colors).
- `cargo test --test regents` **55 passed, 0 failed**: the archer's content test; the finisher test now says a
  one-step string has none.
- `combat_playtest.sh` at 150 ms, the archer holding its fire: **118 passed, 1 failed**: "dealt at once: 5 of 11 hits" wants half or more of the hits it sampled shown at once, and this run sampled six finishers (which wait, as designed) to five lights. The server log of the run shows every light dealt at once and only the finishers (40019, 40021) waiting, as on step 64 (whose runs were 4 of 8 and 7 of 13: the check sits on its own line). No archer shot or shove in the run (0 in the log). Not rerun to get a pass; the check wants the hit kinds, not a ratio.
- Pictures (windowed): `build/archer/archer_draw_side.png`, `archer_draw_front.png` (scratch, not committed).

**Left**
- NOT TESTED LIVE: a finisher flinching the draw (F7: built on the server, step 64; the playtest never hits the
  archer mid-draw), two archers on one player (unit only), the archer and the melee camp together on one player (Luke's playtest is the
  first: the gap between an arrow and a swing, and whether three and an archer is too much).
- "Knocked away" shows only as no damage (your health dips and returns when the parry arrives late): no text, no
  deflected arrow yet. The draw is the aim pose held, not a string pulled back; the bow hand's line is the player's.
- The integration suite was not run (`FOES_PREP.md` §9 step 7 runs it once).

## Step 66: the continent rebuilt, a shot ends where it touches, THE IMP CASTER (2026-11-12 to 13)

Luke: "Lets rebuild continent and then move forward with mage user. There is an interesting issue with mage (player
mage) where if a target is moving, the projectile get redeflected in a random direction"; then: "What I meant is mage
enemy after the continent and player fix".

**1. The continent, rebuilt** (`build_continent.tscn`, twice: with the archer, then with the imp)
- `build_continent.gd`: one `skeleton_archer` by each of the 16 test camps, where the glade's stands by its three
  (after the three, from no random stream: nothing placed before it moved). The camp at the start is the glade's, so
  it has the glade's archer and imp. `shared/world/continent.json`: 831 points, 17 archers, 1 imp.
- As step 59 said it would: the rebuild also took the glade's sun and environment and the nature import; the camp
  there still has NO grass or painted ground (`GroundPaint` and `Clutter` are flat-ground only). Not looked at in the
  game by me: Luke's eyes.
- The suite's "not yet on the continent" list is empty again.

**2. A shot ends where it first touches** (Luke's bug; `combat/missile_flight.gd`, NEW)
- FOUND: the referee says what a shot hit a moment BEFORE it touches, and the server takes the shot away when that
  word arrives. In between it is still a physics body. A target on the move is led, so it is met off its middle, and
  the shot kept its sideways speed and skidded off (or was thrown by the target's own body walking into it) until
  it was taken away. Reproduced with real physics before any fix: a bolt 1.45 m on from where it touched and still
  at 4.7 m/s 20 frames later; an arrow 2.24 m and 7.9 m/s.
- FIX: `MissileFlight` (a `BodyForces`): touching anything, a shot stops dead. On `body/bolt.tres` and
  `body/fireball.tres`; `ArrowFlight` extends it, so arrows too (a player's and the archer's).
- A rolled-through foe shot that was already stopped when the server heard of it flies on the way it came
  (`foe_missile_hit`).
- NOT a foundation change: `BodyDef.forces` is the genre's hook. If the template wants it for every missile, it is a
  `BodyDef` flag there.

**3. The imp caster** (`FOES_PREP.md` §9 step 4; the sheet's §6 numbers, all first guesses)
- **How to play it**: one imp stands by the skeleton camp, north-east of the three (42, -8); the archer is south-east.
  At 13 m it notices you; inside 11 m it stands and casts: an EMBER (a 1000 ms cast, a pale glint, then a slow
  fiery bolt at where you stood 250 ms before: step aside and it passes; stand and it is 13.5), and every THIRD
  cast a CINDER RING (a 700 ms cast, then an orange ring on the ground where you stood, 3 m, filling for 1500 ms:
  still in it as it fills, 23.85; walk out and nothing). 2200 ms between casts. No guard or parry answers the ring.
  It never steps back. Its poise is 30: two or three hits stagger it and the cast in its hands is lost. Up close
  with a melee turn it claws (6.3, blockable). 70 health.
- **Server** (`regents.rs`, `mod.rs`): `rules::is_foe_cast` (a shot or an AREA spell), `cast_lock_ms` (a ring is
  placed as its cast ends: lock 0); `foe_shot_due` lays a `spell_area` for a ring; `land_area` lands a FOE'S ring
  on players only (online, hittable), with no status (F8); a player's ring is as it was. A foe's cast of either
  kind must have range 0 and not be judged, and a finisher flinches either.
- **Content**: `ability/foe_ember.tres` (40032), `foe_cinder_ring.tres` (40033), `foe_claw.tres` (40034);
  `spell/foe_ember.tres` (the fireball's body, 12 m/s), `spell/foe_cinder_ring.tres` (3 m, 1500 ms);
  `kit/imp.tres`; `character/imp.tres` (kind 109, `art/monsters/Imp.glb`); `foe/imp.tres` (family "fiend", F13);
  clips `ability.40032/33/34`, `recover.40032/33`; `genre.tres`; `imp_1` in `frontier.tscn`.
- **THE IMPORT CHECK** (the sheet's open point): the imp's skeleton is the adventurer's less the little fingers and
  two foot leaves (55 of 65 bones, the same names). It plays the humanoid clips as it is.
- **`FoeDef.ring_every`**, `ring()`, `cast_at(n)`: every n-th cast is the kit's area spell. The imp runs the SAME
  `ranged` tree as the archer (no caster tree: the order it minds things is the same; `back_m` 0 so it never steps
  back). `RegentsFoeBrain.shoot` asks `cast_at`.
- **Client**: a foe's ring is drawn orange-red (`SpellLooks`, by its owner), a player's own stays blue; a ring's cast
  glints as a shot's does.

**Decided here (mine, Luke's to change)**
- No `caster.tres`: the sheet proposed one, but it would be the ranged tree again. A tree of its own the day the
  order differs.
- The imp's claw: a kit must have a string, and an imp that only stood there up close read as broken.
- A roll's unhittable moment holds against a ring too (the sheet says a ring is "only left"; the roll's promise is
  everywhere else, so I kept it).
- The imp drops the camp's loot (F14) and nothing of its own yet.

**Tested**
- `game/regents/tests/caster_playtest.sh` (NEW; a real client at 150 ms, a real referee, ~3 min): **15 passed, 0
  failed**, and five on the server's log: past its notice nothing; a bolt stood for 13.50; a bolt stepped out of
  after the lock, nothing; a ring stood in 23.85 as it filled, and drawn; a ring walked out of, nothing; the casts
  seen bolt, bolt, ring sixteen long; pale glints, never red; nothing staggered us; swung at up close it staggers
  and 2 casts "stopped before it flew"; it never stepped back. NEGATIVE: a player's use of the ring is refused.
- `archer_playtest.sh` after the arrow's new flight: **19 passed, 0 failed** and its five.
- Regents unit suite **3713 passed, 0 failed** (3612): `_run_shot_stops` (bolt, fireball and arrow by real physics
  into a walking body; NEGATIVE: the bolt with no `MissileFlight` skids on), `_run_foe_imp`.
- `cargo test --test regents` **56 passed, 0 failed**; wasm check clean.
- `combat_playtest.sh`, the archer and imp holding their fire: **119 passed, 0 failed** on a quiet machine (no
  editor, no game; Luke closed them, 2026-11-13), after three fixes TO THE SUITE, none to the game. Seven runs before
  it failed 1 to 9 checks, each traced in the fighter's whole log (`KEEP_LOGS=<dir>`, new):
  - its "face the nearest foe" turned the guard to the silent archer or imp standing by: now the nearest MELEE foe;
  - slain by the camp, it stepped back before its Slain status had gone, was refused, and stood at the spawn for
    every phase after: now it waits for the status, steps, and checks it arrived;
  - THE PARRY LEG: with two skeletons on you, the other's finisher often has you Staggered as a press is due, and the
    server refuses a staggered player's guard ("you cannot while staggered": the game's rule). Both tries of a quiet
    run went that way, and the leg quit under 40 health. Now such a press is not made and not counted, and you are
    healed between tries rather than the leg given up. The green run skipped two, then parried on its first.
  - My earlier guess that the failures were LOAD was wrong: the quiet run failed too, for the stagger reason.
  - Neither new foe acted in any run (0 in the server's log).
- Pictures: `build/imp/foe_draw_side.png` (scratch).

**Left**
- THE PLAYER'S BOLT FIX IS NOT SEEN LIVE at a moving foe by me (no playtest leg throws a staff bolt at a runner): the
  physics test reproduces Luke's bug and passes with the fix; his eyes are the live check.
- A shot that a body walks INTO without the referee's "about to hit" now stops on it with no word of a hit (before:
  thrown aside, also no hit). Rare; a referee-side fix is the template's.
- Not tested live: the imp, the archer and the three together on one player; a finisher flinching a cast (staggers
  were what stopped the two casts).
- No cue yet for a knocked-away shot; the ring has no sound; the imp has no loot of its own.

## Step 67: A FOE'S SHOT LEADS A MOVER (2026-11-13)

Luke, after playing the archer and the imp: "ranged (both archer and imp) are much easier to handle than melee ... the
no prediction casts are easy to dodge when fighting solo ... I can pick them off and have the enemy ranged be more or
less inconsequential". Asked whether foe shots should lead (reversing his F5 "no leading"): "Yes, lead first". Step 5
of `FOES_PREP.md` §9 (noticing and rest) is next.

**Why they were easy** (the numbers): the aim locked 250 ms before the loose on where you stood. The arrow (26 m/s,
9-14 m) arrives 0.6-0.8 s after the lock, the ember (12 m/s, 7-11 m) up to 1.15 s: a walk carries you 3-5 m, and a body
is under a meter wide. ANY movement missed; the tell asked nothing.

**Built**
- `rules::lead_point` (`server/src/genre/regents/mod.rs`): where a shot meets a target walking `vel` (flat: a jump is
  not led), loosed `to_loose_s` after the lock, `pct` of the way; the walk capped at `LEAD_MAX_MPS` (8, past a sprint,
  so a roll's burst is not followed far); three passes settle the flight time.
- `foe_shot_due` (`server/src/game/regents.rs`), at the lock: a SHOT (not a ring) aims at `lead_point` of the target's
  `movement_state.vel`; the server logs "aims <ability> N m ahead of <target>" when it leads.
- Hot rule `regents.foe_shot_lead_pct` (100, 0-150; `content/rules/regents.tres`, baked): 0 puts the first build back.
  `regents.foe_shot_lock_ms`'s description updated.
- Docs: `GAME.md` F5 (the reversal, his words), `regents-genre.md` (A FOE'S SHOT), `COMBAT_CURRENT.md`, `FOES_PREP.md`
  §4 rule 6.

**How to play it**: the glade's imp (north-east of the skeleton camp) or archer (south-east). Walk across its line as
it casts or draws: the shot meets you. Turn back, stop or roll after the glint: it flies to where you were going. A
guard, a parry and a rock answer it as before. Standing still, nothing changed. Rings are not led (still "leave it").
Restart the game; the play database is published (not fresh).

**Decided here (mine, Luke's to change)**
- The same lead for both foes (one hot rule). The ember is slow, so the same walk is led further and a turn slips it
  more easily: the imp's real threat stays its ring. A per-foe share would be a `FoeDef` field.
- The walk read is the server's `movement_state.vel` at the lock (what the client last reported), not an average.

**Tested**
- `cargo test --test regents` **56/0**, the shot test grown: a 5 m/s walk at 10 m met where it goes (more than 3 m
  ahead); NEGATIVES: 0 % and a standing target are not led; 50 % half; a jump not led; a burst capped; the slow ember
  led further. Wasm check clean.
- `caster_playtest.sh` (two NEW legs; the bolt's ways are now four): **17 passed, 0 failed** on the fighter: a bolt
  WALKED INTO (a steady strafe from 500 ms before the lock) is hit for 13.50; a bolt TURNED FROM (the strafe reversed
  after the lock) takes nothing; stood 13.50 and stepped-out-after-the-lock 0.00 as before. Server: "led 2 bolts at a
  walker (3.8 m 2.5 m)". ONE SERVER CHECK FAILED, not the lead's: "no cast was stopped by our swings". The log shows
  why: with the camp slain the imp has a melee turn free, so at 1.3 m it CLAWS, and our finisher staggered it
  mid-claw with no cast in its hands. Step 66's green run caught two casts by timing. Not rerun for a pass; the leg
  needs to strike it while it casts (left below).
- `archer_playtest.sh` **19/0** and its five (its legs stand still: nothing led).
- Regents unit suite **3713/0**. Play database `regents-rule` published (not fresh).

**Left**
- The caster suite's close-up leg: strike the imp while it CASTS (F7), not whenever it is near.
- Not tested live: a led arrow against a runner (no archer leg walks); two shooters on one player; the five together.

## Step 68: NOTICING AND REST, F9 to F12 (`FOES_PREP.md` §9 step 5) (2026-11-13)

Luke: "Start step 5". His answers (2026-11-12, `GAME.md`): F9 a foe notices in FRONT (140 degrees at `notice_m`) and
hears all round at 4 m, further if you sprint; F10 at rest it wanders a few meters round its point; F11 hit from out
of sight it turns on WHO HIT IT; F12 NOT CHAINED, after a foe's stagger or slow no other foe's lands for 1500 ms.

**Built**
- `FoeDef` (`content/foe_def.gd`), Behavior: `notice_arc_deg` 140, `hear_m` 4, `hear_sprint_m` 8, `wander_m` 3.
  `foe/sparring_skeleton.tres`: `wander_m` 0 (it stands in its yard; its notice 4 m = its hearing, so it is unchanged).
- The brain (`sidecar/npc/brains/regents/foe.gd`): `_notice` (the nearest player SEEN, `sees`: within `notice_m`,
  `in_front` of its yaw, in sight; or HEARD, `hears`: within `hear_m`, or `hear_sprint_m` past 6.5 m/s, halfway from
  a run to a sprint by `MovementConfig`); `_wander` (a stand of 4 to 10 s, a few steps at a walk, `walks`, to a spot
  within `wander_m`; a step that has not arrived in 6 s is over; back from a fight, home ALL THE WAY first, `_homing`);
  Startled turns on `status_by` (the status row's `by_entity`), with the old nearest-player fallback when the row
  names nobody. `tasks/foe_rest.gd`'s description.
- The server (`server/src/game/regents.rs`): `hurt_now` takes who hurt it and passes them as the Startled status's
  `by_entity` (the three callers: a missile, a spell, a swing). NOT CHAINED: a private table `unchained` (a player,
  the last foe that staggered or slowed them, until when); `unchained` asks before a foe's finisher staggers a player
  and before a foe's kit effect (the wolf's hamstring slow) lands on one; `chained_by` marks it after. The hit's damage
  is never held off. `rules::is_chained` (`genre/regents/mod.rs`). Hot rule `regents.unchained_ms` 1500 (0: off).
- Published with `--codegen` (a table added): the schema fingerprint moved, so an exported build from before needs
  exporting again.

**How to play it**: the glade's camp. Walk up behind a skeleton at a walk: it does not turn until you are 4 m off.
Sprint and it hears you at 8. Stand in front of one inside 10 m and it comes. At rest they wander a few steps and
stand, so which way each faces changes. Shoot one from behind with the bow from 20 m: it comes for YOU, not for
whoever stands nearer. With the three on you, after one's finisher staggers you the next one's finisher inside 1.5 s
still hurts but does not stagger.

**Decided here (mine, Luke's to change)**
- A player standing still within `hear_m` is heard (F9 says "hears all round at 4 m"; nothing about moving).
- Hearing needs no line of sight; a heard foe that cannot see you goes to where it heard you.
- The window counts from when the stagger or slow LANDED (not from its end): with an 800 ms stagger you have about
  700 ms after it before another foe's finisher may stagger you again. The same foe's own string is never held off.
- What counts as a slow: any kit effect a foe's hit puts on a player (today only the wolf's hamstring). A push
  (the wolf's lunge) is not held off.
- The sparring skeleton stands (no wander): it teaches in one spot.
- TEMPLATE ASK: the referee reads `by_entity` with `SpaceTimeSync.get_row(&"status_state", id)` (a test hook,
  `status_by_of`, stands in for it); `NpcWorldView` could carry it beside `statuses`.

**Tested**
- Regents unit suite **3734 passed, 0 failed** (3713): `_run_foe_notice` (21 checks): seen 8 m in front, 60 degrees off;
  NEGATIVES not seen at 80 degrees, behind running, in front behind a rock; heard 3.5 m behind out of sight, 7 m behind
  sprinting; NEGATIVES not heard 7 m behind running, 9 m behind sprinting; 360 sees all round. Wandering: stands first,
  six walks (slow) each within 3 m and back to a stand, spots round its point; 10 m off it goes home at its own pace and
  goes on home inside its wander; NEGATIVE the sparring skeleton never walks. Who hit it: the hitter 14 m behind, not
  the bystander 7 m at its side; NEGATIVE no name: the nearest, as before; NEGATIVE the hitter past its leash: nobody.
  Six older fixtures now FACE their player (`_yaw_to`): they test what a foe does once it has noticed.
- `cargo test --test regents` **56/0**: `is_chained` with its negatives (the window over, the same foe, a window of 0).
  Wasm check clean.
- `caster_playtest.sh` **17/0 and 6/6**, `archer_playtest.sh` **19/0 and 5/5**, `combat_playtest.sh` **119/0** and its
  new server check: "of 24 staggers by a finisher, none by another foe inside 1500 ms of one (4 held off: not chained)".
- The suites needed changes, none to the game, each from a log:
  - archer and imp: they stood at a fixed side of the foe's spawn point; a foe that sees only in front, and wanders,
    missed them. Now they first stand 3 m from where it stands NOW (heard), then go to the leg's spot.
  - the imp's spot: the camp's archer, wandering, came within its sight and shot too (a bolt "stood for" took 30 =
    13.5 + the arrow's 16.5); the shell keeps the archer down meanwhile (`ARCHER_DOWN`, slain every ~20 s). The archer's
    legs likewise keep the skeletons and the imp down (`CAMP_DOWN`): a skeleton and the imp came for it.
  - combat: the first skeleton is approached 7 m IN FRONT of where its body faces, and again (up to four) if it does
    not come: one run's log shows it had turned away on a wander step as the fighter arrived. Its home is where it
    stood before it moved. Two camp checks measured another foe's hit: the "too early" try took a finisher already on
    its way (14.00) for the watched light, now such a try is not made (`_other_hit_due`); a riposte flinched by
    another's hit is not counted and the parry is tried again. Three runs: 117/2, then 102/15 (the skeleton never
    noticed, which led to the in-front retry), then 119/0.
- Play database `regents-rule` published (`--codegen`, not fresh).

**Left**
- No live leg for F11 (a shot from behind) or for a wolf's hamstring held off (no wolf leg in a suite); both are unit
  and server-rule tested only.
- No live NEGATIVE for "not seen from behind": a wandering foe may turn at any moment, so a timed stand behind it is
  not a fair check; the unit suite holds it.
- The walked-home check is loose (within wander + 2 m of where it stood as we came).

## Step 69: THE FOE BENCH SHOWS A SHOOTER; COMBAT_CURRENT §11 rewritten (`FOES_PREP.md` §9 step 6) (2026-11-13)

Luke: "Start step 6".

**Built**
- The foe bench (`game/regents/workbench/foe_workbench.gd`): `shot_rhythm` (a foe that shoots: one round of its casts
  as its brain makes them, its shot and every `ring_every`-th its ring, each after its lock and `shot_rest_ms`; its
  damage a second if every cast lands), `fight_rhythm` (its shots for a shooter, its string otherwise: what "damage a
  second", "it kills you in" and the amber checks now read), `noticing` (how it sees, hears and rests, on every foe's
  sheet). A shooter's sheet: its range, its round of casts, its damage a second, its string up close, its step back,
  how long you take to reach it from its range at a run, the one-shot-at-a-time rule. "Play its swings" plays its
  shot and ring first.
- `COMBAT_CURRENT.md` §11 rewritten whole (it had grown by appending, and said things no longer true: a heavy every
  third swing, a 900 ms rest, a bolt at where you stood): the seven foes in one table; how a foe finds you and rests;
  how a melee foe fights; how a foe shoots (the lead); never chained; slain, loot, placement; making and tuning one,
  and the bench. §13 gains the foe rules it lacked (`attack_tokens`, `token_gap_ms`, `foe_aim_lock_ms`,
  `ranged_tokens`, `foe_shot_lock_ms`, `foe_shot_lead_pct`, `unchained_ms`, `startle_ms`).
- The handbook (`docs/HANDBOOK.md`) is the foundation's: nothing of the foundation changed, so it is unchanged; this
  game's guide to foes is `COMBAT_CURRENT.md` §11.

**How to use it**: in the editor, Content Dock, type `foe`, open the skeleton archer or the imp on its bench: the
sheet says its round of shots and what they do; "versus" says how long it kills you in by its shots.

**Tested**: regents unit suite **3741 passed, 0 failed** (3734): the archer's round is its arrow (16.5) every lock +
1800 ms and its damage a second that; its sheet names its range, its step back, its shove; versus reads its shots;
it fits; the imp's round is ember, ember, ring and its damage the three; every sheet says how the foe notices and
rests; NEGATIVE: a melee foe has no round of shots, its fight is its string. No server change: nothing to publish.

**Left**: step 7, integration once, with the hook's checks for steps 67-68 written first (the lead's log, the
startle's `by_entity`, `unchained`), then the continent's test placement (F15).

## Step 70: INTEGRATION, once (`FOES_PREP.md` §9 step 7) (2026-11-13)

Luke: "Start step 7".

**The hook's new checks** (`game/regents/tests/hooks/integration_genre.sh`)
- F11: the wolf's Startled status names who hit it (`by_entity`, read in the hit's own timed run).
- F12, in the wolf section where two wolves stand: the lunge staggers you after the same wolf's slow (its own string
  never held off); wolf_2's lunge staggers, wolf_1's 200 ms after it hurts but "does not land: not chained", both
  hurt in full; NEGATIVE: with the window over, wolf_1's lunge staggers again.
- A foe's shot: the archer's arrow drawn on you (the stand-in naming you, as its brain does), loosed by the server as
  the draw ends, an arrow of the archer's in the air; NEGATIVE: a CLI player stands still, so it is not led.

**The run: 1524 passed, 38 failed** (1509/5 at step 62; not run since). Every failure read from the run's output
and the server's log, none rerun:
- MINE, two bugs in the new checks, fixed: the archer block sat inside the wolf section and teleported you 77 m away,
  so the wolf's carcass legs that follow failed ("too far (76.8 m)", the cut line, the pelts, tanning: about ten);
  and its `use_ability_as` put you in the delay's place (`[actor, ability, target, aim, delay]`): "draws 40030 at
  nobody". The block now follows the tanning legs, with the target third, and steps back to the rack after.
- WORKED, live: wolf 117's lunge staggered you; wolf 116's 1294 ms later was held off ("not chained"); after the
  window 116's staggered.
- STALE since steps 65-66: the glade's foe count, 7, is 9 with the archer and the imp. Fixed.
- A QUICK CLI (this machine was quiet: no editor), about 25: the legs assumed "a CLI call takes a second or more".
  The roles' and the skeleton's strings sent step 2 while step 1 still swung ("still swinging", then "out of the
  combo's order", the pommel bash, the thrust, the rallying cut, lesson 40015 "Your grip" with them); a slain
  skeleton's body was read inside its 1 s. Fixed in the suite: 0.7 s after each separate swing call (the string's
  window is 5 s for the test), and the body waited for (up to 5 s).
- NOT EXPLAINED, 3: the dummy's "full bar breaks" leg. The server's log shows its first chop (request 17) wore no
  poise at all (no "wore" line), the next wore 11 to 1. Not the read's timing (a change for that was made and taken
  back). Not in code steps 67-69 touched (a dummy is no foe and no player: `unchained` and the startle skip it). It
  passed at step 62. Left open: `wear_poise` with `regents.dummy_poise` just set to 11 and a row whose `left` is 60.

**F15**: the continent's test placement is in (step 66): 17 archers (one by each of the 16 test camps, and the
glade's), the glade's imp. `shared/world/continent.json`: 34 warriors, 17 axemen, 17 archers, 1 imp, 30 wolves.

**Left**: the integration run again to see the hook's fixes and new checks green (about 80 min); the poise leg.

## Step 71: A PARRIED STRING GOES ON; THE BACKSWING READS; integration again (2026-11-13)

Luke: "for some reason I was having a hard time parrying/blocking a skeleton on hit 2 of the combo. I could
consistently get hit 1 parried but then it jumps straight to hit 3, and then if I purposely get hit by hit 1 and try
to parry/block hit 2 it just doesnt work... after that you can rerun it and make sure your fixes took".

**What his play's log said** (the play database's server log)
- "Jumps to hit 3": every parry of a first swing (17366's hack, 17374's cut) was followed ~600 ms later by
  "use_ability_as: you cannot while staggered": the parry staggers the foe, its brain sent its next swing anyway, the
  server refused it, and the brain had already counted it (`_swing` steps the string before the server answers). Ten
  such refusals in his session.
- Hit 2: his guard presses against the backswing (40018) reached the server 187-408 ms before it landed (most 200-300),
  against the cut (40017) 150 ms before to 106 after. Not the server: hit 2 is no different there. Not the clip's
  blow either: measured, the hand moves fastest within 20 ms of every foe swing's landing. But the backswing's clip
  (`Sword_Heavy_B`) BEGINS with the hand already in front (it starts where the cut ends, +34 degrees) and drifts slowly
  across it from 400 to 600 ms; the blow is a short flick at the end. No wind-up to read: the drift looks like the blow.

**Fixed**
- The brain (`foe.gd`): `rest` reads whether its status lets it act (`StatusDef.can_act`: not Staggered, Flinched,
  Slain); `swing` and `shoot` send nothing while it cannot. Its string goes on with its next step after the stagger.
  A caster's round is not moved on either.
- The backswing's clip (`anim/adventurer.tres`): `extra/Sword_Light_B` x0.335 (its recovery `Sword_Light_B_Rec`): the
  hand held chambered on the right (+79 to +47 degrees) for half a second, then a sweep across the front, fastest at
  701 ms (its wind-up 700, unchanged). Its lock, from the clip, 805 -> 1294 ms (baked: the kit's `locks`): the third
  swing comes about half a second later than before. Mine to change; `Sword_Light_A` is the other clip with a clear
  wind-up.
- `ANIMATIONS.md`: the rule that a foe's clip holds the hand wide through the first half of its wind-up.

**Tested**
- Regents unit suite **3749 passed, 0 failed**: `_run_foe_stagger_string` (in reach, its first step; Staggered 3 s it
  sends nothing, NEGATIVE: before the fix it sent one; on its feet, its SECOND step, not its finisher; the imp, Flinched,
  casts nothing, then its round's first). `_least_hand_bearing`: the cut, the backswing, the hack each hold the hand 40
  degrees or more off ahead through the first half of the wind-up; NEGATIVE: the old `Sword_Heavy_B` does not.
- `combat_playtest.sh` **121/0** and its server checks: NEW "of 3 parries, no parried foe sent a swing while staggered";
  "of 22 staggers by a finisher, none by another foe inside 1500 ms of one (7 held off)".
- `cargo test --test regents` **56/0**; wasm check clean. Play database published (not fresh).
- INTEGRATION again (Luke's ask): **1544 passed, 5 failed** (1524/38 before): every fix from step 70 took. The five:
  - the dummy's full-bar poise leg, 3: still NOT EXPLAINED (step 70).
  - the archer's shot, 2: nothing flew. The CLI's player connects for each call and is parked between them ("entity
    52 parked", "back where it stood"), and a foe never shoots a player who is not online (`foe_shot_due`); its lock
    comes ~1 s after the draw, between calls. A read of `online` connects too, so it always reads true: my first try to
    show it was wrong. The leg now checks what it can: the draw taken (its swing row), and NEGATIVE: nothing flies at
    a player offline, nothing loosed. NOT RUN YET: the test database had no foes left to replay it on.

**Left**: the two rewritten archer checks, at the next integration run; the poise leg.

## Step 72: THE ABILITY BAR (`ABILITIES_PREP.md` §7 step 1) (2026-11-13)

Luke's B5, B7, B11, B12 (`GAME.md`, "THE ABILITY REWORK BEFORE ARMOR"): a bar low in the middle in place of the text
line, round AND square built to compare, keys that are settings, a clear sign of stance and of a fight. Today's
abilities only (no new content).

**Built**
- `game/regents/ui/ability_bar.gd` (`RegentsAbilityBar`): health above; the weapon (its picture; hover: what the old
  line said, its string by its moves' names, the guard, the roll, Tab, and its mastery toward the next unlock), the
  roll (Ctrl, its cooldown), THE WEAPON'S THREE (Q E R) inside a thin RING that fills toward the kit's next unlock rank,
  the CHEST'S (F), the POTION key (G) apart, the staff's mana or the bow's arrows and chance to hit beside. A slot is
  ready, cooling (a sweep round, a wipe square, its seconds on it), unpaid (the staff's mana, tinted), locked (dim, a
  padlock, "rank 3"), or empty (faint; hover says what goes there: more with mastering the weapon, the chest's own
  ability, potions). A slot flashes as it fires. Out of stance the four FADE (E is the world's key then); in stance
  their edges LIGHT gold; in a FIGHT (you hit or were hurt in the last `CombatComponent.fight_s`, 8 s) a red glow
  breathes under the row. No role or mechanic names anywhere. `model_for` reads the game into a Dictionary;
  `show_model` draws it (the lab and the tests feed it their own).
- `ability_slot.gd` (`RegentsAbilitySlot`): one slot, drawn. Until an ability has an icon (`icons/ability_<id>.png`,
  the content's own icon path, wins) it shows a MARK of how it lands: a bolt, a circle on the ground, a blink, a fan,
  a lunge, a cut; the roll a turning arrow (letters collided with the keys: Frost Ring's "F" sat on E beside F).
- `bar_style.gd` (`RegentsBarStyle`) and its two looks, `bar_round.tres` (Albion) and `bar_square.tres` (boxes): sizes,
  gaps, colors, the ring, the out-of-stance alpha, all in the Inspector. Settings, Game: "Ability bar" (Round/Square)
  switches the game's at once.
- THE LAB, `game/regents/ui/bar_lab.tscn` (F6, no server): both bars fed one made-up player through the real
  `model_for`: buttons for the weapon (sword, axe, bow, staff, none), out of stance / in stance / in a fight, low mana;
  a slider for mastery (locks, the ring); Q E R F fire a slot; "Use round/square in the game" sets the setting. With
  `-- <out dir>` it saves nine shots (sword, staff, bow x the three states) and quits.
- KEYS ARE ACTIONS (B5): `CombatComponent.SLOT_ACTIONS` (`regents_slot_1..4`, Q E R F) and `POTION_ACTION`
  (`regents_potion`, G), added by `bind_keys` and defined with `Settings.define_key` (Controls: "Weapon ability 1-3",
  "Chest ability", "Potion"): rebindable now; the panel notes E is "also Interact", which it is by design.
  `slot_of(event)` replaces the old key constant; `key_label(action)` is what the bar prints.
- `CombatComponent`: `in_combat()`, `note_fight()` (called by `HitFeedbackComponent` on a hit by or on the local
  player), `cooldown_left(a)` and `cooldown_total(a)` for a spell or a swing (with no action component, this client's
  clock: the lab and the tests).
- The tutorial already teaches the string, the guard, the parry, the riposte and the roll; the weapon's tooltip holds
  the rest of what the line said.
- The HUD (`regents_hud.gd`): the text line (`_skillbar`, `skill_bar()`) and the bottom-left health/mana/roll bars are
  gone; the bar replaces them. The E prompt, the work bar and the foundation's hold prompt moved up above it.
  `make_bar` and `string_names` are public (the bar uses them).

**How to play it**: wield a weapon (I). The bar sits at the bottom: Tab a target or swing and its slots light; hit a
dummy and it glows red; Q fires Lunge and you see it cool. Settings, Game, "Ability bar" switches round and square.
Compare them still: open `game/regents/ui/bar_lab.tscn`, F6.

**Tested**
- NEW suite `game/regents/tests/suites/regents_bar.gd` (`--only=regents_bar`: **58 passed, 0 failed**): both looks and
  the setting; the keys (Q E R F G by default, each a Settings key; Q is slot 1, E slot 2 and still Interact; REBOUND
  to 1, 1 fires slot 1 and Q does not, NEGATIVE, then back); the model for nothing wielded, the sword (Lunge ready, its
  words, E R F empty and saying what goes there; no stance, then stance on a target, a fight on a hit, NEGATIVE: out of
  it after `fight_s`; cooling 4 of 6 s, then ready), the staff (locks with what opens them, mana it cannot pay, all four
  ready mastered), the bow (arrows); the ring (empty, half, starts over at an unlock, full); no "finisher", "tank",
  "support", "dps", "stance" or "role" on it; the drawn bar (tooltips, health, the row, a flash on its slot only, the
  fade out of stance and back, the square rebuild, the game's bar following the setting); the lab opens, Q cools on both.
  MUTATION: the lock rule and the fight clock broken, 6 checks failed; restored.
- The `regents` suite's old text-line check now reads the weapon's tooltip. Whole unit run **3836 passed, 0 failed**.
- `combat_playtest.sh` (its five reads of the old line now read the bar's model): FIRST RUN 72/47, the first chop never
  swung. FOUND: the slots STOPPED the mouse (for their tooltips); the playtest's clicks land at the window's corner and
  a headless window is 64 px, so the bar covered them; in play a free cursor over the bar would have eaten a swing the
  same way. FIXED: the slots PASS the mouse (still showing their words on hover). NEW check in `regents_bar`: a left
  click over the bar reaches `_unhandled_input`; NEGATIVE: with the slots stopping it, it does not. Then **119 passed, 0 failed**, and its server checks (not chained; no parried foe swinging while staggered).
- The lab's nine shots, looked at (round and square, sword, staff and bow, each state).

**Left for later**
- Icons for the abilities (a designer drops `game/regents/icons/ability_<id>.png`); until then the marks.
- The staff keeps its four spells on Q E R F until step 5 moves Blink to cloth chests; its locks are still mastery
  1/3/6/9 until step 2's item levels.
- G does nothing yet (no potions). A context E in stance (loot, revive) is Luke's "later".
- The fight sign is the client's (hit or hurt in 8 s); the server's own "out of combat" (for changing picks) comes
  with step 2.

## Step 73: EVERY SKILL 1-33; GALE BUFFED; THE SWORD'S POOLS DRAFTED (`ABILITIES_PREP.md` §8-9) (2026-11-13)

Luke's answers to S1-S4 (`GAME.md`): "move everything from 1-10 to 1-33 (a third of 99) for testing. There will be
wipes between now and the demo for public so we can finalize it then"; "draft a short sheet for me to rewrite"; "yes on
s4, but gale needs buffed largely as it does 8 dmg and nothing else right now on a long cooldown".

**Built**
- THE 1-33 TRACK, every skill (weapon masteries, gathering, making). Old rank r became level round(1 + (r-1) x 32/9):
  1, 5, 8, 12, 15, 19, 22, 26, 29, 33, the XP to each unchanged, the curve straight between them (2 at 15 XP, 5 at
  60, 12 at 280, 33 at 2400): the same pace, finer steps; a character's XP keeps its place (60 XP was rank 2, is 5).
  - Content: the 11 skills' `xp_to_rank` (32 steps); node and recipe `min_rank` (2 -> 5, 3 -> 8, 4 -> 12); materials'
    `rank`; the kits' `skill_ranks` 1/3/6/9 -> 1/8/19/29 (the default too). Generated by a one-off script from the
    mapping; the content's own numbers from now on.
  - Server (`genre/regents/mod.rs`): `RANK_TOP` 33 and `mastery_bp(rank)`: mastery's share an even step a rank, 27 % at
    the top (2700 basis points; the old 3 % a rank to 27 % at 10). `hit_damage` and `speed_pct` use it (rank 12, the
    old 4: 9.28 %, was 9 %). A native test fails any skill whose curve does not end at `RANK_TOP`.
  - Client twins: `SkillDef.RANK_TOP`, `RANK_TOP_BONUS_BP`, `mastery_bp` (the foe bench's damage reads it).
  - Hot rules: rank eases a round 1.2 % a rank for up to 10 ranks (was 4 % for 3: still 12 % at most).
  - The tester page's rank box reads the curve (1-33 already); the bar lab's slider runs to 33.
- GALE, BUFFED LARGELY: 6 -> 18 damage, 20 -> 12 s, 45 -> 60 degrees, push 9 -> 12 m/s, and two new effects: it SLOWS
  what it hurts 2.5 s (its spell's `status`, which a cone never applied before), and it WEARS POISE AS A LAST HIT
  (`wear_poise(.., true, ..)`): a full or worn bar breaks and the foe is STAGGERED (`regents.stagger_ms`), as the
  string's last hit does (the server's cone branch, `spell_lands`). Its tooltip says so ("It can knock a foe off its
  feet"). Cost unchanged (35 mana).
- THE SWORD'S POOLS, a draft for Luke to rewrite: `ABILITIES_PREP.md` §9 (per handle: a Q, three E options, upgrades,
  an ult; every motion from UAL1/UAL2; a metal's twist; what the server needs for them).
- THE BAR HIDES during a minigame round (it would sit over a round played with the mouse).

**Tested**
- `cargo test --test regents` **56/0** (the curve's points, `RANK_TOP` for every skill, `mastery_bp` at 2, 12 and the
  top, the gates' new numbers); wasm check clean.
- Unit `regents` + `regents_bar` **1460/0**: the curve, every skill ending at 33, `mastery_bp`, the gates.
- `skilling_playtest.sh` **118/0 + 8/0** (first run: the skinning drag failed, the bar over the round in a 64 px
  headless window; fixed by hiding it during a round).
- `combat_playtest.sh`: first run 118/3, its damage expectations assumed rank 1 and 3 % a rank (the axe reaches rank 2
  at 15 XP inside the test now); they read `SkillDef.mastery_bp`, and the role check the rank just before the last hit (the first two raise it now). Rerun **119/0** with its server negatives. PLAY DATABASE PUBLISHED (not fresh): characters keep their XP, read on the new curve.
- The integration hooks' rank numbers and Gale's leg updated (rank 5/8/12 refusals, Skinning 5's 96 % speed, the
  tester's 1-33 bounds; Gale's 22.9 at the top rank, slowed, its poise worn): NOT RUN (once per step: with step 2).

**Left for later**: the real 99 curve and its hours, before the public demo (a wipe). Luke's rewrite of §9.

## Step 74: ITEM LEVELS AND PICKS (`ABILITIES_PREP.md` §7 step 2, first slice) (2026-11-13)

Luke: "Start step 2". His decisions it builds (`GAME.md`): B1 (two layers, CATCH-UP 5x, a hot rule), B2 (T4: a holder
uses an item only up to their mastery), B4 (Q at 1, picks at ~5 and ~12, the ult at ~20), B5 (three slots from the
weapon, F the chest's), B6 (picks out of a fight; changing one costs, B13), B15 (one XP track, a refit keeps the level),
S4 (the staff: Q Fireball, its first pick Frost Ring or Gale, Blink on F).

**Built**
- THE ITEM'S OWN DATA: its XP (`"x"`) and picks (`"k"`: [first, second, ult], ability ids) in its bag row's
  `instance_data`, beside its quality, parts and traits. They go wherever the item goes (dropped, picked up, traded:
  T4) with NO new table; a REFIT keeps them (`keep_level`, B15). Server `genre/regents/mod.rs`: `item_xp_of`,
  `picks_of`, `with_field`, `with_item_xp`, `with_picks`, `keep_level`, `item_level` (the kind's mastery curve, 1-33),
  `usable_level` (min of the item's level and the holder's mastery), `item_xp_gain` (catch-up).
- THE KIT'S LAYOUT, content (`KitDef`, "Item levels" group): `skill_slots`, one per skill (0 the base on Q, 1 a pick
  option for E, 2 an ult option for R, 3 F), and `unlock_levels` [1, 5, 12, 20] (Q and F, the first pick, the second,
  the ult). Validated (a slot per skill, one base and one F at most, four levels never falling) and baked
  (`KitSeed::slots`, `unlock_levels`). The staff: Fireball 0, Frost Ring 1, Blink 3, Gale 1. Sword and axe: their one
  skill the base. Foes' kits: none (they gate nothing). The old mastery gate (`skill_ranks`) no longer gates a player.
- THE SERVER (`game/regents.rs`):
  - `train`: every combat XP payment (a swing's hit, a spell's, a missile's) pays the holder's mastery AND the wielded
    weapon when it trains that skill, `regents.item_catch_up` (5, NEW hot rule) times as much while the weapon's level
    is below the holder's mastery. A level reached is logged.
  - `need_slot` (cast_spell and every ability use): a player's skill only if its slot is open at the weapon's usable
    level, an option or ult only as one of its picks (`KitSeed::slot_refusal`): "not chosen: choose it at one of the
    weapon's picks", "opens at the weapon's level 5 (it counts as 3 for you)".
  - `choose_pick(item_row, pick, ability_id)` (NEW reducer, rate limit `pick`): your bag's weapon, OUT OF A FIGHT (not
    hurt within `regents.regen_delay_s`), the pick open at its usable level, an option of its kit's (an ult for the
    last), E holding one ability; a NEWLY OPENED pick is free; CHANGING one is refused for now ("changing a pick comes
    later (at a workbench, at a cost)": B13 not built).
  - `admin_set_item_level(entity_id, item_row, level)` (NEW, admin only): for the suites, and the Tester page later.
- THE CLIENT: `RegentsItemLevel` (`game/regents/combat/item_level.gd`), the twin of every rule above, plus `bar` (what
  is on Q E R F with these picks), `open_picks`, `progress`. `CombatComponent.on_slot`, `item_xp`, `item_picks`,
  `mastery`, `item_usable`, `choose_pick`: Q E R F press the item's abilities, refused here first as the server would.
  THE BAR: a locked E says "lvl 5" and what it offers; an open pick shows "+", pulsing, "choose in the bag"; the ring
  fills toward the weapon's next unlock; the weapon's tooltip says its level and what it counts as for you. THE BAG:
  a weapon's "Level 7, counting as 5 for you (Sorcery 5). Next unlock at level 12 (40 %)", its picks, and a button per
  option for each open pick. THE LAB: one slider for the weapon's level and mastery, "Take a pick".

**How to play it**: wield a yew staff: Fireball on Q, Blink on F, E locked ("lvl 5"). Fight: the staff levels with you
(five times as fast while below your Sorcery). At level 5 E pulses "+": open the bag (I), the staff, choose Frost Ring
or Gale. A second staff can take the other. A sword or axe: Q from level 1, nothing to pick yet.

**Tested**
- `cargo test` all green; `--test regents` **57/0** with NEW `item_levels_and_picks` (the data read and set, kept by a
  refit, NEGATIVE an item with neither gains neither; levels, T4, catch-up and NEGATIVE it never slows; the staff's
  layout; the slot gate and its NEGATIVES (unpicked at any level, picked but counting as 4); the picks and their
  NEGATIVES (below 5, the base, F, changing, the second at 11, E holding one, no ult, no pick 3); a foe's kit gates
  nothing). Wasm check clean.
- Unit: whole run **3864/0**; `regents_bar` **82/0**: the twin mirrors the Rust cases; the bar for a new staff, level 5
  (choose), NEGATIVE level 5 in a Sorcery-3 hand (locked, "counting as 3"), Frost Ring picked, Gale instead; the press
  refused here first (nothing on E; NEGATIVE picked on a level-1 staff); the bag's chooser at 5 and NEGATIVE at 4;
  layouts with two bases or a slot short refused.
- Integration hooks: the staff leg now picks (refusals: unpicked, below 5, NEGATIVE B2 a level-5 staff at Sorcery 1,
  Blink, pick 3, changing, the second at 12, E holding one), measures CATCH-UP exactly (the staff's XP rose five times
  Sorcery's), and casts Gale from a SECOND staff that picked it; a stranger's `admin_set_item_level` refused.
  First run **1596 passed, 6 failed** (step 71's five known failures, the archer's two and the dummy's poise
  leg, all passed): five were the new leg's own (Sorcery raised to 12 for catch-up made the Bolt and Fireball hit
  with mastery's share; the XP read by a JSON parse of the SQL's escaped string), one the axe's round at 83 % (on
  1-33 a few logs make Woodcutting 3, whose share shades it). FIXED in the hooks: Woodcutting held at 1 for that round
  (its XP back after); Sorcery back to 1 after the picks, so the staff is ABOVE it there (NEGATIVE of catch-up: it
  earned what you did, no more) and the 5x is measured at Sorcery 33 around Frost Ring; the XP read by a regex.
  Rerun **1653 passed, 0 failed**: the whole suite green, step 71's five old failures included.
- `skilling_playtest.sh` **118/0 + 8/0**; `combat_playtest.sh` **119/0**.
- The lab's shots, looked at (the staff: Fireball cooling, E locked at 5, Blink on F).
- PLAY DATABASE PUBLISHED with `--codegen` (two new reducers; no table changed).

**Left for later**
- The sword's per-handle pools (Luke's rewrite of §9), the axe's and bow's (§7 step 4), ults, UPGRADES (the second
  pick has nothing to take until there are).
- CHANGING A PICK (B13: one free change a week from level 20, then the head's materials at a workbench, escalating).
- The Tester page's control for an item's level (the reducer is there).
- The server's "out of a fight" is "not hurt lately"; dealing damage does not count yet.

## Step 75: CHANGING A PICK (Luke's B13) (2026-11-13)

Luke: "Build B13 next". His B13 (`GAME.md`): "one free change per item a week; then the head's materials at a workbench,
escalating per change and halving weekly; a newly opened pick free; the price PER PICK CHANGED; no free changes below
20; all hot rules". Read here as: the free change anywhere (out of a fight); the paid ones at a workbench; "halving
weekly" as one doubling forgiven per week without a paid change (the doubling's exponent steps back).

**Built**
- `change_pick(station_id, item_row, pick, ability_id)` (NEW reducer, rate limit `pick`): a CHOSEN pick to another
  option it could take (`KitSeed::change_refusal`: what a newly opened pick may take, the old choice set aside); out of
  a fight. FREE when the weapon's own level is at least `regents.respec_free_level` (20) and its last free change is
  `regents.respec_free_days` (7) old or never, anywhere. Otherwise at a WORKBENCH within reach (`station_id`), paying
  `regents.respec_bars` (2) of the weapon's HEAD'S MATERIAL (`head_material`: the refit's metal; an iron sword's Iron
  bar, a staff's Yew logs), doubled for each paid change before (`regents.respec_max_steps` 5 at most), one doubling
  forgiven each `regents.respec_halve_days` (7) without one. One call, one pick: changing three costs three times one.
- The item keeps its record in its own data: `"f"` (last free change, seconds), `"e"` (doublings), `"c"` (last paid,
  seconds), beside `"x"` and `"k"`; `with_field` writes them, every other field kept.
- `choose_pick` on a chosen pick now says "chosen already: change it instead (...)".
- Client: `RegentsItemLevel.change_refusal`, `head_material`, `change_price` (twins); `CombatComponent.change_pick`;
  THE BAG: under a weapon's picks, "Change it (free this week):" or "Change it (2 Yew logs, at a workbench):" and a
  button per option; the workbench in front of you is sent (`workbench_in_front`), else 0.
- Five NEW hot rules (`regents.respec_free_level`, `_free_days`, `_bars`, `_halve_days`, `_max_steps`).

**How to play it**: a staff with Frost Ring picked: open the bag (I), the staff: "Change it (2 Yew logs, at a
workbench): Gale". Stand at the workbench (E on it, or just in front), press Gale. Again: 4. At level 20 the first
change each week is free, anywhere.

**Tested**
- `cargo test --test regents` **58/0**, NEW `changing_a_pick`: the record read and written beside the level and
  picks; the free change from 20, NEGATIVE at 19, NEGATIVE six days after one, free again after seven; the price 2, 4,
  8 to the cap 64; a doubling forgiven a week, four weeks back to the base, none climbing with halving off; the head's
  material (iron sword: Iron bar; steel axe: Steel bar; a staff); what may change and its NEGATIVES (nothing chosen,
  the same, the base, the pick shut, no pick 3). Wasm check clean.
- Unit whole run **3875/0**; `regents_bar` **93/0**: the twin on the same cases; the bag's change row priced at a
  workbench at level 5, free at 20, NEGATIVE none with nothing chosen.
- Integration, NEW leg (the real server): NEGATIVE no workbench at level 12; NEGATIVE no yew logs (nothing changed);
  Frost Ring to Gale for 2; NEGATIVE the same again; back for 4 (doubled); at level 20 the free change away from the
  workbench, nothing paid; NEGATIVE the next is paid, at a workbench; paid 8. Whole suite **1583 passed, 0 failed** (the
  total moves run to run: several checks are loops over rows the run makes; the test database's log shows the leg's
  four changes: 2, 4, free, 8).
- PLAY DATABASE PUBLISHED with `--codegen` (108 reducers).

**Left for later**: MARKS joining the cost (B13: when marks exist); the bar's E slot does not say a change is
possible (the bag does).

## Step 76: R ASSIGNED; THE WEAPON'S ABILITIES WINDOW; THE UI TO-DOS (2026-11-14)

Luke, after playing 74-75: "right now mage seems to only be able to take an e ability (gale or frost ring) even though I
am level 33. Also we need a separate ui from the bag and possibly new UI anyway to match the feel of our ability bag ...
for now basic weapon ability ui once you click a weapon in your bar or your bag will work. I think that the mage
abilites are in an okay spot. ill flesh out the axe, sword and bow with all of their role abilites for next time. For now
just fix the R ability not being assigned and the new UI". His UI direction is in `GAME.md` ("THE UI, A REBUILD SOON
AFTER ARMOR"), with four to-dos.

**Why R was empty**: as built in 74, R took only an ULT, and no weapon has one yet; E holds one ability, so a staff could
only ever fill E.

**Built**
- R: UNTIL A WEAPON HAS AN ULT OF ITS OWN, ITS LAST PICK (level 20, R) TAKES THE OPTION E DID NOT (server `has_ults`,
  `pick_refusal`, `slot_refusal`; the twin's `has_ults`, `choices_for`, `bar`). A choice already at another pick is
  refused ("it is on the weapon already, at another pick"). A staff at 20: Fireball, Frost Ring, Gale, Blink.
- THE WEAPON'S ABILITIES WINDOW (`game/regents/ui/abilities_window.gd`, `RegentsAbilitiesWindow`), in the bar's look
  (the setting's round or square): the weapon's level against your mastery and a bar to its next unlock; its four slots
  drawn as the bar draws them, each named; a card per option for each pick open ("Choose for R (level 20)"); for each
  pick chosen, "Change E from Frost Ring (free this week):" and a card per option. Hover a card for what it does.
- IT OPENS by clicking the weapon on the bar (with the cursor free, say the bag open: `RegentsAbilityBar.weapon_pressed`;
  only that slot keeps a click, the rest still pass it to the game) or "Abilities" on a weapon in the bag. The bag's
  inline chooser is gone; the bag shows the weapon's level and "A pick is open!".

**How to play it**: a level-20 staff with Frost Ring: the bar's R pulses "+"; open the bag (I), click the staff on the
bar (or the staff in the bag, then Abilities): "Choose for R (level 20)": Gale.

**Tested**
- `cargo test --test regents` **58/0** (R: no ults; Gale for R at 20; NEGATIVES at 19, Frost Ring again, E taking R's,
  the base; Gale on R open from 20 and shut at 19).
- Unit whole run **3884/0**; `regents_bar` **102/0**: the twin's R cases; a new staff's R locked "lvl 20"; the window
  opened from the bag's button on the staff, its four slots (Fireball on Q, E waiting), the pick at 5, NEGATIVE none at
  Sorcery 4, R offering Gale (not Frost Ring) at 20, both taken shown on E and R; a click on the bar's weapon heard; the
  change rows priced (now in the window).
- Integration: the staff leg's R (NEGATIVE at 12; NEGATIVE Frost Ring, NEGATIVE Fireball; Gale at 20, on the item;
  later NEGATIVE Gale on R of a staff below 20): whole suite **1589 passed, 0 failed** (the test database's log shows the
  R pick). `combat_playtest.sh`: first run 67/50, every failure after a skeleton that never noticed the fighter (step 68's
  noticing: the foe faced away; nothing this step touches; the clicks before it passed); rerun **119/0**. A FLAKE to
  watch: the suite stands where the foe should see it, not where it faces now (`regents-genre.md`, NOTICING).
- The window's shot, looked at (a level-20 staff: its slots, R to choose, a free change): it was 1030 px wide at first
  (the slot names took `UiKit.note`'s paragraph width); plain labels now, 485 px.
- PLAY DATABASE PUBLISHED (no new reducer).

**Left for later**: Luke's role abilities for the axe, sword and bow (he writes them next); the UI rebuild (`GAME.md`'s
to-dos, soon after armor; resizing windows is template work).

## Step 77: TEMPLATE 1.8.1 PULLED; THE ROLL IS THE FOUNDATION'S (2026-11-14)

Luke: "Lets do some template work on both the roll and resizable window" (the dodge roll); "if it cant be shown, its
scrollable"; then "the push is done, lets continue" and, asked how Regent's uncommitted work should go, "Commit
everything".

**The template (another session, `UMF Template`)**: 1.8.0, the DODGE ROLL in the foundation (DECISIONS #309: an
`AbilityDef` that `rolls`, `EntityDefinition.dodge_roll`, `RollComponent`, `module/rolls.rs` with the private
`roll_state` table, `Genre::on_roll`) and WINDOWS THAT RESIZE AND REMEMBER (#310); 1.8.1, A WINDOW SCROLLS WHAT IT
CANNOT SHOW (#311). Shipped with `ship_template.sh` to Fishing, Fowl Play, DiscGolf and Regent's (each merged and
pushed). Regent's had committed steps 72-76 and the cinema lab first (`81a7afc2`, Luke's "commit everything").

**Built here**
- Republished `--codegen`; the merged repo green (unit 3990/0, cargo) before the switch.
- THE ROLL SWITCHED to the foundation's (the template's own list in its HANDOFF):
  - Content: `dodge.tres` (40010) `rolls`, `roll_status` Rolling (101), `roll_ms` 550, `roll_ms_rule`
    `regents.roll_ms`, `key` empty (the dash key, Ctrl as `bind_keys` binds it); `adventurer.tres` `dodge_roll`.
  - Server: `may_fight` no longer checks a roll (the foundation's `may_roll`: "no roll in the air"); `fought`'s
    roll branch is `rolled`, called from the genre's NEW `on_roll` (block down, cast ended, swing canceled, combo
    over, held and dealt hits judged with the foundation's `seen_us`); it no longer SETS Rolling: the foundation puts
    it on as an EFFECT. Every "is it rolling" reads it as one (`crate::module::is_rolling`; `roll_left_ms` for the
    still-rolling swing slack and the tutorial's roll-through). `press_seen_now` gone (unused).
  - Client: the combat component's roll (`dodge` key handling, its dash and set direction, the air hold, its clip)
    is the foundation's `RollComponent`; what a roll cancels here is `_on_rolled` (its `rolled` signal); `roll_until_ms`
    and `roll_cooldown` read the RollComponent; `dodge()` asks it to roll. The hit feedback's "Dodged" reads the
    Rolling effect.
- Windows: no code here; Regent's windows (the bag, skills, stations, the map, abilities) now resize, remember and
  scroll.

**Tested**
- Unit whole run **3994/0**: the regents suite's roll checks now on the foundation's (`RollComponent.direction_for`,
  the dodge's content and the adventurer's `dodge_roll`, its length the live `regents.roll_ms`; Ctrl through a real
  RollComponent: taken, the body held to its way, and `_on_rolled` canceling a swing's wind-up, the queue and the
  combo, nothing swinging while it rolls). Cargo all green; wasm clean.
- Server suites: archer **19/0**, caster **17/0**. Combat first run 67/50: its REFEREE STOPPED mid-run ("the project
  changed since it started": another session was writing `game/regents/vfx/` then; the referee watches `game/`), so no
  foe moved; the step-76 "flake" was the same (my own edit mid-run). Integration 1622/1: the late-roll NEGATIVE cleared
  the hit: the foundation credits the delay the USE carries (its last argument), where Regent's read its own
  `report_seen_delay` row; the suite's late roll now says 0 there too (nothing credited, as the check means).
- Rerun, the repo quiet: combat **113/6**, the six the yard's lessons: "Roll through" never ticked, so the loop kept
  rolling. FOUND, A TEMPLATE 1.8.0 BUG: the referee (`sidecar/combat/action_referee.gd` `may_be_hit`) reads only a
  target's STATE; the roll is an EFFECT now, so it reports a hit on a rolling player, the module refuses it ("they
  cannot be hit") and the genre never hears the miss (`on_ability_missed`, which ticks the lesson). Sent to the template
  session (1.8.2). Integration **1659/1**: the bowstring check found no unstrung bow from the carve before it (passed in
  the four runs before: watch it at the next run).
- TEMPLATE 1.8.2 (the referee reads effects; a hit reported on someone who cannot be hit is a miss), pushed by Luke,
  merged into the four games locally (this session's push was refused by its permission check). Regent's republished
  `--codegen`. Then: combat **119/0** (the referee ran throughout; the yard's six lessons ticked), integration
  **1642/0** (the late-roll NEGATIVE and the bowstring check green), unit whole run **4104/0** (with step 78's suite).

**For Luke**: push the four games (1.8.2 is merged in each, locally); restart the game and its referee. The other three games are merged but not
republished (each needs `tools\update_from_template.cmd`, or its own session).

## Step 78: THE VFX LAB (2026-11-14)

Luke: "how advanced or how far can we go (claude you generating) with vfx for abilites and effects? i think I want
some labs (like cinema/ability bar) that show case really cool looking vfx. try to stay procedural if possible", then
"Yes, build the lab". Steam's AI disclosure (`AI_ASSET_AUDIT.md`, his "No AI disclosure" rule the same day): effects
are CODE here (shaders, particles, meshes built at run time, Godot's own noise), never an image from a generative
model; none of this needs an asset.

**Built** (all new, `game/regents/vfx/`; nothing in the fights yet)
- THE SHADERS (`vfx/shaders/`): the ENERGY look (`vfx_energy.gdshaderinc`, glowing `_add` or covering `_mix`): two
  scrolling noises, one bending the other, read through a color RAMP as heat; a rim or core, bands (the toon look),
  eaten away by the noise with a hot edge, a sweep along U (a slash), heat across V, faded ends, a radial fade, pushed out
  by noise, soft against the ground. A CIRCLE on the ground (`vfx_circle.gdshader`): rings, ticks, a band of RUNES
  (each a hash's strokes on a 3 x 3 grid), a fill growing from the middle with a bright front (a warning), drawing itself
  round, wisps. A PARTICLE's shape (`vfx_sprite.gdshaderinc`): dot, streak (along its flight), star, puff (lumpy, eaten
  as it fades, lit by the scene in `_mix`), shard, ring; facing the camera, its own up, or its own turn. A RIPPLE in the
  air (`vfx_distort.gdshader`): a bubble's rim or a ring on a disc bends what is behind.
- `VfxKit` (`vfx_kit.gd`): the shared noises (FastNoiseLite, made once), ramps (HDR), the materials, particles and their
  motion, a slash's ARC mesh, a spike, the fire / frost / arcane ramps. `VfxEffect` (`vfx_effect.gd`): an effect's
  base: built once (`_build`), moved by its own clock (`_animate`; it gives every part the shaders' `fx_time`), plays,
  stops, says it finished, frees itself (or hides, the lab's way), asks the camera to shake (`shook`), `target` and
  `caster`.
- TEN EFFECTS (`vfx/effects/*.tscn`, their look the root's exported values): `fire_charge` (and `frost_charge`, the
  same in frost), `fire_missile` (core, banded flame drawn back, flame puffs, smoke, embers, a ribbon, `arrived`),
  `fire_blast` (flash, a banded ball burning away from inside, a heat ring, a bending bubble, embers, chunks, smoke, a
  cooling scorch, a light, a shake), `frost_ring` (the circle draws itself, its runes turn, it fills for the second
  before it lands; then shards punch up in a wave from the middle, frost rolls out, glints, a cold ring; they crack
  away), `blink` (a violet column snaps shut on you as you fade, a streak, the other end bursts open with a ripple, you
  fade back in), `gale` (a funnel from the hands, blades of air sweeping out over the 60 degrees, streaks, dust and
  leaves), `axe_overhead` (`VfxSlash`: a crescent swept down the axe's path, a bright edge, an echo, sparks, a flare,
  dust, chips and a ring where it hits the ground), `parry_flash` (a star, rings snapping out, sparks sprayed back at
  the attacker), `cinder_ring` (the imp's: a red circle on darkened ground filling from the middle with a bright front
  as its 1.5 s run out, embers rising faster; then a banded wall of fire, sparks, smoke, a burnt floor).
- THE LAB (`vfx/vfx_lab.tscn`, F6, no server): the adventurer, a skeleton and the imp on grass under the glade's own
  light (sky, filmic, glow 0.6, fog, as `frontier.tscn`), seven SHOWCASES played as in a fight (the cast in the hand,
  the missile, the blast; the axe's clip with its cut timed from its `wind_up_ms`; the skeleton's cut parried; the imp's
  ring under you), speeds 1 to 1/10, Day / Dusk / Night, loop, an orbit camera, the camera shake, and a line of what is
  on screen (fps, draw calls, particle systems). Shots: `-- <out dir> [name]` saves a contact sheet of six moments of
  each, day and night, timed on the lab's own clock (a first-use shader compile never shifts them).

**How to play it**: open `game/regents/vfx/vfx_lab.tscn`, F6. Pick a showcase (or Up / Down), Space again, L to loop,
[ and ] for the speed, right mouse to turn round, the wheel to come nearer. To change an effect: open its scene in
`effects/`, change the root's values in the Inspector (colors, sizes, counts, times), run the lab again.

**Tested**
- Unit `regents_vfx` (new) **100/0**: every effect scene builds, plays on its own clock, finishes and frees itself (and
  kept, hides, plays again; stopped, hides); the missile flies distance / speed and arrives there once, not a tenth of a
  second short; Blink fades its caster, moves it at its moment (and, told not to, leaves it) and puts the fade back; the
  frost shards wait for the landing; the blast asks for its shake, and a blast with none for none; NO image file under
  `game/regents/vfx/`; the lab opens, plays all seven, and gives the engine its speed back as it closes. NEGATIVE: an
  effect that never frees itself fails each effect's "frees itself" check.
- The look: the lab's shots, day and night, looked at after each pass (three passes: placement before entering the
  tree, soft lit smoke, strands of wind, a slimmer crescent, gold parry rings, dimmer fire). No shader errors in a
  windowed run. Headless runs cannot draw, so how it looks is the shots' and Luke's.
- Unit whole run (`tests/run_tests.sh`, with step 77's and the audit's uncommitted work in the tree) **4094/0**, the
  lints, no unexpected engine errors, nothing left over at exit.

**Left for later (Luke's to decide)**
- Wiring them into the fights: the fireball's look (`fireball_look.tscn` is `ShotLook` today) and its blast
  (`ImpactBurst`), the frost and cinder circles where the areas are shown now, the parry, the last hit's cut. Each is a
  presentation change on what the server already says.
- Others in a crowd: 300 players' effects at once want a lighter version for others' casts (fewer particles, no bending
  air) and a cap; the lab's line shows each showcase's cost.
- The game's camera shake (the effects ask through `shook`; only the lab listens).
- The style: Luke plays them and says what to push (brighter, more toon, more smoke, slower blasts); the axe's cut is
  timed to the lab's clip and may want `starts_at_s` moved.

## Step 79: THE VFX LAB, LUKE'S FIRST NOTES (2026-11-14)

Luke, after playing the lab: "this looks pretty awesome"; (1) "the fireball (and other magic) originates from behind
the hand instead of slightly infront of it"; (2) "axe overhead is an overhead hit when the animation is a sideways
hit"; (3) "parry should be at the block hand not higher than head"; (4) "frost ring starts 2 handed but then jumps to
one handed all of a sudden"; "the frost ring and cinder ring should be more similar and cohesive but I love the
fireball and ice shards coming up from the ground"; "are these expensive? i think replacing the sword/melee swings
with the vfx from the overhead is nice if cheap".

**Built**
- (1) A spell leaves IN FRONT of the hand: the lab's `_cast_point` (the hand bone, or the middle of two, then on toward
  the target: the charge 0.16 m, the missile 0.3 m, let go 0.06 s into the throw).
- (2) THE CUT FOLLOWS THE REAL BLADE (`effects/blade_cut.gd`, `VfxBladeCut`; replaces the fixed arc `VfxSlash` and
  `axe_overhead.tscn`): the sheet the held weapon sweeps (found as `SwingTrail` finds a blade: `blade_of_item`),
  drawn by two `RibbonTrail`s wearing the crescent's look (`VfxBladeCut.look()`: hot at the tip, nothing at the hilt,
  eaten away as it ages; a thin bright line along the tip); at the hit a flare, sparks and a light at the tip, and dust,
  chips and a ring only when the tip ends at the ground. Any swing, sideways, overhead or a thrust. `RibbonTrail` (a
  combat file the game uses) gains `look` (a material of its own) and UVs (U along it, V base to tip); with no look
  it draws exactly as before.
- (3) The parry's flash is at the BLOCKING HAND (the one nearer the foe's weapon hand), 0.15 m toward the foe.
- (4) Frost Ring is two-handed throughout: `pose.spell_channel`, its charge between both hands, let go with
  `ability.40014` (the two-handed cast).
- ONE FAMILY OF RINGS (`effects/ground_ring.gd`, `VfxGroundRing`, `element` FROST or FIRE; replaces `frost_ring.gd`
  and `cinder_ring.gd`; the two scenes are its values): the same rune circle, filling warning, rising motes and wave
  from the middle; frost's ice shards stand then crack away, fire's tongues of flame leap and burn out; the foe's
  ring keeps its darker ground and stronger fill (it must read at a glance).
- The lab: "Axe Heavy" and a new "Sword String" (the sword's three hits, each wearing the cut: what any swing could
  wear), the weapon in the hand (`_arm`). `-- cost` measures every showcase (below).

**What they cost** (`"$GODOT" --path . res://game/regents/vfx/vfx_lab.tscn -- cost`; this machine, 1280 x 720, the
stage alone 84 draw calls and 1.16 ms of GPU): at their peak, Fireball +14 draw calls, 126 particles, +0.52 ms; Frost
Ring +38, 70, +0.45; Blink 40 particles, +0.39; Gale +10, 94, +0.33; Axe Heavy +14, 30, +0.39; Sword String +15, 30,
+0.41; Parry +10, 48, +0.37; Cinder Ring +36, 112, +0.56. So a cut on a swing is cheap: two ribbons while it cuts (the
plain trail is one), and the hit's flare, sparks and light for a moment. The rings' draw calls are their 24-30 rising
meshes, one each: a MultiMesh would make them one.

**Tested**
- Unit `regents_vfx` **114/0**: as step 78, and both rings are ground rings of their element where nothing rises before
  the landing and everything is up after it; the cut wears its look, draws nothing before its window, draws the
  blade's path through it (a sword swept round), lands its hit at the tip, and with no weapon draws nothing.
- The shots of every changed showcase, looked at (the fireball leaving the palm, the axe's sideways crescent, the
  sword's three cuts thinned once, the parry at the hand, frost two-handed, the cinder ring's flame tongues).
- Unit whole run **4118/0**, the lints, no unexpected engine errors, nothing left over at exit.

**Left for later (Luke's to decide)**
- Wiring the cut into the game's swings: `SwingTrail` makes a `RibbonTrail` per fighter today; giving it
  `VfxBladeCut.look()` (and the hit's flare and sparks) is a small change, presentation only. Others' swings in a crowd
  could keep the cut and drop the hit's light.
- The rings' rising meshes as a MultiMesh before they are in the game (300 players).

## Step 80: TODAY'S CUTS BESIDE THE NEW ONES, IN THE LAB (2026-11-14)

Luke: "add to the lab comparison of todays cuts with axe and sword and the new cuts before I decide to wire them in or
not".

**Built** (`game/regents/vfx/vfx_lab.gd` only)
- Two showcases, **"Axe: today | new"** and **"Sword: today | new"**: a second adventurer and skeleton beside the
  first pair, each pair tagged ("Today" on the left, "New" on the right), the same weapon in both hands, the same
  swings at the same moment (the axe's heavy hit; the sword's three hits).
- TODAY is drawn as the game draws it now: a plain `RibbonTrail` along the blade with `SwingTrail`'s own values (its
  `lifetime_s`, `player_color`, `from_wind_up`, `after_hit_ms`, `blade_from`, read from a fresh one, so a change there
  shows here). NEW is `VfxBladeCut`. Neither shows the hit feedback (`hit_feedback_component.gd`), which is the same
  for both.
- A Blink cut off part way no longer leaves anything faded: `_reset` puts back every mesh under the five roots (the tag
  above the hero was left invisible). Shot names are slugs (`slug()`: "Axe: today | new" is `axe_today_new`).

**How to play it**: the lab (F6), the two "today | new" entries; slow it to 1/4 to see each sheet form.

**Tested**
- Unit `regents_vfx` **125/0**: both comparisons show the second pair and the tags, draw today's plain trail (no look
  of its own) and the new cut along a moving blade, and another showcase hides the second pair. NEGATIVE: today's trail
  never drawn fails both "today's plain trail" checks.
- The shots of both, looked at: today's faint sheet beside the crescent, swing for swing.
- Unit whole run **4129/0**, the lints, no unexpected engine errors, nothing left over at exit.

**Gale's funnel, softened** (Luke, with a picture: "The gale cone needs softened at its end, the hard lines at the
cones base dont look good"): the hard rim at the funnel's mouth was the MESH, found by hiding the funnel for one shot:
Godot's `CylinderMesh` keeps part of its UV for its caps, so a fade toward the mouth never reached the edge.
`VfxKit.tube` (and `spike`) now build their own cone with exact UVs (V 0 at the top, 1 at the bottom), which also lets
the blink column's top and the flame tongues fade as meant. The funnel fades over most of its length to the mouth and
at its silhouette (`rim_fade`), the wind blades lost their hard bands (smooth, softer erosion, wider fades) and fade in
over 0.12 s. Shots looked at: the gale (cropped close), the blink, the cinder ring. `regents_vfx` 125/0 after.

**Waiting on Luke**: whether the game's swings take the cut (PROGRESS 79, "Left for later"). Answered in step 82.

## Step 81: THE WARDROBE: CLOTHES, ARMOR AND THE DYE (2026-11-14)

Luke, 2026-11-14: "I want to continue armor next but before we do, we need to figure out clothes and shaders on them
... do we have armor models? all colors on every model should have a shader material that allows for any color combo
... a lab that is basically a more advanced character selector ... a full inventory of what clothes/armor potential we
have based on our prep, what we need and how we can reuse metal for all tiers/metals with shaders and recoloring."
The inventory, the plan and his open decisions (W1-W8): **`docs/regents_rule/WARDROBE.md`**.

**Built** (all the genre's; nothing in the game yet, presentation only)
- **The Knight outfit** (plate armor, the pack's only one; the foundation's import left it out): male and female,
  20 pieces, in `game/regents/art/outfits/knight/` (`ATTRIBUTION.md`), brought in by
  `python game/regents/tools/wardrobe_assets.py knight` (textures at 1024, its three colorways, no LODs).
- **The dye zones**: `wardrobe_assets.py zones` sorts each outfit's atlas into six DYE SLOTS (metal, main, accent,
  trim, leather, under) by how texels change together across the pack's three colorways, from reference colors in
  `game/regents/wardrobe/zones.json` (designer-editable); metal from the ORM's blue channel. Writes
  `wardrobe/zones/T_<Outfit>_Zones.png` (lossless, no mipmaps) and each colorway as a palette (`palettes/*.tres`).
- **The dye**: `outfit_dye.gdshader` (the outfit's own albedo, ORM and normal textures plus the zones: a slot's color
  times the painting's brightness against the slot's mean; metal also takes metallic, roughness and wear in its
  hollows; alpha is how much; a trim glow; `show_zones`). `DyePalette` (five cloth colors and a `MetalFinish`) and
  `MetalFinish` (`metals/`: copper, iron, steel, four studies for later tiers) as `.tres`.
- **`Wardrobe`** (`wardrobe.gd`): pieces FOUND by file name (`<Male|Female>_<Outfit>_<Part>`) in its `PIECE_DIRS`, by
  body and slot (head, shoulders, neck, torso, arms, legs, feet); `full_set`; `dress(model, palette)` (one material
  per outfit on a figure, re-tinted, never skin or hair; undressing gives back what was worn, a colorway's material
  too); `makeup(piece)` (its vertices by dye slot); `figure(look)`; a closed helm hides hair and beard, a hood the hair.
- **The wardrobe lab** (`wardrobe_lab.tscn`, F6): a figure on a turntable, animated (a `Mannequin` on the adventurer's
  animation set); views One, Metal tiers (the Knight in each finish), Outfits (all five on both bodies), Colorways
  (the pack's painted colorways beside the dye's own); Z zones; every piece per slot with what it is made of; the
  colors (palette, metal and its sliders, each cloth slot); Random, Clear, Save palette. Shots: `-- <dir>`, plus
  `wardrobe_inventory.md` (the piece table in WARDROBE.md §2.2).

**How to play it**: open `res://game/regents/wardrobe/wardrobe_lab.tscn` in the editor, F6. Try Metal tiers (2), then
Random colors a few times, then Z.

**Tested**
- Unit `regents_wardrobe` **208/0** (`-- --only=regents_wardrobe`): every outfit's pieces found for both bodies and
  each slot; the Knight's set wears its armored torso; a woman's four headwear; a part's slot from its name, and
  NEGATIVE: heads, hair and names of no slot are not pieces. Every outfit's mask is 1024, no mipmaps, every sampled
  texel exactly a slot, with metal, main and leather; its three colorway palettes and the copper, iron and steel
  finishes load, in range; NEGATIVE: a material with no zones (skin, an unknown outfit, none) is no outfit's. A mixed
  figure (Noble top, Knight legs) dresses every outfit surface, one material per outfit, wearing the palette's main and
  metal; NEGATIVE: skin and hair keep theirs; a second dressing re-tints the same materials; undressed, its own
  materials return, and a painted colorway's material returns after two dressings; NEGATIVE: undressing an undressed
  figure does nothing. A closed helm hides hair and beard, a hood the hair only, a crown and no headwear neither. The
  armet is metal, the Knight's cloth torso has main cloth, shares add to 1; NEGATIVE: no piece, no makeup. The lab
  opens on one dressed, animated figure; Metal tiers a figure per finish, each in its own metal; Outfits ten; the
  Knight's Colorways six; Z shows zones on all of them, painted ones too; Random colors re-dyes.
- The shots, looked at (windowed): the dye's colorways beside the pack's painted ones (all five outfits: close; the
  Knight's gold colorway made from the silver texture), the seven metal tiers, the zones on all ten figures, six custom
  looks front and back. Found and fixed from them: figures facing away, labels running together, the female helm
  under her hair (hair now hidden under closed helms).
- Unit whole run **4377/0** (with the VFX session's work in the tree), the lints (the lab's quit goes through
  `AppExit`), no unexpected engine errors, nothing left over at exit. No server suite: nothing here touches the server.

**Left for later**
- Luke's W1-W8 (WARDROBE.md §7): the family table, who picks colors (dyes from herbalism?), silhouette by tier, the
  gaps (cloth headwear, a leather helm), the four studies, any-color in the character picker.
- Into the game (WARDROBE.md §6): a public `wear(pieces)` on the foundation's `ModularCharacter` (template work), a
  genre look component reading `worn` and dressing, the picker's colors on the `appearance` text (add-only); measure
  the dye's cost with the load test.
- The zones are a first pass: some small parts (buckles, the Noble's boots) may sit in a neighbor slot. Fix in
  `zones.json`, re-bake, look with Z.

**Luke's calls, the same day** (`GAME.md`, "The wardrobe: who wears what"): every player starts in the Peasant clothes
in colors they pick; leather is the Ranger, cloth the Wizard, metal the Knight; the Noble is for NPCs. "Brown leather
to start and then can scale with different animals"; "cloth ... needs more neutral". Then built:
- **Tier palettes** (`wardrobe/palettes/`): `leather_1_soft` (deer: tan buckskin), `leather_2_supple` (wolf: cool
  gray-brown), `leather_3_hardened` (stag: deep oxblood); `cloth_1_flax` (linen: oatmeal), `cloth_2_hemp` (stone
  gray-taupe), `cloth_3_nettle` (deep slate, silver-gray thread); the fittings in the tier's metal (copper, iron,
  steel); four `starter_*` examples of a player's own Peasant colors. Hardened was deepened after its first shot (it
  read orange).
- **The lab's Tiers view by family** ("Tiers of": Metal on the Knight, Leather on the Ranger, Cloth on the Wizard,
  Starter on the Peasant, without headwear), `tier_palettes(prefix)`; shots `wardrobe_tiers_<family>.png`.
- WARDROBE.md §5 (who wears what, the tier table, the gaps) and §7 (W1-W8). **Luke: "Yes, all stand"**: W1-W8 and
  the tier colors are settled (`GAME.md`, "W1-W8 ANSWERED").
- Tested: `regents_wardrobe` **231/0** (each family a figure per palette, each wearing its palette's leather; the
  Ranger's tiers wear the hood, NEGATIVE: the Wizard's and the starters' none). Shots looked at: the three families'
  tiers and the starters.

## Step 82: THE LAB'S EFFECTS IN EVERY CURRENT ABILITY (2026-11-14)

Luke: "Okay lets use the vfx in all the current abilites we have". (Step 81 is the wardrobe, another session's.)

**What each ability shows now** (presentation only: the server decides everything, as before)
| Ability | Who sees it | How |
|---|---|---|
| Every melee swing (sword, axe, the foes' cuts, the wolf's bite) | everyone | `SwingTrail` wears the crescent: `VfxBladeCut.look()` on its sheet and a bright line along the tip (`crescent`, on; off draws the old plain ribbon). Colors: `crescent_player_color`, `foe_color` |
| Fireball (and the imp's ember: same body) | everyone | the body's look `combat/fireball_look.tscn`: the lab's `fire_missile.tscn` RIDING on it (`rides`), its ribbon; where it ends, `fire_blast.tscn` on the ground below (`ShotLook.end_scene`, `end_on_ground`) |
| The staff's Bolt | everyone | `combat/bolt_look.tscn`: the same missile in arcane violet (`element` Arcane, small, no smoke), ending in `bolt_hit.tscn` (the parry flash's script in violet) |
| Frost Ring; the imp's Cinder Ring | everyone | `SpellLooks` draws `frost_ring.tscn` / `cinder_ring.tscn` (`VfxGroundRing`), its warning running exactly until the row's `lands`; a row gone mid-landing lets it play out |
| Fireball's and Frost Ring's casts | the caster and everyone who gets their `casting` row | `AbilityVfx` (NEW component on `adventurer.tscn` and `foe.tscn`): the charge in front of the hand(s) for the cast time |
| The imp's ember and ring tells | everyone | `AbilityVfx`: the charge in its hand(s) through the wind-up (`started_elsewhere`) |
| Gale | the caster only | `AbilityVfx`: the gust at the feet the way it was aimed, as `cast_sent` says it went. OTHER CLIENTS ARE NOT TOLD of a cast with no cast time (no row for it): showing it to them is a server change, Luke's call |
| Blink | everyone | `AbilityVfx`: a jump of 3-12 m in one frame by a fighter wielding a kit that casts (both clients see teleports snap): the columns at both ends, the body faded in where it landed. Your own character only within 2 s of casting Blink (a teleport of yours, as the playtests use, is none) |
| A parry | the parrier | `AbilityVfx`: the flash at the blocking hand (the one nearer the attacker), out toward them |
| The bow's arrows | everyone | unchanged (`arrow_look.tscn`, its own trail); the hit's spark is `HitFeedbackComponent`'s, as before |

Which effect an ability shows is a table a designer edits: `game/regents/vfx/ability_vfx.tres` (`AbilityVfxSet`, rows
`AbilityVfxEntry`: the charge, one or two hands, how far ahead, the effect as it lands or as it jumps; the parry's).
The lab's "Axe/Sword: old | new" now compare the plain ribbon the game drew before with the crescent it wears now.

**Tested**
- Unit `regents_vfx` **166/0**: as before, plus COVERAGE (every spell drawn by the lab's looks; every spell with a cast
  time and the imp's two tells show a charge; every swing wears the crescent) and `AbilityVfx` on a stand-in fighter (a
  real adventurer model and combat component, bound by hand): no cast no charge; Fireball's charge 0.16 m in front of
  the left hand, gone with the cast; Frost Ring's between both hands; Gale at the feet the way it was aimed, and
  NOTHING for Fireball as it is sent; Blink for an 8 m jump with a staff, NOT for a step, a 30 m jump or a sword; the
  imp's ember charge in its right hand through its wind-up; the parry's flash; `SpellLooks`' rings (frost for a
  player's, fire for a foe's, landing at once when seen late, playing out when the row goes). NEGATIVE: the charge put
  back in the wrist fails three checks.
- Unit `regents` **1407/0**: its ring-color check now reads the `VfxGroundRing`s; the shot-look check reads the riding
  missile and the end effect.
- `caster_playtest.sh` (a real client and referee): its fighter's three NEW checks (the imp's charge through each
  tell, its ring drawn as the fire ring, its embers ending in the fire blast). Three runs: the first 20/0 with one
  server check failing ("no cast was stopped by our swings", a timing check: our swings must stagger the imp mid-cast);
  the second never fought (the imp never noticed the fighter: the known noticing flake); the third **20/0 and 7/7**.
- `combat_playtest.sh`: a NEW leg, "LAB_LOOKS" (the shell's NEW `GRANT_STAFF`): the swings wore the crescent, our
  parries flashed, a staff's Fireball showed its charge, rode as the lab's missile and burst in the blast on the
  dummy, Blink's jump showed its columns (after the cast). Runs: the first **125/1** (Blink: the server blinked us,
  this client never moved), the second broke all over (71/53: the REFEREE STOPPED itself mid-run, "the project changed
  since it started", while another session wrote its files into the project), the third, nothing else writing,
  **126/0**. Between them a probe client (deleted) blinked from the playtest's spot, alone and after a Fireball, and
  saw its move and its blink every time. It also showed the first runs' blink check was passing on a false blink: the
  playtest's own teleport (6-8 m) had been shown as one; since then your own character's jump is a Blink only just
  after you cast it, and the check reads the blink played after the cast.
- Unit whole run **4402/0** (with the wardrobe in the tree), the lints, no unexpected engine errors, nothing left over.

**Left for later (Luke's to decide)**
- Others' Gale (and any instant spell): a server row or event so every client can show it.
- A lighter version of others' effects for 300 players (fewer particles, no lights); the rings' rising meshes as one
  MultiMesh; the game camera listening to the effects' `shook`.

## Step 83: OTHER PLAYERS SEE YOUR GALE (2026-11-15)

Luke, asked "Should other players see your Gale too? It needs a small server event": **"Yes, add it"**.

**Built**
- SERVER (`server/src/game/regents.rs`): a NEW public table `spell_landed` (add-only, rule 17: one `--codegen`
  publish, no wipe): `entity_id` (the caster, PK), `world_id`, `chunk`, `ability`, `from` (where they stood), `aim`, `at`.
  One row a caster, written as EACH of their spells lands (`land_spell` → `tell_landed`), so only a cast the server
  accepted and paid for is told. An EVENT: it stays in the cell it landed in (not in `follow_place`), and goes when
  the player leaves (`on_player_left`). Ring interest: in `genre.tres` (`tables`, `world_tables`, `cell_tables`) and
  the net config's `cell_tables` (not `follow_tables`: an event).
- CLIENT (`game/regents/vfx/ability_vfx.gd`): `AbilityVfx` is sent each fighter's row (`required_tables` and
  `optional_tables`: none until they cast) and shows ANOTHER player's landing as their own client did
  (`landed_elsewhere` → `_land`, the same as `cast_landing`): their spell's `on_land` (Gale's gust) where the server
  says they stood, the way they aimed. Not ours (shown as we cast it), not a row older than `FRESH_MS` (1.5 s, by the
  server's clock: a row handed over as we come near is history), not the same landing twice (its stamp), nothing for
  a spell with a cast time (its `casting` row and missile already show it). Blink still shows from the jump (no
  `on_land`), so nothing doubles.
- What it costs: one row update a cast, sent only to the clients whose ring has that cell.

**How to play it**: two instances from the editor, both near each other, one with a staff that has Gale picked:
cast it, and the other window sees the gust at the caster's feet, aimed their way.

**Tested**
- Unit `regents_vfx` **173/0** (7 NEW): the component asks for `spell_landed` (optional); another player's Gale from
  its row, where they stood, the way they aimed; their next one (a new stamp) again. NEGATIVE: our own row plays
  nothing more; a row 2 s old plays nothing; their Fireball's landing plays nothing; the same row rewritten (same
  stamp) plays once. Mutations: the freshness check taken out fails 5 checks, the same-stamp guard 2 (restored).
- NEW `game/regents/tests/spells_seen_playtest.sh` (two real clients at 150 ms, no referee, ~2 min): **caster 8/0,
  watcher 10/0, the server 2/2**, run twice. The caster picks Gale on a staff, casts it ALONE; the watcher comes in
  after: that row reaches it 13.5 s old and shows NOTHING; the caster casts again: the watcher sees the gust at the
  caster's feet (to the centimeter where the row says they stood), facing south as aimed, once; a third Gale sent
  straight at the server while it cools is refused ("not ready") and shows nothing anywhere; the caster's own client
  showed each of its two Gales once (not again from the row); the row said Gale while they played and was gone
  after they left.
- `cargo check` (wasm) and `cargo test`: green. Unit whole run **4412/0**, the lints, no unexpected engine errors.
- Published to `regents-rule` with `--codegen` (63 tables).
- Not run: the integration suite (~80 min; the new playtest covers the reducer, its refusal, the row and its cleanup
  through real clients). Both playtests' clients warn "binding after 2.0s without rows for session_member" for ten
  entities: the same with this change taken out (an A/B probe), so not this step's; for a later look.

**Their arms too** (Luke, same day, asked "Should other players also see the caster's arms move for Gale?": **"Yes,
add the pose"**). Client only, no publish.
- `CombatComponent` is sent the same row (`TABLE_LANDED`, optional) and plays another player's landing on their arms
  (`landed_elsewhere`): `play_upper("ability.<id>")`, the clip their own client plays as it lands (`cast` for an
  instant spell, `_tick_cast` at a cast's end). So others now see Gale's push, Blink's, the Bolt's, and the release at
  the end of a Fireball or a Frost Ring (before, they saw the cast pose held, then nothing). The same gates as the
  effect: not ours, the same stamp once, fresh only (`AbilityVfx.is_fresh`, now the one test for every reader).
- Unit `regents_vfx` **179/0** (6 NEW, with a stand-in driver that records what it is asked to play): the row asked
  for; another player's Gale plays `ability.40016`, their Frost Ring's landing its own; NEGATIVE: ours, a stale row,
  the same stamp twice. Mutations: the freshness gate out fails 4, the same-stamp guard 2 (restored).
- `spells_seen_playtest.sh` again: caster 8/0, **watcher 12/0** (2 NEW: on the watcher's screen the caster's arms
  played `Spell_Double_Shoot`, the clip their own client plays for Gale; NEGATIVE: the stale and the refused Gale moved
  no arm), the server 2/2. Unit whole run **4418/0**, lints and engine errors ok.
- Not run for it: `combat_playtest.sh` and `caster_playtest.sh` (the change is another player's arms only; neither has
  a second player).

**Left for later**
- Others' AIM after a spell lands (their upper body turning to the shot for a moment, as ours does for
  `aim_after_shot_ms`): it reads only their `casting` row today.
- From step 82: a lighter version of others' effects for 300 players; the rings' rising meshes as one MultiMesh;
  the game camera listening to `shook`.

## Step 84: THE LOGIN SCREEN AND THE SHOWCASE (pictures and films for the composers) (2026-11-15)

Luke: "I am starting to commission some people for music sound tracks. I think I want to send them some cinematic and
or still images/videos to get a feel for the game. First off, a login screen is a classic must have. lets start there
and build a few labs that can really showcase the visuals with the nice skybox/assets and terrain and then a few still
or short videos of combat etc". A parallel session (step 83) worked beside this one; none of its files were touched.

**What was built** (all client-only, all genre files: no publish; everything made in code or from the CC0 kits: no
image, no AI-made asset, `GAME.md` "No AI disclosure"):
- `game/regents/showcase/`: THE VALLEY (`ShowcaseWorld`), made from a seed: a meadow camp round a fire at the origin,
  forested hills, a lake (`showcase_water.gdshader`), the regent's keep on its hill (stone blocks, cones, lit windows,
  gate torches), snowy ridges far off, painted by height and slope (`showcase_ground.gdshader`), the nature kit's trees,
  rocks, bushes, grass, ferns and flowers as MultiMeshes, the camp's props, its fire (flames, embers, a breathing
  light), fireflies and sunlit dust. THE SKY (`showcase_sky.gdshader`): the gradient, the sun's glow, the sun and the
  moon, drifting clouds lit from the sun's side, twinkling stars; there was no skybox before (every level used
  Godot's procedural one). FIVE MOODS (`ShowcaseMood`, `moods/*.tres`: dawn, day, golden hour, dusk, night) set the
  sun, the moon, the sky, the clouds, the fog, the valley mist, the fire, the fireflies and the windows: data in the
  Inspector. The forest's colors are the showcase's own (`LEAF_LOOKS`): the kit draws TallThick blue and TwistedTree
  red; here 88 % are green (the kit's own green leaf pictures), 12 % keep the kit's color as autumn. The glade is
  untouched. Trees and rocks step out of every shot's line of sight and out of the "clearings" a lab names, so a new
  shot never starts inside a trunk. Everything stands on the land AS DRAWN (`ground_at`, the mesh's own triangles):
  set on the smooth shape, grass and a deer floated over the lake's steep bowl where the grid is wide. And a shot's
  camera never goes under the land (`CAMERA_ABOVE_M`): the lake shot's did, and looked out through a hillside's back.
- `ShowcaseActor`: a character that acts with no server (the login ships it, so not the workbench's `Mannequin`): a
  look, a weapon or a foe's dress, the game's clips by their semantic names with a crossfade, one-shots, held deaths,
  walks on the ground.
- `ShowcaseStage` + `ShowcaseShot`: a lab plays its scene's `shots` (camera from/to, orbit, lens, focus, a handheld
  drift, slow motion, a mood, a beat) with fades and film bars; F the free camera and C prints a place for a new shot;
  `-- stills <dir>`, `-- reel`, `-- clip <n>` for the renders. Effects through the game's own `VfxEffect` scenes.
- THE VISTA LAB (`vista_lab.tscn`, 9 shots): the valley at golden hour, the keep at dusk, the lake at dawn with deer,
  the camp at dusk (orbit), the smith, a traveler arriving, the wizard's cold light at night, the night watch, over the
  forest by day.
- THE BATTLE LAB (`battle_lab.tscn`, 7 shots), timelines of the game's own swings and effects: "Steel" (the sword's
  string with its crescents, a skeleton's cut parried with the flash, the finisher, an axeman charging in, a roll, a
  lunge, a second kill), "The finisher" at a quarter speed, "Fire and frost" twice (Fireball, the imp's cinder ring left
  by a Blink, Frost Ring, the last fireball), "Arrows" (the skeleton archer's arrow rolled clear, two answered), "The
  pack" (two wolves at night: a lunge rolled, a bite parried), "The line" (a wide crane over both fights).
- THE LOGIN SCREEN (`game/regents/ui/login/regents_login.tscn`, `RegentsLogin extends ConnectScreen`, an inherited
  scene of the foundation's): the form, signing in, the character and settings are the foundation's, unchanged; behind
  them the valley at dusk, live (`LoginBackdrop` in a SubViewport with its own world: the fire, a guard looking out to
  the keep, the smith, the ranger and the wizard, the camera drifting over 70 s), "REGENT'S RULE" in a serif the system
  has (`SystemFont`: Cinzel, Palatino Linotype, Book Antiqua, Georgia...; no font file shipped), the form lower down in
  a dark panel with a gold edge. Built when the screen shows, freed when it hides: play pays nothing. `regents_game.tscn`
  Boot's `connect_screen` now names it (one line). Its looks are its exported values.
- `game/regents/tests/showcase_render.sh [stills|films|all]`: everything at 1920x1080 into `export/showcase/<date>/`
  (git-ignored): `stills/` (login, vista_NN, battle_NN), `films/` (login 40 s, one .ogv a shot, 30 fps), `index.txt`
  (each file, its mood). Godot's movie writer records Theora `.ogv` (VLC, Chrome, Firefox play it; Windows' own player
  does not) at the PROJECT's window size whatever `--resolution` says, so the script writes a 1920x1080 `override.cfg`
  for the run and removes it after (it refuses to start if one exists). `login_shot.tscn` shoots the front door.

**How to look at it**: F6 on `game/regents/showcase/vista_lab.tscn` or `battle_lab.tscn` (←/→ shots, M moods, F the free
camera, P a still); press Play for the login screen (untick "Connect automatically" if it skips it). The renders:
`tools\run.cmd game\regents\tests\showcase_render.sh`.

**Tested**: `regents_showcase` (NEW) 104/0: the moods; the valley's shape (the camp flat, the keep's hill,
the ridges, the lake's bed), the ground as drawn (NEGATIVE: not the smooth shape on the bowl), trees and grass placed, never in the lake, the keep's yard, a line of sight or (tall) a
clearing; a mood relights it (night: moon and fireflies, no sun); the actor (its look and sword, a one-shot then idle,
NEGATIVE an unknown clip refused, a held death, a walk ending on the ground); a shot's camera, lens and orbit, and lifted over the land when set under it; every
lab shot's beat a method of its lab, and every battle beat played to its end on the stage's clock with its foes down
and the timeline empty, NEGATIVE a new shot starts clean; the login: the foundation's form kept, nothing built while
hidden, the valley built in its own world when shown, freed and its view stopped when hidden, NEGATIVE nothing built
with the picture off; the game's Boot names it. Mutations: a login that never frees its valley and a swing that
never kills both fail it (3 fails), restored. The look: the labs' stills, looked at shot by shot over five passes.
Unit whole run 4522/0, lints and engine-error checks ok (2026-11-15). The renders: `showcase_render.sh all`, 17 stills and 17 films, every still looked at.

**Choices of mine, Luke's to change** (none is a game rule): the forest's colors (`LEAF_LOOKS`, `KIT_LEAVES`), the five
moods' numbers, the keep's look (stone blocks; a real castle kit would be better), the login's dusk, its tagline ("The
frontier waits"), its title face, the shots and their beats. The valley is not the game's world: no server, no
collision; the continent (AI-derived) is not used anywhere in it.

**Left for later**: MP4 (needs ffmpeg on this machine, a download: Luke's yes); music-free cuts longer than a shot (the
`reel` mode plays every shot back to back into one film); the vista's "The keep" at dusk is still hazy; "The line" is
wide and its fighters small; deer only stand (their set has no grazing clip); a skybox in the game's own levels (the
glade, the continent) from `showcase_sky.gdshader` if Luke likes it (the glade's look is his, #12 day/night open).

## Step 85: TOWNS: THE TOWN DYE, THE TOWN WORLD AND THE TOWN LAB (2026-11-15)

Luke, 2026-11-15: "start making the world feel more alive in parallel with the actual content work ... similar to
clothes, each asset should have a shader with external parameters that allow for nearly infinite customization so
things dont look too similar from village to village"; then "a small 3d scene (say 1km x 1km) that packs in a small
village, middle market town and a castle with code made walls and reusing the walls. and then another wardrobe like
lab that shows some preset village sets for colors". A parallel session; presentation only, no server, nothing in the
game's levels yet. Committed `ddbb2850`.

**The full write-up is `docs/regents_rule/SETTLEMENTS_PREP.md`**: §1-5 the kits (Medieval Village MegaKit, Fantasy
Props), the shader plan, the routes to a castle or a capital; §6 the order of work; §7 Luke's open S1-S8; **§8 what is
built, how to look at it, how it is tested, what is left.** In short:
- `game/regents/art/village/`: the kit's 305 pieces (CC0, its glTF Godot export, collisions included), textures, wear
  masks; `ATTRIBUTION.md`.
- `game/regents/town/`: `town_surface.gdshader` (THE TOWN DYE: each kit material a slot, the wardrobe's idea, plus
  each building's nudge and the weather: wear, moss, grime, sun-fade, snow, lit windows at night); `SettlementStyle`
  (a `.tres`, eight presets in `styles/`); `TownKit` (dress, merge each building to one mesh and one body);
  `KitHouse` (a house from the kit's pieces by footprint, floors, finishes); `CastleWall` (walls, towers, gates and
  keeps in code, round any outline); `Settlement` (dresses and merges every building under it as the game runs);
  `houses/demo_*.tscn` (the kit's own demo buildings, rebuilt by `game/regents/tools/town_kit.py demo`).

**How to look at it** (F6, no server): `game/regents/town/town_world.tscn` (the 1 km world: the village, the walled
market town, the castle on its mound; 1-7 views, right mouse and WASD QE to fly, L day/dusk/night, S every place to
the next style, H help) and `game/regents/town/town_lab.tscn` (one street in all eight styles; 2 the live editor,
3 seeds, 4 one house per style). The world takes ~17 s to build.

**Tested**: `regents_town` (NEW) 39/0 (NEGATIVES: a kit material taken out of the table fails three checks; a wall
with no gate is solid where the gate was); unit whole run 4043/0 at the time (before steps 78-84 joined it). The look:
windowed shots of both scenes, day, dusk and night.

**Left for later** (SETTLEMENTS_PREP §8): FURNISHING with the Fantasy Props kit once Luke okays the look ("once i
okay the test Ill want to see how eveything furnishes"); a saved bake of merged buildings and far LODs; the village
kit's own small props; interiors (S7); the ground is a stand-in.

**Then, Luke's first look (2026-11-15)**: "The castle walls and everything looks really good, we need to workshop
the roofs"; streets distinct from walls ("a unique color mix for roads"); the Houses view "not quite right"; then
furnish. Built (all in `SETTLEMENTS_PREP.md` §9): the kit's two 6x4 roofs start at their origin, so `KitHouse`
centers every roof on its measured bounds (the Houses view's 2 x 3 house); `CastleWall` roof styles (CONE with a
flare, STEPPED courses, the KIT's own, a TURRET, OPEN; slate, pitch, overhang, a finial), a roofed tower solid to its
eaves, the lab's view 5 Roofs to compare them; code-made paving (cobbles or setts, `town_paving.gdshaderinc`) in each
style's own `paving`, `paving_mix` and `paving_pattern`, every preset's kept apart from its walls; the FANTASY PROPS
KIT in (`game/regents/art/props/`, CC0), its cloth in a new style slot CLOTH, `PropGroup` (props as one building),
`TownFurnish` (the market, doors, the green, the inn, the castle yard, banners, gate torches). `regents_town` 66/0
(negatives: the roofs' centering, battlements under a roof, a prop material unknown); the whole unit run below.
How to look: F6 on `town_world.tscn` (8 the market's stalls, 9 the inn, 0 the castle yard) and `town_lab.tscn`
(5 Roofs, 6 Places: every preset's green, inn front and castle corner, Luke asked for it). Waiting on Luke: which
roof for which place, and his look at the furnishing. Then merged into main and pushed (Luke's say-so).

## Step 86: THE SHOWCASE, LUKE'S NOTES ON THE FILMS (2026-11-15)

Luke, on the first films: "the movement is unnatural and jumpy. It looks like instead of using the movement we have
in game you manually are setting position. The attack animations also look like they are using IK and moving the
characters when playing"; "the login .ogv should not have the connect play ui, just a Play button that matches the
title font. we can get rid of the subtitle ... and the imp doesnt seem to be using any casting animations"; "the castle
is also floating".

**What was wrong, measured**: the first `ShowcaseActor` slid its body at a set speed (no getting going, no braking,
its legs one clip whatever the speed) and played raw clips on a two-clip crossfade. The adventurer's set takes the
swings' root travel out (`root_motion_bone = root`); the showcase's tree never did, so a Lunge carried the body 2.2 m
and snapped it back (the suite measures it). The imp's cast is TWO clips in the game, its tell (`ability.40032`, the
spell idle for its 1 s wind-up) then its release (`recover.40032`, cross-faded in by `CombatComponent._plan_recovery`);
the lab played only the tell, which looks like standing. The keep's walls stood on the round top of a hill that falls
4 m from its middle to its walls.

**Built**:
- `ShowcaseActor` is now a `SpaceTimeEntity` built in code from the game's own parts, never bound to a row:
  `ShowcaseMovement` (NEW, a `SpaceTimeMovementComponent` that steps the game's `MovementModel` with the character's
  movement config at the game's tick, drawn between ticks, standing on the showcase's land) and the game's
  `AnimationDriverComponent` on the generated tree (the speed blend, the model easing round, the root travel out, two
  action slots, the hit, the fall, held poses on the body or the arms). It is told as a player's keys would tell it:
  `walk_to` steers (walk, run or sprint by the speed asked; it brakes to stop there), `roll` is the dodge's dash and
  clip (`RollComponent`'s way), `act` shows a swing as `CombatComponent._began` does (held to its hit, then its
  recovery), a ranged player's shot or cast's release on the arms (`play_upper`), a foe's every move on the whole
  body. A hit, a fall, a getting up go through an unbound `SpaceTimeHealthComponent`'s signals, as the game's do. The
  driver's commit and face-motion timers run on the wall clock; the actor refreshes them on the stage's clock so a
  slowed shot or a film rendered slower than real time keeps them. A body moved from outside (a Blink carries its
  caster) is put there.
- The battle lab: the game's roll goes its own way (~5 m), so the hero closes again with the Lunge (`lunge`); the fire
  beat begins with the imp's ember (its tell with a glint in its hand, the release, the slow bolt; the mage steps
  aside), then its ring later; the fire shot reframed side-on; shots lengthened (Steel 12.5, Fire 11.5, Pack 10, The
  line 13.5 s). The vista: the deer walk a few steps and stop on the bank (at their real walk they waded in).
- The keep: a flat hilltop out to `keep_flat_m` (24 m, an export) falling to the hill over 16 m, and every wall,
  tower and the hall going 3 m on into the ground (`KEEP_FOOTING_M`).
- The login: no tagline (`tagline` empty: none); a TITLE CARD (`title_card`, off in the game): the name and one PLAY
  button in the title's letters, the form when it is pressed. `login_shot.tscn` shows the card (`form` as a third
  argument shows the form), so the composers' still and film have no form.

**Tested**: `regents_showcase` 120/0. New: the game's driver poses it; its swings' root travel is out and the body
stays put through a swing (NEGATIVE: with the root travel left in, a Lunge carries it 2 m+); the recovery follows the
strike; a player's spell on the arms; the imp's 1 s tell then its release; the walk at the config's speed, getting
going then stopping on the ground, its legs' blend following; a body moved from outside stays; the keep stands in the
ground all round (NEGATIVE: with no flat top its walls hang over 1 m above the slope); the title card shows only Play
in the title's font, Play opens the form (NEGATIVE: once played, a lost connection shows the form). The look: PNG
frame strips (10 fps) of Steel, Fire and frost, The pack, A traveler arrives and The lake at dawn, looked at.

**Then Luke: "card first"**: the GAME's login opens on the title card too (`title_card` on by default; Play opens the
form); connecting by itself (auto-connect, a `--host` launch) puts the form up so its status is seen. `regents_showcase`
124/0 (new: the card by default, connecting puts the form up, NEGATIVE: the card off shows the form at once; a
mutation taking the step-aside out fails its check).

**Left for later**: the deer still have no graze clip.

## Step 87: NPCS BIND AT ONCE (the "binding after 2.0s without rows for session_member" warnings) (2026-11-16, the armor run's E2)

**The cause**: `foundation/core/spacetime_entity.gd`'s bind timeout. The foundation's `SessionComponent` REQUIRES a
`session_member` row (only `lobby_member` is optional). The foes (`combat/foe.tscn`) and the guide are built on
`foundation/entities/player.tscn`, so they carry that component, but the server gives a member row only to a player
joining a world's session. The ten warnings: the guide and the camp's nine foes. NOT ONLY NOISE: each stayed unbound,
frozen at its first rows, ~2.9 s after coming into a client's ring, on every ring change.

**Built**: `game/regents/npc_session_component.gd` (extends SessionComponent, both tables optional);
`combat/foe.tscn`'s inherited `Components/Session` takes it; NEW `game/regents/npc.tscn` (player.tscn with the same
override), used by `content/character/guide.tres` (re-baked: the manifest's hash only); NEW
`game/regents/tests/bind_playtest.sh` (+ `tests/playtest/bind_playtest.{gd,tscn}`): one real client at 150 ms in the
camp times every entity from entering the tree to `bound`, fails a stall over 1 s or any "binding after" line.

**How to play it**: walk into the frontier camp: the foes and the Drillmaster move at once, not 2-3 s later.

**Tested**: `bind_playtest.sh` WITHOUT the fix (the negative) failed: the ten bound 2936-2978 ms after spawn, ten
warnings; WITH it 3/0, the same ten in 99-117 ms. Unit whole 4610/0. No server change, no publish.

**Left for later**: the general fix is the template's (`SessionComponent.optional_tables`, DECISIONS #315, in the
release M3 ships); once pulled, `npc_session_component.gd` and the two overrides are redundant and may go.

## Step 88: OTHERS' EFFECTS AT SCALE (the lighter version, rings as one MultiMesh, the camera's shake) (2026-11-16, the armor run's E1)

**Built**:
- `game/regents/vfx/vfx_effect.gd`: THE LIGHTER VERSION. `lighter` / `make_lighter()`: the same effect at
  `LIGHTER_PARTICLES` (0.5) of each particle system's amount, its own lights out, no camera shake. Works set before
  it enters the world or called after (once). An effect not lighter connects its `shook` to the game's camera
  listener if one is there.
- `game/regents/vfx/ability_vfx.gd`: who gets it. `AbilityVfx.lighter_for(who)`: another PLAYER's effect, seen by
  this client. Not your own, not a foe's or creature's (a foe's warning must read at a glance), not one with no
  fighter (the lab, the showcase). `lighter_for_shot(look)` does the same for a missile's end, by its body's owner.
  `play` sets it on every charge, landing, Blink and parry; the local player's `AbilityVfx` installs the camera listener.
  (These live on `AbilityVfx`, not `VfxEffect`: naming `CombatComponent` from `VfxEffect` makes a load cycle through
  SpellLooks' ring scenes.)
- NEW `game/regents/vfx/vfx_camera_shake.gd` (`VfxCameraShake`): THE CAMERA LISTENING TO `shook`. A child of this
  client's camera. It shakes as hard as an effect asks within 6 m of your character, fading to nothing by 20 m, and
  never for a lighter effect. It moves only the picture (`h_offset`/`v_offset`, 0.25 m at strength 1), never the rig
  or the aim. The lab and the showcase keep their own shakes (no listener there).
- `game/regents/vfx/effects/ground_ring.gd` + `vfx/shaders/vfx_energy.gdshaderinc`: A RING'S PIECES ARE ONE
  MULTIMESH (one draw for all 30 shards or flames, instead of 30). Each instance is a unit spike stretched to its size.
  The energy shader's new `instanced` mode reads each piece's erosion, heat and true size from its custom data. Its
  normal is undone from the stretch, and its push (`displace`) is made as on a piece that size, so it looks as the
  separate pieces did (shots below). The layout is the same throw of the same seed. `risen_count()` is for the suites.
- `game/regents/combat/spell_looks.gd`, `combat/shot_look.gd` (the master's yes): one line each. Another player's
  ring and fireball blast are lighter.
- `game/regents/vfx/vfx_lab.gd`: O (or `others` on the command line) plays every showcase as another player's;
  shots then end `_others.png`. `-- cost` now measures every showcase twice, ours and "(another player's)".

**How to play it**: two instances. On the second, the first player's Frost Ring, fireball blast, Gale, Blink and charges
show with half the particles and no light; your own stay whole. Your own fireball's blast or ring landing near you
shakes your camera a little; someone else's never does. VFX lab (F6): O switches to "as another player sees it".

**Tested**:
- `vfx_lab.tscn -- cost`, BEFORE (b2e27908) -> AFTER (ours) -> AFTER (another player's): draw calls added at most /
  particles at most / GPU at most over the stage's 0.84 ms:
  Fireball +14/126/+0.67 -> +14/126/+0.47 -> +14/63/+0.23; Frost Ring +38/70/+0.54 -> +9/70/+0.34 -> +9/35/+0.25;
  Blink -13/40/+0.37 -> -21/40/+0.48 -> -7/20/+0.15; Gale +10/94/+0.34 -> +10/94/+0.29 -> +10/47/+0.15;
  Axe Heavy +14/30/+0.38 -> +14/30/+0.34 -> +14/15/+0.16; Sword String +15/30/+0.35 -> +15/30/+0.24 -> +15/15/+0.20;
  Parry +12/48/+0.32 -> +12/48/+0.22 -> +10/24/+0.13; Cinder Ring +36/112/+0.35 -> +13/112/+0.34 -> +13/56/+0.21.
  (The GPU times are this machine's and noisy at ±0.1 ms. The rings' draws are the sure win: 38 -> 9 and 36 -> 13.)
- Shots looked at (windowed, day): Frost Ring and Cinder Ring before and after match: the same shards in the same
  places, the same shading (particles differ by their own randomness). Fireball and Gale as another player's read as the
  same effect, thinner, and the fireball's glow on the ground is gone (no light).
- `regents_vfx` 212/0 (was 179; 33 new checks: one MultiMesh per ring, its drawn pieces the risen ones, others' half
  particles and no light, made lighter late, the listener near/far/lighter/put back/freed). NEGATIVES: `make_lighter`
  a no-op and no listener connected: 11 FAIL; the old `ground_ring.gd`: its two MultiMesh checks FAIL (and
  `risen_count` missing). `regents` + `regents_showcase` 1534/0.
- `spells_seen_playtest.sh` (under the lock, after `main` was merged in): caster 8/0, watcher 12/0, so another
  player's Gale is still seen, now as the lighter version. The playtest does not assert lighter-ness itself; the unit
  suite does.

**Needs on merge**: none (client only; no publish).
**Placeholders made**: none. (The numbers 0.5 of the particles, shake 6-20 m and 0.25 m are tuning, in constants at the
top of `vfx_effect.gd` / `vfx_camera_shake.gd`.)
**For Luke**: should others' effects be lighter still, or as whole as yours when few players are near (a distance or
count rule)? Today it is always half for another player.
For the rules/handbook (regents-genre.md, the AN EFFECT rule, add): "ANOTHER PLAYER'S effect is the LIGHTER
version (`VfxEffect.lighter`: half the particles, no light, no shake; `AbilityVfx.lighter_for`), yours and a foe's
whole: a new place that spawns an effect for a fighter sets it. A ring's pieces are one MultiMesh (`instanced` in
the energy shader): a new piece-heavy effect does the same. The game's camera shakes from `shook` through
`VfxCameraShake` (installed by the local player's `AbilityVfx`)."
**Left for later**: a missile's riding look (`VfxFireMissile` inside `fireball_look.tscn`) is still whole for others
(ShotLook builds it before its owner is known; `make_lighter()` can be called on it later). A "camera shake" on/off in
Settings is foundation work. Other players' swing crescents (`SwingTrail`) are untouched (one ribbon each, cheap).

## Step 89: A SWEEP THAT HITS ALL (Cleave reaches every foe in it; a rally heals once a swing) (2026-11-16, the armor run's S1)

**Branches**: TEMPLATE `claude/s1-resolve-action-all` (UMF Template worktree `.claude/worktrees/s1-resolve-action-all`),
head `9e47ea7` (two commits on `0a8681a`: `65007b7`, `9e47ea7`). REGENT'S `claude/s1-areas-hit-all-b949af`: the two
"TEMP foundation copy, dropped at merge" commits `4f3e4ac1` and `8556ce3e` (the template's files exactly; drop them and
take the real pull), the genre commit `7f7d96e3`, then `main` merged in. Nothing pushed.

**Built**:
- What already hit all, unchanged: a player's AREA spell (Frost Ring, `land_area`) and cone (Gale, `land_spell`) hurt every
  foe inside on the server; a foe's ring lands on players only, damage only. The one-body case was the referee's
  JUDGED sweep (the axe's Cleave): the referee reported its first body.
- TEMPLATE (DECISIONS #314; T1 takes the number before it, renumber at merge if needed; no version bump): an ability may be
  marked **Hits All** (`AbilityDef.hits_all`, judged only; baked only when on, and carried into the row's `data` by
  `server/build/content.rs`). The referee judges every body its sweep meets by the single hit's test
  (`LungeJudge.judge_all`; `judge` is now its first, same results) and answers with a NEW reducer
  `resolve_action_all(request_id, hit_ids)` when it met more than one. The module checks each name as `resolve_action`
  checks one (authority only), deals them in order (hurt, the genre's `on_ability_hit`, an `action_event` each), passes
  over those who cannot be hit now or rolled clear, and refuses the answer whole for an ability without Hits All, a
  duplicate, more than 32, or a name `resolve_action` refuses. `resolve_action` keeps its arguments and behaviour (its
  checks now shared). HANDBOOK paragraph, CHANGELOG block (unversioned), DECISIONS row and index lines.
- GENRE: `axe_cleave.tres` `hits_all = true` (re-baked; no number changed). A rallying last hit heals ONCE a swing
  however many it lands on: private table `rallied` (add-only) + `rules::rallies` (`regents.rs` `first_rally_of_swing`).
  Each body is otherwise judged by `hit` as before (the guard, a parry, owed effects, poise, XP per body).

**How to play it**: wield the copper axe at the frontier camp, stand beside the two training dummies on the line between them
and press Q (Cleave): both dummies lose 12.6. Before, only the nearer one did.

**Tested**:
- Template: unit `referee` 183/0 (new "a sweep that hits all": three in a line nearest first, one behind and one wide not,
  a fence hides one, the referee reports all for a hits-all sweep and the first for a plain one); `cargo test` green;
  wasm check clean. NEGATIVE (mutation): the referee cutting every sweep to its first: the suite fails ("a cleave reports
  all three ... ([41])"). Integration refusal written (`resolve_action_all` for a hits-one ability), for M9.
- Regent's: `combat_playtest.sh` 132/0 after the fix (new: Cleave through a real client and referee hits both dummies,
  12.60 each). NEGATIVE: the run before the build fix (the row lacked `hits_all`, so the referee answered with the first
  body) failed exactly there ("the second ... (0.00)"). One rerun was for the known yard flake (the player downed before
  "your chop hit a skeleton back"), green on the rerun. Native `a_sweep_that_hits_several_rallies_once`; `cargo test` green;
  unit `regents,referee,content` 1643/0 before and after `git merge main`. Integration leg written in
  `integration_genre.sh` (Cleave answered with both dummies, 12.6 each; refused: a body named twice, a chop as hitting all).
  NOT RUN: integration (M9). After `git merge main` (step 87): combat playtest 130/0, Cleave on both dummies again.
  DECISIONS: E2 took #315 on main, so #314 may collide with T1: renumber at the template merge.
- Bindings regenerated against the TEST database (codegen pointed at `regents-rule-test`; `plugin_config.tres` restored).

**Needs on merge**: the template release (M3) first; then drop the two TEMP commits, re-bake, `publish.sh --codegen`
(a new reducer and a new table: add-only).
**Placeholders made**: none.
**For Luke**: which other abilities should hit all (the sword's pools, the ults) is his content call; only Cleave is marked.
**For the rules/handbook**: regents-genre.md: "A player's judged sweep marked Hits All (Cleave) lands on every foe in it, each
judged as a single hit; a rallying hit heals once a swing (`rallied`)." HANDBOOK: the template's paragraph comes with the pull.
**Left for later**: a foe's sweep may be marked Hits All too (content); the client shows each body's hit from its own event.

## Step 90: TOWNS, THE ENGINEERING HALF (the piece cache: the world in 4 s; the village's props) (2026-11-16, the armor run's E3)

**Built**:
- `game/regents/town/town_kit.gd`: `TownKit.piece` / `has_piece` keep each kit scene once found, by name. Asking the
  resource loader for a piece cost ~2 ms (`exists` + `load`, even with the scene cached; measured), and a house places
  ~80 pieces. A house now builds in 5.5 ms instead of 148 ms. THE TOWN WORLD, back to back on the same machine
  (headless, props in both): 24.1 s before, 4.0 s after (HANDOFF's "~17 s" was the before on a quieter machine).
  After, by phase: village 0.5 s, town 2.9 s, castle 0.2 s, ground 0.4 s. The look is unchanged: only the lookup changed.
- THE SAVED BAKE, MEASURED AND NOT BUILT (agreed with the master): one merged house saves to 0.53 MB (compressed, 32k
  vertices) and loads in 6.5 ms, against ~14 ms to build and merge it. For the world's ~150 houses that is ~80 MB of
  binaries in git, re-made on every kit change, to save about 1 s.
- NEW `game/regents/town/village_dressing.gd` (`VillageDressing`, a `.tres`): the village kit's small props about a
  house, each a share a designer edits: `vine_share` (the flat vines `Prop_Vine1-4` hung on the ground floor's back
  and side wall cells, on the wall's face, never the front), `fence_share` (a yard behind the house fenced in the
  kit's 2 m panels, `yard_depth` deep; `metal_fence_share` of them metal), `crate_share` (crates stacked by one side
  wall), `wagon_share` (the kit's wagon along the other side). Placed as one `PropGroup` "Village" under the house,
  so it is dressed and merged with it, and its collisions are one body (the wagon alone brings eleven).
- `settlement.gd`: `@export var dressing: VillageDressing`. Null (the default) places nothing: the look before.
  With one, every `KitHouse` is dressed from its own seed (`props_rng`, from `seed_of`): the same house, the same props.
- NEW `game/regents/town/dressing/village.tres`: the preset (vines 0.25, fences 0.4, crates 0.35, wagon 0.12),
  `placeholder = true`. `town_world.gd`: the village wears it (`VILLAGE_DRESSING`); the town and the castle none.
**How to play it**: F6 on `game/regents/town/town_world.tscn`. It is up in about 4 s now. Press 2 (the village) or 3 (its
lane) to see the fenced yards behind the cottages, vines on their sides, crates and a wagon or two. To dress another
place, set a `Settlement`'s `dressing` in the Inspector or edit `dressing/village.tres`.
**Tested**: `regents_town` 77/0 (was 68), also after `git merge main`. New: no dressing, no props; with every share 1,
every house gets vines, a yard, crates and the wagon; the vines on a back or side wall's face, never the front; the
fence, crates and wagon clear of the house; two bodies a house (its own and the props', the wagon's in it); one mesh;
the same seed the same props; the preset loads, a placeholder; the world's village dressed, its town and castle not.
NEGATIVE: with the wagon set inside the house and the back vines set behind the wall's face, the vine check and the
clear-of-the-house check fail (75/2); restored. Windowed shots, before and after, both scenes (52 each), looked at:
the village shows its yards, vines and crates and the rest is the same; the lab is unchanged (byte-identical presets).
**Needs on merge**: none (client only; no publish).
**Placeholders made**: `game/regents/town/dressing/village.tres` (`placeholder = true`): how many of the village's houses
get vines, a fenced yard, crates, a wagon, and how deep the yard is. These are Luke's to set; the town world's village wears it.
**For Luke**:
- The village props: how much of each (`dressing/village.tres`), and which places wear them (only the village now).
- LODs and impostors: `docs/rules/version_settings_looks.md` forbids LODs only on WORN pieces (#177), not on
  buildings. They are allowed on buildings, but none are built.
- A saved bake of merged buildings was measured and not built (numbers above); the cache did the job.
**For the rules/handbook**:
- regents-genre.md (towns): "A kit piece is found through `TownKit.piece` (cached by name): never `load` a kit path
  per piece; the loader's lookup costs ~2 ms each. A place's small village props are its `Settlement`'s `dressing`
  (`VillageDressing`), never placed by hand round a house."
**Left for later**: the deep corner vines (`Prop_Vine5-9`) and the exterior stairs, borders and supports are not used;
the yard can meet a neighbor's in a tight row (the town's rows would need gaps checked before wearing a dressing);
LODs or impostors for the farthest buildings, if wanted.

## Step 91: EVERY WEAPON'S POOLS, AS PLACEHOLDERS (one pool a weapon kind; the staff's ult; the Bolt at 12) (2026-11-16, the armor run's P1)

Built (content, plus one validation line and tests; no server code, no schema change):
- ONE PLACEHOLDER POOL PER WEAPON KIND. Per-ROLE pools (each handle its own Q and options, Luke's "SEPARATE POOLS PER
  ROLE") need server code (`KitSeed` per-role skills/slots, the gates reading the wielded item's role, `build/regents.rs`,
  the twin `item_level.gd`): Lane S's, queued by the master as S1b. Until then every handle of a kind shares its pool.
  - Sword (`content/kit/sword.tres`): Q Lunge; E Flurry, Hamstring Cut (slows 3 s), Shield Bash (shoves back 8 m/s);
    R Execute.
  - Axe (`kit/axe.tres`): Q Cleave (untouched: S1 sets its `hits_all`); E Hamstring Chop (slows 3 s), Skull Splitter,
    Shoulder Shove (shoves 10 m/s); R Whirlwind.
  - Bow (`kit/bow.tres`, had no skills): Q Point-Blank Shot; E Pinning Shot (slows 3 s), Kick Away (shoves 10 m/s), Quick
    Shot; R Arrow Volley. Bow skills are judged sweeps straight ahead (8-18 m), so they take no arrow.
  - Staff (`kit/staff.tres`): its first ult, R Meteor (an AREA spell: 2 s cast standing, 50 mana, a 10 m circle 1.5 s
    later for 40, 60 s cooldown; `content/spell/staff_meteor.tres`, spell 40009).
  - New abilities 40035-40048 (`content/ability/sword_*`, `axe_*`, `bow_*`, `staff_meteor.tres`), every one named
    "... (placeholder)" and marked PLACEHOLDER in `designer_notes`. Slows and shoves are `KitHit` rows on the kits (the
    wolf's mechanic). Clips and recoveries reuse existing ones (`anim/adventurer.tres`: the sword's lights and heavies,
    the hook, the kick, the bow's loose, the double cast). Drawn: swings by `SwingTrail`; Meteor's ring by `SpellLooks`
    and its charge by a new row in `vfx/ability_vfx.tres` (fire charge, both hands).
- THE STAFF'S BOLT (B14): damage 9 -> 12 (`content/ability/staff_bolt.tres`), benched from the bake: ~20 a second at its
  0.6 s pace, beside the bow's full draws (~22/s, arrows paid), the axe's string (~23/s) and the sword's (~21-28/s by
  handle); was ~15. Free, as before. Its projectile look (flight, trail, impact) is step 82's; a CAST FLASH at the hand
  is not added: an instant spell's `on_land` plays at the feet, so a flash needs `AbilityVfx` code (E1's `vfx/`).
- `content/kit_def.gd`: "four skills at most" only for a kit with no `skill_slots` (a foe's); a pooled kit holds more.
- ULTS CHANGE R (step 76): with an ult, a kit's last pick takes only its ult. Step 76's rule ("R takes the option E did
  not") stays in the code for a kit with none, and stays tested on a staff copy without its ult.
**How to play it**: wield a sword, axe or bow: Q from level 1; at level 5 open the weapon's abilities (click it on the bar
  with the bag open, or Abilities in the bag) and pick E from three; at 20 R offers the ult. A staff at 20: R offers
  Meteor (hold still 2 s, then the ring lands). `admin_set_item_level` jumps a weapon's level for a look.
**Tested**:
- Unit `regents,regents_bar,regents_vfx` 1732/0. Updated deliberately: the sword's one-skill and empty-slot checks
  (now E and R locked on a new sword), the staff's layout and spells list, step 76's R checks moved to a no-ult staff
  copy; NEW: Meteor at R from 20 (NEGATIVES at 19, Gale/Frost Ring no last pick, Meteor no first pick, a staff that had
  Gale on R no longer fires it), every kind has one Q, options and one ult named (placeholder), the sword's pool at 33
  and NEGATIVE nothing at 4, the abilities window offering Meteor (NEGATIVE not Gale/Frost Ring). NEGATIVE of the whole:
  with `staff.tres`/`bow.tres` as on `main` the bar suite fails 3 and aborts (Meteor missing).
- `cargo test` all green (`--test regents` 58/0: the same cases in Rust, step 76's on a `KitSeed` copy without the ult,
  every kind's pool), wasm check clean.
- Whole `run_tests.sh`: **4651 passed, 0 failed**, the bake current, no engine errors (after merging `main` e5c07a05).
- NOT run: integration (the master's M9) and the playtests. Integration hook changes, written and syntax-checked only:
  the staff's R leg now picks Meteor (NEGATIVES: Gale, Frost Ring, Fireball refused at R); Meteor shut on R below 20,
  Gale "not chosen"; NEW in the bow leg: the bow's Q, an option and the ult published, NEGATIVES the unpicked option
  and ult refused, a sword option with a bow refused. A BOW SKILL PRESSED BY A REAL CLIENT (a swing on a drawing kit)
  has never run: worth one look in play or in `combat_playtest.sh` (not changed).
**Needs on merge**: re-bake (`shared/content/**` is in the branch, baked); no codegen (no table or reducer); publish the
  play database (content changed).
Placeholders made (Luke fills in names, numbers and what each really does):
- Sword E Flurry, Hamstring Cut, Shield Bash; R Execute: `game/regents/content/ability/sword_{flurry,hamstring_cut,shield_bash,execute}.tres`, the slows/shoves in `content/kit/sword.tres` `hits`.
- Axe E Hamstring Chop, Skull Splitter, Shoulder Shove; R Whirlwind: `content/ability/axe_{hamstring_chop,skull_splitter,shoulder_shove,whirlwind}.tres`, `kit/axe.tres` `hits`.
- Bow Q Point-Blank Shot; E Pinning Shot, Kick Away, Quick Shot; R Arrow Volley: `content/ability/bow_*.tres`, `kit/bow.tres` `hits`.
- Staff R Meteor: `content/ability/staff_meteor.tres`, `content/spell/staff_meteor.tres`.
- The Bolt's 12: `content/ability/staff_bolt.tres` (his feel check).
**For Luke**:
- Per-role pools wait on server work (S1b); until then each weapon kind has one pool shared by its handles.
- The staff's ult changes R: a staff that took Gale or Frost Ring on R before keeps it on the item but it no longer
  fires; he changes the pick to Meteor (free once a week from level 20). His own level-33 staff is one.
- The second pick (~12) still has nothing to take once E holds an option: upgrades are not built (B6).
- The drafts' real effects (Execute by missing health, a fan or volley of arrows, a whirlwind you walk in, Riposte
  Stance, War Cry, Last Stand, heals by share) need new mechanics: his rewrite of §9 first.
**For the rules/handbook**: regents-genre.md, under A PLAYER'S ABILITIES OPEN ON THE ITEM: "A weapon kit's skills are a
  POOL (`skill_slots`: one base, options, ults; more than four allowed); with an ult the last pick takes only the ult.
  Every placeholder ability is named `... (placeholder)` and says PLACEHOLDER in its `designer_notes`."
**Left for later**:
- S1b: per-role pools (each handle its own base Q and options), then split these placeholders by handle.
- Whirlwind and Arrow Volley (and the Point-Blank Shot's fan) should reach every body in their sweep: set S1's
  `hits_all` on 40042, 40047 (and 40043) after S1 merges.
- The bar's words for an ability's slow or shove (`RegentsAbilityBar.ability_words` says only damage and reach; the
  `ui/` token's).
- The Bolt's cast flash (`AbilityVfx`, E1's lane); Meteor's ring is the frost ring (a fire landing ring for players' areas is `SpellLooks`, E1's).
- Ability ids 40035-40048 and spell 40009 are taken: S4's chest abilities start at 40049.

**At the merge (the master)**: Whirlwind (40042) and Arrow Volley (40047) marked `hits_all` (step 89's flag), re-baked.
Unit, `cargo test` and the wasm check on `main`: see HANDOFF.

## Step 92: THE ARMOR CORE (the worn table, wear and take off, Defense in the hit) (2026-11-16, the armor run's S2)

Branch `claude/s2-armor-core` (from `main` e8d69c3f, `main` 13408b0e merged in). Not pushed.

**Built**:
- `server/src/game/regents.rs`: NEW public cell table `worn` (add-only): ONE ROW A WEARER, `entity_id` its key (hard rule 9),
  `world_id`, indexed `chunk` (moved in `follow_place`), and per slot the bag row worn and its item:
  `head_row`/`head_item`, `chest_row`/`chest_item`, `legs_row`/`legs_item`, `trinket_row`/`trinket_item` (0: nothing).
  For W2: a piece's look is its item's content (`ItemDef.material`, `pattern`); the row names the item, the slot is the column.
  A piece worn stays in the bag (as a wielded weapon does); one that has left the bag counts for nothing.
- Reducers `wear(item_row)` and `take_off(slot: String)`, rate line `"wear"` in `shared/rules.json`, out of a fight only
  (`in_fight`: hurt within `regents.regen_delay_s`). A SECOND PIECE IN A TAKEN SLOT IS SWAPPED (the old one stays in the
  bag): one click on the doll, as wielding another weapon is. Refused: a non-armor item ("is not worn"), not in your bag,
  in a fight, taking off an empty slot or a slot that is none. `admin_reset_bag` takes the armor off too.
- DEFENSE IN THE HIT: `defense_of` (a player's worn pieces still in the bag, each `rules::piece_defense` = the item's Defense,
  its quality adding up to a fifth at 1000 as for a weapon's damage, ADDED UP; a foe's `FoeDef.defense`) and
  `rules::defense_mult` = K / (K + Defense), K the NEW hot rule `regents.defense_k` (67). `rules::through(dmg, guard, armor,
  traits)` multiplies them in the settled order; `hit_amount` (every swing and a foe's shot: dealt at once, held, taken back,
  a sweep that hits all, all go through it, so `take_back` returns what armor let through), `arrow_hit` and `spell_hurt`
  (player spells and bolts on foes, a foe's ring and burning on players) use it. The attacker's riposte stays in the hit.
- Content: `ItemDef` group "As armor": `armor_slot` (head, chest, legs, trinket; empty: not armor) and `defense`, baked only
  for armor, validated (a slot that is none, stacking, worn and wielded both, a Defense with no slot); the build checks the
  same. `FoeDef.defense` (0 on every foe today). The genre's `genre.tres` (tables, world, cell) and the net config (cell,
  follow) list `worn`.
- HOW S3 ADDS A PIECE AS CONTENT (no code): an `ItemDef` with `armor_slot` and `defense` set (and `max_stack` 1); its
  material and pattern as any made item's. Nothing else reads a list of armor.
- Test pieces (PLACEHOLDERS): `practice_cuirass.tres` (40067, chest, Defense 20), `practice_helm.tres` (40068, head, 10).

**How to play it**: (dev) `admin_give_item <you> 40067 1 0` and `40068 1 1000`; out of a fight, `wear <row>` (no UI yet: W3's
doll); a skeleton's slash (7) lands at 4.74 with both on (7 x 67 / 99); `take_off "chest"`.

**Tested**:
- Native: `armor_takes_its_share_of_a_hit_multiplied_in_order` (the formula exactly, pieces adding before it, quality,
  the order) and `armor_is_content_in_its_slots`; `cargo test` green; wasm check clean. NEGATIVE (mutation): `through`
  adding the multipliers instead of multiplying fails the test ("multiplied").
- Real client and referee, `combat_playtest.sh` 138/0 after merging `main` (new leg: the pieces worn out of the fight, the
  `worn` row back at the client; refused first while still in the fight; every camp hit landed at its foe's hit x 67/99
  [4.74, 7.44]; NEGATIVE in the same leg: none landed whole; taken off). The shell grants them (`GRANT_ARMOR`). The fighter's
  watchdog 720 -> 840 s and its timeout 760 -> 880 s (the leg adds about a minute).
- Unit `regents,content,regents_bar,referee` 1800/0. Integration legs WRITTEN in `integration_genre.sh` (refused in a fight,
  empty slot, not a slot, a weapon, not in the bag; worn row and its cell; the swap; a skeleton's slash x 67/(67+20+12)
  exactly; taken off): NOT RUN (M9).
- Bindings regenerated against the TEST database (64 tables, 111 reducers); `plugin_config.tres` restored.

**Needs on merge**: re-bake, `publish.sh --codegen` (a new table and two reducers: add-only).
**Placeholders made**: Practice cuirass (40067, Defense 20) and Practice helm (40068, Defense 10), `game/regents/content/item/`:
test pieces only; S3's real pieces replace them (Luke fills the slot shares and tier numbers there).
**For Luke**: a second piece in a taken slot SWAPS (the agent's call, as weapons do; say if it should refuse instead).
**For the rules/handbook**: regents-genre.md: "ARMOR (S2): what a player wears is the `worn` row (one a wearer, a column pair a
slot); a piece is an `ItemDef` with `armor_slot` and `defense`; a hit's damage goes through `rules::through` (guard, armor,
traits, multiplied): a new damage path calls it, never a flat cut. Worn and taken off out of a fight only."
**Left for later**: the doll and words (W3), the look (W2), armor traits (A4.1), a foe given a Defense (content).

## Step 93: THE PLAYER'S OWN COLORS (Peasant-only looks, colors on the appearance text, shared materials) (2026-11-16, the armor run's W1)

STOPPED AT THE PICKER, as briefed: the foundation's `CharacterPicker` has no hook for a free color (below). Everything
else is built and tested.

**Built**:
- NEW `game/regents/wardrobe/regents_colors.gd` (`RegentsColors`): a player's clothes colors on the `appearance` text,
  one key per dye slot (`main`, `accent`, `under`, `trim`, `leather`), each value the number 0xRRGGBB + 1
  ("peasant_f;hair=6;main=4876943"). 0 or missing keeps the Peasant's painting. NOT `main=#rrggbb`: the module takes
  only `a-z0-9_;=,.-` in a look, and the foundation's `Appearance.choices` / `make` keep whole numbers only. A number
  survives both, and an old client ignores the key (add-only, rule 17). A bad value (text, negative, too big) is ignored.
  `palette_of(text)` turns the colors into a `DyePalette`, the SAME object for the same colors (`share_key` meta).
  `swatches(slot)` gives the suggested swatches (from the `starter_*` palettes) for the picker.
- NEW `game/regents/wardrobe/regents_figure.gd` (`RegentsFigure extends ModularCharacter`): THE ONE PLACE THAT DECIDES
  WHAT A BODY WEARS AND IN WHICH PALETTE. It is the root of NEW `game/regents/looks/peasant_m.tscn` and `peasant_f.tscn`
  (the foundation's Peasant looks with this script). It reads the colors and drops the clothes keys (torso, arms, legs,
  feet, head, shoulders, neck and their `_dye` colorways), so a player is Peasant only. It dresses on the foundation's
  `assembled` (#313), after every assembly and re-dress, so a reassembly keeps the colors. `appearance_options()` offers
  everything but clothes: hair, beard, brows, skin, hair color.
  W2'S WAY IN: `wear_armor(pieces: {slot: PackedScene}, palettes: {outfit: DyePalette})`. An armor piece shows in its
  tier's palette (`outfit_palettes`, e.g. {"Knight": metal tier}); a slot with no armor shows the player's own Peasant
  piece in their colors (W4); `palette_for(outfit)` is the rule. W2's look component reads `worn`, maps each item to its
  pieces and tier palette, and calls `wear_armor`, nothing else.
- `game/regents/wardrobe/wardrobe.gd`: `dress_shared(model, palette_of)` and `shared_material`: ONE dye material per
  outfit TEXTURE and palette, shared by every piece and both bodies (each glTF piece has its own copy of the outfit's
  material, so it is keyed on the texture, not the material). 300 players in N distinct color sets cost N materials
  per outfit, not 300. Made once, never re-tinted (the lab's `dress` still re-tints its own). `shared_count()` is for W4.
- `game/regents/content/character/adventurer.tres`: `visual_variants` are only the two genre looks, so the picker steps
  Peasant M / Peasant F. An old text naming "ranger_f" or another look falls back to a Peasant by entity id.
  RE-BAKED (`tools/bake_content.gd`): only `shared/content/manifest.json`'s hash changed.
- NEW `game/regents/tests/suites/regents_figure.gd` (the `regents_figure` suite) and NEW `game/regents/tests/figure_shot.tscn`
  (windowed: `figures.png`, four players; `picker.png`).

THE HOOK THAT IS MISSING (for Lane T, add-only): a COLOR option kind in `foundation/ui/character_picker.gd`, e.g.
`{"key": "main", "label": "Main color", "color": true, "swatches": [Color...]}`. It would show a ColorPickerButton plus
a row of swatch buttons, store `0xRRGGBB + 1` as the int choice (0 = the look's own), and be skipped by
`_build_options`' stale check. TODAY THAT CHECK ERASES ANY KEY THE MODEL DOES NOT OFFER, so a player who opens the
picker and presses Done loses their color keys (the shot shows it: opened on "peasant_f;hair=6;main=...", `current()`
is "peasant_f;hair=6"). Since nothing can set the colors yet, nothing is lost in play today.
THE GENRE SIDE IS READY FOR IT: `RegentsFigure.color_options()` declares the five options in that kind (main, accent,
under, trim, leather, each with its swatches), and `appearance_options()` adds them only when
`RegentsFigure.picker_has_colors()` sees `CharacterPicker.COLOR_OPTIONS` (the constant Lane T adds with the hook, the
master's ask). So today's picker never shows them, and once 1.8.4 is pulled they appear with nothing else changed. No
stopgap of index choices: those would store an index where the free picker stores a color.

**How to play it**: the picker (connect screen or Escape > Character) offers Peasant M / Peasant F with hair, beard, brows,
skin and hair color, and no clothes swaps. Colors can't be picked until the hook; to see them now, run the shot below,
or set an `appearance` with `main=<0xRRGGBB+1>` keys.

**Tested**:
- `regents_figure` 49/0: colors round-trip through the text, which the module would take; all five keys fit (<120
  characters); an old text with no keys is today's look (nothing dyed); bad values are ignored with no crash; colors
  come back after a reassembly (a new beard puts the body together again); old clothes keys are dropped; the picker
  offers no clothes keys; bodies in the same colors share one material, other colors get their own; armor (the Knight
  torso) shows in its tier palette while the empty slots keep the player's colors, and armor off restores them;
  the adventurer offers only the two figures, and an old Ranger text falls back to a Peasant.
  NEGATIVE in the suite: the same body with its `assembled` handler cut loses its colors on reassembly.
  NEGATIVE run by hand: with the `assembled.connect` line taken out of `RegentsFigure._init`, 7 checks FAIL (dressed,
  survives reassembly, recolor, both sharing checks, armor on and off).
- `regents_figure,regents_wardrobe,regents,regents_showcase` 1814/0; `content_test.sh` 18/0 after the re-bake (16
  FAIL before it: the build stops on the stale bake, as it should). WHOLE UNIT RUN (`run_tests.sh`, after merging
`main` 13408b0e): 4770 passed, 0 failed, lints OK. `regents_figure` also checks the five color options are declared
with swatches, and shown only when the picker has `COLOR_OPTIONS` (today: not shown).
- Shots looked at (`"$GODOT" --path . res://game/regents/tests/figure_shot.tscn -- <dir>`): four players told apart
  at a glance (an old text's painted Peasant, a woman in blue and gray, a man in red and cream, a Knight torso in the
  tier's metal over green Peasant pieces); the picker on Peasant F with hair, skin and hair color only.

**Needs on merge**: the FREE PICKER needs template 1.8.4 (`CharacterPicker`'s color option kind and `COLOR_OPTIONS`);
until then the colors are built, tested and shown on bodies, but a player can't pick them. The content manifest is baked: on conflict, re-bake (`tools/bake_content.gd`). No publish needed for
play (nothing the server reads changed except the manifest's hash; a publish with the next server change carries it).
**Placeholders made**: THE SUGGESTED SWATCHES, `RegentsColors.swatches` (`game/regents/wardrobe/regents_colors.gd`, marked
`PLACEHOLDER`): the four `starter_*` palettes' colors per slot. Luke picks the row (or keeps it).
**For Luke**: the suggested swatch row (the placeholder above): keep the starter colors, or choose your own?
For the rules/handbook (regents-genre.md, under THE WARDROBE): "A PLAYER'S BODY is a `RegentsFigure`
(`game/regents/looks/peasant_m|f.tscn`, the adventurer's only looks): Peasant clothes in the player's own colors
(`RegentsColors`: keys `main`, `accent`, `under`, `trim`, `leather` on the `appearance` text, each 0xRRGGBB + 1; never
`#`, which the module refuses), dressed on the foundation's `assembled` with materials shared by palette
(`Wardrobe.dress_shared`). Armor goes on through `wear_armor` (pieces + tier palettes); nothing else dresses a player."
HANDBOOK: the same, plus how to see it (`figure_shot.tscn`).
**Left for later**: the free color picker (the hook above, then ~10 lines). W4 measures the shared materials at 300
(`Wardrobe.shared_count()`). `_shared` and `RegentsColors._palettes` keep every palette seen, so hundreds of distinct
color sets mean hundreds of small materials kept for the session; prune if W4 says so.

## Step 94: ARMOR PIECES (the material table makes metal, leather and cloth armor; Defense = share x tier) (2026-11-16, the armor run's S3)

Branch `claude/s3-armor-pieces` (from `main` 7760ca2c, `main` d82439fd merged in). Not pushed.

**Built**:
- THE MATERIAL TABLE MAKES ARMOR (content and the table's code only; the server needed nothing: S2's `armor_slot` and
  `defense` carry it):
  - `material_def.gd`: two families appended, `HIDE` (leather) and `FIBER` (cloth): METAL 0, WOOD 1, HIDE 2, FIBER 3.
  - `pattern_def.gd`: group "As armor": `armor_slot`, `defense_share`, `trait_parts` (baked only for armor; validated).
  - `material_table.gd`: a cell's `armor_slot` is its pattern's and its `defense` is `defense_share x material.tier`
    (`ITEM_FIELDS`), so a stale piece is reported and Make the table fixes it, as for Power and tool tiers.
- NEW MATERIALS (each a PLACEHOLDER tier): `soft_leather` (HIDE, tier 1, raw Soft leather), `supple_leather` (HIDE,
  tier 2, raw Supple leather), `linen` (FIBER, tier 1, raw Flax: no spinning yet).
- NEW PATTERNS: `plates` (anvil, smithing, two bars, a shape round: the core of metal armor, A3); metal `armet`
  (head), `cuirass` (chest), `legplates` (legs): plates + copper rivets at the workbench, quality from the plates;
  leather `hood`, `jerkin`, `leather_trousers`; cloth `robe`, `cloth_trousers` (W1: no cloth headwear). Leather and
  cloth take their material's raw form at the workbench, no quality.
- MADE BY THE TABLE (40 files): 17 pieces (copper/iron/steel x armet, cuirass, legplates; soft/supple leather x hood,
  jerkin, trousers; linen robe and trousers), three plates, and their 20 recipes. Ids 40069-40088 (items), 40054-40073
  (recipes). Real recipes: a tester crafts them at the anvil and workbench (no dev grant needed).
- `skilling_component.gd`: every armor recipe lists under ONE heading "Armor" in the workbench (not eight, with plurals
  like "Legplateses"); the list's sort kept per station while its recipes stay the same, and `core_grades` checks a
  stack's item before parsing its quality: the workbench's no-change look stays under its 4 ms (3.6-3.7 ms with 46
  recipes; it was 4.2-4.8 before these two).
- S2's practice pieces (40067, 40068) KEPT: S2's integration legs use them; they are no table cells. Remove later.

HOW W2 FINDS A LOOK from an item id in a `worn` column (content only): `var it := ItemDef.by_id(id)`; its SLOT is
`it.armor_slot` (and the column it is in); its MATERIAL is `it.material` (`MaterialDef`: `key` copper/iron/steel,
soft_leather/supple_leather, linen; `tier`; `color`); its FAMILY is `it.material.family` (`MaterialDef.Family.METAL`,
`HIDE`, `FIBER`); its PIECE is `it.pattern.key` (armet, cuirass, legplates, hood, jerkin, leather_trousers, robe,
cloth_trousers). `MetalFinish` by `material.key` for metal; leather by its material (the animal: soft = deer, supple =
wolf); cloth by its material (the fiber). A piece with no material (S2's practice pieces) has no family: draw nothing.
The unit suite checks this lookup (`_run_armor_cells`).

**How to play it**: (dev) `admin_give_item <you> 40075 1 0` (Iron cuirass) or craft: iron plates at the anvil (two iron bars,
a shape round), then the Iron cuirass at the workbench (three plates, two copper rivets); `wear <row>` out of a fight.

**Tested**:
- Native `armor_pieces_are_share_times_tier_for_every_family`: all 17 pieces' slot and Defense = share x tier exactly;
  each family has its slots; NEGATIVES: no cloth head, the trinket empty, and no part offers any armor piece a trait
  (while copper rivets do offer a sword theirs). `cargo test` green, wasm clean.
- Unit `regents,content,regents_bar` 1742/0 after merging `main`. New `_run_armor_cells` (share x tier from each cell's
  pattern and material; W2's lookup; NEGATIVES: no cloth headwear, no trait on armor). Existing checks moved
  deliberately: nine materials and 24 patterns, 65 cells, 21 anvil and 46 workbench recipes, 32 rounds, iron's tier
  moving also flags its three pieces' Defense, the workbench's headings now end "Armor", "Other".
- `combat_playtest.sh` 139/0 (before merging `main`): the armor leg now wears REAL pieces (an iron cuirass and a copper
  armet of quality 1000, Defense 12.4): camp hits landed at 9.28 and 5.91 (11 and 7 x 67/79.4), none whole. The shell's
  `GRANT_ARMOR` now takes the item ids from the fighter. After merging `main`: 137/0 again (hits 9.28 and 15.78).
- Integration leg WRITTEN (not run, M9): the copper armet refused with no plates; offered no trait; begun with plates and
  rivets.

**Needs on merge**: re-bake. No codegen (no table or reducer changed).
Placeholders made (each marked in its file's designer notes):
- The slot shares: head 2, chest 5, legs 3 (`content/pattern/{armet,cuirass,legplates,hood,jerkin,leather_trousers,robe,cloth_trousers}.tres`, `defense_share`).
- The tiers of the new materials: soft leather 1, supple leather 2, linen 1 (`content/material/{soft_leather,supple_leather,linen}.tres`). Metal uses its existing tier (copper 1, iron 2, steel 3).
- The trait parts: every piece names "lining", "straps", "fittings" (`trait_parts`), the structure only: no trait offered.
- The recipes' amounts (plates 2 bars; armet 1, cuirass 3, legplates 2 plates; leather 1/3/2; linen robe 4, trousers 3 flax) and XP.
**For Luke**: leather and cloth are as strong as metal of the same tier for now (A2.2, why wear lighter armor, is his); linen
is made straight from flax (no spinning yet).
**For the rules/handbook**: regents-genre.md: "ARMOR PIECES are cells of the material table: a pattern with `armor_slot` and
`defense_share` (its cells' Defense = share x material tier); a new piece or material is content and Make the table, never
code. Leather is the HIDE family, cloth FIBER."
**Left for later**: armor traits and their parts (Luke's), the look (W2), the doll (W3), the trinket, removing S2's practice pieces.

## Step 95: THE PICKER'S COLORS CHECKED; THE NPC SESSION OVERRIDE GONE (2026-11-16, the armor run's W1b)

**Built**:
- Nothing new genre-side for the picker: template 1.8.4's color option kind took the five options W1 had already
  declared (`RegentsFigure.color_options`, shown since `picker_has_colors()` now sees `CharacterPicker.COLOR_OPTIONS`).
  The "~10 lines" were not needed.
- `game/regents/tests/suites/regents_figure.gd`: THE PICKER check. On the adventurer, a picker opened on
  "peasant_f;hair=6;trim=<red>", `main` picked blue (`pick_color`), then Done. Done hands on `main=<int>` for blue,
  keeps the trim and hair it opened on, the preview wears blue as it is picked, and the module would take the text.
  NEGATIVE: the same pick on a look that does not offer the colors (the foundation's own Peasant scenes) is dropped at
  Done, as the old stale check dropped W1's keys.
- REMOVED `game/regents/npc_session_component.gd` (+ `.uid`) and its override on `Components/Session` in
  `game/regents/combat/foe.tscn` and `game/regents/npc.tscn`. Template #315 makes the foundation's `SessionComponent`
  take `session_member` (and `lobby_member`) as optional, exactly what the genre script did, so the foes and the guide
  now use the foundation's component unchanged. `npc.tscn` STAYS (guide.tres names it; a new NPC scene still inherits
  it): it is now `player.tscn` with nothing over it.

**How to play it**: Escape > Character (or the connect screen's Character). Peasant M / F, hair, skin, hair color, then
Main color, Accent, Under, Trim and Leather: each a color button (any color), a row of suggested swatches, and
"Look's own". The character on the left wears it as you pick; Done keeps it, and everyone sees it.

**Tested**:
- Shot looked at (`figure_shot.tscn`, windowed): the picker on Peasant F shows the five color rows with their
  swatches (the blue the shot opened on is ringed as chosen); the preview is dyed; `current()` keeps
  `main`, `accent` and `trim` ("peasant_f;accent=4868687;hair=6;main=4876943;trim=11577481"). In W1's shot the same
  text came back as "peasant_f;hair=6".
- `regents_figure` 57/0 (6 new checks, the negative among them); `regents` + `regents_figure` 1513/0 after the scene edits.
- `bind_playtest.sh` (under the lock, with the override gone): 3 passed, 0 failed; no "binding after ... without rows"
  warning in the client's log.
- Whole unit run (`run_tests.sh`, branch up to date with `main` d82439fd): 4806 passed, 0 failed, lints OK.

**Needs on merge**: none (client only; no bake, no publish).
**Placeholders made**: none new (W1's swatch row stands).
**For Luke**: none new.
**For the rules/handbook**: regents-genre.md, AN NPC'S SCENE: drop "until the template's fix, DECISIONS #315, is pulled"
and the reason. #315 is pulled and the genre's override is gone. A new NPC scene may inherit `npc.tscn`,
`combat/foe.tscn` or `player.tscn`; the 2 s wait for `session_member` no longer happens. Keep "a change to an NPC's
scene runs `bind_playtest.sh`".
**Left for later**: the picker's color rows give no `own` color (the Peasant's painted color shown while nothing is
chosen: the button shows the foundation's default). Each slot's painted mean could be read from `palettes/peasant_1.tres`
if Luke wants the button to start on it.

## Step 96: WORN ARMOR, SEEN (the look component, the armor looks table, every tier's palette) (2026-11-16, the armor run's W2)

**Built**:
- NEW `game/regents/wardrobe/armor_looks.tres` (`ArmorLooks`, `armor_looks.gd`) with rows `ArmorLookEntry`
  (`armor_look_entry.gd`): THE ONE TABLE A DESIGNER EDITS, in the Inspector. `entries`: per armor PATTERN (and
  optionally one material), the outfit piece files it puts on, slot by slot, for each body (Luke's W1): armet = the
  Knight's armet; cuirass = plate torso + plate arms + round pauldrons + the scarf; legplates = plate legs + feet;
  hood = the Ranger's hood; jerkin = jerkin + bracers + its pauldron; leather_trousers = trousers + boots; robe =
  robe + sleeves; cloth_trousers = trousers + shoes. A STEEL cuirass row wears the SPIKED pauldrons (W3). `palettes`:
  per MATERIAL the palette its pieces wear (W2): copper, iron and steel the NEW `palettes/metal_1_copper|2_iron|3_steel.tres`
  (the bar's `MetalFinish`); soft_leather `leather_1_soft` (deer), supple_leather `leather_2_supple` (wolf); linen
  `cloth_1_flax`. `dress_for(items, body)` answers what a body wears: pieces and palettes per outfit. A closed helm
  takes off hair and beard, a hood the hair (`Wardrobe.HIDES_HAIR`); an item with no material or pattern (the
  practice pieces 40067/40068) puts on nothing.
  A new piece of a known pattern and material needs nothing here; a new pattern needs a row, a new material a palette.
- NEW `game/regents/wardrobe/armor_look_component.gd` (`ArmorLookComponent`, on `adventurer.tscn` as
  `Components/ArmorLook`: the character-scene token, held for W2): reads the `worn` row (required and optional: no row,
  no armor), copies the four item ids out (rule 6), and calls `RegentsFigure.wear_armor` with `dress_for`'s answer.
  A slot back to 0 shows the player's own Peasant piece in their colors (W4); the row gone takes it all off. Every
  client does it for every player in its ring, so everyone sees everyone's armor. A new model (a look chosen again) is
  dressed as it comes. A referee draws nothing. Presentation only (hard rule 11).
- Materials stay SHARED by palette (W1's `Wardrobe.dress_shared`): 300 players in iron armor share one Knight material.
- `game/regents/tests/figure_shot.gd`: two more shots, `armor_male.png` and `armor_female.png`.
- NEW two-client playtest `game/regents/tests/armor_seen_playtest.sh` (+ `playtest/armor_seen_playtest.gd/.tscn`).

**How to play it**: (dev) `admin_give_item <you> 40075 1 0` (iron cuirass; 40069-40088 are the armor), then `wear <row>` out
of a fight (W3's doll will do it with a click), `take_off "chest"`. Two instances: each sees the other's armor.

**Tested**:
- `regents_figure` 221/0 (164 new checks). Every armor piece in the content (17) has a row whose files exist on both
  bodies and a palette (metal with its finish). A `worn` row dresses its wearer: the iron cuirass shows the Knight's
  chest in iron over Peasant legs and feet in the player's colors. Another player's row dresses their body only
  (supple leather in the wolf palette). A reassembly (a new beard) keeps the armor and its finish. A chest back to 0
  brings the Peasant shirt back; a closed helm hides the hair; the row gone restores all Peasant, hair included. The
  practice pieces draw nothing. A new model is dressed again. Steel's pauldrons are spiked; NEGATIVE: iron's are round.
  MUTATIONS: the component not dressing on a row fails 8 checks; the table ignoring a material's own row fails the spike check.
- `armor_seen_playtest.sh` (two real clients at 150 ms, under the lock): wearer 6/0, watcher 7/0, server 1/1. Three
  pieces worn through `wear`; the watcher, coming in after, sees the armet, cuirass and leather trousers on the wearer
  with the hair hidden and the Knight pieces in the chest's iron finish. NEGATIVE: the watcher's own body stays all
  Peasant. The chest comes off (`take_off`) and the watcher sees the Peasant shirt again with the helm still on.
- `bind_playtest.sh` 3/0 with the new component on the adventurer (no binding warning).
- Shots looked at (`figure_shot.tscn`, windowed): on each body a Peasant, then copper, iron, steel (spiked
  pauldrons), soft leather (tan), supple leather (wolf gray), linen. Each tier reads at a glance; a hood hides the hair
  and keeps the beard.
- Whole unit run (`run_tests.sh`, `main` merged in): 5094 passed, 1 failed. The one: "the workbench window's look with
  nothing changed: 4.14 ms (under 4)", a timing check under the whole run's load (S3's own report puts it at 3.6-3.7 ms).
  `--only=regents` twice right after: 1581/0 both times. Not this change (no skilling code touched).

**Needs on merge**: none (client only; no bake, no publish).
**Placeholders made**: THE CLOTH UNDER METAL, `palettes/metal_1_copper|2_iron|3_steel.tres` (their `note` says PLACEHOLDER):
the scarf and padding keep the Knight's first colorway (gray, a red scarf) at every bar. Luke picks it per tier, or one
for all.
**For Luke**: (1) the cloth under metal (the placeholder above). (2) TWO PIECES OF ONE OUTFIT IN DIFFERENT MATERIALS (a steel
armet with an iron cuirass) wear ONE palette, the chest's (then the legs', then the head's): the dye is per outfit
material. Fine, or should each piece keep its own bar (it would take a material per piece)?
For the rules/handbook (regents-genre.md, THE WARDROBE): "WORN ARMOR IS SEEN through `ArmorLookComponent` (the `worn`
row) and the table `game/regents/wardrobe/armor_looks.tres`: a pattern's pieces per body, a material's palette. A new
armor pattern gets a row there (the `regents_figure` suite fails a piece with none), a new material a palette; never
code. A change to it runs `armor_seen_playtest.sh`." HANDBOOK: how to add an armor look (the two lists above), and
`figure_shot.tscn` to look at every tier.
**Left for later**: W3's fittings in the tier's metal show only where an outfit's zones mark metal (the leather and cloth
palettes carry copper or iron buckles already). The trinket shows nothing (no piece). W4: `load_300.sh` with dressed bots.

## Step 97: THE CHEST'S ABILITY ON F (Blink from the cloth chest; placeholder Snare and Shove) (2026-11-16, the armor run's S4)

Branch `claude/s4-chest-ability` (from `main` 71edb653, `main` 2e9322ea merged in). Not pushed. Held: the `ui/` token
(the bar's F) and, split by the master, `game/regents/combat/combat_component.gd` (its F / chest-cast path only).

**Built**:
- CONTENT: a chest names the ability it gives on F. `ItemDef.worn_ability` and `PatternDef.worn_ability` (chests only,
  validated); the material table copies the pattern's to each cell (`ITEM_FIELDS`), the bake carries it, the server's
  `ItemSeed.worn_ability`. One a family: the robe (cloth) Blink, the jerkin (leather) Snare (placeholder), the cuirass
  (metal) Shove (placeholder). NEW `ability/chest_snare.tres` (40049) + `spell/chest_snare.tres` (40010), a cone that slows
  (Gale's atom); `ability/chest_shove.tres` (40050) + `spell/chest_shove.tres` (40011), a short cone that throws back and
  wears poise (Gale's atom). Both drawn as Gale's landing (`vfx/ability_vfx.tres` rows). The staff kit no longer has
  Blink (B8: "BLINK MOVES from the staff to cloth chests"): Fireball, Frost Ring, Gale, Meteor.
- SERVER (`regents.rs`): `cast_spell` and `land_spell` take a CHEST'S spell (`rules::is_worn_ability`) from the worn
  chest (`worn_ability_of`: the `worn` row's chest still in the bag), whatever is wielded; no mana (mana is the staff's),
  no mastery trained (`spell_hurt` skips skill 0), damage as written. Refused "wear a chest that gives it" with no chest,
  another family's chest, or the chest taken off; a weapon's spells are gated by the weapon exactly as before (Q, E, R).
  No new table or reducer: no codegen.
- CLIENT: `RegentsItemLevel.is_worn_ability`, `worn_ability_of` (the twin); `CombatComponent.on_slot(3)` is
  `chest_ability()` (the worn row's chest, in the bag), a chest's spell is cast whatever the kit, F's press skips the
  weapon's level gate. THE BAR (`ui/ability_bar.gd`): F shows the chest's ability, its words and kind as a spell's; empty,
  "A chest you wear may put its own ability here: a robe, a jerkin or a cuirass each gives one." The key is
  `CombatComponent.SLOT_ACTIONS[3]` (default F, a setting already: B5 holds).
- THE CHEST'S LEVEL (B8 "levels as a weapon does"): NOT BUILT. With one ability a family there is nothing to open or pick;
  a chest's ability has no level gate. Left for when a family has more (its numbers are Luke's).

**How to play it**: (dev) `admin_give_item <you> 40087 1 0` (a linen robe), wear it from the bag (or `wear <row>`) out of a
fight, press F: Blink. A soft leather jerkin (40082): Snare (placeholder); an iron cuirass (40075): Shove (placeholder).

Players holding staffs today: Blink was the staff's F (never a pick), so no pick changes; the staff's F is empty until they
wear a robe. A `spell_cooldown` row for Blink stays and is read as before (the cooldown carries over). No crash: an
ability no kit holds is simply not on the weapon's bar; a stale pick of an ability no longer in a kit is ignored (P1's rule).

**Tested**:
- Native: `the_chest_gives_f_one_ability_a_family` (each family's chests give its one; only chests give; each is in no
  weapon's kit, so a staff alone cannot cast Blink; NEGATIVES: no staff spell is a chest's, the staff has no Blink);
  `the_staff_casts_its_spells_from_mana` and `item_levels_and_picks` updated deliberately (four staff spells). `cargo test` green.
- Unit `regents,regents_bar,regents_vfx,regents_wardrobe,regents_figure,content` 2413/0 after merging `main`. New in the bar's
  suite: a staff with no chest has F empty and its words, and NEGATIVE no Blink; in a linen robe Blink on F, ready; a
  jerkin Snare, a cuirass Shove (NEGATIVE: not Blink); NEGATIVE a helm gives nothing; Blink a chest's, in no kit. The staff's
  layout checks moved to four spells. The vfx coverage check passes with the two new rows.
- Real client and referee, `combat_playtest.sh` 139/0 before and 139/0 after merging `main` (with W2's armor look on the adventurer): with the staff and
  no chest the F KEY does nothing (NEGATIVE), the shell gives a linen robe, it is worn, F holds Blink from the `worn` row,
  and the F key Blinks the player 8 m, its columns shown.
- Integration legs WRITTEN (not run, M9): Blink refused from a staff alone, refused in a leather jerkin, Shove refused in
  it, Snare cast in it at no mana, the robe swapped on and Blink cast in the existing timed run, refused again once taken off.

**Needs on merge**: re-bake. No codegen.
**Placeholders made**: Snare (placeholder) 40049/spell 40010 (leather's F) and Shove (placeholder) 40050/spell 40011 (metal's F):
`game/regents/content/ability/chest_*.tres`, `content/spell/chest_*.tres`: what each does and its numbers are Luke's.
**For Luke**:
- Confirm the reading "Blink moves from the staff's F to the cloth chest" (B8): built so; a staff user with no cloth chest
  has an empty F that says what fills it (B7, no tools yet).
- A chest's ability costs no mana and trains no mastery (mana is the staff's alone): his to change.
- The chest's level (B8) waits for a family with more than one ability.
**For the rules/handbook**: regents-genre.md: "F IS THE WORN CHEST'S (S4): a chest pattern's `worn_ability`, cast from the worn
row whatever is wielded (`is_worn_ability`, `worn_ability_of`, both sides); a weapon's kit never holds it."
**Left for later**: the chest's level and picks; tools on an empty F (B7); full-set bonuses (B8, later).
