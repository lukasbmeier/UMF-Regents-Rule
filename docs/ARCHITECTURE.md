# Architecture

## 1. Principles (as sharpened in Phase 1)

**Passive view with two state records.** Components never own *authoritative* state. Each synced component holds `authoritative` (read-only mirror of the cache row) and, where predicted, `predicted` (local, may diverge). Visuals read `predicted` for the local player and interpolated `authoritative` for everyone else. Only the cache dispatcher writes `authoritative`.

**Prediction reconciles on rows, not acks.** The reducer-call outcome tells you the transaction committed; the `movement_state` row tells you what it produced. Reconciliation keys on input `seq`, never on time.

**Composition.** Logic lives in component nodes under `Components/`. `Resource` = design-time config and schemas (`MovementConfig`, `HealthConfig`, `EntityDefinition`). `RefCounted` = runtime structs (`InputFrame`, `MovementState`, `RowEvent`). Generated row classes = cache mirrors (read-only).

**Two buses.** Entity-local signals for component ↔ component (Movement → AnimationTree). Global `SignalBus` for low-frequency, `entity_id`-first, UI-facing events only. UI filters on `EntityRegistry.local_entity_id`.

**SpacetimeDB has no physics engine, so motion authority is pluggable.** Tier A: the module trusts the client within a radius (no geometry). Sidecar: a headless Godot process running the same `MovementModel` + `move_and_slide` is the motion authority and writes back through authority-only reducers (`docs/SIDECAR_SPEC.md`). The client is identical under both; the seam is `input_queue` in, `movement_state` out.

## 2. Autoloads (order = boot sequence)

```
(client and sidecar builds share this list; the sidecar additionally loads res://sidecar/ at boot)
1. SpacetimeDB    GENERATED container (spacetime_bindings/schema/spacetime_autoload.gd); holds SpacetimeDB.<Alias>
2. SignalBus      typed global signals, zero logic
3. ClockSync      server clock estimate (clamped EMA), interpolation timing only
4. SpaceTimeSync  SDK adapter: connect, subscribe, call_reducer, row → RowEvent
5. EntityRegistry entity_id → node; buffers early rows; spawner hooks
6. EntitySpawner  (Phase 3) watches `entity` rows, instantiates via EntityDefinition
7. InterestManager(Phase 3 interface) owns SubscriptionSets; single "core" set until MMO layer
```

## 3. Universal entity scene (`player.tscn`, same scene for local/remote/NPC)

```
Player : CharacterBody3D            [SpaceTimeEntity]  entity_id · world_id · owner · is_local_authority · definition
├── Components : Node
│   ├── Movement   [SpaceTimeMovementComponent]  config: MovementConfig   mode: LOCAL_PREDICTED | REMOTE_INTERPOLATED | SERVER_DRIVEN
│   ├── Health     [SpaceTimeHealthComponent]    config: HealthConfig
│   ├── Action     [SpaceTimeActionComponent]    (Phase 3 skeleton, Phase 4 prediction)
│   ├── Inventory  [SpaceTimeInventoryComponent] (cache-only)
│   ├── Session    [SessionComponent]            (phase machine listener)
│   └── Interaction[InteractionComponent]        (raycast → intent reducer)
├── Input : Node   [LocalInputComponent]          disabled unless is_local
├── CollisionShape3D
├── Visual : Node3D                               mesh only; receives visual_offset for reconciliation smoothing
│   ├── Model · AnimationTree (pulls Movement.get_render_state each frame) · VFX
├── CameraRig : Node3D                            freed if not local; 1st/3rd person is a rig resource swap
└── Nameplate : Node3D                            freed if local
```

Rules: `SpaceTimeEntity` is the only node that knows the component list. Two-phase init — `_ready()` touches nothing synced; `bind()` (called by the spawner) cascades to components. Components find the body via injected `entity.body`, never `get_parent()`.

## 4. Data flow — local player presses Jump

| t | where | what |
|---|---|---|
| 0 | `LocalInputComponent` | samples input → `InputFrame{seq, client_tick, move_dir, look_yaw, look_pitch, jump, client_pos}` |
| 0 | `Movement` (LOCAL_PREDICTED) | pushes to `_pending_inputs`, runs `MovementModel.simulate`, applies to body, records `_history[seq]`, emits `jumped` + `SignalBus.entity_jumped` |
| 0–50 ms | `SpaceTimeSync.submit_input(frames)` | batches `input_batch_size` frames into one generated-reducer call |
| +RTT/2 | module `submit_input` | validates sender owns entity, seq monotonic, batch ≤ 8, queue ≤ 64; queues frames (bad frames dropped, not `Err`) |
| next tick | module `tick_movement` (scheduled, 20 Hz) | drains queue through `sim::simulate` (same model), Tier A trusts `client_pos` within 0.5 m, writes `movement_state{…, last_processed_seq}` |
| +RTT | SDK → `SpaceTimeSync` → `EntityRegistry` → `Movement._on_row_updated` | **reconcile**: drop pending ≤ `last_processed_seq`; compare `_history[seq]` to row; accept (< 2 cm) / re-simulate pending + smooth `visual_offset` over 100 ms (< 1 m) / snap (≥ 1 m or `teleport_flag`) |
| +RTT | remote clients' `Movement` (REMOTE_INTERPOLATED) | push snapshot; render at `ClockSync.server_usec() - interp_delay`; `grounded` flip → `jumped`/`landed` |

Reducer failure path: `ReducerRequest.settled` with `REJECTED/FAILED/TIMEOUT/DISCONNECTED` and `seq_from..seq_to` → Movement drops those inputs immediately instead of waiting for a row that will never come.

## 5. Motion authority

| Mode (`world_config.sim_authority`) | Who simulates | `client_pos` | Geometry | Use |
|---|---|---|---|---|
| MODULE (Tier A) | module `tick_movement`; the gravity-only twin moves only undriven entities | taken exactly within a per-frame speed envelope, clamped beyond it, correction epochs (DECISIONS #70-#72) | none | co-op, party, social, fishing, chicken |
| SIDECAR | headless Godot, `SERVER_AUTHORITY` movement mode, real level scene | ignored | the level itself (Jolt/Godot physics + navmesh) | survival, MMO, physics-heavy party games |

Per world, switchable via `set_sim_authority(mode)` (keyed by `world_id` from Phase 3 Task 1). Phase 2's hand-written proxy collision has been removed. See `docs/SIDECAR_SPEC.md`.

## 6. Parity rules (GDScript ⇄ Rust) — scope

Movement parity between client and sidecar is free (same engine, same script). The Rust movement twin in `sim.rs` is frozen at gravity-only for Tier A idle handling — do not extend it.

Parity rules still apply to anything the **module** must re-simulate: Challenge validators (`ReelModel`, mining rhythm) and any future economic minigame.
1. f32 only (`Vector2/3` or explicit `float` cast through a Vector component in GDScript); identical operation order.
2. Every change regenerates `shared/golden/*.json` and passes both suites with `max_err = 0`.
3. Movement model branches (flap, dash, swim, mount) are config-driven inside the one GDScript model, never per-genre forks — they still need GDScript golden vectors so client and sidecar builds cannot drift across versions.

## 7. Component contracts

### Base — `SpaceTimeComponent` (`@abstract`)
```gdscript
var entity: SpaceTimeEntity; var entity_id: int; var is_local_authority: bool
@abstract func required_tables() -> Array[StringName]
func bind(entity: SpaceTimeEntity, initial_rows: Dictionary[StringName, RefCounted]) -> void   # calls _on_bound()
func receive_row_event(ev: RowEvent) -> void       # dispatches by ev.kind
@abstract func _on_row_updated(table: StringName, old: RefCounted, new: RefCounted) -> void
func _on_row_inserted(table, row) -> void          # default: _on_row_updated(table, null, row)
func _on_row_deleted(table, row) -> void           # default: _on_row_updated(table, row, null)
```

### `SpaceTimeHealthComponent` — fully authoritative, no prediction, no client damage API
- table `health_state{entity_id, current, max, is_dead, last_damage_source, last_change_server_tick}`
- local signals: `health_changed(current, max, delta)` · `damaged(amount, source_id)` · `healed(amount)` · `died(killer_id)` · `revived()`
- bus: `entity_health_changed(eid, current, max)` · `entity_died(eid, killer_id)` · `entity_revived(eid)`
- read: `get_current/get_max/get_ratio/is_dead`

### `SpaceTimeMovementComponent`
- table `movement_state{entity_id, pos, vel, yaw, grounded, move_state, last_processed_seq, server_tick, server_ts, teleport_flag}`
- `push_input(frame)` (LOCAL_PREDICTED only)
- local signals: `predicted_state_changed(state)` · `jumped()` · `landed(impact_speed)` · `move_state_changed(old,new)` · `reconciled(error)`
- bus: `entity_jumped` · `entity_landed` · `entity_teleported`
- read: `get_render_state()` · `get_authoritative_state()` · `get_visual_offset()`

## 8. SDK facts the design depends on (plaught-armor Godot-SpacetimeDB-SDK 2.x)

- Generated bindings: `res://spacetime_bindings/`. Autoload `SpacetimeDB` is a container; the client is `SpacetimeDB.<Alias>` (`Umf`). Generated types: `<Alias><TypeName>` (`UmfInputFrame`), rows expose static `create(...)` and `BSATN_TYPES`.
- Signals used: `connected(identity: PackedByteArray, token: String)`, `disconnected` (terminal), `connection_error(code, reason)`, `reconnecting(attempt, max)`, `reconnected`, `reconnect_failed`, `row_inserted(table: StringName, row: Resource)`, `row_updated(table, old, new)`, `row_deleted(table, row)`.
- `subscribe(PackedStringArray) -> SpacetimeDBSubscription` with `applied`/`end` signals; handles survive reconnects (suspended → applied again). Never resubscribe from `reconnected`.
- Reconnect = full teardown: every row fires `row_deleted`, then survivors re-insert. Spawner despawns/respawns.
- `call_reducer(name, args, types) -> SpacetimeDBReducerCall`; no completion signal — `await handle.wait_for_response(timeout)`. `Outcome { PENDING=0, OK, OK_EMPTY, ERROR, INTERNAL_ERROR, TIMEOUT, DISCONNECTED }`.
- Rows are the cache's own `Resource` instances — read-only.
- Wire types: `float`⇄`f64` default; `Vector3`⇄struct `{x,y,z: f32}` (our Rust `Vec3`); `u32/u8` need BSATN hints → use generated reducer wrappers for struct arguments (`submit_input`).
- `LocalDatabase.first_by(table, field, value)` / `get_row_by_pk` work without generated wrappers.
- Compression enum: `NONE 0, BROTLI 1, GZIP 2`. `confirmed_reads=false` for latency.

## 9. SpacetimeDB 2.10 Rust module facts

`#[table(accessor = x, public)]`, `#[primary_key] #[auto_inc] #[unique] #[index(btree)]`, `#[table(accessor = s, scheduled(reducer))]` with `scheduled_id: u64, scheduled_at: ScheduleAt`, `TimeDuration::from_micros(i64).into()` → looping schedule, `Timestamp.into()` → one-shot. `ctx.sender()` and `ctx.database_identity()` are methods; `ctx.timestamp` is a field. `ctx.db.t().col().find/update/delete` for unique cols; `ctx.db.t().col().filter(v)/delete(v)` for btree. Reducers return `()` or `Result<(), impl Display>`; `Err` rolls back the whole transaction. Row-level security via `#[client_visibility_filter]` (Phase 3 for `challenge`).

## 10. Blindspots and mitigations

| Risk | Mitigation |
|---|---|
| SpacetimeDB can't run physics | Tier A trust for light genres; headless Godot sidecar as motion authority for the rest |
| Client build is readable | authority logic only under `sidecar/`, excluded from client export, lint-enforced |
| Sidecar crash/offline | inputs + state live in DB; `authority_online` flag; clients hold interpolation, keep predicting |
| Rubberbanding / phantom jump | three-band error handling; visual offset decoupled from body; `reducer_failed` drops inputs; predicted event ids for revocation |
| Row arrival order / init races | `EntityRegistry` buffers per entity; `required_tables()` gate; `bind_timeout`; `_ready()` forbidden from cache |
| Reconnect teardown despawns local player | spawner treats delete+reinsert of `local_entity_id` within one drain as a rebind, not respawn (Phase 3) |
| Subscription scale (MMO) | `world_id` + `cell` columns; `InterestManager` with overlapping set swap |
| Client/server tick mismatch | reconciliation on `seq`; `ClockSync` only for interpolation |
| Reducer volume/energy | input batching (3 frames), 20 Hz server tick, bad frames dropped not `Err` |
