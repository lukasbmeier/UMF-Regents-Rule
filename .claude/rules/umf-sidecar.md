---
paths:
  - "sidecar/**"
---
# The sidecar (the world's referee: authority only)

- Authority logic (NPC brains, hit resolution, spawn and loot rules, bodies in flight) lives ONLY
  under `sidecar/`, which the client export excludes. Nothing in `foundation/` or `game/` may
  reference `res://sidecar` (AGENTS.md rule 7b; lint-enforced).
- A genre's brains are `sidecar/npc/brains/<genre>/` (in that genre's manifest).
- Read `docs/rules/sidecar_and_npcs.md` before changing `register_authority`, owed writes, a brain's
  `think`/`frame`, or brain memory.
- The sidecar runs the same `movement_model.gd` as client prediction: a change to it ships
  regenerated golden vectors (rule 7).
- How a referee is started (an editor run starts one; `tools/host.sh` for a hosted world) and why an
  out-of-date one is refused: DECISIONS #272.
- Test with `tests/sidecar_test.sh` (a real sidecar, an unregistered control, a restart) and the
  playtest of whatever the referee moves.
