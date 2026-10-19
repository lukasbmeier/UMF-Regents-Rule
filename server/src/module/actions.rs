//! Abilities and action events (PHASE3_SPEC Task 12, PHASE4_SPEC §3). Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

use super::*;

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
pub(crate) const ACTION_EVENT_TTL_MICROS: i64 = 5_000_000;

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

/// A player's dash as the module has seen it in their input frames (`crate::status::DashWindow`,
/// DECISIONS #256): the Tier A bound counts a kind's dash only inside a dash's window, so a client
/// that never dashes is held to its sprint. Written only while a window or a cooldown runs.
#[table(accessor = dash_window)]
pub struct DashWindowRow {
    #[primary_key]
    pub entity_id: u64,
    pub open_frames: f32,
    pub cooldown_frames: f32,
}

/// Record that the module just overrode `entity_id`, starting `epoch` at input `from_seq`.
pub(crate) fn record_correction(ctx: &ReducerContext, entity_id: u64, epoch: u32, from_seq: u32) {
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
pub(crate) const CHALLENGE_IS_PRIVATE: Filter = Filter::Sql(
    "SELECT c.* FROM challenge c JOIN player p ON c.entity_id = p.entity_id WHERE p.identity = :sender",
);

/// Only an authority registered for a world may read that world's input queue.
///
/// The join is on equal `world_id`, so a sidecar must be registered for a SPECIFIC world —
/// `register_authority` enforces that for ROLE_SIDECAR. A wildcard (`world_id = 0`) authority
/// would pass `require_authority` for writes but match nothing here, and a sidecar that can
/// write but cannot read its inputs is a confusing half-broken state.
#[client_visibility_filter]
pub(crate) const INPUT_QUEUE_IS_AUTHORITY_ONLY: Filter = Filter::Sql(
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
pub(crate) const NPC_BRAIN_IS_AUTHORITY_ONLY: Filter = Filter::Sql(
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
