# Roadmap: the todo list

What is left, in the order it pays off. Each item says roughly how big it is (S: a session, M: a
few, L: a phase) and what needs it. Tick items off here when they land, and move the reasoning to
`docs/DECISIONS.md` as usual. The handbook's section 11 lists the places the template is not yet
modular; most of them appear below.

---

## 1. Before the first test with a friend on another computer

The game is playable end to end and both export presets work (`tools\run.cmd tests\export_test.sh`
builds and runs them). What is missing is mostly about two people on two machines.

| | Item | Size | Why |
|---|---|---|---|
| ☑ | **Pick how the friend reaches your server.** (Handbook §3, "Playing with a friend".) Same house: `spacetime start --listen-addr 0.0.0.0:3000`, allow port 3000 through Windows Firewall, and they type your LAN address on the connect screen (the screen says so). Over the internet: Tailscale on both machines (they type your 100.x address; no router changes), or forward TCP 3000 on your router to your PC. SpacetimeDB's hosted Maincloud works too, but its database names are global, so the client would need `--db=<your name>` at launch until the connect screen has a database field. | S | Nothing is reachable from outside your PC today. |
| ☑ | **A version check on connect.** (0.20.0, DECISIONS #164.) The client and the published module must match; a friend on last week's build against today's server fails in confusing ways (tables or reducers that do not exist). Have the module report a version the client checks, and the connect screen say "your game is out of date". | S | You will republish between test sessions. |
| ☑ | **Mouse sensitivity and volume in the Esc menu** (0.20.0: the whole settings screen, #165), saved per machine. Today sensitivity is a value on the input component and there is no volume control at all. | S | Their mouse and speakers are not yours. |
| ☑ | **Where their log is.** (0.20.0: Open log folder.) Exported builds write `logs/godot.log` in the game's user folder (`tools/print_user_dir.gd` prints it). Add an "Open log folder" button to the Esc menu so a friend can send it to you. | S | The first bug report will be "it broke". |
| ☑ | Tell them about Windows SmartScreen: an unsigned `.exe` shows "Windows protected your PC"; More info, then Run anyway. | none | |
| ☐ | Optional polish already noted: her idle grip puts the reel 0.9 cm into her right thigh (retune in `rod_grip_preview.tscn`); walking during a fight turns her away from the line. | S | Looks, not function. |

Text and voice chat are not needed for a first test: use Discord alongside.

---

## 2. Fishing: features worth adding

The loop is complete (cast, bite, hook-set, the fight, catches, depleting spots, the shop, rounds,
standings). These would make it a game people come back to.

| | Item | Size |
|---|---|---|
| ☑ | **A catch journal** (0.20.0, #171): every kind caught, biggest of each, first-catch moments, rarities still missing. Persistent per player. | M |
| ☑ | **Other players' fights, shown.** (0.20.0, #170) The fight is private (the server replays it at the end), so a friend watching sees nothing happen. A coarse public state (on, heaving, running, landed) would let them watch and cheer. | S-M |
| ☑ | **Music and ambience** (0.20.0, #167) (the sound effects are generated; there is no music). | S |
| ☑ | **Time of day or weather changing what bites** (0.20.0, #168), so the same spot plays differently through a session. | M |
| ☑ | **All-time records and a lobby leaderboard** (0.20.0: the journal's Records, #171) across sessions, not only the round's standings. | S-M |
| ☑ | **A rival angler in the default world.** (0.20.0, #169) The NPC angler only runs with the sidecar; the default world has none. | S |
| ☑ | **The off hand as item data** (0.20.0, #172) (handbook gap 5): the winding hand is rod code today, so the grip preview cannot show it. As a marker on the item plus an IK the held-item system runs, the preview shows it and bows or staffs get it for free. | M |

---

## 3. The template: what every future game gets

| | Item | Size | Notes |
|---|---|---|---|
| ☑ | **A settings menu** (0.20.0, #165) in the Esc menu: video (window or fullscreen, resolution, vsync, frame cap, quality preset), audio (master, music, effects, voice, on their own buses), controls (sensitivity, invert, key rebinding). A foundation `Settings` autoload saving to `user://settings.cfg`. | M | Starts with section 1's sensitivity and volume. |
| ☑ | **A character selector.** (0.20.0, #166) The looks exist (`ModularCharacter`, `make_looks.py`); today a player's look is picked from their entity id. Store the chosen look on the server (a column or a small table: every client dresses them the same) and add a picker to the connect screen or the lobby. Since 0.22.0 (#178) every piece can be swapped, slot by slot, per body. | M | Needed by the chicken game (pick chicken or predator). |
| ☑ | **A lobby screen** (0.21.0, #174: ready-up and teams; mode choice still to come): who is here, ready-up, mode and team choice, then into the round. Today everyone auto-joins the default session. | M | Teams for the chicken game; courses for disc golf. |
| ☑ | **Text chat** (DECISIONS #273): a chat table with a rate limit, and a chat box. | S | |
| ☑ | **Accounts** (built in 1.0: `docs/TEMPLATE_1_0.md` §6, DECISIONS #278-#281; was #202; a real SpacetimeAuth sign-in waits on the Maincloud login): log in (SpacetimeDB's OpenID Connect: its own auth, or Discord/Google) so the same person is the same identity on any machine, and a name belongs to an account. Today an identity is a token file per copy of the game, names are unique first-come. | M | Before strangers play; before progress matters across machines. |
| ☐ | **Voice chat.** SpacetimeDB is the wrong pipe for audio. Choices: WebRTC peer to peer with SpacetimeDB carrying the connection setup and an Opus add-on for Godot; Steam's voice (GodotSteam) if you ship on Steam; or a hosted service. Decide where the game ships first. | L | Research before building. |
| ☑ | **Genres as modules you switch on.** (0.21.0, #173: `shared/game.json`) Not too hard, and worth doing before game 2 so it is not a fork. Server: each genre a Rust module behind a Cargo feature, and `server/src/game/mod.rs` calls every enabled genre's hooks; genres claim their own numbers (challenge kinds, entity kinds, phases) and the module checks they do not collide at `init`. Client: each genre a folder under `game/` with its tables, entity definitions and HUD; a game "manifest" resource lists the enabled genres and boot merges them. `publish.sh --features fishing,discgolf`. | M-L | Handbook gap 2. |
| ☑ | **Levels built in the editor** (handbook gap 1). (0.21.0, #175: LevelInfo + markers, baked from the scene; the meadow) Today the lakeside is generated and the server's bake comes from the generator. A designer should place spawns, hazards, water, goals (and baskets) as nodes in a scene, and a bake step turns that into what the server reads. | L | Both next games need their own maps. |
| ☐ | **Content without hand-edited JSON** (handbook gap 3): validation at least, an editor at best. | M | |
| ☐ | **The template split** (handbook gap 4): a tagged foundation that games pull in with `git subtree`. | M | After genre modules. |
| ☐ | **A spectator camera** for players who are out or waiting. | S | Both next games. |

---

## 4. What the next two games need

### Chicken vs predators

An asymmetric team game: chickens survive or gather, predators hunt them (players, NPCs or both).

| | Needs | Template or genre | Size |
|---|---|---|---|
| ☐ | **Teams and roles**: a team on the session member, team balancing in the lobby, per-team win conditions and scoring. | template | M |
| ☐ | **Movement per kind of body.** Today every entity shares one movement config (`shared/movement_config.json`), and the server's trust envelope is built from it. Chickens and foxes need their own speeds, jumps and the flap (the config already has `flap_charges`, `flap_velocity` and `dash_impulse`). | template | M |
| ☐ | **Animal characters**: models and animation sets for a chicken and a predator rig. The animation system is not tied to the humanoid (a set needs idle, walk, run, jump start/loop/land); the held-item and body-clearance code is, and the chicken game holds no items. | content + small template | M |
| ☐ | **Catching and being caught**: a predator's grab or peck as an ability (`use_ability` with the server checking range and facing), knockback, elimination or respawn, stamina. The action component and `apply_damage` exist; there is no combat code in the sidecar yet. | genre on template | M |
| ☐ | **NPC predators or chickens** as sidecar brains (wander and chase brains exist). Needs the sidecar running: the dedicated-server preset. | genre | M |
| ☐ | **Things to carry or hide in**: eggs to carry home (inventory and interaction exist), bushes to hide in. | genre | S-M |
| ☐ | The lobby, character selector, spectator camera and levels from section 3. | template | |

### Disc golf (a disc-golf Super Battle Golf)

Everyone plays the same hole at once, throwing discs at baskets, with chaos.

| | Needs | Template or genre | Size |
|---|---|---|---|
| ☐ | **The throw: aim, charge, release.** Fishing's cast is exactly this (an aimed point, a charge, the body facing the aim, the server checking it). Lift it into a foundation aim component both games use. | template (from fishing) | M |
| ☐ | **Disc flight the server can check.** A deterministic flight model (speed, glide, turn, fade, wind) written twice, GDScript and Rust, kept bit for bit by a golden file, exactly as the fight is (`FightSim` and `genre::fight`). The server replays a throw from its inputs and decides where it landed. | genre, on the fight's pattern | L |
| ☐ | **The course where the server can see it**: ground, trees, water and out of bounds in the bake, so a replayed flight hits the same tree. The lakeside bake already has the water and the depths. | template (levels) + genre | L |
| ☐ | **Holes as rounds**: tee, play, everyone in, scores, next hole. The session's phase plans are data (`shared/rules.json`); a hole is a plan. Strokes per hole and a scorecard. | genre on template | M |
| ☐ | **Discs as gear**: putter, midrange, driver, unlocked or bought (the fishing shop's rod, reel and line pattern). | genre | S |
| ☐ | **Chaos**: players bumping each other (today entities never collide with one another, on purpose), power-ups, a camera that follows your disc and lets you watch others'. | template change + genre | M |
| ☐ | The lobby, spectator camera and editor-built levels from section 3. | template | |

---

## 5. A suggested order

Done in 0.20.0 and 0.21.0: section 1, all of section 2, and from section 3 the settings menu,
the character selector, the lobby (ready-up and teams), genres as modules and levels built in the
editor.

1. The friend test, and a round of fixes from it.
2. What is left of section 3 that both next games use: a spectator camera, a lobby that picks a
   mode or a course, text chat. Then content validation, and the template split.
3. The chicken game: teams (the lobby has them), movement per body, animals, catching. It reuses
   the most of what exists (NPC brains, abilities, rounds), and is a genre of its own
   (`shared/game.json`).
4. Disc golf: the aim component from fishing, then disc flight on the fight's twin pattern, and a
   course built in the editor with `LevelPoint`s for its tees and baskets.
5. Voice chat, once you know where the games ship.
