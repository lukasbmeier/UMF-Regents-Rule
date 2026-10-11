//! THE SERVER-TIMED PRESS (DECISIONS #210): the sweep, a press's quality, the credit for the trip to
//! the server. The client's twin (`ChallengeModel.sweep_position`...) is checked against the same
//! numbers in the `challenge` unit suite.

use umf_module::challenge::{grade, judged_position, press_credit_ms, press_quality, sweep_period_s, sweep_position, Grade, GREAT_FROM,
    KIND_TIMED_PRESS};

#[test]
fn the_sweep_goes_there_and_back() {
    assert_eq!(sweep_position(-0.5, 2.0), 0.0, "before it begins: at the start");
    assert_eq!(sweep_position(0.0, 2.0), 0.0);
    assert!((sweep_position(0.5, 2.0) - 0.5).abs() < 1e-6, "a quarter period: half way");
    assert!((sweep_position(1.0, 2.0) - 1.0).abs() < 1e-6, "half a period: the far end");
    assert!((sweep_position(1.5, 2.0) - 0.5).abs() < 1e-6, "on its way back");
    assert!((sweep_position(2.5, 2.0) - 0.5).abs() < 1e-6, "and round again");
    assert_eq!(sweep_position(1.0, 0.0), 0.0, "no period: nowhere");
}

#[test]
fn a_press_is_judged_where_the_player_saw_the_marker() {
    // A 2 s sweep, the press arriving 600 ms after it began, from a player 160 ms away (80 each way).
    let credit = press_credit_ms(Some(160), 120);
    assert_eq!(credit, 80, "half the round trip");
    let (at, pos) = judged_position(600, credit, 2.0);
    assert_eq!(at, 520, "judged 80 ms before it arrived");
    assert!((pos - 0.52).abs() < 1e-6, "where the marker was then ({pos})");
    assert_eq!(press_credit_ms(Some(400), 120), 120, "a slow connection is credited at most the cap");
    assert_eq!(press_credit_ms(None, 120), 0, "nothing measured: no credit");
}

#[test]
fn quality_and_difficulty() {
    assert_eq!(press_quality(0.5, 0.5, 0.1), 1.0, "dead centre");
    assert!((press_quality(0.55, 0.5, 0.1) - 0.5).abs() < 1e-5, "half way to the edge");
    assert_eq!(press_quality(0.7, 0.5, 0.1), 0.0, "outside");
    assert_eq!(press_quality(0.5, 0.5, 0.0), 0.0, "no window: nothing");
    assert!((sweep_period_s(0.0, 2.4, 1.2) - 2.4).abs() < 1e-6 && (sweep_period_s(1.0, 2.4, 1.2) - 1.2).abs() < 1e-6,
        "easy sweeps slowly, hard quickly");
    assert!((sweep_period_s(5.0, 2.4, 1.2) - 1.2).abs() < 1e-6, "difficulty is held to 0..1");
    assert_eq!(KIND_TIMED_PRESS, 1);
}

#[test]
fn a_press_is_paid_in_the_words_the_player_saw() {
    // DECISIONS #219: a genre pays its check by the grade the bar showed (TimingBar.word_for).
    assert_eq!(GREAT_FROM, 0.75);
    assert_eq!(grade(1.0), Grade::Great, "dead centre");
    assert_eq!(grade(GREAT_FROM), Grade::Great, "Great from its threshold");
    assert_eq!(grade(GREAT_FROM - 0.01), Grade::Good, "just under it: Good");
    assert_eq!(grade(0.01), Grade::Good, "anything inside the zone: Good");
    assert_eq!(grade(0.0), Grade::Miss, "outside it: a Miss");
}
