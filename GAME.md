# GAME.md — what this repo is

**The UMF template** (github: UMF-Foundation). The foundation with no genre, playable as the
greybox game (`game/greybox_game.tscn`: the reference humanoid, the example level, a wandering
NPC). Every game is a fork of this repo and takes its updates with `git pull template main`
(`docs/TEMPLATE_WORKFLOW.md`).

| | |
|---|---|
| Genres | none (`shared/game.json` `genres: []`) |
| Database | `umf-template`; the suites use `umf-template-test` |
| Main scene | `res://game/greybox_game.tscn` |
| Genre rules files | none |
| Games made from it | Fishing (UMF-Fishing, the reference game, parked) · Fowl Play (game 2) |

## Current state (0.25.0)
Made from Fishing 0.24.1 by `python tools/template/strip_genre.py fishing` (DECISIONS #196). It
builds, publishes and passes every suite with no genre in it. FOUNDATION WORK IS DONE HERE, with
its tests, then each game pulls it.

Next, in order:
1. The compatibility check (`docs/rules/compatibility.md`): a subset check instead of the exact
   fingerprint, `min_client_version`, a schema snapshot per release, an old-build export test.
2. Content tooling step 1 (`docs/CONTENT_TOOLING_SPEC.md` §9): `ContentDef` + bake + the
   manifest check in `build.rs`; then the `rules` table (hot tunables, §4) and the `Workbench`
   base (§3).
3. What Fowl Play needs in the foundation (its `docs/fowl_play/FOWL_PLAY_OPEN_ITEMS.md` §D),
   built here so every game gets it.

Open from the review (`docs/reviews/REVIEW_0.23.1.md`): D1 (kit attribution: no kits ship in the
template), D4 (content validation in `build.rs`: ContentDef covers it), E (spec drift), F (suspected
bugs to check). The held-item system has no foundation content to test it with yet (DECISIONS #194).
