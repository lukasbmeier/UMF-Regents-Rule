//! Small helpers the rest share. Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

use super::*;

// =============================================================================
// HELPERS
// =============================================================================

pub fn current_tick(ctx: &ReducerContext, world_id: u32) -> u64 {
    ctx.db.world_config().world_id().find(world_id).map(|w| w.server_tick).unwrap_or(0)
}
