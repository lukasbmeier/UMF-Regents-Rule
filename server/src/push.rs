//! THE SERVER PUSHES PEOPLE (docs/FOUNDATION_SYSTEMS.md milestone 15, DECISIONS #251): a genre's rule
//! decides something moved a person (a leaf blower, a bounce pad, a disc to the face) and writes a push,
//! a change of velocity. A player moves themselves (Tier A), so the push is applied by THEIR client,
//! inside its own prediction, and the module, which wrote it, lets that player move as fast as the push
//! makes them for a while: their bound is widened by it. Nobody is server-moved, and the bound is the only
//! check. A body (a disc) is pushed by its referee, which flies it. Pure, so the native suites check it.

use crate::content::MovementLimits;
use crate::sim::Vector3;

/// The hardest one push may be, m/s (a genre's push is clamped to it).
pub const MAX_PUSH_MPS: f32 = 40.0;
/// How fast a push's sideways speed is lost, m/s a second: the pushed client carries it at least this
/// long (`SpaceTimeMovementComponent.PUSH_DRAG_MPS2`, the same number), and the bound follows it down.
pub const PUSH_DRAG_MPS2: f32 = 6.0;
/// Gravity, for how long a push up lasts: Earth's, lower than any game's model (the template's is 20,
/// shared/movement_config.json), so the bound outlasts the rise rather than cutting it short.
const GRAVITY: f32 = 9.8;

/// A push as written: finite, and no harder than `MAX_PUSH_MPS`.
pub fn bounded(vel: Vector3) -> Option<Vector3> {
    if !(vel.x.is_finite() && vel.y.is_finite() && vel.z.is_finite()) {
        return None;
    }
    let len = (vel.x * vel.x + vel.y * vel.y + vel.z * vel.z).sqrt();
    if len <= MAX_PUSH_MPS {
        return Some(vel);
    }
    let k = MAX_PUSH_MPS / len;
    Some(Vector3::new(vel.x * k, vel.y * k, vel.z * k))
}

/// A player's bound with the pushes they are under, each `(vel, age_s)`: a push's sideways speed added to
/// the burst they may have, less what its carry has lost by now (`PUSH_DRAG_MPS2`, counted from `grace_s`
/// after it: the rows lag); its upward speed added to the lift until it would have topped out (and
/// `grace_s`). Pushes add up (two blowers at once are twice as fast); a push down widens nothing (the
/// bound's fall is already a fall's).
pub fn widened(limits: MovementLimits, pushes: impl Iterator<Item = (Vector3, f32)>, grace_s: f32) -> MovementLimits {
    let mut out = limits;
    for (v, age) in pushes {
        let late = (age - grace_s).max(0.0);
        out.burst += ((v.x * v.x + v.z * v.z).sqrt() - PUSH_DRAG_MPS2 * late).max(0.0);
        if v.y > 0.0 && age <= v.y / GRAVITY + grace_s {
            out.lift += v.y;
        }
    }
    out
}
