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

### Luke's solo playtest of the continent (2026-10-24 night): his notes, sorted, NOT fixed yet
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
  - #8 the sword: spamming LMB cuts off the second swing's animation; Q (Lunge) is cut off halfway.
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
