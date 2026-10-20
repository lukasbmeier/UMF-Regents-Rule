//! REGENT'S RULE (docs/regents_rule/RULE_DESIGN.md §7.4), the server's half: THE SKILLING CHAIN. Gather
//! (woodcutting, mining) at NODES, work materials (smelting, smithing, crafting) at STATIONS, each two ways
//! at the player's choice (owner, 2026-10-18):
//!
//!   the world  a level's `node` points (tagged with a NodeDef's name) and `station` points (tagged with a
//!              StationDef's key) become entities (`gather_node`, `station` rows); everyone shares them.
//!              A node worked out is in the Depleted status for its `regrow_ms`, then works again.
//!   AFK        tap E: `gather(node, false)` / `craft(station, recipe, false)`, an `afk_work` row;
//!              `work_tick` makes one item (or batch) every interval until the player moves
//!              `regents.afk_stop_moving_m`, the node is worked out, the bag runs out of inputs, or
//!              `work_stop`.
//!   active     hold E: the same call with `active`, dealing a round of the node's or recipe's minigame
//!              (a challenge of this genre's kinds; its payload "<target> <def> <speed %>"). The client
//!              plays it and submits its inputs; `resolve_challenge` REPLAYS them (`genre::regents`'s
//!              twins of the client's models, held to golden files) and pays: what AFK makes in the
//!              round's time x `regents.active_yield_mult` x the score, or (a smithed part) one, as good as
//!              the score.
//!   mastery    every item gives XP in its skill (`skill_xp`); ranks gate nodes and recipes; a rank and a
//!              better tool make work faster (`genre::regents::speed_pct`).
//!
//! A tool is the best of its tag in the bag (design #15); a new character is given a Bronze axe and a
//! Bronze pickaxe, once. What came out is a `work_result` row everyone in the world sees for a moment.

use spacetimedb::{reducer, table, ReducerContext, ScheduleAt, Table, TimeDuration, Timestamp};

use crate::genre::regents::{self as rules, Minigame, NodeSeed, RecipeSeed, ENTITY_NODE, ENTITY_STATION, LEVEL_FRONTIER, STATUS_DEPLETED};
use crate::hot::regents as hot;
use crate::module::{
    ability_def, challenge, entity, health_state, hot_number, inventory_item, item_def, movement_state, npc_brain, player, status_state,
    world_config, world_level, Challenge, InventoryItem, ItemDef, StatusStateRow, DEFAULT_WORLD,
};
use crate::sim::Vector3;

/// How often AFK work is looked at.
const WORK_TICK_MICROS: i64 = 250_000;
/// How long a work_result row is kept for everyone to see.
const RESULT_TTL_MICROS: i64 = 10_000_000;
/// A round's inputs may claim to be this far ahead of the server's clock (one way's lag, and the
/// client's own frame); further, they were not played as the round ran.
const CLOCK_SLACK_MS: i64 = 1_500;
/// A round may be submitted this long after its own time is up.
const ROUND_GRACE_MICROS: i64 = 20_000_000;
/// A round is scored only while its player is within this many times the reach of its node or station.
const RESOLVE_REACH_MULT: f32 = 1.5;

/// Which node an entity is. Public: every client draws a node by its NodeDef.
#[table(accessor = gather_node, public)]
pub struct GatherNode {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub def_id: u32,
    /// The level point it stands on.
    pub point_id: String,
}

/// Which station an entity is (its StationDef's key).
#[table(accessor = station, public)]
pub struct Station {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub key: String,
    pub point_id: String,
}

/// A player working AFK, at a node or a station. Public, so everyone can see them at it (and with what).
#[table(accessor = afk_work, public)]
pub struct AfkWork {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// The node or station.
    pub target_id: u64,
    /// The NodeDef (gathering) or RecipeDef (crafting).
    pub def_id: u32,
    pub craft: bool,
    pub skill_id: u32,
    /// The tool it is done with (0: none), for everyone to draw in the hand.
    pub tool_item: u32,
    /// Its interval, in percent of the base (the tool and the rank).
    pub speed_pct: u32,
    pub started_at: Timestamp,
    /// When the next item (or batch) comes.
    pub next_at: Timestamp,
    /// Where they stood when they started: moving away stops it.
    pub from: Vector3,
    pub count: u32,
}

/// What some work just gave, for everyone in the world to see a moment ("+3 Copper ore", a rare find, a
/// rank, the node worked out, the bag run out).
#[table(accessor = work_result, public)]
pub struct WorkResult {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub entity_id: u64,
    pub world_id: u32,
    pub target_id: u64,
    pub skill_id: u32,
    pub item_id: u32,
    pub qty: u32,
    /// The rare find that came with it (0: none).
    pub rare_item: u32,
    /// The node was worked out by it.
    pub depleted: bool,
    /// The bag ran out of what the recipe takes (`item_id` is what is missing).
    pub ran_out: bool,
    /// A round (true) or AFK.
    pub active: bool,
    /// A round's score in thousandths (-1 for AFK).
    pub score_pm: i32,
    /// The quality of what it made, in thousandths (-1: no quality).
    pub quality: i32,
    pub xp: u32,
    /// The rank it reached, when it reached a new one (0 otherwise).
    pub rank: u32,
    pub at: Timestamp,
}

/// A character's XP in one skill.
#[table(accessor = skill_xp, public)]
pub struct SkillXp {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub entity_id: u64,
    pub skill_id: u32,
    pub xp: u32,
}

/// A character's record of one recipe (owner, 2026-10-19, craft XP): how many batches they have made (the
/// first pays the FIRST-MAKE bonus) and how fresh it is (VARIETY: repeating it wears it stale, XP falls;
/// time away from it brings it back). Public: the HUD shows both.
#[table(accessor = recipe_log, public)]
pub struct RecipeLog {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub entity_id: u64,
    pub recipe_id: u32,
    pub made: u32,
    /// Freshness in thousandths when it was last made (`at`); it recovers from there.
    pub fresh_pm: u32,
    pub at: Timestamp,
}

/// A WORK ORDER on a world's order board (owner, 2026-10-19): the camp wants `qty` of `item_id` and pays
/// `xp` in `skill_id` on top of what making them paid. Each player fills each order once; the board's
/// orders change every `regents.order_rotate_min`, so the best thing to make keeps moving.
#[table(accessor = work_order, public)]
pub struct WorkOrder {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub world_id: u32,
    /// Its place on the board (0, 1, 2).
    pub slot: u32,
    pub item_id: u32,
    pub qty: u32,
    pub skill_id: u32,
    pub xp: u32,
    pub expires_at: Timestamp,
}

/// Who has filled which work order.
#[table(accessor = order_filled, public)]
pub struct OrderFilled {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub order_id: u64,
    pub entity_id: u64,
}

/// Who has had their starter kit (once per character: a kit lost later is not handed out again).
#[table(accessor = starter_kit_given)]
pub struct StarterKitGiven {
    #[primary_key]
    pub entity_id: u64,
    pub at: Timestamp,
}

#[table(accessor = work_schedule, scheduled(work_tick))]
pub struct WorkSchedule {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

pub struct Regents;
pub static REGENTS: Regents = Regents;

fn micros(t: Timestamp) -> i64 {
    t.to_micros_since_unix_epoch()
}

fn flat_dist(a: Vector3, b: Vector3) -> f32 {
    ((a.x - b.x) * (a.x - b.x) + (a.z - b.z) * (a.z - b.z)).sqrt()
}

fn pos_of(ctx: &ReducerContext, entity_id: u64) -> Option<Vector3> {
    ctx.db.movement_state().entity_id().find(entity_id).map(|m| m.pos)
}

fn is_depleted(ctx: &ReducerContext, node_id: u64) -> bool {
    ctx.db.status_state().entity_id().find(node_id).is_some_and(|s| s.status == STATUS_DEPLETED)
}

fn reach(ctx: &ReducerContext) -> f32 {
    hot_number(ctx, hot::WORK_REACH_M) as f32
}

// --- the bag ------------------------------------------------------------------------------------------

/// How many of `item` `entity_id` has.
pub fn count_item(ctx: &ReducerContext, entity_id: u64, item: u32) -> u32 {
    ctx.db.inventory_item().owner_entity_id().filter(entity_id).filter(|s| s.item_def_id == item).map(|s| s.qty).sum()
}

/// The best tool of `tag` in the bag: highest tier, then the quickest (its quality and its handle's trait).
/// (item, quality, its speed with its handle in percent)
pub fn best_tool(ctx: &ReducerContext, entity_id: u64, tag: &str) -> Option<(&'static rules::ItemSeed, u32, u32)> {
    ctx.db.inventory_item().owner_entity_id().filter(entity_id)
        .filter(|s| s.qty > 0)
        .filter_map(|s| rules::item(s.item_def_id).filter(|i| i.tool_tag == tag).map(|i| {
            (i, rules::quality_of(&s.instance_data).unwrap_or(0), rules::tool_speed_with(i, rules::handle_of(&s.instance_data)))
        }))
        .max_by_key(|(i, q, sp)| (i.tool_tier, std::cmp::Reverse(rules::speed_pct(*sp, *q, 1)), *q))
}

/// Takes `qty` of `item` from the bag (the best quality first), noting the qualities taken (one per item
/// that had one). False, taking nothing, when there are not enough.
fn take_items(ctx: &ReducerContext, entity_id: u64, item: u32, qty: u32, taken: &mut Vec<u32>) -> bool {
    if count_item(ctx, entity_id, item) < qty {
        return false;
    }
    let mut rows: Vec<InventoryItem> = ctx.db.inventory_item().owner_entity_id().filter(entity_id).filter(|s| s.item_def_id == item).collect();
    rows.sort_by_key(|r| std::cmp::Reverse(rules::quality_of(&r.instance_data).unwrap_or(0)));
    let mut left = qty;
    for mut r in rows {
        if left == 0 {
            break;
        }
        let n = r.qty.min(left);
        if let Some(q) = rules::quality_of(&r.instance_data) {
            taken.extend(std::iter::repeat_n(q, n as usize));
        }
        left -= n;
        if r.qty == n {
            ctx.db.inventory_item().id().delete(r.id);
        } else {
            r.qty -= n;
            ctx.db.inventory_item().id().update(r);
        }
    }
    true
}

/// Puts `qty` of `item` in the bag: with a quality, one row each (an item with a quality does not stack),
/// noting the handle it was assembled with when it has one.
fn give_items(ctx: &ReducerContext, entity_id: u64, item: u32, qty: u32, quality: Option<u32>) {
    give_made(ctx, entity_id, item, qty, quality, None);
}

fn give_made(ctx: &ReducerContext, entity_id: u64, item: u32, qty: u32, quality: Option<u32>, handle: Option<u32>) {
    if qty == 0 {
        return;
    }
    match quality {
        Some(q) => {
            for _ in 0..qty {
                ctx.db.inventory_item().insert(InventoryItem {
                    id: 0,
                    owner_entity_id: entity_id,
                    item_def_id: item,
                    qty: 1,
                    slot: -1,
                    instance_data: handle.map_or_else(|| rules::quality_data(q), |h| rules::tool_data(q, h)),
                });
            }
        }
        None => {
            if let Err(e) = crate::module::grant_item_internal(ctx, entity_id, item, qty) {
                log::warn!("regents: {qty} of item {item} for {entity_id}: {e}");
            }
        }
    }
}

/// The part `r`'s part slot is filled with: `part` when it is of the slot's kind, the slot's own item for
/// 0 (or a recipe without one: 0). Err when `part` is not of the slot's kind.
fn part_for(r: &RecipeSeed, part: u32) -> Result<u32, String> {
    if r.part_slot < 0 {
        return if part == 0 { Ok(0) } else { Err(format!("a {} takes no part", r.name)) };
    }
    let own = r.inputs[r.part_slot as usize].0;
    if part == 0 || part == own {
        return Ok(own);
    }
    let kind = rules::item(own).map_or("", |i| i.part_tag);
    match rules::item(part) {
        Some(p) if !kind.is_empty() && p.part_tag == kind => Ok(part),
        _ => Err(format!("a {} takes a {kind} there, not item {part}", r.name)),
    }
}

/// `r`'s inputs for one batch with its part slot filled by `part` (see `part_for`).
fn inputs_with(r: &RecipeSeed, part: u32) -> Vec<(u32, u32)> {
    r.inputs.iter().enumerate().map(|(i, (item, qty))| if i as i32 == r.part_slot && part != 0 { (part, *qty) } else { (*item, *qty) }).collect()
}

/// The first input of `r` (its part slot filled by `part`) the bag lacks for one batch, or None.
fn missing_input(ctx: &ReducerContext, entity_id: u64, r: &RecipeSeed, part: u32) -> Option<(u32, u32)> {
    inputs_with(r, part).into_iter().find(|(item, qty)| count_item(ctx, entity_id, *item) < *qty)
}

/// One batch of `r` made with `part` in its part slot: its inputs taken, its output given (as good as
/// `round_quality`, or its inputs; a handle adds its quality and goes on the tool). None, making nothing,
/// when the bag lacks an input. Else the quality made (-1 for none).
fn make_batch(ctx: &ReducerContext, entity_id: u64, r: &RecipeSeed, round_quality: u32, part: u32) -> Option<i32> {
    if missing_input(ctx, entity_id, r, part).is_some() {
        return None;
    }
    let mut taken: Vec<u32> = Vec::new();
    for (item, qty) in inputs_with(r, part) {
        take_items(ctx, entity_id, item, qty, &mut taken);
    }
    let handle = if r.part_slot >= 0 && part != 0 { Some(part) } else { None };
    let bonus = handle.and_then(rules::item).map_or(0, |h| h.handle_quality_pm);
    let quality = match r.quality {
        rules::QUALITY_FROM_ROUND => Some((round_quality + bonus).min(1000)),
        rules::QUALITY_FROM_INPUTS => Some((taken.iter().copied().max().unwrap_or(0) + bonus).min(1000)),
        _ => None,
    };
    give_made(ctx, entity_id, r.output, r.output_qty, quality, if quality.is_some() { handle } else { None });
    Some(quality.map_or(-1, |q| q as i32))
}

/// The XP `entity_id` earns for `batches` of `r` (owner, 2026-10-19, against one-method grinds): the work
/// in its inputs (`regents.craft_work_share_pct`), less as the recipe wears stale from repeating it
/// (VARIETY: freshness drains `variety_drain_pm_per_min` a minute of its work, recovers
/// `variety_recover_pm_per_min` a minute, XP down to `variety_floor_pct`), and a FIRST-MAKE bonus
/// (`first_make_mult` x one batch) the first time. Its `recipe_log` row brought up to date.
fn craft_paid_xp(ctx: &ReducerContext, entity_id: u64, r: &RecipeSeed, batches: u32) -> u32 {
    if batches == 0 {
        return 0;
    }
    let base = rules::craft_xp(r, hot_number(ctx, hot::CRAFT_WORK_SHARE_PCT) as u32);
    let drain = (hot_number(ctx, hot::VARIETY_DRAIN_PM_PER_MIN) * r.afk_ms as f64 / 60_000.0).round() as u32;
    let recover = hot_number(ctx, hot::VARIETY_RECOVER_PM_PER_MIN) as u32;
    let floor = hot_number(ctx, hot::VARIETY_FLOOR_PCT) as u32;
    let row = ctx.db.recipe_log().entity_id().filter(entity_id).find(|l| l.recipe_id == r.id);
    let mut fresh = row.as_ref().map_or(1000, |l| {
        rules::freshness_now(l.fresh_pm, ((micros(ctx.timestamp) - micros(l.at)).max(0) / 1_000_000) as u32, recover)
    });
    let mut xp = 0u32;
    for _ in 0..batches {
        xp += rules::xp_at_freshness(base, fresh, floor);
        fresh = fresh.saturating_sub(drain);
    }
    match row {
        Some(mut l) => {
            l.made += batches;
            l.fresh_pm = fresh;
            l.at = ctx.timestamp;
            ctx.db.recipe_log().id().update(l);
        }
        None => {
            xp += base * hot_number(ctx, hot::FIRST_MAKE_MULT) as u32;
            ctx.db.recipe_log().insert(RecipeLog { id: 0, entity_id, recipe_id: r.id, made: batches, fresh_pm: fresh, at: ctx.timestamp });
        }
    }
    xp
}

// --- mastery ------------------------------------------------------------------------------------------

/// `entity_id`'s XP in skill `skill_id`.
pub fn xp_of(ctx: &ReducerContext, entity_id: u64, skill_id: u32) -> u32 {
    ctx.db.skill_xp().entity_id().filter(entity_id).find(|r| r.skill_id == skill_id).map_or(0, |r| r.xp)
}

pub fn rank_in(ctx: &ReducerContext, entity_id: u64, skill_id: u32) -> u32 {
    rules::skill(skill_id).map_or(1, |s| rules::rank_of(s, xp_of(ctx, entity_id, skill_id)))
}

/// Adds `xp` in skill `skill_id`; the new rank when it went up (0 otherwise).
fn add_xp(ctx: &ReducerContext, entity_id: u64, skill_id: u32, xp: u32) -> u32 {
    if xp == 0 {
        return 0;
    }
    let Some(s) = rules::skill(skill_id) else { return 0 };
    let row = ctx.db.skill_xp().entity_id().filter(entity_id).find(|r| r.skill_id == skill_id);
    let before = row.as_ref().map_or(0, |r| r.xp);
    let after = before.saturating_add(xp);
    match row {
        Some(mut r) => {
            r.xp = after;
            ctx.db.skill_xp().id().update(r);
        }
        None => {
            ctx.db.skill_xp().insert(SkillXp { id: 0, entity_id, skill_id, xp: after });
        }
    }
    let (r0, r1) = (rules::rank_of(s, before), rules::rank_of(s, after));
    if r1 > r0 {
        log::info!("regents: {entity_id} reaches {} rank {r1}", s.name);
        r1
    } else {
        0
    }
}

fn need_rank(ctx: &ReducerContext, entity_id: u64, skill_id: u32, min_rank: u32, verb: &str) -> Result<(), String> {
    let have = rank_in(ctx, entity_id, skill_id);
    if have < min_rank {
        let name = rules::skill(skill_id).map_or("that skill", |s| s.name);
        return Err(format!("{verb}: needs {name} rank {min_rank} (yours: {have})"));
    }
    Ok(())
}

// --- the world ----------------------------------------------------------------------------------------

/// Every item this build has, as `item_def` rows (added, or brought up to date).
fn sync_items(ctx: &ReducerContext) {
    for it in rules::ITEMS {
        let row = ItemDef {
            item_def_id: it.id,
            kind: if it.tool_tag.is_empty() { 2 } else { 1 },
            max_stack: it.max_stack,
            data: format!("{{\"name\":{:?},\"tool\":{:?},\"tier\":{}}}", it.name, it.tool_tag, it.tool_tier),
        };
        match ctx.db.item_def().item_def_id().find(it.id) {
            None => {
                ctx.db.item_def().insert(row);
            }
            Some(old) if old.max_stack != row.max_stack || old.kind != row.kind || old.data != row.data => {
                ctx.db.item_def().item_def_id().update(row);
            }
            Some(_) => {}
        }
    }
}

fn ensure_schedule(ctx: &ReducerContext) {
    if ctx.db.work_schedule().count() == 0 {
        ctx.db.work_schedule().insert(WorkSchedule { scheduled_id: 0, scheduled_at: TimeDuration::from_micros(WORK_TICK_MICROS).into() });
    }
}

/// The default world in the frontier glade, unless it has ever been given a level (an admin who put it
/// on the greybox, `set_world_level 0 0`, keeps it there); its nodes and stations placed.
fn ensure_frontier(ctx: &ReducerContext) {
    if crate::level::by_id(LEVEL_FRONTIER).is_some() && ctx.db.world_level().world_id().find(DEFAULT_WORLD).is_none() {
        if let Err(e) = crate::module::set_world_level_internal(ctx, DEFAULT_WORLD, LEVEL_FRONTIER) {
            log::error!("regents: the frontier could not be set up: {e}");
        }
    }
    populate(ctx, DEFAULT_WORLD);
}

fn yaw_of(point_id: &str) -> f32 {
    let h = point_id.bytes().fold(7u64, |h, b| h.wrapping_mul(31).wrapping_add(b as u64));
    rules::roll_permille(h) as f32 * std::f32::consts::TAU / 1000.0
}

/// A node on every `node` point and a station on every `station` point of world `world_id`'s level
/// that has none yet.
fn populate(ctx: &ReducerContext, world_id: u32) {
    let Some(level) = crate::level::by_id(crate::module::world_level_of(ctx, world_id)) else { return };
    let nodes: Vec<String> = ctx.db.gather_node().world_id().filter(world_id).map(|n| n.point_id).collect();
    for p in level.points_of(rules::NODE_POINT) {
        if nodes.iter().any(|id| id == p.id) {
            continue;
        }
        let Some(def) = p.tags.first().and_then(|t| rules::node_named(t)) else {
            log::error!("regents: node point {} names no node ({:?}); nodes: {:?}", p.id, p.tags, rules::NODES.iter().map(|n| n.name).collect::<Vec<_>>());
            continue;
        };
        let id = crate::module::spawn_npc_internal(ctx, world_id, ENTITY_NODE, Vector3::new(p.x as f32, p.y as f32, p.z as f32), yaw_of(p.id));
        ctx.db.gather_node().insert(GatherNode { entity_id: id, world_id, def_id: def.id, point_id: p.id.to_string() });
    }
    let stations: Vec<String> = ctx.db.station().world_id().filter(world_id).map(|s| s.point_id).collect();
    for p in level.points_of(rules::STATION_POINT) {
        if stations.iter().any(|id| id == p.id) {
            continue;
        }
        let Some(st) = p.tags.first().and_then(|t| rules::station_keyed(t)) else {
            log::error!("regents: station point {} names no station ({:?})", p.id, p.tags);
            continue;
        };
        let id = crate::module::spawn_npc_internal(ctx, world_id, ENTITY_STATION, Vector3::new(p.x as f32, p.y as f32, p.z as f32), yaw_of(p.id));
        ctx.db.station().insert(Station { entity_id: id, world_id, key: st.key.to_string(), point_id: p.id.to_string() });
    }
    populate_dummies(ctx, world_id);
    populate_foes(ctx, world_id);
}

/// Every node and station of world `world_id` taken away (its level changed).
fn clear_world(ctx: &ReducerContext, world_id: u32) {
    let ids: Vec<u64> = ctx.db.gather_node().world_id().filter(world_id).map(|n| n.entity_id)
        .chain(ctx.db.station().world_id().filter(world_id).map(|s| s.entity_id))
        .chain(ctx.db.dummy().world_id().filter(world_id).map(|d| d.entity_id))
        .chain(ctx.db.foe().world_id().filter(world_id).map(|f| f.entity_id)).collect();
    let orders: Vec<u64> = ctx.db.work_order().world_id().filter(world_id).map(|o| o.id).collect();
    for id in orders {
        for f in ctx.db.order_filled().order_id().filter(id).map(|f| f.id).collect::<Vec<_>>() {
            ctx.db.order_filled().id().delete(f);
        }
        ctx.db.work_order().id().delete(id);
    }
    for id in ids {
        ctx.db.dummy().entity_id().delete(id);
        ctx.db.gather_node().entity_id().delete(id);
        ctx.db.station().entity_id().delete(id);
        ctx.db.foe().entity_id().delete(id);
        if ctx.db.entity().entity_id().find(id).is_some() {
            forget_body(ctx, id);
        }
    }
}

/// A character's starter kit, once: the first time they arrive in a world with this genre.
fn starter_kit(ctx: &ReducerContext, entity_id: u64) {
    if ctx.db.starter_kit_given().entity_id().find(entity_id).is_some() {
        return;
    }
    for item in rules::STARTER_KIT {
        if rules::item(*item).is_some() && count_item(ctx, entity_id, *item) == 0 {
            give_items(ctx, entity_id, *item, 1, None);
        }
    }
    ctx.db.starter_kit_given().insert(StarterKitGiven { entity_id, at: ctx.timestamp });
}

/// Whatever `entity_id` is working at, stopped: AFK, and any round not yet submitted (withdrawn, unpaid).
fn stop_work(ctx: &ReducerContext, entity_id: u64) {
    ctx.db.afk_work().entity_id().delete(entity_id);
    let open: Vec<u64> = ctx.db.challenge().entity_id().filter(entity_id)
        .filter(|c| rules::CLAIMS.challenge_kinds.contains(&c.kind)).map(|c| c.id).collect();
    for id in open {
        crate::module::withdraw_challenge(ctx, id);
    }
}

/// Node `node_id` is worked out: Depleted for its regrow time; everyone working it AFK stops.
fn deplete(ctx: &ReducerContext, node_id: u64, n: &NodeSeed, by: u64) {
    if let Err(e) = crate::module::set_status_internal(ctx, node_id, STATUS_DEPLETED, n.regrow_ms, by, String::new()) {
        log::error!("regents: node {node_id} could not be worked out: {e}");
    }
    let afk: Vec<u64> = ctx.db.afk_work().iter().filter(|a| a.target_id == node_id).map(|a| a.entity_id).collect();
    for id in afk {
        ctx.db.afk_work().entity_id().delete(id);
    }
}

#[allow(clippy::too_many_arguments)]
fn report(ctx: &ReducerContext, entity_id: u64, world_id: u32, target_id: u64, skill_id: u32, item_id: u32, qty: u32, rare_item: u32,
    depleted: bool, ran_out: bool, active: bool, score_pm: i32, quality: i32, xp: u32, rank: u32) {
    ctx.db.work_result().insert(WorkResult {
        id: 0, entity_id, world_id, target_id, skill_id, item_id, qty, rare_item, depleted, ran_out, active, score_pm, quality, xp, rank,
        at: ctx.timestamp,
    });
}

/// `entity_id` gathers `n` items at node `node_id` (a round when `active`): each may bring its rare find
/// and may work it out (then no more come). Pays, reports. The items gathered.
#[allow(clippy::too_many_arguments)]
fn gather_items(ctx: &ReducerContext, entity_id: u64, world_id: u32, node_id: u64, def: &NodeSeed, n: u32, active: bool, score_pm: i32, salt: u64) -> u32 {
    let rare_mult = if active { hot_number(ctx, hot::ACTIVE_RARE_MULT) } else { 1.0 };
    let already = is_depleted(ctx, node_id);
    let (mut got, mut rare, mut out) = (0u32, 0u32, false);
    for i in 0..n as u64 {
        got += 1;
        let (r, d) = rules::item_outcome(def, rare_mult, rules::roll_permille(salt ^ (i * 2 + 3)), rules::roll_permille(salt ^ (i * 2 + 4)));
        rare += u32::from(r);
        if d && !already {
            out = true;
            break;
        }
    }
    give_items(ctx, entity_id, def.yield_item, got, None);
    if rare > 0 {
        give_items(ctx, entity_id, def.rare_item, rare, None);
    }
    let rank = add_xp(ctx, entity_id, def.skill, def.xp * got);
    report(ctx, entity_id, world_id, node_id, def.skill, def.yield_item, got, if rare > 0 { def.rare_item } else { 0 }, out, false, active,
        score_pm, -1, def.xp * got, rank);
    if out {
        deplete(ctx, node_id, def, entity_id);
    }
    got
}

// --- the reducers -------------------------------------------------------------------------------------

/// GATHER AT NODE `node_id`: a round of its minigame (`active`: held E), or AFK (tapped E). Checks it is not
/// worked out, the player is within `regents.work_reach_m` of it, has its skill's rank and a tool of its
/// tag and tier in the bag; stops whatever they were working at before.
#[reducer]
pub fn gather(ctx: &ReducerContext, node_id: u64, active: bool) -> Result<(), String> {
    let me = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?.entity_id;
    crate::module::spend_rate(ctx, me, "gather")?;
    crate::module::require_can_act(ctx, me, "gather")?;
    let node = ctx.db.gather_node().entity_id().find(node_id).ok_or("gather: that is nothing to gather")?;
    let def = rules::node(node.def_id).ok_or_else(|| format!("gather: node {node_id} has no NodeDef {}", node.def_id))?;
    if is_depleted(ctx, node_id) {
        return Err(format!("gather: the {} is worked out; it comes back soon", def.name.to_lowercase()));
    }
    let mine = ctx.db.movement_state().entity_id().find(me).ok_or("gather: you have no movement_state")?;
    if mine.world_id != node.world_id {
        return Err("gather: that is in another world".into());
    }
    let at = pos_of(ctx, node_id).ok_or("gather: it has no place")?;
    let d = flat_dist(mine.pos, at);
    if d > reach(ctx) {
        return Err(format!("gather: too far ({d:.1} m, reach {:.1} m)", reach(ctx)));
    }
    need_rank(ctx, me, def.skill, def.min_rank, "gather")?;
    let article = if def.tool_tag.starts_with(['a', 'e', 'i', 'o', 'u']) { "an" } else { "a" };
    let (tool, quality, tool_speed) = best_tool(ctx, me, def.tool_tag).ok_or_else(|| format!("gather: you need {article} {} in your bag", def.tool_tag))?;
    if tool.tool_tier < def.min_tool_tier {
        return Err(format!("gather: a {} needs a {} of tier {} (yours: {})", def.name, def.tool_tag, def.min_tool_tier, tool.tool_tier));
    }
    let speed = rules::speed_pct(tool_speed, quality, rank_in(ctx, me, def.skill));
    stop_work(ctx, me);
    if active {
        let ttl = def.minigame.duration_ms() * 1000 + ROUND_GRACE_MICROS;
        crate::module::issue_genre_challenge(ctx, me, def.minigame.challenge_kind(), rules::payload(node_id, def.id, speed), ttl)?;
        log::info!("regents: {me} plays a round at {} {node_id} (speed {speed} %)", def.name);
    } else {
        ctx.db.afk_work().insert(AfkWork {
            entity_id: me, world_id: node.world_id, target_id: node_id, def_id: def.id, craft: false, skill_id: def.skill,
            tool_item: tool.id, speed_pct: speed, started_at: ctx.timestamp,
            next_at: ctx.timestamp + TimeDuration::from_micros(rules::afk_interval_ms(def.afk_ms, speed) as i64 * 1000),
            from: mine.pos, count: 0,
        });
        log::info!("regents: {me} works {} {node_id} AFK (speed {speed} %)", def.name);
    }
    Ok(())
}

/// CRAFT RECIPE `recipe_id` AT STATION `station_id`: a round of its minigame (`active`, when it has one), or
/// AFK. Checks the station makes it, the player is within reach, has its skill's rank and a batch's inputs.
/// A recipe with a part slot uses the slot's own item (`craft_with` picks another).
#[reducer]
pub fn craft(ctx: &ReducerContext, station_id: u64, recipe_id: u32, active: bool) -> Result<(), String> {
    craft_impl(ctx, station_id, recipe_id, active, 0)
}

/// `craft`, with `part` (an item id) in the recipe's part slot: an Iron axe with an oak or a yew handle
/// (owner, 2026-10-19). 0: the slot's own item. A new reducer, so `craft`'s arguments never change (rule 17).
#[reducer]
pub fn craft_with(ctx: &ReducerContext, station_id: u64, recipe_id: u32, active: bool, part: u32) -> Result<(), String> {
    craft_impl(ctx, station_id, recipe_id, active, part)
}

fn craft_impl(ctx: &ReducerContext, station_id: u64, recipe_id: u32, active: bool, part: u32) -> Result<(), String> {
    let me = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?.entity_id;
    crate::module::spend_rate(ctx, me, "craft")?;
    crate::module::require_can_act(ctx, me, "craft")?;
    let (st, mine) = near_station(ctx, me, station_id, "craft")?;
    let r = rules::recipe(recipe_id).ok_or_else(|| format!("craft: there is no recipe {recipe_id}"))?;
    if r.station != st.key {
        return Err(format!("craft: a {} is not made at the {}", r.name, st.key));
    }
    let part = part_for(r, part).map_err(|e| format!("craft: {e}"))?;
    need_rank(ctx, me, r.skill, r.min_rank, "craft")?;
    if let Some((item, need)) = missing_input(ctx, me, r, part) {
        return Err(format!("craft: a {} needs {need} {} (you have {})", r.name, rules::item(item).map_or("?", |i| i.name), count_item(ctx, me, item)));
    }
    stop_work(ctx, me);
    if active && !matches!(r.minigame, Minigame::None) {
        let ttl = r.minigame.duration_ms() * 1000 + ROUND_GRACE_MICROS;
        crate::module::issue_genre_challenge(ctx, me, r.minigame.challenge_kind(), rules::payload_with_part(station_id, r.id, 100, part), ttl)?;
        log::info!("regents: {me} plays a round of {} at the {}", r.name, st.key);
    } else {
        // A craft's `tool_item` is the part it is made with (0: none).
        ctx.db.afk_work().insert(AfkWork {
            entity_id: me, world_id: st.world_id, target_id: station_id, def_id: r.id, craft: true, skill_id: r.skill, tool_item: part,
            speed_pct: 100, started_at: ctx.timestamp, next_at: ctx.timestamp + TimeDuration::from_micros(r.afk_ms as i64 * 1000),
            from: mine.pos, count: 0,
        });
        log::info!("regents: {me} makes {} AFK at the {}", r.name, st.key);
    }
    Ok(())
}

/// Station `station_id`, when `me` stands within reach of it in its world: (its row, my movement row).
fn near_station(ctx: &ReducerContext, me: u64, station_id: u64, verb: &str) -> Result<(Station, crate::module::MovementStateRow), String> {
    let st = ctx.db.station().entity_id().find(station_id).ok_or_else(|| format!("{verb}: that is no station"))?;
    let mine = ctx.db.movement_state().entity_id().find(me).ok_or_else(|| format!("{verb}: you have no movement_state"))?;
    let at = pos_of(ctx, station_id).ok_or_else(|| format!("{verb}: it has no place"))?;
    let d = flat_dist(mine.pos, at);
    if mine.world_id != st.world_id || d > reach(ctx) {
        return Err(format!("{verb}: too far ({d:.1} m, reach {:.1} m)", reach(ctx)));
    }
    Ok((st, mine))
}

/// FILL WORK ORDER `order_id` at order board `board_id`: hand over what it wants (the best quality first)
/// and be paid its XP. Once per player per order; the order must be on this board's world and not expired.
#[reducer]
pub fn fill_order(ctx: &ReducerContext, board_id: u64, order_id: u64) -> Result<(), String> {
    let me = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?.entity_id;
    crate::module::spend_rate(ctx, me, "craft")?;
    crate::module::require_can_act(ctx, me, "fill_order")?;
    let (st, _) = near_station(ctx, me, board_id, "fill_order")?;
    if st.key != rules::ORDER_BOARD {
        return Err("fill_order: that is no order board".into());
    }
    let o = ctx.db.work_order().id().find(order_id).ok_or("fill_order: that order is gone")?;
    if o.world_id != st.world_id || ctx.timestamp >= o.expires_at {
        return Err("fill_order: that order is gone".into());
    }
    if ctx.db.order_filled().order_id().filter(order_id).any(|f| f.entity_id == me) {
        return Err("fill_order: you have filled that order".into());
    }
    let name = rules::item(o.item_id).map_or("?", |i| i.name);
    let have = count_item(ctx, me, o.item_id);
    if have < o.qty {
        return Err(format!("fill_order: it wants {} {name} (you have {have})", o.qty));
    }
    take_items(ctx, me, o.item_id, o.qty, &mut Vec::new());
    ctx.db.order_filled().insert(OrderFilled { id: 0, order_id, entity_id: me });
    let rank = add_xp(ctx, me, o.skill_id, o.xp);
    report(ctx, me, st.world_id, board_id, o.skill_id, o.item_id, o.qty, 0, false, false, false, -1, -1, o.xp, rank);
    log::info!("regents: {me} filled order {order_id} ({} {name}) for {} xp", o.qty, o.xp);
    Ok(())
}

/// World `world_id`'s order board brought up to date: an order in every slot, a new one where the old has
/// expired, each wanting about `regents.order_minutes` of AFK work of a recipe's output and paying
/// `regents.order_bonus_pct` of that work's XP on top. Seeded from the time, so every world differs.
fn refresh_orders(ctx: &ReducerContext, world_id: u32) {
    if rules::RECIPES.is_empty() {
        return;
    }
    let minutes = hot_number(ctx, hot::ORDER_MINUTES).max(0.5);
    let rotate = TimeDuration::from_micros((hot_number(ctx, hot::ORDER_ROTATE_MIN).max(1.0) * 60_000_000.0) as i64);
    let bonus = hot_number(ctx, hot::ORDER_BONUS_PCT) as u32;
    let share = hot_number(ctx, hot::CRAFT_WORK_SHARE_PCT) as u32;
    let orders: Vec<WorkOrder> = ctx.db.work_order().world_id().filter(world_id).collect();
    for slot in 0..rules::ORDER_SLOTS {
        let live = orders.iter().find(|o| o.slot == slot && ctx.timestamp < o.expires_at);
        if live.is_some() {
            continue;
        }
        for old in orders.iter().filter(|o| o.slot == slot) {
            for f in ctx.db.order_filled().order_id().filter(old.id).map(|f| f.id).collect::<Vec<_>>() {
                ctx.db.order_filled().id().delete(f);
            }
            ctx.db.work_order().id().delete(old.id);
        }
        // Not the same recipe as another slot's.
        let taken: Vec<u32> = ctx.db.work_order().world_id().filter(world_id).map(|o| o.item_id).collect();
        let salt = (micros(ctx.timestamp) as u64) ^ ((world_id as u64) << 40) ^ ((slot as u64 + 1) << 20);
        let pool: Vec<&RecipeSeed> = rules::RECIPES.iter().filter(|r| !taken.contains(&r.output)).collect();
        if pool.is_empty() {
            continue;
        }
        let r = pool[(rules::roll_permille(salt) as usize * pool.len()) / 1000];
        let batches = ((minutes * 60_000.0 / r.afk_ms as f64).round() as u32).max(1);
        let qty = batches * r.output_qty;
        let xp = rules::craft_xp(r, share) * batches * bonus / 100;
        ctx.db.work_order().insert(WorkOrder {
            id: 0, world_id, slot, item_id: r.output, qty, skill_id: r.skill, xp, expires_at: ctx.timestamp + rotate,
        });
    }
}

/// Stop working AFK.
#[reducer]
pub fn work_stop(ctx: &ReducerContext) -> Result<(), String> {
    let me = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?.entity_id;
    crate::module::spend_rate(ctx, me, "work_stop")?;
    ctx.db.afk_work().entity_id().delete(me);
    Ok(())
}

/// AFK work, four times a second: an item (or batch) when one is due; stopped by moving away, the node
/// working out, the tool leaving the bag, the inputs running out, or the player leaving. Old results go.
#[reducer]
pub fn work_tick(ctx: &ReducerContext, _sched: WorkSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("work_tick: scheduler only".into());
    }
    let stop_m = hot_number(ctx, hot::AFK_STOP_MOVING_M) as f32;
    let now = micros(ctx.timestamp);
    let rows: Vec<AfkWork> = ctx.db.afk_work().iter().collect();
    for mut row in rows {
        let online = ctx.db.player().entity_id().find(row.entity_id).is_some_and(|p| p.online);
        let stayed = pos_of(ctx, row.entity_id).is_some_and(|p| flat_dist(p, row.from) <= stop_m);
        if !online || !stayed || ctx.db.entity().entity_id().find(row.target_id).is_none() {
            ctx.db.afk_work().entity_id().delete(row.entity_id);
            continue;
        }
        if ctx.timestamp < row.next_at {
            continue;
        }
        let salt = (now as u64) ^ row.entity_id.rotate_left(17) ^ row.target_id.rotate_left(41) ^ ((row.count as u64) << 7);
        let interval;
        if row.craft {
            let Some(r) = rules::recipe(row.def_id) else {
                ctx.db.afk_work().entity_id().delete(row.entity_id);
                continue;
            };
            match make_batch(ctx, row.entity_id, r, r.afk_quality, row.tool_item) {
                Some(q) => {
                    let xp = craft_paid_xp(ctx, row.entity_id, r, 1);
                    let rank = add_xp(ctx, row.entity_id, r.skill, xp);
                    report(ctx, row.entity_id, row.world_id, row.target_id, r.skill, r.output, r.output_qty, 0, false, false, false, -1, q, xp, rank);
                }
                None => {
                    let missing = missing_input(ctx, row.entity_id, r, row.tool_item).map_or(0, |(i, _)| i);
                    report(ctx, row.entity_id, row.world_id, row.target_id, r.skill, missing, 0, 0, false, true, false, -1, -1, 0, 0);
                    ctx.db.afk_work().entity_id().delete(row.entity_id);
                    continue;
                }
            }
            interval = r.afk_ms;
        } else {
            let Some(def) = rules::node(row.def_id) else {
                ctx.db.afk_work().entity_id().delete(row.entity_id);
                continue;
            };
            let tool_ok = best_tool(ctx, row.entity_id, def.tool_tag).is_some_and(|(t, _, _)| t.tool_tier >= def.min_tool_tier);
            if is_depleted(ctx, row.target_id) || !tool_ok {
                ctx.db.afk_work().entity_id().delete(row.entity_id);
                continue;
            }
            gather_items(ctx, row.entity_id, row.world_id, row.target_id, def, 1, false, -1, salt);
            if is_depleted(ctx, row.target_id) {
                continue;   // `deplete` stopped everyone at it
            }
            interval = rules::afk_interval_ms(def.afk_ms, row.speed_pct);
        }
        row.count += 1;
        row.next_at = row.next_at + TimeDuration::from_micros(interval as i64 * 1000);
        ctx.db.afk_work().entity_id().update(row);
    }
    reset_dummies(ctx);
    tick_foes(ctx);
    tick_regen(ctx, WORK_TICK_MICROS as f32 / 1_000_000.0);
    let mut boards: Vec<u32> = ctx.db.station().iter().filter(|s| s.key == rules::ORDER_BOARD).map(|s| s.world_id).collect();
    boards.dedup();
    for w in boards {
        refresh_orders(ctx, w);
    }
    let kills: Vec<u64> = ctx.db.foe_kill().iter().filter(|k| now - micros(k.at) > RESULT_TTL_MICROS).map(|k| k.id).collect();
    for id in kills {
        ctx.db.foe_kill().id().delete(id);
    }
    let old: Vec<u64> = ctx.db.work_result().iter().filter(|h| now - micros(h.at) > RESULT_TTL_MICROS).map(|h| h.id).collect();
    for id in old {
        ctx.db.work_result().id().delete(id);
    }
    Ok(())
}

/// A round, submitted: REPLAYED from its inputs and paid. None (nothing paid) when the submission is not a
/// round, claims presses the server's clock says had not happened yet, or comes from too far away.
fn resolve_round(ctx: &ReducerContext, ch: &Challenge, result: &[f32]) -> Option<f32> {
    let (target, def_id, speed) = rules::parse_payload(&ch.payload)?;
    let node = rules::node(def_id).filter(|n| n.minigame.challenge_kind() == ch.kind && ctx.db.gather_node().entity_id().find(target).is_some());
    let recipe = rules::recipe(def_id).filter(|r| r.minigame.challenge_kind() == ch.kind && ctx.db.station().entity_id().find(target).is_some());
    let minigame = node.map(|n| &n.minigame).or(recipe.map(|r| &r.minigame))?;
    let elapsed_ms = (micros(ctx.timestamp) - micros(ch.issued_at)) / 1000;
    let arity = if ch.kind == rules::CHALLENGE_CRACK { 3 } else { 2 };
    if let Some(t) = result.chunks(arity).map(|g| g[0] as i64).find(|t| *t > elapsed_ms + CLOCK_SLACK_MS) {
        log::warn!("regents: round {} from {} claims a press at {t} ms, {elapsed_ms} ms after it was dealt", ch.id, ch.entity_id);
        return None;
    }
    let (Some(me), Some(at)) = (pos_of(ctx, ch.entity_id), pos_of(ctx, target)) else { return None };
    if flat_dist(me, at) > reach(ctx) * RESOLVE_REACH_MULT {
        log::info!("regents: round {} from {}: walked away", ch.id, ch.entity_id);
        return None;
    }
    let Some(score) = minigame.score(ch.seed, speed as i64, result) else {
        log::warn!("regents: round {} from {} is not a round (len {})", ch.id, ch.entity_id, result.len());
        return None;
    };
    let world_id = ctx.db.entity().entity_id().find(ch.entity_id).map_or(DEFAULT_WORLD, |e| e.world_id);
    let salt = ch.seed ^ (micros(ctx.timestamp) as u64);
    let mult = hot_number(ctx, hot::ACTIVE_YIELD_MULT);
    if let Some(n) = node {
        let count = rules::whole_items(rules::active_yield_milli(rules::afk_interval_ms(n.afk_ms, speed), n.minigame.duration_ms(), mult, score),
            rules::roll_permille(salt));
        let got = gather_items(ctx, ch.entity_id, world_id, target, n, count, true, score as i32, salt);
        log::info!("regents: round {} at {} {target}: score {score} -> {got} {}", ch.id, n.name, rules::item(n.yield_item).map_or("?", |i| i.name));
    } else if let Some(r) = recipe {
        let batches = if r.quality == rules::QUALITY_FROM_ROUND {
            1
        } else {
            rules::whole_items(rules::active_yield_milli(r.afk_ms, r.minigame.duration_ms(), mult, score), rules::roll_permille(salt))
        };
        let part = part_for(r, rules::parse_part(&ch.payload)).unwrap_or(0);
        let (mut made, mut quality) = (0u32, -1i32);
        for _ in 0..batches {
            match make_batch(ctx, ch.entity_id, r, score as u32, part) {
                Some(q) => {
                    made += 1;
                    quality = q;
                }
                None => break,
            }
        }
        let xp = craft_paid_xp(ctx, ch.entity_id, r, made);
        let rank = add_xp(ctx, ch.entity_id, r.skill, xp);
        let ran_out = made == 0 && batches > 0;
        report(ctx, ch.entity_id, world_id, target, r.skill, r.output, made * r.output_qty, 0, false, ran_out, true, score as i32, quality,
            xp, rank);
        log::info!("regents: round {} of {}: score {score} -> {made} batch(es){}", ch.id, r.name,
            if quality >= 0 { format!(", quality {quality}") } else { String::new() });
    }
    Some(score as f32 / 1000.0)
}

// --- combat (owner, 2026-10-19: the first slice) -------------------------------------------------------
//
// THE WEAPON IS THE KIT. A player WIELDS one weapon from the bag (`wield`); its `ItemDef.weapon_kit`
// names the KitDef whose light combo, heavy and skills (Q E R F, at mastery 1/3/6/9) they may use: every
// other kit's ability is refused (`may_use_ability`). A swing is a foundation ability the world's REFEREE
// judges (a sweep along the way the body faces: aimed, never auto-hit; the client's target ring is for
// reference). What a hit does is ours (`on_ability_hit`): the ability's damage x the weapon x its
// quality x the mastery rank; a BLOCK takes `regents.block_damage_pct` of it, a block raised within
// `regents.parry_ms` of the hit takes none and STAGGERS the attacker; a dodge roll (`Rolling`) is not hit
// at all. Every hit pays mastery XP in the kit's skill. The training DUMMY (camp's `dummy` points) never
// falls and is whole again `regents.dummy_reset_s` after its last hit.

/// What a player fights with: a row of their bag (its item and kit). Public: everyone draws it.
#[table(accessor = wielded, public)]
pub struct Wielded {
    #[primary_key]
    pub entity_id: u64,
    pub item_row: u64,
    pub item_id: u32,
    pub kit: String,
}

/// A fighter's moment: the light combo's last step and when, and when the block went up.
#[table(accessor = combat_state, public)]
pub struct CombatState {
    #[primary_key]
    pub entity_id: u64,
    /// The light step last swung (-1: no combo going).
    pub combo: i32,
    pub combo_at: Timestamp,
    pub blocking: bool,
    pub block_since: Timestamp,
}

/// A fighter's swing (owner, 2026-10-19: animation-locked): when it began, when it lands (its wind-up),
/// how long it holds them (its clip's length: the kit's lock), its light step (-1: not a light), and
/// whether a roll or a heavy hit cancelled it (it never lands). Public: tests and tools read it.
#[table(accessor = swing, public)]
pub struct Swing {
    #[primary_key]
    pub entity_id: u64,
    pub ability_id: u32,
    pub at: Timestamp,
    pub wind_up_ms: u32,
    pub lock_ms: u32,
    pub light_step: i32,
    pub cancelled: bool,
}

/// A FOE on a level point (owner, 2026-10-19: the first enemies): which foe (`FoeDef`), and when it fell.
/// Its entity is gone `regents.foe_corpse_s` after it fell (`gone`); the row stays until it comes back,
/// `regents.foe_respawn_s` after, as a new entity on the same point.
#[table(accessor = foe, public)]
#[derive(Clone)]
pub struct Foe {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub point_id: String,
    pub foe_id: u32,
    pub fell_at: Option<Timestamp>,
    pub gone: bool,
}

/// When an entity was last hurt (a hit landed on it): its health comes back `regents.regen_delay_s` after.
/// No row: whole, or never hurt.
#[table(accessor = hurt)]
pub struct Hurt {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub at: Timestamp,
}

/// A foe slain by a player, and what they got (`item:qty,...`): the HUD's line. Kept a few seconds.
#[table(accessor = foe_kill, public)]
pub struct FoeKill {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    /// The killer.
    #[index(btree)]
    pub entity_id: u64,
    pub world_id: u32,
    pub foe_id: u32,
    pub loot: String,
    pub at: Timestamp,
}

/// A training dummy, on a level point.
#[table(accessor = dummy, public)]
#[derive(Clone)]
pub struct Dummy {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub point_id: String,
    pub last_hit_at: Timestamp,
}

fn combat_state_of(ctx: &ReducerContext, entity_id: u64) -> CombatState {
    ctx.db.combat_state().entity_id().find(entity_id).unwrap_or(CombatState {
        entity_id, combo: -1, combo_at: ctx.timestamp, blocking: false, block_since: ctx.timestamp,
    })
}

fn save_combat_state(ctx: &ReducerContext, s: CombatState) {
    if ctx.db.combat_state().entity_id().find(s.entity_id).is_some() {
        ctx.db.combat_state().entity_id().update(s);
    } else {
        ctx.db.combat_state().insert(s);
    }
}

/// The weapon `entity_id` wields, while it is still in their bag: (its item, its quality).
fn wielded_weapon(ctx: &ReducerContext, entity_id: u64) -> Option<(&'static rules::ItemSeed, u32)> {
    let w = ctx.db.wielded().entity_id().find(entity_id)?;
    let row = ctx.db.inventory_item().id().find(w.item_row).filter(|r| r.owner_entity_id == entity_id && r.qty > 0)?;
    rules::item(row.item_def_id).filter(|i| !i.weapon_kit.is_empty()).map(|i| (i, rules::quality_of(&row.instance_data).unwrap_or(0)))
}

/// WIELD the weapon in bag row `item_row` (an axe, a sword): its kit is what you fight with.
#[reducer]
pub fn wield(ctx: &ReducerContext, item_row: u64) -> Result<(), String> {
    let me = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?.entity_id;
    crate::module::spend_rate(ctx, me, "wield")?;
    let row = ctx.db.inventory_item().id().find(item_row).filter(|r| r.owner_entity_id == me).ok_or("wield: that is not in your bag")?;
    let it = rules::item(row.item_def_id).ok_or("wield: that is no item")?;
    if it.weapon_kit.is_empty() {
        return Err(format!("wield: a {} is no weapon", it.name.to_lowercase()));
    }
    let w = Wielded { entity_id: me, item_row, item_id: it.id, kit: it.weapon_kit.to_string() };
    if ctx.db.wielded().entity_id().find(me).is_some() {
        ctx.db.wielded().entity_id().update(w);
    } else {
        ctx.db.wielded().insert(w);
    }
    log::info!("regents: {me} wields a {}", it.name);
    Ok(())
}

/// Put the weapon away.
#[reducer]
pub fn unwield(ctx: &ReducerContext) -> Result<(), String> {
    let me = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?.entity_id;
    crate::module::spend_rate(ctx, me, "wield")?;
    ctx.db.wielded().entity_id().delete(me);
    stop_block(ctx, me);
    Ok(())
}

/// BLOCK: raise it (`on`, holding the right button) or lower it. Raised, hits take
/// `regents.block_damage_pct`; one within `regents.parry_ms` of raising it is parried.
#[reducer]
pub fn block(ctx: &ReducerContext, on: bool) -> Result<(), String> {
    let me = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?.entity_id;
    crate::module::spend_rate(ctx, me, "block")?;
    if !on {
        stop_block(ctx, me);
        return Ok(());
    }
    crate::module::require_can_act(ctx, me, "block")?;
    if wielded_weapon(ctx, me).is_none() {
        return Err("block: wield a weapon to block".into());
    }
    let mut s = combat_state_of(ctx, me);
    if !s.blocking {
        s.blocking = true;
        s.block_since = ctx.timestamp;
        s.combo = -1;
        save_combat_state(ctx, s);
        crate::module::set_status_internal(ctx, me, rules::STATUS_BLOCKING, 0, me, String::new())?;
    }
    Ok(())
}

fn stop_block(ctx: &ReducerContext, entity_id: u64) {
    let mut s = combat_state_of(ctx, entity_id);
    if s.blocking {
        s.blocking = false;
        save_combat_state(ctx, s);
        if ctx.db.status_state().entity_id().find(entity_id).is_some_and(|st| st.status == rules::STATUS_BLOCKING) {
            let _ = crate::module::set_status_internal(ctx, entity_id, crate::status::NORMAL, 0, entity_id, String::new());
        }
    }
}

/// Whether `actor` may use `ability_id` now: everyone may roll; a kit's ability needs its kit wielded,
/// and a skill its mastery rank; a light step must follow the one before it; nobody swings while blocking.
fn may_fight(ctx: &ReducerContext, actor: u64, ability_id: u32) -> Result<(), String> {
    if ability_id == rules::ABILITY_DODGE {
        return Ok(());
    }
    let Some((kit, slot)) = rules::kit_of_ability(ability_id) else { return Ok(()) };   // not ours
    if ctx.db.player().entity_id().find(actor).is_none() {
        return Ok(());   // a creature's own ability: its brain's to choose
    }
    let what = rules::skill(kit.skill).map_or("that", |s| s.name);
    let Some((weapon, _)) = wielded_weapon(ctx, actor) else {
        let article = if kit.key.starts_with(['a', 'e', 'i', 'o', 'u']) { "an" } else { "a" };
        return Err(format!("wield {article} {} first", kit.key));
    };
    if weapon.weapon_kit != kit.key {
        return Err(format!("that is a {} move; you wield a {}", kit.key, weapon.name.to_lowercase()));
    }
    let s = combat_state_of(ctx, actor);
    if s.blocking {
        return Err("lower your block to swing".into());
    }
    // No swing mid-roll (owner, 2026-10-19: "prevent melee usage like jumping"): the client holds a press
    // until its roll is over; a slack's worth before the end is allowed (its clock ran first).
    let slack = hot_number(ctx, hot::SWING_SLACK_MS).max(0.0) as i64;
    if let Some(st) = ctx.db.status_state().entity_id().find(actor).filter(|st| st.status == rules::STATUS_ROLLING) {
        let left = st.lasts_ms as i64 - (micros(ctx.timestamp) - micros(st.since)) / 1000;
        if left > slack {
            return Err("still rolling".into());
        }
    }
    // No swing in the air (owner, 2026-10-19: a jump attack played a moment and was cut off): the client
    // holds a press made there until it lands.
    if ctx.db.movement_state().entity_id().find(actor).is_some_and(|m| !m.grounded) {
        return Err("not in the air".into());
    }
    let sw = ctx.db.swing().entity_id().find(actor);
    let (lock, last_step) = sw.as_ref().map_or((0i64, -1), |w| (w.lock_ms as i64, if w.cancelled { -1 } else { w.light_step }));
    if let rules::KitSlot::Light(step) = slot {
        let since = (micros(ctx.timestamp) - micros(s.combo_at)) / 1000;
        // The combo's next step: right after the step before, until the window after its lock.
        let prev = if sw.is_some() { last_step } else { s.combo };
        if !rules::combo_allows(step, prev, since, (lock + kit.combo_window_ms as i64 + slack) as u32) {
            return Err("out of the combo's order".into());
        }
    }
    if let Some(w) = &sw {
        let t = (micros(ctx.timestamp) - micros(w.at)) / 1000;
        let chain = matches!(slot, rules::KitSlot::Light(step) if step > 0 && w.light_step == step as i32 - 1);
        if !rules::swing_allows(chain, t, w.wind_up_ms as i64, kit.chain_ms as i64, w.lock_ms as i64, slack, w.cancelled) {
            return Err("still swinging".into());
        }
    }
    if let rules::KitSlot::Skill(_, rank) = slot {
        need_rank(ctx, actor, kit.skill, rank, what)?;
    }
    Ok(())
}

/// A use, recorded: the combo moves on (or starts over), a roll lowers the block and cannot be hit.
fn fought(ctx: &ReducerContext, actor: u64, ability_id: u32) {
    if ability_id == rules::ABILITY_DODGE {
        stop_block(ctx, actor);
        // A ROLL CANCELS A SWING (owner, 2026-10-19): in its wind-up it never lands; in its recovery the
        // recovery ends. Either way the fighter is free, and the combo is over.
        if let Some(mut w) = ctx.db.swing().entity_id().find(actor) {
            let t = ((micros(ctx.timestamp) - micros(w.at)) / 1000).max(0);
            if t < w.lock_ms as i64 && !w.cancelled {
                w.cancelled = t < w.wind_up_ms as i64;
                w.lock_ms = t as u32;
                ctx.db.swing().entity_id().update(w);
            }
        }
        let mut cs = combat_state_of(ctx, actor);
        cs.combo = -1;
        save_combat_state(ctx, cs);
        let ms = (hot_number(ctx, hot::ROLL_MS).max(0.0)) as u32;
        if let Err(e) = crate::module::set_status_internal(ctx, actor, rules::STATUS_ROLLING, ms, actor, String::new()) {
            log::warn!("regents: {actor} rolled, but: {e}");
        }
        return;
    }
    let Some((kit, slot)) = rules::kit_of_ability(ability_id) else { return };
    let mut s = combat_state_of(ctx, actor);
    s.combo = if let rules::KitSlot::Light(step) = slot { step as i32 } else { -1 };
    s.combo_at = ctx.timestamp;
    save_combat_state(ctx, s);
    let wind_up = ctx.db.ability_def().ability_id().find(ability_id).map_or(0, |d| d.wind_up_ms);
    let w = Swing {
        entity_id: actor, ability_id, at: ctx.timestamp, wind_up_ms: wind_up, lock_ms: kit.lock_ms(ability_id).max(wind_up),
        light_step: if let rules::KitSlot::Light(step) = slot { step as i32 } else { -1 }, cancelled: false,
    };
    if ctx.db.swing().entity_id().find(actor).is_some() {
        ctx.db.swing().entity_id().update(w);
    } else {
        ctx.db.swing().insert(w);
    }
    // A COMMITTED SWING: slowed from its start until just after it lands; the server lets go a slack's worth
    // before the client does (`regents.swing_slack_ms`), so a frame from a client already running again
    // never meets the bound (a snap back).
    let hold = (wind_up + hot_number(ctx, hot::SWING_HOLD_MS).max(0.0) as u32)
        .saturating_sub(hot_number(ctx, hot::SWING_SLACK_MS).max(0.0) as u32);
    if let Err(e) = crate::module::set_status_internal(ctx, actor, rules::STATUS_SWINGING, hold, actor, String::new()) {
        log::warn!("regents: {actor} swings, but: {e}");
    }
}

/// What a hit by `actor` with `ability_id` on `target` does (true: done here). Ours when it is a kit's.
fn hit(ctx: &ReducerContext, actor: u64, target: &crate::module::Entity, ability_id: u32) -> bool {
    let Some((kit, slot)) = rules::kit_of_ability(ability_id) else { return false };
    let Some(def) = ctx.db.ability_def().ability_id().find(ability_id) else { return false };
    // A swing a roll (or a flinch) cancelled in its wind-up never lands.
    if ctx.db.swing().entity_id().find(actor).is_some_and(|w| w.ability_id == ability_id && w.cancelled) {
        log::info!("regents: {actor}'s {} was cancelled before it landed", def.ability_id);
        return true;
    }
    // HEAVIES FLINCH LIGHTS: a heavy hit in a light swing's wind-up cancels it (a heavy's wind-up has armor).
    if slot == rules::KitSlot::Heavy {
        if let Some(mut w) = ctx.db.swing().entity_id().find(target.entity_id) {
            let t = (micros(ctx.timestamp) - micros(w.at)) / 1000;
            if w.light_step >= 0 && !w.cancelled && t < w.wind_up_ms as i64 {
                w.cancelled = true;
                w.lock_ms = t.max(0) as u32;
                ctx.db.swing().entity_id().update(w);
                let ms = hot_number(ctx, hot::FLINCH_MS).max(0.0) as u32;
                let _ = crate::module::set_status_internal(ctx, target.entity_id, rules::STATUS_FLINCHED, ms, actor, String::new());
                log::info!("regents: {actor}'s heavy flinched {}", target.entity_id);
            }
        }
    }
    let (pct, quality) = match foe_seed_of(ctx, actor) {
        Some(f) => (f.damage_pct, 0),
        None => wielded_weapon(ctx, actor).filter(|(w, _)| w.weapon_kit == kit.key).map_or((100, 0), |(w, q)| (w.weapon_damage_pct, q)),
    };
    let mut dmg = rules::hit_damage(def.damage, pct, quality, rank_in(ctx, actor, kit.skill));
    let t = combat_state_of(ctx, target.entity_id);
    if t.blocking {
        let since_ms = (micros(ctx.timestamp) - micros(t.block_since)) / 1000;
        if since_ms <= hot_number(ctx, hot::PARRY_MS) as i64 {
            dmg = 0.0;
            let ms = hot_number(ctx, hot::STAGGER_MS).max(0.0) as u32;
            let _ = crate::module::set_status_internal(ctx, actor, rules::STATUS_STAGGERED, ms, target.entity_id, String::new());
            log::info!("regents: {} parried {actor}'s {}", target.entity_id, def.ability_id);
        } else {
            dmg *= hot_number(ctx, hot::BLOCK_DAMAGE_PCT) as f32 / 100.0;
        }
    }
    let dummy = ctx.db.dummy().entity_id().find(target.entity_id);
    if dmg > 0.0 {
        if let Some(mut d) = dummy.clone() {
            // A dummy never falls: it keeps a sliver, and is whole again soon.
            let left = ctx.db.health_state().entity_id().find(target.entity_id).map_or(0.0, |h| h.current);
            dmg = dmg.min((left - 1.0).max(0.0));
            d.last_hit_at = ctx.timestamp;
            ctx.db.dummy().entity_id().update(d);
        }
        if let Err(e) = crate::module::damage_entity(ctx, target.entity_id, dmg, actor) {
            log::warn!("regents: {actor}'s hit on {}: {e}", target.entity_id);
        }
        if dummy.is_none() {
            hurt_now(ctx, target.entity_id, target.world_id);
        }
    }
    if ctx.db.player().entity_id().find(actor).is_some() && dmg > 0.0 {
        let share = if dummy.is_some() {
            hot_number(ctx, hot::DUMMY_XP_PCT) / 100.0
        } else {
            foe_seed_of(ctx, target.entity_id).map_or(1.0, |f| f.xp_pct as f64 / 100.0)
        };
        let xp = (dmg as f64 * hot_number(ctx, hot::COMBAT_XP_PER_DAMAGE) * share).round().max(1.0) as u32;
        add_xp(ctx, actor, kit.skill, xp);
    }
    if dmg > 0.0 && ctx.db.health_state().entity_id().find(target.entity_id).is_some_and(|h| h.is_dead) {
        fell(ctx, target.entity_id, actor);
    }
    true
}

// --- foes (owner, 2026-10-19: the first enemies, a skeleton camp) ------------------------------------

/// The foe entity `entity_id` is (its kind's `FoeSeed`), if it is one.
fn foe_seed_of(ctx: &ReducerContext, entity_id: u64) -> Option<&'static rules::FoeSeed> {
    let kind = ctx.db.entity().entity_id().find(entity_id)?.kind;
    if !rules::FOE_KINDS.contains(&kind) {
        return None;
    }
    rules::foe_of_kind(kind)
}

/// A foe on every point of world `world_id`'s level named by a foe's key that has none yet (standing, fallen
/// or gone: a point waits for its own to come back).
fn populate_foes(ctx: &ReducerContext, world_id: u32) {
    let Some(level) = crate::level::by_id(crate::module::world_level_of(ctx, world_id)) else { return };
    let have: Vec<String> = ctx.db.foe().world_id().filter(world_id).map(|f| f.point_id).collect();
    for seed in rules::FOES {
        for p in level.points_of(seed.key) {
            if have.iter().any(|id| id == p.id) {
                continue;
            }
            spawn_foe(ctx, world_id, seed, p);
        }
    }
}

/// Foe `seed` standing on point `p`, whole: an entity its brain drives (`sidecar/npc/brains/regents/foe.gd`).
fn spawn_foe(ctx: &ReducerContext, world_id: u32, seed: &rules::FoeSeed, p: &crate::level::Point) -> u64 {
    let id = crate::module::spawn_npc_internal(ctx, world_id, seed.kind, Vector3::new(p.x as f32, p.y as f32, p.z as f32), yaw_of(p.id));
    if let Some(mut h) = ctx.db.health_state().entity_id().find(id) {
        h.current = seed.hp as f32;
        h.max = seed.hp as f32;
        h.is_dead = false;
        ctx.db.health_state().entity_id().update(h);
    }
    ctx.db.npc_brain().insert(crate::module::NpcBrainRow {
        entity_id: id, world_id, brain: FOE_BRAIN.into(), state: String::new(), target_id: 0, data: "{}".into(), updated_at: ctx.timestamp,
    });
    ctx.db.foe().insert(Foe { entity_id: id, world_id, point_id: p.id.to_string(), foe_id: seed.id, fell_at: None, gone: false });
    id
}

/// The brain every foe has: its FoeDef says how it behaves.
const FOE_BRAIN: &str = "regents/foe";

/// HEALTH RAN OUT. A foe falls (Slain, until it is gone) and its killer, a player, gets its loot; a player
/// is Slain `regents.player_respawn_s`, then gets up at the spawn (`on_status_expired`).
fn fell(ctx: &ReducerContext, entity_id: u64, killer: u64) {
    stop_block(ctx, entity_id);
    if let Some(mut f) = ctx.db.foe().entity_id().find(entity_id) {
        if f.fell_at.is_some() {
            return;
        }
        f.fell_at = Some(ctx.timestamp);
        ctx.db.foe().entity_id().update(f.clone());
        if let Err(e) = crate::module::set_status_internal(ctx, entity_id, rules::STATUS_SLAIN, crate::module::LASTS_UNTIL_CHANGED, killer, String::new()) {
            log::warn!("regents: foe {entity_id} fell, but: {e}");
        }
        let Some(seed) = rules::FOES.iter().find(|s| s.id == f.foe_id) else { return };
        if ctx.db.player().entity_id().find(killer).is_none() {
            return;
        }
        let salt = (micros(ctx.timestamp) as u64) ^ entity_id.rotate_left(23) ^ killer.rotate_left(47);
        let got = rules::foe_loot(seed, |i| rules::roll_permille(salt ^ ((i as u64 + 1) << 13)));
        for (item, qty) in &got {
            give_items(ctx, killer, *item, *qty, None);
        }
        let loot: Vec<String> = got.iter().map(|(i, q)| format!("{i}:{q}")).collect();
        ctx.db.foe_kill().insert(FoeKill { id: 0, entity_id: killer, world_id: f.world_id, foe_id: seed.id, loot: loot.join(","), at: ctx.timestamp });
        log::info!("regents: {killer} slew {} ({entity_id}): {:?}", seed.name, got);
        return;
    }
    if ctx.db.player().entity_id().find(entity_id).is_some() {
        let ms = (hot_number(ctx, hot::PLAYER_RESPAWN_S).max(0.0) * 1000.0) as u32;
        if let Err(e) = crate::module::set_status_internal(ctx, entity_id, rules::STATUS_SLAIN, ms.max(1), killer, String::new()) {
            log::warn!("regents: player {entity_id} fell, but: {e}");
        }
        log::info!("regents: player {entity_id} was slain by {killer}");
    }
}

/// A slain player's time is up: whole again, at the spawn.
fn get_up(ctx: &ReducerContext, entity_id: u64) {
    ctx.db.hurt().entity_id().delete(entity_id);
    if let Some(mut h) = ctx.db.health_state().entity_id().find(entity_id) {
        h.current = h.max;
        h.is_dead = false;
        ctx.db.health_state().entity_id().update(h);
    }
    let world = ctx.db.entity().entity_id().find(entity_id).map_or(DEFAULT_WORLD, |e| e.world_id);
    let spawn = ctx.db.world_config().world_id().find(world).map_or(Vector3::new(0.0, 0.0, 0.0), |w| w.spawn);
    if let Err(e) = crate::module::place_entity(ctx, entity_id, spawn, None) {
        log::warn!("regents: player {entity_id} got up, but: {e}");
    }
}

/// Fallen foes: gone after `regents.foe_corpse_s`, back on their point after `regents.foe_respawn_s`.
fn tick_foes(ctx: &ReducerContext) {
    let now = micros(ctx.timestamp);
    let corpse = (hot_number(ctx, hot::FOE_CORPSE_S) * 1_000_000.0) as i64;
    let respawn = (hot_number(ctx, hot::FOE_RESPAWN_S) * 1_000_000.0) as i64;
    let fallen: Vec<Foe> = ctx.db.foe().iter().filter(|f| f.fell_at.is_some()).collect();
    for mut f in fallen {
        let since = now - micros(f.fell_at.unwrap_or(ctx.timestamp));
        if !f.gone && since >= corpse.min(respawn) {
            forget_body(ctx, f.entity_id);
            f.gone = true;
            ctx.db.foe().entity_id().update(f.clone());
        }
        if since < respawn {
            continue;
        }
        ctx.db.foe().entity_id().delete(f.entity_id);
        let level = crate::level::by_id(crate::module::world_level_of(ctx, f.world_id));
        let point = level.and_then(|l| l.points.iter().find(|p| p.id == f.point_id));
        match (rules::FOES.iter().find(|s| s.id == f.foe_id), point) {
            (Some(seed), Some(p)) => {
                spawn_foe(ctx, f.world_id, seed, p);
            }
            _ => log::warn!("regents: foe {} at {} cannot come back: its foe or its point is gone", f.foe_id, f.point_id),
        }
    }
}

/// Entity `entity_id` was hurt now: its health waits `regents.regen_delay_s` before it comes back.
fn hurt_now(ctx: &ReducerContext, entity_id: u64, world_id: u32) {
    let row = Hurt { entity_id, world_id, at: ctx.timestamp };
    if ctx.db.hurt().entity_id().find(entity_id).is_some() {
        ctx.db.hurt().entity_id().update(row);
    } else {
        ctx.db.hurt().insert(row);
    }
}

/// OUT OF THE FIGHT, HEALTH COMES BACK (2026-10-20): `regents.regen_delay_s` after its last hurt, a player
/// or a foe gets `regents.regen_pct_per_s` % of its health back a second (a foe led off and left walks
/// home whole), until it is whole. Not while it is slain.
fn tick_regen(ctx: &ReducerContext, dt_s: f32) {
    let now = micros(ctx.timestamp);
    let delay = (hot_number(ctx, hot::REGEN_DELAY_S).max(0.0) * 1_000_000.0) as i64;
    let pct = hot_number(ctx, hot::REGEN_PCT_PER_S) as f32;
    let rows: Vec<Hurt> = ctx.db.hurt().iter().filter(|h| now - micros(h.at) >= delay).collect();
    for r in rows {
        let Some(mut h) = ctx.db.health_state().entity_id().find(r.entity_id) else {
            ctx.db.hurt().entity_id().delete(r.entity_id);
            continue;
        };
        if h.is_dead {
            continue;
        }
        h.current = rules::regen_step(h.current, h.max, pct, dt_s);
        let whole = h.current >= h.max;
        ctx.db.health_state().entity_id().update(h);
        if whole {
            ctx.db.hurt().entity_id().delete(r.entity_id);
        }
    }
}

/// A fallen foe's body goes: its entity and what this genre kept about it.
fn forget_body(ctx: &ReducerContext, entity_id: u64) {
    ctx.db.hurt().entity_id().delete(entity_id);
    crate::module::despawn_entity_internal(ctx, entity_id);
    ctx.db.combat_state().entity_id().delete(entity_id);
    ctx.db.swing().entity_id().delete(entity_id);
}

/// World `world_id`'s dummies whole again `regents.dummy_reset_s` after their last hit.
fn reset_dummies(ctx: &ReducerContext) {
    let after = (hot_number(ctx, hot::DUMMY_RESET_S) * 1_000_000.0) as i64;
    for d in ctx.db.dummy().iter() {
        if micros(ctx.timestamp) - micros(d.last_hit_at) < after {
            continue;
        }
        if let Some(mut h) = ctx.db.health_state().entity_id().find(d.entity_id) {
            if h.current < h.max {
                h.current = h.max;
                h.is_dead = false;
                ctx.db.health_state().entity_id().update(h);
            }
        }
    }
}

/// A dummy on every `dummy` point of world `world_id`'s level that has none yet: an entity a stand-still
/// brain "drives" (so the referee counts it as someone to hit), with `regents.dummy_hp` health.
fn populate_dummies(ctx: &ReducerContext, world_id: u32) {
    let Some(level) = crate::level::by_id(crate::module::world_level_of(ctx, world_id)) else { return };
    let have: Vec<String> = ctx.db.dummy().world_id().filter(world_id).map(|d| d.point_id).collect();
    let hp = hot_number(ctx, hot::DUMMY_HP) as f32;
    for p in level.points_of(rules::DUMMY_POINT) {
        if have.iter().any(|id| id == p.id) {
            continue;
        }
        let id = crate::module::spawn_npc_internal(ctx, world_id, rules::ENTITY_DUMMY, Vector3::new(p.x as f32, p.y as f32, p.z as f32), yaw_of(p.id));
        if let Some(mut h) = ctx.db.health_state().entity_id().find(id) {
            h.current = hp;
            h.max = hp;
            ctx.db.health_state().entity_id().update(h);
        }
        ctx.db.npc_brain().insert(crate::module::NpcBrainRow {
            entity_id: id, world_id, brain: "stand".into(), state: String::new(), target_id: 0, data: "{}".into(), updated_at: ctx.timestamp,
        });
        ctx.db.dummy().insert(Dummy { entity_id: id, world_id, point_id: p.id.to_string(), last_hit_at: ctx.timestamp });
    }
}

impl crate::game::Genre for Regents {
    fn claims(&self) -> &'static crate::genre::Claims {
        &rules::CLAIMS
    }

    fn may_use_ability(&self, ctx: &ReducerContext, actor_id: u64, ability_id: u32) -> Result<(), String> {
        may_fight(ctx, actor_id, ability_id)
    }

    fn on_ability_used(&self, ctx: &ReducerContext, actor_id: u64, ability_id: u32, _aim: Vector3) {
        fought(ctx, actor_id, ability_id);
    }

    fn on_ability_hit(&self, ctx: &ReducerContext, actor_id: u64, target: &crate::module::Entity, ability_id: u32) -> bool {
        hit(ctx, actor_id, target, ability_id)
    }

    /// A slain player's time is up: up again, whole, at the spawn. (A foe's Slain lasts until it is gone.)
    fn on_status_expired(&self, ctx: &ReducerContext, row: &StatusStateRow) -> Option<u8> {
        if row.status == rules::STATUS_SLAIN && ctx.db.player().entity_id().find(row.entity_id).is_some() {
            get_up(ctx, row.entity_id);
            return Some(crate::status::NORMAL);
        }
        None
    }

    fn on_init(&self, ctx: &ReducerContext) {
        sync_items(ctx);
        ensure_schedule(ctx);
        ensure_frontier(ctx);
    }

    /// A world from before the genre (published again, not fresh: `init` does not run) is brought up to
    /// date when a player arrives.
    fn on_player_created(&self, ctx: &ReducerContext, entity_id: u64) {
        sync_items(ctx);
        ensure_schedule(ctx);
        ensure_frontier(ctx);
        starter_kit(ctx, entity_id);
    }

    fn on_player_returned(&self, ctx: &ReducerContext, entity_id: u64) {
        sync_items(ctx);
        ensure_schedule(ctx);
        ensure_frontier(ctx);
        starter_kit(ctx, entity_id);
    }

    fn on_player_left(&self, ctx: &ReducerContext, entity_id: u64) {
        ctx.db.afk_work().entity_id().delete(entity_id);
        stop_block(ctx, entity_id);
    }

    fn on_level_changed(&self, ctx: &ReducerContext, world_id: u32, _level_id: u8) {
        clear_world(ctx, world_id);
        populate(ctx, world_id);
    }

    fn resolve_challenge(&self, ctx: &ReducerContext, challenge: &Challenge, result: &[f32]) -> Option<f32> {
        if rules::CLAIMS.challenge_kinds.contains(&challenge.kind) {
            return resolve_round(ctx, challenge, result);
        }
        None
    }
}
