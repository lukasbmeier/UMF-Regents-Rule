# Template 1.0: chunks, a streamed world, accounts (the design pass, 2026-10-23)

AGREED with Luke 2026-10-23 (his calls: §10). BUILT the same day in the template (milestones B-G; A's
SpacetimeAuth half waits on Luke's Maincloud login): DECISIONS #279-#281, as built in §8. Asked for by Regent's Rule (`../Regents Rule/GAME.md`: `chunk`
on the existing positional tables in a 1.0 reshape, accounts through SpacetimeAuth, hosting on Luke's
machine then a VPS) as its M18 (interest by cell), M19 (streaming) and M23 (accounts and persistence).
Every game gets it; only the games that switch it on change how they play (§4, §6). When this doc and
`RULE_DESIGN.md` §5, §8, §11 differ, this doc wins once Luke has answered §10.

## 1. The shape in one paragraph
Every row that puts something in a world carries the 64 m CELL it is in (`chunk`, the index ground
items already use). A client in a big world subscribes only to the cells round it (3 x 3), swapping a
row of cells as it walks, and loads the level's scenery in a wider ring (5 x 5), so 300 players in one
database each receive about 30 neighbours rather than 300. A player signs in through SpacetimeAuth
(Discord, Google, an email link, Steam later; guests on a unique name where a game allows them) instead of being a token file on one machine: the same
person is the same ACCOUNT on any machine, an account holds its CHARACTERS, and a character logs back
in where it left. Adding `chunk` reshapes tables, which only a major version may do
(`docs/rules/compatibility.md`): 1.0 is that version. Every game's database is wiped once and builds
from before it stop connecting, with "your game is out of date" on the connect screen.

## 2. What was checked (2026-10-23), and what is still to check
Checked:
- **SpacetimeAuth's sign-in methods**: email magic link, Steam (session ticket), Google, GitHub,
  Discord, Twitch, Kick (its docs; beta). Each third-party method needs an app made in that
  provider's developer console (a client id and secret pasted into SpacetimeAuth's dashboard).
- **Its OIDC endpoints** (`https://auth.spacetimedb.com/oidc/.well-known/openid-configuration`): the
  authorization-code flow with PKCE (S256) for a public client (no secret in the game), refresh
  tokens (`offline_access`), and a grant `urn:spacetimeauth:steam-ticket` (Steam needs no bridge of
  ours). The ID token is an RS256 JWT with `sub`, `project_id`, `login_method`, `email`,
  `preferred_username`.
- **Where a project lives**: it is made from the dashboard of a module published on MAINCLOUD
  ("Use SpacetimeAuth"), but a project "is independent of a SpacetimeDB database and can be used by
  one or many databases". So Luke needs a Maincloud login and one module published there (any; it
  can be a stub) to own the project; the games themselves stay on his machine.
- **A self-hosted server accepts its tokens**: SpacetimeDB 2.10.1's standalone server
  (`crates/standalone/src/lib.rs` → `default_auth_environment` → `FullTokenValidator`) checks a token
  it did not sign by fetching the issuer's keys (`CachingOidcTokenValidator`, JWKS). Luke's machine
  (and later the VPS) needs outbound HTTPS to `auth.spacetimedb.com`, nothing else.
- **The consequence**: the server accepts ANY issuer's token, so anyone can mint their own and
  connect. The module itself must accept an account sign-in only from SpacetimeAuth's issuer with this
  game's client id as audience (`ctx.sender_auth().jwt()`: `issuer()`, `subject()`, `audience()`, in
  2.10.1). An identity is made from the issuer and the subject, so nobody can be someone else.
- **The same SpacetimeAuth user is the same identity on every machine**: signing in on a second
  machine with the same method needs no linking at all.
- **Subscriptions** (2.10): `WHERE` takes `AND`, `OR` and comparisons (no `IN`, no arithmetic); a
  query may join two tables on indexed columns.

Still to check, first thing in milestone A (§8): the ID token's lifetime; whether a SpacetimeAuth
client takes a loopback redirect (`http://127.0.0.1:<port>/callback`, the desktop way: the game opens
the browser and listens for the answer); whether Google and Discord with the same email are one
SpacetimeAuth user or two; how the server costs nine one-cell queries against one OR'd query.

## 3. Chunks: which rows know their cell (M18, the server)
- **The cell** is `ground::chunk_of` as ground items have it: 64 m squares, `(x cell + 512) * 1024 +
  (z cell + 512)`, a grid 65 km a side. The size is a number both sides compile in; changing it later
  means re-cutting every row, so it is chosen once (§10, question 1).
- **One place keeps it right**: whenever the module writes where an entity is (`tick_movement`, an
  authority's write, a teleport, a spawn, a carry), a helper compares the new cell with the row's
  and, only on a change, rewrites `chunk` on every chunked row of that entity in the same
  transaction. A moving player crosses a cell edge about every 10 s; the rewrite is a handful of rows
  beside 20 movement rows a second. A genre's own chunked tables join in through a hook
  (`on_chunk_changed`), as genres join everything else.
- **Which tables** (question 2):

| Table | Today | A: every row of a placed thing (recommended) | B: only rows with a position |
|---|---|---|---|
| `entity`, `movement_state`, `body_state` | world | chunk | chunk |
| `health_state`, `equip_state`, `appearance`, `status_state`, `attachment`, `resource_state`, `hold_progress` | world | chunk | joined to `entity`'s cell |
| `noise`, `body_contact`, `push`, `action_event`, `ground_item` (has it) | world | chunk | chunk |
| `chat_message`, `session*`, `lobby_member`, `world_level`, `world_config`, `hold_member` | world | stay world-wide | stay world-wide |
| `inventory_item`, `ability_state` (everyone's, today) | everyone | your own only (a query change, no reshape) | the same |

  A puts the cell on every row the client draws a placed thing from, so every subscription is a
  plain filter that the server shares between everyone in the same cells, and an entity walking out
  of view leaves in one transaction. It costs the rewrite above and one more column on seven tables.
  B writes less, but every one of those tables is subscribed through a join, which costs the server
  more on every change and is close to the side table Luke turned down on 2026-10-18.
- **What does not change**: the world's referee and a sidecar still take the whole world; a game
  that never switches on the ring (§4) sees `chunk` only as a column it ignores.

## 4. Interest: what a client receives (M18, the client)
- `NetConfig.interest`: `WORLD` (today: the whole world; the default, so every game plays as before)
  or `RING` (cells). Which games use the ring is question 3.
- **The ring**: the player's cell and the cells round it (`ring` 1 = 3 x 3), each cell its own
  subscription set (every chunked table, `WHERE world_id = W AND chunk = C`). Two clients in the same
  cell ask the same queries, which the server works out once for both. Crossing into a new cell
  subscribes the three new cells, and drops the three old ones only once the new ones have arrived
  (the overlap `InterestManager` already does for worlds, so nothing despawns and respawns). The
  centre moves only once the player is 4 m inside the new cell, so walking along an edge does not
  churn. One OR'd query for the whole ring is the fallback if nine sets measure worse (§2).
- **Your own rows always**: your own entity's rows by its id, whatever the ring says, so your own body
  never blinks out at an edge. Party frames across cells (Regent's M24) will be a set by entity ids
  in the same way.
- A spawned entity leaving the ring despawns as it does on leaving a world; entering, it spawns.

## 5. Streaming the level (M19, the client)
- The designer keeps ONE level scene. `LevelInfo` gains `streamed` (off: loaded whole, as today).
  Nodes under its `Cells` node (props, trees, buildings, `LevelPoint`s) are cut into one scene per
  cell by the bake (`tools/world/bake_level.gd` already walks the level); everything else (terrain,
  sky, water, a far mesh) is always there. Terrain3D draws its own distance detail, so the ground is
  not cut.
- `LevelStreamer` (beside `LevelLoader`) loads the cells in a 5 x 5 ring round the player on a thread
  and frees those beyond 7 x 7. The streamed ring is always wider than the subscribed one, so a
  neighbour is never drawn standing on scenery that is not loaded.
- The server, the referee and the sidecar keep the whole level (the bake's ground and walkable mask
  are one file, and they are not players). The editor shows the cell grid over the level, and the
  bake warns of a cell far heavier than the rest.

## 6. Accounts and characters (M23)
### 6.1 What is stored
- `account {account_id, created}`; `account_login {identity, account_id, method, linked_at}`: the
  sign-ins that are this account (SpacetimeAuth, Steam later, a device's token for a guest), so a
  new way in is a row, never a migration.
- `character {entity_id, account_id, name, created, last_seen}`: a character IS a player entity that
  outlives the connection. Names stay unique per game (#202), and belong to the character.
- `player` (who plays what now) gains the connection that plays it: a second login to the same
  character takes over, and the older client is told it was signed in elsewhere. This is a reshape,
  so it is folded into the one wipe.
- The editor's two instances, the suites, bots, the referee and sidecars keep their token files and
  their identities as today (#272); whether players may also play that way is question 6.

### 6.2 The flows
- **Signing in**: the connect screen's Sign in opens the browser on SpacetimeAuth's page (its look is
  set in SpacetimeAuth's dashboard), the game hears the answer on `127.0.0.1`, keeps the refresh token
  in its user folder and connects. Later launches sign in silently; Sign out is in the Escape menu.
- **A second machine**: the same method finds the same account; nothing to do.
- **Another way in** (Steam on the Mac, Discord on the PC; or a guest's character joining an
  account): a LINK CODE, shown on a signed-in machine for 10 minutes and typed on the other after it
  signs in its own way (question 7).
- **Steam, later**: GodotSteam's session ticket through SpacetimeAuth's Steam grant, linked as one
  more way in.
- **Admins**: by identity, as today; SpacetimeAuth's roles (an `admin` role in its dashboard) can add
  them later.
- **Tested without the internet**: the suites run a small local OIDC issuer (keys and signed tokens,
  Python's standard library) and the test database trusts it beside SpacetimeAuth, so sign-in, link
  codes, take-over and refusals (a foreign issuer, an old token) are proved end to end on every run.
  A real SpacetimeAuth sign-in is proved by hand once, with Luke.

### 6.3 Logging back in where you left (question 4)
- Today a player who disconnects stays in the world, hidden (#202), with every row kept. That is fine
  at 8 players and wrong at thousands of characters: every one would sit in some cell's rows.
- Proposed: **parking**. After `foundation.park_offline_s` (a hot rule; 0 = never, today's
  behaviour) an offline character's WORLD rows (`movement_state`, `health_state`, statuses...) are
  folded into `character_place {entity_id, world_id, pos, yaw, at}` plus what the genre's `park` hook
  keeps, and removed; signing in puts them back where it stood (or at the level's spawn if that spot
  is no longer standable). Everything keyed by the character and not a world row (its bag, skills,
  journal, standings) is never touched, so it simply persists.
- What else a character keeps (health, a resource, a status such as Weakened) is each game's call
  through the hook; the foundation keeps only the place.

### 6.4 Email and password (Luke, 2026-10-23: "type in their email and password and it signs in; if
they haven't played before it creates one ... reset as needed like most games"; else a username and
password as Titan Reach does)
SpacetimeAuth has NO password sign-in: its docs list the email link, Steam and the social providers,
and its OIDC configuration has no password grant (checked 2026-10-23). SpacetimeDB accepts any OIDC
provider whose issuer serves `/.well-known/openid-configuration` (the 2.10.1 server fetches exactly
that), so the choices are:

| | Email + password in the game | Reset | Discord / Google / Steam | Cost | What Luke runs |
|---|---|---|---|---|---|
| **1. SpacetimeAuth + our own passwords** | yes: the module keeps a salted hash per account; a new email makes the account | "Forgot": SpacetimeAuth's email link proves the address once, then a new password | all, through SpacetimeAuth | free | nothing new |
| **2. Firebase Auth** (Google) | yes: its REST API signs up and signs in from the game | Firebase sends the reset email | Google yes; Discord, Steam no (a small server of ours would mint tokens) | free to 50,000 players a month | a Google account and a Firebase project |
| **3. Auth0** | yes, through its password grant (a flow it discourages for new apps) | Auth0 sends the reset email | Google, GitHub yes; Discord through its marketplace (to check); Steam no | free to 25,000 players a month | an Auth0 account |
| **4. Keycloak** (open source) | yes | its own emails (needs a mail sender) | Google, GitHub yes; Discord, Steam through community add-ons | free | a Java service on his machine or the VPS, reachable over HTTPS from the internet; down means nobody signs in |
| **5. Our own usernames and passwords only** (Titan Reach) | yes, by username | none without an email service | none | free | nothing new |

Every choice needs TLS (`wss://`) on the game server before strangers play: a sign-in token or a
password crossing the internet unencrypted can be replayed. Friends over Tailscale are already
encrypted. Our own passwords (1, 5) also cost the module about 50 ms of hashing per sign-in, and the
module runs one reducer at a time: rare enough at a few sign-ins a minute, worth measuring at 300.
Recommended was 1. **Luke's call (2026-10-23): none of these for now.** "Let's just try SpacetimeAuth
without custom password handling, and for playtests we can just allow guests and map it to unique
usernames": SpacetimeAuth's methods only (its email link is the email sign-in), and guests are allowed
in playtests (Regent's included, by its per-game setting), each guest a machine's token file with a
unique name as today (#202). A guest's name is NOT a login: another machine plays that character only
after a sign-in and a link code. Revisit passwords if SpacetimeAuth adds them, or after the playtests.

## 7. The reshape and the version
- 1.0.0 with `shared/game.json` `"compat": 2`: older builds are refused before connecting, in words.
  Each game publishes `--fresh` once (its database wiped: progress, bags and names go), and friends
  download the new build. After 1.0 the add-only rule (rule 17) holds again until 2.0.
- Only what needs the reshape is folded in (`chunk`, the player's connection). Everything else in
  this doc is additions.

## 8. Milestones (each ends green; the version ships once, at the end, when Luke says)
| | Builds | Proves it |
|---|---|---|
| A | The checks in §2: a scratch SpacetimeAuth project (Luke makes the accounts), a desktop sign-in by hand against his local server; the subscription cost of nine cells vs one OR'd ring with 100 headless clients | a token from SpacetimeAuth connects to his machine; the numbers chosen by measurement |
| B | `chunk` on the tables (question 2) and the helper; a genre's hook | native tests; the integration suite walks an entity over an edge and every row follows (a table left out is caught) |
| C | `RING` interest, cell sets, the overlap, hysteresis, your own rows | unit; two real clients 200 m apart do not see each other, then walk into view and out (nothing respawns on the way) |
| D | Streaming: the bake cuts cells, `LevelStreamer` | a 16 x 16 cell test level walked edge to edge; cells load ahead and free behind; never a hole under the player |
| E | Accounts: the tables, sign-in, link codes, take-over, guests by rule | the local issuer suite: sign in, a second machine, a link, a foreign issuer refused, a guest |
| F | Parking and the place (question 4) | out and back: where you stood, bag kept; a parked character in no cell's rows |
| G | 1.0.0: compat 2, HANDBOOK, DECISIONS, CHANGELOG, the full sweep | every template suite green; an old build refused |

As built (2026-10-23): B-F and G in the template, each with its suites (#279, #280); A's sign-in half is
proved against the suites' own issuer, and a real SpacetimeAuth sign-in waits on Luke's Maincloud login
(HANDBOOK, Accounts: the steps). Differences from the plan: the ring is THREE sets (the world's, our own
rows, the cells), because a row in two queries of one set was deleted once; `account` is private and
characters are shown through `player.account_id`, because a row filter may not join a filtered table
(#281); parking keeps every row and moves it to a NOWHERE cell rather than folding the place into a
`character_place` table, so nothing a game keeps needs saving and restoring. Not built: refreshing a
sign-in's token before a reconnect (its lifetime is still to measure); a spot no longer standable on
coming back; the 9-cells-vs-OR measurement (with the 300-bot harness).

## 9. Each game's wipe (question 9)
`ship_template.sh` reaches Fishing (parked), Fowl Play, DiscGolf and Regent's Rule. Each game commits
first, pulls, publishes `--fresh --codegen`, runs its suites, and its friends re-download. A game
that stays on `WORLD` interest and allows guests plays exactly as before after its wipe.

## 10. Luke's calls (answered 2026-10-23 unless marked open)
1. Cell size and rings: **64 m, 3 x 3 subscribed, 5 x 5 streamed**.
2. Which tables gain `chunk`: **A**, every placed thing's row (§3).
3. The ring: **Regent's Rule only**; the match games keep `WORLD` interest.
4. Logging out: **parking** after a time offline (a hot rule; the match games 0, today's behaviour);
   what else a character keeps is each game's hook.
5. Sign-in methods: **Discord, the email link, Google; Steam later**; no passwords of our own for now
   (§6.4: email + password was asked for, SpacetimeAuth has none, and Luke chose to try SpacetimeAuth
   as it is).
6. Guests: **a setting per game**; during the playtests every game allows them, Regent's included,
   each with a unique name (a name is not a login).
7. Another way in: **a link code**.
8. The Maincloud login and the SpacetimeAuth project: **later**; B-F are built against the local test
   issuer, and a real sign-in is checked with Luke before the ship.
9. The wipes: **all four games at the 1.0 ship**.
10. Characters per account: **a game rule** (Regent's 3, the match games 1).
