//! THE REFEREE (FOUNDATION_SYSTEMS milestone 5, OPEN_ITEMS A1, DECISIONS #226): an ability its
//! content marks `judged` is not resolved here. `use_ability` queues it (`action_request`) for the
//! world's REFEREE, a sidecar, which judges it as it lands (its wind-up after the use) against the
//! level's walls and everyone where its user saw them, rewound by what the user saw (at most
//! `foundation.rewind_max_ms`, favouring the attacker), and answers with `resolve_action`. What a hit
//! does is the genre's (`on_ability_hit`), else the ability's damage.
//!
//! A referee is a sidecar registered for ONE world (`authority`, ROLE_SIDECAR). In a SIDECAR world
//! that is the process that also moves everyone; in a MODULE world (players move themselves) it only
//! judges. An admin's client starts one on its own machine and hands it a one-time code
//! (`offer_referee`); the sidecar presents it (`claim_referee`) and is registered, so nobody has to
//! copy an identity by hand. While no referee is online a judged ability is refused (said, not
//! guessed at), and a request nobody answered in time is a miss.

use super::*;

/// A JUDGED USE WAITING FOR ITS REFEREE. Public behind the filter below: only an authority for its
/// world reads it (as `input_queue`), so a player never learns another's aim early.
#[table(accessor = action_request, public)]
pub struct ActionRequest {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub world_id: u32,
    pub actor_id: u64,
    pub ability_id: u32,
    /// What its user aimed at, if anything (an untargeted sweep: 0).
    pub target_id: u64,
    pub aim: Vector3,
    pub predicted_id: u32,
    /// How far back the referee looks at everyone else: what the user saw (its view delay), capped by
    /// `foundation.rewind_max_ms`.
    pub rewind_ms: u32,
    pub issued_at: Timestamp,
    /// When it lands (`issued_at` + its wind-up): the referee judges it as things stood then.
    pub due_at: Timestamp,
}

/// Only an authority registered for a world may read that world's requests.
#[client_visibility_filter]
pub(crate) const ACTION_REQUEST_IS_AUTHORITY_ONLY: Filter = Filter::Sql(
    "SELECT r.* FROM action_request r JOIN authority a ON a.world_id = r.world_id WHERE a.identity = :sender",
);

/// An admin's one-time code for a referee it is starting for `world_id`. Private.
#[table(accessor = referee_offer)]
pub struct RefereeOffer {
    #[primary_key]
    pub world_id: u32,
    pub code: String,
    pub until: Timestamp,
}

/// How long an offer stands: long enough for a sidecar to boot and connect.
pub(crate) const OFFER_MICROS: i64 = 30_000_000;
/// A request nobody answered by its landing time and this: a miss (the referee went away).
pub(crate) const REQUEST_GRACE_MICROS: i64 = 3_000_000;
/// The shortest code an offer takes.
pub(crate) const MIN_CODE_LEN: usize = 16;

/// Whether the world's referee judges `def` (its row's `data` says `"judged":true`, as the bake writes
/// it for content marked judged), rather than the module's coarse test.
pub fn is_judged(def: &AbilityDef) -> bool {
    def.data.replace(' ', "").contains("\"judged\":true")
}

/// Whether `world_id` has a referee now: a sidecar registered for it that beat in the last 5 s.
pub fn referee_online(ctx: &ReducerContext, world_id: u32) -> bool {
    let cutoff = ctx.timestamp - TimeDuration::from_micros(AUTHORITY_TIMEOUT_MICROS);
    ctx.db.authority().iter().any(|a| a.role == ROLE_SIDECAR && a.world_id == world_id && a.last_seen >= cutoff)
}

/// ADMIN: a referee is being started for `world_id`; the sidecar that presents `code` within 30 s
/// becomes it. Refused while the world has a referee, or another offer stands.
#[reducer]
pub fn offer_referee(ctx: &ReducerContext, world_id: u32, code: String) -> Result<(), String> {
    require_admin(ctx)?;
    if ctx.db.world_config().world_id().find(world_id).is_none() {
        return Err(format!("offer_referee: no world {world_id}"));
    }
    if code.len() < MIN_CODE_LEN {
        return Err(format!("offer_referee: a code of at least {MIN_CODE_LEN} characters"));
    }
    if referee_online(ctx, world_id) {
        return Err(format!("world {world_id} already has a referee"));
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

/// A SIDECAR presents an admin's code: it is registered as `world_id`'s authority (its referee).
/// Once: the offer is used up. Its identity is stable (its token file), so it stays registered.
#[reducer]
pub fn claim_referee(ctx: &ReducerContext, world_id: u32, code: String) -> Result<(), String> {
    let offer = ctx.db.referee_offer().world_id().find(world_id).ok_or("claim_referee: nothing was offered for this world")?;
    if offer.until <= ctx.timestamp {
        ctx.db.referee_offer().world_id().delete(world_id);
        return Err("claim_referee: the offer ran out".into());
    }
    if offer.code != code {
        return Err("claim_referee: not the code offered".into());
    }
    if ctx.db.authority().identity().find(ctx.sender()).is_some_and(|a| a.role == ROLE_ADMIN) {
        return Err("claim_referee: an admin cannot be a referee (it would stop being an admin)".into());
    }
    ctx.db.referee_offer().world_id().delete(world_id);
    let row = Authority { identity: ctx.sender(), role: ROLE_SIDECAR, world_id, last_seen: ctx.timestamp };
    if ctx.db.authority().identity().find(ctx.sender()).is_some() {
        ctx.db.authority().identity().update(row);
    } else {
        ctx.db.authority().insert(row);
    }
    log::info!("world {world_id}: a referee claimed it ({})", ctx.sender());
    // It connected before it was registered, so it was made a player: it is not one.
    drop_sidecar_player(ctx, ctx.sender());
    Ok(())
}

/// A SIDECAR'S PLAYER, IF IT WAS GIVEN ONE, IS TAKEN AWAY (0.41.1): it connected as anyone does, before
/// it was registered, and a first connection makes a player (an entity standing at the spawn, online,
/// in every client's world). Its entity, and its player row, gone.
pub(crate) fn drop_sidecar_player(ctx: &ReducerContext, identity: Identity) {
    if let Some(p) = ctx.db.player().identity().find(identity) {
        despawn_entity_internal(ctx, p.entity_id);
        ctx.db.player().identity().delete(identity);
        log::info!("{identity}: a sidecar, not a player: its player {} taken away", p.entity_id);
    }
}

/// Queue a judged use for the referee (the checks a use makes are done: `use_ability_from`).
pub(crate) fn queue_judged(ctx: &ReducerContext, actor: u64, world_id: u32, def: &AbilityDef, target_id: u64, aim: Vector3,
    predicted_id: u32, view_delay_ms: u32) -> Result<(), String> {
    if !referee_online(ctx, world_id) {
        return Err(format!("use_ability: nobody is judging world {world_id} (no referee)"));
    }
    let cap = hot_number(ctx, crate::hot::foundation::REWIND_MAX_MS).clamp(0.0, 1000.0) as u32;
    let rewind_ms = view_delay_ms.min(cap);
    let due_at = ctx.timestamp + TimeDuration::from_micros(def.wind_up_ms as i64 * 1000);
    let r = ctx.db.action_request().insert(ActionRequest {
        id: 0, world_id, actor_id: actor, ability_id: def.ability_id, target_id, aim, predicted_id, rewind_ms,
        issued_at: ctx.timestamp, due_at,
    });
    log::info!("ability {} by {actor}: for the referee (request {}, lands in {} ms, rewound {rewind_ms} ms of {view_delay_ms})",
        def.ability_id, r.id, def.wind_up_ms);
    Ok(())
}

/// THE REFEREE'S ANSWER: request `request_id` hit `hit_id` (0: nothing). A hit is a hurt (a hold its
/// doer lets go of when hurt is let go of), then what the genre says a hit does, else the ability's
/// damage; a miss is the genre's too (a predator slowed). Every client sees it as an `action_event`.
#[reducer]
pub fn resolve_action(ctx: &ReducerContext, request_id: u64, hit_id: u64) -> Result<(), String> {
    let req = ctx.db.action_request().id().find(request_id).ok_or("resolve_action: no such request (answered, or run out)")?;
    require_authority(ctx, req.world_id)?;
    let def = ctx.db.ability_def().ability_id().find(req.ability_id).ok_or("resolve_action: unknown ability")?;
    let hit = hit_id != 0 && may_land(ctx, &req, hit_id, "resolve_action")?;
    ctx.db.action_request().id().delete(request_id);
    if hit {
        land(ctx, &req, &def, hit_id)?;
    } else {
        missed(ctx, &req);
    }
    log::info!("ability {} by {}: {} (request {request_id})", req.ability_id, req.actor_id,
        if hit { format!("hit {hit_id}") } else { "missed".to_string() });
    if !hit {
        insert_action_event(ctx, &req, req.target_id, OUTCOME_MISS);
    }
    Ok(())
}

/// The most bodies one answer may name (a crowd in one sweep; a referee's wrong report is refused, not cut).
pub const MOST_HIT_AT_ONCE: usize = 32;

/// THE REFEREE'S ANSWER FOR A SWEEP THAT HITS ALL (`AbilityDef.hits_all`, its row's `data` saying
/// `"hits_all":true`): request `request_id` met every one of `hit_ids` (nearest first; none: a miss). Each is
/// checked and dealt as `resolve_action` deals one, in that order, with an `action_event` each; those who cannot
/// be hit now are passed over, and if none could, it is a miss. Refused whole for an ability that does not hit
/// all, a body named twice, more than `MOST_HIT_AT_ONCE`, or any name `resolve_action` would refuse.
/// Add-only (rule 17): `resolve_action` is unchanged, and a referee sends this only for such a sweep.
#[reducer]
pub fn resolve_action_all(ctx: &ReducerContext, request_id: u64, hit_ids: Vec<u64>) -> Result<(), String> {
    const WHO: &str = "resolve_action_all";
    let req = ctx.db.action_request().id().find(request_id).ok_or("resolve_action_all: no such request (answered, or run out)")?;
    require_authority(ctx, req.world_id)?;
    let def = ctx.db.ability_def().ability_id().find(req.ability_id).ok_or("resolve_action_all: unknown ability")?;
    if !hits_all(&def) {
        return Err(format!("{WHO}: ability {} hits one (its first): answer it with resolve_action", def.ability_id));
    }
    if hit_ids.len() > MOST_HIT_AT_ONCE {
        return Err(format!("{WHO}: {} bodies, at most {MOST_HIT_AT_ONCE}", hit_ids.len()));
    }
    let mut landing: Vec<u64> = Vec::with_capacity(hit_ids.len());
    for (i, id) in hit_ids.iter().enumerate() {
        if *id == 0 || hit_ids[..i].contains(id) {
            return Err(format!("{WHO}: {id} named twice, or nobody"));
        }
        if may_land(ctx, &req, *id, WHO)? {
            landing.push(*id);
        }
    }
    ctx.db.action_request().id().delete(request_id);
    for id in &landing {
        land(ctx, &req, &def, *id)?;
    }
    if landing.is_empty() {
        missed(ctx, &req);
        insert_action_event(ctx, &req, req.target_id, OUTCOME_MISS);
    }
    log::info!("ability {} by {}: hit {:?} of {:?} (request {request_id})", req.ability_id, req.actor_id, landing, hit_ids);
    Ok(())
}

/// Whether the world's referee answers `def` with every body its sweep met (`resolve_action_all`).
pub fn hits_all(def: &AbilityDef) -> bool {
    def.data.replace(' ', "").contains("\"hits_all\":true")
}

/// Whether the referee's `hit_id` for `req` lands: Err for a report that cannot be right (itself, another world, someone
/// gone, a thing); false for one who cannot be hit NOW (their state or an effect: downed, out, rolling: DECISIONS #312:
/// the referee proposed it from rows that had not yet caught up, a matter of timing, not a wrong report) or who
/// rolled clear of it where they pressed it (#309: one its player began as they saw this land, and still rolling then,
/// though its status had not reached the referee or has run out since).
fn may_land(ctx: &ReducerContext, req: &ActionRequest, hit_id: u64, who: &str) -> Result<bool, String> {
    if hit_id == req.actor_id {
        return Err(format!("{who}: not itself"));
    }
    let target = ctx.db.entity().entity_id().find(hit_id).ok_or(format!("{who}: no such target"))?;
    if target.world_id != req.world_id {
        return Err(format!("{who}: the target is in another world"));
    }
    if ctx.db.player().entity_id().find(hit_id).is_some_and(|p| !p.online) {
        return Err(format!("{who}: they are not here"));
    }
    if !is_person(ctx, hit_id) {
        return Err(format!("{who}: not someone (a thing is not hit)"));
    }
    if !is_targetable(ctx, hit_id) || !is_hittable(ctx, hit_id) {
        log::info!("ability {} by {}: {hit_id} cannot be hit now: a miss", req.ability_id, req.actor_id);
        return Ok(false);
    }
    if rolled_clear(ctx, hit_id, req.due_at.to_micros_since_unix_epoch()) {
        log::info!("ability {} by {}: {hit_id} rolled clear of it", req.ability_id, req.actor_id);
        return Ok(false);
    }
    Ok(true)
}

/// `req` lands on `hit_id`: a hurt, then what the genre says a hit does, else the ability's damage; its `action_event`.
fn land(ctx: &ReducerContext, req: &ActionRequest, def: &AbilityDef, hit_id: u64) -> Result<(), String> {
    hurt(ctx, hit_id);
    let target = ctx.db.entity().entity_id().find(hit_id).ok_or("resolve_action: no such target")?;
    if !crate::game::on_ability_hit(ctx, req.actor_id, &target, req.ability_id) && def.damage > 0.0 {
        damage_entity(ctx, hit_id, def.damage, req.actor_id)?;
    }
    insert_action_event(ctx, req, hit_id, OUTCOME_HIT);
    Ok(())
}

/// `req` hit nothing: the genre hears it.
fn missed(ctx: &ReducerContext, req: &ActionRequest) {
    let kind = ctx.db.entity().entity_id().find(req.actor_id).map(|e| e.kind).unwrap_or(0);
    crate::game::on_ability_missed(ctx, req.actor_id, kind, req.ability_id);
}

fn insert_action_event(ctx: &ReducerContext, req: &ActionRequest, target_id: u64, outcome: u8) {
    ctx.db.action_event().insert(ActionEvent {
        id: 0,
        world_id: req.world_id,
        chunk: chunk_of_entity(ctx, req.actor_id),
        actor_id: req.actor_id,
        ability_id: req.ability_id,
        target_id,
        aim: req.aim,
        outcome,
        predicted_id: req.predicted_id,
        server_ts: ctx.timestamp,
    });
}

/// From the 1 Hz prune: a request nobody answered by its landing time and the grace is a miss, with
/// no penalty (the referee went away; it was not the user's miss).
pub(crate) fn expire_requests(ctx: &ReducerContext) {
    let cutoff = ctx.timestamp - TimeDuration::from_micros(REQUEST_GRACE_MICROS);
    let late: Vec<ActionRequest> = ctx.db.action_request().iter().filter(|r| r.due_at < cutoff).collect();
    for r in late {
        log::warn!("ability {} by {}: no referee answered request {} in time: a miss", r.ability_id, r.actor_id, r.id);
        ctx.db.action_request().id().delete(r.id);
        insert_action_event(ctx, &r, r.target_id, OUTCOME_MISS);
    }
}
