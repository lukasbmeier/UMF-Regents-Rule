//! THE DODGE ROLL (DECISIONS #309): an ability whose content `rolls` (`AbilityDef`, "A dodge roll") throws its
//! user's body the way their keys push (the movement profile's dash, which their client predicts) and makes them
//! unhittable for its length: the module puts its STATUS on them as an EFFECT (`status_effect`, beside their
//! state), keeps when they pressed it as they saw it (`roll_state`), and asks every genre what else a roll does
//! (`Genre::on_roll`: a swing canceled, a block lowered, a hit taken back). Moved down from Regent's Rule, where it
//! was built first (its `regents.rs`, 2026-10-19 to 2026-11-11).
//!
//! Its rolls are CONTENT, baked and compiled in here as `ROLLS`. Pure, so the native suites check it.

/// One roll, as the module needs it: which ability, the status that holds its user while it lasts (the
/// unhittable window: a status that is not `hittable`), how long it lasts, the hot rule that may say so live
/// instead, and whether it may begin in the air.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RollSeed {
    pub ability_id: u32,
    /// The status put on as an effect for its length (`StatusDef.status`).
    pub status: u8,
    /// How long it lasts (ms): the effect's length, and the time its way is held.
    pub ms: u32,
    /// A hot rule's key that gives its length live (`regents.roll_ms`); empty: `ms`.
    pub ms_rule: &'static str,
    /// May begin in the air. Off: the module refuses one there (a client holds the press until it lands).
    pub in_air: bool,
}

include!(concat!(env!("OUT_DIR"), "/rolls.rs"));

/// The roll that ability `ability_id` is, if it is one.
pub fn find(ability_id: u32) -> Option<&'static RollSeed> {
    ROLLS.iter().find(|r| r.ability_id == ability_id)
}

/// A roll's length (ms): its hot rule's value when it names one this game has (`rule_ms`, already read), else its
/// own. Never below 0.
pub fn length_ms(seed: &RollSeed, rule_ms: Option<f64>) -> u32 {
    match rule_ms {
        Some(n) if n.is_finite() => n.clamp(0.0, u32::MAX as f64) as u32,
        _ => seed.ms,
    }
}

/// When a roll arriving at `arrived_us` (server micros) was PRESSED, on the server's clock of what its player saw:
/// less its trip here (`credit_ms`: half their quickest round trip, `challenge::press_credit_ms`) and how far behind
/// the server they see everyone (`view_delay_ms`, as their client says with every use: at most `cap_ms`, the
/// referee's `foundation.rewind_max_ms`, so a client claiming more gains nothing past it).
pub fn seen_us(arrived_us: i64, credit_ms: u32, view_delay_ms: u32, cap_ms: u32) -> i64 {
    arrived_us - (credit_ms as i64 + view_delay_ms.min(cap_ms) as i64) * 1000
}

/// Whether a roll its player saw themselves begin at `seen_us` CLEARS a hit that landed at `land_us`: begun before
/// it landed (or at most `late_ms` after: the hand forgiven, `foundation.roll_late_ms`), and still rolling as it did
/// (`roll_ms`, its length). The roll judged where it was pressed, not where it arrived.
pub fn clears(seen_us: i64, land_us: i64, roll_ms: u32, late_ms: u32) -> bool {
    seen_us <= land_us + late_ms as i64 * 1000 && land_us < seen_us + roll_ms as i64 * 1000
}

/// The way a roll goes (a world direction, x east and y south, as `InputFrame.move_dir`): `keys` (x right, y back,
/// as pressed) turned by the body's `yaw`; with none pressed, the way it faces. The client's twin:
/// `RollComponent.direction_for`.
pub fn direction(keys: (f32, f32), yaw: f32) -> (f32, f32) {
    let (kx, ky) = keys;
    let len = (kx * kx + ky * ky).sqrt();
    if len < 0.01 {
        return (-yaw.sin(), -yaw.cos());
    }
    let (x, y) = (kx / len, ky / len);
    // Godot's Vector2.rotated(-yaw).
    let (s, c) = ((-yaw).sin(), (-yaw).cos());
    (x * c - y * s, x * s + y * c)
}
