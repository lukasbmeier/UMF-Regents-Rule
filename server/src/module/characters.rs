//! CHOOSING A CHARACTER (DECISIONS #217): which character a player plays, as the kind of their entity.
//! A character a player may choose is content (`EntityDefinition.playable`, baked into
//! `content::PLAYABLE_KINDS`); every client builds the entity again from its new kind (its model, body,
//! movement, camera), and the server bounds its movement by the new kind's. A genre decides who may be
//! what (`game::may_choose_character`: one predator a night) and what follows (`on_character_changed`:
//! the predator's team). `mod.rs` says why the module is wasm-only.

use super::*;

/// THE PLAYER CHOOSES TO PLAY `kind` (a playable character's). In the lobby, between rounds; an admin
/// may change at any time (to try a character out). The same kind again: nothing to do.
#[reducer]
pub fn choose_character(ctx: &ReducerContext, kind: u8) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("choose_character: no player row")?;
    spend_rate(ctx, player.entity_id, "choose_character")?;
    if !crate::content::is_playable(kind) {
        return Err(format!("choose_character: kind {kind} is not a character you can play"));
    }
    let ent = ctx.db.entity().entity_id().find(player.entity_id).ok_or("choose_character: you have no entity")?;
    if ent.kind == kind {
        return Ok(());
    }
    if require_admin(ctx).is_err() {
        let (sess, _) = lobby_of(ctx, player.entity_id, "choose_character")?;
        if sess.phase != PHASE_LOBBY {
            return Err("choose_character: characters are chosen in the lobby".into());
        }
    }
    crate::game::may_choose_character(ctx, player.entity_id, kind)?;
    set_character_internal(ctx, player.entity_id, kind)
}

/// AUTHORITY: make `entity_id` (anyone's, a bot's) a `kind`, playable or not: the sidecar making a bot a
/// wolf, an admin's tools, a game's suite handing the foundation's checks a plain player (kind 0) when
/// the game starts its players as something else. A genre's `may_choose_character` is not asked.
#[reducer]
pub fn set_character_of(ctx: &ReducerContext, entity_id: u64, kind: u8) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("set_character_of: no such entity")?;
    require_authority(ctx, ent.world_id)?;
    set_character_internal(ctx, entity_id, kind)
}

/// Make `entity_id` a `kind` (a genre's code: a new player starts as a hen; a bot is made a wolf). It
/// lets go of what it was holding (a hen's nest is not a wolf's), and every genre hears it.
pub fn set_character_internal(ctx: &ReducerContext, entity_id: u64, kind: u8) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("set_character: no such entity")?;
    let from = ent.kind;
    if from == kind {
        return Ok(());
    }
    let_go(ctx, entity_id, crate::hold::left::TARGET_CHANGED);
    ctx.db.entity().entity_id().update(Entity { kind, ..ent });
    log::info!("entity {entity_id}: now plays kind {kind} (was {from})");
    crate::game::on_character_changed(ctx, entity_id, from);
    Ok(())
}
