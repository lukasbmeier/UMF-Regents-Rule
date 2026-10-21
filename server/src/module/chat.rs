//! CHAT (DECISIONS #273; what a line may say: `crate::chat`). A player says a line to the world they are
//! in (`send_chat`); it is a `chat_message` row every client in that world is sent (it is a world table:
//! `InterestManager`), shown in their chat box and over the speaker's head. A world keeps its last
//! `chat::MAX_KEPT` lines for `foundation.chat_keep_s`, so someone arriving sees what was just said.

use super::*;

#[table(accessor = chat_message, public)]
pub struct ChatMessage {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// Who said it: their entity (their head the line shows over) ...
    pub entity_id: u64,
    /// ... and their name as it was then.
    pub name: String,
    pub text: String,
    pub at: Timestamp,
}

/// SAY `text` to everyone in your world. Refused when there is nothing to say, or too often.
#[reducer]
pub fn send_chat(ctx: &ReducerContext, text: String) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let text = crate::chat::clean(&text).ok_or("nothing to say")?;
    spend_rate(ctx, player.entity_id, "send_chat")?;
    let world_id = ctx.db.movement_state().entity_id().find(player.entity_id).map(|m| m.world_id).unwrap_or(DEFAULT_WORLD);
    ctx.db.chat_message().insert(ChatMessage { id: 0, world_id, entity_id: player.entity_id, name: player.name.clone(), text, at: ctx.timestamp });
    let kept: Vec<(i64, u64)> = ctx.db.chat_message().world_id().filter(world_id).map(|m| (m.at.to_micros_since_unix_epoch(), m.id)).collect();
    for id in crate::chat::overflow(kept) {
        ctx.db.chat_message().id().delete(id);
    }
    Ok(())
}

/// Each second: lines older than `foundation.chat_keep_s` are gone.
pub(crate) fn prune_chat(ctx: &ReducerContext) {
    let keep_s = hot_number(ctx, crate::hot::foundation::CHAT_KEEP_S).max(0.0);
    let cutoff = ctx.timestamp - TimeDuration::from_micros((keep_s * 1_000_000.0) as i64);
    let old: Vec<u64> = ctx.db.chat_message().iter().filter(|m| m.at < cutoff).map(|m| m.id).collect();
    for id in old {
        ctx.db.chat_message().id().delete(id);
    }
}
