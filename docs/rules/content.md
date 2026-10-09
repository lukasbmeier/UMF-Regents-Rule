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
9. **`ContentDef` grows only by methods with a default** (`workbench_scene()` returns "", `ref()`),
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
The `rules` table and hot tunables (step 3), the `Workbench` base and the Catalog (step 4). Fishing's
content (`shared/fishing/*.json`) moves to `.tres` in Fishing, where its round-trip test (bake the
generated resources, compare byte for byte) belongs.
