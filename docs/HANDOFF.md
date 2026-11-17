# Handoff — Regent's Rule, 2026-11-17 (the follow-up run, in progress)

## Where it stands
- The FOLLOW-UP run (after the armor run 87-100 and step 101, the world builder): one master in the main checkout,
  two children in worktrees. The ledger is `docs/regents_rule/FOLLOWUP_RUN.md`; the rules are `MASTER_RUN.md` §1, §3,
  §4, §5.
- `main`: step 101 (`54c7ecb4`), B1 step 102 (`cf259946`), A1 step 103 (`79cf6bc5`), B2 step 104 (`dec49de2`). The
  whole unit suite on `main` after the last merge: **5258/0** (lints, engine errors, leaks ok). Pushed.
- The play database `regents-rule` was last published by the armor run; 102-104 are client or test changes (no publish
  needed).
- M1 done: Fowl Play 2815/0, DiscGolf 2605/0, Fishing 3309/2 (its held-items grip suite: the rod up to 33 cm into the
  body; Luke's grips). Each republished with `--codegen`, bindings committed and pushed.

## This session
- Step 101 committed (Luke's yes). Lane A (`lane-a`, Opus 5.5 high), Lane B (`lane-b`, Opus 5.5 medium) started.
- 102 (B1): the bar's words say a hit's slow, shove and every-foe sweep from the data (`RegentsAbilityBar.hit_words`).
- 103 (A1): `combat_playtest.sh` presses the bow's Q, E (Pinning Shot) and R (Arrow Volley) through a real client and
  reads the server's record; `LEG=bow_skills` runs it alone (~2 min).
- 104 (B2): the Bolt's hand flash (`on_cast`), Meteor's fire ring (`ring`), another player's missile lighter
  (`ShotLook.make_lighter`). New placeholders in `WAITING_ON_LUKE.md` §2.

## Next, in order
1. Lane A's A2 (the practice armor 40067/40068 removed, legs on real pieces, re-bake): merge by `MASTER_RUN.md` §5;
   it re-bakes, so publish the play database after.
2. Lane B's B2b (the one-frame violet circle at the Bolt's cast): merge by §5.
3. M9 on `main`: unit, `cargo test`, wasm, integration ONCE, combat / caster / spells_seen / armor_seen playtests;
   publish the play database; the final HANDOFF; archive both children, remove their worktrees and branches.

## Waiting on Luke
- `docs/regents_rule/WAITING_ON_LUKE.md` §1-§2; new this run: how a shove is worded (m/s or meters), Meteor's ring
  colors (a player's fire ring like the imp's?), the Bolt's hand flash's size.
- Not in this run: armor's traits, parts and numbers; the real ability content; the UI rebuild; towns S1-S8; the
  server spawning the world builder's NPCs.

## Watch out
- The bow's skills are worded as melee on the bar (PROGRESS 102): older than B1, not in this run.
- Two timing-dependent failures in the whole combat run's other legs (PROGRESS 103): a blocked light read once in the
  armor leg; the yard skeleton's swing 3 ms after its stagger.
- The local SpacetimeDB server was down at the start of the run; lane A started it (detached). Fishing needed a Godot
  `--import` before its unit suite.
- `docs/HANDBOOK.md` is the template's: never edited here.
