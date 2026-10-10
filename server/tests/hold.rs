//! HOLD TO INTERACT (DECISIONS #209): the pure rules a hold is done by (`crate::hold`), with the
//! game's own holds (the foundation's Help up) and made-up ones.

use umf_module::hold::{self, left, HoldSeed};

const NEST: HoldSeed = HoldSeed {
    id: 9001, name: "Lay", verb: 0, targets: &[25], doers: &[20], when: -1, seconds_with: &[58.0, 20.0, 6.0],
    range_m: 2.0, max_doers: 0, keeps_progress: true, stopped_by_damage: true, stopped_by_moving_m: 0.5, then_status: -1,
};

#[test]
fn the_foundations_help_up_is_compiled_in() {
    let h = hold::find(0, 0, umf_module::status::DOWNED, 0).expect("a press on a downed player starts Help up");
    assert_eq!(h.name, "Help up");
    assert_eq!(h.then_status, umf_module::status::NORMAL as i16, "and gets them back to normal");
    assert!(hold::find(1, 0, umf_module::status::DOWNED, 0).is_some(), "an NPC too");
    assert!(hold::find(0, 0, umf_module::status::NORMAL, 0).is_none(), "nothing to help up on someone standing");
    assert!(hold::find(0, 1, umf_module::status::DOWNED, 0).is_none(), "nor with another verb");
    assert_eq!(hold::by_id(h.id).map(|x| x.name), Some("Help up"));
}

#[test]
fn faster_together() {
    assert_eq!(hold::rate(&NEST, 0), 0.0, "nobody: it does not move");
    assert!((hold::rate(&NEST, 1) - 1.0 / 58.0).abs() < 1e-6);
    assert!((hold::rate(&NEST, 3) - 1.0 / 6.0).abs() < 1e-6, "three: six seconds");
    assert_eq!(hold::rate(&NEST, 7), hold::rate(&NEST, 3), "the last time applies to more");
}

#[test]
fn progress_is_a_line() {
    assert!((hold::progress_at(0.25, 0.5, 1.0) - 0.75).abs() < 1e-6);
    assert_eq!(hold::progress_at(0.5, 0.5, 5.0), 1.0, "never past done");
    assert_eq!(hold::progress_at(0.1, -0.05, 10.0), 0.0, "nor below nothing, undoing");
    assert_eq!(hold::progress_at(0.4, 0.5, -3.0), 0.4, "a clock that went back changes nothing");
    assert_eq!(hold::seconds_left(0.5, 0.25), Some(2.0));
    assert_eq!(hold::seconds_left(0.5, 0.0), None, "not getting there");
}

#[test]
fn who_it_applies_to() {
    assert!(hold::applies(&NEST, 25, 0, 0, 20), "a chicken presses on a nest");
    assert!(!hold::applies(&NEST, 25, 0, 0, 21), "a wolf does not lay");
    assert!(hold::still_applies(&NEST, 7), "any status, when `when` is -1");
}

#[test]
fn letting_go() {
    let at = [0.0, 0.0, 0.0];
    assert_eq!(hold::keeps_hold(&NEST, at, [1.0, 0.0, 0.0], [2.0, 0.0, 0.0], 2.0, 0.5), Some(left::MOVED), "a metre from where it began");
    assert_eq!(hold::keeps_hold(&NEST, at, [0.3, 0.0, 0.0], [2.0, 0.0, 0.0], 2.0, 0.5), None, "a step is fine");
    assert_eq!(hold::keeps_hold(&NEST, at, at, [2.4, 0.0, 0.0], 2.0, 0.5), None, "past the reach, within the slack");
    assert_eq!(hold::keeps_hold(&NEST, at, at, [2.6, 0.0, 0.0], 2.0, 0.5), Some(left::OUT_OF_RANGE), "past the slack");
    let roams = HoldSeed { stopped_by_moving_m: 0.0, ..NEST };
    assert_eq!(hold::keeps_hold(&roams, at, [1.5, 0.0, 0.0], [2.0, 0.0, 0.0], 2.0, 0.5), None, "0: moving does not stop it");
}
