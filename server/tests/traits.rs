//! TRAITS (DECISIONS #275): an item's traits, read and multiplied up, on a table of the suite's own.

use umf_module::traits::{holds, ids_of, mult_in, roll_in, value_in, with_ids, Against, Atom, TraitSeed};

const A: Atom = Atom { what: "", on: "", mult: 1.0, value: 0.0, condition: "", threshold_pct: 30.0, against: "", cost: false };

static TABLE: &[TraitSeed] = &[
    TraitSeed { id: 1, key: "balanced", name: "Balanced", applies_to: &["weapon"], rollable: true, atoms: &[
        Atom { what: "recovery", on: "basic", mult: 0.85, ..A },
        Atom { what: "damage", on: "skill", mult: 0.9, cost: true, ..A },
    ] },
    TraitSeed { id: 2, key: "brutal", name: "Brutal", applies_to: &["weapon"], rollable: true, atoms: &[
        Atom { what: "damage", mult: 1.25, condition: "target_below", threshold_pct: 30.0, ..A },
        Atom { what: "damage", mult: 0.9, condition: "target_above", threshold_pct: 30.0, cost: true, ..A },
    ] },
    TraitSeed { id: 3, key: "hunters", name: "Hunter's", applies_to: &["bow"], rollable: true, atoms: &[
        Atom { what: "damage", mult: 1.15, condition: "against", against: "beast", ..A },
        Atom { what: "damage", mult: 0.85, condition: "against", against: "humanoid", cost: true, ..A },
    ] },
    TraitSeed { id: 4, key: "thirsting", name: "Thirsting", applies_to: &["weapon"], rollable: true, atoms: &[
        Atom { what: "heal_on_hit", on: "basic", value: 5.0, ..A },
        Atom { what: "healing_received", mult: 0.85, cost: true, ..A },
    ] },
    TraitSeed { id: 5, key: "springy", name: "Springy", applies_to: &["tool"], rollable: false, atoms: &[
        Atom { what: "work_time", mult: 0.95, ..A },
        Atom { what: "depletion", mult: 1.1, cost: true, ..A },
    ] },
];

fn near(a: f32, b: f32) -> bool {
    (a - b).abs() < 1e-5
}

#[test]
fn an_atom_works_at_its_action_only() {
    let none = Against::default();
    assert!(near(mult_in(TABLE, &[1], "recovery", &["basic"], &none, 1.0), 0.85), "a basic recovers 15% faster");
    assert!(near(mult_in(TABLE, &[1], "recovery", &["heavy"], &none, 1.0), 1.0), "a heavy as it was");
    assert!(near(mult_in(TABLE, &[1], "damage", &["skill"], &none, 1.0), 0.9), "an ability pays for it");
    assert!(near(mult_in(TABLE, &[1], "recovery", &["basic", "combo_last"], &none, 1.0), 0.85), "an action may be several things");
    assert!(near(mult_in(TABLE, &[], "recovery", &["basic"], &none, 1.0), 1.0), "no traits: nothing");
    assert!(near(mult_in(TABLE, &[99], "recovery", &["basic"], &none, 1.0), 1.0), "an unknown trait: nothing");
}

#[test]
fn a_condition_holds_only_when_it_is_known() {
    let low = Against { target_pct: Some(20.0), family: "" };
    let high = Against { target_pct: Some(80.0), family: "" };
    assert!(near(mult_in(TABLE, &[2], "damage", &["heavy"], &low, 1.0), 1.25), "below 30%: a quarter more");
    assert!(near(mult_in(TABLE, &[2], "damage", &["heavy"], &high, 1.0), 0.9), "above it: a tenth less");
    assert!(near(mult_in(TABLE, &[2], "damage", &["heavy"], &Against::default(), 1.0), 1.0), "not knowing the target: neither");
    let beast = Against { target_pct: None, family: "beast" };
    let man = Against { target_pct: None, family: "humanoid" };
    assert!(near(mult_in(TABLE, &[3], "damage", &[], &beast, 1.0), 1.15) && near(mult_in(TABLE, &[3], "damage", &[], &man, 1.0), 0.85));
    assert!(near(mult_in(TABLE, &[3], "damage", &[], &Against { target_pct: None, family: "undead" }, 1.0), 1.0), "neither family");
    let at = |p: f32| holds(&TABLE[1].atoms[0], &Against { target_pct: Some(p), family: "" });
    assert!(at(29.9) && !at(30.0), "below is below: 30% itself is above");
}

#[test]
fn traits_multiply_and_add_and_the_dial_scales_them() {
    let none = Against::default();
    assert!(near(mult_in(TABLE, &[1, 2], "damage", &["skill"], &Against { target_pct: Some(10.0), family: "" }, 1.0), 0.9 * 1.25), "two traits: multiplied");
    assert!(near(value_in(TABLE, &[4], "heal_on_hit", &["basic"], &none, 1.0), 5.0), "an amount, added");
    assert!(near(mult_in(TABLE, &[1], "recovery", &["basic"], &none, 0.5), 0.925), "at half strength: half the change");
    assert!(near(value_in(TABLE, &[4], "heal_on_hit", &["basic"], &none, 0.5), 2.5));
    assert!(near(mult_in(TABLE, &[1], "recovery", &["basic"], &none, 0.0), 1.0) && near(value_in(TABLE, &[4], "heal_on_hit", &["basic"], &none, 0.0), 0.0),
        "at 0: traits are off");
}

#[test]
fn an_item_carries_its_traits_in_its_data() {
    assert_eq!(ids_of(""), Vec::<u32>::new());
    assert_eq!(ids_of("{\"q\":734}"), Vec::<u32>::new());
    assert_eq!(ids_of("{\"q\":734,\"h\":40017,\"t\":[5]}"), vec![5]);
    assert_eq!(ids_of("{\"t\":[1, 2]}"), vec![1, 2]);
    assert_eq!(with_ids("", &[5]), "{\"t\":[5]}");
    assert_eq!(with_ids("{}", &[5]), "{\"t\":[5]}");
    assert_eq!(with_ids("{\"q\":734}", &[1, 2]), "{\"q\":734,\"t\":[1,2]}");
    assert_eq!(with_ids("{\"q\":734,\"t\":[1]}", &[2]), "{\"q\":734,\"t\":[2]}", "in place of what it had");
    assert_eq!(with_ids("{\"q\":734,\"t\":[1]}", &[]), "{\"q\":734}", "none: the key goes, and its comma");
    assert_eq!(with_ids("{\"t\":[1],\"q\":734}", &[]), "{\"q\":734}");
    assert_eq!(with_ids("{\"q\":734}", &[]), "{\"q\":734}");
    let d = with_ids("{\"q\":900,\"h\":40017}", &[5, 1]);
    assert_eq!(ids_of(&d), vec![5, 1], "and back ({d})");
}

#[test]
fn a_drop_rolls_distinct_traits_that_fit() {
    for seed in 0..200u64 {
        let got = roll_in(TABLE, &["weapon", "melee"], 2, seed);
        assert_eq!(got.len(), 2);
        assert!(got[0] != got[1], "never the same twice ({got:?})");
        assert!(got.iter().all(|id| [1, 2, 4].contains(id)), "only weapon traits ({got:?})");
    }
    assert!(roll_in(TABLE, &["tool"], 1, 7).is_empty(), "a handle's own trait is not rolled");
    assert_eq!(roll_in(TABLE, &["bow"], 3, 1), vec![3], "fewer when fewer fit");
    let mut seen = std::collections::HashSet::new();
    for seed in 0..200u64 {
        seen.insert(roll_in(TABLE, &["weapon"], 1, seed)[0]);
    }
    assert_eq!(seen.len(), 3, "every fitting trait comes up ({seen:?})");
}
