//! THE SERVER PUSHES PEOPLE (DECISIONS #251): a push's bound, and a player's bound widened by the pushes
//! they are under (the module's movement tick uses this one).

use umf_module::content::MovementLimits;
use umf_module::push::{bounded, widened, MAX_PUSH_MPS, PUSH_DRAG_MPS2};
use umf_module::sim::Vector3;

const RUNNER: MovementLimits = MovementLimits { run: 5.5, sprint: 8.0, burst: 0.0, lift: 5.0 };

#[test]
fn a_push_is_finite_and_no_harder_than_the_most() {
    assert_eq!(bounded(Vector3::new(3.0, 4.0, 0.0)), Some(Vector3::new(3.0, 4.0, 0.0)), "a fair push, as written");
    let hard = bounded(Vector3::new(0.0, 0.0, 400.0)).unwrap();
    assert!((hard.z - MAX_PUSH_MPS).abs() < 1e-4 && hard.x == 0.0, "a huge one, clamped along itself: {hard:?}");
    assert!(bounded(Vector3::new(f32::NAN, 0.0, 0.0)).is_none(), "not a number: none");
    assert!(bounded(Vector3::new(0.0, f32::INFINITY, 0.0)).is_none());
}

#[test]
fn pushes_widen_the_bound_sideways_and_up_and_add_up() {
    let none = widened(RUNNER, std::iter::empty(), 0.5);
    assert_eq!((none.burst, none.lift), (0.0, 5.0), "no push: their own bound");
    let blower = widened(RUNNER, [(Vector3::new(6.0, 0.0, 8.0), 0.2)].into_iter(), 0.5);
    assert!((blower.burst - 10.0).abs() < 1e-5 && blower.lift == 5.0, "a blower's 10 m/s sideways: {blower:?}");
    let pad = widened(RUNNER, [(Vector3::new(0.0, 12.0, 4.0), 0.1)].into_iter(), 0.5);
    assert!((pad.burst - 4.0).abs() < 1e-5 && (pad.lift - 17.0).abs() < 1e-5, "a pad's 12 up and 4 along: {pad:?}");
    let two = widened(RUNNER, [(Vector3::new(5.0, 0.0, 0.0), 0.0), (Vector3::new(0.0, 0.0, 5.0), 0.0)].into_iter(), 0.5);
    assert!((two.burst - 10.0).abs() < 1e-5, "two pushes add up");
    let down = widened(RUNNER, [(Vector3::new(0.0, -9.0, 0.0), 0.0)].into_iter(), 0.5);
    assert_eq!(down.lift, 5.0, "a push down widens nothing");
    assert_eq!((down.run, down.sprint), (5.5, 8.0), "and the gaits are their own");
}

#[test]
fn the_bound_follows_the_carry_down() {
    let one_s = widened(RUNNER, [(Vector3::new(10.0, 0.0, 0.0), 1.5)].into_iter(), 0.5);
    assert!((one_s.burst - (10.0 - PUSH_DRAG_MPS2)).abs() < 1e-4, "a second past its grace: 10 less a second's drag ({})", one_s.burst);
    let gone = widened(RUNNER, [(Vector3::new(10.0, 0.0, 0.0), 4.0)].into_iter(), 0.5);
    assert_eq!(gone.burst, 0.0, "carried out: their own bound again");
    let topped = widened(RUNNER, [(Vector3::new(0.0, 9.8, 0.0), 1.6)].into_iter(), 0.5);
    assert_eq!(topped.lift, 5.0, "a push up, past its top and the grace: no more lift");
    let rising = widened(RUNNER, [(Vector3::new(0.0, 9.8, 0.0), 1.4)].into_iter(), 0.5);
    assert!((rising.lift - 14.8).abs() < 1e-4, "still rising (within the grace): its lift");
}
