# Handoff — UMF Template, 2026-11-19 (1.8.5: a body says every hit; `hits_bodies`; branch claude/body-contacts)

## Where it stands
- 1.8.4 SHIPPED to the template's GitHub (main 9491439 = origin/main): a free colour in the picker (#316).
- 1.8.5 (DECISIONS #317) committed on branch `claude/body-contacts`, cut from main 9491439; not merged, not pushed,
  not shipped. Client and referee only: no republish, no codegen, no bake.
- Green: `bodies` 79/0; the full `tests/run_tests.sh` 2554/0 (no engine errors, nothing left at exit);
  `tests/content_test.sh` 18/0 (`hits_bodies` is not baked). 12 of the `bodies` checks fail on the 1.8.4 flight; each
  guard broken alone fails its own checks (no contacts read 8, no re-hit skip 3, no speed filter 5, push not counted 2,
  push not scaled by the bounce 2, contacts read before the forces 1, `_prev_vel` not kept 4, `hits_bodies` ignored 5).
  No server suite run: no server code changed.

## This session
- `foundation/physics/flying_body.gd`: `_prev_vel`; `_contacts` reads `state.get_contact_count()` first (speed =
  max(into, impulse / mass / (1 + bounce)), below `contact_speed_mps` skipped, `_hit_at` shared with the cast), then
  casts ahead; still AFTER the forces and ground drag (Luke's call); `launch` clears `_hit_at`; `make` honours
  `hits_bodies`.
- `foundation/content/body_def.gd`: `hits_bodies` (Its body, default true, not in `to_bake`).
- `tests/suites/bodies.gd` (`_run_contacts`, the roll check in `_run_flight`, `Hits`), `tests/fixtures/stop_forces.gd`.
- DECISIONS #317, CHANGELOG 1.8.5, HANDBOOK (Bodies: what counts as a hit), rules `sidecar_and_npcs.md` §BODIES and
  `netcode.md` (layers).

## Next, in order
1. Luke merges `claude/body-contacts` and ships 1.8.5 (`ship_template.sh`).
2. Each game pulls it. Regent's Rule: its shots (`MissileFlight`, contact speeds 1-2 m/s) now say hits they used to
   lose; recheck its "a shot stops where it touches" checks and the referee's contacts after the pull. DiscGolf: its
   discs report at 0.5 m/s and take the FIRST hit as the landing spot; run its `discgolf` suite after the pull.

## Waiting on Luke
- From before: strips per expanse; the SDK fix upstream; bandwidth budget; greybox humanoid roll default.

## Watch out
- Two bouncy bodies still read a little fast: Godot ADDS their bounces, the push is divided by 1 + this body's own
  (two 5 m/s balls of bounce 0.5 head-on read 6.7 each). Exact against a wall of no bounce (#317 "revisit if").
- A cast that starts against a surface (a body on the floor, even 5 mm off it) goes nowhere: the look-ahead is blind
  while a body touches something under its path; the step's contacts cover that.
- Godot adds two bodies' bounces (clamped to 1): a test that predicts a collision's outcome must use the sum.
- Nodes freed with `queue_free` keep their name until the frame ends: a new node of the same name is renamed
  (`@RigidBody3D@13`). Name test bodies uniquely if a message prints their names.
- From 1.8.3: a respawn (appearance row change) shows the appearance's pieces until a genre's component wears its own.
