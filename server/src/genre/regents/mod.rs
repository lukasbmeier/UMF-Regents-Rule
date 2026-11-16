//! REGENT'S RULE'S PURE RULES (docs/regents_rule/RULE_DESIGN.md §7.4). No `spacetimedb` dependency, so
//! native tests check them (`server/tests/regents.rs`); `game/regents.rs` applies them: the skilling
//! chain's content (compiled in from game/regents/content/ by `server/build/regents.rs`), its four
//! minigames' replays, mastery ranks, a tool's speed, what a round or an AFK item yields, and the rolls.

pub mod beat;
pub mod carve;
pub mod chop;
pub mod crack;
pub mod pull;
pub mod rng;
pub mod shape;
pub mod skin;
pub mod smelt;

/// A gathering node (a tree, a rock: `NodeSeed`), an entity of this kind (`content/character/node.tres`).
pub const ENTITY_NODE: u8 = 100;
/// A station (a furnace, an anvil, a workbench: `StationSeed`).
pub const ENTITY_STATION: u8 = 101;
/// The challenge kinds the minigames are dealt as (`SkillMinigames.CHALLENGE` on the client).
pub const CHALLENGE_CHOP: u8 = 100;
pub const CHALLENGE_CRACK: u8 = 101;
pub const CHALLENGE_SMELT: u8 = 102;
pub const CHALLENGE_SHAPE: u8 = 103;
/// Smelting as a rhythm track (Luke, 2026-11-07): a new kind, so a client that only knows `CHALLENGE_SMELT` ignores it.
pub const CHALLENGE_BEAT: u8 = 104;
/// Woodworking's carve (Luke, 2026-11-07): a vertical stave, wood off either side.
pub const CHALLENGE_CARVE: u8 = 105;
/// Herbalism's pull the root (HERBALISM_HUNTING_PREP.md §3, Luke's H3, 2026-11-07): hold to pull, mind the strain; the
/// trowel digs round each stem and cuts its side roots (2026-11-08).
pub const CHALLENGE_PULL: u8 = 106;
/// Skinning's cut line (HERBALISM_HUNTING_PREP.md H4, Luke 2026-11-07): drag the knife along the line; off it tears the hide.
pub const CHALLENGE_SKIN: u8 = 107;
/// A node worked out: a stump, rubble, until it comes back (`content/status/depleted.tres`).
pub const STATUS_DEPLETED: u8 = 100;
/// The frontier glade (`game/regents/levels/frontier.tscn`, its `LevelInfo`).
pub const LEVEL_FRONTIER: u8 = 20;
/// A level point's kinds; its first tag names the node (by name) or the station (by key), any case.
pub const NODE_POINT: &str = "node";
pub const STATION_POINT: &str = "station";
/// The order board's station key (`content/station/`), and how many orders it shows.
pub const ORDER_BOARD: &str = "orders";
pub const ORDER_SLOTS: u32 = 3;
/// What a new character is given, once (`content/item/`): a Copper axe, a Copper pickaxe, (2026-11-07, herbalism) a
/// Copper trowel and (2026-11-09, skinning) a Copper knife.
pub const STARTER_KIT: &[u32] = &[40001, 40006, 40051, 40059];

pub static CLAIMS: crate::genre::Claims = crate::genre::Claims {
    name: "regents",
    challenge_kinds: &[CHALLENGE_CHOP, CHALLENGE_CRACK, CHALLENGE_SMELT, CHALLENGE_SHAPE, CHALLENGE_BEAT, CHALLENGE_CARVE, CHALLENGE_PULL, CHALLENGE_SKIN],
    // The foes' kinds are content (`FoeDef`, `content/foe/`): the genre keeps 103-119 for them (FOE_KINDS).
    entity_kinds: &[ENTITY_NODE, ENTITY_STATION, ENTITY_DUMMY, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116,
        117, 118, 119, ENTITY_GUIDE],
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
    pub tool_speed_pct: u32,
    /// The kit it fights with ("sword", "axe"; empty: not a weapon), and its damage in percent.
    pub weapon_kit: &'static str,
    pub weapon_damage_pct: u32,
    /// A part's kind ("handle"): a recipe's part slot takes any item of the same kind.
    pub part_tag: &'static str,
    /// As a part: the trait it offers a TOOL it is made into (a `traits::TRAITS` id; 0: none).
    pub handle_trait: u32,
    /// As a part: the trait it offers a WEAPON (owner, 2026-10-23: oak Heavy, iron rivets Brutal; 0: none).
    pub weapon_trait: u32,
    /// As ammo: the kit it is shot from ("bow"; empty: not ammo), and its hits in percent.
    pub ammo_for: &'static str,
    pub ammo_damage_pct: u32,
    /// As a handle: the role its SHAPE gives the weapon made with it (a `RoleSeed` id; 0: none, the plain one).
    pub role: u32,
    /// As a part: the one kit it fits ("sword": a hilt; empty: any made of its kind).
    pub fits_kit: &'static str,
    /// As ARMOR (S2): the slot it is worn in ("head", "chest", "legs", "trinket"; empty: not armor), and its Defense
    /// at quality 0 (`piece_defense`).
    pub armor_slot: &'static str,
    pub defense: u32,
    /// As a CHEST (S4, B8): the ability it gives on F while worn (an `AbilityDef` id; 0: none, F free).
    pub worn_ability: u32,
}

/// A ROLE (`RoleDef`, COMBAT_OVERHAUL.md §5, Luke 2026-11-01): what a weapon is for, by its handle's SHAPE.
/// What every weapon of it shares: its held guard and its threat. Its name is for code: the player sees a badge.
#[derive(Debug)]
pub struct RoleSeed {
    pub id: u32,
    pub key: &'static str,
    /// The role of a weapon whose handle names none (the plain grip, an old item). One role.
    pub plain: bool,
    /// A held block takes `regents.block_damage_pct` of a hit in front; else `regents.weak_block_pct`.
    pub full_block: bool,
    /// THREAT (stored for step 6): its damage and healing count this % toward a foe's choice, unless
    /// `threat_rule` (a hot rule's key) sets it live; `threat_scope_rule` (a hot flag), on, keeps it to bosses.
    pub threat_pct: u32,
    pub threat_rule: &'static str,
    pub threat_scope_rule: &'static str,
    /// A hot rule's key: its weight when a dropped weapon rolls its handle's shape ("": never rolled).
    pub drop_rule: &'static str,
}

/// One entry of a kit's ROLE MAP (`KitRole`): the string's last hit for weapons of `role`, and what it does
/// besides its damage.
#[derive(Debug)]
pub struct RoleFinisher {
    pub role: u32,
    pub ability: u32,
    /// Its stagger, % of `regents.stagger_ms` (before the Heavy trait's).
    pub stagger_pct: u32,
    /// Landing, it heals players within `heal_radius_m` of its user this much (0: none), once a swing.
    pub heal: f32,
    pub heal_radius_m: f32,
}

/// What a kit's ability does when it lands unblocked (`KitHit`, Luke 2026-11-10: the wolf's hamstring bite slows;
/// its lunge throws back).
#[derive(Debug)]
pub struct KitHitSeed {
    pub ability: u32,
    pub push_mps: f32,
    pub status: u8,
    pub status_ms: u32,
}

/// A skill (`SkillDef`): XP to reach each rank from 2 up.
#[derive(Debug)]
pub struct SkillSeed {
    pub id: u32,
    pub key: &'static str,
    pub name: &'static str,
    pub xp_to_rank: &'static [u32],
}

/// Smithing's shape params as content keeps them (its outline a static slice).
#[derive(Debug)]
pub struct ShapeSeed {
    pub duration_ms: i64,
    pub swing_ms: i64,
    pub heat_ms: i64,
    pub reheat_ms: i64,
    pub start_height: i64,
    pub start_jitter: i64,
    pub hammer_drop: i64,
    pub spread_pct: i64,
    pub tap_drop: i64,
    pub tap_spread_pct: i64,
    pub outline: &'static [i64],
    pub error_scale: i64,
    pub max_reheats: i64,
    pub reheat_cost_pm: i64,
    pub hide_outline: i64,
    pub lay_cost_pm: i64,
    pub outline_vary: i64,
    pub red_ms: i64,
    pub crack_cost_pm: i64,
    pub quench_lo_pm: i64,
    pub quench_hi_pm: i64,
    pub quench_bonus_pm: i64,
    pub quench_loss_pm: i64,
}

impl ShapeSeed {
    pub fn params(&self) -> shape::ShapeParams {
        shape::ShapeParams {
            duration_ms: self.duration_ms,
            swing_ms: self.swing_ms,
            heat_ms: self.heat_ms,
            reheat_ms: self.reheat_ms,
            start_height: self.start_height,
            start_jitter: self.start_jitter,
            hammer_drop: self.hammer_drop,
            spread_pct: self.spread_pct,
            tap_drop: self.tap_drop,
            tap_spread_pct: self.tap_spread_pct,
            outline: self.outline.to_vec(),
            error_scale: self.error_scale,
            max_reheats: self.max_reheats,
            reheat_cost_pm: self.reheat_cost_pm,
            hide_outline: self.hide_outline,
            lay_cost_pm: self.lay_cost_pm,
            outline_vary: self.outline_vary,
            red_ms: self.red_ms,
            crack_cost_pm: self.crack_cost_pm,
            quench_lo_pm: self.quench_lo_pm,
            quench_hi_pm: self.quench_hi_pm,
            quench_bonus_pm: self.quench_bonus_pm,
            quench_loss_pm: self.quench_loss_pm,
        }
    }
}

/// A node's or a recipe's round (`SkillMinigames` on the client).
#[derive(Debug)]
pub enum Minigame {
    None,
    Chop(chop::ChopParams),
    Crack(crack::CrackParams),
    Smelt(smelt::SmeltParams),
    Shape(ShapeSeed),
    Beat(beat::BeatParams),
    Carve(carve::CarveParams<'static>),
    Pull(pull::PullParams),
    Skin(skin::SkinParams),
}

impl Minigame {
    /// The challenge kind it is dealt as (0: none).
    pub fn challenge_kind(&self) -> u8 {
        match self {
            Minigame::None => 0,
            Minigame::Chop(_) => CHALLENGE_CHOP,
            Minigame::Crack(_) => CHALLENGE_CRACK,
            Minigame::Smelt(_) => CHALLENGE_SMELT,
            Minigame::Shape(_) => CHALLENGE_SHAPE,
            Minigame::Beat(_) => CHALLENGE_BEAT,
            Minigame::Carve(_) => CHALLENGE_CARVE,
            Minigame::Pull(_) => CHALLENGE_PULL,
            Minigame::Skin(_) => CHALLENGE_SKIN,
        }
    }

    /// How long a round lasts.
    pub fn duration_ms(&self) -> i64 {
        match self {
            Minigame::None => 0,
            Minigame::Chop(p) => p.duration_ms,
            Minigame::Crack(p) => p.duration_ms,
            Minigame::Smelt(p) => p.heat_ms + p.pour_ms,
            Minigame::Shape(p) => p.duration_ms,
            Minigame::Beat(p) => p.duration_ms(),
            Minigame::Carve(p) => p.duration_ms,
            Minigame::Pull(p) => p.duration_ms,
            Minigame::Skin(p) => p.duration_ms,
        }
    }

    /// A round REPLAYED from what the client sent, at tool speed `speed_pct` (a gathering round's swing:
    /// `SkillMinigames.with_speed`): its score in thousandths, or None when the submission is not a round.
    pub fn score(&self, seed: u64, speed_pct: i64, result: &[f32]) -> Option<i64> {
        self.score_eased(seed, speed_pct, 0, result)
    }

    /// `score`, the round EASED by `ease_pct` (Luke's M3, 2026-11-05: rank above the requirement widens a round's
    /// windows a few percent, capped; `rank_ease_pct`; the client's `SkillMinigames.eased`, which must agree): a branch
    /// staggers for less, the rock's notch is wider, the furnace's band or the beat's windows wider (the outer window
    /// never past a quarter beat), the anvil's bar hot longer and its error scale larger (the same error costs less), a
    /// root's catches jump the strain less.
    pub fn score_eased(&self, seed: u64, speed_pct: i64, ease_pct: i64, result: &[f32]) -> Option<i64> {
        let groups = (self.duration_ms() / 50 + 64) as usize;
        let swing = |s: i64| (s * speed_pct / 100).max(50);
        let e = ease_pct.clamp(0, 50);
        let wider = |v: i64| v * (100 + e) / 100;
        let narrower = |v: i64| v * (100 - e) / 100;
        match self {
            Minigame::None => None,
            Minigame::Chop(p) => {
                let p = chop::ChopParams { swing_ms: swing(p.swing_ms), stagger_ms: narrower(p.stagger_ms), ..*p };
                let ins = rng::decode_groups(result, 2, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i32)> = ins.iter().map(|g| (g[0], g[1] as i32)).collect();
                Some(chop::play(seed, &p, &ins).score_pm)
            }
            Minigame::Crack(p) => {
                let p = crack::CrackParams { swing_ms: swing(p.swing_ms), radius_pm: wider(p.radius_pm), ..*p };
                let ins = rng::decode_groups(result, 3, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i64, i64)> = ins.iter().map(|g| (g[0], g[1], g[2])).collect();
                Some(crack::play(seed, &p, &ins).score_pm)
            }
            Minigame::Smelt(p) => {
                let p = smelt::SmeltParams { band_half_start: wider(p.band_half_start), band_half_end: wider(p.band_half_end), ..*p };
                let ins = rng::decode_groups(result, 2, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i64)> = ins.iter().map(|g| (g[0], g[1])).collect();
                Some(smelt::play(seed, &p, &ins).score_pm)
            }
            Minigame::Shape(s) => {
                let mut sp = s.params();
                sp.error_scale = wider(sp.error_scale);
                sp.heat_ms = wider(sp.heat_ms);   // the bar stays workable longer: fewer reheats, a higher ceiling
                let ins = rng::decode_groups(result, 2, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i64)> = ins.iter().map(|g| (g[0], g[1])).collect();
                Some(shape::play(seed, &sp, &ins).score_pm)
            }
            Minigame::Beat(p) => {
                let good = wider(p.good_ms).min(p.beat_ms / 4).max(p.good_ms);
                let p = beat::BeatParams { perfect_ms: wider(p.perfect_ms).min(good), good_ms: good, ..*p };
                let ins = rng::decode_groups(result, 2, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i64)> = ins.iter().map(|g| (g[0], g[1])).collect();
                Some(beat::play(seed, &p, &ins).score_pm)
            }
            Minigame::Carve(p) => {
                let p = carve::CarveParams { error_scale: wider(p.error_scale), ..*p };
                let ins = rng::decode_groups(result, 2, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i64)> = ins.iter().map(|g| (g[0], g[1])).collect();
                Some(carve::play(seed, &p, &ins).score_pm)
            }
            Minigame::Pull(p) => {
                // A faster trowel strokes faster (dig, cut); rank eases the side roots' jumps and the packed soil's hold.
                let p = pull::PullParams { stroke_ms: swing(p.stroke_ms), jump_lo: narrower(p.jump_lo),
                    jump_hi: narrower(p.jump_hi), hold_pm: narrower(p.hold_pm), ..*p };
                let ins = rng::decode_groups(result, 2, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i64)> = ins.iter().map(|g| (g[0], g[1])).collect();
                Some(pull::play(seed, &p, &ins).score_pm)
            }
            Minigame::Skin(p) => {
                // A better knife cuts faster; rank widens how far off the line it still cuts.
                let p = skin::SkinParams { cut_speed: (p.cut_speed * 100 / speed_pct.max(1)).max(1), near: wider(p.near), ..*p };
                let ins = rng::decode_groups(result, 3, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i64, i64)> = ins.iter().map(|g| (g[0], g[1], g[2])).collect();
                Some(skin::play(seed, &p, &ins).score_pm)
            }
        }
    }
}

/// A gathering node (`NodeDef`).
#[derive(Debug)]
pub struct NodeSeed {
    pub id: u32,
    pub name: &'static str,
    pub skill: u32,
    pub tier: u32,
    pub minigame: Minigame,
    pub yield_item: u32,
    pub tool_tag: &'static str,
    pub min_tool_tier: u32,
    pub min_rank: u32,
    pub xp: u32,
    pub afk_ms: u32,
    pub deplete_permille: u32,
    pub regrow_ms: u32,
    pub rare_item: u32,
    pub rare_permille: u32,
    /// Each model's drawn footprint (cm), by the model a node of an entity shows (`entity_id % len`): the work reach
    /// is measured from a node's edge (Luke, 2026-11-06). Empty: from its middle.
    pub radii_cm: &'static [u32],
    /// The most it gives before it is worked out (0: no cap): a carcass's hides.
    pub max_items: u32,
    /// A played round works the WHOLE node (a carcass skinned in one round): paid by `whole_round_items`, then worked out.
    pub whole_round: bool,
}

impl NodeSeed {
    /// The footprint (m) of the node of entity `entity_id`: its model's, as the client picks it.
    pub fn radius_m(&self, entity_id: u64) -> f32 {
        if self.radii_cm.is_empty() {
            return 0.0;
        }
        self.radii_cm[(entity_id % self.radii_cm.len() as u64) as usize] as f32 / 100.0
    }
}

/// A station (`StationDef`).
#[derive(Debug)]
pub struct StationSeed {
    pub id: u32,
    pub key: &'static str,
    pub name: &'static str,
}

/// Where a recipe's output's quality comes from (`RecipeDef.Quality`).
pub const QUALITY_NONE: u8 = 0;
pub const QUALITY_FROM_ROUND: u8 = 1;
pub const QUALITY_FROM_INPUTS: u8 = 2;

/// Whether input `input` of `r` sets a `QUALITY_FROM_INPUTS` item's quality: only its CORE does, the inputs no
/// part slot names (Luke's M12, 2026-11-05, `MINIGAMES_PREP.md` §4.1). A picked part (a grip, a binding) never
/// does, whatever its own grade: a Masterwork grip on a Common blade makes a Common sword.
pub fn sets_quality(r: &RecipeSeed, input: usize) -> bool {
    !r.part_slots.iter().any(|s| *s >= 0 && *s as usize == input)
}

/// A recipe (`RecipeDef`).
#[derive(Debug)]
pub struct RecipeSeed {
    pub id: u32,
    pub name: &'static str,
    pub station: &'static str,
    pub skill: u32,
    pub inputs: &'static [(u32, u32)],
    pub output: u32,
    pub output_qty: u32,
    pub xp: u32,
    pub min_rank: u32,
    pub afk_ms: u32,
    pub minigame: Minigame,
    pub quality: u8,
    pub afk_quality: u32,
    /// The input that is the tool's HANDLE (-1: none): any item of that input's `part_tag` may take its
    /// place, at the player's choice, and its trait goes on the tool. The first of `part_slots`.
    pub part_slot: i32,
    /// EVERY INPUT THE PLAYER PICKS (MATERIALS.md step 3): a handle, a binding; each offers its trait.
    pub part_slots: &'static [i32],
}

/// A weapon kit (`KitDef`): what a weapon of its key fights with.
#[derive(Debug)]
pub struct KitSeed {
    pub id: u32,
    pub key: &'static str,
    /// Its mastery skill.
    pub skill: u32,
    /// The string, in order; its last step is the FINISHER (COMBAT_OVERHAUL.md §3: the heavy merged in).
    pub light: &'static [u32],
    /// Each step's FOLLOW-THROUGH: after it lands, this long before the next step may start.
    pub follow_ms: &'static [u32],
    /// Q, E, R, F: (ability, the mastery rank it unlocks at).
    pub skills: &'static [(u32, u32)],
    /// Each ability's lock: how long a swing holds its fighter (its clip's length, baked).
    pub locks: &'static [(u32, u32)],
    /// A drawn kit (a bow): its full draw, in ms. 0: a melee kit.
    pub draw_full_ms: u32,
    /// A casting kit (the Staff): its pool's resource id (mana); its abilities are spells. 0: none.
    pub resource: u32,
    /// Its abilities no block or parry stops (COMBAT_OVERHAUL.md §2: a foe's finisher).
    pub unblockable: &'static [u32],
    /// THE ROLE MAP (COMBAT_OVERHAUL.md §5): per role, the string's last hit. Empty: no roles yet.
    pub roles: &'static [RoleFinisher],
    /// What its abilities do when they land unblocked (`KitHit`). Empty: damage only.
    pub hits: &'static [KitHitSeed],
    /// ITEM LEVELS (ABILITIES_PREP.md §7 step 2): each skill's bar slot, in `skills`' order (`SLOT_BASE`, `SLOT_OPTION`,
    /// `SLOT_ULT`, `SLOT_F`). Empty: every skill a base (a foe's kit).
    pub slots: &'static [u32],
    /// The item level each unlock opens at: Q and F, the first pick, the second pick, the ult (Luke's B4: 1, 5, 12, 20).
    pub unlock_levels: [u32; 4],
    /// PER-ROLE POOLS (S1b; Luke's "each weapon of each role a unique set"): (role id, ability) for each skill a role
    /// claims as its own. A skill no role claims is every role's. Empty: one pool for the kit (the staff, foes).
    pub role_skills: &'static [(u32, u32)],
}

/// A SPELL (`SpellDef`, owner 2026-10-20): how a casting kit's ability lands.
#[derive(Debug)]
pub struct SpellSeed {
    pub ability: u32,
    /// `SPELL_BOLT`, `SPELL_AREA`, `SPELL_BLINK`, `SPELL_CONE`.
    pub kind: i64,
    /// Of the kit's pool, paid when it lands.
    pub cost: f32,
    pub cast_ms: i64,
    pub cast_while_moving: bool,
    /// A bolt's missile (a body).
    pub body: i64,
    pub speed: f32,
    pub splash_m: f32,
    pub splash_pct: i64,
    pub burn_dps: f32,
    pub burn_ms: i64,
    pub radius_m: f32,
    pub delay_ms: i64,
    pub angle_deg: f32,
    pub push_mps: f32,
    /// A status for what it hits (Slowed), 0 none; and how long.
    pub status: i64,
    pub status_ms: i64,
}

pub const SPELL_BOLT: i64 = 0;
pub const SPELL_AREA: i64 = 1;
pub const SPELL_BLINK: i64 = 2;
pub const SPELL_CONE: i64 = 3;

/// The spell ability `ability_id` is, if any.
pub fn spell_of(ability_id: u32) -> Option<&'static SpellSeed> {
    SPELLS.iter().find(|s| s.ability == ability_id)
}

/// Whether a cast with this long a cast time may be walked through: the spell says, and the owner's rule
/// (casts of 0.8 s or more root) holds whatever it says.
pub fn may_walk_casting(spell: &SpellSeed) -> bool {
    spell.cast_while_moving && spell.cast_ms < 800
}

/// Whether `at` is in a cone from `from` facing `dir` (flat), `range` m long and `angle_deg` wide.
pub fn in_cone(from: crate::sim::Vector3, dir: crate::sim::Vector3, at: crate::sim::Vector3, range: f32, angle_deg: f32) -> bool {
    let (dx, dz) = (at.x - from.x, at.z - from.z);
    let d = (dx * dx + dz * dz).sqrt();
    if d > range {
        return false;
    }
    if d < 0.3 {
        return true;
    }
    let dl = (dir.x * dir.x + dir.z * dir.z).sqrt();
    if dl < 1e-6 {
        return false;
    }
    let cos = (dx * dir.x + dz * dir.z) / (d * dl);
    cos >= (angle_deg.to_radians() / 2.0).cos()
}

/// Where a blink from `from` along `aim` (flat) lands: `range` m on, on the same height.
pub fn blink_to(from: crate::sim::Vector3, aim: crate::sim::Vector3, range: f32) -> Option<crate::sim::Vector3> {
    let l = (aim.x * aim.x + aim.z * aim.z).sqrt();
    if !l.is_finite() || l < 1e-6 {
        return None;
    }
    Some(crate::sim::Vector3::new(from.x + aim.x / l * range, from.y, from.z + aim.z / l * range))
}

/// WHO MAY HURT WHOM (owner's playtest, 2026-10-20: skeletons crowding a player hit each other and played
/// their hurt over and over; a player's chop hurt a friend). A foe hurts only players; a player hurts
/// anything but another player (no fights between players until duels, RULE_DESIGN §4.5).
pub fn may_hurt(actor_is_foe: bool, actor_is_player: bool, target_is_player: bool) -> bool {
    if actor_is_foe {
        return target_is_player;
    }
    !(actor_is_player && target_is_player)
}

/// Flat distance between two places.
pub fn flat_dist(a: crate::sim::Vector3, b: crate::sim::Vector3) -> f32 {
    ((a.x - b.x).powi(2) + (a.z - b.z).powi(2)).sqrt()
}

impl KitSeed {
    /// The string's last hit for a weapon of role `role` (its role map's; else the string's last).
    pub fn finisher_for(&self, role: &RoleSeed) -> u32 {
        self.roles.iter().find(|r| r.role == role.id).map_or_else(|| self.light.last().copied().unwrap_or(0), |r| r.ability)
    }

    /// The role map's entry whose last hit is `ability_id`, if any.
    pub fn role_finisher(&self, ability_id: u32) -> Option<&'static RoleFinisher> {
        self.roles.iter().find(|r| r.ability == ability_id)
    }

    /// Whether `ability_id` is this kit's string's last hit, for any role.
    pub fn ends_string(&self, ability_id: u32) -> bool {
        self.light.last() == Some(&ability_id) || self.roles.iter().any(|r| r.ability == ability_id)
    }

    /// How long `ability_id` locks its fighter (0: not this kit's).
    pub fn lock_ms(&self, ability_id: u32) -> u32 {
        self.locks.iter().find(|(a, _)| *a == ability_id).map_or(0, |(_, ms)| *ms)
    }

    /// Whether no block or parry stops `ability_id` (roll, or step out of its sweep).
    pub fn unblockable(&self, ability_id: u32) -> bool {
        self.unblockable.contains(&ability_id)
    }

    /// What `ability_id` does when it lands unblocked (`KitHit`), if any.
    pub fn hit_of(&self, ability_id: u32) -> Option<&'static KitHitSeed> {
        self.hits.iter().find(|h| h.ability == ability_id)
    }
}

/// A FOE (`FoeDef`, owner 2026-10-19): a monster on a level's points of kind `key`, fighting with a kit.
#[derive(Debug)]
pub struct FoeSeed {
    pub id: u32,
    pub name: &'static str,
    /// The level points it stands on.
    pub key: &'static str,
    /// Its entity kind (in FOE_KINDS).
    pub kind: u8,
    /// The kit it fights with (a `KitSeed` key; "" for one that never fights).
    pub kit: &'static str,
    /// Whether it fights (hunting, 2026-11-09: a deer never does: a hit STARTLES it, `STATUS_STARTLED`).
    pub fights: bool,
    /// Its brain (its character's: "regents/foe", "regents/deer"), the sidecar's.
    pub brain: &'static str,
    pub hp: u32,
    /// Its hits, as a weapon of this damage %.
    pub damage_pct: u32,
    /// Mastery XP for hitting it, as a share of the usual (%).
    pub xp_pct: u32,
    /// What a kill drops: its loot table's content id (`loot::LOOT_TABLES`; 0: nothing).
    pub loot_table: u32,
    /// Its family ("undead", "beast"): what a trait made against one reads.
    pub family: &'static str,
    /// A BOSS: what a guard handle's threat counts against when `regents.guard_threat_bosses_only` is on.
    pub boss: bool,
    /// Its poise (`FoeDef.poise`; 0: none, every last hit staggers it).
    pub poise: u32,
    /// What its kill leaves (skinning, 2026-11-09): a CARCASS, a node of this id where it fell (0: its body only).
    pub carcass: u32,
    /// How high above its feet a shot the server aims at it goes: the middle of its body (`FoeDef.aim_height_m`).
    pub aim_height_m: f32,
    /// Its Defense (`FoeDef.defense`; 0: none): a hit on it takes `defense_mult` of its damage.
    pub defense: u32,
}

/// Where a shot is aimed on a body with no size of its own (a player, a dummy): a man's chest.
pub const AIM_HEIGHT_M: f32 = 1.1;

/// How long more a carcass is `owner`'s alone, in ms, as `who` asks at `now_us` (0: anyone may skin it now; always 0
/// for its owner). Skinning, Luke 2026-11-09: "the killer first, then anyone", for `own_s` seconds after it fell.
pub fn carcass_owned_ms(owner: u64, who: u64, fell_us: i64, now_us: i64, own_s: f64) -> i64 {
    if owner == who || owner == 0 {
        return 0;
    }
    let until = fell_us + (own_s.max(0.0) * 1_000_000.0) as i64;
    ((until - now_us) / 1000).max(0)
}

/// The entity kinds a foe may be (CLAIMS keeps them for this genre).
pub const FOE_KINDS: std::ops::RangeInclusive<u8> = 103..=119;

/// Where an ability sits in its kit.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KitSlot {
    /// The string's step (0 first; the last is the finisher).
    Light(u32),
    /// A skill key (0 Q .. 3 F) and the rank it needs.
    Skill(u32, u32),
}

include!(concat!(env!("OUT_DIR"), "/regents_data.rs"));

/// The dodge roll (`content/ability/dodge.tres`): everyone's, whatever they wield.
pub const ABILITY_DODGE: u32 = 40010;
/// ABILITIES RETIRED (COMBAT_OVERHAUL.md §3, 2026-10-31: the heavy cut and the second chop, when the heavy
/// merged into the finisher). A database kept across publishes still has their rows (the abilities follow
/// the build, but are never dropped), so the server refuses them by name; their ids are never reused.
pub const RETIRED_ABILITIES: &[u32] = &[40004, 40007];
/// Statuses (`content/status/`): a roll's moment (nothing hits), holding a block, staggered by a parry.
pub const STATUS_ROLLING: u8 = 101;
pub const STATUS_BLOCKING: u8 = 102;
pub const STATUS_STAGGERED: u8 = 103;
pub const STATUS_SWINGING: u8 = 104;
pub const STATUS_FLINCHED: u8 = 105;
/// Health ran out (`content/status/slain.tres`): nothing moves, acts or is hit.
pub const STATUS_SLAIN: u8 = 106;
/// A bow drawn (`content/status/drawing.tres`): the walk slowed; how long it lasted is the draw.
pub const STATUS_DRAWING: u8 = 107;
/// A creature that never fights was hit (`content/status/startled.tres`, hunting 2026-11-09): its brain bolts.
pub const STATUS_STARTLED: u8 = 109;
/// The arrow (`content/body/arrow.tres`): what a bow looses.
pub const BODY_ARROW: u32 = 40001;
/// Gravity on an arrow (Godot's, which the referee flies it by), m/s².
pub const ARROW_GRAVITY: f32 = 9.8;
/// The training dummy's entity kind (`content/character/dummy.tres`) and its level points.
pub const ENTITY_DUMMY: u8 = 102;
pub const DUMMY_POINT: &str = "dummy";
/// THE CAMP'S GUIDE (the tutorial, Luke 2026-11-01): its entity kind (`content/character/guide.tres`) and its
/// level points. Nobody hurts it.
pub const ENTITY_GUIDE: u8 = 120;
pub const GUIDE_POINT: &str = "guide";

/// A character's tutorial (`tutorial.state`): offered (the guide offers it; a new character's), under way,
/// finished, set aside ("not now").
pub const TUTORIAL_OFFERED: u8 = 0;
pub const TUTORIAL_ON: u8 = 1;
pub const TUTORIAL_FINISHED: u8 = 2;
pub const TUTORIAL_SET_ASIDE: u8 = 3;

/// What the server saw that ticks a lesson (`LessonDef.Done`, in its order).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Deed {
    Gathered = 0,
    Made = 1,
    Wielded = 2,
    LastHit = 3,
    RolledThrough = 4,
    Parried = 5,
    Riposte = 6,
    Blocked = 7,
    RolledGlint = 8,
    ShapedLastHit = 9,
}

/// A LESSON of the tutorial (`LessonDef`): its place in the run, its deed, and the item a gathered, made or
/// wielded one wants (0: any; `any_of_its_kind`: any item of that one's part or kit).
#[derive(Debug)]
pub struct LessonSeed {
    pub id: u32,
    pub order: u32,
    pub deed: u8,
    pub item: u32,
    pub any_of_its_kind: bool,
}

impl LessonSeed {
    /// Whether deed `deed` with item `item` (0: none) ticks this lesson.
    pub fn ticked_by(&self, deed: Deed, item: u32) -> bool {
        if self.deed != deed as u8 {
            return false;
        }
        if self.item == 0 || self.item == item {
            return true;
        }
        if !self.any_of_its_kind {
            return false;
        }
        let (Some(want), Some(got)) = (crate::genre::regents::item(self.item), crate::genre::regents::item(item)) else { return false };
        (!want.part_tag.is_empty() && got.part_tag == want.part_tag) || (!want.weapon_kit.is_empty() && got.weapon_kit == want.weapon_kit)
    }
}

/// The lessons a deed ticks, of those not yet `done`, and whether every lesson is then done: what a deed
/// changes in a character's tutorial (`game::regents::lesson_done`).
pub fn lessons_ticked(done: &[u32], deed: Deed, item: u32) -> (Vec<u32>, bool) {
    let newly: Vec<u32> = LESSONS.iter().filter(|l| !done.contains(&l.id) && l.ticked_by(deed, item)).map(|l| l.id).collect();
    let all = LESSONS.iter().all(|l| done.contains(&l.id) || newly.contains(&l.id));
    (newly, all && !LESSONS.is_empty())
}

/// POISE (Luke, 2026-11-02: "the guard handle plus Heavy allows for almost infinite stagger"; option A, a bar that
/// breaks, with a short B, Steadied, after each break): a hit of `wear` on poise `left` (of `most`). Every hit wears
/// it. The string's LAST hit (`last`) breaks it the moment it empties it. A light that would empty it stops at 1: the
/// bar is FULL; and ANY hit on a bar already full breaks it (Luke, 2026-11-12: "if the stagger bar is full (orange)
/// the next hit should stagger not just the next finisher hit"; before, only the last hit ever broke it, so a full
/// bar sat full through every light). Broken, it is whole again and the hit STAGGERS. While `steadied` nothing wears
/// it. Returns what is left, and whether it broke.
pub fn poise_hit(left: f32, most: f32, wear: f32, last: bool, steadied: bool) -> (f32, bool) {
    if steadied || most <= 0.0 {
        return (left, false);
    }
    let after = left - wear.max(0.0);
    let worn_out = left <= POISE_FLOOR;
    if after <= 0.0 && (last || worn_out) {
        return (most, true);
    }
    (after.max(POISE_FLOOR.min(left)), false)
}

/// What a light leaves of a poise it would have emptied: the bar reads full, and the next hit breaks it.
pub const POISE_FLOOR: f32 = 1.0;

/// How much wider than `regents.aim_arc_deg` the server takes a shooter's facing to be (degrees, the whole arc): the
/// body's turn reaches the server a moment after the client checked it.
pub const AIM_ARC_SLACK_DEG: f32 = 30.0;

/// Poise `left` (of `most`) `since_ms` after its last hit: whole again once `regen_ms` have passed unhit.
pub fn poise_now(left: f32, most: f32, since_ms: i64, regen_ms: f32) -> f32 {
    if since_ms as f32 >= regen_ms {
        most
    } else {
        left.min(most)
    }
}

/// Whether a player ROLLED THROUGH a foe's swing the referee judged a MISS: they were rolling as it was judged (`left_ms`
/// of their roll left; a tenth of a second over, for the status's own tick) and in its reach (`dist_m` from the
/// foe, its reach `reach_m`, with a meter's slack: the roll moves them). Judged by the miss, not by the swing's
/// nominal landing: at 150 ms a roll begun as the blow is SEEN starts after that moment, and the referee, which
/// judges the blow later, still finds nobody there (the 2026-11-02 playtest).
pub fn rolled_clear(left_ms: i64, dist_m: f32, reach_m: f32) -> bool {
    left_ms > -100 && dist_m <= reach_m + 1.0
}

/// The foe that is entity kind `kind`, if any.
pub fn foe_of_kind(kind: u8) -> Option<&'static FoeSeed> {
    FOES.iter().find(|f| f.kind == kind)
}


/// OUT OF THE FIGHT, HEALTH COMES BACK (2026-10-20): `pct_per_s` % of `max` a second, over `dt_s`, never
/// past `max`.
pub fn regen_step(current: f32, max: f32, pct_per_s: f32, dt_s: f32) -> f32 {
    (current + max * pct_per_s.max(0.0) / 100.0 * dt_s.max(0.0)).min(max)
}

// --- the bow (owner, 2026-10-20) ----------------------------------------------------------------------

/// A draw of `draw_ms` on a kit drawn full at `full_ms`: its power, `min_pct` % at once rising to 1 at
/// full (and held there).
pub fn draw_power(draw_ms: i64, full_ms: u32, min_pct: f32) -> f32 {
    let min = (min_pct / 100.0).clamp(0.0, 1.0);
    let t = (draw_ms.max(0) as f32 / full_ms.max(1) as f32).clamp(0.0, 1.0);
    min + (1.0 - min) * t
}

/// The chance (%) an auto-aimed arrow hits a target `dist_m` away: `near_pct` within `near_m`, falling
/// evenly to `far_pct` at `far_m` (and past it), less `moving_pct` when the target is on the move.
pub fn hit_chance_pct(dist_m: f32, moving: bool, near_m: f32, far_m: f32, near_pct: f32, far_pct: f32, moving_pct: f32) -> f32 {
    let t = ((dist_m - near_m) / (far_m - near_m).max(0.01)).clamp(0.0, 1.0);
    let base = near_pct + (far_pct - near_pct) * t;
    (base - if moving { moving_pct } else { 0.0 }).clamp(0.0, 100.0)
}

/// The velocity that carries an arrow from `from` to `to` at `speed` under gravity `g`: the low arc. Out of
/// its reach, the farthest it can go (45 degrees) toward it.
pub fn aim_velocity(from: crate::sim::Vector3, to: crate::sim::Vector3, speed: f32, g: f32) -> crate::sim::Vector3 {
    let dx = to.x - from.x;
    let dz = to.z - from.z;
    let x = (dx * dx + dz * dz).sqrt().max(0.001);
    let y = to.y - from.y;
    let v2 = speed * speed;
    let root = v2 * v2 - g * (g * x * x + 2.0 * y * v2);
    let angle = if root >= 0.0 { ((v2 - root.sqrt()) / (g * x)).atan() } else { std::f32::consts::FRAC_PI_4 };
    let (h, up) = (speed * angle.cos(), speed * angle.sin());
    crate::sim::Vector3::new(dx / x * h, up, dz / x * h)
}

/// Where a MISSED arrow is aimed: past the target by `wide_m` to one side (by `roll` 0..1000, as the server
/// rolled it), so it flies visibly wide.
pub fn miss_point(from: crate::sim::Vector3, target: crate::sim::Vector3, roll: u32, wide_m: f32) -> crate::sim::Vector3 {
    let dx = target.x - from.x;
    let dz = target.z - from.z;
    let d = (dx * dx + dz * dz).sqrt().max(0.001);
    // Its side, from the roll: left or right, and how far up (a little high or low).
    let side = if roll % 2 == 0 { 1.0 } else { -1.0 };
    let lift = (roll % 7) as f32 / 6.0 - 0.5;
    crate::sim::Vector3::new(target.x + (-dz / d) * wide_m * side, target.y + lift * wide_m * 0.5, target.z + (dx / d) * wide_m * side)
}

/// An arrow's damage: the shot's at the draw's power, the bow's and the arrow's %, its quality and mastery;
/// at point blank, `point_blank_pct` % of it.
pub fn arrow_damage(shot_damage: f32, power: f32, bow_pct: u32, arrow_pct: u32, quality_pm: u32, rank: u32, point_blank: bool, point_blank_pct: f32) -> f32 {
    let d = hit_damage(shot_damage * power, bow_pct, quality_pm, rank) * arrow_pct as f32 / 100.0;
    if point_blank { d * point_blank_pct / 100.0 } else { d }
}

pub fn kit_keyed(key: &str) -> Option<&'static KitSeed> {
    KITS.iter().find(|k| k.key == key)
}

/// The kit `ability_id` is part of, and where in it (any role's last hit is the string's last step); None for
/// an ability no kit has (the dodge).
pub fn kit_of_ability(ability_id: u32) -> Option<(&'static KitSeed, KitSlot)> {
    for k in KITS {
        if let Some(i) = k.light.iter().position(|a| *a == ability_id) {
            return Some((k, KitSlot::Light(i as u32)));
        }
        if !k.light.is_empty() && k.roles.iter().any(|r| r.ability == ability_id) {
            return Some((k, KitSlot::Light(k.light.len() as u32 - 1)));
        }
        if let Some(i) = k.skills.iter().position(|(a, _)| *a == ability_id) {
            return Some((k, KitSlot::Skill(i as u32, k.skills[i].1)));
        }
    }
    None
}

/// THE TOP RANK OF EVERY SKILL (Luke's S1 + S2, 2026-11-13: "move everything from 1-10 to 1-33 (a third of 99) for
/// testing"; finalized before the public demo, with a wipe). The content's curves must end here (`server/tests`).
pub const RANK_TOP: u32 = 33;
/// What mastery adds at the top rank, in basis points (27 %: the old 3 % a rank over ranks 2-10).
pub const RANK_TOP_BONUS_BP: u32 = 2700;

/// Mastery's share at `rank`, in basis points: an even step a rank past the first, `RANK_TOP_BONUS_BP` at
/// `RANK_TOP` and never more (rank 12 of 33, the old rank 4: 928, about the old 9 %).
pub fn mastery_bp(rank: u32) -> u32 {
    (rank.saturating_sub(1) * RANK_TOP_BONUS_BP / (RANK_TOP - 1)).min(RANK_TOP_BONUS_BP)
}

/// A hit's damage (owner, 2026-10-19): the ability's, times the weapon's `weapon_damage_pct`, its
/// quality adding up to a fifth more, and mastery's share (`mastery_bp`: at most 27 %, at the top rank).
pub fn hit_damage(ability_damage: f32, weapon_damage_pct: u32, quality_pm: u32, rank: u32) -> f32 {
    let quality = 1.0 + quality_pm.min(1000) as f32 / 5000.0;
    let mastery = 1.0 + mastery_bp(rank) as f32 / 10_000.0;
    ability_damage * weapon_damage_pct as f32 / 100.0 * quality * mastery
}

/// THE SLOTS ARMOR IS WORN IN (Luke's five equipment slots: the weapon is wielded, these four worn; S2).
pub const ARMOR_SLOTS: [&str; 4] = ["head", "chest", "legs", "trinket"];

/// WHETHER `ability` IS A CHEST'S (S4, B8): one some piece of armor gives on F while worn. It is used from the worn chest,
/// never from a weapon's kit.
pub fn is_worn_ability(ability: u32) -> bool {
    ability != 0 && ITEMS.iter().any(|i| i.worn_ability == ability)
}

/// A worn piece's DEFENSE (S2, ARMOR_PREP.md A4.3, settled): its item's, its quality adding up to a fifth more as quality
/// adds to a weapon's damage (`hit_damage`).
pub fn piece_defense(defense: u32, quality_pm: u32) -> f32 {
    defense as f32 * (1.0 + quality_pm.min(1000) as f32 / 5000.0)
}

/// What a hit on someone with Defense `defense` keeps of its damage (ARMOR_PREP.md A1, settled): K / (K + Defense), K the hot
/// rule `regents.defense_k`. Never a flat cut: at Defense K a hit is halved, and no Defense makes one nothing. No
/// Defense, or a K that is not above 0: all of it.
pub fn defense_mult(defense: f32, k: f64) -> f32 {
    if defense <= 0.0 || k <= 0.0 { 1.0 } else { (k / (k + defense as f64)) as f32 }
}

/// A HIT'S DAMAGE THROUGH WHAT STANDS IN ITS WAY, in the settled order (A1.2): the guard first, then armor, then the
/// attacker's traits, each a multiplier, MULTIPLIED, never added.
pub fn through(dmg: f32, guard_mult: f32, armor_mult: f32, trait_mult: f32) -> f32 {
    dmg * guard_mult * armor_mult * trait_mult
}

/// Whether a light step `step` may follow: the first always; a later one only right after the step
/// before it, inside the kit's window (`last_step` -1: no combo going).
pub fn combo_allows(step: u32, last_step: i32, since_ms: i64, window_ms: u32) -> bool {
    step == 0 || (last_step == step as i32 - 1 && since_ms >= 0 && since_ms <= window_ms as i64)
}

/// The refusal of a light step the combo does not allow (`combo_allows`).
pub const OUT_OF_ORDER: &str = "out of the combo's order";
/// One after a swing that was cut short (a finisher's flinch or a roll in its wind-up): said apart, because the
/// combo starts again and a client that saw the flinch already knows (the load test's bots are refused this
/// as play; any other order is a bug).
pub const CUT_SHORT: &str = "the swing before was cut short: the combo starts again";

/// Why a light step may not start, or None. `prev` is the step before (-1 for none, or one cut short).
pub fn combo_refusal(step: u32, prev: i32, prev_cut_short: bool, since_ms: i64, window_ms: u32) -> Option<&'static str> {
    if combo_allows(step, prev, since_ms, window_ms) {
        None
    } else if prev_cut_short && step > 0 {
        Some(CUT_SHORT)
    } else {
        Some(OUT_OF_ORDER)
    }
}

/// THE SWING'S TIMELINE (owner, 2026-10-19: animation-locked, with a buffer): a swing used at 0 lands at
/// `wind_up` and holds its fighter until `lock`. May a new swing start `t` ms after the last began?
/// The string's next step from `wind_up + follow` (its FOLLOW-THROUGH, COMBAT_OVERHAUL.md §3: the arc
/// finishes, then the recovery cancels into the next); anything else once the lock is over. `slack`
/// forgives the network; a canceled swing (a roll) holds nothing.
pub fn swing_allows(next_is_chain: bool, t: i64, wind_up: i64, follow: i64, lock: i64, slack: i64, cancelled: bool) -> bool {
    if cancelled {
        return true;
    }
    let from = if next_is_chain { (wind_up + follow).min(lock) } else { lock };
    t >= from - slack
}

impl KitSeed {
    /// Step `step`'s follow-through (200 ms when the bake has none for it).
    pub fn follow_of(&self, step: u32) -> u32 {
        self.follow_ms.get(step as usize).copied().unwrap_or(200)
    }

    /// Whether `slot` is the FINISHER: the string's last step (armor, it flinches a light, it staggers). A string of
    /// ONE STEP has none (2026-11-12: the archer's lone shove must not stagger): a finisher ends a string.
    pub fn is_finisher(&self, slot: KitSlot) -> bool {
        self.light.len() > 1 && matches!(slot, KitSlot::Light(step) if step as usize + 1 == self.light.len())
    }
}

// --- THE GUARD (COMBAT_OVERHAUL.md §4, 2026-10-31): the right button. A tap PARRIES, judged on the hit as the
// player saw it; held, it BLOCKS (a role's block, front-only). Pure, so the native suite checks each rule.

// --- ROLES (COMBAT_OVERHAUL.md §5, Luke 2026-11-01): by the handle's SHAPE. Pure, for the native suite.

/// The role with content id `id`, if any.
pub fn role(id: u32) -> Option<&'static RoleSeed> {
    ROLES.iter().find(|r| r.id == id)
}

/// The role keyed `key` ("tank"), if any.
pub fn role_keyed(key: &str) -> Option<&'static RoleSeed> {
    ROLES.iter().find(|r| r.key == key)
}

/// THE PLAIN ROLE: a weapon's whose handle names none.
pub fn plain_role() -> &'static RoleSeed {
    ROLES.iter().find(|r| r.plain).unwrap_or(&ROLES[0])
}

/// THE ROLE of a weapon assembled from `parts` (its `"p"`, or its handle alone): the first part whose shape
/// gives one, else the plain role. The client's twin: `ItemDef.role_of`.
pub fn role_of_parts(parts: &[u32]) -> &'static RoleSeed {
    parts.iter().filter_map(|p| item(*p)).find_map(|it| role(it.role)).unwrap_or_else(plain_role)
}

/// Whether part `part` may go in a part slot of `made`: of the slot's kind `kind`, and fitting `made`'s kit when
/// it names one (a crossguard hilt fits a sword, not an axe). The client's twin: `ItemDef.fits`.
pub fn part_fits(part: &ItemSeed, kind: &str, made: Option<&ItemSeed>) -> bool {
    !kind.is_empty() && part.part_tag == kind && (part.fits_kit.is_empty() || made.is_some_and(|m| m.weapon_kit == part.fits_kit))
}

/// A DROPPED WEAPON's handle (Luke, 2026-11-01: 50 % plain, 25 / 25, live): of the plain-wood handles that fit
/// `weapon` (a kit with roles), the one `roll` (0..`roll_of`) picks by each role's weight (`weight(role)`);
/// None for a weapon of a kit with no roles, or no weight at all.
pub fn drop_handle(weapon: &ItemSeed, roll: u32, roll_of: u32, weight: &dyn Fn(&RoleSeed) -> f64) -> Option<u32> {
    let kit = kit_keyed(weapon.weapon_kit).filter(|k| !k.roles.is_empty())?;
    let recipe = RECIPES.iter().find(|r| r.output == weapon.id && !r.part_slots.is_empty())?;
    let kind = item(recipe.inputs[recipe.part_slots[0] as usize].0)?.part_tag;
    // Each role of the kit, its plainest handle (no trait: the plain wood's).
    let mut choices: Vec<(u32, f64)> = Vec::new();
    for rf in kit.roles {
        let r = role(rf.role)?;
        let handle = ITEMS.iter().find(|it| part_fits(it, kind, Some(weapon)) && role_of_parts(&[it.id]).id == r.id
            && it.handle_trait == 0 && it.weapon_trait == 0)?;
        choices.push((handle.id, weight(r).max(0.0)));
    }
    let total: f64 = choices.iter().map(|(_, w)| w).sum();
    if total <= 0.0 {
        return None;
    }
    let mut at = roll.min(roll_of.saturating_sub(1)) as f64 / roll_of.max(1) as f64 * total;
    for (h, w) in &choices {
        if at < *w {
            return Some(*h);
        }
        at -= w;
    }
    choices.last().map(|(h, _)| *h)
}

/// The `instance_data` of a dropped weapon with handle `handle`: its parts (the handle), no traits on purpose.
pub fn dropped_data(handle: u32) -> String {
    format!("{{\"h\":{handle},\"p\":[{handle}],\"t\":[]}}")
}

/// A role's THREAT in percent against a foe (stored for step 6: nothing targets by it yet): `live_pct` (its
/// rule's, else its own), unless `bosses_only` keeps it to bosses and this is none (then the plain 100).
pub fn threat_pct(live_pct: f64, bosses_only: bool, foe_is_boss: bool) -> f64 {
    if bosses_only && !foe_is_boss { 100.0 } else { live_pct.max(0.0) }
}

/// THREAT FROM HEALING (Luke, 2026-11-01: "healing draws no more threat than damage"): `healed` points count as
/// at most as many points of damage, at the healer's threat.
pub fn heal_threat(healed: f32, threat_pct: f64) -> f64 {
    healed.max(0.0) as f64 * threat_pct.max(0.0) / 100.0
}

/// THE RALLYING CUT'S HEAL for its user: all of `heal` alone; `self_share_pct` of it with other players near.
pub fn rally_self_heal(heal: f32, others_near: usize, self_share_pct: f64) -> f32 {
    if others_near == 0 { heal } else { heal * (self_share_pct.clamp(0.0, 100.0) / 100.0) as f32 }
}

/// WHETHER A RALLYING HIT HEALS (S1, areas that hit all): once a swing, however many bodies it lands on. `swing_at_us`:
/// when the swing it came from began (none: a hit with no swing kept, which always heals, as before); `last_us`: the
/// swing its fighter's rally last healed from.
pub fn rallies(swing_at_us: Option<i64>, last_us: Option<i64>) -> bool {
    swing_at_us.is_none() || swing_at_us != last_us
}

/// When a guard press arriving at `arrived_us` (server micros) was made, ON THE SERVER'S CLOCK OF THE SWING
/// THE PLAYER SAW: less its trip here (`credit_ms`, the foundation's: half the quickest round trip the server
/// measured) and how late their client shows another's swing (`seen_delay_ms`: a swing's animation starts as
/// its event arrives, half a round trip after the server began it; as the client reports it, at most
/// `cap_ms`, the referee's `foundation.rewind_max_ms`, so a client claiming more gains nothing past it).
pub fn press_seen_us(arrived_us: i64, credit_ms: u32, seen_delay_ms: u32, cap_ms: u32) -> i64 {
    arrived_us - (credit_ms as i64 + seen_delay_ms.min(cap_ms) as i64) * 1000
}

/// A guard press's trip here, in ms: half the quickest round trip the server measured (`press_credit_ms`,
/// DECISIONS #210), or, with none measured yet (a player who never played a timed press), the client's own
/// half round trip as it reports it; at most `cap_ms` (`foundation.press_credit_cap_ms`) either way. Without
/// the fallback a parry is judged half a ping late until a minigame happens to measure one.
pub fn guard_credit_ms(measured_rtt_ms: Option<u32>, reported_half_ms: u32, cap_ms: u32) -> u32 {
    measured_rtt_ms.map_or(reported_half_ms, |r| r / 2).min(cap_ms)
}

/// Whether a press seen at `seen_us` PARRIES a hit that landed at `land_us`: it came within `parry_ms`
/// before the hit, or at most `late_ms` after it.
pub fn parries(seen_us: i64, land_us: i64, parry_ms: u32, late_ms: u32) -> bool {
    seen_us >= land_us - parry_ms as i64 * 1000 && seen_us <= land_us + late_ms as i64 * 1000
}

/// The latest a press that could still parry a hit landing at `land_us` may arrive: a press made `late_ms`
/// after it, as seen, carrying the most credit and view delay the server allows. Until then the hit waits.
pub fn parry_deadline_us(land_us: i64, late_ms: u32, view_cap_ms: u32, credit_cap_ms: u32) -> i64 {
    land_us + (late_ms as i64 + view_cap_ms as i64 + credit_cap_ms as i64) * 1000
}

/// HOW LONG A HIT ON ONE PLAYER WAITS (Luke, 2026-11-11: "the LAG when getting hit ... I think I dodged an attack
/// only for .5 or .8 seconds later to get hit"): until the latest press THIS player could still parry it with
/// arrives: `late_ms` after it as they see it, plus how late they see a swing (`seen_ms`, as their client last
/// said) and their press's trip here (`credit_ms`), plus `slack_ms` for a trip slower than usual. Every hit on a
/// player waited `parry_deadline_us`, the most any press may carry (320 ms); a player on a quick line now waits
/// little more than `late_ms`.
pub fn hold_deadline_us(land_us: i64, late_ms: u32, seen_ms: u32, credit_ms: u32, slack_ms: u32) -> i64 {
    land_us + (late_ms as i64 + seen_ms as i64 + credit_ms as i64 + slack_ms as i64) * 1000
}

/// Whether a hit on a player WAITS for a late parry or roll, or is DEALT AT ONCE and taken back if one comes (Luke,
/// 2026-11-12: "build 'deal the hit at once, take it back on a late parry' or have no late window, whichever is
/// preferred for gameplay and latency"; dealt at once keeps the whole parry window at any ping, where no late
/// window would cut a 200 ms player's from 250 ms to about 80). It waits only while a press could still be on its
/// way (`in_window`), and then only when it could not be taken back: one that STAGGERS them (a staggered player's
/// roll is refused before it is judged) or would KILL them (the dead are not brought back), or with the rule off.
pub fn hit_waits(at_once_rule: bool, in_window: bool, staggers: bool, kills: bool) -> bool {
    in_window && (!at_once_rule || staggers || kills)
}

/// Whether a ROLL its player saw themselves begin at `seen_us` clears a hit that landed at `land_us`: begun
/// before it landed (or at most `late_ms` after, the hand forgiven as a parry's is), and still rolling as it
/// did (`roll_ms`, the roll's length). The roll judged where it was pressed, not where it arrived.
pub fn roll_clears(seen_us: i64, land_us: i64, roll_ms: u32, late_ms: u32) -> bool {
    seen_us <= land_us + late_ms as i64 * 1000 && land_us < seen_us + roll_ms as i64 * 1000
}

// --- A FOE'S SHOT (Luke's F4-F7, 2026-11-12; `FOES_PREP.md` section 7) ---------------------------------------

/// Whether `ability_id` is a SHOT: an ability a `SpellDef` of the bolt kind flies as a missile. A foe's lands on a
/// player as a swing does (the guard, the parry, the roll, dealt at once and taken back) with three differences:
/// a parry only KNOCKS IT AWAY (its shooter is far off: no stagger, no riposte), it NEVER STAGGERS whatever its
/// place in its kit, and a roll lets it fly on.
pub fn is_shot(ability_id: u32) -> bool {
    spell_of(ability_id).is_some_and(|s| s.kind == SPELL_BOLT)
}

/// Whether `ability_id` is something a FOE CASTS through `foe_shot_due` (Luke's F1, 2026-11-12, the imp): a shot (a
/// bolt), or a RING on the ground (an area spell: placed where its target stands as the cast ends, landing
/// `delay_ms` later on every player still in it). Its draw or cast is its foe's swing; a flinch or a stagger stops it.
pub fn is_foe_cast(ability_id: u32) -> bool {
    spell_of(ability_id).is_some_and(|s| s.kind == SPELL_BOLT || s.kind == SPELL_AREA)
}

/// How long before its tell ends a foe's cast fixes where it goes: a shot `lock_ms` (`regents.foe_shot_lock_ms`); a
/// ring 0 (it is placed where its target stands as the cast ends: the time to leave it is its fill).
pub fn cast_lock_ms(ability_id: u32, lock_ms: u32) -> u32 {
    if is_shot(ability_id) { lock_ms } else { 0 }
}

/// When a foe's shot LOCKS ITS AIM and when it is LOOSED (server micros), from when its draw began (`swing_us`), its
/// tell (`wind_up_ms`, the ability's) and `regents.foe_shot_lock_ms`: it flies to where its target's walk at the lock
/// carries them (`lead_point`), so a turn, a stop or a roll after it slips the shot and one before does not. A lock
/// longer than the tell locks as the draw begins.
pub fn shot_times_us(swing_us: i64, wind_up_ms: u32, lock_ms: u32) -> (i64, i64) {
    let loose = swing_us + wind_up_ms as i64 * 1000;
    (loose - lock_ms.min(wind_up_ms) as i64 * 1000, loose)
}

/// NOT CHAINED (Luke's F12, 2026-11-13): whether foe `actor`'s stagger or slow is kept off a player at `now_us`, the
/// last foe's (`by`) holding the window until `until_us`. The same foe's own string is never kept off (its rest
/// spaces it); another's is, until the window ends.
pub fn is_chained(now_us: i64, until_us: i64, by: u64, actor: u64) -> bool {
    by != actor && now_us < until_us
}

/// The fastest walk a shot leads (m/s): past a sprint, so a roll's burst is not followed far beyond where it ends.
pub const LEAD_MAX_MPS: f32 = 8.0;

/// A FOE'S SHOT LEADS A MOVER (Luke, 2026-11-13: shots at where you stood missed anyone who moved at all): where a
/// shot from `from` at `speed` m/s, loosed `to_loose_s` after its aim locks, meets a target at `at` walking `vel` (flat:
/// a jump is not led), `pct` of the way (`regents.foe_shot_lead_pct`; 0: where they stand, 100: a steady walk met).
/// The walk is capped at `LEAD_MAX_MPS`. Height is `at`'s.
pub fn lead_point(from: crate::sim::Vector3, at: crate::sim::Vector3, vel: crate::sim::Vector3, speed: f32, to_loose_s: f32, pct: f32) -> crate::sim::Vector3 {
    let k = (pct / 100.0).clamp(0.0, 1.5);
    let flat = (vel.x * vel.x + vel.z * vel.z).sqrt();
    if k <= 0.0 || speed <= 0.0 || !flat.is_finite() || flat < 0.01 || !to_loose_s.is_finite() {
        return at;
    }
    let cap = flat.min(LEAD_MAX_MPS) / flat;
    let (vx, vz) = (vel.x * cap * k, vel.z * cap * k);
    let mut aim = at;
    // Three passes settle the time of flight to the led point (it moves the point by a few centimetres at most).
    for _ in 0..3 {
        let d = ((aim.x - from.x).powi(2) + (aim.y - from.y).powi(2) + (aim.z - from.z).powi(2)).sqrt();
        let t = to_loose_s.max(0.0) + d / speed;
        aim = crate::sim::Vector3::new(at.x + vx * t, at.y, at.z + vz * t);
    }
    aim
}

/// How high above a shooter's feet its shot leaves: a little over the middle of its body (a man's 1.45 m, as the
/// player's bow and staff).
pub fn shot_height(aim_height_m: f32) -> f32 {
    aim_height_m + 0.35
}

/// Where a missile a ROLL let through goes on from: `clear_m` further along its flight from where it met the
/// roller (past their body). None for one too slow to say which way it flies.
pub fn pass_through(pos: crate::sim::Vector3, vel: crate::sim::Vector3, clear_m: f32) -> Option<crate::sim::Vector3> {
    let speed = (vel.x * vel.x + vel.y * vel.y + vel.z * vel.z).sqrt();
    if !speed.is_finite() || speed < 1.0 {
        return None;
    }
    Some(crate::sim::Vector3::new(pos.x + vel.x / speed * clear_m, pos.y + vel.y / speed * clear_m, pos.z + vel.z / speed * clear_m))
}

/// THE WHIFF LOCKOUT: whether a guard press at `now_us` is no parry, because the last press (at `last_us`)
/// came under `whiff_ms` before it and parried nothing. A press after a parry is never locked (two foes).
pub fn whiff_locked(now_us: i64, last_us: Option<i64>, last_parried: bool, whiff_ms: u32) -> bool {
    !last_parried && last_us.is_some_and(|l| now_us - l < whiff_ms as i64 * 1000)
}

/// Whether a guard facing `yaw` (the body's: forward is (-sin, -cos)) stops a hit from an attacker at
/// (`dx`, `dz`) from it: inside `arc_deg` (the whole arc) in front. On top of each other: in front.
pub fn in_guard_arc(yaw: f32, dx: f32, dz: f32, arc_deg: f32) -> bool {
    let len = (dx * dx + dz * dz).sqrt();
    if len < 1e-3 {
        return true;
    }
    let cos = (-yaw.sin() * dx - yaw.cos() * dz) / len;
    cos >= (arc_deg.clamp(0.0, 360.0) * 0.5).to_radians().cos() - 1e-6
}

/// A held block's damage through: a full guard (the Tank role's) takes `full_pct`, a light one `weak_pct`.
pub fn blocked_damage(dmg: f32, full_block: bool, full_pct: f32, weak_pct: f32) -> f32 {
    dmg * (if full_block { full_pct } else { weak_pct }).clamp(0.0, 100.0) / 100.0
}

/// Whether a swing begun at `swing_at_us` is a RIPOSTE: the string's first step, begun within
/// `riposte_ms` of its fighter's last parry (at `parried_at_us`).
pub fn is_riposte(first_step: bool, swing_at_us: i64, parried_at_us: Option<i64>, riposte_ms: u32) -> bool {
    first_step && parried_at_us.is_some_and(|p| swing_at_us >= p && swing_at_us - p <= riposte_ms as i64 * 1000)
}

pub fn item(id: u32) -> Option<&'static ItemSeed> {
    ITEMS.iter().find(|i| i.id == id)
}

pub fn skill(id: u32) -> Option<&'static SkillSeed> {
    SKILLS.iter().find(|s| s.id == id)
}

pub fn node(id: u32) -> Option<&'static NodeSeed> {
    NODES.iter().find(|n| n.id == id)
}

pub fn recipe(id: u32) -> Option<&'static RecipeSeed> {
    RECIPES.iter().find(|r| r.id == id)
}

/// The node a level point names (its first tag, any case), or None.
pub fn node_named(name: &str) -> Option<&'static NodeSeed> {
    NODES.iter().find(|n| n.name.eq_ignore_ascii_case(name))
}

/// The station a level point names (its first tag: a key, any case), or None.
pub fn station_keyed(key: &str) -> Option<&'static StationSeed> {
    STATIONS.iter().find(|s| s.key.eq_ignore_ascii_case(key))
}

/// The rank `xp` reaches in skill `s` (1 with none).
pub fn rank_of(s: &SkillSeed, xp: u32) -> u32 {
    1 + s.xp_to_rank.iter().filter(|need| xp >= **need).count() as u32
}

/// The highest rank skill `s` has.
pub fn max_rank(s: &SkillSeed) -> u32 {
    1 + s.xp_to_rank.len() as u32
}

/// The XP at which skill `s` reaches `rank` (0 for rank 1), or None past its highest: what the admin's
/// Tester page sets a skill to (owner, 2026-10-23).
pub fn xp_for_rank(s: &SkillSeed, rank: u32) -> Option<u32> {
    match rank {
        0 => None,
        1 => Some(0),
        r => s.xp_to_rank.get(r as usize - 2).copied(),
    }
}

/// How long work takes, in percent of the base: the tool's speed, up to a tenth off for its quality
/// (thousandths), and mastery's share off (`mastery_bp`: at most 27 %, at the top rank). Never under 10 %.
pub fn speed_pct(tool_speed_pct: u32, quality_pm: u32, rank: u32) -> u32 {
    let q = quality_pm.min(1000) as u64;
    let with_quality = tool_speed_pct as u64 * (10_000 - q) / 10_000;
    let rank_off = mastery_bp(rank) as u64;
    ((with_quality * (10_000 - rank_off) / 10_000) as u32).max(10)
}

/// AFK's interval at speed `speed_pct`.
pub fn afk_interval_ms(afk_ms: u32, speed_pct: u32) -> u32 {
    (afk_ms as u64 * speed_pct as u64 / 100).max(100) as u32
}

/// How much a round yields, in thousandths: what AFK makes in the round's time (at its interval), times a factor
/// that runs from `floor` (a score of 0) to `active_mult` (a full score) (Luke's M11, 2026-11-05: a good round beats
/// AFK and a poor one still falls short, the break-even near half a score rather than 80 %; owner #23 before it was
/// `active_mult` x the score, which is `floor` 0). The floor is kept between 0 and `active_mult`.
pub fn active_yield_milli(afk_interval_ms: u32, round_ms: i64, active_mult: f64, floor: f64, score_pm: i64) -> u64 {
    let afk_milli = round_ms as f64 * 1000.0 / afk_interval_ms.max(1) as f64;
    (afk_milli * active_factor(active_mult, floor, score_pm)).floor().max(0.0) as u64
}

/// What a played round pays against AFK (Luke's M11): `floor` at a score of 0 up to `active_mult` at a full score
/// (the floor never over the multiplier). The client's `SkillingRules.active_factor`.
pub fn active_factor(active_mult: f64, floor: f64, score_pm: i64) -> f64 {
    let floor = floor.clamp(0.0, active_mult.max(0.0));
    floor + (active_mult - floor) * score_pm.clamp(0, 1000) as f64 / 1000.0
}

/// What AFK work gets out of a WHOLE node before it is worked out, on average, in thousandths of an item: each item is
/// the last with `deplete_permille` (times the tool's `deplete_mult`), and never more than `max_items` (0: no cap; a
/// node with neither never runs out: 0 here). A carcass's hides (Luke, 2026-11-10: "like a node depletion").
pub fn expected_items_milli(deplete_permille: u32, deplete_mult: f32, max_items: u32) -> u64 {
    let d = (deplete_permille as f64 * deplete_mult.max(0.0) as f64 / 1000.0).clamp(0.0, 1.0);
    if max_items == 0 {
        return if d > 0.0 { (1000.0 / d).floor() as u64 } else { 0 };
    }
    let mut sum = 0.0;
    let mut stay = 1.0;
    for _ in 0..max_items {
        sum += stay;
        stay *= 1.0 - d;
    }
    (sum * 1000.0).round() as u64
}

/// A WHOLE-NODE ROUND (a carcass skinned in one round, `NodeSeed::whole_round`; Luke, 2026-11-10: "good rounds reward
/// more up to a cap"): AFK's average for the whole node times the round's factor (M11), a part item by `roll`, never
/// past what is left under `max_items` (`taken` already).
#[allow(clippy::too_many_arguments)]
pub fn whole_round_items(deplete_permille: u32, deplete_mult: f32, max_items: u32, taken: u32, active_mult: f64, floor: f64, score_pm: i64,
    roll: u32) -> u32 {
    let milli = (expected_items_milli(deplete_permille, deplete_mult, max_items) as f64 * active_factor(active_mult, floor, score_pm)).floor() as u64;
    let n = whole_items(milli, roll);
    if max_items > 0 { n.min(max_items.saturating_sub(taken)) } else { n }
}

/// How much likelier a played round is to bring a rare find than AFK work (Luke's M11: the catalysts lean hard to
/// active play): from 1 (a score of 0: no edge for a round nobody played) up to `active_rare_mult` at a full score.
pub fn active_rare_mult(active_rare_mult: f64, score_pm: i64) -> f64 {
    1.0 + (active_rare_mult.max(1.0) - 1.0) * score_pm.clamp(0, 1000) as f64 / 1000.0
}

/// Thousandths of an item into whole items: the whole part, and one more when `roll` (0..1000) falls
/// under the fraction.
pub fn whole_items(milli: u64, roll: u32) -> u32 {
    (milli / 1000) as u32 + u32::from(((milli % 1000) as u32) > roll)
}

/// One gathered item's outcome: whether it brings the node's rare find (its chance, times `rare_mult`
/// when played) and whether it is the last (the node is worked out), from two rolls.
pub fn item_outcome(n: &NodeSeed, rare_mult: f64, rare_roll: u32, deplete_roll: u32) -> (bool, bool) {
    item_outcome_with(n, rare_mult, 0, 1.0, rare_roll, deplete_roll)
}

/// `item_outcome` with a tool's traits: `rare_add_pm` more rare chance (Prospector's), the depletion
/// chance times `deplete_mult` (Steady, Gentle less; Lucky, Springy more).
pub fn item_outcome_with(n: &NodeSeed, rare_mult: f64, rare_add_pm: u32, deplete_mult: f32, rare_roll: u32, deplete_roll: u32) -> (bool, bool) {
    let rare_pm = (n.rare_permille as f64 * rare_mult).round() as u32 + rare_add_pm;
    let deplete_pm = (n.deplete_permille as f32 * deplete_mult.max(0.0)).round() as u32;
    (n.rare_item != 0 && rare_roll < rare_pm, deplete_roll < deplete_pm)
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

/// An item's quality in thousandths, from its row's `instance_data` (`{"q":734}`); None for none.
pub fn quality_of(instance_data: &str) -> Option<u32> {
    field_of(instance_data, "q").map(|q| q.min(1000))
}

/// The handle a made tool was assembled with (an item id), from its `instance_data` (`"h":N`).
pub fn handle_of(instance_data: &str) -> Option<u32> {
    field_of(instance_data, "h")
}

fn field_of(instance_data: &str, key: &str) -> Option<u32> {
    let at = instance_data.find(&format!("\"{key}\":"))? + key.len() + 3;
    let digits: String = instance_data[at..].trim_start().chars().take_while(|c| c.is_ascii_digit()).collect();
    digits.parse().ok()
}

/// The `instance_data` an item of quality `q` carries.
pub fn quality_data(q: u32) -> String {
    format!("{{\"q\":{}}}", q.min(1000))
}

/// HOW MANY TRAITS A CRAFTED ITEM OF QUALITY `q` HOLDS (owner, 2026-10-23, MATERIALS.md §4): its grade's
/// (`fine_q` and `masterwork_q` cut the grades; `common`, `fine`, `masterwork` are the counts).
pub fn crafted_trait_room(q: u32, fine_q: u32, masterwork_q: u32, common: u32, fine: u32, masterwork: u32) -> u32 {
    if q >= masterwork_q.max(fine_q) {
        masterwork
    } else if q >= fine_q {
        fine
    } else {
        common
    }
}

/// THE TRAITS A CRAFTED ITEM GETS: the player's `wanted`, in their order, those its parts `offer` (the
/// rest dropped, and none twice), as many as `room` holds (a lower grade keeps the first).
pub fn crafted_traits(wanted: &[u32], offered: &[u32], room: u32) -> Vec<u32> {
    let mut out: Vec<u32> = Vec::new();
    for t in wanted {
        if out.len() as u32 >= room {
            break;
        }
        if offered.contains(t) && !out.contains(t) {
            out.push(*t);
        }
    }
    out
}

/// The `instance_data` of an assembled item of quality `q`: its first part (`"h"`, the handle, read by older
/// builds), every part in slot order (`"p"`: what a refit changes), and its traits, `"t":[]` when it has none
/// ON PURPOSE (then no falling back to the handle's trait).
pub fn made_data(q: u32, parts: &[u32], traits: &[u32]) -> String {
    let join = |v: &[u32]| v.iter().map(|t| t.to_string()).collect::<Vec<_>>().join(",");
    match parts.first() {
        Some(h) => format!("{{\"q\":{},\"h\":{h},\"p\":[{}],\"t\":[{}]}}", q.min(1000), join(parts), join(traits)),
        None => format!("{{\"q\":{},\"t\":[{}]}}", q.min(1000), join(traits)),
    }
}

/// The parts an assembled item was made with (`"p"`), or, for one made before they were noted, its handle
/// (`"h"`) alone. Empty for none.
pub fn parts_of_row(instance_data: &str) -> Vec<u32> {
    if let Some(at) = instance_data.find("\"p\":[") {
        let rest = &instance_data[at + 5..];
        if let Some(end) = rest.find(']') {
            return rest[..end].split(',').filter_map(|s| s.trim().parse().ok()).collect();
        }
    }
    handle_of(instance_data).into_iter().collect()
}

/// THE TRAIT part `part` offers item `made` (owner, 2026-10-23): its tool trait for a tool (an axe too), else
/// its weapon trait for a weapon; only one that fits `made`'s tags. 0 for none. The client's twin:
/// `ItemDef.trait_for`.
pub fn offered_for(part: &ItemSeed, made: &ItemSeed) -> u32 {
    let t = if !made.tool_tag.is_empty() { part.handle_trait } else if !made.weapon_kit.is_empty() { part.weapon_trait } else { 0 };
    match crate::traits::find(t) {
        Some(seed) if crate::traits::fits(seed, &item_tags(made)) => t,
        _ => 0,
    }
}

/// THE GRADE of quality `q` (0 Common, 1 Fine, 2 Masterwork) by the cut points `fine_q`, `masterwork_q`.
pub fn grade_of(q: u32, fine_q: u32, masterwork_q: u32) -> u32 {
    if q >= masterwork_q.max(fine_q) {
        2
    } else if q >= fine_q {
        1
    } else {
        0
    }
}

/// `set_craft_grade`'s "no grade picked": the best first, as before (owner, 2026-10-23).
pub const ANY_GRADE: u32 = 3;

/// The `instance_data` of a tool of quality `q` assembled with handle `handle` (an item id): its handle,
/// and the handle's trait (template DECISIONS #275), the tool's whatever its grade (owner, 2026-10-21).
pub fn tool_data(q: u32, handle: u32) -> String {
    let data = format!("{{\"q\":{},\"h\":{handle}}}", q.min(1000));
    match item(handle).map_or(0, |h| h.handle_trait) {
        0 => data,
        t => crate::traits::with_ids(&data, &[t]),
    }
}

/// THE TRAITS a bag row's item has (`"t":[ids]`); a tool made before traits were (it noted only its handle)
/// has its handle's. The client's twin: `ItemDef.trait_ids`.
pub fn traits_of_row(instance_data: &str) -> Vec<u32> {
    let ids = crate::traits::ids_of(instance_data);
    if !ids.is_empty() || instance_data.contains("\"t\":[") {
        return ids;   // its own (none on purpose: `"t":[]`)
    }
    handle_of(instance_data).and_then(item).filter(|h| h.handle_trait != 0).map_or_else(Vec::new, |h| vec![h.handle_trait])
}

/// A tool's speed (percent of the base time its work takes) with its traits' `work_time`, at trait
/// strength `strength` (Springy: quicker; Steady, Gentle: slower).
pub fn tool_speed_with(tool: &ItemSeed, traits: &[u32], strength: f32) -> u32 {
    let m = crate::traits::mult(traits, "work_time", &[], &crate::traits::Against::default(), strength);
    ((tool.tool_speed_pct as f32 * m).round() as u32).max(10)
}

/// WHAT AN ITEM IS, for traits (`TraitDef.applies_to`): a tool ("tool", its tag), a weapon ("weapon", its
/// kit, and "melee", "bow" or "staff" by how the kit fights), ammo. The client's twin: `ItemDef.tags`.
pub fn item_tags(it: &ItemSeed) -> Vec<&'static str> {
    let mut out = Vec::new();
    if !it.tool_tag.is_empty() {
        out.extend(["tool", it.tool_tag]);
    }
    if !it.weapon_kit.is_empty() {
        out.extend(["weapon", it.weapon_kit]);
        let kit = kit_keyed(it.weapon_kit);
        out.push(if kit.is_some_and(|k| k.draw_full_ms > 0) { "bow" } else if kit.is_some_and(|k| k.resource != 0) { "staff" } else { "melee" });
    }
    if !it.ammo_for.is_empty() {
        out.push("ammo");
    }
    out
}

/// WHAT AN ACTION IS, for traits (`TraitAtom.on`): a step of the string is "basic" (and "combo_last" for its
/// last, the finisher), a skill "skill". ("heavy" is retired with the heavy, COMBAT_OVERHAUL.md §3.)
pub fn action_tags(kit: &KitSeed, slot: KitSlot) -> Vec<&'static str> {
    match slot {
        KitSlot::Light(step) if step as usize + 1 == kit.light.len() => vec!["basic", "combo_last"],
        KitSlot::Light(_) => vec!["basic"],
        KitSlot::Skill(..) => vec!["skill"],
    }
}

/// A bow's full draw with its traits' `draw_time` (Swift Draw: sooner). The client's twin:
/// `CombatComponent.draw_full_ms`.
pub fn draw_full_with(draw_full_ms: u32, draw_time: f32) -> u32 {
    ((draw_full_ms as f32 * draw_time.max(0.05)).round() as u32).max(1)
}

/// A swing's lock (`lock_ms`) with its recovery (the part after `wind_up_ms`) scaled by `recovery`: a
/// Balanced basic recovers faster, a Heavy one slower; the wind-up never moves (it is the animation's).
/// The client's twin: `CombatComponent.lock_with`.
pub fn lock_with(lock_ms: u32, wind_up_ms: u32, recovery: f32) -> u32 {
    let rec = lock_ms.saturating_sub(wind_up_ms) as f32 * recovery.max(0.0);
    wind_up_ms + rec.round() as u32
}

/// The XP of the work that went into one `item_id`: a gathered item, its node's XP; a made one, its
/// recipe's XP and its inputs' work, shared over the batch. The cheapest way to it counts; nothing makes
/// it: 0. (Owner, 2026-10-19: crafting pays for the work in what it uses, so it keeps pace with gathering.)
pub fn work_xp(item_id: u32) -> u32 {
    work_xp_at(item_id, 0)
}

fn work_xp_at(item_id: u32, depth: u32) -> u32 {
    if depth > 8 {
        return 0;
    }
    let gathered = NODES.iter().filter(|n| n.yield_item == item_id).map(|n| n.xp);
    let made = RECIPES.iter().filter(|r| r.output == item_id).map(|r| {
        let ins: u32 = r.inputs.iter().map(|(i, q)| q * work_xp_at(*i, depth + 1)).sum();
        (r.xp + ins) / r.output_qty.max(1)
    });
    gathered.chain(made).min().unwrap_or(0)
}

/// A batch of `r`'s XP before variety and first-make: its own XP plus `share_pct` of its inputs' work.
pub fn craft_xp(r: &RecipeSeed, share_pct: u32) -> u32 {
    let ins: u32 = r.inputs.iter().map(|(i, q)| q * work_xp(*i)).sum();
    r.xp + ins * share_pct / 100
}

/// VARIETY (owner, 2026-10-19): a recipe's freshness (thousandths) `secs` seconds after it was last left
/// at `fresh_pm`, recovering `recover_pm_per_min` a minute, never above 1000.
pub fn freshness_now(fresh_pm: u32, secs: u32, recover_pm_per_min: u32) -> u32 {
    (fresh_pm as u64 + secs as u64 * recover_pm_per_min as u64 / 60).min(1000) as u32
}

/// XP at freshness `fresh_pm`: full when fresh, down to `floor_pct` when worn out.
pub fn xp_at_freshness(xp: u32, fresh_pm: u32, floor_pct: u32) -> u32 {
    let floor_pm = floor_pct.min(100) * 10;
    let mult_pm = floor_pm + (1000 - floor_pm) * fresh_pm.min(1000) / 1000;
    (xp as u64 * mult_pm as u64 / 1000) as u32
}

/// What a round's challenge carries: "<target entity> <node or recipe> <speed %>".
pub fn payload(target: u64, def_id: u32, speed_pct: u32) -> String {
    format!("{target} {def_id} {speed_pct}")
}

/// A station round's payload with the part it is made with: "<target> <recipe> <speed %> <part item>".
pub fn payload_with_part(target: u64, def_id: u32, speed_pct: u32, part: u32) -> String {
    if part == 0 { payload(target, def_id, speed_pct) } else { format!("{target} {def_id} {speed_pct} {part}") }
}

/// A round's payload with how much the player's rank eases it (Luke's M3): "<target> <def> <speed %> <part> <ease %>";
/// with no ease, the payload as before (so an old client reads every round it can play the same).
pub fn payload_eased(target: u64, def_id: u32, speed_pct: u32, part: u32, ease_pct: u32) -> String {
    if ease_pct == 0 { payload_with_part(target, def_id, speed_pct, part) } else { format!("{target} {def_id} {speed_pct} {part} {ease_pct}") }
}

/// How much a payload eases its round (its fifth field), or 0.
pub fn parse_ease(payload: &str) -> u32 {
    payload.split(' ').nth(4).and_then(|p| p.parse().ok()).unwrap_or(0)
}

/// RANK EASES THE ROUND (Luke's M3, 2026-11-05: "a few percent wider windows a rank above the requirement, capped at
/// three"; for every skill, "rank eases the numbers; a band adds one rule"): `per_rank_pct` for each rank above
/// `min_rank`, at most `most_ranks` of them (`regents.rank_ease_pct`, `regents.rank_ease_ranks`).
pub fn rank_ease_pct(rank: u32, min_rank: u32, per_rank_pct: f64, most_ranks: f64) -> u32 {
    let above = rank.saturating_sub(min_rank.max(1)) as f64;
    (above.min(most_ranks.max(0.0)) * per_rank_pct.max(0.0)).round().min(50.0) as u32
}

/// The part a payload names (its fourth field), or 0.
pub fn parse_part(payload: &str) -> u32 {
    payload.split(' ').nth(3).and_then(|p| p.parse().ok()).unwrap_or(0)
}

pub fn parse_payload(payload: &str) -> Option<(u64, u32, u32)> {
    let mut p = payload.split(' ');
    Some((p.next()?.parse().ok()?, p.next()?.parse().ok()?, p.next()?.parse().ok()?))
}

// THE META (LOOT_AND_STYLES.md §7.5, owner priority; PROGRESS step 16): each weapon type's share of an
// hour's damage to foes, rolled up as the hour ends, with an alarm when one type dominates.

/// When the period of `period_s` seconds (`regents.meta_period_s`, an hour) that `micros` falls in began,
/// in Unix seconds.
pub fn meta_period(micros: i64, period_s: u32) -> u64 {
    let p = period_s.max(1) as i64;
    (micros.div_euclid(1_000_000).div_euclid(p) * p).max(0) as u64
}

/// Each weapon type's share of the damage in `damage`, in percent, in the same order (all 0 when none).
pub fn meta_shares(damage: &[f32]) -> Vec<f32> {
    let total: f32 = damage.iter().map(|d| d.max(0.0)).sum();
    damage.iter().map(|d| if total > 0.0 { d.max(0.0) / total * 100.0 } else { 0.0 }).collect()
}

/// Whether a share is an alarm: past `alarm_pct` (0: never) in an hour of at least `min_hits` hits.
pub fn meta_alarm(share_pct: f32, hour_hits: u32, alarm_pct: f64, min_hits: f64) -> bool {
    alarm_pct > 0.0 && hour_hits as f64 >= min_hits && share_pct as f64 > alarm_pct
}

/// The weapon type (its kit's key) that trains `skill_id`; "" for none.
pub fn kit_of_skill(skill_id: u32) -> &'static str {
    KITS.iter().find(|k| k.skill == skill_id).map_or("", |k| k.key)
}

// --- ITEM LEVELS AND PICKS (Luke's B1-B6, B15, 2026-11-13; ABILITIES_PREP.md §7 step 2) --------------------------
// An item's XP and its picks live in its own row's `instance_data` ("x", "k"), so they go wherever the item goes (a
// drop, a trade: B2's T4) and a refit keeps them (B15). Its LEVEL is its XP on its kind's mastery curve; a holder uses
// it only up to their own mastery (B2). The client's twin: `RegentsItemLevel`.

/// A kit skill's bar slot (`KitSeed::slots`): the base (Q), a pick option (E), an ult option (R), F.
pub const SLOT_BASE: u32 = 0;
pub const SLOT_OPTION: u32 = 1;
pub const SLOT_ULT: u32 = 2;
pub const SLOT_F: u32 = 3;

/// An item's XP (`"x"`); 0 for none.
pub fn item_xp_of(instance_data: &str) -> u32 {
    field_of(instance_data, "x").unwrap_or(0)
}

/// An item's picks (`"k":[first, second, ult]`): each an ability id, 0 unchosen.
pub fn picks_of(instance_data: &str) -> [u32; 3] {
    let mut out = [0u32; 3];
    if let Some(at) = instance_data.find("\"k\":[") {
        let rest = &instance_data[at + 5..];
        if let Some(end) = rest.find(']') {
            for (i, v) in rest[..end].split(',').filter_map(|s| s.trim().parse::<u32>().ok()).take(3).enumerate() {
                out[i] = v;
            }
        }
    }
    out
}

/// `instance_data` with `key` set to `value` (a number or an array, written as JSON): replaced where it is, else
/// added at the end; an empty `instance_data` becomes `{"key":value}`. Every other field is kept as written.
pub fn with_field(instance_data: &str, key: &str, value: &str) -> String {
    let tag = format!("\"{key}\":");
    let data = instance_data.trim();
    if let Some(at) = data.find(&tag) {
        let start = at + tag.len();
        let rest = &data[start..];
        let len = if rest.starts_with('[') {
            rest.find(']').map_or(rest.len(), |e| e + 1)
        } else {
            rest.find([',', '}']).unwrap_or(rest.len())
        };
        return format!("{}{}{}", &data[..start], value, &rest[len..]);
    }
    match data.rfind('}') {
        Some(end) if data[..end].trim_end().ends_with('{') => format!("{}{tag}{value}{}", &data[..end], &data[end..]),
        Some(end) => format!("{},{tag}{value}{}", &data[..end], &data[end..]),
        None => format!("{{{tag}{value}}}"),
    }
}

/// `instance_data` with the item's XP `xp`.
pub fn with_item_xp(instance_data: &str, xp: u32) -> String {
    with_field(instance_data, "x", &xp.to_string())
}

/// `fresh` (an item's new `instance_data`, a refit's) with `old`'s level and picks kept (B15).
pub fn keep_level(old: &str, fresh: &str) -> String {
    let mut out = fresh.to_string();
    if old.contains("\"x\":") {
        out = with_item_xp(&out, item_xp_of(old));
    }
    if old.contains("\"k\":[") {
        out = with_picks(&out, picks_of(old));
    }
    out
}

/// `instance_data` with the item's picks.
pub fn with_picks(instance_data: &str, picks: [u32; 3]) -> String {
    with_field(instance_data, "k", &format!("[{},{},{}]", picks[0], picks[1], picks[2]))
}

/// The level an item with `xp` is at, on its kind's mastery curve `s` (B1: the same 1-33 track).
pub fn item_level(s: &SkillSeed, xp: u32) -> u32 {
    rank_of(s, xp)
}

/// The level an item counts as in the hands of a holder of `mastery` (B2, T4: used only up to your mastery).
pub fn usable_level(item_level: u32, mastery: u32) -> u32 {
    item_level.min(mastery.max(1))
}

/// The XP an item earns of `xp` its holder earned (B1, CATCH-UP): `mult` times as much while the item is below its
/// holder's mastery, as much at or above it.
pub fn item_xp_gain(xp: u32, item_level: u32, mastery: u32, mult: f64) -> u32 {
    if item_level < mastery {
        (xp as f64 * mult.max(1.0)).round() as u32
    } else {
        xp
    }
}

impl KitSeed {
    /// Whether the kit has an ult of its own (a skill on `SLOT_ULT`). Until it does, its last pick takes an option.
    pub fn has_ults(&self) -> bool {
        self.slots.contains(&SLOT_ULT)
    }

    /// Whether skill `ability` is in role `role`'s pool: claimed by it, or by no role (S1b). Role 0: any pool (the
    /// kit as one, as before roles had pools).
    pub fn in_pool(&self, ability: u32, role: u32) -> bool {
        role == 0 || !self.role_skills.iter().any(|(r, a)| *a == ability && *r != role)
    }

    /// Whether role `role`'s pool has an ult of its own.
    pub fn has_ults_for(&self, role: u32) -> bool {
        self.skills.iter().zip(self.slots.iter()).any(|((a, _), s)| *s == SLOT_ULT && self.in_pool(*a, role))
    }

    /// The bar slot skill `ability` goes to in role `role`'s pool; None when it is not in that pool.
    pub fn pool_slot(&self, ability: u32, role: u32) -> Option<u32> {
        self.in_pool(ability, role).then(|| self.slot_of(ability)).flatten()
    }

    /// An item's stored picks as role `role` reads them: one of an ability outside its pool is no pick (empty: it may be
    /// chosen again, free, never a crash: the picks a sword kept from the one pool before S1b).
    pub fn own_picks(&self, picks: [u32; 3], role: u32) -> [u32; 3] {
        picks.map(|a| if a != 0 && self.pool_slot(a, role).is_none() { 0 } else { a })
    }

    /// The bar slot skill `ability` goes to (`SLOT_*`); None when it is not one of this kit's skills.
    pub fn slot_of(&self, ability: u32) -> Option<u32> {
        let i = self.skills.iter().position(|(a, _)| *a == ability)?;
        Some(self.slots.get(i).copied().unwrap_or(SLOT_BASE))
    }

    /// Whether a PLAYER may use skill `ability` with an item they use at `usable` with `picks`: why not, or None.
    /// The base and F from `unlock_levels[0]`; an option only as one of the item's picks, from that pick's level; an
    /// ult only as its ult, from the ult's level. A kit with no slots (a foe's) gates nothing.
    pub fn slot_refusal(&self, ability: u32, usable: u32, picks: [u32; 3]) -> Option<String> {
        self.slot_refusal_for(ability, usable, picks, 0)
    }

    /// `slot_refusal` for a weapon of role `role` (S1b): a skill of another role's pool is refused.
    pub fn slot_refusal_for(&self, ability: u32, usable: u32, picks: [u32; 3], role: u32) -> Option<String> {
        if self.slots.is_empty() {
            return None;
        }
        let slot = self.slot_of(ability)?;
        if !self.in_pool(ability, role) {
            return Some("not this weapon's: its handle gives other abilities".into());
        }
        let picks = self.own_picks(picks, role);
        let at = |n: usize| self.unlock_levels[n];
        match slot {
            SLOT_OPTION => {
                // On E from one of the first two picks; or on R from the last, while the kit has no ult of its own.
                let Some(j) = (0..3).find(|j| picks[*j] == ability && (*j < 2 || !self.has_ults_for(role))) else {
                    return Some("not chosen: choose it at one of the weapon's picks".into());
                };
                (usable < at(1 + j)).then(|| format!("opens at the weapon's level {} (it counts as {usable} for you)", at(1 + j)))
            }
            SLOT_ULT => {
                if picks[2] != ability {
                    return Some("not chosen: choose it as the weapon's last pick".into());
                }
                (usable < at(3)).then(|| format!("opens at the weapon's level {} (it counts as {usable} for you)", at(3)))
            }
            _ => (usable < at(0)).then(|| format!("opens at the weapon's level {} (it counts as {usable} for you)", at(0))),
        }
    }

    /// Whether `choice` may be chosen at pick `n` (0 the first, 1 the second, 2 the ult) of an item used at `usable`
    /// with `picks`: why not, or None. A pick opens at its level; a newly opened pick is free to choose; a chosen one is
    /// CHANGED (`change_refusal`, `change_pick`: Luke's B13). The first two take a pick option into E
    /// (E holds one: the other takes an upgrade, once there are any); the last an ult option.
    pub fn pick_refusal(&self, n: u32, choice: u32, usable: u32, picks: [u32; 3]) -> Option<String> {
        self.pick_refusal_for(n, choice, usable, picks, 0)
    }

    /// `pick_refusal` for a weapon of role `role` (S1b): only its pool's options and ult; a stored pick outside it is empty.
    pub fn pick_refusal_for(&self, n: u32, choice: u32, usable: u32, picks: [u32; 3], role: u32) -> Option<String> {
        if n > 2 {
            return Some("no such pick (0, 1 or 2)".into());
        }
        let picks = self.own_picks(picks, role);
        let at = self.unlock_levels[1 + n as usize];
        if usable < at {
            return Some(format!("that pick opens at the weapon's level {at} (it counts as {usable} for you)"));
        }
        let mine = picks[n as usize];
        if mine == choice && choice != 0 {
            return Some("already chosen".into());
        }
        if mine != 0 {
            return Some("chosen already: change it instead (free once a week from level 20, else at a workbench)".into());
        }
        // THE LAST PICK, R (Luke, 2026-11-14: "fix the R ability not being assigned"): an ult; while the kit has none of
        // its own, the option E did not take (a staff ends with all four spells).
        let want = if n == 2 && self.has_ults_for(role) { SLOT_ULT } else { SLOT_OPTION };
        if self.pool_slot(choice, role) != Some(want) || self.slots.is_empty() {
            return Some(if n == 2 { "that is not one of this weapon's last picks" } else { "that is not one of this weapon's picks" }.into());
        }
        if (0..3).any(|j| j != n as usize && picks[j] == choice) {
            return Some("it is on the weapon already, at another pick".into());
        }
        if n < 2 && self.pool_slot(picks[1 - n as usize], role) == Some(SLOT_OPTION) {
            return Some("E holds one ability: this pick will take an upgrade, once there are any".into());
        }
        None
    }
}

// --- CHANGING A PICK (Luke's B13, 2026-11-13: "I like 2, 3, 4, 5 ... before level 20, the price should be equal to the
// amount of abilities unlocked so respecing one thing cost less than 3 or all 4") ----------------------------------
// One FREE change a week per item, from its level 20 (none below). Past it, the HEAD'S MATERIAL at a workbench, per pick
// changed, doubling with each paid change (1x, 2x, 4x), the doubling stepping back once a week without one. A newly
// opened pick stays free to choose (`pick_refusal`). The item keeps when (`"f"`: its last free change, seconds), how far
// the price has climbed (`"e"`: doublings) and when it last paid (`"c"`: seconds) in its own data. Every number is a hot
// rule (`regents.respec_*`). The client's twin: `RegentsItemLevel.change_price`.

/// When the item's last free change was (unix seconds; 0: never).
pub fn last_free_change(instance_data: &str) -> u32 {
    field_of(instance_data, "f").unwrap_or(0)
}

/// How many times its price has doubled, as stored (`"e"`), and when it last paid (`"c"`, unix seconds).
pub fn change_escalation(instance_data: &str) -> (u32, u32) {
    (field_of(instance_data, "e").unwrap_or(0), field_of(instance_data, "c").unwrap_or(0))
}

/// The doublings in force at `now_s`: those stored, one fewer for each `halve_days` since the last paid change.
pub fn escalation_now(steps: u32, last_paid_s: u32, now_s: u32, halve_days: f64) -> u32 {
    if steps == 0 || halve_days <= 0.0 {
        return if halve_days <= 0.0 { 0 } else { steps };
    }
    let weeks = (now_s.saturating_sub(last_paid_s) as f64 / (halve_days * 86_400.0)).floor() as u32;
    steps.saturating_sub(weeks)
}

/// Whether an item at `level` has its free change now: from `free_level`, and none in the last `free_days`.
pub fn free_change_open(level: u32, free_level: u32, last_free_s: u32, now_s: u32, free_days: f64) -> bool {
    level >= free_level && (last_free_s == 0 || now_s.saturating_sub(last_free_s) as f64 >= free_days.max(0.0) * 86_400.0)
}

/// What a paid change takes of the head's material: `base`, doubled `steps` times (at most `max_steps`).
pub fn change_qty(base: u32, steps: u32, max_steps: u32) -> u32 {
    base.saturating_mul(1u32 << steps.min(max_steps).min(16))
}

/// THE HEAD'S MATERIAL of a made item (what a refit charges too): the core input of its recipe (the input no part slot
/// takes: the head), and what THAT is made of first (an iron blade: Iron bar); a core nothing makes is itself (a stave's
/// logs). None for an item no recipe makes.
pub fn head_material(item_id: u32) -> Option<u32> {
    let r = RECIPES.iter().find(|r| r.output == item_id)?;
    let core = r.inputs.iter().enumerate().find(|(i, _)| !r.part_slots.contains(&(*i as i32))).map(|(_, (item, _))| *item)?;
    Some(RECIPES.iter().find(|x| x.output == core).and_then(|x| x.inputs.first()).map_or(core, |(item, _)| *item))
}

impl KitSeed {
    /// Whether pick `n`, chosen already, may be CHANGED to `choice` with an item used at `usable` with `picks`: why not,
    /// or None. What may be chosen there is what a newly opened pick may take, the old choice set aside (B13).
    pub fn change_refusal(&self, n: u32, choice: u32, usable: u32, picks: [u32; 3]) -> Option<String> {
        self.change_refusal_for(n, choice, usable, picks, 0)
    }

    /// `change_refusal` for a weapon of role `role` (S1b).
    pub fn change_refusal_for(&self, n: u32, choice: u32, usable: u32, picks: [u32; 3], role: u32) -> Option<String> {
        if n > 2 {
            return Some("no such pick (0, 1 or 2)".into());
        }
        let picks = self.own_picks(picks, role);
        let mine = picks[n as usize];
        if mine == 0 {
            return Some("nothing chosen there yet: choose it, no change needed".into());
        }
        if mine == choice {
            return Some("already chosen".into());
        }
        let mut cleared = picks;
        cleared[n as usize] = 0;
        self.pick_refusal_for(n, choice, usable, cleared, role)
    }
}
