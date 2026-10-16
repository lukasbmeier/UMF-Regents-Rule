//! TELEMETRY'S RULES (DECISIONS #244), plain Rust so `cargo test` checks them: what a performance report
//! or a piece of feedback may hold, cut to size. The tables and reducers are `module/telemetry.rs`.
//!
//! Nothing personal: a report says how the game ran (frame times, spikes, ping, corrections, memory) on
//! what sort of machine (its OS, CPU and GPU names, its memory in GB), never who someone is outside the
//! game, where they are, or what else is on their machine. Who and where in the game are the server's
//! own rows (their player, their entity, their world), not anything the client says.

/// The longest a report's free fields may be, in bytes: what a client could otherwise fill the host's
/// database with. A field over its length is cut, not refused (a report is worth keeping whole).
pub const MAX_BUILD: usize = 64;
pub const MAX_PLATFORM: usize = 200;
pub const MAX_DETAIL: usize = 4096;
pub const MAX_TEXT: usize = 2000;
pub const MAX_CONTEXT: usize = 8192;
/// A report covers at most this long (a window of 30 s by default: `foundation.telemetry_window_s`).
pub const MAX_WINDOW_S: f32 = 600.0;
/// How long the host keeps performance reports; feedback is kept until it is deleted.
pub const PERF_KEEP_MICROS: i64 = 14 * 24 * 3600 * 1_000_000;
/// The moment a player says they noticed something may be this far before the server heard it (they
/// pressed the key, then wrote); earlier is taken as this.
pub const NOTICED_BEFORE_MAX_MICROS: i64 = 30 * 60 * 1_000_000;

/// Who sent a report: a player's game, or a referee (a sidecar judging and driving bots).
pub const ROLE_CLIENT: u8 = 0;
pub const ROLE_REFEREE: u8 = 1;
/// What a piece of feedback is about.
pub const FEEDBACK_BUG: u8 = 0;
pub const FEEDBACK_LAG: u8 = 1;
pub const FEEDBACK_IDEA: u8 = 2;
pub const FEEDBACK_OTHER: u8 = 3;

/// `s` cut to at most `max` bytes, on a character boundary.
pub fn cut(s: &str, max: usize) -> String {
    if s.len() <= max {
        return s.to_string();
    }
    let mut end = max;
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    s[..end].to_string()
}

/// A number from a client as one worth storing: finite and within `[lo, hi]`, else `lo`.
pub fn sane(v: f32, lo: f32, hi: f32) -> f32 {
    if v.is_finite() { v.clamp(lo, hi) } else { lo }
}

/// When a player noticed what their feedback is about, given the moment they say (`noticed`, server
/// microseconds by their clock) and when the server heard it (`heard`): theirs, unless it is after the
/// server heard it or longer before than `NOTICED_BEFORE_MAX_MICROS` (a clock that is off).
pub fn noticed_at(noticed: i64, heard: i64) -> i64 {
    if noticed > heard || noticed < heard - NOTICED_BEFORE_MAX_MICROS { heard } else { noticed }
}

/// A feedback category as one there is (an unknown one is "other").
pub fn category(c: u8) -> u8 {
    if c <= FEEDBACK_OTHER { c } else { FEEDBACK_OTHER }
}
