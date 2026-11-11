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
