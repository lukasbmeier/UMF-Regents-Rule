//! THE DODGE ROLL (DECISIONS #309): the foundation's roll as baked, its status, a roll judged where it was pressed
//! (and the hits it does NOT clear), the press's credit capped, a hot rule's length, the way it goes.

use umf_module::roll::{clears, direction, find, length_ms, seen_us, ROLLS};
use umf_module::status;

const MS: i64 = 1000;

#[test]
fn the_foundation_dodge_roll_is_baked() {
    let r = find(1).expect("foundation/content/ability/dodge_roll.tres is ability 1 and rolls");
    assert_eq!((r.status, r.ms, r.ms_rule, r.in_air), (7, 550, "foundation.roll_ms", false));
    assert!(umf_module::hot::find(r.ms_rule).is_some_and(|h| h.number == 550.0), "its length is a live rule, 550 ms unless tuned");
    // Melee (ability 0) is not a roll; an id nobody has is not either.
    assert!(find(0).is_none());
    assert!(find(999_999).is_none());
    assert!(ROLLS.iter().all(|r| status::find(r.status).is_some()), "every roll's status is in the game");
}

#[test]
fn rolling_cannot_be_hit_and_does_not_sprint_or_jump() {
    let s = status::find(7).expect("the foundation's Rolling, status 7");
    assert_eq!(s.name, "Rolling");
    assert!(!s.hittable, "a roll that can be hit dodges nothing");
    assert!(!s.can_sprint && !s.can_jump);
    assert!(s.can_dash, "its body's burst is the dash");
    assert!(s.can_act && s.targetable);
}

#[test]
fn a_roll_pressed_before_the_hit_landed_clears_it() {
    let land = 10_000 * MS;
    // Pressed 100 ms before, 550 ms long: still rolling as it landed.
    assert!(clears(land - 100 * MS, land, 550, 50));
    // Pressed the moment it landed.
    assert!(clears(land, land, 550, 0));
}

#[test]
fn a_roll_pressed_a_little_late_clears_it_within_the_late_window_only() {
    let land = 10_000 * MS;
    assert!(clears(land + 50 * MS, land, 550, 50), "50 ms late, 50 ms forgiven");
    assert!(!clears(land + 51 * MS, land, 550, 50), "51 ms late is late");
    assert!(!clears(land + 1 * MS, land, 550, 0), "nothing forgiven with the rule at 0");
}

#[test]
fn a_roll_over_before_the_hit_landed_does_not_clear_it() {
    let land = 10_000 * MS;
    // Pressed 550 ms before a 550 ms roll: it ended as the hit landed.
    assert!(!clears(land - 550 * MS, land, 550, 50));
    assert!(clears(land - 549 * MS, land, 550, 50));
    assert!(!clears(land - 2_000 * MS, land, 550, 50));
    // A roll of no length clears nothing.
    assert!(!clears(land, land, 0, 50));
}

#[test]
fn the_press_is_credited_its_trip_and_what_the_player_saw_capped() {
    let at = 50_000 * MS;
    // 40 ms of trip, 120 ms behind the server: pressed 160 ms before it arrived.
    assert_eq!(seen_us(at, 40, 120, 150), at - 160 * MS);
    // A client claiming 900 ms behind gains only the cap.
    assert_eq!(seen_us(at, 40, 900, 150), at - 190 * MS);
    // Nothing claimed, nothing measured: judged where it arrived.
    assert_eq!(seen_us(at, 0, 0, 150), at);
}

#[test]
fn a_hot_rule_gives_the_length_live() {
    let r = find(1).unwrap();
    assert_eq!(length_ms(r, None), 550, "no rule: its content's");
    assert_eq!(length_ms(r, Some(700.0)), 700);
    assert_eq!(length_ms(r, Some(-5.0)), 0, "never below 0");
    assert_eq!(length_ms(r, Some(f64::NAN)), 550, "not a number: its content's");
}

#[test]
fn the_way_it_goes_follows_the_keys_turned_by_the_body() {
    let near = |a: (f32, f32), b: (f32, f32)| (a.0 - b.0).abs() < 1e-5 && (a.1 - b.1).abs() < 1e-5;
    // Facing north (yaw 0): forward is -y, right is +x, nothing pressed is forward.
    assert!(near(direction((0.0, -1.0), 0.0), (0.0, -1.0)));
    assert!(near(direction((1.0, 0.0), 0.0), (1.0, 0.0)));
    assert!(near(direction((0.0, 0.0), 0.0), (0.0, -1.0)));
    // Turned a quarter left (yaw pi/2): forward is west, and nothing pressed too.
    let q = std::f32::consts::FRAC_PI_2;
    assert!(near(direction((0.0, -1.0), q), (-1.0, 0.0)));
    assert!(near(direction((0.0, 0.0), q), (-1.0, 0.0)));
    // A diagonal is as long as a straight roll.
    let d = direction((1.0, -1.0), 0.0);
    assert!(((d.0 * d.0 + d.1 * d.1).sqrt() - 1.0).abs() < 1e-5);
    // Negative: backward is not forward.
    assert!(!near(direction((0.0, 1.0), 0.0), (0.0, -1.0)));
}
