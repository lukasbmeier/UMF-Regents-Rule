//! WHICH HOLD A PRESS STARTS (DECISIONS #209): the rules build.rs builds a game's holds by
//! (`build/hold_rules.rs`), checked here with genres the template does not have.

#[path = "../build/hold_rules.rs"]
mod hold_rules;
use hold_rules::{choose, overlap, HoldKey};

fn h(owner: &str, name: &str, verb: u8, targets: &[u8], doers: &[u8], when: Option<u8>) -> HoldKey {
    HoldKey { owner: owner.into(), name: name.into(), verb, targets: targets.to_vec(), doers: doers.to_vec(), when }
}

fn genres(g: &[&str]) -> Vec<String> {
    g.iter().map(|x| x.to_string()).collect()
}

#[test]
fn a_genres_hold_comes_before_the_foundations_it_replaces() {
    let all = vec![h("foundation", "Help up", 0, &[0, 1], &[], Some(2)), h("hens", "Hen help up", 0, &[0], &[], Some(2)),
        h("hens", "Lay", 0, &[25], &[20], None)];
    assert_eq!(choose(&all, &genres(&["hens"])).unwrap(), vec![1, 2, 0], "the genre's first, so a press on a downed player starts the hen's");
}

#[test]
fn presses_that_differ_are_told_apart() {
    // The same nest and key: a chicken lays, a wolf cracks.
    assert!(!overlap(&h("hens", "Lay", 0, &[25], &[20], None), &h("hens", "Crack", 0, &[25], &[21], None)), "by who does it");
    assert!(!overlap(&h("f", "Help up", 0, &[0], &[], Some(2)), &h("f", "Search", 0, &[0], &[], Some(5))), "by the target's status");
    assert!(!overlap(&h("f", "a", 0, &[0], &[], None), &h("f", "b", 1, &[0], &[], None)), "by the verb");
    assert!(!overlap(&h("f", "a", 0, &[0], &[], None), &h("f", "b", 0, &[1], &[], None)), "by what it is done to");
    assert!(overlap(&h("f", "a", 0, &[0, 1], &[], Some(2)), &h("f", "b", 0, &[1], &[20], None)),
        "anyone, any status and a shared kind: one press could start both");
}

#[test]
fn refused() {
    let one_owner = vec![h("hens", "Lay", 0, &[25], &[], None), h("hens", "Sit", 0, &[25], &[20], None)];
    let e = choose(&one_owner, &genres(&["hens"])).unwrap_err();
    assert!(e.contains("two holds one press could start") && e.contains("Lay") && e.contains("Sit"), "{e}");
    let two_genres = vec![h("hens", "Lay", 0, &[25], &[], None), h("ducks", "Paddle", 0, &[25], &[], None)];
    let e = choose(&two_genres, &genres(&["hens", "ducks"])).unwrap_err();
    assert!(e.contains("only one genre"), "{e}");
    let nothing = vec![h("hens", "Lay", 0, &[], &[], None)];
    assert!(choose(&nothing, &genres(&["hens"])).unwrap_err().contains("done to nothing"));
}
