//! THE WORLD IN SQUARES (template 1.0, DECISIONS #278, `docs/TEMPLATE_1_0.md` §3). Every row of a placed
//! thing carries the cell it is in (`chunk`), so a client far from it is never sent it (ring interest,
//! the client's `InterestManager`). The side is the game's data (`shared/rules.json` `cells.cell_m`,
//! 64 m); the client's twin is `foundation/net/cells.gd`, held to the same answers by the `cells` suite.
//! Pure, so the native suites check it.

use crate::sim::Vector3;

/// The side of a cell, m.
pub const CELL_M: f32 = crate::rules::CELL_M;
/// Cells along each side of the grid: 1024, half either side of the origin (65 km a side at 64 m).
pub const GRID: i64 = 1024;
const HALF: i64 = GRID / 2;
/// The cell of a PARKED character (template 1.0): put away while its player is gone, its rows kept where
/// no client asks (no place is in it), its position untouched for when it comes back.
pub const NOWHERE: u32 = u32::MAX;

/// The cell `pos` is in: `(x cell + 512) * 1024 + (z cell + 512)`, clamped to the grid's edge.
pub fn chunk_of(pos: Vector3) -> u32 {
    at(axis(pos.x), axis(pos.z))
}

/// Which square along one axis a coordinate is in (0 at the origin's, negative west or north of it).
pub fn axis(v: f32) -> i64 {
    ((v / CELL_M).floor() as i64).clamp(-HALF, HALF - 1)
}

/// The cell at squares `x`, `z` (as `axis` counts them), clamped to the grid.
pub fn at(x: i64, z: i64) -> u32 {
    ((x.clamp(-HALF, HALF - 1) + HALF) * GRID + (z.clamp(-HALF, HALF - 1) + HALF)) as u32
}

/// The squares a cell is at, as `axis` counts them.
pub fn squares(chunk: u32) -> (i64, i64) {
    let c = chunk as i64;
    (c / GRID - HALF, c % GRID - HALF)
}

/// The cells within `r` squares of `chunk` (itself and its neighbours: 3 x 3 at 1), each once, those
/// past the grid's edge left out.
pub fn ring(chunk: u32, r: u32) -> Vec<u32> {
    let (cx, cz) = squares(chunk);
    let r = r as i64;
    let mut out = Vec::new();
    for x in (cx - r)..=(cx + r) {
        for z in (cz - r)..=(cz + r) {
            if (-HALF..HALF).contains(&x) && (-HALF..HALF).contains(&z) {
                out.push(at(x, z));
            }
        }
    }
    out
}
