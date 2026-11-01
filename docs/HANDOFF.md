# Handoff — UMF Template, 2026-10-31 (1.6.7: death stops a swing, a hit-stop, two action slots)

## Where it stands
**1.6.7** committed and pushed (`8178aa7`, DECISIONS #301), merged into Regent's Rule only; NOT yet into Fishing,
Fowl Play or DiscGolf. Client only: restart a game; nothing to republish. Suites here: unit 2314/0 (the animation
and animation-scene suites hold it); three mutations of the driver, each caught by its own check.
1.6.6 (#300) is in all four games (the referee session).

## This session (Regent's Rule's combat feel, Luke's feedback 4098/4099; his call: the foundation's part here)
- `AnimationDriverComponent._on_died`: both action slots and the upper-body one-shot fade, a commitment ends,
  held poses go: a body that dies mid-swing falls at once (it fell under the swing, after the clip).
- `hold_still(seconds)`: the tree is not advanced (an advance of 0 re-blended and the pose crept 0.001 rad).
  Tested by the clip's `current_position`: the feet (ground) and head (look) keep moving by design.
- The graph's second action slot (`action2` over `action`, 18 nodes): `_fire_action` takes the other slot when
  one plays and fades the old one out: swing follows swing as a cross-fade.
- `tests/suites/sdk_patches.gd.uid` (1.6.6's file, its uid never committed) went in with 1.6.7.

## Next, in order
1. Merge 1.6.7 into Fishing, Fowl Play and DiscGolf (by hand or `ship_template.sh`), run each unit suite, push.
   Fishing's `fishing_animation_scene.gd` uses the driver: watch its one-shots.
2. Offer the btree patch upstream (plaught-armor SDK): outward-facing, ask Luke first.
3. A region referee loads the whole level (~375 MB); the 2-3 s start-up stalls.

## Waiting on Luke
- How many strips the expanse runs by default (three hold at 43.7 of 50 ms; four have room).
- Whether to send the SDK fix upstream. The bandwidth budget; the server's levers at 300.

## Watch out
- `_fire` on one action slot is internal: every action goes through `_fire_action` (rules/animation.md).
- The sweep's test database `regents-rule-sweep-test` is left on the local server (the worktree is removed).
- `run_tests.sh` passes no arguments: run one suite with `godot --headless --path . res://tests/test_runner.tscn -- --only=x`.
- The runner prints failures to stderr: grep "failed" counts, not "FAIL" on stdout.
- Heredocs through the Bash tool mangle backslashes: write patch scripts with the file tool.
