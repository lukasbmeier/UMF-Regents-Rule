//! Tables and reducers — the SpacetimeDB module proper.
//!
//! Compiled ONLY for wasm32 (see lib.rs). Linking the SpacetimeDB host ABI
//! (`datastore_insert_bsatn`, `console_log`, …) into a native binary is impossible, and
//! `cargo test --test golden` links the whole crate. Gating this module is what lets the
//! golden harness run natively against `sim.rs` while `spacetime build` still gets everything.
//!
//! Type-check this file with:  cargo check --target wasm32-unknown-unknown

use crate::sim::{InputFrame, MovementState, Vector3};
use spacetimedb::{client_visibility_filter, reducer, table, Filter, Identity, ReducerContext,
    ScheduleAt, SpacetimeType, Table, TimeDuration, Timestamp};

// `spacetimedb` is pinned in Cargo.toml to the server's minor; `spacetime version` on the host.

// =============================================================================
// CONSTANTS
// =============================================================================

/// The world every player joins until an interest/lobby layer says otherwise.
pub const DEFAULT_WORLD: u32 = 0;

/// `session.phase` for the foundation's default round machine (`session.kind = 0`).
/// A genre adds its own kinds; it never renumbers these.
pub const PHASE_LOBBY: u8 = 0;
pub const PHASE_PLAYING: u8 = 1;
pub const PHASE_RESULTS: u8 = 2;
/// Between rounds: the scores are in, nothing is being played, and a genre may let players spend
/// what they earned. Generic on purpose — a round-based genre almost always wants somewhere to
/// put progression that is not "while the clock is running" (GENRE_ADAPTERS §1 buys rods here,
/// a survival genre would buy upgrades). The foundation only defines WHEN; what may be bought is
/// entirely the genre's business.
pub const PHASE_SHOP: u8 = 3;

pub const SESSION_KIND_DEFAULT: u8 = 0;

/// How long a phase is held when its plan says hold (0 seconds), or a kind has no plan: until a
/// reducer moves it on, in practice. Phase lengths and orders are data: shared/rules.json
/// (DECISIONS #154).
const HOLD_MICROS: i64 = 365 * 24 * 3600 * 1_000_000;

/// `authority.role`
pub const ROLE_ADMIN: u8 = 0;
pub const ROLE_SIDECAR: u8 = 1;

/// A sidecar that has not heartbeated within this window is considered offline.
const AUTHORITY_TIMEOUT_MICROS: i64 = 5_000_000;

/// `equip_state.state`: the client's `EquipComponent.State`, in the same order (DECISIONS #160).
pub const EQUIP_AWAY: u8 = 0;
pub const EQUIP_DRAWING: u8 = 1;
pub const EQUIP_READY: u8 = 2;
pub const EQUIP_STOWING: u8 = 3;

/// `world_config.sim_authority`
pub const SIM_MODULE: u8 = 0;
pub const SIM_SIDECAR: u8 = 1;

/// MODULE authority (Tier A) is a SPEED bound, not a physics check. The module cannot see the
/// level, so it must never decide where a client stands; it only bounds how far a client could
/// legitimately have moved in one CLIENT_DT frame. Slack covers acceleration overshoot and
/// move_and_slide depenetration pushes.
const TRUST_SPEED_SLACK: f32 = 1.5;
/// Falling faster than you can run is not an exploit. Bounded only to stop absurd values.
const TRUST_MAX_FALL_SPEED: f32 = 50.0;
/// Vertical motion below this per frame counts as resting on something. The module cannot see
/// WHAT the client is standing on and does not need to: `grounded` only feeds other clients'
/// jump/land detection and whether an undriven entity falls.
const GROUNDED_EPS: f32 = 1.0e-4;
/// A client produces CLIENT_TICK_HZ frames a second. Draining at most twice that per server
/// tick lets a late burst catch up, while a client that floods frames cannot multiply the
/// per-frame envelope into a speed hack. Leftovers wait for the next tick.
/// The highest phase the foundation's own machine knows. A genre that adds phases numbers from
/// here, exactly as it does for `move_state` and `challenge.kind`.
pub const PHASE_FOUNDATION_MAX: u8 = PHASE_SHOP;

/// Foundation move states run 0..=MOVE_STATE_FOUNDATION_MAX (IDLE..MOUNT, RUN); genres use >= 100.
/// Anything in between is not a state anyone defined, and is not mirrored.
const MOVE_STATE_FOUNDATION_MAX: u8 = 7;
const MOVE_STATE_GENRE_FROM: u8 = 100;
const MAX_FRAMES_PER_TICK: usize =
    (2 * crate::movement_config::CLIENT_TICK_HZ / crate::movement_config::SERVER_TICK_HZ) as usize;
/// Hard cap on queued-but-unprocessed inputs per entity. Protects against flooding.
const MAX_QUEUE_DEPTH: usize = 64;
const MAX_BATCH: usize = 8;

const CLIENT_DT: f32 = 1.0 / crate::movement_config::CLIENT_TICK_HZ as f32;
const SERVER_DT: f32 = 1.0 / crate::movement_config::SERVER_TICK_HZ as f32;

pub mod entity_kind {
    pub const PLAYER: u8 = 0;
    pub const NPC: u8 = 1;
    /// Something you walk up to and use: a fishing spot, an ore vein, a chest. Interacting
    /// with one issues a Challenge. Genres number their own kinds from 100.
    pub const RESOURCE_NODE: u8 = 2;
}

/// How close a player must be to interact. The client raycasts to decide what to PROMPT; this
/// is what decides whether it happens. Data: shared/rules.json `interact_range_m`, which the
/// client's prompt reads too, so the two cannot disagree.
pub const INTERACT_RANGE: f32 = crate::rules::INTERACT_RANGE;

// =============================================================================
// TABLES
// =============================================================================

/// World settings, one row per world (Phase 3 Task 1; Phase 2 had a single row keyed `id: u8`).
/// Every world ticks independently and picks its own motion authority.
#[table(accessor = world_config, public)]
pub struct WorldConfig {
    #[primary_key]
    pub world_id: u32,
    /// SIM_MODULE or SIM_SIDECAR
    pub sim_authority: u8,
    /// SIDECAR worlds only: cleared by `check_authorities` when the sidecar stops heartbeating.
    /// Clients hold remote interpolation while this is false. Always true for MODULE worlds.
    pub authority_online: bool,
    pub server_tick: u64,
    /// Server clock stamp of the last tick; clients feed this into ClockSync.
    pub server_ts: Timestamp,
    /// Where a new player in this world appears, feet on the ground. A LEVEL fact, so it is set
    /// by whoever knows the level — a genre from its level bake (`crate::level`), an admin with
    /// `set_world_spawn` — and defaults to the origin on `ground_y`, which is where every world
    /// spawned before it existed.
    pub spawn: Vector3,
}

/// The spawn a world gets until something that knows its level says otherwise.
fn default_spawn() -> Vector3 {
    Vector3::new(0.0, crate::movement_config::GROUND_Y, 0.0)
}

/// One row per thing that exists in the world. Drives the client-side spawner.
#[table(accessor = entity, public)]
pub struct Entity {
    #[primary_key]
    #[auto_inc]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub kind: u8,
    pub owner: Identity,
    pub spawned_at: Timestamp,
}

#[table(accessor = player, public)]
pub struct Player {
    #[primary_key]
    pub identity: Identity,
    #[unique]
    pub entity_id: u64,
    pub name: String,
    pub online: bool,
}

#[table(accessor = movement_state, public)]
pub struct MovementStateRow {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub pos: Vector3,
    pub vel: Vector3,
    pub yaw: f32,
    pub grounded: bool,
    pub move_state: u8,
    pub last_processed_seq: u32,
    pub server_tick: u64,
    pub server_ts: Timestamp,
    /// Set for one tick after a respawn/teleport so the client snaps instead of smoothing.
    pub teleport_flag: bool,
    /// Bumped every time the server OVERRIDES the owning client: a teleport, a speed clamp, a
    /// correction. The client stamps each input with the epoch it has applied, so the module can
    /// tell a frame sent before the client saw the override from one sent after. Without it,
    /// the client's in-flight frames drag the server back toward the path it just rejected, and
    /// the two chase each other indefinitely (DECISIONS #71).
    pub correction_epoch: u32,
}

#[table(accessor = health_state, public)]
pub struct HealthStateRow {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub current: f32,
    pub max: f32,
    pub is_dead: bool,
    pub last_damage_source: u64,
    pub last_change_server_tick: u64,
}

/// IN HAND OR PUT AWAY (DECISIONS #160): what an entity's `EquipComponent` says, reported by its
/// owner as it changes (`set_equip_state`), so every other client plays a draw as it starts rather
/// than when the verb that needed it arrives. No row: nothing was ever drawn (away). The module
/// stores it and refuses nothing on it: the draw's timing is the owner's client's.
#[table(accessor = equip_state, public)]
pub struct EquipStateRow {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// `EQUIP_AWAY`, `EQUIP_DRAWING`, `EQUIP_READY` or `EQUIP_STOWING`.
    pub state: u8,
}

/// WHICH LEVEL A WORLD RUNS (DECISIONS #175): a baked level's number (`shared/world/<level>.json`
/// `id`), 0 for none (the greybox test level). Public, so a client loads the matching scene
/// (`LevelLoader`). Set by `set_world_level` (admin) or a genre's own level set-up, which both go
/// through `set_world_level_internal`.
#[table(accessor = world_level, public)]
pub struct WorldLevel {
    #[primary_key]
    pub world_id: u32,
    pub level_id: u8,
}

/// THE LOOK A PLAYER CHOSE (DECISIONS #166): the character picker's choice, so every client dresses
/// them the same. What the text means is the GAME's (the client's `EntityDefinition.visual_for`
/// and the look's `apply_appearance`); the module only keeps it short and printable. No row: the
/// look is picked from the entity id, as before there was a picker.
#[table(accessor = appearance, public)]
pub struct AppearanceRow {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub look: String,
}

/// Longest look a player may choose. Every piece swapped and dyed is about 150 characters
/// ("wizard_f;arms=4;arms_dye=2;...", DECISIONS #178); the rest is room for more slots.
pub const MAX_LOOK_LEN: usize = 256;

/// Client inputs awaiting the next tick_movement.
///
/// Public ONLY so a sidecar can read the queue for the world it simulates; the filter below is
/// what keeps it from being a cheat channel. Players never see input rows — not even their own.
///
/// Verified enforced, not assumed: `spacetime sql --anonymous` sees rows in unfiltered public
/// tables but zero rows here. (The `spacetimedb` crate carries a stale
/// "RLS filters are currently unimplemented" TODO; on 2.10.1 they are enforced.)
#[table(accessor = input_queue, public)]
pub struct InputQueueRow {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub frame: InputFrame,
    pub received_at: Timestamp,
}

/// Who is allowed to write authoritative state. Seeded in `init` with the publishing identity
/// as admin; sidecars are added with `register_authority`. `world_id = 0` means every world.
///
/// Public so a sidecar can read its own row — it holds no secrets, only a list of trusted
/// identities, and the module checks `ctx.sender()` on every privileged reducer regardless.
#[table(accessor = authority, public)]
pub struct Authority {
    #[primary_key]
    pub identity: Identity,
    /// ROLE_ADMIN or ROLE_SIDECAR
    pub role: u8,
    /// 0 = authorised for every world.
    #[index(btree)]
    pub world_id: u32,
    pub last_seen: Timestamp,
}

/// One authoritative movement write. The sidecar batches a world's worth of these into a single
/// `write_movement_batch` per server tick (SIDECAR_SPEC §2).
#[derive(SpacetimeType, Clone, Copy, Debug)]
pub struct MovementWrite {
    pub entity_id: u64,
    pub pos: Vector3,
    pub vel: Vector3,
    pub yaw: f32,
    pub grounded: bool,
    pub move_state: u8,
    pub last_processed_seq: u32,
    pub teleport_flag: bool,
}

// =============================================================================
// ACTIONS (PHASE3_SPEC Task 12, PHASE4_SPEC §3)
// =============================================================================

/// `action_event.outcome`. A use that is refused (cooldown, range, dead, unknown ability) is an
/// Err from `use_ability`, never a row: only its caller needs to know, and the reducer's outcome
/// tells it. A row means the action HAPPENED.
pub const OUTCOME_HIT: u8 = 0;
pub const OUTCOME_MISS: u8 = 1;
/// How long an action_event row lives. Long enough for every client to see it; short enough
/// that the table never becomes a combat log.
const ACTION_EVENT_TTL_MICROS: i64 = 5_000_000;

/// Static ability catalogue. Genre content: ability 0 (melee) ships with the foundation, a genre
/// adds its own with `define_ability` or in its `on_init`.
#[table(accessor = ability_def, public)]
pub struct AbilityDef {
    #[primary_key]
    pub ability_id: u32,
    pub cooldown_ms: u32,
    /// Metres from actor to target. 0 = untargeted (always resolves as a MISS in Tier A: the
    /// module has no hit test; the sidecar will).
    pub range: f32,
    /// Presentation time before the effect lands. Content rule: >= 100 ms, so the predicted
    /// start animation covers a round trip before the server's answer arrives (§3).
    pub wind_up_ms: u32,
    pub damage: f32,
    pub data: String,
}

/// Per-entity cooldowns: when each ability may next be used.
#[table(accessor = ability_state, public)]
pub struct AbilityState {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub entity_id: u64,
    pub ability_id: u32,
    pub cooldown_until: Timestamp,
    pub charges: u8,
}

/// Something happened. Append-only, pruned after ACTION_EVENT_TTL_MICROS. `predicted_id` is the
/// actor client's own number for the use, echoed back so it can match the answer to the
/// animation it already started.
#[table(accessor = action_event, public)]
pub struct ActionEvent {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub actor_id: u64,
    pub ability_id: u32,
    pub target_id: u64,
    pub aim: Vector3,
    pub outcome: u8,
    pub predicted_id: u32,
    pub server_ts: Timestamp,
}

#[table(accessor = action_prune_schedule, scheduled(prune_action_events))]
pub struct ActionPruneSchedule {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

/// SERVER-ONLY bookkeeping for the current correction epoch: when the module last overrode this
/// entity, and at which input seq. Private (no `public`): clients never need it.
///
/// After an override the owning client rewinds to the corrected state and REPLAYS its
/// unacknowledged inputs, so the first frame it sends under the new epoch can legitimately be a
/// whole round trip of movement away from where the server is holding the entity. That frame
/// is granted a budget of `seq - from_seq` frames, capped by the real time since `at` — so a
/// client cannot buy distance by skipping seqs (DECISIONS #72).
#[table(accessor = correction)]
pub struct Correction {
    #[primary_key]
    pub entity_id: u64,
    pub epoch: u32,
    pub from_seq: u32,
    pub at: Timestamp,
}

/// Record that the module just overrode `entity_id`, starting `epoch` at input `from_seq`.
fn record_correction(ctx: &ReducerContext, entity_id: u64, epoch: u32, from_seq: u32) {
    let c = Correction { entity_id, epoch, from_seq, at: ctx.timestamp };
    if ctx.db.correction().entity_id().find(entity_id).is_some() {
        ctx.db.correction().entity_id().update(c);
    } else {
        ctx.db.correction().insert(c);
    }
}

/// An outstanding minigame. The client plays it locally and submits its inputs; the module
/// re-simulates them with `crate::challenge` and scores the result (DECISIONS #19).
///
/// ROW-LEVEL SECURITY, and it is load-bearing: the row carries the `seed` that determines the
/// outcome. Without the filter below, every client could read every other player's pending
/// challenge and precompute it — GENRE_ADAPTERS §1 calls this out for fishing ("challenge under
/// RLS so others can't see the fish early"). Unlike `input_queue` this table cannot simply stay
/// private: the owner must read its own row to play at all.
#[table(accessor = challenge, public)]
pub struct Challenge {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub entity_id: u64,
    pub kind: u8,
    pub seed: u64,
    pub difficulty: f32,
    pub issued_at: Timestamp,
    pub expires_at: Timestamp,
    /// Genre-owned JSON. The foundation never parses it.
    pub payload: String,
}

/// A client may see only its own challenges.
#[client_visibility_filter]
const CHALLENGE_IS_PRIVATE: Filter = Filter::Sql(
    "SELECT c.* FROM challenge c JOIN player p ON c.entity_id = p.entity_id WHERE p.identity = :sender",
);

/// Only an authority registered for a world may read that world's input queue.
///
/// The join is on equal `world_id`, so a sidecar must be registered for a SPECIFIC world —
/// `register_authority` enforces that for ROLE_SIDECAR. A wildcard (`world_id = 0`) authority
/// would pass `require_authority` for writes but match nothing here, and a sidecar that can
/// write but cannot read its inputs is a confusing half-broken state.
#[client_visibility_filter]
const INPUT_QUEUE_IS_AUTHORITY_ONLY: Filter = Filter::Sql(
    "SELECT q.* FROM input_queue q JOIN authority a ON a.world_id = q.world_id WHERE a.identity = :sender",
);

/// What an NPC's brain needs in order to CARRY ON after its sidecar restarts, rather than start
/// over: which brain, what it was doing, who it was after, and whatever else that brain keeps
/// (`data`, its own JSON — the module never parses it). Written by the authority at most once a
/// second and only when something changed (`write_npc_brain`, SIDECAR_SPEC §3).
///
/// A wander brain is the case that shows why: it roams around a HOME, and a sidecar that
/// forgot the home on restart would take wherever the NPC happened to be standing as the new
/// one. Restart it a few times and the NPC has walked off across the level.
///
/// Authority-only, like `input_queue` (below): a brain's plans are the server's business, and a
/// client that could read them could read a boss's next move.
#[table(accessor = npc_brain, public)]
pub struct NpcBrainRow {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// Which brain wrote `data`. A different brain on a later run ignores it rather than
    /// misreading it.
    pub brain: String,
    pub state: String,
    pub target_id: u64,
    pub data: String,
    pub updated_at: Timestamp,
}

/// Only an authority registered for a world may read that world's NPC brains. Same join as
/// `input_queue`, for the same reason: a sidecar is registered for a specific world.
#[client_visibility_filter]
const NPC_BRAIN_IS_AUTHORITY_ONLY: Filter = Filter::Sql(
    "SELECT b.* FROM npc_brain b JOIN authority a ON a.world_id = b.world_id WHERE a.identity = :sender",
);

/// Longest `npc_brain.data` accepted. A brain's memory, not a save file.
pub const MAX_BRAIN_DATA: usize = 4096;
/// Longest `brain` / `state` name accepted.
pub const MAX_BRAIN_NAME: usize = 64;

/// Static item catalogue, seeded by `seed_item_defs`. The `data` string is a genre-owned
/// JSON blob (GENRE_ADAPTERS: "static def table + state table + intent reducer"); the
/// foundation only cares about `kind` and `max_stack`.
#[table(accessor = item_def, public)]
pub struct ItemDef {
    #[primary_key]
    pub item_def_id: u32,
    pub kind: u8,
    /// 1 = unstackable. Stacking is enforced in `grant_item`.
    pub max_stack: u32,
    pub data: String,
}

/// One stack. Many rows per entity, so the client component keys them by row id.
#[table(accessor = inventory_item, public)]
pub struct InventoryItem {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub owner_entity_id: u64,
    pub item_def_id: u32,
    pub qty: u32,
    /// -1 = unslotted (in the bag but not placed).
    pub slot: i16,
    pub instance_data: String,
}

/// A match/round/instance. One per world — `world_id` is unique, so "which session am I in"
/// is answerable from the entity's world alone.
#[table(accessor = session, public)]
pub struct Session {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[unique]
    pub world_id: u32,
    pub kind: u8,
    pub phase: u8,
    /// When `advance_phases` will move this session on. Clients render countdowns from it.
    pub phase_ends_at: Timestamp,
    /// Server-rolled. Genre validators derive per-round randomness from this so a client cannot
    /// predict outcomes (fishing rolls bite time and species from it — GENRE_ADAPTERS §1).
    pub seed: u64,
    pub max_members: u16,
    /// Bumped each time the machine re-enters LOBBY. Genre records stamp it so a scoreboard
    /// can say which round a result belongs to.
    pub round: u32,
}

#[table(accessor = session_member, public)]
pub struct SessionMember {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub session_id: u64,
    #[index(btree)]
    pub entity_id: u64,
    pub score: i64,
    pub coins: i64,
}

/// A MEMBER IN THE LOBBY (DECISIONS #174): whether they are ready to start, and their team, for a
/// session kind whose rules give it a lobby (`shared/rules.json`). Made with the membership, gone
/// with it; ready is cleared each time a round's lobby opens. `team` numbers the rules' teams in
/// order (0 when there are none).
#[table(accessor = lobby_member, public)]
pub struct LobbyMember {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    #[index(btree)]
    pub session_id: u64,
    pub ready: bool,
    pub team: u8,
}

/// THE MATCH (DECISIONS #182): the rounds a world plays from the first player's arrival until the
/// last one leaves. A player sees the round counted from 1 in the match (`match_round`: `round -
/// first_round + 1`); `started` is false while the match's first lobby waits for its players. A world
/// with no player online for its rules' `end_after_empty_s` ends its match and waits, so nothing is
/// played or counted while nobody is there. `session.round` itself keeps counting: catches and
/// standings are filed under it, and restarting it would mix this match's round 1 with the last's.
#[table(accessor = session_match, public)]
pub struct SessionMatch {
    #[primary_key]
    pub session_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The session round the match began on.
    pub first_round: u32,
    pub started: bool,
    /// Which match of this session it is: 1, 2, ...
    pub number: u32,
}

/// Since when a session has had no player online (private: the timer for ending its match).
#[table(accessor = session_empty)]
pub struct SessionEmpty {
    #[primary_key]
    pub session_id: u64,
    pub since: Timestamp,
}

#[table(accessor = challenge_prune_schedule, scheduled(prune_challenges))]
pub struct ChallengePruneSchedule {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

#[table(accessor = phase_schedule, scheduled(advance_phases))]
pub struct PhaseSchedule {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

#[table(accessor = authority_check_schedule, scheduled(check_authorities))]
pub struct AuthorityCheckSchedule {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

#[table(accessor = tick_schedule, scheduled(tick_movement))]
pub struct TickSchedule {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

// =============================================================================
// LIFECYCLE REDUCERS
// =============================================================================

#[reducer(init)]
pub fn init(ctx: &ReducerContext) {
    ctx.db.world_config().insert(WorldConfig {
        world_id: DEFAULT_WORLD,
        sim_authority: SIM_MODULE,
        authority_online: true,   // MODULE worlds are always "online": this module IS the authority
        server_tick: 0,
        server_ts: ctx.timestamp,
        spawn: default_spawn(),
    });
    // The publisher is admin. This is the root of trust for every privileged reducer:
    // `spacetime publish` runs as this identity, so whoever deploys the module controls it.
    ctx.db.authority().insert(Authority {
        identity: ctx.sender(),
        role: ROLE_ADMIN,
        world_id: 0,
        last_seen: ctx.timestamp,
    });
    ctx.db.authority_check_schedule().insert(AuthorityCheckSchedule {
        scheduled_id: 0,
        scheduled_at: TimeDuration::from_micros(1_000_000).into(),
    });
    ctx.db.phase_schedule().insert(PhaseSchedule {
        scheduled_id: 0,
        scheduled_at: TimeDuration::from_micros(1_000_000).into(),
    });
    ctx.db.challenge_prune_schedule().insert(ChallengePruneSchedule {
        scheduled_id: 0,
        scheduled_at: TimeDuration::from_micros(5_000_000).into(),
    });
    ctx.db.action_prune_schedule().insert(ActionPruneSchedule {
        scheduled_id: 0,
        scheduled_at: TimeDuration::from_micros(1_000_000).into(),
    });
    // PHASE3_SPEC Task 12: one built-in ability so the action path works out of the box.
    ctx.db.ability_def().insert(AbilityDef {
        ability_id: 0,
        cooldown_ms: 800,
        range: 2.0,
        wind_up_ms: 150,
        damage: 10.0,
        data: "{\"name\":\"melee\"}".to_string(),
    });
    // A default session on the default world, so a client that just connects lands somewhere
    // with a phase machine already running rather than in a null session.
    let sess = ctx.db.session().insert(Session {
        id: 0,
        world_id: DEFAULT_WORLD,
        kind: SESSION_KIND_DEFAULT,
        phase: PHASE_LOBBY,
        phase_ends_at: ctx.timestamp
            + TimeDuration::from_micros(phase_duration_micros(SESSION_KIND_DEFAULT, PHASE_LOBBY).unwrap_or(HOLD_MICROS)),
        seed: ctx.timestamp.to_micros_since_unix_epoch() as u64,
        max_members: 0,   // 0 = uncapped
        round: 1,
    });
    // Its first match, waiting for players (DECISIONS #182).
    begin_match(ctx, sess);
    let interval = TimeDuration::from_micros((1_000_000 / crate::movement_config::SERVER_TICK_HZ) as i64);
    ctx.db.tick_schedule().insert(TickSchedule {
        scheduled_id: 0,
        scheduled_at: interval.into(),   // TimeDuration → ScheduleAt::Interval (loop)
    });
    log::info!("UMF module initialised: sim_authority=MODULE, server_tick_hz={}", crate::movement_config::SERVER_TICK_HZ);
    // The genre layer seeds its own static content last, once the foundation exists.
    crate::game::on_init(ctx);
}

/// Longest name a player may set. Long enough for a nickname, short enough that a nameplate
/// cannot be used to draw a wall of text over somebody else's screen.
pub const MAX_NAME_LEN: usize = 20;

/// Set your own display name. The only thing a player may write about themselves, so it is the
/// one place untrusted text enters the database — and every client renders it over someone's
/// head, which is why it is cleaned here rather than at each of them.
///
/// Names are NOT unique. Enforcing that needs a rejection path, a retry UI and a decision about
/// what happens when two friends both want "Luke"; a nameplate showing two of them is a smaller
/// problem than any of that. The identity is what the module keys on regardless.
#[reducer]
pub fn set_player_name(ctx: &ReducerContext, name: String) -> Result<(), String> {
    let mut p = ctx
        .db
        .player()
        .identity()
        .find(ctx.sender())
        .ok_or("set_player_name: no player row")?;

    // Control characters cover newlines and the bidi overrides that let a name rewrite the line
    // it is drawn on. Whitespace is collapsed so " a   b " and "a b" cannot look like two names.
    let cleaned: String = name
        .chars()
        .filter(|c| !c.is_control())
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if cleaned.is_empty() {
        return Err("set_player_name: a name cannot be blank".into());
    }
    // By CHARACTERS, not bytes: truncating a multi-byte character mid-way would panic.
    let trimmed: String = cleaned.chars().take(MAX_NAME_LEN).collect();
    if trimmed == p.name {
        return Ok(());   // idempotent: clients send this on every connect
    }
    log::info!("player {} is now '{}'", p.entity_id, trimmed);
    p.name = trimmed;
    ctx.db.player().identity().update(p);
    Ok(())
}


/// A client connected. Creates its player row, entity and state on first sight; flips
/// `online` back on for a returning identity.
#[reducer(client_connected)]
pub fn client_connected(ctx: &ReducerContext) {
    if let Some(mut p) = ctx.db.player().identity().find(ctx.sender()) {
        p.online = true;
        let entity_id = p.entity_id;
        ctx.db.player().identity().update(p);
        player_arrived(ctx, entity_id);
        crate::game::on_player_returned(ctx, entity_id);
        return;
    }
    let ent = ctx.db.entity().insert(Entity {
        entity_id: 0,
        world_id: DEFAULT_WORLD,
        kind: entity_kind::PLAYER,
        owner: ctx.sender(),
        spawned_at: ctx.timestamp,
    });
    ctx.db.player().insert(Player {
        identity: ctx.sender(),
        entity_id: ent.entity_id,
        name: String::new(),
        online: true,
    });
    let spawn = ctx
        .db
        .world_config()
        .world_id()
        .find(DEFAULT_WORLD)
        .map(|w| w.spawn)
        .unwrap_or_else(default_spawn);
    ctx.db.movement_state().insert(MovementStateRow {
        entity_id: ent.entity_id,
        world_id: DEFAULT_WORLD,
        pos: spawn,
        vel: Vector3::ZERO,
        yaw: 0.0,
        grounded: true,
        move_state: 0,
        last_processed_seq: 0,
        server_tick: current_tick(ctx, DEFAULT_WORLD),
        server_ts: ctx.timestamp,
        teleport_flag: true,
        correction_epoch: 0,
    });
    ctx.db.health_state().insert(HealthStateRow {
        entity_id: ent.entity_id,
        world_id: DEFAULT_WORLD,
        current: crate::rules::PLAYER_MAX_HEALTH,
        max: crate::rules::PLAYER_MAX_HEALTH,
        is_dead: false,
        last_damage_source: 0,
        last_change_server_tick: current_tick(ctx, DEFAULT_WORLD),
    });
    // Join whatever session owns the default world, if one exists.
    if let Some(sess) = ctx.db.session().world_id().find(DEFAULT_WORLD) {
        let _ = add_member(ctx, &sess, ent.entity_id);
    }
    player_arrived(ctx, ent.entity_id);
    crate::game::on_player_created(ctx, ent.entity_id);
}

#[reducer(client_disconnected)]
pub fn client_disconnected(ctx: &ReducerContext) {
    if let Some(mut p) = ctx.db.player().identity().find(ctx.sender()) {
        p.online = false;
        let entity_id = p.entity_id;
        ctx.db.player().identity().update(p);
        // Persistence policy is the genre's: the foundation keeps the entity, and the hook may
        // despawn it (a party game) or keep it (an MMO).
        crate::game::on_player_left(ctx, entity_id);
    }
}

// =============================================================================
// GAMEPLAY REDUCERS
// =============================================================================

/// Client → server. Frames are queued, not simulated here, so the tick reducer stays the single
/// place where movement is resolved. Invalid frames are dropped silently: returning Err would
/// roll back the whole batch and make one bad frame cost the client three good ones.
#[reducer]
pub fn submit_input(ctx: &ReducerContext, frames: Vec<InputFrame>) -> Result<(), String> {
    let player = ctx
        .db
        .player()
        .identity()
        .find(ctx.sender())
        .ok_or("submit_input: sender has no player row")?;

    if frames.is_empty() || frames.len() > MAX_BATCH {
        return Err(format!("submit_input: batch size {} out of range 1..={}", frames.len(), MAX_BATCH));
    }

    let state = ctx
        .db
        .movement_state()
        .entity_id()
        .find(player.entity_id)
        .ok_or("submit_input: entity has no movement_state")?;

    let mut queued: Vec<InputQueueRow> = ctx.db.input_queue().entity_id().filter(player.entity_id).collect();
    if queued.len() + frames.len() > MAX_QUEUE_DEPTH {
        return Err("submit_input: queue depth exceeded".into());
    }
    let mut last_seq = queued.iter().map(|q| q.frame.seq).max().unwrap_or(state.last_processed_seq);

    for f in frames {
        // Strictly increasing: anything else is a replay. Gaps are ALLOWED. A batch lost to a
        // dropped connection leaves one, and refusing gaps (this used to cap them at one batch)
        // froze a reconnected player forever: every later frame was too far ahead. A gap buys
        // nothing, because each frame is still bounded by the trust envelope and the per-tick
        // frame budget in tick_world_module.
        if f.seq <= last_seq {
            log::debug!("drop input seq={} (last={}) for entity {}", f.seq, last_seq, player.entity_id);
            continue;
        }
        last_seq = f.seq;
        queued.push(ctx.db.input_queue().insert(InputQueueRow {
            id: 0,
            entity_id: player.entity_id,
            world_id: state.world_id,
            frame: f,
            received_at: ctx.timestamp,
        }));
    }
    Ok(())
}

/// Scheduled at SERVER_TICK_HZ. MODULE authority: drains every entity's queue through the frozen
/// gravity-only twin and applies client trust. SIDECAR authority: only prunes inputs older than
/// 2 s so a dead sidecar cannot grow the queue unbounded (the sidecar deletes consumed rows itself
/// via write_movement_batch — Phase 3).
#[reducer]
pub fn tick_movement(ctx: &ReducerContext, _sched: TickSchedule) -> Result<(), String> {
    // Only the scheduler may call this.
    if ctx.sender() != ctx.database_identity() {
        return Err("tick_movement: scheduler only".into());
    }

    // Every world advances on the same schedule but decides independently who simulates it.
    // Collected up front: the loop body updates world_config and movement_state, and mutating a
    // table while iterating it is not something to rely on.
    let worlds: Vec<WorldConfig> = ctx.db.world_config().iter().collect();
    let cfg = crate::movement_config::default_config();

    for mut world in worlds {
        let wid = world.world_id;
        world.server_tick += 1;
        world.server_ts = ctx.timestamp;
        let tick = world.server_tick;
        let authority = world.sim_authority;
        ctx.db.world_config().world_id().update(world);

        if authority == SIM_SIDECAR {
            // Sidecar owns motion. Drop inputs it has evidently abandoned.
            let cutoff = ctx.timestamp - TimeDuration::from_micros(2_000_000);
            for q in ctx.db.input_queue().world_id().filter(wid) {
                if q.received_at < cutoff {
                    ctx.db.input_queue().id().delete(q.id);
                }
            }
            continue;
        }

        tick_world_module(ctx, wid, tick, &cfg);
    }
    Ok(())
}

/// MODULE authority for one world. A client-driven entity's position comes from its client,
/// bounded per frame by `apply_client_trust`; the frozen gravity-only twin only moves entities
/// that nobody is driving.
fn tick_world_module(
    ctx: &ReducerContext,
    world_id: u32,
    tick: u64,
    cfg: &crate::sim::MovementConfig,
) {
    let rows: Vec<MovementStateRow> = ctx.db.movement_state().world_id().filter(world_id).collect();
    for row in rows {
        let mut inputs: Vec<InputQueueRow> = ctx.db.input_queue().entity_id().filter(row.entity_id).collect();
        inputs.sort_by_key(|q| q.frame.seq);

        let mut s = MovementState {
            pos: row.pos,
            vel: row.vel,
            yaw: row.yaw,
            grounded: row.grounded,
            move_state: row.move_state,
        };
        let mut last_seq = row.last_processed_seq;
        let mut epoch = row.correction_epoch;

        if inputs.is_empty() {
            // Nobody's frames landed this tick. For a CONNECTED player that only means batching
            // and the tick drifted past each other: the frames are late, and they carry the
            // client's own gravity when they arrive. Simulating it here as well puts the module
            // one step ahead of the client for a tick, which the client sees as a correction
            // mid-jump. Only an entity nobody is driving (an NPC, a player who has left) falls.
            let driven = ctx.db.player().entity_id().find(row.entity_id).map(|p| p.online).unwrap_or(false);
            if !driven && !s.grounded {
                s = crate::sim::simulate(&s, &InputFrame::default(), cfg, SERVER_DT);
            }
        } else {
            inputs.truncate(MAX_FRAMES_PER_TICK);
            let mut correction = ctx.db.correction().entity_id().find(row.entity_id);
            for q in &inputs {
                ctx.db.input_queue().id().delete(q.id);
                last_seq = q.frame.seq;
                if q.frame.epoch != epoch {
                    // Produced before the client saw our last override: it describes a path the
                    // server has already replaced. Consume it and move nothing. Taking it would
                    // pull the entity back toward the rejected path, the client would then be
                    // corrected toward THAT, and the two would chase each other indefinitely.
                    continue;
                }
                // The first frame of a new epoch carries the client's replay of everything since
                // the override; every later frame is one step.
                let mut frames: f32 = 1.0;
                if let Some(c) = correction.take() {
                    if c.epoch == epoch {
                        let by_seq = q.frame.seq.saturating_sub(c.from_seq).max(1) as f32;
                        let elapsed = (ctx.timestamp.to_micros_since_unix_epoch()
                            - c.at.to_micros_since_unix_epoch()).max(0) as f32 / 1_000_000.0;
                        let by_time = elapsed / CLIENT_DT * TRUST_SPEED_SLACK + MAX_FRAMES_PER_TICK as f32;
                        frames = by_seq.min(by_time).max(1.0);
                    }
                    ctx.db.correction().entity_id().delete(row.entity_id);
                }
                let (next, clamped) = apply_client_trust(&s, &q.frame, cfg, frames);
                s = next;
                if clamped {
                    // We just overrode the client. Everything it sends until it has seen this
                    // row is from the old path; a new epoch is how we will recognise it.
                    epoch = epoch.wrapping_add(1);
                    record_correction(ctx, row.entity_id, epoch, q.frame.seq);
                    correction = ctx.db.correction().entity_id().find(row.entity_id);
                }
            }
        }

        let changed = s.pos != row.pos || s.vel != row.vel || s.grounded != row.grounded
            || last_seq != row.last_processed_seq || epoch != row.correction_epoch || row.teleport_flag;
        if changed {
            ctx.db.movement_state().entity_id().update(MovementStateRow {
                entity_id: row.entity_id,
                world_id: row.world_id,
                pos: s.pos,
                vel: s.vel,
                yaw: s.yaw,
                grounded: s.grounded,
                move_state: s.move_state,
                last_processed_seq: last_seq,
                server_tick: tick,
                server_ts: ctx.timestamp,
                teleport_flag: false,
                correction_epoch: epoch,
            });
        }
    }
}

/// MODULE authority (Tier A): the client's position, bounded by how far a legitimate client
/// could have moved in one frame. Returns the accepted state and whether the claim was CLAMPED.
///
/// A claim inside the envelope is taken exactly, bit for bit: that is what lets the owning
/// client's reconciliation see zero error in normal play. A claim outside it is clamped to the
/// envelope rather than rejected. Rejecting strands the server behind a client that then
/// carries on normally; clamping always converges.
///
/// The previous policy ran the gravity-only twin and trusted `client_pos` within 0.5 m of it.
/// The twin cannot see the level, so for a client standing on anything above `ground_y` its
/// fall velocity kept growing until the positions diverged past the radius, and the module
/// dropped the player through the floor (DECISIONS #70).
fn apply_client_trust(
    prev: &MovementState,
    frame: &InputFrame,
    cfg: &crate::sim::MovementConfig,
    frames: f32,
) -> (MovementState, bool) {
    let claimed = frame.client_pos.sub(prev.pos);
    // The fastest a legitimate client can go: a sprint, plus a dash burst when dashing is on;
    // and upward, a jump or (when flapping is on) a flap.
    use crate::movement_config::{DASH_IMPULSE, FLAP_CHARGES, FLAP_VELOCITY};
    let burst = if DASH_IMPULSE > 0.0 { DASH_IMPULSE } else { 0.0 };
    let lift = if FLAP_CHARGES > 0 { cfg.jump_velocity.max(FLAP_VELOCITY) } else { cfg.jump_velocity };
    let max_h = (cfg.sprint_speed + burst) * TRUST_SPEED_SLACK * CLIENT_DT * frames;
    let max_up = lift * TRUST_SPEED_SLACK * CLIENT_DT * frames;
    let max_down = TRUST_MAX_FALL_SPEED * CLIENT_DT * frames;

    let h_sq = claimed.x * claimed.x + claimed.z * claimed.z;
    let within = h_sq <= max_h * max_h && claimed.y <= max_up && claimed.y >= -max_down;
    let (pos, step) = if within {
        (frame.client_pos, claimed)
    } else {
        let h_scale = if h_sq > max_h * max_h { max_h / h_sq.sqrt() } else { 1.0 };
        // A claim too far to believe is scaled AS A WHOLE: the height of a place the server does
        // not think the player reached is no more credible than its distance. Clamped on its own,
        // a claim 53 m off at the dock's height dropped a player standing by the village 1.35 m
        // into the ground, stuck there (DECISIONS #149). A claim whose distance IS believable
        // keeps its own vertical limits, because a real fall is fast.
        let step = Vector3::new(claimed.x * h_scale, (claimed.y * h_scale).clamp(-max_down, max_up), claimed.z * h_scale);
        (prev.pos.add(step), step)
    };
    let next = MovementState {
        pos,
        // What the client's motion implies. Remote clients extrapolate briefly with it, and an
        // entity whose client disconnects mid-air falls from it.
        vel: step.scale(1.0 / (CLIENT_DT * frames)),
        // Facing follows the camera only while there is movement input — standing still and
        // looking around must not spin the body — or while the frame says something is being
        // aimed (`face`). The client applies this same rule to the same frame, so both sides
        // always agree.
        yaw: if frame.face || frame.move_x != 0.0 || frame.move_y != 0.0 { frame.look_yaw } else { prev.yaw },
        grounded: step.y.abs() < GROUNDED_EPS,
        // The client's model decided what this movement is; the module cannot, so it mirrors it —
        // but only a state someone defined.
        move_state: if frame.move_state <= MOVE_STATE_FOUNDATION_MAX || frame.move_state >= MOVE_STATE_GENRE_FROM {
            frame.move_state
        } else {
            prev.move_state
        },
    };
    (next, !within)
}

/// Switch a world's motion authority. Admin only.
#[reducer]
pub fn set_sim_authority(ctx: &ReducerContext, world_id: u32, mode: u8) -> Result<(), String> {
    require_admin(ctx)?;
    if mode > SIM_SIDECAR {
        return Err(format!("unknown sim_authority {mode}"));
    }
    let mut w = ctx
        .db
        .world_config()
        .world_id()
        .find(world_id)
        .ok_or(format!("no world_config for world {world_id}"))?;
    w.sim_authority = mode;
    // A SIDECAR world is offline until its sidecar heartbeats; a MODULE world is always online.
    w.authority_online = mode == SIM_MODULE;
    ctx.db.world_config().world_id().update(w);
    Ok(())
}

/// Set where new players in a world appear. The genre's own entry point: it knows its levels
/// (see `crate::level`); nothing here checks that the point is on the ground.
/// Point a world at a level: record it, move the world's spawn to the bake's (the default spawn for
/// level 0, which has no bake), and tell every genre (`on_level_changed`: fishing stocks the
/// greybox's ponds, places its rival, rolls the conditions). The caller has decided it may.
pub fn set_world_level_internal(ctx: &ReducerContext, world_id: u32, level_id: u8) -> Result<(), String> {
    let spawn = match crate::level::by_id(level_id) {
        Some(b) => Vector3::new(b.spawn[0], b.spawn[1], b.spawn[2]),
        None if level_id == 0 => default_spawn(),
        None => return Err(format!("unknown level {level_id} (the baked levels: {:?})",
            crate::level::ALL.iter().map(|l| (l.id, l.name)).collect::<Vec<_>>())),
    };
    set_world_spawn_internal(ctx, world_id, spawn)?;
    let row = WorldLevel { world_id, level_id };
    if ctx.db.world_level().world_id().find(world_id).is_some() {
        ctx.db.world_level().world_id().update(row);
    } else {
        ctx.db.world_level().insert(row);
    }
    crate::game::on_level_changed(ctx, world_id, level_id);
    log::info!("world {world_id} now runs level {level_id}");
    Ok(())
}

/// The level a world runs (0 for none).
pub fn world_level_of(ctx: &ReducerContext, world_id: u32) -> u8 {
    ctx.db.world_level().world_id().find(world_id).map(|w| w.level_id).unwrap_or(0)
}

/// Switch a world to a baked level (or 0, none). Admin only. It moves where the NEXT player
/// appears; anyone already connected stays put, so call it before clients connect.
#[reducer]
pub fn set_world_level(ctx: &ReducerContext, world_id: u32, level_id: u8) -> Result<(), String> {
    require_admin(ctx)?;
    set_world_level_internal(ctx, world_id, level_id)
}

pub fn set_world_spawn_internal(ctx: &ReducerContext, world_id: u32, pos: Vector3) -> Result<(), String> {
    if !(pos.x.is_finite() && pos.y.is_finite() && pos.z.is_finite()) {
        return Err("set_world_spawn: spawn must be finite".into());
    }
    let mut w = ctx
        .db
        .world_config()
        .world_id()
        .find(world_id)
        .ok_or(format!("set_world_spawn: no world {world_id}"))?;
    w.spawn = pos;
    ctx.db.world_config().world_id().update(w);
    Ok(())
}

/// Set where new players in a world appear. Admin only. Players already in the world stay where
/// they are: this decides where the NEXT one arrives.
#[reducer]
pub fn set_world_spawn(ctx: &ReducerContext, world_id: u32, pos: Vector3) -> Result<(), String> {
    require_admin(ctx)?;
    set_world_spawn_internal(ctx, world_id, pos)
}

/// Create a world. Admin only.
#[reducer]
pub fn create_world(ctx: &ReducerContext, world_id: u32, sim_authority: u8) -> Result<(), String> {
    require_admin(ctx)?;
    if sim_authority > SIM_SIDECAR {
        return Err(format!("unknown sim_authority {sim_authority}"));
    }
    if ctx.db.world_config().world_id().find(world_id).is_some() {
        return Err(format!("world {world_id} already exists"));
    }
    ctx.db.world_config().insert(WorldConfig {
        world_id,
        sim_authority,
        authority_online: sim_authority == SIM_MODULE,
        server_tick: 0,
        server_ts: ctx.timestamp,
        spawn: default_spawn(),
    });
    Ok(())
}

/// Dev/test helper: place an entity somewhere and flag it as a teleport.
#[reducer]
pub fn teleport(ctx: &ReducerContext, pos: Vector3) -> Result<(), String> {
    let p = ctx.db.player().identity().find(ctx.sender()).ok_or("no player")?;
    let mut m = ctx.db.movement_state().entity_id().find(p.entity_id).ok_or("no movement_state")?;
    m.pos = pos;
    m.vel = Vector3::ZERO;
    m.grounded = false;
    m.teleport_flag = true;
    // An override: frames the client sends before it sees this row are from the old position.
    m.correction_epoch = m.correction_epoch.wrapping_add(1);
    m.server_ts = ctx.timestamp;
    record_correction(ctx, m.entity_id, m.correction_epoch, m.last_processed_seq);
    ctx.db.movement_state().entity_id().update(m);
    Ok(())
}

/// Dev/test helper: shift YOUR entity's authoritative position without flagging a teleport,
/// the way a server correction would. Exists to prove the owner glides to a correction rather
/// than popping (PHASE4_SPEC section 5). Like `teleport`, a genre must gate or remove this
/// before it ships: any client may call it on itself.
#[reducer]
pub fn dev_nudge(ctx: &ReducerContext, offset: Vector3) -> Result<(), String> {
    let p = ctx.db.player().identity().find(ctx.sender()).ok_or("no player")?;
    let mut m = ctx.db.movement_state().entity_id().find(p.entity_id).ok_or("no movement_state")?;
    m.pos = m.pos.add(offset);
    m.correction_epoch = m.correction_epoch.wrapping_add(1);
    m.server_ts = ctx.timestamp;
    record_correction(ctx, m.entity_id, m.correction_epoch, m.last_processed_seq);
    ctx.db.movement_state().entity_id().update(m);
    Ok(())
}


// =============================================================================
// AUTHORITY (SIDECAR_SPEC §2)
// =============================================================================

/// Sender must hold an admin row.
pub fn require_admin(ctx: &ReducerContext) -> Result<(), String> {
    match ctx.db.authority().identity().find(ctx.sender()) {
        Some(a) if a.role == ROLE_ADMIN => Ok(()),
        _ => Err("admin only".into()),
    }
}

/// Sender must be authorised for `world_id` (or for every world, `world_id = 0`).
/// Every reducer that writes authoritative state begins with this.
fn require_authority(ctx: &ReducerContext, world_id: u32) -> Result<(), String> {
    match ctx.db.authority().identity().find(ctx.sender()) {
        Some(a) if a.world_id == 0 || a.world_id == world_id => Ok(()),
        Some(_) => Err(format!("not authorised for world {world_id}")),
        None => Err("not an authority".into()),
    }
}

/// Add or update a trusted identity. Run once per sidecar from the publishing machine:
///   spacetime call umf register_authority <identity-hex> 1 1
#[reducer]
pub fn register_authority(
    ctx: &ReducerContext,
    identity: Identity,
    role: u8,
    world_id: u32,
) -> Result<(), String> {
    require_admin(ctx)?;
    if role > ROLE_SIDECAR {
        return Err(format!("unknown role {role}"));
    }
    // Demoting yourself would drop admin rights with no way to get them back short of a
    // republish — `require_admin` is the only gate on this reducer.
    if identity == ctx.sender() && role != ROLE_ADMIN {
        return Err("refusing to drop your own admin role".into());
    }
    // A sidecar must name its world: the input_queue RLS filter joins on equal world_id, so a
    // wildcard sidecar could write movement but would never see an input to act on.
    if role == ROLE_SIDECAR && world_id == 0 {
        return Err("a sidecar must be registered for a specific world, not the 0 wildcard".into());
    }
    if let Some(mut a) = ctx.db.authority().identity().find(identity) {
        a.role = role;
        a.world_id = world_id;
        ctx.db.authority().identity().update(a);
    } else {
        ctx.db.authority().insert(Authority { identity, role, world_id, last_seen: ctx.timestamp });
    }
    Ok(())
}

#[reducer]
pub fn revoke_authority(ctx: &ReducerContext, identity: Identity) -> Result<(), String> {
    require_admin(ctx)?;
    if identity == ctx.sender() {
        return Err("refusing to revoke your own authority".into());
    }
    ctx.db.authority().identity().delete(identity);
    Ok(())
}

/// Sidecar liveness ping, 1 Hz (SIDECAR_SPEC §3).
#[reducer]
pub fn heartbeat(ctx: &ReducerContext, world_id: u32) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    let mut a = ctx.db.authority().identity().find(ctx.sender()).ok_or("not an authority")?;
    let is_sidecar = a.role == ROLE_SIDECAR;
    a.last_seen = ctx.timestamp;
    ctx.db.authority().identity().update(a);

    // Only a SIDECAR heartbeat may bring a world online, because only a sidecar simulates it.
    // `check_authorities` applies the same rule; if this accepted an admin ping, the two would
    // disagree and the world would flip online→offline within the same second, republishing
    // `world_config` to every subscribed client each time.
    if is_sidecar {
        if let Some(mut w) = ctx.db.world_config().world_id().find(world_id) {
            if !w.authority_online {
                w.authority_online = true;
                ctx.db.world_config().world_id().update(w);
                log::info!("world {world_id}: authority back online");
            }
        }
    }
    Ok(())
}

/// Scheduled 1 Hz. Marks SIDECAR worlds offline once their sidecar stops heartbeating, so
/// clients can freeze remote interpolation instead of extrapolating into nonsense.
/// MODULE worlds are always online — this module is their authority.
#[reducer]
pub fn check_authorities(ctx: &ReducerContext, _sched: AuthorityCheckSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("check_authorities: scheduler only".into());
    }
    let cutoff = ctx.timestamp - TimeDuration::from_micros(AUTHORITY_TIMEOUT_MICROS);
    let worlds: Vec<WorldConfig> = ctx.db.world_config().iter().collect();

    for mut w in worlds {
        if w.sim_authority != SIM_SIDECAR {
            continue;
        }
        let live = ctx.db.authority().iter().any(|a| {
            a.role == ROLE_SIDECAR && (a.world_id == 0 || a.world_id == w.world_id) && a.last_seen >= cutoff
        });
        if w.authority_online != live {
            w.authority_online = live;
            let wid = w.world_id;
            ctx.db.world_config().world_id().update(w);
            log::warn!("world {wid}: authority_online -> {live}");
        }
    }
    Ok(())
}

/// The sidecar's motion write-back: one call per world per server tick. Also prunes the inputs
/// it has consumed, which is what keeps `input_queue` bounded under SIDECAR authority.
#[reducer]
pub fn write_movement_batch(
    ctx: &ReducerContext,
    world_id: u32,
    writes: Vec<MovementWrite>,
) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    let tick = current_tick(ctx, world_id);

    for w in writes {
        let Some(row) = ctx.db.movement_state().entity_id().find(w.entity_id) else {
            continue;   // entity despawned between the sidecar's read and this write
        };
        if row.world_id != world_id {
            continue;   // authority for one world may not move an entity in another
        }
        ctx.db.movement_state().entity_id().update(MovementStateRow {
            entity_id: w.entity_id,
            world_id,
            pos: w.pos,
            vel: w.vel,
            yaw: w.yaw,
            grounded: w.grounded,
            move_state: w.move_state,
            last_processed_seq: w.last_processed_seq,
            server_tick: tick,
            server_ts: ctx.timestamp,
            teleport_flag: w.teleport_flag,
            correction_epoch: if w.teleport_flag { row.correction_epoch.wrapping_add(1) } else { row.correction_epoch },
        });
        let consumed: Vec<u64> = ctx
            .db
            .input_queue()
            .entity_id()
            .filter(w.entity_id)
            .filter(|q| q.frame.seq <= w.last_processed_seq)
            .map(|q| q.id)
            .collect();
        for id in consumed {
            ctx.db.input_queue().id().delete(id);
        }
    }
    Ok(())
}

/// Damage from an AUTHORITY (the sidecar, an admin tool). Players have no damage API at all
/// (ARCHITECTURE §7): their only route to hurting anything is `use_ability`, which validates the
/// action first. Both end in `damage_entity`, the one place health changes.
#[reducer]
pub fn apply_damage(
    ctx: &ReducerContext,
    target_id: u64,
    amount: f32,
    source_id: u64,
) -> Result<(), String> {
    let h = ctx
        .db
        .health_state()
        .entity_id()
        .find(target_id)
        .ok_or("apply_damage: no health_state for target")?;
    require_authority(ctx, h.world_id)?;
    damage_entity(ctx, target_id, amount, source_id)
}

/// The one place health changes. `apply_damage` (authority) and `use_ability` (a validated
/// player action) both come through here.
fn damage_entity(ctx: &ReducerContext, target_id: u64, amount: f32, source_id: u64) -> Result<(), String> {
    let mut h = ctx.db.health_state().entity_id().find(target_id).ok_or("no health_state for target")?;
    if !amount.is_finite() {
        return Err("apply_damage: non-finite amount".into());
    }
    h.current = (h.current - amount).clamp(0.0, h.max);
    h.is_dead = h.current <= 0.0;
    h.last_damage_source = source_id;
    h.last_change_server_tick = current_tick(ctx, h.world_id);
    ctx.db.health_state().entity_id().update(h);
    Ok(())
}

/// Admin: add or change an ability. A genre's content, like `seed_fish_defs`.
#[reducer]
pub fn define_ability(
    ctx: &ReducerContext,
    ability_id: u32,
    cooldown_ms: u32,
    range: f32,
    wind_up_ms: u32,
    damage: f32,
    data: String,
) -> Result<(), String> {
    require_admin(ctx)?;
    if !range.is_finite() || range < 0.0 || !damage.is_finite() {
        return Err("define_ability: range and damage must be finite, range >= 0".into());
    }
    let row = AbilityDef { ability_id, cooldown_ms, range, wind_up_ms, damage, data };
    if ctx.db.ability_def().ability_id().find(ability_id).is_some() {
        ctx.db.ability_def().ability_id().update(row);
    } else {
        ctx.db.ability_def().insert(row);
    }
    Ok(())
}

/// A player uses an ability (PHASE3_SPEC Task 12; Tier A resolution per PHASE4_SPEC §3).
/// `predicted_id` is the client's own number for this use, echoed on the event so its
/// prediction can be confirmed. Refusals are Errs — only the caller needs to know.
#[reducer]
pub fn use_ability(
    ctx: &ReducerContext,
    ability_id: u32,
    target_id: u64,
    aim: Vector3,
    predicted_id: u32,
) -> Result<(), String> {
    let actor = ctx.db.player().identity().find(ctx.sender()).ok_or("use_ability: no player")?.entity_id;
    let def = ctx.db.ability_def().ability_id().find(ability_id).ok_or("use_ability: unknown ability")?;
    if let Some(h) = ctx.db.health_state().entity_id().find(actor) {
        if h.is_dead {
            return Err("use_ability: the dead cannot act".into());
        }
    }
    let state = ctx.db.ability_state().entity_id().filter(actor).find(|a| a.ability_id == ability_id);
    if let Some(st) = &state {
        if st.cooldown_until > ctx.timestamp {
            return Err("use_ability: on cooldown".into());
        }
    }
    let me = ctx.db.movement_state().entity_id().find(actor).ok_or("use_ability: actor has no movement_state")?;

    // Tier A resolution is coarse: a targeted ability hits if the target is in range. The
    // sidecar (Task 13) replaces this with a real hit test against the level.
    let mut outcome = OUTCOME_MISS;
    if target_id != 0 && def.range > 0.0 {
        let them = ctx.db.movement_state().entity_id().find(target_id).ok_or("use_ability: no such target")?;
        if them.world_id != me.world_id {
            return Err("use_ability: target is in another world".into());
        }
        if them.pos.sub(me.pos).length_sq() > def.range * def.range {
            return Err("use_ability: out of range".into());
        }
        if def.damage > 0.0 {
            damage_entity(ctx, target_id, def.damage, actor)?;
        }
        outcome = OUTCOME_HIT;
    }

    let until = ctx.timestamp + TimeDuration::from_micros(def.cooldown_ms as i64 * 1000);
    match state {
        Some(mut st) => {
            st.cooldown_until = until;
            ctx.db.ability_state().id().update(st);
        }
        None => {
            ctx.db.ability_state().insert(AbilityState { id: 0, entity_id: actor, ability_id, cooldown_until: until, charges: 0 });
        }
    }
    ctx.db.action_event().insert(ActionEvent {
        id: 0,
        world_id: me.world_id,
        actor_id: actor,
        ability_id,
        target_id,
        aim,
        outcome,
        predicted_id,
        server_ts: ctx.timestamp,
    });
    Ok(())
}

/// Scheduled 1 Hz: drop action events older than ACTION_EVENT_TTL_MICROS.
#[reducer]
pub fn prune_action_events(ctx: &ReducerContext, _sched: ActionPruneSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("prune_action_events: scheduler only".into());
    }
    let cutoff = ctx.timestamp - TimeDuration::from_micros(ACTION_EVENT_TTL_MICROS);
    let stale: Vec<u64> = ctx.db.action_event().iter().filter(|e| e.server_ts < cutoff).map(|e| e.id).collect();
    for id in stale {
        ctx.db.action_event().id().delete(id);
    }
    Ok(())
}

#[reducer]
pub fn spawn_npc(ctx: &ReducerContext, world_id: u32, kind: u8, pos: Vector3) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    spawn_npc_internal(ctx, world_id, kind, pos, 0.0);
    Ok(())
}

/// An NPC's rows, for code that has already decided it may (a genre's level set-up). Returns its id.
pub fn spawn_npc_internal(ctx: &ReducerContext, world_id: u32, kind: u8, pos: Vector3, yaw: f32) -> u64 {
    let ent = ctx.db.entity().insert(Entity {
        entity_id: 0,
        world_id,
        kind,
        owner: ctx.sender(),
        spawned_at: ctx.timestamp,
    });
    ctx.db.movement_state().insert(MovementStateRow {
        entity_id: ent.entity_id,
        world_id,
        pos,
        vel: Vector3::ZERO,
        yaw,
        grounded: true,
        move_state: 0,
        last_processed_seq: 0,
        server_tick: current_tick(ctx, world_id),
        server_ts: ctx.timestamp,
        teleport_flag: true,
        correction_epoch: 0,
    });
    ctx.db.health_state().insert(HealthStateRow {
        entity_id: ent.entity_id,
        world_id,
        current: 100.0,
        max: 100.0,
        is_dead: false,
        last_damage_source: 0,
        last_change_server_tick: current_tick(ctx, world_id),
    });
    ent.entity_id
}

#[reducer]
pub fn despawn_entity(ctx: &ReducerContext, entity_id: u64) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("no such entity")?;
    require_authority(ctx, ent.world_id)?;
    if ctx.db.player().entity_id().find(entity_id).is_some() {
        return Err("refusing to despawn a player entity".into());
    }
    despawn_entity_internal(ctx, entity_id);
    Ok(())
}

/// Every row of an entity, for code that has already decided it may (an authority above, a genre
/// taking its own NPC away).
pub fn despawn_entity_internal(ctx: &ReducerContext, entity_id: u64) {
    ctx.db.entity().entity_id().delete(entity_id);
    ctx.db.movement_state().entity_id().delete(entity_id);
    ctx.db.health_state().entity_id().delete(entity_id);
    ctx.db.input_queue().entity_id().delete(entity_id);
    ctx.db.correction().entity_id().delete(entity_id);
    ctx.db.ability_state().entity_id().delete(entity_id);
    ctx.db.inventory_item().owner_entity_id().delete(entity_id);
    ctx.db.npc_brain().entity_id().delete(entity_id);
    ctx.db.equip_state().entity_id().delete(entity_id);
    ctx.db.appearance().entity_id().delete(entity_id);
    let open: Vec<Challenge> = ctx.db.challenge().entity_id().filter(entity_id).collect();
    for ch in open {
        ctx.db.challenge().id().delete(ch.id);
        crate::game::on_challenge_closed(ctx, &ch);
    }
    let memberships: Vec<u64> =
        ctx.db.session_member().entity_id().filter(entity_id).map(|m| m.id).collect();
    for id in memberships {
        ctx.db.session_member().id().delete(id);
    }
    ctx.db.lobby_member().entity_id().delete(entity_id);
}


// =============================================================================
// SESSIONS (phase machine)
// =============================================================================

/// Shared by `join_session` and the auto-join in `client_connected` (and a genre's NPC that plays
/// the round, like the fishing rival).
pub fn add_member(ctx: &ReducerContext, sess: &Session, entity_id: u64) -> Result<(), String> {
    let already = ctx
        .db
        .session_member()
        .entity_id()
        .filter(entity_id)
        .any(|m| m.session_id == sess.id);
    if already {
        return Ok(());
    }
    if sess.max_members > 0 {
        let count = ctx.db.session_member().session_id().filter(sess.id).count();
        if count >= sess.max_members as usize {
            return Err("session is full".into());
        }
    }
    ctx.db.session_member().insert(SessionMember {
        id: 0,
        session_id: sess.id,
        entity_id,
        score: 0,
        coins: 0,
    });
    // The lobby's row: not ready, on the smallest team.
    let world_id = ctx.db.entity().entity_id().find(entity_id).map(|e| e.world_id).unwrap_or(sess.world_id);
    let team = smallest_team(ctx, sess);
    let row = LobbyMember { entity_id, world_id, session_id: sess.id, ready: false, team };
    if ctx.db.lobby_member().entity_id().find(entity_id).is_some() {
        ctx.db.lobby_member().entity_id().update(row);
    } else {
        ctx.db.lobby_member().insert(row);
    }
    Ok(())
}

/// A member's lobby row, made when it is missing (DECISIONS #184): a member from before the lobby
/// existed (a world republished without a wipe) had none, and Ready said "you are not in a session".
fn ensure_lobby_member(ctx: &ReducerContext, sess: &Session, entity_id: u64) -> LobbyMember {
    if let Some(row) = ctx.db.lobby_member().entity_id().find(entity_id) {
        return row;
    }
    let world_id = ctx.db.entity().entity_id().find(entity_id).map(|e| e.world_id).unwrap_or(sess.world_id);
    let team = smallest_team(ctx, sess);
    ctx.db.lobby_member().insert(LobbyMember { entity_id, world_id, session_id: sess.id, ready: false, team })
}

/// The session `entity_id` is a member of, and its lobby row (made if missing), for a lobby reducer.
fn lobby_of(ctx: &ReducerContext, entity_id: u64, verb: &str) -> Result<(Session, LobbyMember), String> {
    let member = ctx.db.session_member().entity_id().filter(entity_id).next()
        .ok_or(format!("{verb}: you are not in a session"))?;
    let sess = ctx.db.session().id().find(member.session_id).ok_or(format!("{verb}: no such session"))?;
    let row = ensure_lobby_member(ctx, &sess, entity_id);
    Ok((sess, row))
}

/// The team with the fewest members in `sess` (0 when its kind has no teams).
fn smallest_team(ctx: &ReducerContext, sess: &Session) -> u8 {
    let Some(lobby) = crate::rules::lobby(sess.kind) else { return 0 };
    if lobby.teams.is_empty() {
        return 0;
    }
    let mut counts = vec![0usize; lobby.teams.len()];
    for m in ctx.db.lobby_member().session_id().filter(sess.id) {
        if (m.team as usize) < counts.len() {
            counts[m.team as usize] += 1;
        }
    }
    counts.iter().enumerate().min_by_key(|(_, c)| **c).map(|(i, _)| i as u8).unwrap_or(0)
}

/// Whether every PLAYER in a lobby that starts on ready is ready, and there are enough of them. NPC
/// members (a fishing rival) and players who are not online are not waited for.
fn lobby_all_ready(ctx: &ReducerContext, sess: &Session) -> bool {
    let Some(lobby) = crate::rules::lobby(sess.kind) else { return false };
    if !lobby.ready_up || sess.phase != PHASE_LOBBY {
        return false;
    }
    let mut players = 0u16;
    for m in ctx.db.lobby_member().session_id().filter(sess.id) {
        let online = ctx.db.player().entity_id().find(m.entity_id).map(|p| p.online).unwrap_or(false);
        if !online {
            continue;
        }
        if !m.ready {
            return false;
        }
        players += 1;
    }
    players >= lobby.min_players.max(1)
}

/// Say you are ready to start (or not). Counts while your session is in its lobby; a round starts
/// at once when the rules say ready-up and everyone is (DECISIONS #174).
#[reducer]
pub fn set_ready(ctx: &ReducerContext, ready: bool) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("set_ready: no player row")?;
    let (sess, mut row) = lobby_of(ctx, player.entity_id, "set_ready")?;
    if sess.phase != PHASE_LOBBY {
        return Err("set_ready: the round has already started".into());
    }
    if row.ready == ready {
        return Ok(());
    }
    row.ready = ready;
    ctx.db.lobby_member().entity_id().update(row);
    if lobby_all_ready(ctx, &sess) {
        log::info!("session {}: everyone is ready", sess.id);
        advance_session(ctx, sess);
    }
    Ok(())
}

/// Pick a team in the lobby (a number into the rules' teams).
#[reducer]
pub fn set_team(ctx: &ReducerContext, team: u8) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("set_team: no player row")?;
    let (sess, mut row) = lobby_of(ctx, player.entity_id, "set_team")?;
    let teams = crate::rules::lobby(sess.kind).map(|l| l.teams).unwrap_or(&[]);
    if teams.is_empty() {
        return Err("set_team: this game has no teams".into());
    }
    if team as usize >= teams.len() {
        return Err(format!("set_team: there is no team {team} (0..{})", teams.len() - 1));
    }
    if sess.phase != PHASE_LOBBY {
        return Err("set_team: teams are picked in the lobby".into());
    }
    row.team = team;
    ctx.db.lobby_member().entity_id().update(row);
    Ok(())
}

/// How long `phase` lasts for this `kind`, from its plan in shared/rules.json (DECISIONS #154).
/// None — held until a reducer moves it — for a phase planned at 0 seconds, a phase its kind does
/// not plan, and a kind with no plan at all.
fn phase_duration_micros(kind: u8, phase: u8) -> Option<i64> {
    let plan = crate::rules::plan(kind)?;
    let (_, micros) = plan.iter().find(|(p, _)| *p == phase)?;
    if *micros > 0 { Some(*micros) } else { None }
}

/// The phase after `phase` in this kind's plan, going round. A phase the plan does not have goes
/// to the plan's first; a kind with no plan stays where it is.
fn next_phase(kind: u8, phase: u8) -> u8 {
    let Some(plan) = crate::rules::plan(kind) else {
        return phase;
    };
    match plan.iter().position(|(p, _)| *p == phase) {
        Some(i) => plan[(i + 1) % plan.len()].0,
        None => plan[0].0,
    }
}

/// Scheduled 1 Hz. Moves every session whose timer has expired to its next phase.
/// Entering LOBBY starts a new round: scores reset and a fresh seed is rolled.
#[reducer]
pub fn advance_phases(ctx: &ReducerContext, _sched: PhaseSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("advance_phases: scheduler only".into());
    }
    // THE MATCH (DECISIONS #182): a world nobody has been in for a while ends its match and waits.
    let sessions: Vec<Session> = ctx.db.session().iter().collect();
    for sess in sessions {
        if crate::rules::plan(sess.kind).is_none() {
            continue;   // a kind with no plan is a genre's to drive, matches and all
        }
        let Some(m) = ctx.db.session_match().session_id().find(sess.id) else {
            begin_match(ctx, sess);   // a session from before matches: its next round is round 1
            continue;
        };
        if online_players(ctx, &sess) > 0 {
            ctx.db.session_empty().session_id().delete(sess.id);
            continue;
        }
        if !m.started {
            // The match's lobby, with nobody to wait for: held until someone arrives.
            if sess.phase == PHASE_LOBBY && sess.phase_ends_at < ctx.timestamp + TimeDuration::from_micros(HOLD_MICROS / 2) {
                let mut held = sess;
                held.phase_ends_at = ctx.timestamp + TimeDuration::from_micros(HOLD_MICROS);
                ctx.db.session().id().update(held);
            }
            continue;
        }
        let since = match ctx.db.session_empty().session_id().find(sess.id) {
            Some(e) => e.since,
            None => {
                ctx.db.session_empty().insert(SessionEmpty { session_id: sess.id, since: ctx.timestamp });
                ctx.timestamp
            }
        };
        let empty_for = ctx.timestamp.to_micros_since_unix_epoch() - since.to_micros_since_unix_epoch();
        if empty_for >= crate::rules::match_rules(sess.kind).end_after_empty_micros {
            log::info!("session {}: nobody here for {} s, the match ends", sess.id, empty_for / 1_000_000);
            ctx.db.session_empty().session_id().delete(sess.id);
            begin_match(ctx, sess);
        }
    }

    let due: Vec<Session> = ctx
        .db
        .session()
        .iter()
        .filter(|s| s.phase_ends_at <= ctx.timestamp)
        .collect();

    for sess in due {
        let Some(_) = phase_duration_micros(sess.kind, sess.phase) else {
            continue;   // unknown kind: a genre reducer drives it, not this machine
        };
        advance_session(ctx, sess);
    }
    // A lobby whose players all said ready while nobody was asking (one left, the last unready one).
    let waiting: Vec<Session> = ctx.db.session().iter().filter(|s| s.phase == PHASE_LOBBY).collect();
    for sess in waiting {
        if lobby_all_ready(ctx, &sess) {
            advance_session(ctx, sess);
        }
    }
    Ok(())
}

/// Move a session to the next phase of its plan. Entering LOBBY starts a new round: scores reset,
/// a fresh seed, and nobody is ready yet.
fn advance_session(ctx: &ReducerContext, mut sess: Session) {
    let from = sess.phase;
    let to = next_phase(sess.kind, sess.phase);
    sess.phase = to;
    sess.phase_ends_at = ctx.timestamp
        + TimeDuration::from_micros(phase_duration_micros(sess.kind, to).unwrap_or(HOLD_MICROS));
    if to == PHASE_LOBBY {
        new_round(ctx, &mut sess);
    }
    if from == PHASE_LOBBY && to != PHASE_LOBBY {
        mark_match_started(ctx, sess.id);
    }
    let id = sess.id;
    ctx.db.session().id().update(sess);
    log::info!("session {id}: phase {from} -> {to}");
    if let Some(now) = ctx.db.session().id().find(id) {
        crate::game::on_phase_changed(ctx, &now, from);
    }
}

/// A new round on `sess` (not yet written): its number, a fresh seed so last round's rolls cannot
/// be replayed, scores reset, and nobody ready yet.
fn new_round(ctx: &ReducerContext, sess: &mut Session) {
    sess.round = sess.round.saturating_add(1);
    sess.seed = ctx.timestamp.to_micros_since_unix_epoch() as u64 ^ (sess.id << 17);
    let members: Vec<SessionMember> = ctx.db.session_member().session_id().filter(sess.id).collect();
    for mut m in members {
        m.score = 0;
        ctx.db.session_member().id().update(m);
    }
    let lobby: Vec<LobbyMember> = ctx.db.lobby_member().session_id().filter(sess.id).collect();
    for mut m in lobby {
        if m.ready {
            m.ready = false;
            ctx.db.lobby_member().entity_id().update(m);
        }
    }
}

// --- the match (DECISIONS #182) -------------------------------------------------------------------

/// How many of a session's members are PLAYERS who are online. An NPC member (a fishing rival) and a
/// player who left are not.
fn online_players(ctx: &ReducerContext, sess: &Session) -> usize {
    ctx.db
        .session_member()
        .session_id()
        .filter(sess.id)
        .filter(|m| ctx.db.player().entity_id().find(m.entity_id).map(|p| p.online).unwrap_or(false))
        .count()
}

/// The round a player sees: counted from 1 in the session's match. A genre that shows or depends on
/// "which round of the game this is" (fishing's time of day) reads this, never `session.round`.
pub fn match_round(ctx: &ReducerContext, sess: &Session) -> u32 {
    match ctx.db.session_match().session_id().find(sess.id) {
        Some(m) => sess.round.saturating_sub(m.first_round).saturating_add(1),
        None => sess.round,
    }
}

/// Begin a new match on a session: back to the lobby if a round was under way (a new round, as at
/// the end of any round), its rounds counted from 1 from here, and the lobby waiting for players.
fn begin_match(ctx: &ReducerContext, mut sess: Session) {
    let from = sess.phase;
    if from != PHASE_LOBBY {
        sess.phase = PHASE_LOBBY;
        new_round(ctx, &mut sess);
    }
    sess.phase_ends_at = match_lobby_ends(ctx, &sess);
    let previous = ctx.db.session_match().session_id().find(sess.id);
    let row = SessionMatch {
        session_id: sess.id,
        world_id: sess.world_id,
        first_round: sess.round,
        started: false,
        number: previous.as_ref().map(|m| m.number.saturating_add(1)).unwrap_or(1),
    };
    let (id, number) = (sess.id, row.number);
    if previous.is_some() {
        ctx.db.session_match().session_id().update(row);
    } else {
        ctx.db.session_match().insert(row);
    }
    ctx.db.session().id().update(sess);
    log::info!("session {id}: match {number} begins, its lobby waiting for players");
    if let Some(now) = ctx.db.session().id().find(id) {
        if from != PHASE_LOBBY {
            crate::game::on_phase_changed(ctx, &now, from);
        }
        crate::game::on_match_began(ctx, &now);
    }
}

/// When a match's first lobby ends: never while nobody is online; with ready-up and no `wait_s`,
/// never (everyone ready starts it); otherwise after `wait_s`, or the lobby's own seconds.
fn match_lobby_ends(ctx: &ReducerContext, sess: &Session) -> Timestamp {
    let rules = crate::rules::match_rules(sess.kind);
    let ready_up = crate::rules::lobby(sess.kind).map(|l| l.ready_up).unwrap_or(false);
    let micros = if online_players(ctx, sess) == 0 {
        HOLD_MICROS
    } else if rules.wait_micros > 0 {
        rules.wait_micros
    } else if ready_up {
        HOLD_MICROS
    } else {
        phase_duration_micros(sess.kind, PHASE_LOBBY).unwrap_or(HOLD_MICROS)
    };
    ctx.timestamp + TimeDuration::from_micros(micros)
}

fn mark_match_started(ctx: &ReducerContext, session_id: u64) {
    if let Some(mut m) = ctx.db.session_match().session_id().find(session_id) {
        if !m.started {
            m.started = true;
            ctx.db.session_match().session_id().update(m);
        }
    }
}

/// A player came online: their sessions are not empty, and a match lobby held while nobody was here
/// starts its clock (DECISIONS #182).
fn player_arrived(ctx: &ReducerContext, entity_id: u64) {
    let sessions: Vec<u64> = ctx.db.session_member().entity_id().filter(entity_id).map(|m| m.session_id).collect();
    for sid in sessions {
        ctx.db.session_empty().session_id().delete(sid);
        if let Some(sess) = ctx.db.session().id().find(sid) {
            ensure_lobby_member(ctx, &sess, entity_id);   // a member from before the lobby (#184)
        }
        let (Some(sess), Some(m)) = (ctx.db.session().id().find(sid), ctx.db.session_match().session_id().find(sid)) else {
            continue;
        };
        if !m.started && sess.phase == PHASE_LOBBY {
            let ends = match_lobby_ends(ctx, &sess);
            if ends < sess.phase_ends_at {
                let mut s = sess;
                s.phase_ends_at = ends;
                ctx.db.session().id().update(s);
            }
        }
    }
}

/// Admin: end a session's match now and begin the next one, its rounds counted from 1 again
/// (DECISIONS #182). A world does this by itself once nobody has been in it for a while.
#[reducer]
pub fn new_match(ctx: &ReducerContext, session_id: u64) -> Result<(), String> {
    require_admin(ctx)?;
    let sess = ctx.db.session().id().find(session_id).ok_or("new_match: no such session")?;
    ctx.db.session_empty().session_id().delete(session_id);
    begin_match(ctx, sess);
    Ok(())
}

/// Dev/admin: force a session into a phase. Admin-only. Without this, exercising a round-based
/// genre means waiting out real phase durations in every test run.
#[reducer]
pub fn set_session_phase(ctx: &ReducerContext, session_id: u64, phase: u8) -> Result<(), String> {
    require_admin(ctx)?;
    let mut sess = ctx.db.session().id().find(session_id).ok_or("no such session")?;
    let dur = phase_duration_micros(sess.kind, phase).unwrap_or(HOLD_MICROS);
    let from = sess.phase;
    sess.phase = phase;
    sess.phase_ends_at = ctx.timestamp + TimeDuration::from_micros(dur);
    ctx.db.session().id().update(sess);
    if phase != PHASE_LOBBY {
        mark_match_started(ctx, session_id);
    }
    if from != phase {
        if let Some(now) = ctx.db.session().id().find(session_id) {
            crate::game::on_phase_changed(ctx, &now, from);
        }
    }
    Ok(())
}

/// Create a session on a world, creating the world as MODULE authority if it does not exist.
/// Admin-only in the foundation: a lobby system is a genre concern and will want its own rules
/// (per-player limits, matchmaking), so the safe default is that players cannot spawn sessions.
#[reducer]
pub fn create_session(
    ctx: &ReducerContext,
    world_id: u32,
    kind: u8,
    max_members: u16,
) -> Result<(), String> {
    require_admin(ctx)?;
    if ctx.db.session().world_id().find(world_id).is_some() {
        return Err(format!("world {world_id} already has a session"));
    }
    if ctx.db.world_config().world_id().find(world_id).is_none() {
        ctx.db.world_config().insert(WorldConfig {
            world_id,
            sim_authority: SIM_MODULE,
            authority_online: true,
            server_tick: 0,
            server_ts: ctx.timestamp,
            spawn: default_spawn(),
        });
    }
    let dur = phase_duration_micros(kind, PHASE_LOBBY).unwrap_or(HOLD_MICROS);
    let sess = ctx.db.session().insert(Session {
        id: 0,
        world_id,
        kind,
        phase: PHASE_LOBBY,
        phase_ends_at: ctx.timestamp + TimeDuration::from_micros(dur),
        seed: ctx.timestamp.to_micros_since_unix_epoch() as u64 ^ ((world_id as u64) << 32),
        max_members,
        round: 1,
    });
    begin_match(ctx, sess);
    Ok(())
}

/// Join a session. Moves the caller's entity into that session's world, so subscriptions and
/// `tick_movement` follow it without a second reducer.
#[reducer]
pub fn join_session(ctx: &ReducerContext, session_id: u64) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let sess = ctx.db.session().id().find(session_id).ok_or("no such session")?;
    add_member(ctx, &sess, player.entity_id)?;
    move_entity_to_world(ctx, player.entity_id, sess.world_id);
    Ok(())
}

#[reducer]
pub fn leave_session(ctx: &ReducerContext) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let rows: Vec<SessionMember> =
        ctx.db.session_member().entity_id().filter(player.entity_id).collect();
    for m in rows {
        ctx.db.session_member().id().delete(m.id);
    }
    ctx.db.lobby_member().entity_id().delete(player.entity_id);
    move_entity_to_world(ctx, player.entity_id, DEFAULT_WORLD);
    Ok(())
}

/// Keep every row that describes an entity on the same world. Anything that scopes by world
/// (subscriptions, `tick_movement`, authority checks) reads these.
fn move_entity_to_world(ctx: &ReducerContext, entity_id: u64, world_id: u32) {
    if let Some(mut e) = ctx.db.entity().entity_id().find(entity_id) {
        e.world_id = world_id;
        ctx.db.entity().entity_id().update(e);
    }
    if let Some(mut m) = ctx.db.movement_state().entity_id().find(entity_id) {
        m.world_id = world_id;
        m.teleport_flag = true;   // the client must snap, not interpolate across worlds
        ctx.db.movement_state().entity_id().update(m);
    }
    if let Some(mut h) = ctx.db.health_state().entity_id().find(entity_id) {
        h.world_id = world_id;
        ctx.db.health_state().entity_id().update(h);
    }
    let queued: Vec<u64> = ctx.db.input_queue().entity_id().filter(entity_id).map(|q| q.id).collect();
    for id in queued {
        ctx.db.input_queue().id().delete(id);   // inputs aimed at the old world are meaningless
    }
    // The brain goes with its body: the new world's authority is the one that must read it.
    if let Some(mut b) = ctx.db.npc_brain().entity_id().find(entity_id) {
        b.world_id = world_id;
        ctx.db.npc_brain().entity_id().update(b);
    }
    if let Some(mut q) = ctx.db.equip_state().entity_id().find(entity_id) {
        q.world_id = world_id;
        ctx.db.equip_state().entity_id().update(q);
    }
    if let Some(mut a) = ctx.db.appearance().entity_id().find(entity_id) {
        a.world_id = world_id;
        ctx.db.appearance().entity_id().update(a);
    }
    if let Some(mut l) = ctx.db.lobby_member().entity_id().find(entity_id) {
        l.world_id = world_id;
        ctx.db.lobby_member().entity_id().update(l);
    }
}

/// Persist what an NPC's brain needs to resume after a restart (see `NpcBrainRow`). Authority
/// only, and only for an NPC: a player's decisions come from a person, not a brain.
#[reducer]
pub fn write_npc_brain(
    ctx: &ReducerContext,
    entity_id: u64,
    brain: String,
    state: String,
    target_id: u64,
    data: String,
) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("write_npc_brain: no such entity")?;
    require_authority(ctx, ent.world_id)?;
    if ctx.db.player().entity_id().find(entity_id).is_some() {
        return Err("write_npc_brain: a player entity has no brain".into());
    }
    if brain.len() > MAX_BRAIN_NAME || state.len() > MAX_BRAIN_NAME {
        return Err(format!("write_npc_brain: names are limited to {MAX_BRAIN_NAME} bytes"));
    }
    if data.len() > MAX_BRAIN_DATA {
        return Err(format!(
            "write_npc_brain: data is {} bytes, the limit is {MAX_BRAIN_DATA}",
            data.len()
        ));
    }
    let row = NpcBrainRow {
        entity_id,
        world_id: ent.world_id,
        brain,
        state,
        target_id,
        data,
        updated_at: ctx.timestamp,
    };
    if ctx.db.npc_brain().entity_id().find(entity_id).is_some() {
        ctx.db.npc_brain().entity_id().update(row);
    } else {
        ctx.db.npc_brain().insert(row);
    }
    Ok(())
}

/// Authority-only score/coin write. Genres award through this so the client never owns score.
#[reducer]
pub fn add_score(ctx: &ReducerContext, entity_id: u64, score: i64, coins: i64) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("no such entity")?;
    require_authority(ctx, ent.world_id)?;
    let rows: Vec<SessionMember> = ctx.db.session_member().entity_id().filter(entity_id).collect();
    for mut m in rows {
        m.score += score;
        m.coins += coins;
        ctx.db.session_member().id().update(m);
    }
    Ok(())
}


// =============================================================================
// ITEMS / INVENTORY
// =============================================================================

/// Idempotent catalogue seeding. Admin-only; a genre calls this with its own list at deploy
/// time. Existing rows are updated rather than duplicated so it is safe to re-run.
#[reducer]
pub fn seed_item_defs(ctx: &ReducerContext, defs: Vec<ItemDef>) -> Result<(), String> {
    require_admin(ctx)?;
    for d in defs {
        if d.max_stack == 0 {
            return Err(format!("item_def {}: max_stack must be >= 1", d.item_def_id));
        }
        if ctx.db.item_def().item_def_id().find(d.item_def_id).is_some() {
            ctx.db.item_def().item_def_id().update(d);
        } else {
            ctx.db.item_def().insert(d);
        }
    }
    Ok(())
}

/// Add `qty` of an item to an entity, filling existing stacks before opening new ones.
/// Authority-only: loot and rewards are server decisions, never client claims.
#[reducer]
pub fn grant_item(
    ctx: &ReducerContext,
    entity_id: u64,
    item_def_id: u32,
    qty: u32,
) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("no such entity")?;
    require_authority(ctx, ent.world_id)?;
    grant_item_internal(ctx, entity_id, item_def_id, qty)
}

/// Shared by `grant_item` and any in-module award path (challenge rewards, for instance), so
/// the stacking rule lives in exactly one place.
fn grant_item_internal(
    ctx: &ReducerContext,
    entity_id: u64,
    item_def_id: u32,
    qty: u32,
) -> Result<(), String> {
    if qty == 0 {
        return Ok(());
    }
    let def = ctx
        .db
        .item_def()
        .item_def_id()
        .find(item_def_id)
        .ok_or(format!("unknown item_def {item_def_id}"))?;

    let mut remaining = qty;

    // Top up partial stacks first.
    if def.max_stack > 1 {
        let mut stacks: Vec<InventoryItem> = ctx
            .db
            .inventory_item()
            .owner_entity_id()
            .filter(entity_id)
            .filter(|i| i.item_def_id == item_def_id && i.qty < def.max_stack)
            .collect();
        stacks.sort_by_key(|i| i.id);
        for mut stack in stacks {
            if remaining == 0 {
                break;
            }
            let room = def.max_stack - stack.qty;
            let add = room.min(remaining);
            stack.qty += add;
            remaining -= add;
            ctx.db.inventory_item().id().update(stack);
        }
    }

    while remaining > 0 {
        let take = def.max_stack.min(remaining);
        ctx.db.inventory_item().insert(InventoryItem {
            id: 0,
            owner_entity_id: entity_id,
            item_def_id,
            qty: take,
            slot: -1,
            instance_data: String::new(),
        });
        remaining -= take;
    }
    Ok(())
}

/// Player intent: spend part of a stack. The caller must own the row — this is the one
/// inventory reducer a client may call, so ownership is checked against `player`, not
/// `authority`.
#[reducer]
pub fn consume_item(ctx: &ReducerContext, item_id: u64, qty: u32) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let mut item = ctx.db.inventory_item().id().find(item_id).ok_or("no such item")?;
    if item.owner_entity_id != player.entity_id {
        return Err("not your item".into());
    }
    if qty == 0 || qty > item.qty {
        return Err(format!("cannot consume {qty} of {}", item.qty));
    }
    if item.qty == qty {
        ctx.db.inventory_item().id().delete(item_id);
    } else {
        item.qty -= qty;
        ctx.db.inventory_item().id().update(item);
    }
    Ok(())
}

/// Say what the caller's own entity has in hand (DECISIONS #160): `EquipComponent` calls it as its
/// state changes. Client-callable and presentational, so it only checks the state is one there is.
/// Choose your own look (DECISIONS #166). Like a name it is untrusted text every client acts on,
/// so it is limited here to what a look is spelled with: lowercase letters, digits and `_;=,.-`.
/// Empty clears the choice (back to the look picked from the entity id).
#[reducer]
pub fn set_appearance(ctx: &ReducerContext, look: String) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("set_appearance: no player row")?;
    let ent = ctx.db.entity().entity_id().find(player.entity_id).ok_or("set_appearance: no entity")?;
    let look = look.trim().to_string();
    if look.chars().count() > MAX_LOOK_LEN {
        return Err(format!("set_appearance: a look is at most {MAX_LOOK_LEN} characters"));
    }
    if let Some(bad) = look.chars().find(|c| !(c.is_ascii_lowercase() || c.is_ascii_digit() || "_;=,.-".contains(*c))) {
        return Err(format!("set_appearance: '{bad}' is not used in a look (a-z, 0-9 and _;=,.-)"));
    }
    if look.is_empty() {
        ctx.db.appearance().entity_id().delete(ent.entity_id);
        return Ok(());
    }
    let row = AppearanceRow { entity_id: ent.entity_id, world_id: ent.world_id, look };
    match ctx.db.appearance().entity_id().find(ent.entity_id) {
        Some(old) if old.look == row.look => {}   // idempotent: clients send it on every connect
        Some(_) => { ctx.db.appearance().entity_id().update(row); }
        None => { ctx.db.appearance().insert(row); }
    }
    Ok(())
}

#[reducer]
pub fn set_equip_state(ctx: &ReducerContext, state: u8) -> Result<(), String> {
    if state > EQUIP_STOWING {
        return Err(format!("set_equip_state: {state} is not a state (0 away .. 3 putting away)"));
    }
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("set_equip_state: no player row")?;
    let ent = ctx.db.entity().entity_id().find(player.entity_id).ok_or("set_equip_state: no entity")?;
    let row = EquipStateRow { entity_id: ent.entity_id, world_id: ent.world_id, state };
    if ctx.db.equip_state().entity_id().find(ent.entity_id).is_some() {
        ctx.db.equip_state().entity_id().update(row);
    } else {
        ctx.db.equip_state().insert(row);
    }
    Ok(())
}

/// Move a stack to a slot. Client-callable; purely presentational, so it only checks ownership.
#[reducer]
pub fn set_item_slot(ctx: &ReducerContext, item_id: u64, slot: i16) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let mut item = ctx.db.inventory_item().id().find(item_id).ok_or("no such item")?;
    if item.owner_entity_id != player.entity_id {
        return Err("not your item".into());
    }
    item.slot = slot;
    ctx.db.inventory_item().id().update(item);
    Ok(())
}


// =============================================================================
// CHALLENGES (DECISIONS #19)
// =============================================================================

/// Default time a player has to complete a challenge.
const CHALLENGE_TTL_MICROS: i64 = 30_000_000;

/// Issue a challenge to an entity. Internal helper — genre reducers call this from whatever
/// action starts the minigame (fishing's `cast`, mining's `interact`).
///
/// The seed mixes the session seed, the entity and the exact issue time. The session seed alone
/// would let everyone in a match precompute each other's challenges; the timestamp is the part
/// the client cannot predict.
fn issue_challenge_internal(
    ctx: &ReducerContext,
    entity_id: u64,
    kind: u8,
    difficulty: f32,
    payload: String,
    ttl_micros: i64,
) -> Result<u64, String> {
    if !difficulty.is_finite() || !(0.0..=1.0).contains(&difficulty) {
        return Err(format!("difficulty {difficulty} out of range"));
    }
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("no such entity")?;
    let session_seed = ctx
        .db
        .session()
        .world_id()
        .find(ent.world_id)
        .map(|s| s.seed)
        .unwrap_or(0);
    let now = ctx.timestamp.to_micros_since_unix_epoch() as u64;
    let seed = session_seed ^ entity_id.wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ now;

    let row = ctx.db.challenge().insert(Challenge {
        id: 0,
        entity_id,
        kind,
        seed,
        difficulty,
        issued_at: ctx.timestamp,
        expires_at: ctx.timestamp + TimeDuration::from_micros(ttl_micros),
        payload,
    });
    Ok(row.id)
}

/// The genre layer's way to start a Challenge. Wraps the internal helper so `game/` never
/// depends on module-private functions — the hook surface stays small and documented.
pub fn issue_challenge_for(
    ctx: &ReducerContext,
    entity_id: u64,
    difficulty: f32,
    payload: String,
) -> Result<u64, String> {
    issue_challenge_internal(
        ctx,
        entity_id,
        crate::challenge::KIND_TIMING_BAR,
        difficulty,
        payload,
        CHALLENGE_TTL_MICROS,
    )
}

/// Start a challenge of the GENRE's own kind (>= `KIND_GENRE_FROM`), with its own lifetime.
/// The genre judges it and pays it out through `game::resolve_challenge`; the foundation only
/// seeds it, keeps it private to its owner (RLS), expires it, and closes it.
pub fn issue_genre_challenge(
    ctx: &ReducerContext,
    entity_id: u64,
    kind: u8,
    payload: String,
    ttl_micros: i64,
) -> Result<u64, String> {
    if kind < crate::challenge::KIND_GENRE_FROM {
        return Err(format!("challenge kind {kind} belongs to the foundation"));
    }
    if ttl_micros <= 0 || ttl_micros > 600_000_000 {
        return Err(format!("challenge lifetime {ttl_micros} us is out of range"));
    }
    issue_challenge_internal(ctx, entity_id, kind, 0.0, payload, ttl_micros)
}

/// Dev/authority entry point so the challenge loop can be exercised before a genre exists.
#[reducer]
pub fn issue_challenge(
    ctx: &ReducerContext,
    entity_id: u64,
    kind: u8,
    difficulty: f32,
) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("no such entity")?;
    require_authority(ctx, ent.world_id)?;
    issue_challenge_internal(ctx, entity_id, kind, difficulty, String::new(), CHALLENGE_TTL_MICROS)?;
    Ok(())
}

/// Submit a played challenge. The server re-simulates it; the client's own opinion of how well
/// it did is never transmitted, only its inputs.
///
/// The challenge is ALWAYS consumed, including when the submission is malformed, and the reducer
/// returns Ok so that the delete commits. Returning Err would roll the delete back and leave the
/// row in place, letting a client submit repeatedly against the same fixed seed and binary-search
/// the hit windows by watching its own score. One shot per issued challenge closes that.
#[reducer]
pub fn submit_challenge_result(
    ctx: &ReducerContext,
    challenge_id: u64,
    result: Vec<f32>,
) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let ch = ctx
        .db
        .challenge()
        .id()
        .find(challenge_id)
        .ok_or("no such challenge")?;
    if ch.entity_id != player.entity_id {
        return Err("not your challenge".into());
    }

    // A GENRE KIND is the genre's to judge and to pay out. It is resolved while the challenge
    // still exists — before `on_challenge_closed` — because a genre keeps its own rows beside a
    // challenge (fishing's cast: what is on the line, when it bit) and cleans them up on close;
    // judging after the close would judge nothing. There is no generic award: what a genre play
    // is worth is the genre's business, and paying it twice was the old behaviour.
    if ch.kind >= crate::challenge::KIND_GENRE_FROM {
        let verdict = if ctx.timestamp > ch.expires_at {
            log::info!("challenge {challenge_id}: expired, no award");
            None
        } else {
            crate::game::resolve_challenge(ctx, &ch, &result)
        };
        ctx.db.challenge().id().delete(challenge_id);
        crate::game::on_challenge_closed(ctx, &ch);
        match verdict {
            Some(q) => log::info!("challenge {challenge_id}: resolved by the genre, quality {q:.3}"),
            None => log::info!("challenge {challenge_id}: the genre awarded nothing"),
        }
        return Ok(());
    }

    ctx.db.challenge().id().delete(challenge_id);
    // Whatever happens next — an award, an expiry, a rejected submission — this challenge is
    // over, and a genre that keeps something beside it has to hear so on every path.
    crate::game::on_challenge_closed(ctx, &ch);

    if ctx.timestamp > ch.expires_at {
        log::info!("challenge {challenge_id}: expired, no award");
        return Ok(());
    }

    match crate::challenge::validate_challenge(ch.kind, ch.seed, ch.difficulty, &result) {
        Some(quality) => {
            // Award through the same authority-free internal path a genre would use.
            // ROUND, not truncate. `as i64` truncates, so a quality of 0.99999994 — one ULP
            // below a perfect play, which is all it takes for a press to be a hair off the
            // centre after a decimal round-trip — scored 99 instead of 100. Losing a whole
            // point to float noise is indistinguishable from a bug to a player.
            let score = (quality * 100.0f32).round() as i64;
            let members: Vec<SessionMember> = ctx
                .db
                .session_member()
                .entity_id()
                .filter(ch.entity_id)
                .collect();
            for mut m in members {
                m.score += score;
                m.coins += score / 10;
                ctx.db.session_member().id().update(m);
            }
            log::info!("challenge {challenge_id}: quality {quality:.4} -> score +{score}");
            // Hand the result to the genre. It decides what the play MEANT — a fish, an ore,
            // nothing at all. Deliberately after the generic award and deliberately infallible:
            // a genre bug must not roll back a legitimate play.
            crate::game::on_challenge_succeeded(ctx, &ch, quality);
        }
        None => {
            // Malformed or out-of-range submission: a client bug or a probe. Consumed, no award.
            log::warn!(
                "challenge {challenge_id}: rejected submission from entity {} (len {})",
                ch.entity_id,
                result.len()
            );
        }
    }
    Ok(())
}

/// Scheduled cleanup so abandoned challenges do not accumulate.
#[reducer]
pub fn prune_challenges(ctx: &ReducerContext, _sched: ChallengePruneSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("prune_challenges: scheduler only".into());
    }
    let stale: Vec<Challenge> = ctx
        .db
        .challenge()
        .iter()
        .filter(|c| ctx.timestamp > c.expires_at)
        .collect();
    for ch in stale {
        ctx.db.challenge().id().delete(ch.id);
        crate::game::on_challenge_closed(ctx, &ch);
    }
    Ok(())
}


// =============================================================================
// INTERACTION
// =============================================================================

/// Player intent: "use that thing". The client's raycast is a prompt, not a permission — the
/// range check here is the real one, because the raycast runs on a machine the player owns.
///
/// Dispatch is by target `entity.kind`, which is how a genre extends this: add a kind, add an
/// arm. Phase 3 ships RESOURCE_NODE, which issues the timing-bar Challenge.
#[reducer]
pub fn interact(ctx: &ReducerContext, target_id: u64, verb: u8) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let me = ctx
        .db
        .movement_state()
        .entity_id()
        .find(player.entity_id)
        .ok_or("interact: you have no movement_state")?;
    let target = ctx
        .db
        .entity()
        .entity_id()
        .find(target_id)
        .ok_or("interact: no such entity")?;
    let target_pos = ctx
        .db
        .movement_state()
        .entity_id()
        .find(target_id)
        .ok_or("interact: target has no movement_state")?;

    if me.world_id != target_pos.world_id {
        return Err("interact: target is in another world".into());
    }
    let d2 = me.pos.sub(target_pos.pos).length_sq();
    if d2 > INTERACT_RANGE * INTERACT_RANGE {
        return Err(format!(
            "interact: out of range ({:.2} m > {:.2} m)",
            d2.sqrt(),
            INTERACT_RANGE
        ));
    }

    match target.kind {
        entity_kind::RESOURCE_NODE => {
            // Difficulty rises with the verb so a genre can offer "careful" vs "quick"
            // without another reducer. Payload names the node so the client can theme it.
            let difficulty = if verb > 0 { 0.75f32 } else { 0.35f32 };
            let payload = format!("{{\"node\":{target_id},\"verb\":{verb}}}");
            issue_challenge_internal(
                ctx,
                player.entity_id,
                crate::challenge::KIND_TIMING_BAR,
                difficulty,
                payload,
                CHALLENGE_TTL_MICROS,
            )?;
            Ok(())
        }
        entity_kind::PLAYER | entity_kind::NPC => {
            Err("interact: nothing to do with that entity".into())
        }
        // A GENRE'S OWN KIND (DECISIONS #154): range and world are checked above; what using it
        // means is the genre's. None: no genre claims the kind.
        other => crate::game::on_interact(ctx, player.entity_id, &target, verb)
            .unwrap_or_else(|| Err(format!("interact: no game handles entity kind {other}"))),
    }
}

/// Dev helper: place a resource node in the world so the interact path can be exercised
/// before a genre ships its own spawning.
#[reducer]
pub fn spawn_resource_node(
    ctx: &ReducerContext,
    world_id: u32,
    pos: Vector3,
) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    let ent = ctx.db.entity().insert(Entity {
        entity_id: 0,
        world_id,
        kind: entity_kind::RESOURCE_NODE,
        owner: ctx.sender(),
        spawned_at: ctx.timestamp,
    });
    ctx.db.movement_state().insert(MovementStateRow {
        entity_id: ent.entity_id,
        world_id,
        pos,
        vel: Vector3::ZERO,
        yaw: 0.0,
        grounded: true,
        move_state: 0,
        last_processed_seq: 0,
        server_tick: current_tick(ctx, world_id),
        server_ts: ctx.timestamp,
        teleport_flag: true,
        correction_epoch: 0,
    });
    Ok(())
}

// =============================================================================
// HELPERS
// =============================================================================

pub fn current_tick(ctx: &ReducerContext, world_id: u32) -> u64 {
    ctx.db.world_config().world_id().find(world_id).map(|w| w.server_tick).unwrap_or(0)
}
