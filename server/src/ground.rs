//! ITEMS ON THE GROUND (DECISIONS #269): where a drop lands and which cell it is in. The table, the
//! windows (its owner's, then anyone's) and the reducers are `module/ground.rs`. Pure, so the native
//! suites check it.

use crate::sim::Vector3;

/// The cell a drop lies in: the world's cells (`crate::cell`, template 1.0) cut every placed row.
pub use crate::cell::{chunk_of, CELL_M as CHUNK_M};
/// How far apart a kill's drops lie, m.
pub const SCATTER_M: f32 = 0.6;

/// Where the `i`th of `n` drops from one spot lands: the first on it, the rest round it on a ring
/// `SCATTER_M` out, evenly (so a kill's sacks never sit in one heap).
pub fn scatter(at: Vector3, i: usize, n: usize) -> Vector3 {
    if n <= 1 || i == 0 {
        return at;
    }
    let a = std::f32::consts::TAU * (i - 1) as f32 / (n - 1) as f32;
    Vector3::new(at.x + SCATTER_M * a.cos(), at.y, at.z + SCATTER_M * a.sin())
}

/// How far in front of a player a dropped stack lands, m (owner, 2026-10-20: dropped at the feet, it was
/// picked straight back up "like a magnet").
pub const DROP_AHEAD_M: f32 = 1.4;

/// Where a stack dropped by someone at `pos` facing `yaw` (the look yaw: forward is -Z turned by it) lands.
pub fn ahead_of(pos: Vector3, yaw: f32, dist: f32) -> Vector3 {
    Vector3::new(pos.x - yaw.sin() * dist, pos.y, pos.z - yaw.cos() * dist)
}

/// Whether someone at `me` may pick up what lies at `at`: within `reach` m on the ground (height
/// counts at half, a step up or a slope).
pub fn within_reach(me: Vector3, at: Vector3, reach: f32) -> bool {
    let (dx, dy, dz) = (me.x - at.x, (me.y - at.y) * 0.5, me.z - at.z);
    dx * dx + dy * dy + dz * dz <= reach * reach
}
