//! RESOURCES (DECISIONS #270): pools an entity spends to act (mana, stamina), filling by themselves,
//! slower in a fight than out of one. What a pool IS is content (`ResourceDef`, a genre's
//! `content/resource/`), baked as `RESOURCES`. Nothing ticks: a pool's row holds what it held after its
//! last spend and when, and `level` works out what it holds now (its twin: `ResourceDef.level`, so
//! every client draws the bar the server counts). Pure, so the native suites check it.

/// One resource, as the module needs it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ResourceSeed {
    pub id: u32,
    pub key: &'static str,
    pub max: f32,
    /// Filling a second, in a fight and out of one.
    pub regen_in: f32,
    pub regen_out: f32,
    /// In a fight for this long after the last spend, s.
    pub combat_s: f32,
}

include!(concat!(env!("OUT_DIR"), "/resources.rs"));

/// The resource with content id `id`.
pub fn find(id: u32) -> Option<&'static ResourceSeed> {
    RESOURCES.iter().find(|r| r.id == id)
}

/// WHAT A POOL HOLDS `since_s` after it last held `stored`: the first `combat_s` at the in-a-fight rate,
/// the rest at the other, never past `max`.
pub fn level(stored: f32, max: f32, since_s: f32, regen_in: f32, regen_out: f32, combat_s: f32) -> f32 {
    let t = since_s.max(0.0);
    let fighting = t.min(combat_s);
    (stored + regen_in * fighting + regen_out * (t - combat_s).max(0.0)).min(max)
}

/// `seed`'s pool, `since_s` after it held `stored`.
pub fn level_of(seed: &ResourceSeed, stored: f32, since_s: f32) -> f32 {
    level(stored, seed.max, since_s, seed.regen_in, seed.regen_out, seed.combat_s)
}
