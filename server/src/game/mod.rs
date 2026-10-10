//! THE GENRE LAYER. Everything in here belongs to a genre; nothing in it is foundation.
//!
//! The rule from `docs/TEMPLATE_WORKFLOW.md` is one-directional: **the foundation never imports
//! from `game/`.** It calls the hooks below and nothing else. That is what lets a new game start
//! from this repo, drop the genres it does not want, and still have a working foundation — and
//! what lets a fix in the foundation be subtree-pushed back without dragging a genre along.
//!
//! A GAME IS A LIST OF GENRES (DECISIONS #173). `shared/game.json` names them; build.rs compiles
//! exactly those in (`cfg(genre_<name>)`), each genre a file here (`<name>.rs`, with its pure rules
//! in `genre/`). Every hook below is passed to every genre the game has, in the file's order, each
//! a `Genre` that keeps only the hooks it needs. A genre's own numbers (challenge kinds, entity
//! kinds, phases, session kinds) are its `Claims`; two genres claiming one, or one claiming the
//! foundation's, stops the module at `init`.
//!
//! ADDING A GENRE: write `<name>.rs` (its tables, reducers and a `pub static <NAME>: impl Genre`,
//! the name upper-cased), its pure rules in `genre/<name>/`, any content it compiles in as a build
//! step in `server/build/` (listed in `build/genres.rs`), and name it in `shared/game.json`. No
//! foundation file names a genre: build.rs declares the modules. If you find
//! yourself wanting to edit `module.rs` to make your game work, the seam is in the wrong place:
//! widen a hook instead.

use crate::genre::Claims;
use crate::module::{Challenge, Entity, Session, StatusStateRow};
use spacetimedb::ReducerContext;

/// A GENRE, as the foundation sees it: the numbers it takes, and the hooks it answers. Every hook
/// has a default that does nothing, so a genre writes only the ones it uses. None may fail the
/// transaction: a genre's bug must not roll back a legitimate play or stop anyone connecting.
pub trait Genre: Sync {
    fn claims(&self) -> &'static Claims;

    /// Once, from `init`, after the foundation has seeded itself. Static content goes here.
    fn on_init(&self, _ctx: &ReducerContext) {}

    /// A NEW player, just made by `client_connected`: the foundation's rows exist (entity, player,
    /// movement at the world's spawn, health, session membership). A starting kit, a team, a class.
    fn on_player_created(&self, _ctx: &ReducerContext, _entity_id: u64) {}

    /// A player who has been here before connected again.
    fn on_player_returned(&self, _ctx: &ReducerContext, _entity_id: u64) {}

    /// A player disconnected. The foundation KEEPS their entity; a party game despawns it here.
    /// Every `spacetime call` from the CLI connects and disconnects too.
    fn on_player_left(&self, _ctx: &ReducerContext, _entity_id: u64) {}

    /// A FOUNDATION-kind challenge validated, with its quality.
    fn on_challenge_succeeded(&self, _ctx: &ReducerContext, _challenge: &Challenge, _quality: f32) {}

    /// A challenge ENDED, however it ended (submitted, expired, its entity gone). A genre clears
    /// what it keeps beside one of its own here.
    fn on_challenge_closed(&self, _ctx: &ReducerContext, _challenge: &Challenge) {}

    /// Judge a submission for one of this genre's challenge kinds: the quality, or None for no award.
    fn resolve_challenge(&self, _ctx: &ReducerContext, _challenge: &Challenge, _result: &[f32]) -> Option<f32> {
        None
    }

    /// A session's phase changed (`sess.phase`, from `from`), after the row is written.
    fn on_phase_changed(&self, _ctx: &ReducerContext, _sess: &Session, _from: u8) {}

    /// A world now runs another level (`world_level`, DECISIONS #175), after its spawn moved. A
    /// genre sets up what it keeps per level here (fishing: the greybox's ponds, its rival).
    fn on_level_changed(&self, _ctx: &ReducerContext, _world_id: u32, _level_id: u8) {}

    /// A session begins a new match (DECISIONS #182): its rounds count from 1 again
    /// (`module::match_round`) and its lobby waits for players. After `on_phase_changed`, when the
    /// match ended a round. A genre resets what it keeps per match here (fishing: the time of day
    /// starts again at dawn).
    fn on_match_began(&self, _ctx: &ReducerContext, _sess: &Session) {}

    /// An entity's status changed (DECISIONS #206), after its row is written: `from`, to `now.status`.
    /// A genre reacts here (a downed hen drops what it carried, an escaped one scores).
    fn on_status_changed(&self, _ctx: &ReducerContext, _entity_id: u64, _from: u8, _now: &StatusStateRow) {}

    /// A status's time is up: what it becomes, or None to leave it to the status's own `then`. The
    /// first genre to answer decides (a downed hen bleeds out unless a teammate is reviving it).
    fn on_status_expired(&self, _ctx: &ReducerContext, _row: &StatusStateRow) -> Option<u8> {
        None
    }

    /// A player used an entity of one of this genre's entity kinds (range and world checked).
    fn on_interact(&self, _ctx: &ReducerContext, _player_entity_id: u64, _target: &Entity, _verb: u8)
        -> Option<Result<(), String>> {
        None
    }
}

// EVERY GENRE THIS BUILD IS MADE OF, in `shared/game.json`'s order: build.rs declares each one's
// module (`game/<name>.rs`) and lists it in `GENRES` (its `pub static <NAME>`, the name upper-cased).
include!(concat!(env!("OUT_DIR"), "/genre_layer.rs"));

/// The genre that claims challenge kind `kind`, if any.
fn owner_of_challenge(kind: u8) -> Option<&'static dyn Genre> {
    GENRES.iter().copied().find(|g| g.claims().challenge_kinds.contains(&kind))
}

/// The genre that claims entity kind `kind`, if any.
fn owner_of_entity(kind: u8) -> Option<&'static dyn Genre> {
    GENRES.iter().copied().find(|g| g.claims().entity_kinds.contains(&kind))
}

// --- what the foundation calls --------------------------------------------------------------

/// After a FOUNDATION-kind challenge has VALIDATED: every genre hears it.
pub fn on_challenge_succeeded(ctx: &ReducerContext, challenge: &Challenge, quality: f32) {
    for g in GENRES {
        g.on_challenge_succeeded(ctx, challenge, quality);
    }
}

/// Whenever a challenge ends: its own genre (for a genre kind) or every genre (a foundation kind).
pub fn on_challenge_closed(ctx: &ReducerContext, challenge: &Challenge) {
    match owner_of_challenge(challenge.kind) {
        Some(g) => g.on_challenge_closed(ctx, challenge),
        None => {
            for g in GENRES {
                g.on_challenge_closed(ctx, challenge);
            }
        }
    }
}

/// A submission for a GENRE challenge kind: judged by the genre that claims the kind; none claims
/// it, no award.
pub fn resolve_challenge(ctx: &ReducerContext, challenge: &Challenge, result: &[f32]) -> Option<f32> {
    owner_of_challenge(challenge.kind)?.resolve_challenge(ctx, challenge, result)
}

pub fn on_phase_changed(ctx: &ReducerContext, sess: &Session, from: u8) {
    for g in GENRES {
        g.on_phase_changed(ctx, sess, from);
    }
}

pub fn on_match_began(ctx: &ReducerContext, sess: &Session) {
    for g in GENRES {
        g.on_match_began(ctx, sess);
    }
}

/// From `init`: the claims are checked first (a clash stops the module, loudly), then every genre
/// seeds itself.
pub fn on_init(ctx: &ReducerContext) {
    let claims: Vec<&Claims> = GENRES.iter().map(|g| g.claims()).collect();
    if let Err(why) = crate::genre::check_claims(&claims) {
        panic!("the genres in shared/game.json disagree about their numbers: {why}");
    }
    log::info!("genres: {:?}", crate::genre::enabled::ENABLED);
    for g in GENRES {
        g.on_init(ctx);
    }
}

pub fn on_player_created(ctx: &ReducerContext, entity_id: u64) {
    for g in GENRES {
        g.on_player_created(ctx, entity_id);
    }
}

pub fn on_player_returned(ctx: &ReducerContext, entity_id: u64) {
    for g in GENRES {
        g.on_player_returned(ctx, entity_id);
    }
}

pub fn on_player_left(ctx: &ReducerContext, entity_id: u64) {
    for g in GENRES {
        g.on_player_left(ctx, entity_id);
    }
}

pub fn on_level_changed(ctx: &ReducerContext, world_id: u32, level_id: u8) {
    for g in GENRES {
        g.on_level_changed(ctx, world_id, level_id);
    }
}

/// An entity of a genre's own kind was used: the genre that claims the kind answers, or None.
pub fn on_interact(ctx: &ReducerContext, player_entity_id: u64, target: &Entity, verb: u8) -> Option<Result<(), String>> {
    owner_of_entity(target.kind)?.on_interact(ctx, player_entity_id, target, verb)
}

pub fn on_status_changed(ctx: &ReducerContext, entity_id: u64, from: u8, now: &StatusStateRow) {
    for g in GENRES {
        g.on_status_changed(ctx, entity_id, from, now);
    }
}

/// The first genre that decides what an expired status becomes; None: the status's own `then`.
pub fn on_status_expired(ctx: &ReducerContext, row: &StatusStateRow) -> Option<u8> {
    GENRES.iter().find_map(|g| g.on_status_expired(ctx, row))
}
