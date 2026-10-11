//! HOLD TO INTERACT (docs/FOUNDATION_SYSTEMS.md milestone 3, DECISIONS #209): who is holding what,
//! and how far along each thing being held is. What a hold IS (which press starts it, how long it
//! takes with how many, what stops it, what it does when done) is content (`crate::hold`); a genre
//! adds to it through hooks (`game::may_hold`, `hold_rate`, `on_hold_completed`, `on_hold_left`).
//! `mod.rs` says why the module is wasm-only.
//!
//! PROGRESS IS A LINE, NOT A COUNTER: a row says how far along it was at `at` and how fast it is
//! going, so every client draws the bar moving without a row per tick, and the row is written only
//! when the rate changes (someone joins or lets go, a genre's rate changes). The 10 Hz tick checks
//! the doers (in reach, able to act, still where they started) and finishes what is done.

use super::*;
use crate::hold::{self, HoldSeed, DONE, GOING};

/// ONE THING BEING HELD (DECISIONS #209): a target and the hold being done to it. Public and per
/// world: every client draws the bar (a half-laid nest shows to everyone). Keyed by its own id; the
/// target is `entity_id`, so a client hands it to the target's components.
#[table(accessor = hold_progress, public)]
pub struct HoldProgress {
    #[primary_key]
    #[auto_inc]
    pub hold_id: u64,
    /// The target.
    #[index(btree)]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The hold's content id (`HoldDef.id`).
    pub hold: u32,
    /// How far along it was at `at` (0..1).
    pub progress: f32,
    /// How fast it is going from `at`: a share of the whole per second (negative: undoing).
    pub rate: f32,
    pub at: Timestamp,
    /// How many are doing it.
    pub doers: u8,
    /// `hold::GOING`, or `hold::DONE` (for one tick, so every client sees it finish, then gone).
    pub state: u8,
}

/// ONE DOER (DECISIONS #209): an entity holding something. One thing at a time; keyed by the doer
/// (`entity_id`), so a client hands it to the doer's components (its pose). Public and per world.
#[table(accessor = hold_member, public)]
pub struct HoldMember {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    #[index(btree)]
    pub hold_id: u64,
    pub target_id: u64,
    pub hold: u32,
    pub since: Timestamp,
    /// Where it stood when it began (a hold `stopped_by_moving_m` lets go of one who wanders).
    pub from: Vector3,
}

/// The 10 Hz tick, while anything is being held (no rows: no tick). Private.
#[table(accessor = hold_tick, scheduled(tick_holds))]
pub struct HoldTick {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

const HOLD_TICK_MICROS: i64 = 100_000;

fn secs_since(ctx: &ReducerContext, at: Timestamp) -> f64 {
    (ctx.timestamp.to_micros_since_unix_epoch() - at.to_micros_since_unix_epoch()) as f64 / 1_000_000.0
}

fn status_of(ctx: &ReducerContext, entity_id: u64) -> u8 {
    ctx.db.status_state().entity_id().find(entity_id).map(|r| r.status).unwrap_or(crate::status::NORMAL)
}

fn arr(v: Vector3) -> [f32; 3] {
    [v.x, v.y, v.z]
}

/// A hold's reach: its own, or the game's interact range.
fn reach_of(ctx: &ReducerContext, h: &HoldSeed) -> f32 {
    if h.range_m > 0.0 { h.range_m } else { hot_number(ctx, crate::hot::foundation::INTERACT_RANGE_M) as f32 }
}

/// A PLAYER PRESSES AND HOLDS the interact key on `target_id` (`verb`: 0 the interact key). Starts
/// the hold such a press starts (`hold::find`: the target's kind and status, the doer's kind), or
/// joins it when others are already doing it. Refused when nothing is held there, out of reach, or
/// the doer cannot act. Letting go is `end_interact`.
#[reducer]
pub fn begin_interact(ctx: &ReducerContext, target_id: u64, verb: u8) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("begin_interact: no player row")?;
    spend_rate(ctx, player.entity_id, "begin_interact")?;
    begin_hold(ctx, player.entity_id, target_id, verb)
}

/// The player let go of the interact key: they stop holding whatever they were. Nothing when they
/// were holding nothing (a release that arrives after the hold finished).
#[reducer]
pub fn end_interact(ctx: &ReducerContext) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("end_interact: no player row")?;
    let_go(ctx, player.entity_id, hold::left::RELEASED);
    Ok(())
}

/// AUTHORITY: `actor_id` (an NPC, a bot) begins holding, as a player's `begin_interact` (the sidecar
/// drives bots that lay eggs and help each other up). Same rules, for an entity in its worlds.
#[reducer]
pub fn begin_interact_as(ctx: &ReducerContext, actor_id: u64, target_id: u64, verb: u8) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(actor_id).ok_or("begin_interact_as: no such entity")?;
    require_authority(ctx, ent.world_id)?;
    begin_hold(ctx, actor_id, target_id, verb)
}

/// AUTHORITY: `actor_id` lets go, as a player's `end_interact`.
#[reducer]
pub fn end_interact_as(ctx: &ReducerContext, actor_id: u64) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(actor_id).ok_or("end_interact_as: no such entity")?;
    require_authority(ctx, ent.world_id)?;
    let_go(ctx, actor_id, hold::left::RELEASED);
    Ok(())
}

/// Start or join the hold `actor_id`'s press of `verb` on `target_id` starts, for code that has
/// decided who is asking (a player's own call, an authority's for its NPC).
pub fn begin_hold(ctx: &ReducerContext, actor_id: u64, target_id: u64, verb: u8) -> Result<(), String> {
    if actor_id == target_id {
        return Err("begin_interact: not on yourself".into());
    }
    require_can_act(ctx, actor_id, "begin_interact")?;
    let actor = ctx.db.entity().entity_id().find(actor_id).ok_or("begin_interact: no such entity")?;
    let target = ctx.db.entity().entity_id().find(target_id).ok_or("begin_interact: no such entity")?;
    if ctx.db.player().entity_id().find(target_id).is_some_and(|p| !p.online) {
        return Err("begin_interact: they are not here".into());
    }
    if !is_targetable(ctx, target_id) {
        return Err("begin_interact: they cannot be reached".into());
    }
    let me = ctx.db.movement_state().entity_id().find(actor_id).ok_or("begin_interact: you have no movement_state")?;
    let there = ctx.db.movement_state().entity_id().find(target_id).ok_or("begin_interact: target has no movement_state")?;
    if me.world_id != there.world_id {
        return Err("begin_interact: target is in another world".into());
    }
    let seed = hold::find(target.kind, verb, status_of(ctx, target_id), actor.kind).ok_or_else(|| format!(
        "begin_interact: nothing to hold there (verb {verb} on a kind {} in status {})", target.kind, status_of(ctx, target_id)))?;
    let reach = reach_of(ctx, seed);
    let d = me.pos.sub(there.pos).length_sq().sqrt();
    if d > reach {
        return Err(format!("begin_interact: out of range ({d:.2} m > {reach:.2} m)"));
    }
    crate::game::may_hold(ctx, actor_id, &target, seed)?;
    // Already doing it: nothing to change. Doing something else: let go of that first.
    if let Some(m) = ctx.db.hold_member().entity_id().find(actor_id) {
        if m.target_id == target_id && m.hold == seed.id {
            return Ok(());
        }
        let_go(ctx, actor_id, hold::left::RELEASED);
    }
    let row = match ctx.db.hold_progress().entity_id().filter(target_id).find(|r| r.hold == seed.id && r.state == GOING) {
        Some(r) => r,
        None => ctx.db.hold_progress().insert(HoldProgress {
            hold_id: 0,
            entity_id: target_id,
            world_id: target.world_id,
            hold: seed.id,
            progress: 0.0,
            rate: 0.0,
            at: ctx.timestamp,
            doers: 0,
            state: GOING,
        }),
    };
    let doers = ctx.db.hold_member().hold_id().filter(row.hold_id).count();
    if seed.max_doers > 0 && doers >= seed.max_doers as usize {
        return Err(format!("begin_interact: {} already being done by {} (at most {})", seed.name, doers, seed.max_doers));
    }
    ctx.db.hold_member().insert(HoldMember {
        entity_id: actor_id,
        world_id: actor.world_id,
        hold_id: row.hold_id,
        target_id,
        hold: seed.id,
        since: ctx.timestamp,
        from: me.pos,
    });
    log::info!("entity {actor_id}: holds '{}' on {target_id} ({} doing it)", seed.name, doers + 1);
    settle(ctx, row.hold_id);
    ensure_tick(ctx);
    Ok(())
}

/// A GENRE MOVES A HOLD ALONG, OR BACK (DECISIONS #220): `by` (a share of the whole: +0.03 for a great
/// wobble, -0.25 for a raid) added to how far along it is now, held to 0..1, and the line drawn on from
/// there at the same pace. Then settled as any change is: done when it reached 1 (its `then` status,
/// `on_hold_completed`), gone when undone to nothing with nobody doing it. Nothing for a row that is not
/// being done (gone, or shown done). True when it moved.
pub fn nudge_hold(ctx: &ReducerContext, hold_id: u64, by: f32) -> bool {
    let Some(row) = ctx.db.hold_progress().hold_id().find(hold_id) else { return false };
    if row.state != GOING || !by.is_finite() {
        return false;
    }
    let now = hold::progress_at(row.progress, row.rate, secs_since(ctx, row.at));
    let moved = (now + by).clamp(0.0, 1.0);
    log::info!("hold {} on {}: moved {by:+.3} by its genre ({now:.3} -> {moved:.3})", row.hold, row.entity_id);
    ctx.db.hold_progress().hold_id().update(HoldProgress { progress: moved, at: ctx.timestamp, ..row });
    settle(ctx, hold_id);
    true
}

/// How far along `row` is now (0..1), from its line.
pub fn hold_progress_now(ctx: &ReducerContext, row: &HoldProgress) -> f32 {
    hold::progress_at(row.progress, row.rate, secs_since(ctx, row.at)).clamp(0.0, 1.0)
}

/// `actor_id` stops holding whatever it holds (`why`: `hold::left`), and what it held is settled again.
pub fn let_go(ctx: &ReducerContext, actor_id: u64, why: u8) {
    let Some(m) = ctx.db.hold_member().entity_id().find(actor_id) else { return };
    drop_member(ctx, &m, why);
    settle(ctx, m.hold_id);
}

/// A doer is hurt: it lets go of a hold that a hurt doer lets go of (`stopped_by_damage`).
pub(crate) fn hurt(ctx: &ReducerContext, entity_id: u64) {
    let Some(m) = ctx.db.hold_member().entity_id().find(entity_id) else { return };
    if hold::by_id(m.hold).map_or(true, |h| h.stopped_by_damage) {
        let_go(ctx, entity_id, hold::left::DAMAGED);
    }
}

/// An entity is gone: what it held, and what was being held on it.
pub(crate) fn forget_holds(ctx: &ReducerContext, entity_id: u64) {
    let_go(ctx, entity_id, hold::left::GONE);
    let on_it: Vec<HoldProgress> = ctx.db.hold_progress().entity_id().filter(entity_id).collect();
    for row in on_it {
        end_hold(ctx, &row, hold::left::GONE);
    }
}

fn drop_member(ctx: &ReducerContext, m: &HoldMember, why: u8) {
    ctx.db.hold_member().entity_id().delete(m.entity_id);
    log::info!("entity {}: lets go of hold {} on {} (why {why})", m.entity_id, m.hold, m.target_id);
    if let Some(row) = ctx.db.hold_progress().hold_id().find(m.hold_id) {
        crate::game::on_hold_left(ctx, m.entity_id, &row, why);
    }
}

/// Everyone lets go (`why`) and the row is gone, whatever the hold keeps.
fn end_hold(ctx: &ReducerContext, row: &HoldProgress, why: u8) {
    let doers: Vec<HoldMember> = ctx.db.hold_member().hold_id().filter(row.hold_id).collect();
    for m in doers {
        drop_member(ctx, &m, why);
    }
    ctx.db.hold_progress().hold_id().delete(row.hold_id);
}

/// THE ROW AGAIN, NOW: done when it has got there; otherwise its rate from who is doing it (a genre
/// may say otherwise, `game::hold_rate`), written only when that changed. Nobody doing it: gone,
/// unless the hold keeps its progress (then it waits, or undoes at a genre's rate, until empty).
fn settle(ctx: &ReducerContext, hold_id: u64) {
    let Some(row) = ctx.db.hold_progress().hold_id().find(hold_id) else { return };
    if row.state != GOING {
        return;
    }
    let Some(seed) = hold::by_id(row.hold) else {
        end_hold(ctx, &row, hold::left::GONE);   // content this build no longer has
        return;
    };
    let doers: Vec<HoldMember> = ctx.db.hold_member().hold_id().filter(hold_id).collect();
    let now = hold::progress_at(row.progress, row.rate, secs_since(ctx, row.at));
    if now >= 1.0 {
        complete(ctx, row, seed, &doers);
        return;
    }
    let n = doers.len() as u32;
    // The genre's answer is its own; the content's is scaled by the game's pace (`foundation.hold_speed`).
    let rate = crate::game::hold_rate(ctx, &row, seed, n)
        .unwrap_or_else(|| hold::rate(seed, n) * hot_number(ctx, crate::hot::foundation::HOLD_SPEED).max(0.0) as f32);
    if n == 0 && (!seed.keeps_progress || (now <= 0.0 && rate <= 0.0)) {
        log::info!("hold {} on {}: let go of by everyone{}", seed.name, row.entity_id,
            if seed.keeps_progress { " and undone" } else { ", and lost" });
        ctx.db.hold_progress().hold_id().delete(hold_id);
        return;
    }
    if rate != row.rate || n as u8 != row.doers {
        ctx.db.hold_progress().hold_id().update(HoldProgress { progress: now, rate, at: ctx.timestamp, doers: n as u8, ..row });
    }
}

/// IT IS DONE: shown done for a tick, everyone lets go, the target is put in the hold's `then`
/// status, and every genre hears it (`on_hold_completed`).
fn complete(ctx: &ReducerContext, row: HoldProgress, seed: &HoldSeed, doers: &[HoldMember]) {
    let ids: Vec<u64> = doers.iter().map(|m| m.entity_id).collect();
    for m in doers {
        ctx.db.hold_member().entity_id().delete(m.entity_id);
    }
    let done = ctx.db.hold_progress().hold_id().update(HoldProgress {
        progress: 1.0, rate: 0.0, at: ctx.timestamp, doers: ids.len() as u8, state: DONE, ..row
    });
    log::info!("hold {} on {}: done by {:?}", seed.name, done.entity_id, ids);
    if seed.then_status >= 0 {
        if let Err(why) = set_status_internal(ctx, done.entity_id, seed.then_status as u8, LASTS_OWN,
            ids.first().copied().unwrap_or(0), String::new()) {
            log::error!("hold {} on {}: done, but its status {} failed: {why}", seed.name, done.entity_id, seed.then_status);
        }
    }
    crate::game::on_hold_completed(ctx, &done, seed, &ids);
}

fn ensure_tick(ctx: &ReducerContext) {
    if ctx.db.hold_tick().iter().next().is_none() {
        ctx.db.hold_tick().insert(HoldTick {
            scheduled_id: 0,
            scheduled_at: TimeDuration::from_micros(HOLD_TICK_MICROS).into(),
        });
    }
}

/// EVERY THING BEING HELD, 10 times a second: a doer who is out of reach (with the rule's slack,
/// `foundation.hold_leave_slack_m`), has wandered, cannot act, has left the game or is in another
/// world lets go; a target that is no longer what the hold is done to (its status changed) ends it;
/// then each is settled (done, or its rate again). What was shown done for a tick goes. Nothing
/// held: the tick stops itself until `begin_hold` needs it again.
#[reducer]
pub fn tick_holds(ctx: &ReducerContext, _tick: HoldTick) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("tick_holds: scheduler only".into());
    }
    let slack = hot_number(ctx, crate::hot::foundation::HOLD_LEAVE_SLACK_M) as f32;
    let rows: Vec<HoldProgress> = ctx.db.hold_progress().iter().collect();
    for row in &rows {
        if row.state == DONE {
            ctx.db.hold_progress().hold_id().delete(row.hold_id);
            continue;
        }
        let Some(seed) = hold::by_id(row.hold) else {
            end_hold(ctx, row, hold::left::GONE);
            continue;
        };
        let target_at = ctx.db.movement_state().entity_id().find(row.entity_id);
        let target_here = ctx.db.entity().entity_id().find(row.entity_id).is_some()
            && !ctx.db.player().entity_id().find(row.entity_id).is_some_and(|p| !p.online);
        let Some(target_at) = target_at.filter(|_| target_here) else {
            end_hold(ctx, row, hold::left::GONE);
            continue;
        };
        if !hold::still_applies(seed, status_of(ctx, row.entity_id)) || !is_targetable(ctx, row.entity_id) {
            end_hold(ctx, row, hold::left::TARGET_CHANGED);
            continue;
        }
        let reach = reach_of(ctx, seed);
        let doers: Vec<HoldMember> = ctx.db.hold_member().hold_id().filter(row.hold_id).collect();
        for m in doers {
            let why = match ctx.db.movement_state().entity_id().find(m.entity_id) {
                None => Some(hold::left::GONE),
                Some(at) if at.world_id != target_at.world_id => Some(hold::left::TARGET_CHANGED),
                Some(_) if ctx.db.player().entity_id().find(m.entity_id).is_some_and(|p| !p.online) => Some(hold::left::CANNOT_ACT),
                Some(_) if !crate::status::find(status_of(ctx, m.entity_id)).unwrap_or_else(crate::status::normal).can_act => Some(hold::left::CANNOT_ACT),
                Some(at) => hold::keeps_hold(seed, arr(m.from), arr(at.pos), arr(target_at.pos), reach, slack),
            };
            if let Some(why) = why {
                drop_member(ctx, &m, why);
            }
        }
        settle(ctx, row.hold_id);
    }
    if ctx.db.hold_progress().iter().next().is_none() {
        let ticks: Vec<u64> = ctx.db.hold_tick().iter().map(|t| t.scheduled_id).collect();
        for id in ticks {
            ctx.db.hold_tick().scheduled_id().delete(id);
        }
    }
    Ok(())
}
