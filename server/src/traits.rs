//! TRAITS (DECISIONS #275): what changes how an item plays, never its Power. A trait is content
//! (`TraitDef`, a genre's `content/trait/`), baked as `TRAITS`: a few ATOMS, each one number the game
//! reads where it acts ("damage" at a "heavy", "work_time" at a node), multiplying or adding. An item
//! carries its traits' ids in its row's `instance_data` (`"t":[40001]`). The game asks `mult` and
//! `value` at its hook points; the live dial `foundation.trait_strength_pct` scales every one (the
//! module passes it in, as a fraction). The client's twin is `Traits`. Pure, so the native suites check it.

/// One thing a trait does.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Atom {
    /// The number it changes, in the game's words ("damage", "recovery").
    pub what: &'static str,
    /// The action it touches ("basic", "heavy"); "": all.
    pub on: &'static str,
    /// A multiplier (1: none).
    pub mult: f32,
    /// Or an amount added, in percent (a chance, a share).
    pub value: f32,
    /// Its condition: "always" (or ""): "target_below" / "target_above" `threshold_pct` of the target's health; "against" a family.
    pub condition: &'static str,
    pub threshold_pct: f32,
    pub against: &'static str,
    /// It is the trait's cost.
    pub cost: bool,
}

/// One trait, as the module needs it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TraitSeed {
    pub id: u32,
    pub key: &'static str,
    pub name: &'static str,
    /// The item tags it may be on (one in common is enough).
    pub applies_to: &'static [&'static str],
    /// A dropped item may roll it.
    pub rollable: bool,
    pub atoms: &'static [Atom],
}

include!(concat!(env!("OUT_DIR"), "/traits.rs"));

/// The trait with content id `id`.
pub fn find(id: u32) -> Option<&'static TraitSeed> {
    TRAITS.iter().find(|t| t.id == id)
}

/// The trait with key `key`.
pub fn by_key(key: &str) -> Option<&'static TraitSeed> {
    TRAITS.iter().find(|t| t.key == key)
}

/// Where an action lands, for the atoms that only work sometimes: the target's health in percent of its
/// most (None: unknown, and no health condition holds) and its family ("": unknown).
#[derive(Clone, Copy, Debug, Default)]
pub struct Against<'a> {
    pub target_pct: Option<f32>,
    pub family: &'a str,
}

/// Whether atom `a`'s condition holds `against` its target.
pub fn holds(a: &Atom, against: &Against) -> bool {
    match a.condition {
        "" | "always" => true,
        "target_below" => against.target_pct.is_some_and(|p| p < a.threshold_pct),
        "target_above" => against.target_pct.is_some_and(|p| p >= a.threshold_pct),
        "against" => !against.family.is_empty() && against.family == a.against,
        _ => false,
    }
}

fn atoms<'a>(table: &'a [TraitSeed], ids: &'a [u32], what: &'a str, ons: &'a [&'a str], against: &'a Against<'a>) -> impl Iterator<Item = &'a Atom> + 'a {
    ids.iter().filter_map(move |id| table.iter().find(|t| t.id == *id)).flat_map(|t| t.atoms.iter())
        .filter(move |a| a.what == what && (a.on.is_empty() || ons.contains(&a.on)) && holds(a, against))
}

/// `what` at an action tagged `ons`, multiplied over the matching atoms of traits `ids`, each scaled by
/// `strength` (1.0 as authored, 0 none: `foundation.trait_strength_pct` / 100).
pub fn mult(ids: &[u32], what: &str, ons: &[&str], against: &Against, strength: f32) -> f32 {
    mult_in(TRAITS, ids, what, ons, against, strength)
}

/// `mult` over another table of traits (a suite's).
pub fn mult_in(table: &[TraitSeed], ids: &[u32], what: &str, ons: &[&str], against: &Against, strength: f32) -> f32 {
    atoms(table, ids, what, ons, against).fold(1.0, |m, a| m * (1.0 + (a.mult - 1.0) * strength))
}

/// `what` added up over the matching atoms (a chance, a share), in percent, scaled by `strength`.
pub fn value(ids: &[u32], what: &str, ons: &[&str], against: &Against, strength: f32) -> f32 {
    value_in(TRAITS, ids, what, ons, against, strength)
}

/// `value` over another table of traits.
pub fn value_in(table: &[TraitSeed], ids: &[u32], what: &str, ons: &[&str], against: &Against, strength: f32) -> f32 {
    atoms(table, ids, what, ons, against).map(|a| a.value * strength).sum()
}

/// Whether trait `t` may be on an item with tags `tags`.
pub fn fits(t: &TraitSeed, tags: &[&str]) -> bool {
    t.applies_to.iter().any(|a| tags.contains(a))
}

/// The trait ids in an item's `instance_data` (`"t":[40001,40002]`): none for none.
pub fn ids_of(instance_data: &str) -> Vec<u32> {
    let Some(at) = instance_data.find("\"t\":[") else { return Vec::new() };
    let rest = &instance_data[at + 5..];
    let Some(end) = rest.find(']') else { return Vec::new() };
    rest[..end].split(',').filter_map(|s| s.trim().parse().ok()).collect()
}

/// `instance_data` carrying traits `ids` (in place of any it had); none: the key is taken out.
pub fn with_ids(instance_data: &str, ids: &[u32]) -> String {
    let list = ids.iter().map(|i| i.to_string()).collect::<Vec<_>>().join(",");
    let field = format!("\"t\":[{list}]");
    let body = instance_data.trim();
    if let Some(at) = body.find("\"t\":[") {
        let end = at + 5 + body[at + 5..].find(']').map_or(0, |e| e + 1);
        let (before, after) = (&body[..at], &body[end..]);
        if ids.is_empty() {
            // Its comma goes with it: the one before it, or else the one after it.
            let before = before.trim_end();
            let (before, after) = match before.strip_suffix(',') {
                Some(b) => (b, after),
                None => (before, after.trim_start().strip_prefix(',').unwrap_or(after)),
            };
            return format!("{before}{after}");
        }
        return format!("{before}{field}{after}");
    }
    if ids.is_empty() {
        return instance_data.to_string();
    }
    match body.strip_suffix('}') {
        Some(open) if open.trim_end().ends_with('{') => format!("{open}{field}}}"),
        Some(open) => format!("{open},{field}}}"),
        None => format!("{{{field}}}"),
    }
}

/// ROLL `count` traits for a dropped item with tags `tags`: distinct, rollable, fitting, each pick from a
/// fresh `roll_from(seed + n)` (the loot engine's). Fewer when fewer fit.
pub fn roll(tags: &[&str], count: usize, seed: u64) -> Vec<u32> {
    roll_in(TRAITS, tags, count, seed)
}

/// `roll` from another table of traits.
pub fn roll_in(table: &[TraitSeed], tags: &[&str], count: usize, seed: u64) -> Vec<u32> {
    let mut pool: Vec<u32> = table.iter().filter(|t| t.rollable && fits(t, tags)).map(|t| t.id).collect();
    pool.sort_unstable();
    let mut out = Vec::new();
    let mut n = 0u64;
    while out.len() < count && !pool.is_empty() {
        let pick = crate::loot::roll_from(seed.wrapping_add(n)) as usize % pool.len();
        out.push(pool.remove(pick));
        n += 1;
    }
    out
}
