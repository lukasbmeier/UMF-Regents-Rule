//! interact and resource nodes. Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

use super::*;

// =============================================================================
// INTERACTION
// =============================================================================

/// Player intent: "use that thing". The client's raycast is a prompt, not a permission — the
/// range check here is the real one, because the raycast runs on a machine the player owns.
///
/// Dispatch is by target `entity.kind`, which is how a genre extends this: add a kind, add an
/// arm. Phase 3 ships RESOURCE_NODE, which issues the timing-bar Challenge.
#[reducer]
pub fn interact(ctx: &ReducerContext, target_id: u64, verb: u8) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    require_can_act(ctx, player.entity_id, "interact")?;
    let me = ctx
        .db
        .movement_state()
        .entity_id()
        .find(player.entity_id)
        .ok_or("interact: you have no movement_state")?;
    let target = ctx
        .db
        .entity()
        .entity_id()
        .find(target_id)
        .ok_or("interact: no such entity")?;
    // A player who is not connected is not in the world (DECISIONS #202).
    if ctx.db.player().entity_id().find(target_id).is_some_and(|p| !p.online) {
        return Err("interact: they are not here".into());
    }
    if !is_targetable(ctx, target_id) {
        return Err("interact: they cannot be reached".into());
    }
    let target_pos = ctx
        .db
        .movement_state()
        .entity_id()
        .find(target_id)
        .ok_or("interact: target has no movement_state")?;

    if me.world_id != target_pos.world_id {
        return Err("interact: target is in another world".into());
    }
    let d2 = me.pos.sub(target_pos.pos).length_sq();
    let range = hot_number(ctx, crate::hot::foundation::INTERACT_RANGE_M) as f32;
    if d2 > range * range {
        return Err(format!(
            "interact: out of range ({:.2} m > {:.2} m)",
            d2.sqrt(),
            range
        ));
    }

    match target.kind {
        entity_kind::RESOURCE_NODE => {
            // Difficulty rises with the verb so a genre can offer "careful" vs "quick"
            // without another reducer. Payload names the node so the client can theme it.
            // A SERVER-TIMED PRESS (DECISIONS #210): judged by the server's clock, not by where the
            // client says it stopped the marker.
            let difficulty = if verb > 0 { 0.75f32 } else { 0.35f32 };
            let payload = format!("{{\"node\":{target_id},\"verb\":{verb}}}");
            issue_challenge_internal(
                ctx,
                player.entity_id,
                crate::challenge::KIND_TIMED_PRESS,
                difficulty,
                payload,
                CHALLENGE_TTL_MICROS,
            )?;
            Ok(())
        }
        entity_kind::PLAYER | entity_kind::NPC => {
            Err("interact: nothing to do with that entity".into())
        }
        // A GENRE'S OWN KIND (DECISIONS #154): range and world are checked above; what using it
        // means is the genre's. None: no genre claims the kind.
        other => crate::game::on_interact(ctx, player.entity_id, &target, verb)
            .unwrap_or_else(|| Err(format!("interact: no game handles entity kind {other}"))),
    }
}

/// Dev helper: place a resource node in the world so the interact path can be exercised
/// before a genre ships its own spawning.
#[reducer]
pub fn spawn_resource_node(
    ctx: &ReducerContext,
    world_id: u32,
    pos: Vector3,
) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    let ent = ctx.db.entity().insert(Entity {
        entity_id: 0,
        world_id,
        chunk: 0,
        kind: entity_kind::RESOURCE_NODE,
        owner: ctx.sender(),
        spawned_at: ctx.timestamp,
    });
    insert_movement(ctx, MovementStateRow {
        entity_id: ent.entity_id,
        world_id,
        chunk: 0,
        pos,
        vel: Vector3::ZERO,
        yaw: 0.0,
        grounded: true,
        move_state: 0,
        last_processed_seq: 0,
        server_tick: current_tick(ctx, world_id),
        server_ts: ctx.timestamp,
        teleport_flag: true,
        correction_epoch: 0,
    });
    Ok(())
}
