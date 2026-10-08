# The UMF Handbook — how it works, and how to change it

This is the human guide. It explains every system in plain terms, what each one depends on, and
what you can change without writing code. `AGENTS.md` holds the rules for AI agents and
`docs/DECISIONS.md` the reasons behind every choice; you should not need either to find your way.

Keep it true: a change to how something works updates its section here, in the same change.

---

## 1. The 60-second version

Two programs make the game:

```
  Godot client (this project)                      SpacetimeDB module (server/)
  ───────────────────────────                      ────────────────────────────
  draws the world, reads input,       ── calls ──▶  reducers: the only things that change state
  predicts your own movement          ◀── rows ───  tables: the whole game state, as a database
```

- **The server is a database with game logic inside it.** All game state lives in TABLES
  (`entity`, `movement_state`, `catch`, `gear`...). It changes only through REDUCERS: functions a
  client calls (`cast`, `buy_upgrade`) or the server runs on a timer (`tick_movement` 20 times
  a second). Each reducer is a transaction: it fully happens or not at all.
- **Clients never decide anything that matters.** A client asks ("cast here"), the server checks
  and writes rows, and every client sees the rows change. The client only predicts its own
  movement (so it feels instant) and plays effects.
- **Godot's own multiplayer is not used.** No RPCs, no MultiplayerSynchronizer.

And the code is split in two layers:

| Layer | Folders | Knows about |
|---|---|---|
| **Foundation** (the template) | `foundation/`, `sidecar/`, `server/src/module.rs`, `sim.rs`, `challenge.rs` | movement, entities, health, inventory, sessions/rounds, interaction, challenges, NPC brains |
| **Genre** (one game: fishing) | `game/`, `server/src/game/`, `server/src/genre/`, `shared/fishing/` | fishing |

The foundation never mentions fishing. Fishing plugs into it through definitions, components and
a handful of hooks.

**A game is a list of genres** (`shared/game.json`, today `["fishing"]`). The server compiles in
exactly the genres listed, and the client boots exactly those: each genre is
`server/src/game/<name>.rs` (with its rules in `server/src/genre/`) plus `game/<name>/genre.tres`
on the client (its entity definitions, tables, and the scenes it puts in the game: fishing's HUD,
sky and music). Take a genre out of the list, republish with `--codegen` and restart: it's gone,
and the foundation still stands (`tests/genres_test.sh` builds the server with no genres).

---

## 2. Where everything is

```
project.godot          the Godot project (the repo root IS the project). Main scene:
                       game/fishing/lakeside_game.tscn
foundation/            THE TEMPLATE, client side
  core/                autoloads + the entity system (SignalBus, EntitySpawner, SpaceTimeEntity...)
  components/          the building blocks of an entity (movement, health, input, inventory...)
  net/                 talking to the server (SpaceTimeSync, NetConfig, InterestManager)
  sim/                 shared simulation (movement model, input frames, challenge validator)
  anim/                animation sets and the generated AnimationTree
  camera/              camera rig + first/third person presets
  ui/                  connect screen, Esc menu, fullscreen
  entities/            player.tscn — the one scene every entity is built from
game/                  THE GENRE, client side
  fishing/             fisher.tscn, the fishing components, HUD, rod, effects, sounds, previews
  characters/          the eight looks (modular Quaternius characters)
  anim/                animation libraries and the fisher's animation set
  world/               the lakeside level, water, nature/village/props kits
sidecar/               SERVER-ONLY Godot code: the headless authority and NPC brains
server/                the SpacetimeDB module (Rust)
  src/module.rs        foundation tables + reducers
  src/game/            fishing's tables + reducers (the genre's server half)
  src/genre/           fishing's pure rules (no database), testable on their own
  build.rs             compiles shared/ data INTO the module
shared/                data both halves read: movement tuning, fishing content, the level bake,
                       golden test vectors
spacetime_bindings/    GENERATED from the module: never edit
tools/                 generators: the level, character looks, animation sets, sounds, fight tuning
tests/                 every test layer (section 10)
addons/                the SpacetimeDB SDK (vendored), Terrain3D, the godot-ai editor bridge
```

---

## 3. The server, in plain terms

### What it is
SpacetimeDB runs the module (`server/`, Rust compiled to WebAssembly) inside the database. You
start the database with `spacetime start` and put your module into it with `spacetime publish`.
The local database is called **`umf`**.

### Its parts
| Thing | What it means here | Examples |
|---|---|---|
| **Table** | a kind of game state. A row per thing | `entity`, `player`, `movement_state`, `health_state`, `session`, `inventory_item`, `challenge`; fishing's `catch`, `gear`, `fishing_line`, `fishing_spot` |
| **Reducer** | something a client (or the server) asks to happen | `submit_input`, `interact`, `submit_challenge_result`; fishing's `cast`, `reel_in`, `buy_upgrade` |
| **Scheduled reducer** | a timer on the server | `tick_movement` (20 Hz), `advance_phases` (1 Hz, the round clock), `prune_challenges`, `check_authorities` |
| **Lifecycle reducer** | runs on connect/disconnect/publish | `client_connected`, `client_disconnected`, `init` |
| **Subscription** | a client's standing query: "send me these rows, and every change to them" | built only by `InterestManager` |
| **Row-level security** | some rows are only visible to their owner | `challenge` (what is on your line), `input_queue` |
| **Identity** | who a client is: a token saved in `user://spacetime_token*.txt` | the publisher's identity is ADMIN |

### Where its code is
| File | Holds |
|---|---|
| `server/src/module.rs` | every foundation table and reducer. A game never edits it: it uses the hooks below and `shared/rules.json` |
| `server/src/game/mod.rs` | the HOOKS the foundation calls into the genre (section 3, "Hooks") |
| `server/src/game/fishing.rs` | fishing's tables and reducers: `cast`, `reel_in`, `buy_upgrade`, `use_level` |
| `server/src/genre/fishing.rs`, `fight.rs` | fishing's pure rules: the rolls, the hook-set, THE FIGHT. No database |
| `server/src/sim.rs` | the frozen gravity-only movement twin + the wire types |
| `server/src/challenge.rs` | challenge validators (the timing bar) |
| `server/src/level.rs` | reads the level bake (water, depth, spots, spawn) |
| `server/build.rs` | compiles `shared/rules.json`, `shared/movement_config.json`, `shared/world/*.json`, `shared/fishing/*.json` into the module |

**Because `build.rs` compiles the shared data in, changing any of those files means building and
publishing the module again.** The client reads the same files directly, so it just needs a restart.

### Genres, and the numbers they claim
Each genre on the server is a `Genre` (`server/src/game/mod.rs`): it answers the hooks below
that it needs, and declares its **claims**, the challenge kinds, entity kinds, phases and session
kinds it uses for itself (fishing claims challenge kind 100). If two genres claim the same number,
or one claims a foundation number, the server refuses to start and says which.

### Hooks: where a game plugs into the server
`server/src/game/mod.rs` is the only place the foundation calls the game. Fill in the ones you
need; leave the rest empty.

| Hook | Called when | Fishing uses it for |
|---|---|---|
| `on_init` | the module is first published | seeding spots and the level |
| `on_player_created` | a new identity connects for the first time (its entity, health, movement and session rows already exist) | nothing (gear starts as the starting kit) |
| `on_player_returned` | a known player connects again | nothing |
| `on_player_left` | a player disconnects. The foundation keeps their entity; despawn it here if your game should not | nothing |
| `on_interact` | someone uses an entity of a kind the foundation does not own (100 and up); range and world are already checked | nothing (it owns no kind) |
| `resolve_challenge` | a minigame of the game's own kind is submitted: judge and pay out | the hook-set and THE FIGHT, replayed |
| `on_challenge_succeeded`, `on_challenge_closed` | a challenge passed / ended in any way | the catch / clearing the line |
| `on_phase_changed` | a session's phase changed (the round machine, or an admin's `set_session_phase`) | the bell: lines nothing has bitten come in |

### Levels: which map a world runs
A world's level is the foundation's `world_level` row: level 1 is the lakeside, 2 the meadow,
0 the greybox test level. `spacetime call umf set_world_level 0 2` (as the publisher) switches
world 0; the game swaps the scene on screen (`LevelLoader`, in the game scene) and moves everyone
into it. Fishing's own `use_level` does the same through the same record. Each genre hears
`on_level_changed` and sets itself up (fishing stocks the greybox's ponds and places the rival).

### Rules a game sets without code: `shared/rules.json`
A new player's health, how close you must be to use something (the client's prompt reads the same
number), and each session kind's ROUND PLAN: its phases in order, their names and how many seconds
each lasts (0 holds a phase until a reducer moves it on). Fishing's rounds are kind 0. Change it,
then publish (below) and restart.

A kind's `match` section says how its MATCHES go (DECISIONS #182). A match is the rounds a world
plays from someone's arrival until everyone has left, and players see them counted from round 1.
`wait_s`: how long a match's first lobby waits (0, with ready-up: until everyone here is ready).
`end_after_empty_s`: how long a world may have nobody online before its match ends (60: a
dropped player can come back to the same match); after that it waits and nothing is played or
counted. The server's `session.round` keeps counting across matches (catches are filed under it):
show the match's round (`SessionComponent.get_match_round()`). To start a new match by hand:
`spacetime call umf new_match 1`.

### Running the project's scripts on Windows
The scripts (`tests/*.sh`, `tools/publish.sh`) are bash. On Windows run them through
`tools\run.cmd`, which uses Git Bash (installed with Git for Windows), from cmd or PowerShell:
```bat
tools\run.cmd tests\run_tests.sh
tools\run.cmd tests\integration_test.sh
```
Put this machine's Godot path in `tools\local.env` once (copy `tools\local.env.example`; keep
the quotes) and every script finds Godot without being told.

### Publishing, and keeping the client in step
One command (double-click `tools\publish.cmd`, or from a terminal):
```bat
tools\publish.cmd                 :: code or data changed; keeps the world's data
tools\publish.cmd --fresh         :: a table changed shape: wipes the data first
tools\publish.cmd --codegen       :: a table or a reducer's arguments changed
```
(In Git Bash, or on Mac and Linux: `./tools/publish.sh` with the same options.)
`--codegen` regenerates the client's bindings; without it the client silently ignores a new table.
Close the editor first (or let it reload the generated scripts). `DB=<name>` picks another
database.

**Two databases:** `umf` is the one you play in; `umf-test` is the one every test suite uses (and
wipes). Running the tests no longer touches your world. A lint stops a test script naming `umf`.

**The version check:** a game refuses to connect to a server whose tables or reducers differ from
the ones it was built with, and says so on the connect screen ("This server is running a different
version of the game"). So after `--codegen`, export the game again for anyone you play with. The
check compares a fingerprint written at codegen (`spacetime_bindings/schema_fingerprint.json`) with
the server's own schema; a test that changes the schema without codegen is refused the same way.

### Playing with a friend on another computer
1. **Export** the game: `tools\run.cmd tests\export_test.sh` builds `build/` (the client is the
   `Windows Client` preset). Zip `build\client\` and send it: `umf.exe` holds the whole game, and
   `libterrain...dll` (Terrain3D, which draws the lakeside's ground) must sit beside it.
2. **Let them reach your server.** `spacetime start` only listens on your own machine. Start it
   with `spacetime start --listen-addr 0.0.0.0:3000` instead, then:
   - **Same house:** allow it through Windows Firewall once (an admin PowerShell:
     `New-NetFirewallRule -DisplayName "SpacetimeDB" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow`)
     and give them your LAN address (`ipconfig`, the IPv4 one, like 192.168.1.20).
   - **Over the internet:** the easiest is Tailscale on both machines (they type your 100.x
     address; no router changes). Or forward TCP 3000 on your router to your PC and give them
     your public address.
3. **They run it.** Windows SmartScreen says "Windows protected your PC" for an unsigned game:
   More info, then Run anyway. They type your address on the connect screen, pick a name and a
   character, and connect.
4. **If something breaks:** Escape, then Open log folder; they send you `godot.log`.
5. **After you change the server**, publish with `--codegen` and send them a new export: an old
   build is refused with a message saying so (above).

Voice: use Discord alongside for now (the roadmap has voice chat later).

### Who moves things (motion authority)
Each world picks one:
- **MODULE (Tier A, what fishing uses):** your client simulates your movement and tells the
  server where you are; the server only checks you could have moved that far that fast, and clamps
  a claim it doesn't believe. Cheap, no server physics.
- **SIDECAR:** a headless Godot process (`sidecar/`) runs real physics for the world and is the
  authority. For games where the server must see walls (NPCs, survival). The fishing rival angler
  NPC is driven by a sidecar brain.

---

## 4. How a player gets into the world

Step by step, from pressing Play:

1. **Godot starts `lakeside_game.tscn`.** Its `Boot` node (`foundation/boot.gd`) hands the
   `EntitySpawner` the game's ENTITY DEFINITIONS (fisher, spot, rival), plays the SPLASH
   (`game/splash_screen.tscn`: the game's name; any key skips it) and shows the connect screen.
2. **Connect.** `SpaceTimeSync` (the only script that talks to the SDK) connects with this
   machine's identity token. Editor instances get their own token each (slot 1, 2...), so two
   instances are two players.
3. **The server runs `client_connected`.** First time for this identity: it creates an `entity`
   row (kind 0 = player), a `player` row (name, online), a `movement_state` at the world's spawn,
   a `health_state` (`shared/rules.json`'s health) and a session membership, then calls the game's
   `on_player_created`. Returning: it marks you online and calls `on_player_returned`. Your player
   persists while you are away unless the game's `on_player_left` says otherwise.
4. **`InterestManager` subscribes** to the tables in the game's `NetConfig.core_tables`
   (`game/fishing/fishing_net_config.tres`), filtered to your world.
5. **Rows stream in.** `EntityRegistry` routes each row by entity id, and holds rows for entities
   that don't exist yet.
6. **`EntitySpawner` sees an `entity` row** and looks up the definition whose `kind` matches.
   It instances the definition's scene (`fisher.tscn`), dresses it (one of `visual_variants`,
   picked by entity id, so everyone sees the same look), and gives it its animation set and
   camera rig.
7. **The entity binds** once the rows its components need have arrived: each component gets its
   rows (`bind()`), and from then on every change to them (`_on_row_updated`).
8. **Yours or someone else's?** The entity owned by your identity is LOCAL: it samples input,
   predicts its movement and owns the camera. Every other one is REMOTE: it is drawn ~100 ms in
   the past, smoothly interpolated between server updates.
9. **The lobby screen** (`foundation/ui/lobby_screen.gd`) covers the game: everyone in the session
   on a stage in their looks, Choose character (the picker), Ready (or R). When everyone here is
   ready the match's first round starts and the screen goes. Arriving mid-match it offers Join.
   While it is up you are held still and have the cursor; Esc still opens the menu.

NPCs, fishing spots and anything else with an `entity` row arrive exactly the same way, as
different kinds with their own definitions.

---

## 5. The entity: one scene, many components

Every entity is `foundation/entities/player.tscn` (a `SpaceTimeEntity`, a CharacterBody3D) with
COMPONENTS under its `Components` node. A genre makes its own entity by instancing that scene and
adding components: `game/fishing/fisher.tscn` = player.tscn + `Fishing`, `Gear`, `Feedback`.

| Component | Job | Backed by table |
|---|---|---|
| Movement | prediction (local), interpolation (remote), jumps/landings | `movement_state` |
| Input | samples keys/mouse into input frames (local only) | — |
| Health | health, death, revival | `health_state` |
| Inventory | items | `inventory_item` |
| Session | round phase, score, coins | `session`, `session_member` |
| Interaction | what you're looking at, the interact key | — (calls `interact`) |
| Action | abilities and cooldowns | `ability_*`, `action_event` |
| Animation | drives the generated AnimationTree from state | — |
| Nameplate | the name over remote players | `player` |
| *Fishing* (genre) | the cast, the bite, the fight, the line | `fishing_line`, `challenge`, `catch` |
| *Gear* (genre) | rod/reel/line tiers | `gear` |
| *Feedback* (genre) | turns fishing state into effects and animation | — |

**The component contract** (`foundation/core/spacetime_component.gd`): a component lists the
tables it needs (`required_tables()`, plus `optional_tables()` for ones it may have no rows in),
receives rows, and NEVER owns authoritative state; it may hold prediction and presentation. It
doesn't touch UI: it emits signals, and UI listens. When the entity appears, the component is
handed EVERY row it already has, one insert each, before it counts as bound: a table with many
rows per entity (catches, stacks) arrives whole, keyed by each row's id, and a component that
celebrates news checks `is_bound()` so old rows are not news.

**`EntityDefinition`** (a `.tres` you edit in the Inspector) says what one kind of entity is:
`kind` (matches the server's `entity.kind`: 0 player, 1 NPC, 2 resource node, 100+ genre),
`scene`, `display_name`, `brain` (NPCs), and the presentation group: `visual_scene` or
`visual_variants`, `visual_offset`, `visual_yaw_deg`, `animation_set`, `camera_rig`.

---

## 6. The client systems

### Autoloads (they start in this order, which is the boot sequence)
`SpacetimeDB` (the SDK, generated) → `SignalBus` (global events) → `Settings` (this machine's
video, audio and control settings) → `MouseCapture` (the only thing
that changes the cursor mode) → `ClockSync` (server time) → `SpaceTimeSync` (the SDK adapter) →
`InterestManager` (subscriptions) → `EntityRegistry` (row routing) → `EntitySpawner` (rows to
scenes). `_mcp_game_helper` is a dev tool for the AI editor bridge.

### SignalBus — the events anything can listen to
`world_ready`, `local_entity_assigned`, `entity_spawned/despawned`, `session_phase_changed`,
`session_score_changed`, `entity_health_changed`, `entity_died/revived`, `entity_jumped/landed/
teleported`, `entity_inventory_changed`, `interact_target_changed`, `entity_action`,
`action_rejected`, `notification_requested`. UI hangs off these. Positions never go on the bus.

### Calling the server
`SpaceTimeSync.call_reducer(&"name", [args], ["types"])` returns a `ReducerRequest`;
`await req.settled`, then read `req.outcome` and `req.error_message`. A reducer the player
triggered must show its error to the player.

### Movement
One model (`foundation/sim/movement_model.gd`) runs on the client for prediction, and in the
sidecar for authority. Tuning is `shared/movement_config.json` (speeds, jump, gravity,
acceleration, reconciliation). Gaits: a plain key RUNS, Shift sprints, Ctrl walks.

### Animation
Characters animate from a SET (`game/anim/fisher.tres`) mapping SEMANTIC names
(`locomotion.run`, `interact`, `fishing.heave`) to clips. The AnimationTree is GENERATED from the
set; never build one by hand. Gameplay asks for semantic names only.

### Held items: rods, swords, shields, bows (`foundation/held/`)
An item held in a hand is a `HeldItem` scene (its root at the item's grip point) with an
`ItemGrip` file saying where it sits in the hand. A grip is set for two things only: an
ANIMATION and a BODY. Whenever a body plays an animation, however it was started (walking about,
a cast, a pose the game holds), the item sits where the grip for that animation and that body
says. Nothing in code tells an item how to be held.

- An animation nobody has set **borrows** a grip: the grip of the animation its clip falls back
  to (sprint borrows run's, run borrows walk's, walk the idle's), else the **idle's**. So an item
  needs one grip, the idle's, plus one for each animation that holds the hand differently.
- **Per body**: a grip can be the shared one (`both`) or kept for one BODY (`female`, `male`, as
  each look says). For the same animation her own grip wins over the shared one, so you can fix
  the reel off her leg without moving his rod. A shared run grip still beats her idle grip while
  she runs: it's there because the run holds the hand differently.
- In the game the grips **blend as the animations blend**: walking into a run, or a cast into the
  waiting pose, moves the item as smoothly as the arm.
- **Steady** (per grip): the item keeps its direction to the body instead of turning with the
  hand. A long item in a running animation needs it, or its tip sweeps through the head.
- Put one in a hand: `HeldItem.attach(skeleton, scene)`, and give it the entity's animation driver
  (`item.driver = driver`). That's all: it reads the animations itself.
- **Line it up in the editor**: a preview scene using `foundation/held/held_item_preview.gd`
  (the rod's is `game/fishing/rod_grip_preview.tscn`). Pick an **Animation** and a **Body**
  (`both`, `female` or `male`), then drag the **Grip** node: that sets the grip for exactly that
  animation and that body. The first drag makes it, starting where the item already sits, so
  nothing jumps. Tick **Steady** to keep its direction to the body. **Clear This Grip** takes the
  grip away, so that animation borrows again. A woman and a man hold the item (every look is one
  of those two bodies). Each label says which grip that character uses, and how much air the
  item's marked points (a `clearance_radius` metadata on any node in the item, in metres) have
  off the body, here and at worst through the whole clip. A node that also has `clearance_to` (a
  NodePath to another node) is measured as a LINE to it: the rod's `Shaft` runs to its `Tip`, so
  a blank swinging through the head turns the label red. **Play** plays the clip.
- **Where the hand closes**: a `Hold` node in the item's scene (the rod's is 10 cm up its cork).
  Grips place the hold, and the item hangs from it, so move the Hold to hold the item higher or
  lower. The preview's Grip node sits on it.
- **The wrist turns while carrying**: a steady grip keeps the item's direction as the arm swings,
  and the hand bends at the wrist (up to the grip file's **Wrist Turn Deg**) to keep the handle in
  the fist. Each label says "in the fist", or how far the handle leaves it.
- **Held in both hands**: the grip file's **Off hand** group (`rod_grip.tres`) names the
  animations the other hand holds the item in (the rod: the cast, the wait, the heave), the arm,
  the point it holds (a node in the item's scene by name: the rod's `OffHand`, on the reel's knob),
  where the wrist sits from it and which way the elbow points. The game and the preview put the
  hand there by the same IK (`OffHand`). A clip's own left hand is not on our rod; add an animation
  here when its left hand floats or crosses the body. The `arms` test suite checks the hand stays
  on the rod in each of them.
- **The hand stays shut round it**: a clip that opens the hand (a jump) has its fingers closed back
  toward the fist of the grip file's **Fist Animation** (the idle's first frame), as far as the clip
  opened them; clear it and the hand does what the clip does. The preview and the fit see the same
  hand the game shows.
- **Or let it fit itself** (`GripFit`): **Fit Every Animation** puts the item's handle in the hole
  the hand's curled fingers make, in every animation, clear of the body. Animations that USE the
  item (the cast, the heave) hold it along the fist, as they were animated; animations that only
  CARRY it (standing, walking, running, jumping) hold it steady toward the grip file's **Carry
  Point** (x right, y up, z forward: the rod's is (0, 1, 1), tip up and forward; or TURN the
  preview's **CarryPoint** node, which sits on her hand: its green arrow is where the rod points,
  its blue arrow the side away from the reel, and the carried animation shown is refitted to it;
  untick Play to turn it). **Fit Face** says
  which way it rolls (the rod's reel hangs on its -Z, so (0, 1, 0) hangs it below). Then **Save
  Pictures** and open `grip_pictures/<grip>.png`: every animation, labelled with how clear each
  body is. Drag whatever still looks wrong. The fit lists what it could not clear, and how close
  the hand itself gets: if the animation puts the hand against the leg, no grip can clear it.
  **Fit This Grip** does just the animation and body chosen. The fit's summary also says how thick
  a handle the fist holds: make the item's handle about that thick, or it shows through the fingers.
- **Put away** (on the back): the grip file's **Stow** settings say which bone it rides on and
  where. In the preview tick **Show Stowed** and drag the **Stow** node, or press **Fit Stow**: it
  slings the item where the draw's hand reaches, hanging the way **Stow Point** asks (the rod's is
  (-0.6, -0.8, 0): down across the back to the left), and makes the draw and stow meet it, so the
  hand takes it with no jump. A long item can be packed short while it is away: **Stow Length**
  (the rod's is 0.45; it packs in the hand before it lets go, and stretches out once drawn), so
  it does not drag on the ground. In the game the item follows the entity's **EquipComponent**
  (`HeldItem.follow`): the draw and put-away play on the upper body (the legs keep walking).
- **In hand or put away is game state** (`EquipComponent`, on the entity's Components): a genre
  calls `needed()` while it uses the item (that draws it), and checks `is_equipped()` before a
  verb that needs it in hand: the fisher's cast waits for the rod. **When it goes away** is on the
  node: **Away After Sec** unused (10 s), or sooner when the body moves faster than **Away When
  Faster Than** (Never, Walk, Run: the gaits' speeds from `shared/movement_config.json`) for
  **Away Moving After Sec**; untick **Away When Idle** and the item stays in hand. The owner's
  client sends each change to the server (`equip_state`), so everyone sees the draw as it starts.

### Camera, UI, debug
- Camera: `foundation/camera/third_person.tres` / `first_person.tres`, chosen per definition.
- Connect screen and Esc menu: `foundation/ui/`. F11 or Alt+Enter: fullscreen. The menu also has
  Settings, Open log folder, Character, and whatever a game adds (`PauseMenu.add_button`,
  `open_page`: fishing's Journal).
- **Settings** (`foundation/core/settings.gd`, saved to `user://settings.cfg` on each computer):
  every setting is a `Settings.define(...)` and the screen (`foundation/ui/settings_panel.gd`)
  draws whatever is defined, so a game adds its own on its own tab without editing the screen.
  Sounds pick a bus (`Settings.BUS_MUSIC`, `BUS_EFFECTS`, `BUS_AMBIENCE`, `BUS_VOICE`) and get its
  volume. Tests never read your settings, nor the name and look you saved on the connect
  screen (a suite's processes keep their own profile, named after the test database).
- **Character picker** (`foundation/ui/character_picker.gd`): start from one of the player
  definition's `visual_variants`, then change whatever the look's model offers
  (`appearance_options()`). Fishing's (`game/characters/character_looks.gd`) offer every piece,
  slot by slot, from the pieces made for that body: torso, arms, legs, feet, headwear,
  shoulders, neck, hair, beard and eyebrows. The four clothing slots each have a colours choice
  beside them, then skin and hair colour. The choice is stored on the server (`appearance`, up to
  256 characters) so everyone dresses you the same. A swapped piece rebuilds the character on a
  new skeleton, so `apply_appearance` runs before the model goes into the tree.
- **Character pieces import without LODs** (`meshes/generate_lods=false` in each
  `game/characters/quaternius/models/*.gltf.import`). The pieces are worn a millimetre apart, and an
  LOD simplifies each one on its own, so at a distance the hair sank into the scalp in spots. The
  importer script sets it for new pieces; the `character` suite fails on a piece that has LODs.
- **Music** (`foundation/audio/music_director.gd`): a node in the game scene with a track per round
  phase.
- Fishing HUD: `game/fishing/fishing_hud.tscn`.
- F3: net overlay. F4: cycle simulated latency.

---

## 7. Fishing, the reference game

### The loop
Walk to the water → **hold the left mouse button** to aim (the ring is green where the server
will accept the cast) → **release** to cast → the float twitches (the tell) → it goes under:
**click** to set the hook → **the fight**: hold to load the rod, let go in the sweet band, wind
with the **mouse wheel** (or circle the mouse), **right button** gives line when it runs → the
catch → score and coins. Rounds: LOBBY 30 s → PLAYING 3 min → RESULTS 20 s → SHOP 25 s (keys 1/2/3
buy rod, reel, line).

Around it:
- **Each round is a time of day and has weather** (dawn, day, dusk, night; clear, overcast, rain,
  fog). They change what bites and how fast (`fishing.json` `conditions`); the HUD says them and
  what they favour, and the sky, fog and rain show them (`game/world/sky_director.tscn`).
- **Old Barnaby**, the rival angler, fishes the village shallows in the default world and plays the
  rounds (`fishing.json` `rival`).
- **Everyone sees your fight**: the heave, the bend and the float coming in.
- **J opens the journal**: everything you've caught, what's missing, and the all-time records.

### Who decides what
- The server ROLLS everything at the cast (what bites, its weight, when) into a private row.
- The client plays the bite and the fight for feel, then submits its reaction and every tick of
  input. The server REPLAYS the fight with the same rules (`server/src/genre/fight.rs`, kept bit
  for bit identical to `game/fishing/fight_sim.gd`) and decides the catch.

### Where things are
| Piece | Server | Client |
|---|---|---|
| Content: catches, spots, gear, timings, economy | `shared/fishing/fishing.json` (compiled in) | read by `fishing_data.gd` |
| The fight's tuning | `shared/fishing/fight.json`, GENERATED by `tools/fishing/gen_fight.py` | `fight_sim.gd` |
| Cast, reel in, shop | `server/src/game/fishing.rs` | `fishing_component.gd`, `gear_component.gd` |
| Spot depletion | `fishing_spot` table | — |
| Effects: rod, line, float, splash, sounds | — | `fishing_fx.gd`, `fishing_feedback.gd`, `sfx/` |
| The rod and how it's held | — | `fishing_rod.tscn` (a `HeldItem`; its `Hold` node), `rod_grip.tres` (its grips, fitted: carried steady tip-up, the cast and the fishing poses along the fist, slung on the back); the fisher's `Components/Equip` (when the rod goes away: Away After Sec unused, Away When Faster Than a walk; or untick Away When Idle to carry it; the cast waits for it) |
| HUD, reel gauge, standings | — | `fishing_hud.*`, `reel_gauge.gd`, `fishing_standings.gd` |
| Time of day and weather | `fishing_conditions` table, rolled each round; `fishing.json` `conditions` | `fishing_conditions.gd` (reads and names them), `game/world/sky_director.tscn` (the sky) |
| Other players' fights | `fight_show` table (`show_fight`) | `fishing_component.gd` reports ours, `fishing_feedback.gd` draws theirs, moving between their reports |
| The journal and the records | the `catch` table (every catch ever) | `fishing_records.gd`, `catch_journal.gd` |
| Music | — | the scene's `Music` node (`MusicDirector`), `game/fishing/music/` (generated by `tools/synth_music.gd`) |
| The level and its spots | `shared/world/lakeside.json` + depth grid (the bake) | `game/world/lakeside.tscn` |
| The rival angler | in a module world: `fishing_rival` + `rival_tick` (`fishing.json` `rival`; `set_rival 0 false` benches him); in a sidecar world: a brain | `rival_definition.tres` (its display name is his) |

---

## 8. What you can change, and what it takes

**Restart** = stop and press Play again. **Republish** = `tools\publish.cmd` (section 3).
**Codegen** = `tools\publish.cmd --codegen` (section 3).

### Without code: data files
| I want to... | Edit | Then |
|---|---|---|
| change walk/run/sprint speed, jump, gravity | `shared/movement_config.json` | republish; regenerate the animation sets (`tools/animation_set_builder.gd`) or the feet skate; regenerate movement goldens (`shared/golden/GENERATE.md`) |
| add or change a catch, its weight, value, rarity | `shared/fishing/fishing.json` → `catches`, `categories` | republish, restart |
| change what bites where | `fishing.json` → `spots` (loot tables), `open_water` | republish, restart |
| change gear tiers and prices | `fishing.json` → `gear` | republish, restart |
| change bite timing, hook-set window | `fishing.json` → `timing` | republish, restart; regenerate the hook-set goldens (`tools/fishing/gen_goldens.py`) |
| tune the fight | `tools/fishing/gen_fight.py` → regenerates `fight.json` | republish; regenerate the fight golden (`REGEN_FIGHT_GOLDEN=1 cargo test --test fight`) |
| spot depletion and regrowth | `fishing.json` → `economy` | republish, restart |
| round lengths and order, phase names | `shared/rules.json` → `sessions` | `./tools/publish.sh`, restart |
| the lobby: start when everyone is ready, how many players, the teams | `shared/rules.json` → `sessions` → `lobby` | `./tools/publish.sh`, restart |
| a match: how long its first lobby waits, how long an empty world keeps its match | `shared/rules.json` → `sessions` → `match` | `./tools/publish.sh`, restart |
| the splash: its words, colours, a logo, how long it stays | `game/splash_screen.tscn` (Inspector) | restart |
| which genres the game is made of | `shared/game.json` → `genres` | `tools\publish.cmd --codegen`, restart (and export again) |
| a new player's health, the interact range | `shared/rules.json` | `./tools/publish.sh`, restart |
| what each time of day and weather favours, how fast things bite in them, the weather's odds | `fishing.json` → `conditions` | republish, restart |
| the rival: where he stands, which spots, how often he lands | `fishing.json` → `rival` (his name also on `rival_definition.tres`) | republish; `cargo test --test level` checks his reach |

### In the editor: resources and scenes
| I want to... | Open | Then |
|---|---|---|
| change how the rod sits in the hand, for one animation or all | `game/fishing/rod_grip_preview.tscn`: pick an Animation and a Body (both, female, male), drag the Grip node until the labels are green | restart |
| swap a character model or the camera | the definition `.tres` (`game/fishing/fisher_definition.tres`) | restart |
| change key bindings | Project → Project Settings → Input Map | restart (and restart the editor if `project.godot` was edited outside it) |
| move or restyle the HUD | `game/fishing/fishing_hud.tscn` | restart |
| change the water's colours and depths | the defaults at the top of `game/world/lake_water.gdshader` | live in the editor. The lake's material sits inside the generated `lakeside.tscn`, so a change made there is lost when the level is regenerated |
| replace a sound | drop a file over one in `game/fishing/sfx/` | restart |
| change the music, or which phase plays what | the game scene's `Music` node (Tracks: phase number → stream; Default Track) or drop a file over one in `game/fishing/music/` | restart |
| change how dawn, dusk, night or rain look | `game/world/sky_director.tscn`: each time of day's SkyLook and each weather's WeatherLook in the inspector | restart |
| change what the character picker offers | the pieces per slot and body, and the colours: `game/characters/character_looks.gd` (append, never reorder); the looks to start from: the definition's `visual_variants` | restart |
| hold an item in both hands in an animation | the item's grip file → Off hand (`rod_grip.tres` for the rod) | restart; the arms suite checks it |
| add a component to the fisher | `game/fishing/fisher.tscn` → `Components` | restart |
| connection, tick rates, latency simulation, which tables to subscribe to | `game/fishing/fishing_net_config.tres` (`core_tables`; a table whose rows each belong to one world also goes in `world_tables`) | restart |

### With a tool
| I want to... | Run | Then |
|---|---|---|
| reshape the level, move spots, the dock, the spawn | edit `tools/world/lakeside_shape.gd`, run `tools/world/build_lakeside.tscn` | republish (the bake changed); `cargo test --test level` checks spots against rod reach. **Re-running overwrites `lakeside.tscn` and any hand edits** |
| build a level by hand, or change one (the meadow) | open its scene (`game/world/levels/meadow.tscn`), move things, select its `LevelInfo` node and press **Bake For The Server** | republish; the `levels` test suite fails until a changed scene is baked again |
| add or change character looks | `tools/characters/make_looks.py` | restart |
| add animations | `tools/extract_animation_library.gd`, then `tools/animation_set_builder.gd` (read its report) | restart |
| regenerate the default sounds | `tools/synth_fishing_sfx.gd` | restart |

### With code
New mechanics (a table, a reducer, a rule), a new component, a new UI screen. Recipes in 9.

---

## 9. Adding things: recipes

**A new kind of entity** (a chest, a creature): server side, insert an `entity` row with your kind
(100+) and its `movement_state`; what using it does goes in the `on_interact` hook. Client side,
make an `EntityDefinition` with that kind and a scene (instance `player.tscn`, add components),
and add it to `Boot.entity_definitions` in the game scene.

**A new component:** a script extending `SpaceTimeComponent` with `required_tables()` and
`_on_row_updated()`, added under an entity scene's `Components` node. If its table is new, add the
table name to the game's `NetConfig.core_tables`, or the entity waits 2 s and comes up wrong. A
foundation table too: the game's `.tres` lists every table it subscribes (the interest suite checks
each game scene's list against its entities' components).

**A new table and reducer** (genre): declare them in `server/src/game/<genre>.rs`, then
`GODOT=<path> ./tools/publish.sh --fresh --codegen`. Add the table to the game's
`NetConfig.core_tables` (and `world_tables` if it has a `world_id` and each row belongs to one
world), and read it in a component. The SDK logs `unknown table` if codegen was skipped, and
nothing else does.

**A new held item** (a sword):
1. A scene whose root runs `held_item.gd` (or a script extending it), with a `Hold` node (a
   Marker3D) where the hand closes on it: its +Y along the handle out past the thumb (toward the
   blade, the rod's tip), its +Z back toward the wrist. Make the handle about as thick as the fit
   says the fist holds.
2. Mark what must stay off the body: `clearance_radius` metadata (metres) on a node, plus
   `clearance_to` (a NodePath) to make it a line, such as a blade from the guard to the point.
3. An `ItemGrip` `.tres` assigned to its `grip`: its `hand`, and under Fit its **Carry Point**
   (where it points while carried: a sheathed-looking sword might be (0, -1, -0.3)) and **Fit
   Face**.
4. A preview scene like `rod_grip_preview.tscn` pointing at the item, the grip and your
   characters' definition (copy it: it has the Grip, CarryPoint and Stow nodes). Press **Fit Every
   Animation** (it fits the stow too, when the set can draw), then **Save Pictures**, look at the
   sheet, and drag anything that still looks wrong.
5. In the game, `HeldItem.attach` and the driver (section 6).

**A new minigame** (anything a player plays that pays out): use the CHALLENGE pattern. The server
issues a challenge with a kind 100+ (`issue_challenge_internal`), the client plays and submits
its inputs, and `game::resolve_challenge` replays and judges them. Never trust a result a
client reports.

**A new catch or fish:** add it to `fishing.json` `catches` and to a spot's loot table, republish.

**A new look:** add it to `tools/characters/make_looks.py`, run it, add the scene to the
definition's `visual_variants`. The character picker offers it by its file name.

**A new character piece** (a hat, another outfit's boots): import it with
`tools/characters/import_quaternius_characters.py` (that also switches off its LODs), then
append `["Name shown", "File_Without_Gltf"]` to its slot's list for its body in
`CharacterLooks.SLOTS`. Several files joined by `+` are worn together; `""` wears nothing. A new
slot is a new entry in `SLOTS` with its own key. Never reorder or remove an entry: players'
choices are stored by position. The `looks` suite then wears your piece on its body's look and
checks it is bound to that body, and the `character` suite checks it has no LODs.

**A new setting** (a game's own): from any script that runs at start (a HUD's `_ready`),
`Settings.define(&"my_key", "MyGame", "Show the thing", Settings.Kind.TOGGLE, true, {"apply":
func(v): ...})`, or `Settings.define_key(&"my_action", "Do the thing", "MyGame")` for a rebindable
key. It appears in the settings screen on that tab; read it with `Settings.get_value(&"my_key")`
or listen to `Settings.changed`.

**A new choice in the character picker** (beyond the look itself): the look's root script offers
`appearance_options()` (a list of `{key, label, choices, swatches, beside}`; `beside` puts an
option in another option's row) and takes `apply_appearance(text)`; `Appearance.choices(text)`
reads the picks. The picker asks for the options again after every choice, so they may depend on
what is worn (a piece's own colourways). See `game/characters/character_looks.gd`.

**Music for a phase:** the game scene's `Music` node, Tracks: add the phase number and a stream.

**A new level, built in the editor:**
1. A new scene with a `Node3D` root (for fishing, give the root `game/world/lakeside_level.gd`
   and set its **Level Name**). Build the ground with anything that has collision on layer 1
   (CSG with Use Collision, meshes with static bodies, Terrain3D), add water if it has some, a
   light and an environment, and a `WorldRoot` node (where players appear in the tree).
2. Add a `LevelInfo` node: the level's **Level Name** and **Level Id** (unused 1-255), the
   **Water Y**, and **Bake Bounds** around where the water could be.
3. Add markers: a `LevelSpawn` (feet on the ground), `LevelSpot`s for fishing spots (each needs
   a loot table in `fishing.json` `spots` by its id), and `LevelPoint`s for anything else a genre
   needs (a Kind such as "basket", "tee", "coop").
4. Save, select `LevelInfo`, press **Bake For The Server**. It writes `shared/world/<name>.json`.
5. Republish. `spacetime call umf set_world_level 0 <id>` puts world 0 there; the game loads the
   scene the bake names. Copy `meadow.tscn` to start.

**A new genre** (the start of game 2): `server/src/game/<name>.rs` with its tables, reducers and a
`Genre` (copy fishing's impl block at the bottom of `fishing.rs`: claims and the hooks you need),
declared in `server/src/game/mod.rs` behind `#[cfg(genre_<name>)]` and added to `GENRES`; its pure
rules in `server/src/genre/`. On the client, `game/<name>/genre.tres` (a `GenreModule`: its entity
definitions, tables, and scenes). Name it in `shared/game.json`, `tools\publish.cmd --codegen`,
restart.

**A new game:** a list of genres in `shared/game.json`, a game scene (a level, Boot with Load
Genres on, a LevelLoader), and the main scene set to it. See `docs/TEMPLATE_WORKFLOW.md` for
pulling the foundation into its own repository (not set up yet, section 11).

---

## 10. Testing

| Layer | Command | Needs the server | What it proves |
|---|---|---|---|
| Unit + scene | `GODOT=<path> ./tests/run_tests.sh` | no | ~1500 checks, plus architecture lints. Suites added in 0.20.0: `version`, `settings`, `music`, `looks` (the character picker), `fishing_world` (conditions, sky, others' fights, journal); in 0.21.0: `genres`, `lobby`, `levels`; in 0.23.0: `match` (the round a player sees, the lobby screen, the splash) |
| The foundation alone | `./tests/genres_test.sh` | yes (`umf-test`) | the server built with no genres builds, passes and publishes, without any of fishing |
| Arms in every animation | `tests/test_runner.tscn -- --only=arms` (through `run_tests.sh` too) | no | every animation, both bodies: no arm through the body (measured on the skin), the left hand on the rod in two-handed animations. Add `--arm-pictures=grip_pictures/arms` and run it without `--headless` to SEE the worst moments |
| Rust | `cd server && cargo test` | no | movement, challenge, level, fishing and fight rules match their goldens |
| Integration | `./tests/integration_test.sh` | yes (`umf-test`) | every reducer, including the refusals |
| End to end | `./tests/e2e_test.sh` | yes (`umf-test`) | a real client against the real module |
| Multiclient | `./tests/multiclient_test.sh` | yes (`umf-test`) | two players see each other |
| Playtests | `fishing_playtest.sh`, `playtest_test.sh`, `remote_playtest.sh`, `connect_playtest.sh` | yes (`umf-test`) | the game played through real keys. `SHOTS=grip_pictures/play` before `fishing_playtest.sh` plays it in a window and saves a picture of every moment there: look at them after a change to how anything looks |
| Sidecar, export | `sidecar_test.sh`, `export_test.sh` | yes (`umf-test`) | the authority process, the builds |
| The look | `./tests/render_test.sh` | no, opens a window | foliage, grass, water, fullscreen |

On Windows run each through `tools\run.cmd` (section 3), e.g. `tools\run.cmd tests\run_tests.sh`;
they find Godot through `tools\local.env` (the integration suite needs it too: it plays fights
through the client's simulation). The server suites publish and wipe `umf-test`, never
`umf`, so they are safe to run while you play. To run one unit suite while iterating:
`godot --headless --path . res://tests/test_runner.tscn -- --only=grip`.

---

## 11. Where the template is not yet modular

These are the places a designer or a second game would still hit a wall. The whole todo list,
with what the next games need, is `docs/ROADMAP.md`.

1. **The lakeside is still generated.** New levels are built in the editor and baked from the
   scene (0.21.0, recipe in 9), but the lakeside's own scene is written by its generator, and
   re-running it erases editor edits there.
2. **Genres are chosen per GAME, not per world.** One server runs the genres `shared/game.json`
   lists for every world; a world running fishing and another running a different genre at the
   same time is not supported yet.
3. **Content is hand-edited JSON** (`shared/fishing/*.json`, `shared/rules.json`) with no editor
   and no validation short of the build and the tests.
4. **`docs/TEMPLATE_WORKFLOW.md` describes the split into a template** (a tagged foundation,
   `git subtree`), which hasn't been done.
Done since the first inventory (0.15.0): the genre hooks (a game no longer edits `module.rs`),
round plans and player rules as data, a game's per-world tables in its own `NetConfig`, one
publish command, a test database, per-animation grips for held items, (0.20.0) a held item's
off hand as data on its grip, settings as data, a character picker, and (0.21.0) genres as
modules, the lobby, and levels built in the editor.
