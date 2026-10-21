//! ITEMS ON THE GROUND (DECISIONS #269): the cell a drop is in, where a kill's drops land, the reach.

use umf_module::ground::{ahead_of, chunk_of, scatter, within_reach, DROP_AHEAD_M, SCATTER_M};
use umf_module::sim::Vector3;

#[test]
fn a_drop_is_in_the_64_m_cell_it_lies_in() {
    let at = |x: f32, z: f32| chunk_of(Vector3::new(x, 0.0, z));
    assert_eq!(at(0.0, 0.0), 512 * 1024 + 512, "the origin's cell");
    assert_eq!(at(63.9, 63.9), at(0.0, 0.0), "one cell is 64 m");
    assert_eq!(at(64.0, 0.0), 513 * 1024 + 512, "the next one east");
    assert_eq!(at(-0.1, 0.0), 511 * 1024 + 512, "and west of the origin");
    assert_eq!(at(0.0, 64.0), at(0.0, 0.0) + 1, "north is the next index");
    assert_eq!(at(1.0e9, -1.0e9), 1023 * 1024, "far out: clamped to the grid's edge");
}

#[test]
fn a_kills_drops_lie_round_where_it_fell() {
    let at = Vector3::new(10.0, 2.0, -4.0);
    assert_eq!(scatter(at, 0, 1), at, "one: where it fell");
    assert_eq!(scatter(at, 0, 4), at, "the first of several too");
    let rest: Vec<Vector3> = (1..4).map(|i| scatter(at, i, 4)).collect();
    for p in &rest {
        let d = ((p.x - at.x).powi(2) + (p.z - at.z).powi(2)).sqrt();
        assert!((d - SCATTER_M).abs() < 1e-4 && p.y == at.y, "the others on a ring {SCATTER_M} m out: {p:?}");
    }
    for (i, a) in rest.iter().enumerate() {
        for b in &rest[i + 1..] {
            assert!(((a.x - b.x).powi(2) + (a.z - b.z).powi(2)).sqrt() > 0.5, "never in one heap: {a:?} {b:?}");
        }
    }
}

#[test]
fn a_pick_up_reaches_its_distance_and_no_further() {
    let me = Vector3::new(0.0, 0.0, 0.0);
    assert!(within_reach(me, Vector3::new(2.4, 0.0, 0.0), 2.5));
    assert!(!within_reach(me, Vector3::new(2.6, 0.0, 0.0), 2.5));
    assert!(within_reach(me, Vector3::new(1.5, 1.5, 0.0), 2.5), "a step up counts at half its height");
    assert!(!within_reach(me, Vector3::new(0.0, 6.0, 0.0), 2.5), "but a ledge far above does not");
}

#[test]
fn a_drop_lands_a_step_in_front_of_you() {
    let me = Vector3::new(2.0, 1.0, 3.0);
    let north = ahead_of(me, 0.0, DROP_AHEAD_M);
    assert!((north.x - 2.0).abs() < 1e-5 && (north.z - (3.0 - DROP_AHEAD_M)).abs() < 1e-5 && north.y == 1.0, "facing -Z: in front, at your height ({north:?})");
    let west = ahead_of(me, std::f32::consts::FRAC_PI_2, DROP_AHEAD_M);
    assert!((west.x - (2.0 - DROP_AHEAD_M)).abs() < 1e-5 && (west.z - 3.0).abs() < 1e-5, "turned a quarter left: to the west ({west:?})");
    assert!(DROP_AHEAD_M > 1.0, "far enough not to be at your feet");
}
