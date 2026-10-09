@tool
@abstract
class_name ContentDef extends Resource
## ONE PIECE OF CONTENT, edited in the Inspector (docs/CONTENT_TOOLING_SPEC.md §1, DECISIONS #199):
## an ability, an item, a fish. Godot's Inspector is the content editor; the JSON the server
## compiles in (`shared/content/<owner>/<type>.json`) is a build artifact, written by the bake
## (`tools/bake_content.gd`) and never edited by hand. `server/build.rs` refuses to build while a
## `.tres` has been changed or added without baking.
##
## A content type is a subclass: `@export`s with `@export_range` on every number (the real design
## bounds), an enum for every category, a typed reference for every link to other content (never a
## bare id). Its instances live under `foundation/content/<type>/` or `game/<genre>/content/<type>/`.
## The `##` comment above each export is what the Inspector shows: it is the documentation.
##
## EVERY CONTENT SCRIPT IS `@tool`: the editor (the Content Dock, a workbench) calls `validate()`
## and `to_bake()`, which a script that is not a tool cannot run there. The `content` suite checks.
## The library (`ContentLibrary`) says where content lives and finds types by themselves.
##
## GROWING THIS CLASS: only by methods with a default (like `workbench_scene()`), so a new one
## never breaks a type written before it. A link to other content is a typed export (`@export var
## bait: BaitDef`); `to_bake()` writes it with `ref()`, and the bake refuses a link to anything that
## is not baked content.

## Unique within its type across the whole game (the bake checks). The dock gives a new piece the
## next free one at or above its owner's base (`GenreModule.content_id_base`).
@export var id: int = 0
## What a player sees it called.
@export var display_name: String = ""
## For the people making the game. Never baked, never shipped to the server.
@export_multiline var designer_notes: String = ""


## The type's name: the baked file is `<type>.json`. `&"ability"`, `&"item"`, `&"fish"`.
@abstract func content_type() -> StringName


## What the server compiles in, exactly: plain JSON values, no designer notes.
@abstract func to_bake() -> Dictionary


## The workbench scene this piece is made and tested in (CONTENT_TOOLING_SPEC §3), or "" for none
## yet. The Content Dock opens it. Override in a type that has one.
func workbench_scene() -> String:
	return ""


## A link to other content, as the bake writes it: its id, or -1 for none.
static func ref(def: ContentDef) -> int:
	return def.id if def != null else -1


## What is wrong with it next to every other piece of its type (keys unique across them, a link
## that must agree with another); empty when fine. The bake calls it with the whole type.
func validate_with(_all_of_type: Array[ContentDef]) -> Array[String]:
	return []


## What is wrong with it that the types cannot say, one human sentence each; empty when it is
## fine. The bake refuses content with any.
func validate() -> Array[String]:
	var out: Array[String] = []
	if id < 0:
		out.append("its id is negative")
	if display_name.strip_edges().is_empty():
		out.append("it has no display name")
	return out
