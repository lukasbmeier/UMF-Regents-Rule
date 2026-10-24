//! The foundation's tables, the dev-tools switch and the rate budgets (with `spend_rate`). Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

use super::*;

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
pub(crate) fn default_spawn() -> Vector3 {
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
    /// The cell it is in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
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
    /// When they last connected or left (template 1.0): how long they have been gone, for parking.
    pub left_at: Timestamp,
    /// The connection that plays this character (template 1.0): a second connection of the same sign-in
    /// takes over, and inputs from the one before are refused.
    pub connection_id: Option<ConnectionId>,
    /// The account playing it (template 1.0); 0: a guest. What a player is shown their characters by
    /// (`account_character`'s filter joins this row, which has no filter of its own).
    #[index(btree)]
    pub account_id: u64,
}

#[table(accessor = movement_state, public)]
pub struct MovementStateRow {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The cell it is in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
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
    /// The cell it is in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
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
    /// The cell it is in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
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
    /// The cell it is in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
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

/// THE DEV TOOLS SWITCH (REVIEW 0.23.1 B1): whether `teleport` and `dev_nudge` answer a player who
/// is not an admin. Private, one row at most (`id = 0`); no row means OFF, which is how every
/// publish starts. The test suites turn it on for `umf-test` (`set_dev_tools true`) because their
/// clients teleport; a database friends play on never has it on. A runtime switch rather than a
/// `cfg`: compiling the reducers out would change the schema fingerprint between a test build and
/// a play build (DECISIONS #164), and an admin may still teleport on a live server.
#[table(accessor = dev_tools)]
pub struct DevTools {
    #[primary_key]
    pub id: u8,
    pub enabled: bool,
}

/// RATE BUDGETS (REVIEW 0.23.1 B3): what each player has left of a reducer's allowance
/// (`shared/rules.json` rate_limits), keyed "<entity>:<reducer>". Private. A refused call rolls its
/// transaction back, so spamming one writes nothing here; the row goes with its entity.
#[table(accessor = rate_budget)]
pub struct RateBudget {
    #[primary_key]
    pub key: String,
    #[index(btree)]
    pub entity_id: u64,
    pub tokens: f32,
    pub at: Timestamp,
}

/// One call to `verb` by `entity_id`, against its budget: Err (and nothing changed) when it is over
/// `crate::rules::rate_limit(verb)`. Call it FIRST in a player-callable reducer whose rows every
/// client receives, or that moves a player between worlds; a genre's verbs too (`show_fight`).
pub fn spend_rate(ctx: &ReducerContext, entity_id: u64, verb: &str) -> Result<(), String> {
    let key = format!("{entity_id}:{verb}");
    let limit = crate::rules::rate_limit(verb);
    let old = ctx.db.rate_budget().key().find(key.clone());
    let elapsed_s = old.as_ref().map(|r| {
        (ctx.timestamp.to_micros_since_unix_epoch() - r.at.to_micros_since_unix_epoch()) as f64 / 1_000_000.0
    }).unwrap_or(0.0);
    let Some(left) = crate::rules::rate_spend(old.as_ref().map(|r| r.tokens), elapsed_s, limit) else {
        return Err(format!("{verb}: too many calls (at most {} at once, {} a second)", limit.burst, limit.per_sec));
    };
    let row = RateBudget { key, entity_id, tokens: left, at: ctx.timestamp };
    if old.is_some() {
        ctx.db.rate_budget().key().update(row);
    } else {
        ctx.db.rate_budget().insert(row);
    }
    Ok(())
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
