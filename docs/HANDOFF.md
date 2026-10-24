# Handoff — UMF Template, 2026-10-24

## Where it stands
1.0.0 and 1.0.1 SHIPPED to all four games (2026-10-24, Luke's go: `ship_template.sh`; 1.0.1 only makes the
suites' sign-in keys one per machine, `~/.umf_test_issuer/`). Each game: `compat` 2, its database wiped and
republished `--fresh --codegen`, committed and pushed. Template sweep all green (below); the games' results
are in each game's HANDOFF and this session's closing message.
Template sweep: cargo test, unit 2139/0, content 18, integration 642, e2e 11, multiclient 25, accounts 65,
ring 15, sidecar 13, connect 95, remote 7, press 7, playtest 41, bodies 10, hot rules 12, telemetry 21,
genres 5, export 32.

## This session
- The design pass with Luke: `docs/TEMPLATE_1_0.md` (§2 what was checked: SpacetimeAuth's methods and
  endpoints, a self-hosted server validating its tokens, the subscription grammar; §10 his calls). #278.
- Cells (#279): `server/src/cell.rs`, `module/place.rs` (the only movement writes; a lint), `chunk` on
  fifteen tables, `shared/rules.json` `cells`, the genre hook `on_place_changed`, the client's `Cells`.
- Ring interest (#279): `InterestManager` RING mode, three sets (world, own rows, cells), hysteresis;
  `tests/ring_test.sh`. Streaming: `LevelInfo.streamed`, `LevelCells` (the bake's cut), `LevelStreamer`.
- Accounts (#280): `module/accounts.rs`, `player` reshaped (`left_at`, `connection_id`, `account_id`),
  parking (`place::park`), four hot rules, `SignIn`, Boot's sign-in flags, the connect screen's Sign in,
  the Escape menu's `AccountPage`; `tests/accounts_test.sh` with `tests/lib/oidc_issuer.py`.
- #281: a row filter may join only an unfiltered table on indexed columns; `ground_item.owner_id`
  indexed (its whole-table query was refused for non-owners; the games' filtered one was fine).
- `compat` 2 in the template's `shared/game.json`. HANDBOOK (Accounts, A big world, the suites),
  netcode/compatibility rules, file map, AGENTS verify loop, ROADMAP, FOUNDATION_SYSTEMS.

## Next, in order
1. Regent's Rule, in its own session: `NetConfig.interest = RING`, the overrides `characters_per_account` 3
   and `park_offline_s` 30, its own placed tables (`cell_tables`/`follow_tables`, `on_place_changed`), its
   glade as a streamed level when it grows past 100 m (today the whole glade is inside any 3 x 3 ring).
2. When Luke makes the Maincloud login: HANDBOOK, Accounts, "Setting up SpacetimeAuth"; a real sign-in by
   hand, measuring the token's lifetime (then refresh before a reconnect) and checking the 127.0.0.1 redirect.
3. New builds for friends of every game (`tools
elease.cmd`): builds from before 1.0 are refused.
4. The 300-bot harness (Regent's): the cell size and nine cells vs one OR'd ring, measured.

## Waiting on Luke
- The Maincloud login and SpacetimeAuth project (later, by his choice); which providers' apps to make.
- Passwords stay off (his call); revisit after the playtests or if SpacetimeAuth adds them.

## Watch out
- The server caches a sign-in service's keys for minutes: a test issuer with a NEW key at the same
  address is refused (InvalidSignature) until it looks again. The suite keeps its keys in
  `~/.umf_test_issuer/` (one per machine, every game's copy of the suite shares it); do not delete it.
- `spacetime subscribe --anonymous` is the way to see what a real client is refused: the owner (the CLI)
  sees through every row filter.
- Not built: refreshing a sign-in's token before a reconnect (an expired token fails the reconnect: sign
  in again); a parked spot no longer standable; the 9-cells-vs-OR measurement (300-bot harness).
- A sign-in through the browser waits up to 5 minutes; the connect screen's clock waits with it.
- In the games, the template's own suites are not all theirs: DiscGolf's integration run fails 12 checks
  with or without 1.0 (its round plan and level are not the template's: the lobby, interact, holds, match,
  two Tier A lines that vary); Fowl Play's e2e cannot spawn its player (the scene knows only kind 0, and
  every Fowl Play player is a hen, kind 100). Each game's own playtests are its client proof.
