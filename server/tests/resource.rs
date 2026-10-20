//! RESOURCES (DECISIONS #270): what a pool holds after a while, in a fight and out of one. The same
//! cases are checked against the client's twin (`ResourceDef.level`) by the `resources` suite.

use umf_module::resource::level;

/// (stored, max, since, in, out, combat) -> level: the cases both twins answer.
const CASES: [(f32, f32, f32, f32, f32, f32, f32); 6] = [
    (40.0, 100.0, 0.0, 4.0, 10.0, 5.0, 40.0),     // just spent: as it was
    (40.0, 100.0, 3.0, 4.0, 10.0, 5.0, 52.0),     // in the fight: 3 s at 4
    (40.0, 100.0, 5.0, 4.0, 10.0, 5.0, 60.0),     // the fight's 5 s at 4
    (40.0, 100.0, 7.0, 4.0, 10.0, 5.0, 80.0),     // then 2 s at 10
    (40.0, 100.0, 60.0, 4.0, 10.0, 5.0, 100.0),   // never past full
    (0.0, 100.0, 10.0, 0.0, 0.0, 5.0, 0.0),       // a pool that never fills
];

#[test]
fn a_pool_fills_slower_in_a_fight_and_never_past_full() {
    for (stored, max, since, rin, rout, combat, want) in CASES {
        let got = level(stored, max, since, rin, rout, combat);
        assert!((got - want).abs() < 1e-4, "{stored} after {since} s: {got}, want {want}");
    }
    assert_eq!(level(50.0, 100.0, -3.0, 4.0, 10.0, 5.0), 50.0, "a clock behind: as it was, never less");
}
