//! ACCOUNTS AND CHARACTERS (template 1.0, DECISIONS #278, `docs/TEMPLATE_1_0.md` §6). An identity was a
//! token file on one machine; now a person may SIGN IN (SpacetimeAuth: Discord, Google, an email link),
//! and the module makes them an ACCOUNT the first time. The same sign-in on another machine is the same
//! identity, so the same account, with nothing to do. Another way in (a guest's machine; Steam later) is
//! joined by a LINK CODE: shown on a signed-in machine, typed on the other. An account holds its
//! CHARACTERS (`foundation.characters_per_account`); each is a player entity that outlives every
//! connection. Whoever connects last plays it: an older connection of the account lets go.
//!
//! WHICH SIGN-INS COUNT. SpacetimeDB accepts any issuer's token (a self-hosted server fetches the
//! issuer's keys), so anyone can connect with a token they minted themselves. Only an issuer in
//! `login_issuer` makes an account: the game's (`shared/game.json` `sign_in`, SpacetimeAuth by default),
//! with its client id as the audience, and any an admin trusts (`trust_issuer`: the suites' local test
//! issuer). Any other token plays as a guest, when the game allows guests (`foundation.guests_allowed`).

use super::*;

include!(concat!(env!("OUT_DIR"), "/sign_in.rs"));

/// How an identity came to be an account's: its own sign-in (a trusted token), or a link code.
pub const LOGIN_SIGN_IN: u8 = 1;
pub const LOGIN_LINKED: u8 = 2;

/// A link code: 8 of these (no 0/O, 1/I/L), made by the signed-in client's own random source.
pub const LINK_CODE_LEN: usize = 8;
pub const LINK_ALPHABET: &str = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/// A sign-in service whose tokens make accounts. Private: who is trusted is the admin's business.
#[table(accessor = login_issuer)]
pub struct LoginIssuer {
    #[primary_key]
    pub issuer: String,
    /// This game's client id there: a token must name it. Empty: any.
    pub audience: String,
    pub name: String,
}

/// A person, however many machines and sign-ins they have. Private: a client knows its account by its
/// `player` row and its `account_login`.
#[table(accessor = account)]
pub struct Account {
    #[primary_key]
    #[auto_inc]
    pub account_id: u64,
    pub created: Timestamp,
}

/// One way in to an account: an identity (a sign-in's, or a machine's joined by a link code).
#[table(accessor = account_login, public)]
pub struct AccountLogin {
    #[primary_key]
    pub identity: Identity,
    #[index(btree)]
    pub account_id: u64,
    /// `LOGIN_SIGN_IN` or `LOGIN_LINKED`.
    pub method: u8,
    /// The sign-in service it came from (empty for a linked machine's token file).
    pub issuer: String,
    pub linked_at: Timestamp,
}

/// One of an account's characters: a player entity that outlives the connection. Its name is kept here
/// too, so a character nobody is playing still holds its name.
#[table(accessor = account_character, public)]
pub struct AccountCharacter {
    #[primary_key]
    pub entity_id: u64,
    #[index(btree)]
    pub account_id: u64,
    pub name: String,
    pub created: Timestamp,
}

/// A link code, for `foundation.link_code_s` (10 minutes). Its maker alone is sent it.
#[table(accessor = link_code, public)]
pub struct LinkCode {
    #[primary_key]
    pub code: String,
    #[unique]
    pub maker: Identity,
    pub account_id: u64,
    pub until: Timestamp,
}

/// Each sees their own sign-in, their account's characters (through their `player` row: a filter may
/// join only a table that has no filter of its own, or the server refuses every subscription to it), and
/// the code they made.
#[client_visibility_filter]
pub(crate) const ACCOUNT_LOGIN_MINE: Filter = Filter::Sql("SELECT * FROM account_login WHERE identity = :sender");
#[client_visibility_filter]
pub(crate) const ACCOUNT_CHARACTER_MINE: Filter = Filter::Sql(
    "SELECT c.* FROM account_character c JOIN player p ON c.account_id = p.account_id WHERE p.identity = :sender",
);
#[client_visibility_filter]
pub(crate) const LINK_CODE_MINE: Filter = Filter::Sql("SELECT * FROM link_code WHERE maker = :sender");

/// The game's own sign-in service is always trusted, as its config says (run on every connect: a
/// republish does not run `init`).
pub(crate) fn sync_issuers(ctx: &ReducerContext) {
    let row = LoginIssuer { issuer: SIGN_IN_ISSUER.to_string(), audience: SIGN_IN_AUDIENCE.to_string(), name: "the game's sign-in".into() };
    match ctx.db.login_issuer().issuer().find(row.issuer.clone()) {
        None => {
            ctx.db.login_issuer().insert(row);
        }
        Some(old) if old.audience != row.audience => {
            ctx.db.login_issuer().issuer().update(row);
        }
        Some(_) => {}
    }
}

/// The sign-in service the sender's token is from, when it is one this game trusts (and names this
/// game's client id, when it has one).
pub fn trusted_sign_in(ctx: &ReducerContext) -> Option<String> {
    let jwt = ctx.sender_auth().jwt()?;
    let row = ctx.db.login_issuer().issuer().find(jwt.issuer().to_string())?;
    if !row.audience.is_empty() && !jwt.audience().iter().any(|a| *a == row.audience) {
        return None;
    }
    Some(row.issuer)
}

/// The account an identity is a way in to, if any.
pub fn account_of(ctx: &ReducerContext, identity: Identity) -> Option<u64> {
    ctx.db.account_login().identity().find(identity).map(|l| l.account_id)
}

/// The sender's account, made on their first trusted sign-in ("if they have not played before, it makes
/// one for them"). None: a guest.
pub(crate) fn account_of_sender(ctx: &ReducerContext) -> Option<u64> {
    if let Some(a) = account_of(ctx, ctx.sender()) {
        return Some(a);
    }
    let issuer = trusted_sign_in(ctx)?;
    let acc = ctx.db.account().insert(Account { account_id: 0, created: ctx.timestamp });
    ctx.db.account_login().insert(AccountLogin {
        identity: ctx.sender(),
        account_id: acc.account_id,
        method: LOGIN_SIGN_IN,
        issuer,
        linked_at: ctx.timestamp,
    });
    log::info!("a new account {} (first sign-in)", acc.account_id);
    Some(acc.account_id)
}

/// An account's characters, oldest first.
pub fn characters_of(ctx: &ReducerContext, account_id: u64) -> Vec<AccountCharacter> {
    let mut out: Vec<AccountCharacter> = ctx.db.account_character().account_id().filter(account_id).collect();
    out.sort_by_key(|c| c.entity_id);
    out
}

/// How many characters an account may have (`foundation.characters_per_account`, at least 1).
pub fn characters_allowed(ctx: &ReducerContext) -> usize {
    hot_number(ctx, crate::hot::foundation::CHARACTERS_PER_ACCOUNT).max(1.0) as usize
}

/// Whether someone who has not signed in may play (`foundation.guests_allowed`).
pub fn guests_allowed(ctx: &ReducerContext) -> bool {
    hot_number(ctx, crate::hot::foundation::GUESTS_ALLOWED) >= 0.5
}

/// The character an account's sign-in comes back to: the one played last (its player row's), else the
/// newest.
fn last_played(ctx: &ReducerContext, account_id: u64) -> Option<u64> {
    let chars = characters_of(ctx, account_id);
    chars.iter()
        .filter_map(|c| ctx.db.player().entity_id().find(c.entity_id).map(|p| (p.left_at, c.entity_id)))
        .max_by_key(|(at, _)| *at)
        .map(|(_, e)| e)
        .or_else(|| chars.last().map(|c| c.entity_id))
}

/// `identity` plays `entity_id` from now on: whoever held it lets go (signed in elsewhere: their client
/// sees its player row go), and what `identity` played before is parked. The character comes back where
/// it stood.
pub(crate) fn take_character(ctx: &ReducerContext, identity: Identity, entity_id: u64) {
    if let Some(holder) = ctx.db.player().entity_id().find(entity_id) {
        if holder.identity == identity {
            return;
        }
        log::info!("character {entity_id} moves from one sign-in to another (signed in elsewhere)");
        ctx.db.player().identity().delete(holder.identity);
    }
    if let Some(mine) = ctx.db.player().identity().find(identity) {
        park(ctx, mine.entity_id);
        ctx.db.player().identity().delete(identity);
    }
    let listing = ctx.db.account_character().entity_id().find(entity_id);
    let name = listing.as_ref().map(|c| c.name.clone()).unwrap_or_default();
    ctx.db.player().insert(Player {
        identity,
        entity_id,
        name,
        online: true,
        left_at: ctx.timestamp,
        connection_id: ctx.connection_id(),
        account_id: listing.map(|c| c.account_id).or_else(|| account_of(ctx, identity)).unwrap_or(0),
    });
    unpark(ctx, entity_id);
}

/// A NEW SIGNED-IN CONNECTION, from `client_connected`: an account with characters plays its last one;
/// Some(true) when one was taken, Some(false) when the account has none yet (a new player is made and
/// listed), None for a guest.
pub(crate) fn connect_account(ctx: &ReducerContext) -> Option<bool> {
    let acc = account_of_sender(ctx)?;
    match last_played(ctx, acc) {
        Some(e) => {
            take_character(ctx, ctx.sender(), e);
            Some(true)
        }
        None => Some(false),
    }
}

/// List `entity_id` (just made for `identity`) as one of its account's characters.
pub(crate) fn list_character(ctx: &ReducerContext, account_id: u64, entity_id: u64, name: &str) {
    if ctx.db.account_character().entity_id().find(entity_id).is_none() {
        ctx.db.account_character().insert(AccountCharacter {
            entity_id,
            account_id,
            name: name.to_string(),
            created: ctx.timestamp,
        });
    }
}

/// A character's name changed (`set_player_name`): its listing keeps it.
pub(crate) fn rename_character(ctx: &ReducerContext, entity_id: u64, name: &str) {
    if let Some(c) = ctx.db.account_character().entity_id().find(entity_id) {
        ctx.db.account_character().entity_id().update(AccountCharacter { name: name.to_string(), ..c });
    }
}

/// Whether a character other than `except` holds `name` (ignoring case): an unplayed character keeps its
/// name too.
pub fn character_name_taken(ctx: &ReducerContext, name: &str, except: u64) -> Option<u64> {
    let want = name.to_lowercase();
    ctx.db.account_character().iter()
        .find(|c| c.entity_id != except && !c.name.is_empty() && c.name.to_lowercase() == want)
        .map(|c| c.entity_id)
}

/// MAKE A LINK CODE (signed in): `code` is the client's own random choice of `LINK_CODE_LEN` from
/// `LINK_ALPHABET` (the module's random source is seeded from the clock, so it cannot make a secret).
/// One per sign-in at a time: a new one replaces it. Good for `foundation.link_code_s`.
#[reducer]
pub fn make_link_code(ctx: &ReducerContext, code: String) -> Result<(), String> {
    let acc = account_of(ctx, ctx.sender()).ok_or("make_link_code: sign in first")?;
    let code = code.trim().to_uppercase();
    if code.chars().count() != LINK_CODE_LEN || !code.chars().all(|c| LINK_ALPHABET.contains(c)) {
        return Err(format!("make_link_code: a code is {LINK_CODE_LEN} of {LINK_ALPHABET}"));
    }
    if let Some(mine) = ctx.db.player().identity().find(ctx.sender()) {
        spend_rate(ctx, mine.entity_id, "make_link_code")?;
    }
    ctx.db.link_code().maker().delete(ctx.sender());
    if ctx.db.link_code().code().find(code.clone()).is_some() {
        return Err("make_link_code: that code is in use; make another".into());
    }
    let secs = hot_number(ctx, crate::hot::foundation::LINK_CODE_S).max(10.0);
    ctx.db.link_code().insert(LinkCode {
        code,
        maker: ctx.sender(),
        account_id: acc,
        until: ctx.timestamp + TimeDuration::from_micros((secs * 1_000_000.0) as i64),
    });
    Ok(())
}

/// USE A LINK CODE: this identity becomes a way in to the code's account, and plays its last character.
/// The character it played as a guest joins the account when there is room, else it is put away
/// (parked) and kept. Rate-limited hard: a code is guessed one try at a time.
#[reducer]
pub fn use_link_code(ctx: &ReducerContext, code: String) -> Result<(), String> {
    let mine = ctx.db.player().identity().find(ctx.sender());
    if let Some(p) = &mine {
        spend_rate(ctx, p.entity_id, "use_link_code")?;
    }
    if account_of(ctx, ctx.sender()).is_some() {
        return Err("use_link_code: this sign-in is already an account's".into());
    }
    let code = code.trim().to_uppercase();
    let row = ctx.db.link_code().code().find(code.clone()).ok_or("use_link_code: no such code")?;
    if row.until < ctx.timestamp {
        ctx.db.link_code().code().delete(code);
        return Err("use_link_code: that code has run out; make another".into());
    }
    ctx.db.link_code().code().delete(code);
    ctx.db.account_login().insert(AccountLogin {
        identity: ctx.sender(),
        account_id: row.account_id,
        method: LOGIN_LINKED,
        issuer: ctx.sender_auth().jwt().map(|j| j.issuer().to_string()).unwrap_or_default(),
        linked_at: ctx.timestamp,
    });
    if let Some(p) = mine {
        let listed = ctx.db.account_character().entity_id().find(p.entity_id).is_some();
        if !listed && characters_of(ctx, row.account_id).len() < characters_allowed(ctx) {
            list_character(ctx, row.account_id, p.entity_id, &p.name);
        }
        ctx.db.player().identity().update(Player { account_id: row.account_id, ..p });
    }
    if let Some(e) = last_played_other(ctx, row.account_id, mine_entity(ctx)) {
        take_character(ctx, ctx.sender(), e);
    }
    log::info!("an identity joined account {} by a link code", row.account_id);
    Ok(())
}

fn mine_entity(ctx: &ReducerContext) -> u64 {
    ctx.db.player().identity().find(ctx.sender()).map(|p| p.entity_id).unwrap_or(0)
}

/// The account's character played last other than `except` (the one just joined), if any.
fn last_played_other(ctx: &ReducerContext, account_id: u64, except: u64) -> Option<u64> {
    let chars: Vec<AccountCharacter> = characters_of(ctx, account_id).into_iter().filter(|c| c.entity_id != except).collect();
    chars.iter()
        .filter_map(|c| ctx.db.player().entity_id().find(c.entity_id).map(|p| (p.left_at, c.entity_id)))
        .max_by_key(|(at, _)| *at)
        .map(|(_, e)| e)
        .or_else(|| chars.last().map(|c| c.entity_id))
}

/// MAKE ANOTHER CHARACTER (signed in, under `foundation.characters_per_account`) and play it; the one
/// played until now is put away where it stood.
#[reducer]
pub fn new_character(ctx: &ReducerContext) -> Result<(), String> {
    let acc = account_of(ctx, ctx.sender()).ok_or("new_character: sign in first")?;
    if let Some(p) = ctx.db.player().identity().find(ctx.sender()) {
        spend_rate(ctx, p.entity_id, "new_character")?;
    }
    let have = characters_of(ctx, acc).len();
    if have >= characters_allowed(ctx) {
        return Err(format!("new_character: an account has at most {} characters", characters_allowed(ctx)));
    }
    let entity_id = new_player_entity(ctx);
    list_character(ctx, acc, entity_id, "");
    take_character(ctx, ctx.sender(), entity_id);
    player_arrived(ctx, entity_id);
    crate::game::on_player_created(ctx, entity_id);
    Ok(())
}

/// PLAY ANOTHER OF YOUR CHARACTERS; the one played until now is put away where it stood.
#[reducer]
pub fn play_character(ctx: &ReducerContext, entity_id: u64) -> Result<(), String> {
    let acc = account_of(ctx, ctx.sender()).ok_or("play_character: sign in first")?;
    if let Some(p) = ctx.db.player().identity().find(ctx.sender()) {
        spend_rate(ctx, p.entity_id, "play_character")?;
    }
    let c = ctx.db.account_character().entity_id().find(entity_id).ok_or("play_character: no such character")?;
    if c.account_id != acc {
        return Err("play_character: not one of your characters".into());
    }
    take_character(ctx, ctx.sender(), entity_id);
    player_arrived(ctx, entity_id);
    crate::game::on_player_returned(ctx, entity_id);
    Ok(())
}

/// Trust another sign-in service's tokens to make accounts (admin). `audience`: this game's client id
/// there (empty: any).
#[reducer]
pub fn trust_issuer(ctx: &ReducerContext, issuer: String, audience: String, name: String) -> Result<(), String> {
    require_admin(ctx)?;
    if issuer.is_empty() || issuer.len() > 256 {
        return Err("trust_issuer: an issuer is an address of at most 256 bytes".into());
    }
    let row = LoginIssuer { issuer, audience, name };
    if ctx.db.login_issuer().issuer().find(row.issuer.clone()).is_some() {
        ctx.db.login_issuer().issuer().update(row);
    } else {
        ctx.db.login_issuer().insert(row);
    }
    Ok(())
}

/// Stop trusting a sign-in service (admin). Its accounts stay; new tokens from it are guests.
#[reducer]
pub fn distrust_issuer(ctx: &ReducerContext, issuer: String) -> Result<(), String> {
    require_admin(ctx)?;
    ctx.db.login_issuer().issuer().delete(issuer);
    Ok(())
}

/// Drop link codes past their time (the module's 1 Hz prune).
pub(crate) fn prune_link_codes(ctx: &ReducerContext) {
    let old: Vec<String> = ctx.db.link_code().iter().filter(|c| c.until < ctx.timestamp).map(|c| c.code).collect();
    for c in old {
        ctx.db.link_code().code().delete(c);
    }
}

/// PARK THE OFFLINE (the 1 Hz prune): a player offline longer than `foundation.park_offline_s` is put
/// away where they stood (0: never, every game before 1.0's way: they stay, hidden).
pub(crate) fn park_offline(ctx: &ReducerContext) {
    let secs = hot_number(ctx, crate::hot::foundation::PARK_OFFLINE_S);
    if secs <= 0.0 {
        return;
    }
    let cutoff = ctx.timestamp - TimeDuration::from_micros((secs * 1_000_000.0) as i64);
    let due: Vec<u64> = ctx.db.player().iter().filter(|p| !p.online && p.left_at < cutoff).map(|p| p.entity_id).collect();
    for e in due {
        park(ctx, e);
    }
}
