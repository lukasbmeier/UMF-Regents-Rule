# Handoff — Regent's Rule, 2026-11-14 (step 77: the roll is the foundation's; step 78: the VFX lab)

## Where it stands
- Last commit `8703e633` (template 1.8.1 merged); steps 72-76 and the cinema lab are in `81a7afc2`. NOT COMMITTED:
  step 77 (the roll switched to the foundation's: content, `server/src/game/regents.rs`, the combat component, bindings;
  another session), the AI asset audit (`docs/regents_rule/AI_ASSET_AUDIT.md`, the "No AI disclosure" rule in `GAME.md`
  and `regents-genre.md`; another session) and step 78 (`game/regents/vfx/`, `game/regents/tests/suites/regents_vfx.gd`,
  docs). Leave `addons/SpacetimeDB/plugin_config.tres` out of any commit, as before.
- Current section in `docs/regents_rule/PROGRESS.md`: **Step 78** (step 77's "Server suites" line still reads
  `SUITES77`: its session did not fill it in).
- The play database: published at step 77 (`--codegen`). Step 78 is client-only (no publish needed).
- Suites (2026-11-14): `regents_vfx` 100/0 (new); unit whole run 4094/0, lints and engine-error checks ok.

## This session (step 78, the VFX lab)
- Luke asked how far code-made VFX can go under Steam's AI disclosure, then for a lab. Answer: shaders, particles and
  meshes made in code, no images (`AI_ASSET_AUDIT.md` §5 reads code-made as fine).
- `game/regents/vfx/shaders/`: energy (noise through a heat ramp, bands, erosion, sweep), ground circle (runes, fill),
  particle shapes, air ripple. `vfx_kit.gd` (`VfxKit`), `vfx_effect.gd` (`VfxEffect`: its own clock, `shook`).
- Ten effect scenes in `vfx/effects/` (fire charge, missile, blast; frost charge and ring; blink; gale; axe overhead;
  parry; cinder ring) and the lab `vfx/vfx_lab.tscn` (F6; seven showcases, speeds, day/dusk/night, shots).
- `game/regents/tests/suites/regents_vfx.gd`; `GAME.md` (how to play), `CLAUDE.md` (the shot command),
  `regents-genre.md` (AN EFFECT rule), PROGRESS step 78.

## Next, in order
1. Luke opens the VFX lab (F6) and says what to push in the look; then which effects go into the fights first
   (PROGRESS 78, "Left for later": the fireball's `ShotLook`/`ImpactBurst`, the areas' circles, the parry, the cut).
2. Before wiring: a lighter version for others' casts (300 players) and the game camera's shake.
3. From before: Luke plays the bar, Gale, a staff to 5 and its pick; writes the axe's, sword's and bow's role
   abilities (`ABILITIES_PREP.md` §9); the UI rebuild after armor (`GAME.md`).

## Waiting on Luke
- The VFX look and which effects go in first; whether others' casts get a lighter version.
- From before: round or square bar; his rewrite of §9; B13 as read; the lead's share; the archer's and imp's numbers;
  #12 day/night, tree scale, the wolf pack's place, `string_chase_ms`, the glade's grass and colors.

## Watch out
- `VfxEffect` reads where it is in `_start` (as it enters the tree): set `position`/`basis`/`target` BEFORE `add_child`
  (the lab's `_spawn`), or a missile flies from the origin.
- The lab's waits are its own Timers and its `ticked` signal (never `get_tree().create_timer`): a showcase still
  waiting when the lab is freed (the suite frees it) is dropped instead of resumed on a freed lab.
- Shader edits: headless cannot compile or draw them; run the lab's shots (windowed) and look.
- A Python patch on Windows writes CRLF unless `newline=''`: `.gitattributes` wants LF.
- From before: `combat_playtest.sh` can flake at its first skeleton (rerun once); every writer of an item's
  `instance_data` keeps `"x"` and `"k"`; `run_tests.sh` ignores `-- --only=`; never edit a shell suite while it runs.
