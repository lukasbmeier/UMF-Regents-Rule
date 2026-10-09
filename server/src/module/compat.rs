//! THE COMPATIBILITY GENERATION (docs/rules/compatibility.md, DECISIONS #198). build.rs writes
//! `compat_generation_<N>` from shared/game.json `compat`; bump it for a deliberate break (a change
//! to what clients simulate, or a reshaped table), and every older build is told plainly to update.

include!(concat!(env!("OUT_DIR"), "/compat.rs"));
