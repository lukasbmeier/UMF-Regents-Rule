# Sidecar — Headless Godot as the Simulation Authority

Replaces "Tier B/C = hand-written server collision" with a headless Godot process running the real engine. SpacetimeDB remains the authority for identity, ownership, economy, inventory, health values, sessions, RLS and persistence. The sidecar is the authority for **motion and world-context decisions** (collision, navigation, hit resolution, NPC behaviour) and writes results back through authority-only reducers.

Tier A (module-only, no sidecar) still exists for genres that don't need it. The client does not know or care which is running.

## 1. One project, two builds

```
<project root>
  foundation/        shared: sync, entity framework, components, MovementModel (public — runs on clients anyway)
  game/              client-only: UI, camera rigs, VFX, audio
  sidecar/           SERVER-ONLY. Excluded from the client export. Never referenced from foundation/ or game/.
    sidecar_main.tscn / .gd     boot, connection, world assignment
    authority_sync.gd           subscribes input_queue, batches writes, heartbeat
    sim_world.gd                owns the loaded level + entity instances in SERVER_AUTHORITY mode
    npc/                        NpcBrainComponent + behaviours (server-context aware)
    combat/                     hit resolution via PhysicsDirectSpaceState3D
  export_presets.cfg
    [Client]  exclude_filter = "sidecar/*"
    [Server]  Linux, "Export as dedicated server" (strips textures/meshes; sets feature `dedicated_server`), include everything
```

- `boot.gd`: `if OS.has_feature("dedicated_server"): change_scene_to_file("res://sidecar/sidecar_main.tscn")`. The client PCK does not contain that scene; the branch is never taken there.
- Lint (`run_tests.sh`): any `res://sidecar` reference outside `sidecar/` fails the build.
- What is still readable in the client: the movement model, component logic, SignalBus. None of it is authority. What is not: NPC brains, hit resolution, spawn/loot rules, anti-cheat heuristics.
- Level scenes: the sidecar loads the same `.tscn` levels (collision + navmesh only after dedicated-server export strips visuals). The Tier B collider exporter is no longer needed for the sidecar path.

## 2. Trust model in the module

```rust
#[table(accessor = authority, public)]           // public so the sidecar can read its own row; RLS not needed (no secrets)
pub struct Authority { #[primary_key] identity: Identity, role: u8 /* 0 admin, 1 sidecar */, world_id: u32 /* 0 = all */, last_seen: Timestamp }
```
- `#[reducer(init)]` inserts `ctx.sender()` (the publisher) as `role = admin`.
- `register_authority(identity, role, world_id)` — sender must be admin. Run once per sidecar identity via `spacetime call` from the publishing machine.
- Every authority-only reducer begins: `require_authority(ctx, world_id)?` → sender has a row with matching `world_id` (or 0).
- `input_queue` becomes `public` with `#[client_visibility_filter]`: rows visible only to identities in `authority`. Players never see other players' inputs.
- `world_config` gains `sim_authority: u8 { MODULE = 0, SIDECAR = 1 }` per `world_id` (move `world_config` from singleton to keyed by `world_id`). `tick_movement` skips simulation for SIDECAR worlds and only prunes stale inputs.

### Authority-only reducers
| Reducer | Body |
|---|---|
| `write_movement_batch(world_id, writes: Vec<MovementWrite>)` | for each: update `movement_state` (pos, vel, yaw, grounded, move_state, last_processed_seq, server_tick, server_ts, teleport_flag); `input_queue.entity_id().filter(eid)` delete rows with `seq <= last_processed_seq`. One call per server tick for the whole world. |
| `apply_damage(target_id, amount, source_id, kind)` | writes `health_state`; death flip; `last_damage_source`. Only path that changes health. |
| `spawn_npc(world_id, kind, pos)` / `despawn_entity(entity_id)` | entity + movement_state + health_state + npc_brain rows |
| `write_npc_brain(entity_id, state, target_id, data)` | low-rate persistence of brain state (on change, ≤ 1 Hz) |
| `write_action_event(...)` | hit resolution outcome (replaces module-side `use_ability` resolution for SIDECAR worlds; module still enforces cooldown + writes `ability_state`) |
| `heartbeat(world_id)` | updates `authority.last_seen`; scheduled `check_authorities` (1 Hz) flips `world_config.authority_online = false` after 5 s silence |

Everything the *client* calls is unchanged: `submit_input`, `interact`, `use_ability` (intent), `consume_item`, session reducers. The module still validates ownership, seq monotonicity, batch size, queue depth, phase gating, cooldowns.

## 3. Sidecar runtime

**Connection.** `NetConfig` with `token_path = user://sidecar_token.dat`, `one_time_token = false`, so the identity is stable across restarts. CLI: `godot --headless --path . -- --world=3` (worlds read from `OS.get_cmdline_user_args()`; default = all worlds with `sim_authority = SIDECAR`).

**Subscriptions** (via `InterestManager.build_queries` override): `SELECT * FROM input_queue WHERE world_id = W`, plus `entity`, `movement_state`, `npc_brain`, `world_config`, `ability_state`, `static level data` for W. Not `health_state` for display — it doesn't render — but yes for gameplay (NPC flee at low HP).

**Entity instances.** The same `EntitySpawner` spawns `player.tscn` for every entity, but `SpaceTimeEntity.bind()` in the sidecar sets `Movement.mode = SERVER_AUTHORITY` for all entities (new 4th mode) and attaches `NpcBrainComponent` when `entity.kind` is an NPC kind. `CameraRig`, `Nameplate`, `Visual` are freed (or never present after dedicated-server export).

**`SERVER_AUTHORITY` movement mode** (in `SpaceTimeMovementComponent`, foundation code — the mode is harmless in the client build because nothing there enters it):
- Initial state from the `movement_state` row on bind.
- Each physics tick (60 Hz): consume every `input_queue` row for this entity with `seq > last_processed_seq`, in seq order, applying `MovementModel.simulate(state, frame, config, dt, _resolve_with_body)` per frame — same function, same resolver (`move_and_slide`), as the client's prediction. If no frames arrived this tick and the entity is airborne or moving, simulate one idle frame so gravity and friction still act. Clamp catch-up to 8 frames per tick; if a client's backlog exceeds that, drop the oldest and set `teleport_flag` once.
- NPC entities: `NpcBrainComponent.produce_frame() -> InputFrame` replaces the queue. NPCs and players are simulated by identical code.
- Per server tick (20 Hz): if state changed since last write, append a `MovementWrite` to `AuthoritySync`'s batch. `AuthoritySync` sends `write_movement_batch` once per tick for the world.

**Combat resolution.** `use_ability` intent reducer (module) checks cooldown/range coarse-grained and inserts an `action_request` row (authority-visible). Sidecar consumes it: exact hit test via `PhysicsDirectSpaceState3D.intersect_ray/shape` against the loaded level and entity bodies, then `apply_damage` + `write_action_event`. Clients see the `action_event` row as before.

**NPC AI.** `NpcBrainComponent` (server-only script) has full engine context: `NavigationServer3D` paths on the level navmesh, raycast line-of-sight, `Area3D` triggers, access to every entity's authoritative state in the local cache. Behaviour trees/state machines are plain GDScript. Persist only what spectators or a restart need via `write_npc_brain`; think at 5–10 Hz, move at 60 Hz through the shared model.

**Cold start / crash.** On `world_ready`, entities spawn from `movement_state` rows as current truth; `input_queue` backlog is applied per entity (oldest first, with the catch-up clamp). Nothing is lost because inputs and state live in the DB. While `authority_online = false`, clients freeze remote interpolation (hold last snapshot) and show a "world paused" notice via `SignalBus`; local prediction continues and reconciles when writes resume.

**Scaling.** One process per world for survival/MMO zones; several small worlds per process is fine for party games (`--world=1,2,3`). Colocate with the SpacetimeDB host; the two extra hops (DB → sidecar push, sidecar → DB reducer) are low single-digit milliseconds on the same machine.

## 4. What this removes and what it keeps

**Removed:** Rust `sim.rs` movement simulation (freeze at gravity-only for Tier A idle handling, or reduce Tier A to validation-only — see DECISIONS #23); `CollisionResolver`/`ProxyResolver`; heightfield and waypoint exporters; movement golden vectors; Phase 4 §2 "server swept capsule". Client/server movement parity is now free: same engine, same scene, same GDScript, reconciliation tolerates the residual float differences across platforms (well under the 2 cm accept band).

**Kept:** everything client-side (prediction, reconciliation, interpolation, components, SignalBus); `submit_input` and all intent reducers; RLS; the golden-vector harness *infrastructure* — now used for the Challenge validators (`ReelModel`, mining rhythm), which are small, economic, and must be re-simulated in the module because the sidecar is not involved in minigames.

## 5. Setup delta (versus current repo)

| Area | Change |
|---|---|
| Godot project | add `sidecar/`; add `export_presets.cfg` with two presets; `boot.gd` branch on `dedicated_server` |
| Module | `authority` table + `register_authority`; `input_queue` public + RLS; `world_config` keyed by `world_id` with `sim_authority`, `authority_online`; 6 authority-only reducers; `tick_movement` skips SIDECAR worlds |
| Movement component | 4th mode `SERVER_AUTHORITY`; `_resolve_with_body` shared with LOCAL_PREDICTED |
| Deploy | one more process per world; a `systemd`/container unit running `godot --headless` with the server PCK; register its identity once |
| Lint | `res://sidecar` outside `sidecar/` fails; `NpcBrainComponent`/combat scripts must live under `sidecar/` |

## 6. Phase plan impact
- **Phase 3**: Task 1 adds `authority`, `sim_authority`, RLS on `input_queue`; Task 13 (NPC brain in Rust) → replaced by `sidecar/npc/NpcBrainComponent`; Task 14 (collider/nav exporter) → dropped; new Task 16: sidecar skeleton (connect, register, spawn entities in SERVER_AUTHORITY, `write_movement_batch`, heartbeat) with Definition of Done: two clients see each other move through a level with walls, simulated by the sidecar.
- **Phase 4**: §1 unchanged (client reconciliation); §2 reduces to "extend `MovementModel` in GDScript only + `_resolve_with_body`"; §3 `use_ability` becomes `action_request` consumed by the sidecar.
