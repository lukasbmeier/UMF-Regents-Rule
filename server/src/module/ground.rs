//! ITEMS ON THE GROUND (DECISIONS #269; where they land: `crate::ground`). A kill's drops (`drop_loot`,
//! every line not marked `to_bag`) and what a player drops from their bag (`drop_item`) lie in the world
//! as `ground_item` rows. Each is its OWNER's alone for `foundation.ground_owner_s` (nobody else is even
//! sent the row: row-level security), then ANYONE's for `foundation.ground_public_s`, then gone. A player
//! picks one up within `foundation.ground_pickup_m` of it (`pick_up`); the server checks the distance
//! from where it last saw them.

use super::*;

#[table(accessor = ground_item, public)]
pub struct GroundItem {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The cell it lies in (`crate::cell`, template 1.0): what a ring client is sent by.
    #[index(btree)]
    pub chunk: u32,
    pub item_def_id: u32,
    pub qty: u32,
    /// What the stack carries (a made item's quality and handle), as in `inventory_item`.
    pub instance_data: String,
    pub pos: Vector3,
    /// The player entity it is first for; 0: anyone's from the start. Indexed: the owner's filter joins
    /// on it, and a subscription to a join on a column with no index is refused (found by the 1.0's ring
    /// test: every client but the database's owner was refused `ground_item`).
    #[index(btree)]
    pub owner_id: u64,
    /// Anyone may see it and take it.
    pub anyone: bool,
    /// When it becomes anyone's.
    pub owner_until: Timestamp,
    /// When it is gone.
    pub despawn_at: Timestamp,
}

/// Anyone sees what is anyone's ...
#[client_visibility_filter]
pub(crate) const GROUND_ITEM_ANYONES: Filter = Filter::Sql("SELECT * FROM ground_item WHERE anyone = true");
/// ... and their own, while it is only theirs.
#[client_visibility_filter]
pub(crate) const GROUND_ITEM_OWNERS: Filter = Filter::Sql(
    "SELECT g.* FROM ground_item g JOIN player p ON g.owner_id = p.entity_id WHERE p.identity = :sender",
);

/// LAY `qty` of item `item_def_id` on the ground at `pos` in world `world_id`, `owner_id`'s for now (0:
/// anyone's), for code that has decided it (a kill's loot, a dropped stack). Returns its row id.
pub fn drop_to_ground(ctx: &ReducerContext, world_id: u32, pos: Vector3, item_def_id: u32, qty: u32, instance_data: String, owner_id: u64) -> u64 {
    let own_s = hot_number(ctx, crate::hot::foundation::GROUND_OWNER_S).max(0.0);
    let public_s = hot_number(ctx, crate::hot::foundation::GROUND_PUBLIC_S).max(0.0);
    let owner_until = ctx.timestamp + TimeDuration::from_micros(if owner_id == 0 { 0 } else { (own_s * 1_000_000.0) as i64 });
    let despawn_at = owner_until + TimeDuration::from_micros((public_s * 1_000_000.0) as i64);
    ctx.db.ground_item().insert(GroundItem {
        id: 0, world_id, chunk: crate::ground::chunk_of(pos), item_def_id, qty, instance_data, pos, owner_id,
        anyone: owner_id == 0, owner_until, despawn_at,
    }).id
}

/// PICK UP ground item `ground_id`: yours or anyone's, within reach of where the server last saw you.
/// It goes into your bag as it was (a made item keeps its quality).
#[reducer]
pub fn pick_up(ctx: &ReducerContext, ground_id: u64) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    spend_rate(ctx, player.entity_id, "pick_up")?;
    let g = ctx.db.ground_item().id().find(ground_id).ok_or("it is gone")?;
    if !g.anyone && g.owner_id != player.entity_id {
        return Err("not yours (yet)".into());
    }
    let me = ctx.db.movement_state().entity_id().find(player.entity_id).ok_or("you are nowhere")?;
    if me.world_id != g.world_id {
        return Err("it is in another world".into());
    }
    let reach = hot_number(ctx, crate::hot::foundation::GROUND_PICKUP_M) as f32;
    if !crate::ground::within_reach(me.pos, g.pos, reach) {
        return Err("too far to pick up".into());
    }
    grant_stack_internal(ctx, player.entity_id, g.item_def_id, g.qty, &g.instance_data)?;
    ctx.db.ground_item().id().delete(ground_id);
    Ok(())
}

/// DROP `qty` of bag row `item_id` a step in front of you (`ground::DROP_AHEAD_M`): yours for a while (pick it
/// up again), then anyone's.
#[reducer]
pub fn drop_item(ctx: &ReducerContext, item_id: u64, qty: u32) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    spend_rate(ctx, player.entity_id, "drop_item")?;
    let mut item = ctx.db.inventory_item().id().find(item_id).ok_or("no such item")?;
    if item.owner_entity_id != player.entity_id {
        return Err("not your item".into());
    }
    if qty == 0 || qty > item.qty {
        return Err(format!("cannot drop {qty} of {}", item.qty));
    }
    let me = ctx.db.movement_state().entity_id().find(player.entity_id).ok_or("you are nowhere")?;
    let data = item.instance_data.clone();
    let def = item.item_def_id;
    if item.qty == qty {
        ctx.db.inventory_item().id().delete(item_id);
    } else {
        item.qty -= qty;
        ctx.db.inventory_item().id().update(item);
    }
    drop_to_ground(ctx, me.world_id, crate::ground::ahead_of(me.pos, me.yaw, crate::ground::DROP_AHEAD_M), def, qty, data, player.entity_id);
    Ok(())
}

/// Each second: what has been its owner's long enough becomes anyone's; what has lain its time is gone.
pub(crate) fn tick_ground(ctx: &ReducerContext) {
    let now = ctx.timestamp;
    let rows: Vec<GroundItem> = ctx.db.ground_item().iter().filter(|g| g.despawn_at <= now || (!g.anyone && g.owner_until <= now)).collect();
    for g in rows {
        if g.despawn_at <= now {
            ctx.db.ground_item().id().delete(g.id);
        } else {
            ctx.db.ground_item().id().update(GroundItem { anyone: true, ..g });
        }
    }
}
