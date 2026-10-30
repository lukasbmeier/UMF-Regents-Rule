//! REGION REFEREES (DECISIONS #288; Regent's Rule's load test, `REFEREE_SCALING.md` fix 3): a big world is
//! refereed by several sidecars, each for a REGION of cells (and a border it watches but does not run).
//! The module does not know the regions: a referee says which NPCs it drives, and the module keeps that
//! straight. One referee drives an NPC at a time (`npc_driver`): an NPC is taken only from nobody, or from a
//! referee that has gone (its heartbeat older than `AUTHORITY_TIMEOUT_MICROS`), and let go by its driver
//! as it walks out of that driver's region. So two referees never both drive one, even when one restarts.
//! A world with one referee for all of it (every game until now) never writes a row here.

use super::*;

/// WHICH REFEREE DRIVES AN NPC, in a world split into regions. Public: every referee of the world reads it
/// (a player's client never asks for it).
#[table(accessor = npc_driver, public)]
pub struct NpcDriver {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub driver: Identity,
    pub since: Timestamp,
}

/// The most NPCs one call may take and let go, together.
const MAX_DRIVE_BATCH: usize = 256;

/// Whether `identity` is a referee of `world_id` heard from in the last few seconds.
fn referee_alive(ctx: &ReducerContext, identity: Identity, world_id: u32) -> bool {
    let cutoff = ctx.timestamp - TimeDuration::from_micros(AUTHORITY_TIMEOUT_MICROS);
    ctx.db.authority().identity().find(identity)
        .is_some_and(|a| a.role == ROLE_SIDECAR && a.world_id == world_id && a.last_seen >= cutoff)
}

/// A REGION REFEREE TAKES AND LETS GO OF NPCs: `take` are the NPCs that have come into its region,
/// `release` those that have left it. A take of an NPC another live referee drives is skipped (it is
/// let go first); a take of a player is refused; a release of one it does not drive changes nothing.
/// Answers with nothing: the referee reads `npc_driver` to learn what it drives.
#[reducer]
pub fn drive_npcs(ctx: &ReducerContext, world_id: u32, take: Vec<u64>, release: Vec<u64>) -> Result<(), String> {
    require_authority(ctx, world_id)?;
    if take.len() + release.len() > MAX_DRIVE_BATCH {
        return Err(format!("drive_npcs: at most {MAX_DRIVE_BATCH} at once"));
    }
    for eid in release {
        if ctx.db.npc_driver().entity_id().find(eid).is_some_and(|d| d.driver == ctx.sender()) {
            ctx.db.npc_driver().entity_id().delete(eid);
        }
    }
    for eid in take {
        let Some(ent) = ctx.db.entity().entity_id().find(eid) else { continue };
        if ent.world_id != world_id {
            return Err(format!("drive_npcs: {eid} is in another world"));
        }
        if ctx.db.player().entity_id().find(eid).is_some() {
            return Err(format!("drive_npcs: {eid} is a player (players move themselves)"));
        }
        let row = NpcDriver { entity_id: eid, world_id, driver: ctx.sender(), since: ctx.timestamp };
        match ctx.db.npc_driver().entity_id().find(eid) {
            None => {
                ctx.db.npc_driver().insert(row);
            }
            Some(d) if d.driver == ctx.sender() => {}
            Some(d) if !referee_alive(ctx, d.driver, world_id) => {
                log::info!("world {world_id}: npc {eid} taken from a referee that has gone ({})", d.driver);
                ctx.db.npc_driver().entity_id().update(row);
            }
            Some(_) => {}
        }
    }
    Ok(())
}

/// ADMIN: one more referee for `world_id`, for a REGION of it, while the world already has one (which
/// `offer_referee` refuses: two referees for the whole world would judge every swing twice). The sidecar
/// that presents `code` within 30 s (`claim_referee`) is registered as another of its referees.
#[reducer]
pub fn offer_region_referee(ctx: &ReducerContext, world_id: u32, code: String) -> Result<(), String> {
    require_admin(ctx)?;
    if ctx.db.world_config().world_id().find(world_id).is_none() {
        return Err(format!("offer_region_referee: no world {world_id}"));
    }
    if code.len() < MIN_CODE_LEN {
        return Err(format!("offer_region_referee: a code of at least {MIN_CODE_LEN} characters"));
    }
    let until = ctx.timestamp + TimeDuration::from_micros(OFFER_MICROS);
    match ctx.db.referee_offer().world_id().find(world_id) {
        Some(o) if o.until > ctx.timestamp => Err(format!("a referee is already being started for world {world_id}")),
        Some(o) => {
            ctx.db.referee_offer().world_id().update(RefereeOffer { code, until, ..o });
            Ok(())
        }
        None => {
            ctx.db.referee_offer().insert(RefereeOffer { world_id, code, until });
            Ok(())
        }
    }
}

/// An entity gone: so is who drove it.
pub(crate) fn forget_driver(ctx: &ReducerContext, entity_id: u64) {
    ctx.db.npc_driver().entity_id().delete(entity_id);
}
