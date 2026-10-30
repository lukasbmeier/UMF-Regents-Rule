//! REGENT'S RULE'S PURE RULES (docs/regents_rule/RULE_DESIGN.md §7.4). No `spacetimedb` dependency, so
//! native tests check them (`server/tests/regents.rs`); `game/regents.rs` applies them: the skilling
//! chain's content (compiled in from game/regents/content/ by `server/build/regents.rs`), its four
//! minigames' replays, mastery ranks, a tool's speed, what a round or an AFK item yields, and the rolls.

pub mod chop;
pub mod crack;
pub mod rng;
pub mod shape;
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
/// What a new character is given, once (`content/item/`): a Copper axe and a Copper pickaxe.
pub const STARTER_KIT: &[u32] = &[40001, 40006];

pub static CLAIMS: crate::genre::Claims = crate::genre::Claims {
    name: "regents",
    challenge_kinds: &[CHALLENGE_CHOP, CHALLENGE_CRACK, CHALLENGE_SMELT, CHALLENGE_SHAPE],
    // The foes' kinds are content (`FoeDef`, `content/foe/`): the genre keeps 103-119 for them (FOE_KINDS).
    entity_kinds: &[ENTITY_NODE, ENTITY_STATION, ENTITY_DUMMY, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116,
        117, 118, 119],
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
    pub outline: &'static [i64],
    pub error_scale: i64,
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
            outline: self.outline.to_vec(),
            error_scale: self.error_scale,
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
        }
    }

    /// A round REPLAYED from what the client sent, at tool speed `speed_pct` (a gathering round's swing:
    /// `SkillMinigames.with_speed`): its score in thousandths, or None when the submission is not a round.
    pub fn score(&self, seed: u64, speed_pct: i64, result: &[f32]) -> Option<i64> {
        let groups = (self.duration_ms() / 50 + 64) as usize;
        let swing = |s: i64| (s * speed_pct / 100).max(50);
        match self {
            Minigame::None => None,
            Minigame::Chop(p) => {
                let p = chop::ChopParams { swing_ms: swing(p.swing_ms), ..*p };
                let ins = rng::decode_groups(result, 2, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i32)> = ins.iter().map(|g| (g[0], g[1] as i32)).collect();
                Some(chop::play(seed, &p, &ins).score_pm)
            }
            Minigame::Crack(p) => {
                let p = crack::CrackParams { swing_ms: swing(p.swing_ms), ..*p };
                let ins = rng::decode_groups(result, 3, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i64, i64)> = ins.iter().map(|g| (g[0], g[1], g[2])).collect();
                Some(crack::play(seed, &p, &ins).score_pm)
            }
            Minigame::Smelt(p) => {
                let ins = rng::decode_groups(result, 2, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i64)> = ins.iter().map(|g| (g[0], g[1])).collect();
                Some(smelt::play(seed, p, &ins).score_pm)
            }
            Minigame::Shape(s) => {
                let ins = rng::decode_groups(result, 2, groups, -1.0, 600_000.0)?;
                let ins: Vec<(i64, i64)> = ins.iter().map(|g| (g[0], g[1])).collect();
                Some(shape::play(seed, &s.params(), &ins).score_pm)
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
    /// The light combo, in order.
    pub light: &'static [u32],
    pub heavy: u32,
    /// Q, E, R, F: (ability, the mastery rank it unlocks at).
    pub skills: &'static [(u32, u32)],
    pub combo_window_ms: u32,
    /// After a light swing lands, this long before the combo's next step may start.
    pub chain_ms: u32,
    /// Each ability's lock: how long a swing holds its fighter (its clip's length, baked).
    pub locks: &'static [(u32, u32)],
    /// A drawn kit (a bow): its full draw, in ms. 0: a melee kit.
    pub draw_full_ms: u32,
    /// A casting kit (the Staff): its pool's resource id (mana); its abilities are spells. 0: none.
    pub resource: u32,
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
    /// How long `ability_id` locks its fighter (0: not this kit's).
    pub fn lock_ms(&self, ability_id: u32) -> u32 {
        self.locks.iter().find(|(a, _)| *a == ability_id).map_or(0, |(_, ms)| *ms)
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
    /// The kit it fights with (a `KitSeed` key).
    pub kit: &'static str,
    pub hp: u32,
    /// Its hits, as a weapon of this damage %.
    pub damage_pct: u32,
    /// Mastery XP for hitting it, as a share of the usual (%).
    pub xp_pct: u32,
    /// What a kill drops: its loot table's content id (`loot::LOOT_TABLES`; 0: nothing).
    pub loot_table: u32,
    /// Its family ("undead", "beast"): what a trait made against one reads.
    pub family: &'static str,
}

/// The entity kinds a foe may be (CLAIMS keeps them for this genre).
pub const FOE_KINDS: std::ops::RangeInclusive<u8> = 103..=119;

/// Where an ability sits in its kit.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KitSlot {
    /// The light combo's step (0 first).
    Light(u32),
    Heavy,
    /// A skill key (0 Q .. 3 F) and the rank it needs.
    Skill(u32, u32),
}

include!(concat!(env!("OUT_DIR"), "/regents_data.rs"));

/// The dodge roll (`content/ability/dodge.tres`): everyone's, whatever they wield.
pub const ABILITY_DODGE: u32 = 40010;
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
/// The arrow (`content/body/arrow.tres`): what a bow looses.
pub const BODY_ARROW: u32 = 40001;
/// Gravity on an arrow (Godot's, which the referee flies it by), m/s².
pub const ARROW_GRAVITY: f32 = 9.8;
/// The training dummy's entity kind (`content/character/dummy.tres`) and its level points.
pub const ENTITY_DUMMY: u8 = 102;
pub const DUMMY_POINT: &str = "dummy";

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

/// The kit `ability_id` is part of, and where in it; None for an ability no kit has (the dodge).
pub fn kit_of_ability(ability_id: u32) -> Option<(&'static KitSeed, KitSlot)> {
    for k in KITS {
        if let Some(i) = k.light.iter().position(|a| *a == ability_id) {
            return Some((k, KitSlot::Light(i as u32)));
        }
        // A kit with no heavy (a bow) bakes its heavy as 0, which is also an ability (the foundation's melee).
        if k.heavy != 0 && k.heavy == ability_id {
            return Some((k, KitSlot::Heavy));
        }
        if let Some(i) = k.skills.iter().position(|(a, _)| *a == ability_id) {
            return Some((k, KitSlot::Skill(i as u32, k.skills[i].1)));
        }
    }
    None
}

/// A hit's damage (owner, 2026-10-19): the ability's, times the weapon's `weapon_damage_pct`, its
/// quality adding up to a fifth more, and 3 % a mastery rank past the first (at most 27 %).
pub fn hit_damage(ability_damage: f32, weapon_damage_pct: u32, quality_pm: u32, rank: u32) -> f32 {
    let quality = 1.0 + quality_pm.min(1000) as f32 / 5000.0;
    let mastery = 1.0 + (3 * rank.saturating_sub(1)).min(27) as f32 / 100.0;
    ability_damage * weapon_damage_pct as f32 / 100.0 * quality * mastery
}

/// Whether a light step `step` may follow: the first always; a later one only right after the step
/// before it, inside the kit's window (`last_step` -1: no combo going).
pub fn combo_allows(step: u32, last_step: i32, since_ms: i64, window_ms: u32) -> bool {
    step == 0 || (last_step == step as i32 - 1 && since_ms >= 0 && since_ms <= window_ms as i64)
}

/// The refusal of a light step the combo does not allow (`combo_allows`).
pub const OUT_OF_ORDER: &str = "out of the combo's order";
/// One after a swing that was cut short (a heavy's flinch or a roll in its wind-up): said apart, because the
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
/// The combo's next light step from `wind_up + chain` (the recovery cancels into it); anything else
/// once the lock is over. `slack` forgives the network; a cancelled swing (a roll) holds nothing.
pub fn swing_allows(next_is_chain: bool, t: i64, wind_up: i64, chain: i64, lock: i64, slack: i64, cancelled: bool) -> bool {
    if cancelled {
        return true;
    }
    let from = if next_is_chain { (wind_up + chain).min(lock) } else { lock };
    t >= from - slack
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
/// (thousandths), and 3 % off per rank above the first (at most 27 %). Never under 10 %.
pub fn speed_pct(tool_speed_pct: u32, quality_pm: u32, rank: u32) -> u32 {
    let q = quality_pm.min(1000) as u64;
    let with_quality = tool_speed_pct as u64 * (10_000 - q) / 10_000;
    let rank_off = (3 * rank.saturating_sub(1)).min(27) as u64;
    ((with_quality * (100 - rank_off) / 100) as u32).max(10)
}

/// AFK's interval at speed `speed_pct`.
pub fn afk_interval_ms(afk_ms: u32, speed_pct: u32) -> u32 {
    (afk_ms as u64 * speed_pct as u64 / 100).max(100) as u32
}

/// How much a round yields, in thousandths: what AFK makes in the round's time (at its interval),
/// times `active_mult`, times the round's score (owner, 2026-10-18, design #23: a poor round falls short).
pub fn active_yield_milli(afk_interval_ms: u32, round_ms: i64, active_mult: f64, score_pm: i64) -> u64 {
    let afk_milli = round_ms as f64 * 1000.0 / afk_interval_ms.max(1) as f64;
    (afk_milli * active_mult * score_pm.clamp(0, 1000) as f64 / 1000.0).floor().max(0.0) as u64
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

/// WHAT AN ACTION IS, for traits (`TraitAtom.on`): a light step is "basic" (and "combo_last" for its
/// kit's last), a heavy "heavy", a skill "skill".
pub fn action_tags(kit: &KitSeed, slot: KitSlot) -> Vec<&'static str> {
    match slot {
        KitSlot::Light(step) if step as usize + 1 == kit.light.len() => vec!["basic", "combo_last"],
        KitSlot::Light(_) => vec!["basic"],
        KitSlot::Heavy => vec!["heavy"],
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
