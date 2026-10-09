# From foundation to games — template workflow

## How the repos fit (0.25.0, DECISIONS #196)
```
UMF ALL/
  UMF Template/   github UMF-Foundation   the foundation with no genre; plays as the greybox game
  Fishing/        github UMF-Fishing      game: genres ["fishing"], database umf
  Fowl Play/      github (its own)        game: genres ["chicken"], database fowl-play
```
Each game is a FORK of the template: the same history, plus its genre's files. A game has a git
remote named `template` pointing at UMF-Foundation, and takes foundation updates by
double-clicking `tools\update_from_template.cmd` (commit your work first). It runs
```bash
git pull template main
```
then republishes the game's own database with `--codegen` (keeping its data: the bindings are each
game's, and a pull keeps the game's copy, `.gitattributes`) and runs the unit suite; then commit
and push. Each game's `GAME.md` and `shared/game.json` are its own too. That merges cleanly when the game kept the boundary (AGENTS.md rule 16): the game changed only
its genre's files (those in `tools/template/genres/<genre>.paths`) and its own settings
(`project.godot`'s name and main scene, `shared/game.json`, `shared/rules.json`). A conflict
anywhere else means foundation work was done in the game; move it to the template.

The template was made from Fishing by removing the genre (`python tools/template/strip_genre.py
fishing`), so Fishing joined the template's history with a one-time `git merge -s ours
template/main` ("I already have all of this"), and pulls normally from then on.

## Where work goes
- **Foundation work goes in the template**, with its tests, then each game pulls it. Never fix the
  foundation in a game: the fix would stay there.
- **Genre work goes in the game.** If a second game needs it, it moves down into the template
  (`foundation/`, or a foundation hook), with a `DECISIONS.md` entry; the first game then deletes
  its copy after pulling.
- **Each game has its own database** (`shared/game.json` `database`), so publishing one game never
  touches another's world on the same server. Tests use `<database>-test`.
- **Old clients keep working** on a new server within a major version (`docs/rules/compatibility.md`):
  a foundation update a game pulls must not force its players to re-download.

## Starting a new game
```bash
cd "UMF ALL"
git clone https://github.com/lukasbmeier/UMF-Foundation.git "<Game>"
cd "<Game>"
git remote rename origin template
git remote add origin https://github.com/lukasbmeier/<game-repo>.git
```
Then: `project.godot` `config/name`, `shared/game.json` `title` and `database`, copy
`tools/local.env`, open the project in Godot once (import), `tools\publish.cmd --codegen`, and the
suites. A genre is added the way `docs/HANDBOOK.md` (the genre recipe) says: its folder under
`game/<genre>/`, `server/src/game/<genre>.rs`, `server/src/genre/<genre>/`, its manifest
`tools/template/genres/<genre>.paths`, its name in `shared/game.json` `genres`. Write
`GAME_BRIEF.md` (below) first.

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
- Anything two games need moves *down* into the template (done in the template, then each game pulls), with a `DECISIONS.md` entry.
- Foundation never imports from `game/`. Hooks only.
- A game may add `move_state` values ≥ 100 and semantic animation names under its own namespace (`game.*`).
- Every foundation release runs `run_tests.sh`, `cargo test`, `integration_test.sh`, `e2e_test.sh`
  and `multiclient_test.sh`, plus the reference-humanoid animation test.
- A genre's static world content (spawn points, resource nodes, catalogues) is seeded from
  `game::on_init` so that a published module is playable on its own. A game that needs a shell
  script before it can be played cannot be opened and run by the next person (DECISIONS #63).
