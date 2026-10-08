# Phase 3 — Universal Entity Framework, Base Components, Foundation Additions

Prerequisite: Phase 2 harness passes on both sides (`cargo test --test golden`, `tests/run_tests.sh`) and the module publishes + codegen runs. Do Task 0 first; it fixes anything the harness finds.

Each task: one PR-sized unit, files listed, acceptance criteria testable headless. Order matters — later tasks reference earlier ones.

---

## Task 0 — Make Phase 2 real
**Files:** whatever breaks.
1. `cargo check` / `cargo test --test golden` in `server/`. Fix macro-generated method names if any differ from `docs.rs/spacetimedb/2.10.0`.
2. `spacetime build && spacetime publish umf --server local`.
3. Vendor SDK, enable plugin, codegen with alias `Umf`, move `SpacetimeDB` autoload to top.
4. `tests/run_tests.sh` passes. Both golden suites print `max_err=0.000e+00` on all 6 cases.
5. Run `boot.tscn`; console shows `connection: CONNECTED`, `world ready`, `local entity: <id>`.
**Accept:** all of the above; commit `spacetime_bindings/`, `plugin_config.tres`, `project.godot`.

## Task 1 — Schema additions (do before any client component)
**Files:** `server/src/lib.rs`, `server/src/sim.rs`, `foundation/sim/input_frame.gd`, `shared/golden/GENERATE.md`, `shared/golden/gravity_only.json`
- Add `world_id: u32` (`#[index(btree)]`) to `entity`, `movement_state`, `health_state`, `input_queue`. Default `0`.
- `world_config` keyed by `world_id` (PK) with `sim_authority: u8 {MODULE, SIDECAR}`, `authority_online: bool`, `server_tick`, `server_ts`. `set_sim_authority(world_id, mode)` admin reducer.
- `authority{identity PK, role: u8, world_id: u32, last_seen: Timestamp}`; `init` inserts publisher as admin; `register_authority` (admin-only); helper `require_authority(ctx, world_id) -> Result<(), String>`.
- `input_queue` → `public` with `#[client_visibility_filter]` restricting rows to identities in `authority`.
- Authority-only reducers: `write_movement_batch`, `apply_damage`, `spawn_npc`, `despawn_entity`, `write_npc_brain`, `write_action_event`, `heartbeat`; scheduled `check_authorities` (1 Hz, 5 s timeout). `tick_movement` already skips SIDECAR worlds (Phase 2) — extend to per-world. `set_sim_authority` becomes admin-only and takes `world_id`.
- `action_request{id PK, world_id btree, actor_id, ability_id, target_id, aim: Vec3, issued_at}` (authority-visible via RLS) written by `use_ability` for SIDECAR worlds after cooldown check.
- Add `look_pitch: f32` to `InputFrame` (Rust + GDScript + `to_reducer_args` + generator). Regenerate goldens (values unchanged; schema field added).
- Add tables (all `public` unless noted):
  - `session{id: u64 PK auto_inc, world_id: u32 unique, kind: u8, phase: u8, phase_ends_at: Timestamp, seed: u64, max_members: u16}`
  - `session_member{id PK auto_inc, session_id: u64 btree, entity_id: u64 btree, score: i64, coins: i64}`
  - `item_def{item_def_id: u32 PK, kind: u8, max_stack: u32, data: String}` (static, seeded by `seed_item_defs`)
  - `inventory_item{id PK auto_inc, owner_entity_id: u64 btree, item_def_id: u32, qty: u32, slot: i16, instance_data: String}`
  - `challenge{id PK auto_inc, entity_id: u64 btree, kind: u8, seed: u64, difficulty: f32, issued_at: Timestamp, expires_at: Timestamp, payload: String}` — **RLS**: `#[client_visibility_filter]` `SELECT c.* FROM challenge c JOIN player p ON c.entity_id = p.entity_id WHERE p.identity = :sender`
  - `npc_brain{entity_id: u64 PK, state: u8, target_id: u64, next_think_at: Timestamp, data: String}` (private)
  - `ability_def{ability_id: u32 PK, cooldown_ms: u32, range: f32, wind_up_ms: u32, data: String}` (static)
  - `ability_state{id PK auto_inc, entity_id btree, ability_id: u32, cooldown_until: Timestamp, charges: u8}`
  - `action_event{id PK auto_inc, world_id btree, actor_id: u64, ability_id: u32, target_id: u64, aim: Vec3, outcome: u8, server_ts: Timestamp}` — pruned by a scheduled reducer after 5 s.
- Reducers: `advance_phases` (scheduled 1 Hz: sessions whose `phase_ends_at` passed advance per `kind`; Phase 3 default kind 0 = LOBBY→PLAYING→RESULTS→LOBBY with fixed durations), `create_session(kind)`, `join_session(session_id)`, `leave_session`, `grant_item(entity_id, item_def_id, qty)` (module-internal helper + admin reducer), `consume_item(item_id, qty)`, `issue_challenge` (internal helper), `submit_challenge_result(challenge_id, result: Vec<f32>)` → validates expiry + calls `validate_challenge(kind, seed, difficulty, result) -> Option<f32 quality>` (Phase 3: kind 0 = "timing bar", pure function with golden vectors), `prune_action_events` (scheduled).
- `client_connected`: set `world_id = 0`, insert `session_member` if a default session exists.
**Accept:** `cargo test`; new `shared/golden/challenge_timing.json` for `validate_challenge` passes in Rust and GDScript (`ChallengeModel`).

## Task 2 — `SpaceTimeComponent` base
**File:** `foundation/core/spacetime_component.gd`
Per `ARCHITECTURE.md §7`. `receive_row_event` dispatch; debug `assert` in `_ready()` that `entity == null`.
**Accept:** unit test with a concrete subclass: insert → `_on_row_updated(t, null, row)`; delete → `(t, row, null)`; `bind` sets fields and calls `_on_bound`.

## Task 3 — `EntityDefinition` + `SpaceTimeEntity`
**Files:** `foundation/core/entity_definition.gd` (Resource: `kind: int`, `scene: PackedScene`, `display_name: String`), `foundation/core/spacetime_entity.gd`, `foundation/entities/player.tscn` (tree per `ARCHITECTURE.md §3`, placeholder capsule mesh)
- `bind(entity_id, world_id, owner_identity, initial_events: Array)`: sets `is_local_authority = EntityRegistry.is_local(entity_id)`; collects `required_tables()` from `$Components` children; builds `Dictionary[StringName, RefCounted]` of latest row per table from `initial_events`; binds components in tree order; `EntityRegistry.register`; frees `CameraRig` if remote, `Nameplate` if local; emits `bound` and `SignalBus.entity_spawned(entity_id, definition.kind)`.
- Missing required tables → start `bind_timeout_sec = 2.0` timer; on timeout bind with defaults + `push_warning` listing missing.
- `receive_row_event(ev)`: forward to components whose `required_tables()` contains `ev.table`.
- `body: CharacterBody3D` property = self, injected to components.
**Accept:** headless test binds a `player.tscn` instance with fake rows for `movement_state` + `health_state`; all components bound; `entity_spawned` emitted once; missing-table path warns and still binds.

## Task 4 — `EntitySpawner` autoload
**File:** `foundation/core/entity_spawner.gd`; register in `project.godot` after `EntityRegistry`.
- `@export var definitions: Array[EntityDefinition]`, `@export var world_root_path: NodePath`.
- Buffers `EntityRegistry.entity_row_inserted` until `SpaceTimeSync.world_ready`; then flushes.
- On insert: instantiate `definition.scene`, add to world root, `bind(entity_id, row.world_id, row.owner, EntityRegistry.peek_buffered(entity_id))`.
- On delete: `queue_free`, `SignalBus.entity_despawned`.
- **Reconnect rebind:** if a delete and a re-insert of the same `entity_id` arrive within the same drain (track a `_pending_despawn` set cleared on `process_frame`), skip despawn and call `entity.rebind(initial_events)` instead. Applies to all entities, matters most for the local one.
- Unknown `kind` → `push_error`, skip.
**Accept:** unit test feeds insert/delete `RowEvent`s; node count matches; reconnect pattern (delete then insert same id in one frame) yields one node, no `entity_despawned`.

## Task 5 — `SpaceTimeHealthComponent` + `HealthConfig`
**Files:** `foundation/components/spacetime_health_component.gd`, `health_config.gd`
Per `ARCHITECTURE.md §7`. Cache last row privately for read API.
**Accept:** tests: first bind → `health_changed` delta 0, no `damaged`; 100→75 → `damaged(25)`; 75→100 → `healed(25)`; `is_dead` false→true → `died(last_damage_source)`; true→false → `revived`; bus signals mirror with `entity_id` first.

## Task 6 — `SpaceTimeMovementComponent` (REMOTE_INTERPOLATED + SERVER_DRIVEN)
**File:** `foundation/components/spacetime_movement_component.gd`
- Snapshot ring (32) of `{server_usec, MovementState}` from `new.server_ts`.
- `_physics_process`: `render_time = ClockSync.server_usec() - config.remote_interp_delay*1e6`; lerp pos / `lerp_angle` yaw between bracketing snapshots; extrapolate with `vel` ≤ 100 ms past newest, then hold.
- `grounded` true→false with `vel.y > 0` → `jumped`; false→true → `landed(abs(old.vel.y))`. Mirror to bus.
- `teleport_flag` → clear ring, snap, `SignalBus.entity_teleported`.
- `LOCAL_PREDICTED`: `push_error("Phase 4")` stub; `push_input` asserts mode.
**Accept:** test feeds 3 snapshots at 50 ms spacing with a stubbed `ClockSync`; interpolated position at midpoint is the midpoint; `jumped`/`landed` fire exactly once each across a grounded flip and back.

## Task 7 — `LocalInputComponent` (sampling only, no sending yet)
**File:** `foundation/components/local_input_component.gd`
- Input map actions: `move_forward/back/left/right`, `jump`, `sprint`, `look_*` via mouse relative; builds `InputFrame` each physics tick with monotonic `seq`; emits `input_sampled(frame)`. Disabled unless `entity.is_local_authority`.
- Camera-relative `move_dir` from `CameraRig` yaw.
**Accept:** headless test with `Input.action_press` produces frames with incrementing `seq` and normalised `move_dir`.

## Task 8 — `SessionComponent` + session bus events
**Files:** `foundation/components/session_component.gd`; add to `SignalBus`: `session_phase_changed(session_id, old_phase, new_phase, ends_at_usec)`, `session_score_changed(entity_id, score, coins)`.
- `required_tables()` → `[&"session_member"]`; resolves its `session` row via `SpaceTimeSync.get_row(&"session", session_id)`; listens to `EntityRegistry.global_row_event` for `session` updates (non-entity table).
**Accept:** test: phase change on `session` row emits bus event once; member score change emits `session_score_changed`.

## Task 9 — `SpaceTimeInventoryComponent` + `ItemDefinition`
**Files:** `foundation/components/spacetime_inventory_component.gd`, `item_definition.gd`
- `required_tables()` → `[&"inventory_item"]` (many rows per entity — component keeps `Dictionary[int, RefCounted]` by row id).
- Signals: `item_added(item_def_id, qty)`, `item_removed(item_def_id, qty)`, `slot_changed(slot)`. Bus: `entity_inventory_changed(entity_id)`.
- Read: `count(item_def_id)`, `items() -> Array`.
- Intent: `request_consume(item_id, qty) -> ReducerRequest` via `SpaceTimeSync.call_reducer(&"consume_item", [item_id, qty], ["u64", "u32"])`.
**Accept:** insert/update/delete rows → correct counts and signals.

## Task 10 — `InteractionComponent`
**File:** `foundation/components/interaction_component.gd`
- Raycast from `CameraRig` camera (local only) each physics tick, `interaction_range` export; target must be a `SpaceTimeEntity` or a node in group `interactable` with `entity_id` meta.
- `SignalBus.interact_target_changed(entity_id_or_-1)` for prompt UI.
- On `interact` action: `SpaceTimeSync.call_reducer(&"interact", [target_id, verb], ["u64", "u8"])`. Server reducer `interact(target_id, verb)`: distance check against both `movement_state` rows (≤ 3 m), then dispatch by target `entity.kind` (Phase 3: kind 2 = `resource_node` stub → `issue_challenge(kind 0)`).
**Accept:** module test for distance rejection; client test that target change emits once per change.

## Task 11 — `InterestManager` autoload (interface only) — DONE
**File:** `foundation/net/interest_manager.gd`
- Owns the core `SubscriptionSet` (moved out of `SpaceTimeSync._on_connected`), keyed by `world_id`: `SELECT * FROM t WHERE world_id = <w>` for entity tables; unfiltered for `world_config`, `item_def`, `ability_def`.
- `set_world(world_id)`: subscribe new set, then unsubscribe old **after** new `applied` (overlap, no flicker).
- Emits `SpaceTimeSync.world_ready` semantics via the new set's `applied`.
- `cell`-based spatial sets are the MMO layer; leave a `virtual func build_queries(world_id) -> Array[String]`.
**Accept:** switching world twice yields exactly one active set after each `applied`; `world_ready` fires per switch.

## Task 12 — `SpaceTimeActionComponent` skeleton
**File:** `foundation/components/spacetime_action_component.gd`
- `required_tables()` → `[&"ability_state"]`; listens to `action_event` via `global_row_event` filtered by `actor_id == entity_id` or `target_id == entity_id`.
- Signals: `ability_ready(ability_id)`, `action_started(ability_id)`, `action_resolved(event_row)`. Bus: `entity_action(actor_id, ability_id, target_id, outcome)`.
- `request_use(ability_id, aim: Vector3, target_id) -> ReducerRequest` → reducer `use_ability`. Server: cooldown check, range check via `movement_state`, writes `action_event` with `outcome`; Phase 3 has one built-in ability 0 = "melee 2 m, 10 dmg" hitting `health_state`.
- No prediction in Phase 3 (Phase 4 adds predicted start + revocation).
**Accept:** module test: cooldown rejection, range rejection, damage applied; client test: `action_event` row → `action_resolved` once.

## Task 13 — Sidecar skeleton — DONE except the export preset (see AGENTS.md)
**Files:** `sidecar/sidecar_main.tscn/.gd`, `sidecar/authority_sync.gd`, `sidecar/sim_world.gd`, `export_presets.cfg`, `foundation/boot.gd` (dedicated_server branch), `SpaceTimeMovementComponent` (new mode `SERVER_AUTHORITY`), `run_tests.sh` (sidecar lint)
Per `docs/SIDECAR_SPEC.md §3`:
- Stable identity via `token_path`; `--world=` args; `InterestManager.build_queries` override adding `input_queue`, `action_request`, `npc_brain`.
- `SERVER_AUTHORITY` mode: drain queue rows per entity in seq order through `MovementModel.simulate` + `_resolve_with_body` at 60 Hz; idle frame when airborne/moving; catch-up clamp 8 with `teleport_flag`.
- `AuthoritySync`: per 20 Hz tick collect changed entities → one `write_movement_batch`; `heartbeat` at 1 Hz.
- Cold start: spawn from `movement_state`, apply backlog.
**Accept:** headless test feeds a fake `input_queue` stream to an entity in `SERVER_AUTHORITY` mode on a test level with a wall; entity stops at the wall; `write_movement_batch` payload has `last_processed_seq` = last consumed. Lint: no `res://sidecar` outside `sidecar/`.

## Task 14 — NPC brain (sidecar) + predator example — DONE except `write_npc_brain` persistence
**Files:** `sidecar/npc/npc_brain_component.gd`, `sidecar/npc/brains/wander.gd`, `chase.gd`
- `NpcBrainComponent.produce_frame() -> InputFrame` each physics tick from the active brain; think at 10 Hz.
- `wander`: random navmesh point via `NavigationServer3D.map_get_random_point`. `chase`: nearest player entity in world within `radius` with raycast LOS; touch ≤ 0.8 m → `apply_damage(target, 10, self)` with 1 s cooldown.
- Persist `state/target` via `write_npc_brain` on change only.
- Sidecar spawns NPCs by reading `entity.kind` and attaching the component; `spawn_npc` dev reducer callable by admin.
**Accept:** headless test on a test level: chase brain closes distance to a stationary target over 2 s of ticks and calls `apply_damage` once per cooldown window.

## Task 15 — Animation driver + generated tree (foundation half of `docs/ANIMATION_SPEC.md`)
**Files:** `foundation/anim/animation_set.gd`, `animation_clip_ref.gd`, `animation_tree_builder.gd`, `foundation/components/animation_driver_component.gd`, `foundation/tools/animation_set_builder.gd`, `game/characters/reference_humanoid.tscn` (any CC0 humanoid + library), test suite.
**Accept:** headless `test_animation_driver` per spec §6; driver has zero references to rows, SDK, or UI; `dedicated_server` feature disables processing.

## Task 16 — Docs & tests sweep
- `test_runner.gd` gains one suite per component; `run_tests.sh` lint extended to `components/`.
- `README.md` status table updated; `docs/DECISIONS.md` appended with any deviations.

---

## Definition of done for Phase 3
- Two clients connect to a local server with the sidecar running for world 1; each sees the other as a remote entity moving through a level with walls (simulated by the sidecar), plus one chasing NPC; health bars driven by `entity_health_changed` via `apply_damage`.
- World 0 (Tier A, no sidecar) still works for the same two clients with no code change on the client.
- `run_tests.sh` and `cargo test` green; goldens `max_err = 0` (challenge validators; movement goldens are GDScript-only regression vectors).
- No file outside `spacetime_sync.gd` references the SDK; no `@rpc`.
- `world_id` on every entity table; `InterestManager` is the only place subscription SQL is built.
