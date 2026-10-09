//! Fishing's rules, from `shared/fishing/fishing.json` (compiled in by build.rs): the catalog,
//! the spots' loot, the gear tracks, and the timings a cast and a bite run on. The tables and
//! reducers that use them are `game/fishing.rs`; the client reads the same JSON through
//! `game/fishing/fishing_data.gd`.
//!
//! THE SERVER ROLLS, THE CLIENT PLAYS. Everything that decides what you catch happens here, from
//! the cast's seed, at the moment the float lands: which spot, what is on the line, how heavy,
//! when it bites. The client is told (the challenge row is private to its owner) so it can play
//! the bite honestly, and submits only its reaction. That is the part of Fishing for Compliments
//! left behind: there the client chose its own catch and reported its own combo.
//!
//! PARITY: `grade_hookset` has a GDScript twin (`FishingData.grade_hookset`) that the player sees
//! the verdict from before the server's arrives; both run `shared/golden/fishing/hookset.json`.
//! Thresholds are f32 on both sides, so a reaction on a boundary grades the same everywhere. The
//! rolls have no twin: the client never predicts them.

/// THE FIGHT, fishing's minigame (`genre::fishing::fight`).
pub mod fight;

pub struct Category {
    pub id: &'static str,
    pub word: &'static str,
    /// 0 (trash) upward. Drives nothing here yet; the HUD colours by it.
    pub rarity: u8,
    /// Fish fight, junk is dead weight (the fight uses this; the roll does not).
    pub alive: bool,
}

pub struct CatchDef {
    pub id: &'static str,
    pub name: &'static str,
    /// Index into `CATEGORIES`.
    pub category: usize,
    /// Typical weight. A caught one is rolled around this (`roll_kg`).
    pub kg: f32,
    /// Coins for a typical one, cleanly hooked.
    pub value: i64,
    /// The props-kit model the fly-out shows, or "" for a fish.
    pub model: &'static str,
}

pub struct SpotLoot {
    /// A level bake's spot id, or "" for open water.
    pub id: &'static str,
    /// The rod tier that reaches this spot AT ALL (FfC's `min_rod`): the level puts the spot out
    /// of a lesser rod's reach from anywhere a player can stand. Checked by `tests/level.rs`.
    pub min_rod: u8,
    /// Divides the bite delay: above 1, bites come faster.
    pub bite_speed: f32,
    /// (category index, relative weight), in a fixed order.
    pub loot: &'static [(usize, f32)],
}

pub struct Rod {
    pub name: &'static str,
    pub cost: i64,
    pub max_cast_m: f32,
    pub reel_power: f32,
}

pub struct Reel {
    pub name: &'static str,
    pub cost: i64,
    pub reel_speed: f32,
    pub hookset_window_mult: f32,
}

pub struct Line {
    pub name: &'static str,
    pub cost: i64,
    pub max_load_kg: f32,
    pub tension_ceiling: f32,
}

/// A time of day: each round is one (DECISIONS #168).
pub struct TimeOfDay {
    pub id: &'static str,
    pub name: &'static str,
    /// Divides the bite delay, times the spot's.
    pub bite_speed: f32,
}

/// A round's weather, rolled by `weight` when its lobby opens.
pub struct Weather {
    pub id: &'static str,
    pub name: &'static str,
    pub weight: f32,
    pub bite_speed: f32,
}

/// The rival angler a module-run world gets (DECISIONS #169).
pub struct RivalDef {
    pub level: &'static str,
    pub name: &'static str,
    pub stand: [f32; 3],
    pub yaw_deg: f32,
    pub rod_tier: u8,
    pub spots: &'static [&'static str],
    pub rest_s: (f32, f32),
    pub fight_s: (f32, f32),
    pub fight_s_per_kg_sqrt: f32,
    pub land_chance: &'static [f32],
}

include!(concat!(env!("OUT_DIR"), "/fishing_data.rs"));

/// The challenge kind a cast opens: the first genre kind.
pub const KIND_FISH: u8 = crate::challenge::KIND_GENRE_FROM;

/// The numbers fishing takes for itself (DECISIONS #173): the cast's challenge kind. Its spots are
/// the foundation's resource nodes and its rival the foundation's NPC kind, so no entity kind.
pub static CLAIMS: crate::genre::Claims = crate::genre::Claims {
    name: "fishing",
    challenge_kinds: &[KIND_FISH],
    entity_kinds: &[],
    phases: &[],
    session_kinds: &[],
};

// =============================================================================================
// CONDITIONS (DECISIONS #168)
// =============================================================================================

/// A round's time of day and weather, as indices into `TIMES` and `WEATHERS`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Conditions {
    pub time: u8,
    pub weather: u8,
}

impl Conditions {
    /// The condition ids that `LIKES` are keyed by.
    pub fn tags(&self) -> [&'static str; 2] {
        [
            TIMES.get(self.time as usize).map(|t| t.id).unwrap_or(""),
            WEATHERS.get(self.weather as usize).map(|w| w.id).unwrap_or(""),
        ]
    }

    /// How much faster than usual things bite under these conditions.
    pub fn bite_speed(&self) -> f32 {
        TIMES.get(self.time as usize).map(|t| t.bite_speed).unwrap_or(1.0)
            * WEATHERS.get(self.weather as usize).map(|w| w.bite_speed).unwrap_or(1.0)
    }
}

/// Each round is one time of day, in order: round 1 the first.
pub fn time_for_round(round: u32) -> u8 {
    ((round.max(1) - 1) as usize % TIMES.len()) as u8
}

/// A round's weather, by weight.
pub fn roll_weather(dice: &mut Dice) -> u8 {
    let total: f32 = WEATHERS.iter().map(|w| w.weight).sum();
    let mut pick = dice.unit() * total;
    for (i, w) in WEATHERS.iter().enumerate() {
        pick -= w.weight;
        if pick < 0.0 {
            return i as u8;
        }
    }
    (WEATHERS.len() - 1) as u8
}

/// The product of every like for `category` (or, with `catch_id`, for that one catch) under `tags`.
pub fn likes(category: usize, catch_id: &str, tags: &[&str]) -> f32 {
    let mut m = 1.0f32;
    for (cat, id, cond, mult) in LIKES {
        let about = if catch_id.is_empty() { *cat == category && id.is_empty() } else { *id == catch_id };
        if about && tags.contains(cond) {
            m *= *mult;
        }
    }
    m
}

// =============================================================================================
// DICE
// =============================================================================================

/// xorshift32, the same generator the challenge validator uses. Deterministic from the seed, so
/// a roll can be re-run from a challenge row and argued with.
pub struct Dice(u32);

impl Dice {
    /// Fold a 64-bit seed into a non-zero state. `salt` separates independent streams drawn
    /// from one seed (the catch, the bite), so changing how many numbers one of them draws does
    /// not reshuffle the other.
    pub fn new(seed: u64, salt: u64) -> Self {
        // Mix before folding: consecutive seeds differ only in low bits, which one xorshift
        // round does not carry into the top bits `unit` reads (see game/fishing.rs, spot mix).
        let mixed = (seed ^ salt).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        let s = (mixed ^ (mixed >> 32)) as u32;
        let mut d = Dice(if s == 0 { 1 } else { s });
        d.next_u32();
        d.next_u32();
        d
    }

    pub fn next_u32(&mut self) -> u32 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.0 = x;
        x
    }

    /// [0, 1), 24 bits, exact in f32.
    pub fn unit(&mut self) -> f32 {
        ((self.next_u32() >> 8) as f32) / 16_777_216.0f32
    }
}

pub const SALT_CATCH: u64 = 0xCA7C_4000_0000_0001;
pub const SALT_BITE: u64 = 0xB17E_0000_0000_0002;
/// The fight's own random stream (`genre::fight`: where the catch wanders, when junk snags).
pub const SALT_FIGHT: u64 = 0xF16B_7000_0000_0003;
/// A round's weather, from its seed (DECISIONS #168).
pub const SALT_WEATHER: u64 = 0x3EA7_4E40_0000_0004;
/// The rival's casts, from the round's seed and his cast count (DECISIONS #169).
pub const SALT_RIVAL: u64 = 0x41BA_1000_0000_0005;

// =============================================================================================
// THE ROLL
// =============================================================================================

/// The loot table for a spot id; open water for "" or an id with no table.
pub fn spot_loot(spot_id: &str) -> &'static SpotLoot {
    SPOTS.iter().find(|s| s.id == spot_id).unwrap_or(&OPEN_WATER)
}

pub fn catch_def(id: &str) -> Option<&'static CatchDef> {
    CATCHES.iter().find(|c| c.id == id)
}

/// What is on the line: a category by the spot's weights, then a catch inside that category,
/// weighted by 1/sqrt(kg) so the small ones are the common ones. Carried over from Fishing for
/// Compliments' LootTable, moved to where the client cannot choose the answer.
///
/// `tags` are the round's conditions (`Conditions::tags`; empty for none): each category's
/// weight, and each catch's inside it, is multiplied by what it `likes` under them.
pub fn roll_catch(dice: &mut Dice, spot: &SpotLoot, tags: &[&str]) -> &'static CatchDef {
    let liked = |c: usize, w: f32| w * likes(c, "", tags);
    let total: f32 = spot.loot.iter().map(|(c, w)| liked(*c, *w)).sum();
    let mut category = spot.loot.first().map(|(c, _)| *c).unwrap_or(0);
    if total > 0.0 {
        let mut pick = dice.unit() * total;
        for (c, w) in spot.loot {
            category = *c;
            pick -= liked(*c, *w);
            if pick < 0.0 {
                break;
            }
        }
    }
    let members: Vec<&'static CatchDef> = CATCHES.iter().filter(|d| d.category == category).collect();
    if members.is_empty() {
        return &CATCHES[0];
    }
    let weight = |d: &CatchDef| likes(d.category, d.id, tags) / d.kg.max(0.05).sqrt();
    let total: f32 = members.iter().map(|d| weight(d)).sum();
    let mut pick = dice.unit() * total;
    for d in &members {
        pick -= weight(d);
        if pick < 0.0 {
            return d;
        }
    }
    members[members.len() - 1]
}

/// How heavy THIS one is: 75% to 125% of its kind's typical weight.
pub fn roll_kg(dice: &mut Dice, def: &CatchDef) -> f32 {
    def.kg * (0.75 + 0.5 * dice.unit())
}

/// Seconds from the float landing to the bite. `u` is a uniform draw; a rich spot and an
/// uncrowded one bite faster, a fished-out one slower.
///
/// `speed` is the round's conditions (`Conditions::bite_speed`; 1.0 for none).
pub fn bite_delay(u: f32, spot: &SpotLoot, richness: f32, others_in_spot: u32, speed: f32) -> f32 {
    let base = BITE_MIN_S + (BITE_MAX_S - BITE_MIN_S) * u.clamp(0.0, 1.0);
    let rich = 0.5 + 0.5 * richness.clamp(0.0, 1.0);
    let crowd = (1.0 - CROWDING_PENALTY * others_in_spot as f32).max(0.4);
    (base / (spot.bite_speed.max(0.05) * speed.max(0.05) * rich * crowd)).min(BITE_CAP_S)
}

/// Coins for a landed catch: its value, scaled by how big this one is against a typical one and
/// by how cleanly it was hooked. A deadlift (heavier than the line is rated for) pays double.
pub fn coins_for(def: &CatchDef, kg: f32, quality: f32, deadlift: bool) -> i64 {
    let size = (kg / def.kg.max(0.001)).clamp(0.5, 2.0);
    let clean = 0.6 + 0.4 * quality.clamp(0.0, 1.0);
    let mult = if deadlift { 2.0 } else { 1.0 };
    ((def.value as f32) * size * clean * mult).round().max(1.0) as i64
}

// =============================================================================================
// THE HOOK-SET
// =============================================================================================

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HookSet {
    Perfect,
    Good,
    Late,
}

impl HookSet {
    pub fn quality(self) -> f32 {
        match self {
            HookSet::Perfect => 1.0,
            HookSet::Good => 0.75,
            HookSet::Late => 0.45,
        }
    }

    pub fn word(self) -> &'static str {
        match self {
            HookSet::Perfect => "perfect",
            HookSet::Good => "good",
            HookSet::Late => "late",
        }
    }
}

/// How long the hook-set window is with this reel.
pub fn hookset_window(window_mult: f32) -> f32 {
    HOOKSET_WINDOW_S * window_mult
}

/// Grade a reaction: seconds from the bite to the press. None when it is not a hook-set at all —
/// faster than a person can react (a guess, or a bot reading the row), or after the window shut
/// (it spat the hook). The reel widens the window; PERFECT and LATE stay where they are, so a
/// better reel buys forgiveness at the slow end rather than a free perfect.
pub fn grade_hookset(reaction: f32, window_mult: f32) -> Option<HookSet> {
    if !reaction.is_finite() || reaction < MIN_REACTION_S {
        return None;
    }
    if reaction > hookset_window(window_mult) {
        return None;
    }
    Some(if reaction <= HOOKSET_PERFECT_S {
        HookSet::Perfect
    } else if reaction >= HOOKSET_LATE_S {
        HookSet::Late
    } else {
        HookSet::Good
    })
}

// =============================================================================================
// GEAR
// =============================================================================================

pub fn rod(tier: u8) -> &'static Rod {
    &RODS[(tier as usize).min(RODS.len() - 1)]
}

pub fn reel(tier: u8) -> &'static Reel {
    &REELS[(tier as usize).min(REELS.len() - 1)]
}

pub fn line(tier: u8) -> &'static Line {
    &LINES[(tier as usize).min(LINES.len() - 1)]
}

/// The highest tier on every track.
pub fn max_tier() -> u8 {
    (RODS.len().min(REELS.len()).min(LINES.len()) - 1) as u8
}
