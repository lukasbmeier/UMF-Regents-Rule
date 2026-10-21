# Handoff — Regent's Rule, 2026-10-21

## Where it stands
Step 15 (the friends' playtest fixes, chat, traits) is committed and pushed (`dc8f01a`; the session
workflow `0313513`, the template's `c6740ad` merged in `0ec76a4`). **Published** to the play database
`regents-rule` with `--codegen` (2026-10-21): Luke's friend needs a NEW EXPORT (older builds are
refused). Suites green at `dc8f01a`: unit 2327/0, integration 922/0, native all, the skilling
playtest (two clients) 60/0 and 7/0. The template is at `4883be6` (#273-#275), pushed.

## This session
- The friends' playtest: drops land 1.4 m ahead and your own stays put; no friendly fire or PvP;
  dying stops work (the "head nod"); a held jump hops again only once falling (template #274);
  bellows heat 50 a press. Chat (template #273). PROGRESS step 15.
- Traits (template #275; here: `game/regents/content/trait/`, wired in `server/src/game/regents.rs`,
  twins in `game/regents/combat/combat_component.gd`); `set_item_traits` (dev tools) to try one.
- Brought `GAME.md` and `.claude/rules/regents-genre.md` up to Luke's 2026-10-19..21 calls (mana on
  the Staff only, #7 and #22 settled, no global cooldown, the trait calls).

## Next, in order
1. Luke playtests step 15 (traits on a made tool, chat, the fixes).
2. `LOOT_AND_STYLES.md` §10 "Next" after traits: the meta telemetry rollup, then salvage and
   components, the reagent cost hook, the teleport spell. Or the materials deep-dive if Luke picks it.
3. Waiting traits: Keen (crits, Bleeding), Padded and Warded (armour), Reaching (a per-swing reach side
   table for the referee). Drops roll traits by grade once loot lines roll a grade (not built).

## Waiting on Luke
- His playtest of step 15; which comes next (telemetry or the materials deep-dive).
- Open items: #10 hosting, #12 day/night, the other skills' minigames, the bow's draw scaling.
- `LOOT_AND_STYLES.md` §11's four questions: §1-4 of its amendments answer them; confirm before asking.

## Watch out
- Uncommitted on purpose: Luke's own GRIP edits (`game/regents/**/*_grip.tres` and their previews,
  2026-10-20) and the adventurer AnimationSet and four texture `.import` files. Never restore, rewrite
  or commit them without Luke; `ship_template.sh` refuses while this repo is dirty, so ask him first.
- Tool traits (Steady, Springy, Gentle, Lucky, Prospector's) are proven by native tests only: their
  effect on a node's speed and depletion has not been seen in play.
- A referee claim in `integration_genre.sh` lapses in seconds: revoke, then offer and claim afresh
  before each step that needs one (the traits section does).
- The local SpacetimeDB was started from a session shell (`spacetime start`): if a suite says "No local
  SpacetimeDB", start it again.
