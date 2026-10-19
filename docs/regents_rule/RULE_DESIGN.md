# Regent's Rule — Game 4 design & plan (fantasy MMO-lite, seamless, 100–300 CCU)

Working title. A persistent, seamless open world for 100–300 concurrent players in one database: log in where you left, fight the wild with a weapon that *is* your class, work the world's trees and veins through minigames that the server scores, craft in the Regent's town, run a lair in the open and a procedurally assembled dungeon in an instance. Hybrid combat: basics resolve against your target instantly; skill shots are aimed and earned; abilities chain without a global cooldown and are paced by their own cooldowns.

Grounded in the template at **0.51.1** (this repo's fork point, 2026-10-18; `docs/FOUNDATION_SYSTEMS.md`): milestones **1–7 and 9–15 are built** (bots on the referee 0.43.0 with behaviour trees 0.48.0; noise, pings, friendly collision, first-person comfort and recording 0.44.0–0.45.0; bodies the referee moves 0.49.0; the follow cam with aim and charge 0.50.0; server pushes 0.51.0). **Milestone 8 (a world per match) is not built**, and the Undercroft needs it. **Milestone 16 (items) exists only as DiscGolf's genre code**, not in the template; milestone 17 (joining between rounds) does not apply here. Statuses from collisions (Knocked Down), planned with 15, were built in DiscGolf's genre, not the template. The design rests on that state and on the owner's answers of 2026-10-13: **100–300 CCU per database, never more**; **hybrid combat** (tab-target basics, action skill shots from day one); **seamless open world**; the eight scope recommendations accepted as a starting point (humanoids on the UAL rig with animals as NPCs and mounts; classless, the weapon is the kit; PvE with opt-in duels; shrine respawn, no item loss; static world, no player building; parties of four, lairs plus one instanced dungeon; vendor economy, no player market; v1 = one ~1 km² zone, three kits, six NPC types, one lair, one dungeon, a short writ chain); and the second-pass owner decisions: **no global cooldown** — MOBA-style chaining with a cast queue, pacing from long cooldowns; **duels** end in a kneel at 1 HP, and leaving the dueling area is a loss for the one who left; **the dungeon is procedural** (modules stitched from a seed) as a template test of replayability; **harvest nodes are OSRS-style** respawning static world objects; and **harvesting runs a minigame** — a complex interactive UI that opens on a button press with the right gear, scored by the server from inputs.

**Owner items of 2026-10-18** (§13): a new fantasy setting (#1); one resource pool named per kit (#2); ranks from XP on a content curve, 10 in v1 with abilities at 1/3/6/9 and nodes gated by gathering rank and tool tier (#3); SpacetimeAuth accounts (#13); **no tool slot**, the best tool in the bag is used (#15); **three minigame models**, Rhythm, Trace and Tension (#17); and **`chunk` added to the existing positional tables in a template 1.0** (§11). Still open: #7 loot, #10 hosting (after measurement), #12 day/night. Where a sentence below needs one of those values, it uses the recommendation and says *pending #n*; nothing marked pending is decided. Every number here is a hot rule or content unless it sits inside a parity model.

---

## 1. Pillars
1. **One world, no seams.** No zones, no loading screens, no turns. You log back in where you stood.
2. **The weapon is the class.** Pick up a bow and you are a ranger; mastery lives in the kit, not a character sheet. Three kits balance against each other instead of nine classes.
3. **Targeted is instant, aimed is earned.** Basics resolve in the module against your target at 2L + 25. Skill shots are aimed and judged by the sidecar. Both feel right; only one can miss.
4. **Chain, then wait.** No global cooldown. Abilities queue and fire back to back; the cost is a long cooldown, so burst and spacing are both real choices.
5. **Working the world is a game, not a bar.** A tree or a vein opens a minigame the server scores. Nodes are real objects: they deplete, they respawn, everyone shares them.
6. **Alive at your LOD, variable on purpose.** NPCs think near players and sleep when nobody is there; the dungeon is assembled from a seed so no two runs are the same.
7. **Scale is a schema decision.** One database for the game's whole life, laid out so a second region is a move, not a rewrite.

## 2. The fiction (three touchpoints, as GroMax in Fowl Play)
The monarch is absent; the **Regent** holds the frontier province in trust. Flavour is confined to three mechanical surfaces and goes no further:
| Touchpoint | Mechanic it explains |
|---|---|
| **The Regent's Writs** | quests: a writ board in town posts the province's needs; turning one in pays in **marks** |
| **The Regent's Shrines** | respawn points and fast travel; "the Regent's protection" is the Weakened status after death |
| **The Levy** | the vendor economy: marks are the Regent's coin, vendors are the Regent's quartermasters, prices are the levy |
Universe (owner, 2026-10-18, #1): **a new fantasy setting**. Hollow Hill's animals are reused as **assets** (wildlife, mounts), not as lore.

## 3. The loop (v1 "lite")
| Layer | Beat |
|---|---|
| **Session** | log in → your character stands where you logged out, with the HP, kit, tools and writs you had. No lobby: the world is the lobby. |
| **Minute** | target a wolf, basics land instantly, queue the aimed shot behind the bash, dodge the lunge; loot drops; a vein glows — press E with a pick in your bag and the tracing minigame opens; a good trace yields ore, a bad one wastes the swing |
| **Hour** | writs from the board: kill eight wolves, mine ten ore, clear the bandit camp, reach the ridge shrine, craft a thing, kill the lair boss. Rank up a kit or a gathering mastery; a new ability or node tier opens. Buy and sell at the quartermaster; craft at the forge. |
| **Evening** | a party of four: the lair in the open (elites, a boss, contested by anyone), or **the Undercroft**, an instanced dungeon through the gate — assembled from a seed on entry (world per party, M8: not built yet), five to eight rooms and a boss, 20 min cap, different every time |
| **Progression** | **weapon mastery** per kit and **gathering mastery** per skill (Woodcutting, Mining, Herbalism; Fishing later from game 1), ranks from use (owner, 2026-10-18, #3): the server stores **XP** and the rank comes from a content curve, so the cap can grow past v1's without a migration (production will want more than 10); **v1 is ranks 1–10**, kit abilities at 1/3/6/9, and a node tier needs **both** a gathering rank and a tool tier. Wearables add stats and one passive each. No character level. |

## 4. Combat
### 4.1 Inputs
| Input | Does |
|---|---|
| **Tab / click** | set the **hard target** (`set_target`); Tab cycles nearest-first in the facing cone |
| reticle | the **soft target**: whatever the client's centre ray highlights; basics use it when no hard target is set |
| **LMB** | the kit's **basic** (TARGETED) on the target; held = auto-repeat at the kit's attack speed |
| **1–4** | kit abilities; aimed kinds read the reticle (origin + direction) at press; pressing during a cast or recovery **queues** the ability (§4.3) |
| **Shift** | dodge roll: 4 m over 0.4 s along input, **Evading** 0.3 s, 4 s cooldown; **interrupts** any cast or recovery and clears the queue |
| Space jump · E interact · R mount (later) · I inventory · J writs · M map · Enter chat |
Casts show a bar; moving cancels a cast unless the ability is `cast_while_moving`. **There is no global cooldown.** One **resource** pool (owner, 2026-10-18, #2): the same rules for every kit, named by the kit (stamina / focus / mana); swapping weapons keeps the current value. 100 max, regenerating 10/s out of combat and 4/s in.

### 4.2 Resolution kinds (every ability declares exactly one)
| Kind | Judge | Validates | Latency | Already have |
|---|---|---|---|---|
| **TARGETED** | module, in the `cast` reducer | queue slot or idle, cooldown, resource, phase, target alive and attackable, range from rows, facing cone 120°; **no LoS in v1** | 2L + 25 | statuses + timers (M2), server-timed checks (M4) |
| **HITSCAN** | sidecar referee | rewind ≤ 150 ms, favour attacker; cone or line against mirrored player/NPC colliders | 2L + 40 | the referee's judged abilities (M5, 0.40.0): reach, radius and height today; cone and line are new |
| **PROJECTILE** | sidecar, as a moved thing | spawned at release; `body_state` rows; contact → `hit` | 2L + 40 | bodies the referee moves (M13, 0.49.0) |
| **GROUND_AOE** | sidecar | placed at the reticle hit on the walkable mask (or at own feet if `self_centred`); fires after `delay`; volume test | 2L + 40 | DiscGolf's Bounce Pad and Leaf Blower (its genre code; M16 is not in the template) |
Abilities flagged `needs_los` are TARGETED abilities the referee re-judges with a line test before the Effect applies; v1 ships none. Self-movement abilities (Charge, Disengage, Gale's knockback) are **server-issued impulses** — `push` rows the client applies, the module widening the envelope — the template's pushes (M15, 0.51.0). Blink is an Effect of kind `teleport` the module validates against the walkable mask and a max distance. Players are never server-moved.

### 4.3 The pipeline (one for players and NPCs) and the cast queue
`Ability → Effects → Statuses / Stats`. The only difference between a player and an NPC is who issues the trigger: a client calls `cast`, a brain calls `npc_cast` (authority-only). Same rows, same validation, same log.
- **`EffectDef`** (content, the atoms): `damage{base, scaling}`, `heal`, `apply_status{status_id, duration}`, `remove_status`, `impulse{vector, frames}` (a `push` row), `teleport{max_m}`, `spawn{entity_def}`, `stat_mod{stat, add, mult, duration}`, `yield{item_id, n}` (harvests use the same atoms). Effects compose; an ability lists them in order.
- **`AbilityDef`**: `kind` (§4.2), `cast_s` (0 = instant), `recovery_s` (the animation lock after release; a basic's recovery is the kit's attack speed), `cooldown_s`, `cost`, `queueable`, `interrupts` (dodge: true), `range_m`, `cone_deg` or `radius_m` or `projectile{speed, gravity, lifetime}`, `delay_s`, `effects[]`, `self_effects[]`, `cast_while_moving`, `needs_los`, clip ids (`act.cast_*`, `act.release_*`).
- **The cast queue** (replaces a GCD): `cast_state{entity_id, current, phase (cast|recovery), ends_at, queued}` holds **one** queued ability (depth is a hot rule). A `cast` that arrives during a cast or recovery is stored, not rejected; pressing another replaces it; dodge or a stun clears it. When `ends_at` passes (a scheduled reducer, M4's clock), the module **re-validates the queued ability at that instant** — cooldown, resource, range, target — and fires it; the effects of a timed cast apply at `cast_complete`, not at press. Pacing comes from cooldowns (6–30 s) and resource: casting everything leaves you empty for ten seconds, which is the intended rhythm. A side benefit: the queue hides RTT — the next ability fires on the server the tick the previous one ends, with no round-trip gap, so chaining feels identical at 30 and 120 ms.
- **Statuses** reuse M2: Stunned, Slowed, Rooted, Weakened, Evading, Knocked Down (from a body's contact: DiscGolf's genre has it, the template does not yet), Burning (ticking damage), Shielded, Kneeling (duels).
- **Stats** = base (humanoid profile) + wearables + statuses → the `stats` **view**: `hp_max, res_max, power, defense, speed_mult, gather_speed`. Current `hp` and `res` are state rows. 2.0 views are subscribable and computed server-side, so there is no denormalised column to keep in sync; **fallback** if the pinned version lacks sender-aware views is a `stats` row recomputed in the equip/status reducers (§13 #5).
- Damage (hot): `dmg = base × (1 + power / 100) × 100 / (100 + defense)`, ±5% roll, crit 10% × 1.5 later.

### 4.4 The three kits (content; every number hot; cooldowns do the pacing)
| Kit | Basic (TARGETED) | Rank 1 | Rank 3 | Rank 6 | Rank 9 |
|---|---|---|---|---|---|
| **Sword & Board** | Slash, 2.5 m, 10 dmg, 0.8 s swing | **Shield Bash** — HITSCAN cone 3 m / 60°, Stunned 1.5 s · cd 12 s | **Cleave** — HITSCAN cone 4 m / 120°, 15 dmg to all · cd 8 s | **Rally** — GROUND_AOE self-centred 6 m, heal 20 to party, 1 s delay · cd 30 s | **Charge** — self impulse 10 m toward aim; first contact Knocked Down 1.2 s · cd 15 s |
| **Bow** | Shot, 30 m, 8 dmg, 1.2 s draw | **Aimed Shot** — PROJECTILE 40 m/s, cast 0.8 s, 25 dmg · cd 6 s | **Volley** — GROUND_AOE 5 m, 1.0 s delay, 12 dmg · cd 14 s | **Disengage** — self impulse 6 m backward + Evading 0.5 s · cd 12 s | **Piercing Arrow** — HITSCAN line 40 m through all, 20 dmg · cd 18 s |
| **Staff** | Bolt, 25 m, 9 dmg, 1.0 s | **Fireball** — PROJECTILE 20 m/s with 3 m splash, 20 + 8 splash, Burning 3 s · cd 7 s | **Frost Ring** — GROUND_AOE 4 m, Slowed 40% 3 s · cd 14 s | **Blink** — teleport 8 m toward aim (walkable-validated) · cd 15 s | **Gale** — HITSCAN cone 8 m / 45°, impulse 5 m on everything in it · cd 20 s |
Each kit spans all four kinds plus an impulse or teleport, so the three kits together exercise every path in §4.2. Every ability is `queueable`; recoveries are 0.3–0.6 s so a Bash → Cleave → Charge chain reads as one motion. Ranks 1/3/6/9 (owner, #3). A fourth kit (spear, mace) is content later.

### 4.5 Death, duels, logout
- **Death**: a `Dead` status; release → respawn at the nearest **shrine** after 30 s with **Weakened** (−20% power) 60 s. No item loss, no durability in v1. A party member can **revive** (hold-to-interact 5 s, M3) within 60 s.
- **Duels** (owner, 2026-10-13): `duel_request` → `duel_accept` sets both `attackable_by` each other and fixes the **dueling area**: a 30 m-radius circle centred on the midpoint at accept, drawn on the ground for both. Neither can drop below **1 HP** from the other; at 1 HP the duel ends, the loser gets **Kneeling** (3 s, `react.kneel`, uninterruptible), the winner a `cheer` callout, and `duel.result = knelt`. **Leaving the area** starts a 3 s warning; still outside → the duel ends with `result = forfeit` and **the one who left is the loser**, no kneel. Both outcomes write `duel_result` and bump `character.duel_wins / duel_losses`; 30 s before either can duel again. A **contested zone** (flag on entry, full PvP, real death) is a later toggle on the same `attackable` rule. Tier A movement is enough for PvE and duels; ranked PvP waits for the `sim_authority = SIDECAR` flag.
- **Logout**: the entity lingers 10 s (30 s if in combat, hot) then despawns; `character_state` persists position, hp, res, kit, equipment, tools, writs, mastery. Login re-spawns it there; if the spot is no longer standable (world edit), the nearest shrine.

## 5. The world
- **One `world_id`** for the overworld; dungeons are extra worlds (M8: not built yet). Positional rows carry **`chunk`**, a 64 m cell index from x/z: new tables have it from the start, and the template's existing ones (`movement_state` and the other rows that place an entity) gain it in a **template 1.0** (owner, 2026-10-18; §11). The v1 zone is ~1 km² = **16 × 16 cells**.
- **Interest management (M18)**: a client holds nine single-chunk subscriptions (the 3 × 3 around it), swapped at the cell edge with 4 m hysteresis — or one OR'd query if the pinned version's subscription grammar allows it. Chunked rows: `position`, `body_state`, entity presence, `npc_state`, `node_state`, `loot_drop`, equipment visuals. Not chunked: own inventory, writs, party, chat, minigame sessions (RLS as now). A sender-aware `nearby` **view**, if supported, replaces client-side swapping (§13 #5).
- **Streaming (M19, client)**: scene cells instanced in a 5 × 5 ring around the player, unloaded with hysteresis; terrain, props and `LevelPoint`s are baked per cell. Godot has no 3D world streaming of its own, so this is template work; the bake already knows the cells. Horizon = a low-poly far mesh per 4 × 4 block.
- **`LevelPoint` kinds**: `shrine`, `spawner{brain_id, cap, respawn_s, leash_m}`, `node{node_def}` (§7.1), `vendor`, `writ_board`, `station{recipe_tag}`, `lair`, `dungeon_gate{dungeon_def}`, `town`. All placed with the Level bench; "spawn a test NPC here", "throw a test projectile from here" and "harvest this node with tool tier N" are bench actions.
- **Bake**: walkable mask (exists), `chunk` index, kind-specific standable cells (`can_stand(kind)`, from DiscGolf's design, "Chain Reaction", §9; the template's `can_stand(x, z)` has no kind yet), trees and buildings as the module's bounds and the sidecar's scene. Node objects are static colliders in the bake with a `point_id`. A coarse LoS grid is **not** in v1.
- **Day/night, weather**: *pending #12*; not in the v1 plan.

### 5.1 The Undercroft: a procedurally assembled dungeon (M25, owner 2026-10-13)
The dungeon is the template's replayability test. Rooms are hand-made modules; the layout is generated from a seed on entry; the server never trusts the client to know the layout.
- **`RoomDef`** (content): a greybox scene on a **4 m grid**, rotations 0/90/180/270 only; **sockets** (door markers: cell, facing, width); a baked **module-local walkable mask**; `spawner_slots[]` (allowed brains, counts), `loot_slots[]`, `tags` (entrance / corridor / chamber / treasure / boss), `weight`.
- **`DungeonDef`** (content): the room pool, a **graph recipe** (entrance → 3–6 chambers with corridors → boss; 0–2 treasure side rooms), size bounds, the time cap, the loot pool.
- **Generator** (module, Rust, deterministic from `seed`): build the room graph from the recipe, then place rooms on the grid by socket matching with backtracking; reject overlaps; cap unused sockets with `wall_cap` modules; guarantee entrance → boss connectivity. Writes `dungeon_layout{world_id, seq, room_def, cell, rot}` rows and spawns from the slots with seeded brain choice. Generation is a few milliseconds and happens inside `enter_dungeon`. **No parity model**: the client and the sidecar instantiate the scene from the rows, so only the module generates. The new foundation piece is **mask composition** — the module assembles the dungeon's walkable mask from the modules' local masks and grid transforms so Tier A validation works in a world that was never baked whole.
- **Variety in v1**: layout, which brains fill each slot, which loot pool rolls. **Later**: one **affix** per run (Dark: no minimap; Hasted: NPC cooldowns −30%; Overgrown: node slots in rooms), rotating boss pool, a daily seed so parties compare runs.
- **Room bench** (a Workbench): socket gizmos, "generate with seed N" preview with the composed mask overlaid, "walk a bot entrance → boss" test action.
- **Entry**: `enter_dungeon(gate)` → the module spawns a world from the `DungeonDef` with the overworld's `sim_authority`, generates, teleports the party (≤ 4), starts the 20 min timer; the sidecar picks the world up as another (M8, to build). Leaving or timing out returns everyone to the gate. Boss loot drops to all four; chest loot per §6.4.

## 6. NPCs
### 6.1 Tiers by presence (the LOD)
| Tier | Runs in | What | Ticks | Enter when |
|---|---|---|---|---|
| **0 — Ambient** | module (scheduled reducers) | spawners, respawn timers (NPCs and nodes), vendors and writ-givers, grid wander on the baked walkable cells, grazing | 1 Hz, or on event | default; no player within 200 m |
| **1 — Awake** | sidecar | perception, threat, pathing, abilities via `npc_cast`, flee | every physics tick | a player within 200 m (the 3 × 3 ring ± hysteresis), or hit |
| **2 — Dormant** | nowhere | frozen; the row keeps its last position | — | no player within 400 m for 30 s |
An empty world ticks nothing. Promotion/demotion is the sidecar's call (it already subscribes to the whole world); the module only runs Tier 0 schedules, which are skipped for dormant spawners.

### 6.2 `BrainDef` (content, on top of `CharacterDef`)
`tier_rules{awake_m, dormant_m, hysteresis_s}`, `perception{range_m, fov_deg, hearing_m}`, `threat{decay_s, taunt_mult}`, `leash_m`, `pack{size, spread_m}`, `ability_ids[]` (**the same `AbilityDef` rows players use**, including the cast queue), `behaviour` (chase / kite / flee / guard / patrol), `loot_table_id`, `kit_xp`, clips. Threat is a sidecar-local struct; the authoritative `target` is a row so clients can draw the aggro arrow.

### 6.3 v1 cast (six)
| NPC | Brain | Abilities | Proves |
|---|---|---|---|
| **Wolf** (pack of 3) | chase; Fowl Play's predator brain adapted | Bite (TARGETED), Lunge (self impulse) | brain reuse across games |
| **Deer** | flee; grazes at Tier 0 | none | a non-combat brain and the hearing model |
| **Bandit Archer** | kite at 15–25 m | **the Bow kit's** Shot and Aimed Shot | NPCs use player kits unchanged |
| **Bandit Brute** | chase, guard the camp | **the Sword kit's** Slash and Shield Bash | same, and the cast queue on an NPC |
| **The Marsh Warden** (lair boss) | guard the lair; three phases by HP | Cleave, Frost Ring, Gale, plus a GROUND_AOE slam | all four kinds on one NPC; a boss-phase pattern |
| **Quartermaster / Writ clerk** | Tier 0 stationary | interact (hold) | vendors and writs are NPCs, not UI |
The Warden's model is the animal pack's bear if it has one, else a KayKit skeleton (§14). Bandits are UAL humanoids wearing the players' own wearables — the Equip bench dresses them. The Undercroft's slots draw from the same six plus skeleton variants when the asset is verified.

### 6.4 Spawners, loot, bots
- **Spawners** are Tier 0: a scheduled reducer per spawner (or one sweep at 1 Hz) keeps population ≤ `cap`, respawning `respawn_s` (60–180 s) after a death, skipped while dormant. Node respawn is the same sweep (§7.1).
- **Loot** is *pending #7*; the recommendation the body assumes is **personal**: on death the module rolls `LootTable` once per contributing player (damage ≥ 5%) and writes `loot_drop` rows under RLS; 2 min to take, then gone.
- **Bots**: no bot players in the MMO, but a **load harness** of 300 bot clients walking chunk-to-chunk, casting basics and harvesting is M18's acceptance test, and a bandit camp of bots is the combat soak.

## 7. Working the world: nodes, minigames, items, economy
### 7.1 Nodes, OSRS-style (owner, 2026-10-13)
A node is a **static world object** — a tree, a vein, an herb patch — placed by the Level bench and present in the bake, with persistent state that everyone shares.
- **`NodeDef`** (content): `skill` (Woodcutting / Mining / Herbalism), `tier`, `tool_tag` + `min_tool_tier`, `min_mastery` (a gathering rank, from the XP curve: #3), `minigame_id` (§7.2), `yield{item_id, n_by_score}`, `xp`, `deplete_chance` per success (hot, 1/8 for a tree, 1/3 for a vein), `respawn_s` (60–180), `model_ready`, `model_depleted`.
- **`node_state{point_id, state: Ready | Depleted, respawn_at, harvesters}`**, chunked, so a depleted tree is a stump for everyone within the ring and comes back at the same instant for all. Many players harvest the same node at once (`harvesters` is a count, not a lock); a depletion roll by any of them depletes it for all.
- **Loop**: stand within 2 m, press **E** with a tool of the right tag and tier **in your bag** (owner, 2026-10-18, #15: no tool slot, OSRS-style; the best matching tool is used, shown in the hand only while the minigame runs, then the weapon comes back) — the module checks state, tool, mastery, then opens a **minigame session**. One round = one attempt: a good score yields items and XP by the `n_by_score` table and rolls depletion; a poor one yields nothing and still rolls. The UI loops rounds while the node is Ready and the player stays; moving > 3 m, taking a hit, or the node depleting closes it. Tool tier and gathering rank raise `gather_speed` (round length) and the score→yield table; `gather_speed` is a stat, so wearables and buffs touch it.
- **Respawn** is the Tier 0 sweep: `respawn_at` passes → `Ready`, skipped while dormant (a node in a dormant cell respawns on promotion if its time has passed).
- Nodes are also the generic **interactable**: chests, doors, shrines and crafting stations are `node`s with `skill = none` and an optional minigame (lockpicking later) — one object model for everything you press E on.

### 7.2 Minigames (M26, foundation; owner 2026-10-13: a must)
*An interactive UI that opens in reaction to a button press with the right gear, whose outcome the server derives from the player's inputs — never from a client-reported score.* This is the slot the parity discipline was rescoped for: server-replayed minigame validators.
- **`MinigameDef`** (content): `model_id` (the deterministic model), `params` (difficulty, length, tolerance), `ui_scene`, `duration_s`, `input_hz`, `score_table` (score → yield multiplier), `rtt_credit: bool`.
- **Flow**: `interact(point_id)` → the module validates (§7.1) and writes `minigame_session{id, player, point_id, minigame_id, seed, started_at, deadline}` under RLS → the client opens `ui_scene`, runs the model (**GDScript**) from the seed for immediate feel, and streams **inputs** (`minigame_input_batch`: timestamped presses or samples, batched at `input_hz`, 10–20 Hz) → at the end or the deadline the module **replays** the inputs through the **Rust twin** of the model from the same seed, derives the score, and applies the session's Effects (`yield`, XP, the depletion roll). The score the client shows is a prediction; the server's is the truth; a mismatch above tolerance is logged as a parity failure, not a cheat.
- **Models are pure functions** `score(seed, params, inputs[]) → f32`, written twice (GDScript, Rust) and pinned by **golden vectors** — exactly the discipline that already exists, now with a product. Timing-sensitive models use Fowl Play's per-identity RTT credit so a 120 ms player and a 30 ms player see the same window.
- **v1 models** (owner, 2026-10-18, #17: **three shapes**, one per skill): **Rhythm** — a seeded sequence of 4–8 timing windows whose positions and widths drift; score = presses inside windows, minus misses; the template's server-timed press (M4) generalised to a sequence (Woodcutting). **Tension** — hold to pull a root; a seeded strain curve rises while held and eases when released; score = time spent in the pulling band, and a snap (strain past the top) ends the round with nothing; close to Fishing's reel (Herbalism). **Trace** — a seeded vein path on a grid; the client streams reticle samples; score = time-weighted fraction within tolerance, with a bonus for finishing (Mining). Fishing's cast-and-reel from game 1 becomes a third model when Fishing joins as a skill.
- **Minigame bench** (a Workbench): play any model with any seed; shows the local score and the Rust-replayed score side by side (a live parity check); exports goldens from recorded sessions.
- **Cheat posture**: a bot can play a minigame perfectly; accepted for v1 and bounded by per-node yield caps, depletion, and mastery curves. Timing models cannot be beaten by lag because the server credits only measured RTT. Record it as the open risk it is (§13 #19).
- **Not only harvesting**: the same system opens a lock, tunes a ritual, or sets crafting quality later — any `node` may name a `minigame_id`.

### 7.3 Items, wearables, tools
- **`ItemDef`** (new content: today the template has only the `item_def` table, seeded by `seed_item_defs`, and DiscGolf's items are its genre's code, not content) grows three optional blocks: **`wearable{slot, stat_mods[], passive_effect_ids[], attach_point, visual}`**, **`kit{basic_ability_id, abilities_by_rank, resource_name, mastery_track}`**, and **`tool{tag, tier}`**. A kit is a wearable in the weapon slot; equipping it swaps the hotbar. A tool is **not worn** (#15): it sits in the bag, and `interact` picks the best matching one, so swinging a pick never costs your weapon; the bag's slots are what carrying three tools costs.
- **Slots** (v1): weapon, head, chest, legs, trinket. Mounts take a sixth later.
- **Equipment** is a row per slot (`equipment{entity_id, slot, item_id}`), chunked so others render it; the client resolves `visual` + `attach_point` through the attach system (M6). The **Equip bench** fits each wearable and tool to the UAL rig and to the bandits, with "wear on mannequin, run the walk and the swing" as its test action.
- **Inventory** reuses the template's `inventory_item` (stacks, slots: `grant_item`, `consume_item`, `set_item_slot`) and Fishing's bank if it generalises (stacks, a bank at the town `station`); if not, it is rebuilt once as foundation (M24). Weight is not modelled; slots are (40 bag, 80 bank).
- **Crafting**: `RecipeDef{inputs[], output, station_tag, seconds, min_mastery?}`; `craft` at a station starts a timer status; the output lands on completion. Six recipes in v1 (a weapon per kit, a chest piece, a potion, a better pick). Crafting quality via a minigame is later.
- **Economy**: **marks** are the only currency; vendors buy at 25% and sell at list; prices are a hot table. No player market, no trade window in v1.
- **Potions**: `ItemDef.on_use` is an `AbilityDef` (TARGETED, self, `queueable`) — the pipeline again.

### 7.4 The skilling loop first: dual-mode skills and modular gear (owner, 2026-10-18)
The owner's priority: **nail the workflow from gathering to refining to smithing, then make the combat
really fun.** Reference points he named: OSRS's skilling, Farever's combat, Titanreach's audience, the
best of Albion Online's PvP, Cube World's openness. So the build starts with the skilling loop (chop,
mine, smelt, smith a weapon, fight a wolf with it), ahead of §12's combat-first order.
- **Minigames are immersive to the skill**, not a charge bar or a QTE. **Woodcutting is branch dodge**
  (built, `game/regents/skilling/woodcutting/`): a 2D trunk you chop from the left or the right; a
  branch at your head on your side hits you and staggers you; tiers are branchier and want more logs.
  **Tier bands get their own minigames** (owner, 2026-10-18): woodcutting tiers 1-3 (Tree, Oak, Yew)
  are branch dodge; tiers 4-5 a harder minigame; tier 6 another again, so mastering a skill keeps
  opening more demanding and more rewarding ways to play it. The same for every skill.
  Mining's, Herbalism's, smelting's and smithing's minigames are to be designed to the same bar
  (the Trace and Tension proposals in §7.2 are starting points, not decisions).
- **Every skill is dual-mode**, gathering and processing alike (smelting and smithing too): **AFK**
  (passive, slower, every material including rares) or **active** (the minigame). Active is a modest
  edge so AFK is never a non-option: **1.25x the yield and 1.3x the rare chance** at a good score
  (hot rules `regents.active_yield_mult`, `regents.active_rare_mult`). **Yield = the AFK rate x
  `active_yield_mult` x the round's score** (owner, #23): a good round beats AFK, a poor one falls short.
  **At a node, tap E to work it AFK; hold E to open its minigame** (owner, 2026-10-18). No separate
  meter for active play yet.
- **Gear is modular, Tinkers'-style**: weapons and tools are crafted, not dropped whole, from a **core**
  (axe head, blade: base stats and tier) and a **handle or hilt** (its trait or combat ability). **Gear
  gains XP through use.** **Durability and repair** are the material sink; ways to lose gear (PvP,
  NPC quests) come later. Active smithing raises the crafted part's quality.
- **Open with this**: how a handle's ability sits with "the weapon is the class" and per-kit mastery
  (§4.4, #3), and gear XP beside character mastery (#22).

## 8. Accounts, persistence, social
- **Accounts** (owner, 2026-10-18, #13): **SpacetimeAuth**. An `account` row that several sign-in identities link to (so Steam, through a ticket-to-token bridge, is a link later, not a migration); one account → up to three `character` rows, and the sidecar and admin tools keep their own authority identities. Identity-per-device, as in games 1–3, is not enough once characters outlive devices.
- **Persistence**: `character` (name, account, created, duel_wins, duel_losses), `character_state` (world_id, position, hp, res, kit, weakened_until), `equipment`, `inventory`, `mastery` (per kit and per skill), `writ_progress`. Written on change, not on a timer; the module is the source of truth, so a crash loses nothing committed.
- **Party** (M24): invite/accept/leave/kick, ≤ 4, leader; party rows under RLS; shared XP within 60 m; the party's `attackable` rule is "never". Party frames subscribe to members' `hp`/`res` across chunks (a party-scoped subscription, not a chunked one).
- **Chat**: `say` (your chunk and its ring), `party`, `whisper`, `zone`. Rows with RLS; reuse Fishing's if present. Messages are rate-limited in the reducer (a review item from 0.23.1 made general).
- **Writs** (`WritDef`): `objectives[]` of kind kill{brain_id, n} / gather{item_id, n} / reach{point_id} / craft{recipe_id} / talk{npc} / duel{wins}; `reward{marks, mastery_xp, item?}`; `prereq`. Progress rows under RLS; objectives advance from the events the pipeline already emits (`hit`, `loot_drop`, `yield`, craft, `duel_result`). Six writs in v1, in a chain.

## 9. What it tests for the template (beyond games 1–3)
| System | Games 1–3 | Regent's Rule |
|---|---|---|
| Persistence | match-scoped; Fishing's profile | **a character that outlives sessions and devices**; accounts |
| World | one world per match, loaded whole | **one persistent seamless world**, chunked subscriptions, client streaming |
| World objects | props | **stateful, shared, respawning nodes** with their own LevelPoint kind and Tier 0 lifecycle |
| Scale | ≤ 8 | **100–300 CCU in one database**; the 300-bot harness; dormancy LOD |
| Authority split | sidecar judges / moves things | **the module resolves TARGETED, the sidecar the spatial kinds** — one content field decides the judge |
| Abilities | per-character, hand-wired | **Ability → Effect → Status pipeline as content**; a **cast queue** instead of a GCD; NPCs cast the players' abilities |
| Minigames | one server-timed skill check | **a minigame system**: UI as content, inputs streamed, **server replay through a Rust twin**, goldens — the parity discipline's designed-for case |
| Procedural | seeded variety on one map | **layouts assembled from modules by a seeded generator** in the module; **runtime mask composition** for Tier A in an unbaked world |
| Stats | hard-coded profiles | **a subscribable view** over base + wearables + statuses |
| Items | hold one, use | **wearables and tools with slots, stats, passives, visuals**; kits that are classes; crafting |
| NPC | brains per game | **tiered brains**, spawners in the module, threat, leash, boss phases |
| Worlds | one, or per match | **instances inside a persistent world** (M8 reused for dungeons) |
| Social | lobby | party, chat scopes, duels with an arena and a recorded result |
| Not used | — | carry, physics comedy, first-person, asymmetry, team collision. The foundation should run clean without them. |

## 10. Authority, hosting, latency
- **Posture**: people move themselves (Tier A: speed envelope + walkable mask + `can_stand(kind)`, composed at runtime in dungeons); the **module** judges TARGETED, runs the cast queue, generates dungeons, replays minigames and owns every persistent row; the **sidecar** judges HITSCAN / PROJECTILE / GROUND_AOE, moves projectiles and placed effects, and runs Tier 1 brains; the server pushes people only through **`push` rows**. `sim_authority = SIDECAR` stays a per-world flag, exercised by the CI job proposed in DiscGolf's design §13 (`sidecar_world_test.sh`, not built yet).
- **One sidecar process per world**; several worlds per process via M8 (the dungeons ride along). If NPC CPU ever needs it, two processes split the overworld by area inside the same database — NPC ownership is fixed to spawn area and the leash keeps them there; no database change.
- **Hosting** (*pending #10*; owner's stated preference is option 1): the database on **Maincloud**; the sidecar on a small VPS **in Maincloud's cloud region**, gated by a measured WebSocket RTT to `maincloud.spacetimedb.com` of **< 5 ms** (then the sidecar path is ≈ 2L + 42 ms, within noise of colocated). If no region measures under 5 ms, self-host both on one box as Fowl Play does. Never a cloud database with a home sidecar (≈ 4L). A connected sidecar keeps the database awake, so energy accrues continuously; Tier 2 dormancy means an empty world costs only the connection. Minigame replay and dungeon generation are module CPU — energy, but small and bursty.
- **Latency budget**: TARGETED 2L + 25; the cast queue removes the round trip between chained abilities; aimed kinds 2L + 40 under a cast animation; minigame outcomes arrive once per round (RTT-insensitive except for timing models, which credit RTT); the local player never feels authority latency (predicted, never corrected). Victims of aimed hits see them ~RTT late — acceptable in PvE and duels; record it.
- **Cheat posture**: Tier A bounds speed, teleport and standing; the module validates every TARGETED input against rows and every minigame against replayed inputs, never against client-reported outcomes; the referee rewinds the aimed kinds. Good enough for PvE; the reason PvP stays small until the SIDECAR flag is tuned.

## 11. Scale: the numbers and the discipline
- **Fan-out, not CPU, is the wall.** Tier A at 20 Hz is 20 rows/s per *moving* player (idle players write nothing). 300 CCU, 3 × 3 chunks, ~30 nearby: ≈ 180k row deltas/s outbound at everyone-moving worst case, ~60k typical. Minigame input batches add ≤ 20 rows/s per harvester, RLS-scoped so they fan out to one. The sidecar takes the whole world: ≤ 6k rows/s in. All comfortable for one database; a flat subscription at 300 would be ~1.8M/s and is the thing M18 forbids.
- **Chunk 64 m / 3 × 3** is the first guess; the 300-bot harness tunes it (sub swaps per minute vs rows per client).
- **Split-ready, not split** (the schema rules, enforced by a lint):
  1. every table carries `world_id` (already) and is annotated **`global`** (account, character, inventory, mastery, writs, party, chat, duel_result) or **`regional`** (position, body_state, npc_state, node_state, loot_drop, equipment visuals, spawner_state, cast_state, minigame_session, dungeon_layout);
  2. no reducer joins across `world_id`; moves go through one `transfer(entity, from_world, to_world)` reducer;
  3. positional rows carry `chunk` (the template's existing ones from its 1.0: a reshape, so every game's database is wiped once and older builds stop connecting; chosen over an `entity_chunk` side table joined into every subscription);
  4. the sidecar never assumes it is the only sidecar (ownership by area, from day one).
  With these, a second region later is a mechanical move of the `regional` tables plus a BitCraft-style global/region bus — a milestone, not a rewrite. It is not expected to be needed.

## 12. Implementation plan (steps; each ends playable)
Rides on `FOUNDATION_SYSTEMS` M1–M7 and M9–M15 (built, 0.51.1); **M8** (a world per match) and **M16** (items, lifted from DiscGolf's genre) are still to build in the template, with **M18–M26**, which are new template work; the **template 1.0** (`chunk` on the existing positional tables) comes before step 3.

| # | Step | Rides on | You can play |
|---|---|---|---|
| 1 | **The fight**: `EffectDef`/`AbilityDef`/kits as content, `cast` with TARGETED in the module, the **cast queue** and resource, `target` and the soft target, the `stats` view (or row), one kit (Sword), a greybox field, a training dummy that hits back (a minimal Tier 1 brain) | **M20 ability/effect pipeline + cast queue**, **M21 stats view**, M2, M4 | two players and a dummy trade blows; Bash → Cleave → Charge is one motion; numbers are correct |
| 2 | **The aim**: HITSCAN through the referee, PROJECTILE as `body_state` bodies, GROUND_AOE, impulses and Blink; Bow and Staff kits; dodge/Evading as the interrupt | M5, M13, M15, M20 | all three kits, every kind; skill shots miss and land |
| 3 | **The world**: `chunk` on positional rows (the template 1.0), nine-subscription swapping, 1 km² greybox streamed in cells, `can_stand(kind)`, accounts + `character_state` persistence, log out and back in | **M18 interest management**, **M19 streaming**, **M23 accounts & persistence** | walk the zone with friends; leave; return where you stood; **300 bots pass** |
| 4 | **The wild**: tiers, spawners in the module, perception/threat/leash on the sidecar, the six NPCs, loot, death and shrines | **M22 tiered brains + spawners** | hunt, die, respawn, loot |
| 5 | **The work**: `NodeDef` + `node_state` with depletion and respawn, the best tool in the bag, **the minigame system with the Rhythm, Trace and Tension models and their goldens**, the Minigame bench, gathering mastery, six recipes, vendors and marks, the six writs | **M26 minigames**, **M24 items & social** (first half), M3, M6 | chop, mine, pick; the server's score matches yours; gear up; finish the writ chain |
| 6 | **The company**: party, chat scopes, revive, the lair, **the procedural Undercroft** with the Room bench and `dungeon_gen_test`, duels with the arena, kneel and forfeit | **M8** (to build), **M25 procedural assembly**, M24 | an evening with four friends; two runs of the Undercroft that differ |
| 7 | **Feel**: UAL combat, kneel and harvest clips via the benches, bandits dressed by the Equip bench, town and wild art, music, recording | M11, M12 | the first real playtest |
| 8 | Then: a contested zone, dungeon affixes and a daily seed, Fishing as a skill (game 1's model as a minigame), mounts (animals), a fourth kit, lockpicking and crafting quality through minigames, a second zone in the same database, player trade; the first region split only if a ceiling is ever hit |

### Content and tables (no shape changes to existing tables, except `chunk` in the template 1.0)
- **Content**: `EffectDef`, `AbilityDef`, `ItemDef` + `wearable` / `kit` / `tool` blocks, `BrainDef`, `LootTable`, `RecipeDef`, `WritDef`, `NodeDef`, `MinigameDef` + models (GDScript + Rust, goldens), `RoomDef`, `DungeonDef`, `LevelPoint` kinds (§5), `game/regents_rule/content/rules/regents_rule.tres` (queue depth, recoveries, resources, damage, respawn, chunk, tiers, prices, depletion, duel radius).
- **Tables**: `account_character`, `character`, `character_state`, `equipment`, `inventory` (the template's `inventory_item`), `mastery`, `target`, `cast_state`, `cooldown` (or M2 timers), `hit` (append-only: attacker, victim, ability, amount, kind, at), `npc_state`, `spawner_state`, `node_state`, `loot_drop`, `minigame_session`, `minigame_input` (append-only, batched), `dungeon_layout`, `writ_progress`, `party`, `party_member`, `chat_message`, `duel`, `duel_result`, plus the template's `body_state` (M13) and `push` (M15). `stats` is a view.
- **Reducers (player)**: `set_target`, `cast(ability_id, target_id?, aim_origin?, aim_dir?)` (queues when busy), `cancel_cast`, `dodge`, `equip`, `unequip`, `interact(point_id)` (opens a minigame or a plain hold), `minigame_input_batch(session_id, inputs[])`, `minigame_leave`, `craft`, `buy`, `sell`, `accept_writ`, `turn_in_writ`, `release` (respawn), `revive`, `party_*`, `chat`, `duel_request`, `duel_accept`, `enter_dungeon`, `leave_dungeon`. **Authority-only**: `npc_cast`, `npc_state_batch`, `hit`, `apply_effect`, `spawn_npc`, `despawn`, `promote_tier`. **Scheduled**: `cast_complete` (queue + timed casts), `spawner_sweep` (1 Hz; NPCs and nodes), `tier0_wander`, `status_expiry` (M2), `linger_despawn`, `minigame_deadline`, `duel_boundary_check` (1 Hz while any duel is live), `dungeon_timer`.

## 13. Open items
The owner went through #1, #2, #3, #13, #15, #17 and the chunk schema (#21) on 2026-10-18; the body says the decision where it applies. Still open: #7, #10, #12. Where the body needs one of those, it uses the recommendation and marks it *pending*; nothing pending is assumed.
| # | Item | Recommendation, or the decision | Decides |
|---|---|---|---|
| 1 | **Universe**: Hollow Hill or new | **a new fantasy setting**; Hollow Hill animals reused as assets, not lore | **Owner — decided 2026-10-18** |
| 2 | Resource model | **one 100-point pool, the same rules for every kit, named by the kit** (stamina / focus / mana); a weapon swap keeps the value | **Owner — decided 2026-10-18** |
| 3 | Mastery: ranks, unlock placement, gathering curve | **v1: 10 ranks per kit and per skill** (15 acceptable; production will go higher, so XP is stored and the rank comes from a content curve); **abilities at 1/3/6/9**; **node tiers need both a gathering rank and a tool tier** | **Owner — decided 2026-10-18** |
| 4 | Dodge i-frames | Evading 0.3 s as a status the referee checks at rewound time; dodge interrupts and clears the queue | Agent |
| 5 | Views | verify sender-aware subscribable views in the pinned version for `stats` and a `nearby` view; fall back to a `stats` row + client-side subscription swapping | Agent |
| 6 | LoS | none for TARGETED in v1; `needs_los` referee-judged when an ability wants it | Agent |
| 7 | Loot | personal, per contributing player | **Owner — open** |
| 8 | Logout linger | 10 s, 30 s in combat | Agent |
| 9 | Chunk size and ring | 64 m, 3 × 3 subscribed, 5 × 5 streamed; tune with the 300-bot harness | Agent |
| 10 | Hosting gate | measure Maincloud RTT from candidate VPS regions; < 5 ms → option 1, else self-host both | **Owner — after measurement** |
| 11 | Bandits use player kits | yes, same `AbilityDef` rows | Agent |
| 12 | Day/night, weather | — | **Owner — open** |
| 13 | Account provider | **SpacetimeAuth**; an `account` that several identities link to, Steam linked later through a bridge; verify its sign-in providers and self-hosted support before step 3 | **Owner — decided 2026-10-18** |
| 14 | Inventory | the template's `inventory_item` (stacks, slots); Fishing's bank if it generalises; rebuild once as foundation if not | Agent |
| 15 | Tool slot | **no tool slot: the best matching tool in the bag is used** (OSRS-style), shown in the hand only during the minigame; five equipment slots | **Owner — decided 2026-10-18** |
| 16 | Cast queue depth and replace rule | depth 1; a new press replaces the queued ability; dodge and stuns clear it | Agent |
| 17 | v1 minigame models | first answer: three shapes, Rhythm (Woodcutting), Trace (Mining), Tension (Herbalism). **Revised the same day: minigames are immersive to their skill; Woodcutting is branch dodge** (built); Mining, Herbalism, smelting and smithing are to design to that bar (§7.4) | **Owner — decided 2026-10-18 (woodcutting); the rest open** |
| 18 | Dungeon generator approach | socket-stitch on a 4 m grid with a graph recipe and backtracking; affixes and a daily seed later | Agent |
| 19 | Minigame cheat posture | accept scripted play in v1; bound by yield caps, depletion, mastery curves; revisit if it shows | Agent |
| 20 | Duel area | 30 m radius at the accept midpoint; 3 s grace outside | Agent (owner set the rule) |
| 21 | `chunk` on the template's existing positional tables (`movement_state` and the others that place an entity), which rule 17 forbids reshaping within a major version | **a template 1.0 reshape**: add the column, wipe every game's database once, older builds stop connecting; chosen over an `entity_chunk` side table joined into each subscription. When, and what else 1.0 folds in, is still to plan (around Fowl Play's and DiscGolf's playtests) | **Owner — decided 2026-10-18** |
| 22 | Modular gear and the kits: does a handle's ability replace, add to, or choose among a kit's ranked abilities; how gear XP sits beside per-kit mastery | to propose with the combat round | **Owner — open** |
| 23 | AFK and active: how a minigame score maps to yield; how a player picks the mode | **yield = AFK rate x `active_yield_mult` x score** (a poor round falls below AFK); **tap E = AFK, hold E = the minigame**; no meter yet | **Owner — decided 2026-10-18** |

## 14. Assets (CC0 only unless noted; verified items are from the 2026-10-13 pass, others marked **verify**)
| Need | Source | Note |
|---|---|---|
| Humanoids + locomotion + combat | Quaternius UAL1 (45 free) and UAL2 (~90 free: combat, parkour, farming, fishing); KayKit Adventurers (75 clips incl. Hit, Dodge, Cheer) | one artist per game; UAL has the combat clips free, so UAL here |
| Kneel / surrender, chop, mine, pick | UAL2 farming set for harvest clips **verify**; kneel in UAL1/2 **verify**, else KayKit `Cheer`/`Hit` family or a short custom clip | the duel's `react.kneel` is one clip |
| Weapons and tools (sword, shield, bow, staff, axe, pick, sickle) | KayKit Adventurers props **verify**; else procedural like the disc | — |
| Wildlife | Quaternius Ultimate Animated Animal Pack (wolf, fox, deer…); bear **verify** | Fowl Play's wolf as-is |
| Bandits | UAL humanoids wearing player wearables | the Equip bench dresses them |
| Dungeon room modules, skeletons | KayKit Dungeon (remastered) and KayKit Skeletons **verify** | modules are re-cut onto the 4 m grid in the Room bench |
| Trees, veins, herbs (ready + depleted states) | Quaternius Stylized Nature MegaKit (in use); Kenney Nature Kit; stumps and spent veins as greybox swaps first | — |
| Town and wild | Kenney medieval / castle kits **verify** | — |
| UI / icons / fonts | Kenney UI Pack + Game Icons; Google Fonts (OFL) | minigame UIs are Control scenes, no art dependency |
| SFX / music | Kenney Audio; freesound CC0 filter (swords, bowstring, spell whoosh, axe, pick, chains) ; FreePD or the synth pipeline | — |
Avoid: Sketchfab "free" (CC-BY, heavy), Mixamo (not CC0). Every import goes through the workbench's intake so `ATTRIBUTION.md` is written even for CC0.

## 15. Keeping it split-ready, sidecar-flag true, and deterministic
- **`schema_partition_lint`** (CI): every table annotated `global`/`regional`; no cross-`world_id` joins outside `transfer`; every positional table has `chunk`. Fails the build.
- **`load_300.sh`** (CI, nightly): 300 bot clients on the 1 km² greybox for 10 min, moving, casting and harvesting; asserts rows/s per client, sub swaps per minute, p95 reducer time, and sidecar inbound rate against hot thresholds.
- **`minigame_goldens`** (CI, every build): each model's GDScript and Rust twins against the fixture set (float32, zero tolerance), plus replay of recorded bench sessions.
- **`dungeon_gen_test`** (CI, every build): 1,000 seeds through the generator; asserts connectivity entrance → boss, no overlaps, every socket matched or capped, the composed mask contains every room's floor, p95 generation time.
- **`sidecar_world_test.sh`** (proposed in DiscGolf's design §13, never built: build it here) runs the zone and a generated Undercroft as SIDECAR worlds with the bandit camp as bots.

## 16. Playtest one — questions and measures
| # | Question | Measure |
|---|---|---|
| 1 | Does targeted feel instant and aimed feel fair? | hit-confirm latency by kind; miss rate by kind; survey |
| 2 | Does chaining feel like a MOBA — burst, then wait? | abilities per 10 s window distribution; queue use rate; time-at-zero-cooldowns; survey |
| 3 | Is "the weapon is the class" legible? | kit switches per session; ability-use spread per kit |
| 4 | Fan-out reality | rows/s per client, sub swaps per minute, bandwidth at 100 / 200 / 300 bots |
| 5 | Projectile prediction | visual-offset distribution at 80 / 150 ms; snaps per hour |
| 6 | Do the minigames feel like play, and does the server agree with the client? | rounds per node visit; abandon rate; local-vs-replayed score delta distribution (must be ≈ 0); survey |
| 7 | Do two Undercroft runs feel different? | layout similarity between consecutive seeds; "felt the same" survey; time per run |
| 8 | Are tier transitions visible? | pop-in reports; Tier 1 NPC count over time |
| 9 | Persistence trust | logout/login position or HP mismatches (must be 0) |
| 10 | Does death cost enough, and does a kneel land? | deaths per hour; time to re-engage; duels per session; forfeit rate |
Scope: one greybox zone, one kit, TARGETED + one HITSCAN with the cast queue, the wolf and the dummy, one node type with the Rhythm model, death and shrines, log out and in, 2–4 humans, 300 bots in the background. Bots soak 1,000 kills and 1,000 harvest rounds first; the balance sim reports time-to-kill by kit and NPC and yield per hour by tool tier.
