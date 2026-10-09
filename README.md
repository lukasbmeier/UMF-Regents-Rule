# Universal Multiplayer Foundation

Godot 4.7 (strictly typed GDScript 2.0; 4.6 is the floor) + SpacetimeDB 2.10 (Rust module) + an optional headless-Godot **sidecar** as motion/NPC authority. A genre-agnostic multiplayer core — movement with client-side prediction, state sync, health, inventory, sessions, interaction — for building MMOs, survival games, party games and more on one codebase. Godot's high-level multiplayer is not used; SpacetimeDB is the authoritative state.

**If you are a person, start with [`docs/HANDBOOK.md`](docs/HANDBOOK.md). If you are an AI agent, start with [`AGENTS.md`](AGENTS.md).**

## Documents
| File | Read when |
|---|---|
| [`docs/HANDBOOK.md`](docs/HANDBOOK.md) | **start here** — every system in plain terms, how players load, the server, what you can change and what each change takes |
| [`AGENTS.md`](AGENTS.md) | before touching anything — rules, verify loop, file map |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | you need the why: principles, node tree, data flow, contracts, SDK/2.10 facts |
| [`docs/PHASE3_SPEC.md`](docs/PHASE3_SPEC.md) | the entity framework's tasks and acceptance criteria (done but for Task 1's `action_request`) |
| [`docs/PHASE4_SPEC.md`](docs/PHASE4_SPEC.md) | after Phase 3 — prediction, reconciliation, full movement model |
| [`docs/SIDECAR_SPEC.md`](docs/SIDECAR_SPEC.md) | the headless-Godot simulation authority: trust model, reducers, runtime, deployment |
| [`docs/ANIMATION_SPEC.md`](docs/ANIMATION_SPEC.md) | animation contract, data-driven AnimationTree generation, visual feedback layer |
| [`docs/TEMPLATE_WORKFLOW.md`](docs/TEMPLATE_WORKFLOW.md) | turning the foundation into a template and starting new games from it |
| [`docs/CONTENT_TOOLING_SPEC.md`](docs/CONTENT_TOOLING_SPEC.md) | content as Resources, the Content Dock, workbenches and the Catalog, hot tunables, the admin panel; §9 is the order of work |
| [`docs/reviews/REVIEW_0.23.1.md`](docs/reviews/REVIEW_0.23.1.md) | the architecture review: B, C done in 0.24.0; D, E, F open |
| [`docs/GENRE_ADAPTERS.md`](docs/GENRE_ADAPTERS.md) | deciding whether something belongs in the foundation or a genre layer |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | before changing a design choice |
| [`shared/golden/GENERATE.md`](shared/golden/GENERATE.md) | changing the movement model |
| [`docs/CHANGELOG.md`](docs/CHANGELOG.md) | confirming which bundle version you hold (this is 0.25.0) |
| [`addons/README.md`](addons/README.md) | installing the SDK and running codegen |

## Layout
```
project.godot               the Godot client project IS the repo root
                            (autoload order = boot sequence; see AGENTS.md)
foundation/core/            SignalBus · ClockSync · EntityRegistry · EntitySpawner · SpaceTimeEntity
foundation/components/      SpaceTimeHealthComponent (one per Phase 3 task)
foundation/entities/        player.tscn (definitions: foundation/content/character/)
foundation/net/             SpaceTimeSync (SDK adapter) · NetConfig · RowEvent · ReducerRequest · SubscriptionSet
foundation/sim/             MovementModel · MovementState · InputFrame · MovementConfig
foundation/tools/           EditorScripts (config codegen)
tests/                      run_tests.sh (unit+scene) · integration_test.sh (server) · e2e_test.sh (client<->server) · multiclient_test.sh (two clients)
tools/                      codegen_config.gd (headless codegen config)
addons/SpacetimeDB/         vendored SDK
addons/godot_ai/            Godot MCP editor bridge (dev tool, not part of the foundation)
spacetime_bindings/         GENERATED, alias `Umf` — 26 files, committed
sidecar/                    (Phase 3) SERVER-ONLY authority code; excluded from the client export preset
server/                     SpacetimeDB module
  src/game/                 THE GENRE LAYER (fishing) — foundation never imports from here
  src/sim.rs                FROZEN twin + wire types; spacetimedb-lib only (DECISIONS #27)
  src/module.rs             tables + reducers, wasm32-gated (DECISIONS #27)
  src/lib.rs                crate root
  tests/golden.rs           golden harness
  build.rs                  shared/movement_config.json → movement_config.rs
shared/                     movement_config.json (single source of truth) · golden/*.json
```

## Status
| Phase | State |
|---|---|
| 1 Blueprint | done → `docs/ARCHITECTURE.md` |
| 2 Scaffold, event bus, SDK adapter, movement model, harness | **done and verified running** — golden 6/6 `max_err=0e0` on both sides, module publishes, client connects. Tier B proxy collision removed in favour of the sidecar |
| 3 Entity framework, base components, foundation additions | **Tasks 0, 2–10 done; Task 1 done for everything fishing needs.** Verified end to end against a live module |
| 4 Prediction & reconciliation | **done** — prediction and reconciliation by input seq, correction epochs, smooth remote interpolation, move states, slopes, flap/dash, predicted actions; verified by playtests at 0–250 ms simulated latency with jitter → `docs/PHASE4_SPEC.md` |
| 5 UI, animation/feedback layer, first genre | **fishing is playable with friends** — a connect screen and Esc menu, round results and a live leaderboard, a rod, float, water, splash and generated sounds, and export presets for a client build and a server build. Press Play in the editor, or `GODOT=<path> ./game/fishing/play_local.sh 2` |

## Play it

Once the module is published (`First run`, below), the fishing game runs straight from the
editor. `run/main_scene` is `game/fishing/lakeside_game.tscn` — the lakeside — so:

1. **Debug ▸ Customize Run Instances…** → enable multiple instances, count **2**.
2. Press **Play**.

Each window opens on the **connect screen**, with the server already filled in: type a name and
press Enter. Tick *Connect automatically next time* and later runs skip straight into the game;
**Esc ▸ Disconnect** brings the screen back. Each instance remembers its own name, because it
remembers it next to its own identity (DECISIONS #122).

Each instance claims its own identity automatically — that is editor-only behaviour in
`foundation/boot.gd`, and without it both windows would be handed the same entity by the server
and look like a single player (DECISIONS #61, #62). A fresh publish runs the lakeside with no
setup: the module compiles the level's bake in, and `use_level 0 0` (admin) switches a world to
the greybox test level and back (#138).

To look at the fishing presentation without a server — rod, cast, float, ripples, a catch
leaping, and the sounds — open `game/fishing/feel_preview.tscn` and press **F6** (C casts, N/M
the tell and the bite, 1-7 land something). To look at the characters,
`game/characters/character_preview.tscn`: UP/DOWN cycles the looks, L lines them all up (#139).

**To change how the rod sits in the hand**, open `game/fishing/rod_grip_preview.tscn` in the
editor (no F6 needed). A woman and a man stand there holding the rod: one grip serves every
look, and every look is one of those two bodies. Pick a **Pose** in the Inspector, select the
**Grip** node (in her hand), and move (W) or turn (E) it with the gizmo: both rods follow, and
`rod_grip.tres` is saved as you go. Idle, walk, run and sprint edit the grip they carry it in;
cast, waiting and heave edit the one they fish with. Each label says how far the reel is from
that leg in the frame shown and at its worst through the whole clip, which the game plays; it is
green only when the reel clears the leg by 2 cm all the way through. Tick **Play** to watch the
clip go round (untick it to edit). **Look** and **Beside** pick who stands there (#147, #152).

From a shell instead, which republishes from scratch and skips the 30 s lobby:

```bash
GODOT=/path/to/Godot_v4.7.1-stable_win64.exe ./game/fishing/play_local.sh 2
VIEW=--first-person GODOT=... ./game/fishing/play_local.sh 2
```

**Controls**

| | |
|---|---|
| `mouse` | look. The character turns to face the camera while it moves, or while you aim a cast — not while it just stands there |
| `WASD` | move — a plain press **runs** (5 m/s) |
| `Ctrl` | walk (1.2 m/s) · `Shift` sprint (8 m/s) · sideways and backwards are slower gears |
| `Alt` (hold) | free look: the camera turns, the character does not |
| `wheel` | zoom the camera in and out (in a fight: reel in) |
| `Space` | jump · `E` interact with whatever the crosshair is on |
| left mouse | **hold** to aim a cast — the ring shows where it lands, green where the server will take it — and let go to cast. When the float goes under, **click** to set the hook. In the fight: **hold** to load the rod, **let go** in the sweet spot |
| right mouse | put the rod down while aiming · in the fight, **hold** to give line when it runs |
| `wheel` / circle the mouse | in the fight, reel — any time, but it only wins much line when the fish is tired or resting (the reel's hub glows), or to take in the slack a pump made. Winding into a run costs line |
| `Q` | dash, if `dash_impulse` is turned on in `shared/movement_config.json` |
| `Esc` | release the mouse and open the menu; click in the window to take it back |
| `F11` / `Alt+Enter` | fullscreen, and back (also in the `Esc` menu). Playing inside the editor's game view, the window is the editor's: use the view's ⋮ menu (top right) → **Stretch to Fit** to fill it |
| `1` `2` `3` | between rounds, buy a better **rod** (reach, and more line per pump) / **reel** (a longer hook-set window, a faster crank) / **line** (holds heavier, snaps later) |

The cursor is captured while you play, and released whenever the window loses focus — so with
two instances open you just click into whichever one you want to drive (DECISIONS #89).

**To fish** (Fishing for Compliments' cast and fight, DECISIONS #136, #140): walk down to the
dock — or any shore — and hold the left button with the camera on the water. The longer you hold
the further it flies; the ring says where it will land and which spot that is (Dock End, Village
Shallows, Reed Bay, The North Drop, The Deep Hole each hold different things). The two good ones
are out of the starting rod's reach: the North Drop wants the Ash Rod, cast from the north shore,
and the Deep Hole the Yew Longrod, from Rocky Point's tip or the dock's end — the aim tells you when
one lies further out, and the shop which rod reaches it (#143). Let go to cast.
The float twitches as the bite comes; when it goes under, click. Then **the fight**: hold to load
the rod — your angler heaves it up and it bends — and let go when the ring round the catch glows.
It turns amber in the band, then pulses and grows in the sweet spot, and shakes if you have gone
too far. The gauge at the bottom right is the rod and the reel: the arc fills as you load, in the
same colours, and never shows WHERE the sweet spot is, only when you are in it. The reel's rim is
the line's tension (#144). Reel with the wheel any time: a fresh fish gives up little line and
strains it, and a tired or resting one comes in fast and easy — the hub glows when it pays (#145).
Pump greedily and a fish
RUNS: hold the right button to give line until it tires. Junk SNAGS: heave (hold) to set it free.
Anything heavier than your line is rated for is a DEADLIFT — the line is failing on its own, so
land it fast for double coins. If the server refuses a cast it says why on screen. A spot fished
hard bites slower, and grows back. A round is 30 s lobby → 3 min playing → 20 s results → 25 s
shop, on a loop; a fight still on the line when the bell goes plays out through the results.

**Swapping presentation** is a `.tres` edit, never code (#60):

| Want | Edit | Field |
|---|---|---|
| A different character model | `game/fishing/fisher_definition.tres` | `visual_variants` (one look per entity, by id) or `visual_scene` (+ `visual_offset`) |
| A new look | `tools/characters/make_looks.py` | the `LOOKS` table: head, pieces, skin, hair, colourway |
| First person | same file | `camera_rig` → `foundation/camera/first_person.tres` |
| Third person | same file | `camera_rig` → `foundation/camera/third_person.tres` |
| Camera feel (boom length, pitch limits) | the rig `.tres` itself | `CameraRigConfig` fields |
| A different animation set | `game/fishing/fisher_definition.tres` | `animation_set` |
| A model that faces the wrong way | same file | `visual_yaw_deg` (180 for the Quaternius rigs) |

**Animation** is a generated `AnimationTree`, never a hand-built graph. `game/anim/humanoid.tres`
maps semantic names — `locomotion.run`, `jump.land`, `react.hit`, `interact` — onto real clips;
`AnimationDriverComponent` reads the movement state and plays them, for remote players as well as
your own. To use your own character and clips:

```bash
# 1. put the library source in, extract it, delete the source (see game/anim/ATTRIBUTION.md)
godot --headless --path . --script res://tools/extract_animation_library.gd
# 2. fuzzy-match its clip names onto the semantic ones and READ THE REPORT
godot --headless --path . --script res://tools/animation_set_builder.gd
```

Then point `visual_scene` at the rigged model and `animation_set` at the generated `.tres`. Any
model whose skeleton uses the same bone names plays the same library; a rig from a different
family needs Godot's retargeting (`docs/ANIMATION_SPEC.md` §1).

**To see a character**, open `game/characters/character_preview.tscn` and press **F6** — no
server, no connection. `player.tscn` itself only ever shows the greybox capsule, because the
model is swapped in at runtime from the definition; this scene does that swap for you:

| Key | Does |
|---|---|
| `←` `→` | previous / next clip in the set |
| `C` | overlay the collision capsule the body actually uses |
| `R` | reload the definition from disk — edit the `.tres`, press R, see it |

It prints the head, pelvis and foot heights in metres, which is the quickest way to tell a
model that is the wrong way up or the wrong size from one that is merely posed oddly.

### Testing movement and latency

The fishing scene carries a **net overlay** (on by default when run from the editor):

| Key | Does |
|---|---|
| `F3` | show / hide the overlay |
| `F4` | cycle simulated round trip: 0 → 50 → 100 → 200 ms |
| `Shift+F4` | cycle simulated jitter: 0 → 20 → 50 ms |

Read it like this. **input ack** is how long the server takes to confirm an input; prediction
hides it, so movement should feel identical at 0 and 200 ms. **corrections** should stay at 0
while you just walk around; each is a glide, or a snap past 1 m. **remote** is how far in the
past other players are drawn, and it grows with measured jitter.

Simulated latency from launch instead: `-- --latency=150 --jitter=30` (round trip, and random
extra per direction). There's a jumpable step on the south side of the platform, for testing
standing on geometry the server can't see.

Automated, the same checks run as playtests against a live server:

```bash
GODOT=... LATENCIES="0 100 200" ./tests/playtest_test.sh    # movement feel
GODOT=... LATENCY=250 JITTER=80 ./tests/remote_playtest.sh  # how others look to you
GODOT=... ./tests/fishing_playtest.sh                       # plays the game: walk, aim, cast, catch
```

## Playing with other people

Everything above runs against `127.0.0.1`, which only you can reach. To let someone else join,
the SpacetimeDB host has to be reachable from their machine and the client has to be pointed at
it — nothing else changes, because the client never assumed it was local.

**On the machine hosting the game:**

```bash
spacetime start --listen-addr 0.0.0.0:3000
```

`0.0.0.0` rather than the default loopback is the whole difference: the default accepts
connections from that machine only. Then publish as usual (`cd server && spacetime build &&
spacetime publish umf --server local`), and open TCP 3000 to whoever is joining — a LAN needs
only the firewall rule, over the internet it needs a port forward or a tunnel. Find the address
with `ipconfig` (Windows) or `ip addr` (Linux); it is the one your friends can see, not
`127.0.0.1`.

**Build the game for them.** Friends do not need Godot, the repo or Rust — just the exported
client. With the Windows export templates for this Godot version installed:

```bash
godot --headless --path . --export-release "Windows Client" build/client/umf.exe
```

Zip `build/client/` and send it: `umf.exe` (the game, its pack embedded) and the Terrain3D library beside it (DECISIONS #185). The presets live in
`export_presets.cfg`; `tests/export_test.sh` builds both and checks what is in them (the
client never carries `sidecar/`, hard rule 7b). Or use **Project ▸ Export** in the editor.

**On each player's machine**, run it and fill in the connect screen: the host's address
(`192.168.1.20` is enough — the port defaults to 3000) and a name. Both are remembered for next
time. If the address is wrong, or the host's firewall is closed, the screen gives up after ten
seconds and says which it looks like, instead of spinning. Without a name the player shows up by
their character's default name on everybody else's nameplates.

From a shell, `--host=` and `--name=` fill the same in for one run without being remembered
(`--autoconnect` skips the screen and uses what was saved):

```bash
godot --path . -- --host=192.168.1.20 --name=Ailsa
```

**The server build** (`"Windows Server"`, `build/server/umf_server.console.exe`) is the
sidecar — a world's motion authority and NPC driver — not something a player runs. The fishing
slice plays without one: its world is MODULE-authoritative. A host who wants NPCs runs it with
`-- --world=<id>` and registers the identity it prints (`docs/SIDECAR_SPEC.md`).

**Things worth knowing before you invite anyone:**

- **One identity per player.** The client keeps its token in `user://`, so two people on
  different machines are automatically different players. Two copies on ONE machine are not —
  they share the token file and the server hands them the same entity. `--token=<name>` gives a
  second copy its own; `tests/multiclient_test.sh` is the suite that exists because this failure
  looks exactly like everything working.
- **The publisher is the admin.** Whoever runs `spacetime publish` owns the module: only they
  can force phases, seed content or register a sidecar. That is the identity in
  `~/.spacetime`, so publish from the machine you intend to administer from.
- **A fresh publish keeps its data** unless you pass `--delete-data`. Every test script does
  pass it, so do not point one at a server other people are on.
- **Latency is not simulated for real players.** `--latency=`/`--jitter=` and the F3 overlay are
  for testing prediction on localhost; a real connection brings its own.

## First run
```bash
rustup target add wasm32-unknown-unknown
spacetime start &                  # local server on 127.0.0.1:3000

cd server
#   crates.io by default; org builds uncomment the Artifactory block in .cargo/config.toml
cargo test --test golden
cargo check --target wasm32-unknown-unknown    # bare `cargo check` skips the wasm-gated module

cd ..
export GODOT=/path/to/Godot_v4.7.1-stable_win64.exe
#   The SDK is vendored in addons/SpacetimeDB/ and the plugin is enabled (addons/README.md).
#   Build, publish to `umf` and regenerate the client's bindings, in one command (the same steps
#   by hand are in AGENTS.md, Verify loop):
./tools/publish.sh --codegen       # on Windows: tools\publish.cmd --codegen
#   project.godot already lists the SpacetimeDB autoload first; the dock would add it for you.

./tests/run_tests.sh               # ~1200 checks and the lints
"$GODOT" --headless --path .       # CONNECTED → local entity: N → world ready
```
Both suites must print `max_err=0.000e+00` on every golden case. Anything above 0 means the GDScript model regressed or the frozen Rust twin was edited; do not widen the tolerance.

## Non-negotiables (enforced by `tests/run_tests.sh`)
- Only `foundation/net/spacetime_sync.gd` references the SDK, the `SpacetimeDB` autoload, or `spacetime_bindings/`.
- No `@rpc`, `MultiplayerSynchronizer`, `MultiplayerSpawner` anywhere in `foundation/`.
- Movement math through `Vector3` only in `movement_model.gd`; every model change ships regenerated golden vectors. `server/src/sim.rs` is frozen.
- No reference to `res://sidecar` outside `sidecar/`.
