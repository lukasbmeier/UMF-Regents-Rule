//! Fishing — the first genre built on the foundation (GENRE_ADAPTERS §1).
//!
//! THE LOOP, carried over from Fishing for Compliments with the server deciding everything:
//!
//!   aim   the client draws the float's arc and a ring where it will land; the rod decides how
//!         far it can reach. Nothing is sent while aiming.
//!   cast  `cast(target)`. The module checks the phase, the reach and that there is water under
//!         the ring (the level's bake, `crate::level`), works out which spot that is, and ROLLS
//!         EVERYTHING NOW, from the cast's seed: what is on the line, how heavy, and when it
//!         bites. It goes in a private `fishing_cast` row, and the client's copy in the challenge
//!         payload, which only its owner can read (RLS, DECISIONS #32).
//!   wait  the client counts down to the bite it was told, twitching the float for the tell. A
//!         press before the bite reels in (`reel_in`): nothing on it, no penalty.
//!   set   the float goes under; the player presses, and the client grades it on the spot with
//!         the module's own rule (a twin, `genre::fishing::grade_hookset`).
//!   fight THE PUMP (`genre::fight`): load the rod, release in the band, crank the slack down,
//!         give line when it runs. The client plays it for feel and keeps every tick's input.
//!   land  it submits the REACTION and the fight's input LOG; `resolve_challenge` grades the
//!         reaction and REPLAYS the log through the same simulation. A catch the replay landed
//!         is a `catch` row, coins and score, and a spot a little more fished out.
//!
//! What is left behind from Fishing for Compliments: its server took the client's word for the
//! catch and the combo, and each client kept its own idea of how fished-out a spot was. Here the
//! client submits its inputs, the server re-runs them, and the spots are rows.
//!
//! Everything here is genre content. The foundation supplies sessions and phases, the Challenge
//! pattern, and private challenge rows; `genre::fishing` supplies the rules and the content.

use spacetimedb::{reducer, table, ReducerContext, ScheduleAt, Table, TimeDuration, Timestamp};

use crate::genre::fight;
use crate::genre::fishing as rules;
use crate::module::{
    challenge, entity, entity_kind, movement_state, player, require_admin, session,
    session_member, world_config, world_level, Challenge, DEFAULT_WORLD, PHASE_LOBBY, PHASE_PLAYING,
    PHASE_RESULTS, PHASE_SHOP, SIM_MODULE,
};
use crate::sim::Vector3;

/// The genre's levels. A world runs exactly one, recorded in `fishing_world`.
///
/// GREYBOX is the test level (`tests/levels/greybox.tscn`): flat ground round the origin, and
/// three small ponds that are ENTITIES, stocked by `use_level`. The movement, remote, multiclient
/// and end-to-end suites all run on it, and select it themselves after they publish. It has no
/// bake, so there is nothing to cast into there.
///
/// LAKESIDE is the game (`game/world/lakeside.tscn`): terrain, a lake, a village. What the module
/// knows about it is its bake, `crate::level::LAKESIDE`. It is the default, so a fresh publish
/// followed by Play in the editor is the real game.
pub const LEVEL_GREYBOX: u8 = 0;
pub const LEVEL_LAKESIDE: u8 = 1;

/// `buy_upgrade` kinds, and the tracks they raise (`shared/fishing/fishing.json`, `gear`).
pub const GEAR_ROD: u8 = 0;
pub const GEAR_REEL: u8 = 1;
pub const GEAR_LINE: u8 = 2;

/// The challenge kind a cast opens. The first genre kind: the foundation hands it to
/// `resolve_challenge` below rather than validating it itself.
pub const KIND_FISH: u8 = rules::KIND_FISH;

/// In every cast's payload, so a client can tell a cast from another genre's challenge.
pub const FISHING_TAG: &str = "\"fishing\"";

/// `catch.hookset`.
pub const HOOKSET_PERFECT: u8 = 0;
pub const HOOKSET_GOOD: u8 = 1;
pub const HOOKSET_LATE: u8 = 2;

/// Where the greybox's pond entities sit (it spans about -10..10 on X and Z). Stocked by
/// `use_level` when a world switches to the greybox, which the multiclient suite counts.
///
/// A pond is SOLID — its stone rim is a wall (`pond_visual.gd`) — so where one sits is level
/// design: it must not stand across the lanes people run, or the movement playtests' scripted
/// routes. The third pond sat at (0, 0, 6), across both the sprint lane from spawn and the remote
/// walker's square, and the rim turned both into collisions. It is out on the open south side.
const POND: [(f32, f32, f32); 3] = [(4.0, 0.0, -4.0), (-5.0, 0.0, -2.0), (-4.0, 0.0, 12.0)];

/// `fight_show.state`: what the angler's tell ring shows (DECISIONS #170), in its own words.
pub const FIGHT_CALM: u8 = 0;
pub const FIGHT_BAND: u8 = 1;
pub const FIGHT_SWEET: u8 = 2;
pub const FIGHT_FAR: u8 = 3;
pub const FIGHT_RUNNING: u8 = 4;

/// `fishing_rival.state` (DECISIONS #169).
const RIVAL_RESTING: u8 = 0;
const RIVAL_WAITING: u8 = 1;
const RIVAL_FIGHTING: u8 = 2;
/// How often the rival is looked after.
const RIVAL_TICK_MICROS: i64 = 500_000;

// =============================================================================
// TABLES
// =============================================================================

/// Which level a world is running (`LEVEL_*`). Public: a client may want to know, and it decides
/// nothing a player could exploit by reading.
#[table(accessor = fishing_world, public)]
pub struct FishingWorld {
    #[primary_key]
    pub world_id: u32,
    pub level: u8,
}

/// Append-only record of what was landed. `owner_entity_id` rather than `entity_id` because a
/// catch is OWNED BY an entity, it is not that entity's state — which is exactly the case
/// `RowEvent`'s owner fallback exists for, so these rows route to the catcher's components.
#[table(accessor = catch, public)]
pub struct Catch {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub owner_entity_id: u64,
    #[index(btree)]
    pub session_id: u64,
    /// `shared/fishing/fishing.json` catch id.
    pub catch_key: String,
    pub kg: f32,
    /// The hook-set's quality, 0..1.
    pub quality: f32,
    /// HOOKSET_*.
    pub hookset: u8,
    /// The level bake's spot id, or "" for open water.
    pub spot: String,
    /// Heavier than the line was rated for. Pays double.
    pub deadlift: bool,
    pub coins: i64,
    pub round: u32,
    pub caught_at: Timestamp,
    /// The longest run of PERFECT pumps in the fight (what FfC's Hot Hand is built on).
    pub best_combo: u32,
    /// How long the fight took, in seconds of the fight's own clock.
    pub fight_s: f32,
    /// Landed without the line ever near its limit, from a hook-set that was not late.
    pub clean: bool,
}

/// What a player fishes with. One row per angler, created on the first upgrade; its absence
/// means tier 0 everywhere, so nothing has to seed it and a new player is never a missing row.
///
/// Rod, reel and line each change a DIFFERENT part of the game (DECISIONS #118): the rod how
/// much lake you can reach, the reel how forgiving the hook-set is, the line how heavy a catch it
/// holds before it is a deadlift.
#[table(accessor = gear, public)]
pub struct Gear {
    #[primary_key]
    pub entity_id: u64,
    pub rod_tier: u8,
    pub reel_tier: u8,
    pub line_tier: u8,
}

/// A line in the water, for everybody to see.
///
/// The cast behind it is private: its row says what is on the line and when it bites, and a
/// client that could read another player's would know the catch before it surfaced. So the one
/// fact other players need to DRAW the scene — that angler has a float at that point — is a row
/// of its own, made by `cast` and removed when the challenge closes however it closes
/// (`on_challenge_closed`). It carries nothing that decides anything.
#[table(accessor = fishing_line, public)]
pub struct FishingLine {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The level bake's spot id, or "" for open water.
    pub spot: String,
    /// Where the float sits, on the water.
    pub x: f32,
    pub z: f32,
    pub challenge_id: u64,
    pub cast_at: Timestamp,
}

/// THE ROUND'S TIME OF DAY AND WEATHER (DECISIONS #168), one row per world, rolled when a round's
/// lobby opens (and when a world gets its level) so the lobby can say what is coming. Indices into
/// `shared/fishing/fishing.json` `conditions.times` and `conditions.weather`. They change what
/// bites (`rules::roll_catch`, `rules::bite_delay`); every client draws them.
#[table(accessor = fishing_conditions, public)]
pub struct FishingConditions {
    #[primary_key]
    pub world_id: u32,
    pub round: u32,
    pub time_of_day: u8,
    pub weather: u8,
}

/// A FIGHT, COARSELY, FOR EVERYONE ELSE TO WATCH (DECISIONS #170). The fight itself is private
/// (the owner's client plays it; the module replays it at the end), so the owner reports what its
/// tell ring shows a few times a second (`show_fight`) and other clients draw the heave, the rod's
/// bend, the float dragged in. It decides nothing, so the module only bounds it.
#[table(accessor = fight_show, public)]
pub struct FightShow {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// `FIGHT_*`.
    pub state: u8,
    /// How hard the rod is loaded against the catch's band, 0..1: the heave.
    pub load: f32,
    /// Metres of line out: where the float is, from the angler toward where it was hooked.
    pub line_m: f32,
}

/// THE RIVAL ANGLER of a world the module runs (DECISIONS #169): which entity he is, what his line
/// is doing, and what is on it. Private: his catch is rolled at his cast, like a player's.
#[table(accessor = fishing_rival)]
pub struct FishingRival {
    #[primary_key]
    pub entity_id: u64,
    #[unique]
    pub world_id: u32,
    /// `RIVAL_*`.
    pub state: u8,
    /// When the next thing happens: the cast, the bite, the end of the fight.
    pub next_at: Timestamp,
    pub catch_key: String,
    pub kg: f32,
    pub spot: String,
    pub x: f32,
    pub z: f32,
    pub fight_s: f32,
    /// Casts so far: with the round's seed, what each cast is rolled from.
    pub casts: u32,
    /// The round his line went in.
    pub round: u32,
    pub fight_started: Timestamp,
}

/// Worlds whose rival an admin has benched (`set_rival`): the test suites, which count every line
/// and catch in the world, and a host who wants the lake to themselves.
#[table(accessor = rival_bench)]
pub struct RivalBench {
    #[primary_key]
    pub world_id: u32,
}

#[table(accessor = rival_schedule, scheduled(rival_tick))]
pub struct RivalSchedule {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

/// What a cast rolled: the server's truth about the line in the water. PRIVATE — no client ever
/// reads it; the owner's client gets its copy through the challenge payload. `resolve_challenge`
/// judges against this, and `on_challenge_closed` deletes it.
#[table(accessor = fishing_cast)]
pub struct FishingCast {
    #[primary_key]
    pub challenge_id: u64,
    #[unique]
    pub entity_id: u64,
    pub world_id: u32,
    pub spot: String,
    pub catch_key: String,
    pub kg: f32,
    /// Seconds after the cast that it bites.
    pub bite_s: f32,
    /// The reel's hook-set multiplier at the time of the cast.
    pub window_mult: f32,
    pub deadlift: bool,
    pub x: f32,
    pub z: f32,
    /// What the fight is replayed with, fixed at the cast so nothing bought or rolled later can
    /// change a fight already on the line: its random stream, how far out it was hooked (whole
    /// centimetres, so both sides compute the same f64 from it), the gear, and the round.
    pub fight_seed: u32,
    pub range_cm: u32,
    pub rod_tier: u8,
    pub reel_tier: u8,
    pub line_tier: u8,
    pub session_id: u64,
    pub round: u32,
}

/// How fished-out a named spot is. SERVER STATE: every angler draws from the same stock, so a
/// spot two players have been working all round bites slower for a third. Richness regrows from
/// `updated_at`, lazily, whenever it is read. No row means untouched: 1.0.
#[table(accessor = fishing_spot, public)]
pub struct FishingSpot {
    /// "<level>:<spot id>".
    #[primary_key]
    pub key: String,
    pub richness: f32,
    pub updated_at: Timestamp,
}

// =============================================================================
// HELPERS
// =============================================================================

/// This angler's gear, or the starting kit.
fn gear_of(ctx: &ReducerContext, entity_id: u64) -> Gear {
    ctx.db.gear().entity_id().find(entity_id).unwrap_or(Gear {
        entity_id,
        rod_tier: 0,
        reel_tier: 0,
        line_tier: 0,
    })
}

/// The level a world runs: the foundation's `world_level` (DECISIONS #175), else what fishing
/// recorded before there was one (a database published earlier), else the greybox, which is what
/// every world was before there were levels.
pub fn level_of(ctx: &ReducerContext, world_id: u32) -> u8 {
    if ctx.db.world_level().world_id().find(world_id).is_some() {
        return crate::module::world_level_of(ctx, world_id);
    }
    ctx.db
        .fishing_world()
        .world_id()
        .find(world_id)
        .map(|w| w.level)
        .unwrap_or(LEVEL_GREYBOX)
}

/// A level's bake, by its number: any level baked into `shared/world/` (the greybox has none).
fn bake_of(level: u8) -> Option<&'static crate::level::LevelBake> {
    crate::level::by_id(level)
}

fn spot_key(level: &str, spot: &str) -> String {
    format!("{level}:{spot}")
}

fn seconds_since(ctx: &ReducerContext, then: Timestamp) -> f32 {
    (ctx.timestamp.to_micros_since_unix_epoch() - then.to_micros_since_unix_epoch()).max(0) as f32
        / 1_000_000.0
}

/// A spot's richness now, regrown since it was last written.
fn richness_of(ctx: &ReducerContext, key: &str) -> f32 {
    match ctx.db.fishing_spot().key().find(key.to_string()) {
        Some(s) => (s.richness + rules::REGEN_PER_SECOND * seconds_since(ctx, s.updated_at)).min(1.0),
        None => 1.0,
    }
}

/// A catch came out of a spot.
fn deplete(ctx: &ReducerContext, key: &str) {
    let r = (richness_of(ctx, key) - rules::DEPLETION_PER_CATCH).max(rules::RICHNESS_FLOOR);
    let row = FishingSpot { key: key.to_string(), richness: r, updated_at: ctx.timestamp };
    if ctx.db.fishing_spot().key().find(key.to_string()).is_some() {
        ctx.db.fishing_spot().key().update(row);
    } else {
        ctx.db.fishing_spot().insert(row);
    }
}

/// A world's conditions this round (the first time of day and weather before any are rolled).
pub fn conditions_of(ctx: &ReducerContext, world_id: u32) -> rules::Conditions {
    ctx.db
        .fishing_conditions()
        .world_id()
        .find(world_id)
        .map(|c| rules::Conditions { time: c.time_of_day, weather: c.weather })
        .unwrap_or(rules::Conditions { time: 0, weather: 0 })
}

/// Roll a round's conditions from its seed, unless they already are for this round.
fn roll_conditions(ctx: &ReducerContext, sess: &crate::module::Session) {
    let old = ctx.db.fishing_conditions().world_id().find(sess.world_id);
    if old.as_ref().map(|c| c.round == sess.round).unwrap_or(false) {
        return;
    }
    roll_conditions_now(ctx, sess);
}

/// Roll them whatever is there: a new match starts its first round at dawn even in a lobby whose
/// round was already rolled (DECISIONS #182).
fn roll_conditions_now(ctx: &ReducerContext, sess: &crate::module::Session) {
    let old = ctx.db.fishing_conditions().world_id().find(sess.world_id);
    let mut dice = rules::Dice::new(sess.seed, rules::SALT_WEATHER);
    let row = FishingConditions {
        world_id: sess.world_id,
        round: sess.round,
        // The round of the MATCH (DECISIONS #182): every match starts at dawn.
        time_of_day: rules::time_for_round(crate::module::match_round(ctx, sess)),
        weather: rules::roll_weather(&mut dice),
    };
    log::info!(
        "fishing: world {} round {}: {}, {}",
        sess.world_id,
        sess.round,
        rules::TIMES[row.time_of_day as usize].name,
        rules::WEATHERS[row.weather as usize].name
    );
    if old.is_some() {
        ctx.db.fishing_conditions().world_id().update(row);
    } else {
        ctx.db.fishing_conditions().insert(row);
    }
}

/// The session a member is in, if any.
fn session_of(ctx: &ReducerContext, entity_id: u64) -> Option<crate::module::Session> {
    ctx.db
        .session_member()
        .entity_id()
        .filter(entity_id)
        .next()
        .and_then(|m| ctx.db.session().id().find(m.session_id))
}

// =============================================================================
// LEVELS
// =============================================================================

/// Point a world at one of the genre's levels: record it, move its spawn, and stock or clear the
/// greybox's pond entities. Idempotent. The caller must be an authority for the world (the
/// publisher in `init`, an admin through `use_level`), because stocking a pond is.
fn apply_level(ctx: &ReducerContext, world_id: u32, level: u8) -> Result<(), String> {
    if level != LEVEL_GREYBOX && bake_of(level).is_none() {
        return Err(format!("use_level: unknown level {level}"));
    }
    // The foundation records it and moves the spawn; `Fishing::on_level_changed` (below) does
    // fishing's part.
    crate::module::set_world_level_internal(ctx, world_id, level)
}

/// FISHING'S PART OF A LEVEL CHANGE (DECISIONS #175): the record it keeps, the greybox's ponds, the
/// round's conditions, the rival.
fn level_changed(ctx: &ReducerContext, world_id: u32, level: u8) -> Result<(), String> {
    let row = FishingWorld { world_id, level };
    if ctx.db.fishing_world().world_id().find(world_id).is_some() {
        ctx.db.fishing_world().world_id().update(row);
    } else {
        ctx.db.fishing_world().insert(row);
    }

    // The ponds are greybox furniture. The lakeside's water is its terrain, not entities.
    let ponds: Vec<u64> = ctx
        .db
        .entity()
        .world_id()
        .filter(world_id)
        .filter(|e| e.kind == entity_kind::RESOURCE_NODE)
        .map(|e| e.entity_id)
        .collect();
    if level == LEVEL_GREYBOX {
        if ponds.is_empty() {
            for (x, y, z) in POND {
                crate::module::spawn_resource_node(ctx, world_id, Vector3 { x, y, z })?;
            }
        }
    } else {
        for id in ponds {
            crate::module::despawn_entity(ctx, id)?;
        }
    }
    if let Some(sess) = ctx.db.session().world_id().find(world_id) {
        roll_conditions(ctx, &sess);
    }
    place_rival(ctx, world_id, level)?;
    log::info!("fishing: world {world_id} is set up for level {level}");
    Ok(())
}

/// The rival stands on his level, in a world the module runs; anywhere else he is not there.
fn place_rival(ctx: &ReducerContext, world_id: u32, level: u8) -> Result<(), String> {
    let wanted = bake_of(level).map(|b| b.name == rules::RIVAL.level).unwrap_or(false)
        && ctx.db.world_config().world_id().find(world_id).map(|w| w.sim_authority == SIM_MODULE).unwrap_or(false)
        && ctx.db.rival_bench().world_id().find(world_id).is_none();
    let existing = ctx.db.fishing_rival().world_id().find(world_id);
    match (existing, wanted) {
        (Some(r), false) => {
            rival_line_in(ctx, r.entity_id);
            ctx.db.fishing_rival().entity_id().delete(r.entity_id);
            if ctx.db.entity().entity_id().find(r.entity_id).is_some() {
                crate::module::despawn_entity_internal(ctx, r.entity_id);
            }
        }
        (None, true) => {
            let [x, y, z] = rules::RIVAL.stand;
            let id = crate::module::spawn_npc_internal(
                ctx, world_id, entity_kind::NPC, Vector3::new(x, y, z), rules::RIVAL.yaw_deg.to_radians());
            if let Some(sess) = ctx.db.session().world_id().find(world_id) {
                crate::module::add_member(ctx, &sess, id)?;
            }
            ctx.db.fishing_rival().insert(FishingRival {
                entity_id: id,
                world_id,
                state: RIVAL_RESTING,
                next_at: ctx.timestamp + TimeDuration::from_micros((rules::RIVAL.rest_s.0 * 1e6) as i64),
                catch_key: String::new(),
                kg: 0.0,
                spot: String::new(),
                x: 0.0,
                z: 0.0,
                fight_s: 0.0,
                casts: 0,
                round: 0,
                fight_started: ctx.timestamp,
            });
            log::info!("fishing: {} is fishing in world {world_id} (entity {id})", rules::RIVAL.name);
        }
        _ => {}
    }
    Ok(())
}

/// Bench the rival in a world, or bring him back (DECISIONS #169). Admin only.
#[reducer]
pub fn set_rival(ctx: &ReducerContext, world_id: u32, on: bool) -> Result<(), String> {
    require_admin(ctx)?;
    if on {
        ctx.db.rival_bench().world_id().delete(world_id);
    } else if ctx.db.rival_bench().world_id().find(world_id).is_none() {
        ctx.db.rival_bench().insert(RivalBench { world_id });
    }
    place_rival(ctx, world_id, level_of(ctx, world_id))
}

/// Switch a world to one of the genre's levels. Admin only.
///
/// The test suites call this straight after they publish (`use_level 0 0`), because every one of
/// them was written against the greybox. It moves where the NEXT player appears; anyone already
/// connected stays put, so call it before clients connect.
#[reducer]
pub fn use_level(ctx: &ReducerContext, world_id: u32, level: u8) -> Result<(), String> {
    require_admin(ctx)?;
    apply_level(ctx, world_id, level)
}

// =============================================================================
// HOOKS
// =============================================================================

pub fn on_init(ctx: &ReducerContext) {
    // The default world is the game: the lakeside. `apply_level` calls reducers as ordinary
    // functions, inside `init`'s transaction, as the publisher — who `init` has already recorded
    // as admin, so their authority checks pass.
    if let Err(e) = apply_level(ctx, DEFAULT_WORLD, LEVEL_LAKESIDE) {
        log::warn!("fishing: could not set up the lakeside: {e}");
    }
    ctx.db.rival_schedule().insert(RivalSchedule {
        scheduled_id: 0,
        scheduled_at: TimeDuration::from_micros(RIVAL_TICK_MICROS).into(),
    });
    log::info!(
        "fishing: {} catches in {} categories, {} stocked spots",
        rules::CATCHES.len(),
        rules::CATEGORIES.len(),
        rules::SPOTS.len()
    );
}

/// A FOUNDATION-kind challenge validated (the generic interact's timing bar). Not a cast: a cast
/// is `KIND_FISH`, which is resolved below. Nothing to do.
pub fn on_challenge_succeeded(_ctx: &ReducerContext, _challenge: &Challenge, _quality: f32) {}

/// Judge a cast's submission and, if it set the hook, land the catch.
///
/// `result` is `[reaction]`: seconds from the bite to the press, by the client's clock. The
/// client has no way to learn the catch from this — it was rolled at the cast — and no way to
/// improve it but pressing sooner. What it could try is pressing before the bite happened, by
/// reading the bite time out of its own challenge; so the claimed timeline must fit inside the
/// server's: the bite and the reaction have to have happened by now, give or take clock skew.
///
/// `result` is `[reaction, n, (ticks, flags, crank) × n]`: the seconds from the bite to the
/// press that set the hook, then the fight's input log (`genre::fight::decode_log`). The fight
/// is REPLAYED here from the cast's own record; what the client says happened is not asked.
pub fn resolve_challenge(ctx: &ReducerContext, challenge: &Challenge, result: &[f32]) -> Option<f32> {
    if challenge.kind != KIND_FISH {
        return None;
    }
    let cast = ctx.db.fishing_cast().challenge_id().find(challenge.id)?;
    let reaction = *result.first()?;
    if !reaction.is_finite() {
        return None;
    }
    let Some(grade) = rules::grade_hookset(reaction, cast.window_mult) else {
        log::info!("fishing: entity {} missed the hook-set ({:.3} s)", cast.entity_id, reaction);
        return None;
    };
    let runs = match fight::decode_log(&result[1..]) {
        Ok(r) => r,
        Err(why) => {
            log::warn!("fishing: entity {} submitted an unreadable fight: {why}", cast.entity_id);
            return None;
        }
    };
    let Some(profile) = fight::profile(&cast.catch_key) else {
        log::warn!("fishing: '{}' has no fight profile", cast.catch_key);
        return None;
    };
    let params = fight::params_for(cast.rod_tier, cast.reel_tier, cast.line_tier, grade, cast.deadlift);
    let fought = fight::replay(params, *profile, cast.fight_seed, cast.range_cm as f64 / 100.0, &runs);
    // THE CLOCK: neither the bite nor the fight can have gone faster than time did.
    let elapsed = seconds_since(ctx, challenge.issued_at);
    let fight_s = fought.ticks as f32 / fight::TICK_HZ as f32;
    if elapsed + rules::CLOCK_SLACK_S < cast.bite_s + reaction.max(0.0) + fight_s {
        log::warn!(
            "fishing: entity {} claimed a bite at {:.2} s, a hook-set {:.2} s later and a {:.1} s fight, \
             but only {:.2} s have passed",
            cast.entity_id, cast.bite_s, reaction, fight_s, elapsed
        );
        return None;
    }
    // YOU GET TO FINISH WHAT YOU HOOKED (FfC): the bell closes the water, but a fight already on
    // the line plays out and counts — through the results, and not past them. A hold longer than
    // that is one angler freezing everyone's round, so the line is cut.
    match session_of(ctx, cast.entity_id) {
        Some(s) if s.id == cast.session_id
            && s.round == cast.round
            && (s.phase == PHASE_PLAYING || s.phase == PHASE_RESULTS) => {}
        _ => {
            log::info!("fishing: entity {}'s fight outlasted its round; the line is cut", cast.entity_id);
            return None;
        }
    }
    match fought.state {
        fight::State::Landed => {
            land(ctx, &cast, grade, &fought);
            Some(grade.quality())
        }
        fight::State::Snapped => {
            log::info!("fishing: entity {} snapped the line on '{}' after {fight_s:.1} s", cast.entity_id, cast.catch_key);
            None
        }
        fight::State::Fighting => {
            log::info!("fishing: entity {} submitted a fight that was not over after {fight_s:.1} s", cast.entity_id);
            None
        }
    }
}

/// THE BELL CLOSES THE WATER (FfC): when a round's PLAYING ends, every line in it that nothing has
/// bitten yet comes in. One that has (a hook-set or a fight under way) plays out: you finish what
/// you hooked (`resolve_challenge`). Left out, a waiting line got its bite during the results, with
/// the results panel over the hook-set (DECISIONS #161).
pub fn on_phase_changed(ctx: &ReducerContext, sess: &crate::module::Session, from: u8) {
    if sess.phase == PHASE_LOBBY {
        roll_conditions(ctx, sess);   // a new round: its time of day and weather (#168)
    }
    // A database published before the rival existed never ran `on_init` again: he arrives here.
    if ctx.db.rival_schedule().count() == 0 {
        ctx.db.rival_schedule().insert(RivalSchedule {
            scheduled_id: 0,
            scheduled_at: TimeDuration::from_micros(RIVAL_TICK_MICROS).into(),
        });
    }
    if let Err(e) = place_rival(ctx, sess.world_id, level_of(ctx, sess.world_id)) {
        log::warn!("fishing: the rival could not be placed in world {}: {e}", sess.world_id);
    }
    if from != PHASE_PLAYING || sess.phase == PHASE_PLAYING {
        return;
    }
    let casts: Vec<FishingCast> = ctx
        .db
        .fishing_cast()
        .iter()
        .filter(|c| c.session_id == sess.id && c.round == sess.round)
        .collect();
    for cast in casts {
        let Some(ch) = ctx.db.challenge().id().find(cast.challenge_id) else {
            continue;
        };
        if seconds_since(ctx, ch.issued_at) >= cast.bite_s {
            continue;   // it has bitten: the angler may be setting the hook or fighting it
        }
        log::info!("fishing: the bell brings in entity {}'s line (no bite yet)", cast.entity_id);
        ctx.db.challenge().id().delete(ch.id);
        crate::game::on_challenge_closed(ctx, &ch);
    }
}

/// A cast ended, however it ended: resolved, reeled in, expired, or gone with its angler. Clear
/// both halves of the line — the public float and the private roll.
pub fn on_challenge_closed(ctx: &ReducerContext, challenge: &Challenge) {
    if challenge.kind != KIND_FISH {
        return;
    }
    ctx.db.fishing_cast().challenge_id().delete(challenge.id);
    if let Some(line) = ctx.db.fishing_line().entity_id().find(challenge.entity_id) {
        // Only THIS challenge's line. A stale close must not reel in a newer cast.
        if line.challenge_id == challenge.id {
            ctx.db.fishing_line().entity_id().delete(challenge.entity_id);
            ctx.db.fight_show().entity_id().delete(challenge.entity_id);
        }
    }
}

/// The catch comes out: a row, coins and score, and a little less in the spot it came from.
fn land(ctx: &ReducerContext, cast: &FishingCast, grade: rules::HookSet, fought: &fight::Fight) {
    let Some(def) = rules::catch_def(&cast.catch_key) else {
        log::warn!("fishing: cast rolled '{}', which the catalog no longer has", cast.catch_key);
        return;
    };
    let quality = grade.quality();
    let coins = rules::coins_for(def, cast.kg, quality, cast.deadlift);
    // The round it was HOOKED in, which a fight finishing during the results still is.
    let (session_id, round) = (cast.session_id, cast.round);
    ctx.db.catch().insert(Catch {
        id: 0,
        owner_entity_id: cast.entity_id,
        session_id,
        catch_key: def.id.to_string(),
        kg: cast.kg,
        quality,
        hookset: match grade {
            rules::HookSet::Perfect => HOOKSET_PERFECT,
            rules::HookSet::Good => HOOKSET_GOOD,
            rules::HookSet::Late => HOOKSET_LATE,
        },
        spot: cast.spot.clone(),
        deadlift: cast.deadlift,
        coins,
        round,
        caught_at: ctx.timestamp,
        best_combo: fought.best_combo,
        fight_s: fought.ticks as f32 / fight::TICK_HZ as f32,
        clean: fought.was_clean(),
    });
    let members: Vec<_> = ctx.db.session_member().entity_id().filter(cast.entity_id).collect();
    for mut m in members {
        // Coins are progression and persist across rounds; score is the competitive number and
        // is reset when a new round starts (`advance_phases`). Same catch feeds both.
        m.coins += coins;
        m.score += coins;
        ctx.db.session_member().id().update(m);
    }
    if !cast.spot.is_empty() {
        if let Some(level) = bake_of(level_of(ctx, cast.world_id)) {
            deplete(ctx, &spot_key(level.name, &cast.spot));
        }
    }
    log::info!(
        "fishing: entity {} landed {} ({:.2} kg, {} hook-set{}) from '{}' for {} coins",
        cast.entity_id,
        def.name,
        cast.kg,
        grade.word(),
        if cast.deadlift { ", DEADLIFT" } else { "" },
        cast.spot,
        coins
    );
}

// =============================================================================
// REDUCERS
// =============================================================================

/// Cast at a point on the water. Everything about what happens next is decided here; see the top
/// of this file.
///
/// Gated to the PLAYING phase so a lobby cannot be farmed; one line at a time; the point must be
/// water the level's bake knows about, at least `MIN_RANGE_M` away and within the rod's reach of
/// where the server has the angler standing. The client's ring is a preview, not a permission.
#[reducer]
pub fn cast(ctx: &ReducerContext, target: Vector3) -> Result<(), String> {
    let p = ctx.db.player().identity().find(ctx.sender()).ok_or("cast: no player row")?;
    let me = ctx
        .db
        .movement_state()
        .entity_id()
        .find(p.entity_id)
        .ok_or("cast: you have no movement_state")?;
    if !(target.x.is_finite() && target.y.is_finite() && target.z.is_finite()) {
        return Err("cast: the target is not a point".into());
    }
    match session_of(ctx, p.entity_id) {
        Some(s) if s.phase == PHASE_PLAYING => {}
        Some(_) => return Err("cast: you can only fish during the PLAYING phase".into()),
        None => return Err("cast: you are not in a session".into()),
    }
    if ctx.db.fishing_cast().entity_id().find(p.entity_id).is_some() {
        return Err("cast: you already have a line out".into());
    }
    let bake = bake_of(level_of(ctx, me.world_id)).ok_or("cast: there is no water to fish in this level")?;

    let kit = gear_of(ctx, p.entity_id);
    let rod = rules::rod(kit.rod_tier);
    let (dx, dz) = (target.x - me.pos.x, target.z - me.pos.z);
    let range = (dx * dx + dz * dz).sqrt();
    if range < rules::MIN_RANGE_M {
        return Err(format!("cast: that is at your feet ({range:.1} m)"));
    }
    if range > rod.max_cast_m + rules::RANGE_SLACK_M {
        return Err(format!(
            "cast: {range:.0} m is further than the {} reaches ({:.0} m)",
            rod.name, rod.max_cast_m
        ));
    }
    if !bake.is_water(target.x, target.z) {
        return Err("cast: that is dry land, or too shallow for a float".into());
    }

    let spot_id: &str = bake.spot_at(target.x, target.z).map(|s| s.id).unwrap_or("");
    let loot = rules::spot_loot(spot_id);
    let richness = if spot_id.is_empty() { 1.0 } else { richness_of(ctx, &spot_key(bake.name, spot_id)) };
    let others = ctx
        .db
        .fishing_line()
        .world_id()
        .filter(me.world_id)
        .filter(|l| l.spot == spot_id && l.entity_id != p.entity_id)
        .count() as u32;

    // Issue first: the challenge's seed is what everything below is rolled from, so the roll can
    // be re-run from the row.
    let ttl = (rules::LINE_LIFE_S * 1_000_000.0) as i64;
    let cid = crate::module::issue_genre_challenge(ctx, p.entity_id, KIND_FISH, String::new(), ttl)?;
    let mut ch = ctx.db.challenge().id().find(cid).ok_or("cast: the challenge vanished")?;
    let cond = conditions_of(ctx, me.world_id);
    let mut dice = rules::Dice::new(ch.seed, rules::SALT_CATCH);
    let def = rules::roll_catch(&mut dice, loot, &cond.tags());
    let kg = rules::roll_kg(&mut dice, def);
    let bite = rules::bite_delay(
        rules::Dice::new(ch.seed, rules::SALT_BITE).unit(), loot, richness, others, cond.bite_speed());
    let window_mult = rules::reel(kit.reel_tier).hookset_window_mult;
    let deadlift = kg > rules::line(kit.line_tier).max_load_kg;
    let fight_seed = rules::Dice::new(ch.seed, rules::SALT_FIGHT).next_u32();
    let range_cm = (range * 100.0).round() as u32;
    let (session_id, round) = session_of(ctx, p.entity_id).map(|s| (s.id, s.round)).unwrap_or((0, 0));

    // The owner's copy, for playing the bite and the fight honestly. Private by RLS. The fight
    // needs exactly what the replay will use: its seed, the range, the gear at this moment.
    ch.payload = format!(
        "{{\"kind\":{FISHING_TAG},\"spot\":\"{spot_id}\",\"catch\":\"{}\",\"kg\":{kg},\"bite\":{bite},\
         \"window_mult\":{window_mult},\"deadlift\":{deadlift},\"x\":{},\"z\":{},\"range\":{range},\
         \"range_cm\":{range_cm},\"fight_seed\":{fight_seed},\"rod\":{},\"reel\":{},\"line\":{}}}",
        def.id, target.x, target.z, kit.rod_tier, kit.reel_tier, kit.line_tier
    );
    ctx.db.challenge().id().update(ch);
    ctx.db.fishing_cast().insert(FishingCast {
        challenge_id: cid,
        entity_id: p.entity_id,
        world_id: me.world_id,
        spot: spot_id.to_string(),
        catch_key: def.id.to_string(),
        kg,
        bite_s: bite,
        window_mult,
        deadlift,
        x: target.x,
        z: target.z,
        fight_seed,
        range_cm,
        rod_tier: kit.rod_tier,
        reel_tier: kit.reel_tier,
        line_tier: kit.line_tier,
        session_id,
        round,
    });
    // The public half: everyone may now draw this angler's float at that point.
    let line = FishingLine {
        entity_id: p.entity_id,
        world_id: me.world_id,
        spot: spot_id.to_string(),
        x: target.x,
        z: target.z,
        challenge_id: cid,
        cast_at: ctx.timestamp,
    };
    if ctx.db.fishing_line().entity_id().find(p.entity_id).is_some() {
        ctx.db.fishing_line().entity_id().update(line);
    } else {
        ctx.db.fishing_line().insert(line);
    }
    log::info!(
        "fishing: entity {} cast {range:.1} m into '{spot_id}' (richness {richness:.2}, {others} others): bites in {bite:.1} s",
        p.entity_id
    );
    Ok(())
}

/// Report what your fight looks like, for the others to watch (DECISIONS #170). Only while you have
/// a line out; bounded, never judged: the fight is replayed from its inputs at the end.
#[reducer]
pub fn show_fight(ctx: &ReducerContext, state: u8, load: f32, line_m: f32) -> Result<(), String> {
    let p = ctx.db.player().identity().find(ctx.sender()).ok_or("show_fight: no player row")?;
    let cast = ctx.db.fishing_cast().entity_id().find(p.entity_id).ok_or("show_fight: you have no line out")?;
    if state > FIGHT_RUNNING {
        return Err(format!("show_fight: {state} is not a fight state (0..{FIGHT_RUNNING})"));
    }
    if !(load.is_finite() && line_m.is_finite()) {
        return Err("show_fight: not numbers".into());
    }
    let row = FightShow {
        entity_id: p.entity_id,
        world_id: cast.world_id,
        state,
        load: load.clamp(0.0, 1.0),
        line_m: line_m.clamp(0.0, cast.range_cm as f32 / 100.0 + rules::RANGE_SLACK_M),
    };
    if ctx.db.fight_show().entity_id().find(p.entity_id).is_some() {
        ctx.db.fight_show().entity_id().update(row);
    } else {
        ctx.db.fight_show().insert(row);
    }
    Ok(())
}

/// THE RIVAL, looked after twice a second (DECISIONS #169): rest, cast into one of his spots, wait
/// for the bite he rolled, fight it for a while (showing it, like a player), and land it or lose
/// it. He fishes only while a round plays, the bell brings his unbitten line in like anyone's, and
/// he finishes a fight he hooked.
#[reducer]
pub fn rival_tick(ctx: &ReducerContext, _sched: RivalSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("rival_tick: scheduler only".into());
    }
    let rivals: Vec<FishingRival> = ctx.db.fishing_rival().iter().collect();
    for mut r in rivals {
        if ctx.db.entity().entity_id().find(r.entity_id).is_none() {
            rival_line_in(ctx, r.entity_id);
            ctx.db.fishing_rival().entity_id().delete(r.entity_id);
            continue;
        }
        let Some(sess) = ctx.db.session().world_id().find(r.world_id) else {
            continue;
        };
        let now = ctx.timestamp;
        match r.state {
            RIVAL_RESTING => {
                if sess.phase != PHASE_PLAYING || now < r.next_at {
                    continue;
                }
                rival_cast(ctx, &mut r, &sess);
            }
            RIVAL_WAITING => {
                if sess.phase != PHASE_PLAYING || sess.round != r.round {
                    rival_rest(ctx, &mut r);   // the bell: nothing has bitten
                } else if now >= r.next_at {
                    r.state = RIVAL_FIGHTING;
                    r.fight_started = now;
                    r.next_at = now + TimeDuration::from_micros((r.fight_s * 1e6) as i64);
                    rival_show(ctx, &r);
                }
            }
            _ => {
                let playable = sess.round == r.round && (sess.phase == PHASE_PLAYING || sess.phase == PHASE_RESULTS);
                if !playable || now >= r.next_at {
                    if playable {
                        rival_land(ctx, &r, &sess);
                    }
                    rival_rest(ctx, &mut r);
                } else {
                    rival_show(ctx, &r);
                }
            }
        }
        ctx.db.fishing_rival().entity_id().update(r);
    }
    Ok(())
}

/// The rival casts: a point in one of his spots, in his rod's reach, rolled like a player's cast.
fn rival_cast(ctx: &ReducerContext, r: &mut FishingRival, sess: &crate::module::Session) {
    let Some(bake) = bake_of(level_of(ctx, r.world_id)) else {
        return;
    };
    let def_rival = &rules::RIVAL;
    r.casts = r.casts.wrapping_add(1);
    let mut dice = rules::Dice::new(sess.seed ^ ((r.casts as u64) << 20), rules::SALT_RIVAL);
    let spot_id = def_rival.spots[(dice.next_u32() as usize) % def_rival.spots.len().max(1)];
    let Some(spot) = bake.spots.iter().find(|s| s.id == spot_id) else {
        return;
    };
    let reach = rules::rod(def_rival.rod_tier).max_cast_m;
    let [sx, _, sz] = def_rival.stand;
    let (mut x, mut z) = (spot.x as f32, spot.z as f32);
    for _ in 0..12 {
        let a = dice.unit() * std::f32::consts::TAU;
        let d = dice.unit() * spot.radius as f32 * 0.7;
        let (cx, cz) = (spot.x as f32 + a.cos() * d, spot.z as f32 + a.sin() * d);
        let range = ((cx - sx).powi(2) + (cz - sz).powi(2)).sqrt();
        if bake.is_water(cx, cz) && range <= reach && range >= rules::MIN_RANGE_M {
            (x, z) = (cx, cz);
            break;
        }
    }
    let loot = rules::spot_loot(spot_id);
    let cond = conditions_of(ctx, r.world_id);
    let def = rules::roll_catch(&mut dice, loot, &cond.tags());
    let kg = rules::roll_kg(&mut dice, def);
    let others = ctx.db.fishing_line().world_id().filter(r.world_id)
        .filter(|l| l.spot == spot_id && l.entity_id != r.entity_id).count() as u32;
    let richness = richness_of(ctx, &spot_key(bake.name, spot_id));
    let bite = rules::bite_delay(dice.unit(), loot, richness, others, cond.bite_speed());
    let (lo, hi) = def_rival.fight_s;
    r.state = RIVAL_WAITING;
    r.catch_key = def.id.to_string();
    r.kg = kg;
    r.spot = spot_id.to_string();
    r.x = x;
    r.z = z;
    r.fight_s = (def_rival.fight_s_per_kg_sqrt * kg.sqrt()).clamp(lo, hi);
    r.round = sess.round;
    r.next_at = ctx.timestamp + TimeDuration::from_micros((bite * 1e6) as i64);
    let line = FishingLine {
        entity_id: r.entity_id,
        world_id: r.world_id,
        spot: spot_id.to_string(),
        x,
        z,
        challenge_id: 0,
        cast_at: ctx.timestamp,
    };
    if ctx.db.fishing_line().entity_id().find(r.entity_id).is_some() {
        ctx.db.fishing_line().entity_id().update(line);
    } else {
        ctx.db.fishing_line().insert(line);
    }
}

/// His fight as a watcher sees it: the load swells and eases, now and then it runs, and the line
/// comes in as the fight goes on.
fn rival_show(ctx: &ReducerContext, r: &FishingRival) {
    let t = seconds_since(ctx, r.fight_started);
    let done = (t / r.fight_s.max(0.1)).clamp(0.0, 1.0);
    let wave = (t * 1.3).sin();
    let running = (t * 0.37).sin() > 0.85;
    let load = if running { 0.4 } else { (0.55 + 0.4 * wave).clamp(0.0, 1.0) };
    let state = if running {
        FIGHT_RUNNING
    } else if load > 0.9 {
        FIGHT_FAR
    } else if load > 0.62 {
        FIGHT_SWEET
    } else if load > 0.35 {
        FIGHT_BAND
    } else {
        FIGHT_CALM
    };
    let [sx, _, sz] = rules::RIVAL.stand;
    let range = ((r.x - sx).powi(2) + (r.z - sz).powi(2)).sqrt();
    let row = FightShow { entity_id: r.entity_id, world_id: r.world_id, state, load, line_m: range * (1.0 - 0.85 * done) };
    if ctx.db.fight_show().entity_id().find(r.entity_id).is_some() {
        ctx.db.fight_show().entity_id().update(row);
    } else {
        ctx.db.fight_show().insert(row);
    }
}

/// The end of his fight: landed, by his catch's rarity, or lost.
fn rival_land(ctx: &ReducerContext, r: &FishingRival, sess: &crate::module::Session) {
    let Some(def) = rules::catch_def(&r.catch_key) else {
        return;
    };
    let rarity = rules::CATEGORIES.get(def.category).map(|c| c.rarity as usize).unwrap_or(0);
    let chances = rules::RIVAL.land_chance;
    let chance = chances.get(rarity).or(chances.last()).copied().unwrap_or(0.5);
    let mut dice = rules::Dice::new(sess.seed ^ ((r.casts as u64) << 20), rules::SALT_RIVAL ^ 0xF1);
    if dice.unit() >= chance {
        log::info!("fishing: {} lost a {} after {:.0} s", rules::RIVAL.name, def.name, r.fight_s);
        return;
    }
    let quality = 0.7;
    let coins = rules::coins_for(def, r.kg, quality, false);
    ctx.db.catch().insert(Catch {
        id: 0,
        owner_entity_id: r.entity_id,
        session_id: sess.id,
        catch_key: def.id.to_string(),
        kg: r.kg,
        quality,
        hookset: HOOKSET_GOOD,
        spot: r.spot.clone(),
        deadlift: false,
        coins,
        round: r.round,
        caught_at: ctx.timestamp,
        best_combo: 0,
        fight_s: r.fight_s,
        clean: true,
    });
    let members: Vec<_> = ctx.db.session_member().entity_id().filter(r.entity_id).collect();
    for mut m in members {
        m.coins += coins;
        m.score += coins;
        ctx.db.session_member().id().update(m);
    }
    if let Some(level) = bake_of(level_of(ctx, r.world_id)) {
        deplete(ctx, &spot_key(level.name, &r.spot));
    }
    log::info!("fishing: {} landed {} ({:.2} kg) for {coins} coins", rules::RIVAL.name, def.name, r.kg);
}

/// His line out of the water, and a rest before the next cast.
fn rival_rest(ctx: &ReducerContext, r: &mut FishingRival) {
    rival_line_in(ctx, r.entity_id);
    let (lo, hi) = rules::RIVAL.rest_s;
    let mut dice = rules::Dice::new(r.casts as u64 ^ 0x5EED, rules::SALT_RIVAL);
    r.state = RIVAL_RESTING;
    r.catch_key.clear();
    r.next_at = ctx.timestamp + TimeDuration::from_micros(((lo + (hi - lo) * dice.unit()) * 1e6) as i64);
}

fn rival_line_in(ctx: &ReducerContext, entity_id: u64) {
    ctx.db.fishing_line().entity_id().delete(entity_id);
    ctx.db.fight_show().entity_id().delete(entity_id);
}

/// Take the line out of the water with nothing on it — pressing before the bite, or walking
/// away. No penalty: the wait is downtime, not a test.
#[reducer]
pub fn reel_in(ctx: &ReducerContext) -> Result<(), String> {
    let p = ctx.db.player().identity().find(ctx.sender()).ok_or("reel_in: no player row")?;
    let cast = ctx
        .db
        .fishing_cast()
        .entity_id()
        .find(p.entity_id)
        .ok_or("reel_in: you have no line out")?;
    match ctx.db.challenge().id().find(cast.challenge_id) {
        Some(ch) => {
            ctx.db.challenge().id().delete(ch.id);
            crate::game::on_challenge_closed(ctx, &ch);
        }
        None => {
            // The challenge went some other way and left its cast behind: clear the cast.
            ctx.db.fishing_cast().challenge_id().delete(cast.challenge_id);
            ctx.db.fishing_line().entity_id().delete(p.entity_id);
        }
    }
    Ok(())
}

/// Buy the next tier of one track (GEAR_ROD, GEAR_REEL, GEAR_LINE), with coins earned by fishing.
///
/// SHOP PHASE ONLY. Upgrading mid-round would change the odds of a cast already in the water,
/// and the only place the spend is legible is between rounds: you see the scores, then you spend.
/// The phase check is the server's, not the UI's — a client that shows the shop at the wrong time
/// gets an Err, which `purchase_refused` surfaces.
///
/// Coins are spent from every session membership this angler has, which today is exactly one.
#[reducer]
pub fn buy_upgrade(ctx: &ReducerContext, kind: u8) -> Result<(), String> {
    if kind > GEAR_LINE {
        return Err(format!("buy_upgrade: unknown gear kind {kind}"));
    }
    let p = ctx.db.player().identity().find(ctx.sender()).ok_or("buy_upgrade: no player row")?;
    let member = ctx
        .db
        .session_member()
        .entity_id()
        .filter(p.entity_id)
        .next()
        .ok_or("buy_upgrade: you are not in a session")?;
    let sess = ctx
        .db
        .session()
        .id()
        .find(member.session_id)
        .ok_or("buy_upgrade: your session is gone")?;
    if sess.phase != PHASE_SHOP {
        return Err("buy_upgrade: the shop is only open between rounds".into());
    }

    let mut kit = gear_of(ctx, p.entity_id);
    let tier = match kind {
        GEAR_ROD => kit.rod_tier,
        GEAR_REEL => kit.reel_tier,
        _ => kit.line_tier,
    };
    if tier >= rules::max_tier() {
        return Err("buy_upgrade: already at the top tier".into());
    }
    let next = tier + 1;
    let (cost, name) = match kind {
        GEAR_ROD => (rules::rod(next).cost, rules::rod(next).name),
        GEAR_REEL => (rules::reel(next).cost, rules::reel(next).name),
        _ => (rules::line(next).cost, rules::line(next).name),
    };
    if member.coins < cost {
        return Err(format!("buy_upgrade: the {name} costs {cost} coins, you have {}", member.coins));
    }
    match kind {
        GEAR_ROD => kit.rod_tier = next,
        GEAR_REEL => kit.reel_tier = next,
        _ => kit.line_tier = next,
    }
    if ctx.db.gear().entity_id().find(p.entity_id).is_some() {
        ctx.db.gear().entity_id().update(kit);
    } else {
        ctx.db.gear().insert(kit);
    }
    let mut m = member;
    m.coins -= cost;
    ctx.db.session_member().id().update(m);
    log::info!("fishing: entity {} bought the {name} (track {kind}, tier {next}) for {cost} coins", p.entity_id);
    Ok(())
}

// =============================================================================
// THE GENRE (DECISIONS #173)
// =============================================================================

/// Fishing, as the foundation's hooks reach it.
pub struct Fishing;
pub static FISHING: Fishing = Fishing;

impl crate::game::Genre for Fishing {
    fn claims(&self) -> &'static crate::genre::Claims {
        &rules::CLAIMS
    }
    fn on_init(&self, ctx: &ReducerContext) {
        on_init(ctx);
    }
    fn on_challenge_succeeded(&self, ctx: &ReducerContext, challenge: &Challenge, quality: f32) {
        on_challenge_succeeded(ctx, challenge, quality);
    }
    fn on_challenge_closed(&self, ctx: &ReducerContext, challenge: &Challenge) {
        on_challenge_closed(ctx, challenge);
    }
    fn resolve_challenge(&self, ctx: &ReducerContext, challenge: &Challenge, result: &[f32]) -> Option<f32> {
        resolve_challenge(ctx, challenge, result)
    }
    fn on_phase_changed(&self, ctx: &ReducerContext, sess: &crate::module::Session, from: u8) {
        on_phase_changed(ctx, sess, from);
    }
    fn on_level_changed(&self, ctx: &ReducerContext, world_id: u32, level_id: u8) {
        if let Err(e) = level_changed(ctx, world_id, level_id) {
            log::warn!("fishing: setting up level {level_id} in world {world_id}: {e}");
        }
    }
    fn on_match_began(&self, ctx: &ReducerContext, sess: &crate::module::Session) {
        roll_conditions_now(ctx, sess);
    }
}
