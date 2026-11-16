# Handoff — Regent's Rule, 2026-11-15 (steps 78-86: the VFX, the wardrobe, the showcase and login, the towns)

## Where it stands
- THE ARMOR RUN IS IN PROGRESS (a master session, 2026-11-15): `docs/regents_rule/MASTER_RUN.md` is the work list
  and its §7 LEDGER says who runs what (children S1, P1, E1, E2, E3 in `.claude/worktrees/`, branches `claude/...`;
  nothing merged yet). T1 (the template's `ModularCharacter.wear`) is NOT started: the app wants Luke to trust the
  `UMF Template` repository first. A restarted master is given the prompt in MASTER_RUN §8 and reads the ledger.
  What waits on Luke: `docs/regents_rule/WAITING_ON_LUKE.md`.
- EVERYTHING IS COMMITTED on `main` and PUSHED to `origin` (2026-11-15). On top of `27a8fc7b` (step 77) and the template 1.8.2
  merge `e87eae25`: `ddbb2850` the towns (step 85), `2031e982` the wardrobe (step 81), `c8aa439f` steps 78-83 (the
  VFX) and the AI asset audit, then the commit holding step 84 (the showcase and login) and this HANDOFF.
  `addons/SpacetimeDB/plugin_config.tres` stays out of every commit, as before.
- STEP 86 (Luke's notes on the showcase films) is COMMITTED and pushed (`13d8ed15` swept it in, `779ac93d` adds its
  missing `showcase_movement.gd`; unit 4581/0 on a clean checkout): `game/regents/showcase/` (the actor on the game's
  movement and driver, NEW `showcase_movement.gd`, the battle and vista beats, the keep), `ui/login/regents_login.gd`
  (title card, on in the game too, no tagline), `tests/login_shot.gd`, the `regents_showcase` suite, PROGRESS 86, GAME.md, the genre rule.
  The village textures' `.import` files also show changed (reimported as 3D at 18:26): NOT this session's.
- THE TOWNS' FOLLOW-UP (Luke's first look: roofs, streets, furnishing; the lab's 5 Roofs and 6 Places) is on `main`
  and PUSHED: `34bedf9d` and the Places commit after it, fast-forwarded from the worktree branch
  `claude/medieval-village-worldbuilding-dd942b`. Client-only: no publish. `regents_town` 68/0.
- Current section in `docs/regents_rule/PROGRESS.md`: **Step 86** (the showcase notes); 85 the towns, 78-84 above.
- The play database: PUBLISHED 2026-11-15 with `--codegen` (step 83's NEW table `spell_landed`, add-only; 63 tables).
  Steps 81, 84 and 85 are client-only: no publish. Luke restarts the editor's game (and reloads `adventurer.tscn`,
  `foe.tscn`, `regents_game.tscn`) before he plays; the first open imports the village kit (~86 MB).
- The local SpacetimeDB server was started by a session (`spacetime start`, background) on 2026-11-14.
- Suites (2026-11-15): unit whole run on the committed `main` (all of 78-85 together) **4561/0**, lints and
  engine-error checks ok; before that `regents_vfx` 179/0, `regents_wardrobe` 231/0, `regents_showcase` 104/0, `regents_town` 39/0;
  `cargo test` green; `spells_seen_playtest.sh` caster 8/0, watcher 12/0, server 2/2; step 82's `caster_playtest.sh`
  20/0 + 7/7, `combat_playtest.sh` 126/0. Integration NOT run since step 77 (PROGRESS 83 says why).

## This session (four parallel sessions, all committed above)
- VFX, steps 78-80: the VFX lab (`game/regents/vfx/`, `vfx_lab.tscn`), Luke's notes, old and new cuts side by side,
  the gale's soft funnel.
- VFX, step 82: the effects in every current ability (`SwingTrail` crescent, `ShotLook.end_scene`, `SpellLooks`
  rings, NEW `AbilityVfx` from `vfx/ability_vfx.tres`).
- VFX, step 83, Luke "Yes, add it": others see your Gale. Server table `spell_landed` (written in `land_spell`, gone on
  `on_player_left`, a cell table); `AbilityVfx.landed_elsewhere` shows another player's landing while fresh (1.5 s).
  NEW two-client playtest `spells_seen_playtest.sh`. Then Luke "Yes, add the pose": `CombatComponent.landed_elsewhere`
  plays their arms' clip (`ability.<id>`) from the same row, every spell's landing (client only, no publish).
- Wardrobe, step 81: `game/regents/wardrobe/` (Wardrobe, the dye shader, DyePalette, MetalFinish, zones, palettes,
  metals, the lab), the Knight (`game/regents/art/outfits/`, CC0), `tools/wardrobe_assets.py`, `WARDROBE.md`. Luke
  decided who wears what (`GAME.md`: Peasant start in chosen colors, leather Ranger, cloth Wizard, metal Knight,
  Noble for NPCs); W1-W8 and the tier colors SETTLED ("Yes, all stand"; `GAME.md`, "W1-W8 ANSWERED").
- Showcase, step 84: NEW `game/regents/showcase/` (world, sky, ground, water, moods, actor, stage, shot, the vista and
  battle labs, the login's backdrop), NEW `game/regents/ui/login/` (`RegentsLogin`, an inherited scene of the
  foundation's connect screen, named by Boot's `connect_screen` in `regents_game.tscn`), `showcase_render.sh`,
  `login_shot.tscn`. Renders for the composers in `export/showcase/2026-11-15/` (git-ignored): 17 stills (1920x1080),
  17 `.ogv` films, `index.txt`. Re-make:
  `tools\run.cmd game\regents\tests\showcase_render.sh`.
- Showcase, step 86 (Luke's notes): its people move and fight by the game's `MovementModel` and animation driver
  (the swings' root travel out, recoveries, the roll's dash); the imp casts (tell, release, ember); the keep stands on
  a flat hilltop with footings; the login film is a title card (Play in the title's letters), no tagline. Re-rendered.
- AI asset audit: `docs/regents_rule/AI_ASSET_AUDIT.md`; Luke's rule NO AI DISCLOSURE (`GAME.md`, `regents-genre.md`).
- Towns, step 85 (then Luke's first look, `SETTLEMENTS_PREP.md` §9): the house roofs centered (the kit's 6x4 roofs
  start at their origin), tower roof styles and the lab's 5 Roofs view, code-made paving per style kept apart from
  the walls, the Fantasy Props kit in (`game/regents/art/props/`, CC0; a style's new CLOTH slot), `PropGroup` and
  `TownFurnish` furnishing the market, doors, green, inn and castle yard. Before that:
- Towns, step 85: the Medieval Village kit (`game/regents/art/village/`, CC0), the town dye and `SettlementStyle`
  (eight presets), `KitHouse`, `CastleWall`, `Settlement`; `town_world.tscn` (village, walled market town, castle in
  1 km) and `town_lab.tscn` (one street in every style, live edit). All in `SETTLEMENTS_PREP.md` §8.

## Next, in order
1. Luke plays the effects (staff, sword, axe, the imp, the skeletons; two instances for Gale); his notes on the look.
2. Luke picks the towers' roofs (town lab, 5 Roofs) and looks at the furnishing (lab 6 Places; world 8, 9, 0); then his S1-S8
   (`SETTLEMENTS_PREP.md` §7, §9). Was: on his okay, FURNISH them with the Fantasy Props kit (`SETTLEMENTS_PREP.md`
   §8, "Left for later").
3. Maybe: others' AIM held a moment after a spell lands (their upper body turns to the shot only while casting).
4. Before many players: a lighter version for others' effects, the rings as one MultiMesh, the camera listening to `shook`.
5. A look at the ten "binding after 2.0s without rows for session_member" warnings every playtest client prints
   (not from step 83: an A/B probe showed them without it).
6. Armor resumes from `ARMOR_PREP.md` §0 (its open parts, traits and numbers), the look now settled; the look's build
   into the game is WARDROBE.md §6, which needs a foundation hook first (`ModularCharacter.wear`: template work), plus
   W8's picker colors.
7. From before: the bar, a staff to 5 and its pick; the role abilities (`ABILITIES_PREP.md` §9); the UI rebuild.

## Waiting on Luke
- The effects in play (two instances for others' Gale and its pose).
- The towns: which roof style for which place (my picks in the world: the town hipped, the castle slate bells, the
  keep turrets), the streets' colors, how it furnishes; S1-S8 in `SETTLEMENTS_PREP.md` §7.
- The showcase: his look at the re-rendered films (the game's login now opens on the title card: his "card first");
  MP4 needs ffmpeg (a download: his yes). Deer have no graze clip; "The line" is wide.
- From before: round or square bar; his rewrite of §9; B13 as read; the lead's share; the archer's and imp's numbers;
  #12 day/night, tree scale, the wolf pack's place, `string_chase_ms`, the glade's grass and colors.

## Watch out
- A PLAYTEST'S REFEREE STOPS when any project file changes on disk ("the project changed since it started"): another
  session writing its files broke a combat run into 71/53. Ask busy sessions to hold writes and make none yourself.
- `AbilityVfx` shows your own Blink only within 2 s of casting it (`JUMP_ARMED_MS`); another player's from the jump.
  Another player's Gale comes from their `spell_landed` row, only while it is under 1.5 s old by `ClockSync`.
- `VfxEffect` reads where it is in `_start`: set `position`/`basis`/`target` (and a cut's `weapon`) BEFORE `add_child`.
- The lab's waits are its own Timers and its `ticked` signal (never `get_tree().create_timer`).
- Shader edits: headless cannot compile or draw them; run the lab's shots (windowed) and look.
- A fade at a mesh's edge needs UVs that reach it: never fade a `CylinderMesh`'s ends (its caps take part of the UV).
- A Python patch on Windows writes CRLF unless `newline=''`: `.gitattributes` wants LF.
- Wardrobe: the zone masks are lossless and unmipmapped on purpose (their `.import`); a new outfit's zones are a
  first pass to check with Z; re-run `wardrobe_assets.py zones` after editing `zones.json` (it rewrites the
  `palettes/<outfit>_<n>.tres`; custom palettes are untouched).
- Showcase: a `ShowcaseActor` is a `SpaceTimeEntity` bound in its own `_ready` (no spawner, no rows); a suite steps
  it by hand with `step(dt)` after turning its and its driver's processing off. PNG frames for a look:
  `--fixed-fps 10 --write-movie <dir>/f.png <lab>.tscn -- clip <n>`.
- Showcase: the movie writer records at the PROJECT's window size (never `--resolution`): the script writes and
  removes `override.cfg`; never leave one in the project. A shot's camera is clamped over the land, and everything
  stands on `ground_at` (the mesh as drawn), never `height_at` (the smooth shape).
- Towns: every kit piece brings its own collision body; a building must go through `TownKit.instance_building` /
  a `Settlement` (one body each) or a town passes Jolt's 10240-body limit. The world builds in ~17 s.
- From before: `combat_playtest.sh` can flake at its first skeleton, `caster_playtest.sh` at the imp noticing (rerun
  once); every writer of an item's `instance_data` keeps `"x"` and `"k"`; `run_tests.sh` ignores `-- --only=`.
