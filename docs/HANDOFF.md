# Handoff — Regent's Rule, 2026-11-18 (steps 110-114: placeholder moves; Mixamo; the bowstring; shots off-target; the clip browser)

## Where it stands
- Step 109 committed and pushed (a5bc9099). Steps 110-114 built in the main checkout, UNCOMMITTED (see git).
  111: `game/regents/tools/retarget_mixamo.gd`, `game/regents/anim/mixamo_*.res` + `ATTRIBUTION.md`, `motion_clip.gd`
  LIBRARIES, the lab's `held=` / `scale=`. 112: `game/regents/combat/bow_string.gd`, a `String` node in `yew_bow.tscn`.
  113: `combat_component.gd`, `combat_look.gd`, `server/src/game/regents.rs` (`loose_arrow`, `cast_spell`), the
  `aim_arc_deg` rule's words (baked), `integration_genre.sh`. Several steps share files (`regents_motion.gd`,
  `combat_component.gd`): stage by path. 114: `motion_lab.gd` (the clip browser), `bow_string.gd` (refits).
- Suites after 113: the unit suite and lints 5442/0; `cargo test` (28) and the wasm check green; integration 1712/0.
  After 114: the unit suite and lints 5453/0.
- The play database `regents-rule`: published after 113 (no schema change: restart the game).

## This session
- Answered the tank bow; Luke's calls (GAME.md): MIXAMO CLIPS (private repo), THE BOWS BY ROLE (bow / longbow-plated /
  shortbow are the bow's roles, as grips are melee's; staves likely the same), THE WAY YOU FACE (CHANGED).
- 111: 170 Mixamo clips on our skeleton; great sword swings, and the yew bow swung through them at 1x and 1.4x.
- 112: the bowstring drawn into a V to the fingers with an arrow on it, every client, from the draw pose.
- 113: a shot at a Tab target you do not face flies to the crosshair (client and server), never refused.
- 114: the motion lab's CLIP BROWSER (any clip, any held item, any size). Luke's staff roles: KEEP THE SHAFTS (GAME.md).

## Next, in order
1. Luke plays: the bowstring (hold LMB with the yew bow); shooting a target behind you; the bow sheets.
2. The three bows as roles (the bow's `KitDef.roles`, the longbow at 1.4x and a shortbow as items with a `String`
   node, carving): Luke's numbers, recipes, names. The tank bow's melee from the great sword set (`adventurer.tres`).
3. The staff's shafts (GAME.md, THE STAFF'S ROLES): ward = melee string + metal part, censer = quick weak bolts; specifics next.
4. 110's live pull and lift check; TEMPLATE work (PROGRESS 108, 107).

## Waiting on Luke
- The bows' and shafts' numbers, recipes, names, spells per role; tap swings or shoots. A Mixamo longbow pack.
- 110's: which moves stay; the spin; the back flip as a backward roll; a real blade waltz.

## Watch out
- NEVER leave Mixamo FBX in `game/anim/_import/`: the export filter does not exclude it.
- `--script` runs have no autoloads: a look check with the game's classes needs a scene.
- A changed `.tres` rule or content needs `tools/bake_content.gd` before `cargo` builds (build.rs refuses a stale bake).
- `docs/HANDBOOK.md` is the template's: never edited here. Heredocs with apostrophes break the Bash tool: patch files.
