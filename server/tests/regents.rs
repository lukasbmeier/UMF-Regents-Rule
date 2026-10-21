#![cfg(genre_regents)]
//! REGENT'S RULE'S PURE RULES: woodcutting's branch dodge, held to the golden vectors that a third
//! (Python) version made (`game/regents/tests/make_chop_golden.py`); the GDScript twin is held to the
//! same file by the `regents` suite.

use umf_module::genre::regents::chop::{self, ChopParams, ChopResult};
use umf_module::traits;

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
fn the_chain_is_compiled_in() {
    let nodes: Vec<&str> = rules::NODES.iter().map(|n| n.name).collect();
    assert_eq!(nodes, vec!["Tree", "Oak", "Yew", "Copper rock", "Iron rock"], "the five nodes, from game/regents/content/node/");
    for n in rules::NODES {
        assert!(rules::item(n.yield_item).is_some() && rules::skill(n.skill).is_some(), "{} gives an item and trains a skill", n.name);
        assert!(matches!(n.minigame, rules::Minigame::Chop(_) | rules::Minigame::Crack(_)), "{}'s round is a gathering round", n.name);
    }
    let skills: Vec<&str> = rules::SKILLS.iter().map(|s| s.key).collect();
    assert_eq!(skills, vec!["woodcutting", "mining", "smelting", "smithing", "crafting", "swordsmanship", "axemanship", "archery", "sorcery"]);
    let stations: Vec<&str> = rules::STATIONS.iter().map(|s| s.key).collect();
    assert_eq!(stations, vec!["furnace", "anvil", "workbench", rules::ORDER_BOARD]);
    for bar in ["Copper bar", "Iron bar"] {
        let r = rules::RECIPES.iter().find(|r| r.name == bar).unwrap();
        assert_eq!(r.inputs[0].1, 2, "{bar}: two ores to a bar (owner, 2026-10-19: never one to one)");
    }
    for r in rules::RECIPES {
        assert!(rules::STATIONS.iter().any(|s| s.key == r.station), "{} is made at a station", r.name);
        assert!(r.inputs.iter().all(|(i, q)| rules::item(*i).is_some() && *q >= 1), "{}'s inputs are items", r.name);
    }
    let head = rules::RECIPES.iter().find(|r| r.name == "Iron axe head").expect("the axe head");
    assert!(matches!(head.minigame, rules::Minigame::Shape(_)) && head.quality == rules::QUALITY_FROM_ROUND, "the head is shaped, as good as its round");
    let axe = rules::RECIPES.iter().find(|r| r.name == "Iron axe").expect("the iron axe");
    assert_eq!(axe.quality, rules::QUALITY_FROM_INPUTS, "an assembled axe is as good as its head");
    assert_eq!(axe.inputs.len(), 3, "a head, a handle and rivets");
    let iron = rules::item(axe.output).unwrap();
    assert_eq!((iron.tool_tag, iron.tool_tier, iron.tool_speed_pct), ("axe", 2, 85), "the iron axe: tier 2, 85 % of the time");
    let yew = rules::node_named("yew").unwrap();
    assert_eq!((yew.min_tool_tier, yew.min_rank), (2, 4), "a yew needs the iron axe and woodcutting rank 4");
    for id in rules::STARTER_KIT {
        assert_eq!(rules::item(*id).map(|i| i.tool_tier), Some(1), "the starter kit is tier 1 tools");
    }
    assert!(rules::node_named("Birch").is_none() && rules::station_keyed("kiln").is_none(), "what is not content is nothing");
}

#[test]
fn handles_are_parts_and_their_wood_is_the_tools_trait() {
    let axe = rules::RECIPES.iter().find(|r| r.name == "Iron axe").unwrap();
    assert!(axe.part_slot >= 0, "the iron axe has a part slot");
    let plain = rules::item(axe.inputs[axe.part_slot as usize].0).unwrap();
    let handles: Vec<&str> = rules::ITEMS.iter().filter(|i| i.part_tag == plain.part_tag).map(|i| i.name).collect();
    assert_eq!(handles, vec!["Handle", "Oak handle", "Yew handle"], "three handles fill it");
    let oak = rules::ITEMS.iter().find(|i| i.name == "Oak handle").unwrap();
    let yew = rules::ITEMS.iter().find(|i| i.name == "Yew handle").unwrap();
    let trait_of = |h: &rules::ItemSeed| traits::find(h.handle_trait).map(|t| t.key);
    assert_eq!((trait_of(oak), trait_of(yew), trait_of(plain)), (Some("steady"), Some("springy"), None),
        "oak gives Steady, yew Springy, a plain handle nothing (template DECISIONS #275)");
    for (h, logs) in [("Oak handle", "Oak logs"), ("Yew handle", "Yew logs")] {
        let r = rules::RECIPES.iter().find(|r| r.name == h).expect(h);
        assert_eq!(rules::item(r.inputs[0].0).map(|i| i.name), Some(logs), "{h} is carved from {logs}");
    }
    let iron = rules::item(axe.output).unwrap();
    assert_eq!(rules::tool_speed_with(iron, &[], 1.0), 85, "no traits: as authored");
    assert_eq!(rules::tool_speed_with(iron, &[yew.handle_trait], 1.0), 81, "Springy: 5 % quicker (85 -> 81)");
    assert_eq!(rules::tool_speed_with(iron, &[oak.handle_trait], 1.0), 89, "Steady: 5 % slower (85 -> 89)");
    assert_eq!(rules::tool_speed_with(iron, &[yew.handle_trait], 0.0), 85, "traits off: as authored");
    assert_eq!(rules::tool_speed_with(iron, &[999_999], 1.0), 85, "a trait that is not one: nothing");
    let data = rules::tool_data(612, yew.id);
    assert_eq!((rules::quality_of(&data), rules::handle_of(&data)), (Some(612), Some(yew.id)), "a tool keeps its quality and its handle");
    assert_eq!(rules::traits_of_row(&data), vec![yew.handle_trait], "and its handle's trait ({data})");
    assert_eq!(rules::traits_of_row(&rules::tool_data(612, plain.id)), Vec::<u32>::new(), "a plain handle's tool: none");
    assert_eq!(rules::traits_of_row(&format!("{{\"q\":700,\"h\":{}}}", oak.id)), vec![oak.handle_trait],
        "a tool made before traits (only its handle noted): its handle's");
    assert_eq!(rules::handle_of(&rules::quality_data(5)), None, "a plain made item has no handle");
    assert_eq!(rules::parse_part(&rules::payload_with_part(9, 40006, 100, yew.id)), yew.id);
    assert_eq!(rules::parse_payload(&rules::payload_with_part(9, 40006, 100, yew.id)), Some((9, 40006, 100)), "the first three fields are as before");
    assert_eq!(rules::parse_part(&rules::payload(9, 40006, 100)), 0, "no part: 0");
}

#[test]
fn crafting_pays_for_the_work_in_its_inputs_and_wears_stale_with_repetition() {
    let copper_ore = rules::node_named("Copper rock").unwrap();
    assert_eq!(rules::work_xp(copper_ore.yield_item), copper_ore.xp, "an ore: what mining it paid");
    let bar = rules::RECIPES.iter().find(|r| r.name == "Copper bar").unwrap();
    assert_eq!(rules::work_xp(bar.output), (bar.xp + 2 * copper_ore.xp) / bar.output_qty, "a bar: its smelt and its two ores");
    assert_eq!(rules::craft_xp(bar, 0), bar.xp, "no share: the recipe's own XP");
    assert_eq!(rules::craft_xp(bar, 100), bar.xp + 2 * copper_ore.xp, "a full share: and all the ores' work");
    assert_eq!(rules::craft_xp(bar, 50), bar.xp + copper_ore.xp, "half");
    let axe = rules::RECIPES.iter().find(|r| r.name == "Iron axe").unwrap();
    assert!(rules::craft_xp(axe, 60) > 4 * axe.xp, "assembling a tool pays for the chain behind it ({} vs its own {})", rules::craft_xp(axe, 60), axe.xp);
    assert_eq!(rules::work_xp(999_999), 0, "nothing makes it: no work");
    assert_eq!(rules::xp_at_freshness(100, 1000, 50), 100, "fresh: full XP");
    assert_eq!(rules::xp_at_freshness(100, 0, 50), 50, "worn out: the floor");
    assert_eq!(rules::xp_at_freshness(100, 500, 50), 75, "halfway");
    assert_eq!(rules::freshness_now(200, 60, 30), 230, "a minute away: back 30");
    assert_eq!(rules::freshness_now(990, 600, 30), 1000, "never past fresh");
}

#[test]
fn ranks_come_from_the_curve_and_speed_from_tool_quality_and_rank() {
    let wc = rules::SKILLS.iter().find(|s| s.key == "woodcutting").unwrap();
    assert_eq!((rules::rank_of(wc, 0), rules::rank_of(wc, 59), rules::rank_of(wc, 60), rules::rank_of(wc, 280)), (1, 1, 2, 4));
    assert_eq!(rules::rank_of(wc, 1_000_000), wc.xp_to_rank.len() as u32 + 1, "the cap is the curve's length");
    assert_eq!(rules::speed_pct(100, 0, 1), 100, "a bronze tool, no quality, rank 1: as authored");
    assert_eq!(rules::speed_pct(85, 0, 1), 85, "the iron axe");
    assert_eq!(rules::speed_pct(85, 1000, 1), 76, "a perfect iron axe: a tenth more off (85 x 0.9)");
    assert_eq!(rules::speed_pct(100, 0, 4), 91, "rank 4: 9 % off");
    assert_eq!(rules::speed_pct(100, 0, 99), 73, "the rank's share stops at 27 %");
    assert_eq!(rules::afk_interval_ms(4000, 85), 3400);
    assert_eq!(rules::quality_of(&rules::quality_data(734)), Some(734), "a quality written is read back");
    assert_eq!(rules::quality_of(""), None);
    assert_eq!(rules::quality_of("{\"q\":5000}"), Some(1000), "and is never over 1000");
    assert_eq!(rules::parse_payload(&rules::payload(77, 40001, 91)), Some((77, 40001, 91)));
    assert_eq!(rules::parse_payload("77 40001"), None, "a payload is three numbers");
}

#[test]
fn a_round_yields_what_afk_makes_in_its_time_times_the_bonus_times_the_score() {
    // A 10 s round at a node giving one every 4 s AFK: 2.5 items' worth, x1.25 at a full score.
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 1000), 3125);
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 800), 2500, "80 %: exactly what AFK makes");
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 400), 1250, "a poor round falls short of AFK (design #23)");
    assert_eq!(rules::active_yield_milli(3400, 10_000, 1.25, 1000), 3676, "a faster tool makes more in the same round");
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 5000), 3125, "a score past 1000 counts as 1000");
    assert_eq!(rules::whole_items(3125, 124), 4, "3.125 items: the fourth when the roll is under 125");
    assert_eq!(rules::whole_items(3125, 125), 3);
    assert_eq!(rules::whole_items(3000, 0), 3, "a whole number has no extra item");
}

#[test]
fn rolls_are_spread_and_played_rounds_find_rares_more_often() {
    let mut counts = [0u32; 10];
    for i in 0..20_000u64 {
        counts[(rules::roll_permille(i) / 100) as usize] += 1;
    }
    assert!(counts.iter().all(|&c| (1800..=2200).contains(&c)), "rolls spread evenly over 0..1000: {counts:?}");
    let iron = rules::node_named("Iron rock").unwrap();
    let (mut afk, mut played, mut out) = (0, 0, 0);
    for i in 0..100_000u64 {
        let (r1, d1) = rules::item_outcome(iron, 1.0, rules::roll_permille(i * 2), rules::roll_permille(i * 2 + 1));
        let (r2, _) = rules::item_outcome(iron, 3.0, rules::roll_permille(i * 2), rules::roll_permille(i * 2 + 1));
        afk += u32::from(r1);
        played += u32::from(r2);
        out += u32::from(d1);
    }
    assert!((600..=1000).contains(&afk), "AFK: about 8 rare finds per 1000 ores ({afk} in 100k)");
    assert!(played > afk * 2, "x3 played: about three times as many ({played} against {afk})");
    assert!((18_000..=22_000).contains(&out), "an iron rock is worked out about 1 ore in 5 ({out} in 100k)");
}

#[test]
fn every_minigame_scores_a_real_round_and_refuses_what_is_not_one() {
    let copper = rules::node_named("Copper rock").unwrap();
    assert_eq!(copper.minigame.duration_ms(), 10_000);
    assert_eq!(copper.minigame.score(5, 100, &[]), Some(0), "nothing struck: a round, scoring nothing");
    assert_eq!(copper.minigame.score(5, 100, &[0.0, 500.0]), None, "a rock's strikes are triples");
    let head = rules::RECIPES.iter().find(|r| r.name == "Iron axe head").unwrap();
    assert_eq!(head.minigame.score(5, 100, &[0.0, 3.0, 300.0, 4.0]).map(|s| (0..=1000).contains(&s)), Some(true));
    assert_eq!(head.minigame.score(5, 100, &[0.0, 3.5]), None, "a column is a whole number");
    let bar = rules::RECIPES.iter().find(|r| r.name == "Copper bar").unwrap();
    assert_eq!(bar.minigame.duration_ms(), 11_000, "the smelt: the heat and the pour");
    assert!(matches!(rules::RECIPES.iter().find(|r| r.name == "Handle").unwrap().minigame, rules::Minigame::None), "a handle has no round");
}

use umf_module::genre::regents::{crack, shape, smelt};

fn golden_of(name: &str) -> Vec<serde_json::Value> {
    let path = format!("../shared/golden/regents/{name}.json");
    let doc: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&path).expect(&path)).expect("malformed golden");
    let cases = doc["cases"].as_array().expect("cases").clone();
    assert!(cases.len() >= 6, "{name}: the golden file has its cases ({})", cases.len());
    cases
}

fn seed_of(c: &serde_json::Value) -> u64 {
    ((int(c, "seed_hi") as u64) << 32) | int(c, "seed_lo") as u64
}

fn rows(c: &serde_json::Value) -> Vec<Vec<i64>> {
    c["inputs"].as_array().unwrap().iter().map(|r| r.as_array().unwrap().iter().map(|v| v.as_i64().unwrap()).collect()).collect()
}

#[test]
fn the_crack_twin_plays_every_golden_round_exactly() {
    for c in golden_of("crack") {
        let name = c["name"].as_str().unwrap_or("?");
        let pp = &c["params"];
        let p = crack::CrackParams {
            duration_ms: int(pp, "duration_ms"), swing_ms: int(pp, "swing_ms"), stagger_ms: int(pp, "stagger_ms"),
            split_ms: int(pp, "split_ms"), notches: int(pp, "notches"), bend_pm: int(pp, "bend_pm"),
            radius_pm: int(pp, "radius_pm"), margin_pm: int(pp, "margin_pm"), target_hits: int(pp, "target_hits"),
        };
        let want_pts: Vec<i64> = c["points"].as_array().unwrap().iter().map(|v| v.as_i64().unwrap()).collect();
        let pts: Vec<i64> = crack::seams(seed_of(&c), &p, 3).iter().flat_map(|(x, y)| [*x, *y]).collect();
        assert_eq!(pts, want_pts, "{name}: the first three seams");
        let inputs: Vec<(i64, i64, i64)> = rows(&c).iter().map(|r| (r[0], r[1], r[2])).collect();
        let e = &c["expected"];
        let want = crack::CrackResult {
            hits: int(e, "hits"), jars: int(e, "jars"), best_combo: int(e, "best_combo"), splits: int(e, "splits"), score_pm: int(e, "score_pm"),
        };
        assert_eq!(crack::play(seed_of(&c), &p, &inputs), want, "{name}: the round");
    }
}

#[test]
fn the_smelt_twin_plays_every_golden_round_exactly() {
    for c in golden_of("smelt") {
        let name = c["name"].as_str().unwrap_or("?");
        let pp = &c["params"];
        let p = smelt::SmeltParams {
            heat_ms: int(pp, "heat_ms"), pour_ms: int(pp, "pour_ms"), pour_ready_ms: int(pp, "pour_ready_ms"),
            pump_ms: int(pp, "pump_ms"), pump_heat: int(pp, "pump_heat"),
            cool_per_tick: int(pp, "cool_per_tick"), start_heat: int(pp, "start_heat"), band_center: int(pp, "band_center"),
            band_amp: int(pp, "band_amp"), band_period_ticks: int(pp, "band_period_ticks"), band_half_start: int(pp, "band_half_start"),
            band_half_end: int(pp, "band_half_end"), burn_line: int(pp, "burn_line"), pour_rate: int(pp, "pour_rate"),
            target_lo: int(pp, "target_lo"), target_hi: int(pp, "target_hi"), pour_tolerance: int(pp, "pour_tolerance"),
            heat_weight_pct: int(pp, "heat_weight_pct"),
        };
        let (phase, _) = smelt::seeded(seed_of(&c), &p);
        for (i, b) in c["bands"].as_array().unwrap().iter().enumerate() {
            let want = (b[0].as_i64().unwrap(), b[1].as_i64().unwrap());
            assert_eq!(smelt::band(&p, phase, (i * 7) as i64), want, "{name}: the band at tick {}", i * 7);
        }
        let inputs: Vec<(i64, i64)> = rows(&c).iter().map(|r| (r[0], r[1])).collect();
        let e = &c["expected"];
        let want = smelt::SmeltResult {
            in_band: int(e, "in_band"), burnt: int(e, "burnt"), fill: int(e, "fill"), target: int(e, "target"),
            heat_pm: int(e, "heat_pm"), pour_pm: int(e, "pour_pm"), score_pm: int(e, "score_pm"),
        };
        assert_eq!(smelt::play(seed_of(&c), &p, &inputs), want, "{name}: the round");
    }
}

#[test]
fn the_shape_twin_plays_every_golden_round_exactly() {
    for c in golden_of("shape") {
        let name = c["name"].as_str().unwrap_or("?");
        let pp = &c["params"];
        let p = shape::ShapeParams {
            duration_ms: int(pp, "duration_ms"), swing_ms: int(pp, "swing_ms"), heat_ms: int(pp, "heat_ms"),
            reheat_ms: int(pp, "reheat_ms"), start_height: int(pp, "start_height"), start_jitter: int(pp, "start_jitter"),
            hammer_drop: int(pp, "hammer_drop"), spread_pct: int(pp, "spread_pct"),
            outline: pp["outline"].as_array().unwrap().iter().map(|v| v.as_i64().unwrap()).collect(),
            error_scale: int(pp, "error_scale"),
        };
        let want_start: Vec<i64> = c["start"].as_array().unwrap().iter().map(|v| v.as_i64().unwrap()).collect();
        assert_eq!(shape::start_heights(seed_of(&c), &p), want_start, "{name}: the bar out of the fire");
        let inputs: Vec<(i64, i64)> = rows(&c).iter().map(|r| (r[0], r[1])).collect();
        let e = &c["expected"];
        let want = shape::ShapeResult {
            strikes: int(e, "strikes"), colds: int(e, "colds"), reheats: int(e, "reheats"), error: int(e, "error"), score_pm: int(e, "score_pm"),
        };
        assert_eq!(shape::play(seed_of(&c), &p, &inputs), want, "{name}: the round");
    }
}

#[test]
fn a_submission_of_groups_is_whole_values_in_range_or_nothing() {
    use umf_module::genre::regents::rng::decode_groups;
    assert_eq!(decode_groups(&[0.0, 500.0, 500.0, 260.0, 10.0, 990.0], 3, 10, -1.0, 1e6), Some(vec![vec![0, 500, 500], vec![260, 10, 990]]));
    assert_eq!(decode_groups(&[0.0, 500.0], 3, 10, -1.0, 1e6), None, "a ragged length");
    assert_eq!(decode_groups(&[0.0, 1.0, 2.0, 3.0, 4.0, 5.0], 3, 1, -1.0, 1e6), None, "more groups than allowed");
    assert_eq!(decode_groups(&[0.0, -5.0], 2, 10, -1.0, 1e6), None, "a value under the range");
    assert_eq!(decode_groups(&[0.0, 2.5], 2, 10, -1.0, 1e6), None, "not a whole number");
}

#[test]
fn weapons_fight_with_their_kit_and_hits_scale_with_the_weapon_and_mastery() {
    let sword = rules::kit_keyed("sword").expect("the sword kit");
    let axe = rules::kit_keyed("axe").expect("the axe kit");
    assert_eq!(rules::skill(sword.skill).map(|s| s.key), Some("swordsmanship"), "a sword trains swordsmanship");
    assert_eq!(rules::skill(axe.skill).map(|s| s.key), Some("axemanship"));
    assert_eq!(sword.light.len(), 3, "the sword's light combo: three swings");
    assert_eq!(rules::kit_of_ability(sword.light[1]).map(|(k, s)| (k.key, s)), Some(("sword", rules::KitSlot::Light(1))));
    assert_eq!(rules::kit_of_ability(sword.heavy).map(|(_, s)| s), Some(rules::KitSlot::Heavy));
    assert_eq!(rules::kit_of_ability(sword.skills[0].0).map(|(_, s)| s), Some(rules::KitSlot::Skill(0, 1)), "Q unlocks at rank 1");
    assert!(rules::kit_of_ability(rules::ABILITY_DODGE).is_none(), "the roll is everyone's: no kit");
    let iron_sword = rules::ITEMS.iter().find(|i| i.name == "Iron sword").unwrap();
    assert_eq!((iron_sword.weapon_kit, iron_sword.weapon_damage_pct), ("sword", 100));
    let bronze_axe = rules::item(40001).unwrap();
    assert_eq!((bronze_axe.weapon_kit, bronze_axe.tool_tag), ("axe", "axe"), "the axe is a tool and a weapon");
    assert!(rules::item(40002).unwrap().weapon_kit.is_empty(), "logs are no weapon");
    assert_eq!(rules::hit_damage(10.0, 100, 0, 1), 10.0, "as authored: no quality, rank 1");
    assert_eq!(rules::hit_damage(10.0, 70, 0, 1), 7.0, "a bronze axe at 70 %");
    assert!((rules::hit_damage(10.0, 100, 1000, 1) - 12.0).abs() < 1e-4, "a perfect weapon: a fifth more");
    assert!((rules::hit_damage(10.0, 100, 0, 4) - 10.9).abs() < 1e-4, "rank 4: 9 % more");
    assert!((rules::hit_damage(10.0, 100, 0, 99) - 12.7).abs() < 1e-4, "mastery's share stops at 27 %");
    assert!(rules::combo_allows(0, -1, 0, 900) && rules::combo_allows(0, 2, 5000, 900), "the first swing always");
    assert!(rules::combo_allows(1, 0, 400, 900) && rules::combo_allows(2, 1, 900, 900), "the next step, inside the window");
    assert!(!rules::combo_allows(1, 0, 901, 900), "too late: the combo is over");
    assert!(!rules::combo_allows(2, 0, 100, 900) && !rules::combo_allows(1, -1, 100, 900), "out of order: refused");
    let blade = rules::RECIPES.iter().find(|r| r.name == "Iron sword blade").unwrap();
    assert!(matches!(blade.minigame, rules::Minigame::Shape(_)) && blade.quality == rules::QUALITY_FROM_ROUND, "the blade is shaped at the anvil");
    let assembled = rules::RECIPES.iter().find(|r| r.name == "Iron sword").unwrap();
    assert!(assembled.part_slot >= 0 && assembled.quality == rules::QUALITY_FROM_INPUTS, "the sword takes any handle, as good as its blade");
}

#[test]
fn a_swing_holds_its_fighter_for_its_clip_and_the_combo_chains_from_its_hit() {
    let axe = rules::kit_keyed("axe").unwrap();
    for (a, lock) in axe.locks {
        let def = rules::kit_of_ability(*a).map(|(k, _)| k.key);
        assert_eq!(def, Some("axe"), "ability {a} is the axe's");
        assert!(*lock >= 200 && *lock <= 2500, "a lock from a clip's length, not a placeholder ({a}: {lock} ms)");
    }
    assert!(axe.lock_ms(axe.light[0]) > 0 && axe.lock_ms(99) == 0, "a lock for each of its abilities; none for another's");
    // Chop: lands at 260 ms, holds 578 ms (its clip), the combo may chain 60 ms after the hit.
    let (wind, chain, lock, slack) = (260, 60, 578, 120);
    assert!(!rules::swing_allows(false, 300, wind, chain, lock, slack, false), "a heavy 300 ms in: still swinging");
    assert!(rules::swing_allows(false, lock - slack, wind, chain, lock, slack, false), "the lock's end (less the network's slack): free");
    assert!(!rules::swing_allows(true, 150, wind, chain, lock, slack, false), "the next combo step before the hit lands: not yet");
    assert!(rules::swing_allows(true, wind + chain - slack, wind, chain, lock, slack, false), "from just after the hit: the combo chains");
    assert!(rules::swing_allows(false, 10, wind, chain, lock, slack, true), "a swing a roll cancelled holds nothing");
    assert!(!rules::swing_allows(true, 50, 500, 60, 400, 0, false) && rules::swing_allows(true, 400, 500, 60, 400, 0, false),
        "a chain is never later than the lock");
}

#[test]
fn the_skeleton_camp_is_content() {
    // The first enemies (owner, 2026-10-19): two skeletons, each a kind of its own in the genre's band,
    // fighting with a kit that exists, with health and a loot table.
    let warrior = rules::FOES.iter().find(|f| f.key == "skeleton_warrior").expect("a skeleton warrior");
    let axeman = rules::FOES.iter().find(|f| f.key == "skeleton_axeman").expect("a skeleton axeman");
    for f in [warrior, axeman] {
        assert!(rules::FOE_KINDS.contains(&f.kind), "{} is kind {}", f.name, f.kind);
        assert_eq!(rules::foe_of_kind(f.kind).map(|s| s.id), Some(f.id));
        assert!(rules::kit_keyed(f.kit).is_some() && f.hp > 0, "{f:?}");
        let t = umf_module::loot::find(f.loot_table).unwrap_or_else(|| panic!("{} drops from table {}, which is not baked", f.name, f.loot_table));
        assert!(!t.one_of && t.lines.iter().any(|l| l.pity), "{}: the camp's table, its gem with pity", f.name);
    }
    assert_eq!((warrior.kit, axeman.kit), ("sword", "axe"), "each with the weapon its model carries");
}

#[test]
fn health_comes_back_out_of_the_fight() {
    // 4 % a second of 100: a quarter-second tick gives 1; never past whole; nothing at 0 %.
    assert!((rules::regen_step(50.0, 100.0, 4.0, 0.25) - 51.0).abs() < 1e-5);
    assert_eq!(rules::regen_step(99.5, 100.0, 4.0, 0.25), 100.0, "never past whole");
    assert_eq!(rules::regen_step(50.0, 100.0, 0.0, 0.25), 50.0, "a rule of 0: none");
    let mut h = 0.0;
    let mut ticks = 0;
    while h < 100.0 {
        h = rules::regen_step(h, 100.0, 4.0, 0.25);
        ticks += 1;
    }
    assert_eq!(ticks, 100, "empty to whole in 25 s at 4 %");
}

#[test]
fn the_bow_is_content() {
    let kit = rules::kit_keyed("bow").expect("a bow kit");
    assert_eq!(kit.draw_full_ms, 800, "a drawn kit, full at 800 ms");
    assert!(rules::kit_keyed("sword").is_some_and(|k| k.draw_full_ms == 0), "a sword is not drawn");
    let arrows = rules::ITEMS.iter().find(|i| i.name == "Copper arrows").expect("copper arrows");
    assert_eq!((arrows.ammo_for, arrows.ammo_damage_pct), ("bow", 100));
    assert!(rules::ITEMS.iter().any(|i| i.name == "Yew bow" && i.weapon_kit == "bow"));
}

#[test]
fn a_draw_scales_the_shot() {
    assert!((rules::draw_power(0, 800, 30.0) - 0.3).abs() < 1e-6, "a quick release: 30 %");
    assert!((rules::draw_power(400, 800, 30.0) - 0.65).abs() < 1e-6, "half a draw: half way");
    assert_eq!(rules::draw_power(800, 800, 30.0), 1.0);
    assert_eq!(rules::draw_power(5000, 800, 30.0), 1.0, "held past full: full");
}

#[test]
fn an_auto_aimed_arrow_hits_less_far_off_and_on_the_move() {
    let c = |d: f32, m: bool| rules::hit_chance_pct(d, m, 8.0, 40.0, 95.0, 55.0, 15.0);
    assert_eq!(c(5.0, false), 95.0, "close: 95 %");
    assert!((c(24.0, false) - 75.0).abs() < 1e-4, "half way: 75 %");
    assert_eq!(c(60.0, false), 55.0, "past far: 55 %");
    assert!((c(24.0, true) - 60.0).abs() < 1e-4, "on the move: 15 less");
}

#[test]
fn the_aim_lands_where_it_was_aimed() {
    use umf_module::sim::Vector3;
    // Fly the velocity under gravity (small steps) and see where it crosses the target's distance.
    let fly = |from: Vector3, v: Vector3, x_goal: f32| -> f32 {
        let (mut p, mut vel, dt) = (from, v, 0.0005f32);
        for _ in 0..200000 {
            if ((p.x - from.x).powi(2) + (p.z - from.z).powi(2)).sqrt() >= x_goal {
                return p.y;
            }
            vel = Vector3::new(vel.x, vel.y - rules::ARROW_GRAVITY * dt, vel.z);
            p = Vector3::new(p.x + vel.x * dt, p.y + vel.y * dt, p.z + vel.z * dt);
        }
        f32::NAN
    };
    let from = Vector3::new(0.0, 1.45, 0.0);
    for (to, speed) in [(Vector3::new(0.0, 1.1, -20.0), 50.0), (Vector3::new(15.0, 2.0, 25.0), 30.0), (Vector3::new(-5.0, 0.5, 3.0), 20.0)] {
        let v = rules::aim_velocity(from, to, speed, rules::ARROW_GRAVITY);
        assert!(((v.x * v.x + v.y * v.y + v.z * v.z).sqrt() - speed).abs() < 1e-3, "at its speed");
        let dist = ((to.x - from.x).powi(2) + (to.z - from.z).powi(2)).sqrt();
        let y = fly(from, v, dist);
        assert!((y - to.y).abs() < 0.05, "it arrives at the target's height: {y} vs {} ({dist:.1} m at {speed})", to.y);
    }
    // Out of reach: the farthest arc, 45 degrees.
    let v = rules::aim_velocity(from, Vector3::new(0.0, 1.0, -500.0), 20.0, rules::ARROW_GRAVITY);
    assert!((v.y - (v.x * v.x + v.z * v.z).sqrt()).abs() < 1e-3, "out of reach: 45 degrees");
}

#[test]
fn a_miss_flies_wide_and_point_blank_costs() {
    use umf_module::sim::Vector3;
    let (from, target) = (Vector3::new(0.0, 1.0, 0.0), Vector3::new(0.0, 1.0, -20.0));
    for roll in [0u32, 1, 500, 999] {
        let m = rules::miss_point(from, target, roll, 1.6);
        let side = (m.x - target.x).abs();
        assert!((side - 1.6).abs() < 1e-4, "a miss is 1.6 m to the side ({roll}: {m:?})");
    }
    assert!((rules::miss_point(from, target, 0, 1.6).x - rules::miss_point(from, target, 1, 1.6).x).abs() > 3.0, "either side");
    let full = rules::arrow_damage(14.0, 1.0, 100, 100, 0, 1, false, 60.0);
    assert!((full - 14.0).abs() < 1e-4);
    assert!((rules::arrow_damage(14.0, 1.0, 100, 100, 0, 1, true, 60.0) - 14.0 * 0.6).abs() < 1e-4, "point blank: 60 %");
    assert!((rules::arrow_damage(14.0, 0.3, 100, 100, 0, 1, false, 60.0) - 14.0 * 0.3).abs() < 1e-4, "a quick release: 30 %");
}

#[test]
fn a_kit_with_no_heavy_claims_no_ability_0() {
    // The bow bakes its heavy as 0; ability 0 is the foundation's melee, no kit's (found by the integration suite).
    assert!(rules::kit_keyed("bow").is_some_and(|k| k.heavy == 0));
    assert!(rules::kit_of_ability(0).is_none(), "ability 0 is no kit's");
    assert!(matches!(rules::kit_of_ability(40011), Some((k, rules::KitSlot::Light(0))) if k.key == "bow"));
}

#[test]
fn the_staff_casts_its_spells_from_mana() {
    // THE STAFF (owner, 2026-10-20, LOOT_AND_STYLES §4): a casting kit, mana its pool, every ability a spell.
    let staff = rules::kit_keyed("staff").expect("a staff kit");
    let mana = umf_module::resource::find(staff.resource).expect("the staff's pool is a resource");
    assert_eq!((mana.key, mana.max, mana.regen_out, mana.regen_in), ("mana", 100.0, 10.0, 4.0), "the design's mana");
    let bolt = rules::spell_of(staff.light[0]).expect("its left button is a spell");
    assert!(bolt.kind == rules::SPELL_BOLT && bolt.cost == 0.0 && bolt.cast_ms == 0 && bolt.body > 0, "the bolt: free, instant, a missile");
    let kinds: Vec<i64> = staff.skills.iter().map(|(a, _)| rules::spell_of(*a).expect("each skill a spell").kind).collect();
    assert_eq!(kinds, vec![rules::SPELL_BOLT, rules::SPELL_AREA, rules::SPELL_BLINK, rules::SPELL_CONE], "Fireball, Frost Ring, Blink, Gale");
    let ranks: Vec<u32> = staff.skills.iter().map(|(_, r)| *r).collect();
    assert_eq!(ranks, vec![1, 3, 6, 9]);
    let fireball = rules::spell_of(staff.skills[0].0).unwrap();
    assert!(fireball.cost == 25.0 && fireball.splash_m == 3.0 && fireball.burn_ms == 3000 && rules::may_walk_casting(fireball),
        "Fireball: 25 mana, a 3 m splash, a 3 s burn, a cast you may walk through");
    let ring = rules::spell_of(staff.skills[1].0).unwrap();
    assert!(!rules::may_walk_casting(ring) && ring.status == 108 && ring.status_ms == 3000, "Frost Ring roots its caster and slows for 3 s");
    for k in rules::KITS.iter().filter(|k| k.key != "staff") {
        assert!(k.resource == 0, "{}: no pool (melee and the bow are paced by cooldowns)", k.key);
    }
}

#[test]
fn a_long_cast_roots_whatever_its_spell_says() {
    let mut s = rules::spell_of(rules::kit_keyed("staff").unwrap().skills[0].0).unwrap();
    assert!(rules::may_walk_casting(s));
    let long = rules::SpellSeed { cast_ms: 800, ability: s.ability, kind: s.kind, cost: s.cost, cast_while_moving: true, body: s.body,
        speed: s.speed, splash_m: s.splash_m, splash_pct: s.splash_pct, burn_dps: s.burn_dps, burn_ms: s.burn_ms, radius_m: s.radius_m,
        delay_ms: s.delay_ms, angle_deg: s.angle_deg, push_mps: s.push_mps, status: s.status, status_ms: s.status_ms };
    s = &long;
    assert!(!rules::may_walk_casting(s), "0.8 s or more roots (the owner's rule), whatever the spell says");
}

#[test]
fn a_cone_and_a_blink_land_where_they_should() {
    use umf_module::sim::Vector3;
    let me = Vector3::new(0.0, 0.0, 0.0);
    let north = Vector3::new(0.0, 0.0, -1.0);
    assert!(rules::in_cone(me, north, Vector3::new(0.0, 0.0, -5.0), 8.0, 45.0), "straight ahead");
    assert!(rules::in_cone(me, north, Vector3::new(1.5, 0.0, -5.0), 8.0, 45.0), "17° off: inside a 45° cone");
    assert!(!rules::in_cone(me, north, Vector3::new(3.0, 0.0, -5.0), 8.0, 45.0), "31° off: outside");
    assert!(!rules::in_cone(me, north, Vector3::new(0.0, 0.0, -9.0), 8.0, 45.0), "past its reach");
    assert!(!rules::in_cone(me, north, Vector3::new(0.0, 0.0, 5.0), 8.0, 45.0), "behind");
    let to = rules::blink_to(Vector3::new(1.0, 2.0, 1.0), Vector3::new(3.0, 9.0, 4.0), 8.0).unwrap();
    assert!((to.x - 5.8).abs() < 1e-4 && to.y == 2.0 && (to.z - 7.4).abs() < 1e-4, "8 m flat along the look, at your height: {to:?}");
    assert!(rules::blink_to(me, Vector3::new(0.0, 1.0, 0.0), 8.0).is_none(), "looking straight up: nowhere");
}

#[test]
fn a_foe_hurts_players_and_players_do_not_hurt_each_other() {
    // (actor is a foe, actor is a player, target is a player)
    assert!(rules::may_hurt(true, false, true), "a skeleton hurts a player");
    assert!(!rules::may_hurt(true, false, false), "but not the skeleton beside it, nor a dummy");
    assert!(rules::may_hurt(false, true, false), "a player hurts a foe or a dummy");
    assert!(!rules::may_hurt(false, true, true), "but not a friend (no fights until duels)");
    assert!(rules::may_hurt(false, false, true), "the world (a trap, a fire) may hurt a player");
}

#[test]
fn every_trait_trades_and_fits_what_it_is_on() {
    assert!(traits::TRAITS.len() >= 11, "the v1 pools: {}", traits::TRAITS.len());
    for t in traits::TRAITS {
        let cost = t.atoms.iter().any(|a| a.cost);
        let sometimes = t.atoms.iter().any(|a| !a.condition.is_empty() && a.condition != "always");
        assert!(cost || sometimes, "{} is a pure gain", t.key);
    }
    for h in rules::ITEMS.iter().filter(|i| i.handle_trait != 0) {
        let t = traits::find(h.handle_trait).expect("a handle's trait is a trait");
        assert!(traits::fits(t, &["tool", "axe"]) && !t.rollable, "{}'s {} is a tool's, and only a handle's", h.name, t.key);
    }
    let iron_axe = rules::ITEMS.iter().find(|i| i.name == "Iron axe").unwrap();
    let bow = rules::ITEMS.iter().find(|i| i.weapon_kit == "bow").unwrap();
    let staff = rules::ITEMS.iter().find(|i| i.weapon_kit == "staff").unwrap();
    assert_eq!(rules::item_tags(iron_axe), vec!["tool", "axe", "weapon", "axe", "melee"], "an axe is a tool and a melee weapon");
    assert_eq!(rules::item_tags(bow), vec!["weapon", "bow", "bow"]);
    assert_eq!(rules::item_tags(staff), vec!["weapon", "staff", "staff"]);
    let melee = traits::roll(&rules::item_tags(iron_axe), 2, 11);
    assert!(melee.iter().all(|id| traits::find(*id).is_some_and(|t| t.rollable && traits::fits(t, &rules::item_tags(iron_axe)))),
        "a drop rolls what fits it ({melee:?})");
}

#[test]
fn a_weapons_traits_reach_its_actions() {
    let axe = rules::kit_keyed("axe").unwrap();
    let last = axe.light.len() as u32 - 1;
    assert_eq!(rules::action_tags(axe, rules::KitSlot::Light(0)), vec!["basic"]);
    assert_eq!(rules::action_tags(axe, rules::KitSlot::Light(last)), vec!["basic", "combo_last"], "the combo's last hit");
    assert_eq!(rules::action_tags(axe, rules::KitSlot::Heavy), vec!["heavy"]);
    assert_eq!(rules::action_tags(axe, rules::KitSlot::Skill(0, 1)), vec!["skill"]);
    let none = traits::Against::default();
    let id = |k: &str| traits::by_key(k).unwrap().id;
    let balanced = traits::mult(&[id("balanced")], "recovery", &rules::action_tags(axe, rules::KitSlot::Light(0)), &none, 1.0);
    assert_eq!(rules::lock_with(900, 400, balanced), 400 + 425, "Balanced: a basic's recovery 15 % shorter, the wind-up as it was");
    assert_eq!(rules::lock_with(900, 400, 1.0), 900, "no traits: the kit's lock");
    let heavy_basic = traits::mult(&[id("heavy")], "recovery", &["basic"], &none, 1.0);
    assert_eq!(rules::lock_with(900, 400, heavy_basic), 400 + 575, "Heavy: a basic recovers 15 % slower");
    assert!((traits::value(&[id("heavy")], "stagger", &["basic", "combo_last"], &none, 1.0) - 100.0).abs() < 1e-4
        && traits::value(&[id("heavy")], "stagger", &["basic"], &none, 1.0) == 0.0, "Heavy staggers on the combo's last hit, not its first");
    let low = traits::Against { target_pct: Some(20.0), family: "undead" };
    let high = traits::Against { target_pct: Some(90.0), family: "beast" };
    assert!((traits::mult(&[id("brutal")], "damage", &["basic"], &low, 1.0) - 1.25).abs() < 1e-5, "Brutal: the target below 30 %");
    assert!((traits::mult(&[id("hunters")], "damage", &["basic"], &high, 1.0) - 1.15).abs() < 1e-5, "Hunter's: a beast");
    assert!((traits::mult(&[id("hunters")], "damage", &["basic"], &low, 1.0) - 1.0).abs() < 1e-5, "Hunter's: an undead skeleton is neither");
    assert_eq!(rules::draw_full_with(800, traits::mult(&[id("swift_draw")], "draw_time", &[], &none, 1.0)), 640, "Swift Draw: 800 ms -> 640");
    assert_eq!(rules::draw_full_with(800, 1.0), 800);
}

#[test]
fn a_tools_traits_change_what_a_node_gives() {
    let tree = rules::NODES.iter().find(|n| n.deplete_permille > 0 && n.rare_item != 0).expect("a node with a rare find and depletion");
    let (rare_pm, dep_pm) = (tree.rare_permille, tree.deplete_permille);
    // Just past the depletion chance: out with Lucky (x1.3), not without; just under it: kept with Gentle (x0.5).
    let past = dep_pm;
    assert!(!rules::item_outcome_with(tree, 1.0, 0, 1.0, 999, past).1, "a roll at the chance: not out");
    assert!(rules::item_outcome_with(tree, 1.0, 0, 1.3, 999, past).1, "Lucky: likelier out");
    assert!(!rules::item_outcome_with(tree, 1.0, 0, 0.5, 999, dep_pm / 2 + 1).1, "Gentle: half as likely");
    assert!(!rules::item_outcome_with(tree, 1.0, 0, 1.0, rare_pm, 999).0 && rules::item_outcome_with(tree, 1.0, 50, 1.0, rare_pm, 999).0,
        "Prospector's: 5 % more rare chance");
    assert_eq!(rules::item_outcome(tree, 1.0, 7, 8), rules::item_outcome_with(tree, 1.0, 0, 1.0, 7, 8), "no traits: as before");
}
