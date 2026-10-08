# The sidecar and NPC brains
SERVER_AUTHORITY worlds, the headless authority process, and the brains it runs. Moved verbatim from AGENTS.md (REVIEW 0.23.1 C1); the DECISIONS rows in each heading say why.

## SIDECAR / SERVER_AUTHORITY (DECISIONS #106-#108)
- The authority runs the SAME `MovementModel` and the SAME `move_and_slide` resolver as client
  prediction, through `SpaceTimeMovementComponent._step`. Never write a second implementation:
  the symptom of drift is constant correction, not an error.
- `NetConfig.authority_process` is what makes a process an authority. It changes exactly two
  things: every entity binds SERVER_AUTHORITY, and the movement component also asks for
  `input_queue`.
- A row's `grounded` flag is a claim, not physics. Nothing sleeps until a simulated frame agrees.
- A write the module refused is owed again. `take_authority_write()` clears the flag
  optimistically, so whoever sends it must re-mark on failure (#108).
- A sidecar is nobody until `register_authority` names its identity: writes are refused AND
  `input_queue` is invisible to it (its RLS filter joins on `authority`). It prints its identity
  on connect for exactly this reason. ROLE_SIDECAR may not take `world_id = 0`.
- `tests/sidecar_test.sh` is the layer that proves any of it. Run it after touching
  `sidecar/`, `SERVER_AUTHORITY`, `write_movement_batch` or the authority reducers.

## NPC BRAINS (DECISIONS #109-#111)
- A brain returns an `InputFrame`, never a position, and it goes through
  `push_authority_input` — the same queue a player's frames use. Never move an NPC directly.
- `move_dir` from a brain is a WORLD direction. Test a steering change at a non-zero yaw or the
  body-frame version of the bug is invisible.
- `think()` runs at `think_hz`, `frame()` every tick. Expensive questions go in `think`.
- `EntityDefinition.brain` is a STRING resolved only in the sidecar (`NpcBrainComponent.make_brain`),
  because `game/` may not reference `res://sidecar`. The sidecar attaches the component with
  `SpaceTimeEntity.add_runtime_component`.

## NPC BRAIN MEMORY (DECISIONS #135)
- A brain's `save_state()`/`load_state()` hold DECISIONS (home, goal, target), not countdowns.
- `npc_brain` is visible only to the world's authority; the publisher (world 0) cannot read a
  sidecar world's brains, so the sidecar test proves persistence by restarting the sidecar.
