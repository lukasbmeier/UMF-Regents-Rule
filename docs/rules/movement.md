# Movement, input and facing
The movement model, Tier A trust, gaits, facing and the input path. Moved verbatim from AGENTS.md (REVIEW 0.23.1 C1); the DECISIONS rows in each heading say why.

## MOVEMENT RULES (DECISIONS #80-#86)
- With a collision resolver the world is the ground; `ground_y` is only the resolver-less plane.
  Call `push_input` inside the physics tick: `move_and_slide` takes the render delta anywhere else.
- Movement tunables live in `shared/movement_config.json` ONLY (client via `MovementConfig.shared()`,
  server via build.rs). Changing the model: new golden file, NumPy mirror with GDScript's f64
  scalar products, old files byte-identical.
- `.tscn` basis is serialised ROW by row. Probe new level geometry through the engine.
- Patch files as bytes with LF; Windows `write_text()` writes CRLF (#87).
- The input `seq` is per ENTITY, not per process (#149). A restarted client carries on from the
  `last_processed_seq` its row holds, because `submit_input` drops anything at or below it.
  Nothing may ever LOWER that count, or a live client's frames drop the same way.
- A claim outside the trust envelope is clamped AS A WHOLE: height scales with distance (#149).
  Clamped apart, a far claim's drop was taken almost in full, and a player stood inside the ground.

## GAITS AND FACING (DECISIONS #100-#102)
- A plain key press RUNS. `walk_speed` is the SLOW gait (the `slow` modifier), `run_speed` is the
  default, `sprint_speed` the fast one; sideways and backwards are multiplied down.
- Those speeds are tied to what the animation clips are authored to travel at. Change one and
  regenerate the sets (`tools/animation_set_builder.gd`), or the feet will skate.
- Facing follows the camera only while there is movement input OR the frame is aiming
  (`InputFrame.face`, held by `LocalInputComponent.hold_facing(reason, on)`), and `module.rs`
  applies the same rule to the same frame. Change one side and you have changed the other.
- The camera's yaw and the body's heading are different numbers: free look freezes the second.
  `move_dir` is relative to the heading, never to the camera.

## INPUT AND AIMING RULES (DECISIONS #89-#93)
- `MouseCapture` (autoload) is the ONLY thing that writes `Input.mouse_mode`. Gameplay states an
  intent (`want_capture`); Escape, clicks and focus decide the rest. Never set the mode directly.
- The interaction ray starts at the camera and is extended by the camera's setback from the
  player; range is measured PLAYER to target so the prompt matches the module's `INTERACT_RANGE`.
- A genre claims the interact key with `InteractionComponent.interact_handler` (return true when
  handled) from its own `_on_bound`. Never edit the foundation's `interact` for a genre verb.
- A reducer the player triggered must surface its Err. A press that silently does nothing is the
  bug this whole section came from.
- `Interaction.interact_requested` fires on every press before the verb runs; presentation hangs
  off that, never off the reducer's answer (ANIMATION_SPEC section 2).
