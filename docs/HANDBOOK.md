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
| **Foundation** (the template) | `foundation/`, `sidecar/`, `server/src/module/`, `sim.rs`, `challenge.rs` | movement, entities, health, inventory, sessions/rounds, interaction, challenges, NPC brains |
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
  src/module/          foundation tables + reducers, one file per system
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
| `server/src/module/` | every foundation table and reducer, one file per system (`tables.rs`, `movement.rs`, `sessions.rs`, `authorities.rs`, `items.rs`, `challenges.rs`, `actions.rs`, `lifecycle.rs`, `interaction.rs`). A game never edits it: it uses the hooks below and `shared/rules.json` |
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
| `may_choose_character`, `on_character_changed` | a player asks to play another character (Play as) / now plays it | nothing (one character) |
| `on_interact` | someone uses an entity of a kind the foundation does not own (100 and up); range and world are already checked | nothing (it owns no kind) |
| `resolve_challenge` | a minigame of the game's own kind is submitted: judge and pay out | the hook-set and THE FIGHT, replayed |
| `on_challenge_succeeded`, `on_challenge_closed` | a challenge passed / ended in any way | the catch / clearing the line |
| `on_phase_changed` | a session's phase changed (the round machine, or an admin's `set_session_phase`) | the bell: lines nothing has bitten come in |

### Levels: which map a world runs
A world's level is the foundation's `world_level` row: level 1 is the lakeside, 2 the meadow,
0 the greybox test level. `spacetime call umf set_world_level 0 2` (as the publisher) switches
world 0; the game swaps the scene on screen (`LevelLoader`, in the game scene) and moves everyone
into it, players and all, while they play (DECISIONS #250: DiscGolf's holes are levels). Fishing's own `use_level` does the same through the same record. Each genre hears
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

`rate_limits` says HOW OFTEN one player may call a reducer that writes rows everyone receives
(DECISIONS #189): `burst` calls at once, `per_sec` coming back each second; a reducer not named
takes `default`. A call over it is refused ("too many calls") and changes nothing. The shipped
numbers are far above what an honest client sends (the fight is reported five times a second).
A genre's own verb that writes a public row calls `spend_rate(ctx, entity, "<reducer>")` first
and gets a line here; `cargo test --test rate` fails if a limited reducer has none.

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

**Two databases per game:** the game's own (`shared/game.json` `database`: Fishing's is `umf`, the
template's `umf-template`, Fowl Play's `fowl-play`) is the one you play in; `<database>-test` is the
one every test suite uses (and wipes). Every game on one SpacetimeDB server needs its own name, or
publishing one game overwrites another's world. Running the tests never touches your world: suites
pick their database through `tests/lib/db.sh`, and a lint stops one naming the play database.

**The version check: old builds keep working** (`docs/rules/compatibility.md`). A build checks only
what IT uses: the tables it reads and the actions it sends must be the same on the server; anything
the server added is fine. So adding a table or an action and publishing with `--codegen` does NOT
make friends re-download. A server that changed something a build uses refuses it with the reason
on the connect screen ("This server runs a version of the game this build cannot play: ...").
A deliberate break (you retuned movement, or reshaped a table) is made by adding `"compat": 2` to
`shared/game.json` (the next number each time): every older build is then told to update.

### Who is in the world
- **A player who quits leaves the world** after a few seconds (the hot rule `foundation.offline_linger_s`,
  5 s: a connection that drops and comes straight back does not make them vanish). Their character
  is hidden and nothing can bump into it or use it; their progress, catches and records stay. They
  reappear where they left when they come back.
- **Names are unique.** Two players cannot both be "Luke" (nor "luke"). Each copy of the game on a
  computer is its own player (each editor window, each exported build): a second copy you start
  needs another name. If two players already shared a name, the one who had it first keeps it and
  the other becomes "Luke 2" the next time they join. Proper accounts (log in, and be the same
  player on any computer) are on the roadmap.

### Playing with a friend on another computer
1. **Make the build:** double-click `tools\release.cmd`. It exports and tests both builds, records
   what this build needs from a server (`shared/compat/`: commit it, so later changes are checked
   against this build), and zips the client to `build\releases\<game>-<version>.zip`. Send that:
   `umf.exe` holds the whole game, and `libterrain...dll` (Terrain3D) sits beside it. For a Mac it
   also makes `<game>-<version>-mac.zip`: one app for Intel and Apple Silicon Macs (the "macOS
   Client" preset, through `tools/mac_export.sh`, which gives it this game's own bundle identifier,
   `com.umf.<title>`). A Mac build is only a player: your PC still runs the server and the referee.
   Every GDExtension a game uses needs its Mac library on THIS machine for that (the export test
   says which one is missing), and the macOS export template installed (Editor > Manage Export
   Templates).
2. **Host it: double-click `tools\host.cmd`** and leave its window open while you play. It starts
   SpacetimeDB listening for other machines (`--listen-addr 0.0.0.0:3000`; a plain `spacetime start`
   only listens on your own PC) and the world's REFEREE, which drives every bot and judges attacks.
   Without one the bots stand where they spawned: pressing Play in the editor starts a referee for
   you, but a friend's build (or your Mac) cannot, and nothing else does. Closing the window stops
   both. Then let them reach it:
   - **Windows Firewall, once** (an admin Terminal: right-click Start, Terminal (Admin)):
     `New-NetFirewallRule -DisplayName "SpacetimeDB 3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow -Profile Private,Public`
     By PORT, not by program: SpacetimeDB's own rules name one version's exe, which an update moves.
   - **Same house:** give them your LAN address (`ipconfig`, the IPv4 one, like 192.168.1.20).
   - **Over the internet:** the easiest is Tailscale on both machines (they type your 100.x
     address; no router changes). Or forward TCP 3000 on your router to your PC (give the PC a
     reserved address in the router so the forward keeps pointing at it) and give them your public
     address. A port forward lets anyone on the internet reach the server; Tailscale only your
     friends. To check from their machine: `curl -s -o /dev/null -w "%{http_code}" http://<address>:3000/v1/ping`
     prints 200.
3. **They run it.** Windows SmartScreen says "Windows protected your PC" for an unsigned game:
   More info, then Run anyway. On a Mac (it is signed ad hoc, not by an Apple developer ID, so
   macOS says it "could not verify" it the first time): unzip it and open it once (Done), then System
   Settings > Privacy & Security, scroll to Security, "Fowl Play was blocked...": Open Anyway, your
   password, Open Anyway again. Or in Terminal, once: `xattr -dr com.apple.quarantine "<the app>"`
   (drag the app onto the Terminal window for its path). Right-click > Open no longer does it on
   macOS 15 and later. Selling on Steam or anywhere
   else wants an Apple Developer ID ($99 a year) to sign and notarize it: the preset's codesign and
   notarization settings, which Godot can do from Windows. They type your address on the connect screen, pick a name and a
   character, and connect.
4. **If something breaks:** Escape, then Open log folder; they send you `godot.log`.
5. **After you change the server**, publish with `--codegen`. Their build keeps working unless you
   changed something it uses; the unit tests tell you before you publish (the release snapshot),
   and if you did it on purpose, bump `compat` and send a new build.
6. **What is NOT in the export:** editor tooling. Both presets leave out `addons/godot_ai/` (the
   AI bridge) and `addons/umf_export/`, the small editor plugin that takes the bridge's autoload
   out while exporting (DECISIONS #190). Another editor addon that adds an autoload goes in its
   `EDITOR_ONLY_AUTOLOADS`; the export test fails if any of it is in a build.

Voice: use Discord alongside for now (the roadmap has voice chat later).

### How it ran for them, and what they said (telemetry and feedback)
Every player's game and every referee reports to the HOST how it ran (DECISIONS #244), always, in
every game and genre: once a window (`foundation.telemetry_window_s`, 30 s) one small call with its
frame times (median, 95th, 99th, worst), each SPIKE with the moment it happened (a frame slower than
`foundation.telemetry_spike_ms`, or the server's rows stopping for 0.4 s: a network stall), ping,
corrections, memory, entities, and the machine coarsely (OS, CPU, GPU, memory). Nothing personal, and
nothing a client receives: the tables are private, read by the database's owner.
- **Feedback: F8** (or Send feedback in the Escape menu). The moment is marked as the key is pressed;
  they pick Bug, Lag, Idea or Other and write. The server adds who, where (their position), the level,
  the round and the phase from its own rows. While you host, it shows up in `tools\host.cmd`'s window
  with a bell.
- **To read it all: double-click `tools\feedback.cmd`** on the machine that hosts: each piece of
  feedback (when, who, what, where, how their game was running then, and the referee's recording of the
  round with the second it happened at), then performance per player and per referee (frames, worst
  frame times, spikes and stalls with their times, ping, corrections).
- **What the bots did: `python tools/replay/analyze.py [recording]`** (the newest recording on this
  machine by default): per bot, how far it walked and how straight, reversals a minute, its time in each
  step of its brain and its flip-flops (a step, another and back within 3 s). The recordings write each
  bot's decisions (`"ev": "brain"`) beside where everyone was.
- Adding a number: put it in the report's `detail` JSON (`Telemetry.send_window`): the table never
  needs reshaping.

### Who moves things (motion authority)
Each world picks one:
- **MODULE (Tier A, what fishing uses):** your client simulates your movement and tells the
  server where you are; the server only checks you could have moved that far that fast, and clamps
  a claim it doesn't believe. It also checks WHERE: a claim that walks off standable ground into
  water too deep to wade is refused (the level's bake says where; DECISIONS #188). Cheap, no
  server physics.
- **SIDECAR:** a headless Godot process (`sidecar/`) runs real physics for the world and is the
  authority. For games where the server must see walls (NPCs, survival). The fishing rival angler
  NPC is driven by a sidecar brain.

### Who judges an attack (the referee)
An ability marked **Judged by a referee** (its `.tres`: `judged`, with its reach, width and height) is
not decided by the server's coarse range check. It goes to the world's **referee**: a sidecar that
looks at the level's real walls and at everyone where the attacker saw them (rewound by what that
player's screen showed, at most `foundation.rewind_max_ms`, 150 ms, favouring the attacker), as the
ability lands (its wind-up after the press). It answers hit or miss; what a hit does is the genre's
(Fowl Play: a hen injured, then downed), or the ability's damage. DECISIONS #226.

- **A sidecar's jobs, per world.** In a MODULE world it only judges (players still move themselves);
  in a SIDECAR world the same process moves everyone and judges. Driving NPCs while players move
  themselves is the next job it takes on (bots, FOUNDATION_SYSTEMS milestone 7). Which a world runs is
  `world_config.sim_authority`; switching later does not change how attacks are judged.
- **You start nothing.** Pressing Play in the editor, the admin's instance starts the referee in the
  background if the game has a judged ability and the world has no referee (`RefereeLauncher`): it
  hands it a one-time code (`offer_referee`), the sidecar presents it (`claim_referee`) and is
  registered, and it stops when your game does. A host starts it beside the server
  (`godot --headless --path . res://sidecar/sidecar_main.tscn -- --world=0 --referee`, registered once).
- **No referee, no guess.** While none is online a judged ability is refused ("no referee"); one
  that lands with nobody to answer is a miss.
- **Hitboxes** are each character's body (`collision_radius`, `collision_height` on its definition).

### Carrying (attach and carry)
One entity can carry another (a wolf, a downed hen). A genre decides when, from its own rules, and
calls `attach` / `detach` (`server/src/module/carry.rs`); the foundation does the rest: the carried
one is CARRIED (it cannot move, act or be hit), the server keeps it where its carrier is, and every
client draws it at the carrier's **carry point**: `carry_offset` and `carry_yaw_deg` on the carrier's
character `.tres` (in its own terms: x right, y up, -z ahead). Put down, it stands where the genre
says, in the status the genre says (else the one it had before). DECISIONS #228.

### Bots
A bot is an NPC that plays: a member of a session (it scores, it is in the standings) with an
`npc_brain` row naming its brain. A genre adds them (`add_bot_internal`, from its rules: Fowl Play
fills each night to one wolf and four hens) and they go with `remove_bots_internal` or a despawn; an
admin can add one by hand (`add_bot`). The world's referee builds and drives every bot (players still
move themselves): its brain thinks a few times a second and walks a path its body fits (a walk map
baked from the level's collision), and holds, lets go or uses an ability the way a player would, so
the server judges a bot as it judges a player. A genre's brains are scripts in
`sidecar/npc/brains/<genre>/` (Fowl Play's `chicken/hen`, `chicken/wolf`). DECISIONS #230.

A brain may run a **behaviour tree** (LimboAI, in `addons/limboai`, DECISIONS #245): its `think`
calls `run_tree("res://sidecar/npc/brains/<genre>/<name>_tree.tres", me, world)`. Open the tree in
the LimboAI tab (the editor's main screen tabs): each step is a task, its numbers in the Inspector;
drag tasks to reorder them. A genre's tasks extend `BrainTask` (`sidecar/npc/brain_task.gd`), whose
`brain()` is the bot that runs it. Nothing to republish: a tree is the referee's, and a restarted
referee (Play again) reads it. The add-on ships libraries for Windows, Linux and macOS only.

### Bodies: things thrown that the referee flies
A disc, a ball, an egg: something thrown that then flies by real physics is a BODY (DECISIONS #246).
What it is is content, `BodyDef` (`foundation/content/body/`, a genre's `game/<genre>/content/body/`):
its shape and size, mass, bounce, friction, drag in the air and on the ground, gravity, who may throw it
and how hard, how many each, how long it lasts, its look, and what else pushes it in flight (`forces`, a
`BodyForces` a genre writes: a disc's lift and fade). Open one in its bench (`tools/workbench/
body_workbench.tscn`: its size by the character, its hardest throw's arc, its bounce, its limits). A
change to "Launching" needs a bake and a publish (`tools\publish.cmd`); the rest is read by the game and
the referee as they start.

In the world a body is an entity (kind 3) the world's REFEREE flies: Play in the editor starts one when
the game has bodies (or a judged ability). Nothing thrown flies without one, so a throw is refused while
none is running. The thrower sees it leave the hand at once (their game flies its own copy and is kept
near the referee's: `foundation.body_correct_share`, `foundation.body_snap_m` on the Rules page);
everyone else sees the referee's. What a body hits fast is said to everyone (a `body_contact` row) and to
the genre (`on_body_contact`: a disc in the chains, a ball to the face), and so is its coming to rest.

To try it in the template: the greybox game, hold G and let go to throw the foundation's ball
where you look. A genre throws its own with `BodyLaunch.throw_body` (or its own reducer calling
`launch_body_internal`, beside `BodyLaunch.fly` for the thrower's view). Tested by the `bodies` suite, the
integration suite's bodies section and `tools\run.cmd tests\bodies_playtest.sh` (a real referee and two
clients at 150 ms).

### The server pushes people (and bodies)
A genre's rule that moves someone (a leaf blower, a bounce pad, a hit) writes a push:
`push_entity(ctx, entity, vel, by)` (DECISIONS #251). Players still move themselves: the pushed player's
own game adds the push to their speed, at once, and carries it a while; the server, which wrote it, lets
them move that fast meanwhile (`foundation.push_grace_s` on the Rules page is its allowance for lag). A
pushed body (a disc) is moved by the world's referee. `dev_push <entity> <vel>` (with the dev tools on)
tries it; `tools
un.cmd testsodies_playtest.sh` proves it at 150 ms.

### Aiming, charging and the flight cam
A throw that is held to charge and let go (a disc, a ball, a cast) is `AimCharge` (`foundation/input/`):
add one to the game scene and give it its keys (`actions`: each a style, a disc golfer's backhand on one
and forehand on another), how long a full charge takes and where overcharging starts. While a key is
held the body faces where the player looks and moving the mouse up and down sets the release angle (the
view's tilt is held); letting go says what was thrown (`released`), and the genre throws it
(`BodyLaunch.throw_body`, its own reducer). `ChargeBar` (`foundation/ui/`) draws the charge: put one in the
HUD and point it at the AimCharge; give it the band you call good.

`FlightCam` (`foundation/camera/`) makes the camera follow what was thrown: call `follow_throw` as you
throw. It follows the ball from the hand, holds on it a moment where it lands, and comes back (at once
if the player runs). How it frames it is a `FollowCamConfig` (`foundation/camera/follow_cam.tres`);
players turn it off in Settings, Game, "Follow what you throw". In the greybox: hold G and let go.

### What a world hears (noises and pings)
A noise is a row everyone in a world receives as it is made: an egg cracking, a raid, a player's
ping. The server says what happened and where (`make_noise` in a genre's rules, numbered from 100;
the `ping` reducer for a player, kind 1); what it sounds like, how far it carries and who sees a
marker is content (`content/noise/*.tres`, a `NoiseDef`). One kind can sound different for each
character that makes it (`made_by`: Fowl Play's hen bawks, its wolf growls). The ping key (`ping`)
pings where the player looks; a genre says what the marker reads (`NoiseFeedback.callout`). DECISIONS #233.

### A recording of every round
Every sidecar, the referee too, writes each round of its world to `user://recordings/` (Esc menu,
Open log folder, then up one): where everyone was, ten times a second, and what happened. Open
`tools/replay/replay_viewer.tscn` and press F6 to watch the newest; `[` and `]` step through the
others, H shows where people were hurt and where pounces landed or missed. DECISIONS #235.

### Walls an entity puts up (a gate, a haystack)
A character can be a wall while it is in some statuses: `blocker_size` and `blocker_offset` (a box,
from its feet, in its own terms) and `blocks_in` (the statuses it blocks in; empty: always) on its
`.tres`. Fowl Play's gate blocks while Shut; its haystack always. Every client builds the box
(`EntityBlocker`, on the level's layer: bodies stop at it as at a fence), and the referee builds its
own, so a pounce stops at it too. The server's module never sees it: a genre that raises one keeps
people out of it first. A genre moves an entity at once (a vault, into a hiding place) with
`place_entity`. DECISIONS #229.

---

## 4. How a player gets into the world

Step by step, from pressing Play:

1. **Godot starts `lakeside_game.tscn`.** Its `Boot` node (`foundation/boot.gd`) hands the
   `EntitySpawner` the game's ENTITY DEFINITIONS (fisher, spot, rival), plays the SPLASH
   (`game/splash_screen.tscn`: the game's name and its tips and lore for 5 s; any key skips it;
   Settings, Game: "Splash screen at start" turns it off) and shows the connect screen.
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
   on a stage in their looks, Play as (which character, when the game has several: a hen or the
   wolf; C in the in-world lobby), Choose look (the picker), Ready (or R). When everyone here is
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
acceleration, reconciliation). Gaits: a plain key RUNS, Shift sprints, Ctrl walks. A character's
own numbers are its movement profile (`content/movement/*.tres`); `turn_rate_full` there makes a
heavy body swing round slowly at speed (Fowl Play's wolf: 180 degrees a second, 360 when slow), and
0 turns at once. Changing the model means new golden vectors (`shared/golden/GENERATE.md`).
A SLOW PLACE in a level (a hedge's hole, mud) is a `LevelSpeedZone`: a box with a pace (0.4: 40 % of
anyone's speed in it), on top of their status (DECISIONS #231). An ability that `lunges` (a pounce)
throws its user forward by their movement profile's dash as its wind-up ends (DECISIONS #232).
A character GLIDES (`glide_fall_speed`: holding jump after a flap it falls slowly) or FLIES (a status
with `hover_height`: held that high, steering as on the ground) by numbers in the same model (DECISIONS
#236). An ability can have its own KEY (`AbilityDef.key`: an input action, e.g. `power` on the right
mouse button); without one, a character's first ability is on the attack key (DECISIONS #237).

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
- **The quick way, for a weapon or tool held the same in most animations** (DECISIONS #259): in the
  preview, pick a **Body** (`both` for everyone) and an **Animation**, type the item's **Hold**
  (position and rotation in the hand) or drag the Grip node, then press **Use This Grip For All**.
  Every animation now uses that one grip, FOR THE BODY CHOSEN: with `male` picked it replaces his
  grips only and hers stay as they are (hands differ); with `both` it replaces everyone's. Step through the other animations; where one looks wrong,
  type or drag it right there: that saves a small fix on the one grip, which keeps following it if
  you move the one grip later. **Clear This Grip** puts an animation back on the one grip. The grip
  file is at the bottom of the Inspector; you never need to open its list. Changes are written to
  the grip file when you **save the scene** (Ctrl+S; the tab shows `*` until then), not on every move.
  To turn a blade's edges (or an axe's head) without moving the handle, use **Spin 15°/-15°/90°**:
  they turn the item on its own length, about the fist. The 3D view's rotate rings turn about the
  WORLD's axes unless Local space is on (press **T**).
  The **Animation** list says what each one is: an ability's name and the clip it plays
  (`ability.40002 · Slash (second) · Sword_Light_B`, `locomotion.run · Jog_Fwd`).
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
- Camera: `foundation/camera/third_person.tres` / `first_person.tres`, chosen per definition. A rig's
  `while_carrying` is the view while its entity carries someone (the wolf with a hen: third person).
  The player's comfort settings sit on top: Field of view (wider or narrower than the rig's), Head bob
  in first person (off by default), Third person while carrying (on). DECISIONS #234.
- The HUD: `foundation/ui/hud.tscn`, one status line (connection, then the round). The greybox game
  carries it as `HUD`; a genre's own `HUD` scene (its `genre.tres` `scenes`) replaces it, and any
  genre scene named like one of the game scene's children replaces that child the same way.
- **The game's look: one style file** (`foundation/ui/kit/`, DECISIONS #265). Every control in the game
  (the Esc menu, settings, a genre's windows and buttons) is drawn with the game's `UiStyle`: its colours
  (panel, edge, title bar, text, accent, good / warn / bad, buttons, slots), sizes (corners, padding,
  button height, slot size, font sizes) and fonts. **To reskin a game** (a fantasy look): make a `.tres`
  of `UiStyle` (in the FileSystem dock: New Resource, UiStyle), change it in the Inspector, and set the
  project setting `umf/ui/style` to it. Nothing else changes; every screen follows. Without it a game has
  the foundation's dark blue.
- **Building a window for your game** (an inventory, a crafting station, a journal): `UiWindow.new()`, set
  `title` and `place` (center, right, left), add your rows to its `content`, `open()` it. It has a title
  bar you can drag, a ✕, Escape closes it, and it frees the cursor while it is open. Put it on your HUD's
  CanvasLayer. For its rows: `UiKit.heading`, `UiKit.note` (small, dim), `UiKit.line(text, role)` (a
  line in the style's good / warn / bad / accent colour), `UiKit.button`, `UiKit.slot_grid`; an item is a
  `UiSlot` (its colour or picture, its initials, a count, picked or not, a tooltip). Never type a colour
  into a screen: ask `UiKit.colour(role)`, so a reskin reaches it.
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
| the splash: its words, its tips and lore (`lines`, one every `line_sec`), colours, a logo, a picture behind it, water ripples, how long it stays | `game/splash_screen.tscn` (Inspector) | restart |
| which genres the game is made of | `shared/game.json` → `genres` | `tools\publish.cmd --codegen`, restart (and export again) |
| what each time of day and weather favours, how fast things bite in them, the weather's odds | `fishing.json` → `conditions` | republish, restart |
| the rival: where he stands, which spots, how often he lands | `fishing.json` → `rival` (his name also on `rival_definition.tres`) | republish; `cargo test --test level` checks his reach |

### In the editor: resources and scenes
| I want to... | Open | Then |
|---|---|---|
| tune the game WHILE IT RUNS (the interact range, a new player's health; more to come): every player follows at once, no republish, no re-download | as the admin (the PC that publishes), in game: Escape, **Rules (admin)**. To keep the values: the Content panel's **Keep live tuning**, then Publish | nothing else: it is live. Reset puts a rule back |
| change a hot rule's default, or add one | the Content panel, type `rules`: `foundation.tres` (the foundation's) or your genre's rule set; a genre sets ITS game's value for a foundation rule under `overrides` | `tools\publish.cmd` |
| change an ability (cooldown, range, wind-up, damage) or add one | the **Content** panel at the bottom of the editor: pick `ability`, pick the piece (it opens in the Inspector, whose tooltips say what each number does), or type a name and press New | `tools\publish.cmd` (it bakes first, `docs/rules/content.md`); the next connection brings an existing database's abilities in step with the build, no `--fresh` (DECISIONS #226) |
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

**Workbenches: make and try content without a server (DECISIONS #203, #207).** In the Content
panel (bottom), pick a piece and press **Open workbench** (or click its card in the **Catalog** tab).
Two things happen, and they never mix:
- the **Inspector** shows the PIECE: every field you change there is the piece's own (the Hen's run
  speed, the chicken's `visual_scale`);
- the **Workbench** panel (beside the Inspector) shows the BENCH: the piece's badge (green, amber,
  red, and why), the others of its type to switch to, its **tests** (buttons that say what they
  play), its **settings** (which animation, which character it is tried on, how fast to replay) and
  its **actions**: Play as this, Save, New from this, Copy into a genre, Capture thumbnail.

The bench redraws as you edit, and it keeps nothing in its own scene: using one never changes it. The
Catalog shows every piece with a coloured strip (red: something is wrong; amber: fine but not yet
looked at in its bench; green: done); **Regenerate thumbnails** redraws every picture.

**In a game, the template's content is read-only.** Fowl Play's Content panel makes new pieces for
`chicken` only. A piece of the foundation's (the humanoid, `downed`) is the template's: the next
update from the template replaces it, so its bench offers **Copy into chicken** instead, a copy
that takes its place where the type allows (the same kind for a character, the same number for a
status). Saving a template piece anyway is warned about in the Content panel's log.

**Making a character, in order.** Dependent things are made from the thing they hang off:
1. **The character.** Content panel, type `character`, open any one on its bench. Drag the rigged
   model (.glb, .gltf) from the FileSystem onto the bench's **Intake File** (select the bench's top
   node to see it), then **New From File**. The new character has the model, a body fitted to it,
   and, when the model brings clips of its own (a chicken's Idle, Walk, Jump), an animation set made
   from them (each clip matched to what the game plays; the ones it lacks stood in, and named).
2. **Fit it.** In the Inspector: `visual_offset` until its feet are on the floor, `visual_yaw_deg`
   until it faces the yellow arrow (the game's forward), `visual_scale` for a model made at another
   size. The pale capsule drawn AROUND it is its body (`collision_radius`, `collision_height`: what
   it collides with and others bump into); **Fit the body to the model** sizes it to the model's
   CORE (a beak, head feathers, a tail left out), and **Body height** / **Body radius** beside it
   fine-tune it, the capsule following. The badge goes amber, with the number to set, while the
   feet float or the body does not fit.
3. **Look at it.** The Workbench panel's **Animation** plays ANY clip: what the game plays for each
   thing (`locomotion.walk`), any clip of its set, or the model's own (`model: Walk`), with
   **Speed**, **Paused** and **Position** to hold or scrub a frame; **Look** wears any of its looks.
   An edit keeps the frame you are on.
4. **Its animations.** Under "Animations the game needs", each thing the game plays is a choice of
   clip; Save keeps them. (A set made for many characters, like the humanoid's, is shared: change it
   where it is made, or make the character its own with **Animation set from the model**.)
5. **Its movement.** **New movement for it** makes a movement profile (starting as the game's
   default), links it, and opens it on the movement bench. There, each test is PERFORMED by the
   character: **Start and stop** (to a full sprint, let go, slide), **Jump**, **Flaps**, **Turn
   around**, at real speed (or slower: Replay speed), with a ruler under it, the moments labelled
   where they happen and its speed over its head. Change a number in the Inspector and it plays again.
6. **Its abilities.** **New ability for it** makes one, lists it on the character (the server lets
   a character use only the abilities its kind's characters list; a kind that lists none may use
   any), and opens it on the ability bench, tried on that character.
7. **Play as this.** On the character's bench (or a movement's) **Play as this** runs the game as it.
   A change the server reads (a speed, a range) is published first; a look, an animation or a fit
   plays at once. Content with a problem is not played until it is fixed. A movement or ability
   made INSIDE the character (the Inspector's New on its field) is saved as its own piece first.

Moving between them: a bench opened from another shows **← Back to …** at the top of the panel;
the movement and ability benches always offer **Open character: …**; the character bench offers
**Open** for its movement and each ability.

**Rules have no bench:** the running game is theirs. Change a default in the Inspector (Content
panel, type `rules`); a game changes the template's with an entry in its genre's rule set
(Overrides); try values live as the admin (in game: Escape, Rules), then **Keep live tuning** writes
them back.

**Statuses: downed, out, and a genre's own.** Content panel, type `status`. The foundation's seven
(normal, injured, downed, carried, out, hidden, escaped) are the defaults; to change one for your
game, make a status in your genre with the SAME number (Fowl Play's downed: number 2, crawling at
0.1): the game uses yours. A new one of your own is numbered 100 or more (a stashed chicken). Open
one in its bench and run **moves** (how fast a character crawls in it, whether it can jump),
**burst**, **pose** (its clip on the character: amber when the character has none) and **timeline**
(how long it lasts and what it becomes). To feel one in the game: play as the admin, Escape, Rules,
**Try a status on yourself**. In code, a genre sets one with `set_status_internal` and hears changes
in `on_status_changed`; when one runs out, `on_status_expired` may choose what it becomes.

**Holds: something done by holding E (help up, lay an egg).** Content panel, type `hold`. The
foundation's **Help up**: hold E on a downed teammate (or NPC) for 4 s, faster together (2.5 s with
two, 2 with three), and they are back on their feet; moving away or being hurt lets go, and the help
is lost. A hold of your own: pick what it is done to (`done_to`: characters), who may do it
(`done_by`; none: anyone), the target's status it needs (`only_when`), `seconds_with` (alone, then
two, three together), what stops it, whether a half-done one keeps its progress (a nest), and the
status the target is left in when done. Try it in the game with two players (one downed with **Try a
status on yourself**; Rules also has **Go to** a player). What your character faces within reach is the
target (a 120-degree arc in front of it: `InteractionComponent.front_arc_deg`); in third person the
crosshair has no say, in first person it goes first (`targeting`, AUTO from the camera rig). In code, a genre refuses one in `may_hold`, changes its speed in `hold_rate`
(a nest cooling while nobody sits on it) and hears it done in `on_hold_completed`; its bots hold with
`begin_interact_as`. It moves one along or back with `nudge_hold` (a raid cools a nest), and says why
one would be refused, on the prompt, with `HoldPrompt.add_note`.

**Skill checks: press when the marker is in the zone.** Server-timed (DECISIONS #210): the player's
game says only "pressed" and the server works out where the marker was when they saw it, so lag does
not cost a good press and a cheat cannot claim one. Its key is Space (Settings: Skill check), so a
check can come up while E is held for something else (an egg wobbling under a sitting hen); E also
presses one when nothing is held, and Space does not jump while one is up. In code,
`issue_challenge_for(entity, difficulty, payload)` starts a scored three-press one; a genre's own
(`issue_timed_press(entity, difficulty, rounds, scored, payload, ttl)`) can be one press, and
unscored when what it pays is the genre's (warmth, not points). The genre hears it end in
`on_challenge_closed` and reads how it went with `press_result` (None: it ran out of time), graded
Great/Good/Miss by `challenge::grade`, the bar's own words; `close_if_expired` ends one on time from
the genre's own tick.

**Characters a player chooses.** Tick **Playable** on a character (its definition, How it plays) and
the lobby offers it (Play as); the server lets a player become it (`choose_character`) in the lobby.
The player's entity becomes that kind and every client builds it again as that character (its model,
body, movement, camera). A genre caps who may be what (`may_choose_character`), follows a change
(`on_character_changed`: a team), and starts a new player as its character (`set_character_internal`
in `on_player_created`). The foundation's own characters are not playable; a game marks its own. Tune it live in the Rules page: how long the marker
waits before moving (`press_lead_in_ms`), how fast it sweeps (`press_sweep_easy_s`, `_hard_s`), how
much a player's lag is forgiven (`press_credit_cap_ms`). The HUD draws it (`TimingBar`).

**Content (an ability; later items, species, levels): a resource, not a file of JSON.** Each kind
of content is a type (`AbilityDef`); each piece is a `.tres` you edit in the Inspector. The
**Content** panel at the bottom of the editor is where you find and make them: the types on the
left (a red mark when something is wrong with one), the pieces in the middle (search; New makes one
with the next free id in the right folder, `foundation/content/<type>/` or
`game/<genre>/content/<type>/`), and the toolbar: **Validate** (every problem, in words; click one to
open the piece), **Bake** (writes `shared/content/` for the server), **Publish** (bakes, builds and
publishes, its output in the panel) and **Play**. The server refuses to build while a piece was
changed without a bake, and names the file; Publish bakes first, so you rarely see that. A new TYPE
of content is a developer's job, and needs no change to the panel: `docs/rules/content.md`.

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
   scene the bake names. Copy `foundation/level/example/example_level.tscn` to start.

**A new genre** (the start of game 2). EVERY FILE IS EITHER THE FOUNDATION'S OR ONE GENRE'S, and a
genre's files are listed in `tools/template/genres/<name>.paths`: that list is what makes a game
without it (`python tools/template/strip_genre.py <name>`), so keep it complete. A genre has:
- **server:** `server/src/game/<name>.rs` (its tables, reducers and a `pub static <NAME>`, the name in
  capitals, implementing `Genre`: copy fishing's impl block at the bottom of `fishing.rs`); its pure
  rules in `server/src/genre/<name>/`; any content it compiles in as `server/build/<name>.rs`, with
  two lines tagged `// genre:<name>` in `server/build/genres.rs`; its native tests in
  `server/tests/<file>.rs` starting `#![cfg(genre_<name>)]`. You do NOT declare it anywhere in the
  foundation: build.rs declares the modules of every genre `shared/game.json` lists.
- **client:** `game/<name>/genre.tres` (a `GenreModule`: its entity definitions, tables, and scenes);
  its data in `shared/<name>/`.
- **tests:** unit suites in `game/<name>/tests/suites/` (the runner finds them, after the
  foundation's), sharing a `game/<name>/tests/<name>_suite_base.gd`; shell checks as HOOKS,
  `game/<name>/tests/hooks/<point>.sh`, sourced where a foundation suite calls `run_genre_hooks
  <point>` (integration_init, integration_levels, integration_genre, integration_genre_late,
  integration_match_began, multiclient, genres_absent, genres_present, export_client); windowed checks
  in `game/<name>/tests/render/`.
Name it in `shared/game.json`, `tools\publish.cmd --codegen`, restart.

**A new game** starts from the TEMPLATE (`UMF Template`, a repo of the foundation with no genres; its
main scene, `game/greybox_game.tscn`, plays the foundation's character on the greybox). Clone it,
add genres, and take foundation updates with `tools\update_from_template.cmd` (it runs `git pull
template main`, then codegen and the unit suite; the steps, and where work
goes: `docs/TEMPLATE_WORKFLOW.md`; the codegen is needed because the bindings are each game's own
and a pull keeps the game's copy). Fix the foundation
in the template, never in a game, or the fix stays in that game. What a repo is (its genres,
database, state) is its `GAME.md`. A game made from a game with
a genre you do not want: `python tools/template/strip_genre.py <name>`. The reference content every
game keeps: the humanoid looks and animations (`game/characters/`, `game/anim/humanoid*`), the greybox,
and the example level (`foundation/level/example/`, level 200).

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
| Playtests | `fishing_playtest.sh`, `playtest_test.sh`, `remote_playtest.sh`, `press_playtest.sh`, `connect_playtest.sh` | yes (`umf-test`) | the game played through real keys. `SHOTS=grip_pictures/play` before `fishing_playtest.sh` plays it in a window and saves a picture of every moment there: look at them after a change to how anything looks |
| Sidecar, export | `sidecar_test.sh`, `export_test.sh` | yes (`umf-test`) | the authority process, the builds |
| The look | `./tests/render_test.sh` | no, opens a window | foliage, grass, water, fullscreen |

On Windows run each through `tools\run.cmd` (section 3), e.g. `tools\run.cmd tests\run_tests.sh`;
they find Godot through `tools\local.env` (the integration suite needs it too: it plays fights
through the client's simulation). The server suites publish and wipe `umf-test`, never
`umf`, so they are safe to run while you play. To run one unit suite while iterating:
`godot --headless --path . res://tests/test_runner.tscn -- --only=grip`.

Each unit suite is its own file, `tests/suites/<name>.gd`, extending `tests/suite_base.gd` (the
counters, `_check`, and every helper two suites share). A new suite is a new file there plus its
name in `SUITES` in `tests/test_runner.gd`, in the order it should run; the runner fails on a file
it does not list.

**The dev tools** (`teleport`, `dev_nudge`) are off for players on every database (DECISIONS
#187); an admin (the identity that published) can always use them. The suites whose clients
teleport turn them on for `umf-test` with `spacetime call umf-test set_dev_tools true`. Never
turn them on for a database friends play on: a player could teleport anywhere.

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
Done since the first inventory (0.15.0): the genre hooks (a game no longer edits `module.rs`),
round plans and player rules as data, a game's per-world tables in its own `NetConfig`, one
publish command, a test database, per-animation grips for held items, (0.20.0) a held item's
off hand as data on its grip, settings as data, a character picker, and (0.21.0) genres as
modules, the lobby, and levels built in the editor, and (0.25.0) the template, a repo the games fork.
