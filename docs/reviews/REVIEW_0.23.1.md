# Review of UMF 0.23.1 — findings, checks, improvements

Reviewer: the architecture author, reading the export without a toolchain. Nothing here was executed; every claim about behaviour is from reading the code and the decision log. Where I say "verify", run it and attach the log.

Verdict: the foundation is real, the fishing game is shippable to friends, and four of the architecture's original assumptions were corrected with measurements (DECISIONS #70, #80, #81, #180) — those corrections are better than the theory they replaced. The items below are what stands between this and (a) strangers playing, (b) a second genre starting from it as a template.

Work the sections in order. Each item names the file, what to do, and how to prove it.

---

## A. Evidence I need back with the next export

| # | Ask | Why |
|---|---|---|
| A1 | `tests/run_tests.sh`, `cargo test`, `integration_test.sh`, `e2e_test.sh`, `multiclient_test.sh`, `sidecar_test.sh`, `export_test.sh` logs, committed under `tests/last_run/` or attached | The export has no logs; "~1200 checks green" is a claim I cannot check |
| A2 | `cargo check --target wasm32-unknown-unknown` output and the pinned `spacetime version` | RLS rides on the `unstable` feature (A5 below) |
| A3 | `.gitignore`, `.gitattributes`, any CI config | Missing from the export (dotfiles were dropped); confirm they exist |

---

## B. Before anyone you don't know plays

### B1 — Dev reducers are live and self-targeting
`server/src/module.rs`: `teleport` (line ~1148) and `dev_nudge` (~1168) are callable by any player on their own entity. In a MODULE-authority (Tier A) world that defeats the rod-reach gate (#143): stand at the Deep Hole.
- Gate both behind `require_admin`, or emit a `cfg(dev)` from `build.rs` (driven by an `UMF_DEV` env var or a field in `shared/game.json`) and compile them out of the published build. The e2e/playtest suites that depend on them run against `umf-test`, so they can publish with the flag on.
- Prove: `integration_test.sh` asserts `teleport` from a non-admin identity returns an error on the production-shaped build.

### B2 — Tier A validates speed, not place
`tick_movement` / the speed envelope (#70) accepts any `client_pos` reachable at sprint speed. Nothing stops a modified client walking across the lake. The module already compiles the level bake in (`$OUT_DIR/levels.rs`, `LevelBake`), so a **walkable mask** is one grid lookup per frame: refuse (clamp to last valid) a `client_pos` whose bake cell is water deeper than wading depth or outside the playable bounds.
- Where: in the envelope step, after the speed clamp, using `level::by_id(world_level.level_id)`.
- Prove: a server test walks a claimed position onto the Deep Hole and asserts it is clamped; a golden-level probe (`shared/golden/level/`) pins the wading depth.
- Note in `docs/ARCHITECTURE.md §5` that Tier A = speed envelope + walkable mask.

### B3 — Rate limits on client-callable reducers
`server/src/game/fishing.rs::show_fight` (~876) writes a public row with no minimum interval; a client can spam transactions that broadcast to the whole world. Sweep every `#[reducer]` a player may call (`set_player_name`, `set_appearance`, `set_equip_state`, `set_item_slot`, `interact`, `use_ability`, `cast`, `show_fight`, `set_ready`, `set_team`, …) for: string/array length caps, finite-float checks (present on `show_fight`, good), and a per-entity minimum interval where the row is public.
- Pattern: a `last_<thing>_at: Timestamp` on the row (or a private `rate` table keyed by entity + reducer id); refuse with a clear `Err` under the interval.
- Prove: integration assertions per reducer.

### B4 — Dev tooling ships in the client build
`export_presets.cfg`: neither preset excludes `addons/godot_ai/*` (MCP bridge; inert without the debugger channel but still shipped, source and all) or `demo/*` (Terrain3D's demo scene, which does not belong at the repo root at all).
- Delete `demo/` (it is the addon's sample, not ours). Exclude `addons/godot_ai/*` from both presets. The `_mcp_game_helper` autoload will then fail to load in exports — either strip that autoload entry in a pre-export step, or keep only `addons/godot_ai/runtime/game_helper.gd` (check Godot's include/exclude precedence; test it).
- Prove: `tests/export_test.sh` lists the PCK and asserts neither path is present.

### B5 — RLS on an unstable feature
`Cargo.toml`: `spacetimedb = { version = "2.10", features = ["unstable"] }` for `#[client_visibility_filter]`. Pin the exact patch (`=2.10.1`) and keep the anonymous-identity control (#32) as a permanent integration assertion so an SDK bump that silently disables filters fails CI rather than leaking every player's `challenge` rows.

### B6 — Token file on shared machines
README already warns two copies on one machine share `user://` token. Consider keying the token file by `--db` and host as well, so pointing one install at two servers does not reuse an identity the other server never issued.

---

## C. Maintainability — do these before the second genre

### C1 — `AGENTS.md` is 11,400 words
It is read at the start of every session; at ~15K tokens it is a third of a small model's context and a tax on every frontier session. It has accreted ~30 topical rule sections (held items, gaits, fishing presentation, the nature kit…).
- Target: `AGENTS.md` ≤ 2,500 words — what this is, current state (one paragraph + a pointer), hard rules, verify loop, file map, where to look.
- Move each topical section to `docs/rules/<topic>.md` (or into the system's own spec) and list them in a single "rules index" table with a one-line scope each, so an agent loads only the rule file its task touches.
- `docs/DECISIONS.md` (184 rows, 27K words) needs a by-system index at the top: movement, netcode, sidecar, fishing, animation, UI, tooling → row numbers.

### C2 — Split the two monoliths
- `tests/test_runner.gd` (9,608 lines, 56 suites, 1,121 checks): one file per suite under `tests/suites/`, the runner discovers and runs them. Keeps the no-framework decision (#45) while making a failing suite findable.
- `server/src/module.rs` (2,622 lines): `module/{world,authority,session,inventory,challenge,movement}.rs` with `module/mod.rs` re-exporting. Reducers and tables can live in separate files; the macros do not care.

### C3 — CI
None visible. Minimum: GitHub Actions (or equivalent) with two jobs — `cargo test` + `tests/genres_test.sh` (no server), and a Godot headless job that installs the pinned Godot and `spacetime` CLI, runs `spacetime start`, then `run_tests.sh`, `integration_test.sh`, `e2e_test.sh`. The codegen.md headless flow (`--import`, then `cli.gd`) is already documented in `addons/README.md`.

### C4 — Config drift guard
#81 found the client ignored `shared/movement_config.json`. Add a unit check that loads the JSON and asserts `MovementConfig` field-by-field equals it, so the next "codegen'd .tres nothing reads" cannot recur silently.

---

## D. Template readiness

| # | Item | Where |
|---|---|---|
| D1 | `game/world/kits/*` (medieval village, fantasy props) lack `ATTRIBUTION.md`; the template's own standard (`game/anim/ATTRIBUTION.md`) requires source + licence per pack | add one per kit |
| D2 | The lakeside is generator-written (`tools/world/build_lakeside.gd`, 1,256 lines) and re-running erases editor edits; HANDBOOK §11.1 knows. Decide: freeze the generator output as the editable scene, or keep the generator and mark the scene read-only | before the subtree split |
| D3 | Genres are per game, not per world (HANDBOOK §11.2). Fine for now; record the intended design (per-world genre column + hooks filtered by world) in `GENRE_ADAPTERS.md` so game 2 does not fork around it | docs |
| D4 | `shared/fishing/*.json`, `shared/rules.json` have no schema validation. Add a `build.rs` validation pass (types, ranges, referenced ids exist) so bad content fails the build rather than the round | `server/build.rs` |
| D5 | `TEMPLATE_WORKFLOW.md` step 3 (tag `foundation-v1.0`, subtree split) is still open. Do C1–C3 first; a template that ships a 15K-token agent file and a 9,600-line test file propagates both | after C |

---

## E. Spec drift to write back
The implementation is ahead of the specs in these places. Confirm each doc says what the code does, or update it:

| Learned (DECISIONS) | Doc to update |
|---|---|
| Tier A = speed envelope, grounded derived from vertical motion; twin moves only undriven entities (#70) | `ARCHITECTURE.md §5`, `SIDECAR_SPEC.md §4` |
| Correction epochs on `InputFrame`/`movement_state`; replay budget bounded by elapsed time (#71, #72) | `PHASE4_SPEC.md §1` pseudocode |
| Ground plane only without a resolver; `grounded = is_on_floor()` (#80) | `PHASE4_SPEC.md §2`, `movement_model.gd` header |
| Bind replays every row per table in order; `optional_tables()` (#69, #180) | `ARCHITECTURE.md §7` base contract |
| Remote timelines on seq, Hermite + projective blend (#75, #76) | `PHASE4_SPEC.md §4` |
| `run/main_scene.dedicated_server` instead of a boot branch | `SIDECAR_SPEC.md §1` |
| Module vector type named `Vector3` so codegen maps natively (#40) | `ARCHITECTURE.md §8` wire types |
| `shared/movement_config.json` read directly by the client (#81) | `ARCHITECTURE.md`, `AGENTS.md` rule 10 |
| Three gaits, speeds authored to clip travel speed (#100) | `ANIMATION_SPEC.md §2` |
| Fight pinned as f64 hex bytes; no transcendental fns in the twins (#140) | `ARCHITECTURE.md §6` parity rules — add the "no `exp/sin/pow`" rule explicitly |

---

## F. Things to double-check (reading suggested bugs, not confirmed)

- `spacetime_movement_component.gd::_reconcile`: on an epoch change with `teleport == false`, `_pending` is cleared after replay; if a new input was pushed between the row's queueing and `apply_pending_rows()`, confirm it is not lost (it should carry the new epoch).
- `SessionComponent` double-subscribe on reconnect was fixed (#48); confirm the same pattern (`global_row_event` listeners) in `FishingConditions`, `CatchJournal`, lobby, standings is connect-once.
- `check_authorities` marks `authority_online=false` after 5 s. Confirm the client's remote interpolation *holds* (not extrapolates forever) and that `SignalBus.notification_requested` fires once, not every tick.
- `write_movement_batch` is in the foundation adapter and thus in the client PCK. Harmless (module refuses non-authorities) — but confirm `require_authority` runs before any row read, so a probing client cannot distinguish "no such entity" from "not authority".
- `tick_movement` SIDECAR prune iterates `input_queue.world_id().filter(wid)` every tick; at MMO scale, index on `(world_id, received_at)` or prune on a slower schedule.

---

## G. Questions for the owner
1. Is "friends only" the intended audience for the next few months? B1–B3 are the cost of changing that answer; everything else can wait.
2. Which is game 2 — chicken (proves sidecar NPCs + prediction under chaos) or the survival slice (proves abilities + bosses)? D2/D3 decisions depend on it.
3. Should the designer-first priority ("Built for designers") become a stated principle in `ARCHITECTURE.md §1`? It has clearly shaped the last ten versions and deserves to be explicit.
