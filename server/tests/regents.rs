#![cfg(genre_regents)]
//! REGENT'S RULE'S PURE RULES: woodcutting's branch dodge, held to the golden vectors that a third
//! (Python) version made (`game/regents/tests/make_chop_golden.py`); the GDScript twin is held to the
//! same file by the `regents` suite.

use umf_module::genre::regents::chop::{self, ChopParams, ChopResult};

fn golden() -> serde_json::Value {
    let text = std::fs::read_to_string("../shared/golden/regents/chop.json").expect("shared/golden/regents/chop.json");
    serde_json::from_str(&text).expect("chop.json malformed")
}

fn int(v: &serde_json::Value, k: &str) -> i64 {
    v[k].as_i64().unwrap_or_else(|| panic!("chop.json: no whole number '{k}'"))
}

#[test]
fn the_rust_twin_plays_every_golden_round_exactly() {
    let doc = golden();
    let cases = doc["cases"].as_array().expect("cases");
    assert!(cases.len() >= 10, "the golden file has its cases ({})", cases.len());
    for c in cases {
        let name = c["name"].as_str().unwrap_or("?");
        let seed = ((int(c, "seed_hi") as u64) << 32) | int(c, "seed_lo") as u64;
        let pp = &c["params"];
        let p = ChopParams {
            duration_ms: int(pp, "duration_ms"),
            swing_ms: int(pp, "swing_ms"),
            stagger_ms: int(pp, "stagger_ms"),
            branch_permille: int(pp, "branch_permille"),
            safe_segments: int(pp, "safe_segments"),
            target_chops: int(pp, "target_chops"),
        };
        let want_seg: Vec<i32> = c["segments"].as_array().unwrap().iter().map(|v| v.as_i64().unwrap() as i32).collect();
        assert_eq!(chop::branches(seed, &p, want_seg.len()), want_seg, "{name}: the trunk");
        let inputs: Vec<(i64, i32)> = c["inputs"].as_array().unwrap().iter()
            .map(|pair| (pair[0].as_i64().unwrap(), pair[1].as_i64().unwrap() as i32)).collect();
        let e = &c["expected"];
        let want = ChopResult { clean: int(e, "clean"), hits: int(e, "hits"), best_combo: int(e, "best_combo"), score_pm: int(e, "score_pm") };
        assert_eq!(chop::play(seed, &p, &inputs), want, "{name}: the round");
    }
}

#[test]
fn a_submission_is_whole_pairs_or_nothing() {
    assert_eq!(chop::decode_inputs(&[0.0, 1.0, 300.0, 2.0], 10), Some(vec![(0, 1), (300, 2)]));
    assert_eq!(chop::decode_inputs(&[], 10), Some(vec![]), "nothing pressed is a round");
    assert_eq!(chop::decode_inputs(&[0.0, 1.0, 300.0], 10), None, "an odd length");
    assert_eq!(chop::decode_inputs(&[0.5, 1.0], 10), None, "a time that is not a whole millisecond");
    assert_eq!(chop::decode_inputs(&[f32::NAN, 1.0], 10), None, "not a number");
    assert_eq!(chop::decode_inputs(&[0.0, 99.0], 10), None, "a side out of range");
    assert_eq!(chop::decode_inputs(&[0.0, 1.0, 1.0, 1.0, 2.0, 1.0], 2), None, "more presses than a round may hold");
}

use umf_module::genre::regents as rules;

#[test]
fn the_content_is_compiled_in() {
    let names: Vec<&str> = rules::TREES.iter().map(|t| t.name).collect();
    assert_eq!(names, vec!["Tree", "Oak", "Yew"], "the three trees, from game/regents/content/tree/");
    for t in rules::TREES {
        assert!(rules::item(t.log_item).is_some(), "{}'s logs are an item", t.name);
        assert!(t.rare_permille == 0 || rules::item(t.rare_item).is_some(), "{}'s rare find is an item", t.name);
    }
    let axe = rules::item(rules::STARTER_AXE).expect("the starter axe");
    assert_eq!((axe.tool_tag, axe.tool_tier, axe.max_stack), (rules::TOOL_AXE, 1, 1), "a bronze axe: tier 1, does not stack");
    assert_eq!(rules::tree_named("oak").map(|t| t.name), Some("Oak"), "a level point names its tree in any case");
    assert!(rules::tree_named("Birch").is_none(), "a tree that is not content is no tree");
}

#[test]
fn a_round_yields_what_afk_makes_in_its_time_times_the_bonus_times_the_score() {
    let tree = rules::tree_named("Tree").unwrap();
    // A 10 s round of a tree giving a log every 4 s AFK: 2.5 logs' worth, x1.25 at a full score.
    assert_eq!(rules::active_yield_milli(tree, 1.25, 1000), 3125);
    assert_eq!(rules::active_yield_milli(tree, 1.25, 800), 2500, "80 %: exactly what AFK makes");
    assert_eq!(rules::active_yield_milli(tree, 1.25, 400), 1250, "a poor round falls short of AFK (design #23)");
    assert_eq!(rules::active_yield_milli(tree, 1.25, 0), 0);
    assert_eq!(rules::active_yield_milli(tree, 1.25, 5000), 3125, "a score past 1000 counts as 1000");
    assert_eq!(rules::whole_logs(3125, 124), 4, "3.125 logs: the fourth when the roll is under 125");
    assert_eq!(rules::whole_logs(3125, 125), 3);
    assert_eq!(rules::whole_logs(3000, 0), 3, "a whole number has no extra log");
}

#[test]
fn rolls_are_spread_and_played_rounds_find_rares_more_often() {
    let mut counts = [0u32; 10];
    for i in 0..20_000u64 {
        counts[(rules::roll_permille(i) / 100) as usize] += 1;
    }
    assert!(counts.iter().all(|&c| (1800..=2200).contains(&c)), "rolls spread evenly over 0..1000: {counts:?}");
    let yew = rules::tree_named("Yew").unwrap();
    let (mut afk, mut played, mut fell) = (0, 0, 0);
    for i in 0..100_000u64 {
        let (r1, f1) = rules::log_outcome(yew, 1.0, rules::roll_permille(i * 2), rules::roll_permille(i * 2 + 1));
        let (r2, _) = rules::log_outcome(yew, 3.0, rules::roll_permille(i * 2), rules::roll_permille(i * 2 + 1));
        afk += u32::from(r1);
        played += u32::from(r2);
        fell += u32::from(f1);
    }
    assert!((350..=650).contains(&afk), "AFK: about 5 rare finds per 1000 logs ({afk} in 100k)");
    assert!(played > afk * 2, "x3 played: about three times as many ({played} against {afk})");
    assert!((9_000..=11_000).contains(&fell), "a yew falls about 1 log in 10 ({fell} in 100k)");
}
