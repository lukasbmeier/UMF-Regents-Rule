//! PLAYER NAMES ARE UNIQUE (DECISIONS #202): a name another player holds becomes the next free
//! "<name> N", within the length limit, whatever its case.

use umf_module::names::free;

#[test]
fn a_free_name_is_kept_and_a_taken_one_numbered() {
    let held = ["luke", "luke 2"];
    let taken = |n: &str| held.contains(&n.to_lowercase().as_str());
    assert_eq!(free("daniel", 24, taken), "daniel");
    assert_eq!(free("Luke", 24, taken), "Luke 3");
}

#[test]
fn a_long_name_is_cut_to_fit_its_number() {
    let taken = |n: &str| n == "abcdefgh";
    let out = free("abcdefgh", 8, taken);
    assert_eq!(out, "abcdef 2");
    assert!(out.chars().count() <= 8);
}
