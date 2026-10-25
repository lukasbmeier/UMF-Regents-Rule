# The version check, settings and character looks
The schema fingerprint, settings as data, appearance rows, modular pieces, LODs, the registry's buffer. Moved verbatim from AGENTS.md (REVIEW 0.23.1 C1); the DECISIONS rows in each heading say why.

## VERSION, SETTINGS, LOOKS (DECISIONS #164-#166, #176-#178)
- THE VERSION CHECK (#164, #198): `publish.sh --codegen` writes `spacetime_bindings/schema_fingerprint.json`
  and `schema_contract.json`; the adapter refuses a server that lacks or changed something the
  contract names, or is of another compatibility generation (`docs/rules/compatibility.md`). A
  schema change without codegen fails the `version` unit suite ("the bindings' contract is the
  schema codegen read"): run codegen.
- SETTINGS: one `Settings.define()` per setting; nothing else stores a copy. Sounds set `bus` to a
  `Settings.BUS_*`. Processes under a test suite (UMF_DB) or UMF_SETTINGS=none never read or write
  the player's file (`run_tests.sh` and `render_test.sh` export UMF_SETTINGS=none).
- LOOKS: the `appearance` row is read by `SpaceTimeEntity` itself, before any component binds (the
  model is chosen first). A change rebuilds the entity from the SDK cache once no component
  `blocks_respawn()`; a component holding state that lives nowhere else (the fishing fight) says
  so. Pages that a menu shows (pickers, the journal) are parented to their menu at once, or they
  leak when never opened.
- PIECES (#178): a look is a starting point; `CharacterLooks.SLOTS` says what each slot may wear
  per body (append, never reorder: choices are stored by position). A swapped piece REASSEMBLES
  the character on a new skeleton: call `apply_appearance` before anything holds the skeleton. A
  colourway dresses only its own outfit's material (`_colourway_fits`). Worn meshes carry
  `ModularCharacter.PIECE_META`. The `looks` suite wears every piece alone on its body's look.
- NO LODS ON WORN PIECES (#177): layered meshes a millimetre apart must not be simplified one by
  one. A new piece imports with `meshes/generate_lods=false` (the importer writes it); the
  `character` suite reads the renderer's surface data and fails on any LOD.
- THE REGISTRY'S BUFFER (#176) holds one event per row, keyed by the cache's row instance: an
  update replaces the event it follows, and nothing is evicted. Never put a cap back that drops
  rows: an entity with many owned rows (the rival's catches) lost its own state that way.

## GRAPHICS QUALITY AND THE RENDERER (DECISIONS #282)
- `quality` (Low / Medium / High / Custom) sets `Settings.PRESET_KEYS` together from
  `QUALITY_PRESETS`; a member changed by hand makes it Custom, and members matching a preset make it
  that preset again. HIGH IS THE LOOK BEFORE PRESETS: never change High's values (or the defaults on
  a good machine) without Luke's say. A fresh install starts on `machine_quality()`: Low on
  Compatibility or a `RendererChoice.LEGACY_GPUS` adapter, else High.
- A preset never runs while a file is read (`use_file`, `use_defaults`, a start): every member takes
  its own saved value. Choices are stored by INDEX: append to a CHOICE, never reorder (`shadows` became
  `shadow_quality` with Off first, and a saved `shadows` is read across).
- What a choice does to a level is `GraphicsQuality`: it turns a level's effects and shadows DOWN
  from what the level was authored with (kept as meta the first time it sees each Environment and
  light) and back to exactly that, never past it. It applies to every node as it enters the tree
  (`node_added`). Only Forward+ gets SSAO, SSIL, SSR, SDFGI, volumetric fog (the others warn).
  Designers mark extra detail with groups (`detail_high`, `detail_medium`, `detail_density` on a
  MultiMeshInstance3D), never code.
- THE RENDERER is picked by the engine as it starts: `project.godot`'s
  `application/config/project_settings_override` names `user://renderer.cfg` (`RendererChoice`); the
  editor ignores it. Keep that line in every game's `project.godot`. Nothing may switch renderers
  but `RendererChoice` (Settings' `renderer`, Automatic's switch and restart). A renderer on the
  command line is the player's: nothing is written then.
- Tests never touch the player's renderer files: `Settings` only uses them with the player's own
  `settings.cfg`; a suite passes its own paths (`use_file(file, [override, guard])`).
  `tests/render_test.sh` sets the player's aside and puts them back.
