# Netcode: entities, subscriptions, connecting
How entities are shaped and bound, what the client subscribes to, and how it connects. Moved verbatim from AGENTS.md (REVIEW 0.23.1 C1); the DECISIONS rows in each heading say why.

## ENTITY CONVENTIONS (DECISIONS #68, #69)
- An entity body's origin is at its FEET. `pos.y == ground_y` means standing on the ground; a
  collision shape centred on the origin puts the body half inside the floor.
- Entity bodies: `collision_layer = SpaceTimeEntity.ENTITY_MASK`, `collision_mask =
  SpaceTimeEntity.WORLD_MASK`. Level geometry stays on layer 1. Entities never collide with each other.
- Bodies the referee flies (DECISIONS #246) are on layer 20 and meet layer 1, each other and layer 21 (the
  referee's stand-ins for people); a body's entity node on a client has no collision at all. Layers 5-19
  are left to the games (Fowl Play's hens' kin layer is 6).
- An entity still binding is handed its rows directly (`EntityRegistry.await_rows`, DECISIONS #247); only an
  entity not yet built has its rows buffered.
- A component whose table may legitimately have NO rows for an entity (a collection) lists it in
  `optional_tables()` as well as `required_tables()`, or every spawn waits out `bind_timeout_sec`.
- `InputFrame` and `movement_state` changed shape (`epoch`, `correction_epoch`, `move_state`,
  `dash`): after changing either, republish and regenerate bindings, then `--import` so new
  class_names register.

## SUBSCRIPTIONS (DECISIONS #104, #105)
- `InterestManager` is the ONLY place subscription SQL is built. A component that needs a table
  adds it to `NetConfig.core_tables`; nothing else writes a query. A game's `.tres` NetConfig
  lists its own copy: a new FOUNDATION table goes in it too (`fishing_net_config.tres`), and the
  interest suite checks every game scene's list against its entities' components (#160).
- A table is filtered `WHERE world_id = N` only if it HAS that column and its rows belong to one
  world. `WORLD_TABLES` is that list; the test asserts every shipped table has been decided.
- Switching world subscribes the new set BEFORE dropping the old one. Never the other way: the
  spawner cannot tell a torn-down cache from a reconnect.
- Never connect a lambda that closes over an SDK handle to that handle's own signal (#105).

## CELLS AND THE RING (template 1.0, DECISIONS #278, #279)
- Every row of a placed thing carries `chunk` (`server/src/cell.rs`, the client's `Cells`). Write a
  `movement_state` row ONLY through `module/place.rs` (`write_movement`, `insert_movement`; `park`,
  `unpark`): they recut the cell and move every row that follows the entity. `run_tests.sh` lints it.
- A new foundation table that describes a placed entity: give it `world_id` and `chunk` (indexed),
  set the chunk from `chunk_of_entity` (an event: `cell::chunk_of(pos)`), add it to `follow` if it
  follows the entity, and to `InterestManager.CELL_TABLES` (and `FOLLOW_TABLES`). A genre's: its
  `NetConfig.cell_tables` / `follow_tables`, and its rows through the `on_place_changed` hook.
- RING interest is three sets: the world's, our own rows (`own#`), the cells (`cells#`). Never put a
  row in two queries of one set (our own rows were deleted once that way, #279), and swap a set only
  with the overlap (the new one applied before the old is dropped).
- A parked entity's rows are in the NOWHERE cell (`u32::MAX`): every query of a cell table skips it.
- A ROW FILTER may join only a table with no filter of its own, on indexed columns (#281); check a new
  one with `spacetime subscribe --anonymous <db> "SELECT * FROM <table>" --num-updates 0` (the owner
  sees through filters, so the CLI's own calls never find it).

## WHO IS HERE, AND WHO THEY ARE (DECISIONS #202)
- A player who disconnects LEAVES THE WORLD: `PresenceComponent` (in `foundation/entities/player.tscn`,
  so every genre's player has it) hides the body and drops its collision after the grace the hot rule
  `foundation.offline_linger_s` gives, and brings it back when `player.online` is true again. The
  rows stay (progress, catches, standings). An entity with no player row (an NPC) is always present.
  The server refuses to let anyone `interact` with an offline player. Anything new that targets a
  player (an ability, a carry, an NPC's chase) checks `player.online` the same way.
- NAMES ARE UNIQUE, ignoring case and spacing: `set_player_name` refuses a name another identity
  holds; a player who shared a name with an OLDER player before this rule becomes "<name> 2" on
  their next connect (the first holder keeps it). A refused name is said on screen (`Notices`).
- An identity is a TOKEN FILE on the machine, not a name: each editor slot, each exported copy and
  each `--token=` has its own, by design: a GUEST. A SIGN-IN (template 1.0, #280) is an identity made
  from the sign-in service's token, the same on every machine; `module/accounts.rs` makes it an
  account the first time. Only the game's issuer (`shared/game.json` `sign_in`) with its client id as
  the audience, or one `trust_issuer` added, counts: SpacetimeDB accepts any issuer's token.
- A character is a `player` entity listed in `account_character`; `take_character` is the only way one
  changes hands (it parks what the identity played). The newest connection plays: check
  `player.connection_id` in a reducer that drives the character (as `submit_input` does).
- `Notices` (Boot adds one to every game scene, outside the HUD) shows every
  `SignalBus.notification_requested` briefly at the top of the screen.

## CONNECTING (DECISIONS #122-#126, #148)
- The connect screen greets whenever there is a display; headless processes connect on their own.
  Auto-connect and `--host=` press the screen's own Connect, so timeouts and explanations apply.
- `ConnectSettings` is one profile per IDENTITY, and only the screen writes it. Flags override a
  run; they are never remembered. Under a test suite (UMF_DB) the profile carries the database's name
  (`connect_dev1.umf-test.cfg`, #179): the e2e client runs as Luke's editor slot 1, and read his look.
- A terminal DISCONNECTED despawns the world (`EntitySpawner.despawn_all`). A transient drop does not.
- `SpaceTimeSync.last_disconnect_requested` says whether the player left or was dropped.
- `_sdk_reset_token_fetch` works around two SDK faults in the identity request (#125). A harness
  that tests connecting must delete the identity TOKEN too, or the faulty path never runs.
- MouseCapture takes the cursor back only on a click NO UI consumed (`_unhandled_input`). A genre
  that acts on the left button ignores clicks while `is_captured()` is false.
- FULLSCREEN is `WindowMode` (#148): F11 / Alt+Enter, read by the PauseMenu whether it is open or
  not, and the menu's button. In the editor's game view the window is not the game's: the button
  is greyed and the view's ⋮ → Stretch to Fit is the answer. `tests/render_test.sh` proves the
  real toggle; a headless run cannot.
