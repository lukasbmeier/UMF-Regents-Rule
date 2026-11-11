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
            knot_permille: pp.get("knot_permille").and_then(|v| v.as_i64()).unwrap_or(0),
            knot_beat_ms: pp.get("knot_beat_ms").and_then(|v| v.as_i64()).unwrap_or(0),
        };
        let want_seg: Vec<i32> = c["segments"].as_array().unwrap().iter().map(|v| v.as_i64().unwrap() as i32).collect();
        assert_eq!(chop::branches(seed, &p, want_seg.len()), want_seg, "{name}: the trunk");
        if let Some(k) = c.get("knots").and_then(|v| v.as_array()) {
            let want: Vec<bool> = k.iter().map(|v| v.as_i64() == Some(1)).collect();
            assert_eq!(chop::knots(seed, &p, want.len()), want, "{name}: the knots");
        }
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
    assert_eq!(nodes, vec!["Tree", "Oak", "Yew", "Copper rock", "Iron rock", "Coal rock", "Flax", "Deer carcass", "Wolf carcass"],
        "the nine nodes, from game/regents/content/node/ (the deer's and the wolf's carcasses, skinning 2026-11-09..10)");
    for n in rules::NODES {
        assert!(rules::item(n.yield_item).is_some() && rules::skill(n.skill).is_some(), "{} gives an item and trains a skill", n.name);
        // Flax's round is pull the root (herbalism step 2, 2026-11-08), the carcasses' the cut line (2026-11-10), each its own kind.
        assert!(matches!(n.minigame, rules::Minigame::Chop(_) | rules::Minigame::Crack(_)) || (n.name == "Flax" && matches!(n.minigame, rules::Minigame::Pull(_)))
            || ((n.name == "Deer carcass" || n.name == "Wolf carcass") && matches!(n.minigame, rules::Minigame::Skin(_))),
            "{}'s round is a gathering round", n.name);
    }
    // SKINNING (Luke, 2026-11-09): the deer leaves its carcass, a knife's node; the copper knife is in the starter kit;
    // the killer has it first for the hot rule's seconds, then anyone. SEVERAL HIDES (Luke, 2026-11-10): each the last
    // with 35 %, at most 4, and a played round skins the whole of it (the cut line, kind 107).
    let carcass = rules::node_named("deer carcass").expect("the deer's carcass");
    let deer = rules::FOES.iter().find(|f| f.key == "deer").unwrap();
    assert_eq!(deer.carcass, carcass.id, "a slain deer leaves its carcass");
    let wolf_carcass = rules::node_named("wolf carcass").expect("the wolf's carcass");
    let wolf = rules::FOES.iter().find(|f| f.key == "wolf").expect("the wolf");
    assert_eq!(wolf.carcass, wolf_carcass.id, "a slain wolf leaves its carcass");
    assert!(rules::FOES.iter().filter(|f| f.key != "deer" && f.key != "wolf").all(|f| f.carcass == 0), "a skeleton leaves its body only");
    assert_eq!((carcass.tool_tag, carcass.min_tool_tier, carcass.deplete_permille, carcass.rare_item), ("knife", 1, 350, 0));
    assert!(carcass.max_items == 4 && carcass.whole_round && carcass.minigame.challenge_kind() == rules::CHALLENGE_SKIN,
        "the carcass: four hides at most, skinned whole in one round of the cut line");
    assert!(wolf_carcass.max_items == 4 && wolf_carcass.whole_round && wolf_carcass.min_rank == 2 && wolf_carcass.rare_permille == 8
        && wolf_carcass.minigame.challenge_kind() == rules::CHALLENGE_SKIN,
        "the wolf's carcass: Skinning 2, four pelts at most, a rare wolf fang (0.8 %), skinned whole in one round of the cut line");
    assert_eq!((rules::item(wolf_carcass.yield_item).map(|i| i.name), rules::item(wolf_carcass.rare_item).map(|i| i.name)),
        (Some("Wolf pelt"), Some("Wolf fang")));
    assert!(rules::NODES.iter().filter(|n| n.name != "Deer carcass" && n.name != "Wolf carcass").all(|n| n.max_items == 0 && !n.whole_round),
        "every other node: no cap, a round pays for its time");
    assert_eq!(rules::item(carcass.yield_item).map(|i| i.name), Some("Deer hide"));
    let knife = rules::item(40059).expect("the copper knife");
    assert!(knife.name == "Copper knife" && knife.tool_tag == "knife" && knife.tool_tier == 1 && rules::STARTER_KIT.contains(&40059));
    assert_eq!(rules::carcass_owned_ms(7, 7, 0, 1_000_000, 60.0), 0, "its owner may skin it at once");
    assert_eq!(rules::carcass_owned_ms(7, 8, 0, 1_000_000, 60.0), 59_000, "another waits out the rest of the minute");
    assert_eq!(rules::carcass_owned_ms(7, 8, 0, 60_000_000, 60.0), 0, "and then may");
    assert_eq!(rules::carcass_owned_ms(0, 8, 0, 0, 60.0), 0, "a carcass nobody owns is anyone's");
    let tan = rules::RECIPES.iter().find(|r| r.name == "Soft leather").expect("tanning");
    assert_eq!((tan.station, rules::item(tan.inputs[0].0).map(|i| i.name)), ("tanning_rack", Some("Deer hide")), "a deer hide to soft leather at the rack");
    let supple = rules::RECIPES.iter().find(|r| r.name == "Supple leather").expect("tanning a wolf pelt");
    assert_eq!((supple.station, supple.min_rank, rules::item(supple.inputs[0].0).map(|i| i.name)), ("tanning_rack", 2, Some("Wolf pelt")),
        "a wolf pelt to supple leather at the rack (Crafting 2)");
    let wolf_kit = rules::kit_keyed(wolf.kit).expect("the wolf's kit");
    assert_eq!(wolf_kit.light, &[40027, 40028, 40029], "bite, hamstring bite, lunge");
    assert_eq!(wolf_kit.hit_of(40028).map(|h| (h.status, h.status_ms, h.push_mps)), Some((108, 3000, 0.0)), "hamstring bite slows for 3 s");
    assert_eq!(wolf_kit.hit_of(40029).map(|h| (h.status, h.status_ms, h.push_mps)), Some((0, 0, 10.0)), "the lunge knocks back at 10 m/s");
    assert!(wolf_kit.hit_of(40027).is_none() && wolf_kit.unblockable(40029), "the lunge glints red; the first bite is plain");
    let flax = rules::NODES.iter().find(|n| n.name == "Flax").unwrap();
    assert_eq!(flax.minigame.challenge_kind(), rules::CHALLENGE_PULL, "flax is dealt as pull the root (106)");
    assert!(rules::CLAIMS.challenge_kinds.contains(&rules::CHALLENGE_PULL), "the genre claims kind 106");
    let skills: Vec<&str> = rules::SKILLS.iter().map(|s| s.key).collect();
    assert_eq!(skills, vec!["woodcutting", "mining", "smelting", "smithing", "crafting", "swordsmanship", "axemanship", "archery", "sorcery", "herbalism", "skinning"]);
    let stations: Vec<&str> = rules::STATIONS.iter().map(|s| s.key).collect();
    assert_eq!(stations, vec!["furnace", "anvil", "workbench", rules::ORDER_BOARD, "spinning_wheel", "tanning_rack"]);
    for bar in ["Copper bar", "Iron bar", "Steel bar"] {
        let r = rules::RECIPES.iter().find(|r| r.name == bar).unwrap();
        assert_eq!(r.inputs[0].1, 2, "{bar}: two ores to a bar (owner, 2026-10-19: never one to one)");
    }
    let steel = rules::RECIPES.iter().find(|r| r.name == "Steel bar").unwrap();
    assert_eq!(steel.inputs.len(), 2, "steel: iron ore and coal (MATERIALS.md step 2)");
    assert_eq!(rules::item(steel.inputs[1].0).map(|i| i.name), Some("Coal"), "steel's second input is coal");
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
    // THE REACH FROM A NODE'S EDGE (Luke, 2026-11-06): each model's footprint, baked from the model, picked by entity.
    let iron_rock = rules::node_named("Iron rock").unwrap();
    assert_eq!(iron_rock.radii_cm.len(), 2, "the iron rock has two looks, each with its footprint");
    assert!(iron_rock.radius_m(0) > 2.0 && iron_rock.radius_m(1) > 1.0 && iron_rock.radius_m(2) == iron_rock.radius_m(0),
        "the big rock stands over 2 m from its middle; a node's footprint is its look's (entity % looks): {:?}", iron_rock.radii_cm);
    assert!(rules::NODES.iter().filter(|n| n.tool_tag == "axe").all(|n| n.radii_cm.iter().all(|r| *r <= 50)),
        "a tree is solid at its trunk only: its footprint is the trunk's, never its crown");
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
    // The grips that fit an axe: every shape in every wood (Luke, 2026-11-01: one family of three shapes for every
    // tool and weapon).
    let made = rules::item(axe.output);
    let handles: Vec<&str> = rules::ITEMS.iter().filter(|i| rules::part_fits(i, plain.part_tag, made)).map(|i| i.name).collect();
    assert_eq!(handles, vec!["Grip", "Oak grip", "Yew grip", "Crossguard grip", "Banner grip", "Oak crossguard grip", "Oak banner grip", "Yew crossguard grip", "Yew banner grip"], "nine grips fill it: three shapes in each wood");
    let oak = rules::ITEMS.iter().find(|i| i.name == "Oak grip").unwrap();
    let yew = rules::ITEMS.iter().find(|i| i.name == "Yew grip").unwrap();
    let trait_of = |h: &rules::ItemSeed| traits::find(h.handle_trait).map(|t| t.key);
    assert_eq!((trait_of(oak), trait_of(yew), trait_of(plain)), (Some("steady"), Some("springy"), None),
        "oak gives Steady, yew Springy, a plain handle nothing (template DECISIONS #275)");
    for (h, logs) in [("Oak grip", "Oak logs"), ("Yew grip", "Yew logs")] {
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
    assert_eq!(rules::speed_pct(100, 0, 1), 100, "a copper tool, no quality, rank 1: as authored");
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
    // With no floor, the curve before M11 (owner #23): the multiplier times the score.
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 0.0, 1000), 3125);
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 0.0, 800), 2500, "no floor: 80 % is exactly what AFK makes");
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 0.0, 400), 1250, "a poor round falls short of AFK (design #23)");
    assert_eq!(rules::active_yield_milli(3400, 10_000, 1.25, 0.0, 1000), 3676, "a faster tool makes more in the same round");
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 0.0, 5000), 3125, "a score past 1000 counts as 1000");
    // Luke's M11 (2026-11-05): a floor of 0.75 moves the break-even to half a score; a full one still pays the multiplier.
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 0.75, 500), 2500, "the floor: half a score pays what AFK makes");
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 0.75, 1000), 3125, "a full score, the whole multiplier");
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 0.75, 300), 2250, "a poor round still falls short (design #23)");
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 0.75, 0), 1875, "nothing played: three quarters of AFK");
    assert_eq!(rules::active_yield_milli(4000, 10_000, 1.25, 9.0, 0), 3125, "a floor over the multiplier is the multiplier");
    assert_eq!(rules::active_rare_mult(3.0, 1000), 3.0, "a full round: the whole rare edge");
    assert_eq!(rules::active_rare_mult(3.0, 500), 2.0, "half a round: half of it");
    assert_eq!(rules::active_rare_mult(3.0, 0), 1.0, "a round nobody played: AFK's chance");
    assert_eq!(rules::active_rare_mult(0.5, 1000), 1.0, "never below AFK's");
    // Rank eases the round (Luke's M3): 4 % a rank above the requirement, three ranks at most.
    assert_eq!(rules::rank_ease_pct(1, 1, 4.0, 3.0), 0, "at the requirement: as authored");
    assert_eq!(rules::rank_ease_pct(3, 1, 4.0, 3.0), 8, "two ranks above: 8 %");
    assert_eq!(rules::rank_ease_pct(9, 3, 4.0, 3.0), 12, "six above: capped at three ranks");
    assert_eq!(rules::rank_ease_pct(2, 3, 4.0, 3.0), 0, "below it (never dealt, but): nothing");
    assert_eq!(rules::payload_eased(7, 40001, 90, 0, 0), "7 40001 90", "no ease: the payload as before");
    assert_eq!(rules::payload_eased(7, 40001, 90, 0, 8), "7 40001 90 0 8");
    assert_eq!((rules::parse_payload("7 40001 90 0 8"), rules::parse_part("7 40001 90 0 8"), rules::parse_ease("7 40001 90 0 8")),
        (Some((7, 40001, 90)), 0, 8), "an eased payload still reads as before, its fifth field the ease");
    assert_eq!(rules::parse_ease("7 40001 90 40011"), 0, "a part and no ease");
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
    // Rank eases the round (Luke's M3): a strike just past the first notch's radius jars as authored, and lands once
    // three ranks above the requirement widen it by 12 %.
    if let rules::Minigame::Crack(p) = &copper.minigame {
        let (x, y) = umf_module::genre::regents::crack::seams(5, p, 1)[0];
        let strike = [0.0, (x + p.radius_pm * 106 / 100) as f32, y as f32];
        assert_eq!(copper.minigame.score_eased(5, 100, 0, &strike), copper.minigame.score(5, 100, &strike), "no ease: the round as authored");
        let plain = copper.minigame.score(5, 100, &strike).unwrap();
        let eased = copper.minigame.score_eased(5, 100, 12, &strike).unwrap();
        assert!(eased > plain, "6 % past the notch: a jar as authored ({plain}), a hit eased 12 % ({eased})");
    } else {
        panic!("the copper rock is crack the rock");
    }
    assert_eq!(copper.minigame.score(5, 100, &[0.0, 500.0]), None, "a rock's strikes are triples");
    let head = rules::RECIPES.iter().find(|r| r.name == "Iron axe head").unwrap();
    assert_eq!(head.minigame.score(5, 100, &[0.0, 3.0, 300.0, 4.0]).map(|s| (0..=1000).contains(&s)), Some(true));
    assert_eq!(head.minigame.score(5, 100, &[0.0, 3.5]), None, "a column is a whole number");
    let bar = rules::RECIPES.iter().find(|r| r.name == "Copper bar").unwrap();
    // Smelting's rhythm track (Luke, 2026-11-07): a count-in of 8 (4 until his play of 2026-11-09: "a slower start to
    // read the directions") and 16 beats of 600 ms, then the 4 s pour.
    assert_eq!(bar.minigame.duration_ms(), 18_400, "the smelt: the count-in, the track and the pour");
    assert_eq!(bar.minigame.challenge_kind(), rules::CHALLENGE_BEAT, "dealt as the rhythm track, a kind an old client ignores");
    assert_eq!(bar.minigame.score(5, 100, &[]), Some(0), "nothing pressed: a round, scoring nothing");
    assert_eq!(bar.minigame.score(5, 100, &[2400.0, 1.0, 2460.5, 2.0]), None, "a press's time is a whole number");
    assert_eq!(bar.minigame.score(5, 100, &[2400.0, 1.0, 2460.0]), None, "presses are pairs");
    assert!(bar.minigame.score(5, 100, &[-5.0, 1.0]).is_none(), "nothing before the round");
    for r in rules::RECIPES.iter().filter(|r| r.name.ends_with(" bar")) {
        assert!(matches!(r.minigame, rules::Minigame::Beat(_)), "{}: smelted on the rhythm track", r.name);
    }
    assert!(matches!(rules::RECIPES.iter().find(|r| r.name == "Grip").unwrap().minigame, rules::Minigame::None), "a handle has no round");
}

use umf_module::genre::regents::{beat, carve, crack, pull, shape, skin, smelt};

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
            brittle_permille: opt(pp, "brittle_permille"), ring_ms: opt(pp, "ring_ms"),
        };
        if let Some(b) = c.get("brittle").and_then(|v| v.as_array()) {
            let want: Vec<bool> = b.iter().map(|v| v.as_i64() == Some(1)).collect();
            assert_eq!(crack::brittle(seed_of(&c), &p, want.len()), want, "{name}: the brittle notches");
        }
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
fn the_beat_twin_plays_every_golden_round_exactly() {
    for c in golden_of("beat") {
        let name = c["name"].as_str().unwrap_or("?");
        let pp = &c["params"];
        let p = beat::BeatParams {
            beat_ms: int(pp, "beat_ms"), lead_beats: int(pp, "lead_beats"), beats: int(pp, "beats"), rest_pm: int(pp, "rest_pm"),
            offbeat_pm: int(pp, "offbeat_pm"), hold_pm: int(pp, "hold_pm"), hold_beats: int(pp, "hold_beats"),
            perfect_ms: int(pp, "perfect_ms"), good_ms: int(pp, "good_ms"), good_pm: int(pp, "good_pm"), stray_pm: int(pp, "stray_pm"),
            pour_ms: int(pp, "pour_ms"), pour_ready_ms: int(pp, "pour_ready_ms"), pour_rate: int(pp, "pour_rate"),
            target_lo: int(pp, "target_lo"), target_hi: int(pp, "target_hi"), pour_tolerance: int(pp, "pour_tolerance"),
            track_weight_pct: int(pp, "track_weight_pct"), slag_pm: opt(pp, "slag_pm"),
        };
        let want_notes: Vec<i64> = c["notes"].as_array().unwrap().iter().map(|v| v.as_i64().unwrap()).collect();
        let notes: Vec<i64> = beat::track(seed_of(&c), &p).1.iter().flat_map(|(t, e)| [*t, *e]).collect();
        assert_eq!(notes, want_notes, "{name}: the track");
        if let Some(sl) = c.get("slag").and_then(|v| v.as_array()) {
            let want: Vec<bool> = sl.iter().map(|v| v.as_i64() == Some(1)).collect();
            assert_eq!(beat::slag(seed_of(&c), &p, &beat::track(seed_of(&c), &p).1), want, "{name}: the slag");
        }
        let inputs: Vec<(i64, i64)> = rows(&c).iter().map(|r| (r[0], r[1])).collect();
        let e = &c["expected"];
        let want = beat::BeatResult {
            notes: int(e, "notes"), perfect: int(e, "perfect"), good: int(e, "good"), strays: int(e, "strays"), fill: int(e, "fill"),
            target: int(e, "target"), track_pm: int(e, "track_pm"), pour_pm: int(e, "pour_pm"), score_pm: int(e, "score_pm"),
        };
        assert_eq!(beat::play(seed_of(&c), &p, &inputs), want, "{name}: the round");
    }
}

#[test]
fn the_carve_twin_plays_every_golden_round_exactly() {
    let ints = |v: &serde_json::Value| -> Vec<i64> { v.as_array().unwrap().iter().map(|x| x.as_i64().unwrap()).collect() };
    for c in golden_of("carve") {
        let name = c["name"].as_str().unwrap_or("?");
        let pp = &c["params"];
        let (lo, ro) = (ints(&pp["left_outline"]), ints(&pp["right_outline"]));
        let p = carve::CarveParams {
            duration_ms: int(pp, "duration_ms"), swing_ms: int(pp, "swing_ms"), start_half: int(pp, "start_half"),
            start_jitter: int(pp, "start_jitter"), deep_cut: int(pp, "deep_cut"), fine_cut: int(pp, "fine_cut"),
            left_outline: &lo, right_outline: &ro, outline_vary: int(pp, "outline_vary"), error_scale: int(pp, "error_scale"),
            hide_outline: int(pp, "hide_outline"), lay_cost_pm: int(pp, "lay_cost_pm"), mirror: int(pp, "mirror"),
        };
        let (l, r, tl, tr) = carve::start(seed_of(&c), &p);
        assert_eq!((l, r, tl, tr), (ints(&c["start_left"]), ints(&c["start_right"]), ints(&c["target_left"]), ints(&c["target_right"])),
            "{name}: the blank and the profiles");
        let inputs: Vec<(i64, i64)> = rows(&c).iter().map(|r| (r[0], r[1])).collect();
        let e = &c["expected"];
        let want = carve::CarveResult {
            error: int(e, "error"), cuts: int(e, "cuts"), lays: int(e, "lays"), ceiling_pm: int(e, "ceiling_pm"), score_pm: int(e, "score_pm"),
        };
        assert_eq!(carve::play(seed_of(&c), &p, &inputs), want, "{name}: the round");
    }
}

#[test]
fn the_pull_twin_plays_every_golden_round_exactly() {
    let ints = |v: &serde_json::Value| -> Vec<i64> { v.as_array().unwrap().iter().map(|x| x.as_i64().unwrap()).collect() };
    for c in golden_of("pull") {
        let name = c["name"].as_str().unwrap_or("?");
        let pp = &c["params"];
        let p = pull::PullParams {
            duration_ms: int(pp, "duration_ms"), stroke_ms: int(pp, "stroke_ms"), target_plants: int(pp, "target_plants"),
            dig_pm: int(pp, "dig_pm"), hold_pm: int(pp, "hold_pm"), strain_rise: int(pp, "strain_rise"),
            strain_ease: int(pp, "strain_ease"), pull_rate: int(pp, "pull_rate"), pull_gain: int(pp, "pull_gain"),
            snags: int(pp, "snags"), jump_lo: int(pp, "jump_lo"), jump_hi: int(pp, "jump_hi"), show_depth: int(pp, "show_depth"),
            snap_keep_pm: int(pp, "snap_keep_pm"), loose_pm: pp["loose_pm"].as_i64().unwrap_or(0),
        };
        assert_eq!(pull::start(seed_of(&c), &p), (ints(&c["snag_depth"]), ints(&c["snag_jump"]), ints(&c["snag_side"])),
            "{name}: the side roots");
        let inputs: Vec<(i64, i64)> = rows(&c).iter().map(|r| (r[0], r[1])).collect();
        let e = &c["expected"];
        let want = pull::PullResult {
            whole: int(e, "whole"), snapped: int(e, "snapped"), caught: int(e, "caught"), cut: int(e, "cut"), dug: int(e, "dug"),
            worth: int(e, "worth"), score_pm: int(e, "score_pm"),
        };
        assert_eq!(pull::play(seed_of(&c), &p, &inputs), want, "{name}: the round");
    }
}

/// A WHOLE-NODE ROUND (a carcass, Luke 2026-11-10: "good rounds reward more up to a cap"): AFK's average for the whole
/// carcass (each hide the last with 35 %, at most 4: 2.35) x the round's factor (0.75 at 0 to 1.25 at full), never past
/// the cap less what is taken.
#[test]
fn a_whole_carcass_round_pays_by_its_score_up_to_the_cap() {
    assert_eq!(rules::expected_items_milli(350, 1.0, 4), 2347, "1 + .65 + .4225 + .2746");
    assert_eq!(rules::expected_items_milli(1000, 1.0, 4), 1000, "each the last: one");
    assert_eq!(rules::expected_items_milli(250, 1.0, 0), 4000, "no cap: one in four is the last, four on average");
    assert_eq!(rules::expected_items_milli(0, 1.0, 0), 0, "never runs out, no cap: nothing to count");
    assert_eq!(rules::expected_items_milli(350, 0.0, 4), 4000, "a tool that never works it out: the cap");
    let pay = |score: i64, taken: u32, roll: u32| rules::whole_round_items(350, 1.0, 4, taken, 1.25, 0.75, score, roll);
    assert_eq!((pay(0, 0, 999), pay(0, 0, 0)), (1, 2), "a score of 0: 1.76 hides (1, or 2 three times in four)");
    assert_eq!((pay(500, 0, 999), pay(500, 0, 0)), (2, 3), "half: what AFK gets out of it, 2.35");
    assert_eq!((pay(1000, 0, 999), pay(1000, 0, 0)), (2, 3), "full: 2.93");
    assert!((0..1000).map(|r| pay(1000, 0, r)).sum::<u32>() > (0..1000).map(|r| pay(0, 0, r)).sum::<u32>() + 1000,
        "a better round, more hides");
    assert_eq!(pay(1000, 3, 0), 1, "three taken AFK first: only one left under the cap");
    assert_eq!(pay(1000, 4, 0), 0, "all four taken: none");
    let high = |score: i64, roll: u32| rules::whole_round_items(0, 1.0, 4, 0, 2.0, 0.75, score, roll);
    assert_eq!(high(1000, 0), 4, "a hot rule paying 2x: never past the cap");
}

#[test]
fn the_skin_twin_plays_every_golden_round_exactly() {
    let ints = |v: &serde_json::Value| -> Vec<i64> { v.as_array().unwrap().iter().map(|x| x.as_i64().unwrap()).collect() };
    let cases = golden_of("skin");
    assert!(cases.len() >= 10, "skinning's golden rounds are there");
    for c in cases {
        let name = c["name"].as_str().unwrap_or("?");
        let pp = &c["params"];
        let p = skin::SkinParams {
            duration_ms: int(pp, "duration_ms"), target_lines: int(pp, "target_lines"), points: int(pp, "points"),
            wobble: int(pp, "wobble"), near: int(pp, "near"), reach: int(pp, "reach"), cut_speed: int(pp, "cut_speed"),
            tear_pm: int(pp, "tear_pm"), part_keep_pm: int(pp, "part_keep_pm"),
        };
        assert_eq!(skin::start(seed_of(&c), &p), (ints(&c["line_x"]), ints(&c["line_y"])), "{name}: the first line");
        let inputs: Vec<(i64, i64, i64)> = rows(&c).iter().map(|r| (r[0], r[1], r[2])).collect();
        let e = &c["expected"];
        let want = skin::SkinResult {
            lines: int(e, "lines"), clean: int(e, "clean"), torn: int(e, "torn"), worth: int(e, "worth"), score_pm: int(e, "score_pm"),
        };
        assert_eq!(skin::play(seed_of(&c), &p, &inputs), want, "{name}: the round");
    }
}

/// The cut line as the server deals and scores it (kind 107): a better knife cuts faster and rank widens how far off
/// the line it still cuts; a submission of pairs (not triples) is not a round.
#[test]
fn the_cut_line_is_dealt_as_107_eased_and_sped() {
    let p = skin::SkinParams { duration_ms: 3000, target_lines: 1, points: 2, wobble: 0, near: 20, reach: 200, cut_speed: 30,
        tear_pm: 100, part_keep_pm: 1000 };
    let mg = rules::Minigame::Skin(p);
    assert_eq!(mg.challenge_kind(), rules::CHALLENGE_SKIN);
    assert!(rules::CLAIMS.challenge_kinds.contains(&rules::CHALLENGE_SKIN), "the genre claims kind 107");
    // A straight line at y 500 from x 100 to 900: the knife pressed at the start, then dragged 25 off the line.
    let mut ins: Vec<f32> = vec![0.0, 100.0, 500.0];
    for k in 1..50 {
        ins.extend_from_slice(&[(k * 50) as f32, (100 + k * 30).min(1000) as f32, 525.0]);
    }
    let authored = mg.score(1, 100, &ins).unwrap();
    let eased = mg.score_eased(1, 100, 30, &ins).unwrap();
    assert!(authored < eased, "25 off the line tears at 20 wide, cuts at 26 (eased 30 %): {authored} < {eased}");
    let slow_hand: Vec<f32> = (0..60).flat_map(|k| [(k * 50) as f32, (100 + k * 15) as f32, 500.0]).collect();
    let (plain, quick) = (mg.score(1, 100, &slow_hand).unwrap(), mg.score(1, 50, &slow_hand).unwrap());
    assert!(plain > 0 && plain == quick, "a hand slower than the knife is not helped by a faster knife: {plain} {quick}");
    let fast_hand: Vec<f32> = (0..60).flat_map(|k| [(k * 50) as f32, (100 + k * 50).min(1000) as f32, 500.0]).collect();
    assert!(mg.score(1, 50, &fast_hand).unwrap() > mg.score(1, 100, &fast_hand).unwrap(), "a hand faster than the knife: a quicker knife keeps up");
    assert!(mg.score(1, 100, &[0.0, 100.0]).is_none(), "pairs are not a cut line's round");
}

/// Pull the root eased by rank (M3): the side roots jump less (the server plays the model with 12 % smaller jumps); a
/// faster trowel strokes sooner done.
#[test]
fn a_pull_round_eases_its_side_roots_and_speeds_its_trowel() {
    let p = pull::PullParams { duration_ms: 6000, stroke_ms: 400, target_plants: 1, dig_pm: 1000, hold_pm: 0, strain_rise: 40,
        strain_ease: 60, pull_rate: 10, pull_gain: 40, snags: 1, jump_lo: 500, jump_hi: 500, show_depth: 0, snap_keep_pm: 500, loose_pm: 0 };
    let p = pull::PullParams { target_plants: 3, ..p };
    let mg = rules::Minigame::Pull(p);
    assert_eq!(mg.challenge_kind(), rules::CHALLENGE_PULL);
    assert_eq!(mg.duration_ms(), 6000);
    // Pulled in short holds so the strain stays near 520 when the side root (never cut: no stroke) catches: 500 more
    // snaps it, 440 does not.
    let mut ins: Vec<(i64, i64)> = Vec::new();
    let mut t = 0;
    while t < 5800 {
        ins.push((t, 1));
        ins.push((t + 650, 2));
        t += 1100;
    }
    let flat: Vec<f32> = ins.iter().flat_map(|&(t, c)| [t as f32, c as f32]).collect();
    let (authored, eased) = (pull::play(1, &p, &ins), pull::play(1, &pull::PullParams { jump_lo: 440, jump_hi: 440, ..p }, &ins));
    assert!(authored.snapped >= 1 && eased.snapped == 0 && eased.whole > authored.whole && eased.score_pm > authored.score_pm,
        "a side root that snaps stems as authored never does eased: {authored:?} {eased:?}");
    assert_eq!(mg.score_eased(1, 100, 12, &flat), Some(eased.score_pm), "the server eases the jumps 12 %");
    assert_eq!(mg.score(1, 100, &flat), Some(authored.score_pm), "as authored it snaps");
    // A stroke at 0 (it digs), held from 100: a trowel twice as fast (200 ms) is done sooner, so the pull starts sooner.
    let early: Vec<f32> = vec![0.0, 3.0, 100.0, 1.0, 900.0, 2.0];
    let plain = rules::Minigame::Pull(pull::PullParams { snags: 0, ..p });
    assert!(plain.score(1, 50, &early).unwrap() > plain.score(1, 100, &early).unwrap(), "a faster trowel: the pull starts sooner");
}

/// A param added after a golden's first cases: absent in those, so 0 (off).
fn opt(o: &serde_json::Value, k: &str) -> i64 {
    o.get(k).and_then(|v| v.as_i64()).unwrap_or(0)
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
            tap_drop: opt(pp, "tap_drop"),
            tap_spread_pct: opt(pp, "tap_spread_pct"),
            outline: pp["outline"].as_array().unwrap().iter().map(|v| v.as_i64().unwrap()).collect(),
            error_scale: int(pp, "error_scale"),
            max_reheats: opt(pp, "max_reheats"),
            reheat_cost_pm: opt(pp, "reheat_cost_pm"),
            hide_outline: opt(pp, "hide_outline"),
            lay_cost_pm: opt(pp, "lay_cost_pm"),
            outline_vary: opt(pp, "outline_vary"),
            red_ms: opt(pp, "red_ms"),
            crack_cost_pm: opt(pp, "crack_cost_pm"),
            quench_lo_pm: opt(pp, "quench_lo_pm"),
            quench_hi_pm: opt(pp, "quench_hi_pm"),
            quench_bonus_pm: opt(pp, "quench_bonus_pm"),
            quench_loss_pm: opt(pp, "quench_loss_pm"),
        };
        let want_start: Vec<i64> = c["start"].as_array().unwrap().iter().map(|v| v.as_i64().unwrap()).collect();
        assert_eq!(shape::start_heights(seed_of(&c), &p), want_start, "{name}: the bar out of the fire");
        let want_outline: Vec<i64> = c["outline"].as_array().unwrap().iter().map(|v| v.as_i64().unwrap()).collect();
        assert_eq!(shape::round_outline(seed_of(&c), &p), want_outline, "{name}: the round's outline");
        let inputs: Vec<(i64, i64)> = rows(&c).iter().map(|r| (r[0], r[1])).collect();
        let e = &c["expected"];
        let want = shape::ShapeResult {
            strikes: int(e, "strikes"), colds: int(e, "colds"), reheats: int(e, "reheats"), lays: int(e, "lays"), cracks: int(e, "cracks"),
            error: int(e, "error"), ceiling_pm: int(e, "ceiling_pm"), quench_pm: int(e, "quench_pm"), score_pm: int(e, "score_pm"),
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
    // THE HEAVY MERGED INTO THE FINISHER (COMBAT_OVERHAUL.md §3): the string's last step, no other.
    assert!(sword.is_finisher(rules::KitSlot::Light(2)) && !sword.is_finisher(rules::KitSlot::Light(1))
        && !sword.is_finisher(rules::KitSlot::Skill(0, 1)), "the sword's finisher is its third step, and only that");
    assert!(axe.light.len() == 2 && axe.is_finisher(rules::KitSlot::Light(1)), "the axe: Chop, then its finisher");
    assert!(rules::kit_of_ability(40004).is_none() && rules::kit_of_ability(40007).is_none(), "the old heavy cut and second chop are no kit's");
    assert!(rules::RETIRED_ABILITIES.iter().all(|a| umf_module::content::ABILITIES.iter().all(|c| c.ability_id != *a)),
        "and no content names a retired id (the server refuses them by name)");
    assert_eq!(rules::kit_of_ability(sword.skills[0].0).map(|(_, s)| s), Some(rules::KitSlot::Skill(0, 1)), "Q unlocks at rank 1");
    assert!(rules::kit_of_ability(rules::ABILITY_DODGE).is_none(), "the roll is everyone's: no kit");
    let iron_sword = rules::ITEMS.iter().find(|i| i.name == "Iron sword").unwrap();
    assert_eq!((iron_sword.weapon_kit, iron_sword.weapon_damage_pct), ("sword", 100));
    let copper_axe = rules::item(40001).unwrap();
    assert_eq!((copper_axe.weapon_kit, copper_axe.tool_tag), ("axe", "axe"), "the axe is a tool and a weapon");
    assert!(rules::item(40002).unwrap().weapon_kit.is_empty(), "logs are no weapon");
    assert_eq!(rules::hit_damage(10.0, 100, 0, 1), 10.0, "as authored: no quality, rank 1");
    assert_eq!(rules::hit_damage(10.0, 70, 0, 1), 7.0, "a copper axe at 70 %");
    assert!((rules::hit_damage(10.0, 100, 1000, 1) - 12.0).abs() < 1e-4, "a perfect weapon: a fifth more");
    assert!((rules::hit_damage(10.0, 100, 0, 4) - 10.9).abs() < 1e-4, "rank 4: 9 % more");
    assert!((rules::hit_damage(10.0, 100, 0, 99) - 12.7).abs() < 1e-4, "mastery's share stops at 27 %");
    assert!(rules::combo_allows(0, -1, 0, 900) && rules::combo_allows(0, 2, 5000, 900), "the first swing always");
    assert!(rules::combo_allows(1, 0, 400, 900) && rules::combo_allows(2, 1, 900, 900), "the next step, inside the window");
    assert!(!rules::combo_allows(1, 0, 901, 900), "too late: the combo is over");
    assert!(!rules::combo_allows(2, 0, 100, 900) && !rules::combo_allows(1, -1, 100, 900), "out of order: refused");
    assert_eq!(rules::combo_refusal(1, 0, false, 400, 900), None, "the next step in time: no refusal");
    assert_eq!(rules::combo_refusal(1, -1, true, 400, 900), Some(rules::CUT_SHORT), "after a swing cut short: the combo starts again");
    assert_eq!(rules::combo_refusal(0, -1, true, 400, 900), None, "and its first step is allowed");
    assert_eq!(rules::combo_refusal(1, -1, false, 400, 900), Some(rules::OUT_OF_ORDER), "the second with no first: out of order");
    assert_eq!(rules::combo_refusal(1, 0, false, 901, 900), Some(rules::OUT_OF_ORDER), "too late: out of order, not cut short");
    let blade = rules::RECIPES.iter().find(|r| r.name == "Iron sword blade").unwrap();
    assert!(matches!(blade.minigame, rules::Minigame::Shape(_)) && blade.quality == rules::QUALITY_FROM_ROUND, "the blade is shaped at the anvil");
    let assembled = rules::RECIPES.iter().find(|r| r.name == "Iron sword").unwrap();
    assert!(assembled.part_slot >= 0 && assembled.quality == rules::QUALITY_FROM_INPUTS, "the sword takes any handle, as good as its blade");
    // Only the core sets an assembled item's quality (Luke's M12, 2026-11-05): the blade does, a picked part never.
    for r in rules::RECIPES.iter().filter(|r| r.quality == rules::QUALITY_FROM_INPUTS) {
        let cores: Vec<usize> = (0..r.inputs.len()).filter(|i| rules::sets_quality(r, *i)).collect();
        assert!(!cores.is_empty(), "{}: some input sets its quality", r.name);
        for s in r.part_slots {
            assert!(!rules::sets_quality(r, *s as usize), "{}: its picked part (input {s}) never sets its quality", r.name);
        }
    }
    let blade_at = assembled.inputs.iter().position(|(i, _)| rules::item(*i).map(|it| it.name) == Some("Iron sword blade")).unwrap();
    assert!(rules::sets_quality(assembled, blade_at), "the iron sword's blade sets its quality");
    assert!(!rules::sets_quality(assembled, assembled.part_slot as usize), "its grip never does");
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
    // Chop: lands at 320 ms, holds its clip; the next step may start once its 200 ms follow-through is over.
    assert_eq!(axe.follow_ms, &[200, 200], "a follow-through per step, from the content");
    let (wind, follow, lock, slack) = (320, axe.follow_of(0) as i64, axe.lock_ms(axe.light[0]) as i64, 120);
    assert!(!rules::swing_allows(false, 400, wind, follow, lock, slack, false), "a skill 400 ms into a chop: still swinging");
    assert!(rules::swing_allows(false, lock - slack, wind, follow, lock, slack, false), "the lock's end (less the network's slack): free");
    assert!(!rules::swing_allows(true, wind + 60, wind, follow, lock, slack, false),
        "the next step 60 ms after the hit (the old chain): refused, the arc is not through (Luke's #8)");
    assert!(rules::swing_allows(true, wind + follow - slack, wind, follow, lock, slack, false), "after the follow-through: the string goes on");
    assert!(rules::swing_allows(false, 10, wind, follow, lock, slack, true), "a swing a roll canceled holds nothing");
    assert!(!rules::swing_allows(true, 50, 500, 200, 400, 0, false) && rules::swing_allows(true, 400, 500, 200, 400, 0, false),
        "a follow-through is never later than the lock");
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
    assert_eq!((warrior.kit, axeman.kit), ("skeleton_sword", "skeleton_axe"), "each with a foe kit of its own (COMBAT_OVERHAUL.md §2)");
}

#[test]
fn the_deer_never_fights_and_has_its_own_brain() {
    // HUNTING (HERBALISM_HUNTING_PREP.md §7 step 3, 2026-11-09): the deer is a foe that never fights: no kit, its
    // character's brain (it flees), a kind of the foes' own; every other foe fights with a kit and the foe brain.
    let deer = rules::FOES.iter().find(|f| f.key == "deer").expect("the deer is a foe");
    assert!(!deer.fights && deer.kit.is_empty() && deer.brain == "regents/deer" && rules::FOE_KINDS.contains(&deer.kind));
    assert_eq!(rules::foe_of_kind(deer.kind).map(|f| f.id), Some(deer.id));
    for f in rules::FOES.iter().filter(|f| f.key != "deer") {
        assert!(f.fights && !f.kit.is_empty() && f.brain == "regents/foe", "{}: fights with its kit, the foe brain", f.name);
    }
    assert_ne!(rules::STATUS_STARTLED, rules::STATUS_SLAIN);
}

#[test]
fn a_foe_finisher_is_unblockable_and_a_player_has_nothing_unblockable() {
    // COMBAT_OVERHAUL.md §2 (2026-10-31): a foe's string ends in an unblockable finisher, glinting red; `hit`
    // lets no block or parry stop it. No weapon fights with a foe kit, and no player kit has one. (A creature that never
    // fights, a deer, has no kit: hunting, 2026-11-09.)
    for f in rules::FOES.iter().filter(|f| f.fights) {
        let kit = rules::kit_keyed(f.kit).unwrap();
        let last = *kit.light.last().unwrap();
        assert!(kit.unblockable(last), "{}: its finisher {last} is unblockable", f.name);
        assert!(kit.light[..kit.light.len() - 1].iter().all(|a| !kit.unblockable(*a)), "{}: its lights may be parried", f.name);
        assert!(rules::ITEMS.iter().all(|i| i.weapon_kit != f.kit), "no weapon wields {}", f.kit);
        let (k, slot) = rules::kit_of_ability(last).unwrap();
        assert_eq!((k.key, slot), (f.kit, rules::KitSlot::Light(kit.light.len() as u32 - 1)), "the finisher is its kit's last light");
    }
    for key in ["sword", "axe", "bow", "staff"] {
        let k = rules::kit_keyed(key).unwrap();
        assert!(k.unblockable.is_empty(), "a player's {key} has nothing unblockable");
        assert!(k.light.iter().chain(k.skills.iter().map(|(a, _)| a)).all(|a| !k.unblockable(*a)));
    }
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
fn no_kit_claims_ability_0() {
    // Ability 0 is the foundation's melee, no kit's (found by the integration suite, when the bow baked its heavy as 0).
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
    // A part's tool trait fits a tool and its weapon trait a weapon (owner, 2026-10-23); a rivet's may be one a
    // drop rolls too (Gentle, Lucky, Prospector's), a handle's is its own (Steady, Springy).
    for h in rules::ITEMS.iter().filter(|i| i.handle_trait != 0) {
        let t = traits::find(h.handle_trait).expect("a part's tool trait is a trait");
        assert!(traits::fits(t, &["tool", "axe"]), "{}'s {} is a tool's", h.name, t.key);
        assert!(h.part_tag != "handle" || !t.rollable, "{}'s {} is a handle's own", h.name, t.key);
    }
    for h in rules::ITEMS.iter().filter(|i| i.weapon_trait != 0) {
        let t = traits::find(h.weapon_trait).expect("a part's weapon trait is a trait");
        assert!(traits::fits(t, &["weapon", "sword", "melee"]), "{}'s {} is a weapon's", h.name, t.key);
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
    assert_eq!(rules::action_tags(axe, rules::KitSlot::Skill(0, 1)), vec!["skill"]);
    let none = traits::Against::default();
    let id = |k: &str| traits::by_key(k).unwrap().id;
    let balanced = traits::mult(&[id("balanced")], "recovery", &rules::action_tags(axe, rules::KitSlot::Light(0)), &none, 1.0);
    assert_eq!(rules::lock_with(900, 400, balanced), 400 + 425, "Balanced: a basic's recovery 15 % shorter, the wind-up as it was");
    assert_eq!(rules::lock_with(900, 400, 1.0), 900, "no traits: the kit's lock");
    let heavy_basic = traits::mult(&[id("heavy")], "recovery", &["basic"], &none, 1.0);
    assert_eq!(rules::lock_with(900, 400, heavy_basic), 400 + 575, "Heavy: a basic recovers 15 % slower");
    // HEAVY, ON POISE (Luke, 2026-11-02): the string's last hit wears 35 % more poise; no longer a longer stagger.
    assert!((traits::mult(&[id("heavy")], "poise", &["basic", "combo_last"], &none, 1.0) - 1.35).abs() < 1e-5
        && traits::mult(&[id("heavy")], "poise", &["basic"], &none, 1.0) == 1.0, "Heavy wears more poise with the last hit, not a first step");
    assert_eq!(traits::mult(&[id("heavy")], "stagger_time", &["basic", "combo_last"], &none, 1.0), 1.0, "and no longer lengthens a stagger");
    assert!(traits::value(&[id("heavy")], "stagger", &["basic", "combo_last"], &none, 1.0) == 0.0, "and no longer rolls a stagger of its own");
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

#[test]
fn the_meta_is_each_weapons_share_of_a_periods_damage_and_an_alarm_past_the_line() {
    assert_eq!(rules::meta_period(0, 3600), 0);
    assert_eq!(rules::meta_period(3_599_999_999, 3600), 0, "the last microsecond of the first hour");
    assert_eq!(rules::meta_period(3_600_000_000, 3600), 3600);
    assert_eq!(rules::meta_period(1_792_614_123_000_000, 3600), 1_792_612_800, "an hour in 2026 began on the hour");
    assert_eq!(rules::meta_period(1_792_614_123_000_000, 10), 1_792_614_120, "a 10 s period (a test's)");
    assert_eq!(rules::meta_period(5_000_000, 0), 5, "a period of 0 is taken as 1 s, never a division by 0");
    let s = rules::meta_shares(&[60.0, 30.0, 10.0]);
    assert!((s[0] - 60.0).abs() < 1e-4 && (s[1] - 30.0).abs() < 1e-4 && (s[2] - 10.0).abs() < 1e-4, "{s:?}");
    assert_eq!(rules::meta_shares(&[0.0, 0.0]), vec![0.0, 0.0], "no damage: no shares");
    assert!(rules::meta_alarm(60.0, 100, 45.0, 50.0), "60 % of a busy hour past 45: an alarm");
    assert!(!rules::meta_alarm(44.0, 100, 45.0, 50.0), "under the line: none");
    assert!(!rules::meta_alarm(100.0, 12, 45.0, 50.0), "a quiet hour (two friends, one sword): none");
    assert!(!rules::meta_alarm(100.0, 1000, 0.0, 50.0), "the alarm at 0: never");
    for k in ["sword", "bow", "staff"] {
        let kit = rules::kit_keyed(k).unwrap_or_else(|| panic!("a {k} kit"));
        assert_eq!(rules::kit_of_skill(kit.skill), k, "the {k}'s skill names its weapon type");
    }
    assert_eq!(rules::kit_of_skill(0), "", "no skill, no weapon type");
}

#[test]
fn the_tester_page_sets_a_rank_at_its_start() {
    let wc = rules::SKILLS.iter().find(|s| s.key == "woodcutting").unwrap();
    assert_eq!(rules::xp_for_rank(wc, 1), Some(0), "rank 1 is no XP");
    for r in 2..=rules::max_rank(wc) {
        let xp = rules::xp_for_rank(wc, r).unwrap();
        assert_eq!(rules::rank_of(wc, xp), r, "rank {r}'s start is rank {r}");
        assert_eq!(rules::rank_of(wc, xp - 1), r - 1, "one XP short of rank {r} is rank {}", r - 1);
    }
    assert_eq!(rules::xp_for_rank(wc, 0), None, "no rank 0");
    assert_eq!(rules::xp_for_rank(wc, rules::max_rank(wc) + 1), None, "nothing past the highest rank");
}

#[test]
fn a_crafted_item_holds_traits_by_its_grade() {
    // Fine from 400, Masterwork from 800 (the hot rules' defaults); Common 1, Fine 2, Masterwork 3.
    let room = |q| rules::crafted_trait_room(q, 400, 800, 1, 2, 3);
    assert_eq!((room(0), room(399), room(400), room(799), room(800), room(1000)), (1, 1, 2, 2, 3, 3), "the grade's count");
    let (steady, springy, other) = (40001, 40002, 40099);
    assert_eq!(rules::crafted_traits(&[springy, steady], &[steady, springy], 3), vec![springy, steady], "the player's order");
    assert_eq!(rules::crafted_traits(&[springy, steady], &[steady, springy], 1), vec![springy], "a lower grade keeps the first");
    assert_eq!(rules::crafted_traits(&[other, steady], &[steady], 2), vec![steady], "a trait no part offers is dropped");
    assert_eq!(rules::crafted_traits(&[steady, steady], &[steady], 2), vec![steady], "none twice");
    assert_eq!(rules::crafted_traits(&[], &[steady], 2), Vec::<u32>::new(), "none chosen: none");
}

#[test]
fn no_traits_on_purpose_stays_none() {
    let oak = rules::item(40016).unwrap();
    assert!(oak.handle_trait != 0, "the oak handle gives a trait");
    let none = rules::made_data(500, &[40016, 40012], &[]);
    assert_eq!(none, "{\"q\":500,\"h\":40016,\"p\":[40016,40012],\"t\":[]}");
    assert!(rules::traits_of_row(&none).is_empty(), "an oak-handled tool made with no traits ON PURPOSE has none");
    assert_eq!(rules::traits_of_row("{\"q\":500,\"h\":40016}"), vec![oak.handle_trait], "one made before traits (no \"t\") still has its handle's");
    let some = rules::made_data(900, &[40016, 40012], &[oak.handle_trait]);
    assert_eq!(rules::traits_of_row(&some), vec![oak.handle_trait], "one made with its handle's trait has it");
    assert_eq!(rules::quality_of(&some), Some(900), "and its quality");
    assert_eq!(rules::parts_of_row(&some), vec![40016, 40012], "and its parts, in slot order (what a refit changes)");
    assert_eq!(rules::parts_of_row("{\"q\":500,\"h\":40016}"), vec![40016], "one made before parts were noted: its handle");
}

#[test]
fn a_part_offers_the_trait_that_fits() {
    // Owner, 2026-10-23: a tool's trait for a tool (an axe too), a weapon's for a weapon; only one that fits.
    let (oak, rivets, steel_r, plain) = (rules::item(40016).unwrap(), rules::item(40012).unwrap(), rules::item(40039).unwrap(), rules::item(40013).unwrap());
    let (axe, sword) = (rules::item(40015).unwrap(), rules::item(40019).unwrap());
    let name = |id: u32| crate_trait_key(id);
    assert_eq!((name(rules::offered_for(oak, axe)), name(rules::offered_for(oak, sword))), ("steady", "heavy"), "oak: Steady on an axe, Heavy on a sword");
    assert_eq!((name(rules::offered_for(rivets, axe)), name(rules::offered_for(rivets, sword))), ("gentle", "thirsting"), "copper rivets: Gentle, Thirsting");
    assert_eq!(rules::offered_for(steel_r, sword), 0, "steel rivets give a sword nothing yet (Keen waits for crits)");
    assert_eq!(rules::offered_for(plain, axe), 0, "a plain handle gives nothing");
    assert_eq!((rules::grade_of(399, 400, 800), rules::grade_of(400, 400, 800), rules::grade_of(800, 400, 800)), (0, 1, 2), "grades by the cut points");
}

fn crate_trait_key(id: u32) -> &'static str {
    umf_module::traits::find(id).map_or("", |t| t.key)
}


#[test]
fn the_guard_parries_the_hit_as_seen_blocks_in_front_and_opens_a_riposte() {
    // COMBAT_OVERHAUL.md §4. A press arriving at 1.000 s, its trip 75 ms, swings shown 100 ms late: made as
    // the player saw the swing at 0.825 s on the server's clock.
    let s = 1_000_000i64;
    assert_eq!(rules::press_seen_us(s, 75, 100, 150), s - 175_000);
    assert_eq!(rules::press_seen_us(s, 75, 900, 150), s - 225_000, "a delay claimed past the referee's cap gains nothing");
    // THE PARRY: within parry_ms before the hit as seen, or late_ms after.
    let land = 900_000i64;
    assert!(rules::parries(land - 150_000, land, 200, 50), "pressed 150 ms before the hit landed: parried");
    assert!(rules::parries(land + 40_000, land, 200, 50), "40 ms after (the hand forgiven): parried");
    assert!(!rules::parries(land - 250_000, land, 200, 50), "250 ms early: no parry (held early is not a read)");
    assert!(!rules::parries(land + 80_000, land, 200, 50), "80 ms late: no parry");
    // The same press with no credit for the trip or the view: judged at its arrival, 100 ms too late. The
    // lag is what makes the seen hit parryable.
    assert!(rules::parries(rules::press_seen_us(land + 150_000, 75, 100, 150), land, 200, 50)
        && !rules::parries(land + 150_000, land, 200, 50), "a press 25 ms before the hit as seen, arriving 150 ms after it lands");
    // THE PRESS'S TRIP: measured by the server when it has (#210), else the client's half round trip; capped.
    assert_eq!(rules::guard_credit_ms(Some(150), 40, 120), 75, "measured: half the quickest round trip, whatever the client says");
    assert_eq!(rules::guard_credit_ms(None, 75, 120), 75, "none measured yet: the client's half round trip");
    assert_eq!(rules::guard_credit_ms(None, 900, 120), 120, "a claim past the cap gains nothing");
    // A hit waits for the latest press that could still parry it.
    assert_eq!(rules::parry_deadline_us(land, 50, 150, 120), land + 320_000);
    // THE WHIFF LOCKOUT.
    assert!(rules::whiff_locked(s + 300_000, Some(s), false, 400), "a press 300 ms after one that parried nothing: locked");
    assert!(!rules::whiff_locked(s + 450_000, Some(s), false, 400), "450 ms after: counts");
    assert!(!rules::whiff_locked(s + 100_000, Some(s), true, 400), "after a parry: never locked (a second foe)");
    assert!(!rules::whiff_locked(s, None, false, 400), "the first press counts");
    // FRONT-ONLY: yaw 0 faces -z.
    assert!(rules::in_guard_arc(0.0, 0.0, -2.0, 120.0), "straight in front");
    assert!(rules::in_guard_arc(0.0, 1.0, -1.0, 120.0), "45 degrees off: inside 120");
    assert!(!rules::in_guard_arc(0.0, 2.0, 0.0, 120.0), "to the side (90 degrees): outside 120");
    assert!(!rules::in_guard_arc(0.0, 0.0, 2.0, 120.0), "from behind: outside");
    assert!(rules::in_guard_arc(std::f32::consts::PI, 0.0, 2.0, 120.0), "turned round, behind is in front");
    // THE BLOCKS: the Tank role's full guard, the others' light one (COMBAT_OVERHAUL.md §5).
    let role = |k: &str| rules::role_keyed(k).unwrap();
    assert_eq!(rules::blocked_damage(20.0, role("tank").full_block, 25.0, 60.0), 5.0);
    assert_eq!(rules::blocked_damage(20.0, role("damage").full_block, 25.0, 60.0), 12.0);
    assert_eq!(rules::blocked_damage(20.0, role("support").full_block, 25.0, 60.0), 12.0);
    // THE RIPOSTE: the first step, begun inside the window after a parry.
    assert!(rules::is_riposte(true, s + 500_000, Some(s), 1000), "the first step half a second after: a riposte");
    assert!(!rules::is_riposte(true, s + 1_200_000, Some(s), 1000), "1.2 s after: too late");
    assert!(!rules::is_riposte(false, s + 500_000, Some(s), 1000), "a second step: no riposte");
    assert!(!rules::is_riposte(true, s - 1, Some(s), 1000) && !rules::is_riposte(true, s, None, 1000), "before the parry, or with none");
}

#[test]
fn the_string_steps_up_and_the_kits_kill_at_a_like_pace() {
    // COMBAT_OVERHAUL.md §3: each step a little heavier and slower; the sword and the axe close in pace.
    let dmg = |id: u32| umf_module::content::ABILITIES.iter().find(|a| a.ability_id == id).map(|a| (a.damage, a.wind_up_ms)).unwrap();
    for key in ["sword", "axe"] {
        let k = rules::kit_keyed(key).unwrap();
        for w in k.light.windows(2) {
            let (a, b) = (dmg(w[0]), dmg(w[1]));
            assert!(b.0 > a.0 && b.1 > a.1, "{key}: each step hits harder and winds up longer ({a:?} then {b:?})");
        }
    }
    let rate = |key: &str| {
        let k = rules::kit_keyed(key).unwrap();
        let mut ms = 0u32;
        let mut total = 0.0f32;
        for (i, a) in k.light.iter().enumerate() {
            let (d, wind) = dmg(*a);
            total += d;
            ms += if i + 1 < k.light.len() { (wind + k.follow_of(i as u32)).min(k.lock_ms(*a)) } else { k.lock_ms(*a) };
        }
        total / ms as f32 * 1000.0
    };
    let axe = rate("axe");
    // ROLES (Luke, 2026-11-01): the plain grip's piercing thrust is the biggest hit (26, +30 %), so a plain sword
    // kills fastest; a crossguard or banner hilt trades pace for what its last hit does (a longer stagger, a
    // heal). The axe, with no roles yet, kills inside that range.
    let sword = rules::kit_keyed("sword").unwrap();
    let role_rate = |r: &rules::RoleSeed| {
        let mut ms = 0u32;
        let mut total = 0.0f32;
        for (i, a) in sword.light.iter().enumerate() {
            let a = if i + 1 == sword.light.len() { sword.finisher_for(r) } else { *a };
            let (d, wind) = dmg(a);
            total += d;
            ms += if i + 1 < sword.light.len() { (wind + sword.follow_of(i as u32)).min(sword.lock_ms(a)) } else { sword.lock_ms(a) };
        }
        total / ms as f32 * 1000.0
    };
    let plain = role_rate(rules::plain_role());
    assert!((plain - rate("sword")).abs() < 1e-3, "the plain role's string is the kit's own");
    let others: Vec<f32> = rules::ROLES.iter().filter(|r| !r.plain).map(role_rate).collect();
    assert!(others.iter().all(|o| *o < plain), "every other role kills slower than the plain one ({plain:.1}/s; {others:?})");
    let slowest = others.iter().cloned().fold(plain, f32::min);
    assert!(axe >= slowest && axe <= plain, "the axe ({axe:.1}/s) kills inside the sword's roles ({slowest:.1} to {plain:.1}/s)");
}

#[test]
fn a_handles_shape_is_its_role() {
    // COMBAT_OVERHAUL.md §5, Luke 2026-11-01: three roles, one plain; the Tank's guard full, the others' light.
    assert_eq!(rules::ROLES.len(), 3);
    assert_eq!(rules::plain_role().key, "damage", "the plain role is Damage");
    let role = |k: &str| rules::role_keyed(k).unwrap();
    assert!(role("tank").full_block && !role("damage").full_block && !role("support").full_block);
    // THE SHAPED GRIPS: pinned ids, each crossed with the woods, a grip for any tool or weapon (Luke, 2026-11-01).
    let names = [(40040, "Crossguard grip"), (40041, "Banner grip"), (40042, "Oak crossguard grip"), (40043, "Oak banner grip"),
        (40044, "Yew crossguard grip"), (40045, "Yew banner grip")];
    for (id, name) in names {
        let it = rules::item(id).unwrap_or_else(|| panic!("item {id}"));
        assert_eq!((it.name, it.part_tag, it.fits_kit), (name, "handle", ""), "item {id}");
        assert_eq!(rules::role_of_parts(&[id]).key, if name.to_lowercase().contains("crossguard") { "tank" } else { "support" }, "{name}'s role");
    }
    assert_eq!(rules::item(40042).unwrap().weapon_trait, rules::item(40016).unwrap().weapon_trait, "an oak hilt has oak's trait (Heavy)");
    assert_eq!(rules::item(40044).unwrap().handle_trait, rules::item(40017).unwrap().handle_trait, "a yew hilt has yew's");
    // The same cost and Crafting rank as the handle of its wood (a role is a choice, not a tier).
    for (hilt, handle) in [(40040, 40013), (40041, 40013), (40042, 40016), (40043, 40016), (40044, 40017), (40045, 40017)] {
        let r = |out: u32| rules::RECIPES.iter().find(|r| r.output == out).unwrap();
        let (a, b) = (r(hilt), r(handle));
        assert_eq!((a.inputs, a.min_rank, a.afk_ms, a.xp, a.station), (b.inputs, b.min_rank, b.afk_ms, b.xp, b.station), "{} costs as {}", a.name, b.name);
    }
    // The role from a weapon's parts: the first shape that gives one, else the plain role.
    assert_eq!(rules::role_of_parts(&[]).key, "damage", "no parts: plain");
    assert_eq!(rules::role_of_parts(&[40013, 40012]).key, "damage", "the plain handle and copper rivets: plain");
    assert_eq!(rules::role_of_parts(&[40042, 40038]).key, "tank", "an oak crossguard hilt and iron rivets");
    assert_eq!(rules::role_of_parts(&rules::parts_of_row(r#"{"q":500,"h":40045,"p":[40045,40012],"t":[]}"#)).key, "support");
    assert_eq!(rules::role_of_parts(&rules::parts_of_row(r#"{"q":500,"h":40016}"#)).key, "damage", "made before parts: its handle");
    // Every shape fits a sword's, an axe's and a pickaxe's grip slot, and not a binding's.
    let sword = rules::ITEMS.iter().find(|i| i.name == "Iron sword").unwrap();
    let axe = rules::ITEMS.iter().find(|i| i.name == "Iron axe").unwrap();
    let pick = rules::ITEMS.iter().find(|i| i.name == "Iron pickaxe").unwrap();
    let hilt = rules::item(40040).unwrap();
    assert!([sword, axe, pick].iter().all(|m| rules::part_fits(hilt, "handle", Some(m))), "a crossguard grip fits a sword, an axe, a pickaxe");
    assert!(!rules::part_fits(hilt, "binding", Some(sword)), "not a binding slot");
    // NEGATIVE: a part that names one kit (`fits_kit`, still the content's to use) fits only that kit's.
    let only_swords = rules::ItemSeed { id: 1, name: "Test hilt", max_stack: 1, tool_tag: "", tool_tier: 0, tool_speed_pct: 100, weapon_kit: "",
        weapon_damage_pct: 100, part_tag: "handle", handle_trait: 0, weapon_trait: 0, ammo_for: "", ammo_damage_pct: 100, role: 0, fits_kit: "sword" };
    assert!(rules::part_fits(&only_swords, "handle", Some(sword)) && !rules::part_fits(&only_swords, "handle", Some(axe))
        && !rules::part_fits(&only_swords, "handle", Some(pick)), "a part for swords alone fits no axe or pickaxe");
    let plain = rules::item(40013).unwrap();
    assert!([sword, axe, pick].iter().all(|m| rules::part_fits(plain, "handle", Some(m))), "the plain handle fits all three");
}

#[test]
fn each_role_ends_the_sword_with_its_own_last_hit() {
    // Luke's three (2026-11-01): Piercing thrust 26, 2.4 m, 380 ms; Pommel bash 14, 340 ms, a 1.2 s stagger;
    // Rallying cut 14, 400 ms, a wider arc, a heal of 8 near you.
    let sword = rules::kit_keyed("sword").unwrap();
    let role = |k: &str| rules::role_keyed(k).unwrap();
    assert_eq!([sword.finisher_for(role("damage")), sword.finisher_for(role("tank")), sword.finisher_for(role("support"))], [40003, 40022, 40023]);
    assert_eq!(sword.finisher_for(role("damage")), *sword.light.last().unwrap(), "the plain role's is the string's own last step");
    let a = |id: u32| umf_module::content::ABILITIES.iter().find(|a| a.ability_id == id).unwrap();
    let data = |id: u32, k: &str| serde_json::from_str::<serde_json::Value>(a(id).data).unwrap()[k].as_f64().unwrap();
    assert_eq!((a(40003).damage, a(40003).wind_up_ms), (26.0, 380));
    assert!((data(40003, "reach") - 2.4).abs() < 1e-6, "the thrust reaches 2.4 m");
    assert_eq!((a(40022).damage, a(40022).wind_up_ms), (14.0, 340));
    assert_eq!((a(40023).damage, a(40023).wind_up_ms), (14.0, 400));
    assert!(data(40023, "radius") > data(40003, "radius") && data(40023, "radius") > data(40022, "radius"), "the rallying cut's arc is the widest");
    assert_eq!(sword.role_finisher(40022).map(|r| r.stagger_pct), Some(150), "the pommel bash staggers 1.5 times as long (1.2 s of 800)");
    let rally = sword.role_finisher(40023).unwrap();
    assert_eq!((rally.heal, rally.heal_radius_m), (8.0, 6.0), "the rallying cut heals 8 within 6 m");
    assert_eq!(sword.role_finisher(40003).map(|r| (r.stagger_pct, r.heal)), Some((100, 0.0)), "the thrust staggers as any last hit, heals nothing");
    // Every last hit is the string's last step: its armor, its flinch, its stagger (`is_finisher`).
    for id in [40003, 40022, 40023] {
        assert_eq!(rules::kit_of_ability(id).map(|(k, s)| (k.key, s)), Some(("sword", rules::KitSlot::Light(2))), "{id} is the sword's last step");
        assert!(sword.ends_string(id) && sword.lock_ms(id) > 0, "{id} ends the string, with a lock");
    }
    assert!(!sword.ends_string(sword.light[1]) && !sword.ends_string(sword.skills[0].0), "a middle step or Q ends nothing");
    // NEGATIVE: a kit with no role map ends with its own last step whatever the role.
    let axe = rules::kit_keyed("axe").unwrap();
    assert!(axe.roles.is_empty() && axe.finisher_for(role("tank")) == *axe.light.last().unwrap(), "the axe has no roles yet");
}

#[test]
fn a_dropped_sword_rolls_its_handles_shape() {
    // Luke, 2026-11-01: 50 % plain, 25 / 25, a live rule each. Its handle is the plain wood's (no trait).
    let sword = rules::ITEMS.iter().find(|i| i.name == "Iron sword").unwrap();
    let weights = |d: f64, t: f64, s: f64| move |r: &rules::RoleSeed| match r.key { "damage" => d, "tank" => t, _ => s };
    let w = weights(50.0, 25.0, 25.0);
    let mut seen = [0u32; 3];
    for roll in (0..1_000_000).step_by(1000) {
        match rules::drop_handle(sword, roll, 1_000_000, &w) {
            Some(40013) => seen[0] += 1,
            Some(40040) => seen[1] += 1,
            Some(40041) => seen[2] += 1,
            other => panic!("roll {roll}: {other:?}"),
        }
    }
    assert_eq!(seen, [500, 250, 250], "half plain, a quarter each shape");
    // The weights are live: all on the crossguard, always a crossguard; none at all, no shape (as before roles).
    assert!((0..1000).step_by(37).all(|r| rules::drop_handle(sword, r * 1000, 1_000_000, &weights(0.0, 25.0, 0.0)) == Some(40040)));
    assert_eq!(rules::drop_handle(sword, 0, 1_000_000, &weights(0.0, 0.0, 0.0)), None);
    // NEGATIVE: an axe (no roles yet), logs: nothing rolled.
    let axe = rules::ITEMS.iter().find(|i| i.name == "Iron axe").unwrap();
    assert_eq!(rules::drop_handle(axe, 0, 1_000_000, &w), None, "an axe has no roles yet");
    // Its data: the handle as its part, no traits on purpose; read back as the role.
    let data = rules::dropped_data(40041);
    assert_eq!(rules::parts_of_row(&data), vec![40041]);
    assert_eq!(rules::role_of_parts(&rules::parts_of_row(&data)).key, "support");
    assert!(rules::traits_of_row(&data).is_empty() && rules::quality_of(&data).is_none(), "no traits, no quality: {data}");
}

#[test]
fn threat_is_stored_and_healing_draws_no_more_than_damage() {
    // Stored for step 6 (threat targeting): the guard handle's multiplier and its scope are live rules.
    assert_eq!(rules::threat_pct(250.0, false, false), 250.0, "every foe");
    assert_eq!(rules::threat_pct(250.0, true, false), 100.0, "bosses only: a plain foe counts it as plain");
    assert_eq!(rules::threat_pct(250.0, true, true), 250.0, "bosses only: a boss counts it");
    assert!(rules::FOES.iter().all(|f| !f.boss), "no foe is a boss yet");
    // Healing: a point healed is at most a point of damage, at the healer's threat.
    let support = rules::role_keyed("support").unwrap();
    assert_eq!(support.threat_pct, 100, "the banner handle draws no extra threat");
    assert!(rules::heal_threat(8.0, support.threat_pct as f64) <= 8.0 * support.threat_pct as f64 / 100.0);
    assert_eq!(rules::role_keyed("tank").unwrap().threat_rule, "regents.guard_threat_pct");
    assert_eq!(rules::role_keyed("tank").unwrap().threat_scope_rule, "regents.guard_threat_bosses_only");
    // THE RALLYING CUT's own share: all of it alone, the live share with others near.
    assert_eq!(rules::rally_self_heal(8.0, 0, 50.0), 8.0);
    assert_eq!(rules::rally_self_heal(8.0, 2, 50.0), 4.0);
    assert_eq!(rules::rally_self_heal(8.0, 1, 0.0), 0.0);
}

#[test]
fn the_tutorial_walks_a_sword_from_wood_to_its_grip() {
    use umf_module::genre::regents::Deed;
    // THE RUN (Luke, 2026-11-01: make your own sword, then the fight with it): fifteen lessons, in order.
    let names: Vec<u32> = rules::LESSONS.iter().map(|l| l.order).collect();
    assert!(names.windows(2).all(|w| w[0] < w[1]) && rules::LESSONS.len() == 15, "fifteen lessons, in order: {names:?}");
    let deeds: Vec<u8> = rules::LESSONS.iter().map(|l| l.deed).collect();
    assert_eq!(deeds, vec![0, 1, 0, 1, 1, 1, 1, 2, 3, 4, 5, 6, 7, 8, 9], "gather, make ... then the fight, the grip's shape last");
    let item = |name: &str| rules::ITEMS.iter().find(|i| i.name == name).unwrap_or_else(|| panic!("{name}")).id;
    let chain: Vec<u32> = rules::LESSONS.iter().take(8).map(|l| l.item).collect();
    assert_eq!(chain, vec![item("Logs"), item("Grip"), item("Copper ore"), item("Copper bar"), item("Copper sword blade"),
        item("Copper rivets"), item("Copper sword"), item("Copper sword")]);
    // A KIND counts where the lesson says: any grip carves the grip, any sword makes the sword ...
    let grip = &rules::LESSONS[1];
    assert!(grip.ticked_by(Deed::Made, item("Oak crossguard grip")) && grip.ticked_by(Deed::Made, item("Grip")));
    let sword = &rules::LESSONS[6];
    assert!(sword.ticked_by(Deed::Made, item("Iron sword")) && sword.ticked_by(Deed::Made, item("Copper sword")));
    // NEGATIVE: ... and nothing else does: a sword blade is no sword, an axe no sword, logs gathered make no grip.
    assert!(!sword.ticked_by(Deed::Made, item("Copper sword blade")) && !sword.ticked_by(Deed::Made, item("Iron axe")));
    assert!(!grip.ticked_by(Deed::Gathered, item("Logs")) && !grip.ticked_by(Deed::Made, item("Copper rivets")));
    // NEGATIVE: an exact lesson takes its own item only (oak logs are not the logs).
    assert!(rules::LESSONS[0].ticked_by(Deed::Gathered, item("Logs")) && !rules::LESSONS[0].ticked_by(Deed::Gathered, item("Oak logs")));
    // TICKS: a deed ticks every lesson it matches not yet done; doing them all finishes the run.
    let (first, all) = rules::lessons_ticked(&[], Deed::Parried, 0);
    assert_eq!((first, all), (vec![rules::LESSONS[10].id], false), "a parry ticks the parry, in any order");
    let (again, _) = rules::lessons_ticked(&[rules::LESSONS[10].id], Deed::Parried, 0);
    assert!(again.is_empty(), "NEGATIVE: a lesson is ticked once");
    let (both, _) = rules::lessons_ticked(&[], Deed::Made, item("Copper sword"));
    assert_eq!(both, vec![rules::LESSONS[6].id], "a sword made ticks the making, not the holding");
    let mut done: Vec<u32> = rules::LESSONS.iter().take(14).map(|l| l.id).collect();
    let (last, all) = rules::lessons_ticked(&done, Deed::ShapedLastHit, 0);
    assert!(all && last == vec![rules::LESSONS[14].id], "the grip's shape is the last");
    done.pop();
    assert!(!rules::lessons_ticked(&done, Deed::ShapedLastHit, 0).1, "NEGATIVE: with one left undone, not finished");
}

#[test]
fn a_roll_clears_a_swing_judged_a_miss() {
    // A swing judged a miss: rolled through by a player still rolling (a tenth over, for the status's tick), within its
    // reach and a meter.
    assert!(rules::rolled_clear(300, 2.0, 2.0));
    assert!(rules::rolled_clear(-99, 3.0, 2.0), "just after the roll's end, a meter over its reach");
    // NEGATIVE: the roll long over (they stepped clear, not rolled), or out of reach (it was never at them).
    assert!(!rules::rolled_clear(-100, 1.0, 2.0));
    assert!(!rules::rolled_clear(300, 3.1, 2.0));
    // The guide is the genre's own kind, and no foe's.
    assert!(rules::CLAIMS.entity_kinds.contains(&rules::ENTITY_GUIDE) && !rules::FOE_KINDS.contains(&rules::ENTITY_GUIDE));
    // The sparring partner: soft, slow, no XP, and its last swing glints (goes through a guard).
    let spar = rules::FOES.iter().find(|f| f.key == "sparring_skeleton").expect("the sparring skeleton");
    assert!(spar.damage_pct <= 15 && spar.xp_pct == 0 && spar.loot_table == 0);
    let kit = rules::kit_keyed(spar.kit).unwrap();
    assert!(kit.unblockable(*kit.light.last().unwrap()) && !kit.unblockable(kit.light[0]));
}

#[test]
fn poise_breaks_only_on_the_last_hit_and_steadies() {
    // Luke, 2026-11-02 (A with a short B): lights wear poise but never break it; the string's last hit breaks it.
    let (most, light, last) = (70.0, 10.0, 40.0);
    let (a, broke) = rules::poise_hit(most, most, light, false, false);
    assert_eq!((a, broke), (60.0, false), "a light wears 10");
    let (b, _) = rules::poise_hit(a, most, light, false, false);
    let (c, broke) = rules::poise_hit(b, most, last, true, false);
    assert_eq!((c, broke), (10.0, false), "the sword's first string (10 + 10 + 40) leaves a skeleton 10 of 70: no stagger");
    let (d, _) = rules::poise_hit(c, most, light, false, false);
    assert_eq!(d, 1.0, "NEGATIVE: a light never breaks it, it stops at 1");
    let (e, broke) = rules::poise_hit(d, most, last, true, false);
    assert_eq!((e, broke), (most, true), "the next last hit breaks it: a stagger, and it is whole again");
    // HEAVY: 35 % more on the last hit breaks a 70-poise foe in one string (10 + 10 + 54 = 74).
    let (h, broke) = rules::poise_hit(50.0, most, last * 1.35, true, false);
    assert!(broke && h == most, "Heavy breaks it with the first string");
    // STEADIED (B): nothing wears it.
    assert_eq!(rules::poise_hit(5.0, most, last, true, true), (5.0, false), "NEGATIVE: steadied, the last hit does nothing to it");
    // No poise (0): handled by the caller as the old rule; here nothing changes.
    assert_eq!(rules::poise_hit(0.0, 0.0, last, true, false), (0.0, false));
    // WHOLE AGAIN, unhit for regen_ms.
    assert_eq!(rules::poise_now(12.0, most, 2999, 3000.0), 12.0);
    assert_eq!(rules::poise_now(12.0, most, 3000, 3000.0), most);
    // Every foe has poise; the dummy's is a live rule.
    assert!(rules::FOES.iter().all(|f| f.poise > 0), "every foe has poise");
}
