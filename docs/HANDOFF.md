# Handoff — Regent's Rule, 2026-11-17 (the follow-up run, finished)

## Where it stands
- The FOLLOW-UP run is done: steps 102-108 on `main`, pushed. The ledger is `docs/regents_rule/FOLLOWUP_RUN.md`.
- Suites on `main` (2026-11-17): the whole unit suite after the last merge 5249/0; `cargo test` and wasm green; `content_test.sh` 18/0. M9 on `main`: combat
  157/0, spells_seen 12/0, armor_seen 7/0; integration and caster red at first (1734/3, 19/1), fixed in 107: integration
  1703/0 then 1710/0 (108), caster 4 of 4 green, on lane A's branch.
- The play database `regents-rule` was published after A2 (step 105: the practice armor gone); later steps are client
  or test changes. Schema unchanged.
- Fishing, Fowl Play, DiscGolf republished with `--codegen`, bindings pushed: Fowl Play 2815/0, DiscGolf 2605/0,
  Fishing 3309/2 (its held-items grip suite: the rod up to 33 cm into the body; the grips are Luke's).
- Both children archived; their worktrees and branches removed.

## This session
- 101 committed (Luke's yes). 102 (B1): the bar's words say a hit's slow, shove and sweep (`RegentsAbilityBar.hit_words`).
- 103 (A1): a real client presses the bow's Q, E, R (`combat_playtest.sh`, `LEG=bow_skills`).
- 104 (B2): the Bolt's hand flash (`on_cast`), Meteor's fire ring (`ring`), others' missiles lighter (`ShotLook.make_lighter`).
- 105 (A2): the practice armor 40067/40068 deleted; integration and tests on the iron cuirass and steel armet.
- 106 (B2b): the VFX lab's leftover Bolt hit flash (lab only). 107 (A3): the poise leg waits on its row
  (`steadied_out`), the caster's walked-bolt and cast-stopped legs robust. 108 (A3b): integration's genre hook counts
  the same checks every run (`put_away`, `give_back`, `COUNT_BY_SECTION=1`).

## Next, in order
1. Luke plays (GAME.md, "The follow-up run"): the bar's words, the staff's Bolt and Meteor, two instances for
   another player's Bolt; restart the game for the new publish.
2. TEMPLATE work (PROGRESS 108, 107): `COUNT_BY_SECTION` in the foundation's `tests/integration_test.sh` and its
   per-row `revoke_authority` / `despawn_entity` checks; the player `vel` in the movement row reading ~4 % low.
   In `../UMF Template`, then pull here.
3. The bow's skills are worded as melee on the bar (PROGRESS 102): a line for a kit that `draws`.
4. Whatever Luke answers in `WAITING_ON_LUKE.md` (armor's traits and numbers, the real ability content, the UI
   rebuild, towns, the world builder's NPCs on the server).

## Waiting on Luke
- `docs/regents_rule/WAITING_ON_LUKE.md`; new this run: a shove worded in m/s or meters; Meteor's ring colors (a
  player's fire ring like the imp's?); the Bolt's hand flash's size; foes' shots led a little short of a walker.

## Watch out
- The local SpacetimeDB server was down at the run's start; lane A started it (detached). Fishing needed a Godot
  `--import` before its unit suite.
- Integration took 14-24 min this run (was ~80). Compare counts leg by leg with `COUNT_BY_SECTION=1` (PROGRESS 108).
- `docs/HANDBOOK.md` is the template's: never edited here.
