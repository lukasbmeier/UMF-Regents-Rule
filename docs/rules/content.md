# Content: resources, baked, in a dock (DECISIONS #199, #200)
`docs/CONTENT_TOOLING_SPEC.md` is the plan; this is what is built (its §9 steps 1 and 2) and the
commitments that let the later steps (hot rules, workbenches, the Catalog, every game's content)
add to it without reworking it.

## The design commitments (read before changing anything here)
1. **One library answers every question about content** (`ContentLibrary`): the types, the owners
   and their folders, the pieces, the next free id, a piece by id. The bake, the dock, and later the
   workbenches, the Catalog and the running game ask it; nothing keeps its own idea of where
   content is. It works in the editor, headless and in an export (`ResourceLoader.list_directory`).
2. **Types are discovered, never registered.** Every non-abstract `ContentDef` subclass in Godot's
   class list is a type. A new type appears in the dock, the bake and the library with no other edit.
3. **Where a type's script lives says who owns it.** `foundation/content/*_def.gd`: any owner may
   make pieces (the foundation, or a genre adding its own abilities). `game/<genre>/content/*_def.gd`:
   that genre alone.
4. **One layout:** `<root>/<content_type>/<name>.tres`, roots `foundation/content/` and
   `game/<genre>/content/`. One type per folder, nothing but content in it (a stray file is an
   error, never skipped).
5. **Ids are unique per type across the whole game**, checked by the bake and again by build.rs.
   A new piece takes the next free id at or above its owner's base (0 for the foundation, the
   genre's `GenreModule.content_id_base`), so two genres in one game never collide. Ids are what
   rows and saves refer to: never renumber a piece that has shipped.
6. **Every content script is `@tool`** (the editor runs `validate()`, `to_bake()`); the suite checks.
7. **Links between content are typed exports**, baked with `ContentDef.ref()` as the id. The bake
   refuses a link to a piece made inside another (no file, no id) or to a file outside the
   content folders. This is generic: a new type gets it for free.
8. **The baked layout has a `format`** (1). build.rs refuses another, so a change of layout is
   caught, never misread; change both sides together.
9. **`ContentDef` grows only by methods with a default** (`workbench_scene()` returns "", `ref()`,
   `validate_with()` for checks against every other piece of the type),
   so adding a hook never breaks a type written before it. Planned next: a thumbnail for the
   Catalog, a singleton flag for the rules.
10. **The dock is a thin view.** Its behaviour is `ContentDockModel` (tested headless); its toolbar
   is a list (`model.add_action`) a later step appends to; everything that needs the editor goes
   through `ContentDockBridge` (the plugin's subclass calls `EditorInterface`); long jobs run as a
   `ProjectTask` (a repo script through Git Bash, its output streamed, the editor never frozen).

## The rules
- **The JSON is a build artifact.** `tools/bake_content.gd` writes `shared/content/<owner>/<type>.json`
  and `shared/content/manifest.json` (a hash of every baked file and every `.tres` it came from).
  Never edit them by hand.
- **The server refuses a stale bake.** `server/build/content.rs` stops the build when a `.tres` changed
  or was added without a bake, or a baked file was edited, and names the file. `tools/publish.sh`
  and the dock's Publish bake first; `cargo test`, CI and a bare `spacetime build` meet the check.
- **A type is honest about its numbers.** Every number has `@export_range` with the real design
  bounds; every category is an enum; the `##` comment above an export is the Inspector's tooltip,
  so it is the documentation. `validate()` says what the types cannot, one sentence each.
- **Renaming an export loses its values** in every `.tres` (Godot drops a property it no longer has
  on the next save). Keep the old name, or move the values with a one-off script, in the same change.
- **`to_bake()` is exactly what the server compiles in**: plain values, no designer notes.
- **Shipped clients carry the `.tres`** (the client may read content directly through the library),
  designer notes included: keep notes fit to be read.

## The Content Dock (`addons/umf_content/`, editor only)
The bottom panel "Content". Left: every type, its count, a red mark with the number of problems.
Middle: the type's pieces (search by name, id or file), and New (owner, name: it makes the `.tres`
in the right folder with the next free id and opens it). Right: the chosen piece (it opens in the
Inspector, which is the content editor), its problems, Open workbench (when the type has one), Show
in FileSystem. Toolbar: Validate (every check the bake makes; a problem's file is a link), Bake,
Publish (`tools/publish.sh` streamed into the log), Play. Excluded from both exports.

## The types so far
| Type | Class | Folder | The server |
|---|---|---|---|
| ability | `AbilityDef` | `foundation/content/ability/` (melee), `game/<genre>/content/ability/` | `content::ABILITIES`, seeded into `ability_def` at init |
| rules | `RuleSetDef` (`RuleEntry`, `RuleOverride`) | `foundation/content/rules/`, `game/<genre>/content/rules/` | `hot::ALL` and `hot::<owner>::<NAME>`, served live in `hot_rule` |
| character | `EntityDefinition` | `foundation/content/character/` (player: a plain capsule, npc, humanoid), `game/<genre>/content/character/` | its kind, movement profile and abilities: each kind's Tier A speed bound (`content::movement_limits`) and what it may use (`content::kind_may_use`) |
| movement | `MovementProfileDef` | `foundation/content/movement/`, `game/<genre>/content/movement/` | its run, sprint, dash and lift, for the kinds whose characters use it |
| status | `StatusDef` | `foundation/content/status/` (normal, injured, downed, carried, out, hidden, escaped), `game/<genre>/content/status/` | `status::STATUSES`: its number, length, what it becomes, its movement and what it allows (a genre's replacing the foundation's of the same number) |
| hold | `HoldDef` | `foundation/content/hold/` (help up), `game/<genre>/content/hold/` | `hold::HOLDS`: which press starts it, how long with how many, what stops it, the status it leaves the target in (a genre's before the foundation's) |

## Hot rules (DECISIONS #201, CONTENT_TOOLING_SPEC §4)
A number the game is tuned by while it runs: a range, a health, a round's length, a price.
- **Declared in a rule set** (`RuleSetDef`): name, kind (number, whole number, flag, text), value,
  bounds, unit, and a description (what the tuner reads). Its key is `<owner>.<name>`, unique in the
  game. A rule set's `overrides` set THIS GAME's value for another owner's rule: a genre tuning the
  foundation's interact range for its game, never by editing the foundation's file. One override per
  key per game, within bounds.
- **Served live.** Every rule has a row in the public `hot_rule` table (subscribed by the foundation
  for every client and sidecar, `InterestManager.ALWAYS_TABLES`). The server keeps it current on
  init and every connect: a rule nobody set follows the build's default (so a republish with a new
  default needs no wipe), one an admin set keeps its value, one the build no longer has is removed.
- **Read live.** Server: `hot_number(ctx, crate::hot::foundation::INTERACT_RANGE_M)` (a generated
  constant: a misspelt rule does not build). Client: `HotRules.number(&"foundation.interact_range_m")`,
  and `HotRules.changed` when it moves; offline, the build's default.
- **Tuned live by the admin.** `set_rule` / `reset_rule` (admin only, within bounds). In game: Escape,
  **Rules (admin)** (shown only to the admin, `Roles`). In the editor: the Content dock's **Keep live
  tuning** writes what the admin set into the rule sets (a genre's own rule takes the value; a
  foundation rule becomes the genre's override; the template's own values with no genre); then Publish.
- **Never for what a client predicts exactly** (movement): the bake refuses a rule named like a
  `shared/movement_config.json` field. A hot rule that a client simulates with is fine ONLY because the
  client reads it live too; that is what lets it be retuned without a `compat` bump.
- **The table never changes shape** (old builds read it). Moving a number from `shared/rules.json`
  into a rule set: build.rs refuses a `rules.json` that still has it, naming where it went, so a
  game's own value is never silently dropped.
- Moved so far: `foundation.interact_range_m`, `foundation.new_player_health`. Round lengths are still
  in `shared/rules.json` (a session plan is structure: which phases, in what order); making each
  phase's length a hot rule is the next candidate.

## Adding a content type
1. `foundation/content/<type>_def.gd` (any owner may make them) or `game/<genre>/content/<type>_def.gd`
   (the genre's alone): `@tool`, `class_name XDef extends ContentDef`, its exports (ranges, enums,
   typed links), `content_type()`, `to_bake()` (links through `ContentDef.ref()`), and `validate()`
   calling `super()`.
2. It is in the dock at once: New makes the first piece. Edit it in the Inspector.
3. Compile it in: a branch in `server/build/content.rs` for a foundation type, or the genre's build
   step (`server/build/<genre>.rs`) reading `shared/content/<genre>/<type>.json`.
4. Tests: the `content` suite already checks every piece is valid and the bake current; add a
   `validate()` case for the type's own rule.

## Workbenches and the Catalog (DECISIONS #203, CONTENT_TOOLING_SPEC §3)
A workbench is where a piece of content is made and tested: a `@tool` scene with the real
character, the real animations and the moment the content lives in, and no server.
- **No content type without one.** The `workbench` suite fails a type with no bench unless it says
  why in `why_no_workbench()` (rules: tried live in the game's Rules page instead).
- **Found by name:** `tools/workbench/<type>_workbench.tscn` (a foundation type), or
  `game/<genre>/workbench/<type>_workbench.tscn` (a genre's). Both stay out of the builds (the export
  test checks). `ContentDef.workbench_scene()` finds it; override only to point elsewhere.
- **Writing one:** extend `Workbench` (`tools/workbench/workbench.gd`): `content_type()`,
  `load_item()` (show the piece), `test_actions()` and `run_test()` (play the moment, return a
  sentence). Optional: `test_label()`/`test_info()` (the button's words), `controls()` +
  `set_control()` (its settings), `bench_actions()` + `do_action()` (its own buttons; return
  `{"open": piece}` to open another piece on its bench, `{"edit": res}`, `{"play": args}`),
  `play_args()` (Play as this), `tries_on_character()` + `default_character()` (the "Tried on"
  choice), `fit_checks()` (amber warnings), `fill_from_file()` (New From File: the base makes the
  piece in its folder with the next free id, the bench fills it), a `ThumbnailCamera`. The base gives
  the common actions (Save, New from this, Copy into a genre, Capture thumbnail), follows edits to
  the piece (it watches the piece's saved fields: a script's fields announce nothing), takes the
  piece the dock hands it (`Workbench.pending`), and renders thumbnails. A character goes in with
  `Mannequin`: an `EntityDefinition`'s model and its AnimationSet, played as the game plays it, and
  any clip previewed (`preview`, speed, pause, scrub).
- **WORKBENCHES 2 (DECISIONS #207): the piece in the Inspector, the bench in the Workbench panel**
  (`addons/umf_content/workbench_panel.gd`, docked beside the Inspector), which draws what the bench
  declares: no bench needs panel code. **A bench keeps nothing in its scene** (`_validate_property`
  strips storage from every bench variable; the `Mannequin`'s too): opening one never dirties the
  template's files in a game. **In a game, the template's content is read-only**: the dock makes a
  genre's pieces only (`owners_for`), a bench offers Copy into a genre (`ContentLibrary.create_copy`,
  `ContentDef.on_copied(owner, replacing)`: a status keeps its number when replacing, takes a free
  one beside), and saving a template piece is warned about.
- **A bench's judgement is the game's.** The ability bench's outcomes are `use_ability`'s Tier A
  rules (`AbilityWorkbench.judge`); a bench that predicted something the server would not do would
  teach the designer the wrong game. When the server's rule changes, the bench's does in the same change.
- **Scripts a bench calls run in the EDITOR**: a resource script it uses must be `@tool` (an
  `AnimationSet` was not, and the editor could not call it; found by opening the bench in a real editor).
- **The Catalog** (the Content dock's second tab): every piece as a card, its picture and a badge:
  red (something is wrong: the first sentence), amber (valid, not yet seen in its bench: no
  picture), green. Filter by type and badge; a click opens the piece and its bench. Pictures are a
  cache under `tools/workbench/thumbnails/` (not imported, not committed): **Regenerate** renders
  every piece in its own bench off screen (needs a renderer; `tests/render_test.sh` proves it).

| Workbench | Tests | Where |
|---|---|---|
| ability | use in range (the wind-up plays, it lands), use out of range (refused), cooldown | `tools/workbench/ability_workbench.tscn` |
| character | every clip (and which the game needs are missing), walk facing (read from a walk that travels; else the floor arrow), looks; fit: feet on the floor, its body (`collision_*`, drawn around it) against the model; any clip previewed (speed, pause, scrub); each needed clip chosen; Animation set from the model (`ClipMatcher`); New movement / New ability for it; Play as this; New From File (a rigged model: its own set and fitted body when it has clips) | `tools/workbench/character_workbench.tscn` |
| movement | Start and stop (time to run and sprint speed, slide to a stop), Jump (height, air time), Flaps (each flap's height), Turn around; PERFORMED by the character it is tried on (the one that moves by it), with a ruler, the moments labelled, its speed shown. Measured by the real model: its numbers match the movement playtest's. Play as this (`--movement=`) | `tools/workbench/movement_workbench.tscn` |
| status | moves (run and sprint in it against the character's own, can it jump), burst (its speed, then after), pose (on the character, or amber: no clip for it), timeline (its length and what it becomes, to the end); measured by the real model with the status applied | `tools/workbench/status_workbench.tscn` |

### Statuses (DECISIONS #206, docs/FOUNDATION_SYSTEMS.md milestone 2)
A status is a `StatusDef`: its NUMBER (the foundation's 0-99: normal 0, injured 1, downed 2,
carried 3, out 4, hidden 5, escaped 6; a genre's 100-255), how long it lasts on its own and what it
becomes then (`then_status`), how an entity in it moves (a share of the character's speed, a burst
at its start, no sprint, no jump, no dash), what it may do (`can_act`: use things and abilities;
`targetable`: be used or aimed at) and how it shows (spectate, hide the body, a pose clip, a tag in
its colour). A GENRE REPLACES one of the foundation's by giving its own the same number: the game
uses the genre's, nobody edits the foundation's file (both the bake and the build refuse two genres
with one number, or a genre's under 100 that replaces nothing).

The server keeps who is in which: `status_state` (a side table; no row is normal), set by
`set_status` (an authority; a player on themself while the dev tools are on) or a genre's
`set_status_internal`, moved on by a timer (`status_expiry`) when its time is up: to what a genre's
`on_status_expired` says, else its `then`. Every genre hears each change (`on_status_changed`).
`use_ability` and `interact` hold to `can_act` and `targetable`; the Tier A bound applies the status
(`status::bound`), with a grace after a change (`foundation.status_grace_ms`) so the player's own
game, a round trip behind, is not pulled back. A new match puts everyone back to normal
(`foundation.statuses_reset_each_match`).

### Holds (DECISIONS #209, docs/FOUNDATION_SYSTEMS.md milestone 3)
A hold is a `HoldDef`: something done by HOLDING the interact key on it until it is finished
(helping a downed teammate up, laying an egg, opening a gate). Which press starts it: a `verb` (0,
the interact key) on a character of `done_to`'s kinds, by one of `done_by`'s (none: anyone), while
the target is `only_when` (none: any status). How long: `seconds_with` (alone, two together, three...,
the last for more), every hold scaled live by the game's pace, `foundation.hold_speed`. What stops a doer: moving `stopped_by_moving_m` from where they began, being hurt
(`stopped_by_damage`), leaving its reach (`range_m`, else `foundation.interact_range_m`, plus
`foundation.hold_leave_slack_m`), a status that cannot act, leaving the game. When everyone lets go
its progress is lost, or kept (`keeps_progress`: a half-laid nest). Done, the target is put in
`then_status` (help up: normal). A press two holds could start is refused (the bake and the build);
a genre's hold over the foundation's REPLACES it for the presses they share. It has no bench (a few
numbers and links): the Content panel's line for it says how long it takes with each count.

The server: `hold_progress` (one per thing being held: how far along it was at `at` and how fast it
goes, written only when that changes, so every client draws the bar moving) and `hold_member` (one
per doer); `begin_interact` / `end_interact` for a player, `begin_interact_as` / `end_interact_as` for
an authority's NPC or bot; a 10 Hz tick (`tick_holds`) only while something is held. A genre adds
through hooks: `may_hold` (refuse), `hold_rate` (another rate, negative to undo: a nest cooling),
`on_hold_completed`, `on_hold_left` (why: `hold::left`). On the client every entity has a
`HoldComponent` (the bar's numbers, the doer's pose), the interact key is held where a hold applies
(`InteractionComponent.hold_for`), and the HUD's `HoldPrompt` says "Hold E: Help up" and draws the bar.

### Timed presses (DECISIONS #210, docs/FOUNDATION_SYSTEMS.md milestone 4)
A skill check where a marker sweeps across a bar and the player presses (the interact key) while it
is in the target, three times. Challenge kind 1 (`challenge::KIND_TIMED_PRESS`); what the foundation's
`interact` on a resource node and a genre's `issue_challenge_for` now issue. The sweep is frozen on
its `timed_press` row when it is issued, from the rules: `foundation.press_lead_in_ms` before it
moves, a sweep across and back in `press_sweep_easy_s` at difficulty 0 to `press_sweep_hard_s` at 1,
the target's width from the difficulty (`challenge::timing_half_width`, the timing bar's). The server
judges each press at its arrival less a credit, half the player's quickest round trip as it measured
it (`client_rtt`), at most `foundation.press_credit_cap_ms` (0: judged on arrival). The old timing bar
(kind 0, judged from where the client said it stopped) is still accepted from old builds; nothing
issues it.

On the client every entity has a `StatusComponent` (added when its scene has none): its movement
component steps in the status (the config and the presses it takes away: the same in prediction and
on the sidecar), its body hides for it (`SpaceTimeEntity.set_hidden_by`, which a disconnect uses
too), its pose is held, its tag shows; the local player in a `spectate` status watches a teammate
(the lobby's team; Jump for the next). The movement numbers are PARITY numbers like a profile's.

### Movement profiles (DECISIONS #205, docs/FOUNDATION_SYSTEMS.md milestone 1)
A character links to a `MovementProfileDef` (`EntityDefinition.movement_profile`): every
per-character movement number (speeds, acceleration, jump, flaps, dash). New fills it from the
default (`shared/movement_config.json`), which every character without a profile still moves by,
and which keeps the network's numbers (tick rates, reconciliation). The entity applies its
character's profile to its movement component before binding, so its player's prediction and the
sidecar's simulation use the same numbers. The module bounds a Tier A claim by its entity's KIND:
the widest of that kind's characters' profiles. Profile numbers are PARITY numbers (clients predict
with them), so they are not hot rules: change one in a shipped build and bump `compat`, or add a
profile. `--character=<res path>` plays as any character for a run (Boot): how a designer tries one.

### Character definitions are content (DECISIONS #204)
`EntityDefinition` is a `ContentDef` (type `character`): listed, benched, Catalogued. Its content
`id` is NOT its `kind`: kinds may repeat on purpose (the bare foundation's capsule player and the
humanoid player are both kind 0; a scene's Boot picks one, a genre's replaces the foundation's).
A definition outside a content folder still works everywhere; it is just not listed: a genre moves
its own (`game/<genre>/content/character/`) when it is ready.

## Not yet (CONTENT_TOOLING_SPEC §9)
Step 5's rest: levels stay scenes (the level scene is its own bench: its Bake button) and gain a
"what the server sees" overlay and a walk test; the NPC sandbox; look PIECES as content (players'
choices are stored by position today, so it is a migration to stable ids, its own step); Fishing's fish, spot and
held-item (rod) benches, in Fishing, with its content. Round lengths as hot rules. Fishing's
content (`shared/fishing/*.json`) moves to `.tres` in Fishing, where its round-trip test (bake the
generated resources, compare byte for byte) belongs.
