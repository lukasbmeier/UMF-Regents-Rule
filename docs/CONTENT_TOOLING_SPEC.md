# Content & Design Tooling — making content a designer's job

Goal: a designer adds a fish, a spot, a predator, a level, a building, a rod, an ability, or a feedback response without opening a JSON file, a GDScript file, or a Rust file, and fits and tests it against the real animations and the real moment in the game before a server is involved — inside Godot's editor, saved as Resources. The engineer's job becomes defining content *types*; the designer's job becomes filling them.

This builds on what exists: `LevelInfo` + marker nodes + "Bake For The Server", the `@tool` preview scenes (`feel_preview`, `character_preview`, `rod_grip_preview`), `animation_set_builder.gd`, settings-as-data, the fight bot, the level-probe goldens. It generalises those patterns and adds the missing layer: an editor dock, gizmos, hot tunables, balance sims, and recording.

Principle: **Godot's Inspector is the content editor. `shared/*.json` is a build artifact.** A designer edits `Resource`s; a bake step writes the JSON the server compiles in; validation happens at bake, in the editor, with a report. Nothing hand-edits JSON after this lands.

---

## 1. Content as Resources

### 1.1 `ContentDef` base
```gdscript
@abstract class_name ContentDef extends Resource
## Every content type: a stable id, a display name, and validation.
@export var id: int                       # genre claims its number space (DECISIONS #173)
@export var display_name: String
@export_multiline var designer_notes: String   # never shipped; bake strips it
@abstract func content_type() -> StringName    # &"fish", &"spot", &"ability", &"npc", &"item", &"feedback"
func validate() -> Array[String]           # empty = valid; each string is a human sentence
func to_bake() -> Dictionary               # exactly what the server compiles in
```
Concrete types per genre under `game/<genre>/content/*.gd`, instances under `game/<genre>/content/<type>/*.tres`. Foundation types under `foundation/content/`: `ItemDef`, `AbilityDef`, `NpcDef`, `FeedbackSet`, `RulesDef`.

Rules for a `ContentDef` subclass:
- Every numeric export has `@export_range` with the real design bounds; every categorical field is an `enum`; every reference to other content is a typed `ContentDef` export, never a bare id (the bake resolves ids and fails on dangling references).
- Tooltips are documentation: the `##` comment above each export is what the Inspector shows.
- `validate()` checks what the type system cannot: a spot's depth vs the level's water, a fish whose weight range exceeds any line's rating, an ability whose wind-up is under the RTT floor.

### 1.2 Bake
`tools/bake_content.gd` (headless + dock button): walks every `ContentDef` under `game/*/content/` and `foundation/content/`, runs `validate()`, writes `shared/<genre>/<type>.json` (sorted, stable formatting so diffs are readable) and a `shared/content_manifest.json` (type → count → hash). `server/build.rs` already consumes `shared/*.json`; extend its schema checks to read the manifest and fail the build on a missing or stale bake (hash mismatch = "you edited a .tres and did not bake").

Client reads the same JSON it does today (no client change), or — better, once stable — reads the `.tres` directly and the JSON exists only for the server.

### 1.3 Migration of existing content
`shared/fishing/fishing.json`, `fight.json`, `shared/rules.json` → generated `.tres` by a one-off script, then deleted as sources. The round-trip test: bake the generated resources and assert byte-identical JSON to what is committed today.

---

## 2. The Content Dock (`addons/umf_content/`, an `EditorPlugin`)

One bottom-dock panel, three columns:

| Left: types | Middle: items | Right: item |
|---|---|---|
| every `content_type()` with count and a red badge for validation errors | the `.tres` list for the selected type, searchable, "New" button that creates a correctly-typed resource in the right folder with the next free id | the Inspector for the selected item plus a **Preview** button |

Toolbar: **Validate** (runs every `validate()`, lists sentences, click jumps to the item) · **Bake** · **Publish** (`tools/publish.sh --codegen`, output streamed into the panel) · **Play** (launches N instances, from Settings) · **Open Rules** (§4 panel).

The dock is a dev tool and lives under `addons/`; it is excluded from both exports.

---

## 3. Workbenches and the Catalog

The rod grip scene and the world builder are the pattern: a `@tool` scene where a person **adds, fits, tests and saves** one kind of content against the real animations, the real level, the real moment in the game — without a server. That is a *workbench*, and the rule is: **no content type without a workbench.** A preview that only shows the thing is not enough; the workbench is where the resource gets made.

### 3.1 The `Workbench` contract
```gdscript
@abstract class_name Workbench extends Node3D       # tools/workbench/workbench.gd
## One per content type. Lives under tools/workbench/<type>_workbench.tscn; excluded from exports.
@abstract func content_type() -> StringName
@abstract func item_list() -> Array[ContentDef]      # what exists (scans game/*/content/<type>/)
@abstract func load_item(def: ContentDef) -> void    # show it, with its model/animations/level
@abstract func new_item_from(path: String) -> ContentDef   # drop a .glb/.png/.wav → a typed resource with the next free id
@abstract func test_actions() -> Array[StringName]   # the moments this content lives in, e.g. &"catch_reveal", &"idle_grip", &"cast_grip", &"placement"
@abstract func run_test(action: StringName) -> void  # plays that moment with the loaded item
func fit_gizmo() -> Node3D                           # the thing you move/rotate; the base class saves its transform into the def
func validate_badge() -> Array[String]               # def.validate() + fit checks (e.g. reel 2 cm clear of the thigh across the whole clip)
func save() -> void                                  # ResourceSaver on the def; the base class refreshes the Catalog thumbnail
func capture_thumbnail() -> Image                    # the Catalog's picture of this item
```
The Content Dock (§2) lists every registered workbench; `Workbench` subclasses register through a `WorkbenchRegistry` resource. A test asserts every `ContentDef` subclass resolves a workbench — a content type without one fails the suite.

### 3.2 The workbenches this game needs (and what each already has)
| Workbench | Adds | Fits | Tests | Exists today |
|---|---|---|---|---|
| **Held item** (rod, disc, weapon) | drop a GLB → `HeldItemDef` | grip transform per animation group (carry / use), off-hand marker | plays idle/walk/run/cast/heave with the item; thigh-clearance badge | `rod_grip_preview.tscn`, `fit_grip.gd` — generalise, rename |
| **Character look** | drop a rigged GLB → look entry | scale, yaw, foot height | cycles every clip in the set; prints head/pelvis/foot heights | `character_preview.tscn` — add New-from-GLB and Save |
| **Fish / catch** | drop a GLB → `FishDef` with `model`, `size_range`, `rarity`, `spots` | reveal pose, pivot, scale at min/median/max size (three silhouettes) | **catch reveal**: the leap, hold, sound and HUD card exactly as in game; "show on every spot that holds it" | nothing — this is where "where does the caught-fish model come from" is answered |
| **Spot** | place on the level → `SpotDef` | radius, depth check against water, cast-reach rings per rod tier | "what bites here" table from the content; depletion/regrowth curve plot | `LevelSpot` marker — add the panel |
| **Building / kit piece** | drop a GLB → prop prefab (`PackedScene`) with collision and a `KitPieceDef` | snap points, footprint, collision shape auto-fit, LOD check | place it on the lakeside at the cursor with snapping; walk a mannequin through the door | `tools/world/` generator — invert it: the generator becomes a palette |
| **Level** | new `LevelInfo` scene from a template | markers, bake bounds, water | bake; server-view overlay (§3.4); walk a mannequin; probe points | `LevelInfo` + Bake button — add overlay and walk-test |
| **NPC / brain** | pick a model + `NpcDef` (brain kind, radii, speed profile) | sight cone, chase radius, touch range gizmos | sandbox: spawns the NPC in the greybox with a scripted dummy player; watch it think; step the brain tick by tick | `sidecar/npc/` brains — the sandbox is new |
| **Ability / action** | `AbilityDef` | range arc, wind-up timeline against RTT floor | play on a mannequin: wind-up, hit frame, feedback | nothing |
| **Feedback** | `FeedbackSet` entry | timings, shake amplitude, colours against the palette | fire the event on loop; A/B two responses | nothing (§7) |
| **Audio** | drop a WAV / synth params → `SoundDef` | gain, pitch variance, bus | play with variance ×10; hear it under the music | `synth_fishing_sfx.gd` — wrap |
| **Round / rules** | `RulesDef` | phase durations on a timeline | scrub the round; see the lobby→play→results→shop bar | nothing |

New genres add rows (predator, egg, pickup for chicken; disc, basket, hole for disc golf) by subclassing `Workbench`; the base class does the list/load/save/thumbnail plumbing so a new workbench is mostly `test_actions()`.

### 3.3 The Catalog (`tools/workbench/catalog.tscn`)
The visual collection: a grid of every item of every type — thumbnail, name, type, validation badge (green / amber / red with the first sentence). Filter by type and by badge. Click → opens that item in its workbench. A **Regenerate thumbnails** button runs `capture_thumbnail()` across the board (the render-test infrastructure already does this for grips). The Catalog is what a designer opens first; the dock's "types" column is the same data as a list.

### 3.4 Asset intake and "see what the server sees"
- **Intake** is `new_item_from(path)`: the workbench detects what was dropped — a rigged GLB (which skeleton family? → `AnimationSet` via the builder, or a look), a static GLB (→ prop / fish / held item), a texture, a WAV — makes the typed resource, and **appends an attribution entry** (`ATTRIBUTION.md` under the content folder: file, source, licence; the review's D1 gap closes by construction). Intake refuses a licence-less import unless the designer fills the field.
- **Level gizmos** (`EditorNode3DGizmoPlugin`): spot radius, spawn facing, hazard volume, cast-reach rings per rod tier read from the baked gear content — so "this spot is out of the starting rod's reach" is visible *in the editor*.
- **Server-view overlay**: a `@tool` child of `LevelInfo` that draws the last bake — walkable mask, depth stops, grid, probe points — and says when the bake is stale.

## 4. Hot vs baked tunables

Split every number in the project into two classes:

| Class | Examples | Where it lives | Changes take effect |
|---|---|---|---|
| **Baked** (in a parity model or a golden) | movement config, fight constants, challenge validators, level bake | `shared/*.json` via bake; compiled into the module | republish; golden vectors regenerated |
| **Hot** (feel and balance) | round durations, shop prices, bite rates, depletion/regrowth, feedback timings, NPC radii, interaction range | a `rules` table seeded from `RulesDef` at `init`; read by reducers at call time | immediately, via admin reducer `set_rule(key, value)` |

Client side: `Rules` autoload already exists (`foundation/core/rules.gd`); subscribe it to the `rules` table so the client follows live changes too.

**Tweak panel** (F3's sibling, admin identity only): lists hot rules with sliders bound to the real ranges, writes through `set_rule`, with "Save to RulesDef" so a good tuning session becomes the new seed. Marked clearly as *live on this server*.

Guard: a hot rule that ends up inside a parity model is a bug — the golden harness is the tripwire, and `RulesDef.validate()` refuses keys that the baked side declares.

---

## 5. Balance simulation (`tools/balance/`)

Promote the fight bot into a designer instrument:
- `balance_fights.gd` (headless): runs N fights per (catch × rod × reel × line × hookset) cell through `FightSim`, outputs CSV + a one-page HTML report (bar charts: land rate, mean fight length, line snaps, deadlift rate) under `build/balance/`.
- Thresholds in `RulesDef` (`target_land_rate_min/max` per rarity) make the report red/green, and `tests/balance_test.sh` fails when a cell is out of band — tuning regressions become test failures.
- Each genre with a core minigame ships its own `balance_<minigame>.gd` against its pure model. The chicken game's is "survive N seconds vs predator mix".

---

## 6. Recording, replay, heatmaps

- `SessionRecorder` (foundation, debug): writes every `InputFrame` sent and every `RowEvent` received, with timestamps, to `user://recordings/<session>.umfrec` (a compact binary; the wire types already serialise).
- `tools/replay.tscn`: scrubs a recording — shows the local predicted path vs the authoritative path, corrections, and reconciliation errors on a timeline. The netcode debugging tool we never had.
- Heatmaps: `tools/heatmap.gd` folds recordings onto the level bake grid (positions, casts, catches, deaths, disconnects) and renders a PNG overlay the "see what the server sees" node can show. Where players actually stand decides where the next spot goes.

---

## 7. Feedback as data (ANIMATION_SPEC §7, finally)

`FeedbackSet extends ContentDef`: `Dictionary[StringName, FeedbackResponse]` mapping SignalBus event names to responses (`vfx_scene`, `sfx`, `camera_shake`, `screen_tint`, `hit_stop_frames`, `ui_cue`). `FeedbackComponent` reads it; `fishing_feedback.gd` shrinks to the genre-specific responses that cannot be expressed as data, and shrinks further each time a response type is added. Colour choices in a `Palette` resource with a colourblind-safe default.

---

## 8. Admin panel

In-client, visible only to an identity with `authority.role == admin`: force phase, kick, teleport self (this is where `teleport` lives once gated), set rule, wipe a player's progress, create a world, switch its level, flip sim authority, register a sidecar. Everything `spacetime call` can do today, as buttons with confirmation. Live ops without a terminal.

---

## 9. Order of work

| Step | What | Unblocks |
|---|---|---|
| 1 | `ContentDef` base + migrate fishing content to `.tres` + bake + manifest check in `build.rs` | every later step; kills hand-edited JSON |
| 2 | Content Dock with Validate/Bake/Publish/Play | the designer loop |
| 3 | `rules` table + `set_rule` + tweak panel | tuning without republish |
| 4 | `Workbench` base + Catalog; retrofit held-item/character/level; build Fish and Spot workbenches first (the two fishing lacks) | content authored and tested in the editor, no server |
| 5 | Building/kit, NPC sandbox, Ability, Feedback, Audio, Rules workbenches | every content type has one; the suite enforces it |
| 5b | `FeedbackSet` + `FeedbackComponent` | visual clarity as data |
| 6 | Balance sims + `balance_test.sh` | tuning as tests |
| 7 | Recording/replay/heatmaps | evidence-based design |
| 8 | Admin panel | live ops |

Each step has a definition of done in the form "a designer did X without opening a code file", recorded in `DECISIONS.md` with the name of the thing they made. The first is: *a new fish species — model dropped into the Fish workbench, sized at min/median/max, its catch reveal watched and its sound heard, assigned to a spot, saved — added by a person who opened no code file and pressed Bake.* The second: *a new rod model fitted to every carry and fishing animation in the Held-item workbench, green on the clearance badge, saved.*
