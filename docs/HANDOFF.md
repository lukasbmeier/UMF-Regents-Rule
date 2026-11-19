# Handoff — Regent's Rule, 2026-11-19 (step 115 + overhead names committed; ready for template pull)

## Where it stands
- Step 115 (playable visual parity on `frontier.tscn` + `continent.tscn` & short dense turf) and crisp 2D screen-space
  overhead names (`RegentsNameplates`) committed cleanly on top of `373c40d5` (push is Luke's). Working tree clean for
  `tools\update_from_template.cmd`.
- Included in this commit (client presentation & docs only — zero `foundation/`, server, schema, bake or content changes):
  - `game/regents/showcase/moods/frontier.tres` (playable golden-hour `ShowcaseMood`)
  - `game/regents/levels/glade_vista.gd` (`@tool class_name RegentsGladeVista`: dual-mode procedural valley for
    `frontier.tscn` + `Terrain3D` mode for `continent.tscn`; northern keep, eastern watchtower, cohesive forest ring,
    living campfire/flames/embers/props, dust/fireflies, sky/mood driver, layer-2 `FireLight` isolation + quadrant culling)
  - `game/regents/levels/glade_dirt_overlay.gdshader` + `ground_paint.gd` spatial cull (trodden dirt trails & soil rings
    over `Terrain3D` camp floor)
  - `game/regents/levels/clutter_kind.gd` + `ground_clutter.gd` (`height_scale` for ankle-high wide plush turf)
  - `game/regents/levels/frontier.tscn` (upgraded sky/volumetric mist/shadows, matched ground, dense short turf, `Vista`;
    also upgrades `cinema_lab.tscn`)
  - `game/regents/levels/continent/continent.tscn` + `continent_assets.tres` + `build_continent.gd` (live level 21 parity:
    rich meadow/rock/sand albedos, `showcase_sky`, volumetric mist, `GroundOverlay`/`GroundPaint`, terrain-aware dense short
    `Clutter`, `Terrain3D`-grounded `Vista`)
  - `game/regents/art/nature/*.import` (VRAM compression + mipmaps on Pine/Twisted bark & leaves used by `RegentsGladeVista`)
  - `game/regents/ui/overhead_names.gd` (`RegentsNameplates`, mounted in `game/regents/regents_hud.gd` on `layer = 2`):
    crisp 2D screen-space overhead names, status tags, chat bubbles and ground-item labels (14/12 px, shorter 16-24 m
    fade / 36 m focus & Tab-target priority, vertical anti-overlap stacking capped at 2 rows with crowd overflow hiding,
    Game Settings toggle `All` / `Focus & close` / `Minimal`, throttled layer-1 LOS occlusion; zero `foundation/` edits)
  - `game/regents/tests/glade_shot.gd` + `game/regents/tests/suites/regents.gd` (`_run_glade_vista()` on both levels;
    `_run_overhead_names()`, 25 checks including negatives, anti-overlap, mode filtering, settings & freed-node safety)
  - `docs/regents_rule/Regents_Rule_Collaboration.xlsx`
- Suites verified clean: `tests/run_tests.sh` **5496/0** (all lints, zero errors, zero leaks); `tests/content_test.sh` **18/0**;
  `perf_bench.tscn --only=presets` (RX 9060 XT, 30 chars):
  - `continent.tscn`: Low **1.14 ms (738.6 fps)**, Medium **3.10 ms (288.6 fps)**, High **4.71 ms (198.3 fps)**
  - `frontier.tscn`: Low **1.63 ms (533.3 fps)**, Medium **5.00 ms (187.2 fps)**, High **7.21 ms (131.2 fps)**
- Play database `regents-rule` (level 21 `continent.tscn`): no republish needed for this commit — just press Play (reload
  open scenes if edited while open in Godot).

## This session
- Investigated and reproduced intermittent projectile freezes in Godot 4.7.1 + Jolt Physics (head-on Fireball vs Arrow
  13/20 frozen, Q Fireball + LMB Bolt chase 10/10 frozen, melee-range Frame-0 hits 19/23 frozen, grazing 2/15 frozen).
- Root causes identified in `UMF Template` (`FlyingBody` missing Frame-0 / Jolt-fallback contacts + `BodyDef.hits_bodies`
  flag); Luke ran the fix in the template repo (`FlyingBody` reads Jolt contacts with pre-step velocity + bounce-scaled
  impulse push, `BodyDef.hits_bodies` added).
- Verified Step 115 + overhead names pass, committed everything cleanly so the repo is ready for `tools\update_from_template.cmd`.

## Next, in order
1. Pull the template's `FlyingBody` / `BodyDef.hits_bodies` update (`tools\update_from_template.cmd`), then build Regent's
   Rule's half of the projectile fix:
   - Visual + audio clang when two projectiles collide (`body_contact` where both entities are bodies; keep `hits_bodies = true`
     for now per Luke's call, toggleable later for PvP).
   - Set `contact_speed_mps = 0.0` on `arrow.tres`, `bolt.tres`, `fireball.tres`; add `on_body_rest` cleanup in
     `server/src/game/regents.rs`; add regression checks in `game/regents/tests/suites/regents.gd`.
2. Luke plays `regents_game.tscn` (loads live level 21 `continent.tscn`) to check the upgraded look, short dense turf, and
   overhead names; plus step 112–114 checks (bowstring V-draw, off-target crosshair shots, clip browser).
3. Optional pre-YouTube polish: decide whether harvestable Oak/Yew trees keep blue/pink leaves or shift to natural tones,
   and grab "before" clips from commit `373c40d5` for a devlog visual-upgrade hook.
4. The three bows as roles (`KitDef.roles`, longbow 1.4x, shortbow with `String`, carving): Luke's numbers, recipes, names.
5. The staff's shafts (GAME.md, THE STAFF'S ROLES): ward = melee string + metal part, censer = quick weak bolts.
6. 110's live pull/lift check; TEMPLATE work (PROGRESS 108, 107).

## Waiting on Luke
- Visual verdict on Step 115 on live `continent.tscn` (grass height/density, `frontier.tres` brightness/haze, Oak/Yew leaf colors).
- The bows' and shafts' numbers, recipes, names, spells per role; tap swings or shoots. A Mixamo longbow pack.
- 110's: which moves stay; the spin; the back flip as a backward roll; a real blade waltz.

## Watch out
- NEVER leave Mixamo FBX in `game/anim/_import/`: the export filter does not exclude it.
- `--script` runs have no autoloads: a look check with the game's classes needs a scene.
- A changed `.tres` rule or content needs `tools/bake_content.gd` before `cargo` builds (build.rs refuses a stale bake).
- `docs/HANDBOOK.md` is the template's: never edited here.
- `RegentsGladeVista` uses `OUTER_LAYER = 2` so `FireLight` (`light_cull_mask = 1`) never renders distant terrain/trees
  into its shadow map — keep outer vista meshes on layer 2 if adding new camp omni lights.
- `continent.tscn` must NOT serialize `metadata/umf_authored` on `WorldEnvironment` (it overrides `volumetric_fog_enabled`).
