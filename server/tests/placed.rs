//! A PLACE THE SERVER PUT SOMEONE IS NOT UNDONE BY THEIR AUTHORITY'S LAST WRITE (DECISIONS #252).

use umf_module::placed::{stale, PLACED_NEAR_M, PLACED_WAIT_US};
use umf_module::sim::Vector3;

const TEE: Vector3 = Vector3 { x: 0.0, y: 0.05, z: 0.0 };
const BASKET: Vector3 = Vector3 { x: 22.0, y: 0.0, z: -90.0 };

#[test]
fn a_write_from_before_the_move_is_dropped() {
    assert!(stale(true, TEE, 50_000, false, BASKET), "the authority still had them at the basket");
}

#[test]
fn the_authoritys_own_word_stands() {
    assert!(!stale(true, TEE, 50_000, false, Vector3 { x: 0.4, y: 0.05, z: -0.3 }), "a tick on from the tee: it adopted the move");
    assert!(!stale(true, TEE, 50_000, true, BASKET), "its own teleport");
    assert!(!stale(false, TEE, 50_000, false, BASKET), "an ordinary row: it is the authority on motion");
}

#[test]
fn a_move_it_never_sees_is_not_held_for_ever() {
    assert!(!stale(true, TEE, PLACED_WAIT_US, false, BASKET));
    assert!(!stale(true, TEE, -1, false, BASKET), "a row from the future (a clock step): not held");
}

#[test]
fn near_is_a_ticks_motion() {
    assert!(!stale(true, TEE, 0, false, Vector3 { x: PLACED_NEAR_M * 0.99, y: 0.05, z: 0.0 }));
    assert!(stale(true, TEE, 0, false, Vector3 { x: PLACED_NEAR_M * 1.01, y: 0.05, z: 0.0 }));
}
