---
paths:
  - "server/**"
---
# The module (Rust, SpacetimeDB)

- The crates are pinned `spacetimedb = "=2.10.1"` and `spacetimedb-lib = "=2.10.1"`
  (`server/Cargo.toml`). Never bump them in a game; a bump is a template change with every suite.
- API: `docs.rs/spacetimedb/2.10.1`. No 1.x spellings: `name =` on a table, `ctx.sender` as a field,
  `ScheduleAt::Interval(...)`.
- Every table and reducer lives in `server/src/module/` (one file per system) behind
  `#[cfg(target_arch = "wasm32")]`; `sim.rs` never depends on the `spacetimedb` crate and is FROZEN
  (DECISIONS #27). Breaking either breaks `cargo test` at link.
- A genre's server is `server/src/game/<genre>.rs` and `server/src/genre/<genre>/`, `cfg`-gated;
  `build.rs` declares genre modules; no foundation file names a genre (AGENTS.md rule 16).
- Schema (AGENTS.md rules 9, 15, 17; `docs/rules/compatibility.md`): add tables and reducers, never
  reshape one or change a reducer's arguments within a major version. New data goes in a side table,
  new arguments in a `_v2` reducer. A table added: `tools/publish.sh --codegen`. `--fresh` wipes the
  game's database: Luke's say-so only.
- A player-callable reducer: inputs in, outcomes derived (rule 13); `spend_rate` first plus a
  `rules.json` `rate_limits` line when every client receives its rows or it moves a player between
  worlds (rule 14); dev helpers behind `require_dev_tools`.
- A number worth tuning live: `hot_number(ctx, crate::hot::<owner>::<NAME>)`, never a constant.

## Checking a change
```bash
cd server && cargo check --target wasm32-unknown-unknown   # the check that counts: module/ is wasm-gated
cd server && cargo test                                    # golden, challenge, level, rate, genres
```
`tests/integration_test.sh` is the only coverage of `module/`. Server suites share one test
database: never run two at once.
