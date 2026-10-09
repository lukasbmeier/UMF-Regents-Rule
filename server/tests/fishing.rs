//! The fishing genre's pure rules (`genre::fishing`), natively.
//!   cargo test --test fishing
//!
//! The hook-set grade has a GDScript twin and runs shared/golden/fishing/hookset.json exactly
//! (the headless runner runs the same file against `FishingData.grade_hookset`). The rolls have
//! no twin — the client never predicts them — so they are tested for the properties the game
//! promises instead: a spot's categories come up at its weights, light things are the common
//! things, a better spot bites faster, a crowded one slower.

// Fishing's rules exist only in a game made with fishing (shared/game.json, DECISIONS #173).
#![cfg(genre_fishing)]

use serde::Deserialize;
use std::{collections::HashMap, fs, path::Path};
use umf_module::genre::fishing::*;

#[derive(Deserialize)]
struct Golden {
    cases: Vec<Case>,
}

#[derive(Deserialize)]
struct Case {
    reaction: f32,
    window_mult: f32,
    grade: String,
}

fn word(g: Option<HookSet>) -> &'static str {
    g.map(|h| h.word()).unwrap_or("none")
}

#[test]
fn hookset_grades_match_the_golden_file() {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join("../shared/golden/fishing/hookset.json");
    let doc: Golden = serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap();
    let mut bad = Vec::new();
    for c in &doc.cases {
        let got = word(grade_hookset(c.reaction, c.window_mult));
        if got != c.grade {
            bad.push(format!("reaction {:e} x{}: got {got}, want {}", c.reaction, c.window_mult, c.grade));
        }
    }
    println!("hookset: {} cases, {} mismatches", doc.cases.len(), bad.len());
    assert!(bad.is_empty(), "\n{}", bad.join("\n"));
    // And the golden file actually exercises every verdict.
    for g in ["none", "perfect", "good", "late"] {
        assert!(doc.cases.iter().any(|c| c.grade == g), "golden file has no '{g}' case");
    }
}

#[test]
fn a_better_reel_widens_the_window_but_not_the_perfect() {
    let slow = HOOKSET_WINDOW_S + 0.1;
    assert_eq!(grade_hookset(slow, reel(0).hookset_window_mult), None, "too slow on the starting reel");
    assert_eq!(grade_hookset(slow, reel(max_tier()).hookset_window_mult), Some(HookSet::Late),
        "the top reel still catches it, as a late set");
    assert_eq!(grade_hookset(HOOKSET_PERFECT_S + 0.01, reel(max_tier()).hookset_window_mult), Some(HookSet::Good),
        "the perfect window does not grow with the reel");
    assert_eq!(grade_hookset(MIN_REACTION_S * 0.5, 1.0), None, "a press faster than a reaction is refused");
    assert_eq!(grade_hookset(f32::NAN, 1.0), None);
}

#[test]
fn a_spot_rolls_its_categories_at_its_weights() {
    for spot in SPOTS.iter().chain(std::iter::once(&OPEN_WATER)) {
        let total: f32 = spot.loot.iter().map(|(_, w)| *w).sum();
        let mut counts: HashMap<usize, u32> = HashMap::new();
        let n = 40_000;
        for i in 0..n {
            let mut dice = Dice::new(i as u64 * 7919 + 13, SALT_CATCH);
            let c = roll_catch(&mut dice, spot, &[]);
            *counts.entry(c.category).or_default() += 1;
        }
        for (cat, w) in spot.loot {
            let want = w / total;
            let got = *counts.get(cat).unwrap_or(&0) as f32 / n as f32;
            assert!((got - want).abs() < 0.02,
                "spot '{}': category {} came up {:.3}, weighted {:.3}", spot.id, CATEGORIES[*cat].id, got, want);
        }
        for (cat, _) in counts.iter() {
            assert!(spot.loot.iter().any(|(c, _)| c == cat), "spot '{}' rolled a category it does not stock", spot.id);
        }
    }
}

#[test]
fn light_things_are_the_common_things() {
    // Inside one category, 1/sqrt(kg): the lightest catch must come up more than the heaviest.
    let spot = spot_loot("deep_hole");
    let mut counts: HashMap<&str, u32> = HashMap::new();
    for i in 0..60_000u64 {
        let mut dice = Dice::new(i * 104_729 + 7, SALT_CATCH);
        *counts.entry(roll_catch(&mut dice, spot, &[]).id).or_default() += 1;
    }
    for (cat, _) in spot.loot {
        let mut members: Vec<&CatchDef> = CATCHES.iter().filter(|d| d.category == *cat).collect();
        members.sort_by(|a, b| a.kg.partial_cmp(&b.kg).unwrap());
        let (light, heavy) = (members[0], members[members.len() - 1]);
        if light.kg < heavy.kg {
            assert!(counts.get(light.id) > counts.get(heavy.id),
                "{}: {} ({} kg) came up {:?} times, {} ({} kg) {:?}", CATEGORIES[*cat].id,
                light.id, light.kg, counts.get(light.id), heavy.id, heavy.kg, counts.get(heavy.id));
        }
    }
}

#[test]
fn every_catch_can_be_caught_somewhere() {
    let mut caught: HashMap<&str, bool> = HashMap::new();
    for spot in SPOTS.iter().chain(std::iter::once(&OPEN_WATER)) {
        for i in 0..20_000u64 {
            let mut dice = Dice::new(i * 31 + spot.id.len() as u64, SALT_CATCH);
            caught.insert(roll_catch(&mut dice, spot, &[]).id, true);
        }
    }
    let missing: Vec<&str> = CATCHES.iter().map(|c| c.id).filter(|id| !caught.contains_key(id)).collect();
    assert!(missing.is_empty(), "never rolled anywhere: {missing:?}");
}

#[test]
fn the_same_seed_rolls_the_same_catch() {
    for seed in [0u64, 1, 42, u64::MAX, 0xDEAD_BEEF_0000_0001] {
        let mut a = Dice::new(seed, SALT_CATCH);
        let mut b = Dice::new(seed, SALT_CATCH);
        let spot = spot_loot("north_drop");
        assert_eq!(roll_catch(&mut a, spot, &[]).id, roll_catch(&mut b, spot, &[]).id);
        assert_eq!(roll_kg(&mut a, CATCHES.first().unwrap()).to_bits(), roll_kg(&mut b, CATCHES.first().unwrap()).to_bits());
        // A different stream from the same seed is a different stream.
        let mut c = Dice::new(seed, SALT_BITE);
        let mut d = Dice::new(seed, SALT_CATCH);
        assert_ne!(c.next_u32(), d.next_u32(), "salts must separate the streams (seed {seed})");
    }
}

#[test]
fn a_rolled_weight_stays_near_its_kind() {
    for (i, def) in CATCHES.iter().enumerate() {
        let mut dice = Dice::new(i as u64, SALT_CATCH);
        for _ in 0..200 {
            let kg = roll_kg(&mut dice, def);
            assert!(kg >= def.kg * 0.75 - 1e-4 && kg <= def.kg * 1.25 + 1e-4, "{}: {kg} kg", def.id);
        }
    }
}

#[test]
fn rich_quiet_spots_bite_faster() {
    let spot = spot_loot("dock_end");
    let rich = bite_delay(0.5, spot, 1.0, 0, 1.0);
    let fished_out = bite_delay(0.5, spot, RICHNESS_FLOOR, 0, 1.0);
    let crowded = bite_delay(0.5, spot, 1.0, 3, 1.0);
    assert!(fished_out > rich, "a fished-out spot bites slower ({fished_out} vs {rich})");
    assert!(crowded > rich, "a crowded spot bites slower ({crowded} vs {rich})");
    // Never instant, never forever.
    for u in [0.0f32, 0.5, 1.0] {
        for spot in SPOTS.iter().chain(std::iter::once(&OPEN_WATER)) {
            let d = bite_delay(u, spot, RICHNESS_FLOOR, 10, 1.0);
            assert!(d >= BITE_MIN_S * 0.3 && d <= BITE_CAP_S, "{}: bite at {d} s", spot.id);
            assert!(BITE_CAP_S + HOOKSET_WINDOW_S * 2.0 < LINE_LIFE_S, "a capped bite must fit inside a line's life");
        }
    }
    // The slow spot is slow: the Deep Hole makes you wait.
    assert!(bite_delay(0.5, spot_loot("deep_hole"), 1.0, 0, 1.0) > bite_delay(0.5, spot_loot("reed_bay"), 1.0, 0, 1.0));
}

#[test]
fn payouts() {
    let def = catch_def("northern_pike").unwrap();
    let clean = coins_for(def, def.kg, 1.0, false);
    assert_eq!(clean, def.value, "a typical one cleanly hooked pays its value");
    assert!(coins_for(def, def.kg * 1.2, 1.0, false) > clean, "a bigger one pays more");
    assert!(coins_for(def, def.kg, 0.45, false) < clean, "a late hook-set pays less");
    assert_eq!(coins_for(def, def.kg, 1.0, true), clean * 2, "a deadlift pays double");
    assert!(coins_for(catch_def("small_crappie").unwrap(), 0.01, 0.0, false) >= 1, "everything pays something");
}

#[test]
fn gear_tracks_climb() {
    for w in RODS.windows(2) {
        assert!(w[1].max_cast_m > w[0].max_cast_m && w[1].cost > w[0].cost, "rods must reach further and cost more");
    }
    for w in REELS.windows(2) {
        assert!(w[1].hookset_window_mult > w[0].hookset_window_mult && w[1].cost > w[0].cost);
    }
    for w in LINES.windows(2) {
        assert!(w[1].max_load_kg > w[0].max_load_kg && w[1].cost > w[0].cost);
    }
    assert_eq!(RODS[0].cost, 0, "the starting kit is free");
    assert_eq!(rod(99).name, RODS[RODS.len() - 1].name, "an out-of-range tier clamps");
}

// =============================================================================================
// THE TIME OF DAY AND THE WEATHER (DECISIONS #168)
// =============================================================================================

/// How often each category comes up at `spot` under `tags`, over the same seeds.
fn category_shares(spot: &SpotLoot, tags: &[&str], n: u64) -> HashMap<usize, f32> {
    let mut counts: HashMap<usize, u32> = HashMap::new();
    for seed in 0..n {
        let mut dice = Dice::new(seed * 7919 + 13, SALT_CATCH);
        *counts.entry(roll_catch(&mut dice, spot, tags).category).or_default() += 1;
    }
    counts.into_iter().map(|(c, k)| (c, k as f32 / n as f32)).collect()
}

fn category_index(id: &str) -> usize {
    CATEGORIES.iter().position(|c| c.id == id).unwrap()
}

#[test]
fn no_conditions_roll_exactly_as_before() {
    // A tag nothing likes changes nothing, draw for draw: the conditions only reweight.
    let spot = spot_loot("deep_hole");
    for seed in 0..2000u64 {
        let mut a = Dice::new(seed, SALT_CATCH);
        let mut b = Dice::new(seed, SALT_CATCH);
        assert_eq!(roll_catch(&mut a, spot, &[]).id, roll_catch(&mut b, spot, &["no_such_condition"]).id);
    }
}

#[test]
fn the_night_and_the_fog_bring_up_the_strange_fish() {
    let spot = spot_loot("deep_hole");
    let whoa = category_index("fish_whoa");
    let plain = category_shares(spot, &[], 6000)[&whoa];
    let night = category_shares(spot, &["night", "fog"], 6000)[&whoa];
    let day = category_shares(spot, &["day", "clear"], 6000)[&whoa];
    assert!(night > plain * 1.4, "strange fish at night in fog {night:.3}, plainly {plain:.3}");
    // Nothing in the deep hole likes a clear day, so a clear day fishes it exactly as no conditions.
    assert!((day - plain).abs() < 1e-6, "a clear day changes nothing there ({day:.3} vs {plain:.3})");
    let nice = category_index("fish_nice");
    let dusk = category_shares(spot, &["dusk", "rain"], 6000)[&nice];
    assert!(dusk > category_shares(spot, &[], 6000)[&nice] * 1.3, "good fish at a rainy dusk {dusk:.3}");
}

#[test]
fn a_catch_can_like_a_time_of_its_own() {
    // The channel catfish likes the night more than the rest of its category does.
    let catfish_share = |tags: &[&str]| {
        let spot = spot_loot("reed_bay");
        let decent = category_index("fish_decent");
        let (mut cat, mut all) = (0u32, 0u32);
        for seed in 0..8000u64 {
            let mut dice = Dice::new(seed * 104729 + 7, SALT_CATCH);
            let c = roll_catch(&mut dice, spot, tags);
            if c.category == decent {
                all += 1;
                if c.id == "channel_catfish" {
                    cat += 1;
                }
            }
        }
        cat as f32 / all.max(1) as f32
    };
    let (night, day) = (catfish_share(&["night"]), catfish_share(&["day"]));
    assert!(night > day * 2.0, "catfish share of decent fish at night {night:.3}, by day {day:.3}");
}

#[test]
fn rounds_go_round_the_times_of_day() {
    assert_eq!(time_for_round(0), 0);
    assert_eq!(time_for_round(1), 0);
    for r in 1..=12u32 {
        assert_eq!(time_for_round(r) as usize, (r as usize - 1) % TIMES.len());
    }
}

#[test]
fn weather_comes_up_by_its_weight() {
    let n = 20000u64;
    let mut counts = vec![0u32; WEATHERS.len()];
    for seed in 0..n {
        let mut d = Dice::new(seed, SALT_WEATHER);
        counts[roll_weather(&mut d) as usize] += 1;
    }
    let total: f32 = WEATHERS.iter().map(|w| w.weight).sum();
    for (i, w) in WEATHERS.iter().enumerate() {
        let got = counts[i] as f32 / n as f32;
        let want = w.weight / total;
        assert!((got - want).abs() < 0.02, "{}: {got:.3}, its weight says {want:.3}", w.id);
    }
}

#[test]
fn conditions_speed_the_bite() {
    let spot = spot_loot("dock_end");
    let calm = bite_delay(0.3, spot, 1.0, 0, 1.0);
    let rain_at_dusk = Conditions { time: TIMES.iter().position(|t| t.id == "dusk").unwrap() as u8,
        weather: WEATHERS.iter().position(|w| w.id == "rain").unwrap() as u8 };
    assert_eq!(rain_at_dusk.tags(), ["dusk", "rain"]);
    let fast = bite_delay(0.3, spot, 1.0, 0, rain_at_dusk.bite_speed());
    assert!((fast * rain_at_dusk.bite_speed() - calm).abs() < 1e-4, "dusk rain bites {fast:.2} s, calm {calm:.2} s");
    assert!(fast < calm);
}

#[test]
fn the_rival_is_set_up_sensibly() {
    assert!(!RIVAL.spots.is_empty());
    for s in RIVAL.spots {
        assert!(SPOTS.iter().any(|l| l.id == *s), "the rival fishes '{s}', which has no loot");
    }
    assert!(RIVAL.land_chance.len() >= 5, "a landing chance for every rarity");
    assert!(RIVAL.land_chance.iter().all(|c| (0.0..=1.0).contains(c)));
    assert!(RIVAL.fight_s.0 > 0.0 && RIVAL.fight_s.0 <= RIVAL.fight_s.1);
    assert!((RIVAL.rod_tier as usize) < RODS.len());
}

/// Fishing claims only numbers of its own (moved from tests/genres.rs: the foundation's suite names no genre).
#[test]
fn fishing_claims_only_its_own() {
    assert_eq!(umf_module::genre::check_claims(&[&CLAIMS]), Ok(()));
    assert_eq!(CLAIMS.challenge_kinds, &[100]);
}

/// THE FIGHT'S REPORTS FIT THEIR RATE LIMIT (REVIEW B3; moved from tests/rate.rs).
#[test]
fn honest_clients_stay_inside_the_shipped_limits() {
    // The fight is reported every 0.2 s and at once when its tell changes (fishing_component.gd,
    // SHOW_INTERVAL_SEC): at worst a change on every physics frame for a moment. A second of
    // reports at 5 a second, then 8 changes inside 0.1 s, then reports again, must all pass.
    let l = umf_module::rules::rate_limit("show_fight");
    let mut t = None;
    let mut calls: Vec<f64> = (0..5).map(|k| k as f64 * 0.2).collect();
    calls.extend((0..8).map(|k| 1.0 + k as f64 / 60.0));
    calls.extend((0..25).map(|k| 1.2 + k as f64 * 0.2));
    let mut last = 0.0;
    for at in calls {
        t = Some(umf_module::rules::rate_spend(t, at - last, l).unwrap_or_else(|| panic!("show_fight refused at {at:.2} s")));
        last = at;
    }
    assert_eq!(l.verb, "show_fight", "shared/rules.json has no rate_limits.show_fight");
}
