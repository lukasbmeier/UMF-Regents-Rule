# S1b: PER-ROLE POOLS
Branch `claude/s1b-role-pools` (from `main` 4c61fc11, `main` 0bc287e1 merged in). Not pushed. Edited by the master's leave:
`combat_component.gd` (on_slot and the press's gate), `ui/ability_bar.gd` (one line), `ui/abilities_window.gd` (the kit
it reads), `ui/station_window.gd` (`refresh`'s early-out); nothing else under `ui/`.

Built:
- THE MODEL (content, baked): every role's abilities stay in the kit's one `skills` list (so lookups, locks, on-hit effects
  and the referee work unchanged); a role CLAIMS its own (`KitRole.skills`); a skill no role claims is every role's; no
  role claiming any is one pool, as before (the staff, the foes; the axe and the bow have no roles: Luke's "the axe has
  none yet", no shaped handle gives them one). `KitDef.for_role(role)` is the kit as that role sees it (its pool, its
  hits; the kit itself when roles claim nothing); `has_role_pools`; validation per role (one Q, at most one F each; a
  skill claimed once, and the kit's). The build (`server/build/regents.rs`) bakes `KitSeed.role_skills` and checks the same.
- THE SERVER (`genre/regents/mod.rs`): `in_pool`, `pool_slot`, `has_ults_for`, `own_picks`, and `slot_refusal_for`,
  `pick_refusal_for`, `change_refusal_for` (the old ones are role 0: any pool). `regents.rs`: `need_slot` gates by the
  wielded weapon's role (`role_of`), `choose_pick` and `change_pick` by the chosen item's (`pool_role_of`: its parts' handle).
  A skill of another handle's pool: "not this weapon's: its handle gives other abilities". No schema change.
- THE CLIENT: `RegentsItemLevel.own_picks` (the twin) applied in `bar`, `slot_refusal`, `pick_refusal`, `open_picks`,
  `change_refusal`; `CombatComponent.pool_kit()` (= `kit.for_role(role())`) for `on_slot` and the press's gate; the bar's
  model and the abilities window read the role's view.
- PICKS PLAYERS HOLD TODAY (from P1's one sword pool): a stored pick of an ability outside the item's role's pool reads as
  EMPTY: it does not fire, the pick is open to choose again FREE (not a paid change), nothing crashes. So a plain-grip sword
  keeps Flurry, Hamstring Cut and Execute; a crossguard or banner sword that took them gets those picks back to choose from
  its own set; anyone who took Shield Bash as an option on a plain grip gets that pick back (Shield Bash is the crossguard's Q now).
- CONTENT (sword; placeholders, P1's rules): the plain grip LUNGE (Q), Flurry, Hamstring Cut (options), Execute (ult), all
  P1's or the old; the crossguard SHIELD BASH (Q, P1's, moved from an option), Charge, Hold the Line (options), Bulwark (ult);
  the banner SWIPE (Q), Shoulder Check, Banner Sweep (options), Banner Storm (ult). New stand-ins, each `(placeholder)`,
  PLACEHOLDER in its notes, existing atoms only (a judged sweep, Hits All, a lunge, a push, a slow), drawn by `SwingTrail`,
  their clips and recoveries in `anim/adventurer.tres`:
  40051 `ability/sword_charge.tres`, 40052 `sword_hold_the_line.tres`, 40053 `sword_bulwark.tres`, 40054 `sword_swipe.tres`,
  40055 `sword_shoulder_check.tres`, 40056 `sword_banner_sweep.tres`, 40057 `sword_banner_storm.tres`. No new spell.
- THE WORKBENCH'S LOOK: `RegentsStationWindow.refresh` stops early when what it reads (the station, its pick, the work
  going, the grade picks, every bag stack's row, item, count and data) is as last time and nothing asked for a redraw;
  the order board always looks. The 4 ms check stays.

How to play it: re-hilt a sword at the workbench (crossguard or banner grip); its bar's Q is that handle's (Shield Bash /
Swipe), its picks at 5, 12 and 20 offer that handle's set only.

Tested:
- Native `each_role_of_a_weapon_its_own_pool`: each handle's Q; NEGATIVES: Lunge refused on a crossguard, Shield Bash on a
  plain grip, Flurry no crossguard pick, Charge no banner pick, Execute no crossguard ult; picks kept from the one pool read
  as empty and do not block or fire; a kit with no role pools (staff, axe, bow) answers exactly as before for any role.
  MUTATION: `in_pool` answering yes to all fails it. `item_levels_and_picks` counts a base, options and an ult per role.
  `cargo test` green, wasm clean.
- Unit `regents,regents_bar,regents_vfx,regents_wardrobe,regents_figure,content` 2467/0 after merging `main`: each handle's
  view has four of its own and NEGATIVE none of another's, the three Qs, stale picks free, a kit with no pools its own
  view; the workbench's unchanged look stops at its inputs, and NEGATIVE a bag change is seen and redrawn (fails without
  the early-out: no look is ever skipped). The sword's checks moved deliberately to twelve skills in three pools.
- `combat_playtest.sh` 144/0 (before merging): the roles leg now presses Q on each re-hilted sword through a real client
  and referee: Lunge, Shield Bash (placeholder), Swipe (placeholder), each on the bar and taken by the server, none refused.
  After merging `main` (W3's doll in): 142/0, the same three Qs taken.
- Integration legs WRITTEN (not run, M9): Lunge refused on the crossguard sword; Flurry refused as its pick, Charge chosen.

Needs on merge: re-bake. No codegen.
Placeholders made: the seven abilities above (names, numbers, what each does: Luke's rewrite, ABILITIES_PREP.md section 9).
For Luke: the axe and the bow keep one set each (no shaped handle gives them a role: his "the axe has none yet");
per-role sets come to them when a handle does. The abilities window's footnote still says the staff's Blink stands in on F
(stale since S4; the window is W3's).
For the rules/handbook: regents-genre.md: "EACH HANDLE ITS OWN SET (S1b): a role claims its skills (`KitRole.skills`); the
gates and the bar read the item's role's view (`KitDef.for_role` / `KitSeed::in_pool`); a stored pick outside it reads as
empty. A new role's set is content: claim the skills, give each a slot."
Left for later: the abilities window's footnote (W3), per-role sets for the axe and the bow when they get roles, the
draft's mechanics the stand-ins only imitate (a mend by a share, buffs, a taunt, a guard window, a health floor).
