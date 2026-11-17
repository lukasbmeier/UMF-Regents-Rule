# Handoff — Regent's Rule, 2026-11-17 (Step 101: World Builder & Lore Studio built + UX polish; Armor Run 87-100 on main)

## Where it stands
- Step 101 (**The World Builder & Lore Studio**, `docs/regents_rule/WORLD_BUILDER_PREP.md`, Luke's WB1-WB12 + UX polish)
  is built and verified on `main` (uncommitted, ready for Luke to try or commit).
- Suites on `main`, 2026-11-17: `tests/run_tests.sh` **5215/0** (including new `regents_builder` **61/0**, `workbench`,
  `content`; lints, engine-error and leak checks ok), `tests/content_test.sh` **18/0**, `cargo test` green, wasm clean.
- Earlier on `main` (`76f4a3bd`): the armor run (steps 87-100, templates 1.8.3 and 1.8.4) finished and was pushed
  and published to `regents-rule` (64 tables, 111 reducers).
- Current section in `docs/regents_rule/PROGRESS.md`: Step 101 ("THE WORLD BUILDER AND LORE STUDIO") after steps 87-100.

## This session (Step 101; full notes in `PROGRESS.md`)
- **Locked in WB1-WB12** (`docs/regents_rule/WORLD_BUILDER_PREP.md`, `GAME.md`, `.claude/rules/regents-genre.md`):
  Luke accepted all proposed decisions ("Accept all proposed and start building").
- **World Builder UX & Bug Fixes (`game/regents/builder/world_builder.gd`, `game/regents/content/npc_def.gd`)**:
  - **UI Focus / Scroll / Search Isolation**: `_palette_list` uses `FOCUS_NONE` and `_search_edit` auto-blurs when the
    mouse moves off the left panel or selects an item, so pressing `R` in 3D never jumps/filters `R` props in the list;
    menus only scroll/search when hovered (`_is_mouse_over_ui`).
  - **Flexible Grid Snapping (`XZ` + `Y`, `Shift`/`Alt` Free Placement)**: custom `m XZ` and `m Y` `SpinBox`es alongside
    grid presets; holding `Shift` or `Alt` temporarily disables snapping; Y snapping is hill-relative so upper-floor
    pieces never sink into sloped terrain.
  - **Centered Prefabs & `Pick Origin in 3D`**: `start_new_prefab` waits for the 1st placed piece (or `Pick Origin in 3D`)
    instead of trapping origin at the button edge; `_instantiate_building_centered` recenters children BEFORE
    `TownKit.gather_collisions` so visuals AND `StaticBody3D` colliders both stamp centered at the cursor.
  - **Conditional Right Studio & Guided NPC Creator (`+ New NPC` -> `1. Appearance & Wardrobe` -> `2. Lore & Dialogue`)**:
    Right panel hides completely in Terrain/Nature/Skilling/Foes, shows Prefab Studio in Towns/Pieces, and NPC Studio in
    NPCs; new NPCs register as live drafts (`NpcDef.register_draft`), include a `DyePalette` selector + real weapon paths,
    and update the 3D ghost/point preview immediately before saving `.tres`.
- **`NpcDef` (`game/regents/content/npc_def.gd`) + 4 starter NPCs (`game/regents/content/npc/*.tres`)**:
  `40001` Drillmaster Vane (`Knight` with `knight_tabard = true`), `40002` Chronicler Venn (`Noble`), `40003` Blacksmith
  Hal (`Peasant` + `hammer.tscn`), `40004` Elder Maren (`Wizard` + `yew_staff.tscn`), baked to
  `shared/content/regents/npc.json`. Validates outfits, unique `key`, and `CinemaDialogue` section/jump targets.
- **Terrain-aware `RegentsGroundClutter` (`game/regents/levels/ground_clutter.gd`)**: optional `terrain` / `height_func`,
  `max_slope`, `water_y`, and `erased_spots` (`erase_in_circle` / `clear_erased`); 100% backwards-compatible on flat levels.
- **3D `LevelPoint` Visualizers & Tactical Rings (`game/regents/builder/level_point_preview.gd`, `RegentsPointPreview`)**:
  `@tool` child attached with `Node.INTERNAL_MODE_BACK` (zero `.tscn` bloat on save) showing the real 3D model and rings
  (`footprint`, `work_reach`, `wander`, `notice_cone`, `hear`, `leash`, `pack` + wolf packmate link lines).
- **World Builder & Lore Studio (`game/regents/builder/world_builder.tscn` + `world_builder.gd`, `terrain_brush.gd`, `kit_catalog.gd`)**:
  - Start From Scratch or Procedural Base with non-destructive layers (`hand_settlements`, `hand_props`, `hand_gameplay`,
    `proc_scatter`) and `exclusion_zones` so `rescatter_procedural()` never touches hand-built towns.
  - `RegentsTerrainBrush` (9 sculpt/paint/ramp/auto-slope modes, `carve_ramp`, `flatten_footprint`, `flatten_road_spline`,
    snapshot undo/redo).
  - 3 building tiers (parametric `KitHouse`, preset/demo houses, 2 m Grid-Snap Piece Mode + `save_custom_house_preset`),
    `CastleWall` & Keep builder, `TownFurnish` stampers, and 3 prop modes (`SCENE_NODE`, `PROP_GROUP`, `TERRAIN_INSTANCER`).
  - Dual-mode camera (`Tab`: Free-Fly vs Drop-In `ShowcaseActor` Walk Mode with `E` to talk to NPCs) + built-in Dialogue &
    Lore Studio (`CinemaDialogue` + `CinemaBalloon` in `REGENTS_CARD`, `SPEECH_BUBBLE`, `OSRS_BOX`, `PLAIN_SUBTITLE`).
  - One-click `save_level` and `bake_level` (`LevelBaker.bake`).

## Next, in order
1. Luke tries `res://game/regents/builder/world_builder.tscn` (**F6**) and plays the armor run (`WAITING_ON_LUKE.md` §3).
2. Optional server wire-up when Luke is ready: spawn `kind == "npc"` `LevelPoint`s on the server from `npc.json` (like
   `guide`) so friendly lore NPCs placed in a baked level also stand in multiplayer worlds.
3. Armor's real parts, traits and numbers (`ARMOR_PREP.md` §0) and role abilities (`ABILITIES_PREP.md` §9) once Luke answers
   `WAITING_ON_LUKE.md` §1-§2.

## Watch out
- After adding a `class_name`, always run `Godot --headless --path . --import` before `bake_content.gd` or `run_tests.sh`.
- `Terrain3D` must be inside the SceneTree before `import_images` is called, and its import origin must be aligned to
  `region_size * vertex_spacing` (`RegentsTerrainBrush.create_terrain_node` and `_push_all_to_terrain` handle this).
- A content source edit (`game/regents/content/npc/*.tres`) requires `tools/bake_content.gd` before `run_tests.sh` or publish.
