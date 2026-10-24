# Handoff — UMF Template, 2026-10-23

## Where it stands
THE TEMPLATE 1.0 is BUILT here and NOT shipped (`docs/TEMPLATE_1_0.md`, DECISIONS #278-#281; CHANGELOG
1.0.0). Nothing committed (Luke commits). `umf-template` was published `--fresh --codegen` with Luke's
say-so (its greybox data wiped); no game's database touched. The full sweep, all green: cargo test,
unit 2139/0, content 18, integration 642, e2e 11, multiclient 25, accounts 65, ring 15, sidecar 13, connect
95, remote 7, press 7, playtest 41, bodies 10, hot rules 12, telemetry 21, genres 5, export 32.

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
1. Luke reviews and commits; then THE SHIP (his say): `bash "../ship_template.sh" "1.0.0: cells,
   streaming, accounts"`. All four games take their one wipe together (his call). Each game first
   commits (Regent's Rule has steps 17-21 uncommitted), then after the pull: add `"compat": 2` to its own
   `shared/game.json` (merge=ours: it does not arrive), `tools\publish.cmd --fresh --codegen` (wipes that
   game's database: Luke's say-so at the ship), run its suites. Fishing: its
   `game/fishing/tests/suites/fishing_interest.gd` asserts the old query strings (lines 111, 121, 154:
   cell tables now end `AND chunk != 4294967295`).
2. Regent's Rule, in its own session after the pull: `NetConfig.interest = RING` in its net config, the
   hot-rule overrides `characters_per_account` 3 and `park_offline_s` 30, its own placed tables
   (`cell_tables`/`follow_tables`, `on_place_changed`), its glade as a streamed level when it grows.
3. When Luke makes the Maincloud login: HANDBOOK, Accounts, "Setting up SpacetimeAuth"; then a real
   sign-in by hand, measuring the token's lifetime and checking the 127.0.0.1 redirect (§2 of the plan).

## Waiting on Luke
- The commit, and the go for the ship (and with it each game's wipe).
- The Maincloud login and SpacetimeAuth project (later, by his choice); which providers' apps to make.
- Passwords stay off (his call); revisit after the playtests or if SpacetimeAuth adds them.

## Watch out
- The server caches a sign-in service's keys for minutes: a test issuer with a NEW key at the same
  address is refused (InvalidSignature) until it looks again. The suite keeps its keys in
  `build/test_issuer/`; do not delete them between runs.
- `spacetime subscribe --anonymous` is the way to see what a real client is refused: the owner (the CLI)
  sees through every row filter.
- Not built: refreshing a sign-in's token before a reconnect (an expired token fails the reconnect: sign
  in again); a parked spot no longer standable; the 9-cells-vs-OR measurement (300-bot harness).
- A sign-in through the browser waits up to 5 minutes; the connect screen's clock waits with it.
