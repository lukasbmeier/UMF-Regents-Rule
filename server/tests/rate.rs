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
fn every_limited_foundation_reducer_has_its_own_line() {
    // Every reducer the foundation limits has its own line in rules.json, not the default by
    // accident. A genre checks its own verbs the same way (fishing: tests/fishing.rs).
    for verb in ["set_equip_state", "set_appearance", "set_player_name", "set_ready", "set_team",
                 "join_session", "leave_session"] {
        assert_eq!(rate_limit(verb).verb, verb, "shared/rules.json has no rate_limits.{verb}");
    }
}
