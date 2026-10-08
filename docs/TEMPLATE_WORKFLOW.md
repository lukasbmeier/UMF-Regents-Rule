# From foundation to games — template workflow

## Sequence
1. **Phase 3, Phase 4** on this repo (see specs).
2. **Phase 5 = one real genre** built *inside* this repo under `game/`, `sidecar/game/`, `server/src/game/`. Pick fishing (exercises sessions, challenge, inventory, Tier A) or chicken (exercises sidecar, NPCs, prediction). Do not template before a game has shipped a playable loop on the foundation; that game is what finds the gaps.
3. **Tag the foundation** (`foundation-v1.0`). Move the first game out into its own repo (step 4) or keep it as the reference game in `examples/`.
4. **New game = new repo from the template** containing:
   - `foundation/`, `sidecar/` (core), `server/src/{lib,sim,challenge}.rs`, `shared/`, `docs/`, `AGENTS.md` — pulled in with `git subtree add --prefix=... <foundation-repo> foundation-v1.0 --squash` so `git subtree pull/push` moves fixes both ways.
   - Empty `game/`, `sidecar/game/`, `server/src/game/` with the `mod.rs` hooks the module calls:
     `on_init`, `on_player_created`, `on_player_returned`, `on_player_left`, `on_interact`,
     `resolve_challenge`, `on_challenge_succeeded`, `on_challenge_closed` — and a
     `shared/rules.json` with the game's health, interact range and round plans. A genre's
     tables and reducers need no registration: SpacetimeDB finds them wherever they are declared.
     The client half needs no hook either: the game scene's `Boot` node lists its entity
     definitions, and its `NetConfig` lists its tables. (An earlier draft planned a
     `game::register_tables!` macro and a `GameLayer` autoload; neither was needed, and neither
     exists. The hooks still missing are listed in `docs/HANDBOOK.md` §11.)
   - `GAME_BRIEF.md` (below) and the matching section copied from `docs/GENRE_ADAPTERS.md`.
   - `project.godot`'s `run/main_scene` repointed at the new game's scene. It ships pointing at
     `game/fishing/lakeside_game.tscn` so that pressing Play runs the reference game; leaving it
     there after deleting `game/` is a dangling path (DECISIONS #64). `foundation/boot.tscn` is
     the bare foundation if you want to run that alone.
5. The frontier model starts from `AGENTS.md` → `GAME_BRIEF.md` → the genre section. It never needs the design conversation.

## `GAME_BRIEF.md` template
```
# <Game name>
Genre section: docs/GENRE_ADAPTERS.md §<n>
Players per world: <n>       Motion authority: MODULE (Tier A) | SIDECAR
Camera: first | third (rig: res://game/camera/<rig>.tres)
Movement branches enabled: walk, sprint, jump[, flap, dash, swim, mount, fly]
Foundation systems used: session(kind=<k>, phases=[...]), challenge(kinds=[...]), inventory, action, npc, interest(cell|world)
Game tables: <name>{fields}  ...
Game reducers: <name>(args) — rule in one line ...
Skeleton families: humanoid (Quaternius UAL) | bird | quadruped — AnimationSets in res://game/anim/
Feedback overrides: <events> → <responses>
Definition of done for the first playable: <one paragraph>
```

## Rules for keeping the template healthy
- Anything two games need moves *down* into the foundation via subtree push, with a `DECISIONS.md` entry.
- Foundation never imports from `game/`. Hooks only.
- A game may add `move_state` values ≥ 100 and semantic animation names under its own namespace (`game.*`).
- Every foundation release runs `run_tests.sh`, `cargo test`, `integration_test.sh`, `e2e_test.sh`
  and `multiclient_test.sh`, plus the reference-humanoid animation test.
- A genre's static world content (spawn points, resource nodes, catalogues) is seeded from
  `game::on_init` so that a published module is playable on its own. A game that needs a shell
  script before it can be played cannot be opened and run by the next person (DECISIONS #63).
