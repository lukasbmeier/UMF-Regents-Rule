//! BODIES THE REFEREE MOVES (docs/FOUNDATION_SYSTEMS.md milestone 13, DECISIONS #246): a thrown thing
//! is an entity (kind `entity_kind::BODY`) with a `movement_state` row like anyone's, written by the
//! world's referee as it flies it, and a `body_state` side row (which body it is, whose, its turn and
//! spin, at rest). What each body is (who may throw it, how hard...) is content (`crate::body`).
//!
//! A player throws with `launch_body`: the throw they made, bounded (rule 13). A genre launches its own
//! with `launch_body_internal` (a disc from the lie). Nothing moves without a referee, so neither is
//! taken while the world has none. The module never simulates a body (`tick_world_module` passes them
//! over); the referee writes them (`write_body_batch`) and says what they hit (`report_body_contacts`).

use super::*;
use crate::body::{self, Throw};

/// How long a contact's row stays (its sound is played as it arrives, as a noise's).
pub const BODY_CONTACT_TTL_MICROS: i64 = 5_000_000;
/// Most contacts one report may carry, and most writes one batch (a world's worth).
const MAX_CONTACTS: usize = 64;
const MAX_BODY_WRITES: usize = 256;

/// A BODY'S OWN ROW, beside its `movement_state`. Public per world: every client draws its turn.
#[table(accessor = body_state, public)]
pub struct BodyState {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The cell it is in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
    /// Which body it is (`BodyDef.id`).
    pub def_id: u32,
    /// Who threw it (an entity; 0: the world, a genre's rule).
    #[index(btree)]
    pub owner_id: u64,
    /// The thrower's own number for this throw, so its game knows the body it is already flying.
    pub launch_id: u32,
    pub launched_at: Timestamp,
    /// Its turn, as a rotation vector (axis times angle, radians).
    pub rot: Vector3,
    /// Its spin (angular velocity, rad/s).
    pub spin: Vector3,
    /// Settled: nothing moves it until something does.
    pub at_rest: bool,
    /// Physics frames since it was launched (60 a second): the referee's own clock for it, also its
    /// movement row's `last_processed_seq`.
    pub frames: u32,
}

/// WHAT A BODY HIT, as it hit it (a tree, a person, another body, the ground), faster than its def's
/// contact speed. Everyone in its world gets it as it is made; gone after a few seconds.
#[table(accessor = body_contact, public)]
pub struct BodyContact {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The cell it is in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
    pub body_id: u64,
    /// What it hit: an entity (a person, another body), or 0 for the level.
    pub other_id: u64,
    pub pos: Vector3,
    pub normal: Vector3,
    /// How fast it was going into it, m/s.
    pub speed: f32,
    pub at: Timestamp,
}

/// One body as the referee has it now: its `movement_state` and `body_state` in one.
#[derive(SpacetimeType, Clone, Copy, Debug)]
pub struct BodyWrite {
    pub entity_id: u64,
    pub pos: Vector3,
    pub vel: Vector3,
    pub rot: Vector3,
    pub spin: Vector3,
    pub at_rest: bool,
    pub frames: u32,
}

/// One contact as the referee saw it.
#[derive(SpacetimeType, Clone, Copy, Debug)]
pub struct BodyContactWrite {
    pub body_id: u64,
    pub other_id: u64,
    pub pos: Vector3,
    pub normal: Vector3,
    pub speed: f32,
}

/// Whether `entity_id` is a body (the module passes them over when it ticks movement).
pub fn is_body(ctx: &ReducerContext, entity_id: u64) -> bool {
    ctx.db.body_state().entity_id().find(entity_id).is_some()
}

/// A PLAYER'S THROW (`launch_id`: the thrower's own number for it). Refused: a body nobody may throw
/// themselves, or not them; faster, spun harder, or from further than the body allows (its reach, plus
/// the thrower's sprint for the time a row takes: `foundation.body_launch_lag_s`); while they cannot
/// act; with no referee to fly it; over the `launch_body` rate; when the genre says no (`may_launch`).
#[reducer]
pub fn launch_body(ctx: &ReducerContext, def_id: u32, launch_id: u32, origin: Vector3, vel: Vector3, rot: Vector3, spin: Vector3) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("launch_body: you have no player")?;
    let me = player.entity_id;
    spend_rate(ctx, me, "launch_body")?;
    let seed = body::find(def_id).ok_or(format!("launch_body: there is no body {def_id}"))?;
    let ent = ctx.db.entity().entity_id().find(me).ok_or("launch_body: you have no entity")?;
    let at = ctx.db.movement_state().entity_id().find(me).ok_or("launch_body: you are nowhere")?;
    require_can_act(ctx, me, "launch_body")?;
    let lag = hot_number(ctx, crate::hot::foundation::BODY_LAUNCH_LAG_S) as f32;
    let slack = crate::content::movement_limits(ent.kind).sprint * lag;
    body::check_throw(seed, ent.kind, at.pos, slack, &Throw { origin, vel, spin })?;
    if !finite3(rot) {
        return Err("launch_body: a throw must be finite".into());
    }
    if !referee_online(ctx, ent.world_id) {
        return Err("launch_body: no referee is running this world, so nothing thrown would fly".into());
    }
    crate::game::may_launch(ctx, me, def_id)?;
    launch_body_internal(ctx, ent.world_id, def_id, me, launch_id, origin, vel, rot, spin);
    Ok(())
}

fn finite3(v: Vector3) -> bool {
    v.x.is_finite() && v.y.is_finite() && v.z.is_finite()
}

/// A BODY INTO THE WORLD, for code that has already decided it may (a player's throw above; a genre's
/// own: a disc from the lie, its speed from the disc). Over its def's `max_per_owner`, the owner's oldest
/// of that body go first. Returns its entity id. The genre hears it (`on_body_launched`).
pub fn launch_body_internal(ctx: &ReducerContext, world_id: u32, def_id: u32, owner_id: u64, launch_id: u32,
        origin: Vector3, vel: Vector3, rot: Vector3, spin: Vector3) -> u64 {
    if owner_id != 0 {
        let max = body::find(def_id).map(|s| s.max_per_owner).unwrap_or(0);
        let mine: Vec<(u64, i64)> = ctx.db.body_state().owner_id().filter(owner_id)
            .filter(|b| b.def_id == def_id)
            .map(|b| (b.entity_id, b.launched_at.to_micros_since_unix_epoch()))
            .collect();
        for old in body::over_limit(mine, max) {
            despawn_entity_internal(ctx, old);
        }
    }
    let ent = ctx.db.entity().insert(Entity {
        entity_id: 0,
        world_id,
        chunk: 0,
        kind: entity_kind::BODY,
        owner: ctx.sender(),
        spawned_at: ctx.timestamp,
    });
    insert_movement(ctx, MovementStateRow {
        entity_id: ent.entity_id,
        world_id,
        chunk: 0,
        pos: origin,
        vel,
        yaw: 0.0,
        grounded: false,
        move_state: 0,
        last_processed_seq: 0,
        server_tick: current_tick(ctx, world_id),
        server_ts: ctx.timestamp,
        teleport_flag: true,
        correction_epoch: 0,
    });
    ctx.db.body_state().insert(BodyState {
        entity_id: ent.entity_id,
        world_id,
        chunk: chunk_of_entity(ctx, ent.entity_id),
        def_id,
        owner_id,
        launch_id,
        launched_at: ctx.timestamp,
        rot,
        spin,
        at_rest: false,
        frames: 0,
    });
    crate::game::on_body_launched(ctx, ent.entity_id, owner_id, def_id);
    ent.entity_id
}

/// THE REFEREE'S BODIES, as it flies them: one call a server tick for a world. A write for a body that
/// is gone, or in another world, is passed over. A body coming to rest is told to the genre once.
#[reducer]
pub fn write_body_batch(ctx: &ReducerContext, world_id: u32, writes: Vec<BodyWrite>) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    if writes.len() > MAX_BODY_WRITES {
        return Err(format!("write_body_batch: {} writes; at most {MAX_BODY_WRITES}", writes.len()));
    }
    let tick = current_tick(ctx, world_id);
    for w in writes {
        let (Some(b), Some(m)) = (ctx.db.body_state().entity_id().find(w.entity_id),
            ctx.db.movement_state().entity_id().find(w.entity_id)) else { continue };
        if b.world_id != world_id || m.world_id != world_id {
            continue;
        }
        if !(finite3(w.pos) && finite3(w.vel) && finite3(w.rot) && finite3(w.spin)) {
            continue;
        }
        let came_to_rest = w.at_rest && !b.at_rest;
        // The body's own row first: written after the move, its old copy would put back its old cell.
        ctx.db.body_state().entity_id().update(BodyState { rot: w.rot, spin: w.spin, at_rest: w.at_rest, frames: w.frames, ..b });
        write_movement(ctx, MovementStateRow {
            pos: w.pos,
            vel: w.vel,
            grounded: w.at_rest,
            last_processed_seq: w.frames,
            server_tick: tick,
            server_ts: ctx.timestamp,
            teleport_flag: false,
            ..m
        });
        if came_to_rest {
            crate::game::on_body_rest(ctx, w.entity_id);
        }
    }
    Ok(())
}

/// WHAT THE REFEREE'S BODIES HIT: a row each (everyone in the world hears it), and the genre is told
/// (`on_body_contact`: a disc in the chains, a tree kicked, a person hit). A contact for a body that is
/// gone, or in another world, is passed over.
#[reducer]
pub fn report_body_contacts(ctx: &ReducerContext, world_id: u32, contacts: Vec<BodyContactWrite>) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    if contacts.len() > MAX_CONTACTS {
        return Err(format!("report_body_contacts: {} contacts; at most {MAX_CONTACTS}", contacts.len()));
    }
    for c in contacts {
        let Some(b) = ctx.db.body_state().entity_id().find(c.body_id) else { continue };
        if b.world_id != world_id || !finite3(c.pos) || !finite3(c.normal) || !c.speed.is_finite() {
            continue;
        }
        ctx.db.body_contact().insert(BodyContact {
            id: 0,
            world_id,
            chunk: crate::cell::chunk_of(c.pos),
            body_id: c.body_id,
            other_id: c.other_id,
            pos: c.pos,
            normal: c.normal,
            speed: c.speed.max(0.0),
            at: ctx.timestamp,
        });
        crate::game::on_body_contact(ctx, c.body_id, c.other_id, c.speed, c.pos);
    }
    Ok(())
}

/// A body's own rows, as it goes (`despawn_entity_internal`).
pub(crate) fn forget_body(ctx: &ReducerContext, entity_id: u64) {
    ctx.db.body_state().entity_id().delete(entity_id);
}

/// Contacts older than `BODY_CONTACT_TTL_MICROS`, and bodies past their lifetime (with the action
/// events' prune, once a second).
pub(crate) fn prune_bodies(ctx: &ReducerContext) {
    let cutoff = ctx.timestamp - TimeDuration::from_micros(BODY_CONTACT_TTL_MICROS);
    let stale: Vec<u64> = ctx.db.body_contact().iter().filter(|c| c.at < cutoff).map(|c| c.id).collect();
    for id in stale {
        ctx.db.body_contact().id().delete(id);
    }
    let now = ctx.timestamp.to_micros_since_unix_epoch();
    let expired: Vec<u64> = ctx.db.body_state().iter()
        .filter(|b| body::find(b.def_id).is_some_and(|s| body::expired(s, b.launched_at.to_micros_since_unix_epoch(), now)))
        .map(|b| b.entity_id)
        .collect();
    for id in expired {
        despawn_entity_internal(ctx, id);
    }
}
