//! BODIES THE REFEREE MOVES (docs/FOUNDATION_SYSTEMS.md milestone 13, DECISIONS #246): something
//! thrown that the world's referee then flies with real physics (a disc, a ball, an egg). What a body
//! IS is content (`BodyDef`, `foundation/content/body/`, a genre's), baked; the module compiles in the
//! part it checks (who may throw it, how hard, from how far, how many, how long it lasts) as `BODIES`.
//! Its physics are the referee's and the thrower's game's, never the module's. Pure, so the native
//! suites check it.

use crate::sim::Vector3;

/// One body, as the module needs it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BodySeed {
    /// Its content id (`BodyDef.id`): what `body_state.def_id` names.
    pub id: u32,
    pub name: &'static str,
    /// The entity kinds whose characters may throw it themselves (`launch_body`). Empty: only a
    /// genre's own rules launch it.
    pub launchers: &'static [u8],
    /// The fastest it may leave a hand, m/s.
    pub max_speed: f32,
    /// The fastest it may spin as it leaves, rad/s.
    pub max_spin: f32,
    /// How far from its thrower it may start, m.
    pub reach: f32,
    /// How many of these one thrower may have at once (0: any number).
    pub max_per_owner: u8,
    /// How long one lasts once thrown, s (0: until a genre takes it away).
    pub lifetime_s: f32,
}

include!(concat!(env!("OUT_DIR"), "/bodies.rs"));

/// The body with content id `id`.
pub fn find(id: u32) -> Option<&'static BodySeed> {
    BODIES.iter().find(|b| b.id == id)
}

/// What a throw claims: where the body starts, how fast it goes and spins.
#[derive(Clone, Copy, Debug)]
pub struct Throw {
    pub origin: Vector3,
    pub vel: Vector3,
    pub spin: Vector3,
}

fn finite(v: Vector3) -> bool {
    v.x.is_finite() && v.y.is_finite() && v.z.is_finite()
}

fn len(v: Vector3) -> f32 {
    (v.x * v.x + v.y * v.y + v.z * v.z).sqrt()
}

/// A THROW BY A PLAYER, BOUNDED (rule 13: the client says what it threw, the server bounds it as Tier
/// A bounds a step). `launcher_kind` throws `seed` from `throw.origin`; the server last had the launcher
/// at `launcher_pos`, and it may have gone `slack_m` further since (its own speed, for the time a row
/// takes). Ok, or why not, as a sentence its player sees.
pub fn check_throw(seed: &BodySeed, launcher_kind: u8, launcher_pos: Vector3, slack_m: f32, throw: &Throw) -> Result<(), String> {
    if !seed.launchers.contains(&launcher_kind) {
        return Err(format!("launch_body: a {} is not something you can throw", seed.name));
    }
    if !(finite(throw.origin) && finite(throw.vel) && finite(throw.spin)) {
        return Err("launch_body: a throw must be finite".into());
    }
    let speed = len(throw.vel);
    if speed > seed.max_speed {
        return Err(format!("launch_body: {:.1} m/s is faster than a {} may be thrown ({:.1})", speed, seed.name, seed.max_speed));
    }
    let spin = len(throw.spin);
    if spin > seed.max_spin {
        return Err(format!("launch_body: {spin:.1} rad/s is more spin than a {} may have ({:.1})", seed.name, seed.max_spin));
    }
    let from = len(throw.origin.sub(launcher_pos));
    let allowed = seed.reach + slack_m.max(0.0);
    if from > allowed {
        return Err(format!("launch_body: thrown from {from:.2} m away; within {allowed:.2} m of you"));
    }
    Ok(())
}

/// Of a launcher's bodies of one kind, `(entity_id, launched_at_micros)`, the ones to take away so a
/// new one makes `max`: the oldest first. `max` 0: none.
pub fn over_limit(mut mine: Vec<(u64, i64)>, max: u8) -> Vec<u64> {
    if max == 0 || mine.len() < max as usize {
        return Vec::new();
    }
    mine.sort_by_key(|(id, at)| (*at, *id));
    let extra = mine.len() + 1 - max as usize;
    mine.into_iter().take(extra).map(|(id, _)| id).collect()
}

/// Whether a body launched at `launched_at_micros` has outlived its seed at `now_micros`.
pub fn expired(seed: &BodySeed, launched_at_micros: i64, now_micros: i64) -> bool {
    seed.lifetime_s > 0.0 && (now_micros - launched_at_micros) as f64 > seed.lifetime_s as f64 * 1_000_000.0
}
