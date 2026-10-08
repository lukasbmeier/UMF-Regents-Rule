# Local-model playbook for the Universal Multiplayer Foundation

Target: Qwen3 30B/35B-A3B class MoE on a 16 GB RX 9060 XT.
Repo docs for the model: `AGENTS.md` (rules), `docs/PHASE3_SPEC.md` (tasks with acceptance criteria). Chunks below map onto Phase 3 tasks.
Role of the local model: **junior implementer**. It writes one bounded file at a time against a contract you paste in. It does not design, does not touch more than one file per task, and never invents SDK or SpacetimeDB API names — it copies them from text you provide.

---

## 0. Runtime setup (do once)

- Runner: llama.cpp (Vulkan or ROCm build) or LM Studio. Ollama works but gives you less control over the settings below.
- Quant: a ~Q4 GGUF of a 30B-A3B MoE is ~17–18 GB and will not fit 16 GB with context. Two options:
  - `IQ4_XS` / `Q3_K_M` fully on GPU, ~24K context, or
  - `Q4_K_M` with experts offloaded to CPU: `-ot ".ffn_.*_exps.=CPU" -ngl 99`. Only ~3B params are active per token, so this stays usable (speed depends on RAM bandwidth).
- Settings: context 32768, `--flash-attn`, KV cache `q8_0`, temperature 0.2, top-p 0.9, repeat penalty 1.05.
- Thinking mode: ON for anything touching parity math or reconciliation; `/no_think` for renames, docstrings, and test scaffolding.
- Do not use agentic editors (Cline, Roo) with this model — they burn the context on tool chatter. Use plain chat with manual paste, or Aider with `--edit-format whole --map-tokens 0` and explicitly `/add` only the 2–3 files the task needs.

---

## 1. System prompt (paste at the start of EVERY session)

```
You are a GDScript 2.0 / Rust implementer on a Godot 4.7 + SpacetimeDB 2.x project.

HARD RULES — violating any of these is a failed task:
1. Output ONE complete file. No prose before or after. No placeholders, no "// rest unchanged".
2. Strictly typed GDScript: every var, parameter, and return has a type. Use `:=` only when the type is obvious from a constructor call.
3. Never use @rpc, MultiplayerSynchronizer, MultiplayerSpawner, or Godot's high-level multiplayer.
4. Never reference SpacetimeDB SDK types or the /root/SpacetimeDB node outside spacetime_sync.gd.
5. Components never own authoritative state. They receive it via `_on_row_updated(table, old, new)` and may only own `predicted` and presentation state.
6. Components never reference UI nodes. Low-frequency, entity-id-tagged events go on SignalBus. Position and velocity never go on SignalBus.
7. Movement math: all pos/vel arithmetic through Vector3 (f32). No scalar float intermediates. Same operation order as the Rust twin.
8. Two-phase init: `_ready()` never touches synced data. `bind()` does.
9. If a needed API name is not in the text I gave you, write `# TODO(verify): <what you need>` and use a reasonable stub. Do not guess a real-looking name.
10. If the task is ambiguous, ask ONE question and stop. Do not write code on an assumption.

When I paste an error, reply with the corrected complete file only.
```

---

## 2. Task prompt template

Every task uses this shape. Fill the blanks; keep total paste under ~12K tokens.

```
## CONTEXT
<one paragraph: what this file is for, where it sits>

## CONTRACT
<the signals / methods / resource fields it must expose — copy from the blueprint>

## REFERENCE FILES
<paste 1–2 existing files it must be consistent with. Prefer a sibling that already follows the pattern.>

## TASK
<numbered, concrete, finite>

## CHECKLIST (verify before answering)
- [ ] every declaration typed
- [ ] no SDK references
- [ ] no UI references
- [ ] file compiles standalone given the reference files
- [ ] <task-specific item>

Output the complete file `res://path/to/file.gd` and nothing else.
```

---

## 3. Chunks, in order

### Chunk 1 — SDK binding fix — DONE (bindings verified against api.md/codegen.md; start at Chunk 2)
Paste: the `SDK BINDING SURFACE` section of `spacetime_sync.gd` + the relevant sections of the vendored SDK's `docs/api.md` (connection, signals, subscribe, call_reducer, table wrappers). Nothing else.

```
## TASK
The section below binds to a GDScript SpacetimeDB SDK. Lines tagged [verify] were written without the docs. Using ONLY the API reference I pasted, correct every [verify] line: signal names, argument order, method names, option field names, and the reducer-call completion signal. Change nothing outside this section. Change no line tagged [confirmed] unless the docs contradict it — if so, say which line and why in a one-line comment above it.
Output the complete corrected section only.
```

### Chunk 2 — `SpaceTimeComponent` base
Reference: `row_event.gd`. Contract: the base contract block from the blueprint.
```
## TASK
Write res://foundation/core/spacetime_component.gd as an @abstract class per the CONTRACT. Include:
1. `bind(entity, initial_rows)` that stores entity/entity_id/is_local_authority, then calls `_on_bound(initial_rows)` (virtual, default no-op).
2. `receive_row_event(ev: RowEvent)` that dispatches to `_on_row_inserted/_on_row_updated/_on_row_deleted` by ev.kind. Only `_on_row_updated` is abstract; the others default to calling it with old=null / new=null respectively.
3. A debug assert in `_ready()` that fails if `entity` is already set (guards against calling bind before the node is in the tree in the wrong order).
```

### Chunk 3 — `SpaceTimeEntity`
Reference: `spacetime_component.gd` (from chunk 2), `entity_registry.gd`.
```
## TASK
Write res://foundation/core/spacetime_entity.gd extending CharacterBody3D.
1. Exports: `definition: EntityDefinition` (assume a Resource with `kind: int` and `scene: PackedScene`; write a TODO(verify) if you need more).
2. `bind(entity_id: int, owner_identity: PackedByteArray, initial_events: Array)`:
   a. set is_local_authority = EntityRegistry.is_local(entity_id)
   b. collect children of $Components, call their required_tables(), build a Dictionary[StringName, RefCounted] of initial rows from initial_events
   c. call bind() on each component in tree order
   d. call EntityRegistry.register(entity_id, self)
   e. free $CameraRig if not local; free $Nameplate if local (use get_node_or_null)
   f. emit `bound` and SignalBus.entity_spawned(entity_id, definition.kind)
3. `receive_row_event(ev)`: forward to every component whose required_tables() contains ev.table.
4. `bind_timeout_sec = 2.0`: if not all required tables have an initial row, start a timer; on timeout, bind anyway with what you have and push_warning listing the missing tables.
```

### Chunk 4 — `EntitySpawner` autoload
Reference: `entity_registry.gd`, `spacetime_entity.gd`.
```
## TASK
Write res://foundation/core/entity_spawner.gd (autoload, goes after EntityRegistry).
1. Export `definitions: Array[EntityDefinition]`; build a Dictionary[int, EntityDefinition] by kind in _ready.
2. Connect EntityRegistry.entity_row_inserted → instantiate definition.scene, add to a `world_root: Node3D` found via a `@export var world_root_path: NodePath`, then call entity.bind(entity_id, owner, EntityRegistry.peek_buffered(entity_id)).
3. Connect EntityRegistry.entity_row_deleted → queue_free the node and emit SignalBus.entity_despawned.
4. Do nothing before SpaceTimeSync.world_ready has fired; buffer entity_row_inserted events until then, then flush.
5. Unknown kind → push_error and skip.
```

### Chunk 5 — `SpaceTimeHealthComponent` (best first real component — fully passive)
Reference: `spacetime_component.gd`, `signal_bus.gd`. Contract: the Health block from the blueprint.
```
## TASK
Write res://foundation/components/spacetime_health_component.gd and res://foundation/components/health_config.gd per the CONTRACT.
1. required_tables() returns [&"health_state"].
2. `_on_row_updated`: compute delta = new.current - old.current (old may be null on first bind → delta 0). Emit local signals: health_changed always; damaged if delta < 0; healed if delta > 0; died when is_dead flips false→true; revived when true→false. Then emit the matching SignalBus signals with entity_id first.
3. Read API per CONTRACT. No prediction. No client-callable damage method.
4. Cache the last row in a private var so read API works without touching the SDK.
```

### Chunk 6 — Health component test
Reference: `test_runner.gd` (the FakeRow pattern), the component from chunk 5.
```
## TASK
Add a `_run_health_component_tests()` suite to test_runner.gd and call it from _init(). Cases: first bind emits health_changed with delta 0 and no damaged/healed; 100→75 emits damaged(25) and not healed; 75→100 emits healed(25); is_dead false→true emits died with killer_id = last_damage_source; true→false emits revived. Use a FakeHealthRow class with the six fields from the health_state table. Output the complete test_runner.gd.
```

### Chunk 7 — `SpaceTimeMovementComponent`, REMOTE_INTERPOLATED only
Reference: `movement_state.gd`, `movement_config.gd`, `clock_sync.gd`, `spacetime_component.gd`.
```
## TASK
Write res://foundation/components/spacetime_movement_component.gd implementing ONLY Mode.REMOTE_INTERPOLATED and Mode.SERVER_DRIVEN (identical behaviour). Leave LOCAL_PREDICTED as `push_error("not implemented")` for now.
1. Snapshot buffer: Array of {server_usec: int, state: MovementState}, max 32, sorted by server_usec. Push on every _on_row_updated using new.server_ts.
2. _physics_process: render_time = ClockSync.server_usec() - int(config.remote_interp_delay * 1e6). Find the two snapshots bracketing render_time, lerp pos (Vector3.lerp) and yaw (lerp_angle), write to entity.global_position and rotation.y. If render_time is past the newest snapshot, extrapolate with vel for at most 100 ms, then hold.
3. Emit jumped when grounded flips true→false with vel.y > 0; landed(impact_speed=abs(old vel.y)) when false→true. Mirror to SignalBus.
4. get_render_state() returns the interpolated state; get_authoritative_state() returns the newest snapshot.
5. teleport_flag == true on a row → clear buffer, snap, emit SignalBus.entity_teleported.
```

### Chunk 8 — `animation_set_builder.gd` EditorScript
Reference: `movement_config_codegen.gd` (EditorScript pattern), `docs/ANIMATION_SPEC.md` §3.
```
## TASK
Write res://foundation/tools/animation_set_builder.gd, an @tool EditorScript.
1. Export `library_path: String` and `output_path: String`. Load the AnimationLibrary.
2. For each semantic name in the ANIMATION_SPEC §3 minimum list, pick the best clip by case-insensitive fuzzy match on these aliases: idle→[idle]; walk→[walk]; run→[run, sprint, jog]; jump.start→[jump, jump_start]; jump.loop→[jump_idle, jump_loop, fall]; jump.land→[jump_land, land]; react.hit→[hitreact, hit, hurt]; react.death→[death, die]; interact→[interact, pickup, use].
3. Build an AnimationSet resource (clips Dictionary[StringName, AnimationClipRef] with loop=true for locomotion/jump.loop, blend_time 0.15) and ResourceSaver.save it to output_path.
4. print() a table of semantic → clip, and a list of unmatched semantics. Do not invent clips for unmatched entries.
```

### Chunk 9 — Rust: timing-bar Challenge validator + golden test
Reference: `sim.rs` (frozen twin, for style), `tests/golden.rs`, `docs/PHASE3_SPEC.md` Task 1 (`validate_challenge`).
```
## TASK
Write server/src/challenge.rs with `pub fn validate_timing_bar(seed: u64, difficulty: f32, result: &[f32]) -> Option<f32>`:
1. Derive target window from seed with a small xorshift64 PRNG: center in [0.2, 0.8], half_width = 0.15 * (1.0 - difficulty).clamp(0.02, 0.15). f32 only.
2. result[0] is the player's stop position in [0,1]. Outside [0,1] → None. quality = 1.0 - (|stop - center| / half_width).clamp(0.0, 1.0); return Some(quality) (0.0 = miss).
3. Add tests/golden_challenge.rs reading shared/golden/challenge_timing.json (format: {"cases":[{"seed","difficulty","result","expected"}]}) with tolerance 1e-6, and write 6 cases into that JSON by running the function once and pasting the outputs (note in the file that GDScript must reproduce them).
Output challenge.rs, then the test file, then the JSON.
```

---

## 4. What NOT to hand to the local model

- The reconciliation core (`LOCAL_PREDICTED` mode: history buffer, three-band error handling, re-simulation, visual offset decay). This is the one piece where a subtle bug produces rubberbanding that looks like "netcode is bad" and is very hard to debug after the fact. Bring the finished Phase 3 back to a frontier model with the golden harness results, and get Phase 4 written as a spec + reference implementation there. The local model can then write the tests for it.
- Anything requiring SpacetimeDB 2.x Rust API knowledge beyond what's already in `lib.rs`. It will produce 1.x-style code that almost compiles.
- The sidecar's `SERVER_AUTHORITY` mode and `AuthoritySync` batching (Phase 3 Task 13) — same reasoning as reconciliation: subtle ordering bugs, hard to see after the fact.
- Multi-file refactors. Split into one-file tasks or don't do them.

---

## 5. Loop discipline

1. One chunk per chat. New chat = system prompt again.
2. Run `tests/run_tests.sh` / `cargo test` after every chunk. Paste the first error only, not the whole log.
3. If it asks a question, answer it in one sentence and re-paste the TASK block.
4. Three failed corrections on the same file → stop. The task is under-specified or beyond the model. Tighten the contract or escalate.
5. After each chunk passes, ask it (with `/no_think`): "List every `TODO(verify)` you left in this file." Resolve those before the next chunk.
