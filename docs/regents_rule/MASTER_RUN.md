# MASTER_RUN — the armor run (2026-11-15)

One master session (Fable 5.2) starts child sessions, merges their branches into `main`, pushes, and keeps the
record. Luke is away for most of it. This file is the master's: the work list (§2), who may touch what (§3), how
a child works (§4), how the master merges (§5), and the ledger (§7). Only the master edits this file.

Luke's scope (2026-11-15): "Armor which might tie into wardrobe in game; anything else that is open not pending
my decisions"; the engineering backlog, the wardrobe into the game, abilities step 3; "the specifics of abilities
can come later but we know the number of abilities and most of the rules ... use placeholders and I'll fill in
later"; a concise sheet of what waits on him. (The town worktree, thought dead, finished itself: M1.)

## 1. Ground rules (on top of AGENTS.md, CLAUDE.md, `.claude/rules/*`)
- **Luke's decisions are never defaulted.** Where a decision is his and the work needs a value, use a PLACEHOLDER:
  named `... (placeholder)` where a player sees it, marked in data (`placeholder: true` or a `# PLACEHOLDER:`
  comment), and listed in `WAITING_ON_LUKE.md` §2 with where to change it. A placeholder never invents a new
  mechanic (no new trait atom, no new effect kind): it reuses what exists.
- **Never `--fresh`.** Schema changes are add-only (rule 17); `publish.sh --codegen` is fine.
- **Only the master** commits to `main`, pushes, publishes the PLAY database, runs `ship_template.sh`, and edits
  `PROGRESS.md`, `GAME.md`, `docs/HANDOFF.md`, this file, `.claude/rules/regents-genre.md`, `docs/HANDBOOK.md`.
  Children write that text into their inbox file (§4) and the master folds it in.
- Stage named paths only (never `commit -a`); `addons/SpacetimeDB/plugin_config.tres` stays out of every commit.
- Integration (~80 min) runs ONCE, at the end (§2, M9), not per item; a failed leg is diagnosed from its log.

## 2. The work list
Ids are fixed; PROGRESS step numbers are given by the master AT MERGE (the next free number, from 87).
"Needs" = must be merged on `main` first.

### Lane 0 — the master itself (main checkout)
| Id | What | Needs |
|---|---|---|
| M1 | **DONE before the run**: the town worktree's session was alive after all and finished its work; it is on `main` as `34bedf9d` (roofs, streets, the props kit's furnishing) and `9064c56b` (the town lab's Places view). Left: remove `.claude/worktrees/medieval-village-worldbuilding-dd942b` once the session list shows its session ended (the worktree is clean). | — |
| M2 | **`docs/regents_rule/WAITING_ON_LUKE.md`**: the concise sheet. §1 decisions only Luke can make: one line each (the question, today's value or the proposal, the doc §), grouped (combat and foes, abilities, armor, towns S1-S8, showcase, world, UI rebuild to-dos, art/AI audit), gathered from HANDOFF "Waiting on Luke", every PREP doc's open list and `GAME.md`'s "still open" lines, deduplicated against what `GAME.md` already settles. §2 every placeholder this run makes (filled in as children report). §3 things to play and look at. Under ~80 lines; no essays. | — |
| M3 | Ship Lane T's template release (`../ship_template.sh`) at a quiet moment (no merge in flight, no child mid-suite on the test database), then republish `--codegen` if the pull needs it, unit suite on `main`, push. | T1 |
| M9 | **The end sweep**: on `main` with everything merged: `run_tests.sh` whole, `cargo test`, wasm check, `integration_test.sh` once, `combat_playtest.sh`, `spells_seen_playtest.sh`, `caster_playtest.sh`; publish the play database; final HANDOFF. | all |

### Lane T — template (`../UMF Template`, its own session there)
| Id | What | Needs |
|---|---|---|
| T1 | **`ModularCharacter.wear(pieces)`** and a signal when the character is put together again (WARDROBE.md §6 step 1), so a genre can swap pieces without the appearance text and dress them after. Template suites, a DECISIONS row + index line, HANDBOOK, CHANGELOG, a release version. If E2 below turns out to be foundation, it goes in this lane too (same session, after T1). | — |

### Lane S — server and referee (ONE child at a time, in order: they share the hit code)
| Id | What | Needs |
|---|---|---|
| S1 | **Areas that hit all** (`ABILITIES_PREP.md` §7 step 3): the referee's area hits reach every target in them. Native tests with negatives, unit, the playtest that covers areas (caster or combat). | — |
| S2 | **Armor core** (`ARMOR_PREP.md` §4 step 1, §3; settled in `GAME.md` "ARMOR PARKED ... Settled now"): the `worn` table (a cell table like `wielded`, add-only: `world_id`, an indexed `chunk`, `follow_place`, the net config's `cell_tables` + `follow_tables`, `genre.tres` `world_tables`, per `regents-genre.md`), wear / take off from the bag, out of combat only (`regen_delay_s`), a `rate_limits` line; Defense in the hit, `damage x K / (K + Defense)`, the guard first then armor then traits, multiplied; hot rule `regents.defense_k` (67); `FoeDef.defense` (0 on today's foes). `publish.sh --codegen` on the test database. Integration legs written (run in M9). | S1 |
| S3 | **Armor pieces** (§4 step 2): head, chest, legs for metal, leather and cloth (W1's pieces), patterns joined to the material table, Defense = the pattern's share x the material's tier, quality +20 % at 1000. PLACEHOLDER: the slot shares, the tier numbers, the secondary parts (structure for three trait-bearing parts, their trait pools EMPTY: traits are Luke's), the recipes (or a dev grant so a tester can wear them). The trinket stays empty. | S2 |
| S4 | **The chest's ability on F** (`ABILITIES_PREP.md` §7 step 5, B5): the F slot sourced from the worn chest, one ability per family. PLACEHOLDER abilities from existing atoms; the reading "Blink moves from the staff's F to the cloth chest" (ABILITIES S4: "Blink stays on F until cloth chests") goes in `WAITING_ON_LUKE.md` to confirm. Touches the bar's F: holds the `game/regents/ui/` token (§3). | S3, P1 |

### Lane P — ability content (content and data; parallel to Lane S)
| Id | What | Needs |
|---|---|---|
| P1 | **Every weapon's pools, as placeholders** (`ABILITIES_PREP.md` §7 step 4, §9; B4-B6): the sword's from the §9 draft, the axe's and bow's per role handle, each with its base Q, 3-4 options a pick (~5 E, ~12), an ult at ~20 for every weapon, the staff's Bolt. Placeholders reuse today's effects and are named and marked (§1). Ults existing changes R (step 76's "until a weapon has an ult, R takes E's other option"): update those tests deliberately, keep a negative. If it needs code under `server/src/genre/regents/` beyond content, STOP and report: the master queues it after Lane S's current item. | — |

### Lane W — the wardrobe in the game (client)
| Id | What | Needs |
|---|---|---|
| W1 | **The picker's colors** (W8, W4): the starting Peasant clothes in the player's own colors, one per slot (main, accent, under, trim, leather) as keys on the `appearance` text (add-only: old clients ignore them), a free picker with a row of suggested swatches; an empty armor slot shows the player's own Peasant piece. | T1 if it swaps pieces; else none |
| W2 | **The look component** (WARDROBE.md §6 step 2): reads `worn`, maps each worn item to its pieces and tier palette (`MetalFinish` by material; leather by animal, cloth neutral), `Wardrobe.dress` after each reassembly; others see it through the ring. Presentation only (hard rule 11). Holds the character-scene token (§3). | T1 (shipped, M3), S2, S3 |
| W3 | **Wearing from the bag** (settled: "from the bag (I), a paper doll of head, chest, legs and trinket"): the doll, wear and take off, refused in combat with the reason, each piece's words ("you'd take 19 % less, now 13 %"), the doll's total, never Light / Heavy. Minimal: the UI REBUILD (drag, resize, C sheet) is Luke's to shape, not this. Holds the `ui/` token. | S2, S3, S4 merged (shares `ui/`) |
| W4 | **The dye's cost at 300** (§6 step 4): `load_300.sh` with dressed bots (~25 min; the test-database lock); a share-by-palette fix if it costs too much. | W2 |

### Lane E — the engineering backlog (client presentation; parallel from the start)
| Id | What | Needs |
|---|---|---|
| E1 | **Others' effects at scale** (HANDOFF next 4): a lighter version for other players' effects, the rings as one MultiMesh, the camera listening to `shook`. `vfx_lab.tscn -- cost` before and after; `regents_vfx`; `spells_seen_playtest.sh`. | — |
| E2 | **The "binding after 2.0s without rows for session_member" warnings** every playtest client prints (HANDOFF next 5; not from step 83). Find the cause; a genre fix here, a foundation fix to Lane T. | — |
| E3 | **Towns, the engineering half** (`SETTLEMENTS_PREP.md` §8 "Left for later"): a saved bake of a merged building (the world builds in ~17 s today); the village kit's small props (wagon, crates, fences, vines) placed by a `Settlement`. LODs or impostors ONLY if `docs/rules/version_settings_looks.md` ("no LODs") allows them; if not, a line in `WAITING_ON_LUKE.md`. | M1 |

**Not in this run** (Luke's to shape or answer first, so they go in `WAITING_ON_LUKE.md`): the UI rebuild's four
to-dos; armor's real traits, parts and numbers (placeholders only); others' aim held after a spell ("maybe");
towns S1-S8 and a first real village; replacing the AI continent map; herbalism dyes; hats.

## 3. Who may touch what (the conflict map)
Each child works in its OWN worktree (`use_worktree: true`), so another session's writes never stop its playtest's
referee. What still collides is files on merge and the shared servers:

| Shared thing | Rule |
|---|---|
| `server/src/game/regents.rs`, `server/src/genre/regents/**`, `sidecar/npc/brains/regents/**`, `shared/regents/*.json` | Lane S only. Anyone else stops and asks the master. |
| `game/regents/ui/**` (bar, bag, windows) | ONE holder at a time: the `ui/` token (S4, then W3; W1's picker if it lives there). |
| `game/regents/**/adventurer.tscn`, `foe.tscn`, `regents_game.tscn`, `CombatComponent` | ONE holder at a time: the character-scene token (W2; E1 if it needs them). |
| `shared/content/**` (baked), `spacetime_bindings/**` (codegen) | Never hand-merged: on conflict take either side, then re-bake / `publish.sh --codegen` on `main` and commit the result. |
| `tools/template/genres/regents.paths` | On conflict, keep both sides' lines (sorted, no duplicates). |
| `PROGRESS.md`, `GAME.md`, `HANDOFF.md`, this file, `regents-genre.md`, `HANDBOOK.md` | Master only (§1). |
| The TEST database `regents-rule-test` | ONE server suite at a time across all sessions: the lock (below). |
| The PLAY database `regents-rule` | Master only, after a merge that is playable. |
| The local SpacetimeDB server | Shared by every game: never stopped or restarted. |
| `main` checkout | Master only. No child edits it; no editor session there (Luke's editor may be open on it). |

**The test-database lock**: `mkdir "../.umf-locks/regents-rule-test"` (atomic; fails if held), then write
`owner.txt` inside (session name, item, time); `rm -rf` it when the suite ends, pass or fail. Held over 2 hours:
the master checks the holder is alive before breaking it. The master hands out the tokens in §3 by recording the
holder in the ledger (§7); a child asks before taking one.

## 4. How a child works (paste into each child's brief)
1. Read `docs/HANDOFF.md`, `GAME.md`'s parts your item names, the doc § your item names, this file's §1, §3, §4.
2. In your worktree: copy `tools/local.env` from the main checkout (it is git-ignored); first Godot open imports
   (the village kit is ~86 MB). Start from the `main` tip the master named.
3. Build only your item. Never touch a file §3 gives to another lane or the master. Unsure: ask the master
   (SendMessage), keep working on what is clear.
4. Test as AGENTS.md's verify loop says, the suites your change touches plus a NEGATIVE that fails without the change
   (Luke's bar: real, end-to-end, never loosened). Server suites only under the lock. No file writes in your own
   worktree while your playtest runs. Windowed shots: look at them.
5. Before reporting: `git merge main` into your branch, re-run your suites, commit (named paths, the attribution
   line), do NOT push, do NOT merge to `main`.
6. Write `docs/regents_rule/inbox/<ID>.md` on your branch (it is your report and becomes the PROGRESS step):
   ```
   # <ID>: <TITLE IN CAPS>
   Built: <files, what each does>
   How to play it: <keys, where, what to see>
   Tested: <suite: passed/failed, the negative and how it failed without the change>
   Needs on merge: <none | publish --codegen | re-bake | template pull>
   Placeholders made: <name, file, what Luke fills in>
   For Luke: <decisions found, in one line each>
   For the rules/handbook: <lines for regents-genre.md or HANDBOOK.md, or none>
   Left for later: <...>
   ```
7. Your final message: the branch name, the head commit, the inbox file, green or red.

## 5. How the master merges (one at a time, in the main checkout)
1. Read the child's inbox file and its diff (`git diff main...<branch> --stat`, then the real changes). A report is
   not proof: re-run the child's key suite yourself if anything looks off.
2. `git merge --no-ff <branch>` (message: `<ID>: <title> (step NN)` + the attribution line). Conflicts by §3.
3. Fold the inbox file into `PROGRESS.md` as `## Step NN: ...` (the next free number), its placeholders and
   "For Luke" into `WAITING_ON_LUKE.md`, its rule lines into `regents-genre.md` / HANDBOOK; delete the inbox file.
   Commit that with the merge (amend nothing: a second commit is fine).
4. On `main`: whatever "Needs on merge" says (re-bake, `publish.sh --codegen` to the TEST database under the lock),
   then `run_tests.sh` whole; `cargo test` + `cargo check --target wasm32-unknown-unknown` if `server/` changed.
   Red: fix it or revert the merge (`git revert -m 1`), never push red.
5. Green: `git push origin main`; publish the PLAY database if the change is playable (`publish.sh --codegen`,
   never `--fresh`); update the ledger (§7); REWRITE `docs/HANDOFF.md` (the protocol's shape, under ~60 lines) so a
   crash at any moment leaves it true; commit and push those.
6. Tell the next waiting children `main` moved (they merge it before reporting); start what this merge unblocked.
7. Worktree cleanup only after the branch is merged and pushed.

## 6. Order of starting
At once: M2 (master), T1, S1, P1, E1, E2, E3 (M1 is done). After T1 (M3 shipped): W1 if it needs the hook,
else at once. After S1: S2; after S2: S3; after S3 + P1: S4; after S2 + S3 + M3: W2; after S4: W3; after W2: W4.
At most ~5 children running at once; never two children holding the test-database lock or the same token.

## 6b. Models and effort (Luke, 2026-11-15: lots done, good quality, no wasted usage)
A child inherits the master's model unless told otherwise: pass `model` on every start and set its effort
(`set_session_effort`) right after.
| Children | Model | Effort | Why |
|---|---|---|---|
| S1, S2, S3, S4, T1 | Opus 5.5 | high | the hit code, a new table, the foundation: a mistake here costs an integration run |
| W2, W3, E2 | Opus 5.5 | high | the character scene, the bag, a cause to find |
| P1, W1, E1, E3, W4 | Opus 5.5 | medium | placeholders, presentation, measured work |
| The master | Fable 5.2 | medium | merging and recording; raise it to high only for a hard merge or a red sweep |

## 7. The ledger (the master updates it at every start, merge and token change)
2026-11-16: every child was cut by the 5-hour usage limit on 2026-11-15; T1, S1, P1, E1, E2 were told to continue
(SendMessage to the same sessions), E3 waits for a slot. Template test database lock: `.umf-locks/umf-template-test`.
| Id | Session | Branch | State | Step | Merge commit | Tokens held |
|---|---|---|---|---|---|---|
| M1 | town session | (deleted) | DONE: worktree and branch removed 2026-11-15 (an empty locked folder `.claude/worktrees/medieval-...` is left: delete by hand) | 85 (extended) | 34bedf9d, 9064c56b | |
| M2 | master | — | DONE: `WAITING_ON_LUKE.md` | | | |
| T1 | t1-wear-hook (local_8bc5463c), in `../UMF Template` | claude/t1-wear-hook-69d351 (template) | MERGED into the template's main 2026-11-16 (`9b2e4aa`: #313 wear + assembled, #315 NPCs bind), SHIPPED in 1.8.3 | — | template 4437fa4 | |
| S1 | s1-areas-hit-all (local_2bb14966) | s1-areas-hit-all (game) + its own branch in `../UMF Template` | MERGED 2026-11-16 | 89 | c94bdc92 | |
| S1b | (queued, Lane S, after S1) | | NEW (P1's stop, 2026-11-15): PER-ROLE POOLS on the server: `KitRole` its own skills + slots (bake), per-role `KitSeed`, the gates (`slot_refusal`, `pick_refusal`, `need_slot`, `choose_pick`) read the wielded item's role, the client twin `item_level.gd`; then P1's content per role. Until then P1 ships ONE placeholder pool per weapon KIND | | | |
| S2 | | | waiting S1 (so M3 too) | | | |
| S3 | | | waiting S2 | | | |
| S4 | | | waiting S3, P1 | | | ui/ |
| P1 | p1-weapon-pools (local_fbb26ccb) | p1-weapon-pools | MERGED 2026-11-16 | 91 | 754818e4 | |
| W1 | | | waiting T1? | | | |
| W2 | | | waiting T1, S2, S3 | | | scene |
| W3 | | | waiting S4 | | | ui/ |
| W4 | | | waiting W2 | | | test DB |
| E1 | e1-effects-scale (local_e7199708) | claude/e1-effects-scale-536c07 | MERGED 2026-11-16 | 88 | 127d571e | |
| E2 | e2-binding-warnings (local_ee2e2534) | claude/e2-binding-warnings-7b4e42 | MERGED 2026-11-16 (the general fix in T1's branch, #315) | 87 | ebead5ac | |
| E3 | e3-towns-bake (local_4afd208b) | claude/e3-towns-bake-d0f216 | MERGED 2026-11-16 | 90 | cb3a6df2 | |
| M3 | master | — | DONE 2026-11-16: template 1.8.3 (`4437fa4`: T1 + S1's `resolve_action_all` #314) shipped to all four games; here `aca81080` | | aca81080 | |
| M9 | master | — | waiting all | | | |

## 8. The master's prompt (what Luke pastes to start it)
See the block in the chat of 2026-11-15; kept here so a restarted master can be given it again:

> You are the MASTER session for Regent's Rule's armor run. Read, in order: `docs/HANDOFF.md`, then
> `docs/regents_rule/MASTER_RUN.md` (all of it: it is your work list, conflict map, child protocol, merge
> procedure and ledger), then `GAME.md`'s armor, wardrobe and abilities sections. Then: (1) `MASTER_RUN.md` is already on `main`;
> remove the town worktree if its session ended (M1); (2) do M2 yourself;
> (3) start the children §6 says can start at once, each with `use_worktree: true`, the model and effort §6b names, a brief that is its §2 row,
> the doc § it names, and §4 pasted in full; Lane T's child runs in `../UMF Template`. You build nothing big
> yourself: you merge, test, push, publish and record. After EVERY merge: the §5 steps, the ledger, a rewritten
> `docs/HANDOFF.md`, pushed. Never default a decision of Luke's (placeholders, §1), never `--fresh`, never push
> red. When everything is merged: M9, the final HANDOFF, and a short report of what Luke should play first and
> what `WAITING_ON_LUKE.md` asks him.
