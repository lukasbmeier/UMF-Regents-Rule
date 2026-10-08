# The version check, settings and character looks
The schema fingerprint, settings as data, appearance rows, modular pieces, LODs, the registry's buffer. Moved verbatim from AGENTS.md (REVIEW 0.23.1 C1); the DECISIONS rows in each heading say why.

## VERSION, SETTINGS, LOOKS (DECISIONS #164-#166, #176-#178)
- THE VERSION CHECK: `publish.sh --codegen` writes `spacetime_bindings/schema_fingerprint.json`;
  the adapter refuses a server whose schema fingerprint differs. A schema change without codegen
  makes EVERY suite fail to connect ("runs schema X; this build's bindings are Y"): run codegen.
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
