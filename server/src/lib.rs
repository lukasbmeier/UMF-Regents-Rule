//! Universal Multiplayer Foundation — SpacetimeDB module.
//!
//! Layout
//!   sim.rs      frozen gravity-only twin for MODULE-authority (Tier A) idle handling + wire types
//!   challenge.rs pure challenge validators with a GDScript twin + golden vectors
//!   module/    tables + reducers, one file per system (wasm32 only)
//!   lib.rs   crate root (this file)
//!
//! Motion authority per world (docs/SIDECAR_SPEC.md):
//!   MODULE  — this module simulates gravity-only and trusts `client_pos` within a radius.
//!   SIDECAR — a headless Godot process simulates; `tick_movement` only prunes stale inputs.
//!             Phase 3 Task 1 adds the `authority` table and authority-only reducers.
//!
//! API: SpacetimeDB 2.10 Rust module API (docs.rs/spacetimedb 2.10.0, verified):
//!   `#[table(accessor = ...)]`, `ctx.sender()` / `ctx.database_identity()` are methods,
//!   `ctx.timestamp` is a field, `ScheduleAt` is built via `.into()` from a TimeDuration,
//!   `RangedIndex::filter/delete` for `#[index(btree)]`, `UniqueColumn::find/update/delete`.

pub mod sim;

/// Challenge validators. Pure, like `sim`, and for the same reason (DECISIONS #27).
pub mod challenge;

/// Level bakes (spawn, water depth, named spots) compiled in from `shared/world/`. Pure.
pub mod level;

/// Statuses (DECISIONS #206): what each one lets an entity do, baked from `StatusDef` content. Pure.
pub mod status;
pub mod hold;

/// The content the module seeds, baked in the editor (`tools/bake_content.gd`) and compiled in by
/// build.rs from `shared/content/` (DECISIONS #199).
pub mod content {
    include!(concat!(env!("OUT_DIR"), "/content.rs"));
    include!(concat!(env!("OUT_DIR"), "/movement_limits.rs"));
    include!(concat!(env!("OUT_DIR"), "/kind_abilities.rs"));
}

/// THE HOT RULES (DECISIONS #201): numbers the game is tuned by while it runs, declared in rule sets
/// (`foundation/content/rules/`, a genre's), baked, and compiled in here as this game's defaults.
/// The module serves each in the `hot_rule` table, where an admin may change it (`set_rule`);
/// reducers read the live value (`module::hot_number`). Pure, so the native suites check them.
pub mod hot {
    /// What a rule holds.
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    pub enum Kind { Number, Integer, Flag, Text }

    /// One rule: its key (`<owner>.<name>`), its kind, this game's default and its bounds.
    #[derive(Debug)]
    pub struct Rule {
        pub key: &'static str,
        pub kind: Kind,
        pub number: f64,
        pub text: &'static str,
        pub min: f64,
        pub max: f64,
    }

    impl Rule {
        /// Whether `number` may be this rule's value (what `set_rule` accepts).
        pub fn check(&self, number: f64) -> Result<(), String> {
            match self.kind {
                Kind::Text => Ok(()),
                _ if !number.is_finite() => Err(format!("{}: not a number", self.key)),
                Kind::Flag if number != 0.0 && number != 1.0 => Err(format!("{}: a flag is 0 or 1", self.key)),
                Kind::Integer if number.fract() != 0.0 => Err(format!("{}: a whole number", self.key)),
                _ if number < self.min || number > self.max => {
                    Err(format!("{}: {} is outside {}..{}", self.key, number, self.min, self.max))
                }
                _ => Ok(()),
            }
        }
    }

    /// A rule by key.
    pub fn find(key: &str) -> Option<&'static Rule> {
        ALL.iter().find(|r| r.key == key)
    }

    include!(concat!(env!("OUT_DIR"), "/hot_rules.rs"));
}

/// PLAYER NAMES (DECISIONS #202): unique, ignoring case. Pure, so the native suites check it.
pub mod names {
    /// `name` if nobody holds it, else "<name> 2", "<name> 3"... (cut to fit `max_len` characters).
    pub fn free(name: &str, max_len: usize, taken: impl Fn(&str) -> bool) -> String {
        if !taken(name) {
            return name.to_string();
        }
        let mut n = 2;
        loop {
            let suffix = format!(" {n}");
            let base: String = name.chars().take(max_len.saturating_sub(suffix.chars().count())).collect();
            let candidate = format!("{}{suffix}", base.trim_end());
            if !taken(&candidate) {
                return candidate;
            }
            n += 1;
        }
    }
}

/// Constants baked from shared/movement_config.json by build.rs.
pub mod movement_config {
    include!(concat!(env!("OUT_DIR"), "/movement_config.rs"));
}

/// The foundation's rules as the game sets them (health, interact range, round plans), baked
/// from shared/rules.json by build.rs (DECISIONS #154).
pub mod rules {
    include!(concat!(env!("OUT_DIR"), "/rules.rs"));

    /// A session kind's phases, in order, with their lengths in microseconds (0: held).
    pub fn plan(kind: u8) -> Option<&'static [(u8, i64)]> {
        SESSION_PLANS.iter().find(|(k, _)| *k == kind).map(|(_, p)| *p)
    }

    /// A session kind's lobby: ready-up, the players it needs, its teams (DECISIONS #174).
    pub struct Lobby {
        pub kind: u8,
        pub ready_up: bool,
        pub min_players: u16,
        pub teams: &'static [&'static str],
    }

    pub fn lobby(kind: u8) -> Option<&'static Lobby> {
        LOBBIES.iter().find(|l| l.kind == kind)
    }

    /// A session kind's match rules (DECISIONS #182): how long its first lobby waits (0: for
    /// everyone to be ready, or the lobby's own seconds without ready-up), and how long a world
    /// may have no player online before its match ends.
    pub struct MatchRules {
        pub kind: u8,
        pub wait_micros: i64,
        pub end_after_empty_micros: i64,
    }

    impl MatchRules {
        pub const DEFAULT: MatchRules = MatchRules { kind: 0, wait_micros: 0, end_after_empty_micros: 60_000_000 };
    }

    pub fn match_rules(kind: u8) -> &'static MatchRules {
        MATCHES.iter().find(|m| m.kind == kind).unwrap_or(&MatchRules::DEFAULT)
    }

    /// How often one player may call a reducer (REVIEW 0.23.1 B3): `burst` calls at once, the
    /// allowance coming back at `per_sec`. A token bucket rather than a minimum interval, because an
    /// honest client sends some things in quick pairs (a fight's tell changing twice in a frame).
    pub struct RateLimit {
        pub verb: &'static str,
        pub burst: f32,
        pub per_sec: f32,
    }

    pub fn rate_limit(verb: &str) -> &'static RateLimit {
        RATE_LIMITS.iter().find(|r| r.verb == verb).unwrap_or(&RATE_DEFAULT)
    }

    /// One call against a budget that held `tokens` `elapsed_s` seconds ago (None: a fresh one,
    /// full). The tokens left after it, or None when the call is over the limit.
    pub fn rate_spend(tokens: Option<f32>, elapsed_s: f64, limit: &RateLimit) -> Option<f32> {
        let refilled = match tokens {
            None => limit.burst,
            Some(t) => (t as f64 + elapsed_s.max(0.0) * limit.per_sec as f64).min(limit.burst as f64) as f32,
        };
        if refilled < 1.0 {
            return None;
        }
        Some(refilled - 1.0)
    }
}

/// Tables + reducers. wasm32-only: see module/mod.rs for why.
/// `pub` so the genre layer can use its types; the dependency runs one way only —
/// `game` imports from `module`, never the reverse (docs/TEMPLATE_WORKFLOW.md).
#[cfg(target_arch = "wasm32")]
pub mod module;

/// The genre layer. Delete this directory and the foundation still stands.
#[cfg(target_arch = "wasm32")]
pub mod game;

/// The genre layer's pure half: rolls, timings and validators with no database, so they are
/// tested natively. Goes with `game/`; the foundation never imports from either.
pub mod genre;
