# AGENTS.md — operating rules for any AI agent working in this repo

Read this first. Then `docs/ARCHITECTURE.md`. Then the spec for the phase you are on.

## What this is
Universal Multiplayer Foundation: Godot 4.7 (strictly typed GDScript 2.0; 4.6 is the floor) client + SpacetimeDB 2.10 Rust module.
A genre-agnostic core (movement, sync, health, inventory, interaction) that genre layers build on.
Godot's high-level multiplayer is **not used**. SpacetimeDB is the authoritative state; Godot is a passive view with client-side prediction on top.

**The repo root IS the Godot project.** `project.godot`, `foundation/`, `tests/`, `addons/` and (later) `sidecar/`, `game/`, `spacetime_bindings/` are all `res://`. `server/` (Rust) and `shared/` sit alongside them in the same tree; `shared/` is reachable as `res://shared/`. Earlier bundles nested all of this under `client/` — that folder no longer exists, so read any `client/...` path in an old note as root-relative.

## Built for designers (the owner's standing priority)
- This is a TEMPLATE: game designers, world designers and developers must be able to add and
  change things without editing the foundation or each other's work. Judge every change by that.
- Prefer what a designer can edit to a constant in code: data in `shared/*.json`, a `.tres` in
  the Inspector, a node placed in a scene, an editor preview. A genre never edits `foundation/`
  or `module.rs`; if it seems to need to, widen a hook (`docs/HANDBOOK.md` §11 lists the
  missing ones).
- The owner did not write this code and must be able to run it alone. `docs/HANDBOOK.md` is the
  human guide: a change to how something works, what it depends on, or what a change to it
  takes (restart, republish, codegen, regenerate) updates the handbook IN THE SAME CHANGE.

## Current state
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

## Hard rules (violations fail review)
1. Strictly typed GDScript. Every var/param/return typed. `:=` only when the RHS is a constructor.
2. No `@rpc`, `MultiplayerSynchronizer`, `MultiplayerSpawner`, `ENetMultiplayerPeer`.
3. Only `foundation/net/spacetime_sync.gd` may reference SDK types, the `SpacetimeDB` autoload, or `spacetime_bindings/`. `tests/run_tests.sh` greps for this.
4. Components never own authoritative state. They receive it via `_on_row_updated(table, old, new)`. They may own `predicted` and presentation state only.
5. Components never reference UI. Low-frequency, `entity_id`-first events go on `SignalBus`. Position/velocity never go on `SignalBus`.
6. Rows delivered by the SDK are the cache's own `Resource` instances. **Never mutate one.** Copy values out (`MovementState.from_row`) or `duplicate()`.
7. Movement math: `Vector3` (f32) only in `movement_model.gd`; it is shared by client prediction and the sidecar. Every change ships regenerated GDScript golden vectors. The Rust `sim.rs` twin is frozen (Tier A idle only) — do not extend it. Rust⇄GDScript parity with `max_err = 0` applies to Challenge validators.
7b. Authority logic (NPC brains, hit resolution, spawn/loot rules) lives ONLY under `sidecar/`, which is excluded from the client export. Nothing in `foundation/` or `game/` may reference `res://sidecar`. Lint-enforced.
8. Two-phase init: `_ready()` never touches synced data; `bind()` does.
9. Every table that describes an entity has `entity_id: u64` as PK and (from Phase 3) `world_id: u32`.
10. Server tunables live in `shared/movement_config.json` only. Never hand-edit `movement_config.tres` or `movement_config.rs`.
11. Animation and VFX never produce gameplay events; they read state (`docs/ANIMATION_SPEC.md`). AnimationTrees are generated by `AnimationTreeBuilder`, never hand-authored.
12. One file per task. State assumptions inline as `# ASSUMPTION:` comments; do not silently guess API names.

## Verify loop
```bash
# Rust type-check against the real target. `module.rs` is wasm-gated, so a BARE `cargo check`
# skips every table and reducer — always pass the target. This is the one that counts.
cd server && cargo check --target wasm32-unknown-unknown

# Rust golden harness (native, no server needed)
cd server && cargo test --test golden          # add -- --nocapture to see per-case max_err
cd server && cargo test --test challenge       # Rust half of the validator parity pair
cd server && cargo test --test level --test fishing --test fight   # the lakeside bake, fishing's
                                               # rules, THE FIGHT (+ its golden file; see below)

# Godot (headless) — lint + binding contract + golden + unit tests.
# Fails on unexpected engine/script errors too, not just failed checks (DECISIONS #42).
GODOT=<path> ./tests/run_tests.sh

# Publish the module (and, with --codegen, regenerate the client's bindings) — one command.
# `--fresh` wipes the data (a table changed shape). DB=<name> for another database.
# THE OWNER IS ON WINDOWS: give them `tools\publish.cmd` and `tools\run.cmd tests\<suite>.sh`
# (Git Bash underneath; tools/local.env holds this machine's GODOT), never a bare `./x.sh`.
# --codegen reads the schema of `umf` (the module's name) and refuses any other DB: to change the
# bindings, publish `umf` (adding a table keeps its data; changing a table's shape needs --fresh).
GODOT=<path> ./tools/publish.sh [--fresh] [--codegen]

# Server reducers — the ONLY automated coverage of module.rs (DECISIONS #43).
# Needs `spacetime start`; republishes with --delete-data. EVERY server suite does, on the TEST
# database `umf-test` (DECISIONS #154): `DB` defaults to it and `UMF_DB` carries it to every Godot
# process the suite starts. `umf` is the owner's play database; a lint in run_tests.sh stops a
# suite naming it. Needs GODOT too: it plays fights through the client's simulation.
GODOT=<path> ./tests/integration_test.sh

# END TO END — a real client against the real module (DECISIONS #51). Run this before
# claiming anything works: it is the only layer that exercises BSATN, the SDK adapter and
# the generated bindings together, and it has found bugs that passed all three other layers.
GODOT=<path> ./tests/e2e_test.sh

# TWO clients at once. Distinct identities, mutual visibility, seeded world content
# (DECISIONS #62). Two clients sharing one identity raise no error anywhere and pass every
# other suite, so this is the only place that failure mode is visible.
GODOT=<path> ./tests/multiclient_test.sh

# MOVEMENT FEEL: scripted keys through the real input path in the real fishing scene, at
# several simulated latencies; and a walker + observer pair for remote smoothness
# (DECISIONS #79). Run both after ANY change to movement, input, the adapter or the tick.
GODOT=<path> LATENCIES="0 100 200" ./tests/playtest_test.sh
GODOT=<path> ./tests/remote_playtest.sh

# THE GAME, PHOTOGRAPHED: SHOTS=<dir> plays it in a WINDOW (at 0 ms) and saves a picture of every
# moment in <dir> (grip_pictures/ is not committed): LOOK at them after anything visual changes.
# THE GAME, PLAYED. Walks from the lakeside's spawn to the end of the dock on the movement keys,
# aims (and turns to face the aim), casts with the cast button, sets the hook, FIGHTS the catch in
# on the real buttons and the mouse wheel — which the module replays — then reads the standings
# and shops, while a SECOND client (fishing_observer.gd) checks it saw the turn, the cast, the
# float and the catch. Run it after any change to input, the camera, presentation or the genre's
# own verbs: it is the only layer that fails when the game stops being playable while every
# reducer still works.
GODOT=<path> ./tests/fishing_playtest.sh

# THE FRONT DOOR. The connect screen and Esc menu driven with typed keys and clicks: a bad
# address, a dead port, the wrong kind of server, a real connect, disconnect and back in, on a
# FRESH INSTALL (DECISIONS #122-#126). Run it after touching boot, the adapter's connection
# path, MouseCapture or foundation/ui/.
GODOT=<path> ./tests/connect_playtest.sh

# THE BUILDS. Exports both presets, reads what each pack contains, runs the client against the
# module and the server through the whole sidecar suite (#134). Needs the export templates.
GODOT=<path> ./tests/export_test.sh

# THE LOOK: checks that need pixels, so it opens a small window (every other layer is headless,
# and the headless renderer draws nothing). Foliage lit the same from both sides (#141), the
# grass's colour (#146), the lake's depth (#150), the grip preview's pictures (#157), F11 (#148).
GODOT=<path> ./tests/render_test.sh
# or via Godot MCP: run `tests/test_runner.gd` headless with `--path . -s tests/test_runner.gd`

# Sidecar (dedicated-server export or from source)
godot --headless --path . -- --world=1

# Module build/publish (needs the wasm32-unknown-unknown target and a running `spacetime start`)
cd server && spacetime build && spacetime publish umf --server local

# Codegen (after publish). The config step replaces the editor dock; cli.gd refuses without it.
# The SECOND --import is not optional: it registers the generated `class_name`s in
# .godot/global_script_class_cache.cfg. Skip it and the SpacetimeDB autoload fails to parse
# with `Could not find type "UmfModuleClient"`.
godot --headless --path . -s tools/codegen_config.gd
godot --headless --path . --import
godot --headless --path . --script res://addons/SpacetimeDB/cli.gd
godot --headless --path . --import

# Smoke test against a live server: expect CONNECTED → local entity: N → world ready
godot --headless --path .
```
Golden output must read `max_err=0.000e+00` on every case on both sides. A non-zero value under tolerance is a parity bug, not a pass — do not widen the tolerance.

## Using Godot MCP
- Prefer running the headless test script over opening scenes; scenes only exist for `boot.tscn` and (from Phase 3) `player.tscn`.
- After editing any `.gd` with `class_name`, trigger a re-import so `.godot/global_script_class_cache.cfg` updates; otherwise `class_name` lookups (and `SpaceTimeSync._find_global_class`) fail.
- If the editor reports "SpacetimeDB.Umf not found": codegen hasn't run, or the alias differs from `NetConfig.module_alias`.
- Godot's `push_error` output in headless runs goes to stderr; the runner exits 1 on any failed check.

## File map
```
AGENTS.md                      this file
README.md                      human overview + run instructions
docs/HANDBOOK.md               THE HUMAN GUIDE: systems, player loading, the server, what to edit
                               and what each change takes, recipes, the modularity gaps
docs/ARCHITECTURE.md           principles, node tree, data flow, contracts, SDK facts
docs/PHASE3_SPEC.md            entity framework + base components + foundation additions (NEXT)
docs/PHASE4_SPEC.md            client-side prediction & reconciliation (after Phase 3)
docs/SIDECAR_SPEC.md           headless Godot as motion/NPC authority: trust model, reducers, runtime, deploy
docs/ANIMATION_SPEC.md         animation contract, AnimationSet, generated AnimationTree, FeedbackComponent
docs/TEMPLATE_WORKFLOW.md      how games are created from the foundation; GAME_BRIEF.md template
docs/GENRE_ADAPTERS.md         how four target genres map onto the foundation
docs/DECISIONS.md              decision log (why things are the way they are)
docs/ROADMAP.md                THE TODO LIST: before a friend test, fishing features, template
                               features, what the chicken game and disc golf need, in order
shared/game.json               THE GAME: which genres it is made of (server and client read it)
foundation/core/genre_module.gd + genres.gd  a genre's client half (game/<name>/genre.tres), loaded by Boot
foundation/ui/lobby_panel.gd   the lobby between rounds: who is here, ready (R), teams (T)
foundation/ui/lobby_screen.gd  the lobby screen after connecting: everyone's characters, Choose
                               character, Ready, Join (#182)
foundation/ui/splash_screen.gd the splash before the connect screen; game/splash_screen.tscn is
                               the game's (#183)
foundation/level/              LevelInfo + LevelSpawn/LevelSpot/LevelPoint (a level built in the
                               editor), LevelBaker (scene -> server bake), LevelLoader (the level on
                               screen follows world_level)
tools/world/bake_level.gd      bake a level scene: --scene=res://...tscn
game/world/levels/meadow.tscn  the example level built in the editor (level 2)
game/fishing/genre.tres        fishing's client half: definitions, tables, HUD + fishing_world.tscn
tests/genres_test.sh           the server built from a game of no genres
foundation/core/settings.gd    Settings autoload: this machine's video/audio/controls, as data
foundation/core/appearance.gd  a chosen look as text ("ranger_f;hair=2")
foundation/ui/settings_panel.gd  the settings screen, drawn from the definitions
foundation/ui/character_picker.gd  choose a look and its options, in a turning preview
foundation/audio/music_director.gd  music by round phase, on the Music bus
foundation/net/schema_fingerprint.gd  the version check's fingerprint
foundation/held/off_hand.gd    the other hand on a held item (grip data, the same IK in game and preview)
default_bus_layout.tres        the audio buses: Master, Music, Effects, Ambience, Voice
tools/write_schema_fingerprint.gd  run by publish.sh --codegen
tools/synth_music.gd           generates game/fishing/music/*.wav
game/fishing/fishing_conditions.gd  the round's time of day and weather, named
game/fishing/fishing_records.gd + catch_journal.gd  the journal and the all-time records (J)
game/characters/character_looks.gd  the character picker's choices: every piece per slot and body
                               (SLOTS), their colours, skin and hair
game/world/sky_director.tscn (+ sky_look.gd, weather_look.gd)  the sky follows the round
docs/CHANGELOG.md              bundle version; 0.3.1
foundation/core/               SignalBus · ClockSync · EntityRegistry · EntitySpawner · SpaceTimeComponent · SpaceTimeEntity · EntityDefinition · AppExit (the one way to quit)
foundation/components/         Health · Movement · LocalInput · Session · Equip (in hand or put away)
                               components + configs
foundation/entities/           player.tscn · player_definition.tres
foundation/net/                SpaceTimeSync (SDK adapter) · NetConfig · RowEvent · ReducerRequest · SubscriptionSet
foundation/sim/                MovementModel · MovementState · InputFrame · MovementConfig · ChallengeModel
foundation/tools/              EditorScripts (config codegen; collider exporter in Phase 3)
tests/                         test_runner.tscn/.gd (headless suites) · run_tests.sh (lint + tests)
tests/integration_test.sh      server reducers against a live local module
tests/multiclient_test.sh      TWO real clients at once: distinct identities, mutual visibility
tests/playtest_test.sh         movement playtest (tests/playtest/movement_playtest.*) at 0/100/200 ms
tests/remote_playtest.sh       walker + observer: remote smoothness under simulated latency
foundation/debug/              net_debug_overlay.tscn — F3 netcode readout, F4 latency
tests/levels/                  greybox.tscn (scene-test level) · greybox_demo.tscn (runnable)
tests/e2e/                     e2e_runner.gd + e2e_test.tscn — real client vs real module
tools/                         codegen_config.gd (writes plugin_config.tres for headless codegen) ·
                               publish.sh (build + publish + codegen, one command) · run.cmd +
                               publish.cmd (the bash scripts on Windows, via Git Bash; this
                               machine's GODOT in tools/local.env, not committed)
foundation/held/               HeldItem · ItemGrip · GripEntry · BodyClearance · SkinClearance (arms
                               against the skin) · GripFit ·
                               HoldWrist (the shut hand, the wrist turn) · held_item_preview.gd (held items:
                               grips per animation and body, fitted to the hand, put away, lined
                               up in the editor)
tools/held/fit_grip.gd         fit a grip file and photograph it from a shell (needs a window)
grip_pictures/                 Save Pictures' sheets (not committed; a .gdignore keeps them out
                               of the import)
shared/rules.json              the foundation's rules as the game sets them (health, interact
                               range, round plans); compiled in by build.rs, read by `Rules`
sidecar/                       (Phase 3) SERVER-ONLY: sidecar_main · authority_sync · sim_world · npc/ · combat/
addons/SpacetimeDB/            vendored SDK (plaught-armor fork) — only spacetime_sync.gd may touch it
spacetime_bindings/            GENERATED, alias `Umf` — 26 files; commit them
server/src/sim.rs              FROZEN gravity-only twin + wire types. spacetimedb-lib ONLY (DECISIONS #27)
server/src/challenge.rs        pure challenge validators; GDScript twin + goldens. No spacetimedb dep
server/src/module.rs           tables + reducers — wasm32-gated (DECISIONS #27)
server/src/game/               THE GENRE LAYER, server half. Foundation never imports from here
game/fishing/                  THE GENRE LAYER, client half: fisher.tscn, HUD, play_local.sh
foundation/camera/             CameraRig + first_person.tres / third_person.tres
foundation/anim/               AnimationSet · AnimationClipRef · AnimationTreeBuilder · AnimationDriverComponent
sidecar/                       SERVER-ONLY: sidecar_main · sim_world · authority_sync · sidecar_net_config.tres
sidecar/npc/                   NpcBrain · NpcWorldView · NpcBrainComponent · brains/wander.gd · brains/chase.gd
tests/sidecar_test.sh          a real sidecar against the real module, with an unregistered control
                               and a restart (the NPC's brain resumes); SIDECAR_BIN= points it at a build
tests/connect_playtest.sh      the connect screen + Esc menu, driven like a player (fresh install)
tests/export_test.sh           export both presets, inspect the packs, run both builds
tests/playtest/fishing_observer.*  the second client in the fishing playtest
foundation/ui/                 connect_screen.tscn (+ ConnectSettings in net/) · pause_menu.tscn ·
                               window_mode.gd (fullscreen: F11 / Alt+Enter / the menu's button)
export_presets.cfg             "Windows Client" (no sidecar/) · "Windows Server" (dedicated, boots the sidecar)
tools/pck_list.py              list the files inside an exported .pck
tools/synth_fishing_sfx.gd     generates game/fishing/sfx/*.wav (deterministic, CC0)
tools/print_user_dir.gd        prints user:// for shell harnesses
game/fishing/                  + fishing_fx (presentation) · fishing_feedback · fishing_rod (+
                               rod_blank.gdshader: the bend, the reel handle, the winding IK) ·
                               reel_gauge (THE FIGHT on the HUD) · rod_grip.tres (the rod's ItemGrip:
                               how it sits in the hand per animation and body) · rod_grip_preview.tscn
                               (edit it in the EDITOR: pick an animation and a body, drag the Grip) ·
                               fishing_data (the content, from shared/fishing/) · fight_sim (THE
                               FIGHT's twin) · gear_component · fishing_standings ·
                               lakeside_game.tscn (main) · fishing_game.tscn (greybox) ·
                               feel_preview.tscn (F6: the presentation, no server) · sfx/
game/world/                    lakeside.tscn (GENERATED) · lakeside_level.gd · lake_water · terrain/ ·
                               kits/ (Quaternius nature, village, props + quaternius_import.gd,
                               foliage_material.gd + nature_foliage*.gdshader: leaves lit both sides) · buildings/
tools/world/                   build_lakeside.tscn (the generator) · lakeside_shape.gd (the shape, and
                               where the spots go) · lakeside_shots.tscn (PNG views, `--shot=` for
                               ad-hoc ones, `--angler=` for a line on the water) · gen_level_probes.py
tests/render/ + render_test.sh THE LOOK: windowed checks that need pixels (foliage, grass colour at a
                               distance, the lake's depth colours) and a real window (F11 and back)
shared/world/                  <level>.json + <level>_depth.bin: the bake the server compiles in
server/src/level.rs            the bake, read by the module; twin of foundation/sim/level_bake.gd
server/src/genre/              fishing's PURE rules: fishing.rs (rolls, hook-set) · fight.rs (THE FIGHT)
shared/fishing/                fishing.json (catalogue, spots, gear, timings) · fight.json (GENERATED
                               by tools/fishing/gen_fight.py: the fight's tuning + catch profiles)
shared/golden/fishing/         hookset.json (NumPy) · fight.json (from server/tests/fight.rs)
tools/fishing/                 gen_goldens.py · gen_fight.py · fight_bot_cli.gd (play a fight from a shell)
tests/fight_bot.gd             FfC's probe players, for the integration suite and the playtest
game/anim/                     extracted AnimationLibrary .res + generated .tres sets + ATTRIBUTION.md
game/characters/               modular_character.gd · looks/ (GENERATED by tools/characters/make_looks.py)
                               · quaternius/ (imported pack parts, ATTRIBUTION.md) · mannequin_f.glb
                               · character_preview.tscn (F6; UP/DOWN looks, L lineup)
tools/characters/              import_quaternius_characters.py · make_looks.py
tools/extract_animation_library.gd  source .glb/.fbx -> portable AnimationLibrary .res
tools/animation_set_builder.gd      fuzzy-match clip names -> AnimationSet .tres (read its report)
server/src/lib.rs              crate root: `pub mod sim` + `movement_config` + the gated `mod module`
server/tests/golden.rs         golden harness
shared/movement_config.json    single source of truth for tunables
shared/golden/movement/        float32 movement vectors (GDScript regression)
shared/golden/challenge/       float32 validator vectors (Rust AND GDScript, max_err = 0)
```

## When you are unsure
- SDK behaviour → **read the vendored source** under `addons/SpacetimeDB/` (`spacetime.gd`, `core/`, `core_types/`, `nodes/`); this copy has no `docs/` folder, so the upstream `docs/api.md` is only available in the plaught-armor repo. Key facts are summarised in `docs/ARCHITECTURE.md` §SDK — treat the vendored source as the tiebreaker.
- Rust module API → `docs.rs/spacetimedb/2.10.0`. Do not use 1.x spellings (`name =`, `ctx.sender` as a field, `ScheduleAt::Interval(...)`).
- Design intent → `docs/ARCHITECTURE.md`, then `docs/DECISIONS.md`. If still unclear, leave an `# OPEN QUESTION:` comment and pick the option that keeps the genre layers thinner.

## ENTITY CONVENTIONS (DECISIONS #68, #69)
- An entity body's origin is at its FEET. `pos.y == ground_y` means standing on the ground; a
  collision shape centred on the origin puts the body half inside the floor.
- Entity bodies: `collision_layer = SpaceTimeEntity.ENTITY_MASK`, `collision_mask =
  SpaceTimeEntity.WORLD_MASK`. Level geometry stays on layer 1. Entities never collide with each other.
- A component whose table may legitimately have NO rows for an entity (a collection) lists it in
  `optional_tables()` as well as `required_tables()`, or every spawn waits out `bind_timeout_sec`.
- `InputFrame` and `movement_state` changed shape (`epoch`, `correction_epoch`, `move_state`,
  `dash`): after changing either, republish and regenerate bindings, then `--import` so new
  class_names register.

## QUITTING (DECISIONS #151)
- Every process quits through `AppExit.quit(get_tree(), code)`, never `get_tree().quit()` (linted).
  A stopped sound is released by the audio server's mixing thread a pass or two later, and a
  process that quit within milliseconds of the stop reported the pond ambience leaked about half
  the time. AppExit stops every sound and waits 0.1 s first. A window's close button goes the
  same way (`AppExit.hold_close_request` + NOTIFICATION_WM_CLOSE_REQUEST, in `boot.gd`).

## EDITOR PREVIEWS (DECISIONS #147, #152)
- In the EDITOR only `@tool` scripts run; every other script is a placeholder with its exported
  data and none of its methods. A tool preview may READ a non-tool resource's exports
  (`AnimationSet.clips`, `EntityDefinition.visual_variants`) but never call its methods: the
  call fails, and the preview stands empty. `ModularCharacter` is a tool script so looks
  assemble in the editor. A runtime test cannot see any of this; check the source (the grip
  suite does), or look in the running editor.
- A `@tool` resource saves only non-default values: keep its defaults neutral so the file
  records every value that matters (`GripEntry`).
- The editor reloads a tool script under an OPEN scene when its file changes, and keeps the
  instance's variables. Keep them to engine types (nodes, numbers, arrays of those); objects of
  a class declared in the script are the known hazard across a reload, and the editor crashed
  while one was being rewritten (#152). Rewriting a tool script while its scene is open in the
  owner's editor can take that editor down: check the script in an editor of your own first.
- A preview shows what the GAME will: the bodies the game dresses people in, and the whole clip
  the game plays, not one frame of it. The grip preview showed a man in one frame, clear of the
  leg, while the game drew the same grip 5 cm inside a woman's (#152).

## HELD ITEMS (DECISIONS #153, #156)
- An item in a hand is a `HeldItem` (root at its grip point) with an `ItemGrip`: `GripEntry`s per
  ANIMATION and BODY, and nothing else: there are no modes. An animation uses its own grip, else
  the one its clip falls back to, else the idle's. Whatever plays an animation, the item follows
  it. Never place a held item by hand in code, and never tell one how to be held: give the
  animation a grip. A genre that needs one animation held two ways plays two animations.
- The game BLENDS the grips by `AnimationDriverComponent.semantic_weights()`. The locomotion
  points are read back by `AnimationTreeBuilder.LINE_POINTS/PLANE_POINTS`, the order
  `_build_ground` adds them: change one, change the other (the animation-scene suite checks).
- STEADY is per grip: its turn is in the BODY's frame, its position in the hand's. `set_steady`
  restates a grip without moving the item.
- `held_item_preview.gd` is a tool script and holds only engine types (#152). It may call
  `ItemGrip`, `GripEntry` and `BodyClearance` (tool scripts) and read the definition's data; it
  may not call a method of `AnimationSet`, `EntityDefinition`, `HeldItem` or the item's script.
- An item marks the points to keep off the body with a `clearance_radius` meta (metres); one
  that also has `clearance_to` (a NodePath) is a LINE to that node (the rod's `Shaft` to `Tip`).
  The preview measured only the reel once and called a run green while the blank went through
  the head (#156).
- The preview sets EXACTLY the chosen (animation, body): a drag or Steady makes it where the item
  already sits (`ItemGrip.ensure`), Clear This Grip removes it. The idle's shared grip is never
  removed: everything ends up borrowing it.
- THE HOLD (#158): grips place an item's `Hold` node, not its root (`GripFit.hold_of`); compare
  a drawn item through `HeldItem.hold_offset()`, and the hand through `HeldItem.hand_now()`: the
  wrist modifier's turn shows only during the skeleton's update and is undone after it, so a
  skeleton read after the frame is the clip's hand, not the drawn one.
- THE WRIST (#158): steady grips turn the hand (`HoldWrist`, `GripFit.wrist_turn`, up to
  `wrist_turn_deg`). The preview turns it the same way (`_turn_wrist`); a fit samples the clip's
  own hand and turns it per try. `GripFit.hole(..., false)` (no circle) is the per-frame call.
- PUT AWAY (#158, #159): IN HAND IS GAME STATE, `EquipComponent`, on its own clock (never an
  animation's). A genre calls `needed()` while using the item and checks `is_equipped()` before a
  verb that needs it in hand, WAITING (the cast) rather than playing it early. The item follows it
  (`HeldItem.follow`): draw/put-away on the UPPER-BODY one-shot, the swap when the state flips.
  Only ANOTHER player's verb, already playing when it arrives, may put the item in hand at once
  (`set_equipped_now(true)`), never with a draw under it: the draw would cover the arms of
  whatever pose follows. Our own state comes from our rig, theirs from their rows.
- THE EQUIP ROW (#160): the OWNER's EquipComponent reports every change (`set_equip_state`) and
  every other client's copy follows the `equip_state` row (`needed()`/`in_use()` are ignored
  there). `deciding()` is true for ours and for an entity nobody reports for (an NPC): only those
  run the idle and speed clocks. Our own verb's animation still playing keeps the item out with
  `in_use()` (never `needed()`: it must not draw).
- FIT, THEN LOOK (#157). `GripFit.hole` finds the fist's hole from the finger bones; `fit` puts the
  grip point there and points the item along the fist when the animation USES it, steady toward
  `ItemGrip.carry_point` when it only CARRIES it (`GripFit.CARRY_FOR`), then searches turns until
  it clears by 2 cm. A miss is reported with the hand's OWN air: when the animation puts the hand
  in the body, no grip clears it, so do not loosen the check. Look at the pictures (Save Pictures,
  or `godot --path . -s res://tools/held/fit_grip.gd -- --preview=<scene> [--fit] [--save]`, which
  needs a window) before calling a fit good. An item's convention: root at the grip point, +Y out
  past the thumb, +Z toward the wrist.
- PACKED SHORT (#161): `ItemGrip.stow_length` squeezes an item along its own +Y about its Hold
  while it is away (`ItemGrip.packing`, eased by `HeldItem.packed()`). Compare a slung item's
  hold through `.orthonormalized()` (`_near` does): its basis carries the squeeze.
- THE SHUT HAND (#160): while an item is in the hand, `HoldWrist` first closes the fingers toward
  `ItemGrip.fist_animation`'s first frame as far as the clip opened them (`GripFit.close_fist`),
  then turns the wrist. The preview does the same before every measurement (`_close_hand`), so a
  fit measures the hand the game draws. Finger poses are put back after the skeleton's update:
  read them in `skeleton_updated`, or `HeldItem.fist_closed()`.
- A grip can be kept for one BODY (`GripEntry.body`, #155): at each lookup step the holder's body
  wins over the shared grip, never across steps. The body comes from the look
  (`ModularCharacter.body`, set by make_looks.py) as the skeleton's `body` meta; the foundation
  reads the meta and never names a look class.

## ANIMATION RULES (DECISIONS #94-#98, #144)
- The `AnimationTree` is built by `AnimationTreeBuilder` from an `AnimationSet`. Never hand-author
  a graph, and never name a clip outside a set — gameplay asks for `locomotion.run`.
- `AnimationDriverComponent` is the ONLY writer of tree parameters, and animation never produces
  gameplay (hard rule 11).
- Library tracks are re-addressed to `Skeleton3D:<bone>` by the extractor; the driver roots the
  tree at the skeleton's parent. A library that plays nothing is usually a track-path mismatch.
- Re-addressing also has to carry the source nodes' TRANSFORM: rotation onto the parentless bones,
  scale onto every position track (an FBX is Z-up centimetres). `_run_pose_tests` measures the
  posed skeleton in metres and is what catches it (DECISIONS #99).
- To look at a character: `game/characters/character_preview.tscn` (F6), or
  `--shot=<path>` for a PNG of the viewport. `player.tscn` only ever shows the greybox capsule.
- `AnimationTreeBuilder.apply_clip` is the ONLY way a node is pointed at a clip, including a swap
  at runtime. A clip's speed and its loop are one decision: `use_custom_timeline` is how a clip is
  sped up, and it overrides the clip's own loop with the node's `loop_mode` (DECISIONS #103).
- Clip timings that fight the game's own numbers are fixed in the SET (`speed_scale`, fitted from
  `shared/movement_config.json`), not by editing the graph. The generator MEASURES a clip's
  authored speed off its planted foot; it does not take anyone's word for it.
- A strafing set blends on a Vector2 in the CHARACTER's frame, a forward-only set on a float.
  `AnimationTreeBuilder.is_strafing(set)` is the one place that decides which.
- A state travelled this frame does not appear in `get_current_node()` until the tree's next
  process tick, and re-issuing a travel restarts its cross-fade. The driver's `_asked` memory
  handles both; do not replace it with a raw `get_current_node()` read.
- A genre shows a STATE through the driver's HELD POSE (#144). `hold_pose(semantic, weight, at)`
  is called every frame from state it reads: `at` < 0 loops the clip; 0..1 freezes it at that
  fraction, which is how a rod's heave is scrubbed. `release_pose()` lets go, and
  `play_action(semantic)` fires a genre's own one-shot. The pose lets go while the body moves.
- A one-shot that fully covers the body stops Godot processing the state machine under it, so a
  travel asked for meanwhile lands when the one-shot ends. A test that revives after a
  full-body action waits for the action to finish.
- THE UPPER BODY (#158): `play_upper(semantic)` fires a one-shot filtered to
  `AnimationTreeBuilder.upper_body(set)` (the set's `upper_body_filter`, else the chest, arms and
  fingers): drawing or stowing while the legs walk. Moving does not cancel it. It sits over the
  pose and under hit and action. Prove a filter by lockstep (two characters, one firing): a
  walking character's legs move in the sword clip too. Once an action or a hit covers the whole
  body, the upper-body one-shot is ended (`_end_covered_upper`): Godot stops processing what is
  under a full-weight one-shot, and the rest of a draw played after the cast (#160).
- A hand on a moving part is IK, not a clip. A looped clip cannot know where a reel's handle is
  (`FishingRod.set_hand_on_reel`: `TwoBoneIK3D` on a wrist target clamped inside the arm's
  reach). IK only moves bones while the skeleton updates: a probe that pauses the
  `AnimationPlayer` sees nothing, so it sets `speed_scale = 0` instead. Point the ELBOW (the
  pole) from the BODY, never from the held item: a pole in the rod's frame turned with each refit
  of the grips and drove the forearm through her waist (#162). The aim suite measures the arm
  against the torso as drawn.
- TEST WHAT CHANGED: run the suites a change touches (and its negative), not every layer each
  round; offer a full sweep before a commit.
- ARMS IN THE BODY (#163): judge clipping on the SKIN (`SkinClearance`), never on bone capsules
  alone (a corseted waist read 2.3 cm clear with a forearm through it). A new animation, item or
  look runs the `arms` suite; an animation whose own off hand is not on the item goes in the
  item's grip file, Off hand (`ItemGrip.off_hand_animations`, #172). Depth limits are calibrated on
  what Luke called right: do not tighten them to catch a pose, add a precise check for it instead.
- THE OFF HAND (#172) is grip data run by `OffHand` (a tool script): `HeldItem` and the preview
  call the same code. Its point is a node in the item's scene BY NAME (it may move: the rod's
  `OffHand` is moved onto the turning handle at runtime), present in the scene so the editor has it.

## MATCHES AND THE LOBBY SCREEN (DECISIONS #182, #183)
- SHOW `get_match_round()` (server: `module::match_round`), never `session.round`: that one keeps
  counting across matches because catches and standings are filed under it. Never restart it.
- A world with no player online for `end_after_empty_s` (rules.json `sessions[].match`) ends its
  match (`begin_match`). Within that grace the phase machine runs as before: the integration suite
  relies on it, since nobody is online between its command-line calls.
- A match's first lobby is HELD (phase_ends_at a year off) until everyone is ready. A client
  shows "waiting" for a held phase (`SessionComponent.is_waiting()`), never the seconds.
- A page over the game holds the player still (`LocalInputComponent.hold_still`) and the cursor
  free (`MouseCapture.hold_free`). Never `MouseCapture.release()` for a page: that is the player's
  Escape, and the Escape menu opens for it.
- The lobby screen shows only with a window (or `--lobby-screen`); `--autoconnect`/`--host=` join a
  match under way without asking, and skip the splash (`--no-splash` too).

## GENRES, LOBBY, LEVELS (DECISIONS #173-#175)
- A GENRE NEVER EDITS THE FOUNDATION, and now it is also a SWITCH: everything of fishing's on the
  server sits behind `#[cfg(genre_fishing)]` (its module in `game/`, its rules in `genre/`, its
  native test files with `#![cfg(genre_fishing)]`). A foundation test that needs a genre's rules is
  gated the same way. `tests/genres_test.sh` is what proves the foundation builds without it.
- A genre's client half is its `genre.tres`: its definitions, tables (and per-world tables) and
  scenes. A game scene sets Boot's `load_genres`; its NetConfig holds only the foundation's tables
  (defaults). The interest suite merges the genres' tables before checking a scene.
- A new genre kind number goes in its `Claims`, never just in code: `init` checks them.
- THE LOBBY counts ONLINE PLAYERS only. An NPC member (the rival) is never waited for.
- A member's lobby row is made where it is needed if missing (`ensure_lobby_member`, #184): worlds
  republished without a wipe hold members from before lobby rows existed. A new per-member table
  must do the same for what a long-lived world already holds; a fresh-publish suite never sees it.
- A WORLD'S LEVEL IS `world_level` (foundation). A genre reads it (`world_level_of`), and sets up
  per level in `on_level_changed`, never by writing its own record of the level as the truth.
- A LEVEL'S BAKE IS GENERATED FROM ITS SCENE: never hand-edit `shared/world/<level>.json`. The
  `levels` suite re-bakes the meadow and fails when the committed bake is stale. Level ids are
  unique (build.rs refuses a repeat); 0 is the level-less greybox.

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

## INPUT AND AIMING RULES (DECISIONS #89-#93)
- `MouseCapture` (autoload) is the ONLY thing that writes `Input.mouse_mode`. Gameplay states an
  intent (`want_capture`); Escape, clicks and focus decide the rest. Never set the mode directly.
- The interaction ray starts at the camera and is extended by the camera's setback from the
  player; range is measured PLAYER to target so the prompt matches the module's `INTERACT_RANGE`.
- A genre claims the interact key with `InteractionComponent.interact_handler` (return true when
  handled) from its own `_on_bound`. Never edit the foundation's `interact` for a genre verb.
- A reducer the player triggered must surface its Err. A press that silently does nothing is the
  bug this whole section came from.
- `Interaction.interact_requested` fires on every press before the verb runs; presentation hangs
  off that, never off the reducer's answer (ANIMATION_SPEC section 2).

## GAITS AND FACING (DECISIONS #100-#102)
- A plain key press RUNS. `walk_speed` is the SLOW gait (the `slow` modifier), `run_speed` is the
  default, `sprint_speed` the fast one; sideways and backwards are multiplied down.
- Those speeds are tied to what the animation clips are authored to travel at. Change one and
  regenerate the sets (`tools/animation_set_builder.gd`), or the feet will skate.
- Facing follows the camera only while there is movement input OR the frame is aiming
  (`InputFrame.face`, held by `LocalInputComponent.hold_facing(reason, on)`), and `module.rs`
  applies the same rule to the same frame. Change one side and you have changed the other.
- The camera's yaw and the body's heading are different numbers: free look freezes the second.
  `move_dir` is relative to the heading, never to the camera.

## SIDECAR / SERVER_AUTHORITY (DECISIONS #106-#108)
- The authority runs the SAME `MovementModel` and the SAME `move_and_slide` resolver as client
  prediction, through `SpaceTimeMovementComponent._step`. Never write a second implementation:
  the symptom of drift is constant correction, not an error.
- `NetConfig.authority_process` is what makes a process an authority. It changes exactly two
  things: every entity binds SERVER_AUTHORITY, and the movement component also asks for
  `input_queue`.
- A row's `grounded` flag is a claim, not physics. Nothing sleeps until a simulated frame agrees.
- A write the module refused is owed again. `take_authority_write()` clears the flag
  optimistically, so whoever sends it must re-mark on failure (#108).
- A sidecar is nobody until `register_authority` names its identity: writes are refused AND
  `input_queue` is invisible to it (its RLS filter joins on `authority`). It prints its identity
  on connect for exactly this reason. ROLE_SIDECAR may not take `world_id = 0`.
- `tests/sidecar_test.sh` is the layer that proves any of it. Run it after touching
  `sidecar/`, `SERVER_AUTHORITY`, `write_movement_batch` or the authority reducers.

## CONNECTING (DECISIONS #122-#126, #148)
- The connect screen greets whenever there is a display; headless processes connect on their own.
  Auto-connect and `--host=` press the screen's own Connect, so timeouts and explanations apply.
- `ConnectSettings` is one profile per IDENTITY, and only the screen writes it. Flags override a
  run; they are never remembered. Under a test suite (UMF_DB) the profile carries the database's name
  (`connect_dev1.umf-test.cfg`, #179): the e2e client runs as Luke's editor slot 1, and read his look.
- A terminal DISCONNECTED despawns the world (`EntitySpawner.despawn_all`). A transient drop does not.
- `SpaceTimeSync.last_disconnect_requested` says whether the player left or was dropped.
- `_sdk_reset_token_fetch` works around two SDK faults in the identity request (#125). A harness
  that tests connecting must delete the identity TOKEN too, or the faulty path never runs.
- MouseCapture takes the cursor back only on a click NO UI consumed (`_unhandled_input`). A genre
  that acts on the left button ignores clicks while `is_captured()` is false.
- FULLSCREEN is `WindowMode` (#148): F11 / Alt+Enter, read by the PauseMenu whether it is open or
  not, and the menu's button. In the editor's game view the window is not the game's: the button
  is greyed and the view's ⋮ → Stretch to Fit is the answer. `tests/render_test.sh` proves the
  real toggle; a headless run cannot.

## STANDINGS AND ROUNDS (DECISIONS #127-#129)
- Standings are assembled from components (`FishingStandings.build`), never a table of their own.
  Members who are neither online nor scored are left off (CLI connections are members too).
- A row that was already true when an entity bound is history: announce only rows after bind.
- `SignalBus.session_phase_changed` comes from the LOCAL player's SessionComponent only.

## FISHING PRESENTATION (DECISIONS #130-#133, #144, #147)
- Other clients learn a line is out from the PUBLIC `fishing_line` row; the challenge stays
  private. A genre that keeps rows beside a challenge clears them in `on_challenge_closed`, which
  fires on every ending (submit, prune, despawn).
- `FishingFx` is driven through its API by `FishingFeedback`; `feel_preview.tscn` drives the same
  API from keys. Tune looks there (`--shot=` renders a moment to PNG), never by guessing.
- The float leaves the rod at `FishingFx.RELEASE_SEC` into the cast clip, measured from the key
  press. Change the clip, re-measure (`--scenario=swing`), and the playtest will tell you if not.
- The pond's interaction shape is wider than its rim wall: the ray stops at the first collider
  (the greybox's ponds; the lakeside's water is terrain and a bake, not entities). Ponds are
  SOLID, so placing one is level design: the movement and remote playtests walk fixed greybox
  routes, and a pond across one fails them (#132).
- Sounds are generated by `tools/synth_fishing_sfx.gd`; replace any by dropping a file over it.
- The fight is shown by `FishingFeedback._show_fight`: the float dragged from where it was hooked
  toward the angler, and a TELL RING (FfC: "the catch is the cue, not the meter") — calm, in the
  band, the sweet spot (pulses, grows), too far (shakes), running. Colour-blind safe; the reel
  gauge on the HUD only confirms it. The float CHASES the fight's position (FfC: a pump is a heave, not
  a teleport), and the HUD's metres are the world's (`FightSim.line_out_m`), never `distance`.
- THE REEL GAUGE (`ReelGauge`, #144) reads a `FightSim` and draws; it decides nothing. The rod
  arc is the load in the tell colour, the rim is the line's tension with the drag marked, and
  the hub glows by `FightSim.reel_pays()`. It never draws WHERE the sweet spot is (Luke, and
  FfC's playtest): the colour says when you are in it. Mark the spot and the game plays itself.
- THE ANGLER is shown from the rig's state by `FishingFeedback._show_angler`. The heave is
  `fishing.heave` held at `pump_of(f)`: the load against the CATCH's band, eased out, reaching
  `HEAVE_TOP` of the clip at "too far". It comes back down at `HEAVE_DROP_PACE` times the clip's
  own pace (#156): a fixed time played it backwards at five times its speed. Never scale it to
  the rod's absolute limit: light catches load a fifth of it, and the heave vanishes. The sweet
  spot lands at 0.53-0.91 of a pump, so the pose gives no fixed release point. The left hand
  is on the reel for the whole fight and while waiting (#161, #162: left to the clips it floated
  off the reel, and hung in the air in front of her waiting), but not under an action, the
  blank bends with the tension, and the line strains. A line out with nothing on it holds
  `fishing.wait` on every client, from the public row. The fight itself is private; what other
  players see is the `fight_show` row the owner reports (#170), and its load is PLAYED BETWEEN
  REPORTS (#181), never set straight from a row: the heave is a frozen pose, and a value set
  per row held still and jumped (the rival fought in a slideshow).
- THE ROD IN THE HAND is a held item (#147, #153, #156): `FishingRod extends HeldItem`, its grips
  in `rod_grip.tres` per animation and body. The idle's carries it (reel off the leg); a running
  animation needs a STEADY grip or the rod's tip sweeps the head; the cast (`interact`),
  `fishing.wait`, `fishing.heave` and `fishing.fail` hold it the fishing way (the fishing clips were
  measured against that grip: the winding hand reaches the handle only there).
  `FishingFeedback` only hands the rod the driver. Edit grips in `rod_grip_preview.tscn`, never as
  numbers in code (#152). The animation-scene suite measures the reel's air off the body
  (`BodyClearance`), the running rod's swing and distance from the head, and that the rod is drawn
  exactly where the file puts it. A grip that clips fails that suite: retune it.
- Slack line LIES ON THE WATER: it hangs from the tip to a touchdown it meets level, then floats
  to the float (`FishingFx._draw_line`); taut while flying, bitten or fighting, eased between.
  `lakeside_shots.tscn -- --angler=<x,z>:<tx,tz>` renders one in the level's light.

## THE NATURE KIT (DECISIONS #137, #141, #146)
- Every leaf, petal and grass blade is `nature_foliage.gdshader`, swapped in at import by
  `quaternius_import.gd` (`FoliageMaterial`): it lights a back face by the kit's own normal. A
  plain double-sided StandardMaterial3D flips it, and up-facing grass turns black from behind.
- Editing the import script reimports NOTHING. `--only=kits` (test_runner) fails until the kit is
  reimported; `tests/render_test.sh` is what shows the shader actually lights both sides.
- The grass is coloured from a PALETTE of thin stripes (`Grass.png`); mipmaps average a stripe
  into its neighbours and the grass whitens with distance. The opaque variant reads it without
  mipmaps (`FOLIAGE_PALETTE`, #146). Never put a detailed texture on that variant.
- The LAKE's colour is how far DOWN the bed is, from the depth buffer (`lake_water.gdshader`,
  #150), never the length of the line of sight: from a player's camera that is long everywhere,
  and the lake went one flat blue. Tune the stops and colours on the material, not in code.

## EXPORTS (DECISIONS #134)
- The client preset excludes `sidecar/` and test CODE. `tests/levels/` is the game's level — it
  must stay in both builds (the first presets lost it).
- The server preset is dedicated-server mode; `run/main_scene.dedicated_server` boots the sidecar.
- Judge an exported process's log before asking it to exit: 4.7.1 prints engine "BUG:" reports
  on shutdown.

## NPC BRAIN MEMORY (DECISIONS #135)
- A brain's `save_state()`/`load_state()` hold DECISIONS (home, goal, target), not countdowns.
- `npc_brain` is visible only to the world's authority; the publisher (world 0) cannot read a
  sidecar world's brains, so the sidecar test proves persistence by restarting the sidecar.

## PRESENTATION AND FEEL (DECISIONS #115-#120)
- `interact_requested` fires when a verb STARTS. A genre that claims a press calls
  `InteractionComponent.announce_interact()` itself — only it knows what the press meant — and
  announces OTHER players' verbs when their public state first shows them (#131).
- A client may refuse its own action to avoid ANIMATING something it knows will fail. The server
  still decides. An unknown state (a row that has not arrived) is not a refusal.
- An action one-shot fades out once the body is moving (`action_cancel_speed`). An action that
  should survive movement wants the upper-body filter, not a wider cancel.
- A component stores row state in a VAR. `bind()` replays existing rows before `_on_bound()`, so
  a node built there must render what is already known rather than being the place it is kept.
  It replays EVERY row of each table (#180), so a collection arrives whole and before
  `is_bound()`: announce only what arrives after bind, and key collection rows by their id.
- Retuning `timing_half_width` regenerates `shared/golden/challenge/challenge_timing.json` with
  the NumPy generator; presses are multiples of the half-width so cases keep their intent.

## THE FISHING GENRE (DECISIONS #112-#114)
- Phases are LOBBY → PLAYING → RESULTS → SHOP → LOBBY. `PHASE_SHOP` is a foundation phase; what
  is sold in it is genre code. A genre adds phases from `PHASE_FOUNDATION_MAX`.
- Gear tracks change three DIFFERENT things: the ROD reach (and line per pump), the REEL the
  hook-set window (and the crank), the LINE the load before a deadlift (and where it snaps). Keep
  them different, or they are one number with three names.
- Score resets each round, coins persist. A catch adds to both.
- Prices, names and effects are `shared/fishing/fishing.json`, read by the client to SHOW them
  (`FishingData`) and compiled into the module, which charges and is the only one that may; every
  refusal reaches the player through `purchase_refused`.
- ADDING A TABLE MEANS RUNNING CODEGEN. Without it the SDK logs `unknown table '<name>'`, the row
  never reaches the client, and every reducer still reports success — see the verify loop.

## THE CAST AND THE FIGHT (DECISIONS #136, #140, #142, #145, #161)
- THE BELL CLOSES THE WATER (#161): `on_phase_changed` (a genre hook, after the session row is
  written) brings in every line of the round nothing has bitten when PLAYING ends; a bitten one
  plays out. A cast the server refuses after the float flew reels the float back in.
- The server ROLLS at the cast (catch, weight, bite) into a private `fishing_cast` row and the
  owner's challenge payload; the client submits `[reaction, n, (ticks, flags, crank) × n]` and
  NEVER a result. `resolve_challenge` grades the reaction and REPLAYS the fight.
- `FightSim` (GDScript) and `genre::fight` (Rust) are twins, bit for bit. f64 on both sides, the
  same operations in the same order, Godot's MIN/MAX/CLAMP/lerp/move_toward written out (not the
  built-ins), the xorshift32 in both files, one fixed tick. Change one and you change the other,
  then `REGEN_FIGHT_GOLDEN=1 cargo test --test fight` and ship the new golden with both.
- A fight is replayed with what the CAST recorded — seed, range in whole centimetres, the gear
  tiers, the round — never with anything read at resolve time.
- The fight ticks on the PHYSICS clock (`_physics_process`), and input is sampled there; timers
  fire after `_process`, so a harness pressing off a timer lands a frame late (see the playtest).
- Tuning is `tools/fishing/gen_fight.py` (it writes `shared/fishing/fight.json`; the curves take a
  logarithm, so they run there and never at runtime). `cargo test --test fight measure --
  --ignored --nocapture` is FfC's tune probe: every bot against the ramp's catches.
- You get to finish what you hooked: a fight resolves through RESULTS, not past. The catch is the
  round it was hooked in.
- THE CAST IS THE FIGHT LENGTH (#142): `fight_length` = clamp(0.9 × range, 10, 40 m), times the
  catch's `distance_scale`. The tests' reference fight (FfC's 40 m) is `REF_CAST`, a 45 m cast.
- REEL ANY TIME; IT PAYS WHEN THE FISH IS SPENT (#145). `FightSim.worn()` and `bare_reel_win()`
  decide how much line a bare wind wins and how hard it strains the line. A run wins nothing
  and strains 2.25×. The bots READ THE FISH: Ace and Good wind while it rests, and `Reeler` only
  winds. `rate_never_beats_depth` holds the reeler at over 1.5× an ace's time; if winding alone
  gets close, the pump has stopped mattering.
- THE YELLOW LASTS: `band_approach_s` caps the load rate between the band's edge and the sweet
  spot, so no catch flashes through the yellow. `the_yellow_is_long_enough_to_see` holds the
  floor and the ceiling. `cargo test --test fight approach -- --ignored --nocapture` and
  `reel_probe` are the probes that chose the numbers.

## SPOTS AND THE ROD GATE (DECISIONS #143)
- A spot's `min_rod` (`shared/fishing/fishing.json`) is the rod that reaches it AT ALL, and only
  where the LEVEL puts it makes that true (`tools/world/lakeside_shape.gd` SPOTS). `cargo test
  --test level` measures every spot of every bake against the rods' reaches and prints how far
  each is from where a player can stand — run it after moving a spot, the shore, the dock, or a
  rod's `max_cast_m`. The band between two rods is ~3 m; expect to place to the metre.
- The gate is said, not just enforced: the aim names a gated spot further along the throw
  (`FishingComponent.spot_beyond`), and the shop names the water a rod reaches.

## NPC BRAINS (DECISIONS #109-#111)
- A brain returns an `InputFrame`, never a position, and it goes through
  `push_authority_input` — the same queue a player's frames use. Never move an NPC directly.
- `move_dir` from a brain is a WORLD direction. Test a steering change at a non-zero yaw or the
  body-frame version of the bug is invisible.
- `think()` runs at `think_hz`, `frame()` every tick. Expensive questions go in `think`.
- `EntityDefinition.brain` is a STRING resolved only in the sidecar (`NpcBrainComponent.make_brain`),
  because `game/` may not reference `res://sidecar`. The sidecar attaches the component with
  `SpaceTimeEntity.add_runtime_component`.

## SUBSCRIPTIONS (DECISIONS #104, #105)
- `InterestManager` is the ONLY place subscription SQL is built. A component that needs a table
  adds it to `NetConfig.core_tables`; nothing else writes a query. A game's `.tres` NetConfig
  lists its own copy: a new FOUNDATION table goes in it too (`fishing_net_config.tres`), and the
  interest suite checks every game scene's list against its entities' components (#160).
- A table is filtered `WHERE world_id = N` only if it HAS that column and its rows belong to one
  world. `WORLD_TABLES` is that list; the test asserts every shipped table has been decided.
- Switching world subscribes the new set BEFORE dropping the old one. Never the other way: the
  spawner cannot tell a torn-down cache from a reconnect.
- Never connect a lambda that closes over an SDK handle to that handle's own signal (#105).

## MOVEMENT RULES (DECISIONS #80-#86)
- With a collision resolver the world is the ground; `ground_y` is only the resolver-less plane.
  Call `push_input` inside the physics tick: `move_and_slide` takes the render delta anywhere else.
- Movement tunables live in `shared/movement_config.json` ONLY (client via `MovementConfig.shared()`,
  server via build.rs). Changing the model: new golden file, NumPy mirror with GDScript's f64
  scalar products, old files byte-identical.
- `.tscn` basis is serialised ROW by row. Probe new level geometry through the engine.
- Patch files as bytes with LF; Windows `write_text()` writes CRLF (#87).
- The input `seq` is per ENTITY, not per process (#149). A restarted client carries on from the
  `last_processed_seq` its row holds, because `submit_input` drops anything at or below it.
  Nothing may ever LOWER that count, or a live client's frames drop the same way.
- A claim outside the trust envelope is clamped AS A WHOLE: height scales with distance (#149).
  Clamped apart, a far claim's drop was taken almost in full, and a player stood inside the ground.


