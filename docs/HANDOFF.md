# Handoff — Regent's Rule, 2026-11-18 (steps 110-114: placeholder moves; Mixamo; the bowstring; shots off-target; the clip browser)

## Where it stands
- Steps 110-114 COMMITTED in one commit (f003e35a, plus this HANDOFF's); the push is Luke's (the session's permission
  check refused it). Left out on purpose: `docs/regents_rule/Regents_Rule_Collaboration.xlsx` (untracked, no step
  names it: Luke's?). 111: `retarget_mixamo.gd`, `game/regents/anim/mixamo_*.res`; 112: `bow_string.gd`; 113: the
  shot rule (`combat_component.gd`, `regents.rs`); 114: `motion_lab.gd` (the clip browser).
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
