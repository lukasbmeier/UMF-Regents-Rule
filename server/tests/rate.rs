//! The rate limit's arithmetic (REVIEW 0.23.1 B3), and that `shared/rules.json` gives every reducer
//! the module limits a budget an honest client never meets.
//!   cargo test --test rate

use umf_module::rules::{rate_limit, rate_spend, RateLimit};

const L: RateLimit = RateLimit { verb: "test", burst: 3.0, per_sec: 2.0 };

#[test]
fn a_burst_then_refusal_then_the_allowance_comes_back() {
    // A fresh budget is full: `burst` calls at once, and the next is refused.
    let mut t = None;
    for _ in 0..3 {
        t = Some(rate_spend(t, 0.0, &L).expect("inside the burst"));
    }
    assert_eq!(rate_spend(t, 0.0, &L), None, "the call past the burst is refused");
    // Refused calls change nothing, so the allowance still comes back at per_sec.
    assert_eq!(rate_spend(t, 0.25, &L), None, "half a token is not a call");
    assert_eq!(rate_spend(t, 0.5, &L), Some(0.0), "after 1/per_sec seconds, one more call");
    // Never more than the burst, however long the player waited.
    assert_eq!(rate_spend(Some(0.0), 3600.0, &L), Some(2.0));
    // A clock that went backwards refills nothing.
    assert_eq!(rate_spend(Some(0.0), -5.0, &L), None);
}

#[test]
fn honest_clients_stay_inside_the_shipped_limits() {
    // The fight is reported every 0.2 s and at once when its tell changes (fishing_component.gd,
    // SHOW_INTERVAL_SEC): at worst a change on every physics frame for a moment. A second of
    // reports at 5 a second, then 8 changes inside 0.1 s, then reports again, must all pass.
    let l = rate_limit("show_fight");
    let mut t = None;
    let mut calls: Vec<f64> = (0..5).map(|k| k as f64 * 0.2).collect();
    calls.extend((0..8).map(|k| 1.0 + k as f64 / 60.0));
    calls.extend((0..25).map(|k| 1.2 + k as f64 * 0.2));
    let mut last = 0.0;
    for at in calls {
        t = Some(rate_spend(t, at - last, l).unwrap_or_else(|| panic!("show_fight refused at {at:.2} s")));
        last = at;
    }
    // Every limited reducer has its own line in rules.json, not the default by accident.
    for verb in ["show_fight", "set_equip_state", "set_appearance", "set_player_name", "set_ready", "set_team",
                 "join_session", "leave_session"] {
        assert_eq!(rate_limit(verb).verb, verb, "shared/rules.json has no rate_limits.{verb}");
    }
}
