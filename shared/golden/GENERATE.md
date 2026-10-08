# Regenerating golden vectors

Vectors are produced with NumPy float32 arithmetic mirroring `movement_model.gd` op-for-op.
Whenever `movement_model.gd` changes, update `simulate()` below to match, re-run, and commit the
new JSON with the change. (`server/src/sim.rs` is a frozen gravity-only twin; the Rust golden test
only guards against accidental edits to it and reads the same files — a new movement branch does
not need a Rust change. Challenge validators DO need Rust twins and their own golden files.)

```python
import json, numpy as np
f = np.float32
cfg = json.load(open("../movement_config.json"))
G = f(cfg["gravity"]); JV = f(cfg["jump_velocity"]); GY = f(cfg["ground_y"])
DT = f(1.0/60.0)

def simulate(s, inp):
    pos = np.array(s["pos"], dtype=f); vel = np.array(s["vel"], dtype=f); grounded = s["grounded"]
    if grounded and inp.get("jump", False):
        vel[1] = JV; grounded = False
    if not grounded:
        vel = vel - np.array([f(0), G, f(0)], dtype=f) * DT
    pos = pos + vel * DT
    if pos[1] <= GY and vel[1] <= f(0):
        pos[1] = GY; vel[1] = f(0); grounded = True
    return {"pos": [float(x) for x in pos], "vel": [float(x) for x in vel],
            "yaw": s["yaw"], "grounded": bool(grounded), "move_state": s["move_state"]}
```

Case schema: `initial`, `inputs[]`, `expected_final`, optional `expected_at{frame_index: state}`.
Tolerance stays at `1e-5`; the goal is `max_err = 0`.
