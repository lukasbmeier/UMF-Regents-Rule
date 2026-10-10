//! HOLD TO INTERACT (docs/FOUNDATION_SYSTEMS.md milestone 3, DECISIONS #209): a press held on
//! something until it is done (helping a downed teammate up, laying an egg, opening a gate), faster
//! with more doing it together. What a hold IS is content (`HoldDef`, `foundation/content/hold/`, a
//! genre's), baked and compiled in here as `HOLDS`; the module keeps who is holding what and how far
//! along it is (`hold_progress`, `hold_member`). Pure, so the native suites check it.

/// One hold, as the module needs it: what press starts it, on what, how long it takes, what stops it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct HoldSeed {
    /// Its content id (`HoldDef.id`): what `hold_progress.hold` names.
    pub id: u32,
    pub name: &'static str,
    /// The interact verb that starts it (0: the interact key).
    pub verb: u8,
    /// The entity kinds it is done to.
    pub targets: &'static [u8],
    /// The entity kinds that may do it (empty: any).
    pub doers: &'static [u8],
    /// The status the target must be in (-1: any).
    pub when: i16,
    /// Seconds to finish with 1, 2, 3... doing it together; the last applies to more.
    pub seconds_with: &'static [f32],
    /// How near a doer must be (0: the game's interact range, `foundation.interact_range_m`).
    pub range_m: f32,
    /// How many may do it at once (0: any number).
    pub max_doers: u8,
    /// Whether what was done stays when everyone lets go (a half-laid nest), or is lost (helping up).
    pub keeps_progress: bool,
    /// A doer who is hurt lets go.
    pub stopped_by_damage: bool,
    /// A doer who moves this far from where they started lets go (0: moving does not stop it).
    pub stopped_by_moving_m: f32,
    /// The status the target is put in when it is done (-1: unchanged).
    pub then_status: i16,
}

include!(concat!(env!("OUT_DIR"), "/holds.rs"));

/// `hold_progress.state`: being done, or done (shown for one tick, then gone).
pub const GOING: u8 = 0;
pub const DONE: u8 = 1;

/// Why a doer let go, for `game::on_hold_left`.
pub mod left {
    /// They let go of the key (`end_interact`), or started holding something else.
    pub const RELEASED: u8 = 0;
    /// They are too far from it.
    pub const OUT_OF_RANGE: u8 = 1;
    /// They moved further than the hold allows from where they started.
    pub const MOVED: u8 = 2;
    /// Their status no longer lets them act (downed), or they left the game.
    pub const CANNOT_ACT: u8 = 3;
    /// They were hurt (a hold `stopped_by_damage`).
    pub const DAMAGED: u8 = 4;
    /// The target is no longer something this hold is done to (its status changed, it is out of
    /// reach, it is in another world).
    pub const TARGET_CHANGED: u8 = 5;
    /// They, or the target, are gone.
    pub const GONE: u8 = 6;
}

/// The hold a press of `verb` by a doer of `doer_kind` starts on a target of `target_kind` in status
/// `target_status`, if any: a genre's before the foundation's (`HOLDS` is in that order).
pub fn find(target_kind: u8, verb: u8, target_status: u8, doer_kind: u8) -> Option<&'static HoldSeed> {
    HOLDS.iter().find(|h| applies(h, target_kind, verb, target_status, doer_kind))
}

/// The hold with content id `id`, if this build has it.
pub fn by_id(id: u32) -> Option<&'static HoldSeed> {
    HOLDS.iter().find(|h| h.id == id)
}

/// Whether `h` is what such a press starts.
pub fn applies(h: &HoldSeed, target_kind: u8, verb: u8, target_status: u8, doer_kind: u8) -> bool {
    h.verb == verb
        && h.targets.contains(&target_kind)
        && (h.doers.is_empty() || h.doers.contains(&doer_kind))
        && still_applies(h, target_status)
}

/// Whether a target in `target_status` is still something `h` is done to.
pub fn still_applies(h: &HoldSeed, target_status: u8) -> bool {
    h.when < 0 || h.when as u8 == target_status
}

/// How fast it goes with `doers` doing it: a share of the whole per second (0 with nobody).
pub fn rate(h: &HoldSeed, doers: u32) -> f32 {
    if doers == 0 || h.seconds_with.is_empty() {
        return 0.0;
    }
    let s = h.seconds_with[(doers as usize).min(h.seconds_with.len()) - 1];
    if s > 0.0 { 1.0 / s } else { 0.0 }
}

/// How far along it is `elapsed_s` after it was `progress` (0..1), going at `rate`.
pub fn progress_at(progress: f32, rate: f32, elapsed_s: f64) -> f32 {
    (progress as f64 + rate as f64 * elapsed_s.max(0.0)).clamp(0.0, 1.0) as f32
}

/// Seconds until it is done from `progress` at `rate`, or None when it is not getting there.
pub fn seconds_left(progress: f32, rate: f32) -> Option<f32> {
    if rate <= 0.0 {
        return None;
    }
    Some(((1.0 - progress) / rate).max(0.0))
}

/// Whether a doer that started at `from` and is now at `now` (metres, as `[x, y, z]`), with the target
/// at `target`, may go on: `range_m` the hold's reach (already the game's when it has none), `slack_m`
/// the rule's leeway for letting go (`foundation.hold_leave_slack_m`). The reason it may not, or None.
pub fn keeps_hold(h: &HoldSeed, from: [f32; 3], now: [f32; 3], target: [f32; 3], range_m: f32, slack_m: f32) -> Option<u8> {
    let d = |a: [f32; 3], b: [f32; 3]| ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt();
    if d(now, target) > range_m + slack_m.max(0.0) {
        return Some(left::OUT_OF_RANGE);
    }
    if h.stopped_by_moving_m > 0.0 && d(now, from) > h.stopped_by_moving_m {
        return Some(left::MOVED);
    }
    None
}
