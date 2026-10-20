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
