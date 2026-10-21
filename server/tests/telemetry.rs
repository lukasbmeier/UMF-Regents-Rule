//! Telemetry's rules (DECISIONS #244): what a report or feedback may hold, cut to size.
use umf_module::telemetry::*;

#[test]
fn long_strings_are_cut_on_a_character_boundary() {
    assert_eq!(cut("short", 64), "short");
    let long = "é".repeat(100); // 2 bytes each
    let c = cut(&long, 51);
    assert!(c.len() <= 51 && c.len() == 50, "cut to 50 bytes, not into the middle of a character: {}", c.len());
    assert_eq!(cut(&"x".repeat(5000), MAX_DETAIL).len(), MAX_DETAIL);
}

#[test]
fn numbers_out_of_sense_are_stored_as_their_floor() {
    assert_eq!(sane(f32::NAN, 0.0, 100.0), 0.0);
    assert_eq!(sane(f32::INFINITY, 0.0, 100.0), 0.0);
    assert_eq!(sane(-5.0, 0.0, 100.0), 0.0);
    assert_eq!(sane(1e9, 0.0, 100.0), 100.0);
    assert_eq!(sane(16.7, 0.0, 100.0), 16.7);
}

#[test]
fn the_moment_noticed_is_theirs_unless_their_clock_is_off() {
    let heard = 1_000_000_000_000_i64;
    assert_eq!(noticed_at(heard - 20_000_000, heard), heard - 20_000_000, "20 s before they sent it: theirs");
    assert_eq!(noticed_at(heard + 5_000_000, heard), heard, "after the server heard it: the server's");
    assert_eq!(noticed_at(heard - NOTICED_BEFORE_MAX_MICROS - 1, heard), heard, "days before (a clock that is off): the server's");
}

#[test]
fn an_unknown_category_is_other() {
    assert_eq!(category(FEEDBACK_LAG), FEEDBACK_LAG);
    assert_eq!(category(200), FEEDBACK_OTHER);
}

#[test]
fn where_everyone_was_is_noted_every_so_often_and_never_when_off() {
    let t = 1_800_000_000_000_000_i64;
    assert!(where_due(t, 0, 5.0), "never noted: now");
    assert!(!where_due(t + 3_000_000, t, 5.0), "3 s after: not yet");
    assert!(where_due(t + 5_000_000, t, 5.0), "5 s after: again");
    assert!(where_due(t + 4_600_000, t, 5.0), "a tick that came a moment early still counts (not stretched to 6 s)");
    assert!(!where_due(t + 4_400_000, t, 5.0), "but not one a whole second early");
    assert!(where_due(t + 60_000_000, t, 60.0) && !where_due(t + 30_000_000, t, 60.0), "a minute");
    assert!(!where_due(t, 0, 0.0) && !where_due(t, 0, -1.0) && !where_due(t, 0, f64::NAN), "0 (or nonsense): never");
}
