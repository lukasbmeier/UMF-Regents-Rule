//! REGENT'S RULE (docs/regents_rule/RULE_DESIGN.md), the server's half: the skilling loop's first skill,
//! WOODCUTTING, worked two ways at the player's choice (owner, 2026-10-18, design §7.4):
//!
//!   the trees  a level's `tree` points (tagged with a TreeDef's name) become entities of kind
//!              `ENTITY_TREE` with a `tree_node` row saying which tree; everyone shares them. A tree
//!              that falls is in the Felled status for its `regrow_ms`, then stands again.
//!   AFK        tap E: `chop(tree, false)`, an `afk_chop` row; `chop_tick` gives a log every
//!              `afk_ms_per_log` until the player moves `regents.afk_stop_moving_m`, the tree falls, or
//!              `chop_stop`.
//!   active     hold E: `chop(tree, true)` deals a round of branch dodge, a challenge of the genre's own
//!              kind with the server's seed (its payload: "<tree entity> <tree def>"). The client plays
//!              it and submits its inputs; `resolve_challenge` REPLAYS them (`genre::regents::chop`, held
//!              to the client's `ChopModel` by the golden file) and pays what AFK makes in the round's
//!              time x `regents.active_yield_mult` x the score (design #23).
//!   each log   may bring the tree's rare find (more likely played: `regents.active_rare_mult`) and may
//!              fell it (`fell_permille`).
//!
//! A tool is the best of its kind in the bag (design #15): a new character is given a Bronze axe, once. What came
//! out is a `harvest` row everyone in the world sees for a few seconds ("+3 Logs").

use spacetimedb::{reducer, table, ReducerContext, ScheduleAt, Table, TimeDuration, Timestamp};

use crate::genre::regents::{self as rules, TreeSeed, CHALLENGE_CHOP, ENTITY_TREE, LEVEL_FRONTIER, STATUS_FELLED, TOOL_AXE};
use crate::hot::regents as hot;
use crate::module::{
    challenge, entity, hot_number, inventory_item, item_def, movement_state, player, status_state, world_level,
    Challenge, ItemDef, DEFAULT_WORLD,
};
use crate::sim::Vector3;

/// How often AFK chopping is looked at.
const CHOP_TICK_MICROS: i64 = 250_000;
/// How long a harvest row is kept for everyone to see.
const HARVEST_TTL_MICROS: i64 = 10_000_000;
/// A round's inputs may claim to be this far ahead of the server's clock (one way's lag, and the
/// client's own frame); further, they were not played as the round ran.
const CLOCK_SLACK_MS: i64 = 1_500;
/// A round may be submitted this long after its own time is up.
const ROUND_GRACE_MICROS: i64 = 20_000_000;
/// A round is scored only while its player is within this many times the reach of its tree.
const RESOLVE_REACH_MULT: f32 = 1.5;

/// Which tree an entity is. Public: every client draws a tree by its TreeDef.
#[table(accessor = tree_node, public)]
pub struct TreeNode {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub def_id: u32,
    /// The level point it stands on.
    pub point_id: String,
}

/// A player chopping AFK. Public, so everyone can see them at it.
#[table(accessor = afk_chop, public)]
pub struct AfkChop {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub tree_id: u64,
    pub def_id: u32,
    pub started_at: Timestamp,
    /// When the next log comes.
    pub next_at: Timestamp,
    /// Where they stood when they started: moving away stops it.
    pub from: Vector3,
    pub logs: u32,
}

/// What a chop just gave, for everyone in the world to see a moment ("+3 Logs", a rare find, timber!).
#[table(accessor = harvest, public)]
pub struct Harvest {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub entity_id: u64,
    pub world_id: u32,
    pub tree_id: u64,
    pub item_id: u32,
    pub qty: u32,
    /// The rare find that came with it (0: none).
    pub rare_item: u32,
    pub felled: bool,
    /// A round (true) or AFK.
    pub active: bool,
    /// A round's score in thousandths (-1 for AFK).
    pub score_pm: i32,
    pub at: Timestamp,
}

/// Who has had their starter kit (once per character: a kit lost later is not handed out again).
#[table(accessor = starter_kit_given)]
pub struct StarterKitGiven {
    #[primary_key]
    pub entity_id: u64,
    pub at: Timestamp,
}

#[table(accessor = chop_schedule, scheduled(chop_tick))]
pub struct ChopSchedule {
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

fn is_felled(ctx: &ReducerContext, tree_id: u64) -> bool {
    ctx.db.status_state().entity_id().find(tree_id).is_some_and(|s| s.status == STATUS_FELLED)
}

/// The best tier of tool `tag` in `entity_id`'s bag (0: none).
pub fn best_tool(ctx: &ReducerContext, entity_id: u64, tag: &str) -> u32 {
    ctx.db.inventory_item().owner_entity_id().filter(entity_id)
        .filter(|s| s.qty > 0)
        .filter_map(|s| rules::item(s.item_def_id))
        .filter(|i| i.tool_tag == tag)
        .map(|i| i.tool_tier)
        .max()
        .unwrap_or(0)
}

fn pos_of(ctx: &ReducerContext, entity_id: u64) -> Option<Vector3> {
    ctx.db.movement_state().entity_id().find(entity_id).map(|m| m.pos)
}

/// The tree entity `tree_id` and what it is.
fn tree_of(ctx: &ReducerContext, tree_id: u64) -> Result<(TreeNode, &'static TreeSeed), String> {
    let node = ctx.db.tree_node().entity_id().find(tree_id).ok_or("chop: that is not a tree")?;
    let def = rules::tree(node.def_id).ok_or_else(|| format!("chop: tree {} has no TreeDef {}", tree_id, node.def_id))?;
    Ok((node, def))
}

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
    if ctx.db.chop_schedule().count() == 0 {
        ctx.db.chop_schedule().insert(ChopSchedule {
            scheduled_id: 0,
            scheduled_at: TimeDuration::from_micros(CHOP_TICK_MICROS).into(),
        });
    }
}

/// The default world in the frontier glade, unless it has ever been given a level (an admin who put it
/// on the greybox, `set_world_level 0 0`, keeps it there); its trees planted.
fn ensure_frontier(ctx: &ReducerContext) {
    if crate::level::by_id(LEVEL_FRONTIER).is_some() && ctx.db.world_level().world_id().find(DEFAULT_WORLD).is_none() {
        if let Err(e) = crate::module::set_world_level_internal(ctx, DEFAULT_WORLD, LEVEL_FRONTIER) {
            log::error!("regents: the frontier could not be set up: {e}");
        }
    }
    plant_trees(ctx, DEFAULT_WORLD);
}

/// A tree on every `tree` point of world `world_id`'s level that has none yet.
fn plant_trees(ctx: &ReducerContext, world_id: u32) {
    let Some(level) = crate::level::by_id(crate::module::world_level_of(ctx, world_id)) else { return };
    let planted: Vec<String> = ctx.db.tree_node().world_id().filter(world_id).map(|n| n.point_id).collect();
    for p in level.points_of(rules::TREE_POINT) {
        if planted.iter().any(|id| id == p.id) {
            continue;
        }
        let Some(def) = p.tags.first().and_then(|t| rules::tree_named(t)) else {
            log::error!("regents: tree point {} names no tree ({:?}); trees: {:?}", p.id, p.tags,
                rules::TREES.iter().map(|t| t.name).collect::<Vec<_>>());
            continue;
        };
        let yaw = (rules::roll_permille(p.id.bytes().fold(7u64, |h, b| h.wrapping_mul(31).wrapping_add(b as u64))) as f32)
            * std::f32::consts::TAU / 1000.0;
        let id = crate::module::spawn_npc_internal(ctx, world_id, ENTITY_TREE, Vector3::new(p.x as f32, p.y as f32, p.z as f32), yaw);
        ctx.db.tree_node().insert(TreeNode { entity_id: id, world_id, def_id: def.id, point_id: p.id.to_string() });
    }
}

/// Every tree of world `world_id` taken away (its level changed).
fn clear_trees(ctx: &ReducerContext, world_id: u32) {
    let ids: Vec<u64> = ctx.db.tree_node().world_id().filter(world_id).map(|n| n.entity_id).collect();
    for id in ids {
        ctx.db.tree_node().entity_id().delete(id);
        if ctx.db.entity().entity_id().find(id).is_some() {
            crate::module::despawn_entity_internal(ctx, id);
        }
    }
}

/// A character's starter kit (a Bronze axe), once: the first time they arrive in a world with this genre.
fn starter_kit(ctx: &ReducerContext, entity_id: u64) {
    if ctx.db.starter_kit_given().entity_id().find(entity_id).is_some() || rules::item(rules::STARTER_AXE).is_none() {
        return;
    }
    if best_tool(ctx, entity_id, TOOL_AXE) == 0 {
        if let Err(e) = crate::module::grant_item_internal(ctx, entity_id, rules::STARTER_AXE, 1) {
            log::error!("regents: no starter axe for {entity_id}: {e}");
            return;
        }
    }
    ctx.db.starter_kit_given().insert(StarterKitGiven { entity_id, at: ctx.timestamp });
}

/// Whatever `entity_id` is chopping, stopped: AFK, and any round not yet submitted (withdrawn, unpaid).
fn stop_chopping(ctx: &ReducerContext, entity_id: u64) {
    ctx.db.afk_chop().entity_id().delete(entity_id);
    let open: Vec<u64> = ctx.db.challenge().entity_id().filter(entity_id).filter(|c| c.kind == CHALLENGE_CHOP).map(|c| c.id).collect();
    for id in open {
        crate::module::withdraw_challenge(ctx, id);
    }
}

/// Tree `tree_id` falls: a stump for its regrow time; everyone chopping it AFK stops.
fn fell(ctx: &ReducerContext, tree_id: u64, def: &TreeSeed, by: u64) {
    if let Err(e) = crate::module::set_status_internal(ctx, tree_id, STATUS_FELLED, def.regrow_ms, by, String::new()) {
        log::error!("regents: tree {tree_id} could not fall: {e}");
    }
    let afk: Vec<u64> = ctx.db.afk_chop().iter().filter(|a| a.tree_id == tree_id).map(|a| a.entity_id).collect();
    for id in afk {
        ctx.db.afk_chop().entity_id().delete(id);
    }
}

/// `n` logs (and `rare` rare finds) of tree `def` into `entity_id`'s bag, and a harvest row saying so.
#[allow(clippy::too_many_arguments)]
fn pay(ctx: &ReducerContext, entity_id: u64, world_id: u32, tree_id: u64, def: &TreeSeed, n: u32, rare: u32, felled: bool,
    active: bool, score_pm: i32) {
    if n > 0 {
        if let Err(e) = crate::module::grant_item_internal(ctx, entity_id, def.log_item, n) {
            log::warn!("regents: {n} logs for {entity_id}: {e}");
        }
    }
    if rare > 0 {
        if let Err(e) = crate::module::grant_item_internal(ctx, entity_id, def.rare_item, rare) {
            log::warn!("regents: a rare find for {entity_id}: {e}");
        }
    }
    ctx.db.harvest().insert(Harvest {
        id: 0,
        entity_id,
        world_id,
        tree_id,
        item_id: def.log_item,
        qty: n,
        rare_item: if rare > 0 { def.rare_item } else { 0 },
        felled,
        active,
        score_pm,
        at: ctx.timestamp,
    });
}

/// CHOP TREE `tree_id`: a round of its minigame (`active`: held E), or AFK (tapped E). Checks the tree
/// stands, the player is within `regents.chop_reach_m` of it and has an axe of its tier in the bag;
/// stops whatever they were chopping before.
#[reducer]
pub fn chop(ctx: &ReducerContext, tree_id: u64, active: bool) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    let me = player.entity_id;
    crate::module::spend_rate(ctx, me, "chop")?;
    crate::module::require_can_act(ctx, me, "chop")?;
    let (node, def) = tree_of(ctx, tree_id)?;
    if is_felled(ctx, tree_id) {
        return Err("chop: it is a stump; it grows back soon".into());
    }
    let mine = ctx.db.movement_state().entity_id().find(me).ok_or("chop: you have no movement_state")?;
    if mine.world_id != node.world_id {
        return Err("chop: that tree is in another world".into());
    }
    let at = pos_of(ctx, tree_id).ok_or("chop: the tree has no place")?;
    let reach = hot_number(ctx, hot::CHOP_REACH_M) as f32;
    let d = flat_dist(mine.pos, at);
    if d > reach {
        return Err(format!("chop: too far from the tree ({d:.1} m, reach {reach:.1} m)"));
    }
    let axe = best_tool(ctx, me, TOOL_AXE);
    if axe < def.min_axe_tier {
        return Err(if axe == 0 {
            "chop: you need an axe in your bag".into()
        } else {
            format!("chop: a {} needs an axe of tier {} (yours: {axe})", def.name, def.min_axe_tier)
        });
    }
    stop_chopping(ctx, me);
    if active {
        let ttl = def.chop.duration_ms * 1000 + ROUND_GRACE_MICROS;
        crate::module::issue_genre_challenge(ctx, me, CHALLENGE_CHOP, format!("{tree_id} {}", def.id), ttl)?;
        log::info!("regents: {me} plays a round on {} {tree_id}", def.name);
    } else {
        ctx.db.afk_chop().insert(AfkChop {
            entity_id: me,
            world_id: node.world_id,
            tree_id,
            def_id: def.id,
            started_at: ctx.timestamp,
            next_at: ctx.timestamp + TimeDuration::from_micros(def.afk_ms_per_log as i64 * 1000),
            from: mine.pos,
            logs: 0,
        });
        log::info!("regents: {me} chops {} {tree_id} AFK", def.name);
    }
    Ok(())
}

/// Stop chopping AFK.
#[reducer]
pub fn chop_stop(ctx: &ReducerContext) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    crate::module::spend_rate(ctx, player.entity_id, "chop_stop")?;
    ctx.db.afk_chop().entity_id().delete(player.entity_id);
    Ok(())
}

/// AFK chopping, four times a second: a log when one is due; stopped by moving away, the tree falling,
/// the axe leaving the bag, or the player leaving. Old harvest rows go.
#[reducer]
pub fn chop_tick(ctx: &ReducerContext, _sched: ChopSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("chop_tick: scheduler only".into());
    }
    let stop_m = hot_number(ctx, hot::AFK_STOP_MOVING_M) as f32;
    let now = micros(ctx.timestamp);
    let rows: Vec<AfkChop> = ctx.db.afk_chop().iter().collect();
    for mut row in rows {
        let online = ctx.db.player().entity_id().find(row.entity_id).is_some_and(|p| p.online);
        let def = rules::tree(row.def_id);
        let here = pos_of(ctx, row.entity_id);
        let keep = online && def.is_some() && !is_felled(ctx, row.tree_id)
            && here.is_some_and(|p| flat_dist(p, row.from) <= stop_m)
            && def.is_some_and(|d| best_tool(ctx, row.entity_id, TOOL_AXE) >= d.min_axe_tier);
        let Some(def) = def.filter(|_| keep) else {
            ctx.db.afk_chop().entity_id().delete(row.entity_id);
            continue;
        };
        if ctx.timestamp < row.next_at {
            continue;
        }
        let salt = (now as u64) ^ row.entity_id.rotate_left(17) ^ row.tree_id.rotate_left(41) ^ ((row.logs as u64) << 7);
        let (rare, falls) = rules::log_outcome(def, 1.0, rules::roll_permille(salt ^ 1), rules::roll_permille(salt ^ 2));
        pay(ctx, row.entity_id, row.world_id, row.tree_id, def, 1, u32::from(rare), falls, false, -1);
        if falls {
            fell(ctx, row.tree_id, def, row.entity_id);
            continue;
        }
        row.logs += 1;
        row.next_at = row.next_at + TimeDuration::from_micros(def.afk_ms_per_log as i64 * 1000);
        ctx.db.afk_chop().entity_id().update(row);
    }
    let old: Vec<u64> = ctx.db.harvest().iter().filter(|h| now - micros(h.at) > HARVEST_TTL_MICROS).map(|h| h.id).collect();
    for id in old {
        ctx.db.harvest().id().delete(id);
    }
    Ok(())
}

/// A round of branch dodge, submitted: REPLAYED from its inputs and paid. None (nothing paid) when the
/// submission is not a round, claims presses the server's clock says had not happened yet, or comes
/// from too far from the tree.
fn resolve_chop(ctx: &ReducerContext, ch: &Challenge, result: &[f32]) -> Option<f32> {
    let mut parts = ch.payload.split(' ');
    let tree_id: u64 = parts.next()?.parse().ok()?;
    let def = rules::tree(parts.next()?.parse().ok()?)?;
    let max_pairs = (rules::chop::max_chops(&def.chop) as usize) * 4 + 64;
    let Some(inputs) = rules::chop::decode_inputs(result, max_pairs) else {
        log::warn!("regents: round {} from {} is not a round (len {})", ch.id, ch.entity_id, result.len());
        return None;
    };
    let elapsed_ms = (micros(ctx.timestamp) - micros(ch.issued_at)) / 1000;
    if let Some(&(t, _)) = inputs.iter().find(|(t, _)| *t > elapsed_ms + CLOCK_SLACK_MS) {
        log::warn!("regents: round {} from {} claims a press at {t} ms, {elapsed_ms} ms after it was dealt", ch.id, ch.entity_id);
        return None;
    }
    let reach = hot_number(ctx, hot::CHOP_REACH_M) as f32 * RESOLVE_REACH_MULT;
    let (Some(me), Some(at)) = (pos_of(ctx, ch.entity_id), pos_of(ctx, tree_id)) else { return None };
    if flat_dist(me, at) > reach {
        log::info!("regents: round {} from {}: walked away from the tree", ch.id, ch.entity_id);
        return None;
    }
    let r = rules::chop::play(ch.seed, &def.chop, &inputs);
    let salt = ch.seed ^ (micros(ctx.timestamp) as u64);
    let n = rules::whole_logs(rules::active_yield_milli(def, hot_number(ctx, hot::ACTIVE_YIELD_MULT), r.score_pm), rules::roll_permille(salt));
    let rare_mult = hot_number(ctx, hot::ACTIVE_RARE_MULT);
    let already = is_felled(ctx, tree_id);
    let (mut logs, mut rare, mut falls) = (0u32, 0u32, false);
    for i in 0..n as u64 {
        logs += 1;
        let (r_rare, r_fell) = rules::log_outcome(def, rare_mult, rules::roll_permille(salt ^ (i * 2 + 3)), rules::roll_permille(salt ^ (i * 2 + 4)));
        rare += u32::from(r_rare);
        if r_fell && !already {
            falls = true;
            break;
        }
    }
    let world_id = ctx.db.entity().entity_id().find(ch.entity_id).map(|e| e.world_id).unwrap_or(DEFAULT_WORLD);
    pay(ctx, ch.entity_id, world_id, tree_id, def, logs, rare, falls, true, r.score_pm as i32);
    if falls {
        fell(ctx, tree_id, def, ch.entity_id);
    }
    log::info!("regents: round {} on {} {tree_id}: {} clean, {} hits, score {} -> {logs} logs{}", ch.id, def.name,
        r.clean, r.hits, r.score_pm, if falls { ", timber!" } else { "" });
    Some(r.score_pm as f32 / 1000.0)
}

impl crate::game::Genre for Regents {
    fn claims(&self) -> &'static crate::genre::Claims {
        &rules::CLAIMS
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
        ctx.db.afk_chop().entity_id().delete(entity_id);
    }

    fn on_level_changed(&self, ctx: &ReducerContext, world_id: u32, _level_id: u8) {
        clear_trees(ctx, world_id);
        plant_trees(ctx, world_id);
    }

    fn resolve_challenge(&self, ctx: &ReducerContext, challenge: &Challenge, result: &[f32]) -> Option<f32> {
        if challenge.kind == CHALLENGE_CHOP {
            return resolve_chop(ctx, challenge, result);
        }
        None
    }
}
