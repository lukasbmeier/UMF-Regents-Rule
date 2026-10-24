//! ATTACH AND CARRY (FOUNDATION_SYSTEMS milestone 6, OPEN_ITEMS C1, DECISIONS #228): one entity carried
//! by another (a downed hen in the wolf's mouth). A genre decides when (its holds: pick up, stash) and
//! calls `attach` / `detach`; the foundation keeps the rows and the rules:
//!
//!   the row      `attachment`: who is carried, by whom, since when, and the status it had before
//!   its status   CARRIED while carried (it cannot move or act, nor be hit: `carried.tres`)
//!   its place    the module's tick puts it where its carrier is, every tick, and drops what its
//!                own client claims (it is not moving itself); every client draws it at its carrier's
//!                carry point (`EntityDefinition.carry_offset`, `CarryComponent`), late joiners too
//!   let go       `detach` puts it down where the genre says (or at its carrier's feet) in the status
//!                the genre says (or the one it had); a carrier that leaves or is gone drops what it
//!                carried where it was, in the status it had before
//!
//! A world the module moves (MODULE, Fowl Play's farm) is handled here. NOT YET a world a sidecar moves
//! (SIDECAR): its simulation would still move a carried entity by its own frames; that is the sidecar's
//! part of this, to build when a SIDECAR game carries anything.

use super::*;

/// ONE CARRIED ENTITY. Public and per world: every client draws it at its carrier.
#[table(accessor = attachment, public)]
pub struct Attachment {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The cell it is in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
    #[index(btree)]
    pub carrier_id: u64,
    /// Where on its carrier (a genre's name for it; "" the carrier's carry point).
    pub socket: String,
    pub since: Timestamp,
    /// Its status before it was picked up: what it is put down in unless the genre says otherwise.
    pub prev_status: u8,
}

/// What carries `entity_id`, if anything.
pub fn carrier_of(ctx: &ReducerContext, entity_id: u64) -> Option<u64> {
    ctx.db.attachment().entity_id().find(entity_id).map(|a| a.carrier_id)
}

/// What `carrier_id` carries, if anything (one at a time).
pub fn carried_by(ctx: &ReducerContext, carrier_id: u64) -> Option<u64> {
    ctx.db.attachment().carrier_id().filter(carrier_id).next().map(|a| a.entity_id)
}

/// PICK UP: `carrier_id` carries `entity_id` from now. Both in the same world; neither already
/// carrying nor carried (one at a time, no chains); not itself. It lets go of anything it held, is
/// CARRIED, and is at its carrier from the next tick.
pub fn attach(ctx: &ReducerContext, entity_id: u64, carrier_id: u64, socket: &str) -> Result<(), String> {
    if entity_id == carrier_id {
        return Err("attach: not itself".into());
    }
    let it = ctx.db.entity().entity_id().find(entity_id).ok_or("attach: no such entity")?;
    let carrier = ctx.db.entity().entity_id().find(carrier_id).ok_or("attach: no such carrier")?;
    if it.world_id != carrier.world_id {
        return Err("attach: they are in different worlds".into());
    }
    if carrier_of(ctx, entity_id).is_some() {
        return Err("attach: it is already carried".into());
    }
    if carried_by(ctx, carrier_id).is_some() {
        return Err("attach: the carrier already carries something".into());
    }
    if carrier_of(ctx, carrier_id).is_some() || carried_by(ctx, entity_id).is_some() {
        return Err("attach: no carrying while carried, nor carrying a carrier".into());
    }
    let prev_status = ctx.db.status_state().entity_id().find(entity_id).map(|s| s.status).unwrap_or(crate::status::NORMAL);
    let_go(ctx, entity_id, crate::hold::left::DAMAGED);
    ctx.db.attachment().insert(Attachment {
        entity_id,
        world_id: it.world_id,
        chunk: chunk_of_entity(ctx, entity_id),
        carrier_id,
        socket: socket.to_string(),
        since: ctx.timestamp,
        prev_status,
    });
    set_status_internal(ctx, entity_id, crate::status::CARRIED, LASTS_UNTIL_CHANGED, carrier_id, String::new())?;
    log::info!("{carrier_id} picked up {entity_id} (it was in status {prev_status})");
    Ok(())
}

/// PUT DOWN: `entity_id` is carried no more. It stands at `at` (None: its carrier's feet), facing its
/// carrier's way, in `status` (None: the one it had before it was picked up). Err when it was not
/// carried.
pub fn detach(ctx: &ReducerContext, entity_id: u64, at: Option<Vector3>, status: Option<u8>) -> Result<(), String> {
    let a = ctx.db.attachment().entity_id().find(entity_id).ok_or("detach: it is not carried")?;
    ctx.db.attachment().entity_id().delete(entity_id);
    let carrier = ctx.db.movement_state().entity_id().find(a.carrier_id);
    if let Some(mut row) = ctx.db.movement_state().entity_id().find(entity_id) {
        row.pos = at.or(carrier.as_ref().map(|c| c.pos)).unwrap_or(row.pos);
        row.yaw = carrier.as_ref().map(|c| c.yaw).unwrap_or(row.yaw);
        row.vel = Vector3::new(0.0, 0.0, 0.0);
        row.teleport_flag = true;
        row.server_ts = ctx.timestamp;
        write_movement(ctx, row);
    }
    let then = status.unwrap_or(a.prev_status);
    set_status_internal(ctx, entity_id, then, LASTS_OWN, a.carrier_id, String::new())?;
    log::info!("{} put down {entity_id} (status {then})", a.carrier_id);
    Ok(())
}

/// AUTHORITY: carry, and put down (a sidecar's bots; tests). The genre's own rules are not asked:
/// these are the foundation's mechanism, and a genre calls `attach`/`detach` from its rules.
#[reducer]
pub fn attach_as(ctx: &ReducerContext, entity_id: u64, carrier_id: u64, socket: String) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(carrier_id).ok_or("attach_as: no such carrier")?;
    require_authority(ctx, ent.world_id)?;
    attach(ctx, entity_id, carrier_id, &socket)
}

#[reducer]
pub fn detach_as(ctx: &ReducerContext, entity_id: u64) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("detach_as: no such entity")?;
    require_authority(ctx, ent.world_id)?;
    detach(ctx, entity_id, None, None)
}

/// From the module's tick, for one world: every carried entity is at its carrier (its own claims
/// dropped: `carried_rows`), and one whose carrier has gone, or left, is put down where it was.
pub(crate) fn carried_rows(ctx: &ReducerContext, world_id: u32) -> Vec<(u64, u64)> {
    let rows: Vec<Attachment> = ctx.db.attachment().world_id().filter(world_id).collect();
    let mut out = Vec::new();
    for a in rows {
        let gone = ctx.db.entity().entity_id().find(a.carrier_id).is_none()
            || ctx.db.player().entity_id().find(a.carrier_id).is_some_and(|p| !p.online);
        if gone {
            if let Err(e) = detach(ctx, a.entity_id, None, None) {
                log::error!("{}: its carrier {} has gone, and it could not be put down: {e}", a.entity_id, a.carrier_id);
            }
            continue;
        }
        out.push((a.entity_id, a.carrier_id));
    }
    out
}

/// An entity is gone: what it carried is put down, and it is carried no more.
pub(crate) fn forget_carry(ctx: &ReducerContext, entity_id: u64) {
    if let Some(c) = carried_by(ctx, entity_id) {
        let _ = detach(ctx, c, None, None);
    }
    ctx.db.attachment().entity_id().delete(entity_id);
}
