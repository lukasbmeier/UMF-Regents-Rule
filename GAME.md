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

## Current state (0.38.0)
Made from Fishing 0.24.1 by `python tools/template/strip_genre.py fishing` (DECISIONS #196). It
builds, publishes and passes every suite with no genre in it. FOUNDATION WORK IS DONE HERE, with
its tests, then each game pulls it (`tools\update_from_template.cmd`). 0.26.0: old builds keep
working on new servers (#198); builds for friends come from `tools\release.cmd`. 0.27.0-0.31.0:
content is `ContentDef` resources, baked, in the Content Dock, with hot rules tuned live and
workbenches with a Catalog (#199-#201, #203), characters as content with a bench (#204); 0.33.0: movement profiles, the first of the foundation systems (`docs/FOUNDATION_SYSTEMS.md`, #205); 0.34.0: statuses and their timers, spectate (#206); 0.35.0: Workbenches 2, the benches reworked after their first real use (#207); 0.36.0: hold to interact, with Help up (#209); 0.37.0: server-timed skill checks (#210); 0.38.0: a splash with tips and lore, the target in front of the character, a self-calibrating skill-check bar (#211-#213); 0.30.0: players who disconnect leave the world, names
are unique (#202). `docs/rules/content.md`: read its design commitments before extending content.

Next, in order: `docs/FOUNDATION_SYSTEMS.md`, milestone 3 (hold to interact), then 4 (server-timed
skill checks), 5 (abilities on the sidecar), and on. Fishing moves its own content (definitions,
fish, spots) in Fishing.

Open from the review (`docs/reviews/REVIEW_0.23.1.md`): D1 (kit attribution: no kits ship in the
template), D4 (content validation in `build.rs`: ContentDef covers it), E (spec drift), F (suspected
bugs to check). The held-item system has no foundation content to test it with yet (DECISIONS #194).
