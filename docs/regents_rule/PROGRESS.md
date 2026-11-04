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
    click a column of the hot bar to beat it down (some spreads to its neighbours) until it matches the
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
definitions; a FoeDef (`content/foe/`: its key, character, kit, health, damage %, XP %, behaviour, loot);
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
foundation now has a UI kit (template DECISIONS #265): one style file (`UiStyle`: colours, sizes, fonts)
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
landing beside it, point blank); the integration (a draw, a loose at a skeleton ten metres off with the
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
- **The grade is a colour**: a slot's edge (two wide; a picked slot keeps it) and the item's name. The
  colours are the game's style (`UiStyle.grade_colors`: grey, green, gold), so a fantasy reskin recolours
  them (template DECISIONS #267).
- **Names**: "Fine iron axe", "Masterwork iron sword"; a Common one keeps its plain name.
- **Power**: the one number to compare, the weapon's damage in percent of its kit's with its quality in:
  an iron weapon 100 to 120, a bronze one 70 to 84; arrows their own percent. It is exactly the hit
  the server deals. Tools show their tier and work instead (a node asks for a tier).
- **The bag** shows it all: the graded name, "Masterwork · quality 85% · oak handle", and
  "Power 117 (+6 on your Fine iron sword)" in green (red when worse) against the weapon you wield. A
  crafted item's notice is in its grade's colour.
- **Tier dominates**, checked: an item's check in the Content Dock (and the bake) refuses a weapon whose
  best reaches the next tier's worst in its kit.
- Fixed on the way: a made item with a handle showed a garbage quality in the bag (`"q":850,"h":40016`
  read as 85040016); quality is now read as JSON.

Code: `content/item_grade.gd` (`RegentsGrade`), the bag window, the HUD's notice. Proven: the regents
suite (bands, names, Power against the server's damage rule, tier dominance and a bronze axe at 90 %
caught, the bag window's slots, name colour and Power lines); negative: Power ignoring quality and the
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
grade's colour and its name above. Each is **yours alone for a minute** (nobody else is even sent it),
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
- **Waiting**: Keen (needs crits and Bleeding), Padded and Warded (need armour), Reaching (needs the
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
  a thin **roll** bar that refills over the roll's 1.5 s cooldown (grey while it does; its tooltip says
  how long).
- **A work bar** under the prompt while you work AFK: it fills to the next piece (bar, batch, ore, log),
  piece after piece, from the server's own `next_at`. The station's window shows the same bar.
- **Make 1, Make X, Make all** in the station's window (X is the number box beside it; 5 to start).
  Make X stops itself after that many batches (the client asks `work_stop` after the last), Make all
  works until the bag runs out (what Make did before). The prompt and the window say "Making 2 of 5".
- **The minimap**, top right, OSRS style: round, turning with the camera so ahead is up, N on the rim, the
  level drawn once from straight above when it loads, dots for players (white), foes (yellow), trees
  (green), rocks (grey), stations (blue) and the dummy (orange), your arrow in the middle. The mouse
  wheel over it zooms (15 to 90 m) while the cursor is free (a window open, or Alt). Open for iterations: click-to-walk, a world map, quest markers.
- **Hits flash**: whatever is hit lights up white for a moment, you light up red, and the screen's edge
  pulses red (more for a bigger hit); a hit taken while blocking flashes steel blue and says "Blocked";
  a stagger (your parry, a Heavy trait) flashes gold and says "Staggered". On top of the numbers and the
  shake that were there.

**Tested**: native `regents` (the meta's period, shares and alarm; each weapon type's skill); the
integration hook (a chop on a foe tallies one axe hit of 2 damage; the dummy never counts; the period
closes into one share: axe, 1 hit, 100 %, an alarm); the template's `telemetry_test.sh` (21 checks on a
real server); the regents suite's polish checks (the minimap's sums and colours, the work's progress and
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
  shows its ore so (grey in the scene, the ore's colour in the game). They start snapped onto the surface,
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
  output and part slot. **Everything else is yours and stays**: an item's colour, look and words; a
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
XP and time), made again a no-op, a renamed cell restored with its colour and XP kept, a tier change
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
left out, a Common head's room for one, MAKE greyed with the oak handle gone); native `cargo test` all (the
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
or a Masterwork), greyed when you have none; there is no benefit to more than one trait yet (only handles
offer one); and earlier materials should say what to expect at the workbench. His calls (`GAME.md`):
- **The head by grade**: in Takes, the head is a list, "1 / 1  Masterwork iron axe head", "Fine ...",
  "Common ..." (a grade you lack greyed; none at all, the list greyed). The window sends it
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
with the missing grade greyed and the best as fallback; "A Fine iron axe holds 2 traits"; a checkbox drawn
as one; Gentle with no room at Common, moving up when Steady is left out; the refit line, its cost, REFIT
greyed when nothing changes or bars are short; tooltips: what a material makes, a part's traits); native
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
continent only (no islands, no name), **about 3 km across its widest**, the camp in the **centre-west
lowlands**.
- **The shape is read off the map** (`continent_shape.gd`): its green is land, its grey-brown ridge the
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
    proven; two real foundation bugs found on the way are fixed: (a) `Cells.recentre` held the old ring centre
    after a long jump onto a cell's EDGE, and the spawn (0, 0, 8) is on one: back at the camp from far away a
    player kept a ring 600 m off and was sent nothing round them (now a jump past the neighbouring cells
    re-centres at once); (b) a nameless player whose admin row comes after theirs is asked after again
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
the town at its neighbours' frame time; was 102), four 30.4, six 21.2. `REFEREE_SCALING.md`, last section.
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

**Left for later**: the step-2 rules (the finisher's armour, so a player's heavy no longer flinches a foe's
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
- **The finisher** (`hit`, `deal`): armour (never flinched); it flinches a step in its wind-up; landing
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
  draws no more than damage), the drop weight's rule, a badge (shape and colour) and its guard in words.
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
neighbour, gave up while the player was staggered, or stopped the block phase at 45 health after ~5 s): each now
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

- **The hit's light** (`combat/hit_feedback_component.gd`): FOUND the squares were every ember drawn a whole metre
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
  bursts as it breaks and is grey while Steadied; nothing for a player. Its state is the public `poise_state` table
  (by cell, as every placed thing of ours); the private `poise` table published an hour before it is retired, kept
  declared (a published table is never removed).

**Tested**: native (poise_hit: lights stop at 1, the last hit breaks, Steadied wears nothing, Heavy breaks 70 in one
string; poise_now), unit (Heavy's poise and words; the marker's reading: worn, whole again unhit, steadied, a burst once
and not twice), integration (a real referee: a chop wears 10 of 60, the last hit leaves 10 and no stagger, a light stops
at 1, the next last hit breaks and staggers, Steadied a chop wears nothing, Heavy breaks a fresh 60 in one string; the
older stagger checks run on a dummy without poise), combat playtest (a chop fills a fifth of the arc; broken, the arc is
grey; the yard's three in a row breaks the partner). The camp phases now bring a slain player back (three skeletons
killed it once). A render of the arc at 30 / 75 / 98 % and Steadied checked by eye.

**Luke's to tune** (live rules and FoeDef): poise 70 / dummy 50, wear 10 and 40, Heavy x1.35, Steadied 3 s, regrowth
8 s. Players without poise for now.

## Step 35: Luke's play of 2026-11-03 (feedback #8193-#8196); the armour prep sheet (2026-11-03)

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

**The armour prep sheet**: `docs/regents_rule/ARMOUR_PREP.md` (A1-A10, each with options and a recommendation), for
Luke's answers before any armour is built.

**Left**: #8196 (the template change above, Luke's go-ahead); the foundation's `content` check "a script runs from the
repo root" failed 2 of 5 unit runs here (it waits 600 headless frames for Git Bash under load: flaky, a template fix).
