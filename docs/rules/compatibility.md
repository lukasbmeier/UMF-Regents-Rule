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

## What enforces it (being built in the template)
- **A compatibility check instead of an exact match.** At connect the client checks only what IT
  uses: every table it subscribes to has the same row shape on the server, every reducer it calls the
  same arguments. Extra server tables and reducers are fine. The server carries a
  `min_client_version`, bumped by hand for a deliberate break; a client below it is told plainly
  "this server needs a newer version". (Today the fingerprint must match exactly, DECISIONS #164.)
- **A schema snapshot per release.** Each release saves its schema to `shared/compat/<version>.json`;
  a test fails the build when the new schema is not a superset of the last release's, unless the
  major version was bumped.
- **A real old client.** The export test keeps the previous release's build and plays it against
  the new server.
