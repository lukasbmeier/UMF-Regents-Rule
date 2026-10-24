//! The phase machine, matches, the lobby, joining and leaving, NPC brains, score. Split from module.rs (REVIEW 0.23.1 C2); `mod.rs` says why the
//! module is wasm-only.

use super::*;

// =============================================================================
// SESSIONS (phase machine)
// =============================================================================

/// Shared by `join_session` and the auto-join in `client_connected` (and a genre's NPC that plays
/// the round, like the fishing rival).
pub fn add_member(ctx: &ReducerContext, sess: &Session, entity_id: u64) -> Result<(), String> {
    let already = ctx
        .db
        .session_member()
        .entity_id()
        .filter(entity_id)
        .any(|m| m.session_id == sess.id);
    if already {
        return Ok(());
    }
    if sess.max_members > 0 {
        let count = ctx.db.session_member().session_id().filter(sess.id).count();
        if count >= sess.max_members as usize {
            return Err("session is full".into());
        }
    }
    ctx.db.session_member().insert(SessionMember {
        id: 0,
        session_id: sess.id,
        entity_id,
        score: 0,
        coins: 0,
    });
    // The lobby's row: not ready, on the smallest team.
    let world_id = ctx.db.entity().entity_id().find(entity_id).map(|e| e.world_id).unwrap_or(sess.world_id);
    let team = smallest_team(ctx, sess);
    let row = LobbyMember { entity_id, world_id, session_id: sess.id, ready: false, team };
    if ctx.db.lobby_member().entity_id().find(entity_id).is_some() {
        ctx.db.lobby_member().entity_id().update(row);
    } else {
        ctx.db.lobby_member().insert(row);
    }
    Ok(())
}

/// A member's lobby row, made when it is missing (DECISIONS #184): a member from before the lobby
/// existed (a world republished without a wipe) had none, and Ready said "you are not in a session".
pub(crate) fn ensure_lobby_member(ctx: &ReducerContext, sess: &Session, entity_id: u64) -> LobbyMember {
    if let Some(row) = ctx.db.lobby_member().entity_id().find(entity_id) {
        return row;
    }
    let world_id = ctx.db.entity().entity_id().find(entity_id).map(|e| e.world_id).unwrap_or(sess.world_id);
    let team = smallest_team(ctx, sess);
    ctx.db.lobby_member().insert(LobbyMember { entity_id, world_id, session_id: sess.id, ready: false, team })
}

/// The session `entity_id` is a member of, and its lobby row (made if missing), for a lobby reducer.
pub(crate) fn lobby_of(ctx: &ReducerContext, entity_id: u64, verb: &str) -> Result<(Session, LobbyMember), String> {
    let member = ctx.db.session_member().entity_id().filter(entity_id).next()
        .ok_or(format!("{verb}: you are not in a session"))?;
    let sess = ctx.db.session().id().find(member.session_id).ok_or(format!("{verb}: no such session"))?;
    let row = ensure_lobby_member(ctx, &sess, entity_id);
    Ok((sess, row))
}

/// The team with the fewest members in `sess` (0 when its kind has no teams).
pub(crate) fn smallest_team(ctx: &ReducerContext, sess: &Session) -> u8 {
    let Some(lobby) = crate::rules::lobby(sess.kind) else { return 0 };
    if lobby.teams.is_empty() {
        return 0;
    }
    let mut counts = vec![0usize; lobby.teams.len()];
    for m in ctx.db.lobby_member().session_id().filter(sess.id) {
        if (m.team as usize) < counts.len() {
            counts[m.team as usize] += 1;
        }
    }
    counts.iter().enumerate().min_by_key(|(_, c)| **c).map(|(i, _)| i as u8).unwrap_or(0)
}

/// Whether every PLAYER in a lobby that starts on ready is ready, and there are enough of them. NPC
/// members (a fishing rival) and players who are not online are not waited for.
pub(crate) fn lobby_all_ready(ctx: &ReducerContext, sess: &Session) -> bool {
    let Some(lobby) = crate::rules::lobby(sess.kind) else { return false };
    if !lobby.ready_up || sess.phase != PHASE_LOBBY {
        return false;
    }
    let mut players = 0u16;
    for m in ctx.db.lobby_member().session_id().filter(sess.id) {
        let online = ctx.db.player().entity_id().find(m.entity_id).map(|p| p.online).unwrap_or(false);
        if !online {
            continue;
        }
        if !m.ready {
            return false;
        }
        players += 1;
    }
    players >= lobby.min_players.max(1)
}

/// Say you are ready to start (or not). Counts while your session is in its lobby; a round starts
/// at once when the rules say ready-up and everyone is (DECISIONS #174).
#[reducer]
pub fn set_ready(ctx: &ReducerContext, ready: bool) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("set_ready: no player row")?;
    spend_rate(ctx, player.entity_id, "set_ready")?;
    let (sess, mut row) = lobby_of(ctx, player.entity_id, "set_ready")?;
    if sess.phase != PHASE_LOBBY {
        return Err("set_ready: the round has already started".into());
    }
    if row.ready == ready {
        return Ok(());
    }
    row.ready = ready;
    ctx.db.lobby_member().entity_id().update(row);
    if lobby_all_ready(ctx, &sess) {
        log::info!("session {}: everyone is ready", sess.id);
        advance_session(ctx, sess);
    }
    Ok(())
}

/// Pick a team in the lobby (a number into the rules' teams).
#[reducer]
pub fn set_team(ctx: &ReducerContext, team: u8) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("set_team: no player row")?;
    spend_rate(ctx, player.entity_id, "set_team")?;
    let (sess, mut row) = lobby_of(ctx, player.entity_id, "set_team")?;
    let teams = crate::rules::lobby(sess.kind).map(|l| l.teams).unwrap_or(&[]);
    if teams.is_empty() {
        return Err("set_team: this game has no teams".into());
    }
    if team as usize >= teams.len() {
        return Err(format!("set_team: there is no team {team} (0..{})", teams.len() - 1));
    }
    if sess.phase != PHASE_LOBBY {
        return Err("set_team: teams are picked in the lobby".into());
    }
    row.team = team;
    ctx.db.lobby_member().entity_id().update(row);
    Ok(())
}

/// How long `phase` lasts for this `kind`, from its plan in shared/rules.json (DECISIONS #154).
/// None — held until a reducer moves it — for a phase planned at 0 seconds, a phase its kind does
/// not plan, and a kind with no plan at all.
pub(crate) fn phase_duration_micros(kind: u8, phase: u8) -> Option<i64> {
    let plan = crate::rules::plan(kind)?;
    let (_, micros) = plan.iter().find(|(p, _)| *p == phase)?;
    if *micros > 0 { Some(*micros) } else { None }
}

/// The phase after `phase` in this kind's plan, going round. A phase the plan does not have goes
/// to the plan's first; a kind with no plan stays where it is.
pub(crate) fn next_phase(kind: u8, phase: u8) -> u8 {
    let Some(plan) = crate::rules::plan(kind) else {
        return phase;
    };
    match plan.iter().position(|(p, _)| *p == phase) {
        Some(i) => plan[(i + 1) % plan.len()].0,
        None => plan[0].0,
    }
}

/// Scheduled 1 Hz. Moves every session whose timer has expired to its next phase.
/// Entering LOBBY starts a new round: scores reset and a fresh seed is rolled.
#[reducer]
pub fn advance_phases(ctx: &ReducerContext, _sched: PhaseSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("advance_phases: scheduler only".into());
    }
    // THE MATCH (DECISIONS #182): a world nobody has been in for a while ends its match and waits.
    let sessions: Vec<Session> = ctx.db.session().iter().collect();
    for sess in sessions {
        if crate::rules::plan(sess.kind).is_none() {
            continue;   // a kind with no plan is a genre's to drive, matches and all
        }
        let Some(m) = ctx.db.session_match().session_id().find(sess.id) else {
            begin_match(ctx, sess);   // a session from before matches: its next round is round 1
            continue;
        };
        if online_players(ctx, &sess) > 0 {
            ctx.db.session_empty().session_id().delete(sess.id);
            continue;
        }
        if !m.started {
            // The match's lobby, with nobody to wait for: held until someone arrives.
            if sess.phase == PHASE_LOBBY && sess.phase_ends_at < ctx.timestamp + TimeDuration::from_micros(HOLD_MICROS / 2) {
                let mut held = sess;
                held.phase_ends_at = ctx.timestamp + TimeDuration::from_micros(HOLD_MICROS);
                ctx.db.session().id().update(held);
            }
            continue;
        }
        let since = match ctx.db.session_empty().session_id().find(sess.id) {
            Some(e) => e.since,
            None => {
                ctx.db.session_empty().insert(SessionEmpty { session_id: sess.id, since: ctx.timestamp });
                ctx.timestamp
            }
        };
        let empty_for = ctx.timestamp.to_micros_since_unix_epoch() - since.to_micros_since_unix_epoch();
        if empty_for >= crate::rules::match_rules(sess.kind).end_after_empty_micros {
            log::info!("session {}: nobody here for {} s, the match ends", sess.id, empty_for / 1_000_000);
            ctx.db.session_empty().session_id().delete(sess.id);
            begin_match(ctx, sess);
        }
    }

    let due: Vec<Session> = ctx
        .db
        .session()
        .iter()
        .filter(|s| s.phase_ends_at <= ctx.timestamp)
        .collect();

    for sess in due {
        let Some(_) = phase_duration_micros(sess.kind, sess.phase) else {
            continue;   // unknown kind: a genre reducer drives it, not this machine
        };
        advance_session(ctx, sess);
    }
    // A lobby whose players all said ready while nobody was asking (one left, the last unready one).
    let waiting: Vec<Session> = ctx.db.session().iter().filter(|s| s.phase == PHASE_LOBBY).collect();
    for sess in waiting {
        if lobby_all_ready(ctx, &sess) {
            advance_session(ctx, sess);
        }
    }
    Ok(())
}

/// Move a session to the next phase of its plan. Entering LOBBY starts a new round: scores reset,
/// a fresh seed, and nobody is ready yet.
pub(crate) fn advance_session(ctx: &ReducerContext, mut sess: Session) {
    let from = sess.phase;
    let to = next_phase(sess.kind, sess.phase);
    sess.phase = to;
    sess.phase_ends_at = ctx.timestamp
        + TimeDuration::from_micros(phase_duration_micros(sess.kind, to).unwrap_or(HOLD_MICROS));
    if to == PHASE_LOBBY {
        new_round(ctx, &mut sess);
    }
    if from == PHASE_LOBBY && to != PHASE_LOBBY {
        mark_match_started(ctx, sess.id);
    }
    let id = sess.id;
    ctx.db.session().id().update(sess);
    log::info!("session {id}: phase {from} -> {to}");
    if let Some(now) = ctx.db.session().id().find(id) {
        crate::game::on_phase_changed(ctx, &now, from);
    }
}

/// A new round on `sess` (not yet written): its number, a fresh seed so last round's rolls cannot
/// be replayed, scores reset, and nobody ready yet.
pub(crate) fn new_round(ctx: &ReducerContext, sess: &mut Session) {
    sess.round = sess.round.saturating_add(1);
    sess.seed = ctx.timestamp.to_micros_since_unix_epoch() as u64 ^ (sess.id << 17);
    let members: Vec<SessionMember> = ctx.db.session_member().session_id().filter(sess.id).collect();
    for mut m in members {
        m.score = 0;
        ctx.db.session_member().id().update(m);
    }
    let lobby: Vec<LobbyMember> = ctx.db.lobby_member().session_id().filter(sess.id).collect();
    for mut m in lobby {
        if m.ready {
            m.ready = false;
            ctx.db.lobby_member().entity_id().update(m);
        }
    }
}

// --- the match (DECISIONS #182) -------------------------------------------------------------------

/// How many of a session's members are PLAYERS who are online. An NPC member (a fishing rival) and a
/// player who left are not.
pub(crate) fn online_players(ctx: &ReducerContext, sess: &Session) -> usize {
    ctx.db
        .session_member()
        .session_id()
        .filter(sess.id)
        .filter(|m| ctx.db.player().entity_id().find(m.entity_id).map(|p| p.online).unwrap_or(false))
        .count()
}

/// The round a player sees: counted from 1 in the session's match. A genre that shows or depends on
/// "which round of the game this is" (fishing's time of day) reads this, never `session.round`.
pub fn match_round(ctx: &ReducerContext, sess: &Session) -> u32 {
    match ctx.db.session_match().session_id().find(sess.id) {
        Some(m) => sess.round.saturating_sub(m.first_round).saturating_add(1),
        None => sess.round,
    }
}

/// Begin a new match on a session: back to the lobby if a round was under way (a new round, as at
/// the end of any round), its rounds counted from 1 from here, and the lobby waiting for players.
pub(crate) fn begin_match(ctx: &ReducerContext, mut sess: Session) {
    let from = sess.phase;
    if from != PHASE_LOBBY {
        sess.phase = PHASE_LOBBY;
        new_round(ctx, &mut sess);
    }
    sess.phase_ends_at = match_lobby_ends(ctx, &sess);
    let previous = ctx.db.session_match().session_id().find(sess.id);
    let row = SessionMatch {
        session_id: sess.id,
        world_id: sess.world_id,
        first_round: sess.round,
        started: false,
        number: previous.as_ref().map(|m| m.number.saturating_add(1)).unwrap_or(1),
    };
    let (id, number) = (sess.id, row.number);
    if previous.is_some() {
        ctx.db.session_match().session_id().update(row);
    } else {
        ctx.db.session_match().insert(row);
    }
    let world = sess.world_id;
    ctx.db.session().id().update(sess);
    log::info!("session {id}: match {number} begins, its lobby waiting for players");
    reset_statuses(ctx, world);
    if let Some(now) = ctx.db.session().id().find(id) {
        if from != PHASE_LOBBY {
            crate::game::on_phase_changed(ctx, &now, from);
        }
        crate::game::on_match_began(ctx, &now);
    }
}

/// When a match's first lobby ends: never while nobody is online; with ready-up and no `wait_s`,
/// never (everyone ready starts it); otherwise after `wait_s`, or the lobby's own seconds.
pub(crate) fn match_lobby_ends(ctx: &ReducerContext, sess: &Session) -> Timestamp {
    let rules = crate::rules::match_rules(sess.kind);
    let ready_up = crate::rules::lobby(sess.kind).map(|l| l.ready_up).unwrap_or(false);
    let micros = if online_players(ctx, sess) == 0 {
        HOLD_MICROS
    } else if rules.wait_micros > 0 {
        rules.wait_micros
    } else if ready_up {
        HOLD_MICROS
    } else {
        phase_duration_micros(sess.kind, PHASE_LOBBY).unwrap_or(HOLD_MICROS)
    };
    ctx.timestamp + TimeDuration::from_micros(micros)
}

pub(crate) fn mark_match_started(ctx: &ReducerContext, session_id: u64) {
    if let Some(mut m) = ctx.db.session_match().session_id().find(session_id) {
        if !m.started {
            m.started = true;
            ctx.db.session_match().session_id().update(m);
        }
    }
}

/// A player came online: their sessions are not empty, and a match lobby held while nobody was here
/// starts its clock (DECISIONS #182).
pub(crate) fn player_arrived(ctx: &ReducerContext, entity_id: u64) {
    let sessions: Vec<u64> = ctx.db.session_member().entity_id().filter(entity_id).map(|m| m.session_id).collect();
    for sid in sessions {
        ctx.db.session_empty().session_id().delete(sid);
        if let Some(sess) = ctx.db.session().id().find(sid) {
            ensure_lobby_member(ctx, &sess, entity_id);   // a member from before the lobby (#184)
        }
        let (Some(sess), Some(m)) = (ctx.db.session().id().find(sid), ctx.db.session_match().session_id().find(sid)) else {
            continue;
        };
        if !m.started && sess.phase == PHASE_LOBBY {
            let ends = match_lobby_ends(ctx, &sess);
            if ends < sess.phase_ends_at {
                let mut s = sess;
                s.phase_ends_at = ends;
                ctx.db.session().id().update(s);
            }
        }
    }
}

/// Admin: end a session's match now and begin the next one, its rounds counted from 1 again
/// (DECISIONS #182). A world does this by itself once nobody has been in it for a while.
#[reducer]
pub fn new_match(ctx: &ReducerContext, session_id: u64) -> Result<(), String> {
    require_admin(ctx)?;
    let sess = ctx.db.session().id().find(session_id).ok_or("new_match: no such session")?;
    ctx.db.session_empty().session_id().delete(session_id);
    begin_match(ctx, sess);
    Ok(())
}

/// Dev/admin: force a session into a phase. Admin-only. Without this, exercising a round-based
/// genre means waiting out real phase durations in every test run.
#[reducer]
pub fn set_session_phase(ctx: &ReducerContext, session_id: u64, phase: u8) -> Result<(), String> {
    require_admin(ctx)?;
    let mut sess = ctx.db.session().id().find(session_id).ok_or("no such session")?;
    let dur = phase_duration_micros(sess.kind, phase).unwrap_or(HOLD_MICROS);
    let from = sess.phase;
    sess.phase = phase;
    sess.phase_ends_at = ctx.timestamp + TimeDuration::from_micros(dur);
    ctx.db.session().id().update(sess);
    if phase != PHASE_LOBBY {
        mark_match_started(ctx, session_id);
    }
    if from != phase {
        if let Some(now) = ctx.db.session().id().find(session_id) {
            crate::game::on_phase_changed(ctx, &now, from);
        }
    }
    Ok(())
}

/// Create a session on a world, creating the world as MODULE authority if it does not exist.
/// Admin-only in the foundation: a lobby system is a genre concern and will want its own rules
/// (per-player limits, matchmaking), so the safe default is that players cannot spawn sessions.
#[reducer]
pub fn create_session(
    ctx: &ReducerContext,
    world_id: u32,
    kind: u8,
    max_members: u16,
) -> Result<(), String> {
    require_admin(ctx)?;
    if ctx.db.session().world_id().find(world_id).is_some() {
        return Err(format!("world {world_id} already has a session"));
    }
    if ctx.db.world_config().world_id().find(world_id).is_none() {
        ctx.db.world_config().insert(WorldConfig {
            world_id,
            sim_authority: SIM_MODULE,
            authority_online: true,
            server_tick: 0,
            server_ts: ctx.timestamp,
            spawn: default_spawn(),
        });
    }
    let dur = phase_duration_micros(kind, PHASE_LOBBY).unwrap_or(HOLD_MICROS);
    let sess = ctx.db.session().insert(Session {
        id: 0,
        world_id,
        kind,
        phase: PHASE_LOBBY,
        phase_ends_at: ctx.timestamp + TimeDuration::from_micros(dur),
        seed: ctx.timestamp.to_micros_since_unix_epoch() as u64 ^ ((world_id as u64) << 32),
        max_members,
        round: 1,
    });
    begin_match(ctx, sess);
    Ok(())
}

/// Join a session. Moves the caller's entity into that session's world, so subscriptions and
/// `tick_movement` follow it without a second reducer.
#[reducer]
pub fn join_session(ctx: &ReducerContext, session_id: u64) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    spend_rate(ctx, player.entity_id, "join_session")?;
    let sess = ctx.db.session().id().find(session_id).ok_or("no such session")?;
    add_member(ctx, &sess, player.entity_id)?;
    move_entity_to_world(ctx, player.entity_id, sess.world_id);
    Ok(())
}

#[reducer]
pub fn leave_session(ctx: &ReducerContext) -> Result<(), String> {
    let player = ctx.db.player().identity().find(ctx.sender()).ok_or("no player row")?;
    spend_rate(ctx, player.entity_id, "leave_session")?;
    let rows: Vec<SessionMember> =
        ctx.db.session_member().entity_id().filter(player.entity_id).collect();
    for m in rows {
        ctx.db.session_member().id().delete(m.id);
    }
    ctx.db.lobby_member().entity_id().delete(player.entity_id);
    move_entity_to_world(ctx, player.entity_id, DEFAULT_WORLD);
    Ok(())
}

/// Keep every row that describes an entity on the same world. Anything that scopes by world
/// (subscriptions, `tick_movement`, authority checks) reads these. The rows that also carry its cell
/// follow it through `follow` (template 1.0); the rest are here.
pub(crate) fn move_entity_to_world(ctx: &ReducerContext, entity_id: u64, world_id: u32) {
    if let Some(mut m) = ctx.db.movement_state().entity_id().find(entity_id) {
        m.world_id = world_id;
        m.teleport_flag = true;   // the client must snap, not interpolate across worlds
        write_movement(ctx, m);   // and everything that follows it goes too
    } else {
        follow(ctx, entity_id, world_id, chunk_of_entity(ctx, entity_id));
    }
    let queued: Vec<u64> = ctx.db.input_queue().entity_id().filter(entity_id).map(|q| q.id).collect();
    for id in queued {
        ctx.db.input_queue().id().delete(id);   // inputs aimed at the old world are meaningless
    }
    // The brain goes with its body: the new world's authority is the one that must read it.
    if let Some(mut b) = ctx.db.npc_brain().entity_id().find(entity_id) {
        b.world_id = world_id;
        ctx.db.npc_brain().entity_id().update(b);
    }
    if let Some(mut l) = ctx.db.lobby_member().entity_id().find(entity_id) {
        l.world_id = world_id;
        ctx.db.lobby_member().entity_id().update(l);
    }
}

/// Persist what an NPC's brain needs to resume after a restart (see `NpcBrainRow`). Authority
/// only, and only for an NPC: a player's decisions come from a person, not a brain.
#[reducer]
pub fn write_npc_brain(
    ctx: &ReducerContext,
    entity_id: u64,
    brain: String,
    state: String,
    target_id: u64,
    data: String,
) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("write_npc_brain: no such entity")?;
    require_authority(ctx, ent.world_id)?;
    if ctx.db.player().entity_id().find(entity_id).is_some() {
        return Err("write_npc_brain: a player entity has no brain".into());
    }
    if brain.len() > MAX_BRAIN_NAME || state.len() > MAX_BRAIN_NAME {
        return Err(format!("write_npc_brain: names are limited to {MAX_BRAIN_NAME} bytes"));
    }
    if data.len() > MAX_BRAIN_DATA {
        return Err(format!(
            "write_npc_brain: data is {} bytes, the limit is {MAX_BRAIN_DATA}",
            data.len()
        ));
    }
    let row = NpcBrainRow {
        entity_id,
        world_id: ent.world_id,
        brain,
        state,
        target_id,
        data,
        updated_at: ctx.timestamp,
    };
    if ctx.db.npc_brain().entity_id().find(entity_id).is_some() {
        ctx.db.npc_brain().entity_id().update(row);
    } else {
        ctx.db.npc_brain().insert(row);
    }
    Ok(())
}

// --- bots (milestone 7, DECISIONS #230) -----------------------------------------------------------

/// A BOT: an NPC of `kind` in `sess`'s world at `pos`, a member of the session (it scores, it is in the
/// standings, on the smallest team), driven by brain `brain` (its `npc_brain` row: the world's referee,
/// or its sidecar, builds every entity with one and runs that brain on it). A genre decides when and
/// how many (Fowl Play fills a night to one wolf and four hens). Returns its entity id.
pub fn add_bot_internal(ctx: &ReducerContext, sess: &Session, kind: u8, brain: &str, pos: Vector3) -> Result<u64, String> {
    if brain.is_empty() || brain.len() > MAX_BRAIN_NAME {
        return Err(format!("add_bot: a brain's name is 1-{MAX_BRAIN_NAME} bytes"));
    }
    let id = spawn_npc_internal(ctx, sess.world_id, kind, pos, 0.0);
    if let Err(e) = add_member(ctx, sess, id) {
        despawn_entity_internal(ctx, id);
        return Err(format!("add_bot: {e}"));
    }
    ctx.db.npc_brain().insert(NpcBrainRow {
        entity_id: id,
        world_id: sess.world_id,
        brain: brain.to_string(),
        state: String::new(),
        target_id: 0,
        data: "{}".into(),
        updated_at: ctx.timestamp,
    });
    log::info!("session {}: bot {id} (kind {kind}, brain '{brain}') joins", sess.id);
    Ok(id)
}

/// Whether `entity_id` is a bot: it has a brain row and is not a player.
pub fn is_bot(ctx: &ReducerContext, entity_id: u64) -> bool {
    ctx.db.npc_brain().entity_id().find(entity_id).is_some() && ctx.db.player().entity_id().find(entity_id).is_none()
}

/// The bots in `sess`, by entity id.
pub fn bots_of(ctx: &ReducerContext, sess: &Session) -> Vec<u64> {
    ctx.db.session_member().session_id().filter(sess.id).map(|m| m.entity_id).filter(|&e| is_bot(ctx, e)).collect()
}

/// Every bot in `sess` gone (its entity and every row of it). Returns how many.
pub fn remove_bots_internal(ctx: &ReducerContext, sess: &Session) -> usize {
    let bots = bots_of(ctx, sess);
    for &b in &bots {
        despawn_entity_internal(ctx, b);
    }
    if !bots.is_empty() {
        log::info!("session {}: {} bot(s) leave", sess.id, bots.len());
    }
    bots.len()
}

/// ADMIN: a bot in session `session_id` (a test; a designer filling a lobby by hand).
#[reducer]
pub fn add_bot(ctx: &ReducerContext, session_id: u64, kind: u8, brain: String, pos: Vector3) -> Result<(), String> {
    require_admin(ctx)?;
    let sess = ctx.db.session().id().find(session_id).ok_or("add_bot: no such session")?;
    add_bot_internal(ctx, &sess, kind, &brain, pos).map(|_| ())
}

/// ADMIN: every bot in session `session_id` gone.
#[reducer]
pub fn remove_bots(ctx: &ReducerContext, session_id: u64) -> Result<(), String> {
    require_admin(ctx)?;
    let sess = ctx.db.session().id().find(session_id).ok_or("remove_bots: no such session")?;
    remove_bots_internal(ctx, &sess);
    Ok(())
}

/// Authority-only score/coin write. Genres award through this so the client never owns score.
#[reducer]
pub fn add_score(ctx: &ReducerContext, entity_id: u64, score: i64, coins: i64) -> Result<(), String> {
    let ent = ctx.db.entity().entity_id().find(entity_id).ok_or("no such entity")?;
    require_authority(ctx, ent.world_id)?;
    let rows: Vec<SessionMember> = ctx.db.session_member().entity_id().filter(entity_id).collect();
    for mut m in rows {
        m.score += score;
        m.coins += coins;
        ctx.db.session_member().id().update(m);
    }
    Ok(())
}
