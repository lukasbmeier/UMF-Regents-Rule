# The full file map
Moved from AGENTS.md (REVIEW 0.23.1 C1); AGENTS.md keeps the top level. docs/HANDBOOK.md section 2
is the human version.

```
AGENTS.md                      this file
README.md                      human overview + run instructions
docs/HANDBOOK.md               THE HUMAN GUIDE: systems, player loading, the server, what to edit
                               and what each change takes, recipes, the modularity gaps
docs/ARCHITECTURE.md           principles, node tree, data flow, contracts, SDK facts
docs/PHASE3_SPEC.md            entity framework + base components + foundation additions (NEXT)
docs/PHASE4_SPEC.md            client-side prediction & reconciliation (after Phase 3)
docs/SIDECAR_SPEC.md           headless Godot as motion/NPC authority: trust model, reducers, runtime, deploy
docs/ANIMATION_SPEC.md         animation contract, AnimationSet, generated AnimationTree, FeedbackComponent
docs/TEMPLATE_WORKFLOW.md      how games are created from the foundation; GAME_BRIEF.md template
docs/GENRE_ADAPTERS.md         how four target genres map onto the foundation
docs/DECISIONS.md              decision log (why things are the way they are)
docs/ROADMAP.md                THE TODO LIST: before a friend test, fishing features, template
                               features, what the chicken game and disc golf need, in order
shared/game.json               THE GAME: which genres it is made of (server and client read it)
foundation/core/genre_module.gd + genres.gd  a genre's client half (game/<name>/genre.tres), loaded by Boot
foundation/ui/lobby_panel.gd   the lobby between rounds: who is here, ready (R), teams (T)
foundation/ui/lobby_screen.gd  the lobby screen after connecting: everyone's characters, Choose
                               character, Ready, Join (#182)
foundation/ui/splash_screen.gd the splash before the connect screen; game/splash_screen.tscn is
                               the game's (#183)
foundation/level/              LevelInfo + LevelSpawn/LevelSpot/LevelPoint (a level built in the
                               editor), LevelBaker (scene -> server bake), LevelLoader (the level on
                               screen follows world_level)
tools/world/bake_level.gd      bake a level scene: --scene=res://...tscn
game/world/levels/meadow.tscn  the example level built in the editor (level 2)
game/fishing/genre.tres        fishing's client half: definitions, tables, HUD + fishing_world.tscn
tests/genres_test.sh           the server built from a game of no genres
foundation/core/settings.gd    Settings autoload: this machine's video/audio/controls, as data
foundation/core/appearance.gd  a chosen look as text ("ranger_f;hair=2")
foundation/ui/settings_panel.gd  the settings screen, drawn from the definitions
foundation/ui/character_picker.gd  choose a look and its options, in a turning preview
foundation/audio/music_director.gd  music by round phase, on the Music bus
foundation/net/schema_fingerprint.gd  the version check's fingerprint
foundation/held/off_hand.gd    the other hand on a held item (grip data, the same IK in game and preview)
default_bus_layout.tres        the audio buses: Master, Music, Effects, Ambience, Voice
tools/write_schema_fingerprint.gd  run by publish.sh --codegen
tools/synth_music.gd           generates game/fishing/music/*.wav
game/fishing/fishing_conditions.gd  the round's time of day and weather, named
game/fishing/fishing_records.gd + catch_journal.gd  the journal and the all-time records (J)
game/characters/character_looks.gd  the character picker's choices: every piece per slot and body
                               (SLOTS), their colours, skin and hair
game/world/sky_director.tscn (+ sky_look.gd, weather_look.gd)  the sky follows the round
docs/CHANGELOG.md              bundle version; 0.3.1
foundation/core/               SignalBus · ClockSync · EntityRegistry · EntitySpawner · SpaceTimeComponent · SpaceTimeEntity · EntityDefinition · AppExit (the one way to quit)
foundation/components/         Health · Movement · LocalInput · Session · Equip (in hand or put away)
                               components + configs
foundation/entities/           player.tscn (definitions: foundation/content/character/)
foundation/net/                SpaceTimeSync (SDK adapter) · NetConfig · RowEvent · ReducerRequest · SubscriptionSet
foundation/sim/                MovementModel · MovementState · InputFrame · MovementConfig · ChallengeModel
foundation/tools/              EditorScripts (config codegen; collider exporter in Phase 3)
tests/                         test_runner.tscn/.gd (runs tests/suites/*.gd, which extend suite_base.gd) · run_tests.sh (lint + tests)
tests/integration_test.sh      server reducers against a live local module
tests/multiclient_test.sh      TWO real clients at once: distinct identities, mutual visibility
tests/playtest_test.sh         movement playtest (tests/playtest/movement_playtest.*) at 0/100/200 ms
tests/remote_playtest.sh       walker + observer: remote smoothness under simulated latency
foundation/debug/              net_debug_overlay.tscn — F3 netcode readout, F4 latency
tests/levels/                  greybox.tscn (scene-test level) · greybox_demo.tscn (runnable)
tests/e2e/                     e2e_runner.gd + e2e_test.tscn — real client vs real module
tools/                         codegen_config.gd (writes plugin_config.tres for headless codegen) ·
                               publish.sh (build + publish + codegen, one command) · run.cmd +
                               publish.cmd (the bash scripts on Windows, via Git Bash; this
                               machine's GODOT in tools/local.env, not committed)
foundation/held/               HeldItem · ItemGrip · GripEntry · BodyClearance · SkinClearance (arms
                               against the skin) · GripFit ·
                               HoldWrist (the shut hand, the wrist turn) · held_item_preview.gd (held items:
                               grips per animation and body, fitted to the hand, put away, lined
                               up in the editor)
tools/held/fit_grip.gd         fit a grip file and photograph it from a shell (needs a window)
grip_pictures/                 Save Pictures' sheets (not committed; a .gdignore keeps them out
                               of the import)
shared/rules.json              the foundation's rules as the game sets them (health, interact
                               range, round plans); compiled in by build.rs, read by `Rules`
sidecar/                       (Phase 3) SERVER-ONLY: sidecar_main · authority_sync · sim_world · npc/ · combat/
addons/SpacetimeDB/            vendored SDK (plaught-armor fork) — only spacetime_sync.gd may touch it
spacetime_bindings/            GENERATED, alias `Umf` — 26 files; commit them
server/src/sim.rs              FROZEN gravity-only twin + wire types. spacetimedb-lib ONLY (DECISIONS #27)
server/src/challenge.rs        pure challenge validators; GDScript twin + goldens. No spacetimedb dep
server/src/module/             tables + reducers, one file per system (mod.rs re-exports them) — wasm32-gated (DECISIONS #27)
server/src/game/               THE GENRE LAYER, server half. Foundation never imports from here
game/fishing/                  THE GENRE LAYER, client half: fisher.tscn, HUD, play_local.sh
foundation/camera/             CameraRig (and `watch`) + first_person.tres / third_person.tres · FollowCamConfig + follow_cam.tres · FlightCam (DECISIONS #248)
foundation/input/              ChargeMeter · AimCharge (DECISIONS #249); foundation/ui/charge_bar.gd draws one
foundation/anim/               AnimationSet · AnimationClipRef · AnimationTreeBuilder · AnimationDriverComponent
sidecar/                       SERVER-ONLY: sidecar_main · sim_world · authority_sync · sidecar_net_config.tres
sidecar/npc/                   NpcBrain (and its behaviour tree: run_tree) · BrainTask · NpcWorldView · NpcBrainComponent · brains/wander.gd · brains/chase.gd
addons/limboai/                LimboAI 1.8.1 (GDExtension): bots' behaviour trees (DECISIONS #245); Windows, Linux, macOS libraries only
foundation/physics/            FlyingBody (the one flight) · BodyForces (a genre's flight hook) · BodyLaunch (the thrower's view) (DECISIONS #246)
foundation/content/body_def.gd BodyDef; foundation/content/body/ball.tres (the greybox's ball); foundation/entities/body.tscn + content/character/body.tres (kind 3)
foundation/components/body_component.gd  a body on screen: its look, its turn, the thrower's flight kept near the referee's
sidecar/physics/body_referee.gd          the world's bodies flown, written, their hits reported
server/src/body.rs + module/bodies.rs    what the module checks of a throw; body_state, body_contact, launch_body, write_body_batch, report_body_contacts
foundation/content/loot_table_def.gd + loot_line.gd  LootTableDef (each / one-of, nested, pity) (DECISIONS #268)
server/src/loot.rs + module/loot.rs      the roll, pity, who earns one; damage_share, drop_pity, drop_loot; server/tests/loot.rs, tests/suites/loot.gd
server/src/ground.rs + module/ground.rs  items on the ground: ground_item (its RLS), drop_to_ground, pick_up, drop_item, the tick (DECISIONS #269)
foundation/items/ground_items.gd         GroundItems: the sacks shown, walked over and picked up (Boot adds it)
foundation/content/resource_def.gd + components/resource_component.gd  ResourceDef (mana) and an entity's pools on the client (DECISIONS #270)
server/src/resource.rs + module/resources.rs  a pool's level; resource_state, ensure_resource, spend_resource
tests/sidecar_test.sh          a real sidecar against the real module, with an unregistered control
                               and a restart (the NPC's brain resumes); SIDECAR_BIN= points it at a build
tests/connect_playtest.sh      the connect screen + Esc menu, driven like a player (fresh install)
tests/export_test.sh           export both presets, inspect the packs, run both builds
tests/playtest/fishing_observer.*  the second client in the fishing playtest
foundation/ui/                 connect_screen.tscn (+ ConnectSettings in net/) · pause_menu.tscn ·
                               window_mode.gd (fullscreen: F11 / Alt+Enter / the menu's button)
export_presets.cfg             "Windows Client" (no sidecar/) · "Windows Server" (dedicated, boots the sidecar)
tools/pck_list.py              list the files inside an exported .pck
tools/synth_fishing_sfx.gd     generates game/fishing/sfx/*.wav (deterministic, CC0)
tools/print_user_dir.gd        prints user:// for shell harnesses
game/fishing/                  + fishing_fx (presentation) · fishing_feedback · fishing_rod (+
                               rod_blank.gdshader: the bend, the reel handle, the winding IK) ·
                               reel_gauge (THE FIGHT on the HUD) · rod_grip.tres (the rod's ItemGrip:
                               how it sits in the hand per animation and body) · rod_grip_preview.tscn
                               (edit it in the EDITOR: pick an animation and a body, drag the Grip) ·
                               fishing_data (the content, from shared/fishing/) · fight_sim (THE
                               FIGHT's twin) · gear_component · fishing_standings ·
                               lakeside_game.tscn (main) · fishing_game.tscn (greybox) ·
                               feel_preview.tscn (F6: the presentation, no server) · sfx/
game/world/                    lakeside.tscn (GENERATED) · lakeside_level.gd · lake_water · terrain/ ·
                               kits/ (Quaternius nature, village, props + quaternius_import.gd,
                               foliage_material.gd + nature_foliage*.gdshader: leaves lit both sides) · buildings/
tools/world/                   build_lakeside.tscn (the generator) · lakeside_shape.gd (the shape, and
                               where the spots go) · lakeside_shots.tscn (PNG views, `--shot=` for
                               ad-hoc ones, `--angler=` for a line on the water) · gen_level_probes.py
tests/render/ + render_test.sh THE LOOK: windowed checks that need pixels (foliage, grass colour at a
                               distance, the lake's depth colours) and a real window (F11 and back)
shared/world/                  <level>.json + <level>_depth.bin: the bake the server compiles in
server/src/level.rs            the bake, read by the module; twin of foundation/sim/level_bake.gd
server/src/genre/              fishing's PURE rules: fishing.rs (rolls, hook-set) · fight.rs (THE FIGHT)
shared/fishing/                fishing.json (catalogue, spots, gear, timings) · fight.json (GENERATED
                               by tools/fishing/gen_fight.py: the fight's tuning + catch profiles)
shared/golden/fishing/         hookset.json (NumPy) · fight.json (from server/tests/fight.rs)
tools/fishing/                 gen_goldens.py · gen_fight.py · fight_bot_cli.gd (play a fight from a shell)
tests/fight_bot.gd             FfC's probe players, for the integration suite and the playtest
game/anim/                     extracted AnimationLibrary .res + generated .tres sets + ATTRIBUTION.md
game/characters/               modular_character.gd · looks/ (GENERATED by tools/characters/make_looks.py)
                               · quaternius/ (imported pack parts, ATTRIBUTION.md) · mannequin_f.glb
                               · character_preview.tscn (F6; UP/DOWN looks, L lineup)
tools/characters/              import_quaternius_characters.py · make_looks.py
tools/extract_animation_library.gd  source .glb/.fbx -> portable AnimationLibrary .res
tools/animation_set_builder.gd      fuzzy-match clip names -> AnimationSet .tres (read its report)
server/src/lib.rs              crate root: `pub mod sim` + `movement_config` + the gated `mod module`
server/tests/golden.rs         golden harness
shared/movement_config.json    single source of truth for tunables
shared/golden/movement/        float32 movement vectors (GDScript regression)
shared/golden/challenge/       float32 validator vectors (Rust AND GDScript, max_err = 0)
```
