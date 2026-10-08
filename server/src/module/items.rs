//! Item definitions, inventories, the look a player chose, the equip state. Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

use super::*;

// =============================================================================
// ITEMS / INVENTORY
// =============================================================================

/// Idempotent catalogue seeding. Admin-only; a genre calls this with its own list at deploy
/// time. Existing rows are updated rather than duplicated so it is safe to re-run.
#[reducer]
pub fn seed_item_defs(ctx: &ReducerContext, defs: Vec<ItemDef>) -> Result<(), String> {
    require_admin(ctx)?;
    for d in defs {
        if d.max_stack == 0 {
            return Err(format!("item_def {}: max_stack must be >= 1", d.item_def_id));
        }
        if ctx.db.item_def().item_def_id().find(d.item_def_id).is_some() {
            ctx.db.item_def().item_def_id().update(d);
        } else {
            ctx.db.item_def().insert(d);
        }
    }
    Ok(())
}

/// Add `qty` of an item to an entity, filling existing stacks before opening new ones.
/// Authority-only: loot and rewards are server decisions, never client claims.
#[reducer]
pub fn grant_item(
    ctx: &ReducerContext,
    entity_id: u64,
    item_def_id: u32,
    qty: u32,
) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("no such entity")?;
    require_authority(ctx, ent.world_id)?;
    grant_item_internal(ctx, entity_id, item_def_id, qty)
}

/// Shared by `grant_item` and any in-module award path (challenge rewards, for instance), so
/// the stacking rule lives in exactly one place.
pub(crate) fn grant_item_internal(
    ctx: &ReducerContext,
    entity_id: u64,
    item_def_id: u32,
    qty: u32,
) -> Result<(), String> {
    if qty == 0 {
        return Ok(());
    }
    let def = ctx
        .db
        .item_def()
        .item_def_id()
        .find(item_def_id)
        .ok_or(format!("unknown item_def {item_def_id}"))?;

    let mut remaining = qty;

    // Top up partial stacks first.
    if def.max_stack > 1 {
        let mut stacks: Vec<InventoryItem> = ctx
            .db
            .inventory_item()
            .owner_entity_id()
            .filter(entity_id)
            .filter(|i| i.item_def_id == item_def_id && i.qty < def.max_stack)
            .collect();
        stacks.sort_by_key(|i| i.id);
        for mut stack in stacks {
            if remaining == 0 {
                break;
            }
            let room = def.max_stack - stack.qty;
            let add = room.min(remaining);
            stack.qty += add;
            remaining -= add;
            ctx.db.inventory_item().id().update(stack);
        }
    }

    while remaining > 0 {
        let take = def.max_stack.min(remaining);
        ctx.db.inventory_item().insert(InventoryItem {
            id: 0,
            owner_entity_id: entity_id,
            item_def_id,
            qty: take,
            slot: -1,
            instance_data: String::new(),
        });
        remaining -= take;
    }
    Ok(())
}

/// Player intent: spend part of a stack. The caller must own the row — this is the one
/// inventory reducer a client may call, so ownership is checked against `player`, not
/// `authority`.
#[reducer]
pub fn consume_item(ctx: &ReducerContext, item_id: u64, qty: u32) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let mut item = ctx.db.inventory_item().id().find(item_id).ok_or("no such item")?;
    if item.owner_entity_id != player.entity_id {
        return Err("not your item".into());
    }
    if qty == 0 || qty > item.qty {
        return Err(format!("cannot consume {qty} of {}", item.qty));
    }
    if item.qty == qty {
        ctx.db.inventory_item().id().delete(item_id);
    } else {
        item.qty -= qty;
        ctx.db.inventory_item().id().update(item);
    }
    Ok(())
}

/// Say what the caller's own entity has in hand (DECISIONS #160): `EquipComponent` calls it as its
/// state changes. Client-callable and presentational, so it only checks the state is one there is.
/// Choose your own look (DECISIONS #166). Like a name it is untrusted text every client acts on,
/// so it is limited here to what a look is spelled with: lowercase letters, digits and `_;=,.-`.
/// Empty clears the choice (back to the look picked from the entity id).
#[reducer]
pub fn set_appearance(ctx: &ReducerContext, look: String) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("set_appearance: no player row")?;
    let ent = ctx.db.entity().entity_id().find(player.entity_id).ok_or("set_appearance: no entity")?;
    spend_rate(ctx, ent.entity_id, "set_appearance")?;
    let look = look.trim().to_string();
    if look.chars().count() > MAX_LOOK_LEN {
        return Err(format!("set_appearance: a look is at most {MAX_LOOK_LEN} characters"));
    }
    if let Some(bad) = look.chars().find(|c| !(c.is_ascii_lowercase() || c.is_ascii_digit() || "_;=,.-".contains(*c))) {
        return Err(format!("set_appearance: '{bad}' is not used in a look (a-z, 0-9 and _;=,.-)"));
    }
    if look.is_empty() {
        ctx.db.appearance().entity_id().delete(ent.entity_id);
        return Ok(());
    }
    let row = AppearanceRow { entity_id: ent.entity_id, world_id: ent.world_id, look };
    match ctx.db.appearance().entity_id().find(ent.entity_id) {
        Some(old) if old.look == row.look => {}   // idempotent: clients send it on every connect
        Some(_) => { ctx.db.appearance().entity_id().update(row); }
        None => { ctx.db.appearance().insert(row); }
    }
    Ok(())
}

#[reducer]
pub fn set_equip_state(ctx: &ReducerContext, state: u8) -> Result<(), String> {
    if state > EQUIP_STOWING {
        return Err(format!("set_equip_state: {state} is not a state (0 away .. 3 putting away)"));
    }
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("set_equip_state: no player row")?;
    let ent = ctx.db.entity().entity_id().find(player.entity_id).ok_or("set_equip_state: no entity")?;
    spend_rate(ctx, ent.entity_id, "set_equip_state")?;
    let row = EquipStateRow { entity_id: ent.entity_id, world_id: ent.world_id, state };
    if ctx.db.equip_state().entity_id().find(ent.entity_id).is_some() {
        ctx.db.equip_state().entity_id().update(row);
    } else {
        ctx.db.equip_state().insert(row);
    }
    Ok(())
}

/// Move a stack to a slot. Client-callable; purely presentational, so it only checks ownership.
#[reducer]
pub fn set_item_slot(ctx: &ReducerContext, item_id: u64, slot: i16) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let mut item = ctx.db.inventory_item().id().find(item_id).ok_or("no such item")?;
    if item.owner_entity_id != player.entity_id {
        return Err("not your item".into());
    }
    item.slot = slot;
    ctx.db.inventory_item().id().update(item);
    Ok(())
}
