# Animation
AnimationSet, the generated tree, the driver, held poses, the upper body, IK, arms in the body. Moved verbatim from AGENTS.md (REVIEW 0.23.1 C1); the DECISIONS rows in each heading say why.

## ANIMATION RULES (DECISIONS #94-#98, #144)
- The `AnimationTree` is built by `AnimationTreeBuilder` from an `AnimationSet`. Never hand-author
  a graph, and never name a clip outside a set — gameplay asks for `locomotion.run`.
- `AnimationDriverComponent` is the ONLY writer of tree parameters, and animation never produces
  gameplay (hard rule 11).
- Library tracks are re-addressed to `Skeleton3D:<bone>` by the extractor; the driver roots the
  tree at the skeleton's parent. A library that plays nothing is usually a track-path mismatch.
- Re-addressing also has to carry the source nodes' TRANSFORM: rotation onto the parentless bones,
  scale onto every position track (an FBX is Z-up centimetres). `_run_pose_tests` measures the
  posed skeleton in metres and is what catches it (DECISIONS #99).
- To look at a character: `game/characters/character_preview.tscn` (F6), or
  `--shot=<path>` for a PNG of the viewport. `player.tscn` only ever shows the greybox capsule.
- `AnimationTreeBuilder.apply_clip` is the ONLY way a node is pointed at a clip, including a swap
  at runtime. A clip's speed and its loop are one decision: `use_custom_timeline` is how a clip is
  sped up, and it overrides the clip's own loop with the node's `loop_mode` (DECISIONS #103).
- Clip timings that fight the game's own numbers are fixed in the SET (`speed_scale`, fitted from
  `shared/movement_config.json`), not by editing the graph. The generator MEASURES a clip's
  authored speed off its planted foot; it does not take anyone's word for it.
- A strafing set blends on a Vector2 in the CHARACTER's frame, a forward-only set on a float.
  `AnimationTreeBuilder.is_strafing(set)` is the one place that decides which.
- A state travelled this frame does not appear in `get_current_node()` until the tree's next
  process tick, and re-issuing a travel restarts its cross-fade. The driver's `_asked` memory
  handles both; do not replace it with a raw `get_current_node()` read.
- A genre shows a STATE through the driver's HELD POSE (#144). `hold_pose(semantic, weight, at)`
  is called every frame from state it reads: `at` < 0 loops the clip; 0..1 freezes it at that
  fraction, which is how a rod's heave is scrubbed. `release_pose()` lets go, and
  `play_action(semantic)` fires a genre's own one-shot. The pose lets go while the body moves.
- A one-shot that fully covers the body stops Godot processing the state machine under it, so a
  travel asked for meanwhile lands when the one-shot ends. A test that revives after a
  full-body action waits for the action to finish.
- THE UPPER BODY (#158): `play_upper(semantic)` fires a one-shot filtered to
  `AnimationTreeBuilder.upper_body(set)` (the set's `upper_body_filter`, else the chest, arms and
  fingers): drawing or stowing while the legs walk. Moving does not cancel it. It sits over the
  pose and under hit and action. Prove a filter by lockstep (two characters, one firing): a
  walking character's legs move in the sword clip too. Once an action or a hit covers the whole
  body, the upper-body one-shot is ended (`_end_covered_upper`): Godot stops processing what is
  under a full-weight one-shot, and the rest of a draw played after the cast (#160).
- A hand on a moving part is IK, not a clip. A looped clip cannot know where a reel's handle is
  (`FishingRod.set_hand_on_reel`: `TwoBoneIK3D` on a wrist target clamped inside the arm's
  reach). IK only moves bones while the skeleton updates: a probe that pauses the
  `AnimationPlayer` sees nothing, so it sets `speed_scale = 0` instead. Point the ELBOW (the
  pole) from the BODY, never from the held item: a pole in the rod's frame turned with each refit
  of the grips and drove the forearm through her waist (#162). The aim suite measures the arm
  against the torso as drawn.
- TEST WHAT CHANGED: run the suites a change touches (and its negative), not every layer each
  round; offer a full sweep before a commit.
- ARMS IN THE BODY (#163): judge clipping on the SKIN (`SkinClearance`), never on bone capsules
  alone (a corseted waist read 2.3 cm clear with a forearm through it). A new animation, item or
  look runs the `arms` suite; an animation whose own off hand is not on the item goes in the
  item's grip file, Off hand (`ItemGrip.off_hand_animations`, #172). Depth limits are calibrated on
  what Luke called right: do not tighten them to catch a pose, add a precise check for it instead.
- THE OFF HAND (#172) is grip data run by `OffHand` (a tool script): `HeldItem` and the preview
  call the same code. Its point is a node in the item's scene BY NAME (it may move: the rod's
  `OffHand` is moved onto the turning handle at runtime), present in the scene so the editor has it.
