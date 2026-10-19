//! REGENT'S RULE'S PURE RULES (docs/regents_rule/RULE_DESIGN.md). No `spacetimedb` dependency, so
//! native tests can check them; `game/regents.rs` applies them. Empty until the skilling loop's
//! server half: the woodcutting minigame is played and tuned on the client first
//! (`game/regents/skilling/woodcutting/`), then its model gets its Rust twin here.

pub static CLAIMS: crate::genre::Claims = crate::genre::Claims {
    name: "regents",
    challenge_kinds: &[],
    entity_kinds: &[],
    phases: &[],
    session_kinds: &[],
};
