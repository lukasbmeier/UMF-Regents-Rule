# Phase 4 — Client-Side Prediction, Reconciliation, Interpolation

> **STATUS (2026-09-21): ALL SECTIONS IMPLEMENTED.** §1 prediction, reconciliation, predicted
> discrete events with revocation (#68-#73, #83); §2 horizontal ground/air with reversal braking,
> slopes, config-gated flap/dash, `move_state` classification mirrored to everyone (#80-#82,
> #84, #85); §3 predicted actions with the Task 12 component, resolved coarsely in Tier A (#86);
> §4 remote interpolation (#75, #76); §5 verified by `tests/playtest_test.sh` and
> `tests/remote_playtest.sh` at 0-250 ms simulated latency with jitter. What differs from the
> text below, and why: overrides use a correction EPOCH plus a replay budget (#71, #72); remote
> snapshots sit on a per-entity seq timeline with Hermite interpolation (#75, #76); a refused
> action is a reducer Err rather than a REJECTED row (#86). The sidecar parts (SERVER_AUTHORITY
> movement, `action_request` hit tests) belong to Task 13.


Prerequisite: Phase 3 done. Read `ARCHITECTURE.md §4–6` first. Everything here lives in `SpaceTimeMovementComponent` (LOCAL_PREDICTED mode), `SpaceTimeActionComponent`, `MovementModel` (GDScript), and `_resolve_with_body`.

## 1. LOCAL_PREDICTED mode — `SpaceTimeMovementComponent`

### State
```
predicted: MovementState                 # what we render (plus visual_offset)
authoritative: MovementState             # last row
_pending: Array[InputFrame]              # sent or to-send, seq > last_processed_seq
_history: Dictionary[int, MovementState] # seq → predicted state AFTER applying that seq; ring ~2 s (120 entries)
_visual_offset: Vector3                  # decays to zero over config.reconcile_smooth_time
_batch: Array[InputFrame]                # frames not yet sent
```

### Per physics tick
1. `push_input(frame)` from `LocalInputComponent`: `frame.client_pos` is filled **after** simulation (Tier A trust).
2. `predicted = MovementModel.simulate(predicted, frame, config, dt, _resolve_with_body)` where `_resolve_with_body` applies the state to the `CharacterBody3D`, calls `move_and_slide()`, and reads back `global_position`, `velocity`, `is_on_floor()` into the returned state. This is the client's `CollisionResolver`.
3. `frame.client_pos = predicted.pos`; `_history[frame.seq] = predicted`; `_pending.append(frame)`; `_batch.append(frame)`.
4. Discrete events: `grounded` flip → `jumped`/`landed` with a `predicted_event_id`.
5. When `_batch.size() >= config.input_batch_size`: `req = SpaceTimeSync.submit_input(_batch)`; `req.settled.connect(_on_req_settled)`; clear batch.
6. Render: `Visual.position = _visual_offset`; body is already at `predicted.pos`. Decay `_visual_offset` toward zero: `move_toward` by `len / smooth_time * dt`.

### On `_on_row_updated(movement_state)`
```
authoritative = MovementState.from_row(new)
if new.teleport_flag: snap(); return
drop _pending where seq <= new.last_processed_seq
hist = _history.get(new.last_processed_seq)
if hist == null: snap(); return          # history evicted or first row
err = hist.pos.distance_to(authoritative.pos)
if err < config.reconcile_accept_epsilon: return
if err >= config.reconcile_snap_threshold: snap(); emit reconciled(err); return
# smooth band
old_render = predicted.pos
predicted = authoritative
for f in _pending: predicted = simulate(predicted, f, config, dt, _resolve_with_body); _history[f.seq] = predicted
_visual_offset += old_render - predicted.pos
emit reconciled(err)
```
`snap()`: `predicted = authoritative`, clear `_pending`/`_history`, `_visual_offset = ZERO`, body to pos, `SignalBus.entity_teleported`.

### On `ReducerRequest.settled` with non-OK outcome
Drop `_pending` and `_history` entries in `[seq_from, seq_to]`; re-simulate the remainder from `authoritative` (same loop as smooth band). `REJECTED` also emits `SignalBus.action_rejected`.

### Event revocation
If a row contradicts a predicted discrete event (predicted `jumped` at seq N but authoritative `grounded` stayed true through N), emit `event_revoked(predicted_event_id)`. SFX ignore it; ability systems (Phase 4 §3) cancel.

### Tests (headless, no server)
- Feed a scripted row stream against a scripted input stream through a fake `SpaceTimeSync`: (a) matching rows → zero reconciles; (b) row offset 10 cm → one smooth reconcile, `visual_offset` decays to < 1 mm within `smooth_time`; (c) 2 m offset → snap; (d) request `REJECTED` for seqs 5–7 → those seqs gone from `_history`, re-sim from authoritative.
- Determinism: replaying `_pending` twice from the same authoritative state yields bit-identical `predicted`.

## 2. Full movement model
Extend `simulate()` in **GDScript only** (`movement_model.gd`, shared by client prediction and the sidecar's `SERVER_AUTHORITY` mode). GDScript golden vectors remain as regression tests so client and sidecar builds of different versions cannot drift. Order:
1. `horizontal_ground.json`: acceleration/friction toward `move_dir * (sprint ? sprint_speed : walk_speed)`, rotated by `look_yaw`.
2. `horizontal_air.json`: air control blend.
3. `slopes.json`: `max_slope_deg` via the resolver's floor normal (`get_floor_normal()` on both client and sidecar).
4. `flap_dash.json`: config-gated `flap_charges`, `flap_velocity`, `dash_impulse`, `dash_cooldown_ticks` (chicken genre) — present in the model, zero/disabled by default.
5. `move_state` enum: `IDLE, WALK, SPRINT, AIR, DASH, SWIM, MOUNT` assigned by the model.

Collision on both sides is `_resolve_with_body` (`move_and_slide`). No server-side proxy resolver.

## 3. Predicted actions — `SpaceTimeActionComponent`
- `request_use()` immediately emits `action_started(ability_id, predicted_event_id)` and starts the local cooldown timer if `ability_def.wind_up_ms > 0`.
- Module `use_ability` checks cooldown → `ability_state` + `action_request` row. Sidecar (`sidecar/combat/`) resolves the hit with `PhysicsDirectSpaceState3D` and calls `apply_damage` + `write_action_event`. In MODULE (Tier A) worlds the module resolves coarsely as in Phase 3.
- `action_event` row with matching `actor_id` within `wind_up_ms + RTT` → `action_resolved`. Missing or `outcome == REJECTED` → `event_revoked`, cooldown reset.
- Design rule: content authors set `wind_up_ms >= 100`.

## 4. Remote interpolation refinements
- Adaptive `interp_delay`: `max(config.remote_interp_delay, 1.5 * observed snapshot interval)`.
- Snapshot buffer respects `teleport_flag` (already) and `world_id` change (clear).

## 5. Definition of done
Two clients on a local server with 100 ms artificial latency (`tc`/`clumsy`): the local player's movement has no visible input latency; the remote player is smooth; forcing a divergence (Tier A trust radius exceeded via a dev reducer that offsets the server row) produces a glide, not a pop, and a 2 m teleport produces a snap with `entity_teleported`. All golden suites `max_err = 0` on both sides.
