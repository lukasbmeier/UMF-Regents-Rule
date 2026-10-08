# What AGENTS.md's "Current state" said, up to 0.23.2
Moved verbatim from AGENTS.md (REVIEW 0.23.1 C1). Newest first; docs/CHANGELOG.md has every version.

- **A SPLASH, THE LOBBY SCREEN, MATCHES (0.23.0).** `SplashScreen` before the connect screen
  (#183); the lobby screen after it: everyone's characters, Choose character, Ready, Join
  mid-match (#182). A match (`session_match`) counts its rounds from 1 (`match_round`); a world
  empty for `end_after_empty_s` ends its match and waits. `session.round` still counts on.
- **THE JOURNAL REMEMBERS (0.22.1).** Bind hands a component every row its entity was sent, not
  the newest of each table (`SpaceTimeComponent.bind(..., history)`, #180): an angler's catches
  arrive whole. Another angler's heave moves between their reports instead of holding and
  jumping (#181).
- **EVERY PIECE OF A CHARACTER (0.22.0).** The picker starts from a look and swaps any piece, slot
  by slot, from the pieces made for that body, with colours per clothing slot
  (`CharacterLooks.SLOTS`, `ModularCharacter.worn`/`dyes`, #178). The entity registry holds one
  event per row and drops nothing (the rival's 900 catches pushed his position out, #176).
  Character pieces import without LODs (the hair sank into the scalp at a distance, #177).
- **THE TEMPLATE (0.21.0).** A game is a list of genres (`shared/game.json`; build.rs compiles them
  in as `cfg(genre_<name>)`, Boot loads each `game/<name>/genre.tres`; `Genre` trait and `Claims`,
  #173); the lobby (`lobby_member`, `set_ready`/`set_team`, `LobbyPanel`, #174); levels built in the
  editor and baked from the scene (`LevelInfo` + markers, `tools/world/bake_level.gd`; a world's
  level is the foundation's `world_level`; `LevelLoader` swaps the scene; the meadow is level 2,
  #175).
- **READY FOR A FRIEND (0.20.0).** A version check before connecting (`SchemaFingerprint`, #164);
  settings as data in the Escape menu and connect screen (`Settings`, `SettingsPanel`, #165); a
  character picker whose choice is a public row (`appearance`, `CharacterPicker`, `Appearance`; a
  changed look rebuilds the entity, `EntitySpawner.respawn`, #166); music by phase
  (`MusicDirector`, #167); per-round time of day and weather that change the rolls
  (`fishing_conditions`, `SkyDirector`, #168); a module-driven rival in module worlds (#169);
  other players' fights shown (`fight_show`, #170); the catch journal and records (#171); a held
  item's off hand as grip data (`OffHand`, #172).
- **ARMS CHECKED IN EVERY ANIMATION (0.19.3).** The `arms` suite measures arms against the
  character's own skin (`SkinClearance`) in every animation of the set, both bodies, and that the
  off hand stays on the rod in `FishingRod.two_handed` animations (the cast, the wait, the heave),
  whose weight now drives the reel hand (#163).
- **WHAT THE PICTURES SHOWED (0.19.1).** `SHOTS=<dir> tests/fishing_playtest.sh` photographs the
  game as it is played; from it: a refused cast reels its float in, the bell brings in unbitten
  lines (`on_phase_changed`), an item packs to `stow_length` on the back, the left hand stays on
  the reel, the fight gauge clears the prompt (#161).
- **SHARED EQUIP, THE SHUT HAND (0.19.0).** The equip state is a public row the owner reports
  (`equip_state`, `set_equip_state`) and everyone else follows; it goes away after `away_after_sec`
  or when moving faster than `away_when_faster_than`; an action or hit over the whole body ends an
  upper-body draw; a held item keeps the hand shut (`GripFit.close_fist`) (#160).
- **EQUIPPED IS GAME STATE (0.18.1).** `EquipComponent` (AWAY/DRAWING/READY/STOWING, its own
  clock) says whether an item is in hand; verbs that need it check `is_equipped()` (the cast waits
  for the rod) and the held item follows it. The preview's Carry Point sits on the hand and is
  turned (#159).
- **THE HOLD, THE WRIST, PUT AWAY (0.18.0).** An item's `Hold` node is where the fist closes; the
  fist's hole is the circle inside the fist; carried steady, the wrist turns (`HoldWrist`) to keep
  the handle in it; Carry Point and Stow are nodes in the preview; items are put away on the back
  and drawn with clips on a new UPPER-BODY one-shot; the fisher's `rod_away` picks ON_BACK or
  IN_HAND (#158).
- **FIT TO THE HAND (0.17.0).** `GripFit` puts an item's handle in the hole the fingers make and
  points it (along the fist when an animation uses it, steady toward `carry_point` when it only
  carries it), clear of the body; the preview fits every animation and photographs them for a
  person to check (`grip_pictures/`); `tools/held/fit_grip.gd` does it from a shell (#157).
- **GRIPS BY ANIMATION AND BODY (0.16.0).** A held item has no modes: its grips are per animation
  and per body, and whatever plays an animation, the item sits in that animation's grip. The
  preview sets exactly the chosen animation for the chosen body. The angler's heave comes back
  down at its clip's own pace (#156).
- **BUILT FOR DESIGNERS (0.15.0).** Held items are a foundation system: grips per MODE and per
  ANIMATION, blended as the animations blend, steady per grip, lined up in an editor preview for
  any item (#153). A game tunes the foundation with `shared/rules.json` (health, interact range,
  round plans) and extends it through hooks (`on_player_created/returned/left`, `on_interact`)
  instead of editing `module.rs`; its per-world tables go in `NetConfig.world_tables`;
  `tools/publish.sh` builds, publishes and regenerates bindings; the test suites run on their own
  database, `umf-test` (#154).
- **RESTARTS, THE EDITOR PREVIEW, THE WATER (0.14.4).** A restarted client carries on the server's
  input count, so its first seconds are no longer dropped. A claim too far to believe is clamped
  as a whole, so no one lands inside the ground (#149). The rod-grip preview works IN THE EDITOR:
  `ModularCharacter` is a tool script (#147), and it shows what the game will: a woman and a man,
  and the reel's air at its worst through the clip (#152). The lake is coloured by its depth (#150).
- **PLAYTEST POLISH (0.14.3).** Grass keeps its colour at a distance: its palette is read
  without mipmaps (#146). The rod is held two ways, fishing and carrying, and carried steady while
  moving. The reel is off the leg, and the running rod no longer sweeps through the head. The grip
  is edited in the editor, in `rod_grip_preview.tscn` (#147). F11 / Alt+Enter / the Escape menu
  give fullscreen; in the editor's game view the menu says to use the view's ⋮ → Stretch to Fit
  (#148).
- **THE FIGHT, SHOWN (0.14.2).** The HUD's two bars are now a rod-and-reel gauge (`ReelGauge`),
  and the sweet spot is still undrawn. The angler performs the fight: the heave is a held pose
  scrubbed from `Fish_Reel`, the left hand winds the reel by IK, the rod bends and the line
  strains. A waiting angler holds the rod out, and a snap plays the fail clip (#144). The
  foundation's animation tree gained a HELD POSE layer for it (ANIMATION_SPEC §4). The fight rule:
  reel any time, and it pays when the fish is spent or resting. The yellow now lasts at least
  0.35 s (#145).
- **LAKESIDE REFINEMENTS (0.14.1).** Foliage lit on both sides — the "dark spots" were back faces
  (#141, and a windowed `tests/render_test.sh`); a fight's length is FfC's clamp of the cast, and
  the HUD's metres are the world's (#142); spots are gated by rod reach, placed by the level and
  measured by `cargo test --test level` (#143); slack line lies on the water.
- **THE LAKESIDE, AND FISHING FOR COMPLIMENTS' FISHING (0.14.0).** The game's level is a generated
  Terrain3D lakeside (`tools/world/build_lakeside.tscn`), baked for the server — water, depth,
  spots, spawn — into `shared/world/` and read by `level.rs` and its twin `LevelBake` (DECISIONS
  #138); the greybox is the test level (`use_level 0 0`, admin). FfC's systems are ported with
  the server deciding: the cast is AIMED at a point on the water and rolled at the cast; the
  hook-set is graded by a GDScript twin of the module's rule (#136); the fight is FfC's PUMP,
  which the client plays and the module REPLAYS from the input log, bit for bit (#140); spots
  deplete server-side; rod/reel/line each change a different thing. The angler faces the aim
  (`InputFrame.face`, #136). Characters are assembled from Quaternius' modular packs, one look
  per entity (#139). Lighting: TAA and tuned shadows (#137).
- **FRIENDS CAN PLAY IT (0.13.0).** A connect screen and an Esc menu (`foundation/ui/`), round
  results and a live leaderboard, the fishing presentation (rod, cast, float, water, splash, a
  leaping fish, generated sounds — `game/fishing/fishing_fx.gd`), export presets for a client and
  a dedicated server (`export_presets.cfg`), and NPC brains that resume after a sidecar restart
  (`npc_brain`). Each has a layer that plays it: `tests/connect_playtest.sh`, the fishing
  playtest plus a second client watching it (`tests/playtest/fishing_observer.gd`),
  `tests/export_test.sh`, and the restart step of `tests/sidecar_test.sh` (DECISIONS #122-#135).
- Phase 1 (blueprint) and Phase 2 (scaffold, event bus, SDK adapter, movement model, golden harness) are written. Motion authority is per-world: MODULE (Tier A, gravity-only + client trust) or SIDECAR (headless Godot). Tier B proxy collision was removed.
- **Phase 3 Task 0 is DONE (2026-09-18). Phase 2 is real — it compiles, publishes and connects.** End to end on Godot 4.7.1 + SpacetimeDB 2.10.1: `cargo test --test golden` 6/6 at `max_err=0e0`; `cargo check --target wasm32-unknown-unknown` clean; `spacetime build && spacetime publish umf --server local` creates all 7 tables and runs `init`; the 20 Hz scheduled `tick_movement` advances `world_config.server_tick`; codegen emits 26 files to `res://spacetime_bindings/` under alias `Umf`; `boot.tscn` prints `CONNECTED` → `local entity: N` → `world ready`; `client_connected`/`client_disconnected` create rows and flip `online`. `tests/run_tests.sh` is 30/30 with all three lints green.
- **The Rust half is GREEN too.** `cargo test --test golden` passes natively, 6/6 cases at `max_err=0e0`; `spacetime build` produces the wasm module. Getting there needed the crate split described in `docs/DECISIONS.md` #27 — **read it before touching `server/src/`**, because the two rules it imposes are not obvious: `sim.rs` must never depend on the `spacetimedb` crate (only `spacetimedb-lib`, with `#[sats(crate = spacetimedb_lib)]`), and every table/reducer lives in `module.rs` behind `#[cfg(target_arch = "wasm32")]`. Violating either one breaks `cargo test` at link with ~20 unresolved externals (`datastore_insert_bsatn`, `console_log`, …).
- Because `module.rs` is wasm-gated, a bare `cargo check` does **not** type-check tables or reducers. Always use `cargo check --target wasm32-unknown-unknown` — that is the check that counts.
- SDK and SpacetimeDB API bindings were verified against the upstream SDK docs (`docs/api.md` + `docs/codegen.md`) and `docs.rs/spacetimedb/2.10.0` when written. The vendored copy in `addons/SpacetimeDB/` is **v2.8.0 and ships no `docs/` folder** — verify against its source, not against a file that isn't there.
- **Task 2 done** (`foundation/core/spacetime_component.gd`, 13 checks in `tests/test_runner.gd`).
- **Task 1 PART DONE.** Verified live against the local server, not just compiled:
  - `world_id: u32` `#[index(btree)]` on `entity`, `movement_state`, `health_state`, `input_queue`; `world_config` re-keyed to `world_id` and given `authority_online`; `tick_movement` ticks each world independently and only simulates MODULE worlds. Two worlds confirmed ticking separately.
  - `authority` table, publisher seeded as admin in `init`; `require_admin` / `require_authority` helpers; `register_authority` / `revoke_authority`; `heartbeat` + scheduled `check_authorities` (1 Hz, 5 s timeout) driving `authority_online`.
  - Authority-only: `write_movement_batch`, `apply_damage`, `spawn_npc`, `despawn_entity`. `create_world` / `set_sim_authority` are admin-only.
  - `look_pitch: f32` on `InputFrame` — Rust, GDScript, `to_reducer_args`, the adapter's wire builder and the golden harness. Goldens unchanged at `max_err=0e0` (the frozen twin ignores pitch), so this was a schema-only edit to `sim.rs`, not a change to the frozen movement math.
- **Task 1 second pass done — everything the fishing genre needs.** Ordering follows `docs/TEMPLATE_WORKFLOW.md` step 2 (prove the foundation with one genre before templating); `docs/GENRE_ADAPTERS.md` §1 lists fishing's foundation dependencies as session, challenge, inventory and Tier A, none of which are the combat/NPC tables.
  - `session` (one per world, unique `world_id`) + `session_member`, 1 Hz `advance_phases` running LOBBY→PLAYING→RESULTS with score reset and a fresh seed each new round, `create_session` (admin), `join_session` / `leave_session` (which move the entity's whole row set between worlds), authority-only `add_score`. `client_connected` auto-joins the default world's session.
  - `item_def` + `inventory_item`: `seed_item_defs` (idempotent, admin), authority-only `grant_item` that fills partial stacks before opening new ones, player-callable `consume_item` / `set_item_slot`.
  - `challenge` + `issue_challenge_internal` (the hook a genre's `cast`/`interact` calls) + `submit_challenge_result` + 0.2 Hz `prune_challenges`.
- **The challenge validator is the first proven Rust⇄GDScript parity pair.** `server/src/challenge.rs` ⇄ `foundation/sim/challenge_model.gd`, both at `max_err = 0e0` over `shared/golden/challenge/challenge_timing.json` (8 cases + 6 rejection cases), generated independently with NumPy float32. Read the parity rules at the top of both files before touching either — the f32 discipline is not optional and the failure mode is silent drift.
- **Task 14 done.** `sidecar/npc/` has the brain component, a `wander` and a `chase` brain, and
  fishing's rival angler (kind 1) is driven by one (DECISIONS #109-#111). `npc_brain` +
  `write_npc_brain` persist what a brain needs to resume after a restart (#135).
- **Task 13 done.** `SERVER_AUTHORITY` + `sidecar/` run a world for real (DECISIONS #106-#108);
  `tests/sidecar_test.sh` drops an entity into the air in a SIDECAR world and proves the sidecar
  is what makes it fall. The "Windows Server" export preset builds it as a dedicated server, and
  `tests/export_test.sh` runs the sidecar suite against that build (#134).
- **Task 11 done.** `InterestManager` autoload owns the core subscription set, keyed by
  `world_id`, with the overlapping world switch and the `build_queries()` hook the sidecar and
  the MMO cell layer override (DECISIONS #104).
- **Task 1 REMAINING** (none of it needed for fishing): `action_request`. `npc_brain` + `write_npc_brain` are done (#135).
- **RLS works on 2.10.1** — `challenge` and `input_queue` are public behind `#[client_visibility_filter]` (needs `features = ["unstable"]`). The crate's "currently unimplemented, and are not enforced" TODO is stale; verified with an anonymous-identity control (`docs/DECISIONS.md` #32). Re-run that control after any SpacetimeDB upgrade: if enforcement regresses, `challenge.seed` leaks to every client and the anti-cheat story in #19 collapses silently.
- **Tasks 9 and 10 done.** `SpaceTimeInventoryComponent` + `ItemDefinition` (many rows per entity — DECISIONS #53) and `InteractionComponent` + the server's `interact` reducer, whose range check is the real one: the client raycast only decides what to PROMPT.
- **Task 15 DONE: characters animate** (DECISIONS #94-#98). `foundation/anim/` holds `AnimationSet` + `AnimationClipRef` + `AnimationTreeBuilder` + `AnimationDriverComponent`; `game/anim/` holds the extracted Quaternius libraries (CC0) and the generated sets; `game/characters/mannequin_f.glb` is the default rig. The tree is GENERATED from the set — never hand-author one. Remote entities animate from `move_state` + the mirrored jump/land events; the local one from its prediction.
- **THE FISHING LOOP IS PLAYABLE END TO END** (mouse look, crosshair, cast, minigame, catch) as of DECISIONS #89-#93. It was not before: the cursor was never captured, the interaction ray ended behind the player in third person, and E sent the wrong reducer. All four older test layers were green throughout, because they call `cast` directly — `tests/fishing_playtest.sh` is the layer that plays the game instead.
- **IT IS PLAYABLE.** With a published module, press Play in the editor — `run/main_scene` is the fishing scene, Debug ▸ Customize Run Instances ▸ 2 gives two players, and each instance claims its own identity automatically (DECISIONS #61, #62). `GODOT=<path> ./game/fishing/play_local.sh 2` does the same from a shell, republishing from scratch and skipping the 30 s lobby. WASD/Shift/Space to move, E to cast at a spot, Space or E on the markers. `VIEW=--first-person` swaps the camera. **F3** toggles the net overlay; **F4** cycles simulated latency (`--latency=`/`--jitter=` at launch). Movement is Phase 4 predicted and reconciled — see DECISIONS #68-#79 before touching `spacetime_movement_component.gd`, `LocalInputComponent`, or `tick_world_module`.
- **Movement works (Tier A).** `movement_model.gd` gained horizontal movement; `sim.rs` stays frozen because Tier A trusts `client_pos` (DECISIONS #57). `LOCAL_PREDICTED` is client-authoritative-within-trust, NOT Phase 4 reconciliation (#59).
- **Swapping models and camera framing is a `.tres` edit** — `EntityDefinition.visual_scene` and `.camera_rig` (DECISIONS #60). `foundation/camera/` ships first/third person presets.
- **THE FISHING GENRE HAS STARTED.** `server/src/game/` holds it, behind two hooks (DECISIONS #54). The loop works end to end: walk to a spot → `cast` → play the timing-bar Challenge → the module re-simulates your presses and writes a `catch`. Integration-tested including the negative cases (wrong phase, out of range, double cast, and a non-fishing challenge producing no fish).
- **Foundation never imports from `game/`.** If making a game work seems to need an edit to `module.rs`, widen a hook instead.
- **Task 8 done.** `SessionComponent` + `SignalBus.session_phase_changed` / `session_score_changed`. It is the first component to read a non-entity row (`session`) off `EntityRegistry.global_row_event` — DECISIONS #47.
- **Four test layers, all green** (DECISIONS #51): 222 unit+scene checks · 68 server integration · 25 end-to-end · 3 Rust suites. **Adding a component means adding its table to `NetConfig.core_tables`** or it silently never binds (#49).
- **Task 7 done.** `LocalInputComponent` samples input into `InputFrame`s each physics tick on the owning client only, with camera-relative `move_dir`, magnitude clamped so diagonals are not faster, and a monotonic `seq`. It SAMPLES ONLY — Phase 4 connects `input_sampled` to prediction and `submit_input`. Input actions are defined in `project.godot`.
- **Scene-level testing exists.** `tests/levels/greybox.tscn` (floor, walls, platform, spawn point) plus a suite that spawns the real `player.tscn` through the real `EntitySpawner` and steps real physics frames. `tests/levels/greybox_demo.tscn` is the runnable version: `godot --path . res://tests/levels/greybox_demo.tscn` against a live server. Read DECISIONS #45 before proposing a test framework — the trigger to adopt one is defined there.
- **If the editor disagrees with a headless run, the editor is stale** (DECISIONS #46). Autoload edits to `project.godot` need an editor restart; headless runs are authoritative.
- **Task 6 done.** `SpaceTimeMovementComponent`: REMOTE_INTERPOLATED (snapshot ring, render at `server_now - remote_interp_delay`, velocity extrapolation clamped to 100 ms) and SERVER_DRIVEN. Discrete events (`jumped`/`landed`/`move_state_changed`) are read off the AUTHORITATIVE row sequence, never the interpolated view. LOCAL_PREDICTED is Phase 4 and SERVER_AUTHORITY is Task 13; both `push_error` rather than silently doing nothing.
- **Testing is now three layers, all green:** 149 headless GDScript checks, 3 Rust suites (movement golden, challenge parity, wasm type-check), and 68 server integration assertions against a live module. Before changing how tests run, read DECISIONS #37, #42 and #43.
- **Tasks 3, 4 and 5 done.** `EntityDefinition` + `SpaceTimeEntity` + `foundation/entities/player.tscn`; the `EntitySpawner` autoload (registered after `EntityRegistry`) with the reconnect-rebind path from DECISIONS #17; `SpaceTimeHealthComponent` + `HealthConfig`. 125 headless checks green.
- **Proven live, not just unit-tested:** the client connects, `EntitySpawner` instantiates every `entity` row and flags its own as local, and a server-side `apply_damage` reaches `SignalBus.entity_died` on the client. `boot.tscn` registers `player_definition.tres` and logs the whole chain — run `godot --headless --path .` against a live server to see it.
- `player.tscn` grows one component per task: Health is in, Movement arrives with Task 6, Input with Task 7. Its `Components` node is the only place the entity looks for them.
- The test harness is a SCENE (`tests/test_runner.tscn`), not a `--script` run — see DECISIONS #37 before changing how tests are launched.
