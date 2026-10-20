//! LOOT TABLES (DECISIONS #268): what a kill drops. A table is content (`LootTableDef`, a genre's
//! `content/loot_table/`), baked and compiled in as `LOOT_TABLES`. Rolled ONCE PER CONTRIBUTING PLAYER
//! (a personal roll: `module/loot.rs` decides who contributed), with that player's pity. Pure, so the
//! native suites check it.
//!
//!   EACH     every line rolls its own chance; several can drop; adding a line changes no other line.
//!   ONE-OF   one roll, walked through the lines' shares (absolute percentages, at most 100 in all:
//!            the bake refuses more); past the last share, nothing.
//!   PITY     a line marked so (each tables only): its chance for a player grows with the misses since
//!            their last hit (`pity_chance`), and is certain after enough of them.

/// One line, as baked: an item or a nested table, its chance in parts per million.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LootLineSeed {
    /// The item's content id, or 0 when the line is a table.
    pub item: u32,
    /// The nested table's content id, or 0.
    pub table: u32,
    /// Its chance (each) or share (one-of), per million.
    pub chance_pm: u32,
    pub qty_min: u32,
    pub qty_max: u32,
    /// Straight into the bag, never on the ground.
    pub to_bag: bool,
    pub pity: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LootTableSeed {
    pub id: u32,
    pub name: &'static str,
    pub one_of: bool,
    pub lines: &'static [LootLineSeed],
}

include!(concat!(env!("OUT_DIR"), "/loot_tables.rs"));

/// A table nests at most this deep (the bake refuses deeper, and a loop).
pub const MAX_DEPTH: u32 = 8;
/// A roll: 0 .. ROLL (parts per million).
pub const ROLL: u32 = 1_000_000;

/// What one roll gave.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Drop {
    pub item: u32,
    pub qty: u32,
    pub to_bag: bool,
}

/// A pity line that was rolled, and whether it hit (the player's count goes up, or back to 0).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PityRoll {
    pub table: u32,
    pub line: u32,
    pub hit: bool,
}

/// The table with content id `id` among this game's.
pub fn find(id: u32) -> Option<&'static LootTableSeed> {
    LOOT_TABLES.iter().find(|t| t.id == id)
}

/// A pity line's chance (per million) after `since` misses in a row: its own odds `base_pm`, times
/// `1 + since / N`, certain from the `K`th roll. N and K are in units of the line's own expected rolls
/// (`1 / odds`): `ramp_x` (1: after as many misses as it usually takes, the odds have doubled) and
/// `cap_x` (5: never more than five times the usual run). 0 turns either off.
pub fn pity_chance(base_pm: u32, since: u32, ramp_x: f64, cap_x: f64) -> u32 {
    if base_pm == 0 {
        return 0;
    }
    let p = base_pm.min(ROLL) as f64 / ROLL as f64;
    if cap_x > 0.0 && (since as f64 + 1.0) >= cap_x / p {
        return ROLL;
    }
    let eff = if ramp_x > 0.0 { p * (1.0 + since as f64 / (ramp_x / p)) } else { p };
    ((eff.min(1.0) * ROLL as f64).round() as u32).min(ROLL)
}

/// ROLL TABLE `id` among `tables` once: `rng` gives 0..ROLL; `since(table, line)` is the player's run of
/// misses on a pity line. Returns what dropped, and every pity line rolled.
pub fn roll(
    tables: &[LootTableSeed],
    id: u32,
    rng: &mut dyn FnMut() -> u32,
    since: &dyn Fn(u32, u32) -> u32,
    ramp_x: f64,
    cap_x: f64,
) -> (Vec<Drop>, Vec<PityRoll>) {
    let mut drops = Vec::new();
    let mut pity = Vec::new();
    roll_into(tables, id, rng, since, ramp_x, cap_x, 0, &mut drops, &mut pity);
    (drops, pity)
}

#[allow(clippy::too_many_arguments)]
fn roll_into(
    tables: &[LootTableSeed],
    id: u32,
    rng: &mut dyn FnMut() -> u32,
    since: &dyn Fn(u32, u32) -> u32,
    ramp_x: f64,
    cap_x: f64,
    depth: u32,
    drops: &mut Vec<Drop>,
    pity: &mut Vec<PityRoll>,
) {
    if depth >= MAX_DEPTH {
        return;
    }
    let Some(t) = tables.iter().find(|t| t.id == id) else { return };
    if t.one_of {
        let r = rng() % ROLL;
        let mut upto: u64 = 0;
        for l in t.lines {
            upto += l.chance_pm as u64;
            if (r as u64) < upto {
                give(tables, l, rng, since, ramp_x, cap_x, depth, drops, pity);
                return;
            }
        }
        return;
    }
    for (i, l) in t.lines.iter().enumerate() {
        let chance = if l.pity { pity_chance(l.chance_pm, since(t.id, i as u32), ramp_x, cap_x) } else { l.chance_pm };
        let hit = rng() % ROLL < chance;
        if l.pity {
            pity.push(PityRoll { table: t.id, line: i as u32, hit });
        }
        if hit {
            give(tables, l, rng, since, ramp_x, cap_x, depth, drops, pity);
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn give(
    tables: &[LootTableSeed],
    l: &LootLineSeed,
    rng: &mut dyn FnMut() -> u32,
    since: &dyn Fn(u32, u32) -> u32,
    ramp_x: f64,
    cap_x: f64,
    depth: u32,
    drops: &mut Vec<Drop>,
    pity: &mut Vec<PityRoll>,
) {
    if l.table != 0 {
        roll_into(tables, l.table, rng, since, ramp_x, cap_x, depth + 1, drops, pity);
        return;
    }
    let span = l.qty_max.saturating_sub(l.qty_min) + 1;
    let qty = l.qty_min + if span > 1 { rng() % span } else { 0 };
    if qty > 0 {
        drops.push(Drop { item: l.item, qty, to_bag: l.to_bag });
    }
}

/// WHO GETS A ROLL: of `shares` (attacker, damage dealt, when they last hit, micros), those whose last
/// hit is within `forget_s` of `now` and who dealt at least `min_pct` % of what those dealt, most
/// damage first.
pub fn contributors(shares: &[(u64, f32, i64)], now: i64, min_pct: f64, forget_s: f64) -> Vec<u64> {
    let fresh: Vec<&(u64, f32, i64)> = shares
        .iter()
        .filter(|s| s.1 > 0.0 && (forget_s <= 0.0 || (now - s.2) as f64 <= forget_s * 1_000_000.0))
        .collect();
    let total: f64 = fresh.iter().map(|s| s.1 as f64).sum();
    if total <= 0.0 {
        return Vec::new();
    }
    let mut out: Vec<&(u64, f32, i64)> = fresh.into_iter().filter(|s| s.1 as f64 * 100.0 / total + 1e-9 >= min_pct).collect();
    out.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal).then(a.0.cmp(&b.0)));
    out.into_iter().map(|s| s.0).collect()
}

/// A roll from a seed (splitmix64), 0..ROLL: the module seeds it from the moment, the target and the
/// player, so each player's roll is their own.
pub fn roll_from(seed: u64) -> u32 {
    let mut z = seed.wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;
    (z % ROLL as u64) as u32
}
