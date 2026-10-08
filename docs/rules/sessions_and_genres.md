# Sessions, matches, the lobby, genres and levels
Round phases, matches, the lobby screen, standings, genres as switches, levels and their bakes. Moved verbatim from AGENTS.md (REVIEW 0.23.1 C1); the DECISIONS rows in each heading say why.

## MATCHES AND THE LOBBY SCREEN (DECISIONS #182, #183)
- SHOW `get_match_round()` (server: `module::match_round`), never `session.round`: that one keeps
  counting across matches because catches and standings are filed under it. Never restart it.
- A world with no player online for `end_after_empty_s` (rules.json `sessions[].match`) ends its
  match (`begin_match`). Within that grace the phase machine runs as before: the integration suite
  relies on it, since nobody is online between its command-line calls.
- A match's first lobby is HELD (phase_ends_at a year off) until everyone is ready. A client
  shows "waiting" for a held phase (`SessionComponent.is_waiting()`), never the seconds.
- A page over the game holds the player still (`LocalInputComponent.hold_still`) and the cursor
  free (`MouseCapture.hold_free`). Never `MouseCapture.release()` for a page: that is the player's
  Escape, and the Escape menu opens for it.
- The lobby screen shows only with a window (or `--lobby-screen`); `--autoconnect`/`--host=` join a
  match under way without asking, and skip the splash (`--no-splash` too).

## GENRES, LOBBY, LEVELS (DECISIONS #173-#175)
- A GENRE NEVER EDITS THE FOUNDATION, and now it is also a SWITCH: everything of fishing's on the
  server sits behind `#[cfg(genre_fishing)]` (its module in `game/`, its rules in `genre/`, its
  native test files with `#![cfg(genre_fishing)]`). A foundation test that needs a genre's rules is
  gated the same way. `tests/genres_test.sh` is what proves the foundation builds without it.
- A genre's client half is its `genre.tres`: its definitions, tables (and per-world tables) and
  scenes. A game scene sets Boot's `load_genres`; its NetConfig holds only the foundation's tables
  (defaults). The interest suite merges the genres' tables before checking a scene.
- A new genre kind number goes in its `Claims`, never just in code: `init` checks them.
- THE LOBBY counts ONLINE PLAYERS only. An NPC member (the rival) is never waited for.
- A member's lobby row is made where it is needed if missing (`ensure_lobby_member`, #184): worlds
  republished without a wipe hold members from before lobby rows existed. A new per-member table
  must do the same for what a long-lived world already holds; a fresh-publish suite never sees it.
- A WORLD'S LEVEL IS `world_level` (foundation). A genre reads it (`world_level_of`), and sets up
  per level in `on_level_changed`, never by writing its own record of the level as the truth.
- A LEVEL'S BAKE IS GENERATED FROM ITS SCENE: never hand-edit `shared/world/<level>.json`. The
  `levels` suite re-bakes the meadow and fails when the committed bake is stale. Level ids are
  unique (build.rs refuses a repeat); 0 is the level-less greybox.

## STANDINGS AND ROUNDS (DECISIONS #127-#129)
- Standings are assembled from components (`FishingStandings.build`), never a table of their own.
  Members who are neither online nor scored are left off (CLI connections are members too).
- A row that was already true when an entity bound is history: announce only rows after bind.
- `SignalBus.session_phase_changed` comes from the LOCAL player's SessionComponent only.
