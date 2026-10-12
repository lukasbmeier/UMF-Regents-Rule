//! STATUSES (docs/FOUNDATION_SYSTEMS.md milestone 2, DECISIONS #206): what state an entity is in
//! (normal, injured, downed, carried, out, hidden, escaped, or a genre's own), and what that lets
//! it do. Each status is CONTENT (`StatusDef`, `foundation/content/status/`, a genre's), baked and
//! compiled in here as `STATUSES`; the module keeps who is in which in the `status_state` table.
//!
//! The foundation's numbers are 0-99, a genre's 100-255. A genre may also REPLACE one of the
//! foundation's (its own `StatusDef` with the same number): the game then uses the genre's, as a
//! genre's rule override replaces a foundation rule's value. Pure, so the native suites check it.

use crate::content::MovementLimits;

/// One status, as the module needs it: how long it lasts on its own, what it becomes then, and
/// what an entity in it may do.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct StatusSeed {
    pub status: u8,
    pub name: &'static str,
    /// How long it lasts when set without a length (0: until something changes it).
    pub lasts_ms: u32,
    /// What it becomes when that time is up (unless a genre's `on_status_expired` says otherwise).
    pub then: u8,
    /// Its speed, as a share of the character's own (1: unchanged, 0: cannot move).
    pub speed: f32,
    /// A burst at its start: speed times this for `burst_ms` (1: none).
    pub burst: f32,
    pub burst_ms: u32,
    pub can_sprint: bool,
    /// Jumps and flaps.
    pub can_jump: bool,
    pub can_dash: bool,
    /// May use things and abilities (`interact`, `use_ability`).
    pub can_act: bool,
    /// May be the target of someone else's use or ability.
    pub targetable: bool,
    /// May be HIT by an ability a referee judges (DECISIONS #226): a downed player is not hit again.
    pub hittable: bool,
}

include!(concat!(env!("OUT_DIR"), "/statuses.rs"));

/// The foundation's statuses: what every game's status 0-6 means unless a genre replaces it.
pub const NORMAL: u8 = 0;
pub const INJURED: u8 = 1;
pub const DOWNED: u8 = 2;
pub const CARRIED: u8 = 3;
pub const OUT: u8 = 4;
pub const HIDDEN: u8 = 5;
pub const ESCAPED: u8 = 6;
/// Where a genre's own statuses start.
pub const GENRE_FROM: u8 = 100;

/// The status numbered `n` in this game, if there is one.
pub fn find(n: u8) -> Option<&'static StatusSeed> {
    STATUSES.iter().find(|s| s.status == n)
}

/// The status an entity with no row is in, and what an unknown number falls back to.
pub fn normal() -> &'static StatusSeed {
    find(NORMAL).expect("status 0 (normal) is foundation content: foundation/content/status/normal.tres")
}

/// How fast an entity may claim to move in a Tier A world (`module::apply_client_trust`) while in
/// status `cur`, `since_ms` after it changed from `prev`: its kind's bound with the status applied.
///
/// For `grace_ms` after a change it is the WIDER of the two: the change reaches the entity's
/// client a round trip later, and until then it moves as it did (a downed player still running).
/// Without the grace, every change to a slower status would clamp the client and correct it.
pub fn bound(kind: MovementLimits, cur: &StatusSeed, prev: &StatusSeed, since_ms: i64, grace_ms: i64) -> MovementLimits {
    let now = applied(kind, cur, since_ms < cur.burst_ms as i64);
    if since_ms >= grace_ms {
        return now;
    }
    // The status it left may have been mid-burst; giving it the burst is the generous reading.
    let before = applied(kind, prev, true);
    MovementLimits {
        run: now.run.max(before.run),
        sprint: now.sprint.max(before.sprint),
        burst: now.burst.max(before.burst),
        lift: now.lift.max(before.lift),
    }
}

/// A kind's bound in one status, bursting or not.
pub fn applied(kind: MovementLimits, s: &StatusSeed, bursting: bool) -> MovementLimits {
    let speed = s.speed.max(0.0) * if bursting { s.burst.max(1.0) } else { 1.0 };
    let run = kind.run * speed;
    let sprint = if s.can_sprint { kind.sprint * speed } else { run };
    MovementLimits {
        run,
        sprint,
        burst: if s.can_dash { kind.burst * speed } else { 0.0 },
        // Without a jump it still climbs what it walks up: a slope rises no faster than it moves.
        lift: if s.can_jump { kind.lift } else { sprint },
    }
}
