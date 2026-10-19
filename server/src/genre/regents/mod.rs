//! REGENT'S RULE'S PURE RULES (docs/regents_rule/RULE_DESIGN.md). No `spacetimedb` dependency, so
//! native tests check them (`server/tests/regents.rs`); `game/regents.rs` applies them: the skilling
//! loop's numbers, what a round or an AFK log yields, and the rolls that decide rares and felling.

pub mod chop;

/// A tree to chop (`TreeSeed`, from its `TreeDef`): an entity of this kind (`content/character/tree.tres`).
pub const ENTITY_TREE: u8 = 100;
/// A round of woodcutting's branch dodge: the challenge a held E deals.
pub const CHALLENGE_CHOP: u8 = 100;
/// A tree that fell: a stump until it grows back (`content/status/felled.tres`).
pub const STATUS_FELLED: u8 = 100;
/// The frontier glade (`game/regents/levels/frontier.tscn`, its `LevelInfo`).
pub const LEVEL_FRONTIER: u8 = 20;
/// A level point's kind for a tree; its first tag names its TreeDef (case does not matter).
pub const TREE_POINT: &str = "tree";
/// What a tool works: an axe fells trees.
pub const TOOL_AXE: &str = "axe";
/// The axe a new player starts with (`content/item/bronze_axe.tres`).
pub const STARTER_AXE: u32 = 40001;

pub static CLAIMS: crate::genre::Claims = crate::genre::Claims {
    name: "regents",
    challenge_kinds: &[CHALLENGE_CHOP],
    entity_kinds: &[ENTITY_TREE],
    phases: &[],
    session_kinds: &[],
};

/// An item, as the server keeps it (`ItemDef`).
#[derive(Debug)]
pub struct ItemSeed {
    pub id: u32,
    pub name: &'static str,
    pub max_stack: u32,
    pub tool_tag: &'static str,
    pub tool_tier: u32,
}

/// A tree, as the server keeps it (`TreeDef`).
#[derive(Debug)]
pub struct TreeSeed {
    pub id: u32,
    pub name: &'static str,
    pub tier: u32,
    pub chop: chop::ChopParams,
    pub log_item: u32,
    pub min_axe_tier: u32,
    pub afk_ms_per_log: u32,
    pub fell_permille: u32,
    pub regrow_ms: u32,
    pub rare_item: u32,
    pub rare_permille: u32,
}

include!(concat!(env!("OUT_DIR"), "/regents_data.rs"));

pub fn item(id: u32) -> Option<&'static ItemSeed> {
    ITEMS.iter().find(|i| i.id == id)
}

pub fn tree(id: u32) -> Option<&'static TreeSeed> {
    TREES.iter().find(|t| t.id == id)
}

/// The tree a level point names (its first tag, any case), or None.
pub fn tree_named(name: &str) -> Option<&'static TreeSeed> {
    TREES.iter().find(|t| t.name.eq_ignore_ascii_case(name))
}

/// A roll: a number 0..1000 from `salt` (splitmix64), so a result is reproducible in a test and still
/// unguessable in play (the server salts with its own clock and ids).
pub fn roll_permille(salt: u64) -> u32 {
    let mut z = salt.wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^= z >> 31;
    (z % 1000) as u32
}

/// How many logs an active round yields, in thousandths of a log: what AFK makes in the round's time,
/// times `active_mult`, times the round's score (owner, 2026-10-18, design #23: a poor round falls
/// short of AFK).
pub fn active_yield_milli(t: &TreeSeed, active_mult: f64, score_pm: i64) -> u64 {
    let afk_milli = t.chop.duration_ms as f64 * 1000.0 / t.afk_ms_per_log as f64;
    (afk_milli * active_mult * score_pm.clamp(0, 1000) as f64 / 1000.0).floor().max(0.0) as u64
}

/// Thousandths of a log into whole logs: the whole part, and one more when `roll` (0..1000) falls under
/// the fraction.
pub fn whole_logs(milli: u64, roll: u32) -> u32 {
    (milli / 1000) as u32 + u32::from(((milli % 1000) as u32) > roll)
}

/// One log's outcome: whether it brings the rare find (its chance, times `rare_mult` when played) and
/// whether it is the last (the tree falls), from two rolls.
pub fn log_outcome(t: &TreeSeed, rare_mult: f64, rare_roll: u32, fell_roll: u32) -> (bool, bool) {
    let rare_pm = (t.rare_permille as f64 * rare_mult).round() as u32;
    (t.rare_item != 0 && rare_roll < rare_pm, fell_roll < t.fell_permille)
}
