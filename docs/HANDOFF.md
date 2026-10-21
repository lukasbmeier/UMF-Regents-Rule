# Handoff — Regent's Rule, 2026-10-21

## Where it stands
Step 15 (traits, chat, the friends' playtest fixes) is committed (`dc8f01a`, 2026-10-21) and the
template's half (#273-#275) is shipped. **Not committed**: edits to the nine weapon and tool grips and
their previews (`game/regents/**/*_grip.tres`, `*_grip_preview.tscn`, saved 2026-10-20 20:26; the
iron sword's grip went from 168 lines to 21), the adventurer's AnimationSet and four texture imports.
Nobody has said whether these are wanted.

## This session
- Seeded by the switch to one session per sit-down (no game work): `CLAUDE.md`,
  `.claude/rules/regents-genre.md` (in `regents.paths`), this file, `.claude/settings.local.json`.

## Next, in order
1. Luke tries step 15 (traits, chat, the playtest fixes); settle the uncommitted grips with him.
2. `LOOT_AND_STYLES.md` §10 "Next", after traits: the meta telemetry rollup, then salvage and
   components, the reagent cost hook, the teleport spell.
3. Step 15's waiting traits (Keen, Padded, Warded, Reaching) need crits, armour or a reach side table.

## Waiting on Luke
- His look at step 15; whether the uncommitted grip edits are his (keep and commit) or an editor's
  re-save (restore).
- Open items #7 loot, #10 hosting, #12 day/night, #22 handles and kits; the other skills' minigames.
- `LOOT_AND_STYLES.md` §11 asks four questions back (cast queue, hit chance, multi-contact bodies,
  quality grades): check whether they were answered in step 9-15's notes before asking again.

## Watch out
- `ship_template.sh` refuses to run while this repo is dirty: settle the grips before the next
  template release.
- `game/anim/humanoid.tres` and `project.godot` had editor re-saves (the same animation set
  reordered; one blank line): restored to the committed copies, which are the template's files.
