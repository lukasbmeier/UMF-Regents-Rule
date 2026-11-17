# Handoff — Regent's Rule, 2026-11-17 (the follow-up run, in progress)

## Where it stands
- The FOLLOW-UP run (after the armor run 87-100 and step 101, the world builder): one master in the main checkout,
  two children in worktrees. The ledger is `docs/regents_rule/FOLLOWUP_RUN.md`; the rules are `MASTER_RUN.md` §1, §3,
  §4, §5.
- `main`: step 101 committed (`54c7ecb4`); B1 merged as step 102 (`cf259946`). The whole unit suite on `main` after
  the merge: **5228/0** (lints, engine errors, leaks ok). Pushed.
- The play database `regents-rule` was last published by the armor run; B1 is client-only (no publish needed).
- M1 done: Fowl Play 2815/0, DiscGolf 2605/0, Fishing 3309/2 (its held-items grip suite: the rod up to 33 cm into
  the body; the grips are Luke's). Each republished with `--codegen`, bindings committed and pushed.

## This session
- Step 101 committed and pushed (Luke's yes).
- Lane A (`lane-a`, Opus 5.5 high) and Lane B (`lane-b`, Opus 5.5 medium) started, each with its whole list.
- B1 (step 102): `RegentsAbilityBar.ability_words` says a hit's slow, shove and every-foe sweep, from the data
  (`hit_words`, `status_words`); `bar_lab.tscn` shows a words panel; `regents_bar` 165/0. Rule line in
  `regents-genre.md`; the shove's wording question in `WAITING_ON_LUKE.md`.

## Next, in order
1. Lane A's A1 (the bow's Q, an option and the ult pressed by a real client in `combat_playtest.sh`), then A2 (the
   practice armor 40067/40068 removed, legs on real pieces, re-bake): merge each by `MASTER_RUN.md` §5.
2. Lane B's B2 (Bolt's cast flash, Meteor's ring in fire, others' missile lighter): merge by §5.
3. M9 on `main`: unit, `cargo test`, wasm, integration ONCE, combat / caster / spells_seen / armor_seen playtests;
   publish the play database; the final HANDOFF; archive both children, remove their worktrees and branches.

## Waiting on Luke
- `docs/regents_rule/WAITING_ON_LUKE.md` §1-§2 (unchanged by this run except: how a shove is worded, m/s or meters).
- Not in this run: armor's traits, parts and numbers; the real ability content; the UI rebuild; towns S1-S8; the
  server spawning the world builder's NPCs.

## Watch out
- The bow's skills are worded as melee on the bar ("A strike in front of you ... reaching 15.0 m"): older than B1,
  recorded in PROGRESS 102, not in this run.
- Fishing needed a Godot `--import` before its unit suite (`RollComponent` from template 1.8.x); its first publish
  failed a 3 s server ping under load and passed on retry.
- `docs/HANDBOOK.md` is the template's: never edited here.
