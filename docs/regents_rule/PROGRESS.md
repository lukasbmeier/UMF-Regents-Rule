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
