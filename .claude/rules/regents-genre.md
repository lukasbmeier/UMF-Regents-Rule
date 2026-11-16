---
paths:
  - "game/regents/**"
  - "server/src/game/regents.rs"
  - "server/src/genre/regents/**"
  - "server/build/regents.rs"
  - "server/tests/regents.rs"
  - "shared/content/regents/**"
  - "sidecar/npc/brains/regents/**"
  - "docs/regents_rule/**"
---
# Regent's Rule's standing rules (Luke's decisions; `GAME.md` has the full list and dates)

- Scale is 100-300 CCU per database, one seamless world. Design every per-player cost for 300.
- The skilling loop comes first, then fun combat. Every skill is dual-mode: tap E works AFK, hold E
  plays its minigame, paying from AFK x 0.75 (a score of 0) to AFK x 1.25 (a full score), rares up to 3x
  with the score (Luke's M11, PROGRESS 46); gathering and smelting rounds run back to back. Those numbers
  are hot rules (`game/regents/content/rules/regents.tres`, `regents.*`), never constants.
- No tool slot: the best matching tool in the bag is used. Five equipment slots: weapon, head, chest,
  legs, trinket. The weapon you hold is your class (its kit).
- Mana is on the Staff only (Luke reversed the one-pool decision on 2026-10-20); a resource never
  ticks (#270). Melee is paced by its combo and the roll, the bow by its arrows.
- No global cooldown: each ability has its own; the cast queue only buffers a press. Melee never
  rolls to hit; the bow and the Staff do.
- Mastery: XP stored, rank from a content curve: EVERY skill 1-33 for now (Luke's S1 + S2, 2026-11-13, a third of
  99; the old ranks 1-10 mapped to 1, 5, 8, 12, 15, 19, 22, 26, 29, 33 with their XP unchanged; finalized before the
  public demo, with a wipe). The top is `rules::RANK_TOP` / `SkillDef.RANK_TOP` and every curve ends there (both
  suites check); mastery's share (`mastery_bp`: damage, tool speed) is 27 % at the top, an even step a rank. Harder
  nodes need a gathering rank AND a tool tier.
- A PLAYER'S ABILITIES OPEN ON THE ITEM (PROGRESS 74, Luke's B1-B6): an item's XP and picks are its bag row's
  `instance_data` (`"x"`, `"k"`), never a side table, and EVERY writer of `instance_data` keeps them (`keep_level`, as the
  refit does). The kit's layout is content (`KitDef.skill_slots`, `unlock_levels`); the server gates by `need_slot`
  (`KitSeed::slot_refusal`) and the client's twin is `RegentsItemLevel`: change both together. Combat XP goes through
  `train` (the holder and the wielded weapon, catch-up), never `add_xp` alone.
- A WEAPON KIT'S SKILLS ARE A POOL (PROGRESS 91): `skill_slots`: one base, options, ults; more than four allowed; with
  an ult the last pick takes only the ult. Every placeholder ability is named `... (placeholder)` and says
  PLACEHOLDER in its `designer_notes`. Ability ids to 40048 and spell 40009 are taken.
- Items: three grades; Power is the number; a trait changes how an item plays and never its Power,
  and every trait trades (#275, `LOOT_AND_STYLES.md` §2, §6). Materials and modular gear:
  `docs/regents_rule/MATERIALS.md` (2026-10-23; crafted items hold Common 1 / Fine 2 / MW 3 traits, picked).
- The server judges every swing, round and roll from inputs; the referee (sidecar) runs the foes.
- `chunk` comes to the template's positional tables in the template 1.0 reshape, not a side table:
  never add a chunk side table here.
- The client has RING interest (`game/regents/regents_net_config.tres`, PROGRESS step 22). A new table of
  ours that describes a placed thing: `world_id` and an indexed `chunk` (set at insert: `place_of`,
  `chunk_of_entity`; an event `cell::chunk_of(pos)`), moved in `follow_place` if it follows an entity, listed
  in the net config's `cell_tables` (and `follow_tables` when a player's) and in `genre.tres` `world_tables`.
  The regents suite fails a table with a chunk that is not a cell table.
- The continent (level 21, PROGRESS step 23) is GENERATED: never hand-edit `continent.tscn`, its
  `continent_cells/` or `terrain/`; change `continent_shape.gd`, `build_continent.gd` or the map and run
  `build_continent.tscn` (it bakes too), then publish. Its node and skeleton placement is a TEST one: Luke's
  own replaces it. The glade (level 20) stays the suites' level and a fresh database's.
- Still open, Luke's to decide (never default): #12 day/night, the other skills' minigames, how the
  minimap grows, what is still open in `MATERIALS.md` §11. The order of work: `GAME.md`. (#7 loot and #22 handles are settled:
  `GAME.md`.)
- THE GLADE'S LOOK (PROGRESS step 59): a NEW NATURE MODEL (`game/regents/art/nature/`) gets `nature_import.gd` as its
  import script (the suite names one that has not). The glade's ground is painted from its markers (`GroundPaint`:
  a station, a child Path3D or Marker3D wears it; a gathering node sits in soil) and its grass is `Clutter`'s
  MultiMeshes: never hand-place grass, flowers or pebbles as nodes. Both are flat-ground only; the continent has
  neither yet. A check of where clutter stands reads `places_in`, never the MultiMesh (headless keeps no transforms).
- The weapon and tool GRIPS (`*_grip.tres`, `*_grip_preview.tscn`) are Luke's to fix himself: never
  restore, rewrite or commit his edits to them; ask.
- A content change publishes (`tools\publish.cmd`): the server takes content from the bake.
- A FOE STAGGERS BY POISE (Luke, 2026-11-02, PROGRESS step 34): the string's last hit breaks it as it empties it; a
  light that would empty it fills the bar instead, and ANY hit on a full bar breaks it (Luke, 2026-11-12, step 61); a
  new FoeDef sets `poise` (0 = every last hit staggers). Shown on the target marker, never a bar under the health. PLAYERS HAVE
  NO POISE (Luke, 2026-11-04): a foe's unblocked last hit always staggers them. Armor (parked) has no weight: it never
  costs the roll or sprint.
- SHOTS AND HITS AS THE PLAYER SEES THEM (Luke, 2026-11-11, PROGRESS step 60): a shot with no Tab target goes TO THE
  CROSSHAIR (`CombatComponent.crosshair_point`, `launch_direction`: never along the look from the chest), with no aim
  assist; a shot the server aims goes to the middle of its target (`FoeDef.aim_height_m`, from the character's
  `collision_height`: give a new creature one). A hit on a player waits for a late parry only as long as THAT player's
  line needs (`seen_delay`, `rules::hold_deadline_us`), and a roll is judged where it was pressed (`rules::roll_clears`):
  never add a fixed wait to a hit. Since 2026-11-12 (step 62) a hit on a player is DEALT AT ONCE and taken back by a
  parry or roll that arrives after it (`dealt_hit`, `take_back`; `regents.hit_at_once`); only one that staggers or
  kills waits (`rules::hit_waits`). Anything new a hit DOES to a player (an effect, a push) is owed until it can no
  longer be taken back (`settle_dealt_hit`), never done at once. A roll goes the way it began for its whole length. A new foe needs nothing for its
  swing trail if its weapon is in its hand bone's mesh or it has a `Head` bone (`SwingTrail`); a new shot's look has
  `shot_look.gd` at its root.
- FACE YOUR TARGET (Luke, 2026-11-12, step 61): a bow's or a staff's shot is aimed at the Tab target only when it is
  inside `regents.aim_arc_deg` (120) in front of the body; outside it the shot is REFUSED ("Face your target"), by the
  client and by the server (`faces_target`). Never turn the body for the player, never quietly shoot elsewhere. The
  upper body turns to the shot from the way the BODY faces, less where the pose points by itself (`CombatLook`'s
  "pose points", Luke's to adjust with `tests/aim_shot.tscn`): never from the hands, which move through a draw.
- A FOE'S BEHAVIOR IS A LIMBOAI TREE (Luke's F2, 2026-11-12, PROGRESS step 63; `FOES_PREP.md`): `FoeDef.behavior` names
  `sidecar/npc/brains/regents/trees/<name>.tres`; a task (`tasks/foe_*.gd`, extends `RegentsFoeTask`) only calls a step
  of `RegentsFoeBrain` (`foe.gd`), which keeps the foe's knowledge (target, turn, string, pack, aim). A new KIND of foe
  is a new tree with new steps and tasks, never an `if` on the kind in an old step; the fighting tasks go BELOW
  `foe_rest` (it finds the target they read). `game/` names a tree by its key only, never its path (rule 7b). Every foe
  keeps the sheet's §4 rules (Luke: "smart but fun (not annoying or painful)"): every hurt announced, nothing from off
  screen, a foe that keeps its distance is caught, never chained.
- A FOE'S SHOT (Luke's F4-F7, 2026-11-12, PROGRESS step 64): a foe's kit ability that a BOLT `SpellDef` flies
  (`rules::is_shot`), with `range_m` 0 and NOT judged (the server refuses one with a range). Its brain names the
  target in `use_ability`; the server locks the aim `regents.foe_shot_lock_ms` before the tell ends and flies the
  missile there (`foe_shot_due`), LED to where the target's walk carries it (`rules::lead_point`,
  `regents.foe_shot_lead_pct`; Luke, 2026-11-13, step 67; a ring is never led): never roll its hit. On a player it goes through `land_on_player`,
  the same lines a swing does: never judge a shot's hit anywhere else. A parry only knocks it away (`knocked_away`), it
  never staggers, a roll lets it fly on, and it hurts nobody but players. A player's missile still never hurts a player.
- A FOE THAT SHOOTS (PROGRESS step 65, the skeleton archer): `FoeDef.behavior = ranged`, its shot its kit's first skill
  a bolt spell flies (`FoeDef.shot()`), its distances and rests on its FoeDef. Its kit's string is what it does up
  close, and A STRING OF ONE STEP HAS NO FINISHER (server and client `is_finisher`): it never staggers and is never
  unblockable. A shot takes a RANGED turn (`regents.ranged_tokens`), never a melee one. A NEW FOE ON AN OLD MODEL is
  its FoeDef's look fields (`held_scene`, `hidden_meshes`, `albedo`: `FoeLook`), never a new scene. A change to a
  ranged foe runs `game/regents/tests/archer_playtest.sh`.
- NOTICING AND REST (Luke's F9-F12, 2026-11-13, PROGRESS step 68): a foe SEES only in front (`FoeDef.notice_arc_deg`,
  from its yaw: the way it last walked or aimed) and HEARS all round (`hear_m`, `hear_sprint_m`); at rest it WANDERS
  (`wander_m`); Startled, it turns on the status's `by_entity` (who hit it). A SUITE that needs a foe to notice it
  stands IN FRONT of where the foe faces NOW (its body's `rotation.y`) or within its hearing of where it stands NOW,
  never at a fixed side of its spawn point; and keeps other foes down when their wander could bring them in.
  NOT CHAINED is the server's (`unchained`, private; `regents.unchained_ms`): a foe's stagger or slow on a player
  goes through `unchained` / `chained_by`, never round them.
- A SHOT'S BODY (PROGRESS step 66): every missile's `BodyDef.forces` is a `MissileFlight` (or extends it, as
  `ArrowFlight`): it stops dead where it first touches. A new missile body without it skids off a moving target (the
  suite's `_run_shot_stops` names the three; add a new one there).
- A FOE THAT CASTS (step 66, the imp): the `ranged` tree, with `FoeDef.ring_every` and an AREA `SpellDef` skill for
  its ring (range 0, not judged). A foe's ring lands on players only, damage only, and is LEFT, never blocked. A
  change to it runs `game/regents/tests/caster_playtest.sh`.
- AMERICAN SPELLING (Luke, 2026-11-04): armor, defense, color, gray, center, meter, canceled, behavior, mold, in
  everything a player reads and in every new name, rule, table and doc. Old names already published (tables, hot
  rules, ids) are renamed only where rule 17 allows. Swept 2026-11-04 (PROGRESS 38); British on purpose: the
  `swing` table's `cancelled` column, and the foundation's `UiKit.colour`, `InterestManager.centre`, `Cells.recentre`.
- The TUTORIAL's lessons are content (`content/lesson/`, `LessonDef`); the server ticks them where a deed happens
  (`lesson_done`): a new deed is a new `LessonDef.Done` and `rules::Deed`, and a call where it happens.
- AN EFFECT (the VFX lab, PROGRESS 78) is a scene in `game/regents/vfx/effects/` whose root extends `VfxEffect`: built
  in code from `VfxKit` and the shaders in `vfx/shaders/` (noise, ramps, math: NO image file under `vfx/`, the
  `regents_vfx` suite fails one), moved by its own clock (`_animate`; the shaders' `fx_` instance values), its look the
  root's exported values. Presentation only: it shows what the server said, never decides. A new one gets a showcase
  in `vfx_lab.gd` and the suite's every-effect check picks it up; look at it with the lab's shots before handing over.
  A MELEE CUT follows the real blade (`VfxBladeCut`, Luke 2026-11-14, PROGRESS 79), never a fixed arc guessed from the
  clip; a spell leaves IN FRONT of the hand; a landing ring is a `VfxGroundRing` of its element (frost and fire one
  family). Cost: `vfx_lab.tscn -- cost`. IN THE GAME (PROGRESS 82): swings by `SwingTrail` (the crescent), missiles by their
  body's look (`ShotLook` + a riding `VfxFireMissile`, `end_scene`), rings by `SpellLooks`, the rest (charges, Gale,
  Blink, the parry) by `AbilityVfx` from the table `vfx/ability_vfx.tres` (another player's instant spell from the
  server's `spell_landed` row, while fresh: PROGRESS 83; a change to it runs `spells_seen_playtest.sh`): a new ability gets a row there or is drawn by
  one of those three (the `regents_vfx` coverage check fails one drawn by none).
- ANOTHER PLAYER'S EFFECT IS THE LIGHTER VERSION (PROGRESS 88): `VfxEffect.lighter` (half the particles, no light, no
  shake; `AbilityVfx.lighter_for`), yours and a foe's whole: a new place that spawns an effect for a fighter sets it.
  A ring's pieces are one MultiMesh (`instanced` in the energy shader): a new piece-heavy effect does the same. The
  game's camera shakes from `shook` through `VfxCameraShake` (installed by the local player's `AbilityVfx`).
- A SWEEP THAT HITS ALL (PROGRESS 89, template #314): a player's judged sweep marked Hits All (`AbilityDef.hits_all`:
  Cleave) lands on every foe in it, each judged as a single hit; a rallying hit heals once a swing (`rallied`).
  Which abilities hit all is Luke's content call.
- TOWNS (PROGRESS 85, 90): a kit piece is found through `TownKit.piece` (cached by name): never `load` a kit path per
  piece (the loader's lookup costs ~2 ms each). A place's small village props are its `Settlement`'s `dressing`
  (`VillageDressing`), never placed by hand round a house.
- ARMOR (PROGRESS 92): what a player wears is the `worn` row (one a wearer, a column pair a slot); a piece is an
  `ItemDef` with `armor_slot` and `defense`; a hit's damage goes through `rules::through` (guard, armor, traits,
  multiplied): a new damage path calls it, never a flat cut. Worn and taken off out of a fight only.
- ARMOR PIECES (PROGRESS 94) are cells of the material table: a pattern with `armor_slot` and `defense_share` (its
  cells' Defense = share x material tier); a new piece or material is content and Make the table, never code. Leather
  is the HIDE family, cloth FIBER. A look finds a worn item's slot, family, material and piece from `ItemDef.by_id`
  (`armor_slot`, `material.family`, `material.key`, `pattern.key`). Armor's trait pools are EMPTY until Luke fills them.
- NO AI DISCLOSURE (Luke, 2026-11-14; `docs/regents_rule/AI_ASSET_AUDIT.md`): look first to make a thing procedurally,
  in code (draw calls, shaders, noise, synthesis, renders of the game's own models). Never add an image, model,
  texture, sound, music, voice or text from a generative model, nor anything traced or derived from one, to the game
  or its store page: anything that would need Steam's AI disclosure. Otherwise human-made, CC0 or licensed, its
  source in the folder's ATTRIBUTION.md. A new asset whose source is unknown is asked about, never added. The
  continent map (`continent_map.webp`) is AI-made and to be replaced: never build more on it.
- THE SHOWCASE AND THE LOGIN (PROGRESS 84): `game/regents/showcase/` is a place made to be LOOKED AT (the login's
  picture, the vista and battle labs, the composers' renders), never the game's world: no server, no collision, no
  bake, and it never reads the continent. Made in code or from the CC0 kits like everything else. A lab's shots are
  its scene's `ShowcaseShot`s and a battle's beats are timelines of the game's own clips and `VfxEffect`s (never a
  look of its own). Its people are `ShowcaseActor`s: the game's `MovementModel` (`ShowcaseMovement`) and
  `AnimationDriverComponent`, told as keys and the combat component would tell them (Luke, 2026-11-15, PROGRESS 86):
  never set a body's position or play a raw clip by hand. The login (`RegentsLogin`) stays the foundation's `ConnectScreen` dressed: a change to the form
  is the template's; its valley is built only while it shows (the `regents_showcase` suite checks it is freed).
- THE WARDROBE (PROGRESS 81, `docs/regents_rule/WARDROBE.md`): an outfit piece is a `<Male|Female>_<Outfit>_<Part>.gltf`
  in one of `Wardrobe.PIECE_DIRS` (found by name, never listed); an outfit's colors come from the DYE
  (`outfit_dye.gdshader` through `Wardrobe.dress`, a `DyePalette`, a `MetalFinish` per metal), never a repainted
  texture or a new mesh per tier. A new outfit gets its zones in `wardrobe/zones.json` and a bake
  (`game/regents/tools/wardrobe_assets.py zones`); look at it in the wardrobe lab with Z. The Knight is the genre's
  (`game/regents/art/outfits/knight/`), the other four outfits the foundation's.
- A PLAYER'S BODY (PROGRESS 93) is a `RegentsFigure` (`game/regents/looks/peasant_m|f.tscn`, the adventurer's only
  looks): Peasant clothes in the player's own colors (`RegentsColors`: keys `main`, `accent`, `under`, `trim`, `leather`
  on the `appearance` text, each 0xRRGGBB + 1; never `#`, which the module refuses), dressed on the foundation's
  `assembled` with materials shared by palette (`Wardrobe.dress_shared`). Armor goes on through `wear_armor` (pieces +
  tier palettes); nothing else dresses a player. The picker's color options need template 1.8.4 (`COLOR_OPTIONS`).
- AN NPC'S SCENE (PROGRESS 87, 95): a new NPC scene inherits `game/regents/npc.tscn`, `combat/foe.tscn` or
  `player.tscn` (template #315: no wait for a `session_member` row). A change to an NPC's scene runs
  `game/regents/tests/bind_playtest.sh`.
