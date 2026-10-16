//! Bodies the referee moves (DECISIONS #246): what the module checks of a player's throw, which of a
//! launcher's bodies go when it throws one too many, and when one has outlived its lifetime.

use umf_module::body::{check_throw, expired, over_limit, BodySeed, Throw, BODIES};
use umf_module::sim::Vector3;

const BALL: BodySeed = BodySeed {
    id: 1,
    name: "ball",
    launchers: &[0],
    max_speed: 25.0,
    max_spin: 30.0,
    reach: 2.0,
    max_per_owner: 3,
    lifetime_s: 60.0,
};

fn throw(origin: Vector3, vel: Vector3, spin: Vector3) -> Throw {
    Throw { origin, vel, spin }
}

#[test]
fn a_throw_inside_the_bounds_is_taken() {
    let t = throw(Vector3::new(1.0, 1.5, 0.0), Vector3::new(0.0, 5.0, -20.0), Vector3::new(0.0, 10.0, 0.0));
    assert!(check_throw(&BALL, 0, Vector3::new(0.0, 0.0, 0.0), 0.0, &t).is_ok());
}

#[test]
fn a_kind_that_may_not_throw_it_is_refused() {
    let t = throw(Vector3::ZERO, Vector3::new(0.0, 0.0, -5.0), Vector3::ZERO);
    let e = check_throw(&BALL, 100, Vector3::ZERO, 0.0, &t).unwrap_err();
    assert!(e.contains("not something you can throw"), "{e}");
    let genre_only = BodySeed { launchers: &[], ..BALL };
    assert!(check_throw(&genre_only, 0, Vector3::ZERO, 0.0, &t).is_err(), "no launchers: only a genre's rules launch it");
}

#[test]
fn too_fast_or_spun_too_hard_is_refused() {
    let fast = throw(Vector3::ZERO, Vector3::new(0.0, 0.0, -25.01), Vector3::ZERO);
    assert!(check_throw(&BALL, 0, Vector3::ZERO, 0.0, &fast).unwrap_err().contains("faster than"));
    let at = throw(Vector3::ZERO, Vector3::new(0.0, 0.0, -25.0), Vector3::ZERO);
    assert!(check_throw(&BALL, 0, Vector3::ZERO, 0.0, &at).is_ok(), "exactly the max is allowed");
    let spun = throw(Vector3::ZERO, Vector3::ZERO, Vector3::new(30.5, 0.0, 0.0));
    assert!(check_throw(&BALL, 0, Vector3::ZERO, 0.0, &spun).unwrap_err().contains("spin"));
}

#[test]
fn too_far_from_the_thrower_is_refused_its_slack_allowed() {
    let t = throw(Vector3::new(3.0, 0.0, 0.0), Vector3::ZERO, Vector3::ZERO);
    assert!(check_throw(&BALL, 0, Vector3::ZERO, 0.0, &t).unwrap_err().contains("within 2.00 m"));
    assert!(check_throw(&BALL, 0, Vector3::ZERO, 1.5, &t).is_ok(), "a thrower who has run on since its last row: its slack");
    assert!(check_throw(&BALL, 0, Vector3::ZERO, -5.0, &throw(Vector3::new(1.9, 0.0, 0.0), Vector3::ZERO, Vector3::ZERO)).is_ok(),
        "a negative slack is no slack, not less reach");
}

#[test]
fn a_throw_that_is_not_finite_is_refused() {
    let t = throw(Vector3::ZERO, Vector3::new(f32::NAN, 0.0, 0.0), Vector3::ZERO);
    assert!(check_throw(&BALL, 0, Vector3::ZERO, 0.0, &t).unwrap_err().contains("finite"));
    let t = throw(Vector3::new(f32::INFINITY, 0.0, 0.0), Vector3::ZERO, Vector3::ZERO);
    assert!(check_throw(&BALL, 0, Vector3::ZERO, 0.0, &t).is_err());
}

#[test]
fn one_too_many_takes_the_oldest_away() {
    assert!(over_limit(vec![(10, 100), (11, 200)], 3).is_empty(), "two of three: room for one more");
    assert_eq!(over_limit(vec![(11, 200), (10, 100), (12, 300)], 3), vec![10], "three of three: the oldest goes");
    assert_eq!(over_limit(vec![(11, 200), (10, 100), (12, 300), (13, 50)], 3), vec![13, 10], "over already: as many as it takes, oldest first");
    assert!(over_limit(vec![(1, 1); 50], 0).is_empty(), "0: any number");
}

#[test]
fn a_body_outlives_its_lifetime_only_when_it_has_one() {
    assert!(!expired(&BALL, 0, 59_000_000));
    assert!(expired(&BALL, 0, 61_000_000));
    let forever = BodySeed { lifetime_s: 0.0, ..BALL };
    assert!(!expired(&forever, 0, i64::MAX / 2));
}

#[test]
fn the_baked_bodies_have_unique_ids_and_sane_bounds() {
    let mut ids: Vec<u32> = BODIES.iter().map(|b| b.id).collect();
    ids.sort();
    ids.dedup();
    assert_eq!(ids.len(), BODIES.len());
    for b in BODIES {
        assert!(b.max_speed >= 0.0 && b.max_spin >= 0.0 && b.reach >= 0.0 && b.lifetime_s >= 0.0, "{}", b.name);
    }
}
