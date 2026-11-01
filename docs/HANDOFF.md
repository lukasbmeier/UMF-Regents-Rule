# Handoff — UMF Template, 2026-11-01 (1.7.0: statuses that stack; 1.6.7: death stops a swing)

## Where it stands
**1.7.0** committed and pushed (DECISIONS #302): a table added (`status_effect`) and a reducer (`set_effect`):
games publish with `--codegen` (data kept). **1.6.7** (#301) before it. Both merged into Regent's Rule only;
NOT yet into Fishing, Fowl Play or DiscGolf. Suites here: unit 2324/0, native 93/0, integration 667/0, e2e
47/0 + 11/0; mutations: three of the driver (1.6.7), two of the effects (the client's bound, `stricter`), each
caught. `umf-template` published with codegen; bindings committed.

## This session (Regent's Rule's combat overhaul; Luke: the foundation's part here, then pulled)
- 1.6.7 (#301): `AnimationDriverComponent`: death fades both action slots and the upper one-shot; `hold_still`
  (a hit-stop: the tree not advanced); a second action slot (`action2`), so swing follows swing as a cross-fade.
- 1.7.0 (#302): EFFECTS, statuses alongside the state: `status_effect` (public, a cell and follow table),
  `effect_expiry`; `add_effect_internal` / `remove_effect_internal` / `set_effect`; `on_effect_changed`; the
  bound is the STRICTER of state and effects (`status::stricter`, `effect_limits`, an effect under the grace not
  counted yet); `require_can_act`, `is_targetable` and the new `is_hittable` read both; `StatusComponent`
  keeps them (`effects()`, `has_effect`, `can_act()`, `effect_changed`) and predicts by the same stricter.

## Next, in order
1. Merge 1.6.7 and 1.7.0 into Fishing, Fowl Play and DiscGolf, `--codegen` each, run each unit suite, push.
   Fishing's `fishing_animation_scene.gd` uses the driver: watch its one-shots.
2. Effects' own presentation (a status's pose or tag shown as an effect) when a game needs it.
3. Offer the btree patch upstream (plaught-armor SDK): outward-facing, ask Luke first.
4. A region referee loads the whole level (~375 MB); the 2-3 s start-up stalls.

## Waiting on Luke
- How many strips the expanse runs by default (three hold at 43.7 of 50 ms; four have room).
- Whether to send the SDK fix upstream. The bandwidth budget; the server's levers at 300.

## Watch out
- Every action goes through `_fire_action` (rules/animation.md); a hit-stop is tested by a clip's
  `current_position`, not the bones (feet and head keep moving).
- The sidecar's referees pre-filter hittable by the STATE only; the module re-checks effects (`is_hittable`).
- The sweep's test database `regents-rule-sweep-test` is left on the local server (the worktree is removed).
- `run_tests.sh` passes no arguments: run one suite with `godot --headless --path . res://tests/test_runner.tscn -- --only=x`.
- The runner prints failures to stderr: grep "failed" counts, not "FAIL" on stdout.
- Heredocs through the Bash tool mangle backslashes: write patch scripts with the file tool.
