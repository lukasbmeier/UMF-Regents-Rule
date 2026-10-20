//! LOOT TABLES (DECISIONS #268): each and one-of, nesting, pity, and who earns a roll. The owner's
//! Warden (LOOT_AND_STYLES.md §3) is the fixture.

use umf_module::loot::{contributors, pity_chance, roll, Drop, LootLineSeed, LootTableSeed, PityRoll, ROLL};

const fn item(item: u32, pct_pm: u32, lo: u32, hi: u32, to_bag: bool, pity: bool) -> LootLineSeed {
    LootLineSeed { item, table: 0, chance_pm: pct_pm, qty_min: lo, qty_max: hi, to_bag, pity }
}
const fn table(table: u32, pct_pm: u32) -> LootLineSeed {
    LootLineSeed { item: 0, table, chance_pm: pct_pm, qty_min: 1, qty_max: 1, to_bag: false, pity: false }
}

const BONES: u32 = 1;
const MARKS: u32 = 2;
const DAGGER: u32 = 3;
const CLOTH: u32 = 4;
const SHARD: u32 = 5;
const RECIPE: u32 = 6;
const SKULL: u32 = 7;

// warden (each): bones 100 % to_bag; marks 80 % -> one-of 5 / 10 / 15 marks at 50 / 35 / 15;
// undead_common 100 % -> each: dagger 10, cloth 25, shard 40; warden_recipe 2 % pity.
static WARDEN: [LootTableSeed; 3] = [
    LootTableSeed { id: 10, name: "warden", one_of: false, lines: &[
        item(BONES, 1_000_000, 1, 1, true, false),
        table(11, 800_000),
        table(12, 1_000_000),
        item(RECIPE, 20_000, 1, 1, false, true),
    ] },
    LootTableSeed { id: 11, name: "marks", one_of: true, lines: &[
        item(MARKS, 500_000, 5, 5, true, false),
        item(MARKS, 350_000, 10, 10, true, false),
        item(MARKS, 150_000, 15, 15, true, false),
    ] },
    LootTableSeed { id: 12, name: "undead_common", one_of: false, lines: &[
        item(DAGGER, 100_000, 1, 1, false, false),
        item(CLOTH, 250_000, 1, 1, false, false),
        item(SHARD, 400_000, 1, 1, false, false),
    ] },
];

/// A table's lines for a test's own table (a seed's lines are `'static`).
fn leak(v: Vec<LootLineSeed>) -> &'static [LootLineSeed] {
    Box::leak(v.into_boxed_slice())
}

/// The rolls, in order.
fn scripted(rolls: Vec<u32>) -> impl FnMut() -> u32 {
    let mut i = 0;
    move || {
        let r = rolls[i];
        i += 1;
        r
    }
}

/// A reproducible stream (an LCG), for the counts.
fn stream(mut s: u64) -> impl FnMut() -> u32 {
    move || {
        s = s.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        ((s >> 33) % ROLL as u64) as u32
    }
}

#[test]
fn annas_kill_of_the_warden_rolls_as_the_owner_wrote_it() {
    // bones: hit; marks: hit (0.79 < 0.8), the one-of roll 0.6 -> past 50, inside 85: 10 marks;
    // undead_common (100 %); dagger 0.2 misses, cloth 0.1 hits, shard 0.3 hits; the recipe, 150 misses in: 3.5 %, rolled 0.05 misses.
    let mut rng = scripted(vec![0, 790_000, 600_000, 0, 200_000, 100_000, 300_000, 50_000]);
    let since = |t: u32, l: u32| if (t, l) == (10, 3) { 150 } else { 0 };
    let (drops, pity) = roll(&WARDEN, 10, &mut rng, &since, 4.0, 20.0);
    assert_eq!(drops, vec![
        Drop { item: BONES, qty: 1, to_bag: true },
        Drop { item: MARKS, qty: 10, to_bag: true },
        Drop { item: CLOTH, qty: 1, to_bag: false },
        Drop { item: SHARD, qty: 1, to_bag: false },
    ]);
    assert_eq!(pity, vec![PityRoll { table: 10, line: 3, hit: false }], "the recipe was rolled, and missed: her run goes on");
    assert_eq!(pity_chance(20_000, 150, 4.0, 20.0), 35_000, "2 % x (1 + 150 / 200) = 3.5 % (N = 200, K = 1000 for a 2 % line)");
}

#[test]
fn bens_roll_hits_the_recipe_and_his_run_resets() {
    let mut rng = scripted(vec![0, 999_999, 0, 999_999, 999_999, 999_999, 10_000]);
    let since = |_: u32, _: u32| 40;
    let (drops, pity) = roll(&WARDEN, 10, &mut rng, &since, 4.0, 20.0);
    assert!(drops.contains(&Drop { item: RECIPE, qty: 1, to_bag: false }) && !drops.iter().any(|d| d.item == MARKS));
    assert_eq!(pity, vec![PityRoll { table: 10, line: 3, hit: true }]);
}

#[test]
fn pity_is_certain_after_its_cap_and_off_when_its_rules_are() {
    // 1 % line, cap 5x its usual 100 rolls: the 500th roll is certain.
    assert_eq!(pity_chance(10_000, 499, 1.0, 5.0), ROLL);
    assert!(pity_chance(10_000, 498, 1.0, 5.0) < ROLL);
    assert_eq!(pity_chance(10_000, 100, 1.0, 5.0), 20_000, "after its usual 100 misses, doubled");
    assert_eq!(pity_chance(10_000, 10_000, 0.0, 0.0), 10_000, "ramp and cap off: its own odds forever");
    assert_eq!(pity_chance(0, 9_999, 1.0, 5.0), 0, "a line that never drops still never does");
    // Rolled: never lucky, the run ends at the cap.
    let t = [LootTableSeed { id: 1, name: "t", one_of: false, lines: leak(vec![item(9, 10_000, 1, 1, false, true)]) }];
    let mut run = 0u32;
    let mut got_at = None;
    for k in 0..1_000 {
        let since = move |_: u32, _: u32| run;
        let (d, p) = roll(&t, 1, &mut || ROLL - 1, &since, 1.0, 5.0);
        if !d.is_empty() {
            got_at = Some(k + 1);
            assert!(p[0].hit);
            break;
        }
        run += 1;
    }
    assert_eq!(got_at, Some(500), "an unlucky player gets it on the 500th kill, never later");
}

#[test]
fn one_of_shares_come_out_as_typed_and_the_rest_is_nothing() {
    let t = [LootTableSeed { id: 1, name: "t", one_of: true, lines: leak(vec![
        item(1, 100_000, 1, 1, false, false), item(2, 200_000, 1, 1, false, false), item(3, 300_000, 1, 1, false, false),
    ]) }];
    let mut rng = stream(7);
    let n = 200_000;
    let mut counts = [0u32; 4];
    for _ in 0..n {
        let (d, _) = roll(&t, 1, &mut rng, &|_, _| 0, 1.0, 5.0);
        assert!(d.len() <= 1, "one of: never two");
        counts[d.first().map_or(0, |d| d.item as usize)] += 1;
    }
    for (i, want) in [(0usize, 0.40), (1, 0.10), (2, 0.20), (3, 0.30)] {
        let got = counts[i] as f64 / n as f64;
        assert!((got - want).abs() < 0.005, "line {i}: {got} for {want}");
    }
}

#[test]
fn adding_a_line_to_an_each_table_changes_no_other_line() {
    let base = [LootTableSeed { id: 12, name: "undead_common", one_of: false, lines: leak(vec![
        item(DAGGER, 100_000, 1, 1, false, false), item(CLOTH, 250_000, 1, 1, false, false), item(SHARD, 400_000, 1, 1, false, false),
    ]) }];
    let more = [LootTableSeed { id: 12, name: "undead_common", one_of: false, lines: leak(vec![
        item(DAGGER, 100_000, 1, 1, false, false), item(CLOTH, 250_000, 1, 1, false, false), item(SHARD, 400_000, 1, 1, false, false),
        item(SKULL, 150_000, 1, 1, false, false),
    ]) }];
    let n = 200_000;
    let rate = |tables: &[LootTableSeed], it: u32, seed: u64| -> f64 {
        let mut rng = stream(seed);
        let mut hits = 0u32;
        for _ in 0..n {
            hits += roll(tables, 12, &mut rng, &|_, _| 0, 1.0, 5.0).0.iter().filter(|d| d.item == it).count() as u32;
        }
        hits as f64 / n as f64
    };
    for (it, want) in [(DAGGER, 0.10), (CLOTH, 0.25), (SHARD, 0.40)] {
        let (a, b) = (rate(&base, it, 3), rate(&more, it, 4));
        assert!((a - want).abs() < 0.005 && (b - want).abs() < 0.005, "item {it}: {a} before, {b} with the skull, for {want}");
    }
    assert!((rate(&more, SKULL, 5) - 0.15).abs() < 0.005);
}

#[test]
fn quantities_span_their_range_and_a_missing_table_gives_nothing() {
    let t = [LootTableSeed { id: 1, name: "t", one_of: false, lines: leak(vec![item(1, 1_000_000, 2, 4, false, false)]) }];
    let mut seen = [false; 5];
    let mut rng = stream(11);
    for _ in 0..2_000 {
        let (d, _) = roll(&t, 1, &mut rng, &|_, _| 0, 1.0, 5.0);
        assert_eq!(d.len(), 1);
        assert!((2..=4).contains(&d[0].qty));
        seen[d[0].qty as usize] = true;
    }
    assert!(seen[2] && seen[3] && seen[4], "2, 3 and 4 all come up");
    assert_eq!(roll(&t, 99, &mut stream(1), &|_, _| 0, 1.0, 5.0).0, vec![], "a table that is not there");
}

#[test]
fn a_roll_earns_a_share_of_the_recent_damage() {
    let now = 100_000_000i64;
    let s = 1_000_000i64;
    // Anna 70, Ben 26, Cy 4 (under 5 %), Dee 50 but a minute and a half ago.
    let shares = [(1u64, 70.0f32, now - s), (2, 26.0, now - 2 * s), (3, 4.0, now), (4, 50.0, now - 90 * s)];
    assert_eq!(contributors(&shares, now, 5.0, 60.0), vec![1, 2], "Anna and Ben, most first; Cy under 5 %; Dee left the fight");
    assert_eq!(contributors(&shares, now, 0.0, 60.0), vec![1, 2, 3], "0 %: anyone who hit it lately");
    assert_eq!(contributors(&shares, now, 5.0, 0.0), vec![1, 4, 2], "never forgotten: Dee counts (Cy is under 5 % of 150)");
    assert_eq!(contributors(&[], now, 5.0, 60.0), Vec::<u64>::new());
}
