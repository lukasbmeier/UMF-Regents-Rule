//! WHERE AN ENTITY IS, ON EVERY ROW THAT DESCRIBES IT (template 1.0, DECISIONS #278,
//! `docs/TEMPLATE_1_0.md` §3). A client with ring interest is sent only the rows of the cells round it,
//! so every row it draws a placed thing from carries that thing's cell (`chunk`) as well as its world.
//! ONE PLACE KEEPS THEM RIGHT: every write of a `movement_state` row goes through `write_movement` or
//! `insert_movement`, which recut its cell from its position; when the cell (or the world) changes,
//! `follow` rewrites the rest in the same transaction, so an entity walking out of a client's cells
//! leaves it whole, in one step. A genre's own rows that follow an entity join in through the
//! `on_place_changed` hook. Rows that are an EVENT (a noise, a contact, a push, an action) are cut once,
//! where it happened, and never follow.

use super::*;

/// The cell an entity is in: its movement row's, else its entity row's; 0 (the grid's corner) for none.
pub fn chunk_of_entity(ctx: &ReducerContext, entity_id: u64) -> u32 {
    if let Some(m) = ctx.db.movement_state().entity_id().find(entity_id) {
        return m.chunk;
    }
    ctx.db.entity().entity_id().find(entity_id).map(|e| e.chunk).unwrap_or(0)
}

/// Write an entity's movement row, its cell recut from where it now is; in a new cell or world,
/// everything that follows it moves with it. Returns the row as written.
pub fn write_movement(ctx: &ReducerContext, row: MovementStateRow) -> MovementStateRow {
    let was = ctx.db.movement_state().entity_id().find(row.entity_id);
    write_movement_over(ctx, was.as_ref(), row)
}

/// `write_movement` for a caller that has the stored row in hand (`was`, read in THIS transaction and
/// not written since): the movement tick, which reads a world's rows once and writes each at most once.
/// One lookup less a moving entity a tick (300 players: 6,000 a second).
pub(crate) fn write_movement_over(ctx: &ReducerContext, was: Option<&MovementStateRow>, mut row: MovementStateRow) -> MovementStateRow {
    if was.is_some_and(|w| w.chunk == crate::cell::NOWHERE) {
        // Parked: whatever moves it (gravity on an idle body), it stays put away until `unpark`.
        row.chunk = crate::cell::NOWHERE;
        return ctx.db.movement_state().entity_id().update(row);
    }
    let chunk = crate::cell::chunk_of(row.pos);
    // Against the stored row, not the caller's copy: a caller holding an old row cannot hide a move.
    let moved = was.is_none_or(|w| w.chunk != chunk || w.world_id != row.world_id);
    row.chunk = chunk;
    let row = ctx.db.movement_state().entity_id().update(row);
    if moved {
        follow(ctx, row.entity_id, row.world_id, chunk);
    }
    row
}

/// Make an entity's movement row, its cell cut from where it is, and everything that follows it there.
pub fn insert_movement(ctx: &ReducerContext, mut row: MovementStateRow) -> MovementStateRow {
    row.chunk = crate::cell::chunk_of(row.pos);
    let row = ctx.db.movement_state().insert(row);
    follow(ctx, row.entity_id, row.world_id, row.chunk);
    row
}

/// Put every row that describes `entity_id` in `world_id` and cell `chunk`, writing only those that are
/// not there already (it is called on every crossing, and must cost nothing when nothing moved). Its
/// movement row is the caller's, written through `write_movement`.
pub fn follow(ctx: &ReducerContext, entity_id: u64, world_id: u32, chunk: u32) {
    let off = |w: u32, c: u32| w != world_id || c != chunk;
    if let Some(r) = ctx.db.entity().entity_id().find(entity_id) {
        if off(r.world_id, r.chunk) {
            ctx.db.entity().entity_id().update(Entity { world_id, chunk, ..r });
        }
    }
    if let Some(r) = ctx.db.health_state().entity_id().find(entity_id) {
        if off(r.world_id, r.chunk) {
            ctx.db.health_state().entity_id().update(HealthStateRow { world_id, chunk, ..r });
        }
    }
    if let Some(r) = ctx.db.equip_state().entity_id().find(entity_id) {
        if off(r.world_id, r.chunk) {
            ctx.db.equip_state().entity_id().update(EquipStateRow { world_id, chunk, ..r });
        }
    }
    if let Some(r) = ctx.db.appearance().entity_id().find(entity_id) {
        if off(r.world_id, r.chunk) {
            ctx.db.appearance().entity_id().update(AppearanceRow { world_id, chunk, ..r });
        }
    }
    if let Some(r) = ctx.db.status_state().entity_id().find(entity_id) {
        if off(r.world_id, r.chunk) {
            ctx.db.status_state().entity_id().update(StatusStateRow { world_id, chunk, ..r });
        }
    }
    if let Some(r) = ctx.db.attachment().entity_id().find(entity_id) {
        if off(r.world_id, r.chunk) {
            ctx.db.attachment().entity_id().update(Attachment { world_id, chunk, ..r });
        }
    }
    if let Some(r) = ctx.db.body_state().entity_id().find(entity_id) {
        if off(r.world_id, r.chunk) {
            ctx.db.body_state().entity_id().update(BodyState { world_id, chunk, ..r });
        }
    }
    for r in ctx.db.resource_state().entity_id().filter(entity_id).collect::<Vec<_>>() {
        if off(r.world_id, r.chunk) {
            ctx.db.resource_state().id().update(ResourceState { world_id, chunk, ..r });
        }
    }
    for r in ctx.db.hold_progress().entity_id().filter(entity_id).collect::<Vec<_>>() {
        if off(r.world_id, r.chunk) {
            ctx.db.hold_progress().hold_id().update(HoldProgress { world_id, chunk, ..r });
        }
    }
    crate::game::on_place_changed(ctx, entity_id, world_id, chunk);
}

/// PARK an entity (template 1.0): a character whose player is gone (`foundation.park_offline_s`) or who
/// switched to another character. Every row that describes it moves to the NOWHERE cell, which no ring
/// client asks for and no world client either (`InterestManager`), and stays there with everything in
/// it (health, statuses, the genre's own rows): nothing is deleted. Its position is untouched.
pub fn park(ctx: &ReducerContext, entity_id: u64) {
    let Some(m) = ctx.db.movement_state().entity_id().find(entity_id) else { return };
    if m.chunk == crate::cell::NOWHERE {
        return;
    }
    let world_id = m.world_id;
    ctx.db.movement_state().entity_id().update(MovementStateRow { chunk: crate::cell::NOWHERE, ..m });
    follow(ctx, entity_id, world_id, crate::cell::NOWHERE);
    log::info!("entity {entity_id} parked");
}

/// Bring a parked entity back where it stood (its player signed in again): its cell cut from its
/// position, every row with it, a teleport so clients snap it there.
pub fn unpark(ctx: &ReducerContext, entity_id: u64) {
    let Some(m) = ctx.db.movement_state().entity_id().find(entity_id) else { return };
    if m.chunk != crate::cell::NOWHERE {
        return;
    }
    let chunk = crate::cell::chunk_of(m.pos);
    let world_id = m.world_id;
    ctx.db.movement_state().entity_id().update(MovementStateRow { chunk, teleport_flag: true, ..m });
    follow(ctx, entity_id, world_id, chunk);
    log::info!("entity {entity_id} back where it stood");
}

/// Whether an entity is parked.
pub fn is_parked(ctx: &ReducerContext, entity_id: u64) -> bool {
    ctx.db.movement_state().entity_id().find(entity_id).is_some_and(|m| m.chunk == crate::cell::NOWHERE)
}
