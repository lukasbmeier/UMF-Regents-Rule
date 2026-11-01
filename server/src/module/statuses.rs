//! STATUSES AND THEIR TIMERS (docs/FOUNDATION_SYSTEMS.md milestone 2, DECISIONS #206): which
//! status each entity is in, since when, for how long, and what moves it on. What a status LETS an
//! entity do is content (`crate::status`); this file keeps who is in which. `mod.rs` says why the
//! module is wasm-only.

use super::*;
use crate::status::{StatusSeed, NORMAL};

/// AN ENTITY'S STATUS (DECISIONS #206). No row: normal. A side table, keyed by entity, so no
/// table any old client reads changed shape (docs/rules/compatibility.md). Public and per world:
/// every client shows it (a pose, a tag, the HUD's countdown) and predicts its own movement by it.
#[table(accessor = status_state, public)]
pub struct StatusStateRow {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The cell it is in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
    /// Its number (`StatusDef.status`): the foundation's 0-99, a genre's 100-255.
    pub status: u8,
    /// The one before: for the grace after a change (`status::bound`), and for whoever shows it.
    pub prev_status: u8,
    pub since: Timestamp,
    /// How long it lasts from `since` (0: until something changes it). Clients count down from it.
    pub lasts_ms: u32,
    /// Who put it in it (0: nobody: the game, a timer, the server).
    pub by_entity: u64,
    /// The genre's own words about it (which coop a chicken is stashed in). The foundation keeps it.
    pub data: String,
    /// Counts every change, so a timer can tell the status it was set for from a newer one, and a
    /// client can see the same status set again (downed twice).
    pub serial: u32,
}

/// AN EFFECT ON AN ENTITY (DECISIONS #302): a status held ALONGSIDE its state (`status_state`), not instead
/// of it, so a block raised while Slowed leaves the slow, and two effects (Slowed and Shielded) stand together.
/// Effects are statuses (`StatusDef`) applied this way: one row per entity and status (the same effect again
/// refreshes it), each with its own timer. What the entity may do is its state's and every effect's, the
/// strictest winning (`may_act`, `is_targetable`, `is_hittable`; the movement bound, `effect_limits`). Public
/// and per cell, as `status_state`: clients predict their movement by it and show it. A side table: no table
/// an old client reads changed shape (an old client never hears of an effect, and is corrected by the bound).
#[table(accessor = status_effect, public)]
pub struct StatusEffectRow {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The cell it is in (`crate::cell`): it follows its entity, as its state does.
    #[index(btree)]
    pub chunk: u32,
    pub status: u8,
    pub since: Timestamp,
    /// How long it lasts from `since` (0: until it is taken off).
    pub lasts_ms: u32,
    /// Who put it on (0: nobody: the game, the server).
    pub by_entity: u64,
    /// Counts each refresh, so a timer can tell the effect it was set for from a newer one.
    pub serial: u32,
}

/// An effect's timer (`expire_effect`). Private, one row per timed effect.
#[table(accessor = effect_expiry, scheduled(expire_effect))]
pub struct EffectExpiry {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
    #[index(btree)]
    pub effect_id: u64,
    pub serial: u32,
}

/// A status's timer: when it fires, `expire_status` moves the entity on, unless the status it was
/// set for has changed since (`serial`). Private, one row per timed status.
#[table(accessor = status_expiry, scheduled(expire_status))]
pub struct StatusExpiry {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
    #[index(btree)]
    pub entity_id: u64,
    pub serial: u32,
}

/// `set_status`'s `lasts_ms`: the status's own length (its `StatusDef.lasts_s`).
pub const LASTS_OWN: u32 = 0;
/// `set_status`'s `lasts_ms`: until something changes it, whatever its own length.
pub const LASTS_UNTIL_CHANGED: u32 = u32::MAX;
/// Longest `data` a status keeps.
pub const MAX_STATUS_DATA: usize = 256;

/// The status an entity is in (normal, with no row; normal too for a number this build does not
/// have, from an older build's row).
pub fn status_seed(ctx: &ReducerContext, entity_id: u64) -> &'static StatusSeed {
    ctx.db.status_state().entity_id().find(entity_id)
        .and_then(|r| crate::status::find(r.status))
        .unwrap_or_else(crate::status::normal)
}

/// The effects an entity is under (DECISIONS #302): each one's status (an unknown number, from an older
/// build's row, is left out).
pub fn effects_of(ctx: &ReducerContext, entity_id: u64) -> Vec<&'static StatusSeed> {
    ctx.db.status_effect().entity_id().filter(entity_id).filter_map(|r| crate::status::find(r.status)).collect()
}

/// Ok when an entity's state and every effect it is under let it use things and abilities; else why not,
/// for the player (the first that does not).
pub fn require_can_act(ctx: &ReducerContext, entity_id: u64, verb: &str) -> Result<(), String> {
    let s = status_seed(ctx, entity_id);
    if !s.can_act {
        return Err(format!("{verb}: you cannot while {}", s.name.to_lowercase()));
    }
    match effects_of(ctx, entity_id).into_iter().find(|e| !e.can_act) {
        Some(e) => Err(format!("{verb}: you cannot while {}", e.name.to_lowercase())),
        None => Ok(()),
    }
}

/// Whether someone else may use or aim at an entity in its state and effects (an escaped player is not there).
pub fn is_targetable(ctx: &ReducerContext, entity_id: u64) -> bool {
    status_seed(ctx, entity_id).targetable && effects_of(ctx, entity_id).iter().all(|e| e.targetable)
}

/// Whether an ability a referee judges may HIT an entity in its state and effects (DECISIONS #226, #302).
pub fn is_hittable(ctx: &ReducerContext, entity_id: u64) -> bool {
    status_seed(ctx, entity_id).hittable && effects_of(ctx, entity_id).iter().all(|e| e.hittable)
}

/// A bound (`status_limits`) made as strict as every effect on the entity asks (`status::stricter`). An effect
/// put on under `grace_ms` ago is not counted yet: it reaches its entity's client a round trip later, and until
/// then the client moves as it did (the state's own grace, #206).
pub fn effect_limits(limits: crate::content::MovementLimits, effects: &[StatusEffectRow], now_micros: i64,
    kind: crate::content::MovementLimits, grace_ms: i64) -> crate::content::MovementLimits {
    let mut out = limits;
    for e in effects {
        if (now_micros - e.since.to_micros_since_unix_epoch()) / 1000 < grace_ms {
            continue;
        }
        if let Some(s) = crate::status::find(e.status) {
            out = crate::status::stricter(out, crate::status::applied(kind, s, false));
        }
    }
    out
}

/// PUT AN EFFECT ON an entity (DECISIONS #302), for code that has already decided it may (a genre's spell):
/// alongside its state, which it leaves alone. The same effect again refreshes it (its time from now, its
/// putter). `lasts_ms` as `set_status_internal`'s. Every genre hears it (`on_effect_changed`).
pub fn add_effect_internal(ctx: &ReducerContext, entity_id: u64, status: u8, lasts_ms: u32, by_entity: u64) -> Result<(), String> {
    let seed = crate::status::find(status).ok_or_else(|| format!("add_effect: there is no status {status} in this game"))?;
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("add_effect: no such entity")?;
    let lasts = match lasts_ms {
        LASTS_OWN => seed.lasts_ms,
        LASTS_UNTIL_CHANGED => 0,
        n => n,
    };
    let old = ctx.db.status_effect().entity_id().filter(entity_id).find(|r| r.status == status);
    let row = match old {
        Some(r) => {
            for t in ctx.db.effect_expiry().effect_id().filter(r.id).map(|t| t.scheduled_id).collect::<Vec<_>>() {
                ctx.db.effect_expiry().scheduled_id().delete(t);
            }
            ctx.db.status_effect().id().update(StatusEffectRow {
                since: ctx.timestamp, lasts_ms: lasts, by_entity, serial: r.serial.wrapping_add(1), ..r
            })
        }
        None => ctx.db.status_effect().insert(StatusEffectRow {
            id: 0, entity_id, world_id: ent.world_id, chunk: chunk_of_entity(ctx, entity_id), status,
            since: ctx.timestamp, lasts_ms: lasts, by_entity, serial: 1,
        }),
    };
    if lasts > 0 {
        ctx.db.effect_expiry().insert(EffectExpiry {
            scheduled_id: 0,
            scheduled_at: ScheduleAt::Time(ctx.timestamp + TimeDuration::from_micros(lasts as i64 * 1000)),
            effect_id: row.id,
            serial: row.serial,
        });
    }
    log::info!("entity {entity_id}: effect {status} ({}) on{}", seed.name,
        if lasts > 0 { format!(" for {lasts} ms") } else { String::new() });
    crate::game::on_effect_changed(ctx, entity_id, status, true);
    Ok(())
}

/// TAKE AN EFFECT OFF an entity (DECISIONS #302): true if it was under it.
pub fn remove_effect_internal(ctx: &ReducerContext, entity_id: u64, status: u8) -> bool {
    let Some(r) = ctx.db.status_effect().entity_id().filter(entity_id).find(|r| r.status == status) else { return false };
    drop_effect(ctx, r.id);
    log::info!("entity {entity_id}: effect {status} off");
    crate::game::on_effect_changed(ctx, entity_id, status, false);
    true
}

fn drop_effect(ctx: &ReducerContext, effect_id: u64) {
    for t in ctx.db.effect_expiry().effect_id().filter(effect_id).map(|t| t.scheduled_id).collect::<Vec<_>>() {
        ctx.db.effect_expiry().scheduled_id().delete(t);
    }
    ctx.db.status_effect().id().delete(effect_id);
}

/// An effect's time is up: it comes off (unless it was refreshed since). Scheduled only.
#[reducer]
pub fn expire_effect(ctx: &ReducerContext, timer: EffectExpiry) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("expire_effect: scheduler only".into());
    }
    let Some(row) = ctx.db.status_effect().id().find(timer.effect_id) else { return Ok(()) };
    if row.serial != timer.serial {
        return Ok(());
    }
    remove_effect_internal(ctx, row.entity_id, row.status);
    Ok(())
}

/// An entity's Tier A bound with its status applied (`status::bound`): its kind's bound, scaled
/// by the status (`row`, its status row; None: none), and for `grace_ms` after a change the wider of
/// the old and new. The movement tick reads a world's status rows once a tick.
pub fn status_limits(row: Option<&StatusStateRow>, now_micros: i64, kind: crate::content::MovementLimits, grace_ms: i64)
    -> crate::content::MovementLimits {
    let Some(row) = row else {
        return crate::status::applied(kind, crate::status::normal(), false);
    };
    let cur = crate::status::find(row.status).unwrap_or_else(crate::status::normal);
    let prev = crate::status::find(row.prev_status).unwrap_or_else(crate::status::normal);
    let since_ms = (now_micros - row.since.to_micros_since_unix_epoch()).max(0) / 1000;
    crate::status::bound(kind, cur, prev, since_ms, grace_ms)
}

/// Put an entity in a status, for code that has already decided it may (a genre's rule, a timer,
/// `set_status`). `lasts_ms`: `LASTS_OWN`, `LASTS_UNTIL_CHANGED`, or a length. Every genre hears it
/// (`on_status_changed`), after the row is written.
pub fn set_status_internal(ctx: &ReducerContext, entity_id: u64, status: u8, lasts_ms: u32, by_entity: u64, data: String)
    -> Result<(), String> {
    let seed = crate::status::find(status).ok_or_else(|| format!(
        "set_status: there is no status {status} in this game (its statuses: {:?})",
        crate::status::STATUSES.iter().map(|s| (s.status, s.name)).collect::<Vec<_>>()))?;
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("set_status: no such entity")?;
    if data.len() > MAX_STATUS_DATA {
        return Err(format!("set_status: at most {MAX_STATUS_DATA} bytes of data"));
    }
    let old = ctx.db.status_state().entity_id().find(entity_id);
    let from = old.as_ref().map(|r| r.status).unwrap_or(NORMAL);
    let serial = old.as_ref().map(|r| r.serial.wrapping_add(1)).unwrap_or(1);
    let lasts = match lasts_ms {
        LASTS_OWN => seed.lasts_ms,
        LASTS_UNTIL_CHANGED => 0,
        n => n,
    };
    // Whatever timer the old status had is moot now.
    let timers: Vec<u64> = ctx.db.status_expiry().entity_id().filter(entity_id).map(|e| e.scheduled_id).collect();
    for id in timers {
        ctx.db.status_expiry().scheduled_id().delete(id);
    }
    let row = StatusStateRow {
        entity_id,
        world_id: ent.world_id,
        chunk: chunk_of_entity(ctx, entity_id),
        status,
        prev_status: from,
        since: ctx.timestamp,
        lasts_ms: lasts,
        by_entity,
        data,
        serial,
    };
    if old.is_some() {
        ctx.db.status_state().entity_id().update(row);
    } else {
        ctx.db.status_state().insert(row);
    }
    if lasts > 0 {
        ctx.db.status_expiry().insert(StatusExpiry {
            scheduled_id: 0,
            scheduled_at: ScheduleAt::Time(ctx.timestamp + TimeDuration::from_micros(lasts as i64 * 1000)),
            entity_id,
            serial,
        });
    }
    log::info!("entity {entity_id}: status {from} -> {status} ({}){}", seed.name,
        if lasts > 0 { format!(" for {lasts} ms") } else { String::new() });
    if let Some(now) = ctx.db.status_state().entity_id().find(entity_id) {
        crate::game::on_status_changed(ctx, entity_id, from, &now);
    }
    Ok(())
}

/// AUTHORITY: put an entity in a status (DECISIONS #206). The sidecar and an admin may for any
/// entity in their worlds; while the dev tools are on, a player may for themself (a designer trying
/// one). Players have no other route: a genre's verbs set statuses through `set_status_internal`.
#[reducer]
pub fn set_status(ctx: &ReducerContext, entity_id: u64, status: u8, lasts_ms: u32, data: String) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("set_status: no such entity")?;
    let me = ctx.db.player().identity().find(ctx.sender()).map(|p| p.entity_id);
    if require_authority(ctx, ent.world_id).is_err() {
        if me != Some(entity_id) {
            return Err("set_status: only an authority (the sidecar, an admin) sets someone's status".into());
        }
        require_dev_tools(ctx, "set_status")?;
        spend_rate(ctx, entity_id, "set_status")?;
    }
    set_status_internal(ctx, entity_id, status, lasts_ms, me.unwrap_or(0), data)
}

/// AUTHORITY: put an effect on an entity (`on`) or take it off (DECISIONS #302), as `set_status`: the sidecar
/// and an admin for any entity in their worlds; a player for themself while the dev tools are on.
#[reducer]
pub fn set_effect(ctx: &ReducerContext, entity_id: u64, status: u8, lasts_ms: u32, on: bool) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("set_effect: no such entity")?;
    let me = ctx.db.player().identity().find(ctx.sender()).map(|p| p.entity_id);
    if require_authority(ctx, ent.world_id).is_err() {
        if me != Some(entity_id) {
            return Err("set_effect: only an authority (the sidecar, an admin) puts an effect on someone".into());
        }
        require_dev_tools(ctx, "set_effect")?;
        spend_rate(ctx, entity_id, "set_status")?;
    }
    if on {
        add_effect_internal(ctx, entity_id, status, lasts_ms, me.unwrap_or(0))
    } else if remove_effect_internal(ctx, entity_id, status) {
        Ok(())
    } else {
        Err(format!("set_effect: entity {entity_id} is not under effect {status}"))
    }
}

/// A status's time is up: what it becomes is a genre's answer (`on_status_expired`), else the
/// status's own `then`. Scheduled only; a timer for a status that has changed since does nothing.
#[reducer]
pub fn expire_status(ctx: &ReducerContext, timer: StatusExpiry) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("expire_status: scheduler only".into());
    }
    let Some(row) = ctx.db.status_state().entity_id().find(timer.entity_id) else { return Ok(()) };
    if row.serial != timer.serial {
        return Ok(());
    }
    let next = crate::game::on_status_expired(ctx, &row)
        .unwrap_or_else(|| crate::status::find(row.status).map(|s| s.then).unwrap_or(NORMAL));
    if let Err(why) = set_status_internal(ctx, row.entity_id, next, LASTS_OWN, 0, String::new()) {
        // A genre answered with a status this game does not have: normal, rather than stuck.
        log::error!("entity {}: status {} ended into {next}, which failed ({why}): normal instead", row.entity_id, row.status);
        set_status_internal(ctx, row.entity_id, NORMAL, LASTS_UNTIL_CHANGED, 0, String::new())?;
    }
    Ok(())
}

/// A new match begins in `world_id`: every PERSON in it back to normal, when the game's rule says so
/// (`foundation.statuses_reset_each_match`). Not things (DECISIONS #222): a nest's stage or a gate's
/// state is its game's, which resets it when it means to (`on_match_began`). Resetting everything
/// left Fowl Play's nests in no stage at all after a new match, so nothing could be done to them.
pub(crate) fn reset_statuses(ctx: &ReducerContext, world_id: u32) {
    if !hot_flag(ctx, crate::hot::foundation::STATUSES_RESET_EACH_MATCH) {
        return;
    }
    let ids: Vec<u64> = ctx.db.status_state().world_id().filter(world_id)
        .filter(|r| r.status != NORMAL || r.lasts_ms > 0)
        .filter(|r| is_person(ctx, r.entity_id))
        .map(|r| r.entity_id).collect();
    for id in ids {
        let _ = set_status_internal(ctx, id, NORMAL, LASTS_UNTIL_CHANGED, 0, String::new());
    }
    // And their effects (#302): a new match starts no one slowed.
    let effects: Vec<(u64, u8)> = ctx.db.status_effect().world_id().filter(world_id)
        .filter(|e| is_person(ctx, e.entity_id)).map(|e| (e.entity_id, e.status)).collect();
    for (id, status) in effects {
        remove_effect_internal(ctx, id, status);
    }
}

/// Whether `entity_id` is a PERSON: a player's (it has a player row), an NPC driven by a brain, one of
/// the foundation's people kinds, or a character a player may choose (a bot hen). Not a thing: a
/// resource node, a nest, a gate.
pub fn is_person(ctx: &ReducerContext, entity_id: u64) -> bool {
    if ctx.db.player().entity_id().find(entity_id).is_some() || ctx.db.npc_brain().entity_id().find(entity_id).is_some() {
        return true;
    }
    ctx.db.entity().entity_id().find(entity_id).is_some_and(|e| {
        e.kind == entity_kind::PLAYER || e.kind == entity_kind::NPC || crate::content::is_playable(e.kind)
    })
}

/// An entity is gone: its status and timers with it.
pub(crate) fn forget_status(ctx: &ReducerContext, entity_id: u64) {
    ctx.db.status_state().entity_id().delete(entity_id);
    for e in ctx.db.status_effect().entity_id().filter(entity_id).map(|e| e.id).collect::<Vec<_>>() {
        drop_effect(ctx, e);
    }
    let timers: Vec<u64> = ctx.db.status_expiry().entity_id().filter(entity_id).map(|e| e.scheduled_id).collect();
    for id in timers {
        ctx.db.status_expiry().scheduled_id().delete(id);
    }
}
