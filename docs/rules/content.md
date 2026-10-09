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

## Not yet (CONTENT_TOOLING_SPEC §9)
The `Workbench` base and the Catalog (step 4); round lengths as hot rules. Fishing's
content (`shared/fishing/*.json`) moves to `.tres` in Fishing, where its round-trip test (bake the
generated resources, compare byte for byte) belongs.
