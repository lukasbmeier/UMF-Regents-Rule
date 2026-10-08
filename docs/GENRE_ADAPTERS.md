# Genre Adapters — how target genres map onto the foundation

Purpose: keep genre-specific work out of the foundation, and make sure the foundation has what every genre needs. Everything in the "Foundation" column of §6 is Phase 3 scope (see `PHASE3_SPEC.md`); the rest is a genre layer built on top.

Recurring pattern for any new mechanic: **static def table + state table + intent reducer + client reacts to the row.** Never client-side authority.

## 1. Fishing — round-based competitive, gear upgrades
- **Camera/movement:** 3rd person; Tier A; CSP optional (spot-to-spot teleport is fine). Shippable before Phase 4.
- **Tables:** `fish_def` (rarity, value curve, size range), `catch` (append-only: match, entity, fish, size, quality, round), `gear` (rod/line/lure tiers). Uses foundation `session`, `session_member`, `challenge`, `inventory_item`.
- **Reducers:** `cast(spot_id)` → server rolls bite time + species from `session.seed + gear + spot` → `issue_challenge(kind REEL)`. `submit_challenge_result` → server re-simulates `ReelModel` (pure, golden-vectored, GDScript+Rust) over the trace → quality → `catch` + score/coins. `buy_upgrade` gated to SHOP phase. `advance_phases` drives rounds.
- **Prediction:** none; "reeling…" until `catch` row (~100 ms).
- **Security:** rarity rolled server-side; `challenge` under RLS so others can't see the fish early.
- **Subscriptions:** core set by `world_id` (= match). 
- **UI events:** `session_phase_changed`, `session_score_changed`, `catch` insert → `SignalBus.entity_caught_fish(eid, fish_def_id, quality)` (genre bus extension).

## 2. 8-player survival fantasy — open world, bosses, raids
- **Camera/movement:** 3rd person; **sidecar** authority + CSP; real terrain collision from the level scene; `SWIM`/`CLIMB` move_states with GDScript goldens.
- **Tables:** `world_instance` (seed, party, persistent), `party`, `status_effect`, `telegraph` (shape, pos, ends_at — clients render danger zones from data), `container`, `loot_table`, `quest_def`/`quest_progress`. Uses `ability_def/ability_state/action_event`, `npc_brain`, `inventory_item`, `health_state`.
- **Reducers:** `use_ability` (server resolves hit via proxy geometry: AABB raycast LOS, sphere overlap melee), `interact` (distance-checked), `loot_container`, `npc_think` boss phase machines writing `telegraph`, `party_invite/accept`.
- **Prediction:** action *start* predicted with revocation; hit reactions authoritative; ability `wind_up_ms >= RTT`.
- **NPC navigation:** sidecar uses `NavigationServer3D` on the level navmesh; LOS via raycast.
- **Subscriptions:** one set `WHERE world_id = X`; 8 players need no spatial partitioning.
- **Persistence:** the DB is the save; entities persist through disconnect (already default).

## 3. MMO-lite — 100 players, harvesting minigames
- **Camera/movement:** 3rd person; **sidecar** authority (one process per zone) + CSP; `MOUNT` state with config profile swap. Consider server tick 15 Hz, `input_batch_size` 4 (≈1,500 reducer calls/s at 100 players).
- **Interest management (defining problem):** `movement_state.cell: u32` computed in `tick_movement`; `InterestManager.build_queries()` override returns 3×3 neighbourhood queries; on cell crossing subscribe new set, unsubscribe old after `applied`. Rows leaving scope arrive as deletes → spawner despawns (reuses reconnect-teardown path).
- **Tables:** `resource_node` (pos, type, tier, state, respawn_at), `skill_progress`, `player_profile`, `craft_job` (completes_at), `chat_message` (append-only, RLS by channel). Dungeons = `session` with own `world_id`.
- **Reducers:** `interact(node)` → `issue_challenge(kind MINING)` → `submit_challenge_result` → `grant_item`, deplete node, schedule respawn via per-row `ScheduleAt` timestamp. `craft(recipe)` → `craft_job` completed by scheduled reducer.
- **Prediction:** movement only.

## 4. Chicken vs predators — friend slop
- **Camera/movement:** 3rd person; Tier A; small maps; model branches `flap` (limited air charges), `dash` impulse, optional `glide` — config-driven, goldens required.
- **NPCs:** minimal `npc_brain` kinds: chase-nearest (wolf/coyote/raccoon), dive-on-timer (eagle). Capture = server sphere overlap in tick → `health_state` or `captured` state + respawn. **Build this genre's predators before survival's bosses.**
- **Collectibles:** `pickup` (pos, kind, state); server overlap check in tick (spatial hash) → score. Client predicts pickup visually; on contention the loser's pickup reappears.
- **Egg-throw:** `SpaceTimeActionComponent` + projectile as server-driven entity on a kinematic parabola (tiny shared model).
- **Physics props:** possible only in a sidecar world (server-owned `RigidBody3D`, transforms written to a `prop_state` table at ≤ 20 Hz). Tier A worlds: kinematic only.
- **Session:** LOBBY → PLAYING → RESULTS via foundation phase machine.

## 5. Cross-cutting notes
- 1st vs 3rd person is a `CameraRig` resource swap; `look_pitch` in `InputFrame` supports 1st-person aim.
- All movement variants live in the one shared model behind config flags; per-genre model forks are forbidden (parity cost).
- Any client-side minigame with economic consequences uses the Challenge pattern with server re-simulation, not plausibility checks.

## 6. Ownership matrix
| Foundation (Phase 3) | Genre layer |
|---|---|
| `world_id` on entity tables | `fish_def`, `resource_node`, `pickup`, `telegraph` |
| `session` + phase machine + `SessionComponent` | round rules, lobby UI, phase durations per kind |
| `challenge` + `submit_challenge_result` + RLS + timing-bar validator | `ReelModel`, mining rhythm validator |
| `item_def` / `inventory_item` + grant/consume/equip | loot tables, shop pricing |
| `npc_brain` table + sidecar `NpcBrainComponent` | predator steering, boss scripts (all under `sidecar/`) |
| `SpaceTimeActionComponent` + `ability_def/action_event` + melee ability 0 | ability content |
| `InterestManager` (world_id set; overridable `build_queries`) | 3×3 cell strategy |
| `look_pitch`; `flap/dash/swim/mount` model branches (Phase 4) | camera rigs, tuning |
