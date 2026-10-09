# Compatibility: old clients on new servers

The owner's rule (2026-10-08): an exported build should keep working when the server is updated, so
friends re-download only for real changes (new art, new presentation, a deliberate break). An
occasional re-export is fine; a re-export for every server fix is not.

## Which way, and why
Old client → new server is the direction this architecture makes cheap. The server is the
authority, and SpacetimeDB already pushes schema changes to be additive: a table or reducer can be
added to a live database, but reshaping a table needs `--fresh`. New client → old server is not
attempted: a new client would ask for tables and reducers the old server never had.

## The rules, within a major version
1. **Add, never change.** New tables and new reducers are fine. Never add, remove or retype a column
   of an existing table, and never change an existing reducer's arguments.
2. **New data goes in a side table** keyed by `entity_id` (most of the foundation is built this way:
   `equip_state`, `appearance`, `fight_show`). An old client never subscribes to it.
3. **New arguments mean a new reducer** (`cast_v2`); the old one stays as a shim that fills in
   defaults, until the next major version.
4. **What a client simulates is part of its contract.** Movement speeds, a minigame's curves, a
   hook-set window: the client predicts with the numbers its build carries, and the server replays
   inputs against its own. Changing one breaks old clients quietly (constant corrections, fights
   graded differently). Until tunables are served by the server (CONTENT_TOOLING_SPEC §4, the
   `rules` table), retuning anything a client simulates is a major change.
5. **New content falls back.** An item, species or look an old client has no model for is drawn as
   a generic stand-in with the name from its row. It still plays; the new model needs an update.

## What enforces it (DECISIONS #198)
- **The contract, not the fingerprint.** Codegen writes `spacetime_bindings/schema_contract.json`
  beside the bindings (`SchemaContract`): every public table the bindings decode, with its row, and
  every reducer a client can call, with its arguments (types resolved, by name and shape). At
  connect the client fetches the server's schema and checks only that: extra tables and reducers
  are fine, a changed or missing one is refused with the reason ("the server's table 'x' has other
  columns"). The fingerprint is still shown, to tell versions apart; it no longer decides. A build
  from before #198 has no contract and still needs the exact fingerprint.
- **The compatibility generation.** `shared/game.json` `compat` (1 when absent). build.rs puts it
  in the schema as an empty reducer, `compat_generation_<N>`, so it is part of every contract: builds
  and servers of different generations refuse each other, both ways round, in those words. Bump it
  (add `"compat": 2`) for a deliberate break: a change to what clients simulate (rule 4), a reshaped
  table. Never for an addition.
- **Release snapshots.** `tools\release.cmd` (the way to make a build for friends) exports and tests
  both builds, saves the build's contract to `shared/compat/<database>/<fingerprint>.json`, and zips
  the client to `build/releases/`. Commit the snapshot. Exporting from the editor saves one too
  (`addons/umf_export`). The `version` unit suite then fails while any snapshot of the current
  generation cannot play on the current schema: a change that would strand a friend's build is
  caught before it is published.
- **A real old client.** `tests/export_test.sh` plays the build it just exported against servers
  built from the same source with `UMF_COMPAT_PROBE`: `add` (a new table and reducer: it must play)
  and `break` (the next generation: it must be refused before connecting).
- Negative-tested: with the contract check off, the unit suite, the connect playtest's older build
  and the export test's old client all fail.

## What this means day to day
- Added a table or a reducer: `tools\publish.cmd --codegen`. Friends' builds keep playing; they
  update when they want the new feature.
- Changed a table's columns or a reducer's arguments: the unit suite says which release it strands.
  Do it the compatible way instead (side table, `_v2` reducer), or, if it is worth a re-download,
  bump `compat` and send everyone a new build.
- Retuned something clients simulate (movement, a minigame's curve): bump `compat`; the unit suite
  cannot see that one.
