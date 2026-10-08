//! THE GENRE LAYER'S PURE HALF: the rules a genre runs on that need no database — rolls,
//! timings, validators — so they can be tested natively like `sim` and `challenge`. Its tables
//! and reducers live in `game/`, which is wasm-gated; this directory is not, and must never
//! depend on the `spacetimedb` crate (DECISIONS #27).
//!
//! Same one-way rule as `game/`: the foundation never imports from here. Delete `game/` and
//! `genre/` together and the foundation still stands.

//!
//! A GAME IS A LIST OF GENRES (DECISIONS #173): `shared/game.json` names them and build.rs compiles
//! exactly those in, as `cfg(genre_<name>)`. A genre's pure rules sit behind its flag here.

#[cfg(genre_fishing)]
pub mod fight;
#[cfg(genre_fishing)]
pub mod fishing;

/// The genres this build is made of, in shared/game.json's order.
pub mod enabled {
    include!(concat!(env!("OUT_DIR"), "/genres.rs"));
}

/// THE NUMBERS A GENRE TAKES FOR ITSELF, so two genres in one game cannot both mean something by
/// the same one. Checked when the module starts (`check_claims`): a clash fails the publish.
pub struct Claims {
    pub name: &'static str,
    /// `challenge.kind`s it issues and resolves (from `challenge::KIND_GENRE_FROM`, 100).
    pub challenge_kinds: &'static [u8],
    /// `entity.kind`s of its own (from 100; the foundation's player, NPC and resource node are
    /// everyone's).
    pub entity_kinds: &'static [u8],
    /// `session.phase`s of its own (above the foundation's, `PHASE_FOUNDATION_MAX`).
    pub phases: &'static [u8],
    /// `session.kind`s of its own (the foundation's default round is 0).
    pub session_kinds: &'static [u8],
}

/// Where a genre's own numbers may start: below these they are the foundation's.
pub const CHALLENGE_KIND_FROM: u8 = crate::challenge::KIND_GENRE_FROM;
pub const ENTITY_KIND_FROM: u8 = 100;
/// The foundation's highest phase (`module.rs` PHASE_FOUNDATION_MAX).
pub const PHASE_FOUNDATION_MAX: u8 = 3;

/// No two genres claim the same number, and none claims one of the foundation's. Err says which.
pub fn check_claims(all: &[&Claims]) -> Result<(), String> {
    let mut problems: Vec<String> = Vec::new();
    let mut taken: Vec<(String, u8, &'static str)> = Vec::new();
    for c in all {
        let lists: [(&str, &[u8], u8); 4] = [
            ("challenge kind", c.challenge_kinds, CHALLENGE_KIND_FROM),
            ("entity kind", c.entity_kinds, ENTITY_KIND_FROM),
            ("phase", c.phases, PHASE_FOUNDATION_MAX + 1),
            ("session kind", c.session_kinds, 1),
        ];
        for (what, nums, from) in lists {
            for n in nums {
                if *n < from {
                    problems.push(format!("{} claims {what} {n}, which is the foundation's (a genre's start at {from})", c.name));
                }
                if let Some((_, _, by)) = taken.iter().find(|(w, m, _)| w == what && m == n) {
                    problems.push(format!("{} and {by} both claim {what} {n}", c.name));
                } else {
                    taken.push((what.to_string(), *n, c.name));
                }
            }
        }
    }
    if problems.is_empty() { Ok(()) } else { Err(problems.join("; ")) }
}
