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

/// Ok when an entity's status lets it use things and abilities; else why not, for the player.
pub fn require_can_act(ctx: &ReducerContext, entity_id: u64, verb: &str) -> Result<(), String> {
    let s = status_seed(ctx, entity_id);
    if s.can_act { Ok(()) } else { Err(format!("{verb}: you cannot while {}", s.name.to_lowercase())) }
}

/// Whether someone else may use or aim at an entity in its status (an escaped player is not there).
pub fn is_targetable(ctx: &ReducerContext, entity_id: u64) -> bool {
    status_seed(ctx, entity_id).targetable
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
    let timers: Vec<u64> = ctx.db.status_expiry().entity_id().filter(entity_id).map(|e| e.scheduled_id).collect();
    for id in timers {
        ctx.db.status_expiry().scheduled_id().delete(id);
    }
}
