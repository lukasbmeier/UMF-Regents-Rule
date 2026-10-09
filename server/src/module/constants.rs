//! The module's constants: phases, roles, Tier A's trust bounds, move states. Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

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
pub(crate) const HOLD_MICROS: i64 = 365 * 24 * 3600 * 1_000_000;

/// `authority.role`
pub const ROLE_ADMIN: u8 = 0;
pub const ROLE_SIDECAR: u8 = 1;

/// A sidecar that has not heartbeated within this window is considered offline.
pub(crate) const AUTHORITY_TIMEOUT_MICROS: i64 = 5_000_000;

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
pub(crate) const TRUST_SPEED_SLACK: f32 = 1.5;
/// Falling faster than you can run is not an exploit. Bounded only to stop absurd values.
pub(crate) const TRUST_MAX_FALL_SPEED: f32 = 50.0;
/// Vertical motion below this per frame counts as resting on something. The module cannot see
/// WHAT the client is standing on and does not need to: `grounded` only feeds other clients'
/// jump/land detection and whether an undriven entity falls.
pub(crate) const GROUNDED_EPS: f32 = 1.0e-4;
/// A client produces CLIENT_TICK_HZ frames a second. Draining at most twice that per server
/// tick lets a late burst catch up, while a client that floods frames cannot multiply the
/// per-frame envelope into a speed hack. Leftovers wait for the next tick.
/// The highest phase the foundation's own machine knows. A genre that adds phases numbers from
/// here, exactly as it does for `move_state` and `challenge.kind`.
pub const PHASE_FOUNDATION_MAX: u8 = PHASE_SHOP;

/// Foundation move states run 0..=MOVE_STATE_FOUNDATION_MAX (IDLE..MOUNT, RUN); genres use >= 100.
/// Anything in between is not a state anyone defined, and is not mirrored.
pub(crate) const MOVE_STATE_FOUNDATION_MAX: u8 = 7;
pub(crate) const MOVE_STATE_GENRE_FROM: u8 = 100;
/// `MovementState.Move` (movement_state.gd): the client's model says whether it stands or is in
/// the air, decided after collision (MovementModel.classify).
pub(crate) const MOVE_IDLE: u8 = 0;
pub(crate) const MOVE_WALK: u8 = 1;
pub(crate) const MOVE_SPRINT: u8 = 2;
pub(crate) const MOVE_AIR: u8 = 3;
pub(crate) const MOVE_RUN: u8 = 7;
pub(crate) const MAX_FRAMES_PER_TICK: usize =
    (2 * crate::movement_config::CLIENT_TICK_HZ / crate::movement_config::SERVER_TICK_HZ) as usize;
/// Hard cap on queued-but-unprocessed inputs per entity. Protects against flooding.
pub(crate) const MAX_QUEUE_DEPTH: usize = 64;
pub(crate) const MAX_BATCH: usize = 8;

pub(crate) const CLIENT_DT: f32 = 1.0 / crate::movement_config::CLIENT_TICK_HZ as f32;
pub(crate) const SERVER_DT: f32 = 1.0 / crate::movement_config::SERVER_TICK_HZ as f32;

pub mod entity_kind {
    pub const PLAYER: u8 = 0;
    pub const NPC: u8 = 1;
    /// Something you walk up to and use: a fishing spot, an ore vein, a chest. Interacting
    /// with one issues a Challenge. Genres number their own kinds from 100.
    pub const RESOURCE_NODE: u8 = 2;
}

// How close a player must be to interact is a hot rule now: `hot::foundation::INTERACT_RANGE_M`
// (DECISIONS #201), read live in `interact`; the client's prompt reads the same row.
