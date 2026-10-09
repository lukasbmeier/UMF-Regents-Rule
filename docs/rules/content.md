# Content: resources, baked (DECISIONS #199)
`docs/CONTENT_TOOLING_SPEC.md` is the plan; this is what is built (its §9 step 1).

## The rules
- **Content is a `.tres`, edited in the Inspector.** Each content type is a `ContentDef` subclass
  (`foundation/content/content_def.gd`); its instances live under `foundation/content/<type>/` or
  `game/<genre>/content/<type>/`. A content folder holds nothing else: the bake refuses a stray
  resource rather than skipping it.
- **The JSON is a build artifact.** `tools/bake_content.gd` writes `shared/content/<owner>/<type>.json`
  and `shared/content/manifest.json` (a hash of every baked file and of every `.tres` it came from).
  Never edit them by hand.
- **The server refuses a stale bake.** `server/build/content.rs` (run by build.rs) stops the build
  when a `.tres` changed or was added without a bake, or a baked file was edited, and names the
  file. `tools/publish.sh` bakes first, so a person who publishes never meets it; `cargo test`,
  CI and a bare `spacetime build` do.
- **A type is honest about its numbers.** Every number has `@export_range` with the real design
  bounds; every category is an enum; a link to other content is a typed export, never a bare id;
  the `##` comment above an export is the Inspector's tooltip, so it is the documentation.
  `validate()` says what the types cannot ("its wind-up is under the 100 ms a round trip needs"),
  one sentence each, and the bake refuses content with any.
- **`to_bake()` is exactly what the server compiles in**: plain values, no designer notes. Ids are
  unique within a type (the bake checks; build.rs checks again across the foundation and genres).

## The types so far
| Type | Class | Folder | The server |
|---|---|---|---|
| ability | `AbilityDef` | `foundation/content/abilities/` (melee), `game/<genre>/content/` | `content::ABILITIES`, seeded into `ability_def` at init |

## Adding a content type
1. `foundation/content/<type>_def.gd` (or `game/<genre>/content/<type>_def.gd`): `class_name XDef
   extends ContentDef`, its exports, `content_type()`, `to_bake()`, and `validate()` (call `super()`).
2. Make one in the editor (FileSystem → New Resource → XDef), save it under the type's folder.
3. Bake (`tools\publish.cmd` does, or `godot --headless --path . -s res://tools/bake_content.gd`).
4. Compile it in: a branch in `server/build/content.rs` for the foundation's types, or a genre's
   build step (`server/build/<genre>.rs`) reading `shared/content/<genre>/<type>.json`.
5. Tests: the `content` unit suite checks every bake is current and valid; add a `validate()`
   case for the new type's rule. `tests/content_test.sh` proves the build refuses a stale bake.

## Not yet (CONTENT_TOOLING_SPEC §9)
The Content Dock (step 2: Validate, Bake, Publish, Play buttons), the `rules` table and hot
tunables (step 3), the `Workbench` base and the Catalog (step 4). Fishing's content
(`shared/fishing/*.json`) moves to `.tres` in Fishing, where its round-trip test (bake the
generated resources, compare byte for byte) belongs.
