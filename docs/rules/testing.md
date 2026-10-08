# Testing: every layer, with why it exists
The full verify loop moved from AGENTS.md (REVIEW 0.23.1 C1); AGENTS.md keeps the commands.
docs/HANDBOOK.md section 10 is the human version.

```bash
# Rust type-check against the real target. `module.rs` is wasm-gated, so a BARE `cargo check`
# skips every table and reducer — always pass the target. This is the one that counts.
cd server && cargo check --target wasm32-unknown-unknown

# Rust golden harness (native, no server needed)
cd server && cargo test --test golden          # add -- --nocapture to see per-case max_err
cd server && cargo test --test challenge       # Rust half of the validator parity pair
cd server && cargo test --test level --test fishing --test fight   # the lakeside bake, fishing's
                                               # rules, THE FIGHT (+ its golden file; see below)

# Godot (headless) — lint + binding contract + golden + unit tests.
# Fails on unexpected engine/script errors too, not just failed checks (DECISIONS #42).
GODOT=<path> ./tests/run_tests.sh

# Publish the module (and, with --codegen, regenerate the client's bindings) — one command.
# `--fresh` wipes the data (a table changed shape). DB=<name> for another database.
# THE OWNER IS ON WINDOWS: give them `tools\publish.cmd` and `tools\run.cmd tests\<suite>.sh`
# (Git Bash underneath; tools/local.env holds this machine's GODOT), never a bare `./x.sh`.
# --codegen reads the schema of `umf` (the module's name) and refuses any other DB: to change the
# bindings, publish `umf` (adding a table keeps its data; changing a table's shape needs --fresh).
GODOT=<path> ./tools/publish.sh [--fresh] [--codegen]

# Server reducers — the ONLY automated coverage of module.rs (DECISIONS #43).
# Needs `spacetime start`; republishes with --delete-data. EVERY server suite does, on the TEST
# database `umf-test` (DECISIONS #154): `DB` defaults to it and `UMF_DB` carries it to every Godot
# process the suite starts. `umf` is the owner's play database; a lint in run_tests.sh stops a
# suite naming it. Needs GODOT too: it plays fights through the client's simulation.
GODOT=<path> ./tests/integration_test.sh

# END TO END — a real client against the real module (DECISIONS #51). Run this before
# claiming anything works: it is the only layer that exercises BSATN, the SDK adapter and
# the generated bindings together, and it has found bugs that passed all three other layers.
GODOT=<path> ./tests/e2e_test.sh

# TWO clients at once. Distinct identities, mutual visibility, seeded world content
# (DECISIONS #62). Two clients sharing one identity raise no error anywhere and pass every
# other suite, so this is the only place that failure mode is visible.
GODOT=<path> ./tests/multiclient_test.sh

# MOVEMENT FEEL: scripted keys through the real input path in the real fishing scene, at
# several simulated latencies; and a walker + observer pair for remote smoothness
# (DECISIONS #79). Run both after ANY change to movement, input, the adapter or the tick.
GODOT=<path> LATENCIES="0 100 200" ./tests/playtest_test.sh
GODOT=<path> ./tests/remote_playtest.sh

# THE GAME, PHOTOGRAPHED: SHOTS=<dir> plays it in a WINDOW (at 0 ms) and saves a picture of every
# moment in <dir> (grip_pictures/ is not committed): LOOK at them after anything visual changes.
# THE GAME, PLAYED. Walks from the lakeside's spawn to the end of the dock on the movement keys,
# aims (and turns to face the aim), casts with the cast button, sets the hook, FIGHTS the catch in
# on the real buttons and the mouse wheel — which the module replays — then reads the standings
# and shops, while a SECOND client (fishing_observer.gd) checks it saw the turn, the cast, the
# float and the catch. Run it after any change to input, the camera, presentation or the genre's
# own verbs: it is the only layer that fails when the game stops being playable while every
# reducer still works.
GODOT=<path> ./tests/fishing_playtest.sh

# THE FRONT DOOR. The connect screen and Esc menu driven with typed keys and clicks: a bad
# address, a dead port, the wrong kind of server, a real connect, disconnect and back in, on a
# FRESH INSTALL (DECISIONS #122-#126). Run it after touching boot, the adapter's connection
# path, MouseCapture or foundation/ui/.
GODOT=<path> ./tests/connect_playtest.sh

# THE BUILDS. Exports both presets, reads what each pack contains, runs the client against the
# module and the server through the whole sidecar suite (#134). Needs the export templates.
GODOT=<path> ./tests/export_test.sh

# THE LOOK: checks that need pixels, so it opens a small window (every other layer is headless,
# and the headless renderer draws nothing). Foliage lit the same from both sides (#141), the
# grass's colour (#146), the lake's depth (#150), the grip preview's pictures (#157), F11 (#148).
GODOT=<path> ./tests/render_test.sh
# or via Godot MCP: run `tests/test_runner.gd` headless with `--path . -s tests/test_runner.gd`

# Sidecar (dedicated-server export or from source)
godot --headless --path . -- --world=1

# Module build/publish (needs the wasm32-unknown-unknown target and a running `spacetime start`)
cd server && spacetime build && spacetime publish umf --server local

# Codegen (after publish). The config step replaces the editor dock; cli.gd refuses without it.
# The SECOND --import is not optional: it registers the generated `class_name`s in
# .godot/global_script_class_cache.cfg. Skip it and the SpacetimeDB autoload fails to parse
# with `Could not find type "UmfModuleClient"`.
godot --headless --path . -s tools/codegen_config.gd
godot --headless --path . --import
godot --headless --path . --script res://addons/SpacetimeDB/cli.gd
godot --headless --path . --import

# Smoke test against a live server: expect CONNECTED → local entity: N → world ready
godot --headless --path .
```
Golden output must read `max_err=0.000e+00` on every case on both sides. A non-zero value under tolerance is a parity bug, not a pass — do not widen the tolerance.
