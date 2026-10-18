//! A PLACE THE SERVER PUT SOMEONE IS NOT UNDONE BY THEIR AUTHORITY'S LAST WRITE (DECISIONS #252). The
//! module moves an entity a sidecar simulates (`place_entity`: a hole's tee, a session move) with a
//! teleport row; the sidecar adopts it when the row reaches it. Until then its writes still say where
//! it had the entity, and one landing just after the move put it straight back (DiscGolf, 2026-10-17:
//! bots left at the last basket, walking ninety metres to the next tee, one stuck on the way). Pure,
//! so the native suites check it.

use crate::sim::Vector3;

/// How long a placed row waits for its authority to see it, microseconds: a write that disagrees with
/// it within this is from before the move. Far more than a sidecar's round trip; after it, the
/// authority's word is taken again (an authority that never adopts is not left frozen).
pub const PLACED_WAIT_US: i64 = 1_000_000;
/// How far a write may be from the placed position and still be the authority's, metres: a tick's
/// motion from it (a sprint, a dash) and no more. Our own echo of the place is at it.
pub const PLACED_NEAR_M: f32 = 1.5;

/// Whether an authority's write `write_pos` (`write_teleport`: the authority's own move) lands on a row
/// that is a teleport (`row_teleport`) at `row_pos`, written `age_us` ago, from before it saw that move.
pub fn stale(row_teleport: bool, row_pos: Vector3, age_us: i64, write_teleport: bool, write_pos: Vector3) -> bool {
    if !row_teleport || write_teleport || !(0..PLACED_WAIT_US).contains(&age_us) {
        return false;
    }
    let (dx, dy, dz) = (write_pos.x - row_pos.x, write_pos.y - row_pos.y, write_pos.z - row_pos.z);
    dx * dx + dy * dy + dz * dz > PLACED_NEAR_M * PLACED_NEAR_M
}
