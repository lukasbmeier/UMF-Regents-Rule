# Changelog

## 0.3.1 — Phase 3 Task 0: the foundation runs
- Repo flattened: the Godot project IS the repo root. The old `client/` level is gone; `shared/` is now `res://shared/`. All docs repathed.
- Rust split on the WASM ABI boundary (DECISIONS #27): `sim.rs` uses `spacetimedb-lib` + `#[sats(crate = spacetimedb_lib)]`; tables/reducers moved to `module.rs` behind `#[cfg(target_arch = "wasm32")]`. `cargo test --test golden` now links and passes natively, 6/6 at `max_err=0e0`.
- Verified live on SpacetimeDB 2.10.1 / Godot 4.7.1: publish creates all 7 tables, `init` runs, the 20 Hz `tick_movement` schedule advances, codegen emits 26 files under alias `Umf`, and `boot.tscn` connects and is assigned a local entity.
- `local_entity_assigned` had two emitters and fired twice per connect (and again per reconnect); `EntityRegistry` is now the single emitter (DECISIONS #28).
- `run_tests.sh` lint is comment-aware — it matched the SDK name inside a doc comment in `net_config.gd`.
- `test_runner.gd`: GDScript has no `%e` format conversion, so the golden harness crashed instead of printing; suites now run deferred so autoloads exist when scripts are loaded.
- Two untyped `for` iterator variables in `entity_registry.gd` / `spacetime_sync.gd` were fatal under the project's own warnings-as-errors setting.
- `tools/codegen_config.gd` makes headless codegen work on a fresh checkout (DECISIONS #29). `.cargo/config.toml` defaults to crates.io. Added `.gitignore` / `.gitattributes`.
- Phase 3 Task 2 done: `SpaceTimeComponent` abstract base (ARCHITECTURE §7) + 13 unit checks.
- Phase 3 Task 1 part done: per-world schema (`world_id` everywhere, `world_config` re-keyed, independent per-world ticking) and the full authority trust model (`authority` table, admin seeding, `require_authority`, heartbeat + 1 Hz watchdog, authority-only `write_movement_batch`/`apply_damage`/`spawn_npc`/`despawn_entity`). `look_pitch` added to `InputFrame` on both sides. See AGENTS.md for what remains.
- Heartbeat/watchdog role mismatch fixed (DECISIONS #31).
- Phase 3 Task 1 continued (fishing-first ordering, per TEMPLATE_WORKFLOW step 2): `session` + `session_member` + the 1 Hz phase machine (LOBBY/PLAYING/RESULTS, score reset and fresh seed each round), `join_session`/`leave_session` moving an entity between worlds, `item_def` + `inventory_item` with stack-filling `grant_item`/`consume_item`/`set_item_slot`, and the `challenge` table + `issue_challenge`/`submit_challenge_result`/`prune_challenges`.
- **First challenge validator with proven Rust/GDScript parity**: `server/src/challenge.rs` + `foundation/sim/challenge_model.gd` + `shared/golden/challenge/challenge_timing.json`, 8 cases at `max_err=0e0` on both sides plus 6 rejection cases. Generated independently with NumPy float32 so neither implementation validates itself.
- RLS confirmed working on 2.10.1 (DECISIONS #32): `challenge` and `input_queue` are public behind `#[client_visibility_filter]`, verified with an anonymous-identity control. Supersedes the earlier deferral in #30.
- Golden vectors reorganised into `shared/golden/movement/` and `shared/golden/challenge/` (DECISIONS #35).
- Phase 3 Tasks 3, 4 and 5 done: `EntityDefinition` + `SpaceTimeEntity` + `player.tscn`; the `EntitySpawner` autoload with reconnect-rebind; `SpaceTimeHealthComponent` + `HealthConfig`. 125 headless checks, all green.
- Proven live end to end: the client connects, the spawner instantiates every `entity` row (flagging its own as local), and a server-side `apply_damage` propagates to `SignalBus.entity_died` on the client.
- Test harness converted from a `--script` runner to a scene (DECISIONS #37); initial rows now delivered exactly once (DECISIONS #38); unused rig nodes detached immediately (DECISIONS #39).
- Phase 3 Task 6 done: `SpaceTimeMovementComponent` with snapshot interpolation, clamped extrapolation, authoritative transition detection and teleport snapping.
- **Fixed a broken wire binding**: the module's vector struct is now named `Vector3` so codegen maps it to Godot's native type (DECISIONS #40). Before this, `MovementState.from_row()` and `submit_input` both failed at runtime — no client could read or send a position.
- `submit_challenge_result` rounds instead of truncating, so a perfect play scores 100 (DECISIONS #41).
- Testing hardened: the Godot harness now fails on unexpected engine/script errors (#42), a binding-contract check guards the generated `Vector3` mapping, and `tests/integration_test.sh` gives `module.rs` its first automated coverage — 68 assertions (#43).
- Phase 3 Task 7 done: `LocalInputComponent` (sampling only) plus the project's input map.
- Scene-level testing added: `tests/levels/greybox.tscn` and a suite that spawns the real player scene through the real spawner and steps real physics frames. It caught `player.tscn` missing its Movement component on the first run. `greybox_demo.tscn` is the runnable version.
- Test fixtures centralised: `_player_rows()` is the single source of truth for a valid player row set, so adding a component to the scene breaks one place instead of every spawn test.
- Test framework evaluated and deferred with a defined trigger (DECISIONS #45).
- Phase 3 Task 8 done: `SessionComponent` + session bus events, reading the non-entity `session` row off the global stream.
- **Added an end-to-end layer** (`tests/e2e_test.sh`): a real Godot client against a real published module. It found three production bugs on its first run, all of which passed every other suite — `session_member` missing from `NetConfig.core_tables` so entities never bound (#49), `submit_input` rejected by the generated typed-array wrapper so no input could ever be sent (#50), and a `SessionComponent` double-subscribe on reconnect (#48).
- Fixed an E2E flake honestly rather than by retrying: `teleport` clears `grounded`, so gravity moved the entity before the exact-position assertion could read it. The test now asserts the horizontal round-trip and that gravity acts.
- Phase 3 Tasks 9 and 10 done: inventory and interaction components, plus the server's `interact` reducer with the authoritative range check.
- `RowEvent` now falls back to `owner_entity_id`, without which no inventory row ever reached its owner (DECISIONS #52).
- **Fishing genre started** under `server/src/game/`, behind `game::on_init` / `game::on_challenge_succeeded` hooks. `fish_def` + `catch` tables, a `cast` reducer gated to the PLAYING phase and range-checked, and a deterministic species/size roll driven by the challenge seed and how well it was played. 25 integration assertions cover the loop and its refusals.
- `session.round` added; `set_session_phase` dev reducer so round-based genres are testable without waiting out real phase durations.
- **Playable local multiplayer.** `game/fishing/play_local.sh` launches N clients with separate identities against a freshly stocked pond.
- Horizontal movement added to `movement_model.gd` with 7 new golden cases at `max_err=0e0`; the original gravity vectors are byte-identical, proving the change was additive (DECISIONS #57). Golden files now declare `frozen_twin` so the Rust harness only runs what the frozen twin can reproduce (#58).
- `LOCAL_PREDICTED` implemented as Tier A client-authoritative movement (#59); input now drives the local player and batches to `submit_input`.
- Template seams for presentation: `EntityDefinition.visual_scene` swaps the model, `.camera_rig` swaps first/third person, both as `.tres` edits (#60). `foundation/camera/` ships a `CameraRig` with both presets.
- Fishing client layer: `FishingComponent`, a timing-bar HUD drawn from `ChallengeModel`, a `fisher.tscn` that instances `player.tscn` and adds one genre component, and a fishing-spot entity.

## 0.3.0 — consolidated handoff (this set supersedes all earlier bundles)
- Motion authority is per-world: MODULE (Tier A: frozen gravity-only twin + client trust) or SIDECAR (headless Godot). Tier B proxy collision, `collision.rs`, `static_collider`, `seed_colliders`, `set_movement_tier` removed. `world_config.sim_authority` + `set_sim_authority` added; `tick_movement` skips SIDECAR worlds and prunes stale inputs; `input_queue.received_at` added.
- `server/src/sim.rs` frozen; Rust⇄GDScript parity discipline re-scoped to Challenge validators. Movement goldens are GDScript regression vectors (Rust test guards the frozen twin).
- Docs added: `SIDECAR_SPEC.md`, `ANIMATION_SPEC.md`, `TEMPLATE_WORKFLOW.md`, `CHANGELOG.md`. Phase 3 spec: Tasks 13–16 reworked (sidecar skeleton, sidecar NPC brain, animation driver, sweep).
- `run_tests.sh`: lint forbids `res://sidecar` outside `sidecar/`.
- Playbook chunks 8–9 replaced (AnimationSet builder, timing-bar Challenge validator).

## 0.2.0
- SDK bindings verified against plaught-armor `docs/api.md` + `docs/codegen.md`; Rust module verified against `docs.rs/spacetimedb/2.10.0`. Generated client is `SpacetimeDB.Umf`; bindings in `res://spacetime_bindings/`.

## 0.1.0
- Phase 1 blueprint; Phase 2 scaffold (SignalBus, ClockSync, SpaceTimeSync, EntityRegistry, NetConfig/RowEvent/ReducerRequest/SubscriptionSet, movement model, golden harness, Rust module).
- **Playable from the editor.** `run/main_scene` now points at `game/fishing/fishing_game.tscn` (DECISIONS #64), the fishing spots are seeded by `game::on_init` instead of by `play_local.sh` (#63), and `foundation/boot.gd` gives every editor instance its own identity so Debug ▸ Customize Run Instances ▸ 2 produces two real players (#61). No shell script needed to play.
- The identity slot is claimed by binding a loopback port rather than writing a pid lock file (#62). The lock-file version failed `multiclient_test.sh` on its first run: on Windows `OS.is_process_running` only knows processes Godot launched, so every instance read the others' locks as dead and all claimed slot 1.
- New suite `tests/multiclient_test.sh` — two real clients against one live module, asserting they get different identities, see each other's entity as remote, and both receive the seeded pond. 15 assertions. This is a multi-process property; no single-client suite can observe it.
- `e2e_runner.gd` picks its teleport target relative to where the entity already is, so the suite is re-runnable against a database that was not freshly published. A fixed destination was a silent no-op on the second run.
- `boot.gd` duplicates an `EntityDefinition` before overriding its camera rig; `--first-person` was mutating the shared `.tres` in place.
- `integration_test.sh` asserts the pond exists immediately after init, and takes the LAST resource node when it wants the one it just spawned — taking the first would have made the out-of-range assertion pass for the wrong reason.
- **Fixed: the game rendered nothing.** `CameraRig._ready()` runs when the spawner adds an entity to the tree, before `bind()` knows whose entity it is, so every camera evaluated `is_local_authority` as false and none became current. `SpaceTimeEntity` now calls `rig.activate()` once the role is known (DECISIONS #65). The HUD is a CanvasLayer and kept drawing, so the symptom was a grey screen with a working UI and no error in any log.
- The view is now asserted in three layers (#66): the scene suite checks exactly one current camera and that it belongs to the local player, the E2E suite checks the viewport is looking through our entity, and `multiclient_test.sh` checks both real clients report a view in the real genre scene. Negative-tested by disabling the fix — 3 assertions fail with `got 0` current cameras.
- `boot.gd` prints `view: looking through <path>` on local spawn, and `push_error`s when no camera is current.
- `greybox.tscn` gained a real `Environment` (sky + filmic tonemap); its `WorldEnvironment` node had no resource assigned, so the world rendered into the default clear colour (#67).

## 0.4.0 — Phase 4: movement you can actually play
Reported: "movement is very laggy locally, we spawn in the ground, jumping is required before moving." A scripted playtest of the real fishing scene reproduced all of it — walked 0.07 m in 1 s, 109 corrections, dragged off raised geometry — and now passes at 0, 100 and 200 ms simulated round trip.
- **Spawn / stuck:** body origin moved to the feet; entities on their own physics layer (DECISIONS #68). Every entity no longer freezes 2 s at bind waiting for empty collections (#69).
- **Server fighting the client:** Tier A trust rewritten as a per-frame speed envelope; the gravity twin only moves undriven entities (#70). Correction epochs stop in-flight frames dragging the server back (#71); overrides replay pending inputs within a time-bounded budget (#72). Seq gaps accepted, frames per tick capped.
- **Rubber-banding:** Phase 4 §1 reconciliation against prediction history by seq, glide not pop (#73).
- **Smoothness at 144 Hz:** physics interpolation on; camera placed from the interpolated transform every frame (#74).
- **Remote players:** per-entity seq timeline, physics-time render clock with slew, jitter-adaptive delay, Hermite interpolation, projective velocity blending out of dry spells (#75, #76). Zero lurches in 7 consecutive two-client runs at up to 250 ms / 80 ms jitter.
- **Tooling:** `--latency=` / `--jitter=` latency simulator in the adapter (#77); F3 net overlay in the fishing scene (F4 cycles latency live); jumpable step onto the greybox platform.
- `ClockSync` sign error fixed (#78). `EntityRegistry.all_entity_ids()`.
- **Tests:** `playtest_test.sh`, `remote_playtest.sh` (#79); 28 prediction unit tests including the Phase 3 bug pinned as a regression; scene checks for the feet origin and layers; 24 server assertions for the trust envelope, epochs and budget. Unit 331, integration 129, e2e 29, multiclient 19. Every new guard negative-tested.
- **Wire change:** `InputFrame.epoch` and `movement_state.correction_epoch`. Republish and regenerate bindings (README).

## 0.5.0 — Phase 4 complete: jumping fixed, snappier movement, move states, slopes, actions
- **Fixed: jumping broke after a few jumps.** The analytic ground plane zeroed the fall before collision ran, so landings could hover a few mm up for ever (DECISIONS #80). A drop sweep reproduces it deterministically against the old logic; 24 jumps on open floor and against a wall pass through the real keys at 0/100/200 ms + 50 ms jitter.
- **Movement is no longer glidy.** Reversal braking and a retune: sprint reversal 380 → 167 ms, stop 1.07 → 0.47 m, pinned by a feel contract (#81). Not netcode: zero corrections at 200 ms + 50 ms jitter.
- **One config for client and server.** The client now reads `shared/movement_config.json` too; a test fails if the defaults drift (#81).
- **§2:** `move_state` classified by the model and mirrored to every client (#82); slopes (walkable 30 degree ramp onto the platform, unclimbable 55 degree) (#84); config-gated flap and dash, off by default, Q to dash when enabled (#85).
- **§1 remainder:** the local player's jump/land/move-state events fire from the prediction, instantly, with revocation (#83).
- **§3 + Task 12:** abilities and `SpaceTimeActionComponent` — predicted start, confirmation by echoed id, revocation with the cooldown handed back (#86).
- **Wire:** `InputFrame` gains `move_state` and `dash`; `ability_def`/`ability_state`/`action_event` tables. Republish and regenerate bindings.
- **Housekeeping:** all text files LF again (#87); the remote playtest walks a deterministic route (#88).
- **Tests:** unit 485, integration 155, e2e 38, multiclient 19, movement playtest 29 per latency, remote playtest 11. New golden files `turning.json`, `flap_dash.json`; every golden file asserts move_state. Every new guard negative-tested.


## 0.5.1 — the fishing loop is actually playable
- **Fixed: the mouse was never captured.** `MouseCapture` autoload owns the cursor — Escape frees it, a click takes it back, losing focus hands it to the other instance, and a display-less run never touches it (DECISIONS #89). Mouse look only turns while it is captured, so a free cursor no longer steers the camera out of the window.
- **Fixed: the crosshair could never be on anything.** The interaction ray was `interaction_range` long from a camera 4.5 m behind the player, so it ended behind them. It now starts at the camera, is extended by the boom, and measures range from the player exactly as the module does (#90).
- **Fixed: E did not cast.** The interact key sent the foundation's generic `interact`, whose node Challenge the fishing component ignores by design. A genre now claims the key through `InteractionComponent.interact_handler`; the server's refusals reach the HUD instead of vanishing (#91).
- **Finding a pond:** a 2 m interaction volume, a beacon, a name sign, a crosshair that fills in when a cast would be accepted, and a HUD line giving the distance to the nearest one (#93).
- **New test layer that plays the game.** `tests/fishing_playtest.sh`: walk there, aim, press E, play the bar, land a fish — no reducer called directly (#92). At 0 and 150 ms: acquires the pond at 2.86 m, scores 0.66 server-side, catches a fish, and a cast from 5.2 m comes back "cast: too far from the spot (5.19 m)".
- `Interaction.interact_requested` fires on every press, before the verb runs — the one-shot `docs/ANIMATION_SPEC.md` names for the reach animation (Task 15).
- **Tests:** unit 524, fishing playtest 32 per latency, integration 159. All six new guards negative-tested by reverting each fix in turn.
- Three integration assertions were quietly racing the `spacetime` CLI (a 30 s session phase elapsing mid-run, an 800 ms cooldown shorter than two calls, a real-time replay budget). Each now forces the state or computes its bound from a measured clock.

## 0.6.0 — Task 15: characters that animate
- **The greybox capsule is a rigged character.** `AnimationSet` (semantic name -> clip) + a generated `AnimationTree` + `AnimationDriverComponent`, the only writer of its parameters (DECISIONS #94). Locomotion blends on speed; jump start/loop/land, death and revival are a state machine; hit reactions and verbs are layered one-shots.
- **Remote players animate too**, from the `move_state` and jump/land events the server already mirrors — the local player's from its own prediction, so its jump starts on the frame the key goes down.
- **Quaternius Universal Animation Library 1 + 2** (CC0) extracted to 3.7 MB `AnimationLibrary` resources with bone tracks re-addressed so any matching rig can play them; sources stay out of the repo, and `tools/extract_animation_library.gd` regenerates them (#95, `game/anim/ATTRIBUTION.md`).
- **`tools/animation_set_builder.gd`** fuzzy-matches 127 clip names onto the semantic ones and prints what it matched; the fishing genre overrides two lines so `E` plays a rod cast and ability 0 plays a punch.
- **Swapping a character is still a `.tres` edit** (#96): `EntityDefinition` gains `animation_set` and `visual_yaw_deg` (these rigs face +Z; measured off a root-motion clip, not guessed).
- **Clip timings are fitted to the config** (#97): the 1.33 s take-off is scaled to 40% of this game's 0.8 s airtime, or the character lands before it finishes crouching.
- **Three bugs the scene suite caught** (#98), none of them visible in review: a state travelled in the same frame still reads as the old one, so the driver kept overwriting its own take-off; re-issuing a travel every frame restarts its cross-fade, so a revived character never got up; and `travel()` takes the shortest route it can find, so with only two-hop routes available a living character reached the ground THROUGH THE DEATH STATE. The graph now carries a direct transition for every travel the driver can make, asserted as an invariant.
- **Tests:** unit 588, integration 159, e2e 39, multiclient 19, movement playtest 29 per latency, remote playtest 13, fishing playtest 36 per latency. The scene suite spawns the real rig in the real level and asserts the skeleton MOVES, that walking poses it differently from idling, that the jump arc is travelled, and that a remote character animates from rows alone. Measured live: the locomotion blend peaks at 0.62 walking (walk 5 / sprint 8 m/s) for both the local and the remote player. Eight animation guards negative-tested.

## 0.6.1 — the character stands up
- **Fixed: the fisher animated lying on its back.** Re-addressing the FBX library's tracks dropped the node Godot had put the Z-up conversion on; the GLB library carried the same rotation in its pose and was fine, which is why half the clips looked right (DECISIONS #99).
- **Fixed: and then it was 100x too small in the wrong places.** An FBX is authored in centimetres, so every position track needed the unit scale, not just the root's — the first fix left an upright character with its pelvis 9 mm off the ground.
- **The test that should have existed**: `_run_pose_tests` measures the posed skeleton in metres for clips out of both libraries — head above pelvis above feet, head between 1.2 m and 2 m, feet near the ground. Every earlier animation test asked whether the skeleton moved; none asked which way was up.
- **`game/characters/character_preview.tscn`**: press F6 to see a character with no server — cycle its clips, overlay the collision capsule, edit the `.tres` and press R to reload. `--shot=<path>` saves a PNG of the viewport, which is how the poses above were checked by eye rather than only by assertion.
- **Tests:** unit 603, fishing playtest 36.

## 0.7.0 — gaits, strafing, and a camera you can look around with
- **A plain key press RUNS** (5 m/s). `Ctrl` walks (1.2), `Shift` sprints (8), and sideways/backwards are slower gears (0.7x / 0.65x) — DECISIONS #100. The numbers come from measuring what the clips are authored to travel at, not from taste: the old single gait played a 1 m/s walk clip at 5 m/s, which is the skating that read as floaty.
- **Strafing.** The character keeps facing the camera and side-steps, using the directional clips both Quaternius libraries ship, blended on a plane in the character's own frame (#101). `AnimationSet.strafe` turns it off for a genre whose characters should turn to face the way they are going.
- **Every locomotion clip is speed-matched to its gear.** The generator measures each clip's authored speed off its planted foot and scales it to this game's speed for that gear (walk x1.25, run x0.97, strafe x1.36, backwards x0.60 …).
- **A landing no longer outlives the landing.** Still moving when you touch down hands straight back to locomotion; landing on the spot still plays the recovery. Measured: 0 frames of recovery at a run, 22 standing still.
- **The body turns to the camera only while moving**, and the MODEL eases round while the body's yaw snaps — the body's yaw is simulated state the server mirrors, so it cannot ease there.
- **Free look** (hold `Alt`) and **wheel zoom**, both client-only (#102).
- **Wire:** `InputFrame.slow`, and `move_state` gains `RUN = 7`. Republish and regenerate bindings.
- **Two bugs the tests caught, both invisible at yaw 0:**
  - `move_dir` is a WORLD direction (the input component has already turned the stick by the look direction), and the new gears were being read as if it were body-relative — so sprinting north was a *backwards* sprint at 8 x 0.65 = 5.2 m/s. The movement playtest measured exactly that. The gears are now read in the character's own frame and applied back out, and `gaits.json` carries a case that runs while turned.
  - The camera's zoom used a negative sentinel for "not initialised yet"; zooming in past the near limit drove the target below zero, which read as uninitialised and snapped the camera back out to the preset.
- **Tests:** unit 685, movement playtest 29, fishing playtest 36, remote playtest 13, server 159, e2e 39, two-client 19. New `gaits.json` (11 NumPy-generated cases); scene checks that drive the real prediction — walking lands on the walk ring (0.15), sprinting on the outside (1.00), moving right blends right (0.44, 0.00), and running forward while turned 90 degrees still blends FORWARD (0.00, 0.62). Landing recovery measured at 0 frames running, 22 standing.

## 0.7.1 — the animations actually loop
- **Every locomotion clip except idle froze after one cycle** and the character slid along the ground in a fixed pose. Speed-scaling a clip plays it through a custom timeline, and turning that on overrides the clip's own loop with the node's `loop_mode`, which defaults to "do not loop" (DECISIONS #103). `AnimationTreeBuilder.apply_clip` is now the one place a node is pointed at a clip, and it sets the loop explicitly: locomotion loops, the one-shots that hand over at their end do not.
- **A clip swapped at runtime takes the new clip's timing.** The two swap sites (a heavy landing, an ability's own animation) assigned `animation` directly and kept the previous clip's timeline length, stretching the new clip to fit a length it never had.
- **The preview scene plays clips at the speed the game plays them.** It pointed the node straight at the clip, so it showed everything at its authored speed — which is why a clip the game froze looked perfectly fine in there.
- **Tests: 700** (up from 685). The gap that let this ship: the scene test asserted the walking pose *differed from the idle pose*, which a clip frozen on frame one satisfies. It now holds each direction past the end of its own clip and measures whether the skeleton is still moving — forwards, both strafes, running backwards and walking backwards (the longest clip in the set, 2.22 s). Frame counts cannot express that window: animation advances on the render clock while a headless run puts several physics steps inside one idle frame, so it is measured in seconds. A structural guard names any clip in a generated tree whose loop contradicts its job, for both the strafing and the forward-only graph.

## 0.8.0 — Task 11: InterestManager
- **Subscription SQL lives in one place** (`foundation/net/interest_manager.gd`, autoload after `SpaceTimeSync`) and is keyed by world: per-world tables are filtered `WHERE world_id = N`, static catalogues and entity-keyed tables are subscribed whole (DECISIONS #104). `SpaceTimeSync` still owns the connection, the handles and `world_ready`; it no longer decides what to ask for.
- **Switching world overlaps.** The new set is subscribed first and the old one dropped only once the new one has applied, so the cache is never empty and the spawner never mistakes a switch for a reconnect. A switch overtaken before the server answers is cancelled rather than applied into a world we already left.
- **`build_queries()` is the override point** the MMO cell layer and the sidecar hang off; `extra_tables` covers the common "an authority needs more tables" case, and `input_queue` is already in the world-filtered list for it.
- **Fixed a leak nothing had ever exercised** (DECISIONS #105): the SDK subscription handle's `applied`/`end` callbacks were lambdas that captured the handle itself, so every subscription leaked its set. Invisible until something switched worlds more than once — which is exactly what Task 11 introduced.
- **Tests: 726** (up from 700), including the accept criteria — two switches leave exactly one active set, `world_ready` fires per switch — driven through the real `SpaceTimeSync.subscribe` path with a fake SDK handle. Six mutations, all caught.

## 0.9.0 — Task 13: the sidecar simulates a world
- **`SERVER_AUTHORITY` movement mode** (DECISIONS #106). A headless process drains each entity's `input_queue` in seq order through the same `MovementModel` and the same `move_and_slide` resolver the client predicts with. Measured: given identical frames from identical state, the authority lands where the client predicted to **0.0000 m**.
- **`sidecar/`**: `sidecar_main` (`--world=N`, stable identity, prints the identity an admin needs to register it), `sim_world` (loads the SAME level the clients do, so both resolve against the same walls), `authority_sync` (one `write_movement_batch` per world per server tick, plus the heartbeat that keeps `authority_online` true).
- **`SpaceTimeSync.write_movement_batch`** — the adapter's second typed reducer path, built like `submit_input` because the generated wrapper's typed-array parameter cannot take an untyped array.
- **An entity is only asleep once a simulated frame says so** (#107). `spawn_npc` writes `grounded: true` at any height; believing it left entities hanging in the air.
- **A refused write is owed again** (#108) — found by the live test. One refused write used to strand an entity's row forever, and a sidecar that starts before it is registered does exactly that.
- **`tests/sidecar_test.sh`** — a real sidecar against the real module, with a control: the entity sits at y=8 while the sidecar is unregistered, and falls once `register_authority` lands. That ordering is what makes it evidence rather than coincidence, and it is the only layer that exercises the BSATN shape of a nested-struct reducer argument.
- **Fixed: `InputFrame.from_row` read the wrong field names.** The wire spells the direction `move_x`/`move_y` (`sim.rs`); `move_dir` is the client class's own convenience. Reading the convenience name off a real row yields (0, 0) — the entity is simulated perfectly and stands still. The test fake now carries the wire shape so the unit layer proves the mapping.
- **Tests: 761** unit + **7** sidecar. Nine mutations against SERVER_AUTHORITY, all caught.

## 0.10.0 — Task 14: the sidecar drives NPCs
- **NPC brains** (`sidecar/npc/`): `wander` ambles around a home point, `chase` runs at the nearest player it can see and wanders when it cannot (DECISIONS #109-#111). A brain answers "which way would this character push the stick" and the ordinary movement path does the rest — same model, same collision resolver, same seq numbering as a player.
- **`EntityDefinition.brain`** names the brain as a string. A designer picks behaviour in a `.tres`; only the authority process resolves the name, so the brains stay server-only and a client sees an ordinary remote entity.
- **`SpaceTimeEntity.add_runtime_component`** — attach and bind a component after the entity bound, which is how the sidecar adds a brain the scene is not allowed to name.
- **A rival angler in fishing** (`game/fishing/rival_definition.tres`, kind 1), driven by the sidecar. The live test spawns one and watches it walk.
- **Tests: 783** unit + **9** sidecar. The live sidecar test now proves two things end to end: registering the authority is what makes a dropped entity fall, and an NPC nobody sends input to walks anyway. Six NPC mutations, all caught — including a brain steering in the character's frame instead of the world's, which is invisible at yaw 0 and is why the test asks at 90 degrees.
- **Not done:** `npc_brain` / `write_npc_brain` persistence. A brain's state and target live only in the sidecar process, so a restart re-thinks from scratch rather than resuming. Nothing depends on it yet; spectators and a warm restart would.

## 0.11.0 — gear, and a shop to spend it in
- **A SHOP phase** between rounds (DECISIONS #112). The foundation defines when; the genre decides what is sold. LOBBY → PLAYING → RESULTS → SHOP → LOBBY.
- **`gear`**: rod, line and lure, four tiers each, at 40 / 110 / 260 / 600 coins. Each changes a different part of the roll — the rod lifts rarity, the line makes the timing bar gentler, the lure grows the fish (#113). `buy_upgrade` is SHOP-only, priced and charged server-side.
- **Score and coins are different numbers** (#114): score is the round's competitive readout and resets with it, coins are progression and persist. One catch feeds both.
- **The HUD shows both, plus your gear**, and offers the shop with live prices between rounds — `1`/`2`/`3` to buy. A refusal comes back as a notice rather than as nothing happening.
- **Tests: 793** unit, **184** integration (up from 159, with the phase gate, the climbing prices, the tier cap and the refusal-leaves-nothing-behind case), and the fishing playtest now **plays the shop**: it presses the key mid-round and asserts the HUD offers nothing, asks anyway and asserts the server's refusal reaches the player, then buys a rod once the shop opens — 48 checks at 0 ms and 150 ms.
- **Regenerate the bindings after this one.** `gear` is a new table; without codegen the SDK logs `unknown table 'gear'` and the row never reaches the client, while every reducer still succeeds.

## 0.12.0 — hosting, names, and the four things play found
- **Play with other people.** `--host=<url>` and `--name=<name>`, both remembered in `user://connect.cfg`; the README has the host-side setup (`spacetime start --listen-addr 0.0.0.0:3000`, the firewall, who the admin is, and why two copies on one machine need `--token=`).
- **`set_player_name`** — the one place untrusted text enters the database, so the module strips control characters and collapses whitespace. **Nameplates** draw it over everyone but you; an entity with no player row (the rival angler) uses its definition's display name.
- **Fixed: the cast animation played when no cast happened** (DECISIONS #115, #116). `interact_requested` announced the press before anything had decided it was a verb. It now fires when a verb starts, and the fishing component refuses locally — for presentation only — when it already knows the phase is wrong.
- **Fixed: the cast animation outlived the cast** (#117). Walk away and it fades out instead of playing over a sliding character.
- **Fixed: the minigame was spam-E, and gear did nothing** (#118, #119) — the same arithmetic both times. Every fishing spot ran at the difficulty clamp's floor, so the hit window was over half the bar and a better line subtracted into the clamp. The window is now `0.16 - 0.12 * difficulty`, each spot rolls its own difficulty, and the rod lifts the rarity roll instead of scaling it. `challenge_timing.json` regenerated; both sides still `max_err = 0`.
- **Fixed: a nameplate dropped every name that arrived before it existed** (#120) — which is every player already in the world when you join.
- **Fixed a flaky pose test.** It sampled a clip "four frames in" and asserted the head was at human height; `Jump_Start` plays at x4.17, so four frames landed mid-crouch and the check sat on its own threshold. It now samples across the clip and asks each property where it means something — upright at its TALLEST, the PLANTED foot near the ground — which also revealed that "feet down at all times" was never true of a run.
- **Tests: 800** unit, **193** integration (up from 184), 24 multiclient (up from 19, with names reaching the other client's nameplate). The integration suite now measures the reported symptom directly: six ponds at six distinct difficulties, and on the hardest one four line tiers take it from 0.70 to 0.40 — a hit window 48% wider.
- **Fixed a hash that was not one** (DECISIONS #121). The first version of per-spot difficulty gave every pond 0.499; it was caught by printing the six values rather than by reading the code.

## 0.13.0 — a game you can hand to friends
- **A connect screen** (`foundation/ui/connect_screen.tscn`): server address and name, prefilled from last time, Enter to connect, "connect automatically next time". A bare `192.168.1.20` gets port 3000; an address that never answers is given up on after ten seconds with an explanation that names the address and the firewall; the wrong kind of server shows the SDK's own words. Settings are one profile per identity, so two editor instances remember two names (DECISIONS #122).
- **An Esc menu** — Resume, Disconnect, Quit — over a world that keeps running. Its buttons can be clicked because MouseCapture now takes the cursor back only on a click no UI consumed (#124). Disconnect tears the world down and lands on the connect screen, filled in; connecting again in the same process comes back as the same entity (#123, #126).
- **Fixed an SDK fault a friend would hit on first launch** (#125): a fresh install that mistyped the address once could not connect anywhere until restarted. Worked around in the adapter; the playtest now starts from a genuinely fresh install, which is the only way the fault shows.
- **Round results and a live leaderboard.** While a round runs, the top five and you; when it ends, everyone's points, fish count and best catch — by its real name, coloured by rarity — and who won. Built from what the entities already hold (#127). Catches are finally named: the HUD's name table was never filled, so every fish had been "Fish #3".
- **Fixed: every player in view announced each phase change** (#129) — the end-of-round bell rang three times with three players.
- **Fishing looks and sounds like fishing.** A rod in the right hand that follows every clip; the float waits through the wind-up and leaves at the cast clip's release, whatever the latency (#131); it lands with a plop and a ripple on a proper pond — water shader, stone rim you cannot walk through, reeds; each press dips it and clicks as a hit or a miss; a catch splashes and the fish leaps out toward you, gold for a legendary. Bells for the round, a coin for a purchase, water lapping at every pond. **Other players see all of it**: your line, your cast, your fish (#130).
- **Sounds are generated** by `tools/synth_fishing_sfx.gd` — twelve of them, deterministic, CC0 — and replaced by dropping a file of the same name over one (#133).
- **`feel_preview.tscn`** — the fishing presentation with no server. F6, then C to cast, N/M to press, 1-4 to land a fish; `--shot=` renders a moment to PNG.
- **Export presets** (#134): "Windows Client" leaves out `sidecar/` and test code; "Windows Server" is a dedicated-server build whose main scene is the sidecar. `tests/export_test.sh` exports both, reads what each pack contains (`tools/pck_list.py`), runs the client against the module and runs the whole sidecar suite against the server build. Its first run caught the presets leaving the game's level out of both builds.
- **NPC brains resume after a restart** (#135): `npc_brain` + `write_npc_brain`, visible only to the world's authority, written on change at most once a second. The sidecar test kills the sidecar with the rival wandered off, and the restarted one resumes the rival's old home.
- **Tests: 861** unit, **217** integration, **60** connect playtest, **83** fishing playtest + **12** from a second client watching it, **26** multiclient (with each client's leaderboard showing the other's score), **13** sidecar, **17** export. Every new guard was broken on purpose and seen to fail — and two checks that could not fail were caught that way and fixed: the observer's swing check read a clip name the tree is built with, and the export test's claim that the movement JSON needed an include filter.
- **Restart the editor after pulling this one** — `project.godot` gained the dedicated-server main scene. **Republish and regenerate the bindings** — `fishing_line` and `npc_brain` are new tables.

## 0.14.0 — the lakeside, and Fishing for Compliments' fishing
- **A real world** (DECISIONS #138). The main scene is now `game/fishing/lakeside_game.tscn`: a Terrain3D valley around a lake, generated from a fixed seed by `tools/world/build_lakeside.tscn` — Quaternius' Stylized Nature kit as ~31k instanced plants and trees you cannot walk through, a village from the Medieval Village kit's sample, a dock with lanterns and props, water with ripples, foam and depth colour, and invisible walls (physics layer 3, ignored by the camera) at wading depth, the dock's edges and the map's rim. The generator BAKES what the server needs — spawn, water, a depth grid, five named spots — into `shared/world/`, read by `server/src/level.rs` and its twin `LevelBake` at `max_err = 0`. A walk test takes a real player from the spawn to the end of the dock and leans on every barrier. The greybox is the test level (`use_level 0 0`, admin).
- **The aimed cast** (#136), from Fishing for Compliments: hold the left button and the ring goes out over the water — green where the server will take it, with the spot named and the range — and let go to cast. The server checks the reach and the water against the bake and rolls what is on the line AT THE CAST, privately. The float twitches for the tell; when it goes under, click. The hook-set is graded on the client by a twin of the module's rule, held to NumPy goldens. Spots deplete server-side and grow back; crowding slows bites.
- **The angler turns to face the cast** (#136). Casting behind you threw the float behind you while the character kept facing the lake. `InputFrame.face` makes facing "while moving OR aiming", the same rule in `_step` and `module.rs`, so every other client sees the turn too — the fishing playtest's second client checks it.
- **The fight** (#140): Fishing for Compliments' "THE PUMP". Hold to load the rod, let go in the sweet band (the ring round the catch tells you: it pulses in the sweet spot, shakes when you have gone too far), reel the slack in with the wheel or by circling the mouse, give line when it runs, heave a snag free. A catch heavier than your line is rated for is a deadlift: land it fast for double coins. The client plays it; **the module replays every tick of your input through its own copy of the fight and lands only what its replay lands** — the two simulations agree to the last bit (`shared/golden/fishing/fight.json`: 13 scripted fights, 7,854 values). FfC trusted the client's result; that stayed behind. A fight still on the line when the round ends plays out through the results.
- **Gear that means something**: the rod reaches further and lifts more line per pump, the reel widens the hook-set window and cranks faster, the line holds heavier catches before a deadlift and snaps later. Prices and numbers are one file, `shared/fishing/fishing.json`, read by both sides.
- **Characters** (#139) from the Universal Base Characters and Modular Character Outfits – Fantasy packs: eight looks (peasant, ranger, noble, wizard; male and female) and a crowned rival, each a head, an outfit and a haircut assembled onto one skeleton that the existing animation clips play on. Each player wears one by entity id, the same on every screen. `character_preview.tscn`: UP/DOWN cycles them, L lines them all up.
- **Lighting** (#137). The "fuzzy, dotted" shadows were the soft-shadow filter's noise with nothing to resolve it: TAA is on, the filter is Soft Medium, the sun's shadow splits are pulled in toward the player and its normal bias doubled. The cherry blossom's blended leaves are imported as cut-outs.
- **Fixed: the sidecar subscribed to a table that no longer existed** and ran blind; `run_tests.sh` now fails any shipped NetConfig that names a table the module does not have. **Fixed a flaky sidecar check** that killed the sidecar at a fixed time and sometimes caught the rival back beside its home.
- **Tests:** **1109** unit and scene checks (up from 861), **295** integration (the module replaying real fights played from a shell — landed, snapped, cut short, forged, too fast — up from 217), **99** fishing playtest + **13** from the second client, at 0 and 150 ms, **40** e2e, **26** multiclient, **29** movement at three latencies, **60** connect, **13** sidecar, **21** export; Rust: **15** fight (including the golden file and FfC's ramp), **10** fishing rules, **3** level bake. Every new guard was broken on purpose and seen to fail: a reordered product in the GDScript fight (one ULP, caught), a server whose pumps are 10% weaker (the playtest's catch never lands), a server that accepts dry land or ignores the reel (9 integration failures), facing switched off (the playtest AND its second client), a character piece left on its own skeleton, and a config naming a table the module lacks.
- **After pulling:** restart the editor (`project.godot` gained TAA and the shadow filter), republish and regenerate the bindings (`fishing_cast`, `catch` and `fishing_spot` changed), and reimport the Nature kit if the editor does not (`game/world/kits/nature/`, for the cherry blossom).

## 0.14.1 — lakeside refinements
- **The dark spots in the foliage** (DECISIONS #141) were not shadows. Quaternius author their foliage normals on purpose — every grass blade's points straight up, the crowns' bend outward — and a double-sided material flips a back face's normal, so a blade seen from behind was lit as if it faced the ground: black strands in every tuft, dark blotches in bushes and trees. Every leaf, petal and blade is now drawn by `nature_foliage.gdshader`, swapped in at import, which lights both sides by the kit's own normal. A new windowed layer, `tests/render_test.sh`, renders a blade from both sides (a plain double-sided material is the control: 0.01 from behind against 0.75 in front; the shader, 0.75 both ways).
- **The cast is the fight's length** (#142), Fishing for Compliments' rule that the first port missed: `clamp(0.9 × range, 10, 40 m)`, times the catch's share of it. The HUD reads out the WORLD's metres — "the aim said 42 m, and when it bit it said 8" was the fight's own units — and the float eases toward the catch after each pump (FfC: a heave, not a teleport). Both twins and the golden file changed; dropping the clamp on one side fails exactly the three clamped cases.
- **The good spots need a better rod** (#143), FfC's gate: each spot declares the rod that reaches it at all, and the level puts it there. The North Drop (was 0 m from the north beach) is 28 m out and wants the Ash Rod; the Deep Hole (was 4.5 m off Rocky Point) is 37 m from Rocky Point's tip and the dock's end and wants the Yew Longrod. `cargo test --test level` measures every spot against the rods' reaches, and fails the old level. The aim tells you when a gated spot lies further out ("The Deep Hole is further out: the Yew Longrod reaches it"), and the shop says what a rod reaches.
- **Slack line lies on the water.** It hangs from the rod tip, meets the surface level and floats out to the float; before, a long cast's line dived under the lake halfway out. `lakeside_shots.tscn -- --angler=<x,z>:<tx,tz>` renders one in the level's light.
- **Tests:** **1128** unit and scene checks (up from 1109: the Nature kit as imported, the line on the water, the rod gate said aloud, the fight's metres), **295** integration, **103** fishing playtest (the fight's first read-out is the aim's range, the float starts where it was hooked and comes in, the shop names the water the next rod reaches) + **13** from the second client, at 0 and 150 ms, **40** e2e, **26** multiclient, **29** movement, remote walker **1** + observer **12**, **60** connect, **13** sidecar, **22** export (the foliage shaders ship with the file they include, and no test code does); the new **render** layer; Rust: **16** fight (the cast-is-the-fight-length rule, and FfC's 40 m reference fight as `REF_CAST`), **4** level (every spot against the rods), **10** fishing rules. Broken on purpose and seen to fail: a grass model imported without the conversion (named), the shader without its un-flip (0.01 from behind), one fight twin without the clamp (exactly the three clamped fights), the old level (the Deep Hole 4.5 m from standable ground), the old line (48 of 67 points under the lake), and the HUD printing the fight's own metres ("2.0 m", with the aim at 18.6 m).
- **After pulling:** restart the editor — if it offers to reload `game/world/lakeside.tscn` (regenerated: the Deep Hole moved), reload it rather than saving over it; if the foliage still has black blades, select `game/world/kits/nature/` and Reimport — and republish the module (the fight and the spots are compiled in; no table changed, so the bindings stand).

## 0.14.2 — the fight, shown
- **A rod and a reel instead of two bars** (DECISIONS #144). The fight is one gauge at the bottom right. The rod's arc fills as you load it, in the colours of the ring round the catch: amber in the band, a pulsing cyan in the sweet spot, a shaking pink past it. The reel's rim is the line's tension, with a white tick where the drag slips. The hub glows when winding pays, and "reel pays" says how much. What the fish is doing and the fight it has left sit on the right, and the line you win pops off the reel. The sweet spot is still never drawn (Luke: "let's not have the sweet spot visible"; FfC's playtest found the same): the colour says when you are in it.
- **The angler does it.** Hold the left button and your angler heaves the rod up while it bends toward the float. The heave is `Fish_Reel`, held at how far through the pump you are for THIS catch, so a tankard lifts the rod as plainly as a sturgeon. Let go and it comes back down. Winding puts the left hand on the reel's handle and turns it: that is IK on the real handle, because neither library has a winding clip and a looped one could not know where the handle is. Under strain the line takes the tell's colour. With a line out and nothing on it, an angler holds the rod out waiting (`Fish_Cast_Idle`), on every client; a snapped line plays `Fish_Reel_Failed`.
- **The foundation gained a held pose**: `hold_pose` / `release_pose` / `play_action` on `AnimationDriverComponent`, a layer between the body and the one-shots (ANIMATION_SPEC §4). A pose is a clip held at a value the genre reads every frame, so it cannot produce gameplay.
- **Reel any time; it pays when the fish is spent** (#145). Two seconds flat out on a pike: fresh wins 0.45 m and loads the line to 0.62 of the snap; spent, 3.9 m at 0.17; resting, 4.4 m at 0.16. Winding into a run wins nothing and takes the line to 0.98 of the snap, because the drag pays out anyway. Both twins and the golden changed. Ace and Good now wind while a fish rests, and a new `Reeler` bot that only winds never gets near an ace.
- **The yellow lasts at least 0.35 s** before the sweet spot. Under FfC's lift it lasted as little as 0.10 s on a fresh sturgeon, fewer frames than a reaction takes. The floor is a cap on the load rate between the band's edge and the sweet spot. Probed at 0, 0.35 and 0.6 s: 0.35 costs an ace up to 4.4 s a fight, 0.6 up to 6.7 s.
- **Tests:**
  - **1150** unit and scene checks, up from 1128. New: the angler in the fight (heave, winding hand, bend and line strain, read off the real feedback, driver and rod), the held pose measured on the skeleton, the gauge, its "+m" labels, and a tankard's heave.
  - **295** integration.
  - **106** fishing playtest, up from 103: the gauge is up for the fight and goes with it, and the angler heaved, wound and bent the rod. Plus **14** from the second client (up from 13: the other angler held the waiting pose). Both at 0 and 150 ms.
  - **40** e2e, **26** multiclient, **29** movement, remote walker **1** + observer **12**, **60** connect, **13** sidecar, **22** export; the render layer.
  - Rust: **18** fight, up from 16 (the reel pays when the fish is spent; the yellow is long enough to see; the golden now covers a resting fish), **4** level, **10** fishing rules.
  - The fishing playtest failed once, for real, and that is how the heave came to follow the catch's own band: it hooked a tankard at 150 ms, and the heave reached 0.15 of the clip.
  - Broken on purpose and seen to fail:
    - the old heave mapping: a tankard 0.19 of the way up, bent 0.17;
    - the gauge's labels without merging: 5 at once, 10 px apart;
    - one twin's yellow cap nudged ×1.01: the golden fails in nearly every case;
    - the winding hand switched off;
    - and, kept in the suite as a control, FfC's lift without the floor: a fresh sturgeon's yellow under 0.15 s.
- **After pulling:** restart the editor (new class names: `ReelGauge`) and republish the module: the fight's rules are compiled in. No table changed, so the bindings stand.

## 0.14.3 — playtest polish: grass, the rod in the hand, fullscreen
- **The grass keeps its colour at a distance** (DECISIONS #146). The kit colours its grass from a palette of thin stripes, and the mipmap a third-person camera picks averaged the light-green stripe with its neighbours and the white beside it: (104,162,0) turned (177,208,128). The grass's shader now reads its palette at full size. `tests/render_test.sh` draws the real tuft close up and 9 px tall: its hue moved 0.17 before and 0.03 now, with a plain mipmapped material kept as the control.
- **The rod is held two ways** (#147). The fishing grip (the reel under the rod, its handle to the winding hand) is unchanged. A new carrying grip turns the reel off the leg; it sat up to 4.7 cm inside the thigh. The hand eases between them as a cast starts and the line comes in, for every angler.
- **The run no longer swings the rod through her head.** There are three separate clips (walk, jog for the default run, sprint), and the rod rode the running arm: its tip swept 88° through the head every stride. While moving, the rod is now carried steady, keeping its resting direction with the grip still in the moving hand. Running, it turns 0.0° and stays 17 cm from the head.
- **Adjust the grip yourself, in the editor**: `game/fishing/rod_grip_preview.tscn`. Pick a pose and drag the Grip node; `rod_grip.tres` is written as you go, and a label reads out the reel's air off the leg.
- **Fullscreen** (#148): F11 or Alt+Enter anywhere in the game, or the Escape menu's new button. The screenshot was the editor's game view in its default "Fixed Size" mode; there, the menu now says to use the view's ⋮ → Stretch to Fit. `tests/render_test.sh` presses F11 in a real window: 1920 x 1080, then back to 320 x 240.
- **Tests:**
  - **1177** unit and scene checks, up from 1150. New: the grip file and its geometry; the preview scene driven the way the gizmo drives it; the rod carried on the real rig (the reel's air off the leg, the running rod's swing and its distance from the head, the cast taking the fishing grip); F11 and Alt+Enter.
  - The render layer adds the grass's colour at a distance and a real F11 in a real window.
  - Unchanged: **295** integration, **106** fishing playtest + **14** from the second client (a crappie at 0 ms, a frying pan at 150 ms), **40** e2e, **26** multiclient, **29** movement, remote **1** + **12**, **60** connect, **13** sidecar, **22** export (the grip file ships in the client), and the Rust suites.
  - Broken on purpose and seen to fail:
    - the grass read through its mipmaps (hue 0.17 apart);
    - FishingFeedback without the carry (the reel 4.7 cm inside the leg; the running rod swinging 81° through the head);
    - the preview editing the wrong grip;
    - the Escape menu ignoring F11 (the window stayed 320 x 240).
  - Kept in the suites as controls: a plain mipmapped material on the tuft, and the old grip left to the hand.
- **After pulling:** restart the editor (new class names `RodGrip` and `WindowMode`; `fishing_rod.tscn` and `pause_menu.tscn` changed — reload them if asked). Nothing on the server changed, so no republish is needed.

## 0.14.4 — restarts, the grip editor in the editor, the lake's depth
- **Snapped into the ground at the dock** (DECISIONS #149). A restarted game (same identity, same player) counted its inputs from 1, while the server still held the last run's count and dropped every frame at or below it. The module's log read "drop input seq=1 (last=570)". The server held the player where the last run left them for as long as that run had lasted, then corrected the whole walk at once: 53.56 m, the spawn to the dock's end. That correction took the distance back but most of the drop to the dock's height, which put the player inside the ground. Now the client carries on the server's count, and a claim too far to believe is clamped as a whole, height with distance.
- **The rod-grip preview works in the editor** (#147). In the editor only tool scripts run, so the characters never assembled and the preview called a method on data; it stood empty while every runtime test passed. `ModularCharacter` is now a tool script, so looks also show when opened in the editor. The preview reads the animation set as data, and its label is readable. Checked in the running editor: posed, holding the rod, and a Grip drag was saved to `rod_grip.tres`.
- **The lake shows its depth** (#150). Coloured by how far down the bed is: turquoise shallows, teal slopes, navy water, and the Deep Hole darkest, blended stop to stop. It was coloured by the line of sight through the water, which from a player's camera is long everywhere, so the lake read as one flat blue.
- **No more "1 resources still in use" at exit** (#151). About half the time a process quit, the pond's looping ambience was still being released by the audio server's mixing thread, and the engine reported it leaked. That hit test runs and game clients alike. Every quit now goes through `AppExit`, which stops the sounds and gives the mixer 0.1 s first; closing the window does too. A lint keeps it that way. `--only=aim` went from 4 leaking exits in 6 to none in 8.
- **The grip preview shows what the game will** (#152). Luke's grip edits did reach the game, exactly (now checked: the rod is drawn where the file puts it, both grips). The preview misled him: it showed a man in the idle's first frame, where the new carrying grip cleared the leg by 5.3 cm, while he plays a woman, and on her the game's idle puts the reel 5.1 cm inside the leg. A woman and a man now hold the grip side by side (every look is one of the two bodies), each label gives the reel's air at its worst through the whole clip and is red below 2 cm, and **Play** plays the clip. The unit suite fails until the carrying grip clears her leg.
- **After pulling:** republish the module (the clamp changed; no table did, so the bindings stand), and restart the editor or close and reopen `rod_grip_preview.tscn`.

## 0.15.0 — built for designers: held items, game rules as data, hooks, one-command publish
- **Held items are a template system** (#153, `foundation/held/`). Any item held in a hand (a rod, a sword, a shield, a bow) is a `HeldItem` with an `ItemGrip` saying where it sits per MODE ("carry", "fishing", "drawn"...) and per ANIMATION. An animation uses its own grip, or borrows the grip of the animation its clip falls back to, or the mode's. In game the grips blend as the animations blend, so walking into a run is smooth. "Steady" is now a setting on a grip, not code: the rod's steady carry is three steady grips (walk, run, sprint).
- **The grip preview works for any item, per animation.** Pick a Mode and an Animation; the label says which grip a drag edits; **Own Grip** gives one animation its own grip (starting where the item already is), **Steady** keeps its direction to the body. Items mark the points to keep off the body (`clearance_radius`), measured against legs, torso and head through the whole clip. The rod's preview is the same tool.
- **`shared/rules.json`** (#154): a new player's health, the interact range (the client's prompt reads it too) and each session kind's round plan (phases, names, seconds) are data, compiled into the server and read by the client. Changing a round's length is an edit and a publish, not Rust.
- **Hooks instead of edits to `module.rs`**: `on_player_created`, `on_player_returned`, `on_player_left` (keep or despawn a player who leaves) and `on_interact` (a game's own entity kinds). A game's per-world tables go in its own `NetConfig.world_tables`.
- **`tools/publish.sh`**: build, publish, and with `--codegen` regenerate the client's bindings, in one command; `--fresh` wipes the data when a table changed shape.
- **The tests have their own database, `umf-test`.** Every server suite publishes and wipes it, never `umf`, the one you play in; a lint stops a test script naming `umf`.
- **After pulling:** run `./tools/publish.sh` once (the module now reads `rules.json`; no table changed, so no `--fresh` and no `--codegen`), then restart the editor: `foundation/held/` adds class names, and the rod preview's script changed.

## 0.15.1 — a grip for her alone; the scripts on Windows
- **A grip can be kept for one body** (#155). Each look now says which body it is (`female`, `male`), and a held item uses that body's own grip where it has one, the shared grip elsewhere. In the grip preview, **Body Grip** makes the grip you are dragging the first character's body's alone: fix the reel off her leg without moving his rod. To fix his alone, put a man first (`look` even, `beside` odd).
- **The scripts run on Windows**: `tools\run.cmd <script.sh> [args]` runs any of them in Git Bash (`tools\run.cmd tests\run_tests.sh`), and `tools\publish.cmd` publishes (double-click it, or `tools\publish.cmd --fresh`). Put this machine's Godot path in `tools\local.env` (copy `tools\local.env.example`; it is not committed).
- **After pulling:** restart the editor (the preview and the looks changed). If the editor asks about files changed on disk, choose **Reload**.

## 0.16.0 — grips by animation and body; the heave at its own pace
- **No more modes** (#156). A held item's grips are per ANIMATION and per BODY, nothing else: whenever a body plays an animation, however it was started, the item sits where that animation's grip says. An animation nobody has set borrows the grip of the animation its clip falls back to, else the idle's.
- **The grip preview** has two choices: **Animation**, and **Body** (`both`, `female`, `male`). Drag the Grip node and you set exactly that animation for that body. The first drag makes it, starting where the item already is. **Steady** is per grip. **Clear This Grip** (a button) takes it away, so it borrows again. Mode, Own Grip and Body Grip are gone. Each label says which grip that character uses.
- `rod_grip.tres` converted from what it held: carry became the idle's grip (sprint keeps its steady grip), and fishing became the grips for the cast (`interact`), `fishing.wait`, `fishing.heave` and `fishing.fail`. Her own grips went the same way.
- **The heave comes back down at its clip's own pace.** Letting go at the sweet spot used to play the rod's drop backwards at about 5x speed.
- **The preview measures the rod's blank, not just its reel.** A node with a `clearance_to` meta is measured as a line to that node (the rod's new `Shaft` marker, to `Tip`). A running rod swinging through the head now turns the label red, as it fails in the game.
- Code: `HeldItem.set_mode`, `mode()`, `mode_weight`, `mode_fade_sec`, `ItemGrip.default_mode`, `modes()` and `source_of` are removed. `ItemGrip.find/resolve/ensure/remove(animation, body)` and `blend(animations, hand, body, body_type)` replace them, with static `ItemGrip.steps(animation)` for the lookup order. `FishingFeedback.HEAVE_DROP_SEC` became `HEAVE_DROP_PACE`.
- **After pulling:** restart the editor (the preview's scripts changed). If it asks about files changed on disk, choose **Reload**.

## 0.17.0 — fit an item to the hand, then check the pictures
- **Fit, don't drag** (#157). The grip preview has **Fit This Grip** and **Fit Every Animation**. They find the hole the hand's curled fingers make, from the finger bones, and put the item's handle in it, clear of the body through the whole clip. Animations that *use* the item (a cast, the heave) hold it along the fist. Animations that only *carry* it (standing, walking, running, jumping) hold it steady toward the grip file's new **Carry Point**, the same in all of them. **Fit Face** sets which way it rolls (the rod's reel below). **Fit Cone Deg** sets how far a fit may turn it to clear the body.
- **Save Pictures** draws every animation (its first frame, and the frame where the item comes closest to the body) into `grip_pictures/<grip>.png`, labelled with each body's grip and clearance: check it, then drag anything that still looks wrong. Fit Every Animation names any animation it could not clear, what touches, and how close the hand itself gets (when the animation puts the hand against the leg, no grip can clear it).
- From a shell, for scripts and agents: `godot --path . -s res://tools/held/fit_grip.gd -- --preview=res://game/fishing/rod_grip_preview.tscn --fit --save` (it needs a window).
- `rod_grip.tres` is now fitted: 21 grips, carried tip-up and forward. The game's checks that failed on the hand-tuned grips pass.
- `tests/render_test.sh` no longer hangs: a broken line in its scene list made it start the game. It also checks Save Pictures now.
- After pulling: restart the editor (the preview's scripts changed).

## 0.18.0 — the hold, the wrist, and putting the rod away
- **A Hold marker on the item** (#158). Put a `Hold` node in the item's scene where the fist should close; grips place that point and the item hangs from it. The rod's sits 10 cm up the cork, and the cork is thinner (1 cm) so the fist really closes round it.
- **The hole is the gap inside the fist.** The fit used to aim between the finger joints; it now finds the biggest circle inside the fist (palm, fingers, and the gap back to the palm), and Fit Every Animation says how thick a handle that fist holds ("about 1.9 cm across").
- **The wrist turns while carrying.** A carried, steady item keeps its direction while the arm swings, and the hand now turns at the wrist (up to the grip file's **Wrist Turn Deg**, 60) to keep the handle in the fist. Each preview label says "in the fist" or how far the handle leaves it, and the fit checks it (**Fit Cone Deg**, 15).
- **Carry Point is a node** in the preview: drag it, and the grip file's Carry Point follows; the carried animation you're looking at is fitted to it a moment later.
- **Put away and drawn.** The grip file's new **Stow** settings sling the item on a bone (the upper spine). In the preview: **Show Stowed**, a **Stow** node to drag, and **Fit Stow**, which slings it where the draw's hand reaches, hanging the way **Stow Point** asks, and makes the draw and the stow meet it with no jump. The draw and stow (`Sword_Enter`/`Sword_Exit`, over the right shoulder) play on the UPPER BODY, so the legs keep walking.
- **Try both**: on the fisher's `FishingFeedback`, **Rod Away** is `ON_BACK` (default: put away 1.5 s after fishing, drawn when you aim) or `IN_HAND` (carried, the wrist keeping it in the fist).
- The animation tree has a new upper-body one-shot (`AnimationDriverComponent.play_upper`); the sets map `item.draw` and `item.stow`.
- `rod_grip.tres` refitted with all of it.
- After pulling: restart the editor.

## 0.18.1 — the cast waits for the rod; the Carry Point on the hand
- **In hand or put away is game state** (#159): a new foundation `EquipComponent` (on the fisher as `Components/Equip`). The game asks it `is_equipped()` before anything that needs the item in hand. **A cast let go while the rod is still being drawn waits, and goes the moment the rod is in hand**; the draw plays first, then the cast. Attacks and abilities can check the same thing later.
- **Away When Idle** on the fisher's Equip node replaces FishingFeedback's Rod Away: on, the rod is put away 1.5 s after fishing stops (Away After Sec) and drawn when you aim; off, it stays in your hand.
- **The Carry Point sits on her hand** in the grip preview. Turn it: green (Y) is where a carried rod points, blue (Z) the side away from the reel. The animation shown is refitted to it a moment later; Fit Every Animation carries it that way everywhere. With Play ticked it rides the hand; untick Play to turn it.
- Code: `HeldItem.follow(equip)`, `draw_seconds()`, `stow_seconds()`; `AnimationDriverComponent.stop_upper()`; `FishingComponent.waiting_for_rod()`.

## 0.19.0 — the rod comes out once, everyone sees it, and the hand stays shut
- **A fast cast no longer draws the rod twice.** The hand takes the rod a third of the way into the draw. The rest of the draw clip froze under the cast and played after it. Now anything that covers the whole body (a cast, a hit) ends the draw. A refused or short cast also no longer puts the rod away while the cast still plays.
- **When the rod goes away** is three settings on the fisher's `Components/Equip` node:
  - **Away After Sec**: now 10 s without fishing.
  - **Away When Faster Than**: Never, Walk or Run. It is now **Walk**, so running puts the rod away.
  - **Away Moving After Sec**: 0.3 s at that speed.
  - Untick **Away When Idle** to keep the rod in hand always.
- **Other players see your rod come out as you start drawing**, not when your cast arrives. A new public table, `equip_state`, holds what each player has in hand, and a new reducer, `set_equip_state`, sets it.
  - Your `umf` database is already published with it, keeping your data, and the bindings are regenerated.
  - Anyone else pulling this runs `tools\publish.cmd`.
- **The hand stays shut round the rod while jumping** (or dying, or reviving). Fingers that the clip opens close back toward the idle's fist, as far as the clip opened them. That fist is the grip file's new **Fist Animation**. Clips that already make a fist are untouched, so no grip moved. The preview shows it too.
- New check: every game scene subscribes the tables its entities' components need. The fishing game's `fishing_net_config.tres` was missing the new table.
- `tools/publish.sh --codegen` now refuses any database but `umf`. The bindings are generated from `umf`'s schema, whatever `DB` says.
- Code: `EquipComponent.in_use()`, `reported()`, `deciding()`, `moving_speed()`; `GripFit.fist_pose()`, `close_fist()`; `HeldItem.close_fist_now()`, `fist_closed()`; `AnimationTreeBuilder.clip_animation()`.

## 0.19.1 — what the pictures showed
- **Pictures of the game as it is played:** `SHOTS=grip_pictures/play tools\run.cmd tests\fishing_playtest.sh` plays the fishing loop in a window and saves a picture of every moment (walking, aiming, the cast, the wait, the bite, the fight from four sides, the catch, the results, the shop) in that folder. Shots mode also leaves a line out when the round ends.
- **A cast refused after the float left** (the round ended as you cast) brings the float back in. It used to stay on the water, and the rod was later put away under its line: your round-over picture.
- **The bell brings the lines in.** When a round's play ends, every line nothing has bitten yet comes in ("the round is over: line in"). A fish already biting or on the line is still yours to land through the results. Before, a waiting line could get a bite during the results screen.
- **The rod packs short on her back** (your choice): the grip file's new **Stow Length** (the rod's is 0.45). It packs in her hand as she puts it away and stretches out again once she has drawn it. Its tip no longer drags on the ground or the dock.
- **The left hand stays on the reel for the whole fight**, heaving too.
- **The fight gauge** sits on the right, above the prompt line, and shrinks in a small window. It covered the prompt and the hook-set bar.
- Server: a new genre hook, `on_phase_changed`. No table changed: publish with `tools\publish.cmd`, which keeps your data.
- Code: `ItemGrip.stow_length`, `packing()`; `HeldItem.packed()`; `FishingHUD` gauge layout; tests for each, each seen to fail without its fix.

## 0.19.2 — the reeling arm out of her body
- **Her left arm no longer goes through her body while reeling.** The elbow is pulled out to her left side and a little forward, worked out from her body every frame, so the forearm crosses in front of her to the reel. Before, the elbow followed the rod's angle, and after the grips were refitted it was dragged into her middle: the forearm sat 6 cm inside her heaving and 12 cm inside winding. Now it is 11 cm and 8 cm clear.
- **Waiting for a bite, her left hand holds the rod at the reel** too. It used to hang clenched in the air in front of her until a fish was hooked. It still lets go while the cast clip plays.
- Only the suites this touches were run: aim, animation scene, and the fishing playtest with pictures.

## 0.19.3 — every animation checked for arms in the body
- **The cast is fixed:** her left hand holds the reel through the cast, as it does waiting and fighting. The clip's own left hand is not on our rod, so it crossed her belly and pressed into her chest.
- **Which animations the rod is held two-handed in** is now the rod's own list: `two_handed` on the rod (the cast, the wait, the heave). Add an animation there and the left hand takes the reel while it plays.
- **A new test suite, `arms`**, plays every animation in the set, for both body types, and checks two things as the game draws them:
  - **Into the body:** a forearm or hand may sink no more than 3 cm deeper into the body than when standing, and an upper arm no more than 4.5 cm. This is measured against the character's real skin.
  - **On the rod:** in every two-handed animation, her left wrist stays on the reel.
- `--arm-pictures=<folder>` with a window saves close-ups of the worst moment of any animation that sinks an arm in, plus the cast through its whole clip.
- Code: `SkinClearance` (foundation), `FishingRod.two_handed`, `two_handed_weight()`.

## 0.20.0 — ready for a friend, a richer lake, and your own character
- **Version check:** before connecting, the game compares the server's version with its own. If they differ (for example, after you republished and your friend still has the old build), the connect screen says so plainly instead of failing strangely. Republishing with `--codegen` now prints a reminder to export again.
- **Settings**, in the Escape menu and on the connect screen, saved on each computer:
  - **Video:** fullscreen, vertical sync, a frame-rate limit, render scale, anti-aliasing, shadows, interface scale.
  - **Audio:** master, music, sound effects, ambience and voices, each on its own bus.
  - **Controls:** mouse sensitivity, invert look, and rebinding every key, including fishing's own keys.
- **Open log folder**, in the Escape menu: a friend can send you their log.
- **Character picker**, on the connect screen and in the Escape menu. Choose your look and its skin, hair and outfit colours, with the character turning in front of you. Everyone sees what you pick. A change made mid-game waits until your line is in.
- **Music:** one generated track while a round plays, another in the lobby, results and shop.
- **Time of day and weather:** each round is dawn, day, dusk or night, and clear, overcast, rainy or foggy. Both change what bites and how fast. The HUD tells you the conditions and what they favour, and the sky, fog and rain show them.
- **Old Barnaby**, a rival angler, fishes the lake in the default world and plays the rounds.
- **Other players' fights are visible:** you can watch a friend heave, their rod bend and their catch come in.
- **Catch journal and records** (J, or Journal in the Escape menu):
  - every kind you've caught and still have to find;
  - the biggest of each kind anyone has landed;
  - every angler, ranked by what their catches have earned.
- **The off hand is item data:** which animations hold the rod in both hands now lives in `rod_grip.tres`, and the grip preview shows the left hand on the reel.
- Code: `SchemaFingerprint`, `Settings` (autoload), `SettingsPanel`, `CharacterPicker`, `Appearance`, `EntitySpawner.respawn`, `SpaceTimeComponent.blocks_respawn`, `MusicDirector`, `OffHand`; fishing's `FishingConditions`, `SkyDirector`, `FishingRecords`, `CatchJournal`, `CharacterLooks`.
- Server: the `appearance`, `fishing_conditions`, `fight_show`, `fishing_rival` and `rival_bench` tables; the `set_appearance`, `show_fight`, `set_rival` and `rival_tick` reducers. Republish `umf` with `--codegen` (no wipe needed).
- New test suites: `version`, `settings`, `music`, `looks`, `fishing_world`. The connect playtest picks a character and meets a server running another version. The observer in the fishing playtest watches the other player's fight.

## 0.21.0 — the template: genres as modules, the lobby, levels built in the editor
- **Genres are modules.** `shared/game.json` lists the genres a game is made of; the server compiles in exactly those and the client boots exactly those. Each genre is a folder: `server/src/game/<name>.rs` plus its rules in `server/src/genre/`, and `game/<name>/` with a `genre.tres` saying what to boot. Two genres can't claim the same numbers; a clash stops the server at start-up. Take fishing out and the foundation still builds, tests and publishes on its own (`tests/genres_test.sh` proves it).
- **The lobby.** Between rounds a lobby lists who is here, who is ready and their teams. Press R when you're ready: once every player is, the round starts at once. T changes team in a game with teams (`shared/rules.json` → `lobby`).
- **Levels built in the editor.** Put a `LevelInfo` node and markers in a level scene: `LevelSpawn`, `LevelSpot`, and `LevelPoint` for anything else a genre needs. Press **Bake For The Server** and the scene's own ground and markers become the server's level file. A world's level is now the foundation's to set (`set_world_level`), and the game swaps to the matching scene. **The meadow** (`game/world/levels/meadow.tscn`) is the example: level 2, a pond built from CSG.
- The fishing scenes are now a level plus Boot: the HUD, the sky and the music come from fishing's `genre.tres`.
- Server: the `lobby_member` and `world_level` tables; the `set_ready`, `set_team` and `set_world_level` reducers; the `Genre` trait with `on_level_changed`. Republish `umf` with `--codegen` (no wipe needed).
- New test suites:
  - `genres` and `tests/genres_test.sh`: the foundation with no genres.
  - `lobby`. The connect playtest presses R in a real lobby.
  - `levels`: the meadow's bake is current, and agrees with the lakeside's generator.
  - Native: `cargo test --test genres`, and the meadow in `--test level`.
- **Fix:** the fishing playtest no longer waits forever on an observer whose script fails to load; it fails after 240 s.

## 0.22.0 — every piece of your character, and two things you saw
- **Mix and match every piece.** The character picker starts from a look, then lets you change any part of it from the pieces made for that body: torso, arms, legs, feet, headwear, shoulders, neck, hair, beard and eyebrows. The torso, arms, legs and feet each have a colours choice beside them. A piece keeps its own outfit's colours, so a noble torso on a peasant is still noble red. Add a piece by appending it to its slot in `game/characters/character_looks.gd` (DECISIONS #178).
- **Fix: the rival stood in the middle of the lake.** The client spawned him without his position, so he stood at the world's origin, out on the water. He arrived with about 900 catches, and the registry kept only an entity's newest 256 early rows, so his position was pushed out. Now an update replaces the row it follows, and nothing is dropped (#176).
- **Fix: spots on a character as the camera zoomed out.** The automatic LODs simplified each worn piece on its own, so at a distance the hair sank into the scalp and skin showed through it. The character pieces now import without LODs (#177). Pictures before and after are in `grip_pictures/v021/`.
- **Fix: the test suites read your saved look.** The e2e client runs as editor slot 1, the slot you play on, so once you picked a look it was rebuilt in the middle of the test. Under a test suite the connect profile is now the test database's own (#179).
- Server: a look can be 256 characters (it was 64). Republish `umf` (`tools\publish.cmd`, no wipe, no codegen).

## 0.22.1 — the journal remembers, and other anglers' fights move
- **Fix: the journal showed one catch per angler.** When an angler appeared, each of their components was handed only the newest row of each table, so 50 catches arrived as one. Only fish caught while you were playing were added after that. Now every row arrives, and old catches are on the record without being celebrated again (DECISIONS #180). Your muskellunge is back.
- **Fix: another angler's fight looked like a slideshow.** Their heave was set straight from each report (the rival reports twice a second), so it held still and then jumped. It now moves from one report to the next over the time between them, and the rod strains while their catch runs (#181). Measured at 144 fps, the rival's skeleton moves on 140 to 144 frames a second in a fight; it was 2 to 50.

## 0.23.0 — a splash, a lobby, and rounds that start from 1
- **A splash screen.** The game's name and a line under it, for a moment before the connect screen; any key or click skips it. Change the words, colours or add a logo on `game/splash_screen.tscn` (DECISIONS #183).
- **The lobby screen.** After connecting you land in a lobby: everyone stands on a stage in the looks they chose, with their names and whether they're ready. **Choose character** opens the character picker; **Ready** (or R) says you're ready; when everyone is, round 1 starts and you're in the game. Arriving in the middle of a match, it offers **Join**. Esc still opens the menu over it (#182).
- **Rounds count from 1 in each match.** A match is the rounds played from when someone arrives until everyone has left. When a world has had nobody online for a minute, its match ends and nothing more is played or counted (the rival stops fishing to an empty lake); the next match starts at round 1, at dawn, once its players are ready. `new_match` (admin) starts a new one by hand. Your catches and coins are kept.
- Server: the `session_match` table, the `new_match` reducer, the `on_match_began` genre hook, and a `match` section in `shared/rules.json`. Republished `umf` with `--codegen` (no wipe).

## 0.23.1 — ready, for players from before the lobby
- **Fix: "you are not in a session" when pressing Ready.** Players who joined before lobby rows existed (0.21.0) never got one, since the world was republished without a wipe. The server now makes a missing lobby row when the player connects, and when they press Ready or change team (DECISIONS #184). Republished `umf` (no wipe, no codegen).
- The client's game data is now inside `umf.exe` (no `umf.pck`); send the zipped `build\client` folder, which also holds Terrain3D's library (#185).

## 0.23.2 — a republish is not a new version
- **Fix: "this server is running a different version of the game" after every republish.** The server lists its tables in a different order each time it's published, and the version check fingerprinted that order. It now ignores order (DECISIONS #186). Export the game again: older builds compare the old way.

## 0.24.0 — before strangers play (REVIEW 0.23.1 B1–B5)
- **Players can no longer teleport themselves.** `teleport` and `dev_nudge` are admin-only unless a database's dev tools are on (`set_dev_tools`, admin); the test suites turn them on for `umf-test` (DECISIONS #187).
- **No walking on the lake.** The server refuses a position claim that walks off standable ground into water too deep to wade, using the level's bake (`LevelBake.can_stand`, both twins, #188).
- **Rate limits** on the reducers whose rows everyone receives, as data in `shared/rules.json` `rate_limits` (#189).
- **The builds leave out editor tooling** (`addons/godot_ai`, the new `addons/umf_export` plugin that keeps the bridge's autoload out of exports) and Terrain3D's `demo/` is gone; the SpacetimeDB crates are pinned to `=2.10.1` (#190).
- Fixed a test that depended on the order the server lists its tables (#191).
- **Fix: other players' jump and land animations restarted** (the friends' test). Walking up a slope read as a jump to everyone watching, and a jump's top as a landing; the server now takes 'in the air' from the player's own movement state (#192).
- **Split for the template (REVIEW C1–C3):** AGENTS.md is 1,700 words with the topical rules in `docs/rules/`; DECISIONS.md has an index by system; the unit tests are one file per suite (`tests/suites/`); the module is one file per system (`server/src/module/`); a CI workflow (`.github/workflows/ci.yml`, not yet run on GitHub) (#193).
- Server: new private tables `dev_tools` and `rate_budget`, new reducer `set_dev_tools`. Republished `umf` with `--codegen` (no wipe). **Export again** before playing with a friend: older builds are refused.

## 0.24.1 — the foundation and fishing, apart
- **Every file is the foundation's or fishing's** (`tools/template/genres/fishing.paths`), and `tools/template/strip_genre.py fishing` makes the game without it (DECISIONS #194). The foundation's own tests run on its own character, the greybox game and an example level; fishing's tests are in `game/fishing/tests/`.
- **Each game names its database** in `shared/game.json` `database`; Fishing's is `umf`, unchanged (#195).

## 0.25.0 — the template
- **UMF Template** (github UMF-Foundation): the foundation with no genre, made from Fishing 0.24.1; games are its forks and take its updates with `git pull template main` (`docs/TEMPLATE_WORKFLOW.md`, #196).
- **`GAME.md`**: each repo says what it is; AGENTS.md is the foundation's and the same in every game.
- **The specs are in the repo**: `docs/CONTENT_TOOLING_SPEC.md` (workbenches, the Content Dock, hot tunables, the admin panel) and `docs/reviews/REVIEW_0.23.1.md`.
- Codegen names the bindings `Umf` whatever the database is called; a pull keeps a game's own bindings (`.gitattributes`).
- **A foundation HUD** (`foundation/ui/hud.tscn`): the greybox game shows its connection and round; a genre's `HUD` replaces it (#197). The sidecar no longer subscribes to fishing's tables by name.

## 0.26.0 — old builds keep working on new servers
- **The version check is a contract** (DECISIONS #198): a build checks only the tables and actions it uses, so a server that ADDED things still plays with older builds. A server that changed one is refused with the reason on the connect screen.
- **`compat` in `shared/game.json`** (1 when absent): bump it for a deliberate break, and every older build is told to update.
- **`tools\release.cmd`**: exports and tests both builds, records the build's contract in `shared/compat/` (commit it), and zips the client to `build/releases/`. The unit tests then fail while a change would strand a released build.
- `tests/export_test.sh` plays the exported build against a newer server (it plays) and the next generation (refused).
- Server: a new reducer `compat_generation_1`. Publish with `--codegen` and export once more: builds from before 0.26.0 compare fingerprints exactly and are refused by any new server (this is the last time).

## 0.27.0 — content is resources (CONTENT_TOOLING_SPEC step 1)
- **`ContentDef`**: content is a `.tres` edited in the Inspector, with tooltips and bounds; `tools/bake_content.gd` bakes it to `shared/content/` for the server (DECISIONS #199, `docs/rules/content.md`).
- **The server refuses a stale bake**, naming the file: a `.tres` changed or added without baking, or a baked file edited by hand. `tools\publish.cmd` bakes first.
- **Abilities are content**: the built-in `melee` is `foundation/content/abilities/melee.tres` (it was hard-coded in the module); a genre adds abilities by adding `.tres` files.
- New suites: `content` (unit) and `tests/content_test.sh`.

## 0.28.0 — the Content Dock (CONTENT_TOOLING_SPEC step 2)
- **A Content panel at the bottom of the editor**: every content type and its pieces, search, New (the next free id, the right folder), Validate (every problem in words, a click opens the piece), Bake, Publish (its output in the panel) and Play (DECISIONS #200, `docs/rules/content.md`). **Restart the editor once** to load it.
- **`ContentLibrary`**: one place that knows where content is; content types are found by themselves (a new `ContentDef` subclass needs no registering).
- **The bake checks more**: ids unique across the foundation and every genre, a genre's type only in its own folder, every piece in its type's folder, links only to baked content. Baked files carry a format number the server checks.
- **`content_id_base`** on a genre's `genre.tres`: where its new content's ids start.
- `foundation/content/abilities/` is now `foundation/content/ability/` (one folder per type, named after it).

## 0.29.0 — hot rules: tune the game while it runs (CONTENT_TOOLING_SPEC step 3)
- **Hot rules** (DECISIONS #201): numbers the server serves live. The admin changes one in game (Escape, **Rules (admin)**) and every player follows at once, old builds included: no republish, no re-download.
- **Declared as content**: rule sets in the Content panel (type `rules`), each rule with bounds, a unit and a description. A genre sets its game's value for a foundation rule with an override, never by editing the foundation's file.
- **Keep live tuning** (Content panel): what the admin tuned becomes the game's defaults.
- **Moved**: the interact range and a new player's health are hot rules now (`shared/rules.json` no longer has them; the build says so if a game's still does).
- Server: new table `hot_rule`, reducers `set_rule`, `reset_rule` (admin only). Every client now also subscribes to `authority` (who the admin is). Additive: older builds keep playing. Publish with `--codegen`; **restart the editor** (a new autoload, `HotRules`).
- New suite: `tests/hot_rules_test.sh` (a real server).

## 0.30.0 — players who leave, leave; one name, one player
- **A player who quits leaves the world** a few seconds later (the hot rule `foundation.offline_linger_s`): no more characters standing on the dock for players long gone. They come back where they left (DECISIONS #202).
- **Names are unique**, whatever the case. Two players who already shared a name: the first keeps it, the other becomes "Name 2" on their next join.
- **Notices on screen**: lost connection, reconnecting, a name refused (they were sent before but nothing showed them).
- Server: no new tables or reducers (old builds keep playing). Publish; restart the editor.

## 0.31.0 — workbenches and the Catalog (CONTENT_TOOLING_SPEC step 4)
- **Workbenches** (DECISIONS #203): make and try a piece of content with the real character, no server. The first is the **ability bench**: a range ring, a dummy, and tests that play the wind-up and say what the game would do (hit, refused out of range, refused on cooldown). Edit the ability in the Inspector and the bench follows.
- **The Catalog**: a second tab in the Content panel, every piece as a card with its picture and a red / amber / green strip; click to open it in its bench; Regenerate redraws every picture.
- Every content type has a bench, or says why not (rules: tried live in the game). A new bench is mostly its tests (`docs/rules/content.md`).
- Players who are not connected cannot be targeted by abilities either.
- No server schema change. **Restart the editor.**

## 0.32.0 — characters are content, with a bench
- **The character workbench** (DECISIONS #204): drop a rigged model in (New From File) and get a character, in the right folder, on the bench. Fit it (feet on the floor, facing the arrow), see it beside the capsule it really collides with, play every animation, and hear which ones the game needs are missing.
- **Character definitions are content**: the foundation's are `foundation/content/character/` (player, npc, humanoid); they show in the Content panel and the Catalog. A genre's become content when it moves them into its own content folder.
- Workbenches can make a new piece from a file (`fill_from_file`); the next benches (fish models, sounds) use it.
- No server schema change. **Restart the editor.**

## 0.33.0 — each character moves its own way (Foundation systems, milestone 1)
- **The plan** for the foundation systems Fowl Play (and every later game) needs: `docs/FOUNDATION_SYSTEMS.md`, twelve milestones, their data and how each stays compatible and tunable.
- **Movement profiles** (DECISIONS #205): a character links to a profile (its speeds, jump, flaps, dash); its entities move by it, predicted and simulated the same way. The server bounds each kind by its characters' profiles.
- **The movement workbench**: measures a profile with the game's own movement (time to top speed, slide to a stop, jump height, each flap, turning round) and draws the path.
- `--character=<path>` plays as any character for a run.
- No server schema change. **Restart the editor.**

## 0.34.0 — statuses and their timers, spectate (Foundation systems, milestone 2)
- **Statuses** (DECISIONS #206): downed, out, injured, carried, hidden, escaped, and a genre's own, as content (`StatusDef`, Content panel type `status`). Each says how long it lasts and what it becomes, how a character moves in it, whether it can act or be reached, and how it shows. A genre changes one of the foundation's by making its own with the same number.
- The server keeps who is in which and moves them on when the time is up; abilities and use hold to it; a downed player's speed is enforced. A new match puts everyone back to normal.
- **On screen**: a downed player crawls (predicted, no rubber-banding), out players vanish and watch a teammate (Jump: the next), a tag over each head, your own status and countdown on the HUD.
- **The status workbench**: how a character moves in a status, its burst, its pose, its timeline.
- **Try a status on yourself**: Escape, Rules (admin).
- Server: a new table and reducers (old builds keep working). **Republish with codegen; restart the editor.**

## 0.35.0 — Workbenches 2 (from the first real test of the benches)
- **The piece in the Inspector, the bench in its own panel** (Workbench, beside the Inspector): tests as buttons that say what they play, settings, and actions. What you change is always the piece.
- **Benches never change their own files** when used.
- **The character comes first**: its body drawn around the model (and its size a field: `collision_radius`, `collision_height`), `visual_scale`, ANY animation played, paused, slowed or scrubbed, an animation set made from a model's own clips with each clip a choice, then **New movement for it** and **New ability for it**.
- **The movement bench performs**: the character runs, stops, jumps and turns along the path with a ruler, labels and its speed.
- **Play as this** (character or movement), publishing first when the content changed.
- **In a game the template's content is read-only**: Copy into your genre; **New from this** for any piece.
- **A character's abilities**: the server lets a character use only its kind's abilities (a kind listing none may use any).
- Fixed: a model dragged in was named after its internal id; the two "Player" characters are now Player (plain capsule) and Humanoid.
- Server: no table changes (the abilities rule is new logic). **Republish; restart the editor.**

## 0.35.1 — workbench fixes from the second test
- Opening a workbench now brings the **Workbench** panel to the front (its title in gold): Luke's second test never found it, docked as a tab behind "Godot AI" below the Inspector. The bench's own status and the Content panel's Open workbench say where its controls are.
- **Fit the body to the model fits its core**: a beak, head feathers or a tail are left out. **Body height** and **Body radius** are in the panel beside it, to fine-tune with the capsule following.
- **Moving between benches**: a bench opened from another has **← Back to …**; the movement and ability benches have **Open character: …**; the character bench has **Open** for each of its abilities.
- **Play as this only publishes when the server's content changed**: a look, an animation or a fit plays at once (the bake is refreshed locally).
- **Choose a character's movement and abilities from lists** in its bench (Movement, Add ability) instead of the Inspector's New, which made blank ones inside the character.
- **A movement or ability made inside a character** (the Inspector's New on its field) is saved as its own piece and linked, on Save or Play, instead of Play refusing it.
- The bake writes into a test's scratch project when there is one, never over the real bake.

## 0.35.2 — a model's own animations play
- **An animation set made from a model's own clips now moves its bones.** A glTF's clips are addressed from the model's root (`CharacterArmature/Skeleton3D:Head` in the chicken), but the game and the benches play a set from the skeleton's parent: not one of the chicken's clips reached a bone, and the editor filled with "couldn't resolve track" warnings. `ClipMatcher.set_from_model` now copies the clips re-addressed, as `tools/extract_animation_library.gd` does for the humanoid's. A set made before this needs making again (the character bench's **Animation set from the model**).
- The bench's preview of a model's own clips (`model/Walk`) keeps working when its skeleton is renamed for the game's (`Skeleton3D`).
- **The panel's choices follow the bench**: switching to another piece left "Tried on" showing the last one's character (Chicken, from Peck) while the new ability, which no character listed, was on the humanoid.
- No server change: nothing to republish for the template; restart the editor.

## 0.36.0 — hold to interact (foundation systems milestone 3)
- **Hold E to do something** (DECISIONS #209): where a press would start a hold, the interact key is held. Down begins it, up lets go; others can join, and it goes faster together. Moving away from where you began, being hurt, a status that cannot act, or leaving the game lets go; when everyone has let go the progress is lost, or kept (a half-laid nest).
- **Holds are content** (`HoldDef`, Content panel type `hold`): which press starts it (a verb on these characters, by those, while the target is in this status), seconds to finish alone, with two, with three..., what stops it, and the status the target is left in when done. One press, one hold: two that one press could start are refused (by the bake and by the build), unless a genre's replaces the foundation's.
- **Help up** (foundation): hold E on a downed player or NPC, 4 s alone, 2.5 s with two, 2 s with three; back on their feet when done.
- The HUD says "Hold E: Help up" and draws the bar, moving smoothly between the server's updates; the doer holds the hold's pose.
- Rules: `foundation.hold_speed` (every hold's pace, live: 0.5 = twice as long), `foundation.hold_leave_slack_m` (how far past the reach before a doer lets go).
- For a genre: `may_hold` (refuse), `hold_rate` (another speed, negative to undo: a nest cooling), `on_hold_completed`, `on_hold_left`; bots and NPCs hold through `begin_interact_as` / `end_interact_as` (an authority's).
- Server: two new public tables, `hold_progress` and `hold_member` (no table changed shape), and new reducers. **Republish with codegen; restart the editor.**

## 0.37.0 — server-timed skill checks (foundation systems milestone 4)
- **A skill check judged by the server's clock** (DECISIONS #210): a marker sweeps across a bar, the player presses (the interact key) while it is in the target, three times. The player's game sends only "pressed"; the server works out where the marker was when they saw it, from when the press arrived less half their quickest round trip (which the server measured itself: the game acknowledges each check the moment it arrives), at most a rule's cap. Lag no longer costs a good press, and a cheat cannot claim one.
- The game draws the marker from the server's clock and shows each press's result at once (its prediction), replaced by the server's a round trip later: Great, Good, Miss. `TimingBar` on the HUD.
- Using a resource node, and a genre's `issue_challenge_for`, now start a timed press (challenge kind 1). The old timing bar (kind 0, judged from where the game said it stopped: an outcome) is still accepted from old builds; nothing issues it.
- Rules: `foundation.press_credit_cap_ms` (120: the most lag forgiven; 0 judges on arrival), `press_lead_in_ms`, `press_sweep_easy_s`, `press_sweep_hard_s`.
- Proven at a 150 ms round trip by a real client: pressing on the centre of its own bar scored 0.83; with no credit the same play scored 0.00.
- Server: new tables `timed_press` (public, each player's own) and `client_rtt` (private), new reducers `challenge_seen` and `challenge_press`; no table changed shape. **Republish with codegen; restart the editor.**

## 0.37.1 — fixes from trying Help up
- **The target is what you stand at, not only what the crosshair is on** (DECISIONS #211): facing a downed teammate within reach offers "Hold E: Help up" while the camera looks elsewhere (third person, scouting while acting). The crosshair still wins when it is on something. Only things there is something to do with are offered nearby (a hold that applies, or what a genre's `nearby_wanted` accepts), so a crowd of players is never "the target". `InteractionComponent.targeting` (crosshair, nearby, both) and `facing_cone_deg`.
- **An out player no longer falls into the void**: hiding a body cleared its collision mask too, so its own game dropped it through the floor, and coming back in left it there. Hidden, nothing collides with it, but it still stands on the world.
- **Rules (admin): Go to** the spawn or beside any player (stuck, lost, or to try something on someone).
- To use the Rules page from the editor's players: they are not the admin (the identity that published is). Make one an admin with `spacetime call <database> register_authority <identity> 0 0`.

## 0.37.2 — right beside them is enough
- Standing right beside a downed teammate offers "Hold E: Help up" whichever way you face (within 1.5 m, `InteractionComponent.close_m`). 0.37.1 still needed them inside a 70-degree cone of where you or the camera face, and the character faces where the camera does: someone square to your side was missed (Luke). Further away, they still need to be roughly in front.
- The two-player playtest now helps up from beside the downed player with the crosshair on nothing.

## 0.38.0 — a splash with tips and lore; the front of the character; a calibrated bar
- **The splash is every game's** (DECISIONS #213): the game's name, a line under it, and its TIPS AND LORE one after another (`lines`, a new one every 3 s), for 5 s; a picture behind it, a logo, colours; water ripples only for a game that asks (Fishing). Any key skips it; **Settings, Game: "Splash screen at start"** turns it off for testing (`--no-splash` too). The template's lists its own controls; Fowl Play's tells of Hollow Hill Farm and GroMax; Fishing keeps Old Barnaby.
- **The target in front of the character** replaces 0.37.2's 1.5 m all round (Luke: "not immersive"): within reach and inside a 120-degree arc across the front of the model (`InteractionComponent.front_arc_deg`), not beside, not behind. The crosshair still wins when it is on something.
- **The skill check's bar calibrates itself** from the server's judgements: each judged press says when the server took it to be; the bar is drawn that much on (the median of the last few, at most 0.3 s), so a press on the line in Great is judged Great. Luke saw Great judged Good: the clock the bar is drawn by comes from row timestamps, which can arrive later than half a round trip. The bar also marks where the server judged each press.
- No server change: nothing to republish.

## 0.38.1 — the character decides; the press, beside the judgement; no flash before the splash
- **In third person the crosshair no longer picks what you interact with** (DECISIONS #214): only what is in front of your character, within reach (the 120-degree arc). Luke saw Help up offered for someone his character was not facing, because the camera's ray was on them. In first person the crosshair still goes first (it is where the character looks): `InteractionComponent.targeting` AUTO, from the camera rig. With no ray in third person, the arc now also offers what is not a person (a resource node, a genre's own kinds) and props in the `interactable` group; people only when there is something to do with them (a downed teammate).
- **The skill check shows each press under the bar**: that press's zone (lighter, its Great band brighter), a white line where the marker was drawn when you pressed, and an orange one where the server judged it: whether it is your timing or the game's, at a glance.
- **No frame of the level before the splash**: its background is opaque from the first frame and only its words fade in (it used to fade in whole, so the level showed through for its first frames; a capture of a real launch showed the grey level, now the splash's colour).
- No server change: nothing to republish.

## 0.38.2 — the skill check's results stay, in their places
- **Each press's strip keeps its own zone after the check** (DECISIONS #215): the last press closes the challenge on the server, and the bar read the zones from it afterwards, so all three strips jumped to the middle (Luke). Each press now keeps its zone from the moment it is made.
- **The results stay until you move away** (half a metre), or 15 s (`TimedPressComponent.results_linger_s`, `results_move_m`), instead of 1.5 s.
- **Rolling**: the last six presses stay listed, across checks, so a check started at once shows the previous one's presses above its own.
- No server change: nothing to republish.

## 0.38.3 — newest press at the top
- The skill check's strips list the newest press at the top, the older ones flowing down beneath it (Luke), DECISIONS #216.
- No server change: nothing to republish.

## 0.39.0 — choose a character; the skill check's own key; a genre's own checks
What Fowl Play's nest needs from the foundation (DECISIONS #217, #218, #219).
- **Play as** (DECISIONS #217): a character can be marked `playable` (EntityDefinition, How it plays). The lobby screen offers the game's playable characters (Play as: <name>, cycling) and the in-world lobby the C key; the server's `choose_character(kind)` makes the player's entity that kind, in the lobby (an admin at any time). Every client builds the entity again from its new kind: model, body, movement, camera. A genre decides who may be what (`may_choose_character`: one predator a night) and what follows (`on_character_changed`), and puts a new player in its starting character with `set_character_internal`. The foundation's own characters are not playable: a game marks its own, so the bare template offers none.
- **The skill check has its own key, Space** (DECISIONS #218, rebindable in Settings: Skill check). A check can come up while you hold E (an egg wobbling under a sitting hen), so E could not press it. E still presses a check when you are not holding anything. While a check is up, Space does not jump (a hen jumping off her nest would let it go), until you let go of it. The bar says which key.
- **A genre's own skill checks** (DECISIONS #219): `issue_timed_press(entity, difficulty, rounds, scored, payload, ttl)`, with 1 to 3 presses and the choice not to score them (the foundation adds score and coins for every check; a wobble's result is warmth, not points); `press_result(challenge_id)` tells a genre how it went when it closes (None: it ran out of time); `close_if_expired` ends one on time from the genre's own tick, rather than at the next 5 s prune; `challenge::grade` gives Great/Good/Miss by the same threshold the bar shows (`GREAT_FROM`, 0.75, checked against the client's).
- **Fixed**: `issue_challenge_for` (a genre's way to start a check) still issued the old timing bar, judged from where the client said it stopped, whatever its comment said; nothing called it. It issues a three-press timed press now.
- Server change: republish (new reducer and private table; additive, old clients unaffected).

## 0.39.1 — a genre moves a hold along; a word on the prompt
- `nudge_hold(hold_id, by)` (DECISIONS #220): a genre adds to or takes from how far along a hold is (a great wobble warms a nest 3 %, a raid cools it 25 %), and it is settled as any change is: done at 1, gone when undone with nobody on it. `hold_progress_now` reads how far along one is.
- `HoldPrompt.add_note(func(me, target_id, hold) -> String)`: a genre says why a hold would be refused before the player tries, shown dimmed after the prompt ("Hold E: Lay an egg  ·  you can lay again in 12 s").
- Server change: republish (no new table or reducer).

## 0.39.2 — an authority sets anyone's character
- `set_character_of(entity_id, kind)` (DECISIONS #217): an authority (an admin, the world's sidecar) makes any entity any kind, playable or not: the sidecar making a bot the wolf, and a game whose players start as something else (Fowl Play's hens) handing the foundation's own suite a plain player in its `integration_init` hook.
- Server change: republish (a new reducer; additive).

## 0.39.3 — three foundation checks that only passed by luck
Found running the foundation's integration suite inside Fowl Play (its nests are ten more entities):
- **The interact check took the wrong resource node**: it picked "the last row" of a query for the node it had just spawned, and the server does not promise row order (with Fowl Play's entities it returned the far node, so "in range" was refused). Every such pick (seven) now takes the highest id, which is the newest.
- **The timed press's verdict was flaky**: it recomputed each press's quality from the marker and target the log prints to three places, which over a 0.1 half-width moves a quality by up to 0.005; the tolerance was 0.002. Now 0.011. Its "scored their mean" check, from those rounded qualities, now allows the mean to round either way (one point).
- **The content suite's hand-edit check edited nothing** in a game with a genre's content: it changed an ability's `damage` in the first baked file, which in Fowl Play is the hens' `character.json`. It now changes the file whatever it holds.
- No server change.

## 0.39.4 — the splash's ripples, checked in a game that wants them
- The match suite asserted the splash shows no water ripples, which fails in any game whose splash asks for them (Fishing's does). It now checks they show exactly when the game's splash asks, and that the default does not. Found running Fishing's suites on 0.39 (they had not run since 0.37). No server change.

## 0.39.5 — in front of the character, not the camera; people of any kind; a new match from the Rules page
From Luke's first try of Fowl Play (DECISIONS #221):
- **What is in front of the character is in front of its BODY.** The front arc read the input's heading, which follows the camera even standing still, so in third person you still had to aim the camera at a nest the hen already faced. It reads the body's heading now, which turns to the camera only while moving or aiming. The remote playtest faced the downed walker the old way (camera only): it now turns the body, and checks the camera alone offers nothing.
- **A person is a person whatever kind they play.** The front arc offered anything not kind 0 or 1 as a thing to use, so a hen beside a nest (kind 100) could be the target instead of the nest. A person is now a foundation person kind, a playable character, or anyone with a player row; the lobby, the Rules page's Go to and the net overlay find players by their player row, not kind 0.
- **Play as whenever the server would take it**: in the lobby phase (between rounds too, not only before a match's first round), or any time for an admin. Luke came back to the lobby screen after a round and had no way to switch.
- **New match** on the Rules page (admin): everyone back to the lobby, the rounds from 1; a game resets what it keeps per match (Fowl Play: its nests).
- **A new match resets PEOPLE's statuses, not things'** (DECISIONS #222). It reset every entity's, so Fowl Play's nests (whose stage is their status) were left in no stage after a new match began, and nothing could be done to them: no "Sit on the nest". A person is a player, a brained NPC, a foundation people kind or a playable character; a game resets its things when it means to (`on_match_began`).
- **First person** (DECISIONS #223): your own model is not drawn for you (its shadow is), and your body faces where you look, standing still too. The wolf's own greybox sat in front of the camera, and the view swung while the body stayed put until it moved.
- The integration suite has an end hook (`integration_end`), for a genre's checks that end a match.
- **Two integration checks raced the CLI**, which now takes a second or more a call on this machine: Help up ran at a tenth of its pace so the CLI could look at it mid-way, and a run of slow calls finished it first; the status grace was entered three reads before the step it covers. Help up now runs at a fiftieth (its rates compared within 5 %), and the reads come before the grace begins.
- Server change: republish (who a new match resets; no table changed).

## 0.39.6 — the hold checks, at a pace the rule allows
- 0.39.5 slowed the integration suite's Help up to a fiftieth of its pace so slow CLI calls could not finish it, but `foundation.hold_speed`'s least is a twentieth, so the server refused it and the hold ran at full speed (the checks failed the same way as before). It runs at a twentieth now, its rates compared at that pace. Fowl Play's nest checks hold the nest's cooling off while a raid is measured. Test-only: no game change, nothing to republish.

## 0.39.7 — the hen's frame rate: holds and statuses kept loaded
- **Holds and statuses are kept loaded while the game runs** (DECISIONS #224). `HoldDef.find` loaded each hold from its path, and once nothing else held one, Godot's cache let it go: the next lookup read the .tres and what it links from disk again, 1.07 ms a call in Luke's profiler (a few microseconds kept). The front arc asks it for every entity in reach every physics frame, and the prompt every frame, so a hen beside a nest with the wolf near fell to 10-20 fps. `StatusDef.find` did the same. Both keep what they load (the editor still reads afresh); `AppExit` lets them go on quitting.
- No server change: nothing to republish.

## 0.39.8 — the hold prompt says what just happened
- **A genre's note while the player holds** (DECISIONS #225). `HoldPrompt.add_note` was asked only while a hold was offered (why the server would refuse it, dimmed); it is now asked while one is held too, and shown after it in the hold's own colour: what just happened to it ("Sit on the nest  ·  an egg cracked: -8 % warmth"). Luke missed a crack in a playtest: the warmth was taken, but nothing on his prompt said so.
- **The bar flashes red when it goes back** at once by 1 % or more (a raid, a missed check); a slow undoing (a rate) does not. `HoldPrompt.is_flashing()`.
- No server change: nothing to republish.

## 0.40.0 — milestone 5: abilities judged by a referee, lag-compensated
- **A referee judges an ability its content marks `judged`** (DECISIONS #226, FOUNDATION_SYSTEMS milestone 5, OPEN_ITEMS A1). `use_ability` queues it (`action_request`, readable only by the world's authority) instead of resolving it; the world's referee, a sidecar, judges it as it lands (its wind-up after the press): the user where it was then, everyone else where the user SAW them (rewound by the client's view delay, capped by the new hot rule `foundation.rewind_max_ms`, 150 ms, favouring the attacker), a ball of the ability's radius swept along its reach against the level's walls (a fence stops it; a hen through a gap it cannot fit is safe; nobody is hit through a wall) and each person's body (their character's `collision_radius`/`collision_height`). It answers `resolve_action(request, hit)`; a hit hurts (a hold a hurt stops is let go of), then is the genre's (`on_ability_hit`) or the ability's damage; a miss is the genre's (`on_ability_missed`). Every client sees the `action_event` as before. A request nobody answers in 3 s past its landing is a miss; with no referee online a judged ability is refused ("no referee").
- **The proof, as the plan put it:** a pounce whose user saw a hen 100 ms before she was through a gap hits her though she was through by the time it landed; one that saw her 50 ms after misses; the rewind is what decides (the referee suite, against real physics).
- **A sidecar's jobs, per world.** `--referee` makes the sidecar judge only (players move themselves, a MODULE world: it builds no entities, `EntitySpawner.spawning`); a SIDECAR world's sidecar judges as well as moves everyone. It follows the world's level (`world_level`), as a client does.
- **Starting one is automatic in an editor run.** When the admin presses Play, the game has a judged ability and the world has no referee, `RefereeLauncher` offers a one-time code (`offer_referee`, admin) and starts the project's sidecar headless with it (`--referee --claim=<code> --parent-pid=<the game>`); the sidecar presents it (`claim_referee`) and is registered for the world, and quits when the game does.
- **Clients say how far behind they see** (`use_ability_seen`: the interpolation delay and half the round trip; `SpaceTimeActionComponent.view_delay_ms`). `use_ability` stays for older clients (judged as things are).
- **The left mouse button** (`attack`) uses the character's first ability, ahead the way it faces (`LocalInputComponent.use_first_ability`). An authority's NPCs: `use_ability_as`.
- **`withdraw_challenge`** (DECISIONS #227): a genre ends its own check before its time, when it no longer means anything (Fowl Play's hard egg, laid or let go of before its press), so it does not stay up and take the player's next press of E.
- **`StatusDef.hittable`**: downed and carried are not (a pounce passes over a downed player; a teammate can still help them up).
- **Abilities follow the build.** The `ability_def` rows were seeded once, at `init`: a world made before an ability was added never had it, and an edited cooldown waited for `--fresh`. Every connection now brings the content's abilities up to date (an admin's `define_ability` of another id is left alone).
- **Foundation checks that hold in any game:** the injured burst is read from the game's own Injured (a genre may replace it: Fowl Play's hen bursts 1.3x); a player in no status is normal with or without a row. The match suite no longer leaks a splash screen (an orphan from 0.39.4's ripple check: the run's only unexpected engine error).
- New tables (`action_request`, public behind its filter; `referee_offer`, private) and reducers (`use_ability_seen`, `use_ability_as`, `resolve_action`, `offer_referee`, `claim_referee`): **republish with `--codegen`** (keeps data). Old clients keep working (they call `use_ability`).

## 0.40.1 — the referee stays while its game does; a lunge slides along a wall it grazes
- **The referee an editor run starts no longer quits at once** (DECISIONS #226). It asked every second whether the game that started it was still running, by process id, and on Windows Godot can only ask that of processes it started itself: the answer was always "gone". Each referee claimed the world and quit a second later; the game started another 30 s on, and pounces in between were refused ("no referee"), so Luke saw *Pounce!* and never a hit or a miss. The game now touches a file in its user folder every second (`RefereeLauncher.touch_alive`), and the referee stops when it goes stale or is removed (`is_alive`, 6 s; at once on a clean exit).
- **A lunge slides along a wall it grazes** (`LungeJudge.path`), as a lunge does; a wall met head on still stops it (a gap's posts, a fence), and nobody is hit through one. Luke, by a hay bale and angled a little into it: the sweep caught its corner and stopped 0.1-0.3 m out (his referee's log), so a hen right there was missed. The referee suite has his case (it fails with the slide taken out: 0.19 m of 1.4).
- The launch playtest now checks the referee is still online 12 s after it claimed, and that no second one was started (it passed before with the referee already gone); it fails with the old check put back.
- No server change: nothing to republish.

## 0.41.0 — milestone 6: attach and carry
- **One entity carried by another** (DECISIONS #228, FOUNDATION_SYSTEMS milestone 6, OPEN_ITEMS C1): a new public table `attachment` (who is carried, by whom, since when, the status it had). A genre calls `attach(entity, carrier, socket)` and `detach(entity, at, status)` from its rules (Fowl Play: pick a downed hen up, stash her); an authority has `attach_as` / `detach_as`. Carried, an entity is CARRIED (cannot move, act, or be hit), lets go of what it held, and the module keeps it at its carrier every tick, dropping what its own client claims (its frames are consumed, so its client keeps up). Put down, it stands where the genre says (else at its carrier's feet) in the status the genre says (else the one it had), by a teleport every client takes at once. A carrier that leaves or is despawned puts down what it carried where it was.
- **Every client draws it at its carrier's carry point** (`CarryComponent`, on every entity as its status is): `EntityDefinition.carry_offset` (from the carrier's feet, in its own terms) and `carry_yaw_deg`, every frame after movement, so it rides smoothly, its own player's camera with it, late joiners included.
- **`Genre::may_use_ability`**: a genre refuses a use with a reason (Fowl Play: a predator carrying a hen does not pounce).
- **Not yet:** a world a sidecar moves (SIDECAR) would still simulate a carried entity by its own frames; that part waits for a SIDECAR game that carries.
- New table `attachment` and reducers (`attach_as`, `detach_as`): **republish with `--codegen`** (keeps data). Old clients keep working (they draw a carried entity where its row puts it: at its carrier, 20 times a second).

## 0.41.1 — a sidecar is not a player; a hold is offered only within its own reach
- **A sidecar gets no player** (Luke saw a stranger standing at the spawn: his referee). It connects as anyone does before it is registered, and a first connection made it a player (an entity, online, in every world view). Registering it (`claim_referee`, `register_authority` as a sidecar) takes that player away, and a registered sidecar's connection makes none.
- **A hold is offered only as near as the server takes it** (`InteractionComponent.reach_for`): its own reach (`HoldDef.range_m`), not the 3 m any use reaches. Luke's wolf was offered a larder's Stash at 2.9 m of its 2.2, and refused. Both the in-front targeting and the crosshair.
- No table changed: republish (keeps data), no codegen.

## 0.42.0 — a limited turn at speed (OPEN_ITEMS A2); walls an entity puts up; a genre puts an entity somewhere
- **Turning at speed** (OPEN_ITEMS A2, for Fowl Play's chase): a movement profile's `turn_rate_full` (degrees a second at run speed), `turn_rate_slow` (at and under `turn_slow_speed`) swing a heavy body's run round instead of turning it at once, and it slows while it points away from where it is told to go (`MovementModel.turn_toward`). The look is never clamped: the overshoot is the body's. 0 (every character until it says otherwise) turns at once, exactly as before. Golden vectors `shared/golden/movement/turn_rate.json` (NumPy float32, `max_err = 0`).
- **A wall an entity puts up** (DECISIONS #229): a character's `blocker_size`/`blocker_offset`/`blocks_in` make its entity a box on the level's layer while it is in one of those statuses (a gate while shut; empty: always, a solid haystack). Every client builds it (`EntityBlocker`), so bodies stop at it as at a fence; the referee builds its own where the entity stands, so a pounce stops at it too; aimed at, it is its entity (the crosshair on a shut gate targets the gate).
- **`place_entity(ctx, id, pos, yaw)`**: a genre puts an entity somewhere at once (a vault over a fence, a hen into a hiding place), as a teleport that moves its correction epoch on (frames its client sent from the old place move nothing). The dev tool `teleport` uses it.
- The native `status` test reads the statuses a game has (a game may replace Downed and Injured with its own: Fowl Play's failed it).
- No table changed: republish (keeps data), no codegen. A movement profile's three new numbers default to 0 (no limit), so every old profile moves as it did.

## 0.43.0 — milestone 7: bots, driven by the world's referee
- **A bot** (DECISIONS #230): an NPC that is a session member and has an `npc_brain` row naming its brain. `add_bot_internal(ctx, sess, kind, brain, pos)` for a genre (Fowl Play fills a night), `remove_bots_internal`, `is_bot`, `bots_of`; the admin reducers `add_bot` and `remove_bots` (a test, or a designer filling a lobby by hand). A bot is despawned with every row of it.
- **The referee drives the bots** of a MODULE world: started `--referee`, it builds only entities with a brain row and no player (`EntitySpawner.spawn_filter`; `spawn_now` when the brain row comes after the entity, `release` when it goes) and runs each one's brain through the same movement model and the level's walls, writing where it went as a sidecar does. Players still move themselves.
- **Brains do things**: `hold(target, verb)`, `let_go()`, `use_ability(id, aim, target)` from `think`, sent as the authority's reducers (`begin_interact_as`, `end_interact_as`, `use_ability_as`), judged as a player's are. **Brains go round things**: `go_to(p, me, world)` walks a path its body fits, from a walk map baked from the level's collision per body size (`NpcNav`: a hen is routed under a hedge's low hole a wolf is not). **A genre's brains** are found by name at `res://sidecar/npc/brains/<name>.gd` (`chicken/hen`); the foundation adds `stand`. The world view a brain thinks with now has everyone (the rows of those it does not simulate), their statuses, and who is a player.
- Tested: the `bots` suite (the filter, brains by name, the acts, a route walked, the walk map round and under a hedge), the integration suite (a real referee drives a wandering bot in a MODULE world, builds nobody else, lets it go when it leaves).
- Two reducers added (`add_bot`, `remove_bots`): republish with codegen (keeps data). Milestone 8 (a world per match) is not built: one world plays one match at a time.

## 0.43.1 — a bot's input waits for its own
- `LocalInputComponent` samples only once it is bound as its player's own: a bot (built by a referee from the same scene) waited on its rows sampling a keyboard nobody has, and logged an error a frame for two seconds.
- No table or reducer changed: republish (keeps data).

## 0.44.0 — what a world hears, slow places, lunges, comfort, and a recording of every round
- **Slow places** (DECISIONS #231): `LevelSpeedZone`, a box in a level (layer 4, "zones") whose `speed` scales the pace of a body whose feet are in it, on top of its status. Read where a body is stepped, so a player's prediction and a referee driving a bot agree. Client-trusted (the server bounds by kind and status). Fowl Play's hedge holes are crawls.
- **Lunges** (DECISIONS #232): an ability whose content `lunges` throws its user forward by its movement profile's dash as the wind-up ends (`LocalInputComponent.dash_once`; a referee's bot likewise); a character with one dashes only so. The ability row's data says `"lunges": true`. Others see an ability start (`SpaceTimeActionComponent.started_elsewhere`, from its cooldown row) and play its clip. `CameraRig.offset`: where a genre moves the view (a vault's arc, a pounce's crouch).
- **Noises and pings** (DECISIONS #233): a `noise` row (public, per world, gone after 10 s) is something a world hears; `make_noise` for a genre's rules; the `ping` reducer for a player (kind 1, within 80 m, about what they point at, at the `ping` rate in `shared/rules.json`). What each kind sounds like, how far it carries and who is shown a marker is content (`NoiseDef`, `content/noise/`; a genre gives a character its own sound for a kind with `made_by`). `NoiseFeedback` (in the HUD) plays them where they were made, draws the markers (pointing from the screen's edge when off screen), says `SignalBus.noise_heard`, and sends a ping where the player looks (the `ping` action; a genre's words for what was pointed at: `NoiseFeedback.callout`).
- **First-person comfort** (DECISIONS #234): the Video setting Field of view (each character's own, wider or narrower), and under Game: Head bob in first person (off by default) and Third person while carrying (on): a rig's `while_carrying` is the view while its entity carries someone.
- **A recording of every round** (DECISIONS #235): every sidecar (a referee too) writes each round of its world to `user://recordings/` (`SessionRecorder`: ten frames a second of where everyone was, and what happened: statuses, uses, holds done, noises, phases, the standings; the newest 60 kept; `--no-record` turns it off). `tools/replay/replay_viewer.tscn` (F6) plays the newest back over its level: a timeline, speeds, the events, and where people were hurt.
- Tested: the `zones`, `noise` and `record` suites, the `action` suite's lunge, the `camera` suite's comfort, the integration suite's pings (range, target, rate, gone after a while, not while out).
- Tables added (`noise`) and a reducer (`ping`): republish with codegen (keeps data). Fowl Play's step 6 is built on these.

## 0.45.0 — gliding and flying, abilities on their own keys, friendly collision, bots that call their genre
- **Glide and hover in the movement model** (DECISIONS #236): `glide_fall_speed` (airborne, holding jump after a flap, a body falls no faster than it) and `hover_height`/`hover_climb` (a body held at a height, flying there, neither jumping nor falling); both 0 by default, so nothing moved before moves differently. A status may put a body on the wing (`StatusDef.hover_height`). Golden vectors: `glide_hover_*.json` (NumPy float32 mirror, max_err 0).
- **Abilities on their own keys** (DECISIONS #237): `AbilityDef.key`, an input action (`power`: the right mouse button); the attack key uses a character's first ability with no key of its own. A genre hears every use (`on_ability_used`, a judged one as it is queued), not only a judged one's hit or miss.
- **Friendly collision** (DECISIONS #238): `EntityDefinition.kin_layer`, a layer a character's bodies share; solid to each other while the hot rule `foundation.friendly_collision` is on (off by default: the Rules page turns it on).
- **A bot calls its genre's reducers** (DECISIONS #239): `NpcBrain.call_as(reducer, args, types)`, sent as the bot (a hen coming out of hiding, wiggling free).
- **Ground that makes its own collision** (DECISIONS #240): the bots' walk maps take the faces of any level node that gives them (`generate_nav_mesh_source_geometry`: Terrain3D).
- Tested: the `golden`, `status`, `action`, `bots` and `entity` suites. No table changed; Fowl Play's own tables did.

## 0.45.1 — a sweep begun against a wall
- **A referee's sweep with its back to a wall goes its whole way** (`LungeJudge`): a ball cast from touching a wall it moves away from was stopped where it stood (a box) or a couple of metres on in the open (a mesh's faces, the farm's CSG): Fowl Play's egg thrown by a hen backed onto a hay stack went 2.3 m of 9 and missed the wolf (Luke's playtest of step 7). Set off the wall by `CONTACT_SLOP_M` (2 cm) before it is cast.
- Tested: the `referee` suite (a throw with its back to a bale: 0 m before, 9 after); Fowl Play's `walk` suite (the farm's own stack).

## 0.46.0 — a genre walks the player; anything a brain drives can be hit
- **A genre walks the player** (DECISIONS #241): `LocalInputComponent.force_move(dir, seconds)`, its stick pushed a world direction for a while whatever keys are held, without jumping (`is_forced()`). Frames as the player's own, bounded by the server as any. Fowl Play: a hen slipping off a roof no predator can reach her on.
- **The referee hits what the module would** (DECISIONS #242): anything a brain drives (an `npc_brain` row) is a person to `ActionReferee.may_be_hit`, as it always was to the module's `is_person`; before, a genre's brain-driven NPC of no playable kind was hit by the server's rules but never proposed by the referee (Fowl Play's decoy hens).
- Tested: the `action` suite (walked two frames, then the keys again; a zero direction walks nowhere) and the `referee` suite (a genre NPC: a thing without a brain, a person with one).

## 0.46.1 — the Mac app
- **A Mac client** (DECISIONS #243): the "macOS Client" preset, one app for Intel and Apple Silicon (universal), signed ad hoc so an M1 opens it (right-click, Open, the first time). `tools/mac_export.sh` exports it as each game's own app (its bundle identifier `com.umf.<title>`, from `shared/game.json`); `tools/release.sh` zips it beside the Windows build (`<game>-<version>-mac.zip`). A Mac build is a player only: the host's PC still runs the server and the referee.
- Projects import textures for Apple Silicon too (`rendering/textures/vram_compression/import_etc2_astc`): the Mac export needs them.
- The export presets leave out `demo/` (an add-on's demo folder unpacked beside the project: LimboAI's put 150 files into Fowl Play's builds).
- Tested: `tests/export_test.sh` exports the Mac app too and checks it from Windows (`tools/mac_bundle.py`): universal, signed, this game's own bundle identifier and name, the preset left as it was, a pack with no sidecar, tests, tools or editor tooling but the runtime files and the level, and the Mac library of every GDExtension the game uses (Terrain3D's hidden: caught). It cannot run the app: a Mac does.

## 0.46.2 — opening the Mac app; CI by hand
- **Opening the Mac app the first time** (Luke, on his M1: "could not verify it is free of malware"): macOS 15 and later no longer let right-click > Open pass an app signed ad hoc. The handbook, `tools/release.sh` and `tools/mac_export.sh` now say System Settings > Privacy & Security > Open Anyway, or `xattr -dr com.apple.quarantine` on the app. The build is unchanged; a developer ID and notarization (for selling) is what makes the message go away.
- **CI runs only by hand** (Luke: an email that it failed on every ship): `.github/workflows/ci.yml` is `workflow_dispatch` only until it has passed on GitHub once; the suites run before every ship are the gate.

## 0.46.3 — hosting without the editor
- **`tools\host.cmd`** (`tools/host.sh`): hosts a game for players on other machines with no editor open (Luke, playing on his Mac across town: the bot hens stood still and the wolf never came, because only an editor run starts the world's referee). It starts SpacetimeDB listening for other machines if it is not running (and refuses one listening only on this PC), offers the world a referee code and runs the referee, starts it again if it stops, and stops it when its window closes. Logs in `build/host/`.
- The handbook's "Playing with a friend": host with it; the Windows Firewall rule by port (SpacetimeDB's own rules name one version's exe and one network profile); a reserved address for a port forward; checking from the friend's machine.
- Tested: Fowl Play's `game/chicken/tests/host_playtest.sh` (a night nobody hosts: its wolf stands; hosted: every bot driven, the wolf hunting; the referee killed: back; the host closed: its referee gone).

## 0.46.4 — the server's clock from old stamps
- **ClockSync takes the server's clock from stamps old and new** (Luke, on his Mac against a database kept for days: a night's clock read 5000 minutes, a larder's tens of thousands of seconds, and he could not lay an egg). A row's `server_ts` is when it was WRITTEN: a nest or a gate keeps the day it was placed, and a subscription may hand one over first. Taken as "now", the estimate started days behind, and the clamped EMA (50 ms a sample) would never have caught up. Now a stamp more than a second ahead of the estimate puts it there at once (the server is never earlier than what it sent), one more than a second behind it is ignored (an old row's), and between, the clamped EMA as before. Every countdown, hold bar, skill check and cooldown reads this clock.
- Tested: the `press` suite (a stamp three days old first: days behind; the next fresh one: right at once; an old one after: nothing; jitter: a little). The old code fails it 259 200 s off.

## 0.47.0 — how it ran, what they said, what the bots decided
- **Telemetry** (DECISIONS #244): every player's game and every referee reports to the host how it ran, once a window (`foundation.telemetry_window_s`, 30 s): frame times (median, 95th, 99th, worst), each spike with its moment (a slow frame over `foundation.telemetry_spike_ms`, or a network stall), ping, corrections, memory, entities, the machine coarsely. One small call (`report_perf`), private tables, nothing personal (`Telemetry`, made by `SpaceTimeSync`).
- **Feedback** (F8, or Send feedback in the Escape menu, `FeedbackPage`): the moment marked as the key is pressed, then Bug/Lag/Idea/Other and their words; the server adds who, where, the level, the round and the phase (`send_feedback`). `tools\host.cmd` shows each as it arrives, with a bell; `toolseedback.cmd` lists them, with how their game was running and the recording's second to watch, and performance per player and referee.
- **The recordings write what each bot decided** (`"ev": "brain"`: its step as it changes, its goal as it jumps), and `tools/replay/analyze.py` sums a round up per bot: straightness, reversals, time in each step, flip-flops.
- Tested: the `telemetry` suite (a window summed up, spikes and stalls, a small report with nothing personal, the feedback page marking the moment and holding the player still), the `record` suite (a bot's decisions), `cargo test` (`telemetry.rs`: lengths, numbers, the moment noticed), the integration suite (who may report, the rate, what the server adds, private tables, the log), the end-to-end test (a real client's reports reach the host).

## 0.48.0 — bots' behaviour trees in the template
- **LimboAI moves into the template** (DECISIONS #245; Luke: "most games will have AI"): `addons/limboai` (v1.8.1, Windows, Linux and macOS libraries; the others ignored, as Fowl Play had it), and the glue Fowl Play's bots had: `NpcBrain.run_tree(path, me, world)` steps a `BehaviorTree` from `think` (its blackboard: `brain`, `me`, `world`), `NpcBrain.tree_status()`, and `BrainTask` (`sidecar/npc/brain_task.gd`), the task a genre's tasks extend. A brain's `clock` and `now_ms()` are the foundation's now, so any brain's test can walk its time.
- Chosen over Beehave (GDScript only, no library) and hand-written state machines: Fowl Play's trees are built on it, and its editor tab and debugger are a designer's (DECISIONS #245).
- Tested: the `bots` suite (a tree from a file reaches its brain with this think's me and world, the step's time from the brain's clock, another tree in its place, the tree's agent freed with its brain).

## 0.49.0 — bodies the referee moves (milestone 13)
- **A thrown thing is an entity the world's referee flies** (DECISIONS #246; DiscGolf's discs first): kind 3, a `movement_state` row like anyone's and a `body_state` side row (its def, owner, the thrower's launch number, turn, spin, at rest, frames since launch). What a body is is content, `BodyDef` (shape, mass, bounce, friction, drag in the air and on the ground, gravity, who may throw it and how hard, how many, how long it lasts, its look, its `BodyForces`: a genre's flight), with a bench (`tools/workbench/body_workbench.tscn`). The foundation's own is a ball.
- **Throwing**: `launch_body` (a player's throw, bounded by the body's speed, spin and reach, with a referee online, at the `launch_body` rate, the genre's `may_launch`; over `max_per_owner` the oldest goes) and `launch_body_internal` (a genre's own). Genre hooks: `may_launch`, `on_body_launched`, `on_body_contact`, `on_body_rest`.
- **The referee flies them** (`sidecar/physics/body_referee.gd`, in both of a sidecar's jobs): a `FlyingBody` (`foundation/physics/`) per body against the level, the other bodies and a stand-in for each person; `write_body_batch` once a server tick (its frames since launch as the rows' seq, so every client's timeline is the referee's own 60 Hz); hits faster than the def's contact speed reported to everyone (`report_body_contacts`, `body_contact` rows for 5 s); a body the server moves taken from its row. The module never moves a body.
- **The thrower sees it leave the hand at once** (`BodyLaunch`): their game flies its own `FlyingBody` from the click; its `BodyComponent` takes the flight over and keeps it near the referee's, row by row at the same frame (`foundation.body_correct_share`, `foundation.body_snap_m`), and glides to the referee's resting place. Everyone else interpolates the rows; the turn is drawn at the same moment as the place (`SpaceTimeMovementComponent.get_render_seq`).
- Found by its tests: Godot reports only the contacts still there after a step, so a fast hit (a ball into a person) is found by casting the body's shape along each frame's motion; Godot has no rolling resistance, so a body has a `ground_drag` while it touches something.
- Its playtest's findings: **a new entity binds the moment its rows are in** (DECISIONS #247: rows that came just after its `entity` row used to wait out the 2 s bind timeout, for every entity); a body's watchers place its rows by when the server wrote them and guess ahead at most 25 ms (it bounces); a body passes through its own thrower for its first half second. At 150 ms the thrower's flight and the referee's agree on every row; a watcher's worst step a frame is 0.46 m.
- The greybox game: **G throws the ball** where you look (hold for harder). An editor run starts the referee for a game with bodies (a genre's, or the ball with no genre).
- **The suites leave nothing alive at exit**: the `noise` suite's stray node freed, and `tests/run_tests.sh` now fails a run that leaks one.
- Tested: `cargo test` (`body.rs`: a throw's bounds, the oldest going, lifetimes), the `bodies` suite (content, a real flight to rest, forces, shift and place, the referee's writes and hits on a person's stand-in, the thrower's correction, `BodyLaunch`, the turn, the bench), the integration suite's bodies section (every refusal, the limit, the module not moving it, the referee's writes and contacts, cleanup), and `tests/bodies_playtest.sh` (a real referee, a thrower and a watcher at 150 ms).

## 0.50.0 — the flight cam (milestone 14), aim and charge
- **A camera watches what is not its player** (DECISIONS #248): `CameraRig.watch(node, FollowCamConfig)` goes behind it along where it is going, above it, trailing it, looking at it, and glides back to the player's own view when it stops (`return_s`); the player's look is untouched meanwhile. `FlightCam` follows a throw from the hand, through its body taking the flight over, to its rest, holds there a moment and comes back, at once if the player runs; `follow_body` watches anyone's (spectating). Settings, Game: "Follow what you throw" (on).
- **Aim and charge** (DECISIONS #249): `ChargeMeter` (fills in its time, overcharged past its mark, holds or bounces at the top); `AimCharge`, the input a genre adds (each key a style; while held the body faces the aim and the mouse's up and down sets a release angle, the view's tilt held: `LocalInputComponent.borrow_mouse_y`; let go: `released(style, power, over, aim, angle)`; another style, a cancel or Escape puts it down); `ChargeBar` draws it.
- The greybox game: **hold G** to charge the ball, let go to throw it; the bar shows the charge, mouse up and down spins it, the camera follows it.
- Tested: the `aim` suite (the meter, the lent mouse, a charge thrown and put down, the camera watching and coming back, the flight cam, the bar), and `tests/bodies_playtest.sh` (the flight cam on a real throw with a real referee at 150 ms).

## 0.51.0 — the server pushes people (milestone 15, pushes); a level change keeps its players
- **A genre pushes a person or a body** (DECISIONS #251): `push_entity(entity, vel, by)` writes a `push` row (public, per world, gone after 5 s). The pushed player's own client applies it inside its prediction at its next frame (by the frame's number, so a correction's replay pushes again) and carries its sideways speed a while; the module widens that player's Tier A bound by the push while it lasts (`foundation.push_grace_s` for lag); the world's referee pushes a body (woken if at rest).
- `dev_push` (the dev tools), for tests. The `push` table is a core, per-world table: every game runs `tools/publish.sh --codegen` after this.
- Tested: `server/tests/push.rs`, the `prediction` suite (a push flies, and a replay is the same flight), the integration suite (gated, clamped, nobody refused), `tests/bodies_playtest.sh` (a pushed player uncorrected at 150 ms; a ball at rest pushed on).
- **A level change keeps every entity receiving its rows** (DECISIONS #250): `LevelLoader` registers each entity it moves into the new level again (leaving the tree had unregistered it, so the local player stopped following the server); `LocalInputComponent` takes the cursor back as it enters the tree again; `BodyComponent` frees its flight only when deleted, not when moved.
- Found by DiscGolf's three-hole race playtest. Tested: the `levels` suite (a registered entity moved with the level is still registered; it fails without the fix).
- The integration suite's timed checks hold on a busy machine (the press acknowledged straight after its issue, the referee's waiting request read once).

## 0.51.1 — the referee keeps hearing its entities after a level change
- **The referee's world, its level changed, keeps the entities it moved registered** (DECISIONS #253): `SimWorld.show_level` and `LevelLoader` move entities through one call, `EntitySpawner.move_entities_to(root)`, which registers each moved entity again (#250 had fixed only the loader). Before, the referee stopped hearing its bots after a level change: the server's move to the next hole's tee never reached them, so they walked back from where they were, and fell for ever where the new level had no ground. Found by DiscGolf's nine-hole round ("the bots dropped off half way through"). Tested: the `levels` suite, and DiscGolf's nine-hole bots run.
- **A place the server put someone is not undone by their authority's last write** (DECISIONS #252): `write_movement_batch` drops a sidecar's write that lands within a second of a server teleport, more than 1.5 m from it and not the sidecar's own teleport (`crate::placed::stale`). No wire change. Tested: `server/tests/placed.rs`.

## 0.51.2 — a body forgets a stand-in that went
- `FlyingBody` skips a collision exception freed since (a referee's stand-in for someone who left, or who became untouchable: DiscGolf's finished golfer); before, its contact cast called `get_rid` on null every frame. Found by DiscGolf's bots playtest.

## Between 0.51.2 and 1.0.0 — what Regent's Rule and the friends' playtests asked for
Shipped to the games as they were made (DECISIONS #258-#277): a replay frame may hold one dash, a
correction keeps the client's bookkeeping; the grip preview's quick way, its file written on save, spin,
named animations and per-body grips; one look for every screen (`UiStyle`, `UiWindow`, `UiSlot`), item
grades as colours, icons drawn from the models; held upper-body poses; loot tables rolled per
contributing player with pity, items on the ground (yours, then anyone's, then gone), resources that
fill by themselves, traits that trade; no referee runs old code, the editor is an admin, a tool is not a
person; chat; a held jump hops again only once it has stopped rising; the chronicle and the telemetry
page; a loop a clip does not have is its node's.

## 1.0.0 — the world in cells, a streamed level, accounts (a reshape: every game's database wiped once)
The plan, agreed with Luke on 2026-10-23: `docs/TEMPLATE_1_0.md` (DECISIONS #278-#281). The first major
version: tables changed shape, so builds from before it are refused before connecting (`compat` 2) and
each game publishes `--fresh` once.
- **Cells**: every row of a placed thing carries its 64 m cell (`chunk`), kept right by
  `server/src/module/place.rs` (every movement write goes through it; a lint stops any other).
  `shared/rules.json` `cells` holds the numbers.
- **Ring interest** (`NetConfig.interest = RING`, Regent's Rule's): a client is sent the 3 x 3 cells round
  its player and its own rows, swapped as it walks. Every other game keeps `WORLD` and plays as before.
- **Streaming**: `LevelInfo.streamed` with a `Cells` node; the bake cuts it into a scene per cell and
  `LevelStreamer` loads the 5 x 5 round the player.
- **Accounts**: sign in through SpacetimeAuth (set up per game in `shared/game.json` `sign_in`; until
  then everyone is a guest, as before), an account per person on any machine, characters
  (`foundation.characters_per_account`), link codes, take-over, guests by `foundation.guests_allowed`,
  the connect screen's Sign in and the Escape menu's Account page.
- **Parking**: `foundation.park_offline_s` puts an offline character away and brings it back where it
  stood (0, the default: as before).
- `player` gains `left_at`, `connection_id`, `account_id`; `ground_item.owner_id` is indexed (#281).
- New suites: `tests/accounts_test.sh` (with the suites' own OIDC issuer, `tests/lib/oidc_issuer.py`),
  `tests/ring_test.sh`; unit `cells`, `streaming`, `accounts`; native `cell`.
- Taking it in a game: commit, pull, add `"compat": 2` to its own `shared/game.json` (that file is the
  game's and does not arrive with the pull), `tools\publish.cmd --fresh --codegen`, run its suites; its
  friends download the new build.

## 1.1.0 — runs well on weak computers (DECISIONS #282)
No schema change: a game takes it with a pull and a restart of the editor (`project.godot` gains a line).
- **The renderer, chosen with no command line.** `project.godot` `application/config/project_settings_override`
  names `user://renderer.cfg`, which the engine reads as it starts. Settings ▸ Video ▸ Renderer: Automatic
  (the default), Full (the game's own) or Compatibility, used from the next start (Restart now). Automatic
  picks Compatibility by itself on Intel's pre-Xe graphics (HD, UHD 6xx, Iris Plus) and, in a build, after a
  start that crashed; it restarts once and says why. A friend no longer needs `--rendering-method`.
- **Graphics quality** Low / Medium / High / Custom sets render scale, anti-aliasing, Shadows (now with
  Off), Lighting effects (Off, Reduced, Full), Detail and the frame cap together. High is the look the
  game always had; a fresh install on Compatibility or an old Intel GPU starts on Low.
- A level's effects and lights are turned DOWN from what it was made with, never past it
  (`GraphicsQuality`); designers mark extra detail with the groups `detail_high`, `detail_medium` and
  `detail_density` (a MultiMesh drawn at a quarter, half or all of its instances).
- Other characters are posed less often far away and off screen on Low and Medium (`AnimationRate`), and
  drawn to 80 / 150 m: skinning a crowd was most of a weak GPU's frame.
- Measured with `tools/perf/perf_bench.tscn` (60 characters, 1080p): Forward+ 5.8 ms a frame on High, 1.5
  on Low; Compatibility 5.4 on High, 1.2 on Low.
- New: unit suite `quality`; `tests/render_test.sh` checks the renderer switch, the self-restart and Low
  against High on both renderers; `tests/export_test.sh` checks the exported client reads the file.
- The accounts suite pins the foundation defaults it is written for (1 character, no parking): a game
  that overrides them (Regent's Rule: 3, 30 s) failed 6 of its checks (`511eee3`).

## 1.1.1 — the referee's two sides (DECISIONS #283)
No schema change: a game takes it with a pull (the content bake is in it).
- A hot flag `foundation.referee_two_sides` (off): on, a judged ability passes through its user's own side
  (the players, or everyone else) to the first person of the other. Regent's Rule turns it on (two skeletons were hitting
  each other); Fowl Play keeps it off.
- A character is posed the moment it is built (`AnimationDriverComponent`): since #282 its tree is advanced
  only by the driver, and a new one stood in its rest pose (a T-pose) until its first advance.
- Ring interest re-centres at once after a jump past the cells next to its centre (`Cells.recentre`): a player
  teleported or respawned onto a cell's edge (Regent's Rule's spawn) kept a ring hundreds of metres away.
- `PresenceComponent` asks again after a nameless player who is not yet known as an admin (the `authority`
  rows may come after the player's): a tool is hidden whichever comes first. Its `is_tool` is now
  `is_tool_row` (`PresenceComponent.is_tool` from outside called Godot's own `Script.is_tool()`).

## 1.2.0 — the load test (DECISIONS #284)
No schema change: a game takes it with a pull; nothing to republish.
- **`tests/load_test.sh`** (`tools\run.cmd tests\load_test.sh`, ~20 minutes): bot players in steps (50, 100,
  300: `shared/load.json`) on the TEST database, each a real guest connection walking cell to cell with the
  world's referee running, measured step by step until a limit breaks. Report in `build/load/ring/report.md`.
- **The bots** (`tools/load/`, Python standard library only): many in one process, asking exactly what the
  game's client asks for (`interest_dump.gd` writes out the game's own `InterestManager` queries), calling
  reducers by name from the module's own schema. What a game's bots do besides walking is its hook,
  `game/<genre>/load_bot.py`; its limits go in `shared/<genre>/load.json`.
- `InterestManager.cell_query` / `own_query`: the ring's two queries by name (the client and the bots share them).
- **Measured on this machine, the greybox** (`docs/load/2026-10-29_greybox.md`): the server keeps up at 300
  (movement tick p95 9.5 ms of its 50; 6000 `submit_input` calls a second queue 41 ms at p95); per player at
  300, 57 KB/s on the wire (gzip), 2000 rows a second, 55 others in view. **The referee breaks between 150 and
  200 bots** (frame p95 6.9 ms at 100, 76 at 200; stalls up to 2 s at 300): it is sent every bot's movement.
- New: `tests/load/test_load.py` (19 checks, no server); the suite's two negative runs.

## 1.2.1 — the load test plays on the game's own level
No schema change: a game takes it with a pull; nothing to republish.
- `shared/load.json` `"level"` (0, the greybox): the level world 0 is put on for the load test; a game sets its
  own in `shared/<genre>/load.json` (Regent's Rule's continent is 21). `tests/load_test.sh` always used 0.
- A game's bot hook may name the refusals that are play (`EXPECTED_REFUSALS`: counted apart, never judged),
  hear each call's answer (`on_result`) and read rows as the owner sees them (`bot.sql`, off the bots' loop).
  The owner's SQL is `wire.owner_sql`, shared with `load_test.py`. `tests/load/test_load.py` 20 checks.
- A judged ability refused because the referee dropped out ("nobody is judging world") is the game
  breaking, a limit (`referee_gone_refusals`, 0), no longer a harness failure that stopped the run.
- **A big level's walk map, a tile at a time** (DECISIONS #285): `NpcNav` bakes a level wider than 256 m in
  128 m tiles (half a tile round each) on first asking, and every walk map off the main thread. On Regent's
  Rule's continent the whole-level bake was refused by the engine (no foe could path) and stalled the referee.
  The bots suite's new 3 km level: tiled maps bake and route round a wall; baked whole, it fails.

## 1.2.2 — a referee is sent only what it reads (DECISIONS #286)
No schema change: a game takes it with a pull; nothing to republish.
- `--referee`: the sidecar subscribes `SidecarMain.referee_feed` (its own reads, its entity scenes' components'
  tables, each genre's `GenreModule.referee_tables`, the recorder's while it records) and never `input_queue`
  (80 % of its feed in Regent's Rule's load test; thin, the referee holds at 100 bots instead of 50).
- `GenreModule.referee_tables` (`*` by default: every one of the genre's tables, as before). A game trims it to what
  its brains read; reading a table not asked for is an error in the referee (`SpaceTimeSync.read_only`).
- `SpaceTimeComponent.also_reads()`: the tables a component looks up itself (SessionComponent: `session`,
  `session_match`; StatusComponent: `lobby_member`); a referee subscribes them. A genre's component that reads
  a table by `get_row` / `find_rows` lists it there.
- `sidecar_main.gd` is `class_name SidecarMain`. The referee suite's feed checks; `run_tests.sh` expects its one error.

## 1.3.0 — the brains' cost: one world view a think period, and NPC tiers (DECISIONS #287)
No schema change; four new hot rules, so a game republishes (no `--codegen`).
- `NpcWorldView.current` is shared for `SHARED_MS` (100) instead of one physics tick: the rebuild was the brains'
  whole cost at 300 players (286 ms a second of Regent's Rule's referee).
- NPC tiers: `foundation.npc_tiers` (off), `npc_awake_m` 200, `npc_dormant_m` 400, `npc_dormant_s` 30. On, an NPC
  alone sleeps (no think, no walk, no writes) until a player is near; `NpcBrainComponent.dormant`, `tier_changed`.
- Fixed: the brains' view never knew who was a player (`player` is keyed by identity, and it was looked up by
  entity id), so `NpcWorldView.players` was always empty; `SidecarMain.is_bot` had the same lookup.
- The npc suite's view and tier checks; the integration suite reads the referee's feed from its log (#286).

## 1.4.0 — region referees (DECISIONS #288)
A table and three reducers added: a game republishes with `--codegen` (data kept; older builds keep playing).
- `--region=x0,z0,x1,z1` (cell squares) `--border=1` `--hand-on=8` `--name=N`: a referee for part of a world, asking only
  for its cells (one query a column), running the NPCs and bodies there and judging its own people's swings.
- `npc_driver` and `drive_npcs`: the module gives each NPC (and body) to one referee at a time; `RegionKeeper`.
- `offer_region_referee`: one more referee for a world that has one.
- The load test: `shared/load.json` `referees` [columns, rows], `REFEREES=2x2`; `tests/regions_test.sh` (25 checks).
- A world with one referee is unchanged.

## 1.4.1 — the server's movement tick reads each world once a tick; the load test reads the server right (DECISIONS #289)
Code only: a game republishes (no `--codegen`; data kept).
- `tick_movement` reads what every row needs once a tick for the world (its inputs, kinds and statuses by
  the world's index; bodies, pushes, dash windows, corrections whole), takes a player's frames in one delete,
  and writes each row without looking it up again (`write_movement_over`); `write_movement_batch` likewise.
  `status_limits` and `push_limits` take the rows instead of looking them up.
- The load test counted every server call twice: SpacetimeDB times each as two transactions, the reducer
  and the subscription update after it. Now one call is one call, the update is its own column, the
  table is sorted by what each reducer cost the module a second (`busy ms/s`, exact, from the
  histograms' sums), and the report says how busy the module was. The p95s are bucket guesses (1, 5, 10,
  50 ms): the HANDBOOK says which numbers to read.

## 1.5.0 — a world's worth of bots: spread over a level, watched, joined, and how many referees (DECISIONS #290)
Code and tools only: a game republishes (no `--codegen`; data kept).
- `LevelInfo.bake_ground`: the bake also writes `<level>_ground.bin`, the ground's height over the whole grid,
  for tools (the server never reads it). Off by default: no level's bake changes.
- The load test's bots can live anywhere on a level's land (`shared/load.json` `"spread": {"over": "level"}`,
  `tools/load/level.py`): a share in a town round the spawn, each roaming near home, never into the sea, on
  the ground's height when baked. Region referees are then cut where the bots live, an equal share each.
- `LOAD=<name>`: a game's other load config (`shared/<genre>/load_<name>.json`).
- The server is judged by its exact numbers: `module_busy_pct` 80 and `tick_movement_mean_ms` 25 (the bucketed
  p95s are reported, not judged).
- Each referee's own row in the report (its region, frames, stalls and when, cores, memory), and what this
  machine's referees, bots and server took together. A referee prints its process (`[Sidecar] process N name`)
  and names itself in its reports (`Telemetry.who`).
- `WATCH=<s>` keeps the bots playing after the steps (0: until stopped); `PLAYER=1` opens the game on the test
  database to join them.
- `tests/referee_sweep.sh` (`tools/load/sweep_report.py`): the load test once per cut of the world, and the
  fewest referees that held with room (`build/load/sweep.md`).
- `GenreModule.cell_tables`: a genre's tables of placed things; a region referee asks for them by its cells
  (its config never had the game's `cell_tables`, so it was sent every one of those rows in the world).

## 1.5.1 — a ring's cells are asked for by their number alone (DECISIONS #291)
Code only: a game republishes (no `--codegen`; data kept).
- `InterestManager.cell_query` is `SELECT * FROM <table> WHERE chunk = N`: the server narrows a subscription
  by one `column = value` and not by `world_id = W AND chunk = N`. Measured on Regent's Rule's Skyrim-size
  world (300 bots spread out, each with cells of its own): the movement tick's subscription update 111 ms
  a tick with the world in the query, 19 ms without; a referee's write 55 ms, 7.
- Rows of another world in the same cell number are kept from the game where they arrive
  (`SpaceTimeSync.ring_world`, `ring_tables`); a row moving out of the world shown is a delete, into it an
  insert; our own entity's rows always pass. Moving to another world shows its rows from the cache at once
  (`show_ring_world`).
- The referee sweep's test no longer prints its tables into the unit run.

## 1.5.2 — a big world's idle rows cost the tick nothing; referees cut by their work (DECISIONS #292)
Code only: a game republishes (no `--codegen`; data kept).
- `tick_movement` passes a row standing on the ground with no frames and no teleport before any lookup, and
  looks an entity's kind up only for a row that moves (it read every entity of the world a tick; for every row
  without frames it asked whether a player drives it). Regent's Rule's Skyrim-size world has 12,000 such rows.
- The load test cuts region referees by players AND the NPCs the level places (`npc_kinds`, `npc_weight` in
  a game's load config): by players alone, one referee of four got half of a world's 660 skeletons.
- `EntityRegistry` says what it dropped (events for entities never built here) once a minute, not once an
  entity with a backtrace (a region referee printed thousands).

## 1.5.3 — a referee's walk maps one at a time, and its level's bounds found once (DECISIONS #293)
Sidecar code only: restart the referees (no republish).
- `NpcNav` bakes one tile at a time (`MAX_BAKES`), the rest queued, each read from the level only when its
  bake starts. Every awake camp asked at once before: on Regent's Rule's Skyrim-size world one of ~50 tiles
  finished in five minutes and each read held the main thread 178 ms.
- `NpcNav._bounds` (asked on every brain's every `ready` and `path`) searched every node of the level for its
  LevelInfo each time: 20,000 nodes there. It is found once a level.

## 1.5.4 — an idle NPC costs its referee nothing; a referee poses nobody (DECISIONS #294)
Code only (client and sidecar): restart the referees; a game republishes nothing.
- `push_authority_input` drops a still frame (no stick, jump, dash or aim) for a body at rest on the ground
  with nothing pushing it: the body is idle as one nobody drives, not stepped and not written. A brain sends a
  frame every physics tick, so every NPC standing still was stepped 60 times a second and written 20.
- `AnimationDriverComponent` builds its tree in a referee (a clip's length can be read) but never advances
  it: no pose decides anything (rule 11).
- `NpcWorldView` is indexed by kind (`by_kind`): a search for the nearest player looks at players, not every
  node and stone the referee holds (~3,000 in a region there); unchanged rows are not decoded again; statuses
  come from their own rows.
- Measured: With the world view below, four region referees on Regent's Rule's Skyrim-size world at 300 players: frame p95 145 to 24-27 ms, their memory flat at ~1 GB each (it had climbed ~5 MB a second each: a referee too far behind to apply what it was sent).

## 1.5.5 — a referee builds no animation trees
Code only: restart the referees.
- `AnimationDriverComponent` in a referee builds no tree at all (1.5.4 built it and never advanced it): a clip's
  length comes from the set (`shot_seconds`). ~70 MB less a referee with ~170 skeletons.

## 1.6.0 — Jolt Physics, every game (DECISIONS #295)
Project setting only: restart the editor (project.godot changed); no republish.
- `physics/3d/physics_engine = "Jolt Physics"` in the template's `project.godot` (DiscGolf already had it). The
  project had never named one, so it ran Godot's default physics. On Regent's Rule's Skyrim-size world, a region
  referee's frame in which its ~170 skeletons first moved took 15-65 s inside the default engine's step (scripts
  5-14 ms, navigation none, ~350 pairs), and the server dropped it for idle timeout. On Jolt: none.
- Client prediction and the referee both resolve with `move_and_slide` on the same engine, so they still agree;
  the movement golden vectors use no engine (the flat ground) and are unchanged.
- The bake raycasts the level's collision, so it now depends on Jolt's rays: the example level re-baked (152 of 1,156
  depth samples moved by 0.1 m at a rounding edge) and its probes regenerated. A game's level whose bake check
  fails after this pull: bake it again (LevelInfo's button) and regenerate its probes.
