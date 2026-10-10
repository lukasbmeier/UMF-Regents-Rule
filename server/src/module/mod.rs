//! Tables and reducers — the SpacetimeDB module proper.
//!
//! Compiled ONLY for wasm32 (see lib.rs). Linking the SpacetimeDB host ABI
//! (`datastore_insert_bsatn`, `console_log`, …) into a native binary is impossible, and
//! `cargo test --test golden` links the whole crate. Gating this module is what lets the
//! golden harness run natively against `sim.rs` while `spacetime build` still gets everything.
//!
//! Type-check this file with:  cargo check --target wasm32-unknown-unknown
//!
//! SPLIT BY SYSTEM (REVIEW 0.23.1 C2): one file per section below; each opens with `use super::*`,
//! and this file re-exports them all, so `crate::module::<item>` reaches anything, as before.

pub(crate) use crate::sim::{InputFrame, MovementState, Vector3};
pub(crate) use spacetimedb::{client_visibility_filter, reducer, table, Filter, Identity, ReducerContext,
    ScheduleAt, SpacetimeType, Table, TimeDuration, Timestamp};

// `spacetimedb` is pinned in Cargo.toml to the server's exact version (DECISIONS #190).

mod constants;
pub use constants::*;
mod tables;
pub use tables::*;
mod actions;
pub use actions::*;
mod lifecycle;
pub use lifecycle::*;
mod movement;
pub use movement::*;
mod authorities;
pub use authorities::*;
mod sessions;
pub use sessions::*;
mod items;
pub use items::*;
mod challenges;
pub use challenges::*;
mod interaction;
pub use interaction::*;
mod helpers;
pub use helpers::*;
mod compat;
pub use compat::*;
mod hot_rules;
pub use hot_rules::*;
mod statuses;
pub use statuses::*;
mod holds;
pub use holds::*;
mod presses;
pub use presses::*;
