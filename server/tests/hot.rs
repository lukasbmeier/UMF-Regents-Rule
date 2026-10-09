//! THE HOT RULES, as compiled in (DECISIONS #201): every rule's default is one `set_rule` would
//! accept, keys are `<owner>.<name>` and unique, the named constants point at their rule, and
//! `check` refuses what an admin may not set.

use umf_module::hot::{self, Kind, Rule};

#[test]
fn every_default_is_a_value_an_admin_could_set() {
    assert!(!hot::ALL.is_empty(), "the foundation declares rules (foundation/content/rules/)");
    for r in hot::ALL {
        assert!(r.check(r.number).is_ok(), "{}: its default {} is outside its own bounds", r.key, r.number);
        let (owner, name) = r.key.split_once('.').expect("a key is <owner>.<name>");
        assert!(!owner.is_empty() && !name.is_empty() && !name.contains('.'), "{}", r.key);
    }
    let mut keys: Vec<&str> = hot::ALL.iter().map(|r| r.key).collect();
    keys.sort();
    keys.dedup();
    assert_eq!(keys.len(), hot::ALL.len(), "keys are unique");
}

#[test]
fn named_constants_point_at_their_rules() {
    assert_eq!(hot::foundation::INTERACT_RANGE_M.key, "foundation.interact_range_m");
    assert_eq!(hot::foundation::NEW_PLAYER_HEALTH.key, "foundation.new_player_health");
    assert!(hot::find("foundation.interact_range_m").is_some());
    assert!(hot::find("foundation.nope").is_none());
}

#[test]
fn check_refuses_what_an_admin_may_not_set() {
    let n = Rule { key: "t.n", kind: Kind::Number, number: 1.0, text: "", min: 0.5, max: 2.0 };
    assert!(n.check(0.5).is_ok() && n.check(2.0).is_ok());
    assert!(n.check(0.49).is_err() && n.check(2.01).is_err());
    assert!(n.check(f64::NAN).is_err() && n.check(f64::INFINITY).is_err());
    let i = Rule { key: "t.i", kind: Kind::Integer, number: 3.0, text: "", min: 0.0, max: 10.0 };
    assert!(i.check(4.0).is_ok() && i.check(4.5).is_err());
    let f = Rule { key: "t.f", kind: Kind::Flag, number: 0.0, text: "", min: 0.0, max: 1.0 };
    assert!(f.check(1.0).is_ok() && f.check(0.5).is_err());
    let t = Rule { key: "t.t", kind: Kind::Text, number: 0.0, text: "hi", min: 0.0, max: 0.0 };
    assert!(t.check(123.0).is_ok(), "a text rule ignores the number");
}
